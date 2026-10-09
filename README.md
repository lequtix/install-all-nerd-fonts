# nerd-fonts

A single bash script that installs **every Nerd Font family** on Fedora.

Fedora ships nothing for Nerd Fonts, and upstream publishes 72 separate archives with no combined
bundle — so there is no `dnf install` shortcut. This script reads the official family list from
[nerdfonts.com/font-downloads](https://www.nerdfonts.com/font-downloads) and installs all of them.

## Requirements

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

## Install

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

## Usage

```
./install-nerd-fonts.sh [font-directory]
```

With no argument, fonts go to `${XDG_DATA_HOME:-$HOME/.local/share}/fonts/NerdFonts`, which honours
`XDG_DATA_HOME` and needs no root. Passing a directory installs there instead — use
`/usr/share/fonts` for a system-wide install.

Anything starting with `-` is rejected with exit code `2`, so a typo like `--dry-run` fails loudly
rather than silently installing to a directory named `--dry-run`.

### Uninstall

Fonts are plain files in one directory. Remove that directory and refresh the cache:

```bash
rm -rf ~/.local/share/fonts/NerdFonts
fc-cache -f ~/.local/share/fonts
```

## What it does

1. Fetches the official download page and extracts every font archive link from it.
2. Aborts with a clear message if the page yields nothing (offline, or the markup changed).
3. Prints the pinned release tag and the family count.
4. Downloads each archive to a single reused `mktemp` file and unzips only the `*.ttf` members
   straight into the destination.
5. Runs `fc-cache -f` on the fonts root so the fonts appear immediately.
6. Reports how many `.ttf` files were installed.

The temp file is removed on exit via a `trap`, including on failure or `Ctrl-C`.

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

Budget a few minutes and a few GiB of disk. Extraction is the slow part, not the download.

## Why `.zip` when `.tar.xz` is 7× smaller

Every family is published in both formats. The `.tar.xz` set totals **580 MiB** versus **4.03 GiB**
for the `.zip` set — the archives contain byte-identical file sets (same flat layout, no
directories; the difference is purely DEFLATE versus LZMA2).

This script still uses `.zip` deliberately:

- `unzip` is already installed on Fedora; `xz` handling adds a dependency and a second code path.
- Info-ZIP `unzip` **requires a seekable file**, so it cannot stream an archive from a pipe.
  `curl … | tar -xJ` works for `.tar.xz`, but piping hurts error reporting and retries.
- Simplicity: one format, one extractor, one guard.

If bandwidth matters more than that, switching to `.tar.xz` in the `urls=` and extract steps of the
script is a small, self-contained change.

## Verify

```bash
fc-list | grep -ic 'nerd font'                      # count of installed faces
fc-list | grep -i 'nerd font' | head                # sample
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

**`no font archives found at https://www.nerdfonts.com/font-downloads - is it reachable?`** —
`curl` failed, or the page markup no longer matches. Test the URL in a browser with
`curl -fsSL https://www.nerdfonts.com/font-downloads | head`.

**Fonts installed but not selectable** — you probably skipped `fc-cache`. Run `fc-cache -f` and
restart the terminal.

**`unzip` exits 11** — means "nothing matched the pattern". The script tolerates this explicitly
(`|| [ "$?" -eq 11 ]`) because under `set -e` an unguarded exit 11 would abort the whole run and
skip every remaining family.

## Notes

- The catalogue comes from the official download page rather than a hand-maintained list, so new
  families appear automatically. It also pins a known-good release tag, which is why the script can
  print it and why the file set is predictable.
- nerdfonts.com does **not** host font bytes — it is the project's static site and links every
  archive to the project's GitHub releases. That is upstream's design, not a shortcut taken here.
- Archives are flat and each carries a license file plus a `README.md`; the script's `'*.ttf'`
  pattern excludes those. License filenames vary between families (`LICENSE`, `OFL.txt`,
  `Vic Fieger License.txt`).
- `NerdFontsSymbolsOnly.zip` also ships `10-nerd-font-symbols.conf`, a fontconfig snippet enabling
  symbol fallback. It is **not** installed by this script — copy it to
  `/etc/fonts/conf.d/` yourself if you want that behaviour.

## License

The script and this README are released under the [MIT License](LICENSE).

Nerd Fonts itself is a separate project with its own terms — **each font family carries its own
license**, which is why every archive bundles its own license file. Review those if you plan to
redistribute the fonts. See [nerdfonts.com](https://www.nerdfonts.com/) and
[github.com/ryanoasis/nerd-fonts](https://github.com/ryanoasis/nerd-fonts).
