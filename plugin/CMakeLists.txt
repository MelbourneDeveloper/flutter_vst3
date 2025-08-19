cmake_minimum_required(VERSION 3.20)
project(dart_vst_host_plugin LANGUAGES CXX)

# Build a VST3 plug‑in that hosts the Dart VST graph. This uses the
# Steinberg SDK and the core dart_vst_host library. On macOS the
# output will be a bundle with extension .vst3.

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

add_library(dvh_plugin MODULE
  src/factory.cpp
  src/plugin_processor.cpp
  src/plugin_controller.cpp
  src/plugin_view.cpp
)

set_target_properties(dvh_plugin PROPERTIES
  BUNDLE TRUE
  BUNDLE_EXTENSION vst3
)

target_link_libraries(dvh_plugin
  ${CMAKE_DL_LIBS}
  /workspace/native/build/libdart_vst_host.so
)

if(APPLE)
  find_library(COCOA_FRAMEWORK Cocoa)
  target_link_libraries(dvh_plugin ${COCOA_FRAMEWORK})
endif()