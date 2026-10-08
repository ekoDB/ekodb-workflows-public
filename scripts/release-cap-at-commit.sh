#!/usr/bin/env bash
# Find a release cap at COMMIT, or at the second parent when COMMIT is a
# two-parent merge. The subject parser remains the sole authority for the cap
# shape. The caller tags COMMIT, the code that actually reached the branch.
# Prints version=X.Y.Z and cap_sha=<sha> when found; nothing otherwise.
set -uo pipefail

COMMIT="${COMMIT:?release-cap-at-commit: COMMIT is required}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! parents="$(git rev-list --parents -n 1 "$COMMIT")"; then
  echo "release-cap-at-commit: cannot read ${COMMIT}" >&2
  exit 1
fi
read -r -a commits <<< "$parents"

check_cap() {
  local sha="$1" subject out
  if ! subject="$(git log -1 --format=%s "$sha")"; then
    echo "release-cap-at-commit: cannot read subject at ${sha}" >&2
    return 1
  fi
  out="$(SUBJECT="$subject" bash "${HERE}/release-cap-detect.sh")" || return 1
  if [ -n "$out" ]; then
    printf '%s\ncap_sha=%s\n' "$out" "$sha"
  fi
}

out="$(check_cap "${commits[0]}")" || exit 1
if [ -n "$out" ]; then
  printf '%s\n' "$out"
elif [ "${#commits[@]}" -eq 3 ]; then
  check_cap "${commits[2]}"
fi
