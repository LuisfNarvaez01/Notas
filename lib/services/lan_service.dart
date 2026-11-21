import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as hash;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;

import '../data/store.dart';

class LanService extends ChangeNotifier {
  final Store store;
  final int port;
  final Future<String?> Function(String) readSecret;
  final Future<void> Function(String, String) writeSecret;
  HttpServer? _server;
  Map<String, dynamic>? _peer;
  String? _invitation;
  DateTime? _expires;
  final Map<String, int> _seen = {};
  bool _busy = false, _disposed = false;
  String status = 'Sin vincular';
  final cipher = AesGcm.with256bits();
  LanService(
    this.store, {
    this.port = 53319,
    Future<String?> Function(String)? readSecret,
    Future<void> Function(String, String)? writeSecret,
  }) : readSecret =
           readSecret ?? ((k) => const FlutterSecureStorage().read(key: k)),
       writeSecret =
           writeSecret ??
           ((k, v) => const FlutterSecureStorage().write(key: k, value: v));
  bool get paired => _peer != null;
  int get listeningPort => _server?.port ?? port;
  void _status(String value) {
    status = value;
    if (!_disposed) notifyListeners();
  }

  String random() => base64UrlEncode(
    List<int>.generate(32, (_) => Random.secure().nextInt(256)),
  );
  Future<void> start() async {
    if (_server != null) return;
    final saved = await readSecret('hilva_lan_peer');
    if (saved != null && saved.isNotEmpty) {
      _peer = Map<String, dynamic>.from(jsonDecode(saved));
    }
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server!.listen(_handle);
    _status(paired ? 'Dispositivo vinculado' : 'Sin vincular');
  }

  static bool localAddress(String host) {
    final ip = InternetAddress.tryParse(host);
    if (ip == null || ip.type != InternetAddressType.IPv4) return false;
    final b = ip.rawAddress;
    return b[0] == 10 ||
        b[0] == 127 ||
        (b[0] == 192 && b[1] == 168) ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 169 && b[1] == 254);
  }

  Future<String> pairingCode({String? host}) async {
    await start();
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    host ??= interfaces
        .expand((i) => i.addresses)
        .map((a) => a.address)
        .where(localAddress)
        .firstOrNull;
    if (host == null) throw StateError('Conéctate a una red Wi-Fi o Ethernet.');
    _invitation = random();
    _expires = DateTime.now().add(const Duration(minutes: 5));
    return jsonEncode({
      'hilva': 1,
      'host': host,
      'port': listeningPort,
      'secret': _invitation,
    });
  }

  Future<Map<String, dynamic>> _seal(
    Map<String, dynamic> data,
    String secret,
  ) async {
    final box = await cipher.encrypt(
      utf8.encode(jsonEncode(data)),
      secretKey: SecretKey(base64Url.decode(secret)),
    );
    return {
      'nonce': base64Encode(box.nonce),
      'cipher': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    };
  }

  Future<Map<String, dynamic>> _open(
    Map<String, dynamic> data,
    String secret,
  ) async {
    final box = SecretBox(
      base64Decode(data['cipher']),
      nonce: base64Decode(data['nonce']),
      mac: Mac(base64Decode(data['mac'])),
    );
    final bytes = await cipher.decrypt(
      box,
      secretKey: SecretKey(base64Url.decode(secret)),
    );
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)));
  }

  Future<Map<String, dynamic>> _request(
    Map<String, dynamic> peer,
    String action,
    Map<String, dynamic> payload,
  ) async {
    final host = peer['host'] as String;
    if (!localAddress(host)) {
      throw StateError('Solo se permiten direcciones de red local.');
    }
    final id = random();
    final packet = await _seal({
      'id': id,
      'time': DateTime.now().millisecondsSinceEpoch,
      ...payload,
    }, peer['secret']);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client
          .post(host, peer['port'] as int, '/hilva/$action')
          .timeout(const Duration(seconds: 10));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(packet));
      final res = await req.close().timeout(const Duration(seconds: 40));
      if (res.statusCode != 200) {
        throw StateError(
          'El otro dispositivo no aceptó la conexión. Genera otro QR si cambió la red.',
        );
      }
      final body = await _read(res);
      final data = await _open(body, peer['secret']);
      if (data['replyTo'] != id) throw StateError('Respuesta no válida');
      return data;
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _read(Stream<List<int>> stream) async {
    final bytes = <int>[];
    await for (final chunk in stream.timeout(const Duration(seconds: 45))) {
      bytes.addAll(chunk);
      if (bytes.length > 80 * 1024 * 1024) {
        throw StateError('Sincronización demasiado grande (80 MB).');
      }
    }
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)));
  }

  Future<void> pair(String code) async {
    await start();
    final peer = Map<String, dynamic>.from(jsonDecode(code));
    if (peer['hilva'] != 1 ||
        !localAddress(peer['host'] as String) ||
        peer['port'] is! int ||
        peer['port'] < 1 ||
        peer['port'] > 65535 ||
        base64Url.decode(peer['secret']).length != 32) {
      throw const FormatException('Código de Hilva no válido');
    }
    final response = await _request(peer, 'pair', {
      'device': store.deviceId,
      'port': listeningPort,
    });
    peer['secret'] = response['sharedSecret'];
    _peer = peer;
    await writeSecret('hilva_lan_peer', jsonEncode(peer));
    _status('Dispositivo vinculado');
    await sync();
  }

  Future<void> forget() async {
    _peer = null;
    _invitation = null;
    await writeSecret('hilva_lan_peer', '');
    _status('Sin vincular');
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      if (req.method != 'POST' ||
          !localAddress(req.connectionInfo!.remoteAddress.address)) {
        req.response.statusCode = 403;
        return;
      }
      final pairing = req.uri.path == '/hilva/pair';
      if (!pairing && req.uri.path != '/hilva/sync') {
        req.response.statusCode = 404;
        return;
      }
      final secret = pairing ? _invitation : _peer?['secret'] as String?;
      if (secret == null ||
          (pairing &&
              (_expires == null || DateTime.now().isAfter(_expires!)))) {
        req.response.statusCode = 403;
        return;
      }
      final packet = await _open(await _read(req), secret);
      _seen.removeWhere(
        (_, time) => DateTime.now().millisecondsSinceEpoch - time > 300000,
      );
      final id = packet['id'];
      final time = packet['time'];
      if (id is! String ||
          time is! int ||
          (DateTime.now().millisecondsSinceEpoch - time).abs() > 300000 ||
          _seen.containsKey(id)) {
        req.response.statusCode = 403;
        return;
      }
      if (_seen.length > 10000) {
        req.response.statusCode = 429;
        return;
      }
      _seen[id] = DateTime.now().millisecondsSinceEpoch;
      Map<String, dynamic> result;
      if (pairing) {
        final shared = random();
        final remotePort = packet['port'];
        if (remotePort is! int || remotePort < 1 || remotePort > 65535) {
          throw const FormatException();
        }
        _peer = {
          'host': req.connectionInfo!.remoteAddress.address,
          'port': remotePort,
          'secret': shared,
        };
        await writeSecret('hilva_lan_peer', jsonEncode(_peer));
        _invitation = null;
        result = {'sharedSecret': shared};
        _status('Dispositivo vinculado');
      } else {
        await _import(packet);
        result = await _export();
        _status(
          'Sincronizado ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}',
        );
      }
      req.response.headers.contentType = ContentType.json;
      req.response.write(
        jsonEncode(await _seal({'replyTo': id, ...result}, secret)),
      );
    } catch (_) {
      req.response.statusCode = 400;
    } finally {
      await req.response.close();
    }
  }

  Future<Map<String, dynamic>> _export() async {
    final files = <String, String>{};
    final entries = <Map<String, dynamic>>[];
    var total = 0;
    for (final e in store.allRecords) {
      final refs = <String>[];
      for (final path in e.attachments) {
        if (!p.isWithin(p.join(store.directory, 'attachments'), path)) {
          throw StateError('Adjunto fuera de Hilva');
        }
        final file = File(path);
        if (!await file.exists()) continue;
        final size = await file.length();
        if (size > 20 * 1024 * 1024) throw StateError('Adjunto mayor de 20 MB');
        final bytes = await file.readAsBytes();
        final name =
            '${hash.sha256.convert(bytes)}${p.extension(path).toLowerCase()}';
        refs.add(name);
        if (!files.containsKey(name)) {
          total += size;
          if (total > 45 * 1024 * 1024) {
            throw StateError(
              'Los adjuntos superan 45 MB por sincronización. Exporta un respaldo.',
            );
          }
          files[name] = base64Encode(bytes);
        }
      }
      entries.add({
        ...e.toJson(),
        'payload': {...e.payload, 'attachments': refs},
      });
    }
    return {'records': entries, 'files': files};
  }

  Future<void> _import(Map<String, dynamic> data) async {
    final files = Map<String, dynamic>.from(data['files']);
    final records = (data['records'] as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final directory = Directory(p.join(store.directory, 'attachments'));
    await directory.create(recursive: true);
    final paths = <String, String>{};
    var total = 0;
    for (final item in files.entries) {
      if (!RegExp(r'^[a-f0-9]{64}(\.[a-z0-9]{1,10})?$').hasMatch(item.key)) {
        throw const FormatException('Adjunto inválido');
      }
      final bytes = base64Decode(item.value);
      total += bytes.length;
      if (bytes.length > 20 * 1024 * 1024 ||
          total > 45 * 1024 * 1024 ||
          !item.key.startsWith(hash.sha256.convert(bytes).toString())) {
        throw const FormatException('Adjunto inválido');
      }
      paths[item.key] = p.join(directory.path, item.key);
      if (!await File(paths[item.key]!).exists()) {
        await File(paths[item.key]!).writeAsBytes(bytes, flush: true);
      }
    }
    for (final record in records) {
      final payload = Map<String, dynamic>.from(record['payload']);
      final refs = List<String>.from(payload['attachments'] ?? []);
      if (refs.any((r) => !paths.containsKey(r))) {
        throw const FormatException('Adjunto incompleto');
      }
      payload['attachments'] = refs.map((r) => paths[r]!).toList();
      record['payload'] = payload;
      Entry.fromJson(record);
    }
    await store.mergeLan(records);
  }

  Future<void> sync() async {
    if (_busy || !paired) return;
    _busy = true;
    _status('Sincronizando…');
    try {
      final remote = await _request(_peer!, 'sync', await _export());
      await _import(remote);
      _status(
        'Sincronizado ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}',
      );
    } catch (_) {
      _status('Esperando al otro dispositivo');
      rethrow;
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _server?.close(force: true);
    super.dispose();
  }
}
