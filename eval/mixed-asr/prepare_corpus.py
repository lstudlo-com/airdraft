#!/usr/bin/env python3
"""Build the AD-074 mixed Chinese-English corpora under a scratch directory.

  python3 -I eval/mixed-asr/prepare_corpus.py --work /tmp/airdraft-groupA/asr-eval

(a) ASCEND (CAiRE/ASCEND, CC BY-SA 4.0) test and validation splits, utterances labelled
    `mixed`, deterministic selection. Parquets are downloaded at a pinned
    Hugging Face revision and their SHA-256 digests are checked before use.
(b) Taiwan-style synthetic sentences (taiwan_synthetic.json) spoken by macOS
    `say` zh_TW voices. Synthetic TTS is a weak proxy for real speech.

Audio stays under --work. Only manifest.json is written into the repository.
"""
import argparse, hashlib, json, pathlib, re, subprocess, sys, urllib.request

HERE = pathlib.Path(__file__).resolve().parent
REVISION = "737e9800ae31be9932ba8464c80366559bd28424"
SPLITS = {  # held-out splits only; digests checked before use
    "test": ("test-00000-of-00001.parquet", "a4c81d2b5ed6124f052089a695972808c16e0ce0c365ec9773c5d1a8fcf043a7"),
    "validation": ("validation-00000-of-00001.parquet", "3bdec53d2abfd3dd4f0d86a6df4e27e60f20660edc9b66055ae0ef8ec05cf7e2"),
}
VOICES = ["Meijia", "Flo (Chinese (Taiwan))", "Eddy (Chinese (Taiwan))", "Reed (Chinese (Taiwan))"]
TARGET = 100
MAX_PER_SPEAKER = 25


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def ascend(work):
    import pyarrow.parquet as pq
    dl = work / "dl" / "ascend"
    dl.mkdir(parents=True, exist_ok=True)
    candidates = []
    for split, (name, digest) in SPLITS.items():
        parquet = dl / f"{split}.parquet"
        if not parquet.exists():
            urllib.request.urlretrieve(f"https://huggingface.co/datasets/CAiRE/ASCEND/resolve/{REVISION}/main/{name}", parquet)
        if sha256(parquet) != digest:
            sys.exit(f"ASCEND {split} parquet digest mismatch")
        for row in pq.read_table(parquet).to_pylist():
            text = row["transcription"]
            cjk = len(re.findall(r"[㐀-鿿]", text))
            latin = re.findall(r"[A-Za-z][A-Za-z']*", text)
            # Real code-switching: at least 4 Han characters and one English word,
            # long enough to be a dictation-like phrase (2.5-15 s).
            if row["language"] == "mixed" and cjk >= 4 and latin and 2.5 <= row["duration"] <= 15:
                row["split"] = split
                candidates.append(row)
    # Deterministic, speaker-spread selection: order by SHA-256 of split/ID.
    candidates.sort(key=lambda r: hashlib.sha256(f"{r['split']}/{r['id']}".encode()).hexdigest())
    picked, per_speaker = [], {}
    for row in candidates:
        speaker = row["original_speaker_id"]
        if per_speaker.get(speaker, 0) >= MAX_PER_SPEAKER:
            continue
        per_speaker[speaker] = per_speaker.get(speaker, 0) + 1
        picked.append(row)
        if len(picked) == TARGET:
            break
    out = work / "audio" / "ascend"
    out.mkdir(parents=True, exist_ok=True)
    items = []
    for row in sorted(picked, key=lambda r: (r["split"], r["id"])):
        uid = f"ascend-{row['split'][:3]}-{row['id']}"
        wav = out / f"{uid}.wav"
        wav.write_bytes(row["audio"]["bytes"])
        items.append({
            "id": uid, "corpus": "ascend", "split": row["split"], "row_id": row["id"], "reference": row["transcription"],
            "duration": round(row["duration"], 3), "session": row["session_id"],
            "speaker": row["original_speaker_id"], "topic": row["topic"],
            "source_file": pathlib.PurePosixPath(row["path"]).name, "audio_sha256": sha256(wav),
        })
    return items, len(candidates)


def synthetic(work, corpus, voices, prefix):
    out = work / "audio" / corpus
    out.mkdir(parents=True, exist_ok=True)
    items = []
    for index, entry in enumerate(json.loads((HERE / "taiwan_synthetic.json").read_text())):
        voice = voices[index % len(voices)]
        uid = prefix + entry["id"][2:]
        wav = out / f"{uid}.wav"
        subprocess.run(["/usr/bin/say", "-v", voice, "--file-format=WAVE", "--data-format=LEI16@16000",
                        "-o", str(wav), entry["text"]], check=True)
        info = subprocess.run(["/usr/bin/afinfo", str(wav)], capture_output=True, text=True).stdout
        duration = float(re.search(r"estimated duration: ([0-9.]+)", info).group(1))
        items.append({"id": uid, "corpus": corpus, "reference": entry["text"], "voice": voice,
                      "duration": round(duration, 3), "audio_sha256": sha256(wav)})
    return items


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--work", required=True, type=pathlib.Path)
    args = parser.parse_args()
    a, pool = ascend(args.work)
    # tw-tts rotates four zh_TW voices; Flo/Eddy/Reed render English words poorly,
    # so tw-tts-meijia repeats the same sentences with the Meijia voice only.
    t = synthetic(args.work, "tw-tts", VOICES, "tw") + synthetic(args.work, "tw-tts-meijia", ["Meijia"], "twm")
    manifest = {
        "ascend": {"dataset": "CAiRE/ASCEND", "revision": REVISION, "splits": {k: v[1] for k, v in SPLITS.items()},
                   "license": "CC BY-SA 4.0",
                   "selection": f"language=mixed, >=4 Han chars, >=1 English word, 2.5-15 s; "
                                f"sorted by sha256(split/id); max {MAX_PER_SPEAKER} per speaker; first {TARGET}",
                   "candidate_pool": pool,
                   "note": "References are the dataset's Simplified Chinese transcriptions (Mainland/HK speakers)."},
        "tw_tts": {"source": "eval/mixed-asr/taiwan_synthetic.json", "voices": VOICES, "corpora": {"tw-tts": "voices rotated per sentence", "tw-tts-meijia": "Meijia only"},
                   "macos": subprocess.run(["/usr/bin/sw_vers", "-productVersion"], capture_output=True, text=True).stdout.strip(),
                   "note": "macOS say zh_TW voices, 16 kHz mono PCM. Synthetic TTS is a weak proxy for real speakers."},
        "items": a + t,
    }
    (HERE / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=1) + "\n")
    print(f"ascend {len(a)} (pool {pool}), synthetic {len(t)}")


if __name__ == "__main__":
    main()
