"""Check the Airdraft Obsidian vault against its maintenance rules.

The vault's `Knowledge Architecture.md` defines the rules; this module enforces
the mechanical part of them: frontmatter schema per note type, folder placement,
Work item numbering, resolvable wikilinks, no dated update paragraphs in
current-state notes, and no iCloud conflict copies. It only reads the vault.
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import re

DEFAULT_VAULT = Path.home() / "Library/Mobile Documents/iCloud~md~obsidian/Documents/Airdraft"

# Longest matching prefix decides which note types a folder may hold.
FOLDER_TYPES = {
    "Work/": {"issue", "task"},
    "Product/": {"product"},
    "Strategy/": {"strategy"},
    "Research/": {"research", "index"},
    "Records/Releases/": {"release"},
    "Records/Decisions/": {"decision"},
    "Records/Studies/": {"study"},
    "Records/Verification/": {"verification"},
    "Records/Evidence/": {"evidence"},
    "Records/": {"index"},
    "": {"index", "guide"},
}

WORK_STATUS = {"open", "doing", "released", "closed", "wont-do"}
RECORD_STATUS = {"recorded", "superseded"}
STATUS = {
    "index": {"maintained"},
    "guide": {"maintained"},
    "product": {"source-reviewed", "needs-review"},
    "strategy": {"proposed", "adopted", "superseded"},
    "research": {"current", "superseded"},
    "issue": WORK_STATUS,
    "task": WORK_STATUS,
    "release": {"published", "draft", "withdrawn"},
    "decision": {"adopted", "superseded"},
    "study": RECORD_STATUS,
    "verification": RECORD_STATUS,
    "evidence": RECORD_STATUS,
}
REQUIRED = {
    "product": ["verified_on", "source_commit"],
    "strategy": ["source_as_of"],
    "research": ["source_as_of", "evidence"],
    "issue": ["id", "verification", "gaps", "area", "source", "opened"],
    "task": ["id", "verification", "gaps", "area", "source", "opened"],
    "release": ["date", "version", "build", "source_commit", "verification"],
    "decision": ["date"],
    "study": ["date"],
    "verification": ["date"],
    "evidence": ["date"],
}
KINDS = {
    "product": {"overview", "feature", "architecture", "design-system"},
    "research": {"model-support"},
    "decision": {"correction"},
    "verification": {"audit", "correction"},
    "evidence": {"catalogue", "review", "migration"},
}
ENUMS = {
    "verification": {"none", "partial", "verified"},
    "evidence": {"source-checked", "interpretation", "forecast", "planned"},
    "source": {"user", "audit", "agent", "release"},
}
STATE_TYPES = {"index", "guide", "product", "strategy", "research"}
DATE_FIELDS = ("date", "opened", "verified_on")
SKIPPED_FOLDERS = (".obsidian/", ".trash/", "Templates/")
LARGE_FILE = 10 * 1024 * 1024

DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
ANY_DATE = re.compile(r"20\d{2}-\d{2}-\d{2}")
DATED_LINE = re.compile(r"^(?:\*\*)?(?:20\d{2}-\d{2}-\d{2}|[^\s|>#\-*]{2,8}（20\d{2}-\d{2}-\d{2})")
WIKILINK = re.compile(r"!?\[\[([^\]]+)\]\]")
CONFLICT = re.compile(r"^(?P<stem>.+) \d+(?P<ext>\.(?:md|base|canvas))$")
WORK_FILE = re.compile(r"^(AD-\d{3}) .+\.md$")
FILE_NAMES = {
    "release": (re.compile(r"^\d{4}-\d{2}-\d{2} Release \d+\.\d+\.\d+ Build \d+\.md$"), "YYYY-MM-DD Release X.Y.Z Build N.md"),
    "decision": (re.compile(r"^\d{4}-\d{2}-\d{2} .+\.md$"), "YYYY-MM-DD Title.md"),
    "study": (re.compile(r"^\d{4}-\d{2}-\d{2} .+\.md$"), "YYYY-MM-DD Title.md"),
    "verification": (re.compile(r"^\d{4}-\d{2}-\d{2} .+\.md$"), "YYYY-MM-DD Title.md"),
}


@dataclass(frozen=True)
class Finding:
    path: str
    message: str
    warning: bool = False

    def __str__(self) -> str:
        return f"{'warning' if self.warning else 'error'}: {self.path}: {self.message}"


def parse_frontmatter(text: str) -> tuple[dict | None, str | None]:
    """Parse the flat frontmatter subset the vault uses: scalars and lists."""
    if not text.startswith("---\n"):
        return None, "missing frontmatter"
    end = text.find("\n---", 3)
    if end < 0:
        return None, "unterminated frontmatter"
    data: dict = {}
    key = None
    for line in text[4:end].splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        item = re.match(r"^\s*- (.*)$", line)
        if item and key is not None:
            if not isinstance(data[key], list):
                data[key] = []
            data[key].append(_scalar(item.group(1)))
            continue
        field = re.match(r"^([A-Za-z_][\w-]*):(?:\s+(.*))?$", line)
        if not field:
            return data, f"unparsed frontmatter line: {line.strip()}"
        key, value = field.group(1), field.group(2)
        data[key] = None if value in (None, "") else _scalar(value)
    return data, None


def _scalar(value: str):
    value = value.strip()
    if value == "[]":
        return []
    if value.startswith("[") and value.endswith("]"):
        return [_scalar(part) for part in value[1:-1].split(",") if part.strip()]
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return value


def _strip_code(text: str) -> str:
    text = re.sub(r"```.*?```", "", text, flags=re.S)
    return re.sub(r"`[^`\n]*`", "", text)


def _body(text: str) -> str:
    if text.startswith("---\n"):
        end = text.find("\n---", 3)
        if end >= 0:
            return text[end + 4:]
    return text


def _allowed_types(relative: str) -> set[str]:
    prefix = max((p for p in FOLDER_TYPES if relative.startswith(p)), key=len)
    if prefix == "" and "/" in relative:
        return set()
    return FOLDER_TYPES[prefix]


def _dated_updates(body: str) -> list[str]:
    """Headings with a date, or paragraphs that open with one, in a state note.

    Appended updates usually land after the 來源 section, so it is not exempt;
    a source line states its check date mid-sentence ("查核：2026-10-01").
    """
    found, in_fence = [], False
    for line in body.splitlines():
        if line.startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        heading = re.match(r"^#{1,6}\s+(.*)$", line)
        if heading:
            if ANY_DATE.search(heading.group(1)):
                found.append(line.strip())
        elif DATED_LINE.match(line.strip()):
            found.append(line.strip()[:80])
    return found


def check(vault: Path) -> list[Finding]:
    findings: list[Finding] = []
    files = [p for p in vault.rglob("*") if p.is_file()]
    relative = {p: p.relative_to(vault).as_posix() for p in files}
    by_path = {r.lower() for r in relative.values()}
    by_name = {p.name.lower() for p in files} | {p.stem.lower() for p in files}
    work_ids: dict[str, str] = {}

    for path in sorted(files):
        rel = relative[path]
        if rel.startswith(SKIPPED_FOLDERS) or path.name == ".DS_Store":
            continue
        conflict = CONFLICT.match(path.name)
        if conflict and (path.parent / (conflict["stem"] + conflict["ext"])).exists():
            findings.append(Finding(rel, "iCloud conflict copy; merge it into the original and delete it"))
        if path.stat().st_size > LARGE_FILE:
            findings.append(Finding(rel, "larger than 10 MB; keep new large evidence outside the vault", warning=True))
        if path.suffix != ".md":
            continue

        text = path.read_text(encoding="utf-8")
        fm, error = parse_frontmatter(text)
        if error:
            findings.append(Finding(rel, error))
        fm = fm or {}
        note_type = fm.get("type")
        if note_type not in STATUS:
            findings.append(Finding(rel, f"type {note_type!r} is not one of {sorted(STATUS)}"))
        else:
            allowed = _allowed_types(rel)
            if note_type not in allowed:
                findings.append(Finding(rel, f"type {note_type!r} does not belong in this folder (allowed: {sorted(allowed) or 'none'})"))
            if fm.get("status") not in STATUS[note_type]:
                findings.append(Finding(rel, f"status {fm.get('status')!r} is not one of {sorted(STATUS[note_type])}"))
            for field in REQUIRED.get(note_type, []):
                if fm.get(field) in (None, "") and not (field == "gaps" and fm.get(field) == []):
                    findings.append(Finding(rel, f"missing {field}"))
            kind = fm.get("kind")
            if kind is not None and kind not in KINDS.get(note_type, set()):
                findings.append(Finding(rel, f"kind {kind!r} is not valid for {note_type}"))
            for field, values in ENUMS.items():
                if field in fm and fm[field] is not None and field in REQUIRED.get(note_type, []) and fm[field] not in values:
                    findings.append(Finding(rel, f"{field} {fm[field]!r} is not one of {sorted(values)}"))
            for field in DATE_FIELDS:
                if fm.get(field) not in (None, "") and not DATE.match(str(fm[field])):
                    findings.append(Finding(rel, f"{field} must be YYYY-MM-DD"))
            if note_type in FILE_NAMES and not FILE_NAMES[note_type][0].match(path.name):
                findings.append(Finding(rel, f"{note_type} notes are named '{FILE_NAMES[note_type][1]}'"))
            leading = re.match(r"^(\d{4}-\d{2}-\d{2}) ", path.name)
            if leading and fm.get("date") and note_type in REQUIRED and "date" in REQUIRED[note_type] and fm["date"] != leading.group(1):
                findings.append(Finding(rel, "date does not match the file name"))
            if note_type in ("issue", "task"):
                findings += _check_work(rel, path.name, fm, work_ids)
            if note_type in STATE_TYPES:
                for line in _dated_updates(_body(text)):
                    findings.append(Finding(rel, f"dated update in a current-state note; rewrite the topic and move history to Work or Records: {line}"))

        for target in WIKILINK.findall(_strip_code(_body(text))):
            name = target.split("|")[0].split("#")[0].split("^")[0].strip().rstrip("\\")
            if not name:
                continue
            candidates = {name.lower(), f"{name}.md".lower()}
            if "/" in name:
                if not candidates & by_path:
                    findings.append(Finding(rel, f"unresolved link [[{name}]]"))
            elif not candidates & by_name:
                findings.append(Finding(rel, f"unresolved link [[{name}]]"))
    return findings


def _check_work(rel: str, filename: str, fm: dict, work_ids: dict[str, str]) -> list[Finding]:
    findings = []
    match = WORK_FILE.match(filename)
    if not match:
        findings.append(Finding(rel, "Work notes are named 'AD-### Title.md'"))
    elif fm.get("id") != match.group(1):
        findings.append(Finding(rel, f"id {fm.get('id')!r} does not match the file name"))
    if fm.get("id") in work_ids:
        findings.append(Finding(rel, f"duplicate id {fm['id']} (also {work_ids[fm['id']]})"))
    elif fm.get("id"):
        work_ids[fm["id"]] = rel
    if not isinstance(fm.get("gaps"), list):
        findings.append(Finding(rel, "gaps must be a list"))
    if fm.get("status") == "released" and not fm.get("released_in"):
        findings.append(Finding(rel, "released items need released_in"))
    if fm.get("verification") == "verified" and fm.get("gaps"):
        findings.append(Finding(rel, "verified items cannot list gaps"))
    return findings
