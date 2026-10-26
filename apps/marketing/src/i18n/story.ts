import type { Locale } from "./index";

/**
 * The homepage's scroll story (components/StoryScroll.astro): one dictation
 * told in four steps as the visitor scrolls. `spoken` is what was said, with
 * fillers marked; `written` is what lands at the cursor. Sample text,
 * illustrative like the rest of the homepage's samples.
 */
export interface StoryCopy {
  title: string;
  steps: [string, string][];
  spoken: (string | { filler: string })[];
  written: string;
}

export const story: Record<Locale, StoryCopy> = {
  en: {
    title: "Hold, speak, let go",
    steps: [
      [
        "Hold the shortcut",
        "Control and Option, in whatever app you’re typing in.",
      ],
      ["Say it the way you’d say it", "Pauses, fillers and restarts are fine."],
      [
        "Airdraft tidies it",
        "Refinement drops fillers and fixes slips. Turn it off to keep every word.",
      ],
      [
        "Let go, and it’s there",
        "The text lands at your cursor, ready to send.",
      ],
    ],
    spoken: [
      { filler: "Um, so" },
      " can we move the design review to ",
      { filler: "uh," },
      " Thursday?",
    ],
    written: "Can we move the design review to Thursday?",
  },
  "zh-tw": {
    title: "按住、說話、放開",
    steps: [
      ["按住快速鍵", "在任何正在打字的 App 裡，按住 Control 與 Option。"],
      ["照平常的方式說", "停頓、贅字、說到一半改口都沒關係。"],
      ["Airdraft 幫你整理", "潤稿會刪掉贅字、修正口誤；關掉潤稿就保留每個字。"],
      ["放開，文字就到了", "文字直接出現在游標位置，馬上可以送出。"],
    ],
    spoken: [
      { filler: "嗯，那個，" },
      "設計審查可以",
      { filler: "，呃，" },
      "改到星期四嗎？",
    ],
    written: "設計審查可以改到星期四嗎？",
  },
  "zh-cn": {
    title: "按住、说话、松开",
    steps: [
      ["按住快捷键", "在任何正在打字的 App 里，按住 Control 和 Option。"],
      ["像平时一样说", "停顿、口头禅、说到一半改口都没关系。"],
      [
        "Airdraft 帮你整理",
        "润色会删掉口头禅、修正口误；关闭润色则保留每个字。",
      ],
      ["松开，文字就到了", "文字直接出现在光标处，马上就能发送。"],
    ],
    spoken: [
      { filler: "嗯，那个，" },
      "设计评审能不能",
      { filler: "，呃，" },
      "改到周四？",
    ],
    written: "设计评审能不能改到周四？",
  },
  es: {
    title: "Mantén, habla, suelta",
    steps: [
      [
        "Mantén pulsado el atajo",
        "Control y Opción, en la app en la que estés escribiendo.",
      ],
      [
        "Habla como siempre",
        "Las pausas, muletillas y frases a medias no importan.",
      ],
      [
        "Airdraft lo ordena",
        "El refinamiento quita muletillas y corrige deslices. Desactívalo para conservar cada palabra.",
      ],
      ["Suelta y ya está", "El texto aparece en el cursor, listo para enviar."],
    ],
    spoken: [
      { filler: "Eh, bueno," },
      " ¿podemos pasar la revisión de diseño al ",
      { filler: "mmm," },
      " jueves?",
    ],
    written: "¿Podemos pasar la revisión de diseño al jueves?",
  },
  ja: {
    title: "押して、話して、離す",
    steps: [
      [
        "ショートカットを押し続ける",
        "入力中のアプリで、Control と Option を押したままにします。",
      ],
      ["いつも通りに話す", "言いよどみや言い直しがあっても大丈夫です。"],
      [
        "Airdraft が整える",
        "整形がフィラーや言い間違いを取り除きます。オフにすれば一語一句そのまま残ります。",
      ],
      [
        "離せば、もう入力済み",
        "テキストはカーソル位置に入り、そのまま送信できます。",
      ],
    ],
    spoken: [
      { filler: "えーと、" },
      "デザインレビューを",
      { filler: "、あの、" },
      "木曜日に移せますか？",
    ],
    written: "デザインレビューを木曜日に移せますか？",
  },
};
