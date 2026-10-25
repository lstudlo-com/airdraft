#!/usr/bin/env python3
"""Run every AD-098 manifest utterance through the Debug app's LocalE2E route.

  python3 -I eval/intl-asr/run_matrix.py --app "<DerivedData>/Airdraft Debug.app" \
      --work dist/intl-asr-work [--languages es,fr,...] [--configs qwen3:1.7b:auto,...] [--phase 1|2]

Same production route as eval/eja-asr (AD-083) and eval/mixed-asr (AD-074): one
`--e2e-action transcribe --e2e-prepare` process per utterance, isolated data (one
--e2e-local directory per configuration), AIRDRAFT_E2E_MODEL_ROOT=<work>/models,
refinement off, insertion disabled, empty dictionary. Each language runs as a
user of that system language (`-AppleLanguages (es-419|fr-FR|pt-BR|ru-RU|ar-EG|
hi-IN|id-ID)`), which sets the output guards' expected languages. Utterances are
the outer loop and configurations the inner loop, so background load affects all
models alike. Results are resumable JSON files under
<work>/runs/<lang>/<config>/<id>.json; a configuration whose model is not
installed in <work>/models is skipped (and listed) instead of recording failures.

Configurations: every local model whose SpeechLanguagePolicy supports the
language, explicit language for every model with a language parameter, plus Auto
for Whisper and Qwen3-ASR. Models whose manual control is `.notApplied`
(Parakeet, Orukeet, GigaAM, Moonshine, Fun-ASR, Voxtral) ignore the setting and
run once as "auto". Cohere, Canary and Granite have no Auto.
"""
import argparse, json, os, pathlib, re, subprocess, time

HERE = pathlib.Path(__file__).resolve().parent
LANGUAGES = ["es", "fr", "pt", "ru", "ar", "hi", "id"]
SYSTEM_LANGUAGE = {"es": "es-419", "fr": "fr-FR", "pt": "pt-BR", "ru": "ru-RU", "ar": "ar-EG", "hi": "hi-IN", "id": "id-ID"}
EUROPEAN = {"es", "fr", "pt", "ru"}            # Parakeet TDT v3, Orukeet, Canary 1B v2
COHERE = {"es", "fr", "pt", "ar"}               # Cohere Transcribe (of these seven)
FUN_ASR = {"pt", "ar", "hi", "id"}              # Fun-ASR Nano Multilingual
VOXTRAL = {"es", "fr", "pt", "ru", "ar", "hi"}  # Voxtral Mini 4B Realtime
GRANITE = {"es", "fr", "pt"}                    # Granite Speech 4.1 2B


def configs(lang, phase):
    """(catalogue ID, --e2e-language) pairs for one language and phase."""
    if phase == 1:
        out = [("qwen3:1.7b", "auto"), ("qwen3:1.7b", lang),
               ("whisper:turbo", "auto"), ("whisper:turbo", lang),
               ("whisper:large-v3", "auto"), ("whisper:large-v3", lang)]
        if lang in EUROPEAN:
            out += [("coreml:parakeet-v3", "auto"), ("sherpa:orukeet", "auto"), ("gguf:canary-1b-v2", lang)]
        if lang in COHERE:
            out += [("cohere", lang)]
        if lang == "ru":
            out += [("gguf:gigaam-v3-ctc", "auto"), ("gguf:gigaam-v3-e2e-rnnt", "auto")]
        if lang == "ar":
            out += [("gguf:cohere-transcribe-arabic-07-2026", "ar"), ("gguf:moonshine-base-ar", "auto")]
        if lang in FUN_ASR:
            out += [("gguf:fun-asr-mlt-nano-2512", "auto")]
        return out
    out = []
    if lang in VOXTRAL:
        out += [("gguf:voxtral-mini-4b-realtime-2602", "auto")]
    if lang in GRANITE:
        out += [("gguf:granite-speech-4.1-2b", lang)]
    return out


def environment(work):
    return {"HOME": os.environ["HOME"], "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "TMPDIR": os.environ.get("TMPDIR", "/tmp"), "AIRDRAFT_E2E_MODEL_ROOT": str(work / "models")}


def installed(app, work):
    data = work / "sessions" / "inventory"
    data.mkdir(parents=True, exist_ok=True)
    proc = subprocess.run([str(app / "Contents/MacOS/Airdraft Debug"), "--e2e-local", str(data), "--e2e-action", "inventory"],
                          env=environment(work), capture_output=True, text=True, timeout=120)
    report = json.loads(proc.stdout[proc.stdout.index("{"):proc.stdout.rindex("}") + 1])
    return {m["id"] for m in report["models"] if m["installed"]}


def run_app(app, work, model, language, audio, data_dir, system_language):
    data_dir.mkdir(parents=True, exist_ok=True)
    command = ["/usr/bin/time", "-l", str(app / "Contents/MacOS/Airdraft Debug"),
               "-AppleLanguages", f"({system_language})", "--e2e-local", str(data_dir),
               "--e2e-action", "transcribe", "--e2e-model", model, "--e2e-language", language,
               "--e2e-audio", str(audio), "--e2e-prepare"]
    load = os.getloadavg()[0]
    start = time.monotonic()
    try:
        proc = subprocess.run(command, env=environment(work), capture_output=True, text=True, timeout=600)
        stdout, stderr, code = proc.stdout, proc.stderr, proc.returncode
    except subprocess.TimeoutExpired as error:
        stdout = error.stdout.decode(errors="replace") if isinstance(error.stdout, bytes) else (error.stdout or "")
        stderr, code = "", -9
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
    parser.add_argument("--languages", default=",".join(LANGUAGES))
    parser.add_argument("--phase", type=int, choices=[1, 2], default=1,
                        help="1: Qwen3-ASR, Whisper and the small/medium models; 2: the 2-4B GGUF models")
    parser.add_argument("--configs", help="comma list of model:language; default: all for each language")
    parser.add_argument("--ids", help="comma list of utterance IDs")
    args = parser.parse_args()
    work = args.work.resolve()
    items = json.loads((HERE / "manifest.json").read_text())["items"]
    have = installed(args.app, work)
    wanted_ids = set(args.ids.split(",")) if args.ids else None
    only = {tuple(c.rsplit(":", 1)) for c in args.configs.split(",")} if args.configs else None
    plan = {}
    for lang in args.languages.split(","):
        chosen = [c for c in configs(lang, args.phase) if only is None or c in only]
        missing = sorted({m for m, _ in chosen if m not in have})
        if missing:
            print("skip (not installed)", lang, missing, flush=True)
        plan[lang] = [c for c in chosen if c[0] in have]
    # Utterances outer, configurations inner; languages interleaved by utterance index.
    by_lang = {lang: [i for i in items if i["language"] == lang] for lang in plan}
    for index in range(max((len(v) for v in by_lang.values()), default=0)):
        for lang, lang_items in by_lang.items():
            if index >= len(lang_items):
                continue
            item = lang_items[index]
            if wanted_ids and item["id"] not in wanted_ids:
                continue
            audio = work / "audio" / item["corpus"] / f"{item['id']}.wav"
            for model, language in plan[lang]:
                tag = f"{model.replace(':', '_')}-{language}"
                out = work / "runs" / lang / tag / f"{item['id']}.json"
                if out.exists():
                    continue
                out.parent.mkdir(parents=True, exist_ok=True)
                result = run_app(args.app, work, model, language, audio, work / "sessions" / lang / tag, SYSTEM_LANGUAGE[lang])
                result.update(model=model, language=language, id=item["id"], corpus=item["corpus"],
                              duration=item["duration"], system_language=SYSTEM_LANGUAGE[lang], started=time.time())
                out.write_text(json.dumps(result, ensure_ascii=False, indent=1))
                print(lang, index, item["id"], tag, result["status"], result["asrMs"], result.get("peak_footprint"),
                      (result["final"] or result["error"] or "")[:50].replace("\n", " "), flush=True)


if __name__ == "__main__":
    main()
