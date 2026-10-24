# Interface localization glossary

Airdraft ships English (source), Spanish (es), Japanese (ja), Simplified Chinese
(zh-Hans) and Traditional Chinese (Taiwan, zh-Hant). The workflow and rules are in
the Localization section of `CLAUDE.md`; this file fixes the terms so new strings
stay consistent. The es and ja catalogs were machine-drafted from the English and
zh-Hant text, then checked in renders; they still need review by native speakers.

## Style

| | Spanish | Japanese |
|---|---|---|
| Address | tú | です／ます |
| Capitalization | Sentence case for buttons, menus and titles | — |
| Quotes | “…” | 「…」 |
| Ellipsis | … | … |
| Numbers | Decimal comma in prose (0,0045 USD) | Half-width digits, a space before units (3 GB, 10 分) |

Keycap and key names (Control, Option, Return, Esc, fn) are never translated.
Model, provider and product names stay as published.

## Terms

| English | Spanish | Japanese |
|---|---|---|
| Dictation, dictate | dictado, dictar | 音声入力、音声入力する |
| Transcript, transcribe | transcripción, transcribir | 文字起こし、文字起こしする |
| Refinement, refine | refinamiento, refinar | 整形、整形する |
| Tidy your words | pulir tus palabras | テキストを整える |
| Profile | perfil | モード |
| Vocabulary | vocabulario | 語彙 |
| Speech model | modelo de voz | 音声モデル |
| Speech recognition, speech | reconocimiento de voz, voz | 音声認識 |
| Home | Inicio | ホーム |
| History | Historial | 履歴 |
| Meetings | Reuniones | 会議 |
| Models | Modelos | モデル |
| Settings | Ajustes | 設定 |
| System Settings | Ajustes del Sistema | システム設定 |
| Accessibility | Accesibilidad | アクセシビリティ |
| Microphone | micrófono | マイク |
| Keychain | Llavero | キーチェーン |
| Clipboard | portapapeles | クリップボード |
| Shortcut | atajo | ショートカット |
| Recording | grabación | 録音 |
| Insert at cursor | insertar en el cursor | カーソル位置に挿入 |
| Paste | pegar | ペースト |
| API key | clave de API | API キー |
| Provider | proveedor | プロバイダ |
| Endpoint | punto de acceso | エンドポイント |
| Trial, license | prueba, licencia | 試用、ライセンス |
| Live preview | vista previa en directo | ライブプレビュー |
| Recording window | ventana de grabación | 録音ウインドウ |
| Load, unload (a model) | cargar, descargar de memoria | 読み込む、アンロード |
| Default | Por defecto (menu), Normal (text size) | デフォルト, 標準 (text size) |

## Composed sentences

Some views place a verb, key caps and the rest of a sentence side by side. The
verbs Hold and Press translate as Mantén pulsado / Pulsa in Spanish and as the
nouns 長押し / 押下 in Japanese, so templates such as `%2$@ を%1$@して…` stay
grammatical. Where the key caps sit between the verb and the rest, Japanese uses a
label form (`長押し ⌃⌥：話し終えたら離すと挿入されます。`).

## Known gaps

- No catalog uses plural variations yet; strings with counts keep English-style
  parity (separate keys for 1 where the English has them).
- Built-in profile instructions and prompts stay English by design.
