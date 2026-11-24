# Native libraries

A JNI library built on one runner carries the library of one platform. Kreate publishes one
artifact per platform instead, `mylib-windows-x86_64` next to `mylib`, and builds each of them
where it is native. The native stage of kotlin-workflow runs that build: one job per platform
builds and stages its library, and the publishing job hands every stage to Kreate, which checks
them and uploads them before the library itself.

It needs Kreate 5.5.0 or later, with `jni { packaging { publishing { enabled = true } } }`. See
[Publishing native libraries](https://davils-com.github.io/kreate/jni-publishing.html) in the
documentation of Kreate.

## Switching it on

List a runner for every platform in `.github/kotlin-workflow.yml`:

```yaml
native:
  stage-task: kreateJniStage
  runners:
    - { platform: windows-x86_64, runs-on: windows-latest }
    - { platform: windows-aarch64, runs-on: windows-11-arm }
  tools:
    msvc: true
    cmake: true
    ninja: true
    clang-tidy: true
```

A platform is `linux`, `windows` or `macos` followed by `x86_64` or `aarch64`, the identifiers of
Kreate. `runs-on` is a runner label or a list of labels. A project without `native.runners`
builds no natives, and nothing about its pipeline changes.

## What runs

| Stage | Natives |
|---|---|
| snapshot | built first, published with the snapshot |
| release | built after the gate, with the version of the tag, published with the release |
| check | only when `native.stages` lists `check`: built, checked, and kept nowhere |

`native.stages` decides which stages build them, `[snapshot, release]` by default.

Each runner of `native.runners`

1. checks out the commit, sets up the JDK and Gradle without any cache, and installs `tools` and
   `native.tools`,
2. runs `native.stage-task`, `kreateJniStage` by default, with the version the publishing job
   will use: `KREATE_SNAPSHOT=true` for a snapshot, `release.version-env` for a release,
3. checks that the stage in `native.stage-directory` holds its own platform and nothing else,
   so that a runner label that leads to the wrong machine stops here and not in the release,
4. keeps the stage as the artifact `kotlin-workflow-native-<platform>` for
   `retention.native` days.

The publishing job of the same run then

1. downloads every stage into one directory and checks that each artifact of it has every
   platform of `native.runners`,
2. builds `publish.build-tasks` and `native.build-tasks` with
   `-Pkreate.jni.stage=<directory>` and `-Pkreate.jni.publishPlatforms=<platforms>`, before any
   secret exists. `kreateJniNativeJars` packages every platform, and Kreate refuses a stage of
   another group, artifact, version or, for a release, commit, and a library whose checksum
   differs from its manifest,
3. uploads with the same arguments. In a release the preflight lists the platform publications
   too, and they are uploaded before the library, each in a Gradle invocation of its own, so
   the repository never serves a library without its platforms.

The provenance and SBOM attestations cover the platform JARs, because they land in
`build/libs` like every other JAR, and the smoke job downloads and verifies them like every other
publication.

## Tools

`tools` applies to every job that builds, `native.tools` to the native runners only, in
addition. A Windows-only toolchain therefore does not slow down the check on Linux.

| Tool | Linux | macOS | Windows |
|---|---|---|---|
| `msvc` | - | - | runs `vcvarsall.bat` of the newest Visual Studio for the architecture of the runner and hands its environment to the later steps |
| `cmake` | apt | Homebrew | Chocolatey, unless Visual Studio provides it |
| `ninja` | apt | Homebrew | Chocolatey, unless Visual Studio provides it |
| `clang-tidy` | apt | Homebrew's LLVM, put on the `PATH` | `C:\Program Files\LLVM`, from Chocolatey when missing |
| `packages` | `apt` | `brew` | `choco` |

A tool that is on the `PATH` already is taken as it is. A tool that is still missing afterwards
fails the job: a native build that skips a check for a missing tool has not passed it.

## Overriding the properties

`native.stage-property` and `native.platforms-property` name the Gradle properties of Kreate.
An empty name passes nothing, for a build that selects its platforms itself.
`native.build-tasks` runs in the build before the upload; empty leaves the packaging to the upload.
