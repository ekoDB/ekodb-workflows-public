#!/usr/bin/env bash
# Tests for release-cap-detect.sh. Every refusal and the success path, against fixtures.
set -uo pipefail
# Hermetic against the caller's git environment: no inherited repository
# pointers and no global or system config (identity, signing, hooks), so a
# fixture behaves the same on a developer's machine and on a bare runner.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILURES=0
ok()   { printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

SUT="${DIR}/release-cap-detect.sh"
detect() { SUBJECT="$1" bash "$SUT" 2>&1; }

want_cap() { # <subject> <version> <label>
  out="$(detect "$1")"; rc=$?
  if [ "$rc" -eq 0 ] && [ "$out" = "version=$2" ]; then ok "$3"; else fail "$3 -- rc=$rc out='$out'"; fi
}
want_not() { # <subject> <label>
  out="$(detect "$1")"; rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$out" ]; then ok "$2"; else fail "$2 -- rc=$rc out='$out'"; fi
}

want_cap 'chore(*): v1.2.3' 1.2.3 'star scope is a cap'
want_cap 'chore(core): v2.4.6' 2.4.6 'named scope is a cap'
want_cap 'chore: v10.20.30' 10.20.30 'no scope is a cap'
want_not 'chore(*): v1.2.3-rc.1' 'a pre-release suffix never tags'
want_not 'chore(*): v1.2.3-1' 'a numeric pre-release suffix never tags'
want_not 'docs: prepare for v1.2.3' 'a subject that mentions a version is not a cap'
want_not 'Revert "chore(*): v1.2.3"' 'a revert of a cap is not a cap'
want_not 'chore(*): v1.2.3 and more' 'trailing text is not a cap'
want_not ' chore(*): v1.2.3' 'a leading space is not a cap'
want_not 'Merge pull request #12 from x/chore(*): v1.2.3' 'a merge subject naming a cap is not a cap'
want_not $'feat: x\n\nchore(*): v1.2.3' 'a cap-shaped line in the body is not a cap'
want_not '' 'an empty subject is not a cap'

if [ "$FAILURES" -ne 0 ]; then
  printf '%s failure(s)\n' "$FAILURES"; exit 1
fi
printf 'all %s tests passed\n' "$(basename "${BASH_SOURCE[0]}" _test.sh)"
