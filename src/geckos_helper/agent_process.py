"""Own short-lived agent processes, including cancellation during process creation."""

import asyncio
import contextlib
import os
import signal

from . import access

ACTIVE: set[asyncio.Task] = set()


async def _stop(proc) -> None:
    # Each invocation gets its own session; stop MCP descendants as well as the CLI.
    with contextlib.suppress(ProcessLookupError):
        os.killpg(proc.pid, signal.SIGTERM)
    try:
        await asyncio.wait_for(proc.wait(), 2)
    except TimeoutError:
        with contextlib.suppress(ProcessLookupError):
            os.killpg(proc.pid, signal.SIGKILL)
        await proc.wait()
    # A child may ignore TERM even if the group leader already exited.
    with contextlib.suppress(ProcessLookupError):
        os.killpg(proc.pid, signal.SIGKILL)


async def run(argv: list[str], text: str, timeout: float, *, cwd=None, capability=None):
    """Return (stdout, stderr, status); always reap the agent and its process group."""
    access.require(capability)
    task = asyncio.current_task()
    ACTIVE.add(task)
    proc = None
    spawn = asyncio.create_task(asyncio.create_subprocess_exec(
        *argv, cwd=cwd, start_new_session=True, stdin=asyncio.subprocess.PIPE,
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE))
    try:
        try:
            proc = await asyncio.shield(spawn)
        except asyncio.CancelledError:
            # Cancellation must not abandon a process still being spawned.
            proc = await spawn
            raise
        access.require(capability)  # the switch may have changed while spawning
        out, err = await asyncio.wait_for(proc.communicate(text.encode()), timeout)
        return out, err, proc.returncode
    finally:
        try:
            if proc is not None:
                await _stop(proc)
        finally:
            ACTIVE.discard(task)


async def stop_all() -> None:
    tasks = [t for t in ACTIVE if t is not asyncio.current_task()]
    for task in tasks:
        task.cancel()
    await asyncio.gather(*tasks, return_exceptions=True)
