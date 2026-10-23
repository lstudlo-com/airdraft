#!/usr/bin/env python3
"""AD-082: re-run the configurations affected by the local ASR output guards.

  python3 -I eval/mixed-asr/run_guards.py --app "<Debug.app>" --work <dir> --tag after \
      [--configs qwen3:0.6b:zh,whisper:turbo:auto] [--ids tw08,ascend-tes-00678] [--reps 1]

Uses the same production route as run_matrix.py (`LocalE2E --e2e-action transcribe
--e2e-prepare`, isolated --e2e-local data, AIRDRAFT_E2E_MODEL_ROOT=<work>/models,
refinement off, insertion disabled). Results go to <work>/runs-<tag>/<config>/<id>-<rep>.json.

`--english` first renders english_control.json with four macOS English voices into
<work>/audio/en-control; those items join the manifest items as corpus `en-control`
(pure English speech, a false-positive check for the language guard).
"""
import argparse, json, pathlib, re, subprocess, sys, time

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from run_matrix import run_app  # noqa: E402

AFFECTED = [
    ("sherpa:senseVoice", "auto"), ("sherpa:senseVoice", "zh"), ("sherpa:fireRed", "auto"),
    ("qwen3:1.7b", "auto"), ("qwen3:0.6b", "zh"), ("qwen3:0.6b", "auto"),
    ("whisper:turbo", "auto"), ("whisper:turbo", "zh"),
]
EN_VOICES = ["Samantha", "Daniel", "Karen", "Rishi"]


def english_items(work):
    out = work / "audio" / "en-control"
    out.mkdir(parents=True, exist_ok=True)
    items = []
    for index, entry in enumerate(json.loads((HERE / "english_control.json").read_text())):
        voice = EN_VOICES[index % len(EN_VOICES)]
        wav = out / f"{entry['id']}.wav"
        if not wav.exists():
            subprocess.run(["/usr/bin/say", "-v", voice, "--file-format=WAVE", "--data-format=LEI16@16000",
                            "-o", str(wav), entry["text"]], check=True)
        info = subprocess.run(["/usr/bin/afinfo", str(wav)], capture_output=True, text=True).stdout
        duration = float(re.search(r"estimated duration: ([0-9.]+)", info).group(1))
        items.append({"id": entry["id"], "corpus": "en-control", "reference": entry["text"], "voice": voice,
                      "duration": round(duration, 3)})
    return items


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", required=True, type=pathlib.Path)
    parser.add_argument("--work", required=True, type=pathlib.Path)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--configs", help="comma list of model:language, default: all affected")
    parser.add_argument("--ids", help="comma list of utterance IDs, default: all")
    parser.add_argument("--corpora", help="comma list of corpora, default: all")
    parser.add_argument("--english", action="store_true")
    parser.add_argument("--reps", type=int, default=1)
    args = parser.parse_args()
    items = json.loads((HERE / "manifest.json").read_text())["items"]
    if args.english:
        items += english_items(args.work)
        (args.work / "en-control.json").write_text(json.dumps(items[-20:], ensure_ascii=False, indent=1))
    if args.ids:
        wanted = set(args.ids.split(","))
        items = [i for i in items if i["id"] in wanted]
    if args.corpora:
        wanted = set(args.corpora.split(","))
        items = [i for i in items if i["corpus"] in wanted]
    configs = AFFECTED
    if args.configs:
        configs = [tuple(c.rsplit(":", 1)) for c in args.configs.split(",")]
    runs = args.work / f"runs-{args.tag}"
    for index, item in enumerate(items):
        audio = args.work / "audio" / item["corpus"] / f"{item['id']}.wav"
        for model, language in configs:
            tag = f"{model.replace(':', '_')}-{language}"
            for rep in range(args.reps):
                out = runs / tag / f"{item['id']}-{rep}.json"
                if out.exists():
                    continue
                out.parent.mkdir(parents=True, exist_ok=True)
                started = time.time()
                result = run_app(args.app, args.work, model, language, audio, args.work / "sessions" / f"{args.tag}-{tag}")
                # Wall-clock bounds let guard_log.py attach the app's asr-guard log lines to this run.
                result.update(started=round(started, 3), ended=round(time.time(), 3))
                result.update(model=model, language=language, id=item["id"], corpus=item["corpus"],
                              duration=item["duration"], rep=rep)
                out.write_text(json.dumps(result, ensure_ascii=False, indent=1))
                print(index, item["id"], tag, rep, result["status"], result["asrMs"], result.get("peak_footprint"),
                      (result["final"] or "")[:50], flush=True)


if __name__ == "__main__":
    main()
