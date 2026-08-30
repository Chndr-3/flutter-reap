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
/// [onProgress], when given, is called with human-readable status lines as
/// the scan proceeds: once when the walk of [root] starts, and again as each
/// project is found and as each artifact/cache directory is sized. It exists
/// so a slow scan (a large `$root`, or a home-directory scan that must size
/// gigabytes of Xcode DerivedData) is not silent for the whole run — callers
/// that don't care how the work is reported can leave it null.
///
/// `buildPlan` never touches stdout/stderr itself; rendering the callback's
/// messages (or suppressing them, e.g. for `--json`) is the caller's job.
List<Candidate> buildPlan({
  required String root,
  required String home,
  required int minDays,
  required bool includeMachineWide,
  void Function(String message)? onProgress,
}) {
  final candidates = <Candidate>[];

  // Progress messages deliberately report counts, not the paths being sized:
  // buildPlan's caller may render the final listing right next to this
  // stream (e.g. both on stderr in a test harness), and a progress line
  // must never accidentally read like part of that listing.
  onProgress?.call('scanning $root ...');
  final projects = findProjects(root);
  onProgress?.call('scanning $root ... ${projects.length} project'
      '${projects.length == 1 ? '' : 's'} found');

  var sizedCount = 0;
  for (var i = 0; i < projects.length; i++) {
    final project = projects[i];
    onProgress?.call(
      'scanning $root ... ${i + 1}/${projects.length} projects',
    );
    final stale = stalenessOf(project);
    if (stale.ageDays < minDays) continue;

    for (final relative in artifactRelativePaths) {
      final dir = p.joinAll([project, ...p.posix.split(relative)]);
      if (!Directory(dir).existsSync()) continue;
      final bytes = directorySizeBytes(dir);
      sizedCount++;
      onProgress?.call('scanning $root ... ${i + 1}/${projects.length} '
          'projects, $sizedCount dirs sized');
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
    onProgress?.call('sizing machine-wide caches ...');
    // Override the home entries rather than passing the raw environment: a
    // scan rooted at a temp directory must never surface the real machine's
    // caches. This is the narrow-scan bug that bit the bash version.
    for (final cache in sharedCachePaths(
      os: Platform.operatingSystem,
      env: {...Platform.environment, 'HOME': home, 'USERPROFILE': home},
    )) {
      final bytes = directorySizeBytes(cache);
      sizedCount++;
      onProgress?.call('sizing machine-wide caches ... $sizedCount dirs sized');
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
    onProgress?.call('checking fvm SDKs ...');
    for (final sdk in fvmSdks(home: home)) {
      if (!sdk.unused) continue;
      candidates.add(Candidate(
        path: sdk.path,
        bytes: directorySizeBytes(sdk.path),
        kind: CandidateKind.fvmSdk,
        // Include the path, not just the version: this is the one candidate
        // kind whose label used to omit it, and the user is authorizing
        // deletion of 1-3 GB without seeing which directory it is.
        label: 'fvm ${sdk.version} (${sdk.path})',
      ));
    }
  }

  return sortBySize(candidates);
}
