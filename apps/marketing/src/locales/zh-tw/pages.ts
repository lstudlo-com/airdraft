import type { PageCopy } from "../types";

export const zhTw: PageCopy = {
  chrome: {
    breadcrumb: "導覽路徑",
    home: "首頁",
    guides: "指南",
    related: "相關指南",
  },
  notFound: {
    title: "找不到頁面｜Airdraft",
    heading: "這個頁面不存在",
    action: "回到首頁",
  },
  hub: {
    title: "Mac 聽寫設定與模型指南｜Airdraft",
    description:
      "Airdraft 實用指南：離線聽寫、中英混著講、Claude Code 與終端機、本機或雲端模型、會議逐字稿、App 比較，以及免費版與官方版怎麼選。",
    heading: "聽寫指南",
    help: ["設定好了卻出問題？", "檢查權限、快速鍵與常見問題。"],
    pricing: "比較價格",
    changes: "查看更新紀錄",
  },
  support: {
    title: "Airdraft 支援：權限、快速鍵與模型",
    description: "解決 Airdraft 權限、快速鍵與模型的常見問題，或回報錯誤。",
    heading: "支援",
  },
  privacy: {
    title: "Airdraft 隱私：哪些資料留在 Mac",
    description:
      "Airdraft 如何處理聽寫資料、選用的 App 使用資料與網站分析，以及如何更改這兩項選擇。",
    heading: "隱私",
  },
  changelog: {
    title: "Airdraft 更新紀錄：每一版的變更",
    description:
      "Airdraft 的版本歷史：從第一個原始碼版本，到各模式專屬的語音模型、本機智慧功能與全新的原生介面。",
    heading: "更新紀錄",
    nav: "各版本",
    latest: "最新版本",
    source: "原始碼",
    releaseNotes: "版本說明",
    initialSource: "原始碼",
    sourceFor: (label, version) =>
      `${version}${/[0-9A-Za-z]$/.test(version) ? " " : ""}的${label}`,
    firstBuild: "第一個原始碼版本",
    availability: [
      "已發布的安裝檔是以 Apple Development 簽署、未經公證的個人使用版本。請參閱",
      "安裝說明",
      ".",
    ],
  },
  guides: {
    "offline-dictation-on-mac": {
      title: "在 Mac 上設定離線聽寫",
      description:
        "用本機語音辨識與選用的本機 AI 潤稿設定 Airdraft。包含 Mac 需求、模型怎麼選、Airdraft 自行測量的英文、日文與韓文結果，以及權限與模式設定。",
      summary: "依語言選語音模型，潤稿也留在本機，完成第一次聽寫。",
    },
    "mixed-chinese-english-dictation": {
      title: "在 Mac 上中英混著講：本機模型怎麼選",
      description:
        "一句話夾著英文術語時，該選哪個本機語音模型？Airdraft 自行測量五個模型的錯誤率、英文詞保留率、下載大小、記憶體與速度。",
      summary: "中英混說該用哪個本機模型，附 Airdraft 的實測取捨。",
    },
    "dictate-to-claude-code-and-terminals": {
      title: "用語音在 Claude Code、Codex 與終端機輸入提示詞",
      description:
        "在 Mac 上用語音輸入 Claude Code、Codex 與終端機的提示詞：自繪文字的終端機如何貼上、如何沿用現有訂閱潤稿，以及哪些資料會離開 Mac。",
      summary: "用說的輸入提示詞，並沿用你已付費的訂閱潤稿。",
    },
    "local-vs-cloud-dictation": {
      title: "聽寫該用本機還是雲端？",
      description:
        "比較 Airdraft 本機與雲端的語音辨識和潤稿選項。選定組合前，先看清楚音訊、逐字稿與已開啟的 App 情境會送到哪裡。",
      summary: "每種模型組合下，音訊與文字分別送到哪裡。",
    },
    "free-source-or-official-app": {
      title: "免費原始碼版還是官方版？",
      description:
        "比較 Airdraft 功能完整的免費原始碼版與一次買斷的官方版授權：安裝方式、更新、Mac 數量限制與目前供應情形。",
      summary: "比較安裝、更新與授權條款，以及現在能取得哪一種。",
    },
    "private-meeting-transcription": {
      title: "在自己的 Mac 上把會議轉成逐字稿",
      description:
        "在「轉錄」頁錄下會議的 App 音訊與麥克風，或匯入音訊、影片檔，在 Mac 上轉成逐字稿，可選擇標出講者。另說明所需權限、限制與匯出格式。",
      summary: "錄下通話或匯入檔案，標出講者，再匯出字幕。",
    },
    "compare-mac-dictation-apps": {
      title: "Airdraft 與 VoiceInk、Handy、Typeless、Apple 聽寫比較",
      metaTitle: "Airdraft 與 VoiceInk、Handy、Typeless、Apple 聽寫比較",
      description:
        "附查核日期，比較 Airdraft、VoiceInk、Handy、Typeless 與 macOS 27 的 Apple 聽寫：價格、原始碼、語音在哪裡處理、錄音與檔案轉錄，以及各自的強項。",
      summary:
        "並排比較價格、資料去向與錄音轉錄功能，也列出別人做得更好的地方。",
    },
  },
};
