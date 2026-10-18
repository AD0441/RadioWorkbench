# RadioWorkbench 0.11.0

Versión preliminar para macOS 14+ y Apple Silicon. CWKit requiere macOS 15; el runtime
oficial opcional DSD-neo requiere macOS 26. Firma local ad hoc; sin notarización.

[Descarga en GitHub](https://github.com/AD0441/RadioWorkbench/releases/tag/v0.11.0),
con ZIP arm64 y archivo `SHA256SUMS`. El código de los decodificadores y sus
licencias están en el repositorio y en los archivos de fuentes del paquete.

- Guía de radios → Planificador HF reparada: selección al navegar, envío directo,
  copia con unidades/procedencia, sitios múltiples, campos faltantes visibles y
  potencia HFCC elegida como supuesto. Fecha UTC seleccionable.
- Modelo HF: R12=0 válido, condiciones de hemisferio sur corregidas y 21 pruebas
  C; se conserva la referencia pública ITU y los escalados físicos de unidades.
- Descarga HFCC reparada para los nombres reales dentro del ZIP y reglas de
  calendario HFCC separadas de EiBi.
- MT63 en seis variantes y ALE 2G, con ejemplos y fuentes reproducibles.
- Biblioteca de recepciones; diagnóstico; audio TCP local; DSC MF/HF y VHF;
  mapa común; SatDump LRPT offline; Rigctl optativo; eventos externos; taller
  CW/RTTY/BPSK31. [Alcance y límites de los nueve módulos](NUEVE-MEJORAS.md).
- Revisión de DMR Brown y comparación con DSD-neo: arquitectura y oportunidades
  documentadas; no se confunde voz decodificada con discriminador DMR.

Los modos SITOR-A, DGPS, LORAN-C, Globe Wireless y ALE 3G no se anuncian como
implementados. La clasificación automática, I/Q/SigMF en biblioteca, AIS/RS41,
UDP, Doppler automático y un parser DSC completo siguen como ampliaciones.

La prueba física SDR++ → VB-Cable permanece aplazada. Las pruebas TCP/Rigctl
usan servidores de este Mac y no sintonizan el SDR. La validación LRPT de señal
independiente aún falta; la ejecución real con entrada cero es una prueba
negativa del proceso, no una imagen recibida. Ningún audio privado del usuario
ni fotografías de SSTV se añaden a GitHub.

Validación de lógica: suite Release con 202 funciones registradas, 198 aprobadas,
cuatro opcionales omitidas y cero fallos; 21 comprobaciones C de HF y 18 DSC
repetidas con ASan/UBSan. El ZIP extraído pasó integridad y firma estricta;
sus ejecutables son arm64. SHA-256:
`ab2a4b05a0324a2112e671c88ab1f5c6e066b2086f1ebe90c535b0432e420961`.

La inspección de interfaz comprobó apertura, navegación disponible, parámetros
TCP y diagnóstico. La herramienta de control de pantalla se cerró y RadioWorkbench
siguió activa; la comprobación interactiva de los otros flujos, incluida Guía → HF,
queda pendiente. [Evidencia y límites](VALIDACION.md).
