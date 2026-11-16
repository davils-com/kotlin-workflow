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
