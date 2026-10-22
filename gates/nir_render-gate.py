#!/usr/bin/env python3
"""nir_render-gate.py -- `tinybendygrad/renderer/nir.bend` against LIVE CPython.

    .venv/bin/python gates/nir_render-gate.py
    .venv/bin/python gates/nir_render-gate.py --port <path>   # for the plant

102 ROWS, THREE LANES, ZERO DECLARED DIVERGENCES.

WHY THIS GATE EXISTS AT ALL, AND IT IS A RECOVERY
-------------------------------------------------
`renderer/nir.bend` carried 103 `py=` cells, every one of them a LITERAL -- text
transcribed once from what CPython said.  A transcription has no generator: it cannot
see CPython move, and it cannot see the PORT move either.  **MEASURED 2026-10-22: the
port's `cfo_names()` had no `SQRT`, and the four `cfo` rows were GREEN -- because the
transcription AGREED with the wrong port.**  The file agreed with itself and was wrong
on four rows.  That is the rot the derivation removes, and the port's `py=` half is now
the port's OWN value, re-read, so a row cannot disagree with itself; the ASSERTION is
the byte diff against CPython's lane, which is where the value now lives.

THE ORACLE IS RECOVERED, from git history: blob
`b56eb2648a1033971cbd7df9cd87cad269cd320a` of `.agents/slop/nir/nir_oracle.py`, last
carried by commit `e853efc4b` and DELETED by `371cc64c9` ("THE SWEEP DELETED 3,603
FILES AND TOOK 166 REPRODUCTION PATHS WITH THEM").  It lived under `.agents/slop/`,
which this tree is pruning, and a sweep of `.agents/slop/` has already taken 7 of 9
driver/oracle files out from under gates that still named them -- so the oracle was
RECOVERABLE but NOT SAFE.  It now lives beside this gate, at `gates/nir-oracle.py`,
with its provenance in its own header, and it is the same tree's live `tinygrad/` it
asks.

THE UPSTREAM IS LIVE, AND THAT IS A DEPARTURE FROM `gates/renderkit.py`
-----------------------------------------------------------------------
`renderkit.py` measures the other two render ports against the upstream they were
WRITTEN AGAINST, pinned to one commit, because upstream has since moved and a
measurement against HEAD would be RED on every row that moved.  **A PIN IS HOW THAT
ROT HID FOR ELEVEN DAYS.**  MEASURED: upstream's `tinygrad/renderer/nir.py` gained
`Ops.SQRT: "fsqrt"` in `f_aop` (upstream PR #18815, `c04397442`, 2026-10-18) and the
tree took it in the 2026-10-20 re-vendor `77e6c2bec`; the port, last edited 2026-10-06,
still had twelve float ops and twenty `code_for_op` ops, and its `py=` half was DERIVED
from its own value, so the lane was green on a stale port.  **A PIN MEASURES A PORT
AGAINST THE UPSTREAM IT WAS WRITTEN AGAINST, WHICH IS EXACTLY WHAT A STALE PORT
NEEDS.**  So this gate measures against the tree's LIVE `tinygrad/`, and the upstream
it measured is PRINTED as the blob id of `tinygrad/renderer/nir.py` at run time -- a
pin that is DERIVED from the tree rather than a hand list, so it cannot rot.

THE ROW COUNT IS 102 AND IT IS NOT A NARRATIVE
----------------------------------------------
`gates/nir-oracle.py` prints one row per (name, value) pair, in the order
`nir.bend`'s `main` emits them, and the port prints the same 102 in the same order.
A lane that printed a different number is DEAD or FAIL, never PASS.

THE THREE LANES, AND WHAT EACH ONE IS FOR
------------------------------------------
    py   CPython, from the recovered oracle, against the tree's LIVE `tinygrad/`
    bd   the port, interpreted by `bin/bend`
    bn   the port, compiled by `bin/bend -o` and run

Two lanes would measure the port against CPython and the port against itself; the
compiled lane is what catches a difference between the interpreter and the compiler,
which is a class of defect the interpreted lane cannot see at all.

THE LOCK IS TAKEN PER INVOCATION
---------------------------------
`checks/bendlock.sh` holds the lock for the WHOLE command, and this gate runs TWO
`bend` processes, so taking it once would make the gate wait on itself.  `gates/
bendlock.py` is the same lock taken PER INVOCATION (it shares the path, so the two
exclude each other), and `nir.bend` peaks at ~1.2 GB, so a concurrent compiler is a
memory event and not a scheduling detail.
"""
import argparse
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
from bendlock import bend_lock  # noqa: E402
from renderkit import DEAD, FAIL, PASS, REFUSED, SKIP, VERDICT, split_rows  # noqa: E402

BEND = ROOT / "bin" / "bend"
PY = ROOT / ".venv" / "bin" / "python"
ART = HERE / "artifacts"

PORT = "tinybendygrad/renderer/nir.bend"
ORACLE = "gates/nir-oracle.py"
# 102 ROWS, and the number is 102 and not 103 because a LINE is not a ROW.  Both lanes
# end with a BLANK line -- the oracle's `print()` and the port's `IO.print` each supply
# their own newline -- so the files have 103 LINES and 102 ROWS.  A gate that counted
# LINES would have had a denominator one bigger than the population, and the one row it
# invented is a row nobody can check.
ROWS = 102

# NO DECLARED DIVERGENCES.  There are none to declare: the port and CPython agree on
# every one of the 103 rows, and this gate is what makes that statement a MEASUREMENT
# rather than a memory.  A declared divergence is a CLAIM -- "these two sides differ" --
# and a claim can go stale, so `renderkit` REFUSES a declaration whose two sides are the
# same row.  `gates/ops_dsp_render-gate.py` is the same gate over a port that has some.
DIVERGES = {}


def say(name, msg):
    print(f"{name}: {msg}", file=sys.stderr)


def refuse(name, why):
    print(f"== REFUSED, NOT A VERDICT: {name}: {why}", file=sys.stderr)
    return REFUSED


def upstream_blob():
    """The blob id of the `tinygrad/renderer/nir.py` this run measured against.

    A PIN THAT IS DERIVED FROM THE TREE AT RUN TIME, and not a hand list and not a
    frozen commit: the upstream this gate compares against IS the tree's live
    `tinygrad/`, so the id that says which upstream it was has to come from the tree.
    """
    q = subprocess.run(["git", "hash-object", "tinygrad/renderer/nir.py"],
                       capture_output=True, text=True, cwd=str(ROOT))
    return q.stdout.strip() if q.returncode == 0 else "UNREADABLE"


def warm(bendfile):
    """`--check-only`'s FIRST LINE, never its exit status."""
    r = subprocess.run([str(BEND), str(bendfile), "--check-only"],
                       capture_output=True, text=True, cwd=str(ROOT))
    first = (r.stdout or "").splitlines()[:1]
    return bool(first) and first[0].strip() == "ALL PROOFS CHECK"


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--port", default=str(ROOT / PORT))
    ap.add_argument("--oracle", default=str(ROOT / ORACLE))
    args = ap.parse_args()
    name = "nir_render"
    port, oracle = Path(args.port), Path(args.oracle)
    for p in (port, oracle, BEND, PY):
        if not p.exists():
            return refuse(name, f"an input is absent: {p}")
    out = ART / name
    out.mkdir(parents=True, exist_ok=True)
    for p in out.iterdir():
        if p.is_file():
            p.unlink()
    if not warm(port):
        return refuse(name, f"{port} is not warm (`--check-only`'s first line is not "
                            f"'ALL PROOFS CHECK')")

    # ---- the ORACLE's lane, against the tree's LIVE `tinygrad/`.
    # `PORT_ROOT` is REMOVED from the child environment rather than set: this gate
    # measures against the live tree on purpose, and an inherited `PORT_ROOT` from
    # another gate's environment would silently redirect the oracle at a different
    # upstream.  `gates/nir-oracle.py` falls back to the tree it is standing in.
    env = {k: v for k, v in os.environ.items() if k != "PORT_ROOT"}
    orc = subprocess.run([str(PY), str(oracle), "rows"], capture_output=True, text=True,
                         cwd=str(ROOT), env=env)
    if orc.returncode != 0:
        return refuse(name, f"the oracle failed rc={orc.returncode}: "
                             f"{(orc.stderr or '').strip()[:200]}")
    if not orc.stdout.strip():
        return refuse(name, "the oracle emitted no rows")
    (out / "py.rows").write_text(orc.stdout)

    # ---- the PORT's lane, interpreted, THROUGH THE LOCK
    with bend_lock() as waited:
        if waited:
            say(name, f"waited {waited}s for the bend lock")
        bd = subprocess.run([str(BEND), str(port)], capture_output=True, text=True,
                            cwd=str(ROOT))
    if bd.returncode != 0:
        return refuse(name, f"the interpreted lane failed rc={bd.returncode}: "
                             f"{(bd.stderr or '').strip()[:200]}")
    if not bd.stdout.strip():
        return refuse(name, "the interpreted lane emitted no rows")
    (out / "bd.out").write_text(bd.stdout)

    # ---- the PORT's lane, compiled, THROUGH THE LOCK AGAIN (a second invocation)
    binp = out / "gate.bin"
    with bend_lock() as waited:
        if waited:
            say(name, f"waited {waited}s for the bend lock (compile)")
        c = subprocess.run([str(BEND), str(port), "-o", str(binp)],
                           capture_output=True, text=True, cwd=str(ROOT))
    if c.returncode != 0:
        return refuse(name, f"the native compile failed: {(c.stderr or '').strip()[:200]}")
    bn = subprocess.run([str(binp)], capture_output=True, text=True, cwd=str(ROOT))
    if bn.returncode != 0 or not bn.stdout.strip():
        return refuse(name, "the compiled lane emitted no rows")
    (out / "bn.out").write_text(bn.stdout)

    # ---- the row counts, and the DIFF
    lanes = {t: split_rows((out / f).read_text())
             for t, f in (("py", "py.rows"), ("bd", "bd.out"), ("bn", "bn.out"))}
    for tag, rs in lanes.items():
        if len(rs) != ROWS:
            say(name, f"the {tag} lane has {len(rs)} rows, expected {ROWS}")
            return DEAD if not rs else FAIL
    names = [n for n, _ in lanes["py"]]
    for tag in ("bd", "bn"):
        if [n for n, _ in lanes[tag]] != names:
            say(name, f"the {tag} lane's ROW NAMES differ from the oracle's")
            return FAIL
    for (row, (want_oracle, want_port)) in DIVERGES.items():
        py_row, bd_row = dict(lanes["py"]).get(row), dict(lanes["bd"]).get(row)
        if py_row is not None and py_row == bd_row:
            return refuse(name, f"the declared divergence {row!r} is STALE: the port's row "
                                f"and CPython's row are the same, so it is not a divergence "
                                f"any more -- drop the declaration")
        for tag, want in (("py", want_oracle), ("bd", want_port), ("bn", want_port)):
            got = dict(lanes[tag]).get(row)
            if got != want:
                say(name, f"the {tag} lane's {row} is not {want!r} -- it is {got!r}")
                return FAIL
    skip = set(DIVERGES)
    for tag in ("py", "bd", "bn"):
        kept = [(n, t) for (n, t) in lanes[tag] if n not in skip]
        (out / f"{tag}.cmp").write_text("".join(t for _, t in kept))
    for tag in ("bd", "bn"):
        a = [(n, t) for (n, t) in lanes[tag] if n not in skip]
        b = [(n, t) for (n, t) in lanes["py"] if n not in skip]
        if a != b:
            bad = [(x[0], x[1], y[1]) for x, y in zip(a, b) if x[1] != y[1]]
            say(name, f"DISAGREE ({tag}): {len(bad)} of {len(b)} rows differ; "
                      f"first: {[(n, o.strip()[:70], p.strip()[:70]) for n, o, p in bad[:3]]}")
            return FAIL
    print(f"  {name}: {ROWS} rows, {len(DIVERGES)} declared divergences, "
          f"{ROWS - len(DIVERGES)} compared, THREE LANES BYTE-IDENTICAL against the LIVE "
          f"upstream (tinygrad/renderer/nir.py blob {upstream_blob()})")
    return PASS


if __name__ == "__main__":
    raise SystemExit(main())
