#!/usr/bin/env python3
"""Generate the AD-081 vocabulary-bias audio with macOS `say` (no network).

  python3 -I eval/vocab-bias/prepare_corpus.py --work /tmp/airdraft-wave/vocab

Writes <work>/audio/<id>.wav (16 kHz mono 16-bit) and <work>/audio/hashes.json.
Speech items may be attenuated (gain_db) or append low-noise trailing silence; silence items are
low-level deterministic noise, so the pipeline's empty-capture check does not
short-circuit them before speech recognition.
"""
import argparse, array, hashlib, json, math, pathlib, random, subprocess, wave

HERE = pathlib.Path(__file__).resolve().parent


def read_pcm(path):
    with wave.open(str(path)) as source:
        assert source.getframerate() == 16000 and source.getnchannels() == 1 and source.getsampwidth() == 2
        return array.array("h", source.readframes(source.getnframes()))


def write_pcm(path, samples):
    with wave.open(str(path), "wb") as target:
        target.setnchannels(1); target.setsampwidth(2); target.setframerate(16000)
        target.writeframes(samples.tobytes())


def noise(seconds, dbfs, seed):
    rng = random.Random(seed)
    amplitude = 32767 * math.pow(10, dbfs / 20)
    return array.array("h", (int(rng.gauss(0, amplitude)) for _ in range(int(seconds * 16000))))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--work", required=True, type=pathlib.Path)
    args = parser.parse_args()
    corpus = json.loads((HERE / "corpus.json").read_text())
    out = args.work / "audio"
    out.mkdir(parents=True, exist_ok=True)
    hashes = {}
    for item in corpus["items"]:
        aiff, wav = out / f"{item['id']}.aiff", out / f"{item['id']}.wav"
        subprocess.run(["say", "-v", corpus["voices"][item["language"]], "-o", str(aiff), item["text"]], check=True)
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", str(aiff), str(wav)], check=True)
        aiff.unlink()
        if item.get("gain_db"):
            # Quiet speech (about -42 dBFS RMS) stays above the -50 dBFS silence gate.
            factor = math.pow(10, item["gain_db"] / 20)
            write_pcm(wav, array.array("h", (int(x * factor) for x in read_pcm(wav))))
        if item.get("trailing_silence_s"):
            samples = read_pcm(wav)
            samples.extend(noise(item["trailing_silence_s"], -60, item["id"]))
            write_pcm(wav, samples)
        hashes[item["id"]] = hashlib.sha256(wav.read_bytes()).hexdigest()
    for item in corpus["silence"]:
        wav = out / f"{item['id']}.wav"
        write_pcm(wav, noise(item["seconds"], item["noise_dbfs"], item["id"]))
        hashes[item["id"]] = hashlib.sha256(wav.read_bytes()).hexdigest()
    (out / "hashes.json").write_text(json.dumps(hashes, indent=1, sort_keys=True))
    print(f"{len(hashes)} files in {out}")


if __name__ == "__main__":
    main()
