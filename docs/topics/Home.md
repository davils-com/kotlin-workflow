# kotlin-workflow

Reusable GitHub Actions workflows for the Kotlin projects of Davils that build with
[Kreate](https://github.com/davils-com/kreate): checks, security scans, snapshots and releases to
`repo.davils.com`, documentation and benchmarks.

One workflow, `pipeline.yml`, decides from the event what a run does. Every part can be switched
off or changed, down to the task a stage runs and the runner it runs on.

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

## Where to go

- [Getting started](Getting-Started.md): one file in your project
- [Configuration](Configuration.md): the layers, the events and the keys
- [Workflows](Workflows.md): what each stage does and which permissions it needs
- [Dependency updates](Dependency-Updates.md): Dependabot, and how its pull requests repair themselves
- [Security](Security.md): where secrets exist and where they cannot
- [Cost](Cost.md): what keeps the runner minutes down
- [Adoption](Adoption.md): moving a project to these workflows
- [Releasing](Releasing.md): how this repository is versioned
