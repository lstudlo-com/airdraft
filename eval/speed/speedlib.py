#!/usr/bin/env python3
"""Shared helpers for the AD-104 speed tooling (stdlib only).

Used by scripts/speed-metrics.py and the eval/speed scripts:
- Clopper-Pearson bounds from the regularized incomplete beta function.
- A read-only, temporary copy of History (history.sqlite plus -wal/-shm).
- History row decoding that mirrors DictationRecord.deliveryStatus and
  tolerates databases from before migration v9-speed.
- AI-destination and app-family classification by bundle ID.
"""
import contextlib, datetime, json, math, os, pathlib, shutil, sqlite3, tempfile, unicodedata

HERE = pathlib.Path(__file__).resolve().parent
PRIVATE_DIR = HERE / "private"
DEFAULT_DATA_DIR = pathlib.Path.home() / "Library" / "Application Support" / "Transcribar"

# Read-back confirmation of pasted text began on this date; earlier rows used an
# older delivery meaning and never count toward gate 5.
READBACK_SINCE = datetime.datetime(2026, 10, 7, tzinfo=datetime.timezone.utc)

FLAG_KINDS = ("number", "negation", "newTerm", "identifier", "recognition")
CAPTURE_TRANSPORTS = ("builtIn", "bluetooth", "usb", "continuity", "virtual", "other", "unknown")

# Desktop AI apps (bundle ID prefix -> label).
AI_APP_PREFIXES = (
    ("com.openai.chat", "ChatGPT"),
    ("com.anthropic.claudefordesktop", "Claude"),
)
# Copy of the code and terminal rows of AppFamily.table (AppFamily.swift).
CODE_TERMINAL_PREFIXES = (
    ("com.microsoft.VSCode", "code"),
    ("com.todesktop.230313mzl4w4u92", "code"),  # Cursor
    ("com.exafunction.windsurf", "code"),
    ("com.apple.dt.Xcode", "code"),
    ("com.jetbrains.", "code"),
    ("dev.zed.Zed", "code"),
    ("com.sublimetext", "code"),
    ("com.apple.Terminal", "terminal"),
    ("com.googlecode.iterm2", "terminal"),
    ("dev.warp.Warp", "terminal"),
    ("com.mitchellh.ghostty", "terminal"),
    ("net.kovidgoyal.kitty", "terminal"),
    ("org.alacritty", "terminal"),
    ("com.github.wez.wezterm", "terminal"),
)
# TextInserter.selfDrawingEditorBundlePrefixes: these confirm no caret, so a
# paste can only be sentUnverified.
SELF_DRAWING_PREFIXES = ("dev.warp.Warp", "dev.zed.Zed", "com.mitchellh.ghostty", "net.kovidgoyal.kitty",
                         "org.alacritty", "com.github.wez.wezterm")
WEB_APP_PREFIXES = ("com.apple.Safari.WebApp.", "com.google.Chrome.app.")
CODE_FAMILIES = ("code", "terminal")


# --------------------------------------------------------------------------
# Clopper-Pearson

def _betacf(a, b, x):
    """Continued fraction for the incomplete beta (modified Lentz)."""
    tiny, eps = 1e-300, 1e-15
    qab, qap, qam = a + b, a + 1.0, a - 1.0
    c, d = 1.0, 1.0 - qab * x / qap
    d = 1.0 / (d if abs(d) > tiny else tiny)
    h = d
    for m in range(1, 10000):
        m2 = 2 * m
        aa = m * (b - m) * x / ((qam + m2) * (a + m2))
        d = 1.0 + aa * d
        d = 1.0 / (d if abs(d) > tiny else tiny)
        c = 1.0 + aa / c
        c = c if abs(c) > tiny else tiny
        h *= d * c
        aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2))
        d = 1.0 + aa * d
        d = 1.0 / (d if abs(d) > tiny else tiny)
        c = 1.0 + aa / c
        c = c if abs(c) > tiny else tiny
        delta = d * c
        h *= delta
        if abs(delta - 1.0) < eps:
            break
    return h


def betainc(a, b, x):
    """Regularized incomplete beta I_x(a, b) for a, b > 0."""
    if x <= 0.0:
        return 0.0
    if x >= 1.0:
        return 1.0
    ln_front = (math.lgamma(a + b) - math.lgamma(a) - math.lgamma(b)
                + a * math.log(x) + b * math.log1p(-x))
    if x < (a + 1.0) / (a + b + 2.0):
        return math.exp(ln_front) * _betacf(a, b, x) / a
    return 1.0 - math.exp(ln_front) * _betacf(b, a, 1.0 - x) / b


def beta_quantile(p, a, b):
    """x with I_x(a, b) = p, by bisection."""
    lo, hi = 0.0, 1.0
    for _ in range(200):
        mid = (lo + hi) / 2.0
        if betainc(a, b, mid) < p:
            lo = mid
        else:
            hi = mid
        if hi - lo < 1e-14:
            break
    return (lo + hi) / 2.0


def cp_lower(k, n, alpha=0.05):
    """One-sided (1 - alpha) Clopper-Pearson lower bound for k successes in n."""
    if n <= 0:
        return None
    if k <= 0:
        return 0.0
    return beta_quantile(alpha, k, n - k + 1)


def cp_upper(k, n, alpha=0.05):
    """One-sided (1 - alpha) Clopper-Pearson upper bound for k successes in n."""
    if n <= 0:
        return None
    if k >= n:
        return 1.0
    return beta_quantile(1.0 - alpha, k + 1, n - k)


def cp_interval(k, n, alpha=0.05):
    """Two-sided (1 - alpha) Clopper-Pearson interval."""
    if n <= 0:
        return (None, None)
    return (cp_lower(k, n, alpha / 2.0), cp_upper(k, n, alpha / 2.0))


def n_needed_for_upper(errors, limit=0.01, alpha=0.05, cap=1_000_000):
    """Smallest n whose one-sided upper bound with `errors` errors is <= limit."""
    n = max(errors + 1, 1)
    while cp_upper(errors, n, alpha) > limit:
        n += 1
        if n > cap:
            return None
    return n


def n_needed_for_lower(failures, limit=0.95, alpha=0.05, cap=1_000_000):
    """Smallest n whose one-sided lower bound with `failures` failures is >= limit."""
    n = max(failures + 1, 1)
    while cp_lower(n - failures, n, alpha) < limit:
        n += 1
        if n > cap:
            return None
    return n


def rate(k, n):
    return (k / n) if n else None


# --------------------------------------------------------------------------
# Text and time

def normalize_ws(text):
    return " ".join(unicodedata.normalize("NFC", text or "").split())


def parse_time(value):
    """GRDB dates ('YYYY-MM-DD HH:MM:SS.SSS', UTC), ISO 8601 or Unix seconds."""
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return datetime.datetime.fromtimestamp(float(value), datetime.timezone.utc)
    text = str(value).strip()
    if not text:
        return None
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        parsed = datetime.datetime.fromisoformat(text)
    except ValueError:
        try:
            return datetime.datetime.fromtimestamp(float(text), datetime.timezone.utc)
        except ValueError:
            return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=datetime.timezone.utc)
    return parsed


def parse_since(text):
    """--since YYYY-MM-DD as local midnight, returned in UTC."""
    if not text:
        return None
    day = datetime.date.fromisoformat(text)
    local = datetime.datetime(day.year, day.month, day.day).astimezone()
    return local.astimezone(datetime.timezone.utc)


def iso(dt):
    return dt.astimezone(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ") if dt else None


# --------------------------------------------------------------------------
# Classification

def ai_app_label(bundle_id):
    for prefix, label in AI_APP_PREFIXES:
        if bundle_id and bundle_id.startswith(prefix):
            return label
    return None


def code_terminal_family(bundle_id):
    for prefix, family in CODE_TERMINAL_PREFIXES:
        if bundle_id and bundle_id.startswith(prefix):
            return family
    return None


def is_self_drawing(bundle_id):
    return bool(bundle_id) and bundle_id.startswith(SELF_DRAWING_PREFIXES)


def is_ai_destination_bundle(bundle_id):
    """Desktop AI apps plus code editors and terminals, by bundle ID only.

    Browsers are excluded even when History's family says code (github.com):
    send-to-AI never applies to browser bundle IDs.
    """
    return ai_app_label(bundle_id) is not None or code_terminal_family(bundle_id) is not None


def is_ai_destination_row(row):
    return is_ai_destination_bundle(row.get("appBundleId")) or row.get("family") in CODE_FAMILIES


def delivery_status(destination, inserted, output_succeeded):
    """Mirror of DictationRecord.deliveryStatus."""
    if destination in ("script", "copy", "file"):
        return "delivered" if output_succeeded else "notDelivered"
    if inserted:
        return "delivered"
    if destination == "cursor" and output_succeeded:
        return "sentUnverified"
    return "notDelivered"


def parse_flags(value):
    """Return (flags or None, readable). NULL -> (None, True)."""
    if value is None:
        return None, True
    try:
        flags = json.loads(value)
    except (TypeError, ValueError):
        return None, False
    if not isinstance(flags, list) or not all(isinstance(f, dict) for f in flags):
        return None, False
    return flags, True


def flag_holds_send(flag):
    value = flag.get("holdsSend", True)
    return bool(value) if value is not None else True


# --------------------------------------------------------------------------
# History access

@contextlib.contextmanager
def history_copy(data_dir):
    """Copy history.sqlite (+ -wal/-shm) to a fresh temp dir and open it read-only.

    Yields (connection, temp_dir). The copy is deleted on exit; the original
    database is never opened.
    """
    data_dir = pathlib.Path(data_dir).expanduser()
    source = data_dir / "history.sqlite"
    if not source.is_file():
        raise FileNotFoundError(f"no history.sqlite in {data_dir}")
    temp = pathlib.Path(tempfile.mkdtemp(prefix="airdraft-speed-"))
    conn = None
    try:
        os.chmod(temp, 0o700)
        for suffix in ("", "-wal", "-shm"):
            path = data_dir / ("history.sqlite" + suffix)
            if path.is_file():
                shutil.copy2(path, temp / path.name)
        uri = (temp / "history.sqlite").as_uri() + "?mode=ro"
        conn = sqlite3.connect(uri, uri=True)
        conn.row_factory = sqlite3.Row
        yield conn, temp
    finally:
        if conn is not None:
            conn.close()
        shutil.rmtree(temp, ignore_errors=True)


def table_columns(conn, table):
    return {row[1] for row in conn.execute(f"PRAGMA table_info({table})")}


def load_dictations(conn, since=None, include_text=False):
    """Decode dictation rows into dicts, oldest first.

    Text columns (rawTranscript, refinedText, finalText) are included only when
    `include_text` is true; callers that print must not ask for them. Columns
    missing from older databases read as None.
    """
    columns = table_columns(conn, "dictation")
    wanted = ["id", "createdAt", "appBundleId", "mode", "family", "llmEngine",
              "audioSeconds", "inserted", "outputDestination", "outputSucceeded",
              "recordingID", "flags", "sendRequest", "submitted"]
    if include_text:
        wanted += ["rawTranscript", "refinedText", "finalText"]
    select = ", ".join(c if c in columns else f"NULL AS {c}" for c in wanted)
    rows = []
    for raw in conn.execute(f"SELECT {select} FROM dictation ORDER BY createdAt, id"):
        row = dict(raw)
        row["createdAt"] = parse_time(row["createdAt"])
        if since and (row["createdAt"] is None or row["createdAt"] < since):
            continue
        row["inserted"] = bool(row["inserted"])
        row["outputSucceeded"] = None if row["outputSucceeded"] is None else bool(row["outputSucceeded"])
        row["submitted"] = None if row["submitted"] is None else bool(row["submitted"])
        row["flags"], row["flagsReadable"] = parse_flags(row["flags"])
        row["deliveryStatus"] = delivery_status(row["outputDestination"], row["inserted"], row["outputSucceeded"])
        rows.append(row)
    return rows, columns


def recording_filenames(conn):
    if "recordingAsset" not in {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}:
        return {}
    return {r[0]: r[1] for r in conn.execute("SELECT id, filename FROM recordingAsset")}


def is_safe_audio_filename(name):
    return bool(name) and "/" not in name and "\\" not in name and not name.startswith(".") \
        and name.lower().endswith(".wav")


# --------------------------------------------------------------------------
# Private folder

def inside(path, folder):
    try:
        pathlib.Path(path).resolve().relative_to(pathlib.Path(folder).resolve())
        return True
    except ValueError:
        return False


def read_jsonl(path):
    items = []
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            if line.strip():
                items.append(json.loads(line))
    return items


def write_jsonl(path, items):
    """Atomic write: a crash never leaves a half-written manifest."""
    path = pathlib.Path(path)
    tmp = path.with_name(path.name + ".tmp")
    with open(tmp, "w", encoding="utf-8") as handle:
        for item in items:
            handle.write(json.dumps(item, ensure_ascii=False) + "\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(tmp, path)


def write_json(path, value):
    path = pathlib.Path(path)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, path)


def pct(value, digits=1):
    return "n/a" if value is None else f"{value * 100:.{digits}f}%"
