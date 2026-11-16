# Adoption

## A project that uses Kreate

1. In the Kreate block, publish to `repo.davils.com` with a repository named `Davils`, and read
   the version from `CI_COMMIT_TAG`. The snippet is in [Getting started](Getting-Started.md).
2. Copy [`templates/pipeline.yml`](https://github.com/davils-com/kotlin-workflow/blob/main/templates/pipeline.yml) to
   `.github/workflows/pipeline.yml` and pin a commit of this repository.
3. Copy [`templates/dependabot.yml`](https://github.com/davils-com/kotlin-workflow/blob/main/templates/dependabot.yml) to `.github/dependabot.yml`.
4. In the repository settings:
   - create the environments `snapshot`, restricted to `develop`, and `release`, with required
     reviewers,
   - make `DAVILS_MAVEN_NAME` and `DAVILS_MAVEN_SECRET` available, and the signing secrets
     `SIGNING_KEY`, `SIGNING_KEY_ID`, `SIGNING_PASSWORD` for releases,
   - require the status check **Pipeline / Pipeline**.
5. Delete the workflows this replaces, in the same commit, so that one revert brings them back.
6. Rehearse a release: run the workflow by hand with `stages: release` and `dry-run` ticked.

Kreate 4.2.0 is the first version with the `maven { }` target and the snapshot switch. An older
version can use every stage except `snapshot` and `release`.

## What needs configuration

| The project | Set |
|---|---|
| has native code | `tools.cmake: true` |
| has integration tests | `check.invocations: [[integrationTest]]` |
| wants coverage in the summary | `check.primary-tasks: [koverXmlReport]` |
| is a composite build | task paths of the included builds in `check.tasks` and `publish.tasks`, and `release.publications.discovery: explicit` |
| tags with a prefix | `release.tag.prefix` |
| keeps its version elsewhere | `release.gate.version-file`, `release.gate.version-key` |
| writes its changelog with Kreate | `release.github-release.notes: task` |
| has Dokka or Writerside docs | `docs.engine` |
| locks its dependencies | `dependencies.lock.invocations` |

## Verifying a release afterwards

A release made by these workflows is attested by this repository:

```bash
gh attestation verify ARTIFACT.jar --repo OWNER/PROJECT --signer-repo davils-com/kotlin-workflow
```
