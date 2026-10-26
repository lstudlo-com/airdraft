#!/usr/bin/env python3
"""Gate 2: do dictation errors change the AI's answer? (local LLM only)

    python3 -B eval/speed/compare_answers.py eval/speed/private/<date>/manifest.jsonl --model <id>
        [--base-url http://127.0.0.1:1234/v1] [--out DIR] [--limit N] [--fresh]

Rows: labeled items going to AI destinations (History family code/terminal, or
a ChatGPT/Claude desktop or code/terminal bundle ID) whose reference differs
from the final text after whitespace normalisation. For each, the final text
and the reference are sent as separate prompts to a local OpenAI-compatible
server (LM Studio), then the same model judges whether the two answers are
equivalent for the intended request (strict JSON verdict).

Writes into the manifest's folder (inside eval/speed/private/ unless --out):
  compare-verdicts.jsonl  per-row verdicts and answers (resumable; --fresh redoes)
  compare-sample.jsonl    seeded 20% sample for manual checking
  compare-summary.json    counts, rate, Clopper-Pearson bounds, gate 2 status
Gate 2: share of rows whose answer changes <= 25% (pass when the one-sided 95%
upper bound is <= 25%; provisional when only the point estimate is).
Non-loopback hosts are refused unless --allow-remote. Proxies are bypassed.
"""
import argparse, ipaddress, json, math, pathlib, random, re, socket, sys, time, urllib.error, urllib.parse, urllib.request

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import speedlib as S  # noqa: E402

GATE2_LIMIT = 0.25
BACKOFF_SECONDS = 1.0
ANSWER_SYSTEM = "You are a helpful assistant. Answer the user's message."
JUDGE_SYSTEM = (
    "You compare two answers given to versions of the same request. Reply with JSON only, exactly "
    '{"equivalent": true or false, "reason": "<one short sentence>"}. '
    "equivalent is true when a user who meant the intended request would be equally well served by "
    "either answer: the same facts, actions, code, commands and conclusions. Ignore differences in "
    "wording, order, formatting and length."
)
THINK = re.compile(r"<think>.*?</think>", re.S)


class RequestFailed(Exception):
    pass


def is_loopback_url(url):
    host = urllib.parse.urlparse(url).hostname
    if not host:
        return False
    if host.lower() == "localhost":
        return True
    try:
        return ipaddress.ip_address(host).is_loopback
    except ValueError:
        return False


def judge_prompt(reference, answer_final, answer_reference):
    return (f"Intended request:\n<<<\n{reference}\n>>>\n\n"
            f"Answer A (to a transcription of the request that may contain errors):\n<<<\n{answer_final}\n>>>\n\n"
            f"Answer B (to the intended request):\n<<<\n{answer_reference}\n>>>\n\n"
            "Are A and B equivalent for the intended request? Reply with the JSON object only.")


def parse_verdict(text):
    text = THINK.sub("", text or "")
    decoder = json.JSONDecoder()
    for match in re.finditer(r"\{", text):
        try:
            value, _ = decoder.raw_decode(text[match.start():])
        except ValueError:
            continue
        if isinstance(value, dict) and isinstance(value.get("equivalent"), bool):
            return {"equivalent": value["equivalent"], "reason": str(value.get("reason", ""))[:500]}
    return None


class Client:
    def __init__(self, base_url, model, timeout=120.0, retries=2, max_tokens=2048, temperature=0.0):
        self.url = base_url.rstrip("/") + "/chat/completions"
        self.model, self.timeout, self.retries = model, timeout, retries
        self.max_tokens, self.temperature = max_tokens, temperature
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

    def chat(self, system, user):
        body = json.dumps({"model": self.model, "temperature": self.temperature, "max_tokens": self.max_tokens,
                           "messages": [{"role": "system", "content": system},
                                        {"role": "user", "content": user}]}).encode()
        last = None
        for attempt in range(self.retries + 1):
            if attempt:
                time.sleep(min(BACKOFF_SECONDS * 2 ** (attempt - 1), 30))
            request = urllib.request.Request(self.url, data=body, headers={"Content-Type": "application/json"})
            try:
                with self.opener.open(request, timeout=self.timeout) as response:
                    payload = json.load(response)
                return payload["choices"][0]["message"]["content"] or ""
            except urllib.error.HTTPError as error:
                last = f"HTTP {error.code}"
                if error.code < 500 and error.code != 429:
                    break
            except (urllib.error.URLError, socket.timeout, TimeoutError, ConnectionError) as error:
                last = type(error).__name__
            except (ValueError, KeyError, IndexError, TypeError):
                last = "malformed response"
        raise RequestFailed(last or "request failed")


def select_rows(items):
    rows = []
    for item in items:
        reference = item.get("reference") or ""
        if not reference.strip() or not S.is_ai_destination_row(item):
            continue
        if S.normalize_ws(reference) != S.normalize_ws(item.get("finalText")):
            rows.append(item)
    return rows


def compare_row(client, item, judge_attempts=3):
    final, reference = item.get("finalText") or "", item["reference"]
    record = {"id": item["id"], "family": item.get("family"), "appBundleId": item.get("appBundleId"),
              "model": client.model, "equivalent": None, "changesAIAnswer": None, "reason": None,
              "finalAnswer": None, "referenceAnswer": None, "error": None}
    try:
        record["finalAnswer"] = client.chat(ANSWER_SYSTEM, final)
        record["referenceAnswer"] = client.chat(ANSWER_SYSTEM, reference)
        prompt = judge_prompt(reference, THINK.sub("", record["finalAnswer"]).strip(),
                              THINK.sub("", record["referenceAnswer"]).strip())
        for _ in range(judge_attempts):
            verdict = parse_verdict(client.chat(JUDGE_SYSTEM, prompt))
            if verdict:
                record.update(verdict, changesAIAnswer=not verdict["equivalent"])
                return record
        record["error"] = "unparsed verdict"
    except RequestFailed as error:
        record["error"] = str(error)
    return record


def gate2_status(changes, n):
    if n == 0:
        return "no data"
    if changes / n > GATE2_LIMIT:
        return "fail"
    return "pass" if S.cp_upper(changes, n) <= GATE2_LIMIT else "provisional pass (upper95 above 25%)"


def summarize(items, verdicts, model, sample_share, seed):
    judged = [v for v in verdicts if v.get("error") is None and v.get("changesAIAnswer") is not None]
    changes = sum(1 for v in judged if v["changesAIAnswer"])
    n = len(judged)
    lo, hi = S.cp_interval(changes, n)
    ai_labeled = [i for i in items if (i.get("reference") or "").strip() and S.is_ai_destination_row(i)]
    by_id = {str(i["id"]): i for i in items}
    human = [(v["changesAIAnswer"], by_id[str(v["id"])].get("changesAIAnswer")) for v in judged
             if by_id.get(str(v["id"]), {}).get("changesAIAnswer") is not None]
    sample_size = math.ceil(sample_share * n) if n else 0
    sample_ids = sorted((v["id"] for v in random.Random(seed).sample(judged, sample_size)), key=str)
    return {
        "model": model,
        "rowsWithDifferences": len(verdicts), "judged": n, "changesAIAnswer": changes,
        "errors": sum(1 for v in verdicts if v.get("error")),
        "rate": S.rate(changes, n), "ci95": [lo, hi], "upper95": S.cp_upper(changes, n) if n else None,
        "aiLabeledRows": len(ai_labeled), "rateAmongAllAILabeled": S.rate(changes, len(ai_labeled)),
        "humanAgreement": {"n": len(human), "agree": sum(1 for a, b in human if a == b)} if human else None,
        "sample": {"seed": seed, "share": sample_share, "ids": sample_ids},
        "gate2": {"rule": "errors that change the AI answer <= 25%", "status": gate2_status(changes, n)},
    }


def run(manifest, client, out_dir, limit=None, fresh=False, sample_share=0.2, seed=104, log=print):
    manifest = pathlib.Path(manifest)
    items = S.read_jsonl(manifest)
    rows = select_rows(items)
    if limit:
        rows = rows[:limit]
    out_dir = pathlib.Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    verdict_path = out_dir / "compare-verdicts.jsonl"
    previous = {}
    if verdict_path.exists() and not fresh:
        previous = {str(v["id"]): v for v in S.read_jsonl(verdict_path)
                    if v.get("model") == client.model and v.get("error") is None}
    verdicts = []
    for position, item in enumerate(rows, 1):
        cached = previous.get(str(item["id"]))
        if cached:
            verdicts.append(cached)
            continue
        record = compare_row(client, item)
        verdicts.append(record)
        log(f"[{position}/{len(rows)}] #{item['id']} "
            + (f"error: {record['error']}" if record["error"] else
               ("changes answer" if record["changesAIAnswer"] else "equivalent")))
        previous[str(item["id"])] = record
        S.write_jsonl(verdict_path, previous.values())  # progress survives an interruption
    S.write_jsonl(verdict_path, verdicts)
    summary = summarize(items, verdicts, client.model, sample_share, seed)
    by_id = {str(i["id"]): i for i in items}
    sample = []
    for v in verdicts:
        if v["id"] in summary["sample"]["ids"]:
            item = by_id[str(v["id"])]
            sample.append(dict(v, finalText=item.get("finalText"), reference=item.get("reference"),
                               manualChangesAIAnswer=None))
    S.write_jsonl(out_dir / "compare-sample.jsonl", sample)
    S.write_json(out_dir / "compare-summary.json", summary)
    return summary


def render_text(summary):
    lo, hi = summary["ci95"]
    lines = [f"Model {summary['model']}",
             f"Rows with differences {summary['rowsWithDifferences']}, judged {summary['judged']}, "
             f"errors {summary['errors']}",
             f"Changes AI answer  {summary['changesAIAnswer']}/{summary['judged']}  {S.pct(summary['rate'])}  "
             f"95% CI {S.pct(lo)}..{S.pct(hi)}  upper95 {S.pct(summary['upper95'])}",
             f"Among all labeled AI rows ({summary['aiLabeledRows']}): {S.pct(summary['rateAmongAllAILabeled'])}"]
    if summary["humanAgreement"]:
        h = summary["humanAgreement"]
        lines.append(f"Agreement with manual labels: {h['agree']}/{h['n']}")
    lines.append(f"Manual-check sample: {len(summary['sample']['ids'])} rows (seed {summary['sample']['seed']})")
    lines.append(f"Gate 2 (<= 25%): {summary['gate2']['status']}")
    return "\n".join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0],
                                     formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__)
    parser.add_argument("manifest", help="labeled manifest.jsonl")
    parser.add_argument("--model", required=True, help="model identifier loaded in the local server")
    parser.add_argument("--base-url", default="http://127.0.0.1:1234/v1", help="OpenAI-compatible base URL (default: %(default)s)")
    parser.add_argument("--allow-remote", action="store_true", help="permit a non-loopback host (sends transcripts off this Mac)")
    parser.add_argument("--out", help="output folder (default: the manifest's folder, which must be inside eval/speed/private/)")
    parser.add_argument("--limit", type=int, help="compare at most N rows")
    parser.add_argument("--fresh", action="store_true", help="ignore earlier verdicts")
    parser.add_argument("--timeout", type=float, default=120.0, help="seconds per request (default: %(default)s)")
    parser.add_argument("--retries", type=int, default=2, help="retries per request (default: %(default)s)")
    parser.add_argument("--max-tokens", type=int, default=2048, help="max output tokens (default: %(default)s)")
    parser.add_argument("--sample-share", type=float, default=0.2, help="manual-check share (default: %(default)s)")
    parser.add_argument("--seed", type=int, default=104, help="sample seed (default: %(default)s)")
    parser.add_argument("--json", action="store_true", help="print the summary as JSON")
    args = parser.parse_args(argv)
    if not is_loopback_url(args.base_url) and not args.allow_remote:
        parser.error(f"{args.base_url} is not a loopback address; pass --allow-remote to send transcripts there")
    if not 0 <= args.retries <= 5:
        parser.error("--retries must be between 0 and 5")
    if args.out:
        out_dir = pathlib.Path(args.out).expanduser()
    else:
        out_dir = pathlib.Path(args.manifest).resolve().parent
        if not S.inside(out_dir, S.PRIVATE_DIR):
            parser.error("the manifest is outside eval/speed/private/; pass --out explicitly")
    client = Client(args.base_url, args.model, timeout=args.timeout, retries=args.retries, max_tokens=args.max_tokens)
    summary = run(args.manifest, client, out_dir, limit=args.limit, fresh=args.fresh,
                  sample_share=args.sample_share, seed=args.seed, log=lambda m: print(m, file=sys.stderr))
    print(json.dumps(summary, indent=2) if args.json else render_text(summary))
    return 0


if __name__ == "__main__":
    sys.exit(main())
