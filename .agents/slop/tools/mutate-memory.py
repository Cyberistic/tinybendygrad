"""The measured mutation table for tinybendygrad/schedule/memory.bend.

DRIVER, not an editor: it writes one mutated copy of the file at a time, runs
BOTH lanes, diffs against the baseline, and restores. Run it from the repo root:

    python3 .agents/slop/tools/mutate-memory.py > /tmp/memtable.md

Each mutation is a single-token change to this file's OWN code. A mutation whose
pattern is absent is reported as NOT APPLIED rather than silently skipped.
"""
import subprocess, shutil, sys, os

os.chdir("/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
SRC = "tinybendygrad/schedule/memory.bend"

MUT = [
 ("`mem_ev_cmp`'s differing-index arm `is_le(ai,bi)` -> `False{}` (a comparator that says False in BOTH directions: the events sort in REVERSE key order)",
  "    case _: U32.is_le(ai, bi)", "    case _: False{}"),
 ("the open's `o` 1 -> 0, i.e. OPEN and CLOSE share a key and the close no longer precedes the open at one index",
  "  Ev{mem_first_i.of2(b, tc), 1, b}", "  Ev{mem_first_i.of2(b, tc), 0, b}"),
 ("`mem_hold.of`'s copy arm `add(d,1)` -> `d` (buf_hold off by one)",
  "def mem_hold.of(copy: Bool, d: U32) -> U32:\n  match copy:\n    case True{}: U32.add(d, 1)",
  "def mem_hold.of(copy: Bool, d: U32) -> U32:\n  match copy:\n    case True{}: d"),
 ("`mem_hold.of`'s non-copy arm 0 -> `d` (every buffer gets a hold, copy and compute alike)",
  "    case _: 0\n\ndef mem_hold2", "    case _: d\n\ndef mem_hold2"),
 ("`mem_key.cp.of`'s copy arm 1 -> 0 (the two lanes collide into one)",
  "def mem_key.cp.of(copy: Bool) -> U32:\n  match copy:\n    case True{}: 1",
  "def mem_key.cp.of(copy: Bool) -> U32:\n  match copy:\n    case True{}: 0"),
 ("`mem_collect.is_multi`'s MSTACK arm -> False{} (MSTACK stops recursing)",
  "def mem_collect.is_multi(op: O.Op) -> Bool:\n  match op:\n    case O.OpsMSELECT{}: True{}\n    case O.OpsMSTACK{}: True{}",
  "def mem_collect.is_multi(op: O.Op) -> Bool:\n  match op:\n    case O.OpsMSELECT{}: True{}\n    case O.OpsMSTACK{}: False{}"),
 ("`mem_collect.is_buf`'s True -> False{} (a BUFFER no longer collects itself)",
  "def mem_collect.is_buf(op: O.Op) -> Bool:\n  match op:\n    case O.OpsBUFFER{}: True{}",
  "def mem_collect.is_buf(op: O.Op) -> Bool:\n  match op:\n    case O.OpsBUFFER{}: False{}"),
 ("`mem_kern_cp3`'s STORE arm `mem_cp_add` -> `cp` (no buffer is ever a copy buffer)",
  "    case True{}: mem_cp_add.of(cp, bufs)", "    case True{}: cp"),
 ("`mem_kept.one`'s keep arm -> acc (the `_can_plan` filter stops filtering)",
  "def mem_kept.one(ok: Bool, b: U32, acc: List<&2, U32>) -> List<&2, U32>:\n  match ok:\n    case True{}: List.append(&2, U32, acc, [b])",
  "def mem_kept.one(ok: Bool, b: U32, acc: List<&2, U32>) -> List<&2, U32>:\n  match ok:\n    case True{}: acc"),
 ("`mem_args.of`'s `src_from(.., si, 1)` -> `.., si, 0` (the slice is not observable here)",
  "mem_args(O.Arena.budget(Plan.ar(pl)), pl, O.Arena.src_from(Plan.ar(pl), si, 1), Nil{})",
  "mem_args(O.Arena.budget(Plan.ar(pl)), pl, O.Arena.src_from(Plan.ar(pl), si, 0), Nil{})"),
 ("`mem_off.go`'s hit arm -> acc (every offset reads 0, so every peak is the raw size)",
  "def mem_off_step(hit: Bool, d: Off, acc: U32) -> U32:\n  match hit:\n    case True{}: Off.o(d)",
  "def mem_off_step(hit: Bool, d: Off, acc: U32) -> U32:\n  match hit:\n    case True{}: acc"),
 ("`mem_nbytes`'s `round_up(..)` -> the raw size (block rounding dropped)",
  "def mem_nbytes(+fx: F.Folded, +self: U32) -> U32:\n  H.round_up_u32(mem_raw(fx, self), mem_block_size())",
  "def mem_nbytes(+fx: F.Folded, +self: U32) -> U32:\n  mem_raw(fx, self)"),
 ("`mem_nbytes`'s block_size 256 -> 512 (the round is still done, to the wrong unit)",
  "def mem_block_size() -> U32: 256", "def mem_block_size() -> U32: 512"),
 ("`mem_raw`'s `U32.mul` -> `U32.add` (itemsize applied as an addition)",
  "def mem_raw(+fx: F.Folded, +self: U32) -> U32:\n  U32.mul(mem_numel(fx, self), S.Dt.itemsize(mem_dt(fx, self)))",
  "def mem_raw(+fx: F.Folded, +self: U32) -> U32:\n  U32.add(mem_numel(fx, self), S.Dt.itemsize(mem_dt(fx, self)))"),
 ("`mem_peak_one`'s hit arm `max(acc,v)` -> `v` (the peak is the LAST event, not the max)",
  "def mem_peak_one(hit: Bool, v: U32, acc: U32) -> U32:\n  match hit:\n    case True{}: U32.max(acc, v)",
  "def mem_peak_one(hit: Bool, v: U32, acc: U32) -> U32:\n  match hit:\n    case True{}: v"),
 ("`mem_lane_in.of`'s seed `False{}` -> `True{}` (every lane matches every other, so one lane)",
  "def mem_lane_in.of(+ls: List<&2, Lane>, +ln: Lane) -> Bool:\n  mem_lane_in(List.length(&2, Lane, ls), ls, ln, False{})",
  "def mem_lane_in.of(+ls: List<&2, Lane>, +ln: Lane) -> Bool:\n  mem_lane_in(List.length(&2, Lane, ls), ls, ln, True{})"),
 ("`mem_last_one`'s hit arm `v` -> `acc` (last_appearance is the FIRST touch)",
  "def mem_last_one(hit: Bool, v: U32, acc: U32) -> U32:\n  match hit:\n    case True{}: v",
  "def mem_last_one(hit: Bool, v: U32, acc: U32) -> U32:\n  match hit:\n    case True{}: acc"),
 ("`mem_first_i.seen`'s keep-first arm `acc` -> `v` (first_appearance is the LAST touch)",
  "def mem_first_i.seen(seen: Bool, v: U32, acc: U32) -> U32:\n  match seen:\n    case True{}: acc",
  "def mem_first_i.seen(seen: Bool, v: U32, acc: U32) -> U32:\n  match seen:\n    case True{}: v"),
 ("`mem_touch.one`'s `mem_bs_add` -> append unconditionally (the distinct list grows every touch)",
  "Scan{mem_tc_add(i, b, Scan.tc(s)), mem_bs_add(b, Scan.bs(s)), Scan.cp(s)}",
  "Scan{mem_tc_add(i, b, Scan.tc(s)), List.append(&2, U32, Scan.bs(s), [b]), Scan.cp(s)}"),
 ("`mem_scan`'s kernel fuel -> `+ 1n` (one step past the end, on the bottom node)",
  "mem_scan((List.length(&2, U32, O.Arena.srcs(ar, linear))), 0, ar, pl,",
  "mem_scan((List.length(&2, U32, O.Arena.srcs(ar, linear)) + 1n : Nat), 0, ar, pl,"),
]


def rows(stdout):
  d = {}
  for l in stdout.split("\n"):
    if "=" in l:
      k, v = l.split("=", 1)
      d[k] = v.strip()
  return d


def run():
  return subprocess.run(["./bin/bend", SRC], capture_output=True, text=True)


GREEN = open(SRC).read()
shutil.copy(SRC, SRC + ".gatebak")
base = rows(run().stdout)
print("| mutation | rows that moved | how many |")
print("| --- | --- | --- |")
for label, old, new in MUT:
  if old not in GREEN:
    print(f"| (NOT APPLIED -- pattern absent) {label[:44]} | - | - |")
    continue
  with open(SRC, "w") as f:
    f.write(GREEN.replace(old, new, 1))
  r = run()
  if r.returncode != 0:
    moved = ["<did not compile>"]
  else:
    out = rows(r.stdout)
    moved = [k for k in base if out.get(k) != base[k]]
  short = label if len(label) <= 58 else label[:55] + "..."
  print(f"| {short} | {', '.join(moved) if moved else 'NONE'} | {len(moved)} |")
shutil.copy(SRC + ".gatebak", SRC)
os.remove(SRC + ".gatebak")
print("(baseline restored)")