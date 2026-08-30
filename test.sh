#!/usr/bin/env bash
# Self-check: builds a fake project tree, asserts flutter-reap finds and removes the right things.
set -euo pipefail
cd "$(dirname "$0")"

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0
check() { if [ "$2" != "$3" ]; then echo "FAIL: $1 (want '$3', got '$2')"; fail=1; else echo "ok: $1"; fi; }

# stale project: has junk, last commit long ago
mk() {
  mkdir -p "$tmp/$1"/{build,.dart_tool,ios/Pods,lib}
  echo "name: $1" > "$tmp/$1/pubspec.yaml"
  head -c 2000000 /dev/zero > "$tmp/$1/build/blob.bin"
  echo 'void main(){}' > "$tmp/$1/lib/main.dart"
}
mk stale; mk fresh
# clean project: no build dirs at all, must not appear
mkdir -p "$tmp/clean"; echo 'name: clean' > "$tmp/clean/pubspec.yaml"

# age comes from pubspec.yaml mtime when there's no git repo
touch -t 202401010000 "$tmp/stale/pubspec.yaml"

out=$(./flutter-reap "$tmp" 0 2>&1)
check "finds stale project"      "$(grep -c '/stale$'  <<<"$out")" 1
check "finds fresh project"      "$(grep -c '/fresh$'  <<<"$out")" 1
check "skips project with no junk" "$(grep -c '/clean$' <<<"$out")" 0
check "sums build+dart_tool size" "$(grep '/stale$' <<<"$out" | grep -c '  *[12]M')" 1

# age filter: stale is years old, fresh is seconds old
out=$(./flutter-reap "$tmp" 30 2>&1)
check "age filter keeps stale"   "$(grep -c '/stale$' <<<"$out")" 1
check "age filter drops fresh"   "$(grep -c '/fresh$' <<<"$out")" 0

# machine-wide stuff must never appear in a narrow scan - otherwise this very
# test run would queue the developer's real caches for deletion
check "narrow scan skips shared caches" "$(grep -c 'shared caches' <<<"$out")" 0
check "narrow scan skips fvm"           "$(grep -c 'fvm sdks'      <<<"$out")" 0
check "narrow scan reports no UNUSED"   "$(grep -c 'UNUSED'        <<<"$out")" 0

# dry run must not delete
./flutter-reap "$tmp" 0 >/dev/null 2>&1
check "dry run keeps files" "$([ -f "$tmp/stale/build/blob.bin" ] && echo yes || echo no)" yes

# DELETE=1 with 'n' must not delete
echo n | DELETE=1 ./flutter-reap "$tmp" 0 >/dev/null 2>&1 || true
check "declining keeps files" "$([ -f "$tmp/stale/build/blob.bin" ] && echo yes || echo no)" yes

# DELETE=1 with 'y' removes build dirs but never source
echo y | DELETE=1 ./flutter-reap "$tmp" 0 >/dev/null 2>&1 || true
check "delete removes build"    "$([ -d "$tmp/stale/build" ] && echo yes || echo no)" no
check "delete removes Pods"     "$([ -d "$tmp/stale/ios/Pods" ] && echo yes || echo no)" no
check "delete keeps lib/"       "$([ -f "$tmp/stale/lib/main.dart" ] && echo yes || echo no)" yes
check "delete keeps pubspec"    "$([ -f "$tmp/stale/pubspec.yaml" ] && echo yes || echo no)" yes

exit $fail
