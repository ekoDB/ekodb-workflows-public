#!/usr/bin/env bash
# public-hygiene_test.sh -- every ekoDB/<name> reference in this repository
# names a public repository. An ALLOW-LIST, never a deny-list: a deny-list
# would have to carry the private names it exists to keep out.
#
# It cannot catch an internal path or term that carries no ekoDB/ prefix; that
# stays with review.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILURES=0
ok()   { printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

ALLOWED="ekodb-client ekodb-client-go anndists hnswlib-rs ekodb-workflows-public"

# scan <root>: prints every disallowed token as "file: token"; exit 1 if any.
# A root with no tracked files is refused (exit 2): a scan of nothing is
# indistinguishable from a clean scan at the output, so it must not read as one.
scan() {
  local root="$1" bad=0 line name tracked
  tracked="$(cd "$root" && git ls-files 2>/dev/null | wc -l | tr -d ' ')"
  if [ "${tracked:-0}" -eq 0 ]; then
    printf 'no tracked files under %s -- refusing to report a clean scan of nothing\n' "$root"
    return 2
  fi
  while IFS= read -r line; do
    name="${line##*ekoDB/}"; name="${name%%[!A-Za-z0-9._-]*}"
    case " $ALLOWED " in
      *" $name "*) ;;
      *) printf '%s: ekoDB/%s\n' "${line%%:*}" "$name"; bad=1 ;;
    esac
  done < <(cd "$root" && git ls-files -z 2>/dev/null | xargs -0 grep -HnoiE 'ekoDB/[A-Za-z0-9._-]+' 2>/dev/null | sed -E 's/^([^:]+):[0-9]+:/\1:/' | sed -E 's/ekodb\//ekoDB\//i')
  return $bad
}

# 1. The fixture: a repo naming a disallowed repository must be caught. The
# disallowed token is composed at run time so this file, which the real-tree
# scan below also reads, never carries it at rest.
OWNER="ekoDB"; PRIVATE="$OWNER/something-private"
mkdir -p "$TMP/fixture"; git -C "$TMP/fixture" init -q
printf 'uses: ekoDB/ekodb-client-go/x@v1\nuses: %s/y@main\n' "$PRIVATE" > "$TMP/fixture/a.yml"
git -C "$TMP/fixture" add a.yml
out="$(scan "$TMP/fixture")"; rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF "$PRIVATE" && ok "fixture: a disallowed name is reported" || fail "fixture -- rc=$rc out='$out'"
printf '%s' "$out" | grep -q 'ekodb-client-go' && fail "fixture: an allowed name was reported" || ok "fixture: allowed names pass"

# 2. Case: the owner is matched case-insensitively, the name exactly.
printf 'see ekodb/ekodb-client and EKODB/anndists\n' > "$TMP/fixture/b.md"; git -C "$TMP/fixture" add b.md
git -C "$TMP/fixture" rm -q --cached a.yml
out="$(scan "$TMP/fixture")"; rc=$?
[ "$rc" -eq 0 ] && ok "owner case-insensitive, allowed names pass" || fail "case -- rc=$rc out='$out'"

# 3. A root with nothing tracked is refused, never reported clean.
mkdir -p "$TMP/empty"; git -C "$TMP/empty" init -q
out="$(scan "$TMP/empty")"; rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'no tracked files' && ok "an empty root is refused, not reported clean" || fail "empty -- rc=$rc out='$out'"

# 4. The real tree.
out="$(scan "${PUBLIC_HYGIENE_ROOT:-$DIR/..}")"; rc=$?
[ "$rc" -eq 0 ] && ok "this repository names only public repositories" || fail "this repository names a non-public repository: $out"

if [ "$FAILURES" -ne 0 ]; then printf '%s failure(s)\n' "$FAILURES"; exit 1; fi
printf 'all public-hygiene tests passed\n'
