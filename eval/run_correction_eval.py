#!/usr/bin/env python3
"""Runs eval/correction_cases.json through `airdraft-cli refine` and scores each case.

A case passes when every `expect` substring is in the output and no `forbid`
substring is. Usage: eval/run_correction_eval.py <label> [--model gemma4] [--runs 3]
Writes eval/results/<label>.json.
"""
import json, subprocess, sys, pathlib, time, argparse

ROOT = pathlib.Path(__file__).resolve().parent.parent
CLI = ROOT / "Packages/AirdraftCore/.build/debug/airdraft-cli"

ap = argparse.ArgumentParser()
ap.add_argument("label")
ap.add_argument("--model", default="gemma4")
ap.add_argument("--runs", type=int, default=3)
ap.add_argument("--cases", default="correction_cases.json")
ap.add_argument("--base-rules-file")
args = ap.parse_args()

cases = json.loads((ROOT / "eval" / args.cases).read_text())
results = []
for case in cases:
    runs = []
    for _ in range(args.runs):
        cmd = [str(CLI), "refine", case["raw"], "--llm-model", args.model, "--family", case.get("family", "general"),
               "--mode", case.get("profile", "clean"), "--script", "traditional", "--timeout", "90"]
        for key, flag in (("before", "before"), ("after", "after"), ("selected", "selected"), ("app", "app"),
                          ("window", "window"), ("url", "page-url"), ("recent", "recent")):
            if case.get(key):
                cmd += [f"--{flag}", case[key]]
        if args.base_rules_file:
            cmd += ["--base-rules-file", args.base_rules_file]
        if case.get("vocab"):
            cmd += ["--dict", case["vocab"]]
        t = time.time()
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
        text = "\n".join(l for l in out.stdout.splitlines() if not l.startswith("[llm]")).strip()
        ok = all(e in text for e in case["expect"]) and not any(f in text for f in case["forbid"])
        runs.append({"ok": ok, "text": text, "seconds": round(time.time() - t, 2), "stderr": out.stderr[-300:]})
    passed = sum(r["ok"] for r in runs)
    results.append({"id": case["id"], "passed": passed, "runs": runs})
    print(f"{case['id']:<24} {passed}/{args.runs}  {runs[-1]['text'][:90]!r}")

total = sum(r["passed"] for r in results)
print(f"TOTAL {total}/{len(cases) * args.runs}")
out_dir = ROOT / "eval/results"; out_dir.mkdir(parents=True, exist_ok=True)
(out_dir / f"{args.label}.json").write_text(json.dumps({"label": args.label, "cases": args.cases, "model": args.model, "runs": args.runs, "total": total, "max": len(cases) * args.runs, "results": results}, ensure_ascii=False, indent=2))
