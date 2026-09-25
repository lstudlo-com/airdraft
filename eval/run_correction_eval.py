#!/usr/bin/env python3
"""Runs eval/correction_cases.json through `airdraft-cli refine` and scores each case.

A case passes when every `expect` substring is in the output and no `forbid`
substring is. Usage: eval/run_correction_eval.py <label> [--model gemma4] [--runs 3]
Use --cli <path> to evaluate an Xcode-built airdraft-cli without a SwiftPM build.
Writes eval/results/<label>.json.
"""
import json, subprocess, sys, pathlib, time, argparse, hashlib, re, textwrap

ROOT = pathlib.Path(__file__).resolve().parent.parent
CLI = ROOT / "Packages/AirdraftCore/.build/debug/airdraft-cli"

ap = argparse.ArgumentParser()
ap.add_argument("label")
ap.add_argument("--model", default="gemma4")
ap.add_argument("--runs", type=int, default=3)
ap.add_argument("--cases", default="correction_cases.json")
ap.add_argument("--base-rules-file")
ap.add_argument("--cli", type=pathlib.Path, default=CLI, help="Path to airdraft-cli, including an Xcode-built binary")
args = ap.parse_args()

if args.runs < 3:
    ap.error("Release evidence requires at least three runs per case")
source_path = ROOT / "Packages/AirdraftCore/Sources/AirdraftCore/LLM/PromptBuilder.swift"
source = source_path.read_text()
version = re.search(r'public static let version = "([^"]+)"', source).group(1)
default_rules = textwrap.dedent(re.search(r'public static let defaultBaseRules = """\n(.*?)\n    """', source, re.S).group(1))
rules = pathlib.Path(args.base_rules_file).read_text() if args.base_rules_file else default_rules
prompt_args = [str(args.cli), "prompt"]
if args.base_rules_file: prompt_args += ["--base-rules-file", args.base_rules_file]
compiled_prompt = subprocess.run(prompt_args, check=True, capture_output=True, text=True).stdout
if rules.strip() not in compiled_prompt:
    raise SystemExit("CLI prompt does not match the source under evaluation; rebuild the CLI first")
source_files = ["LLM/PromptBuilder.swift", "LLM/RefinementProfile.swift", "Context/AppFamily.swift", "Dictionary/DictionaryPostProcessor.swift"]
source_hashes = {name: hashlib.sha256((ROOT / "Packages/AirdraftCore/Sources/AirdraftCore" / name).read_bytes()).hexdigest() for name in source_files}
cases_sha256 = hashlib.sha256((ROOT / "eval" / args.cases).read_bytes()).hexdigest()
cases = json.loads((ROOT / "eval" / args.cases).read_text())
results = []
for case in cases:
    runs = []
    for _ in range(args.runs):
        cmd = [str(args.cli), "refine", case["raw"], "--llm-model", args.model, "--family", case.get("family", "general"),
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
        ok = out.returncode == 0 and all(e in text for e in case["expect"]) and not any(f in text for f in case["forbid"])
        runs.append({"returncode": out.returncode, "ok": ok, "text": text, "seconds": round(time.time() - t, 2), "stderr": out.stderr[-300:]})
    passed = sum(r["ok"] for r in runs)
    results.append({"id": case["id"], "passed": passed, "runs": runs})
    print(f"{case['id']:<24} {passed}/{args.runs}  {runs[-1]['text'][:90]!r}")

total = sum(r["passed"] for r in results)
print(f"TOTAL {total}/{len(cases) * args.runs}")
out_dir = ROOT / "eval/results"; out_dir.mkdir(parents=True, exist_ok=True)
(out_dir / f"{args.label}.json").write_text(json.dumps({"label": args.label, "prompt_version": version, "default_rules_sha256": hashlib.sha256(rules.strip().encode()).hexdigest(), "assembly_sources": source_hashes, "cases_sha256": cases_sha256, "cli_sha256": hashlib.sha256(args.cli.read_bytes()).hexdigest(), "cases": args.cases, "model": args.model, "runs": args.runs, "total": total, "max": len(cases) * args.runs, "results": results}, ensure_ascii=False, indent=2))
