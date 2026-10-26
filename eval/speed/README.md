# AD-104 gate 0: speed measurements

Tools for the measurements that decide whether the speed flagship continues
past gate 0: flag precision (gate 3), whether dictation errors change an AI's
answer (gate 2), residual error among unflagged dictations, and AI-destination
read-back confirmation (gate 5, from `scripts/speed-metrics.py`, which reads the
app's per-destination delivery counters in `speed-metrics.json`). Gates 1 and 4
need a user test with screen recordings and are not measured here.

Python 3 standard library only. Every tool reads History through a temporary
read-only copy and never writes to Airdraft's data directory.

## Privacy

- Corpora go to `eval/speed/private/<date>/`, which `.gitignore` excludes.
  Never commit or share that folder: it holds transcripts and audio.
- Audio never leaves the Mac. `export_corpus.py` copies kept recordings into
  the private folder; `label.py --play` plays them with `/usr/bin/afplay`.
- Nothing is sent anywhere except to a local LM Studio server you start
  yourself: `compare_answers.py` refuses non-loopback URLs unless you pass
  `--allow-remote`, and it bypasses proxies.
- `scripts/speed-metrics.py` prints counts, rates, durations, AI-destination
  bundle IDs, web-app prefixes and app families only, never transcript text,
  titles, URLs or flag text.

## Workflow

1. In Airdraft, turn on Settings > Audio history > Keep recordings.
2. Dictate normally, or read prompts aloud (about one third read, two thirds
   free speech, covering AI prompts, chat, mixed languages and technical terms;
   the plan targets about 500 recordings).
3. Export:
   `python3 -B eval/speed/export_corpus.py --since 2026-10-26`
   (`--families code,terminal`, `--limit N` and `--audio-only` narrow it).
4. Label (resumable; Enter keeps the final text as the reference):
   `python3 -B eval/speed/label.py eval/speed/private/<date>/manifest.jsonl --play`
   or edit `--export-csv` output in a spreadsheet and merge it with `--import-csv`.
5. Score flag precision and residual error:
   `python3 -B eval/speed/score.py eval/speed/private/<date>/manifest.jsonl --save`
6. Compare AI answers (LM Studio running, model loaded):
   `python3 -B eval/speed/compare_answers.py eval/speed/private/<date>/manifest.jsonl --model <id>`
   Then check the rows in `compare-sample.jsonl` (a seeded 20% sample) by hand.
7. Report:
   `python3 -B scripts/speed-metrics.py --since 2026-10-26 --corpus eval/speed/private/<date>`

## Definitions

- Residual error is counted among labeled dictations with no flag that holds
  send: `intentCorrect` false, or a typed reference that differs from the final
  text after whitespace normalisation. Claiming at most 1% at 95% confidence
  (one-sided Clopper-Pearson) needs n >= 299 with no errors, 473 with one and
  628 with two (exact binomial; the proposal's 474 and 630 are the Poisson
  approximation).
- Read-back confirmation comes from the `deliveries` counters in
  `<data dir>/speed-metrics.json` (cursor outcomes per destination), not
  History, which stores bundle IDs only when Read app context is on. Rate =
  delivered / (delivered + sentUnverified + notDelivered) over AI
  destinations; 95% with all confirmed needs n >= 59 (one-sided
  Clopper-Pearson). Self-drawing editors (Warp, Zed, Ghostty, kitty,
  Alacritty, WezTerm) can only be sentUnverified; they are marked, and a
  second line excludes them for reference.
- AI destinations are the ChatGPT and Claude desktop apps plus the code and
  terminal bundle IDs from `AppFamily.swift`; browsers never count.
- Web-app counts (Safari "Add to Dock", Chrome apps) come from the same
  `deliveries` keys and show prefixes only.

## Tests

`python3 -B eval/speed/test_speed_tools.py` and
`python3 -B scripts/test-speed-metrics.py` use synthetic History databases and
an in-process fake LLM server on 127.0.0.1.
