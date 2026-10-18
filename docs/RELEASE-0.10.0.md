# RadioWorkbench 0.10.0 · build 25

La nueva compilación añade dos receptores pendientes: **MT63 500/1000/2000 Hz con entrelazado corto/largo** y **ALE 2G** para sondeos, llamadas y AMD. Funcionan desde la entrada de audio seleccionada o un archivo, con remuestreo a 8 kHz, ejemplos incluidos y exportación de texto/JSON. Se conservan los modos e integraciones anteriores.

MT63 usa un subconjunto fijado del DSP de fldigi; ALE usa el decodificador standalone de KiwiSDR. Ambos helpers son arm64 y declaran macOS 14 mínimo. Las licencias GPL, las revisiones, los hashes y las fuentes/adaptadores correspondientes se incluyen en el bundle. No requieren instalar fldigi, GNU Radio, Qt ni FFTW globalmente.

El control MT63 permite elegir las seis variantes y el centro de audio. La guía RF y los límites de banda cambian junto con ese centro. La adquisición y el entrelazado tienen latencia; 500 Hz/largo puede tardar más de 20 s y perder el inicio de emisiones cortas. ALE necesita conservar los ocho tonos de 750–2500 Hz en USB. No se presenta sincronía como SNR ni se atribuye CRC de mensaje a ninguno de los dos modos.

**Pruebas:** 159 funciones registradas, 155 aprobadas y cuatro opcionales omitidas; sin fallos. Incluye WAV estéreo a 48 kHz, canal derecho, recepción simulada con la entrada abierta y ajustes antiguos. Los sanitizadores detectaron y permitieron corregir errores heredados de memoria/índices en MT63. ALE se contrastó con dos grabaciones públicas; MT63 sigue pendiente de una grabación independiente. No se probó micrófono ni SDR++/VB-Cable físicamente en esta pasada.

**Investigación:** se revisaron estáticamente MultiMode Cocoa, AFSK1200 Decoder, SDR++Brown, SatDump y SDRangel usando REA y sus recursos/metadatos. El informe propone biblioteca de recepciones, diagnóstico de señal, audio TCP desde Brown, DSC, mapa común y procesamiento I/Q/LRPT con SatDump. Esas propuestas no están habilitadas como funciones de esta compilación.

**Pendientes originales:** SITOR-A, DSC/GMDSS, DGPS, LORAN-C, Globe Wireless y ALE 3G. Cada uno conserva sus requisitos y límites en el informe. El nuevo código no sustituye esos motores con rótulos o ejemplos simulados.

Distribución local: `dist/RadioWorkbench.app` y `dist/RadioWorkbench-0.10.0-macos-arm64.zip`, firma ad hoc sin notarización. No se ha creado una release pública nueva; la descarga publicada continúa en 0.8.8 hasta que se publique otra versión.

[Uso de los modos](INTEGRATIONS-0.10.md) · [Revisión y propuestas](REVISION-APPS-0.10.md) · [Validación](VALIDACION.md).
