# kotlin-workflow

Reusable GitHub Actions workflows for the Kotlin projects of Davils that build with
[Kreate](https://github.com/davils-com/kreate): checks, security scans, snapshots and releases to
`repo.davils.com`, documentation and benchmarks.

One workflow, `pipeline.yml`, decides from the event what a run does. A pull request is checked,
a push to `develop` is checked and published as a snapshot, a tag is checked and released, a
schedule scans for vulnerabilities. Every part can be switched off or changed, down to the task a
stage runs and the runner it runs on.

## Quick start

Copy [`templates/pipeline.yml`](templates/pipeline.yml) to `.github/workflows/pipeline.yml` of
your project. The part that matters:

```yaml
jobs:
  pipeline:
    uses: davils-com/kotlin-workflow/.github/workflows/pipeline.yml@COMMIT # v1.0.0
    permissions:
      contents: write
      actions: write
      security-events: write
      id-token: write
      attestations: write
      pages: write
      pull-requests: read
    secrets:
      MAVEN_USERNAME: ${{ secrets.DAVILS_MAVEN_NAME }}
      MAVEN_PASSWORD: ${{ secrets.DAVILS_MAVEN_SECRET }}
      SIGNING_KEY: ${{ secrets.SIGNING_KEY }}
      SIGNING_KEY_ID: ${{ secrets.SIGNING_KEY_ID }}
      SIGNING_PASSWORD: ${{ secrets.SIGNING_PASSWORD }}
```

Then require the status check **Pipeline / Pipeline** on your protected branches. That is all a
project needs whose Kreate block publishes to `repo.davils.com`:

```kotlin
kreate {
    project {
        version { environment = "CI_COMMIT_TAG" }

        publish {
            enabled = true
            repositories {
                maven {
                    name = "Davils"
                    releases = "https://repo.davils.com/releases"
                    snapshots = "https://repo.davils.com/snapshots"
                    usernameEnv = "DAVILS_MAVEN_NAME"
                    passwordEnv = "DAVILS_MAVEN_SECRET"
                    signPublications = true
                }
            }
        }
    }
}
```

Anything else goes into `.github/kotlin-workflow.yml`, see
[`templates/kotlin-workflow.yml`](templates/kotlin-workflow.yml):

```yaml
version: 1

tools:
  cmake: true

check:
  primary-tasks: [koverXmlReport]

policy:
  push-develop:
    os: [ubuntu-latest, macos-latest, windows-latest]
```

## What runs when

| Event | Stages by default |
|---|---|
| Pull request | check, and a review of the dependencies it changes |
| Pull request of Dependabot | the lock files and checksums are regenerated first |
| Push to `develop` | check, snapshot, dependency graph |
| Push to `main` | check, docs |
| Tag | check, release |
| Schedule | security: assurance, Trivy, repository scan, SBOM |
| Merge queue, manual run | check |

A change that touches nothing but documentation skips every stage and still reports a green
check.

## Workflows

| Workflow | Purpose |
|---|---|
| [`pipeline.yml`](.github/workflows/pipeline.yml) | Plans the run and calls the stages; ends in the one check to require |
| [`dependencies.yml`](.github/workflows/dependencies.yml) | Regenerates lock files and checksums on a pull request of Dependabot and commits them |
| [`check.yml`](.github/workflows/check.yml) | Builds and verifies on a matrix of runners, sends SARIF to code scanning, summarises tests and coverage |
| [`security.yml`](.github/workflows/security.yml) | Kreate's assurance gate and Trivy scans, a repository scan, an SBOM, dependency review, the dependency graph |
| [`snapshot.yml`](.github/workflows/snapshot.yml) | Publishes `<version>-SNAPSHOT` to the snapshots repository |
| [`release.yml`](.github/workflows/release.yml) | Gate, preflight, signed upload, attestations, consumer smoke test, GitHub release |
| [`docs.yml`](.github/workflows/docs.yml) | Dokka or Writerside to GitHub Pages |
| [`benchmark.yml`](.github/workflows/benchmark.yml) | Benchmarks against a baseline |

Every stage can be called on its own with the same configuration.

## Documentation

The documentation is a Writerside project in [`docs`](docs), published to GitHub Pages.

- [Configuration](docs/topics/Configuration.md): the layers, the events and the keys
- [Workflows](docs/topics/Workflows.md): what each stage does and which permissions it needs
- [Security](docs/topics/Security.md): where secrets exist and where they cannot
- [Cost](docs/topics/Cost.md): what keeps the runner minutes down
- [Adoption](docs/topics/Adoption.md): moving a project to these workflows
- [Releasing](docs/topics/Releasing.md): how this repository is versioned
- [Dependency updates](docs/topics/Dependency-Updates.md): Dependabot, and how its pull requests repair
  themselves

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Security problems: [SECURITY.md](SECURITY.md).

## License

[Apache License 2.0](LICENSE)
