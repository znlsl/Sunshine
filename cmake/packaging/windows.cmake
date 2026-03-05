# windows specific packaging
install(TARGETS sunshine RUNTIME DESTINATION "." COMPONENT application)

# Hardening: include zlib1.dll (loaded via LoadLibrary() in openssl's libcrypto.a)
install(FILES "${ZLIB}" DESTINATION "." COMPONENT application)

# Include libopus runtime DLL when linked dynamically (common with MSYS2/mingw-w64).
# Without this, Sunshine may fail to start on systems that don't have MSYS2 installed.
set(_sunshine_opus_dll "")
if(DEFINED Opus_LIBRARY AND IS_ABSOLUTE "${Opus_LIBRARY}")
    get_filename_component(_sunshine_opus_lib_dir "${Opus_LIBRARY}" DIRECTORY)
    set(_sunshine_opus_dll_candidate "${_sunshine_opus_lib_dir}/../bin/libopus-0.dll")
    if(EXISTS "${_sunshine_opus_dll_candidate}")
        set(_sunshine_opus_dll "${_sunshine_opus_dll_candidate}")
    endif()
endif()

if(NOT _sunshine_opus_dll)
    find_file(_sunshine_opus_dll
            NAMES libopus-0.dll libopus.dll opus-0.dll
            PATH_SUFFIXES bin
    )
endif()

if(_sunshine_opus_dll)
    install(FILES "${_sunshine_opus_dll}" DESTINATION "." COMPONENT application)
endif()

# Include libssp runtime DLL (used by GCC stack-protector on mingw).
set(_sunshine_libssp_dll "")
if(DEFINED CMAKE_CXX_COMPILER AND IS_ABSOLUTE "${CMAKE_CXX_COMPILER}")
    get_filename_component(_sunshine_toolchain_bin_dir "${CMAKE_CXX_COMPILER}" DIRECTORY)
    set(_sunshine_libssp_dll_candidate "${_sunshine_toolchain_bin_dir}/libssp-0.dll")
    if(EXISTS "${_sunshine_libssp_dll_candidate}")
        set(_sunshine_libssp_dll "${_sunshine_libssp_dll_candidate}")
    endif()
endif()

if(NOT _sunshine_libssp_dll)
    find_file(_sunshine_libssp_dll NAMES libssp-0.dll PATH_SUFFIXES bin)
endif()

if(_sunshine_libssp_dll)
    install(FILES "${_sunshine_libssp_dll}" DESTINATION "." COMPONENT application)
endif()

# Bundle runtime DLL dependencies (e.g. libssp-0.dll, libwinpthread-1.dll) for mingw builds.
# This keeps the portable ZIP and installers runnable on machines without MSYS2 installed.
set(_sunshine_bundle_deps_script "${CMAKE_BINARY_DIR}/bundle-runtime-deps.cmake")
set(_sunshine_runtime_search_dirs "")
if(DEFINED CMAKE_CXX_COMPILER AND IS_ABSOLUTE "${CMAKE_CXX_COMPILER}")
    get_filename_component(_sunshine_toolchain_bin_dir "${CMAKE_CXX_COMPILER}" DIRECTORY)
    cmake_path(CONVERT "${_sunshine_toolchain_bin_dir}" TO_CMAKE_PATH_LIST _sunshine_toolchain_bin_dir)
    set(_sunshine_runtime_search_dirs "${_sunshine_toolchain_bin_dir}")
endif()

set(_sunshine_bundle_deps_script_content [==[
set(_sunshine_runtime_search_dirs "@SUNSHINE_RUNTIME_SEARCH_DIRS@")

set(_sunshine_runtime_targets
  "$<TARGET_FILE:sunshine>|."
  "$<TARGET_FILE:sunshinesvc>|tools"
  "$<TARGET_FILE:audio-info>|tools"
  "$<TARGET_FILE:dxgi-info>|tools"
)

foreach(_pair IN LISTS _sunshine_runtime_targets)
  string(REPLACE "|" ";" _parts "${_pair}")
  list(GET _parts 0 _exe)
  list(GET _parts 1 _dest)

  if(NOT EXISTS "${_exe}")
    message(STATUS "bundle-runtime-deps: skip missing '${_exe}'")
    continue()
  endif()

  if(_sunshine_runtime_search_dirs)
    file(GET_RUNTIME_DEPENDENCIES
      EXECUTABLES "${_exe}"
      RESOLVED_DEPENDENCIES_VAR _deps
      UNRESOLVED_DEPENDENCIES_VAR _udeps
      DIRECTORIES ${_sunshine_runtime_search_dirs}
      PRE_EXCLUDE_REGEXES
        "api-ms-win-.*"
        "ext-ms-win-.*"
      POST_EXCLUDE_REGEXES
        ".*[/\\\\]Windows[/\\\\](System32|SysWOW64|WinSxS)[/\\\\].*"
    )
  else()
    file(GET_RUNTIME_DEPENDENCIES
      EXECUTABLES "${_exe}"
      RESOLVED_DEPENDENCIES_VAR _deps
      UNRESOLVED_DEPENDENCIES_VAR _udeps
      PRE_EXCLUDE_REGEXES
        "api-ms-win-.*"
        "ext-ms-win-.*"
      POST_EXCLUDE_REGEXES
        ".*[/\\\\]Windows[/\\\\](System32|SysWOW64|WinSxS)[/\\\\].*"
    )
  endif()

  list(REMOVE_DUPLICATES _deps)
  foreach(_dll IN LISTS _deps)
    file(INSTALL
      DESTINATION "${CMAKE_INSTALL_PREFIX}/${_dest}"
      TYPE SHARED_LIBRARY
      FILES "${_dll}"
    )
  endforeach()

  if(_udeps)
    message(STATUS "bundle-runtime-deps: unresolved for '${_exe}': ${_udeps}")
  endif()
endforeach()
]==]
)
string(REPLACE "@SUNSHINE_RUNTIME_SEARCH_DIRS@" "${_sunshine_runtime_search_dirs}"
        _sunshine_bundle_deps_script_content "${_sunshine_bundle_deps_script_content}")

file(GENERATE
        OUTPUT "${_sunshine_bundle_deps_script}"
        CONTENT "${_sunshine_bundle_deps_script_content}"
)
install(SCRIPT "${_sunshine_bundle_deps_script}" COMPONENT application)

# ARM64: include minhook-detours DLL (shared library for ARM64)
if(NOT CMAKE_SYSTEM_PROCESSOR MATCHES "AMD64" AND DEFINED _MINHOOK_DLL)
    install(FILES "${_MINHOOK_DLL}" DESTINATION "." COMPONENT application)
endif()

# ViGEmBus installer
set(VIGEMBUS_INSTALLER "${CMAKE_BINARY_DIR}/scripts/vigembus_installer.exe")
set(VIGEMBUS_DOWNLOAD_URL_1 "https://github.com/nefarius/ViGEmBus/releases/download")
set(VIGEMBUS_DOWNLOAD_URL_2 "v${VIGEMBUS_PACKAGED_V_2}/ViGEmBus_${VIGEMBUS_PACKAGED_V}_x64_x86_arm64.exe")
file(DOWNLOAD
        "${VIGEMBUS_DOWNLOAD_URL_1}/${VIGEMBUS_DOWNLOAD_URL_2}"
        ${VIGEMBUS_INSTALLER}
        SHOW_PROGRESS
        EXPECTED_HASH SHA256=155c50f1eec07bdc28d2f61a3e3c2c6c132fee7328412de224695f89143316bc
        TIMEOUT 60
)
install(FILES ${VIGEMBUS_INSTALLER}
        DESTINATION "scripts"
        RENAME "vigembus_installer.exe"
        COMPONENT gamepad)

# Adding tools
install(TARGETS dxgi-info RUNTIME DESTINATION "tools" COMPONENT dxgi)
install(TARGETS audio-info RUNTIME DESTINATION "tools" COMPONENT audio)

# Mandatory tools
install(TARGETS sunshinesvc RUNTIME DESTINATION "tools" COMPONENT application)

# Mandatory scripts
install(FILES "${SUNSHINE_SOURCE_ASSETS_DIR}/windows/misc/sunshine-setup.ps1"
        DESTINATION "scripts"
        COMPONENT assets)
install(DIRECTORY "${SUNSHINE_SOURCE_ASSETS_DIR}/windows/misc/service/"
        DESTINATION "scripts"
        COMPONENT assets)
install(DIRECTORY "${SUNSHINE_SOURCE_ASSETS_DIR}/windows/misc/migration/"
        DESTINATION "scripts"
        COMPONENT assets)
install(DIRECTORY "${SUNSHINE_SOURCE_ASSETS_DIR}/windows/misc/path/"
        DESTINATION "scripts"
        COMPONENT assets)

# Optional helper scripts (e.g., VB-Cable installer for microphone redirection)
install(DIRECTORY "${SUNSHINE_SOURCE_ASSETS_DIR}/windows/misc/vsink/"
        DESTINATION "scripts"
        COMPONENT assets)

# Configurable options for the service
install(DIRECTORY "${SUNSHINE_SOURCE_ASSETS_DIR}/windows/misc/autostart/"
        DESTINATION "scripts"
        COMPONENT autostart)

# scripts
install(DIRECTORY "${SUNSHINE_SOURCE_ASSETS_DIR}/windows/misc/firewall/"
        DESTINATION "scripts"
        COMPONENT firewall)

# Sunshine assets
install(DIRECTORY "${SUNSHINE_SOURCE_ASSETS_DIR}/windows/assets/"
        DESTINATION "${SUNSHINE_ASSETS_DIR}"
        COMPONENT assets)

# copy assets (excluding shaders) to build directory, for running without install
file(COPY "${SUNSHINE_SOURCE_ASSETS_DIR}/windows/assets/"
        DESTINATION "${CMAKE_BINARY_DIR}/assets"
        PATTERN "shaders" EXCLUDE)
# use junction for shaders directory
cmake_path(CONVERT "${SUNSHINE_SOURCE_ASSETS_DIR}/windows/assets/shaders"
        TO_NATIVE_PATH_LIST shaders_in_build_src_native)
cmake_path(CONVERT "${CMAKE_BINARY_DIR}/assets/shaders" TO_NATIVE_PATH_LIST shaders_in_build_dest_native)
execute_process(COMMAND cmd.exe /c mklink /J "${shaders_in_build_dest_native}" "${shaders_in_build_src_native}")

set(CPACK_PACKAGE_ICON "${CMAKE_SOURCE_DIR}\\\\sunshine.ico")

# The name of the directory that will be created in C:/Program files/
set(CPACK_PACKAGE_INSTALL_DIRECTORY "${CPACK_PACKAGE_NAME}")

# Setting components groups and dependencies
set(CPACK_COMPONENT_GROUP_CORE_EXPANDED true)

# sunshine binary
set(CPACK_COMPONENT_APPLICATION_DISPLAY_NAME "${CMAKE_PROJECT_NAME}")
set(CPACK_COMPONENT_APPLICATION_DESCRIPTION "${CMAKE_PROJECT_NAME} main application and required components.")
set(CPACK_COMPONENT_APPLICATION_GROUP "Core")
set(CPACK_COMPONENT_APPLICATION_REQUIRED true)
set(CPACK_COMPONENT_APPLICATION_DEPENDS assets)

# service auto-start script
set(CPACK_COMPONENT_AUTOSTART_DISPLAY_NAME "Launch on Startup")
set(CPACK_COMPONENT_AUTOSTART_DESCRIPTION "If enabled, launches Sunshine automatically on system startup.")
set(CPACK_COMPONENT_AUTOSTART_GROUP "Core")

# assets
set(CPACK_COMPONENT_ASSETS_DISPLAY_NAME "Required Assets")
set(CPACK_COMPONENT_ASSETS_DESCRIPTION "Shaders, default box art, and web UI.")
set(CPACK_COMPONENT_ASSETS_GROUP "Core")
set(CPACK_COMPONENT_ASSETS_REQUIRED true)

# audio tool
set(CPACK_COMPONENT_AUDIO_DISPLAY_NAME "audio-info")
set(CPACK_COMPONENT_AUDIO_DESCRIPTION "CLI tool providing information about sound devices.")
set(CPACK_COMPONENT_AUDIO_GROUP "Tools")

# display tool
set(CPACK_COMPONENT_DXGI_DISPLAY_NAME "dxgi-info")
set(CPACK_COMPONENT_DXGI_DESCRIPTION "CLI tool providing information about graphics cards and displays.")
set(CPACK_COMPONENT_DXGI_GROUP "Tools")

# firewall scripts
set(CPACK_COMPONENT_FIREWALL_DISPLAY_NAME "Add Firewall Exclusions")
set(CPACK_COMPONENT_FIREWALL_DESCRIPTION "Scripts to enable or disable firewall rules.")
set(CPACK_COMPONENT_FIREWALL_GROUP "Scripts")

# gamepad scripts
set(CPACK_COMPONENT_GAMEPAD_DISPLAY_NAME "Virtual Gamepad")
set(CPACK_COMPONENT_GAMEPAD_DESCRIPTION "ViGEmBus installer for virtual gamepad support.")
set(CPACK_COMPONENT_GAMEPAD_GROUP "Scripts")

# include specific packaging
include(${CMAKE_MODULE_PATH}/packaging/windows_nsis.cmake)
include(${CMAKE_MODULE_PATH}/packaging/windows_wix.cmake)
