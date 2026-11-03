#!/usr/bin/env bash
# All mutations and build outputs are confined to this disposable copy.
set -euo pipefail
root="$(cd "$(dirname "$0")/../../.." && pwd)"
work="$(mktemp -d /tmp/vst3-incremental-XXXXXX)"
trap 'rm -rf "$work"' EXIT
tar -C "$root" --exclude=.git --exclude=build --exclude=.dart_tool -cf - flutter_vst3 vsts/echo | tar -C "$work" -xf -
(cd "$work/flutter_vst3" && flutter pub get)
(cd "$work/vsts/echo" && flutter pub get)
cmake -S "$work/vsts/echo" -B "$work/build" -G Ninja -DFLUTTER_VST3_NATIVE_UI_ONLY=ON
cmake --build "$work/build" --target echo
worker="$work/build/VST3/Release/echo.vst3/Contents/x86_64-linux/echo_processor"
before="$(sha256sum "$worker" | cut -d' ' -f1)"
source="$work/vsts/echo/lib/src/echo_processor.dart"
cp "$source" "$work/original.dart"
python3 - "$source" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1]); text = p.read_text()
assert '0.85' in text
p.write_text(text.replace('0.85', '0.75'))
PY
cmake --build "$work/build" --target echo
test "$before" != "$(sha256sum "$worker" | cut -d' ' -f1)"
echo 'PASS audible constant changed bundled worker hash'
printf '\nTHIS_IS_INVALID_DART\n' >> "$source"
if cmake --build "$work/build" --target echo; then
  echo 'FAIL invalid Dart accepted' >&2; exit 1
fi
echo 'PASS invalid Dart rejected'
cp "$work/original.dart" "$source"
cmake --build "$work/build" --target echo
python3 - "$work/vsts/echo/plugin_metadata.json" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1]); data = json.loads(p.read_text())
data['parameters'][0]['defaultValue'] = 0.123456
p.write_text(json.dumps(data))
PY
cmake --build "$work/build" --target echo
grep -F '0.123456' "$work/build/generated/echo_controller.cpp"
grep -F '0.123456' "$work/build/generated/echo_processor.cpp"
echo 'PASS restored Dart and regenerated metadata default'
