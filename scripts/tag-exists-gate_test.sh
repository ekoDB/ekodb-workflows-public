#!/usr/bin/env bash
# Tests for tag-exists-gate.sh. Every refusal and the success path, against fixtures.
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

SUT="${DIR}/tag-exists-gate.sh"
GH="$TMP/gh"
cat > "$GH" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TMP/calls"
case "\$2" in
  repos/o/r/git/ref/tags/v1.2.3) printf '{"ref":"refs/tags/v1.2.3"}\n' ;;
  repos/o/r/git/ref/tags/v9.9.9) printf '{"message":"Not Found","status":"404"}\n' >&2; exit 1 ;;
  repos/o/r/git/ref/tags/v2.0.0) printf '{"ref":"refs/tags/v2.0.0-rc.1"}\n' ;;
  *) printf 'connection reset\n' >&2; exit 1 ;;
esac
EOF
chmod +x "$GH"
run() { TAG_EXISTS_GATE_GH="$GH" TAG="${1-}" REPO="${2-}" GITHUB_REPOSITORY="" bash "$SUT" 2>&1; }

out="$(run v1.2.3 o/r)"; rc=$?
[ "$rc" -eq 0 ] && ok "existing tag passes" || fail "exists -- rc=$rc out='$out'"
grep -q 'repos/o/r/git/ref/tags/v1.2.3' "$TMP/calls" && ok "asked the tags endpoint for exactly that tag" || fail "endpoint not asked"

out="$(TAG_EXISTS_GATE_GH="$GH" TAG=v1.2.3 REPO="" GITHUB_REPOSITORY=o/r bash "$SUT" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'exists in o/r' && ok "GITHUB_REPOSITORY stands in for an unset REPO" || fail "fallback -- rc=$rc out='$out'"

out="$(run v9.9.9 o/r)"; rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'does not exist' && ok "a 404 is 'the cutter did not push it'" || fail "404 -- rc=$rc out='$out'"

out="$(run v2.0.0 o/r)"; rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'not the one asked' && ok "an answer naming another ref is refused" || fail "other-ref -- rc=$rc out='$out'"

out="$(run v3.3.3 o/x)"; rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'could not determine' && ok "an API failure is 'could not determine', never a pass" || fail "api-fail -- rc=$rc out='$out'"

out="$(run '' o/r)"; rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'TAG is required' && ok "missing TAG refused" || fail "no-tag -- rc=$rc out='$out'"

out="$(run 1.2.3 o/r)"; rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'not v<semver>' && ok "a tag without the v prefix is refused" || fail "bad-tag -- rc=$rc out='$out'"

out="$(run v1.2.3 '')"; rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'REPO' && ok "missing REPO refused" || fail "no-repo -- rc=$rc out='$out'"

if [ "$FAILURES" -ne 0 ]; then
  printf '%s failure(s)\n' "$FAILURES"; exit 1
fi
printf 'all %s tests passed\n' "$(basename "${BASH_SOURCE[0]}" _test.sh)"
