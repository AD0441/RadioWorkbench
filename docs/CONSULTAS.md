# Consultas de radio · 0.8.10

La pantalla **Consultas de radio** reúne consulta de frecuencia, directorios SUBTEL, actividad APRS por Internet y pases de satélites.

## Frecuencia y bandas chilenas

El buscador compara la frecuencia ingresada en MHz con las asignaciones de radioaficionado de la tabla SUBTEL publicada en 2025. Muestra servicio, categoría primaria/secundaria y segmentos de satélite cuando se superponen. Una frecuencia ausente de esta tabla no se clasifica como libre: la consulta no contiene todas las asignaciones de espectro.

El perfil elegido muestra modulación RF, ancho, banda de audio y centro que requiere el decodificador RadioWorkbench. **Preparar recepción** abre ese decodificador y conserva la frecuencia como instrucción de sintonía manual en SDR++; no controla el VFO ni configura automáticamente el demodulador externo.

## Repetidoras y licencias SUBTEL

La app revisa la página de Radioaficionados de SUBTEL al abrirse si la copia local tiene más de 24 horas. El Excel mensual de repetidoras se interpreta en el Mac; si el formato o los encabezados cambian, se conserva la copia previa y se muestra el error. La lista puede buscarse por indicativo, región o comuna. Cuando la fila publica coordenadas, estas se proponen en el análisis ITM; si no, se pueden ingresar manualmente. El sitio puede estar autorizado aunque el repetidor no esté transmitiendo.

La búsqueda de indicativos descarga los PDF vigentes de categorías y aspirantes. RadioWorkbench conserva solo indicativo, categoría, zona publicada y fecha de vencimiento; descarta nombres y números de licencia. La fecha de actualización mostrada proviene del texto de la página SUBTEL.

El botón **Usar como destino ITM** carga las coordenadas en el perfil de terreno VHF/UHF. Si hay frecuencia de transmisión publicada, la copia al campo de frecuencia para escuchar; el resultado sigue siendo una predicción del enlace, no una recepción confirmada.

El mapa pequeño muestra los resultados que tienen coordenadas publicadas válidas, el sitio seleccionado en naranja y la ubicación guardada del observador. No convierte el centro de una comuna en una ubicación supuestamente precisa. Si falta la posición, se puede escribir latitud/longitud o activar **Ubicar con clic**; esa posición manual se utiliza al preparar el destino ITM. El modo de ubicación con clic se desactiva al elegir otra repetidora para evitar modificarla accidentalmente.

## APRS cercano

La conexión solo comienza cuando el usuario la solicita. Requiere un indicativo y una ubicación guardada; usa APRS-IS por TCP con `pass -1` y filtro geográfico, no transmite paquetes. El área redondea latitud y longitud a dos decimales antes de enviar el filtro. Los paquetes recibidos pueden haber llegado por gateways remotos: no confirman cobertura RF en el Mac. Se reconocen posiciones APRS sin comprimir y comprimidas; otras formas, incluidas Mic-E, se omiten.

Los resultados permanecen en memoria hasta detener la conexión o cerrar la app. Se puede usar la última posición publicada como destino del perfil ITM, dejando claro que el punto viene de APRS-IS.

## Satélites y pases

La app actualiza tres conjuntos independientes: frecuencias AMSAT/SatNOGS, órbitas y reportes de estado AMSAT. Las frecuencias se descargan mediante la API oficial de contenidos de GitHub y conservan una alternativa raw. Las órbitas utilizan GP del grupo `amateur` de CelesTrak y TLE de AMSAT como alternativa; si AMSAT fue el último proveedor orbital que funcionó, se intenta primero al actualizar. La interfaz muestra fuente y fecha para cada conjunto. Un error de frecuencias no impide calcular pases si existen órbitas válidas; un fallo de red conserva la última copia correspondiente.

La reparación 0.8.10 interpreta como UTC las épocas GP que CelesTrak entrega sin sufijo `Z`, acepta fracciones de segundo y valida los campos físicos. Los TLE deben tener checksum correcto y NORAD coincidente. Lee la fecha real `reported_time` de la API AMSAT. Los reportes conservan satélite, estado y hora, descartando indicativos y cuadrículas de los colaboradores. Los errores HTTPS se presentan sin desactivar la validación de certificados.

La prueba con URLSession nativo del 14 de octubre descargó **97 satélites, 402 registros de frecuencias y 500 reportes**. CelesTrak agotó el tiempo de espera en el primer intento; AMSAT TLE permitió completar las órbitas. La siguiente actualización, con AMSAT preferido, terminó en 1,43 s. Es evidencia de esa consulta, no una garantía de disponibilidad permanente.

Los pases de 48 horas usan SatelliteKit SGP4/SDP4 con BSTAR conservado en GP/TLE, observador WGS84 y época visible. El mapa calcula Doppler de AOS/LOS para una frecuencia nominal editable; no controla SDR++. Una caché anterior sin BSTAR requiere actualización. Consulta [motores 0.9](INTEGRATIONS-0.9.md).

Selecciona un pase de la tabla para mostrar su trayectoria proyectada sobre Apple Maps, con observador y marcas AOS, máximo y LOS. Las polilíneas se separan al cruzar el meridiano de 180°. El gráfico polar usa la misma solución orbital: norte arriba, este a la derecha, horizonte en el borde y 90° de elevación en el centro. La hora del pase incluye fecha para distinguir los dos días calculados. Cambiar satélite, ubicación o elementos elimina resultados anteriores y descarta resultados de cálculos pendientes.

El mapa es la trayectoria terrestre del satélite durante el pase; no es una huella de cobertura RF. Para obtener resultados hace falta una ubicación guardada y pulsar **Calcular pases**. Una órbita antigua puede dar horarios imprecisos aunque la descarga de hoy haya funcionado; la época orbital y la fecha de consulta son campos distintos.

Los datos de frecuencia derivados de SatNOGS se atribuyen en la interfaz y se distribuyen bajo CC BY-SA 4.0. Las órbitas provienen de CelesTrak o AMSAT y los reportes de estado de AMSAT. Los reportes son observaciones de usuarios, no telemetría oficial.

## Fuentes

- [SUBTEL · servicio de radioaficionados, listados y tabla](https://www.subtel.gob.cl/inicio-concesionario/servicios-de-telecomunicaciones/servicios-de-radio-aficionados/)
- [SUBTEL · tabla de frecuencias 2025](https://www.subtel.gob.cl/wp-content/uploads/2025/06/Tabla_de_Bandas_Actualizada_2025.pdf)
- [APRS-IS · conexión y filtros](https://www.aprs-is.net/Connecting.aspx)
- [AMSAT · catálogo de frecuencias](https://satdb.amsat.org/)
- [AMSAT · API de reportes de estado](https://www.amsat.org/status/api/)
- [CelesTrak · formatos de elementos orbitales GP](https://celestrak.org/NORAD/documentation/gp-data-formats.php)
- [AMSAT · elementos Keplerianos y TLE](https://www.amsat.org/keplerian-elements-resources/)
- [Catálogo de datos de frecuencia · CC BY-SA 4.0](https://github.com/palewire/amateur-satellite-database/tree/main/data)

## Sintonía y mapa en 0.11

La consulta por frecuencia permite preparar una propuesta Rigctl con frecuencia, modo y ancho. La conexión local se habilita aparte; comprobar solo lee, y enviar requiere pulsar un botón. El servidor se vuelve a leer para confirmar los tres ajustes. No se envían PTT ni seguimiento automático.

El mapa común conserva posiciones APRS/ACARS con su procedencia. Una conexión APRS-IS ya iniciada puede continuar al entrar al mapa, con botón Desconectar visible; se detiene al salir hacia otras herramientas. El mapa no inicia conexiones ni obtiene ubicación por sí solo. Una recepción de audio ya iniciada también puede seguir mientras se consulta el mapa, con su botón Detener visible.
