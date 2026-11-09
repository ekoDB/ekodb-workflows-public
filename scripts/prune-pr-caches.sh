#!/usr/bin/env bash
# prune-pr-caches.sh <owner/repo> <pr-number>
#
# Deletes the GitHub Actions caches of one pull request: those whose ref is
# refs/pull/<n>/merge or refs/pull/<n>/head. Only runs of that pull request can
# restore them, so once it closes they only occupy the repository's cache
# storage until retention expires them. Default-branch caches and those of
# other pull requests are never selected.
#
# Exit status: 0 when nothing is left to delete, 1 when the caches could not be
# listed or one could not be deleted, 2 when the arguments are refused. No
# caches and "could not list" are different outcomes and say so.
set -uo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: prune-pr-caches.sh <owner/repo> <pr-number>" >&2
  exit 2
fi
repo="$1"
pr="$2"

# The number is written into a jq filter below, so it is validated before use.
if ! [[ "$pr" =~ ^[1-9][0-9]*$ ]]; then
  echo "::error::prune-pr-caches: '${pr}' is not a pull request number" >&2
  exit 2
fi
if ! [[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] \
  || [[ "${repo%%/*}" =~ ^\.{1,2}$ ]] || [[ "${repo##*/}" =~ ^\.{1,2}$ ]]; then
  echo "::error::prune-pr-caches: '${repo}' is not an owner/repo name" >&2
  exit 2
fi

filter=".actions_caches[] | select(.ref == \"refs/pull/${pr}/merge\" or .ref == \"refs/pull/${pr}/head\") | .id"

if ! ids="$(gh api --paginate "repos/${repo}/actions/caches?per_page=100" --jq "$filter")"; then
  echo "::error::prune-pr-caches: could not list the caches of ${repo}" >&2
  exit 1
fi

if [ -z "$ids" ]; then
  echo "pull request #${pr} has no caches in ${repo}"
  exit 0
fi

deleted=0
gone=0
failed=0
while IFS= read -r id; do
  if err="$(gh api -X DELETE "repos/${repo}/actions/caches/${id}" 2>&1 >/dev/null)"; then
    deleted=$((deleted + 1))
  elif [[ "$err" == *"HTTP 404"* ]]; then
    gone=$((gone + 1))
  else
    failed=$((failed + 1))
    echo "::error::prune-pr-caches: could not delete cache ${id}: ${err}" >&2
  fi
done <<< "$ids"

echo "pull request #${pr} in ${repo}: deleted ${deleted}, ${gone} already gone, ${failed} failed"
[ "$failed" -eq 0 ]
