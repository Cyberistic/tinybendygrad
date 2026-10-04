#!/usr/bin/env python3
"""nv-iowr-mutate.py -- DO THE ROWS THIS UNIT CONVERTED ACTUALLY MOVE?

WHAT THIS SETTLES. Converting a row from a literal to a call buys PROVENANCE. It does
not automatically buy SENSITIVITY: `qmd.ver.of`'s `>=` -> `>` moved `nv_qmd_ver_bwa`
5->3 and did not move `nv_qmd_ver_ada` or `bwb`, so a converted row that no mutation
touches is provenance and nothing more. This harness answers the question for the
rows `.agents/slop/nv-oracle.py`'s `nv_iowr_*` / `nv_hdr_*` block was converted to, by
mutating the PORT and diffing WHOLE `name=value` LINES.

TWO RULES FROM `agent-core.md` ARE LOAD-BEARING HERE AND ARE ENFORCED BELOW.

  * THE DIFF IS OVER `name=value` LINES, NOT ROW NAMES. A name-comparing harness
    reported 0 for all 30 mutations in one unit and 0 for all 68 in another.
  * `ZERO ROWS EMITTED IS NOT A PASS.` bend stack-overflows roughly 1 run in 20, so a
    mutation that emits nothing is reported INCONCLUSIVE and is counted as neither a
    move nor a non-move. It is never silently folded into the "did not move" column.

`rebase-gate.py`'s `rows()` is IMPORTED, not reimplemented: row names in this project
contain SPACES and splitting them a second way is how a harness ends up comparing
something other than what the gate compares.

THE SCRATCH TREE IS THE WHOLE `tinybendygrad/` DIRECTORY, because a $TMPDIR copy of a
single .bend cannot resolve a relative import -- that produced 22 phantom blind spots
in one unit -- and its port is asserted byte-identical to the live one before and
after, so a run that silently picked up a concurrent agent's edit is caught.

    .venv/bin/python .agents/slop/nv-iowr-mutate.py
    .venv/bin/python .agents/slop/nv-iowr-mutate.py --keep
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import pathlib
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[2]
SLOP = ROOT / ".agents" / "slop"
BEND_MAIN = ROOT / "references" / "bend" / "bend2" / "main.ts"
PORT_REL = "runtime/ops_nv.bend"
PORT = ROOT / "tinybendygrad" / PORT_REL
ORACLE = SLOP / "nv-oracle.py"

# The rows this unit converted. Reported SEPARATELY from the oracle's other rows
# because a converted row and an untouched row are not the same claim.
CONVERTED = (
    [f"nv_iowr_{a}_{b}" for a, b in ((0, 0), (4, 1), (64, 44), (40, 43), (96, 65),
                                    (1280, 2), (8191, 136), (8192, 1), (8192, 255))]
    + ["nv_iowr_explicit_kept", "nv_iowr_explicit_0", "nv_iowr_size_is_same"]
    + [f"nv_iowr_msg_{r}" for r in (0, 5, 4096)]
    + ["nv_hdr_typ2", "nv_hdr_subc4", "nv_hdr_nvals5", "nv_hdr_all"]
    + ["nv_pc_grow_0", "nv_pc_grow_1", "nv_pc_grow_3", "nv_pc_grow_repeat",
       "nv_pc_grow_repeat_k1", "nv_pc_miss_3", "nv_pc_id_0", "nv_err_unknown"]
)


def _load_gate():
    """`rebase-gate.py`'s own `rows()`. Its top level is argparse-driven, so the
    module is loaded by path and only the FUNCTION is taken. Writing a second reader
    is the mistake `rows()`'s own docstring records at length."""
    spec = importlib.util.spec_from_file_location("_rebase_gate_rows", SLOP / "rebase-gate.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.rows


ROWS = _load_gate()


def digest(p: pathlib.Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()[:16]


def run_bend(port: pathlib.Path) -> tuple[dict, int, str]:
    """(rows, returncode, stderr-tail).

    `bun <ABS main.ts> <ABS scratch port>` with the CWD at the scratch root. ABSOLUTE
    on main.ts because a relative path resolves against the CWD, which is not the tree;
    the port is ABSOLUTE because it lives in the scratch copy. The scratch copy is the
    WHOLE `tinybendygrad/` directory precisely so the port's own relative imports
    resolve -- a $TMPDIR copy of one .bend cannot, and that produced 22 phantom blind
    spots in one unit."""
    r = subprocess.run(["bun", str(BEND_MAIN), str(port)],
                       cwd=port.parents[2], capture_output=True, text=True)
    return ROWS(r.stdout), r.returncode, r.stderr[-300:]


# (id, what it breaks in the PORT, exact old, exact new)
MUTATIONS: list[tuple[str, str, str, str]] = [
    ("H1", "the header's TYPE field moves 28 -> 27 bits",
     "U32.or(U32.or(U32.shln(typ, 28n), U32.shln(nvals, 16n)),",
     "U32.or(U32.or(U32.shln(typ, 27n), U32.shln(nvals, 16n)),"),
    ("H2", "the header's SUBC field moves 13 -> 12 bits",
     "U32.or(U32.shln(subc, 13n), U32.shrn(mthd, 2n)))",
     "U32.or(U32.shln(subc, 12n), U32.shrn(mthd, 2n)))"),
    ("H3", "the header's NVALS field moves 16 -> 15 bits",
     "U32.shln(typ, 28n), U32.shln(nvals, 16n)),",
     "U32.shln(typ, 28n), U32.shln(nvals, 15n)),"),
    ("H4", "the header's MTHD field divides by 4 instead of 2",
     "U32.or(U32.shln(subc, 13n), U32.shrn(mthd, 2n)))",
     "U32.or(U32.shln(subc, 13n), U32.shrn(mthd, 4n)))"),
    ("I1", "the ioctl SIZE mask 0x1FFF -> 0x3FFF, so the 8 KiB truncation dies",
     "def IOWR_SIZE_MASK() -> U32: 8191", "def IOWR_SIZE_MASK() -> U32: 16383"),
    ("I2", "the ioctl NR mask 0xFF -> 0x7F",
     "def IOWR_NR_MASK() -> U32: 255", "def IOWR_NR_MASK() -> U32: 127"),
    ("I3", "the ioctl read bit 3 -> 1",
     "def IOWR_READ() -> U32: 3", "def IOWR_READ() -> U32: 1"),
    ("I4", "`cmd or (...)` becomes `cmd and (...)`: the explicit arm is lost",
     "Bool.pick(U32, U32.is_zero(explicit), iowr.cmd(nbytes, nr), explicit)",
     "Bool.pick(U32, U32.is_eq(explicit, 1), iowr.cmd(nbytes, nr), explicit)"),
    ("I5", "the refusal's message text",
     'String.concat(["ioctl returned ", U32.show(ret)])',
     'String.concat(["ioctl returned code ", U32.show(ret)])'),
    # ---- the mutations below exist so that "DID NOT MOVE" is not an artefact of
    # ---- which targets I happened to pick. A row listed as insensitive when no
    # ---- mutation ever touched its own subject is a statement about my choices.
    ("P1", "the program cache's key COUNT stops tracking insertions",
     "  PC.at(p, U32.add(PC.n(p), 1), List.append(&2, PKey, PC.ks(p), [k]),",
     "  PC.at(p, PC.n(p), List.append(&2, PKey, PC.ks(p), [k]),"),
    ("P2", "a MISS no longer advances the id counter",
     "PC.at(p, PC.n(p), PC.ks(p), PC.miss(p), U32.add(PC.hit(p), 1), PC.ord(p), PC.next(p))",
     "PC.at(p, PC.n(p), PC.ks(p), PC.miss(p), U32.add(PC.hit(p), 1), PC.ord(p), PC.miss(p))"),
    ("E1", "the unknown-status default text",
     'def iface.unknown() -> String: "Unknown error"',
     'def iface.unknown() -> String: "Unrecognised error"'),
    ("E2", "`cmd or (...)` -> the explicit word is used UNCONDITIONALLY (always 201)",
     "Bool.pick(U32, U32.is_zero(explicit), iowr.cmd(nbytes, nr), explicit)",
     "Bool.pick(U32, Bool.True{}, iowr.cmd(nbytes, nr), explicit)"),
]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--keep", action="store_true")
    args = ap.parse_args()

    print("=" * 96)
    print("nv-oracle.py -- DO THE CONVERTED ROWS MOVE?  (port mutated, whole name=value lines diffed)")
    print("=" * 96)

    work = pathlib.Path(tempfile.mkdtemp(prefix="nviowr-"))
    shutil.copytree(ROOT / "tinybendygrad", work / "tinybendygrad")
    scratch = work / "tinybendygrad" / PORT_REL
    live = digest(PORT)
    assert digest(scratch) == live, "scratch copy is not the live port"
    print(f"  live port sha256[:16]  : {live}  tinybendygrad/runtime/ops_nv.bend")
    print(f"  scratch port sha256[:16]: {digest(scratch)}  (asserted equal)")

    pristine = scratch.read_text()

    # ---- baseline, with the same 2-attempt rule the gate uses -----------------
    base_rows, tries = {}, 0
    for attempt in (1, 2):
        base_rows, rc, err = run_bend(scratch)
        tries = attempt
        if base_rows:
            break
        print(f"  baseline attempt {attempt}: {len(base_rows)} rows -- INCONCLUSIVE, re-running")
        time.sleep(20)
    if not base_rows:
        print(f"\n  BASELINE PRODUCED NO ROWS after {tries} attempts. NOT A RESULT. Stopping: "
              f"bend stack-overflows ~1 run in 20 and 0 rows is indistinguishable from "
              f"a wedged process.")
        shutil.rmtree(work, ignore_errors=True)
        return 2
    print(f"  baseline rows: {len(base_rows)}  rc={rc}  (took {tries} attempt(s))")

    oracle = subprocess.run([sys.executable, str(ORACLE)], cwd=ROOT, capture_output=True, text=True)
    orows = ROWS(oracle.stdout)
    print(f"  ORACLE rows   : {len(orows)}  rc={oracle.returncode}")
    if not orows:
        print("  ORACLE PRODUCED NO ROWS. That is a FAILED ORACLE, not a disagreement. Stopping.")
        shutil.rmtree(work, ignore_errors=True)
        return 2

    shared = set(base_rows) & set(orows)
    pre_dis = {k for k in shared if base_rows[k] != orows[k]}
    print(f"  shared row names: {len(shared)}   pre-existing disagreements: {len(pre_dis)}")
    if pre_dis:
        print(f"    {sorted(pre_dis)}")

    results = {}
    for mid, what, old, new in MUTATIONS:
        if pristine.count(old) != 1:
            print(f"\n{mid}  DOES NOT APPLY -- `old` occurs {pristine.count(old)} times, expected 1")
            print(f"      {what}")
            continue
        scratch.write_text(pristine.replace(old, new))
        rows, rc, err = {}, 0, ""
        for attempt in (1, 2):
            rows, rc, err = run_bend(scratch)
            if rows:
                break
            time.sleep(20)
        if not rows:
            print(f"\n{mid}  INCONCLUSIVE -- the mutated port emitted 0 rows after 2 attempts")
            print(f"      rc={rc} err={' '.join(err.split())[:120]}")
            results[mid] = ("inconclusive", set())
            continue
        moved = {k for k in set(rows) | set(base_rows)
                 if base_rows.get(k) != rows.get(k)}
        conv_moved = moved & set(CONVERTED)
        results[mid] = ("ran", moved)
        print(f"\n{mid}  {'MOVED %d' % len(moved) if moved else 'MOVED 0'}   converted rows moved: "
              f"{len(conv_moved)}/{len(CONVERTED)}   {what}")
        for k in sorted(moved)[:8]:
            print(f"        {k}: {base_rows.get(k)!r} -> {rows.get(k)!r}")
        if len(moved) > 8:
            print(f"        ... and {len(moved) - 8} more")

    scratch.write_text(pristine)
    assert digest(scratch) == live, "scratch tree was not restored"
    print(f"\n  scratch tree restored; live tree sha256 unchanged: {digest(ROOT / 'tinybendygrad' / PORT_REL)}")

    ran = {m: v for m, v in results.items() if v[0] == "ran"}
    print("\n" + "=" * 96)
    print("PER-ROW: WHICH OF THE CONVERTED ROWS MOVED, AND WHICH NEVER DID")
    print("=" * 96)
    never, ever = [], []
    for name in CONVERTED:
        hits = sorted(m for m, v in ran.items() if name in v[1])
        (ever if hits else never).append((name, hits))
    print(f"\n  MOVED by at least one mutation -- {len(ever)} of {len(CONVERTED)}:")
    for name, hits in ever:
        print(f"    {name:26s} {','.join(hits)}")
    print(f"\n  DID NOT MOVE under ANY of the {len(ran)} mutations -- {len(never)} of {len(CONVERTED)}:")
    for name, _ in never:
        print(f"    {name}")
    print("\n  The second list is provenance, NOT sensitivity. A row listed there gained a")
    print("  real upstream call and still cannot fail on this tree.")

    incon = sorted(m for m, v in results.items() if v[0] == "inconclusive")
    print(f"\n  INCONCLUSIVE (0 rows emitted, NOT counted either way): {incon or 'none'}")
    zero = sorted(m for m, v in ran.items() if not v[1])
    print(f"  mutations that moved NOTHING at all: {zero or 'none'}")

    if args.keep:
        print(f"\n  scratch kept at {work}")
    else:
        shutil.rmtree(work, ignore_errors=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())