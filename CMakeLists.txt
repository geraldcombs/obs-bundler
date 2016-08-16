
project(OBS-Bundler)

if (NOT WIN32)
    message(ERROR "Must be built on Windows")
endif()

# Just a guess at this point.
cmake_minimum_required(VERSION 3.1.3)

foreach (_subdir bin bundles work work/x86 work/x64)
    file (MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/${_subdir}")
endforeach()

####
# Prerequisites: 7-Zip, gendef, etc.
####

# set (NUGET_EXECUTABLE "${CMAKE_BINARY_DIR}/bin/nuget.exe")
# if (NOT EXISTS "${NUGET_EXECUTABLE}")
#     file (DOWNLOAD
#         "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
#         "${CMAKE_BINARY_DIR}/bin/nuget.exe"
#     )
# endif()

find_program(ZIP_EXECUTABLE 7z
    PATH "$ENV{PROGRAMFILES}/7-Zip" "$ENV{PROGRAMW6432}/7-Zip"
    DOC "Path to the 7z utility."
)

if (NOT "${ZIP_EXECUTABLE}")
    message (FATAL "7z not found")
endif()

set (GENDEF_EXECUTABLE "${CMAKE_BINARY_DIR}/bin/gendef.exe")
if (NOT EXISTS "${GENDEF_EXECUTABLE}")
    set (GENDEF_PKG "gendef-v3.3.0-1-i686-w64-mingw32")
    # http://win-builds.org/1.5.0/packages/windows_32/gendef-v3.3.0-1-i686-w64-mingw32.txz
    # http://win-builds.org/1.5.0/packages/windows_64/gendef-v3.3.0-1-x86_64-w64-mingw32.txz
    #
    # http://www.vultaire.net/blog/2016/05/14/setting-up-mingw-w64-tools-on-windows-without-msys2/
    # https://sourceforge.net/projects/mingw-w64/files/Toolchains%20targetting%20Win64/Personal%20Builds/mingw-builds/6.1.0/threads-posix/seh/
    file (DOWNLOAD
        "http://win-builds.org/1.5.0/packages/windows_32/${GENDEF_PKG}.txz"
        "${CMAKE_BINARY_DIR}/work/${GENDEF_PKG}.txz"
    )
    execute_process(
        COMMAND "${ZIP_EXECUTABLE}" e -so "${GENDEF_PKG}.txz"
        # |
        COMMAND "${ZIP_EXECUTABLE}" e -si -ttar "windows_32\\bin\\gendef.exe"
        WORKING_DIRECTORY "${CMAKE_BINARY_DIR}/work"
    )
    file (RENAME "${CMAKE_BINARY_DIR}/work/gendef.exe" ${GENDEF_EXECUTABLE})
endif()

find_program(LIB_EXECUTABLE lib
    DOC "Path to the Microsoft Library Manager."
)

if (NOT "${LIB_EXECUTABLE}")
    message (FATAL "Lib.exe not found")
endif()

find_program(EDITBIN_EXECUTABLE editbin
    DOC "Path to the Microsoft COFF/PE Editor."
)

if (NOT "${EDITBIN_EXECUTABLE}")
    message (FATAL "Editbin not found")
endif()

# Make sure we don't find Cygwin's Python. Adapted from
# cmake/modules/LocatePythonExecutable.cmake in the Wireshark sources.
if(NOT PYTHON_EXECUTABLE AND WIN32)
    set (_major_version 3)
    foreach(_minor_version 7 6 5 4 3 2 1)
        find_program(PYTHON_EXECUTABLE
            python.exe
            PATHS [HKEY_LOCAL_MACHINE\\SOFTWARE\\Python\\PythonCore\\${_major_version}.${_minor_version}\\InstallPath]
            NO_DEFAULT_PATH
        )
        if (PYTHON_EXECUTABLE)
            break()
        endif()
    endforeach()
endif()

find_package (PythonInterp 3 REQUIRED)

set (_dmr_version 1.0.3)
set (DOWNLOAD_MINGW_RPM "${CMAKE_BINARY_DIR}/download-mingw-rpm-${_dmr_version}/download-mingw-rpm.py")
if (NOT EXISTS "${DOWNLOAD_MINGW_RPM}")
    file (DOWNLOAD
        "https://github.com/geraldcombs/download-mingw-rpm/archive/v${_dmr_version}.zip"
        "${CMAKE_BINARY_DIR}/work/download-mingw-rpm-${_dmr_version}.zip"
    )
    execute_process(
        COMMAND "${ZIP_EXECUTABLE}" x "${CMAKE_BINARY_DIR}/work/download-mingw-rpm-${_dmr_version}.zip"
    )
endif()

set (OBS_REPOSITORY openSUSE_42.1)

# OBS packaging steps:
# - Download the OBS mingw RPMs using download-mingw-rpm.
# - Unzip the bundle.
# - Create .defs using gendef
# - Create .libs using lib
# - Enable ASLR+NX in DLLs using editbin https://sourceware.org/bugzilla/show_bug.cgi?id=19011
# - At some point create package using NuGet?

# Add bundle targets.
# Parameters are RPM package names. The first package will be used as the
# bundle name.
# To do:
# - Navigate CMake's target/command dependency maze
macro(add_bundle_targets _base_package)
    set (_prep_target ${_base_package}-prep)
    set (_bundle_target ${_base_package}-bundle)
    add_custom_target(${_prep_target} ALL)
    add_custom_target(${_bundle_target} ALL)
    add_dependencies(${_bundle_target} ${_prep_target})

    foreach (BITS 32 64)
        if (${BITS} EQUAL 32)
            set (MACHINE x86)
        else()
            set (MACHINE x64)
        endif()

        # Download our RPMS and combine them into a .zip.
        #
        # XXX We do way too much work at configure time. Unfortunately we
        # don't know the bundle version until we download the OBS package
        # so this has to be done here.
        execute_process(
            COMMAND "${PYTHON_EXECUTABLE}" "${DOWNLOAD_MINGW_RPM}"
                --make-zip
                --7zip-program=${ZIP_EXECUTABLE}
                --add-metadata
                --deps
                --project=windows:mingw:win${BITS}
                --repository=${OBS_REPOSITORY}
                ${ARGV}
            WORKING_DIRECTORY "${CMAKE_BINARY_DIR}/work/${MACHINE}"
        )
        file (STRINGS
            "${CMAKE_BINARY_DIR}/work/${MACHINE}/${_base_package}.zipname"
            _dmr_zip
            LIMIT_COUNT 1
        )
        if (NOT _dmr_zip)
            message (FATAL_ERROR "Unable to find download-mingw-rpm output for ${_base_package} ${MACHINE}")
        endif()

        # -prep targets.
        # Make whatever changes are necessary to the OBS files.
        string (REPLACE ".zip" "" _prep_base ${_dmr_zip})

        add_custom_command(TARGET ${_prep_target}
            COMMAND ${CMAKE_COMMAND} -E remove_directory "${_prep_base}"
            COMMAND ${ZIP_EXECUTABLE} x -o"${_prep_base}" ${_dmr_zip}
            WORKING_DIRECTORY "${CMAKE_BINARY_DIR}/work/${MACHINE}"
        )

        # Custom -prep targets.
        # If we find a matching "prep" script in the tools directory, run it.
        if (EXISTS "${CMAKE_SOURCE_DIR}/tools/${_prep_target}.ps1")
            file(TO_NATIVE_PATH "${CMAKE_SOURCE_DIR}/src" _src_path)
            add_custom_command(TARGET ${_prep_target}
                COMMAND powershell -NoProfile -NonInteractive -executionpolicy bypass
                    "${CMAKE_SOURCE_DIR}/tools/${_prep_target}.ps1"
                    -SrcDir "${_src_path}"
                WORKING_DIRECTORY "${CMAKE_BINARY_DIR}/work/${MACHINE}/${_prep_base}"
            )
        endif()

        file(TO_NATIVE_PATH "${CMAKE_BINARY_DIR}/bin" _ps_bin_path)
        add_custom_command(TARGET ${_prep_target}
            COMMAND powershell -NoProfile -NonInteractive -executionpolicy bypass
                "${CMAKE_SOURCE_DIR}/tools/mingw-library-prep.ps1"
                -BinDir "${_ps_bin_path}"
                -Machine "${MACHINE}"
            WORKING_DIRECTORY "${CMAKE_BINARY_DIR}/work/${MACHINE}/${_prep_base}"
        )

        # -bundle target.
        # Create the final .zip.
        set (_bundle_base "${_prep_base}-win${BITS}ws")
        set (_bundle_name "${CMAKE_BINARY_DIR}/bundles/${_bundle_base}.zip")
        file (TO_NATIVE_PATH "${_bundle_name}" _win_bundle_name)
        add_custom_command(TARGET ${_bundle_target}
            COMMAND ${CMAKE_COMMAND} -E remove -f "${_bundle_name}"
            COMMAND ${CMAKE_COMMAND} -E remove_directory "${_bundle_base}"
            COMMAND ${CMAKE_COMMAND} -E rename "${_prep_base}" "${_bundle_base}"
            COMMAND ${ZIP_EXECUTABLE} a -tzip -mx=9 "${_win_bundle_name}" "${_bundle_base}\\"
            WORKING_DIRECTORY "${CMAKE_BINARY_DIR}/work/${MACHINE}"
        )

    endforeach()
endmacro(add_bundle_targets)

# Create our bundles.

add_bundle_targets(libcares2 libcares2-devel)

add_bundle_targets(geoip geoip-devel)

# XXX Make gcrypt a separate bundle?
add_bundle_targets(gnutls libgnutls-devel libgcrypt20 libgcrypt-devel)

# Includes custom target gtk2-prep.ps1
add_bundle_targets(gtk2 gtk2-devel libgthread-2_0-0 glib2-debug)

add_bundle_targets(libpcre1 pcre-devel)

# Not built by OBS:
# - Kerberos (or heimdal?)
# - Lua
# - PortAudio (GTK+ only)
# - AirPcap and WinPcap/NPcap developer packs
# - Libsmi
# - WinSparkle