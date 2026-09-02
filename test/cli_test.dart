import 'dart:io';

import 'package:test/test.dart';
import 'package:flutter_reap/src/cli.dart';
import 'package:flutter_reap/src/candidate.dart';

void main() {
  test('defaults to a dry run of the current directory', () {
    final options = parseArgs([]);
    expect(options.delete, isFalse);
    expect(options.minDays, 0);
    expect(options.json, isFalse);
  });

  test('parses days and delete', () {
    final options = parseArgs(['--days', '60', '--delete', '/tmp/x']);
    expect(options.minDays, 60);
    expect(options.delete, isTrue);
    expect(options.root, '/tmp/x');
  });

  test('--yes requires --days', () {
    expect(
      () => parseArgs(['--delete', '--yes']),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => parseArgs(['--delete', '--yes', '--days', '30']),
      returnsNormally,
    );
  });

  test('--json implies a dry run even alongside --delete', () {
    expect(parseArgs(['--json', '--delete']).delete, isFalse);
  });

  test('a negative day count is rejected', () {
    expect(() => parseArgs(['--days', '-5']), throwsA(isA<FormatException>()));
  });

  test('a non-numeric day count is rejected', () {
    expect(() => parseArgs(['--days', 'soon']), throwsA(isA<FormatException>()));
  });

  test('refuses a filesystem root as the scan root', () {
    expect(() => parseArgs(['/']), throwsA(isA<FormatException>()));
  });

  test('more than one path is rejected', () {
    expect(() => parseArgs(['/tmp/a', '/tmp/b']), throwsA(isA<FormatException>()));
  });

  test('listing is numbered from one and marks dirty projects', () {
    final listing = renderListing([
      Candidate(
        path: '/x/build',
        bytes: 5 * 1024 * 1024,
        kind: CandidateKind.projectArtifact,
        label: '/x/build',
        ageDays: 42,
        dirty: true,
      ),
    ]);
    expect(listing, contains('1.'));
    expect(listing, contains('5M'));
    expect(listing, contains('42d'));
    expect(listing, contains('!'));
  });

  test('json output carries the total and each path', () {
    final json = renderJson([
      Candidate(path: '/x/build', bytes: 100, kind: CandidateKind.projectArtifact, label: '/x/build'),
    ]);
    expect(json, contains('"totalBytes": 100'));
    expect(json, contains('"/x/build"'));
  });

  group('resolveHome', () {
    final env = {'HOME': '/home/bob', 'USERPROFILE': r'C:\Users\bob'};

    test('POSIX branch: HOME wins on macOS/Linux', () {
      expect(resolveHome(env, 'macos'), '/home/bob');
      expect(resolveHome(env, 'linux'), '/home/bob');
    });

    test('Windows branch: USERPROFILE wins, matching shared_caches.dart', () {
      expect(resolveHome(env, 'windows'), r'C:\Users\bob');
    });

    test('falls back to the other variable when the preferred one is unset', () {
      expect(resolveHome({'USERPROFILE': r'C:\Users\bob'}, 'macos'), r'C:\Users\bob');
      expect(resolveHome({'HOME': '/home/bob'}, 'windows'), '/home/bob');
    });

    test('empty when neither is set', () {
      expect(resolveHome({}, 'macos'), '');
      expect(resolveHome({}, 'windows'), '');
    });
  });

  test('packageVersion matches the version in pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final declared = RegExp(r'^version:\s*(\S+)', multiLine: true)
        .firstMatch(pubspec)
        ?.group(1);

    expect(declared, isNotNull, reason: 'pubspec.yaml has no version: line');
    expect(packageVersion, declared);
  });
}
