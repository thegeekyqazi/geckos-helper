#!/usr/bin/env bash
# Removes the command and services. Keeps your config, chats and state in
# ~/.config, ~/.local/share and ~/.local/state /geckos-helper.
set -euo pipefail
systemctl --user disable --now geckos-helper.service geckos-helper-context.timer 2>/dev/null || true
rm -f ~/.config/systemd/user/geckos-helper{.service,-context.service,-context.timer}
systemctl --user daemon-reload
uv tool uninstall geckos-helper 2>/dev/null || true
echo "Uninstalled. Data kept in ~/.config/geckos-helper, ~/.local/share/geckos-helper, ~/.local/state/geckos-helper"
