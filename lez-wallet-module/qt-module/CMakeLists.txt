cmake_minimum_required(VERSION 3.14)
project(LezWalletModulePlugin LANGUAGES CXX)

# Use the Logos module build helper (same path the agent_module uses). It runs
# logos-cpp-generator, links the Logos SDK + Qt, and produces the loadable plugin.
if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
else()
    message(FATAL_ERROR "LogosModule.cmake not found. Set LOGOS_MODULE_BUILDER_ROOT.")
endif()

# Prebuilt lez-bridge Rust core (committed in ./corelib/liblez_wallet_core.a).
# LEZ_WALLET_CORE_DIR is exported by the flake's preConfigure.
if(NOT LEZ_WALLET_CORE_DIR AND DEFINED ENV{LEZ_WALLET_CORE_DIR})
    set(LEZ_WALLET_CORE_DIR "$ENV{LEZ_WALLET_CORE_DIR}")
endif()
set(LEZ_WALLET_CORE_LIB "${LEZ_WALLET_CORE_DIR}/liblez_wallet_core.a")
if(NOT EXISTS "${LEZ_WALLET_CORE_LIB}")
    message(FATAL_ERROR "liblez_wallet_core.a not found at ${LEZ_WALLET_CORE_LIB}")
endif()

logos_module(
    NAME lez_wallet_module
    SOURCES
        src/lez_wallet_module_impl.h
        src/lez_wallet_module_impl.cpp
    INCLUDE_DIRS
        .
        src
    LINK_LIBRARIES
        ${LEZ_WALLET_CORE_LIB}
        dl
        pthread
)
