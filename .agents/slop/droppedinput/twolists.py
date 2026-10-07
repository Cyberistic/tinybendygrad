#!/usr/bin/env python3
"""Are the run's input declarations ONE population or TWO, and does either use the token that
already exists?

`.agents/slop/quiesce/snapshot.py` freezes inputs by copying them. `checks/differ.py` records the
substrate by hashing them. Both declare the same run. Neither imports the other: both are
module-level tuples read by `ast.literal_eval` / direct reference.

This compares them BY DISCOVERY (import both by path, read their tuple), and asks one question
about each member: does the consumer emit the token `ABSENT` when the path is not there, or does
it drop the member?

    usage: .venv/bin/python .agents/slop/droppedinput/twolists.py
"""
from __future__ import annotations

import ast
import importlib.util
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
SNAP = ROOT / ".agents/slop/quiesce/snapshot.py"
DIFFER = ROOT / "checks/differ.py"


def load(p: pathlib.Path, name: str):
    spec = importlib.util.spec_from_file_location(name, p)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def tuple_at(path: pathlib.Path, name: str) -> tuple[str, ...]:
    """The literal members of a module-level tuple, read off the AST so nothing is executed."""
    for node in ast.parse(path.read_text()).body:
        if isinstance(node, ast.Assign) and any(
                isinstance(t, ast.Name) and t.id == name for t in node.targets):
            return tuple(e.value for e in node.value.elts if isinstance(e, ast.Constant))
    return ()


def emits_absent(path: pathlib.Path, member: str) -> bool:
    """Does the file's SOURCE emit the token `ABSENT` on the guard branch for this list? A
    textual test, and deliberately so: the question is what a reader sees, not what an AST infers."""
    src = path.read_text()
    return "ABSENT" in src


def main() -> int:
    snap = load(SNAP, "droppedinput_snapshot")
    copies = tuple(snap.COPIES)
    tooling = tuple(snap.TOOLING)
    sub_inputs = tuple_at(DIFFER, "SUBSTRATE_INPUTS")

    print(f"DECLARATION snapshot.COPIES      n={len(copies)}")
    print(f"DECLARATION differ.SUBSTRATE_INPUTS n={len(sub_inputs)}")
    both = set(copies) & set(sub_inputs)
    only_snap = [c for c in copies if c not in sub_inputs]
    only_diff = [c for c in sub_inputs if c not in copies]
    print(f"INTERSECTION n={len(both)}")
    print(f"ONLY IN snapshot.COPIES ({len(only_snap)}): {only_snap}")
    print(f"ONLY IN differ.SUBSTRATE_INPUTS ({len(only_diff)}): {only_diff}")

    print()
    print("MEMBER-BY-MEMBER. present = on disk; ABSENT-token = the consumer has the token.")
    for c in copies:
        print(f"  {'ok  ' if (ROOT / c).exists() else 'MISS'}  snapshot.COPIES        {c}")
    for c in sub_inputs:
        print(f"  {'ok  ' if (ROOT / c).exists() else 'MISS'}  differ.SUBSTRATE_INPUTS {c}")
    for n in tooling:
        print(f"  {'ok  ' if (ROOT / n).exists() else 'MISS'}  snapshot.TOOLING       {n}")

    print()
    print(f"TOKEN 'ABSENT' in snapshot.py source: {emits_absent(SNAP, 'COPIES')}")
    print(f"TOKEN 'ABSENT' in differ.py   source: {emits_absent(DIFFER, 'SUBSTRATE_INPUTS')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())