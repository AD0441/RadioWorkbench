# RadioWorkbench 0.14.0 · nuevos receptores y correcciones

Esta versión incorpora **SITOR-A, DGPS y FLEX** en los flujos existentes de archivo, entrada de audio seleccionada, audio TCP y biblioteca. Cada uno tiene su guía SDR y una muestra propia en **Ejemplo** y **Taller de señales**; el taller reúne 77 referencias. La aplicación principal sigue siendo nativa arm64 para macOS 14+, con los requisitos separados de CWKit y DSD-neo.

| Modo | Entrada desde SDR++ | Recepción disponible | Límites |
|---|---|---|---|
| SITOR-A | USB, RF inicial 2,4 kHz; audio 1615/1785 Hz, centro 1700 Hz; LSB requiere invertir | 100 baud, bloques CCIR 476 de tres caracteres, cadencia 210/450 ms, letras/cifras y controles de retorno observados | Monitor pasivo; no transmite ni actúa como terminal ARQ. 4/7 detecta parte de los errores y no equivale a CRC. Sin retorno conserva bloques iguales y no confirma entrega |
| DGPS | USB, RF inicial 1,5 kHz; MSK centrada en 800 Hz; tasa automática o fija 100/200 bit/s | RTCM 2 con cabecera y paridad encadenada; estación, salud, secuencia, texto, correcciones GPS y coordenadas de referencia cuando llegan | Sin solución de navegación, RTCM 3, catálogo comercial, 25/50 bit/s ni datum confirmado. Conversión ECEF aproximada con WGS84 asumido; tipo 32 puede usar PE-90 |
| FLEX | FM, RF inicial 25 kHz; discriminador plano, sin de-emphasis, squelch ni filtros de voz; PCM interno 22050 Hz | 1600/3200/6400 bit/s, 2/4-FSK, direcciones cortas, ALPHA, números y avisos; capcode, fase, ciclo/trama y fragmento en JSON | Sin ReFLEX, direcciones largas, grupos, mensajes seguros/binarios ni reensamblado de fragmentos. La corrección BCH de hasta dos bits se aplica por palabra |

Los anchos RF son puntos de partida; no representan el ancho ocupado de la señal de audio. Selecciona el dispositivo y canal en **Entrada de audio**. No mezcles canales de fases opuestas. Conserva ráfagas y pausas completas y desactiva el procesado de voz del SDR.

En DGPS, **Guardar RTCM en JSON** conserva las cabeceras y palabras de datos recuperadas; el monitor interpreta los tipos 1/9, 3/32 y 16/36. Los demás tipos siguen disponibles como payload validado. La posición corresponde al transmisor de referencia y no a quien escucha. Los tiempos Z son del protocolo, no fechas UTC de captura; el desplazamiento temporal pertenece al audio recibido.

SITOR-A exige tres ciclos coherentes para adquirir sincronía. Solo elimina una repetición si el control de retorno observado respalda esa decisión. No adquiere SITOR-B por compartir su alfabeto y no muestra controles de 70 ms como letras recibidas.

FLEX detecta velocidad, niveles y fases automáticamente. A 3200 símbolos/s con cuatro niveles transporta 6400 bit/s; la interfaz conserva ambas magnitudes. Los fragmentos C/F se muestran por separado y no se presentan como un mensaje reconstruido.

## Errores y optimizaciones

- El FIR Hilbert de audio utiliza un búfer circular duplicado y producto vectorial Accelerate. Una comparación aislada release sobre diez segundos de audio, mediana de cinco repeticiones, midió 3,62 → 2,27 ms a 8 kHz, 54,06 → 27,44 ms a 48 kHz y 135,82 → 62,97 ms a 96 kHz. Es el coste de este filtro, **no** una medida de aceleración de toda la app ni del waterfall. La prueba numérica contrasta fase, cuadratura y retardo con una implementación escalar independiente.
- Muestras NaN/Inf se sustituyen por cero antes de entrar al FIR, para no contaminar la recepción posterior.
- La exportación WAV de voz copia en segundo plano y publica mediante un renombrado atómico. Conserva el destino anterior si falla la copia y mantiene el archivo temporal de origen mientras se exporta, incluso al cambiar de modo.
- Volver a voz digital conserva el ancho RF del protocolo seleccionado, incluido NXDN48 de 6,25 kHz.
- El umbral muestra décimas y admite 0,1 %, útil para señales débiles; se evita una conversión entera insegura al presentar valores sin validar.
- La salida nativa publica el último bloque decodificado aunque el emisor TCP pause el audio antes de la siguiente actualización. Mantiene un único bloque pendiente y evita FFT durante la espera sin datos.
- POCSAG, FLEX y Selcall dejan de mostrar un centro de audio que sus motores no utilizan. Una sintonía residual a 5900 Hz ya no impide abrir después audio de discriminador a 8 kHz. SITOR-A muestra sus dos tonos separados 170 Hz.
- El lector del helper recupera la lectura después de una línea excesiva y publica la última línea al cerrar sin salto de línea. Los eventos FLEX vacían stdout durante la recepción. Si un helper ignora SIGTERM se fuerza únicamente el cierre de su proceso propio tras un segundo.

## Evidencia y fuentes

SITOR-A y DGPS usan código propio a partir de [ITU-R M.476-5](https://www.itu.int/rec/R-REC-M.476/en), [ITU-R M.823-3](https://www.itu.int/rec/R-REC-M.823/en) y las ecuaciones de paridad de [IS-GPS-200N](https://www.navcen.uscg.gov/sites/default/files/pdf/gps/IS-GPS-200N.pdf). La referencia funcional de MultiMode se conserva en [la revisión existente](REVISION-MULTIMODE.md); no se copió su código ni su catálogo.

DGPS se contrasta además con 131 tramas del vector independiente GPSD, con licencia BSD de dos cláusulas incluida. Las pruebas verifican estación, correcciones y pérdida/readquisición de sincronía. Se modulan también sus bits mediante un transmisor de prueba separado para comprobar el trayecto de audio a 8/44,1/48/96 kHz. Esto es una comprobación de protocolo independiente; el audio modulado sigue siendo sintético.

FLEX utiliza el [multimon-ng ya incluido](https://github.com/EliasOenal/multimon-ng), con parches locales, fuentes GPL y licencia distribuidas en el bundle. Su generador de prueba separado verificó 96 combinaciones de velocidad/niveles, polaridad, tipo de mensaje y errores; doce flujos de ruido no produjeron eventos. Las pruebas de Pipe comprueban publicación antes de EOF y cancelación.

No se ha hecho una nueva prueba física con micrófono, SDR++ o cable virtual. SITOR-A y FLEX aún necesitan capturas RF independientes; DGPS no se ha contrastado con una baliza real. LORAN-C y Globe Wireless siguen pendientes: el primero requiere preservar pulsos RF y el segundo necesita identificar la variante y validar un corpus y motor adecuados. DRM, AIS y otros candidatos permanecen en la [lista de investigación](DECODIFICADORES-EXTRA.md).

Resultados de compilación, suite y paquete: [VALIDACION.md](VALIDACION.md).
