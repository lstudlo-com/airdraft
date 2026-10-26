import { monthYear } from "./format";
import type { Messages } from "./types";

// Spanish (neutral). App labels follow the app's es catalog (src/data/app.ts).
export const es: Messages = {
  gap: " ",
  layout: { skip: "Ir al contenido", rss: "Versiones de Airdraft" },
  header: {
    pricing: "Precios",
    support: "Ayuda",
    changelog: "Novedades",
    home: "Inicio de Airdraft",
    nav: "Navegación principal",
    github: "Airdraft en GitHub",
    source: "Código en GitHub",
    get: "Obtener Airdraft",
    menu: "Menú",
    language: "Idioma",
  },
  footer: {
    nav: "Pie de página",
    build: "Instrucciones de compilación",
    pricing: "Precios",
    guides: "Guías",
    support: "Ayuda",
    changelog: "Novedades",
    rss: "RSS",
    privacy: "Privacidad",
    license: "Licencia",
  },
  analytics: {
    title: "Analítica web opcional",
    body: "Ayúdanos a entender las visitas y qué funciones interesan. Sin grabaciones ni texto escrito.",
    privacy: "Detalles de privacidad",
    decline: "Rechazar",
    allow: "Permitir analítica",
  },
  home: {
    title: "Airdraft | Dictado en tu idioma y transcripción de audio para Mac",
    description:
      "Airdraft es una app de código abierto para Mac que escribe lo que dices en cualquier app, en tu idioma y con términos en inglés de por medio, y transcribe grabaciones y archivos de audio o vídeo. La voz y el refinamiento funcionan en tu Mac o con tu propio proveedor. Compilarla desde el código es gratis.",
    headline: ["Habla en cualquier app.", "Transcribe lo que sea."],
    headlineGap: " ",
    get: "Obtener Airdraft",
    source: "Ver el código",
    sample: "Probar el ejemplo",
    facts: [
      "Código abierto",
      "En tu Mac o con tu propio proveedor",
      "macOS 15+ con Apple silicon",
    ],
    guidesTitle: "Guías de configuración",
    featuresTitle: "Lo que Airdraft hace por ti",
    spoken: "Eh, dile a Maya que el, este, borrador llega mañana.",
    outputs: [
      "Dile a Maya que el borrador llega mañana.",
      "Borrador para Maya, mañana.",
      "Maya recibe el borrador mañana.",
    ],
    typed: "Hola, Maya: mañana por la mañana te envío el borrador.",
    mixed: {
      kind: "languages",
      samples: [
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
        {
          lang: "fr",
          sentence: "Avant la démo, change l’API key et fais un push sur main.",
        },
      ],
    },
    tiles: {
      cursor: [
        "Se inserta en el cursor",
        "En la app en la que estés escribiendo.",
      ],
      shortcut: ["Un atajo", "Mantén pulsado ⌃⌥ o graba el tuyo."],
      profiles: ["Perfiles", "Cuatro incluidos, todos editables."],
      vocabulary: ["Vocabulario", "Enséñale nombres y jerga una sola vez."],
      history: ["Historial", "Busca, vuelve al original y copia."],
      fallback: [
        "No se pierde nada",
        "Si el refinamiento falla, se inserta el texto sin refinar.",
      ],
      privacy: [
        "Se queda en tu Mac",
        "Los modelos locales no envían nada; las claves quedan en el Llavero.",
      ],
      mixed: [
        "Tu idioma, con inglés de por medio",
        "Mezcla términos en inglés y técnicos en tus frases. El chino puede salir en 繁體 o 简体.",
      ],
      plan: [
        "Tu plan de Claude o ChatGPT",
        "Claude Code o Codex, sin clave de API.",
      ],
    },
    privacyArt: {
      mac: "Este Mac",
      speech: "Voz",
      refinement: "Refinamiento",
      cloud: "Nube, si lo eliges",
    },
  },
  preview: {
    name: "Dictado de ejemplo",
    said: "Lo que dijiste",
    inserts: "Lo que inserta Airdraft",
    picker: "Perfil de refinamiento",
    run: "Reproducir ejemplo",
    noscript:
      "Se muestra el perfil Limpio. Activa JavaScript para reproducir el ejemplo.",
    spoken: [
      "«",
      { filler: "Eh," },
      " avísale a Maya que mañana por la mañana le mando el borrador. ",
      { filler: "Y, este," },
      " pregúntale si podemos pasar la reunión a las dos».",
    ],
    examples: {
      clean:
        "Hola, Maya: mañana por la mañana te envío el borrador. ¿Podemos pasar la reunión a las dos?",
      concise:
        "Maya, mañana por la mañana te mando el borrador. ¿Pasamos la reunión a las dos?",
      summary:
        "Enviar a Maya el borrador mañana por la mañana. Pedir pasar la reunión a las dos.",
    },
    stop: "Detener",
    again: "Repetir",
    placeholder: "El texto aparece aquí cuando sueltas.",
  },
  meetings: {
    title: "Transcribe audio y vídeo en tu Mac",
    intro:
      "Graba una llamada, una clase o el audio de cualquier app, o importa un archivo, y obtén una transcripción con hablantes.",
    sample: "Transcripción de ejemplo",
    meeting: "Revisión de diseño",
    meta: "21 oct · 32:14 · Whisper Large v3 Turbo",
    turns: [
      [1, "0:12", "Publiquemos los cambios del onboarding el jueves."],
      [2, "0:31", "Entonces actualizo las capturas antes del lanzamiento."],
    ],
    points: [
      [
        "Graba cualquier app",
        "Una app o todas, y tu micrófono si quieres. Sin vídeo de la pantalla.",
      ],
      [
        "O importa un archivo",
        "Audio o vídeo de hasta dos horas, con una pista de audio.",
      ],
      [
        "Hablantes, estimados en local",
        "Etiquetas de hablante opcionales que puedes renombrar y reasignar.",
      ],
      [
        "Local, salvo que elijas la nube",
        "Un modelo local deja el audio aquí; Soniox lo sube solo después de que confirmes.",
      ],
      [
        "Edita, resume y exporta",
        "Conserva el original junto a tus cambios, añade un resumen o las tareas pendientes y exporta TXT, JSON, SRT o VTT.",
      ],
    ],
    guide: "Leer la guía de reuniones",
  },
  interface: {
    title: "Una interfaz que da gusto abrir",
    intro:
      "Teclas en relieve, huecos hundidos y surcos tallados, en claro y en oscuro.",
    alt: "La página de ajustes de Airdraft en modo claro: una barra lateral junto a tarjetas en relieve para el micrófono y la apariencia, con los seis estilos de la ventana de grabación.",
    compare: "Comparar la apariencia clara y oscura",
    half: "Mitad claro, mitad oscuro",
    allLight: "Todo claro",
    allDark: "Todo oscuro",
    mixed: "{light} % claro, {dark} % oscuro",
    materials: "Materiales de la ventana",
    caption: "Captura real de la app en español, con el acento Graphite.",
    drag: "Arrastra para comparar claro y oscuro.",
    press: [
      "Teclas que se hunden",
      "Mantén pulsado ⌃⌥ en tu teclado para hundirlas.",
    ],
    select: [
      "Una selección que se desliza",
      "Primero se mueve el hueco; la base del icono lo sigue.",
    ],
    travel: [
      "Controles con recorrido",
      "Perillas y deslizadores se mueven dentro de su carril.",
    ],
    keysLabel: "Control Option",
    callouts: {
      "Carved mark": ["Marca tallada", "Su onda está grabada."],
      "Pressed well": ["Hueco hundido", "La página actual se hunde."],
      "Raised button": [
        "Botón en relieve",
        "Los controles sobresalen para pulsarlos.",
      ],
      "Raised card": [
        "Tarjeta en relieve",
        "Cada sección se eleva de la página.",
      ],
      "Engraved divider": [
        "Divisor grabado",
        "Las filas se separan con un surco.",
      ],
      "Reactive capsules": [
        "Cápsulas que reaccionan",
        "Cinco estilos siguen tu voz.",
      ],
    },
  },
  pipeline: {
    title: "Tú eliges dónde se ejecuta cada paso",
    intro:
      "La voz y el refinamiento se ejecutan por separado. Elige local o nube para cada uno.",
    speech: "Voz",
    refinement: "Refinamiento",
    insertion: "Inserción",
    where: (stage) => `Dónde se ejecuta: ${stage.toLowerCase()}`,
    mac: "Este Mac",
    cloud: "Nube",
    plan: "Suscripción",
    speechMac: "El audio nunca sale de tu Mac.",
    speechCloud: "El audio va al proveedor, con tu propia clave de API.",
    refinementMac: "Un modelo local limpia la transcripción. Se queda aquí.",
    refinementCloud: "La transcripción va al proveedor que elijas.",
    refinementPlan: "Usa el plan de Claude o ChatGPT que ya pagas.",
    atCursor: "En tu cursor",
    insertionLine:
      "El vocabulario corrige los nombres al final y luego el texto entra en la app en la que escribes.",
    fix: ["Nos vemos en", "a las nueve."],
  },
  get: {
    title: "Obtener Airdraft",
    intro:
      "Gratis si la compilas desde el código, o una licencia de pago único para la app lista para usar.",
    notOnSale: "La app oficial aún no está a la venta.",
    build: "Compílala tú",
    free: "Gratis",
    note: "Todas las funciones. Necesita Xcode en un Mac con Apple silicon.",
    action: "Instrucciones de compilación",
  },
  license: {
    title: "App lista para usar",
    count: "Número de Macs",
    once: "pago único",
    use: (macs) => `Uso personal en ${macs}.`,
    rest: " Todas las funciones, con una prueba de 14 días primero.",
    restNotOnSale:
      " Todas las funciones, con una prueba de 14 días cuando salga a la venta.",
    see: "Ver precios",
    plans: {
      "one-mac": { name: "1 Mac", title: "Un Mac", macs: "un Mac" },
      "three-macs": {
        name: "3 Macs",
        title: "Tres Macs",
        macs: "hasta tres Macs",
      },
    },
  },
  guideLinks: {
    labels: {
      "offline-dictation-on-mac": "Dictado sin conexión",
      "mixed-chinese-english-dictation": "Chino e inglés mezclados",
      "dictate-to-claude-code-and-terminals": "Claude\u00a0Code, Codex",
      "local-vs-cloud-dictation": "Local o en la nube",
      "free-source-or-official-app": "Gratis o app oficial",
      "private-meeting-transcription": "Reuniones en privado",
      "compare-mac-dictation-apps": "Compara Airdraft",
    },
  },
  pricing: {
    title: "Precios — Airdraft",
    description:
      "Airdraft se compila gratis desde el código. La app lista para usar es una licencia de pago único: 29 US$ para un Mac o 49 US$ para hasta tres.",
    heading: "Precios",
    intro: "Compílala gratis o compra la app lista para usar una sola vez.",
    source: "Código abierto",
    build: "Compílala tú",
    buildAction: "Instrucciones de compilación",
    sourceList: "La versión compilada desde el código incluye",
    sourceIncludes: [
      "Dictado y transcripción",
      "Todas las funciones, sin bloqueos",
      "Necesita Xcode para compilar",
    ],
    app: "App lista para usar",
    once: "pago único",
    buy: (macs) => `Comprar para ${macs}`,
    notOnSale: "Aún no está a la venta",
    appList: "Toda licencia incluye",
    licenseIncludes: [
      "Dictado y transcripción",
      "Todas las funciones, sin Xcode",
      "Prueba de 14 días con todo",
      "Actualizaciones de la versión que compras",
      "Muévela entre Macs tú mismo",
    ],
    currency: "Dólares estadounidenses, impuestos aparte.",
    costTitle: "Lo que cuesta un año de dictado",
    costIntro: (count) =>
      `Los mismos ${count} dictados al mes, de cinco formas.`,
    columns: ["Configuración", "Al mes", "Primer año", "Tres años"],
    groups: ["Airdraft", "Suscripciones"],
    rows: {
      local: { name: "Todo local", detail: "Nada sale de tu Mac" },
      "local-cerebras": {
        name: "Voz local + Cerebras",
        detail: "Las transcripciones van a Cerebras",
      },
      "groq-cerebras": {
        name: "Groq + Cerebras",
        detail: "Audio a Groq, transcripciones a Cerebras",
      },
      wispr: { name: "Wispr Flow Pro", detail: "Facturación anual" },
      typeless: { name: "Typeless Pro", detail: "Facturación anual" },
    },
    note: ({ checked, perDay, seconds, inputTokens, outputTokens }) =>
      `${perDay} dictados por día laborable, de ${seconds} segundos cada uno, con la licencia de un Mac. Voz: Parakeet o Groq Whisper Large v3 Turbo. Refinamiento: Apple Intelligence, LM Studio o Qwen 3.8 27B en Cerebras (${inputTokens} tokens de entrada, ${outputTokens} de salida). Precios de lista, ${checked}.`,
    checked: monthYear("es"),
    questions: "Preguntas",
    faq: {
      subscription: [
        "¿Es una suscripción?",
        [
          "No. Una licencia es un pago único y no caduca. Incluye las actualizaciones de la versión que compras.",
        ],
      ],
      licenses: [
        "¿En qué se diferencian las licencias?",
        [
          "Solo en cuántos Macs pueden usarla a la vez. Para mover una licencia, desactiva el Mac anterior.",
        ],
      ],
      trial: [
        "¿Puedo probarla antes?",
        [
          "Sí. La app tiene una prueba de 14 días con todas las funciones, que empieza cuando tú decides, no al instalarla.",
        ],
      ],
      trialNotOnSale: [
        "¿Puedo probarla antes?",
        [
          "Cuando la app oficial salga a la venta, incluirá una prueba de 14 días con todas las funciones, que empieza cuando tú decides, no al instalarla. Aún no está a la venta, así que no hay prueba para descargar; la versión gratuita compilada desde el código ya tiene todas las funciones.",
        ],
      ],
      editions: [
        "¿Qué incluyen las dos ediciones?",
        [
          "La misma app: dictado en cualquier app, «Transcribir» (graba el audio de las apps y tu micrófono o importa audio y vídeo, con etiquetas de hablante opcionales, resúmenes y exportación a TXT, JSON, SRT o VTT), perfiles, vocabulario e historial. La app oficial no añade funciones; te ahorra compilar con Xcode. Consulta la ",
          { link: "meetingGuide", text: "guía de reuniones" },
          ".",
        ],
      ],
      providers: [
        "¿Cuánto cuestan los proveedores en la nube?",
        [
          "Te cobran directamente, por uso, con tu propia clave de API guardada en el Llavero. Los modelos locales son gratis; consulta ",
          { link: "offlineGuide", text: "cuál encaja con tu idioma" },
          ". Claude Code y Codex usan tu suscripción actual; consulta ",
          { link: "agentGuide", text: "cómo dictar a agentes de programación" },
          ".",
        ],
      ],
      compare: [
        "¿Cómo se compara con otras apps?",
        [
          "Consulta la ",
          {
            link: "comparison",
            text: "comparación fechada con VoiceInk, Handy, Typeless y el Dictado de Apple",
          },
          ", que incluye en qué son mejores.",
        ],
      ],
    },
  },
};
