#!/usr/bin/env bash
# Idempotent installer for Gecko's Helper. Re-run any time (also after end-4 updates).
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Installing the gecko command (editable, so repo changes apply)"
uv tool install --editable . --force --quiet

echo "==> Installing systemd user units"
mkdir -p ~/.config/systemd/user
cp systemd/*.service systemd/*.timer ~/.config/systemd/user/
systemctl --user daemon-reload

echo "==> Generating the tools context file"
~/.local/bin/gecko context >/dev/null

echo "==> Starting the daemon and the daily context timer"
systemctl --user enable --now geckos-helper.service geckos-helper-context.timer
systemctl --user restart geckos-helper.service

echo "Done. Try: gecko chat"
