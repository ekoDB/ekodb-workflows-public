#!/usr/bin/env bash
# github-release.sh -- publish the GitHub Release for TAG from the changelog.
#
# The notes are the `## [X.Y.Z]` block of the changelog at the tagged commit,
# followed by GitHub's generated notes. Idempotent: an existing Release is
# reported, its latest policy is (re)applied, and the script exits 0, so a
# half-finished release is completed by re-running.
# Which Release is "latest" follows GitHub's date-and-version rule: the new
# Release is set to `make_latest=legacy` through the API right after it is
# created (the API defaults to marking every new Release latest, and `gh
# release create` cannot express `legacy`), so a lower version cut after a
# higher one is not force-marked latest.
# Refuses a pre-release tag (skip, exit 0: only releases are published) and a
# missing or empty block (exit 1: a release carries its notes or is not cut).
#
# Inputs (env): TAG (vX.Y.Z), CHANGELOG (default CHANGELOG.md), GH_TOKEN,
#   REPO (default GITHUB_REPOSITORY).
#   GITHUB_RELEASE_GH overrides the gh binary for tests.
set -uo pipefail

GH="${GITHUB_RELEASE_GH:-gh}"
TAG="${TAG:?github-release: TAG is required (vX.Y.Z)}"
CHANGELOG="${CHANGELOG:-CHANGELOG.md}"
REPO="${REPO:-${GITHUB_REPOSITORY:-}}"
[ -n "$REPO" ] || { echo "github-release: REPO (or GITHUB_REPOSITORY) is unset; refusing before anything is published." >&2; exit 1; }

if ! printf '%s' "$TAG" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$'; then
  echo "github-release: tag '${TAG}' is not v<semver>; refusing." >&2
  exit 1
fi
VERSION="${TAG#v}"
case "$VERSION" in
  *-*) echo "github-release: ${TAG} is a pre-release; only releases are published. Skipping."; exit 0 ;;
esac

# make "latest" GitHub's date-and-version call for TAG; a failure is reported
# with the command that finishes it by hand, and never fails the run: the
# Release exists either way. $1 says what a failure means: "created" (the
# API default has just marked it latest) or "existing" (an earlier run may
# already have set the policy; only this re-application failed).
set_latest_policy() {
  local id state
  id="$("$GH" api "repos/${REPO}/releases/tags/${TAG}" --jq .id 2>/dev/null)" || id=""
  if [ -z "$id" ] || ! "$GH" api -X PATCH "repos/${REPO}/releases/${id}" -f make_latest=legacy >/dev/null 2>&1; then
    case "$1" in
      created) state="GitHub's default has marked it latest regardless of version" ;;
      *)       state="the policy may not be in force" ;;
    esac
    echo "::warning::github-release: could not set make_latest=legacy on ${TAG} -- ${state}. Finish by hand: gh api -X PATCH repos/${REPO}/releases/${id:-<id>} -f make_latest=legacy"
    return 1
  fi
}

if "$GH" release view "$TAG" >/dev/null 2>&1; then
  echo "github-release: release ${TAG} already exists; nothing to publish."
  set_latest_policy existing || true
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

rule=" (GitHub's date-and-version rule)"
set_latest_policy created || rule=""

actual="$("$GH" release view --json tagName --jq .tagName 2>/dev/null || true)"
echo "github-release: published ${TAG}; the repository reports ${actual:-none} as its latest release${rule}."
