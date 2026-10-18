# Trabajo acordado · actualizado 18 de octubre de 2026

Este documento conserva el alcance solicitado; una propuesta no se marca como función terminada.

## Correcciones y revisión en curso

- [x] MT63 en seis variantes y ALE 2G: fuentes, pruebas, ejemplos, paquete 0.10.0 y comprobación de interfaz. Cambios incorporados al PR existente durante el cierre de 0.11.0.
- [x] Reparar Guía de radios → Planificador HF: selección persistente, envío directo, datos parciales, procedencia y campos pendientes visibles.
- [x] Auditar cálculo HF: unidades, dirección TX/RX, índices solares, condiciones por hemisferio, supuestos y pruebas de referencia.
- [x] Comparar DMR de SDR++Brown con DSD-neo: arquitectura, slots, CC y límites documentados. Biblioteca, diagnóstico y entrada TCP de discriminador en 0.11; voz DMR durante recepción, selector de síntesis y panel por intervalo en 0.12. Falta contraste con dos llamadas simultáneas y recepción física.

## Revisión y DMR · 0.12

- [x] Guía: selección BBC de 9410 kHz y ficha observadas; el usuario confirmó BBC, 9,410 MHz y Escucha tras el envío directo al planificador. El control de pantalla falló al abrir esa vista.
- [x] DMR: runtime oficial con una grabación independiente TS1; origen/destino/clase coinciden con el oráculo público. CC7 observado, sin oráculo independiente para ese campo.
- [x] Voz DMR durante la recepción, TS1/TS2/ambos y panel con procedencia y antigüedad, conservando WAV.
- [ ] Terminar el recorrido visual de biblioteca, DSC, mapas y otras herramientas en la nueva compilación.
- [ ] Corpus identificado con dos conversaciones simultáneas y evaluación perceptual de voz; la prueba física sigue aplazada.

## Ampliaciones solicitadas, en este orden

1. [x] Biblioteca de recepciones: audio, ajustes y fecha juntos; volver a decodificar. Después, I/Q/SigMF y comparación de motores.
2. [x] Diagnóstico de entrada y calidad: causas medidas y acciones útiles; después, pruebas guiadas de conexión.
3. [x] Audio TCP local desde SDR++Brown: formato explícito y conexión elegida por el usuario; después, UDP y pérdidas.
4. [x] DSC marítimo MF/HF y VHF: mensajes validados y exportación; después, áreas y contexto marítimo.
5. [x] Mapa común: origen, antigüedad y trazas de las posiciones disponibles; después, AIS/RS41 y avisos optativos.
6. [x] SatDump offline para LRPT: archivo I/Q identificado, progreso/cancelación y productos; después, preparación de pasadas e I/Q de red.
7. [x] Sintonía optativa desde consultas: verificar Rigctl y enviar frecuencia/modo/ancho mediante acción explícita; después, Doppler probado.
8. [x] Adaptadores de eventos externos: formato validado con procedencia y límites; después, NMEA/telemetría por protocolo.
9. [x] Taller de aprendizaje: señal de referencia, espectro y parámetros; después, ejercicios CW y clasificación con incertidumbre.

La prueba física SDR++ → VB-Cable sigue aplazada. Se puede avanzar con WAV, fuentes sintéticas, conexiones locales simuladas y capturas públicas identificadas. Se conserva la distinción entre audio de discriminador, voz ya decodificada e I/Q.

## Cierre de la primera fase 0.11.0

Los nueve primeros resultados están implementados y documentados en [NUEVE-MEJORAS.md](NUEVE-MEJORAS.md), con sus límites. Las ampliaciones «Después» de cada punto siguen pendientes; no se marcan como implementadas. Suite Release: 202 funciones, 198 aprobadas, cuatro opcionales omitidas, cero fallos; 21 comprobaciones C HF y 18 DSC repetidas con ASan/UBSan. ZIP extraído, firma estricta, arm64, fuentes y ejemplos verificados.

Tras desbloquear el Mac se comprobó la apertura de 0.11.0, las nuevas entradas de navegación, los parámetros TCP y el diagnóstico de entrada. La herramienta SkyComputerUseService se cerró al cambiar de modo y volvió a fallar tras reconectarse; RadioWorkbench permaneció activa y no apareció un nuevo informe de cierre de la app. La revisión interactiva de los demás flujos, incluida Guía → HF, sigue pendiente; [observaciones y diagnóstico](validation/ui-0.11.0.json). La ejecución LRPT con captura independiente, la interoperabilidad real Brown TCP y la prueba física SDR++/VB-Cable permanecen pendientes; las pruebas de red local no sustituyen esas comprobaciones.
