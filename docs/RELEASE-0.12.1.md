# RadioWorkbench 0.12.1

Compilación 28 para macOS 14+ y Apple Silicon. Corrige el refresco lento del
espectro y waterfall durante la recepción en vivo. Conserva las funciones DMR
de [0.12.0](RELEASE-0.12.0.md); DSD-neo requiere macOS 26.

El dibujo tenía el mismo temporizador que los mensajes: en DMR, un máximo de
cinco actualizaciones por segundo, y los sondeos sin audio podían consumir ese
intervalo. Ahora el análisis visual tiene un reloj propio, limitado a 25 Hz, y
una ventana de 2048 muestras que conserva también los paquetes pequeños. La
entrega visual no espera al hilo de interfaz: mantiene un único cuadro pendiente
y descarta cuadros visuales antiguos cuando la ventana tarda en dibujar. Esto
no descarta audio del decodificador.

Las vistas de espectro y nivel observan su propio estado; sus actualizaciones
no invalidan por sí mismas los controles ni el texto completo. El waterfall
colorea solo la fila nueva y desplaza los píxeles anteriores. Conserva colores
y orden, con altura fija de 80 filas desde la primera recepción. La escala
vertical ya no se estira durante el llenado. Las 80 filas representan menos
tiempo al aumentar la cadencia; no constituyen un eje de tiempo calibrado.

Medición Release en el mismo Mac, con audio sintético a 48 kHz y bloques de
2048 muestras, a velocidad real, a través del worker DMR y DSD-neo oficial:

| Medida | 0.12.0 | 0.12.1 |
|---|---:|---:|
| Cuadros entregados en 3,072 s de audio | 10 | 59 |
| Actualizaciones por segundo de audio | 3,26 | 19,21 |
| Intervalo mediano entre cuadros | 213 ms | 47 ms |
| Mayor intervalo observado | 836 ms | 131 ms |
| Muestras de audio perdidas | 0 | 0 |

La construcción del raster 256×80 pasó de 104 a 4,7 microsegundos de media en
3000 iteraciones. Su coste anterior ya era pequeño; el defecto principal
reproducido fue la cadencia. Son mediciones de entrega y construcción de imagen,
no FPS presentados por la pantalla ni latencia RF/voz. No se obtuvo un perfil
CPU de la recepción física del usuario: la inspección automatizada veía una
ventana CW inactiva.

Validación: **218 funciones registradas, 216 aprobadas y dos opcionales de red
omitidas; cero fallos**. Incluye conservación del historial, imágenes inmutables,
paquetes pequeños, pausa/reinicio visual, entrega del cuadro más reciente,
cancelación, DMR independiente, PCM y los demás decodificadores. No se activaron
micrófono, altavoces ni sintonía física.

[Mediciones](validation/visualization-0.12.1.json) ·
[Raster](validation/waterfall-0.12.1.json) ·
[Suite](validation/release-0.12.1-tests.txt) ·
[Resumen](validation/tests-0.12.1-summary.json).

Para repetir la medición: habilitar `RWB_VISUALIZATION_BENCHMARK=1` y establecer
`DSD_NEO_PATH` al runtime oficial instalado antes de ejecutar
`script/test.sh -c release --filter liveVisualizationBenchmark`. Para medir el
raster, compilar con `swiftc -O` los archivos
`Sources/RadioWorkbench/Services/WaterfallRaster.swift` y
`script/validation/waterfall_benchmark.swift`, y ejecutar el resultado.

La prueba con la entrada real del usuario queda pendiente. La mejora visual
se aplica a dispositivo y TCP local, tanto a DMR como a los demás modos de audio;
no cambia sus algoritmos de decodificación. El paquete mantiene firma local
ad hoc, sin notarización.
