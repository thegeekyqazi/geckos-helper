#!/usr/bin/env bash
# Removes the command, panel, services, keybinds and end-4 add-ons. Keeps your
# config, chats and state in ~/.config, ~/.local/share and ~/.local/state /geckos-helper.
set -euo pipefail
systemctl --user disable --now geckos-helper.service geckos-helper-ui.service geckos-helper-context.timer 2>/dev/null || true
~/.local/bin/gecko end4-patch --revert 2>/dev/null || true
hyprctl reload >/dev/null 2>&1 || true
rm -f ~/.config/systemd/user/geckos-helper{.service,-ui.service,-context.service,-context.timer}
rm -rf ~/.config/quickshell/gecko
systemctl --user daemon-reload
uv tool uninstall geckos-helper 2>/dev/null || true
echo "Uninstalled. Data kept in ~/.config/geckos-helper, ~/.local/share/geckos-helper, ~/.local/state/geckos-helper"
