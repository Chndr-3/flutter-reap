import 'dart:io';

/// Total apparent size in bytes of every file under [path].
///
/// Walks iteratively rather than with `listSync(recursive: true)` so that a
/// single unreadable subdirectory is skipped instead of ending the walk.
/// Symlinks are never followed, so a link out of the tree cannot inflate the
/// total or cause an infinite loop.
///
/// This sums file lengths, so it reports apparent size rather than the blocks
/// actually allocated on disk. [directorySizeBytes] is what the tool reports;
/// this is its portable fallback.
int walkSizeBytes(String path) {
  final root = Directory(path);
  if (!root.existsSync()) return 0;

  var total = 0;
  final stack = <Directory>[root];

  while (stack.isNotEmpty) {
    final dir = stack.removeLast();
    final List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } on FileSystemException {
      continue; // unreadable directory: skip, never fatal
    }

    for (final entry in entries) {
      if (entry is File) {
        try {
          total += entry.lengthSync();
        } on FileSystemException {
          continue;
        }
      } else if (entry is Directory) {
        stack.add(entry);
      }
    }
  }
  return total;
}

/// Allocated size in bytes of everything under [path] according to `du -sk`,
/// or null when `du` cannot answer.
///
/// Returns blocks actually allocated rather than the sum of file lengths, so
/// the figure matches what `df` gives back after a delete and hardlinked
/// content is counted once.
///
/// The exit code is deliberately ignored. `du` on a tree containing one
/// unreadable subdirectory writes the diagnostic to stderr, prints a correct
/// total to stdout, and exits 1; treating that as failure would drop every
/// mixed-permission tree onto the slow walk, which is the exact shape of a
/// real DerivedData directory. Null is returned only when the process cannot
/// run at all or stdout does not begin with a number.
int? duSizeBytes(String path) {
  final ProcessResult result;
  try {
    result = Process.runSync('du', ['-sk', path]);
  } catch (e) {
    return null; // du missing or unspawnable
  }
  final first = (result.stdout as String).trimLeft().split(RegExp(r'\s')).first;
  final kilobytes = int.tryParse(first);
  return kilobytes == null ? null : kilobytes * 1024;
}

/// Size on disk in bytes of everything under [path], or 0 if it is missing.
///
/// Prefers `du`, which is several times faster than walking every file from
/// Dart on the large trees this tool exists for, and falls back to
/// [walkSizeBytes] on Windows or whenever `du` cannot answer. The two disagree
/// slightly — `du` reports allocated blocks, the walk reports apparent size —
/// and `du`'s answer is the one the tool means by "reclaimable".
///
/// [du] is injected only so the fallback branch can be tested: on a machine
/// that has `du`, nothing else ever takes it, which makes it the branch most
/// likely to rot unnoticed. Callers leave it alone.
int directorySizeBytes(
  String path, {
  int? Function(String path) du = duSizeBytes,
}) {
  // Checked before spawning anything: a missing directory is common (most
  // projects have no macos/Pods) and must not cost a process.
  if (!Directory(path).existsSync()) return 0;
  if (Platform.isWindows) return walkSizeBytes(path);
  return du(path) ?? walkSizeBytes(path);
}
