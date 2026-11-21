import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hilva/data/store.dart';

void main() {
  test('version 1 notes receive persistent clocks without changing original', () async {
    final dir=await Directory.systemTemp.createTemp('hilva-upgrade');
    var s=await Store.open(directory:dir.path);
    final entry=await s.save('note',{'title':'Antigua','body':'Texto','original':'Texto'});
    await s.db.update('entries',{'payload':'{"title":"Antigua","body":"Texto","original":"Texto"}'},where:'id=?',whereArgs:[entry.id]);
    await s.close();s=await Store.open(directory:dir.path);
    final clock=s.records.single.payload['_lanClock'];expect(clock,isNotEmpty);expect(s.records.single.payload['original'],'Texto');
    await s.close();s=await Store.open(directory:dir.path);expect(s.records.single.payload['_lanClock'],clock);
    await s.close();await dir.delete(recursive:true);
  });

  test('offline save survives reopening and preserves original', () async {
    final dir = await Directory.systemTemp.createTemp('hilva-test');
    var s = await Store.open(directory: dir.path);
    final n = await s.save('note', {
      'title': 'Cola',
      'body': 'Limpiar cola',
      'original': 'Limpiar cola',
    });
    await s.save('note', {
      ...n.payload,
      'body': 'Vaciar cola completa',
    }, id: n.id);
    await s.close();
    s = await Store.open(directory: dir.path);
    expect(s.records.single.payload['original'], 'Limpiar cola');
    expect(s.records.single.payload['body'], 'Vaciar cola completa');
    expect(s.pending.length, 1);
    await s.close();
    await dir.delete(recursive: true);
  });
  test(
    'sync response cannot overwrite changes made during network request',
    () async {
      final dir = await Directory.systemTemp.createTemp('hilva-test');
      final s = await Store.open(directory: dir.path);
      final n = await s.save('note', {'body': 'first'});
      final sent = s.pending;
      await s.save('note', {'body': 'second'}, id: n.id);
      await s.mergeRemote([
        {...sent.single, 'revision': 1, 'base_revision': 1},
      ], sent);
      expect(s.records.single.payload['body'], 'second');
      expect(s.pending.length, 1);
      await s.close();
      await dir.delete(recursive: true);
    },
  );
}
