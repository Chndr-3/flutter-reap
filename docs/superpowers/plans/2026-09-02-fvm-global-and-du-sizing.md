# fvm Global SDK Fix and du-Based Sizing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop `flutter_reap` offering to delete the fvm SDK activated by `fvm global`, and make directory sizing use `du` where available.

**Architecture:** `dir_size.dart` splits into two named implementations (`walkSizeBytes`, `duSizeBytes`) plus a thin selector keeping the public name `directorySizeBytes`. `fvm_sdks.dart` gains a symlink read of `~/fvm/default` and an `isGlobalDefault` flag on `FvmSdk` that participates in `unused`. No new dependencies, no signature changes at any call site.

**Tech Stack:** Dart 3.6+, `package:test`, `package:path`, `dart:io` `Process.runSync` and `Link`.

## Global Constraints

- Package is `flutter_reap` at `~/oss/flutter-reap`; work happens on branch `fix/fvm-global-and-du-sizing`.
- Spec of record: `docs/superpowers/specs/2026-09-02-fvm-global-and-du-sizing-design.md`.
- Target release is **0.2.0**. `version:` in `pubspec.yaml` and `packageVersion` in `lib/src/cli.dart` must match exactly.
- No new package dependencies. `dependencies:` stays `args` and `path`.
- Every public declaration needs a doc comment — the package lints for it (`analysis_options.yaml`). Match the existing comment style: say *why*, not *what*.
- `du` is invoked only when `!Platform.isWindows`.
- The public function `directorySizeBytes(String path) -> int` keeps its exact name and signature; `reap_plan.dart` must not change.
- Full suite command: `dart test`. Analyzer: `dart analyze`. Both must be clean before the final commit.
- Sizes reported by the tool become allocated blocks, not apparent bytes. This is intended and user-visible.

---

### Task 1: Extract `walkSizeBytes` with no behaviour change

Pure refactor. `directorySizeBytes` keeps working identically; the walk just gets its own name so a later task can fall back to it. A reviewer should be able to approve this without any opinion about `du`.

**Files:**
- Modify: `lib/src/dir_size.dart` (whole file, currently 38 lines)
- Test: `test/dir_size_test.dart:12-18` (retarget one existing test)

**Interfaces:**
- Consumes: nothing.
- Produces: `int walkSizeBytes(String path)` — apparent-size sum, skips unreadable subdirectories, never follows symlinks. `int directorySizeBytes(String path)` — unchanged public entry point, for now a one-line delegation.

- [ ] **Step 1: Retarget the existing exact-byte test onto `walkSizeBytes`**

In `test/dir_size_test.dart`, change the first test so it names the walk directly. Apparent-size semantics belong to the walk from now on, so this assertion must not sit on the selector.

```dart
  test('walkSizeBytes sums apparent file sizes recursively', () {
    File(p.join(tmp.path, 'a.bin'))..createSync()..writeAsBytesSync(List.filled(1000, 0));
    Directory(p.join(tmp.path, 'nested')).createSync();
    File(p.join(tmp.path, 'nested', 'b.bin'))..createSync()..writeAsBytesSync(List.filled(500, 0));

    expect(walkSizeBytes(tmp.path), 1500);
  });
```

- [ ] **Step 2: Run it to make sure it fails**

```bash
cd ~/oss/flutter-reap && dart test test/dir_size_test.dart -n 'walkSizeBytes sums apparent'
```

Expected: FAIL at compile time — `Error: Undefined name 'walkSizeBytes'` / "Method not found".

- [ ] **Step 3: Rename the implementation and add the delegating selector**

Replace the whole of `lib/src/dir_size.dart` with:

```dart
import 'dart:io';

/// Total apparent size in bytes of every file under [path].
///
/// Walks iteratively rather than with `listSync(recursive: true)` so that a
/// single unreadable subdirectory is skipped instead of ending the walk.
/// Symlinks are never followed, so a link out of the tree cannot inflate the
/// total or cause an infinite loop.
///
/// This sums file lengths, so it reports apparent size rather than the blocks
/// actually allocated on disk. [directorySizeBytes] is what the tool reports;
/// this is its portable fallback.
int walkSizeBytes(String path) {
  final root = Directory(path);
  if (!root.existsSync()) return 0;

  var total = 0;
  final stack = <Directory>[root];

  while (stack.isNotEmpty) {
    final dir = stack.removeLast();
    final List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } on FileSystemException {
      continue; // unreadable directory: skip, never fatal
    }

    for (final entry in entries) {
      if (entry is File) {
        try {
          total += entry.lengthSync();
        } on FileSystemException {
          continue;
        }
      } else if (entry is Directory) {
        stack.add(entry);
      }
    }
  }
  return total;
}

/// Size on disk in bytes of everything under [path], or 0 if it is missing.
int directorySizeBytes(String path) => walkSizeBytes(path);
```

- [ ] **Step 4: Run the full suite**

```bash
cd ~/oss/flutter-reap && dart test && dart analyze
```

Expected: all tests pass, `No issues found!`. Nothing else in the package referenced the old private shape, so `reap_plan.dart` is untouched.

- [ ] **Step 5: Commit**

```bash
cd ~/oss/flutter-reap
git add lib/src/dir_size.dart test/dir_size_test.dart
git commit -m "refactor: name the directory walk walkSizeBytes

Pure rename plus a delegating directorySizeBytes, so a du fast path can
fall back to the walk without the walk being anonymous. No behaviour
change: the exact-byte assertion moves onto walkSizeBytes, where apparent
size semantics now live."
```

---

### Task 2: Add `duSizeBytes` and make it the default path

**Files:**
- Modify: `lib/src/dir_size.dart`
- Test: `test/dir_size_test.dart`
- Test: `test/reap_plan_test.dart:64,148` (two exact-byte assertions that `du`'s block rounding breaks)

**Interfaces:**
- Consumes: `walkSizeBytes(String)` from Task 1.
- Produces: `int? duSizeBytes(String path)` — allocated-block size via `du -sk`, or null when unavailable/unparseable. `int directorySizeBytes(String path, {int? Function(String) du = duSizeBytes})` — the selector; the named parameter exists only to test the fallback and no production caller passes it, so `reap_plan.dart` stays untouched.

- [ ] **Step 1: Write the failing tests**

Append these to `test/dir_size_test.dart`, inside `main()`. Note `_root()`: a container running as root can read a `chmod 000` directory, which would make the partial-permission test assert nothing, so it skips there.

```dart
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
```

Then replace the existing "returns zero for a directory that does not exist" test so it covers the selector's short-circuit explicitly, and delete the old "does not follow symlinks out of the tree" test that asserted `directorySizeBytes(tmp.path) == 0` — the selector no longer returns apparent bytes, and the symlink invariant is now covered for both implementations.

```dart
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
```

Add this helper below `main()`, next to the file's existing top-level code:

```dart
bool _root() => Process.runSync('id', ['-u']).stdout.toString().trim() == '0';
```

- [ ] **Step 2: Run them to make sure they fail**

```bash
cd ~/oss/flutter-reap && dart test test/dir_size_test.dart
```

Expected: FAIL at compile time — `Error: Method not found: 'duSizeBytes'`.

- [ ] **Step 3: Implement `duSizeBytes` and the selector**

In `lib/src/dir_size.dart`, add `duSizeBytes` after `walkSizeBytes` and replace the delegating `directorySizeBytes`:

```dart
/// Allocated size in bytes of everything under [path] according to `du -sk`,
/// or null when `du` cannot answer.
///
/// Returns blocks actually allocated rather than the sum of file lengths, so
/// the figure matches what `df` gives back after a delete and hardlinked
/// content is counted once.
///
/// The exit code is deliberately ignored. `du` on a tree containing one
/// unreadable subdirectory writes the diagnostic to stderr, prints a correct
/// total to stdout, and exits 1; treating that as failure would drop every
/// mixed-permission tree onto the slow walk, which is the exact shape of a
/// real DerivedData directory. Null is returned only when the process cannot
/// run at all or stdout does not begin with a number.
int? duSizeBytes(String path) {
  final ProcessResult result;
  try {
    result = Process.runSync('du', ['-sk', path]);
  } catch (e) {
    return null; // du missing or unspawnable
  }
  final first = (result.stdout as String).trimLeft().split(RegExp(r'\s')).first;
  final kilobytes = int.tryParse(first);
  return kilobytes == null ? null : kilobytes * 1024;
}

/// Size on disk in bytes of everything under [path], or 0 if it is missing.
///
/// Prefers `du`, which is several times faster than walking every file from
/// Dart on the large trees this tool exists for, and falls back to
/// [walkSizeBytes] on Windows or whenever `du` cannot answer. The two disagree
/// slightly — `du` reports allocated blocks, the walk reports apparent size —
/// and `du`'s answer is the one the tool means by "reclaimable".
///
/// [du] is injected only so the fallback branch can be tested: on a machine
/// that has `du`, nothing else ever takes it, which makes it the branch most
/// likely to rot unnoticed. Callers leave it alone.
int directorySizeBytes(
  String path, {
  int? Function(String path) du = duSizeBytes,
}) {
  // Checked before spawning anything: a missing directory is common (most
  // projects have no macos/Pods) and must not cost a process.
  if (!Directory(path).existsSync()) return 0;
  if (Platform.isWindows) return walkSizeBytes(path);
  return du(path) ?? walkSizeBytes(path);
}
```

- [ ] **Step 4: Run the full suite**

```bash
cd ~/oss/flutter-reap && dart test && dart analyze
```

Expected: two failures in `test/reap_plan_test.dart`, then green after the fix below.

`test/reap_plan_test.dart:64` and `test/reap_plan_test.dart:148` both assert
`expect(plan.single.bytes, 2048)` against a fixture holding one 2048-byte file.
Those totals now come from `du`, which rounds to a whole block, so both must
become:

```dart
      expect(plan.single.bytes, greaterThanOrEqualTo(2048));
```

Nothing in `test/cli_run_test.dart` asserts an exact byte total — it checks
ordering and rendering, both of which survive the change — so it needs no edit.
Re-run `dart test && dart analyze` after the two edits and expect all green,
`No issues found!`.

- [ ] **Step 5: Commit**

```bash
cd ~/oss/flutter-reap
git add lib/src/dir_size.dart test/dir_size_test.dart test/reap_plan_test.dart
git commit -m "perf: size directories with du, falling back to the walk

du -sk is several times faster than stat-ing every file from Dart on the
trees this tool exists for, and it reports allocated blocks, so the figure
is the space df gives back and hardlinked content counts once.

The fallback keys on stdout parsing rather than the exit code: du prints a
correct total and exits 1 when any subdirectory is unreadable, and a
DerivedData directory is exactly that shape."
```

---

### Task 3: Never report the `fvm global` SDK as unused

**Files:**
- Modify: `lib/src/fvm_sdks.dart`
- Test: `test/fvm_sdks_test.dart`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `FvmSdk.isGlobalDefault` (`bool`, defaults to `false` in the const constructor). `FvmSdk.unused` becomes `referenceCount == 0 && !isGlobalDefault`. `fvmSdks({required String home, int maxDepth})` keeps its signature.

- [ ] **Step 1: Write the failing tests**

Add to `test/fvm_sdks_test.dart`, inside `main()`, below the existing `projectUsing` helper. Add this helper alongside it first:

```dart
  void globalDefault(String version) {
    Link(p.join(home.path, 'fvm', 'default'))
        .createSync(p.join(home.path, 'fvm', 'versions', version));
  }
```

Then the tests:

```dart
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
```

`test/fvm_sdks_test.dart` already imports `dart:io`, so `Link` and `Platform` are in scope.

- [ ] **Step 2: Run them to make sure they fail**

```bash
cd ~/oss/flutter-reap && dart test test/fvm_sdks_test.dart
```

Expected: FAIL at compile time — `Error: The getter 'isGlobalDefault' isn't defined for the class 'FvmSdk'`.

- [ ] **Step 3: Add the flag and the symlink read**

In `lib/src/fvm_sdks.dart`, extend the class (lines 4-24):

```dart
/// An installed fvm SDK and how many projects reference it.
class FvmSdk {
  /// Version string, which is also the directory name.
  final String version;

  /// Absolute path of the SDK checkout.
  final String path;

  /// Number of project configs naming this version.
  final int referenceCount;

  /// Whether `~/fvm/default` points at this SDK, i.e. `fvm global` selected it.
  final bool isGlobalDefault;

  /// Creates an fvm SDK entry with version, path, and reference count.
  const FvmSdk({
    required this.version,
    required this.path,
    required this.referenceCount,
    this.isGlobalDefault = false,
  });

  /// Whether nothing references this SDK, making it safe to remove.
  ///
  /// The global default counts as a reference even though `fvm global` writes
  /// no project config: it is what a bare `flutter` command resolves through.
  bool get unused => referenceCount == 0 && !isGlobalDefault;
}
```

Add the helper at the bottom of the file, beside `_insideFvmVersions`:

```dart
/// The version `~/fvm/default` points at, or null when there is no global SDK.
///
/// `fvm global <version>` records its choice only as this symlink — no config
/// file is written anywhere — so this read is the only way to learn the global
/// version without the `fvm` executable, which is frequently not on PATH.
/// A missing link, a plain directory of that name, or an unreadable link all
/// yield null, which leaves the SDK to be judged by config references alone.
String? _globalSdkVersion(String home) {
  final link = p.join(home, 'fvm', 'default');
  if (!FileSystemEntity.isLinkSync(link)) return null;
  try {
    return p.basename(Link(link).targetSync());
  } on FileSystemException {
    return null;
  }
}
```

Then wire it into `fvmSdks`. Read the global version immediately after the `installed.isEmpty` guard, before `_findConfigs`:

```dart
  final globalVersion = _globalSdkVersion(home);

  final configs = _findConfigs(home, maxDepth);
```

and set the flag in the `map`:

```dart
  return installed.map((dir) {
    final version = p.basename(dir.path);
    final count = configs.where((text) => _mentions(text, version)).length;
    return FvmSdk(
      version: version,
      path: dir.path,
      referenceCount: count,
      isGlobalDefault: version == globalVersion,
    );
  }).toList()
    ..sort((a, b) => a.version.compareTo(b.version));
```

Reading the global version before the `configs.isEmpty` early return is deliberate but not load-bearing for safety: that guard already returns an empty list, which reports nothing and so spares every SDK. It sits there so `isGlobalDefault` stays correct if that guard is ever relaxed.

- [ ] **Step 4: Run the full suite**

```bash
cd ~/oss/flutter-reap && dart test && dart analyze
```

Expected: all tests pass, `No issues found!`. The existing `configs.isEmpty` test still expects `isEmpty`, which is unchanged.

- [ ] **Step 5: Commit**

```bash
cd ~/oss/flutter-reap
git add lib/src/fvm_sdks.dart test/fvm_sdks_test.dart
git commit -m "fix: never offer the fvm global SDK for deletion

fvm global records its choice only as the ~/fvm/default symlink and writes
no project config, so counting config mentions reported that SDK as
unreferenced and offered to delete the one a bare flutter command resolves
through — one to three gigabytes, in use.

Reads the symlink and spares its target via a separate isGlobalDefault
flag, so the reason an SDK was spared stays visible rather than hiding in
an inflated reference count."
```

---

### Task 4: Release 0.2.0 — version, changelog, README

**Files:**
- Modify: `pubspec.yaml:3`
- Modify: `lib/src/cli.dart:13`
- Modify: `CHANGELOG.md` (prepend a section above `## 0.1.1`)
- Modify: `README.md`
- Test: `test/cli_test.dart`

**Interfaces:**
- Consumes: the behaviour from Tasks 2 and 3.
- Produces: nothing other code reads.

- [ ] **Step 1: Write the failing test that pins version drift**

`packageVersion` currently carries a "keep in step with pubspec.yaml" comment, and a comment cannot keep anything in step. Add to `test/cli_test.dart`, inside `main()`:

```dart
  test('packageVersion matches the version in pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final declared = RegExp(r'^version:\s*(\S+)', multiLine: true)
        .firstMatch(pubspec)
        ?.group(1);

    expect(declared, isNotNull, reason: 'pubspec.yaml has no version: line');
    expect(packageVersion, declared);
  });
```

`test/cli_test.dart` imports `package:flutter_reap/src/cli.dart` already; add `import 'dart:io';` at the top if it is not there.

- [ ] **Step 2: Run it to confirm it passes at 0.1.1, then fails after the bump**

```bash
cd ~/oss/flutter-reap && dart test test/cli_test.dart -n 'packageVersion matches'
```

Expected: PASS — both are `0.1.1` today. This test guards the *next* step; bump only `pubspec.yaml` and re-run to see it FAIL with `Expected: '0.2.0' Actual: '0.1.1'`, which proves it is wired to something real.

- [ ] **Step 3: Bump both versions**

`pubspec.yaml` line 3:

```yaml
version: 0.2.0
```

`lib/src/cli.dart` line 13:

```dart
const String packageVersion = '0.2.0';
```

- [ ] **Step 4: Run the suite**

```bash
cd ~/oss/flutter-reap && dart test && dart analyze
```

Expected: all tests pass including `packageVersion matches the version in pubspec.yaml`, `No issues found!`.

- [ ] **Step 5: Prepend the changelog section**

Insert above the existing `## 0.1.1` heading in `CHANGELOG.md`:

```markdown
## 0.2.0

- Fixed: an SDK selected with `fvm global` is no longer offered for deletion.
  fvm records that choice only as the `~/fvm/default` symlink and writes no
  project config, so the previous reference count read it as unused — and
  offered to delete the SDK a bare `flutter` command resolves through.
- Faster: directory sizing now shells out to `du` where it is available,
  falling back to the previous Dart walk on Windows and whenever `du` cannot
  answer. A home-directory scan spends most of its time sizing Xcode
  DerivedData, and that is the part this speeds up.
- Changed: reported sizes are now disk usage — the blocks actually allocated —
  rather than the sum of file lengths. Figures shift slightly upward for trees
  of many small files, hardlinked content counts once, and the number now
  matches what `df` gives back after a delete.
```

- [ ] **Step 6: Document both in the README**

In the section describing the listing (just after the columns paragraph added on `main`), add:

```markdown
Sizes are disk usage — the blocks actually allocated — so they match what `df`
gives back after a delete, and content that is hardlinked in several places is
counted once.
```

In the paragraph describing fvm SDK handling, add:

```markdown
The SDK selected with `fvm global` is never offered for deletion, even though
`fvm global` writes no project config naming it.
```

- [ ] **Step 7: Run everything one last time**

```bash
cd ~/oss/flutter-reap && dart test && dart analyze && dart pub publish --dry-run
```

Expected: tests pass, `No issues found!`, and the dry run reports the package as `flutter_reap 0.2.0` with no errors. Warnings about an uncommitted working tree are fine at this point.

- [ ] **Step 8: Commit**

```bash
cd ~/oss/flutter-reap
git add pubspec.yaml lib/src/cli.dart CHANGELOG.md README.md test/cli_test.dart
git commit -m "chore: release 0.2.0

Bumps both version declarations and adds the test that keeps them in step,
since the comment asking a human to do it demonstrably cannot.

Documents the size-semantics change: the listing now reports allocated
blocks, which is a user-visible shift in the numbers and belongs in the
changelog rather than in a diff nobody reads."
```

---

## Verification

After all four tasks:

```bash
cd ~/oss/flutter-reap
dart test                                   # whole suite green
dart analyze                                # No issues found!
dart run bin/flutter_reap.dart ~ --json | head -40
```

The `--json` run against the real home directory is the end-to-end check worth doing by hand. `~/fvm/versions` holds `3.38.3` and `3.44.6`, and `~/fvm/default` points at `3.38.3`, so no candidate with `"kind": "fvmSdk"` may name `3.38.3`. Compare the run's wall-clock against the same command on `main` to see the `du` effect.

## Out of scope

Not to be added while implementing, per the spec: the `findProjects` depth-6
versus fvm-config depth-10 mismatch, human-readable size units in the listing,
parallelising the scan with isolates, JSON-parsing the fvm configs, and
tightening `isDeletable` from a basename allowlist to full-path matching.
