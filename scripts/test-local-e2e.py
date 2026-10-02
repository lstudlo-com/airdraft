#!/usr/bin/env python3
"""Run the explicitly credential-free native regression selection.

The allowlist is intentional: running all AirdraftCoreTests also runs credential
and cloud-provider tests. Live app actions are documented in docs/local-e2e.md.
"""
import argparse
import json
import os
import signal
from pathlib import Path
import subprocess
import sys
import tempfile

SUITES = """
AudioRecorderTests AudioChunkerTests MicrophoneTests SpeechPreviewTests
AppleSpeechTranscriberTests
PipelinePreviewTests PipelineAutomationTests HistoryRetranscriptionTests
AudioHistoryTests ScriptDeliveryTests HistoryStoreTests ProfileStoreTests
DictionaryPostProcessorTests CLIProcessTests CLIModelCatalogTests
CLIEffortAndIsolationTests ModelOwnershipTests AppleIntelligenceTests
HotkeyPressStateTests HotkeyBehaviorTests ControlOptionHotkeyTests
SystemPermissionsTests MicrophonePermissionTests PipelineSafetyTests
LocalRecordingPrerequisitesTests CLIWarmPoolTests LMStudioControlTests
LocalModelCompletenessTests ModelDownloadProgressTests ParakeetTests AppSettingsTests LocalPersistenceTests
TextInsertionTests TextDeliveryRegressionTests AppContextTests PromptBuilderTests
SilentRecordingTests RefinementFidelityTests
EngineFactoryLeaseTests OnboardingProgressTests LicensingTests PolarLicenseWireTests
""".split()
CASES = """
AppIdentityTests/testDefaultsMigrationPreservesNewValuesAndRunsOnlyOnce
PersistenceRecoveryTests/testUnsavedDictionaryDraftCanBeRetriedAfterStorageRecovery
PersistenceRecoveryTests/testUnsavedProfileDraftSurvivesAndRetries
PersistenceRecoveryTests/testAliasRemovalPreservesSiblingsAndCanBeUndone
PersistenceRecoveryTests/testHistoryPaginationHasNoGapsWithEqualTimestamps
PersistenceRecoveryTests/testCalendarTodayExcludesYesterdayAcrossDST
HardeningTests/testUnreadableDictionaryIsSetAsideNotOverwritten
HardeningTests/testModelRemovalStaysInsideModelsFolder
HardeningTests/testCLIProcessTimesOutAndStops
HardeningTests/testCLIProcessDrainsLargeOutput
EngineFactoryTests/testLocalEnginesAreCachedPerModel
""".split()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--timeout", type=int, default=1800,
                        help="Overall Xcode deadline in seconds (default: 1800)")
    parser.add_argument("--parakeet-model", type=Path,
                        help="Existing downloaded INT8 folder; enables native reload/long-audio test")
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    root = Path(__file__).resolve().parents[1]
    output = (args.output or Path(tempfile.mkdtemp(prefix="airdraft-local-e2e-"))).resolve()
    output.mkdir(parents=True, exist_ok=True)
    result = output / "tests.xcresult"
    if result.exists():
        parser.error(f"Refusing to overwrite {result}; choose a fresh output directory")
    env = {key: os.environ[key] for key in
           ("HOME", "PATH", "TMPDIR", "USER", "LOGNAME", "LANG", "DEVELOPER_DIR")
           if key in os.environ}
    if args.parakeet_model:
        path = args.parakeet_model.resolve(strict=True)
        env["AIRDRAFT_PARAKEET_TEST_MODEL_DIR"] = str(path)
        env["TEST_RUNNER_AIRDRAFT_PARAKEET_TEST_MODEL_DIR"] = str(path)
    command = ["xcodebuild", "-project", "airdraft.xcodeproj", "-scheme", "airdraft",
               "-configuration", "Debug", "-skipPackagePluginValidation", "-skipMacroValidation",
               "-packageAuthorizationProvider", "netrc",
               "test", "-parallel-testing-enabled", "NO", "-resultBundlePath", str(result)]
    command += [f"-only-testing:AirdraftCoreTests/{name}" for name in SUITES + CASES]
    (output / "command.json").write_text(json.dumps(command, indent=2) + "\n")
    print(f"Credential-free regression results: {output}", flush=True)
    with (output / "tests.log").open("w") as log:
        process = subprocess.Popen(command, cwd=root, env=env, stdout=log,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = process.wait(timeout=args.timeout)
        except subprocess.TimeoutExpired:
            print(f"Xcode exceeded {args.timeout} seconds; stopping this test process group", flush=True)
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=5)
            code = 124
    print(f"xcodebuild exit: {code}; see {output / 'tests.log'}", flush=True)
    if code == 0:
        code = subprocess.run([sys.executable, str(root / 'scripts/verify-insertion-regressions.py'),
                               str(result), '--report', str(output / 'insertion-regressions.json')],
                              cwd=root, env=env).returncode
    return code


if __name__ == "__main__":
    raise SystemExit(main())
