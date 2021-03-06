
set(proj SimpleITK)

# Set dependency list
set(${proj}_DEPENDENCIES ITKv4 Swig python python-setuptools)

# Include dependent projects if any
ExternalProject_Include_Dependencies(${proj} PROJECT_VAR proj DEPENDS_VAR ${proj}_DEPENDENCIES)

if(${CMAKE_PROJECT_NAME}_USE_SYSTEM_${proj})
  message(FATAL_ERROR "Enabling ${CMAKE_PROJECT_NAME}_USE_SYSTEM_${proj} is not supported !")
endif()

# Sanity checks
if(DEFINED SimpleITK_DIR AND NOT EXISTS ${SimpleITK_DIR})
  message(FATAL_ERROR "SimpleITK_DIR variable is defined but corresponds to nonexistent directory")
endif()

if(NOT ${CMAKE_PROJECT_NAME}_USE_SYSTEM_${proj})

  include(ExternalProjectForNonCMakeProject)

  # environment
  set(_env_script ${CMAKE_BINARY_DIR}/${proj}_Env.cmake)
  ExternalProject_Write_SetPythonSetupEnv_Commands(${_env_script})

  # install step - the working path must be set to the location of the SimpleITK.py
  # file so that it will be picked up by distuils setup, and installed
  set(_install_script ${CMAKE_BINARY_DIR}/${proj}_install_step.cmake)
  file(WRITE ${_install_script}
"include(\"${_env_script}\")
set(${proj}_WORKING_DIR \"${CMAKE_BINARY_DIR}/${proj}-build/SimpleITK-build/Wrapping/Python\")
ExternalProject_Execute(${proj} \"install\" \"${PYTHON_EXECUTABLE}\" Packaging/setup.py install)
")

  ExternalProject_SetIfNotDefined(
    ${CMAKE_PROJECT_NAME}_${proj}_GIT_REPOSITORY
    "${git_protocol}://itk.org/SimpleITK.git"
    QUIET
    )

  ExternalProject_SetIfNotDefined(
    ${CMAKE_PROJECT_NAME}_${proj}_GIT_TAG
    "699ed4bb8934b83ee3bb4a6633b547291f0347ce"
    QUIET
    )

  set(EP_SOURCE_DIR ${CMAKE_BINARY_DIR}/${proj})
  set(EP_BINARY_DIR ${CMAKE_BINARY_DIR}/${proj}-build)
  set(EP_INSTALL_DIR ${CMAKE_BINARY_DIR}/${proj}-install)


  # A separate project is used to download, so that the SuperBuild
  # subdirectory can be use for SimpleITK's SuperBuild to build
  # required Lua, GTest etc. dependencies not in Slicer SuperBuild
  ExternalProject_add(SimpleITK-download
    SOURCE_DIR ${EP_SOURCE_DIR}
    GIT_REPOSITORY "${${CMAKE_PROJECT_NAME}_${proj}_GIT_REPOSITORY}"
    GIT_TAG "${${CMAKE_PROJECT_NAME}_${proj}_GIT_TAG}"
    CONFIGURE_COMMAND ""
    INSTALL_COMMAND ""
    BUILD_COMMAND ""
    )

  ExternalProject_GenerateProjectDescription_Step(SimpleITK-download
    SOURCE_DIR ${EP_SOURCE_DIR}
    NAME ${proj}
    )

  set(EXTERNAL_PROJECT_OPTIONAL_ARGS)
  if(CMAKE_CXX_STANDARD EQUAL 11 OR CMAKE_CXX_STANDARD LESS 30)
    #
    # Since SimpleITK requires C++11 with libc++ ( vs. libstdc++ ), we let
    # it's build system figure out the correct set of flags.
    #
    # From Brad:
    #   "Compiling ITK with C++98 while compiling SimpleITK C++11,
    #   is not ideal, but all the tests seem to pass for the wrapping.
    #   That said, there may be a problem if the SimpleITK C++ interface
    #   is used with this mixing of C++ standards."
    #
    # More details here: https://discourse.slicer.org/t/cannot-compile-slicer-on-mac-macos-sierra-clang-9-cmake-3-9-1/1104/9
    #

    if(CMAKE_VERSION VERSION_LESS "3.8.2")
      message(FATAL_ERROR "Since SimpleITK requires CMP0067 to properly support C++11, "
                          "CMake >= 3.8.2 is required to configure ${PROJECT_NAME}: "
                          "Current CMake version is [${CMAKE_VERSION}]")
    endif()

    list(APPEND EXTERNAL_PROJECT_OPTIONAL_ARGS
      -DCMAKE_CXX_STANDARD:STRING=${CMAKE_CXX_STANDARD}
      -DCMAKE_CXX_STANDARD_REQUIRED:BOOL=${CMAKE_CXX_STANDARD_REQUIRED}
      -DCMAKE_CXX_EXTENSIONS:BOOL=${CMAKE_CXX_EXTENSIONS}
      )
  endif()

  ExternalProject_add(SimpleITK
    ${${proj}_EP_ARGS}
    SOURCE_DIR ${EP_SOURCE_DIR}/SuperBuild
    BINARY_DIR ${EP_BINARY_DIR}
    INSTALL_DIR ${EP_INSTALL_DIR}
    DOWNLOAD_COMMAND ""
    UPDATE_COMMAND ""
    CMAKE_CACHE_ARGS
      -DCMAKE_CXX_COMPILER:FILEPATH=${CMAKE_CXX_COMPILER}
      -DCMAKE_CXX_FLAGS:STRING=${ep_common_cxx_flags}
      -DCMAKE_C_COMPILER:FILEPATH=${CMAKE_C_COMPILER}
      -DCMAKE_C_FLAGS:STRING=${ep_common_c_flags}
      ${EXTERNAL_PROJECT_OPTIONAL_ARGS}
      -DBUILD_SHARED_LIBS:BOOL=${Slicer_USE_SimpleITK_SHARED}
      -DBUILD_EXAMPLES:BOOL=OFF
      -DSimpleITK_PYTHON_THREADS:BOOL=ON
      -DSimpleITK_INSTALL_ARCHIVE_DIR:PATH=${Slicer_INSTALL_LIB_DIR}
      -DSimpleITK_INSTALL_LIBRARY_DIR:PATH=${Slicer_INSTALL_LIB_DIR}
      -DSimpleITK_INT64_PIXELIDS:BOOL=OFF
      -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
      -DSimpleITK_USE_SYSTEM_ITK:BOOL=ON
      -DITK_DIR:PATH=${ITK_DIR}
      -DSimpleITK_USE_SYSTEM_SWIG:BOOL=ON
      -DSWIG_EXECUTABLE:PATH=${SWIG_EXECUTABLE}
      -DPYTHON_EXECUTABLE:PATH=${PYTHON_EXECUTABLE}
      -DPYTHON_LIBRARY:FILEPATH=${PYTHON_LIBRARY}
      -DPYTHON_INCLUDE_DIR:PATH=${PYTHON_INCLUDE_DIR}
      -DBUILD_TESTING:BOOL=OFF
      -DBUILD_DOXYGEN:BOOL=OFF
      -DWRAP_DEFAULT:BOOL=OFF
      -DWRAP_PYTHON:BOOL=ON
      -DSimpleITK_BUILD_DISTRIBUTE:BOOL=ON # Shorten version and install path removing -g{GIT-HASH} suffix.
      -DExternalData_OBJECT_STORES:PATH=${ExternalData_OBJECT_STORES}
      # macOS
      -DCMAKE_MACOSX_RPATH:BOOL=0
    #
    INSTALL_COMMAND ${CMAKE_COMMAND} -P ${_install_script}
    #
    DEPENDS SimpleITK-download ${${proj}_DEPENDENCIES}
    )
  set(SimpleITK_DIR ${CMAKE_BINARY_DIR}/SimpleITK-build/SimpleITK-build)

  set(_lib_subdir lib)
  if(WIN32)
    set(_lib_subdir bin)
  endif()

  #-----------------------------------------------------------------------------
  # Launcher setting specific to build tree

  set(${proj}_LIBRARY_PATHS_LAUNCHER_BUILD ${SimpleITK_DIR}/${_lib_subdir}/<CMAKE_CFG_INTDIR>)
  mark_as_superbuild(
    VARS ${proj}_LIBRARY_PATHS_LAUNCHER_BUILD
    LABELS "LIBRARY_PATHS_LAUNCHER_BUILD"
    )

else()
  ExternalProject_Add_Empty(${proj} DEPENDS ${${proj}_DEPENDENCIES})
endif()

mark_as_superbuild(
  VARS SimpleITK_DIR:PATH
  LABELS "FIND_PACKAGE"
  )
