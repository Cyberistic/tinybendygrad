"""sitecustomize: record every file OPEN, with its mode, per process.

The diary test is a PROCESS-level question -- "did the run that consulted this
file also produce it?" -- so it is answered by the interpreter rather than by a
regex over source. Installed by putting this directory on PYTHONPATH; CPython
imports `sitecustomize` automatically at startup unless `-S` is passed.

Writes one JSON object per line to $LEDGER_TRACE_OUT: {"p": path, "w": bool}.
"""
import atexit
import json
import os
import sys

_OUT = os.environ.get("LEDGER_TRACE_OUT")
_ROOT = os.environ.get("LEDGER_TRACE_ROOT", os.getcwd())
_seen = set()


def _hook(event, args):
    if event != "open" or not _OUT:
        return
    try:
        path, mode, flags = args
    except (ValueError, TypeError):
        return
    if isinstance(path, int):  # os.open on some builds hands the fd's path via bytes
        return
    if isinstance(path, bytes):
        path = path.decode("utf-8", "replace")
    if not isinstance(path, str):
        return
    if not path.startswith(_ROOT):
        return
    w = False
    mode_s = ""
    if isinstance(mode, str):
        mode_s = mode
        w = any(c in mode for c in "wax+")
    elif isinstance(flags, int):
        mode_s = "O_WRONLY" if flags & os.O_WRONLY else ""
        if flags & os.O_APPEND:
            mode_s += "|O_APPEND"
        w = bool(flags & (os.O_WRONLY | os.O_RDWR | os.O_APPEND | os.O_CREAT))
    key = (path, w)
    if key in _seen:
        return
    _seen.add(key)
    with open(_OUT, "a", encoding="utf-8") as fh:
        rel = os.path.relpath(path, _ROOT) if path.startswith(_ROOT) else path
        fh.write(json.dumps({"p": rel, "w": w, "m": mode_s}) + "\n")


def _flush():
    pass


sys.addaudithook(_hook)