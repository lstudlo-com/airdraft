#!/usr/bin/env python3
"""Run every manifest utterance through the Debug app's LocalE2E transcription route.

  python3 -I eval/mixed-asr/run_matrix.py --app "<DerivedData>/Airdraft Debug.app" \
      --work /tmp/airdraft-groupA/asr-eval [--load-reps 3]

Each run is one `--e2e-action transcribe --e2e-prepare` process with isolated data
(one reused --e2e-local directory per configuration), AIRDRAFT_E2E_MODEL_ROOT at
<work>/models, refinement off and insertion disabled (LocalE2E defaults). The
production pipeline resolves SpeechLanguagePolicy, applies the Chinese script
(ASRConfig default: Traditional) and dictionary post-processing. Utterances are
the outer loop and configurations the inner loop, so background load affects
all models alike. Results are resumable JSON files under <work>/runs.
"""
import argparse, json, os, pathlib, re, subprocess, time

HERE = pathlib.Path(__file__).resolve().parent
# (model catalogue ID, --e2e-language). FireRed ignores the language setting
# (SpeechLanguagePolicy .notApplied), so only Auto is run for it.
CONFIGS = [
    ("sherpa:senseVoice", "auto"), ("sherpa:senseVoice", "zh"),
    ("qwen3:1.7b", "auto"), ("qwen3:1.7b", "zh"),
    ("qwen3:0.6b", "auto"), ("qwen3:0.6b", "zh"),
    ("whisper:turbo", "auto"), ("whisper:turbo", "zh"),
    ("sherpa:fireRed", "auto"),
]


def run_app(app, work, model, language, audio, data_dir, prepare=True):
    data_dir.mkdir(parents=True, exist_ok=True)
    env = {"HOME": os.environ["HOME"], "PATH": os.environ["PATH"], "TMPDIR": os.environ.get("TMPDIR", "/tmp"),
           "AIRDRAFT_E2E_MODEL_ROOT": str(work / "models")}
    command = ["/usr/bin/time", "-l", str(app / "Contents/MacOS/Airdraft Debug"), "--e2e-local", str(data_dir),
               "--e2e-action", "transcribe", "--e2e-model", model, "--e2e-language", language,
               "--e2e-audio", str(audio)] + (["--e2e-prepare"] if prepare else [])
    load = os.getloadavg()[0]
    start = time.monotonic()
    proc = subprocess.run(command, env=env, capture_output=True, text=True, timeout=900)
    wall = time.monotonic() - start
    text = proc.stdout
    report = json.loads(text[text.index("{"):text.rindex("}") + 1]) if "{" in text else {"status": "failed", "error": text[-500:]}
    stats = {key: int(m.group(1)) for key, pattern in
             [("max_rss", r"(\d+)\s+maximum resident set size"), ("peak_footprint", r"(\d+)\s+peak memory footprint")]
             if (m := re.search(pattern, proc.stderr))}
    return {"exit": proc.returncode, "wall_s": round(wall, 3), "loadavg1": round(load, 2), **stats,
            "status": report.get("status"), "error": report.get("error"), "engine": report.get("engine"),
            "raw": report.get("raw"), "final": report.get("final"), "asrMs": report.get("asrMs"),
            "processingMs": (report.get("timings") or {}).get("processingMs")}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", required=True, type=pathlib.Path)
    parser.add_argument("--work", required=True, type=pathlib.Path)
    parser.add_argument("--load-reps", type=int, default=3)
    args = parser.parse_args()
    items = json.loads((HERE / "manifest.json").read_text())["items"]
    runs = args.work / "runs"
    # Load time: asrMs without --e2e-prepare (load + inference) minus asrMs with it,
    # on the same file, OS file cache warm. Alternated per repetition.
    probe = next(i for i in items if i["id"] == "tw01")
    for model in sorted({m for m, _ in CONFIGS}):
        for rep in range(args.load_reps):
            for prepare in (False, True):
                out = runs / "load" / f"{model.replace(':', '_')}-{rep}-{'prep' if prepare else 'cold'}.json"
                if out.exists():
                    continue
                out.parent.mkdir(parents=True, exist_ok=True)
                result = run_app(args.app, args.work, model, "auto", args.work / "audio/tw-tts/tw01.wav",
                                 args.work / "sessions" / f"load-{model.replace(':', '_')}", prepare)
                result.update(model=model, rep=rep, prepare=prepare, id=probe["id"])
                out.write_text(json.dumps(result, ensure_ascii=False, indent=1))
                print("load", model, rep, prepare, result["asrMs"], result["status"], flush=True)
    for index, item in enumerate(items):
        audio = args.work / "audio" / item["corpus"] / f"{item['id']}.wav"
        for model, language in CONFIGS:
            tag = f"{model.replace(':', '_')}-{language}"
            out = runs / tag / f"{item['id']}.json"
            if out.exists() and json.loads(out.read_text()).get("status") == "passed":
                continue
            out.parent.mkdir(parents=True, exist_ok=True)
            result = run_app(args.app, args.work, model, language, audio, args.work / "sessions" / tag)
            result.update(model=model, language=language, id=item["id"], corpus=item["corpus"], duration=item["duration"])
            out.write_text(json.dumps(result, ensure_ascii=False, indent=1))
            print(index, item["id"], tag, result["status"], result["asrMs"], (result["final"] or "")[:40], flush=True)


if __name__ == "__main__":
    main()
