import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Handshake with the helper: never close Hilva before preflight succeeds.
class WindowsUpdater {
  static Future<void> prepare({
    required String helperPath,
    required String archivePath,
    required String destination,
    required String temporaryDirectory,
    required String statePath,
    required int waitPid,
  }) async {
    final helper = File(helperPath);
    if (!await helper.exists()) {
      throw StateError('Falta el asistente; usa el paquete portable completo.');
    }
    final temp = Directory(temporaryDirectory).absolute;
    await temp.create(recursive: true);
    final copy = await helper.copy(
      p.join(temp.path, 'hilva-update-$waitPid.ps1'),
    );
    final state = File(statePath);
    await state.parent.create(recursive: true);
    if (await state.exists()) await state.delete();
    final hash = (await sha256.bind(File(archivePath).openRead()).first)
        .toString();
    final powershellDirectory = p.join(
      Platform.environment['SystemRoot'] ?? r'C:\Windows',
      'System32',
      'WindowsPowerShell',
      'v1.0',
    );
    final process = await Process.start(
      p.join(powershellDirectory, 'powershell.exe'),
      [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-WindowStyle',
        'Hidden',
        '-File',
        copy.path,
        '-Archive',
        File(archivePath).absolute.path,
        '-Destination',
        Directory(destination).absolute.path,
        '-WaitPid',
        '$waitPid',
        '-ExpectedHash',
        hash,
        '-StateFile',
        state.absolute.path,
      ],
      workingDirectory: temp.path,
      // Do not inherit PowerShell 7's incompatible module search path.
      environment: {'PSModulePath': p.join(powershellDirectory, 'Modules')},
      // Windows PowerShell 5 can exit silently with DETACHED_PROCESS (no console
      // handles). Hidden normal mode works; install calls exit(0) after ready,
      // which closes our handles without terminating the Windows child.
      mode: ProcessStartMode.normal,
    );
    var ended = false;
    var startupError = '';
    final output = process.stdout.transform(utf8.decoder).listen((chunk) {
      if (startupError.length < 2000) startupError += chunk;
    });
    final errors = process.stderr.transform(utf8.decoder).listen((chunk) {
      if (startupError.length < 2000) startupError += chunk;
    }, onDone: () => ended = true);
    try {
      final deadline = DateTime.now().add(const Duration(seconds: 90));
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (ended) {
          throw StateError(
            'El asistente se cerró antes de preparar la actualización. $startupError',
          );
        }
        if (!await state.exists()) continue;
        Map<String, dynamic> result;
        try {
          result = jsonDecode(
            (await state.readAsString()).replaceFirst('\uFEFF', ''),
          ) as Map<String, dynamic>;
        } on FormatException {
          continue; // The helper is in the middle of writing its status.
        }
        if (result['status'] == 'ready') return;
        if (result['status'] == 'failed') {
          throw StateError(
            'El asistente no pudo preparar la actualización: ${result['message']}',
          );
        }
      }
      throw StateError(
        'El asistente no confirmó que pudiera actualizar. Hilva permanece abierta; consulta $statePath.',
      );
    } finally {
      await output.cancel();
      await errors.cancel();
    }
  }
}
