# ACARS VHF de audio · RadioWorkbench 0.6

Recepción de ACARS clásico a 2400 baud desde audio demodulado en AM. Funciona
con archivos legibles por AVFoundation y con el dispositivo/canal de entrada
seleccionado en la app. No es VDL2, HFDL, ADS-B ni un receptor I/Q directo.

## Motor y procedencia

Se integra [f00b4r0/acarsdec](https://github.com/f00b4r0/acarsdec), revisión
`cbaa28c4173fc1529a01ab50708e29d12d09a644`, como ejecutable **arm64** separado.
La adaptación compila `msk.c`, `acars.c` y `script/acars-helper.c`, sin instalar
paquetes globales ni depender de libsndfile, ALSA, cJSON o libacars.

El helper recibe float32 mono de 12000 Hz por stdin y devuelve bloques
validados como JSON por stdout. No tiene destinos UDP/MQTT, dispositivos de
radio ni lectura de archivos. La captura, selección de canal y lectura WAV
pertenecen a RadioWorkbench. El callback CoreAudio conserva su ring SPSC; el
remuestreo, pipes y motor se ejecutan fuera de ese callback.

Las fuentes del helper están en `Vendor/acarsdec`; conservan licencia
**GPL-2.0-only** y avisos de sus autores. El paquete incluye la licencia y
`ACARS-Sources.tar.gz`, con fuentes completas del componente y su script de
compilación. «Licencia y fuentes» permite localizarlas. Separar procesos
describe la arquitectura; no declara una excepción a obligaciones de licencia.

Se modificó el cierre de la cola para drenar los últimos paquetes antes de salir
y se limitó la cola a 256 bloques, informando descartes. El DSP y los algoritmos
de paridad/CRC/corrección se conservan. El adaptador JSON y los cambios se
documentan en `Vendor/acarsdec/RADIOWORKBENCH-PATCHES.md`.

## Audio y SDR++

| Ajuste | Valor inicial |
|---|---|
| Demodulación RF | **AM** |
| Filtro RF | **10–12,5 kHz**, ajustable al canal |
| Audio útil | 300–3500 Hz; conservar tonos 1200/2400 Hz |
| Salida del cable virtual | 48 kHz recomendado |
| Tasas aceptadas por la app | 8–384 kHz; remuestreo interno a 12 kHz |
| Squelch / reducción de ruido de voz | Desactivados |
| Canal | Mezclar solo si L/R corresponden a la misma señal; elegir uno en capturas multicanal |

La separación entre canales RF no equivale al ancho ocupado ni al ancho del
audio. El preset inicial se apoya en los tonos y el comentario AM de 10 kHz del
[contrato del motor](https://github.com/f00b4r0/acarsdec/blob/cbaa28c4173fc1529a01ab50708e29d12d09a644/acarsdec.h)
y su [contrato de audio a múltiplos de 12 kHz](https://github.com/f00b4r0/acarsdec/blob/cbaa28c4173fc1529a01ab50708e29d12d09a644/soundfile.c).

El remuestreador propio usa un FIR sinc con ventana, normalización y 128 fases;
mantiene el reloj a través de los bloques y filtra antes de reducir la tasa.
Los controles de frecuencia y umbral de otros motores no se muestran: acarsdec
hace su propia adquisición MSK. Los ajustes RF se aplican manualmente en SDR++.

## Mensajes y límites

La tabla conserva los últimos 200 mensajes: hora **de decodificación**, matrícula,
vuelo, etiqueta y contenido. La ficha conserva modo, bloque, número de mensaje,
ETX/ETB y correcciones de paridad. El vuelo y número se extraen del prefijo
estándar de un downlink cuando existe; una ausencia se muestra como tal.
Texto y JSON pueden exportarse. Los tiempos de un WAV no se presentan como la
fecha de recepción original, porque el archivo no aporta ese dato.

La validación/corrección es la del motor acarsdec. `parityCorrections` cuenta
errores de paridad, no todas las correcciones posibles en datos/CRC. El nivel
es interno del DSP, no potencia RF calibrada. Un CRC válido no autentica la
matrícula, el vuelo ni el contenido de la transmisión.

No están incorporadas interpretación ARINC-622 ADS-C/CPDLC, ensamblado de bloques
fragmentados, rutas/cartografía ni identificación de modelo mediante bases
externas. Las listas comerciales del MultiMode original no se distribuyen.

## Validación

La muestra upstream `test.wav` tiene cuatro canales independientes a 12 kHz.
El ejemplo incluido extrae el canal 0: **F-GTAE, AF7728, H1**. El manifiesto
`acars_upstream_12000_mono.json` conserva fuente y SHA-256. No se afirma una
fecha, localización o procedencia RF de esa captura no documentada.

`script/generate_acars_fixtures.py` es un transmisor matemático independiente:
ASCII con paridad impar, CRC reflejado 0x8408 inicial 0, prekey/sincronía,
NRZI, fase continua y tiempos de símbolo exactos. No importa el código del
receptor. Genera 12/44,1/48 kHz, un error reparable, cuatro errores de paridad
rechazados y CRC inválido. El manifiesto conserva bytes transmitidos y hashes.

Las pruebas verifican matrícula/vuelo/texto, continuidad con bloques de 317
muestras, cuatro mensajes en un único proceso, cola final al EOF, duración y
continuidad del FIR, silencio, reinicios, motor ausente y cancelación del helper.
Queda pendiente recepción RF/captura real de SDR++, fading y corpus más amplio.
