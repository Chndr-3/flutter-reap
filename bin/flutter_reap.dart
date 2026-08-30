import 'dart:io';

import 'package:flutter_reap/src/cli.dart';
import 'package:flutter_reap/src/deleter.dart';
import 'package:flutter_reap/src/reap_plan.dart';
import 'package:flutter_reap/src/selection.dart';
import 'package:path/path.dart' as p;

void main(List<String> args) {
  final CliOptions options;
  try {
    options = parseArgs(args);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln('');
    stderr.writeln(buildParser().usage);
    exit(64); // EX_USAGE
  }

  if (options.help) {
    stdout.writeln('flutter_reap [path] [options]\n');
    stdout.writeln(buildParser().usage);
    return;
  }
  if (options.version) {
    stdout.writeln(packageVersion);
    return;
  }

  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  final rootIsHome = home.isNotEmpty &&
      p.equals(p.normalize(p.absolute(options.root)), p.normalize(home));

  final candidates = buildPlan(
    root: options.root,
    home: home,
    minDays: options.minDays,
    includeMachineWide: rootIsHome && !options.noCaches,
  );

  if (options.json) {
    stdout.writeln(renderJson(candidates));
    return;
  }

  if (candidates.isEmpty) {
    stdout.writeln('Nothing to reclaim.');
    return;
  }

  stdout.write(renderListing(candidates));
  final totalMb = candidates.fold<int>(0, (sum, c) => sum + c.bytes) ~/ (1024 * 1024);
  stdout.writeln('--- ${candidates.length} dirs, ${totalMb}M reclaimable');

  if (!options.delete) {
    stdout.writeln('(dry run - pass --delete to remove)');
    return;
  }

  final Selection selection;
  if (options.assumeYes) {
    selection = const KeepIndexes({});
  } else {
    stdout.write(
      'keep which? (e.g. 1,3-5)  [enter = keep nothing, delete all]  [k = keep everything, cancel] ',
    );
    selection = parseSelection(stdin.readLineSync() ?? 'k', candidates.length);
  }

  if (selection is CancelSelection) {
    stdout.writeln('cancelled - nothing deleted');
    return;
  }

  final doomed = survivors(candidates, (selection as KeepIndexes).indexes);
  if (doomed.isEmpty) {
    stdout.writeln('nothing selected');
    return;
  }

  final outcome = deleteCandidates(doomed);
  for (final path in outcome.deleted) {
    stdout.writeln('rm $path');
  }
  outcome.failed.forEach((path, reason) {
    stderr.writeln('skipped $path: $reason');
  });
  stdout.writeln('deleted ${outcome.deleted.length} of ${doomed.length}');
}
