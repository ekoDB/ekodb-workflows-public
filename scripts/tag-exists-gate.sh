#!/usr/bin/env bash
# tag-exists-gate.sh -- does refs/tags/TAG exist in REPO, according to the API?
#
# The release job runs even when the tag job failed, so a half-finished
# release stays recoverable by re-running. That leaves it not knowing whether
# the tag was pushed; this asks directly and answers in one sentence, so a
# cutter that failed before its push reads as "no tag" rather than as a
# credentials error from `gh release create`.
#
# Inputs (env): TAG (vX.Y.Z), REPO (owner/name; default GITHUB_REPOSITORY).
#   TAG_EXISTS_GATE_GH overrides the gh binary for tests.
# Exit 0 = the API names refs/tags/TAG. Exit 1 otherwise, saying which case.
set -uo pipefail

GH="${TAG_EXISTS_GATE_GH:-gh}"
TAG="${TAG:-}"
REPO="${REPO:-${GITHUB_REPOSITORY:-}}"

[ -n "$TAG" ] || { echo "tag-exists-gate: TAG is required (vX.Y.Z)." >&2; exit 1; }
[ -n "$REPO" ] || { echo "tag-exists-gate: REPO (or GITHUB_REPOSITORY) is unset, so there is no repository to ask about ${TAG}." >&2; exit 1; }
if ! printf '%s' "$TAG" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "tag-exists-gate: tag '${TAG}' is not v<semver>; refusing to ask about it." >&2
  exit 1
fi

if body="$("$GH" api "repos/${REPO}/git/ref/tags/${TAG}" 2>&1)"; then
  if printf '%s' "$body" | grep -q "\"refs/tags/${TAG}\""; then
    echo "tag-exists-gate: ${TAG} exists in ${REPO}."
    exit 0
  fi
  echo "tag-exists-gate: ${REPO} answered for '${TAG}' without naming refs/tags/${TAG} -- the tag that exists is not the one asked about: ${body}" >&2
  exit 1
fi
if printf '%s' "$body" | grep -qi 'not found\|404'; then
  echo "tag-exists-gate: ${TAG} does not exist in ${REPO}. The cutter did not push it, so there is nothing to release -- look at the tag job. The API said: ${body}" >&2
  exit 1
fi
echo "tag-exists-gate: could not determine whether ${TAG} exists in ${REPO} (the API call failed): ${body}" >&2
exit 1
