# Microphone recording

The selected input is stored by device UID. A missing selected device must fail
visibly; never substitute a different microphone during a recording.

## Input channels

Multi-input devices show an Input channel picker in Configuration. The selection
is saved with the microphone; existing preferences start with Input 1. Choose
Input 2 if that is where the microphone is connected. Selecting another device
resets the channel to Input 1. An unavailable channel reports an error.

The recorder explicitly maps the selected hardware channel to 16 kHz mono with
[`AVAudioConverter.channelMap`](https://developer.apple.com/documentation/avfaudio/avaudioconverter/channelmap).
Discrete inputs have no speaker layout, so automatic mapping can select `-1`,
which means silence. This reproduced on the Scarlett 2i2 4th Gen's four-channel
format even though permission was granted and audio buffers were arriving.
Do not mix all device channels: on this interface, inputs 3 and 4 are
[computer-audio loopback](https://support.focusrite.com/hc/en-gb/articles/13414231413906-Can-I-Simultaneously-Record-All-4-Inputs-of-My-Scarlett-2i2-4th-Generation).

## Configuration changes

Apple's [AVAudioEngine configuration notification](https://developer.apple.com/documentation/foundation/nsnotification/name-swift.struct/avaudioengineconfigurationchange)
can describe a change to input or output hardware. The notification alone does
not establish that the microphone disconnected. Apple also warns against tearing
down the engine inside its notification callback.

`AudioRecorder` leaves that callback queue and coalesces notifications on the
main queue. It checks the selected device's UID, actual Core Audio route and
current format. A healthy input keeps recording. A stopped engine or changed
format rebuilds the tap and converter for the same input, preserving accumulated
samples. A missing or changed input, invalid format or failed restart reports the
specific error. Private aggregate routes count as the selected input when they
contain that physical device.

## Verification

Run the Xcode-built app with `AIRDRAFT_SELFTEST=microphones`. Set
`AIRDRAFT_MICROPHONE_TEST_CYCLES=10` for repeated checks. The self-test uses the
system default and each available input, validates the actual hardware route,
posts a configuration notification while recording, then stops only its own
engine and posts another notification. It checks that audio callbacks resume, no
interruption is reported and enough audio remains to include the earlier capture.
It does not change macOS input/output settings.

To isolate a device, set `AIRDRAFT_MICROPHONE_TEST_DEVICE` to its name or UID.
`AIRDRAFT_MICROPHONE_TEST_CHANNEL` selects a one-based input number.
`AIRDRAFT_MICROPHONE_TEST_REQUIRE_SIGNAL=1` also fails a recording containing
only zeros. Logs include the channel, frame count and signal peak, never audio.
`AudioRecorderTests` feeds known signals through the production converter at
44.1/48 kHz, checks that every selected discrete input reaches mono, and verifies
that unselected inputs, including loopback, remain excluded. Hardware signal
checks still need a person to speak into the selected microphone.

Read `microphone-test` and `recorder` messages under the `com.lightiichen.airdraft`
log subsystem. A sample count alone cannot prove success: the earlier self-test
never installed an interruption handler, so it missed the app's false failures.

On the M4 development Mac, the regression scenarios failed before the fix and
passed in 20 consecutive recordings after it. This does not verify the affected
M5, physical unplugging, or every device's hardware format changes.

On 2026-09-23, the local channel-mapping fix passed 148 core tests with 3 skipped
and no failures. The rebuilt app passed nine real-device checks across Scarlett
Input 2, system-default Input 2 and the built-in microphone. Each checked a
nonzero signal and audio callbacks after engine recovery. Light/dark Configuration
renders were inspected. These checks do not replace speaking while holding the
physical dictation shortcut, and this workspace build is not a published update.
