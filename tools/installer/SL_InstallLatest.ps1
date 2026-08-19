param(
    [string]$Downloads = "D:\Downloads",
    [string]$ReposRoot = "$env:USERPROFILE\source\repos",
    [string]$ReShadeRoot = "$env:USERPROFILE\source\repos\reshade",
    [string]$FirestormRoot = "C:\Program Files\Firestorm-Releasex64"
)

$ErrorActionPreference = "Stop"

function Fail($msg) {
    Write-Host ""
    Write-Host "ERROR: $msg" -ForegroundColor Red
    exit 1
}

Write-Host "SL build/install helper" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $Downloads)) { Fail "Downloads folder not found: $Downloads" }
if (-not (Test-Path $ReposRoot)) { Fail "Repos root not found: $ReposRoot" }
if (-not (Test-Path $ReShadeRoot)) { Fail "ReShade source not found: $ReShadeRoot" }
if (-not (Test-Path $FirestormRoot)) { Fail "Firestorm folder not found: $FirestormRoot" }

# Pick the newest SL package ZIP from Downloads.
$zip = Get-ChildItem -Path $Downloads -File -Filter "SL_*.zip" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $zip) {
    Fail "No SL_*.zip package found in $Downloads"
}

Write-Host "Using package:" $zip.FullName -ForegroundColor Yellow

$baseName = [System.IO.Path]::GetFileNameWithoutExtension($zip.Name)
$extractTmp = Join-Path $env:TEMP ("SLInstall_" + [guid]::NewGuid().ToString("N"))

New-Item -ItemType Directory -Path $extractTmp | Out-Null
Expand-Archive -LiteralPath $zip.FullName -DestinationPath $extractTmp -Force

# Most packages contain one top-level folder. If not, use temp root.
$topDirs = Get-ChildItem -Path $extractTmp -Directory
if ($topDirs.Count -eq 1) {
    $packageRoot = $topDirs[0].FullName
    $projectName = $topDirs[0].Name
} else {
    $packageRoot = $extractTmp
    $projectName = $baseName
}

# Firestorm only needs to be closed when this package can replace/load an add-on.
# Pure .fx packages are safe to copy while Firestorm is running; ReShade can
# recompile/reload shader text without replacing a loaded DLL/add-on module.
$packageBuildBat = Get-ChildItem -Path $packageRoot -File -Filter "build-msvc.bat" -Recurse |
    Select-Object -First 1
$packageAddon = Get-ChildItem -Path $packageRoot -File -Filter "*.addon" -Recurse |
    Select-Object -First 1
$requiresFirestormClosed = ($null -ne $packageBuildBat) -or ($null -ne $packageAddon)

$fs = Get-Process | Where-Object {
    $_.ProcessName -match 'firestorm'
} | Select-Object -First 1

if ($fs -and $requiresFirestormClosed) {
    Fail "This package builds or installs an add-on. Close Firestorm first, then run this again."
}
elseif ($fs) {
    Write-Host "Firestorm is running; package is FX-only, so hot-install is allowed." -ForegroundColor Yellow
}

$repoDir = Join-Path $ReposRoot $projectName

if (Test-Path $repoDir) {
    Write-Host "Replacing existing repo folder:" $repoDir
    Remove-Item -LiteralPath $repoDir -Recurse -Force
}

Copy-Item -LiteralPath $packageRoot -Destination $repoDir -Recurse -Force

Write-Host "Extracted to:" $repoDir -ForegroundColor Green

# Build add-on if the package has build files.
$buildBat = Get-ChildItem -Path $repoDir -File -Filter "build-msvc.bat" -Recurse |
    Select-Object -First 1

if ($buildBat) {
    Write-Host ""
    Write-Host "Building add-on..." -ForegroundColor Cyan

    # This helper may be launched from an ordinary PowerShell window, where
    # MSVC/nmake are not on PATH. Resolve Visual Studio and run the package
    # build inside VsDevCmd so NMake + cl.exe are available automatically.
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    $vsInstall = $null

    if (Test-Path $vswhere) {
        $vsInstall = & $vswhere -latest -products * `
            -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
            -property installationPath
    }

    if (-not $vsInstall) {
        $knownVS = @(
            "C:\Program Files\Microsoft Visual Studio\18\Community",
            "C:\Program Files\Microsoft Visual Studio\2026\Community",
            "C:\Program Files\Microsoft Visual Studio\2022\Community"
        )

        foreach ($candidate in $knownVS) {
            if (Test-Path $candidate) {
                $vsInstall = $candidate
                break
            }
        }
    }

    if (-not $vsInstall) {
        Fail "Could not locate a Visual Studio installation with MSVC tools."
    }

    $vsDevCmd = Join-Path $vsInstall "Common7\Tools\VsDevCmd.bat"

    if (-not (Test-Path $vsDevCmd)) {
        Fail "VsDevCmd.bat not found: $vsDevCmd"
    }

    Write-Host "Using Visual Studio:" $vsInstall -ForegroundColor Yellow

    $cmdLine = 'call "{0}" -arch=x64 -host_arch=x64 && call "{1}" "{2}"' -f `
        $vsDevCmd, $buildBat.FullName, $ReShadeRoot

    Push-Location $buildBat.Directory.FullName
    try {
        & cmd.exe /d /s /c $cmdLine
        $buildExit = $LASTEXITCODE

        if ($buildExit -ne 0) {
            Fail "Build failed with exit code $buildExit"
        }
    }
    finally {
        Pop-Location
    }
}

# Install any built .addon files.
$addons = Get-ChildItem -Path $repoDir -File -Filter "*.addon" -Recurse |
    Where-Object { $_.FullName -match '\\build\\' }

foreach ($addon in $addons) {
    $dest = Join-Path $FirestormRoot $addon.Name
    Copy-Item -LiteralPath $addon.FullName -Destination $dest -Force
    Write-Host "Installed add-on:" $addon.Name -ForegroundColor Green
}

# Install all shader files from the package.
$shaderDest = Join-Path $FirestormRoot "reshade-shaders\Shaders"
$shaders = Get-ChildItem -Path $repoDir -File -Filter "*.fx" -Recurse

foreach ($shader in $shaders) {
    $dest = Join-Path $shaderDest $shader.Name
    Copy-Item -LiteralPath $shader.FullName -Destination $dest -Force
    Write-Host "Installed shader:" $shader.Name -ForegroundColor Green
}

if (($addons.Count -eq 0) -and ($shaders.Count -eq 0)) {
    Fail "Package contained no built add-on and no .fx shader."
}

Write-Host ""
Write-Host "Done." -ForegroundColor Cyan
Write-Host "Package repo:" $repoDir
if ($fs -and -not $requiresFirestormClosed) {
    Write-Host "FX-only hot-install complete. Firestorm can remain open." -ForegroundColor Green
} else {
    Write-Host "You can now start Firestorm."
}
