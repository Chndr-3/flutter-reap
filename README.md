# flutter-reap

Find Flutter build artifacts you stopped using months ago, and delete them. Dry run by default.

```sh
./flutter-reap                 # scan ~, show everything
./flutter-reap ~/projects 90   # only projects untouched for 90+ days
DELETE=1 ./flutter-reap        # open the list in $EDITOR, then remove what's left
```

```
== projects ==
  1840M   214d  ~/AndroidStudioProjects/old-client-app
   920M   131d  ~/AndroidStudioProjects/side-project
    12M     3d  ~/AndroidStudioProjects/current-work

== shared caches ==
 14204M  ~/Library/Developer/Xcode/DerivedData
  3100M  ~/.gradle/caches

--- reclaimable: 20076M across 9 dirs
```

## What it looks at

Per project: `build/`, `.dart_tool/`, `ios/Pods`, `macos/Pods`, `android/.gradle`.

Machine-wide (only on a full `~` scan): Xcode `DerivedData`, `~/.gradle/caches`,
the CocoaPods cache, and `~/.android/cache`. Everything here regenerates on your
next build — that's why it's safe to delete and why it grows without limit.

If you use [fvm](https://fvm.app), it also flags SDK versions **no project references**
— roughly 1–3 GB each. Silent if you don't use fvm.

## Why not just `flutter clean`

`flutter clean` is one project at a time, and you have to remember which projects exist.
`dart pub cache clean` is all-or-nothing. Neither knows that you last touched
`old-client-app` in March.

## How it decides something is stale

The **last commit date** (or `pubspec.yaml` mtime for non-git projects) — not the build
directory's own timestamp, which resets on every build and makes a two-year-dead project
look like you touched it this morning.

## Safety

- Dry run unless `DELETE=1`. Even then, the list opens in your `$EDITOR` first: delete a
  line to spare that directory, quit without saving to cancel everything. Nothing is
  removed until you save. (Same idea as `git rebase -i`, and it's why there's no TUI.)
- Only ever removes generated directories. Never `lib/`, never `pubspec.yaml`, never source.
- Shared caches and fvm SDKs are only touched on a full `~` scan, so narrowing the root
  can't surprise you.
- `./test.sh` covers all of the above, including that declining the prompt deletes nothing.
- `~/.pub-cache` is deliberately left alone — it's shared across every project and
  refetching it is slow. Use `dart pub cache clean` if you really want it gone.

## Install

```sh
git clone https://github.com/Chndr-3/flutter-reap && cd flutter-reap
./flutter-reap
```

Bash, no dependencies. Tested on macOS and Linux in CI. Windows isn't supported.

MIT.
