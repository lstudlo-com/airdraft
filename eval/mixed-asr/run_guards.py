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
`--english-in` renders the same sentences with three Indian English voices as
`en-in-control`, the false-positive check for a Hindi system language.

AD-098: `--intl` renders intl_control.json (Russian, Hindi and Arabic dictation
sentences, some with English terms) with the macOS ru_RU, hi_IN and ar voices as
corpora `intl-ru`, `intl-hi` and `intl-ar`. `--system-languages ru-RU,en-US` runs
the app with those preferred languages (`-AppleLanguages`, volatile argument
domain), which the guard's expected languages follow; use one tag per setting.
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
EN_IN_VOICES = ["Rishi", "Tara", "Aman"]
INTL_VOICES = {"ru": ["Milena"], "hi": ["Lekha"], "ar": ["Majed"]}


def render(work, corpus, entries, voices_for, id_prefix=""):
    out = work / "audio" / corpus
    out.mkdir(parents=True, exist_ok=True)
    items = []
    for index, entry in enumerate(entries):
        voices = voices_for(entry)
        voice = voices[index % len(voices)]
        item_id = id_prefix + entry["id"]
        wav = out / f"{item_id}.wav"
        if not wav.exists():
            subprocess.run(["/usr/bin/say", "-v", voice, "--file-format=WAVE", "--data-format=LEI16@16000",
                            "-o", str(wav), entry["text"]], check=True)
        info = subprocess.run(["/usr/bin/afinfo", str(wav)], capture_output=True, text=True).stdout
        duration = float(re.search(r"estimated duration: ([0-9.]+)", info).group(1))
        item = {"id": item_id, "corpus": corpus, "reference": entry["text"], "voice": voice, "duration": round(duration, 3)}
        if "language" in entry:
            item["language"] = entry["language"]
        items.append(item)
    return items


def english_items(work):
    return render(work, "en-control", json.loads((HERE / "english_control.json").read_text()), lambda _: EN_VOICES)


def english_in_items(work):
    return render(work, "en-in-control", json.loads((HERE / "english_control.json").read_text()),
                  lambda _: EN_IN_VOICES, id_prefix="in-")


def intl_items(work):
    items = []
    entries = json.loads((HERE / "intl_control.json").read_text())
    for language, voices in INTL_VOICES.items():
        items += render(work, f"intl-{language}", [e for e in entries if e["language"] == language], lambda _: voices)
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
    parser.add_argument("--english-in", action="store_true")
    parser.add_argument("--intl", action="store_true")
    parser.add_argument("--system-languages", help="comma list passed as -AppleLanguages, e.g. ru-RU,en-US")
    parser.add_argument("--reps", type=int, default=1)
    args = parser.parse_args()
    items = json.loads((HERE / "manifest.json").read_text())["items"]
    if args.english:
        items += english_items(args.work)
        (args.work / "en-control.json").write_text(json.dumps(items[-20:], ensure_ascii=False, indent=1))
    extra = []
    if args.english_in or args.intl:
        added = (english_in_items(args.work) if args.english_in else []) + (intl_items(args.work) if args.intl else [])
        path = args.work / "intl-control.json"
        known = {i["id"]: i for i in json.loads(path.read_text())} if path.exists() else {}
        known.update({i["id"]: i for i in added})
        path.write_text(json.dumps(list(known.values()), ensure_ascii=False, indent=1))
        items += added
    if args.system_languages:
        extra = ["-AppleLanguages", "(" + ", ".join(args.system_languages.split(",")) + ")"]
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
                result = run_app(args.app, args.work, model, language, audio, args.work / "sessions" / f"{args.tag}-{tag}",
                                 extra_args=extra)
                # Wall-clock bounds let guard_log.py attach the app's asr-guard log lines to this run.
                result.update(started=round(started, 3), ended=round(time.time(), 3))
                result.update(model=model, language=language, id=item["id"], corpus=item["corpus"],
                              duration=item["duration"], rep=rep, systemLanguages=args.system_languages)
                out.write_text(json.dumps(result, ensure_ascii=False, indent=1))
                print(index, item["id"], tag, rep, result["status"], result["asrMs"], result.get("peak_footprint"),
                      (result["final"] or "")[:50], flush=True)


if __name__ == "__main__":
    main()
