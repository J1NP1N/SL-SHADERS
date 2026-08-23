cmake_minimum_required(VERSION 3.20)
project(SLRenderBridge VERSION 0.1.0 LANGUAGES CXX)

option(SLRB_BUILD_TESTS "Build deterministic bridge-core tests" ON)
option(SLRB_BUILD_ADDON "Build the Windows ReShade add-on" ${WIN32})
set(RESHADE_SDK_DIR "" CACHE PATH "Path to a ReShade source checkout containing include/reshade.hpp and deps/imgui")

add_library(SLRenderBridgeCore STATIC
    src/BridgeCore.cpp
    src/MainViewClassifier.cpp
    src/ResourceTracker.cpp
    src/StageTracker.cpp
)
target_include_directories(SLRenderBridgeCore PUBLIC include)
target_compile_features(SLRenderBridgeCore PUBLIC cxx_std_17)

if(MSVC)
    target_compile_options(SLRenderBridgeCore PRIVATE /W4 /permissive-)
else()
    target_compile_options(SLRenderBridgeCore PRIVATE -Wall -Wextra -Wpedantic)
endif()

if(SLRB_BUILD_ADDON)
    if(NOT WIN32)
        message(FATAL_ERROR "SLRenderBridge.addon64 is a Windows-only target")
    endif()
    if(NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
        message(FATAL_ERROR "Firestorm/ReShade target is 64-bit; configure an x64 build")
    endif()
    if(NOT EXISTS "${RESHADE_SDK_DIR}/include/reshade.hpp")
        message(FATAL_ERROR "Set RESHADE_SDK_DIR to a ReShade checkout (API 20 expected)")
    endif()
    if(NOT EXISTS "${RESHADE_SDK_DIR}/deps/imgui/imgui.h")
        message(FATAL_ERROR "ReShade ImGui headers not found under RESHADE_SDK_DIR/deps/imgui")
    endif()

    add_library(SLRenderBridge MODULE src/Addon.cpp)
    target_link_libraries(SLRenderBridge PRIVATE SLRenderBridgeCore)
    target_include_directories(SLRenderBridge PRIVATE
        "${RESHADE_SDK_DIR}/include"
        "${RESHADE_SDK_DIR}/deps/imgui"
    )
    target_compile_features(SLRenderBridge PRIVATE cxx_std_17)
    target_compile_definitions(SLRenderBridge PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
    if(MSVC)
        target_compile_options(SLRenderBridge PRIVATE /W4 /permissive- /EHsc)
    endif()
    set_target_properties(SLRenderBridge PROPERTIES PREFIX "" SUFFIX ".addon64")
endif()

if(SLRB_BUILD_TESTS)
    enable_testing()
    add_executable(SLRenderBridgeCoreTests tests/BridgeCoreTests.cpp)
    target_link_libraries(SLRenderBridgeCoreTests PRIVATE SLRenderBridgeCore)
    target_compile_features(SLRenderBridgeCoreTests PRIVATE cxx_std_17)
    add_test(NAME SLRenderBridgeCoreTests COMMAND SLRenderBridgeCoreTests)
endif()
