# RadioWorkbench 0.8.11 · build 23

Corrige dos defectos reproducibles de POCSAG al activar **Avisos sin texto**.

- Una transmisión completa seguida de silencio generaba capcodes falsos porque una palabra BCH válida podía sustituir al sincronismo periódico. El receptor ahora exige sincronismo después de cada 16 palabras de datos; si falta, descarta el estado incompleto y vuelve a buscar sincronismo. Reinicia los contadores al recuperarlo y conserva el límite BCH configurado.
- Los avisos JSON sin texto quedaban en el búfer de stdout. Esa rama ahora llama a `fflush`. El lector Swift consume los bytes disponibles en el Pipe, sin esperar 8192 bytes o el fin de la entrada. El monitor recoge los resultados asíncronos incluso cuando ya no llegan nuevos bloques de audio, manteniendo el límite de diez actualizaciones por segundo.

Las pruebas usan transmisiones generadas matemáticamente: tres velocidades, ambas polaridades, los ocho frames de dirección, silencio posterior, pérdida/recuperación con cambio de fase, sincronismos dañados y mensajes que cruzan varios bloques. La prueba en vivo mantiene stdin abierto y comprueba que el aviso llega antes de cancelarlo. Un capcode real 0 sigue siendo válido: la corrección comprueba el framing, sin filtrar direcciones por su valor.

`Vendor/MultimonNG/LOCAL-CHANGES.md` documenta el parche frente al commit upstream y el manifiesto conserva los hashes original/modificado. El bundle incluye el código corregido y sus avisos GPL.

[Validación](VALIDACION.md) · [Modos, entrada y límites](DECODIFICADORES-0.8.10.md) · [Cambios del componente](../Vendor/MultimonNG/LOCAL-CHANGES.md).
