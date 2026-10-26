#!/usr/bin/env python3
"""Score run_eval.py results against the AD-114 references.

  uv run --with opencc-python-reimplemented python -I eval/qa-sets/score.py \
      --sets "<qa-sets dir>" --work <dir> [--out summary.json]

Text: NFKC, lower case, apostrophes dropped, every punctuation or symbol becomes
a space; Chinese is converted to Simplified on both sides. zh/ja are scored as
CER over characters without whitespace, en/es as WER. Numbers are not
converted, so `25` against `twenty-five` counts as an error. A failed run counts
as a full deletion. Aggregates are pooled (total edits / total reference tokens).

Speakers (media suite): frame-level (10 ms) diarization error against the
reference segments. Reference speech is the union of segments; overlap counts as
correct when the mapped hypothesis speaker is any active reference speaker.
Hypothesis speakers map one-to-one to reference speakers by greatest overlap,
greedily. DER = (missed + false alarm + confusion) / reference speech. No
collar is applied; segment-timed models make DER pessimistic at turn edges.
"""
import argparse, collections, json, pathlib, unicodedata

CJK = {"zh", "ja"}
_cc = None


def tokens(text, lang):
    global _cc
    t = unicodedata.normalize("NFKC", text or "").lower().replace("'", "").replace("’", "")
    if lang == "zh":
        if _cc is None:
            import opencc
            _cc = opencc.OpenCC("t2s")
        t = _cc.convert(t)
    t = "".join(" " if unicodedata.category(c)[0] in "PS" else c for c in t)
    return list("".join(t.split())) if lang in CJK else t.split()


def edits(ref, hyp):
    prev = list(range(len(hyp) + 1))
    for i, r in enumerate(ref, 1):
        cur = [i]
        for j, h in enumerate(hyp, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (r != h)))
        prev = cur
    return prev[-1]


def der(ref_segments, turns, duration, step=0.01):
    n = int(duration / step) + 1
    ref = [set() for _ in range(n)]
    hyp = [None] * n
    for s in ref_segments:
        if s["speaker"] in {"ALL", "UNI", "INV"}:
            continue
        for k in range(max(0, int(s["start"] / step)), min(n, int(s["end"] / step))):
            ref[k].add(s["speaker"])
    for t in turns:
        if not t.get("speaker"):
            continue
        for k in range(max(0, int(t["start"] / step)), min(n, int(t["end"] / step))):
            hyp[k] = t["speaker"]
    overlap = collections.Counter((h, r) for k in range(n) if hyp[k] for r in ref[k] for h in [hyp[k]])
    mapping, used = {}, set()
    for (h, r), _ in overlap.most_common():
        if h not in mapping and r not in used:
            mapping[h] = r
            used.add(r)
    speech = sum(1 for k in range(n) if ref[k])
    miss = sum(1 for k in range(n) if ref[k] and not hyp[k])
    fa = sum(1 for k in range(n) if hyp[k] and not ref[k])
    conf = sum(1 for k in range(n) if ref[k] and hyp[k] and mapping.get(hyp[k]) not in ref[k])
    return {"der": round((miss + fa + conf) / max(1, speech), 4), "missed": round(miss / max(1, speech), 4),
            "false_alarm": round(fa / max(1, speech), 4), "confusion": round(conf / max(1, speech), 4)}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sets", required=True, type=pathlib.Path)
    ap.add_argument("--work", required=True, type=pathlib.Path)
    ap.add_argument("--out", type=pathlib.Path)
    a = ap.parse_args()
    refs = {p.stem: json.loads(p.read_text()) for p in a.sets.glob("*/*.json")}
    rows = []
    for path in sorted((a.work / "runs").glob("*/*/*.json")):
        r = json.loads(path.read_text())
        ref = refs[r["clip"]]
        lang = ref["language"]
        ok = r.get("status") == "passed"
        row = {"suite": r["suite"], "model": r["model"], "clip": r["clip"], "language": lang, "kind": ref["kind"],
               "speakers": ref["speakers"], "duration": ref["duration"], "status": r.get("status"),
               "error": r.get("error") or r.get("documentIssue") or "", "wall_s": r.get("wall_s"),
               "peak_footprint": r.get("peak_footprint")}
        rt = tokens(ref["text"], lang)
        row["ref_tokens"] = len(rt)
        if r["suite"] == "media":
            hyp = r.get("text") if ok else ""
            row["mediaMs"] = r.get("mediaMs")
            row["hyp_speakers"] = r.get("speakerCount")
            if ok and r.get("turns"):
                row.update(der(ref["segments"], r["turns"], ref["duration"]))
        else:
            # A refinement fallback still delivers the raw transcript; score what was delivered.
            delivered = ok or r.get("pipelineStatus") == "passed"
            hyp = (r.get("final") if delivered else "") or ""
            row["asrMs"] = r.get("asrMs")
            row["processingMs"] = (r.get("timings") or {}).get("processingMs")
            if r["suite"] == "refine":
                row["raw_edits"] = edits(rt, tokens(r.get("raw") or "", lang))
                row["refinement"] = r.get("refinementStatus")
                row["refinement_skipped"] = r.get("refinementSkipped")
        row["edits"] = edits(rt, tokens(hyp, lang))
        row["error_rate"] = round(row["edits"] / max(1, len(rt)), 4)
        row["hyp"] = hyp
        rows.append(row)
    groups = collections.defaultdict(list)
    for row in rows:
        groups[(row["suite"], row["language"], row["model"], row["kind"])].append(row)
    summary = []
    for (suite, lang, model, kind), rs in sorted(groups.items()):
        item = {"suite": suite, "language": lang, "model": model, "kind": kind, "clips": len(rs),
                "failed": sum(r["status"] != "passed" for r in rs),
                "error_rate": round(sum(r["edits"] for r in rs) / max(1, sum(r["ref_tokens"] for r in rs)), 4),
                "metric": "CER" if lang in CJK else "WER"}
        if suite == "refine":
            item["raw_error_rate"] = round(sum(r["raw_edits"] for r in rs) / max(1, sum(r["ref_tokens"] for r in rs)), 4)
            item["fallbacks"] = sum(r.get("refinement") == "fallback" for r in rs)
        if suite == "media" and any("der" in r for r in rs):
            item["der"] = round(sum(r.get("der", 1) for r in rs) / len(rs), 4)
            item["speaker_count_exact"] = sum(r.get("hyp_speakers") == r["speakers"] for r in rs)
        if suite != "media":
            rtf = [r["asrMs"] / 1000 / r["duration"] for r in rs if r.get("asrMs")]
            item["rtf"] = round(sum(rtf) / len(rtf), 4) if rtf else None
        else:
            rtf = [r["mediaMs"] / 1000 / r["duration"] for r in rs if r.get("mediaMs")]
            item["rtf"] = round(sum(rtf) / len(rtf), 4) if rtf else None
        summary.append(item)
    for s in summary:
        extra = ""
        if "raw_error_rate" in s:
            extra = f" raw {s['raw_error_rate']:.3f} fallbacks {s['fallbacks']}"
        if "der" in s:
            extra = f" DER {s['der']:.3f} speakers exact {s['speaker_count_exact']}/{s['clips']}"
        print(f"{s['suite']:9} {s['language']} {s['model']:30} {s['kind']:6} n={s['clips']} fail={s['failed']} "
              f"{s['metric']} {s['error_rate']:.3f} RTF {s['rtf']}{extra}")
    if a.out:
        a.out.write_text(json.dumps({"summary": summary, "clips": rows}, ensure_ascii=False, indent=1) + "\n")


if __name__ == "__main__":
    main()
