import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data/store.dart';
import 'services/ai_service.dart';
import 'services/lan_service.dart';
import 'services/native_service.dart';
import 'ui/theme.dart';
import 'ui/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final store = await Store.open();
    runApp(HilvaApp(store: store));
  } catch (e) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SelectableText(
              'No se pudo abrir Hilva. Tus archivos no se han borrado.\n$e',
            ),
          ),
        ),
      ),
    );
  }
}

class HilvaApp extends StatefulWidget {
  final Store store;
  const HilvaApp({super.key, required this.store});
  @override
  State<HilvaApp> createState() => _HilvaAppState();
}

class _HilvaAppState extends State<HilvaApp> {
  ThemeMode mode = ThemeMode.system;
  @override
  void initState() {
    super.initState();
    widget.store.setting('theme').then((v) {
      if (mounted) {
        setState(
          () => mode = v == 'dark'
              ? ThemeMode.dark
              : v == 'light'
              ? ThemeMode.light
              : ThemeMode.system,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Hilva',
    debugShowCheckedModeBanner: false,
    theme: hilvaTheme(false),
    darkTheme: hilvaTheme(true),
    themeMode: mode,
    home: Workspace(
      store: widget.store,
      mode: mode,
      onTheme: (m) {
        setState(() => mode = m);
        widget.store.setSetting('theme', m.name);
      },
    ),
  );
}

class Workspace extends StatefulWidget {
  final Store store;
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onTheme;
  const Workspace({
    super.key,
    required this.store,
    required this.mode,
    required this.onTheme,
  });
  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> with WidgetsBindingObserver {
  late final LanService lan;
  final search = TextEditingController();
  final capture = TextEditingController();
  final recorder = AudioRecorder();
  final secure = const FlutterSecureStorage();
  int section = 0;
  String? projectId, selectedId;
  String status = 'Todas';
  bool busy = false, recording = false, syncing = false;
  String? recordingPath;
  Timer? syncTimer;
  List<String> attachments = [];
  Store get store => widget.store;
  List<Entry> get projects =>
      store.records.where((e) => e.kind == 'project').toList();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    lan = LanService(store);
    lan.addListener(refresh);
    store.addListener(refresh);
    initServices();
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  Future<void> initServices() async {
    try {
      await lan.start();
    } catch (_) {
      message(
        'No se pudo activar la conexión local. Puedes seguir guardando notas.',
      );
    }
    NativeService.onCapture((text) {
      if (mounted) {
        setState(() {
          section = 0;
          capture.text = text;
        });
      }
    });
    NativeService.onImages((paths) async {
      for (final path in paths) {
        final saved = await store.addAttachment(path);
        if (mounted) setState(() => attachments.add(saved));
      }
    });
    for (final path in await NativeService.initialImages()) {
      final saved = await store.addAttachment(path);
      if (mounted) setState(() => attachments.add(saved));
    }
    final initial = await NativeService.initialText();
    if (initial != null && mounted) setState(() => capture.text = initial);
    syncTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => sync(silent: true),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) sync(silent: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    store.removeListener(refresh);
    syncTimer?.cancel();
    lan.removeListener(refresh);
    lan.dispose();
    capture.dispose();
    search.dispose();
    recorder.dispose();
    super.dispose();
  }

  void message(String s) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
    }
  }

  Future<void> sync({bool silent = false}) async {
    if (syncing) return;
    if (!lan.paired) {
      if (!silent) message('Vincula tus dispositivos desde Ajustes.');
      return;
    }
    setState(() => syncing = true);
    try {
      await lan.sync();
      if (!silent) message('Tus notas están al día.');
    } catch (e) {
      if (!silent) {
        message('No se pudo sincronizar. Tus cambios siguen guardados aquí.');
      }
    } finally {
      if (mounted) setState(() => syncing = false);
    }
  }

  Future<void> saveCapture() async {
    final text = capture.text.trim();
    if (text.isEmpty && attachments.isEmpty) return;
    try {
      await store.save('note', {
        'title': text.isEmpty ? 'Nota de voz o imagen' : text.split('\n').first,
        'body': text,
        'original': text,
        'projectId': projectId,
        'tags': <String>[],
        'status': 'Capturada',
        'attachments': List<String>.from(attachments),
        'isLink': RegExp(r'https?://').hasMatch(text),
      });
      capture.clear();
      setState(() => attachments = []);
      message('Guardado en este dispositivo.');
      unawaited(sync(silent: true));
    } catch (e) {
      message('No se pudo guardar. El borrador sigue aquí.');
    }
  }

  Future<void> attach() async {
    try {
      final result = await FilePicker.pickFile(type: FileType.image);
      if (result?.path != null) {
        final path = await store.addAttachment(result!.path!);
        setState(() => attachments.add(path));
      }
    } catch (e) {
      message('No se pudo adjuntar: $e');
    }
  }

  Future<void> toggleRecord() async {
    try {
      if (recording) {
        final path = await recorder.stop();
        setState(() {
          recording = false;
          if (path != null) attachments.add(path);
        });
      } else {
        if (!await recorder.hasPermission()) {
          message('Permite el micrófono para grabar.');
          return;
        }
        final dir = Directory(p.join(store.directory, 'attachments'));
        await dir.create(recursive: true);
        recordingPath = p.join(
          dir.path,
          'audio-${DateTime.now().millisecondsSinceEpoch}.m4a',
        );
        await recorder.start(const RecordConfig(), path: recordingPath!);
        setState(() => recording = true);
      }
    } catch (e) {
      message('No se pudo grabar el audio.');
    }
  }

  Future<void> projectDialog([Entry? entry]) async {
    final title = TextEditingController(text: entry?.title);
    final body = TextEditingController(text: entry?.body);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          entry == null ? 'Un nuevo proyecto' : 'Contexto del proyecto',
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: title,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del proyecto',
                    hintText: 'Por ejemplo, TubeDeck',
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: body,
                  maxLines: 9,
                  decoration: const InputDecoration(
                    labelText: 'Contexto para la IA',
                    hintText: 'Qué hace, quién lo usa, pantallas, términos y límites.',
                  ),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(
                      const ClipboardData(
                        text: 'Resume este proyecto en máximo 1500 palabras: propósito, usuarios, pantallas y módulos, términos particulares, limitaciones, versión actual y fecha. Describe solo lo implementado. No incluyas secretos ni credenciales. Usaré esta ficha para contextualizar ideas y bugs.',
                      ),
                    );
                    message('Plantilla copiada para tu asistente.');
                  },
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copiar solicitud de contexto'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              if (title.text.trim().isEmpty) return;
              await store.save('project', {
                'title': title.text.trim(),
                'body': body.text,
                'contextHistory': [
                  ...?entry?.payload['contextHistory'] as List?,
                  if (entry != null)
                    {'body': entry.body, 'date': entry.updatedAt},
                ],
              }, id: entry?.id);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Guardar proyecto'),
          ),
        ],
      ),
    );
    title.dispose();
    body.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 960;
    final notes = store.records
        .where(
          (e) =>
              e.kind == 'note' &&
              (projectId == null || e.projectId == projectId) &&
              (section != 2 || e.payload['isLink'] == true) &&
              (status == 'Todas' || e.status == status) &&
              ('${e.title} ${e.body} ${e.tags.join(' ')}'
                  .toLowerCase()
                  .contains(search.text.toLowerCase())),
        )
        .toList();
    final selected = selectedId == null ? null : store.find(selectedId!);
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (wide) sideNav(),
            Expanded(
              child: Column(
                children: [
                  header(wide),
                  Expanded(
                    child: section == 3
                        ? SettingsPanel(
                            store: store,
                            lan: lan,
                            mode: widget.mode,
                            onTheme: widget.onTheme,
                            onMessage: message,
                            onSync: () => sync(),
                          )
                        : section == 1
                        ? projectList()
                        : Row(
                            children: [
                              Expanded(
                                child: Column(
                                  children: [
                                    if (section == 0) composer(),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        24,
                                        8,
                                        24,
                                        12,
                                      ),
                                      child: TextField(
                                        controller: search,
                                        onChanged: (_) => setState(() {}),
                                        decoration: const InputDecoration(
                                          hintText: 'Buscar ideas, herramientas o etiquetas',
                                          prefixIcon: Icon(
                                            Icons.search_rounded,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        24,
                                        0,
                                        24,
                                        10,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: DropdownButtonHideUnderline(
                                              child: DropdownButton<String>(
                                                isExpanded: true,
                                                value: status,
                                                items:
                                                    [
                                                          'Todas',
                                                          'Capturada',
                                                          'Por aclarar',
                                                          'Lista',
                                                          'En desarrollo',
                                                          'Resuelta',
                                                          'Archivada',
                                                        ]
                                                        .map(
                                                          (
                                                            s,
                                                          ) => DropdownMenuItem(
                                                            value: s,
                                                            child: Text(
                                                              s,
                                                              style:
                                                                  const TextStyle(
                                                                    fontSize:
                                                                        13,
                                                                  ),
                                                            ),
                                                          ),
                                                        )
                                                        .toList(),
                                                onChanged: (v) =>
                                                    setState(() => status = v!),
                                              ),
                                            ),
                                          ),
                                          Text(
                                            '${notes.length} notas',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelMedium,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: notes.isEmpty
                                          ? emptyState()
                                          : ListView.separated(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                    16,
                                                    0,
                                                    16,
                                                    24,
                                                  ),
                                              itemCount: notes.length,
                                              separatorBuilder: (_, i) =>
                                                  const SizedBox(height: 4),
                                              itemBuilder: (ctx, i) =>
                                                  noteTile(notes[i], wide),
                                            ),
                                    ),
                                  ],
                                ),
                              ),
                              if (wide && selected != null) ...[
                                VerticalDivider(
                                  width: 1,
                                  color: Theme.of(context).dividerColor,
                                ),
                                SizedBox(
                                  width: 440,
                                  child: NoteEditor(
                                    key: ValueKey(selected.id),
                                    entry: selected,
                                    store: store,
                                    onMessage: message,
                                  ),
                                ),
                              ],
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: section,
              onDestinationSelected: (i) => setState(() {
                section = i;
                selectedId = null;
              }),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.inbox_outlined),
                  selectedIcon: Icon(Icons.inbox),
                  label: 'Bandeja',
                ),
                NavigationDestination(
                  icon: Icon(Icons.folder_outlined),
                  selectedIcon: Icon(Icons.folder),
                  label: 'Proyectos',
                ),
                NavigationDestination(
                  icon: Icon(Icons.bookmarks_outlined),
                  selectedIcon: Icon(Icons.bookmarks),
                  label: 'Biblioteca',
                ),
                NavigationDestination(icon: Icon(Icons.tune), label: 'Ajustes'),
              ],
            ),
    );
  }

  Widget sideNav() => Container(
    width: 224,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      border: Border(right: BorderSide(color: Theme.of(context).dividerColor)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(28, 32, 24, 36),
          child: Row(
            children: [
              HilvaMark(),
              SizedBox(width: 12),
              Text(
                'hilva',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.4,
                ),
              ),
            ],
          ),
        ),
        for (final (i, label, icon) in [
          (0, 'Bandeja', Icons.inbox_outlined),
          (1, 'Proyectos', Icons.folder_outlined),
          (2, 'Biblioteca', Icons.bookmarks_outlined),
        ])
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              selected: section == i,
              selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
              leading: Icon(icon, size: 21),
              title: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              onTap: () => setState(() {
                section = i;
                selectedId = null;
              }),
            ),
          ),
        const SizedBox(height: 28),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Text(
            'Tus espacios',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 28),
                leading: const Icon(Icons.grid_view_rounded, size: 17),
                title: const Text(
                  'Todos los proyectos',
                  style: TextStyle(fontSize: 12),
                ),
                selected: projectId == null,
                onTap: () => setState(() {
                  projectId = null;
                  section = 0;
                }),
              ),
              ...projects.map(
                (e) => ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 28),
                  leading: const Icon(Icons.circle_outlined, size: 17),
                  title: Text(
                    e.title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                  selected: projectId == e.id,
                  onTap: () => setState(() {
                    projectId = e.id;
                    section = 0;
                  }),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: ListTile(
            leading: const Icon(Icons.tune, size: 20),
            title: const Text('Ajustes'),
            onTap: () => setState(() => section = 3),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 20, 22),
          child: Text(
            syncing ? 'Sincronizando…' : 'Guardado local activo',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ],
    ),
  );
  Widget header(bool wide) => Padding(
    padding: EdgeInsets.fromLTRB(wide ? 28 : 20, 24, 20, 14),
    child: Row(
      children: [
        if (!wide) ...[const HilvaMark(size: 26), const SizedBox(width: 12)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ['Tu bandeja', 'Proyectos', 'Biblioteca', 'Ajustes'][section],
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -.8),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  'Captura ahora. Dale forma después.',
                  'Un contexto para cada idea.',
                  'Lo que quieres volver a encontrar.',
                  'Tu espacio, a tu manera.',
                ][section],
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Sincronizar',
          onPressed: syncing ? null : () => sync(),
          icon: Icon(syncing ? Icons.sync : Icons.cloud_sync_outlined),
        ),
        if (section == 1)
          IconButton(
            tooltip: 'Nuevo proyecto',
            onPressed: () => projectDialog(),
            icon: const Icon(Icons.add),
          ),
      ],
    ),
  );
  Widget composer() => Container(
    margin: const EdgeInsets.fromLTRB(24, 8, 24, 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Theme.of(context).dividerColor),
    ),
    child: Column(
      children: [
        TextField(
          controller: capture,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: '¿Qué se te ocurrió?\nUna idea suelta también cuenta.',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (attachments.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 6,
              children: attachments
                  .map(
                    (a) => InputChip(
                      label: Text(
                        p.extension(a) == '.m4a' ? 'Audio' : 'Imagen',
                      ),
                      onDeleted: () => setState(() => attachments.remove(a)),
                    ),
                  )
                  .toList(),
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            IconButton(
              tooltip: recording ? 'Detener grabación' : 'Grabar voz',
              onPressed: toggleRecord,
              icon: Icon(
                recording ? Icons.stop_circle : Icons.mic_none,
                color: recording ? Colors.red : null,
              ),
            ),
            IconButton(
              tooltip: 'Adjuntar imagen',
              onPressed: attach,
              icon: const Icon(Icons.image_outlined),
            ),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: projectId,
                  isExpanded: true,
                  hint: const Text(
                    'Sin proyecto',
                    style: TextStyle(fontSize: 12),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Sin proyecto'),
                    ),
                    ...projects.map(
                      (e) => DropdownMenuItem(
                        value: e.id,
                        child: Text(
                          e.title,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => projectId = v),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: recording ? null : saveCapture,
              child: const Text('Guardar'),
            ),
          ],
        ),
      ],
    ),
  );
  Widget emptyState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            section == 2 ? Icons.bookmark_border : Icons.edit_note_rounded,
            size: 46,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 18),
          Text(
            search.text.isEmpty
                ? 'Aquí empieza la próxima mejora'
                : 'Sin coincidencias',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            search.text.isEmpty
                ? 'Guarda una idea o comparte un enlace.\nPodrás organizarlo cuando tengas tiempo.'
                : 'Prueba con otra palabra o cambia los filtros.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
  Widget noteTile(Entry e, bool wide) {
    final project = e.projectId == null ? null : store.find(e.projectId!);
    return Material(
      color: selectedId == e.id
          ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .5)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          if (wide) {
            setState(() => selectedId = e.id);
          } else {
            Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('Tu idea')),
                  body: NoteEditor(entry: e, store: store, onMessage: message),
                ),
              ),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    e.payload['isLink'] == true
                        ? Icons.link
                        : Icons.notes_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      e.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (e.payload['conflict_of'] != null)
                    const Tooltip(
                      message: 'Revisar versiones en conflicto',
                      child: Icon(Icons.difference_outlined, size: 18),
                    ),
                ],
              ),
              if (e.body != e.title) ...[
                const SizedBox(height: 8),
                Text(
                  e.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  Text(
                    project?.title ?? 'Sin proyecto',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(e.status, style: Theme.of(context).textTheme.labelSmall),
                  ...e.tags.map(
                    (t) => Text(
                      '#$t',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget projectList() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      if (projects.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Text(
            'Crea tu primer proyecto y añade el contexto que ayudará a la IA.',
          ),
        ),
      ...projects.map(
        (e) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              side: BorderSide(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(16),
            ),
            leading: const Icon(Icons.folder_open),
            title: Text(
              e.title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              e.body.isEmpty ? 'Añadir contexto' : e.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              tooltip: 'Editar contexto',
              onPressed: () => projectDialog(e),
              icon: const Icon(Icons.edit_outlined),
            ),
            onTap: () => setState(() {
              projectId = e.id;
              section = 0;
            }),
          ),
        ),
      ),
      OutlinedButton.icon(
        onPressed: () => projectDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Crear proyecto'),
      ),
    ],
  );
}

class NoteEditor extends StatefulWidget {
  final Entry entry;
  final Store store;
  final ValueChanged<String> onMessage;
  const NoteEditor({
    super.key,
    required this.entry,
    required this.store,
    required this.onMessage,
  });
  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late TextEditingController title, body, tags, prompt;
  late Entry entry;
  bool busy = false, dirty = false;
  String? result;
  final ai = AiService();
  @override
  void initState() {
    super.initState();
    entry = widget.entry;
    title = TextEditingController(text: entry.title);
    body = TextEditingController(text: entry.body);
    tags = TextEditingController(text: entry.tags.join(', '));
    prompt = TextEditingController(
      text: entry.payload['prompt'] as String? ?? '',
    );
    for (final c in [title, body, tags, prompt]) {
      c.addListener(changed);
    }
  }

  void changed() {
    if (mounted) setState(() => dirty = true);
  }

  @override
  void dispose() {
    if (dirty) {
      unawaited(save());
    }
    title.dispose();
    body.dispose();
    tags.dispose();
    prompt.dispose();
    super.dispose();
  }

  Future<void> save() async {
    entry = await widget.store.save('note', {
      ...entry.payload,
      'title': title.text.trim().isEmpty ? 'Sin título' : title.text.trim(),
      'body': body.text,
      'tags': tags.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
      'prompt': prompt.text,
      'promptHistory': [
        ...?entry.payload['promptHistory'] as List?,
        if (prompt.text != entry.payload['prompt'] &&
            entry.payload['prompt'] != null)
          {'text': entry.payload['prompt'], 'date': entry.updatedAt},
      ],
    }, id: entry.id);
    if (mounted) setState(() => dirty = false);
  }

  Future<void> process(String kind) async {
    await save();
    setState(() => busy = true);
    try {
      const secure = FlutterSecureStorage();
      final provider = await widget.store.setting('provider') ?? 'groq';
      final key = await secure.read(key: '${provider}Key') ?? '';
      final model =
          await widget.store.setting('${provider}Model') ??
          (provider == 'groq' ? 'llama-3.3-70b-versatile' : 'gemini-2.5-flash');
      if (key.isEmpty) throw Exception('Añade tu API key en Ajustes.');
      final context = entry.projectId == null
          ? ''
          : widget.store.find(entry.projectId!)?.body ?? '';
      final instruction = kind == 'prompt'
          ? 'Redacta un prompt de implementación en español con objetivo, contexto, requisitos explícitos, criterios de aceptación y dudas pendientes. Conserva cada requisito. Distingue sugerencias opcionales. No inventes respuestas ni afirmes conocer código.'
          : kind == 'questions'
          ? 'Formula hasta 5 preguntas breves para aclarar ambigüedades de estas notas. No repitas lo que ya se sabe. Luego ofrece sugerencias opcionales claramente separadas.'
          : 'Organiza todas las viñetas de esta nota por tema, conserva cada detalle, propone títulos y etiquetas. Si contiene un enlace, solo describe lo que diga el usuario: no has visto el video. Señala ambigüedades sin inventar. Devuelve texto legible en español.';
      final response = await ai.run(
        provider: provider,
        apiKey: key,
        model: model,
        instruction: instruction,
        text: body.text,
        context: context,
      );
      if (!mounted) return;
      setState(() => result = response);
      entry = await widget.store.save('note', {
        ...entry.payload,
        'lastAiResult': response,
        'lastAiKind': kind,
      }, id: entry.id);
      if (kind == 'prompt') {
        prompt.text = response;
        await save();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> transcribe(String path) async {
    setState(() => busy = true);
    try {
      final key = await const FlutterSecureStorage().read(key: 'groqKey') ?? '';
      if (key.isEmpty) throw Exception('Configura Groq para transcribir.');
      final text = await ai.transcribe(apiKey: key, path: path);
      body.text = '${body.text}\n$text'.trim();
      await save();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !dirty,
    onPopInvokedWithResult: (didPop, result) async {
      if (didPop) return;
      await save();
      if (context.mounted) Navigator.pop(context);
    },
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Dale forma',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            TextButton.icon(
              onPressed: save,
              icon: const Icon(Icons.check, size: 17),
              label: Text(dirty ? 'Guardar' : 'Guardado'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        TextField(
          controller: title,
          maxLines: null,
          style: Theme.of(context).textTheme.titleLarge,
          decoration: const InputDecoration(labelText: 'Título'),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: body,
          minLines: 5,
          maxLines: 14,
          decoration: const InputDecoration(labelText: 'Tu nota'),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: tags,
          decoration: const InputDecoration(
            labelText: 'Etiquetas',
            hintText: 'reproducción, bug, jCode',
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: entry.status,
          decoration: const InputDecoration(labelText: 'Estado'),
          items: [
            'Capturada',
            'Por aclarar',
            'Lista',
            'En desarrollo',
            'Resuelta',
            'Archivada',
          ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
          onChanged: (s) async {
            entry = await widget.store.save('note', {
              ...entry.payload,
              'status': s,
            }, id: entry.id);
            setState(() {});
          },
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: entry.projectId,
          decoration: const InputDecoration(labelText: 'Proyecto'),
          items: [
            const DropdownMenuItem<String>(
              value: null,
              child: Text('Sin proyecto'),
            ),
            ...widget.store.records
                .where((e) => e.kind == 'project')
                .map(
                  (e) => DropdownMenuItem(value: e.id, child: Text(e.title)),
                ),
          ],
          onChanged: (v) async {
            entry = await widget.store.save('note', {
              ...entry.payload,
              'projectId': v,
            }, id: entry.id);
            setState(() {});
          },
        ),
        ...entry.attachments.map(
          (f) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              f.endsWith('.m4a') ? Icons.graphic_eq : Icons.image_outlined,
            ),
            title: Text(
              p.basename(f),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: f.endsWith('.m4a')
                ? TextButton(
                    onPressed: busy ? null : () => transcribe(f),
                    child: const Text('Transcribir'),
                  )
                : null,
            onTap: () async {
              if (await File(f).exists()) {
                if (f.endsWith('.m4a')) {
                  await launchUrl(Uri.file(f));
                } else if (context.mounted) {
                  showDialog<void>(
                    context: context,
                    builder: (c) => Dialog(
                      child: InteractiveViewer(child: Image.file(File(f))),
                    ),
                  );
                }
              }
            },
          ),
        ),
        if (entry.payload['isLink'] == true)
          TextButton.icon(
            onPressed: () async {
              final match = RegExp(r'https?://[^\s]+').firstMatch(body.text);
              if (match != null) {
                await launchUrl(
                  Uri.parse(match.group(0)!),
                  mode: LaunchMode.externalApplication,
                );
              }
            },
            icon: const Icon(Icons.open_in_new),
            label: const Text('Abrir enlace original'),
          ),
        const SizedBox(height: 24),
        Text('Trabajar con IA', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(
          'Solo se envían esta nota y el contexto de su proyecto.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: busy ? null : () => process('organize'),
              child: const Text('Organizar'),
            ),
            OutlinedButton(
              onPressed: busy ? null : () => process('questions'),
              child: const Text('Aclarar idea'),
            ),
            FilledButton(
              onPressed: busy ? null : () => process('prompt'),
              child: const Text('Crear prompt'),
            ),
          ],
        ),
        if (busy)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: LinearProgressIndicator(),
          ),
        if ((result ?? entry.payload['lastAiResult']) != null) ...[
          const SizedBox(height: 18),
          SelectableText(result ?? entry.payload['lastAiResult'] as String),
          TextButton.icon(
            onPressed: () {
              body.text =
                  '${body.text}\n\n${result ?? entry.payload['lastAiResult']}';
              save();
            },
            icon: const Icon(Icons.playlist_add),
            label: const Text('Añadir a mi nota'),
          ),
        ],
        const SizedBox(height: 24),
        TextField(
          controller: prompt,
          minLines: 4,
          maxLines: 14,
          decoration: const InputDecoration(
            labelText: 'Prompt editable',
            hintText: 'Tu próximo paso, listo para llevar al PC.',
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: () async {
            await save();
            await Clipboard.setData(ClipboardData(text: prompt.text));
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Prompt copiado.')));
            }
          },
          icon: const Icon(Icons.copy_outlined, size: 18),
          label: const Text('Copiar prompt'),
        ),
        const SizedBox(height: 20),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Nota original', style: TextStyle(fontSize: 13)),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(
                entry.payload['original'] as String? ?? entry.body,
              ),
            ),
          ],
        ),
        TextButton.icon(
          onPressed: () async {
            final yes = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Â¿Eliminar esta nota?'),
                content: const Text(
                  'La eliminación se sincronizará con tus dispositivos.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Cancelar'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('Eliminar'),
                  ),
                ],
              ),
            );
            if (yes == true) {
              await widget.store.remove(entry.id);
              if (context.mounted && Navigator.canPop(context)) {
                Navigator.pop(context);
              }
            }
          },
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text('Eliminar nota'),
        ),
      ],
    ),
  );
}
