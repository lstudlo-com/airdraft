import type { ChangelogText } from "../../data/changelog";

// One entry per release id in src/data/changelog.ts, with the same number of
// changes in the same order.
export const changelog: ChangelogText = {
  "0-16-0": {
    title: "Texto en directo a tu gusto y una sola lista de modelos de voz",
    changes: [
      {
        title: "Elige cómo se ve el texto en directo",
        description:
          "«Ajustes» > «Vista previa en directo» ofrece cinco estilos («Cristal», «Sólido», «Escarcha», «Subtítulo» y «Solo texto»), de una a cuatro líneas y tres tamaños de texto, cada uno con su vista previa.",
      },
      {
        title: "Mira qué modelos muestran texto en directo",
        description:
          "Los modelos locales que pueden mostrar texto mientras hablas llevan la etiqueta «Texto en directo» en «Modelos».",
      },
      {
        title: "Una sola lista de modelos de voz",
        description:
          "«Modelos» reúne la voz local y en la nube en una sección, «Modelos de voz»: elige «En este Mac» o «Nube» y luego el proveedor. Al elegir un proveedor local se muestran todos sus modelos.",
      },
      {
        title: "Un aviso más breve",
        description:
          "Si el modelo elegido no puede mostrar texto en directo, la ventana de grabación lo dice en una línea durante 1,2 segundos, una vez por perfil y modelo.",
      },
    ],
  },
  "0-15-0": {
    title: "Enviar tras pegar, palabras señaladas y atajos de perfil",
    changes: [
      {
        title: "Pulsa Retorno cuando el texto ya está pegado",
        description:
          "Mantén Mayúsculas mientras grabas, o activa «Enviar automáticamente» en un perfil que uses con chats y agentes de IA, y Airdraft pulsa Retorno una vez cuando el campo original confirma el texto pegado. El envío automático no se hace en navegadores, correo ni apps de chat, el correo nunca se envía, y Esc durante la breve espera deja el texto sin enviar.",
      },
      {
        title: "Palabras que conviene revisar",
        description:
          "Si el refinamiento cambia un número o una negación, añade un nombre o escribe algo con aspecto de código que no está en tu «Vocabulario», Airdraft pega el texto pero no lo envía, y la ventana de grabación muestra hasta tres de esas palabras.",
      },
      {
        title: "Perfiles que copian o escriben en un archivo",
        description:
          "Un perfil puede «Insertar en el cursor», «Solo copiar» o «Añadir a un archivo» cada dictado como una línea, con {date}, {time} y {app} en la línea.",
      },
      {
        title: "Atajos de perfil y de edición",
        description:
          "Hasta dos perfiles pueden tener su propio atajo, y el atajo de edición reescribe el texto seleccionado con tu voz.",
      },
    ],
  },
  "0-14-1": {
    title: "Una ventana de texto en directo más ligera",
    changes: [
      {
        title: "Texto en directo translúcido",
        description:
          "La ventana de texto en directo sobre la cápsula de grabación es ahora una tarjeta compacta de cristal ahumado: una línea hasta que el texto se ajusta y luego las dos líneas más recientes. Con «Reducir transparencia» es opaca.",
      },
      {
        title: "Un aviso breve en su lugar",
        description:
          "Los modelos que no pueden mostrar texto en directo ya no abren la ventana; un aviso breve nombra el modelo mientras la grabación continúa.",
      },
    ],
  },
  "0-14-0": {
    title: "Español, japonés y mejores valores predeterminados en cada idioma",
    changes: [
      {
        title: "Usa Airdraft en español o japonés",
        description:
          "La interfaz, los menús nativos y las frases de Atajos de Apple están disponibles en español y japonés, según el idioma de tu Mac. Las instrucciones de los atajos son frases completas en cada idioma, y los controles se ensanchan para que quepan etiquetas más largas.",
      },
      {
        title: "Valores predeterminados adaptados a tu idioma",
        description:
          "Una configuración nueva en un Mac sin chino ya no empieza con la escritura china tradicional ni con una configuración regional de Taiwán para Apple Speech; el ajuste de escritura china solo se aplica al mandarín y al cantonés, y solo aparece con ellos. La vista previa en directo muestra todos los idiomas que admite tu Mac.",
      },
      {
        title: "Modelos locales recomendados para siete idiomas más",
        description:
          "La configuración inicial y Modelos recomiendan según la medición propia de Airdraft en español, francés, portugués, ruso, árabe, hindi e indonesio: Qwen3-ASR 1.7B, con opciones más ligeras en Macs con 8 GB de memoria o menos (Parakeet TDT v3, GigaAM v3 o Whisper Large v3 Turbo, según el idioma).",
      },
      {
        title: "El refinamiento respeta tu idioma",
        description:
          "Si el refinamiento cambia el idioma en el que hablaste, en cualquier escritura, se descarta y se usa la transcripción sin procesar. Los dictados en tailandés, lao, jemer y birmano ya no se omiten por demasiado cortos, y la configuración ya no ofrece Apple Intelligence para un idioma que no puede escribir.",
      },
    ],
  },
  "0-13-0": {
    title: "Datos de uso anónimos e informes de fallos opcionales",
    changes: [
      {
        title: "Elige si compartes datos de uso anónimos",
        description:
          "Las descargas de airdraft.app preguntan una vez si quieres compartir recuentos de uso anónimos e informes de fallos, con la lista de lo que se comparte y lo que nunca se comparte. No se envía nada antes de que elijas, puedes desactivarlo cuando quieras en Ajustes > Comportamiento, y las versiones compiladas desde el código nunca envían nada. Nunca se envían tus palabras, transcripciones, audio, vocabulario, nombres de apps, títulos de ventana, URL, rutas de archivo ni claves.",
      },
      {
        title: "Texto en directo de Apple Speech como modelo seleccionado",
        description:
          "Cuando Apple Speech es tu modelo de voz y la vista previa en directo usa el modelo seleccionado, el texto en directo aparece ahora en la ventana de grabación y durante las reuniones.",
      },
    ],
  },
  "0-12-1": {
    title: "Inserción más estable en Macs ocupados",
    changes: [
      {
        title: "Confirma el destino de forma más fiable",
        description:
          "Antes de grabar, Airdraft comprueba que el campo de texto y el cursor han dejado de cambiar. Ahora también los lee dos veces seguidas, para que un Mac lento u ocupado no acepte un campo que aún se mueve y luego informe de que el destino cambió.",
      },
    ],
  },
  "0-12-0": {
    title: "Perfiles según la app, texto en directo y chino simplificado",
    changes: [
      {
        title: "Elige un perfil para cada app",
        description:
          "Perfiles > Perfil según la app asigna una app, o una familia como editores de código, terminales, correo, chat o documentos, a uno de tus perfiles. Está desactivado por defecto, e Inicio indica qué regla tiene un perfil que aún necesita configuración.",
      },
      {
        title: "Mira el texto en directo de tu modelo local",
        description:
          "La vista previa en directo puede usar el modelo de voz seleccionado (Parakeet, SenseVoice u Orukeet) además de Apple Speech, en la ventana de grabación y al grabar una reunión. La transcripción final no cambia.",
      },
      {
        title: "Usa Airdraft en chino simplificado",
        description:
          "La interfaz, los menús nativos y las frases de Atajos de Apple están disponibles en chino simplificado. Una configuración nueva en un Mac en chino simplificado empieza con la escritura simplificada.",
      },
      {
        title: "Un mejor primer modelo para inglés, japonés y coreano",
        description:
          "La configuración inicial recomienda Parakeet TDT v2 para inglés y Qwen3-ASR 1.7B para japonés y coreano, según la medición propia de Airdraft. SenseVoice instala ahora el modelo multilingüe original; el ajuste fino para cantonés que instalaban la 0.11.0 y anteriores sigue funcionando como SenseVoice Cantonese.",
      },
      {
        title: "Tu vocabulario ayuda al reconocimiento en el dispositivo",
        description:
          "Qwen3-ASR, Parakeet y Orukeet usan las grafías del Vocabulario mientras reconocen la voz. Puedes desactivarlo en Ajustes > Comportamiento.",
      },
      {
        title: "Transcripciones locales más limpias",
        description:
          "Se cortan las repeticiones en bucle, se reintenta cuando se detecta mal el idioma, y SenseVoice y FireRedASR2 escriben el inglés con mayúsculas normales y puntuación. Los kanji japoneses ya no se convierten a escritura china, y si el refinamiento convierte japonés o coreano en chino, se vuelve a tu transcripción.",
      },
      {
        title: "Reuniones que recuerdan los nombres de los hablantes",
        description:
          "Los nombres de hablante que escribes se sugieren en reuniones posteriores, y «Resumir» ofrece «Resumen breve», «Tareas pendientes», «Decisiones y seguimientos» y «Acta de reunión».",
      },
      {
        title: "Una página Modelos más sencilla",
        description:
          "Modelos se abre con la recomendación para tu idioma y algunas alternativas, con «Mostrar todos los modelos» para la lista completa y los nombres completos de los idiomas en cada fila.",
      },
      {
        title: "Pega en Ghostty 1.3 sin errores",
        description:
          "Ghostty 1.3 muestra a Airdraft un cursor de texto, lo que hacía que cada pegado informara de que no se pudo confirmar. Ahora recibe un solo pegado y ningún aviso, como otras terminales que dibujan su propio texto.",
      },
      {
        title: "Menos uso de memoria",
        description:
          "Cuando macOS informa de presión de memoria, se descargan de memoria los modelos de voz locales inactivos y los modelos de LM Studio que cargó Airdraft. Un dictado en curso conserva su modelo.",
      },
    ],
  },
  "0-11-0": {
    title: "Interfaz en chino tradicional y entrega fiable",
    changes: [
      {
        title: "Usa Airdraft en chino tradicional",
        description:
          "La interfaz, los menús nativos y las frases de Atajos de Apple están disponibles en chino tradicional (Taiwán) y siguen el idioma de macOS. Los nombres de los perfiles integrados aparecen en el idioma de la interfaz hasta que los renombras.",
      },
      {
        title: "Dicta de nuevo justo después de pegar",
        description:
          "Un atajo pulsado mientras se restauraba el portapapeles o se guardaba el Historial podía ignorarse. Ahora Airdraft está listo en cuanto se confirma la entrega, y un pegado más reciente nunca recupera un portapapeles anterior.",
      },
      {
        title: "Pega en terminales que dibujan su propio texto",
        description:
          "Warp, Zed, Ghostty, kitty, Alacritty y WezTerm reciben un solo pegado sin errores, y el Historial lo marca como «Pegado, sin confirmar». Tu portapapeles vuelve a los dos segundos. Otras apps sin un cursor visible siguen dejando el texto en el portapapeles con un aviso de recuperación.",
      },
      {
        title: "Sigue dictando mientras esperan grabaciones",
        description:
          "Una grabación guardada tras un fallo de voz ya no bloquea nuevos dictados. Pueden esperar hasta tres grabaciones o 15 minutos de audio para reintentarlas o descartarlas; cuando queda poco espacio, la siguiente grabación se detiene antes y explica por qué.",
      },
      {
        title: "Configuración más clara en Inicio y en la bienvenida",
        description:
          "Inicio da por listo un modelo de voz instalado aunque aún no se haya cargado, e indica los bloqueos por prueba, licencia o grabaciones guardadas. «Pruébalo» se completa ahora con un dictado real, y «Listo» ofrece el refinamiento con Apple Intelligence cuando el Mac lo admite.",
      },
      {
        title: "Modelos locales recomendados y verificados",
        description:
          "A un Mac en chino se le recomienda Qwen3-ASR 1.7B, o primero SenseVoice con 8 GB de memoria o menos. Modelos se abre con esa recomendación y los modelos verificados, y el resto queda en «Experimental». Las descargas de Qwen3-ASR y Whisper están fijadas y se comprueban por tamaño y SHA-256 antes de instalarlas.",
      },
      {
        title: "Ajusta el tamaño del texto",
        description:
          "Ajustes > Apariencia > Tamaño del texto ofrece Normal, Grande y Máximo, y en los tamaños mayores el texto pasa a otra línea en lugar de cortarse. Cada control tiene ahora un nombre y un estado para VoiceOver.",
      },
      {
        title: "Empieza y guarda dictados más rápido",
        description:
          "El micrófono se abre en cuanto pasan las comprobaciones de configuración, el refinamiento se prepara mientras hablas y guardar un dictado ya no recorre el audio guardado. Una grabación larga mantiene cargado su modelo de voz local hasta que termina el procesamiento.",
      },
      {
        title: "Compila Airdraft desde el código más fácilmente",
        description:
          "Ajustes > Actualizaciones > Agradecimientos muestra los avisos de terceros, y las versiones compiladas desde el código se abren ahora sin el equipo de firma del proyecto.",
      },
    ],
  },
  "0-10-2": {
    title: "Llega la versión preliminar de AssemblyAI Universal-3.6 Pro",
    changes: [
      {
        title: "Elige la versión preliminar por lotes de 3.6 Pro",
        description:
          "Modelos y Perfiles ofrecen ahora Universal-3.6 Pro (Preview) mediante la API preliminar de audio pregrabado de AssemblyAI. Universal-3.5 Pro sigue disponible y conserva las selecciones guardadas. La disponibilidad de la versión preliminar y la calidad de la transcripción aún deben verificarse con una cuenta de AssemblyAI.",
      },
      {
        title: "La solicitud usa el modelo de voz seleccionado",
        description:
          "Las solicitudes a AssemblyAI usan el modelo que eliges. Los fallos de la versión preliminar no se reintentan con 3.5 Pro, y una respuesta que indica otra versión del modelo se rechaza en lugar de registrarse como una transcripción correcta de 3.6 Pro.",
      },
    ],
  },
  "0-10-1": {
    title: "Recupera modelos atascados y añade los colores Disco",
    changes: [
      {
        title: "Cambia de un modelo de voz atascado",
        description:
          "La carga de modelos tiene ahora un límite de dos minutos. Al cancelar o cambiar de modelo, la siguiente selección queda libre mientras el trabajo nativo pendiente se limpia de forma segura. Un modelo que aún se está limpiando queda protegido de cargas duplicadas y de la eliminación.",
      },
      {
        title: "Colores de grabación que responden a tu voz",
        description:
          "El interruptor guardado Disco añade colores fluidos a Clásico, Cubo, Sónico, Órbita y Seda. La energía de la voz y los acentos de las sílabas dan forma a la paleta, que se asienta en las pausas y se congela durante la entrega. Con «Reducir movimiento», los colores quedan quietos.",
      },
    ],
  },
  "0-10-0": {
    title: "Más modelos de voz locales y configuración guiada",
    changes: [
      {
        title: "Estilos animados para la ventana de grabación",
        description:
          "Mini pasa a llamarse Clásico, con una vista previa animada en Ajustes y el mismo tamaño de cápsula que los demás estilos. Las vistas previas, más grandes, muestran los cinco estilos, incluidos los anillos plateados entrelazados de Órbita y la cinta metálica plegada de Seda.",
      },
      {
        title: "Más modelos de voz en el dispositivo",
        description:
          "El catálogo local añade Whisper Large v3, Turbo comprimido, opciones GGUF y Core ML fijadas, Distil-Whisper y Orukeet. Modelos, Perfiles y Reuniones comparten la selección exacta del modelo, los límites de idioma y las comprobaciones de descarga.",
      },
      {
        title: "Aprende a dictar paso a paso",
        description:
          "Seis pasos de configuración opcionales te guían para elegir la voz, conceder permisos, practicar el atajo y hacer tu primer dictado. Las descargas de modelos continúan entre pasos, y la práctica del atajo pausa la grabación.",
      },
      {
        title: "Reuniones más claras y controles coherentes",
        description:
          "Las tarjetas de reunión mantienen la siguiente acción junto a un reproductor compacto. La edición de transcripciones tiene acciones fijas en la cabecera y el pie, y botones, selectores y campos de texto comparten una misma forma redondeada.",
      },
    ],
  },
  "0-9-1": {
    title: "Corrige el audio y los controles de las reuniones",
    changes: [
      {
        title: "Lee y elige apps para la reunión",
        description:
          "El selector de apps da ahora a cada app una fila de altura completa, crece a medida que se cargan las fuentes y desplaza las listas más largas. «Actualizar», los estados vacíos y los errores siguen visibles.",
      },
      {
        title: "Escucha las nuevas grabaciones en ambos canales",
        description:
          "Las reuniones nuevas y recuperadas mezclan el micrófono y el audio de las apps en canales izquierdo y derecho idénticos. Los archivos guardados antes no cambian. Los medidores de las reuniones usan ahora la misma respuesta lineal y la misma escala de diez celdas que el selector de micrófono.",
      },
      {
        title: "Controles principales coherentes",
        description:
          "Las acciones de grabar, transcribir y guardar la transcripción usan cápsulas azules en relieve con los mismos estados de pulsado y desactivado que los demás botones neumórficos de Airdraft.",
      },
    ],
  },
  "0-9-0": {
    title: "Un espacio propio para las reuniones",
    changes: [
      {
        title: "Encuentra cada reunión y transcripción",
        description:
          "Reuniones tiene ahora su propia página en la barra lateral. Cada grabación tiene una acción directa para transcribirla, versiones guardadas de la transcripción, controles de recuperación, acceso desde el Finder y exportación de audio. El Historial se centra en el dictado.",
      },
      {
        title: "Elige entre más modelos de transcripción locales",
        description:
          "La transcripción de archivos con etiquetas de hablante admite ocho modelos locales, entre ellos los dos tamaños de Qwen3-ASR, Cohere, SenseVoice, FireRed, Parakeet y Apple Speech, además de Whisper Turbo. Los motores añadidos muestran marcas de tiempo por segmento; Whisper conserva las marcas de tiempo por palabra.",
      },
      {
        title: "Empieza a grabar con menos pasos",
        description:
          "Una hoja de reunión compacta te permite elegir el audio de las apps e incluir tu micrófono. El selector de apps se abre al instante, y las grabaciones guardadas siguen visibles tras reiniciar. Modelos aparece ahora encima de Ajustes, el nuevo nombre de Configuración.",
      },
      {
        title: "Más opciones de voz en la nube y una recuperación más clara",
        description:
          "Las integraciones de voz nativas añaden AssemblyAI, Cartesia, Speechmatics, xAI, Mistral y Gemini. Las pantallas de datos bloqueados y de recuperación permiten ahora salir con normalidad, y la limpieza en curso sigue protegida.",
      },
    ],
  },
  "0-8-1": {
    title: "Recupera el texto cuando no se puede confirmar un pegado",
    changes: [
      {
        title: "El texto sin confirmar sigue disponible",
        description:
          "Airdraft comprueba ahora el texto del destino antes de dar por bueno un pegado. Si un editor ignora el pegado o no puede exponer su texto, tu transcripción se queda en el portapapeles y aparece un aviso de recuperación. Revisa el destino antes de volver a pegar; Airdraft nunca reintenta por sí solo un pegado dudoso.",
      },
      {
        title: "Los detalles de recuperación se guardan en el Historial",
        description:
          "El Historial guarda la transcripción y el diagnóstico de la entrega cuando no se puede confirmar un pegado, también después de un refinamiento correcto. Si otra app cambia el portapapeles, su contenido más reciente se conserva y el aviso te remite al Historial.",
      },
    ],
  },
  "0-8-0": {
    title: "Grabaciones, captura de reuniones y búsqueda en Configuración",
    changes: [
      {
        title: "Conserva el audio con independencia de las transcripciones",
        description:
          "Explora y exporta grabaciones, importa archivos multimedia, edita transcripciones con hablantes y captura el audio de reuniones. El audio guardado sigue disponible para transcribirlo y recuperarlo, con controles de limpieza separados para grabaciones y texto.",
      },
      {
        title: "Encuentra ajustes y elige tu ventana de grabación",
        description:
          "Busca en Configuración por nombre o descripción del ajuste. Elige las ventanas de grabación Mini, Cubo o Sónico, activa un temporizador opcional y elige iconos de app distintos para el modo claro y el oscuro.",
      },
      {
        title: "Protección de la privacidad y del trabajo interrumpido",
        description:
          "Las comprobaciones de redirección de proveedores, los límites del contexto del navegador y la recuperación de limpiezas interrumpidas son más estrictos. Las comprobaciones compartidas de ocupación protegen las operaciones en curso, y el desplazamiento del Historial y los avisos de recuperación reciben correcciones de fiabilidad.",
      },
    ],
  },
  "0-7-0": {
    title: "Mantén pulsado para empezar con «Retardo de activación»",
    changes: [
      {
        title: "Evita dictados accidentales",
        description:
          "Ajusta «Retardo de activación» de 0 a 1000 ms en Configuración. Las pulsaciones cortas conservan la acción normal de la tecla del atajo; mantenerla más allá del retardo inicia el dictado. Por defecto está desactivado, y la detención sigue siendo inmediata.",
      },
      {
        title: "Grabaciones de diez minutos como máximo",
        description:
          "El límite de grabación va ahora de 10 segundos a 10 minutos. Los límites guardados más largos se reducen a diez minutos, y se conservan las opciones más cortas y el valor predeterminado de cinco minutos. El audio importado mantiene sus propios límites.",
      },
    ],
  },
  "0-6-2": {
    title: "Los idiomas de voz siguen a cada modelo",
    changes: [
      {
        title: "Elige un idioma compatible",
        description:
          "Las opciones de idioma siguen ahora al modelo de voz activo, incluidos los modelos propios de cada perfil. Las combinaciones no compatibles se detienen antes de grabar, con una explicación. Parakeet no admite chino.",
      },
      {
        title: "Fija el idioma para Cohere",
        description:
          "El modelo local Cohere Transcribe necesita ahora que elijas un idioma. La detección automática no está disponible en este entorno porque puede convertir la voz en chino en un texto en inglés incorrecto.",
      },
      {
        title: "Opciones de idioma aplicadas de forma coherente",
        description:
          "SenseVoice recibe el idioma elegido, Qwen usa los nombres de idioma esperados y Apple Speech muestra las configuraciones regionales disponibles en el sistema. Cambiar de modelo conserva tu preferencia compartida.",
      },
    ],
  },
  "0-6-1": {
    title: "El contexto de la app pasa a ser opcional",
    changes: [
      {
        title: "Elige cuándo compartir el contexto de la app",
        description:
          "«Leer el contexto de la app» está ahora desactivado por defecto cuando no hay ninguna preferencia guardada. Las elecciones existentes se conservan, y la inserción en el cursor sigue funcionando de forma independiente.",
      },
      {
        title: "Un icono de app neutro",
        description:
          "El icono de la app usa ahora los mismos grises neutros, la misma onda en relieve y el mismo cursor grafito que la ventana de la app.",
      },
    ],
  },
  "0-6-0": {
    title: "Un modelo de voz para cada perfil",
    changes: [
      {
        title: "Elige la voz en cada perfil",
        description:
          "Asigna un modelo de voz a un perfil de escritura o sigue usando el predeterminado de la app. Al cambiar de perfil, esa elección se aplica a la siguiente grabación.",
      },
      {
        title: "Lee un dictado desde Inicio",
        description:
          "Haz clic en una barra de la onda para abrir su transcripción. Despliega el texto largo, cópialo o pasa a otro dictado sin salir de Inicio.",
      },
      {
        title: "Encuentra modelos más fácilmente",
        description:
          "Explora los modelos de voz por proveedor, con iconos de marca y etiquetas del servicio que los aloja. Filtrar la lista no cambia tu modelo activo.",
      },
      {
        title: "Progreso y controles más claros",
        description:
          "Las barras y los porcentajes de descarga avanzan a la vez. Las cabeceras de página, más cortas, dejan más espacio al contenido, y el menú agrupa los controles de modelos y las acciones de recuperación.",
      },
    ],
  },
  "0-5-1": {
    title: "Modelos listos cuando tú lo estás",
    changes: [
      {
        title: "Empieza tras una pausa de inactividad",
        description:
          "Al empezar un dictado se vuelve a cargar automáticamente un modelo de voz instalado. Por defecto, los modelos inactivos se descargan de memoria a los 30 minutos, y puedes elegir 5, 10 o 30 minutos, o «Nunca».",
      },
      {
        title: "Mira el progreso real de las descargas",
        description:
          "Las descargas de modelos informan de los bytes recibidos a lo largo de cada archivo. La preparación y la descompresión muestran actividad en lugar de un porcentaje inventado.",
      },
      {
        title: "Los mensajes se cierran solos",
        description:
          "Los errores, los avisos de recuperación y las confirmaciones se muestran durante cinco segundos y luego se desvanecen. Los detalles de recuperación siguen disponibles en Inicio y en el Historial cuando corresponde.",
      },
      {
        title: "Una barra lateral más precisa",
        description:
          "Un icono en relieve sigue al hueco de selección deslizante. El botón del micrófono, el botón de la barra lateral y las sombras de las tarjetas mantienen una posición y una profundidad coherentes.",
      },
    ],
  },
  "0-5-0": {
    title: "La app cambia de forma",
    changes: [
      {
        title: "Un solo material en toda la ventana",
        description:
          "Islas de página redondeadas, tarjetas y controles en relieve, selecciones hundidas y una onda neutra en Inicio comparten la misma luz y sombra en las dos apariencias.",
      },
      {
        title: "Una navegación que se mueve contigo",
        description:
          "El hueco seleccionado de la barra lateral se desliza entre páginas. La marca tallada y el marco de ventana opaco completan la nueva interfaz.",
      },
      {
        title: "El inglés se queda en inglés",
        description:
          "Las indicaciones de escritura china solo se envían cuando el chino está seleccionado, lo que evita traducciones no deseadas al detectar automáticamente el idioma de voz.",
      },
      {
        title: "Confirmaciones del portapapeles más discretas",
        description:
          "Las confirmaciones del portapapeles se cierran solas. La siguiente versión, la 0.5.1, extiende el cierre temporizado a todos los mensajes de la ventana de grabación.",
      },
    ],
  },
  "0-4-6": {
    title: "Conserva las palabras que acabas de decir",
    changes: [
      {
        title: "Los dictados anteriores no se cuelan en los nuevos",
        description:
          "El refinamiento separa el contexto de la transcripción actual y comprueba la fidelidad para reducir las frases reutilizadas y las traducciones no deseadas.",
      },
      {
        title: "Un menú compacto y una selección más clara",
        description:
          "Los títulos dinámicos largos del menú caben en su anchura, y el destino activo de la barra lateral se asienta en un hueco más hundido.",
      },
    ],
  },
  "0-4-5": {
    title: "Compatibilidad con editores que no exponen el cursor",
    changes: [
      {
        title: "Pega a través de la app activa",
        description:
          "Los editores que no exponen un cursor de texto accesible pueden usar el pegado a través de la ventana de la app, y los cambios de destino siguen activando la recuperación.",
      },
    ],
  },
  "0-4-4": {
    title: "Lee el error completo",
    changes: [
      {
        title: "Espacio para los diagnósticos",
        description:
          "La cápsula de grabación se amplía para mostrar los mensajes de error y de recuperación completos. Los mensajes demasiado largos se desplazan dentro de la pantalla.",
      },
      {
        title: "Copia el mensaje completo",
        description:
          "La acción «Copiar mensaje», al final, copia el diagnóstico sin quitar el foco a la app que estabas usando.",
      },
    ],
  },
  "0-4-3": {
    title: "Te sigue entre apps",
    changes: [
      {
        title: "Espera a que el destino se asiente",
        description:
          "Airdraft espera a la app, el campo de texto y el cursor seleccionados cuando hay un cambio de app en curso. Las lecturas de foco transitorias pueden asentarse antes de la entrega.",
      },
    ],
  },
  "0-4-2": {
    title: "Una sola vía de pegado, más segura",
    changes: [
      {
        title: "Sin intentos de inserción en conflicto",
        description:
          "La entrega del texto usa una única vía de pegado normal en lugar de una escritura especulativa por Accesibilidad seguida de un pegado.",
      },
      {
        title: "El texto se conserva al cancelar",
        description:
          "Si se cancela después de que empiece la entrega, el texto dictado se queda en el portapapeles el tiempo suficiente para que el destino lo lea.",
      },
    ],
  },
  "0-4-1": {
    title: "Un dictado diario más fiable",
    changes: [
      {
        title: "Los iPhone no seleccionados siguen desconectados",
        description:
          "Al abrir el selector de micrófono, solo se previsualiza un micrófono de Continuidad cuando está seleccionado, también a través de «Predeterminado del sistema».",
      },
      {
        title: "Recorre el Historial con accesibilidad",
        description:
          "Las marcas de tiempo visibles siguen la navegación por la línea de tiempo, y las entradas fuera de pantalla salen de la representación accesible cuando vuelves arriba.",
      },
      {
        title: "Recuperación del foco y de fallos del proveedor",
        description:
          "La inserción espera al foco y la selección del editor. Los fallos de Claude conservan la transcripción original con un diagnóstico útil; la hoja de licencia usa menos controles.",
      },
    ],
  },
  "0-4-0": {
    title: "Un primer dictado guiado",
    changes: [
      {
        title: "Aprende haciendo",
        description:
          "Una bienvenida opcional te guía por los permisos y la configuración de la voz, y luego te deja probar un dictado real.",
      },
      {
        title: "Prueba y activa la versión oficial",
        description:
          "Las versiones oficiales añaden una prueba de 14 días con todas las funciones, que inicias tú, y la activación de la licencia. Las ediciones compiladas por ti siguen totalmente desbloqueadas.",
      },
      {
        title: "El texto largo se queda dentro del Historial",
        description:
          "Las transcripciones largas y las selecciones de texto se quedan dentro de sus tarjetas. La cápsula de grabación se ajusta a su etiqueta y se desvanece tras una entrega correcta.",
      },
      {
        title: "Una licencia de código abierto explícita",
        description:
          "El repositorio adopta GPL-3.0-only, con la licencia enlazada desde el sitio web.",
      },
    ],
  },
  "0-3-0": {
    title: "Inteligencia local, reproducción y automatización",
    changes: [
      {
        title: "Refina con Apple Intelligence",
        description:
          "En los Macs compatibles con macOS 26 o posterior, una sesión de Foundation Models en el dispositivo limpia cada dictado. Si el refinamiento no está disponible o falla, se conserva la transcripción sin procesar.",
      },
      {
        title: "Más formas de oír y revisar la voz",
        description:
          "Parakeet TDT v3 se suma al reconocimiento de voz local. Las vistas previas opcionales de transcripción en directo muestran palabras provisionales mientras grabas.",
      },
      {
        title: "Guarda y reproduce el audio",
        description:
          "Activa la conservación del audio de los dictados, reprodúcelo desde el Historial y reintenta la transcripción a partir de la grabación guardada.",
      },
      {
        title: "Conecta el dictado con tu flujo de trabajo",
        description:
          "Inicia y detén el dictado con Atajos, y envía el texto entregado a un script configurado.",
      },
      {
        title: "Mejor fidelidad del texto y un mejor Historial",
        description:
          "El refinamiento corrige términos y conserva el texto literal. El Historial limita el trabajo durante el desplazamiento, añade fechas a su línea de tiempo y gana un desenfoque progresivo en la cabecera.",
      },
    ],
  },
  "0-2-0": {
    title: "Nuevos controles de voz y una interfaz renovada",
    changes: [
      {
        title: "Comprueba tu conexión",
        description:
          "Prueba el acceso a la API de Soniox, Groq, ElevenLabs, OpenAI y Deepgram antes de dictar. OpenRouter añade controles de modelo y de proveedor.",
      },
      {
        title: "Compara los modelos de voz compatibles",
        description:
          "Explora los modelos de cada proveedor con sus precios y la información de calidad y velocidad disponible, enlazada a la documentación oficial. Las métricas no publicadas quedan señaladas.",
      },
      {
        title: "Una interfaz nativa renovada",
        description:
          "Una barra lateral contraíble, medidores de micrófono en directo y una línea de tiempo desplazable en el Historial se suman a ajustes y listas de modelos coherentes.",
      },
      {
        title: "Recupera el trabajo interrumpido",
        description:
          "Los requisitos de grabación se comprueban antes de capturar. El audio de voz que falla sigue disponible para reintentarlo o descartarlo, y los errores de refinamiento conservan la transcripción sin procesar.",
      },
      {
        title: "Un número de versión para la versión con funciones",
        description:
          "Esta versión tiene las mismas funciones que la 0.1.9, compilación 44, con un nuevo número de versión menor. Su instalador está firmado con Apple Development y no está notarizado.",
      },
    ],
  },
  "0-1-9": {
    title: "Toman forma los controles de escritorio",
    changes: [
      {
        title: "Elige y prueba un micrófono",
        description:
          "El panel del micrófono añade una vista previa del nivel de entrada en directo. Los controles de la barra lateral y de los perfiles se vuelven más compactos a lo largo de esta serie de compilaciones.",
      },
      {
        title: "Edita las reglas de refinamiento compartidas",
        description:
          "La edición del prompt base se suma a la personalización de perfiles, para que las instrucciones compartidas se puedan guardar o restaurar.",
      },
      {
        title: "Un sitio web y un instalador con marca",
        description:
          "El sitio web en Astro y una imagen de disco propia para arrastrar a Aplicaciones se suman al proyecto. Las compilaciones posteriores de esta serie desembocan en la versión con funciones 0.2.0.",
      },
    ],
  },
  "0-1-8": {
    title: "Haz tuyos los perfiles de escritura",
    changes: [
      {
        title: "Edita, duplica y restablece",
        description:
          "Los perfiles ganan un editor abierto, cambio de nombre en línea y duplicación, incluido el comportamiento de «Literal». Las reglas compartidas ofrecen «Guardar», «Cancelar» y «Restaurar valores predeterminados».",
      },
    ],
  },
  "0-1-7": {
    title: "Menos interrupciones durante la configuración",
    changes: [
      {
        title: "Pide acceso a las claves solo cuando hace falta",
        description:
          "La navegación entre páginas y las comprobaciones en segundo plano dejan de pedir permiso al Llavero. Las claves protegidas tienen una acción de acceso explícita, y las lecturas denegadas conservan las credenciales guardadas.",
      },
      {
        title: "Captura el canal de entrada seleccionado",
        description:
          "La captura del micrófono usa el canal elegido. Soltar el atajo mientras el permiso está pendiente impide que empiece una grabación con retraso.",
      },
    ],
  },
  "0-1-6": {
    title: "Más proveedores de refinamiento",
    changes: [
      {
        title: "Usa Cerebras o Groq",
        description:
          "Elige Cerebras o Groq para refinar el texto, con independencia de tu proveedor de reconocimiento de voz.",
      },
    ],
  },
  "0-1-5": {
    title: "Una identidad estable para las actualizaciones",
    changes: [
      {
        title: "Una firma coherente",
        description:
          "Las versiones firmadas con certificado sustituyen a la identidad ad hoc anterior. El proceso de actualización comprueba la continuidad de la firma; al actualizar desde compilaciones antiguas puede que tengas que volver a conceder los permisos.",
      },
    ],
  },
  "0-1-4": {
    title: "Recuperación tras interrupciones del micrófono",
    changes: [
      {
        title: "Reanuda una entrada interrumpida",
        description:
          "La captura del micrófono se recupera de las interrupciones de la entrada, y el espaciado de los ajustes es más coherente.",
      },
    ],
  },
  "0-1-3": {
    title: "Apps de desarrollo e instaladas por separado",
    changes: [
      {
        title: "Se reconoce la app correcta",
        description:
          "Las compilaciones de desarrollo y las instaladas usan identidades distintas, con el estado de los permisos actualizado para que las comprobaciones de acceso se apliquen a la app correcta.",
      },
    ],
  },
  "0-1-2": {
    title: "Respeta el micrófono del sistema",
    changes: [
      {
        title: "Se conserva la ruta seleccionada",
        description:
          "La captura mantiene la ruta del micrófono del sistema en lugar de sustituir inesperadamente la entrada que elegiste.",
      },
    ],
  },
  "0-1-1": {
    title: "Las primeras compilaciones empaquetadas",
    changes: [
      {
        title: "Recuerda tu elección de micrófono",
        description:
          "El micrófono predeterminado pasa a formar parte de la configuración, y las versiones compiladas localmente llegan como DMG con un canal de actualizaciones de Sparkle firmado.",
      },
    ],
  },
  "initial-source": {
    title: "Airdraft llega a GitHub",
    changes: [
      {
        title: "Habla en la app que usas",
        description:
          "Mantén pulsado un atajo, habla y suelta para insertar texto en el cursor. Airdraft se queda en la barra de menús entre grabaciones.",
      },
      {
        title: "Elige cada paso por separado",
        description:
          "Usa reconocimiento de voz local o en la nube y elige el refinamiento por separado. Los perfiles de escritura editables, las correcciones de vocabulario y el Historial local forman parte de la versión compilada desde el código.",
      },
    ],
  },
};
