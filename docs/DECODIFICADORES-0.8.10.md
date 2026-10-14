# POCSAG, Selcall, Hell y RTTY ASCII · 0.8.10

Esta ampliación prioriza audio/WAV y aprovecha la selección de entrada y canales existente. No requiere conectar un SDR USB directamente a RadioWorkbench. **Ejemplo** carga señales matemáticas incluidas; la recepción RF y el cable virtual deben comprobarse con una fuente real aparte.

## Modos incorporados

| Modo | Opciones | Resultado |
|---|---|---|
| POCSAG | 512, 1200 y 2400 baud, individual o automático; corrección BCH 0–2 bits; mensajes vacíos opcionales | Capcode, función, tipo y contenido; últimas 200 filas y JSON |
| Cinco tonos / Selcall | ZVEI1, ZVEI2, ZVEI3, PZVEI, DZVEI, EEA, EIA y CCIR | Secuencia original hexadecimal y familia; JSON |
| Hellschreiber por pulsos | Feld, Slow 14 baud, Slow fldigi /8, Feld X5 y Feld X9 | Raster de doble traza, inversión, umbral, inicio y reloj ppm; PNG |
| RTTY | ITA2 existente más ASCII de 7/8 bits sin paridad | Texto ASCII imprimible, salto de línea y tabulación |

POCSAG no cubre FLEX. Selcall no añade DCS ni DUALTONE y no identifica al titular de un código. RTTY ASCII 8 no implementa Latin-1 ni alfabetos nacionales; CHU requiere su propio framing. Hell recibe amplitud por pulsos, sin OCR: FSK Hell y Hell 80 siguen pendientes. MT63, ALE, DRM e integraciones IQ permanecen en investigación.

## Entrada desde SDR++

| Modo | Demodulación RF | Filtro RF inicial | Audio necesario |
|---|---|---|---|
| POCSAG | FM/NFM con salida de discriminador | 12,5–25 kHz, según canal y desviación | Baseband continuo, sin de-emphasis, pasa-altos de voz, reducción de ruido ni squelch; no son tonos AFSK |
| Selcall | FM/NFM | 12,5–25 kHz, según servicio | Conservar aproximadamente 300–3500 Hz y el inicio completo de la secuencia |
| RTTY ASCII | USB/LSB según señal y polaridad | 2,4 kHz como inicio | Dos tonos con centro/shift y baud correspondientes a la emisión |
| Hell en HF | USB | 2,4 kHz para Feld/Slow; ampliar para X5/X9 | Centro ajustable y banda completa de la variante |

Estos anchos son ajustes iniciales de la app, no una asignación normativa ni una garantía para todos los transmisores. Selecciona en RadioWorkbench la entrada virtual y el canal que contiene la señal. Se recomienda transportar PCM a 44,1/48 kHz, sin efectos de voz. El worker remuestrea POCSAG/Selcall a 22.050 Hz mono signed16 mediante un FIR polifásico continuo; no exige cambiar el muestreo global del Mac.

La salida de altavoz de un receptor puede eliminar componentes necesarios para POCSAG. Aunque el cable entregue sonido, verifica que el módulo SDR utilizado permita conservar el discriminador. El programa no transmite ni controla SDR++ automáticamente.

## Variantes Hell

| Variante | Columnas/s | Píxeles/s | Banda de audio inicial |
|---|---:|---:|---:|
| Feld Hell | 17,5 | 245 | 350 Hz |
| Slow Hell · 14 baud | 2 | 28 | 40 Hz |
| Slow Hell · fldigi /8 | 2,1875 | 30,625 | 44 Hz |
| Feld Hell X5 | 87,5 | 1225 | 1750 Hz |
| Feld Hell X9 | 157,5 | 2205 | 3150 Hz |

El raster usa 14 posiciones verticales por columna y dos trazas sucesivas para leer una señal que no tiene sincronismo de caracteres. El receptor combina demodulación I/Q de amplitud, filtro de cuatro polos, integración de píxel y seguimiento de nivel. Retiene ocho franjas de 160 columnas, con dimensiones acotadas; no crece indefinidamente con una escucha larga.

Se muestran dos variantes Slow porque la [documentación Hell de fldigi](https://github.com/w1hkj/fldigi/blob/master/fldigi_doxygen/user_src_docs/hell.txt) describe 14 baud, mientras que el [código del modo Slow](https://github.com/w1hkj/fldigi/blob/master/src/feld/feld.cxx) reduce la tasa Feld por ocho. Seleccionar la tasa que use el transmisor evita una inclinación o escala errónea. Las bandas son aproximaciones iniciales; el conformado de pulsos y el filtro del emisor pueden cambiarlas.

## Motor externo y distribución

POCSAG y Selcall utilizan [multimon-ng](https://github.com/EliasOenal/multimon-ng), versión 1.6.2, fijado a `3d8e925782b389ec16e3d48dd8b6d94fbb132197`. `Vendor/MultimonNG/source-manifest.json` registra origen y SHA-256 por archivo. La app incluye el ejecutable arm64, COPYING y un archivo de sus fuentes más el script de compilación.

La compilación selecciona `DUMMY_AUDIO` y `ONLY_RAW`: recibe PCM por stdin, sin backend de captura propio, sin dispositivos SDR, SDL/X11 o proceso sox. La selección de entrada sigue a cargo de RadioWorkbench. Los decodificadores habilitados por sesión son únicamente los elegidos; salida y diagnósticos están acotados. Cancelar termina el proceso hijo de esa sesión. El componente conserva su GPL v2 o posterior; ejecutar un proceso separado no elimina sus condiciones.

Hell y los cambios RTTY se implementan en Swift. No se copió el motor DSP ni las fuentes tipográficas de fldigi. Los caracteres de prueba C/Q son patrones propios incluidos en el generador.

## Validación

`script/generate_additional_fixtures.py` crea **19 WAV sintéticos**: tres tasas POCSAG, nueve secuencias Selcall, dos transmisiones RTTY ASCII y cinco imágenes Hell. El manifiesto documenta parámetros y hashes. No son grabaciones privadas ni tráfico de pagers reales.

Las pruebas comprueban POCSAG en ambas polaridades, BCH con dos bits dañados y rechazo sin corrección; ocho familias Selcall con código distintivo; ASCII 7/8 exacto; cinco rasters Hell comparados con los patrones del transmisor; rechazo de identificadores JSON inválidos; límites de memoria; compatibilidad con perfiles antiguos; cancelación y la integración WAV→worker→helper. Las imágenes Hell generadas por el motor nativo se inspeccionaron visualmente.

La suite Release de 0.8.10 registró 128 funciones: 126 ejecutadas y aprobadas; las dos consultas de red opcionales se omiten en la suite ordinaria. La descarga real de satélites pasó por separado. No se hizo una prueba SDR++ → VB-Cable ni recepción RF de estos nuevos modos en esta versión.
