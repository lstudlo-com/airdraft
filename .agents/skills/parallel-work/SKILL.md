---
name: parallel-work
description: Coordinate Airdraft work across parallel sessions, worktrees and subagents so changes never collide and finished work is never left unmerged. Use before starting any implementation, fix, refactor, documentation or website change; before merging another branch; before spawning subagents or sessions that edit files; and before any push, release or website deploy. Questions about the procedure alone do not require running it.
---

# Parallel work

Airdraft 常同時有多個 session、worktree 與 subagent 在改同一個 repository。本 skill 讓每次工作在開工前看見別人正在改什麼、在結束時真的合併，並在發佈或部署前確認沒有遺漏已完成的工作。所有實作與修正都要照這份流程做；`CLAUDE.md` 的 Checkouts and branches 是規則，本文件是步驟。

## 為什麼

2026-10-25 的三個問題都來自同一個原因：各 session 只看自己的 branch，看不到別人已經做完、正在做或已經決定的事。

- 網站優化（AD-099）在 `claude/website-refresh` 做完就停在 branch，沒有合併。另一個 session 隨後把網站文案搬到各語言檔案（AD-098），兩邊改了同一批檔案，合併時 16 個檔案衝突；部署只送出 main，使用者以為做好的優化沒有上線。
- 一個 session 依使用者決定把介面限縮為五種語言，另一個 session 不知道這個決定，做完十一種語言後才發現衝突，又移除六種。
- 開工時已經看到另一個 worktree 在改網站 header，卻只是叮囑 agent「少改一點」，仍然平行做了結構性改寫。

## 1. 開工前

1. 在要工作的 checkout 執行 `python3 scripts/check-checkout.py`。
2. 列出預計修改的路徑（目錄或檔案），執行：

   ```sh
   python3 scripts/parallel_work.py status --fetch --paths <預計修改的路徑…>
   ```

   它列出每個 worktree 的未提交檔案、每個領先 main 的 branch 與其改動範圍、所有 claim，並在有重疊時以 exit 2 結束。
3. 讀 vault：同一區域 `status: doing`／`open` 的 Work 項目，以及最近 14 天的 `Records/Decisions/`。使用者這次的要求若與已記錄的決定或進行中的工作衝突，開工前用一句話問清楚要以哪個為準；不要先做完再發現。
4. 依 status 的結果處理重疊：

   | 情況 | 做法 |
   |---|---|
   | 別的 branch 已完成但未合併，且碰到你的路徑 | 先把它整合進 main（或把你的 branch 建在它上面）並驗證，再開始你的工作。它屬於其他 session 時，先問使用者一句「先合併 `<branch>` 再開始？」 |
   | 別的 worktree 有未提交的改動碰到你的路徑 | 不改同一檔案的同一區段。能切開就切開（不同檔案，或同一檔案的不同章節）；切不開就等它完成，或用 SendMessage 協調／告知使用者。不要平行做結構性改寫 |
   | 有 claim 碰到你的路徑 | 視同進行中的工作處理；claim 標示 STALE（worktree 已不存在）時，確認該 branch 已合併或廢棄後 `release` 它 |
   | 沒有重疊 | 直接開始 |

5. 結構性改動（搬移或拆分檔案、改目錄或資料結構、把文案搬到新位置）先做成一個小提交，盡快合併到 main，再做內容改動，讓其他人只需要 rebase 一次。
6. 從最新 `origin/main`（或剛整合好的基礎）建立 worktree，然後登記：

   ```sh
   python3 scripts/parallel_work.py claim AD-### --paths <路徑…> --branch <branch> --note "<一句話>"
   ```

   Work 項目的紀錄表也寫上 branch 與路徑。

## 2. 進行中

- 每次 rebase、合併別的 branch，或工作範圍擴大時，用新的路徑清單重跑 `status --paths`，必要時更新 claim。
- 派 subagent 或開新 session 時，每個 brief 都寫明它可以改的路徑與不能碰的路徑，彼此不重疊；coordinator 在每個 agent 完成時就合併它的 branch，不等到最後。
- 同一區域同一時間只有一個寫入者。需要同區的第二件工作時，排在第一件合併之後，或建在它的 branch 上。

## 3. 完成就是合併

- 驗證通過後，在同一個任務內 rebase 到 `origin/main`、fast-forward 主資料夾的 main、移除 worktree 與 branch，並執行 `parallel_work.py release AD-###`。
- 「做完但沒合併」不算完成。合併需要使用者決定時，Work 項目 `gaps` 第一行寫「未合併：`<branch>`」，最終回報第一段也寫出來，並在同一回合請使用者決定；不要留著不提。
- 長期保留、刻意不合併的 branch（`wip/…`）用 `claim <ID> --branch <branch> --parked --note "<原因>"` 標示，發佈檢查才會略過它。

## 4. 發佈或部署前

1. 執行 `python3 scripts/parallel_work.py status --fetch --release`。
2. 每個 BLOCKER（領先 main、沒有 parked 的 branch）都要先處理：屬於這次發佈或網站內容的，先合併並驗證；不屬於的，在發佈回報中列出 branch 與 Work 項目；長期保留的標成 parked。
3. 部署網站前，特別確認沒有碰 `apps/marketing` 的未合併 branch；有的話先合併，否則部署出去的網站會少掉那些改動。

## 5. 回報

每次最終回報都附上 `status` 摘要：這次工作以外，仍有哪些 branch 未合併、各自的 Work 項目與下一步。看到別人的未合併工作也要說，不要只回報自己的部分。
