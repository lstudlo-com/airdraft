#!/usr/bin/env python3
"""Build the AD-098 seven-language corpus under a scratch directory.

  python3 -I eval/intl-asr/prepare_corpus.py --work dist/intl-asr-work

Same source and selection rule as eval/eja-asr (AD-083): Google FLEURS
(google/fleurs, CC BY 4.0), test split, the Hub's parquet conversion at the same
pinned revision. Each parquet's SHA-256 (the Hub's LFS digest at REVISION) is
checked before use.

Configs: es_419 (Latin American Spanish), fr_fr, pt_br, ru_ru, ar_eg (Egyptian
Arabic speakers reading Modern Standard Arabic), hi_in, id_id.

Selection, per language (deterministic, no model output involved):
  1. keep recordings of 2-20 s (Airdraft's Whisper windows are at most 25 s);
  2. one recording per FLEURS sentence: the lowest sha256(lang/path);
  3. order sentences by sha256(lang/sentence id) and take the first PER_LANGUAGE,
     with at most MAX_SHARE of them from one gender. The pt_br, ar_eg and id_id
     test splits contain a single gender value, so the cap is lifted there.
FLEURS publishes no speaker IDs, so speaker spread cannot be controlled.

Audio stays under --work (outside git); only manifest.json is written into the
repository.
"""
import argparse, hashlib, json, pathlib, subprocess, sys, urllib.error, urllib.request

HERE = pathlib.Path(__file__).resolve().parent
REVISION = "70bb2e84b976b7e960aa89f1c648e09c59f894dd"
PARQUETS = {  # test split only; LFS SHA-256 digests from the Hub at REVISION (checked 2026-10-25)
    "es_419": "f1e8b7f6eecb91d16b79d91bc1838d8b0e5ebc0b37b317e2b58eb8694c64d3c0",
    "fr_fr": "99a08ff00edbc7b6f040e23b33e49bc4a1fce38f364d50c603227d612fd797ef",
    "pt_br": "dde5da617c30a9c88703f1095077bc1e263c31190f76d613ba31bdc57602ff49",
    "ru_ru": "1e5bbee150c05a219c6c318e95d765886d34b4d179e8ab06dbecdb2791ac9a5d",
    "ar_eg": "3386d58ff9619c2b1395dcaed0a476363fae15420bc68b7ca4870cffdff9936d",
    "hi_in": "8a0be26c5584c1478233a6f47fb90275c713f72565327ea1da76c9f1cd5dd38b",
    "id_id": "910017ff324772fdd6fac9c859255b867d90066f098d2b5db6dbab6c530dd7d8",
}
# Airdraft language code (and utterance ID prefix) per FLEURS config.
LANGUAGE = {"es_419": "es", "fr_fr": "fr", "pt_br": "pt", "ru_ru": "ru", "ar_eg": "ar", "hi_in": "hi", "id_id": "id"}
PER_LANGUAGE = 40
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
    # pt_br, ar_eg and id_id test recordings carry a single gender value, so the
    # cap cannot apply there; it is lifted only when the pool has one gender.
    capped = len({row["gender"] for row in ordered}) > 1
    picked, genders = [], {}
    for row in ordered:
        if capped and genders.get(row["gender"], 0) >= MAX_SHARE * PER_LANGUAGE:
            continue
        genders[row["gender"]] = genders.get(row["gender"], 0) + 1
        picked.append(row)
        if len(picked) == PER_LANGUAGE:
            break
    return picked, {"sentences": len(by_sentence), "genders": sorted({row["gender"] for row in ordered}), "capped": capped}


def main():
    import pyarrow.parquet as pq
    parser = argparse.ArgumentParser()
    parser.add_argument("--work", required=True, type=pathlib.Path)
    parser.add_argument("--download-only", action="store_true", help="fetch and check the parquets, write nothing else")
    args = parser.parse_args()
    dl = args.work / "dl" / "fleurs"
    dl.mkdir(parents=True, exist_ok=True)
    items, pools = [], {}
    for lang, digest in PARQUETS.items():
        parquet = dl / f"{lang}-test.parquet"
        if not parquet.exists():
            partial = parquet.with_suffix(".part")
            url = f"https://huggingface.co/datasets/google/fleurs/resolve/{REVISION}/parquet-data/{lang}/test-00000-of-00001.parquet"
            try:
                urllib.request.urlretrieve(url, partial)
            except urllib.error.URLError:
                # python.org builds may lack a CA bundle; the digest check below still applies.
                subprocess.run(["/usr/bin/curl", "-sSfL", "-o", str(partial), url], check=True)
            partial.rename(parquet)
        if sha256(parquet) != digest:
            sys.exit(f"FLEURS {lang} parquet digest mismatch")
        print(lang, "parquet ok", flush=True)
        if args.download_only:
            continue
        rows = pq.read_table(parquet, columns=["id", "num_samples", "path", "audio", "transcription",
                                               "raw_transcription", "gender"]).to_pylist()
        picked, pools[lang] = select(rows, lang)
        out = args.work / "audio" / lang
        out.mkdir(parents=True, exist_ok=True)
        for row in sorted(picked, key=lambda r: r["id"]):
            uid = f"{LANGUAGE[lang]}-{row['id']}"
            wav = out / f"{uid}.wav"
            wav.write_bytes(row["audio"]["bytes"])
            items.append({
                "id": uid, "corpus": lang, "language": LANGUAGE[lang], "fleurs_id": row["id"],
                "source_file": pathlib.PurePosixPath(row["path"]).name,
                "reference": row["raw_transcription"], "reference_normalized_by_fleurs": row["transcription"],
                "gender": row["gender"], "duration": round(row["num_samples"] / 16000, 3),
                "audio_sha256": sha256(wav),
            })
    if args.download_only:
        return
    manifest = {
        "dataset": "google/fleurs", "revision": REVISION, "split": "test", "parquets": PARQUETS,
        "license": "CC BY 4.0",
        "attribution": "FLEURS: Conneau et al., 'FLEURS: Few-shot Learning Evaluation of Universal Representations of Speech', "
                       "SLT 2022. https://huggingface.co/datasets/google/fleurs. Transcriptions reproduced under CC BY 4.0.",
        "selection": f"{MIN_SECONDS:g}-{MAX_SECONDS:g} s; one recording per sentence (lowest sha256(lang/path)); "
                     f"sentences sorted by sha256(lang/id); first {PER_LANGUAGE}, at most {MAX_SHARE:.0%} one gender "
                     "(not applicable where the test split has one gender value: pt_br, ar_eg, id_id)",
        "sentence_pool": pools,
        "note": "Read Wikipedia sentences (FLoRes-101), not dictation. FLEURS publishes no speaker IDs. "
                "gender is the dataset's 0/1 field. reference is raw_transcription (cased, punctuated).",
        "items": items,
    }
    (HERE / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=1) + "\n")
    print({lang: sum(i["corpus"] == lang for i in items) for lang in PARQUETS}, "pools", pools)


if __name__ == "__main__":
    main()
