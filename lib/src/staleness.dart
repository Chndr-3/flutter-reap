import 'dart:io';
import 'package:path/path.dart' as p;

/// How long ago a human last touched a project, and whether work is in flight.
class Staleness {
  /// Whole days since the last commit, or since `pubspec.yaml` was modified.
  final int ageDays;

  /// Whether the project has uncommitted changes.
  final bool dirty;

  /// Creates a [Staleness] record with the given age and dirty status.
  const Staleness({required this.ageDays, required this.dirty});
}

/// When a human last touched [projectDir].
///
/// Uses the last commit date, falling back to the modification time of
/// `pubspec.yaml` for projects that are not git repositories.
///
/// It deliberately never looks at the build directory's own timestamp: that
/// resets on every build, so a long-dead project would look freshly touched and
/// an age filter would silently match nothing.
Staleness stalenessOf(String projectDir, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  DateTime? lastTouched;
  var dirty = false;

  try {
    final log = Process.runSync(
      'git',
      ['-C', projectDir, 'log', '-1', '--format=%ct'],
    );
    if (log.exitCode == 0) {
      final seconds = int.tryParse((log.stdout as String).trim());
      if (seconds != null) {
        lastTouched = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
      }
      final status = Process.runSync(
        'git',
        ['-C', projectDir, 'status', '--porcelain'],
      );
      dirty = status.exitCode == 0 && (status.stdout as String).trim().isNotEmpty;
    }
  } catch (e) {
    // git is not installed or inaccessible; fall through to the mtime path.
  }

  lastTouched ??= _pubspecModified(projectDir) ?? reference;
  final age = reference.difference(lastTouched).inDays;
  return Staleness(ageDays: age < 0 ? 0 : age, dirty: dirty);
}

DateTime? _pubspecModified(String projectDir) {
  final pubspec = File(p.join(projectDir, 'pubspec.yaml'));
  try {
    return pubspec.existsSync() ? pubspec.lastModifiedSync() : null;
  } on FileSystemException {
    return null;
  }
}
