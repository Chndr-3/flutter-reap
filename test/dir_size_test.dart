import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:flutter_reap/src/dir_size.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('reap_size_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('sums file sizes recursively', () {
    File(p.join(tmp.path, 'a.bin'))..createSync()..writeAsBytesSync(List.filled(1000, 0));
    Directory(p.join(tmp.path, 'nested')).createSync();
    File(p.join(tmp.path, 'nested', 'b.bin'))..createSync()..writeAsBytesSync(List.filled(500, 0));

    expect(directorySizeBytes(tmp.path), 1500);
  });

  test('returns zero for a directory that does not exist', () {
    expect(directorySizeBytes(p.join(tmp.path, 'nope')), 0);
  });

  test('does not follow symlinks out of the tree', () {
    final outside = Directory.systemTemp.createTempSync('reap_outside_');
    File(p.join(outside.path, 'big.bin'))..createSync()..writeAsBytesSync(List.filled(9999, 0));
    Link(p.join(tmp.path, 'link')).createSync(outside.path);

    expect(directorySizeBytes(tmp.path), 0);
    outside.deleteSync(recursive: true);
  }, skip: Platform.isWindows ? 'symlink creation requires privileges on Windows' : null);
}
