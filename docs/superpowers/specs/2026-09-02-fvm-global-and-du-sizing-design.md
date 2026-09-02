# fvm global SDKs and du-based sizing

- Date: 2026-09-02
- Status: approved, not yet implemented
- Target release: 0.2.0

## Problem

Two defects, one correctness and one performance.

**A global fvm SDK is reported as unused.** `fvmSdks` decides whether an
installed SDK is in use by counting `.fvmrc` / `fvm_config.json` files under
`$HOME` that mention its version. An SDK activated with `fvm global 3.38.3` is
recorded only as the symlink `~/fvm/default -> ~/fvm/versions/3.38.3`; fvm
writes no project config for it. Such an SDK therefore has `referenceCount == 0`,
reads as `unused`, and is offered for deletion. That is one to three gigabytes
of SDK that the user's default `flutter` command resolves through, and it is
exactly the class of mistake the module's existing `configs.isEmpty` guard was
written to prevent, arriving through a door that guard does not watch.

Verified on the author's machine: `~/fvm/default` is a symlink into
`~/fvm/versions/3.38.3`, and the `fvm` executable is not on `PATH`, so reading
the symlink is the only way to learn the global version.

**Sizing is slow.** `directorySizeBytes` walks every entry and calls
`lengthSync()` on every file, synchronously, on the main isolate. The dominant
cost in a home-directory scan is `~/Library/Developer/Xcode/DerivedData`, which
is routinely hundreds of thousands of files. The progress line added in 0.1.1
exists because of this cost.

## Decisions

Settled during brainstorming, recorded here so implementation does not
relitigate them:

1. **Reported sizes become allocated blocks, not apparent size.** `du -sk` is
   the fast path, and its numbers are disk usage. This is a deliberate change
   in what the tool reports: it now states the space `df` will give back, and
   de-dupes hardlinks. macOS ships BSD `du`, which has no `--apparent-size`, so
   keeping both semantics is not available.
2. **`du` integration is two named functions plus a selector**, not an internal
   fast path and not an injected `Sizer` interface. Both implementations stay
   directly testable on any platform without threading a parameter through
   `buildPlan`.
3. **"In use" for fvm means the `~/fvm/default` symlink target only.** Not the
   global config file under `~/Library/Application Support/fvm`, and not a
   rewrite of the config text-matching into JSON parsing. The symlink is fvm's
   own source of truth for the global SDK and needs no parsing.
4. **The spared reason stays visible**: a new `isGlobalDefault` flag, rather
   than incrementing `referenceCount` to fake a project reference.

## Design

### `lib/src/dir_size.dart`

Three functions replace the current one.

`walkSizeBytes(String path) -> int` is today's body, unchanged. It remains the
Windows path and the fallback path, and keeps its existing invariants: an
unreadable subdirectory is skipped rather than fatal, and symlinks are never
followed.

`duSizeBytes(String path) -> int?` runs `du -sk <path>`, takes the first
whitespace-delimited token of stdout, and returns `kilobytes * 1024`. It
returns `null` when the process cannot be spawned or when that token does not
parse as an integer.

**The exit code is deliberately ignored.** `du` on a tree containing a single
unreadable subdirectory writes the diagnostic to stderr, prints a correct total
to stdout, and exits 1. Keying the fallback on `exitCode == 0` would drop every
such tree onto the slow walk — precisely the large, mixed-permission trees the
fast path exists for. Measured on macOS:

```
$ du -sk partial
du: partial/bad: Permission denied
4	partial
exit=1
```

`directorySizeBytes(String path) -> int` is the selector:

- returns `0` when the directory does not exist, before spawning anything;
- on Windows, returns `walkSizeBytes(path)`;
- otherwise returns `duSizeBytes(path) ?? walkSizeBytes(path)`.

Candidate paths are always absolute, so no path passed to `du` can begin with
`-` and be read as a flag.

### `lib/src/fvm_sdks.dart`

A private `_globalSdkVersion(String home) -> String?` reads
`p.join(home, 'fvm', 'default')`. When that path is a symlink, it returns the
basename of `Link(...).targetSync()`. It returns `null` when the path is
absent, is not a link, or when `targetSync()` throws — a dangling link included.

`FvmSdk` gains `final bool isGlobalDefault`, defaulting to `false` in the
const constructor so existing construction sites and tests keep compiling, and:

```dart
bool get unused => referenceCount == 0 && !isGlobalDefault;
```

The global lookup happens **before** the existing `configs.isEmpty` early
return, so a machine whose Flutter projects all live outside `$HOME` still
protects its global SDK.

### Error handling

Every new failure mode degrades toward doing less work, never toward deleting
more:

| Failure | Behaviour |
| --- | --- |
| `du` absent or unspawnable | falls back to the walk: slower, still correct |
| `du` stdout unparseable | falls back to the walk |
| `du` partial permission failure | uses the printed total, as the walk would |
| `~/fvm/default` unreadable or dangling | no global version found; SDK judged by config references alone |
| `~/fvm/default` present | that SDK is spared |

No new fatal paths, and no new way for a directory to become deletable.

## Testing

`test/dir_size_test.dart`:

- the existing exact-byte assertion (`1500`) moves onto `walkSizeBytes`, which
  still has apparent-size semantics;
- the selector gets a block-aware assertion instead of an exact byte count;
- `duSizeBytes` and `walkSizeBytes` agree within block granularity on a fixture
  tree;
- a symlink pointing outside the tree is excluded under both implementations
  (verified: `du` does not follow it);
- a tree with one unreadable subdirectory still yields a total from
  `duSizeBytes` rather than `null`;
- `duSizeBytes` on a missing path returns `null`;
- `du`-specific tests skip on Windows, as the symlink test already does.

`test/fvm_sdks_test.dart`:

- an SDK referenced by no config but pointed at by `~/fvm/default` is not
  `unused`;
- a dangling `~/fvm/default` does not throw and leaves other judgements intact;
- an installed SDK that is neither referenced nor the global default is still
  reported `unused`;
- the global default is honoured even when no config files exist anywhere under
  `home`.

## Documentation

- README: a line stating that reported sizes are disk usage (allocated blocks),
  not apparent file size, and that fvm's global SDK is never offered for
  deletion.
- CHANGELOG: both entries under 0.2.0, with the size-semantics change called
  out as user-visible.
- `packageVersion` in `lib/src/cli.dart` and `version` in `pubspec.yaml` both
  move to 0.2.0.

## Out of scope

Named here so they are not smuggled in: the `findProjects` depth-6 versus
fvm-config depth-10 mismatch, human-readable size units in the listing,
parallelising the scan with isolates, JSON-parsing the fvm configs, and
tightening `isDeletable` from a basename allowlist to full-path matching.
