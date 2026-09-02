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
    result = Process.runSync('du', ['-sk', '--', path]);
  } catch (e) {
    return null; // du missing or unspawnable
  }
  final first = (result.stdout as String).trimLeft().split(RegExp(r'\s')).first;
  final kilobytes = int.tryParse(first);
  return kilobytes == null ? null : kilobytes * 1024;
}

/// Size on disk in bytes of everything under [path], or 0 if it is missing.
///
/// Prefers `du`, falling back to [walkSizeBytes] on Windows or whenever `du`
/// cannot answer. Each `du` call pays a fixed process-spawn cost — roughly
/// 8.8ms on macOS/APFS against roughly 0.04ms for the walk on a trivial
/// directory — so `du` loses on small trees (measured: 8 entries, walk 0ms,
/// du 25ms) and wins on large ones (measured: 11,670 entries, walk 207ms, du
/// 170ms; 84,501 entries, walk 2782ms, du 1135ms). The large trees are what
/// dominate a scan's wall clock — a home-directory scan spends most of its
/// time sizing Xcode DerivedData — so `du` is the better default despite
/// losing on the small cases.
///
/// The two also disagree slightly on the number itself — `du` reports
/// allocated blocks, the walk reports apparent size — and `du`'s answer is
/// the one the tool means by "reclaimable".
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
  // A 0 from du is not trusted on its own: du -sk does not follow a symlink
  // given directly as its argument, so a candidate that is itself a symlink
  // (a DerivedData or build/ directory relinked onto another volume) reads as
  // an empty tree and would otherwise vanish from the plan. Falling back to
  // the walk here costs one extra walk on a genuinely empty directory, which
  // also returns 0, so the fallback is free in the common case.
  final duResult = du(path);
  if (duResult == null) return walkSizeBytes(path);
  if (duResult == 0) return walkSizeBytes(path);
  return duResult;
}
