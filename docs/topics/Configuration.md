# Configuration

## The layers

A run resolves its configuration from four layers, each merged over the one before:

1. the defaults in [`actions/plan/defaults.yml`](https://github.com/davils-com/kotlin-workflow/blob/main/actions/plan/defaults.yml),
2. the project's file, `.github/kotlin-workflow.yml` unless the `config-file` input names another,
3. the `config` input of the caller, a YAML string,
4. `policy.<event>.overrides` of the event that started the run.

Maps merge key by key. Lists and single values replace what was there.

The defaults file is the schema as well. A key that is not in it, or a value of another type,
stops the plan job and names the path, such as `check.taskz: unknown option`. Every problem of a
configuration is reported at once. A number is accepted where a string is expected, so
`version: 25` and `version: "25"` are the same. Two maps are free-form: `env`, and
`schedule.crons`.

The defaults file carries a comment for every key that needs one. It is the reference.

## Events

The plan turns the GitHub event into one of eight names, and each has a policy:

| Name | When |
|---|---|
| `pull-request` | a pull request |
| `push-develop` | a push to `branches.develop` |
| `push-main` | a push to `branches.main` |
| `push-other` | a push to any other branch |
| `tag` | a pushed tag |
| `schedule` | a cron of the caller |
| `merge-group` | a merge queue |
| `workflow-dispatch` | a manual run |

```yaml
policy:
  push-develop:
    stages: [check, snapshot, security]
    os: [ubuntu-latest, windows-latest]
    overrides:
      check:
        reproducible: { enabled: true }
```

- `stages` lists what runs: `dependencies`, `check`, `security`, `snapshot`, `release`, `docs`,
  `benchmark`.
- `os` lists the runners of the check stage. The first is the primary leg: it alone runs
  `check.primary-tasks`, sends SARIF to code scanning and writes the summary. An entry is a
  runner label, or `{name: ..., runs-on: [...]}` for a set of labels.
- `overrides` changes any other key for this event. It cannot change `policy` or `version`.

The triggers themselves stay in the workflow file of the project. GitHub reads `on:` before any
job runs, so no configuration can change it.

## What can skip a run

- **Ignored paths.** When a push, a pull request or a merge group changes nothing but paths that
  match `paths.ignore`, every stage except `docs` is skipped. The check of the pipeline still
  reports success, so a required check never waits. A tag, a schedule and a manual run are never
  filtered.
- **Drafts.** `pull-request.drafts: false` skips every stage while a pull request is a draft.
- **The `stages` input.** A manual run can name its stages; that replaces the policy and the path
  filter.

## Schedules

A workflow file may carry several crons. `schedule.crons` maps a cron to its stages; a cron that
is not listed starts `policy.schedule.stages`.

```yaml
schedule:
  crons:
    "0 4 * * 0": [benchmark]
```

## The version of a release

For a tag the plan takes the version from the tag name, without `release.tag.prefix` and, with
`release.tag.allow-v`, without a leading `v`. It hands that version to every Gradle invocation in
the environment variable `release.version-env`, `CI_COMMIT_TAG` by default, which is where a
Kreate project that sets `version { environment = "CI_COMMIT_TAG" }` reads it.

## Native libraries

`native.runners` lists a runner for every platform of a JNI library. The stages of
`native.stages` then build the natives there first and publish them with the library; see
[Native libraries](Native-Libraries.md). Each entry is `{platform, runs-on}`, and the plan
refuses an unknown platform, a platform listed twice and an entry without a runner.

## Calling one stage

Every stage workflow takes the same `config-file` and `config` inputs and plans for itself when
`pipeline.yml` did not:

```yaml
jobs:
  check:
    uses: davils-com/kotlin-workflow/.github/workflows/check.yml@COMMIT # v1.0.0
    permissions:
      contents: read
      security-events: write
      pull-requests: read
    with:
      config: |
        check:
          tasks: [build]
```
