import 'dart:io';
import 'package:path/path.dart' as p;

import 'candidate.dart';
import 'dir_size.dart';
import 'fvm_sdks.dart';
import 'project_scanner.dart';
import 'shared_caches.dart';
import 'staleness.dart';

/// [candidates] ordered largest first.
List<Candidate> sortBySize(List<Candidate> candidates) {
  final sorted = [...candidates];
  sorted.sort((a, b) => b.bytes.compareTo(a.bytes));
  return sorted;
}

/// The candidates that will be deleted, given the one-based indexes to keep.
///
/// Pure, so the selection rules can be tested without touching a filesystem.
/// Indexes outside the range of [listed] are ignored rather than treated as an
/// error: an out-of-range number must never silently shift which directory is
/// spared.
List<Candidate> survivors(List<Candidate> listed, Set<int> keepOneBased) {
  final doomed = <Candidate>[];
  for (var i = 0; i < listed.length; i++) {
    if (!keepOneBased.contains(i + 1)) doomed.add(listed[i]);
  }
  return doomed;
}

/// Every deletable directory under [root], largest first.
///
/// Machine-wide caches and fvm SDKs are only included when
/// [includeMachineWide] is true, which the caller sets only when [root] is the
/// user's home directory. Narrowing the scan root must never widen what is at
/// risk.
List<Candidate> buildPlan({
  required String root,
  required String home,
  required int minDays,
  required bool includeMachineWide,
}) {
  final candidates = <Candidate>[];

  for (final project in findProjects(root)) {
    final stale = stalenessOf(project);
    if (stale.ageDays < minDays) continue;

    for (final relative in artifactRelativePaths) {
      final dir = p.joinAll([project, ...p.posix.split(relative)]);
      if (!Directory(dir).existsSync()) continue;
      final bytes = directorySizeBytes(dir);
      if (bytes == 0) continue;
      candidates.add(Candidate(
        path: dir,
        bytes: bytes,
        kind: CandidateKind.projectArtifact,
        label: dir,
        ageDays: stale.ageDays,
        dirty: stale.dirty,
      ));
    }
  }

  if (includeMachineWide) {
    // Override the home entries rather than passing the raw environment: a
    // scan rooted at a temp directory must never surface the real machine's
    // caches. This is the narrow-scan bug that bit the bash version.
    for (final cache in sharedCachePaths(
      os: Platform.operatingSystem,
      env: {...Platform.environment, 'HOME': home, 'USERPROFILE': home},
    )) {
      final bytes = directorySizeBytes(cache);
      if (bytes == 0) continue;
      candidates.add(Candidate(
        path: cache,
        bytes: bytes,
        kind: CandidateKind.sharedCache,
        label: cache,
      ));
    }

    // No size floor here, unlike the loops above: an unused SDK is a candidate
    // by identity, not by leftover size.
    for (final sdk in fvmSdks(home: home)) {
      if (!sdk.unused) continue;
      candidates.add(Candidate(
        path: sdk.path,
        bytes: directorySizeBytes(sdk.path),
        kind: CandidateKind.fvmSdk,
        label: 'fvm ${sdk.version}',
      ));
    }
  }

  return sortBySize(candidates);
}
