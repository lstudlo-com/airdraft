import type { Messages } from "./types";

// Japanese. App labels follow the app's ja catalog (src/data/app.ts):
// 音声入力 (dictation), 整形 (refinement), モード, 語彙, 履歴.
export const ja: Messages = {
  gap: "",
  layout: { skip: "本文へ移動", rss: "Airdraft のリリース" },
  header: {
    pricing: "価格",
    support: "サポート",
    changelog: "更新履歴",
    home: "Airdraft ホーム",
    nav: "メインナビゲーション",
    github: "GitHub の Airdraft",
    source: "GitHub のソースコード",
    get: "Airdraft を入手",
    menu: "メニュー",
    language: "言語",
  },
  footer: {
    nav: "フッター",
    build: "ビルド手順",
    pricing: "価格",
    guides: "ガイド",
    support: "サポート",
    changelog: "更新履歴",
    rss: "RSS",
    privacy: "プライバシー",
    license: "ライセンス",
  },
  analytics: {
    title: "任意のウェブサイト分析",
    body: "訪問状況や関心を持たれている機能を把握するためにご協力ください。録音や入力した文字は収集しません。",
    privacy: "プライバシーの詳細",
    decline: "拒否",
    allow: "分析を許可",
  },
  home: {
    title: "Airdraft | 日本語で音声入力、会議の文字起こしもできる Mac アプリ",
    description:
      "Airdraft はオープンソースの Mac アプリです。話した言葉を英語の用語まじりのまま、どのアプリにも入力し、会議も文字起こしします。音声認識と整形は Mac 上でも、自分のプロバイダでも動かせます。ソースからのビルドは無料です。",
    // Phrases wrap as wholes (.hero h1 span).
    headline: ["声で、\u200bどこでも入力。", "なんでも、\u200b文字起こし。"],
    headlineGap: "",
    get: "Airdraft を入手",
    source: "ソースを見る",
    sample: "サンプルを試す",
    facts: [
      "オープンソース",
      "Mac 上でも、自分のプロバイダでも",
      "macOS 15 以降・Apple シリコン",
    ],
    guidesTitle: "設定ガイド",
    featuresTitle: "Airdraft がしてくれること",
    spoken: "えーと、Maya に、あの、draft は明日できるって伝えて。",
    outputs: [
      "Maya に draft は明日できると伝えて。",
      "Maya：draft は明日。",
      "Maya は明日 draft を受け取る。",
    ],
    typed: "Maya さん、明日の朝 draft をお送りします。",
    mixed: {
      kind: "languages",
      samples: [
        {
          lang: "ja",
          sentence:
            "demo の前に API key を差し替えて、main に push してください。",
        },
        {
          lang: "es",
          sentence: "Antes de la demo, cambia la API key y haz push a main.",
        },
        {
          lang: "zh-Hant",
          sentence: "明天 demo 前先把 API key 換掉，再 push 到 main。",
        },
        {
          lang: "fr",
          sentence: "Avant la démo, change l’API key et fais un push sur main.",
        },
      ],
    },
    tiles: {
      cursor: ["カーソル位置に入力", "いま入力しているアプリにそのまま。"],
      shortcut: [
        "ショートカットはひとつ",
        "⌃⌥ を長押し、または好きな組み合わせを登録。",
      ],
      profiles: ["モード", "4 つを内蔵、どれも編集できます。"],
      vocabulary: ["語彙", "名前や専門用語は一度教えるだけ。"],
      history: ["履歴", "検索、元の内容への切り替え、コピー。"],
      fallback: [
        "何も失われない",
        "整形に失敗しても、元のテキストが入ります。",
      ],
      privacy: [
        "Mac の中にとどまる",
        "ローカルモデルは何も送信せず、キーはキーチェーンに保存されます。",
      ],
      mixed: [
        "あなたの言葉に、英語をまじえて",
        "英語や専門用語をまじえて話せます。中国語は 繁體 か 简体 で出力。",
      ],
      plan: [
        "Claude や ChatGPT のプランで",
        "Claude Code か Codex。API キーは不要。",
      ],
    },
    privacyArt: {
      mac: "この Mac",
      speech: "音声認識",
      refinement: "整形",
      cloud: "必要ならクラウド",
    },
  },
  preview: {
    name: "音声入力のサンプル",
    said: "話した内容",
    inserts: "Airdraft が入力するテキスト",
    picker: "整形モード",
    run: "サンプルを再生",
    noscript:
      "クリーンのモードを表示しています。サンプルを再生するには JavaScript をオンにしてください。",
    spoken: [
      "「",
      { filler: "えーと、" },
      "Maya に draft は明日の朝送るって伝えて。",
      { filler: "それと、えっと、" },
      "打ち合わせを 2 時にずらせるか聞いて。」",
    ],
    examples: {
      clean:
        "Maya さん、draft は明日の朝お送りします。打ち合わせを 2 時に変更できますか？",
      concise:
        "Maya さん、draft は明日の朝送ります。打ち合わせは 2 時でいいですか？",
      summary:
        "明日の朝 Maya に draft を送る。打ち合わせを 2 時に変更できるか確認する。",
    },
    stop: "停止",
    again: "もう一度",
    placeholder: "キーを離すと、ここにテキストが表示されます。",
  },
  meetings: {
    title: "会議を Mac 上で文字起こし",
    intro:
      "通話を録音するかファイルを読み込んで、話者つきの文字起こしにします。",
    sample: "会議の文字起こしのサンプル",
    meeting: "デザインレビュー",
    meta: "10月21日 · 32:14 · Qwen3-ASR 1.7B",
    turns: [
      [1, "0:12", "onboarding の変更は木曜にリリースしましょう。"],
      [2, "0:31", "では release 前にスクリーンショットを更新します。"],
    ],
    points: [
      [
        "どのアプリでも録音",
        "ひとつのアプリかすべてのアプリに、マイクも加えられます。画面は録画しません。",
      ],
      [
        "ファイルも読み込める",
        "最長 2 時間、音声トラックがひとつの音声または動画。",
      ],
      [
        "話者はローカルで推定",
        "話者ラベルは任意で、名前の変更や割り当て直しもできます。",
      ],
      [
        "クラウドを選ばない限りローカル",
        "ローカルモデルなら音声はここに残ります。Soniox は確認後にだけアップロードします。",
      ],
      [
        "編集して書き出す",
        "元の内容を編集と並べて残し、TXT、JSON、SRT、VTT で書き出せます。",
      ],
    ],
    guide: "会議ガイドを読む",
  },
  interface: {
    title: "開くのが楽しくなるインターフェイス",
    intro: "浮き出たキー、くぼんだ溝、刻まれた区切り線。ライトでもダークでも。",
    alt: "ライトモードの Airdraft の設定ページ。サイドバーの横に、マイクと外観の浮き出たカードがあり、録音ウインドウの 6 つのスタイルも並んでいます。",
    compare: "ライトとダークの外観を比べる",
    half: "半分ライト、半分ダーク",
    allLight: "すべてライト",
    allDark: "すべてダーク",
    mixed: "ライト {light}%、ダーク {dark}%",
    materials: "ウインドウの素材",
    caption:
      "アプリの日本語インターフェイスの実際の画面です（グラファイトのアクセント）。",
    drag: "ドラッグしてライトとダークを比べられます。",
    press: ["押し込めるキー", "キーボードで ⌃⌥ を押すと一緒に沈みます。"],
    select: ["すべる選択", "まず溝が動き、アイコンの台座があとに続きます。"],
    travel: [
      "ストロークのあるコントロール",
      "ノブやつまみがトラックの中をすべります。",
    ],
    keysLabel: "Control Option",
    callouts: {
      "Carved mark": ["刻まれたマーク", "波形が彫り込まれています。"],
      "Pressed well": ["くぼんだ溝", "いまのページが沈みます。"],
      "Raised button": ["浮き出たボタン", "押せるものは浮き上がっています。"],
      "Raised card": ["浮き出たカード", "各セクションがページから浮きます。"],
      "Engraved divider": ["刻まれた区切り線", "行は溝で区切られます。"],
      "Reactive capsules": [
        "反応するカプセル",
        "5 つのスタイルが声に合わせて動きます。",
      ],
    },
  },
  pipeline: {
    title: "各ステップをどこで動かすか、あなたが選ぶ",
    intro:
      "音声認識と整形は別々に動きます。それぞれローカルかクラウドを選べます。",
    speech: "音声認識",
    refinement: "整形",
    insertion: "入力",
    where: (stage) => `${stage}を実行する場所`,
    mac: "この Mac",
    cloud: "クラウド",
    plan: "サブスクリプション",
    speechMac: "音声は Mac の外に出ません。",
    speechCloud: "音声はプロバイダに送られます。API キーはあなたのものです。",
    refinementMac:
      "ローカルモデルが文字起こしを整えます。テキストはここに残ります。",
    refinementCloud: "文字起こしは選んだプロバイダに送られます。",
    refinementPlan: "すでに支払っている Claude や ChatGPT のプランを使います。",
    atCursor: "カーソル位置に",
    insertionLine:
      "最後に語彙が名前を直し、入力中のアプリにテキストが入ります。",
    fix: ["9 時に", "で会いましょう。"],
  },
  get: {
    title: "Airdraft を入手",
    intro:
      "ソースから無料でビルドするか、すぐ使えるアプリを買い切りのライセンスで。",
    notOnSale: "公式アプリはまだ販売していません。",
    build: "自分でビルド",
    free: "無料",
    note: "すべての機能。Apple シリコンの Mac と Xcode が必要です。",
    action: "ビルド手順",
  },
  license: {
    title: "すぐ使えるアプリ",
    count: "Mac の台数",
    once: "買い切り",
    use: (macs) => `${macs}で個人利用。`,
    rest: "すべての機能、まず 14 日間の試用から。",
    restNotOnSale: "すべての機能。販売開始後は 14 日間の試用つき。",
    see: "価格を見る",
    plans: {
      "one-mac": { name: "1 台", title: "Mac 1 台", macs: "Mac 1 台" },
      "three-macs": {
        name: "3 台",
        title: "Mac 3 台",
        macs: "Mac 最大 3 台",
      },
    },
  },
  guideLinks: {
    labels: {
      "offline-dictation-on-mac": "オフライン音声入力",
      "mixed-chinese-english-dictation": "中国語と英語の混在",
      "dictate-to-claude-code-and-terminals": "Claude\u00a0Code、Codex",
      "local-vs-cloud-dictation": "ローカルかクラウドか",
      "free-source-or-official-app": "無料版か公式版か",
      "private-meeting-transcription": "会議を Mac で文字起こし",
      "compare-mac-dictation-apps": "Airdraft を比較",
    },
  },
  pricing: {
    title: "価格 — Airdraft",
    description:
      "Airdraft はソースから無料でビルドできます。すぐ使えるアプリは買い切りのライセンスで、Mac 1 台は 29 米ドル、最大 3 台は 49 米ドルです。",
    heading: "価格",
    intro: "無料でビルドするか、すぐ使えるアプリを一度だけ購入。",
    source: "オープンソース",
    build: "自分でビルド",
    buildAction: "ビルド手順",
    sourceList: "ソース版に含まれるもの",
    sourceIncludes: [
      "音声入力と会議",
      "すべての機能、制限なし",
      "ビルドに Xcode が必要",
    ],
    app: "すぐ使えるアプリ",
    once: "買い切り",
    buy: (macs) => `${macs}用を購入`,
    notOnSale: "まだ販売していません",
    appList: "すべてのライセンスに含まれるもの",
    licenseIncludes: [
      "音声入力と会議",
      "すべての機能、Xcode 不要",
      "14 日間の全機能試用",
      "購入したバージョンのアップデート",
      "Mac 間の移行は自分で",
    ],
    currency: "米ドル、税別。",
    costTitle: "1 年間の音声入力にかかる費用",
    costIntro: (count) => `同じ月 ${count} 回の音声入力を、5 つの方法で。`,
    columns: ["構成", "月額", "1 年目", "3 年間"],
    groups: ["Airdraft", "サブスクリプション"],
    rows: {
      local: { name: "すべてローカル", detail: "何も Mac の外に出ません" },
      "local-cerebras": {
        name: "ローカル音声認識 + Cerebras",
        detail: "文字起こしは Cerebras へ",
      },
      "groq-cerebras": {
        name: "Groq + Cerebras",
        detail: "音声は Groq へ、文字起こしは Cerebras へ",
      },
      wispr: { name: "Wispr Flow Pro", detail: "年払い" },
      typeless: { name: "Typeless Pro", detail: "年払い" },
    },
    note: ({ checked, perDay, seconds, inputTokens, outputTokens }) =>
      `営業日あたり ${perDay} 回、1 回 ${seconds} 秒、Mac 1 台のライセンスで計算。音声認識：Parakeet または Groq Whisper Large v3 Turbo。整形：Apple Intelligence、LM Studio、または Cerebras の Qwen 3.8 27B（入力 ${inputTokens} トークン、出力 ${outputTokens}）。${checked}時点の定価。`,
    checked: ({ year, month }) => `${year}年${month}月`,
    questions: "よくある質問",
    faq: {
      subscription: [
        "サブスクリプションですか？",
        [
          "いいえ。ライセンスは買い切りで、期限はありません。購入したバージョンのアップデートが含まれます。",
        ],
      ],
      licenses: [
        "ライセンスの違いは？",
        [
          "同時に使える Mac の台数だけです。ライセンスを移すときは、古い Mac で無効にしてください。",
        ],
      ],
      trial: [
        "試してから買えますか？",
        [
          "はい。すべての機能を使える 14 日間の試用があり、インストール時ではなく、あなたが始めたときから数えます。",
        ],
      ],
      trialNotOnSale: [
        "試してから買えますか？",
        [
          "公式アプリの販売が始まれば、すべての機能を使える 14 日間の試用がつき、インストール時ではなく、あなたが始めたときから数えます。まだ販売していないので試用版はダウンロードできませんが、無料のソース版なら、いますぐすべての機能を使えます。",
        ],
      ],
      editions: [
        "どちらの版にも何が含まれますか？",
        [
          "同じアプリです。どのアプリへの音声入力も、会議（アプリの音声とマイクの録音、または音声や動画の読み込み。話者ラベルは任意で、TXT、JSON、SRT、VTT に書き出し）も、モード、語彙、履歴も含まれます。公式アプリに追加機能はなく、Xcode でのビルドが不要になるだけです。詳しくは",
          { link: "meetingGuide", text: "会議ガイド" },
          "をご覧ください。",
        ],
      ],
      providers: [
        "クラウドのプロバイダの料金は？",
        [
          "キーチェーンに保存したあなた自身の API キーで、利用量に応じてプロバイダから直接請求されます。ローカルモデルは無料です。",
          { link: "offlineGuide", text: "日本語に合うモデル" },
          "をご覧ください。Claude Code と Codex は今のサブスクリプションを使います。",
          { link: "agentGuide", text: "コーディングエージェントへの音声入力" },
          "もどうぞ。",
        ],
      ],
      compare: [
        "ほかのアプリと比べると？",
        [
          "確認日つきの",
          {
            link: "comparison",
            text: "VoiceInk、Handy、Typeless、Apple の音声入力との比較",
          },
          "をご覧ください。ほかのアプリが優れている点も書いています。",
        ],
      ],
    },
  },
};
