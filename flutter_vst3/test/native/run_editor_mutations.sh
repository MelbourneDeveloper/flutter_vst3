#!/usr/bin/env bash
# Every mutation lives in a separate source tree and build tree.
set -euo pipefail
root="$(cd "$(dirname "$0")/../../.." && pwd)"
: "${VST3_SDK_DIR:?Set VST3_SDK_DIR}"
case "$(uname)" in
  Linux) mutants=(linux_release h13 h15) ;;
  Darwin) mutants=(h15) ;;
  *) mutants=(win_ignore h12 h14 h15) ;;
esac
work="$(mktemp -d /tmp/testb_mutations.XXXXXX)"
echo "Mutation evidence: $work"
survivors=0
for mutant in "${mutants[@]}"; do
  tree="$work/$mutant/source"
  mkdir -p "$tree"
  (cd "$root" && tar --exclude=.git --exclude=node_modules --exclude=build --exclude=.dart_tool -cf - .) | (cd "$tree" && tar -xf -)
  python3 - "$tree" "$mutant" <<'PY'
import pathlib, sys
root, mutant = pathlib.Path(sys.argv[1]), sys.argv[2]
base = root / 'flutter_vst3/native/src'
def replace(path, old, new):
    text = path.read_text()
    assert text.count(old) == 1, (path, old, text.count(old))
    path.write_text(text.replace(old, new), newline='\n')
if mutant == 'linux_release':
    replace(base/'embedded_flutter_view_linux_flutter.inc', '            releasePointer();', '            /* mutant: no release */')
elif mutant == 'win_ignore':
    replace(base/'embedded_flutter_view_win_flutter.inc', '        ignoreHeldButton();', '        /* mutant: no ignore */')
elif mutant == 'h12':
    replace(base/'embedded_flutter_view_win_flutter.inc', 'sFlDll = LoadLibraryExW(', 'SetDllDirectoryW(L"C:\\\\Windows");\n            sFlDll = LoadLibraryExW(')
elif mutant == 'h13':
    replace(base/'embedded_flutter_view_linux_flutter.inc', 'gdk_set_allowed_backends("x11");', 'gdk_set_allowed_backends("x11");\n            setenv("GDK_BACKEND", "x11", 1);')
elif mutant == 'h14':
    replace(base/'embedded_flutter_view_win_native.inc', 'static const auto name = editorClassName(L"FlutterVst3NativeWin32View");', 'static const std::wstring name = L"FlutterVst3NativeWin32View";')
    replace(base/'embedded_flutter_view_win_native.inc', 'HINSTANCE hInst = editorModule();', 'HINSTANCE hInst = GetModuleHandleW(nullptr);')
elif mutant == 'h15':
    replace(root/'flutter_vst3/native/include/view_logic.h', 'if (alive.load()) work();', 'if (true) work();')
else:
    raise AssertionError(mutant)
print('APPLIED', mutant)
PY
  (cd "$tree/vsts/echo" && flutter pub get) > "$work/$mutant-pub.log" 2>&1
  if [[ "$mutant" == h15 ]]; then
    cmake -S "$tree/flutter_vst3/test/native" -B "$work/$mutant/host" -DCMAKE_BUILD_TYPE=Release > "$work/$mutant-build.log" 2>&1
    cmake --build "$work/$mutant/host" --config Release --target editor_liveness_test >> "$work/$mutant-build.log" 2>&1
    executable="$(find "$work/$mutant/host" -type f \( -name editor_liveness_test -o -name editor_liveness_test.exe \) -print -quit)"
    test -n "$executable"
    command=("$executable")
  else
    case "$mutant" in
      h12|h13) modes=environment ;;
      h14) modes=modules ;;
      *) modes=good ;;
    esac
    command=(env "VST3_E2E_BUILD_DIR=$work/$mutant/build" "VST3_E2E_MODES=$modes" bash "$tree/flutter_vst3/test/native/run_editor_e2e.sh")
  fi
  if "${command[@]}" > "$work/$mutant.log" 2>&1; then
    echo "FAIL mutant survived: $mutant"; survivors=$((survivors + 1)); continue
  fi
  case "$mutant" in
    linux_release) expected='FAIL .*drag missing events' ;;
    win_ignore) expected='FAIL .*(contract:|drag boundaries)' ;;
    h12) expected='FAIL H12 DLL directory changed' ;;
    h13) expected='FAIL H13 GDK_BACKEND changed' ;;
    h14) expected='FAIL H14|FAIL .*drag|FAIL .*controller|FAIL .*attached' ;;
    h15) expected='FAIL H15 dead token ran work' ;;
  esac
  if ! grep -E "$expected" "$work/$mutant.log"; then
    echo "FAIL mutant failed for another reason: $mutant"; tail -15 "$work/$mutant.log"
    survivors=$((survivors + 1)); continue
  fi
  echo "KILLED $mutant"
done
test "$survivors" -eq 0
