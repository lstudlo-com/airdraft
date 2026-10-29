import type { PageCopy } from "../types";

export const es: PageCopy = {
  chrome: {
    breadcrumb: "Ruta de navegación",
    home: "Inicio",
    guides: "Guías",
    related: "Guías relacionadas",
    onThisPage: "En esta página",
  },
  notFound: {
    title: "Página no encontrada | Airdraft",
    heading: "Esta página no existe",
    action: "Ir a la página de inicio",
  },
  hub: {
    title: "Guías de dictado y modelos para Mac | Airdraft",
    description:
      "Guías de Airdraft: dictado sin conexión, chino e inglés mezclados, agentes de código, modelos locales o en la nube, transcripción privada y comparaciones.",
    heading: "Guías de dictado",
    help: [
      "¿Ya lo tienes configurado y algo falla?",
      "Revisa permisos, atajos y problemas habituales.",
    ],
    pricing: "Comparar precios",
    changes: "Ver novedades",
  },
  support: {
    title: "Ayuda de Airdraft: permisos, atajos y modelos",
    description:
      "Soluciona problemas habituales de Airdraft con permisos, atajos y modelos, o informa de un error.",
    heading: "Ayuda",
  },
  privacy: {
    title: "Privacidad de Airdraft: lo que se queda en tu Mac",
    description:
      "Cómo trata Airdraft los datos de dictado, los datos de uso opcionales de la app y la analítica web, y cómo cambiar cada elección.",
    heading: "Privacidad",
  },
  changelog: {
    title: "Novedades de Airdraft: todas las versiones",
    description:
      "Historial de versiones de Airdraft, desde la primera compilación hasta los modelos de voz por perfil, la inteligencia local y la nueva interfaz nativa.",
    heading: "Novedades",
    nav: "Versiones publicadas",
    latest: "Versión más reciente",
    source: "Código",
    releaseNotes: "Notas de la versión",
    initialSource: "Código inicial",
    sourceFor: (label, version) =>
      /^\d/.test(version) ? `${label} ${version}` : `${label} de ${version}`,
    firstBuild: "la primera versión",
    availability: [
      "Los instaladores publicados son compilaciones de uso personal firmadas con Apple Development, sin notarizar. Consulta las ",
      "instrucciones de instalación",
      ".",
    ],
  },
  guides: {
    "offline-dictation-on-mac": {
      title: "Configura el dictado sin conexión en tu Mac",
      description:
        "Configura Airdraft con voz local y limpieza opcional con IA local: requisitos del Mac, qué modelo elegir, permisos y perfiles.",
      summary:
        "Elige un modelo de voz para tu idioma, mantén la limpieza en local y haz tu primer dictado.",
    },
    "mixed-chinese-english-dictation": {
      title: "Dicta chino e inglés mezclados en un Mac",
      description:
        "Elige un modelo de voz local para mandarín con términos en inglés, con la medición propia de Airdraft de errores, términos, tamaño, memoria y velocidad.",
      summary:
        "Elige un modelo local para mandarín e inglés mezclados, con las ventajas y desventajas que midió Airdraft.",
    },
    "dictate-to-claude-code-and-terminals": {
      title: "Dicta prompts en Claude Code, Codex y terminales",
      description:
        "Dicta prompts en Claude Code, Codex y terminales en un Mac: cómo se pega en terminales que dibujan su texto, el refinamiento con tu plan y qué sale del Mac.",
      summary:
        "Dicta prompts a agentes de programación y terminales, y refínalos con el plan que ya pagas.",
    },
    "local-vs-cloud-dictation": {
      title: "Elige entre dictado local o en la nube",
      description:
        "Compara la voz y el refinamiento locales o en la nube de Airdraft, y mira adónde van el audio, las transcripciones y el contexto antes de elegir.",
      summary:
        "Mira adónde van tu audio y tu texto con cada combinación de modelos.",
    },
    "free-source-or-official-app": {
      title: "Elige entre la versión gratuita desde el código o la app oficial",
      metaTitle: "Versión gratuita desde el código o app oficial | Airdraft",
      description:
        "Compara la versión gratuita y completa compilada desde el código con la licencia única de la app oficial: instalación, actualizaciones, Macs y disponibilidad.",
      summary:
        "Compara instalación, actualizaciones y condiciones de la licencia, incluido lo que está disponible ahora.",
    },
    "private-meeting-transcription": {
      title: "Transcribe reuniones en privado en tu Mac",
      description:
        "En «Transcribir», graba el audio de una reunión y tu micrófono o importa un archivo, y transcríbelo en tu Mac con etiquetas de hablante opcionales.",
      summary:
        "Graba una llamada o importa un archivo, etiqueta a los hablantes y exporta subtítulos.",
    },
    "compare-mac-dictation-apps": {
      title:
        "Compara Airdraft con VoiceInk, Handy, Typeless y el Dictado de Apple",
      metaTitle: "Airdraft vs. VoiceInk, Handy, Typeless y Dictado de Apple",
      description:
        "Comparación fechada de Airdraft, VoiceInk, Handy, Typeless y el Dictado de Apple: precio, código, dónde se procesa la voz y en qué es mejor cada uno.",
      summary:
        "Compara precios, flujo de datos y transcripción de grabaciones, incluido en qué son mejores los demás.",
    },
  },
};
