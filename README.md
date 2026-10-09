# nerd-fonts

Scripts that install **every Nerd Font family** on Fedora and on Windows.

Fedora ships nothing for Nerd Fonts, and upstream publishes 72 separate archives with no combined
bundle — so there is no `dnf install` shortcut. Both scripts read the official family list from
[nerdfonts.com/font-downloads](https://www.nerdfonts.com/font-downloads) and install all of them:

| Script | Platform | Fonts go to |
|---|---|---|
| `install-nerd-fonts.sh` | Fedora/RHEL, native Linux (no WSL) | `${XDG_DATA_HOME:-$HOME/.local/share}/fonts/NerdFonts` |
| `install-nerd-fonts.ps1` | Windows 10 1809 or later | `%LOCALAPPDATA%\Microsoft\Windows\Fonts`, or `C:\Windows\Fonts` with `-SystemWide` |

## Requirements

### Fedora

Fedora 44 (or any Fedora/RHEL with `bash`, `curl`, `unzip`). **Native Linux — no WSL.**

| Tool | Needed? | Notes |
|---|---|---|
| `bash` | required | |
| `curl` | required | |
| `unzip` | required | preinstalled on Fedora |
| `coreutils` | required | `sed`, `sort`, `mktemp`, `find`, `wc` |
| `fontconfig` (`fc-cache`) | optional | the script warns and tells you what to run if missing |

Check in one line:

```bash
for c in curl unzip sed sort mktemp find; do command -v $c >/dev/null || echo "missing: $c"; done
```

### Windows

Windows 10 1809 (build 17763) or later for a per-user install. **Native Windows — no WSL.**

| Tool | Needed? | Notes |
|---|---|---|
| PowerShell 5.1+ | required | ships with Windows; PowerShell 7 works too |
| `curl`, `unzip` | not needed | downloading is `Invoke-WebRequest`, unzipping is .NET's `System.IO.Compression` |

Check in one line:

```powershell
powershell -NoProfile -Command '$PSVersionTable.PSVersion'
```

## Install

### Fedora

```bash
git clone https://github.com/lequtix/nerd-fonts.git
cd nerd-fonts
chmod +x install-nerd-fonts.sh
./install-nerd-fonts.sh
```

For all users instead of just you:

```bash
sudo ./install-nerd-fonts.sh /usr/share/fonts
```

### Windows

```powershell
git clone https://github.com/lequtix/nerd-fonts.git
cd nerd-fonts
.\install-nerd-fonts.ps1
```

If your execution policy blocks the script, run it in a process that bypasses it:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-nerd-fonts.ps1
```

For all users instead of just you, from an elevated prompt:

```powershell
.\install-nerd-fonts.ps1 -SystemWide
```

## Usage

### Fedora

```
./install-nerd-fonts.sh [font-directory]
```

With no argument, fonts go to `${XDG_DATA_HOME:-$HOME/.local/share}/fonts/NerdFonts`, which honours
`XDG_DATA_HOME` and needs no root. Passing a directory installs there instead — use
`/usr/share/fonts` for a system-wide install.

Anything starting with `-` is rejected with exit code `2`, so a typo like `--dry-run` fails loudly
rather than silently installing to a directory named `--dry-run`.

### Windows

```
.\install-nerd-fonts.ps1 [-SystemWide] [-FontFamily <pattern>[,<pattern>...]] [-WhatIf]
```

With no argument, fonts go to `%LOCALAPPDATA%\Microsoft\Windows\Fonts` and are registered for the
current user only, so no elevation is needed. `-SystemWide` registers them for every user in
`C:\Windows\Fonts` instead, and refuses to run unless the session is elevated.

There is no font-directory argument on Windows, unlike the bash script: Windows only loads fonts
from a registered font folder, so pointing it at an arbitrary directory would produce a folder full
of files no application could see.

`-FontFamily` installs a subset — handy given the full set is 4 GiB:

```powershell
.\install-nerd-fonts.ps1 -FontFamily JetBrainsMono, FiraCode
.\install-nerd-fonts.ps1 -FontFamily 'Caskaydia*', 'Iosevka*'
```

`-WhatIf` prints what would be installed and downloads nothing — no file, registry value or loaded
font is touched:

```powershell
.\install-nerd-fonts.ps1 -FontFamily HeavyData -WhatIf
```

Re-running is safe and cheap: a font file that is already present with the same size is left alone
and only its registry entry is refreshed.

### Uninstall

Fonts are plain files in one directory. On Fedora, remove that directory and refresh the cache:

```bash
rm -rf ~/.local/share/fonts/NerdFonts
fc-cache -f ~/.local/share/fonts
```

On Windows the registry entries have to go too, or the Fonts settings page keeps listing fonts whose
files are gone. The script names each value after the file it installs, and every Nerd Font file
name contains `NerdFont`, so both halves are one pattern match:

```powershell
$key = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
(Get-Item $key).Property | Where-Object { $_ -like '*NerdFont*' } | ForEach-Object {
    Remove-ItemProperty -Path $key -Name $_
}
Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Fonts\*NerdFont*.ttf" -Force
Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Fonts\*NerdFont*.otf" -Force
```

Both extensions are listed on purpose: 14 families ship only `.otf`, so a `.ttf`-only glob leaves
those files behind.

For a `-SystemWide` install, use `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts` and
`C:\Windows\Fonts` instead, from an elevated prompt. Sign out and back in afterwards, because
Windows keeps the loaded copies of those files until the session ends.

## What it does

1. Fetches the official download page and extracts every font archive link from it.
2. Aborts with a clear message if the page yields nothing (offline, or the markup changed).
3. Prints the pinned release tag and the family count.
4. Downloads each archive to a single reused temp file and extracts only the font files
   (`*.ttf` and `*.otf`) straight into the destination.
5. Runs `fc-cache -f` on the fonts root (Fedora), or copies each file into a registered font folder,
   adds its Fonts registry entry, loads it with `AddFontResourceW` and broadcasts `WM_FONTCHANGE` so
   the fonts appear immediately (Windows).
6. Reports how many font files were installed.

The temp file is removed on exit — via a `trap` on Fedora, and via a `finally` block on Windows —
including on failure or `Ctrl-C`.

## How much it downloads

All 72 archives, measured against the pinned release:

| | |
|---|---|
| Families | 72 |
| Total download | **4.03 GiB** (4,324,882,585 bytes) |
| Average per family | 57.3 MiB |
| Largest | `Noto.zip` — 591.3 MiB |
| Smallest | `HeavyData.zip` — 2.63 MiB |

The five biggest families account for a large share of the total:

| Family | Size |
|---|---|
| `Noto` | 591.3 MiB |
| `Iosevka` | 384.2 MiB |
| `IosevkaTerm` | 383.7 MiB |
| `ZedMono` | 266.1 MiB |
| `Monaspace` | 261.3 MiB |

Budget a few minutes and a few GiB of disk. Extraction is the slow part, not the download. The
figures are the same on Windows — it is the same set of archives.

## Why `.zip` when `.tar.xz` is 7× smaller

Every family is published in both formats. The `.tar.xz` set totals **580 MiB** versus **4.03 GiB**
for the `.zip` set — the archives contain byte-identical file sets (same flat layout, no
directories; the difference is purely DEFLATE versus LZMA2).

This script still uses `.zip` deliberately:

- `unzip` is already installed on Fedora; `xz` handling adds a dependency and a second code path.
- Info-ZIP `unzip` **requires a seekable file**, so it cannot stream an archive from a pipe.
  `curl … | tar -xJ` works for `.tar.xz`, but piping hurts error reporting and retries.
- On Windows, .NET can read `.zip` out of the box via `System.IO.Compression`; `.tar.xz` would mean
  shelling out to `tar.exe` and lining up an external process per family.
- Simplicity: one format, one extractor, one guard.

If bandwidth matters more than that, switching to `.tar.xz` in the `urls=` and extract steps
(Fedora) is a small, self-contained change.

## Verify

On Fedora:

```bash
fc-list | grep -ic 'nerd font'                      # count of installed faces
fc-list | grep -i 'nerd font' | head                # sample
```

On Windows, fontconfig does not exist, so check the files and the registry instead:

```powershell
$key = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
(Get-Item $key).Property | Where-Object { $_ -like '*NerdFont*' }
Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Windows\Fonts\*NerdFont*.ttf" | Measure-Object
Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Windows\Fonts\*NerdFont*.otf" | Measure-Object
```

Then **restart your terminal and editor** — already-running processes keep their old font list.
Pick a family such as `JetBrainsMono Nerd Font` in your terminal's font setting.

## Troubleshooting

**`env: 'bash\r': No such file or directory`** — the file has Windows CRLF line endings. The
shebang is read by `env` *before* any script code runs, so the script cannot repair itself; the fix
is external:

```bash
sed -i 's/\r$//' install-nerd-fonts.sh
```

The included `.editorconfig` keeps it LF-only in editors that respect it. If you cloned on Linux
this should never happen — it only bites when the file is copied from Windows.

**`no font archives found at https://www.nerdfonts.com/font-downloads - is it reachable?`** — the
download of the family list failed, or the page markup no longer matches. Both scripts print this
same message. Test the URL in a browser with
`curl -fsSL https://www.nerdfonts.com/font-downloads | head`.

**Fonts installed but not selectable** — you probably skipped `fc-cache`. Run `fc-cache -f` and
restart the terminal.

**`unzip` exits 11** — means "nothing matched the pattern". The script tolerates this explicitly
(`|| [ "$?" -eq 11 ]`) because under `set -e` an unguarded exit 11 would abort the whole run and
skip every remaining family. In practice nothing hits it: `'*.[to]tf'` matches at least one file in
every family.

**`install-nerd-fonts.ps1 cannot be loaded because running scripts is disabled on this system`** —
the default execution policy blocks unsigned scripts. Either run it with a per-process bypass
(`powershell -NoProfile -ExecutionPolicy Bypass -File .\install-nerd-fonts.ps1`) or allow local
scripts for your user once with `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.

**`could not replace <font>.ttf: The process cannot access the file because it is being used by
another process.`** — Windows locks a font file once a process has loaded it, and the lock survives
until the session ends. `RemoveFontResourceW` does not release it, so nothing running can overwrite
that file. The script reports each one as a warning and keeps going, then exits non-zero. Close the
applications using the font, or **sign out and back in**, then re-run the script; files that were
already current are skipped either way, and the rest install normally.

**`-SystemWide installs into C:\Windows\Fonts and needs an elevated session`** — open PowerShell with
*Run as administrator*, or drop `-SystemWide` to install for the current user only.

**`per-user font installs need Windows 10 1809 or later; use -SystemWide on this system.`** — a
warning, not an error: the per-user font folder only exists from that build. On anything older, use
`-SystemWide` from an elevated prompt.

**`no families matched: <pattern>`** — `-FontFamily` matched none of the 72 family names. Use the
archive's base name (`JetBrainsMono`, not `JetBrains Mono Nerd Font`), or a wildcard such as
`'Iosevka*'`.

**Installed, but no application lists the family** — per-user fonts are appended to the registry by
hand, so a viewer that cached its font list before the install will not see them. Restart the
application; if it still does not appear, confirm the registry values from *Verify* above and check
that the file sizes are non-zero.

## Notes

- The catalogue comes from the official download page rather than a hand-maintained list, so new
  families appear automatically. It also pins a known-good release tag, which is why the script can
  print it and why the file set is predictable.
- **14 of the 72 families ship `.otf` instead of `.ttf`**, because they have CFF outlines:
  `AtkinsonHyperlegibleMono`, `AurulentSansMono`, `CodeNewRoman`, `ComicShannsMono`, `CommitMono`,
  `DepartureMono`, `DroidSansMono`, `FiraMono`, `GeistMono`, `Hasklig`, `Hermit`, `Monaspace`,
  `OpenDyslexic` and `Overpass`. Both Windows and fontconfig load OpenType/CFF fonts, so both
  scripts collect `*.ttf` and `*.otf` — a `*.ttf`-only filter silently installs nothing at all for
  those fourteen families.
- nerdfonts.com does **not** host font bytes — it is the project's static site and links every
  archive to the project's GitHub releases. That is upstream's design, not a shortcut taken here.
- Archives are flat and each carries a license file plus a `README.md`; the script's `'*.[to]tf'`
  pattern (or the equivalent `*.ttf`/`*.otf` check in PowerShell) excludes those. License filenames
  vary between families (`LICENSE`, `OFL.txt`, `Vic Fieger License.txt`).
- `NerdFontsSymbolsOnly.zip` also ships `10-nerd-font-symbols.conf`, a fontconfig snippet enabling
  symbol fallback. It is **not** installed by this script — copy it to
  `/etc/fonts/conf.d/` yourself if you want that behaviour. Windows has no fontconfig, so that file
  is irrelevant there; the equivalent is picking a Nerd Font as the terminal's font directly.
- On Windows, per-user registry values hold the full path to the font file while machine-wide
  (`-SystemWide`, HKLM) values hold only the file name. That is Windows' own convention, and the
  script writes whichever matches the destination it used.

## License

The script and this README are released under the [MIT License](LICENSE).

Nerd Fonts itself is a separate project with its own terms — **each font family carries its own
license**, which is why every archive bundles its own license file. Review those if you plan to
redistribute the fonts. See [nerdfonts.com](https://www.nerdfonts.com/) and
[github.com/ryanoasis/nerd-fonts](https://github.com/ryanoasis/nerd-fonts).
