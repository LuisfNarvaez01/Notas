# Hilva 1.1.1

Notas personales con IA para Android y Windows. Captura local, proyectos, contexto y sincronización cifrada entre dos dispositivos en la misma red, sin cuentas ni nube.

## Uso
En ambos equipos abre Ajustes. En Windows pulsa Mostrar QR y escanéalo en Android. El vínculo queda guardado. La sincronización se repite cada 5 minutos mientras Hilva está activa. Android puede suspenderla en segundo plano; se retoma al abrir si ya transcurrió ese intervalo. El botón manual funciona en cualquier momento. Guardar notas ya no provoca un intercambio inmediato. Si cambia la IP del PC, vuelve a vincular. Permite Hilva en el firewall solo en redes privadas.

Las claves de Groq y Gemini se guardan por dispositivo. Probar y guardar hace una petición pequeña al modelo configurado, sin enviar notas y consumiendo una pequeña parte de la cuota. Si funciona, guarda la clave y activa ese proveedor. Elegir modelo consulta el catálogo del proveedor; la prueba comprueba el acceso real. Los errores distinguen clave inválida, permiso, modelo y cuota, sin mostrar claves.

Puedes pulsar Seleccionar o mantener una nota pulsada, marcar varias y copiarlas como texto. Copiar todas incluye las notas visibles según proyecto, búsqueda y estado. No incluye metadatos, adjuntos ni prompts separados.

## Límites de esta versión
Una pareja de dispositivos. Sin descubrimiento multicast; QR/código contiene dirección local. Hasta 20 MB por adjunto y 45 MB de adjuntos en un intercambio completo. Ediciones simultáneas se conservan como conflictos. Los datos locales existentes se mantienen al actualizar.

## Desarrollo
flutter pub get
flutter analyze
flutter test
flutter run -d windows

## Actualización
APK firmado con la misma identidad y versionCode 3. Windows portable debe conservar todas sus DLL y carpeta data. GitHub Releases distribuye paquetes y SHA256SUMS. El asistente de Windows verifica y prepara el paquete antes de cerrar Hilva, conserva el paquete anterior y registra el resultado. Para salir de 1.1.0 si falla el actualizador, cierra Hilva desde la bandeja y extrae el nuevo ZIP completo en una carpeta nueva; abre hilva.exe. Las notas se conservan en AppData. Si usas inicio automático, desactívalo y actívalo desde la nueva carpeta. Ver docs/RELEASE.md.

## Dependencia adaptada
third_party/flutter_secure_storage_windows conserva licencia upstream 4.2.2. Conversiones ATL reemplazadas por equivalentes Win32 CP_ACP para compilar sin ATL; conserva Credential APIs.
