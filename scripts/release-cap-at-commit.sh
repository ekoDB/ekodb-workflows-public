#!/usr/bin/env bash
# Find a release cap at COMMIT or through at most 32 two-parent merge wrappers.
# Every wrapper must have the same tree as its second parent: additional content
# requires a new cap. Never walk ordinary commits or search earlier history.
# Prints version=X.Y.Z and cap_sha=<sha>; the caller still tags COMMIT.
set -uo pipefail

COMMIT="${COMMIT:?release-cap-at-commit: COMMIT is required}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
current="$COMMIT"
wrappers=0

while :; do
  if ! object="$(git cat-file -p "$current")"; then
    echo "release-cap-at-commit: cannot read ${current}; fetch complete ancestry." >&2
    exit 1
  fi
  if ! subject="$(git log -1 --format=%s "$current")"; then
    echo "release-cap-at-commit: cannot read subject at ${current}." >&2
    exit 1
  fi
  out="$(SUBJECT="$subject" bash "${HERE}/release-cap-detect.sh")" || exit 1
  if [ -n "$out" ]; then
    printf '%s\ncap_sha=%s\n' "$out" "$current"
    exit 0
  fi

  # Raw headers preserve parent IDs at shallow boundaries; rev-list hides them
  # and would silently classify incomplete ancestry as an ordinary root commit.
  parents="$(printf '%s\n' "$object" | sed -n '/^$/q; s/^parent //p')"
  read -r -a commits <<< "$(printf '%s' "$parents" | tr '\n' ' ')"
  [ "${#commits[@]}" -eq 2 ] || exit 0
  if [ "$wrappers" -ge 32 ]; then
    echo "release-cap-at-commit: more than 32 merge wrappers; refusing to guess." >&2
    exit 1
  fi
  next="${commits[1]}"
  if ! tree="$(git rev-parse "$current^{tree}")" || ! next_tree="$(git rev-parse "$next^{tree}")"; then
    echo "release-cap-at-commit: incomplete merge ancestry; fetch complete history." >&2
    exit 1
  fi
  [ "$tree" = "$next_tree" ] || exit 0
  current="$next"
  wrappers=$((wrappers + 1))
done
