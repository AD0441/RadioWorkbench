# Audio local TCP: contrato y comprobación

RadioWorkbench puede actuar como cliente de un flujo de **audio PCM sin
cabecera**, con formato declarado por el usuario. El cliente admite únicamente
los destinos literales `127.0.0.1` y `::1`; la conexión se inicia manualmente.

## Configuración de ambos extremos

Para SDR++Brown en M1, la configuración inicial es TCP, puerto 7355, 48.000 Hz,
un canal y PCM firmado de 16 bits little-endian. En el módulo de salida
**Network** del SDR, elige TCP, el mismo puerto/tasa/canales y activa su servidor
antes de conectar RadioWorkbench. Selecciona también el modo y filtro RF
necesarios para el decodificador.

El [código upstream de Network Sink](https://raw.githubusercontent.com/sannysanoff/SDRPlusPlusBrown/master/sink_modules/network_sink/src/main.cpp)
declara valores iniciales de 48 kHz, mono y puerto 7355, convierte a `int16_t`
y ofrece TCP; su protocolo inicial es UDP, por lo que debe cambiarse
explícitamente. La variante Float32 de RadioWorkbench sirve para otros
productores que declaren ese formato. No se atribuye esa opción al Brown
instalado.

La [revisión de las aplicaciones instaladas](REVISION-APPS-0.10.md) aporta
evidencia estática del módulo Brown. Los ensayos con un servidor local de
prueba comprueban nuestro transporte; una prueba con la app Brown instalada
y una señal de radio sigue siendo una validación independiente pendiente.

## Formatos admitidos

| Campo | Contrato |
|---|---|
| Muestras | `s16le`, normalizado dividiendo por 32768; o `float32le` |
| Tasa | Declarada, entre 4.000 y 384.000 muestras/s por canal |
| Canales | Declarados, 1–32, intercalados por trama |
| Selección | Promedio de canales o un canal concreto; el anillo recibe mono |
| Cabecera | Ninguna; sin negociación ni inferencia de tasa o formato |
| Float32 | NaN/infinito interrumpen la sesión; valores finitos fuera de ±1 se limitan y contabilizan |
| Fragmentación | Se conservan bytes parciales hasta completar todos los canales de la trama |
| Fin incompleto | Error explícito si faltan bytes de una muestra/trama |

Una grabación WAV completa, una fuente I/Q, un servidor `rtl_tcp` o un flujo de
red del receptor no son intercambiables con esta salida de audio. El tipo de
entrada debe coincidir con su productor.

## Recursos, errores y cierre

Se mantiene una sola lectura TCP pendiente, de hasta 65.536 bytes. El parser
retiene como máximo una trama incompleta; el anillo de audio tiene capacidad
fija. Una cola serie es su único productor y el decodificador su único
consumidor. Si este último se atrasa, el contador de muestras descartadas del
anillo lo indica. Ese contador no representa paquetes TCP perdidos.

Se cuentan bytes recibidos, tramas PCM decodificadas, muestras limitadas y
muestras descartadas. El tiempo de conexión inicial es 5 segundos y el límite
sin nuevos datos es 10 segundos. El cierre o un error marca el anillo como
terminado antes del aviso de estado; el decodificador puede consumir el audio
pendiente y finalizar su motor. Una nueva conexión tiene una generación propia
para ignorar avisos tardíos de la anterior. No hay reconexión automática.

## Pruebas incluidas

`NetworkPCMTests.swift` cubre límites de bytes/canales, ambos formatos,
fragmentación muestra a muestra, mezcla/selección, NaN/infinito, limitación,
cola parcial al final y rechazo de destinos remotos. `TCPAudioInputTests.swift`
crea servidores de prueba en loopback para comprobar audio fragmentado,
cierre normal, trama truncada, espera sin datos, desbordamiento del anillo y
cancelación sin avisos de una conexión antigua. No utiliza micrófono ni SDR.

La ejecución final y su resultado se registran en la validación de la versión.
