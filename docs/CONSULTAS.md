# Consultas locales · 0.8.7

La pantalla **Consultas de radio** reúne consulta de frecuencia, directorios SUBTEL, actividad APRS por Internet y pases de satélites.

## Frecuencia y bandas chilenas

El buscador compara la frecuencia ingresada en MHz con las asignaciones de radioaficionado de la tabla SUBTEL publicada en 2025. Muestra servicio, categoría primaria/secundaria y segmentos de satélite cuando se superponen. Una frecuencia ausente de esta tabla no se clasifica como libre: la consulta no contiene todas las asignaciones de espectro.

El perfil elegido muestra modulación RF, ancho, banda de audio y centro que requiere el decodificador RadioWorkbench. **Preparar recepción** abre ese decodificador y conserva la frecuencia como instrucción de sintonía manual en SDR++; no controla el VFO ni configura automáticamente el demodulador externo.

## Repetidoras y licencias SUBTEL

La app revisa la página de Radioaficionados de SUBTEL al abrirse si la copia local tiene más de 24 horas. El Excel mensual de repetidoras se interpreta en el Mac; si el formato o los encabezados cambian, se conserva la copia previa y se muestra el error. La lista puede buscarse por indicativo, región o comuna. Cuando la fila publica coordenadas, estas se proponen en el análisis ITM; si no, se pueden ingresar manualmente. El sitio puede estar autorizado aunque el repetidor no esté transmitiendo.

La búsqueda de indicativos descarga los PDF vigentes de categorías y aspirantes. RadioWorkbench conserva solo indicativo, categoría, zona publicada y fecha de vencimiento; descarta nombres y números de licencia. La fecha de actualización mostrada proviene del texto de la página SUBTEL.

El botón **Usar como destino ITM** carga las coordenadas en el perfil de terreno VHF/UHF. Si hay frecuencia de transmisión publicada, la copia al campo de frecuencia para escuchar; el resultado sigue siendo una predicción del enlace, no una recepción confirmada.

## APRS cercano

La conexión solo comienza cuando el usuario la solicita. Requiere un indicativo y una ubicación guardada; usa APRS-IS por TCP con `pass -1` y filtro geográfico, no transmite paquetes. El área redondea latitud y longitud a dos decimales antes de enviar el filtro. Los paquetes recibidos pueden haber llegado por gateways remotos: no confirman cobertura RF en el Mac. Se reconocen posiciones APRS sin comprimir y comprimidas; otras formas, incluidas Mic-E, se omiten.

Los resultados permanecen en memoria hasta detener la conexión o cerrar la app. Se puede usar la última posición publicada como destino del perfil ITM, dejando claro que el punto viene de APRS-IS.

## Satélites y pases

La app actualiza en línea el catálogo de frecuencias AMSAT/SatNOGS, los elementos GP del grupo `amateur` de CelesTrak y los reportes de estado publicados en AMSAT. Las fuentes se guardan en caché para consultar sin conexión. Los reportes de estado son observaciones de usuarios, no telemetría oficial del satélite.

Los pases de 48 horas se calculan desde elementos orbitales recientes con Kepler y corrección secular J2. Este método no implementa SGP4; horarios y elevación son aproximados, sobre todo si el TLE está antiguo. No se estima ni corrige Doppler y no se controla SDR++. La interfaz muestra la época orbital para que se pueda evaluar su antigüedad.

Los datos de frecuencia derivados de SatNOGS se atribuyen en la interfaz y se distribuyen bajo CC BY-SA 4.0. Las órbitas provienen de CelesTrak y los reportes de estado de AMSAT.

## Fuentes

- [SUBTEL · servicio de radioaficionados, listados y tabla](https://www.subtel.gob.cl/inicio-concesionario/servicios-de-telecomunicaciones/servicios-de-radio-aficionados/)
- [SUBTEL · tabla de frecuencias 2025](https://www.subtel.gob.cl/wp-content/uploads/2025/06/Tabla_de_Bandas_Actualizada_2025.pdf)
- [APRS-IS · conexión y filtros](https://www.aprs-is.net/Connecting.aspx)
- [AMSAT · catálogo de frecuencias](https://satdb.amsat.org/)
- [AMSAT · API de reportes de estado](https://www.amsat.org/status/api/)
- [CelesTrak · formatos de elementos orbitales GP](https://celestrak.org/NORAD/documentation/gp-data-formats.php)
- [Catálogo de datos de frecuencia · CC BY-SA 4.0](https://github.com/palewire/amateur-satellite-database/tree/main/data)
