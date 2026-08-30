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
