#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
echo 'Setting up development environment...'

if [ "$(uname)" = Darwin ]; then
    if ! command -v cmake >/dev/null; then
        command -v brew >/dev/null
        brew install cmake
    fi
    if ! command -v make >/dev/null; then
        xcode-select --install
        echo 'Complete the Xcode command line tools installation, then rerun setup.' >&2
        exit 1
    fi
fi

if [ ! -d vst3sdk ]; then
    curl -fL -o vst3sdk.zip https://www.steinberg.net/vst3sdk
    unzip -q vst3sdk.zip
    if [ -d VST_SDK/vst3sdk ]; then
        mv VST_SDK/vst3sdk .
        rm -rf VST_SDK
    fi
    test -d vst3sdk
    find vst3sdk -name '*.sh' -exec chmod +x {} +
    rm vst3sdk.zip
fi
export VST3_SDK_DIR="$PWD/vst3sdk"
make native
echo 'Setup complete! Native libraries built and ready for development.'
