# flutter-reap

Reclaim disk from Flutter projects and shared caches. Dry run by default.

```sh
./flutter-reap              # scan ~, show everything
./flutter-reap ~/projects 30   # only projects idle 30+ days
DELETE=1 ./flutter-reap        # prompt, then remove
```

Finds, per project: `build/`, `.dart_tool/`, `ios/Pods`, `android/.gradle`, `macos/Pods`.
Staleness comes from the **last commit** (or `pubspec.yaml` mtime), not the build dir —
build dirs reset on every build, so they always look fresh.

Also lists your fvm SDKs and flags any that **no project references** — usually the
biggest single win, ~1–3 GB per orphaned SDK. Reference scanning always covers all of
`$HOME`, even when you narrow the scan root, so an SDK used elsewhere is never marked unused.

Leaves `~/.pub-cache` alone: it's shared and refetchable, and `dart pub cache clean` covers it.

## Why

`flutter clean` is per-project. `dart pub cache clean` is all-or-nothing. Neither knows
which of your 18 projects you stopped touching a year ago, and nothing knows about fvm.

## Status

Bash, macOS-tested. Linux should work; Windows doesn't. A Dart port (for
`dart pub global activate`) is the plan if people want it.

MIT.
