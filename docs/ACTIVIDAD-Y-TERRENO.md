# Spots, alertas y perfil de terreno · 0.8.9

## Reverse Beacon Network

La conexión RBN se inicia manualmente desde **Condiciones y propagación**. El flujo CW/RTTY usa `telnet.reversebeacon.net:7000`; el flujo FT8 usa el puerto 7001. Se envía el indicativo o alias escrito para iniciar sesión en el nodo. No se transmite por radio. Los relés oficiales no filtran el caudal: RadioWorkbench aplica el filtro de banda y modo en el Mac, conserva hasta 1.000 spots y muestra como máximo 60 filas. No hay reconexión automática; la app no mantiene una conexión en segundo plano.

El feed informa frecuencia, señal detectada, modo y skimmer. No entrega coordenadas fiables para cada spot. Por eso el mapa no inventa ubicaciones RBN: muestra un conteo global por banda durante la última hora. El enlace azul es el trayecto del cálculo HF; las líneas verdes y marcadores PSK solo se dibujan si PSK Reporter publicó localizadores válidos para ambos extremos.

## Avisos de favoritas EiBi

En la ficha de una emisora, guárdala como favorita y activa **Avisarme**. macOS solicitará permiso de notificación en ese momento. Elige entre aviso al inicio o 5, 10 o 15 minutos antes. Se programa el próximo inicio UTC que el calendario EiBi identifica con certeza; días desconocidos o irregulares no producen un aviso. La guía recalcula avisos cuando actualiza EiBi y al abrirse. Los horarios son asignaciones publicadas: no confirman que la emisora transmita o que la recepción sea posible.

## Pronóstico NOAA de tres días

El panel consulta el producto de texto oficial NOAA SWPC, que incluye una tabla de Kp por periodos de tres horas, probabilidad de tormenta de radiación S1+ y probabilidad de apagón R1–R2/R3+. NOAA emite este pronóstico aproximadamente cada 12 horas; RadioWorkbench conserva caché y consulta como máximo cada seis horas, con espera de reintento si falla. El Kp y las probabilidades describen riesgo global, no disponibilidad cierta de una banda en una ubicación.

## Perfil y cobertura NTIA ITM

En **VHF/UHF · enlace punto a punto con relieve**, fija TX y RX mediante coordenadas o clic en Apple Maps. Ingresa la altura de cada antena sobre el suelo (AGL), frecuencia, watts, ganancias y umbral RX. **Calcular relieve y enlace** consulta el corredor DEM de ese trayecto o reutiliza la malla disponible. El perfil geodésico mantiene elevaciones AMSL separadas de las alturas AGL; ITM combina ambas y calcula pérdida, difracción y potencia recibida. Los enlaces se limitan a 1–500 km.

**Calcular malla con terreno** analiza un área de 5–200 km con 65 × 65 o 129 × 129 celdas. Cada centro recibe un cálculo independiente con todo su perfil topográfico. Las celdas bajo umbral quedan transparentes o rojas al activar su visualización, conservando sombras interiores e islas de recepción. El radio limita los puntos analizados y no define el alcance máximo. Elegir RX mantiene el área y permite calcular después el enlace exacto.

El raster se coloca sobre Apple Maps en vista plana o con relieve. El corte muestra terreno, curvatura de referencia k=4/3 y rayo entre antenas. La altura AMSL de cada antena es **terreno AMSL + altura AGL**; una cresta que corta la línea directa no implica silencio total. El corredor Fresnel del 60 % es una ayuda geométrica. El círculo de Tierra lisa usa únicamente AGL, es opcional y está apagado inicialmente.

El DEM viene de Mapzen Terrain Tiles/Terrarium en AWS, con SRTM/GMTED y otras fuentes regionales. La app descarga teselas solo al solicitar el cálculo y las conserva en caché; el proveedor recibe índices que permiten inferir la región. Apple Maps realiza sus consultas propias. El paso DEM cambia con zoom y latitud; el perfil usa ese paso, como mínimo 90 m y hasta 4.097 muestras. El paso de la malla se muestra por separado. Si falta relieve no se supone terreno plano. Las elevaciones negativas se llevan a nivel del mar como aproximación de superficie marina, sin distinguir aún depresiones terrestres.

NTIA utiliza N0=301, permitividad=15, conductividad=0,005 S/m y confianza/fiabilidad del 50 %, con clima y polarización elegidos. Las llamadas nativas arm64 evitan ejecutar un proceso por celda. Las predicciones válidas con avisos se conservan y explican; edificios, vegetación, patrón de antena, pérdidas de cable, interferencia y meteorología instantánea quedan fuera del modelo implementado.

Se mantienen el código y licencia de [NTIA/itm](https://github.com/NTIA/itm) en el repositorio y paquete; la adaptación de compilación para macOS no cambia su algoritmo. Mapzen y sus [atribuciones regionales](https://github.com/tilezen/joerd/blob/master/docs/attribution.md) aparecen en la app. [Revisión a fondo, resoluciones, privacidad y validación](TERRAIN-COVERAGE.md).

## Fuentes

- [RBN · servidores Telnet y puertos](https://beta.reversebeacon.net/pages/Telnet%2Bservers%2B30)
- [RBN · red de receptores voluntarios](https://www.reversebeacon.net/index.php)
- [PSK Reporter · API y datos](https://pskreporter.info/pskdev.html)
- [NTIA · código ITS Irregular Terrain Model](https://github.com/NTIA/itm)
- [Mapzen Terrain Tiles · catálogo AWS](https://registry.opendata.aws/terrain-tiles/)
- [Mapzen · formato Terrarium](https://github.com/tilezen/joerd/blob/master/docs/formats.md)
- [NOAA SWPC · pronóstico de tres días](https://www.swpc.noaa.gov/products/3-day-forecast)
- [Producto NOAA en texto](https://services.swpc.noaa.gov/text/3-day-forecast.txt)
