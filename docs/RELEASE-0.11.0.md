# RadioWorkbench 0.11.0

Versión para macOS 14+ y Apple Silicon. CWKit requiere macOS 15; el runtime
oficial opcional DSD-neo requiere macOS 26. Firma local ad hoc; sin notarización.

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

Validación de lógica: suite Release con 202 pruebas y cero fallos; 21 comprobaciones C de HF y 18 comprobaciones DSC repetidas con ASan/UBSan. Las omisiones opcionales se conservan en el registro de la suite.
