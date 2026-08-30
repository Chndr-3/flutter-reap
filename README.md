# flutter_reap

Find Flutter build artifacts you stopped using months ago, and see how much
space they're wasting. Dry run by default.

## Install

```sh
dart pub global activate flutter_reap
```

## Use

```sh
flutter_reap ~              # scan home, show everything, delete nothing
flutter_reap ~ --days 90    # only projects untouched for 90+ days
flutter_reap ~ --delete     # list, then choose what to keep
```

Illustrative output — not a measured figure, just the shape of it:

```
  1. 1840M    214d  ~/AndroidStudioProjects/old-client-app
  2.  920M    131d  ~/AndroidStudioProjects/side-project
  3.   12M      3d  ~/AndroidStudioProjects/current-work
  4. 14204M          ~/Library/Developer/Xcode/DerivedData
  5.  3100M          ~/.gradle/caches
--- 5 dirs, 20076M reclaimable
(dry run - pass --delete to remove)
```

## Options

```
-d, --days <n>     only projects idle n+ days (default 0)
    --delete       enter the delete flow (default is a dry run)
    --no-caches    skip machine-wide caches
    --json         machine-readable output, implies a dry run
-y, --yes          delete without review; requires --days
-h, --help
-v, --version
```

## What it looks at

Per project: `build/`, `.dart_tool/`, `ios/Pods`, `macos/Pods`, `android/.gradle`.

Machine-wide caches and fvm SDKs are only included when the scan root is your
home directory — narrowing the root to a subfolder of projects can't
accidentally touch them:

- Xcode `DerivedData` and the CocoaPods cache (macOS)
- `~/.gradle/caches` and `~/.android/cache` (macOS, Linux and Windows)

If you use [fvm](https://fvm.app), it also flags SDK versions **no project
references** — roughly 1–3 GB each. Silent if you don't use fvm.

## Why not just `flutter clean`

`flutter clean` is one project at a time, and you have to remember which
projects exist. `dart pub cache clean` is all-or-nothing. Neither knows that
you last touched `old-client-app` in March.

## How it decides something is stale

The **last commit date** for git projects, falling back to `pubspec.yaml`'s
modification time for projects that aren't git repos — never the build
directory's own timestamp, which resets on every build and would make a
two-year-dead project look freshly touched.

## Safety

- Dry run unless you pass `--delete`. Even then, nothing is removed until you
  answer the `keep which?` prompt: an empty answer deletes everything listed,
  `k` cancels, and anything that doesn't parse also cancels rather than
  guessing.
- `--yes` skips that prompt, but is rejected unless you also pass `--days`, so
  an unfiltered delete-everything is never one keystroke away.
- Deletion is refused for any directory whose final path segment isn't a known
  generated name (`build`, `.dart_tool`, `Pods`, `.gradle`, `caches`, `cache`,
  `DerivedData`, `CocoaPods`, or an fvm SDK version directory), and for
  anything sitting directly under a filesystem root. A bug in path handling
  cannot reach `lib/`, `pubspec.yaml`, or your source.
- `~/.pub-cache` is never touched, on any platform — it's shared across every
  project and slow to refetch. Use `dart pub cache clean` if you really want
  it gone.
- `dart test` covers all of the above, including that a directory which isn't
  a known generated name is never deleted, and that declining the prompt
  deletes nothing.

## Platform support

Tested in CI on Linux, macOS and Windows.

## License

MIT.
