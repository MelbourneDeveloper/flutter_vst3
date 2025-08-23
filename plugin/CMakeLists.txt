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

# Use the properly downloaded VST3 SDK
if(NOT DEFINED ENV{VST3_SDK_DIR})
  set(VST3_SDK_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../vst3sdk)
else()
  set(VST3_SDK_DIR $ENV{VST3_SDK_DIR})
endif()

if(NOT EXISTS ${VST3_SDK_DIR}/CMakeLists.txt)
  message(FATAL_ERROR "VST3 SDK not found at ${VST3_SDK_DIR}. Download it first.")
endif()

include_directories(
  ${VST3_SDK_DIR}
  ${VST3_SDK_DIR}/pluginterfaces
  ${VST3_SDK_DIR}/public.sdk/source
  ${CMAKE_CURRENT_SOURCE_DIR}/include
  ../native/include
)

# Add required VST3 SDK sources for plugin
file(GLOB VST3_PLUGIN_SOURCES
  ${VST3_SDK_DIR}/public.sdk/source/vst/vstbus.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/vstcomponent.cpp  
  ${VST3_SDK_DIR}/public.sdk/source/vst/vstcomponentbase.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/vsteditcontroller.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/vstinitiids.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/vstparameters.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/vstpresetfile.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/vstrepresentation.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/vstnoteexpressiontypes.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/vstaudioeffect.cpp
  ${VST3_SDK_DIR}/public.sdk/source/common/commoniids.cpp
  ${VST3_SDK_DIR}/public.sdk/source/common/pluginview.cpp
  ${VST3_SDK_DIR}/public.sdk/source/main/pluginfactory.cpp
  ${VST3_SDK_DIR}/base/source/baseiids.cpp
  ${VST3_SDK_DIR}/base/source/fobject.cpp
  ${VST3_SDK_DIR}/base/source/fstring.cpp
  ${VST3_SDK_DIR}/pluginterfaces/base/coreiids.cpp
  ${VST3_SDK_DIR}/pluginterfaces/base/funknown.cpp
  ${VST3_SDK_DIR}/pluginterfaces/base/ustring.cpp
)

add_library(flutter_dart_reverb MODULE
  src/dart_reverb_factory.cpp
  src/dart_reverb_processor.cpp
  src/dart_reverb_controller.cpp
  ../native/src/dart_reverb_bridge.cpp
  ${VST3_PLUGIN_SOURCES}
)

if(APPLE)
  set_target_properties(flutter_dart_reverb PROPERTIES
    BUNDLE TRUE
    BUNDLE_EXTENSION vst3
    OUTPUT_NAME "FlutterDartReverb"
    MACOSX_BUNDLE_INFO_PLIST ${CMAKE_CURRENT_SOURCE_DIR}/Info.plist.in
  )
  
  # Copy the required dylib into the bundle
  if(EXISTS "/workspace/native/build")
    set(DART_VST_HOST_LIB "/workspace/native/build/libdart_vst_host.dylib")
  else()
    set(DART_VST_HOST_LIB "${CMAKE_CURRENT_SOURCE_DIR}/../native/build/libdart_vst_host.dylib")
  endif()
  
  add_custom_command(TARGET flutter_dart_reverb POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory 
    $<TARGET_BUNDLE_DIR:flutter_dart_reverb>/Contents/Frameworks
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
    ${DART_VST_HOST_LIB}
    $<TARGET_BUNDLE_DIR:flutter_dart_reverb>/Contents/Frameworks/
    COMMAND install_name_tool -change @rpath/libdart_vst_host.dylib 
    @loader_path/../Frameworks/libdart_vst_host.dylib
    $<TARGET_BUNDLE_DIR:flutter_dart_reverb>/Contents/MacOS/FlutterDartReverb
    COMMENT "Bundling libdart_vst_host.dylib and fixing rpath"
  )
else()
  set_target_properties(flutter_dart_reverb PROPERTIES
    OUTPUT_NAME "FlutterDartReverb"
    PREFIX ""
    SUFFIX ".vst3"
  )
endif()

# Link against the dart_vst_host library
if(EXISTS "/workspace/native/build")
  # Dev container environment
  if(APPLE)
    target_link_libraries(flutter_dart_reverb
      ${CMAKE_DL_LIBS}
      /workspace/native/build/libdart_vst_host.dylib
    )
  elseif(UNIX)
    target_link_libraries(flutter_dart_reverb
      ${CMAKE_DL_LIBS}
      /workspace/native/build/libdart_vst_host.so
    )
  else()
    target_link_libraries(flutter_dart_reverb
      ${CMAKE_DL_LIBS}
      /workspace/native/build/libdart_vst_host.dll
    )
  endif()
else()
  # Local environment
  if(APPLE)
    target_link_libraries(flutter_dart_reverb
      ${CMAKE_DL_LIBS}
      ${CMAKE_CURRENT_SOURCE_DIR}/../native/build/libdart_vst_host.dylib
    )
  elseif(UNIX)
    target_link_libraries(flutter_dart_reverb
      ${CMAKE_DL_LIBS}
      ${CMAKE_CURRENT_SOURCE_DIR}/../native/build/libdart_vst_host.so
    )
  else()
    target_link_libraries(flutter_dart_reverb
      ${CMAKE_DL_LIBS}
      ${CMAKE_CURRENT_SOURCE_DIR}/../native/build/libdart_vst_host.dll
    )
  endif()
endif()

if(APPLE)
  find_library(COCOA_FRAMEWORK Cocoa)
  target_link_libraries(flutter_dart_reverb ${COCOA_FRAMEWORK})
endif()