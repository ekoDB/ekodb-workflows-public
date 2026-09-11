#!/usr/bin/env bash
# github-release.sh -- publish the GitHub Release for TAG from the changelog.
#
# The notes are the `## [X.Y.Z]` block of the changelog at the tagged commit,
# followed by GitHub's generated notes. Idempotent: an existing Release is
# reported and exits 0, so a half-finished release is completed by re-running.
# Which Release is "latest" is left to GitHub (by date and version), so a
# lower version cut after a higher one is not force-marked latest.
# Refuses a pre-release tag (skip, exit 0: only releases are published) and a
# missing or empty block (exit 1: a release carries its notes or is not cut).
#
# Inputs (env): TAG (vX.Y.Z), CHANGELOG (default CHANGELOG.md), GH_TOKEN.
#   GITHUB_RELEASE_GH overrides the gh binary for tests.
set -uo pipefail

GH="${GITHUB_RELEASE_GH:-gh}"
TAG="${TAG:?github-release: TAG is required (vX.Y.Z)}"
CHANGELOG="${CHANGELOG:-CHANGELOG.md}"

if ! printf '%s' "$TAG" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$'; then
  echo "github-release: tag '${TAG}' is not v<semver>; refusing." >&2
  exit 1
fi
VERSION="${TAG#v}"
case "$VERSION" in
  *-*) echo "github-release: ${TAG} is a pre-release; only releases are published. Skipping."; exit 0 ;;
esac

if "$GH" release view "$TAG" >/dev/null 2>&1; then
  echo "github-release: release ${TAG} already exists; nothing to do."
  exit 0
fi

[ -f "$CHANGELOG" ] || { echo "github-release: no changelog at '${CHANGELOG}'." >&2; exit 1; }
NOTES="$(mktemp)"
trap 'rm -f "$NOTES"' EXIT
awk -v ver="$VERSION" '
  /^## \[/ { in_block = (index($0, "## [" ver "]") == 1) }
  in_block { print }
' "$CHANGELOG" > "$NOTES"
if ! head -1 "$NOTES" | grep -qF "## [${VERSION}]"; then
  echo "github-release: ${CHANGELOG} has no '## [${VERSION}]' block -- a release must carry its changelog. Refusing." >&2
  exit 1
fi
if [ "$(grep -cv '^[[:space:]]*$' "$NOTES")" -le 1 ]; then
  echo "github-release: the '## [${VERSION}]' block is empty -- refusing to publish a release with no notes." >&2
  exit 1
fi

"$GH" release create "$TAG" --title "$TAG" --notes-file "$NOTES" --generate-notes --verify-tag \
  || { echo "github-release: gh release create failed for ${TAG}." >&2; exit 1; }

actual="$("$GH" release view --json tagName --jq .tagName 2>/dev/null || true)"
if [ "$actual" != "$TAG" ]; then
  echo "::warning::github-release: published ${TAG}, but the repository still reports '${actual:-none}' as its latest release."
fi
echo "github-release: published ${TAG}."
