# flutter_reap: Dart port design

**Date:** 2026-08-30
**Status:** approved, not yet implemented

## Goal

Get flutter-reap into the hands of Flutter developers who are not its author.

The bash version works and is tested, but it can only be installed by cloning a
repository, and it cannot run on Windows. Both are distribution problems, not code
problems. Porting to Dart puts the tool on pub.dev — where Flutter developers already
look — and makes Windows support possible.

Success in three months: a pub.dev listing, installs from strangers, and issues filed by
people the author has never met. The project is maintained as an ongoing hobby, so the
codebase must be one that Flutter developers can contribute to. Effectively nobody sends
PRs to a bash script.

## Scope

Flutter only. Not mobile-wide, not a general dev-machine cleaner.

pub.dev has no cache-reclamation tool today (`flutter_pruner`, `flutter_unused_packages`
and `flutter_app_size_reducer` all analyse *code*, not disk). Going wider means competing
with npkill (9.4k stars) and kondo on ground where developers already have habits, and it
dilutes the Flutter-specific advantages — fvm awareness and Flutter's particular mix of
Gradle, CocoaPods and Xcode artifacts.

## Package

`flutter_reap` on pub.dev. Installed with `dart pub global activate flutter_reap`, invoked
as `flutter_reap`.

Dependencies: `args`, and `dart:io`. Nothing else. A tool that deletes directories should
have a dependency tree a reviewer can read in one sitting.

## Modules

| Module | Question it answers | Depends on |
|---|---|---|
| `project_scanner` | where are the Flutter projects under this root? | `dart:io` |
| `staleness` | when did a human last touch this project? | git, else `pubspec.yaml` mtime |
| `dir_size` | how big is this directory? | `dart:io` |
| `shared_caches` | what machine-wide caches exist on this OS? | `Platform` |
| `fvm_sdks` | which fvm SDKs does no project reference? | `project_scanner` |
| `reap_plan` | what are the candidates, and what survived review? | the four above |
| `bin/flutter_reap.dart` | parse args, print, call the plan | everything |

`reap_plan` is the load-bearing seam. It produces a list of candidates and accepts a
filtered list back. It never deletes anything and never touches the terminal. This is what
makes the logic testable without a filesystem full of fake projects, and what allows a TUI
to be added later as just another filter over the same list — the same role `$EDITOR`
played in the bash version.

All OS-specific knowledge lives in `shared_caches`. Every other module is OS-agnostic.

## CLI

```
flutter_reap [path] [options]

  -d, --days <n>     only projects idle n+ days (default: 0, show all)
      --delete       enter the delete flow (default is dry run)
      --no-caches    skip machine-wide caches, projects only
      --json         machine-readable output, implies dry run
  -y, --yes          delete everything listed without review
  -h, --help  -v, --version
```

`--delete` replaces the bash version's `DELETE=1` environment variable: it is discoverable
from `--help`, which an environment variable never is.

`-y` must be combined with `--days`. It exists for CI, but an unfiltered `-y` across an
entire home directory should not be one keystroke away.

## Selection

A numbered list and a prompt. The answer names what to **keep**, and the wording avoids
bare "all"/"none", which is ambiguous about which side of the line it means:

```
keep which? (e.g. 1,3-5)  [enter = keep nothing, delete all]  [k = keep everything, cancel]
```

Deleting everything therefore requires a deliberate empty answer at a prompt that has just
listed every path, and any unparseable input cancels.

Chosen over `$EDITOR` (unset on most Windows machines, awkward to test) and over a full
TUI (raw terminal mode, an extra dependency, painful in CI). The numbered prompt behaves
identically on every OS and is tested by piping stdin.

A TUI remains possible later without touching the scan logic, because of the `reap_plan`
seam.

## Data flow

```
scan root ──> project_scanner ──> for each project:
                                    staleness  ──> age in days
                                    dir_size   ──> MB per artifact dir
                                        │
shared_caches (only if root == home) ───┤
                                        ▼
                                   reap_plan: candidates, sorted by size
                                        │
                        ┌───────────────┴───────────────┐
                    dry run                          --delete
                   print, exit                     numbered prompt
                                                        │
                                                  keep-list applied
                                                        ▼
                                                  delete survivors
```

Per project, the tool looks at `build/`, `.dart_tool/`, `ios/Pods`, `macos/Pods` and
`android/.gradle`.

Machine-wide, on a home-directory scan only: Xcode `DerivedData` and the CocoaPods cache
(macOS), `~/.gradle/caches` (macOS and Linux), `%USERPROFILE%\.gradle\caches` and
`%LOCALAPPDATA%\Pub\Cache` (Windows).

If fvm is installed, `fvm_sdks` also reports SDK versions that no project references —
roughly 1–3 GB each. It reads every `.fvmrc` and `fvm_config.json` under the home directory
and matches version names against the installed SDKs. It stays silent when `~/fvm` does not
exist, which is most users: fvm is a minority tool and must never dominate the output.

Reference scanning always covers the whole home directory even when the scan root is
narrower. A narrow scan that marked an in-use SDK as unused is exactly the bug that would
have deleted 2.7 GB.

`~/.pub-cache` is deliberately left alone. It is shared across every project and slow to
refetch; `dart pub cache clean` already covers it.

Scanning and sizing run concurrently. Sizing a large `DerivedData` is the slow step, and
running it in parallel with the scan lets results stream rather than appearing after a
long silence.

### Two behaviours carried over from bash

Both were bugs before they were features, and both cost real debugging:

**Staleness comes from the last commit**, not the build directory's own timestamp. A build
directory's timestamp resets on every build, so a long-dead project looks freshly touched
and the age filter silently matches nothing.

**Machine-wide caches appear only when the scan root is the home directory.** Narrowing the
root must never widen what is at risk. In the bash version this omission meant running the
test suite would queue the developer's real DerivedData for deletion.

## Safety

- Dry run is the default. `--delete` requires an explicit keep/none answer; empty or
  unparseable input cancels everything rather than proceeding.
- Only directories whose final path segment matches a known generated name are ever
  removed, so a path-handling bug cannot reach `lib/` or `pubspec.yaml`.
- Permission errors, vanished directories and unreadable git repositories are skipped with
  a note, never fatal. One unreadable folder must not end a scan of 200 projects.
- Refuse to run when the scan root is a filesystem root.
- Projects with uncommitted changes are marked `⚠`. Deleting `build/` there is still safe,
  but it signals live work.

## Testing

`package:test`, one file per module, each building a throwaway tree under
`Directory.systemTemp`.

The suite ports every check the bash version has, including the three that caught real
data-loss bugs: an in-use fvm SDK reported as unused, machine-wide caches in scope during a
narrow scan, and GNU `stat -f` returning filesystem information with exit 0 (making every
project read as age zero). It adds the checks the seam makes cheap: `reap_plan` tested
against fabricated candidates with no filesystem at all.

CI runs `dart analyze` and `dart test` on Linux, macOS and Windows. Windows is the entire
reason for the port; untested Windows support is only a claim.

## Retiring the bash script

Once the Dart version reaches parity, the bash script is deleted.

Two implementations of a tool that deletes directories means two places for a data-loss bug
to hide, and the unused one always rots. Git history preserves it.

## Publishing

pub.dev ranks search results partly by package score, so the following are ranking
requirements, not polish: `CHANGELOG.md`, dartdoc comments on public APIs, an `example/`,
zero analyzer issues, declared platform support, and `topics:` in the pubspec.

Launch order:

1. Obtain a real reclaim figure from a machine other than the author's. The author's
   machine yields 6 MB, which is not a pitch.
2. Record an asciinema or GIF of that run. The number is the pitch.
3. `dart pub publish` at `0.1.0`.
4. Post to r/FlutterDev, then Flutter Community on Medium.

## Explicitly out of scope

- A TUI. Revisit once real users ask for one.
- Compiled binaries on GitHub Releases. The entire audience has a Dart toolchain by
  definition.
- Touching `~/.pub-cache`.
- Any scheduled or background operation. A daemon that silently deletes directories is how
  someone loses the one `build/` they needed for a demo.
