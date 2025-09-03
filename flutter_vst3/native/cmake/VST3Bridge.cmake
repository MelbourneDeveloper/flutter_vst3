# VST3Bridge.cmake - Shared CMake configuration for VST® 3 plugins using flutter_vst3
#
# This file provides common functions and setup for building VST® 3 plugins that use
# the flutter_vst3 framework for Flutter UI and Dart audio processing integration.

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
        set(VST3_SDK_DIR $ENV{VST3_SDK_DIR})
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
    find_program(DART_EXECUTABLE dart)
    if(NOT DART_EXECUTABLE)
        message(FATAL_ERROR "Dart compiler is required for code generation and native executable compilation")
    endif()
    
    set(GENERATE_SCRIPT "${BRIDGE_DIR}/../scripts/generate_plugin.dart")
    if(NOT EXISTS ${GENERATE_SCRIPT})
        message(FATAL_ERROR "Code generator not found: ${GENERATE_SCRIPT}")
    endif()
    
    # COMPILE DART TO NATIVE EXECUTABLE - NOT AOT!
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
    
    # Bridge components (view and native processor if available)
    set(bridge_sources_no_factory
        ${BRIDGE_DIR}/src/plugin_view.cpp
    )
    
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
        if(NOT EXISTS ${DART_VST_HOST_LIB})
            # Copy Dart executable to VST3 bundle
            if(EXISTS ${DART_PROCESSOR_EXE})
                add_custom_command(TARGET ${target_name} POST_BUILD
                    COMMAND ${CMAKE_COMMAND} -E copy
                            ${DART_PROCESSOR_EXE}
                            "${PLUGIN_PACKAGE_PATH}/Contents/MacOS/${target_name}_processor"
                    COMMAND SetFile -a B "${PLUGIN_PACKAGE_PATH}"
                    COMMAND xattr -cr "${PLUGIN_PACKAGE_PATH}"
                    COMMAND codesign --force --deep --sign - "${PLUGIN_PACKAGE_PATH}"
                    COMMENT "Bundling Dart executable, setting bundle bit, cleaning attrs, and signing VST3 plugin"
                )
            else()
                add_custom_command(TARGET ${target_name} POST_BUILD
                    COMMAND SetFile -a B "${PLUGIN_PACKAGE_PATH}"
                    COMMAND xattr -cr "${PLUGIN_PACKAGE_PATH}"
                    COMMAND codesign --force --deep --sign - "${PLUGIN_PACKAGE_PATH}"
                    COMMENT "Setting bundle bit, cleaning attrs, and signing VST3 plugin"
                )
            endif()
        endif()
    endif()

    # The native library is optional for standalone VST3 plugins
    # Only link if it exists (for plugins that need host functionality)
    if(EXISTS "/workspace/native/build")
        set(DART_VST_HOST_LIB "/workspace/native/build/libdart_vst_host.dylib")
    else()
        set(DART_VST_HOST_LIB "${CMAKE_CURRENT_SOURCE_DIR}/../../native/build/libdart_vst_host.dylib")
    endif()

    if(EXISTS ${DART_VST_HOST_LIB})
        target_link_libraries(${target_name}
            PRIVATE
                ${DART_VST_HOST_LIB}
        )

        # Bundle the dylib into the VST3 package on macOS
        if(SMTG_MAC)
            get_target_property(PLUGIN_PACKAGE_PATH ${target_name} SMTG_PLUGIN_PACKAGE_PATH)
            
            # Create basic command list
            set(BUNDLE_COMMANDS
                COMMAND ${CMAKE_COMMAND} -E make_directory 
                "${PLUGIN_PACKAGE_PATH}/Contents/Frameworks"
                COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "${DART_VST_HOST_LIB}"
                "${PLUGIN_PACKAGE_PATH}/Contents/Frameworks/"
                COMMAND install_name_tool -change @rpath/libdart_vst_host.dylib 
                @loader_path/../Frameworks/libdart_vst_host.dylib
                "${PLUGIN_PACKAGE_PATH}/Contents/MacOS/${target_name}"
            )
            
            # Add Dart executable copy if it exists
            if(EXISTS ${DART_PROCESSOR_EXE})
                list(APPEND BUNDLE_COMMANDS
                    COMMAND ${CMAKE_COMMAND} -E copy
                    ${DART_PROCESSOR_EXE}
                    "${PLUGIN_PACKAGE_PATH}/Contents/MacOS/${target_name}_processor"
                )
            endif()
            
            # Add signing commands
            list(APPEND BUNDLE_COMMANDS
                COMMAND SetFile -a B "${PLUGIN_PACKAGE_PATH}"
                COMMAND xattr -cr "${PLUGIN_PACKAGE_PATH}"
                COMMAND codesign --force --deep --sign - "${PLUGIN_PACKAGE_PATH}"
            )
            
            add_custom_command(TARGET ${target_name} POST_BUILD
                ${BUNDLE_COMMANDS}
                COMMENT "Bundling libdart_vst_host.dylib and Dart executable, fixing rpath, setting bundle bit, cleaning attrs, and signing"
            )
        endif()
    endif()
endfunction()