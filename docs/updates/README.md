# Canal de actualizaciones

Sparkle 2.10.0 usa el canal HTTPS de la rama `updates`, archivo `docs/updates/appcast.xml`. La aplicación incluye únicamente la clave pública de `public-key.txt`. El canal inicial no tiene enclosures: una comprobación no ofrece una versión inexistente.

La clave Ed25519 privada reside en `~/.config/radioworkbench/signing/sparkle.key`, permisos 0600, directorio 0700. Conservar una copia segura: perderla impide publicar para estas instalaciones. Nunca copiarla al proyecto, al bundle o a GitHub.

Para preparar una publicación futura, crear y validar primero el ZIP final, subir ese artefacto a una publicación GitHub y añadir su URL, tamaño, versión interna y firma mediante las herramientas oficiales `sign_update`/`generate_appcast` de la misma versión de Sparkle. Firmar de nuevo el XML después de cualquier modificación y verificarlo antes de actualizar la rama `updates`. El ZIP, el appcast y la app requieren firmas distintas: firmar el appcast no firma el ZIP ni notariza la aplicación.

No reemplazar la clave pública sin un plan de migración y no añadir enclosures de archivos que no estén publicados y verificados. La instalación completa de una actualización futura requiere una prueba entre dos versiones firmadas y publicadas; esta entrega comprueba el canal inicial y el empaquetado local.
