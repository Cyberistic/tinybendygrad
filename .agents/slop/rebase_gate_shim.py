#!/usr/bin/env python3
"""dd-split-shim: load rebase-gate.py by PATH so dd-split.py uses the GATE'S OWN rows().

A shim, not a reimplementation: `rebase-gate.py`'s filename is not an identifier, so it
cannot be `import`ed, and copying its rows() would be a second parser -- which is exactly
the "SAME parser" requirement this file exists to satisfy. The function object below IS
`rebase_gate.rows`, pulled out of the file by path.
"""
import importlib.util
import pathlib

_GATE = pathlib.Path(__file__).resolve().parent / "rebase-gate.py"
_spec = importlib.util.spec_from_file_location("rebase_gate", _GATE)
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)

rows = _mod.rows  # the gate's own parser, verbatim