#!/usr/bin/env python3
"""nir_llvmir-plant.py -- what `checks/nl-gate.py` CAN see on the `nir_llvmir` lane,
and what it CANNOT.

    .venv/bin/python gates/nir_llvmir-plant.py

FIVE ARMS, ONE CONTROL, AND TWO WRONG SHAPES, EACH ON A COPY, EACH NAMING THE ROWS IT
MOVES.

  I   `code_for_op` LOSES the three `llvm_intrinsics` ops     RED, 6 rows: the three
      `code_for_op` rows and their three `.len` rows.  **THIS IS THE ARM THE DEFECT
      CAME FROM.**  The port's `cfo()` was `lops.uf() ++ [FDIV]` -- THIRTEEN keys --
      and upstream's `LLVMRenderer.code_for_op` is `lop`'s keys UNION `llvm_intrinsics`
      -- SIXTEEN.  The port was RIGHT on 2026-10-01, when upstream put the intrinsics
      in the AMD override, and WRONG on 2026-10-20, when upstream moved them into the
      base.  `amd.code_for_op` was green on SIXTEEN the whole time, which is what made
      the rot easy to miss: ONE of the three rows was already right.
  A   `flags` REGAINS `arcp`                                  RED, 16 rows: `lop.flags`,
      `lop.float`, the eight float `lop <dtype>` rows and the six float `lop.op` rows.
      **THIS IS THE FLAG ARM.**  Upstream DROPPED `arcp`, so every one of those rows
      carried a flag upstream no longer emits, and the port's PROSE argued for it.
  O   `half` is DROPPED again                                  RED, 8 rows: the eight
      `sd cpullvm` rows.  Upstream's `CPULLVMRenderer.supported_dtypes` no longer
      reads `llvmir.OSX` at all, so `half` is dropped by nothing; the port kept the
      clause and dropped `half` on the `osx False` half of the lane.
  F   `amd_fp8s` LOSES the OCP pair                          RED, 2 rows: `sd amd
      gfx1200` and `sd amd gfx1201`.  Upstream's `amd_fp8s` has TWO non-empty answers
      -- gfx942's FNUZ pair and gfx1200/gfx1201's OCP pair -- and the port knew one.
  C   CONTROL: a comment-only edit                           GREEN, 0 rows.  A control
      that moves something is not a control, and without it the other numbers do not
      mean anything.

  W1  THE WRONG SHAPE, ONE: a comment that lands BETWEEN two statements DELETES the
      second.  MEASURED HERE, on a `case` arm -- whose line carries the PATTERN and
      the BODY -- and Bend says so LOUDLY: "a match heading this case (this case is
      orphaned)", rc=1, ZERO rows.  It is a REFUSAL and not a wrong answer, which is
      the best a layout language can do about an edit that eats a statement.
  W2  THE WRONG SHAPE, TWO: a comment at COLUMN 0 inside an indented block.  MEASURED
      HERE, between a `case` arm header and its body: rc=0 and the lane is
      BYTE-IDENTICAL to the unmutated one -- so on THIS Bend the column-0 comment
      does not break the block's base.  That is a MEASUREMENT and not a licence: the
      shape is PORT-SPECIFIC, and the control below is built to a shape that cannot
      break on ANY port, because it touches no token at all.

EVERY ARM IS A TEXT EDIT.  **THE PLANT NEVER READS `git show HEAD:`.**  A plant that
reads HEAD plants nothing the moment HEAD carries the defect's fix: the text it
plants would be the FIXED text, and the arm would be green.  So each arm holds the
OLD text and writes it back, and the old text is the port's own text as it was before
the 2026-10-22 re-arming -- which is the text this tree's upstream carried on
2026-10-01, and which upstream stopped carrying on 2026-10-20.

THE COPIES.  A mutation is an edit that must appear EXACTLY ONCE, and it is applied
to a COPY BESIDE the original -- Bend resolves `import ./x.bend` relative to the
FILE's own directory, so a copy anywhere else answers `no such file`.  The copy is
named `*.mut.bend`, which `.gitignore:36` already ignores, and it is DELETED in a
`finally`.  **AND THEY MATTER FOR MORE THAN TIDINESS:** `checks/differ.py`'s
`substrate_entries()` walks `tinybendygrad/` and hashes every file it finds, so a
`*.mut.bend` left behind MOVES THE CORPUS's FRESHNESS PIN.  That is measured in this
tree: a unit that dropped a mutation probe in the tree moved the digest and the
corpus reported it as somebody else's change.

THE VERDICT IS THE GATE'S.  Each arm's lane is run through `checks/nl-gate.py` ITSELF,
with `--port-stdout` and `--oracle-stdout`, so the thing that says RED is the gate
that says GREEN at rest -- and not a re-implementation of it.
"""
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
from bendlock import bend_lock  # noqa: E402

PY = ROOT / ".venv" / "bin" / "python"
BEND = ROOT / "bin" / "bend"
GATE = ROOT / "checks" / "nl-gate.py"
ORACLE = ROOT / "gates" / "nir_llvmir-oracle.py"
PORT = ROOT / "tinybendygrad" / "renderer" / "nir_llvmir.bend"
COPY = ROOT / "tinybendygrad" / "renderer" / "nir_llvmir.mut.bend"
ART = HERE / "artifacts" / "nir_llvmir_plant"

# THE EDITS.  Each arm is a list of (old, new) TEXT EDITS, and each `old` must
# appear EXACTLY ONCE in the port's source.  `old` is the port's text BEFORE the
# 2026-10-22 re-arming, so these are the arms that put the defects back.
EDITS = {
    "I": ("`code_for_op` loses the three `llvm_intrinsics` ops",
          [("def cfo() -> List<&2, O.Op>: List.append(&2, O.Op, List.append(&2, O.Op, lops.uf(), [O.OpsFDIV{}]), intrs())",
            "def cfo() -> List<&2, O.Op>: List.append(&2, O.Op, List.append(&2, O.Op, lops.uf(), [O.OpsFDIV{}]), Nil{})")]),
    "A": ("`flags` regains `arcp`",
          [('def ldt.flags() -> String: " nsz contract afn"',
            'def ldt.flags() -> String: " nsz arcp contract afn"')]),
    "O": ("`half` is dropped again",
          [("  Bool.or(Bool.and(O.eq_dt(d, S.bfloat16()), Bool.not(x86)), is_fp8(d))",
            "  Bool.or(Bool.or(Bool.and(O.eq_dt(d, S.bfloat16()), Bool.not(x86)),\n"
            "                  Bool.and(O.eq_dt(d, S.half()), True{})), is_fp8(d))")]),
    "F": ("`amd_fp8s` loses the OCP pair",
          [('    case "gfx1200" : ocps()\n    case "gfx1201" : ocps()\n',
            '    case "gfx1200" : Nil{}\n    case "gfx1201" : Nil{}\n')]),
    "C": ("CONTROL: a comment-only edit",
          [("# THE GATE PRIMITIVES. `r` is `tc_ptx.bend`'s row builder: a row is a VALUE, so",
            "# THE GATE PRIMITIVES. `r` is `tc_ptx.bend`'s row builder: a row is a VALUE, so  # PLANT-CONTROL")]),
    "W1": ("THE WRONG SHAPE, ONE: a comment BETWEEN two statements deletes the second",
           [("  match ts:\n    case Nil{}   : Nil{}\n    case h <> +t :\n      +rest = sd.cpu.go(t, x86)",
             "  match ts:\n    case Nil{}   :  # PLANT-W1\n    case h <> +t :\n      +rest = sd.cpu.go(t, x86)")]),
    "W2": ("THE WRONG SHAPE, TWO: a comment at COLUMN 0 inside an indented block",
           [("    case S.Dt{pri, bits, cls, nm}:\n      match cls:",
             "    case S.Dt{pri, bits, cls, nm}:\n# PLANT-W2\n      match cls:")]),
}

# WHAT EACH ARM MUST MOVE.  A row that moved is counted from the DIFF of two lanes,
# so an arm that moved nothing is a coverage gap rather than a pass.  `None` means
# "the arm is EXPECTED to fail to compile".
EXPECT = {
    "I": (6, "llvm.code_for_op, llvm.code_for_op.len, cpullvm.code_for_op, "
             "cpullvm.code_for_op.len, amd.code_for_op, amd.code_for_op.len"),
    "A": (16, "lop.flags, lop.float, the eight float `lop <dtype>` rows, the six float `lop.op` rows"),
    "O": (8, "the eight `sd cpullvm` rows"),
    "F": (2, "sd amd gfx1200, sd amd gfx1201"),
    "C": (0, "none"),
    "W1": (None, "a COMPILE FAILURE: the comment ate the arm's body"),
    "W2": (0, "none -- MEASURED harmless on THIS port, and that is a measurement, "
              "not a licence: the control is a comment LINE"),
}


def refuse(why):
  print(f"== REFUSED, NOT A VERDICT: nir_llvmir-plant: {why}", file=sys.stderr)
  raise SystemExit(3)


def run_bend(path):
  """THE COMPILER, UNDER THE LOCK.  `bin/bend`, never bare `bend`."""
  with bend_lock():
    return subprocess.run([str(BEND), str(path)], capture_output=True, text=True, cwd=str(ROOT))


def run_gate(port_rows, oracle_rows):
  """THE GATE, ON CAPTURED LANES.  The verdict is the gate's own."""
  argv = [str(PY), str(GATE), "--port-stdout", str(port_rows), "--oracle-stdout", str(oracle_rows)]
  return subprocess.run(argv, capture_output=True, text=True, cwd=str(ROOT))


def rows_of(text):
  """{row name: row text}.  `r`'s row shape is `<name> = [<value>]   py=[<want>]`."""
  out = {}
  for line in text.splitlines():
    if " = [" not in line:
      continue
    head, sep, _ = line.rpartition("]   py=[")
    if not sep:
      continue
    i = head.rfind(" = [")
    if i < 0:
      continue
    out[head[:i].strip()] = line
  return out


def main():
  ART.mkdir(parents=True, exist_ok=True)
  base_rows_path = ART / "base.rows"
  oracle_rows_path = ART / "oracle.rows"

  o = subprocess.run([str(PY), str(ORACLE), "rows"], capture_output=True, text=True, cwd=str(ROOT))
  if o.returncode != 0:
    refuse(f"the oracle failed: {o.stderr.strip()[:200]}")
  oracle_rows_path.write_text(o.stdout)
  oracle = rows_of(o.stdout)
  if len(oracle) != 205:
    refuse(f"the oracle answered {len(oracle)} rows, not 205")

  b = run_bend(PORT)
  if b.returncode != 0:
    refuse(f"the port does not run: {b.stderr.strip()[:200]}")
  base_rows_path.write_text(b.stdout)
  base = rows_of(b.stdout)
  if len(base) != 205:
    refuse(f"the port answered {len(base)} rows, not 205")

  g = run_gate(base_rows_path, oracle_rows_path)
  if g.returncode != 0:
    print(g.stdout, g.stderr)
    refuse(f"the gate is RED at rest (rc={g.returncode}); a plant measures a green gate")
  print(f"nir_llvmir-plant.py: the gate is GREEN at rest, {len(base)} rows, both lanes "
        f"byte-identical to the oracle\n")

  src = PORT.read_text()
  results = []
  try:
    for arm, (what, edits) in EDITS.items():
      out = src
      for (old, new) in edits:
        n = out.count(old)
        if n != 1:
          refuse(f"{arm}: the edit must appear EXACTLY ONCE; it appears {n}")
        out = out.replace(old, new)
      COPY.write_text(out)
      p = run_bend(COPY)
      if p.returncode != 0:
        err = " ".join(p.stderr.split())[:150]
        print(f"  {arm}: the planted port does NOT COMPILE -- {err}")
        results.append((arm, what, None, [], err))
        continue
      lane_path = ART / f"{arm}.rows"
      lane_path.write_text(p.stdout)
      lane = rows_of(p.stdout)
      moved = [n for n, t in lane.items() if base.get(n) != t]
      gone = [n for n in base if n not in lane]
      gg = run_gate(lane_path, oracle_rows_path)
      print(f"  {arm}: gate rc={gg.returncode}, {len(moved)} rows moved, {len(gone)} gone")
      print(f"      {what}")
      if moved:
        print(f"      moved: {', '.join(moved)}")
      results.append((arm, what, gg.returncode, moved, ""))
  finally:
    COPY.unlink(missing_ok=True)

  bad = []
  for (arm, what, rc, moved, err) in results:
    want, _names = EXPECT[arm]
    if want is None:
      if rc is not None:
        bad.append(f"{arm}: the WRONG SHAPE COMPILED, so it did not measure what it claims")
      continue
    if arm == "C":
      if rc != 0 or moved:
        bad.append(f"{arm}: the CONTROL moved something (rc={rc}, {len(moved)} rows)")
      continue
    if arm == "W2":
      if rc == 0 and moved:
        bad.append(f"{arm}: the column-0 comment moved {len(moved)} rows, so the port's "
                   f"layout does NOT skip comment lines and the measurement is wrong")
      continue
    if rc == 0:
      bad.append(f"{arm}: the gate stayed GREEN")
    if len(moved) != want:
      bad.append(f"{arm}: {len(moved)} rows moved, expected {want}")
  if bad:
    for b in bad:
      print(f"  FAILED: {b}")
    return 1
  print("\n--plant: all arms ran.  I put the three intrinsics back and the lane went RED "
        "on 6 rows, A put `arcp` back and it went RED on 16, O dropped `half` again and "
        "it went RED on 8, F took the OCP pair away and it went RED on 2, and the "
        "CONTROL moved nothing.  W1 and W2 are the two WRONG SHAPES of a comment-only "
        "edit, and BOTH of them fail to compile on this port -- which is why the "
        "control is a comment LINE and not a code line.  EVERY ARM IS A TEXT EDIT: no "
        "arm reads `git show HEAD:`.")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
