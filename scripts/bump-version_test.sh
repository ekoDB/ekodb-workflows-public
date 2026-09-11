#!/usr/bin/env bash
# Tests for the Makefile's bump-version target. Every refusal and the success
# path, against a copy of the Makefile in a throwaway directory.
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

REPO="$TMP/repo"
seed() {
  rm -rf "$REPO"; mkdir -p "$REPO"; cp "${DIR}/../Makefile" "$REPO/Makefile"
  printf '# Changelog\n\n## [Unreleased]\n\n### Added\n\n- **The new thing.**\n\n## [0.0.1] - 2026-01-01\n\n- Old.\n' > "$REPO/CHANGELOG.md"
  printf '{\n  "version": "0.0.1"\n}\n' > "$REPO/version.json"
}
run() { make -C "$REPO" bump-version "$@" 2>&1; }
today="$(date -u +%Y-%m-%d)"

seed; out="$(run VERSION=1.0.0)"; rc=$?
[ "$rc" -eq 0 ] && grep -q "^## \[1.0.0\] - ${today}$" "$REPO/CHANGELOG.md" && ok "collapses [Unreleased] into a dated block" || fail "collapse -- rc=$rc out='$out'"
grep -q '^## \[Unreleased\]' "$REPO/CHANGELOG.md" && fail "collapse: [Unreleased] heading survived" || ok "collapse: no [Unreleased] heading remains"
grep -q '^## \[0.0.1\] - 2026-01-01$' "$REPO/CHANGELOG.md" && ok "collapse: the released block is untouched" || fail "collapse: released block moved"
grep -q '"version": "1.0.0"' "$REPO/version.json" && ok "stamps version.json" || fail "version.json: $(cat "$REPO/version.json")"
[ ! -f "$REPO/CHANGELOG.md.bak" ] && ok "leaves no .bak behind" || fail "CHANGELOG.md.bak left behind"
printf '%s' "$out" | grep -q 'chore(\*): v1.0.0' && ok "names the cap commit subject" || fail "subject hint missing: $out"

out="$(run VERSION=1.0.1)"; rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'no \[Unreleased\] block' && ok "a second bump with nothing unreleased is refused" || fail "second -- rc=$rc out='$out'"

seed; out="$(run VERSION=1.0.0-rc.1)"; rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'plain X.Y.Z' && grep -q '^## \[Unreleased\]' "$REPO/CHANGELOG.md" && ok "a pre-release is refused and nothing changes" || fail "prerelease -- rc=$rc out='$out'"

seed; out="$(run)"; rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'usage' && ok "a missing VERSION is refused with usage" || fail "no-version -- rc=$rc out='$out'"

seed; sed -i.bak 's/^## \[Unreleased\]$/## [Unreleased] - TBD/' "$REPO/CHANGELOG.md"; rm -f "$REPO/CHANGELOG.md.bak"; out="$(run VERSION=1.0.0)"; rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'no \[Unreleased\] block' && grep -q '^## \[Unreleased\] - TBD$' "$REPO/CHANGELOG.md" && grep -q '"version": "0.0.1"' "$REPO/version.json" && ok "a non-canonical [Unreleased] heading is refused and nothing is stamped" || fail "noncanonical -- rc=$rc out='$out'"

if [ "$FAILURES" -ne 0 ]; then
  printf '%s failure(s)\n' "$FAILURES"; exit 1
fi
printf 'all %s tests passed\n' "$(basename "${BASH_SOURCE[0]}" _test.sh)"
