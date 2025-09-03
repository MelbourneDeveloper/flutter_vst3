cmake_minimum_required(VERSION 3.20)
project(dart_vst_host LANGUAGES CXX)

# Build the VST host library for loading and controlling VST3 plugins.
# When consuming from Dart you will need to load
# libdart_vst_host.{so,dylib,dll} from your application.

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Use the properly downloaded VST3 SDK
if(NOT DEFINED ENV{VST3_SDK_DIR})
  set(VST3_SDK_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../vst3sdk)
else()
  set(VST3_SDK_DIR $ENV{VST3_SDK_DIR})
endif()

if(NOT EXISTS ${VST3_SDK_DIR}/CMakeLists.txt)
  message(FATAL_ERROR "VST3 SDK not found at ${VST3_SDK_DIR}. Download it first.")
endif()

# Manually include VST3 sources - SDK requires CMake 3.25+ but we have 3.22
file(GLOB_RECURSE VST3_BASE_SOURCES 
  ${VST3_SDK_DIR}/base/source/*.cpp
  ${VST3_SDK_DIR}/pluginterfaces/base/*.cpp
  ${VST3_SDK_DIR}/pluginterfaces/vst/*.cpp
  ${VST3_SDK_DIR}/pluginterfaces/gui/*.cpp
)

# Add core VST SDK sources - avoid duplicates
file(GLOB VST3_SDK_SOURCES
  ${VST3_SDK_DIR}/public.sdk/source/vst/vstbus.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/vstcomponent.cpp  
  ${VST3_SDK_DIR}/public.sdk/source/vst/vstcomponentbase.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/vsteditcontroller.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/vstinitiids.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/vstnoteexpressiontypes.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/vstparameters.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/vstpresetfile.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/vstrepresentation.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/hostclasses.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/pluginterfacesupport.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/module.cpp
  ${VST3_SDK_DIR}/public.sdk/source/common/pluginview.cpp
  ${VST3_SDK_DIR}/public.sdk/source/common/commoniids.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/utility/stringconvert.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/utility/sampleaccurate.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/eventlist.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/parameterchanges.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/plugprovider.cpp
  ${VST3_SDK_DIR}/public.sdk/source/common/updatehandler.cpp
  ${VST3_SDK_DIR}/base/thread/source/flock.cpp
  ${VST3_SDK_DIR}/base/thread/source/fcondition.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/connectionproxy.cpp
  ${VST3_SDK_DIR}/public.sdk/source/common/commonstringconvert.cpp
)

include_directories(
  ${VST3_SDK_DIR}
  ${VST3_SDK_DIR}/pluginterfaces
  ${VST3_SDK_DIR}/public.sdk/source
  ${VST3_SDK_DIR}/base/thread/include
  ${CMAKE_CURRENT_SOURCE_DIR}/include
)

# List source files. This library provides VST3 plugin hosting functionality.
add_library(dart_vst_host SHARED
  src/dart_vst_host.cpp
  ${VST3_BASE_SOURCES}
  ${VST3_SDK_SOURCES}
)

# Add platform-specific module files
if(APPLE)
  target_sources(dart_vst_host PRIVATE
    ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/module_mac.mm
    ${VST3_SDK_DIR}/public.sdk/source/common/threadchecker_mac.mm
  )
elseif(UNIX)
  target_sources(dart_vst_host PRIVATE
    ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/module_linux.cpp
    ${VST3_SDK_DIR}/public.sdk/source/common/threadchecker_linux.cpp
  )
elseif(WIN32)
  target_sources(dart_vst_host PRIVATE
    ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/module_win32.cpp
    ${VST3_SDK_DIR}/public.sdk/source/common/threadchecker_win32.cpp
  )
endif()

target_compile_definitions(dart_vst_host PRIVATE 
  DART_VST_HOST_EXPORTS
  RELEASE=1
)

if(APPLE)
  find_library(COCOA_FRAMEWORK Cocoa)
  find_library(CARBON_FRAMEWORK Carbon)
  find_library(COREFOUNDATION_FRAMEWORK CoreFoundation)
  find_library(AUDIOTOOLBOX_FRAMEWORK AudioToolbox)
  target_link_libraries(dart_vst_host 
    ${COCOA_FRAMEWORK} 
    ${CARBON_FRAMEWORK}
    ${COREFOUNDATION_FRAMEWORK}
    ${AUDIOTOOLBOX_FRAMEWORK}
  )
  
  # Enable Objective-C++ for .mm files with ARC
  set_source_files_properties(
    ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/module_mac.mm
    ${VST3_SDK_DIR}/public.sdk/source/common/threadchecker_mac.mm
    PROPERTIES COMPILE_FLAGS "-x objective-c++ -fobjc-arc"
  )
endif()