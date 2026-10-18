# HFCC: emplazamientos, calendario y asociación con EiBi

Revisión de fuentes públicas: 18 de octubre de 2026. **La tabla de coordenadas sigue disponible dentro del ZIP oficial de HFCC.** Permite contrastar físicamente los emplazamientos de EiBi antes de asociar una potencia programada. Esta investigación no modificó el servicio, el parser ni los cálculos de RadioWorkbench.

## Fuente accesible y procedencia

La [página operativa A26](https://new.hfcc.org/data/a26/) publica el [paquete oficial a26allx2.zip](https://new.hfcc.org/data/a26/a26allx2.zip), actualizado el 16 de octubre de 2026. Se descargó sin autenticación y se inspeccionaron sus miembros como datos. No se accedió a áreas privadas de HFCC o ITU.

| Elemento descargado | Tamaño | SHA-256 |
|---|---:|---|
| `a26allx2.zip` | 164750 bytes | `07c4eff6d73cdd38f65e7591dc2895fcce1d2c45b09ea571c6af24a2f667350e` |
| Miembro `site.txt` | 37357 bytes | `62339f1db63170d038d0c813f22eb0e2ed5099014f08d5553e062f5a118dde70` |
| Miembro `A26all00.TXT` | 523538 bytes | `0f54e722efcac41e34afb7b5c7ef63269fd3d805674220490dd52e4479024604` |

`site.txt` declara **20-May-2026 SITE.TXT REFERENCE TABLE** y contiene 700 códigos distintos; las 700 filas se pudieron interpretar. Es la versión incluida en el paquete operativo consultado, no una afirmación de que sea la revisión global más reciente de toda la base ITU. El horario contiene 3388 filas de requisitos. El [resumen reproducible](validation/hfcc-source-audit-0.10.json) conserva estas identidades, ejemplos y límites.

El enlace antiguo a `www.itu.int/ITU-R/terrestrial/broadcast/hf/refdata/reftables/site.txt` ya no fue utilizable en esta investigación. El enlace actual de tablas desde HFCC dirige a [eHFBC de ITU](https://www.itu.int/ITU-R/eTerrestrial/eBroadcasting/eHFBC); su respuesta consultada mostró pantallas de sesión/error y no entregó una tabla descargable. El ZIP público de HFCC evita depender de ese enlace roto.

## Defecto concreto en la lectura del ZIP

El nombre del ZIP es `a26allx2.zip`, pero su miembro de horario actual se llama **`A26all00.TXT`**. También contiene `admin.txt`, `antenna.txt`, `broadcas.txt`, `fmorg.txt`, `language.txt` y `site.txt`.

La versión inspeccionada de `HFCCScheduleService.scheduleText` buscaba únicamente el nombre `a26allx2.txt`, ignorando mayúsculas. Por tanto, este paquete oficial válido terminaba con un error `cannotFindHost`, aunque la descarga había funcionado.

Corrección propuesta: reconocer por nombre exacto y temporada las variantes conocidas `seasonallx2.txt` y `seasonall00.txt`; rechazar ausencias o selecciones ambiguas. No elegir simplemente el primer `.txt`, porque podría ser una tabla de referencia. Se puede extraer `site.txt` del mismo ZIP y mantener horario/coordenadas de la misma descarga.

## Formato observado de `site.txt`

Los comentarios empiezan por `;`, las filas usan espacios y finales CRLF. El paquete estándar utiliza Latin-1. Las columnas siguientes son **posiciones de byte de base 1**, observadas en la tabla descargada:

| Campo | Columnas / forma |
|---|---|
| Código de emplazamiento | 1–3; recortar espacios, no exigir tres letras: existen códigos con guion o de dos caracteres |
| Nombre | 5–34 |
| Administración | 36–38; recortar espacios; no asumir código ISO de país |
| Latitud | 40–44: `DDNMM` o `DDSMM` |
| Longitud | Desde 46: `DDDEMM` o `DDDWMM`; algunas filas omiten un cero inicial y tienen dos dígitos de grados |

Una expresión que interpreta las 700 filas de esta copia es:

```regex
^(.{3}) (.{30}) (.{3}) (\d{2})([NS])(\d{2})\s+(\d{1,3})([EW])(\d{2})\s*$
```

Convertir grados y minutos como `signo × (grados + minutos/60)`, validar minutos inferiores a 60 y límites ±90/±180. La expresión describe esta copia; un cambio de formato debe producir una advertencia de lectura y conservar la última copia válida. Los códigos nuevos provisionales `SP1`–`SP9` requieren coordenadas proporcionadas aparte según ITU; no asignarles una ubicación supuesta.

En el horario descargado, cuatro filas usan el código **BNA**, ausente de su `site.txt`. La falta de coordenadas debe impedir una asociación física automática para esas filas.

## Cruce físico con la referencia EiBi de RadioWorkbench

Se contrastó la tabla con el `README.TXT` de EiBi ya incluido en el proyecto. Distancias calculadas mediante haversine, radio terrestre 6371 km:

| Clave EiBi | Código HFCC | Emplazamiento | Separación |
|---|---|---|---:|
| `G|w` | WOF | Woofferton | 0 km |
| `CVA|` | SMG | Santa Maria di Galeria | 0 km |
| `USA|o` | RMI | Okeechobee | 0,927 km |
| `F|i` | ISS | Issoudun | 6,592 km |
| `ROU|g` | GAL | Galbeni | 11,579 km |

Las discrepancias no se explican todas por redondeo a minutos. Un umbral de **10 km es una propuesta conservadora**, no una norma ni una validación de ubicación. Con ese criterio, Galbeni debe quedar como discrepancia. No aumentar automáticamente el radio porque los nombres se parecen.

Para una futura asociación automática de potencia:

1. Exigir una ubicación EiBi resuelta por `BroadcastReference.site(for:)`; conservar sin resolver los listados de varios sitios.
2. Resolver el código de cada candidato HFCC en su propia tabla y comparar distancia. No confundir el país de la emisora con el del transmisor de relevo, ni comparar directamente códigos de administración ITU con códigos de país EiBi.
3. Filtrar también frecuencia, intervalo UTC, fechas de operación, días y modulación. La proximidad no identifica por sí sola una transmisión.
4. Aceptar solo una asociación inequívoca. Si quedan varias filas con potencias diferentes, ubicación ausente o calendario incierto, mantener los candidatos para selección explícita.
5. Conservar temporada, fuente, descarga, sitio y fila asociados. Mostrar **potencia programada HFCC**, sin convertirla en potencia real medida ni potencia radiada.

La tolerancia temporal, el radio y las equivalencias de idioma/emisora son decisiones de implementación. No deben transformar silenciosamente un candidato aproximado en un dato comprobado.

## Calendario y potencia: convenciones que deben separarse

La [especificación oficial ITU del archivo HFBC](https://www.itu.int/en/ITU-R/terrestrial/broadcast/HFBC/Documents/File%20format%20for%20submission%20of%20HFBC%20requirements-E.pdf) establece horarios UTC, fechas `DDMMYY`, domingo=1 y sábado=7. El [texto de ayuda de HFCC](https://new.hfcc.org/schedule/help.html) confirma esa numeración.

**EiBi numérico usa lunes=1 en el calendario actual de RadioWorkbench.** No pasar los días HFCC directamente a `BroadcastCalendar.dayMatch`. Por ejemplo, `23456` HFCC representa lunes–viernes y `1` representa domingo. Ambas formas aparecen en la descarga real.

Hay 155 filas cuyo fin horario es anterior al inicio: cruzan medianoche. La implementación debe trabajar con fechas UTC completas y probar el anclaje del día de inicio, la parte posterior a medianoche, los cambios de mes/año y el fin de temporada. Una comparación de cadenas o de minutos sin fecha no basta.

La descarga mezcla fechas finales `241026` y `251026`. El documento consultado especifica el formato y los límites respecto a la temporada, pero no resolvió expresamente la inclusividad del día final ni el anclaje de días para todos los registros nocturnos. No inferir esas reglas únicamente del nombre A26; documentar la política y comprobar los casos de borde antes de usarlos para asociaciones automáticas. Comparar fechas completas evita confundir octubre/marzo o años distintos.

Otros campos que afectan a la interpretación:

- `OLD`, columna 132: la especificación define `1` como información heredada sin actualización. En esta descarga las 3388 filas tienen ese campo vacío; futuras filas antiguas deben conservar esa condición visible.
- La potencia se declara en kW. Para AM/DSB representa **potencia de portadora**; para SSB, **potencia de envolvente de pico**. No son magnitudes intercambiables con ERP/EIRP.
- La especificación obliga a informar `1` para potencias menores de 1 kW. Por ello, una fila con `1 kW` no siempre acredita exactamente 1000 W.
- El acimut se mide desde norte verdadero. El valor cero también se utiliza para antena no direccional; no equivale siempre a un haz apuntando al norte.
- `N` identifica DRM en el formato citado; el código de modulación no determina por sí solo todos sus parámetros de recepción.

## Acceso público y licencia

HFCC ofrece [acceso público a sus bases](https://new.hfcc.org/data/public_access_HFCC_database.phtml), pero las páginas consultadas mantienen un aviso de derechos reservados y no se encontró una licencia abierta explícita que autorizara redistribuir el conjunto completo. «Descarga pública» no significa «dominio público». La opción técnica propuesta es descargar y cachear bajo demanda desde la fuente oficial, con fecha y atribución; una redistribución integral requeriría aclarar sus condiciones.

Se conservaron localmente el ZIP, `site.txt`, el horario y los resultados de análisis. Este informe publica solo identidades y unos pocos ejemplos de comparación, sin incorporar la tabla completa al bundle.
