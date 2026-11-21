import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'native_service.dart';

class ReleaseUpdate {
  final String version, notes, assetName, checksum;
  final Uri url;
  const ReleaseUpdate({
    required this.version,
    required this.notes,
    required this.assetName,
    required this.checksum,
    required this.url,
  });
}

/// SHA256 checks integrity against GitHub metadata, not an independent signature.
class UpdateService {
  static const repository = 'LuisfNarvaez01/Notas';
  final http.Client _client;
  UpdateService({http.Client? client}) : _client = client ?? http.Client();
  static bool isNewer(String candidate, String current) {
    List<int> parts(String value) => value
        .replaceFirst(RegExp(r'^v'), '')
        .split('+')
        .first
        .split('.')
        .map((x) => int.tryParse(x) ?? 0)
        .toList();
    final a = parts(candidate), b = parts(current);
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  Future<ReleaseUpdate?> check() async {
    if (!Platform.isAndroid && !Platform.isWindows) return null;
    final response = await _client
        .get(
          Uri.https('api.github.com', '/repos/$repository/releases/latest'),
          headers: {'Accept': 'application/vnd.github+json'},
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw HttpException('GitHub: ${response.statusCode}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['prerelease'] == true || data['draft'] == true) return null;
    final version = data['tag_name'] as String;
    final info = await PackageInfo.fromPlatform();
    if (!isNewer(version, info.version)) return null;
    final name = Platform.isAndroid ? 'hilva-android.apk' : 'hilva-windows.zip';
    final assets = (data['assets'] as List).cast<Map<String, dynamic>>();
    final matches = assets.where((a) => a['name'] == name);
    final sums = assets.where((a) => a['name'] == 'SHA256SUMS');
    if (matches.isEmpty || sums.isEmpty) {
      throw StateError('La versión no incluye paquete y SHA256SUMS.');
    }
    Uri assetUri(Map<String, dynamic> asset) {
      final uri = Uri.parse(asset['browser_download_url'] as String);
      if (uri.scheme != 'https' ||
          uri.host != 'github.com' ||
          !uri.path.startsWith('/$repository/releases/download/')) {
        throw StateError('Origen de actualización no permitido.');
      }
      return uri;
    }

    final hashes = await _client
        .get(assetUri(sums.first))
        .timeout(const Duration(seconds: 20));
    if (hashes.statusCode != 200) {
      throw StateError('No se pudo verificar la actualización.');
    }
    final line = const LineSplitter()
        .convert(hashes.body)
        .where(
          (line) =>
              RegExp('^[a-fA-F0-9]{64}  ${RegExp.escape(name)}\$')
                  .hasMatch(line),
        )
        .firstOrNull;
    if (line == null) throw StateError('Falta el hash del paquete.');
    return ReleaseUpdate(
      version: version,
      notes: data['body'] as String? ?? '',
      assetName: name,
      checksum: line.substring(0, 64).toLowerCase(),
      url: assetUri(matches.first),
    );
  }

  Future<File> download(ReleaseUpdate release) async {
    final directory = Directory(
      p.join((await getTemporaryDirectory()).path, 'updates'),
    );
    await directory.create(recursive: true);
    final partial = File(p.join(directory.path, '${release.assetName}.part'));
    final response = await _client
        .send(http.Request('GET', release.url))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw HttpException('Descarga: ${response.statusCode}');
    }
    final sink = partial.openWrite();
    try {
      var size = 0;
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 45),
      )) {
        size += chunk.length;
        if (size > 512 * 1024 * 1024) {
          throw StateError('Paquete demasiado grande.');
        }
        sink.add(chunk);
      }
      await sink.close();
      final digest = await sha256.bind(partial.openRead()).first;
      if (digest.toString() != release.checksum) {
        throw StateError('Hash incorrecto: descarga descartada.');
      }
      return await partial.rename(p.join(directory.path, release.assetName));
    } catch (_) {
      await sink.close();
      if (await partial.exists()) await partial.delete();
      rethrow;
    }
  }

  /// Call only after the user approves installation and saves pending edits.
  Future<void> install(File file) async {
    if (Platform.isAndroid) return NativeService.installApk(file.path);
    if (!Platform.isWindows) {
      throw UnsupportedError('Plataforma no disponible.');
    }
    final helper = File(
      p.join(p.dirname(Platform.resolvedExecutable), 'update-windows.ps1'),
    );
    if (!await helper.exists()) {
      throw StateError('Falta el asistente; usa el paquete portable completo.');
    }
    final copy = await helper.copy(
      p.join((await getTemporaryDirectory()).path, 'hilva-update-$pid.ps1'),
    );
    await Process.start('powershell.exe', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-WindowStyle',
      'Hidden',
      '-File',
      copy.path,
      '-Archive',
      file.absolute.path,
      '-Destination',
      p.dirname(Platform.resolvedExecutable),
      '-WaitPid',
      '$pid',
      '-ExpectedHash',
      (await sha256.bind(file.openRead()).first).toString(),
    ], mode: ProcessStartMode.detached);
    exit(0);
  }

  void dispose() => _client.close();
}
