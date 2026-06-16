cmake_minimum_required(VERSION 3.20)
project(agent_module VERSION 0.0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Required for Q_OBJECT / Q_PLUGIN_METADATA in generated glue header
set(CMAKE_AUTOMOC ON)
set(CMAKE_INCLUDE_CURRENT_DIR ON)

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

# --- LEZ wallet plugin (for generating client binding) ---
if(NOT LEZ_WALLET_PLUGIN AND DEFINED ENV{LEZ_WALLET_PLUGIN})
    set(LEZ_WALLET_PLUGIN "$ENV{LEZ_WALLET_PLUGIN}")
endif()

set(GENERATED_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated")
file(MAKE_DIRECTORY "${GENERATED_DIR}")

set(SDK_GENERATED_DIR "${CMAKE_CURRENT_BINARY_DIR}/sdk_generated")
file(MAKE_DIRECTORY "${SDK_GENERATED_DIR}")

if(LOGOS_CPP_GENERATOR)
    # Pass 1: module-specific glue (qt_glue.h, dispatch.cpp)
    add_custom_command(
        OUTPUT
            "${GENERATED_DIR}/agent_module_qt_glue.h"
            "${GENERATED_DIR}/agent_module_dispatch.cpp"
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

    # Pass 2: generate platform sdk + logos_sdk.h from metadata dependencies.
    add_custom_command(
        OUTPUT
            "${SDK_GENERATED_DIR}/core_manager_api.h"
            "${SDK_GENERATED_DIR}/core_manager_api.cpp"
            "${SDK_GENERATED_DIR}/logos_sdk_platform.h"
            "${SDK_GENERATED_DIR}/logos_sdk_platform.cpp"
        COMMAND ${LOGOS_CPP_GENERATOR}
            --metadata "${CMAKE_CURRENT_SOURCE_DIR}/metadata.json"
            --general-only
            --output-dir "${SDK_GENERATED_DIR}/platform_tmp/"
        # Rename the platform logos_sdk.h to logos_sdk_platform.h
        COMMAND ${CMAKE_COMMAND} -E copy
            "${SDK_GENERATED_DIR}/platform_tmp/logos_sdk.h"
            "${SDK_GENERATED_DIR}/logos_sdk_platform.h"
        COMMAND ${CMAKE_COMMAND} -E copy
            "${SDK_GENERATED_DIR}/platform_tmp/logos_sdk.cpp"
            "${SDK_GENERATED_DIR}/logos_sdk_platform.cpp"
        COMMAND ${CMAKE_COMMAND} -E copy
            "${SDK_GENERATED_DIR}/platform_tmp/core_manager_api.h"
            "${SDK_GENERATED_DIR}/core_manager_api.h"
        COMMAND ${CMAKE_COMMAND} -E copy
            "${SDK_GENERATED_DIR}/platform_tmp/core_manager_api.cpp"
            "${SDK_GENERATED_DIR}/core_manager_api.cpp"
        DEPENDS metadata.json
        COMMENT "Running logos-cpp-generator (platform sdk pass) for agent_module"
    )

    # Pass 3: generate wallet client binding from the built wallet plugin .so.
    if(LEZ_WALLET_PLUGIN)
        add_custom_command(
            OUTPUT
                "${SDK_GENERATED_DIR}/lez_wallet_module_api.h"
                "${SDK_GENERATED_DIR}/lez_wallet_module_api.cpp"
            COMMAND ${LOGOS_CPP_GENERATOR}
                "${LEZ_WALLET_PLUGIN}"
                --output-dir "${SDK_GENERATED_DIR}/wallet_tmp/"
            COMMAND ${CMAKE_COMMAND} -E copy
                "${SDK_GENERATED_DIR}/wallet_tmp/lez_wallet_module_api.h"
                "${SDK_GENERATED_DIR}/lez_wallet_module_api.h"
            COMMAND ${CMAKE_COMMAND} -E copy
                "${SDK_GENERATED_DIR}/wallet_tmp/lez_wallet_module_api.cpp"
                "${SDK_GENERATED_DIR}/lez_wallet_module_api.cpp"
            DEPENDS "${LEZ_WALLET_PLUGIN}"
            COMMENT "Running logos-cpp-generator (wallet binding pass) for agent_module"
        )
        set(WALLET_BINDING_SOURCES
            "${SDK_GENERATED_DIR}/lez_wallet_module_api.h"
            "${SDK_GENERATED_DIR}/lez_wallet_module_api.cpp"
        )
    else()
        set(WALLET_BINDING_SOURCES "")
        message(WARNING "LEZ_WALLET_PLUGIN not set; wallet binding not generated. Set -DLEZ_WALLET_PLUGIN=/path/to/liblez_wallet_module_plugin.so")
    endif()

    # Copy platform-module stubs into sdk_generated/ so logos_sdk.cpp can #include them.
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

    # Copy metadata.json next to the generated qt_glue.h so moc can resolve FILE "metadata.json"
    configure_file("${CMAKE_CURRENT_SOURCE_DIR}/metadata.json" "${GENERATED_DIR}/metadata.json" COPYONLY)

    # Create the combined logos_sdk.h that includes both platform modules and the wallet binding.
    # This is written as a configure_file template so cmake generates it at configure time.
    file(WRITE "${SDK_GENERATED_DIR}/logos_sdk.h"
        "#pragma once\n"
        "#include \"logos_api.h\"\n"
        "#include \"logos_api_client.h\"\n"
        "\n"
        "#include \"core_manager_api.h\"\n"
        "#include \"chat_module_api.h\"\n"
        "#include \"delivery_module_api.h\"\n"
        "#include \"storage_module_api.h\"\n"
        "#include \"lez_wallet_module_api.h\"\n"
        "\n"
        "struct LogosModules {\n"
        "    explicit LogosModules(LogosAPI* api) : api(api),\n"
        "        core_manager(api),\n"
        "        chat_module(api),\n"
        "        delivery_module(api),\n"
        "        storage_module(api),\n"
        "        lez_wallet_module(api) {}\n"
        "    LogosAPI* api;\n"
        "    CoreManager core_manager;\n"
        "    ChatModule chat_module;\n"
        "    DeliveryModule delivery_module;\n"
        "    StorageModule storage_module;\n"
        "    LezWalletModule lez_wallet_module;\n"
        "};\n"
    )
    file(WRITE "${SDK_GENERATED_DIR}/logos_sdk.cpp" "// combined sdk - platform + wallet\n")

    set(GENERATED_SOURCES
        "${GENERATED_DIR}/agent_module_qt_glue.h"
        "${GENERATED_DIR}/agent_module_dispatch.cpp"
        "${SDK_GENERATED_DIR}/core_manager_api.h"
        "${SDK_GENERATED_DIR}/core_manager_api.cpp"
        ${WALLET_BINDING_SOURCES}
    )
    set_source_files_properties("${GENERATED_DIR}/agent_module_qt_glue.h" PROPERTIES GENERATED TRUE)
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

# Logos SDK source headers (logos_module_context.h, logos_result.h, logos_types.h, etc.)
if(LOGOS_CPP_SDK_SRC)
    target_include_directories(agent_module_plugin PRIVATE
        "${LOGOS_CPP_SDK_SRC}/cpp"
        "${LOGOS_CPP_SDK_SRC}/core"
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
