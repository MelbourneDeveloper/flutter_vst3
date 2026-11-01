#!/usr/bin/env bash
# Builds the Flutter-enabled Echo, then opens real editors on it in a test host,
# with a good bundle and with bundles whose Flutter app is missing or corrupt.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
build="${VST3_E2E_BUILD_DIR:-$(mktemp -d)}"
: "${VST3_SDK_DIR:?Set VST3_SDK_DIR}"
export VST3_SDK_DIR

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

(cd "$root/vsts/echo" && flutter build "$platform" --release)
cmake -S "$root/vsts/echo" -B "$build/echo" -DCMAKE_BUILD_TYPE=Release -DSMTG_CREATE_PLUGIN_LINK=OFF -DFLUTTER_VST3_NATIVE_UI_ONLY=OFF
cmake --build "$build/echo" --config Release --target echo
cmake -S "$root/flutter_vst3/test/native" -B "$build/host" -DCMAKE_BUILD_TYPE=Release
cmake --build "$build/host" --config Release --target editor_host_test
host_test="$(find "$build/host" -type f \( -name editor_host_test -o -name editor_host_test.exe \) -print -quit)"
bundle="$(find "$build/echo" -type d -name echo.vst3 -print -quit)"
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
for mode in good missing garbage wire; do
    path="$bundle"
    if [[ "$mode" == missing || "$mode" == garbage ]]; then path="$build/$mode/echo.vst3"; fi
    echo "=== $mode"
    "${run[@]+"${run[@]}"}" "$host_test" "$path" "$mode" 2>&1 | tee "$build/$mode.log" || result=1
    grep -q '^PASS ALL EDITOR CASES' "$build/$mode.log" || result=1
done

cmake -S "$VST3_SDK_DIR" -B "$build/sdk" -DCMAKE_BUILD_TYPE=Release \
  -DSMTG_ADD_VSTGUI=OFF -DSMTG_ENABLE_VSTGUI_SUPPORT=OFF -DSMTG_ADD_VST3_PLUGINS_SAMPLES=OFF -DSMTG_RUN_VST_VALIDATOR=OFF
cmake --build "$build/sdk" --config Release --target validator
validator="$(find "$build/sdk" -type f \( -name validator -o -name validator.exe \) -print -quit)"
"${run[@]+"${run[@]}"}" "$validator" "$bundle" || result=1
exit "$result"
