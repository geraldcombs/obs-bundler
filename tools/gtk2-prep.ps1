#
# gtk2-prep - Prep glibconfig.h and gtkrc.
#
# Copyright 2016 Gerald Combs <gerald@wireshark.org>
#

#requires -version 2

<#
.SYNOPSIS
Creates a glibconfig.h usable by Visual C++ selects the MS-Windows theme.

.DESCRIPTION
This script preps glibconfig.h and gtkrc prior to packaging.
MUST be run from the top of the GTK2 bundle directory.

.INPUTS
SrcDir. Directory containing the glibconfig.h template file.

.OUTPUTS
- Local modifications.

.EXAMPLE
C:\PS> \path\to\gtk2-prep.ps1 -SrcDir ..\..\..\..\src
#>

Param(
    [Parameter(Mandatory=$true, Position=0)]
    [String]
    $SrcDir
)

# Fail early and often
$ErrorActionPreference = "Stop"

# Create a glibconfig.h that's usable by Visual C++.

$GLibConfigH = "lib\glib-2.0\include\glibconfig.h"

if (-Not (Test-Path "$GLibConfigH.mingw")) {
    Move-Item "$GLibConfigH" "$GLibConfigH.mingw"
}

$GLibMajorVer = (Select-String -Path "$GLibConfigH.mingw" '^#define *GLIB_MAJOR_VERSION.*').Matches[0].Value
$GLibMinorVer = (Select-String -Path "$GLibConfigH.mingw" '^#define *GLIB_MINOR_VERSION.*').Matches[0].Value
$GLibMicroVer = (Select-String -Path "$GLibConfigH.mingw" '^#define *GLIB_MICRO_VERSION.*').Matches[0].Value

# Created by running
# git show 2.48.1:glib/glibconfig.h.win32.in > path/to/glibconfig.h.win32.in.2.48.1
# from a GLib Git clone.
$GLibConfigWin32In = Get-Content "$SrcDir\glibconfig.h.win32.in.2.48.1"

$GLibConfigWin32In = $GLibConfigWin32In `
    -Replace '^#define *GLIB_MAJOR_VERSION.*', "$GLibMajorVer" `
    -Replace '^#define *GLIB_MINOR_VERSION.*', "$GLibMinorVer" `
    -Replace '^#define *GLIB_MICRO_VERSION.*', "$GLibMicroVer" `
    -Replace '@.*@', '' # @GLIB_WIN32_STATIC_COMPILATION_DEFINE@
$GLibConfigWin32In | Set-Content "$GLibConfigH"

# Use the MS-Windows theme.
Copy-Item "share\themes\MS-Windows\gtk-2.0\gtkrc" "etc\gtk-2.0\gtkrc"
