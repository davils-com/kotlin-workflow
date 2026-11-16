# Cost

Standard runners are free for public repositories. For private ones a macOS minute costs about
ten times a Linux minute and a Windows minute nearly twice, so the defaults lean on Linux.

| What | Default | Change it with |
|---|---|---|
| Runners of the check | Ubuntu only | `policy.<event>.os` |
| Reports, SARIF, coverage | on the first runner only | the order of `os` |
| Checks per commit | one: snapshot and release wait for the check of the same run | - |
| Detekt, API check, coverage | in the same Gradle invocation as the tests | `check.tasks`, `check.primary-tasks` |
| Push and pull request of one branch | the template starts a run on push for `develop`, `main` and tags only | the `on:` block |
| Documentation changes | skip every stage but docs | `paths.ignore` |
| Superseded runs | a new push cancels the run of a pull request, never a publication | the `concurrency` block |
| Gradle cache | written by pushes to `main` and `develop`, read everywhere else, off with secrets | `gradle.cache-write-branches` |
| Configuration cache | on | `gradle.configuration-cache` |
| Report artifacts | only when the job failed, kept 7 days | `check.reports.upload`, `retention.reports` |
| Full security scan | weekly | the cron of the caller, `policy.schedule` |
| Pull request security | dependency review only, no JDK | `policy.pull-request.overrides` |
| Dependabot repairs | only for a Dependabot pull request that changes the version catalog | `dependencies.catalog`, `dependencies.triggers` |
| Time limit | 45 minutes for check and release, less elsewhere | `timeout` |

The plan job is the only fixed cost of a run: a checkout and two scripts on Linux.

A sensible widening for a library that ships native code:

```yaml
policy:
  push-develop: { os: [ubuntu-latest, windows-latest] }
  push-main: { os: [ubuntu-latest, windows-latest] }
  tag: { os: [ubuntu-latest, windows-latest] }
```

Pull requests then stay on Linux, and a platform problem shows on `develop` before a release.

`macos-latest` is a runner like any other and can be added to a list. Think twice before a stage
that publishes depends on it: an account may run only a few macOS jobs at a time, a job that waits
for a runner has no time limit, since `timeout` counts from its start, and while it waits the
snapshot or the release behind it waits too, as does every later run of the branch.
