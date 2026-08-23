cmake_minimum_required(VERSION 3.20)
project(SLAlphaGTAOHook VERSION 1.1 LANGUAGES CXX)

if(NOT WIN32)
    message(FATAL_ERROR "SLAlphaGTAOHook is a Windows ReShade add-on and must be built on Windows.")
endif()

set(RESHADE_DIR "" CACHE PATH "Path to the crosire/reshade source checkout")

if(NOT EXISTS "${RESHADE_DIR}/include/reshade.hpp")
    message(FATAL_ERROR "RESHADE_DIR must point to the ReShade source folder containing include/reshade.hpp.")
endif()
if(NOT EXISTS "${RESHADE_DIR}/deps/imgui/imgui.h")
    message(FATAL_ERROR "ReShade deps/imgui/imgui.h is missing. Clone ReShade with submodules.")
endif()

add_library(SLAlphaGTAOHook SHARED
    SLAlphaGTAOHook.cpp
    SLDirectGTAO.cpp
    SLDirectGTAOShaders.hpp
)
target_compile_features(SLAlphaGTAOHook PRIVATE cxx_std_17)
target_include_directories(SLAlphaGTAOHook PRIVATE
    "${RESHADE_DIR}/include"
    "${RESHADE_DIR}/deps/imgui"
)
target_compile_definitions(SLAlphaGTAOHook PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
if(MSVC)
    target_compile_options(SLAlphaGTAOHook PRIVATE /W4 /permissive-)
endif()
target_link_libraries(SLAlphaGTAOHook PRIVATE
    opengl32
)

set_target_properties(SLAlphaGTAOHook PROPERTIES PREFIX "" OUTPUT_NAME "SLAlphaGTAOHook" SUFFIX ".addon")
