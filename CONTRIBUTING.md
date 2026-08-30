# Contributing

It's one bash script. Keep it that way.

- `./test.sh` must pass before and after your change. It builds a throwaway project tree in `mktemp -d` and never touches real files.
- Anything that deletes needs a test proving it *doesn't* delete source.
- New cache directory to sweep? Add the name to `TARGETS` in `flutter-reap`. That's the whole change — no config file, please.
- No dependencies. Bash, `find`, `du`, `stat`, `grep`.
