# RadioWorkbench · 0.13.0

Receptor y laboratorio de radio nativo para **macOS y Apple Silicon**. Permite decodificar audio de un receptor, del micrófono o de un archivo; consultar horarios y frecuencias; observar condiciones de bandas; y estudiar enlaces HF y VHF/UHF con modelos de propagación y terreno.

El proyecto usa SwiftUI, CoreAudio/AVFoundation, Accelerate y MapKit. La aplicación original MultiMode Cocoa se utilizó como referencia funcional documentada; el nuevo producto no incorpora su ejecutable, código, NIB ni recursos comerciales.

**Plataforma:** el bundle declara macOS 14 o posterior y el paquete publicado es **arm64 para M1 y posteriores**. Se ha probado en un MacBook Pro M1 con macOS 27.2. No se distribuyen binarios para Mac Intel, iOS, Windows o Linux; tampoco se ha verificado la ejecución física en todas las versiones macOS 14–26.

**Estado:** aplicación experimental en desarrollo. Las señales sintéticas y las pruebas unitarias validan el comportamiento implementado, pero no garantizan recepción RF bajo cualquier condición.

**Nuevo en 0.13.0:** registro explícito de escuchas sin audio, biblioteca y mapa con fechas/antenas y trayectos TX → RX; separación de escucha HF y enlace bilateral; pantalla propia de voz digital; búsqueda global de pases en los próximos 60 minutos; taller con 74 referencias y ficha SDR común. [Uso, migración y límites](docs/RELEASE-0.13.0.md). El waterfall conserva la actualización acotada de 0.12.1.

## Descargar y abrir

- [RadioWorkbench 0.11.0 · versión preliminar · macOS arm64](https://github.com/AD0441/RadioWorkbench/releases/tag/v0.11.0)
- [ZIP de la aplicación](https://github.com/AD0441/RadioWorkbench/releases/download/v0.11.0/RadioWorkbench-0.11.0-macos-arm64.zip)
- [Sumas SHA-256](https://github.com/AD0441/RadioWorkbench/releases/download/v0.11.0/SHA256SUMS)

Extrae el ZIP, mueve `RadioWorkbench.app` a una carpeta local como Aplicaciones y ábrela. La primera captura requiere el permiso de micrófono de macOS, también cuando se utiliza una entrada de audio virtual.

El bundle tiene **firma local ad hoc**, sin Developer ID ni notarización. macOS puede bloquear su primera apertura; consulta el [procedimiento de Apple para abrir una app de un desarrollador no identificado](https://support.apple.com/es-cl/102445). La verificación estricta se realizó sobre el ZIP extraído en una carpeta temporal, porque File Provider puede añadir metadatos Finder a un bundle ubicado en el Escritorio.

La versión preliminar **0.11.0** repara la transferencia de emisoras al Planificador HF, revisa el modelo por hemisferio y mes UTC, e incorpora las nueve herramientas acordadas: biblioteca, diagnóstico, audio TCP local, DSC MF/HF/VHF, mapa común, LRPT offline con SatDump, Rigctl optativo, eventos externos y taller de señales. Incluye MT63 en seis variantes y ALE 2G de 0.10.0. DSD-neo requiere macOS 26 y descarga separada; CWKit requiere 15. La app principal conserva macOS 14. [Nueve mejoras y límites](docs/NUEVE-MEJORAS.md) · [Notas 0.11.0](docs/RELEASE-0.11.0.md) · [MT63/ALE](docs/INTEGRATIONS-0.10.md) · [DMR de Brown](docs/DMR-BROWN-0.10.md) · [Historial](docs/HISTORIAL.md).

## Funciones incluidas

| Área | Funciones disponibles |
|---|---|
| Texto y tonos | MT63 500/1000/2000 corto/largo, FT8/FT4, Morse/CW manual o CWKit automático/neuronal, RTTY ITA2/ASCII 7/8, BPSK31, DTMF, CTCSS de 51 tonos, ocho familias Selcall y análisis FSK |
| Mensajes | DSC MF/HF y VHF con ECC e interpretación parcial; ALE 2G (sondeos, llamadas y AMD), POCSAG 512/1200/2400, NAVTEX/SITOR-B colectivo, AX.25/APRS AFSK1200 y ACARS VHF/ADS-C/CPDLC por audio AM |
| Voz digital | DSD-neo descargable: DMR con escucha durante recepción, TS1/TS2 y panel; P25 I/II, NXDN, D-STAR, YSF, M17 y dPMR con voz WAV; un canal RF |
| Imágenes | 41 variantes SSTV, WEFAX HF, APT y cinco variantes Hell por pulsos desde audio/archivos |
| Entrada | Micrófono, USB o cable virtual; audio TCP local con formato explícito; mezcla/canal individual y diagnóstico medido |
| Biblioteca y taller | Escuchas manuales con audio opcional, instantáneas de RX/antena, papelera y 74 referencias de laboratorio con espectro/waterfall |
| Mapas e I/Q | Trayectos históricos de escucha, filtros por fecha/hora/antena/banda/origen, trazas de eventos y SatDump LRPT offline |
| Guía de radios | Horarios EiBi, cruce técnico HFCC, favoritas y avisos de inicio |
| Condiciones HF | NOAA, D-RAP, Band Info, ionosondas y pronóstico NOAA de tres días |
| Propagación | ITU-R P.533/P.372 para HF; NTIA ITM con perfiles de terreno para VHF/UHF |
| Actividad observada | PSK Reporter, Reverse Beacon Network y APRS-IS bajo demanda |
| Consultas | Bandas chilenas, repetidoras e indicativos SUBTEL, APRS cercano y satélites de radioaficionado |

## Primer uso y audio desde SDR++

1. Elige el decodificador. **Ejemplo** carga una señal sintética incluida para familiarizarte con los controles.
2. En **Entrada de audio**, selecciona micrófono, receptor USB o cable virtual. Elige mezcla o el canal que contiene la señal; mezclar canales con señales distintas o fases opuestas puede corromperla.
3. Ajusta en SDR++ la demodulación RF y el ancho del filtro recomendados para el modo. Los campos del receptor son una guía para sintonía manual. La pantalla separada Rigctl permite enviar frecuencia/modo/ancho solo después de habilitarla y pulsar el botón de envío; verifica la lectura de vuelta.
4. Pulsa **Escuchar**, o usa **Abrir audio** para WAV, AIFF u otro formato que AVFoundation pueda leer. Exporta texto/JSON según el modo o guarda la imagen como PNG.

Para un cable virtual como VB-Cable, selecciona su salida en el módulo Audio/New Audio de SDR++, preferentemente a **48 kHz**, y el mismo dispositivo como entrada en RadioWorkbench. El cable debe estar instalado por separado. La app cambia la entrada de su propio motor, sin modificar el dispositivo predeterminado del sistema. Una desconexión o un cambio de formato detiene la sesión y permite reiniciarla.

| Recepción | Demodulación en SDR++ | Filtro RF inicial | Audio que conservar |
|---|---|---|---|
| CW, RTTY, BPSK31 | CW/USB; polaridad según la señal | Ajustable, hasta unos 2,4–3 kHz | Portadora/tonos del modo y centro configurado |
| MT63 | USB | 3 kHz inicial; ampliar si se desplaza el centro | Bloque de 500/1000/2000 Hz centrado inicialmente en 1500 Hz; mismo entrelazado que el emisor |
| ALE 2G | USB | 3 kHz | Ocho tonos completos 750–2500 Hz; sintonía en SDR++ |
| DSC MF/HF | USB; inversión según polaridad | 2,4 kHz | 100 baud, shift 170 Hz; centro de audio ajustable |
| DSC VHF | NFM, discriminador plano | 16 kHz inicial | 1300/2100 Hz, 1200 baud; preservar pre-emphasis o indicar audio ya compensado |
| NAVTEX/SITOR-B | USB; LSB con inversión | 2,4 kHz | 1615/1785 Hz; centro 1700 Hz, 100 baud, shift 170 Hz |
| AX.25/APRS 1200 | FM/NFM | 12–15 kHz | 1200/2200 Hz; conservar el paquete completo |
| CTCSS | FM/NFM | 12,5 kHz | 50–300 Hz; desactivar el pasa-altos de voz |
| POCSAG | FM/NFM, salida de discriminador | 12,5–25 kHz según canal | Baseband continuo; desactivar de-emphasis, squelch y filtros de voz |
| Cinco tonos/Selcall | FM/NFM | 12,5–25 kHz según canal | Aproximadamente 300–3500 Hz; conservar la secuencia completa |
| Hell por pulsos | USB en HF | 2,4 kHz inicial; ampliar para X9 | Centro y ancho por variante: 40–3150 Hz, mostrados en la app |
| ACARS VHF | AM | 10–12,5 kHz | 300–3500 Hz; tonos 1200/2400 Hz |
| SSTV HF | USB | 3 kHz | Cabecera y vídeo alrededor de 1100–2300 Hz |
| SSTV VHF/FM | FM/NFM según emisión | 12,5–25 kHz | Los mismos tonos del formato SSTV |
| WEFAX HF | USB | 2,8–3 kHz | Negro 1500, centro 1900, blanco 2300 Hz |
| APT de archivo | FM | 50 kHz | Subportadora AM de audio a 2400 Hz, banda hasta unos 5 kHz |

Son ajustes iniciales, no anchos universales de todos los servicios. Desactiva el squelch y los filtros de voz que corten datos. Para APT conserva la banda completa y desactiva de-emphasis/reducción de ruido. [Presets y fundamentos](docs/SDR-AUDIO-PRESETS.md).

## Decodificadores y alcance actual

- **MT63 y ALE 2G:** seis variantes MT63 con centro ajustable y controles de adquisición; ALE 2G con sondeos, llamadas y AMD. Helpers ligeros, audio/WAV y JSON. No aportan CRC de mensaje ni SNR calibrado. ALE 3G sigue pendiente. [Uso, pruebas y límites](docs/INTEGRATIONS-0.10.md).
- **CW, RTTY, BPSK31:** Morse con velocidad manual, RTTY ITA2 con letras/cifras e inversión, ASCII de 7/8 bits sin paridad y BPSK31 con Varicode ASCII. El modo ASCII 8 conserva el subconjunto ASCII imprimible, no implementa Latin-1. CHU, alfabetos nacionales y QPSK31 siguen pendientes.
- **DTMF y CTCSS:** detección de pares DTMF y 51 tonos CTCSS con confirmación temporal. [Tonos](docs/TONOS.md).
- **POCSAG y Selcall:** helper multimon-ng arm64 incluido; POCSAG 512/1200/2400 automático o fijo, BCH de 0–2 bits, capcode/función/texto y JSON. Selcall reconoce ZVEI1/2/3, PZVEI, DZVEI, EEA, EIA y CCIR, conservando los códigos especiales originales. FLEX y DCS siguen pendientes. [Implementación y audio requerido](docs/DECODIFICADORES-0.8.10.md).
- **Hellschreiber:** raster nativo para Feld, Slow 14 baud, Slow compatible con la tasa fldigi /8, X5 y X9; doble traza, reloj, umbral e inversión, con exportación PNG. No incluye OCR, FSK Hell ni Hell 80. [Variantes y validación](docs/DECODIFICADORES-0.8.10.md).
- **NAVTEX/SITOR-B:** adquisición por phasing CCIR 476 y corrección FEC mediante dos copias. Es el modo colectivo; no incluye SITOR-A/ARQ ni adquisición de una captura que empieza a mitad del tráfico. [NAVTEX](docs/NAVTEX.md).
- **AX.25/APRS AFSK1200:** decodificador nativo de paquetes por audio, con CRC y monitor acotado. La consulta APRS-IS de Internet es un servicio separado. [Packet/APRS](docs/PACKET.md).
- **ACARS VHF:** helper acarsdec arm64, audio AM, remuestreo continuo a 12 kHz, mensajes y exportación JSON. No incluye VDL2 ni HFDL. [ACARS](docs/ACARS.md).
- **WEFAX:** IOC 288/576, 60/90/120/240 LPM, inversión y reloj. El inicio de imagen es manual; detección automática de inicio/fin y eliminación de phasing están pendientes.
- **APT:** envolvente de la subportadora AM de 2400 Hz, sincronía A y dos regiones de vídeo de 909 píxeles. No incluye calibración radiométrica ni georreferenciación. Es útil para grabaciones históricas; las emisiones de NOAA 15/18/19 no se anuncian como un servicio actual.

**SSTV:** 41 variantes implementadas en las familias Martin M1–M4, Scottie S1–S4/DX, PD50–PD290, Robot 36/72, Pasokon P3/P5/P7, Wraase SC2-180 y extensiones MMSSTV MP/MR/ML/MP-N/MC-N. Auto VIS reconoce cabeceras clásicas, VIS de 16 bits y N-VIS de 24 bits. Hay calibración automática de centro/reloj, reducción de impulsos, ajuste manual en ppm y selección BT.601 limitado/rango completo para modos de diferencia de color. Sin cabecera, selecciona el formato y el inicio manualmente.

Las 41 variantes tienen pruebas matemáticas; una recepción acústica Robot36C se completó usando el micrófono del Mac. Eso no valida todos los transmisores ni todos los modos en RF. La opción de compatibilidad Robot36C permite exclusivamente la paridad VIS no estándar observada en esa prueba. Las fotografías y el audio personal de esa sesión se conservan localmente y **no se publican**. [Catálogo SSTV](docs/SSTV-MODOS.md) · [Prueba del micrófono](docs/MICROFONO.md).

El catálogo de investigación contiene 103 entradas con fuentes y estado de disponibilidad. FT8/FT4 y DSD-neo ya tienen recepción integrada con los requisitos descritos arriba. DSC ya recibe MF/HF y VHF con interpretación parcial; SatDump ya tiene un adaptador LRPT offline para I/Q, con calidad de extremo a extremo pendiente de una captura independiente. DRM, WSPR y otros modos WSJT-X, AIS, RDS y DAB continúan como candidatos. [Decodificadores candidatos](docs/DECODIFICADORES-EXTRA.md) · [Motores en GitHub](docs/GITHUB-MOTORES.md).

## Guía de radios, condiciones y propagación

**Guía de radios:** consulta EiBi con conexión y conserva la última copia sin conexión. Muestra horarios UTC, filtros, favoritas y avisos de inicio. HFCC aporta un candidato por frecuencia/horario/idioma con sitio y potencia programados. Eso no demuestra la misma instalación física. El planificador ofrece esa potencia como supuesto explícito, conserva la procedencia y pide los datos que faltan. Una potencia de horario no es medición en tiempo real. **Planificar escucha** copia nombre y frecuencia aunque no se conozcan las coordenadas. **Registrar escucha en biblioteca…** permite anotar un resultado real con fecha, antena y audio opcional. [Guía y revisión de RADIO BUNKER SWL](docs/RADIO-BUNKER-REA.md).

**Condiciones HF:** datos NOAA Kp/F10.7 y escalas R/S/G; pronóstico de tres días; absorción D-RAP en la celda correspondiente a la ubicación; Band Info día/noche con avisos; e ionosondas cercanas con foF2, MUF a 3000 km, fecha y confianza. Cada fuente conserva su fecha y su procedencia.

**Planificador HF:** dos flujos separados: escucha con geometría/horario sin exigir potencia y estimación P.533 opcional; enlace A → B y B → A con potencia, ganancias y requisitos RX propios. Fecha/hora UTC seleccionable, R12 0–311 con control de mes y campos pendientes visibles. ITU-R P.533/P.372 estima enlaces y contactos para ubicación, banda, potencia y rumbo. El cálculo describe condiciones mensuales y presupuesto de radio; se presenta separado de las observaciones solares y los spots recientes. Cambiar potencia no garantiza un contacto: ruido, antenas, modo y condiciones del trayecto influyen en el resultado.

**VHF/UHF con terreno:** origen y destino editables o seleccionables en Apple Maps, alturas AGL, frecuencia, potencia, ganancias y umbral RX. NTIA ITM calcula cada celda de una malla 65 × 65 o 129 × 129 con el perfil DEM completo TX→celda; conserva sombras detrás de crestas y recuperaciones en cumbres. Las elevaciones AMSL y alturas AGL se combinan dentro del modelo. El enlace exacto reutiliza el DEM de la malla o descarga su corredor de teselas. El horizonte de Tierra lisa es una referencia opcional apagada inicialmente. Apple Maps aporta contexto visual y las alturas proceden de Mapzen Terrain Tiles; se muestran resolución y avisos. [Método y validación geográfica](docs/TERRAIN-COVERAGE.md).

**Actividad:** PSK Reporter y Reverse Beacon Network muestran recepciones publicadas. La interfaz distingue estas observaciones de los enlaces modelados; un spot remoto no prueba recepción en el propio Mac. [Propagación y fuentes](docs/PROPAGACION.md) · [Actividad y terreno](docs/ACTIVIDAD-Y-TERRENO.md).

## Consultas de radio

1. **Frecuencia y bandas:** asignaciones de radioaficionado SUBTEL para Chile; modulación, filtro RF y banda de audio del perfil elegido. Una frecuencia ausente de esa tabla no se clasifica como libre.
2. **Repetidoras:** listados oficiales SUBTEL, búsqueda por indicativo/región/comuna, pequeño mapa Apple Maps y paso al destino ITM con coordenadas publicadas o ingresadas manualmente/con clic. Un permiso de operación no demuestra actividad actual.
3. **Indicativos:** consulta las listas SUBTEL conservando indicativo, categoría, zona y vencimiento; descarta nombres y números de licencia.
4. **APRS cercano:** flujo de solo recepción APRS-IS, filtro geográfico y selección de una estación como destino del análisis de terreno. Los paquetes llegan a través de gateways y no confirman cobertura RF local.
5. **Satélites:** frecuencias AMSAT/SatNOGS por API de GitHub, elementos GP de CelesTrak con alternativa TLE de AMSAT, reportes AMSAT y pases aproximados de 48 horas. Seleccionar un pase muestra su trayectoria terrestre y un gráfico polar de azimut/elevación. Cada fuente conserva caché y fecha independientes. El cálculo usa SGP4/SDP4 con BSTAR y observador WGS84; muestra Doppler de entrada/salida para la frecuencia elegida.

SUBTEL y satélites actualizan datos y mantienen caché local; APRS conecta únicamente al solicitarlo. [Fuentes, actualización y límites](docs/CONSULTAS.md).

## Datos y privacidad

El audio se procesa en el Mac. DSD guarda voz decodificada en un WAV temporal local, reproducible/exportable al detener; al iniciar otra sesión se elimina la copia temporal previa. La captura diagnóstica a WAV requiere una opción explícita; no se envía a terceros. Los perfiles y las copias de datos se almacenan localmente en Application Support.

Los servicios en línea consultan a sus proveedores: EiBi, HFCC, NOAA, HamQSL, ionosondas, SUBTEL, CelesTrak y AMSAT/SatNOGS. PSK Reporter comparte una cuadrícula Maidenhead de cuatro caracteres tras activarlo; APRS-IS envía indicativo y ubicación redondeada a dos decimales para filtrar. El análisis topográfico solicita índices de teselas DEM a AWS solo al pedir terreno; esos índices permiten inferir la región consultada. Apple Maps mantiene sus propias consultas de mapa. Estos servicios tienen su propia cobertura y disponibilidad.

## Compilar y probar

Toolchain verificado: **Apple Swift 6.4, SDK macOS 27.0, arm64**, con CMake para libacars. El código usa nuevas APIs de audio del SDK macOS 27 con una ruta de ejecución anterior protegida por disponibilidad; para compilar las fuentes actuales se requiere ese SDK o uno posterior, aunque el bundle declare macOS 14 como mínimo.

```sh
git clone https://github.com/AD0441/RadioWorkbench.git
cd RadioWorkbench
bash script/test.sh -c release
bash script/build_and_run.sh --build-only
open dist/RadioWorkbench.app
```

`dist/RadioWorkbench.app` (o el bundle elegido mediante `RADIO_OUTPUT_APP_BUNDLE`) y `dist/RadioWorkbench-<versión>-macos-arm64.zip` son salidas de compilación y están excluidas de Git. Se genera un único ZIP por versión. `bash script/build_and_run.sh` compila y abre la app; `--debug` inicia LLDB. `RADIO_BUILD_PATH` permite una caché distinta y `RADIO_BUILD_CONFIGURATION=debug` cambia la configuración.

**Retención local:** conservar únicamente la entrega actual y la anterior, con una sola app por versión y sin ZIP duplicados. Al cerrar una entrega, retirar las versiones más antiguas, cachés regenerables, extracciones temporales y registros de intentos descartados. Conservar código, dependencias, pruebas, documentación y evidencias finales; evitar crear nuevos informes por cada intento intermedio.

La pasada **0.13.0** registra **240 funciones: 234 aprobadas y seis opcionales omitidas**, sin fallos, más 21 controles C HF. Incluye migración de biblioteca, anotaciones/mapa, flujos HF, límites de pases, perfiles y 74 referencias. Firma estricta y 13 objetos arm64 verificados; instalada localmente en Aplicaciones. La revisión visual comprobó guía/formulario e inspector y quedó parcial por fallo de la herramienta al abrir HF. [Resultados y límites](docs/VALIDACION.md).

La pasada **0.12.1** registra **218 funciones: 216 aprobadas y dos opcionales de red omitidas**, sin fallos. Incluye actualización visual, el runtime DSD-neo oficial, una grabación DMR independiente, TS1/TS2, voz antes de EOF, cancelación, conservación del WAV y el grafo de audio renderizado offline sin altavoces. [Resultados y límites](docs/VALIDACION.md).

La pasada **0.11.0** registra **202 funciones: 198 aprobadas y cuatro opcionales omitidas**, sin fallos. Añade pruebas de biblioteca/integridad, PCM/TCP/EOF, DSC, mapa/eventos, SatDump aislado, Rigctl y taller. El ZIP extraído pasó integridad y firma estricta, con todos sus ejecutables arm64. La revisión visual comprobó la apertura, las nuevas entradas de navegación, los parámetros TCP y el diagnóstico; quedó interrumpida por un cierre de la herramienta de control de pantalla mientras RadioWorkbench seguía activa. [Comprobaciones y límite de interfaz](docs/validation/ui-0.11.0.json) · [Notas y límites](docs/RELEASE-0.11.0.md).

La pasada **0.10.0** registra **159 funciones: 155 aprobadas y cuatro opcionales omitidas**, sin fallos. Añade las seis variantes MT63, ALE con señales sintéticas y grabaciones públicas de contraste, audio estéreo a 48 kHz, selección de canal y publicación en vivo simulada. Los dos casos DSD requieren su runtime externo; los otros dos omitidos consultan red/terreno real. La pasada anterior 0.9.0 sí verificó DSD con su runtime oficial: 146 aprobadas y dos opcionales omitidas. Las señales MT63 son un contraste TX/RX del mismo upstream; falta una captura independiente. No se hizo una nueva prueba física de micrófono o SDR++/VB-Cable. [Evidencia y alcance](docs/VALIDACION.md).

| Carpeta | Contenido |
|---|---|
| `Sources/RadioCore` | DSP, modelos, parsers y fuentes de datos |
| `Sources/RadioWorkbench` | Interfaz SwiftUI, captura CoreAudio, almacenes y servicios |
| `Sources/AudioRing` | Ring SPSC C preasignado para audio |
| `Tests` | Pruebas, transmisiones sintéticas y manifiestos |
| `Vendor` | Fuentes/datos de componentes externos y sus avisos |
| `script` | Helpers, compilación, pruebas y empaquetado |
| `docs` | Protocolos, fuentes, limitaciones y validaciones |

El callback de audio copia/mezcla al ring; los decodificadores y archivos se procesan fuera del callback. Texto, raster y waterfall tienen límites, y las actualizaciones UI se acotan a diez por segundo. La compilación nativa favorece Apple Silicon; todavía no hay una comparación de rendimiento medida contra MultiMode bajo Rosetta.

## Componentes y avisos

- **SatelliteKit, ft8_lib, CWKit y libacars:** fuentes MIT, avisos y hashes fijados, con archivos de fuentes incluidos en el bundle. [Integración y cambios](docs/INTEGRATIONS-0.9.md).
- **DSD-neo:** runtime oficial opcional descargado de GitHub, con SHA-256 y versión fijados; no redistribuido por este proyecto. Conserva sus avisos GPL y los de sus dependencias.
- **acarsdec:** helper separado bajo [GPL v2](Vendor/acarsdec/LICENSE.md), con fuentes y wrapper incluidos en el bundle.
- **multimon-ng:** helper separado bajo [GPL v2 o posterior](Vendor/MultimonNG/COPYING), fijado a un commit con [parches locales documentados](Vendor/MultimonNG/LOCAL-CHANGES.md) y compilado para PCM por stdin, con fuentes, script y licencia incluidos en el bundle.
- **fldigi MT63 y KiwiSDR ALE 2G:** helpers separados bajo GPL v3 o posterior, con [cambios MT63](Vendor/MT63/LOCAL-CHANGES.md), [cambios ALE](Vendor/ALE2G/LOCAL-CHANGES.md), hashes fijados y código correspondiente incluido en el bundle.
- **ITU-R HF:** modelos P.533/P.372 y sus datos, con el [aviso upstream preservado](Vendor/ITU-R-HF/NOTICE.md).
- **NTIA ITM:** fuentes originales y [licencia/avisos NTIA](Vendor/NTIA-ITM/LICENSE.md), con manifiesto de procedencia.
- **DEM Mapzen Terrain Tiles:** datos consultados bajo demanda, con [fuentes y atribuciones regionales](https://github.com/tilezen/joerd/blob/master/docs/attribution.md).
- **Datos de frecuencia de satélites:** atribución AMSAT/SatNOGS y CC BY-SA 4.0 documentadas en [Consultas](docs/CONSULTAS.md).
- **MultiMode Cocoa:** [revisión funcional y límites de la evidencia](docs/REVISION-MULTIMODE.md); los archivos originales permanecen fuera del producto.

Los componentes de terceros mantienen sus propias condiciones; este repositorio no les asigna una licencia nueva ni declara una licencia global para el código propio.
