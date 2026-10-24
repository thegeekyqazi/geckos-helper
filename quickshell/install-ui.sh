#!/usr/bin/env bash
# Builds ~/.config/quickshell/gecko: our shell.qml plus symlinks to our components
# and to end-4's common widgets/services/assets (so the panel matches the theme).
set -euo pipefail
repo="$(cd "$(dirname "$0")" && pwd)/gecko"
ii="$HOME/.config/quickshell/ii"
dest="$HOME/.config/quickshell/gecko"

[ -d "$ii" ] || { echo "end-4 quickshell config not found at $ii" >&2; exit 1; }
mkdir -p "$dest/modules"
cp "$repo/shell.qml" "$dest/shell.qml"   # copied: a symlinked shell.qml would move the config root
ln -sfn "$repo/gecko" "$dest/gecko"
ln -sfn "$ii/modules/common" "$dest/modules/common"
for d in services assets translations GlobalStates.qml; do
    ln -sfn "$ii/$d" "$dest/$d"
done
