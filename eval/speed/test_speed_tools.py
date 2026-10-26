#!/usr/bin/env python3
"""Tests for the eval/speed tools on synthetic data (no real History, no network).

    python3 -B eval/speed/test_speed_tools.py
"""
import contextlib, io, json, pathlib, sys, tempfile, threading, unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import compare_answers  # noqa: E402
import export_corpus  # noqa: E402
import label  # noqa: E402
import score  # noqa: E402
import speedlib as S  # noqa: E402
import synthetic  # noqa: E402

F = synthetic.flag


def item(id, final="ok", reference="", intent=None, flags=(), judgments=None, family="general",
         bundle="com.apple.TextEdit", changes=None):
    flags = list(flags) if flags is not None else None
    return {"id": id, "family": family, "appBundleId": bundle, "mode": "Clean", "finalText": final,
            "rawTranscript": final, "flags": flags, "reference": reference, "intentCorrect": intent,
            "flagJudgments": judgments if judgments is not None else ([None] * len(flags or [])),
            "changesAIAnswer": changes, "audio": None}


class ExportTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.tmp.name)
        self.data = self.root / "data"
        synthetic.make_history(self.data, [
            dict(createdAt="2026-10-20 10:00:00.000", family="code", appBundleId="com.microsoft.VSCode",
                 rawTranscript="raw one", finalText="final one", recordingID="A1",
                 flags=[F("identifier", "fooBar")], sendRequest="shift", submitted=0),
            dict(createdAt="2026-10-20 10:01:00.000", family="general", finalText="final two", recordingID="A2"),
            dict(createdAt="2026-10-20 10:02:00.000", family="terminal", appBundleId="com.apple.Terminal",
                 finalText="final three", outputDestination="file", inserted=0, outputSucceeded=1),
            dict(createdAt="2026-10-01 10:00:00.000", family="code", finalText="old", recordingID="A3"),
        ], assets=[("A1", "one.wav", True), ("A2", "two.wav", False), ("A3", "three.wav", True)])

    def tearDown(self):
        self.tmp.cleanup()

    def test_export_manifest_and_audio(self):
        out = self.root / "corpus"
        result = export_corpus.export(self.data, out, since=S.parse_since("2026-10-10"))
        self.assertEqual((result["items"], result["audio"]), (3, 1))
        items = S.read_jsonl(out / "manifest.jsonl")
        self.assertEqual([i["finalText"] for i in items], ["final one", "final two", "final three"])
        first = items[0]
        self.assertEqual(first["audio"], "audio/one.wav")
        self.assertTrue((out / "audio" / "one.wav").is_file())
        self.assertEqual(first["flags"][0]["kind"], "identifier")
        self.assertEqual(first["flagJudgments"], [None])
        self.assertEqual((first["sendRequest"], first["submitted"]), ("shift", False))
        self.assertEqual((first["reference"], first["intentCorrect"], first["changesAIAnswer"]), ("", None, None))
        self.assertEqual(first["createdAt"], "2026-10-20T10:00:00Z")
        self.assertIsNone(items[1]["audio"])  # asset row without a file
        self.assertEqual(items[2]["deliveryStatus"], "delivered")  # file destination succeeded
        for key in ("id", "createdAt", "family", "appBundleId", "mode", "rawTranscript", "finalText", "flags",
                    "sendRequest", "submitted", "deliveryStatus", "audio", "reference", "intentCorrect",
                    "flagJudgments", "changesAIAnswer"):
            self.assertIn(key, first)

    def test_filters_limit_and_overwrite_guard(self):
        out = self.root / "c2"
        export_corpus.export(self.data, out, families={"code"}, audio_only=True)
        self.assertEqual([i["finalText"] for i in S.read_jsonl(out / "manifest.jsonl")], ["old", "final one"])
        with self.assertRaises(SystemExit):
            export_corpus.export(self.data, out)
        export_corpus.export(self.data, out, limit=1, force=True)
        self.assertEqual([i["finalText"] for i in S.read_jsonl(out / "manifest.jsonl")], ["final three"])

    def test_default_out_is_private(self):
        folder, explicit = export_corpus.resolve_out(None, today="2026-10-26")
        self.assertFalse(explicit)
        self.assertTrue(S.inside(folder, S.PRIVATE_DIR))
        self.assertEqual(folder.name, "2026-10-26")
        self.assertTrue(export_corpus.resolve_out(str(self.root / "x"))[1])

    def test_private_folder_is_git_ignored(self):
        gitignore = (HERE.parent.parent / ".gitignore").read_text().splitlines()
        self.assertIn("eval/speed/private/", gitignore)


class ScoreTests(unittest.TestCase):
    def test_precision_share_and_residual(self):
        items = [
            item(1, intent=True, flags=[F("number", "4"), F("negation", "not")], judgments=[True, False]),
            item(2, intent=True, flags=[F("identifier", "x", holds=False)], judgments=[True]),
            item(3, final="a  b", reference="a b", intent=True, flags=[]),
            item(4, final="a b", reference="a c", intent=True, flags=[]),  # reference differs -> error
            item(5, intent=False, flags=[]),                               # intent wrong -> error
            item(6, intent=None, flags=[]),                                # unlabeled
            item(7, intent=True, flags=None),                              # flags never checked
            item(8, intent=True, flags=[F("newTerm", "Zed")], judgments=[None]),
        ]
        result = score.score(items)
        fp = result["flagPrecision"]
        self.assertEqual((fp["worthALook"], fp["judged"], fp["unjudged"]), (2, 3, 1))
        self.assertAlmostEqual(fp["precision"], 2 / 3)
        self.assertEqual(fp["byKind"]["negation"]["precision"], 0.0)
        nh = result["noHoldShare"]
        self.assertEqual((nh["noHold"], nh["checked"], nh["uncheckedItems"]), (5, 7, 1))
        re_ = result["residualError"]
        self.assertEqual((re_["errors"], re_["n"]), (2, 4))
        self.assertAlmostEqual(re_["upper95"], S.cp_upper(2, 4))
        self.assertEqual(re_["nNeeded"], 628)
        self.assertEqual(result["gate3"]["status"], "pass")

    def test_gate3_fail_and_needed_n(self):
        items = [item(i, intent=True, flags=[F("number", "1")], judgments=[i == 0]) for i in range(4)]
        result = score.score(items)
        self.assertEqual(result["gate3"]["status"], "fail")  # 1/4 = 25%
        clean = score.score([item(i, intent=True, flags=[]) for i in range(299)])
        self.assertTrue(clean["residualError"]["claimable"])
        self.assertEqual(clean["residualError"]["nNeeded"], 299)
        self.assertEqual(score.score([item(1, intent=True, flags=[])])["residualError"]["nMore"], 298)

    def test_cli_save_and_json(self):
        with tempfile.TemporaryDirectory() as tmp:
            manifest = pathlib.Path(tmp) / "manifest.jsonl"
            S.write_jsonl(manifest, [item(1, intent=True, flags=[F("number", "1")], judgments=[True])])
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                score.main([str(manifest), "--json", "--save"])
            self.assertEqual(json.loads(out.getvalue())["gate3"]["status"], "pass")
            self.assertTrue((pathlib.Path(tmp) / "score.json").is_file())


class LabelTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.manifest = pathlib.Path(self.tmp.name) / "manifest.jsonl"
        S.write_jsonl(self.manifest, [
            item(1, final="hello world", flags=[F("number", "4"), F("negation", "not")]),
            item(2, final="second", flags=[]),
            item(3, final="third", flags=None),
        ])

    def tearDown(self):
        self.tmp.cleanup()

    def test_import_csv(self):
        csv_path = pathlib.Path(self.tmp.name) / "labels.csv"
        csv_path.write_text("id,reference,intentCorrect,flagJudgments,changesAIAnswer\n"
                            "1,hello word,n,y;n,y\n2,,yes,,\n", encoding="utf-8")
        self.assertEqual(label.import_csv(self.manifest, csv_path), 2)
        items = {i["id"]: i for i in S.read_jsonl(self.manifest)}
        self.assertEqual(items[1]["reference"], "hello word")
        self.assertIs(items[1]["intentCorrect"], False)
        self.assertEqual(items[1]["flagJudgments"], [True, False])
        self.assertIs(items[1]["changesAIAnswer"], True)
        self.assertEqual((items[2]["reference"], items[2]["intentCorrect"]), ("", True))
        self.assertIsNone(items[3]["intentCorrect"])

    def test_import_csv_rejects_bad_rows_atomically(self):
        csv_path = pathlib.Path(self.tmp.name) / "bad.csv"
        csv_path.write_text("id,intentCorrect,flagJudgments\n2,y,\n1,y,y\n9,y,\n", encoding="utf-8")
        with self.assertRaises(SystemExit) as caught:
            label.import_csv(self.manifest, csv_path)
        self.assertIn("expected 2 flag judgment", str(caught.exception))
        self.assertIn("unknown id", str(caught.exception))
        self.assertIsNone({i["id"]: i for i in S.read_jsonl(self.manifest)}[2]["intentCorrect"])

    def test_export_csv_round_trip(self):
        csv_path = pathlib.Path(self.tmp.name) / "out.csv"
        self.assertEqual(label.export_csv(self.manifest, csv_path), 3)
        self.assertIn("number:4; negation:not", csv_path.read_text(encoding="utf-8"))
        label.import_csv(self.manifest, csv_path)  # blank labels change nothing
        self.assertIsNone(S.read_jsonl(self.manifest)[0]["intentCorrect"])

    def test_interactive_resumes_and_saves_each_item(self):
        answers = iter(["", "y", "y", "n",   # item 1: keep final text, intent y, flags y/n
                        "q"])                # stop at item 2
        done = label.run_interactive(self.manifest, ask=lambda _: next(answers), out=lambda *_: None)
        self.assertEqual(done, 1)
        items = S.read_jsonl(self.manifest)
        self.assertEqual((items[0]["reference"], items[0]["intentCorrect"], items[0]["flagJudgments"]),
                         ("hello world", True, [True, False]))
        self.assertIsNone(items[1]["intentCorrect"])
        answers = iter(["s", "typed ref", "n"])
        done = label.run_interactive(self.manifest, ask=lambda _: next(answers), out=lambda *_: None)
        items = S.read_jsonl(self.manifest)
        self.assertEqual(done, 1)
        self.assertIsNone(items[1]["intentCorrect"])  # skipped
        self.assertEqual((items[2]["reference"], items[2]["intentCorrect"]), ("typed ref", False))

    def test_play_only_runs_afplay_inside_manifest_folder(self):
        calls = []
        audio = pathlib.Path(self.tmp.name) / "audio"
        audio.mkdir()
        synthetic.write_wav(audio / "a.wav")
        label.play(self.manifest.parent, {"audio": "audio/a.wav"}, runner=lambda *a, **k: calls.append(a[0]))
        with contextlib.redirect_stdout(io.StringIO()):
            label.play(self.manifest.parent, {"audio": "../../etc/passwd"}, runner=lambda *a, **k: calls.append(a[0]))
            label.play(self.manifest.parent, {"audio": None}, runner=lambda *a, **k: calls.append(a[0]))
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][0], "/usr/bin/afplay")


class FakeLLM(BaseHTTPRequestHandler):
    calls = []
    fail_first = 0
    bad_judge_first = 0

    def log_message(self, *args):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        FakeLLM.calls.append(body)
        if FakeLLM.fail_first > 0:
            FakeLLM.fail_first -= 1
            self.send_response(500); self.end_headers(); return
        system, user = body["messages"][0]["content"], body["messages"][1]["content"]
        if system == compare_answers.JUDGE_SYSTEM:
            if FakeLLM.bad_judge_first > 0:
                FakeLLM.bad_judge_first -= 1
                content = "I think they are similar."
            else:
                changed = "DIFFERENT" in user
                content = "<think>hmm {not json}</think>" + json.dumps(
                    {"equivalent": not changed, "reason": "test"})
        else:
            content = "DIFFERENT answer" if "typo" in user else "answer"
        payload = json.dumps({"choices": [{"message": {"role": "assistant", "content": content}}]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


class CompareTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), FakeLLM)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base = f"http://127.0.0.1:{cls.server.server_address[1]}/v1"
        compare_answers.BACKOFF_SECONDS = 0.01

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def setUp(self):
        FakeLLM.calls, FakeLLM.fail_first, FakeLLM.bad_judge_first = [], 0, 0
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = pathlib.Path(self.tmp.name)
        self.manifest = self.dir / "manifest.jsonl"
        S.write_jsonl(self.manifest, [
            item(1, final="fix the typo bug", reference="fix the auth bug", intent=False,
                 bundle="com.openai.chat", changes=True),
            item(2, final="run tests", reference="run the tests", intent=True, family="code",
                 bundle="com.microsoft.VSCode", changes=True),
            item(3, final="same", reference="same", intent=True, bundle="com.anthropic.claudefordesktop"),
            item(4, final="hi there", reference="hi bear", intent=False, bundle="com.apple.MobileSMS"),
            item(5, final="ls typo", reference="ls -la", intent=False, family="terminal",
                 bundle="com.apple.Terminal"),
        ])

    def tearDown(self):
        self.tmp.cleanup()

    def client(self, **kw):
        return compare_answers.Client(self.base, "fake-model", timeout=5, **kw)

    def test_selection(self):
        self.assertEqual([r["id"] for r in compare_answers.select_rows(S.read_jsonl(self.manifest))], [1, 2, 5])

    def test_run_writes_verdicts_summary_and_sample(self):
        FakeLLM.fail_first = 1       # first request 500 -> retried
        FakeLLM.bad_judge_first = 1  # first verdict unparsable -> asked again
        summary = compare_answers.run(self.manifest, self.client(retries=2), self.dir, log=lambda *_: None)
        self.assertEqual((summary["judged"], summary["changesAIAnswer"], summary["errors"]), (3, 2, 0))
        self.assertAlmostEqual(summary["rate"], 2 / 3)
        lo, hi = S.cp_interval(2, 3)
        self.assertEqual(summary["ci95"], [lo, hi])
        self.assertEqual(summary["gate2"]["status"], "fail")
        self.assertEqual(summary["humanAgreement"], {"n": 2, "agree": 1})
        self.assertEqual(summary["aiLabeledRows"], 4)
        self.assertEqual(len(summary["sample"]["ids"]), 1)  # ceil(20% of 3)
        verdicts = {v["id"]: v for v in S.read_jsonl(self.dir / "compare-verdicts.jsonl")}
        self.assertIs(verdicts[1]["changesAIAnswer"], True)
        self.assertIs(verdicts[2]["changesAIAnswer"], False)
        self.assertEqual(len(S.read_jsonl(self.dir / "compare-sample.jsonl")), 1)
        self.assertTrue((self.dir / "compare-summary.json").is_file())
        self.assertTrue(all(c["model"] == "fake-model" and c["temperature"] == 0.0 for c in FakeLLM.calls))
        # Seeded sample is stable, and a rerun reuses verdicts without requests.
        FakeLLM.calls = []
        again = compare_answers.run(self.manifest, self.client(), self.dir, log=lambda *_: None)
        self.assertEqual(again["sample"]["ids"], summary["sample"]["ids"])
        self.assertEqual(FakeLLM.calls, [])

    def test_bounded_retries_record_error(self):
        FakeLLM.fail_first = 100
        summary = compare_answers.run(self.manifest, self.client(retries=1), self.dir, limit=1, log=lambda *_: None)
        self.assertEqual((summary["judged"], summary["errors"]), (0, 1))
        self.assertEqual(len(FakeLLM.calls), 2)  # one try + one retry
        self.assertEqual(summary["gate2"]["status"], "no data")

    def test_gate2_status(self):
        self.assertEqual(compare_answers.gate2_status(0, 20), "pass")
        self.assertEqual(compare_answers.gate2_status(2, 10), "provisional pass (upper95 above 25%)")
        self.assertEqual(compare_answers.gate2_status(3, 10), "fail")

    def test_loopback_guard(self):
        self.assertTrue(compare_answers.is_loopback_url("http://127.0.0.1:1234/v1"))
        self.assertTrue(compare_answers.is_loopback_url("http://localhost:1234/v1"))
        self.assertTrue(compare_answers.is_loopback_url("http://[::1]:1234/v1"))
        self.assertFalse(compare_answers.is_loopback_url("https://api.openai.com/v1"))
        self.assertFalse(compare_answers.is_loopback_url("http://192.168.1.5:1234/v1"))
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            compare_answers.main([str(self.manifest), "--model", "m", "--base-url", "https://example.com/v1",
                                  "--out", str(self.dir)])
        self.assertEqual(FakeLLM.calls, [])

    def test_cli_against_fake_server(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
            compare_answers.main([str(self.manifest), "--model", "fake-model", "--base-url", self.base,
                                  "--out", str(self.dir / "o"), "--json"])
        self.assertEqual(json.loads(out.getvalue())["judged"], 3)

    def test_parse_verdict(self):
        self.assertEqual(compare_answers.parse_verdict('x {"equivalent": false, "reason": "r"} y'),
                         {"equivalent": False, "reason": "r"})
        self.assertIsNone(compare_answers.parse_verdict('{"equivalent": "yes"}'))
        self.assertIsNone(compare_answers.parse_verdict("<think>{\"equivalent\": true}</think>no"))


if __name__ == "__main__":
    unittest.main(verbosity=1)
