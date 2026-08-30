import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:flutter_reap/src/cli.dart';

/// The sentinel `bin/flutter_reap.dart` passes when stdin has hit EOF.
const _eofSentinel = 'k';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('cli_run_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Directory makeProject(Directory parent, String name, {required int fileBytes}) {
    final dir = Directory(p.join(parent.path, name))..createSync(recursive: true);
    File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('name: $name\n');
    File(p.join(dir.path, 'lib', 'main.dart'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('void main() {}\n');
    final build = Directory(p.join(dir.path, 'build'))..createSync();
    File(p.join(build.path, 'blob.bin')).writeAsBytesSync(List.filled(fileBytes, 0));
    return dir;
  }

  int runCli(
    List<String> args, {
    String Function()? readLine,
    required StringSink out,
    required StringSink err,
    Map<String, String>? environment,
  }) {
    return run(
      args,
      readLine: readLine ?? () => _eofSentinel,
      out: out,
      err: err,
      environment: environment ?? {'HOME': tmp.path},
    );
  }

  test('dry run lists the build directory and deletes nothing', () {
    final project = makeProject(tmp, 'app', fileBytes: 2048);
    final out = StringBuffer();
    final err = StringBuffer();

    final code = runCli([tmp.path, '--days', '0'], out: out, err: err);

    expect(code, 0);
    expect(out.toString(), contains('build'));
    expect(out.toString(), contains('dry run'));
    expect(Directory(p.join(project.path, 'build')).existsSync(), isTrue);
  });

  test('EOF at the prompt cancels and deletes nothing', () {
    final project = makeProject(tmp, 'app', fileBytes: 2048);
    final out = StringBuffer();
    final err = StringBuffer();

    final code = runCli(
      [tmp.path, '--days', '0', '--delete'],
      readLine: () => _eofSentinel,
      out: out,
      err: err,
    );

    expect(code, 0);
    expect(out.toString(), contains('cancelled - nothing deleted'));
    expect(Directory(p.join(project.path, 'build')).existsSync(), isTrue);
  });

  test('an empty answer deletes the build dir but spares source files', () {
    final project = makeProject(tmp, 'app', fileBytes: 2048);
    final out = StringBuffer();
    final err = StringBuffer();

    final code = runCli(
      [tmp.path, '--days', '0', '--delete'],
      readLine: () => '',
      out: out,
      err: err,
    );

    expect(code, 0);
    expect(Directory(p.join(project.path, 'build')).existsSync(), isFalse);
    expect(File(p.join(project.path, 'lib', 'main.dart')).existsSync(), isTrue);
    expect(File(p.join(project.path, 'pubspec.yaml')).existsSync(), isTrue);
  });

  test('keeping the only listed candidate deletes nothing', () {
    final project = makeProject(tmp, 'app', fileBytes: 2048);
    final out = StringBuffer();
    final err = StringBuffer();

    final code = runCli(
      [tmp.path, '--days', '0', '--delete'],
      readLine: () => '1',
      out: out,
      err: err,
    );

    expect(code, 0);
    expect(Directory(p.join(project.path, 'build')).existsSync(), isTrue);
  });

  test('--json emits parseable JSON and never deletes, even with --delete', () {
    final project = makeProject(tmp, 'app', fileBytes: 2048);
    final out = StringBuffer();
    final err = StringBuffer();

    final code = runCli(
      [tmp.path, '--days', '0', '--json', '--delete'],
      readLine: () => '',
      out: out,
      err: err,
    );

    expect(code, 0);
    final decoded = jsonDecode(out.toString());
    expect(decoded, isA<Map<String, dynamic>>());
    expect(Directory(p.join(project.path, 'build')).existsSync(), isTrue);
  });

  test('--yes without --days exits 64 with usage on stderr', () {
    makeProject(tmp, 'app', fileBytes: 2048);
    final out = StringBuffer();
    final err = StringBuffer();

    final code = runCli([tmp.path, '--delete', '--yes'], out: out, err: err);

    expect(code, 64);
    expect(err.toString(), isNotEmpty);
  });

  test('a narrow scan root never surfaces machine-wide caches or fvm SDKs', () {
    // HOME (tmp) carries an fvm SDK and looks like it has shared caches, but
    // the scan root is a subdirectory of HOME, not HOME itself.
    Directory(p.join(tmp.path, 'fvm', 'versions', '3.38.3')).createSync(recursive: true);
    Directory(p.join(tmp.path, '.gradle', 'caches')).createSync(recursive: true);
    File(p.join(tmp.path, '.gradle', 'caches', 'blob.bin'))
        .writeAsBytesSync(List.filled(2048, 0));

    final subRoot = Directory(p.join(tmp.path, 'projects'))..createSync(recursive: true);
    makeProject(subRoot, 'app', fileBytes: 2048);

    final out = StringBuffer();
    final err = StringBuffer();

    final code = runCli(
      [subRoot.path, '--days', '0', '--json'],
      environment: {'HOME': tmp.path},
      out: out,
      err: err,
    );

    expect(code, 0);
    final decoded = jsonDecode(out.toString()) as Map<String, dynamic>;
    final kinds = (decoded['candidates'] as List)
        .map((c) => (c as Map<String, dynamic>)['kind'])
        .toSet();
    expect(kinds.contains('sharedCache'), isFalse);
    expect(kinds.contains('fvmSdk'), isFalse);
  });
}
