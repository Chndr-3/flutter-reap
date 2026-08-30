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
}
