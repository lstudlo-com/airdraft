#!/usr/bin/env python3
"""Synthetic Airdraft data directories for the speed tooling tests.

Builds history.sqlite with the schema HistoryStore creates through migration
v9-speed (GRDB DDL, dates as 'YYYY-MM-DD HH:MM:SS.SSS' UTC), Recordings/ WAV
sidecars and speed-metrics.json. Never touches real user data.
"""
import json, pathlib, sqlite3, struct

SCHEMA = """
CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY);
CREATE TABLE dictation (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  createdAt DATETIME NOT NULL,
  appBundleId TEXT, appName TEXT, windowTitle TEXT, url TEXT,
  mode TEXT NOT NULL, family TEXT NOT NULL,
  rawTranscript TEXT NOT NULL, refinedText TEXT NOT NULL, finalText TEXT NOT NULL,
  language TEXT, asrEngine TEXT NOT NULL, llmEngine TEXT, promptVersion TEXT,
  audioSeconds DOUBLE NOT NULL, asrMs INTEGER NOT NULL, llmMs INTEGER NOT NULL,
  inserted BOOLEAN NOT NULL, error TEXT,
  audioFilename TEXT,
  outputDestination TEXT, outputSucceeded BOOLEAN,
  recordingID TEXT REFERENCES recordingAsset(id) ON DELETE SET NULL,
  wordCount INTEGER,
  flags TEXT, sendRequest TEXT, submitted BOOLEAN);
CREATE INDEX dictation_on_createdAt ON dictation(createdAt);
CREATE INDEX dictation_on_appBundleId ON dictation(appBundleId);
CREATE TABLE recordingAsset (
  id TEXT PRIMARY KEY, createdAt DATETIME NOT NULL, filename TEXT NOT NULL UNIQUE,
  duration DOUBLE NOT NULL, source TEXT NOT NULL, captureIssue TEXT);
CREATE TABLE mediaDocument (
  id TEXT PRIMARY KEY, createdAt DATETIME NOT NULL,
  recordingID TEXT REFERENCES recordingAsset(id) ON DELETE SET NULL,
  title TEXT NOT NULL, text TEXT NOT NULL, revision INTEGER NOT NULL, payload BLOB NOT NULL);
CREATE TABLE speakerName (key TEXT PRIMARY KEY, name TEXT NOT NULL, lastUsedAt DATETIME NOT NULL);
"""
MIGRATIONS = ("v1", "v2", "v3", "v4-recording-assets", "v5-media-documents", "v6-meeting-metadata",
              "v7-word-count", "v8-speaker-names", "v9-speed")

DEFAULTS = {
    "createdAt": "2026-10-20 10:00:00.000", "appBundleId": "com.apple.TextEdit", "appName": "TextEdit",
    "windowTitle": None, "url": None, "mode": "Clean", "family": "general",
    "rawTranscript": "raw", "refinedText": "raw", "finalText": "raw", "language": "en",
    "asrEngine": "sherpa:parakeet", "llmEngine": None, "promptVersion": None,
    "audioSeconds": 3.0, "asrMs": 200, "llmMs": 0, "inserted": 1, "error": None,
    "audioFilename": None, "outputDestination": "cursor", "outputSucceeded": 1,
    "recordingID": None, "wordCount": 1, "flags": None, "sendRequest": None, "submitted": None,
}


def flag(kind, text, snippet=None, holds=True):
    return {"kind": kind, "text": text, "snippet": snippet or f"..{text}..", "holdsSend": holds}


def write_wav(path, seconds=0.1, rate=16000):
    frames = int(seconds * rate)
    data = b"\x00\x00" * frames
    header = b"RIFF" + struct.pack("<I", 36 + len(data)) + b"WAVEfmt " + struct.pack(
        "<IHHIIHH", 16, 1, 1, rate, rate * 2, 2, 16) + b"data" + struct.pack("<I", len(data))
    pathlib.Path(path).write_bytes(header + data)


def make_history(data_dir, rows, assets=(), keep_open=False, wal=True):
    """Create <data_dir>/history.sqlite. `rows` are dicts over DEFAULTS; a list
    `flags` value is JSON-encoded. `assets` are (id, filename, write_file) tuples.
    With keep_open the connection is returned unclosed so -wal stays on disk."""
    data_dir = pathlib.Path(data_dir)
    data_dir.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(data_dir / "history.sqlite")
    if wal:
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA wal_autocheckpoint=0")
    conn.executescript(SCHEMA)
    conn.executemany("INSERT INTO grdb_migrations VALUES (?)", [(m,) for m in MIGRATIONS])
    recordings = data_dir / "Recordings"
    for asset_id, filename, write_file in assets:
        conn.execute("INSERT INTO recordingAsset (id, createdAt, filename, duration, source) VALUES (?,?,?,?,?)",
                     (asset_id, "2026-10-20 10:00:00.000", filename, 0.1, "dictation"))
        if write_file:
            recordings.mkdir(exist_ok=True)
            write_wav(recordings / filename)
    for row in rows:
        values = dict(DEFAULTS)
        values.update(row)
        if isinstance(values["flags"], list):
            values["flags"] = json.dumps(values["flags"], ensure_ascii=False)
        columns = list(values)
        conn.execute(f"INSERT INTO dictation ({', '.join(columns)}) VALUES ({', '.join('?' * len(columns))})",
                     [values[c] for c in columns])
    conn.commit()
    if keep_open:
        return conn
    conn.close()
    return None


def write_counters(data_dir, ignored, accepted, samples, since="2026-10-01T00:00:00Z", deliveries=None):
    payload = {"version": 1, "since": since, "ignoredPresses": ignored, "acceptedPresses": accepted,
               "captureSamples": samples}
    if deliveries is not None:
        payload["deliveries"] = deliveries
    (pathlib.Path(data_dir) / "speed-metrics.json").write_text(json.dumps(payload), encoding="utf-8")
