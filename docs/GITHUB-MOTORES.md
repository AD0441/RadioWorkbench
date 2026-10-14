# Motores y complementos encontrados en GitHub

Consulta: **12 de octubre de 2026**. Objetivo: apoyar una nueva aplicación macOS arm64 para Apple Silicon, inspirada en las funciones de MultiMode Cocoa. Se consultaron repositorios mediante el conector GitHub y documentación primaria de los proyectos. No se instalaron, compilaron ni ejecutaron los motores de esta investigación.

Las columnas de compatibilidad distinguen paquetes disponibles, declaraciones del proyecto y candidatos que necesitan un port. Una compilación o un paquete arm64 no prueba por sí solo la calidad del decodificador ni que todos los dispositivos USB sean compatibles. Las fechas de actividad son `pushed_at` observadas en la API de GitHub; no equivalen a una release ni a una validación funcional.

## Recomendación de integración

Estado del producto al 13 de octubre: RadioWorkbench 0.5 incorpora 41 variantes SSTV, WEFAX, APT, NAVTEX/SITOR-B, APRS/AX.25 AFSK1200 y CTCSS, además de CW/RTTY/BPSK31/DTMF. La guía de radios consulta y cachea EiBi. La ampliación SSTV queda para después, según la indicación del usuario. La tabla conserva alternativas externas y sus contratos; no implica que se hayan instalado. [NAVTEX.md](NAVTEX.md), [PACKET.md](PACKET.md), [TONOS.md](TONOS.md) y [SSTV-MODOS.md](SSTV-MODOS.md) documentan las implementaciones.

Mantener un núcleo Swift/Accelerate propio para audio y WAV en CW, RTTY, PSK31 y tonos. Separar los motores externos por contrato de entrada y salida: audio PCM/WAV, IQ complejo, texto de protocolo o control de otra aplicación. Ningún repositorio verificado es una biblioteca macOS arm64 lista para cubrir todos los modos de MultiMode.

Prioridad propuesta:

1. Cerrar y verificar el núcleo de audio/WAV CW, RTTY, PSK31 y tonos.
2. ACARS por WAV/PCM ya se incorporó con `acarsdec` en 0.6; captura/decodificación IQ con SoapySDR y `xng` sigue pendiente.
3. Ampliar AX.25/APRS con Dire Wolf y modos de audio con fldigi.
4. Tratar ALE, DGPS, LORAN-C y Globe Wireless como integraciones separadas, con su estado y evidencia de validación. Retomar SSTV cuando el usuario lo priorice.

Los proyectos GPL siguen teniendo condiciones de distribución aunque se ejecuten como procesos separados. IPC no cambia automáticamente la licencia de un componente. Verificar también licencias de dependencias, recursos gráficos y controladores que se vayan a distribuir.

## Ocho candidatos principales

| Proyecto y fuente primaria | Función e integración | Licencia observada | macOS/arm64 y límites | Actividad observada |
|---|---|---|---|---|
| [liquid-dsp](https://github.com/jgaeddert/liquid-dsp), [README](https://github.com/jgaeddert/liquid-dsp/blob/master/README.rst) | Biblioteca C: filtros, remuestreo, AGC, NCO, sincronización y modulación. Bridge C desde Swift; candidata para el DSP propio. | MIT | [Homebrew declara paquetes macOS arm64](https://github.com/Homebrew/homebrew-core/blob/master/Formula/l/liquid-dsp.rb). Sus bloques no son aplicaciones completas CW/RTTY/PSK31. FFTW es opcional y tiene licencia diferente; el README ofrece `FIND_FFTW=OFF`. La fórmula Homebrew consultada sí depende de FFTW. | 2026-10-04 |
| [SoapySDR](https://github.com/pothosware/SoapySDR), [README](https://github.com/pothosware/SoapySDR/blob/master/README.md) | Biblioteca C/C++ de adquisición IQ y abstracción SDR; módulos por fabricante/dispositivo. | BSL-1.0 | [Fórmula con paquetes macOS arm64](https://github.com/Homebrew/homebrew-core/blob/master/Formula/s/soapysdr.rb). Cada controlador necesita validación propia; instalar SoapySDR no prueba soporte de cualquier USB SDR. | 2026-10-10 |
| [fldigi](https://github.com/w1hkj/fldigi), [proyecto oficial](https://w1hkj.org/) | Motor de audio amplio como aplicación separada, controlable por XML-RPC: CW, RTTY, PSK31, Hell, MT63, NAVTEX/SITOR-B y WEFAX. | GPL-3.0+ | El espejo GitHub quedó en 2023. El proyecto oficial publicó **4.2.13 en julio de 2026**. [Wiki oficial](https://sourceforge.net/p/fldigi/wiki/apple_howto/) declara DMG para Intel y Apple M1/M2/M3. Usar una versión oficial actual; no congelar el espejo viejo. XML-RPC no documenta entrada PCM ni playback WAV. | GitHub: 2023-06-29; desarrollo oficial: 2026 |
| [f00b4r0/acarsdec](https://github.com/f00b4r0/acarsdec), [README](https://github.com/f00b4r0/acarsdec/blob/master/README.md) | Proceso para ACARS desde WAV/audio, con stdout JSON; entradas SDR opcionales y decodificación de aplicaciones mediante libacars. | GPLv2-only según README | C/CMake y dependencias opcionales permiten estudiar una compilación macOS; no se encontró release/CI arm64 que pruebe el resultado. Habilitar SNDFILE y CJSON, desactivar ALSA; verificar el build. Audio a un múltiplo de 12 kHz. La versión antigua [TLeconte/acarsdec](https://github.com/TLeconte/acarsdec) está archivada. | 2026-10-07 |
| [airframesio/xng](https://github.com/airframesio/xng), [README v0.21.0](https://github.com/airframesio/xng/blob/v0.21.0/README.md) | Proceso Rust para aviación/marítimo; salida JSON/JSONL, UDP y otras interfaces. ACARS, VDL2, HFDL, Aero, STD-C, AIS, ADS-B, NAVTEX, DSC y APRS. | MIT **o** Apache-2.0 | [Release v0.21.0](https://github.com/airframesio/xng/releases/tag/v0.21.0) contiene `xng-v0.21.0-aarch64-apple-darwin.tar.gz`. Entrada IQ cruda, no WAV/audio. No cubre CW, RTTY, PSK31, WEFAX, SSTV, ALE ni DGPS. Madurez distinta por modo. | 2026-08-20; release: 2026-06-19 |
| [Dire Wolf](https://github.com/wb2osz/direwolf), [README](https://github.com/wb2osz/direwolf/blob/master/README.md) | AX.25/APRS, FX.25, DTMF/APRStt. Proceso separado mediante KISS/AGW TCP, antes que extraer módulos internos. | GPL-2.0+ | README declara compilación verificada en macOS Ventura **M2** e Intel. No se ejecutó localmente. AX.25/APRS no implica todos los protocolos packet posibles. | 2026-10-11 |
| [multimon-ng](https://github.com/EliasOenal/multimon-ng), [README](https://github.com/EliasOenal/multimon-ng/blob/master/README.md) | Proceso para MORSE_CW, DTMF, DUALTONE, AFSK1200/2400, FSK9600, pagers y DUMPCSV/Scope. Entrada PCM firmado de 16 bit a 22050 Hz por stdin. | GPL-2.0+ | README declara macOS; [macos_audio.m](https://github.com/EliasOenal/multimon-ng/blob/master/macos_audio.m) usa CoreAudio ProcessTap, macOS 14.2+. No se inspeccionó un binario arm64. Salida principalmente textual, sin JSON uniforme para todos los modos. | 2026-10-11 |
| [tomtastic/QSSTV](https://github.com/tomtastic/QSSTV), [README](https://github.com/tomtastic/QSSTV/blob/main/README.md) | SSTV analógico RX/TX y HAMDRM; aplicación separada inicialmente. | GPL-3.0 | [Workflow macOS 26](https://github.com/tomtastic/QSSTV/blob/main/.github/workflows/macos-26.yml) genera un artefacto llamado `qsstv_arm64.app.zip`; no se inspeccionó el binario. Requiere Qt6, FFTW, Hamlib, OpenJPEG y **PulseAudio activo**. No es biblioteca ligera ni se verificó una API externa. | 2026-03-09 |

## Matriz de cobertura de los modos solicitados

La matriz identifica alternativas de integración. **No declara que estos motores estén incorporados en RadioWorkbench.**

| Modo | Motor o referencia verificable | Entrada/API y alcance | Pendiente o límite |
|---|---|---|---|
| CW/Morse | fldigi; multimon-ng `MORSE_CW` | Audio/WAV; pueden contrastar el decodificador Swift. | Medir desempeño con señales reales y ruido; no equivaler pruebas sintéticas a recepción real. |
| RTTY | fldigi; [SDRangel RTTY](https://github.com/f4exb/sdrangel/tree/master/plugins/channelrx/demodrtty) | Audio en fldigi; IQ/canales en SDRangel. | Comprobar baud, shift, Baudot y variantes específicas necesarias. |
| PSK31 | fldigi; [SDRangel PSK31](https://github.com/f4exb/sdrangel/tree/master/plugins/channelrx/demodpsk31) | Motores completos; liquid-dsp ofrece bloques DSP. | Validar sincronización/Varicode y señales reales del núcleo propio. |
| ACARS | f00b4r0/acarsdec; xng; libacars para contenido | acarsdec: WAV/PCM y stdout JSON. xng: IQ y JSON. libacars: mensajes ya demodulados. | acarsdec necesita build arm64 y audio a múltiplos de 12 kHz. No pasar WAV a xng ni usar libacars como demodulador. |
| SSTV | tomtastic/QSSTV | RX/TX convencional; aplicación Qt. | Definir bridge hacia SwiftUI; no API externa verificada. |
| WEFAX | fldigi; [SDRangel WEFAX](https://github.com/f4exb/sdrangel/tree/master/plugins/channelrx/demodwefax) | fldigi entrega nombre del archivo recibido por XML-RPC. SDRangel documenta REST settings/report/actions. | Imágenes, sincronía y corrección de inclinación requieren pruebas propias. |
| SITOR/NAVTEX | [fldigi NAVTEX/SITOR-B](https://www.w1hkj.org/FldigiHelp/navtex_and_sitorb_page.html); [xng NAVTEX](https://github.com/airframesio/xng/blob/master/docs/notes/NAVTEX.md) | fldigi: audio y mensajes XML-RPC. xng: IQ, CCIR476, FEC-B y framing NAVTEX. | No afirmar SITOR-A/ARQ: lo verificado cubre B/FEC. xng documenta captura real USCG para NAVTEX. |
| Packet AX.25 | Dire Wolf; multimon-ng; xng `aprs` | Dire Wolf: audio, KISS/AGW TCP. xng: IQ AFSK1200/AX.25 UI/APRS. | xng declara demodulación APRS sintética; Dire Wolf es mejor candidato inicial para audio. |
| ALE | [KiwiSDR ALE_2G](https://github.com/jks-prv/KiwiSDR/tree/master/extensions/ALE_2G); [gr-ale](https://github.com/gat3way/gr-ale) | ALE **2G**. gr-ale acepta float de audio USB a 8 kHz y escribe stdout. Kiwi conserva `standalone_test`. | Port y build macOS pendientes; no 3G verificado. gr-ale de 2016 declara sólo sounding/call establishment y soporte incompleto. |
| Hell | fldigi | Variantes Feld/Slow/FSK Hell en el motor de audio. | Bridge para renderizado visual; no reducir a texto RX. |
| MT63 | fldigi | Variantes 500/1000/2000 en audio. | Integrar motor oficial y verificar opciones necesarias. |
| GMDSS/DSC | [xng DSC](https://github.com/airframesio/xng/blob/master/docs/notes/DSC.md); [SDRangel DSC](https://github.com/f4exb/sdrangel/tree/master/plugins/channelrx/demoddsc) | xng: MF/HF, IQ y JSON. Símbolos contrastados con vectores externos; demodulación IQ sintética. | xng conserva formatos Unsupported y campos no implementados. GMDSS abarca más servicios que DSC; no afirmar GMDSS completo. |
| DGPS | [cruvolo/gr-dgps](https://github.com/cruvolo/gr-dgps) AGPL-3.0; [on1arf/dgps](https://github.com/on1arf/dgps) GPL-2.0 | GNU Radio/Python, RTCM/DGPS. | Repositorios de 2014/2021; sin evidencia macOS arm64. Requieren port, fixtures y auditoría de alcance. |
| LORAN-C | [KiwiSDR Loran_C](https://github.com/jks-prv/KiwiSDR/tree/master/extensions/Loran_C) | Monitor de pulsos, GRI y promedios. | No es solución completa de navegación. Depende de Kiwi; revisar licencia por archivo y portar. |
| DTMF/tonos | multimon-ng; Dire Wolf | Multimon añade CCIR/ZVEI/DUALTONE. | Tonos genéricos pueden quedar en el DSP Swift; comprobar tolerancia temporal/frecuencias. |
| Bit analysis | multimon-ng DUMPCSV/Scope; [SDRangel Channel Analyzer](https://github.com/f4exb/sdrangel/tree/master/plugins/channelrx/chanalyzer) | Exportación/exploración de muestras y señales. | No garantiza reconocer cualquier protocolo desconocido. |
| Globe Wireless | Sin decodificador mantenido y reutilizable verificado en esta búsqueda. | [iq_broadcast](https://github.com/eugenyh/iq_broadcast) enumera GW-PSK como **generador**. | Generar no prueba RX. Necesita especificación y grabaciones reales; el resultado negativo se limita a la búsqueda realizada. |
| Captura SDR USB (entrada) | SoapySDR y módulo del dispositivo; xng/acarsdec como consumidores | IQ complejo, tasa y frecuencia central, canales seleccionados. | Probar hardware/controlador concreto y sus dependencias arm64; captura USB no es un modo de decodificación. |

## Otras piezas y descartes útiles

- [SDRangel](https://github.com/f4exb/sdrangel), GPL-3.0, tiene arquitectura de plugins y decodificadores de CW, RTTY, PSK31, WEFAX, NAVTEX, DSC y packet. La [release 7.27.2](https://github.com/f4exb/sdrangel/releases/tag/v7.27.2), del 19-08-2026, ofrece `sdrangel-7.27.2_mac-14.8.7_arm64.dmg`. Es alternativa integral/referencia; reutilizar plugins implica la arquitectura Qt/C++ y dependencias, no una conexión directa a Swift.
- [libacars](https://github.com/szpajder/libacars), **MIT**, decodifica contenidos ACARS ADS-C/CPDLC/MIAM/OHMA; no demodula audio. Su [README](https://github.com/szpajder/libacars/blob/master/README.md) declara macOS/Clang. Encaja detrás de acarsdec o de un demodulador propio.
- [Hamlib](https://github.com/Hamlib/Hamlib): biblioteca **LGPL-2.1+**, utilidades/ejemplos **GPL-2.0+** según [LICENSE](https://github.com/Hamlib/Hamlib/blob/master/LICENSE). Útil para CAT/PTT/serial, por biblioteca o `rigctld`; disponer de PTT no implica habilitar transmisión en la aplicación.
- [Caperean/csstv](https://github.com/Caperean/csstv), MIT, implementa encode/decode y [C ABI](https://github.com/Caperean/csstv/blob/main/docs/API.md), pero sólo **PD50–PD290**, todavía 0.1.x y sin una prueba específica macOS arm64 verificada. Es candidato ligero para investigación de SSTV parcial.
- [rimio/libsstv](https://github.com/rimio/libsstv), MIT, **sólo codifica**: su [README](https://github.com/rimio/libsstv/blob/master/README.md) advierte que RX aún no está implementado. No presentarlo como receptor SSTV.
- [MarioKlebsch/QSSTV-macos](https://github.com/MarioKlebsch/QSSTV-macos), GPL-3.0, quedó en 2023. Se priorizó el fork Qt6 de tomtastic.
- [KiwiSDR](https://github.com/jks-prv/KiwiSDR) es la continuación actual del repositorio archivado `Beagle_SDR_GPS`. Su [_LICENSE](https://github.com/jks-prv/KiwiSDR/blob/master/_LICENSE) exige consultar licencias de subdirectorios/archivos; mezcla GPL y MIT. [ALE_2G/decode_ff_impl.cpp](https://github.com/jks-prv/KiwiSDR/blob/master/extensions/ALE_2G/decode_ff_impl.cpp) declara GPL-3.0+. No se verificó build local macOS.
- [radiolab81/DGPS_decoder](https://github.com/radiolab81/DGPS_decoder) contiene DSP/RTCM y simulador host recientes. No se encontró licencia explícita en el inventario y README consultados: no copiarlo al proyecto. Los decodificadores RTCM/NTRIP de otras bibliotecas no sustituyen por sí solos un demodulador MSK de balizas DGPS.
- [SSTVAE](https://github.com/arodland/SSTVAE) ofrece una aplicación experimental para imágenes mediante codec neuronal, con builds Apple Silicon, pero su README declara **sin interoperabilidad con SSTV existente** y formato todavía cambiante. No usarlo para sustituir SSTV analógico de MultiMode. Código Artistic-2.0; su icono tiene restricciones separadas.

## Contratos documentados para adaptadores

Los comandos siguientes se contrastaron con documentación/código; **no se ejecutaron**. Un adaptador debe comprobar versión, arquitectura y capacidades reales del ejecutable seleccionado antes de activar el modo.

### ACARS de audio/WAV

```sh
acarsdec --sndfile captura.wav --output json:file:path=-
```

El [README](https://github.com/f00b4r0/acarsdec/blob/master/README.md) permite archivos soportados por libsndfile y exige una tasa múltiplo de 12 kHz. El [parser soundfile.c](https://github.com/f00b4r0/acarsdec/blob/master/soundfile.c) acepta el nombre directo del archivo; permite parámetros adicionales para PCM crudo. [CMakeLists.txt](https://github.com/f00b4r0/acarsdec/blob/master/CMakeLists.txt) controla SNDFILE/CJSON/ALSA y otras dependencias opcionales. JSON necesita CJSON; WAV necesita SNDFILE.

### xng: IQ, no WAV

```sh
# IQ I/Q intercalado de RTL-SDR; JSON por stdout.
xng decode captura.cu8 --mode acars -r 2400000 -c 131.500M \
  --channels 131.550,131.725 --format cu8 --json

# Parámetros del fixture NAVTEX real documentado por el proyecto.
xng decode navtex_62500.cs16 --mode navtex -r 62500 -c 516k \
  --channels 518k --format cs16 --json
```

[main.rs v0.21.0](https://github.com/airframesio/xng/blob/v0.21.0/src/main.rs) define `decode`, archivo, `--format`, tasa/centro/canales y `--json`. El [lector IQ](https://github.com/airframesio/xng/blob/master/crates/xng-sdr/src/file.rs) soporta `cf32`, `cs16`, `cs8`, `cu8` y contiene una prueba explícita donde `.wav` no se reconoce. Los parámetros NAVTEX proceden de [NAVTEX.md](https://github.com/airframesio/xng/blob/master/docs/notes/NAVTEX.md): captura SDRplay a 62.5 kS/s, centro 516 kHz, canal 518 kHz. No convertir una grabación de audio mono en supuesto IQ sólo cambiando la extensión.

Los binarios de xng con soporte SDR requieren las bibliotecas de runtime declaradas en README, incluida SoapySDR. Compilar sin las funciones SDR permite estudiar reproducción IQ sin instalar controladores globales. No activar automáticamente envío a servicios externos ni interfaces de red.

### fldigi: control y resultados

Inicio documentado:

```sh
fldigi --xmlrpc-server-address 127.0.0.1 --xmlrpc-server-port 7362
```

La [API XML-RPC oficial](https://www.w1hkj.org/FldigiHelp/xmlrpc_control_page.html) ofrece:

- `modem.get_names`, `modem.set_by_name`: enumerar y elegir modos reales del motor.
- `rx.get_data`: bytes RX acumulados desde la consulta anterior.
- `navtex.get_message`: siguiente mensaje NAVTEX/SITOR-B, con timeout.
- `wefax.get_received_file`: nombre del siguiente archivo WEFAX recibido.
- `main.rx_only`: desactivar TX, si se necesita un adaptador receptor.

La tabla publicada no expone inyección de PCM ni playback WAV por XML-RPC. [File → Audio → Playback](https://www.w1hkj.org/FldigiHelp/menus_page.html) sí permite reproducir WAV en la aplicación. Por tanto, la integración automática WAV requiere una ruta de audio/interfaz adicional verificada; no prometer decodificación batch mediante XML-RPC con esta evidencia. Las imágenes de Hell y SSTV necesitan un contrato de renderizado diferente del texto RX.

### multimon-ng: audio crudo

El [README](https://github.com/EliasOenal/multimon-ng/blob/master/README.md) documenta conversión WAV a PCM firmado de 16 bit a 22050 Hz y entrada por stdin. RadioWorkbench puede preparar esa entrada con su procesamiento de audio; no necesita asumir que un WAV ya cumple la tasa/formato. Elegir demoduladores explícitos y parsear la salida del modo elegido.

## Evidencia pendiente antes de incorporar un motor

Falta una compilación o prueba local de los componentes seleccionados, inspección de arquitectura y dependencias de los ejecutables que se empaqueten, y comparación con grabaciones reales por modo. Las afirmaciones de compatibilidad del documento se limitan a fuentes primarias consultadas. Cualquier incorporación debe registrar versión y entrada, distinguir resultado vacío de fallo del motor y exponer los modos aún no implementados con claridad.
