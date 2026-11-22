# Hilva 1.1.1

## Cambios

- Selección múltiple por botón, pulsación larga y casillas. Copiar todas respeta los filtros visibles; Copiar selección conserva el orden mostrado. Solo copia el cuerpo de las notas (título si no hay cuerpo), separado por líneas en blanco.
- Sincronización al iniciar, cada 5 minutos después del intercambio y al reanudar si pasó ese intervalo. Guardar una nota no sincroniza inmediatamente. El botón manual sigue disponible. Actualiza ambos dispositivos para retirar el temporizador antiguo.
- Probar y guardar valida una respuesta real, guarda la clave y el modelo y activa el proveedor verificado. Una prueba fallida no reemplaza la clave guardada. Se detectan claves pegadas en el proveedor equivocado y se limpian comillas, prefijo Bearer y caracteres invisibles.
- Las configuraciones nuevas usan GPT-OSS 20B en Groq y Gemini 2.5 Flash-Lite. Las elecciones guardadas se conservan. Si el modelo anterior perdió acceso, elegir uno del catálogo y probarlo.
- Elegir modelo consulta el catálogo actual de Groq/Gemini. El catálogo no garantiza acceso o cuota: se comprueba al probar el modelo. Se distinguen HTTP 400/401/403/404/429 y algunas restricciones concretas sin mostrar respuestas arbitrarias que puedan contener secretos.
- La prueba Gemini tiene presupuesto de salida suficiente y desactiva el razonamiento opcional de Flash 2.5. No envía notas ni contexto del proyecto.
- Windows prepara y verifica el paquete antes de cerrar la aplicación. PowerShell arranca oculto con handles válidos, desde una carpeta temporal y con sus módulos propios. Conserva la instalación anterior y registra fallos visibles desde Ajustes.

## Verificación

- 26 pruebas Flutter: IA con respuestas HTTP controladas, persistencia y selección del proveedor probado, selección/copia, sincronización cifrada y conservación de datos.
- Análisis estático sin incidencias; capturas de interfaz a 390 y 1280 píxeles.
- Reproducción del fallo anterior: mover la carpeta usada como directorio de trabajo falla por estar en uso. También se reprodujo el cierre silencioso de PowerShell 5 al iniciarlo con `ProcessStartMode.detached` desde Dart.
- `scripts/test-windows-update.ps1` usa un padre Dart real con directorio de trabajo dentro del portable, rutas con espacios, reemplazo por hash y arranque del nuevo ejecutable. También comprueba que un ZIP corrupto falla antes de cerrar el padre o modificar la instalación.
- Las pruebas de inferencia exitosa usan HTTP simulado; una clave inválida/restringida requiere corregirla en el proveedor. No se valida una cuenta por el solo hecho de que el código compile.

## Actualizar desde 1.1.0

Android: actualizar desde Ajustes o instalar el nuevo APK encima del existente; no desinstalar. Se mantiene el certificado y aumenta `versionCode` a 3.

Windows: si el actualizador antiguo solo cierra Hilva, cerrar también desde la bandeja, extraer el ZIP completo en una carpeta nueva y ejecutar `hilva.exe`. Las notas y el vínculo están en AppData. Si se usa inicio automático, desactivarlo y volver a activarlo desde esa nueva ubicación. La corrección del actualizador se aplica a las siguientes actualizaciones.

Fuentes de los contratos de API: [modelos de Groq](https://console.groq.com/docs/models), [errores de Groq](https://console.groq.com/docs/errors), [modelos de Gemini](https://aistudio.google.com/api-reference/models).

Modelos predeterminados revisados contra [retiros de Gemini](https://aistudio.google.com/docs/deprecations) y [límites de Groq](https://console.groq.com/docs/rate-limits); el antiguo Gemini 2.5 Flash tiene acceso limitado a usuarios anteriores.
