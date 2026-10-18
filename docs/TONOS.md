# CTCSS y Selcall · 0.8.10

La app ofrece dos modos separados: **CTCSS / tonos**, con el motor Swift descrito debajo, y **Cinco tonos / Selcall**, mediante multimon-ng incluido. Selcall permite elegir ZVEI1, ZVEI2, ZVEI3, PZVEI, DZVEI, EEA, EIA o CCIR. El monitor conserva la secuencia hexadecimal original, incluidos los símbolos especiales E/F, sin asignarles nombres de personas o dispositivos. Exporta JSON y procesa audio FM/WAV fuera del callback de captura.

Se probaron las ocho familias con señales sintéticas independientes y códigos distintivos `1ABCD`, además de una secuencia ZVEI1 `12345` y un código especial. La temporización del detector es la de multimon-ng; las secuencias observadas no se fuerzan siempre a cinco dígitos. DCS y DUALTONE siguen pendientes. [Entrada, integración y límites](DECODIFICADORES-0.8.10.md).

## CTCSS en «CTCSS / tonos»

Recepción nativa de CTCSS sobre audio PCM de FM. El motor recorre
automáticamente 51 frecuencias entre 67,0 y 254,1 Hz, incluida la extensión
150,0 Hz. La tabla se verificó con el código fuente de SDRangel:
[CTCSSFrequencies](https://github.com/f4exb/sdrangel/blob/master/sdrbase/dsp/ctcssfrequencies.cpp),
blob `c921c835b357694b79035ac0d4183d102f5dedf6`.
Es una tabla de frecuencias, no una garantía de que todos los equipos ofrezcan
las 51 selecciones.

El README actual de multimon-ng enumera DTMF, EIA, CCIR y familias ZVEI, pero
no enumera CTCSS. Por eso se usó SDRangel como referencia de las frecuencias.
[Modos de multimon-ng](https://github.com/EliasOenal/multimon-ng/blob/master/README.md).
La implementación DSP y su máquina de estados son propias en Swift; no
incluyen código de estos proyectos.

## Entrada desde SDR++

| Parámetro | Selección inicial |
|---|---|
| RF | NFM |
| Ancho RF | 12–15 kHz según canal y desviación |
| Banda de audio que debe conservarse | 50–300 Hz, además de la voz si se quiere escucharla |
| Muestreo | PCM 8 kHz o superior; 44,1/48 kHz habitual |
| Canal | Entrada y L/R disponibles en el selector existente |
| Umbral | Amplitud mínima del tono, inicialmente 0,02 para subaudio débil |
| Frecuencia/baudios | Búsqueda automática en la tabla; CTCSS es un tono continuo |

No usar un filtro pasaaltos de voz a 300 Hz: elimina la información que este
motor necesita. Evitar reducción de ruido de voz, supresión de CTCSS en el
receptor y squelch que corte el tono. La salida de altavoz de ciertos equipos
ya ha eliminado el subaudio; en ese caso usar una salida que lo conserve.
Estos valores son el preset inicial de RadioWorkbench; verificar el espectro
real de la fuente antes de atribuir un resultado negativo al transmisor.

## Detección y tiempos

El worker aplica un pasaaltos suave de 25 Hz para retirar DC y un pasa-bajos
Butterworth de octavo orden a 300 Hz antes de reducir el muestreo a 1024 Hz.
La decimación fraccional mantiene el reloj original para tasas de 44,1/48 kHz.
Los buffers y coeficientes se reservan al crear el motor.

Cada 250 ms analiza una ventana Hann de 2 s con Goertzel en las frecuencias
exactas. Esto distingue vecinos como 150,0 y 151,4 Hz. El candidato debe
explicar al menos el 62 % de la energía de la ventana y superar claramente
al segundo candidato. Además debe superar el umbral de amplitud. La confianza
es una medida de coherencia y separación espectral, no una probabilidad
estadística calibrada.

Tres ventanas sucesivas confirman la entrada; dos ventanas sin confirmación
retiran el tono. Para una señal estable presente desde el inicio, la primera
confirmación llega aproximadamente a 2,5 s. Cambios bruscos y silencios tardan
en atravesar la ventana: no son tiempos instantáneos de apertura de squelch.

El texto registra inicio y fin **confirmados**. La duración se cuenta desde
la confirmación, no desde el comienzo físico estimado de la transmisión.
El estado muestra frecuencia, confianza y duración confirmada, y la memoria
del texto se recorta entre 32 y 64 KiB. No se abre ni cierra audio automáticamente.

## Pruebas y límites

Las pruebas sintetizan audio sin leer la tabla ni el algoritmo del detector.
Comprueban los 51 tonos a 8 kHz, mezcla con voz modelada y ruido a 44,1/48 kHz,
selección de un umbral débil, separación de vecinos y cambios con/sin silencio.
También rechazan silencio, ruido, contenido de voz modelada, tonos no catalogados,
un tono a mitad de camino entre vecinos, candidatos iguales simultáneos,
un pulso de 350 ms y un tono de voz que podría aliasarse a subaudio.
La prueba de integración recorre `DecoderEngine` y el WAV de ejemplo de 100 Hz
incluido en la aplicación, con silencio final para comprobar el cierre del evento.
Verificación local del 13 de octubre de 2026: 68 casos en 7 funciones,
todos aprobados en 1,487 s; registro `/tmp/radioworkbench-selective-tests.log`.

Son señales matemáticas independientes, no grabaciones de todos los fabricantes.
Aún faltan pruebas con RF, captura real de SDR++ y tolerancias de frecuencia
de equipos concretos. La ventana busca tonos cercanos a sus valores nominales;
puede rechazar señales con frecuencia demasiado desviada. Un componente de voz
que imite de forma estable una sinusoidal CTCSS no se puede distinguir por
este audio solo; la persistencia y pureza reducen falsos positivos, sin autenticar
el origen de la señal.

Este motor Swift implementa CTCSS. CCIR, EIA y las familias ZVEI están disponibles en el modo Selcall separado; DCS y tonos dobles aún requieren integración y validación.

Para repetir: `RADIO_BUILD_PATH=/tmp/radioworkbench-packet-tests script/test.sh --filter selective`.
