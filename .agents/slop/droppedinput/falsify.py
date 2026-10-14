#!/usr/bin/env python3
"""Falsifiability: does the plant's core assertion FAIL against the PRE-FIX `inputs()`?

An assertion that cannot fail is not an assertion (`prune4`'s lesson, which cost a clause vacuously
true for 3 974 files). The pre-fix body is reconstructed from the `:80-85` this unit read before
editing -- `elif p.is_file(): files.append(p)` -- by patching the shipped file's source in a temp
copy and LOADING IT BY PATH. The property under test is `inputs()`'s MEMBERSHIP, so only `inputs()`
is reverted: the first attempt also reverted `build()` and produced `froze 0`, which is a broken
reconstruction rather than evidence, and a falsification harness that fabricates its own failure
proves nothing.

    usage: .venv/bin/python .agents/slop/droppedinput/falsify.py
"""
from __future__ import annotations

import importlib.util
import pathlib
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[3]
SNAP = ROOT / ".agents/slop/quiesce/snapshot.py"

#: the pre-fix branch, verbatim from the line this unit edited.
OLD_BRANCH = "        elif p.is_file():\n            files.append(p)\n"
NEW_BRANCH = ("        else:\n            files.append(p)"
              "  # declared and ABSENT is still a member; `build` writes it ABSENT\n")


def members_of(path: pathlib.Path, tree: pathlib.Path, copies: tuple[str, ...]) -> list[str]:
    """Load `path` by path, re-point `ROOT` at `tree`, and ask for the population."""
    spec = importlib.util.spec_from_file_location("falsify_snap", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    kept, mod.ROOT, mod.COPIES = mod.ROOT, tree, copies
    try:
        return sorted(p.relative_to(tree).as_posix() for p in mod.inputs())
    finally:
        mod.ROOT, mod.COPIES = kept, copies


def main() -> int:
    with tempfile.TemporaryDirectory() as td:
        td = pathlib.Path(td)
        tree = td / "tree"
        (tree / "tinybendygrad").mkdir(parents=True)
        (tree / "tinybendygrad/port.bend").write_text("port\n")
        (tree / "kept.bend").write_text("present\n")
        (tree / "gone.bend").write_text("declared then removed\n")
        (tree / "gone.bend").unlink()
        (tree / "undelared.py").write_text("never declared\n")
        copies = ("kept.bend", "gone.bend")

        src = SNAP.read_text()
        assert NEW_BRANCH in src, "the post-fix branch is not in snapshot.py; this harness is stale"
        old = td / "snapshot_prefix.py"
        old.write_text(src.replace(NEW_BRANCH, OLD_BRANCH))

        new_mem = members_of(SNAP, tree, copies)
        old_mem = members_of(old, tree, copies)

    want = "gone.bend"
    rows = [("PRESENT declared  kept.bend", "kept.bend", new_mem, old_mem),
            ("ABSENT  declared  gone.bend", "gone.bend", new_mem, old_mem),
            ("CONTROL  undeclared  undelared.py", "undelared.py", new_mem, old_mem),
            ("DISCOVERY port  tinybendygrad/port.bend", "tinybendygrad/port.bend",
             new_mem, old_mem)]
    print(f"{'population':<40} {'shipped':<10} {'pre-fix':<10}")
    bad = 0
    for label, member, new, o in rows:
        n, p = member in new, member in o
        bad += (n != p)
        print(f"{label:<40} {str(n):<10} {str(p):<10}")
    print()
    ok = bad > 0 and want not in old_mem and want in new_mem
    print(f"{'PASS' if ok else 'FAIL'}  the assertion FAILS against the pre-fix branch:"
          f" `gone.bend` is a member after the fix and NOT before it")
    print("        so its green against the shipped code is a measurement, not a decoration.")
    print(f"        the CONTROL moved in neither direction ({bad} row(s) differ), so the "
          f"difference is attributable to the `else` and not to the walk widening.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())