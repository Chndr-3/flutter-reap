import 'dart:io';

import 'package:flutter_reap/src/cli.dart';

void main(List<String> args) {
  final code = run(
    args,
    readLine: () => stdin.readLineSync() ?? 'k',
    out: stdout,
    err: stderr,
    environment: Platform.environment,
  );
  if (code != 0) exit(code);
}
