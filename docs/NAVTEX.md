# NAVTEX / SITOR-B en RadioWorkbench 0.3

Receptor nativo Swift desde PCM/WAV o audio en vivo seleccionado, implementado con los datos de protocolo de [UIT-R M.476-5](https://www.itu.int/dms_pubrec/itu-r/rec/m/R-REC-M.476-5-199510-I!!PDF-E.pdf) y [UIT-R M.625-4](https://www.itu.int/dms_pubrec/itu-r/rec/m/R-REC-M.625-4-201203-I!!PDF-E.pdf). Se consultaron también tablas de proyectos públicos como contraste; no se portó código de otro modem.

## Ajuste inicial

En SDR++: **USB**, filtro RF inicial **2400 Hz**, salida VB-Cable **48000 Hz**, sin squelch que recorte el comienzo. En la app: NAVTEX, VB-Cable, canal que contenga el receptor, centro **1700 Hz** y umbral **8 %**. Los tonos correspondientes son **1615 y 1785 Hz**, a **100 baud** y **170 Hz de shift**. El centro es editable porque una grabación puede usar otros tonos. Si se recibe por LSB, ajustar **Invertir**. El filtro RF es una guía aplicada manualmente en SDR++, y debe conservar ambos tonos.

M.476 indica centro 1700 Hz y contempla equipos antiguos a 1500 Hz. Para el servicio SITOR HF, la [guía NWS](https://www.weather.gov/marine/uscg_broadcasts) distingue frecuencia asignada y dial con offset de 1,7 kHz. No se incorporaron horarios ni se verificó ninguna emisora operativa local.

## Comportamiento del receptor

- CCIR 476: siete bits síncronos, cuatro B y tres Y. B representa el tono alto. Las secuencias emitidas de la tabla UIT se ensamblan con el primer elemento en el bit menos significativo.
- Adquisición mediante cuatro señales de phasing alternas ALPHA/REP; recuperación gradual del reloj a partir de transiciones. Sin bits start/stop de RTTY.
- Diversidad: la segunda copia llega cinco slots de carácter después de la primera. Son **35 bits / 350 ms entre comienzos**, con **280 ms entre el fin de la primera y el comienzo de la segunda**. No confundir esas dos medidas.
- Si una copia es válida se utiliza; dos copias válidas iguales se aceptan. Dos válidas diferentes se consideran dañadas, siguiendo M.625 §4.3. Se imprimen `�` para erasure y `□` para figuras no asignadas/admitidas. Los contadores no atribuyen recuperaciones de caracteres a señales idle.
- Alfabeto internacional de M.476: cifras 0–9 y signos asignados. F/G/H no tienen figura asignada; D corresponde a WRU. Las variantes nacionales/amateur no se presentan como idénticas. BELL no produce sonido ni acciones.
- Texto acotado; una pausa de señal reinicia adquisición y conserva el texto recibido. No hay transmisor ni procedimiento de respuesta ARQ.

La app muestra texto, cabeceras `ZCZC`/`NNNN` recibidas y estadísticas FEC. Todavía no extrae una lista estructurada de mensajes, deduplica transmisiones ni filtra B1/B2. Requiere una secuencia de phasing; adquisición en medio del mensaje, B selectivo y SITOR-A son trabajo pendiente.

## Evidencia de prueba

`script/generate_navtex_fixtures.py` usa las cadenas B/Y de la tabla UIT para formar un transmisor matemático independiente del decoder. El manifiesto `Tests/RadioCoreTests/Fixtures/navtex-manifest.json` conserva sus hashes y parámetros. Diez casos de audio comprueban 8 kHz mono y 44,1 kHz estéreo, inicio/fase desplazados, ruido sintético de 18 dB, una copia dañada, dos copias perdidas, dos válidas discrepantes, inversión, 100,1 baud y reanudación después de silencio. Incluyen todos los dígitos y signos internacionales imprimibles, además de BELL sin acción.

El interleave publicado de **NAUTICAL** en la [documentación del autor de JNX](https://vps.arachnoid.com/JNX/index.html) se alimenta directamente como vector de bytes: cinco casos verifican orden y selección de copias sin invocar un encoder. Se usa su secuencia; los tiempos se fijan desde UIT. Su explicación temporal de tres caracteres no se adopta como norma.

Un WAV adicional a 48 kHz tiene L y R en fase opuesta. Tres casos comprueban que cada canal decodifica el mensaje y la mezcla se cancela. Un canal ausente produce error explícito; el ring también comprueba mezcla de tres canales y copia de uno. Es evidencia matemática y de software; **recepción RF real y captura CoreAudio extremo a extremo siguen pendientes**.
