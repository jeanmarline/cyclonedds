#
# Copyright(c) 2006 to 2018 ADLINK Technology Limited and others
#
# This program and the accompanying materials are made available under the
# terms of the Eclipse Public License v. 2.0 which is available at
# http://www.eclipse.org/legal/epl-2.0, or the Eclipse Distribution License
# v. 1.0 which is available at
# http://www.eclipse.org/org/documents/edl-v10.php.
#
# SPDX-License-Identifier: EPL-2.0 OR BSD-3-Clause
#
find_package(CUnit REQUIRED)

include(Glob)

set(CUNIT_DIR "${CMAKE_CURRENT_LIST_DIR}/CUnit")

function(add_cunit_executable target)
  # Retrieve location of shared libary, which is need to extend the PATH
  # environment variable on Microsoft Windows, so that the operating
  # system can locate the .dll that it was linked against.
  # On macOS, this mechanism is used to set the DYLD_LIBRARY_PATH.
  get_target_property(CUNIT_LIBRARY_TYPE CUnit TYPE)
  get_target_property(CUNIT_IMPORTED_LOCATION CUnit IMPORTED_LOCATION)
  get_filename_component(CUNIT_LIBRARY_DIR "${CUNIT_IMPORTED_LOCATION}" PATH)

  # Generate semi-random filename to store the generated code in to avoid
  # possible naming conflicts.
  string(RANDOM random)
  set(runner "${target}_${random}")

  set(s "[ \t\r\n]") # space
  set(w "[0-9a-zA-Z_]") # word
  set(param "${s}*(${w}+)${s}*")
  set(pattern "CUnit_${w}+${s}*\\(${param}(,${param}(,${param})?)?\\)")

  glob(filenames "c" ${ARGN})

  foreach(filename ${filenames})
    file(READ "${filename}" contents)
    string(REGEX MATCHALL "${pattern}" captures "${contents}")

    list(APPEND sources "${filename}")
    list(LENGTH captures length)
    if(length)
      foreach(capture ${captures})
        string(REGEX REPLACE "${pattern}" "\\1" suite "${capture}")

        if("${capture}" MATCHES "CUnit_Suite_Initialize")
          list(APPEND suites ${suite})
          list(APPEND suites_w_init ${suite})
        elseif("${capture}" MATCHES "CUnit_Suite_Cleanup")
          list(APPEND suites ${suite})
          list(APPEND suites_w_deinit ${suite})
        elseif("${capture}" MATCHES "CUnit_Test")
          list(APPEND suites ${suite})

          # Specifying a test name is mandatory
          if("${capture}" MATCHES ",")
            string(REGEX REPLACE "${pattern}" "\\3" test "${capture}")
          else()
            message(FATAL_ERROR "Bad CUnit_Test signature in ${filename}")
          endif()

          # Specifying if a test is enabled is optional
          set(enable "true")
          if("${capture}" MATCHES ",${param},")
            string(REGEX REPLACE "${pattern}" "\\5" enable "${capture}")
          endif()

          if((NOT "${enable}" STREQUAL "true") AND
             (NOT "${enable}" STREQUAL "false"))
            message(FATAL_ERROR "Bad CUnit_Test signature in ${filename}")
          endif()

          list(APPEND tests "${suite}:${test}:${enable}")
        else()
          message(FATAL_ERROR "Bad CUnit signature in ${filename}")
        endif()
      endforeach()
    endif()
  endforeach()

  # Test suite signatures can be decided on only after everything is parsed.
  set(lf "\n")
  set(declf "")
  set(deflf "")

  list(REMOVE_DUPLICATES suites)
  list(SORT suites)
  foreach(suite ${suites})
    set(init "NULL")
    set(deinit "NULL")
    if(${suite} IN_LIST suites_w_init)
      set(init "CUnit_Suite_Initialize__(${suite})")
      set(decls "${decls}${declf}CUnit_Suite_Initialize_Decl__(${suite});")
      set(declf "${lf}")
    endif()
    if(${suite} IN_LIST suites_w_deinit)
      set(deinit "CUnit_Suite_Cleanup__(${suite})")
      set(decls "${decls}${declf}CUnit_Suite_Cleanup_Decl__(${suite});")
      set(declf "${lf}")
    endif()

    set(defs "${defs}${deflf}CUnit_Suite__(${suite}, ${init}, ${deinit});")
    set(deflf "${lf}")
  endforeach()

  list(REMOVE_DUPLICATES tests)
  list(SORT tests)
  foreach(entry ${tests})
    string(REPLACE ":" ";" entry ${entry})
    list(GET entry 0 suite)
    list(GET entry 1 test)
    list(GET entry 2 enable)

    set(decls "${decls}${declf}CUnit_Test_Decl__(${suite}, ${test});")
    set(declf "${lf}")
    set(defs "${defs}${deflf}CUnit_Test__(${suite}, ${test}, ${enable});")
    set(deflf "${lf}")

    add_test(
      NAME "CUnit_${suite}_${test}"
      COMMAND ${target} -a -r "${suite}-${test}" -s ${suite} -t ${test})
    set_tests_properties("CUnit_${suite}_${test}" PROPERTIES TIMEOUT 10)
    if(APPLE)
      set_property(
        TEST "CUnit_${suite}_${test}"
        PROPERTY ENVIRONMENT "DYLD_LIBRARY_PATH=${CUNIT_LIBRARY_DIR}:$ENV{DYLD_LIBRARY_PATH}")
    endif()
    if(WIN32 AND ${CUNIT_LIBRARY_TYPE} STREQUAL "SHARED_LIBRARY")
      set_property(
        TEST "CUnit_${suite}_${test}"
        PROPERTY ENVIRONMENT "PATH=${CUNIT_LIBRARY_DIR};$ENV{PATH}")
    endif()
  endforeach()

  set(root "${CUNIT_DIR}")
  set(CUnit_Decls "${decls}")
  set(CUnit_Defs "${defs}")

  configure_file("${root}/src/main.c.in" "${runner}.c" @ONLY)
  add_executable(${target} "${runner}.c" "${root}/src/runner.c" ${sources})
  target_link_libraries(${target} CUnit)
  target_include_directories(${target} PRIVATE "${root}/include")
  if("2.1.3" VERSION_LESS_EQUAL
       "${CUNIT_VERSION_MAJOR}.${CUNIT_VERSION_MINOR}.${CUNIT_VERSION_PATCH}")
    set_source_files_properties(
      "${root}/src/runner.c" PROPERTIES COMPILE_DEFINITIONS HAVE_ENABLE_JUNIT_XML)
  endif()
endfunction()

