# Trabajo acordado · actualizado 24 de octubre de 2026

Este documento conserva el alcance solicitado; una propuesta no se marca como función terminada.

## Correcciones y revisión en curso

- [x] MT63 en seis variantes y ALE 2G: fuentes, pruebas, ejemplos, paquete 0.10.0 y comprobación de interfaz. Cambios incorporados al PR existente durante el cierre de 0.11.0.
- [x] Reparar Guía de radios → Planificador HF: selección persistente, envío directo, datos parciales, procedencia y campos pendientes visibles.
- [x] Auditar cálculo HF: unidades, dirección TX/RX, índices solares, condiciones por hemisferio, supuestos y pruebas de referencia.
- [x] Comparar DMR de SDR++Brown con DSD-neo: arquitectura, slots, CC y límites documentados. Biblioteca, diagnóstico y entrada TCP de discriminador en 0.11; voz DMR durante recepción, selector de síntesis y panel por intervalo en 0.12. Falta contraste con dos llamadas simultáneas y recepción física.

## Revisión y DMR · 0.12

- [x] Guía: selección BBC de 9410 kHz y ficha observadas; el usuario confirmó BBC, 9,410 MHz y Escucha tras el envío directo al planificador. El control de pantalla falló al abrir esa vista.
- [x] DMR: runtime oficial con una grabación independiente TS1; origen/destino/clase coinciden con el oráculo público. CC7 observado, sin oráculo independiente para ese campo.
- [x] Voz DMR durante la recepción, TS1/TS2/ambos y panel con procedencia y antigüedad, conservando WAV.
- [x] Corregir waterfall lento en vivo: reloj visual, cola de un cuadro, ventanas completas y raster incremental; comparación sintética reproducible en 0.12.1.
- [ ] Repetir recepción en vivo con la entrada del usuario para confirmar la fluidez visual en su flujo real.
- [ ] Terminar el recorrido visual de biblioteca, DSC, mapas y otras herramientas en la nueva compilación.
- [ ] Corpus identificado con dos conversaciones simultáneas y evaluación perceptual de voz; la prueba física sigue aplazada.

## Revisión del 24 de octubre · propuesta de la siguiente etapa

El usuario confirmó que CW funciona. Esta confirmación no valida automáticamente
los otros modos ni identifica la fuente de audio utilizada. Los puntos siguientes
son una propuesta basada en la revisión del código y de Artemis; todavía no se
presentan como funciones implementadas. No se creó otra compilación ni se
copiaron catálogos completos al proyecto.

### 1. Un registro de escucha para guía, biblioteca y mapa

- [ ] Añadir en la ficha de la guía el botón principal **«Registrar escucha en
  biblioteca…»**, visible aunque no exista una grabación de audio. Abrir una ficha
  con emisora y frecuencia precargadas, hora real, resultado, antena y notas;
  adjuntar una grabación será opcional. Guardar requiere confirmar la observación.
- [ ] Ofrecer resultados **Escuchada / No escuchada / Dudosa**, para conservar
  también los intentos fallidos y poder interpretar el historial.
- [ ] Separar horario previsto, hora de observación e importación de un archivo.
  La ubicación de la estación emisora debe tener procedencia; si hay varios sitios
  candidatos, permitir elegir uno o guardar la escucha sin posición.
- [ ] Integrar esas observaciones en la misma biblioteca, con filtros **Todas /
  Escuchas anotadas / Con audio**. Vincular audio existente sin duplicarlo. Una
  emisión AM de la guía no necesita seleccionar un decodificador CW o digital.

La biblioteca actual exige un archivo de audio y un `RadioMode`. La opción mínima
compatible es añadir `ListeningObservation` al repositorio y migrar el índice
preservando `ReceptionSession`, sus audios y la papelera. Una observación conserva:
identificador, inicio/fin reales, ficha de emisora y horario como instantánea,
frecuencia en Hz, modo RF, decodificador opcional, sitio TX y su procedencia,
posición RX en ese momento, equipo/antena, resultado, notas y vínculos opcionales
a grabación o evento. Ubicación y antena históricas no deben cambiar al editar el
perfil actual. Las grabaciones y fichas existentes deben seguir abriéndose.

**Mapa:** derivar la capa de escuchas de ese registro persistente; no crear otro
historial independiente. Mostrar **TX → RX**, distancia, rumbo, fecha y antena.
Conservar las capas actuales APRS/ACARS/eventos con su procedencia y permitir
filtrar por fecha, franja horaria UTC/local, banda, modo, antena y tipo de fuente.
Añadir una línea de tiempo por hora y resumen de distancias observadas por rumbo.
Las observaciones sin sitio TX resuelto siguen visibles en una lista pendiente
de localizar. WebSDR y eventos de Internet quedan separados del alcance local.

El nombre recomendado es **«Alcance observado»**: puntos y trayectos registrados,
sin convertir unos pocos éxitos en un círculo de cobertura o un patrón de
radiación de la antena. Los intentos negativos necesitan contexto: que una emisora
no se escuche no demuestra que estuviese transmitiendo ni que esa dirección sea
inaccesible.

**Base observada:** `ReceptionLibrary.swift` exige audio; `BroadcastGuideView.swift`
no ofrece registro en la biblioteca; `ReceptionEventStore.swift` conserva hasta
5.000 eventos solo en memoria y `ReceptionEventsView.swift` filtra por fuente.

### 2. Separar Escucha HF y Enlace HF

- [ ] **Escucha de emisoras:** emisora/sitio remoto, fecha/hora, frecuencia,
  receptor y antena local. Mostrar de inmediato horario previsto, distancia,
  rumbo, iluminación del trayecto y sintonía recomendada. La guía abre este flujo
  mediante **«Planificar escucha»**.
- [ ] Dentro de escucha, ofrecer **«Estimación de recepción P.533»** como cálculo
  adicional: requiere potencia remota conocida o un supuesto explícito, antenas,
  ruido y requisito de recepción. No pedir «tu potencia TX» a quien solo escucha.
  Sin esos datos, los resultados básicos siguen siendo útiles; no inventar SNR
  ni porcentaje de recepción. HFCC programado no prueba la potencia efectiva.
- [ ] **Enlace entre estaciones:** fichas A y B con parámetros TX y RX propios;
  calcular **A → B** y **B → A**, mostrar la dirección limitante y conservar los
  supuestos de cada estación. No multiplicar disponibilidades mensuales como
  si fueran probabilidades independientes de contacto en tiempo real.
- [ ] Adaptar textos y gráficos a cada flujo. El barrido desde un transmisor
  remoto no se denominará alcance de la antena local. Las entradas fuera del
  rango 1,6–30 MHz del motor mantienen registro/distancia, con su límite visible.

**Defectos observados:** `PropagationStore.swift` usa un `Bool listening` que
invierte extremos de un único cálculo. La importación borra potencia y el motor
la exige antes de calcular. `HFPredictionPanel.swift` conserva «con tu potencia» y
«Qué contactos podrían ser posibles» en escucha. Separar los formularios evita
reutilizar sin advertencia parámetros de una estación al cambiar de dirección.

### 3. Reorganizar Voz digital como pantalla propia

- [ ] Cabecera con protocolo, entrada, iniciar/detener y estado de audio.
- [ ] Preparación SDR compacta; controles **TS1 / TS2 / Ambos** y escucha de voz
  juntos. Conservar la cola de salida acotada y el funcionamiento ya implementado.
- [ ] Área principal con tarjetas de actividad TS1/TS2, CC, origen, destino,
  clase y antigüedad; distinguir audio entrante, sincronía, datos de llamada,
  salida de voz y finalización del WAV. Ningún estado garantiza inteligibilidad.
- [ ] Espectro plegable; quitar en DSD el marcador y la sintonía de tono que no
  intervienen en el motor. Registro del motor y detalles técnicos quedan abajo.
- [ ] Cambiar «TEXTO RECIBIDO» por **«Registro del decodificador»** en esta vista.
  Presentar el ejemplo como **«Ejemplo M17 de datos»**, sin cambiar DMR en silencio
  ni sugerir que se está probando voz DMR.
- [ ] Presets por protocolo, con aplicación explícita: el perfil NFM/12,5 kHz
  actual no cubre de igual forma todos los protocolos. Separar audio discriminador,
  voz ya decodificada e I/Q; la ruta DSD actual consume PCM.

**Defectos observados:** `SpectrumView.swift` permite variar un tono de 1500 Hz
que DSD no usa; `ReceiverStore.loadExample()` cambia a M17; `ReceiverView.swift`
presenta consola y pie explicativo CW/PSK a DSD. La jerarquía de controles explica
parte de la confusión. La revisión visual sigue parcial: la herramienta de
pantalla volvió a cerrar su conexión al seleccionar DSD; esto no demuestra un
cierre de RadioWorkbench. No se inició captura ni reproducción de audio.

### 4. Próximos pases de satélite en 60 minutos

- [ ] Botón **«Buscar pases en la próxima hora»** sobre el catálogo, junto a la
  búsqueda de 48 h del satélite seleccionado. Resultados: satélite/NORAD, en curso
  o empieza en, AOS, máximo, LOS, duración útil, bajada/modo y estado del transmisor.
- [ ] Elegir el transmisor concreto y enviar su frecuencia al mapa/Doppler;
  mostrar ubicación utilizada y antigüedad de los elementos orbitales.
- [ ] Calcular con margen antes/después y filtrar pases que se solapen con la
  hora solicitada; conservar pases en curso o cuyo final quede fuera de esa hora.
  Usar trabajo cancelable y acotado entre satélites.
- [ ] Presentar factores de recepción: elevación, duración, compatibilidad del
  equipo, estado publicado, antigüedad orbital y obstáculos cuando se conozcan.
  Un **índice de favorabilidad** debe explicar sus componentes y no etiquetarse
  como porcentaje probabilístico. Sin historial, indicar que el éxito no está
  calibrado. Después se podrá mostrar un porcentaje histórico real de intentos
  comparables, con denominador, fecha, antena y criterio de éxito.
- [ ] Separar pase RF y visibilidad óptica. Esta última necesita iluminación,
  sombra terrestre y oscuridad local; hoy no se calcula. Un horizonte geométrico
  ideal no incluye montañas o edificios.

**Correcciones detectadas:** ya se utiliza SGP4/SDP4, pero el texto de consultas
todavía dice Kepler/J2. El predictor solo publica un pase cuando encuentra LOS;
una ventana de una hora sin margen omitiría pases. El mapa usa inicialmente
145,8 MHz fijo. El rótulo «72 h» de reportes puede quedar vencido sin red porque
su edad se filtra al descargar y no al presentar. Archivos principales:
`RadioConsultations.swift`, `SatelliteConsultationService.swift`,
`SatellitePassMapPanel.swift` y `RadioConsultationsView.swift`.

### 5. Taller y ficha SDR común inspirados en Artemis

- [ ] Añadir un inspector derecho en los decodificadores: modo de sintonía SDR,
  modulación de la señal, filtro RF inicial, banda de audio que conservar,
  frecuencia de muestreo/canal y procesamiento que conviene desactivar. Ofrecer
  variantes HF/VHF cuando corresponda y reutilizar un único catálogo de perfiles.
  Los ajustes manuales de SDR++ se distinguen del control optativo mediante Rigctl.
- [ ] Mostrar una referencia visual por familia y variantes donde haya muestras
  verificadas. Separar **espectro RF/IQ de referencia** de **espectro de audio de
  entrada**; no superponerlos como si compartieran ejes. Una imagen sin escala
  conocida lleva esa limitación visible. Ancho ocupado no equivale necesariamente
  al filtro RF práctico que se recomienda al receptor.
- [ ] Ampliar las tres referencias actuales con ejemplos propios ya incluidos:
  DTMF, CTCSS, NAVTEX, Packet/APRS, POCSAG, DSC, FT8/FT4, MT63, ALE, SSTV, WEFAX,
  Hell y APT histórico. Identificar parámetros y resultado esperado de cada muestra.
  M17 de datos no sustituye a una referencia de voz DMR.
- [ ] Para otros protocolos, permitir catálogo **«Identificar / Sin motor
  integrado»**. Una ficha o imagen no añade automáticamente un decodificador.
- [ ] Comparación de sonido, espectro y waterfall; más adelante autocorrelación
  y búsqueda por características como tonos, ráfagas y periodicidad. Los resultados
  son candidatos, no identificación validada por semejanza visual.
- [ ] Permitir usar una recepción propia como referencia. Generar vistas a demanda
  y limitar la caché, sin copiar todo el catálogo ni crear imágenes de cada intento.

**Artemis local, observación estática:** el `Data/db.csv` es un CSV sin cabecera,
delimitado por `*`; sus 12 campos están declarados en `Resources/constants.py`.
Se contaron **432 fichas, 423 PNG y 402 OGG**, con aproximadamente 99 MB de medios.
Incluye DMR, CW, RTTY, SSTV, WEFAX, POCSAG, APT, FT8/FT4 y MT63. No todas las fichas
tienen todas las muestras. Se inspeccionó una imagen DMR local, sin ejes rotulados.
La copia local suministrada no se confunde con las capacidades del Artemis actual.

**Reutilización:** Artemis declara GPLv3 y Artemis-DB remite a esa licencia; la
procedencia/licencia de cada medio sigue requiriendo verificación. Conservar
origen, autor cuando conste, licencia y cambios por recurso. Podemos revisar
localmente los recursos suministrados, ofrecer enlaces a su fuente y producir
referencias con los WAV propios, sin afirmar que toda la colección externa esté
lista para redistribuirse. Fuentes primarias:
[Artemis, licencia](https://aresvalley.github.io/Artemis/credits/),
[Artemis-DB](https://github.com/AresValley/Artemis-DB),
[modo de recepción](https://aresvalley.github.io/Artemis/database/db_mode/),
[ancho](https://aresvalley.github.io/Artemis/database/db_bandwidth/),
[operación](https://aresvalley.github.io/Artemis/basic_operations/).

**Alcance REA:** CLI 6.7.0; inspección del ejecutable mediante `inspect_artifact`,
Evidence `ev_466a49cfd6666065a296acf74961e07ab707ed3c7c8b8fb0101b07e2365ef042`,
inventario `ev_1cb07d24a9851c57d28ed72ea2eb572fac4f641f7e404abf6e454559b4ee7523`.
Observa un Mach-O de 5.986.765 bytes, sin miembros contenedores, SHA-256
`962705a6601a7994af7548940f0143ab216e1b369f47d7adc164b88fbfafd0a8`.
No es una decompilación ni una ejecución. El contenedor `.app` fue rechazado por
REA por su `CFBundleExecutable` con subruta; no se modificó para eludirlo.
La lectura del CSV, Python y recursos se hizo con herramientas de archivos y no
se atribuye a REA. SHA-256 del CSV:
`d7c214ee4c74d790d45970798a7b5fabc44c1c9de6bb4189c53bf2bac07e498f`.
El diagnóstico auxiliar tuvo un fallo al preparar su caché Swift protegida;
no se instalaron motores ni se cambió la configuración del cliente.

### Mejoras adicionales y orden de implementación

1. **Perfil de estación/antena compartido:** ubicación, receptor, antena y origen
   local/remoto; reutilizarlo en guía, HF, satélites y mapa, guardando una instantánea
   en cada escucha. No convertir dBFS de audio en potencia RF o SNR calibrado.
2. **Datos vigentes y estado operativo:** fechas claras de horario, órbita y
   reportes, con operación offline transparente. NOAA retiró NOAA-18 en junio de
   2025 y NOAA-15/19 en agosto de 2025; mantener APT como reproducción histórica y
   no recomendar esos satélites como objetivos RF activos. Esto coincide con la
   nota histórica ya existente en nuestro perfil APT. [NOAA/NESDIS](https://www.nesdis.noaa.gov/news/legacy-orbit-noaa-decommissions-the-poes-satellite-constellation).
3. **Comparación por antena y horario:** registrar también intentos fallidos,
   calidad manual, ruido/interferencias anotados y las mismas bandas/franjas.
   Un mapa con más observaciones en una dirección no prueba por sí solo una
   antena más sensible allí.
4. **Preparación coherente de recepción:** desde una emisora, pase o referencia,
   abrir la ficha correcta con sus parámetros; confirmar cualquier envío al SDR
   mediante la acción optativa existente. No cambiar de protocolo en silencio.
5. **Pronóstico frente a resultado:** vincular opcionalmente la escucha o el
   intento a una instantánea del pronóstico HF o pase usado para prepararlo.
   Comparar después resultados por banda/hora y antena, conservando fecha, modelo
   y supuestos originales. Esa evidencia puede ayudar a calibrar futuras
   estimaciones sin cambiar retrospectivamente el historial.

Orden recomendado: **registro/biblioteca/mapa → separación HF → voz digital →
próxima hora de satélites → taller e inspector SDR común**. Corregir los textos,
el ejemplo M17 y la falsa sintonía DSD dentro de sus respectivos pasos. Mantener
las vistas visuales aisladas para no reintroducir la lentitud del waterfall.
Cada entrega conserva solo versión actual y anterior; los sondeos y archivos
temporales de esta revisión permanecieron fuera del proyecto.

Resumen de cobertura: guía/biblioteca, HF, mapa y catálogo: revisados y propuestos;
satélites: revisados, probabilidad pendiente de calibración; voz digital: revisión
de código completa para estos hallazgos, comprobación visual parcial por fallo
de la herramienta. La integración de medios externos queda condicionada a la
verificación de sus permisos. No se marca ninguna de estas ampliaciones como
terminada por haberla descrito.

## Ampliaciones solicitadas, en este orden

1. [x] Biblioteca de recepciones: audio, ajustes y fecha juntos; volver a decodificar. Después, I/Q/SigMF y comparación de motores.
2. [x] Diagnóstico de entrada y calidad: causas medidas y acciones útiles; después, pruebas guiadas de conexión.
3. [x] Audio TCP local desde SDR++Brown: formato explícito y conexión elegida por el usuario; después, UDP y pérdidas.
4. [x] DSC marítimo MF/HF y VHF: mensajes validados y exportación; después, áreas y contexto marítimo.
5. [x] Mapa común: origen, antigüedad y trazas de las posiciones disponibles; después, AIS/RS41 y avisos optativos.
6. [x] SatDump offline para LRPT: archivo I/Q identificado, progreso/cancelación y productos; después, preparación de pasadas e I/Q de red.
7. [x] Sintonía optativa desde consultas: verificar Rigctl y enviar frecuencia/modo/ancho mediante acción explícita; después, Doppler probado.
8. [x] Adaptadores de eventos externos: formato validado con procedencia y límites; después, NMEA/telemetría por protocolo.
9. [x] Taller de aprendizaje: señal de referencia, espectro y parámetros; después, ejercicios CW y clasificación con incertidumbre.

La prueba física SDR++ → VB-Cable sigue aplazada. Se puede avanzar con WAV, fuentes sintéticas, conexiones locales simuladas y capturas públicas identificadas. Se conserva la distinción entre audio de discriminador, voz ya decodificada e I/Q.

## Cierre de la primera fase 0.11.0

Los nueve primeros resultados están implementados y documentados en [NUEVE-MEJORAS.md](NUEVE-MEJORAS.md), con sus límites. Las ampliaciones «Después» de cada punto siguen pendientes; no se marcan como implementadas. Suite Release: 202 funciones, 198 aprobadas, cuatro opcionales omitidas, cero fallos; 21 comprobaciones C HF y 18 DSC repetidas con ASan/UBSan. ZIP extraído, firma estricta, arm64, fuentes y ejemplos verificados.

Tras desbloquear el Mac se comprobó la apertura de 0.11.0, las nuevas entradas de navegación, los parámetros TCP y el diagnóstico de entrada. La herramienta SkyComputerUseService se cerró al cambiar de modo y volvió a fallar tras reconectarse; RadioWorkbench permaneció activa y no apareció un nuevo informe de cierre de la app. La revisión interactiva de los demás flujos, incluida Guía → HF, sigue pendiente; [observaciones y diagnóstico](validation/ui-0.11.0.json). La ejecución LRPT con captura independiente, la interoperabilidad real Brown TCP y la prueba física SDR++/VB-Cable permanecen pendientes; las pruebas de red local no sustituyen esas comprobaciones.
