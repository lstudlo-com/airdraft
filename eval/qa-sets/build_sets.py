#!/usr/bin/env python3
"""Build Airdraft's internal QA speech sets (AD-114).

  uv run --with pyarrow,soundfile,numpy python -I eval/qa-sets/build_sets.py \
      --cache <download dir> --out <dataset dir>

One SET per language (zh, en, ja, es), six clips each:
  single-1..3   one speaker (short, medium, long dictation-length read speech)
  small-1..2    two or three speakers (small-1 exactly 2, small-2 exactly 3)
  group-1       four or more speakers

Every source is a public benchmark corpus pinned to a revision and SHA-256.
Clips are chosen by the deterministic rules below, never by model output.
Writes <out>/<lang>/<clip>.wav (16 kHz mono PCM16), <out>/<lang>/<clip>.json
(speaker-attributed reference) and <out>/manifest.json. Audio and transcripts
stay out of the repository (licences differ, see README.md); digests.json in
this folder pins what a build must produce. --check compares against it,
--update-digests rewrites it.
"""
import argparse, hashlib, html, io, json, pathlib, re, shutil, subprocess, sys, tarfile, zipfile
import xml.etree.ElementTree as ET

HERE = pathlib.Path(__file__).resolve().parent
RATE = 16000

HF = "https://huggingface.co/datasets"
SOURCES = {
    "librispeech": {
        "url": f"{HF}/openslr/librispeech_asr/resolve/71cacbfb7e2354c4226d01e70d77d5fca3d04ba1/all/test.clean/0000.parquet",
        "file": "librispeech-test-clean.parquet",
        "dataset": "LibriSpeech test-clean",
        "license": "CC BY 4.0",
        "attribution": "Panayotov et al., LibriSpeech: an ASR corpus based on public domain audio books, ICASSP 2015. openslr.org/12",
    },
    "aishell1": {
        "url": f"{HF}/AudioLLMs/aishell_1_zh_test/resolve/e73dc7f096ecea5c8e5c722446c8d3b4014fdd18/data/test-00000-of-00003.parquet",
        "file": "aishell1-test-0.parquet",
        "dataset": "AISHELL-1 test (AudioLLMs parquet mirror; IDs recovered from the official transcript)",
        "license": "Apache 2.0",
        "attribution": "Bu et al., AISHELL-1: An Open-Source Mandarin Speech Corpus and A Speech Recognition Baseline, O-COCOSDA 2017. openslr.org/33",
    },
    "aishell1_transcript": {
        "url": f"{HF}/AISHELL/AISHELL-1/resolve/bbe295d530192a4cd41644b711c9aecd087df653/data_aishell/transcript/aishell_transcript_v0.8.txt",
        "file": "aishell_transcript_v0.8.txt",
    },
    "fleurs_ja": {
        "url": f"{HF}/google/fleurs/resolve/70bb2e84b976b7e960aa89f1c648e09c59f894dd/parquet-data/ja_jp/test-00000-of-00001.parquet",
        "file": "fleurs-ja_jp-test.parquet",
        "dataset": "FLEURS ja_jp test",
        "license": "CC BY 4.0",
        "attribution": "Conneau et al., FLEURS: Few-shot Learning Evaluation of Universal Representations of Speech, SLT 2022",
    },
    "mls_es_transcripts": {
        "url": f"{HF}/facebook/multilingual_librispeech/resolve/2e83e61823b4c47dcbcb1980bb88601274127609/data/mls_spanish/test/transcripts.txt",
        "file": "mls-es-test-transcripts.txt",
        "dataset": "Multilingual LibriSpeech Spanish test",
        "license": "CC BY 4.0",
        "attribution": "Pratap et al., MLS: A Large-Scale Multilingual Dataset for Speech Research, Interspeech 2020. openslr.org/94",
    },
    "mls_es_segments": {
        "url": f"{HF}/facebook/multilingual_librispeech/resolve/2e83e61823b4c47dcbcb1980bb88601274127609/data/mls_spanish/test/segments.txt",
        "file": "mls-es-test-segments.txt",
    },
    "voxpopuli_es": {
        "url": f"{HF}/facebook/voxpopuli/resolve/42f01879c780b4a2e90ec0b4f616c2ece526e4f1/es/test-00000-of-00001.parquet",
        "file": "voxpopuli-es-test.parquet",
        "dataset": "VoxPopuli Spanish transcribed test",
        "license": "CC0 1.0 (European Parliament recordings, re-use per EP legal notice)",
        "attribution": "Wang et al., VoxPopuli: A Large-Scale Multilingual Speech Corpus, ACL 2021",
    },
    "ami_annotations": {
        "url": "https://groups.inf.ed.ac.uk/ami/AMICorpusAnnotations/ami_public_manual_1.6.2.zip",
        "file": "ami_public_manual_1.6.2.zip",
        "dataset": "AMI Meeting Corpus (manual annotations 1.6.2, Mix-Headset audio)",
        "license": "CC BY 4.0",
        "attribution": "Carletta et al., The AMI Meeting Corpus: A Pre-Announcement, MLMI 2005. groups.inf.ed.ac.uk/ami",
    },
    "aishell4": {
        "dataset": "AISHELL-4 test (first far-field array channel)",
        "license": "CC BY-SA 4.0 (openslr.org/111; Apache 2.0 on the Hub mirror)",
        "attribution": "Fu et al., AISHELL-4: An Open Source Dataset for Speech Enhancement, Separation, Recognition and Speaker Diarization in Conference Scenario, Interspeech 2021",
    },
    "callhome_ja": {
        "dataset": "CABank CallHome Japanese (TalkBank)",
        "license": "CC BY-NC-SA 3.0 (TalkBank ground rules; internal evaluation only)",
        "attribution": "MacWhinney & Wagner, Transcribing, searching and data sharing: The CLAN software and the TalkBank data repository, 2010. doi:10.21415/T5H59V",
    },
    "sakura": {
        "dataset": "CABank Japanese Sakura Corpus (TalkBank)",
        "license": "CC BY-NC-SA 3.0 (TalkBank ground rules; internal evaluation only)",
        "attribution": "Miyata, CABank Sakura Corpus. doi:10.21415/T5M90R",
    },
}

AMI_AUDIO = "https://groups.inf.ed.ac.uk/ami/AMICorpusMirror/amicorpus/{m}/audio/{m}.Mix-Headset.wav"
A4 = f"{HF}/AISHELL/AISHELL-4/resolve/aada72727856313b19d4a030383c426364931dbf/test"
CH = f"{HF}/Fhrozen/CABankSakuraCHJP/resolve/208ae52187c393a222ee77605d94ec3e033d7e92/dummy"
SK = f"{HF}/Fhrozen/CABankSakura/resolve/5b7594b2d1e6a6a63df63bbc943409112acf0377/dummy"
MLS_AUDIO = HF + "/facebook/multilingual_librispeech/resolve/2e83e61823b4c47dcbcb1980bb88601274127609/data/mls_spanish/test/audio/{key}.tar.gz"

# SHA-256 of every fetched file and every built clip (written by --update-digests).
DIGESTS_FILE = HERE / "digests.json"

# Single-speaker duration bands (seconds): short, medium, long.
BANDS = {
    "librispeech": [(4, 8), (9, 15), (16, 35)],
    "aishell1": [(3, 6), (7, 10), (11, 15)],
    "fleurs_ja": [(4, 8), (9, 15), (16, 30)],
    "mls_es": [(10, 12), (13, 16), (17, 20)],
}

# Conversation windows: (source, recording, speaker rule, min/max seconds, skip seconds).
# "exact:N" = exactly N people speak in the window; "atleast:N" = N or more, each
# with at least MIN_SPEECH seconds of speech. Windows start and end in silence.
WINDOWS = {
    "en": {"small-1": ("ami", "ES2004c", "exact:2", 45, 120, 60),
           "small-2": ("ami", "IS1009b", "exact:3", 45, 120, 60),
           "group-1": ("ami", "TS3003c", "atleast:4", 120, 240, 60)},
    "zh": {"small-1": ("aishell4", "S_R004S01C01", "exact:2", 45, 120, 60),
           "small-2": ("aishell4", "M_R003S01C01", "exact:3", 45, 120, 60),
           "group-1": ("aishell4", "L_R003S01C02", "atleast:4", 120, 240, 60)},
    "ja": {"small-1": ("callhome_ja", "0696", "exact:2", 45, 120, 0),
           "small-2": ("callhome_ja", None, "exact:3", 45, 120, 0),
           "group-1": ("sakura", "sakura05", "atleast:4", 120, 240, 60)},
}
MIN_SPEECH = 3.0
MIN_GAP = 0.2
PAD = 0.5

# VoxPopuli: real plenary speeches from one session, joined in session order
# with GAP seconds of silence (stitched, not a continuous recording).
VOXPOPULI = {
    "small-1": ("20090505-0900-PLENARY-3-es", 2),
    "small-2": ("20090203-0900-PLENARY-13-es", 3),
    "group-1": ("20180612-0900-PLENARY-es", 4),
}
VOX_PER_SPEAKER = (2, 3)  # segments per speaker for small, group
VOX_GAP = 0.6
VOX_SKIP = {"20180612-13:40:09_0"}  # speaker-gender metadata contradicts the rest of that speech

CJK = {"zh", "ja"}


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def key(text):
    return hashlib.sha256(text.encode()).hexdigest()


def fetch(url, dest):
    if not dest.exists():
        dest.parent.mkdir(parents=True, exist_ok=True)
        part = dest.with_name(dest.name + ".part")
        subprocess.run(["curl", "-sSLf", "--retry", "3", "-o", str(part), url], check=True)
        part.rename(dest)
    return dest


class Fetcher:
    def __init__(self, cache, pins):
        self.cache, self.pins, self.seen = cache, pins, {}

    def get(self, url, name):
        path = fetch(url, self.cache / name)
        digest = sha256(path)
        pinned = self.pins.get(name)
        if pinned and pinned != digest:
            sys.exit(f"digest mismatch for {name}: {digest} != pinned {pinned}")
        self.seen[name] = digest
        return path

    def source(self, sid):
        s = SOURCES[sid]
        return self.get(s["url"], s["file"])


def ffmpeg_cut(src, dest, start=None, end=None, channel=None, data=None):
    cmd = ["ffmpeg", "-v", "error", "-nostdin", "-y"]
    if start is not None:
        cmd += ["-ss", f"{start:.3f}"]
    if end is not None:
        cmd += ["-to", f"{end:.3f}"]
    cmd += ["-i", "pipe:0" if data is not None else str(src)]
    if channel is not None:
        cmd += ["-af", f"pan=mono|c0=c{channel}"]
    cmd += ["-ac", "1", "-ar", str(RATE), "-c:a", "pcm_s16le", "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact", str(dest)]
    subprocess.run(cmd, input=data, check=True)


def wav_seconds(path):
    import soundfile as sf
    return sf.info(str(path)).frames / RATE


def join(texts, lang):
    texts = [t for t in texts if t]
    return ("" if lang in CJK else " ").join(texts)


# ---------- single speaker ----------

def pick_single(items, bands):
    """items: (id, speaker, seconds, payload). One per band, distinct speakers, sha256 order."""
    out, speakers = [], set()
    for lo, hi in bands:
        for it in sorted(items, key=lambda x: key(x[0])):
            if lo <= it[2] <= hi and it[1] not in speakers:
                out.append(it)
                speakers.add(it[1])
                break
        else:
            sys.exit(f"no item in band {lo}-{hi}")
    return out


def singles_librispeech(f):
    import pyarrow.parquet as pq, soundfile as sf
    rows = pq.read_table(f.source("librispeech")).to_pylist()
    items = [(r["id"], r["speaker_id"], sf.info(io.BytesIO(r["audio"]["bytes"])).duration, (r["audio"]["bytes"], r["text"])) for r in rows]
    return [(i, str(s), b, t) for i, s, _, (b, t) in pick_single(items, BANDS["librispeech"])]


def singles_aishell1(f):
    import pyarrow.parquet as pq, soundfile as sf
    ref = {}
    for line in open(f.source("aishell1_transcript"), encoding="utf-8"):
        k, v = line.strip().split(None, 1)
        if 764 <= int(k[7:11]) <= 916:  # test speakers S0764-S0916
            ref.setdefault(v.replace(" ", ""), []).append(k)
    rows = pq.read_table(f.source("aishell1"), columns=["context", "answer"]).to_pylist()
    items = []
    for r in rows:
        ids = ref.get(r["answer"].replace(" ", ""), [])
        if len(ids) == 1:  # skip sentences read by more than one speaker
            b = r["context"]["bytes"]
            items.append((ids[0], ids[0][6:11], sf.info(io.BytesIO(b)).duration, (b, r["answer"].replace(" ", ""))))
    return [(i, s, b, t) for i, s, _, (b, t) in pick_single(items, BANDS["aishell1"])]


def singles_fleurs_ja(f):
    import pyarrow.parquet as pq
    rows = pq.read_table(f.source("fleurs_ja")).to_pylist()
    items = []
    for r in rows:
        name = r["path"].rsplit("/", 1)[-1]
        # FLEURS publishes no speaker IDs; one recording per sentence keeps sentences distinct.
        items.append((f"ja_jp/{r['id']}/{name}", f"sentence-{r['id']}", r["num_samples"] / RATE, (r["audio"]["bytes"], r["raw_transcription"])))
    return [(i, s, b, t) for i, s, _, (b, t) in pick_single(items, BANDS["fleurs_ja"])]


def singles_mls_es(f):
    seconds = {}
    for line in open(f.source("mls_es_segments"), encoding="utf-8"):
        k, _, a, b = line.rstrip("\n").split("\t")
        seconds[k] = float(b) - float(a)
    items = []
    for line in open(f.source("mls_es_transcripts"), encoding="utf-8"):
        k, text = line.rstrip("\n").split("\t", 1)
        items.append((k, k.split("_")[0], seconds[k], text))
    out = []
    for k, spk, _, text in pick_single(items, BANDS["mls_es"]):
        book = "_".join(k.split("_")[:2])
        tar = f.get(MLS_AUDIO.format(key=f"{book}_000"), f"mls-es/{book}_000.tar.gz")
        with tarfile.open(tar) as t:
            member = next(m for m in t.getmembers() if m.name.endswith(f"{k}.opus") or m.name.endswith(f"{k}.flac"))
            data = t.extractfile(member).read()
        out.append((k, spk, data, text))
    return out


SINGLES = {"en": ("librispeech", singles_librispeech), "zh": ("aishell1", singles_aishell1),
           "ja": ("fleurs_ja", singles_fleurs_ja), "es": ("mls_es_transcripts", singles_mls_es)}


# ---------- conversations: segment readers ----------

def ami_segments(f, meeting):
    z = zipfile.ZipFile(f.source("ami_annotations"))
    segs = []
    for name in sorted(n for n in z.namelist() if n.startswith(f"words/{meeting}.") and n.endswith(".words.xml")):
        spk = name.split(".")[1]
        words = []
        for w in ET.fromstring(z.read(name)):
            if w.tag != "w" or w.get("starttime") is None:
                continue
            text = re.sub(r"\b((?:[A-Za-z]_)+)", lambda m: m.group(1).replace("_", ""), w.text or "")  # AMI spells letters L_C_D_
            words.append((float(w.get("starttime")), float(w.get("endtime")), text, w.get("punc") == "true"))
        cur = None
        for s, e, t, punc in words:
            if cur and (punc or s - cur["end"] <= 1.0):
                cur["text"] += t if punc else " " + t
                cur["end"] = max(cur["end"], e)
                continue
            if punc:
                continue
            cur = {"speaker": spk, "start": s, "end": e, "text": t}
            segs.append(cur)
    return sorted(segs, key=lambda x: (x["start"], x["speaker"]))


def textgrid_tiers(text):
    tiers, name, cur = [], None, {}
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("name ="):
            name = line.split("=", 1)[1].strip().strip('"')
            tiers.append((name, []))
        elif line.startswith("xmin =") and tiers:
            cur = {"start": float(line.split("=")[1])}
        elif line.startswith("xmax =") and tiers and "start" in cur:
            cur["end"] = float(line.split("=")[1])
        elif line.startswith("text =") and tiers:
            cur["text"] = line.split("=", 1)[1].strip().strip('"')
            tiers[-1][1].append(cur)
            cur = {}
    return tiers


def clean_aishell4(t):
    t = re.sub(r"<[^>]*>", "", t)
    t = re.sub(r"[\[\]&]", "", t)  # &呃& marks a filler; keep the filler
    return t.replace(" ", "").strip()


def aishell4_segments(f, meeting):
    tg = f.get(f"{A4}/TextGrid/{meeting}.TextGrid", f"aishell4/{meeting}.TextGrid").read_text(encoding="utf-8")
    segs = []
    for name, intervals in textgrid_tiers(tg):
        for iv in intervals:
            text = clean_aishell4(iv.get("text", ""))
            if text:
                segs.append({"speaker": name, "start": iv["start"], "end": iv["end"], "text": text})
    return sorted(segs, key=lambda x: (x["start"], x["speaker"]))


BULLET = re.compile("\x15(\\d+)_(\\d+)\x15")


def chat_utterances(text):
    """Yield (speaker, main line, {tier: text}, bullet or None) from a CHAT file."""
    lines, out = [], []
    for raw in text.splitlines():
        if raw.startswith("\t") and lines:
            lines[-1] += " " + raw.strip()
        else:
            lines.append(raw)
    cur = None
    for line in lines:
        if line.startswith("*"):
            spk, body = line[1:].split(":", 1)
            m = BULLET.search(body)
            cur = [spk, BULLET.sub("", body).strip(), {}, (int(m.group(1)) / 1000, int(m.group(2)) / 1000) if m else None]
            out.append(cur)
        elif line.startswith("%") and cur:
            tier, body = line[1:].split(":", 1)
            cur[2][tier] = BULLET.sub("", body).strip()
    return out


def clean_callhome(t):
    t = re.sub(r"\[:[^\]]*\]", "", t)            # standardized form; keep what was said
    t = re.sub(r"\[[^\]]*\]", "", t)             # retracing, overlaps, comments
    t = re.sub(r"&[=\-+~*]?\S*", "", t)          # events, fillers marked as fragments
    t = re.sub(r"\bxxx\b|\byyy\b|\bwww\b", "", t)
    t = re.sub(r"[<>⇘⇗→↗↘↑↓≈≋∬∙⌈⌉⌊⌋°“”„‡+^/]", "", t)
    t = re.sub(r"\(\.+\)", "", t)
    t = re.sub(r"(?<=[^\x00-\x7f]) +|(?<=[\x00-\x7f]) +(?=[^\x00-\x7f])", "", t)
    return t.strip(" ,.")


def clean_sakura(t):
    t = re.sub(r"[(（][^)）]*[)）]", "", t)   # transcriber notes, (笑)
    t = re.sub(r"\[[^\]]*\]", "", t)
    t = t.replace(" ?", "？").replace("?", "？").replace(",", "、").replace(".", "。")
    t = re.sub(r"\s+", "", t)
    t = re.sub(r"^[、。]+", "", t)
    t = re.sub(r"([、。？])[、。]+", r"\1", t)
    return t


def chat_segments(cha, cleaner, ort_tier=None):
    segs, pending = [], {}
    for spk, main, tiers, bullet in chat_utterances(cha):
        text = cleaner(tiers.get(ort_tier, "") if ort_tier else main)
        if not bullet:
            if text:
                pending[spk] = pending.get(spk, "") + text
            continue
        text = pending.pop(spk, "") + text
        if text:
            segs.append({"speaker": spk, "start": bullet[0], "end": bullet[1], "text": text})
    return sorted(segs, key=lambda x: (x["start"], x["speaker"]))


def callhome_segments(f, call):
    cha = f.get(f"{CH}/cha/{call}.cha", f"callhome_ja/{call}.cha").read_text(encoding="utf-8")
    return chat_segments(cha, clean_callhome)


def sakura_segments(f, name):
    cha = f.get(f"{SK}/cha/{name}.cha", f"sakura/{name}.cha").read_text(encoding="utf-8")
    return chat_segments(cha, clean_sakura, ort_tier="ort")


# ---------- conversations: window choice ----------

NON_SPEAKERS = {"ALL", "UNI", "INV"}  # CHAT codes for everyone at once, unidentified, investigator


def choose_window(segs, rule, lo, hi, skip):
    kind, n = rule.split(":")
    n = int(n)
    # Cut points: silences of at least MIN_GAP seconds where nobody speaks, between
    # annotated segments only (some transcripts cover part of the recording). A
    # window starts at most PAD before its first word and ends PAD after its last.
    gaps, end = [], None
    for s in segs:
        if end is not None and s["start"] - end >= MIN_GAP:
            gaps.append((end, s["start"]))
        end = s["end"] if end is None else max(end, s["end"])
    pad = lambda g: min((g[1] - g[0]) / 2, PAD)
    for i, ga in enumerate(gaps):
        a = ga[1] - pad(ga)
        if a < skip:
            continue
        for gb in gaps[i + 1:]:
            b = gb[0] + pad(gb)
            if b - a < lo:
                continue
            if b - a > hi:
                break
            inside = [s for s in segs if s["start"] >= a and s["end"] <= b]
            speech = {}
            for s in inside:
                speech[s["speaker"]] = speech.get(s["speaker"], 0) + s["end"] - s["start"]
            people = {k: v for k, v in speech.items() if k not in NON_SPEAKERS}
            if kind == "exact":
                ok = len(people) == n and min(people.values()) >= MIN_SPEECH and set(speech) <= set(people)
            else:
                ok = sum(v >= MIN_SPEECH for v in people.values()) >= n
            if ok and sum(speech.values()) >= 0.5 * (b - a):
                return a, b, inside
    return None


def conversation(f, lang, clip, out_wav):
    source, rec, rule, lo, hi, skip = WINDOWS[lang][clip]
    if source == "ami":
        segs = ami_segments(f, rec)
        audio = f.get(AMI_AUDIO.format(m=rec), f"ami/{rec}.Mix-Headset.wav")
        channel = None
    elif source == "aishell4":
        segs = aishell4_segments(f, rec)
        audio = f.get(f"{A4}/wav/{rec}.flac", f"aishell4/{rec}.flac")
        channel = 0
    elif source == "callhome_ja":
        if rec is None:  # first call in sha256 order with a third participant that fits the rule
            calls = sorted((p.stem for p in (f.cache / "callhome_ja").glob("*.cha")), key=lambda c: key(f"callhome/{c}"))
            for call in calls:
                found = choose_window(callhome_segments(f, call), rule, lo, hi, skip)
                if found:
                    rec = call
                    break
            else:
                sys.exit("no CallHome call with three speakers")
        segs = callhome_segments(f, rec)
        audio = f.get(f"{CH}/wav/{rec}.wav", f"callhome_ja/{rec}.wav")
        channel = None
    elif source == "sakura":
        segs = sakura_segments(f, rec)
        audio = f.get(f"{SK}/mp4/{rec}.mp4", f"sakura/{rec}.mp4")
        channel = None
    found = choose_window(segs, rule, lo, hi, skip)
    if not found:
        sys.exit(f"no window for {lang}/{clip} in {rec}")
    a, b, inside = found
    ffmpeg_cut(audio, out_wav, a, b, channel)
    segments = [{"speaker": s["speaker"], "start": round(s["start"] - a, 3), "end": round(s["end"] - a, 3), "text": s["text"]} for s in inside]
    return {"ami": "ami_annotations"}.get(source, source), {"recording": rec, "start": round(a, 3), "end": round(b, 3), "rule": rule}, segments


def all_callhome_cha(f):
    """CallHome needs every transcript to find a three-speaker call."""
    listing = json.loads(subprocess.run(["curl", "-sSLf", "https://huggingface.co/api/datasets/Fhrozen/CABankSakuraCHJP/tree/208ae52187c393a222ee77605d94ec3e033d7e92/dummy/cha?limit=1000"],
                                        check=True, capture_output=True).stdout)
    for item in listing:
        name = item["path"].rsplit("/", 1)[-1]
        f.get(f"{CH}/cha/{name}", f"callhome_ja/{name}")


def voxpopuli(f, clip, out_wav):
    import numpy as np, pyarrow.parquet as pq, soundfile as sf
    session, speakers = VOXPOPULI[clip]
    per = VOX_PER_SPEAKER[1 if clip.startswith("group") else 0]
    table = pq.read_table(f.source("voxpopuli_es"), columns=["audio_id", "speaker_id", "raw_text"])
    ids = [i for i in table.column("audio_id").to_pylist() if i.startswith(session + "_")]

    def order(audio_id):  # speech start time, then segment index
        stamp, idx = audio_id.split("_", 1)[1].rsplit("_", 1)
        return stamp, int(idx)

    meta = {r["audio_id"]: r for r in table.to_pylist() if r["audio_id"] in set(ids)}
    chosen, count = [], {}
    for i in sorted(ids, key=order):
        if i.split("_", 1)[1] in VOX_SKIP:
            continue
        spk = meta[i]["speaker_id"]
        if count.get(spk, 0) < per:
            count[spk] = count.get(spk, 0) + 1
            chosen.append(i)
    if len(count) != speakers:
        sys.exit(f"VoxPopuli {session}: {len(count)} speakers, expected {speakers}")
    full = pq.read_table(f.source("voxpopuli_es"), columns=["audio_id", "audio"])
    audio = {r["audio_id"]: r["audio"]["bytes"] for r in full.to_pylist() if r["audio_id"] in set(chosen)}
    pieces, segments, t = [], [], 0.0
    gap = np.zeros(int(VOX_GAP * RATE), dtype=np.float32)
    for n, i in enumerate(chosen):
        data, rate = sf.read(io.BytesIO(audio[i]), dtype="float32")
        if data.ndim > 1:
            data = data.mean(axis=1)
        if rate != RATE:
            sys.exit(f"unexpected rate {rate}")
        if n:
            pieces.append(gap)
            t += VOX_GAP
        segments.append({"speaker": meta[i]["speaker_id"], "start": round(t, 3), "end": round(t + len(data) / RATE, 3), "text": meta[i]["raw_text"]})
        pieces.append(data)
        t += len(data) / RATE
    sf.write(str(out_wav), np.concatenate(pieces), RATE, subtype="PCM_16")
    return "voxpopuli_es", {"session": session, "segments": chosen, "gap_seconds": VOX_GAP, "stitched": True}, segments


# ---------- build ----------

def build(cache, out, pins):
    f = Fetcher(cache, pins)
    all_callhome_cha(f)
    manifest = {"version": 1, "work_item": "AD-114", "sample_rate": RATE, "sets": {}}
    for lang in ("zh", "en", "ja", "es"):
        (out / lang).mkdir(parents=True, exist_ok=True)
        clips = []
        sid, picker = SINGLES[lang]
        for n, (item, spk, data, text) in enumerate(picker(f), 1):
            cid = f"{lang}-single-{n}"
            wav = out / lang / f"{cid}.wav"
            ffmpeg_cut(None, wav, data=data)
            dur = wav_seconds(wav)
            src = "mls_es_transcripts" if sid.startswith("mls") else sid
            clips.append(record(lang, cid, "single", src, {"item": item, "speaker": spk},
                                [{"speaker": spk, "start": 0.0, "end": round(dur, 3), "text": text}], wav))
        for clip in ("small-1", "small-2", "group-1"):
            cid = f"{lang}-{clip}"
            wav = out / lang / f"{cid}.wav"
            if lang == "es":
                src, where, segments = voxpopuli(f, clip, wav)
            else:
                src, where, segments = conversation(f, lang, clip, wav)
            clips.append(record(lang, cid, clip.split("-")[0], src, where, segments, wav))
        manifest["sets"][lang] = clips
    manifest["source_files"] = dict(sorted(f.seen.items()))
    shutil.copyfile(HERE / "README.md", out / "README.md")
    (out / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    return manifest


def record(lang, cid, kind, src, where, segments, wav):
    s = SOURCES[src]
    speakers = sorted({x["speaker"] for x in segments} - NON_SPEAKERS)
    ref = {
        "id": cid, "language": lang, "kind": kind, "speakers": len(speakers), "speaker_labels": speakers,
        "duration": round(wav_seconds(wav), 3),
        "source": {"dataset": s["dataset"], "license": s["license"], "attribution": s["attribution"], **where},
        "text": join([x["text"] for x in segments], lang),
        "segments": segments,
    }
    path = wav.with_suffix(".json")
    path.write_text(json.dumps(ref, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    return {"id": cid, "kind": kind, "speakers": len(speakers), "duration": ref["duration"],
            "dataset": s["dataset"], "license": s["license"], "where": where,
            "audio": f"{lang}/{cid}.wav", "audio_sha256": sha256(wav),
            "reference": f"{lang}/{cid}.json", "reference_sha256": sha256(path)}


def digests_of(manifest):
    return {"source_files": manifest["source_files"],
            "clips": {c["id"]: {"audio_sha256": c["audio_sha256"], "reference_sha256": c["reference_sha256"], "where": c["where"]}
                      for clips in manifest["sets"].values() for c in clips}}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cache", type=pathlib.Path, required=True, help="download cache (several GB)")
    ap.add_argument("--out", type=pathlib.Path, required=True, help="dataset directory")
    ap.add_argument("--update-digests", action="store_true", help="rewrite digests.json from this build")
    args = ap.parse_args()
    if not shutil.which("ffmpeg"):
        sys.exit("ffmpeg is required")
    pinned = json.loads(DIGESTS_FILE.read_text()) if DIGESTS_FILE.exists() else {}
    pins = {} if args.update_digests else pinned.get("source_files", {})
    manifest = build(args.cache.resolve(), args.out.resolve(), pins)
    got = digests_of(manifest)
    if args.update_digests:
        DIGESTS_FILE.write_text(json.dumps(got, ensure_ascii=False, indent=1) + "\n")
        print(f"wrote {DIGESTS_FILE}")
    elif pinned:
        bad = [k for k, v in got["clips"].items() if pinned["clips"].get(k) != v]
        if bad:
            sys.exit(f"clips differ from digests.json: {', '.join(bad)}")
        print("all clips match digests.json")
    for lang, clips in manifest["sets"].items():
        for c in clips:
            print(f"{c['id']:14} {c['speakers']} spk {c['duration']:7.1f} s  {c['dataset']}")


if __name__ == "__main__":
    main()
