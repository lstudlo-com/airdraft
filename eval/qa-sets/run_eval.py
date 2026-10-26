#!/usr/bin/env python3
"""Run the AD-114 QA sets through the Debug app's production routes.

  python3 -I eval/qa-sets/run_eval.py --app "<DerivedData>/Airdraft Debug.app" \
      --sets "<qa-sets dir>" --work <dir> [--suites dictation,refine,media] [--languages zh,en,ja,es]

Suites (each clip runs in its own process with isolated data under <work>/sessions):
  dictation  `--e2e-action transcribe --e2e-prepare`: the dictation pipeline with
             refinement off, insertion disabled, an empty dictionary, Auto language.
             Every clip, with each language's first-run recommendation and its
             alternative (LocalSpeechRecommendation, more than 8 GB).
  refine     the same route with Apple Intelligence refinement (Clean profile),
             recommended model only.
  media      `--e2e-action media`: Transcribe's file import with speaker
             identification, recommended model only.
Models come from AIRDRAFT_E2E_MODEL_ROOT=<work>/models, an APFS clone of the
installed models (never downloaded here). Each language runs as a user of that
system language. Results are resumable: <work>/runs/<suite>/<config>/<clip>.json.
"""
import argparse, json, os, pathlib, re, subprocess, time

SYSTEM_LANGUAGE = {"zh": "zh-Hans-CN", "en": "en-US", "ja": "ja-JP", "es": "es-ES"}
# The E2E container saves an explicit ASRConfig, whose default script is Traditional;
# a new install with a Simplified Chinese system language gets Simplified.
CHINESE_SCRIPT = {"zh": "simplified"}
# (dictation model ID, Transcribe model choice ID); first entry is the recommendation.
MODELS = {
    "zh": [("qwen3:1.7b", "qwenLarge"), ("sherpa:senseVoiceMultilingual", None)],
    "en": [("coreml:parakeet-v2", "coreml:parakeet-v2"), ("qwen3:1.7b", None)],
    "ja": [("qwen3:1.7b", "qwenLarge"), ("whisper:turbo", None)],
    "es": [("qwen3:1.7b", "qwenLarge"), ("coreml:parakeet-v3", None)],
}


def run_app(app, work, args, system_language, data_dir, timeout=1200):
    data_dir.mkdir(parents=True, exist_ok=True)
    env = {"HOME": os.environ["HOME"], "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
           "TMPDIR": os.environ.get("TMPDIR", "/tmp"), "AIRDRAFT_E2E_MODEL_ROOT": str(work / "models")}
    command = ["/usr/bin/time", "-l", str(app / "Contents/MacOS/Airdraft Debug"),
               "-AppleLanguages", f"({system_language})", "--e2e-local", str(data_dir)] + args
    start = time.monotonic()
    try:
        proc = subprocess.run(command, env=env, capture_output=True, text=True, timeout=timeout)
        stdout, stderr, code = proc.stdout, proc.stderr, proc.returncode
    except subprocess.TimeoutExpired:
        stdout, stderr, code = "", "", -9
    wall = time.monotonic() - start
    try:
        report = json.loads(stdout[stdout.index("{"):stdout.rindex("}") + 1])
    except ValueError:
        report = {"status": "failed", "error": stdout[-500:] or "timeout"}
    m = re.search(r"(\d+)\s+peak memory footprint", stderr)
    report.update(exit=code, wall_s=round(wall, 3), peak_footprint=int(m.group(1)) if m else None)
    return report


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--app", required=True, type=pathlib.Path)
    ap.add_argument("--sets", required=True, type=pathlib.Path)
    ap.add_argument("--work", required=True, type=pathlib.Path)
    ap.add_argument("--suites", default="dictation,refine,media")
    ap.add_argument("--languages", default="zh,en,ja,es")
    ap.add_argument("--clips", help="comma list of clip IDs")
    a = ap.parse_args()
    manifest = json.loads((a.sets / "manifest.json").read_text())
    wanted = set(a.clips.split(",")) if a.clips else None
    for suite in a.suites.split(","):
        for lang in a.languages.split(","):
            models = MODELS[lang] if suite == "dictation" else MODELS[lang][:1]
            for clip in manifest["sets"][lang]:
                if wanted and clip["id"] not in wanted:
                    continue
                audio = a.sets / clip["audio"]
                for dictation_model, media_model in models:
                    if suite == "media":
                        tag = media_model.replace(":", "_")
                        args = ["--e2e-action", "media", "--e2e-media-model", media_model, "--e2e-audio", str(audio)]
                    else:
                        tag = dictation_model.replace(":", "_")
                        args = ["--e2e-action", "transcribe", "--e2e-prepare", "--e2e-model", dictation_model,
                                "--e2e-language", "auto", "--e2e-audio", str(audio)]
                        if lang in CHINESE_SCRIPT:
                            args += ["--e2e-chinese-script", CHINESE_SCRIPT[lang]]
                        if suite == "refine":
                            args += ["--e2e-refiner", "appleIntelligence", "--e2e-profile", "Clean"]
                    out = a.work / "runs" / suite / tag / f"{clip['id']}.json"
                    if out.exists():
                        continue
                    out.parent.mkdir(parents=True, exist_ok=True)
                    report = run_app(a.app, a.work, args, SYSTEM_LANGUAGE[lang], a.work / "sessions" / suite / tag / clip["id"])
                    report.update(suite=suite, model=media_model if suite == "media" else dictation_model,
                                  clip=clip["id"], language=lang, duration=clip["duration"], finished=time.time())
                    out.write_text(json.dumps(report, ensure_ascii=False, indent=1))
                    text = report.get("final") or report.get("text") or report.get("error") or ""
                    print(suite, tag, clip["id"], report.get("status"), report["wall_s"], text[:60].replace("\n", " "), flush=True)


if __name__ == "__main__":
    main()
