# Validación de RadioWorkbench 0.15.0

Suite Release arm64: **281 funciones registradas, 275 aprobadas, seis opcionales omitidas y cero fallos**, 7,942 s tras compilar. Pasaron además **21 controles C HF**. Las omisiones siguen siendo tres contrastes DMR con corpus temporal independiente, dos pruebas de red real y el benchmark visual opcional; no se repitió recepción física.

Las pruebas nuevas verifican importación/exportación SigMF sin alterar el original, conservación de anotaciones y muestras, papelera/restauración, SHA-512 y rollback al fallar, rechazo de enlaces y diseños no admitidos, índice corrupto preservado y preparación SatDump sin iniciar proceso. La comparación A/B sobre el mismo AX.25 recupera una trama con el centro correcto y ninguna con el incorrecto; también cubre cancelación y modos excluidos. La configuración de actualización rechaza HTTP, credenciales en URL y claves inválidas.

El canal inicial Sparkle 2.10.0 está publicado por HTTPS en la rama `updates`. Se descargó, comparó con el original y verificó su firma; una copia alterada fue rechazada. El canal no ofrece paquetes y no se presenta como validada una actualización entre dos versiones publicadas. La clave privada permanece fuera de Git y del bundle.

ZIP 0.15.0/build 31 extraído: integridad y firma estricta correctas, **18 objetos Mach-O con arm64** (13 propios arm64 y cinco componentes universales de Sparkle), sin dependencias del checkout/Homebrew/Testing ni rutas del compilador; **78 WAV idénticos** a los fixtures. SHA-256: `a3da7731ecc7cf7fd6e7f7b4cdfbf27b0174e5202b0cc68b25fd0c23eb49d8c6`.

Se sustituyó `/Applications/RadioWorkbench.app` y se compararon los archivos con el paquete verificado. **2.258 archivos existentes de datos y preferencias conservaron su contenido durante la copia**. Se conserva la entrega actual y el ZIP previo 0.14.0.

**Interfaz parcial:** se observó la app instalada, el paso de fuente/perfil del asistente, la biblioteca de audio y la sección SigMF. Al abrir el taller se cerró la conexión de la herramienta de pantalla; reconectar y reiniciar su sesión no la recuperó. RadioWorkbench siguió activa y no apareció un informe nuevo de cierre. No se observaron el resultado A/B ni el diálogo Sparkle; no se inició micrófono ni reproducción. Sus pruebas de código no sustituyen esa comprobación visual pendiente.

El README principal contiene español e inglés, el botón Ko-fi y el agradecimiento solicitado a G4ZJH. La traducción completa de la interfaz continúa pendiente. Las tres skills instaladas pasaron la validación de estructura y se retiró una copia anidada duplicada de Swift Testing Pro.

[Resumen único](validation/release-0.15.0.json) · [Uso y límites](RELEASE-0.15.0.md).

# Validación de RadioWorkbench 0.14.0

Suite Release arm64: **273 funciones registradas, 267 aprobadas, seis opcionales
omitidas y cero fallos**, 7,802 s después de compilar; además, 21 controles C HF.
Las omisiones corresponden al corpus temporal DMR independiente, red real de
satélites/terreno y benchmark visual opcional. No se repitió recepción física.

SITOR-A y DGPS pasan por el worker normal de WAV, entrada abierta y selección
de canal estéreo a 48 kHz. SITOR-A verifica cadencia, retorno, retransmisiones,
alfabeto, ruido y rechazos. DGPS recupera 131 tramas del vector GPSD independiente
con ambas polaridades y contrasta sus correcciones; audio sintético a
8/44,1/48/96 kHz y WAV con ruido/deriva/paridad dañada. FLEX verifica cuatro
variantes, fases, polaridad, corrección/rechazo, JSON y publicación antes de EOF.
Los generadores, manifiestos y licencias están junto a las pruebas.

La suite detectó y permitió corregir la retención del último texto cuando una
entrada abierta pausa el audio antes del siguiente refresco. También cubre la
frecuencia de audio residual en modos de discriminador, regreso a NXDN48,
conservación de fase/retardo del FIR vectorizado, muestras no finitas, copia
atómica de grabaciones y cierre del proceso propio si ignora SIGTERM. Se
conservan las regresiones CW, imágenes/SSTV, HF, terreno, biblioteca y TCP.

El ZIP 0.14.0/build 30 extraído pasó integridad y firma estricta: **13 objetos
Mach-O arm64**, sin enlaces al checkout/Homebrew/Testing, y **78 WAV idénticos** a
los fixtures. SHA-256: `8af1234af3d92a4a3b2657b7ef870e5c1a6579cc6ac02cfeeb09abcea5e9fb99`.
Se sustituyó `/Applications/RadioWorkbench.app`, verificando hashes y firma;
367 archivos existentes de preferencias/datos conservaron su contenido durante
la copia. Se conserva el ZIP anterior 0.13.0 junto a la entrega actual; se retiraron la caché de compilación y las extracciones temporales.

**Interfaz pendiente:** el Mac estaba bloqueado en ambas comprobaciones; no se
presenta como observada la ejecución visual de los nuevos modos. No se inició
micrófono, reproducción, SDR ni sintonía. SITOR-A/FLEX necesitan una grabación
RF independiente y DGPS no se ha probado con una baliza real. LORAN-C y Globe
Wireless siguen deshabilitados.

[Resumen único de entrega](validation/release-0.14.0.json) · [Uso y fuentes](RELEASE-0.14.0.md).

# Validación de RadioWorkbench 0.13.0

Suite Release arm64: **240 funciones registradas, 234 aprobadas y seis opcionales
omitidas, cero fallos**, 7,795 s después de compilar. Pasaron además 21 controles C
HF. Las omisiones son tres pruebas con corpus DMR independiente temporal, dos
pruebas con red (satélites/terreno) y el benchmark visual optativo. No se repitió
la evaluación de voz DMR independiente de 0.12 ni la recepción física.

La ampliación comprueba migración del índice v1 con copia única del original y
conservación del audio/SHA, anotaciones sin audio, actualizaciones inválidas,
papelera, filtros de medianoche y zona horaria, geodésicas por el Pacífico,
parámetros separados RX/TX y enlace bilateral, copia del regreso y utilitarias
sin ancho conocido. También prueba límites AOS/LOS, Doppler/bajadas publicadas,
reportes vencidos offline, perfiles de voz por protocolo, las 74 referencias y
sus ajustes, espectrograma acotado, canal/fase, cancelación y números extremos.
Se conservan las regresiones CW, SSTV, POCSAG, TCP, Rigctl, ITM y grafo de voz offline.

El paquete ZIP extraído pasó firma estricta y 13 objetos Mach-O arm64; sus 75
WAV coinciden con los fixtures del proyecto. El 25 de octubre se instaló en
`/Applications/RadioWorkbench.app` (0.13.0/build 29), con verificación de firma y
hashes y sin alterar las preferencias/recepciones existentes antes de abrir.
Se observó la app instalada, SSTV con inspector, la guía, la ficha BBC 9410 kHz
y el formulario de escucha con audio opcional; se canceló sin guardar.

Al abrir HF falló la conexión de Sky Computer Use; RadioWorkbench continuó activa.
El recorrido visual de HF, DMR, pases y taller/mapa queda parcial. EiBi conservó
A26 tras un error de actualización, con aviso de temporada visible; HFCC B26 sí
estaba disponible. No se iniciaron micrófono, SDR ni reproducción. Se conservaron
solo la entrega actual y el ZIP anterior y se retiró la caché temporal de compilación.

[Resumen de entrega](validation/release-0.13.0.json) · [Uso y límites](RELEASE-0.13.0.md).

# Validación de RadioWorkbench 0.12.1

Suite Release arm64: **218 funciones registradas, 216 aprobadas, dos opcionales
omitidas y cero fallos**, 14,531 s una vez compilada. Se habilitó la medición de
entrada sintética; las omisiones siguen siendo satélites y terreno con red.
Se conservan las comprobaciones DMR independientes y del grafo de salida offline.

La regresión visual verifica historial de 2048 muestras con paquetes pequeños,
sondeos vacíos, pausas/reinicio, límite de frecuencia, cola con el cuadro más
reciente, rechazo de una sesión anterior, colores/orden del raster y snapshots
inmutables. La comparación aislada de entrada DMR sintética a velocidad real
pasó de 10 a 59 cuadros en 3,072 s (3,26 → 19,21 actualizaciones/s), sin pérdida
de muestras. El raster pasó de 104 a 4,7 µs de media. No mide FPS de pantalla,
latencia RF a voz ni la recepción física del usuario. La captura del proceso
existente estaba inactiva y no se usa como perfil de carga en vivo.

[Suite](validation/release-0.12.1-tests.txt) ·
[Resumen](validation/tests-0.12.1-summary.json) ·
[Mediciones y reproducción](RELEASE-0.12.1.md).

El ZIP 0.12.1/build 28 extraído pasó integridad y firma estricta; los 13 binarios
son arm64, sin dependencias del checkout o Homebrew. La app se abrió por separado
en CW; tras desplazar la barra lateral, captura y lectura de interfaz fallaron
por timeout. Su proceso continuó activo. La presentación del waterfall con la
entrada real sigue pendiente. [Paquete](validation/package-0.12.1.json) ·
[Revisión visual parcial](validation/ui-0.12.1.json).

# Validación de RadioWorkbench 0.12.0

Suite Release arm64: **212 funciones registradas, 210 aprobadas, dos opcionales
omitidas y cero fallos**, 13,572 s una vez compilada. Esta pasada sí incluye el
runtime oficial DSD-neo y el corpus independiente DMR; se omiten descarga de
satélites en vivo y benchmark de terreno en red. Se conservan los casos HF,
relieve, biblioteca, DSC, imágenes, TCP y Rigctl de la versión anterior.

DMR verifica PCM estéreo fragmentado, perfiles anteriores, máscara de síntesis
TS1/TS2, parser con ANSI y errores, voz antes de EOF, cierre de entrada y WAV,
cancelación sin EOF y cierre forzado de un proceso propio que ignora SIGTERM.
El grafo AVAudioEngine se renderiza offline y se comprueba su límite de audio
pendiente sin usar altavoces ni micrófono. Se corrigió una espera repetida al
finalizar el motor y la espera del cierre queda fuera de la interfaz.

El corpus externo confirma TS1, emisor 3025209, destino 9990 y llamada privada.
CC7 es una observación del motor, sin oráculo independiente para ese campo.
No se verificaron dos conversaciones simultáneas ni calidad perceptual. El
audio externo se mantiene temporalmente y no se incluye en Git o en el paquete.

Guía → HF: selección, ficha y botón de envío observados en 0.11; el usuario
confirmó posteriormente BBC, 9,410 MHz y dirección Escucha. Esta confirmación
es del usuario y no una captura de pantalla automatizada. La revisión visual
de los otros flujos se registra por separado, sin sustituirla por los tests.

[Suite completa](validation/release-0.12.0-tests.txt) ·
[Resumen](validation/tests-0.12.0-summary.json) ·
[Contrato independiente](validation/dmr-0.12-contract.md) · [Uso DMR](DMR-0.12.md).

El paquete 0.12.0/build 27 extraído pasó integridad ZIP y firma ad hoc estricta;
sus ejecutables son arm64, sin dependencias Homebrew o del checkout. La nueva
app abrió en CW. SkyComputerUseService volvió a cerrarse al intentar cambiar
a DSC y al reconectar; RadioWorkbench permaneció activa, sin un nuevo informe
de cierre. El panel DMR y los otros flujos no se presentan como observados en
la interfaz por esta pasada. [Verificación de paquete](validation/package-0.12.0.json) ·
[Límite de revisión visual](validation/ui-0.12.0.json).

# Validación de RadioWorkbench 0.11.0

Suite Release arm64: **202 funciones registradas, 198 aprobadas y cuatro opcionales omitidas**, cero fallos, 7,438 s una vez compilada. Las omisiones son dos pruebas que requieren el runtime DSD instalado, descarga satelital en vivo y el benchmark de terreno en red. No se inició micrófono, SDR++ ni sintonía del receptor físico.

Se verificaron biblioteca/SHA-256/papelera, calidad PCM, fragmentación y EOF TCP, cierre concurrente sin perder el último bloque, servidores Rigctl simulados (incluido éxito sin sintonizar y cancelación), DSC con ECC y exportación de símbolos, mapa/eventos con fechas y trazas, SatDump aislado con importación y cancelación, y referencias del taller. La revisión HF incorpora 21 comprobaciones C y conserva la referencia pública y las escalas de potencia/ancho. DSC pasó 18 comprobaciones aisladas, repetidas con ASan/UBSan y muestras públicas identificadas.

[Suite](validation/release-0.11.0-tests.txt) · [Resumen](validation/tests-0.11.0-summary.json) · [HF](validation/hf-review-0.10-tests.txt) · [DSC](validation/dsc-prototype-0.10.json) · [Sanitizadores DSC](validation/dsc-sanitizers-0.10.json) · [SatDump real con I/Q cero](validation/satdump-offline-0.11.json) · [Límites](NUEVE-MEJORAS.md).

La prueba física SDR++ → VB-Cable y una captura LRPT independiente siguen pendientes. El procesamiento real de I/Q cero produjo descriptores vacíos y ninguna imagen; no se interpreta como recepción. La firma es local ad hoc, sin notarización. El [paquete 0.11.0](validation/package-0.11.0.json) extraído pasó integridad y firma estricta; sus ejecutables son arm64 y los ejemplos DSC/MT63/ALE decodificaron con los helpers distribuidos. ZIP: 190.779.871 bytes, SHA-256 `ab2a4b05a0324a2112e671c88ab1f5c6e066b2086f1ebe90c535b0432e420961`.

Con el Mac desbloqueado, la interfaz 0.11.0 mostró las nuevas entradas de navegación, el selector de dispositivo/TCP, los parámetros explícitos de TCP y el diagnóstico desplegado. No se inició la conexión. Al cambiar a DSC se cerró SkyComputerUseService, con `EXC_BREAKPOINT / SIGTRAP` en `Array.remove(at:)`; el servicio volvió a fallar tras reiniciar la sesión de control. RadioWorkbench seguía en ejecución y no apareció un nuevo informe de cierre de la app. La transferencia Guía → HF y los demás flujos interactivos no se presentan como comprobados en esta pasada; sus pruebas automatizadas sí están incluidas en la suite indicada. [Registro de interfaz parcial](validation/ui-0.11.0.json).

# Validación de RadioWorkbench 0.8.11

## 0.10.0

La suite release registra **159 funciones: 155 aprobadas y cuatro opcionales omitidas**, ejecución 7,618 s. Se omitieron las dos pruebas de DSD que exigen su runtime externo y dos comprobaciones de red/terreno real. No hubo fallos. [Salida completa](validation/release-0.10.0-tests.txt) · [Resumen](validation/tests-0.10.0-summary.json).

La ampliación verifica las seis variantes MT63; ALE 2G con modulador aritmético independiente, AMD y sondeos; silencio, ruido y floats no finitos; publicación con stdin abierto; enrutamiento del worker, remuestreo de WAV estéreo a 48 kHz con el canal derecho seleccionado, recepción simulada en vivo y persistencia de ajustes anteriores. Un caso comprueba que la guía RF MT63 conserve el bloque al desplazar su centro.

Las comprobaciones nativas de MT63 añaden ruido a 12 dB en los seis modos, 60 s de silencio/ruido, entradas fragmentadas, escape JSON, argumentos inválidos y ASan/UBSan en TX/RX y doce centros extremos. Corrigen fallos heredados de asignación y de índice FFT. [Resultados](../Vendor/MT63/validation-summary.json) · [Cambios](../Vendor/MT63/LOCAL-CHANGES.md). Los fixtures usan TX/RX del mismo upstream: falta una grabación MT63 independiente.

ALE se contrastó además con dos AU públicos del repositorio KiwiSDR, identificados por SHA-256 y conservados solo para comprobación local; recupera XSS y el AMD de referencia. [Once comprobaciones nativas y procedencia](validation/ale2g-0.10.json). El caso sintético con +25 Hz y ruido recupera AMD completo; +65 Hz no garantiza el mensaje. Se documenta la sensibilidad limitada en lugar de generalizarla.

Una ejecución inicial dentro del aislamiento del agente quedó esperando la enumeración de formatos de AudioToolbox. La muestra del proceso localizó esa espera; se detuvieron únicamente los procesos de esa prueba y se repitió la suite con acceso al servicio de audio de macOS. Esa repetición es la pasada indicada arriba. No fue una caída de RadioWorkbench.

No se realizó captura de micrófono ni prueba física de SDR++/VB-Cable en esta ampliación. La inspección REA de las cinco aplicaciones fue estática: [cobertura, identidades y límites](REVISION-APPS-0.10.md).

## 0.9.0

148 pruebas registradas, 146 aprobadas y dos opcionales de red omitidas en la pasada Release. Nuevas pruebas: FT8/FT4 por WAV y silencio, CW automático/neuronal con tono/velocidad apartados de valores iniciales y publicación en vivo, ADS-C/CPDLC y CRC interno, bloques ACARS en FIFO bajo acumulación, exportación, M17 SMS/Codec2 WAV, referencia SGP4 de Vallado y actualización de caché sin BSTAR. La comparación con seis WAV públicos FT8 recupera 53 mensajes; se conservan también los no recuperados en [ft8-independent-0.9.json](validation/ft8-independent-0.9.json). No certifica todos los protocolos DSD ni sustituye pruebas RF. No se usó micrófono o SDR++ en esta actualización.

Release arm64/macOS 14+, build 23. Se reprodujeron los dos defectos revisados con **Avisos sin texto**: un aviso a 1200 baud para capcode 123456 seguido de dos segundos de silencio producía 75 registros, 74 falsos; la salida breve no era legible mientras stdin seguía abierto. Con el parche del sincronismo periódico, el mismo audio produce **un registro legítimo y cero falsos**. El aviso JSON se puede leer con stdin abierto y queda recibido antes de terminar el helper con SIGTERM.

La corrección combina tres etapas: `fflush` en el aviso sin texto, lectura del Pipe mediante los bytes disponibles y publicación de resultados asíncronos aunque se haya agotado el último bloque de audio. El sincronismo se exige después de 16 palabras, reiniciando el framing al adquirirlo y respetando el límite BCH configurado. No se filtran direcciones bajas: un capcode real 0 conserva su recepción.

Se añadieron siete funciones con 25 casos, incluyendo 48 comprobaciones de aviso+silencio que cubren tres tasas, ambas polaridades y ocho frames de capcode. También cubren sincronismo ausente/sustituido por idle, recuperación con cambio de fase, mensajes multibloque, errores corregibles/no permitidos, publicación antes de EOF/cancelación y monitor en vivo/WAV a 48 kHz. La suite Release final registró **135 funciones: 133 ejecutadas y aprobadas; dos opcionales omitidas**, en 6,364 s. La prueba de 48 kHz tolera la espera del ejecutor durante la suite DSP completa; la condición sigue siendo recibir el aviso con la entrada abierta, antes de cancelar. No se utilizó micrófono, SDR++ ni una grabación de tráfico real.

Las modificaciones de multimon-ng se identifican con fecha en `pocsag.c`, un aviso local y hashes upstream/distribuidos en el manifiesto. [Cambios del componente](../Vendor/MultimonNG/LOCAL-CHANGES.md).

El ZIP 0.8.11/build 23 extraído pasó integridad y firma estricta; todos sus binarios son arm64. Se ejecutó la misma reproducción contra el helper extraído del ZIP: un aviso, cero falsos, lectura antes de EOF y evento recibido antes de SIGTERM. El archivo de fuentes del bundle contiene exactamente el `pocsag.c` parcheado, manifiesto y aviso local. Firma ad hoc, sin notarización. SHA-256 de `RadioWorkbench-0.8.11-macos-arm64.zip`: `cb9933beaeba800d8a3ddb49d5bdf1a1a84836268e9723814fbce6e870cadbe0`.

[Pruebas completas](validation/release-0.8.11-tests.txt) · [Resumen](validation/tests-0.8.11-summary.json) · [Reproducción antes/después](validation/pocsag-regressions-0.8.11.json) · [Paquete](validation/package-0.8.11.json) · [Notas 0.8.11](RELEASE-0.8.11.md).

# Validación de RadioWorkbench 0.8.10

Release arm64/macOS 14+, build 22. La suite ordinaria registró **128 funciones: 126 ejecutadas y aprobadas; dos opcionales omitidas**, en 5,502 s una vez compilada. Las nuevas pruebas cubren tres tasas POCSAG, ambas polaridades, BCH con errores, ocho familias Selcall, ASCII 7/8, cinco variantes Hell, datos malformados, cancelación, perfiles anteriores y el pipeline WAV→worker→helper. Se inspeccionaron los cinco PNG «CQ» generados por el decodificador Hell nativo; el error medio contra patrones del transmisor fue aproximadamente 17–18 niveles de 255.

Los tests satelitales verifican épocas GP UTC sin Z, fracciones de segundo, checksum TLE, NORAD, fechas AMSAT, actualización parcial, error de certificado sin pérdida de órbitas, persistencia precisa de épocas y consistencia entre trayectoria terrestre/azimut/elevación. Una prueba separada con URLSession real descargó **97 satélites, 402 registros de frecuencias y 500 reportes**. CelesTrak agotó su espera en el primer intento; AMSAT TLE completó las órbitas. Una actualización posterior con AMSAT preferido pasó en 1,431 s, sin errores por fuente y sin desactivar TLS.

El ZIP final extraído pasó integridad y `codesign --verify --deep --strict`. Todos sus ejecutables y bibliotecas son arm64, incluido multimon-helper. Contiene las fuentes, script y licencia de multimon-ng. Versión 0.8.10/build 22; firma ad hoc, sin notarización. SHA-256 de `RadioWorkbench-0.8.10-macos-arm64.zip`: `4794f84c8c0e1973cd49b9f9fad7e7a0f9b0a2377ad78c29fd5983a4713ba966`.

La app abrió y se pudo inspeccionar su árbol de accesibilidad: nuevos modos disponibles y selector de entrada/canal presentes. El control CUA volvió a desconectar el canal nativo al entrar a Consultas, incluso después de reconectarse; la revisión visual interactiva de los mapas queda pendiente. No se hizo una prueba SDR++ → VB-Cable ni recepción RF de los nuevos modos. Los cálculos y las descargas se comprobaron independientemente de ese bloqueo de la herramienta.

[Pruebas](validation/release-0.8.10-tests.txt) · [Resumen](validation/tests-0.8.10-summary.json) · [Descarga real](validation/satellites-live-0.8.10.json) · [Paquete](validation/package-0.8.10.json) · [Modos y parámetros](DECODIFICADORES-0.8.10.md) · [Consultas](CONSULTAS.md).

# Validación de RadioWorkbench 0.8.9

Release arm64/macOS 14+, build 21. La cobertura VHF/UHF pasa de una envolvente radial a enlaces ITM independientes por celda, con DEM Mapzen/Terrarium, alturas AGL y terreno AMSL, cancelación, caché y avisos válidos del modelo. El horizonte de Tierra lisa es opcional y usa AGL; elegir RX conserva el área.

`bash script/test.sh --configuration release` terminó con 110 funciones registradas: **109 aprobaron** y el benchmark geográfico quedó omitido por defecto. Ese benchmark pasó por separado con 36 teselas reales de Santiago: 13.098 celdas modeladas, 4.841 sobre −110 dBm y 7.498 con avisos NTIA, en 6,35 s incluyendo descarga/cálculo en esta ejecución. Los cinco perfiles oficiales NTIA coinciden a menos de 0,01 dB. La prueba de cresta sintética arroja 48,37 dB de diferencia frente al lado despejado. El renderizador MapKit se verifica fuera de pantalla: norte arriba y huecos transparentes.

El ZIP extraído pasó verificación estricta de firma e integridad y todos los ejecutables/bibliotecas son arm64, incluida `libitm.dylib`. Versión 0.8.9/build 21; firma ad hoc, sin notarización. SHA-256 de `RadioWorkbench-0.8.9-macos-arm64.zip`: `fcaa8f9a34f6cbf0dd7bcb5a30a6eaec2d5483ead85e7c0c083a9042fbc22dc5`.

La app abrió y permaneció activa sin un nuevo informe de cierre. CUA desconectó su canal nativo antes de inspeccionar el mapa, también después de reconectarse: la revisión visual interactiva queda pendiente. La figura científica es una simulación con coordenadas públicas, no una captura de Apple Maps ni una recepción RF medida. No se hizo la prueba SDR++ → VB-Cable.

[Pruebas](validation/release-0.8.9-tests.txt) · [Paquete](validation/package-0.8.9.json) · [Método, fuentes y figura](TERRAIN-COVERAGE.md).

# Validación de RadioWorkbench 0.8.8

Release arm64/macOS 14+, build 20. Se corrigió el cierre reportado al editar el indicativo en APRS: el `didSet` de 0.8.7 volvía a escribir la propiedad `@Observable` en cada cambio y causaba recursión hasta agotar la pila. La propiedad ahora enlaza con almacenamiento separado y normaliza una sola vez. Una regresión asigna fragmentos sucesivos como lo hace el campo SwiftUI y confirma persistencia en mayúsculas sin reentrancia. `bash script/test.sh` aprobó **99 pruebas**. `bash script/build_and_run.sh --build-only` compiló Release; el ZIP extraído en `/private/tmp` pasó `codesign --verify --deep --strict`, contiene un ejecutable Mach-O arm64 e identifica versión 0.8.8/build 20. El archivo pasó `unzip -t`. SHA-256 de `RadioWorkbench-arm64.zip`: `d01d190fa4595f7cb26a4797f8e3fba980f14e0b9ccd407ed64c822d22c71cb8`.

# Validación de RadioWorkbench 0.8.7

Release arm64/macOS 14+, build 19. `bash script/test.sh` aprobó **98 pruebas**, incluida la validación de posiciones APRS comprimidas/no comprimidas y el rechazo de coordenadas inválidas. Las pruebas nuevas cubren asignaciones SUBTEL, normalización de repetidoras, minimización de datos personales y cálculo aproximado de pases; la suite completa también pasó los fixtures de SSTV, APT y WEFAX. `bash script/build_and_run.sh --build-only` compiló la app Release. El ZIP extraído en `/private/tmp` pasó `codesign --verify --deep --strict`; su ejecutable principal es Mach-O arm64 y el Info.plist informa versión 0.8.7/build 19. SHA-256 de `RadioWorkbench-arm64.zip`: `c27c0d61c0734c3158138e8145d5fe43b53eb978bb84e7068b8de106fbd6d058`. El ZIP también pasó `unzip -t`.

La carpeta `.app` publicada dentro de `dist` recibe `com.apple.FinderInfo` del contenedor Desktop/File Provider y falla la verificación estricta directa por ese atributo; la copia limpia extraída del ZIP sí se verifica y es el paquete distribuible. Los límites funcionales y las fuentes de Consultas están en [CONSULTAS.md](CONSULTAS.md). Los pases orbitales son aproximados (Kepler+J2, no SGP4), APRS-IS solo recibe y comparte un filtro geográfico redondeado, y SDR++ se sintoniza manualmente.

# Validación de RadioWorkbench 0.8.6

Release arm64/macOS 14+, build 18. `bash script/test.sh` aprobó **93 pruebas**. Las cinco pruebas de terreno se repitieron sobre la fuente final y pasaron: perfil ~500 m, suma AMSL+AGL, obstrucción por cresta, corredor Fresnel y geometría de 32 rumbos. En un perfil ITM sintético de 10 km, la cresta elevó la pérdida de **104,28 a 135,69 dB** (+31,41 dB) frente al mismo perfil plano. `bash script/build_and_run.sh --build-only` compiló el bundle arm64; versión 0.8.6/build 18. El ZIP extraído pasó `codesign --verify --deep --strict`, y tanto la app como `itm-helper` son Mach-O arm64. SHA-256 del ZIP: `07bf4b111a78ce4d9c61e978100d31b7db1baa6f25f566a9c0d733474c1985d9`. No se consultó un trayecto real a Open-Meteo ni se inspeccionó el mapa en una ubicación de prueba; la verificación topográfica es sintética.

## Validación de RadioWorkbench 0.8.5

Release arm64/macOS 14+, build 17. `bash script/test.sh --configuration release` aprobó **92 pruebas**, incluidas sus variantes parametrizadas, en arm64. Las pruebas nuevas validan el corredor Fresnel y la envolvente de 16 rumbos; el build release compiló también el selector cartográfico y el cálculo ITM de alcance con umbral configurable.

El bundle release se compiló, firmó localmente y verificó con `codesign --verify --deep --strict`; también pasó el ZIP extraído. La app y el helper ITM son arm64, versión 0.8.5, build 17. SHA-256 del ZIP: `4e3783e00b23410eef9d2572697883fff472145d029a42785235f6c5719dcb63`. No se abrió una sesión RBN ni se enviaron coordenadas reales a Open-Meteo; tampoco se probó la entrada SDR++/audio ni se hizo inspección visual de Apple Maps en vivo.

## Validación de RadioWorkbench 0.8.4

Release arm64/macOS 14+, build 16. `bash script/test.sh --configuration release` aprobó **91 pruebas**, incluidas sus variantes parametrizadas, en arm64. La prueba nueva valida la geometría del corredor Fresnel según trayectoria y frecuencia; se cubren perfiles DEM, entradas ITM, fuentes y decodificadores. El mapa se compiló con selección por clic y estilo topográfico realista de MapKit. La app arm64 firmada localmente, versión 0.8.4/build 16, pasó `codesign --verify --deep --strict` al extraer el ZIP. SHA-256: `9e50368686832d092bcd3cf238d3233db93985552e6add832408318803693216`.

## Validación de RadioWorkbench 0.8.3

Release arm64/macOS 14+, build 15. `bash script/test.sh --configuration release` aprobó **90 pruebas**, incluidas sus variantes parametrizadas, en arm64. Las nuevas verificaciones cubren parsing del protocolo RBN y negociación Telnet, centros Maidenhead, consulta y validación de perfiles DEM, entradas ITM, pronóstico NOAA de tres días y programación del próximo inicio EiBi. La suite también recompila los helpers previos de ACARS y P.533/P.372. El helper NTIA ITM se compiló por separado para arm64 y una ruta plana de referencia de 2 km devolvió pérdida finita de 103,92 dB, potencia recibida de −63,92 dBm a 10 W, modo de visibilidad y cero flags.

El bundle release de 0.8.3 es arm64, build 15. SHA-256: `b0c7d8dd45374548f4c74d59942f24de544c21441988b87de7aead5a8c662d34`. La validación de fuentes no abrió una sesión RBN ni envió coordenadas reales a Open-Meteo; tampoco probó la entrada SDR++/audio.

Release arm64/macOS 14+, build 14. La suite completa `bash script/test.sh` terminó correctamente en arm64: **84 funciones de prueba** aprobaron en 230,482 s. Se incluyen pruebas para el parser fijo HFCC, rechazo de asociaciones ambiguas, celdas Maidenhead, XML y cadencia de PSK Reporter, y datos geográficos/confianza de ionosondas. Se compilaron los helpers nativos de ACARS y propagación durante la ejecución. Después de limitar la extracción ZIP por streaming, los seis tests de fuentes de radio se repitieron y pasaron. La app release también compiló en arm64; el ZIP extraído en `/tmp` pasó `codesign --verify --deep --strict` y su `Info.plist` identifica la versión 0.8.2, build 14. SHA-256: `8b86249064afe4029341e6b86ba5de3add0ac74c9b0530d4b634777e1194f3a6`.

La guía ahora cruza EiBi con el horario técnico estacional HFCC; el planificador recibe potencia declarada solo si la asociación por frecuencia y horario es inequívoca. La vista de condiciones muestra observaciones de estaciones ionosonda ordenadas por proximidad. PSK Reporter queda apagado hasta el consentimiento del usuario, comparte una cuadrícula Maidenhead de cuatro caracteres y limita los intentos de consulta a cinco minutos, incluso tras fallo o reinicio. Fuentes y límites: [PROPAGACION.md](PROPAGACION.md).

---

# Validación de RadioWorkbench 0.8.1

Release arm64/macOS 14+, build 13. La compilación de producción se completó. El ZIP extraído pasó `codesign --verify --deep --strict` y contiene un ejecutable arm64. SHA-256: `4c417acafdc52399a000228194733a022548b405ac12bb19a93298f4553a6f9e`.

**Regresión Robot36C:** reproduje offline la grabación real del celular con Martin M4 seleccionado, Auto VIS y compatibilidad Robot36C activos. El encabezado VIS 8 ahora se acepta pese a la paridad no estándar, y el decoder identifica Robot 36 por la cabecera y completa **320×240**. El centro y el reloj se calibraron automáticamente a **1899,96 Hz** y **−18.150,84 ppm**, respectivamente, con **192 sincronías** y **0,288 ms** de jitter. Esta reproducción prueba el archivo capturado; la captura en vivo del micrófono no se reinició. [Diagnóstico](validation/sstv-phone-auto-m4-0.8.1.json).

El cambio permite la excepción de paridad VIS solo para código 8 cuando el usuario activa Robot36C y usa Auto VIS o el modo Robot 36 manual. La suite de la validación original no pudo ejecutarse con el toolchain disponible en ese momento.

**Revalidación de fuentes · 14 de octubre de 2026:** se restauró `SSTVNoiseReduction` con sus valores persistidos, se añadieron conformidades `Codable` a los ajustes SSTV y se corrigió la posición del sync periódico Scottie para la calibración automática. `./script/test.sh --configuration release` compiló desde un scratch path vacío y aprobó los **78 tests** en arm64. El script ahora usa `--disable-sandbox`, igual que la compilación de la app, para evitar el fallo de aislamiento de SwiftPM en Command Line Tools. [Registro](validation/release-0.8.1-source-tests.log). Esta comprobación valida fuentes y tests; el ZIP 0.8.1 arriba conserva su propia fecha y hash.

---

# Validación de RadioWorkbench 0.8.0

Incluye calibración automática SSTV del centro y reloj, reducción de impulsos y perfiles persistentes de entrada. Build release arm64/macOS 14+, versión 0.8.0, build 12. La compilación de producción terminó correctamente; no se ejecutó la suite unitaria.

**Reproducción de audio acústico real:** se volvió a decodificar la captura Robot36C del celular hecha con el micrófono del Mac en la versión 0.7.3. La 0.8.0 estimó automáticamente un centro de **1899,96 Hz** y reloj de **−18.150,84 ppm**, con **192 sincronías** y **0,288 ms** de jitter. Sin corrección manual de reloj reconstruyó la imagen completa **320×240**. El modo de reducción fue Equilibrada. La reproducción offline tardó aproximadamente 1,49 s; no equivale a una nueva recepción RF o una segunda captura en vivo. [Diagnóstico JSON](validation/sstv-phone-auto-0.8.0.json), registro de compilación y replay (archivo local no publicado).

Los controles de calibración automática y reducción Equilibrada aparecen en la vista SSTV. Los perfiles persistentes incluyen el micrófono integrado y VB-Cable; se guardan en Application Support, y el primer arranque deja “Ajustes actuales” activo para no cambiar la entrada elegida previamente. La imagen es reconocible y completa, aunque conserva ruido e interferencias acústicas; la reducción Equilibrada es conservadora para no borrar detalle. El ZIP extraído pasó `codesign --verify --deep --strict`; el ejecutable del bundle es arm64. SHA-256: `dcd2cc03b00a71cbfe03630d614f52cbc3c9c790a6998a2e395075a243638b87`.

---

# Validación de RadioWorkbench 0.7.3

Release arm64/macOS 14+, build 11. **70 funciones**, incluidas sus pruebas parametrizadas, aprobaron en **3,974 s**. Suite completa (archivo local no publicado), compilación (archivo local no publicado). Se verificaron los modos existentes, los buffers de audio moderno/legado, SSTV débil a 96 kHz, la excepción de paridad acotada a Robot 36 y corrección de reloj con barras al comienzo/centro/final del raster.

El ZIP extraído en `/tmp` pasó `codesign --verify --deep --strict`; el ejecutable principal es arm64, la versión del bundle es 0.7.3 y conserva 51 WAV. SHA-256: `4528a8af344bd2627dfed2d6d639a4975532cce5c4e68fcffa0f62937ffabc3b`.

La captura física anterior se mantuvo a 96 kHz/mono sin pérdidas. Se conservaron localmente 84,8 s del celular, con dos cabeceras indicadas como Robot36C. La primera registra VIS 8 con paridad diferente a la esperada. La medición de línea da aproximadamente 152,76 ms; calibración experimental −18.068 ppm y centro 1865 Hz. La 0.7.3 detectó automáticamente esa cabecera en una repetición offline, reconstruyó 320×240 y terminó a unos 42,581 s del archivo. La imagen sigue muy ruidosa: no se considera recibida con calidad suficiente. [Mediciones y límites](validation/sstv-phone-analysis.json), [procedimiento](MICROFONO.md).

**Recepción acústica real completada.** Tras desbloquear el Mac y conceder el permiso, se reabrió el mismo bundle con `--repeat-microphone-test`, conservando su firma. Robot36C se detectó automáticamente y completó **320×240**. Se observaron **5.040.000 muestras**, 96 kHz/mono, **cero pérdidas y ningún error**; el usuario detuvo la captura después y confirmó «funciono». La foto es reconocible y contiene ruido/líneas de interferencia. No hubo cierre observado. [Resultado final](validation/microphone-real-reception-0.7.3.json), [captura y estados](validation/microphone-live-0.7.3-retry.json).

La calibración utilizada fue centro 1865 Hz, reloj −18.068 ppm, Robot 36, Auto VIS, compatibilidad de paridad explícita y umbral 0,1 %. El WAV local conserva 52,5 s y 5.040.000 muestras. Esto confirma la ruta celular → micrófono → ring → decoder → imagen de esta prueba; los demás modos y recepción RF aún requieren contrastes reales. El [primer diagnóstico](validation/microphone-live-0.7.3.json) terminó esperando permiso y se conserva como historial. La repetición usa el mismo paquete sin volver a compilar ni firmar.

---

# Validación de RadioWorkbench 0.7.1

Se retiraron las dos ayudas emergentes personalizadas presentes en el recorrido `TooltipBridge` de los cierres reportados en 0.6 y 0.7. Se añadió preparación de micrófono SSTV, umbral del 1 %, nivel/saturación y contadores de muestras. El tap usa el formato hardware seleccionado; el arranque admite hasta tres intentos de estabilización y exige PCM antes de iniciar el decoder. Se preservaron los 51 WAV y los helpers existentes.

Suite completa (archivo local no publicado): **68 funciones**, incluidas pruebas parametrizadas, aprobadas en **2,355 s**. Tres funciones nuevas de captura (archivo local no publicado), con seis combinaciones de tasa/API en selección de canales, mono/overflow y Robot 36 de bajo nivel a 96 kHz reconstruido a 320×240. Build final (archivo local no publicado): release arm64/macOS 14+, versión 0.7.1/build 9. El ZIP extraído en `/tmp` pasó `codesign --verify --deep --strict`; contiene 51 WAV. SHA-256: `2117e9c7df0c8e06a1bd9d2c8093b2ddc7c0fba971f250815bd637c9d1e83219`.

La revisión visual volvió a funcionar: SSTV mostró micrófono integrado de 96 kHz/mono, Auto VIS, umbral del 1 % y las explicaciones visibles. El permiso concedido permitió observar una discrepancia de formato y una notificación durante el arranque; ambas situaciones detuvieron la captura con errores visibles y la app permaneció abierta. Se observó también audio continuo por una entrada temporal agregada a 48 kHz, más de un millón de muestras, sin pérdidas. Esto no certifica por sí solo el micrófono físico ni la transmisión del celular.

La última compilación incorporó estabilización y ocultó las entradas agregadas internas. Su prueba acotada terminó esperando autorización (`notDetermined`, cero muestras); se volvió a iniciar **Escuchar** desde la interfaz. Tras conceder el permiso, se comprobó **captura directa del Micrófono de MacBook Pro a 96000 Hz y un canal**. El contador aumentó de 1.344.000 a **6.835.200 muestras**, siempre con **cero pérdidas**, sin error ni cierre durante más de 71 segundos de audio. Los niveles ambientales observados fueron −63,8 y −76,6 dBFS. SSTV quedó en Auto VIS/umbral 1 %, buscando cabecera. [Observaciones de la interfaz](validation/microphone-ui-observation.json).

**Pendiente:** recibir una imagen acústica del celular. La captura física ya se comprobó; no se afirma resuelto de manera definitiva cualquier fallo interno de SwiftUI ni una prueba SSTV real completa. [MICROFONO.md](MICROFONO.md) conserva evidencia y procedimiento.

---

# Validación de RadioWorkbench 0.7

Se incorporaron Condiciones y propagación, Band Info y tipos de contacto. Build release arm64/macOS 14+, helper ITU-R P.533 14.2/P.372 14.3 y bibliotecas arm64 incluidos. La firma estricta del ZIP extraído, 25 archivos de datos contrastados con SHA-256 upstream y un cálculo de referencia desde el paquete movido fuera del proyecto pasaron.

La suite final aprobó **65 funciones**, incluidas sus pruebas parametrizadas, en **2,456 s**. [Suite completa 0.7](validation/release-0.7-tests.log), [13 pruebas Band Info/propagación](validation/propagation-tests.log), [build final](validation/propagation-build.log). Se conservaron los modos anteriores; SSTV no recibió cambios de implementación. Las pruebas nuevas incluyen XML/fechas/regiones, cadencia horaria de HamQSL incluso tras reinicio y actualización manual, cambios de estado sin duplicados, países y distancia independientes, NOAA/D-RAP/caché, geometría y cálculo/escala física de potencia y ancho.

La app en ejecución descargó NOAA: Kp y D-RAP con fecha 13 de octubre 14:30 UTC, escalas 14:31 UTC y F10.7 del 12 de octubre 22:00 UTC; obtuvo 57 índices R12 de ITU. La muestra XML de HamQSL se descargó directamente y el parser verificó sus 4 grupos HF y 5 regiones VHF. El elemento de navegación apareció en el árbol de accesibilidad. El puente de control visual se desconectó después; no se completó la revisión visual del formulario, Band Info y gráficos. No se afirma calibración con contactos RF reales ni apertura local observada por spots.

La tabla de contactos calcula 414 o 429 puntos por sesión, según la frecuencia elegida. Se etiqueta como estadística mensual, separada de Band Info general y datos recientes NOAA. Los avisos son internos a la vista; no se implementaron notificaciones de macOS. Países ISO de dos letras opcionales determinan nacional/internacional sin envío de coordenadas.

El paquete conserva 51 WAV de los decodificadores y añade 12 mapas ionosféricos mensuales, 12 coeficientes y factores P.1239, avisos, manifiesto y archivo de fuentes de propagación. SHA-256 del ZIP final: `d81e91ddbde9af8181305ae9f3c9bc3334c03b45ca5778d08832b324cd4ca3c7`. [PROPAGACION.md](PROPAGACION.md) documenta fuentes, alcance y validación; [README](../README.md) explica acceso.

---

# Validación de RadioWorkbench 0.6

ACARS VHF por audio AM se incorporó como helper arm64 separado. La app y el helper se compilaron en release, se abrió el paquete y pasó la firma ad hoc estricta del ZIP extraído. SSTV no recibió cambios de implementación.

La suite completa aprobó **231 casos en 51 funciones**, en 2,010 s: los 220 anteriores y 11 ACARS. Después se añadió un caso de exportación JSON y la comprobación ACARS final aprobó **12 casos en 10 funciones**, incluyendo los anteriores. Son **232 casos distintos verificados**. [Suite completa](validation/release-tests.log), [ACARS y JSON](validation/acars-tests.log), [build](validation/release-build.log).

ACARS incluye transmisión matemática independiente a 12/44,1/48 kHz, continuidad entre bloques y mensajes, CRC inválido rechazado, paridad reparada/rechazada, EOF, silencio, reinicios y cancelación del proceso propio. El remuestreador se compara por procesamiento completo y por bloques, con duración exacta. Las fuentes, contratos y límites se describen en [ACARS.md](ACARS.md).

La interfaz mostró **VB-Cable, 48 kHz, dos canales**, AM y filtro RF inicial de 12,5 kHz. «Ejemplo» decodificó la muestra publicada de **F-GTAE / AF7728 / H1**, modo G, bloque 3, número D65C, con contenido completo. Informó 4,3 s de WAV procesados en 0,03 s. El espectro se puede desplegar; la tabla y detalle están disponibles directamente. La hora se etiqueta como decodificación y no como recepción original.

Se comprobó por archivo la serialización JSON, su escritura atómica y su lectura, preservando campos y ACK de control. El botón de exportación se mostró habilitado; no se completó el diálogo de guardado porque el usuario estaba utilizando otra vista de la app. Se mantuvo su guía de radios abierta.

El paquete incluye **51 WAV**, helper, licencia y fuentes completas del componente GPL. SHA-256: `582b107bb2f628804c24ed302076cb54634b78b3c59784eec63a20224959f78b`. No necesita instalar librerías globales. La cadena de captura real desde SDR++/receptor RF aún necesita validación; el PCM continuo se verificó alimentando un mismo proceso con varios mensajes.

---

# Validación de RadioWorkbench 0.5.1

Versión final del 13 de octubre de 2026, compilada en release para **arm64** y macOS 14+. La compilación, apertura del proceso y firma ad hoc del paquete extraído se verificaron. SSTV no recibió cambios de implementación.

## Resultados actuales

`script/test.sh --configuration release` terminó correctamente: **220 casos en 42 funciones**, 1,864 s de ejecución de pruebas. [Registro 0.5](validation/release-0.5-tests.log), [compilación 0.5](validation/release-0.5-build.log).

| Grupo | Casos |
|---|---:|
| Núcleo previo: texto, NAVTEX, imágenes, canales y ring | 106 |
| Calendario/CSV/referencias EiBi | 21 |
| Descarga EiBi, caché offline y respuestas inválidas | 4 |
| APRS/AX.25: audio, CRC, HDLC, direcciones e integración | 21 |
| CTCSS: 51 tonos, audio adverso, histéresis e integración | 68 |

La **app real** descargó nuevamente la fuente EiBi al arrancar el paquete final: 9.591 registros A26; última consulta observada `2026-10-13 06:25:18 UTC`, archivo fuente del 4 de octubre. Esto comprueba la ruta de red de la app. Las pruebas de offline, HTML inválido, dominio inesperado y fallback HTTP usan un transporte controlado y comprueban que se conserva la caché anterior.

El paquete contiene **50 WAV de ejemplo** y tres archivos públicos EiBi con metadatos. La firma estricta pasó en el ZIP extraído fuera del Escritorio. SHA-256 actual: `a1d01bcc2a19efc05db27904d36518d25ed56a20a37ca327f07611976b3e870c`, también en `dist/RadioWorkbench-arm64.zip.sha256`.

La revisión visual se completó el 13 de octubre con el Mac desbloqueado. Se comprobó búsqueda BBC, filtro de frecuencia, alta/baja de favorito, ficha de sitio/idioma/destino y actualización manual; la descarga visible cambió a 07:07 hora de Santiago. APRS mostró una trama con CRC válido, sin rechazos. CTCSS mostró 100,0 Hz, confianza del 100 % e inicio/fin confirmados. Se seleccionó L y se volvió a decodificar el WAV: el motor informó Canal 1 · L y conservó la detección. La versión 0.5.1 limpia las estadísticas al cambiar de modo y refresca el selector de canal cuando un ejemplo cambia la selección; ambas indicaciones se revisaron en pantalla. La guía quedó abierta, mostrando una consulta automática a las 07:14 hora de Santiago. El núcleo y sus 220 casos de prueba no cambiaron en este ajuste de interfaz. El flujo de audio en vivo desde SDR++ y recepción RF real siguen pendientes. APRS/CTCSS se verificaron con transmisiones matemáticas independientes, sin reutilizar la salida del receptor.

Alcances: [guía y REA](RADIO-BUNKER-REA.md), [Packet/APRS](PACKET.md), [CTCSS](TONOS.md). Lo siguiente conserva el historial 0.4 y sus resultados de imagen/interfaz; no representa una segunda versión actual.

---

# Validación de RadioWorkbench 0.4

Verificación local del 13 de octubre de 2026. Ejecutable **arm64**, configuración **release**, macOS 14 como mínimo y Swift 6.4 de las Command Line Tools disponibles. El original MultiMode Cocoa se preservó.

## Pruebas ejecutadas

`./script/test.sh --configuration release` terminó correctamente: **106 casos**, agrupados en quince funciones de Swift Testing. El registro se conserva en [validation/release-0.4-tests.log](validation/release-tests.log).

| Grupo | Casos | Comprobación |
|---|---:|---|
| CW, RTTY, BPSK31, DTMF | 24 | Mensajes/tonos conocidos, 8 kHz mono y 44,1 kHz estéreo; limpio, desplazamiento y ruido sintético |
| SSTV, conjunto inicial | 8 | Martin M1, Scottie S1, PD50 y Robot36, limpios/desplazados, dimensiones y RGB |
| SSTV, familias y color | 20 | Las otras 18 variantes, además de PD50/Robot36 en rango completo; dimensiones, grises, colores y últimas líneas |
| MMSSTV y cabeceras | 27 | MP/MR/ML/MP-N/MC-N: 19 formatos, tres rangos completos adicionales, uno manual y cuatro rechazos de cabeceras/identificadores |
| APT | 2 | 16640/48000 Hz, sincronía A, raster A/B de 1818×24 y niveles de ambos canales |
| WEFAX | 1 | Inicio manual, 120 LPM/IOC576, raster 1810×64 y barras invertidas al final |
| NAVTEX/SITOR-B de audio | 10 | Limpio, desplazado, ruido, copias dañadas, discrepancia, inversión, reloj 100,1 baud, reinicio y dos tasas/layouts |
| CCIR 476 publicado | 5 | Interleave NAUTICAL y daños independientes de primera/segunda copia |
| Selección de canal | 4 | L/R/mezcla de un WAV de fase opuesta y error al elegir un canal ausente |
| Controles del motor | 3 | Silencio/parámetros, espectro y overflow/wrap del ring SPSC |
| Ring multicanal | 1 | Media de tres canales y copia de un canal sin mezclar |
| Banda de imagen | 1 | Rechazo de audio cuya tasa no conserva vídeo/cabecera por debajo de Nyquist |

Las **41 variantes SSTV** tienen al menos una transmisión matemática completa comprobada. No significa interoperabilidad verificada con todos los transmisores. M3/M4/S3/S4 usan las extensiones históricas documentadas; los modelos con diferencia de color admiten BT.601 limitado y rango completo. Los modos MMSSTV se verifican contra la definición de su autor, incluyendo VIS de 16 bits, N-VIS de 24 bits y LP de 0,1 ms en MR/ML. Las fórmulas y tiempos se calcularon desde fuentes de protocolo: el generador no importa ni utiliza la salida del decoder. Los manifiestos conservan SHA-256 y se comprobaron los hashes de las 27 grabaciones MMSSTV/cabeceras y las 11 NAVTEX.

## Reconstrucciones conservadas

- [Martin M1, 320×256](validation/sstv_martin_m1_8000_mono_clean.png).
- [PD50 con conversión BT.601, 320×256](validation/sstv_pd50_8000_mono_clean.png).
- [Robot72, 320×240](validation/sstv_robot72_8000_mono_clean.png).
- [Pasokon P3, 640×496](validation/sstv_pasokon_p3_8000_mono_clean.png).
- [Wraase SC2-180, 320×256](validation/sstv_wraasesc2_180_8000_mono_clean.png).
- [MP73, 320×256](validation/sstv_mmsstv_mp73_8000_clean.png).
- [ML180, 640×496](validation/sstv_mmsstv_ml180_8000_clean.png).
- [MP73-N, 320×256](validation/sstv_mmsstv_mp73_n_8000_clean.png).
- [MC110-N, 320×256](validation/sstv_mmsstv_mc110_n_8000_clean.png).
- [WEFAX, 1810×64](validation/wefax_hf120_ioc576_8000_mono_manual.png).
- [APT A/B, 1818×24](validation/noaa_apt_2400am_48000_mono_24lines.png).

Se revisaron visualmente las reconstrucciones, además de las aserciones numéricas. Son barras sintéticas; no son imágenes recibidas por antena.

## Aplicación y entrada

La interfaz de 0.4 mostró **VB-Cable, dos canales, 48 kHz**, selección de mezcla/L/R, controles SDR++/filtro RF y 41 opciones SSTV. Se seleccionó L y se volvió a decodificar NAVTEX correctamente; el texto incluyó `ZCZC SA01`, todos los dígitos y signos de la prueba, `NNNN` y contadores FEC en cero. El catálogo mostró 103 perfiles y 41 formatos experimentales; la búsqueda ML mostró sus identificadores de 16 bits en hexadecimal, con MR140/MR175 distintos.

Se cargaron los ejemplos por formato dentro de la app: **MP73-N completo, 320×256**, con N-VIS, y **ML180 completo, 640×496**, con VIS16. La interfaz informó 0,12 s para 75,3 s de audio MP73-N y 0,22 s para 182,7 s ML180. En la versión anterior Martin M1 también se completó y mostró 0,14/0,16 s para 116,7 s. Son observaciones de archivos sintéticos, no benchmarks comparativos ni medidas de consumo de memoria.

Se inspeccionó CoreAudio: VB-Cable existe en este Mac. El selector configura la unidad de entrada de RadioWorkbench y no cambia el dispositivo predeterminado del sistema. La versión 0.3 añade selección de canal para WAV y captura; los casos L/R/mezcla se comprobaron por archivo y en el ring. Todavía no se ha probado una sesión de captura en vivo con SDR++, permisos y señal real; el resultado de WAV no demuestra esa cadena completa.

## Bundle y firma local

La app de `dist/RadioWorkbench.app` contiene un Mach-O arm64 y firma **ad hoc**. Un atributo `com.apple.FinderInfo` añadido de nuevo por File Provider al bundle del Escritorio impidió comprobaciones estrictas durante el empaquetado. El script ahora firma y valida el bundle en staging temporal, después copia la app al proyecto y genera `dist/RadioWorkbench-arm64.zip` sin esos metadatos. `codesign --verify --deep --strict` validó también el ZIP 0.4 extraído en una carpeta temporal. La verificación de apertura comprobó el proceso de la app del proyecto. Eliminar el atributo del Escritorio permite comprobar su copia, pero File Provider puede añadirlo posteriormente sin modificar los bytes firmados.

El bundle incluye 48 WAV, con 41 ejemplos SSTV completos. Se verificó que cada nombre calculado por el selector corresponde a un recurso presente. Los ejemplos suman aproximadamente 93,4 MiB de PCM SSTV en disco; cada archivo se lee por bloques y no se carga el conjunto en memoria. El ZIP final ocupa aproximadamente 60 MiB.

Es un bundle de desarrollo local; no tiene firma Developer ID ni notarización para distribución.

El SHA-256 del ZIP final es `da8ff53a9ecd17b35cccf66b94cd53b1443aaa656ee1c30fc7fe3d8445849d6c`; corresponde al paquete histórico 0.4.

## Trabajo pendiente de recepción

SSTV requiere corpus de transmisores externos y señales con fading/deriva/ruido. WEFAX usa comienzo manual: detección automática de inicio, phasing y fin está pendiente. APT muestra regiones A/B sin calibración radiométrica ni georreferenciación; las grabaciones NOAA APT son históricas. NAVTEX requiere phasing y cubre B colectivo. Los 103 perfiles SSTV del catálogo incluyen 41 formatos del motor y perfiles todavía pendientes; los quince candidatos externos documentados siguen sin integración. Los límites actuales se detallan en [README](../README.md), [SSTV-MODOS](SSTV-MODOS.md), [NAVTEX](NAVTEX.md) y [DECODIFICADORES-EXTRA](DECODIFICADORES-EXTRA.md).
