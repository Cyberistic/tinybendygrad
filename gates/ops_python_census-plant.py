#!/usr/bin/env python3
"""ops_python_census-plant.py -- THE WAYS A CORE COUNT CAN BE WRONG, EACH PLANTED.

    .venv/bin/python gates/ops_python_census-plant.py             # the arms; exit 0 iff all held
    .venv/bin/python gates/ops_python_census-plant.py --falsify   # ARM 1's expectation INVERTED

WHAT THIS IS FOR. `pyr_gfx1201_ncores` -- a gfx1201 device's tensor-core COUNT -- was
a PORT BUG, and the port said 4 where CPython said 7. The cause was not a mistake in
the arithmetic: `ops_python.bend`'s `cores_of` HOLDS the LENGTHS of `tc.py`'s tables,
and `tinygrad/` was re-vendored to upstream `002630241` (2026-10-16), which grew
`tc.amd_rdna4` from FOUR tensor cores to SEVEN. A HELD LENGTH IS A PIN ON A FILE THAT
CAN MOVE, and the port carried the old one.

So the count can be wrong in more ways than the one that happened, and this file
PLANTS each of them and MEASURES that an instrument says so. The instrument is the
gate's own, and there are TWO of them, because they fail differently:

  * THE ROW DIFF -- the port's own fixture lane against CPython's oracle, byte for
    byte. This is what went red on the real defect, and it is the slow one.
  * `cores_axis_hold()` -- the port's THREE LADDERS re-derived against `tc.py` ITSELF,
    at the source, with NO `bend` run at all. It names the table and the two numbers.

THE ARMS. Each one is a mutation of a SCRATCH copy of the port (or, for ARM 6, of a
scratch copy of `tc.py`), and each names the way it could be wrong:

  0 CONTROL     nothing planted. The lanes agree and the axis check is OK.
  1 INHERITED   the port's bytes at HEAD -- the defect as it was inherited. The count
                is the OLD TABLE'S LENGTH, which is right for the table tc.py used to
                have and wrong for the table it has.
  2 ONE DEVICE  gfx1201 is sent to rdna3, the table gfx1100 REALLY selects. The count
                is another device's count: RIGHT for the device it was measured on,
                WRONG for this one -- and gfx1200, which shares the table, is still
                right, so a per-DEVICE constant is what this arm is.
  3 WRONG TABLE the rdna4 COUNT is cdna4's length. A count read from the wrong table.
  4 CU COUNT    the rdna4 COUNT is 40 -- gfx1201's COMPUTE UNITS. A CU count mistaken
                for a count of TensorCores. Nothing in `tc.py` is a CU.
  5 CARD        gfx1200 is sent to rdna3 while gfx1201 stays on rdna4, so the count
                DEPENDS ON THE CARD rather than on the table. **AND THE ROW DIFF
                SEES ONLY `pyr_gfx1200_tid`** -- there is no `pyr_gfx1200_ncores` row,
                because the two devices share a table and one row was enough -- so the
                TID axis is the instrument that earns its keep here, and the COUNT
                axis alone would have said nothing.
  6 THE ORACLE  `tc.py`'s `amd_rdna4` grows by one entry and the PORT DOES NOT. This
                is the re-vendor, reproduced: the oracle moved and the port did not.

**THE PLANT NEVER WRITES THE TREE.** Everything happens in a `tempfile.mkdtemp()`
scratch: a copy of `tinybendygrad/` (so a mutant's RELATIVE imports resolve -- bend
resolves `import ../helpers.bend` against the importing file's own path), a copy of
`tinygrad/`, and a copy of the oracle at `scratch/gates/` (so the oracle's own
`ROOT` is the scratch and `import tinygrad` resolves THERE -- measured: the venv's
editable install APPENDS its finder to `sys.meta_path`, so `sys.path[0]` still wins).

**THE SUBSTRATE IS HEAD's `tinybendygrad/`, NOT THE WORKING TREE's.** Another unit was
mid-edit on `tinybendygrad/uop/ops.bend` while this was written, and its bytes do not
compile -- so a scratch built from the working tree would make EVERY arm DEAD for a
reason that has nothing to do with the count. The substrate is therefore HEAD's, and
the file under test is the port, copied in per arm.

**ONE `bend` AT A TIME.** Every `bend` invocation holds the shared lock for its whole
run and releases it immediately after, because several units share this machine. The
wait is REPORTED, not hidden.

`--falsify` INVERTS ARM 1's expectation and MUST exit 1. A plant whose expectations
cannot be violated proves nothing.
"""
from __future__ import annotations

import contextlib
import importlib.util
import io
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
GATE = HERE / "ops_python_census-gate.py"
ORACLE = HERE / "ops_python_census-oracle.py"
PORT_REL = "tinybendygrad/runtime/ops_python.bend"
TC_REL = "tinygrad/renderer/tc.py"
BEND = ROOT / "bin" / "bend"
PY = ROOT / ".venv" / "bin" / "python"
LOCK = Path("/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/bend.lock")


# --------------------------------------------------------------------------
# THE BEND LOCK. One compiler at a time, and the wait is a number.
# --------------------------------------------------------------------------
@contextlib.contextmanager
def bend_lock():
    """The shared `bend` lock, held for the WHOLE invocation and released after."""
    waited = 0
    while True:
        try:
            LOCK.mkdir()
            break
        except FileExistsError:
            time.sleep(2)
            waited += 2
    try:
        yield waited
    finally:
        try:
            LOCK.rmdir()
        except OSError:
            pass


def run_bend(path: Path) -> tuple[int, list[str], str]:
    """`(rc, rows, stderr)` of one `bend` run under the lock."""
    with bend_lock() as waited:
        r = subprocess.run([str(BEND), str(path)], capture_output=True, text=True,
                           cwd=str(ROOT))
    rows = [ln for ln in r.stdout.splitlines() if ln.strip()]
    return r.returncode, rows, f"{r.stderr.strip()[:160]} (waited {waited}s)"


# --------------------------------------------------------------------------
# THE SCRATCH. A mirror of the paths the port and the oracle resolve against.
# --------------------------------------------------------------------------
def build_scratch() -> Path:
    """A scratch tree: HEAD's `tinybendygrad/`, the real `tinygrad/`, the oracle.

    `git archive` rather than a copy of the working tree, so the substrate is a
    MEASURED thing -- HEAD's bytes -- and not whatever another unit is writing."""
    tmp = Path(tempfile.mkdtemp(prefix="opspythonplant."))
    a = subprocess.run(["git", "archive", "HEAD", "tinybendygrad"], cwd=str(ROOT),
                       capture_output=True)
    if a.returncode != 0:
        raise SystemExit(f"REFUSED: git archive HEAD tinybendygrad failed: {a.stderr[:200]!r}")
    import tarfile
    with tarfile.open(fileobj=io.BytesIO(a.stdout)) as tf:
        tf.extractall(tmp)
    shutil.copytree(ROOT / "tinygrad", tmp / "tinygrad", symlinks=True)
    (tmp / "gates").mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ORACLE, tmp / "gates" / ORACLE.name)
    return tmp


# --------------------------------------------------------------------------
# THE TWO INSTRUMENTS.
# --------------------------------------------------------------------------
def lane_diff(py_rows: list[str], bd_rows: list[str]) -> tuple[str, list[str]]:
    """`(verdict, the rows that disagree)` -- THE ROW DIFF.

    Row NAMES, not line numbers: a diff of two lanes that misalign would otherwise
    report a disagreement about a different row than the one that moved."""
    if len(py_rows) != len(bd_rows):
        return "DISAGREE", [f"<row count {len(py_rows)} vs {len(bd_rows)}>"]
    names = []
    for a, b in zip(py_rows, bd_rows):
        if a != b:
            names.append(a.split("=", 1)[0])
    return ("IDENTICAL" if not names else "DISAGREE"), names


def axis_check(port: Path, root: Path) -> tuple[str, str]:
    """`(verdict, the message)` of `cores_axis_hold()` against a scratch port and a
    scratch `tinygrad/`. NO `bend` RUNS HERE -- which is the point of the check.

    **IN A FRESH PROCESS, and that is not a style choice.** The check reads `tc.py`
    and then IMPORTS it, and an imported module is cached in `sys.modules` for the
    life of the interpreter: an in-process check would have measured ARM 6's OLD
    table, because ARM 1's check had already imported it. A plant that measures a
    cached value is a plant that scores green for the wrong reason."""
    runner = root / "gates" / "_plant_axis.py"
    runner.write_text(
        "import contextlib, importlib.util, io, sys\n"
        "from pathlib import Path\n"
        f"spec = importlib.util.spec_from_file_location('g', {str(GATE)!r})\n"
        "m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)\n"
        f"m.PORT = Path({str(port)!r})\n"
        f"m.ROOT = Path({str(root)!r})\n"
        "buf = io.StringIO()\n"
        "with contextlib.redirect_stderr(buf): ok = m.cores_axis_hold()\n"
        "print('VERDICT:' + ('OK' if ok else 'FAIL'))\n"
        "print(buf.getvalue().strip())\n")
    r = subprocess.run([str(PY), str(runner)], capture_output=True, text=True, cwd=str(root))
    lines = r.stdout.splitlines()
    verdict = "?"
    for ln in lines:
        if ln.startswith("VERDICT:"):
            verdict = ln.split(":", 1)[1].strip()
    return verdict, "\n".join(ln for ln in lines if not ln.startswith("VERDICT:")).strip()


# --------------------------------------------------------------------------
# THE ARMS. Each is (label, port text, expected lane verdict, expected disagreeing
# rows, expected axis verdict).
# --------------------------------------------------------------------------
def mutations(port_text: str) -> dict[str, str]:
    """The MUTATED port texts, by label. Every one is a TEXT EDIT on the port, so the
    mutation is a change a port author could have made by accident."""
    out = {}
    # ARM 2: gfx1201 alone is sent to rdna3 -- the table gfx1100 really selects. The
    # `Bool.or` of gfx1200 and gfx1201 is SPLIT, so the chain gains a `Bool.pick` and
    # needs one more closing paren: a mutation that does not compile is a DEAD arm,
    # and a dead arm that scores green is worse than no arm.
    out["2 ONE DEVICE"] = port_text.replace(
        '      Bool.pick(U32, Bool.or(String.eq(arch, "gfx1200"), String.eq(arch, "gfx1201")),\n'
        '        CORES_AMD_RDNA4(), CORES_AMD_RDNA3())))',
        '      Bool.pick(U32, String.eq(arch, "gfx1200"), CORES_AMD_RDNA4(),\n'
        '        Bool.pick(U32, String.eq(arch, "gfx1201"), CORES_AMD_RDNA3(), CORES_AMD_RDNA3()))))')
    # ARM 5: gfx1200 alone is sent to rdna3, so the count depends on the CARD.
    out["5 CARD"] = port_text.replace(
        '      Bool.pick(U32, Bool.or(String.eq(arch, "gfx1200"), String.eq(arch, "gfx1201")),\n'
        '        CORES_AMD_RDNA4(), CORES_AMD_RDNA3())))',
        '      Bool.pick(U32, String.eq(arch, "gfx1200"), CORES_AMD_RDNA3(),\n'
        '        Bool.pick(U32, String.eq(arch, "gfx1201"), CORES_AMD_RDNA4(), CORES_AMD_RDNA3()))))')
    # ARM 3: the rdna4 COUNT is cdna4's length -- a count read from the wrong table.
    out["3 WRONG TABLE"] = port_text.replace(
        "U32.is_eq(tid, CORES_AMD_RDNA4()), 7,", "U32.is_eq(tid, CORES_AMD_RDNA4()), 8,")
    # ARM 4: the rdna4 COUNT is 40 -- gfx1201's COMPUTE UNITS.
    out["4 CU COUNT"] = port_text.replace(
        "U32.is_eq(tid, CORES_AMD_RDNA4()), 7,", "U32.is_eq(tid, CORES_AMD_RDNA4()), 40,")
    return out


def row(ok: bool, label: str) -> bool:
    print(f"  {'OK  ' if ok else 'FAIL'} {label}")
    return ok


def main() -> int:
    falsify = "--falsify" in sys.argv[1:]
    results: list[bool] = []
    scratch = build_scratch()
    try:
        port = scratch / PORT_REL
        live = (ROOT / PORT_REL).read_text()
        muts = mutations(live)
        for label, text in muts.items():
            if text == live:
                print(f"  FAIL {label}: THE PLANT DID NOT PLANT -- the text it edits is "
                      f"not in the port any more", file=sys.stderr)
                results.append(False)
        head_port = subprocess.run(["git", "show", f"HEAD:{PORT_REL}"], cwd=str(ROOT),
                                   capture_output=True, text=True).stdout
        muts = {"1 INHERITED": head_port, **muts}
        # ARM 6: the ORACLE moves. `tc.amd_rdna4` grows by one entry, the port does not.
        tc_scratch = scratch / TC_REL
        tc_live = tc_scratch.read_text()
        grew = tc_live.replace(
            "  for di,do in [(dtypes.half,dtypes.float),(dtypes.half,dtypes.half),"
            "(dtypes.bfloat16,dtypes.float),(dtypes.bfloat16,dtypes.bfloat16),\n"
            "                (dtypes.fp8e4m3,dtypes.float),(dtypes.fp8e5m2,dtypes.float),"
            "(dtypes.int8,dtypes.int32)]]",
            "  for di,do in [(dtypes.half,dtypes.float),(dtypes.half,dtypes.half),"
            "(dtypes.bfloat16,dtypes.float),(dtypes.bfloat16,dtypes.bfloat16),\n"
            "                (dtypes.fp8e4m3,dtypes.float),(dtypes.fp8e5m2,dtypes.float),"
            "(dtypes.int8,dtypes.int32),(dtypes.float32,dtypes.float32)]]")
        if grew == tc_live:
            print("  FAIL 6 THE ORACLE: the plant did not plant -- tc.py's amd_rdna4 is "
                  "not the list the plant edits", file=sys.stderr)
            results.append(False)

        # THE ARMS, in order. `expect_rows` is the SET of row names that must
        # disagree -- the plant asserts the NAME, so a lane that misaligned cannot
        # pass by disagreeing about a different row.
        arms = [
            ("0 CONTROL", live, "IDENTICAL", set(), "OK"),
            ("1 INHERITED", muts["1 INHERITED"], "DISAGREE", {"pyr_gfx1201_ncores"}, "FAIL"),
            ("2 ONE DEVICE", muts["2 ONE DEVICE"], "DISAGREE",
             {"pyr_gfx1201_ncores", "pyr_gfx1201_tid"}, "FAIL"),
            ("3 WRONG TABLE", muts["3 WRONG TABLE"], "DISAGREE", {"pyr_gfx1201_ncores"}, "FAIL"),
            ("4 CU COUNT", muts["4 CU COUNT"], "DISAGREE", {"pyr_gfx1201_ncores"}, "FAIL"),
            ("5 CARD", muts["5 CARD"], "DISAGREE", {"pyr_gfx1200_tid"}, "FAIL"),
        ]
        for label, text, want_lane, want_rows, want_axis in arms:
            port.write_text(text)
            tc_scratch.write_text(tc_live)
            rc, bd_rows, said = run_bend(port)
            if rc != 0 or not bd_rows:
                print(f"  FAIL {label}: the port lane produced {len(bd_rows)} rows "
                      f"(rc={rc}) -- {said}", file=sys.stderr)
                results.append(False)
                continue
            o = subprocess.run([str(PY), str(scratch / "gates" / ORACLE.name)],
                               capture_output=True, text=True, cwd=str(scratch))
            py_rows = [ln for ln in o.stdout.splitlines() if ln.strip()]
            if o.returncode != 0 or not py_rows:
                print(f"  FAIL {label}: the oracle lane produced {len(py_rows)} rows "
                      f"(rc={o.returncode}) -- {o.stderr.strip()[:160]}", file=sys.stderr)
                results.append(False)
                continue
            lane, names = lane_diff(py_rows, bd_rows)
            axis, axis_msg = axis_check(port, scratch)
            if falsify and label == "1 INHERITED":
                want_lane, want_rows, want_axis = "IDENTICAL", set(), "OK"
            ok = lane == want_lane and set(names) == want_rows and axis == want_axis
            detail = (f"lane={lane} rows={sorted(names)} axis={axis}"
                      + (f" [{axis_msg[:110]}]" if axis_msg else ""))
            results.append(row(ok, f"{label:<14} want lane={want_lane} rows={sorted(want_rows)}"
                                     f" axis={want_axis}  --  {detail}"))

        # ARM 6: the ORACLE moves and the port does not.
        port.write_text(live)
        tc_scratch.write_text(grew)
        rc, bd_rows, said = run_bend(port)
        o = subprocess.run([str(PY), str(scratch / "gates" / ORACLE.name)],
                           capture_output=True, text=True, cwd=str(scratch))
        py_rows = [ln for ln in o.stdout.splitlines() if ln.strip()]
        if rc != 0 or not py_rows or not bd_rows:
            print(f"  FAIL 6 THE ORACLE: a lane produced nothing (port {len(bd_rows)} rows "
                  f"rc={rc}, oracle {len(py_rows)} rows rc={o.returncode}) -- {said}",
                  file=sys.stderr)
            results.append(False)
        else:
            lane, names = lane_diff(py_rows, bd_rows)
            axis, axis_msg = axis_check(port, scratch)
            want_lane, want_rows, want_axis = "DISAGREE", {"pyr_gfx1201_ncores"}, "FAIL"
            if falsify:
                want_lane, want_rows, want_axis = "IDENTICAL", set(), "OK"
            ok = lane == want_lane and set(names) == want_rows and axis == want_axis
            detail = f"lane={lane} rows={sorted(names)} axis={axis}"
            results.append(row(ok, f"{'6 THE ORACLE':<14} want lane={want_lane} "
                                     f"rows={sorted(want_rows)} axis={want_axis}  --  {detail}"))

        # THE CONTROLS AT THE END.
        tc_scratch.write_text(tc_live)
        port.write_text(live)
        rc, bd_rows, said = run_bend(port)
        o = subprocess.run([str(PY), str(scratch / "gates" / ORACLE.name)],
                           capture_output=True, text=True, cwd=str(scratch))
        py_rows = [ln for ln in o.stdout.splitlines() if ln.strip()]
        lane, names = lane_diff(py_rows, bd_rows)
        axis, _ = axis_check(port, scratch)
        results.append(row(lane == "IDENTICAL" and axis == "OK",
                           "CONTROL the unplanted tree is clean and the axis check is OK"))
        results.append(row((ROOT / PORT_REL).read_text() == live
                           and (ROOT / TC_REL).read_text() == tc_live,
                           "CONTROL the REAL tree was never written"))
    finally:
        shutil.rmtree(scratch, ignore_errors=True)
    print(f"--- {sum(results)} of {len(results)} arm(s) behaved as required"
          + ("   [FALSIFY: ARM 1's expectation was inverted, so the failures below are required]"
             if falsify else ""))
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
