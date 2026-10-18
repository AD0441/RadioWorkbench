# Revisión de aplicaciones: siguientes integraciones

**Actualización 0.11:** las propuestas iniciales evolucionaron a implementaciones documentadas en [Nueve mejoras](NUEVE-MEJORAS.md). Este informe conserva la evidencia y el estado de la investigación anterior; no atribuye los cambios posteriores al binario instalado.

Fecha: 17 de octubre de 2026. La revisión cubre **las copias instaladas indicadas por el usuario**. La investigación de SatDump/SDRangel y la investigación paralela de AFSK1200/SDR++Brown emplearon inventarios estáticos REA 6.4.0; se integran abajo con atribución a su evidencia. Se leyeron metadatos, símbolos y configuraciones. No se abrieron las interfaces, no se capturó radio, no se ejecutaron sus decodificadores y no se recuperó su código mediante un descompilador.

MultiMode dispone de una [revisión detallada previa](REVISION-MULTIMODE.md) y una [nueva identidad REA](app-evidence-0.10/multimode-summary.json). El avance de MT63 y ALE 2G se registra por separado. Las propuestas siguientes todavía no representan modos disponibles en RadioWorkbench.

## Identidad y evidencia conservada

| Copia inspeccionada | Versión declarada | Arquitectura observada | SHA-256 del ejecutable principal |
|---|---|---|---|
| SatDump.app | 1.2.3 | arm64 | `82ca066fc01a0412f2486e983377105b491a8b915c73caed216bc3e49ebc680f` |
| SDRangel.app | 7.27.1 | arm64 | `8afeb0e6667c2ec23e1d1a04a6e0524c95d3636d7013813ac765de49b1b0471b` |
| AFSK1200 Decoder.app | Sin versión en el plist inspeccionado | x86_64 | `521d4907cefce1c5615cfb652690aa8ec8b3bc818785a781f254e6c500319537` |
| SDR++Brown.app | 1.2.1; texto interno `1.2.1-brown` | arm64 | `547e193c66f37966953457759dfb2ec88fb238aa5187392a9cecd733f5f24c6d` |
| MultiMode Cocoa.app | 6.9.1b1 | x86_64, slice único | `3464d5add25fa01096c2eabca8ff490e49b3fbae5dd3011a536c495dcce6338f` |

El ejecutable de consola `satdump` declara macOS 11.0 mínimo en su cabecera Mach-O; el ejecutable principal de SDRangel declara 14.0. Esto no demuestra el mínimo de todas sus dependencias. Ambas copias contienen código para Apple Silicon; esta revisión no midió consumo, latencia ni rendimiento.

| Target | Evidencia REA de inspección | Evidencia de inventario | Manifiesto |
|---|---|---|---|
| SatDump | `ev_a826f2cd0e4ca674f3b84965016775a3f399417ef3085feef5db70802cd78b5d` | `ev_4a797ed1edb8ee4891e327bec8dd42fa6de0c1220c431a4372532ad41179249b` | `agm_139f7875abf7c78e9207f7994678cf847778cf1ebab18bd4cfff191afe88b80c` |
| SDRangel | `ev_01787d16a2c0d3792c6a2324eff217dbc0a0ffda1af06559ac809f6bfcc3bbe8` | `ev_af36007e27afd5cd37cdf6456d1b8ba58ef91cd9f5777aa3a41415a3501ff168` | `agm_8d5d35eb7c2766930542e3f607c35328a0a962c65749d1b3d4fdd07f765e4382` |
| AFSK1200 | `ev_4240f4182adad57c862bd13648eb7c58fb36bbe48f1cf18b3c5fea1783baa7da` | `ev_500ddb88811ca7479918f014ab4889f20d66579960fd5a975e9369758d881ef5` | `agm_4e6739b9f215bf93a19daf4fc16801a28070a942163655ce594931f59ddf6d01` |
| SDR++Brown | `ev_5d5f90d7e7d189b9116349ec7f6708d49a638e4a4db940bedd2deb79ea4bcf63` | `ev_6aa4742b391eb860d08fa247b07691e999c48b1177f11669d392ec7a75731b63` | `agm_4f17f629d3f496b8edde4a3d723d27dc7f5865649e27d6085f4d258e8b360739` |

El [resumen verificable](app-evidence-0.10/satdump-sdrangel-summary.json) relaciona cada fichero seleccionado con su hash y nodo del inventario. Los JSON completos de REA permanecen en `docs/app-evidence-0.10/local/satdump-sdrangel/`, excluidos de Git. Los hashes del directorio calculados por REA son identidades del inventario, distintos de los hashes de los ejecutables de la tabla.

AFSK1200/Brown se resumen desde la investigación paralela; sus JSON completos se conservan bajo `docs/app-evidence-0.10/local/afsk-sdrpp/`. MultiMode necesitó una recuperación diferente: REA rechazó el contenedor FAT sin slice arm64; se extrajo su único slice x86_64 sin modificar el original y se inventarió ese derivado, evidencia `ev_e16b9529b30651f953f164daa5ed34d42f4ef5915b38b872bd5323b0a53b589f`. No es evidencia de ejecución ni de equivalencia de sus decodificadores.

## Hallazgos que cambian las decisiones

**SatDump aporta una arquitectura útil para ampliar satélites.** La copia contiene un ejecutable separado `Contents/MacOS/satdump`, 76 configuraciones JSON con comentarios y 194 definiciones de procesamiento. El análisis de esos documentos establece sus etapas y parámetros; la presencia de una definición no prueba recepción ni funcionamiento de sus módulos.

El procesamiento `meteor_m2-x_lrpt` pasa por `baseband → soft → cadu → products`: OQPSK a 72 ksímbolos/s, decodificación convolucional/CCSDS, Reed–Solomon y productos MSU-MR. También existe una variante a 80 ksímbolos/s. La configuración instalada propone 1 Mmuestra/s de entrada. Necesita **I/Q complejo** conservando la señal; la salida de audio de voz de SDR++ no sustituye esa entrada. La [documentación oficial de pipelines](https://docs.satdump.org/md_docs_2pages_2Pipelines.html) explica el modelo general; los valores concretos citados provienen del archivo instalado `pipelines/Meteor-M.json`, hash `0eed0e52d4615539b65873471a15abc376a442d8a604865ea19b50cdd0c8f550`.

**APT puede crecer como herramienta para grabaciones históricas.** El pipeline instalado `noaa_apt` admite la etapa `audio_wav` antes del decodificador de imagen. Sus opciones incluyen guardar imagen sin sincronizar, alinear marcas temporales y recortar. Una futura integración puede añadir productos y proyección, pero debe exigir fecha de captura y datos orbitales adecuados para esa fecha. La georreferenciación no se valida por tener una imagen decodificada.

**El catálogo de una aplicación no acredita que un transmisor siga activo.** SatDump 1.2.3 conserva `live: true` y frecuencias de NOAA 15/18/19 en `pipelines/NOAA.json`. NOAA confirma que los tres fueron retirados en 2025. RadioWorkbench ya presenta APT como reproducción histórica y debe conservar esa distinción. Conviene añadir procedencia, fecha de verificación y estado del transmisor a cualquier futuro catálogo importado. [Estado oficial POES](https://ospo.noaa.gov/operations/poes/status.html).

**SDRangel confirma candidatos útiles, pero sus plugins no son helpers de audio autónomos.** El inventario contiene 130 bibliotecas en `Contents/Resources/lib/plugins`, incluidas DSC, AIS, radiosondas, Inmarsat C, Meshtastic, MeshCore, APT, NAVTEX, entrada y salida SigMF. La consulta estática de símbolos del plugin DSC encuentra `DSCDemodSink::receiveBit(bool)`, `processOneSample(complex<float>&)` y métodos de API web. La interfaz depende de Qt y del entorno SDRangel: copiar la biblioteca al bundle no integra el modo.

**AFSK1200 sirve como contraste, sin justificar sustituir el receptor nativo.** La inspección paralela encuentra una app Intel y textos de Qtmm que describen AX.25/APRS por tarjeta de sonido, selección de dispositivo, guardado y aviso de CRC incorrecto. Son textos empaquetados, no recepción observada. El [proyecto Qtmm](https://github.com/csete/qtmm) está archivado y se describe como obsoleto. RadioWorkbench ya tiene entrada seleccionable y AX.25/APRS con CRC; lo aprovechable es mejorar la explicación de errores y la exportación.

**Brown ofrece una posible conexión de audio sin cable virtual.** El bundle incluye módulos Network Sink, Network Source, Rigctl Server, Recorder, FT8 y un decodificador VHF adicional. Esa presencia no establece cuáles están cargados. El [código upstream Network Sink](https://raw.githubusercontent.com/sannysanoff/SDRPlusPlusBrown/master/sink_modules/network_sink/src/main.cpp) convierte audio a `int16` nativo sin cabecera; configura por defecto 48 kHz, mono, localhost y puerto 7355, con UDP por defecto y TCP seleccionable. Para M1 corresponde a PCM de 16 bits little-endian. **Propuesta:** cliente TCP local explícito en RadioWorkbench, verificando antes el contrato de la compilación instalada. Network Source corresponde a otra ruta: no confundir entrada I/Q con salida de audio.

El [código upstream Rigctl Server](https://raw.githubusercontent.com/sannysanoff/SDRPlusPlusBrown/master/misc_modules/rigctl_server/src/main.cpp) permite seleccionar VFO y cambiar frecuencia, modo y ancho; propone localhost:4532 y arranque automático desactivado. Esto hace plausible un botón optativo «Sintonizar en SDR++» desde una consulta o pasada. Falta contrastar versión/protocolo con la app instalada; no se envió ningún comando ni se cambió su configuración.

## Modos y entradas que conviene incorporar

| Elemento | Qué aporta | Entrada adecuada | Etapa propuesta y verificación necesaria |
|---|---|---|---|
| DSC MF/HF y VHF | MMSI, destinatario, categoría, posición y comprobación de mensaje | MF/HF: audio SSB de dos tonos, 100 baud y separación de 170 Hz. VHF: audio NFM con tonos de 1300/2100 Hz a 1200 baud; el plugin usa canal RF de 20 kHz | Próximo receptor de audio: implementar sincronía, diversidad temporal, símbolos y ECC; probar mensajes válidos, dañados, silencio y flujos fragmentados antes de habilitarlo |
| AIS | Buques, rumbo, velocidad y trayectoria en mapa | I/Q o discriminador FM plano que conserve el ancho y la respuesta necesarios; para una primera conexión, NMEA ya decodificado por UDP | Primero importación NMEA local con checksum, fragmentación y origen visible; después demodulación GMSK y validación CRC con grabaciones |
| Radiosondas RS41 | Globo en mapa, altitud, trayectoria, temperatura y humedad | I/Q o discriminador FM plano validado. La ruta de voz NFM puede modificar la señal | Primero aceptar telemetría de un motor externo; después recepción GFSK propia con Reed–Solomon y controles de calibración |
| METEOR LRPT con SatDump | Imágenes meteorológicas, canales y productos derivados | Archivo I/Q con formato, frecuencia, muestreo y fecha conocidos | Importación offline, ejecución de un motor seleccionado, progreso, cancelación y galería de resultados; validar con una captura independiente |
| Inmarsat C | Mensajes marítimos y áreas geográficas | I/Q de canal estrecho; una eventual entrada SSB requiere un adaptador y pruebas explícitas | Etapa posterior: motor externo y archivos de prueba, reensamblado, separación entre trama, mensaje y coordenadas |
| Meshtastic/MeshCore | Observación de redes y posiciones de nodos | I/Q para CSS/LoRa o eventos ya decodificados | Etapa posterior: adaptador de eventos; validar el esquema exacto de la versión elegida antes de implementarlo |

Las especificaciones de DSC, sus campos de ECC y sus salidas UDP/CSV están descritos en el [manual del plugin DSC](https://github.com/f4exb/sdrangel/blob/master/plugins/channelrx/demoddsc/readme.md). El [manual AIS](https://github.com/f4exb/sdrangel/blob/master/plugins/channelrx/demodais/readme.md) documenta GMSK a 9600 baud, canales de 25 kHz y NMEA por UDP. El [manual RS41](https://github.com/f4exb/sdrangel/blob/master/plugins/channelrx/demodradiosonde/readme.md) documenta GFSK a 4800 baud, corrección Reed–Solomon y telemetría.

El [manual Inmarsat C](https://github.com/f4exb/sdrangel/blob/master/plugins/channelrx/demodinmarsat/readme.md) describe BPSK a 1200 símbolos/s, reconstrucción de mensajes y mapa. El [formato JSON UDP de Meshtastic](https://github.com/f4exb/sdrangel/blob/master/json_udp_data_format.readme.md) conserva tipo de paquete, estado de interpretación y resultados CRC/FEC. Son documentos upstream actuales; esta investigación no demostró que todos sus campos coincidan con la compilación instalada 7.27.1.

## Elementos nuevos, por prioridad

| Orden | Propuesta | Primer resultado concreto | Ampliación posterior |
|---|---|---|---|
| 1 | Biblioteca de recepciones | Audio, ajustes y fecha juntos; repetir decodificación | I/Q, SigMF y comparación entre motores |
| 2 | Diagnóstico de entrada y calidad | Causas medidas, integridad de paquetes y acciones comprensibles | Prueba guiada de cada conexión |
| 3 | Audio local por TCP desde Brown | Elegir una entrada de red con formato explícito | UDP con contadores de pérdida y fuentes adicionales |
| 4 | DSC marítimo | MF/HF y VHF, mensajes validados y exportación | Áreas geográficas, filtros y contexto marítimo |
| 5 | Mapa común de recepciones | Origen, antigüedad y trazas de posiciones ya disponibles | AIS/RS41 y avisos locales configurables |
| 6 | SatDump offline para LRPT | I/Q identificado, progreso y productos importados | Preparación de pasadas y fuente I/Q de red |
| 7 | Sintonía optativa desde consultas | Rigctl: comprobar conexión y enviar frecuencia/modo/ancho | Doppler de seguimiento una vez validado |
| 8 | Adaptadores de eventos externos | Un formato documentado, validado y con procedencia | NMEA, telemetría y eventos por protocolo |
| 9 | Taller de aprendizaje de señales | Comparar una señal de referencia, su espectro y sus parámetros | Ejercicios CW y clasificación asistida con incertidumbre |

Estas prioridades son una propuesta de diseño. El flujo de audio TCP y Rigctl necesitan una prueba independiente de interoperabilidad; el usuario aplazó la prueba física SDR++/VB-Cable y esa decisión se conserva.

1. **Biblioteca de recepciones reproducibles.** Guardar junto al audio el modo, entrada, canal, frecuencia RF declarada, modulación, ancho, muestreo, fecha UTC y versión del motor. Permitir volver a procesar y comparar resultados. El primer paso puede reutilizar las grabaciones y perfiles existentes; el posterior añade I/Q y metadatos compatibles con SigMF.
2. **Diagnóstico de señal que explique por qué no decodifica.** Diferenciar ausencia de audio, saturación, banda recortada, frecuencia de muestreo insuficiente, captura incompleta y pérdida de sincronía. Mostrar primero la acción útil: ajustar volumen, ensanchar el filtro o reiniciar la transmisión desde su cabecera. Debe basarse en medidas, sin presentar la mera ausencia de mensajes como identificación del problema.
3. **Mapa común de recepción local.** Reunir APRS, ADS-C, futuros DSC/AIS y radiosondas con trazas, antigüedad y tipo de origen. Un dato recibido de SDRangel por red debe figurar como decodificación externa; un punto de Internet no debe aparecer como recepción RF del Mac. Añadir filtros y avisos locales por área o indicativo/MMSI cuando el usuario los active.
4. **Satélites: pasar de predicción a flujo de captura y resultados.** Elegir una pasada, comprobar el tipo de señal y entrada necesarios, adjuntar una grabación y obtener productos con su procedencia. La frecuencia nominal, Doppler y horario previstos ayudan a preparar la recepción; no confirman que una emisión esté activa. La primera versión puede trabajar solo con archivos, seguida por una fuente I/Q de red o SDR.
5. **Conexión local con otros decodificadores.** Recibir NMEA, tramas o eventos documentados mediante adaptadores por protocolo. Esto permite aprovechar SDRangel sin incorporar toda su interfaz Qt. Incorporar primero un solo formato estable con límites de tamaño, validación, conexión explícita y exportación; ampliar con capturas de prueba de cada fuente.

## Modos originales que siguen pendientes

| Modo | Entrada y alcance correcto | Qué falta para habilitarlo |
|---|---|---|
| SITOR-A | Audio SSB; recepción pasiva ARQ, diferente del FEC de SITOR-B/NAVTEX | Implementar ciclos, control y retransmisiones según [ITU-R M.476](https://www.itu.int/rec/R-REC-M.476/en); corpus con errores y repeticiones. No reutilizar el rótulo SITOR-B como si cubriera A |
| GMDSS / DSC | DSC MF/HF y VHF tienen rutas de audio posibles; GMDSS incluye servicios adicionales | Receptor y parser con símbolos, diversidad temporal y ECC. Validar ambos perfiles. El candidato xng consume I/Q, mientras que el plugin SDRangel necesita adaptación; ninguno se activa por añadir un selector |
| DGPS marítimo | Balizas MSK y mensajes RTCM; una cadena de audio SSB adecuada puede estudiarse | Seleccionar implementación con licencia, demodulación MSK, paridad/encadenamiento RTCM, grabaciones y parámetros. [on1arf/dgps](https://github.com/on1arf/dgps) es un módulo GNU Radio/Python, sin release; [gr-dgps](https://github.com/cruvolo/gr-dgps) tiene otro entorno y licencia. No se verificó port arm64 ni vigencia de los catálogos históricos |
| LORAN-C | Monitor de pulsos/GRI; conservar temporización y ancho de la captura RF o IF adecuada | Definir hardware y captura antes de portar el [monitor KiwiSDR](https://github.com/jks-prv/KiwiSDR/tree/master/extensions/Loran_C). Audio de voz filtrado no garantiza una forma de pulso válida; dibujar pulsos no establece navegación |
| Globe Wireless | El manual histórico describe identificación de estaciones en paquetes idle, no un receptor universal de mensajes | Especificación, capturas identificadas, estado de emisores y un motor RX reutilizable. [iq_broadcast](https://github.com/eugenyh/iq_broadcast) es un generador: su presencia no resuelve recepción. El resultado negativo se limita a la búsqueda documentada |
| ALE 3G | Protocolo distinto de ALE 2G | Elegir motor y corpus propios; una integración 2G no acredita 3G |

## Licencias y límites pendientes

[SatDump](https://github.com/SatDump/SatDump) declara GPL-3.0. El encabezado del [sink DSC de SDRangel](https://github.com/f4exb/sdrangel/blob/master/plugins/channelrx/demoddsc/dscdemodsink.cpp) declara GPL-3.0 o posterior. Una implementación debe seleccionar una revisión concreta, conservar sus licencias y cumplir la distribución del código correspondiente. El inventario de un bundle no resuelve las licencias individuales de todas sus dependencias. Ningún binario de estas aplicaciones se ha copiado a RadioWorkbench en esta revisión.

| Pregunta | Estado | Evidencia o límite |
|---|---|---|
| ¿Qué versiones y arquitectura tienen las copias? | Respondida | REA, plists, cabeceras Mach-O y hashes |
| ¿Qué pipelines y plugins se distribuyen? | Respondida dentro del inventario | 76 JSONC/194 definiciones SatDump y 130 bibliotecas de plugins SDRangel |
| ¿Qué señales necesitan audio o I/Q? | Parcialmente respondida | Configuración instalada y documentación de los protocolos; falta validar cada adaptador |
| ¿Puede reutilizarse directamente el plugin DSC como helper? | No acreditado | Símbolos y fuente muestran interfaz Qt/SDRangel; no hay contrato PCM autónomo validado |
| ¿Funcionan en recepción real todos esos modos? | No evaluada | No hubo ejecución ni captura RF |
| ¿Cuál es su consumo y estabilidad en M1? | No evaluada | La arquitectura arm64 está acreditada; faltan medidas y pruebas runtime |
