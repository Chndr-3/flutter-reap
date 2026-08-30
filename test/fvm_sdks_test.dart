import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:flutter_reap/src/fvm_sdks.dart';

void main() {
  late Directory home;

  setUp(() => home = Directory.systemTemp.createTempSync('reap_fvm_'));
  tearDown(() => home.deleteSync(recursive: true));

  void installSdk(String version) {
    Directory(p.join(home.path, 'fvm', 'versions', version)).createSync(recursive: true);
  }

  void projectUsing(String name, String version) {
    final dir = Directory(p.join(home.path, name))..createSync(recursive: true);
    File(p.join(dir.path, '.fvmrc')).writeAsStringSync('{"flutter": "$version"}');
  }

  test('returns nothing when fvm is not installed', () {
    expect(fvmSdks(home: home.path), isEmpty);
  });

  test('marks an SDK no project references as unused', () {
    installSdk('3.38.3');
    expect(fvmSdks(home: home.path).single.unused, isTrue);
  });

  test('marks a referenced SDK as used and counts projects', () {
    installSdk('3.38.3');
    projectUsing('app_one', '3.38.3');
    projectUsing('app_two', '3.38.3');

    final sdk = fvmSdks(home: home.path).single;
    expect(sdk.unused, isFalse);
    expect(sdk.referenceCount, 2);
  });

  test('reads the legacy fvm_config.json as well as .fvmrc', () {
    installSdk('3.44.6');
    final dir = Directory(p.join(home.path, 'legacy', '.fvm'))..createSync(recursive: true);
    File(p.join(dir.path, 'fvm_config.json')).writeAsStringSync('{"flutterSdkVersion": "3.44.6"}');

    expect(fvmSdks(home: home.path).single.unused, isFalse);
  });

  test('does not count a config living inside the SDK checkout itself', () {
    installSdk('3.38.3');
    File(p.join(home.path, 'fvm', 'versions', '3.38.3', '.fvmrc'))
        .writeAsStringSync('{"flutter": "3.38.3"}');

    expect(fvmSdks(home: home.path).single.unused, isTrue);
  });

  test('regression: SDK referenced by config is not marked unused when home is set normally', () {
    installSdk('3.38.3');
    projectUsing('app', '3.38.3');

    final sdk = fvmSdks(home: home.path).single;
    expect(sdk.unused, isFalse);
    expect(sdk.referenceCount, 1);
  });

  test('root-relative check: config inside SDK checkout does not count as reference', () {
    installSdk('3.38.3');
    // This SDK has a config inside itself
    File(p.join(home.path, 'fvm', 'versions', '3.38.3', '.fvmrc'))
        .writeAsStringSync('{"flutter": "3.38.3"}');
    // But no external project references it

    final sdk = fvmSdks(home: home.path).single;
    expect(sdk.unused, isTrue);
  });
}
