#!/usr/bin/env python3
"""AD-081: run the vocabulary-bias corpus through the Debug app, bias off vs on.

  python3 -I eval/vocab-bias/run_eval.py --app "<DerivedData>/Airdraft Debug.app" \
      --work /tmp/airdraft-wave/vocab [--configs qwen3:1.7b,sherpa:parakeet] [--tag name]

Each utterance is one `--e2e-action transcribe --e2e-prepare` process (the
production pipeline: SpeechLanguagePolicy, TranscriptionHints, script
conversion, dictionary post-processing) with isolated data: one --e2e-local
directory per configuration whose dictionary.json holds the corpus terms
(preferred spellings, no aliases) and AIRDRAFT_E2E_MODEL_ROOT=<work>/models.
Refinement, app context and insertion stay off. `--e2e-vocabulary-bias`
switches Settings > Vocabulary's on-device option. Silence clips run with
--e2e-expect-silence (pass = no outcome, no history; fresh data directory) and
once without it to capture any hallucinated text. Results are resumable JSON under <work>/runs.
"""
import argparse, json, os, pathlib, subprocess, time, uuid

HERE = pathlib.Path(__file__).resolve().parent
# model -> languages it is run with (Parakeet is English/European only).
MODELS = {
    "qwen3:1.7b": ["en", "zh"], "qwen3:0.6b": ["en", "zh"], "sherpa:parakeet": ["en"],
    "whisper:turbo": ["en", "zh"], "apple": ["en"],
}


def run_app(app, work, model, language, audio, data_dir, bias, expect_silence=False):
    env = {"HOME": os.environ["HOME"], "PATH": os.environ["PATH"], "TMPDIR": os.environ.get("TMPDIR", "/tmp"),
           "AIRDRAFT_E2E_MODEL_ROOT": str(work / "models")}
    command = [str(app / "Contents/MacOS/Airdraft Debug"), "--e2e-local", str(data_dir),
               "--e2e-action", "transcribe", "--e2e-model", model, "--e2e-language", language,
               "--e2e-audio", str(audio), "--e2e-prepare", "--e2e-vocabulary-bias", bias]
    if model == "apple":
        command += ["--e2e-locale", {"en": "en-US", "zh": "zh-TW"}[language]]
    if expect_silence:
        command.append("--e2e-expect-silence")
    start = time.monotonic()
    proc = subprocess.run(command, env=env, capture_output=True, text=True, timeout=600)
    text = proc.stdout
    try:
        report = json.loads(text[text.index("{"):text.rindex("}") + 1])
    except ValueError:
        report = {"status": "failed", "error": (text + proc.stderr)[-500:]}
    return {"exit": proc.returncode, "wall_s": round(time.monotonic() - start, 3), "status": report.get("status"),
            "error": report.get("error"), "raw": report.get("raw"), "final": report.get("final"),
            "asrMs": report.get("asrMs"), "historyEmpty": report.get("historyEmpty"), "noOutcome": report.get("noOutcome")}


def write_dictionary(directory, terms):
    directory.mkdir(parents=True, exist_ok=True)
    entries = [{"id": str(uuid.uuid5(uuid.NAMESPACE_URL, "airdraft-ad081/" + term)).upper(), "term": term,
                "aliases": [], "caseSensitive": False} for term in terms]
    (directory / "dictionary.json").write_text(json.dumps(entries, ensure_ascii=False, indent=1))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", required=True, type=pathlib.Path)
    parser.add_argument("--work", required=True, type=pathlib.Path)
    parser.add_argument("--configs", default=",".join(MODELS))
    parser.add_argument("--biases", default="off,on")
    parser.add_argument("--tag", default="", help="Suffix for a variant build, e.g. whisper-prompt")
    parser.add_argument("--dictionary", default="corpus", help="'corpus' or a comma-separated override list")
    parser.add_argument("--items", default="", help="Optional comma-separated item IDs")
    args = parser.parse_args()
    corpus = json.loads((HERE / "corpus.json").read_text())
    terms = corpus["dictionary"] if args.dictionary == "corpus" else [t for t in args.dictionary.split(",") if t]
    wanted = set(filter(None, args.items.split(",")))
    for model in filter(None, args.configs.split(",")):
        for bias in args.biases.split(","):
            label = f"{model.replace(':', '_')}-{bias}{('-' + args.tag) if args.tag else ''}"
            session = args.work / "sessions" / label
            write_dictionary(session, terms)
            for item in corpus["items"] + [dict(s, language=lang) for s in corpus["silence"] for lang in MODELS[model][:1]]:
                if item["language"] not in MODELS[model] or (wanted and item["id"] not in wanted):
                    continue
                audio = args.work / "audio" / f"{item['id']}.wav"
                silence = item["id"].startswith("sil")
                for expect in ([True, False] if silence else [False]):
                    name = item["id"] + ("-expect" if expect else "")
                    out = args.work / "runs" / label / f"{name}.json"
                    if out.exists():
                        continue
                    out.parent.mkdir(parents=True, exist_ok=True)
                    # A silence check requires empty history, so it gets fresh data.
                    data = session
                    if silence:
                        data = args.work / "sessions" / f"{label}-{name}-{uuid.uuid4().hex[:8]}"
                        write_dictionary(data, terms)
                    result = run_app(args.app, args.work, model, item["language"], audio, data, bias, expect)
                    result.update(id=item["id"], model=model, bias=bias, tag=args.tag, expectSilence=expect,
                                  dictionary=terms)
                    out.write_text(json.dumps(result, ensure_ascii=False, indent=1))
                    print(label, name, result["status"], result["asrMs"], (result["raw"] or result["error"] or "")[:90], flush=True)


if __name__ == "__main__":
    main()
