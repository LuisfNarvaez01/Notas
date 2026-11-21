import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as mobile;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

class Entry {
  final String id, kind, updatedAt;
  final Map<String, dynamic> payload;
  final int revision, baseRevision;
  final bool deleted;
  const Entry({
    required this.id,
    required this.kind,
    required this.payload,
    required this.revision,
    required this.baseRevision,
    required this.updatedAt,
    this.deleted = false,
  });
  factory Entry.fromJson(Map<String, dynamic> j) => Entry(
    id: j['id'] as String,
    kind: j['kind'] as String,
    payload: Map<String, dynamic>.from(
      j['payload'] is String ? jsonDecode(j['payload']) : j['payload'],
    ),
    revision: j['revision'] as int,
    baseRevision: j['base_revision'] as int,
    updatedAt: j['updated_at'] as String,
    deleted: j['deleted'] == true || j['deleted'] == 1,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'payload': payload,
    'revision': revision,
    'base_revision': baseRevision,
    'updated_at': updatedAt,
    'deleted': deleted,
  };
  Map<String, Object?> toDb() => {
    ...toJson(),
    'payload': jsonEncode(payload),
    'deleted': deleted ? 1 : 0,
  };
  String get title => payload['title'] as String? ?? 'Sin título';
  String get body => payload['body'] as String? ?? '';
  String get status => payload['status'] as String? ?? 'Capturada';
  String? get projectId => payload['projectId'] as String?;
  List<String> get tags => List<String>.from(payload['tags'] ?? []);
  List<String> get attachments =>
      List<String>.from(payload['attachments'] ?? []);
}

class Store extends ChangeNotifier {
  final Database db;
  final String directory;
  List<Entry> _all = [];
  late String deviceId;
  Store._(this.db, this.directory);
  static Future<Store> open({String? directory}) async {
    directory ??= p.join(
      (await getApplicationSupportDirectory()).path,
      'hilva',
    );
    await Directory(directory).create(recursive: true);
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
    }
    final factory = Platform.isWindows || Platform.isLinux
        ? databaseFactoryFfi
        : mobile.databaseFactory;
    final db = await factory.openDatabase(
      p.join(directory, 'hilva.db'),
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, v) async {
          await db.execute(
            'CREATE TABLE entries (id TEXT PRIMARY KEY, kind TEXT NOT NULL, payload TEXT NOT NULL, revision INTEGER NOT NULL, base_revision INTEGER NOT NULL, updated_at TEXT NOT NULL, deleted INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
        },
      ),
    );
    final s = Store._(db, directory);
    s.deviceId = await s.setting('lan_device_id') ?? const Uuid().v4();
    await s.setSetting('lan_device_id', s.deviceId);
    // Give legacy 1.0 records stable clocks before their first LAN exchange.
    await db.transaction((tx) async {
      for (final row in await tx.query('entries')) {
        final payload = Map<String, dynamic>.from(
          jsonDecode(row['payload'] as String),
        );
        if (payload['_lanClock'] == null) {
          payload['_lanClock'] = {s.deviceId: 1};
          await tx.update(
            'entries',
            {'payload': jsonEncode(payload)},
            where: 'id=?',
            whereArgs: [row['id']],
          );
        }
      }
    });
    await s.reload();
    return s;
  }

  List<Entry> get records => _all.where((e) => !e.deleted).toList();
  List<Entry> get allRecords => List.unmodifiable(_all);
  Map<String, int> _clock(Entry? e) =>
      Map<String, int>.from(e?.payload['_lanClock'] ?? {});
  List<Map<String, dynamic>> get pending => _all
      .where((e) => e.revision != e.baseRevision)
      .map((e) => e.toJson())
      .toList();
  Future<void> reload() async {
    _all = (await db.query(
      'entries',
      orderBy: 'updated_at DESC',
    )).map(Entry.fromJson).toList();
    notifyListeners();
  }

  Entry? find(String id) {
    for (final e in records) {
      if (e.id == id) return e;
    }
    return null;
  }

  Future<Entry> save(
    String kind,
    Map<String, dynamic> payload, {
    String? id,
  }) async {
    final old = id == null ? null : find(id);
    final e = Entry(
      id: id ?? const Uuid().v4(),
      kind: kind,
      payload: {
        ...payload,
        '_lanClock': {
          ..._clock(old),
          deviceId: (_clock(old)[deviceId] ?? 0) + 1,
        },
      },
      revision: (old?.revision ?? 0) + 1,
      baseRevision: old?.baseRevision ?? 0,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
    await db.insert(
      'entries',
      e.toDb(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await reload();
    return e;
  }

  Future<void> remove(String id) async {
    final e = find(id);
    if (e == null) return;
    await db.update(
      'entries',
      {
        'deleted': 1,
        'payload': jsonEncode({
          ...e.payload,
          '_lanClock': {..._clock(e), deviceId: (_clock(e)[deviceId] ?? 0) + 1},
        }),
        'revision': e.revision + 1,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id=?',
      whereArgs: [id],
    );
    await reload();
  }

  Future<void> mergeRemote(
    List<Map<String, dynamic>> remote,
    List<Map<String, dynamic>> sent,
  ) async {
    await db.transaction((tx) async {
      for (final j in remote) {
        final e = Entry.fromJson(j);
        final rows = await tx.query(
          'entries',
          where: 'id=?',
          whereArgs: [e.id],
        );
        final local = rows.isEmpty ? null : Entry.fromJson(rows.first);
        final before = sent.where((x) => x['id'] == e.id).firstOrNull;
        if (local != null &&
            local.revision != local.baseRevision &&
            (before == null ||
                before['updated_at'] != local.updatedAt ||
                jsonEncode(before['payload']) != jsonEncode(local.payload))) {
          // Rebase an edit made while the request was in flight, never replace it.
          if (before != null) {
            await tx.update(
              'entries',
              {'base_revision': e.revision, 'revision': e.revision + 1},
              where: 'id=?',
              whereArgs: [e.id],
            );
          }
          continue;
        }
        await tx.insert(
          'entries',
          e.toDb(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    await reload();
  }

  Future<String?> setting(String key) async {
    final rows = await db.query('settings', where: 'key=?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  /// Vector clocks distinguish edits after a sync from simultaneous offline edits.
  /// Concurrent live versions survive as deterministic, convergent copies.
  Future<void> mergeLan(List<Map<String, dynamic>> incoming) async {
    await db.transaction((tx) async {
      for (final json in incoming) {
        var remote = Entry.fromJson(json);
        final rows = await tx.query(
          'entries',
          where: 'id=?',
          whereArgs: [remote.id],
        );
        if (rows.isEmpty) {
          await tx.insert('entries', remote.toDb());
          continue;
        }
        final local = Entry.fromJson(rows.first);
        final a = _clock(local), b = _clock(remote);
        final keys = {...a.keys, ...b.keys};
        final newerA = keys.any((k) => (a[k] ?? 0) > (b[k] ?? 0));
        final newerB = keys.any((k) => (b[k] ?? 0) > (a[k] ?? 0));
        if (!newerB && (a.isNotEmpty || b.isNotEmpty)) continue;
        if (newerA && newerB ||
            (a.isEmpty &&
                b.isEmpty &&
                jsonEncode(local.payload) != jsonEncode(remote.payload))) {
          String signature(Entry e) {
            final clock = _clock(e);
            final sorted = {
              for (final k in clock.keys.toList()..sort()) k: clock[k],
            };
            return sha256
                .convert(
                  utf8.encode(jsonEncode([sorted, e.updatedAt, e.deleted])),
                )
                .toString();
          }

          final winner = signature(local).compareTo(signature(remote)) >= 0
              ? local
              : remote;
          final loser = identical(winner, local) ? remote : local;
          if (!loser.deleted) {
            final copy = Entry(
              id: '${local.id}-conflict-${signature(loser)}',
              kind: loser.kind,
              payload: {
                ...loser.payload,
                'title': '${loser.title} (conflicto)',
                'conflict_of': local.id,
              },
              revision: loser.revision,
              baseRevision: 0,
              updatedAt: loser.updatedAt,
            );
            await tx.insert(
              'entries',
              copy.toDb(),
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
          }
          remote = Entry(
            id: winner.id,
            kind: winner.kind,
            payload: {
              ...winner.payload,
              '_lanClock': {
                for (final k in keys)
                  k: (a[k] ?? 0) > (b[k] ?? 0) ? a[k] : b[k],
              },
            },
            revision: winner.revision,
            baseRevision: winner.baseRevision,
            updatedAt: winner.updatedAt,
            deleted: winner.deleted,
          );
        }
        await tx.insert(
          'entries',
          remote.toDb(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    await reload();
  }

  Future<void> setSetting(String key, String value) => db
      .insert('settings', {
        'key': key,
        'value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace)
      .then((_) {});
  Future<String> addAttachment(String source) async {
    final f = File(source);
    if (await f.length() > 20 * 1024 * 1024) {
      throw Exception('El archivo supera 20 MB.');
    }
    final dir = Directory(p.join(directory, 'attachments'));
    await dir.create(recursive: true);
    final target = p.join(
      dir.path,
      '${const Uuid().v4()}${p.extension(source)}',
    );
    await f.copy(target);
    return target;
  }

  Future<String> exportBackup() async {
    final files = <String, String>{};
    for (final e in records) {
      for (final path in e.attachments) {
        if (await File(path).exists()) {
          files[path] = base64Encode(await File(path).readAsBytes());
        }
      }
    }
    return jsonEncode({
      'format': 'hilva',
      'version': 1,
      'records': _all.map((e) => e.toJson()).toList(),
      'files': files,
    });
  }

  Future<int> importBackup(String data) async {
    final j = jsonDecode(data);
    if (j is! Map ||
        j['format'] != 'hilva' ||
        j['version'] != 1 ||
        j['records'] is! List) {
      throw const FormatException('Respaldo Hilva no válido');
    }
    final entries = (j['records'] as List)
        .map((x) => Entry.fromJson(Map<String, dynamic>.from(x)))
        .toList();
    final mapping = <String, String>{};
    final files = Map<String, dynamic>.from(j['files'] ?? {});
    final dir = Directory(p.join(directory, 'attachments'));
    await dir.create(recursive: true);
    for (final item in files.entries) {
      final bytes = base64Decode(item.value as String);
      if (bytes.length > 20 * 1024 * 1024) {
        throw const FormatException('Adjunto demasiado grande');
      }
      final target = p.join(
        dir.path,
        '${const Uuid().v4()}${p.extension(item.key)}',
      );
      await File(target).writeAsBytes(bytes);
      mapping[item.key] = target;
    }
    await db.transaction((tx) async {
      for (final e in entries) {
        final current = await tx.query(
          'entries',
          where: 'id=?',
          whereArgs: [e.id],
        );
        if (current.isNotEmpty) continue;
        final payload = {
          ...e.payload,
          'attachments': e.attachments.map((f) => mapping[f] ?? f).toList(),
        };
        final copy = Entry(
          id: e.id,
          kind: e.kind,
          payload: payload,
          revision: 1,
          baseRevision: 0,
          updatedAt: DateTime.now().toUtc().toIso8601String(),
          deleted: e.deleted,
        );
        await tx.insert('entries', copy.toDb());
      }
    });
    await reload();
    return entries.length;
  }

  Future<void> close() => db.close();
}
