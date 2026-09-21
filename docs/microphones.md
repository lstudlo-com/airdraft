# Microphone recording

The selected input is stored by device UID. A missing selected device must fail
visibly; never substitute a different microphone during a recording.

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
engine and posts another notification. It checks that recording resumes, no
interruption is reported and enough audio remains to include the earlier capture.
It does not change macOS input/output settings.

Read `microphone-test` and `recorder` messages under the `com.lightiichen.airdraft`
log subsystem. A sample count alone cannot prove success: the earlier self-test
never installed an interruption handler, so it missed the app's false failures.

On the M4 development Mac, the regression scenarios failed before the fix and
passed in 20 consecutive recordings after it. This does not verify the affected
M5, physical unplugging, or every device's hardware format changes.
