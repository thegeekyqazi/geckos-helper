#!/usr/bin/env bash
# Idempotent installer for Gecko's Helper. Re-run any time, and after end-4 updates
# (they overwrite the small to-do add-on in ~/.config/quickshell/ii).
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Installing the gecko command (editable, so repo changes apply)"
uv tool install --editable . --force --quiet

echo "==> Installing the panel (~/.config/quickshell/gecko)"
./quickshell/install-ui.sh

echo "==> end-4 add-ons: to-do widget reload + Super+A / Super+Alt+K keybinds"
~/.local/bin/gecko end4-patch
hyprctl reload >/dev/null 2>&1 || true

echo "==> Installing systemd user units"
mkdir -p ~/.config/systemd/user
cp systemd/*.service systemd/*.timer ~/.config/systemd/user/
systemctl --user daemon-reload

echo "==> Generating the tools context file"
~/.local/bin/gecko context >/dev/null

echo "==> Starting the daemon, the panel and the daily context timer"
systemctl --user enable --now geckos-helper.service geckos-helper-ui.service geckos-helper-context.timer
systemctl --user restart geckos-helper.service geckos-helper-ui.service

echo "Done. Press Super+A, or try: gecko chat"
