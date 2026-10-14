# AX.25 / APRS AFSK1200

Motor propio en Swift para recepción pasiva de tramas UI de AX.25, incluido
el contenido APRS. No requiere ejecutar Dire Wolf ni instalar librerías.
SSTV permanece independiente.

## Qué recibe

Audio Bell 202 a 1200 símbolos/s: tonos de 1200 y 2200 Hz, centro de audio
1700 Hz. `PacketAFSK1200Decoder` usa dos correladores en cuadratura,
integración deslizante de un símbolo y reloj corregido por transiciones.
Después aplica NRZI: cambio de tono significa cero; tono constante, uno.

`PacketHDLCReceiver` identifica flags 0x7E, elimina el cero insertado tras
cinco unos y acepta únicamente tramas completas, alineadas a octetos y con
FCS válido. El CRC reflejado X-25 usa polinomio 0x8408 e inicio 0xFFFF; con
el FCS recibido, el residuo debe ser 0xF0B8. Esta representación contempla
el orden de bits del FCS mediante su reflexión, no intercambia sus bytes.
[AX.25 2.2, §§3.1–3.12](https://files.tapr.org/tech_docs/AX25/AX25.2.2.1997.pdf),
[RFC 1662, apéndice C](https://www.rfc-editor.org/rfc/rfc1662.html#appendix-C).

Las direcciones muestran destino, origen, SSID y hasta ocho repetidores,
incluido `*` en los repetidores que ya trataron la trama. Solo se admite
control UI 0x03 o 0x13 con el bit P/F. Para PID 0xF0 la salida es formato
monitor `ORIGEN>DESTINO,RUTA:contenido`; otros PID se identifican en hexadecimal.
Los octetos fuera de ASCII imprimible se conservan como `\xNN`.
[APRS Protocol Reference 1.0.1, capítulo 3](https://www.aprs.org/doc/APRS101.PDF).

El código de RadioWorkbench no incorpora código de Dire Wolf. Su implementación
pública se consultó para comprobar el convenio NRZI y los bytes del FCS:
[HDLC](https://github.com/wb2osz/direwolf/blob/master/src/hdlc_rec.c),
[FCS](https://github.com/wb2osz/direwolf/blob/master/src/fcs_calc.c).
SHA de blobs consultados: `cfae77a6467138d4d02668a5e489c064e0b05fbd` y
correlador de referencia `3e5d03ec8693c6f4a89f70e1ad730f83b898b862`.

## SDR++ y audio

Preset inicial recomendado por esta implementación:

| Parámetro | Valor |
|---|---|
| Demodulación RF | NFM |
| Ancho de recepción RF | Aproximadamente 12–15 kHz; ajustar al canal y desviación real |
| Audio útil | 300–3000 Hz; preservar ambos tonos |
| Frecuencia central en RadioWorkbench | 1700 Hz |
| Baudios | 1200 fijos |
| PCM | 8 kHz mínimo; 44,1 o 48 kHz recomendado |
| Canal | Mezclar si L/R son equivalentes; elegir L o R si se cancelan |

Desactivar reducción de ruido de voz y evitar que el squelch corte el comienzo
del paquete. Preferir audio sin deénfasis para iniciar las pruebas; el balance
entre tonos puede cambiar con filtros de voz. La inversión de fase de todo el
audio o intercambiar los dos tonos no requiere invertir los bits: NRZI depende
de los cambios, no de cuál tono representa uno.

## Validación

`script/generate_packet_fixtures.py` genera archivos sin importar código Swift.
El transmisor usa `binascii.crc_hqx` con reflexión explícita y modulación con
fase continua. El receptor usa un CRC bit a bit independiente. El manifiesto
contiene protocolo, texto esperado, bits transmitidos y SHA-256 de cada WAV.
El vector de control `123456789` da FCS 0x906E.

Ocho WAV cubren 8 kHz mono, 44,1 kHz estéreo y 48 kHz en oposición de fase;
ruido gaussiano a 16 dB de SNR, desplazamiento de ambos tonos +45 Hz,
transmisor a 1206 símbolos/s, CRC dañado y recuperación entre ráfagas.
El caso de recuperación contiene una trama válida, otra corrupta y una segunda
válida, y exige exactamente dos mensajes y un CRC rechazado.

Las pruebas `PacketTests.swift` también recorren bits HDLC independientes,
direcciones inválidas, control UI/P-F, abortos, tamaño máximo, límite de 64 tramas
retenidas, octetos de control, ruido sin trama y ausencia del flag de cierre.
Procesan bloques de audio de 137 muestras para comprobar continuidad entre
llamadas. Para repetir: `RADIO_BUILD_PATH=/tmp/radioworkbench-packet-tests script/test.sh --filter packet`.
También verifican la integración por `DecoderEngine` y el rechazo de tasas
menores de 8 kHz o de cualquiera de los dos tonos fuera del intervalo de Nyquist.
Verificación local del 13 de octubre de 2026: 21 casos en 11 funciones,
todos aprobados en 0,090 s; registro `/tmp/radioworkbench-packet-tests.log`.

## Límites

Esta validación usa señales sintéticas independientes. Aún falta comprobar
grabaciones RF, radios reales y captura continua desde SDR++.
Un CRC válido comprueba integridad de trama; no autentica la estación ni la
veracidad del mensaje.

El motor muestra contenido APRS sin convertir coordenadas, Mic-E, posiciones
comprimidas, meteorología o telemetría a objetos estructurados. No es un TNC
de sesión: no ejecuta AX.25 conectado, transmisión, digipeating ni iGate.
Tampoco cubre packet HF 300 baud, G3RUH/9600, FX.25 o IL2P. Los formatos
requieren motores y pruebas separados. No corrige errores de CRC ni inventa
paquetes a partir de fragmentos sin delimitadores.

La memoria es acotada: 4096 bits para una candidata, 330 octetos decodificados,
64 tramas recientes y texto recortado entre 32 y 64 KiB. Demodulación y parseo
corren en el worker de RadioWorkbench, fuera del callback CoreAudio; el callback
sigue limitándose a la cola SPSC. Las métricas incluyen tramas aceptadas,
CRC rechazados, formato rechazado y abortos.
