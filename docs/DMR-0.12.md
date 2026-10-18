# Recepción DMR · RadioWorkbench 0.12

La ampliación añade escucha de voz durante la recepción, selección de síntesis
TS1/TS2 y un panel con los datos que entrega DSD-neo 2.10.0. Conserva la voz WAV
para escuchar o exportar al terminar. La app principal declara macOS 14+;
el runtime oficial opcional de DSD-neo requiere macOS 26 y Apple Silicon.

## Entrada y uso

1. En **Voz digital / DSD**, elige **DMR**. Descarga el motor oficial si falta;
   la descarga se verifica mediante SHA-256.
2. Alimenta el discriminador del canal NFM de 12,5 kHz, sin squelch,
   de-emphasis ni filtros de voz. La integración lo convierte a PCM16 mono de
   48 kHz. La voz ya decodificada de Brown no conserva las tramas DMR.
3. Elige **Ambos**, **TS1** o **TS2** antes de iniciar. Estos controles envían
   la máscara de síntesis `-V 3/1/2`; no cambian la frecuencia ni utilizan `-z`
   como sustituto del filtro de audio. El panel puede mostrar señalización de
   un intervalo cuya voz se ha silenciado.
4. Activa **Escuchar voz DMR durante la recepción** para oír la salida del
   motor por los altavoces o auriculares del sistema. La opción comienza
   desactivada. Los archivos con escucha activada se procesan a velocidad de
   reproducción; con la opción desactivada se decodifican sin esa espera.
5. **Detener** cierra la entrada del proceso y la reproducción. El WAV se
   habilita al finalizar su cierre; puede reproducirse y exportarse.

TS1 y TS2 son intervalos de tiempo del mismo canal. No se asignan etiquetas de
intervalo a los altavoces izquierdo y derecho: en la grabación MS/DM comprobada,
la voz TS1 llega duplicada a ambos canales. No se verificaron dos conversaciones
simultáneas con identidades conocidas. Los controles no habilitan transmisión,
trunking, claves ni sintonía automática.

## Voz y límites de memoria

La ruta DMR usa `-fs` y, cuando se solicita escucha, `-o -`: PCM16LE estéreo,
intercalado, a 8 kHz. stdout binario y stderr textual se leen por separado.
La conversión conserva los bytes incompletos entre lecturas y entrega bloques
de hasta 2.048 tramas. El grafo de salida admite como máximo 16.000 tramas
pendientes, incluidos los trabajos aún no programados: dos segundos por canal.
Si se alcanza ese límite, descarta bloques de reproducción y muestra el
recuento; esto no equivale a pérdida de paquetes RF. El WAV lo escribe el motor
por separado. Se conserva el límite de 30 minutos por sesión.

Al terminar normalmente se reproduce el audio pendiente antes de cerrar la
salida. Detener o cambiar de modo la corta inmediatamente. Se mantiene la
comprobación de generación del receptor para ignorar resultados de una sesión
cancelada. No se inicia el micrófono por abrir el panel o activar el control.

## Panel y procedencia

Cada intervalo puede mostrar código de color, emisor, destino, clase individual
o grupo, actividad y antigüedad del último identificador. **Guardar estado DMR
JSON** conserva los datos, la procedencia del adaptador y las horas locales de
procesamiento. No son horas de captura RF de un archivo.

El adaptador reconoce formas concretas de la consola fijada, con ANSI,
cabeceras con hora y lecturas fragmentadas. `Color Code=XX` queda desconocido.
Una línea con errores no reemplaza los identificadores anteriores; estos
conservan su propia antigüedad aunque llegue otra ráfaga. La pérdida de
sincronía elimina el contexto usado para atribuir nuevos datos.

Los identificadores impresos por DSD-neo no acreditan una verificación
independiente de CRC ni la identidad real del emisor. El panel tampoco inventa
BER, SNR, cifrado o inteligibilidad. **Private Call** describe el destinatario,
no una conclusión sobre cifrado. El contador de audio también puede incluir
silencio, por ejemplo al escuchar TS2 cuando solo hay una llamada TS1.

## Contraste independiente

Se comprobó el binario oficial con una grabación de SDRTrunk #1803 y un oráculo
público: TS1, origen 3025209, destino 9990 y llamada privada. El CC7 fue observado
en el motor y no formaba parte del oráculo. `-V 1` y `-V 3` recuperan el mismo
audio; `-V 2` lo silencia y conserva la señalización. stdout coincide con el
PCM del WAV y publica antes de cerrar stdin. Cerrar stdin antes de terminar el
proceso evita el bloqueo observado al enviar solo SIGTERM.

Las pruebas incluyen fragmentación, extremos PCM, perfiles antiguos, errores
de consola, separación TS1/TS2, publicación antes de EOF, el grafo de audio
real en renderizado offline y el recorrido del worker con fin de entrada.
La señal externa se conserva temporalmente: no se redistribuye sin licencia.

[Mediciones y fuentes](validation/dmr-0.12-contract.md) ·
[Investigación previa de Brown](DMR-BROWN-0.10.md).

Faltan una grabación independiente identificada con dos conversaciones
simultáneas, evaluación perceptual de voz y recepción física desde Brown/SDR++.
La prueba SDR++ → VB-Cable permanece aplazada.
