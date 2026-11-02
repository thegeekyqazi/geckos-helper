"""Native Claude Code modes, shared by daemon, CLI and panel.

These control approvals, not an OS sandbox. Never emulate auto mode with a
blanket allow: Claude Code's own classifier must make those decisions.
"""

MODES = [
    {"id": "default", "label": "Manual", "description": "Ask before actions that need approval."},
    {"id": "acceptEdits", "label": "Accept edits", "description": "Auto-accept edits and common filesystem commands in working directories; ask for other actions."},
    {"id": "plan", "label": "Plan", "description": "Explore and plan using Claude Code's native Plan mode before implementing."},
    {"id": "auto", "label": "Auto", "description": "Claude Code's classifier reviews actions instead of routine prompts. Requires backend support."},
    {"id": "dontAsk", "label": "Don't ask", "description": "Deny actions that would prompt; preapproved actions can still run."},
    {"id": "bypassPermissions", "label": "Full access", "description": "Skip approval checks, including protected-file edits. Commands use your account's access; no OS sandbox is added."},
]
IDS = tuple(m["id"] for m in MODES)


def validate(mode: str) -> str:
    if mode == "manual":
        return "default"
    if mode not in IDS:
        raise ValueError(f"Unknown permission mode {mode!r}. Choose: {', '.join(IDS)}")
    return mode


def native(mode: str) -> str:
    # Current Claude CLI names the old default mode 'manual'.
    mode = validate(mode)
    return "manual" if mode == "default" else mode
