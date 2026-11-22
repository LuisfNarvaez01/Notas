// Run only against an isolated installation copied for the update regression test.
// The parent deliberately owns the target's current directory until it exits.
import 'dart:io';

import 'package:hilva/services/windows_updater.dart';

Future<void> main(List<String> args) async {
  if (args.length != 5) throw ArgumentError('helper archive target temp state');
  Directory.current = args[2];
  await WindowsUpdater.prepare(
    helperPath: args[0],
    archivePath: args[1],
    destination: args[2],
    temporaryDirectory: args[3],
    statePath: args[4],
    waitPid: pid,
  );
  stdout.writeln('READY: preflight succeeded before the parent exits.');
  exit(0);
}
