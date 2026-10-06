#!/usr/bin/env python3
"""Reproduce the crash `gates/wk-cd-gate.py` reported, and discriminate BOTH ways.

    .venv/bin/python .agents/slop/refusalsweep/repro.py

The report: an absent `gates/artifacts/` made `gatekit`'s staged oracle write raise
`FileNotFoundError: '…/gates/artifacts/<gate>/.tmp.py.rows'`. `gates/artifacts/` is
`.gitignore`d, and `AGENTS.md` records `rm -rf gates/artifacts` as a live command, so the
directory can be removed BETWEEN construction and the write. The FIX is `gatekit._ensure_dir`:
an OUTPUT directory the gate owns is CREATED, at construction AND at the top of `run()`; only
an uncreatable one is REFUSED (exit 3).

Every state runs over the REAL `gatekit.py` source and the REAL `wk-cd-oracle.py`, with
`gatekit.ART` pointed at a TEMP directory, so the live `gates/artifacts/` is never touched.
No `bend` runs: this exercises the constructor, `_ensure_dir`, and `_oracle` -- exactly the
write the report named.
"""
from __future__ import annotations

import pathlib
import shutil
import sys
import tempfile
import traceback

ROOT = pathlib.Path(__file__).resolve().parents[3]
KIT = ROOT / "gates" / "gatekit.py"
ORACLE = "wk-cd-oracle.py"                # pure CPython, resolved beside the real gatekit


def load(module_file: pathlib.Path, art: pathlib.Path) -> dict:
    """Exec a copy of gatekit with `__file__` at its REAL path, so `_resolve`/`HERE` are intact.
    `ART` is rebound to the temp dir AFTER exec, because the module's own `ART = HERE / ...`
    assignment would otherwise overwrite anything bound before `exec` ran."""
    ns: dict = {"__file__": str(module_file), "__name__": "gatekit_repro"}
    exec(compile(module_file.read_text(), str(module_file), "exec"), ns)  # noqa: S102
    ns["ART"] = art
    return ns


def state(dir_removed: bool, ensure: bool) -> tuple[bool, str, int | None]:
    """Construct a Gate, optionally remove its output dir mid-run, optionally re-ensure it, then
    run the oracle write. Returns (crashed, detail, ensure_rc)."""
    with tempfile.TemporaryDirectory() as td:
        art = pathlib.Path(td) / "artifacts"
        ns = load(KIT, art)
        g = ns["Gate"]("repro", bend="wk-cd.bend", oracle=ORACLE, rows=1)
        rc = None
        if dir_removed:
            shutil.rmtree(art)                     # `rm -rf gates/artifacts`, mid-run
        if ensure:
            rc = g._ensure_dir()                   # the FIX: run()'s first step
        try:
            ok = g._oracle()
            return (not ok), f"_oracle() -> {ok}", rc
        except FileNotFoundError as e:
            frames = traceback.extract_tb(sys.exc_info()[2])
            kit = [f for f in frames if pathlib.Path(f.filename).name == KIT.name]
            last = kit[-1] if kit else frames[-1]
            return True, f"{type(e).__name__} at {pathlib.Path(last.filename).name}:" \
                         f"{last.lineno} (in {last.name}): {e}", rc


def uncreatable() -> tuple[int, bool]:
    """A FILE where the gate's directory must go: the constructor must not crash, and
    `_ensure_dir` must REFUSE (3)."""
    with tempfile.TemporaryDirectory() as td:
        art = pathlib.Path(td) / "artifacts"
        art.write_text("not a directory\n")
        ns = load(KIT, art)
        try:
            g = ns["Gate"]("repro", bend="wk-cd.bend", oracle=ORACLE, rows=1)
        except Exception:
            return -1, False                       # a constructor crash would be the old bug
        return g.dir_rc, True                      # the constructor's `_ensure_dir` verdict


def main() -> int:
    crashed, detail, _ = state(dir_removed=False, ensure=False)
    print(f"A dir ABSENT at construction:      crashed={crashed}  {detail}  "
          f"(constructor `_ensure_dir` creates it -- no exception)")

    pre, pre_detail, _ = state(dir_removed=True, ensure=False)
    print(f"B dir removed mid-run, NO ensure:   crashed={pre}  {pre_detail}")

    post, post_detail, rc = state(dir_removed=True, ensure=True)
    print(f"C dir removed mid-run, WITH ensure: crashed={post}  {post_detail}  ensure_rc={rc}")

    rc_bad, constructor_ok = uncreatable()
    print(f"D out dir UNCREATABLE:              constructor_ok={constructor_ok}  "
          f"_ensure_dir rc={rc_bad} (REFUSED=3)")

    both = pre and not post and rc == 0 and rc_bad == 3 and constructor_ok
    print(f"\nBOTH-WAYS: {'OK -- B crashes where C does not; D refuses; A creates' if both else 'FAILED'}")
    return 0 if both else 1


if __name__ == "__main__":
    sys.exit(main())
