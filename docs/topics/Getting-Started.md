# Getting started

## The workflow file

Copy
[`templates/pipeline.yml`](https://github.com/davils-com/kotlin-workflow/blob/main/templates/pipeline.yml)
to `.github/workflows/pipeline.yml` of your project. The part that matters:

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

Replace `COMMIT` with the commit of a release. Then require the status check
**Pipeline / Pipeline** on your protected branches.

## The build

That is all a project needs whose Kreate block publishes to `repo.davils.com`:

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

The repository name `Davils` is what names the upload task the pipeline calls,
`publishAllPublicationsToDavilsRepository`.

## The configuration

Anything else goes into `.github/kotlin-workflow.yml`. Every key is optional:

```yaml
version: 1

tools:
  cmake: true

check:
  primary-tasks: [koverXmlReport]

policy:
  push-develop:
    os: [ubuntu-latest, windows-latest]
```

See [Configuration](Configuration.md) for the model and
[`templates/kotlin-workflow.yml`](https://github.com/davils-com/kotlin-workflow/blob/main/templates/kotlin-workflow.yml)
for a commented starting point.

## Dependabot

Copy
[`templates/dependabot.yml`](https://github.com/davils-com/kotlin-workflow/blob/main/templates/dependabot.yml)
to `.github/dependabot.yml`. See [Dependency updates](Dependency-Updates.md).
