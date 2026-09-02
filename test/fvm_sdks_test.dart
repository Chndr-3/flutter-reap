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

  void globalDefault(String version) {
    Link(p.join(home.path, 'fvm', 'default'))
        .createSync(p.join(home.path, 'fvm', 'versions', version));
  }

  test('returns nothing when fvm is not installed', () {
    expect(fvmSdks(home: home.path), isEmpty);
  });

  test('an installed SDK with zero config files anywhere under home is not '
      'reported as unused', () {
    installSdk('3.38.3');
    // No .fvmrc / fvm_config.json anywhere: the scan has found no evidence at
    // all, so it must not conclude every SDK is unused.
    expect(fvmSdks(home: home.path), isEmpty);
  });

  test('a config at depth 8 under home is found', () {
    installSdk('3.38.3');
    final deep = Directory(p.joinAll([
      home.path,
      'a', 'b', 'c', 'd', 'e', 'f', 'g',
    ]))..createSync(recursive: true);
    File(p.join(deep.path, '.fvmrc')).writeAsStringSync('{"flutter": "3.38.3"}');

    final sdk = fvmSdks(home: home.path).single;
    expect(sdk.unused, isFalse);
    expect(sdk.referenceCount, 1);
  });

  test('marks an SDK no project references as unused', () {
    installSdk('3.38.3');
    // At least one config must exist somewhere under home, so the scan has
    // evidence and can conclude "unused" rather than "nothing found".
    projectUsing('unrelated_app', '9.9.9');
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
    // Unrelated config elsewhere, so the scan has evidence beyond the
    // in-checkout config that gets excluded.
    projectUsing('unrelated_app', '9.9.9');

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
    // But no external project references it, aside from an unrelated config
    // that gives the scan evidence to work from.
    projectUsing('unrelated_app', '9.9.9');

    final sdk = fvmSdks(home: home.path).single;
    expect(sdk.unused, isTrue);
  });

  test('substring matching bug: 3.4 should not match 3.4.6', () {
    installSdk('3.4');
    installSdk('3.4.6');
    projectUsing('app', '3.4.6');

    final sdks = fvmSdks(home: home.path);
    final sdk34 = sdks.firstWhere((s) => s.version == '3.4');
    final sdk346 = sdks.firstWhere((s) => s.version == '3.4.6');

    expect(sdk346.unused, isFalse);
    expect(sdk346.referenceCount, 1);
    expect(sdk34.unused, isTrue);
    expect(sdk34.referenceCount, 0);
  });

  test('substring matching bug: 3.38.3 should not match 3.38.30', () {
    installSdk('3.38.3');
    projectUsing('app', '3.38.30');

    final sdk = fvmSdks(home: home.path).single;
    expect(sdk.unused, isTrue);
  });

  test('substring matching bug: 3.4 should not match unrelated 13.4.6', () {
    installSdk('3.4');
    projectUsing('app', '13.4.6');

    final sdk = fvmSdks(home: home.path).single;
    expect(sdk.unused, isTrue);
  });

  test('exact match still works: 3.38.3 matches exactly 3.38.3', () {
    installSdk('3.38.3');
    projectUsing('app', '3.38.3');

    final sdk = fvmSdks(home: home.path).single;
    expect(sdk.unused, isFalse);
    expect(sdk.referenceCount, 1);
  });

  test('an SDK that is only the global default is not reported as unused', () {
    installSdk('3.38.3');
    globalDefault('3.38.3');
    // `fvm global` writes no project config at all, so without the symlink
    // read this SDK looks unreferenced and gets offered for deletion — an
    // SDK the user's default `flutter` command resolves through.
    projectUsing('unrelated_app', '9.9.9');

    final sdk = fvmSdks(home: home.path).single;
    expect(sdk.unused, isFalse);
    expect(sdk.isGlobalDefault, isTrue);
    expect(sdk.referenceCount, 0);
  }, skip: Platform.isWindows ? 'symlink creation requires privileges on Windows' : null);

  test('the global default does not spare a different SDK', () {
    installSdk('3.38.3');
    installSdk('3.44.6');
    globalDefault('3.38.3');
    projectUsing('unrelated_app', '9.9.9');

    final sdks = fvmSdks(home: home.path);
    expect(sdks.firstWhere((s) => s.version == '3.38.3').unused, isFalse);
    expect(sdks.firstWhere((s) => s.version == '3.44.6').unused, isTrue);
  }, skip: Platform.isWindows ? 'symlink creation requires privileges on Windows' : null);

  test('a dangling global default link does not throw', () {
    installSdk('3.38.3');
    Link(p.join(home.path, 'fvm', 'default'))
        .createSync(p.join(home.path, 'fvm', 'versions', 'never-installed'));
    projectUsing('unrelated_app', '9.9.9');

    // The link still resolves to a version name, so nothing throws; the SDK
    // it names is simply not installed and the real one stays unused.
    final sdk = fvmSdks(home: home.path).single;
    expect(sdk.unused, isTrue);
  }, skip: Platform.isWindows ? 'symlink creation requires privileges on Windows' : null);

  test('a plain directory named default is not read as a global version', () {
    installSdk('3.38.3');
    Directory(p.join(home.path, 'fvm', 'default')).createSync();
    projectUsing('unrelated_app', '9.9.9');

    final sdk = fvmSdks(home: home.path).single;
    expect(sdk.isGlobalDefault, isFalse);
    expect(sdk.unused, isTrue);
  });
}
