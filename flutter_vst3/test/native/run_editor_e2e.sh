#!/usr/bin/env bash
# Builds the Flutter-enabled Echo, then opens real editors on it in a test host,
# with a good bundle and with bundles whose Flutter app is missing or corrupt.
# Usage: run_editor_e2e.sh [build|test]. With no argument it does both.
set -euo pipefail

phase="${1:-all}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
build="${VST3_E2E_BUILD_DIR:-$(mktemp -d)}"
mkdir -p "$build"
build="$(cd "$build" && pwd)"

case "$(uname)" in
  Linux)
    platform=linux; app=x86_64-linux/lib/libapp.so; run=(xvfb-run -a)
    export CMAKE_GENERATOR="${CMAKE_GENERATOR:-Ninja}" ;;
  Darwin)
    platform=macos; app=Frameworks/App.framework/Versions/A/App; run=()
    export CMAKE_GENERATOR="${CMAKE_GENERATOR:-Ninja}" ;;
  *)
    # CMake's default here is Visual Studio, which the SDK's bundle layout needs.
    platform=windows; app=x86_64-win/data/app.so; run=() ;;
esac

if [[ "$phase" != test ]]; then
    : "${VST3_SDK_DIR:?Set VST3_SDK_DIR}"
    export VST3_SDK_DIR
    (cd "$root/vsts/echo" && flutter build "$platform" --release)
    cmake -S "$root/vsts/echo" -B "$build/echo-flutter" -DCMAKE_BUILD_TYPE=Release -DSMTG_CREATE_PLUGIN_LINK=OFF -DFLUTTER_VST3_NATIVE_UI_ONLY=OFF
    cmake --build "$build/echo-flutter" --config Release --target echo
    cmake -S "$root/flutter_vst3/test/native" -B "$build/host" -DCMAKE_BUILD_TYPE=Release
    cmake --build "$build/host" --config Release --target editor_host_test editor_liveness_test
    if [[ -z "${VST3_E2E_MODES:-}" ]]; then
        cmake -S "$VST3_SDK_DIR" -B "$build/sdk" -DCMAKE_BUILD_TYPE=Release \
          -DSMTG_ADD_VSTGUI=OFF -DSMTG_ENABLE_VSTGUI_SUPPORT=OFF -DSMTG_ADD_VST3_PLUGINS_SAMPLES=OFF -DSMTG_RUN_VST_VALIDATOR=OFF
        cmake --build "$build/sdk" --config Release --target validator
    fi
fi

if [[ "$phase" == build ]]; then exit 0; fi

liveness="$(find "$build/host" -type f \( -name editor_liveness_test -o -name editor_liveness_test.exe \) -print -quit)"
"$liveness"
host_test="$(find "$build/host" -type f \( -name editor_host_test -o -name editor_host_test.exe \) -print -quit)"
bundle="$(find "$build/echo-flutter" -type d -name echo.vst3 -print -quit)"
test -n "$bundle"
test -e "$bundle/Contents/$app"

mkdir -p "$build/missing" "$build/garbage"
rm -rf "$build/missing/echo.vst3" "$build/garbage/echo.vst3"
cp -a "$bundle" "$build/missing/"
cp -a "$bundle" "$build/garbage/"
rm "$build/missing/echo.vst3/Contents/$app"
printf 'not a library\n' > "$build/garbage/echo.vst3/Contents/$app"

# Every mode runs even after a failure. The marker catches a process that exits
# with status 0 before finishing.
result=0
modes="${VST3_E2E_MODES:-good missing garbage wire environment immediate modules}"
for mode in $modes; do
    path="$bundle"
    if [[ "$mode" == missing || "$mode" == garbage ]]; then path="$build/$mode/echo.vst3"; fi
    extra=()
    if [[ "$mode" == modules ]]; then
        mkdir -p "$build/second"
        rm -rf "$build/second/echo.vst3"
        cp -a "$build/missing/echo.vst3" "$build/second/"
        path="$build/missing/echo.vst3"
        extra=("$build/second/echo.vst3")
    fi
    echo "=== $mode"
    if ! "${run[@]+"${run[@]}"}" "$host_test" "$path" "$mode" ${extra[@]+"${extra[@]}"} 2>&1 | tee "$build/$mode.log"; then
        result=1
        if [[ "$mode" == modules ]]; then echo 'FAIL H14 module survivor process failed'; fi
    fi
    grep -q '^PASS ALL EDITOR CASES' "$build/$mode.log" || result=1
done

if [[ -n "${VST3_E2E_MODES:-}" ]]; then exit "$result"; fi

validator="$(find "$build/sdk" -type f \( -name validator -o -name validator.exe \) -print -quit)"
"${run[@]+"${run[@]}"}" "$validator" "$bundle" || result=1
exit "$result"
