"""Exec the manifest-selected owned runtime. Never builds or downloads implicitly."""
import os
from runtime import RuntimeManager

explicit = os.environ.get("LYRIC_ISLAND_BACKEND")
if explicit:
    os.execv(explicit, [explicit, "--stdio"])
state = RuntimeManager().status()
if state["status"] == "development":
    os.execvp("dotnet", ["dotnet", state["path"], "--stdio"])
if state["status"] == "ready":
    os.execv(state["path"], [state["path"], "--stdio"])
raise SystemExit("backend_not_installed")
