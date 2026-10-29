param(
    [string]$VcpkgRoot = "D:\vcpkg",
    [string]$Triplet = "x64-windows-static-md-release",
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Continue"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$SourceDir = Join-Path $RepoRoot "platform\windows"
$BuildDir = Join-Path $RepoRoot "build\windows"

$vswhere = Join-Path ([Environment]::GetFolderPath("ProgramFilesX86")) "Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) {
    throw "vswhere.exe not found"
}
$vsPath = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath).Trim()
if (-not $vsPath) {
    throw "Visual Studio C++ toolchain not found"
}
$vcvars = Join-Path $vsPath "VC\Auxiliary\Build\vcvars64.bat"
if (-not (Test-Path $vcvars)) {
    throw "vcvars64.bat not found"
}

$cmake = (Get-Command cmake.exe -ErrorAction SilentlyContinue).Source
if (-not $cmake) {
    $cmake = Join-Path $vsPath "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
}
if (-not (Test-Path $cmake)) {
    throw "cmake.exe not found"
}
if (-not (Test-Path (Join-Path $VcpkgRoot "scripts\buildsystems\vcpkg.cmake"))) {
    throw "vcpkg toolchain not found under $VcpkgRoot"
}

$toolchain = Join-Path $VcpkgRoot "scripts\buildsystems\vcpkg.cmake"
$cmakeArgs = "-S `"$SourceDir`" -B `"$BuildDir`" -G Ninja -DCMAKE_BUILD_TYPE=$Configuration -DCMAKE_TOOLCHAIN_FILE=`"$toolchain`" -DVCPKG_TARGET_TRIPLET=$Triplet"
cmd.exe /c "call `"$vcvars`" && `"$cmake`" $cmakeArgs"
if ($LASTEXITCODE -ne 0) {
    throw "cmake configure failed"
}

cmd.exe /c "call `"$vcvars`" && `"$cmake`" --build `"$BuildDir`" --target fplayercore"
if ($LASTEXITCODE -ne 0) {
    throw "cmake build failed"
}

$dll = Get-ChildItem -Path $BuildDir -Recurse -Filter fplayercore.dll | Select-Object -First 1
$lib = Get-ChildItem -Path $BuildDir -Recurse -Filter fplayercore.lib | Select-Object -First 1
if ($null -eq $dll -or $null -eq $lib) {
    throw "fplayercore outputs not found under $BuildDir"
}

$outBin = Join-Path $BuildDir "bin"
$outLib = Join-Path $BuildDir "lib"
$outInclude = Join-Path $BuildDir "include"
New-Item -ItemType Directory -Force $outBin, $outLib, $outInclude | Out-Null
Copy-Item $dll.FullName (Join-Path $outBin "fplayercore.dll") -Force
Copy-Item $lib.FullName (Join-Path $outLib "fplayercore.lib") -Force
Copy-Item (Join-Path $SourceDir "sources\fplayercore.h") (Join-Path $outInclude "fplayercore.h") -Force

Write-Host "fplayercore.dll: $outBin\fplayercore.dll"
Write-Host "fplayercore.lib: $outLib\fplayercore.lib"
Write-Host "header: $outInclude\fplayercore.h"
