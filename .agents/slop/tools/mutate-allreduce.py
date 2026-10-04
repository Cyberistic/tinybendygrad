"""The measured mutation table for tinybendygrad/schedule/allreduce.bend.

    python3 .agents/slop/tools/mutate-allreduce.py > /tmp/artable.md
"""
import subprocess, shutil, os

os.chdir("/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
SRC = "tinybendygrad/schedule/allreduce.bend"

MUT = [
 ("`red_worth`'s `and` -> `or` (either the device count or the size is enough)",
  "def red_worth.of(many: Bool, big: Bool) -> Bool:\n  Bool.and(many, big)",
  "def red_worth.of(many: Bool, big: Bool) -> Bool:\n  Bool.or(many, big)"),
 ("`red_worth`'s `numel > thr` -> `numel >= thr` (the threshold is inclusive)",
  "  red_worth.of(U32.is_gt(ndev, 2), U32.is_gt(numel, thr))",
  "  red_worth.of(U32.is_gt(ndev, 2), U32.is_ge(numel, thr))"),
 ("`red_worth`'s `ndev > 2` -> `ndev >= 2` (the two-node empirical arm disappears)",
  "  red_worth.of(U32.is_gt(ndev, 2), U32.is_gt(numel, thr))",
  "  red_worth.of(U32.is_ge(ndev, 2), U32.is_gt(numel, thr))"),
 ("`red_ge2`/`red_ge1`'s `2` -> `1` (the force overrides become the default)",
  "def red_ge2(v: U32) -> Bool:\n  U32.is_ge(v, 2)",
  "def red_ge2(v: U32) -> Bool:\n  U32.is_ge(v, 1)"),
 ("`red_ring3`'s `not a2` -> `a2` (ring and all2all can both fire)",
  "def red_ring3(concrete: Bool, a2: Bool, ok: Bool) -> Bool:\n  Bool.and(Bool.and(concrete, Bool.not(a2)), ok)",
  "def red_ring3(concrete: Bool, a2: Bool, ok: Bool) -> Bool:\n  Bool.and(Bool.and(concrete, a2), ok)"),
 ("`red_a2` drops the `concrete and` (a symbolic shape still gets a ring)",
  "def red_a2(concrete: Bool, +ndev: U32, +numel: U32, +cfg: Cfg) -> Bool:\n  red_and(concrete, Bool.or(",
  "def red_a2(concrete: Bool, +ndev: U32, +numel: U32, +cfg: Cfg) -> Bool:\n  red_and(True{}, Bool.or("),
 ("`red_all_int`'s `and` -> `or` (one int dim is enough to call a shape concrete)",
  "    case s <> t: Bool.and(red_is_int(s), red_all_int.go(t))",
  "    case s <> t: Bool.or(red_is_int(s), red_all_int.go(t))"),
 ("`red_mode`'s ALL2ALL arm 2 -> 1 (all2all and ring print the same number)",
  "def red_mode.of(a2: Bool, ring: Bool) -> U32:\n  match a2:\n    case True{}: 2",
  "def red_mode.of(a2: Bool, ring: Bool) -> U32:\n  match a2:\n    case True{}: 1"),
 ("`red_factor`'s keep-first `Bool.not(found)` -> `True{}` (last factor wins)",
  "def red_factor.take(found: Bool, ok: Bool) -> Bool:\n  Bool.and(Bool.not(found), ok)",
  "def red_factor.take(found: Bool, ok: Bool) -> Bool:\n  Bool.or(Bool.not(found), ok)"),
 ("`red_factor_factors`'s 32 -> 8 (the granularity ladder starts lower)",
  "  [32, 16, 8, 4, 2]", "  [8, 16, 4, 2]"),
 ("`red_bump`'s `is_lt(k, left)` -> `is_lt(k, left+1)` (one chunk too many are enlarged)",
  "def red_bump(+k: U32, +left: U32) -> U32:\n  red_bump.of(U32.is_lt(k, left))",
  "def red_bump(+k: U32, +left: U32) -> U32:\n  red_bump.of(U32.is_lt(k, U32.add(left, 1)))"),
 ("`red_bounds`'s running start `add` -> `sub` (the bounds walk backwards)",
  "    case 1n+p: red_bounds(p, List.tail(&2, U32, ws), U32.add(st, red_head(ws)),\n                          List.append(&2, Chk, acc, [Chk{st, U32.add(st, red_head(ws))}]))",
  "    case 1n+p: red_bounds(p, List.tail(&2, U32, ws), U32.add(st, red_head(ws)),\n                          List.append(&2, Chk, acc, [Chk{U32.add(st, red_head(ws)), st}]))"),
 ("`red_bounds`'s start 0 -> `numel` (the accumulate starts at the wrong end)",
  "def red_bounds_of(+numel: U32, +ndev: U32) -> List<&2, Chk>:\n  red_bounds(U32.to_nat(ndev), red_chunk_sizes(numel, ndev), 0, Nil{})",
  "def red_bounds_of(+numel: U32, +ndev: U32) -> List<&2, Chk>:\n  red_bounds(U32.to_nat(ndev), red_chunk_sizes(numel, ndev), numel, Nil{})"),
 ("`red_hdev_fires` drops `hdev > 0` (a zero hdev divides everything)",
  "def red_hdev_fires.of(on: Bool, divides: Bool) -> Bool:\n  Bool.and(on, divides)",
  "def red_hdev_fires.of(on: Bool, divides: Bool) -> Bool:\n  Bool.or(on, divides)"),
 ("`red_boxes`'s `div` -> `mod` (the box count is the remainder)",
  "def red_boxes(+ndev: U32, +hdev: U32) -> U32:\n  U32.div(ndev, hdev)",
  "def red_boxes(+ndev: U32, +hdev: U32) -> U32:\n  U32.mod(ndev, hdev)"),
 ("`red_cs.k`'s `k+1` -> `k` (every cs bound pair collapses to a point)",
  "  Chk{U32.div(U32.mul(numel, k), hdev), U32.div(U32.mul(numel, U32.add(k, 1)), hdev)}",
  "  Chk{U32.div(U32.mul(numel, k), hdev), U32.div(U32.mul(numel, k), hdev)}"),
]


import pathlib
import sys

# ── THE ROW READER IS `rebase-gate.py`'s OWN, LOADED BY PATH AND NOT COPIED ──────────────
# Measured by reader-fork-census.py on this corpus: 51 of 52 text readers disagreed with
# `rows()` on at least one of six row shapes, and four of them carried a docstring
# claiming to BE it. This file used to be one of them.
# ⚠ NOT FREE, and the census prints the load: of 1,440 lane files under .agents/slop
# (289,262 lines), 44,345 are F2 `py=`-tail lines and 2,370 are F3 two-space lines --
# so a fork that did not fold the tail was reading a DIFFERENT STRING on ~15% of lanes,
# and one that skipped F3 was blind to ~0.8%. Those are the sizes of what was wrong.
_RG = importlib.util.spec_from_file_location("rebase_gate", pathlib.Path(__file__).resolve().parent.parent / "rebase-gate.py")
_rebase_gate = importlib.util.module_from_spec(_RG)
_RG.loader.exec_module(_rebase_gate)
rows = _rebase_gate.rows


GREEN = open(SRC).read()
shutil.copy(SRC, SRC + ".gatebak")
base = rows(subprocess.run(["./bin/bend", SRC], capture_output=True, text=True).stdout)
print("| mutation | rows that moved | how many |")
print("| --- | --- | --- |")
for label, old, new in MUT:
  if old not in GREEN:
    print(f"| (NOT APPLIED -- pattern absent) {label[:44]} | - | - |")
    continue
  with open(SRC, "w") as f:
    f.write(GREEN.replace(old, new, 1))
  r = subprocess.run(["./bin/bend", SRC], capture_output=True, text=True)
  moved = ["<did not compile>"] if r.returncode != 0 else [k for k in base if rows(r.stdout).get(k) != base[k]]
  short = label if len(label) <= 58 else label[:55] + "..."
  print(f"| {short} | {', '.join(moved) if moved else 'NONE'} | {len(moved)} |")
shutil.copy(SRC + ".gatebak", SRC)
os.remove(SRC + ".gatebak")
print("(baseline restored)")