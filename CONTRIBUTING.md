# Contributing

- `dart test` must pass before and after your change. Tests build a throwaway
  project tree in a temp directory and never touch real files.
- `dart analyze` must be clean.
- Anything that deletes needs a test proving it *doesn't* delete source.
- New generated directory to sweep inside a project? Add its relative path to
  `artifactRelativePaths` in `lib/src/project_scanner.dart`. That's the whole
  change — no config file, please.
- New machine-wide cache? Add it to `sharedCachePaths` in
  `lib/src/shared_caches.dart`, and add its final path segment to
  `_deletableNames` in `lib/src/deleter.dart` so deletion isn't refused.
- Minimal dependencies: `args` for the command line, `path` for cross-platform
  path handling.
