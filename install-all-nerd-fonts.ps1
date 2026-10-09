#Requires -Version 5.1
<#
.SYNOPSIS
    Install every Nerd Font family on Windows, using the official list at nerdfonts.com.

.DESCRIPTION
    Reads the family list from https://www.nerdfonts.com/font-downloads, downloads each
    archive from the project's GitHub releases and installs every *.ttf and *.otf member.

    By default the fonts are installed for the current user only, which needs no
    elevation:

        %LOCALAPPDATA%\Microsoft\Windows\Fonts
        HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts

    With -SystemWide they go to C:\Windows\Fonts and
    HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts instead, which requires an
    elevated session.

    Nothing but PowerShell is needed: downloading uses Invoke-WebRequest and unzipping
    uses the .NET zip classes that ship with Windows.

.PARAMETER SystemWide
    Install for every user instead of just the current one. Requires an elevated
    ("Run as administrator") session.

.PARAMETER FontFamily
    Only install families whose names match these patterns. Wildcards are supported and
    matching ignores case. Use the family name as it appears in the archive name, with
    or without the .zip extension - for example JetBrainsMono or 'Caskaydia*'.

.EXAMPLE
    .\install-all-nerd-fonts.ps1

    Installs all 72 families for the current user.

.EXAMPLE
    .\install-all-nerd-fonts.ps1 -SystemWide

    Installs all families for every user. Run from an elevated session.

.EXAMPLE
    .\install-all-nerd-fonts.ps1 -FontFamily JetBrainsMono, FiraCode -WhatIf

    Shows what would be installed and downloads nothing.

.NOTES
    Restart your terminal and editor afterwards - already-running processes keep their
    old font list.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$SystemWide,

    [string[]]$FontFamily
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Progress rendering makes Invoke-WebRequest an order of magnitude slower on Windows
# PowerShell, and these archives are measured in hundreds of megabytes each.
$ProgressPreference = 'SilentlyContinue'

if ($PSVersionTable.PSVersion.Major -lt 6) {
    # Windows PowerShell 5.1 can still negotiate TLS 1.0 by default on older builds.
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}

# Windows has no fontconfig. A font is "installed" when the file sits in a registered
# font folder and is named in the Fonts registry key; per-user values hold the full path
# to the file, machine-wide values hold the bare file name.
$site = 'https://www.nerdfonts.com/font-downloads'
$archivePattern = 'https://github\.com/ryanoasis/nerd-fonts/releases/download/[^"''<>]*\.zip'

function Test-Elevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Register-FontFile {
    param(
        [Parameter(Mandatory)][string]$FontFile,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][bool]$ValueIsFullPath
    )

    if (-not (Test-Path -LiteralPath $Key)) {
        New-Item -Path $Key -Force | Out-Null
    }

    $name = [IO.Path]::GetFileNameWithoutExtension($FontFile)
    $value = if ($ValueIsFullPath) { $FontFile } else { [IO.Path]::GetFileName($FontFile) }
    # Windows labels TrueType outlines "(TrueType)" and CFF/OpenType ones "(OpenType)";
    # the label is what the Fonts settings page shows.
    $label = if ([IO.Path]::GetExtension($FontFile) -eq '.otf') { 'OpenType' } else { 'TrueType' }
    New-ItemProperty -LiteralPath $Key -Name "$name ($label)" -Value $value `
        -PropertyType String -Force | Out-Null
}

function Initialize-FontApi {
    # gdi32/user32 entry points used to load a new font into the running session and to
    # release it again before replacing it - Windows keeps loaded font files locked.
    if ('NerdFonts.FontApi' -as [type]) { return $true }

    try {
        Add-Type -Namespace NerdFonts -Name FontApi -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("gdi32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern int AddFontResourceW(string lpFileName);

[System.Runtime.InteropServices.DllImport("gdi32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern bool RemoveFontResourceW(string lpFileName);

[System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern System.IntPtr SendMessageTimeout(System.IntPtr hWnd, uint Msg, System.IntPtr wParam, System.IntPtr lParam, uint fuFlags, uint uTimeout, out System.IntPtr lpdwResult);
'@
        return $true
    } catch {
        Write-Warning "fonts can be installed but not activated in this session " +
            "($($_.Exception.Message)); sign out and back in to pick them up."
        return $false
    }
}

function Update-FontCache {
    param([Parameter(Mandatory)][string[]]$FontFile)

    foreach ($file in $FontFile) {
        [void][NerdFonts.FontApi]::AddFontResourceW($file)
    }

    # WM_FONTCHANGE to every top-level window, so running apps rebuild their font list.
    $result = [IntPtr]::Zero
    [void][NerdFonts.FontApi]::SendMessageTimeout(
        [IntPtr]0xffff, 0x001D, [IntPtr]::Zero, [IntPtr]::Zero, 0x0002, 1000, [ref]$result)
}

if ($SystemWide) {
    if (-not (Test-Elevated)) {
        throw '-SystemWide installs into C:\Windows\Fonts and needs an elevated session; open PowerShell with "Run as administrator", or drop -SystemWide to install for the current user only.'
    }
    $fontDir = Join-Path $env:SystemRoot 'Fonts'
    $fontKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    $valueIsFullPath = $false
} else {
    $fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    $fontKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
    $valueIsFullPath = $true
    $os = [Environment]::OSVersion.Version
    if ($os.Major -lt 10 -or $os.Build -lt 17763) {
        Write-Warning "per-user font installs need Windows 10 1809 or later; use -SystemWide on this system."
    }
}

Write-Host "Reading the family list from $site"
try {
    $page = Invoke-WebRequest -Uri $site -UseBasicParsing
} catch {
    throw "could not fetch $site - is it reachable? $($_.Exception.Message)"
}

$urls = @(
    [regex]::Matches($page.Content, $archivePattern) |
        ForEach-Object { $_.Value } |
        Sort-Object -Unique
)
if ($urls.Count -eq 0) {
    throw "no font archives found at $site - is it reachable?"
}

if ($FontFamily) {
    # Accept both -FontFamily A,B and -FontFamily A B; a native command line such as
    # `pwsh -File install-all-nerd-fonts.ps1 -FontFamily A,B` arrives as one comma-joined string.
    $patterns = @($FontFamily | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
    $urls = @($urls | Where-Object {
            $name = [IO.Path]::GetFileNameWithoutExtension($_)
            @($patterns | Where-Object { $name -like $_ }).Count -gt 0
        })
    if ($urls.Count -eq 0) {
        throw "no families matched: $($patterns -join ', ')"
    }
}

$tags = @($urls | ForEach-Object { if ($_ -match '/download/([^/]+)/') { $Matches[1] } } | Sort-Object -Unique)
Write-Host "Nerd Fonts $($tags -join ', ') -> $fontDir"
Write-Host "Installing $($urls.Count) font families"

if ($PSCmdlet.ShouldProcess($fontDir, 'Create font directory')) {
    New-Item -ItemType Directory -Path $fontDir -Force | Out-Null
}

if (-not ('System.IO.Compression.ZipFile' -as [type])) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
}

$tmp = $null
$installed = [System.Collections.Generic.List[string]]::new()
$seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$upToDate = 0
$locked = 0
$fontApi = Initialize-FontApi

try {
    foreach ($url in $urls) {
        $archive = [IO.Path]::GetFileName($url)
        Write-Host "  $archive"
        if (-not $PSCmdlet.ShouldProcess($archive, "Download and extract *.ttf/*.otf into $fontDir")) {
            continue
        }

        # Invoke-WebRequest, like unzip, needs the whole archive on disk before it can be
        # read, so one temp file is reused for every family.
        if (-not $tmp) { $tmp = [IO.Path]::GetTempFileName() }
        Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing

        $zip = [IO.Compression.ZipFile]::OpenRead($tmp)
        try {
            foreach ($entry in $zip.Entries) {
                # 14 of the 72 families publish CFF outlines, so they ship *.otf instead of
                # *.ttf. Windows loads both, and extracting only *.ttf would silently skip
                # those families altogether.
                if ($entry.Name -notlike '*.ttf' -and $entry.Name -notlike '*.otf') { continue }

                $target = Join-Path $fontDir $entry.Name
                if (-not $seen.Add($entry.Name)) {
                    Write-Warning "$($entry.Name) is in more than one family archive; the last copy wins."
                }

                # Windows locks a font file it has loaded, so an existing file with the same
                # byte count is left alone: re-running is a no-op instead of a heap of
                # "file in use" failures.
                if ([IO.File]::Exists($target) -and (Get-Item -LiteralPath $target).Length -eq $entry.Length) {
                    $upToDate++
                    Register-FontFile -FontFile $target -Key $fontKey -ValueIsFullPath $valueIsFullPath
                    continue
                }
                if ($fontApi -and [IO.File]::Exists($target)) {
                    [void][NerdFonts.FontApi]::RemoveFontResourceW($target)
                }

                try {
                    [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
                } catch {
                    Write-Warning "could not replace $($entry.Name): $($_.Exception.Message)"
                    $locked++
                    continue
                }

                Register-FontFile -FontFile $target -Key $fontKey -ValueIsFullPath $valueIsFullPath
                $installed.Add($target)
            }
        } finally {
            $zip.Dispose()
        }
    }
} finally {
    # [IO.File]::Delete rather than Remove-Item: the latter honours -WhatIf/$ConfirmPreference.
    if ($tmp -and [IO.File]::Exists($tmp)) { [IO.File]::Delete($tmp) }
}

if ($WhatIfPreference) {
    Write-Host 'Dry run only (-WhatIf): nothing was downloaded or installed.'
} else {
    if ($installed.Count -gt 0) { Update-FontCache -FontFile $installed }

    $summary = "$($installed.Count) font files installed"
    if ($upToDate -gt 0) { $summary += ", $upToDate already up to date" }
    if ($locked -gt 0) { $summary += ", $locked could not be replaced" }
    Write-Host "$summary in $fontDir"

    if ($locked -gt 0) {
        throw "$locked font files are loaded by Windows and could not be replaced - sign out and back in, then re-run."
    }
    if ($installed.Count -eq 0 -and $upToDate -eq 0) {
        throw "no *.ttf or *.otf files were extracted from $($urls.Count) archives."
    }

    Write-Host "Restart your terminal/editor, then pick a family such as 'JetBrainsMono Nerd Font'."
}
