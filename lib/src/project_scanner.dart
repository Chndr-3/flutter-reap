import 'dart:io';
import 'package:path/path.dart' as p;

/// Generated directories inside a Flutter project, relative to its root.
const List<String> artifactRelativePaths = [
  'build',
  '.dart_tool',
  'ios/Pods',
  'macos/Pods',
  'android/.gradle',
];

const _skipNames = {
  '.pub-cache',
  'node_modules',
  'build',
  '.dart_tool',
  'Pods',
  '.git',
};

/// Absolute paths of every Flutter project under [root].
///
/// A project is any directory containing a `pubspec.yaml`. Vendored copies are
/// excluded: anything inside `.pub-cache`, inside an fvm SDK checkout
/// (`fvm/versions/...`), or inside a generated directory, since those pubspecs
/// belong to dependencies rather than to the user's work.
List<String> findProjects(String root, {int maxDepth = 6}) {
  final found = <String>[];
  final rootDepth = p.split(p.normalize(p.absolute(root))).length;
  final stack = <Directory>[Directory(p.absolute(root))];

  while (stack.isNotEmpty) {
    final dir = stack.removeLast();
    final List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } on FileSystemException {
      continue;
    }

    for (final entry in entries) {
      final name = p.basename(entry.path);
      if (entry is File) {
        if (name == 'pubspec.yaml') found.add(dir.path);
      } else if (entry is Directory) {
        if (_skipNames.contains(name)) continue;
        if (_insideFvmVersions(entry.path)) continue;
        final depth = p.split(p.normalize(entry.path)).length - rootDepth;
        if (depth < maxDepth) stack.add(entry);
      }
    }
  }
  found.sort();
  return found;
}

bool _insideFvmVersions(String dir) {
  final parts = p.split(dir);
  final index = parts.indexOf('versions');
  return index > 0 && parts[index - 1] == 'fvm';
}
