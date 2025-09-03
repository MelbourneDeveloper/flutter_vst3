cmake_minimum_required(VERSION 3.20)
project(echo_plugin 
    VERSION 1.0.0
    LANGUAGES CXX)

# Build the Echo VST® 3 plugin using flutter_vst3
# This plugin uses pure Dart audio processing with Flutter UI via FFI bridge

set(CMAKE_CXX_STANDARD 17)

# Set build type and debug flags
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

if(CMAKE_BUILD_TYPE STREQUAL "Debug")
  add_compile_definitions(_DEBUG)
else()
  add_compile_definitions(NDEBUG RELEASE)
endif()

# Include the flutter_vst3 CMake helper
include(../../flutter_vst3/native/cmake/VST3Bridge.cmake)

# Create the VST® 3 plugin using auto-generated code from Dart definitions
# The bridge will auto-generate all C++ files from lib/echo_parameters.dart
# Metadata is read from plugin_metadata.json by the generator
add_dart_vst3_plugin(echo echo_parameters.dart)