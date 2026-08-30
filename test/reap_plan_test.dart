import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:flutter_reap/src/candidate.dart';
import 'package:flutter_reap/src/reap_plan.dart';

Candidate _c(String path, int bytes) => Candidate(
      path: path,
      bytes: bytes,
      kind: CandidateKind.projectArtifact,
      label: path,
    );

void main() {
  group('pure selection logic', () {
    test('sorts largest first', () {
      final sorted = sortBySize([_c('a', 10), _c('b', 300), _c('c', 20)]);
      expect(sorted.map((c) => c.path), ['b', 'c', 'a']);
    });

    test('keeping nothing deletes everything listed', () {
      final listed = [_c('a', 1), _c('b', 2)];
      expect(survivors(listed, {}).length, 2);
    });

    test('keeping an index spares exactly that candidate', () {
      final listed = [_c('a', 1), _c('b', 2), _c('c', 3)];
      expect(survivors(listed, {2}).map((c) => c.path), ['a', 'c']);
    });

    test('keeping every index deletes nothing', () {
      final listed = [_c('a', 1), _c('b', 2)];
      expect(survivors(listed, {1, 2}), isEmpty);
    });

    test('out-of-range keep indexes are ignored', () {
      final listed = [_c('a', 1)];
      expect(survivors(listed, {5}).length, 1);
    });
  });

  group('buildPlan', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('reap_plan_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    void makeProject(String name, {required int fileBytes}) {
      final dir = Directory(p.join(tmp.path, name))..createSync(recursive: true);
      File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('name: $name\n');
      final build = Directory(p.join(dir.path, 'build'))..createSync();
      File(p.join(build.path, 'blob.bin')).writeAsBytesSync(List.filled(fileBytes, 0));
    }

    test('collects project artifacts', () {
      makeProject('app', fileBytes: 2048);
      final plan = buildPlan(
        root: tmp.path,
        home: tmp.path,
        minDays: 0,
        includeMachineWide: false,
      );
      expect(plan.single.path, p.join(tmp.path, 'app', 'build'));
      expect(plan.single.bytes, 2048);
    });

    test('skips projects with no artifacts at all', () {
      final dir = Directory(p.join(tmp.path, 'clean'))..createSync();
      File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('name: clean\n');

      final plan = buildPlan(
        root: tmp.path,
        home: tmp.path,
        minDays: 0,
        includeMachineWide: false,
      );
      expect(plan, isEmpty);
    });

    test('minDays filters out freshly touched projects', () {
      makeProject('app', fileBytes: 1024);
      final plan = buildPlan(
        root: tmp.path,
        home: tmp.path,
        minDays: 30,
        includeMachineWide: false,
      );
      expect(plan, isEmpty);
    });

    test('includeMachineWide false yields no shared caches or fvm SDKs', () {
      makeProject('app', fileBytes: 1024);
      Directory(p.join(tmp.path, 'fvm', 'versions', '3.38.3')).createSync(recursive: true);

      final plan = buildPlan(
        root: tmp.path,
        home: tmp.path,
        minDays: 0,
        includeMachineWide: false,
      );
      expect(plan.any((c) => c.kind != CandidateKind.projectArtifact), isFalse);
    });

    test('includeMachineWide true yields unused fvm SDKs', () {
      Directory(p.join(tmp.path, 'fvm', 'versions', '3.38.3')).createSync(recursive: true);

      final plan = buildPlan(
        root: tmp.path,
        home: tmp.path,
        minDays: 0,
        includeMachineWide: true,
      );
      expect(plan.where((c) => c.kind == CandidateKind.fvmSdk).length, 1);
    });
  });
}
