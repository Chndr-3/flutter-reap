import 'dart:convert';
import 'dart:io' show Directory, Platform;

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'candidate.dart';
import 'deleter.dart';
import 'reap_plan.dart';
import 'selection.dart';

/// The version reported by `--version`. Keep in step with `pubspec.yaml`.
const String packageVersion = '0.1.1';

/// Parsed command line options.
class CliOptions {
  /// Directory to scan.
  final String root;

  /// Only report projects idle at least this many days.
  final int minDays;

  /// Whether to enter the delete flow.
  final bool delete;

  /// Whether to skip the keep/delete prompt.
  final bool assumeYes;

  /// Whether to emit machine-readable output.
  final bool json;

  /// Whether to skip machine-wide caches.
  final bool noCaches;

  /// Whether `--help` was requested.
  final bool help;

  /// Whether `--version` was requested.
  final bool version;

  /// Creates a fully-specified set of parsed command line options.
  const CliOptions({
    required this.root,
    required this.minDays,
    required this.delete,
    required this.assumeYes,
    required this.json,
    required this.noCaches,
    required this.help,
    required this.version,
  });
}

/// The command line grammar.
ArgParser buildParser() => ArgParser()
  ..addOption('days', abbr: 'd', help: 'Only projects idle n+ days.', valueHelp: 'n')
  ..addFlag('delete', negatable: false, help: 'Enter the delete flow (default is a dry run).')
  ..addFlag('no-caches', negatable: false, help: 'Skip machine-wide caches.')
  ..addFlag('json', negatable: false, help: 'Machine-readable output. Implies a dry run.')
  ..addFlag('yes',
      abbr: 'y',
      negatable: false,
      help: 'Delete without review. Requires --days. Project artifacts only; '
          'machine-wide caches are never deleted unattended.')
  ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.')
  ..addFlag('version', abbr: 'v', negatable: false, help: 'Show the version.');

/// Parse [args], rejecting combinations that would be dangerous or meaningless.
///
/// Throws [FormatException] with a message suitable for printing.
CliOptions parseArgs(List<String> args) {
  final ArgResults results;
  try {
    results = buildParser().parse(args);
  } on FormatException catch (e) {
    throw FormatException(e.message);
  }

  if (results.rest.length > 1) {
    throw const FormatException('Provide at most one path to scan.');
  }
  final root = results.rest.isEmpty ? Directory.current.path : results.rest.first;
  final normalized = p.normalize(p.absolute(root));
  if (normalized == p.rootPrefix(normalized)) {
    throw const FormatException('Refusing to scan a filesystem root.');
  }

  var minDays = 0;
  final daysValue = results.option('days');
  if (daysValue != null) {
    final parsed = int.tryParse(daysValue);
    if (parsed == null) throw FormatException('--days expects a number, got "$daysValue".');
    if (parsed < 0) throw const FormatException('--days cannot be negative.');
    minDays = parsed;
  }

  final json = results.flag('json');
  final assumeYes = results.flag('yes');
  if (assumeYes && daysValue == null) {
    throw const FormatException(
      '--yes must be combined with --days, so an unfiltered delete is never one keystroke away.',
    );
  }

  return CliOptions(
    root: root,
    minDays: minDays,
    // --json is for reporting; it must never delete.
    delete: json ? false : results.flag('delete'),
    assumeYes: assumeYes,
    json: json,
    noCaches: results.flag('no-caches'),
    help: results.flag('help'),
    version: results.flag('version'),
  );
}

/// Resolve the home directory from [environment] using the same
/// OS-dependent precedence `shared_caches.dart` uses: on Windows,
/// `USERPROFILE` wins over `HOME`; everywhere else, `HOME` wins over
/// `USERPROFILE`. On Git Bash / MSYS on Windows, `HOME` (e.g. `/home/bob`)
/// and `USERPROFILE` (e.g. `C:\Users\bob`) can both be set and disagree, and
/// a HOME-first resolution silently omits every machine-wide cache because
/// `rootIsHome` then fails to match the real home directory.
String resolveHome(Map<String, String> environment, String os) {
  return os == 'windows'
      ? environment['USERPROFILE'] ?? environment['HOME'] ?? ''
      : environment['HOME'] ?? environment['USERPROFILE'] ?? '';
}

/// Render [candidates] as a numbered listing.
String renderListing(List<Candidate> candidates) {
  final buffer = StringBuffer();
  for (var i = 0; i < candidates.length; i++) {
    final c = candidates[i];
    final age = c.ageDays == null ? '' : '${c.ageDays}d';
    final flag = c.dirty ? ' !' : '';
    buffer.writeln(
      '${(i + 1).toString().padLeft(3)}. '
      '${c.megabytes.toString().padLeft(6)}M '
      '${age.padLeft(6)}$flag  ${c.label}',
    );
  }
  return buffer.toString();
}

/// Render [candidates] as JSON, without a JSON encoder dependency beyond dart:convert.
String renderJson(List<Candidate> candidates) {
  final entries = candidates.map((c) => {
        'path': c.path,
        'bytes': c.bytes,
        'kind': c.kind.name,
        'ageDays': c.ageDays,
        'dirty': c.dirty,
      });
  return const JsonEncoder.withIndent('  ').convert({
    'totalBytes': candidates.fold<int>(0, (sum, c) => sum + c.bytes),
    'candidates': entries.toList(),
  });
}

/// Runs the CLI end to end and returns the process exit code.
///
/// This is the whole of `main()`'s decision logic, pulled out so it can be
/// exercised without a real process: [readLine] stands in for reading the
/// keep/delete prompt (a caller simulating EOF should return the same
/// sentinel `stdin.readLineSync() ?? 'k'` produces, which already cancels
/// rather than deleting), [out]/[err] stand in for stdout/stderr, and
/// [environment] stands in for `Platform.environment` so a test can point
/// HOME at a temp directory instead of the real machine.
/// [showProgress] decides whether scan progress is written to [err] at all.
///
/// Real usage (`bin/flutter_reap.dart`) passes `stderr.hasTerminal` here
/// rather than `run` reading it directly, so a piped or CI stderr never
/// fills with carriage-returned status lines, and so tests — which never run
/// attached to a terminal — can still exercise the progress path by passing
/// `true` explicitly. `--json` always suppresses progress regardless of this
/// flag, since machine-readable mode must be silent apart from the JSON.
int run(
  List<String> args, {
  required String Function() readLine,
  required StringSink out,
  required StringSink err,
  required Map<String, String> environment,
  bool showProgress = true,
}) {
  final CliOptions options;
  try {
    options = parseArgs(args);
  } on FormatException catch (e) {
    err.writeln(e.message);
    err.writeln('');
    err.writeln(buildParser().usage);
    return 64; // EX_USAGE
  }

  if (options.help) {
    out.writeln('flutter_reap [path] [options]\n');
    out.writeln(buildParser().usage);
    return 0;
  }
  if (options.version) {
    out.writeln(packageVersion);
    return 0;
  }

  final home = resolveHome(environment, Platform.operatingSystem);
  final rootIsHome = home.isNotEmpty &&
      p.equals(p.normalize(p.absolute(options.root)), p.normalize(home));

  // Machine-readable mode must stay silent apart from the JSON, so progress
  // is suppressed there even when showProgress is true.
  final reportProgress = showProgress && !options.json;
  var lastProgressLength = 0;
  void onProgress(String message) {
    // \r plus overwriting with spaces erases the previous line rather than
    // leaving stray trailing characters when a later message is shorter.
    err.write('\r${' ' * lastProgressLength}\r$message');
    lastProgressLength = message.length;
  }

  final candidates = buildPlan(
    root: options.root,
    home: home,
    minDays: options.minDays,
    // Unattended deletes (--yes) cover project artifacts only: machine-wide
    // caches and fvm SDKs are multi-gigabyte, slow to rebuild, and must never
    // be removed without a human looking at the listing first.
    includeMachineWide: !options.assumeYes && rootIsHome && !options.noCaches,
    onProgress: reportProgress ? onProgress : null,
  );

  // Clear any in-progress status line before the real output, so the final
  // listing (or JSON) never has a half-written progress line above it.
  if (reportProgress && lastProgressLength > 0) {
    err.write('\r${' ' * lastProgressLength}\r');
  }

  if (options.json) {
    out.writeln(renderJson(candidates));
    return 0;
  }

  if (candidates.isEmpty) {
    out.writeln('Nothing to reclaim.');
    return 0;
  }

  out.write(renderListing(candidates));
  final totalMb = candidates.fold<int>(0, (sum, c) => sum + c.bytes) ~/ (1024 * 1024);
  out.writeln('--- ${candidates.length} dirs, ${totalMb}M reclaimable');

  if (!options.delete) {
    out.writeln('(dry run - pass --delete to remove)');
    return 0;
  }

  final Selection selection;
  if (options.assumeYes) {
    selection = const KeepIndexes({});
  } else {
    out.write(
      'keep which? (e.g. 1,3-5)  [enter = keep nothing, delete all]  [k = keep everything, cancel] ',
    );
    selection = parseSelection(readLine(), candidates.length);
  }

  if (selection is CancelSelection) {
    out.writeln('cancelled - nothing deleted');
    return 0;
  }

  final doomed = survivors(candidates, (selection as KeepIndexes).indexes);
  if (doomed.isEmpty) {
    out.writeln('nothing selected');
    return 0;
  }

  final outcome = deleteCandidates(doomed);
  for (final path in outcome.deleted) {
    out.writeln('rm $path');
  }
  outcome.failed.forEach((path, reason) {
    err.writeln('skipped $path: $reason');
  });
  out.writeln('deleted ${outcome.deleted.length} of ${doomed.length}');
  // A pass where every removal was refused must not look identical to
  // success, e.g. in CI.
  return outcome.failed.isEmpty ? 0 : 1;
}
