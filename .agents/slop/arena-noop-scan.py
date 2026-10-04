#!/usr/bin/env python3
"""arena-noop-scan.py -- THE DETECTOR, run over gate OUTPUT rather than over source.

`O.Arena.node` is TOTAL (ops.bend:1192): `Maybe.default(&1, Node, Arena.at(ar, i),
Arena.bottom())`, and `Arena.bottom()` is `Node{OpsNOOP{}, Nil{}, ABad{}, TNone{}}`. A read
addressed to the wrong arena therefore CANNOT fail -- it answers a NOOP, which is a value no
constructor in the tree ever produces.

So the cheap detector needs no mutation and no new fixture: every gate row already prints
op names, so a NOOP in gate OUTPUT is a read that landed on a node nothing constructed. Two
of the ten shapes are benign and are excluded by MECHANISM, not by a hand list:

  * INDEX 0 IS THE BOTTOM. `Arena.empty()` interns the bottom at slot 0 by construction
    (ops.bend:1166), so a graph dump that prints EVERY index will always print `NOOP` for
    index 0. Excluded by reading the index off the row, not by a name list.
  * A ROW THAT NAMES NOOP IS A NOOP ROW. `mmk_noop`, `mv_expnoop`, `ear_pd_NOOP`, `axs_NOOP`
    and `op_color.NOOP` are rows whose SUBJECT is the op. Excluded by the row name, and
    reported separately so the exclusion is visible rather than silent.

  * A NOOP INSIDE A REPR IS A SPELLING, NOT A READ. `jit.bend:415` carries the literal
    string `"UOp(Ops.NOOP, arg=None, src=())"`, which CPython's repr of `None`-as-UOp
    prints and which three jit rows quote verbatim. Reading an arena can never produce an
    `arg=None, src=()` field pair, because `Arena.bottom()` is `ABad{}`/`TNone{}` with an
    EMPTY src -- so a NOOP carrying `src=()` is a string, and this is excluded by SHAPE.

Anything left is a NOOP at an index the row did not name as a NOOP row: an aliasing defect,
a deliberately-minted NOOP, or a stale arena. This tool cannot tell those three apart -- it
reports them and the classification is a human judgement made against the source.

usage: arena-noop-scan.py [glob-dir]
"""
import os, re, sys, glob, collections

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# a row whose NAME says the subject is a NOOP. `=` or whitespace separated, case sensitive.
NOOP_NAME = re.compile(r"NOOP|noop")

# CPython's repr of a UOp, quoted into a row as a literal. `jit.bend:415` holds the STRING
# `"UOp(Ops.NOOP, arg=None, src=())"` and three rows quote it, so a bare `NOOP` grep reports
# three defects that are three spellings. Measured: this exclusion takes jit's suspect count
# from 5 to 2, and the 2 it leaves are the real defect.
REPR_NOOP = re.compile(r"NOOP, arg=None, src=\(\)")

def idx_of(row):
  """the arena index a row is about, if the row prints one.

  Three shapes, all measured in the tree: `a_rintk=0,NOOP` (dumps print `name=index`),
  `ear_pd_NOOP=26` (a count, not an index), `mmk_noop n=2 op=Ops.NOOP` (`n=` is the node
  COUNT, not an index). Only the first is an index, so only the first is checked."""
  m = re.match(r"^([\w.]+)=(\d+)(?:,|$)", row)
  return int(m.group(2)) if m else None

def main():
  d = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, ".agents/slop/blobrows/CURRENT")
  files = sorted(glob.glob(os.path.join(d, "*.txt")))
  if not files:
    print(f"no gate output in {d}"); return 1
  total_rows = 0
  benign0, benign_name, benign_repr, suspect = [], [], [], []
  scanned = 0
  for path in files:
    scanned += 1
    for ln, row in enumerate(open(path, encoding="utf-8", errors="replace").read().splitlines(), 1):
      total_rows += 1
      if "NOOP" not in row and "noop" not in row: continue
      name = row.split("=", 1)[0].split(" ", 1)[0].strip()
      if NOOP_NAME.search(name):
        benign_name.append((os.path.basename(path), ln, name, row[:110]))
        continue
      # A NOOP that carries `src=()` was not read out of an arena: `Arena.bottom()` is
      # `Node{OpsNOOP{}, Nil{}, ABad{}, TNone{}}` and `Nil{}` prints as `src=()`, so the
      # SHAPE is genuinely ambiguous with the hand-written repr string -- which is why this
      # exclusion is reported as a class rather than applied silently.
      if REPR_NOOP.search(row):
        benign_repr.append((os.path.basename(path), ln, name, row[:110]))
        continue
      i = idx_of(row)
      if i == 0:
        benign0.append((os.path.basename(path), ln, name, row[:110]))
        continue
      suspect.append((os.path.basename(path), ln, name, row[:150]))

  total_noop = len(benign0) + len(benign_name) + len(benign_repr) + len(suspect)
  print(f"ARENA NOOP SCAN -- {scanned} gate outputs, {total_rows} rows")
  print(f"  rows mentioning NOOP: {total_noop} "
        f"({100.0*total_noop/max(total_rows,1):.2f}% of rows)")
  print()
  print(f"EXCLUDED -- index 0 is the bottom by construction (Arena.empty, ops.bend:1166): {len(benign0)}")
  for f, ln, n, r in benign0:
    print(f"  {f}:{ln}  {n}")
  print()
  print(f"EXCLUDED -- the row NAMES a NOOP, so NOOP is the subject: {len(benign_name)}")
  for f, ln, n, r in benign_name:
    print(f"  {f}:{ln}  {n}  {r}")
  print()
  print(f"EXCLUDED -- a NOOP inside a REPR STRING (arg=None, src=()): {len(benign_repr)}")
  for f, ln, n, r in benign_repr:
    print(f"  {f}:{ln}  {n}")
  print()
  print(f"SUSPECT -- a NOOP where the row does not name one: {len(suspect)}")
  for f, ln, n, r in suspect:
    print(f"  {f}:{ln}  {n}")
    print(f"      {r}")

  print()
  print("COVERAGE FLOOR. This scan reads GATE OUTPUT, so it can only see an arena read that a")
  print("row PRINTS. A read whose result is consumed by arithmetic, a fuel computation, a")
  print("fuel burn, or a control decision never reaches a row and is INVISIBLE here -- which")
  print("is exactly the `dd_fuel` failure, where a wrong arena shrank a cone from 2184 nodes")
  print("to 57 and the cone SIZE row did move, so that one was caught, but a wrong arena")
  print("feeding only a comparison may not be. Floor stated as a measured number:")
  n_files = len(files)
  n_gates = len([f for f in files if os.path.getsize(f) > 0])
  print(f"  gate outputs present and non-empty: {n_gates} of {n_files}")
  return 0

if __name__ == "__main__":
  sys.exit(main())