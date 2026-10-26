#!/usr/bin/env python3
"""Tests for scripts/speed-metrics.py on synthetic data directories.

    python3 -B scripts/test-speed-metrics.py
"""
import contextlib, hashlib, importlib.util, io, json, pathlib, sys, tempfile, unittest
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "eval" / "speed"))
import speedlib as S  # noqa: E402
import synthetic  # noqa: E402

spec = importlib.util.spec_from_file_location("speed_metrics", ROOT / "scripts" / "speed-metrics.py")
SM = importlib.util.module_from_spec(spec)
spec.loader.exec_module(SM)

CHATGPT, CLAUDE, VSCODE = "com.openai.chat", "com.anthropic.claudefordesktop", "com.microsoft.VSCode"
LLM = "lmstudio:qwen"
F = synthetic.flag


def rows():
    secret = {"windowTitle": "SECRET-WINDOW", "url": "https://secret.example/SECRET-PATH"}
    return [
        dict(secret, createdAt="2026-10-20 10:00:00.000", appBundleId=CHATGPT, rawTranscript="SECRET-RAW-1 a",
             refinedText="  SECRET-RAW-1 a ", finalText="SECRET-FINAL-1", llmEngine=LLM, flags=[],
             sendRequest="auto", submitted=1),
        dict(secret, createdAt="2026-10-20 10:01:00.000", appBundleId=CHATGPT, rawTranscript="SECRET-RAW-2",
             refinedText="SECRET-REFINED-2", finalText="SECRET-FINAL-2", llmEngine=LLM,
             flags=[F("number", "SECRETFLAG-42"), F("negation", "SECRETFLAG-not")],
             sendRequest="shift", submitted=0),
        dict(createdAt="2026-10-20 10:02:00.000", appBundleId=CHATGPT, mode="Verbatim",
             rawTranscript="SECRET-RAW-3", refinedText="SECRET-RAW-3", finalText="SECRET-RAW-3"),
        dict(createdAt="2026-10-20 10:03:00.000", appBundleId=CLAUDE, rawTranscript="SECRET-RAW-4",
             refinedText="SECRET-REFINED-4", llmEngine=LLM, inserted=0, outputSucceeded=1,
             flags=[F("identifier", "SECRETFLAG-id", holds=False)]),
        dict(createdAt="2026-10-20 10:04:00.000", appBundleId=VSCODE, family="code", rawTranscript="SECRET-RAW-5",
             refinedText="SECRET-REFINED-5", llmEngine=LLM, inserted=0, outputSucceeded=0,
             flags=[F("newTerm", "SECRETFLAG-term")], sendRequest="auto", submitted=0),
        dict(createdAt="2026-10-01 09:00:00.000", appBundleId=CHATGPT, inserted=0, outputSucceeded=0),
        dict(secret, createdAt="2026-10-20 10:06:00.000", appBundleId="com.google.Chrome", family="code", flags=[]),
        dict(createdAt="2026-10-20 10:07:00.000", appBundleId=CHATGPT, outputDestination="copy",
             inserted=0, outputSucceeded=1, flags=[]),
        dict(createdAt="2026-10-20 10:08:00.000", appBundleId="com.apple.Safari.WebApp.SECRETAPP", mode="Message",
             flags=[F("recognition", "SECRETFLAG-rec")]),
        dict(createdAt="2026-10-20 10:09:00.000", appBundleId="com.google.Chrome.app.SECRETPWA", mode="Message",
             flags="not json"),
        dict(createdAt="2026-10-20 10:10:00.000", appBundleId="com.google.Chrome.app.SECRETPWA", mode="Message"),
        dict(createdAt="2026-10-20 10:11:00.000", appBundleId="com.mitchellh.ghostty", family="terminal",
             rawTranscript="SECRET-RAW-12", refinedText="SECRET-REFINED-12", llmEngine=LLM,
             outputDestination="script", inserted=0, outputSucceeded=1, flags=[]),
    ]


SAMPLES = [
    {"ms": 100, "transport": "builtIn", "at": "2026-10-20T10:00:00Z"},
    {"ms": 200, "transport": "builtIn", "at": "2026-10-20T10:00:01Z"},
    {"ms": 300, "transport": "builtIn", "at": "2026-10-20T10:00:02Z"},
    {"ms": 400, "transport": "builtIn", "at": "2026-10-20T10:00:03Z"},
    {"ms": 500, "transport": "bluetooth", "at": "2026-10-20T10:00:04Z"},
    {"ms": 700, "transport": "bluetooth", "at": "2026-10-20T10:00:05Z"},
    {"ms": 900, "transport": "bluetooth", "at": "2026-10-01T10:00:00Z"},
    {"ms": 50, "transport": "zzz", "at": "2026-10-20T10:00:06Z"},
]


def counts(delivered=0, unverified=0, failed=0):
    return {"delivered": delivered, "sentUnverified": unverified, "notDelivered": failed}


DELIVERIES = {
    CHATGPT: counts(3),
    CLAUDE: counts(0, 1),
    VSCODE: counts(0, 0, 1),
    "dev.warp.Warp-Stable": counts(0, 4),
    "com.apple.TextEdit": counts(9),                       # not an AI destination
    "com.google.Chrome": counts(5, 0, 2),                  # browsers never count
    "com.apple.Safari.WebApp.SECRETAPP": counts(2),
    "com.google.Chrome.app.SECRETPWA": counts(1, 1),
    "com.google.Chrome.app.SECRETPWA2": counts(0, 0, 1),
}


class ClopperPearsonTests(unittest.TestCase):
    def test_known_values(self):
        self.assertAlmostEqual(S.cp_lower(59, 59), 0.9505, places=4)
        self.assertAlmostEqual(S.cp_upper(0, 299), 0.00997, places=5)
        lo, hi = S.cp_interval(5, 20)
        self.assertAlmostEqual(lo, 0.0866, places=4)
        self.assertAlmostEqual(hi, 0.4910, places=4)
        self.assertEqual(S.cp_lower(0, 10), 0.0)
        self.assertEqual(S.cp_upper(10, 10), 1.0)
        self.assertIsNone(S.cp_lower(0, 0))

    def test_needed_sample_sizes(self):
        self.assertEqual(S.n_needed_for_lower(0), 59)
        self.assertEqual(S.n_needed_for_upper(0), 299)
        # Exact binomial; the vault's 474 and 630 are Poisson approximations.
        self.assertEqual(S.n_needed_for_upper(1), 473)
        self.assertEqual(S.n_needed_for_upper(2), 628)

    def test_betainc_symmetry(self):
        for a, b, x in ((2, 3, 0.4), (0.5, 7, 0.1), (30, 2, 0.95)):
            self.assertAlmostEqual(S.betainc(a, b, x), 1 - S.betainc(b, a, 1 - x), places=12)
        self.assertAlmostEqual(S.betainc(2, 3, 0.4), 0.5248, places=12)


class ReportTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.data = pathlib.Path(self.tmp.name) / "data"
        synthetic.make_history(self.data, rows())
        synthetic.write_counters(self.data, 3, 120, SAMPLES, deliveries=DELIVERIES)

    def tearDown(self):
        self.tmp.cleanup()

    def run_cli(self, *args):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = SM.main(["--data-dir", str(self.data), *args])
        self.assertEqual(code, 0)
        return out.getvalue()

    def test_report_numbers(self):
        report = json.loads(self.run_cli("--json"))
        self.assertEqual(report["window"]["dictations"], 12)
        ref = report["refinement"]
        self.assertEqual((ref["all"]["changed"], ref["all"]["n"]), (4, 12))
        self.assertEqual((ref["clean"]["changed"], ref["clean"]["n"]), (4, 8))
        self.assertEqual((ref["withRefiner"]["changed"], ref["withRefiner"]["n"]), (4, 5))

        fl = report["flags"]
        self.assertTrue(fl["columnPresent"])
        self.assertEqual((fl["unchecked"], fl["unreadable"]), (3, 1))
        self.assertEqual((fl["overall"]["flagged"], fl["overall"]["checked"]), (4, 8))
        self.assertAlmostEqual(fl["overall"]["rate"], 0.5)
        self.assertEqual(fl["overall"]["holdsSend"]["rows"], 3)
        self.assertEqual(fl["overall"]["holdsSend"]["nonHoldingFlags"], 1)
        for kind in S.FLAG_KINDS:
            self.assertEqual(fl["overall"]["byKind"][kind]["rows"], 1, kind)
        self.assertEqual((fl["codeTerminal"]["flagged"], fl["codeTerminal"]["checked"]), (1, 3))
        self.assertEqual((fl["other"]["flagged"], fl["other"]["checked"]), (3, 5))

        rb = report["readback"]
        self.assertTrue(rb["present"])
        self.assertEqual(rb["since"], "2026-10-01T00:00:00Z")
        o = rb["overall"]
        self.assertEqual((o["delivered"], o["n"], o["sentUnverified"], o["notDelivered"]), (3, 9, 5, 1))
        self.assertAlmostEqual(o["lower95"], S.cp_lower(3, 9))
        self.assertEqual(o["status"], "fail")
        x = rb["excludingSelfDrawing"]
        self.assertEqual((x["delivered"], x["n"]), (3, 5))
        self.assertEqual(sorted(rb["byDestination"]), sorted([CHATGPT, CLAUDE, VSCODE, "dev.warp.Warp-Stable"]))
        self.assertTrue(rb["byDestination"]["dev.warp.Warp-Stable"]["selfDrawing"])
        self.assertFalse(rb["byDestination"][VSCODE]["selfDrawing"])
        self.assertEqual(rb["byDestination"][CLAUDE]["label"], "Claude")
        self.assertNotIn("deliveries", report["counters"])

        self.assertEqual(report["send"]["table"],
                         {"auto": {"submitted": 1, "held": 1}, "shift": {"held": 1}, "none": {"null": 9}})
        web = report["webApps"]["byPrefix"]
        self.assertEqual(web["com.apple.Safari.WebApp."], {"destinations": 1, "deliveries": 2})
        self.assertEqual(web["com.google.Chrome.app."], {"destinations": 2, "deliveries": 3})

        c = report["counters"]
        self.assertAlmostEqual(c["ignoredPer100Accepted"], 2.5)
        self.assertEqual(c["capture"]["byTransport"]["builtIn"], {"n": 4, "medianMs": 250.0, "p90Ms": 400.0})
        self.assertEqual(c["capture"]["byTransport"]["bluetooth"], {"n": 3, "medianMs": 700.0, "p90Ms": 900.0})
        self.assertEqual(c["capture"]["byTransport"]["unknown"]["n"], 1)
        gates = {g["gate"]: g["status"] for g in report["gates"]}
        self.assertEqual(gates[1], "needs user test")
        self.assertEqual(gates[4], "needs user test")
        self.assertEqual(gates[5], "fail")

    def test_since_filter(self):
        report = json.loads(self.run_cli("--json", "--since", "2026-10-05"))
        self.assertEqual(report["window"]["dictations"], 11)
        self.assertEqual(report["refinement"]["clean"]["n"], 7)
        self.assertEqual(report["counters"]["capture"]["byTransport"]["bluetooth"],
                         {"n": 2, "medianMs": 600.0, "p90Ms": 700.0})

    def test_no_text_in_output(self):
        for output in (self.run_cli(), self.run_cli("--json")):
            self.assertNotIn("SECRET", output)
            self.assertNotIn("secret.example", output)
        text = self.run_cli()
        self.assertIn("Gates", text)
        self.assertIn("needs user test", text)
        self.assertIn("dev.warp.Warp-Stable", text)

    def test_pass_status_with_59_confirmations(self):
        data = pathlib.Path(self.tmp.name) / "pass"
        synthetic.make_history(data, [dict()])
        synthetic.write_counters(data, 0, 1, [], deliveries={CHATGPT: counts(40), CLAUDE: counts(19)})
        self.assertEqual(SM.build_report(data)["readback"]["overall"]["status"], "pass")
        synthetic.write_counters(data, 0, 1, [], deliveries={CHATGPT: counts(58)})
        self.assertEqual(SM.build_report(data)["readback"]["overall"]["status"],
                         "not yet: needs n >= 59 at 0 failure(s)")
        synthetic.write_counters(data, 0, 1, [], deliveries={"com.mitchellh.ghostty": counts(0, 80),
                                                             CHATGPT: counts(59)})
        report = SM.build_report(data)["readback"]
        self.assertEqual(report["overall"]["status"], "fail")
        self.assertEqual(report["excludingSelfDrawing"]["status"], "pass")
        self.assertIn("self-drawing: only sentUnverified possible", SM.render_text(SM.build_report(data)))

    def test_counters_without_deliveries(self):
        data = pathlib.Path(self.tmp.name) / "old-counters"
        synthetic.make_history(data, [dict(appBundleId=CHATGPT)])
        synthetic.write_counters(data, 1, 10, [])
        report = SM.build_report(data)
        self.assertFalse(report["readback"]["present"])
        self.assertEqual(report["readback"]["overall"]["status"], "no data")
        self.assertFalse(report["webApps"]["present"])
        self.assertIn("no deliveries counters yet", SM.render_text(report))

    def test_copy_is_read_only_and_deleted(self):
        data = pathlib.Path(self.tmp.name) / "wal"
        writer = synthetic.make_history(data, [dict(appBundleId=CHATGPT)] * 2, keep_open=True)
        try:
            self.assertTrue((data / "history.sqlite-wal").is_file())
            before = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in data.iterdir()}
            created = []
            real = tempfile.mkdtemp

            def spy(*a, **k):
                created.append(real(*a, **k))
                return created[-1]

            with mock.patch.object(tempfile, "mkdtemp", spy):
                report = SM.build_report(data)
            self.assertEqual(report["window"]["dictations"], 2)  # rows live only in the WAL
            self.assertEqual(len(created), 1)
            self.assertFalse(pathlib.Path(created[0]).exists())
            after = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in data.iterdir()}
            self.assertEqual(before, after)
        finally:
            writer.close()

    def test_copy_connection_is_read_only(self):
        with S.history_copy(self.data) as (conn, temp):
            self.assertNotEqual(temp.resolve(), self.data.resolve())
            with self.assertRaises(Exception):
                conn.execute("DELETE FROM dictation")

    def test_pre_v9_database(self):
        data = pathlib.Path(self.tmp.name) / "old"
        synthetic.make_history(data, [dict(appBundleId=CHATGPT)], wal=False)
        import sqlite3
        conn = sqlite3.connect(data / "history.sqlite")
        for column in ("flags", "sendRequest", "submitted"):
            conn.execute(f"ALTER TABLE dictation DROP COLUMN {column}")
        conn.commit(); conn.close()
        report = SM.build_report(data)
        self.assertFalse(report["flags"]["columnPresent"])
        self.assertFalse(report["send"]["columnPresent"])
        self.assertEqual(report["flags"]["unchecked"], 1)
        self.assertFalse(report["counters"]["present"])
        self.assertIn("older than migration v9-speed", SM.render_text(report))

    def test_missing_history(self):
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            code = SM.main(["--data-dir", str(pathlib.Path(self.tmp.name) / "none")])
        self.assertEqual(code, 1)

    def test_corpus_gate_statuses(self):
        corpus = pathlib.Path(self.tmp.name) / "corpus"
        corpus.mkdir()
        (corpus / "score.json").write_text(json.dumps({"gate3": {"status": "pass"}}))
        (corpus / "compare-summary.json").write_text(json.dumps({"gate2": {"status": "fail"}}))
        gates = {g["gate"]: g["status"] for g in SM.build_report(self.data, corpus=corpus)["gates"]}
        self.assertEqual((gates[2], gates[3]), ("fail", "pass"))


if __name__ == "__main__":
    unittest.main(verbosity=1)
