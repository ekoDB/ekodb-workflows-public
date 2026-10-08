#!/usr/bin/env bash
# Commit-graph regression tests for direct and merge-wrapped release caps.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export LC_ALL=C
unset COMMIT SUBJECT VERSION SUBJECT_VERSION TAG CHANGELOG REPO GITHUB_REPOSITORY MAKEFLAGS MFLAGS
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILURES=0
ok()   { printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

git init -q -b main "$TMP"
cd "$TMP" || exit 1
git config user.name Test
git config user.email test@example.com
git -c commit.gpgsign=false commit -q --allow-empty -m 'initial'
base="$(git rev-parse HEAD)"
git switch -q -c release
git -c commit.gpgsign=false commit -q --allow-empty -m 'chore(*): v1.2.3'
cap="$(git rev-parse HEAD)"
git switch -q main
git -c commit.gpgsign=false commit -q --allow-empty -m 'docs: update main'
first_parent="$(git rev-parse HEAD)"
git -c commit.gpgsign=false merge -q --no-ff release -m 'Merge pull request #12 from release'
merge="$(git rev-parse HEAD)"
git branch release-merge "$merge"
git -c commit.gpgsign=false commit -q --allow-empty -m 'docs: after release'
later="$(git rev-parse HEAD)"

detect() { COMMIT="$1" bash "$DIR/release-cap-at-commit.sh" 2>&1; }
want_cap() { # <commit> <cap_sha> <label>
  out="$(detect "$1")"; rc=$?
  expected="$(printf 'version=1.2.3\ncap_sha=%s' "$2")"
  if [ "$rc" -eq 0 ] && [ "$out" = "$expected" ]; then ok "$3"; else fail "$3 -- rc=$rc out='$out'"; fi
}
want_not() { # <commit> <label>
  out="$(detect "$1")"; rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$out" ]; then ok "$2"; else fail "$2 -- rc=$rc out='$out'"; fi
}

want_cap "$cap" "$cap" 'direct cap (rebase or fast-forward)'
want_cap "$merge" "$cap" 'merge commit wrapping a cap on its second parent'
want_not "$first_parent" 'first-parent non-cap is ignored'
want_not "$later" 'a cap buried in earlier history is ignored'
want_not "$base" 'ordinary root commit is ignored'

git clone -q --depth 2 --branch release-merge "file://${TMP}" "${TMP}/shallow"
out="$(cd "${TMP}/shallow" && detect "$merge")"; rc=$?
expected="$(printf 'version=1.2.3\ncap_sha=%s' "$cap")"
if [ "$rc" -eq 0 ] && [ "$out" = "$expected" ]; then
  ok 'depth-2 checkout retains the merge parents'
else
  fail "depth-2 checkout retains the merge parents -- rc=$rc out='$out'"
fi

git switch -q -c followup "$cap"
git -c commit.gpgsign=false commit -q --allow-empty -m 'docs: later on release branch'
git switch -q main
git -c commit.gpgsign=false merge -q --no-ff followup -m 'Merge pull request #13 from followup'
want_not "$(git rev-parse HEAD)" 'cap behind the second-parent tip is ignored'

if [ "$FAILURES" -ne 0 ]; then
  printf '%s failure(s)\n' "$FAILURES"; exit 1
fi
printf 'all %s tests passed\n' "$(basename "${BASH_SOURCE[0]}" _test.sh)"
