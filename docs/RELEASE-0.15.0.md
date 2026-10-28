# RadioWorkbench 0.15.0 · complementos y diagnóstico

macOS 14 o posterior, Apple Silicon. Esta entrega conserva la biblioteca de audio existente y añade una biblioteca I/Q independiente.

## Cambios de uso

- **Entrada de audio → Asistente de conexión**: fuente y canal, perfil SDR del modo/variante, comprobación de niveles y pérdidas, validación del protocolo y diagnóstico JSON local. La captura solo empieza al pulsar el botón correspondiente. No atribuye una pérdida de audio a una causa RF sin evidencia.
- **Calidad de entrada**: contadores nativos AX.25 CRC, RTCM 2/paridad y SITOR-A 4/7/cadencia. Indican lo observado desde el último reinicio del decodificador; no son una tasa de entrega ni un contador de todo lo transmitido. Un bloque SITOR-A válido no equivale a CRC ni a confirmación propia.
- **Taller → Comparar decodificación A/B**: mismo WAV, ejecuciones consecutivas con dos centros de audio, canales e inversión. Conserva los otros parámetros de la referencia. Presenta tiempo, texto acotado e integridad disponible, sin declarar un ganador. Se limita a modos de texto disponibles, diez minutos y 1 GB; voz e imágenes requieren una evaluación específica.
- **Biblioteca → I/Q · SigMF**: importa y copia el par `.sigmf-meta`/`.sigmf-data`, verifica SHA-512, conserva anotaciones y exporta a una carpeta nueva. Papelera reversible sin eliminación automática. Máximo 100 GB y 1000 entradas; copia por bloques de 1 MiB, cancelable.
- **Preparar LRPT**: pasa a SatDump el archivo, formato, tasa, RF y fecha de una captura SigMF compatible. No inicia el proceso ni garantiza que las muestras contengan LRPT.
- **Ajustes → Actualizaciones** y menú **Buscar actualizaciones**: Sparkle 2.10.0 fijado, canal HTTPS y firmas Ed25519 del canal y del paquete. Búsqueda automática optativa; descarga e instalación requieren una acción. El canal inicial firmado está vacío: no se publica una actualización descargable 0.15.0 al instalar esta compilación local.

## Alcance SigMF

Especificación 1.0–1.2, muestras crudas reales o complejas con formato reconocido, canales y capturas ordenadas. Rechaza enlaces simbólicos, referencias a otro directorio, cabeceras/desplazamientos no nulos, datos incompletos y extensiones obligatorias desconocidas. Preserva anotaciones y campos desconocidos sin interpretarlos. No admite todavía archivos tar/colecciones. SatDump requiere un solo canal complejo `cf32_le`, `ci16_le`, `ci8` o `cu8`, una captura desde muestra cero, RF y fecha conocidas.

## Herramientas para el desarrollo

Instaladas en Codex: [SwiftUI Expert](https://github.com/AvdLee/SwiftUI-Agent-Skill), [Swift Testing Pro](https://github.com/twostraws/Swift-Testing-Agent-Skill) y la skill local `radioworkbench-quality`. Mejoran la revisión del proyecto; no se ejecutan dentro de la aplicación. El cambio completo de idioma español/inglés continúa pendiente.

Fuentes: [Sparkle](https://sparkle-project.org/documentation/), [SigMF](https://sigmf.org/). Sparkle conserva su licencia en el paquete. La clave privada de publicación permanece fuera del repositorio y de la aplicación. La firma local de la aplicación sigue siendo ad hoc; no se afirma notarización ni firma Developer ID.

La evidencia final de pruebas, empaquetado e instalación se registra en `validation/release-0.15.0.json`.
