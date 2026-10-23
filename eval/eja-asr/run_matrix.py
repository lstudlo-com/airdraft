#!/usr/bin/env python3
"""Run every AD-083 manifest utterance through the Debug app's LocalE2E route.

  python3 -I eval/eja-asr/run_matrix.py --app "<DerivedData>/Airdraft Debug.app" \
      --work /tmp/airdraft-wave/ad083 [--languages en,ja,ko] [--configs qwen3:1.7b:auto,...]

Same production route as eval/mixed-asr (AD-074): one `--e2e-action transcribe
--e2e-prepare` process per utterance, isolated data (one --e2e-local directory per
configuration), AIRDRAFT_E2E_MODEL_ROOT=<work>/models, refinement off, insertion
disabled, empty dictionary. Each language runs as a user of that system language
(`-AppleLanguages (en-US|ja-JP|ko-KR)`), which sets the output guards' expected
languages. The ASRConfig default script (Traditional) is unchanged, as for a new
install. Utterances are the outer loop and configurations the inner loop, so
background load affects all models alike. Results are resumable JSON files
under <work>/runs/<lang>/<config>/<id>.json.
"""
import argparse, json, os, pathlib, re, subprocess, time

HERE = pathlib.Path(__file__).resolve().parent
SYSTEM_LANGUAGE = {"en": "en-US", "ja": "ja-JP", "ko": "ko-KR"}
# (model catalogue ID, --e2e-language). Only languages each model's
# SpeechLanguagePolicy supports. Models with manualControl .notApplied (Parakeet)
# ignore the setting and run once; Cohere has no Auto.
CONFIGS = {
    "en": [("sherpa:senseVoice", "auto"), ("sherpa:senseVoice", "en"),
           ("qwen3:1.7b", "auto"), ("qwen3:1.7b", "en"), ("qwen3:0.6b", "auto"), ("qwen3:0.6b", "en"),
           ("whisper:turbo", "auto"), ("whisper:turbo", "en"), ("whisper:large-v3", "auto"), ("whisper:large-v3", "en"),
           ("cohere", "en"), ("sherpa:parakeet", "auto"), ("coreml:parakeet-v2", "auto")],
    "ja": [("sherpa:senseVoice", "auto"), ("sherpa:senseVoice", "ja"),
           ("qwen3:1.7b", "auto"), ("qwen3:1.7b", "ja"), ("qwen3:0.6b", "auto"), ("qwen3:0.6b", "ja"),
           ("whisper:turbo", "auto"), ("whisper:turbo", "ja"), ("whisper:large-v3", "auto"), ("whisper:large-v3", "ja"),
           ("cohere", "ja"), ("coreml:parakeet-ja", "auto")],
    "ko": [("sherpa:senseVoice", "auto"), ("sherpa:senseVoice", "ko"),
           ("qwen3:1.7b", "auto"), ("qwen3:1.7b", "ko"), ("qwen3:0.6b", "auto"), ("qwen3:0.6b", "ko"),
           ("whisper:turbo", "auto"), ("whisper:turbo", "ko"), ("whisper:large-v3", "auto"), ("whisper:large-v3", "ko"),
           ("cohere", "ko")],
}
# Evaluation only (--sensevoice-2024): the original multilingual SenseVoice Small
# (sherpa-onnx int8 2024-07-17) staged under the shipped folder name in a separate
# model root, so the same app route loads it as "sherpa:senseVoice". The shipped
# 2025-09-09 archive is converted from the Cantonese fine-tune ASLP-lab/WSYue-ASR.
SENSEVOICE_2024 = "sherpa:senseVoice@2024"
SENSEVOICE_2024_ROOT = "models-sv2024"


def run_app(app, work, model, language, audio, data_dir, system_language, prepare=True):
    data_dir.mkdir(parents=True, exist_ok=True)
    root = work / (SENSEVOICE_2024_ROOT if model == SENSEVOICE_2024 else "models")
    env = {"HOME": os.environ["HOME"], "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
           "TMPDIR": os.environ.get("TMPDIR", "/tmp"), "AIRDRAFT_E2E_MODEL_ROOT": str(root)}
    command = ["/usr/bin/time", "-l", str(app / "Contents/MacOS/Airdraft Debug"),
               "-AppleLanguages", f"({system_language})", "--e2e-local", str(data_dir),
               "--e2e-action", "transcribe", "--e2e-model", model.split("@")[0], "--e2e-language", language,
               "--e2e-audio", str(audio)] + (["--e2e-prepare"] if prepare else [])
    load = os.getloadavg()[0]
    start = time.monotonic()
    try:
        proc = subprocess.run(command, env=env, capture_output=True, text=True, timeout=600)
        stdout, stderr, code = proc.stdout, proc.stderr, proc.returncode
    except subprocess.TimeoutExpired as error:
        stdout, stderr, code = (error.stdout or b"").decode(errors="replace") if isinstance(error.stdout, bytes) else (error.stdout or ""), "", -9
    wall = time.monotonic() - start
    try:
        report = json.loads(stdout[stdout.index("{"):stdout.rindex("}") + 1])
    except ValueError:
        report = {"status": "failed", "error": stdout[-500:] or "timeout"}
    stats = {key: int(m.group(1)) for key, pattern in
             [("max_rss", r"(\d+)\s+maximum resident set size"), ("peak_footprint", r"(\d+)\s+peak memory footprint")]
             if (m := re.search(pattern, stderr))}
    timings = report.get("timings") or {}
    return {"exit": code, "wall_s": round(wall, 3), "loadavg1": round(load, 2), **stats,
            "status": report.get("status"), "error": report.get("error"), "engine": report.get("engine"),
            "raw": report.get("raw"), "final": report.get("final"), "asrMs": report.get("asrMs"),
            "processingMs": timings.get("processingMs"), "postProcessingMs": timings.get("postProcessingMs")}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", required=True, type=pathlib.Path)
    parser.add_argument("--work", required=True, type=pathlib.Path)
    parser.add_argument("--languages", default="en,ja,ko")
    parser.add_argument("--configs", help="comma list of model:language; default: all for each language")
    parser.add_argument("--ids", help="comma list of utterance IDs")
    parser.add_argument("--sensevoice-2024", action="store_true",
                        help="run only the evaluation-only original SenseVoice (Auto and the explicit language)")
    args = parser.parse_args()
    items = json.loads((HERE / "manifest.json").read_text())["items"]
    wanted_ids = set(args.ids.split(",")) if args.ids else None
    only = {tuple(c.rsplit(":", 1)) for c in args.configs.split(",")} if args.configs else None
    for lang in args.languages.split(","):
        configs = [c for c in CONFIGS[lang] if only is None or c in only]
        if args.sensevoice_2024:
            configs = [(SENSEVOICE_2024, "auto"), (SENSEVOICE_2024, lang)]
        for index, item in enumerate(i for i in items if i["language"] == lang):
            if wanted_ids and item["id"] not in wanted_ids:
                continue
            audio = args.work / "audio" / item["corpus"] / f"{item['id']}.wav"
            for model, language in configs:
                tag = f"{model.replace(':', '_').replace('@', '_')}-{language}"
                out = args.work / "runs" / lang / tag / f"{item['id']}.json"
                if out.exists():
                    continue
                out.parent.mkdir(parents=True, exist_ok=True)
                result = run_app(args.app, args.work, model, language, audio,
                                 args.work / "sessions" / lang / tag, SYSTEM_LANGUAGE[lang])
                result.update(model=model, language=language, id=item["id"], corpus=item["corpus"],
                              duration=item["duration"], system_language=SYSTEM_LANGUAGE[lang], started=time.time())
                out.write_text(json.dumps(result, ensure_ascii=False, indent=1))
                print(lang, index, item["id"], tag, result["status"], result["asrMs"], result.get("peak_footprint"),
                      (result["final"] or result["error"] or "")[:50].replace("\n", " "), flush=True)


if __name__ == "__main__":
    main()
