cmake_minimum_required(VERSION 3.20)
project(flutter_dart_reverb_plugin LANGUAGES CXX)

# Build the Flutter Dart Reverb VST3 plugin. This uses pure Dart audio
# processing from the flutter_reverb package via FFI bridge, implementing
# a complete VST3 reverb plugin powered by Dart. On macOS the output
# will be a bundle with extension .vst3.

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

set(VST3_SDK_DIR $ENV{VST3_SDK_DIR})

include_directories(
  ${VST3_SDK_DIR}
  ${VST3_SDK_DIR}/pluginterfaces
  ${VST3_SDK_DIR}/public.sdk/source
  ${CMAKE_CURRENT_SOURCE_DIR}/include
  ../native/include
)

add_library(flutter_dart_reverb MODULE
  src/dart_reverb_factory.cpp
  src/dart_reverb_processor.cpp
  src/dart_reverb_controller.cpp
  ../native/src/dart_reverb_bridge.cpp
)

if(APPLE)
  set_target_properties(flutter_dart_reverb PROPERTIES
    BUNDLE TRUE
    BUNDLE_EXTENSION vst3
    OUTPUT_NAME "FlutterDartReverb"
  )
else()
  set_target_properties(flutter_dart_reverb PROPERTIES
    OUTPUT_NAME "FlutterDartReverb"
    PREFIX ""
    SUFFIX ".vst3"
  )
endif()

target_link_libraries(flutter_dart_reverb
  ${CMAKE_DL_LIBS}
  /workspace/native/build/libdart_vst_host.so
)

if(APPLE)
  find_library(COCOA_FRAMEWORK Cocoa)
  target_link_libraries(flutter_dart_reverb ${COCOA_FRAMEWORK})
endif()