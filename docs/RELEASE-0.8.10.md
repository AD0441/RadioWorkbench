# RadioWorkbench 0.8.10 · build 22

Paquete local Release para macOS 14+ y Apple Silicon arm64. Continúa la corrección del área topográfica de 0.8.9; añade los mapas de repetidoras y pases, reparación de fuentes de satélites y los grupos de decodificadores VHF/HF priorizados.

- **Repetidoras:** mapa Apple Maps de sitios con coordenadas y selección manual con clic para preparar el destino ITM.
- **Satélites:** épocas UTC GP sin Z, fechas reales AMSAT, actualización y caché por fuente, API GitHub para frecuencias y alternativa orbital AMSAT TLE. Trayectoria de cada pase y gráfico de azimut/elevación.
- **VHF/audio:** POCSAG 512/1200/2400 con BCH y exportación JSON; ocho familias de cinco tonos/Selcall mediante multimon-ng arm64 incluido.
- **HF/audio:** cinco variantes Hell por pulsos con raster/PNG y RTTY ASCII de 7/8 bits sin paridad.
- **Ejemplos:** señales sintéticas y controles específicos de tasa, variante, tipo y ancho de audio.

[Validación y paquete](VALIDACION.md) · [Decodificadores y límites](DECODIFICADORES-0.8.10.md) · [Consultas y fuentes](CONSULTAS.md) · [Cobertura topográfica](TERRAIN-COVERAGE.md).

Las órbitas continúan con Kepler + J2 aproximado; SGP4 y Doppler no están implementados. El mapa satelital muestra trayectoria, no una huella RF. La captura real por SDR++/cable virtual de los nuevos modos queda pendiente. Firma ad hoc, sin Developer ID ni notarización. La release pública previa sigue siendo 0.8.8; esta ampliación se prepara en la rama de revisión.
