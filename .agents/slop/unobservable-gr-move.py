#!/usr/bin/env python3
"""PROOF THAT `.agents/slop/unobservable-gr-probe.bend`'s ROW ACTUALLY MOVES.

A row that cannot fail is not a fixture. This measures the probe under three
behaviours of `tinybendygrad/codegen/__init__.bend`, in a FROZEN COPY whose md5
is asserted equal to the live tree first, and reports which of the three answer
CPython's value and which do not.

  BASE    as committed: `pm_post_sched_cache()` carries a `SINK -> self` rule
          (tag 0 -> `pm_r_sink_m` -> `Some{self}`) and `wr.step.scan` passes `u`.

  M-u     `pm_rewrite_m(pm, ar, u, ctx)` -> `(pm, ar, rebuilt, ctx)`. This is the
          mutation the brief names, and it is the one the existing one-row gate
          CANNOT see.

  M-norule  the `SINK` PMEntry is dropped from the table, so no rule claims the
          SINK. Upstream's `pm_post_sched_cache` has NO SINK rule -- read off
          the pattern objects, two rules, PARAM and ALLOC -- so M-norule is the
          port moving TOWARDS upstream. It isolates the spurious rule from the
          arena wall.

CPython's expected value is NOT typed here; it is read out of
`.agents/slop/unobservable-gr-oracle.py`'s Q4 answer, which CALLS tinygrad.
This script only runs the Bend side.

Run:  .venv/bin/python .agents/slop/unobservable-gr-move.py
"""
from __future__ import annotations

import hashlib
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
PORT = "codegen/__init__.bend"
PROBE = "unobservable-gr-probe.bend"

MUTANTS = {
    "BASE": [],
    "M-u": [("wr.step.try_rule(u, O.pm_rewrite_m(pm, ar, u, ctx), repl, rebuilt)",
             "wr.step.try_rule(u, O.pm_rewrite_m(pm, ar, rebuilt, ctx), repl, rebuilt)")],
    "M-norule": [("O.PMEntrys{[O.PMEntry{0, [O.OpsSINK{}], Nil{}}, "
                  "O.PMEntry{3, [O.OpsPARAM{}], Nil{}}, O.PMEntry{4, [O.OpsALLOC{}], Nil{}}]}",
                  "O.PMEntrys{[O.PMEntry{3, [O.OpsPARAM{}], Nil{}}, "
                  "O.PMEntry{4, [O.OpsALLOC{}], Nil{}}]}")],
}


def freeze() -> pathlib.Path:
    d = pathlib.Path(tempfile.mkdtemp(prefix="gr-move-"))
    shutil.copytree(ROOT / "tinybendygrad", d / "tinybendygrad", symlinks=True)
    (d / ".agents" / "slop").mkdir(parents=True)
    shutil.copy(ROOT / ".agents" / "slop" / PROBE,
                d / ".agents" / "slop" / PROBE)
    (d / "bin").mkdir()
    os.symlink(ROOT / "references", d / "references")
    os.symlink(ROOT / "bin" / "bend", d / "bin" / "bend")
    bad = []
    for rel in ("tinybendygrad/" + PORT, ".agents/slop/" + PROBE):
        a = hashlib.md5((ROOT / rel).read_bytes()).hexdigest()
        b = hashlib.md5((d / rel).read_bytes()).hexdigest()
        if a != b:
            bad.append(rel)
    if bad:
        raise SystemExit("FROZEN COPY DOES NOT REPRODUCE THE LIVE TREE: " + ", ".join(bad))
    print("frozen copy reproduces the live tree (md5-verified on the port and the probe)")
    return d


def run(d: pathlib.Path, probe_rel: str, tries: int = 6) -> str:
    for _ in range(tries):
        r = subprocess.run([str(d / "bin" / "bend"), str(d / probe_rel)],
                           capture_output=True, text=True, cwd=str(d), timeout=1800)
        if "gr.sink_srcs" in r.stdout:
            return r.stdout.strip()
    return "ZERO ROWS AFTER %d TRIES: %s" % (tries, r.stderr.strip().splitlines()[:2])


def main() -> int:
    d = freeze()
    # the probe's imports are written for its home in .agents/slop/, so the
    # frozen tree keeps the same shape.
    probe_rel = ".agents/slop/" + PROBE
    port = d / "tinybendygrad" / PORT
    orig = port.read_text()
    print()
    print("CPython, CALLED (`.agents/slop/unobservable-gr-oracle.py` Q4):")
    print("    gr.sink_srcs = PARAM(99),PARAM(100),BUFFER")
    print("    (upstream returns a NEW SINK whose srcs are the REWRITTEN ones)")
    print()
    print("=" * 96)
    out = {}
    for name, subs in MUTANTS.items():
        text = orig
        for old, new in subs:
            n = text.count(old)
            if n != 1:
                print(f"PATCH DID NOT APPLY  {name}: anchor appears {n} times")
                out[name] = "PATCH DID NOT APPLY"
                continue
            text = text.replace(old, new)
        port.write_text(text)
        try:
            out[name] = run(d, probe_rel)
        finally:
            port.write_text(orig)
        ok = out[name].strip() == "gr.sink_srcs=PARAM(99),PARAM(100),BUFFER,"
        print(f"  {name:9} -> {out[name]}")
        print(f"  {'':9}    {'MATCHES CPYTHON' if ok else 'DOES NOT MATCH CPYTHON'}")
    print()
    uniq = len({v for v in out.values()})
    print(f"distinct answers across {len(out)} behaviours: {uniq}")
    if uniq < 2:
        print("THE ROW IS BLIND -- every behaviour gives the same answer. NOT A FIXTURE.")
    else:
        moved = sorted(k for k in out if k != "BASE" and out[k] != out["BASE"])
        print(f"the row MOVES under: {', '.join(moved) if moved else 'NOTHING'}")
    shutil.rmtree(d)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
