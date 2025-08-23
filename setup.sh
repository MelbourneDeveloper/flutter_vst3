#!/bin/bash

set -e

echo 'Setting up development environment...'

# Check and install dependencies on macOS
if [ "$(uname)" = "Darwin" ]; then
    echo 'Checking dependencies for macOS...'
    
    # Check if Homebrew is installed
    if ! command -v brew &> /dev/null; then
        echo 'Installing Homebrew...'
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    
    # Check and install cmake
    if ! command -v cmake &> /dev/null; then
        echo 'Installing cmake...'
        brew install cmake
    else
        echo 'cmake already installed'
    fi
    
    # Check and install make (part of Xcode command line tools)
    if ! command -v make &> /dev/null; then
        echo 'Installing Xcode command line tools...'
        xcode-select --install
        echo 'Please complete the Xcode command line tools installation and run this script again.'
        exit 1
    else
        echo 'make already installed'
    fi
fi

# Download and extract VST3 SDK if not present
if [ ! -d vst3sdk ]; then
    echo 'Downloading VST3 SDK...'
    curl -L -o vst3sdk.zip https://www.steinberg.net/vst3sdk
    unzip -q vst3sdk.zip
    if [ -d VST_SDK/vst3sdk ]; then
        mv VST_SDK/vst3sdk .
        rm -rf VST_SDK
    fi
    rm -f vst3sdk.zip
    echo 'VST3 SDK downloaded and extracted.'
else
    echo 'VST3 SDK already exists, skipping download.'
fi

# Set VST3_SDK_DIR environment variable
export VST3_SDK_DIR="$(pwd)/vst3sdk"

# Build native library
echo 'Building native library...'
mkdir -p native/build
cd native/build
cmake ..
make

# Copy library to project root
if [ "$(uname)" = "Darwin" ]; then
    cp libdart_vst_host.dylib ../../
elif [ "$(uname)" = "Linux" ]; then
    cp libdart_vst_host.so ../../
else
    cp libdart_vst_host.dll ../../
fi

cd ../..

echo 'Setup complete! Native library built and ready for development.'