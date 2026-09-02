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

## 0.1.1

- Prints scan progress to stderr while a run is in flight, so a scan of a
  large tree (or a home-directory scan sizing gigabytes of Xcode
  DerivedData) no longer sits silent for tens of seconds before dumping the
  finished listing.
- Progress is suppressed for `--json` and whenever stderr is not a
  terminal, so `--json` stays machine-readable and CI logs and redirected
  stderr stay clean.
- stdout is untouched: the listing and `--json` output are exactly as
  before, so piping into `jq` or a file keeps working.

## 0.1.0

First release.

- Scans a directory tree for Flutter projects and reports reclaimable build
  artifacts: `build/`, `.dart_tool/`, `ios/Pods`, `macos/Pods`, `android/.gradle`.
- Reports machine-wide caches on a home-directory scan: Xcode DerivedData, the
  CocoaPods cache, Gradle caches and the Android cache.
- Flags fvm SDK versions that no project references.
- Ranks projects by how long since a human last touched them, taken from the
  last commit rather than build directory timestamps.
- Dry run by default; deletion requires an explicit selection.
