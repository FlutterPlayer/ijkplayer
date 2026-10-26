param(
    [string]$VcpkgRoot = "D:\vcpkg",
    [string]$Triplet = "x64-windows-static-md-release",
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Continue"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$SourceDir = Join-Path $RepoRoot "platform\windows"
$BuildDir = Join-Path $RepoRoot "build\windows"

$cmake = (Get-Command cmake.exe -ErrorAction SilentlyContinue).Source
if (-not $cmake) {
    $vswhere = Join-Path ([Environment]::GetFolderPath("ProgramFilesX86")) "Microsoft Visual Studio\Installer\vswhere.exe"
    $vsPath = & $vswhere -latest -products * -property installationPath
    $cmake = Join-Path $vsPath "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
}
if (-not (Test-Path $cmake)) {
    throw "cmake.exe not found"
}
if (-not (Test-Path (Join-Path $VcpkgRoot "scripts\buildsystems\vcpkg.cmake"))) {
    throw "vcpkg toolchain not found under $VcpkgRoot"
}

$cmakeArgs = @(
    "-S", $SourceDir,
    "-B", $BuildDir,
    "-G", "Visual Studio 17 2022",
    "-A", "x64",
    "-DCMAKE_TOOLCHAIN_FILE=$(Join-Path $VcpkgRoot 'scripts\buildsystems\vcpkg.cmake')",
    "-DVCPKG_TARGET_TRIPLET=$Triplet",
    "-DCMAKE_BUILD_TYPE=$Configuration"
)
& $cmake @cmakeArgs
if ($LASTEXITCODE -ne 0) {
    throw "cmake configure failed"
}

& $cmake --build $BuildDir --config $Configuration --target fplayercore
if ($LASTEXITCODE -ne 0) {
    throw "cmake build failed"
}

$configDir = Join-Path $BuildDir $Configuration
$dll = Join-Path $configDir "fplayercore.dll"
$lib = Join-Path $configDir "fplayercore.lib"
if (-not (Test-Path $dll) -or -not (Test-Path $lib)) {
    throw "fplayercore outputs not found in $configDir"
}

$outBin = Join-Path $BuildDir "bin"
$outLib = Join-Path $BuildDir "lib"
$outInclude = Join-Path $BuildDir "include"
New-Item -ItemType Directory -Force $outBin, $outLib, $outInclude | Out-Null
Copy-Item $dll (Join-Path $outBin "fplayercore.dll") -Force
Copy-Item $lib (Join-Path $outLib "fplayercore.lib") -Force
Copy-Item (Join-Path $SourceDir "sources\fplayercore.h") (Join-Path $outInclude "fplayercore.h") -Force

Write-Host "fplayercore.dll: $outBin\fplayercore.dll"
Write-Host "fplayercore.lib: $outLib\fplayercore.lib"
Write-Host "header: $outInclude\fplayercore.h"
