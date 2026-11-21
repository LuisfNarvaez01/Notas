> Documento histórico: la arquitectura de nube fue sustituida por sincronización LAN. Ver README.md y docs/UPDATE-1.1.md para la versión actual.

# Hilva: definición de producto y ruta de implementación

Estado: propuesta para revisión, 20 de noviembre de 2026. Alcance confirmado en PRODUCT.md. Las decisiones técnicas descritas como propuestas pertenecen al agente y deben validarse antes de implementación. No se ha creado código de aplicación.

## Resultado esperado
Capturar una nota durante un turno en segundos, recuperarla organizada por proyecto en Windows y convertirla en un prompt que preserve lo pedido, a costo cero dentro de las cuotas gratuitas disponibles.

## Experiencia
Android abre una bandeja con captura accesible, pendientes y filtro por proyecto. Navegación propuesta: Bandeja, Proyectos y Biblioteca. La captura admite texto libre y varias viñetas juntas, voz e imágenes. Guardar no requiere clasificación, conexión ni IA. Proyecto actual opcional; una sesión de pruebas mantiene el mismo proyecto para capturas sucesivas.

Windows adapta la información a navegación lateral, listado y editor; no estira la pantalla del teléfono. Bandeja del sistema, atajo configurable, copia al portapapeles y arranque opcional. La app no ejecuta prompts ni los envía a otros asistentes automáticamente.

Al pulsar Organizar, la IA propone dividir y clasificar la nota. Se conserva el original y se revisa el resultado antes de aplicarlo. El usuario elige ideas para afinar. Preguntas breves, agrupadas cuando comparten contexto; se puede omitir una respuesta dejando explícito el pendiente. Sugerencias de IA separadas de requisitos confirmados. Prompt editable con objetivo, contexto, comportamiento esperado, alcance, criterios de aceptación y dudas. Estados propuestos: capturada, por aclarar, lista, en desarrollo, resuelta y archivada.

Ficha de proyecto: propósito, usuarios, pantallas/módulos, términos particulares, limitaciones, versión y fecha. Plantilla para pedirla al asistente que conoce el proyecto. Importar texto/Markdown con previsualización; contexto versionado y sin secretos. No rastrear repositorios. Permitir seleccionar fragmentos pertinentes dentro de un límite de tamaño visible.

Biblioteca: título/herramienta, función breve, etiquetas editables, proyectos asociados, enlace original y origen del contenido utilizado. Diferenciar resumen basado en contenido accesible, descripción publicada y nota manual. No prometer extracción universal de Facebook/Instagram/TikTok. Guardado del enlace siempre disponible; no descargar bibliotecas completas de videos. Buscar por texto, etiquetas, proyecto y estado sin IA.

## Nube y funcionamiento local
Propuesta: Supabase Free para PostgreSQL, Google Auth y Storage privado; SQLite en ambos dispositivos. Supabase no proporciona por sí solo toda la sincronización offline: implementar cola persistente de cambios, identificadores estables e idempotencia. Realtime puede acelerar avisos; la reconciliación al abrir y reconectar garantiza recuperar cambios perdidos.

Cada registro tiene propietario, identificador, revisión y marcas de eliminación. Si dos dispositivos cambian la misma revisión, conservar ambas variantes y ofrecer resolver el conflicto, sin sobrescritura silenciosa. Enviar cambios locales y recuperar remotos por cursor; probar también borrados, reinicios e interrupciones. Originales y versiones de prompts permanecen recuperables.

Autenticación Google mediante Supabase: validar retorno OAuth tanto Android como Windows antes de comprometer el mecanismo. RLS por propietario en todas las tablas y políticas equivalentes en adjuntos. Cuenta de Luis permitida para la instancia personal mediante configuración de servidor; otras cuentas no obtienen acceso. No incluir claves administrativas en clientes. Captura local previa al login permitida; asociar datos locales tras confirmar identidad.

Claves Groq/Gemini introducidas por el usuario en cada dispositivo, guardadas con protección del sistema operativo, nunca en Git ni en textos de exportación. Llamadas directas desde clientes nativos para evitar un servidor de IA de pago. No sincronizar claves en la primera versión. Selección explícita de proveedor y fallback opcional previamente habilitado.

Cuotas: límite de adjuntos configurable, compresión de imágenes y audio, contador de uso estimado con aviso y acceso al panel del proveedor. Si falla una subida, conservar archivo local y estado pendiente. No borrar originales automáticamente. Exportación/importación local versionada con notas, contexto y adjuntos; comprobar restauración.

## IA
Una interfaz por proveedor, modelo configurable y límites de entrada/salida. Clasificar un lote solo bajo demanda. Salida estructurada validada, con referencia a fragmentos originales. Respuesta inválida no modifica notas; permitir revisar o reintentar explícitamente. Manejar timeout y 429 con espera indicada y reintentos limitados, sin bucles. Cancelación y estados persistentes.

Audio se graba primero y se transcribe bajo demanda si existe capacidad gratuita disponible; no prometer transcripción offline. El texto transcrito es editable. Capturas se guardan aunque el modelo seleccionado no admita imágenes. Validar reconocimiento visual por proveedor antes de ofrecerlo.

Contenido externo y contexto importado se tratan como datos, nunca como instrucciones para ejecutar acciones. La IA no tiene herramientas para modificar repositorios. Probar con las 13 viñetas reales de TubeDeck, conservando ambigüedades como los marcos, los detalles temporales de precarga y todas las acciones de cola.

## Diseño y calidad
Modo Operate de Impeccable: completar tareas con precisión, legibilidad y personalidad propia. Uso con una mano, teclado del móvil abierto, poca luz y notas largas. Sin emojis. Iconos consistentes con etiquetas donde sean necesarias. Temas claro y oscuro, escala de texto accesible, foco visible, navegación por teclado en Windows, movimiento reducido y objetivos táctiles adecuados.

Dirección visual todavía por representar: moderna, compacta sin amontonar, identidad reconocible en tipografía, icono y composición. No adoptar automáticamente la plantilla visual de una búsqueda. UI UX Pro Max devolvió inicialmente una composición de marketing; se descarta para las pantallas operativas. Elaborar vistas de captura, proyecto y revisión usando TubeDeck/jCode como contenido real. Revisar en tamaños Android/Windows antes de fijar tokens. La identidad final y DESIGN.md se documentan desde el resultado validado, no se presentan como ya diseñados.

## Distribución y actualizaciones
Git versiona código; GitHub Actions compila y verifica y GitHub Releases distribuye artefactos. APK firmado con identidad y clave estables. Aviso de versión, notas, descarga y confirmación mediante instalador Android, conservando datos; no prometer instalación silenciosa ni parches OTA de Dart gratuitos ilimitados.

Windows: portable ZIP con ejecutable y todas sus dependencias. Preferencia inicial por portable para costo cero. Actualizador externo tras cierre, staging, verificación y recuperación de fallos; los datos viven fuera del directorio reemplazado. Instalador opcional si la prueba de empaquetado lo justifica. Sin garantía de evitar avisos de reputación de Windows con binarios sin certificado comercial.

Metadatos de versión y manifiesto firmado para verificar hashes y procedencia; distinguir prereleases. Nunca almacenar tokens GitHub personales en la app. Distribución pública solo de binarios y código sin datos personales. Validar visibilidad actual del repositorio antes de configurar CI gratuito; alternativa compilación local si no aplican cuotas gratuitas. No renombrar el repositorio hasta fijar el nombre definitivo.

## Ruta por entregas, pendiente del plan ejecutable
0. Viabilidad: Google OAuth Android/Windows; sincronización desconectada; límites gratuitos; compartir desde tres redes; widget; audio; claves seguras; actualizaciones reales v1 a v2. Documentar APIs/paquetes/versiones probados antes de construir alrededor de ellos.
1. Diseño: recorrido y maquetas con las notas reales, estados offline/error/cuota y revisión móvil/escritorio. Fijar identidad y componentes.
2. Núcleo local: proyectos, ficha de contexto, captura, edición, etiquetas, búsqueda, estados, originales y exportación. Aceptación: reiniciar offline sin perder una captura.
3. Nube: login, restricciones de acceso, sincronización, adjuntos y conflictos. Aceptación: cambios realizados offline en ambos equipos se recuperan sin pérdida ni duplicados.
4. IA: Groq/Gemini, división revisable, preguntas, sugerencias y prompt versionado. Aceptación: todas las viñetas preservadas, ambigüedades señaladas y cuota agotada sin bloquear captura.
5. Captura integrada y biblioteca: widget, Compartir, audio, imágenes, referencias de videos, bandeja y atajo Windows. Aceptación: enlace compartido accesible o bloqueado siempre se guarda y se encuentra por etiqueta.
6. Entrega: APK y portable, actualizador, migraciones, backups, documentación de portafolio y demo sin datos privados. Aceptación: instalación limpia y actualización conservan notas, claves y contextos; interrupción de descarga no rompe instalación.

## Fuera de la primera versión
Multiusuario/colaboración, suscripciones, iOS, lectura de repositorios, ejecución automática de prompts, scraping de redes con garantías, transcripción offline y servicios pagos.

## Riesgos y límites aceptables
Cero costo no equivale a capacidad ilimitada: ante cuotas o pausa de nube, seguir local y mostrar estado pendiente. No activar facturación. Supabase Free puede pausarse por inactividad; restaurar en panel cuando corresponda. Respaldos locales exportables para no depender exclusivamente de disponibilidad de la nube. OAuth y las restricciones Android se validarán en el dispositivo real.

## Fuentes consultadas
- https://supabase.com/pricing — plan Free: 500 MB de base de datos, 1 GB archivos, cuotas de transferencia y pausa por inactividad.
- https://supabase.com/docs/guides/platform/free-project-pausing
- https://supabase.com/docs/guides/getting-started/quickstarts/flutter
- https://supabase.com/docs/reference/dart/auth-signinwithoauth — signInWithOAuth.
- https://supabase.com/docs/guides/auth/social-sign-in/auth-google?platform=flutter
- https://supabase.com/docs/guides/database/postgres/row-level-security
- https://docs.flutter.dev/app-architecture/design-patterns/offline-first — repositorio local/remoto y sincronización.
- https://docs.flutter.dev/deployment/android — firma, versiones y APK.
- https://docs.flutter.dev/deployment/windows — distribución escritorio.
- https://firebase.google.com/docs/storage/faqs-storage-changes-announced-sept-2024 — Storage requiere Blaze; por eso no se elige como base para presupuesto cero.
- https://console.groq.com/docs/rate-limits
- https://ai.google.dev/gemini-api/docs/pricing

## Verificación adicional de distribución
GitHub Actions: runners estándar gratuitos para repositorios públicos, según https://docs.github.com/en/billing/concepts/product-billing/github-actions . Evitar runners grandes y comprobar plan/visibilidad antes de activar CI.
GitHub Releases: https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases . Consultar novedades mediante GET /repos/{owner}/{repo}/releases/latest y usar tag_name, body y assets[].browser_download_url según https://docs.github.com/en/rest/releases/releases#get-the-latest-release . Hash de descarga no sustituye firma de procedencia.
Android: https://developer.android.com/studio/publish/app-signing y https://developer.android.com/reference/android/content/pm/PackageInstaller . Mantener certificado/applicationId, aumentar versionCode y manejar STATUS_PENDING_USER_ACTION. Verificar requisitos de distribución lateral aplicables al dispositivo/región durante fase 0.
Windows: https://docs.flutter.dev/platform-integration/windows/building . Empaquetar dependencias completas y comprobar runtime VC++ en una máquina limpia. No presentar el exe solo como portable autosuficiente.
