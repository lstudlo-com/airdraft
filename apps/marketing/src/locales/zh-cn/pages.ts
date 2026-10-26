import type { PageCopy } from "../types";

export const zhCn: PageCopy = {
  chrome: {
    breadcrumb: "面包屑导航",
    home: "首页",
    guides: "指南",
    related: "相关指南",
  },
  notFound: {
    title: "找不到页面 — Airdraft",
    heading: "这个页面不存在",
    action: "返回首页",
  },
  hub: {
    title: "Mac 听写设置与模型指南 | Airdraft",
    description:
      "Airdraft 实用指南：用你的语言在 Mac 上离线听写、中英混说、对 Claude Code 和终端听写、本机与云端模型、在本机转录会议、与其他 App 的对比，以及免费源代码编译与官方版的区别。",
    heading: "听写指南",
    help: ["已经设置好却出了问题？", "检查权限、快捷键和常见问题。"],
    pricing: "比较价格",
    changes: "查看更新内容",
  },
  support: {
    title: "支持 — Airdraft",
    description:
      "解决 Airdraft 在权限、快捷键和模型方面的常见问题，或者报告错误。",
    heading: "支持",
  },
  privacy: {
    title: "隐私 | Airdraft",
    description:
      "Airdraft 如何处理听写数据、可选的 App 使用数据和网站分析，以及如何更改这两项选择。",
    heading: "隐私",
  },
  changelog: {
    title: "更新日志 — Airdraft",
    description:
      "Airdraft 的版本历史：从第一个源代码版本，到按模式选择语音模型、本机智能和全新的原生界面。",
    heading: "更新日志",
    nav: "发布版本",
    latest: "最新版本",
    source: "源代码",
    releaseNotes: "发布说明",
    initialSource: "初始源代码",
    sourceFor: (label, version) => `${version} 的${label}`,
    firstBuild: "第一个源代码版本",
    availability: [
      "已发布的安装包是以 Apple Development 签名、未经公证的个人使用版本。请参阅",
      "安装说明",
      "。",
    ],
  },
  guides: {
    "offline-dictation-on-mac": {
      title: "在 Mac 上设置离线听写",
      description:
        "为 Airdraft 设置本机语音识别和可选的本机 AI 润色。了解 Mac 的要求、该选哪个模型、Airdraft 自己对英语、日语和韩语的测量，以及权限和模式。",
      summary: "为你的语言选一个语音模型，让润色也留在本机，完成第一次听写。",
    },
    "mixed-chinese-english-dictation": {
      title: "在 Mac 上中英混着说：本机模型怎么选",
      description:
        "一句话里夹着英文术语，该选哪个本机语音模型？Airdraft 自行测量了各模型的错误率、英文词保留率、下载大小、内存和速度。",
      summary: "中英混说该用哪个本机模型，附 Airdraft 的实测取舍。",
    },
    "dictate-to-claude-code-and-terminals": {
      title: "用语音给 Claude Code、Codex 和终端输入提示词",
      description:
        "在 Mac 上用语音给 Claude Code、Codex 和终端输入提示词：自绘文字的终端怎么粘贴，怎样沿用现有套餐润色，以及哪些数据会离开你的 Mac。",
      summary: "用说的输入提示词，并用你已付费的套餐润色。",
    },
    "local-vs-cloud-dictation": {
      title: "听写用本机还是云端",
      description:
        "比较 Airdraft 的本机与云端语音识别和润色选项。选择设置之前，先看清音频、转录文本和已开启的 App 上下文会去哪里。",
      summary: "看清每种模型组合下，你的音频和文字会去哪里。",
    },
    "free-source-or-official-app": {
      title: "选免费源代码编译还是官方版",
      description:
        "比较 Airdraft 功能完整的免费源代码编译与一次买断的官方版许可证：安装、更新、Mac 数量限制和目前能否购买。",
      summary: "比较安装、更新和许可条款，以及现在能拿到什么。",
    },
    "private-meeting-transcription": {
      title: "在自己的 Mac 上把会议转成转录稿",
      description:
        "在「转录」页面录下会议的 App 音频和麦克风，或导入文件，在 Mac 上转录，可选择标出发言人。另附所需权限、限制和导出格式。",
      summary: "录下通话或导入文件，标出发言人，再导出字幕。",
    },
    "compare-mac-dictation-apps": {
      title: "Airdraft 与 VoiceInk、Handy、Typeless、Apple 听写对比",
      description:
        "附核查日期，对比 Airdraft、VoiceInk、Handy、Typeless 和 macOS 27 的 Apple 听写：价格、源代码、语音在哪里处理、录音和文件转录，以及各自的长处。",
      summary:
        "并排比较价格、数据去向和录音转录功能，也列出别人做得更好的地方。",
    },
  },
};
