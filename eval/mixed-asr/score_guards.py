#!/usr/bin/env python3
"""Score AD-082 guard runs (run_guards.py) against a baseline tag.

  python3 -I eval/mixed-asr/score_guards.py --work <dir> --tags before,after [--out results/guards.json]

Uses score.py's normalization (ICU Hans-Hant, NFKC, case-insensitive tokens) for
MER and English retention. Additional measures, per configuration and corpus:
  empty      runs that delivered nothing (pipeline idle or failed)
  loop       finals containing a block repeated in a row (period <= 10 tokens;
             8x for one token, 6x for two, otherwise >= 4x and >= 12 tokens)
  wrongScript finals with >= 30% letters in a script a zh/en user does not write
             (anything but Latin and Han)
  zhLost     ASCEND finals keeping < 30% of the reference's Han characters
  allCaps    finals whose English words (>= 2 letters) are all in capitals
  punctuated finals containing any punctuation mark
  caseExact  share of reference English words found with the same case (TTS sets)
  languageRetried  runs whose guard log records an applied language retry
  probeMax   highest spoken-language probability the guard's probe logged, per language

AD-098 corpora from intl-control.json (intl-ru, intl-hi, intl-ar, en-in-control) add:
  WERintl    word error rate over whitespace words after NFKC, lowercasing and removing
             punctuation and Arabic diacritics (score.py's tokenizer keeps only Han and Latin)
  scriptLost finals with < 30% of their letters in the reference language's script
             (a translation or transliteration)
"""
import argparse, collections, json, pathlib, re, statistics, sys, unicodedata

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from score import HAN, distance, is_han, is_latin, retained, to_traditional, tokenize  # noqa: E402

PUNCT = re.compile(r"[，。？！、；：,.?!;:…]")


def units(text):
    return [t.lower() for t in re.findall(rf"[{HAN}぀-ヿ가-힯]|[^\W_]+", text)]


def has_loop(text):
    u = units(text)
    for period in range(1, 11):
        need = 8 if period == 1 else 6 if period == 2 else max(4, -(-12 // period))
        run = 0
        for i in range(len(u) - period):
            run = run + 1 if u[i] == u[i + period] else 0
            if (run + period) // period >= need:
                return True
    return False


def wrong_script(text):
    letters = [c for c in text if c.isalpha()]
    if not letters:
        return False
    odd = [c for c in letters if not (re.match(rf"[{HAN}]", c) or re.match(r"[A-Za-zÀ-ɏ]", c))]
    return len(odd) / len(letters) >= 0.3


def all_caps(text):
    words = re.findall(r"[A-Za-z]{2,}", text)
    return bool(words) and all(w.isupper() for w in words)


SCRIPTS = {"ru": r"[\u0400-\u04FF]", "hi": r"[\u0900-\u097F]", "ar": r"[\u0600-\u06FF]"}


def words(text):
    text = unicodedata.normalize("NFKC", text).lower()
    text = re.sub(r"[\u064B-\u0652\u0670]", "", text)  # Arabic diacritics
    text = "".join(" " if unicodedata.category(c).startswith(("P", "S")) else c for c in text)
    return text.split()


def script_lost(text, language):
    letters = [c for c in text if c.isalpha() or unicodedata.category(c) in ("Mn", "Mc")]
    if not letters:
        return True
    native = [c for c in letters if re.match(SCRIPTS[language], c)]
    return len(native) / len(letters) < 0.3


def guard_events(run):
    probes, retried = [], False
    for line in run.get("guard_log") or []:
        if m := re.search(r"probe=(\S+) probability=([0-9.e-]+)", line):
            probes.append((m.group(1), float(m.group(2))))
        if "action=languageRetried applied=true" in line:
            retried = True
    return probes, retried


def load(work, tag):
    runs = []
    for path in sorted((work / f"runs-{tag}").glob("*/*.json")):
        runs.append(json.loads(path.read_text()))
    return runs


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--work", required=True, type=pathlib.Path)
    parser.add_argument("--tags", default="before,after")
    parser.add_argument("--out", type=pathlib.Path)
    args = parser.parse_args()
    items = {i["id"]: i for i in json.loads((HERE / "manifest.json").read_text())["items"]}
    for name in ("en-control.json", "intl-control.json"):
        control = args.work / name
        if control.exists():
            items.update({i["id"]: i for i in json.loads(control.read_text())})
    report = {}
    for tag in args.tags.split(","):
        runs = load(args.work, tag)
        texts = [items[r["id"]]["reference"] for r in runs] + [r.get("final") or "" for r in runs]
        converted = to_traditional(texts)
        groups = collections.defaultdict(list)
        n = len(runs)
        for index, run in enumerate(runs):
            ref_text, hyp_text = converted[index], converted[n + index]
            final = run.get("final") or ""
            ref, hyp = tokenize(ref_text), tokenize(hyp_text)
            ref_lat = [t for t in ref if is_latin(t)]
            ref_han = [t for t in ref if is_han(t)]
            exact_ref = [t for t in tokenize(items[run["id"]]["reference"], keep_case=True) if is_latin(t)]
            exact_hyp = [t for t in tokenize(final, keep_case=True) if is_latin(t)]
            probes, retried = guard_events(run)
            language = items[run["id"]].get("language")
            intl = {}
            if language in SCRIPTS:
                ref_words = words(items[run["id"]]["reference"])
                intl = {"werErr": distance(ref_words, words(final)), "werRef": len(ref_words),
                        "scriptLost": script_lost(final, language)}
            groups[(f"{run['model']} {run['language']}", run["corpus"])].append({
                "probes": probes, "retried": retried, **intl,
                "id": run["id"], "rep": run.get("rep", 0), "empty": not final, "err": distance(ref, hyp), "ref": len(ref),
                "lat": len(ref_lat), "kept": retained(ref_lat, [t for t in hyp if is_latin(t)]),
                "exact": retained(exact_ref, exact_hyp), "loop": has_loop(final), "wrong": wrong_script(final),
                "zhLost": bool(ref_han) and retained(ref_han, [t for t in hyp if is_han(t)]) < 0.3 * len(ref_han),
                "caps": all_caps(final), "punct": bool(PUNCT.search(final)), "asrMs": run.get("asrMs"),
                "peak": run.get("peak_footprint"), "final": final,
            })
        table = {}
        for (config, corpus), rows in sorted(groups.items()):
            ms = [r["asrMs"] for r in rows if r["asrMs"] is not None]
            lat = sum(r["lat"] for r in rows)
            table[f"{config} | {corpus}"] = {
                "runs": len(rows), "empty": sum(r["empty"] for r in rows), "loop": sum(r["loop"] for r in rows),
                "wrongScript": sum(r["wrong"] for r in rows),
                "zhLost": sum(r["zhLost"] for r in rows) if corpus == "ascend" else None,
                "allCaps": sum(r["caps"] for r in rows), "punctuated": sum(r["punct"] for r in rows),
                "MER": round(sum(r["err"] for r in rows) / max(1, sum(r["ref"] for r in rows)), 4),
                "ENkeep": round(sum(r["kept"] for r in rows) / lat, 4) if lat else None,
                "caseExact": round(sum(r["exact"] for r in rows) / lat, 4) if lat and corpus != "ascend" else None,
                "asrMsMedian": statistics.median(ms) if ms else None, "asrMsMax": max(ms) if ms else None,
                "peakMaxMB": round(max((r["peak"] or 0) for r in rows) / 1e6) if rows else None,
                "languageRetried": sum(r["retried"] for r in rows),
                "probeMax": {code: round(max(p for c, p in probes if c == code), 4)
                             for probes in [[x for r in rows for x in r["probes"]]] for code in sorted({c for c, _ in probes})},
                "WERintl": round(sum(r["werErr"] for r in rows) / max(1, sum(r["werRef"] for r in rows)), 4)
                           if rows and "werErr" in rows[0] else None,
                "scriptLost": sum(r["scriptLost"] for r in rows) if rows and "scriptLost" in rows[0] else None,
                "flagged": [{"id": r["id"], "rep": r["rep"], "final": r["final"][:120]} for r in rows
                            if r["loop"] or (r["wrong"] and "scriptLost" not in r) or r["empty"] or r["retried"]
                            or r.get("scriptLost") or (r["zhLost"] and corpus == "ascend")],
            }
        report[tag] = table
    text = json.dumps(report, ensure_ascii=False, indent=1)
    if args.out:
        args.out.write_text(text + "\n")
    for tag, table in report.items():
        print(f"== {tag}")
        for key, value in table.items():
            print(key, {k: v for k, v in value.items() if k != "flagged"})


if __name__ == "__main__":
    main()
