# RadioWorkbench Events v1

Un adaptador exporta un documento JSON UTF-8 con `schemaVersion: 1` y un array
`events`. La app lo importa mediante **Eventos externos → Importar eventos**.
Hasta 10.000.000 bytes y 5.000 eventos por documento; IDs únicos. Un registro
inválido rechaza el lote completo. Ejemplo mínimo:

```json
{
  "schemaVersion": 1,
  "events": [{
    "id": "example-001",
    "source": "Mi adaptador 1.0 / archivo de prueba",
    "sourceKind": "imported",
    "protocolName": "TEST",
    "entityID": "SYNTHETIC",
    "receivedAt": "2026-10-18T00:00:00Z",
    "observedAt": "2026-10-17T23:59:58Z",
    "latitude": -33.45,
    "longitude": -70.67,
    "message": "Ejemplo sintético, no una recepción real",
    "integrity": "No verificado"
  }]
}
```

| Campo | Regla |
|---|---|
| id | Texto no vacío, hasta 256 bytes UTF-8; único dentro del lote. |
| source | Adaptador, versión y origen comprensibles; hasta 300 bytes. No se interpreta como URL. |
| sourceKind | audioFile, audioLive, networkAudio, internet o imported. Al importar se reemplaza por imported, conservando la fuente declarada. |
| protocolName | Texto no vacío de hasta 40 bytes. No habilita código ni selecciona un ejecutable. |
| entityID | Identidad declarada, hasta 128 bytes; no implica autenticación. |
| receivedAt | ISO 8601 UTC, fecha de recepción según el productor; año 1900 o posterior y como máximo 5 min en el futuro. |
| observedAt | Opcional. Hora original de observación/captura si se conoce; mismos límites. No copiar la importación como captura. |
| latitude/longitude | Ambas ausentes o ambas válidas, finitas, −90…90 y −180…180. Sin coordenadas se conserva el evento en la tabla. |
| message | Hasta 8.192 bytes. Se muestra como texto. |
| integrity | Hasta 300 bytes; explica qué verificó el productor. Importar no vuelve a comprobar el CRC de su protocolo. |
| importedAt | Opcional en exportaciones. La app asigna su hora local al importar, sin confiar en la recibida. |

La app añade un espacio de IDs derivado del hash del documento, evitando que un
adaptador sustituya un evento local. Conserva hasta 5.000 eventos en memoria y
permite exportar los visibles en el mismo formato. Las trazas de importaciones
requieren `observedAt` y no se unen entre documentos distintos. El importador no
escucha puertos ni envía datos, interpreta comandos o abre enlaces del mensaje.
Los adaptadores NMEA y de telemetría necesitan validadores de protocolo propios.
