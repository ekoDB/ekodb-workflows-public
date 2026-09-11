#!/usr/bin/env bash
# Tests for release-tag-gate.sh. Every refusal and the success path, against fixtures.
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

SUT="${DIR}/release-tag-gate.sh"

# A throwaway git repo: the gate asks git about local tags. The fixture commit
# carries its own identity, so it works on a runner that has none configured.
export GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid
export GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid
REPO="$TMP/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q; git -C "$REPO" commit -q --allow-empty -m "init"
printf '## [1.2.3] - 2026-09-11\n\n- an entry\n\n## [1.2.2] - 2026-09-01\n\n- old\n' > "$REPO/CHANGELOG.md"

run() { # VERSION SUBJECT_VERSION [LSREMOTE]
  ( cd "$REPO" && VERSION="$1" SUBJECT_VERSION="$2" CHANGELOG=CHANGELOG.md \
      RELEASE_TAG_GATE_LSREMOTE="${3:-printf ''}" bash "$SUT" 2>&1 )
}

out="$(run 1.2.3 1.2.3)"; rc=$?
[ "$rc" -eq 0 ] && ok "happy: safe to cut" || fail "happy -- rc=$rc out='$out'"

out="$(run 1.2.3-rc.1 1.2.3-rc.1)"; rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'plain X.Y.Z' && ok "pre-release refused" || fail "prerelease -- rc=$rc out='$out'"

out="$(run 1.2.3 1.2.4)"; rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'subject' && ok "subject/manifest disagreement refused" || fail "mismatch -- rc=$rc out='$out'"

out="$(run 1.2.4 1.2.4)"; rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'changelog' && ok "no dated block refused (delegated to changelog-block-gate)" || fail "no-block -- rc=$rc out='$out'"

printf '## [1.2.5] - 2026-09-11\n\n\n## [1.2.3] - 2026-09-11\n\n- an entry\n' > "$REPO/CHANGELOG.md"
out="$(run 1.2.5 1.2.5)"; rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'empty' && ok "empty block refused" || fail "empty -- rc=$rc out='$out'"
printf '## [1.2.3] - 2026-09-11\n\n- an entry\n' > "$REPO/CHANGELOG.md"

git -C "$REPO" tag v1.2.3
out="$(run 1.2.3 1.2.3)"; rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'already exists' && ok "local tag refused" || fail "local-tag -- rc=$rc out='$out'"
git -C "$REPO" tag -d v1.2.3 >/dev/null

out="$(run 1.2.3 1.2.3 "printf 'abc\trefs/tags/v1.2.3\n'")"; rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'on origin' && ok "remote tag refused" || fail "remote-tag -- rc=$rc out='$out'"

out="$(run 1.2.3 1.2.3 "exit 128")"; rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'failing closed' && ok "an unanswerable remote fails closed" || fail "remote-fail -- rc=$rc out='$out'"

out="$(cd "$REPO" && env -u VERSION SUBJECT_VERSION=1.2.3 CHANGELOG="$TMP/CHANGELOG.md" bash "$SUT" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'VERSION is required' && ok "an unset VERSION is refused" || fail "unset-version -- rc=$rc out='$out'"
out="$(cd "$REPO" && env -u SUBJECT_VERSION VERSION=1.2.3 CHANGELOG="$TMP/CHANGELOG.md" bash "$SUT" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'SUBJECT_VERSION is required' && ok "an unset SUBJECT_VERSION is refused" || fail "unset-subject -- rc=$rc out='$out'"

if [ "$FAILURES" -ne 0 ]; then
  printf '%s failure(s)\n' "$FAILURES"; exit 1
fi
printf 'all %s tests passed\n' "$(basename "${BASH_SOURCE[0]}" _test.sh)"
