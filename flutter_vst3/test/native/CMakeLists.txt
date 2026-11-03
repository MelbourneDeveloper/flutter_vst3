# Builds plugin_host_test, which loads a real .vst3 bundle through the SDK's
# hosting classes. VST3_SDK_DIR must point at the Steinberg VST3 SDK.
cmake_minimum_required(VERSION 3.20)
project(flutter_vst3_plugin_host_test LANGUAGES C CXX)
if(APPLE)
    enable_language(OBJC OBJCXX)
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

if(NOT DEFINED ENV{VST3_SDK_DIR})
    message(FATAL_ERROR "Set VST3_SDK_DIR to the Steinberg VST3 SDK")
endif()
file(TO_CMAKE_PATH "$ENV{VST3_SDK_DIR}" VST3_SDK_DIR)

set(SMTG_ADD_VSTGUI OFF CACHE BOOL "" FORCE)
set(SMTG_ENABLE_VSTGUI_SUPPORT OFF CACHE BOOL "" FORCE)
set(SMTG_ADD_VST3_PLUGINS_SAMPLES OFF CACHE BOOL "" FORCE)
set(SMTG_ADD_VST3_HOSTING_SAMPLES OFF CACHE BOOL "" FORCE)
set(SMTG_RUN_VST_VALIDATOR OFF CACHE BOOL "" FORCE)
set(SMTG_CREATE_MODULE_INFO OFF CACHE BOOL "" FORCE)
add_subdirectory(${VST3_SDK_DIR} ${CMAKE_CURRENT_BINARY_DIR}/vst3sdk EXCLUDE_FROM_ALL)

add_executable(plugin_host_test plugin_host_test.cpp)
target_link_libraries(plugin_host_test PRIVATE sdk_hosting sdk_common pluginterfaces base)
target_include_directories(plugin_host_test PRIVATE ${VST3_SDK_DIR})

# The SDK leaves these out of sdk_hosting, for hosts to add themselves.
set(hosting_dir ${VST3_SDK_DIR}/public.sdk/source/vst/hosting)
target_sources(plugin_host_test PRIVATE
    ${VST3_SDK_DIR}/public.sdk/source/common/memorystream.cpp
    ${hosting_dir}/module.cpp
)
if(WIN32)
    target_sources(plugin_host_test PRIVATE ${hosting_dir}/module_win32.cpp)
elseif(APPLE)
    target_sources(plugin_host_test PRIVATE ${hosting_dir}/module_mac.mm)
    set_source_files_properties(${hosting_dir}/module_mac.mm PROPERTIES COMPILE_FLAGS -fobjc-arc)
    target_link_libraries(plugin_host_test PRIVATE "-framework Foundation" "-framework CoreFoundation")
else()
    target_sources(plugin_host_test PRIVATE ${hosting_dir}/module_linux.cpp)
    target_link_libraries(plugin_host_test PRIVATE ${CMAKE_DL_LIBS} stdc++fs)
endif()

add_executable(editor_liveness_test editor_liveness_test.cpp)
add_executable(editor_host_test editor_host_test.cpp ${hosting_dir}/module.cpp
    ${VST3_SDK_DIR}/public.sdk/source/common/memorystream.cpp)
target_include_directories(editor_host_test PRIVATE ${VST3_SDK_DIR})
target_link_libraries(editor_host_test PRIVATE sdk sdk_hosting sdk_common pluginterfaces base)
if(WIN32)
    target_sources(editor_host_test PRIVATE editor_host_platform_win.cpp ${hosting_dir}/module_win32.cpp)
elseif(APPLE)
    target_sources(editor_host_test PRIVATE editor_host_platform_mac.mm ${hosting_dir}/module_mac.mm)
    set_source_files_properties(editor_host_platform_mac.mm PROPERTIES COMPILE_FLAGS -fobjc-arc)
    target_link_libraries(editor_host_test PRIVATE "-framework Cocoa" "-framework Foundation" "-framework CoreFoundation")
else()
    find_package(X11 REQUIRED)
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(GTK3 REQUIRED IMPORTED_TARGET gtk+-3.0)
    target_link_libraries(editor_host_test PRIVATE PkgConfig::GTK3)
    target_sources(editor_host_test PRIVATE editor_host_platform_x11.cpp ${hosting_dir}/module_linux.cpp)
    target_link_libraries(editor_host_test PRIVATE X11::X11 Xtst ${CMAKE_DL_LIBS} stdc++fs)
endif()
