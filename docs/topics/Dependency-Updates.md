# Dependency updates

## Dependabot

[`templates/dependabot.yml`](https://github.com/davils-com/kotlin-workflow/blob/main/templates/dependabot.yml)
watches two things: the Gradle build and the GitHub Actions of the workflows, which includes the
pin of kotlin-workflow itself.

The versions of a build are expected in one place, the version catalog
`gradle/libs.versions.toml`. One Dependabot entry for the directory `/` is then enough, also for
a composite build whose included builds read the same catalog. An entry per included build would
open every update once more for each of them.

Minor and patch updates arrive as one pull request per ecosystem, majors one by one, and a new
version waits a few days before it is proposed.

## Why a Dependabot pull request is red

Dependabot changes versions and nothing else. A build that locks its dependencies, or verifies
them against `gradle/verification-metadata.xml`, refuses the new versions until the lock files
and the checksums are regenerated. Without help that is a checkout and two Gradle commands by
hand for every update.

## The dependencies stage

The stage `dependencies` does that work. It runs for a pull request that

- was opened by Dependabot,
- comes from a branch of the repository itself, and
- changes the version catalog, or one of `dependencies.triggers`.

For every other pull request it is skipped.

1. **Regenerate.** A job without any permission to write and without a secret runs
   `dependencies.lock.invocations` and then Gradle with `--write-verification-metadata` over
   `dependencies.verification.tasks`. What changed in the files of `dependencies.paths` becomes a
   patch. Anything else the build touched is left out.
2. **Apply.** A second job, which runs no code of the project, checks the patch: it may touch
   nothing but the allowed paths, and it may only change or add plain files. Then it commits the
   patch to the pull request.
3. **Start again.** A push made by a workflow starts no run, so the new commit would have no
   check. The job starts the pipeline on the branch itself, and that run carries the check of the
   pull request. The run that made the commit skips its own check, because it is about a commit
   that is no longer the head.

When there is nothing to regenerate, the stage commits nothing and the run goes on to its check.

## Configuration

```yaml
dependencies:
  catalog: gradle/libs.versions.toml
  lock:
    invocations:
      - [kreateResolveAndLockAll, --write-locks]
  verification:
    tasks: [check]
```

| Key | Default | Meaning |
|---|---|---|
| `catalog` | `gradle/libs.versions.toml` | the version catalog whose change starts the stage |
| `triggers` | the Gradle wrapper properties | further files whose change starts it |
| `lock.invocations` | none | Gradle invocations that rewrite the lock files |
| `verification.enabled` | `true` | rewrites the verification metadata when the project has the file |
| `verification.tasks` | `check` | the tasks that resolve everything the build verifies |
| `verification.checksums` | `sha256` | what Gradle records |
| `paths` | lock files and the verification metadata | the only files the stage may change |
| `commit-message` | `build(deps): record locks and checksums` | the message of the commit |
| `rerun` | `pipeline.yml` | the workflow file to start on the new commit |

The workflow file named by `rerun` needs a `workflow_dispatch` trigger, which the template has.

## What to review

The commit the stage adds is generated, but it is not a formality. Read the diff of the
verification metadata: a new version adds entries, and nothing else should change. A checksum
that changes for a version that did not is a tampered artifact.

## Permissions

The stage needs `contents: write` to commit and `actions: write` to start the pipeline. A
Dependabot run gets a read-only token unless the workflow asks for more, which the template does.
Secrets of the repository do not reach a Dependabot run, and the stage needs none.

To switch it off, remove it from the policy:

```yaml
policy:
  pull-request:
    stages: [check, security]
```
