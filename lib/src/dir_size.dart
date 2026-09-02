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

/// Size on disk in bytes of everything under [path], or 0 if it is missing.
int directorySizeBytes(String path) => walkSizeBytes(path);
