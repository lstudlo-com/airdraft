#!/usr/bin/env python3
"""AD-082: compare punctuation for SenseVoice/FireRedASR2 output against Qwen3-ASR's.

  python3 -I eval/mixed-asr/punctuation_eval.py --work <dir> --tag after --punct-bin <harness> --punct-model <model.int8.onnx>

Neither corpus has punctuated references, so Qwen3-ASR 1.7B (zh) finals from
results/utterances.csv, which punctuate every output, serve as a proxy. Tokens
(Han characters and Latin words) of both texts are aligned with difflib; for each
aligned token we compare whether a punctuation mark follows it. Reported for
(a) the shipped rule (sentence-final mark only) and (b) sherpa-onnx's offline
CT-Transformer zh-en punctuation model (int8, evaluation harness only), which is
also checked for token changes (it must only insert punctuation).
"""
import argparse, csv, difflib, json, pathlib, re, subprocess, sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from score import HAN, to_traditional  # noqa: E402

MARK = r"，。？！、；：,.?!;:…"


def marked_tokens(text):
    tokens = []
    for piece in re.findall(rf"[{HAN}]|[A-Za-z0-9']+|[{MARK}]", text):
        if re.fullmatch(rf"[{MARK}]", piece):
            if tokens:
                tokens[-1][1] = True
        else:
            tokens.append([piece.lower(), False])
    return tokens


def boundary_scores(pairs):
    tp = fp = fn = 0
    for hyp, ref in pairs:
        h, r = marked_tokens(hyp), marked_tokens(ref)
        matcher = difflib.SequenceMatcher(a=[t for t, _ in h], b=[t for t, _ in r], autojunk=False)
        for block in matcher.get_matching_blocks():
            for k in range(block.size):
                hm, rm = h[block.a + k][1], r[block.b + k][1]
                tp += hm and rm
                fp += hm and not rm
                fn += rm and not hm
    precision = tp / (tp + fp) if tp + fp else 0
    recall = tp / (tp + fn) if tp + fn else 0
    f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0
    return {"precision": round(precision, 3), "recall": round(recall, 3), "f1": round(f1, 3), "marks_ref": tp + fn}


def strip(text):
    return re.sub(rf"[\s{MARK}]", "", text).lower()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--work", required=True, type=pathlib.Path)
    parser.add_argument("--tag", default="after")
    parser.add_argument("--punct-bin", type=pathlib.Path)
    parser.add_argument("--punct-model", type=pathlib.Path)
    parser.add_argument("--out", type=pathlib.Path)
    args = parser.parse_args()
    qwen = {r["id"]: r["final"] for r in csv.DictReader(open(HERE / "results/utterances.csv"))
            if r["model"] == "qwen3:1.7b" and r["language"] == "zh" and r["final"]}
    report = {}
    for config in ["sherpa_senseVoice-auto", "sherpa_fireRed-auto"]:
        runs = [json.loads(p.read_text()) for p in sorted((args.work / f"runs-{args.tag}" / config).glob("*-0.json"))]
        runs = [r for r in runs if r.get("final") and r["id"] in qwen and r["corpus"] in ("ascend", "tw-tts-meijia")]
        finals = [r["final"] for r in runs]
        refs = to_traditional([qwen[r["id"]] for r in runs])
        bare = [re.sub(rf"[{MARK}]$", "", f) for f in finals]
        entry = {"utterances": len(runs), "shipped_rule": boundary_scores(zip(finals, refs)),
                 "no_punctuation": boundary_scores(zip(bare, refs))}
        if args.punct_bin and args.punct_model:
            proc = subprocess.run([str(args.punct_bin), str(args.punct_model)], input="\n".join(bare) + "\n",
                                  capture_output=True, text=True, check=True)
            lines = [line.split("\t", 1) for line in proc.stdout.splitlines()]
            ms = sorted(float(t) for t, _ in lines)
            outputs = to_traditional([o for _, o in lines])
            entry["ct_transformer"] = boundary_scores(zip(outputs, refs))
            entry["ct_transformer"]["token_changes"] = sum(strip(o) != strip(b) for o, b in zip(outputs, to_traditional(bare)))
            entry["ct_transformer"]["latin_han_spaces_removed"] = sum(
                bool(re.search(rf"[A-Za-z] [{HAN}]|[{HAN}] [A-Za-z]", b)) and not re.search(rf"[A-Za-z] [{HAN}]|[{HAN}] [A-Za-z]", o)
                for o, b in zip(outputs, bare))
            entry["ct_transformer"]["ms_median"] = ms[len(ms) // 2]
            entry["ct_transformer"]["examples"] = [{"input": b, "output": o} for b, o in list(zip(bare, outputs))[:8]]
        report[config] = entry
    text = json.dumps(report, ensure_ascii=False, indent=1)
    if args.out:
        args.out.write_text(text + "\n")
    print(text)


if __name__ == "__main__":
    main()
