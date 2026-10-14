# Spots, alertas y perfil de terreno · 0.8.6

## Reverse Beacon Network

La conexión RBN se inicia manualmente desde **Condiciones y propagación**. El flujo CW/RTTY usa `telnet.reversebeacon.net:7000`; el flujo FT8 usa el puerto 7001. Se envía el indicativo o alias escrito para iniciar sesión en el nodo. No se transmite por radio. Los relés oficiales no filtran el caudal: RadioWorkbench aplica el filtro de banda y modo en el Mac, conserva hasta 1.000 spots y muestra como máximo 60 filas. No hay reconexión automática; la app no mantiene una conexión en segundo plano.

El feed informa frecuencia, señal detectada, modo y skimmer. No entrega coordenadas fiables para cada spot. Por eso el mapa no inventa ubicaciones RBN: muestra un conteo global por banda durante la última hora. El enlace azul es el trayecto del cálculo HF; las líneas verdes y marcadores PSK solo se dibujan si PSK Reporter publicó localizadores válidos para ambos extremos.

## Avisos de favoritas EiBi

En la ficha de una emisora, guárdala como favorita y activa **Avisarme**. macOS solicitará permiso de notificación en ese momento. Elige entre aviso al inicio o 5, 10 o 15 minutos antes. Se programa el próximo inicio UTC que el calendario EiBi identifica con certeza; días desconocidos o irregulares no producen un aviso. La guía recalcula avisos cuando actualiza EiBi y al abrirse. Los horarios son asignaciones publicadas: no confirman que la emisora transmita o que la recepción sea posible.

## Pronóstico NOAA de tres días

El panel consulta el producto de texto oficial NOAA SWPC, que incluye una tabla de Kp por periodos de tres horas, probabilidad de tormenta de radiación S1+ y probabilidad de apagón R1–R2/R3+. NOAA emite este pronóstico aproximadamente cada 12 horas; RadioWorkbench conserva caché y consulta como máximo cada seis horas, con espera de reintento si falla. El Kp y las probabilidades describen riesgo global, no disponibilidad cierta de una banda en una ubicación.

## Perfil de terreno NTIA ITM

En **VHF/UHF · enlace punto a punto con relieve**, fija origen TX y destino RX escribiendo sus coordenadas o haciendo clic en el mapa de Apple Maps, que permite alternar vista plana y relieve 3D. Los campos se guardan localmente. Puedes copiar la ubicación de la guía y el destino del planificador HF como punto de partida. Registra por separado la altura AGL de cada antena, frecuencia, potencia, ganancias y umbral del receptor. **Calcular relieve y enlace** envía explícitamente los extremos y hasta 501 puntos a Open-Meteo para consultar el DEM Copernicus GLO-90; se agrupan hasta 100 coordenadas por solicitud. Para enlaces de hasta 250 km el perfil usa aproximadamente 500 m entre muestras; el límite de 501 puntos aumenta esa separación en trayectos más largos, hasta 500 km. No se solicita GPS; las coordenadas salen de los campos guardados y el perfil se conserva en memoria durante la sesión.

**Calcular zona orientativa** parte del origen TX y consulta perfiles radiales hasta el radio máximo elegido (20–200 km). Usa 32 rumbos separados 11,25°, un perfil topográfico de aproximadamente 500 m entre muestras y evalúa alcances ITM en intervalos de hasta 5 km. La envolvente coloreada conecta los radios donde la potencia calculada supera el umbral RX. A 100 km, los rumbos vecinos aún están separados por unos 20 km; el borde entre ellos es interpolado y puede omitir valles o crestas fuera de los perfiles. Es una exploración del umbral ITM, no un mapa probabilístico ni una garantía.

El mapa topográfico 3D muestra el trayecto, la envolvente ITM y un radiohorizonte solo como referencia geométrica. El corte del enlace grafica el relieve aparente con curvatura k=4/3 y el rayo directo. En cada extremo, la altura de la antena sobre el nivel del mar se calcula como **elevación del terreno AMSL + altura AGL**. La marca naranja indica dónde la montaña cruza la línea directa. Una obstrucción visual no significa silencio total: NTIA ITM puede estimar señal difractada sobre esa cresta. El corredor Fresnel del 60 % sigue siendo una referencia geométrica, no una probabilidad.

El motor NTIA ITM calcula pérdida básica, irregularidad de terreno, modo de propagación y potencia recibida estimada en dBm. Sus entradas de antena son alturas estructurales AGL; el perfil contiene elevaciones AMSL, y el modelo combina ambos valores internamente para evaluar horizontes y difracción. La potencia recibida combina pérdida calculada con los watts y ganancias introducidos. Se muestra el margen frente al umbral RX; no es una tasa de éxito. Se usan N0=301, permitividad=15, conductividad=0,005 S/m y confianza/fiabilidad del 50 %. El DEM tiene resolución nominal de 90 m, pero la app consulta muestras cada ~500 m y limita el perfil a 501 puntos. Aún pueden faltar crestas estrechas, y la envolvente no modela el terreno entre sus 32 perfiles radiales. La estimación no incluye patrón real de antena, edificios, vegetación, pérdidas de cable, interferencia ni refracción meteorológica instantánea. No garantiza alcance, cobertura o contacto.

El código ITM proviene del repositorio público [NTIA/itm](https://github.com/NTIA/itm), con licencia y aviso original incluidos en `Vendor/NTIA-ITM/LICENSE.md` y en el paquete. La compilación adapta en un directorio temporal las rutas de inclusión y anotaciones de exportación para macOS; no modifica el algoritmo upstream. Los datos de elevación son de [Copernicus GLO-90](https://doi.org/10.5270/ESA-c5d3d65), servidos por [Open-Meteo](https://open-meteo.com/en/docs/elevation-api); el crédito aparece en la app.

## Fuentes

- [RBN · servidores Telnet y puertos](https://beta.reversebeacon.net/pages/Telnet%2Bservers%2B30)
- [RBN · red de receptores voluntarios](https://www.reversebeacon.net/index.php)
- [PSK Reporter · API y datos](https://pskreporter.info/pskdev.html)
- [NTIA · código ITS Irregular Terrain Model](https://github.com/NTIA/itm)
- [Open-Meteo · API de elevación](https://open-meteo.com/en/docs/elevation-api)
- [NOAA SWPC · pronóstico de tres días](https://www.swpc.noaa.gov/products/3-day-forecast)
- [Producto NOAA en texto](https://services.swpc.noaa.gov/text/3-day-forecast.txt)
