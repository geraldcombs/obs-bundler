#
# bootstrap - Bootstrap our environment.
#
# Copyright 2016 Gerald Combs <gerald@wireshark.org>
#

# XXX Currently unused. Responsibilities taken over by CMakeLists.txt.

#requires -version 2

<#
.SYNOPSIS
Prepare the environment for building and bundling packages.

.DESCRIPTION
This script downloads and extracts tools necessary to build FOSS development
packages for Windows.

.INPUTS
None.

.OUTPUTS
- NuGet
- gendef

.EXAMPLE
C:\PS> .\bin\bootstrap.ps1
#>

#Set-PSDebug -trace 2

# CWD
$PSScriptRoot = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
$WorkDir = "$PSScriptRoot\..\work"


function DownloadFile($filePath, [Uri] $fileUrl) {
    if ((Test-Path $filePath -PathType 'Leaf') -and -not ($Force)) {
        Write-Output "$filePath already there; not retrieving."
        return
    }

    $proxy = [System.Net.WebRequest]::GetSystemWebProxy()
    $proxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials

    Write-Output "Downloading $fileUrl to $filePath"
    $webClient = New-Object System.Net.WebClient
    $webClient.proxy = $proxy
    $webClient.DownloadFile($fileUrl, "$filePath")
}

# Find 7-Zip, downloading it if necessary. We require the full version.
function Bootstrap7Zip() {
    $binDir = "$Destination\bin"
    $exe = "7z.exe"

    # First, check $env:Path.
    if (Get-Command $exe -ErrorAction SilentlyContinue)  {
        $Global:SevenZip = "$exe"
        Write-Output "Found 7-zip on the path"
        return
    }

    # Next, look in a few likely places.
    $searchDirs = @(
        "${env:ProgramFiles}\7-Zip"
        "${env:ProgramFiles(x86)}\7-Zip"
        "${env:ProgramW6432}\7-Zip"
        "${env:ChocolateyInstall}\bin"
        "${env:ChocolateyInstall}\tools"
        "$binDir"
    )

    foreach ($dir in $searchDirs) {
        if ($dir -ne $null -and (Test-Path $dir -PathType 'Container')) {
            if (Test-Path "$dir\$exe" -PathType 'Leaf') {
                $Global:SevenZip = "$dir\$exe"
                Write-Output "Found 7-zip at $dir\$exe"
                return
            }
        }
    }

    # Finally, download a copy from anonsvn.
    if ( -not (Test-Path $binDir -PathType 'Container') ) {
        New-Item -ItemType 'Container' "$binDir" > $null
    }

    Write-Output "Unable to find 7-zip."
    # XXX Fetch using NuGet?
    exit 1
}


# NuGet

DownloadFile "$PSScriptRoot\nuget.exe" "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
Write-Output "NuGet: $PSScriptRoot\nuget.exe"

# 7-Zip
Bootstrap7Zip

# Gendef
# XXX Add 32-bit support

DownloadFile "$WorkDir\gendef-v3.3.0-1-x86_64-w64-mingw32.txz" "http://win-builds.org/1.5.0/packages/windows_64/gendef-v3.3.0-1-x86_64-w64-mingw32.txz"

$GenDefVersion = "gendef-v3.3.0-1-x86_64-w64-mingw32"
# XXX Not sure how to do this all in one command.
& "$SevenZip" e -y "-o$($WorkDir)" "$WorkDir\$GenDefVersion.txz" > $null
& "$SevenZip" e -y "-o$($PSScriptRoot)" "$WorkDir\$GenDefVersion.tar" "windows_64\bin\gendef.exe" > $null

Remove-Item "$WorkDir\$GenDefVersion.tar"

Write-Output "gendef: $PSScriptRoot\gendef.exe"
