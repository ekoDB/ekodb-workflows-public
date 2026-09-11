#!/usr/bin/env bash
# release-cap-detect.sh -- is this commit a release cap, and what version does
# it claim? Prints `version=X.Y.Z` for a subject that is exactly
# `chore(<scope>): vX.Y.Z` (scope optional, plain version), nothing otherwise.
#
# The version here comes from the commit SUBJECT, written by whoever cut the
# cap. The tag gate compares it against the manifest (or the changelog heading)
# written by the bump, so the two agree only when the cap was applied
# coherently. Reading the manifest here too would make that comparison a
# tautology.
#
# Only the first line is examined: a cap-shaped line inside a body (a squash, a
# revert quoting the cap) must not tag. Anchored at both ends: a subject that
# mentions a version is not a cap. Plain X.Y.Z only: a pre-release suffix never
# tags.
#
# Input (env): SUBJECT. Exit 0 always -- "not a cap" is a normal answer.
set -uo pipefail

SUBJECT="${SUBJECT:-}"
SUBJECT="$(printf '%s' "$SUBJECT" | head -1)"

version="$(printf '%s' "$SUBJECT" \
  | sed -nE 's/^chore(\([^)]*\))?: v([0-9]+\.[0-9]+\.[0-9]+)$/\2/p')"
[ -n "$version" ] && printf 'version=%s\n' "$version"
exit 0
