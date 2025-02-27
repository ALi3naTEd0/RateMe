# Project-level configuration.
cmake_minimum_required(VERSION 3.10)
project(runner LANGUAGES CXX)
project(runner LANGUAGES CXX)
cmake_policy(SET CMP0079 NEW)
r the application. Change this to change
# The name of the executable created for the application. Change this to changer application.
# the on-disk name of your application.
set(BINARY_NAME "rateme")plication. See:
# The unique GTK application identifier for this application. See:plicationID
# https://wiki.gnome.org/HowDoI/ChooseApplicationIDset(APPLICATION_ID "com.example.rateme")
set(APPLICATION_ID "com.example.rateme")
to modern CMake behaviors to avoid warnings with recent
# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.cmake_policy(SET CMP0063 NEW)
cmake_policy(SET CMP0063 NEW)
 directory relative to the binary.
# Load bundled libraries from the lib/ directory relative to the binary.set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")
set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")
g.
# Root filesystem for cross-building.
if(FLUTTER_TARGET_PLATFORM_SYSROOT)M_SYSROOT})
  set(CMAKE_SYSROOT ${FLUTTER_TARGET_PLATFORM_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH ${CMAKE_SYSROOT}))
  set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
  set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)MAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)endif()
endif()

# Configure build options.LTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)TYPES "Debug;Profile;Release"
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"CHE STRING "" FORCE)
    CACHE STRING "" FORCE)
else()E_CONFIGURATION_TYPES)
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)_TYPE PROPERTY STRINGS
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGSbug" "Profile" "Release")
      "Debug" "Profile" "Release")()
  endif()endif()
endif()
 Compilation settings that should be applied to most targets.
# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by should add new options to specific targets instead
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_14)
  target_compile_options(${TARGET} PRIVATE -Wall -Werror)
  target_compile_options(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:-O3>")ile_definitions(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:NDEBUG>")
  target_compile_definitions(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:NDEBUG>")endfunction()
endfunction()

# Flutter library and tool build rules._SOURCE_DIR}/flutter")
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")add_subdirectory(${FLUTTER_MANAGED_DIR})
add_subdirectory(${FLUTTER_MANAGED_DIR})

# System-level dependencies.
find_package(PkgConfig REQUIRED)pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)
pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)
unner/CMakeLists.txt.
# Application build; see runner/CMakeLists.txt.add_subdirectory("runner")
add_subdirectory("runner")
s must not be removed.
# Run the Flutter tool portions of the build. This must not be removed.add_dependencies(${BINARY_NAME} flutter_assemble)
add_dependencies(${BINARY_NAME} flutter_assemble)

# Only the install-generated bundle's copy of the executable will launchd
# correctly, since the resources must in the right relative locations. To avoidled copy, put it in a subdirectory instead of
# people trying to run the unbundled copy, put it in a subdirectory instead of
# the default top-level location.roperties(${BINARY_NAME}
set_target_properties(${BINARY_NAME}
  PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/intermediates_do_not_run"
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/intermediates_do_not_run")
)

ules, which manage building the plugins and adding
# Generated plugin build rules, which manage building the plugins and adding
# them to the application.include(flutter/generated_plugins.cmake)
include(flutter/generated_plugins.cmake)


# === Installation ===, "installing" just makes a relocatable bundle in the build
# By default, "installing" just makes a relocatable bundle in the build
# directory.e")
set(BUILD_BUNDLE_DIR "${CMAKE_BINARY_DIR}/bundle")set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}")
set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}")

install(TARGETS ${BINARY_NAME} "${CMAKE_INSTALL_PREFIX}"
  RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}" .
  BUNDLE DESTINATION .  COMPONENT Runtime)
  COMPONENT Runtime)
/data")
install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${CMAKE_INSTALL_PREFIX}/data")install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${CMAKE_INSTALL_PREFIX}/lib")
install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${CMAKE_INSTALL_PREFIX}/lib")
DLED_LIBRARIES})
foreach(bundled_library ${PLUGIN_BUNDLED_LIBRARIES})
  install(FILES "${bundled_library}"KE_INSTALL_PREFIX}/lib"
    DESTINATION "${CMAKE_INSTALL_PREFIX}/lib"
    COMPONENT Runtime)endforeach(bundled_library)
endforeach(bundled_library)
ages.
# Copy the native assets provided by the build.dart from all packages.IR}native_assets/linux/")
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/linux/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"KE_INSTALL_PREFIX}/lib"
   DESTINATION "${CMAKE_INSTALL_PREFIX}/lib"   COMPONENT Runtime)
   COMPONENT Runtime)
 directory on each build to avoid having stale files
# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.SET_DIR_NAME "flutter_assets")
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "\"${CMAKE_INSTALL_PREFIX}/data/${FLUTTER_ASSET_DIR_NAME}\")
  file(REMOVE_RECURSE \"${CMAKE_INSTALL_PREFIX}/data/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)E}"
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"  DESTINATION "${CMAKE_INSTALL_PREFIX}/data" COMPONENT Runtime)
  DESTINATION "${CMAKE_INSTALL_PREFIX}/data" COMPONENT Runtime)
uilds only.
# Install the AOT library on non-Debug builds only.
if(NOT CMAKE_BUILD_TYPE MATCHES "Debug")_LIBRARY}" DESTINATION "${CMAKE_INSTALL_PREFIX}/lib"
  install(FILES "${AOT_LIBRARY}" DESTINATION "${CMAKE_INSTALL_PREFIX}/lib"PONENT Runtime)


endif()    COMPONENT Runtime)endif()