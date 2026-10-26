# RadioWorkbench 0.16.0 · Ajustes / Settings

[Español](#es) · [English](#en)

<a id="es"></a>
## Español

La versión 0.16.0, build 32, incorpora Ajustes con seis apartados y selección de idioma español/inglés. Conserva los formatos e índices de las bibliotecas existentes.

| Apartado | Comportamiento |
|---|---|
| General e idioma | Español/English para controles, ayudas y estados propios de la app; recordar sección y recuperar modo, parámetros, dispositivo/canal y PCM TCP. La recuperación no inicia captura, reproducción, Rigctl ni conexiones. |
| Audio | Fuente, dispositivo por UID y canal predeterminados; aplicar explícitamente a recepción; perfiles existentes y avisos de saturación/pérdida de muestras. La sesión restaurada tiene prioridad; si falta el canal se usa mezcla. No cambia la entrada predeterminada de macOS. |
| Apariencia y rendimiento | Sistema/claro/oscuro, tamaño de texto, paletas océano/ámbar/grises y límite visual 5/10/15/25 cuadros/s. Menor consumo fija 5 cuadros/s y reduce el historial de 80 a 40 líneas; conserva las muestras que recibe el decodificador. Cambiar estos parámetros gráficos requiere una recepción detenida. |
| Biblioteca | Espacio ocupado por audio/I/Q, ubicación configurable mediante copia por bloques con verificación SHA-256, nombres para nuevos registros/exportaciones y ZIP de respaldo manual. Conserva el original y la papelera reversible; no elimina automáticamente grabaciones. |
| Datos y avisos | Actualización manual o automática de guía, satélites y condiciones, intervalos configurables y avisos de favoritas. Desactivar avisos retira las notificaciones programadas por la app. Se respetan las cadencias mínimas de cada proveedor; una actualización puede ser parcial si una fuente falla. |
| Conexiones y diagnóstico | Guardar/aplicar perfiles de PCM TCP local y puerto Rigctl, disponibilidad de motores y exportación JSON local a solicitud. Aplicar un perfil solo cambia parámetros. El diagnóstico excluye audio, mensajes, indicativos, coordenadas y rutas. |

### Idioma y persistencia

El idioma cambia las vistas SwiftUI sin volver a decodificar. Los menús propios usan el mismo catálogo. Los diálogos del sistema y componentes externos pueden seguir el idioma de macOS o requerir reabrir la app. Los mensajes recibidos, nombres de emisoras, archivos, indicativos y anotaciones personales se conservan literalmente. Los textos de servidores y motores externos no se traducen automáticamente. El README y estas notas están en ambos idiomas; otros documentos técnicos conservan su idioma original.

Los ajustes y perfiles de conexión residen en las preferencias de esta aplicación, con validación de límites. No se altera el idioma global del Mac. La sección recordada es independiente de la recuperación de parámetros. Los valores anteriores se mantienen si se desactiva su recuperación; no se borra la biblioteca.

### Carpeta, respaldo y recuperación

En **Ajustes → Biblioteca**, el selector crea `RadioWorkbenchLibrary` dentro del destino elegido y copia únicamente `Recepciones` y `SigMF`. Rechaza destinos que ya contengan esas bibliotecas, carpetas anidadas y enlaces simbólicos. Solo cambia de repositorio después de verificar cada archivo. Los motores y cachés permanecen en Application Support.

**Crear copia de seguridad** incluye bibliotecas/índices, `preferences.json` con ajustes/perfiles de conexión y `InputProfiles.json` cuando existe. No incluye motores descargados, cachés ni claves de publicación. Es una copia manual; necesita espacio para el staging y el ZIP y puede tardar con I/Q grande.

Recuperación manual: cierra la app, extrae el ZIP, conserva una copia de la biblioteca de destino y repón `Recepciones` y `SigMF` bajo la carpeta activa que mostraba Ajustes. Si necesitas recuperar perfiles de entrada, devuelve `InputProfiles.json` a `~/Library/Application Support/RadioWorkbench/`. `preferences.json` documenta los valores a reponer en Ajustes; esta versión no importa automáticamente ese JSON ni restaura las preferencias del sistema. Comprueba los registros y el audio antes de retirar tu copia anterior.

### Verificación y límites

292 funciones registradas: 286 aprobadas, seis opcionales omitidas, cero fallos; además 21 controles C HF. Se comprueban persistencia aislada, recuperación sin autoarranque, política manual de guía sin solicitudes automáticas, formato/variables de traducción, copias y rollback, respaldo ZIP y límites visuales sin cambiar las muestras del decoder. No se repitió recepción física. [Evidencia de entrega](validation/release-0.16.0.json).

La distribución sigue siendo experimental, arm64 para Apple Silicon, mínimo del bundle macOS 14; CWKit requiere 15 y el runtime DSD-neo opcional, 26. Firma ad hoc, sin Developer ID ni notarización. La publicación y el canal Sparkle usan firmas Ed25519 separadas; su verificación no demuestra por sí sola una instalación completa mediante Sparkle.

**Gracias a G4ZJH por su aporte y por proponer español e inglés.** [Apoyar en Ko-fi](https://ko-fi.com/sebastianpasten).

<a id="en"></a>
## English

Version 0.16.0, build 32, adds six Settings sections and a Spanish/English selector while preserving existing library formats and indexes.

| Section | Behavior |
|---|---|
| General and language | Spanish/English app controls, help and status text; remember the section and restore mode, parameters, device/channel and TCP PCM settings. Restoration does not start capture, playback, Rigctl or a connection. |
| Audio | Default source, device UID and channel, an explicit Apply action, existing input profiles and clipping/dropped-sample warnings. A restored session takes priority; an unavailable channel falls back to mixing. The macOS default input is unchanged. |
| Appearance and performance | System/light/dark appearance, text size, ocean/amber/gray palettes and a 5/10/15/25 FPS visual cap. Lower power uses 5 FPS and 40 rather than 80 history lines, preserving decoder samples. Stop reception before changing these graphics parameters. |
| Library | Audio/I/Q storage usage, a configurable folder with block copying and SHA-256 verification, naming for new logs/exports and a manual backup ZIP. Originals and reversible trash remain; recordings are not deleted automatically. |
| Data and alerts | Manual/automatic station-guide, satellite and condition refresh, configurable intervals and favorite-station alerts. Disabling alerts removes the app's pending notifications. Provider-specific minimum intervals still apply; a failed source can result in a partial refresh. |
| Connections and diagnostics | Save/apply local TCP PCM and Rigctl-port presets, inspect engine availability and explicitly export a local JSON diagnostic. Applying presets changes parameters only. Diagnostics exclude audio, messages, callsigns, coordinates and paths. |

SwiftUI views switch language without decoding again. System dialogs and external components may follow macOS language or require relaunching. Received messages, station names, filenames, callsigns and personal notes remain verbatim. Server and decoder-engine text is not automatically translated. The README and these release notes are bilingual; other technical documents retain their original language. Preferences are app-specific and do not change the Mac's global language.

Changing the library folder creates a new `RadioWorkbenchLibrary`, verifies copies of `Recepciones` and `SigMF`, and switches repositories only after success. It rejects existing library folders, nested destinations and symbolic links. Originals are retained; engines and caches stay in Application Support.

Manual backups contain both libraries/indexes, `preferences.json` (settings and connection presets), and `InputProfiles.json` if present. Downloaded engines, caches and signing keys are excluded. Large I/Q backups need room for temporary copies and the ZIP. To recover, quit the app, extract the ZIP, preserve the destination's existing libraries and restore `Recepciones`/`SigMF` under the active library root shown in Settings. Input profiles belong in `~/Library/Application Support/RadioWorkbench/`. Use `preferences.json` as a reference to re-enter Settings: automatic preference-JSON import is not implemented. Verify restored records/audio before removing the earlier copy.

Release tests: 292 registered functions, 286 passed, six optional skips, zero failures, plus 21 HF C checks. New checks cover persistence, restoration without auto-start, manual guide refresh, localization placeholders, library copies/rollback, backup ZIPs and visual caps without changing decoder samples. Physical reception was not repeated. [Release evidence](validation/release-0.16.0.json).

Experimental arm64 distribution for Apple Silicon; bundle minimum macOS 14, CWKit 15, optional DSD-neo runtime 26. Ad hoc signature, without Developer ID or notarization. Archive/feed Ed25519 verification is separate from a complete Sparkle installation test.

**Thank you to G4ZJH for the contribution and the Spanish/English idea.** [Support on Ko-fi](https://ko-fi.com/sebastianpasten).
