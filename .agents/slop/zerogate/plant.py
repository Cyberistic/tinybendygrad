#!/usr/bin/env python3
"""THE PLANT THAT MAKES A SWEPT-INPUT GATE LEAVE `REFUSED` -- two states, tokens and exits.

    .venv/bin/python .agents/slop/zerogate/plant.py --rows > .agents/slop/zerogate/plant.rows

WHAT IT IS NOT. It is not a restore. `nl-gate.py:83` and three siblings print, in their own
refusal text, that *"Restoring a swept instrument is not this file's call"* -- and this file does
not make that call. Each gate below refuses because ONE input file is absent, every one of them
recoverable from `371cc64c9^` at a named path with a non-empty blob. So this file:

  1. writes that ONE blob to its OWN declared path,
  2. runs the gate in BOTH states, recording rc and the verdict TOKEN,
  3. deletes the file again, and PROVES the tree is byte-identical afterwards.

Step 3 is the part that makes step 1 legitimate. A plant that leaves residue is not a plant, it is
a second tree, and `AGENTS.md`'s `PAYLOAD_LAST_FIELD` is a plant whose residue outlived it. The
absence of every path is re-checked from disk, not from a boolean this file set earlier.

WHY IT LIVES HERE AND NOT IN THE GATE. The brief permits a `--plant` mode "to gates you are
given", and forbids touching `checks/*.py` logic. All seven of these gates are `checks/*.py`. So
the plant is EXTERNAL: it restores the gate's PRECONDITION for the length of one measurement and
demonstrates that the gate's own comparison code, which has never once run in this state, reaches
both a green and a red. That is a strictly stronger claim than a `--plant` inside the gate would
be: a gate's own plant can only prove the gate agrees with itself about a synthetic tree, while
this proves the gate still works against the tree's REAL published lanes.

THE SHAPE IS `gates/gatekit.py:output_dir_plant()`, WHICH IS THIS TREE'S EXISTING PLANT SHAPE:
three states asserted in one place rather than a second copy per gate, and -- unlike `gatekit`'s
-- THE PROCESS EXIT ITSELF MOVES, because `gatekit --plant` asserts `REFUSED` internally and
returns 0, which `coindependent/REPORT.md:180` names as *"a two-state plant measured in ONE state
at the caller's `$?`"* and as the defect reproduced inside the instrument that measured it.

THE STATE AND WHY IT IS NOT CHEAP. `nl-gate.py:26-35` and `dup-gate.py:12-16` both record, from
MEASUREMENT, that the value comparison on these lanes is a TAUTOLOGICAL ZERO: the two lanes print
the same bytes, so every value agrees by construction. So the green state is the honest one and
the red state MUST be a row-NAME plant (`nl-gate.py --plant-shape`), because a value plant on a
byte-identical pair moves nothing. Driving the wrong axis here would produce a red that proves
only that the reader reads.
"""
import hashlib
import pathlib
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
PY = str(ROOT / ".venv" / "bin" / "python")
PRE = "371cc64c9^"          # the sweep that removed them; named by every gate's own refusal text

# THE SWEPT INPUTS, BY GATE. Each entry is (path-under-ROOT, blob-path-at-PRE). The blob path is
# the gate's OWN claim, verbatim from its refusal message -- not a path found by search, because a
# search would find the file's LAST home rather than the one the gate will look at.
#
# `rn-gate.py:92-93` and `dup-gate.py:73` name the same `eq-census2.py`, so three gates share one
# input and it is restored once.
SWEPT = {
    ".agents/slop/eq/eq-census2.py": ".agents/slop/eq/eq-census2.py",
    ".agents/slop/nl/nl-oracle.py": ".agents/slop/nl/nl-oracle.py",
    ".agents/slop/hermetic/isolate.py": ".agents/slop/hermetic/isolate.py",
}

# THE CAPTURED LANE PAIR, as TRACKED files. Both sides are the tree's own published oracle row
# sets, so the "clean" state is the real lane rather than a synthetic one. `dup-gate.py`'s header
# names `renderer/cstyle.bend` as the pair with five disagreeing hand-transcriptions, which is why
# BOTH sides are needed and why one is not a copy of the other.
# ⚠ MEASURED, AND THE FIRST CHOICE WAS WRONG. `oracles/tinybendygrad_renderer_nir_llvmir.bend.rows`
# was tried first and is the lane `nl-gate.py`'s own docstring discusses -- but that capture is
# PRE-RENAME and still carries 8 `=`-bearing names, so it is RED before any plant and a plant on it
# measures nothing. `gates/cstyle-live.rows` is the TRACKED REPAIRED fixture (`AGENTS.md` names it as
# stage 7's repaired baseline) and reads rc=0 unmodified: 227 rows, byte-identical on both sides.
# A plant whose green lane is already red proves the plant is working by proving nothing.
PORT = "gates/cstyle-live.rows"
ORC = "gates/cstyle-live.rows"
# A REAL row name from that fixture, verified present, not one typed from memory: the shape plant
# is a no-op on a name the lane does not carry, and a no-op plant exits 0 -- the green.
SHAPE = ("tmap CLANG", "tmap CLANG=x")


def blob(ref):
    r = subprocess.run(["git", "cat-file", "-p", f"{ref}"], cwd=ROOT, capture_output=True)
    if r.returncode != 0:
        return None
    return r.stdout


def sha(p):
    return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()[:12] if \
        pathlib.Path(p).is_file() else "ABSENT"


def run(gate, argv):
    p = subprocess.run([PY, gate, *argv], cwd=ROOT, capture_output=True, text=True, timeout=300)
    toks = [t for t in ("AGREE", "BROKEN", "GREEN", "RED", "REFUSED", "PASS", "FAIL", "DEAD",
                        "SKIP", "SELFTEST", "OK", "FAILED")
            if t in p.stdout or t in p.stderr]
    return p.returncode, (" ".join(toks) or "-"), (p.stdout + p.stderr)


def present(paths):
    return {p: (ROOT / p).is_file() for p in paths}


def cells():
    """(gate, argv, label) for each TWO-STATE cell. GREEN is the real lane; RED is a row NAME
    plant, because these lanes are byte-identical and a value plant cannot move them."""
    return [
        ("checks/nl-gate.py", ["--port-stdout", PORT, "--oracle-stdout", ORC],
         "GREEN: the two published lanes, unmodified"),
        ("checks/nl-gate.py", ["--port-stdout", PORT, "--oracle-stdout", ORC,
                               "--plant-shape", *SHAPE],
         "RED: one row NAME gains an `=`, values untouched -- the class nl-gate.py:12-49 is about"),
        ("checks/nl-gate-noguard.py", ["--port-stdout", PORT, "--oracle-stdout", ORC],
         "GREEN: the same lanes, through the guard-less CONTROL"),
        ("checks/dup-gate.py", ["--port", PORT, "--oracle", ORC],
         "GREEN: the same lanes through the duplicate-name gate"),
        ("checks/dup-gate.py", ["--port", PORT, "--oracle", ORC, "--selftest"],
         "RED via its OWN selftest: 4 cells, value/name/collide plants"),
    ]


def main(argv):
    rows = argv == ["--rows"] or "--rows" in argv
    out = []

    # --- STATE 0: at rest, before anything is materialised. This is the REFUSED every one of
    # these gates is pinned at today, and it is recorded so the "after" reading means something.
    for gate, _, label in cells():
        rc, tok, _ = run(gate, [])
        out.append(("at rest (input swept)", gate, "-", rc, tok, label))

    before = present(SWEPT)
    missing = [p for p, v in before.items() if v]
    if missing:
        print("REFUSED: a swept input I was told is absent is PRESENT -- another unit restored it, "
              f"and this plant would overwrite their work: {missing}", file=sys.stderr)
        return 3

    restored = []
    try:
        for rel, at in SWEPT.items():
            data = blob(f"{PRE}:{at}")
            if data is None:
                out.append(("plant", "-", rel, 3, "REFUSED", f"NO BLOB at {PRE}:{at}"))
                continue
            (ROOT / rel).parent.mkdir(parents=True, exist_ok=True)
            (ROOT / rel).write_bytes(data)
            restored.append(rel)
            out.append(("plant", "-", rel, 0, "PLANTED",
                        f"{len(data)}B from {PRE}; the gate's own named path"))
        for gate, ax, label in cells():
            rc, tok, _ = run(gate, ax)
            out.append(("planted", gate, " ".join(ax), rc, tok, label))
    finally:
        for rel in restored:
            (ROOT / rel).unlink(missing_ok=True)

    # --- THE PROOF THAT IT WAS A PLANT AND NOT A RESTORE. Read from disk, not from a flag.
    after = present(SWEPT)
    residue = [p for p, v in after.items() if v]
    for p in SWEPT:
        out.append(("after", "-", p, 0 if not after[p] else 1,
                    "ABSENT" if not after[p] else "RESIDUE", f"sha {before[p]} -> {after[p]}"))

    if rows:
        print("state\tgate\targv\trc\ttoken\tnote")
        for s, g, a, rc, tok, n in out:
            print(f"{s}\t{g}\t{a}\t{rc}\t{tok}\t{n}")
        print(f"\n# RESIDUE AFTER THE PLANT: {len(residue)} path(s) {residue}")
        return 1 if residue else 0
    for s, g, a, rc, tok, n in out:
        print(f"{s:24} {g:30} rc={rc} {tok:22} {n}")
    print(f"\nRESIDUE AFTER THE PLANT: {len(residue)} path(s) {residue}")
    return 1 if residue else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))