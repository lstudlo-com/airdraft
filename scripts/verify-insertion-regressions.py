#!/usr/bin/env python3
"""Fail if an insertion regression is missing, skipped or failed in an Xcode result."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

# Stable regression contract. Renaming or retiring a case requires an intentional
# contract update; test discovery alone must not silently shrink this gate.
# AX-write cases were retired with the AX text-write path. The gate now
# covers one paste for both persisted settings plus cancellation during handoff.
# Caretless cases cover editors that draw their own text, such as Zed and Warp;
# their paste is sent unverified rather than reported as failed. Other caretless
# apps (Finder, an Electron app without a caret) keep the recovery outcome.
# Retries of caretless recordings copy only; Try It delivers through the
# explicit practice channel, never by pasting into Airdraft itself.
REQUIRED_TESTS = (
    'TextDeliveryRegressionTests/testIgnoredPasteKeepsRecoveryTextAndDoesNotReportDelivery()',
    'TextDeliveryRegressionTests/testDelayedPasteReportsDeliveryOnlyAfterExpectedTextArrives()',
    'TextDeliveryRegressionTests/testSlowReceiverCanReadClipboardAfterConfirmationDeadline()',
    'TextDeliveryRegressionTests/testPartialPasteOrCaretMovementCannotConfirmDelivery()',
    'TextDeliveryRegressionTests/testUnobservablePasteKeepsRecoveryTextEvenWhenItWasPosted()',
    'TextDeliveryRegressionTests/testConfirmedPasteReplacesUTF16SelectionAndPreservesSurroundingText()',
    'TextDeliveryRegressionTests/testIgnoredPasteThroughPipelineKeepsNoticeClipboardAndUndeliveredHistory()',
    'TextDeliveryRegressionTests/testIgnoredPasteAfterRefinementKeepsFinalTextAndRecoveryNotice()',
    # A validated caretless paste is sent unverified: no error, clipboard restored.
    'TextDeliveryRegressionTests/testCaretlessIgnoredPasteAfterRefinementIsSentUnverified()',
    'TextDeliveryRegressionTests/testCaretlessPasteThroughPipelineIsSentUnverifiedWithoutError()',
    'TextDeliveryRegressionTests/testCaretlessPasteRestoresClipboardLaterUnlessReplaced()',
    'TextDeliveryRegressionTests/testCancellationAfterCaretlessPasteKeepsSingleDeliveryAndRestore()',
    'TextDeliveryRegressionTests/testCaretEditorUnreadablePasteThroughPipelineKeepsRecovery()',
    'TextDeliveryRegressionTests/testEditorNormalizedPasteStillConfirmsDelivery()',
    # Only allowlisted self-drawing editors are sent unverified (AD-064 review).
    'TextDeliveryRegressionTests/testOnlySelfDrawingEditorsAreSentUnverified()',
    # A self-drawing editor that publishes a caret (Ghostty 1.3) is still sent unverified (AD-002 matrix).
    'TextDeliveryRegressionTests/testSelfDrawingEditorWithCaretIsSentUnverifiedWhenReadBackFails()',
    'TextDeliveryRegressionTests/testCaretlessNonEditorThroughPipelineKeepsRecoveryNoticeAndUndeliveredHistory()',
    'TextDeliveryRegressionTests/testCaretlessPasteAfterRefinementFailureSaysRawTextPasted()',
    'TextDeliveryRegressionTests/testQuitWaitsOutUnverifiedPasteBeforeRestoringClipboard()',
    'TextDeliveryRegressionTests/testRetryOfCaretlessRecordingCopiesWithoutPasting()',
    'TextDeliveryRegressionTests/testRetryOfCaretRecordingStillPastesAndConfirms()',
    'TextDeliveryRegressionTests/testPracticeDictationReachesPracticeEditorThroughPipeline()',
    'TextDeliveryRegressionTests/testPracticeChannelIsIgnoredOutsidePractice()',
    'HistoryStoreTests/testDeliveryStatusRoundTripsWithoutSchemaChange()',
    'TextInsertionTests/testUnconfirmedPasteDoesNotOverwriteNewClipboardOrClaimItKeptText()',
    'TextInsertionTests/testCancellationAfterUnconfirmedPasteKeepsRecoveryText()',
    'TextDeliveryRegressionTests/testCaptureFollowsAppSwitchBeforeRecordingStarts()',
    'TextDeliveryRegressionTests/testCaptureUsesSystemEditorWhenApplicationFocusIsStaleAfterSwitch()',
    'TextDeliveryRegressionTests/testRestorationUsesSystemEditorWhileApplicationFocusIsStale()',
    'TextDeliveryRegressionTests/testTransientFocusLossAtFinalValidationRetriesBeforePostingPaste()',
    'TextDeliveryRegressionTests/testCaptureWaitsForInitiallyValidButUnsettledEditor()',
    'TextDeliveryRegressionTests/testSlowAppActivationKeepsOriginalDestinationAndPastesOnce()',
    'TextDeliveryRegressionTests/testForeignSystemFocusCannotUseCachedApplicationEditor()',
    'TextDeliveryRegressionTests/testAlternateSelectionRangeStillDelivers()',
    'TextDeliveryRegressionTests/testAlwaysPasteCapturesAndDeliversToNativeEditor()',
    'TextDeliveryRegressionTests/testAppActivationWaitsForOriginalFieldBeforePaste()',
    'TextDeliveryRegressionTests/testApplicationWindowFallsBackToSystemEditorFocus()',
    'TextDeliveryRegressionTests/testCancellationWhileRestoringFocusNeverCopiesOrPastes()',
    'TextDeliveryRegressionTests/testCancelledInsertionNeverChangesClipboardOrDestination()',
    'TextDeliveryRegressionTests/testChangedFieldOrSelectionPreservesRecoveryTextWithoutPasting()',
    'TextDeliveryRegressionTests/testDefaultMethodDoesNotRequireAXValueOrWritableSelectedText()',
    'TextDeliveryRegressionTests/testEveryPersistedMethodPastesExactlyOnceWithoutAXTextWrites()',
    'TextDeliveryRegressionTests/testFrontmostEditorWaitsForTemporarilyUnavailableAXFocus()',
    'TextDeliveryRegressionTests/testNativeEditorCaptureWaitsWhenWebAccessibilityIsUnsupported()',
    'TextDeliveryRegressionTests/testPermissionLossDoesNotDeliverText()',
    'TextDeliveryRegressionTests/testPipelineWithContextOffCapturesPastesAndSavesDeliveredHistory()',
    'TextDeliveryRegressionTests/testForeignSystemFocusCannotAuthorizeCaretlessPaste()',
    'TextDeliveryRegressionTests/testCaretlessEditorPastesIntoItsFocusedWindow()',
    'TextDeliveryRegressionTests/testCaretlessEditorIsReactivatedBeforePaste()',
    'TextDeliveryRegressionTests/testCaretlessEditorRefusesAnotherWindow()',
    'TextDeliveryRegressionTests/testWebEditorStillWaitsForItsCaretAfterCaretlessSettleTime()',
    'TextDeliveryRegressionTests/testWebEditorCaptureWaitsForItsFieldThenDelivers()',
    'TextInsertionTests/testCancellationAfterPostingKeepsClipboardUntilReceiverCanRead()',
    'TextInsertionTests/testCaptureKeepsNativeSelectionAndDoesNotEnableWebAccessibility()',
    'TextInsertionTests/testCaptureNeverSubstitutesAnotherAppOrAnUnknownSelection()',
    'TextInsertionTests/testCaptureWaitsForTheWebEditorToExposeItsRealFieldAndCaret()',
    'TextInsertionTests/testEditorWithOnlySelectedTextRangesStillExposesItsCaret()',
    'TextInsertionTests/testEmptyClipboardIsRestoredAfterPaste()',
    'TextInsertionTests/testFailedPasteKeepsTextAvailableWithoutRetry()',
    'TextInsertionTests/testFocusRestorationWaitsForTheFieldAndSelectionAfterAppActivation()',
    'TextInsertionTests/testPasteDoesNotOverwriteNewClipboardOwnership()',
    'TextInsertionTests/testPasteRestoresAllOriginalItemsAndFormats()',
    'TextInsertionTests/testSelectionFallbackRejectsMultipleCaretsMalformedRangesAndTransportErrors()',
    'TextInsertionTests/testUnknownAndChangedSelectionCannotAuthorizeInsertion()',
    # Delivery releases the pipeline before clipboard restoration and history.
    'TextDeliveryRegressionTests/testHoldShortcutImmediatelyAfterConfirmedDeliveryStartsRecording()',
    'TextDeliveryRegressionTests/testToggleShortcutImmediatelyAfterConfirmedDeliveryStartsRecording()',
    'TextDeliveryRegressionTests/testQuitAndMaintenanceWaitForDeliveredDictationHistory()',
    'TextDeliveryRegressionTests/testShortcutDuringExclusiveWorkShowsReasonInsteadOfDroppingPress()',
    'TextInsertionTests/testNewerPasteTakesOverPendingRestoreWithoutClobbering()',
    'TextInsertionTests/testPendingRestoreKeepsAClipboardCopiedBeforeTheNextPaste()',
    'TextInsertionTests/testQuitRestoresConfirmedPasteClipboardWithoutWaitingForDelay()',
)


def validate_test_tree(tree, required=REQUIRED_TESTS):
    results = {name: [] for name in required}

    def descendant_results(node):
        values = []
        for child in node.get('children', []):
            if 'result' in child:
                values.append(child['result'])
            values.extend(descendant_results(child))
        return values

    def walk(node):
        if isinstance(node, list):
            for child in node:
                walk(child)
        elif isinstance(node, dict):
            name = node.get('nodeIdentifier')
            if node.get('nodeType') == 'Test Case' and name in results:
                url = node.get('nodeIdentifierURL', '')
                if '/AirdraftCoreTests/' in url:
                    results[name].append(node.get('result'))
                    results[name].extend(descendant_results(node))
            for child in node.get('children', []):
                walk(child)

    walk(tree.get('testNodes', []))
    missing = [name for name, values in results.items() if not values]
    unsuccessful = {name: values for name, values in results.items()
                    if values and any(value != 'Passed' for value in values)}
    if missing or unsuccessful:
        detail = []
        if missing:
            detail.append('Missing required insertion tests: ' + ', '.join(missing))
        if unsuccessful:
            detail.append('Required insertion tests did not pass: ' + json.dumps(unsuccessful))
        raise RuntimeError('; '.join(detail))
    return {'required': len(required), 'passed': len(results), 'tests': sorted(results)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('result_bundle', type=Path)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    result = subprocess.run(['xcrun', 'xcresulttool', 'get', 'test-results', 'tests',
                             '--path', str(args.result_bundle)], check=True,
                            text=True, capture_output=True)
    report = validate_test_tree(json.loads(result.stdout))
    report['resultBundle'] = str(args.result_bundle.resolve())
    if args.report:
        args.report.write_text(json.dumps(report, indent=2) + '\n')
    print(f"PASS: all {report['required']} mandatory insertion regressions executed and passed")


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f'Insertion regression gate failed: {error}', file=sys.stderr)
        sys.exit(1)
