cmake_minimum_required(VERSION 3.20)
project(agent_module VERSION 0.0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# --- Logos SDK root (set by `nix develop` via LOGOS_CPP_SDK_ROOT) ---
if(NOT LOGOS_CPP_SDK_ROOT AND DEFINED ENV{LOGOS_CPP_SDK_ROOT})
    set(LOGOS_CPP_SDK_ROOT "$ENV{LOGOS_CPP_SDK_ROOT}")
endif()

# Precompiled Logos SDK library (provides LogosProviderBase, LogosProviderObject, etc.)
find_package(logos-cpp-sdk QUIET)
if(NOT logos-cpp-sdk_FOUND)
    if(LOGOS_CPP_SDK_ROOT)
        find_library(LOGOS_SDK_LIB NAMES logos_sdk
            HINTS "${LOGOS_CPP_SDK_ROOT}/lib"
        )
    endif()
endif()

# --- Qt6 ---
find_package(Qt6 REQUIRED COMPONENTS Core RemoteObjects)

# --- nlohmann/json ---
find_package(nlohmann_json QUIET)

# --- logos-cpp-generator codegen ---
find_program(LOGOS_CPP_GENERATOR logos-cpp-generator)
if(NOT LOGOS_CPP_GENERATOR)
    message(WARNING "logos-cpp-generator not found on PATH. Run inside `nix develop`.")
endif()

set(GENERATED_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated")
file(MAKE_DIRECTORY "${GENERATED_DIR}")

set(SDK_GENERATED_DIR "${CMAKE_CURRENT_BINARY_DIR}/sdk_generated")
file(MAKE_DIRECTORY "${SDK_GENERATED_DIR}")

if(LOGOS_CPP_GENERATOR)
    # Pass 1: module-specific glue (qt_glue.h, dispatch.cpp, events.cpp)
    add_custom_command(
        OUTPUT
            "${GENERATED_DIR}/agent_module_qt_glue.h"
            "${GENERATED_DIR}/agent_module_dispatch.cpp"
            "${GENERATED_DIR}/agent_module_events.cpp"
        COMMAND ${LOGOS_CPP_GENERATOR}
            --from-header "${CMAKE_CURRENT_SOURCE_DIR}/src/agent_module_impl.h"
            --impl-class AgentModuleImpl
            --backend qt
            --metadata "${CMAKE_CURRENT_SOURCE_DIR}/metadata.json"
            --output-dir "${GENERATED_DIR}/"
        DEPENDS
            src/agent_module_impl.h
            metadata.json
        COMMENT "Running logos-cpp-generator (module pass) for agent_module"
    )

    # Pass 2: general SDK helpers (logos_sdk.h, logos_sdk.cpp)
    add_custom_command(
        OUTPUT
            "${SDK_GENERATED_DIR}/logos_sdk.h"
            "${SDK_GENERATED_DIR}/logos_sdk.cpp"
        COMMAND ${LOGOS_CPP_GENERATOR}
            --metadata "${CMAKE_CURRENT_SOURCE_DIR}/metadata.json"
            --general-only
            --output-dir "${SDK_GENERATED_DIR}/"
        DEPENDS metadata.json
        COMMENT "Running logos-cpp-generator (sdk pass) for agent_module"
    )

    # Copy platform-module stubs into sdk_generated/ so logos_sdk.cpp can #include them.
    # The generator emits #include "chat_module_api.cpp" etc. relative to sdk_generated/.
    foreach(_stub chat_module delivery_module storage_module)
        configure_file(
            "${CMAKE_CURRENT_SOURCE_DIR}/interfaces/${_stub}_api.h"
            "${SDK_GENERATED_DIR}/${_stub}_api.h"
            COPYONLY
        )
        configure_file(
            "${CMAKE_CURRENT_SOURCE_DIR}/interfaces/${_stub}_api.cpp"
            "${SDK_GENERATED_DIR}/${_stub}_api.cpp"
            COPYONLY
        )
    endforeach()

    set(GENERATED_SOURCES
        "${GENERATED_DIR}/agent_module_dispatch.cpp"
        "${GENERATED_DIR}/agent_module_events.cpp"
        "${SDK_GENERATED_DIR}/logos_sdk.cpp"
    )
    set(GENERATED_INCLUDE_DIRS "${GENERATED_DIR}" "${SDK_GENERATED_DIR}")
else()
    set(GENERATED_SOURCES "")
    set(GENERATED_INCLUDE_DIRS "")
endif()

# --- Plugin target ---
add_library(agent_module_plugin MODULE
    src/agent_module_impl.cpp
    ${GENERATED_SOURCES}
)

target_include_directories(agent_module_plugin PRIVATE
    src/
    interfaces/
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${GENERATED_INCLUDE_DIRS}
)

if(LOGOS_CPP_SDK_ROOT)
    target_include_directories(agent_module_plugin PRIVATE
        "${LOGOS_CPP_SDK_ROOT}/include"
        "${LOGOS_CPP_SDK_ROOT}/include/core"
        "${LOGOS_CPP_SDK_ROOT}/include/cpp"
    )
endif()

target_link_libraries(agent_module_plugin PRIVATE
    Qt6::Core
    Qt6::RemoteObjects
)

if(nlohmann_json_FOUND)
    target_link_libraries(agent_module_plugin PRIVATE nlohmann_json::nlohmann_json)
endif()

if(logos-cpp-sdk_FOUND)
    target_link_libraries(agent_module_plugin PRIVATE logos-cpp-sdk::logos_sdk)
elseif(LOGOS_SDK_LIB)
    target_link_libraries(agent_module_plugin PRIVATE "${LOGOS_SDK_LIB}")
endif()

if(APPLE)
    target_link_libraries(agent_module_plugin PRIVATE
        "-framework Security"
        "-framework CoreFoundation"
    )
elseif(UNIX)
    target_link_libraries(agent_module_plugin PRIVATE dl pthread)
endif()

# --- Install ---
install(TARGETS agent_module_plugin LIBRARY DESTINATION lib/)
install(FILES metadata.json DESTINATION .)
