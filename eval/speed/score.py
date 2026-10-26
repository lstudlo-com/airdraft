#!/usr/bin/env python3
"""Score a labeled speed corpus (AD-104 gate 3 and residual error).

    python3 -B eval/speed/score.py eval/speed/private/<date>/manifest.jsonl [--json] [--save]

Definitions
- Flag precision = flags judged worth a look / judged flags, overall and per
  kind (unjudged flags are reported, not counted). Gate 3: precision >= 30%.
- No-hold share = dictations with no holdsSend flag / dictations whose flags
  were checked (`flags` not null).
- Residual error, among labeled dictations (intentCorrect set) with checked
  flags and no holdsSend flag: an error is intentCorrect == false, or a
  non-empty reference that differs from finalText after whitespace
  normalisation. Reported with the one-sided 95% Clopper-Pearson upper bound
  and the n needed to claim <= 1% at the observed error count (exact binomial:
  0 errors -> 299, 1 -> 473, 2 -> 628; the Poisson approximation gives 474
  and 630).
--save writes score.json (counts only) beside the manifest; speed-metrics.py
--corpus reads it.
"""
import argparse, json, pathlib, sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import speedlib as S  # noqa: E402

PRECISION_GATE = 0.30
RESIDUAL_LIMIT = 0.01


def is_error(item):
    if item.get("intentCorrect") is False:
        return True
    reference = item.get("reference") or ""
    return bool(reference.strip()) and S.normalize_ws(reference) != S.normalize_ws(item.get("finalText"))


def holds_send(item):
    return any(S.flag_holds_send(f) for f in item.get("flags") or [])


def precision_block(pairs):
    judged = [j for _, j in pairs if j is not None]
    worth = sum(1 for j in judged if j)
    return {"flags": len(pairs), "judged": len(judged), "unjudged": len(pairs) - len(judged),
            "worthALook": worth, "precision": S.rate(worth, len(judged)),
            "lower95": S.cp_lower(worth, len(judged)) if judged else None}


def score(items):
    labeled = [i for i in items if i.get("intentCorrect") is not None]
    pairs = []
    for item in labeled:
        flags = item.get("flags") or []
        judgments = list(item.get("flagJudgments") or []) + [None] * len(flags)
        pairs += [(f.get("kind") if f.get("kind") in S.FLAG_KINDS else "other", judgments[i])
                  for i, f in enumerate(flags)]
    by_kind = {}
    for kind in sorted({k for k, _ in pairs}):
        by_kind[kind] = precision_block([p for p in pairs if p[0] == kind])
    precision = precision_block(pairs)

    checked = [i for i in items if i.get("flags") is not None]
    no_hold = [i for i in checked if not holds_send(i)]
    residual_rows = [i for i in no_hold if i.get("intentCorrect") is not None]
    errors = sum(1 for i in residual_rows if is_error(i))
    n = len(residual_rows)
    upper = S.cp_upper(errors, n) if n else None
    needed = S.n_needed_for_upper(errors, RESIDUAL_LIMIT)

    if precision["judged"] == 0:
        gate3 = "no data"
    else:
        gate3 = "pass" if precision["precision"] >= PRECISION_GATE else "fail"
    return {
        "items": len(items), "labeled": len(labeled),
        "flagPrecision": dict(precision, byKind=by_kind),
        "noHoldShare": {"checked": len(checked), "noHold": len(no_hold), "rate": S.rate(len(no_hold), len(checked)),
                        "uncheckedItems": len(items) - len(checked)},
        "residualError": {"n": n, "errors": errors, "rate": S.rate(errors, n), "upper95": upper,
                          "limit": RESIDUAL_LIMIT, "nNeeded": needed,
                          "nMore": max(0, needed - n) if needed else None,
                          "claimable": upper is not None and upper <= RESIDUAL_LIMIT},
        "gate3": {"rule": "flag precision >= 30%", "status": gate3,
                  "precision": precision["precision"], "lower95": precision["lower95"]},
    }


def render_text(result):
    fp, nh, re_ = result["flagPrecision"], result["noHoldShare"], result["residualError"]
    out = [f"Items {result['items']}, labeled {result['labeled']}", "",
           f"Flag precision  {fp['worthALook']}/{fp['judged']}  {S.pct(fp['precision'])}  "
           f"lower95 {S.pct(fp['lower95'])}  (unjudged {fp['unjudged']})"]
    for kind, b in fp["byKind"].items():
        out.append(f"  {kind:<12} {b['worthALook']}/{b['judged']}  {S.pct(b['precision'])}")
    out += ["", f"No holdsSend flag  {nh['noHold']}/{nh['checked']}  {S.pct(nh['rate'])}"
            f"  (flags not checked: {nh['uncheckedItems']})",
            f"Residual error (no holdsSend flag)  {re_['errors']}/{re_['n']}  {S.pct(re_['rate'], 2)}  "
            f"upper95 {S.pct(re_['upper95'], 2)}",
            f"  n needed for <= 1% at {re_['errors']} error(s): {re_['nNeeded']} "
            f"({re_['nMore']} more)" + ("  -> claimable" if re_["claimable"] else ""),
            "", f"Gate 3 (flag precision >= 30%): {result['gate3']['status']}"]
    return "\n".join(out)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0],
                                     formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__)
    parser.add_argument("manifest", help="labeled manifest.jsonl")
    parser.add_argument("--json", action="store_true", help="machine-readable output")
    parser.add_argument("--save", action="store_true", help="write score.json beside the manifest")
    args = parser.parse_args(argv)
    result = score(S.read_jsonl(args.manifest))
    if args.save:
        S.write_json(pathlib.Path(args.manifest).parent / "score.json", result)
    print(json.dumps(result, indent=2) if args.json else render_text(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
