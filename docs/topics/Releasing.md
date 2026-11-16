# Releasing

Work happens on `develop`; `main` carries releases.

1. Finish the section of the version in `CHANGELOG.md` on `develop`.
2. Merge `develop` into `main`.
3. Push the tag `vX.Y.Z` on `main`.

`self-release.yml` refuses a tag that is not on `main`, creates the GitHub release and moves the
tag `vX` to the new commit.

## What a version means

- **Major**: an option was removed or renamed, a default changed visibly, or a workflow needs a
  permission or a secret it did not need before.
- **Minor**: a new option, stage or workflow.
- **Patch**: a fix, or an update of a pinned action.

## How consumers follow

A consumer pins a commit and names the version in a comment:

```yaml
uses: davils-com/kotlin-workflow/.github/workflows/pipeline.yml@COMMIT # v1.2.0
```

Dependabot's `github-actions` ecosystem reads the tags of this repository and updates both the
commit and the comment. A pin on a commit that carries no tag is moved to the newest commit
instead, so pin releases.

`develop` is never force-pushed: a project may pin one of its commits while it tries a change.
