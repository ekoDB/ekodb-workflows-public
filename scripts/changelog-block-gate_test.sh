#!/usr/bin/env bash
# Tests for <script>. Every refusal and the success path, against fixtures.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILURES=0
ok()   { printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

SUT="${DIR}/changelog-block-gate.sh"
run() { VERSION="$1" CHANGELOG="$2" bash "$SUT" 2>&1; }

printf '## [1.2.3] - 2026-09-11\n\n- an entry\n\n## [1.2.2] - 2026-09-01\n' > "$TMP/dated.md"
out="$(run 1.2.3 "$TMP/dated.md")"; rc=$?
[ "$rc" -eq 0 ] && ok "dated block passes" || fail "dated -- rc=$rc out='$out'"

printf '## [1.2.3]\n\n- an entry\n' > "$TMP/undated.md"
out="$(run 1.2.3 "$TMP/undated.md")"; rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no date' && ok "heading without a date is refused and named" || fail "undated -- rc=$rc out='$out'"

printf '## [Unreleased]\n\n- an entry\n\n## [1.2.2] - 2026-09-01\n' > "$TMP/unreleased.md"
out="$(run 1.2.3 "$TMP/unreleased.md")"; rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'Unreleased' && ok "still under [Unreleased] is refused and named" || fail "unreleased -- rc=$rc out='$out'"

printf '## [1.2.2] - 2026-09-01\n\n- old\n' > "$TMP/missing.md"
out="$(run 1.2.3 "$TMP/missing.md")"; rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no .* block' && ok "no block is refused" || fail "missing -- rc=$rc out='$out'"

out="$(run 1.2.3 "$TMP/absent.md")"; rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no changelog' && ok "missing file is refused" || fail "absent -- rc=$rc out='$out'"

out="$(run 1.2.3-rc.1 "$TMP/dated.md")"; rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'pre-release' && ok "a pre-release version is refused" || fail "prerelease -- rc=$rc out='$out'"

if [ "$FAILURES" -ne 0 ]; then
  printf '%s failure(s)\n' "$FAILURES"; exit 1
fi
printf 'all %s tests passed\n' "$(basename "${BASH_SOURCE[0]}" _test.sh)"
