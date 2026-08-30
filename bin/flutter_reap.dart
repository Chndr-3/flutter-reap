import 'dart:io';

import 'package:flutter_reap/src/cli.dart';

void main(List<String> args) {
  final code = run(
    args,
    readLine: () => stdin.readLineSync() ?? 'k',
    out: stdout,
    err: stderr,
    environment: Platform.environment,
    // Only draw the carriage-returned progress line when stderr is an actual
    // terminal, so a piped stderr (CI logs, `2> file`) stays clean.
    showProgress: stderr.hasTerminal,
  );
  if (code != 0) exit(code);
}
