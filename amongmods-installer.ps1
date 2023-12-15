<#
.SYNOPSIS
 Proof of concept of  a downloader for Town of Us and Better Crew Link

.DESCRIPTION
 Tries to locate an installation of Among Us (Steam version only)
 Checks for Town of Us and Better Crew Link and if needed, downloads them.
 Clones the installed Among Us, adds the ToU mod, and creates a shortcut on desktop.
 Optionally downloads and installs BetterCrewLink

 To run directly from powershell, try either:
  Set-ExecutionPolicy Bypass -Scope Process -Force; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/rapid-io/amongmods/main/amongmods-installer.ps1'))
 or
  iex (iwr "https://raw.githubusercontent.com/rapid-io/amongmods/main/amongmods-installer.ps1").Content
  
.NOTES
 Version:        2023-12-15.0
 Author:         rapid

.LINK
 https://github.com/rapid-io/amongmods
#>
$version = '2023-12-15.0'

Import-Module BitsTransfer

function showBanner() {
    Write-Host ""
    Write-Host "/----------------------------------------------"
    Write-Host "| Among Mods | Downloader by rapid v$version"
    write-host "\----------------------------------------------"
    Write-Host ""
}


function scanSteam($Paths) {
    # Find directories for the Steam Game Library
    $SteamVDF = (Get-ItemPropertyValue -Path 'HKCU:\\SOFTWARE\Valve\Steam\'  -Name 'SteamPath') + "/steamapps/libraryfolders.vdf"
    $SteamLibs = gc $SteamVDF | Select-String -Pattern '"path"		"(.*?)"' -AllMatches | ForEach-Object {$_.matches.groups[1].value}
    $Paths.Steam = ($SteamVDF -replace '/','\')

    # Iterate through the directories to find the Among Us-instalation
    $hits = 0
    $SteamLibs | ForEach-Object  {
        $Path = ($_  -replace '\\\\','\') + "\steamapps\common\Among Us\Among Us.exe"

        if (Test-Path -Path $Path  -PathType Leaf) {
            $Split = $Path.Split("\")
            $Paths.AmongUs = [string]($Split[0..($Split.count-2)] -join "\")
            $Paths.TownOfUs = [string]($Split[0..($Split.count-3)] -join "\") + "\Among Us ToU"
            $hits++
        }
    }
    return $hits
}

function infoFromGitHub([string]$repository,[string]$filepattern) {
    $GH_Asset = ((Invoke-RestMethod -Method GET -Uri "https://api.github.com/repos/$repository/releases")[0].assets | Where-Object name -like $filepattern )
    $source= $GH_Asset.browser_download_url
    $size = $GH_Asset.size

    if ($source -eq $null) {
        Write-Host "Could not find a file, giving up."
        return $null
    }
    $m = $source -match '^https://github.com/\S+/\S+/releases/download/v(\d+\.\d+\.\d+)/'
    if ($m -eq $false) {
        Write-Host "Could not detect version number of release, giving up."
        return $null
    }
    $version = $Matches[1]

    # Return hashtable with info
    @{
        URL = $source
        Filename = $source.split('/')[-1]
        Version = $version
        Size = [string]([math]::Truncate($size/1MB)) + "MB"
    }
}

function downloadFile([string]$URL,[string]$destination) {
    Write-Host "[DL] From: " $URL
    Write-Host "[DL] To:   " $destination
    try {
        Start-BitsTransfer -DisplayName "Download" -ErrorAction Stop -Description $URL -Source $URL -Destination $destination
    }
    Catch {
            Write-Host "[DL] Failed:" $($_)
            return $false
    }
    Write-Host "[DL]" (Get-Item $destination).Length "bytes downloaded"
    return $true
}

#"C:\Program Files (x86)\Steam\steamapps\common\Among Us ToU\BepInEx\plugins\TownOfUs.dll"
function checkToU($Paths,$ToU) {
    $ToUdllpath = $Paths.TownofUs + "\BepInEx\plugins\TownOfUs.dll"
    if (Test-Path -Path $ToUdllpath) {
        $ToUdllversion = (Get-Item $ToUdllpath).VersionInfo.ProductVersion # FileVersion and ProductVersion are not the same here
        if ($ToU.Version -eq $ToUdllversion) {
            return $true
        }
    }
    return $false
}

#"C:\Program Files (x86)\Steam\steamapps\common\Among Us\GameAssembly.dll"
function checkAU($Paths) {
    $ToUdllpath = $Paths.TownofUs + "\GameAssembly.dll"
    $AUdllpath = $Paths.AmongUs  + "\GameAssembly.dll"
    if (Test-Path -Path $ToUdllpath) {
        $ToUdllversion = (Get-Item $ToUdllpath).LastWriteTime.DateTime
        $AUdllversion = (Get-Item $AUdllpath).LastWriteTime.DateTime
        Write-Host ""
        Write-Host "[Version] Among Us: " $AUdllversion
        Write-Host "[Version]      ToU: " $ToUdllversion
        if ($AUdllversion -eq $ToUdllversion) {
            return $true
        }
    }
    return $false
}


# https://github.com/eDonnes124/Town-Of-Us-R/releases/download/v3.4.0/ToU.v3.4.0.zip
function installToU($Paths,$ToU) {
    Write-Host ""
    Write-Host "[Town of Us] Installing to: " $Paths.TownOfUs

    # Make a check if ToU is already installed, asked to reinstall, if yes, wipe the entire directory first
    if (Test-Path -Path $Paths.TownOfUs) {
        Write-Host ""
        $confirmation = Read-Host "[Town of Us] Previous installation detected at this location. Want to remove it and reinstall? [y/n]"
        while($confirmation -ne "y") {
            if ($confirmation -eq 'n') { return $false }
            $confirmation = Read-Host "[Town of Us] Remove and reinstall? [y/n]"

        }
        Remove-Item $Paths.TownOfUs -Recurse -Force
        Write-Host "[Town of Us] Removed" $Paths.TownOfUs
    } 

    Write-Host ""
    Write-Host "[Town of Us] Copying Among Us files..."

    # Create a copy
    Copy-Item -Path $Paths.AmongUs -Destination $Paths.TownOfUs -Recurse

    Write-Host "[Town of Us] ... Done!"
    Write-Host ""

    $confirmation = Read-Host "[Town of Us] About to download Town of Us (about $($ToU.Size)). This might take a while. You ready? [y/n]"
    while($confirmation -ne "y") {
        if ($confirmation -eq 'n') { return $false }
        $confirmation = Read-Host "[Town of Us] Ready? [y/n]"
    }

    # Download ToU from Github
    $filePath = "$($Paths.TownOfUs)\$($ToU.Filename)"
    $d = downloadFile -URL $ToU.URL -destination $filePath

    if ($d -eq $false) {
        Write-Host "[Town of Us] Failed the download, aborting."
        return $false
    }

    # Unzip ToU to the new directory
    Write-Host ""
    Write-Host "[Town of Us] Unpacking ToU..."
    Expand-Archive -Path $filePath -DestinationPath $Paths.TownOfUs

    Write-Host "[Town of Us] Moving unpacked files..."
    # Move all files from new dir, to the parent directory
    $ToU_dir = "$($Paths.TownOfUs)\$(Get-ChildItem -Path $Paths.TownOfUs -Directory -Name -Include "ToU*")"
    Get-ChildItem -Path $ToU_dir | Move-Item -Destination $Paths.TownOfUs
    Write-Host "[Town of Us] ... Done!"

    # Create a shortcut 
    Write-Host ""
    Write-Host "[Town of Us] Creating a shortcut on desktop."
    $ShortcutFile = ([Environment]::GetFolderPath("Desktop"))+"\Among Us - ToU.lnk"
    $Shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($ShortcutFile)
    $Shortcut.TargetPath = $($Paths.TownOfUs) + "\Among Us.exe"
    $Shortcut.Save()
   
    # Clean up 
    Write-Host "[Town of Us] Removing downloaded archive."
    Remove-Item $filePath -Force #-Verbose

    Write-Host ""
    Write-Host "[Town of Us] Installation completed, start by using shortcut on desktop named 'Among Us - ToU'"
    Write-Host ""
}


function checkBCL($BCL) {
    $BCLexepath = "$env:LOCALAPPDATA\Programs\bettercrewlink\Better-CrewLink.exe"
    if (Test-Path -Path $BCLexepath) {
        $BCLexeversion = (Get-Item $BCLexepath).VersionInfo.FileVersion # FileVersion and ProductVersion are not the same here
        if ($BCL.Version -eq $BCLexeversion) {
            return $true
        }
    }
    return $false

}

# https://github.com/OhMyGuus/BetterCrewLink/releases/download/v3.0.5/Better-CrewLink-Setup-3.0.5.exe
function installBCL($BCL) {
    $confirmation = Read-Host "[Better Crew Link] Want to download and install BetterCrewLink, about $($BCL.Size)? [y/n]"
    while($confirmation -ne "y") {
        if ($confirmation -eq 'n') { return $false }
        $confirmation = Read-Host "[Better Crew Link] Want it or not? [y/n]"
    }

    $filename = "$((Get-Item $env:TEMP).Fullname)\$($BCL.Filename)"
    # Download BetterCrewLink from Github to current directory
    $d = downloadFile -URL $BCL.URL -destination $filename

    if ($d -eq $false) {
        Write-Host "[Better Crew Link] Failed the download, aborting."
        return $false
    }

    Write-Host "[Better Crew Link] Download finished, installing."
    Start-Process -Wait $filename
    #$confirmation = Read-Host "[Better Crew Link] Wait for the installer to complete, and once BetterCrewLink starts, press Enter to remove the setup-file"
    Write-Host "[Better Crew Link] Installation finished, removing the setup-file."
    Remove-Item -Path "$filename" -Force -Verbose
    Write-Host ""
    Write-Host "[Better Crew Link] Removed " $filename
    Write-Host ""
    return $true
}


### Main
$AU_Paths = [PSCustomObject]@{
    Steam = ''
    AmongUs = ''
    TownofUs = ''
}

showBanner
$steam = scanSteam -Paths $AU_Paths

if ($steam -eq 0) {
    Write-Host "[INIT] Could not find the Among Us installation directory. Aborting!"
}
elseif ($steam > 1) {
    Write-Host "[INIT] Among Us found at multiple locations, this can cause issues... Aborting!"
}
else {
    Write-Host "[INIT] Steam VDF found at" $($AU_Paths.Steam)
    Write-Host "[INIT] Among Us found at" $($AU_Paths.AmongUs)
    Write-Host "[INIT] Town of Us location " $($AU_Paths.TownofUs)

    $ToU = infoFromGitHub -repository "eDonnes124/Town-Of-Us-R" -filepattern "ToU.v*.zip"
    if ($ToU -eq $null) {
        Write-Host ""
        Write-Host "[MAIN] Could not find a release for Town of Us. Skipping."
    }
    elseif ((checkAU -Paths $AU_Paths) -and (checkToU -Paths $AU_Paths -ToU $ToU)) {
        Write-Host ""
        Write-Host "[MAIN] Town of Us is already installed with the current version:" $ToU.Version
    }
    else {
        $r = installToU -Paths $AU_Paths -ToU $ToU
    }


    $BCL = infoFromGitHub -repository "OhMyGuus/BetterCrewLink" -filepattern "Better-CrewLink-Setup-*.exe"
    if ($BCL -eq $null) {
        Write-Host ""
        Write-Host "[MAIN] Could not find a release for Better Crew Link. Skipping."
    }
    elseif (checkBCL -BCL $BCL) {
        Write-Host ""
        Write-Host "[MAIN] Better Crew Link is already installed with the current version:" $BCL.Version
    }
    else {
        $r = installBCL -BCL $BCL
    }
}

Write-Host ""
$confirmation = Read-Host "[END] This is the end of our journey. Press Enter to exit the installer"
