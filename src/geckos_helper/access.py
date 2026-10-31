"""Shared runtime access checks for desktop MCP tools and daemon shortcuts."""

from . import config


def require(capability: str | None = None) -> None:
    state = config.load_state()
    if state['killed']:
        raise PermissionError("Gecko's Helper kill switch is on; desktop access is disabled.")
    if capability and not state['capabilities'].get(capability, False):
        raise PermissionError(f"The user has turned off the '{capability}' capability.")


def call(capability, fn, *args, **kwargs):
    """Check inside the worker, immediately before accessing desktop data."""
    require(capability)
    return fn(*args, **kwargs)
