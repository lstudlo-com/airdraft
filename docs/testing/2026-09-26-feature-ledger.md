# Feature coverage ledger, 2026-09-26

This ledger contains 153 grouped acceptance cases. A partial result does not certify every variant in that row. Live actions use disposable app data; controlled regressions and source review are labelled separately. All API-key-dependent actions and credential operations are excluded. See [the audit](2026-09-26-local-e2e.md) for measured model, microphone, automation, updater and build evidence.


## Window, navigation and app menu

| ID | Test action | Verdict | Evidence and limits |
|---|---|---|---|
| WI-01 | Launch isolated app, open from menu, reopen via Finder/Spotlight | Live partial pass | Isolated launch and main-window reopen via Sky succeeded repeatedly with one main window. Finder/Spotlight UI itself not automated. |
| WI-02 | Click Home, Profiles, Vocabulary, History, Configuration, Models | Live pass | Every destination clicked and corresponding heading/selection inspected. |
| WI-03 | Press Cmd+1 through Cmd+6 | Live pass | Cmd1 through Cmd6 individually asserted matching Home/Profiles/Vocabulary/History/Configuration/Models headings. |
| WI-04 | Press Cmd+comma, use Settings menu | Live shortcut pass; menu variant unavailable | Cmd+comma opens Configuration. Sky omits the app Settings menu and reopens a closed main window when capturing state; that variant is not claimed live. |
| WI-05 | Collapse and expand sidebar on every page | Live partial pass | Root collapse and Light; agent Dark/Auto/Light immediate selection. Every page/height/restart combination requires render evidence. |
| WI-06 | Resize height to 600 and taller, scroll each page to bottom | Root renders + live partial | Root48 page/size/appearance renders and window-resize verification cover fixed width, minimum/tall heights and lower sections. Sticky backdrop blur requires live observation; every combination not independently replayed here. |
| WI-07 | Close and minimize window | Live actions pass; visibility limitation | Close and Minimize controls invoked; subsequent app activation reopens main window and process survives. Sky activates/reopens during capture, so hidden-window duration is not observable. |
| WI-08 | Switch Auto, Light, Dark | Live partial pass | Root collapse and Light; agent Dark/Auto/Light immediate selection. Every page/height/restart combination requires render evidence. |
| WI-09 | Inspect Reduce Transparency and increased contrast | Unavailable hardware/OS condition | No OS setting changes or permission resets performed; only built-in input and current permission state available. |
| WI-10 | Open native menu bar | Live actual MenuView fixture partial | Real production MenuView hosted in DEBUG isolated window. Ready/Listening/Apple built-in/SenseVoice Loaded→Not loaded/Apple Intelligence unavailable states asserted; all processing microstates rely on pipeline tests. |
| WI-11 | Menu Start Dictation, Stop & Transcribe, Cancel | Live real MenuView actions pass | Start with cursor blocked into actionable Home; script-output Start→Listening, microphone disabled, Cancel→Ready, silent Stop→Ready.160rows unchanged; receiver output absent. |
| WI-12 | Menu Profile and non-key Refinement pickers | Live real MenuView actions pass | Profile Clean→Concise persisted to Profiles. Apple Intelligence selection reports unavailable, restored Off. Session snapshot races covered in pipeline tests. |
| WI-13 | Menu Microphone, Open Airdraft, History | Live real MenuView actions pass | Named microphone selection reflected in Configuration/sidebar. Open Airdraft and History open correct main page; microphone picker disabled while recording. Status-item placement itself unavailable in Sky AX tree. |
| WI-14 | Menu Unload Models with no/one local model resident | Live real MenuView actions pass | Apple selected hides Unload. Loaded SenseVoice exposes Unload; action changes status to Not loaded and hides itself. Home Load Model returns Loaded. |
| WI-15 | Quit idle | Live pass | Idle Quit Airdraft terminated isolated process; process list empty. Safe no-argument relaunch guard prevented tool auto-restart escaping isolation. |
| WI-16 | Quit while recording, downloading, recoverable audio or unsaved storage error | Live primary paths + core errors | Keep Open while downloading preserves download; while recording preserves Listening. Quit and Discard during recording terminated after asynchronous cleanup; idle Quit also terminated. Storage/recovery variants covered by core/shutdown harness, not every GUI error injection. |
| WI-17 | Debug account button and close/Escape/outside-click | Live pass | Sample-account notice visible; Close, Escape and outside-pointer dismissals all return to prior page. |

## Home and readiness

| ID | Test action | Verdict | Evidence and limits |
|---|---|---|---|
| HO-01 | Empty isolated history | Live pass for empty-history state | After Delete All, Home showed zero metrics, first-dictation setup guidance and No dictations yet. Sidebar count defect fixed and verified separately: one deletion reduced 3,993→3,843; Delete All showed Ready to dictate. |
| HO-02 | Seed varied records, load Home | Live partial pass | Root Home fixture statistics/Today/collapse; navigation verified. Full calendar boundary/hover matrix remains unit/source. |
| HO-03 | Choose All Time, Last 7 Days, Today, switch rapidly | Live settings + core date tests | All time, Last7days and Today selected and content updated. Full calendar/timezone boundaries rely on core tests. |
| HO-04 | Hover waveform bars then leave | Tool unavailable; source reviewed | Sky has no hover/move-pointer API. Click/drag would change interaction semantics; hover-only bar tooltip not claimed live. |
| HO-05 | Readiness header ready and attention states | Live partial pass | Root Home fixture statistics/Today/collapse; navigation verified. Full calendar boundary/hover matrix remains unit/source. |
| HO-06 | Shortcut Change / Grant Accessibility | Live partial pass + source | Matching readiness states/actions observed; actual permission grants/revocations were not performed. |
| HO-07 | Cursor Accessibility / script Configure row | Live partial pass + source | Matching readiness states/actions observed; actual permission grants/revocations were not performed. |
| HO-08 | Microphone Allow / Settings row | Live partial pass + source | Matching readiness states/actions observed; actual permission grants/revocations were not performed. |
| HO-09 | Speech Get Model / Load Model | Live pass for load; source missing-asset link | Home Speech Not loaded→Load Model→Loaded after menu unload. Actual missing/corrupt model source and core checks documented separately. |
| HO-10 | Refinement Models / Profiles | Live partial pass + source | Matching readiness states/actions observed; actual permission grants/revocations were not performed. |
| HO-11 | Recent View All | Live pass | View All opens History from Home. |
| HO-12 | Force failed speech, Retry / recovery menu Change Provider / Discard | Unit/integration + source | Pipeline safety/history tests cover failures, recovery and persistence; each visible error interaction not forced in live GUI. |
| HO-13 | Notice Dismiss | Live pass | Blocked recording permission notice appears on Home; Dismiss removes current notice. |
| HO-14 | Failed history read/save, Retry, Copy Last Dictation | Unit/integration + source | Pipeline safety/history tests cover failures, recovery and persistence; each visible error interaction not forced in live GUI. |

## Microphones and permissions

| ID | Test action | Verdict | Evidence and limits |
|---|---|---|---|
| MI-01 | Open sidebar capsule | Live partial pass | Built-in microphone overlay, live meter and Escape dismissal exercised. Multi-device/VoiceOver focus claims not inferred. |
| MI-02 | Observe ten-cell meters for all devices | Live partial pass | Built-in microphone overlay, live meter and Escape dismissal exercised. Multi-device/VoiceOver focus claims not inferred. |
| MI-03 | Close via Close, Escape, outside click; navigate away | Live partial pass | Built-in microphone overlay, live meter and Escape dismissal exercised. Multi-device/VoiceOver focus claims not inferred. |
| MI-04 | Start dictation with overlay open | Unit/source + root hardware evidence | See pipeline-coverage.md and root capture self-test for exact scope; physical unplug/route-change not generated here. |
| MI-05 | Set Input 2, switch System Default ↔ same named device via sidebar, Configuration and menu | Fixed; real-source harness pass | Shared route selection preserves Input2 for identical resolved device and resets for a different route. Physical multichannel interface unavailable. |
| MI-06 | Choose different device, restart app | Unit/source + root hardware evidence | See pipeline-coverage.md and root capture self-test for exact scope; physical unplug/route-change not generated here. |
| MI-07 | Multi-input device, every valid channel | Unavailable hardware/OS condition | No OS setting changes or permission resets performed; only built-in input and current permission state available. |
| MI-08 | Selected device disconnected / saved channel unavailable | Unavailable hardware/OS condition | No OS setting changes or permission resets performed; only built-in input and current permission state available. |
| MI-09 | Permission not determined, deny, allow; configuration Request/Open Settings | Unavailable hardware/OS condition | No OS setting changes or permission resets performed; only built-in input and current permission state available. |
| MI-10 | Permission denied/restricted during overlay | Unavailable hardware/OS condition | No OS setting changes or permission resets performed; only built-in input and current permission state available. |
| MI-11 | Same-device format change or output change during capture | Unit/source + root hardware evidence | See pipeline-coverage.md and root capture self-test for exact scope; physical unplug/route-change not generated here. |
| MI-12 | Accessibility grant/revoke while running | Unavailable hardware/OS condition | No OS setting changes or permission resets performed; only built-in input and current permission state available. |

## Keyboard shortcuts

| ID | Test action | Verdict | Evidence and limits |
|---|---|---|---|
| HK-01 | Default Control+Option hold, both left/right modifiers | Unit/source partial | Core hotkey/session tests cover state invariants; every real global hardware key combination not generated by automation. |
| HK-02 | Toggle mode, press twice | Unit/source partial | Core hotkey/session tests cover state invariants; every real global hardware key combination not generated by automation. |
| HK-03 | Record Shortcut with ordinary modified key | Live pass for listed primary actions | Recorded reserved CtrlOptionShiftCmd9, Escape cancels, sidebar navigation ends recorder, Reset restores ControlOption. Persistence across restart not separately asserted. |
| HK-04 | Record single left/right modifier, fn, multi-modifier combo | Unit/source partial | Core hotkey/session tests cover state invariants; every real global hardware key combination not generated by automation. |
| HK-05 | Record fn+ordinary key | Unit/source partial | Core hotkey/session tests cover state invariants; every real global hardware key combination not generated by automation. |
| HK-06 | Recorder Cancel or Escape | Live pass for listed primary actions | Recorded reserved CtrlOptionShiftCmd9, Escape cancels, sidebar navigation ends recorder, Reset restores ControlOption. Persistence across restart not separately asserted. |
| HK-07 | Leave Configuration while recorder active | Live pass for listed primary actions | Recorded reserved CtrlOptionShiftCmd9, Escape cancels, sidebar navigation ends recorder, Reset restores ControlOption. Persistence across restart not separately asserted. |
| HK-08 | Press current Carbon shortcut inside recorder | Fixed; live + real Carbon harness pass | Same Carbon combination can be rerecorded without starting capture. Registry contention regression failed baseline and passes fix. |
| HK-09 | Reset shortcut button | Live pass for listed primary actions | Recorded reserved CtrlOptionShiftCmd9, Escape cancels, sidebar navigation ends recorder, Reset restores ControlOption. Persistence across restart not separately asserted. |
| HK-10 | Register conflicting ordinary shortcut | Unit/source partial | Core hotkey/session tests cover state invariants; every real global hardware key combination not generated by automation. |
| HK-11 | Escape during recording | Unit/source partial | Core hotkey/session tests cover state invariants; every real global hardware key combination not generated by automation. |
| HK-12 | Release during microphone permission/model startup wait | Unit/source partial | Core hotkey/session tests cover state invariants; every real global hardware key combination not generated by automation. |
| HK-13 | Simulate missed release/tap interruption/wake | Unit/source partial | Core hotkey/session tests cover state invariants; every real global hardware key combination not generated by automation. |
| HK-14 | Change shortcut while active/cancelling | Unit/source partial | Core hotkey/session tests cover state invariants; every real global hardware key combination not generated by automation. |

## Configuration and HUD

| ID | Test action | Verdict | Evidence and limits |
|---|---|---|---|
| CO-01 | Auto/Light/Dark choice tiles and persisted restart | Live partial pass | Root collapse and Light; agent Dark/Auto/Light immediate selection. Every page/height/restart combination requires render evidence. |
| CO-02 | Maximum Recording arrows and typed values | Live typed bounds and stepper pass | 99999→1800, 1→10, 300; invalid text Return and blank Tab restore 300. Increment/decrement changed 300→310→300. Integer-overflow text not separately injected. |
| CO-03 | Maximum duration reached | Unit/integration + live setting pass | Timer/context invariants exercised in core; toggle live. Context from actual third-party target apps not read. |
| CO-04 | Read App Context on/off | Unit/integration + live setting pass | Timer/context invariants exercised in core; toggle live. Context from actual third-party target apps not read. |
| CO-05 | Output cursor/script toggle | Live settings + unit/integration pass | Cursor/script and auto/paste UI choices worked. Actual external AX insertion/paste event remains root evidence, not this UI run. |
| CO-06 | Accessibility then paste / Always Paste | Live settings + unit/integration pass | Cursor/script and auto/paste UI choices worked. Actual external AX insertion/paste event remains root evidence, not this UI run. |
| HU-01 | Classic while recording and processing | Live setting + source/harness partial | All HUD style tiles selected; root pipeline/HUD renders supply recording evidence. Every timing/rapid session variant not live asserted here. |
| HU-02 | Mini while recording and processing | Live setting + source/harness partial | All HUD style tiles selected; root pipeline/HUD renders supply recording evidence. Every timing/rapid session variant not live asserted here. |
| HU-03 | None before starting | Live setting + source/harness partial | All HUD style tiles selected; root pipeline/HUD renders supply recording evidence. Every timing/rapid session variant not live asserted here. |
| HU-04 | Classic/Mini → None during recording/notice | Fixed; real NSPanel harness pass | Actual controller Classic→None→Mini→None visibility assertions passed using fixture pipeline/content. |
| HU-05 | Idle and failure/notice timing; rapid new recording | Live setting + source/harness partial | All HUD style tiles selected; root pipeline/HUD renders supply recording evidence. Every timing/rapid session variant not live asserted here. |
| HU-06 | Move pointer across displays/Spaces | Unavailable hardware/OS condition | No OS setting changes or permission resets performed; only built-in input and current permission state available. |

## Automation and delivery

| ID | Test action | Verdict | Evidence and limits |
|---|---|---|---|
| AU-01 | Open Shortcuts button | Live pass | Open Shortcuts launched the previously absent installed Shortcuts process. No Shortcuts data was read or changed. |
| AU-02 | Choose Script valid executable, non-executable, directory, Cancel | Live partial pass | Cancel preserved path; nonexecutable rejected; executable accepted. Directory choice disallowed by panel source; not manually selected. |
| AU-03 | Script path spaces and metacharacters; literal final text incl shell syntax | Unit/integration + root hardware automation | See pipeline-coverage.md; root actual Start/Stop/Cancel and literal script delivery with physical microphone. UI did not execute chooser fixture. |
| AU-04 | Script success, nonzero exit, hang, excessive output, missing file | Unit/integration + root hardware automation | See pipeline-coverage.md; root actual Start/Stop/Cancel and literal script delivery with physical microphone. UI did not execute chooser fixture. |
| AU-05 | Change output/path/insertion mode during recording | Unit/integration + root hardware automation | See pipeline-coverage.md; root actual Start/Stop/Cancel and literal script delivery with physical microphone. UI did not execute chooser fixture. |
| AU-06 | Start/Stop/Cancel Shortcuts commands with app running | Unit/integration + root hardware automation | See pipeline-coverage.md; root actual Start/Stop/Cancel and literal script delivery with physical microphone. UI did not execute chooser fixture. |
| AU-07 | Commands during startup, duplicate start, no active capture, processing, approved shutdown | Unit/integration + root hardware automation | See pipeline-coverage.md; root actual Start/Stop/Cancel and literal script delivery with physical microphone. UI did not execute chooser fixture. |
| AU-08 | Successful automation | Unit/integration + root hardware automation | See pipeline-coverage.md; root actual Start/Stop/Cancel and literal script delivery with physical microphone. UI did not execute chooser fixture. |
| AU-09 | Review-only transcription or insertion disabled with script configured | Unit/integration + root hardware automation | See pipeline-coverage.md; root actual Start/Stop/Cancel and literal script delivery with physical microphone. UI did not execute chooser fixture. |

## Profiles and prompt editor

| ID | Test action | Verdict | Evidence and limits |
|---|---|---|---|
| PR-01 | Select every built-in profile | Live pass | Each Clean/Concise/Summary/Verbatim selected; instruction/task/refinement fields match profile. Browsing other rows retains Concise active marker. |
| PR-02 | Use Profile in editor and context menu | Live partial pass | Root created/renamed/duplicated/activated/edited/previewed/deleted fixtures. Every built-in/context-menu/empty-name/permutation not independently repeated. |
| PR-03 | New Profile | Live partial pass | Root created/renamed/duplicated/activated/edited/previewed/deleted fixtures. Every built-in/context-menu/empty-name/permutation not independently repeated. |
| PR-04 | Rename via action menu/context menu, Return, blur, page leave, empty/whitespace | Live partial pass | Root created/renamed/duplicated/activated/edited/previewed/deleted fixtures. Every built-in/context-menu/empty-name/permutation not independently repeated. |
| PR-05 | Duplicate normal and Verbatim profiles | Live pass for normal and Verbatim | Root duplicated normal custom profile; agent duplicated Verbatim and verified copied refinement remains off, active Concise unchanged. |
| PR-06 | Delete custom: Cancel / confirm; attempt built-in deletion | Live partial pass | Root created/renamed/duplicated/activated/edited/previewed/deleted fixtures. Every built-in/context-menu/empty-name/permutation not independently repeated. |
| PR-07 | Modify built-in, Reset Profile Cancel/confirm | Live pass for primary actions | Verbatim refinement toggle/reset Cancel+Confirm; ResetAll Cancel+Confirm; warning Continue; custom base Save; Restore+Cancel retains custom; Restore+Save defaults. Root checked empty Save. |
| PR-08 | Reset All Cancel/confirm | Live pass for primary actions | Verbatim refinement toggle/reset Cancel+Confirm; ResetAll Cancel+Confirm; warning Continue; custom base Save; Restore+Cancel retains custom; Restore+Save defaults. Root checked empty Save. |
| PR-09 | Refine Transcript toggle | Live pass for primary actions | Verbatim refinement toggle/reset Cancel+Confirm; ResetAll Cancel+Confirm; warning Continue; custom base Save; Restore+Cancel retains custom; Restore+Save defaults. Root checked empty Save. |
| PR-10 | Edit Profile Instructions and optional Task, switch rows/restart | Live partial pass | Root created/renamed/duplicated/activated/edited/previewed/deleted fixtures. Every built-in/context-menu/empty-name/permutation not independently repeated. |
| PR-11 | Preview Prompt then Done | Live partial pass | Root created/renamed/duplicated/activated/edited/previewed/deleted fixtures. Every built-in/context-menu/empty-name/permutation not independently repeated. |
| PR-12 | Base Edit warning Cancel/Continue | Live pass for primary actions | Verbatim refinement toggle/reset Cancel+Confirm; ResetAll Cancel+Confirm; warning Continue; custom base Save; Restore+Cancel retains custom; Restore+Save defaults. Root checked empty Save. |
| PR-13 | Base draft edit then Cancel/Save | Live pass for primary actions | Verbatim refinement toggle/reset Cancel+Confirm; ResetAll Cancel+Confirm; warning Continue; custom base Save; Restore+Cancel retains custom; Restore+Save defaults. Root checked empty Save. |
| PR-14 | Base Restore Defaults then Cancel/Save | Live pass for primary actions | Verbatim refinement toggle/reset Cancel+Confirm; ResetAll Cancel+Confirm; warning Continue; custom base Save; Restore+Cancel retains custom; Restore+Save defaults. Root checked empty Save. |
| PR-15 | Force profile storage failure; Retry Saving; quit | Unit/integration + source | Forced persistence failures covered by isolated core tests; live app storage-failure controls not forced. |

## Vocabulary

| ID | Test action | Verdict | Evidence and limits |
|---|---|---|---|
| VO-01 | Add preferred spelling with no replacement via Add and Return | Live partial + unit pass | Root add/remove/Undo/no-match search; store tests cover persistence and dedup. Every keyboard/context-menu permutation not manually repeated. |
| VO-02 | Add mishearing → replacement | Live partial + unit pass | Root add/remove/Undo/no-match search; store tests cover persistence and dedup. Every keyboard/context-menu permutation not manually repeated. |
| VO-03 | Empty/whitespace word; duplicate alias | Live partial + unit pass | Root add/remove/Undo/no-match search; store tests cover persistence and dedup. Every keyboard/context-menu permutation not manually repeated. |
| VO-04 | Search term, alias, case variants, unmatched, clear | Live partial + unit pass | Root add/remove/Undo/no-match search; store tests cover persistence and dedup. Every keyboard/context-menu permutation not manually repeated. |
| VO-05 | Remove term / one of several aliases using trash and context menu | Live partial + unit pass | Root add/remove/Undo/no-match search; store tests cover persistence and dedup. Every keyboard/context-menu permutation not manually repeated. |
| VO-06 | Undo term/alias removal | Live partial + unit pass | Root add/remove/Undo/no-match search; store tests cover persistence and dedup. Every keyboard/context-menu permutation not manually repeated. |
| VO-07 | Remove a from [a,b], add c to same term, Undo | Fixed; real store regression pass | Undo now merges removed aliases without overwriting aliases or term/case edited later; LocalPersistenceTests. |
| VO-08 | Dictate replacement case/boundaries/Chinese mix | Unit/integration pass | DictionaryPostProcessorTests and pipeline ordering; actual model quality in root report. |
| VO-09 | Storage failure and Retry Saving | Unit/integration + source | Forced persistence failures covered by isolated core tests; live app storage-failure controls not forced. |

## Local speech and Models page

| ID | Test action | Verdict | Evidence and limits |
|---|---|---|---|
| MO-01 | Search by model title/vendor/note, no match, clear; All/On this Mac | Live partial pass | No-match/sense search; All/OnThisMac exclude cloud; all installed local row controls inspected. SenseVoice select→Home Loaded→Apple restore. |
| MO-02 | Inspect every local model row | Live partial pass | No-match/sense search; All/OnThisMac exclude cloud; all installed local row controls inspected. SenseVoice select→Home Loaded→Apple restore. |
| MO-03 | Click uninstalled model | Live pass | Clicking Use SenseVoice after its fixture files were deleted left Apple selected; no incomplete selection. |
| MO-04 | Download each supported family in isolated model root | Live SenseVoice + root all-family downloads | SenseVoice downloaded to isolated model root, completed, selected and loaded. Root separately downloaded and transcribed with all local families. |
| MO-05 | Cancel download, navigate away/back, retry, two model downloads | Live primary paths + core concurrency | SenseVoice Cancel and Resume worked; download persisted across Home/Models navigation; Quit Keep Open retained it. Simultaneous downloads covered by store tests, not repeated UI. |
| MO-06 | Change provider while earlier download runs | Live pass | Started SenseVoice download; chose Qwen0.6 then Apple before completion. Finished SenseVoice exposes Delete while Apple remains selected. |
| MO-07 | Delete unselected isolated model Cancel/confirm | Live pass | Delete SenseVoice Cancel preserves files; Confirm removes only isolated SenseVoice and changes action to Download. Reinstalled successfully. |
| MO-08 | Selected/busy/loading model delete | Live selected-state pass + source busy checks | Selected loaded SenseVoice Delete button explicitly disabled. Busy/loading disable logic reviewed; every timing variant not forced. |
| MO-09 | Select installed model then another | Live partial pass | No-match/sense search; All/OnThisMac exclude cloud; all installed local row controls inspected. SenseVoice select→Home Loaded→Apple restore. |
| MO-10 | Language automatic and each listed/manual-preserved language | Source + root real inference | English selection/Apple en-US observed; not every listed/custom locale or ASR language manually selected. |
| MO-11 | Chinese script Original/Simplified/Traditional | Live settings + unit pass | Auto/Simplified/Traditional choices all selected; postprocessing tests cover conversion. |
| MO-12 | Apple Speech locale listed and saved custom locale | Source + root real inference | English selection/Apple en-US observed; not every listed/custom locale or ASR language manually selected. |
| MO-13 | Idle unload After 5/10/30/Never | Live settings + unit/source | All four idle policies selected then10min restored; real elapsed5/10/30min unload not awaited. |
| MO-14 | Corrupt/incomplete/missing model and failed preparation | Core/integration + source | Root model completeness and preparation error tests cover corrupt/incomplete/missing files and retries. GUI exercised uninstalled Use without selecting incomplete files; corrupt model preparation UI was not forced. |

## Non-key refinement

| ID | Test action | Verdict | Evidence and limits |
|---|---|---|---|
| RE-01 | Off | Live/integration pass | Off persisted; actual Apple/SenseVoice readiness and review used no refinement; core confirms no refiner execution. |
| RE-02 | Apple Intelligence readiness, Test, Cancel, profile variants | Unavailable; error UI pass | System reports Apple Intelligence preparing; Test shows same useful failure. Successful on-device refinement not claimed. |
| RE-03 | Claude Code/Codex Locate Again | Live partial + source | Claude CLI Locate Again and model/effort controls inspected; no account access. Not every custom/model/refresh permutation executed. |
| RE-04 | CLI model discovery/refresh, default, listed and custom model; switch providers | Live partial + source | Claude CLI Locate Again and model/effort controls inspected; no account access. Not every custom/model/refresh permutation executed. |
| RE-05 | CLI Test, Cancel, actual dictation and warm/cold paths | Root local CLI + unit evidence | See root report for actual subscription CLI outcomes; agent did not run authenticated CLI Test from GUI. |
| RE-06 | Loopback server preset, base URL, model ID, Test, Load/Unload | Live refusal + lifecycle harness | Explicit loopback127.0.0.1:1 Test produced connection failure. Root mock/local lifecycle harness covers Load/Unload/error ownership. |
| RE-07 | Advanced disclosure, temperature, timeout, minimum-word threshold, thinking effort | Live partial + unit | Advanced opened, timeout999→120 and minwords-1→0; other provider numeric/effort/temperature variants source reviewed. |
| RE-08 | Unload LM Studio on quit on/off | Real-source lifecycle + core pass | Endpoint attribution/failed unload ownership/generation fixes tested by verifier; session snapshots tested in pipeline. |
| RE-09 | Provider/model/profile changes during dictation; timeout/cancellation | Real-source lifecycle + core pass | Endpoint attribution/failed unload ownership/generation fixes tested by verifier; session snapshots tested in pipeline. |

## Live preview

| ID | Test action | Verdict | Evidence and limits |
|---|---|---|---|
| LP-01 | Show Text While Speaking on/off; Open Models | Live pass for toggle/navigation | Show text while speaking toggle persists; Configuration Open Models button opens Models preview controls. |
| LP-02 | Every supported locale, ready/missing assets, Install/Cancel | Live locale partial + root asset/inference | zh-TW missing displayed Install; en-US displayed Ready. Every offered locale install/cancel not performed. |
| LP-03 | Classic/Mini recording with installed language | Root real preview + core pass | See root reports for actual preview; injected callback/queue/failure/session independence tests passed. |
| LP-04 | Toggle off or HUD None during recording | Root real preview + core pass | See root reports for actual preview; injected callback/queue/failure/session independence tests passed. |
| LP-05 | Missing assets/error/interruption/new session | Root real preview + core pass | See root reports for actual preview; injected callback/queue/failure/session independence tests passed. |
| LP-06 | Stop/cancel recording and inspect saved output | Root real preview + core pass | See root reports for actual preview; injected callback/queue/failure/session independence tests passed. |

## Audio history, history cards and retranscription

| ID | Test action | Verdict | Evidence and limits |
|---|---|---|---|
| HI-01 | Empty, seeded, long and 2,000-record history | Live 260 + root 2000 render/performance pass | 160 then 260 disposable records exercised. Final build18 root 2000-record check: zero regrouping, 59 card bodies per 180 scroll events in both appearances; p95 approximately 35ms. |
| HI-02 | Search text, raw/refined/final variants, unmatched, clear | Live partial pass | No-match→42→clear search and filtered timeline worked. Every raw/refined-only/rapid stale-query variant not manually repeated. |
| HI-03 | Load Older Dictations | Live pass | Appended100 synthetic text rows; initial200 then LoadOlder revealed remaining60, last fixture100/ID260 reached. No automatic paging feature claimed. |
| HI-04 | Timeline tick click, card scroll, bottom-to-top | Fixed; live navigation + performance pass | Baseline lazy AX edge crash reproduced four times. Build18 search no-match→42→clear→last→first survives; both columns page and jump correctly, Next/Previous Dictation and timestamp jump track the correct active row. Bounded child labels readable; 2,000-record performance has zero regrouping and 59 card updates per 180 scroll events. Full VoiceOver rotor interaction not automated. |
| HI-05 | Long text expand/collapse, version Raw/Refined, scroll away/back | Live pass for expansion/version persistence | Long text expansion/collapse and Original/Refined switching persist across scroll eviction/navigation. Native collapsed layout remains bounded; build18 native word selection and substring Copy pass. Very long text sizing is additionally checked by root 2,000-record render harness. |
| HI-06 | Copy button and context menu, text selection | Live pointer and copy pass; AX limitation recorded | Build18 single-window: native doubleclick visibly selects original; Cmd-C→Search pastes original. Copy button and metadata context-menu Copy paste the complete expected sentence. Native text right-click menu works. Text accessibilityRepresentation exposes readable text/actions but omits AX selected-text readback; full VoiceOver rotor/range interaction is not automated. |
| HI-07 | Details expand/collapse | Live pass for primary actions | Visible and offscreen Details show correct record metadata; dismissal works. Context menu Copy/Play/Retranscribe/Delete inspected. |
| HI-08 | Delete single via button/context menu Cancel/confirm | Live pass for text/audio records | Single text fixture4 Cancel/Confirm only removes that row. Later first150-word audio record261 removed; sidebar3993→3843 immediately; remaining rows preserved. |
| HI-09 | Delete All Cancel/confirm | Fixed; live pass | DeleteAll Cancel preserves rows. Confirm empties History and Home; sidebar now Ready to dictate (previously stale count). Generation guarded refresh also runs after save/retry. |
| HI-10 | Keep Recordings Off/1d/7d/30d/Until Deleted, save/restart | Live choices/cleanup + core retention pass | 1d/7d/30d/UntilDeleted selected. Off removed all3 audio references/sidecars and playback/retranscribe controls, retaining259 text rows. Core covers expiration/orphans/save recovery. |
| HI-11 | Turn retention Off, launch/hourly/save/setting cleanup, forced failure Retry | Live cleanup + core ownership pass | Off left259 text rows and zero WAV sidecars; History audio controls gone. Per-entry audio delete still not separately repeated. |
| HI-12 | Play/Stop via card and context menu; play second record | Live partial + core | Played first then second recording and observed StopPlayback. Navigation stop/root pipeline covered; corrupt audio UI not forced. |
| HI-13 | Navigate away, begin recording, delete or prune currently playing | Live partial + core | Played first then second recording and observed StopPlayback. Navigation stop/root pipeline covered; corrupt audio UI not forced. |
| HI-14 | Retranscribe saved audio | Live actual Apple review pass, rerun after AX fix | Accurate English fixture transcript; Raw/Refined and Copy→Copied/Close work. Repeated successful review with final History candidate; original SQLite count unchanged before cleanup. |
| HI-15 | Review Raw/Refined, Copy, Close | Live actual Apple review pass, rerun after AX fix | Accurate English fixture transcript; Raw/Refined and Copy→Copied/Close work. Repeated successful review with final History candidate; original SQLite count unchanged before cleanup. |
| HI-16 | Review processing Cancel, failure Retry, close then new session | Core pass; live partial | Review cancellation/retry/stale isolation tested in core; success review live. ErrorRetry live not forced. |
| HI-17 | Persistent write/read failures and retry | Unit/integration + source | Forced persistence failures covered by isolated core tests; live app storage-failure controls not forced. |

## Updates and distribution boundaries

| ID | Test action | Verdict | Evidence and limits |
|---|---|---|---|
| UP-01 | E2E/Debug update section | Live isolated pass | Version displayed; Check/auto toggles disabled under explicit E2E args. Root added fail-safe after no-arg relaunch escape. |
| UP-02 | Production-signed fixture Check for Updates menu/button | Root signed updater fixture/source evidence | Root reported real signed feed/tamper/download/install-on-quit/relaunch fixture passing; see update report for precise boundaries. Not inferred from Debug GUI. |
| UP-03 | Automatic Checks on/off and Automatic Downloads dependency | Root signed updater fixture/source evidence | Root reported real signed feed/tamper/download/install-on-quit/relaunch fixture passing; see update report for precise boundaries. Not inferred from Debug GUI. |
| UP-04 | Download completes during dictation | Root signed updater fixture/source evidence | Root reported real signed feed/tamper/download/install-on-quit/relaunch fixture passing; see update report for precise boundaries. Not inferred from Debug GUI. |
| UP-05 | Installer mount, drag to Applications, identity/update migration | Root signed updater fixture/source evidence | Root reported real signed feed/tamper/download/install-on-quit/relaunch fixture passing; see update report for precise boundaries. Not inferred from Debug GUI. |
