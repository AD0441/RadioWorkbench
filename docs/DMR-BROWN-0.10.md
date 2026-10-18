# DMR de SDR++Brown y mejoras para RadioWorkbench

**Actualización 0.11:** ya se incorporaron biblioteca de audio/ajustes, diagnóstico y entrada TCP local con formato explícito. La voz DMR continua, el selector TS1/TS2 y un panel estructurado de llamadas siguen pendientes de corpus y validación independientes; no se sustituyó DSD-neo por el plugin Brown.

Revisión: 18 de octubre de 2026. **Brown incorpora un decodificador de voz digital dentro de su receptor SDR. RadioWorkbench ya ofrece DMR mediante DSD-neo; la mejora más útil es escuchar la voz durante la recepción y mostrar con claridad el estado de cada intervalo DMR.** No se ha incorporado código de Brown ni se ha validado una recepción DMR real en esta investigación.

## Qué se comprobó

Se reutilizó el inventario REA de SDR++Brown y se revisaron símbolos, textos y fuentes públicas concretas. No se volvió a inventariar toda la aplicación, no se abrió su interfaz ni se capturó audio o RF.

| Evidencia | Identidad y límite |
|---|---|
| Copia instalada | SDR++Brown 1.2.1, arm64; texto interno de compilación del 4 de julio de 2025 |
| Plugin distribuido | `Contents/Plugins/ch_extravhf_decoder.dylib`, 1180104 bytes, SHA-256 `80cd38686ef6a8d678a61b179715d8a5aa18b902e3902d36fa39c7bbbb479e67` |
| Inventario REA reutilizado | `ev_5d5f90d7e7d189b9116349ec7f6708d49a638e4a4db940bedd2deb79ea4bcf63`; manifiesto `agm_4f17f629d3f496b8edde4a3d723d27dc7f5865649e27d6085f4d258e8b360739` |
| Fuentes Brown consultadas | Commit `5fca05446b3f985ab49c7c3c257980aaf2ec34fe`, fechado el 12 de agosto de 2026; **posterior a la compilación instalada**, sin correspondencia exacta demostrada |
| DSD-neo de RadioWorkbench | Runtime oficial 2.10.0, descarga separada fijada por SHA-256; su ejecutable exige macOS 26. La app principal permanece en macOS 14+ |

Los símbolos del plugin incluyen `dsp::NewDSD::processDMRdata`, `processDMRvoice`, `processMbeFrame`, el DSD anterior y funciones AMBE/IMBE de mbelib. Los textos incluyen DMR, SLOT0, SLOT1, CC y errores MBE. Eso acredita componentes distribuidos y etiquetas; no mide su calidad ni demuestra qué modo está activo. Las funciones P25 son de **fase I**: que un nombre mencione IMBE no significa «P25 fase II».

El [resumen de evidencia](app-evidence-0.10/dmr-brown-summary.json) conserva nodos, hashes, revisión de fuentes y búsquedas negativas acotadas. Los resultados REA completos se mantienen localmente en la carpeta ignorada de evidencia; los identificadores anteriores no corresponden a una ejecución del decodificador.

## Cómo obtiene voz Brown

El [módulo principal](https://github.com/sannysanoff/SDRPlusPlusBrown/blob/5fca05446b3f985ab49c7c3c257980aaf2ec34fe/decoder_modules/ch_extravhf_decoder/src/main.cpp) añade dos demoduladores al módulo Radio: `DSD` y `oldDSD`. El [README del componente](https://github.com/sannysanoff/SDRPlusPlusBrown/blob/5fca05446b3f985ab49c7c3c257980aaf2ec34fe/decoder_modules/ch_extravhf_decoder/README.md) atribuye su origen a [cropinghigh/sdrpp-vhfvoiceradio](https://github.com/cropinghigh/sdrpp-vhfvoiceradio). Se conserva su licencia GPL-3.0; la nota del autor no sustituye las licencias del componente y sus dependencias.

En la fuente fijada, la ruta nueva es:

```text
Canal I/Q → discriminador FM → bloqueo DC → filtro RRC
          → recuperación de reloj → decisión de cuatro niveles
          → sincronía/tramas DMR → AMBE/mbelib → voz PCM a 8 kHz
```

El [adaptador DSD](https://github.com/sannysanoff/SDRPlusPlusBrown/blob/5fca05446b3f985ab49c7c3c257980aaf2ec34fe/decoder_modules/ch_extravhf_decoder/src/demodulators/dsd.h) solicita I/Q a 9600 muestras/s y recupera 4800 símbolos/s. Bloquea el ancho predeterminado en 12,5 kHz, desactiva de-emphasis, reducción de ruido IF y noise blanker. El gráfico muestra muestras y umbrales del decisor; no es un medidor calibrado de potencia RF.

La [ruta antigua](https://github.com/sannysanoff/SDRPlusPlusBrown/blob/5fca05446b3f985ab49c7c3c257980aaf2ec34fe/decoder_modules/ch_extravhf_decoder/src/demodulators/olddsd.h) convierte I/Q a FM, bloquea DC y entrega PCM entero de 16 bits a 48 kHz al DSD legado. Ambas devuelven voz a 8 kHz, convertida después a float y duplicada a estéreo para la salida de SDR++. En la [etapa de vocoder](https://github.com/sannysanoff/SDRPlusPlusBrown/blob/5fca05446b3f985ab49c7c3c257980aaf2ec34fe/decoder_modules/ch_extravhf_decoder/src/dsp/dsd_demod.cpp), DMR usa la función AMBE 3600×2450 y P25 fase I la función IMBE 7200×4400.

**Si Brown ya está en DSD y entrega habla comprensible a VB-Cable o Network Sink, RadioWorkbench recibe voz ya decodificada.** Ese audio no conserva el flujo DMR necesario para obtener de nuevo slots, CC o mensajes de señalización. Para usar nuestro DSD-neo, SDR++ debe entregar el discriminador NFM del canal antes del vocoder, sin squelch ni procesamiento de voz, o proporcionar una ruta I/Q específica.

## Qué significan SLOT0, SLOT1 y CC

DMR permite dos canales lógicos alternados en una misma frecuencia de 12,5 kHz. Los intervalos duran 30 ms y forman una trama de 60 ms. Brown los indexa como `0` y `1`; la terminología habitual de usuario es **TS1 y TS2**. Son intervalos de tiempo, no dos frecuencias, y pueden transportar conversaciones o datos distintos. [DMR Association](https://dmrassociation.org/dmr-key-benefits.html), [ETSI TS 102 361-1](https://www.etsi.org/deliver/etsi_ts/102300_102399/10236101/02.06.01_60/ts_10236101v020601p.pdf).

La [implementación DMR](https://github.com/sannysanoff/SDRPlusPlusBrown/blob/5fca05446b3f985ab49c7c3c257980aaf2ec34fe/decoder_modules/ch_extravhf_decoder/src/dsp/dsd_dmr.cpp) toma el índice del CACH y mantiene el último tipo de ráfaga de cada intervalo: voz, cabecera de voz, datos, CSBK, idle, entre otros. El código de color es un campo separado de cuatro bits; no es el talkgroup ni el identificador del emisor. El adaptador no presenta un selector de escucha de slot: mostrar ambos estados no acredita dos conversaciones reproducidas por separado.

Hay dos límites relevantes al interpretar el panel de esa revisión de fuentes:

- El [estado DMR](https://github.com/sannysanoff/SDRPlusPlusBrown/blob/5fca05446b3f985ab49c7c3c257980aaf2ec34fe/decoder_modules/ch_extravhf_decoder/src/dsp/dsd.h) expone CC y tipos de ráfaga. Sus campos `SRC`, `TG`, `ALGID` y `KID` pertenecen al estado **P25**. No deben atribuirse a DMR.
- La fuente del panel imprime junto a `CC` el tipo numérico de la última ráfaga del segundo intervalo y después el código de color. No son dos códigos de color. Esta observación corresponde a la fuente; no se comprobó visualmente el binario instalado.

Reconocer sincronía o invocar el vocoder no garantiza habla inteligible. Los errores, el desvanecimiento y el cifrado pueden impedirla. En los archivos DMR/MBE inspeccionados no se encontró una ruta de configuración de claves ni descifrado DMR; se identifican cabeceras, pero no se acredita descifrado. Tampoco se demostró una detección fiable de cifrado DMR en esa interfaz.

## API de Brown: disponible en fuente, no confirmada en esta copia

La fuente reciente añade los comandos de depuración `get_dmr_status` y `wait_dmr_sync_voice`. Devuelven JSON con sincronía, DMR, actividad del vocoder, CC, tipos por slot y texto de errores MBE. Su condición `voice` combina indicadores de sincronía y vocoder: no evalúa si una persona entiende el audio.

Los nombres de esos comandos y de sus accesores no aparecieron en la búsqueda literal realizada sobre textos y exportaciones conservados del plugin instalado. Esa búsqueda tiene alcance limitado y no demuestra ausencia universal. Con la diferencia de fechas entre fuente y binario, **no se ofrece esa API como una conexión ya utilizable por RadioWorkbench**.

## Comparación con la integración actual

| Aspecto | Brown: evidencia de fuente | RadioWorkbench: implementación actual |
|---|---|---|
| Captura | El receptor controla el canal I/Q antes del demodulador | Entrada seleccionada o archivo; conversión a PCM16 mono de 48 kHz |
| Motor | NewDSD y DSD legado integrados en el plugin | DSD-neo 2.10.0, proceso separado, modo DMR `-fs` |
| Voz | El grafo entrega audio mientras procesa | Se guarda WAV; reproducción y exportación al detener o terminar |
| Estado | Sincronía, tipo de ráfaga por slot, CC, errores MBE | Monitor textual; sin modelo estructurado propio de llamadas/slots |
| Otros protocolos | La presencia de código y etiquetas no valida cada variante | Selecciones P25 I/II, NXDN, D-STAR, YSF, M17 y dPMR; la validación previa cubre M17 sintético, no DMR RF |
| Integración | Acoplado al núcleo, flujos y GUI de SDR++ | Transporte y cancelación propios; el runtime oficial requiere macOS 26 |

El contrato actual puede revisarse en `ExternalAudioEngine.swift` y `AdditionalAudioDecoders.swift`; los límites de validación están en [INTEGRATIONS-0.9.md](INTEGRATIONS-0.9.md).

## Mejoras concretas que conviene hacer

1. **Voz en vivo dentro de RadioWorkbench.** DSD-neo documenta `-o -` para PCM decodificado por stdout y salida UDP alternativa. Para DMR hay que comprobar formato, tasa y canales reales antes de crear una cola de reproducción; separar audio binario y mensajes diagnósticos. Mantener el WAV exportable. [Contrato de audio 2.10.0](https://github.com/arancormonk/dsd-neo/blob/v2.10.0/docs/network-audio.md).
2. **Escuchar TS1, TS2 o ambos.** La CLI 2.10.0 ofrece `-V 1`, `-V 2` y `-V 3` para síntesis de voz; `-z 0/1/2` expresa preferencia de slot. No son el mismo control. `-fs` usa el receptor de dos slots y `-fr` el receptor mono de un slot. Validar la correspondencia con un archivo identificado antes de añadir los controles. [Guía CLI](https://github.com/arancormonk/dsd-neo/blob/v2.10.0/docs/cli.md).
3. **Panel de llamada comprensible.** Mostrar buscando/sincronizado, voz/datos, CC, slot, grupo, emisor, errores y antigüedad solo cuando el motor entregue cada dato. El registro `-J` es texto de eventos; no se ha acreditado una salida JSON CLI general. Para datos tipados, estudiar un adaptador sobre los snapshots públicos de DSD-neo: exigen un único consumidor y sus últimos valores pueden sobrevivir al paro. [Contrato de snapshots](https://github.com/arancormonk/dsd-neo/blob/v2.10.0/include/dsd-neo/app_control/snapshot.h).
4. **Diagnóstico y reproducción verificable.** Conservar un WAV de discriminador identificado y sus ajustes; probar un slot por vez, dos slots, datos, silencio, ruido, señal débil, fin abrupto y cancelación. La CLI permite trazas de ráfagas y eventos, pero el indicador de cifrado debe proceder de señalización validada; una voz distorsionada no basta.
5. **Audio TCP local desde SDR++.** Es una alternativa al cable virtual si entrega el discriminador, con el formato PCM acordado. Empezar por conexión explícita de solo recepción y aviso de desconexión. La sintonía por Rigctl y el seguimiento trunking serían una etapa posterior, con configuración visible y pruebas propias; no se activan como consecuencia de recibir DMR.

Antes de reemplazar el motor, conviene ampliar la presentación y la reproducción de DSD-neo, que ya está integrado. Un helper alternativo para macOS 14/15/26 podría estudiarse compilando una revisión mantenida con dependencias fijadas; esta investigación no produjo ni validó ese port. Copiar el plugin Brown arrastraría su acoplamiento SDR++/ITPP/mbelib y no elimina ese trabajo.

## Qué queda abierto

No se midieron sensibilidad, errores de voz, estabilidad ni consumo M1 de ninguno de los receptores DMR. Falta un corpus DMR independiente con slots e identificadores conocidos, comprobar APIs en la versión instalada y verificar la reproducción continua de DSD-neo. Ninguna de las propuestas anteriores está integrada por este informe.
