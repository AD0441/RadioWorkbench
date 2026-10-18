# RadioWorkbench 0.9.0 · build 24

Cinco mejoras de recepción y planificación:

1. SatelliteKit SGP4/SDP4 reemplaza Kepler/J2, conserva BSTAR en GP/TLE, usa observador WGS84 y muestra Doppler de bajada AOS/LOS para la frecuencia elegida.
2. FT8/FT4 por WAV o entrada seleccionada: LDPC/CRC, ventanas UTC, inicio ajustable de WAV, mensaje/frecuencia/sincronía y JSON. Búsqueda temporal FT4 corregida. No hay transmisión.
3. CWKit automático y neuronal en helper macOS 15+, con modelo Core ML CPU, tono/WPM estimados y texto provisional separado. Morse manual permanece en macOS 14.
4. libacars interpreta ADS-C/CPDLC y reensambla aplicaciones. La cola acarsdec ahora es FIFO bajo carga. Mapa de coordenadas ADS-C con CRC interno válido y exportación completa; ejemplo incluido.
5. DSD-neo oficial 2.10.0 arm64, descargable con huella SHA-256 fijada; requiere macOS 26. Receptor PCM para DMR, P25 I/II, NXDN, D-STAR, YSF, M17 y dPMR, registro y voz WAV al finalizar. Ejemplo M17 SMS. Sin seguimiento de trunking ni control del SDR.

La app conserva macOS 14+ y arm64. Los requisitos adicionales se indican antes de iniciar los motores. No se incorporan binarios o recursos comerciales de MultiMode ni del APK de referencia. Se mantienen todas las correcciones POCSAG de 0.8.11, los mapas/fuentes de 0.8.10 y el cálculo topográfico por celda de 0.8.9.

Validación: 148 pruebas registradas, dos opcionales de red omitidas; señales sintéticas, CW en vivo simulado, 100 aplicaciones ACARS consecutivas sin pérdidas de orden, SGP4 de referencia y seis grabaciones públicas FT8 comparadas. M17 comprueba SMS/CRC y Codec2 a WAV; los otros protocolos DSD requieren validación RF específica. Sin captura nueva de micrófono o SDR++/VB-Cable. Consulta [detalles](INTEGRATIONS-0.9.md) y [evidencias](VALIDACION.md).

Firma local ad hoc, sin Developer ID ni notarización. El ZIP local 0.9.0 se genera en dist; la descarga pública indicada en el README continúa en 0.8.8 hasta publicar una nueva release.
