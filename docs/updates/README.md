# Canal de actualizaciones / Update channel

Sparkle 2.10.0 consulta por HTTPS la rama `updates`, archivo `docs/updates/appcast.xml`. El canal ofrece **0.16.0/build 32**, con el ZIP público de la publicación GitHub y firma Ed25519 del archivo, además de la firma del XML. La aplicación contiene únicamente la clave pública de `public-key.txt`.

La comprobación automática es optativa en **Ajustes → General e idioma**. Descargar e instalar requiere una acción del usuario. El paquete sigue siendo ad hoc, sin Developer ID ni notarización; las firmas Ed25519 no cambian ese estado.

La clave Ed25519 privada permanece en `~/.config/radioworkbench/signing/sparkle.key`, permisos 0600, directorio 0700. Conservar una copia segura: perderla impide publicar para estas instalaciones. Nunca copiarla al proyecto, al bundle o a GitHub.

Para publicar: validar el ZIP final, subir exactamente ese archivo a GitHub, añadir al appcast su URL, tamaño, build y firma usando `sign_update` de la versión fijada, firmar de nuevo el XML y verificar ambas firmas antes de actualizar `updates`. Cualquier cambio del ZIP requiere nueva firma y cualquier modificación del XML, volver a firmarlo. El SHA-256 permite comprobar la descarga; no sustituye la firma. No reemplazar la clave pública sin un plan de migración.

La validación de 0.16 verifica el paquete, la instalación local y las firmas del archivo/canal descargados. No se declara probada una instalación completa mediante Sparkle entre dos publicaciones.

---

Sparkle 2.10.0 uses the HTTPS feed on the `updates` branch, `docs/updates/appcast.xml`. It offers **0.16.0/build 32** using the public GitHub ZIP, an archive Ed25519 signature and a separate signed XML feed. Only the public key is shipped in the application.

Automatic checks are opt-in under **Settings → General and language**. Downloading/installing requires user action. The app remains ad hoc signed, without Developer ID or notarization. Archive/feed signatures do not alter that distribution status.

The private publishing key stays outside Git and the bundle. Validate/upload the final ZIP, include its URL/length/build/signature, re-sign XML after every change and verify both signatures before updating the branch. SHA-256 is an additional download check, not a replacement for signatures. The 0.16 checks do not claim an end-to-end installation through Sparkle between two published versions.
