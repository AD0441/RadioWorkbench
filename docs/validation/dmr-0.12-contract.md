# Contrato DMR comprobado en DSD-neo 2.10.0

Revisión del 18 de octubre de 2026. Pruebas offline del **ejecutable oficial arm64**, sin micrófono, SDR, reproducción de audio ni conexión TCP. El informe medido completo está en [dmr-0.12-contract.json](dmr-0.12-contract.json); el procedimiento reproducible, en [dmr_runtime_contract.py](../../script/validation/dmr_runtime_contract.py).

## Identidad

| Elemento | Identidad |
|---|---|
| [DMG oficial 2.10.0](https://github.com/arancormonk/dsd-neo/releases/tag/v2.10.0) | SHA-256 `260e7aaaa02301dbfce2fb1d7492e3e0be4e64f6f654059e5d52f2c4f5131a58` |
| Ejecutable distribuido | SHA-256 `dff6a26e4fb1bd6bc67dc408b4e06352ca875376135681aa2d17bda02c26efe7`; banner `v2.10.0 (ff5843f)` |
| Sistema mínimo declarado en Mach-O | macOS 26.0, arm64. No cambia el mínimo de la app principal. |
| Corpus independiente | [Grabación aportada a SDRTrunk #1803](https://github.com/DSheirer/sdrtrunk/issues/1803), 6 438 956 bytes, SHA-256 `5cc14eb12ce0d2fb452582484f415dc873b8b6c5df8d7a3186bcdd183986e675` |

El paquete se montó en solo lectura y se copió a una carpeta temporal propia, sin instalación global. La versión del vocoder anunciada por este binario es MBElib-neo 2.1.0.

La investigación reutiliza la evidencia REA de Brown conservada en [el informe anterior](../DMR-BROWN-0.10.md). Las mediciones nuevas proceden de ejecución controlada con pipes; **no se les atribuyen identificadores REA**. No había herramientas REA conectadas ni una CLI en la búsqueda acotada de los lanzadores existentes. No se instalaron proveedores ni se repitió el inventario de Brown.

## Resultado de audio

Con `--frontend none -fs -i - -s 48000 -o -`, sin `-y`:

- Entrada: PCM firmado de 16 bits, little endian, mono, 48 kHz, sin cabecera.
- Salida stdout: **PCM firmado de 16 bits, little endian, estéreo intercalado, 8 kHz**, sin cabecera.
- `-w` generó un WAV de 8 kHz, dos canales y 16 bits. En siete variantes enteras, el PCM de stdout fue idéntico a los datos del WAV.
- La recepción con voz produjo 158 400 tramas estéreo: 633 600 bytes y 19,8 segundos de audio. El original I/Q dura aproximadamente 32,2 segundos; la salida no representa un reloj continuo que rellene todos los silencios de recepción.
- Los 633 600 bytes estaban disponibles **mientras stdin seguía abierto**. El primer bloque apareció a los 0,396 segundos de comenzar la ejecución de la prueba rápida, que alimenta la grabación sin esperar su duración real. Ese tiempo no es una medición de latencia de recepción por radio.

| Opción | Resultado con la llamada identificada en TS1 |
|---|---|
| `-V 3` | Voz de TS1 duplicada en ambos canales. |
| `-V 1` | Mismo PCM que `-V 3`. |
| `-V 2` | Igual cantidad de tramas; ambos canales completamente en silencio. La llamada continúa en los mensajes diagnósticos. |
| `-V 0` | No produce audio ni tramas WAV; conserva la identificación de la llamada. |
| `-z 0`, `-z 1`, `-z 2` | Mismo audio en esta grabación de una sola llamada audible. `-z` expresa preferencia y no sustituye el filtro de síntesis `-V`. |
| `-fr` | El algoritmo anunciado como «single-slot mono» también produjo **dos canales** en este binario. No deducir el formato de transporte de la palabra «mono». |
| `-y` | Produjo float32 estéreo con voz solo en el canal izquierdo y WAV sin tramas. Se registra como límite de esta combinación; no se usa para la integración. |

El bloque de salida del código fijado usa escritura directa al descriptor, sin esperar un vaciado de stdio. La observación de stdout antes de EOF corrobora esa publicación durante la ejecución. Fuente revisada: [dsd_audio2.c](https://github.com/arancormonk/dsd-neo/blob/v2.10.0/src/core/audio/dsd_audio2.c), SHA-256 `f1ea36027b8e11e2819a4ead3b5bc0f526aa401c57d76782260b42d8024eaaab`.

## Detención y controles negativos

Cuatro pruebas mantienen abiertas las dos tuberías de salida y las drenan en paralelo. La entrada se fragmenta deliberadamente en bloques de 8 191 bytes, también en límites impares.

| Finalización | Resultado medido |
|---|---|
| Cerrar stdin para indicar EOF | Salida limpia, código 0, 0,317 segundos después del cierre. |
| Enviar SIGTERM con stdin abierto y sin más bytes | Permanece bloqueado; no terminó en tres segundos y se cerró con SIGKILL. |
| Cerrar stdin y después enviar SIGTERM | Salida limpia, código 0, 0,420 segundos; no necesitó SIGKILL. |
| Dos segundos de ceros seguidos de EOF | Cero bytes de audio, cero llamadas y cero códigos de color. Salida limpia. |

La integración debe cerrar la entrada al detener y mantener la lectura de stdout/stderr hasta el final, con un límite temporal para el proceso propio. SIGTERM por sí solo no constituye una detención suficiente para el caso probado.

## Identificadores y fiabilidad

El comentario público de lwvmobile del 24 de enero de 2024 en SDRTrunk #1803 proporciona un oráculo independiente de **TS1, destino 9990, origen 3025209 y llamada privada**. Estos cuatro valores coinciden con el ejecutable oficial probado. El código de color 07 fue observado en esta ejecución; no formaba parte del oráculo publicado.

Ejemplos de forma de salida, sin cabeceras de rutas locales:

```text
Sync: +DMR MS/DM MODE/MONO | Color Code=07 | VLC
 SLOT 1 TGT=9990 SRC=3025209 Private Call
 SLOT 1 FLCO FEC ERR
Sync: no sync
```

stderr contiene secuencias de color ANSI y mensajes de inicialización. `Color Code=XX` significa desconocido. La línea con IDs puede aparecer en un bloque distinto de la cabecera, y los mensajes de error no deben convertirse en identificadores nuevos.

El [código fijado dmr_flco.c](https://github.com/arancormonk/dsd-neo/blob/v2.10.0/src/protocol/dmr/dmr_flco.c), SHA-256 `90401a97e4e3e0b1826d5a6ca182669cae2c130496d35eaab56e487f8fa05b4b`, impide imprimir la cabecera normal cuando hay errores FEC irrecuperables o el LC está protegido. **Imprimir TGT/SRC no demuestra por sí solo un CRC correcto**: la condición `CRCCorrect == 1` para publicar el evento es más estricta que la condición de impresión. El panel debe indicar procedencia de consola y antigüedad; no presentar estas líneas como BER, SNR, autenticación o comprobación independiente del CRC. «Private Call» es clase de destinatario y no indica cifrado.

`-J` escribe un registro textual, no JSON. En este corpus MS/DM incluye destino, origen, código de color y clase privada, pero no etiqueta de slot en la línea final. No debe confundirse su hora de decodificación con la fecha de captura del archivo.

## Contraste con el adaptador de RadioWorkbench

El adaptador `DMRLogParser` se compiló y recibió **dos logs reales** de esta grabación: con la consola normal y con `-Z`, como lo invoca la app. Cada log se dividió en fragmentos de 1, 7, 137 y 8 192 bytes. Los ocho casos conservaron TS1, origen 3025209, destino 9990, CC 7 y clase individual; TS2 quedó sin identidad y las líneas de error se contaron sin reemplazar los IDs. Se comprobaron cabeceras con hora `HH:mm:ss` y secuencias ANSI.

Resultados: [consola normal](dmr-0.12-console-parser.json) y [consola con payload](dmr-0.12-console-parser-payload.json). El [probe Swift](../../script/validation/dmr_console_probe.swift) se compila junto al archivo del adaptador. La copia de `DigitalVoice.swift` verificada tenía SHA-256 `21d18093bb4cf427078254f7677ed9c7a0bccb4935a94a2fa3c884678b8a0bb7`. Esta prueba comprueba la correspondencia entre el log y el estado de la app; no convierte la consola en un verificador de CRC.

## Corpus y límites

Aunque el nombre histórico contiene `baseband`, el WAV descargado contiene **I/Q estéreo de 50 kHz**, no audio discriminador mono listo para stdin. La prueba realiza diferencia de fase compleja, filtro FIR de 129 coeficientes a 6 kHz, conversión a 48 kHz y escala explícita a PCM16. El script conserva la descripción y los hashes de esa conversión.

No se encontró una licencia que autorizara redistribuir la grabación. El original y sus derivados permanecen temporales; no se incorporan a Git ni al paquete. La búsqueda de muestras públicas se limitó a las fuentes de SDRTrunk, DSD-FME, DSD-neo, DSDcc y referencias de ejemplos de otros proyectos. **No se obtuvo un corpus de dos conversaciones simultáneas con TS1/TS2 y destinos conocidos**. Quedan pendientes ese contraste, la calidad perceptual de voz y la recepción física con Brown o SDR++.
