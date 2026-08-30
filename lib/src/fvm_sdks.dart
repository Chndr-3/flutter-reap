import 'dart:io';
import 'package:path/path.dart' as p;

/// An installed fvm SDK and how many projects reference it.
class FvmSdk {
  /// Version string, which is also the directory name.
  final String version;

  /// Absolute path of the SDK checkout.
  final String path;

  /// Number of project configs naming this version.
  final int referenceCount;

  /// Creates an fvm SDK entry with version, path, and reference count.
  const FvmSdk({
    required this.version,
    required this.path,
    required this.referenceCount,
  });

  /// Whether no project references this SDK, making it safe to remove.
  bool get unused => referenceCount == 0;
}

const _configNames = {'.fvmrc', 'fvm_config.json'};

/// Installed fvm SDKs under [home], each with a count of referencing projects.
///
/// Returns an empty list when fvm is not installed, which is the common case:
/// fvm is a minority tool and must never dominate the output.
///
/// Config discovery always covers the whole of [home], never a narrower scan
/// root. A narrow scan that reported an in-use SDK as unused would delete
/// gigabytes of SDK somebody was using.
List<FvmSdk> fvmSdks({required String home, int maxDepth = 6}) {
  final versionsDir = Directory(p.join(home, 'fvm', 'versions'));
  if (!versionsDir.existsSync()) return const [];

  final installed = versionsDir
      .listSync(followLinks: false)
      .whereType<Directory>()
      .toList();
  if (installed.isEmpty) return const [];

  final configs = _findConfigs(home, maxDepth);
  return installed.map((dir) {
    final version = p.basename(dir.path);
    final count = configs.where((text) => text.contains(version)).length;
    return FvmSdk(version: version, path: dir.path, referenceCount: count);
  }).toList()
    ..sort((a, b) => a.version.compareTo(b.version));
}

List<String> _findConfigs(String home, int maxDepth) {
  final contents = <String>[];
  final normalizedHome = p.normalize(p.absolute(home));
  final rootDepth = p.split(normalizedHome).length;
  final stack = <Directory>[Directory(normalizedHome)];

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
      if (entry is File && _configNames.contains(name)) {
        try {
          contents.add(entry.readAsStringSync());
        } on FileSystemException {
          continue;
        }
      } else if (entry is Directory) {
        // A config inside an SDK checkout describes the SDK, not a user project.
        if (_insideFvmVersions(entry.path, rootDepth)) continue;
        final depth = p.split(p.normalize(entry.path)).length - rootDepth;
        if (depth < maxDepth) stack.add(entry);
      }
    }
  }
  return contents;
}

bool _insideFvmVersions(String dir, int rootDepth) {
  final parts = p.split(dir);
  final relativeParts = parts.skip(rootDepth).toList();
  final index = relativeParts.indexOf('versions');
  return index > 0 && relativeParts[index - 1] == 'fvm';
}
