# LibrePods Windows Build Script (MSVC + Qt 6)
[CmdletBinding()]
param (
    [string]$QtDir = "C:\Qt\6.8.0\msvc2022_64",
    [string]$BuildType = "Release",
    [switch]$NoDeploy
)

$ErrorActionPreference = "Stop"

Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "  LibrePods Windows Build Script (MSVC + Qt 6)" -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan

# 1. Locate Visual Studio
$vsPath = "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools"
if (-not (Test-Path $vsPath)) {
    $vsPath = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools"
}
if (-not (Test-Path $vsPath)) {
    $vsPath = "C:\Program Files\Microsoft Visual Studio\2022\Community"
}
if (-not (Test-Path $vsPath)) {
    Write-Error "Visual Studio C++ Build Tools not found."
}

Write-Host "[INFO] Visual Studio: $vsPath" -ForegroundColor Green

# 2. Check Qt 6
if (-not (Test-Path $QtDir)) {
    Write-Error "Qt 6 not found at $QtDir. Please install Qt 6 (msvc2022_64)."
}

Write-Host "[INFO] Qt 6 SDK: $QtDir" -ForegroundColor Green

# 3. Setup build environment
$vcvars = Join-Path $vsPath "VC\Auxiliary\Build\vcvars64.bat"
$ninjaDir = Join-Path $vsPath "Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja"

$qtPrefix = $QtDir -replace '\\', '/'

Write-Host "[INFO] Configuring CMake..." -ForegroundColor Yellow
$cmdConfig = "set `"PATH=$ninjaDir;$QtDir\bin;%PATH%`" && call `"$vcvars`" && cmake -S windows -B build -G Ninja -DCMAKE_PREFIX_PATH=`"$qtPrefix`" -DCMAKE_BUILD_TYPE=$BuildType"
cmd.exe /c $cmdConfig
if ($LASTEXITCODE -ne 0) {
    Write-Error "CMake configuration failed."
}

Write-Host "[INFO] Compiling librepods-windows..." -ForegroundColor Yellow
$cmdBuild = "set `"PATH=$ninjaDir;$QtDir\bin;%PATH%`" && call `"$vcvars`" && cmake --build build"
cmd.exe /c $cmdBuild
if ($LASTEXITCODE -ne 0) {
    Write-Error "Compilation failed."
}

if (-not $NoDeploy) {
    Write-Host "[INFO] Deploying Qt runtime DLLs via windeployqt..." -ForegroundColor Yellow
    & "$QtDir\bin\windeployqt.exe" build\librepods-windows.exe --qmldir windows
}

Write-Host "`n===================================================" -ForegroundColor Green
Write-Host "  Build Successful!" -ForegroundColor Green
Write-Host "  Executable: $(Get-Location)\build\librepods-windows.exe" -ForegroundColor Green
Write-Host "  To launch:  .\build\librepods-windows.exe --debug" -ForegroundColor Green
Write-Host "===================================================" -ForegroundColor Green
