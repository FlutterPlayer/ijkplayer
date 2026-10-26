param(
    [string]$VcpkgRoot = "D:\vcpkg",
    [string]$Triplet = "x64-windows-static-md-release"
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$vcpkg = Join-Path $VcpkgRoot "vcpkg.exe"
if (-not (Test-Path $vcpkg)) {
    throw "vcpkg.exe not found under $VcpkgRoot"
}

$tripletDir = Join-Path $VcpkgRoot "triplets\community"
$tripletFile = Join-Path $tripletDir "$Triplet.cmake"
if (-not (Test-Path $tripletFile)) {
    New-Item -ItemType Directory -Force $tripletDir | Out-Null
    @'
set(VCPKG_TARGET_ARCHITECTURE x64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_BUILD_TYPE release)
'@ | Set-Content -Encoding ASCII $tripletFile
}

& $vcpkg install "ffmpeg:$Triplet" "sdl2:$Triplet" "pthreads:$Triplet" --triplet $Triplet
if ($LASTEXITCODE -ne 0) {
    throw "vcpkg install failed"
}

$srcRoot = Join-Path $VcpkgRoot "buildtrees\ffmpeg\src"
$src = Get-ChildItem $srcRoot -Directory | Where-Object { $_.Name -like "n*" } | Select-Object -First 1
if ($null -eq $src) {
    throw "FFmpeg source tree not found under $srcRoot"
}

$config = Join-Path $VcpkgRoot "buildtrees\ffmpeg\$Triplet-rel\config.h"
if (-not (Test-Path $config)) {
    throw "FFmpeg config.h not found at $config"
}

$dst = Join-Path $VcpkgRoot "installed\$Triplet\include"
Copy-Item (Join-Path $src.FullName "libavutil\*.h") (Join-Path $dst "libavutil") -Force
Copy-Item (Join-Path $src.FullName "libavformat\*.h") (Join-Path $dst "libavformat") -Force
Copy-Item (Join-Path $src.FullName "libavcodec\*.h") (Join-Path $dst "libavcodec") -Force
Copy-Item -Recurse -Force (Join-Path $src.FullName "compat") (Join-Path $dst "compat")
Copy-Item (Join-Path $RepoRoot "platform\windows\sources\ffmpeg_application.h") `
    (Join-Path $dst "libavutil\application.h") -Force
Copy-Item $config (Join-Path $dst "config.h") -Force
New-Item -ItemType Directory -Force (Join-Path $dst "libffmpeg") | Out-Null
Copy-Item $config (Join-Path $dst "libffmpeg\config.h") -Force

$encoding = [System.Text.Encoding]::GetEncoding(936)
foreach ($path in @((Join-Path $dst "config.h"), (Join-Path $dst "libffmpeg\config.h"))) {
    $lines = [System.IO.File]::ReadAllLines($path, $encoding)
    $lines = $lines | ForEach-Object {
        if ($_ -match '^#define CC_IDENT') { '#define CC_IDENT "MSVC"' } else { $_ }
    }
    [System.IO.File]::WriteAllLines($path, $lines, (New-Object System.Text.UTF8Encoding($true)))
}

Write-Host "Prepared MSVC FFmpeg headers under $dst"
