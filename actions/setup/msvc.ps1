# Sets up the developer environment of Visual Studio for the architecture of the runner: runs
# vcvarsall.bat and hands every variable it changed, PATH, INCLUDE and LIB among them, to the
# later steps of the job. A CMake build then finds cl, link and the Windows SDK, as it would in a
# Developer Command Prompt, whatever generator it uses.
#
# PowerShell, not Git Bash: Git Bash renames variables of Windows, and the names written here
# have to be the ones cmd.exe knows.
#
# Environment: RUNNER_ARCH (X64 or ARM64), RUNNER_TEMP, GITHUB_ENV

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

# A script of its own, so that no quoting of PowerShell reaches cmd.exe.
$script = Join-Path $env:RUNNER_TEMP "kotlin-workflow-msvc-$([guid]::NewGuid().ToString('N')).cmd"
Set-Content -Path $script -Encoding ascii -Value @(
  "@call `"$vcvars`" $architecture >nul"
  '@if errorlevel 1 exit /b 1'
  '@set'
)
$lines = & cmd.exe /d /c $script
$exitCode = $LASTEXITCODE
Remove-Item $script -ErrorAction SilentlyContinue
if ($exitCode -ne 0) {
  Write-Output "::error::$vcvars $architecture failed with exit code $exitCode."
  exit 1
}

# The names of the environment of Windows ignore case, and so does this table.
$before = @{}
foreach ($entry in Get-ChildItem Env:) { $before[$entry.Name] = $entry.Value }

$delimiter = "kw_$([guid]::NewGuid().ToString('N'))"
$changed = 0
foreach ($line in $lines) {
  $index = $line.IndexOf('=')
  if ($index -le 0) { continue }
  $name = $line.Substring(0, $index)
  $value = $line.Substring($index + 1)
  if ($before.ContainsKey($name) -and $before[$name] -ceq $value) { continue }
  Add-Content -Path $env:GITHUB_ENV -Encoding utf8 -Value @("$name<<$delimiter", $value, $delimiter)
  $changed++
}

Write-Output "Visual Studio $installation, $architecture: $changed variable(s) set."
