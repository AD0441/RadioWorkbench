# Motores integrados · RadioWorkbench 0.9.0

La app permanece en macOS 14+, Apple Silicon. Cuatro componentes se compilan desde fuentes fijadas; DSD-neo se descarga por separado desde su distribución oficial. No se integra código de MultiMode Cocoa ni del APK analizado.

| Componente | Función | Requisito |
|---|---|---|
| [SatelliteKit](https://github.com/gavineadie/SatelliteKit) | SGP4/SDP4, pases y mapa; WGS84 y Doppler de bajada | macOS 14+ |
| [ft8_lib](https://github.com/kgoba/ft8_lib) | FT8 y FT4 por audio/WAV, LDPC y CRC | macOS 14+ |
| [CWKit](https://github.com/captobie/cwdecode) | CW automático y neuronal Core ML | macOS 15+; Morse manual sigue en 14 |
| [libacars](https://github.com/szpajder/libacars) | ADS-C/CPDLC, texto y JSON, reensamblado; posición ADS-C en mapa | macOS 14+ |
| [DSD-neo 2.10.0](https://github.com/arancormonk/dsd-neo/releases/tag/v2.10.0) | DMR, P25 I/II, NXDN48/96, D-STAR, YSF, M17, dPMR mediante PCM | **Paquete oficial: macOS 26+**, arm64 |

## Uso

- Selecciona FT8/FT4, elige entrada o WAV y conserva USB, filtro RF 3,5 kHz y audio 100–3500 Hz. La conversión a 12 kHz es interna. En vivo se descarta la primera ventana incompleta y se espera al límite UTC de 15/7,5 s; sincroniza el reloj del Mac. En WAV ajusta el inicio de la primera ventana. El campo de inicio del resultado es relativo al análisis, no una medida calibrada del error del reloj del transmisor. Se muestran mensajes con LDPC/CRC válidos, frecuencia, inicio y puntuación de sincronía. No se presenta esta puntuación como SNR. Los indicativos abreviados por hash pueden quedar sin resolver entre ventanas.
- En Morse selecciona Manual, CWKit automático o CWKit neuronal. Los últimos dos estiman tono y velocidad. El modelo neuronal usa CPU por decisión de CWKit, no promete ejecución ANE/GPU; añade varios segundos de latencia y puede equivocarse. No sustituye confirmación de un indicativo. La salida provisional se muestra separada del texto confirmado.
- ACARS mantiene AM y ambos tonos MSK 1200/2400 Hz. libacars recibe exclusivamente bloques previamente validados por acarsdec, recupera paridad y comprueba BCS otra vez. Solo se interpretan aplicaciones completas; se conservan bloques y estado de reensamblado. Se dibuja una posición cuando un informe ADS-C válido la contiene; no se interpola ni se presenta como seguimiento continuo. JSON incluye texto original, árbol de aplicación y posición. zlib habilita MIAM; XML/Jansson están desactivados y no se promete interpretación OHMA ni formateo XML.
- En Voz digital elige el protocolo y descarga el motor. Usa discriminador NFM sin de-emphasis, squelch ni filtros de voz, PCM mono de al menos 48 kHz. El motor trabaja en un canal sintonizado; no sigue trunking, no controla el SDR y no se configuran claves. El registro aparece en pantalla. La voz se guarda temporalmente como WAV y se puede reproducir o exportar al detener. Máximo 30 minutos por sesión; una transmisión cifrada no implica voz inteligible.
- En Satélites actualiza la copia orbital para conservar BSTAR, selecciona pase e indica la frecuencia nominal de bajada. El mapa muestra desplazamientos Doppler de AOS/LOS: sintonía recibida = nominal + desplazamiento. No se aplica al SDR automáticamente. Los elementos antiguos sin BSTAR exigen actualización; los pases siguen dependiendo de la edad de la órbita y no confirman disponibilidad del transmisor.

## Procedencia y distribución

Fuentes MIT fijadas, avisos individuales conservados:

- SatelliteKit `9a87cdb80344f26e81bc5fc82fdf9a3350478603`.
- ft8_lib `9fec6ca39886edbf96f4f5e71edc76da5074e871`.
- CWKit `021e4d6e35a9f51d50e1446e6e5b726551814121`.
- libacars `9af09a0121d4ec577339cbd4c7420d7519da48fa` (2.2.1).

Cada directorio Vendor incluye licencia, manifiesto de hashes y cambios locales. El bundle incluye sus archivos de fuentes y avisos. libacars se enlaza al helper GPL-2.0 de acarsdec; el archivo ACARS-Sources incluye ambas fuentes y la receta de construcción. FT8/CW usan procesos separados.

DSD-neo no se redistribuye ni se sube al repositorio. La app descarga el DMG oficial v2.10.0, exige SHA-256 `260e7aaaa02301dbfce2fb1d7492e3e0be4e64f6f654059e5d52f2c4f5131a58`, lo monta en solo lectura y conserva el runtime con sus licencias en `~/Library/Application Support/RadioWorkbench/Engines/dsd-neo-2.10.0`. Una huella distinta impide la instalación. No hay descarga o actualización silenciosa. La versión está fijada y no se instala automáticamente una nueva. El ejecutable oficial informa commit `ff5843f` y MBElib-neo 2.1.0; su cabecera Mach-O declara mínimo macOS 26.0. Las licencias del runtime se encuentran en su carpeta `share/doc/dsd-neo` y las fuentes en el proyecto oficial.

## Validación y límites

Las pruebas cubren FT8/FT4 sintéticos y silencio, ambos CWKit con texto conocido, ADS-C completo/fragmentado/huérfano, exportación, referencia orbital de [Vallado/CelesTrak](https://celestrak.org/publications/AIAA/2006-6753/), Doppler y compatibilidad con caché anterior. DSD se comprueba con un paquete M17 sintético y audio M17/Codec2 generado sin emisión RF. Esto no certifica todos los protocolos DSD en condiciones reales. No se realizó captura nueva de micrófono ni SDR++/VB-Cable en esta actualización.
