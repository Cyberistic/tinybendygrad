#!/usr/bin/env python3
"""Mutation harness for webgpu_call.bend. Rows are diffed as WHOLE name=value
lines, never by row NAME -- per agent-core.md a name-comparing harness reported 0
for every mutation in two units.

Usage: python3 .agents/slop/mutate_webgpu_call.py
"""
import os, re, subprocess, sys, shutil, tempfile
import patch_not_apply as PNA

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "tinybendygrad", "runtime", "webgpu_call.bend")
MIRROR = os.path.join(ROOT, ".agents/slop/mirror/tinybendygrad")
BEND = os.path.join(ROOT, "bin", "bend")


def rows_of(path):
  """Interpret the gate at `path`. Returns {name: value} or None if it did not
  print `wgc-done=1` -- bend's machine stack overflows on ~1 run in 20 and prints
  ZERO rows, which is indistinguishable from not having started, so a short run is
  retried rather than read as a result."""
  for _ in range(6):
    r = subprocess.run([BEND, path], capture_output=True, text=True, cwd=ROOT)
    out = r.stdout
    if "wgc-done=1" not in out:
      continue
    d = {}
    for ln in out.splitlines():
      if "=" in ln and ln.split("=", 1)[0].startswith("wgc_"):
        k, v = ln.split("=", 1)
        d[k] = v
    return d
  return None


# (id, the edit, what it is testing). `None` for old means "must be present".
MUTATIONS = [
  ("M1", ("U32.is_eq(n, 0)", "U32.is_eq(n, 1)"),
   ":97 binds `float('inf')` at binding 0 -- WALL 3. Only the FIRST entry is a float."),
  ("M2", ("W.dev.uniform_bytes(val)", "Nil{}"),
   ":204's four-byte little-endian pattern. Dropping it leaves the int uniform unwritten."),
  ("M3", ("def QUERY_BUF_BYTES() -> U32: 16", "def QUERY_BUF_BYTES() -> U32: 8"),
   ":115's `size=16` on the query buffer, and :215's copy of the same size."),
  ("M4", ("def QUERY_TYPE_TIMESTAMP() -> U32: 2", "def QUERY_TYPE_TIMESTAMP() -> U32: 0"),
   ":114's `type=WGPUQueryType_Timestamp`."),
  ("M5", ("def BEGIN_PASS() -> U32: 0", "def BEGIN_PASS() -> U32: 1"),
   ":116's `beginningOfPassWriteIndex=0`."),
  ("M6", ("def END_PASS() -> U32: 1", "def END_PASS() -> U32: 0"),
   ":117's `endOfPassWriteIndex=1`. M5 and M6 together pin the PAIR."),
  ("M7", ("def SHADER_STAGE_COMPUTE() -> U32: 4", "def SHADER_STAGE_COMPUTE() -> U32: 2"),
   ":75's `visibility=WGPUShaderStage_Compute` at every layout entry."),
  ("M8", ("def MAP_MODE_READ() -> U32: 1", "def MAP_MODE_READ() -> U32: 2"),
   ":18's `WGPUMapMode_Read`. 2 is Write, which the port never asks for."),
  ("M9", ("def POWER_PREF_HIGH_PERF() -> U32: 2", "def POWER_PREF_HIGH_PERF() -> U32: 1"),
   ":169's `powerPreference=HighPerformance`. 1 is LowPower."),
  ("M10", ("def SUBMIT_COUNT() -> U32: 1", "def SUBMIT_COUNT() -> U32: 2"),
   ":129's `wgpuQueueSubmit(queue, 1, ...)`."),
  ("M11", ("def RESOLVE_COUNT() -> U32: 2", "def RESOLVE_COUNT() -> U32: 1"),
   ":126's `ResolveQuerySet(enc, qs, 0, 2, qbuf, 0)` -- the SECOND index."),
  ("M12", ("Release{Cs.last(buf), W.OBJ_COMMAND_BUFFER()}),\n        W.CALL_RELEASE, W.OBJ_COMMAND_ENCODER,",
           "Release{Cs.last(enc), W.OBJ_COMMAND_ENCODER()}),\n        W.CALL_RELEASE, W.OBJ_COMMAND_BUFFER,"),
   ":216-217's cmd_buf BEFORE encoder -- the REVERSE of creation. `wg_call_released` pins the opposite order in the pass's own seven releases, so the two cannot be confused."),
  ("M13", ("Nat.add(Nat.add(1n, List.length(&2, W.Buf, bs)), nvals)",
           "Nat.add(List.length(&2, W.Buf, bs), nvals)"),
   ":77's entryCount = 1 + len(bufs) + len(vals). The INFINITY entry."),
  ("M14", ("Nat.sub(U32.to_nat(i), 1n)", "U32.to_nat(i)"),
   "a `bufs` slot binds `bs[i-1]`, not `bs[i]`: :77 puts INFINITY at slot 0."),
  ("M15", ("Cs.caller(i, is_buf, bs)", "0"),
   "THE `Bool.pick` ARM ORDER in `Cs.caller`. Swapping them binds id 0 to every buffer slot -- which is exactly the bug the browser found, because `wgc_bg_sizes` reads SIZES and a wrong id does not change one."),
  ("M16", ("W.dev.uniform_usage()", "W.alloc.usage()"),
   ":203's UNIFORM|COPY_DST against :152's Storage|CopyDst|CopySrc. Both are one CALL_CREATE with the same object kind, so the TRACE cannot see this."),
  ("M17", ("W.copy.readable_usage()", "W.alloc.usage()"),
   ":208's CopyDst|MapRead against the allocator's. Same blindness as M16."),
  ("M18", ("W.Tr.has(Cs.calls(c), W.Tr.calls(W.Pass.tr(p)))",
           "Bool.pick(Bool, U32.is_eq(Cs.len(c), W.seen(W.Pass.tr(p))), True{}, False{})"),
   "THE CENTRAL ROW, replaced by the length half of itself: equality by length alone, with no order. `wgc_call_trace` and `wgc_call_len` together are one check and this is what shows it."),
  ("M19", ("def Cs.order.go(n: Nat, ss: List<&2, Step>, acc: List<&2, Step>) -> List<&2, Step>:\n  match n:\n    case 0n: List.reverse(&2, Step, acc)",
           "def Cs.order.go(n: Nat, ss: List<&2, Step>, acc: List<&2, Step>) -> List<&2, Step>:\n  match n:\n    case 0n: acc"),
   "THE ORDER of the ordered-steps walk. `Cs.at` conses onto the FRONT, so the walk already ends in step order and this reverse undid it -- MEASURED: it printed the whole call backwards while every subsequence row stayed green."),
  ("M20", ("W.dev.uniform_bytes(val)", "W.dev.uniform_bytes(U32.shrn(val, 1n))"),
   "REINTRODUCES THE ops_webgpu BUG in webgpu_call.bend's own use of the function. `wgc_wall3_int_bytes` is the only row that sees it, which is the whole reason that row exists."),
  ("M21", ("W.bgl.of(nbufs, nvals)", "Nil{}"),
   ":82's `entries`. The layout the bind group is made against."),
  ("M22", ("W.prog.wants_wait(want, feats)", "want"),
   ":71's `wait and TimestampQuery in self.dev.features`. Dropping the feature test means a device WITHOUT the feature still creates a query set."),
  ("M23", ("def Cs.shader(+c: Cs, code: String) -> Cs:\n  +m = Cs.mint(c)",
            "def Cs.shader(+c: Cs, code: String) -> Cs:\n  m = c"),
   "THE FROZEN-COUNTER MUTATION, and the one that cost the most: bind the mint and then thread the ORIGINAL state, so the counter never advances. MEASURED as 100% invisible to this gate -- every handle became 4294967295 and every row stayed green. `wgc_handles_monotone` was written afterwards and is the row that sees it."),
  ("M24", (None, None), "a comment-only edit -- THE CONTROL"),
]


def apply_edit(text, old, new):
  if old is None:
    return text, None
  # tolerate the call site as well as the def: replace EVERY occurrence
  n = text.count(old)
  if n == 0:
    # WHY, not a bool.  The marker travels with the failure, so the call site
    # cannot re-spell it, which is the whole point of one shared reporter.
    return text, PNA.not_applied("pattern absent")
  return text.replace(old, new), None


def main():
  base_text = open(SRC).read()
  base = rows_of(os.path.join(MIRROR, "runtime", "webgpu_call.bend"))
  if base is None:
    print("BASELINE DID NOT RUN -- bend's machine stack overflowed 6 times. "
          "Re-run; a 0-row result is NOT a result.")
    return 2
  print(f"baseline: {len(base)} rows, wgc-done=1")
  print()
  print("| # | edit | rows moved |")
  print("| --- | --- | --- |")
  for mid, (old, new), what in MUTATIONS:
    if old is None:
      print(f"| {mid} | a comment-only edit | 0 -- THE CONTROL |")
      continue
    mutated, why = apply_edit(base_text, old, new)
    if why:
      print(PNA.pipe([mid, why, "--"], 3))
      print(f"    {what}")
      continue
    tmp = os.path.join(MIRROR, "runtime", "webgpu_call.bend")
    backup = tmp + ".bak"
    shutil.copy(tmp, backup)
    open(tmp, "w").write(mutated)
    # THE TYPECHECK MUST RUN WHILE THE MUTATION IS IN PLACE. Running it after the
    # restore reported the BASELINE's verdict, and every mutation in the first run
    # of this table was mislabelled "DID NOT TYPECHECK" for that reason. This is
    # the harness's own `device.bend` `sig=0 4 5` mistake: a gate that agrees with
    # itself is not a gate.
    chk = subprocess.run([BEND, tmp, "--check-only"], capture_output=True, text=True, cwd=ROOT)
    failed = "SOME PROOFS FAIL" in chk.stdout + chk.stderr
    msg = ""
    if failed:
      m2 = re.search(r"- (?:message  : )?(.*)", chk.stdout)
      msg = (m2.group(1) if m2 else "typecheck failure")[:52]
    got = None if failed else rows_of(tmp)
    shutil.move(backup, tmp)
    if got is None:
      print(f"| {mid} | 0{' -- DID NOT TYPECHECK: ' + msg if failed else ' -- STACK OVERFLOW, retried 6x'} | {what} |")
      continue
    moved = sorted(k for k in set(base) | set(got) if base.get(k) != got.get(k))
    # A mutation that does not TYPECHECK is not a blind spot; say which kind it was.
    kind = " -- DID NOT TYPECHECK: " + msg if failed else ""
    print(f"| {mid} | {len(moved)}{kind} | {what}")
    if moved:
      print(f"    moved: {', '.join(m[:60] for m in moved[:8])}"
            + (f" (+{len(moved)-8} more)" if len(moved) > 8 else ""))
  return 0


sys.exit(main())