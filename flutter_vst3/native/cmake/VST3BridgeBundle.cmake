# Copies the Dart worker and the Flutter runtime into the plugin bundle.
# A macro, because it reads the variables set by add_dart_vst3_plugin.
macro(flutter_vst3_bundle_resources target_name)
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
        set(FLUTTER_MAC_FW_DIR "${CMAKE_CURRENT_SOURCE_DIR}/build/macos/Build/Products/${FLUTTER_VST3_BUNDLE_MODE}/${target_name}.app/Contents/Frameworks")
        flutter_vst3_require_flutter_path("${FLUTTER_MAC_FW_DIR}/FlutterMacOS.framework" "Run: flutter build macos --${FLUTTER_VST3_BUNDLE_MODE_LOWER}")
        if(FLUTTER_VST3_WANTS_FLUTTER)
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
        set(FLUTTER_WIN_DIR "${CMAKE_CURRENT_SOURCE_DIR}/build/windows/x64/runner/${FLUTTER_VST3_BUNDLE_MODE}")
        flutter_vst3_require_flutter_path("${FLUTTER_WIN_DIR}/flutter_windows.dll" "Run: flutter build windows --${FLUTTER_VST3_BUNDLE_MODE_LOWER}")
        if(FLUTTER_VST3_WANTS_FLUTTER)
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
        set(FLUTTER_LINUX_DIR "${CMAKE_CURRENT_SOURCE_DIR}/build/linux/x64/${FLUTTER_VST3_BUNDLE_MODE_LOWER}/bundle")
        flutter_vst3_require_flutter_path("${FLUTTER_LINUX_DIR}/lib/libflutter_linux_gtk.so" "Run: flutter build linux --${FLUTTER_VST3_BUNDLE_MODE_LOWER}")
        if(FLUTTER_VST3_WANTS_FLUTTER)
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
endmacro()
