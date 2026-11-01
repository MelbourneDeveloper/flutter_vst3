# Build script for Windows (PowerShell equivalent to Makefile)
param(
    [Parameter(Position = 0)]
    [string]$Target = "reverb"
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

# Ensure VST3_SDK_DIR is set
if (-not $env:VST3_SDK_DIR) {
    if (Test-Path "$ScriptDir\vst3sdk") {
        $env:VST3_SDK_DIR = ("$ScriptDir\vst3sdk").Replace('\', '/')
    } else {
        Write-Error "VST3_SDK_DIR environment variable not set. Please run .\setup.bat first."
        exit 1
    }
}

# Resolve best CMake (preferring >= 3.25 for VST3 SDK)
function Get-CMakeCommand {
    $candidates = @()
    $vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vsWhere) {
        $vsPath = & $vsWhere -latest -products * -property installationPath
        if ($vsPath) {
            $vsCMake = Join-Path $vsPath "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
            if (Test-Path $vsCMake) { $candidates += $vsCMake }
        }
    }
    $pathCMake = Get-Command cmake -ErrorAction SilentlyContinue
    if ($pathCMake) { $candidates += $pathCMake.Source }

    foreach ($c in $candidates) {
        try {
            $verOutput = & $c --version
            if ($verOutput -match 'cmake version (\d+)\.(\d+)') {
                $major = [int]$matches[1]
                $minor = [int]$matches[2]
                if ($major -gt 3 -or ($major -eq 3 -and $minor -ge 25)) { return $c }
            }
        } catch {}
    }
    if ($candidates.Count -gt 0) { return $candidates[0] }
    return "cmake"
}

$CMake = Get-CMakeCommand

# Resolve Dart executable
function Get-DartCommand {
    $dartCmd = Get-Command dart.bat, dart.exe, dart -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($dartCmd) { return $dartCmd.Source }
    return "dart"
}
$Dart = Get-DartCommand

function Dart-Deps {
    Write-Host "Installing flutter_vst3, dart_vst_host, dart_vst_graph dependencies..."
    & $Dart pub get --directory=flutter_vst3
    & $Dart pub get --directory=dart_vst_host
    & $Dart pub get --directory=dart_vst_graph
}

function Reverb-Deps {
    Write-Host "Installing Flutter Reverb dependencies..."
    & $Dart pub get --directory=flutter_vst3
    & $Dart pub get --directory=vsts/flutter_reverb
}

function Echo-Deps {
    Write-Host "Installing Echo dependencies..."
    & $Dart pub get --directory=flutter_vst3
    & $Dart pub get --directory=vsts/echo
}

function Build-NativeLib {
    param([string]$name, [string]$sourceRelPath)
    Write-Host "Building $name library..."
    $srcDir = Join-Path $ScriptDir $sourceRelPath
    $buildDir = Join-Path $srcDir "build"

    & $CMake -B $buildDir -S $srcDir -DCMAKE_BUILD_TYPE=Release
    if ($LASTEXITCODE -ne 0) { throw "CMake configuration failed for $name" }

    & $CMake --build $buildDir --config Release
    if ($LASTEXITCODE -ne 0) { throw "Build failed for $name" }

    $candidates = @((Join-Path $buildDir "Release"), $buildDir)
    $destDirs = @($ScriptDir, (Join-Path $ScriptDir "dart_vst_host"), (Join-Path $ScriptDir "dart_vst_graph"))

    foreach ($cand in $candidates) {
        if (Test-Path $cand) {
            $files = Get-ChildItem -Path $cand -File | Where-Object { $_.Extension -in '.dll', '.lib' }
            foreach ($file in $files) {
                foreach ($dest in $destDirs) {
                    Copy-Item -Path $file.FullName -Destination $dest -Force
                }
            }
        }
    }
}

function Build-Native {
    Clean-Native
    Write-Host "Building native libraries..."
    Build-NativeLib -name "dart_vst_host" -sourceRelPath "dart_vst_host\native"
    Build-NativeLib -name "dart_vst_graph" -sourceRelPath "dart_vst_graph\native"
    Write-Host "✅ Native libraries built and copied." -ForegroundColor Green
}

function Build-Reverb {
    Reverb-Deps
    Write-Host "Building Flutter Reverb VST3 plugin..."
    $buildDir = "vsts/flutter_reverb/build"
    & $CMake -B $buildDir -S "vsts/flutter_reverb" -DCMAKE_BUILD_TYPE=Release
    if ($LASTEXITCODE -ne 0) { throw "CMake configuration failed for flutter_reverb" }

    & $CMake --build $buildDir --config Release
    if ($LASTEXITCODE -ne 0) { throw "Build failed for flutter_reverb" }
    Write-Host "✅ VST3 plugin built: $buildDir/VST3/Release/flutter_reverb.vst3" -ForegroundColor Green
}

function Build-Echo {
    Echo-Deps
    Write-Host "Building Flutter Windows bundle for Echo..."
    $nativeAssets = Join-Path $ScriptDir "vsts\echo\build\native_assets\windows"
    if (-not (Test-Path $nativeAssets)) {
        New-Item -ItemType Directory -Force -Path $nativeAssets | Out-Null
    }
    Push-Location (Join-Path $ScriptDir "vsts\echo")
    try {
        & flutter build windows --debug
        if ($LASTEXITCODE -ne 0) { throw "Flutter build windows failed for echo" }
    } finally {
        Pop-Location
    }

    Write-Host "Building Echo VST3 plugin..."
    $buildDir = "vsts/echo/build"
    & $CMake -B $buildDir -S "vsts/echo" -DCMAKE_BUILD_TYPE=Release
    if ($LASTEXITCODE -ne 0) { throw "CMake configuration failed for echo" }

    & $CMake --build $buildDir --config Release
    if ($LASTEXITCODE -ne 0) { throw "Build failed for echo" }
    Write-Host "✅ VST3 plugin built: $buildDir/VST3/Release/echo.vst3" -ForegroundColor Green
}

function Run-Tests {
    Build-Native
    Dart-Deps
    Write-Host "Running tests..."
    Write-Host "Running dart_vst_host tests..."
    Push-Location dart_vst_host
    try { & $Dart test } finally { Pop-Location }

    Write-Host "Running dart_vst_graph tests..."
    Push-Location dart_vst_graph
    try { & $Dart test } finally { Pop-Location }
}

function Clean-Native {
    Write-Host "Cleaning native library builds..."
    Remove-Item -Path "dart_vst_host/native/build" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "dart_vst_graph/native/build" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "*.dll", "*.lib", "*.exp" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "dart_vst_host/*.dll", "dart_vst_host/*.lib", "dart_vst_host/*.exp" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "dart_vst_graph/*.dll", "dart_vst_graph/*.lib", "dart_vst_graph/*.exp" -Force -ErrorAction SilentlyContinue
}

function Clean-Plugin {
    Write-Host "Cleaning all VST plugin builds..."
    Get-ChildItem -Path "vsts" -Directory | ForEach-Object {
        $b = Join-Path $_.FullName "build"
        if (Test-Path $b) {
            Write-Host "Cleaning $($_.Name)..."
            Remove-Item -Path $b -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Clean-All {
    Clean-Native
    Clean-Plugin
    Write-Host "✅ All clean." -ForegroundColor Green
}

function Install-Plugins {
    $vst3Dir = "$env:LOCALAPPDATA\Programs\Common\VST3"

    $plugins = @(
        @{ Name = "flutter_reverb.vst3"; Path = "$ScriptDir/vsts/flutter_reverb/build/VST3/Release/flutter_reverb.vst3"; Target = "reverb" },
        @{ Name = "echo.vst3"; Path = "$ScriptDir/vsts/echo/build/VST3/Release/echo.vst3"; Target = "echo" }
    )

    # Ensure each plugin is built
    foreach ($p in $plugins) {
        if (-not (Test-Path $p.Path)) {
            Write-Host "$($p.Name) not found. Building $($p.Target)..."
            if ($p.Target -eq "reverb") { Build-Reverb }
            elseif ($p.Target -eq "echo") { Build-Echo }
        }
    }

    Write-Host "Installing plugins to $vst3Dir..."

    if (-not (Test-Path $vst3Dir)) {
        New-Item -ItemType Directory -Path $vst3Dir -Force | Out-Null
    }

    foreach ($p in $plugins) {
        if (Test-Path $p.Path) {
            $dest = Join-Path $vst3Dir $p.Name
            if (Test-Path $dest) {
                Get-ChildItem -Path $dest -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    try { $_.Attributes = 'Normal' } catch {}
                }
                Remove-Item -Path $dest -Recurse -Force -ErrorAction SilentlyContinue
                if (Test-Path $dest) {
                    $oldDest = "$dest.old"
                    Remove-Item -Path $oldDest -Recurse -Force -ErrorAction SilentlyContinue
                    Move-Item -Path $dest -Destination $oldDest -Force -ErrorAction SilentlyContinue
                }
            }
            if (-not (Test-Path $dest)) {
                New-Item -ItemType Directory -Path $dest -Force | Out-Null
            }
            Copy-Item -Path "$($p.Path)\*" -Destination $dest -Recurse -Force
            Write-Host "✅ Installed $($p.Name) to $dest" -ForegroundColor Green
        } else {
            Write-Host "⚠️ $($p.Name) not found at $($p.Path)." -ForegroundColor Yellow
        }
    }
}

function Show-Help {
    Write-Host "Dart VST3 Toolkit Windows Build System" -ForegroundColor Cyan
    Write-Host "======================================"
    Write-Host ""
    Write-Host "Usage: .\build.ps1 [target]  (or build.bat [target])"
    Write-Host ""
    Write-Host "Targets:"
    Write-Host "  all, reverb, reverb-vst  - Build Flutter Reverb VST3 plugin (default)"
    Write-Host "  echo, echo-vst           - Build Echo VST3 plugin"
    Write-Host "  native                   - Build native libraries (dart_vst_host & dart_vst_graph)"
    Write-Host "  test                     - Run all tests (host & graph)"
    Write-Host "  test-host                - Run dart_vst_host tests only"
    Write-Host "  test-graph               - Run dart_vst_graph tests only"
    Write-Host "  dart-deps                - Install Dart package dependencies"
    Write-Host "  reverb-deps              - Install Reverb plugin dependencies"
    Write-Host "  echo-deps                - Install Echo plugin dependencies"
    Write-Host "  install                  - Install plugins to user VST3 directory"
    Write-Host "  clean                    - Clean all build artifacts"
    Write-Host "  clean-native             - Clean native library builds only"
    Write-Host "  clean-plugin             - Clean plugin builds only"
    Write-Host "  help                     - Show this help message"
}

switch ($Target.ToLower()) {
    "all"              { Build-Reverb }
    "reverb"           { Build-Reverb }
    "reverb-vst"       { Build-Reverb }
    "reverb-build-only"{ Build-Reverb }
    "reverb-deps"      { Reverb-Deps }
    "echo"             { Build-Echo }
    "echo-vst"         { Build-Echo }
    "echo-build-only"  { Build-Echo }
    "echo-deps"        { Echo-Deps }
    "native"           { Build-Native }
    "dart-deps"        { Dart-Deps }
    "test"             { Run-Tests }
    "test-host"        {
        Build-Native; Dart-Deps
        Push-Location dart_vst_host; try { & $Dart test } finally { Pop-Location }
    }
    "test-graph"       {
        Build-Native; Dart-Deps
        Push-Location dart_vst_graph; try { & $Dart test } finally { Pop-Location }
    }
    "clean"            { Clean-All }
    "clean-native"     { Clean-Native }
    "clean-plugin"     { Clean-Plugin }
    "install"          { Install-Plugins }
    "help"             { Show-Help }
    default            {
        Write-Host "Unknown target: $Target" -ForegroundColor Red
        Show-Help
        exit 1
    }
}
