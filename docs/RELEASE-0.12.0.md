# RadioWorkbench 0.12.0

Compilación 27 para macOS 14+ y Apple Silicon. El motor oficial opcional DSD-neo
requiere macOS 26. Firma local ad hoc, sin notarización.

- DMR: reproducción durante la recepción, selección TS1/TS2/ambos y conservación
  del WAV. stdout PCM y mensajes de consola usan rutas separadas.
- Panel DMR con CC, emisor, destino, clase de llamada y antigüedad por intervalo;
  exportación JSON con procedencia y horas de procesamiento. Las líneas con
  errores no sustituyen identidades y no se etiquetan como CRC validado.
- Audio de salida limitado a dos segundos pendientes. Los archivos con escucha
  activada se procesan a velocidad de reproducción; Detener corta la salida y
  el cierre del WAV se espera fuera de la interfaz.
- El motor puede esperarse más de una vez sin consumir su señal de finalización.
  La cancelación cierra stdin antes de terminar el proceso y contempla un límite
  de dos segundos antes de forzar el cierre de ese proceso propio.
- Revisión Guía → HF: se observaron selección, ficha y envío BBC a 9410 kHz;
  el usuario confirmó BBC, 9,410 MHz y dirección Escucha en el planificador.

La grabación independiente de SDRTrunk #1803 confirma TS1, origen 3025209,
destino 9990 y llamada privada. El motor produjo CC7, sin oráculo externo para
ese campo. TS2 silencia esa llamada sin borrar su señalización. Falta una
grabación identificada de dos conversaciones simultáneas y evaluación perceptual
de voz. No se inicia micrófono, hardware SDR, trunking ni transmisión durante las
pruebas offline. La prueba física SDR++ → VB-Cable permanece aplazada.

[Uso y límites DMR](DMR-0.12.md) · [Contrato medido](validation/dmr-0.12-contract.md).

Validación: 212 funciones registradas, 210 aprobadas, dos opcionales de red
omitidas y cero fallos. Incluye DSD-neo oficial, M17, corpus DMR independiente,
renderizado de audio offline, cierre normal y cancelación; no captura física.
