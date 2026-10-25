# Interface localization

Airdraft ships the interface languages listed in `Config/languages.json`: English
(source), Spanish (es), Japanese (ja), Simplified Chinese (zh-Hans) and
Traditional Chinese (Taiwan, zh-Hant). The workflow and rules are in
the Localization section of `CLAUDE.md`. This file summarizes each language's
conventions; the term lists are `Config/glossaries/<code>.json` (zh-Hans and
zh-Hant keep their terms in the catalogs and the rules in `CLAUDE.md`).

The es and ja catalogs were machine-drafted, checked against
Default and Larger renders of every page, and reviewed once more for wording. None
has had a native speaker's review yet.

## Workflow

1. Build Debug, then `python3 scripts/localization.py sync`.
2. `python3 scripts/localization.py export <code> <file>` for each language: the
   untranslated keys with English, comments and es/ja/zh-Hant references.
3. Translate with that language's glossary, keeping placeholders and
   `${applicationName}`; counts may use plural `variations`.
4. `python3 scripts/localization.py import <code> <file> --dry-run`, then without
   `--dry-run`, then `check`.
5. Render every shipped language at Default and Larger text size and fix truncation
   with shorter strings or layout changes.

## Conventions

| Language | Address | Buttons and titles | Quotes | Notes |
|---|---|---|---|---|
| Spanish | tú | sentence case | “…” | Ajustes, Llavero, portapapeles; endpoint stays English |
| Japanese | です／ます | — | 「…」 | モード for profile, matching 模式; half-width space between Japanese and Latin text |

Keycap and key names (Control, Option, Return, Esc, fn), model, provider and
product names are never translated.

## Known gaps

- Native-speaker review of every machine-drafted catalog.
- Built-in profile instructions and prompts stay English by design.
