# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 1.1.1

### Fixed

- **Setting up Visual Studio leaves long variables alone.** cmd.exe prints no variable of 8191
  characters or more in full; it cuts it off and runs the next one into it. The resolved
  configuration of a project with `native` is that long, so `tools.msvc` read it as changed by
  `vcvarsall.bat` and handed the cut-off value to every later step, where the check of the
  Windows runner failed with "Bad JSON escape sequence". Such variables are now kept away from
  cmd.exe, and only what `vcvarsall.bat` changed in the environment of cmd.exe is handed on.

## 1.1.0

### Added

- **Natives built per platform and published with the library.** A project that publishes a JNI
  library per platform with Kreate 5.5.0 lists a runner for each platform in `native.runners`.
  `snapshot.yml` and `release.yml` then build the natives there first, in the new `native.yml`,
  with `native.stage-task`, `kreateJniStage` by default, keep each stage as an artifact, and hand
  them all to the publishing build with `-Pkreate.jni.stage` and `-Pkreate.jni.publishPlatforms`.
  A release builds them after its gate with the version of the tag, discovers the platform
  publications and uploads them before the library. `native.stages` lists `check` to try the
  native build on every check. A project without `native.runners` runs as before.
- **`tools.msvc`, `tools.ninja` and `tools.clang-tidy`.** `msvc` sets up the developer
  environment of Visual Studio for the architecture of a Windows runner, `ninja` and
  `clang-tidy` install the tools where they are missing. `native.tools` adds tools to the native
  runners only.

- **`{releases-repository}` in the arguments of a consumer build.** The consumer build of a
  snapshot learned only the snapshots repository, so a consumer that keeps `com.davils` to one
  repository could not resolve a snapshot that depends on a released artifact of the group: a
  develop build of Kreate failed with "Could not find com.davils:kore-core:2.1.1". The argument is
  replaced by `publish.repository.releases-url`, for the consumer to list next to `{repository}`.

### Fixed

- **The build asks the GitHub API with a token.** Gradle got no `GITHUB_TOKEN`, so Kreate's
  standards audit shared the anonymous rate limit of the runner's address, and the check of the
  Kreate 5.3.0 tag failed once with HTTP 403 from `api.github.com`. The builds of `check.yml`,
  `security.yml` and of a snapshot now read the token of their job as `GITHUB_TOKEN`. The builds
  of `release.yml` still get none, because the tokens of its jobs write.
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
