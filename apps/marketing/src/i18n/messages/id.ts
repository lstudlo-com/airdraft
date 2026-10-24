import { monthYear } from "./format";
import type { Messages } from "./types";

// Indonesian. App labels follow the translators' id catalog export
// (src/data/app.ts): dikte, penyempurnaan (refinement), profil, Pengaturan.
export const id: Messages = {
  gap: " ",
  english: " (Inggris)",
  layout: {
    skip: "Langsung ke konten",
    rss: "Rilis Airdraft (bahasa Inggris)",
  },
  header: {
    pricing: "Harga",
    support: "Bantuan",
    changelog: "Perubahan",
    home: "Beranda Airdraft",
    nav: "Navigasi utama",
    github: "Airdraft di GitHub",
    source: "Kode sumber di GitHub",
    get: "Dapatkan Airdraft",
    menu: "Menu",
    language: "Bahasa",
    homeOnly: "beranda",
  },
  footer: {
    nav: "Footer",
    build: "Petunjuk build",
    pricing: "Harga",
    guides: "Panduan",
    support: "Bantuan",
    donate: "Donasi",
    changelog: "Perubahan",
    rss: "RSS",
    privacy: "Privasi",
    license: "Lisensi",
    languages: "Bahasa",
  },
  analytics: {
    title: "Analitik situs opsional",
    body: "Bantu kami memahami kunjungan dan fitur yang diminati. Tanpa rekaman atau teks yang diketik.",
    privacy: "Detail privasi",
    decline: "Tolak",
    allow: "Izinkan analitik",
  },
  home: {
    title: "Airdraft | Dikte dalam bahasamu dan transkripsi rapat di Mac",
    description:
      "Airdraft adalah app Mac sumber terbuka yang mengetik ucapanmu ke app apa pun, dalam bahasamu dengan istilah bahasa Inggris di tengahnya, dan mentranskripsi rapat. Ucapan dan penyempurnaan berjalan di Mac-mu atau dengan penyedia milikmu sendiri. Build dari kode sumber gratis.",
    headline: [
      "Bicara dalam bahasamu,",
      "dengan istilah Inggris.",
      "Transkripsikan rapatmu.",
    ],
    headlineGap: " ",
    get: "Dapatkan Airdraft",
    source: "Lihat kode sumber",
    sample: "Coba contohnya",
    facts: [
      "Sumber terbuka",
      "Di Mac-mu atau dengan penyedia sendiri",
      "macOS 15+ di Apple silicon",
    ],
    guidesTitle: "Pilih penyiapanmu",
    guidesIntro:
      "Dikte offline dalam bahasamu, campuran Mandarin dan Inggris, dikte ke Claude Code dan terminal, lokal atau cloud, dan rapat. Panduannya dalam bahasa Inggris.",
    featuresTitle: "Yang diurus Airdraft untukmu",
    spoken: "Eh, bilang ke Maya, itu, draft-nya jadi besok.",
    outputs: [
      "Bilang ke Maya draft-nya jadi besok.",
      "Draft untuk Maya besok.",
      "Maya menerima draft besok.",
    ],
    typed: "Halo Maya, aku kirim draft-nya besok pagi.",
    mixed: {
      kind: "languages",
      samples: [
        {
          lang: "id",
          sentence: "Sebelum demo, ganti API key lalu push ke main.",
        },
        {
          lang: "es",
          sentence: "Antes de la demo, cambia la API key y haz push a main.",
        },
        {
          lang: "ja",
          sentence:
            "demo の前に API key を差し替えて、main に push してください。",
        },
        {
          lang: "zh-Hant",
          sentence: "明天 demo 前先把 API key 換掉，再 push 到 main。",
        },
      ],
    },
    tiles: {
      cursor: ["Masuk di kursor", "Di app mana pun kamu sedang mengetik."],
      shortcut: ["Satu pintasan", "Tahan ⌃⌥, atau rekam pintasanmu sendiri."],
      profiles: ["Profil", "Empat bawaan. Tulis ulang yang mana saja."],
      vocabulary: ["Kosakatamu", "Ajarkan nama dan istilah sekali saja."],
      history: ["Riwayat", "Cari, kembali ke aslinya, salin."],
      fallback: [
        "Tidak ada yang hilang",
        "Jika penyempurnaan gagal, teks mentah tetap masuk.",
      ],
      privacy: [
        "Tetap di Mac-mu",
        "Dengan model lokal, tidak ada yang keluar. Kunci disimpan di Rantai Kunci.",
      ],
      mixed: [
        "Bahasamu, dengan bahasa Inggris di tengahnya",
        "Selipkan istilah Inggris dan teknis di kalimatmu. Mandarin bisa keluar sebagai 繁體 atau 简体.",
      ],
      plan: [
        "Paket Claude atau ChatGPT-mu",
        "Claude Code atau Codex, tanpa kunci API.",
      ],
    },
    privacyArt: {
      mac: "Mac ini",
      speech: "Ucapan",
      refinement: "Penyempurnaan",
      cloud: "Cloud, jika kamu pilih",
    },
  },
  preview: {
    name: "Contoh dikte",
    said: "Yang kamu ucapkan",
    inserts: "Yang dimasukkan Airdraft",
    picker: "Profil penyempurnaan",
    run: "Putar contoh",
    noscript:
      "Menampilkan profil Rapi. Aktifkan JavaScript untuk memutar contoh.",
    spoken: [
      "“",
      { filler: "Eh," },
      " kabari Maya aku kirim draft-nya besok pagi. ",
      { filler: "Terus, apa ya," },
      " tanyakan apa rapat kita bisa diundur ke jam dua.”",
    ],
    examples: {
      clean:
        "Halo Maya, aku kirim draft-nya besok pagi. Apa rapat kita bisa diundur ke jam dua?",
      concise: "Maya, draft besok pagi. Rapat bisa jam dua?",
      summary:
        "Kirim draft ke Maya besok pagi. Minta rapat diundur ke jam dua.",
    },
    stop: "Hentikan",
    again: "Putar lagi",
    placeholder: "Teks muncul di sini saat kamu melepas tombol.",
  },
  meetings: {
    title: "Rapat, ditranskripsi di Mac-mu",
    intro:
      "Rekam panggilan atau impor file, lalu jadikan transkrip lengkap dengan pembicara.",
    sample: "Contoh transkrip rapat",
    meeting: "Tinjauan desain",
    meta: "21 Okt · 32:14 · Whisper Large v3 Turbo",
    turns: [
      [1, "0:12", "Kita rilis perubahan onboarding hari Kamis."],
      [2, "0:31", "Kalau begitu aku perbarui screenshot sebelum rilis."],
    ],
    points: [
      [
        "Rekam app apa pun",
        "Satu app atau audio semua app, ditambah mikrofonmu. Video layar tidak disimpan.",
      ],
      [
        "Atau impor file",
        "Audio atau video hingga dua jam, dengan satu trek audio.",
      ],
      [
        "Pembicara, diperkirakan secara lokal",
        "Label pembicara opsional yang bisa kamu ganti nama dan tetapkan ulang.",
      ],
      [
        "Lokal, kecuali kamu pilih cloud",
        "Model lokal menyimpan audio di sini; Soniox mengunggah hanya setelah kamu konfirmasi.",
      ],
      [
        "Edit, lalu ekspor",
        "Versi asli tetap di samping editanmu. Ekspor TXT, JSON, SRT, atau VTT.",
      ],
    ],
    guide: "Baca panduan rapat",
  },
  interface: {
    title: "Antarmuka yang menyenangkan dibuka",
    intro:
      "Tombol timbul, cekungan tertekan, dan alur terukir, dalam mode terang dan gelap.",
    alt: "Halaman Pengaturan Airdraft dalam mode terang: bilah samping di samping kartu timbul untuk mikrofon dan tampilan, termasuk enam gaya jendela rekaman.",
    compare: "Bandingkan tampilan terang dan gelap",
    half: "Setengah terang, setengah gelap",
    allLight: "Semua terang",
    allDark: "Semua gelap",
    mixed: "{light}% terang, {dark}% gelap",
    materials: "Material di jendela",
    caption:
      "Dirender dari antarmuka bahasa Inggris app, dengan aksen Graphite.",
    unreleased:
      "Versi app yang sudah dirilis masih menampilkan antarmuka bahasa Inggris; label yang dikutip di sini berasal dari terjemahan bahasa Indonesianya.",
    drag: "Seret untuk membandingkan terang dan gelap.",
    press: [
      "Tombol yang bisa ditekan",
      "Tahan ⌃⌥ di keyboard untuk menekannya.",
    ],
    select: [
      "Pilihan yang meluncur",
      "Cekungan bergerak dulu; alas ikon menyusul.",
    ],
    travel: [
      "Kontrol dengan jarak tempuh",
      "Kenop dan penggeser meluncur di dalam jalurnya.",
    ],
    keysLabel: "Control Option",
    callouts: {
      "Carved mark": ["Tanda terukir", "Gelombangnya dipahat."],
      "Pressed well": ["Cekungan tertekan", "Halaman aktif tenggelam."],
      "Raised button": ["Tombol timbul", "Kontrol menonjol untuk ditekan."],
      "Raised card": ["Kartu timbul", "Setiap bagian terangkat dari halaman."],
      "Engraved divider": ["Pemisah terukir", "Baris dipisah oleh alur."],
      "Reactive capsules": [
        "Kapsul yang bereaksi",
        "Lima gaya mengikuti suaramu.",
      ],
    },
  },
  pipeline: {
    title: "Kamu yang memilih di mana setiap langkah berjalan",
    intro:
      "Ucapan dan penyempurnaan berjalan terpisah. Pilih lokal atau cloud untuk masing-masing.",
    speech: "Ucapan",
    refinement: "Penyempurnaan",
    insertion: "Penyisipan",
    where: (stage) => `Tempat ${stage.toLowerCase()} berjalan`,
    mac: "Mac ini",
    cloud: "Cloud",
    plan: "Langganan",
    speechMac: "Audio tidak pernah keluar dari Mac-mu.",
    speechCloud: "Audio dikirim ke penyedia, dengan kunci API milikmu.",
    refinementMac: "Model lokal merapikan transkrip. Teksnya tetap di sini.",
    refinementCloud: "Transkrip dikirim ke penyedia yang kamu pilih.",
    refinementPlan: "Memakai paket Claude atau ChatGPT yang sudah kamu bayar.",
    atCursor: "Di kursormu",
    insertionLine:
      "Terakhir, kosakatamu membetulkan nama. Lalu teks masuk ke app tempat kamu mengetik.",
    fix: ["Ketemu di", "jam sembilan."],
  },
  get: {
    title: "Dapatkan Airdraft",
    intro:
      "Gratis jika di-build dari kode sumber, atau lisensi sekali bayar untuk app siap pakai.",
    notOnSale: "App resminya belum dijual.",
    build: "Build sendiri",
    free: "Gratis",
    note: "Semua fitur. Butuh Xcode di Mac dengan Apple silicon.",
    action: "Petunjuk build",
  },
  license: {
    title: "App siap pakai",
    count: "Jumlah Mac",
    once: "sekali bayar",
    use: (macs) => `Penggunaan pribadi untuk ${macs}.`,
    rest: " Semua fitur, dengan uji coba 14 hari lebih dulu.",
    restNotOnSale:
      " Semua fitur, dengan uji coba 14 hari setelah mulai dijual.",
    see: "Lihat harga",
    plans: {
      "one-mac": { name: "1 Mac", title: "Satu Mac", macs: "satu Mac" },
      "three-macs": {
        name: "3 Mac",
        title: "Tiga Mac",
        macs: "hingga tiga Mac",
      },
    },
  },
  guideLinks: { read: "Baca panduan", readLabel: "Baca panduan: " },
  pricing: {
    title: "Harga — Airdraft",
    description:
      "Airdraft gratis di-build dari kode sumber. App siap pakai adalah lisensi sekali bayar: US$29 untuk satu Mac atau US$49 untuk hingga tiga.",
    heading: "Harga",
    intro: "Build gratis, atau beli app siap pakai sekali saja.",
    source: "Sumber terbuka",
    build: "Build sendiri",
    buildAction: "Petunjuk build",
    sourceList: "Build dari kode sumber mencakup",
    sourceIncludes: [
      "Dikte dan Rapat",
      "Semua fitur, tanpa kunci",
      "Butuh Xcode untuk build",
    ],
    app: "App siap pakai",
    once: "sekali bayar",
    buy: (macs) => `Beli untuk ${macs}`,
    notOnSale: "Belum dijual",
    appList: "Setiap lisensi mencakup",
    licenseIncludes: [
      "Dikte dan Rapat",
      "Semua fitur, tanpa Xcode",
      "Uji coba penuh 14 hari",
      "Pembaruan untuk versi yang kamu beli",
      "Pindahkan antar-Mac sendiri",
    ],
    currency: "Dolar AS, belum termasuk pajak.",
    costTitle: "Biaya dikte selama setahun",
    costIntro: (count) =>
      `${count} dikte yang sama setiap bulan, dengan lima cara.`,
    columns: ["Penyiapan", "Per bulan", "Tahun pertama", "Tiga tahun"],
    groups: ["Airdraft", "Langganan"],
    rows: {
      local: {
        name: "Semua lokal",
        detail: "Tidak ada yang keluar dari Mac-mu",
      },
      "local-cerebras": {
        name: "Ucapan lokal + Cerebras",
        detail: "Transkrip dikirim ke Cerebras",
      },
      "groq-cerebras": {
        name: "Groq + Cerebras",
        detail: "Audio ke Groq, transkrip ke Cerebras",
      },
      wispr: { name: "Wispr Flow Pro", detail: "Ditagih tahunan" },
      typeless: { name: "Typeless Pro", detail: "Ditagih tahunan" },
    },
    note: ({ checked, perDay, seconds, inputTokens, outputTokens }) =>
      `${perDay} dikte per hari kerja, masing-masing ${seconds} detik, dengan lisensi satu Mac. Ucapan: Parakeet atau Groq Whisper Large v3 Turbo. Penyempurnaan: Apple Intelligence, LM Studio, atau Qwen 3.8 27B di Cerebras (${inputTokens} token masuk, ${outputTokens} keluar). Harga daftar, ${checked}.`,
    checked: monthYear("id"),
    questions: "Pertanyaan",
    faq: {
      subscription: [
        "Apakah ini langganan?",
        [
          "Bukan. Lisensi dibeli sekali dan tidak kedaluwarsa. Pembaruan untuk versi yang kamu beli sudah termasuk.",
        ],
      ],
      licenses: [
        "Apa bedanya kedua lisensi?",
        [
          "Hanya berapa Mac yang bisa memakainya bersamaan. Untuk memindahkan lisensi, nonaktifkan Mac yang lama.",
        ],
      ],
      trial: [
        "Bisakah saya mencobanya dulu?",
        [
          "Bisa. App punya uji coba 14 hari dengan semua fitur, yang dimulai saat kamu memilih, bukan saat dipasang.",
        ],
      ],
      trialNotOnSale: [
        "Bisakah saya mencobanya dulu?",
        [
          "Setelah app resmi dijual, akan ada uji coba 14 hari dengan semua fitur, yang dimulai saat kamu memilih, bukan saat dipasang. App ini belum dijual, jadi hari ini belum ada uji coba yang bisa diunduh. Build gratis dari kode sumber sudah punya semua fitur sekarang.",
        ],
      ],
      editions: [
        "Apa isi kedua edisi?",
        [
          "App yang sama: dikte ke app apa pun, Rapat (rekam audio app dan mikrofonmu atau impor audio dan video, dengan label pembicara opsional dan ekspor TXT, JSON, SRT, atau VTT), profil, kosakata, dan riwayat. App resmi tidak menambah fitur; ia menghemat build dengan Xcode. Lihat ",
          { link: "meetingGuide", text: "panduan rapat" },
          ".",
        ],
      ],
      providers: [
        "Berapa biaya penyedia cloud?",
        [
          "Mereka menagihmu langsung, sesuai pemakaian, dengan kunci API milikmu yang disimpan di Rantai Kunci. Model lokal gratis; lihat ",
          { link: "offlineGuide", text: "mana yang cocok untuk bahasamu" },
          ". Claude Code dan Codex memakai langgananmu yang sekarang; lihat ",
          { link: "agentGuide", text: "dikte ke agen coding" },
          ".",
        ],
      ],
      compare: [
        "Bagaimana dibandingkan app lain?",
        [
          "Lihat ",
          {
            link: "comparison",
            text: "perbandingan bertanggal dengan VoiceInk, Handy, Typeless, dan Dikte Apple",
          },
          ", termasuk di mana mereka lebih baik.",
        ],
      ],
    },
  },
};
