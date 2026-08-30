import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:flutter_reap/src/staleness.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('reap_stale_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('falls back to pubspec mtime when there is no git repo', () {
    final pubspec = File(p.join(tmp.path, 'pubspec.yaml'))..writeAsStringSync('name: x\n');
    pubspec.setLastModifiedSync(DateTime(2024, 1, 1));

    final result = stalenessOf(tmp.path, now: DateTime(2024, 3, 1));
    expect(result.ageDays, 60);
    expect(result.dirty, isFalse);
  });

  test('prefers the last commit date over file mtime', () {
    File(p.join(tmp.path, 'pubspec.yaml')).writeAsStringSync('name: x\n');
    _git(tmp.path, ['init', '-q']);
    _git(tmp.path, ['config', 'user.email', 'test@example.com']);
    _git(tmp.path, ['config', 'user.name', 'Test']);
    _git(tmp.path, ['add', '.']);
    _git(tmp.path, ['commit', '-qm', 'init', '--date', '2024-01-01T00:00:00']);

    // pubspec.yaml is brand new; the commit is old. The commit must win.
    final result = stalenessOf(tmp.path, now: DateTime(2024, 1, 31));
    expect(result.ageDays, 30);
  });

  test('reports uncommitted changes as dirty', () {
    File(p.join(tmp.path, 'pubspec.yaml')).writeAsStringSync('name: x\n');
    _git(tmp.path, ['init', '-q']);
    _git(tmp.path, ['config', 'user.email', 'test@example.com']);
    _git(tmp.path, ['config', 'user.name', 'Test']);
    _git(tmp.path, ['add', '.']);
    _git(tmp.path, ['commit', '-qm', 'init']);
    File(p.join(tmp.path, 'lib.dart')).writeAsStringSync('void main() {}\n');

    expect(stalenessOf(tmp.path).dirty, isTrue);
  });

  test('treats a missing pubspec as age zero rather than crashing', () {
    expect(stalenessOf(tmp.path, now: DateTime(2024, 1, 1)).ageDays, 0);
  });
}

void _git(String dir, List<String> args) {
  final result = Process.runSync('git', ['-C', dir, ...args]);
  if (result.exitCode != 0) throw StateError('git ${args.join(' ')}: ${result.stderr}');
}
