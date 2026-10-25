# Interface localization

Airdraft ships the interface languages listed in `Config/languages.json`: English
(source), Arabic (ar), Spanish (es), French (fr), Hindi (hi), Indonesian (id),
Japanese (ja), Portuguese (Brazil, pt-BR), Russian (ru), Simplified Chinese
(zh-Hans) and Traditional Chinese (Taiwan, zh-Hant). The workflow and rules are in
the Localization section of `CLAUDE.md`. This file summarizes each language's
conventions; the term lists are `Config/glossaries/<code>.json` (zh-Hans and
zh-Hant keep their terms in the catalogs and the rules in `CLAUDE.md`).

Every catalog except zh-Hans and zh-Hant was machine-drafted, checked against
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
| Arabic | gender-neutral | — | «…» | Right to left; Latin names placed so the bidi result reads naturally; no invisible bidi controls; six plural forms |
| Spanish | tú | sentence case | “…” | Ajustes, Llavero, portapapeles; endpoint stays English |
| French | vous | sentence case | « … » with non-breaking spaces | Réglages; non-breaking space before `: ; ? !`; “sauvegarder” for saving, “enregistrer” stays the Save button |
| Hindi | आप | — | “…” | Apple Hindi loanwords in Devanagari; “API की”, “लाइसेंस की”; “।” ends sentences |
| Indonesian | Anda | Apple title case for buttons and menu items | “…” | Prepositions and conjunctions stay lowercase in title case |
| Japanese | です／ます | — | 「…」 | モード for profile, matching 模式; half-width space between Japanese and Latin text |
| Portuguese (Brazil) | você | sentence case | “…” | Ajustes; Keychain is “Chaves do macOS”, never “chave” for a switch |
| Russian | вы | sentence case, infinitive buttons | «…» | one/few/many/other plurals; short labels in the glossary for fixed controls |

Keycap and key names (Control, Option, Return, Esc, fn), model, provider and
product names are never translated.

## Known gaps

- Native-speaker review of every machine-drafted catalog.
- Built-in profile instructions and prompts stay English by design.
