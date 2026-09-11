#!/usr/bin/env bash
# release-tag-gate.sh -- would cutting tag vVERSION lie? Every check is one way
# it could:
#   * VERSION must be plain X.Y.Z; pre-releases are never tagged.
#   * SUBJECT_VERSION (from the cap commit's subject) must equal VERSION (from
#     the manifest, or the changelog heading for a caller with no manifest).
#     Two sources written by different steps of the cap; they disagree exactly
#     when something is wrong.
#   * The changelog must carry a dated `## [VERSION]` block with content.
#   * The tag must not exist locally or on origin. A released version maps to
#     one commit forever; a bad release means the next version, never a moved
#     tag. If origin cannot be asked, this FAILS CLOSED.
#
# Inputs (env): VERSION, SUBJECT_VERSION, CHANGELOG (default CHANGELOG.md).
#   RELEASE_TAG_GATE_LSREMOTE overrides the ls-remote command for tests.
# Exit 0 = safe to tag. Exit 1 with the reason otherwise. Creates nothing.
set -uo pipefail

VERSION="${VERSION:?release-tag-gate: VERSION is required}"
SUBJECT_VERSION="${SUBJECT_VERSION:?release-tag-gate: SUBJECT_VERSION is required}"
CHANGELOG="${CHANGELOG:-CHANGELOG.md}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "release-tag-gate: '${VERSION}' is not a plain X.Y.Z release version -- pre-releases are never tagged." >&2
  exit 1
fi
if [ "$SUBJECT_VERSION" != "$VERSION" ]; then
  echo "release-tag-gate: the commit subject names v${SUBJECT_VERSION} but the manifest or changelog says ${VERSION} -- the cap was not applied coherently; refusing." >&2
  exit 1
fi
if ! VERSION="$VERSION" CHANGELOG="$CHANGELOG" bash "${HERE}/changelog-block-gate.sh"; then
  echo "release-tag-gate: refusing to tag ${VERSION} -- the changelog block is not in place (see above)." >&2
  exit 1
fi
block="$(awk -v ver="$VERSION" '
  /^## \[/ { in_block = (index($0, "## [" ver "]") == 1) }
  in_block { print }
' "$CHANGELOG")"
if [ "$(printf '%s\n' "$block" | grep -cv '^[[:space:]]*$')" -le 1 ]; then
  echo "release-tag-gate: the '## [${VERSION}]' block is empty -- refusing to tag a release with no notes." >&2
  exit 1
fi

TAG="v${VERSION}"
if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null 2>&1; then
  echo "release-tag-gate: tag ${TAG} already exists locally -- a released version is immutable; release the next version instead." >&2
  exit 1
fi
lsremote() {
  if [ -n "${RELEASE_TAG_GATE_LSREMOTE:-}" ]; then eval "${RELEASE_TAG_GATE_LSREMOTE}"
  else git ls-remote --tags origin "refs/tags/${TAG}"; fi
}
if ! remote_tags="$(lsremote)"; then
  echo "release-tag-gate: could not check origin for tag ${TAG} -- failing closed; fix the remote or auth and retry." >&2
  exit 1
fi
if [ -n "$remote_tags" ]; then
  echo "release-tag-gate: tag ${TAG} already exists on origin -- a released version is immutable; release the next version instead." >&2
  exit 1
fi
echo "release-tag-gate: ${TAG} is safe to cut."
