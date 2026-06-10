cmake_minimum_required(VERSION 3.20)
project(lez_wallet_module VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# --- Logos SDK (set by `nix develop` via LOGOS_CPP_SDK_ROOT) ---
if(NOT LOGOS_CPP_SDK_ROOT AND DEFINED ENV{LOGOS_CPP_SDK_ROOT})
    set(LOGOS_CPP_SDK_ROOT "$ENV{LOGOS_CPP_SDK_ROOT}")
endif()

# Precompiled Logos SDK library (provides LogosProviderBase, LogosProviderObject, etc.)
find_package(logos-cpp-sdk QUIET)
if(NOT logos-cpp-sdk_FOUND)
    # Manual fallback: look for liblogos_sdk.a alongside the generator
    if(LOGOS_CPP_SDK_ROOT)
        set(LOGOS_SDK_LIB_HINT "${LOGOS_CPP_SDK_ROOT}/../logos-cpp-sdk-lib-0.1.0")
        find_library(LOGOS_SDK_LIB NAMES logos_sdk
            HINTS "${LOGOS_SDK_LIB_HINT}/lib" "${LOGOS_CPP_SDK_ROOT}/lib"
        )
    endif()
endif()

# --- Qt6 ---
find_package(Qt6 REQUIRED COMPONENTS Core RemoteObjects)

# --- nlohmann/json (available in the nix shell via NIXPKGS_CMAKE_PREFIX_PATH) ---
find_package(nlohmann_json QUIET)

# --- lez-wallet-core Rust library ---
set(LEZ_WALLET_CORE_DIR "" CACHE PATH "Path to lez-wallet-core/target/release/")
if(NOT LEZ_WALLET_CORE_DIR AND DEFINED ENV{LEZ_WALLET_CORE_DIR})
    set(LEZ_WALLET_CORE_DIR "$ENV{LEZ_WALLET_CORE_DIR}")
endif()
if(NOT LEZ_WALLET_CORE_DIR)
    message(FATAL_ERROR "Set -DLEZ_WALLET_CORE_DIR=<path/to/lez-wallet-core/target/release> or export LEZ_WALLET_CORE_DIR")
endif()

set(LEZ_WALLET_CORE_LIB
    "${LEZ_WALLET_CORE_DIR}/${CMAKE_STATIC_LIBRARY_PREFIX}lez_wallet_core${CMAKE_STATIC_LIBRARY_SUFFIX}"
)
if(NOT EXISTS "${LEZ_WALLET_CORE_LIB}")
    message(FATAL_ERROR "liblez_wallet_core not found at ${LEZ_WALLET_CORE_LIB}. Run: cargo build --release --features lez-bridge")
endif()

# cbindgen-generated FFI header (must exist before cmake).
set(FFI_HEADER "${CMAKE_CURRENT_SOURCE_DIR}/lez_wallet_ffi.h")
if(NOT EXISTS "${FFI_HEADER}")
    message(WARNING "FFI header not found at ${FFI_HEADER}. Run: cbindgen --lang C --output qt-module/lez_wallet_ffi.h from lez-wallet-core/")
endif()

# --- logos-cpp-generator codegen ---
find_program(LOGOS_CPP_GENERATOR logos-cpp-generator)
if(LOGOS_CPP_GENERATOR)
    set(GENERATED_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated")
    file(MAKE_DIRECTORY "${GENERATED_DIR}")

    set(SDK_GENERATED_DIR "${CMAKE_CURRENT_BINARY_DIR}/sdk_generated")
    file(MAKE_DIRECTORY "${SDK_GENERATED_DIR}")

    # Pass 1: module-specific glue (qt_glue.h, dispatch.cpp, events.cpp)
    add_custom_command(
        OUTPUT
            "${GENERATED_DIR}/lez_wallet_module_qt_glue.h"
            "${GENERATED_DIR}/lez_wallet_module_dispatch.cpp"
            "${GENERATED_DIR}/lez_wallet_module_events.cpp"
        COMMAND ${LOGOS_CPP_GENERATOR}
            --from-header "${CMAKE_CURRENT_SOURCE_DIR}/src/lez_wallet_module_impl.h"
            --impl-class LezWalletModuleImpl
            --backend qt
            --metadata "${CMAKE_CURRENT_SOURCE_DIR}/metadata.json"
            --output-dir "${GENERATED_DIR}/"
        DEPENDS
            src/lez_wallet_module_impl.h
            metadata.json
        COMMENT "Running logos-cpp-generator (module pass) for lez_wallet_module"
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
        COMMENT "Running logos-cpp-generator (sdk pass) for lez_wallet_module"
    )

    set(GENERATED_SOURCES
        "${GENERATED_DIR}/lez_wallet_module_dispatch.cpp"
        "${GENERATED_DIR}/lez_wallet_module_events.cpp"
        "${SDK_GENERATED_DIR}/logos_sdk.cpp"
    )
    set(GENERATED_INCLUDE_DIRS "${GENERATED_DIR}" "${SDK_GENERATED_DIR}")
else()
    message(WARNING "logos-cpp-generator not found. Run inside `nix develop`.")
    set(GENERATED_SOURCES "")
    set(GENERATED_INCLUDE_DIRS "")
endif()

# --- Plugin target ---
add_library(lez_wallet_module_plugin MODULE
    src/lez_wallet_module_impl.cpp
    ${GENERATED_SOURCES}
)

target_include_directories(lez_wallet_module_plugin PRIVATE
    src/
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${GENERATED_INCLUDE_DIRS}
)

# Logos SDK headers (LogosModuleContext, logos_types, interface.h, logos_result.h, etc.)
if(LOGOS_CPP_SDK_ROOT)
    target_include_directories(lez_wallet_module_plugin PRIVATE
        "${LOGOS_CPP_SDK_ROOT}/include"
        "${LOGOS_CPP_SDK_ROOT}/include/core"
        "${LOGOS_CPP_SDK_ROOT}/include/cpp"
    )
endif()

target_link_libraries(lez_wallet_module_plugin PRIVATE
    Qt6::Core
    Qt6::RemoteObjects
    ${LEZ_WALLET_CORE_LIB}
)

if(nlohmann_json_FOUND)
    target_link_libraries(lez_wallet_module_plugin PRIVATE nlohmann_json::nlohmann_json)
endif()

# Logos SDK lib (LogosProviderBase, LogosProviderObject, LogosResult streaming ops)
if(logos-cpp-sdk_FOUND)
    target_link_libraries(lez_wallet_module_plugin PRIVATE logos-cpp-sdk::logos_sdk)
elseif(LOGOS_SDK_LIB)
    target_link_libraries(lez_wallet_module_plugin PRIVATE "${LOGOS_SDK_LIB}")
endif()

if(APPLE)
    target_link_libraries(lez_wallet_module_plugin PRIVATE
        "-framework Security"
        "-framework CoreFoundation"
    )
elseif(UNIX)
    target_link_libraries(lez_wallet_module_plugin PRIVATE dl pthread)
endif()

# --- Install ---
install(TARGETS lez_wallet_module_plugin LIBRARY DESTINATION lib/)
install(FILES metadata.json DESTINATION .)
