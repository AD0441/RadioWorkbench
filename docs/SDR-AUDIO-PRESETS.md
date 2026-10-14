# Audio desde SDR++ y parámetros de imagen

En 0.6, **ACARS VHF** ya recibe audio AM con acarsdec: filtro RF inicial 10–12,5 kHz, audio útil 300–3500 Hz, salida del cable virtual 48 kHz y squelch/reducción de ruido desactivados. La app convierte la entrada a 12 kHz conservando continuidad entre bloques. [ACARS.md](ACARS.md) incluye muestra, contrato del motor y límites; no equivale a VDL2 ni HFDL.

Actualización 0.5: **Packet/APRS AFSK1200** y **CTCSS** ya se reciben en el motor nativo. Para APRS utiliza NFM, ancho RF inicial 12–15 kHz y audio 300–3000 Hz que conserve 1200/2200 Hz; centro 1700 Hz. Para CTCSS utiliza NFM, ancho RF 12,5 kHz y audio que conserve **50–300 Hz**; desactiva el pasa-altos de voz de 300 Hz. El detector busca automáticamente 51 tonos y confirma aproximadamente en 2,5 s. El selector de dispositivo y canal se aplica a ambos modos. [PACKET.md](PACKET.md) y [TONOS.md](TONOS.md) documentan fuentes, pruebas y límites. SSTV ya está integrado; el catálogo detalla las 41 variantes implementadas.

Investigación de fuentes primarias: **12-10-2026**. SSTV, APT y fax deben reconstruir imágenes dentro de RadioWorkbench. Los motores externos de `GITHUB-MOTORES.md` son referencias/opciones futuras; su existencia no satisface esa implementación.

## Separar RF, audio y el modo que se decodifica

`AM`, `FM/NFM`, `USB` y `LSB` son elecciones del demodulador **RF en SDR++**. `SSTV`, `APT`, `WEFAX`, `RTTY` y otros son formatos que nuestra app decodifica después. El ancho RF se expresa en Hz del canal del receptor; el rango de audio es la banda de frecuencias que debe conservar el sonido entregado a la app. Tampoco son la tasa de muestreo: **48000 muestras/s** es el transporte recomendado para el cable virtual existente.

APT usa RF **FM**, aunque la imagen module en amplitud una subportadora de audio de 2400 Hz. Elegir AM en SDR++ porque el decoder APT usa envolvente AM sería incorrecto. Para WEFAX HF, NOAA prescribe **USB** y un dial 1.9 kHz por debajo de la frecuencia asignada. Fuentes: [NOAA KLM, §4.2](https://www.ncei.noaa.gov/pub/data/cdo/documentation/podguides/N-15%20thru%20N-19/pdf/2.1%20Section%204.0%20Real%20Time%20Data%20Systems%20for%20Local%20Users%20.pdf), [NWS FAQ, pregunta 20](https://www.weather.gov/marine/faq).

## Ruta prioritaria: el VB-Cable ya existente

La inspección local comunicada por el agente principal encontró **VB-Cable, 48000 Hz, 2 canales**. Esa presencia no prueba todavía una conexión de audio extremo a extremo ni una recepción RF real. No hace falta instalar BlackHole para esta ruta.

1. En SDR++, elegir el stream de radio correspondiente en el panel de salida **Sinks**.
2. Elegir el proveedor **Audio** o **New Audio**, según el módulo disponible en esa build.
3. En el combo de dispositivos de ese proveedor, elegir **VB-Cable**; New Audio añade el nombre de la API al dispositivo, por ejemplo `[Core Audio] VB-Cable` si esa es la enumeración que devuelve PortAudio.
4. En el segundo combo, elegir **48000**. En RadioWorkbench, elegir **VB-Cable** como dispositivo de entrada; seleccionar un canal válido y mostrar la tasa de captura real.

RadioWorkbench 0.3 ofrece **Canal de audio**: mezcla, L, R y canales adicionales del dispositivo/archivo. Se aplica tanto al WAV como al tap de captura. Elegir un canal ausente produce un error. Evitar mezclar dos receptores distintos o señales de fase opuesta; la prueba de fase opuesta comprueba que la mezcla puede cancelar el contenido. Este selector pertenece a la entrada PCM de los modos nativos; no es una ruta IQ.
5. Aplicar el modo y ancho RF del preset en SDR++. Comprobar nivel y espectro de entrada en la app antes de decodificar. El selector de modo de nuestra app no modifica SDR++ por sí mismo.

Los nombres de proveedor y los dos combos se verificaron en código upstream: [portaudio_sink: Audio](https://github.com/AlexandreRouma/SDRPlusPlus/blob/master/sink_modules/portaudio_sink/src/main.cpp), [new_portaudio_sink: New Audio](https://github.com/AlexandreRouma/SDRPlusPlus/blob/master/sink_modules/new_portaudio_sink/src/main.cpp), [SinkManager](https://github.com/AlexandreRouma/SDRPlusPlus/blob/master/core/src/signal_path/sink.cpp). Los combos son dispositivo y tasa de muestreo, sin asumir que una versión traducida muestre una etiqueta idéntica. La [página oficial VB-Audio](https://vb-audio.com/Cable/?source=korben.info) declara paquete macOS Intel/Apple Silicon y paso de audio entre aplicaciones; sus nombres Windows `CABLE Input`/`CABLE Output` no deben reemplazar el nombre macOS observado.

Para las tres imágenes, empezar sin squelch, noise reduction, notch, efectos de voz, limitador o normalización dinámica. APT depende de amplitudes relativas de su audio: evitar AGC después de demodular RF y desactivar de-emphasis. Usar ganancia de salida fija que no recorte. Son elecciones de recepción propuestas para conservar el formato, no prueba de que la ruta local ya funcione.

En upstream, el demodulador NFM se etiqueta **FM**, tiene ancho inicial 12500 Hz y admite hasta 50000 Hz. Dispone de `Low Pass`, y declara de-emphasis permitido con modo inicial `None`. [nfm.h](https://github.com/AlexandreRouma/SDRPlusPlus/blob/master/decoder_modules/radio/src/demodulators/nfm.h), [FM DSP](https://github.com/AlexandreRouma/SDRPlusPlus/blob/master/core/src/dsp/demod/fm.h). No elegir WFM de radiodifusión con estéreo sólo para ampliar el filtro de APT.

BlackHole, si ya estuviera disponible, permite salida de SDR++ al dispositivo BlackHole e input homónimo en la app. Para monitor simultáneo, la [guía del proyecto](https://github.com/ExistentialAudio/BlackHole/wiki/Multi-Output-Device) describe Multi-Output y drift correction. [README](https://github.com/ExistentialAudio/BlackHole/blob/master/README.md) declara builds Intel/Apple Silicon. Loopback ofrece un [Pass-Thru](https://www.rogueamoeba.com/support/manuals/loopback/?page=passthru) que aparece como salida e input, o captura de una aplicación como fuente; mantener un único origen SDR y evitar mezclar micrófono/notificaciones. Son alternativas de routing, no decodificadores ni instalaciones realizadas.

## Tres presets prioritarios

Los anchos siguientes son **valores de partida de recepción**, no anchos normativos únicos de un protocolo. La tasa de transporte propuesta es 48 kHz para todos. El decodificador puede remuestrear internamente después de conservar el contenido requerido.

| Preset | RF en SDR++ | Ancho del filtro RF inicial | Audio que conservar | Valores del formato |
|---|---|---:|---:|---|
| SSTV HF, Martin M1/Scottie S1 | USB | 3000 Hz | 1000–2500 Hz | Negro 1500, blanco 2300, sync 1200; VIS también usa 1100/1300 Hz. |
| SSTV desde una emisión FM de VHF | FM/NFM, según la emisión real | 12500–25000 Hz | 1000–2500 Hz | El formato SSTV de audio es independiente de USB/FM RF. No asumir que una emisión VHF use M1/S1 sin VIS o selección manual. |
| WEFAX HF IOC576/120LPM | USB | 3000 Hz | 1000–2800 Hz | Negro 1500, gris 1900, blanco 2300 Hz; dial = asignada −1900 Hz; 0.5 s/línea. |
| NOAA APT de archivo | **FM** | **50000 Hz**, reajustable | 300–5000 Hz | Subportadora AM 2400 Hz; 4160 words/s, 2080 words/línea, 2 líneas/s. |

El intervalo de audio APT cubre aproximadamente 2400 ±2080 Hz con margen; esa elección se deriva de la tasa de video y necesita validación con grabaciones. Los presets no deben aplicar a APT el paso de voz 300–3000 Hz ni a SSTV un high-pass que suprima VIS 1100 Hz. El filtro RF APT de 50 kHz cabe en el máximo FM upstream y coincide con órdenes de magnitud de receptores APT de la [guía RF NOAA](https://repository.library.noaa.gov/view/noaa/13408/noaa_13408_DS1.pdf); no equivale a una medición de la señal recibida.

## SSTV: contrato para un fixture independiente

Fuente primaria: JL Barber, N7CXI, *Proposal for SSTV Mode Specifications*, Dayton 20-05-2000; [PDF íntegro accesible en espejo](https://www.classicsstv.com/downloads/daytonpaper.pdf), páginas PDF 2–4 y 12. El documento explica su procedencia y que es una propuesta técnica, no una norma internacional.

| Elemento | Frecuencia | Duración/orden |
|---|---:|---|
| Leader | 1900 Hz | 300 ms |
| Break | 1200 Hz | 10 ms |
| Segundo leader | 1900 Hz | 300 ms |
| Start VIS | 1200 Hz | 30 ms |
| 7 bits VIS | 1 →1100 Hz; 0 →1300 Hz | 30 ms cada uno, LSB primero |
| Paridad | 1100 Hz si los 7 bits tienen cantidad impar de unos; 1300 si par | 30 ms; paridad total par |
| Stop VIS | 1200 Hz | 30 ms |

M1: VIS **44/0x2C**, 320×256, scans **G/B/R**, 146.432 ms por color; sync 1200 Hz **4.862 ms** al comienzo de cada línea; porch y los tres separadores a 1500 Hz **0.572 ms** cada uno. Derivación: 446.446 ms/línea; 114.290176 s de líneas.

S1: VIS **60/0x3C**, 320×256, G/B/R, **138.240 ms** por color; dos separadores y porch a 1500 Hz **1.5 ms**, sync 1200 Hz **9 ms entre B y R**. Sólo la primera línea añade otro sync inicial de 9 ms. Derivación: 428.220 ms/línea; 109.633320 s con ese sync inicial. No añadir VIS a esos tiempos de imagen. Nivel de componente: `round(255 × (f−1500)/800)`, limitado a 0–255.

El fixture debe ejercitar el sync intermedio Scottie y colores distintos, además de un VIS con paridad equivocada y una captura que comienza después de VIS. Los tiempos derivados son aritmética de los parámetros, no capturas observadas. Evitar que el encoder de prueba y el decoder compartan la misma tabla privada: ese round-trip no detectaría un error común de timing.

## WEFAX: tonos, reloj y controles

[NWS FAQ](https://www.weather.gov/marine/faq) fija los tonos 1500/1900/2300 Hz, shift 800 Hz y offset USB −1.9 kHz. [Manual fldigi](https://www.w1hkj.org/FldigiHelp/wefax_page.html) documenta IOC576/288 y centro 1900 Hz; DWD puede usar shift 850 Hz. IOC es índice de cooperación, no una anchura fija de archivo; el [código fldigi](https://github.com/w1hkj/fldigi/blob/master/src/wefax/wefax.cxx) usa una anchura proporcional a `π × IOC` y trunca el entero. Para IOC576, 1809 o 1810 píxeles son decisiones de rasterización que deben quedar explícitas.

120 LPM = 500 ms/línea, independientemente de la tasa WAV. Con 48 kHz, son 24000 muestras/línea antes de drift/corrección de reloj. La implementación fldigi consultada usa start de **300 Hz** para IOC576 y **675 Hz** para IOC288, stop **450 Hz**; son frecuencias de la secuencia de conmutación de la imagen **después de demodular sus tonos**, no sustitutos del centro 1900 Hz. Soporta phasing invertido; su transmisor tiene 5% blanco en el borde y 95% negro, intercambiables. No tomar esa duración de transmisor como obligación para todos los servicios.

Prueba independiente propuesta: líneas de 500 ms con bloques negro/gris/blanco, transiciones de comienzo y un header de phasing separado. Verificar que una fila tardía no cambie de anchura y que ppm/offset permitan alinear una captura real. Una recepción manual puede empezar en imagen; debe indicar que la sincronía es manual, no afirmar adquisición automática de phasing.

## APT: geometría y sincronía verificadas

Fuente: [NOAA KLM Users Guide, revisión abril 2014](https://www.ncei.noaa.gov/pub/data/cdo/documentation/podguides/N-15%20thru%20N-19/pdf/2.1%20Section%204.0%20Real%20Time%20Data%20Systems%20for%20Local%20Users%20.pdf), §4.2, páginas impresas 4-52 a 4-57. Se revisaron visualmente figuras 4.2.3-2/3.

RF FM transporta AM a **2400 Hz**. Video: **4160 words/s**, **2080/línea**, **2 líneas/s**, dos imágenes de **909 píxeles**. Los 2080 words son posiciones de video, no 2080 muestras del WAV; obtener la envolvente antes de remuestrearla a ese reloj.

| Campo | Offset 0-based | Longitud words |
|---|---:|---:|
| Sync A / espacio A / imagen A / telemetría A | 0 / 39 / 86 / 995 | 39 / 47 / 909 / 45 |
| Sync B / espacio B / imagen B / telemetría B | 1040 / 1079 / 1126 / 2035 | 39 / 47 / 909 / 45 |

Sync A: 7 ciclos de 1040 Hz. Sync B: 7 pulsos a 832 pulsos/s. La figura fija nivel D/A bajo **11**, alto **244**, `T=1/4160 s`:

- A: 4 bajos + `(2 altos, 2 bajos)×7` +7 bajos =39 words.
- B: 4 bajos + `(3 altos, 2 bajos)×7` =39 words.

Usar correlación de patrones y reloj fraccional; comprobar A/B a 1040 words y líneas a 2080. Un simple corte cada 0.5 s sin adquirir sync produce un raster diagnóstico, no una imagen correctamente alineada. Una frame de telemetría tiene 128 líneas/64 s, con 16 wedges de 8 líneas; no atribuir canal térmico/visible ni temperatura sin leer telemetría.

## Frecuencias: distinguir ejemplo, historia y servicio verificado

NOAA-18 fue retirado **06-06-2025**; NOAA-19 **13-08-2025**; NOAA-15 **19-08-2025**. Son fechas finales de la actualización 20-08-2025 de [NESDIS](https://www.nesdis.noaa.gov/news/suspension-of-poes-data-users-after-june-16-2025-and-decommissioning). Las frecuencias APT que aparezcan para estos satélites son presets **históricos/de archivo**, no objetivos activos en octubre 2026. No equiparar HRPT/LRPT de satélites posteriores con APT.

El [RFAX NWS, edición 07-03-2025](https://www.weather.gov/media/marine/rfax.pdf), página PDF15, enumera CBV Playa Ancha 4228.0/8677.0/17146.4 kHz y CBM Punta Arenas 4322.0/8696.0 kHz, pero esa ficha chilena está fechada **23-09-2010**. Diales USB derivados: CBV **4226.1/8675.1/17144.5 kHz**; CBM **4320.1/8694.1 kHz**. No anunciar operación actual ni horarios confirmados desde esa ficha antigua. El mismo PDF prescribe offset −1.9 kHz y lista 120/576.

## Presets para el resto del catálogo

Son propuestas editables para recepción, no estándares universales ni modos ya implementados. Frecuencia de emisora, polaridad y rango de audio dependen del formato elegido. Para contenidos cuya fuente necesita IQ, la salida de voz de SDR++ no sustituye esa entrada.

| Modo | Demodulación RF propuesta | Filtro RF inicial | Audio a conservar / observación |
|---|---|---:|---|
| CW | CW o USB | 500 Hz, expandible | Pitch configurable, p.ej. 700 Hz; 400–1000 Hz como punto de partida. |
| RTTY | USB; LSB con polaridad configurada | 3000 Hz | 300–2800 Hz; baud/shift/mark deben ser editables. |
| PSK31 | USB | 3000 Hz | 300–2800 Hz; elegir portadora audio dentro de esa banda. |
| ACARS VHF | AM | 10000–12500 Hz | 300–3500 Hz; conservar tonos 1200/2400 Hz, remuestreo interno a 12 kHz. |
| SITOR-B/NAVTEX | USB | 2400 Hz | 1615/1785 Hz con centro 1700; centro/polaridad editables, 100 Bd/shift 170 Hz. Motor nativo colectivo desde 0.3. |
| AX.25/APRS 1200 | FM/NFM | 12500–25000 Hz | Conservar Bell202 1200/2200 Hz y banda 300–3000 Hz; sin squelch que corte paquetes. |
| ALE 2G | USB | 3000 Hz | Conservar toda la banda de voz; `gr-ale` necesita audio remuestreado a 8 kHz. |
| Hell | USB | 3000 Hz | 300–2800 Hz; variantes y portadora editables. |
| MT63 | USB | 3000 Hz | 300–2800 Hz para iniciar; variar con modo 500/1000/2000. |
| DSC MF/HF | USB | 3000 Hz | 300–2800 Hz; shift170 Hz/100 Bd, centro configurable. xng no toma WAV. |
| DSC VHF | FM/NFM | 25000 Hz | Banda que preserve 1300/2100 Hz y 1200 Bd; no confundir con el DSC MF/HF de xng. |
| DGPS | USB/CW para convertir baliza a audio | 3000 Hz | 300–1500 Hz inicialmente; centro editable. Alternativa real necesita pruebas del demodulador MSK. |
| LORAN-C | Captura IQ para análisis temporal | Por determinar con objetivo | Evitar preset genérico de voz: un monitor de envolvente no es navegación ni timing calibrado. |
| DTMF/tonos | Depende de la emisión: AM, FM o SSB | 3000 Hz en SSB; 12500–25000 en FM | 300–3000 Hz; conservar las dos frecuencias del símbolo. |
| Bit analysis | Depende del objetivo | Manual | Audio o IQ según señal; no preseleccionar un demodulador universal. |
| Globe Wireless | Sin preset validado | Manual | Especificación/fixtures pendientes; USB candidato no demuestra RX. |

Fuentes por formato: [fldigi modos](https://www.w1hkj.org/FldigiHelp/menus_page.html), [acarsdec](https://github.com/f00b4r0/acarsdec/blob/master/README.md), [xng NAVTEX](https://github.com/airframesio/xng/blob/master/docs/notes/NAVTEX.md), [xng DSC](https://github.com/airframesio/xng/blob/master/docs/notes/DSC.md), [Dire Wolf](https://github.com/wb2osz/direwolf/blob/master/README.md), [gr-ale](https://github.com/gat3way/gr-ale/blob/master/README.md). Los anchos/rangos propuestos necesitan ajuste y no se presentan como mediciones extraídas de esas fuentes.
