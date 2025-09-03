#!/bin/bash

# Script to validate the Flutter Reverb VST3 plugin

echo "Validating Flutter Reverb VST3 plugin..."

# Check if VST3 validator exists
if [ ! -f "vst3sdk/build_all/bin/Debug/validator" ]; then
    echo "ERROR: VST3 validator not found at vst3sdk/build_all/bin/Debug/validator"
    echo "Please build the VST3 SDK validator first."
    exit 1
fi

# Run the validator on the Flutter Reverb plugin
vst3sdk/build_all/bin/Debug/validator vsts/flutter_reverb/build/VST3/Release/flutter_reverb.vst3