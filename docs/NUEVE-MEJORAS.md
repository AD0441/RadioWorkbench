# Ampliaciones de recepción y herramientas locales

Alcance acordado el 18 de octubre de 2026. Este documento distingue función
implementada, evidencia de laboratorio y comprobaciones físicas pendientes.

| Orden | Función inicial | Uso y límites |
|---|---|---|
| 1 | Biblioteca de recepciones | Copia el audio original y sus ajustes completos, modo, parámetros RF declarados, fecha de importación y captura opcional. Restaura esos ajustes para volver a decodificar. Papelera recuperable. Máximo 1 GB/audio y 1.000 fichas. SHA-256 comprueba que la copia no cambió. No graba micrófono automáticamente. I/Q/SigMF y comparación entre motores quedan para ampliación. |
| 2 | Diagnóstico de entrada | RMS dBFS, pico, DC, muestras al límite, valores no finitos, tasa/canal y descartes del búfer. Explica acciones según observaciones, separando mediciones del último bloque y contadores de sesión. Describe CRC/FEC según el protocolo; no inventa un denominador de paquetes enviados ni un SNR RF. Prueba guiada de conexiones posterior. |
| 3 | Audio TCP local | Entrada seleccionable con formato PCM s16le/float32le, tasa y canales explícitos, mezcla/canal individual, límites y cierre que drena el audio antes de finalizar el motor. Solo loopback, acción Escuchar, sin reconexión. Brown Network Sink: TCP, s16le, mono, 48 kHz; no confundir con Network Source I/Q o voz ya decodificada. UDP y medición de pérdidas de datagramas son posteriores. |
| 4 | DSC marítimo | MF/HF 100 baud/170 Hz, centro ajustable e inversión; VHF 1200 baud/1300–2100 Hz con opción de audio compensado. Diversidad temporal, paridad de símbolos y ECC; solo se publican tramas completas aceptadas. Exporta identidades, algunos canales, símbolos y estado ECC. **Interpretación parcial**; no genera coordenadas, clasificación completa de emergencias, autenticación ni avisos de rescate. GMDSS abarca otros servicios. |
| 5 | Mapa común | Posiciones APRS con CRC AX.25 local, ADS-C de ACARS y APRS-IS optativo; origen, hora y antigüedad visibles. Conserva hasta 5.000 eventos, muestra 300 posiciones y trazas acotadas. No une fuentes distintas, saltos mayores de 30 min ni el antimeridiano. No dibuja movimiento de archivos/importaciones sin hora de observación. No inicia APRS-IS ni comparte ubicación por abrir el mapa. AIS/RS41 y alertas son ampliaciones. |
| 6 | SatDump offline LRPT | Elige SatDump.app y un archivo I/Q crudo con formato, tasa, RF y captura UTC declarados. Ejecuta el pipeline 72/80k en una carpeta nueva, muestra registro/progreso de etapa, admite cancelación e incorpora productos con vista previa de imágenes reconocidas. Red bloqueada y escrituras limitadas al trabajo mediante sandbox de macOS. No TLE automático, SDR en vivo ni georreferenciación confirmada. Hasta 100 GB y dos horas. |
| 7 | Sintonía optativa | Desde Consultas, prepara frecuencia/modo/ancho. Una opción separada habilita Rigctl local: comprobar solo lee; enviar realiza una acción explícita y vuelve a leer para verificar. Solo F/M y f/m; sin PTT, grabación, exploración o Doppler automático. No modifica el receptor por seleccionar una consulta. |
| 8 | Eventos externos | Formato JSON v1 documentado, fechas/coordenadas/tamaños validados y lote rechazado si algún registro es inválido. Procedencia declarada, IDs separados de los internos y fecha local de importación. No interpreta órdenes ni abre URLs del contenido; un CRC declarado por otro programa no se verifica de nuevo. NMEA/telemetría por protocolo son ampliaciones. |
| 9 | Taller de señales | Referencias sintéticas CW, RTTY y BPSK31, sonido a petición, parámetros y texto conocido. Compara potencia espectral media y dBFS de hasta 12 s de un archivo propio; permite elegir canal y probar los ajustes en el decodificador. No activa micrófono ni clasifica automáticamente. Ejercicios CW y clasificación con incertidumbre son posteriores. |

## Validación y límites

La biblioteca se prueba con carpetas temporales, corrupción del índice, límites,
archivos ausentes, enlaces simbólicos, papelera, escrituras fallidas e importación
concurrente. TCP se comprueba con servidores locales simulados, fragmentos que
cortan muestras/canales, EOF, espera agotada, saturación del búfer y cancelación.
No se realizó todavía interoperabilidad física Brown → RadioWorkbench ni la
prueba aplazada SDR++ → VB-Cable.

DSC usa el núcleo abierto SDRangel fijado y una adaptación PCM independiente;
[fuente y licencia](../Vendor/DSC/NOTICE.md), [cambios](../Vendor/DSC/LOCAL-CHANGES.md).
Pasó 18 comprobaciones aisladas, también con ASan/UBSan: audio VHF público con
identidades/canal conocidos, cinco llamadas de una grabación MF/HF independiente,
diversidad dañada, ECC incorrecto, ausencia de sincronía, ruido, silencio después
de un mensaje, truncado, fragmentación y publicación antes de EOF. El recuento
HF observado no prueba que se recuperen todas las llamadas. Los audios externos
no se distribuyen sin licencia; los ejemplos incluidos son sintéticos.

SatDump 1.2.3-943de7d fue ejecutado con I/Q cero y red/escrituras restringidas.
Procesó las etapas hasta descriptores vacíos, sin imagen: ese resultado es un
**negativo**, no una recepción LRPT. Su fuente `src-cli/offline.cpp` contiene un
retorno 1 incondicional tras el pipeline; además emite porcentajes infinitos o
fuera de rango en ese caso. La app conserva el código de salida, rechaza tales
porcentajes y no considera un descriptor o la presencia de una carpeta como
imagen recibida. El adaptador se comprueba además con un CLI simulado; todavía
falta una grabación I/Q LRPT independiente con productos esperados para validar
la calidad de extremo a extremo.

Rigctl se verifica con un servidor simulado, incluido el caso que contesta
`RPRT 0` pero ignora la sintonía. No se enviaron órdenes al SDR del usuario.
El taller usa referencias matemáticas independientes del decodificador. Los
resultados y recuentos definitivos de la suite se conservan en `docs/validation`.
