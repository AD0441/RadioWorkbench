# RADIO BUNKER SWL y la guía nativa

Objetivo: estudiar el APK suministrado, identificar la procedencia de sus datos y construir una consulta equivalente de emisoras en RadioWorkbench, con actualización cuando haya conexión. El APK se mantuvo intacto y no se ejecutó.

## Identidad y evidencia

Archivo: `/Users/sebastian/Downloads/rb_swl_1.5.1.apk`.
SHA-256: `6118bec924d855c6f4a234c0c6956bcc55ad47fcfcc0d339372f4e1927449783`.

REA MCP no estaba conectado. Se utilizó REA **6.4.0** mediante el gestor y Node existentes, sin registrar otro servidor, instalar JADX/Java ni cambiar la configuración global. Las operaciones fueron `inspect-artifact` sobre el APK y `analyze-javascript-application` sobre los recursos web extraídos, conservando los hashes de sus miembros en [apk-evidence/inventory.json](apk-evidence/inventory.json). Las extracciones y registros completos quedan localmente excluidos de Git y no se incluyen en la app.

| Conclusión | Evidencia y alcance |
|---|---|
| Es un APK con recursos Capacitor y una interfaz web | `ev_5bde37fb9fab9779db4b82b8b6dc2024c098cd78d637aee6168fa1b07ec28c6c`, inventario ZIP observado |
| El árbol extraído contiene 16 archivos relevantes, 13 JavaScript, sin fallos de parseo | `ev_1ff3eb6bf550d631b7f53fe7e04df2a52c0abaca0c5db19cd42535f542c21b8f`, análisis estático |
| Nombre RADIO BUNKER SWL y appId `com.dxradio.eibi` | `assets/capacitor.config.json`, miembro observado en el mismo inventario |
| Descarga horarios de EiBi por temporada, con alternativas y proxies | `assets/public/js/parser.js`, funciones `currentSeasonCode`, `candidateUrls`, `downloadEibiData`; lectura estática adicional, no ejecución Android |
| Guarda estaciones y metadatos para uso offline | `assets/public/js/db.js`, IndexedDB `eibi_current` |
| Recalcula el estado por horario cada minuto | `assets/public/js/app.js`, `timeRangeActive` y temporizador `renderAll` |
| La potencia típica y las coordenadas complementarias son datos manuales | `assets/public/js/transmitters.js`, tabla y cabecera; no es un feed de telemetría |
| Su probabilidad de recepción usa bandas, hora y distancia, sin clima espacial real | `assets/public/js/propagation.js`, `estimateReception`; inferencia de reglas estáticas, calidad no validada |

Digest exacto del árbol analizado: `ef4e14d77ee25e35b68c69eb8cdfdc450c812d07cfa660c03bf9e76b41dc786b`.
Resúmenes conservados: [APK](apk-evidence/rea-apk-summary.json), [JavaScript](apk-evidence/rea-js-summary.json).

El archivo se llama 1.5.1, pero `app.js` declara `APP_VERSION = "1.5.0"`; no se equiparan ambos valores. No se decompiló `classes.dex`: el proveedor JADX no estaba disponible. La actividad Android real, permisos efectivos, llamadas dinámicas y disponibilidad de sus proxies permanecen sin verificar. REA analizó texto inerte; un endpoint o temporizador estático no demuestra que se haya ejecutado en Android.

## Fuente pública comprobada

El 13 de octubre de 2026 se descargaron directamente:

- [CSV A26](http://www.eibispace.de/dx/sked-a26.csv): HTTP 200, 527.973 bytes; `Last-Modified: 4 Oct 2026 12:53:56 GMT`.
- [Documentación EiBi](http://www.eibispace.de/dx/README.TXT): campos, condiciones, idiomas, países, regiones y sitios transmisores.
- [Página EiBi](http://www.eibispace.de/): temporada A26 y actualización del 4 de octubre de 2026.

La documentación permite descargar, usar, copiar y distribuir las listas e incorporarlas en software de terceros. La app atribuye los datos a EiBi. Se conserva una copia inicial pública con metadatos y SHA-256 en `docs/eibi-snapshot`, incluida en el paquete para el primer uso sin conexión. No se reutilizan HTML, JavaScript, imágenes ni la tabla privada de potencia del APK.

La app nativa también realizó una descarga real y guardó su caché: **9.591 registros**, **289 países**, **560 idiomas**, **1.596 sitios con coordenadas**. Una fila de horario inválido se omitió y una duplicada se eliminó. Es una comprobación de red de RadioWorkbench, separada del análisis estático del APK.

## Comportamiento construido

**Guía de radios** en la barra lateral: búsqueda por emisora/país/idioma, frecuencia kHz y tolerancia, banda, tipo de señal, idioma, favoritos y emisiones previstas ahora. La ficha muestra UTC/días, país, destino, sitio, coordenadas, distancia/rumbo desde coordenadas introducidas por el usuario, datos originales y fecha de archivo. Hay enlaces a EiBi y al WebSDR de Twente, abierto externamente.

La consulta automática se inicia al abrir RadioWorkbench y se repite cada **6 horas**, también durante el uso de otros modos. Un fallo conserva la última copia y programa un reintento en **5 minutos**. **Actualizar** fuerza una nueva consulta; **Importar CSV** admite listas locales. La caché se guarda atómicamente en `~/Library/Application Support/RadioWorkbench/eibi-cache.json`.

Se intenta HTTPS y, si no está disponible, HTTP directo solo al dominio EiBi. La excepción ATS se limita a ese dominio. No se utilizan proxies CORS. Respuestas HTTP fallidas, HTML, listas demasiado pequeñas, exceso de tamaño o redirecciones a otros dominios no reemplazan la copia válida.

El reloj y los estados del horario se recalculan cada minuto. «Prevista ahora» significa que coincide el horario publicado; no demuestra que una estación esté transmitiendo ni que llegue al receptor. EiBi publica actualizaciones de listas, no intensidad de señal ni potencia instantánea. Se conserva la fecha de descarga y la fecha del archivo por separado.

Los días numéricos 1–7, intervalos semanales, medianoche, primer sábado, último domingo, MF-15, fechas puntuales y vigencia parcial DDMM se tratan explícitamente. Calendarios alternantes, religiosos o no reconocidos se muestran como **Horario incierto**, sin convertirlos automáticamente en emisiones confirmadas. Una copia de otra temporada se marca en la vista. Los sitios múltiples o ambiguos no se asignan a una coordenada inventada.

## Validación y pendientes

Pruebas de calendario y parseo con límites de temporada, medianoche, días numéricos y fechas parciales, incluido el sufijo histórico `[MMYY]`. Pruebas de servicio con descarga, fecha de fuente, persistencia, reapertura sin conexión, fallo de red, rechazo de HTML/redirección y fallback HTTP. La descarga real descrita arriba complementa esos casos simulados.

La revisión visual de 0.5 se completó con el Mac desbloqueado: tabla de emisoras, búsqueda BBC, filtro por frecuencia, favorito añadido y retirado, ficha de idioma/destino/sitio y actualización manual. La descarga visible pasó de 03:25 a 07:07 hora de Santiago el 13 de octubre. APRS mostró una trama con CRC válido y CTCSS el tono de 100 Hz del ejemplo. No se ha comprobado la experiencia de la app Android en un emulador. En 0.5 la guía aún no integraba predicción científica, potencia medida por transmisión ni control automático de SDR++; su alcance era EiBi y sintonía manual. **0.7 añade un apartado independiente de condiciones y propagación con NOAA e ITU-R P.533/P.372**, descrito en [PROPAGACION.md](PROPAGACION.md). La potencia de cálculo la declara el usuario; se investigó HFCC como fuente de potencia programada. Se confirmó Rigctl en el código de SDR++, pero el control aún no está integrado.
