import type { PageCopy } from "../types";

export const es: PageCopy = {
  chrome: {
    breadcrumb: "Ruta de navegación",
    home: "Inicio",
    guides: "Guías",
    related: "Guías relacionadas",
  },
  notFound: {
    title: "Página no encontrada — Airdraft",
    heading: "Esta página no existe",
    action: "Ir a la página de inicio",
  },
  hub: {
    title: "Guías de dictado y modelos para Mac | Airdraft",
    description:
      "Guías prácticas de Airdraft: dictado sin conexión en tu Mac en tu idioma, chino e inglés mezclados, dictado en Claude Code y terminales, modelos locales y en la nube, transcripción privada de reuniones, comparación con otras apps y la versión gratuita desde el código o la app oficial.",
    heading: "Guías de dictado",
    help: [
      "¿Ya lo tienes configurado y algo falla?",
      "Revisa permisos, atajos y problemas habituales.",
    ],
    pricing: "Comparar precios",
    changes: "Ver novedades",
  },
  support: {
    title: "Ayuda — Airdraft",
    description:
      "Soluciona problemas habituales de Airdraft con permisos, atajos y modelos, o informa de un error.",
    heading: "Ayuda",
  },
  privacy: {
    title: "Privacidad | Airdraft",
    description:
      "Cómo trata Airdraft los datos de dictado, los datos de uso opcionales de la app y la analítica web, y cómo cambiar cada elección.",
    heading: "Privacidad",
  },
  changelog: {
    title: "Novedades — Airdraft",
    description:
      "Historial de versiones de Airdraft, desde la primera compilación del código hasta los modelos de voz por perfil, la inteligencia local y una nueva interfaz nativa.",
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
        "Configura Airdraft con reconocimiento de voz local y limpieza opcional con IA local. Requisitos del Mac, qué modelo elegir, la medición propia de Airdraft en inglés, japonés y coreano, permisos y perfiles.",
      summary:
        "Elige un modelo de voz para tu idioma, mantén la limpieza en local y haz tu primer dictado.",
    },
    "mixed-chinese-english-dictation": {
      title: "Dicta chino e inglés mezclados en un Mac",
      description:
        "Elige un modelo de voz local para frases que mezclan mandarín y términos en inglés. La medición propia de Airdraft compara errores, términos en inglés conservados, tamaño, memoria y velocidad.",
      summary:
        "Elige un modelo local para mandarín e inglés mezclados, con las ventajas y desventajas que midió Airdraft.",
    },
    "dictate-to-claude-code-and-terminals": {
      title: "Dicta prompts en Claude Code, Codex y terminales",
      description:
        "Dicta prompts en Claude Code, Codex y apps de terminal en un Mac. Cómo funciona el pegado en terminales que dibujan su propio texto, el refinamiento con tu plan actual y qué sale de tu Mac.",
      summary:
        "Dicta prompts a agentes de programación y terminales, y refínalos con el plan que ya pagas.",
    },
    "local-vs-cloud-dictation": {
      title: "Elige entre dictado local o en la nube",
      description:
        "Compara las opciones locales y en la nube de Airdraft para la voz y el refinamiento. Mira adónde van el audio, las transcripciones y el contexto de la app que actives antes de elegir.",
      summary:
        "Mira adónde van tu audio y tu texto con cada combinación de modelos.",
    },
    "free-source-or-official-app": {
      title: "Elige entre la versión gratuita desde el código o la app oficial",
      description:
        "Compara la versión completa y gratuita de Airdraft compilada desde el código con la licencia de pago único de la app oficial: instalación, actualizaciones, límite de Macs y disponibilidad actual.",
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
      description:
        "Comparación fechada de Airdraft, VoiceInk, Handy, Typeless y el Dictado de Apple en macOS 27: precio, código, dónde se procesa la voz, transcripción de grabaciones y archivos, y en qué es mejor cada uno.",
      summary:
        "Compara precios, flujo de datos y transcripción de grabaciones, incluido en qué son mejores los demás.",
    },
  },
};
