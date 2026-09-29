import json
import plistlib
import tempfile
import unittest
from pathlib import Path
from licensing import build_settings, verify_app


class LicensingBuildTests(unittest.TestCase):
    def config(self):
        return dict(environment="production", organization_id="11111111-1111-4111-8111-111111111111",
                    benefit_ids=["22222222-2222-4222-8222-222222222222", "33333333-3333-4333-8333-333333333333"],
                    checkout_url="https://buy.polar.sh/polar_cl_test-only",
                    customer_portal_url="https://polar.sh/test-only/portal", trial_days=14)

    def test_missing_invalid_and_substituted_values_are_rejected(self):
        cases = [dict(environment="sandbox"), dict(environment="staging"), dict(environment=None),
                 dict(organization_id=""), dict(benefit_ids=[]), dict(benefit_ids="bad"),
                 dict(benefit_ids=["bad"]), dict(benefit_ids=[None]), dict(benefit_ids=["00000000-0000-0000-0000-000000000000"]),
                 dict(benefit_ids=[self.config()["benefit_ids"][0]] * 2), dict(trial_days=True), dict(trial_days=0),
                 dict(checkout_url="http://polar.sh/checkout/test"), dict(checkout_url="https://polar.sh.evil.test/a"),
                 dict(checkout_url="https://buy.polar.sh.evil.test/a"), dict(checkout_url="https://user@buy.polar.sh/a"),
                 dict(checkout_url="https://buy.polar.sh:443/a"), dict(checkout_url="https://sandbox.polar.sh/a"),
                 dict(customer_portal_url="https://buy.polar.sh/test-only/portal"),
                 dict(checkout_url="https://polar.sh/$(TOKEN)"), dict(customer_portal_url="https://polar.sh")]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "config.json"
            for change in cases:
                with self.subTest(change=change):
                    path.write_text(json.dumps(self.config() | change))
                    with self.assertRaises(RuntimeError): build_settings(path)

    def test_both_official_checkout_hosts_are_accepted(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "config.json"
            for url in ["https://polar.sh/checkout/test-only", "https://buy.polar.sh/polar_cl_test-only"]:
                path.write_text(json.dumps(self.config() | {"checkout_url": url}))
                self.assertIn(f"AIRDRAFT_CHECKOUT_URL={url}", build_settings(path))

    def test_final_artifact_must_match_official_config(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "config.json"
            path.write_text(json.dumps(self.config()))
            settings = build_settings(path)
            self.assertIn("AIRDRAFT_DISTRIBUTION=official", settings)
            self.assertIn("AIRDRAFT_POLAR_BENEFITS=" + ",".join(self.config()["benefit_ids"]), settings)
            app = root / "Fixture.app"
            (app / "Contents").mkdir(parents=True)
            keys = ["AirdraftDistribution", "AirdraftPolarEnvironment", "AirdraftPolarOrganization", "AirdraftPolarBenefits",
                    "AirdraftCheckoutURL", "AirdraftCustomerPortalURL", "AirdraftTrialDays"]
            info = dict(zip(keys, [x.split("=", 1)[1] for x in settings]))
            plist = app / "Contents/Info.plist"
            plist.write_bytes(plistlib.dumps(info))
            verify_app(app, settings)
            info["AirdraftPolarBenefits"] = self.config()["benefit_ids"][0]
            plist.write_bytes(plistlib.dumps(info))
            with self.assertRaises(RuntimeError): verify_app(app, settings)
            info["AirdraftPolarBenefits"] = ",".join(self.config()["benefit_ids"])
            info["AirdraftPolarEnvironment"] = "sandbox"
            plist.write_bytes(plistlib.dumps(info))
            with self.assertRaises(RuntimeError): verify_app(app, settings)
            info["AirdraftPolarEnvironment"] = "production"
            info["AirdraftDistribution"] = "community"
            plist.write_bytes(plistlib.dumps(info))
            with self.assertRaises(RuntimeError): verify_app(app, settings)

    def test_sandbox_settings_cannot_be_used_for_an_official_release(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "sandbox.json"
            config = self.config() | dict(environment="sandbox",
                checkout_url="https://sandbox.polar.sh/checkout/test-only",
                customer_portal_url="https://sandbox.polar.sh/test-only/portal")
            path.write_text(json.dumps(config))
            sandbox = build_settings(path, environment="sandbox")
            self.assertIn("AIRDRAFT_POLAR_ENVIRONMENT=sandbox", sandbox)
            with self.assertRaises(RuntimeError): build_settings(path)
            for field, url in [("checkout_url", self.config()["checkout_url"]),
                               ("customer_portal_url", self.config()["customer_portal_url"]),
                               ("checkout_url", "https://sandbox.polar.sh.evil.test/checkout/test-only")]:
                path.write_text(json.dumps(config | {field: url}))
                with self.subTest(field=field, url=url), self.assertRaises(RuntimeError):
                    build_settings(path, environment="sandbox")


if __name__ == "__main__": unittest.main()
