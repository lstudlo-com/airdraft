#!/usr/bin/env python3
"""Build the AD-083 English, Japanese and Korean corpus under a scratch directory.

  python3 -I eval/eja-asr/prepare_corpus.py --work /tmp/airdraft-wave/ad083

Source: Google FLEURS (google/fleurs, CC BY 4.0), test split of en_us, ja_jp and
ko_kr, as the Hub's parquet conversion at a pinned revision. Each parquet's
SHA-256 is checked before use.

Selection, per language (deterministic, no model output involved):
  1. keep recordings of 2-20 s (Airdraft's Whisper windows are at most 25 s);
  2. one recording per FLEURS sentence: the lowest sha256(lang/path);
  3. order sentences by sha256(lang/sentence id) and take the first PER_LANGUAGE,
     with at most MAX_SHARE of them from one gender.
FLEURS publishes no speaker IDs, so speaker spread cannot be controlled.

Audio stays under --work; only manifest.json is written into the repository.
"""
import argparse, hashlib, json, pathlib, sys, urllib.request

HERE = pathlib.Path(__file__).resolve().parent
REVISION = "70bb2e84b976b7e960aa89f1c648e09c59f894dd"
PARQUETS = {  # test split only; LFS SHA-256 digests from the Hub at REVISION
    "en_us": "6428a4d04d3aac29e16b45e039bb1470a8bd7aa334cf92f7984c9c520d1f234d",
    "ja_jp": "e954b67e934b9a31d7a74a070a75225379660d50c8d1aacdb755852c57f23e6b",
    "ko_kr": "1a8319fc61c7996e8c15acde633786de97054e28ae1e463eb13901716176a7ec",
}
PER_LANGUAGE = 60
MAX_SHARE = 0.6
MIN_SECONDS, MAX_SECONDS = 2.0, 20.0


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def key(text):
    return hashlib.sha256(text.encode()).hexdigest()


def select(rows, lang):
    by_sentence = {}
    for row in rows:
        seconds = row["num_samples"] / 16000
        if not MIN_SECONDS <= seconds <= MAX_SECONDS:
            continue
        current = by_sentence.get(row["id"])
        if current is None or key(f"{lang}/{row['path']}") < key(f"{lang}/{current['path']}"):
            by_sentence[row["id"]] = row
    ordered = sorted(by_sentence.values(), key=lambda r: key(f"{lang}/{r['id']}"))
    picked, genders = [], {}
    for row in ordered:
        if genders.get(row["gender"], 0) >= MAX_SHARE * PER_LANGUAGE:
            continue
        genders[row["gender"]] = genders.get(row["gender"], 0) + 1
        picked.append(row)
        if len(picked) == PER_LANGUAGE:
            break
    return picked, len(by_sentence)


def main():
    import pyarrow.parquet as pq
    parser = argparse.ArgumentParser()
    parser.add_argument("--work", required=True, type=pathlib.Path)
    args = parser.parse_args()
    dl = args.work / "dl" / "fleurs"
    dl.mkdir(parents=True, exist_ok=True)
    items, pools = [], {}
    for lang, digest in PARQUETS.items():
        parquet = dl / f"{lang}-test.parquet"
        if not parquet.exists():
            urllib.request.urlretrieve(
                f"https://huggingface.co/datasets/google/fleurs/resolve/{REVISION}/parquet-data/{lang}/test-00000-of-00001.parquet",
                parquet)
        if sha256(parquet) != digest:
            sys.exit(f"FLEURS {lang} parquet digest mismatch")
        rows = pq.read_table(parquet).to_pylist()
        picked, pools[lang] = select(rows, lang)
        out = args.work / "audio" / lang
        out.mkdir(parents=True, exist_ok=True)
        for row in sorted(picked, key=lambda r: r["id"]):
            uid = f"{lang[:2]}-{row['id']}"
            wav = out / f"{uid}.wav"
            wav.write_bytes(row["audio"]["bytes"])
            items.append({
                "id": uid, "corpus": lang, "language": lang[:2], "fleurs_id": row["id"],
                "source_file": pathlib.PurePosixPath(row["path"]).name,
                "reference": row["raw_transcription"], "reference_normalized_by_fleurs": row["transcription"],
                "gender": row["gender"], "duration": round(row["num_samples"] / 16000, 3),
                "audio_sha256": sha256(wav),
            })
    manifest = {
        "dataset": "google/fleurs", "revision": REVISION, "split": "test", "parquets": PARQUETS,
        "license": "CC BY 4.0",
        "attribution": "FLEURS: Conneau et al., 'FLEURS: Few-shot Learning Evaluation of Universal Representations of Speech', "
                       "SLT 2022. https://huggingface.co/datasets/google/fleurs. Transcriptions reproduced under CC BY 4.0.",
        "selection": f"{MIN_SECONDS:g}-{MAX_SECONDS:g} s; one recording per sentence (lowest sha256(lang/path)); "
                     f"sentences sorted by sha256(lang/id); first {PER_LANGUAGE}, at most {MAX_SHARE:.0%} one gender",
        "sentence_pool": pools,
        "note": "Read Wikipedia sentences (FLoRes-101), not dictation. FLEURS publishes no speaker IDs. "
                "gender is the dataset's 0/1 field. reference is raw_transcription (cased, punctuated).",
        "items": items,
    }
    (HERE / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=1) + "\n")
    print({lang: sum(i["corpus"] == lang for i in items) for lang in PARQUETS}, "pools", pools)


if __name__ == "__main__":
    main()
