#!/usr/bin/env bash
# changelog-block-gate.sh -- the release commit must have collapsed
# `[Unreleased]` into a dated `## [VERSION] - YYYY-MM-DD` block before a tag
# is cut, or the release ships without notes.
#
# Inputs (env): VERSION (X.Y.Z), CHANGELOG (default CHANGELOG.md).
# Exit 0 when the dated block exists. Exit 1 otherwise, naming which of three
# states the file is in: a heading with no date, notes still under
# [Unreleased], or no block at all.
set -uo pipefail

VERSION="${VERSION:?changelog-block-gate: VERSION is required}"
CHANGELOG="${CHANGELOG:-CHANGELOG.md}"

[ -f "$CHANGELOG" ] || { echo "changelog-block-gate: no changelog at '${CHANGELOG}'." >&2; exit 1; }
case "$VERSION" in
  *-*) echo "changelog-block-gate: '${VERSION}' is a pre-release; no block is expected and none is tagged." >&2; exit 1 ;;
esac

ver_re="$(printf '%s' "$VERSION" | sed 's/\./\\./g')"
if grep -Eq "^## \[${ver_re}\] - [0-9]{4}-[0-9]{2}-[0-9]{2}" "$CHANGELOG"; then
  exit 0
fi
if grep -Eq "^## \[${ver_re}\]" "$CHANGELOG"; then
  echo "changelog-block-gate: '## [${VERSION}]' exists in ${CHANGELOG} but carries no date -- the heading was written by hand rather than by the bump." >&2
  exit 1
fi
newest="$(grep -m1 -E '^## \[' "$CHANGELOG" || true)"
if printf '%s' "$newest" | grep -q '^## \[Unreleased\]'; then
  echo "changelog-block-gate: ${CHANGELOG} has no '## [${VERSION}]' block; its notes are still under '## [Unreleased]'. Collapse it in the cap commit." >&2
else
  echo "changelog-block-gate: ${CHANGELOG} has no '## [${VERSION}]' block. Newest heading: ${newest:-<none>}" >&2
fi
exit 1
