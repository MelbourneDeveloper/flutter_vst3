# Windows build entry point. Every native command is checked immediately.
param([Parameter(Position = 0)][string]$Target = 'reverb')
$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir
if (-not $env:VST3_SDK_DIR) { $env:VST3_SDK_DIR = "$ScriptDir/vst3sdk" }

function Invoke-Checked {
    param([string]$Command, [string[]]$Arguments)
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Command $Arguments failed ($LASTEXITCODE)" }
}

function Package-Command {
    param([string]$Package, [string]$Tool, [string[]]$Arguments)
    Push-Location (Join-Path $ScriptDir $Package)
    try { Invoke-Checked $Tool $Arguments } finally { Pop-Location }
}

function Dart-Deps {
    foreach ($p in @('dart_vst_host', 'dart_vst_graph')) {
        Package-Command $p 'dart' @('pub', 'get')
    }
    foreach ($p in @('flutter_vst3', 'vsts/echo', 'vsts/flutter_reverb')) {
        Package-Command $p 'flutter' @('pub', 'get')
    }
}

function Plugin-Deps {
    param([string]$Name)
    Package-Command 'flutter_vst3' 'flutter' @('pub', 'get')
    Package-Command "vsts/$Name" 'flutter' @('pub', 'get')
}

function Build-NativeLib {
    param([string]$Name)
    $source = "$ScriptDir/$Name/native"
    $build = "$source/build"
    Invoke-Checked 'cmake' @('-S', $source, '-B', $build, '-DCMAKE_BUILD_TYPE=Release')
    Invoke-Checked 'cmake' @('--build', $build, '--config', 'Release')
    $dlls = @(Get-ChildItem $build -Recurse -Filter "$Name.dll")
    if ($dlls.Count -ne 1) { throw "Expected exactly one $Name.dll, found $($dlls.Count)" }
    foreach ($dest in @($ScriptDir, "$ScriptDir/$Name")) {
        Copy-Item $dlls[0].FullName $dest -Force
    }
}

function Build-Native {
    Build-NativeLib 'dart_vst_host'
    Build-NativeLib 'dart_vst_graph'
}

function Build-Plugin {
    param([string]$Name)
    Plugin-Deps $Name
    $metadata = Get-Content "vsts/$Name/plugin_metadata.json" -Raw | ConvertFrom-Json
    if ($metadata.flutterEntrypoint) {
        Package-Command "vsts/$Name" 'flutter' @('build', 'windows', '--release')
    }
    Invoke-Checked 'cmake' @('-S', "vsts/$Name", '-B', "vsts/$Name/build", '-DCMAKE_BUILD_TYPE=Release')
    Invoke-Checked 'cmake' @('--build', "vsts/$Name/build", '--config', 'Release')
}

function Run-Tests {
    Build-Native
    Dart-Deps
    Invoke-Checked 'powershell' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'flutter_vst3/test/native/run.ps1')
    foreach ($p in @('dart_vst_host', 'dart_vst_graph')) {
        Package-Command $p 'dart' @('test')
    }
    foreach ($p in @('flutter_vst3', 'vsts/echo', 'vsts/flutter_reverb')) {
        Package-Command $p 'flutter' @('test')
    }
}

function Remove-Build {
    param([string]$Path)
    if (Test-Path $Path) { Remove-Item $Path -Recurse -Force }
}
function Clean-Native {
    foreach ($p in @('dart_vst_host', 'dart_vst_graph')) { Remove-Build "$p/native/build" }
}
function Clean-Plugin {
    foreach ($p in @('echo', 'flutter_reverb')) { Remove-Build "vsts/$p/build" }
}
function Install-Plugins {
    $dest = "$env:LOCALAPPDATA/Programs/Common/VST3"
    New-Item -ItemType Directory -Force $dest | Out-Null
    foreach ($p in @('echo', 'flutter_reverb')) {
        Build-Plugin $p
        Remove-Build "$dest/$p.vst3"
        Copy-Item "vsts/$p/build/VST3/Release/$p.vst3" $dest -Recurse -Force
    }
}

switch ($Target.ToLower()) {
    { $_ -in 'all', 'reverb', 'reverb-vst', 'reverb-build-only' } { Build-Plugin 'flutter_reverb' }
    { $_ -in 'echo', 'echo-vst', 'echo-build-only' } { Build-Plugin 'echo' }
    'native' { Build-Native }
    'build' { Build-Native; Build-Plugin 'echo'; Build-Plugin 'flutter_reverb' }
    'dart-deps' { Dart-Deps }
    'reverb-deps' { Plugin-Deps 'flutter_reverb' }
    'echo-deps' { Plugin-Deps 'echo' }
    'test' { Run-Tests }
    'test-native' { Invoke-Checked 'powershell' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'flutter_vst3/test/native/run.ps1') }
    'test-host' { Build-Native; Package-Command 'dart_vst_host' 'dart' @('test') }
    'test-graph' { Build-Native; Package-Command 'dart_vst_graph' 'dart' @('test') }
    'clean' { Clean-Native; Clean-Plugin }
    'clean-native' { Clean-Native }
    'clean-plugin' { Clean-Plugin }
    'install' { Install-Plugins }
    'help' { Write-Host 'Targets: native, build, reverb, echo, test, test-native, test-host, test-graph, dart-deps, install, clean' }
    default { throw "Unknown target: $Target" }
}
