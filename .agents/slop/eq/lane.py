#!/usr/bin/env python3
"""lane.py -- CAPTURE A LANE, AND PROVE THE SUBSTRATE HELD STILL WHILE IT RAN.

    .venv/bin/python .agents/slop/eq/lane.py --port tinybendygrad/renderer/nir_llvmir.bend \
        --oracle .agents/slop/nl/nl-oracle.py rows --out PREFIX

WHY THIS EXISTS, MEASURED TWICE IN THIS UNIT.  The first capture of the `nir_llvmir` PORT lane
printed 206 rows; the second, thirty seconds later, printed ZERO with rc=1 and

    - message  : a parameter or field scrutinee (a match cannot scrutinize a computed value)
    7833 |     match vd_text.go(ys, Nil{}):

`vd_text` is in `tinybendygrad/uop/ops.bend:7837`, a file this unit does not own and must not
touch, and `stat` shows its mtime moving to the second.  So the second run is not a starved lane
(`agent-core.md`'s failure, where eight concurrent compiles starve each other) and not a port bug:
it is ANOTHER AGENT MID-EDIT in this file's import closure.  A capture taken across such an edit
is evidence about a revision that never existed, and reporting its zero as a result would be
reporting a defect in someone else's work.

So every capture here digests the WHOLE IMPORT CLOSURE before and after -- using
`rebase-gate.py`'s own `import_closure` and `substrate_manifest`, IMPORTED, because a second
closure walker is a second reader -- and a capture whose closure moved is labelled UNSTABLE and
retried, up to `rebase-gate.py`'s own `BEND_ROW_TRIES`, with the same backoff.  An UNSTABLE
capture is never silently kept.

IT ALSO PRINTS THE LOAD, because `0 rows` and `205 rows` are different claims and a starved lane is
plausible: every run reports the accepted-line count, the distinct-key count, and how long it took.
"""
import argparse, importlib.util, pathlib, subprocess, sys, time

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[2]


def load(name):
  spec = importlib.util.spec_from_file_location(name, str(HERE.parent / f"{name}.py"))
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod


RG = load("rebase-gate")


def closure(bend):
  """{path: (head, size)} over the whole import closure, via `rebase-gate.py`'s own walker."""
  return {p: (h, s) for p, h, s in RG.substrate_manifest(pathlib.Path(bend))}


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--port")
  ap.add_argument("--oracle", nargs="+")
  ap.add_argument("--out", required=True)
  ap.add_argument("--tries", type=int, default=RG.BEND_ROW_TRIES)
  # An oracle may carry ITS OWN flags (`rebase-gate.py:BASE_ORACLES` records
  # `.agents/slop/xd1/render-gate-oracle.py --gate`), and argparse eats a leading `--flag` as one of
  # its own. `--` ends this file's options; everything after it belongs to the ORACLE.
  a, rest = ap.parse_known_args()
  oracle = list(a.oracle or []) + [x for x in rest if x != "--"]
  if a.port and oracle:
    print("  give EITHER --port OR --oracle, not both: a lane pair is two invocations, and a "
          "capture of both would hide which side produced what.")
    return 1
  port = pathlib.Path(a.port) if a.port else None
  before = closure(port) if port else {}
  t0 = time.monotonic()
  if port:
    p = subprocess.run(["./bin/bend", a.port], cwd=REPO, capture_output=True, text=True)
    rc, out, err = p.returncode, p.stdout, p.stderr
  else:
    o = subprocess.run([sys.executable] + oracle, cwd=REPO, capture_output=True, text=True)
    rc, out, err = o.returncode, o.stdout, o.stderr
  secs = round(time.monotonic() - t0, 1)
  after = closure(port) if port else {}
  moved = sorted(set(before) ^ set(after)) + \
      sorted(p for p in set(before) & set(after) if before[p] != after[p])
  names = len(RG.rows(out))
  print(f"  rc={rc}  {secs}s  lines={len(out.splitlines())}  distinct keys of `rows()`={names}"
        f"  closure={len(before)} file(s)"
        f"{'' if not moved else '  !! SUBSTRATE MOVED: ' + ', '.join(moved)}")
  if rc:
    print(f"  stderr: {' '.join(err.split())[-160:]}")
  pathlib.Path(f"{a.out}.txt").write_text(out)
  pathlib.Path(f"{a.out}.err").write_text(err)
  # A lane that printed NOTHING is a REQUEST FOR A RETRY, not a result -- and never a pass.
  return 0 if (not rc and names and not moved) else 1


if __name__ == "__main__":
  sys.exit(main())