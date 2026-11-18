# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Fixed

- **The smoke check of a release reads klibs.** It expected a JAR for every publication that is not a
  POM, so the release of a Kotlin Multiplatform library failed on the klib of its Wasm publication
  with "kore-core-wasm-js-2.0.0.jar is missing from the release". It now downloads the file the
  packaging of the POM names, a klib, an AAR or a WAR, and a JAR for any other packaging, and
  verifies the provenance of klibs, AARs and WARs as well as of JARs.
- **A release guard of the build sees the release branch.** The publish job of `release.yml` checked
  out only the tag, so `kreateReleaseGuard` of Kreate, which checks again that the tag is on
  `origin/main`, stopped every release before the upload with "Git could not tell whether the
  release tag is part of origin/main". The job now checks out the whole history, as the gate does.

## 1.0.0

The first version: one pipeline for the Kotlin projects that build with Kreate.

### Added

- **`pipeline.yml`** plans a run from its event and calls the stages; it ends in one status check.
- **`dependencies.yml`** repairs a pull request of Dependabot that changes the version catalog: it
  regenerates the lock files and the verification metadata, commits them to the pull request and
  starts the pipeline on the new commit. The job that runs the build cannot write, and the job
  that commits accepts nothing but lock files and checksums.
- **`check.yml`** builds and verifies on a matrix of runners, sends the SARIF of Detekt and of the
  assurance gate to code scanning and summarises tests and coverage.
- **`security.yml`** runs Kreate's assurance gate and Trivy scans, a repository scan, an SBOM, the
  dependency review of a pull request and the dependency graph.
- **`snapshot.yml`** publishes `<version>-SNAPSHOT` to `repo.davils.com/snapshots`.
- **`release.yml`** releases a tag to `repo.davils.com/releases`: gate, preflight, signed upload,
  provenance and SBOM attestations, a consumer smoke test and the GitHub release. A dry run
  rehearses it.
- **`docs.yml`** builds with Dokka or Writerside and deploys to GitHub Pages.
- **`benchmark.yml`** runs the benchmarks against their baseline.
- **A configuration** in `.github/kotlin-workflow.yml`, validated against the defaults, with a
  policy per event that sets the stages, the runners and any other option.
- **Templates** for the caller workflow, the configuration and Dependabot.
- **The documentation** as a Writerside project, published to GitHub Pages.
