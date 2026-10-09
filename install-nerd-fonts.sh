#!/usr/bin/env bash
# Install every Nerd Font family, using the official list at nerdfonts.com.
#
#   ./install-nerd-fonts.sh                        -> ~/.local/share/fonts
#   sudo ./install-nerd-fonts.sh /usr/share/fonts  -> system-wide
#
# Needs curl, unzip and coreutils; fontconfig (fc-cache) is optional.
# The catalogue comes from the official download page, which pins a known-good
# release and lists only font families. The archives themselves are served from
# the project's GitHub releases - nerdfonts.com links to them, it does not host
# the bytes. These .zip assets are ~7x larger than the .tar.xz equivalents
# (4.0 GiB vs 580 MiB) and need a temp file, but hold the exact same files.
set -euo pipefail

case "${1:-}" in
	-*) echo "usage: $0 [font-directory]" >&2; exit 2 ;;
esac

for c in curl unzip; do
	command -v "$c" >/dev/null || { echo "$c is required but not installed" >&2; exit 1; }
done

site=https://www.nerdfonts.com/font-downloads
root=${1:-${XDG_DATA_HOME:-$HOME/.local/share}/fonts}
dest="$root/NerdFonts"

# "|| true" so an empty grep match cannot trip pipefail before the check below.
urls=$(curl -fsSL "$site" \
	| grep -o 'https://github\.com/ryanoasis/nerd-fonts/releases/download/[^"]*\.zip' \
	| sort -u || true)
[ -n "$urls" ] || { echo "no font archives found at $site - is it reachable?" >&2; exit 1; }

tag=$(printf '%s\n' "$urls" | sed -n 's|.*/download/\([^/]*\)/.*|\1|p' | sort -u)
echo "Nerd Fonts $tag -> $dest"
echo "Installing $(printf '%s\n' "$urls" | wc -l) font families"

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

mkdir -p "$dest"
printf '%s\n' "$urls" | while read -r url; do
	echo "  ${url##*/}"
	curl -fsSL "$url" -o "$tmp"
	unzip -qo "$tmp" '*.ttf' -d "$dest" || [ "$?" -eq 11 ]   # 11 = nothing matched the pattern
done

if command -v fc-cache >/dev/null 2>&1; then
	fc-cache -f "$root"
else
	echo "fc-cache not found - install fontconfig, then run 'fc-cache -f'" >&2
fi

echo "Installed $(find "$dest" -name '*.ttf' | wc -l) font files into $dest"
echo "Restart your terminal/editor, then pick a family such as 'JetBrainsMono Nerd Font'."