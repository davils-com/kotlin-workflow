# Runs Gradle invocations on Windows, one after the other, each from a JSON list of tasks.
#
# The twin of run.sh. Gradle is started from PowerShell on Windows, never from Git Bash: Git Bash
# renames variables of Windows, SystemRoot to SYSTEMROOT among them, and a build that hands its
# environment on, as a test with Gradle TestKit does, ends up with both names. MSBuild refuses
# to start a compiler in such an environment.
#
# Environment:
#   KW_INVOCATIONS          JSON list of invocations, each a list of tasks and their options
#   KW_ARGS                 JSON list of arguments added to every invocation
#   KW_CONFIGURATION_CACHE  true, false or omit
#   KW_WORKING_DIRECTORY    where the Gradle wrapper is

$ErrorActionPreference = 'Stop'

$cacheArgument = ''
switch ("$env:KW_CONFIGURATION_CACHE") {
  'true' { $cacheArgument = '--configuration-cache' }
  'false' { $cacheArgument = '--no-configuration-cache' }
  'omit' { }
  '' { }
  default {
    Write-Output "::error::KW_CONFIGURATION_CACHE is '$env:KW_CONFIGURATION_CACHE', expected true, false or omit."
    exit 1
  }
}

$extra = [System.Collections.Generic.List[string]]::new()
if (-not [string]::IsNullOrWhiteSpace($env:KW_ARGS)) {
  foreach ($element in [System.Text.Json.JsonDocument]::Parse($env:KW_ARGS).RootElement.EnumerateArray()) {
    $extra.Add($element.GetString())
  }
}

if (-not [string]::IsNullOrWhiteSpace($env:KW_WORKING_DIRECTORY)) {
  Set-Location $env:KW_WORKING_DIRECTORY
}

$invocations = '[]'
if (-not [string]::IsNullOrWhiteSpace($env:KW_INVOCATIONS)) {
  $invocations = $env:KW_INVOCATIONS
}

foreach ($invocation in [System.Text.Json.JsonDocument]::Parse($invocations).RootElement.EnumerateArray()) {
  $arguments = [System.Collections.Generic.List[string]]::new()
  foreach ($element in $invocation.EnumerateArray()) {
    $value = $element.GetString()
    if (-not [string]::IsNullOrEmpty($value)) { $arguments.Add($value) }
  }
  if ($arguments.Count -eq 0) { continue }

  foreach ($argument in $extra) {
    if (-not [string]::IsNullOrEmpty($argument)) { $arguments.Add($argument) }
  }
  if ($cacheArgument) { $arguments.Add($cacheArgument) }

  $commandLine = $arguments.ToArray()
  Write-Output "::group::./gradlew $($commandLine -join ' ')"
  & ./gradlew.bat @commandLine
  $exitCode = $LASTEXITCODE
  Write-Output '::endgroup::'
  if ($exitCode -ne 0) { exit $exitCode }
}
