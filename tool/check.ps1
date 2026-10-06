param([string]$Flutter = 'flutter')
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    & $Flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed' }
    & $Flutter analyze
    if ($LASTEXITCODE -ne 0) { throw 'Static analysis failed' }
    & $Flutter test
    if ($LASTEXITCODE -ne 0) { throw 'Tests failed' }
} finally { Pop-Location }
