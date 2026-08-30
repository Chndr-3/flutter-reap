import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:flutter_reap/src/project_scanner.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('reap_scan_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  void makeProject(String relative) {
    final dir = Directory(p.join(tmp.path, relative))..createSync(recursive: true);
    File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('name: x\n');
  }

  test('finds a project at the root', () {
    makeProject('app');
    expect(findProjects(tmp.path), [p.join(tmp.path, 'app')]);
  });

  test('finds nested projects', () {
    makeProject('a');
    makeProject(p.join('a', 'example'));
    expect(findProjects(tmp.path).length, 2);
  });

  test('ignores pubspecs inside .pub-cache', () {
    makeProject(p.join('.pub-cache', 'hosted', 'thing'));
    expect(findProjects(tmp.path), isEmpty);
  });

  test('ignores pubspecs inside fvm SDK checkouts', () {
    makeProject(p.join('fvm', 'versions', '3.38.3'));
    expect(findProjects(tmp.path), isEmpty);
  });

  test('does not descend into build or .dart_tool', () {
    makeProject('app');
    makeProject(p.join('app', 'build', 'stale'));
    expect(findProjects(tmp.path), [p.join(tmp.path, 'app')]);
  });

  test('respects maxDepth', () {
    makeProject(p.join('a', 'b', 'c', 'd', 'e', 'f', 'g'));
    expect(findProjects(tmp.path, maxDepth: 3), isEmpty);
  });
}
