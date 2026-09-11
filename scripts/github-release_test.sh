#!/usr/bin/env bash
# Tests for github-release.sh. Every refusal and the success path, against fixtures.
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

SUT="${DIR}/github-release.sh"
GH="$TMP/gh"
cat > "$GH" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in
  "release view")
    if [ "\$3" = "--json" ]; then sed -E 's/.*"tagName":"([^"]*)".*/\\1/' "$TMP/latest-tag" 2>/dev/null; exit 0; fi
    [ -f "$TMP/release-exists" ] ;;
  "api -X")
    printf '%s\n' "\$@" > "$TMP/patched-args"; [ -f "$TMP/patch-fails" ] && exit 1; exit 0 ;;
  "api "*) printf '42\n' ;;
  "release create")
    [ -f "$TMP/create-fails" ] && { echo "HTTP 502" >&2; exit 1; }
    shift 2; printf '%s\n' "\$@" > "$TMP/created-args"
    while [ \$# -gt 0 ]; do [ "\$1" = "--notes-file" ] && { cp "\$2" "$TMP/created-notes"; shift; }; shift; done ;;
  *) exit 64 ;;
esac
EOF
chmod +x "$GH"
seed() {
  rm -f "$TMP/release-exists" "$TMP/created-args" "$TMP/created-notes" "$TMP/create-fails" "$TMP/patched-args" "$TMP/patch-fails"
  printf '## [1.3.0] - 2026-09-11\n\n- **The new thing.** It does the thing.\n\n## [1.2.9] - 2026-09-01\n\n- Old fix that must not leak.\n' > "$TMP/CHANGELOG.md"
  printf '{"tagName":"v1.3.0"}' > "$TMP/latest-tag"
}
run() { GITHUB_RELEASE_GH="$GH" TAG="$1" CHANGELOG="${2:-$TMP/CHANGELOG.md}" GITHUB_REPOSITORY=o/r bash "$SUT" 2>&1; }

seed; out="$(run v1.3.0)"; rc=$?
[ "$rc" -eq 0 ] && ok "happy: exit 0" || fail "happy -- rc=$rc out='$out'"
[ -f "$TMP/created-args" ] && ok "happy: release created" || fail "happy: no create call"
grep -q -- '--verify-tag' "$TMP/created-args" && ok "happy: --verify-tag" || fail "happy: --verify-tag missing"
grep -q -- '--generate-notes' "$TMP/created-args" && ok "happy: --generate-notes" || fail "happy: --generate-notes missing"
grep -q -- '--latest' "$TMP/created-args" && fail "happy: --latest forced on create" || ok "happy: --latest not forced on create"
[ -f "$TMP/patched-args" ] && grep -q 'make_latest=legacy' "$TMP/patched-args" && grep -q 'repos/o/r/releases/42' "$TMP/patched-args" && ok "happy: latest follows GitHub's date-and-version rule (make_latest=legacy on the new release)" || fail "happy: make_latest=legacy not set: $(cat "$TMP/patched-args" 2>/dev/null)"
grep -q 'The new thing' "$TMP/created-notes" && ok "happy: block leads the notes" || fail "happy: block missing from notes"
grep -q 'Old fix' "$TMP/created-notes" && fail "happy: previous block leaked" || ok "happy: notes scoped to 1.3.0"
printf '%s' "$out" | grep -q '::warning::' && fail "happy: a warning on a clean publish: $out" || ok "happy: no warning on a clean publish"
printf '%s' "$out" | grep -q "as its latest release (GitHub's date-and-version rule)" && ok "happy: the closing line credits the rule that was applied" || fail "happy: closing line: $out"

seed; touch "$TMP/release-exists"; out="$(run v1.3.0)"; rc=$?
[ "$rc" -eq 0 ] && [ ! -f "$TMP/created-args" ] && ok "existing release: exit 0, nothing created" || fail "existing -- rc=$rc created=$([ -f "$TMP/created-args" ] && echo yes || echo no)"
[ -f "$TMP/patched-args" ] && grep -q 'make_latest=legacy' "$TMP/patched-args" && ok "existing release: the latest policy is applied on the re-run too" || fail "existing: no make_latest patch on the re-run"

seed; touch "$TMP/release-exists" "$TMP/patch-fails"; out="$(run v1.3.0)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'Finish by hand: gh api -X PATCH repos/o/r/releases/42' && ok "existing release, failed patch: exit 0 with the by-hand command" || fail "existing-patch-fail -- rc=$rc out='$out'"
printf '%s' "$out" | grep -q 'may not be in force' && ! printf '%s' "$out" | grep -q 'has marked it latest' && ok "existing release, failed patch: the warning claims only what it knows" || fail "existing-patch-fail wording: $out"

seed; out="$(run v1.3.0-rc.1)"; rc=$?
[ "$rc" -eq 0 ] && [ ! -f "$TMP/created-args" ] && printf '%s' "$out" | grep -q 'pre-release' && ok "pre-release: skipped, nothing created" || fail "prerelease -- rc=$rc out='$out'"

seed; out="$(run v1.4.0)"; rc=$?
[ "$rc" -eq 1 ] && [ ! -f "$TMP/created-args" ] && printf '%s' "$out" | grep -q 'no .* block' && ok "no block: refused before create" || fail "no-block -- rc=$rc out='$out'"

seed; printf '## [1.5.0] - 2026-09-11\n\n\n## [1.3.0] - 2026-09-11\n\n- x\n' > "$TMP/CHANGELOG.md"; out="$(run v1.5.0)"; rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'empty' && ok "empty block: refused" || fail "empty -- rc=$rc out='$out'"

seed; out="$(run 1.3.0)"; rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'not v' && ok "tag without v prefix refused" || fail "bad-tag -- rc=$rc out='$out'"

seed; touch "$TMP/patch-fails"; out="$(run v1.3.0)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'could not set make_latest' && ok "a failed make_latest patch is a warning, the Release stands" || fail "patch-fail -- rc=$rc out='$out'"
printf '%s' "$out" | grep -q 'has marked it latest regardless' && ! printf '%s' "$out" | grep -q 'date-and-version rule' && ok "a failed make_latest patch: the closing line does not credit a rule that was not applied" || fail "patch-fail wording: $out"

seed; out="$(env -u GITHUB_REPOSITORY GITHUB_RELEASE_GH="$GH" TAG=v1.3.0 CHANGELOG="$TMP/CHANGELOG.md" bash "$SUT" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && [ ! -f "$TMP/created-args" ] && printf '%s' "$out" | grep -q 'REPO' && ok "an unset REPO is refused before anything is published" || fail "no-repo -- rc=$rc out='$out'"

seed; out="$(run v1.3.0 "$TMP/missing.md")"; rc=$?
[ "$rc" -eq 1 ] && [ ! -f "$TMP/created-args" ] && printf '%s' "$out" | grep -q 'no changelog' && ok "missing changelog refused before create" || fail "no-changelog -- rc=$rc out='$out'"

seed; touch "$TMP/create-fails"; out="$(run v1.3.0)"; rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'release create failed' && ok "a failed gh release create is reported, exit 1" || fail "create-fail -- rc=$rc out='$out'"

seed; printf '{"tagName":"v1.2.9"}' > "$TMP/latest-tag"; out="$(run v1.3.0)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'reports v1.2.9 as its latest release' && ! printf '%s' "$out" | grep -q '::warning::' && ok "a backport that is not the latest is reported as information, not warned about" || fail "backport -- rc=$rc out='$out'"
printf '%s' "$out" | grep -q "reports v1.2.9 as its latest release (GitHub's date-and-version rule)" && ok "backport: the closing line credits the rule" || fail "backport closing line: $out"

out="$(env -u TAG GITHUB_RELEASE_GH="$GH" CHANGELOG="$TMP/CHANGELOG.md" bash "$SUT" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'TAG is required' && ok "an unset TAG is refused" || fail "unset-tag -- rc=$rc out='$out'"

if [ "$FAILURES" -ne 0 ]; then
  printf '%s failure(s)\n' "$FAILURES"; exit 1
fi
printf 'all %s tests passed\n' "$(basename "${BASH_SOURCE[0]}" _test.sh)"
