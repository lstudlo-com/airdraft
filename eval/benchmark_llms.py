#!/usr/bin/env python3
"""Loads each LM Studio model with the app's dictation context (8K), runs both
correction eval sets, records accuracy and latency, then unloads it.

Usage: eval/benchmark_llms.py <model-key> [<model-key> ...] [--runs 2]
Writes eval/results/llm-benchmark.json.
"""
import json, subprocess, sys, time, urllib.request, pathlib, argparse, statistics

ROOT = pathlib.Path(__file__).resolve().parent.parent
API = "http://localhost:1234/api/v1"

def post(path, body, timeout=600):
    req = urllib.request.Request(API + path, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)

ap = argparse.ArgumentParser()
ap.add_argument("models", nargs="+")
ap.add_argument("--runs", type=int, default=2)
args = ap.parse_args()

report = []
for key in args.models:
    t = time.time()
    loaded = post("/models/load", {"model": key, "context_length": 8192, "echo_load_config": True})
    instance = loaded["instance_id"]
    entry = {"model": key, "instance": instance, "load_seconds": round(time.time() - t, 1), "load_config": loaded.get("load_config")}
    print(f"\n### {key} loaded as {instance} in {entry['load_seconds']} s config={loaded.get('load_config')}", flush=True)
    for cases in ("correction_cases.json", "holdout_cases.json"):
        label = f"bench-{key.replace('/', '_')}-{cases.split('_')[0]}"
        subprocess.run([sys.executable, str(ROOT / "eval/run_correction_eval.py"), label, "--model", instance, "--cases", cases, "--runs", str(args.runs)], check=True)
        data = json.loads((ROOT / f"eval/results/{label}.json").read_text())
        secs = sorted(r["seconds"] for c in data["results"] for r in c["runs"])
        entry[cases] = {"passed": data["total"], "max": data["max"], "median_seconds": round(statistics.median(secs), 2), "p90_seconds": round(secs[max(0, int(len(secs) * 0.9) - 1)], 2)}
    post("/models/unload", {"instance_id": instance})
    report.append(entry)
    print(json.dumps(entry, ensure_ascii=False), flush=True)

(ROOT / "eval/results/llm-benchmark.json").write_text(json.dumps(report, ensure_ascii=False, indent=2))
print("\nwrote eval/results/llm-benchmark.json")
