# SSTV: catálogo de protocolos y compatibilidad

Investigación de 12–13 de octubre de 2026; ampliación del catálogo el 13. Se investigó más allá de Martin M1 y Scottie S1. Este documento distingue datos de protocolo comprobados, parámetros de una implementación y nombres históricos pendientes. **Estar en el catálogo no significa que el decodificador esté implementado o probado en RadioWorkbench.**

El inventario de trabajo tiene 103 entradas entre modos base, opciones, perfiles históricos y pistas de búsqueda; no son 103 decodificadores terminados ni una norma universal exhaustiva. Son 38 perfiles con documento original de protocolo, 4 extensiones de familia, 8 perfiles de QSSTV que requieren interoperabilidad, 45 entradas históricas/opciones sin parámetros suficientemente comprobados y 8 pistas de búsqueda. Sus valores desconocidos quedan vacíos en el inventario JSON; no deben alimentar autodetección ni activar motores.

## Fuentes y nivel de evidencia

- **D**: [JL Barber N7CXI, Proposal for SSTV Mode Specifications, Dayton 2000](https://www.classicsstv.com/downloads/daytonpaper.pdf). El autor documenta fuentes de firmware Robot 1200C y datos de autores de Pasokon, PD y FAX480. Es una propuesta técnica, con tiempos de scan redondeados a 0,001 ms y tiempos totales aproximados. No incluye AVT.
- **M**: [JE3HHT Makoto Mori, especificación original de modos MMSSTV](https://github.com/n5ac/mmsstv/blob/master/mode.txt). Define MP, MR/ML, MP-N, MC-N y sus identificadores. Es el documento del creador, conservado en el repositorio de código publicado. Autoriza usar los modos en software/equipos; eso no sustituye la licencia del código.
- **Q**: [Parámetros de QSSTV de ON4QZ](https://github.com/ON4QZ/QSSTV/blob/main/src/sstv/sstvparam.cpp). Evidencia primaria de ese programa, no una especificación universal de cada transmisor histórico. No se incorporó código GPL al motor Swift.
- **H**: [Catálogo histórico de OK2MNM](https://www.sstv-handbook.com/download/sstv_05.pdf) y [descripción de formatos](https://www.sstv-handbook.com/download/sstv_04.pdf), publicación del autor. Sirve para localizar nombres y variantes; algunos números discrepan entre tablas o con fuentes originales y no se adoptan automáticamente como parámetros fiables.

## Modos clásicos con temporización utilizable

En RGB, el tiempo indicado es por componente; en PD es por uno de los cuatro scans del par de líneas. Los tamaños incluyen todas las líneas transmitidas; no se elimina automáticamente una cabecera de imagen de 16 líneas.

| Modo | VIS decimal | Raster de trabajo | Scan ms | Modelo / secuencia | Evidencia |
|---|---:|---|---:|---|---|
| Martin M1 | 44 | 320×256 | 146,432 | RGB / G-B-R | D |
| Martin M2 | 40 | 320×256 | 73,216 | RGB / G-B-R | D |
| Martin M3 | 36 | 320×128 | 146,432 | RGB / G-B-R | H; extensión de M1 |
| Martin M4 | 32 | 320×128 | 73,216 | RGB / G-B-R | H; extensión de M2 |
| Scottie S1 | 60 | 320×256 | 138,240 | RGB / G-B-R | D |
| Scottie S2 | 56 | 320×256 | 88,064 | RGB / G-B-R | D |
| Scottie S3 | 52 | 320×128 | 138,240 | RGB / G-B-R | H; extensión de S1 |
| Scottie S4 | 48 | 320×128 | 88,064 | RGB / G-B-R | H; extensión de S2 |
| Scottie DX | 76 | 320×256 | 345,600 | RGB / G-B-R | D |
| PD50 | 93 | 320×256 | 91,520 | Y0-Cr-Cb-Y1 | D |
| PD90 | 99 | 320×256 | 170,240 | Y0-Cr-Cb-Y1 | D |
| PD120 | 95 | 640×496 | 121,600 | Y0-Cr-Cb-Y1 | D |
| PD160 | 98 | 512×400 | 195,584 | Y0-Cr-Cb-Y1 | D |
| PD180 | 96 | 640×496 | 183,040 | Y0-Cr-Cb-Y1 | D |
| PD240 | 97 | 640×496 | 244,480 | Y0-Cr-Cb-Y1 | D |
| PD290 | 94 | 800×616 | 228,800 | Y0-Cr-Cb-Y1 | D |
| Robot 36 color | 8 | 320×240 | Y 88 / C 44 | Y-Cr, Y-Cb; cromas compartidos | D |
| Robot 72 color | 12 | 320×240 | Y 138 / C 69 | Y-Cr-Cb por línea | D |
| Pasokon P3 | 113 | 640×496 | 133,333 | RGB / R-G-B | D |
| Pasokon P5 | 114 | 640×496 | 200,000 | RGB / R-G-B | D |
| Pasokon P7 | 115 | 640×496 | 266,666 | RGB / R-G-B | D |
| Wraase SC2-180 | 55 | 320×256 | 235,000 | RGB / R-G-B | D |
| FAX480 original | sin VIS | 512×480 + 20 fases | 262,144 | BW | D |

Los tiempos y secuencias publicados permiten construir generadores independientes. Sus duraciones calculadas a partir de cada segmento pueden diferir unos milisegundos de los totales redondeados de otros programas. Para pruebas se utiliza la suma de segmentos, sin forzarla al nombre del modo.

**Martin:** sync 4,862 ms a 1200 Hz, cuatro porches/separadores de 0,572 ms a 1500 Hz. **Scottie:** tres separaciones/porch de 1,5 ms; sync 9 ms entre B y R y un sync inicial adicional de 9 ms solo antes de la primera línea. **PD:** sync 20 ms, porch 2,080 ms y cuatro scans iguales; Cr/Cb se comparten entre dos líneas. **Robot 36/72:** sync 9 ms, porch 3 ms; separadores de color 4,5 ms y porch de 1,5 ms. Robot 36 alterna Cr/Cb; Robot 72 transmite ambos por línea. N7CXI distingue el porch Cr de Robot72 a 1900 Hz y Cb a 1500 Hz.

**Pasokon:** sync P3/P5/P7 5,208 / 7,813 / 10,417 ms y cuatro porches 1,042 / 1,563 / 2,083 ms. **SC2-180:** sync 5,5225 ms, porch 0,5 ms y R-G-B consecutivos, sin separadores entre componentes. No aplicar esa estructura sin cambios a todos los SC2.

**Color Robot/PD:** el apéndice B de D publica ecuaciones BT.601 con Y limitado y chroma centrado en 128; también advierte diferencias de escala entre transmisores. RadioWorkbench ofrece BT.601 y rango completo. Los WAV originales PD50/Robot36 usan las ecuaciones del documento; dos fixtures adicionales comprueban la opción completa. Usar una inversa de rango completo para el transmisor limitado produce negros elevados y blancos apagados.

**FAX480:** alternancia de 2300/1500 Hz de 2,05 ms por mitad repetida 1220 veces, 20 líneas de fase, luego 480 líneas de imagen con sync 5,12 ms. No equivale a WEFAX HF de IOC/LPM configurables. Algunas implementaciones integran las 20 fases como píxeles y entregan 500 líneas; otras agregan un VIS85 posterior. Son perfiles diferentes.

## Las 19 extensiones MMSSTV

Todos los tamaños y tiempos de esta tabla proceden de **M**. Los códigos extendidos se expresan en hexadecimal; no son VIS de 7 bits.

| Grupo | Modos y código | Raster | TW ms |
|---|---|---|---|
| MP | MP73 `2523`, MP115 `2923`, MP140 `2A23`, MP175 `2C23` | 320×256 | 140 / 223 / 270 / 340 |
| MR | MR73 `4523`, MR90 `4623`, MR115 `4923`, MR140 `4A23`, MR175 `4C23` | 320×256 | 138 / 171 / 220 / 269 / 337 |
| ML | ML180 `8523`, ML240 `8623`, ML280 `8923`, ML320 `8A23` | 640×496 | 176,5 / 236,5 / 277,5 / 317,5 |
| MP-N | MP73-N N-VIS `02`, MP110-N `04`, MP140-N `05` | 320×256 | 140 / 212 / 270 |
| MC-N | MC110-N N-VIS `14`, MC140-N `15`, MC180-N `16` | 320×256 | 143 / 180 / 232 |

MP usa sync 9 + porch 1 ms y Y0-Cr-Cb-Y1 de TW por scan, 128 pares. MR/ML usa sync 9 + porch 1, Y de TW y Cr/Cb de TW/2, manteniendo el último píxel 0,1 ms después de cada scan. MP-N conserva pares y MC-N transmite RGB; usan sync a 1900 Hz y video 2044–2300 Hz. MC-N usa sync 8 + porch 0,5 ms.

La cabecera extendida MMSSTV tiene 16 bits LSB primero de 30 ms. N-VIS usa un mensaje distinto de 24 bits, grupos de 6 bits, símbolos 22 ms y tonos 1900/2100 Hz. Un valor N-VIS 02 nunca debe confundirse con Robot BW8 VIS2. MR175 original es `4C23`; la tabla QSSTV consultada contiene un `4A23` duplicado para MR140/MR175.

**RadioWorkbench 0.4 implementa las 19 extensiones de esta tabla.** VIS16 verifica el prefijo 23H y el stop; N-VIS verifica D0=`101101`, D1=`010101`, D2=código y D3=`010101 xor código`, sin tratarlo como VIS clásico. MR/ML preserva el último píxel 0,1 ms después de cada componente. Los narrow transforman 2044–2300 Hz a la escala de píxel. La escala Y/Cr/Cb se elige con el control BT.601/completo; mode.txt no fija una ecuación universal de color.

## Inventario ampliado y límites que hay que resolver

| Familia | Modos u opciones adicionales localizados | Tratamiento propuesto |
|---|---|---|
| Robot color | 12, 24 | Q ofrece Robot24 con160×120 y 24,0015s; verificar transmisor y temporización. Robot12 requiere especificación/fixture independiente. |
| Robot BW | 8, 12, 24, 36 | Q ofrece BW8/BW12 con160×120, VIS2/6 y 8,028/12,001s. VIS1/2/3,5/6/7,9/10/11,13/14/15 son componentes R/G/B; no tres modos iguales. BW24/36 quedan pendientes. |
| Wraase SC2 | 30, 60, 120, 180 | SC2-180 tiene fuenteD; 60/120 figuran enQ. Proporciones RGB y perfiles históricos discrepantes requieren validar cada variante. |
| Wraase SC1 | Color24,48,48Q,96; BW8,16,24,32 | Catalogados; cabeceras, sincronía por componente y rasters aún sin validación de transmisor. |
| Martin HQ | HQ1,HQ2,HQ3,HQ4 | Localizados enH; no sustituyen M1–M4 ni comparten automáticamente el modeloRGB. VIS/temporización incompletos. |
| Scottie | DX2 además deS1–S4/DX | DX2 es perfil distinto; pendiente de fuente original y audio. |
| AVT | 24,90,94,188,125BW | Q documenta primeros 3. AVT125BW es monocromo. Cada base tiene Normal,Narrow,QRM,Narrow+QRM; son 20 perfiles potenciales. Requieren cabecera digital AVT e interlace cuando corresponda. |
| AVT antiguo | 8,16h,16w,32,48h,48w,96,128 | Pistas de catálogo de software; no hay parámetros originales suficientemente comprobados en esta revisión. |
| MSCAN | TV1,TV2 | Localizados; pendientes de especificación/fixture. |
| Proskan | J120 | Localizado; pendiente. |
| Vester | ColorFAX | Localizado; pendiente. |
| Kenwood | FAST-FM | Localizado; paridad y RF/audio deben verificarse con especificación del equipo. |
| Otros BW | SP17BW y perfiles7,2/8/16/32/64s | Históricos, sin motor activado por el catálogo. |

AVT188 y ScottieDX comparten VIS76: la autodetección necesita considerar su cabecera posterior y la selección manual. Q usa320 píxeles horizontales para AVT90 mientras documentación histórica menciona256. Martin M2/M4 y Scottie S2/S4 también suelen presentarse en 320 píxeles aunque la resolución nominal histórica sea160. El número de píxeles renderizados es una convención y no prueba de mayor resolución de RF.

RobotBW24 ilustra por qué no se deben adivinar parámetros: algunas tablas históricas contradicen líneas, sync y lpm. El JSON conserva los datos dudosos como desconocidos. Nada impide incorporarlos posteriormente con evidencia de una implementación transmisora y señales independientes.

## Ajuste SDR++ y entrada de audio

Es decisión de diseño de RadioWorkbench ofrecer perfiles por protocolo, separados del modo RF de SDR++. El demodulador SDR++ produce el audio que recibe la app; SSTV convierte tonos de audio en imagen. Hay que elegir expresamente dispositivo y canal de entrada —por ejemplo el dispositivo virtual utilizado para llevar audio de SDR++—, conservar frecuencia de muestreo y mostrar nivel/clipping.

| Perfil | SDR++ RF recomendado inicialmente | Banda de audio que debe conservarse | Ajuste inicial de filtro RF |
|---|---|---|---|
| SSTV analógica convencional HF | USB; LSB cuando así se transmite | 1100–2300 Hz, incluyendo VIS | SSB≈2,8–3kHz, sin recortar los tonos |
| SSTV analógica VHF/UHF FM | NFM según transmisión | Mismos tonos SSTV después de demodularFM | ≈12–15kHz como punto inicial; ajustar a la señal real |
| MP-N / MC-N | USB/LSB según transmisión | 1900–2300 Hz, incluyendo cabecera | Filtro desplazado que cubra esos tonos; no cerrar solo sobre el video |
| AVT Narrow | USB/LSB oFM según transmisión | Cabecera AVT además de video estrecho | Mantener cabecera completa antes de estrechar manualmente |

Los anchos RF anteriores son **presets iniciales de diseño**, no requisitos universales de todos los emisores. No convertir una imagen SSTV a AM por el hecho de llevar información de brillo en tonos. Guardar audio PCM a 48 kHz mono o canal L/R seleccionado facilita replay; cada motor remuestrea explícitamente a su tasa interna.

## Imágenes digitales: módulos diferentes

[QSSTV](https://github.com/ON4QZ/QSSTV) implementa SSTV analógica y HAMDRM, compatible con MMSSTV y EasyPal según su [manual](https://www.qsl.net/on4qz/qsstv/manual/index.html). HAMDRM/EasyPal necesita un motor de modem digital separado; no es otro VIS/timing del decoder SSTV. DRM de radiodifusión debe tratarse como otra integración.

[SSDV de Philip Heron](https://github.com/fsphil/ssdv) codifica imágenes JPEG en paquetes con corrección Reed-Solomon y requiere primero recuperar esos bytes desde su transporte; no transforma por sí solo un WAV arbitrario en imagen. El repositorio GitHub está archivado desde 31-12-2025 y el autor remite a [Codeberg](https://codeberg.org/fsphil/ssdv). MFSK pictures de fldigi sería igualmente otro modem y flujo de imagen. No mezclar estos motores con los perfiles analógicos ni declarar soporte solo por añadir sus nombres al selector.

## Fixtures y recepción implementada

El proyecto conserva 28 WAV del conjunto clásico, más 27 WAV MMSSTV/cabeceras, PCM16 mono a 8 kHz en `Tests/RadioCoreTests/Fixtures`. Cubren las 41 variantes implementadas, desplazamientos, rangos de color y rechazo de cabeceras. Sus manifiestos son `image-manifest.json`, `extra-image-manifest.json`, `family-image-manifest.json` y `mmsstv-manifest.json`. Los generadores están en `script/generate_image_fixtures.py`, `script/generate_sstv_extra.py`, `script/generate_sstv_family_fixtures.py` y `script/generate_mmsstv_fixtures.py`.

PD50 tiene 49,684480 s de imagen según suma de tiempos D y Robot36 tiene 36 s; ambos precedidos por 0,91 s de calibración/VIS. Los manifiestos detallan silencio inicial, fase, hashes y secuencia. Las pruebas verifican raster completo, RGB y, en las variantes nuevas, las zonas iniciales/finales que revelan errores acumulados de temporización. Son señales matemáticas de laboratorio, sin fading, deriva de reloj ni recepción RF real. Las cuatro extensiones de familias históricas se prueban contra el modelo publicado, todavía sin corpus de transmisores externos.

El inventario estructurado está en [sstv-modes.json](sstv-modes.json) y se empaqueta con la app para el **Catálogo completo**. Conserva fuente, tipo de cabecera, raster, timing, límite y estado de evidencia por entrada. Sus 103 perfiles siguen separados de los 41 formatos habilitados. Cada formato tiene un **Ejemplo** completo propio, excepto Auto VIS que usa Martin M1. El catálogo documenta la investigación; [VALIDACION.md](VALIDACION.md) registra las pruebas efectivamente ejecutadas.
