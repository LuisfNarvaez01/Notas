# Compilar y distribuir Hilva

SDK probado: Flutter 3.47.7 / Dart 3.13.5. Actions utiliza únicamente runners estándar; el flujo compila y adjunta artefactos y **no publica Releases**. Ejecutar CI solo en el repositorio público LuisfNarvaez01/Notas para mantener el presupuesto previsto.

## Firma Android estable

Ejecutar una sola vez con Java/keytool disponible:

```powershell
./scripts/create-signing-key.ps1
./scripts/build-release.ps1 -Platform android
```

Respaldar privadamente android/hilva-release.jks y android/key.properties. Están ignorados por Git; perderlos impide actualizar instalaciones existentes. No generar otra identidad para cada compilación. Release falla si no existe firma configurada y nunca usa la clave debug. El APK conserva dev.hilva.hilva; aumentar versionCode y versión en pubspec.yaml.

CI necesita secretos HILVA_KEYSTORE_BASE64 (el mismo almacén), HILVA_STORE_PASSWORD, HILVA_KEY_PASSWORD y HILVA_KEY_ALIAS. No poner tokens ni claves en Dart, logs o commits.

## Windows portable

```powershell
./scripts/build-release.ps1 -Platform windows
```

El ZIP contiene todo Release (exe, DLL, data y update-windows.ps1). No distribuir el exe solo. El runtime Microsoft Visual C++ puede requerir instalación en una máquina limpia: validar antes de distribuir. Binarios sin firma comercial pueden mostrar SmartScreen.

La app registra hilva:// para el usuario actual, en la ruta del ejecutable actual, sin admin. Si se mueve el portable, abrirlo de nuevo registra su nueva ruta. El plugin app_links 7.2.2 recibe el enlace inicial y reenvía enlaces a la instancia abierta mediante SendAppLinkToInstance. Permitir hilva://login-callback/ en Supabase. Probar OAuth real con configuración del proyecto antes de darlo por validado.

Ctrl+Shift+H abre captura; si otro programa ocupa ese atajo puede no registrarse. Minimizar oculta en bandeja; cerrar sale. Menú de bandeja: abrir, capturar, salir. NativeService.setAutoStart permite la preferencia opcional de inicio (HKCU Run); la UI debe solicitarla al usuario.

## Release y actualización

Publicar manualmente una versión estable vX.Y.Z con hilva-android.apk, hilva-windows.zip y un único SHA256SUMS que combine ambas líneas de hash. Los workflows entregan un SHA256SUMS por plataforma: combinarlos, no sobrescribir uno con el otro.

La app consulta Releases/latest sin token. No instala prereleases ni versiones iguales/anteriores. La descarga se limita a 512 MB, se guarda primero como .part y se comprueba SHA256 antes de ofrecer instalación. **SHA256SUMS no tiene firma independiente**: protege integridad, no prueba procedencia ante compromiso de la cuenta GitHub. Manifiesto firmado sigue pendiente.

Android usa FileProvider limitado a updates/ y abre el instalador del sistema con confirmación. Puede requerir habilitar “instalar apps desconocidas” para Hilva; volver a intentar tras concederlo. Nunca instalación silenciosa.

Windows ejecuta el helper solo tras confirmación de UI y guardado. El helper revisa hash y rutas del ZIP, extrae a staging junto al portable, espera cierre y sustituye con backup completo del directorio anterior. Si falla el segundo movimiento, restaura el anterior. Conserva backup para recuperación; si el arranque nuevo falla después de lanzarlo, restaurar manualmente el backup. No detecta salud del nuevo proceso. Los datos de usuario deben estar en ApplicationSupport, fuera del portable. El directorio padre debe permitir escritura.

## Captura Android

Widget de pantalla principal abre captura; compartir texto/enlaces y hasta 12 imágenes copia archivos privados (25 MB por imagen). Suscribir NativeService.onCapture y onImages antes de consumir initialText e initialImages. Las imágenes son rutas locales persistentes. El permiso de micrófono se solicita mediante record al grabar. No hay notificación persistente en esta entrega.

## Comprobación en dispositivos pendiente

Probar APK v1→v2 con mismo certificado, cancelación de instalador, descarga cortada, hash incorrecto, desconocidos deshabilitado, compartir desde redes, imágenes y widget tras muerte del proceso. Probar Windows limpio, bandeja, atajo ocupado, OAuth con app abierta/cerrada, actualización con espacios en la ruta, recuperación y conservación de SQLite/adjuntos/claves. Estas pruebas necesitan dispositivos, releases y credenciales reales; no se sustituyen por compilar.
