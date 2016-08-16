#
# mingw-library-prep - Generate DLL import libraries and set flags.
#
# Copyright 2016 Gerald Combs <gerald@wireshark.org>
#

#requires -version 2

<#
.SYNOPSIS
Prepare DLLs and import libraries for use with Visual C++.

.DESCRIPTION
This script takes a set of DLLs generated by MinGW-w64, sets hardening flags,
and creates Visuall C++ import libraries.

.INPUTS
BinDir. Local binary directory. Needed for gendef.
Machine. The DLL machine architecture. One of x86 or x64.

.OUTPUTS
- A set of definition files.
- A set of import libraries.

.EXAMPLE
C:\PS> \path\to\mingw-library-prep.ps1 -BinDir ..\..\bin -Machine x64
#>

Param(
    [Parameter(Mandatory=$true, Position=0)]
    [String]
    $BinDir,

    [Parameter(Mandatory=$true, Position=1)]
    [String]
    $Machine
)

# Fail early and often
$ErrorActionPreference = "Stop"

Get-ChildItem "bin" -Filter *.dll |
Foreach-Object {
    # Given libfoo-123.dll or foo-123.dll, harden foo-123.dll and create
    # foo.def and foo.lib
    $dll = $_
    $dll_base = $dll.Basename
    $lib_base = $dll_base -replace '^lib', ''
    $lib_base = $lib_base -replace '-[0-9]+', ''

    # This wouldn't be needed if GNU ld used sane defaults:
    # https://sourceware.org/bugzilla/show_bug.cgi?id=19011
    Write-Output ("Hardening $dll.")
    if ($Machine -eq 'x86') {
        & editbin /DYNAMICBASE /NXCOMPAT bin\$dll
    } else {
        & editbin /DYNAMICBASE /HIGHENTROPYVA /NXCOMPAT bin\$dll
    }
    if ($LastExitCode -gt 0) { exit $LastExitCode }

    # It would be nice if OBS passed -Wl,--out-implib to gcc.
    if (-Not (Test-Path "lib/$lib_base.lib")) {
        Write-Output ("Generating $lib_base.def from $dll.")
        & "$BinDir\gendef" - bin/$dll > lib/$lib_base.def
        if ($LastExitCode -gt 0) { exit $LastExitCode }

        Write-Output ("Generating $lib_base.lib from $lib_base.def.")
        Set-Location lib
        & lib /machine:$Machine /def:$lib_base.def /name:$dll_base /out:$lib_base.lib
        if ($LastExitCode -gt 0) { exit $LastExitCode }
        Set-Location ..
    }
}
