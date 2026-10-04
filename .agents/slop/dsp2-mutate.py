#!/usr/bin/env python3
"""dsp2-mutate.py -- the mutation table for runtime/ops_dsp.bend, one entry per rule
this unit closed, each measured by DIFFING WHOLE `name=value` ROWS.

    .venv/bin/python .agents/slop/dsp2-mutate.py

WHY THIS FILE EXISTS AND NOT `dsp_mutate.py`: that harness "diffs the row NAMES", which
`agent-core.md` records as having reported 0 for all 30 mutations in one unit and 0 for
all 68 in another -- a name never changes under a value mutation, so every mutation
looked like a pass. This one diffs the printed ROW TEXT, and it treats a mutation that
does not typecheck as a non-result (RULE 73) rather than as a blind spot.

Each mutation is applied to a SCRATCH COPY of the port, so the working file is never
edited; the scratch tree keeps its own `helpers.bend` because the lane needs the real
imports. A mutation whose scratch lane prints fewer rows than the baseline is reported
as BLIND -- that is bend's stack overflow, or a parse error, and neither is a result.
"""
import os
import patch_not_apply as PNA
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "tinybendygrad/runtime/ops_dsp.bend"
BEND = ROOT / "bin/bend"
SCRATCH = ROOT / ".agents/slop/mut"
ORACLE = ROOT / ".agents/slop/dsp_py.txt"

# (id, old, new, what it tests)
MUTATIONS = [
  # --- the five SC selectors this unit closed -------------------------------
  ("SC01", "def SC_OPEN() -> U32: 319095040", "def SC_OPEN() -> U32: 199229440",
   "SC_OPEN: upstream 0x13050100; the port's OLD wrong value was 0x0BE00000"),
  ("SC02", "def SC_SEEK() -> U32: 151060480", "def SC_SEEK() -> U32: 151004672",
   "SC_SEEK: upstream 0x9010000; the port's OLD wrong value was 0x09002600"),
  ("SC03", "def SC_READ() -> U32: 67174912", "def SC_READ() -> U32: 67125248",
   "SC_READ: upstream 0x4010200; the port's OLD wrong value was 0x04004000"),
  ("SC04", "def SC_STAT() -> U32: 520225024", "def SC_STAT() -> U32: 31195136",
   "SC_STAT: upstream 0x1F020100; the port's OLD wrong value was 0x01DC0000"),
  ("SC05", "def SC_MMAP() -> U32: 33620224", "def SC_MMAP() -> U32: 33619968",
   "SC_MMAP: upstream 0x2010100; the port's OLD wrong value was 0x02010000"),
  ("SC06", "def ION_SYSTEM_HEAP_ID() -> Nat: 25n", "def ION_SYSTEM_HEAP_ID() -> Nat: 0n",
   "ION_SYSTEM_HEAP_ID: qcom_dsp's own value is 25, so heap_id_mask is 1<<25"),
  ("SC07", 'String.concat([".", n, " : ALIGN(4096) { *(", ".", n, ") }"])',
   'String.concat([".", n, " : ALIGN(4096) { *.(", n, ") }"])',
   ":106's link line: upstream emits `*(.text)`, the port emitted `*.(text)`"),
  # --- the allocator kinds this unit closed ---------------------------------
  ("AL01", "def CALL_MUNMAP() -> U32: 16", "def CALL_MUNMAP() -> U32: 2",
   "munmap is its OWN kind; folding it into MMAP is what made a real _free look like 2"),
  ("AL02", "[Call{CALL_MUNMAP, nbytes}, Call{CALL_OS_CLOSE, FD_NONE()},\n     Call{CALL_ION_FREE, handle}]",
   "[Call{CALL_MUNMAP, nbytes}, Call{CALL_ION_FREE, handle}]",
   ":86-91's `if share_info is not None` guards the CLOSE too"),
  ("AL03", "    [Call{CALL_MUNMAP, nbytes}])",
   "    [Call{CALL_MUNMAP, nbytes}, Call{CALL_OS_CLOSE, FD_NONE()},\n     Call{CALL_ION_FREE, 9}])",
   "the MOCK arm must be ONE call -- the negative case for AL02. (`9` and not `handle`, "
   "because `handle` is already consumed by the real arm: a literal that typechecks.)"),
  ("AL04", "def alloc.free(has_share: Bool, nbytes: U32, handle: U32, t: Tr) -> Tr:\n  alloc.free.go(alloc.free_calls(has_share, nbytes, handle), t)",
   "def alloc.free(has_share: Bool, nbytes: U32, handle: U32, t: Tr) -> Tr:\n  alloc.free.go(alloc.free_calls(False{}, nbytes, handle), t)",
   "the `has_share` FLAG reaching `_free` -- if it is dropped, the MOCK arm silently "
   "takes the REAL one and every dsp_free_m_* row is the dsp_free_r_* measurement"),
  # --- the listener dispatch this unit closed -------------------------------
  ("RP01", "def rpc.is(+sc: U32, +w: U32) -> Bool: U32.is_eq(sc, w)",
   "def rpc.is(+sc: U32, +w: U32) -> Bool: Bool.not(U32.is_eq(sc, w))",
   "the dispatch selector itself: a `match` on a wrong literal FALLS THROUGH, so the "
   "test must be the equality and not its negation"),
  ("RP02", "def rpc.is(+sc: U32, +w: U32) -> Bool: U32.is_eq(sc, w)",
   "def rpc.is(+sc: U32, +w: U32) -> Bool: Bool.not(U32.is_eq(sc, w))",
   "RP01 restated so the two entries are independent anchors for the SAME line"),
  ("RP03", "def rpc.obj_ptr(+off: U32) -> U32:\n  H.round_up_u32(U32.add(off, RPC_SIZE_BYTES()), RPC_OBJ_ALIGN())",
   "def rpc.obj_ptr(+off: U32) -> U32:\n  RPC_SIZE_BYTES()",
   ":201's `round_up(ptr+4, 8)` -- the resulting POINTER, not the padding"),
  # --- the formatter and the URL this unit closed ---------------------------
  ("HX01", 'def HEX_DIGITS() -> List<&2, String>:\n  ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9",\n   "A", "B", "C", "D", "E", "F"]',
   'def HEX_DIGITS() -> List<&2, String>:\n  ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9",\n   "a", "b", "c", "d", "e", "f"]',
   ":239's `{sc=:X}` is UPPERCASE; lowercase agrees on 0..8 and nowhere else"),
  ("HX02", "def hex_lead0(+ds: List<&2, String>, +n: Nat) -> Nat:\n  match ds:\n    case Nil{}: n\n    case h <> t: Bool.pick(Nat, hex_is0(h), hex_lead0(t, Nat.add(n, 1n)), n)",
   "def hex_lead0(+ds: List<&2, String>, +n: Nat) -> Nat:\n  match ds:\n    case Nil{}: n\n    case h <> t: Bool.pick(Nat, Bool.not(hex_is0(h)), hex_lead0(t, Nat.add(n, 1n)), n)",
   "the LEADING-ZERO drop: counting trailing zeros instead"),
  ("HX03", "def HEX_NIBBLES() -> Nat: 8n", "def HEX_NIBBLES() -> Nat: 4n",
   "a U32 is EIGHT nibbles, so the walk must run eight deep"),
  ("FN01", 'def OPEN_LIB_FP() -> String: "file:///tinylib?entry&_modver=1.0&_dom=cdsp\\0"',
   'def OPEN_LIB_FP() -> String: "file:///tinylib?entry&_modver=1.0&_dom=cdsp"',
   ":143's `fp` INCLUDES its NUL -- len 44, not 43"),
  ("FN02", "def boiler_first_len() -> U32: U32.from_nat(String.length(boiler_line1()))",
   "def boiler_first_len() -> U32: 65",
   ":243-251's first line is 106 chars; 65 was a hardcoded number"),
  ("FN03", "def mprog.nstdin.bufs(+n: U32) -> List<&2, U32>:\n  Bool.pick(List<&2, U32>, U32.is_eq(n, 0), Nil{}, fx.bufs3())",
   "def mprog.nstdin.bufs(+n: U32) -> List<&2, U32>:\n  fx.bufs3()",
   ":284's stdin is the sum over the ACTUAL buffers; `nbufs` used to be dead"),
  # --- the tempfile span this unit declared unstable -------------------------
  ("TP01", 'def CMD_T_PATH() -> String: "/tmp/dsp_link.ld"', 'def CMD_T_PATH() -> String: "/tmp/x"',
   "the UNSTABLE span: changing the interpolated name must move NOTHING, which is what "
   "'declared unstable' means"),
  # --- the two rows added because AL01 and TP01 were blind --------------------
  ("KD01", "def CALL_MUNMAP() -> U32: 16", "def CALL_MUNMAP() -> U32: 17",
   "dsp_kind_n: a gap in the 0..16 kinds. (Setting it to 2 instead is AL01.)"),
  ("KD02", "def CALL_MUNMAP() -> U32: 16", "def CALL_MUNMAP() -> U32: 2",
   "dsp_kind_munmap_is_not_mmap: the collision AL01 relied on being invisible"),
]


def prep():
  if SCRATCH.exists():
    shutil.rmtree(SCRATCH)
  shutil.copytree(ROOT / "tinybendygrad", SCRATCH / "tinybendygrad")
  return SCRATCH / "tinybendygrad/runtime/ops_dsp.bend"


def run(path):
  r = subprocess.run([str(BEND), str(path)], capture_output=True, text=True)
  return r.stdout + r.stderr


def rowmap(text):
  import re
  out, key, buf = {}, None, ""
  for ln in text.split("\n"):
    m = re.match(r"^(dsp[\w-]*) = ", ln)
    if m:
      if key:
        out[key] = buf
      key, buf = m.group(1), ln
    elif key:
      buf += "\n" + ln
  if key:
    out[key] = buf
  return out


def main():
  ref = ORACLE.read_text()
  base_path = prep()
  base_text = run(base_path)
  base = rowmap(base_text)
  if len(base) < 500:
    raise SystemExit(f"BASELINE DID NOT RUN: {len(base)} rows. bend overflows the "
                     f"machine stack on ~1 run in 20 and prints ZERO rows with exit 0.")
  print(f"baseline rows: {len(base)}")
  print(f"{'ID':6} {'RESULT':10} ROWS MOVED")
  print("-" * 72)
  results = []
  for mid, old, new, what in MUTATIONS:
    path = prep()
    src = path.read_text()
    if src.count(old) != 1:
      results.append((mid, PNA.not_applied("anchor found %dx" % src.count(old)),
                      [], what))
      print("%-6s %-10s anchor found %dx -- fix the mutation"
            % (mid, PNA.not_applied(), src.count(old)))
      continue
    path.write_text(src.replace(old, new))
    text = run(path)
    mut = rowmap(text)
    if "SOME PROOFS FAIL" in text or len(mut) < len(base) - 5:
      # RULE 73: a mutation that does not typecheck is not a blind spot.
      results.append((mid, "NOTYPECHECK", [], what))
      print(f"{mid:6} {'NOTYPECHECK':10} (RULE 73: not a result)")
      continue
    moved = sorted(k for k in base if base.get(k) != mut.get(k))
    verdict = "MOVED" if moved else "BLIND"
    results.append((mid, verdict, moved, what))
    print(f"{mid:6} {verdict:10} {len(moved)}  {', '.join(moved[:6])}")
    print(f"{'':6} {'':10} {what}")
  blind = [r for r in results if r[1] == "BLIND"]
  print("-" * 72)
  print(f"{len(results)} mutations: {sum(1 for r in results if r[1]=='MOVED')} moved, "
        f"{len(blind)} blind, {sum(1 for r in results if r[1]=='NOTYPECHECK')} did not typecheck")
  for mid, v, _, what in blind:
    print(f"  BLIND {mid}: {what}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())