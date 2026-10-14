# RadioWorkbench 0.8.8 · macOS arm64

Primera publicación pública de RadioWorkbench: aplicación experimental de recepción y consulta de radio para Mac con Apple Silicon.

## Descarga y requisitos

`RadioWorkbench-0.8.8-macos-arm64.zip` contiene la app, sus helpers arm64, ejemplos sintéticos y fuentes/avisos de los componentes externos. `SHA256SUMS` permite comprobar el archivo descargado.

- Plataforma declarada: macOS 14 o posterior, arm64/M1 y posteriores.
- Entorno de prueba: MacBook Pro M1, macOS 27.2.
- Herramientas verificadas para compilar: Apple Swift 6.4 y SDK macOS 27.0.
- Firma local ad hoc; no incluye Developer ID ni notarización. La verificación de firma no equivale a aprobación de Gatekeeper para una descarga de Internet.

Extrae el ZIP y abre `RadioWorkbench.app`. Si macOS bloquea la primera apertura, consulta el [procedimiento de Apple](https://support.apple.com/es-cl/102445). La captura requiere el permiso de micrófono del sistema.

## Funciones de esta publicación

- Audio en vivo o desde archivos, entrada/canal seleccionable, perfiles persistentes, espectro y waterfall.
- CW, RTTY ITA2, BPSK31, DTMF, 51 tonos CTCSS, NAVTEX/SITOR-B colectivo, AX.25/APRS AFSK1200 y ACARS VHF por audio AM.
- 41 variantes SSTV con Auto VIS, reloj/centro automáticos, reducción de impulsos y exportación PNG; WEFAX HF y APT de grabaciones.
- Guía EiBi/HFCC con horarios UTC, favoritas, avisos y datos técnicos cuando la asociación es inequívoca.
- Condiciones NOAA, Band Info, D-RAP, ionosondas, PSK Reporter y Reverse Beacon Network.
- Planificación HF mediante ITU-R P.533/P.372 y enlaces VHF/UHF mediante NTIA ITM, alturas topográficas más antenas AGL, perfiles de montaña y corredor Fresnel.
- Consultas SUBTEL de bandas, repetidoras e indicativos; APRS-IS de solo recepción; frecuencias/reportes de satélites y pases aproximados.

## Corrección en 0.8.8

Se elimina el cierre al escribir el indicativo en el panel APRS. En 0.8.7, el observador `didSet` reasignaba la propiedad `@Observable` y entraba en recursión hasta agotar la pila. El campo ahora normaliza a mayúsculas mediante almacenamiento separado. Una prueba sobre el almacén usado por SwiftUI simula la escritura carácter por carácter y comprueba la persistencia.

## Validación y límites

La suite completa aprobó **99 funciones de prueba**, con variantes parametrizadas. El ZIP extraído pasó `codesign --verify --deep --strict`, sus componentes son arm64 y el bundle identifica **0.8.8/build 20**. El archivo también pasó `unzip -t`.

SHA-256 del ZIP:

```text
d01d190fa4595f7cb26a4797f8e3fba980f14e0b9ccd407ed64c822d22c71cb8
```

SDR++ se sintoniza manualmente. El modelo HF describe condiciones mensuales; la cobertura ITM es aproximada entre perfiles. Los pases de satélites usan Kepler+J2 y no SGP4 ni corrección Doppler. Los servicios consultados pueden estar desactualizados o no disponibles. Las pruebas sintéticas no establecen interoperabilidad completa ni calidad en todas las condiciones RF.

Esta publicación incluye código, documentación y datos de prueba sintéticos. Las fotografías reconstruidas del celular y las grabaciones acústicas personales permanecen locales y no forman parte del repositorio ni de sus commits públicos.

[README y uso](https://github.com/AD0441/RadioWorkbench#readme) · [Validación detallada](https://github.com/AD0441/RadioWorkbench/blob/main/docs/VALIDACION.md) · [Consultas](https://github.com/AD0441/RadioWorkbench/blob/main/docs/CONSULTAS.md) · [Propagación](https://github.com/AD0441/RadioWorkbench/blob/main/docs/PROPAGACION.md)
