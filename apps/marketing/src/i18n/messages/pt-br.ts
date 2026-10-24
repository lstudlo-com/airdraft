import { monthYear } from "./format";
import type { Messages } from "./types";

// Brazilian Portuguese. App labels follow the translators' pt-BR catalog
// export (src/data/app.ts): ditado, refinamento, perfis, Ajustes.
export const ptBr: Messages = {
  gap: " ",
  english: " (inglês)",
  layout: {
    skip: "Pular para o conteúdo",
    rss: "Versões do Airdraft (em inglês)",
  },
  header: {
    pricing: "Preços",
    support: "Suporte",
    changelog: "Novidades",
    home: "Início do Airdraft",
    nav: "Navegação principal",
    github: "Airdraft no GitHub",
    source: "Código no GitHub",
    get: "Obter o Airdraft",
    menu: "Menu",
    language: "Idioma",
    homeOnly: "página inicial",
  },
  footer: {
    nav: "Rodapé",
    build: "Instruções de compilação",
    pricing: "Preços",
    guides: "Guias",
    support: "Suporte",
    donate: "Doar",
    changelog: "Novidades",
    rss: "RSS",
    privacy: "Privacidade",
    license: "Licença",
    languages: "Idiomas",
  },
  analytics: {
    title: "Análise opcional do site",
    body: "Ajude a gente a entender as visitas e quais recursos despertam interesse. Sem gravações nem texto digitado.",
    privacy: "Detalhes de privacidade",
    decline: "Recusar",
    allow: "Permitir análise",
  },
  home: {
    title: "Airdraft | Ditado no seu idioma e transcrição de reuniões no Mac",
    description:
      "O Airdraft é um app de código aberto para Mac que digita o que você fala em qualquer app, no seu idioma e com termos em inglês no meio, e transcreve reuniões. A fala e o refinamento rodam no seu Mac ou no seu próprio provedor. Compilar a partir do código é grátis.",
    headline: [
      "Fale no seu idioma,",
      "com termos em inglês.",
      "Transcreva suas reuniões.",
    ],
    headlineGap: " ",
    get: "Obter o Airdraft",
    source: "Ver o código",
    sample: "Testar o exemplo",
    facts: [
      "Código aberto",
      "No seu Mac ou no seu provedor",
      "macOS 15+ com Apple silicon",
    ],
    guidesTitle: "Escolha sua configuração",
    guidesIntro:
      "Ditado offline no seu idioma, chinês e inglês misturados, ditado no Claude Code e em terminais, local ou na nuvem, e reuniões. Os guias estão em inglês.",
    featuresTitle: "O que o Airdraft faz por você",
    spoken: "Hum, fala pra Maya que o, é, rascunho chega amanhã.",
    outputs: [
      "Fala pra Maya que o rascunho chega amanhã.",
      "Rascunho para a Maya amanhã.",
      "A Maya recebe o rascunho amanhã.",
    ],
    typed: "Oi, Maya, amanhã de manhã te mando o rascunho.",
    mixed: {
      kind: "languages",
      samples: [
        {
          lang: "pt-BR",
          sentence: "Antes da demo, troca a API key e faz push na main.",
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
        "Insere no cursor",
        "Em qualquer app em que você estiver digitando.",
      ],
      shortcut: ["Um atalho", "Segure ⌃⌥ ou grave o seu."],
      profiles: ["Perfis", "Quatro prontos. Reescreva qualquer um."],
      vocabulary: ["Seu vocabulário", "Ensine nomes e jargões uma vez só."],
      history: ["Histórico", "Pesquise, volte ao original, copie."],
      fallback: [
        "Nada se perde",
        "Se o refinamento falhar, entra o texto bruto.",
      ],
      privacy: [
        "Fica no seu Mac",
        "Com modelos locais, nada sai. As chaves ficam nas Chaves do macOS.",
      ],
      mixed: [
        "Seu idioma, com inglês no meio",
        "Misture termos em inglês e técnicos nas suas frases. O chinês pode sair em 繁體 ou 简体.",
      ],
      plan: [
        "Seu plano do Claude ou ChatGPT",
        "Claude Code ou Codex, sem chave de API.",
      ],
    },
    privacyArt: {
      mac: "Este Mac",
      speech: "Fala",
      refinement: "Refinamento",
      cloud: "Nuvem, se você quiser",
    },
  },
  preview: {
    name: "Ditado de exemplo",
    said: "O que você disse",
    inserts: "O que o Airdraft insere",
    picker: "Perfil de refinamento",
    run: "Rodar o exemplo",
    noscript:
      "Mostrando o perfil Limpo. Ative o JavaScript para rodar o exemplo.",
    spoken: [
      "“",
      { filler: "Hum," },
      " avisa a Maya que eu mando o rascunho amanhã de manhã. ",
      { filler: "E, é," },
      " pergunta se dá pra passar a nossa reunião para as duas.”",
    ],
    examples: {
      clean:
        "Oi, Maya, amanhã de manhã te mando o rascunho. Podemos passar a nossa reunião para as duas?",
      concise:
        "Maya, rascunho amanhã de manhã. Dá pra passar a reunião para as duas?",
      summary:
        "Mandar o rascunho para a Maya amanhã de manhã. Pedir para passar a reunião para as duas.",
    },
    stop: "Parar",
    again: "Rodar de novo",
    placeholder: "O texto aparece aqui quando você solta.",
  },
  meetings: {
    title: "Reuniões transcritas no seu Mac",
    intro:
      "Grave uma chamada ou importe um arquivo e transforme em uma transcrição com falantes.",
    sample: "Transcrição de reunião de exemplo",
    meeting: "Revisão de design",
    meta: "21 de out. · 32:14 · Whisper Large v3 Turbo",
    turns: [
      [1, "0:12", "Vamos lançar as mudanças do onboarding na quinta."],
      [2, "0:31", "Então eu atualizo as capturas antes do lançamento."],
    ],
    points: [
      [
        "Grave qualquer app",
        "Um app ou o áudio de todos, mais o seu microfone. Nenhum vídeo da tela é guardado.",
      ],
      [
        "Ou importe um arquivo",
        "Áudio ou vídeo de até duas horas, com uma faixa de áudio.",
      ],
      [
        "Falantes estimados localmente",
        "Rótulos de falante opcionais, que você pode renomear e reatribuir.",
      ],
      [
        "Local, a não ser que você escolha a nuvem",
        "Um modelo local mantém o áudio aqui; o Soniox só envia depois que você confirma.",
      ],
      [
        "Edite e exporte",
        "O original fica ao lado das suas edições. Exporte TXT, JSON, SRT ou VTT.",
      ],
    ],
    guide: "Ler o guia de reuniões",
  },
  interface: {
    title: "Uma interface que dá gosto de abrir",
    intro:
      "Teclas em relevo, cavidades afundadas e sulcos entalhados, no claro e no escuro.",
    alt: "A página de Ajustes do Airdraft no modo claro: uma barra lateral ao lado de cartões em relevo para o microfone e a aparência, com os seis estilos da janela de gravação.",
    compare: "Comparar aparência clara e escura",
    half: "Metade claro, metade escuro",
    allLight: "Tudo claro",
    allDark: "Tudo escuro",
    mixed: "{light}% claro, {dark}% escuro",
    materials: "Materiais da janela",
    caption:
      "Renderizada a partir da interface em inglês do app, com o destaque Graphite.",
    unreleased:
      "A versão publicada do app ainda mostra a interface em inglês; os rótulos citados aqui são os da tradução para o português.",
    drag: "Arraste para comparar claro e escuro.",
    press: ["Teclas que afundam", "Segure ⌃⌥ no seu teclado para afundá-las."],
    select: [
      "Seleção que desliza",
      "A cavidade se move primeiro; a base do ícone vem atrás.",
    ],
    travel: [
      "Controles com curso",
      "Botões e cursores deslizam dentro dos trilhos.",
    ],
    keysLabel: "Control Option",
    callouts: {
      "Carved mark": ["Marca entalhada", "A forma de onda é gravada."],
      "Pressed well": ["Cavidade afundada", "A página atual afunda."],
      "Raised button": [
        "Botão em relevo",
        "Os controles se levantam para o toque.",
      ],
      "Raised card": ["Cartão em relevo", "Cada seção se destaca da página."],
      "Engraved divider": [
        "Divisória gravada",
        "As linhas se separam por um sulco.",
      ],
      "Reactive capsules": [
        "Cápsulas que reagem",
        "Cinco estilos seguem a sua voz.",
      ],
    },
  },
  pipeline: {
    title: "Você escolhe onde cada etapa roda",
    intro:
      "A fala e o refinamento rodam separados. Escolha local ou nuvem para cada um.",
    speech: "Fala",
    refinement: "Refinamento",
    insertion: "Inserção",
    where: (stage) => `Onde roda: ${stage.toLowerCase()}`,
    mac: "Este Mac",
    cloud: "Nuvem",
    plan: "Assinatura",
    speechMac: "O áudio nunca sai do seu Mac.",
    speechCloud: "O áudio vai para o provedor, com a sua própria chave de API.",
    refinementMac: "Um modelo local organiza a transcrição. Ela fica aqui.",
    refinementCloud: "A transcrição vai para o provedor que você escolher.",
    refinementPlan: "Usa o plano do Claude ou ChatGPT que você já paga.",
    atCursor: "No seu cursor",
    insertionLine:
      "Seu vocabulário corrige os nomes por último. Depois o texto entra no app em que você está digitando.",
    fix: ["Te encontro em", "às nove."],
  },
  get: {
    title: "Obter o Airdraft",
    intro:
      "Grátis para compilar a partir do código, ou uma licença de pagamento único para o app pronto para usar.",
    notOnSale: "O app oficial ainda não está à venda.",
    build: "Compile você mesmo",
    free: "Grátis",
    note: "Todos os recursos. Precisa do Xcode em um Mac com Apple silicon.",
    action: "Instruções de compilação",
  },
  license: {
    title: "App pronto para usar",
    count: "Número de Macs",
    once: "pagamento único",
    use: (macs) => `Uso pessoal em ${macs}.`,
    rest: " Todos os recursos, com um teste de 14 dias antes.",
    restNotOnSale:
      " Todos os recursos, com um teste de 14 dias quando estiver à venda.",
    see: "Ver preços",
    plans: {
      "one-mac": { name: "1 Mac", title: "Um Mac", macs: "um Mac" },
      "three-macs": {
        name: "3 Macs",
        title: "Três Macs",
        macs: "até três Macs",
      },
    },
  },
  guideLinks: { read: "Ler o guia", readLabel: "Ler o guia: " },
  pricing: {
    title: "Preços — Airdraft",
    description:
      "O Airdraft é grátis para compilar a partir do código. O app pronto para usar é uma licença de pagamento único: US$ 29 para um Mac ou US$ 49 para até três.",
    heading: "Preços",
    intro: "Compile de graça ou compre o app pronto para usar uma vez só.",
    source: "Código aberto",
    build: "Compile você mesmo",
    buildAction: "Instruções de compilação",
    sourceList: "A versão compilada do código inclui",
    sourceIncludes: [
      "Ditado e Reuniões",
      "Todos os recursos, sem bloqueios",
      "Precisa do Xcode para compilar",
    ],
    app: "App pronto para usar",
    once: "pagamento único",
    buy: (macs) => `Comprar para ${macs}`,
    notOnSale: "Ainda não está à venda",
    appList: "Toda licença inclui",
    licenseIncludes: [
      "Ditado e Reuniões",
      "Todos os recursos, sem Xcode",
      "Teste completo de 14 dias",
      "Atualizações da versão que você comprar",
      "Transfira entre Macs você mesmo",
    ],
    currency: "Dólares americanos, sem impostos.",
    costTitle: "Quanto custa um ano de ditado",
    costIntro: (count) =>
      `Os mesmos ${count} ditados por mês, de cinco jeitos.`,
    columns: ["Configuração", "Por mês", "Primeiro ano", "Três anos"],
    groups: ["Airdraft", "Assinaturas"],
    rows: {
      local: { name: "Tudo local", detail: "Nada sai do seu Mac" },
      "local-cerebras": {
        name: "Fala local + Cerebras",
        detail: "As transcrições vão para a Cerebras",
      },
      "groq-cerebras": {
        name: "Groq + Cerebras",
        detail: "Áudio para a Groq, transcrições para a Cerebras",
      },
      wispr: { name: "Wispr Flow Pro", detail: "Cobrança anual" },
      typeless: { name: "Typeless Pro", detail: "Cobrança anual" },
    },
    note: ({ checked, perDay, seconds, inputTokens, outputTokens }) =>
      `${perDay} ditados por dia útil, de ${seconds} segundos cada, com a licença de um Mac. Fala: Parakeet ou Groq Whisper Large v3 Turbo. Refinamento: Apple Intelligence, LM Studio ou Qwen 3.8 27B na Cerebras (${inputTokens} tokens de entrada, ${outputTokens} de saída). Preços de tabela, ${checked}.`,
    checked: monthYear("pt-BR"),
    questions: "Perguntas",
    faq: {
      subscription: [
        "É uma assinatura?",
        [
          "Não. A licença é um pagamento único e não expira. As atualizações da versão que você comprar estão incluídas.",
        ],
      ],
      licenses: [
        "Qual é a diferença entre as licenças?",
        [
          "Só quantos Macs podem usar ao mesmo tempo. Para transferir uma licença, desative o Mac antigo.",
        ],
      ],
      trial: [
        "Posso testar antes?",
        [
          "Sim. O app tem um teste de 14 dias com todos os recursos, que começa quando você decidir, não na instalação.",
        ],
      ],
      trialNotOnSale: [
        "Posso testar antes?",
        [
          "Quando o app oficial estiver à venda, ele terá um teste de 14 dias com todos os recursos, que começa quando você decidir, não na instalação. Ele ainda não está à venda, então hoje não há teste para baixar. A versão grátis compilada do código já tem todos os recursos.",
        ],
      ],
      editions: [
        "O que as duas edições incluem?",
        [
          "O mesmo app: ditado em qualquer app, Reuniões (grave o áudio dos apps e o seu microfone ou importe áudio e vídeo, com rótulos de falante opcionais e exportação em TXT, JSON, SRT ou VTT), perfis, vocabulário e histórico. O app oficial não acrescenta recursos; ele poupa a compilação no Xcode. Veja o ",
          { link: "meetingGuide", text: "guia de reuniões" },
          ".",
        ],
      ],
      providers: [
        "Quanto custam os provedores na nuvem?",
        [
          "Eles cobram você diretamente, por uso, com a sua própria chave de API guardada nas Chaves do macOS. Os modelos locais são grátis; veja ",
          { link: "offlineGuide", text: "qual combina com o seu idioma" },
          ". O Claude Code e o Codex usam a sua assinatura atual; veja ",
          {
            link: "agentGuide",
            text: "como ditar para agentes de programação",
          },
          ".",
        ],
      ],
      compare: [
        "Como ele se compara com outros apps?",
        [
          "Veja a ",
          {
            link: "comparison",
            text: "comparação datada com VoiceInk, Handy, Typeless e o Ditado da Apple",
          },
          ", incluindo onde eles são melhores.",
        ],
      ],
    },
  },
};
