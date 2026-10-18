# RadioWorkbench 0.8.9 · cobertura con relieve

La cobertura anterior rellenaba una envolvente hasta el punto favorable más lejano de cada rumbo y dibujaba un círculo ideal por defecto. Eso ocultaba sombras y podía sugerir recepción en valles no calculados. Esta versión usa una malla de enlaces independientes con perfiles DEM completos y conserva huecos e islas de recepción.

## Uso

En **Condiciones y propagación**, abre el panel VHF/UHF, indica TX y las alturas AGL de ambas antenas. Ajusta frecuencia, watts, ganancias, umbral RX, radio de análisis y malla. Pulsa **Calcular malla con terreno**. Verde significa margen ≥10 dB; ámbar, margen 0–10 dB. Activa las celdas bajo umbral para inspeccionar sombras. El círculo de Tierra lisa es una referencia opcional apagada inicialmente.

Selecciona RX en el mapa para consultar su celda; el área se conserva. **Calcular relieve y enlace** calcula después el punto exacto usando el mismo DEM. La app muestra el suelo y la suma AMSL+AGL, perfil de montañas, resolución, margen y avisos NTIA. Hay progreso, cancelación y caché local. El límite circular de análisis no indica el alcance máximo.

## Validación y entrega

109 funciones automáticas aprobaron; el benchmark opcional con DEM real de Santiago pasó por separado. Se contrastaron cinco perfiles oficiales NTIA a menos de 0,01 dB y se verificó el renderizador fuera de pantalla. [Método y evidencia](TERRAIN-COVERAGE.md).

Paquete local: `RadioWorkbench-0.8.9-macos-arm64.zip`, macOS 14+, arm64, versión 0.8.9/build 21. La firma ad hoc estricta y el ZIP extraído se verificaron; no está notarizado. SHA-256:

```text
fcaa8f9a34f6cbf0dd7bcb5a30a6eaec2d5483ead85e7c0c083a9042fbc22dc5
```

La inspección visual interactiva de Apple Maps queda pendiente porque CUA desconectó su canal nativo; la app siguió activa. El modelo usa terreno y parámetros estadísticos, sin edificios, vegetación, pérdidas detalladas de cable, interferencia, esporádica E ni ductos instantáneos. Las celdas sin datos son transparentes. No se ajustó frente a recepción RF medida. Las fotografías personales no se incluyen.
