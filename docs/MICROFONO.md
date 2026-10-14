# Micrófono y SSTV · 0.7.3

## Evidencia del cierre

Los reportes del 13 de octubre de 2026 corresponden a 0.6.0/build 7 y 0.7.0/build 8. El segundo fue facilitado por el usuario: cierre a las 12:11:04 hora de Santiago, macOS 27.2, arm64 nativo. Ambos señalan EXC_BAD_ACCESS/SIGSEGV, dirección 0x1e, en el hilo principal. El recorrido incluye `MainActor.assumeIsolated`, `NSViewResponder.platformCurrentEvent`, `TooltipBridge.DynamicTooltipManager.dynamicToolTipRect` y eventos de entrada del ratón en AppKit. El hilo que falla no apunta al callback de audio. Esto identifica el recorrido del fallo, sin demostrar su causa interna ni establecer que retirar `.help` elimine cualquier otro fallo de SwiftUI.

Se retiraron las dos ayudas personalizadas `.help`: actualizar dispositivos y explicación BT.601. La primera tiene texto visible y la segunda una nota permanente. Los reportes completos no se copiaron al proyecto; esta nota omite identificadores personales del diagnóstico.

## Captura

La selección aplica `kAudioOutputUnitProperty_CurrentDevice` únicamente a la unidad de esta app. El dispositivo predeterminado y las tasas globales de macOS no se modifican. El micrófono integrado se identifica por transporte CoreAudio BuiltIn, sin depender de su nombre o idioma.

La prueba inicial, una vez concedido el permiso, mostró un bus de salida de 48 kHz al pasar al micrófono anunciado por HAL a 96 kHz. La comprobación de formato detuvo la captura con un error visible y mantuvo abierta la app. Ahora el tap utiliza `inputFormat(forBus: 0)` del dispositivo seleccionado, que configura también el formato de salida del nodo. Se permiten hasta tres intentos durante el arranque para estabilizar posibles cambios de CoreAudio; cada intento tiene su propio ring, y el decoder solo recibe muestras cuando la tasa/canales coinciden y el tap ha entregado PCM. [AVAudioInputNode de Apple](https://developer.apple.com/documentation/avfaudio/avaudioinputnode) describe el formato hardware y las restricciones de conversión del nodo de entrada.

Durante esta investigación también se observó una entrada temporal `CADefaultDeviceAggregate` a 48 kHz que sí entregaba audio. Se ocultan esas entradas internas de la lista para que el usuario seleccione su dispositivo físico o virtual. La tasa efectiva entregada al decoder se muestra junto al nivel; puede diferir de la tasa nominal anunciada en la lista si CoreAudio reorganiza la ruta. Un aviso de configuración redundante con motor activo y formato idéntico no detiene una sesión válida.

En macOS 27 se usa `installAudioTap`, con errores Swift y un callback Sendable. En macOS 14–26 se usa el tap anterior con una fábrica no aislada del MainActor. El ring C SPSC conserva memoria fija, un productor y un consumidor; el callback solo valida los planos Float32 y copia/mezcla audio. No escribe archivos, registra logs ni ejecuta el decoder. El trabajador procesa y envía estadísticas a la interfaz como máximo diez veces por segundo. La nueva sesión limpia el raster, espectro y estadísticas anteriores.

## Prueba del celular

1. En **SSTV**, pulsa **Preparar micrófono del Mac**. Confirma la entrada integrada, **Auto VIS**, mezcla y umbral **0,1 %**.
2. Pulsa **Escuchar** y permite el micrófono si macOS lo solicita. Espera a ver nivel dBFS y un contador de muestras que aumenta.
3. Selecciona **Robot 36** en el celular. Emite desde el principio, incluyendo cabecera VIS, con el altavoz cerca del Mac y volumen moderado. La transmisión dura unos 36 segundos más la cabecera. Auto VIS también admite otros formatos implementados.
4. Si aparece saturación, reduce el volumen. Si no se reconoce VIS, detén, revisa nivel/umbral y vuelve a enviar la cabecera completa. Un nivel RMS útil inicial es aproximadamente −30 a −12 dBFS; es una orientación de ajuste, no un criterio de éxito del decoder.
5. Espera la imagen completa y usa **Guardar PNG…**. Robot y PD permiten BT.601 limitado o rango completo según el transmisor. No cambies ese parámetro a mitad de una captura.

AM/NFM/USB/LSB son ajustes de demodulación RF en SDR++; una señal reproducida por el celular ya llega como audio al micrófono.

## Verificación local

Pruebas de buffers (archivo local no publicado): mono, estéreo, mezcla y canales separados a 8/48/96 kHz, tap moderno y legado, rechazo de canal ausente/layout interleaved y overflow explícito. Una señal Robot 36 resampleada a 96 kHz y reducida a un nivel de unas centésimas de amplitud reconstruyó 320×240 y sus barras blanco/negro. Es una transmisión matemática de prueba; no verifica por sí sola el trayecto acústico ni una transmisión RF.

Suite 0.7.1 (archivo local no publicado): 68 funciones, incluidas pruebas parametrizadas, aprobadas en 2,355 s. Build (archivo local no publicado).

Después de conceder el permiso de la compilación final, **Escuchar** mantuvo el Micrófono de MacBook Pro a **96 kHz/mono**, con **6.835.200 muestras y cero pérdidas**, más de 71 segundos de audio, sin error ni cierre observado. SSTV estaba en Auto VIS/umbral 1 %, buscando cabecera. Los niveles indicados en ese momento eran ruido ambiental; todavía no constituyen una imagen acústica recibida del celular. [Observaciones de la interfaz](validation/microphone-ui-observation.json).

`script/build_and_run.sh --microphone-test` abre el mismo bundle y ejecuta una prueba acotada del micrófono, usando el mismo ReceiverStore, tap, ring y decoder de **Escuchar**. Guarda estadísticas y estados en `docs/validation/microphone-live.json`; si se completa una imagen, guarda además el PNG. `RADIO_PROBE_SECONDS` elige 5–300 s (15 s por defecto), y `RADIO_DIAGNOSTICS_PATH` indica el archivo local. Opcionalmente, **RADIO_DIAGNOSTIC_WAV_PATH** habilita un WAV Float32 mono de hasta 90 segundos por sesión en la ruta indicada. La escritura ocurre en el trabajador de audio, fuera del tap. La prueba del celular utiliza `/tmp/radioworkbench-sstv-celular/robot36c.wav`; la captura normal sin esa opción conserva el comportamiento anterior. El permiso se gestiona normalmente con macOS: no se editan bases TCC ni se evita el aviso. Una compilación ad hoc distinta puede requerir concederlo de nuevo.

## Recepción débil y calibración en 0.7.3

Los envíos indicados por el usuario como **Robot36C** llegaron al micrófono integrado a 96 kHz/mono, sin pérdidas en el ring. El WAV local final contiene 84,8 s y 8.140.800 muestras, incluyendo dos cabeceras. La señal útil era débil y el ruido ambiental dominaba parte del audio. La captura pertenece al usuario y permanece fuera del repositorio.

La medición de la primera cabecera entrega código VIS 8. Su tono de paridad registrado corresponde a 0, aunque el código exige 1 para paridad par. Es una observación de este audio: no establece un defecto universal de una app del celular. La validación sigue estricta por defecto. **Robot 36C: admitir paridad VIS no estándar** solo permite esa excepción cuando está seleccionado Robot 36 y el código es 8; conserva el aviso en la imagen. Auto VIS general, otros códigos y un tono de stop inválido no reciben la excepción.

Se sustituyó el promediado de frecuencia de 0.7.2 por cinco detectores Goertzel coherentes, con ventana de 8 ms y salto de 2 ms, para separar 1100/1200/1300/1900/2100 Hz del ruido. La banda SSTV utiliza pasa-altos y pasa-bajos Butterworth de cuarto orden, 900–3200 Hz, adaptados al centro de audio. Los coeficientes siguen el [Audio EQ Cookbook de W3C](https://www.w3.org/TR/audio-eq-cookbook/). El decoder sigue ejecutándose fuera del tap.

Las muestras de vídeo se promedian antes de limitar el nivel a 0–255: limitar cada muestra ruidosa elevaba los negros y bajaba los blancos. El final puede reconocerse aunque llegue silencio después del último tono. Regresión anterior (archivo local no publicado) y corrección inicial 0.7.2 (archivo local no publicado) conservan el historial. Detección coherente (archivo local no publicado) verifica señal débil/ruidosa a 96 kHz y los formatos anteriores.

La correlación de los pulsos de línea del audio real da aproximadamente **152,76 ms**, frente a 150 ms nominales de Robot 36. La calibración experimental de esa grabación es **−18.068 ppm** y centro aproximado **1865 Hz**. El reloj se aplica tanto a la cabecera como al raster y admite ±50.000 ppm. La reconstrucción offline detecta VIS 8, termina 320×240 y reduce las franjas diagonales; aún contiene mucho ruido. Esta calibración no se aplica como valor predeterminado para otros transmisores y no identifica por sí sola el origen de la diferencia de reloj.

Las regresiones incluyen rechazo estricto de paridad, excepción acotada Robot 36, rechazo de otros códigos/stop inválido y un WAV independiente presentado con relojes de −18.068/+25.000 ppm. Se contrastan barras al comienzo, centro y final del raster. La calidad de recepción real se documenta separadamente; completar 320×240 no basta para afirmar que se recibió bien la fotografía.

Para repetir esta prueba local, el script permite `RADIO_ROBOT36C_COMPATIBILITY=1`, `RADIO_AUDIO_CENTER=1865` y `RADIO_CLOCK_PPM=-18068` junto a `--microphone-test`. Son parámetros optativos de diagnóstico y quedan visibles en la interfaz y en su JSON. El WAV requiere la opción explícita `RADIO_DIAGNOSTIC_WAV_PATH`; nunca se envía a terceros.

## Resultado acústico confirmado

El usuario desbloqueó el Mac y concedió el permiso. `--repeat-microphone-test` reanudó el mismo bundle 0.7.3 sin recompilar ni firmar. La interfaz mostró el micrófono integrado a 96 kHz/mono, Robot 36, Auto VIS y la calibración anterior. La imagen creció progresivamente y terminó **320×240**; se guardó automáticamente el PNG. El usuario confirmó «funciono».

La sesión recibió **5.040.000 muestras en 52,5 s, cero pérdidas y ningún error**, sin cierre observado. El WAV quedó local, fuera del repositorio. La fotografía recibida es reconocible, con ruido y líneas de interferencia; completar el raster no certifica fidelidad de color ni calidad RF. [Resultado](validation/microphone-real-reception-0.7.3.json), [estados de captura](validation/microphone-live-0.7.3-retry.json).

Para volver a usar ese emisor, selecciona Robot 36 y la opción de paridad explícita, centro 1865 Hz y reloj −18.068 ppm. Estos valores corresponden a la señal probada. **Preparar micrófono del Mac** restaura el preset general: Auto VIS, centro 1900 Hz y reloj cero. La repetición de diagnóstico admite los parámetros por variables de entorno como se describe arriba y preserva el permiso del bundle existente.

## Mejoras 0.8.0

**Sincronización automática:** el centro se estima sobre el líder VIS; el período y fase del raster se siguen con pulsos coherentes de línea. La estimación actualiza al reunir 8, 16, 32 y luego 64 pulsos nuevos. Antes de que haya una estimación fiable, se usa el reloj manual. La vista presenta ppm, centro, número de líneas y residuo. Esto corrige deriva progresiva; no repara una cabecera cortada ni un canal de audio saturado.

**Reducción de ruido:** `Equilibrada` elimina impulsos aislados cuando los cuatro vecinos se parecen y conserva bordes; `Intensa` aplica la mediana también en zonas de alto contraste y puede suavizar líneas finas. `Sin reducción` conserva el raster directo. Se aplica una vez al terminar el raster para no retrasar la captura. La recepción Robot36C real se usa además para una regresión fuera de línea del worker completo; el WAV permanece local.

**Perfiles:** la franja superior de Entrada de audio ofrece perfiles Micrófono · Robot36C y SDR++ · VB-Cable cuando ambos dispositivos están presentes. Se guardan con su UID estable, modo, canal, tono, compatibilidad Robot36C, sensibilidad, demodulación y ancho RF. El último perfil elegido se recupera al volver a abrir la app. En la primera ejecución se crean los dos perfiles y se mantiene la selección de entrada anterior; ninguno altera la ruta global de CoreAudio. “Guardar como…” y “Actualizar con estos ajustes” permiten perfiles propios.

## Publicación

Las fotografías reconstruidas del celular y el WAV acústico pertenecen a la prueba local. Se conservan fuera de la publicación pública y de su historial; únicamente se comparten mediciones y fixtures sintéticos.
