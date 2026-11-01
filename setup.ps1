# Stop on first error
$ErrorActionPreference = 'Stop'

Write-Host "Setting up development environment on Windows..."

# Resolve script root directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

# Check dependencies on Windows
Write-Host "Checking dependencies for Windows..."

# 1. Check CMake
if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
    Write-Host "CMake is not installed or not in PATH." -ForegroundColor Yellow
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "Installing CMake via winget..."
        winget install --id Kitware.CMake -e --silent --accept-source-agreements --accept-package-agreements
        Write-Host "Please restart your terminal after installation and run this script again."
        exit 1
    } else {
        Write-Error "Please install CMake (https://cmake.org/download/) and add it to your PATH."
    }
} else {
    Write-Host "cmake already installed"
}

# 2. Check C++ Compiler / Build Tools (MSVC / Visual Studio Build Tools)
$hasCompiler = $false
if (Get-Command cl -ErrorAction SilentlyContinue) {
    $hasCompiler = $true
} else {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        $vsInstall = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if ($vsInstall) {
            $hasCompiler = $true
        }
    }
}

if (-not $hasCompiler) {
    Write-Host "Visual Studio C++ Build Tools not detected." -ForegroundColor Yellow
    Write-Host "Please install 'Desktop development with C++' via Visual Studio Installer or run:"
    Write-Host "  winget install Microsoft.VisualStudio.2022.BuildTools --override `"--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended`""
    Write-Error "C++ compiler tools are required to build native libraries."
} else {
    Write-Host "C++ build tools available"
}

# 3. Check / Download and extract VST3 SDK
$vst3SdkDir = "$ScriptDir\vst3sdk"
if (-not (Test-Path $vst3SdkDir)) {
    Write-Host "Downloading VST3 SDK..."
    $zipFile = "$ScriptDir\vst3sdk.zip"
    
    # Download using curl if available, otherwise Invoke-WebRequest
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
        & curl.exe -L -o $zipFile https://www.steinberg.net/vst3sdk
    } else {
        Invoke-WebRequest -Uri "https://www.steinberg.net/vst3sdk" -OutFile $zipFile
    }

    Write-Host "Extracting VST3 SDK..."
    # tar is built-in on Windows 10/11 and much faster than Expand-Archive
    if (Get-Command tar.exe -ErrorAction SilentlyContinue) {
        & tar.exe -xf $zipFile
    } else {
        Expand-Archive -Path $zipFile -DestinationPath $ScriptDir -Force
    }

    if (Test-Path "$ScriptDir\VST_SDK\vst3sdk") {
        Move-Item -Path "$ScriptDir\VST_SDK\vst3sdk" -Destination $ScriptDir -Force
        Remove-Item -Path "$ScriptDir\VST_SDK" -Recurse -Force
    }
    if (Test-Path $zipFile) {
        Remove-Item -Path $zipFile -Force
    }
    Write-Host "VST3 SDK downloaded and extracted."
} else {
    Write-Host "VST3 SDK already exists, skipping download."
}

# 4. Set VST3_SDK_DIR environment variable (forward slashes for CMake compatibility)
$cmakeVst3Sdk = ($vst3SdkDir).Replace('\', '/')
$env:VST3_SDK_DIR = $cmakeVst3Sdk

# 5. Build native libraries (host and graph)
Write-Host "Building native libraries..."

function Build-NativeLib {
    param(
        [string]$name,
        [string]$sourceRelPath
    )
    Write-Host "Building $name library..."
    $srcDir = Join-Path $ScriptDir $sourceRelPath
    $buildDir = Join-Path $srcDir "build"

    cmake -B $buildDir -S $srcDir -DCMAKE_BUILD_TYPE=Release
    if ($LASTEXITCODE -ne 0) { throw "CMake configuration failed for $name" }

    cmake --build $buildDir --config Release
    if ($LASTEXITCODE -ne 0) { throw "Build failed for $name" }

    # Copy DLL and LIB artifacts
    $candidates = @(
        (Join-Path $buildDir "Release"),
        $buildDir
    )
    
    $destDirs = @(
        $ScriptDir,
        (Join-Path $ScriptDir "dart_vst_host"),
        (Join-Path $ScriptDir "dart_vst_graph")
    )

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

Build-NativeLib -name "dart_vst_host" -sourceRelPath "dart_vst_host\native"
Build-NativeLib -name "dart_vst_graph" -sourceRelPath "dart_vst_graph\native"

Write-Host "Setup complete! Native libraries built and ready for development." -ForegroundColor Green
