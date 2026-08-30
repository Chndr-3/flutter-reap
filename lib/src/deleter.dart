import 'dart:io';
import 'package:path/path.dart' as p;

import 'candidate.dart';

/// Directory names this tool is ever allowed to remove.
const _deletableNames = {
  'build',
  '.dart_tool',
  'Pods',
  '.gradle',
  'caches',
  'cache',
  'DerivedData',
  'CocoaPods',
};

/// What actually happened during a delete pass.
class DeleteOutcome {
  /// Paths successfully removed.
  final List<String> deleted;

  /// Paths that could not be removed, mapped to the reason.
  final Map<String, String> failed;

  /// Creates an outcome summarizing a completed delete pass.
  const DeleteOutcome({required this.deleted, required this.failed});
}

/// Whether [candidate] is a directory this tool may remove.
///
/// The last path segment must be a known generated name, so a bug in path
/// handling cannot reach `lib/` or `pubspec.yaml`. Additionally, the path must
/// have at least two segments below its root prefix (e.g., `/x/build` is allowed,
/// but `/build` is not). fvm SDK checkouts are the one exception — their directory
/// name is a version number — and they are accepted only when they sit directly
/// inside `fvm/versions`.
bool isDeletable(Candidate candidate) {
  final normalized = p.normalize(p.absolute(candidate.path));
  if (normalized == p.rootPrefix(normalized)) return false;

  final name = p.basename(normalized);
  if (name.isEmpty) return false;

  // Ensure the path has at least two segments below the root prefix.
  final segments = p.split(normalized);
  final segmentsAfterRoot = segments.length - 1; // Discard the root prefix.
  if (segmentsAfterRoot < 2) return false;

  if (candidate.kind == CandidateKind.fvmSdk) {
    final parts = p.split(p.dirname(normalized));
    return parts.length >= 2 &&
        parts.last == 'versions' &&
        parts[parts.length - 2] == 'fvm';
  }
  return _deletableNames.contains(name);
}

/// Delete every candidate that passes [isDeletable].
///
/// A candidate that fails the check is recorded as failed rather than skipped
/// silently, so a mistake is visible instead of invisible. One failure never
/// stops the remaining deletions.
DeleteOutcome deleteCandidates(List<Candidate> candidates) {
  final deleted = <String>[];
  final failed = <String, String>{};

  for (final candidate in candidates) {
    if (!isDeletable(candidate)) {
      failed[candidate.path] = 'refused: not a known generated directory';
      continue;
    }
    final dir = Directory(candidate.path);
    if (!dir.existsSync()) continue;
    try {
      dir.deleteSync(recursive: true);
      deleted.add(candidate.path);
    } on FileSystemException catch (e) {
      failed[candidate.path] = e.osError?.message ?? e.message;
    }
  }
  return DeleteOutcome(deleted: deleted, failed: failed);
}
