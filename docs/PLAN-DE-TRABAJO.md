# Trabajo acordado · actualizado 18 de octubre de 2026

Este documento conserva el alcance solicitado; una propuesta no se marca como función terminada.

## Correcciones y revisión en curso

- [x] MT63 en seis variantes y ALE 2G: fuentes, pruebas, ejemplos, paquete 0.10.0 y comprobación de interfaz. Falta incorporar los cambios al PR existente al cerrar la siguiente revisión.
- [x] Reparar Guía de radios → Planificador HF: selección persistente, envío directo, datos parciales, procedencia y campos pendientes visibles.
- [x] Auditar cálculo HF: unidades, dirección TX/RX, índices solares, condiciones por hemisferio, supuestos y pruebas de referencia.
- [x] Comparar DMR de SDR++Brown con DSD-neo: arquitectura, slots, CC y límites documentados. Se aplicaron biblioteca, diagnóstico y entrada TCP de discriminador. Voz DMR continua, selector de slots y panel de llamada quedan para una fase con corpus DMR independiente.

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

La comprobación visual 0.11 está pendiente: CUA informó Mac bloqueado y se pidió desbloquearlo. La ejecución LRPT con captura independiente, la interoperabilidad real Brown TCP y la prueba física SDR++/VB-Cable permanecen pendientes; las pruebas de red local no sustituyen esas comprobaciones.
