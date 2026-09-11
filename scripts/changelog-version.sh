#!/usr/bin/env bash
# changelog-version.sh -- the newest released version in a Keep-a-Changelog
# file: the first `## [X.Y.Z]` heading, skipping `## [Unreleased]`.
#
# For a caller with no manifest (a Go module is versioned by its tags alone),
# this is the second source the tag gate compares the commit subject against.
#
# Input (env): CHANGELOG (default CHANGELOG.md). Exit 0 with the version on
# stdout; exit 1 with a reason when there is no file or no released heading.
set -uo pipefail

CHANGELOG="${CHANGELOG:-CHANGELOG.md}"
[ -f "$CHANGELOG" ] || { echo "changelog-version: no changelog at '${CHANGELOG}'." >&2; exit 1; }

version="$(grep -m1 -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' "$CHANGELOG" | tr -d '#[] ')"
[ -n "$version" ] || { echo "changelog-version: ${CHANGELOG} has no released '## [X.Y.Z]' heading." >&2; exit 1; }
printf '%s\n' "$version"
