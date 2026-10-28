# RAZIEL 0.17.0 · estabilización e identidad / stabilization and identity

## Español

RAZIEL es el nuevo nombre de RadioWorkbench. La versión 0.17.0/build 33 conserva el identificador de aplicación, los directorios de datos, preferencias, perfiles y la clave pública de actualización. No es una instalación con bibliotecas vacías ni convierte audio existente.

- Icono blanco/negro, ICNS con tamaños macOS, portada bilingüe y símbolos de documentación. Crédito visible: **Creado por Sebastián Pastén F.**
- Cuatro paletas de acento en Ajustes: Grafito, Petróleo, Bosque y Ámbar, con adaptación clara/oscura. Se guardan por separado para conservar el documento de preferencias 0.16; también se incluyen en el respaldo manual.
- En General, apoyo voluntario en Ko-fi y GitHub. No hay contenido web incrustado ni contacto automático con Ko-fi al abrir Ajustes.
- El espectro rechaza tasas no finitas, negativas, nulas o fuera del rango de audio admitido antes de convertir tamaños a entero. La vista usa un eje seguro para un resultado sin espectro. Se elimina un cálculo RMS redundante cuyo resultado no se utilizaba; las medidas válidas siguen procediendo de `AudioBlockQuality`.
- NOAA muestra fechas UTC según el idioma elegido. Una probabilidad ausente/inválida se muestra como desconocida y una tabla Kp incompleta no inventa un cero. El parser rechaza porcentajes fuera de 0–100.
- Traducciones de modos de voz/tonos, condiciones pobres, regiones VHF y confianza ionosférica; etiquetas accesibles de coordenadas en el idioma activo. Las notas y datos originales de fuentes externas se conservan.

Las medidas de CPU se limitan al raster y al cálculo de espectro sintético: no son FPS de pantalla, consumo de batería ni latencia RF→altavoz. No se fuerza Metal donde no se ha demostrado una ventaja. Instrumentos/xctrace no está instalado en el toolchain disponible; no se afirma un perfil Instruments.

Esta publicación estabiliza la interfaz y rutas revisadas; los modos experimentales y límites de los modelos de propagación siguen identificados en el README. No supone validación física universal ni vuelve actuales los satélites NOAA APT históricos. macOS 14+ arm64; CWKit requiere 15 y DSD-neo opcional, 26. Firma ad hoc, sin Developer ID ni notarización.

[Validación final](validation/release-0.17.0.json) · [Identidad](BRAND.md) · [Ajustes y recuperación de biblioteca](RELEASE-0.16.0.md).

Gracias a **G4ZJH** por su aporte e idea de español/inglés. [Apoyo voluntario en Ko-fi](https://ko-fi.com/C0C51WQ1T0).

## English

RAZIEL is the new name of RadioWorkbench. Version 0.17.0/build 33 preserves the bundle identifier, data directories, preferences, profiles and update public key. Existing audio is not converted and libraries are retained.

- Black/white app icon, macOS ICNS sizes, bilingual cover, documentation symbols and creator credit.
- Graphite, Petroleum, Forest and Amber control-accent palettes with light/dark variants. A separate preference key preserves compatibility with 0.16 settings; the selected palette is included in manual backups.
- Voluntary Ko-fi support and GitHub links in General, without an embedded web view or automatic service contact.
- Invalid spectrum sample rates are rejected before integer conversion; the view uses a safe empty-spectrum axis. An unused duplicate RMS calculation is removed; valid measurements still come from `AudioBlockQuality`.
- NOAA dates use the selected UI language and UTC. Missing/invalid probabilities remain unknown, incomplete Kp tables no longer invent zero, and percentages outside 0–100 are rejected.
- Mode/condition/ionosonde translations and coordinate accessibility labels follow the chosen language. Original external-source text remains verbatim.

CPU benchmarks cover synthetic spectrum/raster work only, not display FPS, battery impact or RF-to-speaker latency. Instruments/xctrace is unavailable in the installed toolchain. Metal is not forced without evidence of a benefit.

This release stabilizes the reviewed application paths; experimental decoders and propagation-model limits remain documented. It is not universal physical RF validation. macOS 14+ arm64, CWKit 15+, optional DSD-neo 26+. Ad hoc signature, without Developer ID or notarization.

[Final validation](validation/release-0.17.0.json) · [Identity](BRAND.md) · [Settings and backup recovery](RELEASE-0.16.0.md).

Thanks to **G4ZJH** for the contribution and Spanish/English idea. [Voluntary support](https://ko-fi.com/C0C51WQ1T0).
