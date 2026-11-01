# VST3Bridge.cmake - Shared CMake configuration for VST® 3 plugins using flutter_vst3
#
# This file provides common functions and setup for building VST® 3 plugins that use
# the flutter_vst3 framework for Flutter UI and Dart audio processing integration.

# Default to Release for single-config generators (Linux/macOS Makefiles & Ninja)
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Choose the type of build." FORCE)
endif()

# Function to create a VST3 plugin using the bridge
function(add_dart_vst3_plugin target_name dart_file)
    # Parse additional arguments
    set(options "")
    set(oneValueArgs BUNDLE_IDENTIFIER COMPANY_NAME PLUGIN_NAME)
    set(multiValueArgs INCLUDE_DIRS LINK_LIBRARIES)
    cmake_parse_arguments(PLUGIN "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    # Set default values if not provided
    if(NOT PLUGIN_BUNDLE_IDENTIFIER)
        set(PLUGIN_BUNDLE_IDENTIFIER "com.yourcompany.vst3.${target_name}")
    endif()
    
    if(NOT PLUGIN_COMPANY_NAME)
        set(PLUGIN_COMPANY_NAME "Your Company")
    endif()
    
    if(NOT PLUGIN_PLUGIN_NAME)
        set(PLUGIN_PLUGIN_NAME "${target_name}")
    endif()

    # Set up VST3 SDK
    if(NOT DEFINED ENV{VST3_SDK_DIR})
        set(VST3_SDK_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../vst3sdk)
    else()
        file(TO_CMAKE_PATH "$ENV{VST3_SDK_DIR}" VST3_SDK_DIR)
    endif()

    if(NOT EXISTS ${VST3_SDK_DIR}/CMakeLists.txt)
        message(FATAL_ERROR "VST3 SDK not found at ${VST3_SDK_DIR}. Download it first.")
    endif()

    # Disable validator and module info to avoid build failures
    set(SMTG_RUN_VST_VALIDATOR OFF CACHE BOOL "" FORCE)
    set(SMTG_CREATE_MODULE_INFO OFF CACHE BOOL "" FORCE)
    
    # Disable all SDK examples and samples to speed up build
    set(SMTG_ADD_VST3_PLUGINS_SAMPLES OFF CACHE BOOL "" FORCE)
    set(SMTG_ADD_VST3_HOSTING_SAMPLES OFF CACHE BOOL "" FORCE)
    set(SMTG_ADD_VSTGUI OFF CACHE BOOL "" FORCE)
    set(SMTG_CREATE_VST3_LINK OFF CACHE BOOL "" FORCE)
    set(SMTG_CREATE_PLUGIN_LINK OFF CACHE BOOL "" FORCE)
    
    # Only build the minimal SDK components needed
    set(SMTG_BUILD_UNIVERSAL_BINARY OFF CACHE BOOL "" FORCE)
    set(SMTG_ENABLE_VST3_PLUGIN_EXAMPLES OFF CACHE BOOL "" FORCE)
    set(SMTG_ENABLE_VST3_HOSTING_EXAMPLES OFF CACHE BOOL "" FORCE)
    
    # Only add SDK if not already added by parent project
    if(NOT TARGET sdk)
        # Save current build settings
        set(SAVED_CMAKE_MESSAGE_LOG_LEVEL ${CMAKE_MESSAGE_LOG_LEVEL})
        set(CMAKE_MESSAGE_LOG_LEVEL WARNING)
        
        # Add only the base SDK without examples
        add_subdirectory(${VST3_SDK_DIR} ${CMAKE_CURRENT_BINARY_DIR}/vst3sdk EXCLUDE_FROM_ALL)
        
        # Restore message level
        set(CMAKE_MESSAGE_LOG_LEVEL ${SAVED_CMAKE_MESSAGE_LOG_LEVEL})
    endif()

    # Find flutter_vst3 native directory
    # Since plugins are in vsts/ and bridge is in flutter_vst3/native/
    # The path from any vst plugin to bridge is ../../flutter_vst3/native/
    set(BRIDGE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../flutter_vst3/native")
    get_filename_component(BRIDGE_DIR "${BRIDGE_DIR}" ABSOLUTE)
    
    # Auto-generate C++ files from JSON metadata
    
    # Find Dart compiler for code generation and native executable compilation
    find_program(DART_EXECUTABLE NAMES dart.bat dart.exe dart)
    if(NOT DART_EXECUTABLE)
        message(FATAL_ERROR "Dart compiler is required for code generation and native executable compilation")
    endif()
    
    set(GENERATE_SCRIPT "${BRIDGE_DIR}/../scripts/generate_plugin.dart")
    if(NOT EXISTS ${GENERATE_SCRIPT})
        message(FATAL_ERROR "Code generator not found: ${GENERATE_SCRIPT}")
    endif()
    
    # COMPILE DART TO NATIVE EXECUTABLE - NOT AOT!
    # Use the combined UI+processor executable that contains BOTH Flutter UI and audio processing
    set(DART_EXE_SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/lib/${target_name}_processor_exe.dart")
    
    if(EXISTS ${DART_EXE_SOURCE})
        set(DART_EXE_OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/${target_name}_processor")
        if(WIN32)
            set(DART_EXE_OUTPUT "${DART_EXE_OUTPUT}.exe")
        endif()
        
        message(STATUS "Compiling Dart to NATIVE EXECUTABLE: ${DART_EXE_SOURCE}")
        
        # Compile Dart to native executable at configure time
        execute_process(
            COMMAND ${DART_EXECUTABLE} compile exe 
                    ${DART_EXE_SOURCE} 
                    -o ${DART_EXE_OUTPUT}
                    --verbose
            RESULT_VARIABLE DART_COMPILE_RESULT
            OUTPUT_VARIABLE DART_COMPILE_OUTPUT
            ERROR_VARIABLE DART_COMPILE_ERROR
            WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
        )
        
        if(NOT DART_COMPILE_RESULT EQUAL 0)
            message(FATAL_ERROR "FAILED TO COMPILE DART TO NATIVE: ${DART_COMPILE_ERROR}")
        endif()
        
        message(STATUS "Successfully compiled Dart to native executable: ${DART_EXE_OUTPUT}")
        
        # Store executable path for later use in bundle creation
        set(DART_PROCESSOR_EXE "${DART_EXE_OUTPUT}")
    else()
        message(WARNING "No Dart executable source at ${DART_EXE_SOURCE}")
    endif()
    
    # Run code generation using Dart script
    message(STATUS "Auto-generating VST3 C++ files from JSON metadata...")
    execute_process(
        COMMAND ${DART_EXECUTABLE} ${GENERATE_SCRIPT} ${CMAKE_CURRENT_SOURCE_DIR} ${target_name} ${target_name} ${CMAKE_CURRENT_BINARY_DIR}
        RESULT_VARIABLE GENERATION_RESULT
        OUTPUT_VARIABLE GENERATION_OUTPUT
        ERROR_VARIABLE GENERATION_ERROR
    )
    
    if(NOT GENERATION_RESULT EQUAL 0)
        message(FATAL_ERROR "Failed to generate VST3 files: ${GENERATION_ERROR}")
    endif()
    
    message(STATUS "Generated VST3 C++ files successfully")
    
    # Include generated metadata from Dart script
    set(METADATA_CMAKE_FILE "${CMAKE_CURRENT_BINARY_DIR}/generated/metadata.cmake")
    if(EXISTS ${METADATA_CMAKE_FILE})
        include(${METADATA_CMAKE_FILE})
        
        # Use JSON values if not provided as arguments
        if(NOT PLUGIN_BUNDLE_IDENTIFIER AND JSON_BUNDLE_ID)
            set(PLUGIN_BUNDLE_IDENTIFIER ${JSON_BUNDLE_ID})
        endif()
        
        if(NOT PLUGIN_COMPANY_NAME AND JSON_VENDOR)
            set(PLUGIN_COMPANY_NAME ${JSON_VENDOR})
        endif()
        
        if(NOT PLUGIN_PLUGIN_NAME AND JSON_PLUGIN_NAME)
            set(PLUGIN_PLUGIN_NAME ${JSON_PLUGIN_NAME})
        endif()
    endif()
    
    # Use generated sources instead of user-written sources
    set(generated_sources
        ${CMAKE_CURRENT_BINARY_DIR}/generated/${target_name}_controller.cpp
        ${CMAKE_CURRENT_BINARY_DIR}/generated/${target_name}_processor.cpp
        ${CMAKE_CURRENT_BINARY_DIR}/generated/${target_name}_factory.cpp
    )
    
    # Check that generated files exist
    foreach(src ${generated_sources})
        if(NOT EXISTS ${src})
            message(FATAL_ERROR "Generated source file not found: ${src}")
        endif()
    endforeach()
    
    # Check if native C++ processor exists (transpiled from Dart)
    set(NATIVE_PROCESSOR_FILE "${CMAKE_CURRENT_BINARY_DIR}/generated/${target_name}_processor_native.cpp")
    
    # Bridge components - Platform-specific view
    set(bridge_sources_no_factory)
    list(APPEND bridge_sources_no_factory ${BRIDGE_DIR}/src/vst3_shared_memory.cpp)
    if(SMTG_MAC)
        list(APPEND bridge_sources_no_factory
            ${BRIDGE_DIR}/src/embedded_flutter_view.mm
            ${BRIDGE_DIR}/src/native_cocoa_view.mm)
        set_source_files_properties(
            ${BRIDGE_DIR}/src/embedded_flutter_view.mm
            ${BRIDGE_DIR}/src/native_cocoa_view.mm
            PROPERTIES COMPILE_FLAGS "-fobjc-arc"
        )
    else()
        list(APPEND bridge_sources_no_factory ${BRIDGE_DIR}/src/embedded_flutter_view.cpp)
    endif()
    
    if(EXISTS ${NATIVE_PROCESSOR_FILE})
        message(STATUS "Using native C++ processor: ${NATIVE_PROCESSOR_FILE}")
        list(APPEND bridge_sources_no_factory ${NATIVE_PROCESSOR_FILE})
    else()
        message(STATUS "Using FFI Dart bridge: ${BRIDGE_DIR}/src/dart_vst3_bridge.cpp")
        list(APPEND bridge_sources_no_factory ${BRIDGE_DIR}/src/dart_vst3_bridge.cpp)
    endif()
    
    # Add platform-specific main entry point
    if(SMTG_MAC)
        list(APPEND bridge_sources_no_factory ${VST3_SDK_DIR}/public.sdk/source/main/macmain.cpp)
    elseif(SMTG_WIN)
        list(APPEND bridge_sources_no_factory ${VST3_SDK_DIR}/public.sdk/source/main/dllmain.cpp)
    elseif(SMTG_LINUX)
        list(APPEND bridge_sources_no_factory ${VST3_SDK_DIR}/public.sdk/source/main/linuxmain.cpp)
    endif()
    
    set(all_sources
        ${generated_sources}
        ${bridge_sources_no_factory}
    )

    # Create VST3 plugin using SDK's standard function
    smtg_add_vst3plugin(${target_name} ${all_sources})

    # Set target properties
    smtg_target_configure_version_file(${target_name})

    target_compile_features(${target_name}
        PUBLIC
            cxx_std_17
    )

    if(MSVC)
        target_compile_options(${target_name} PRIVATE
            $<$<NOT:$<CONFIG:Debug>>:/O2 /Oi /Ot /GF /Gy /fp:fast>
        )
    else()
        target_compile_options(${target_name} PRIVATE
            $<$<NOT:$<CONFIG:Debug>>:-O3 -fno-math-errno -fno-trapping-math -ffp-contract=fast>
        )
    endif()

    # Add include directories - INCLUDE generated FOLDER FOR HEADERS
    target_include_directories(${target_name}
        PRIVATE
            ${CMAKE_CURRENT_BINARY_DIR}/generated
            ${CMAKE_CURRENT_SOURCE_DIR}/include
            ${BRIDGE_DIR}/include
            ${CMAKE_CURRENT_SOURCE_DIR}/../../native/include
            ${PLUGIN_INCLUDE_DIRS}
    )

    # Pass metadata to C++ as compile definitions
    if(EXISTS ${METADATA_CMAKE_FILE})
        target_compile_definitions(${target_name} PRIVATE
            PLUGIN_NAME="${JSON_PLUGIN_NAME}"
            PLUGIN_TARGET_NAME=${target_name}
            PLUGIN_VENDOR="${JSON_VENDOR}"
            PLUGIN_VERSION="${JSON_VERSION}"
            PLUGIN_CATEGORY="${JSON_CATEGORY}"
            PLUGIN_WEB="${JSON_WEB}"
            PLUGIN_EMAIL="${JSON_EMAIL}"
        )
    endif()

    # Link against SDK and additional libraries
    target_link_libraries(${target_name}
        PRIVATE
            sdk
            ${PLUGIN_LINK_LIBRARIES}
    )
    
    if(SMTG_WIN)
        target_link_libraries(${target_name} PRIVATE comctl32)
        set(FLUTTER_EPHEMERAL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/windows/flutter/ephemeral")
        if(EXISTS "${FLUTTER_EPHEMERAL_DIR}/flutter_windows.h")
            message(STATUS "Configuring Flutter Windows UI embedding for ${target_name}...")
            target_include_directories(${target_name} PRIVATE
                "${FLUTTER_EPHEMERAL_DIR}"
                "${FLUTTER_EPHEMERAL_DIR}/cpp_client_wrapper"
                "${FLUTTER_EPHEMERAL_DIR}/cpp_client_wrapper/include"
            )
            target_sources(${target_name} PRIVATE
                "${FLUTTER_EPHEMERAL_DIR}/cpp_client_wrapper/core_implementations.cc"
                "${FLUTTER_EPHEMERAL_DIR}/cpp_client_wrapper/standard_codec.cc"
            )
            target_link_libraries(${target_name} PRIVATE
                "${FLUTTER_EPHEMERAL_DIR}/flutter_windows.dll.lib"
                delayimp
            )
            target_link_options(${target_name} PRIVATE
                "/DELAYLOAD:flutter_windows.dll"
            )
            target_compile_definitions(${target_name} PRIVATE
                FLUTTER_VST3_HAS_FLUTTER=1
            )
        endif()
    endif()
    
    # Link macOS frameworks for embedded views
    if(SMTG_MAC)
        find_library(FOUNDATION_FRAMEWORK Foundation)
        find_library(APPKIT_FRAMEWORK AppKit)
        target_link_libraries(${target_name} PRIVATE ${FOUNDATION_FRAMEWORK} ${APPKIT_FRAMEWORK})
        
        find_library(FLUTTER_FRAMEWORK FlutterMacOS PATHS "/usr/local/flutter" PATH_SUFFIXES "bin/cache/artifacts/engine/darwin-x64")
        if(FLUTTER_FRAMEWORK)
            target_link_libraries(${target_name} PRIVATE ${FLUTTER_FRAMEWORK})
        endif()
    elseif(SMTG_LINUX)
        find_package(PkgConfig REQUIRED)
        pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0 gtk+-x11-3.0)
        target_link_libraries(${target_name} PRIVATE PkgConfig::GTK ${CMAKE_DL_LIBS})
        set(FLUTTER_LINUX_EPHEMERAL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/linux/flutter/ephemeral")
        if(EXISTS "${FLUTTER_LINUX_EPHEMERAL_DIR}/flutter_linux/flutter_linux.h")
            message(STATUS "Configuring Flutter Linux UI embedding for ${target_name}...")
            target_include_directories(${target_name} PRIVATE
                "${FLUTTER_LINUX_EPHEMERAL_DIR}"
            )
            target_link_libraries(${target_name} PRIVATE
                "${FLUTTER_LINUX_EPHEMERAL_DIR}/libflutter_linux_gtk.so"
            )
            target_compile_definitions(${target_name} PRIVATE
                FLUTTER_VST3_HAS_FLUTTER=1
            )
        endif()
    endif()

    # Set bundle properties on macOS
    if(SMTG_MAC)
        # Create Info.plist.in in build directory to avoid polluting source
        set(INFO_PLIST_PATH "${CMAKE_CURRENT_BINARY_DIR}/Info.plist.in")
        if(NOT EXISTS ${INFO_PLIST_PATH})
            file(WRITE ${INFO_PLIST_PATH} "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
    <key>CFBundleExecutable</key>
    <string>${PLUGIN_PLUGIN_NAME}</string>
    <key>CFBundleIconFile</key>
    <string></string>
    <key>CFBundleIdentifier</key>
    <string>${PLUGIN_BUNDLE_IDENTIFIER}</string>
    <key>CFBundleName</key>
    <string>${PLUGIN_PLUGIN_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleSignature</key>
    <string>????</string>
</dict>
</plist>")
        endif()
        
        smtg_target_set_bundle(${target_name}
            BUNDLE_IDENTIFIER "${PLUGIN_BUNDLE_IDENTIFIER}"
            COMPANY_NAME "${PLUGIN_COMPANY_NAME}"
            INFOPLIST_IN ${INFO_PLIST_PATH}
        )
        
        # Set bundle bit for plugins without native library
        get_target_property(PLUGIN_PACKAGE_PATH ${target_name} SMTG_PLUGIN_PACKAGE_PATH)
        set(BUNDLE_COMMANDS)

        # Copy Dart processor executable if exists
        if(EXISTS ${DART_PROCESSOR_EXE})
            list(APPEND BUNDLE_COMMANDS
                COMMAND ${CMAKE_COMMAND} -E copy
                        ${DART_PROCESSOR_EXE}
                        "${PLUGIN_PACKAGE_PATH}/Contents/MacOS/${target_name}_processor"
            )
        endif()

        # Copy and link host dylib if exists
        if(EXISTS ${DART_VST_HOST_LIB})
            target_link_libraries(${target_name} PRIVATE ${DART_VST_HOST_LIB})
            list(APPEND BUNDLE_COMMANDS
                COMMAND ${CMAKE_COMMAND} -E make_directory "${PLUGIN_PACKAGE_PATH}/Contents/Frameworks"
                COMMAND ${CMAKE_COMMAND} -E copy_if_different
                        "${DART_VST_HOST_LIB}"
                        "${PLUGIN_PACKAGE_PATH}/Contents/Frameworks/"
                COMMAND install_name_tool -change @rpath/libdart_vst_host.dylib
                        @loader_path/../Frameworks/libdart_vst_host.dylib
                        "${PLUGIN_PACKAGE_PATH}/Contents/MacOS/${target_name}"
            )
        endif()

        # Copy Flutter frameworks if present
        set(FLUTTER_MAC_FW_DIR "${CMAKE_CURRENT_SOURCE_DIR}/build/macos/Build/Products/Release/${target_name}.app/Contents/Frameworks")
        if(NOT EXISTS "${FLUTTER_MAC_FW_DIR}/FlutterMacOS.framework")
            set(FLUTTER_MAC_FW_DIR "${CMAKE_CURRENT_SOURCE_DIR}/build/macos/Build/Products/Debug/${target_name}.app/Contents/Frameworks")
        endif()
        if(EXISTS "${FLUTTER_MAC_FW_DIR}/FlutterMacOS.framework")
            list(APPEND BUNDLE_COMMANDS
                COMMAND ${CMAKE_COMMAND} -E make_directory "${PLUGIN_PACKAGE_PATH}/Contents/Frameworks"
                COMMAND cp -a "${FLUTTER_MAC_FW_DIR}/FlutterMacOS.framework" "${PLUGIN_PACKAGE_PATH}/Contents/Frameworks/"
                COMMAND cp -a "${FLUTTER_MAC_FW_DIR}/App.framework" "${PLUGIN_PACKAGE_PATH}/Contents/Frameworks/"
                COMMAND codesign --force --sign - "${PLUGIN_PACKAGE_PATH}/Contents/Frameworks/FlutterMacOS.framework"
                COMMAND codesign --force --sign - "${PLUGIN_PACKAGE_PATH}/Contents/Frameworks/App.framework"
            )
        endif()

        # Set bundle bit, strip quarantine, and sign outer bundle
        list(APPEND BUNDLE_COMMANDS
            COMMAND SetFile -a B "${PLUGIN_PACKAGE_PATH}"
            COMMAND xattr -cr "${PLUGIN_PACKAGE_PATH}"
            COMMAND codesign --force --sign - "${PLUGIN_PACKAGE_PATH}"
        )

        add_custom_command(TARGET ${target_name} POST_BUILD
            ${BUNDLE_COMMANDS}
            COMMENT "Finalizing and codesigning VST3 bundle"
        )
    elseif(SMTG_WIN)
        get_target_property(PLUGIN_PACKAGE_PATH ${target_name} SMTG_PLUGIN_PACKAGE_PATH)
        set(BUNDLE_COMMANDS)
        if(EXISTS ${DART_PROCESSOR_EXE})
            list(APPEND BUNDLE_COMMANDS
                COMMAND ${CMAKE_COMMAND} -E copy_if_different
                        "${DART_PROCESSOR_EXE}"
                        "${PLUGIN_PACKAGE_PATH}/Contents/x86_64-win/${target_name}_processor.exe"
            )
        endif()
        set(FLUTTER_WIN_DIR "${CMAKE_CURRENT_SOURCE_DIR}/build/windows/x64/runner/Release")
        if(NOT EXISTS "${FLUTTER_WIN_DIR}/flutter_windows.dll")
            set(FLUTTER_WIN_DIR "${CMAKE_CURRENT_SOURCE_DIR}/build/windows/x64/runner/Debug")
        endif()
        if(EXISTS "${FLUTTER_WIN_DIR}/flutter_windows.dll")
            list(APPEND BUNDLE_COMMANDS
                COMMAND ${CMAKE_COMMAND} -E copy_if_different
                        "${FLUTTER_WIN_DIR}/flutter_windows.dll"
                        "${PLUGIN_PACKAGE_PATH}/Contents/x86_64-win/flutter_windows.dll"
                COMMAND ${CMAKE_COMMAND} -E copy_directory
                        "${FLUTTER_WIN_DIR}/data"
                        "${PLUGIN_PACKAGE_PATH}/Contents/x86_64-win/data"
            )
        endif()
        if(BUNDLE_COMMANDS)
            add_custom_command(TARGET ${target_name} POST_BUILD
                ${BUNDLE_COMMANDS}
                COMMENT "Bundling Dart processor and Flutter Windows assets into VST3 package"
            )
        endif()
    elseif(SMTG_LINUX)
        get_target_property(PLUGIN_PACKAGE_PATH ${target_name} SMTG_PLUGIN_PACKAGE_PATH)
        set(BUNDLE_COMMANDS)
        if(EXISTS ${DART_PROCESSOR_EXE})
            list(APPEND BUNDLE_COMMANDS
                COMMAND ${CMAKE_COMMAND} -E copy_if_different
                        "${DART_PROCESSOR_EXE}"
                        "${PLUGIN_PACKAGE_PATH}/Contents/x86_64-linux/${target_name}_processor"
            )
        endif()
        set(FLUTTER_LINUX_DIR "${CMAKE_CURRENT_SOURCE_DIR}/build/linux/x64/release/bundle")
        if(NOT EXISTS "${FLUTTER_LINUX_DIR}/lib/libflutter_linux_gtk.so")
            set(FLUTTER_LINUX_DIR "${CMAKE_CURRENT_SOURCE_DIR}/build/linux/x64/debug/bundle")
        endif()
        if(EXISTS "${FLUTTER_LINUX_DIR}/lib/libflutter_linux_gtk.so")
            list(APPEND BUNDLE_COMMANDS
                COMMAND ${CMAKE_COMMAND} -E copy_if_different
                        "${FLUTTER_LINUX_DIR}/lib/libflutter_linux_gtk.so"
                        "${PLUGIN_PACKAGE_PATH}/Contents/x86_64-linux/libflutter_linux_gtk.so"
                COMMAND ${CMAKE_COMMAND} -E copy_directory
                        "${FLUTTER_LINUX_DIR}/data"
                        "${PLUGIN_PACKAGE_PATH}/Contents/x86_64-linux/data"
                COMMAND ${CMAKE_COMMAND} -E copy_directory
                        "${FLUTTER_LINUX_DIR}/lib"
                        "${PLUGIN_PACKAGE_PATH}/Contents/x86_64-linux/lib"
            )
        endif()
        if(BUNDLE_COMMANDS)
            add_custom_command(TARGET ${target_name} POST_BUILD
                ${BUNDLE_COMMANDS}
                COMMENT "Bundling Dart processor and Flutter Linux assets into VST3 package"
            )
        endif()
    endif()
endfunction()