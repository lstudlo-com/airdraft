"""Public official-build configuration. No merchant secrets belong here."""
import json
import plistlib
from pathlib import Path
from urllib.parse import urlparse
from uuid import UUID


def build_settings(path: Path) -> list[str]:
    config = json.loads(path.read_text())
    for name in ("organization_id",):
        try:
            if UUID(config[name]).int == 0:
                raise ValueError()
        except (ValueError, KeyError, TypeError, AttributeError):
            raise RuntimeError(f"Configure Polar {name} in {path}. See docs/licensing.md.")
    benefits = config.get("benefit_ids")
    try:
        if not isinstance(benefits, list) or not benefits:
            raise ValueError()
        parsed = [UUID(value) for value in benefits]
        if any(value.int == 0 for value in parsed) or len(set(parsed)) != len(parsed):
            raise ValueError()
    except (ValueError, TypeError, AttributeError):
        raise RuntimeError(f"benefit_ids must be a nonempty list of distinct nonzero UUIDs in {path}")
    for name in ("checkout_url", "customer_portal_url"):
        url = urlparse(config.get(name, ""))
        hosts = {"polar.sh", "buy.polar.sh"} if name == "checkout_url" else {"polar.sh"}
        if url.scheme != "https" or url.hostname not in hosts or url.username or url.password or url.port or not url.path.strip("/"):
            raise RuntimeError(f"{name} must use HTTPS and an approved Polar host: {', '.join(sorted(hosts))}")
        # These values become Xcode build settings; reject substitutions and controls.
        if any(char in config[name] for char in "$\n\r\t"):
            raise RuntimeError(f"Unsupported characters in {name}")
    if type(config.get("trial_days")) is not int or not 1 <= config["trial_days"] <= 90:
        raise RuntimeError("trial_days must be an integer from 1 to 90")
    return ["AIRDRAFT_DISTRIBUTION=official",
            f"AIRDRAFT_POLAR_ORGANIZATION={config['organization_id']}",
            f"AIRDRAFT_POLAR_BENEFITS={','.join(str(value) for value in parsed)}",
            f"AIRDRAFT_CHECKOUT_URL={config['checkout_url']}",
            f"AIRDRAFT_CUSTOMER_PORTAL_URL={config['customer_portal_url']}",
            f"AIRDRAFT_TRIAL_DAYS={config['trial_days']}"]


def verify_app(app: Path, settings: list[str]) -> None:
    with (app / "Contents/Info.plist").open("rb") as source:
        info = plistlib.load(source)
    keys = ["AirdraftDistribution", "AirdraftPolarOrganization", "AirdraftPolarBenefits",
            "AirdraftCheckoutURL", "AirdraftCustomerPortalURL", "AirdraftTrialDays"]
    for key, setting in zip(keys, settings, strict=True):
        if info.get(key) != setting.split("=", 1)[1]:
            raise RuntimeError(f"Official artifact has an incorrect {key}")


if __name__ == "__main__":
    for setting in build_settings(Path(__file__).with_name("licensing-config.json")):
        print(setting)
