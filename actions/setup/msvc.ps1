# Sets up the developer environment of Visual Studio for the architecture of the runner: runs
# vcvarsall.bat and writes the environment of cmd.exe before and after it, from which msvc-env.sh
# hands every variable it changed, PATH, INCLUDE and LIB among them, to the later steps of the job. A CMake build then finds cl, link and the Windows SDK, as it would in a
# Developer Command Prompt, whatever generator it uses.
#
# PowerShell, not Git Bash: Git Bash renames variables of Windows, and the environment cmd.exe
# prints has to carry the names Windows knows.
#
# Environment: RUNNER_ARCH (X64 or ARM64), RUNNER_TEMP
# Outputs (GITHUB_OUTPUT): before, after (the files `set` of cmd.exe wrote)

$ErrorActionPreference = 'Stop'

switch ("$env:RUNNER_ARCH") {
  'X64' { $architecture = 'x64'; $component = 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64' }
  'ARM64' { $architecture = 'arm64'; $component = 'Microsoft.VisualStudio.Component.VC.Tools.ARM64' }
  default {
    Write-Output "::error::The runner architecture '$env:RUNNER_ARCH' has no developer environment of Visual Studio."
    exit 1
  }
}

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path $vswhere)) {
  Write-Output "::error::Visual Studio is not installed on this runner: $vswhere is missing."
  exit 1
}

$installation = & $vswhere -latest -products * -requires $component -property installationPath | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($installation)) {
  Write-Output "::error::No installation of Visual Studio on this runner has the C++ tools for $architecture ($component)."
  exit 1
}

$vcvars = Join-Path $installation 'VC\Auxiliary\Build\vcvarsall.bat'
if (-not (Test-Path $vcvars)) {
  Write-Output "::error::$vcvars is missing."
  exit 1
}

# cmd.exe prints no variable of 8191 characters or more in full: it cuts it off and runs the next
# variable into it. A variable that long, such as the resolved configuration of kotlin-workflow,
# is left out of the environment of cmd.exe. vcvarsall.bat does not read it, and it stays as it
# is in the later steps.
$limit = 8000
$long = @(Get-ChildItem Env: | Where-Object { $_.Name.Length + 1 + $_.Value.Length -ge $limit })
foreach ($entry in $long) { Remove-Item -LiteralPath "Env:$($entry.Name)" }
if ($long.Count -gt 0) { Write-Output "Left out of cmd.exe as too long: $(($long | ForEach-Object Name) -join ', ')." }

# The environment as cmd.exe sees it, before and after vcvarsall.bat; msvc-env.sh hands on what
# changed. A script of its own, so that no quoting of PowerShell reaches cmd.exe.
$before = Join-Path $env:RUNNER_TEMP 'kotlin-workflow-msvc-before.txt'
$after = Join-Path $env:RUNNER_TEMP 'kotlin-workflow-msvc-after.txt'
$script = Join-Path $env:RUNNER_TEMP "kotlin-workflow-msvc-$([guid]::NewGuid().ToString('N')).cmd"
Set-Content -Path $script -Encoding ascii -Value @(
  "@set > `"$before`""
  "@call `"$vcvars`" $architecture >nul"
  '@if errorlevel 1 exit /b 1'
  "@set > `"$after`""
)
& cmd.exe /d /c $script
$exitCode = $LASTEXITCODE
Remove-Item $script -ErrorAction SilentlyContinue
if ($exitCode -ne 0) {
  Write-Output "::error::$vcvars $architecture failed with exit code $exitCode."
  exit 1
}

Add-Content -Path $env:GITHUB_OUTPUT -Encoding utf8 -Value @(
  "before=$($before -replace '\\', '/')"
  "after=$($after -replace '\\', '/')"
)
Write-Output "Visual Studio $installation, ${architecture}."
