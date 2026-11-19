# Security

## Where secrets exist

- `check.yml`, `security.yml`, `docs.yml`, `benchmark.yml` and `dependencies.yml` declare no
  secret. The code they
  build, its tests and its dependencies cannot read one.
- `snapshot.yml` and `release.yml` build first and upload afterwards. The repository token and
  the signing key are inputs of the single upload step and exist nowhere else in the job.
- A job that holds a secret restores no Gradle cache and keeps the configuration cache off:
  a cache was written by another job, and the configuration cache would store the credentials.
- The build of `check.yml`, of `security.yml` and of a snapshot reads the token of its job as
  `GITHUB_TOKEN`, so that a build that asks the GitHub API, as Kreate's standards audit does,
  gets a rate limit of its own. That token reads the repository and, in `check.yml` and
  `security.yml`, writes code scanning; GitHub gives a pull request from a fork or from
  Dependabot one that only reads. The builds of `release.yml` get no token: there it could
  write attestations or the repository.
- A release runs in an environment. Give it required reviewers; a snapshot's environment is
  restricted to the development branch.
- The workflows read the secrets `MAVEN_USERNAME`, `MAVEN_PASSWORD`, `SIGNING_KEY`,
  `SIGNING_KEY_ID` and `SIGNING_PASSWORD`. The caller passes them, usually from organisation
  secrets. A secret of the same name in the environment of a job wins over what the caller
  passed: that is how the `snapshot` environment gets a token that writes snapshots only, and
  how a signing key can live in the `release` environment alone.

## Who may write

- `dependencies.yml` is the one workflow that commits to a branch. The job that runs the build
  of the new versions has no permission to write; the job that commits runs no code of the
  project and accepts a patch only when it touches nothing but lock files and the verification
  metadata, as plain files. It acts for pull requests that Dependabot opened from a branch of
  the repository itself, never for a fork.

## What a release proves

- The tag is on the release branch and equals the version the project declares.
- Every artifact is signed, and carries a build provenance attestation and an SBOM attestation.
- The smoke job downloads the files without credentials and verifies them:

```bash
gh attestation verify library-1.4.0.jar --repo OWNER/PROJECT --signer-repo davils-com/kotlin-workflow
```

The attestation is signed by the workflow that ran the build. That is this repository, so
`--signer-repo` names it.

## How the workflows are written

- `permissions: {}` at the top of every workflow, and per job only what it needs.
- Every action is pinned to a full commit SHA with its version in a comment.
  `scripts/check-pins.sh` enforces it, and that one action has one commit everywhere.
- Values that come from an event or from a configuration reach a script through `env`, never as
  an expression inside `run`.
- References inside this repository use `$/`, which GitHub resolves to the commit that is
  running. A project that pins one commit of `pipeline.yml` runs every workflow, action and
  script at that commit.
- Checkouts do not persist their credentials.
- The workflows do not offer step-security/harden-runner. It sets itself up before the first step
  of a job, whatever the condition of its own step says, so a shared workflow could not switch it
  off for the projects that do not want it. A project that wants it calls the stages from a job
  of its own.

## Reporting a problem

See [SECURITY.md](https://github.com/davils-com/kotlin-workflow/blob/main/SECURITY.md).
