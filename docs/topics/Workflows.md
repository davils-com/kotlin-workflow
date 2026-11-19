# Workflows

Every workflow has `permissions: {}` at the top and grants each job what it needs. A caller has
to grant at least the permissions listed here, because GitHub checks them for every job a
workflow could run before the first one starts.

## pipeline.yml

Plans, then calls the stages the plan names. `snapshot` and `release` wait for `check` of the
same run, so a commit is verified once. The last job, **Pipeline**, fails when a stage failed or
was cancelled and passes when the rest succeeded or was skipped on purpose. Require that one
check.

Inputs: `config-file`, `config`, `stages`, `dry-run`. Secrets, all optional: `MAVEN_USERNAME`,
`MAVEN_PASSWORD`, `SIGNING_KEY`, `SIGNING_KEY_ID`, `SIGNING_PASSWORD`.

Permissions: `contents: write`, `actions: write`, `security-events: write`, `id-token: write`,
`attestations: write`, `pages: write`, `pull-requests: read`.

## dependencies.yml

Regenerates the lock files and the checksums of a pull request of Dependabot and commits them to
it. See [Dependency updates](Dependency-Updates.md).

Permissions: `contents: write`, `actions: write`, `pull-requests: read`. No secrets.

## check.yml

One job per runner of the matrix:

1. checks out with the configured depth, `0` by default, because Kreate's semantic version check
   and its changelog read tags and history,
2. sets up the JDK, Gradle and the tools of `tools`, and refuses a runner that holds local
   Kreate publications,
3. runs `check.tasks` in one Gradle invocation, with `check.primary-tasks` added on the primary
   leg, then each list of `check.invocations` as an invocation of its own. On Windows Gradle is
   started from PowerShell, so the build sees the environment of Windows itself: Git Bash renames
   variables such as `SystemRoot`, and MSBuild starts no compiler when a build hands on both names,
4. on the primary leg, merges the SARIF files of Detekt and of the assurance gate into one run
   per tool and sends them to code scanning. Code scanning refuses a finding without a location,
   so a finding that names no file, such as one about a dependency, is filed under
   `code-scanning.fallback-location`, the version catalog by default,
5. writes test totals, line coverage and the assurance report to the job summary and keeps the
   report files as an artifact, by default only when the job failed. A job that failed names its
   failed tests as error annotations and in its summary, on every runner, so the reason is on the
   page of the run; `check.summary.failed-tests` limits how many.

`check.reproducible` adds a job that builds the same artifacts twice and compares their
checksums. Each build starts with `check.reproducible.clean-tasks` as a Gradle invocation of
its own, because Gradle does not order a clean before the tasks of an included build and would
delete what it just built.

Permissions: `contents: read`, `security-events: write`, `pull-requests: read`. No secrets.

## security.yml

| Job | Does | Switch |
|---|---|---|
| Assurance and Trivy | `kreateAssurance` and `kreateTrivyScan` through Gradle, SARIF to code scanning | `security.gradle` |
| Repository scan | Trivy over the files of the repository, SARIF to code scanning, fails on `fail-on` and on secrets | `security.repository-scan` |
| SBOM | a CycloneDX SBOM as an artifact | `security.sbom` |
| Dependency review | fails a pull request that adds a vulnerable dependency | `security.dependency-review` |
| Dependency graph | submits the resolved Gradle dependencies, which feeds Dependabot alerts | `security.dependency-submission` |

By default a pull request runs the dependency review only, a push to `develop` the dependency
graph only, and the schedule everything.

Permissions: `contents: write` for the dependency graph, otherwise `read`;
`security-events: write`; `pull-requests: read`. No secrets.

## snapshot.yml

Builds `publish.build-tasks` without any secret, then runs `publish.tasks` one by one with the
repository token, with `KREATE_SNAPSHOT=true` unless `snapshot.kreate-snapshot` is off. The job
runs in the environment `snapshot.environment`; restrict that environment to the development
branch. Uploads never run in parallel and are never cancelled. `snapshot.smoke` builds a
consumer project against the snapshot afterwards. In its arguments `{version}` is the snapshot
version, `{repository}` the snapshots repository and `{releases-repository}` the releases
repository. A snapshot can depend on a released artifact of its own group, such as a develop
build of Kreate on a released kore, so a consumer that filters the group to one repository
lists both:

```kotlin
exclusiveContent {
    forRepositories(maven(snapshots), maven(releases))
    filter { includeGroupAndSubgroups("com.davils") }
}
```

Permissions: `contents: read`, `pull-requests: read`. Secrets: `MAVEN_USERNAME`,
`MAVEN_PASSWORD`.

## release.yml

| Job | Does |
|---|---|
| Gate | The tag is on `release.gate.branch`, equals the version in `release.gate.version-file`, and is no snapshot |
| Preflight | Lists the publications and looks each one up in the releases repository, without credentials |
| Publish | Builds without secrets, uploads the missing publications signed, attests provenance and an SBOM. Runs in `release.environment`, which is the approval gate |
| Smoke | Downloads every file as a consumer, verifies the attestations, optionally builds a consumer project |
| GitHub release | Creates the release with generated notes or with the notes of `kreateChangelogNotes` |

A releases repository refuses to overwrite a file, so an interrupted release cannot simply run
again. The preflight tells three states apart: a publication that is missing is uploaded, one
that is listed in its `maven-metadata.xml` is skipped, and one whose files exist without being
listed stops the job and names the directory to delete.

`release.publications.discovery: auto` asks Gradle for the publications of every project of the
build. A composite build, or a build that needs a fixed order, lists them with `explicit`.

With `dry-run`, the gate takes the declared version and only warns about the branch, the build
runs, and nothing is uploaded, attested or released.

Permissions: `contents: write`, `id-token: write`, `attestations: write`,
`pull-requests: read`. Secrets: `MAVEN_USERNAME`, `MAVEN_PASSWORD`, and the signing secrets
unless `release.sign` is off.

## docs.yml

Builds with Dokka through Gradle (`docs.engine: dokka`) or with Writerside
(`docs.engine: writerside`, `docs.writerside.instance`), and deploys the result to GitHub Pages.

Permissions: `contents: read`, `pages: write`, `id-token: write`, `pull-requests: read`.

## benchmark.yml

Runs `benchmark.tasks`, appends the comparison Kreate writes to the job summary and keeps it as
an artifact.

Permissions: `contents: read`, `pull-requests: read`.
