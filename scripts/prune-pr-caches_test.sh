#!/usr/bin/env bash
# Tests for prune-pr-caches.sh, against a stubbed gh. The script deletes real
# caches, so the harness first proves the stub is what resolves as gh and runs
# nothing if it is not.
set -uo pipefail
# Hermetic against the caller's environment: no inherited repository pointers,
# none of the stub's own controls, and no flags a parent make would hand down.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE MAKEFLAGS MFLAGS
unset STUB_LIST_FAIL STUB_GONE_IDS STUB_FAIL_IDS GH_TOKEN GITHUB_TOKEN
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILURES=0
ok()   { printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

SUT="${DIR}/prune-pr-caches.sh"
export STUB_CALLS="$TMP/calls"
export STUB_FIXTURE="$TMP/caches.json"

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
# The list call runs the script's real jq filter over the fixture, so the ref
# selection is exercised rather than assumed.
printf '%s\n' "$*" >> "$STUB_CALLS"
[ "$1" = "api" ] || exit 99
shift
if [ "$1" = "-X" ]; then
  id="${3##*/}"
  case " ${STUB_GONE_IDS:-} " in *" $id "*) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;; esac
  case " ${STUB_FAIL_IDS:-} " in *" $id "*) echo "gh: Server Error (HTTP 500)" >&2; exit 1 ;; esac
  exit 0
fi
if [ -n "${STUB_LIST_FAIL:-}" ]; then
  echo "gh: Service Unavailable (HTTP 503)" >&2
  exit 1
fi
[ "$1" = "--paginate" ] && [ "$3" = "--jq" ] || exit 98
jq -r "$4" "$STUB_FIXTURE"
STUB
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"

if [ "$(command -v gh)" != "$TMP/bin/gh" ]; then
  printf 'FAIL: the gh stub is not first on PATH (%s); refusing to run a script that deletes caches\n' "$(command -v gh)"
  exit 1
fi

cat > "$STUB_FIXTURE" <<'JSON'
{"actions_caches":[
 {"id":101,"ref":"refs/pull/7/merge"},
 {"id":102,"ref":"refs/pull/7/head"},
 {"id":103,"ref":"refs/pull/7/merge"},
 {"id":201,"ref":"refs/pull/70/merge"},
 {"id":202,"ref":"refs/pull/17/head"},
 {"id":203,"ref":"refs/pull/7/mergeish"},
 {"id":301,"ref":"refs/heads/main"},
 {"id":302,"ref":"refs/heads/refs/pull/7/merge"}
]}
JSON

reset() { : > "$STUB_CALLS"; unset STUB_LIST_FAIL STUB_GONE_IDS STUB_FAIL_IDS; }
deleted() { grep -E '^api -X DELETE ' "$STUB_CALLS" | sed -E 's#.*/##' | sort -n | tr '\n' ' ' | sed 's/ $//'; }
calls() { wc -l < "$STUB_CALLS" | tr -d ' '; }

reset
out="$(bash "$SUT" acme/widgets 7 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "a normal prune exits 0" || fail "normal rc=$rc out='$out'"
[ "$(deleted)" = "101 102 103" ] && ok "deletes both refs of the closed pull request and nothing else" || fail "selection -- deleted '$(deleted)'"
grep -q 'repos/acme/widgets/actions/caches?per_page=100' "$STUB_CALLS" && ok "lists the named repository's caches" || fail "list url -- $(cat "$STUB_CALLS")"
printf '%s' "$out" | grep -q 'deleted 3' && ok "reports how many it deleted" || fail "count -- '$out'"

reset
out="$(bash "$SUT" acme/widgets 8 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ -z "$(deleted)" ] && printf '%s' "$out" | grep -q 'no caches' && ok "a pull request with no caches is a stated no-op" || fail "no caches rc=$rc out='$out'"

reset; export STUB_LIST_FAIL=1
out="$(bash "$SUT" acme/widgets 7 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && [ -z "$(deleted)" ] && printf '%s' "$out" | grep -q 'could not list' && ok "a list that could not run fails, and is not reported as no caches" || fail "list failure rc=$rc out='$out'"
if printf '%s' "$out" | grep -q 'no caches'; then fail "list failure read as no caches -- '$out'"; else ok "a failed list never says no caches"; fi

reset; export STUB_GONE_IDS="102"
out="$(bash "$SUT" acme/widgets 7 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'deleted 2' && printf '%s' "$out" | grep -q '1 already gone' && ok "a cache already gone is not a failure" || fail "404 rc=$rc out='$out'"

reset; export STUB_FAIL_IDS="102"
out="$(bash "$SUT" acme/widgets 7 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'cache 102' && ok "a failed delete fails the job and names the cache" || fail "500 rc=$rc out='$out'"
[ "$(grep -c -E '^api -X DELETE ' "$STUB_CALLS")" -eq 3 ] && ok "one failed delete does not stop the others" || fail "stopped early -- $(cat "$STUB_CALLS")"

refused() { # <description> <args...>: exits 2 and made no gh call at all.
  local name="$1" out rc; shift
  reset
  out="$(bash "$SUT" "$@" 2>&1)"; rc=$?
  [ "$rc" -eq 2 ] && [ "$(calls)" -eq 0 ] && ok "$name" || fail "$name -- rc=$rc calls=$(calls) out='$out'"
}
refused "refuses no arguments"
refused "refuses a missing pull request number" acme/widgets
refused "refuses an extra argument" acme/widgets 7 8
refused "refuses a non-numeric pull request number" acme/widgets abc
refused "refuses zero" acme/widgets 0
refused "refuses an empty pull request number" acme/widgets ""
refused "refuses a number carrying a jq expression" acme/widgets '7" or true or "'
refused "refuses a repository with no owner" widgets 7
refused "refuses a repository with a path in it" 'acme/widgets/../other' 7

if [ "$FAILURES" -ne 0 ]; then
  printf '%s failure(s)\n' "$FAILURES"; exit 1
fi
printf 'all %s tests passed\n' "$(basename "${BASH_SOURCE[0]}" _test.sh)"
