#!/usr/bin/env bash
# Tests for changelog-version.sh. Every refusal and the success path, against fixtures.
set -uo pipefail
# Hermetic against the caller's environment: no inherited repository pointers,
# no global or system git config (identity, signing, hooks), none of the
# scripts' own input variables, and no flags a parent make would hand to a
# child, so a fixture behaves the same on a developer's machine, under
# `make VERSION=x test`, and on a bare runner.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
unset VERSION SUBJECT_VERSION SUBJECT TAG CHANGELOG REPO GITHUB_REPOSITORY MAKEFLAGS MFLAGS
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILURES=0
ok()   { printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

SUT="${DIR}/changelog-version.sh"
run() { CHANGELOG="$1" bash "$SUT" 2>&1; }

printf '# Changelog\n\n## [Unreleased]\n\n- pending\n\n## [1.4.0] - 2026-09-01\n\n- x\n\n## [1.3.9] - 2026-08-01\n\n- y\n' > "$TMP/with-unreleased.md"
out="$(run "$TMP/with-unreleased.md")"; rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "1.4.0" ] && ok "skips [Unreleased] and prints the newest release" || fail "newest -- rc=$rc out='$out'"

printf '# Changelog\n\n## [2.0.0] - 2026-09-11\n\n- z\n' > "$TMP/plain.md"
out="$(run "$TMP/plain.md")"; rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "2.0.0" ] && ok "first heading when there is no [Unreleased]" || fail "plain -- rc=$rc out='$out'"

printf '# Changelog\n\n## [Unreleased]\n\n- only pending\n' > "$TMP/only-unreleased.md"
out="$(run "$TMP/only-unreleased.md")"; rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no released' && ok "only [Unreleased] is a refusal" || fail "only-unreleased -- rc=$rc out='$out'"

out="$(run "$TMP/absent.md")"; rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no changelog' && ok "missing file is a refusal, not an empty version" || fail "absent -- rc=$rc out='$out'"

if [ "$FAILURES" -ne 0 ]; then
  printf '%s failure(s)\n' "$FAILURES"; exit 1
fi
printf 'all %s tests passed\n' "$(basename "${BASH_SOURCE[0]}" _test.sh)"
