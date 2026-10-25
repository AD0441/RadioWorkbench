# RadioWorkbench · 0.15.0

[Español](#es) · [English](#en) · [Historial / Changelog](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/HISTORIAL.md) · [Validación / Validation](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/VALIDACION.md)

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/C0C51WQ1T0)

<a id="es"></a>
## Español

RadioWorkbench es un receptor y laboratorio de radio nativo para **macOS y Apple Silicon**. Decodifica audio de un receptor, del micrófono o de archivos; consulta emisoras, condiciones y satélites; y estudia enlaces HF y VHF/UHF con modelos de propagación y terreno.

Usa SwiftUI, CoreAudio/AVFoundation, Accelerate y MapKit. MultiMode Cocoa se utilizó como referencia funcional documentada: no se incorporan su ejecutable, código, NIB ni recursos comerciales. Las muestras y fotografías personales de pruebas permanecen fuera de GitHub.

### Plataforma y estado

- Aplicación experimental. Bundle mínimo **macOS 14**, ejecutable **arm64 para M1 y posteriores**, probado en un MacBook Pro M1 con macOS 27.2. No se ha verificado físicamente cada versión intermedia de macOS.
- CWKit requiere macOS 15; el runtime opcional DSD-neo requiere macOS 26 y descarga separada. La app no se distribuye para Intel, iOS, Windows o Linux. Sparkle conserva los componentes universales arm64/x86_64 de su distribución oficial.
- La rama de desarrollo contiene **0.15.0**, en el [PR #2, todavía borrador](https://github.com/AD0441/RadioWorkbench/pull/2). La descarga pública sigue siendo **0.11.0 preliminar**. Una versión en desarrollo no equivale a una publicación descargable.
- Firma local **ad hoc**, sin Developer ID ni notarización. [Procedimiento de Apple para la primera apertura](https://support.apple.com/es-cl/102445).

### Descargar

[Publicación 0.11.0](https://github.com/AD0441/RadioWorkbench/releases/tag/v0.11.0) · [ZIP macOS arm64](https://github.com/AD0441/RadioWorkbench/releases/download/v0.11.0/RadioWorkbench-0.11.0-macos-arm64.zip) · [SHA-256](https://github.com/AD0441/RadioWorkbench/releases/download/v0.11.0/SHA256SUMS).

Extrae el ZIP y mueve `RadioWorkbench.app` a Aplicaciones. macOS pide permiso de micrófono al iniciar la captura, incluso con un cable virtual. Las funciones incorporadas después de 0.11.0 requieren compilar la rama de desarrollo o una publicación posterior.

### Novedades 0.15.0

- **Biblioteca I/Q SigMF:** importación/exportación del par de muestras y metadatos, SHA-512, anotaciones conservadas y papelera reversible. Prepara SatDump con formato, tasa, RF y fecha conocidos; el procesamiento se inicia por separado.
- **Asistente de conexión:** revisa fuente/canal, perfil SDR, nivel, continuidad e integridad; exporta un diagnóstico local sin audio ni mensajes recibidos.
- **Contadores de protocolo:** CRC AX.25, paridad RTCM 2 y 4/7/cadencia SITOR-A. Son observaciones del decodificador, no porcentajes de entrega ni SNR RF.
- **Comparación A/B:** dos ajustes sobre el mismo archivo, ejecuciones consecutivas, tiempos, texto y validaciones disponibles. Modos de texto, hasta diez minutos/1 GB; no declara automáticamente qué resultado es correcto.
- **Actualizaciones Sparkle 2.10.0:** canal HTTPS y firmas Ed25519, comprobación automática optativa y descarga/instalación mediante acción del usuario. El canal inicial firmado está vacío; no ofrece un paquete 0.15.0 inexistente.
- Skills de desarrollo instaladas: SwiftUI Expert, Swift Testing Pro y `radioworkbench-quality`. Son herramientas de Codex, no módulos ejecutados por la app. **La traducción completa de la interfaz español/inglés sigue pendiente**; este README sí está en ambos idiomas.

[Uso, formatos admitidos y límites 0.15.0](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/RELEASE-0.15.0.md) · [Canal de actualizaciones](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/updates/README.md).

### Funciones y límites

| Área | Disponible | Límites principales |
|---|---|---|
| Texto | Morse/CW manual y CWKit, RTTY ITA2/ASCII 7/8, BPSK31, FT8/FT4, MT63 500/1000/2000 corto/largo | ASCII sin alfabetos nacionales; MT63 sin CRC global ni SNR calibrado |
| Tonos | DTMF, 51 CTCSS, ocho familias Selcall, análisis FSK | DCS y CHU pendientes |
| Mensajes | DSC MF/HF/VHF con ECC, ALE 2G, POCSAG 512/1200/2400, FLEX 1600/3200/6400, SITOR-A, DGPS MSK/RTCM 2, NAVTEX/SITOR-B, AX.25/APRS AFSK1200, ACARS/ADS-C/CPDLC por AM | Interpretación DSC parcial; sin ALE 3G, ReFLEX, VDL2 ni HFDL; SITOR-A es RX pasivo y DGPS no calcula una solución de navegación |
| Voz digital | DSD-neo opcional: DMR con escucha durante recepción, TS1/TS2; P25 I/II, NXDN, D-STAR, YSF, M17 y dPMR | Un canal RF; disponibilidad sujeta al runtime y al sistema |
| Imágenes | 41 SSTV, WEFAX HF, APT y cinco Hell por pulsos | WEFAX con inicio manual; APT sin calibración radiométrica/georreferenciación; Hell sin OCR/FSK Hell/Hell 80 |
| Entrada y biblioteca | Micrófono/USB/cable virtual, PCM TCP local, canal explícito, escuchas anotadas con audio opcional, SigMF y taller con 77 referencias | Audio no equivale a I/Q; SigMF admite un subconjunto de muestras crudas 1.0–1.2, no tar/colecciones |
| Consulta y mapas | EiBi/HFCC, favoritas/avisos, SUBTEL, repetidoras, APRS-IS, satélites, historial TX → RX con filtros de fecha/hora/antena | Fuentes y cachés con fechas; permiso o listado no demuestra actividad actual |
| Condiciones y cálculo | NOAA, D-RAP, Band Info, ionosondas, ITU-R P.533/P.372 y NTIA ITM con DEM | Predicción/modelo y observación se presentan por separado; no garantizan un contacto |

SSTV incluye Martin M1–M4, Scottie S1–S4/DX, PD50–PD290, Robot 36/72, Pasokon P3/P5/P7, Wraase SC2-180 y extensiones MMSSTV MP/MR/ML/MP-N/MC-N; VIS clásico, 16 bits y N-VIS de 24 bits. Calibración centro/reloj, control de ruido, ppm y rango de color. Sin cabecera, elegir formato e inicio manual. Las 41 variantes tienen pruebas matemáticas; se completó una prueba acústica Robot36C con el micrófono del Mac, sin validar con ello todos los transmisores en RF. [Catálogo SSTV](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/SSTV-MODOS.md) · [Prueba acústica](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/MICROFONO.md).

APT sirve para archivos históricos: no se anuncian las emisiones NOAA 15/18/19 como un servicio actual. DRM, WSPR/otros WSJT-X, AIS, RDS, DAB, LORAN-C y Globe Wireless siguen como candidatos o no disponibles. [Estado de los modos](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/DECODIFICADORES-EXTRA.md) · [Motores](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/GITHUB-MOTORES.md) · [SITOR-A/DGPS/FLEX](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/RELEASE-0.14.0.md) · [MT63/ALE](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/INTEGRATIONS-0.10.md).

### Audio desde SDR++

1. Elige un decodificador y prueba **Ejemplo** con una señal sintética identificada.
2. Selecciona dispositivo y canal en **Entrada de audio**. Para VB-Cable, elige ese cable como salida Audio/New Audio de SDR++ y como entrada aquí, preferiblemente a 48 kHz. El cable se instala por separado. Mezclar señales de fases opuestas puede cancelarlas.
3. Configura demodulación, filtro RF y tonos según la ficha del modo. No todos los protocolos aceptan el audio de un altavoz o los filtros de voz. La app selecciona su propia entrada sin cambiar el dispositivo predeterminado de macOS.
4. Pulsa **Escuchar** o **Abrir audio**. Puedes exportar texto/JSON/PNG según el modo. El asistente no inicia el micrófono por sí solo. Rigctl permite enviar frecuencia/modo/ancho solo tras habilitarlo y pulsar Enviar, con lectura de confirmación.

| Señal | Demodulación / filtro RF inicial | Audio necesario |
|---|---|---|
| CW, RTTY, PSK31, NAVTEX, SITOR-A, DGPS | CW/USB; normalmente 2,4–3 kHz, según señal | Centro/velocidad/shift propios; DGPS es MSK en audio SSB, no discriminador FM |
| MT63 / ALE 2G | USB, 3 kHz inicial | MT63: bloque 500/1000/2000 Hz; ALE: ocho tonos 750–2500 Hz |
| DSC MF/HF / VHF | USB 2,4 kHz / NFM 16 kHz inicial | HF: 100 baud, shift 170 Hz; VHF: discriminador plano, 1300/2100 Hz, 1200 baud |
| AX.25 / CTCSS / Selcall | FM/NFM, 12–25 kHz según servicio | 1200/2200 Hz / subaudio 50–300 Hz / secuencia completa |
| POCSAG / FLEX / voz digital | FM/NFM, ancho según canal/protocolo | Discriminador plano; sin squelch, de-emphasis ni filtros que corten datos |
| ACARS VHF | AM, 10–12,5 kHz | Tonos 1200/2400 Hz |
| SSTV / WEFAX / Hell | USB HF; SSTV también FM según emisión | SSTV: cabecera/vídeo 1100–2300 Hz; fax: 1500–2300 Hz; Hell: ancho por variante |
| APT de archivo | FM, unos 50 kHz | Subportadora AM 2400 Hz y audio hasta unos 5 kHz; sin de-emphasis |

Son puntos de partida, no anchos universales. La ficha de la variante y el servicio concreto prevalecen. [Presets de audio](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/SDR-AUDIO-PRESETS.md) · [Packet](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/PACKET.md) · [ACARS](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/ACARS.md) · [NAVTEX](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/NAVTEX.md).

### Planificación, terreno y datos

La guía conserva EiBi sin conexión y cruza candidatos HFCC por frecuencia/horario/idioma. Sitio y potencia son datos **programados**, no mediciones en tiempo real ni prueba de identidad. **Planificar escucha** copia nombre/frecuencia aunque falten coordenadas; **Registrar escucha en biblioteca** anota fecha, antena, resultado y audio opcional.

El Planificador HF separa **escucha RX** de **enlace bilateral A → B/B → A**. P.533/P.372 utiliza mes UTC, R12 y presupuesto de enlace; no convierte spots o condiciones solares en garantía de recepción. NOAA/ionosondas conservan fecha y procedencia. PSK Reporter/RBN son observaciones remotas, no pruebas de recepción en el Mac.

La cobertura VHF/UHF calcula cada celda de una malla 65 × 65 o 129 × 129 con NTIA ITM y el perfil DEM completo TX→celda, combinando terreno **AMSL + antena AGL** y conservando sombras de montañas. Apple Maps aporta contexto visual; la elevación proviene de Mapzen Terrain Tiles. Se muestran resolución y avisos; el horizonte de Tierra lisa es una referencia opcional desactivada inicialmente. [Método y evidencia](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/TERRAIN-COVERAGE.md).

Satélites usa frecuencias AMSAT/SatNOGS, GP CelesTrak con alternativa AMSAT, SGP4/SDP4, observador WGS84, Doppler y próximos pases RF en 60 minutos. No equivale a visibilidad óptica ni a un porcentaje medido de éxito. [Consultas](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/CONSULTAS.md) · [Propagación](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/PROPAGACION.md) · [Actividad y terreno](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/ACTIVIDAD-Y-TERRENO.md).

El audio se procesa localmente. DSD guarda un WAV temporal hasta la siguiente sesión; la captura diagnóstica requiere acción explícita. Datos y perfiles residen en Application Support. Las consultas en línea contactan a sus proveedores. PSK Reporter comparte cuadrícula Maidenhead tras activarlo; APRS-IS envía indicativo/ubicación redondeada para filtrar. Las peticiones DEM permiten inferir la región consultada; Apple Maps realiza sus propias consultas. Sparkle consulta GitHub al pedir una comprobación o activar búsquedas automáticas. La clave privada de publicación no se incluye en la app ni en GitHub.

### Compilar y verificar

Toolchain probado: **Swift 6.4, SDK macOS 27.0, arm64**, CMake y herramientas C/C++. Las fuentes usan APIs del SDK 27 con rutas anteriores protegidas por disponibilidad; el mínimo del bundle no significa que un SDK 14 pueda compilar el proyecto.

```sh
git clone https://github.com/AD0441/RadioWorkbench.git
cd RadioWorkbench
git switch feat/dmr-reception-review
bash script/test.sh -c release
bash script/build_and_run.sh --build-only
open dist/RadioWorkbench.app
```

SwiftPM descarga Sparkle 2.10.0, fijado en `Package.resolved`. `RADIO_BUILD_PATH` permite una caché temporal y `RADIO_OUTPUT_APP_BUNDLE` elige el bundle de salida. `dist/` está excluido de Git. Conservar la entrega actual y la anterior; retirar cachés y extracciones regenerables tras validar. El callback de audio copia al ring preasignado; DSP, archivos y helpers trabajan fuera de él. Texto y waterfall tienen límites; falta una comparación medida con MultiMode bajo Rosetta.

[Resultados y omisiones de las pruebas](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/VALIDACION.md) · [Evidencia 0.15.0](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/validation/release-0.15.0.json). Las pruebas sintéticas y unitarias no garantizan recepción física con cualquier equipo o señal.

### Componentes y agradecimientos

SatelliteKit, ft8_lib, CWKit y libacars conservan sus avisos MIT; acarsdec y multimon-ng, GPL v2/v2+; MT63/fldigi y ALE/KiwiSDR, GPL v3+. Fuentes y modificaciones correspondientes se incluyen con los helpers. DSD-neo es un runtime opcional externo con sus propias licencias. Se conservan avisos de ITU-R HF, NTIA ITM y las atribuciones de Mapzen; los datos AMSAT/SatNOGS incluyen CC BY-SA 4.0. Sparkle 2.10.0 conserva su licencia en el paquete. [Integraciones](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/INTEGRATIONS-0.9.md) · [Cambios MT63/ALE](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/INTEGRATIONS-0.10.md) · [MultiMode](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/REVISION-MULTIMODE.md).

Los componentes externos mantienen sus condiciones. El repositorio no les asigna una licencia nueva ni declara una licencia global para el código propio.

**Gracias a G4ZJH por su aporte y por la idea de ofrecer RadioWorkbench en español e inglés.**

Puedes apoyar el desarrollo en [Ko-fi](https://ko-fi.com/C0C51WQ1T0).

<a id="en"></a>
## English

RadioWorkbench is a native **macOS and Apple Silicon** radio receiver and laboratory. It decodes receiver, microphone or file audio; provides station, propagation and satellite information; and studies HF and VHF/UHF links using propagation and terrain models.

It uses SwiftUI, CoreAudio/AVFoundation, Accelerate and MapKit. MultiMode Cocoa served as a documented functional reference: its executable, code, NIBs and commercial resources are not included. Personal test photographs and recordings remain outside GitHub.

### Platform and status

- Experimental application. The bundle requires **macOS 14 or later**, with an **arm64 executable for M1 and later**, tested on an M1 MacBook Pro running macOS 27.2. Every intermediate macOS version has not been physically tested.
- CWKit requires macOS 15; the optional DSD-neo runtime requires macOS 26 and a separate download. The app is not distributed for Intel Macs, iOS, Windows or Linux. Sparkle retains the universal arm64/x86_64 components of its official distribution.
- The development branch contains **0.15.0** in [PR #2, still a draft](https://github.com/AD0441/RadioWorkbench/pull/2). The public download remains the **0.11.0 prerelease**. Development source is not a downloadable release.
- **Ad hoc local signature**, without Developer ID signing or notarization. [Apple's first-launch instructions](https://support.apple.com/102445).

### Download

[0.11.0 release](https://github.com/AD0441/RadioWorkbench/releases/tag/v0.11.0) · [macOS arm64 ZIP](https://github.com/AD0441/RadioWorkbench/releases/download/v0.11.0/RadioWorkbench-0.11.0-macos-arm64.zip) · [SHA-256](https://github.com/AD0441/RadioWorkbench/releases/download/v0.11.0/SHA256SUMS).

Extract the ZIP and move `RadioWorkbench.app` to Applications. macOS requests microphone permission when capture starts, including with virtual audio devices. Features added after 0.11.0 require building the development branch or a later release.

### What's new in 0.15.0

- **SigMF I/Q library:** import/export sample and metadata pairs, SHA-512, preserved annotations and reversible trash. Prepare SatDump with known sample format/rate, RF frequency and capture time; processing starts separately.
- **Connection assistant:** source/channel, SDR profile, level, continuity and protocol integrity checks; export a local diagnostic without audio or received messages.
- **Protocol counters:** AX.25 CRC, RTCM 2 parity and SITOR-A 4-of-7/cadence. These are decoder observations, not delivery percentages or RF SNR.
- **A/B comparison:** two configurations applied consecutively to the same file, reporting time, text and available checks. Text modes, up to ten minutes/1 GB; no automatic claim that either result is correct.
- **Sparkle 2.10.0 updates:** HTTPS feed and Ed25519 signatures, optional automatic checks, user-initiated download/installation. The initial signed feed is empty; it does not offer a nonexistent 0.15.0 update archive.
- Installed development skills: SwiftUI Expert, Swift Testing Pro and `radioworkbench-quality`. These are Codex tools, not app runtime modules. **Full Spanish/English interface localization is still pending**; this README is available in both languages.

[0.15.0 usage, supported formats and limits](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/RELEASE-0.15.0.md) · [Update feed](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/updates/README.md). Detailed supporting documents are currently in Spanish.

### Features and limits

| Area | Available | Main limits |
|---|---|---|
| Text | Manual Morse/CW and CWKit, RTTY ITA2/7-bit and 8-bit ASCII, BPSK31, FT8/FT4, MT63 500/1000/2000 short/long | ASCII without national alphabets; MT63 has no message-wide CRC or calibrated SNR |
| Tones | DTMF, 51 CTCSS tones, eight Selcall families, FSK analysis | DCS and CHU pending |
| Messages | MF/HF/VHF DSC with ECC, ALE 2G, POCSAG 512/1200/2400, FLEX 1600/3200/6400, SITOR-A, MSK/RTCM 2 DGPS, NAVTEX/SITOR-B, AX.25/APRS AFSK1200, ACARS/ADS-C/CPDLC through AM audio | Partial DSC interpretation; no ALE 3G, ReFLEX, VDL2 or HFDL; SITOR-A is passive RX and DGPS does not compute a navigation solution |
| Digital voice | Optional DSD-neo: live DMR voice monitoring, TS1/TS2; P25 I/II, NXDN, D-STAR, YSF, M17 and dPMR | One RF channel; runtime and OS requirements apply |
| Images | 41 SSTV formats, HF WEFAX, APT and five pulsed Hell variants | Manual WEFAX start; no APT radiometric calibration/georeferencing; no OCR, FSK Hell or Hell 80 |
| Input and library | Microphone/USB/virtual cable, local TCP PCM, explicit channel, listening logs with optional audio, SigMF and 77 workshop references | Audio is not I/Q; SigMF supports a raw-sample subset of 1.0–1.2, without tar archives/collections |
| Queries and maps | EiBi/HFCC, favorites/alerts, SUBTEL, repeaters, APRS-IS, satellites, historical TX → RX paths with date/time/antenna filters | Timestamped sources/caches; a permit or listing does not prove current activity |
| Conditions and models | NOAA, D-RAP, Band Info, ionosondes, ITU-R P.533/P.372 and NTIA ITM with DEM | Models and observations are presented separately; neither guarantees a contact |

SSTV includes Martin M1–M4, Scottie S1–S4/DX, PD50–PD290, Robot 36/72, Pasokon P3/P5/P7, Wraase SC2-180 and MMSSTV MP/MR/ML/MP-N/MC-N extensions; classic, 16-bit and 24-bit N-VIS headers. Center/clock calibration, noise controls, ppm and color-range adjustment are available. Without a header, choose the format and start position manually. All 41 variants have mathematical tests; a Robot36C acoustic reception was completed using the Mac microphone, which does not validate every transmitter over RF. [SSTV catalog](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/SSTV-MODOS.md) · [Acoustic test](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/MICROFONO.md).

APT is useful for historical recordings: NOAA 15/18/19 transmissions are not advertised as a current service. DRM, WSPR/other WSJT-X modes, AIS, RDS, DAB, LORAN-C and Globe Wireless remain candidates or unavailable. [Mode status](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/DECODIFICADORES-EXTRA.md) · [Engines](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/GITHUB-MOTORES.md) · [SITOR-A/DGPS/FLEX](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/RELEASE-0.14.0.md) · [MT63/ALE](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/INTEGRATIONS-0.10.md).

### Audio from SDR++

1. Select a decoder and try **Ejemplo** using an identified synthetic signal.
2. Select the device and channel under **Entrada de audio**. For VB-Cable, select the cable as SDR++ Audio/New Audio output and as the app input, preferably at 48 kHz. Install the cable separately. Mixing opposite-phase signals can cancel them.
3. Configure demodulation, RF filter and tones using the mode's reception profile. Speaker audio and voice filters are unsuitable for some protocols. The app selects its own input without changing the macOS default device.
4. Click **Escuchar** or **Abrir audio**. Export text/JSON/PNG depending on the mode. The assistant does not start microphone capture automatically. Optional Rigctl sends frequency/mode/bandwidth only after enabling it and clicking Send, with readback confirmation.

| Signal | Demodulation / initial RF filter | Required audio |
|---|---|---|
| CW, RTTY, PSK31, NAVTEX, SITOR-A, DGPS | CW/USB; typically 2.4–3 kHz, depending on signal | Mode-specific center/rate/shift; DGPS uses MSK in SSB audio, not an FM discriminator |
| MT63 / ALE 2G | USB, initially 3 kHz | MT63: 500/1000/2000 Hz block; ALE: all eight tones, 750–2500 Hz |
| MF/HF / VHF DSC | USB 2.4 kHz / initially NFM 16 kHz | HF: 100 baud, 170 Hz shift; VHF: flat discriminator, 1300/2100 Hz, 1200 baud |
| AX.25 / CTCSS / Selcall | FM/NFM, 12–25 kHz depending on service | 1200/2200 Hz / 50–300 Hz subaudio / complete tone sequence |
| POCSAG / FLEX / digital voice | FM/NFM, channel/protocol-specific bandwidth | Flat discriminator; no squelch, de-emphasis or filters that remove data |
| VHF ACARS | AM, 10–12.5 kHz | 1200/2400 Hz tones |
| SSTV / WEFAX / Hell | HF USB; SSTV may also use FM | SSTV: header/video 1100–2300 Hz; fax: 1500–2300 Hz; Hell: variant-specific bandwidth |
| Archived APT | FM, about 50 kHz | 2400 Hz AM subcarrier and audio to about 5 kHz; no de-emphasis |

These are starting points, not universal service bandwidths. Follow the variant's profile and the actual service. [Audio presets](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/SDR-AUDIO-PRESETS.md) · [Packet](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/PACKET.md) · [ACARS](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/ACARS.md) · [NAVTEX](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/NAVTEX.md).

### Planning, terrain and data

The guide caches EiBi offline and matches HFCC candidates by frequency/time/language. Sites and power are **scheduled data**, not real-time measurements or identity proof. **Planificar escucha** copies name/frequency even without coordinates; **Registrar escucha en biblioteca** records time, antenna, outcome and optional audio.

The HF planner separates **RX listening** from **two-way A → B/B → A links**. P.533/P.372 uses UTC month, R12 and a link budget; it does not turn spots or solar conditions into guaranteed reception. NOAA/ionosonde data retain timestamps and provenance. PSK Reporter/RBN reports are remote observations, not proof of reception on this Mac.

VHF/UHF coverage evaluates each cell in a 65 × 65 or 129 × 129 grid using NTIA ITM and the full TX→cell DEM profile, combining **AMSL ground elevation + AGL antenna height** and retaining mountain shadows. Apple Maps provides visual context; Mapzen Terrain Tiles provide elevation. Resolution and warnings are shown; the smooth-Earth horizon is an optional reference, initially off. [Method and evidence](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/TERRAIN-COVERAGE.md).

Satellites uses AMSAT/SatNOGS frequencies, CelesTrak GP with an AMSAT fallback, SGP4/SDP4, a WGS84 observer, Doppler and RF passes in the next 60 minutes. These are not optical-visibility forecasts or measured success percentages. [Queries](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/CONSULTAS.md) · [Propagation](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/PROPAGACION.md) · [Activity and terrain](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/ACTIVIDAD-Y-TERRENO.md).

Audio is processed locally. DSD keeps a temporary WAV until the next session; diagnostic recording requires an explicit action. Data/profiles are stored in Application Support. Online queries contact their respective providers. PSK Reporter shares a Maidenhead square after activation; APRS-IS sends callsign/rounded location for filtering. DEM tile requests can reveal the queried region; Apple Maps makes its own requests. Sparkle contacts GitHub when you request a check or enable automatic checks. The private publishing key is not included in the app or GitHub.

### Build and verify

Verified toolchain: **Swift 6.4, macOS 27.0 SDK, arm64**, CMake and C/C++ tools. Source uses SDK 27 APIs with availability-guarded older execution paths; the bundle minimum does not mean an SDK 14 toolchain can build it.

```sh
git clone https://github.com/AD0441/RadioWorkbench.git
cd RadioWorkbench
git switch feat/dmr-reception-review
bash script/test.sh -c release
bash script/build_and_run.sh --build-only
open dist/RadioWorkbench.app
```

SwiftPM downloads Sparkle 2.10.0, pinned in `Package.resolved`. `RADIO_BUILD_PATH` selects a temporary cache and `RADIO_OUTPUT_APP_BUNDLE` chooses the output bundle. `dist/` is excluded from Git. Retain the current and previous deliveries; remove regenerable caches/extractions after validation. The audio callback copies into a preallocated ring; DSP, files and helpers run outside it. Text/waterfall histories are bounded; there is no measured comparison against MultiMode under Rosetta yet.

[Test results and skipped checks](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/VALIDACION.md) · [0.15.0 evidence](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/validation/release-0.15.0.json). Synthetic/unit tests do not guarantee physical reception with arbitrary equipment or signals.

### Components and thanks

SatelliteKit, ft8_lib, CWKit and libacars retain MIT notices; acarsdec and multimon-ng use GPL v2/v2+; MT63/fldigi and ALE/KiwiSDR use GPL v3+. Corresponding sources/modifications ship with the helpers. DSD-neo is an optional external runtime with its own licenses. ITU-R HF and NTIA ITM notices and Mapzen attribution are retained; AMSAT/SatNOGS data include CC BY-SA 4.0 attribution. Sparkle 2.10.0 retains its license in the bundle. [Integrations](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/INTEGRATIONS-0.9.md) · [MT63/ALE changes](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/INTEGRATIONS-0.10.md) · [MultiMode](https://github.com/AD0441/RadioWorkbench/blob/feat/dmr-reception-review/docs/REVISION-MULTIMODE.md).

Third-party components retain their own terms. This repository neither relicenses them nor declares an overall license for its own code.

**Thank you to G4ZJH for the contribution and the idea of offering RadioWorkbench in Spanish and English.**

You can support development on [Ko-fi](https://ko-fi.com/C0C51WQ1T0).
