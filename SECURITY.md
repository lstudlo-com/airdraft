# Security policy

Airdraft holds sensitive permissions: it records from the microphone, can
capture app audio for meetings, and uses Accessibility access to read the
focused field and insert text into other apps. It also stores API keys and
license receipts in the Keychain. Please report security problems privately.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting:
[Report a vulnerability](https://github.com/lstudlo-com/airdraft/security/advisories/new)
(repository **Security** tab > **Report a vulnerability**).

Do not open a public issue, pull request or discussion for a suspected
vulnerability. Include:

- the Airdraft version and edition (official build or built from source, with
  the commit), and your macOS version
- what an attacker can do, and the steps or a proof of concept to reproduce it
- any logs, with API keys, transcripts and personal data removed

We aim to acknowledge reports within seven days, keep you informed
while we investigate, agree on a disclosure date with you, and credit you in the
advisory unless you prefer otherwise.

## Scope

In scope:

- Text inserted into the wrong app or field, or dictation that continues after
  it was cancelled or stopped
- Microphone or app-audio capture that starts without the user's action, or
  continues after recording ends
- Misuse of Accessibility access, such as reading context when Read app context
  is off, or reading password fields
- Exposure of API keys, license keys, transcripts, recordings or history to
  logs, files, other processes or unintended network destinations
- Provider requests that leak credentials across redirects or hosts
- Update integrity: Sparkle feed or archive verification, code-signing and
  Hardened Runtime checks in the release process
- Code execution through scripts, CLI refiners, downloaded models or imported
  media

Out of scope:

- Vulnerabilities in third-party services or language models themselves,
  including content a model returns
- Attacks that require an already compromised account or administrator access
  to the Mac
- Builds you modified, or settings you changed to weaken protections
- The marketing website's private preview access policy

## Supported versions

Security fixes go into the latest release and `main`. Official builds update
through Sparkle; if you build from source, update to the latest commit.
