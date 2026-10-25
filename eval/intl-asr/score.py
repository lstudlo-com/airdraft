#!/usr/bin/env python3
"""Score AD-098 runs.  python3 -I eval/intl-asr/score.py --work dist/intl-asr-work

Normalization (identical for the reference and the hypothesis), eval/eja-asr's
rule plus two script-specific steps:
 1. Unicode NFKC, then lowercase.
 2. Arabic: tashkeel (U+064B-U+065F), superscript alef (U+0670) and tatweel
    (U+0640) are removed. Hindi: NFKC already decomposes the precomposed nukta
    letters (U+0958-U+095F are composition exclusions); the nukta sign (U+093C)
    is then removed, so क़/क and ज़/ज compare equal. Nothing else is folded
    (no alef/hamza or chandrabindu/anusvara unification).
 3. Apostrophes are dropped (l'homme -> lhomme); every other character in a
    Unicode punctuation (P*) or symbol (S*) category becomes a space (this
    includes the danda and the Arabic comma).
 4. Tokens are whitespace-separated words -> WER for all seven languages.
Numbers are not converted (25 vs veinticinco). `error_clean` repeats the score on
utterances whose reference has no digit and no bracket. `truncated` counts
outputs with fewer than 70% of the reference's words.

`final` is the pipeline's output as saved to history; `raw` is the speech
engine's text after Airdraft's output guards, before the dictionary. For these
languages the two are equal unless a guard or post-processor changed the text.

Error rate = sum of edit distances / sum of reference tokens over the set.
95% CIs: 2000 bootstrap resamples of utterances (seed 98). Paired deltas
resample the same utterances for both systems. A failed or empty run counts as
a full deletion.

Real-time factor (RTF) = asrMs / audio duration, median over utterances (lower
is faster; asrMs includes the factory lease wait and preparation after
--e2e-prepare loaded the model). Memory class from the p95 peak footprint:
light < 1 GB, medium 1-2 GB, large 2-4 GB, very large >= 4 GB. Core ML (Whisper,
Parakeet) memory partly lives outside the process, so its class is a lower bound.
"""
import argparse, collections, csv, json, pathlib, random, re, statistics, unicodedata

HERE = pathlib.Path(__file__).resolve().parent
SEED = 98
# Paired comparisons behind the AD-098 decision, as (language, first, second);
# the delta is second minus first on model output (raw), all and clean utterances.
# Every configuration is also compared with Qwen3-ASR 1.7B Auto and Whisper
# Large v3 Turbo Auto in `paired_vs_reference`.
PAIRS = [
    *[(lang, ("qwen3:1.7b", "auto"), ("whisper:turbo", "auto")) for lang in ["es", "fr", "pt", "ru", "ar", "hi", "id"]],
    *[(lang, ("qwen3:1.7b", lang), ("qwen3:1.7b", "auto")) for lang in ["es", "fr", "pt", "ru", "ar", "hi", "id"]],
    *[(lang, ("whisper:turbo", "auto"), ("whisper:large-v3", "auto")) for lang in ["es", "fr", "pt", "ru", "ar", "hi", "id"]],
    *[(lang, ("whisper:turbo", "auto"), ("coreml:parakeet-v3", "auto")) for lang in ["es", "fr", "pt", "ru"]],
    *[(lang, ("qwen3:1.7b", "auto"), ("coreml:parakeet-v3", "auto")) for lang in ["es", "fr", "pt", "ru"]],
    *[(lang, ("qwen3:1.7b", "auto"), ("gguf:canary-1b-v2", lang)) for lang in ["es", "fr", "pt", "ru"]],
    *[(lang, ("qwen3:1.7b", "auto"), ("gguf:voxtral-mini-4b-realtime-2602", "auto")) for lang in ["es", "fr", "pt", "ru", "ar", "hi"]],
    *[(lang, ("qwen3:1.7b", "auto"), ("gguf:granite-speech-4.1-2b", lang)) for lang in ["es", "fr", "pt"]],
    ("ru", ("qwen3:1.7b", "auto"), ("gguf:gigaam-v3-e2e-rnnt", "auto")),
    ("ru", ("gguf:gigaam-v3-e2e-rnnt", "auto"), ("coreml:parakeet-v3", "auto")),
    ("ru", ("gguf:gigaam-v3-e2e-rnnt", "auto"), ("gguf:gigaam-v3-ctc", "auto")),
    ("ru", ("gguf:gigaam-v3-e2e-rnnt", "auto"), ("whisper:turbo", "auto")),
    ("ar", ("qwen3:1.7b", "auto"), ("gguf:cohere-transcribe-arabic-07-2026", "ar")),
    ("ar", ("qwen3:1.7b", "ar"), ("gguf:cohere-transcribe-arabic-07-2026", "ar")),
    ("ar", ("whisper:turbo", "auto"), ("gguf:moonshine-base-ar", "auto")),
    ("id", ("whisper:turbo", "auto"), ("gguf:fun-asr-mlt-nano-2512", "auto")),
]
REFERENCES = [("qwen3:1.7b", "auto"), ("whisper:turbo", "auto")]
ARABIC_MARKS = re.compile("[\u064B-\u065F\u0670\u0640]")
SCRIPTS = {"ru": "[\u0400-\u04FF]", "ar": "[\u0600-\u06FF\u0750-\u077F]", "hi": "[\u0900-\u097F]"}


def clean(text, language):
    text = unicodedata.normalize("NFKC", text).lower()
    if language == "ar":
        text = ARABIC_MARKS.sub("", text)
    if language == "hi":
        text = text.replace("\u093C", "")
    text = text.replace("'", "").replace("\u2019", "").replace("\u02BC", "")
    return "".join(" " if unicodedata.category(c)[0] in "PS" else c for c in text)


def tokens(text, language):
    return clean(text, language).split()


def distance(a, b):
    previous = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        current = [i]
        for j, y in enumerate(b, 1):
            current.append(min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (x != y)))
        previous = current
    return previous[-1]


def percentile(values, q):
    values = sorted(values)
    return values[min(len(values) - 1, int(round(q * (len(values) - 1))))]


def rate(rows, err="err"):
    ref = sum(r["ref"] for r in rows)
    return sum(r[err] for r in rows) / ref if ref else 0.0


def bootstrap(rows, err="err", n=2000, seed=SEED):
    rng = random.Random(seed)
    stats = [rate([rows[rng.randrange(len(rows))] for _ in rows], err) for _ in range(n)]
    return [round(percentile(stats, 0.025), 4), round(percentile(stats, 0.975), 4)]


def paired(base, other, err="err_raw", n=2000, seed=SEED):
    rng = random.Random(seed)
    pairs = list(zip(base, other))
    def delta(sample):
        ref = sum(a["ref"] for a, _ in sample)
        return (sum(b[err] for _, b in sample) - sum(a[err] for a, _ in sample)) / ref if ref else 0.0
    stats = [delta([pairs[rng.randrange(len(pairs))] for _ in pairs]) for _ in range(n)]
    return round(delta(pairs), 4), [round(percentile(stats, 0.025), 4), round(percentile(stats, 0.975), 4)]


def script_ok(text, language):
    """The output is written in the expected script at all."""
    letters = [c for c in text if c.isalpha()]
    if not letters:
        return False
    if language in SCRIPTS:
        return sum(bool(re.match(SCRIPTS[language], c)) for c in letters) >= 0.7 * len(letters)
    return sum(c.isascii() or unicodedata.name(c, "").startswith("LATIN") for c in letters) >= 0.9 * len(letters)


def memory_class(mb):
    if mb is None:
        return None
    return "light" if mb < 1024 else "medium" if mb < 2048 else "large" if mb < 4096 else "very large"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--work", required=True, type=pathlib.Path)
    args = parser.parse_args()
    items = {i["id"]: i for i in json.loads((HERE / "manifest.json").read_text())["items"]}
    runs = [json.loads(p.read_text()) for p in sorted((args.work / "runs").glob("*/*/*.json"))]
    rows = []
    for run in runs:
        item = items[run["id"]]
        lang = item["language"]
        ok = run["status"] == "passed"
        ref = tokens(item["reference"], lang)
        row = {"id": run["id"], "lang": lang, "model": run["model"], "setting": run["language"],
               "status": run["status"], "duration": item["duration"], "ref": len(ref),
               "clean": not re.search(r"[\d()（）\[\]]", item["reference"]),
               "asrMs": run.get("asrMs"), "processingMs": run.get("processingMs"),
               "peak_footprint": run.get("peak_footprint"), "loadavg1": run.get("loadavg1"), "wall_s": run.get("wall_s"),
               "final": run.get("final") or "", "raw": run.get("raw") or "", "reference": item["reference"]}
        for key in ("final", "raw"):
            hyp = tokens(row[key], lang) if ok else []
            row["err" if key == "final" else "err_raw"] = distance(ref, hyp)
        row["truncated"] = len(tokens(row["raw"], lang) if ok else []) < 0.7 * len(ref)
        row["empty"] = not ok or not row["final"].strip()
        row["wrong_script"] = ok and bool(row["raw"].strip()) and not script_ok(row["raw"], lang)
        rows.append(row)

    groups = collections.defaultdict(list)
    for row in rows:
        groups[(row["lang"], row["model"], row["setting"])].append(row)
    summary = []
    for (lang, model, setting), group in sorted(groups.items()):
        group.sort(key=lambda r: r["id"])
        ok = [r for r in group if r["status"] == "passed"]
        asr = [r["asrMs"] for r in ok if r["asrMs"] is not None]
        proc = [r["processingMs"] for r in ok if r["processingMs"] is not None]
        mem = [r["peak_footprint"] / 2**20 for r in ok if r["peak_footprint"]]
        clean_rows = [r for r in group if r["clean"]]
        rtf = [r["asrMs"] / 1000 / r["duration"] for r in ok if r["asrMs"] is not None]
        summary.append({
            "lang": lang, "model": model, "setting": setting, "utterances": len(group),
            "failures": len(group) - len(ok), "empty": sum(r["empty"] for r in group),
            "wrong_script": sum(r["wrong_script"] for r in group), "truncated": sum(r["truncated"] for r in group),
            "metric": "WER",
            "error": round(rate(group), 4), "error_ci95": bootstrap(group),
            "error_raw": round(rate(group, "err_raw"), 4), "error_raw_ci95": bootstrap(group, "err_raw"),
            "error_clean": round(rate(clean_rows, "err_raw"), 4) if clean_rows else None,
            "error_clean_ci95": bootstrap(clean_rows, "err_raw") if clean_rows else None,
            "clean_utterances": len(clean_rows),
            "asr_ms_median": round(statistics.median(asr)) if asr else None,
            "asr_ms_p90": round(percentile(asr, 0.9)) if asr else None,
            "processing_ms_median": round(statistics.median(proc)) if proc else None,
            "rtf_median": round(statistics.median(rtf), 4) if rtf else None,
            "rtf_p90": round(percentile(rtf, 0.9), 4) if rtf else None,
            "peak_mb_median": round(statistics.median(mem)) if mem else None,
            "peak_mb_p95": round(percentile(mem, 0.95)) if mem else None,
            "memory_class": memory_class(percentile(mem, 0.95) if mem else None),
            "loadavg1_median": round(statistics.median(r["loadavg1"] for r in group if r["loadavg1"] is not None), 1),
        })

    def pair(lang, first, second):
        a, b = groups.get((lang, *first)), groups.get((lang, *second))
        if not a or not b:
            return None
        a_by_id, b_by_id = {r["id"]: r for r in a}, {r["id"]: r for r in b}
        ids = sorted(set(a_by_id) & set(b_by_id))
        clean_ids = [i for i in ids if a_by_id[i]["clean"]]
        delta, ci = paired([a_by_id[i] for i in ids], [b_by_id[i] for i in ids])
        clean_delta, clean_ci = paired([a_by_id[i] for i in clean_ids], [b_by_id[i] for i in clean_ids])
        return {"lang": lang, "first": " ".join(first), "second": " ".join(second), "utterances": len(ids),
                "second_minus_first": delta, "ci95": ci, "clean_second_minus_first": clean_delta, "clean_ci95": clean_ci,
                "clean_utterances": len(clean_ids)}

    versus = [p for (lang, model, setting) in sorted(groups) for ref in REFERENCES
              if (model, setting) != ref and (p := pair(lang, ref, (model, setting)))]
    decision = [p for lang, first, second in PAIRS if (p := pair(lang, first, second))]

    results = HERE / "results"
    results.mkdir(parents=True, exist_ok=True)
    (results / "summary.json").write_text(json.dumps(
        {"summary": summary, "paired_vs_reference": versus, "decision_pairs": decision}, ensure_ascii=False, indent=1) + "\n")
    with open(results / "utterances.csv", "w", newline="") as f:
        fields = ["id", "lang", "model", "setting", "status", "duration", "ref", "err", "err_raw", "empty", "truncated",
                  "wrong_script", "asrMs", "processingMs", "peak_footprint", "final", "raw"]
        writer = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        for row in sorted(rows, key=lambda r: (r["lang"], r["id"], r["model"], r["setting"])):
            writer.writerow({**row, "final": row["final"][:400], "raw": row["raw"][:400]})
    for e in sorted(summary, key=lambda e: (e["lang"], e["error_raw"])):
        print(f"{e['lang']} {e['model']:40} {e['setting']:4} n={e['utterances']:2} WER {e['error_raw']:.3f} {e['error_raw_ci95']} "
              f"final {e['error']:.3f} clean {e['error_clean']} fail {e['failures']} trunc {e['truncated']} script {e['wrong_script']} "
              f"asr {e['asr_ms_median']}/{e['asr_ms_p90']} rtf {e['rtf_median']} mem {e['peak_mb_median']}/{e['peak_mb_p95']} {e['memory_class']}")
    for p in decision:
        print("pair", p["lang"], p["first"], "->", p["second"], p["second_minus_first"], p["ci95"], "clean", p["clean_second_minus_first"], p["clean_ci95"])


if __name__ == "__main__":
    main()
