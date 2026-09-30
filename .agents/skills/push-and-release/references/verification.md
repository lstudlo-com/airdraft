# 驗證細節

所有路徑以 repository root 為準。具體引數與限制以目前的 `AGENTS.md`、`docs/local-e2e.md` 和腳本為準，先檢查再執行；不要依賴某次任務的 `/tmp` helper 或固定 DerivedData 路徑。

## 本機測試

以 `mktemp -d` 或同等方式建立新的 `EVIDENCE` 目錄，再依序執行：

```sh
python3 scripts/test-local-e2e.py --output "$EVIDENCE/core"
python3 scripts/verify-native-behaviors.py
python3 scripts/verify-model-lifecycle.py
python3 -B scripts/test-release.py
python3 -B scripts/test-insertion-regressions.py
python3 -B scripts/test-prompt-gate.py
python3 -B scripts/verify-prompt.py
```

使用者排除 API-key／credential 測試時，`prepare` 加上
`--test-scope credential-free`，push 保留
`AIRDRAFT_RELEASE_TEST_SCOPE=credential-free`。已提交的 local allowlist 取代完整
core suite，跨身分 Keychain fixture 也排除；scope 與 exclusions 記在
`release.json` 和 release notes。其餘簽章、updater、封裝及下載驗證不變。
不得將此範圍描述為完整 credential 驗收。未指定時仍跑完整 suite。

`test-local-e2e.py` 是無 API 憑證的核心測試選集。release prepare 在建立新成品時另跑完整核心 suite；重用成品會略過，依 skill 第 3 節補齊本次測試。兩者都不能代替 App 的實際流程。原生 fixture 的 HUD 會短暫出現，與其他 UI 操作錯開執行。

本機 runner 與 release prepare 都會檢查實際 xcresult 的 34 個 mandatory
insertion regressions，涵蓋 production capture／insert entry points 與關閉
context 的 pipeline → History。任何 missing、skip 或 fail 都會阻止通過，
不可只引用 xcodebuild exit 0。此 gate 適用於完整與 credential-free 範圍；
證據為各次 core run 旁的 `insertion-regressions.json`。

Moon 可用時採用既有 tasks。若 Moon 或 XcodeGen 不在 PATH，依 repo 現有工具與發佈腳本處理；可用 `dist/tools/xcodegen/bin/xcodegen generate` 與直接 `xcodebuild`。Xcode 指令保留 `-skipPackagePluginValidation -skipMacroValidation -packageAuthorizationProvider netrc`，序列化執行，不指定 `-derivedDataPath`。

從正確專案路徑執行 `xcodebuild -showBuildSettings -json`，以 `TARGET_BUILD_DIR`、`FULL_PRODUCT_NAME` 與 Info.plist 找到產品及 executable。已提交來源使用 `dist/release-source/airdraft.xcodeproj`。檢查實際產品版本，不能把工作區先前的 Debug App 當成 release snapshot 的產品。

## 實際 App 流程

使用 `docs/local-e2e.md` 的 `--e2e-local` 入口與最小環境，確保 API key 環境變數不會傳入。每個獨立案例使用新資料目錄，設定外部 process timeout，檢查 exit code 與 `result.json`。

一般本機 E2E 至少涵蓋：

- `inventory` 確認可用引擎與必要資源。
- 以已知文字的本機 WAV 執行真實 `transcribe`。檢查辨識內容、history、保存的 WAV 與未插入外部欄位。可用 macOS `say`／`afconvert` 產生非私人語音 fixture。
- 目前各本機 ASR 選項的 silence rejection。這些案例在模型載入前即可退出，不能算作每個模型的辨識成功。
- macOS 26+ 且 Apple Speech 可用時，在已準備的引擎上，以長音檔測試 20、50、150 ms 取消。確認無輸出／history，且 engine lease 在期限內釋放。
- 同樣在支援環境檢查 Apple Speech `preview` 有產生文字、無錯誤，取消後不再收到舊 session callback。其他 macOS 版本以已安裝的本機引擎測轉錄及取消，preview 如實記為不適用。
- 本次修改所涉及的其他流程，依文件加入 targeted checks；例如 HUD 交付後淡出、恢復、保留錄音、腳本交付或實際模型長音檔。

模型、語音資源或 CLI 未安裝／未登入時，記錄未涵蓋原因；不自行讀取 API keys 或登入。需要實際麥克風、Accessibility 或另一台 Mac 才能驗證的行為，不能用模擬事件或 fixture 結果冒充。必要測試缺少前提時按 skill 的失敗流程處理。

有 UI 變更時，依 `AGENTS.md` 檢查已提交版本的 6 頁、明暗模式、784 pt 寬、600 pt 最小高度與能看見下方區段的較高畫面，以及展開／收合側欄。錄音 HUD 變更另外驗證 HUD。需看圖片與適用的 live fixture，圖片存在不代表檢查通過。

## Prompt 評測

`verify-prompt.py` 核對既有報告與程式碼，並不重新呼叫模型。若 prompt 組裝、綁定來源、資料集改變、證據缺失，或使用者明確要求重新評測，就重新建置 `airdraft-cli`，在 LM Studio 上對三份資料集各跑至少三次：

```sh
python3 -u eval/run_correction_eval.py "$LABEL" \
  --model "$MODEL_INSTANCE" --runs 3 --cases "$CASES" --cli "$CLI"
```

`CASES` 依序為 `correction_cases.json`、`holdout_cases.json`、`context_correction_cases.json`，每份使用不同的新 `LABEL`。以精簡環境執行，不傳入 API-key 環境變數。只卸載本次載入的模型 instance。

評測腳本目前即使有失敗案例也可能回傳 exit code 0，必須檢查報告的逐案結果。修 prompt 要升 `PromptBuilder.version`，保留失敗報告；不可只改 manifest hash 或挑選成功抽樣。依 `verify_prompt.py` 更新 `eval/results/prompt-validation.json` 的候選檔名、雜湊與版本，保留有效 baseline，重新執行 gate。

既有 gate 的最低門檻是 correction／holdout 逐案不退步，以及所有 context-correction runs 通過。本 skill 預設要求採用的候選報告每個案例、每次 run 全部通過；符合 baseline 但仍有失敗時，繼續修正與評測，不能當成全過。使用者明確指定其他驗收範圍時才依其要求調整，仍不得繞過 gate。使用過的 holdout 要如實標為回歸證據。

## 公開成品

先取得實際 `TAG` 與完整 `COMMIT`。可從 repository root 用以下命令呼叫既有驗證函式，避免重寫簽章邏輯：

```sh
python3 - "$TAG" "$COMMIT" <<'PY'
from pathlib import Path
import sys
import tempfile

sys.path.insert(0, str(Path("scripts").resolve()))
import release

tag, commit = sys.argv[1:3]
with tempfile.TemporaryDirectory(prefix="airdraft-published-") as directory:
    manifest = release.download_and_verify(tag, commit, Path(directory))
PY
```

在簽章 Mac 執行時，此函式會檢查下載的 DMG 內 App；GitHub 的 Linux workflow 只驗證 metadata、hash 與 feed。

另外以無登入要求的 HTTP 請求讀取實際 App 的 `SUFeedURL`，確認雜湊符合 manifest 的 `appcast.xml`。檢查實際 Release App 與 core framework 的 arm64 架構、版本、固定身分與 Hardened Runtime，並確認 executable 未包含 `--e2e-local`、`--render-window`、`AIRDRAFT_SELFTEST` 等 Debug 入口。公開 release 的存在不等於已完成 Developer ID 公證；依現行簽章契約回報。
