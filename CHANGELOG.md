# Changelog

All notable changes to ekodb-workflows-public are documented here. The format
is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and the
version lives in `version.json`.

## [Unreleased]

### Added

- **`auto-tag.yml`, a reusable workflow that turns a version cap merged to the default branch into a tag and a GitHub Release.** A commit whose subject is exactly `chore(<scope>): vX.Y.Z` is detected, asserted to be on the default branch, gated (plain semver; the subject's version equals the manifest's or the changelog heading's; a dated `## [X.Y.Z]` block with content; the tag absent locally and on origin, failing closed), tagged with `github.token`, and its Release published from the changelog block, idempotently. An optional `post-tag-command` runs after the Release. Inputs `version-command`, `changelog`, `post-tag-command`, `default-branch`; outputs `version` and `tag` from `detect`, empty on a non-cap merge. The scripts under `scripts/`, each with a test beside it, a public-hygiene allow-list test, and a wiring test over the workflow and this repository's own caller.
