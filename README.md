# RadioWorkbench · 0.8.8

Receptor y laboratorio de radio nativo para **macOS y Apple Silicon**. Permite decodificar audio de un receptor, del micrófono o de un archivo; consultar horarios y frecuencias; observar condiciones de bandas; y estudiar enlaces HF y VHF/UHF con modelos de propagación y terreno.

El proyecto usa SwiftUI, CoreAudio/AVFoundation, Accelerate y MapKit. La aplicación original MultiMode Cocoa se utilizó como referencia funcional documentada; el nuevo producto no incorpora su ejecutable, código, NIB ni recursos comerciales.

**Plataforma:** el bundle declara macOS 14 o posterior y el paquete publicado es **arm64 para M1 y posteriores**. Se ha probado en un MacBook Pro M1 con macOS 27.2. No se distribuyen binarios para Mac Intel, iOS, Windows o Linux; tampoco se ha verificado la ejecución física en todas las versiones macOS 14–26.

**Estado:** aplicación experimental en desarrollo. Las señales sintéticas y las pruebas unitarias validan el comportamiento implementado, pero no garantizan recepción RF bajo cualquier condición.

## Descargar y abrir

- [RadioWorkbench 0.8.8 · macOS arm64](https://github.com/AD0441/RadioWorkbench/releases/tag/v0.8.8)
- [ZIP de la aplicación](https://github.com/AD0441/RadioWorkbench/releases/download/v0.8.8/RadioWorkbench-0.8.8-macos-arm64.zip)

Extrae el ZIP, mueve `RadioWorkbench.app` a una carpeta local como Aplicaciones y ábrela. La primera captura requiere el permiso de micrófono de macOS, también cuando se utiliza una entrada de audio virtual.

El bundle tiene **firma local ad hoc**, sin Developer ID ni notarización. macOS puede bloquear su primera apertura; consulta el [procedimiento de Apple para abrir una app de un desarrollador no identificado](https://support.apple.com/es-cl/102445). La verificación estricta se realizó sobre el ZIP extraído en una carpeta temporal, porque File Provider puede añadir metadatos Finder a un bundle ubicado en el Escritorio.

La versión 0.8.8 corrige el cierre al escribir el indicativo APRS: la normalización a mayúsculas ya no reasigna la propiedad desde su propio observador. [Notas de la versión](docs/RELEASE-0.8.8.md) · [Historial](docs/HISTORIAL.md).

## Funciones incluidas

| Área | Funciones disponibles |
|---|---|
| Texto y tonos | Morse/CW, RTTY ITA2, BPSK31, DTMF, CTCSS de 51 tonos y análisis FSK |
| Mensajes | NAVTEX/SITOR-B colectivo, AX.25/APRS AFSK1200 y ACARS VHF por audio AM |
| Imágenes | 41 variantes SSTV, WEFAX HF y APT desde audio/archivos |
| Entrada | Micrófono, dispositivo USB o virtual seleccionable, canales individuales/mezcla y perfiles persistentes |
| Guía de radios | Horarios EiBi, cruce técnico HFCC, favoritas y avisos de inicio |
| Condiciones HF | NOAA, D-RAP, Band Info, ionosondas y pronóstico NOAA de tres días |
| Propagación | ITU-R P.533/P.372 para HF; NTIA ITM con perfiles de terreno para VHF/UHF |
| Actividad observada | PSK Reporter, Reverse Beacon Network y APRS-IS bajo demanda |
| Consultas | Bandas chilenas, repetidoras e indicativos SUBTEL, APRS cercano y satélites de radioaficionado |

## Primer uso y audio desde SDR++

1. Elige el decodificador. **Ejemplo** carga una señal sintética incluida para familiarizarte con los controles.
2. En **Entrada de audio**, selecciona micrófono, receptor USB o cable virtual. Elige mezcla o el canal que contiene la señal; mezclar canales con señales distintas o fases opuestas puede corromperla.
3. Ajusta en SDR++ la demodulación RF y el ancho del filtro recomendados para el modo. En RadioWorkbench estos campos son una guía para la sintonía manual; la app no controla SDR++ por red.
4. Pulsa **Escuchar**, o usa **Abrir audio** para WAV, AIFF u otro formato que AVFoundation pueda leer. Exporta texto/JSON según el modo o guarda la imagen como PNG.

Para un cable virtual como VB-Cable, selecciona su salida en el módulo Audio/New Audio de SDR++, preferentemente a **48 kHz**, y el mismo dispositivo como entrada en RadioWorkbench. El cable debe estar instalado por separado. La app cambia la entrada de su propio motor, sin modificar el dispositivo predeterminado del sistema. Una desconexión o un cambio de formato detiene la sesión y permite reiniciarla.

| Recepción | Demodulación en SDR++ | Filtro RF inicial | Audio que conservar |
|---|---|---|---|
| CW, RTTY, BPSK31 | CW/USB; polaridad según la señal | Ajustable, hasta unos 2,4–3 kHz | Portadora/tonos del modo y centro configurado |
| NAVTEX/SITOR-B | USB; LSB con inversión | 2,4 kHz | 1615/1785 Hz; centro 1700 Hz, 100 baud, shift 170 Hz |
| AX.25/APRS 1200 | FM/NFM | 12–15 kHz | 1200/2200 Hz; conservar el paquete completo |
| CTCSS | FM/NFM | 12,5 kHz | 50–300 Hz; desactivar el pasa-altos de voz |
| ACARS VHF | AM | 10–12,5 kHz | 300–3500 Hz; tonos 1200/2400 Hz |
| SSTV HF | USB | 3 kHz | Cabecera y vídeo alrededor de 1100–2300 Hz |
| SSTV VHF/FM | FM/NFM según emisión | 12,5–25 kHz | Los mismos tonos del formato SSTV |
| WEFAX HF | USB | 2,8–3 kHz | Negro 1500, centro 1900, blanco 2300 Hz |
| APT de archivo | FM | 50 kHz | Subportadora AM de audio a 2400 Hz, banda hasta unos 5 kHz |

Son ajustes iniciales, no anchos universales de todos los servicios. Desactiva el squelch y los filtros de voz que corten datos. Para APT conserva la banda completa y desactiva de-emphasis/reducción de ruido. [Presets y fundamentos](docs/SDR-AUDIO-PRESETS.md).

## Decodificadores y alcance actual

- **CW, RTTY, BPSK31:** Morse con velocidad manual, RTTY ITA2 con letras/cifras e inversión, y BPSK31 con Varicode ASCII. RTTY ASCII/CHU, alfabetos nacionales y QPSK31 siguen pendientes.
- **DTMF y CTCSS:** detección de pares DTMF y 51 tonos CTCSS con confirmación temporal. [Tonos](docs/TONOS.md).
- **NAVTEX/SITOR-B:** adquisición por phasing CCIR 476 y corrección FEC mediante dos copias. Es el modo colectivo; no incluye SITOR-A/ARQ ni adquisición de una captura que empieza a mitad del tráfico. [NAVTEX](docs/NAVTEX.md).
- **AX.25/APRS AFSK1200:** decodificador nativo de paquetes por audio, con CRC y monitor acotado. La consulta APRS-IS de Internet es un servicio separado. [Packet/APRS](docs/PACKET.md).
- **ACARS VHF:** helper acarsdec arm64, audio AM, remuestreo continuo a 12 kHz, mensajes y exportación JSON. No incluye VDL2 ni HFDL. [ACARS](docs/ACARS.md).
- **WEFAX:** IOC 288/576, 60/90/120/240 LPM, inversión y reloj. El inicio de imagen es manual; detección automática de inicio/fin y eliminación de phasing están pendientes.
- **APT:** envolvente de la subportadora AM de 2400 Hz, sincronía A y dos regiones de vídeo de 909 píxeles. No incluye calibración radiométrica ni georreferenciación. Es útil para grabaciones históricas; las emisiones de NOAA 15/18/19 no se anuncian como un servicio actual.

**SSTV:** 41 variantes implementadas en las familias Martin M1–M4, Scottie S1–S4/DX, PD50–PD290, Robot 36/72, Pasokon P3/P5/P7, Wraase SC2-180 y extensiones MMSSTV MP/MR/ML/MP-N/MC-N. Auto VIS reconoce cabeceras clásicas, VIS de 16 bits y N-VIS de 24 bits. Hay calibración automática de centro/reloj, reducción de impulsos, ajuste manual en ppm y selección BT.601 limitado/rango completo para modos de diferencia de color. Sin cabecera, selecciona el formato y el inicio manualmente.

Las 41 variantes tienen pruebas matemáticas; una recepción acústica Robot36C se completó usando el micrófono del Mac. Eso no valida todos los transmisores ni todos los modos en RF. La opción de compatibilidad Robot36C permite exclusivamente la paridad VIS no estándar observada en esa prueba. Las fotografías y el audio personal de esa sesión se conservan localmente y **no se publican**. [Catálogo SSTV](docs/SSTV-MODOS.md) · [Prueba del micrófono](docs/MICROFONO.md).

El catálogo de investigación contiene 103 entradas con fuentes y estado de disponibilidad. DRM, FT8/FT4/WSPR, DMR/P25/NXDN, AIS, RDS, DAB, SatDump y otras ampliaciones están investigadas, pero no deben confundirse con motores ya integrados. [Decodificadores candidatos](docs/DECODIFICADORES-EXTRA.md) · [Motores en GitHub](docs/GITHUB-MOTORES.md).

## Guía de radios, condiciones y propagación

**Guía de radios:** consulta EiBi con conexión y conserva la última copia sin conexión. Muestra horarios UTC, filtros, favoritas y avisos de inicio. Cruza HFCC para añadir potencia, rumbo y zona programados solo cuando la asociación es inequívoca. Una potencia declarada en un horario no es una medición en tiempo real. [Guía y revisión de RADIO BUNKER SWL](docs/RADIO-BUNKER-REA.md).

**Condiciones HF:** datos NOAA Kp/F10.7 y escalas R/S/G; pronóstico de tres días; absorción D-RAP en la celda correspondiente a la ubicación; Band Info día/noche con avisos; e ionosondas cercanas con foF2, MUF a 3000 km, fecha y confianza. Cada fuente conserva su fecha y su procedencia.

**Planificador HF:** ITU-R P.533/P.372 estima enlaces y contactos para ubicación, banda, potencia y rumbo. El cálculo describe condiciones mensuales y presupuesto de radio; se presenta separado de las observaciones solares y los spots recientes. Cambiar potencia no garantiza un contacto: ruido, antenas, modo y condiciones del trayecto influyen en el resultado.

**VHF/UHF con terreno:** origen y destino editables o seleccionables en Apple Maps, alturas AGL de ambas antenas, frecuencia, potencia, ganancias y umbral RX. El perfil DEM Copernicus suma elevación topográfica AMSL y altura de antena AGL; identifica crestas que cruzan la línea directa y muestra el corredor Fresnel. NTIA ITM calcula pérdida y potencia recibida. El alcance sobre el mapa usa 32 rumbos, perfiles alrededor de cada 500 m y evaluación hasta 200 km; la envolvente entre rumbos es aproximada. El relieve visible de Apple Maps sirve de contexto: las alturas del cálculo provienen del perfil DEM, no del dibujo del mapa.

**Actividad:** PSK Reporter y Reverse Beacon Network muestran recepciones publicadas. La interfaz distingue estas observaciones de los enlaces modelados; un spot remoto no prueba recepción en el propio Mac. [Propagación y fuentes](docs/PROPAGACION.md) · [Actividad y terreno](docs/ACTIVIDAD-Y-TERRENO.md).

## Consultas de radio

1. **Frecuencia y bandas:** asignaciones de radioaficionado SUBTEL para Chile; modulación, filtro RF y banda de audio del perfil elegido. Una frecuencia ausente de esa tabla no se clasifica como libre.
2. **Repetidoras:** listados oficiales SUBTEL, búsqueda por indicativo/región/comuna y paso al destino ITM con coordenadas publicadas o ingresadas manualmente. Un permiso de operación no demuestra actividad actual.
3. **Indicativos:** consulta las listas SUBTEL conservando indicativo, categoría, zona y vencimiento; descarta nombres y números de licencia.
4. **APRS cercano:** flujo de solo recepción APRS-IS, filtro geográfico y selección de una estación como destino del análisis de terreno. Los paquetes llegan a través de gateways y no confirman cobertura RF local.
5. **Satélites:** frecuencias AMSAT/SatNOGS, elementos GP de CelesTrak, reportes de estado AMSAT y pases aproximados de 48 horas. El cálculo usa Kepler con corrección secular J2; no implementa SGP4 ni corrección Doppler.

SUBTEL y satélites actualizan datos y mantienen caché local; APRS conecta únicamente al solicitarlo. [Fuentes, actualización y límites](docs/CONSULTAS.md).

## Datos y privacidad

El audio se procesa en el Mac. La captura diagnóstica a WAV requiere una opción explícita; no se envía a terceros. Los perfiles y las copias de datos se almacenan localmente en Application Support.

Los servicios en línea consultan a sus proveedores: EiBi, HFCC, NOAA, HamQSL, ionosondas, SUBTEL, CelesTrak y AMSAT/SatNOGS. PSK Reporter comparte una cuadrícula Maidenhead de cuatro caracteres tras activarlo; APRS-IS envía indicativo y ubicación redondeada a dos decimales para filtrar. El análisis topográfico comparte las coordenadas del perfil con Open-Meteo solo al solicitar terreno. Estos servicios tienen su propia cobertura y disponibilidad.

## Compilar y probar

Toolchain verificado: **Apple Swift 6.4, SDK macOS 27.0, arm64**. El código usa nuevas APIs de audio del SDK macOS 27 con una ruta de ejecución anterior protegida por disponibilidad; para compilar las fuentes actuales se requiere ese SDK o uno posterior, aunque el bundle declare macOS 14 como mínimo.

```sh
git clone https://github.com/AD0441/RadioWorkbench.git
cd RadioWorkbench
bash script/test.sh
bash script/build_and_run.sh --build-only
open dist/RadioWorkbench.app
```

`dist/RadioWorkbench.app` y `dist/RadioWorkbench-arm64.zip` son salidas de compilación y están excluidas de Git. `bash script/build_and_run.sh` compila y abre la app; `--debug` inicia LLDB. `RADIO_BUILD_PATH` permite una caché distinta y `RADIO_BUILD_CONFIGURATION=debug` cambia la configuración.

La suite actual aprobó **99 funciones de prueba**, algunas parametrizadas, incluidos todos los fixtures SSTV y la regresión del indicativo APRS. El bundle Release arm64 y el ZIP extraído pasaron la verificación estricta de firma. [Evidencia y alcance](docs/VALIDACION.md).

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

- **acarsdec:** helper separado bajo [GPL v2](Vendor/acarsdec/LICENSE.md), con fuentes y wrapper incluidos en el bundle.
- **ITU-R HF:** modelos P.533/P.372 y sus datos, con el [aviso upstream preservado](Vendor/ITU-R-HF/NOTICE.md).
- **NTIA ITM:** fuentes originales y [licencia/avisos NTIA](Vendor/NTIA-ITM/LICENSE.md), con manifiesto de procedencia.
- **Datos de frecuencia de satélites:** atribución AMSAT/SatNOGS y CC BY-SA 4.0 documentadas en [Consultas](docs/CONSULTAS.md).
- **MultiMode Cocoa:** [revisión funcional y límites de la evidencia](docs/REVISION-MULTIMODE.md); los archivos originales permanecen fuera del producto.

Los componentes de terceros mantienen sus propias condiciones; este repositorio no les asigna una licencia nueva ni declara una licencia global para el código propio.
