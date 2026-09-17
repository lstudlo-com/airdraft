#!/usr/bin/env python3
"""Refine latency on long real dictations (history rows) per model. Loads, measures, unloads.
Usage: eval/long_latency.py <history-db> <model-key> [...]  Writes eval/results/long-latency.json"""
import json, sqlite3, subprocess, sys, time, urllib.request, pathlib, statistics
ROOT = pathlib.Path(__file__).resolve().parent.parent
API = "http://localhost:1234/api/v1"
def post(path, body):
    req = urllib.request.Request(API + path, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=600) as r: return json.load(r)
db, models = sys.argv[1], sys.argv[2:]
rows = sqlite3.connect(db).execute("select id, rawTranscript from dictation where length(rawTranscript) between 350 and 700 order by id desc limit 4").fetchall()
out = []
for key in models:
    inst = post("/models/load", {"model": key})["instance_id"]
    cli = ROOT / "Packages/AirdraftCore/.build/debug/airdraft-cli"
    subprocess.run([str(cli), "refine", "暖機", "--llm-model", inst], capture_output=True)
    for rid, raw in rows:
        t = time.time()
        r = subprocess.run([str(cli), "refine", raw, "--llm-model", inst, "--mode", "clean", "--family", "code", "--timeout", "120"], capture_output=True, text=True)
        text = "\n".join(l for l in r.stdout.splitlines() if not l.startswith("[llm]"))
        out.append({"model": key, "row": rid, "in_chars": len(raw), "out_chars": len(text), "seconds": round(time.time() - t, 2)})
        print(out[-1], flush=True)
    post("/models/unload", {"instance_id": inst})
(ROOT / "eval/results/long-latency.json").write_text(json.dumps(out, ensure_ascii=False, indent=2))
for key in models:
    s = [o["seconds"] for o in out if o["model"] == key]
    print(key, "median", statistics.median(s), "s")
