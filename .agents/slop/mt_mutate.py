#!/usr/bin/env python3
"""The mutation harness for tinybendygrad/runtime/ops_metal.bend.

    python3 .agents/slop/mt_mutate.py            # all mutations
    python3 .agents/slop/mt_mutate.py M3 M11     # a subset

One edit to a scratch copy, run the INTERPRETED lane, diff the row NAMES.  The
useful column is "rows MOVED": a mutation that moves nothing measures what the
gate does NOT see, and those are reported rather than hidden.
"""
import subprocess, sys, pathlib, shutil, re
import patch_not_apply as PNA

ROOT = pathlib.Path(__file__).resolve().parents[2]
# an optional first argument is the FILE, and it must not be mistaken for a
# mutation id -- otherwise `want` is non-empty and every mutation is skipped.
BEND = ROOT / "tinybendygrad/runtime/ops_metal.bend"
if len(sys.argv) > 1 and sys.argv[1].endswith(".bend"):
  BEND, sys.argv = pathlib.Path(sys.argv[1]), sys.argv[1:]
SCRATCH = pathlib.Path("/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode")
SCRATCH.mkdir(parents=True, exist_ok=True)
# the scratch copy lives NEXT TO THE FILE so its relative imports resolve
BASE = BEND.parent / "mt_base.bend"
MUT = BEND.parent / "mt_mut.bend"

# (id, what it is, old, new).  `old` must appear EXACTLY ONCE or the harness
# says so, because a mutation that matched the wrong place is a lie.
MUTS = [
 ("M1", "csrc_pad drops the `- n`", "U32.sub(D.round_up(U32.add(n, 1), 4), n)", "D.round_up(U32.add(n, 1), 4)"),
 ("M2", "metal_version's `>= 13` becomes `>= 14`", "Bool.pick(String, g13, \"metal3.0\", \"macos-metal2.0\")", "Bool.pick(String, g13, \"macos-metal2.0\", \"metal3.0\")"),
 ("M3", "sel_ix cannot say `no name matched`", "Bool.pick(U32, hit, at, got)", "Bool.pick(U32, Bool.not(hit), at, got)"),
 ("M4", "q.items appends the vars BEFORE the globals", "List.append(&2, U32, q.items.bufs(nbufs, Nil{}), vars)", "List.append(&2, U32, vars, q.items.bufs(nbufs, Nil{}))"),
 ("M5", "q.end's `default` is `at`, not `at + 8`", "def q.end(at: U32, +rs: List<&2, Row>) -> U32:\n  q.end.go(List.length(&2, Row, rs), at, rs, 0)", "def q.end(+at: U32, +rs: List<&2, Row>) -> U32:\n  Bool.pick(U32, U32.is_ne(U32.from_nat(List.length(&2, Row, rs)), 0), q.end.go(List.length(&2, Row, rs), at, rs, 0), at)"),
 ("M5b", "q.end's `default` is `at + 16`", "def q.end(at: U32, +rs: List<&2, Row>) -> U32:\n  q.end.go(List.length(&2, Row, rs), at, rs, 0)", "def q.end(+at: U32, +rs: List<&2, Row>) -> U32:\n  Bool.pick(U32, U32.is_ne(U32.from_nat(List.length(&2, Row, rs)), 0), q.end.go(List.length(&2, Row, rs), at, rs, 0), U32.add(at, 16))"),
 ("M6", "q.exec.off aligns to 64, not 256", "D.round_up(nbytes, ARG_ALIGN())", "D.round_up(nbytes, 64)"),
 ("M7", "run.encoder before run.cmdbuf", "  a1 = run.cmdbuf(d, r)\n  a2 = run.encoder(d, a1)\n  a3 = run.waitfence(d, a2)\n  a4 = run.use_resources.at(nores, d, a3)",
      "  a1 = run.encoder(d, r)\n  a2 = run.cmdbuf(d, a1)\n  a3 = run.waitfence(d, a2)\n  a4 = run.use_resources.at(nores, d, a3)"),
 ("M8", "run.pipeline.at is inverted", "    case True{}: run.pipeline(r, d)\n    case False{}: r", "    case False{}: run.pipeline(r, d)\n    case True{}: r"),
 ("M9", "run.execute dispatches `first`, not `count`", "    case Run{first, +count, last, n, np, zero, cbuf, val, +t}:\n      Run{first, count, last, n, np, zero, cbuf, val,\n           Tr.emit(CALL_MSGSEND, SEL_EXECUTECMDS(), count, t)}", "    case Run{+first, +count, last, n, np, zero, cbuf, val, +t}:\n      Run{first, count, last, n, np, zero, cbuf, val,\n           Tr.emit(CALL_MSGSEND, SEL_EXECUTECMDS(), first, t)}"),
 ("M10", "run.slot0 and run.slot1 swapped", "    case True{}: run.slot1(d, run.slot0(d, r))", "    case True{}: run.slot0(d, run.slot1(d, r))"),
 ("M11", "dev.apple9's `or` becomes an `and`", "  Bool.or(Bool.not(String.starts_with(arch, \"Apple\")),\n          U32.is_lt(dev.apple_num(arch), APPLE9()))", "  Bool.and(Bool.not(String.starts_with(arch, \"Apple\")),\n          U32.is_lt(dev.apple_num(arch), APPLE9()))"),
 ("M12", "runs2's FIRST run is `last`", "Run.of.t(n, np, zero, val, 0, 1, False{}, t), nores, a9, True{})", "Run.of.t(n, np, zero, val, 0, 1, True{}, t), nores, a9, True{})"),
 ("M13", "runs2 does NOT thread the trace", "  a1 = run.at(d, Run.of.t(n, np, zero, val, 0, 1, False{}, t), nores, a9, True{})\n  run.at(d, Run.of.t(n, np, zero, val, U32.sub(n, 1), 1, True{}, a1), nores, a9, True{})", "  +a1 = run.at(d, Run.of.t(n, np, zero, val, 0, 1, False{}, t), nores, a9, True{})\n  run.at(d, Run.of.t(n, np, zero, val, U32.sub(n, 1), 1, True{}, t), nores, a9, True{})"),
 ("M14", "q.submit.at's no-stamps arm builds the STAMPS path", "def q.submit.at(nostamps: Bool, many: Bool,", "def q.submit.at(+nostamps: Bool, many: Bool,"),
 ("M14b", "q.submit.at's no-stamps arm builds the STAMPS path (real)", "Bool.pick(Tr, nostamps, q.submit.nostamps(d, n, np, zero, val, nores, a9, t),", "Bool.pick(Tr, nostamps, q.submit.runs1(d, n, np, zero, val, nores, a9, t),"),
 ("M14c", "q.submit.at's many arm is selected when NOT many", "def q.submit.at(nostamps: Bool, many: Bool, +d: Dev,", "def q.submit.at(nostamps: Bool, +many: Bool, +d: Dev,"),
 ("M14e", "q.submit.at's many arm is selected when NOT many (real)", "            Bool.pick(Tr, many, q.submit.runs2(d, n, np, zero, val, nores, a9, t),", "            Bool.pick(Tr, Bool.not(many), q.submit.runs2(d, n, np, zero, val, nores, a9, t),"),
 ("M14d", "q.submit.runs2 drops its SECOND run", "  run.at(d, Run.of.t(n, np, zero, val, U32.sub(n, 1), 1, True{}, a1), nores, a9, True{})", "  a1"),
 ("M15", "Tr.emit.go drops the `raise` guard", "  Tr{Bool.pick(List<&2, Call>, refused, calls,\n               List.append(&2, Call, calls, [Call{k, sel, arg}])),\n     Bool.pick(U32, refused, next, U32.add(next, 1)), refused}", "  Tr{List.append(&2, Call, calls, [Call{k, sel, arg}]),\n     U32.add(next, 1), refused}"),
 ("M16", "Tr.has.go's fuel is the PATTERN length", "Tr.has.go(List.length(&2, Call, cs), List.length(&2, Call, pat), cs, pat, 0n)", "Tr.has.go(List.length(&2, Call, pat), List.length(&2, Call, pat), cs, pat, 0n)"),
  ("M17", "pipeline emits setComputeFunction BEFORE newFunctionWithName", '  Tr.emit(CALL_SETCOMPFUNC, sel_ix("setComputeFunction"), 0,\n          Tr.emit(CALL_NEWFUNC, sel_ix("newFunctionWithName"), 0,\n                  cns_string(t)))', '  Tr.emit(CALL_NEWFUNC, sel_ix("newFunctionWithName"), 0,\n          Tr.emit(CALL_SETCOMPFUNC, sel_ix("setComputeFunction"), 0,\n                  cns_string(t)))'),
  ("M17b", "pipeline drops the NSString as well", '  Tr.emit(CALL_SETCOMPFUNC, sel_ix("setComputeFunction"), 0,\n          Tr.emit(CALL_NEWFUNC, sel_ix("newFunctionWithName"), 0,\n                  cns_string(t)))', '  Tr.emit(CALL_SETCOMPFUNC, sel_ix("setComputeFunction"), 0,\n          Tr.emit(CALL_NEWFUNC, sel_ix("newFunctionWithName"), 0, t))'),
 ("M18", "mark_resident runs BOTH paths", "Bool.pick(Tr, dev.has_res(resid), dev.mark_resident.rs(mtl, add, t),\n                    dev.mark_resident.tab.at(sels_made, n2, t))", "Tr.emit(CALL_RS_COMMIT, sel_ix(\"commit\"), 0, dev.mark_resident.tab.at(sels_made, n2, dev.mark_resident.rs(mtl, add, t)))"),
 ("M19", "setMaxKernelBufferBindCount is 2", "def icb_binds() -> U32: KERNEL_BUF_BINDS()", "def icb_binds() -> U32: 2"),
 ("M20", "icb_max drops the `max(..., 1)`", "Bool.pick(U32, U32.is_zero(n), 1, n)", "n"),
 ("M21", "local_ok's `>` becomes `>=`", "def local_ok(prod: U32, mx: U32) -> Bool: Bool.not(U32.is_gt(prod, mx))", "def local_ok(prod: U32, mx: U32) -> Bool: Bool.not(U32.is_ge(prod, mx))"),
 ("M22", "sync_count uses round_up, not ceildiv", "ceildiv(U32.sub(size, SYNC_START()), SYNC_STEP())", "D.round_up(U32.sub(size, SYNC_START()), SYNC_STEP())"),
 ("M23", "sync_range CONSES and reverses", "  match nat:\n    case 0n: acc\n    case 1n+m: sync_range.go(m, U32.add(at, SYNC_STEP()),\n                             List.append(&2, U32, acc, [at]))", "  match nat:\n    case 0n: List.reverse(&2, U32, acc)\n    case 1n+m: sync_range.go(m, U32.add(at, SYNC_STEP()),\n                             List.append(&2, U32, acc, [at]))"),
 ("M24", "sync.one's guard is inverted", "  Bool.pick(Tr, filled, t, sync_times(start, sync_wait(t)))", "  Bool.pick(Tr, filled, sync_times(start, sync_wait(t)), t)"),
 ("M25", "the autorelease pool PUSHES before it POPS", "    case True{}: pool_push(pool_pop(t))", "    case True{}: pool_pop(pool_push(t))"),
 ("M26", "pmb_m2 requires the mtl_sel tag as well", "  Bool.and(PmbNode.par(n), Bool.and(PmbNode.named_b(n), PmbNode.icb(n)))", "  Bool.and(pmb_m0(n), Bool.and(PmbNode.named_b(n), PmbNode.icb(n)))"),
 ("M26b", "pmb_m1 requires the mtl_sel tag as well", "  Bool.and(PmbNode.par(n), Bool.and(PmbNode.slots(n), PmbNode.named_b(n)))", "  Bool.and(pmb_m0(n), Bool.and(PmbNode.slots(n), PmbNode.named_b(n)))"),
 ("M26c", "dev.pipeline.f keeps the COMPILER's magic check", "def dev.pipeline.f(pipe_ok: Bool, t: Tr) -> Tr:\n  Tr.refuse(Tr.emit(CALL_NEWPIPE,\n                    sel_ix(\"newComputePipelineStateWithDescriptor_options_reflection_error\"),\n                    0, t), pipe_ok)", "def dev.pipeline.f(pipe_ok: Bool, t: Tr) -> Tr:\n  ccompile.ok(0, 0, Tr.refuse(Tr.emit(CALL_NEWPIPE,\n                    sel_ix(\"newComputePipelineStateWithDescriptor_options_reflection_error\"),\n                    0, t), pipe_ok))"),
 ("M26d", "pmb_keep does not advance the rule index on a miss", "            PmbRun{PmbStep.ar(s), True{}, PmbStep.got(s), PmbStep.k(s)},\n            PmbRun{PmbRun.ar(r), PmbRun.made(r), PmbRun.got(r), PmbStep.k(s)})", "            PmbRun{PmbStep.ar(s), True{}, PmbStep.got(s), PmbStep.k(s)}, r)"),
 ("M26e", "icb: every command is set up BEFORE the next handle is taken", "  a5 = icb_cmds(Q.ncmds(q), a4)\n  made.at(b, icb_store(header, Q.ncmds(q), Q.npipes(q), icb_setup(q, True{}, True{}, True{}, a5)))", "  a5 = icb_setup(q, True{}, True{}, True{}, a4)\n  made.at(b, icb_store(header, Q.ncmds(q), Q.npipes(q), icb_cmds(Q.ncmds(q), a5)))"),
 ("M27", "pmb_keep is LAST-wins", "            PmbRun{PmbStep.ar(s), True{}, PmbStep.got(s), PmbStep.k(s)},\n            PmbRun{PmbRun.ar(r), PmbRun.made(r), PmbRun.got(r), PmbStep.k(s)})", "            PmbRun{PmbRun.ar(r), PmbRun.made(r), PmbRun.got(r), PmbStep.k(s)},\n            PmbRun{PmbStep.ar(s), True{}, PmbStep.got(s), PmbStep.k(s)})"),
 ("M28", "icb_hdr_word divides by 4, not 8", "def icb_hdr_word(header: U32) -> U32: U32.div(header, ADDR_SIZE())", "def icb_hdr_word(header: U32) -> U32: U32.div(header, 4)"),
 ("M29", "icb_size drops the `+ 24` header", "def icb_size(header: U32, n: U32, np: U32) -> U32:\n  U32.add(header, U32.mul(ADDR_SIZE(), U32.add(1, U32.add(n, np))))", "def icb_size(header: U32, n: U32, np: U32) -> U32:\n  U32.add(0, U32.mul(ADDR_SIZE(), U32.add(1, U32.add(n, np))))"),
 ("M30", "fam_scan is FIRST-wins, not LAST-wins", "                      Bool.pick(U32, Bool.and(String.contains(nm, f),\n                                              List.contains(U32, U32.is_eq, sup, ix)),\n                                ix, got))", "                      Bool.pick(U32, Bool.and(String.contains(nm, f),\n                                              List.contains(U32, U32.is_eq, sup, ix)),\n                                got, ix))"),
 ("M31", "arch_of drops 5 characters, not 12", "def arch_of(fam: U32) -> String: String.drop(fam_nm(fam), FAM_PREFIX())", "def arch_of(fam: U32) -> String: String.drop(fam_nm(fam), 5n)"),
 ("M32", "dev.arch.apple's `or` becomes an `and`", "def dev.arch.apple(mac: U32, +apple: U32) -> U32:\n  Bool.pick(U32, U32.is_eq(apple, 0), mac, apple)", "def dev.arch.apple(mac: U32, +apple: U32) -> U32:\n  Bool.pick(U32, U32.is_ne(apple, 0), mac, apple)"),
 ("M33", "csrc_padded is off by one", "def csrc_padded(+n: U32) -> U32: U32.add(n, csrc_pad(n))", "def csrc_padded(+n: U32) -> U32: U32.add(U32.add(n, 1), csrc_pad(n))"),
 ("M34", "hdr_pipe is `n + 2`, not `n + 1`", "def hdr_pipe(n: U32, i: U32) -> U32: U32.add(U32.add(n, HDR_PIPE()), i)", "def hdr_pipe(n: U32, i: U32) -> U32: U32.add(U32.add(n, 2), i)"),
 ("M35", "selreg starts at word 0, not word 5", "  selreg.go(List.length(&2, String, selectors()), selectors(),\n           U32.add(SELS_CNT(), 1), t)", "  selreg.go(List.length(&2, String, selectors()), selectors(), 0, t)"),
 ("M36", "q.dims reads bit i+1, not bit i", "def q.dim(m: U32, i: U32, d: U32) -> U32: Bool.pick(U32, q.sym_at(m, i), 1, d)", "def q.dim(m: U32, i: U32, d: U32) -> U32: Bool.pick(U32, q.sym_at(m, U32.add(i, 1)), 1, d)"),
 ("M37", "alloc.of asks for contents BEFORE gpuAddress", "made.at(b, alloc_contents(alloc_addr(Made.t(b))))", "made.at(b, alloc_addr(alloc_contents(Made.t(b))))"),
 ("M38", "icb_cmds retains BEFORE it indexes", "                 Tr.emit(CALL_RETAIN, sel_ix(\"retain\"), i,\n                         Tr.emit(CALL_ICBCMD, sel_ix(\"indirectComputeCommandAtIndex\"), i, t)))", "                 Tr.emit(CALL_ICBCMD, sel_ix(\"indirectComputeCommandAtIndex\"), i,\n                         Tr.emit(CALL_RETAIN, sel_ix(\"retain\"), i, t)))"),
 ("M39", "q.exec.sizes.at is unconditional", "def q.exec.sizes.at(sym: Bool, ci: U32, +q: Q) -> Q:\n  match sym:\n    case True{}: q.exec.sizes.on(ci, q, q.exec.at(Q.nbytes(q)))\n    case False{}: q", "def q.exec.sizes.at(sym: Bool, ci: U32, +q: Q) -> Q:\n  match sym:\n    case True{}: q.exec.sizes.on(ci, q, q.exec.at(Q.nbytes(q)))\n    case False{}: q.exec.sizes.on(ci, q, q.exec.at(Q.nbytes(q)))"),
 ("M40", "dev.queue_max is 512", "def QUEUE_MAX_CMDS() -> U32: 1024", "def QUEUE_MAX_CMDS() -> U32: 512"),
 ("M41", "a comment-only edit -- THE CONTROL", "# ops_metal.py:213-215 -- `check_family` and the arch string. THE TABLE IS THE\n# POINT:", "# ops_metal.py:213-215 -- `check_family` and the arch string. THE TABLE\n# IS THE POINT:"),
  ("M42", "the seam: `cc_error_ok` tests `err == 2` instead of `err == 0`", "def cc_error_ok(err: U32) -> Bool: U32.is_zero(err)", "def cc_error_ok(err: U32) -> Bool: U32.is_eq(err, CB_ERR_COMPILE())"),
  ("M43", "the seam: the error arm does NOT refuse", "    case False{}: Tr.refuse(t, False{})", "    case False{}: t"),
  ("M44", "the seam: the error arm refuses WITHOUT calling", "  ccompile.slice.at(cc_error_ok(err), head, tail, cgs_build(ibytes, cgs_create(t)))", "  ccompile.slice.at(cc_error_ok(err), head, tail, Tr.of())"),
  ("M45", "the seam: `REPLY_HDR` is 100, the header the SYNTHETIC fixtures guessed", "def REPLY_HDR() -> U32: 104", "def REPLY_HDR() -> U32: 100"),
  ("M46", "the seam: `REPLY_LEAD` is MTLB -- the two blobs confused", "def REPLY_LEAD() -> U32: 3", "def REPLY_LEAD() -> U32: 1112298573"),
  ("M47", "the seam: `CB_ERR_COMPILE` is 1", "def CB_ERR_COMPILE() -> U32: 2", "def CB_ERR_COMPILE() -> U32: 1"),
  ("M48", "the seam: `MACOS_MAJOR` is 15, so the host compiles with metal3.1", "def MACOS_MAJOR() -> U32: 26", "def MACOS_MAJOR() -> U32: 15"),
  ("M49", "the seam: the magic check drops the ENDT half", "  Tr.refuse(t, Bool.and(U32.is_eq(head, MTLB_MAGIC()), U32.is_eq(tail, ENDT_MAGIC())))", "  Tr.refuse(t, U32.is_eq(head, MTLB_MAGIC()))"),
  ("M50", "the wiring: `dev.sync.go` drops the call and keeps walking", "        case x <> t2: dev.sync.go(m, t2, filled, sync.one(x, filled, t))", "        case x <> t2: dev.sync.go(m, t2, filled, t)"),
  ("M51", "the wiring: `dev.sync_scan` misses the LAST entry", "  dev.sync.go(U32.to_nat(sync_count(size)), sync_starts(size), filled, t)", "  dev.sync.go(U32.to_nat(sync_count(U32.sub(size, 4))), sync_starts(size), filled, t)"),
  ("M52", "the wiring: `dev.sync_scan` ignores the guard", "def dev.sync_scan(+size: U32, filled: Bool, t: Tr) -> Tr:\n  dev.sync.go(U32.to_nat(sync_count(size)), sync_starts(size), filled, t)", "def dev.sync_scan(+size: U32, +filled: Bool, t: Tr) -> Tr:\n  dev.sync.go(U32.to_nat(sync_count(size)), sync_starts(size), False{}, t)"),
  ("M53", "the wiring: `icb_keep` adds ZERO -- :267 is entered and not counted", "           U32.add(nics, 1), nslot, sels_made, t}", "           U32.add(nics, 0), nslot, sels_made, t}"),
  ("M54", "the wiring: `str_list_eq` compares lengths only", "                     U32.from_nat(List.length(&2, String, b))), str_eq.go(a, b, False{}))", "                     U32.from_nat(List.length(&2, String, b))), True{})"),
  ("M54b", "the wiring: `str_list_eq` returns True unconditionally", "  Bool.and(U32.is_eq(U32.from_nat(List.length(&2, String, a)),\n                     U32.from_nat(List.length(&2, String, b))), str_eq.go(a, b, False{}))", "  True{}"),
  ("M55", "the constants: `ARG_ALIGN` is 128", "def ARG_ALIGN() -> U32: 256", "def ARG_ALIGN() -> U32: 128"),
  ("M56", "the constants: `SYNC_START` is 4", "def SYNC_START() -> U32: 5", "def SYNC_START() -> U32: 4"),
  ("M57", "the constants: `MTLB_MAGIC` is byte-swapped", "def MTLB_MAGIC() -> U32: 1112298573", "def MTLB_MAGIC() -> U32: 847821905"),
  ("M58", "the constants: `DIM_WORDS` is 3", "def DIM_WORDS() -> U32: 6", "def DIM_WORDS() -> U32: 3"),
  ("M59", "the constants: `ALL_SYMS` is 32, a NON-ALL symbolic mask", "def ALL_SYMS() -> U32: 63", "def ALL_SYMS() -> U32: 32"),
  ("M60", "the constants: `SEL_SIGNALEDVALUE` is 16", "def SEL_SIGNALEDVALUE() -> U32: 17", "def SEL_SIGNALEDVALUE() -> U32: 16"),
  ("M61", "the constants: `HDR_ICB` is 1 -- the ICB word is 0", "def HDR_ICB() -> U32: 0", "def HDR_ICB() -> U32: 1"),
]


def run_gate(path):
  r = subprocess.run([str(ROOT / "bin/bend"), str(path)], cwd=ROOT,
                     capture_output=True, text=True)
  if r.returncode != 0:
    return None, (r.stdout + r.stderr).strip().splitlines()[:3]
  return {l.split("=", 1)[0]: l.split("=", 1)[1]
          for l in r.stdout.splitlines() if "=" in l}, None


CONST = re.compile(r"^(def [A-Za-z_][A-Za-z_0-9]*\(\) -> \w+: )(-?\d+)\s*$")


def const_sweep(base_rows):
  """EVERY numeric constant def, +1, one at a time. The question is not "does this
  row move" but "IS THERE A CONSTANT WHOSE MUTATION MOVES NOTHING" -- which is the
  whole ops_nv lesson, measured over all of them at once instead of one at a time."""
  text = BASE.read_text()
  defs = [CONST.match(l) for l in text.splitlines()]
  defs = [m for m in defs if m]
  blind = []
  for m in defs:
    name, v = m.group(1).split()[1], int(m.group(2))
    MUT.write_text(text.replace(f"{m.group(1)}{m.group(2)}\n", f"{m.group(1)}{v + 1}\n"))
    got, err = run_gate(MUT)
    if got is None:
      blind.append((name, "LANE FAILS")); continue
    if not [k for k in set(base_rows) | set(got) if base_rows.get(k) != got.get(k)]:
      blind.append((name, "NOTHING"))
  print(f"\nCONSTANT SWEEP: {len(defs)} numeric constant defs, "
        f"{len(blind)} whose +1 moves NOTHING")
  for n, why in blind: print(f"  BLIND {n}: {why}")
  return blind


def main():
  # The scratch copy MUST live beside the .bend file -- `bin/bend` resolves
  # `import ../helpers.bend` relative to the SOURCE, so a copy anywhere else
  # cannot even be checked -- and it is removed on the way out so nothing is left
  # in the port tree.
  try:
    return sweep()
  finally:
    for f in (BASE, MUT):
      if f.exists():
        f.unlink()


def sweep():
  shutil.copy(BEND, BASE)
  base, err = run_gate(BASE)
  if base is None:
    print("BASE LANE FAILS", err); return 1
  args = sys.argv[1:]
  want = set(args)
  sweep_const = not args or "CONST" in args
  print(f"base gate: {len(base)} rows\n")
  print("| # | the edit | rows moved | what it is testing |")
  print("| --- | --- | --- | --- |")
  for mid, what, old, new in MUTS:
    if want and mid not in want:
      continue
    src = BASE.read_text()
    n = src.count(old)
    if n != 1:
      print(PNA.pipe([mid, what, PNA.not_applied("anchor occurs %dx" % n), ""], 4))
      continue
    MUT.write_text(src.replace(old, new))
    got, err = run_gate(MUT)
    if got is None:
      print(f"| {mid} | {what} | **LANE FAILS** {err} | |")
      continue
    moved = sorted(k for k in set(base) | set(got)
                   if base.get(k) != got.get(k))
    print(f"| {mid} | {what} | {len(moved)}{'  ' + ','.join(moved[:6]) if moved else '  -- NOTHING'} | |")
  if sweep_const:
    const_sweep(base)
  return 0


if __name__ == "__main__":
  sys.exit(main())
