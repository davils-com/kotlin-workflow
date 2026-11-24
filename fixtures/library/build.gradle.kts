/*
 * Copyright 2026 Davils
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

plugins {
    id("org.jetbrains.kotlin.jvm") version "2.4.21"
    id("com.davils.kreate") version "4.1.0"
}

group = "com.davils.kotlinworkflow.fixture"
version = "1.0.0"

kreate {
    platform {
        javaVersion = JavaVersion.VERSION_25
        explicitApi = true
        allWarningsAsErrors = true
    }

    project {
        name = "KotlinWorkflowFixture"
        description = "The project kotlin-workflow runs its own workflows against."

        detekt {
            enabled = true
        }
    }
}

val nativeEnvironment = tasks.register("nativeEnvironment") {
    description = "Fails when Gradle runs on Windows in an environment whose variables were renamed."
    group = "verification"
    val isWindows = System.getProperty("os.name").startsWith("Windows")
    val names = System.getenv().keys.toSet()
    doLast {
        if (isWindows && "SystemRoot" !in names) {
            throw GradleException(
                "Gradle does not run in the environment of Windows: SystemRoot is missing or renamed. " +
                    "kotlin-workflow has to start Gradle from PowerShell, not from Git Bash."
            )
        }
    }
}

tasks.named("check") {
    dependsOn(nativeEnvironment)
}

// Stands in for kreateJniStage, which the fixture's Kreate does not have: stages a file for the
// platform of the runner with the manifest kotlin-workflow's native stage checks. On Windows it
// fails unless the developer environment of Visual Studio reached Gradle.
tasks.register("kotlinWorkflowStage") {
    description = "Stages a stand-in native library for the platform of the runner."
    group = "build"
    val osName = System.getProperty("os.name").lowercase()
    val osArch = System.getProperty("os.arch").lowercase()
    val isWindows = osName.startsWith("windows")
    val operatingSystem = when {
        isWindows -> "windows"
        osName.startsWith("mac") -> "macos"
        else -> "linux"
    }
    val architecture = if (osArch == "aarch64" || osArch == "arm64") "aarch64" else "x86_64"
    val platform = "$operatingSystem-$architecture"
    val visualStudio = providers.environmentVariable("VCINSTALLDIR").orNull
    val stage = layout.buildDirectory.dir("kreate/jni-stage/kotlin-workflow-fixture/$platform").get().asFile
    val manifest = "format=1\nplatform=$platform\ngroup=${project.group}\nartifact=kotlin-workflow-fixture\nversion=${project.version}\n"
    outputs.upToDateWhen { false }
    doLast {
        if (isWindows && visualStudio.isNullOrEmpty()) {
            throw GradleException("VCINSTALLDIR is not set: the developer environment of Visual Studio did not reach Gradle.")
        }
        stage.deleteRecursively()
        stage.mkdirs()
        stage.resolve("fixture.txt").writeText(platform)
        stage.resolve("native.properties").writeText(manifest)
    }
}
