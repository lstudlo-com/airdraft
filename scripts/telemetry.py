"""Public official-build telemetry configuration: a PostHog project token and host.

The token is a client-side project token (it already ships in the website bundle),
not a secret. Only official release builds embed it; source, community and Polar
Sandbox builds keep the empty defaults and never offer telemetry.
"""
import json
import plistlib
import re
from pathlib import Path

HOSTS = ("https://us.i.posthog.com", "https://eu.i.posthog.com")
TOKEN = re.compile(r"phc_[A-Za-z0-9]+")
KEYS = ("AirdraftTelemetryToken", "AirdraftTelemetryHost")


def build_settings(path: Path) -> list[str]:
    try:
        config = json.loads(Path(path).read_text())
    except (OSError, ValueError) as error:
        raise RuntimeError(f"Unreadable telemetry configuration {path}: {error}")
    token, host = config.get("posthog_token"), config.get("posthog_host")
    if not isinstance(token, str) or not TOKEN.fullmatch(token):
        raise RuntimeError(f"posthog_token must be a PostHog project token (phc_…) in {path}. See docs/telemetry.md.")
    if host not in HOSTS:
        raise RuntimeError(f"posthog_host must be exactly one of {', '.join(HOSTS)} in {path}")
    return [f"AIRDRAFT_TELEMETRY_TOKEN={token}", f"AIRDRAFT_TELEMETRY_HOST={host}"]


def embedded(app: Path) -> dict:
    with (Path(app) / "Contents/Info.plist").open("rb") as source:
        info = plistlib.load(source)
    return {key: info.get(key) for key in KEYS}


def verify_app(app: Path, settings: list[str]) -> None:
    values = embedded(app)
    for key, setting in zip(KEYS, settings, strict=True):
        if values[key] != setting.split("=", 1)[1]:
            raise RuntimeError(f"Official artifact has an incorrect {key}")


def verify_absent(app: Path) -> None:
    """Sandbox, Debug and community builds must embed no telemetry configuration."""
    values = embedded(app)
    if any(values.values()):
        raise RuntimeError(f"This build must not embed telemetry configuration: {sorted(k for k, v in values.items() if v)}")


if __name__ == "__main__":
    for setting in build_settings(Path(__file__).with_name("telemetry-config.json")):
        print(setting)
