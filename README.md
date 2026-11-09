# ekodb-workflows-public

A reusable GitHub Actions workflow for ekoDB's public repositories: when a
version cap merges to the default branch, it cuts the tag and publishes the
GitHub Release. It runs with `github.token` only and shares nothing.

It also carries `prune-pr-caches.yml`, described under
[Deleting a closed pull request's caches](#deleting-a-closed-pull-requests-caches).

## What a cap is

A commit whose subject is exactly `chore(<scope>): vX.Y.Z` (scope optional,
plain version, no pre-release suffix), containing the changelog collapse of
`## [Unreleased]` into `## [X.Y.Z] - YYYY-MM-DD` and the version bump. Any
other merge is a green no-op that says so in the run summary.

The cap must reach the default branch with its subject intact, either as the
tip of the push (rebase or fast-forward) or through at most 32 two-parent merge
wrappers. Each wrapper must have the same complete file tree as its second
parent. This includes a cap PR merged into a feature PR that is then merged
into the default branch. The tag always points to the pushed default-branch
commit. Detection fetches complete ancestry and fails if ancestry is missing
or the wrapper limit is exceeded.

A changed-tree wrapper, a squash that changes the cap subject, a cap behind an
ordinary commit, or an octopus merge is a green no-op. Detection never searches
arbitrary earlier history for an old cap. Content added above a cap needs a new
cap before release.

## Calling it

With a manifest (the version is cross-checked against it):

```yaml
name: release
on:
  push:
    branches: [main]
permissions:
  contents: write
jobs:
  auto-tag:
    uses: ekoDB/ekodb-workflows-public/.github/workflows/auto-tag.yml@main
    with:
      version-command: grep -m1 '^version' path/to/Cargo.toml | cut -d'"' -f2
      changelog: path/to/CHANGELOG.md
```

Without a manifest (a Go module is versioned by its tags; the newest
changelog heading is the second source), with a command to run afterwards:

```yaml
    uses: ekoDB/ekodb-workflows-public/.github/workflows/auto-tag.yml@main
    with:
      post-tag-command: make index-release VERSION="$TAG"
```

Inputs: `version-command`, `changelog` (default `CHANGELOG.md`),
`post-tag-command` (runs with `TAG` and `VERSION` in the environment),
`default-branch` (default `main`; pass `master` where that is the default, and
trigger the caller on that branch too). Outputs: `version` and `tag`, empty
when the commit was not a cap, so a later job in the caller can gate on
`needs.auto-tag.outputs.tag != ''`. The caller must declare
`permissions: contents: write`.

## Deleting a closed pull request's caches

`prune-pr-caches.yml` deletes the Actions caches of a pull request when it
closes. Only runs of that pull request can restore them, so afterwards they
only take up the repository's cache storage until retention expires them.
Default-branch caches and those of other pull requests are never touched.

```yaml
name: prune-pr-caches
on:
  pull_request_target:
    types: [closed]
permissions: {}
jobs:
  prune:
    permissions:
      actions: write
      contents: read
    uses: ekoDB/ekodb-workflows-public/.github/workflows/prune-pr-caches.yml@main
    with:
      pr-number: ${{ github.event.pull_request.number }}
```

`pull_request_target` is what lets a Dependabot-authored pull request delete
its caches. The job runs only this repository's script and never checks out
the pull request's code.

## What it refuses, and what each means

| Message | Meaning |
| --- | --- |
| `not a plain X.Y.Z release version` | the manifest or changelog version carries a pre-release suffix (a pre-release in the SUBJECT never reaches this: it is not a cap, and the run is a green no-op) |
| `the commit subject names vA but the manifest or changelog says B` | the cap was not applied coherently; fix the manifest or the subject and cap again |
| `notes are still under '## [Unreleased]'` | the cap did not collapse the block |
| `no date in that shape` | the heading is not `## [X.Y.Z] - YYYY-MM-DD` as the bump writes it (a link or another date form is not accepted) |
| `block is empty` | a release carries its notes or is not cut |
| `tag ... already exists` | a released version is immutable; release the next version |
| `could not check origin ... failing closed` | the remote could not be asked; nothing is tagged on a guess |
| `does not exist in <repo>` (release job) | the tag job did not push; look there, not here |

A tag that was pushed but whose Release failed to publish is recovered by
re-running the workflow: the tag step refuses (the tag exists) and the release
step, which runs on `!cancelled()`, publishes it.

## Versioning this workflow

Callers pin `@main`, the way every caller in the organization pins its release
workflow, so a change merged here reaches every caller on its next cap. Each
release of this repository is a `chore(*): vX.Y.Z` cap tagged by this workflow
itself; the tags are the record of what changed when, and nothing pins them.

## Developing

`make bootstrap` once (PyYAML and ruff into `.venv`), then `make test` (every
`scripts/*_test.sh` and `*_test.py`) and `make lint` (shellcheck, actionlint,
ruff). Every script has a test beside it that drives every refusal, and
`scripts/public-hygiene_test.sh` fails if any `ekoDB/<name>` token in the
tree names a repository that is not public.
