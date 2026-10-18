# MT63 y ALE 2G · RadioWorkbench 0.10.0

Esta ampliación incorpora dos modos pendientes como **receptores de audio y WAV**. Ambos helpers se compilan para arm64/macOS 14, sin Qt, GNU Radio, FFTW ni instalación global. La captura continúa usando la entrada y el canal elegidos en RadioWorkbench. No se transmite ni se controla SDR++ automáticamente.

## MT63

Motor C++ de [fldigi](https://github.com/w1hkj/fldigi), revisión `61b97f4133c488063f3de1795c894d22d5032e8a`, con código y licencia GPL-3.0-o-posterior en `Vendor/MT63`. No es la aplicación fldigi completa. La revisión seleccionada es la del espejo de código; no se presenta como la versión más reciente del producto fldigi.

Selecciona **MT63** y la variante: **500, 1000 o 2000 Hz**, cada una con **entrelazado corto o largo**. Debe coincidir con el emisor. Audio (Hz) es el centro del bloque; el valor inicial es 1500 Hz. El helper acepta centros de 1000 a 2500 Hz conservando toda la banda dentro de 0–4000 Hz. La entrada se remuestrea de forma continua a 8 kHz.

| Variante | Banda de audio con centro 1500 Hz | SDR++ inicial |
|---|---|---|
| 500 corto/largo | 1250–1750 Hz | USB, filtro RF 3 kHz |
| 1000 corto/largo | 1000–2000 Hz | USB, filtro RF 3 kHz |
| 2000 corto/largo | 500–2500 Hz | USB, filtro RF 3 kHz |

Desactiva squelch y procesado de voz. Conserva el inicio y espera la adquisición y el entrelazado: puede haber más de 20 s sin texto en 500 Hz/largo. El adaptador espera a llenar el entrelazado y exige sincronía y una métrica FEC mínima; una emisión corta o débil puede perder el inicio. En los ejemplos con preámbulo, la latencia añadida medida fue de 3,3–19,6 s según variante; no es un máximo garantizado. El receptor muestra sincronía; la confianza exportada es una medida interna de sincronización entre 0 y 1, **no SNR, probabilidad de texto correcto ni CRC**. El texto debe contrastarse cuando la señal sea difícil. El protocolo no aporta aquí una comprobación CRC de mensaje.

**Ejemplo** carga la variante elegida. Son señales locales producidas con el transmisor de prueba del mismo código upstream, separado del helper distribuido. Verifican compatibilidad TX/RX y la integración, pero no constituyen una captura RF independiente. Se conserva el generador y la procedencia en los manifiestos de fixtures. La validación añade ruido, silencio, flujos fragmentados y recepción con la entrada abierta.

## ALE 2G

Motor [ALE_2G de KiwiSDR, copia fijada del repositorio histórico](https://github.com/jks-prv/Beagle_SDR_GPS/tree/efb38e2b25137029cb37a96a94e03366f8d2871e/extensions/ALE_2G), revisión `efb38e2b25137029cb37a96a94e03366f8d2871e`, descendiente de gr-ale/LinuxALE. Fuentes y GPL-3.0-o-posterior en `Vendor/ALE2G`. El desarrollo actual está en jks-prv/KiwiSDR; esta integración no afirma usar su revisión más reciente.

En SDR++ selecciona **USB**, filtro RF **3 kHz**, squelch y filtros de voz desactivados. El receptor espera los **ocho tonos entre 750 y 2500 Hz** a 125 símbolos/s; ajusta la sintonía en SDR++. RadioWorkbench remuestrea el audio a 8 kHz. Recibe sondeos THIS IS/THIS WAS, eventos de establecimiento de llamada y texto AMD según el motor. No habilita exploración automática ni transmisión.

**ALE 3G sigue pendiente.** La corrección Golay y diversidad temporal del motor 2G no equivalen a CRC de mensaje, ni a una estimación de SNR. El campo upstream «His BER» se conserva como diagnóstico del motor, sin transformarlo en calidad física local o porcentaje de errores medido.

**Ejemplo** carga una señal 8-FSK creada mediante un modulador Python independiente, con Golay por división polinómica, interleaving y diversidad temporal. Sus textos son ficticios y no corresponden a emisiones. Las grabaciones externas de KiwiSDR se usan solo para comprobación local: no se redistribuyen sin aclarar su licencia.

## Flujo, recursos y exportación

- Abrir audio, Escuchar, selección de canal, perfiles guardados y Detener usan el mismo flujo de recepción de los demás modos.
- Los helpers reciben float32 mono por stdin y publican JSON incremental, vaciando stdout durante la recepción. Se conservan fragmentos de muestra entre lecturas; una muestra incompleta al EOF se informa como error.
- El procesamiento se realiza fuera del callback de CoreAudio. El texto y los registros conservan los límites existentes: 40.000 caracteres y 200 registros visibles/exportables. Los registros JSON de MT63 incluyen estados sin texto; no son contactos.
- La app ofrece exportación de texto y JSON. No asigna automáticamente frecuencia RF, ubicación o indicativo a una palabra que el protocolo no proporcionó.
- Los ajustes antiguos siguen abriéndose; la variante MT63 predeterminada es 1000 Hz/largo.

Los cambios locales, hashes originales/actuales y recetas de compilación están en cada carpeta Vendor. El bundle incluye licencias y archivos de fuentes completas del motor seleccionado y su adaptador. No se incorporaron código, interfaces ni recursos comerciales de MultiMode Cocoa o AFSK1200.

## Qué sigue pendiente

SITOR-A, DSC/GMDSS, DGPS, LORAN-C y Globe Wireless permanecen deshabilitados como receptores. ALE 3G también necesita otra integración. La [revisión de las cinco aplicaciones y las propuestas](REVISION-APPS-0.10.md) explica para cada uno la entrada necesaria, el motor candidato y la evidencia que falta. No se activaron AIS, LRPT, radiosondas, DRM ni conexiones TCP/Rigctl en esta ampliación.

Las pruebas de audio se realizan con archivos y flujos simulados. La conexión física SDR++ → cable virtual → entrada seleccionada continúa aplazada por indicación del usuario.
