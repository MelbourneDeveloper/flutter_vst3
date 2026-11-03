#!/usr/bin/env bash
# Runs one package's tests with line coverage and always writes its lcov report.
# Usage: run_package_coverage.sh <package>
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
package="${1:?usage: run_package_coverage.sh <package>}"
: "${VST3_SDK_DIR:=$root/vst3sdk}"
export VST3_SDK_DIR
cd "$root/$package"
mkdir -p coverage
rm -f coverage/lcov.info

status=0
format_status=0
if grep -qE '^[[:space:]]+sdk:[[:space:]]*flutter' pubspec.yaml; then
  flutter test --coverage || status=$?
else
  dart test --coverage=coverage || status=$?
  dart run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info \
    --report-on=lib --packages=.dart_tool/package_config.json || format_status=$?
fi
[ -f coverage/lcov.info ] || : > coverage/lcov.info
[ "$status" -eq 0 ] || exit "$status"
exit "$format_status"
