import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'candidate.dart';

/// The version reported by `--version`. Keep in step with `pubspec.yaml`.
const String packageVersion = '0.1.0';

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
  ..addFlag('yes', abbr: 'y', negatable: false, help: 'Delete without review. Requires --days.')
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
