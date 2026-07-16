# Release Process

This repository publishes immutable semantic versions of a CircleCI registry orb, such as `2.0.0`. Git tags use the corresponding `v2.0.0` form and trigger the existing Orb Tools production publishing workflow.

## Requirements

The local maintenance scripts require `curl`, `git`, `gh`, and Ruby. Authenticate the GitHub CLI before using them:

```bash
gh auth login
gh auth status
```

Scripts that create commits use signed commits and verify the signature before pushing. Run the bump PR and release helpers from a clean working tree.

## Release labels

Every PR intended for a release must have one of these labels:

- `semver-patch`: requests the next patch release
- `semver-minor`: requests the next minor release
- `semver-major`: requests the next major release

If a release includes multiple merged PRs, the highest requested version change wins. An explicit tag can also be supplied to the release script.

## Bump pinned library versions

Use `scripts/create-library-version-bump-pr.sh` for the normal maintainer workflow. It discovers available updates and handles the branch, signed commit, push, labels, and PR.

Preview all currently available library updates:

```bash
scripts/create-library-version-bump-pr.sh --dry-run
```

Create one PR containing every available update:

```bash
scripts/create-library-version-bump-pr.sh
```

The script reads the official package sources for .NET, Java, JavaScript, Python, Python coverage, Ruby, and Go/Orchestrion. If at least one pinned default is outdated, it updates `src/commands/autoinstrument.yml` and `README.md`, creates and verifies a signed commit, pushes the branch, and opens a PR. The PR lists exactly which languages changed so release notes remain relevant to users of those languages.

The PR receives:

- `library-version-bump`
- `semver-patch` when every update is a patch
- `semver-minor` when at least one library changes its major or minor version

Use `scripts/bump-library-versions.sh` only as the lower-level manual tool for targeted changes or testing. It accepts explicit versions and updates the orb source and README without querying package sources, creating a branch or commit, pushing, or opening a PR.

```bash
scripts/bump-library-versions.sh --java 1.65.0 --js 6.3.1
scripts/bump-library-versions.sh --go v1.12.0
```

Review and merge the resulting changes normally.

## Release the orb

Preview the next release first:

```bash
scripts/release-orb.sh --dry-run
```

The script fetches `main` and release tags, finds merged PRs since the latest immutable release, reads their `semver-patch`, `semver-minor`, and `semver-major` labels, and selects the highest release level. It verifies the release commit's signature and creates only the immutable `vX.Y.Z` tag. It never creates or moves a `v2` Git branch; CircleCI resolves `@2` through the orb registry after the tag-triggered Orb Tools workflow publishes the production version.

Publish the inferred release:

```bash
scripts/release-orb.sh
```

Release a specific commit on `main`:

```bash
scripts/release-orb.sh --sha abc1234 --dry-run
scripts/release-orb.sh --sha abc1234
```

Choose the tag explicitly:

```bash
scripts/release-orb.sh --tag v2.0.0 --dry-run
scripts/release-orb.sh --tag v2.0.0
```

If the requested tag is lower than the merged PR labels imply, the script fails. To publish that tag intentionally, pass `--allow-version-mismatch` with `--tag`.

After the tag is pushed, the CircleCI workflow tests and publishes the production orb version. The GitHub release workflow creates release notes from the merged PRs, including the affected-language details from library bump PRs.
