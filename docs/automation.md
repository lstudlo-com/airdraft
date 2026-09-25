# Automation

Configure output in **Configuration → Output and automation**. The default remains **Insert at cursor**. **Send to script** runs the executable you choose after refinement, Chinese conversion and vocabulary replacement. The destination, script path and insertion method are fixed when recording starts, including any later retry of failed speech recognition. History records script completion separately from cursor insertion. Reviewing old audio never sends text to a script.

## Shortcuts

Airdraft exposes **Start Dictation**, **Stop Dictation** and **Cancel Dictation** in Apple Shortcuts. Start returns after recording begins; Stop begins transcription and returns while processing continues. Repeated Start does not toggle recording off. Cancel discards the active session, but cannot undo delivery once it has started.

The actions run in the background and reuse normal permissions, model readiness, recovery and focus checks. Keep the intended editor focused when using cursor output. If Shortcuts or another app changes focus, Airdraft cannot infer the previous target. Script output does not require Accessibility for insertion, though app context and modifier-only hotkeys still use it. Early actions wait up to ten seconds for app startup; recording startup has a fifteen-second deadline. Actions are rejected once approved shutdown begins.

These are main-app [AudioRecordingIntent](https://developer.apple.com/documentation/appintents/audiorecordingintent) actions with an [AppShortcutsProvider](https://developer.apple.com/documentation/appintents/appshortcutsprovider), supporting macOS 15+. macOS 26+ uses explicit [background execution](https://developer.apple.com/documentation/appintents/appintent/supportedmodes).

## Script delivery

`ScriptDelivery.send(text:to:timeout:)` sends final text once to an absolute, executable, regular file selected by the user. The executable receives **exact UTF-8 text on stdin**, with no added newline and no arguments. Airdraft invokes the file directly through `Process.executableURL`; it does not construct a shell command or interpolate the text. A script needs its own shebang. Its working directory is its parent folder, and it inherits the app's environment.

Successful delivery means all input was written and the process exited with status zero. It does not prove that a downstream app or service accepted the text. Stdout is ignored; a nonzero exit returns at most 300 characters of stderr. Missing files, execute permission errors and nonregular files fail before launch. `unavailableReason(path:)` provides the same check for configuration and recording prerequisites.

The default deadline is **10 seconds**. Cancellation or timeout closes Airdraft's pipes, requests termination, and kills the selected process after one second if it remains running. Airdraft never retries delivery automatically: a script may already have performed external actions before an error. Scripts should finish their work before exiting, avoid detached children, and handle duplicate requests themselves when appropriate. Airdraft cannot undo script effects or guarantee termination of descendants that detach from the selected process.

The shared `CLIProcess` runner drains stdout and stderr while writing stdin, retains at most **1 MiB per output stream**, and reports capture truncation. Its nonblocking poll loop checks cancellation and a monotonic deadline even when the parent has exited but a descendant still holds pipes. Incomplete stdin delivery cannot report success. Per-descriptor `F_SETNOSIGPIPE` handles an early reader exit without changing the app's global signal behavior. Existing warm-session and line-reader interfaces remain unchanged.

## Example script

Save this as `dictation.sh`, make it executable with `chmod +x dictation.sh`, then select it in Configuration. It appends each result to a text file in the same directory.

```sh
#!/bin/sh
set -eu
/bin/cat >> dictations.txt
/usr/bin/printf '\n' >> dictations.txt
```

Script failures leave the final text available in History and show an error. They never trigger a paste or an automatic second execution.

## Validation and references

Validated September 26, 2026: the complete suite ran 266 tests with zero failures and three existing skips. The built app contains all three discoverable AudioRecording intents and App Shortcuts with background execution. Light and dark settings renders were inspected. Shortcuts invocation, cold launch and insertion into a real focused editor remain manual checks.

Tests use temporary executable fixtures only. They cover literal Unicode, newlines and shell metacharacters; path validation; nonzero status and bounded errors; output beyond both capture limits; blocked stdin; early reader exit; cancellation; timeout after parent exit; and no automatic retries. No user-selected script is run by the test suite.

The process contract follows Apple's [Process documentation](https://developer.apple.com/documentation/foundation/process), including [Pipe handling for standard output](https://developer.apple.com/documentation/foundation/process/standardoutput), and the Darwin [poll](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/poll.2.html) and [write](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/write.2.html) contracts. `O_NONBLOCK` and `F_SETNOSIGPIPE` were checked in the installed macOS SDK's `sys/fcntl.h` on September 26, 2026.
