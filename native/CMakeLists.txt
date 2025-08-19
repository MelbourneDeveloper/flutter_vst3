cmake_minimum_required(VERSION 3.20)
project(dart_vst_host LANGUAGES CXX)

# Build the combined VST host and graph into a single shared
# library. When consuming from Dart you will need to load
# libdart_vst_host.{so,dylib,dll} from your application.

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

if(NOT DEFINED ENV{VST3_SDK_DIR})
  message(FATAL_ERROR "Set VST3_SDK_DIR to the root of Steinberg VST3 SDK")
endif()
set(VST3_SDK_DIR $ENV{VST3_SDK_DIR})

include_directories(
  ${VST3_SDK_DIR}
  ${VST3_SDK_DIR}/pluginterfaces
  ${VST3_SDK_DIR}/public.sdk/source
  ${CMAKE_CURRENT_SOURCE_DIR}/include
)

# List source files. Both the core host and graph are built into
# the same library to simplify linking from Dart.
add_library(dart_vst_host SHARED
  src/dart_vst_host.cpp
  src/graph.cpp
)

target_compile_definitions(dart_vst_host PRIVATE DART_VST_HOST_EXPORTS)

if(APPLE)
  find_library(COCOA_FRAMEWORK Cocoa)
  target_link_libraries(dart_vst_host ${COCOA_FRAMEWORK})
endif()