#!/usr/bin/env python3
"""End-to-end freeze check on a COPY of the real tree: build `snapshot.py` against a cloned
source, edit that clone, and prove the frozen snapshot did not move while the source did.

    usage: .venv/bin/python .agents/slop/quiesce/freeze-check.py

WHY A COPY. The property to prove is "editing the LIVE source does not change the SNAPSHOT", and
the live source (`tinybendygrad/`, `.agents/slop/graphcmp.bend`) is off-limits to this unit and is
being written by others. A clone of the real 140-file port exercises the same `build`/`verify` code
on the same bytes; a two-file toy would prove the toy. The real snapshot in §4 is built separately;
this is the controlled half that the quiet window could not supply.
"""
from __future__ import annotations

import hashlib
import importlib.util
import shutil
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def load_snapshot():
    # `checks/substrate-snapshot.py`, NOT a sibling: the declaration moved out of
    # `.agents/slop/quiesce/` into git on 2026-10-08 -- `git ls-tree -r HEAD --
    # .agents/slop/quiesce/` answered 0 paths, so a gate loading it by path measured nothing on a
    # `git archive HEAD` tree and said PASS.
    spec = importlib.util.spec_from_file_location("snap", ROOT / "checks/substrate-snapshot.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main() -> int:
    snapmod = load_snapshot()
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        fake, dest = td / "clone", td / "snap"
        # Clone the REAL input set: the port by walk, the harness files, and symlinked toolchain.
        (fake / "tinybendygrad").parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(ROOT / "tinybendygrad", fake / "tinybendygrad")
        (fake / "checks").mkdir()
        for f in ("differ.py", "devpin.py"):
            shutil.copy2(ROOT / "checks" / f, fake / "checks" / f)
        (fake / "bin").mkdir()
        shutil.copy2(ROOT / "bin/bend", fake / "bin/bend")
        (fake / ".agents/slop").mkdir(parents=True)
        for f in sorted((ROOT / ".agents/slop").glob("graphcmp*")):
            if f.is_file():
                shutil.copy2(f, fake / ".agents/slop" / f.name)
        for t in (".venv", "references", "tinygrad"):
            (fake / t).symlink_to(ROOT / t)

        kept = snapmod.ROOT
        try:
            snapmod.ROOT = fake
            snapmod.build(dest, None)
            target = "tinybendygrad/tensor.bend"
            before_snap = sha(dest / target)
            before_live = sha(fake / target)
            # EDIT THE CLONE, exactly as a unit writing the port would.
            with (fake / target).open("a") as f:
                f.write("\n# a concurrent unit edited the live tree\n")
            after_snap = sha(dest / target)
            after_live = sha(fake / target)
        finally:
            snapmod.ROOT = kept

        print(f"  snapshot {target}: {before_snap[:12]} -> {after_snap[:12]}")
        print(f"  clone    {target}: {before_live[:12]} -> {after_live[:12]}")
        frozen = before_snap == after_snap
        moved = before_live != after_live
        print(f"  {'PASS' if frozen else 'FAIL'}  live clone edited -> snapshot UNCHANGED")
        print(f"  {'PASS' if moved else 'FAIL'}  the edit reached the clone (so the test is live)")
        rc = 0 if frozen and moved else 1
        print(f"FREEZE-CHECK: {'OK' if rc == 0 else 'FAILED'}")
        return rc


if __name__ == "__main__":
    sys.exit(main())
