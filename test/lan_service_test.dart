import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hilva/data/store.dart';
import 'package:hilva/services/lan_service.dart';

void main() {
  test(
    'encrypted two-peer sync preserves edits, conflicts, files and deletion',
    () async {
      final aDir = await Directory.systemTemp.createTemp('hilva-a');
      final bDir = await Directory.systemTemp.createTemp('hilva-b');
      final a = await Store.open(directory: aDir.path),
          b = await Store.open(directory: bDir.path);
      Future<String?> read(String k) async => null;
      Future<void> write(String k, String v) async {}
      final x = LanService(a, port: 0, readSecret: read, writeSecret: write),
          y = LanService(b, port: 0, readSecret: read, writeSecret: write);
      try {
        await x.start();
        await y.start();
        final file = File('${aDir.path}/source.txt');
        await file.writeAsString('attachment');
        final path = await a.addAttachment(file.path);
        final note = await a.save('note', {
          'title': 'Idea',
          'body': 'original',
          'original': 'original',
          'attachments': [path],
        });
        final code = await x.pairingCode(host: '127.0.0.1');
        await y.pair(code);
        expect(b.records.single.body, 'original');
        expect(
          await File(b.records.single.attachments.single).readAsString(),
          'attachment',
        );
        await a.save('note', {
          ...a.find(note.id)!.payload,
          'body': 'PC',
        }, id: note.id);
        await b.save('note', {
          ...b.find(note.id)!.payload,
          'body': 'Android',
        }, id: note.id);
        await y.sync();
        await x.sync();
        expect(
          a.records.map((e) => e.body).toSet(),
          containsAll(['PC', 'Android']),
        );
        expect(b.records.length, a.records.length);
        await a.remove(note.id);
        await y.sync();
        expect(b.find(note.id), isNull);
        final bad = jsonDecode(await x.pairingCode(host: '127.0.0.1'));
        bad['secret'] = base64UrlEncode(List.filled(32, 0));
        await expectLater(y.pair(jsonEncode(bad)), throwsA(anything));
      } finally {
        x.dispose();
        y.dispose();
        await a.close();
        await b.close();
        await aDir.delete(recursive: true);
        await bDir.delete(recursive: true);
      }
    },
  );
}
