# Hilva 1.1.0 — verificación

Sin Supabase ni Google Auth. QR/código para pareja local; AES-GCM autentica y cifra intercambios. Claves y vínculo protegidos en almacenamiento del sistema. Sincronización cada 10 segundos mientras la app está activa y al reanudar. Sin descubrimiento multicast; cambios de IP requieren nuevo vínculo. Sin servicio Android perpetuo de fondo.

Pruebas: dos servidores loopback con bases SQLite distintas intercambian notas/archivos, conservan conflictos, propagan borrados y rechazan secret incorrecto. Migración 1.0 conserva texto original y relojes persistentes. Botón IA probado con HTTP simulado; no se han usado claves reales. UI evaluada en 390 y 1280 píxeles.

Actualizador Windows probado con copia aislada del portable anterior, reemplazo verificado por hash y proceso de nueva app iniciado. Se conserva backup de ejecutables; datos fuera del directorio de instalación. Falta confirmación del usuario en su instalación real y Android físico. No se ha probado conectividad entre un Android físico y Windows en esta sesión.

Distribución mantiene nombres hilva-android.apk, hilva-windows.zip y SHA256SUMS esperados por v1.0. Android usa misma clave local de firma y versionCode creciente. No desinstalar para actualizar. El repositorio no incluye contraseñas ni keystore.
