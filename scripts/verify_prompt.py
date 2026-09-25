"""Validate that evaluation evidence matches the shipped prompt and has no case regression."""
import hashlib
import json
from pathlib import Path
import re
import textwrap


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify(root):
    manifest_path = root / "eval/results/prompt-validation.json"
    if not manifest_path.exists():
        raise RuntimeError("Prompt release evidence is missing; run correction and holdout evaluations first")
    manifest = json.loads(manifest_path.read_text())
    source_root = root / "Packages/AirdraftCore/Sources/AirdraftCore"
    source = (source_root / "LLM/PromptBuilder.swift").read_text()
    version = re.search(r'public static let version = "([^"]+)"', source).group(1)
    rules = textwrap.dedent(re.search(r'public static let defaultBaseRules = """\n(.*?)\n    """', source, re.S).group(1)).strip()
    if manifest.get("prompt_version") != version: raise RuntimeError("Prompt version has no matching evaluation")
    expected_sources = {name: digest(source_root / name) for name in
                        ["LLM/PromptBuilder.swift", "LLM/RefinementProfile.swift", "Context/AppFamily.swift", "Dictionary/DictionaryPostProcessor.swift"]}
    for dataset in ["correction_cases.json", "holdout_cases.json"]:
        entry = manifest.get("datasets", {}).get(dataset)
        if not entry: raise RuntimeError(f"Missing {dataset} evaluation")
        reports = {}
        for kind in ["candidate", "baseline"]:
            name = entry[kind]
            if Path(name).name != name: raise RuntimeError("Evaluation path must be a local JSON filename")
            path = root / "eval/results" / name
            if digest(path) != entry[kind + "_sha256"]: raise RuntimeError(f"Changed {kind} evaluation: {dataset}")
            reports[kind] = json.loads(path.read_text())
        candidate, baseline = reports["candidate"], reports["baseline"]
        if candidate.get("prompt_version") != version or candidate.get("assembly_sources") != expected_sources:
            raise RuntimeError("Prompt assembly changed after evaluation; rerun both suites")
        if candidate.get("default_rules_sha256") != hashlib.sha256(rules.encode()).hexdigest():
            raise RuntimeError("Evaluation used different base rules")
        cases = json.loads((root / "eval" / dataset).read_text())
        if candidate.get("cases_sha256") != digest(root / "eval" / dataset):
            raise RuntimeError("Evaluation cases changed after validation")
        if candidate.get("cases") != dataset or int(candidate.get("runs", 0)) < 3:
            raise RuntimeError("Expected three or more runs on the matching dataset")
        rows = {row["id"]: row for row in candidate["results"]}
        old = {row["id"]: row for row in baseline["results"]}
        if len(rows) != len(cases) or set(rows) != {case["id"] for case in cases} or set(rows) != set(old):
            raise RuntimeError("Evaluation case coverage is incomplete")
        total = 0
        for case in cases:
            row = rows[case["id"]]
            if len(row["runs"]) != candidate["runs"]: raise RuntimeError("Missing evaluation runs")
            scored = [run.get("returncode") == 0 and all(term in run["text"] for term in case["expect"])
                      and not any(term in run["text"] for term in case["forbid"]) for run in row["runs"]]
            if [run["ok"] for run in row["runs"]] != scored or sum(scored) != row["passed"]:
                raise RuntimeError("Evaluation scores do not match captured outputs")
            if sum(scored) / len(scored) < old[case["id"]]["passed"] / baseline["runs"]:
                raise RuntimeError(f"Prompt regressed on {dataset}: {case['id']}")
            total += sum(scored)
        if candidate["total"] != total or candidate["max"] != len(cases) * candidate["runs"]:
            raise RuntimeError("Invalid evaluation total")
    return version
