#!/usr/bin/env python3
"""Score AD-081 runs.  python3 -I eval/vocab-bias/score.py --work /tmp/airdraft-wave/vocab

Hypothesis = the pipeline's raw transcript (speech recognition output, before
dictionary post-processing), converted to Traditional Chinese with the ICU
transform ChineseScriptConverter uses (../mixed-asr/to_traditional.swift).
  term_exact  expected term occurrences found with exact spelling and case
  term_fold   the same, case-insensitive (what dictionary casing repair yields)
  final_exact the same as term_exact on the pipeline's final text
  TER         token error rate: Latin word runs and single Han characters,
              lowercase, punctuation removed (WER for English, MER for Chinese)
  false_terms dictionary terms (case-insensitive) in a hypothesis whose
              reference does not contain them
  silence     --e2e-expect-silence passes, plus any text produced without it
"""
import argparse, collections, json, pathlib, re, statistics, subprocess, tempfile, unicodedata

HERE = pathlib.Path(__file__).resolve().parent
HAN = r"㐀-䶿一-鿿豈-﫿"


def to_traditional(strings):
    binary = pathlib.Path(tempfile.gettempdir()) / "airdraft-ad081-to-traditional"
    if not binary.exists():
        subprocess.run(["xcrun", "swiftc", "-O", str(HERE.parent / "mixed-asr/to_traditional.swift"), "-o", str(binary)], check=True)
    out = subprocess.run([str(binary)], input=json.dumps(strings), capture_output=True, text=True, check=True)
    return json.loads(out.stdout)


def tokens(text):
    text = unicodedata.normalize("NFKC", text).lower().replace("'", "").replace("’", "")
    return re.findall(rf"[{HAN}]|[a-z0-9]+", text)


def distance(a, b):
    row = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        prev, row[0] = row[0], i
        for j, y in enumerate(b, 1):
            prev, row[j] = row[j], min(row[j] + 1, row[j - 1] + 1, prev + (x != y))
    return row[-1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--work", required=True, type=pathlib.Path)
    parser.add_argument("--out", type=pathlib.Path)
    args = parser.parse_args()
    corpus = json.loads((HERE / "corpus.json").read_text())
    items = {i["id"]: i for i in corpus["items"]}
    runs = [json.loads(p.read_text()) | {"label": p.parent.name} for p in sorted((args.work / "runs").glob("*/*.json"))]
    raws = to_traditional([r.get("raw") or "" for r in runs])
    for run, raw in zip(runs, raws):
        run["hyp"] = raw
    summary = {}
    for label in sorted({r["label"] for r in runs}):
        group = [r for r in runs if r["label"] == label]
        row = collections.defaultdict(float)
        detail = []
        lat = []
        for r in group:
            if r["id"].startswith("sil"):
                if r["expectSilence"]:
                    row["silence_runs"] += 1
                    row["silence_pass"] += r["status"] == "passed"
                else:
                    row["silence_text"] += bool((r.get("raw") or "").strip())
                    if (r.get("raw") or "").strip():
                        detail.append({"id": r["id"], "silence_text": r["raw"]})
                continue
            item = items[r["id"]]
            lang = item["language"]
            if r["status"] != "passed":
                row[f"{lang}_failed"] += 1
                detail.append({"id": r["id"], "error": r.get("error")})
                continue
            ref, hyp = tokens(item["text"]), tokens(r["hyp"])
            row[f"{lang}_edits"] += distance(ref, hyp)
            row[f"{lang}_reftok"] += len(ref)
            final = to_traditional([r.get("final") or ""])[0] if any(ord(c) > 0x2E80 for c in r.get("final") or "") else (r.get("final") or "")
            for term in item["terms"]:
                row[f"{lang}_terms"] += 1
                row[f"{lang}_term_exact"] += term in r["hyp"]
                row[f"{lang}_term_fold"] += term.casefold() in r["hyp"].casefold()
                row[f"{lang}_final_exact"] += term in final
            for term in corpus["dictionary"] + r.get("dictionary", []):
                if term.casefold() in r["hyp"].casefold() and term.casefold() not in item["text"].casefold():
                    row["false_terms"] += 1
                    detail.append({"id": r["id"], "false_term": term, "hyp": r["hyp"]})
            if r.get("asrMs") is not None:
                lat.append(r["asrMs"])
            detail.append({"id": r["id"], "hyp": r["hyp"]})
        out = {}
        for lang in ("en", "zh"):
            if row[f"{lang}_reftok"]:
                out[lang] = {
                    "TER": round(row[f"{lang}_edits"] / row[f"{lang}_reftok"], 4),
                    "term_exact": f"{int(row[f'{lang}_term_exact'])}/{int(row[f'{lang}_terms'])}",
                    "term_fold": f"{int(row[f'{lang}_term_fold'])}/{int(row[f'{lang}_terms'])}",
                    "final_exact": f"{int(row[f'{lang}_final_exact'])}/{int(row[f'{lang}_terms'])}",
                    "failed": int(row[f"{lang}_failed"]),
                }
        out["false_terms"] = int(row["false_terms"])
        out["silence_pass"] = f"{int(row['silence_pass'])}/{int(row['silence_runs'])}"
        out["silence_text"] = int(row["silence_text"])
        out["asrMs_median"] = statistics.median(lat) if lat else None
        out["detail"] = detail
        summary[label] = out
    text = json.dumps(summary, ensure_ascii=False, indent=1)
    (args.out or args.work / "score.json").write_text(text)
    for label, out in summary.items():
        print(label, {k: v for k, v in out.items() if k != "detail"})


if __name__ == "__main__":
    main()
