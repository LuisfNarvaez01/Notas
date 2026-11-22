import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/store.dart';
import '../services/lan_service.dart';
import '../services/ai_service.dart';
import 'pairing.dart';
import '../services/native_service.dart';
import '../services/update_service.dart';

class SettingsPanel extends StatefulWidget {
  final Store store;
  final LanService lan;
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onTheme;
  final ValueChanged<String> onMessage;
  final VoidCallback onSync;
  final AiService Function() aiFactory;
  const SettingsPanel({
    super.key,
    required this.store,
    required this.lan,
    required this.mode,
    required this.onTheme,
    required this.onMessage,
    required this.onSync,
    this.aiFactory = AiService.new,
  });
  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  final groq = TextEditingController(),
      gemini = TextEditingController(),
      groqModel = TextEditingController(),
      geminiModel = TextEditingController();
  String provider = 'groq';
  bool saving = false, loading = true, autoStart = false;
  final Map<String, String> connectionStatus = {};
  String? updateFailure;
  final secure = const FlutterSecureStorage();
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    groq.text = await secure.read(key: 'groqKey') ?? '';
    gemini.text = await secure.read(key: 'geminiKey') ?? '';
    groqModel.text =
        await widget.store.setting('groqModel') ?? AiService.defaultGroqModel;
    geminiModel.text =
        await widget.store.setting('geminiModel') ??
        AiService.defaultGeminiModel;
    provider = await widget.store.setting('provider') ?? 'groq';
    autoStart = await widget.store.setting('autoStart') == 'true';
    updateFailure = await UpdateService.lastWindowsFailure();
    if (mounted) setState(() => loading = false);
  }

  @override
  void dispose() {
    for (final c in [groq, gemini, groqModel, geminiModel]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    setState(() => saving = true);
    try {
      await secure.write(
        key: 'groqKey',
        value: AiService.normalizeKey(groq.text),
      );
      await secure.write(
        key: 'geminiKey',
        value: AiService.normalizeKey(gemini.text),
      );
      for (final item in {
        'groqModel': groqModel.text.trim(),
        'geminiModel': geminiModel.text.trim(),
        'provider': provider,
      }.entries) {
        await widget.store.setSetting(item.key, item.value);
      }
      widget.onMessage(
        'Ajustes guardados. Las claves permanecen en este dispositivo.',
      );
    } catch (e) {
      widget.onMessage('$e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> testKey(String provider) async {
    final key = AiService.normalizeKey(
      (provider == 'groq' ? groq : gemini).text,
    );
    final model = (provider == 'groq' ? groqModel : geminiModel).text.trim();
    setState(() {
      saving = true;
      connectionStatus[provider] = 'Comprobando clave y respuesta del modelo…';
    });
    final ai = widget.aiFactory();
    try {
      await ai.testConnection(provider: provider, apiKey: key, model: model);
      await secure.write(key: '${provider}Key', value: key);
      await widget.store.setSetting('${provider}Model', model);
      await widget.store.setSetting('provider', provider);
      this.provider = provider;
      connectionStatus[provider] =
          'Conexión verificada. $provider activo; clave y modelo guardados en este dispositivo.';
      widget.onMessage('$provider: conexión verificada y guardada.');
    } catch (e) {
      connectionStatus[provider] = '$e';
      widget.onMessage('$e');
    } finally {
      ai.dispose();
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> chooseModel(String name) async {
    setState(() => saving = true);
    final ai = widget.aiFactory();
    try {
      final models = await ai.listModels(
        provider: name,
        apiKey: (name == 'groq' ? groq : gemini).text,
      );
      if (!mounted) return;
      final controller = name == 'groq' ? groqModel : geminiModel;
      final model = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text('Modelos de ${name == 'groq' ? 'Groq' : 'Gemini'}'),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(
                'Catálogo actual. El acceso y la cuota se comprueban con Probar y guardar.',
              ),
            ),
            for (final id in models)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(id),
                ),
              ),
          ],
        ),
      );
      if (model != null && mounted) {
        controller.text = model;
        connectionStatus[name] =
            'Modelo seleccionado. Pulsa Probar y guardar para verificarlo.';
      }
    } catch (e) {
      connectionStatus[name] = '$e';
      widget.onMessage('$e');
    } finally {
      ai.dispose();
      if (mounted) setState(() => saving = false);
    }
  }

  Widget connectionActions(String name) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 8,
        children: [
          TextButton(
            onPressed: saving ? null : () => chooseModel(name),
            child: const Text('Elegir modelo'),
          ),
          OutlinedButton(
            onPressed: saving ? null : () => testKey(name),
            child: Text(
              'Probar y guardar ${name == 'groq' ? 'Groq' : 'Gemini'}',
            ),
          ),
        ],
      ),
      if (connectionStatus[name] != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SelectableText(connectionStatus[name]!),
        ),
    ],
  );

  Future<void> backup() async {
    try {
      final data = await widget.store.exportBackup();
      final path = await FilePicker.saveFile(
        dialogTitle: 'Exportar respaldo de Hilva',
        fileName:
            'hilva-${DateTime.now().toIso8601String().substring(0, 10)}.json',
        bytes: Uint8List.fromList(utf8.encode(data)),
      );
      if (path != null) widget.onMessage('Respaldo exportado sin API keys.');
    } catch (e) {
      widget.onMessage('No se pudo exportar: $e');
    }
  }

  Future<void> restore() async {
    try {
      final result = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result?.path == null) return;
      final file = File(result!.path!);
      if (await file.length() > 100 * 1024 * 1024) {
        throw const FormatException('Respaldo demasiado grande');
      }
      await widget.store.importBackup(await file.readAsString());
      widget.onMessage(
        'Respaldo importado. Las notas existentes se conservaron.',
      );
    } catch (e) {
      widget.onMessage('No se pudo importar: $e');
    }
  }

  Future<void> update() async {
    setState(() => saving = true);
    final service = UpdateService();
    try {
      final release = await service.check();
      if (!mounted) return;
      if (release == null) {
        widget.onMessage('No hay una versión nueva publicada.');
        return;
      }
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Hilva ${release.version}'),
          content: SingleChildScrollView(
            child: Text(
              '${release.notes}\n\nSe descargará la actualización. Windows cerrará Hilva para reemplazarla; Android pedirá confirmar la instalación.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Ahora no'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Actualizar'),
            ),
          ],
        ),
      );
      if (ok == true) {
        widget.onMessage('Descargando y verificando la actualización…');
        final file = await service.download(release);
        await service.install(file);
      }
    } catch (e) {
      widget.onMessage('No se pudo actualizar: $e');
    } finally {
      service.dispose();
      if (mounted) setState(() => saving = false);
    }
  }

  Widget field(
    String name,
    TextEditingController c, {
    bool secret = false,
    String? hint,
  }) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: TextField(
      controller: c,
      obscureText: secret,
      enableSuggestions: !secret,
      autocorrect: false,
      enabled: !saving,
      decoration: InputDecoration(labelText: name, hintText: hint),
    ),
  );
  Widget heading(String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
      children: [
        Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heading('Apariencia', 'Una interfaz cómoda en cada momento.'),
                DropdownButtonFormField<ThemeMode>(
                  initialValue: widget.mode,
                  items: const [
                    DropdownMenuItem(
                      value: ThemeMode.system,
                      child: Text('Seguir al sistema'),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.light,
                      child: Text('Claro'),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.dark,
                      child: Text('Oscuro'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) widget.onTheme(v);
                  },
                ),
                heading(
                  'Tu inteligencia artificial',
                  'Se usa únicamente cuando lo pides. Introduce tus propias claves gratuitas.',
                ),
                DropdownButtonFormField<String>(
                  initialValue: provider,
                  decoration: const InputDecoration(
                    labelText: 'Proveedor preferido',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'groq', child: Text('Groq')),
                    DropdownMenuItem(value: 'gemini', child: Text('Gemini')),
                  ],
                  onChanged: (v) => setState(() => provider = v!),
                ),
                field('API key de Groq', groq, secret: true),
                field('Modelo de Groq', groqModel),
                connectionActions('groq'),
                field('API key de Gemini', gemini, secret: true),
                field('Modelo de Gemini', geminiModel),
                connectionActions('gemini'),
                const SizedBox(height: 10),
                Text(
                  'Los modelos y las cuotas dependen de tu cuenta. Si se agotan, puedes seguir guardando notas. El nivel gratuito de Gemini puede usar contenido para mejorar sus productos.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                FilledButton(
                  onPressed: saving ? null : save,
                  child: const Text('Guardar configuración'),
                ),
                PairingPanel(lan: widget.lan),
                heading(
                  'Tu información, contigo',
                  'Exporta notas, contextos y adjuntos. Las claves no se incluyen. Guarda una copia antes de cambiar de equipo.',
                ),
                Wrap(
                  spacing: 12,
                  children: [
                    OutlinedButton.icon(
                      onPressed: backup,
                      icon: const Icon(Icons.file_download_outlined),
                      label: const Text('Exportar respaldo'),
                    ),
                    OutlinedButton.icon(
                      onPressed: restore,
                      icon: const Icon(Icons.file_upload_outlined),
                      label: const Text('Importar respaldo'),
                    ),
                  ],
                ),
                if (Platform.isWindows) ...[
                  heading(
                    'En tu escritorio',
                    'Ctrl + Shift + H abre la captura. Hilva puede permanecer en la bandeja del sistema.',
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Abrir al iniciar Windows'),
                    value: autoStart,
                    onChanged: (v) async {
                      try {
                        await NativeService.setAutoStart(v);
                        await widget.store.setSetting('autoStart', '$v');
                        setState(() => autoStart = v);
                      } catch (e) {
                        widget.onMessage(
                          'No se pudo cambiar el inicio automático.',
                        );
                      }
                    },
                  ),
                ],
                heading(
                  'Hilva 1.1.1',
                  'Ideas que toman forma. Actualizaciones desde GitHub Releases.',
                ),
                if (updateFailure != null) SelectableText(updateFailure!),
                OutlinedButton.icon(
                  onPressed: saving ? null : update,
                  icon: const Icon(Icons.system_update_alt),
                  label: const Text('Buscar actualizaciones'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
