import { monthYear } from "./format";
import type { Messages } from "./types";

// French. App labels follow the translators' fr catalog export
// (src/data/app.ts): dictée, affinage (refinement), profils, Réglages.
export const fr: Messages = {
  gap: " ",
  english: " (anglais)",
  layout: {
    skip: "Aller au contenu",
    rss: "Versions d’Airdraft (en anglais)",
  },
  header: {
    pricing: "Tarifs",
    support: "Aide",
    changelog: "Nouveautés",
    home: "Accueil d’Airdraft",
    nav: "Navigation principale",
    github: "Airdraft sur GitHub",
    source: "Code source sur GitHub",
    get: "Obtenir Airdraft",
    menu: "Menu",
    language: "Langue",
    homeOnly: "page d’accueil",
  },
  footer: {
    nav: "Pied de page",
    build: "Instructions de compilation",
    pricing: "Tarifs",
    guides: "Guides",
    support: "Aide",
    donate: "Faire un don",
    changelog: "Nouveautés",
    rss: "RSS",
    privacy: "Confidentialité",
    license: "Licence",
    languages: "Langues",
  },
  analytics: {
    title: "Mesure d’audience facultative",
    body: "Aidez-nous à comprendre les visites et les fonctions qui intéressent. Aucun enregistrement ni texte saisi.",
    privacy: "Détails sur la confidentialité",
    decline: "Refuser",
    allow: "Autoriser la mesure",
  },
  home: {
    title:
      "Airdraft | Dictée dans votre langue et transcription de réunions sur Mac",
    description:
      "Airdraft est une app Mac open source qui écrit ce que vous dites dans n’importe quelle app, dans votre langue et avec des termes anglais au milieu, et qui transcrit vos réunions. La reconnaissance vocale et l’affinage tournent sur votre Mac ou chez votre propre fournisseur. Gratuit à compiler depuis le code source.",
    headline: [
      "Parlez votre langue,",
      "termes anglais compris.",
      "Transcrivez vos réunions.",
    ],
    headlineGap: " ",
    get: "Obtenir Airdraft",
    source: "Voir le code",
    sample: "Essayer l’exemple",
    facts: [
      "Open source",
      "Sur votre Mac ou chez votre fournisseur",
      "macOS 15+ sur puce Apple",
    ],
    guidesTitle: "Choisissez votre configuration",
    guidesIntro:
      "Dictée hors ligne dans votre langue, chinois et anglais mêlés, dictée dans Claude Code et les terminaux, local ou cloud, et réunions. Les guides sont en anglais.",
    featuresTitle: "Ce qu’Airdraft fait pour vous",
    spoken: "Euh, dis à Maya que le, euh, brouillon arrive demain.",
    outputs: [
      "Dis à Maya que le brouillon arrive demain.",
      "Brouillon à Maya demain.",
      "Maya reçoit le brouillon demain.",
    ],
    typed: "Bonjour Maya, je t’envoie le brouillon demain matin.",
    mixed: {
      kind: "languages",
      samples: [
        {
          lang: "fr",
          sentence: "Avant la démo, change l’API key et fais un push sur main.",
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
      cursor: [
        "S’insère au curseur",
        "Dans l’app où vous êtes en train d’écrire.",
      ],
      shortcut: ["Un seul raccourci", "Maintenez ⌃⌥, ou enregistrez le vôtre."],
      profiles: [
        "Profils",
        "Quatre intégrés. Réécrivez celui que vous voulez.",
      ],
      vocabulary: [
        "Votre vocabulaire",
        "Apprenez-lui noms et jargon une fois.",
      ],
      history: ["Historique", "Cherchez, revenez à l’original, copiez."],
      fallback: [
        "Rien ne se perd",
        "Si l’affinage échoue, le texte brut est inséré.",
      ],
      privacy: [
        "Reste sur votre Mac",
        "Avec des modèles locaux, rien ne sort. Les clés restent dans le trousseau.",
      ],
      mixed: [
        "Votre langue, avec de l’anglais",
        "Glissez des termes anglais et techniques dans vos phrases. Le chinois peut sortir en 繁體 ou 简体.",
      ],
      plan: [
        "Votre forfait Claude ou ChatGPT",
        "Claude Code ou Codex, sans clé API.",
      ],
    },
    privacyArt: {
      mac: "Ce Mac",
      speech: "Parole",
      refinement: "Affinage",
      cloud: "Cloud, si vous le choisissez",
    },
  },
  preview: {
    name: "Exemple de dictée",
    said: "Ce que vous avez dit",
    inserts: "Ce qu’Airdraft insère",
    picker: "Profil d’affinage",
    run: "Lancer l’exemple",
    noscript: "Profil Épuré affiché. Activez JavaScript pour lancer l’exemple.",
    spoken: [
      "« ",
      { filler: "Euh," },
      " préviens Maya que je lui envoie le brouillon demain matin. ",
      { filler: "Et, euh," },
      " demande-lui si on peut décaler notre point à 14 h. »",
    ],
    examples: {
      clean:
        "Bonjour Maya, je t’envoie le brouillon demain matin. Pourrait-on décaler notre point à 14 h ?",
      concise:
        "Maya, brouillon demain matin. On peut décaler notre point à 14 h ?",
      summary:
        "Envoyer le brouillon à Maya demain matin. Demander à décaler le point à 14 h.",
    },
    stop: "Arrêter",
    again: "Relancer",
    placeholder: "Le texte apparaît ici quand vous relâchez.",
  },
  meetings: {
    title: "Vos réunions, transcrites sur votre Mac",
    intro:
      "Enregistrez un appel ou importez un fichier, puis obtenez une transcription avec les intervenants.",
    sample: "Exemple de transcription de réunion",
    meeting: "Revue de design",
    meta: "21 oct. · 32:14 · Whisper Large v3 Turbo",
    turns: [
      [1, "0:12", "On livre les changements de l’onboarding jeudi."],
      [2, "0:31", "Alors je mets à jour les captures avant la sortie."],
    ],
    points: [
      [
        "Enregistrez n’importe quelle app",
        "Une app ou le son de toutes, plus votre micro. Aucune vidéo de l’écran n’est gardée.",
      ],
      [
        "Ou importez un fichier",
        "Audio ou vidéo jusqu’à deux heures, avec une seule piste audio.",
      ],
      [
        "Intervenants estimés en local",
        "Des étiquettes d’intervenant facultatives, à renommer et réattribuer.",
      ],
      [
        "Local, sauf si vous choisissez le cloud",
        "Un modèle local garde l’audio ici ; Soniox n’envoie qu’après votre confirmation.",
      ],
      [
        "Modifiez, puis exportez",
        "L’original reste à côté de vos modifications. Export TXT, JSON, SRT ou VTT.",
      ],
    ],
    guide: "Lire le guide des réunions",
  },
  interface: {
    title: "Une interface qu’on a envie d’ouvrir",
    intro:
      "Touches en relief, creux enfoncés et sillons gravés, en clair comme en sombre.",
    alt: "La page Réglages d’Airdraft en mode clair : une barre latérale à côté de cartes en relief pour le micro et l’apparence, dont les six styles de la fenêtre d’enregistrement.",
    compare: "Comparer l’apparence claire et sombre",
    half: "Moitié clair, moitié sombre",
    allLight: "Tout clair",
    allDark: "Tout sombre",
    mixed: "{light} % clair, {dark} % sombre",
    materials: "Matières de la fenêtre",
    caption:
      "Rendu à partir de l’interface anglaise de l’app, avec l’accent Graphite.",
    unreleased:
      "La version publiée de l’app affiche encore l’interface en anglais ; les libellés cités ici sont ceux de sa traduction française.",
    drag: "Faites glisser pour comparer clair et sombre.",
    press: [
      "Des touches qui s’enfoncent",
      "Maintenez ⌃⌥ sur votre clavier pour les enfoncer.",
    ],
    select: [
      "Une sélection qui glisse",
      "Le creux bouge d’abord ; le socle de l’icône suit.",
    ],
    travel: [
      "Des commandes avec de la course",
      "Boutons et curseurs glissent dans leur rail.",
    ],
    keysLabel: "Control Option",
    callouts: {
      "Carved mark": ["Marque gravée", "Son onde est creusée."],
      "Pressed well": ["Creux enfoncé", "La page en cours s’enfonce."],
      "Raised button": [
        "Bouton en relief",
        "Les commandes se dressent pour être pressées.",
      ],
      "Raised card": [
        "Carte en relief",
        "Chaque section se détache de la page.",
      ],
      "Engraved divider": [
        "Séparateur gravé",
        "Les lignes sont séparées par un sillon.",
      ],
      "Reactive capsules": [
        "Capsules réactives",
        "Cinq styles suivent votre voix.",
      ],
    },
  },
  pipeline: {
    title: "Vous choisissez où tourne chaque étape",
    intro:
      "La reconnaissance vocale et l’affinage sont séparés. Choisissez local ou cloud pour chacun.",
    speech: "Parole",
    refinement: "Affinage",
    insertion: "Insertion",
    where: (stage) => `Où tourne l’étape ${stage.toLowerCase()}`,
    mac: "Ce Mac",
    cloud: "Cloud",
    plan: "Abonnement",
    speechMac: "L’audio ne quitte jamais votre Mac.",
    speechCloud: "L’audio part chez le fournisseur, avec votre propre clé API.",
    refinementMac:
      "Un modèle local met la transcription au propre. Elle reste ici.",
    refinementCloud: "La transcription part chez le fournisseur choisi.",
    refinementPlan: "Utilise le forfait Claude ou ChatGPT que vous payez déjà.",
    atCursor: "À votre curseur",
    insertionLine:
      "Votre vocabulaire corrige les noms en dernier. Puis le texte entre dans l’app où vous écrivez.",
    fix: ["Rendez-vous à", "à neuf heures."],
  },
  get: {
    title: "Obtenir Airdraft",
    intro:
      "Gratuit à compiler depuis le code source, ou une licence à achat unique pour l’app prête à l’emploi.",
    notOnSale: "L’app officielle n’est pas encore en vente.",
    build: "Compilez-la vous-même",
    free: "Gratuit",
    note: "Toutes les fonctions. Nécessite Xcode sur un Mac à puce Apple.",
    action: "Instructions de compilation",
  },
  license: {
    title: "App prête à l’emploi",
    count: "Nombre de Mac",
    once: "achat unique",
    use: (macs) => `Usage personnel sur ${macs}.`,
    rest: " Toutes les fonctions, avec d’abord un essai de 14 jours.",
    restNotOnSale:
      " Toutes les fonctions, avec un essai de 14 jours dès sa mise en vente.",
    see: "Voir les tarifs",
    plans: {
      "one-mac": { name: "1 Mac", title: "Un Mac", macs: "un Mac" },
      "three-macs": {
        name: "3 Mac",
        title: "Trois Mac",
        macs: "trois Mac au plus",
      },
    },
  },
  guideLinks: { read: "Lire le guide", readLabel: "Lire le guide : " },
  pricing: {
    title: "Tarifs — Airdraft",
    description:
      "Airdraft se compile gratuitement depuis le code source. L’app prête à l’emploi est une licence à achat unique : 29 $ US pour un Mac ou 49 $ US pour trois au plus.",
    heading: "Tarifs",
    intro:
      "Compilez-la gratuitement, ou achetez une fois l’app prête à l’emploi.",
    source: "Open source",
    build: "Compilez-la vous-même",
    buildAction: "Instructions de compilation",
    sourceList: "La version compilée depuis le code inclut",
    sourceIncludes: [
      "Dictée et Réunions",
      "Toutes les fonctions, rien de verrouillé",
      "Xcode nécessaire pour compiler",
    ],
    app: "App prête à l’emploi",
    once: "achat unique",
    buy: (macs) => `Acheter pour ${macs}`,
    notOnSale: "Pas encore en vente",
    appList: "Chaque licence inclut",
    licenseIncludes: [
      "Dictée et Réunions",
      "Toutes les fonctions, sans Xcode",
      "Essai complet de 14 jours",
      "Mises à jour de la version achetée",
      "Transfert entre Mac par vous-même",
    ],
    currency: "Dollars américains, hors taxes.",
    costTitle: "Ce que coûte une année de dictée",
    costIntro: (count) =>
      `Les mêmes ${count} dictées par mois, de cinq façons.`,
    columns: ["Configuration", "Par mois", "Première année", "Trois ans"],
    groups: ["Airdraft", "Abonnements"],
    rows: {
      local: { name: "Tout en local", detail: "Rien ne quitte votre Mac" },
      "local-cerebras": {
        name: "Parole locale + Cerebras",
        detail: "Les transcriptions partent chez Cerebras",
      },
      "groq-cerebras": {
        name: "Groq + Cerebras",
        detail: "Audio chez Groq, transcriptions chez Cerebras",
      },
      wispr: { name: "Wispr Flow Pro", detail: "Facturé à l’année" },
      typeless: { name: "Typeless Pro", detail: "Facturé à l’année" },
    },
    note: ({ checked, perDay, seconds, inputTokens, outputTokens }) =>
      `${perDay} dictées par jour ouvré, de ${seconds} secondes chacune, avec la licence un Mac. Parole : Parakeet ou Groq Whisper Large v3 Turbo. Affinage : Apple Intelligence, LM Studio ou Qwen 3.8 27B sur Cerebras (${inputTokens} tokens en entrée, ${outputTokens} en sortie). Prix catalogue, ${checked}.`,
    checked: monthYear("fr"),
    questions: "Questions",
    faq: {
      subscription: [
        "Est-ce un abonnement ?",
        [
          "Non. Une licence s’achète une fois et n’expire pas. Les mises à jour de la version achetée sont incluses.",
        ],
      ],
      licenses: [
        "Quelle différence entre les licences ?",
        [
          "Seulement le nombre de Mac qui peuvent l’utiliser en même temps. Pour transférer une licence, désactivez l’ancien Mac.",
        ],
      ],
      trial: [
        "Puis-je l’essayer d’abord ?",
        [
          "Oui. L’app propose un essai de 14 jours avec toutes les fonctions, qui démarre quand vous le décidez, pas à l’installation.",
        ],
      ],
      trialNotOnSale: [
        "Puis-je l’essayer d’abord ?",
        [
          "Une fois l’app officielle en vente, elle inclura un essai de 14 jours avec toutes les fonctions, qui démarre quand vous le décidez, pas à l’installation. Elle n’est pas encore en vente : il n’y a donc pas d’essai à télécharger aujourd’hui. La version gratuite compilée depuis le code a déjà toutes les fonctions.",
        ],
      ],
      editions: [
        "Que contiennent les deux éditions ?",
        [
          "La même app : dictée dans n’importe quelle app, Réunions (enregistrez le son des apps et votre micro ou importez de l’audio et de la vidéo, avec étiquettes d’intervenant facultatives et export TXT, JSON, SRT ou VTT), profils, vocabulaire et historique. L’app officielle n’ajoute aucune fonction ; elle évite de compiler avec Xcode. Voir le ",
          { link: "meetingGuide", text: "guide des réunions" },
          ".",
        ],
      ],
      providers: [
        "Combien coûtent les fournisseurs cloud ?",
        [
          "Ils vous facturent directement, à l’usage, avec votre propre clé API gardée dans le trousseau. Les modèles locaux sont gratuits ; voyez ",
          { link: "offlineGuide", text: "lequel convient à votre langue" },
          ". Claude Code et Codex utilisent votre abonnement actuel ; voyez ",
          { link: "agentGuide", text: "la dictée vers les agents de code" },
          ".",
        ],
      ],
      compare: [
        "Comment se compare-t-elle aux autres apps ?",
        [
          "Voyez la ",
          {
            link: "comparison",
            text: "comparaison datée avec VoiceInk, Handy, Typeless et Dictée d’Apple",
          },
          ", y compris là où elles font mieux.",
        ],
      ],
    },
  },
};
