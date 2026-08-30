import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:flutter_reap/src/shared_caches.dart';

void main() {
  bool always(String _) => true;

  test('macOS includes DerivedData and the CocoaPods cache', () {
    final paths = sharedCachePaths(
      os: 'macos',
      env: {'HOME': '/Users/x'},
      exists: always,
    );
    expect(paths, contains(p.join('/Users/x', 'Library', 'Developer', 'Xcode', 'DerivedData')));
    expect(paths, contains(p.join('/Users/x', 'Library', 'Caches', 'CocoaPods')));
  });

  test('linux includes gradle caches but no Xcode paths', () {
    final paths = sharedCachePaths(os: 'linux', env: {'HOME': '/home/x'}, exists: always);
    expect(paths, contains(p.join('/home/x', '.gradle', 'caches')));
    expect(paths.any((path) => path.contains('Xcode')), isFalse);
  });

  test('windows uses USERPROFILE', () {
    final paths = sharedCachePaths(
      os: 'windows',
      env: {'USERPROFILE': r'C:\Users\x', 'LOCALAPPDATA': r'C:\Users\x\AppData\Local'},
      exists: always,
    );
    expect(paths, contains(p.join(r'C:\Users\x', '.gradle', 'caches')));
  });

  test('never offers the pub cache on any platform', () {
    for (final os in ['macos', 'linux', 'windows']) {
      final paths = sharedCachePaths(
        os: os,
        env: {
          'HOME': '/Users/x',
          'USERPROFILE': r'C:\Users\x',
          'LOCALAPPDATA': r'C:\Users\x\AppData\Local',
        },
        exists: always,
      );
      expect(
        paths.any((path) => path.toLowerCase().contains('pub')),
        isFalse,
        reason: '$os offered a pub cache path',
      );
    }
  });

  test('omits directories that do not exist', () {
    final paths = sharedCachePaths(os: 'linux', env: {'HOME': '/home/x'}, exists: (_) => false);
    expect(paths, isEmpty);
  });

  test('returns nothing when the home directory is unknown', () {
    expect(sharedCachePaths(os: 'linux', env: {}, exists: always), isEmpty);
  });

  test('windows with both HOME (POSIX) and USERPROFILE prefers USERPROFILE', () {
    final paths = sharedCachePaths(
      os: 'windows',
      env: {
        'HOME': '/c/Users/alice',
        'USERPROFILE': r'C:\Users\alice',
      },
      exists: always,
    );
    // All paths should be rooted at USERPROFILE, not the POSIX-style HOME
    expect(paths.every((path) => path.startsWith(r'C:\Users\alice')), isTrue);
    expect(paths.any((path) => path.contains('/c/Users/alice')), isFalse);
  });

  test('windows with only HOME falls back to that', () {
    final paths = sharedCachePaths(
      os: 'windows',
      env: {
        'HOME': '/home/alice',
      },
      exists: always,
    );
    expect(paths, isNotEmpty);
    expect(paths, contains(p.join('/home/alice', '.gradle', 'caches')));
  });

  test('posix systems with both HOME and USERPROFILE prefer HOME', () {
    for (final os in ['macos', 'linux']) {
      final paths = sharedCachePaths(
        os: os,
        env: {
          'HOME': '/Users/alice',
          'USERPROFILE': r'C:\Users\alice',
        },
        exists: always,
      );
      // All paths should be rooted at HOME, not USERPROFILE
      expect(paths.every((path) => path.startsWith('/Users/alice')), isTrue,
          reason: '$os should prefer HOME when both are set');
    }
  });
}
