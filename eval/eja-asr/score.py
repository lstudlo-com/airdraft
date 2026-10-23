#!/usr/bin/env python3
"""Score AD-083 runs.  python3 -I eval/eja-asr/score.py --work /tmp/airdraft-wave/ad083

Normalization (identical for the reference and the hypothesis):
 1. Unicode NFKC, then lowercase (full-width Latin and digits become ASCII).
 2. Apostrophes are dropped (don't -> dont); every other character in a Unicode
    punctuation (P*) or symbol (S*) category becomes a space.
 3. English: tokens are the remaining whitespace-separated words -> WER.
    Japanese and Korean: all whitespace is removed and every remaining character
    is a token -> CER. Spacing differs freely between Korean writers and
    Japanese has none, so it is not scored.
Numbers are not converted (25 vs twenty-five, 1967年 vs 千九百六十七年), and
Japanese kana/kanji variants of the same word count as errors. `error_clean`
repeats the score on utterances whose reference has no digit and no bracket:
FLEURS references often add unspoken glosses in brackets, such as
`선거위원회(CEP)` or `(Cristina Fernandez de Kirchner)` (16 of 60 Korean ones).
`truncated` counts outputs with fewer than 70% of the reference's tokens.

`final` is the pipeline's output as saved to history (what the user gets).
`raw` is the speech engine's text after Airdraft's output guards, before
ChineseScriptConverter and the dictionary. With the default Traditional script,
at 7f79be0 the converter rewrote Japanese kanji (国 -> 國); `raw` shows the
model itself. AD-083 skips the conversion for text with kana.

Error rate = sum of edit distances / sum of reference tokens over the set.
95% CIs: 2000 bootstrap resamples of utterances (seed 83). Paired deltas
resample the same utterances for both systems. A failed or empty run counts
as a full deletion.

`--followup` (2026-10-24) scores <work>/runs-followup (both manifests) into
results/followup-2026-10-24/. Cantonese (yue) and Mandarin (zh) are CER over
characters after ICU Hans-Hant on reference and hypothesis (eval/mixed-asr's
to_traditional.swift), because FLEURS Mandarin references are Simplified and
the app delivers Traditional by default. `--ad083 <work>` adds that study's
runs for the same utterances under "<model>@ad083" for before/after pairs.
"""
import argparse, collections, csv, json, pathlib, random, re, statistics, unicodedata

HERE = pathlib.Path(__file__).resolve().parent
BASELINE = ("sherpa:senseVoice", "auto")  # the 0.11.0 recommendation for en/ja/ko
# Paired comparisons behind the AD-083 decision: (language, first, second);
# the delta is second minus first on model output, all and clean utterances.
PAIRS = [
    ("en", ("coreml:parakeet-v2", "auto"), ("qwen3:1.7b", "auto")),
    ("en", ("coreml:parakeet-v2", "auto"), ("whisper:turbo", "auto")),
    ("ja", ("qwen3:1.7b", "auto"), ("qwen3:1.7b", "ja")),
    ("ja", ("qwen3:1.7b", "auto"), ("coreml:parakeet-ja", "auto")),
    ("ja", ("qwen3:1.7b", "auto"), ("whisper:turbo", "auto")),
    ("ja", ("qwen3:1.7b", "ja"), ("cohere", "ja")),
    ("ko", ("qwen3:1.7b", "auto"), ("qwen3:1.7b", "ko")),
    ("ko", ("qwen3:1.7b", "auto"), ("whisper:turbo", "auto")),
    ("ko", ("qwen3:1.7b", "ko"), ("whisper:turbo", "ko")),
    ("ko", ("qwen3:1.7b", "ko"), ("cohere", "ko")),
]
SV, SVM = "sherpa:senseVoice", "sherpa:senseVoiceMultilingual"
FOLLOWUP_PAIRS = [
    ("en", (SVM, "auto"), ("sherpa:senseVoice@2024@ad083", "auto")),
    ("ja", (SVM, "auto"), ("sherpa:senseVoice@2024@ad083", "auto")),
    ("ko", (SVM, "auto"), ("sherpa:senseVoice@2024@ad083", "auto")),
    ("en", (SVM, "auto"), ("sherpa:senseVoice@ad083", "auto")),
    ("ja", (SVM, "auto"), ("sherpa:senseVoice@ad083", "auto")),
    ("ko", (SVM, "auto"), ("sherpa:senseVoice@ad083", "auto")),
    ("ja", (SVM, "auto"), ("qwen3:1.7b@ad083", "auto")),
    ("ko", (SVM, "auto"), ("qwen3:1.7b@ad083", "auto")),
    ("ja", (SVM, "auto"), ("whisper:turbo@ad083", "auto")),
    ("ko", (SVM, "auto"), ("whisper:turbo@ad083", "auto")),
    ("ja", ("coreml:parakeet-ja@ad083", "auto"), ("coreml:parakeet-ja", "auto")),
    ("yue", (SV, "auto"), (SVM, "auto")),
    ("yue", (SV, "yue"), (SVM, "yue")),
    ("yue", (SVM, "auto"), ("qwen3:1.7b", "auto")),
    ("yue", (SVM, "yue"), ("qwen3:1.7b", "yue")),
    ("zh", (SV, "auto"), (SVM, "auto")),
    ("zh", (SV, "zh"), (SVM, "zh")),
    ("zh", (SVM, "auto"), ("qwen3:1.7b", "auto")),
    ("zh", (SVM, "zh"), ("qwen3:1.7b", "zh")),
]
AD083_MODELS = {"sherpa_senseVoice", "sherpa_senseVoice_2024", "qwen3_1.7b", "whisper_turbo", "coreml_parakeet-ja"}


def clean(text):
    text = unicodedata.normalize("NFKC", text).lower().replace("'", "").replace("’", "")
    return "".join(" " if unicodedata.category(c)[0] in "PS" else c for c in text)


def tokens(text, language):
    text = clean(text)
    return text.split() if language == "en" else [c for c in text if not c.isspace()]


def traditional(strings):
    """ICU Hans-Hant through eval/mixed-asr's helper (the app's converter transform)."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("mixed_score", HERE.parent / "mixed-asr" / "score.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.to_traditional(strings)


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


def bootstrap(rows, err="err", n=2000, seed=83):
    rng = random.Random(seed)
    stats = [rate([rows[rng.randrange(len(rows))] for _ in rows], err) for _ in range(n)]
    return [round(percentile(stats, 0.025), 4), round(percentile(stats, 0.975), 4)]


def paired(base, other, err="err", n=2000, seed=83):
    rng = random.Random(seed)
    pairs = list(zip(base, other))
    def delta(sample):
        ref = sum(a["ref"] for a, _ in sample)
        return (sum(b[err] for _, b in sample) - sum(a[err] for a, _ in sample)) / ref
    stats = [delta([pairs[rng.randrange(len(pairs))] for _ in pairs]) for _ in range(n)]
    return round(delta(pairs), 4), [round(percentile(stats, 0.025), 4), round(percentile(stats, 0.975), 4)]


def script_ok(text, language):
    """The output is written in the expected script at all."""
    if language == "ja":
        return re.search(r"[぀-ヿ]", text) is not None
    if language == "ko":
        return re.search(r"[가-힣]", text) is not None
    if language in ("yue", "zh"):
        return re.search(r"[一-鿿]", text) is not None
    letters = [c for c in text if c.isalpha()]
    return bool(letters) and sum(c.isascii() for c in letters) >= 0.9 * len(letters)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--work", required=True, type=pathlib.Path)
    parser.add_argument("--followup", action="store_true")
    parser.add_argument("--ad083", type=pathlib.Path, help="AD-083 work directory, for before/after pairs")
    args = parser.parse_args()
    items = {i["id"]: i for i in json.loads((HERE / "manifest.json").read_text())["items"]}
    if args.followup:
        items.update({i["id"]: i for i in json.loads((HERE / "manifest-chinese.json").read_text())["items"]})
    runs = [json.loads(p.read_text()) for p in sorted((args.work / ("runs-followup" if args.followup else "runs")).glob("*/*/*.json"))]
    if args.followup and args.ad083:
        for path in sorted((args.ad083 / "runs").glob("*/*/*.json")):
            if path.parent.name.rsplit("-", 1)[0] in AD083_MODELS:
                run = json.loads(path.read_text())
                run["model"] = run["model"] + "@ad083"
                runs.append(run)
    chinese = [r for r in runs if items[r["id"]]["language"] in ("yue", "zh")]
    if chinese:
        texts = [items[r["id"]]["reference"] for r in chinese] + [r.get("final") or "" for r in chinese] + [r.get("raw") or "" for r in chinese]
        converted, n = traditional(texts), len(chinese)
        for index, run in enumerate(chinese):
            run["reference_hant"], run["final_hant"], run["raw_hant"] = converted[index], converted[n + index], converted[2 * n + index]
    rows = []
    for run in runs:
        item = items[run["id"]]
        lang = item["language"]
        ok = run["status"] == "passed"
        ref = tokens(run.get("reference_hant", item["reference"]), lang)
        row = {"id": run["id"], "lang": lang, "model": run["model"], "setting": run["language"],
               "status": run["status"], "duration": item["duration"], "ref": len(ref),
               "digits": bool(re.search(r"\d", item["reference"])),
               "clean": not re.search(r"[\d()（）\[\]]", item["reference"]),
               "asrMs": run.get("asrMs"), "processingMs": run.get("processingMs"),
               "peak_footprint": run.get("peak_footprint"), "loadavg1": run.get("loadavg1"),
               "final": run.get("final") or "", "raw": run.get("raw") or "", "reference": item["reference"]}
        for key in ("final", "raw"):
            hyp = tokens(run.get(f"{key}_hant", row[key]), lang) if ok else []
            row["err" if key == "final" else "err_raw"] = distance(ref, hyp)
        # Lost speech: the output keeps less than 70% of the reference length
        # (a dropped sentence, or no text at all).
        row["truncated"] = len(tokens(run.get("raw_hant", row["raw"]), lang) if ok else []) < 0.7 * len(ref)
        row["empty"] = not ok or not row["final"].strip()
        row["wrong_script"] = ok and bool(row["raw"].strip()) and not script_ok(row["raw"], lang)
        row["converted"] = ok and row["raw"] != row["final"]
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
        no_digits = [r for r in group if not r["digits"]]
        clean_rows = [r for r in group if r["clean"]]
        entry = {
            "lang": lang, "model": model, "setting": setting, "utterances": len(group),
            "failures": len(group) - len(ok), "empty": sum(r["empty"] for r in group),
            "wrong_script": sum(r["wrong_script"] for r in group),
            "truncated": sum(r["truncated"] for r in group),
            "metric": "WER" if lang == "en" else "CER",
            "error": round(rate(group), 4), "error_ci95": bootstrap(group),
            "error_raw": round(rate(group, "err_raw"), 4), "error_raw_ci95": bootstrap(group, "err_raw"),
            "error_no_digits": round(rate(no_digits), 4) if no_digits else None,
            "no_digit_utterances": len(no_digits),
            "error_clean": round(rate(clean_rows, "err_raw"), 4) if clean_rows else None,
            "error_clean_ci95": bootstrap(clean_rows, "err_raw") if clean_rows else None,
            "clean_utterances": len(clean_rows),
            "converted_by_script": sum(r["converted"] for r in group),
            "asr_ms_median": round(statistics.median(asr)) if asr else None,
            "asr_ms_p90": round(percentile(asr, 0.9)) if asr else None,
            "processing_ms_median": round(statistics.median(proc)) if proc else None,
            "processing_ms_p90": round(percentile(proc, 0.9)) if proc else None,
            "rtf_median": round(statistics.median(r["asrMs"] / 1000 / r["duration"] for r in ok if r["asrMs"]), 4) if asr else None,
            "peak_mb_median": round(statistics.median(mem)) if mem else None,
            "peak_mb_p95": round(percentile(mem, 0.95)) if mem else None,
            "peak_mb_max": round(max(mem)) if mem else None,
            "loadavg1_median": round(statistics.median(r["loadavg1"] for r in group if r["loadavg1"] is not None), 1),
        }
        summary.append(entry)

    comparisons = []
    for (lang, model, setting), group in sorted(groups.items()):
        base = groups.get((lang, *BASELINE))
        if not base or (model, setting) == BASELINE:
            continue
        base_by_id = {r["id"]: r for r in base}
        common = [r for r in group if r["id"] in base_by_id]
        pairs_base = [base_by_id[r["id"]] for r in common]
        delta, ci = paired(pairs_base, common)
        delta_raw, ci_raw = paired(pairs_base, common, "err_raw")
        comparisons.append({"lang": lang, "model": model, "setting": setting, "vs": "sherpa:senseVoice auto",
                            "delta": delta, "delta_ci95": ci, "delta_raw": delta_raw, "delta_raw_ci95": ci_raw})

    # Auto vs the explicit language, per model.
    settings = []
    for (lang, model, setting), group in sorted(groups.items()):
        if setting == "auto" and (lang, model, lang) in groups:
            explicit = {r["id"]: r for r in groups[(lang, model, lang)]}
            common = [r for r in group if r["id"] in explicit]
            delta, ci = paired(common, [explicit[r["id"]] for r in common], "err_raw")
            settings.append({"lang": lang, "model": model, "explicit_minus_auto_raw": delta, "ci95": ci})

    pairs = []
    for lang, first, second in (FOLLOWUP_PAIRS if args.followup else PAIRS):
        a, b = groups.get((lang, *first)), groups.get((lang, *second))
        if not a or not b:
            continue
        a_by_id, b_by_id = {r["id"]: r for r in a}, {r["id"]: r for r in b}
        ids = sorted(set(a_by_id) & set(b_by_id))
        clean_ids = [i for i in ids if a_by_id[i]["clean"]]
        delta, ci = paired([a_by_id[i] for i in ids], [b_by_id[i] for i in ids], "err_raw")
        clean_delta, clean_ci = paired([a_by_id[i] for i in clean_ids], [b_by_id[i] for i in clean_ids], "err_raw")
        pairs.append({"lang": lang, "first": " ".join(first), "second": " ".join(second), "second_minus_first": delta,
                      "ci95": ci, "clean_second_minus_first": clean_delta, "clean_ci95": clean_ci, "clean_utterances": len(clean_ids)})

    results = HERE / "results" / ("followup-2026-10-24" if args.followup else "")
    results.mkdir(parents=True, exist_ok=True)
    (results / "summary.json").write_text(json.dumps(
        {"summary": summary, "paired_vs_sensevoice_auto": comparisons, "explicit_vs_auto": settings, "decision_pairs": pairs},
        ensure_ascii=False, indent=1) + "\n")
    with open(results / "utterances.csv", "w", newline="") as f:
        fields = ["id", "lang", "model", "setting", "status", "duration", "ref", "err", "err_raw", "empty", "truncated",
                  "wrong_script", "converted", "asrMs", "processingMs", "peak_footprint", "final", "raw"]
        writer = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        for row in sorted(rows, key=lambda r: (r["lang"], r["id"], r["model"], r["setting"])):
            writer.writerow({**row, "final": row["final"][:400], "raw": row["raw"][:400]})
    for e in summary:
        print(f"{e['lang']} {e['model']:32} {e['setting']:4} n={e['utterances']:2} {e['metric']} {e['error']:.3f} "
              f"{e['error_ci95']} raw {e['error_raw']:.3f} {e['error_raw_ci95']} nodig {e['error_no_digits']} clean(raw) {e['error_clean']} "
              f"fail {e['failures']} empty {e['empty']} trunc {e['truncated']} script {e['wrong_script']} conv {e['converted_by_script']} "
              f"asr {e['asr_ms_median']}/{e['asr_ms_p90']} proc {e['processing_ms_median']} "
              f"mem {e['peak_mb_median']}/{e['peak_mb_p95']}")
    for c in comparisons:
        print("paired", c)
    for s in settings:
        print("setting", s)
    for pair in pairs:
        print("pair", pair)


if __name__ == "__main__":
    main()
