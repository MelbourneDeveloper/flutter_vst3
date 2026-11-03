# Builds and runs the native IPC round-trip tests on Windows.
# Run from a Visual Studio developer prompt, so that cl.exe is on PATH.
# -Phase build or test does one half; with neither it does both.
param([ValidateSet('all', 'build', 'test')][string]$Phase = 'all')
$ErrorActionPreference = 'Stop'

function Invoke-Checked {
    param([string]$Exe, [string[]]$Arguments)
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Exe failed with exit code $LASTEXITCODE" }
}

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$build = if ($env:VST3_IPC_TEST_BUILD_DIR) { $env:VST3_IPC_TEST_BUILD_DIR } else { Join-Path $env:TEMP 'vst3_ipc_test' }
New-Item -ItemType Directory -Force -Path $build | Out-Null

if ($Phase -ne 'test') {
Push-Location $root
try {
    Invoke-Checked 'dart' @('compile', 'exe', 'test/native/probe_worker.dart', '-o', "$build\probe_worker.exe")
} finally {
    Pop-Location
}

Push-Location $build
try {
    Invoke-Checked 'cl.exe' @('/nologo', '/std:c++17', '/EHsc', '/W4', '/WX', '/O1', '/D_CRT_SECURE_NO_WARNINGS',
        "/I$root\native\include", "/I$root\native\src",
        "$root\native\src\vst3_ipc_host.cpp",
        "$root\native\src\vst3_ipc_platform_win.cpp",
        "$root\test\native\ipc_host_test.cpp",
        "$root\test\native\ipc_host_recovery_test.cpp",
        '/Fe:ipc_host_test.exe')
    Invoke-Checked 'cl.exe' @('/nologo', '/std:c++17', '/EHsc', '/W4', '/WX', '/O1', '/D_CRT_SECURE_NO_WARNINGS',
        "/I$root\native\include", "/I$root\native\src",
        "$root\native\src\vst3_ipc_platform_win.cpp",
        "$root\test\native\ipc_platform_test.cpp", 'user32.lib', '/Fe:ipc_platform_test.exe')
} finally {
    Pop-Location
}
}

if ($Phase -eq 'build') { exit 0 }

Push-Location $build
try {
    Invoke-Checked "$build\ipc_platform_test.exe" @()
    Invoke-Checked "$build\ipc_host_test.exe" @("$build\probe_worker.exe")
} finally {
    Pop-Location
}
