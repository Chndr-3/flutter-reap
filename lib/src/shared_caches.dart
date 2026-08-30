import 'dart:io';
import 'package:path/path.dart' as p;

/// Machine-wide caches worth reclaiming on [os], filtered to those that exist.
///
/// [env] and [exists] are injected so the platform matrix can be tested on a
/// single machine. All OS-specific knowledge in the package lives here.
///
/// The pub cache is deliberately absent on every platform: it is shared by every
/// project and slow to refetch, and `dart pub cache clean` already covers it.
List<String> sharedCachePaths({
  required String os,
  required Map<String, String> env,
  bool Function(String path)? exists,
}) {
  final present = exists ?? (path) => Directory(path).existsSync();
  final home = env['HOME'] ?? env['USERPROFILE'];
  if (home == null) return const [];

  final candidates = <String>[];
  switch (os) {
    case 'macos':
      candidates.addAll([
        p.join(home, 'Library', 'Developer', 'Xcode', 'DerivedData'),
        p.join(home, 'Library', 'Caches', 'CocoaPods'),
        p.join(home, '.gradle', 'caches'),
        p.join(home, '.android', 'cache'),
      ]);
    case 'linux':
      candidates.addAll([
        p.join(home, '.gradle', 'caches'),
        p.join(home, '.android', 'cache'),
      ]);
    case 'windows':
      candidates.addAll([
        p.join(home, '.gradle', 'caches'),
        p.join(home, '.android', 'cache'),
      ]);
  }
  return candidates.where(present).toList();
}
