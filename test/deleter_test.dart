import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:flutter_reap/src/candidate.dart';
import 'package:flutter_reap/src/deleter.dart';

Candidate _c(String path, CandidateKind kind) =>
    Candidate(path: path, bytes: 1, kind: kind, label: path);

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('reap_del_'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('isDeletable', () {
    test('accepts known generated directory names', () {
      for (final name in ['build', '.dart_tool', 'Pods', '.gradle', 'caches', 'cache', 'DerivedData']) {
        expect(
          isDeletable(_c(p.join('/x', name), CandidateKind.projectArtifact)),
          isTrue,
          reason: name,
        );
      }
    });

    test('rejects source directories', () {
      for (final name in ['lib', 'src', 'test', 'ios', 'android']) {
        expect(
          isDeletable(_c(p.join('/x', name), CandidateKind.projectArtifact)),
          isFalse,
          reason: name,
        );
      }
    });

    test('accepts an fvm SDK only under fvm/versions', () {
      expect(
        isDeletable(_c(p.join('/home', 'fvm', 'versions', '3.38.3'), CandidateKind.fvmSdk)),
        isTrue,
      );
      expect(
        isDeletable(_c(p.join('/home', 'projects', '3.38.3'), CandidateKind.fvmSdk)),
        isFalse,
      );
    });

    test('rejects a filesystem root', () {
      expect(isDeletable(_c(p.rootPrefix(Directory.current.path), CandidateKind.sharedCache)), isFalse);
    });

    test('rejects a projectArtifact whose path ends in a version-number segment', () {
      // Only fvmSdk kind gets the version-number exemption.
      expect(
        isDeletable(_c(p.join('/x', '3.38.3'), CandidateKind.projectArtifact)),
        isFalse,
      );
    });

    test('rejects an fvmSdk nested one level too deep under fvm/versions', () {
      expect(
        isDeletable(_c(p.join('/home', 'fvm', 'versions', '3.38.3', 'bin'), CandidateKind.fvmSdk)),
        isFalse,
      );
    });

    test('a trailing separator does not defeat the name check', () {
      expect(
        isDeletable(_c('/x/build/', CandidateKind.projectArtifact)),
        isTrue,
      );
    });

    test('matching is exact, not substring', () {
      for (final name in ['mybuild', 'build-old']) {
        expect(
          isDeletable(_c(p.join('/x', name), CandidateKind.projectArtifact)),
          isFalse,
          reason: name,
        );
      }
    });
  });

  group('deleteCandidates', () {
    test('removes the directory and reports it', () {
      final build = Directory(p.join(tmp.path, 'build'))..createSync();
      File(p.join(build.path, 'blob.bin')).writeAsBytesSync([1, 2, 3]);

      final outcome = deleteCandidates([_c(build.path, CandidateKind.projectArtifact)]);

      expect(build.existsSync(), isFalse);
      expect(outcome.deleted, [build.path]);
      expect(outcome.failed, isEmpty);
    });

    test('refuses a candidate that fails the name check', () {
      final lib = Directory(p.join(tmp.path, 'lib'))..createSync();
      File(p.join(lib.path, 'main.dart')).writeAsStringSync('void main() {}');

      final outcome = deleteCandidates([_c(lib.path, CandidateKind.projectArtifact)]);

      expect(lib.existsSync(), isTrue);
      expect(outcome.deleted, isEmpty);
      expect(outcome.failed.keys, [lib.path]);
    });

    test('a missing directory is not an error', () {
      final outcome = deleteCandidates([
        _c(p.join(tmp.path, 'build'), CandidateKind.projectArtifact),
      ]);
      expect(outcome.failed, isEmpty);
    });

    test('one failure does not stop the rest', () {
      final build = Directory(p.join(tmp.path, 'build'))..createSync();
      final lib = Directory(p.join(tmp.path, 'lib'))..createSync();

      final outcome = deleteCandidates([
        _c(lib.path, CandidateKind.projectArtifact),
        _c(build.path, CandidateKind.projectArtifact),
      ]);

      expect(outcome.deleted, [build.path]);
      expect(outcome.failed.length, 1);
      expect(lib.existsSync(), isTrue);
    });

    test('deleteCandidates([]) returns an empty outcome without error', () {
      final outcome = deleteCandidates([]);
      expect(outcome.deleted, isEmpty);
      expect(outcome.failed, isEmpty);
    });
  });
}
