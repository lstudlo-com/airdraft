# Automation

Configure output in **Settings → Output and automation**. The default remains **Insert at cursor**. **Send to script** runs the executable you choose after refinement, Chinese conversion and vocabulary replacement. The destination, script path and insertion method are fixed when recording starts, including any later retry of failed speech recognition. History records script completion separately from cursor insertion. Reviewing old audio never sends text to a script.

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

Save this as `dictation.sh`, make it executable with `chmod +x dictation.sh`, then select it in Settings. It appends each result to a text file in the same directory.

```sh
#!/bin/sh
set -eu
/bin/cat >> dictations.txt
/usr/bin/printf '\n' >> dictations.txt
```

Script failures leave the final text available in History and show an error. They never trigger a paste or an automatic second execution.

## Profile destinations (AD-104)

Each profile can choose its own **Send to** in Profiles → Output: **Use App Default** (the setting above), **Insert at Cursor**, **Copy Only** or **Add to File**. The choice is captured with the rest of the recording when it starts. **Copy Only** puts the final text on the clipboard and pastes nothing. **Add to File** appends the final text as its own line to the file you chose, creating it when needed. Its path may contain `{date}` (`yyyy-MM-dd`), `{time}` (`HH-mm`) and `{app}` (the destination app's name, with `/` and `:` replaced); nothing else is filled in and a model never chooses the path. Writes use `NSFileCoordinator`, so a file in an iCloud folder such as an Obsidian vault is safe. A missing folder blocks recording before the microphone opens, and a failed write keeps the text in History without a paste. History stores these outputs as `copy` and `file`.

## Sending after the paste (AD-104)

Return is pressed only after a paste that the original field confirmed, and only once:

- **Shift to send** (Settings → Send after pasting, off by default): press Shift while recording; the recording window shows **Send ↩**. Each press toggles the lock. It is unavailable when the shortcut itself uses Shift, for edits, and for destinations other than the cursor.
- **Send automatically** (per profile): for AI chats and agents. It never applies in browsers, email, work chat or personal messaging apps, and never without read-back confirmation.
- **Flags** hold a send: numbers or negations that refinement changed, names refinement introduced, code-like words not in Vocabulary (optional) and speech-guard corrections. The text stays pasted; by default the recording window lists up to three flagged phrases and you press Return yourself, or choose **Paste Without Sending**.
- The cancel window counts from the release and overlaps processing: 1 second for a Shift-locked send, 0.5 seconds for an automatic one. Esc during it keeps the paste and sends nothing.
- Editors that draw their own text (Warp, Zed, Ghostty and similar) cannot confirm a paste. A Shift-locked send presses Return there only with **Send in terminals that can't confirm**; automatic sends never do.
- Email apps never send with Return. Return is posted with no modifier flags after waiting briefly for held keys, and only while focus is still in the original field.

History stores the flags (`flags`, JSON), the request (`sendRequest`: `shift` or `auto`) and whether Return was pressed (`submitted`).

## Profile and Edit shortcuts (AD-104)

Settings → Keyboard shortcuts holds up to two profile shortcuts and an **Edit selection** shortcut, all unset by default. They follow the dictation shortcut's Hold or Toggle behavior and Trigger Delay. A profile shortcut dictates with its profile in any app, ignoring app rules. The Edit shortcut reads the current selection once, when pressed; with nothing selected the microphone never opens. The spoken instruction rewrites the selection through the refinement provider (a profile without refinement edits with Clean's instructions) and the result replaces the selection at the cursor. Edits never send, use profile destinations or flag words. Read app context stays independent: the Edit shortcut is the explicit consent to read that one selection.

## Sending to an agent in tmux

A script destination can paste into a terminal pane without switching windows. Save, `chmod +x` and choose this script; set `PANE` to the target (`session:window.pane`) and the absolute tmux path:

```sh
#!/bin/sh
# Paste Airdraft's final text into a tmux pane.
set -eu
TMUX_BIN=/opt/homebrew/bin/tmux   # absolute path: scripts inherit the app's environment
PANE="agent:1.0"
SEND_ENTER=1                      # 0 only pastes

text=$(/bin/cat)
# Join lines: a pane without bracketed paste would run each line on its own.
text=$(printf '%s' "$text" | /usr/bin/tr '\n' ' ')
printf '%s' "$text" | "$TMUX_BIN" load-buffer -b airdraft -
"$TMUX_BIN" paste-buffer -d -p -b airdraft -t "$PANE"
if [ "$SEND_ENTER" = 1 ]; then
  "$TMUX_BIN" send-keys -t "$PANE" Enter
fi
```

`paste-buffer` turns LF into CR, and `-p` adds bracketed-paste markers only when the pane asked for them; without them every line break acts as Enter, and `-r` does not help because shells treat LF as Enter too. The named buffer is deleted after pasting (`-d`), so your own tmux buffers are untouched. Exit status 0 means tmux accepted the text, not that the agent read it. Add `-S <socket>` when your tmux server uses another socket.

## Measurements (AD-104)

Settings → Send after pasting → Measurements shows local counts: flagged dictations, sends, read-back confirmations for AI apps and shortcut presses ignored while a dictation was processing. They come from History and `speed-metrics.json` in the data folder (counts per destination bundle ID and capture timing by input type, never text) and are never sent. `python3 scripts/speed-metrics.py` prints the full report from a temporary read-only copy; `eval/speed/` exports retained recordings for labeling and scores flag precision, residual errors and whether errors change an AI's answer (see its README).

## Validation and references

Validated September 26, 2026: the complete suite ran 266 tests with zero failures and three existing skips. The built app contains all three discoverable AudioRecording intents and App Shortcuts with background execution. Light and dark settings renders were inspected. Shortcuts invocation, cold launch and insertion into a real focused editor remain manual checks.

Tests use temporary executable fixtures only. They cover literal Unicode, newlines and shell metacharacters; path validation; nonzero status and bounded errors; output beyond both capture limits; blocked stdin; early reader exit; cancellation; timeout after parent exit; and no automatic retries. No user-selected script is run by the test suite.

The process contract follows Apple's [Process documentation](https://developer.apple.com/documentation/foundation/process), including [Pipe handling for standard output](https://developer.apple.com/documentation/foundation/process/standardoutput), and the Darwin [poll](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/poll.2.html) and [write](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/write.2.html) contracts. `O_NONBLOCK` and `F_SETNOSIGPIPE` were checked in the installed macOS SDK's `sys/fcntl.h` on September 26, 2026.
