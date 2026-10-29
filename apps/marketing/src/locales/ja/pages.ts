import type { PageCopy } from "../types";

export const ja: PageCopy = {
  chrome: {
    breadcrumb: "パンくずリスト",
    home: "ホーム",
    guides: "ガイド",
    related: "関連するガイド",
    onThisPage: "このページの内容",
  },
  notFound: {
    title: "ページが見つかりません | Airdraft",
    heading: "このページは存在しません",
    action: "ホームページへ",
  },
  hub: {
    title: "Mac の音声入力の設定とモデルのガイド | Airdraft",
    description:
      "Airdraft のガイド。オフライン音声入力、中国語と英語の混在、コーディングエージェント、ローカルとクラウド、文字起こし、アプリの比較を解説します。",
    heading: "音声入力ガイド",
    help: [
      "設定は済んだのに、うまく動きませんか？",
      "権限、ショートカット、よくある問題を確認しましょう。",
    ],
    pricing: "価格を比べる",
    changes: "変更点を見る",
  },
  support: {
    title: "Airdraft サポート：権限、ショートカット、モデル",
    description:
      "権限、ショートカット、モデルに関する Airdraft のよくある問題を解決するか、不具合を報告できます。",
    heading: "サポート",
  },
  privacy: {
    title: "Airdraft のプライバシー：Mac に残るもの",
    description:
      "Airdraft が音声入力のデータ、任意のアプリの使用状況データ、ウェブサイト分析をどう扱うか、またそれぞれの選択を変更する方法を説明します。",
    heading: "プライバシー",
  },
  changelog: {
    title: "Airdraft の更新履歴：すべてのリリース",
    description:
      "Airdraft のリリース履歴。最初のソースビルドから、モードごとの音声モデル、ローカルのインテリジェンス、新しいネイティブのインターフェイスまで。",
    heading: "更新履歴",
    nav: "リリースのバージョン",
    latest: "最新のリリース",
    source: "ソース",
    releaseNotes: "リリースノート",
    initialSource: "最初のソース",
    sourceFor: (label, version) =>
      /^\d/.test(version) ? `${version} の${label}` : `${label}（${version}）`,
    firstBuild: "最初のソースビルド",
    availability: [
      "公開しているインストーラは、Apple Development で署名した個人利用向けのビルドで、公証は受けていません。詳しくは",
      "インストールの案内",
      "をご覧ください。",
    ],
  },
  guides: {
    "offline-dictation-on-mac": {
      title: "Mac でオフライン音声入力を設定する",
      description:
        "ローカルの音声認識と任意のローカル整形で Airdraft を設定。Mac の要件、モデルの選び方、権限、モードを確認できます。",
      summary:
        "お使いの言語に合う音声モデルを選び、整形もローカルにして、最初の音声入力をします。",
    },
    "mixed-chinese-english-dictation": {
      title: "Mac で中国語と英語を混ぜて音声入力する",
      description:
        "標準中国語に英語の用語が混ざる文に向いたローカル音声モデルを選びます。Airdraft 独自の計測で、誤り率、残った英語の用語、サイズ、メモリ、速度を比べています。",
      summary:
        "標準中国語と英語の混在に向いたローカルモデルを、Airdraft 独自の計測から選びます。",
    },
    "dictate-to-claude-code-and-terminals": {
      title: "Claude Code、Codex、ターミナルにプロンプトを音声入力する",
      metaTitle: "Claude Code、Codex、ターミナルに音声入力 | Airdraft",
      description:
        "Claude Code、Codex、ターミナルにプロンプトを話して入力。ペーストの仕組み、契約中のプランでの整形、Mac の外に出るものを確認できます。",
      summary:
        "コーディングエージェントやターミナルにプロンプトを話して入力し、契約中のプランで整形します。",
    },
    "local-vs-cloud-dictation": {
      title: "ローカルとクラウドの音声入力を選ぶ",
      description:
        "Airdraft のローカルとクラウドの音声認識と整形の選択肢を比べます。構成を選ぶ前に、音声、文字起こし、オンにしたアプリのコンテキストの送信先を確認できます。",
      summary: "モデルの組み合わせごとに、音声とテキストの行き先を確認します。",
    },
    "free-source-or-official-app": {
      title: "無料のソースビルドか公式アプリかを選ぶ",
      description:
        "無料のソースビルドと買い切りの公式アプリを比較。セットアップ、アップデート、Mac の台数、現在の提供状況を確認できます。",
      summary:
        "セットアップ、アップデート、ライセンスの条件と、いま入手できるものを比べます。",
    },
    "private-meeting-transcription": {
      title: "Mac で会議をプライベートに文字起こしする",
      description:
        "会議のアプリ音声とマイクを録音、またはファイルを読み込み、Mac 上で文字起こし。話者ラベルや書き出しも確認できます。",
      summary:
        "通話を録音するかファイルを読み込み、話者を分けて、字幕を書き出します。",
    },
    "compare-mac-dictation-apps": {
      title: "Airdraft と VoiceInk、Handy、Typeless、Apple の音声入力を比較",
      metaTitle: "Airdraft、VoiceInk、Handy、Typeless、Apple を比較",
      description:
        "Airdraft、VoiceInk、Handy、Typeless、Apple の音声入力を日付つきで比較。価格、ソース、音声の処理場所、それぞれが優れている点。",
      summary:
        "価格、データの流れ、録音の文字起こしへの対応を並べて比べます。ほかのアプリが優れている点も含みます。",
    },
  },
};
