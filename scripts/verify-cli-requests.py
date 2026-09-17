#!/usr/bin/env python3
"""Local HTTP capture for the opt-in CLIRefiner integration tests. No inference billing.

Usage: verify-cli-requests.py codex|claudeCode /absolute/path/to/cli <CLIRefiner args...>
The test supplies the real app's flags. Only the endpoint/auth changes here.
"""
import http.server
import json
import os
from pathlib import Path
import subprocess
import sys
import threading

kind, executable, *arguments = sys.argv[1:]
requests = []


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"models":[],"data":[]}')

    def do_POST(self):
        data = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        if "messages" not in data and "input" not in data:
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'{}')
            return
        requests.append(data)
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        if kind == "codex":
            message = {"id": "msg_test", "type": "message", "role": "assistant", "status": "completed",
                       "content": [{"type": "output_text", "text": "這是一個測試。", "annotations": []}]}
            response = {"id": "resp_test", "object": "response", "status": "completed", "output": [message],
                        "usage": {"input_tokens": 1, "output_tokens": 1, "total_tokens": 2}}
            events = [
                {"type": "response.created", "response": {"id": "resp_test", "object": "response", "status": "in_progress", "output": []}},
                {"type": "response.output_item.done", "output_index": 0, "item": message},
                {"type": "response.completed", "response": response},
            ]
        else:
            events = [
                {"type": "message_start", "message": {"id": "msg_test", "type": "message", "role": "assistant",
                    "model": data["model"], "content": [], "stop_reason": None, "stop_sequence": None,
                    "usage": {"input_tokens": 1, "output_tokens": 0}}},
                {"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}},
                {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "這是一個測試。"}},
                {"type": "content_block_stop", "index": 0},
                {"type": "message_delta", "delta": {"stop_reason": "end_turn", "stop_sequence": None}, "usage": {"output_tokens": 1}},
                {"type": "message_stop"},
            ]
        for event in events:
            self.wfile.write(("event: " + event["type"] + "\ndata: " + json.dumps(event) + "\n\n").encode())
            self.wfile.flush()


server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
base = "http://127.0.0.1:" + str(server.server_port)
env = dict(os.environ)
if kind == "codex":
    # Keep stdin's '-' last. The local provider does not request OpenAI credentials.
    arguments[-1:-1] = ["-c", 'model_provider="airdraft_capture"', "-c",
        'model_providers.airdraft_capture={name="airdraft_capture",base_url="' + base + '/v1",wire_api="responses"}']
else:
    env["ANTHROPIC_BASE_URL"] = base
    env["ANTHROPIC_API_KEY"] = "local-test-placeholder"
    env.pop("ANTHROPIC_AUTH_TOKEN", None)
    env.pop("CLAUDE_CODE_OAUTH_TOKEN", None)
    env["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"

try:
    result = subprocess.run([executable, *arguments], input=sys.stdin.read(), text=True,
                            capture_output=True, env=env, timeout=30)
    if result.returncode:
        # Do not print arbitrary CLI stderr: it may contain account information.
        raise AssertionError(f"{kind} exited {result.returncode}")
    assert requests, "The CLI did not send an inference request"
    for data in requests:
        tools = data.get("tools", [])[:]
        for item in data.get("input", []):
            if item.get("type") == "additional_tools":
                tools.extend(item.get("tools", []))
        assert not tools, f"Unexpected tool schemas: {len(tools)}"
        system = data.get("system", data.get("instructions", ""))
        if kind == "codex":
            # Responses Lite places base instructions in a developer message.
            system = str(system) + "".join(str(item.get("content", "")) for item in data.get("input", []) if item.get("role") == "developer")
        serialized = json.dumps(data, ensure_ascii=False)
        assert "FIDELITY" in str(system), "The app's refinement system prompt was lost"
        for marker in ["You are Codex", "coding agent", "<skills_instructions>", "<environment_context>", "<collaboration_mode>"]:
            assert marker not in serialized, f"Unexpected coding context: {marker}"
        assert "AIRDRAFT_TEST_UNTRUSTED_EFFORT" not in serialized
        if kind == "codex":
            requested = next(value.split("=", 1)[1].strip('"') for value in arguments if value.startswith("model_reasoning_effort="))
            actual = data.get("reasoning", {}).get("effort")
        else:
            requested = arguments[arguments.index("--effort") + 1]
            actual = data.get("output_config", {}).get("effort", data.get("effort"))
        assert actual == requested, f"Requested {requested} effort, sent {actual}"
        global_docs = sum("# AGENTS.md instructions" in str(item) for item in data.get("input", []))
        summary = {"cli": kind, "model": data.get("model"), "tools": len(tools),
                          "system_chars": len(str(system)), "global_agents_messages": global_docs,
                          "effort": data.get("reasoning", data.get("output_config", data.get("effort")))}
        if report_dir := os.environ.get("AIRDRAFT_WIRE_REPORT_DIR"):
            Path(report_dir).mkdir(parents=True, exist_ok=True)
            Path(report_dir, kind + "-" + str(os.getpid()) + ".json").write_text(json.dumps(summary))
        print(json.dumps(summary), file=sys.stderr)
    sys.stdout.write(result.stdout)
finally:
    server.shutdown()
