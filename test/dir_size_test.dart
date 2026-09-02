import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:flutter_reap/src/dir_size.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('reap_size_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('walkSizeBytes sums apparent file sizes recursively', () {
    File(p.join(tmp.path, 'a.bin'))..createSync()..writeAsBytesSync(List.filled(1000, 0));
    Directory(p.join(tmp.path, 'nested')).createSync();
    File(p.join(tmp.path, 'nested', 'b.bin'))..createSync()..writeAsBytesSync(List.filled(500, 0));

    expect(walkSizeBytes(tmp.path), 1500);
  });

  test('duSizeBytes reports allocated blocks, at least the apparent size', () {
    File(p.join(tmp.path, 'a.bin'))..createSync()..writeAsBytesSync(List.filled(1000, 0));
    Directory(p.join(tmp.path, 'nested')).createSync();
    File(p.join(tmp.path, 'nested', 'b.bin'))..createSync()..writeAsBytesSync(List.filled(500, 0));

    final blocks = duSizeBytes(tmp.path);
    // Blocks round up from the 1500 apparent bytes and are a whole number of
    // kilobytes, but the exact figure is filesystem-dependent (APFS, ext4,
    // block size), so the assertion pins the relationship, not the number.
    expect(blocks, isNotNull);
    expect(blocks!, greaterThanOrEqualTo(walkSizeBytes(tmp.path)));
    expect(blocks % 1024, 0);
  }, skip: Platform.isWindows ? 'du is not available on Windows' : null);

  test('duSizeBytes does not follow symlinks out of the tree', () {
    final outside = Directory.systemTemp.createTempSync('reap_outside_du_');
    File(p.join(outside.path, 'big.bin'))..createSync()..writeAsBytesSync(List.filled(999999, 0));
    Link(p.join(tmp.path, 'link')).createSync(outside.path);

    // The 999999-byte file behind the link must not be counted. An empty tree
    // plus a link is well under one megabyte of blocks.
    expect(duSizeBytes(tmp.path)!, lessThan(1024 * 1024));
    outside.deleteSync(recursive: true);
  }, skip: Platform.isWindows ? 'du is not available on Windows' : null);

  test('duSizeBytes still returns a total when one subdirectory is unreadable', () {
    Directory(p.join(tmp.path, 'good')).createSync();
    File(p.join(tmp.path, 'good', 'f.bin'))..createSync()..writeAsBytesSync(List.filled(1000, 0));
    final bad = Directory(p.join(tmp.path, 'bad'))..createSync();
    File(p.join(bad.path, 'f.bin'))..createSync()..writeAsBytesSync(List.filled(1000, 0));
    Process.runSync('chmod', ['000', bad.path]);

    // du writes "Permission denied" to stderr, prints a correct total to
    // stdout, and exits 1. Keying the fallback on the exit code would drop
    // every mixed-permission tree onto the slow walk, which is exactly the
    // shape of a real DerivedData directory.
    final blocks = duSizeBytes(tmp.path);
    Process.runSync('chmod', ['755', bad.path]);

    expect(blocks, isNotNull);
    expect(blocks!, greaterThan(0));
  }, skip: Platform.isWindows
      ? 'du is not available on Windows'
      : (_root() ? 'root can read a chmod 000 directory' : null));

  test('duSizeBytes returns null for a path du cannot stat', () {
    expect(duSizeBytes(p.join(tmp.path, 'nope')), isNull);
  }, skip: Platform.isWindows ? 'du is not available on Windows' : null);

  test('directorySizeBytes agrees with duSizeBytes off Windows', () {
    File(p.join(tmp.path, 'a.bin'))..createSync()..writeAsBytesSync(List.filled(1000, 0));

    expect(directorySizeBytes(tmp.path), duSizeBytes(tmp.path));
  }, skip: Platform.isWindows ? 'du is not available on Windows' : null);

  test('directorySizeBytes falls back to the walk when du cannot answer', () {
    File(p.join(tmp.path, 'a.bin'))..createSync()..writeAsBytesSync(List.filled(1000, 0));

    // The one branch no machine with du ever exercises, and therefore the one
    // most likely to be broken: a stubbed du that answers null must produce
    // the walk's apparent-size figure, not a crash or a zero.
    expect(directorySizeBytes(tmp.path, du: (_) => null), 1000);
  });

  test('directorySizeBytes returns zero for a directory that does not exist', () {
    expect(directorySizeBytes(p.join(tmp.path, 'nope')), 0);
  });

  test('walkSizeBytes does not follow symlinks out of the tree', () {
    final outside = Directory.systemTemp.createTempSync('reap_outside_');
    File(p.join(outside.path, 'big.bin'))..createSync()..writeAsBytesSync(List.filled(9999, 0));
    Link(p.join(tmp.path, 'link')).createSync(outside.path);

    expect(walkSizeBytes(tmp.path), 0);
    outside.deleteSync(recursive: true);
  }, skip: Platform.isWindows ? 'symlink creation requires privileges on Windows' : null);
}

bool _root() => Process.runSync('id', ['-u']).stdout.toString().trim() == '0';
