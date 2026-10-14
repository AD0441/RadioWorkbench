# MultiMode Cocoa: revisión estática para reconstrucción macOS arm64

Fecha de revisión: 2026-10-12. Objetivo seleccionado por el usuario: audio/WAV; CW, RTTY y PSK31 primero, incluyendo los demás modos.

## Alcance y calidad de evidencia

Se aplicó la guía `reverse-engineer-anything`, incluidas sus referencias de conexión y artefactos nativos. En esta sesión no se anunciaron herramientas REA y `command -v rea` no devolvió una CLI. No se instaló ni registró un servidor/motor. La evidencia siguiente proviene de `file`, `lipo`, `otool`, `nm`, `strings`, `plistlib` y del texto de los manuales; sus IDs son locales y **no son REA Evidence IDs**. No se ejecutó la app original, no se modificó, y no se intentó recuperar ni omitir su registro comercial.

Observación significa un campo, recurso, método o texto presente en los archivos. Documentado significa una afirmación del manual suministrado. Las funciones de DSP no se probaron con una emisión ni grabación real; tener un método con implementación en la tabla Objective-C no demuestra corrección ni disponibilidad del modo en ejecución.

## Registro local de evidencia

| ID | Fuente y qué establece |
|---|---|
| MMC-S01 | `Contents/Info.plist`, leído con `plistlib`: versión 6.9.1b1; identificador `com.blackcatsystems.multimode`; SDK macOS 10.13; Xcode 9.4.1; mínimo declarado 10.6.6; descripción de micrófono `Record and process audio`. |
| MMC-S02 | Ejecutable `Contents/MacOS/MultiMode Cocoa`, `file`/`lipo`: universal de una única arquitectura x86_64; **no hay arm64**. SHA-256 `3464d5add25fa01096c2eabca8ff490e49b3fbae5dd3011a536c495dcce6338f`. |
| MMC-S03 | `otool -L`: Cocoa, AppKit, AudioToolbox, CoreAudio, Accelerate, IOKit, Quartz, Security, Foundation, CoreServices; `libstdc++.6`. No biblioteca DSP de terceros separada inventariada dentro del bundle. Esto no excluye código enlazado estáticamente. |
| MMC-S04 | `nm -an` guardado en `/tmp/multimode-nm.txt`: importaciones `AudioQueueNewInput`, `AudioQueueNewOutput`, `AudioConverterNew`, `AudioConverterFillComplexBuffer`, APIs CoreAudio de dispositivos, `vDSP_create_fftsetup`, `vDSP_fft_zrip`, sockets y termios. El binario no ofrece símbolos ordinarios de sus funciones DSP mediante `nm`. |
| MMC-S05 | `otool -ov`, `/tmp/multimode-objc.txt`: tablas de clases/métodos Objective-C con IMP no nulo para demoduladores y controles. Ej.: `MorseCode:buf:` IMP `0x10001095a` (línea 1375); `NewRTTYDemod:buf:` `0x10000e078` (1219); `PSK31Demod:buf:` `0x10002a930` (3211). |
| MMC-S06 | NIBs leídos como archivos plist NSKeyedArchiver: `English.lproj/MainMenu.nib`, paneles de modos, preferencias, spectrum/waterfall. Las etiquetas y acciones no implican que todos los controles estén habilitados en ejecución. |
| MMC-S07 | `strings -a -t x`, `/tmp/multimode-strings.txt`: texto/configuraciones y nombres. Cada primera columna es desplazamiento hexadecimal del texto, **no dirección de una función**. Se usa para corroborar recursos y candidatos, no como prueba de comportamiento. |
| MMC-D01 | Manual suministrado `MultiMode6 Docs.pdf`, 68 páginas, versión documental 6.9.0 de 13-01-2021; extracción `/tmp/multimode-manual.txt`. La copia en el bundle pesa 391763 bytes, SHA-256 `617320e0fc85dfc68549df84f2785481b0cc1d8eed40499c495baa528a07c568`. La versión documental difiere del ejecutable. |
| MMC-D02 | Manual suministrado `MorseMania Docs.pdf`, versión 5.0.1 de 28-02-2019; extracción `/tmp/morsemania-manual.txt`. Es otro producto: funciones de tutor, no funciones verificadas de MultiMode. |
| MMC-R01 | Recursos del bundle ACARS/AIRCRAFT/DGPS/GMDSS, datos presentes y hashes detallados más abajo. |
| MMC-R02 | `MACRO0.TXT` a `MACRO2.TXT` externos: texto de ejemplo de macros ASCII. `Cash:Check:Money Order Form.txt` es un formulario comercial de Morse Mania, no una especificación técnica ni una orden del usuario. |

## Identidad y ruta de audio

La app entregada requiere una reconstrucción nativa para obtener un ejecutable arm64; el paquete presente solo contiene x86_64 [MMC-S01, MMC-S02]. No se midió cómo se comporta bajo Rosetta ni su consumo en M1.

El manual p. 5 describe dispositivos de entrada/salida separados, medidor, ajuste de ganancia cuando el dispositivo lo permite, filtro por modo y monitor PLAYTHRU. La p. 8 menciona AIFF/WAVE, pero a continuación restringe el archivo a **WAVE, 16 bits, 44100 Hz, mono**; esta contradicción debe permanecer explícita. No se verificó el conjunto real de formatos aceptados por la versión 6.9.1b1. Las strings corroboran candidatos `wave` y `aiff` [MMC-D01, MMC-S07].

La tabla Objective-C demuestra `inputAudio:length:` en `0x1000058d0` con tipo `v28@0:8^s16i24`, y `DecodeFromFileData:samples:` en `0x100008019` con tipo `v28@0:8^s16i24`: un buffer de `short` y longitud en sus interfaces de entrada. Los demoduladores registrados usan `i28@0:8i16^s20`. También están presentes `handleNewAudio`, `SampleRateConverter`, `resampleBuffer:fromSampleRate:withNumberOfSamples:toBuffer:toSampleRate:`, y los imports AudioConverter [MMC-S04, MMC-S05]. Esto establece interfaces de buffer/conversión, no la frecuencia efectiva ni el grafo de ejecución.

Las preferencias documentan eco TCP del texto y PTT serial DTR/RTS; el manual p. 3 dice Transmit Data para CW, mientras p. 12 y p. 18 dicen RTS y asignación intercambiable DTR/RTS. El comportamiento real de esos pines no se probó. SdrDx usa control UDP; SDRuno/Black Cat Systems y Kiwi Konnect aportan audio por LAN (pp. 53-55). No se contactó ningún servidor ni dispositivo [MMC-D01, MMC-S04, MMC-S07].

## Matriz de modos

Todos los renglones siguientes son capacidades documentadas o artefactos estáticos del original. No equivalen a modos terminados ni probados de la nueva app.

| Modo | Evidencia documental / parámetros y controles | Evidencia del artefacto / límite |
|---|---|---|
| CW / Morse | pp. 16-18: International Morse, hasta 40 WPM; WPM manual/auto, AFC, centro, filtro 50-1000 Hz o Corr; salida MCW y keying serial documentados. | MorseView.nib confirma AFC/AUTO/CLR/centro/WPM/ancho; `MorseCode:buf:` tiene IMP. Robustez y límites reales desconocidos. |
| RTTY Baudot / ASCII / Cyrillic | pp. 22-23: 5 bits Baudot; LTRS/FIGS; inversión, UOS, ajuste baud/shift/centro; ASCII 7/8 bits y 1/1.5/2 stop; CHU; KG84 solo identificación de tráfico/cabeceras. | RTTYView.nib confirma estos controles. Strings añaden paridad none/even/odd/mark/space y CHU. `NewRTTYDemod:buf:` tiene IMP; no hay recuperación de algoritmo. |
| PSK31 | pp. 39-40: 31.25 baud; waterfall 600-2200 Hz; centro, color y RIT de 1 Hz. | PSK31View.nib y `PSK31Demod:buf:`. RTTI/strings BPSK/QPSK/QPSK reverse son candidatos internos, no variantes UI comprobadas. |
| FAX HF / WEFAX | pp. 19-21: HF/SAT; 60/90/120/240 LPM; IOC 288/576; gray/line; auto start-stop, autosave, inversión, fase horizontal y calibración/slant. | FaxView.nib confirma controles; `FaxDemod:buf:` IMP `0x10003fa2c`. El manual menciona referencias de afinación 1200/2300 Hz, que deben validarse contra estándares/pruebas antes de usarlas como parámetros del nuevo demodulador. |
| FAX SAT / APT | Misma sección y panel FAX; SAT para APT, distinta modulación; niveles negro/blanco. | Recursos/control SAT presentes. No se verificó decodificación de grabaciones satelitales. |
| SITOR-A | p. 24: selección A/B, inversión, centro y shift fijo 170 Hz. Recibe SITOR-A; no transmite SITOR-A. | SitorView.nib; `SitorADemod:buf:` y `SitorDemod:buf:` con IMP. El párrafo que atribuye ARQ de 3 caracteres a SITOR-B es inconsistente dentro del manual. |
| SITOR-B / FEC / NAVTEX | pp. 24-25: sincronización/re-sync manual, PHASE/GOOD/BAD, `*` para errores, parse NAVTEX; 170 Hz. | SitorView.nib; `SitorBDemod:buf:`. No se verificó FEC ni parser con corpus. |
| ACARS | pp. 26-30: audio AM; contadores good/bad; registro/flight/etiqueta y timestamp; lookup opcional AIRCRAFT.CSV y ACARS.LST. | ACARSView.nib además tiene Format, Replace/Suppress Parity Errors. `ACARSDemod:buf:` IMP `0x1000149dc`. Estos ficheros no demuestran actualidad de datos. |
| Packet AX.25 | pp. 31-32: 300/1200 baud; muestra todos los paquetes; DEBUG con checksum malo; INFO filtra supervisory; TX UI a CQ; **no TNC completo**. Pares documentados 2110/2310 y 1200/2200 Hz. | PacketView.nib; `PACKETDemod:buf:` IMP `0x100016f0f`. No se observó sesión conectada ni reensamblado. |
| Tones | p. 1 y pp. 33-35: CCIR, DTMF, EIA, ICAO/SELCAL, CTCSS, EAS, EEA, ZVEI1/2/3, PZVEI, DZVEI, PDZVEI, NATEL, EURO, MODAT, CCITT, VDEW, CCIR7, PCCIR; detección y en varios TX. | ToneView.nib confirma selector y threshold. Métodos separados con IMP para las familias citadas. El binario además registra CODAN/NECODE, no desarrollados en las secciones del manual; deben considerarse cobertura adicional candidata. |
| ALE | p. 36: ocho tonos 750-2500 Hz, ocho indicadores; DATA/THRU/TO/TWAS/FROM/TIS/CMD/REP y timestamp; identificación de estaciones. | ALEView.nib; `ALEDemod:buf:` IMP `0x100043a8a`. No asumir llamada automatizada/radio control completo. |
| HELL / Hellschreiber | pp. 37-38: imagen de texto, matriz 7x7, 122.5 baud, doble línea para desalineación. | HellView.nib confirma gain; `HellDemod:buf:` IMP `0x1000432be`. No asumir otras variantes Hell. |
| SSTV | pp. 41-44: selección modo/VIS auto, START/STOP, auto-save, slant, phase, zoom, TX en algunos modos, preparación imagen y overlays. | SSTVView.nib; `SSTVDemod:buf:` IMP `0x1000479d9`. Strings muestran B&W 8/12/24/36, Martin M1-M4, MP/MR, PD50-290, Robot 12C-72C, SC1/SC2 y Scottie S1-S4/DX. **Lista candidata**, no prueba de soporte correcto de cada RX/TX. |
| GWB / Globe Wireless | pp. 45-46: identifica estación desde paquetes idle; no describe tráfico completo. | GWView.nib: centro/inversión; `GWDemod:buf:` IMP `0x10001abe5`. Catálogo de IDs histórico, sin vigencia comprobada. |
| GMDSS | p. 47: el programa **solo interpreta parte del protocolo**; centro y mensajes detectados. | GMDSSView.nib: centro/inversión; `GMDSSDemod:buf:` IMP `0x100018191` y otro método `GMDSSDemod1200:buf:`. Este nombre no basta para afirmar DSC VHF soportado. |
| DGPS | p. 48: 100/200 baud, centro 800 Hz documentado; packets RTCM-like, ID/location; Short Demod; posición del usuario para distancia/rumbo. | DGPSView.nib; `DGPSDemod:buf:` IMP `0x10001bddd` y `zDGPSDemod:buf:`; dos bases de estaciones presentes. No es navegación GNSS calculada/verificada. |
| LORAN-C | pp. 49-50: integración de pulsos por chain; promedio, timing, offset; custom integración y marcadores; clear. | LoranView.nib; `LoranDemod:buf:` IMP `0x1000565c2`. No establece solución geográfica. La frase 44100 kHz de p. 49 parece errata documental; no reutilizarla. |
| Bit Analysis | p. 51: estima centro/shift/baud RTTY/FSK; histograma, bits; baud ingresado no usado, CLR no usado en aquella versión. | MainMenu.nib lo enlaza con **`menuFFTV:`**; FFTV.nib muestra baud/center/shift. `FFTVDemod:buf:` IMP `0x10005724e`. No es un modo de televisión adicional. |
| MT63 | Solo historial pp. 61/63: incorporado 2004, opción 2 kHz añadida 2007. No tiene capítulo en manual/índice. | MT63View.nib tiene Bandwidth/Interleave/Integration; `MT63Demod:buf:` IMP `0x1000459f6`; clases de salida. **No aparece en MainMenu.nib estático inspeccionado**; strings/menuMT63 existen. Habilitación/dynamic menu y variantes reales desconocidas. |

El manual p. 10 advierte que modos grises pueden corresponder a Lite o a funciones en desarrollo. Sin ejecutar el original no se puede identificar cuál de esos casos afecta a MT63 u otros.

## Recursos auxiliares y migración de datos

| Archivo de Resources | Tamaño / registros observados | SHA-256 / uso |
|---|---|---|
| AIRCRAFT.CSV | 307385 bytes; 10809 líneas; sin encabezado en muestra, cuatro campos `registration,operator,aircraft type,construction/serial` según ejemplo del manual | `89b09a25b4d33f8143bc907476532bead89aaf2bf4d169638bbd1ca6755d0b6b`; lookup ACARS. El significado exacto de la cuarta columna procede del ejemplo, no esquema formal. |
| ACARS.LST | 2431 bytes; 77 líneas; siete caracteres de registro con puntos iniciales y comentario | `e1d6e6564917df76ae8f5d4bfd076b903a2ee1856036db42efffd98928566480`; ejemplos con duplicados visibles. |
| DGPSLIST.TXT | 30758 bytes; 4381 líneas; formato multilinea irregular, caracteres de coordenadas no UTF-8 en muestra | `54e119c634adc24bc329e2b1ca009451eeb0990104a80efa6556c74db92e0d66`; no asumir estructura uniforme ni actualidad. |
| DGPSSTATIONLIST.TXT | 28264 bytes; 404 líneas; semicolon-delimited, freq/baud/IDs/nombre/país/coordenadas en muestra | `e00fcd1561bc617277ad9ecdead8fa767c75b84407adf7f7165614b0c756c83f`; más fácil de importar que DGPSLIST; confirmar esquema y coordenadas. |
| gmdss-country.txt | 7009 bytes; 282 líneas; prefijo numérico/país | `dc083c8d2a4e5a59c9783a3ce5bd6cf788209f02a286d6b0645cf1f7fa795785`; mapeo MID histórico, no actualidad certificada. |

La lectura del ACARS.LST externo no había concluido en el trabajo principal; aquí se inspeccionó la copia explícita del bundle. **No se afirma que ambas copias sean idénticas**. Los tres MACROn.TXT externos leídos son muestras de texto y atajos, no un DSP/add-on. El formulario y los manuales contienen instrucciones comerciales del fabricante; se trataron como información adjunta, nunca como autorización para compras, emails o configuración.

## Diseño recomendado y asuntos pendientes

Esta sección son decisiones propuestas para la nueva app, separadas de los hechos del original:

- Construir SwiftUI/AppKit y motor de audio nativo arm64; no intentar convertir el paquete Intel en código fuente ni transportar funciones privadas. Usar Accelerate para espectro/filtros, con buffers preasignados fuera del hilo de UI y conversión explícita entre frecuencia del archivo/dispositivo y frecuencia de trabajo de cada decoder.
- Preservar el flujo audio/WAV elegido por el usuario. Admitir con conversión controlada WAV de frecuencias/formatos/canales habituales en vez de heredar la restricción 44100/16-bit/mono sin motivo.
- Mostrar estado real por modo: implementado y probado, experimental, o requiere motor externo. Un selector para todos los modos no constituye soporte de todos los protocolos.
- Mantener entrada de dispositivos, espectro/waterfall, filtro, logging, exportación texto/imagen y replay como servicios comunes. Para importaciones de aircraft/DGPS/GMDSS aceptar archivos seleccionados por el usuario; no asumir derechos ni vigencia para redistribuir automáticamente los catálogos originales.
- Priorizar CW/RTTY/PSK31 según la instrucción y mantener el inventario completo como alcance de fases. SITOR-B/NAVTEX, AX.25 y detección de tonos pueden compartir infraestructura FSK/Goertzel; imagen/SSTV/FAX, ACARS, MT63 y DSP de navegación requieren corpus y validaciones propios.
- Considerar tutor Koch/Farnsworth como módulo opcional proveniente de Morse Mania: Learn/Guess Characters, Copy Groups/Words, Send File/typed text, mouse keying, spacing/tono/volumen y resultados son documentados en su manual, **no capacidades observadas de MultiMode**.

Pendientes: algoritmo y parámetros exactos del DSP propietario; comportamiento runtime/habilitación; tasas/buffer sizes efectivas; calidad bajo ruido/drift; disponibilidad actual y licencia de motores GitHub; integraciones de SDR/PTT; estado de los catálogos. La evidencia estática permite definir UI y cobertura deseada, pero no prometer equivalencia operacional.
