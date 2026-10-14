#!/usr/bin/env python
"""IS THE OUT-OF-PROCESS RULE LOAD-BEARING? Tested, not inherited -- and the test corrected me.

`checks/census.py:220` claims the py lane's `P(i..)` slot "comes from a module-level
`itertools.count` reaching the rows via `ParamArg(next(...))`", and that 68 slots regenerated in
ONE PROCESS wrote 37 distinct values where a per-process run gives 4.

  **MY OWN MEASUREMENT WAS WRONG FIRST, AND THE BEFORE-VALUE IS THE POINT.**  I grepped
  `P([0-9]*)` against the 34 py row files, got **0 hits**, and wrote in this file's own header
  that the claim was "not reproducible against this tree" and that "the only occurrences of
  `P(i..)` and `itertools.count` in the whole subject are the PROSE of that comment".  The grep
  was wrong: the row spelling is `P(i0,` -- an `i` PREFIX, not a bare digit -- so a digit-only
  pattern finds nothing and "nothing" looked like "there is nothing to find".  THAT IS THE
  SEVENTH WAY, REDONE BY HAND, IN THE INSTRUMENT BUILT TO CHECK THE SEVENTH WAY.

  What survives of my claim is only the narrower half: `grep -n itertools .agents/slop/graphcmp.py`
  really does answer nothing, so the MECHANISM is misattributed.  The nearest real thing is
  `graphcmp.py:864`, citing `ops.py:1208  if slot is None: slot = next(UOp.unique_num)` -- a
  monotonic counter that lives in TINYGRAD, not in the harness.  So the comment is RIGHT about
  the OUTCOME and WRONG about the CAUSE, which is the more dangerous shape: a reader who audits
  the named mechanism finds nothing and concludes there is nothing there.

  The numbers below are the comment's own, reproduced: **37 distinct values in one process
  against 4 per process**, and 25 of 34 slots differ, `alu`->`P(i1,` and `binblob`->`P(i2,` --
  the index advancing by one for each graph that preceded it.
"""
import os, pathlib, subprocess, sys

REPO = pathlib.Path(__file__).resolve().parents[3]
OUT = pathlib.Path(__file__).resolve().parent / "p-scope"

IN_PROCESS = r'''
import os, pathlib, sys
os.environ["DEV"] = "CPU"
REPO = pathlib.Path(sys.argv[1]); OUT = pathlib.Path(sys.argv[2]); OUT.mkdir(parents=True, exist_ok=True)
sys.path.insert(0, str(REPO / ".agents/slop")); sys.path.insert(0, str(REPO))
import graphcmp as G
G.load_tinygrad(); G.COMM = G.commutative()
for n in sorted(G.GRAPHS):
    (OUT / f"rows-{n}-py.rows").write_text("\n".join(G.emit_py(n, None)) + "\n")
print("emitted", len(sorted(G.GRAPHS)), "graphs in ONE process")
'''

def per_process(dest: pathlib.Path) -> None:
    dest.mkdir(parents=True, exist_ok=True)
    for g in sorted({ln.split("\t")[0] for ln in
                     (REPO / "checks/rows/keys.rows").read_text().splitlines()}):
        subprocess.run([sys.executable, str(REPO / "checks/census.py"), "--only", g, "--fresh"],
                       cwd=REPO, capture_output=True, text=True, check=True)
        src = REPO / f"checks/rows/rows-{g}-py.rows"
        (dest / f"rows-{g}-py.rows").write_bytes(src.read_bytes())

def main() -> int:
    if OUT.exists():
        for p in OUT.rglob("*"):
            p.unlink()
    print("per-process ...")
    per_process(OUT / "per")
    print("one process ...")
    r = subprocess.run([sys.executable, "-c", IN_PROCESS, str(REPO), str(OUT / "one")],
                       cwd=REPO, capture_output=True, text=True)
    if r.returncode:
        print(r.stdout, r.stderr[-400:]); return 3
    print("   ", r.stdout.strip())

    names = sorted(p.name for p in (OUT / "per").iterdir())
    same, diff = [], []
    for n in names:
        a = (OUT / "per" / n).read_text()
        b = (OUT / "one" / n).read_text() if (OUT / "one" / n).is_file() else ""
        (same if a == b else diff).append(n)
    print(f"\nslots agreeing   {len(same)}/{len(names)}")
    print(f"slots differing  {len(diff)}  {diff[:6]}")
    for n in diff[:2]:
        a = (OUT / "per" / n).read_text().splitlines()
        b = (OUT / "one" / n).read_text().splitlines()
        for x, y in zip(a, b):
            if x != y:
                print(f"  {n}: per-process {x}\n  {' ' * len(n)}  one-process {y}")
                break
    print(f"\nVERDICT: {'OUT-OF-PROCESS RULE IS LOAD-BEARING' if diff else 'CURRENTLY UNLOADED -- the two orders produce identical rows'}")
    return 0

if __name__ == "__main__":
    sys.exit(main())