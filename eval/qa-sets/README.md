# AD-114: internal QA speech sets

A fixed, small set of real recordings per interface language for checking
dictation and Transcribe quality by ear and by score. It complements the
measurement corpora in `eval/mixed-asr`, `eval/eja-asr` and `eval/intl-asr`,
which answer one model question each; these sets stay the same between
releases so results can be compared over time.

## Contents

One SET per language: Chinese (`zh`, Mandarin), English (`en`), Japanese (`ja`)
and Spanish (`es`). Each SET has six clips:

| Clip | Speakers | Length | Use |
| --- | --- | --- | --- |
| `single-1`…`3` | 1 | short, medium, long (about 5–25 s) | dictation |
| `small-1` | exactly 2 | 45–120 s | conversation, diarization |
| `small-2` | exactly 3 | 45–120 s | conversation, diarization |
| `group-1` | 4 or more, each speaking at least 3 s | 120–240 s | meetings, diarization |

| SET | Single speaker | 2–3 speakers | 4+ speakers |
| --- | --- | --- | --- |
| zh | AISHELL-1 test | AISHELL-4 test meetings | AISHELL-4 test meeting |
| en | LibriSpeech test-clean | AMI meetings (Mix-Headset) | AMI meeting |
| ja | FLEURS ja_jp test | CallHome Japanese phone calls | Sakura 4-person conversation |
| es | Multilingual LibriSpeech test | VoxPopuli plenary (stitched) | VoxPopuli plenary (stitched) |

These are the corpora speech papers report most for each language and
condition: LibriSpeech, AISHELL-1 and MLS for read speech; FLEURS for
multilingual read speech; AMI and AISHELL-4 for meetings; CallHome for
telephone conversation. Every clip uses a held-out test split where the corpus
has one.

## Where the data lives

Audio and transcripts are not in this repository: several licences forbid it
(see Licences), and the repository is public. Build the sets into the
maintainer's Project Files folder:

```bash
uv run --with pyarrow,soundfile,numpy python -I eval/qa-sets/build_sets.py \
  --cache ~/Library/Caches/airdraft-qa-sets \
  --out "/Users/lightiichen/Desktop/Project Files/Production Projects/Airdraft/qa-sets"
```

The cache needs about 4 GB; the built sets are about 50 MB. `ffmpeg` must be on
PATH. Every downloaded file and every built clip is pinned in `digests.json`;
a build that differs fails. `--update-digests` rewrites the pins after a
deliberate change to the rules or sources, which then needs a new Work log row.

Output, under `--out`:

- `<lang>/<clip>.wav`: 16 kHz mono 16-bit PCM.
- `<lang>/<clip>.json`: the reference. `text` is the whole transcript in time
  order (no separator for zh/ja, a space otherwise). `segments` lists
  `speaker`, `start`, `end` (seconds from the clip start) and `text`.
  `speakers`/`speaker_labels` count real people only. `source` names the corpus,
  licence, attribution and the exact item or window.
- `manifest.json`: every clip with its digests; `README.md`: this file.

## Selection rules

No clip was chosen by looking at model output.

**Single speaker.** Items are ordered by SHA-256 of their corpus ID. For each
duration band (short, medium, long; per corpus in `BANDS`), take the first item
whose speaker was not already used. AISHELL-1 has no utterance over 15 s and
MLS none under 10 s, so their bands differ. The AISHELL-1 test audio comes from
a parquet mirror without IDs; IDs come from matching the official transcript,
and sentences read by more than one speaker are skipped. FLEURS publishes no
speaker IDs, so the three Japanese clips are three different sentences that
may share a reader.

**Conversations** (zh, en, ja). Windows start and end in a silence of at least
0.2 s between annotated segments, with at most 0.5 s of padding, so no segment
is cut. The first window, after skipping the opening minute of meetings, that
meets the clip's rule is taken: exactly N people (each speaking at least 3 s and
nobody else), or at least four people each speaking at least 3 s; in both,
speech must cover half the window. Recordings: AMI ES2004c, IS1009b and TS3003c;
AISHELL-4 S_R004S01C01, M_R003S01C01 and L_R003S01C02 (first array channel, far
field); CallHome 0696 and the first call in SHA-256 order with a third speaker;
Sakura 05. Overlapping speech stays in the audio; its text is listed in start
order.

**Spanish conversations.** No freely licensed Spanish multi-party recording
with speaker-attributed transcripts was found (CallHome Spanish needs a
TalkBank login; Fisher Spanish is LDC-only). The Spanish group clips therefore
join consecutive VoxPopuli segments from one European Parliament session, two
per speaker (three in `group-1`), in session order with 0.6 s of silence
between them. The voices and words are real; the turn-taking is not a
conversation. One segment whose gender label contradicts the rest of its
speech is skipped.

## Reference conventions

References are the corpora's own transcripts with markup removed; nothing was
retranscribed.

- LibriSpeech: upper case, no punctuation. MLS: lower case, no punctuation.
  Normalize case and punctuation before scoring.
- AMI: cased and punctuated; spelled letters (`L_C_D_`) are joined (`LCD`);
  word fragments such as `b buttons` are kept as annotated.
- AISHELL-4: fillers kept (`呃`), noise and markup tags removed.
- CallHome Japanese: spoken forms kept (the CHAT `[: …]` standard form is
  dropped), events, unintelligible marks and intonation arrows removed.
- Sakura: the orthographic `%ort` tier, with transcriber notes and `(笑)`
  removed. Speaker `ALL` (everyone at once) is kept in `segments` but not
  counted as a speaker.
- Numbers are written as each corpus writes them (`500` or `quinientos`).

Telephone audio (CallHome, 8 kHz) is upsampled to 16 kHz; it still has
telephone bandwidth.

## Sanity check

On 2026-10-26, Whisper small (MLX) transcribed every built clip and the
transcript was compared with the reference at several timestamps: every
clip's audio and reference line up. Its error rates are a quick check, not
a measurement.

## Licences

| Corpus | Licence |
| --- | --- |
| LibriSpeech, MLS, FLEURS, AMI | CC BY 4.0 |
| AISHELL-1 | Apache 2.0 |
| AISHELL-4 | CC BY-SA 4.0 (Apache 2.0 on its Hub mirror) |
| VoxPopuli | CC0 1.0 |
| CallHome Japanese, Sakura (TalkBank) | CC BY-NC-SA 3.0 |

The TalkBank clips (`ja-small-*`, `ja-group-1`) are for internal evaluation
only: never ship them, publish them or quote them on the website. Any published
result citing a clip must carry its `source.attribution`.
