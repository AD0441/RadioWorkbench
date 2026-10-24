# RadioWorkbench 0.13.0 · escucha, planificación y referencias

## Registrar una escucha

En la ficha de la **Guía de radios**, pulsa **Registrar escucha en biblioteca…**.
Revisa la hora real UTC, emisora, frecuencia, resultado y antena; confirma con
**Guardar escucha**. Puedes registrar **Escuchada**, **No escuchada** o **Dudosa**
sin grabación ni decodificador. Una grabación ya guardada se adjunta por vínculo,
sin duplicar su audio. La biblioteca también permite crear una anotación manual.

La ficha conserva el horario previsto y la temporada de la guía separados de la
observación. Un sitio TX único de EiBi se precarga; si hay varios, se elige uno o
se deja pendiente. Se pueden completar coordenadas manuales. No se deduce la
posición de una emisora a partir del país. Receptor, antena y posición RX quedan
como instantánea histórica. El perfil actual se edita en **Condiciones y
propagación** y se guarda con **Guardar ubicación**.

El índice de biblioteca pasa de esquema 1 a 2 al guardar. Conserva las sesiones,
los archivos originales, SHA-256, ajustes y papelera anteriores. Si existía un
índice de esquema 1, guarda una única copia `library-schema-1-backup.json` antes
de migrarlo. 0.12.1 no entiende el esquema 2: volver a esa versión requiere
restaurar ese índice anterior; las anotaciones nuevas pertenecen a 0.13. Las anotaciones
tienen papelera recuperable; no se elimina permanentemente audio desde la app.
Límites: 1.000 audios y 5.000 anotaciones, índice de 10 MB.

## Mapa de alcance observado

La capa **Escuchas anotadas** usa el mismo historial persistente. Muestra
trayectos de gran círculo **TX → RX**, con distancia y rumbo desde el receptor.
Separa las rutas que cruzan el antimeridiano. Filtra por fechas, horas UTC/local,
banda, modo, antena y origen local/remoto/grabación. Selecciona una ficha para
completar su posición o revisar notas. Las posiciones APRS/ACARS y adaptadores
externos se conservan en otra capa con su procedencia.

El resumen horario cuenta intentos y escuchas. La mayor distancia por rumbo usa
solo éxitos de antena local y los filtros elegidos. No rellena un círculo de
cobertura ni interpreta unos pocos puntos como patrón de radiación. Un intento
fallido no prueba que hubiera emisión. El mapa dibuja hasta 500 trayectos para
mantener acotada la presentación.

## Escucha HF y enlace bilateral

**Escucha de emisoras · RX** muestra coordenadas, horario, sintonía, distancia,
rumbo e iluminación solar aproximada sin pedir potencia. **Planificar escucha**
desde la guía abre este flujo. La **estimación P.533** se activa aparte y exige
potencia remota conocida o supuesto elegido explícitamente, ganancias, ruido,
ancho equivalente, SNR y R12. Una asignación HFCC no confirma potencia radiada.
Fuera de 1,6–30 MHz se puede usar la ficha y el registro, sin estimación P.533.

**Enlace entre estaciones · TX/RX** calcula **A → B** y **B → A**. Cada sentido
tiene potencia, ganancias TX/RX, ancho, ruido y SNR propios. La dirección con
menor BCR mensual orienta sobre el límite; las disponibilidades no se multiplican
como probabilidades independientes de contacto. Cambiar de flujo conserva sus
supuestos por separado. Los resultados anteriores se identifican al cambiar
parámetros. Copiar incluye los dos sentidos. Se puede vincular una instantánea
de P.533 vigente al registrar desde la emisora o el planificador.

## Voz digital

Pantalla específica con protocolo, dispositivo/TCP y canal, acciones, actividad
DMR por intervalo, salida de voz, WAV y registro plegable. Preparación SDR y
TS1/TS2/ambos se eligen antes de iniciar. El gráfico DSD ya no muestra un tono
central que el motor no utiliza. Los perfiles distinguen protocolos de canal
6,25/12,5 kHz y audio de discriminador mono 48 kHz, sin cambiar por sí solos el SDR
ni la conexión TCP. Las fuentes primarias están enlazadas en cada perfil.

**Ejemplo M17 de datos…** confirma el cambio a M17; no se presenta como una
conversación DMR. El WAV conserva el protocolo usado al crearlo aunque después
se cambie el selector. Se mantiene la cola de voz acotada y la visualización
independiente de 0.12.1. DSD-neo oficial sigue siendo opcional y requiere macOS 26.
Dos llamadas simultáneas identificadas, inteligibilidad y recepción física
siguen pendientes; una tarjeta de sincronía no garantiza voz comprensible.

## Satélites en la próxima hora

**Buscar pases en la próxima hora** revisa el catálogo disponible, con límite de
512 satélites y cancelación. Incluye pases en curso y los que terminan después
de la ventana, conservando AOS/LOS con margen orbital. Permite elegir bajada o
baliza publicada y utiliza esa frecuencia en Doppler/mapa, sin 145,8 MHz fijo.
Los reportes AMSAT se filtran por su edad también sin conexión.

La favorabilidad es un índice explicable de geometría/duración y antigüedad
orbital, **no un porcentaje de éxito**. Equipo, antena, actividad del transmisor,
terreno y condiciones pueden cambiar el resultado. El modelo usa SGP4/SDP4,
WGS84 y horizonte geométrico ideal. No calcula visibilidad óptica ni montañas.
Pases muy largos con cruces no encontrados dentro del margen quedan señalados.

## Taller y ficha SDR común

El taller reúne **74 referencias** existentes del proyecto: CW, RTTY/ASCII,
BPSK31, DTMF, CTCSS, NAVTEX, APRS, tres POCSAG, Selcall, FT8/FT4, ALE, WEFAX,
APT histórico, ACARS, M17 de datos, seis MT63, cinco Hell, dos DSC y **41 SSTV**.
Identifica ajustes y resultado esperado. Permite elegir una grabación propia
como referencia y conservar su canal, sin atribuirle el protocolo de laboratorio.

Espectro y waterfall se calculan desde el WAV, hasta 12 segundos, 256 columnas y
96 filas, con cancelación y memoria acotada. Son ejes de **audio demodulado** y
dBFS, no espectro RF/IQ ni potencia recibida. La resolución FFT depende del
muestreo. No se guarda una imagen por intento ni se añade un clasificador.

El inspector derecho muestra demodulación SDR, modulación de señal, filtro RF
inicial, audio que conservar, canal y recomendaciones. Ofrece variante HF/VHF
para SSTV y perfiles según variante/protocolo. Aplicar prepara la app mediante
acción explícita; la sintonía del SDR sigue siendo manual o por Rigctl optativo.
Las referencias se generan a demanda y se pueden abrir en el taller.

Artemis se estudió como referencia funcional y se enlaza como catálogo externo.
No se redistribuyen sus 423 imágenes ni 402 sonidos. Las fichas sin muestra
verificada lo indican; una ficha tampoco añade un motor pendiente.

## Validación y entrega

Los resultados de pruebas, paquete y revisión de interfaz se registran al cerrar
la entrega en [VALIDACION.md](VALIDACION.md). Las pruebas físicas SDR++/VB-Cable
permanecen aplazadas. Se conserva solo la entrega actual y la anterior.
