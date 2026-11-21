# Hilva 1.1

Notas personales con IA para Android y Windows. Captura local, proyectos, contexto y sincronización cifrada entre dos dispositivos en la misma red, sin cuentas ni nube.

## Uso
En ambos equipos abre Ajustes. En Windows pulsa Mostrar QR y escanéalo en Android. El vínculo queda guardado. La sincronización se repite cada 10 segundos mientras Hilva está activa. Android puede suspenderla en segundo plano; se retoma al abrir. Si cambia la IP del PC, vuelve a vincular. Permite Hilva en el firewall solo en redes privadas.

Las claves de Groq y Gemini se guardan por dispositivo. Probar conexión hace una petición pequeña al modelo configurado, sin enviar notas y consumiendo una pequeña parte de la cuota.

## Límites de esta versión
Una pareja de dispositivos. Sin descubrimiento multicast; QR/código contiene dirección local. Hasta 20 MB por adjunto y 45 MB de adjuntos en un intercambio completo. Ediciones simultáneas se conservan como conflictos. Los datos locales existentes se mantienen al actualizar.

## Desarrollo
flutter pub get
flutter analyze
flutter test
flutter run -d windows

## Actualización
APK firmado con la misma identidad y versionCode 2. Windows portable debe conservar todas sus DLL y carpeta data. GitHub Releases distribuye paquetes y SHA256SUMS. Ver docs/RELEASE.md.

## Dependencia adaptada
third_party/flutter_secure_storage_windows conserva licencia upstream 4.2.2. Conversiones ATL reemplazadas por equivalentes Win32 CP_ACP para compilar sin ATL; conserva Credential APIs.
