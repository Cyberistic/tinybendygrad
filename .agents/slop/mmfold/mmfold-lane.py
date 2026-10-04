#!/usr/bin/env python3
"""mmfold-lane.py -- THE LANE THAT GATES `fold.bend`'s 93 ONE-SPACE ROWS.

    .venv/bin/python .agents/slop/mmfold/mmfold-lane.py                 # the verdict
    .venv/bin/python .agents/slop/mmfold/mmfold-lane.py --port OTHER.bend  # a plant

WHAT IT IS. `rebase-gate.py`'s `rows()` reads 240 of the 334 lines `uop/fold.bend` prints, and
the 94th..334th are not missing by accident: `mm_row`/`bl_row` write ONE space and `rows()`
wants TWO. The oracles for those rows already exist and are alive -- `.agents/slop/mm-gate.py`
for the 72 `mm_*` rows and `.agents/slop/mm-bl-gate.py` for the 38 `bl_*` rows, both pure-CPython
and both naming this collision in their headers as a `diff` against a scratch `.bend` file that
no longer exists (`uop/fold2_work.bend`) or that duplicates the port (`uop/probe-mmcore.bend`).
So nothing was measured because nothing was WIRED, and the wiring needs a reader that can see
the rows, which is `.agents/slop/mmfold/mmfold-rows.py`.

WHAT IT REFUSES TO DO, all three measured in this repo today:

  * IT DOES NOT COMPARE TWO OF ITS OWN RUNS. The port lane and the oracle lane are different
    processes reading different trees; a lane that diffed its own output against its own output
    would be green forever, which is what `nv_query_litter`'s double error looked like.
  * IT DOES NOT CALL A CHILD THAT DIED A ZERO. Each child is checked for rc and for a NON-EMPTY
    row count, and a child that fails prints `DIED` and the lane exits 2 -- never 0 and never a
    green verdict over nothing. This is the defect `mm-lift-gate.py` had.
  * IT DOES NOT KEY ON ROW INDEX. Whole `name=value` lines are compared, keyed on name, because
    `agent-core.md` records a name-comparing harness that reported 0 for all 30 mutations in one
    unit and 0 for all 68 in another.

IT UNIONS `rows()` WITH `rows_f3one()` AND ASSERTS THEY ARE DISJOINT, which is what lets the
verdict be stated over the WHOLE 334-row lane rather than over a fragment of it.
"""
import argparse
import importlib.util
import pathlib
import subprocess
from collections import Counter
import sys

REPO = pathlib.Path(__file__).resolve().parents[3]
SLOP = REPO / ".agents" / "slop"
BEND = REPO / "bin" / "bend"
PORT = REPO / "tinybendygrad" / "uop" / "fold.bend"
ORACLES = (SLOP / "mm-gate.py", SLOP / "mm-bl-gate.py")   # the two producers of `mm_`/`bl_`
DIED_RC = 2


def _load(name, path):
  spec = importlib.util.spec_from_file_location(name, path)
  m = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(m)
  return m


def read_lane(text, gate_rows, one_rows):
  """(rows, unread, collapse) for one lane's text: `rows()` plus `rows_f3one()`, disjoint.

  The assertion is the point. Two readers both claiming a name is two answers to what a line
  means, and a union that silently preferred one of them would be exactly the phantom-row
  failure `reader-fork-census.py` was written to count.

  `collapse` is `lines claimed - distinct names`, and it is 0 unless a name is printed twice,
  in which case the dict kept the LAST answer and the first is gone with nothing saying so --
  which is how `rows()` loses a row and how a mutation table can report 19 of 28 as the whole.
  The lane refuses a non-zero collapse rather than diffing a set with a hole in it. The two
  per-reader counts below pin which reader owns it without either reader being re-implemented
  here, which is the discipline this project keeps having to relearn."""
  a, b = gate_rows(text), one_rows(text)
  both = set(a) & set(b)
  if both:
    raise SystemExit(f"DIED mmfold-lane readers overlap on {sorted(both)}: not a union")
  read = {**a, **b}
  unread = [l for l in text.splitlines() if l.strip() and
            l.partition(" ")[0].strip() not in read and l.partition("=")[0].strip() not in read]
  claimed = len([l for l in text.splitlines() if l.strip()]) - len(unread)
  return read, unread, claimed - len(read), len(a), len(b)


def child(argv, label):
  """(rc, stdout). A child that fails is reported as a death by `main`, never as zero rows."""
  r = subprocess.run(argv, capture_output=True, text=True, timeout=3600, cwd=str(REPO))
  return r.returncode, r.stdout, r.stderr


def main():
  ap = argparse.ArgumentParser(description=__doc__)
  ap.add_argument("--port", default=str(PORT), help="the .bend lane (default: uop/fold.bend)")
  ap.add_argument("--python", default=sys.executable,
                  help="the interpreter for the ORACLE side; mm-gate/mm-bl-gate are pure "
                       "CPython and import nothing, so any python runs them")
  args = ap.parse_args()

  gate = _load("rebase_gate", SLOP / "rebase-gate.py")     # the shared reader, by PATH
  one = _load("mmfold_rows", SLOP / "mmfold" / "mmfold-rows.py")

  rc, out, err = child([str(BEND), args.port], "port")
  if rc != 0:
    print(f"DIED mmfold-lane port: {args.port} exited {rc}: {err.strip().splitlines()[-1:]}")
    return DIED_RC
  port, port_unread, port_collapse, port_a, port_b = read_lane(out, gate.rows, one.rows_f3one)

  oracle, unread_by_readers, collapse_rows = {}, [], 0
  for o in ORACLES:
    rc, o_out, o_err = child([args.python, str(o)], o.name)
    if rc != 0:
      print(f"DIED mmfold-lane oracle {o.name}: exited {rc}: "
            f"{(o_err.strip().splitlines() or ['no stderr'])[-1]}")
      return DIED_RC
    got, unread, collapse, _, _ = read_lane(o_out, gate.rows, one.rows_f3one)
    if not got:
      print(f"DIED mmfold-lane oracle {o.name}: COMPARED ZERO ROWS -- it printed lines, and "
              f"none of them is a row under either reader. Nothing was checked.")
      return DIED_RC
    unread_by_readers += [f"{o.name}: {l!r}" for l in unread]
    collapse_rows += collapse
    print(f"oracle {o.name}: {len(got)} rows, {len(unread)} unread by either reader, "
          f"{collapse} name(s) printed twice")
    oracle.update(got)
  for l in unread_by_readers:
    print(f"  {l}")

  # SCOPE IS THE ORACLE SIDE'S, and that is deliberate: the oracles are the fixed list of what
  # is MEASURED, so scoping by them cannot silently shrink because a port lane stopped printing.
  # Naming the scope on every run is what makes "0 compared" a visible fact rather than a lane
  # that looks green because nothing asked it anything.
  scope = set(oracle)
  one_space_port = sorted(n for n in port if n in one.rows_f3one(out))
  compared = sorted(scope & set(port))
  bad = [(n, oracle[n], port[n]) for n in compared if oracle[n] != port[n]]
  only_port = sorted(scope - set(port))            # an oracle row the PORT DID NOT PRINT: a defect
  only_oracle = sorted(set(port) - scope)           # a port row nothing here measures: a COUNT
  outside = sorted(n for n in one_space_port if n not in scope)

  print()
  print(f"port  {args.port}")
  print(f"  {len(out.splitlines())} lines -> {len(port)} rows by rows()+rows_f3one(), "
        f"{len(port_unread)} unread, {port_collapse} name(s) printed twice")
  print(f"  of those rows: rows() read {port_a} and rows_f3one() read {port_b}")
  print(f"  ONE-SPACE F3 POPULATION (what the 93 were): {len(one_space_port)} rows, of which "
        f"{len(outside)} are outside these two oracles: {outside or 'none'}")
  print(f"SCOPE: {len(scope)} oracle rows ({dict(Counter(n.split('_')[0] for n in scope))})")
  print(f"COMPARED {len(compared)}   DISAGREEMENTS {len(bad)}   "
        f"MISSING FROM PORT {len(only_port)}   port rows out of scope {len(only_oracle)}")
  for n, want, got in bad:
    print(f"  DISAGREE {n}: oracle {want}  port {got}")
  for n in only_port:
    print(f"  MISSING FROM PORT {n} = {oracle[n]}")
  if only_oracle:
    print("  out of scope, by prefix: "
          f"{dict(Counter(n.split('_')[0] for n in only_oracle))}")
  print()
  ok = not bad and not only_port and not outside
  print("VERDICT", "GREEN" if ok else "NOT GREEN",
        f"-- the {len(scope)} rows these two oracles measure")
  faults = []
  if port_collapse:
    faults.append(f"{port_collapse} name(s) printed twice (fold.bend, NOT this lane's scope: "
                  f"see mm-lift-gate.py's DUPLICATE line)")
  if port_unread:
    faults.append(f"{len(port_unread)} printed line(s) no reader claims")
  print("LANE INTEGRITY", "CLEAN" if not faults else "; ".join(faults),
        f"-- all {len(out.splitlines())} lines of the port lane")
  return 0 if ok else 1


if __name__ == "__main__":
  raise SystemExit(main())
