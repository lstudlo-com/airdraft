---
name: push-and-release
description: Complete Airdraft's local test, repair, commit, push and release workflow, including E2E checks and verification of published artifacts. Use when the user requests an Airdraft release or invokes $push-and-release to execute it. Questions about the workflow and requests to create or edit this skill do not execute a release.
---

# Push and release

完成 Airdraft 的測試、必要修正、提交、推送與發佈，並驗證使用者實際下載的版本。沿用 repository 的發佈腳本；skill 負責安排驗證、處理失敗與確認完成。

## 適用範圍

- 這是 Airdraft 專案內的 skill。從 Git root 執行指令，確認 `origin` 指向 `lstudlo-com/airdraft`，標準發佈目標為 `origin/main`。其他分支的推送不會產生 release；目標不明時先釐清。
- 使用者要求執行 `$push-and-release` 或完成 commit、push、release，已授權這些步驟及其必要修正，不逐步重問。保留使用者指定的測試範圍與排除項目。單純詢問流程、建立／修改 skill，或只要求 commit，不構成發佈授權。
- 使用者說「push and release」就必須呼叫本 skill 並完成推送與公開發佈。除非使用者明確指定停止條件，不增設確認、驗收或環境前提作為 blocker。缺少權限、硬體、服務或其他未驗證項目，記錄原因並繼續；發佈完成後再簡短告知。可修正的失敗持續修正，不把失敗或缺少證據寫成通過。
- 不加入無關工作區變更，不強制推送、不繞過 hook，也不改動簽章身分或使用者的實際資料。沿用已核准的個人使用簽章流程；Developer ID、公證或憑證遷移另需明確範圍。
- 先讀 [AGENTS.md](../../../AGENTS.md)、[發佈契約](../../../docs/updates.md) 與 [本機 E2E](../../../docs/local-e2e.md)。修正 UI、設定或 prompt 前讀 `docs/PRODUCT.md`。以下步驟不取代這些契約。

## 1. 確認本次版本

1. 檢查 Git 狀態、分支、remote、尚未推送的提交與 diff。刷新遠端狀態，確認本次要發佈的內容，保留無關檔案與 hunks。
2. 比對已發布版本，依 `docs/updates.md` 選擇 display version。必要時修改 `project.yml`、執行 XcodeGen，並納入產生的 `Sources/App/Info.plist`。build number 由 Git commit count 決定。
3. 確認 Xcode、原生 Vendor、`gh`、`uv`、固定簽章身分及 pre-push hook 可用。hook 已安裝就沿用；缺少時依 `docs/updates.md` 執行 release setup，不覆寫其他用途的 hook。
4. 建立本次專用證據目錄，保留指令、log、xcresult、runtime JSON 與圖片。不要引用其他執行或其他 commit 的成功結果來代替本次驗證。
5. 列出上次發佈以來的 commits 與其 `Refs: AD-###`，確認本次包含的 Obsidian Work 項目。

## 2. 測試與修正

依 [驗證細節](references/verification.md) 執行本機 E2E、受影響的原生／UI 檢查，以及適用的 prompt 評測。核心測試、建置與實際 App 操作分別記錄。

遇到失敗時持續處理：

1. 保留失敗證據，查明是產品問題、測試問題還是環境前提缺失。
2. 修正可在授權範圍內處理的根因。先重跑失敗案例，再跑修正影響到的檢查。執行本次可完成的發佈檢查，保留尚未驗證項目的原因。
3. 不刪除有效失敗案例、不降低標準、不跳過簽章檢查，不靠重複抽樣挑出一次成功。只有證據支持測試本身錯誤時才修正測試，並說明原因。
4. 可處理的失敗持續修正。缺少外部驗收前提時，使用有紀錄的未驗證狀態完成 release，不交回使用者等待確認。實際建置或上傳失敗仍須修復並重試，不能宣稱已發佈。

測試失敗、環境缺失與選配測試略過要分開記錄。不能把略過當成通過，或在驗收缺失時宣稱全部驗證通過。長工作期間提供簡短進度，說明已通過、正在處理與下一步。

## 3. 提交並驗證已提交版本

1. 可執行的檢查與修正完成、未驗證項目記錄後，更新受影響的文件。依 vault 的 `Knowledge Architecture.md` 改寫受影響的 Product 主題，不追加日期段落；在本次包含的 Work 項目紀錄表追加一列。確認所有專案擁有的 `AGENTS.md`／`CLAUDE.md` 配對一致。
2. 檢查實際 staged diff，僅 stage 本次相關變更，建立 conventional commit。若工作已提交且內容正確，直接使用該提交，不製造空 commit。
3. 記下完整的 `COMMIT` SHA。先明確執行準備流程，讓已提交版本的 E2E 有機會在公開發佈前完成：

   ```sh
   COMMIT=$(git rev-parse HEAD)
   python3 scripts/release.py prepare "$COMMIT"
   ```

   沒有既有成品時，此步驟匯出該 commit、跑 prompt 證據檢查與完整核心測試、建置 Release、驗證 Keychain／簽章／Sparkle、製作 DMG，並上傳驗證過的 draft。它尚未公開 release。

4. 從 `dist/release-source` 的 Xcode build settings 找到該提交建出的 Debug App，依驗證細節執行實際本機流程。`prepare` 重用既有 draft 時可能直接返回，必須核對來源與產品；缺少對應 Debug snapshot 時，另從該 SHA 匯出並建置，不沿用殘留產品。若本次尚未對該 SHA 跑完整核心 suite，從核對過的 snapshot 執行完整 Debug `xcodebuild test`，使用發佈腳本的共同引數與固定簽章設定。UI 變更要檢查這份已提交來源的 renders。驗證 Release 的版本、arm64、Hardened Runtime 與 Debug 入口未包含在內。
5. 若此時發現問題，修正後重新提交、準備並驗證新 SHA。舊 draft 與舊證據不能代表新版本。推送前確認 `HEAD`、`refs/heads/main` 與通過驗證的 SHA 三者相同；不相同時先處理分支目標，不能直接推送未驗證的 main。

## 4. 推送及發佈

```sh
git push origin main
```

- 正常通過 hook。它會重新驗證並重用上一節的 draft；不要使用 `--no-verify` 或停用 hook。未完成的 live insertion 驗收使用 `--unverified-live-insertion REASON`，讓 hook 和 manifest 保留真實狀態。
- 推送失敗先核對遠端狀態。建置或驗證失敗回到修正流程；網路問題先確認提交是否已到遠端，再決定重試，避免重複建立版本。
- 推送成功後，以完整 SHA 查詢 `Publish local macOS release` workflow，等待成功。`git push` 成功只代表程式碼已推送。

  ```sh
  gh run list --repo lstudlo-com/airdraft --commit "$COMMIT" \
    --json databaseId,name,status,conclusion,headSha,url
  ```

- 發佈失敗時先讀對應 run 的錯誤。若遠端 main 仍是同一 SHA，依 `docs/updates.md` 恢復準備並重跑對應 workflow。必要時可執行 `python3 scripts/release.py publish "$COMMIT"` 恢復發佈，但仍須重跑該 SHA 的 workflow 並確認成功；手動補發不會改變原 run 的失敗狀態。若 main 已前進，重新確認目前發佈目標，不把舊提交強行設為 latest。
- 若重新執行時同一 SHA 的 release 已完成，核對既有成品並完成使用者要求的重測；不製造空提交或覆寫已發布的成品。

## 5. 發佈後驗證與回報

完成推送與公開發佈後回報結果，並據實記錄下列檢查：

- 遠端 main、release tag、`release.json` 與本次完整 SHA 一致；workflow 成功，release 為非 draft 且是預期的 latest。
- 下載公開 release 的 DMG、`appcast.xml`、`release.json`，用 `scripts/release.py` 的 `download_and_verify()` 核對 SHA-256、feed 資訊及 DMG 內 App 簽章。詳見驗證細節的呼叫方式。
- 從 App 實際設定的 `SUFeedURL` 取得線上 feed，確認它描述這次版本，且內容雜湊與已驗證的 feed 相同。
- 已提交版本的 E2E 分別記錄通過、失敗與未驗證，選配略過及未涵蓋的硬體／外部服務驗收在發佈後告知使用者。

驗證後更新 Obsidian vault，規範見 vault 的 `Knowledge Architecture.md`：

1. 新增 `Records/Releases/YYYY-MM-DD Release X.Y.Z Build N.md`。frontmatter 為 `type: release`、`status: published`、`date`、`version`、`build`、`source_commit`（完整 SHA）、`verification`（`verified`、`partial` 或 `none`）與 `items`（本次包含的 AD 編號）。正文寫 release 連結、包含項目、變更摘要、驗證結果（通過、失敗與未驗證分開，未驗證寫原因）及證據位置；調查過程留在 Work 筆記。
2. 本次包含的 Work 項目改為 `status: released`，填 `released_in`，依實際驗收更新 `verification` 與 `gaps`，並在紀錄表追加一列。發佈時仍有驗收缺口、但沒有對應項目的，新建 task。
3. Product 主題不寫發佈狀態或「最新版本」。
4. 執行 `python3 scripts/check-vault.py`，錯誤必須是 0。

最後簡短列出 release 連結、版本／build、commit、主要測試結果與必要的未涵蓋範圍。單有 build 成功、draft 上傳或 push 成功，都還沒完成上述流程。
