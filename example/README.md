# Examples

Scan your home directory and see what could be reclaimed:

```sh
flutter_reap ~
```

Only projects you have not touched in three months:

```sh
flutter_reap ~ --days 90
```

Delete, choosing what to spare from the numbered list:

```sh
flutter_reap ~ --days 90 --delete
```

Delete everything idle 90+ days without a review prompt (still requires `--days`):

```sh
flutter_reap ~ --days 90 --delete --yes
```

Report reclaimable space from CI without deleting anything:

```sh
flutter_reap ~ --json
```

Scan a specific project tree instead of your whole home directory (skips
machine-wide caches and fvm SDKs, since those are only in scope on a full
home-directory scan):

```sh
flutter_reap ~/projects --days 30
```
