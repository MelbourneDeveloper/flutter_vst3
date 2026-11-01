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

if(UNIX AND NOT APPLE)
    find_package(X11 REQUIRED)
    add_executable(editor_host_test editor_host_test.cpp
        ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/module.cpp
        ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/module_linux.cpp)
    target_include_directories(editor_host_test PRIVATE ${VST3_SDK_DIR})
    target_link_libraries(editor_host_test PRIVATE sdk_hosting sdk_common pluginterfaces base X11::X11 ${CMAKE_DL_LIBS} stdc++fs)
endif()

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
else()
    target_sources(plugin_host_test PRIVATE ${hosting_dir}/module_linux.cpp)
    target_link_libraries(plugin_host_test PRIVATE ${CMAKE_DL_LIBS} stdc++fs)
endif()
