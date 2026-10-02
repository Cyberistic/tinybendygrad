"""THE SPLIT. `runtime/ops_cl.bend` was ONE file for three upstream files; the 1:1
ruling made it three. Every def body moves VERBATIM -- the only edits are the ones
the split forces, and each is a `(dest, old, new)` in EDITS below, so the whole
edit list is auditable in one place.

  tinygrad/runtime/ops_cl.py   -> tinybendygrad/runtime/ops_cl.bend    (leaf)
  tinygrad/runtime/ops_cuda.py -> tinybendygrad/runtime/ops_cuda.bend  (imports CL)
  tinygrad/runtime/ops_hip.py  -> tinybendygrad/runtime/ops_hip.bend   (imports CL, CU)

THE IMPORT DAG IS WHY THE THREE-VENDOR TABLES SPLIT. bend REFUSES an import cycle
(MEASURED, "an import cycle through .../a.bend"), so `vend.cu` cannot live in
`ops_cuda.bend` AND be read by `vend.name(v, op)` in `ops_cl.bend`. The forced
consequence: the vendor dimension becomes a MODULE instead of a `U32` argument.
`vend.name(+v, +op)` becomes `vend.name(+op)` in each file, and `V_CUDA`/`V_HIP`
have nothing left to index, so they are deleted. That is 4 signatures and 3 deleted
defs, and it is why this file's 445 rows come out in a DIFFERENT ORDER.

Run:  python3 .agents/slop/cl_split.py
"""
import re, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / ".agents/slop/ops_cl-pre-split.bend"   # the ARCHIVED pre-split source
L = SRC.read_text().splitlines()


def cut(lo: int, hi: int) -> list[str]:
  """lines [lo, hi], 1-indexed inclusive.

  A scripted block move once lost 841 lines to a REVERSED range, so the range is
  checked here AND the whole move is checked at the bottom: every `def` in the
  source must appear in exactly one destination, exactly once.
  """
  assert hi >= lo >= 1, f"bad block {lo}..{hi}"
  assert hi <= len(L), f"block {lo}..{hi} runs past the {len(L)}-line file"
  out = L[lo - 1:hi]
  assert out, f"empty block {lo}..{hi}"
  return out


# --------------------------------------------------------------------------
# EDITS. Each is (dest, section-marker, old, new). `qualify` is applied per file
# AFTER the blocks are laid out, so a name only gets prefixed where it crosses a
# file boundary.
# --------------------------------------------------------------------------
EDITS: list[tuple[str, str, str, str]] = []


def edit(dest: str, why: str, old: str, new: str) -> None:
  EDITS.append((dest, why, old, new))


# --------------------------------------------------------------------------
# THE THREE DESTINATIONS.
# --------------------------------------------------------------------------
cl: list[str] = []
cu: list[str] = []
hp: list[str] = []
DST = {"cl": cl, "cu": cu, "hp": hp}


def put(dest: str, lines: list[str]) -> None:
  DST[dest].extend(lines)


# ==========================================================================
# ops_cl.bend
# ==========================================================================
put("cl", [
  "# tinybendygrad/runtime/ops_cl.bend -- port of tinygrad/runtime/ops_cl.py.",
  "#",
  "# ONE `.bend` PER UPSTREAM `.py`, AT THE SAME PATH. This file used to hold THREE",
  "# ports -- ops_cl.py, ops_cuda.py and ops_hip.py -- and the 1:1 ruling made it",
  "# three files. `ops_cuda.bend` and `ops_hip.bend` import this one; this one",
  "# imports neither, because bend has NO IMPORT CYCLE (MEASURED: \"an import",
  "# cycle through .../a.bend\"), and an acyclic graph of three files has exactly",
  "# one leaf.",
  "#",
  "# SO THE CROSS-CUTTING RATIONALE STAYS HERE AND THE THREE VENDOR TABLES DO NOT.",
  "# The header below is about all three files and is part of the reason this file",
  "# is the leaf; the tables are DATA about one file each, and a `vend.cu` in",
  "# `ops_cl.bend` is exactly the violation the ruling exists to stop. The",
  "# consequence is at THE IMPORT DAG and it is not free: `vend.name(+v, +op)`",
  "# became `vend.name(+op)` in each file, because a reader of all three tables",
  "# cannot live in any one of the three files.",
  "#",
  "# ONE DEVICE, THREE VENDOR SPELLINGS. `ops_cl.py` is the BASE CLASS for CUDA and",
  "# HIP: `CUDADevice` and `HIPDevice` are both `Compiled`, and `Program.__call__`",
  "# (device.py:372) is the one entry point all three share. So the three files are",
  "# not three backends to be compared -- they are ONE backend whose every operation",
  "# has a CL spelling, a CUDA spelling and a HIP spelling, and most of which are",
  "# NOT the same operation under a different name. `hipMalloc` is `clCreateBuffer`",
  "# is `cuMemAlloc_v2`; but `clSetKernelArg` has NO CUDA spelling at all (CUDA",
  "# packs a kernargs blob) and no HIP spelling either (HIP packs a `c_args`",
  "# struct), and `clReleaseKernel` exists in exactly ONE of the three. That table",
  "# is the content of all three files, and `vend` is it -- one table per file now.",
  "#",
  "# WHAT IS IN THIS FILE, precisely: the OpenCL port (`CLDevice`, `CLProgram`,",
  "# `CLAllocator`, `CLCompiler`, `CL_*`) and `cl_err_*` (ops_cl.py:16), plus the",
  "# port-LOCAL TRACE that all three files share -- `OP_*`, `Call`, `Tr`, `Tr.*`,",
  "# `Sig`/`Arg`/`Buf`/`Made`, `u32_dec`/`u32s`, `one_s`/`one_u`, `vend.argname`,",
  "# `cl_dev_index`, and the gate's row printers. None of that has a counterpart in",
  "# ops_cl.py alone: it is the `runtime/support/c.py` seam that all three files",
  "# import (`init_c_var`, `init_c_struct_t`, `ccall`), and it lives here because",
  "# this is the leaf of the DAG. `vend.cu`, `cu_err_*`, `Spec` and `cu.*` are in",
  "# `ops_cuda.bend`; `vend.hp`, `hp_err_of`, `timing.scale_hp` and `hp.*` are in",
  "# `ops_hip.bend`.",
  "#",
])
put("cl", cut(3, 257))                       # the rest of the header, verbatim
put("cl", cut(258, 259))                     # import Base / helpers.bend as H
put("cl", [
  "# ===========================================================================",
  "# THE IMPORT DAG, and the ONE thing the 1:1 split cost.",
  "#",
  "#   ops_cl.bend   the leaf. The OpenCL port, `cl_err_*`, and the port-local",
  "#                 trace seam (`OP_*`, `Call`, `Tr`, `Sig`, `Arg`, `Buf`,",
  "#                 `Made`, `u32_dec`, `u32s`, `one_s`, `one_u`, `vend.argname`,",
  "#                 `cl_dev_index`, the row printers).",
  "#   ops_cuda.bend imports ops_cl.bend as `CL.`",
  "#   ops_hip.bend  imports ops_cl.bend as `CL.` and ops_cuda.bend as `CU.`",
  "#",
  "# bend REFUSES an import cycle -- MEASURED, `a.bend` importing `b.bend` with",
  "# `b` importing `a` back reports \"an import cycle through .../a.bend\". So a",
  "# def that reads all THREE vendor tables cannot live in any of the three files,",
  "# and the four shared picks -- `vend.name`, `vend.count`,",
  "# `vend.checked`/`chk_count`, `vend.trace`/`vend.line` -- had to become PER",
  "# FILE. What that DELETED:",
  "#",
  "#   V_CUDA, V_HIP     nothing indexes them once the picks are per file.",
  "#   vend.name.at      the `Bool.pick` ladder over three tables.",
  "#   the `v` argument  on four signatures -- 61 `vend.trace(v, cs)` call sites,",
  "#                     20 `vend.name(v, op)`, 17 `vend.checked(v, op)`,",
  "#                     11 `chk_count(v)`, 11 `vend.count(v)`, 3 `V_*` records.",
  "#",
  "# What it ADDED: `cu.sync` in `ops_cuda.bend` -- cu:82 is CUDA's own",
  "# `cuCtxSynchronize`, and before the split CUDA called `cl.sync` because this",
  "# file was the only `OP_FINISH` emitter. Two call sites moved, and mutation M2",
  "# in `ops_cuda.bend` is what proves the ORDER of cu:80 survived it.",
  "#",
  "# WHAT IT DID NOT COST: the 445 rows. `ops_cl.bend` 229, `ops_cuda.bend` 120,",
  "# `ops_hip.bend` 96, and all 445 `name=value` LINES are byte-identical to the",
  "# pre-split snapshot. 444 of them changed POSITION, because the old `t_vend`,",
  "# `t_check` and `t_err` interleaved the three vendors row by row and one",
  "# concatenation of three programs cannot interleave -- so the gate diffs",
  "# SORTED, which is strictly stronger on VALUES, and `cl_split_rows.py` checks",
  "# that no row landed in the wrong FILE. See `.agents/slop/ops-cl-gate.sh`.",
  "#",
  "# MUTATIONS over what stayed in this file, in whole `name=value` LINES.",
  "# Reproduce with `.agents/slop/cl_split_mutate.py`.",
  "#",
  "#   M10  8 lines  `cl_err_msg`: spell the tag wrong. Moves `cl_err_0`,",
  "#               `cl_err_m1`, `cl_err_m2`, `cl_err_m3`, `cl_err_m19`,",
  "#               `cl_err_m30`, `cl_err_m72`, `cl_err_p999`.",
  "#   M12  5 lines  `cl.PITCH_ALIGN`: 256 -> 128. Moves `cl_pitch_align` and the",
  "#               four `cl_pitch_osx_*` rows.",
  "#   M13  0 lines  `Sig`: swap `h` and `w` in the TYPE DECLARATION. THEOREM, and",
  "#               M16 is its proof: in bend 2.0.34 a `Data` record's",
  "#               `type ... is Data:` field list is DOCUMENTATION, because the",
  "#               constructor and every reader bind POSITIONALLY. M16 swaps the",
  "#               same two names in `Sig.w`'s READER and moves 4 rows. So the",
  "#               field-NAME discipline this repo records lands on the READERS,",
  "#               not on the declaration -- which is where `ops_cl`'s original",
  "#               `Sig` inversion actually was.",
  "#   M15  6 lines  THE TRAP, the tc_ptx unit's exact bug class: rewrite a string",
  "#               LITERAL (`clEnqueueNDRangeKernel` -> `T.r1_NDRangeKernel`).",
  "#               THE ROW COUNT STAYS 445 and the byte diff catches it:",
  "#               `vend_names_cl`, the four `cl_call_trace*` rows, `x_launch`. A",
  "#               harness that diffed row NAMES would have reported 0. This",
  "#               file's qualifier skips string literals for exactly that reason.",
  "#   M11  0 lines  `V_CL`: 0 -> 1. A REAL BLIND SPOT, reported and not closed:",
  "#               after the split `V_CL` is DEAD. `Prog.of`'s first argument",
  "#               lands in `Prog`'s `vendor` field and NO reader reads that",
  "#               field, while `cl_prog_unit` reads `Prog.unit` -- a different",
  "#               field, which `Prog.of` sets to the literal 0. So that row",
  "#               asserts `Prog.of`'s literal and not `V_CL`, and it did so",
  "#               before the split too. Deleting `V_CL` and `Prog.vendor` is a",
  "#               real simplification but it is NOT a split; it is the owner's.",
  "# ===========================================================================",
  "",
])

put("cl", [""])
put("cl", cut(261, 271))                     # PART 0 comment + V_CL
put("cl", cut(274, 314))                     # OP_NONE .. OP_N
put("cl", [""])
put("cl", cut(316, 331))                     # vend.cl
put("cl", [""])
put("cl", cut(350, 369))                     # vend.argname, one_s, one_u
put("cl", cut(371, 372))                     # vend.cl.of
put("cl", [
  "# `vend.name` is now PER FILE and the vendor tag is gone. It used to be",
  "# `vend.name(+v, +op)`, a three-way choice, as two Bool.picks -- the old",
  "# comment read:",
  "#",
  "#   # the three-way choice, as two Bool.picks: a `U32` ladder over tags that are not",
  "#   # 0/1/n is refused outright (\"a declared constructor (unknown: U32)\"), and",
  "#   # bend2-constraints rule 34 at line 4982 is the note on it.",
  "#",
  "# -- all three tables were in this one file. The 1:1 split puts `vend.cu` in",
  "# `ops_cuda.bend` and `vend.hp` in `ops_hip.bend`, and bend has no import",
  "# cycle for a shared reader (MEASURED), so the ladder cannot exist and",
  "# the three `vend.name` defs are one line each.",
  "def vend.name(+op: U32) -> String: vend.cl.of(op)",
])
put("cl", [""])
put("cl", cut(389, 398))                     # vend.count.at, unchanged
put("cl", [""])
put("cl", ["# the per-file `vend.count`, and the `v` argument is gone with the ladder.",
           "def vend.count() -> U32: vend.count.at(vend.cl())"])

put("cl", [""])
put("cl", cut(404, 421))                     # THE CHECK TABLE comment
put("cl", [""])
put("cl", cut(423, 423))                     # cl_unchecked
put("cl", [""])
put("cl", cut(430, 430))                     # is_unchecked
put("cl", [""])
put("cl", cut(432, 443))                     # cl_probe/info/build_log_checked
put("cl", [
  "def vend.checked(+op: U32) -> Bool: Bool.not(is_unchecked(cl_unchecked(), op))",
  "",
  "# how many of the 39 ops each vendor CHECKS. CL checks all 39 at the op level,",
  "# CUDA 33 and HIP 38, and those three numbers are the compact form of the table.",
  "# A `U32` HAS NO CONSTRUCTORS, so the walk counts in `Nat` and carries the op",
  "# index as a `+U32` that grows from zero (bend2-constraints rule 34, line 4982).",
  "def chk_count.at(n: Nat, +op: U32) -> U32:",
  "  match n:",
  "    case 0n: 0",
  "    case 1n+m: U32.add(Bool.to_u32(vend.checked(op)), chk_count.at(m, U32.add(op, 1)))",
  "",
  "def chk_count() -> U32: chk_count.at(U32.to_nat(OP_N()), 0)",
])

put("cl", [""])
put("cl", cut(461, 505))                     # the integer printer
put("cl", [""])
put("cl", cut(507, 511))                     # THE ERROR TABLES comment
put("cl", [""])
put("cl", cut(513, 597))                     # cl_err_code .. cl_err_msg

put("cl", [""])
put("cl", cut(701, 726))                     # THE TYPES comment, Call, Tr
put("cl", [""])
put("cl", cut(728, 750))                     # Sig, Arg, Buf, Made
put("cl", [""])
put("cl", cut(758, 825))                     # the readers, through Made.tr
put("cl", [""])
put("cl", cut(841, 994))                     # THE TRACE + THE RAISE, Tr.* queries
put("cl", cut(994, 999))                     # the fold-order rationale, VERBATIM
put("cl", [
  "# `vend.trace` reads a trace BACK as C symbols, and it is per file for the",
  "# same reason `vend.name` is: the table it indexes is this file's.",
  "def vend.line(+c: Call) -> String:",
  "  String.concat([vend.name(Call.op(c)), \"(\", Call.arg(c), \")\"])",
  "",
  "def vend.trace.put(c: Call, +acc: List<&2, String>) -> List<&2, String>:",
  "  List.append(&2, String, acc, [vend.line(c)])",
  "",
  "def vend.trace.go(cs: List<&2, Call>, +acc: List<&2, String>) -> List<&2, String>:",
  "  match cs:",
  "    case Nil{}: acc",
  "    case c <> t: vend.trace.go(t, vend.trace.put(c, acc))",
  "",
  "def vend.trace(cs: List<&2, Call>) -> String:",
  "  String.join(vend.trace.go(cs, Nil{}), \" \")",
])

put("cl", [""])
put("cl", cut(1014, 1754))                   # PART 1 -- OpenCL, through timing.scale
put("cl", [""])
# 1755-1757 is `timing.scale_hp`'s COMMENT and 1760-1762 is `arg.str`'s; the
# first moves to `ops_hip.bend` WITH its def and the second stays here.
# pre-split line 1776 has the next section marker GLUED onto the def. The def is
# the content; the marker opens PART 2 and now opens `ops_cuda.bend` instead.
assert L[1775] == 'def arg.strs(+xs: List<&2, Arg>) -> String: String.join(arg.strs.go(xs, Nil{}), " ")# ===========================================================================', L[1775]
put("cl", cut(1760, 1775))                   # arg.str
put("cl", ['def arg.strs(+xs: List<&2, Arg>) -> String: String.join(arg.strs.go(xs, Nil{}), " ")'])

# ---- the gate, CL's half
put("cl", [""])
put("cl", cut(2444, 2482))                   # THE GATE comment + the row printers
put("cl", [
  "# --- 1: the vendor table, the CL column ---------------------------------",
  "def t_vend() -> IO(Unit):",
  "  do IO<Unit>:",
  "    urow(\"vend_count_cl\", vend.count())",
  "    srowlist(\"vend_names_cl\", vend.cl())",
  "    urow(\"vend_len_cl\", U32.from_nat(List.length(&2, String, vend.cl())))",
  "    srow(\"vend_alloc_cl\", vend.name(OP_ALLOC()))",
  "    srow(\"vend_setarg_cl\", vend.name(OP_SET_ARG()))",
  "    srow(\"vend_relkernel_cl\", vend.name(OP_RELEASE_KERNEL()))",
  "    srow(\"vend_relprg_cl\", vend.name(OP_RELEASE_PRG()))",
  "    srow(\"vend_initext_cl\", vend.name(OP_INIT()))",
  "    srow(\"vend_none_cl\", vend.name(OP_NONE()))",
  "    srow(\"vend_oob\", vend.name(39))",
  "    # the two ARGUMENT-COLUMN rows and the table width are not per vendor:",
  "    # `vend.argname` is the trace's one `arg` column and `OP_N` is the width",
  "    # all three tables are asserted against, so they live with the first file.",
  "    srowlist(\"vend_argnames\", vend.argname())",
  "    urow(\"vend_len_argnames\", U32.from_nat(List.length(&2, String, vend.argname())))",
  "    urow(\"vend_op_n\", OP_N())",
  "",
  "# --- 2: the check table, cl:98/105/114 ----------------------------------",
  "def t_check() -> IO(Unit):",
  "  do IO<Unit>:",
  "    urow(\"vend_nchecked_cl\", chk_count())",
  "    urow(\"cl_unchecked_n\", U32.from_nat(List.length(&2, U32, cl_unchecked())))",
  "    brow(\"chk_cl_alloc\", vend.checked(OP_ALLOC()))",
  "    brow(\"cl_probe_checked\", cl_probe_checked())",
  "    brow(\"cl_info_checked\", cl_info_checked())",
  "    brow(\"cl_build_log_checked\", cl_build_log_checked())",
  "",
  "# --- 3: the error table, cl:16 ------------------------------------------",
  "def t_err() -> IO(Unit):",
  "  do IO<Unit>:",
  "    urow(\"cl_err_n\", cl_err_n())",
  "    urow(\"cl_err_aliases\", cl_err_aliases())",
  "    srow(\"cl_err_0\", cl_err_msg(0))",
  "    srow(\"cl_err_m1\", cl_err_msg(4294967295))",
  "    srow(\"cl_err_m2\", cl_err_msg(4294967294))",
  "    srow(\"cl_err_m3\", cl_err_msg(4294967293))",
  "    srow(\"cl_err_m19\", cl_err_msg(4294967277))",
  "    srow(\"cl_err_m30\", cl_err_msg(4294967266))",
  "    srow(\"cl_err_m72\", cl_err_msg(4294967224))",
  "    srow(\"cl_err_p999\", cl_err_msg(999))",
  "    # the four ALIASED codes -- 0, -1, -2 and -3 carry 9, 2, 2 and 2 names -- and",
  "    # the comprehension keeps the LAST one, so these four rows are what pins WHICH",
  "    # name survives. Without them `cl_err_step`'s \"first hit wins\" guard is",
  "    # invisible: MEASURED, dropping it moved nothing until these four rows existed.",
  "    srow(\"cl_err_alias_m3\", cl_err_of(4294967293))",
  "    srow(\"cl_err_alias_m2\", cl_err_of(4294967294))",
  "    srow(\"cl_err_alias_m1\", cl_err_of(4294967295))",
  "    srow(\"cl_err_alias_0\", cl_err_of(0))",
  "",
])
assert L[2605].strip() == 'urow("timing_hp_scale_bits", F32.bits(timing.scale_hp()))', L[2606]
put("cl", cut(2575, 2605))                   # t_print, WITHOUT the hp factor row
put("cl", [""])
put("cl", cut(2608, 2870))                   # t_clinit .. t_clalloc, t_refuse
put("cl", [""])
put("cl", [
  "def main() -> IO(Unit):",
  "  do IO<Unit>:",
  "    a : Unit <- t_vend()",
  "    b : Unit <- t_check()",
  "    c : Unit <- t_err()",
  "    d : Unit <- t_print()",
  "    e : Unit <- t_clinit()",
  "    f : Unit <- t_climg()",
  "    g : Unit <- t_clprog()",
  "    h : Unit <- t_clcall()",
  "    i : Unit <- t_clalloc()",
  "    j : Unit <- t_refuse()",
  "    IO.print(\"cl-done=1\")",
  "",
])

# ==========================================================================
# ops_cuda.bend
# ==========================================================================
put("cu", [
  "# tinybendygrad/runtime/ops_cuda.bend -- port of tinygrad/runtime/ops_cuda.py.",
  "#",
  "# ONE `.bend` PER UPSTREAM `.py`, AT THE SAME PATH. This file was 707 lines of",
  "# `runtime/ops_cl.bend` until the 1:1 ruling; it now holds ONLY what",
  "# ops_cuda.py says, plus its half of the gate. The shared trace -- `OP_*`,",
  "# `Tr`, `Tr.*`, `vend.argname`, `u32s`, `one_s`, the row printers -- is imported",
  "# from `ops_cl.bend` as `CL.`, which is the DAG's only edge in one direction.",
  "#",
  "# WHAT IS HERE: `CU_*` (autogen/cuda.py), the CUDA column of the vendor table",
  "# `vend.cu`, `cu_unchecked` (cu:17-18), `cu_err_*` (cu:18), `Spec` (device.py:89)",
  "# and `CUDA_HOST_REGISTERED` (cu:90), `cu_handle_words`/`cu_handles_tail`/",
  "# `cu_nstreams` (cu:119/109/120), `cu.*` and `CuDev`.",
  "#",
])
put("cu", cut(1777, 1784))                   # PART 2 -- CUDA comment
put("cu", [""])
# the CUDA-owned pieces of the substrate
put("cu", [
  "# --- the CUDA vendor vocabulary, read straight off ops_cuda.py -----------",
  "#",
  "# The three lists are the SAME 39 indices and the oracle asserts the three",
  "# lengths. \"\" is MEASURED absence, not an omission: `cuDeviceGetCount` has no",
  "# op of its own because `count()` at cu:132 calls it under `OP_GET_DEVICE_COUNT`",
  "# and `cuDeviceGet` is the `get_device_properties` at cu:110.",
  "def vend.cu() -> List<&2, String>:",
  "  [\"\", \"\", \"cuDeviceGet\", \"cuDeviceGetCount\", \"\", \"\", \"cuInit\", \"cuCtxCreate_v2\",",
  "   \"cuCtxSetCurrent\", \"cuStreamCreate\", \"\", \"cuModuleLoadData\", \"\", \"\", \"\",",
  "   \"cuModuleGetFunction\", \"\", \"\", \"\", \"cuMemAlloc_v2\", \"cuMemHostAlloc\",",
  "   \"cuMemFree_v2\", \"cuMemFreeHost\", \"cuMemHostRegister_v2\", \"cuMemHostUnregister\",",
  "   \"cuMemcpyAsync\", \"cuMemcpyAsync\", \"cuCtxSynchronize\", \"\", \"\", \"cuLaunchKernel\",",
  "   \"\", \"\", \"\", \"cuStreamWriteValue64_v2\", \"cuStreamWaitValue64_v2\",",
  "   \"cuLaunchHostFunc\", \"cuDeviceComputeCapability\", \"\"]",
  "",
  "def vend.cu.of(+op: U32) -> String: CL.one_s(List.get(&2, String, vend.cu(), U32.to_nat(op)))",
  "",
  "def vend.name(+op: U32) -> String: vend.cu.of(op)",
  "",
  "def vend.count() -> U32: CL.vend.count.at(vend.cu())",
  "",
  "# cu:17-18 -- every call in `CUDAQueue` goes through `hcq2.ccall`, whose answer is",
  "# `UOp.custom_function(fn.__name__).call(...)`, so there is no status to check.",
  "# SIX ops, and the largest unchecked set of the three.",
  "def cu_unchecked() -> List<&2, U32>:",
  "  [CL.OP_CTX_SET, CL.OP_LAUNCH, CL.OP_COPY_IN, CL.OP_SIGNAL, CL.OP_WAIT_VALUE, CL.OP_HOST_FUNC]",
  "",
  "def vend.checked(+op: U32) -> Bool: Bool.not(CL.is_unchecked(cu_unchecked(), op))",
  "",
  "def chk_count.at(n: Nat, +op: U32) -> U32:",
  "  match n:",
  "    case 0n: 0",
  "    case 1n+m: U32.add(Bool.to_u32(vend.checked(op)), chk_count.at(m, U32.add(op, 1)))",
  "",
  "def chk_count() -> U32: chk_count.at(U32.to_nat(CL.OP_N()), 0)",
  "",
  "# cu:18 `cuda.enum_cudaError_enum`, MEASURED: 92 entries, keyed int -> str, and",
  "# NOT ONE of them is negative -- so `u32s` is a no-op for every CUDA status and",
  "# that asymmetry with the OpenCL table is itself a row.",
])
put("cu", cut(599, 689))                     # cu_err_code .. CUDA_SUCCESS
put("cu", [""])
put("cu", cut(691, 695))                     # cu_handle_words, cu_handles_tail, cu_nstreams
put("cu", [""])
put("cu", [
  "# device.py:89 `BufferSpec`, and only the three fields the three allocators read.",
  "# `host` and `cpu` are cu:75's `options.host or options.cpu_access`, which is ONE",
  "# test in Python and two in the record, and `ext` is `options.external_ptr`.",
  "# PORT-LOCAL CORRECTION to the pre-split comment, which said \"the three",
  "# allocators\": only `CUDADevice._alloc` and `._map` read it. `CLAllocator` and",
  "# `HIPAllocator` take a bare byte count in ops_cl.py and ops_hip.py.",
  "type Spec is Data:",
  "  Spec{host: Bool, cpu: Bool, ext: U32}",
  "",
  "def Spec.host(+s: Spec) -> Bool:",
  "  match s:",
  "    case Spec{host, cpu, ext}: host",
  "",
  "def Spec.cpu(+s: Spec) -> Bool:",
  "  match s:",
  "    case Spec{host, cpu, ext}: cpu",
  "",
  "def Spec.ext(+s: Spec) -> U32:",
  "  match s:",
  "    case Spec{host, cpu, ext}: ext",
  "",
  "def Spec.of(host: Bool, cpu: Bool, ext: U32) -> Spec: Spec{host, cpu, ext}",
  "",
  "# cu:82 `cuCtxSynchronize()`. It USED to be `cl.sync`, because before the split",
  "# `cl.sync` was the file's only `OP_FINISH` emitter and the trace carries the OP,",
  "# not the vendor; the split makes CUDA answer for its own synchronize.",
  "def cu.sync(+t: CL.Tr) -> CL.Tr: CL.Tr.emit(CL.OP_FINISH(), \"0\", t)",
  "",
  "def vend.line(+c: CL.Call) -> String:",
  "  String.concat([vend.name(CL.Call.op(c)), \"(\", CL.Call.arg(c), \")\"])",
  "",
  "def vend.trace.put(c: CL.Call, +acc: List<&2, String>) -> List<&2, String>:",
  "  List.append(&2, String, acc, [vend.line(c)])",
  "",
  "def vend.trace.go(cs: List<&2, CL.Call>, +acc: List<&2, String>) -> List<&2, String>:",
  "  match cs:",
  "    case Nil{}: acc",
  "    case c <> t: vend.trace.go(t, vend.trace.put(c, acc))",
  "",
  "def vend.trace(cs: List<&2, CL.Call>) -> String:",
  "  String.join(vend.trace.go(cs, Nil{}), \" \")",
  "",
  "# hp:10 has the same shape for HIP and lives in `ops_hip.bend`.",
])
put("cu", [""])
put("cu", cut(1786, 2151))                   # the CUDA body -- LAST, because bend
                                          # requires a def to be defined above every
                                          # user: "expected a filled definition (an
                                          # unfilled law is a dead claim)" is what a
                                          # forward reference reports.
# the CUDA half of the gate
put("cu", [
  "# --- the CUDA column of the three-vendor tables --------------------------",
  "def t_vend() -> IO(Unit):",
  "  do IO<Unit>:",
  "    urow(\"vend_count_cuda\", vend.count())",
  "    srowlist(\"vend_names_cu\", vend.cu())",
  "    urow(\"vend_len_cu\", U32.from_nat(List.length(&2, String, vend.cu())))",
  "    srow(\"vend_alloc_cu\", vend.name(CL.OP_ALLOC()))",
  "    srow(\"vend_setarg_cu\", vend.name(CL.OP_SET_ARG()))",
  "    srow(\"vend_relkernel_cu\", vend.name(CL.OP_RELEASE_KERNEL()))",
  "    srow(\"vend_relprg_cu\", vend.name(CL.OP_RELEASE_PRG()))",
  "    srow(\"vend_initext_cu\", vend.name(CL.OP_INIT()))",
  "    srow(\"vend_none_cu\", vend.name(CL.OP_NONE()))",
  "",
  "def t_check() -> IO(Unit):",
  "  do IO<Unit>:",
  "    urow(\"vend_nchecked_cu\", chk_count())",
  "    urow(\"cu_unchecked_n\", U32.from_nat(List.length(&2, U32, cu_unchecked())))",
  "    lrow(\"cu_unchecked_ops\", cu_unchecked())",
  "    brow(\"chk_cu_launch\", vend.checked(CL.OP_LAUNCH()))",
  "    brow(\"chk_cu_ctxset\", vend.checked(CL.OP_CTX_SET()))",
  "    brow(\"chk_cu_alloc\", vend.checked(CL.OP_ALLOC()))",
  "",
  "def t_err() -> IO(Unit):",
  "  do IO<Unit>:",
  "    urow(\"cu_err_n\", cu_err_n())",
  "    srow(\"cu_err_0\", cu_err_msg(0))",
  "    srow(\"cu_err_1\", cu_err_msg(1))",
  "    srow(\"cu_err_712\", cu_err_msg(712))",
  "    srow(\"cu_err_777\", cu_err_msg(777))",
  "    srow(\"cu_err_999\", cu_err_msg(999))",
  "    # cu:18's f-string has a DEFAULT, so `cu_err_777` is the row that pins it.",
  "    urow(\"cu_host_registered\", CUDA_HOST_REGISTERED())",
  "    urow(\"cu_success\", CUDA_SUCCESS())",
  "",
])
put("cu", cut(2871, 2874))                   # PART 4 -- CUDA comment
put("cu", cut(2875, 2879))                   # CUDEV0, CUDEV1, fx_cu
put("cu", cut(2880, 2997))                   # t_cuinit, t_cuqueue, t_cualloc
put("cu", [
  "def main() -> IO(Unit):",
  "  do IO<Unit>:",
  "    a : Unit <- t_vend()",
  "    b : Unit <- t_check()",
  "    c : Unit <- t_err()",
  "    d : Unit <- t_cuinit()",
  "    e : Unit <- t_cuqueue()",
  "    # NO trailing print: the pre-split file emitted ONE `cl-done=1` sentinel and",
  "    # the pre-split snapshot has exactly one, so `ops_cl.bend` still owns it.",
  "    # A `do IO<Unit>` block's last line is the block's RESULT, so the last test",
  "    # is CALLED there rather than bound (bend2-constraints: `ops_cpu.bend` does",
  "    # the same).",
  "    t_cualloc()",
  "",
])

put("cu", [
  "# ===========================================================================",
  "# THE SPLIT, MEASURED. 120 of the pre-split file's 445 rows are here, and every",
  "# one is byte-identical to the pre-split snapshot. The 22 `x_*` cross-vendor",
  "# rows are NOT: they are in `ops_hip.bend`, for the DAG reason in this file's",
  "# header.",
  "#",
  "# MUTATIONS, over what moved into THIS file. Each is applied to a scratch copy",
  "# and reverted; each is counted in whole `name=value` LINES.",
  "#",
  "#   M1   7 lines   `vend.cu`: swap cells 19 and 20 (`cuMemAlloc_v2` /",
  "#                `cuMemHostAlloc`). Moves `vend_names_cu`, `vend_alloc_cu`,",
  "#                `cu_alloc_dev`, `cu_alloc_host`, `cu_alloc_cpu`, `x_alloc`,",
  "#                `x_alloc_host` -- so the CUDA spelling is load-bearing.",
  "#   M2   4 lines   `cu.free.at`: drop the `cuCtxSynchronize` before the free.",
  "#                Moves `cu_free_dev`, `cu_free_host`, `cu_free_cpu`,",
  "#                `x_free_cu`. This is the mutation that proves the split's",
  "#                forced `cu.sync` edit preserved cu:80's ORDER.",
  "#   M3   0 lines   `Spec`: swap `host` and `cpu` in the TYPE DECLARATION.",
  "#                THEOREM -- the same one as `ops_cl.bend`'s M13, and the reason",
  "#                it is worth writing down: in bend 2.0.34 a `Data` record's",
  "#                declaration is documentation because every constructor and",
  "#                reader binds POSITIONALLY.",
  "#   M4   3 lines   `cu.kernarg_extra`: drop the 40-byte descriptor offset.",
  "#                Moves `cu_extra_fresh`, `cu_extra_44`, `cu_extra_84`.",
  "#   M17  0 lines   `Spec.of`: swap the `host` and `cpu` ARGUMENTS. THEOREM, and",
  "#                a PROVABLE one: the only reader is `spec.is_host(s)` =",
  "#                `Bool.or(Spec.host(s), Spec.cpu(s))`, which is SYMMETRIC in",
  "#                its two arguments, so swapping them is the same function over",
  "#                every reachable `Spec` and no fixture can separate them. The",
  "#                consequence is a LOC observation, not a bug: upstream cu:75 is",
  "#                ONE test (`options.host or options.cpu_access`), so `Spec`'s",
  "#                two `Bool` fields could be one.",
  "# ===========================================================================",
  "",
])

# ==========================================================================
# ops_hip.bend
# ==========================================================================
put("hp", [
  "# tinybendygrad/runtime/ops_hip.bend -- port of tinygrad/runtime/ops_hip.py.",
  "#",
  "# ONE `.bend` PER UPSTREAM `.py`, AT THE SAME PATH. This file was 290 lines of",
  "# `runtime/ops_cl.bend` until the 1:1 ruling. It imports `ops_cl.bend` as `CL.`",
  "# (the shared trace) and `ops_cuda.bend` as `CU.`, and imports neither of them",
  "# back: bend has NO IMPORT CYCLE (MEASURED).",
  "#",
  "# WHY THIS FILE HOLDS THE CROSS-VENDOR GATE, and that is a MEASUREMENT and not a",
  "# preference. `t_cross` is 22 rows that read all three vendors. A reader of",
  "# three files must live in a file that can import all three, and the only such",
  "# file in an acyclic three-file graph is the LAST one -- so `t_cross` and the",
  "# three-vendor columns of `t_vend`/`t_check`/`t_err` live here. A reader asking",
  "# \"what does HIP call that CUDA spells differently\" finds the whole answer in",
  "# one file instead of three.",
  "#",
  "# WHAT IS HERE: `HP_*`, the HIP column of the vendor table `vend.hp`,",
  "# `hp_unchecked` (hp:16), `hp_err_of` (hp:10), `timing.scale_hp` (hp:57's",
  "# `ret.value * 1e-3`), `iter_sig` (TinyELF.iter_sig, device.py:365), `hp.*` and",
  "# `HpDev`.",
  "#",
])
put("hp", cut(2154, 2161))                   # PART 3 -- HIP comment
# the last line of PART 3 has the next section marker GLUED onto it, because the
# marker follows the body on the same physical line. `hp_offset_sum` is the def and
# the marker is not, so the marker is dropped here.
assert L[2442].startswith("def hp_offset_sum(buf: U32, offset: U32) -> U32: U32.add(buf, offset)#"), L[2442]
put("hp", ["def hp_offset_sum(buf: U32, offset: U32) -> U32: U32.add(buf, offset)"])
put("hp", [""])
put("hp", [
  "# hp:57 `ret.value * 1e-3` -- the ms->s divisor, and it is a THIRD scale: the three",
  "# vendors do not agree on a unit, and `timing_ns_scale_bits` beside",
  "# `timing_hp_scale_bits` is the row that says so. `timing.scale` beside it is",
  "# cl:75's nanosecond divisor and lives in `ops_cl.bend`.",
  "def timing.scale_hp() -> F32: 0.001",
  "",
  "# --- the HIP vendor vocabulary, read straight off ops_hip.py --------------",
  "def vend.hp() -> List<&2, String>:",
  "  [\"\", \"hipSetDevice\", \"\", \"hipGetDeviceCount\", \"\", \"hipGetDeviceProperties\", \"\", \"\",",
  "   \"\", \"hipEventCreate\", \"\", \"hipModuleLoadData\", \"\", \"\", \"\",",
  "   \"hipModuleGetFunction\", \"\", \"hipModuleUnload\", \"\", \"hipMalloc\", \"\", \"hipFree\",",
  "   \"\", \"\", \"\", \"hipMemcpy\", \"hipMemcpy\", \"hipDeviceSynchronize\", \"\", \"\",",
  "   \"hipModuleLaunchKernel\", \"hipEventSynchronize\", \"hipEventRecord\",",
  "   \"hipEventElapsedTime\", \"\", \"\", \"\", \"\", \"hipGetErrorString\"]",
  "",
  "def vend.hp.of(+op: U32) -> String: CL.one_s(List.get(&2, String, vend.hp(), U32.to_nat(op)))",
  "",
  "def vend.name(+op: U32) -> String: vend.hp.of(op)",
  "",
  "def vend.count() -> U32: CL.vend.count.at(vend.hp())",
  "",
  "# hp:16 `hipEventCreate` is the only `hip*` call in the file with no `check`",
  "# around it, and it is the only op the HIP column does not check.",
  "def hp_unchecked() -> List<&2, U32>: [CL.OP_QUEUE_CREATE]",
  "",
  "def vend.checked(+op: U32) -> Bool: Bool.not(CL.is_unchecked(hp_unchecked(), op))",
  "",
  "def chk_count.at(n: Nat, +op: U32) -> U32:",
  "  match n:",
  "    case 0n: 0",
  "    case 1n+m: U32.add(Bool.to_u32(vend.checked(op)), chk_count.at(m, U32.add(op, 1)))",
  "",
  "def chk_count() -> U32: chk_count.at(U32.to_nat(CL.OP_N()), 0)",
  "",
  "# hp:10 -- the FUNCTION name is a symbol and is ported; the TEXT it returns is",
  "# WALL 7. `hp_err_of` answers the prefix and the tail is the seam's.",
  "def hp_err_of(status: U32) -> String: String.concat([\"HIP Error \", CL.u32s(status), \", \"])",
  "",
  "def vend.line(+c: CL.Call) -> String:",
  "  String.concat([vend.name(CL.Call.op(c)), \"(\", CL.Call.arg(c), \")\"])",
  "",
  "def vend.trace.put(c: CL.Call, +acc: List<&2, String>) -> List<&2, String>:",
  "  List.append(&2, String, acc, [vend.line(c)])",
  "",
  "def vend.trace.go(cs: List<&2, CL.Call>, +acc: List<&2, String>) -> List<&2, String>:",
  "  match cs:",
  "    case Nil{}: acc",
  "    case c <> t: vend.trace.go(t, vend.trace.put(c, acc))",
  "",
  "def vend.trace(cs: List<&2, CL.Call>) -> String:",
  "  String.join(vend.trace.go(cs, Nil{}), \" \")",
  "",
])
put("hp", [""])
put("hp", cut(2162, 2442))                   # the HIP body -- LAST, see ops_cuda
# the HIP half of the gate
put("hp", [
  "# --- the HIP column of the three-vendor tables ---------------------------",
  "def t_vend() -> IO(Unit):",
  "  do IO<Unit>:",
  "    urow(\"vend_count_hip\", vend.count())",
  "    srowlist(\"vend_names_hp\", vend.hp())",
  "    urow(\"vend_len_hp\", U32.from_nat(List.length(&2, String, vend.hp())))",
  "    srow(\"vend_alloc_hp\", vend.name(CL.OP_ALLOC()))",
  "    srow(\"vend_setarg_hp\", vend.name(CL.OP_SET_ARG()))",
  "    srow(\"vend_relkernel_hp\", vend.name(CL.OP_RELEASE_KERNEL()))",
  "    srow(\"vend_relprg_hp\", vend.name(CL.OP_RELEASE_PRG()))",
  "    srow(\"vend_initext_hp\", vend.name(CL.OP_INIT()))",
  "    srow(\"vend_errstr_hp\", vend.name(CL.OP_ERRSTR()))",
  "",
  "def t_check() -> IO(Unit):",
  "  do IO<Unit>:",
  "    urow(\"vend_nchecked_hp\", chk_count())",
  "    urow(\"hp_unchecked_n\", U32.from_nat(List.length(&2, U32, hp_unchecked())))",
  "    lrow(\"hp_unchecked_ops\", hp_unchecked())",
  "    brow(\"chk_hp_queue\", vend.checked(CL.OP_QUEUE_CREATE()))",
  "    brow(\"chk_hp_launch\", vend.checked(CL.OP_LAUNCH()))",
  "",
  "def t_err() -> IO(Unit):",
  "  do IO<Unit>:",
  "    srow(\"hp_err_0\", hp_err_of(0))",
  "    srow(\"hp_err_1\", hp_err_of(1))",
  "    srow(\"hp_err_999\", hp_err_of(999))",
  "",
  "# hp:57's `ret.value * 1e-3`. It is the HIP file's own timing factor and its",
  "# sibling `timing.scale` is cl:75's nanosecond divisor in `ops_cl.bend`, so the",
  "# row follows the factor: the row was in `ops_cl.bend`'s `t_print` before the",
  "# split and no longer is.",
  "def t_hptiming() -> IO(Unit):",
  "  do IO<Unit>:",
  "    urow(\"timing_hp_scale_bits\", F32.bits(timing.scale_hp()))",
  "",
])
put("hp", cut(2998, 3036))                   # PART 5 -- HIP comment + fixtures + tests
put("hp", cut(3037, 3072))                   # t_hpargs
put("hp", cut(3073, 3127))                   # t_cross
put("hp", [
  "def main() -> IO(Unit):",
  "  do IO<Unit>:",
  "    a : Unit <- t_vend()",
  "    b : Unit <- t_check()",
  "    c : Unit <- t_err()",
  "    d : Unit <- t_hptiming()",
  "    e : Unit <- t_hpinit()",
  "    f : Unit <- t_hpargs()",
  "    # NO trailing print: see the note in `ops_cuda.bend`'s main.",
  "    t_cross()",
  "",
])

put("hp", [
  "# ===========================================================================",
  "# THE SPLIT, MEASURED. 96 of the pre-split file's 445 rows are here, all of them",
  "# byte-identical to the pre-split snapshot: the HIP column of",
  "# `t_vend`/`t_check`/`t_err`, `t_hpinit`, `t_hpargs`, `timing_hp_scale_bits`,",
  "# and the 22 `x_*` cross-vendor rows.",
  "#",
  "# MUTATIONS, over what moved into THIS file. Reproduce with",
  "# `.agents/slop/cl_split_mutate.py`.",
  "#",
  "#   M5   4 lines   `vend.hp`: typo a symbol (`hipMalloc` -> `hipMallocX`).",
  "#                Moves `vend_names_hp`, `vend_alloc_hp`, `hp_alloc_trace`,",
  "#                `x_alloc`.",
  "#   M6   3 lines   `hp_err_of`: change the message prefix. Moves `hp_err_0`,",
  "#                `hp_err_1`, `hp_err_999`.",
  "#   M7   2 lines   `vend.checked`: forget `hp_unchecked` (say `hipEventCreate`",
  "#                IS checked). Moves `vend_nchecked_hp`, `chk_hp_queue`. NOT",
  "#                `chk_hp_launch`: `hipModuleLaunchKernel` is checked under both",
  "#                readings, so that row is a CONSTANT against this mutation and",
  "#                not a witness for it.",
  "#   M8   1 line    `timing.scale_hp`: hp:57's `1e-3` -> `1e-2`. Moves",
  "#                `timing_hp_scale_bits` -- the one row that followed the factor",
  "#                out of `ops_cl.bend`'s `t_print`.",
  "#   M9   1 line    `t_cross`: swap the second and third cells of `x_launch`.",
  "#                Moves `x_launch` and nothing else, which is what a row that",
  "#                JOINS three spellings is supposed to do.",
  "#   M14  5 lines   THE TRAP, the tc_ptx unit's exact bug class: rewrite a string",
  "#                LITERAL (`hipModuleLaunchKernel` -> `T.r1_ModuleLaunchKernel`).",
  "#                THE ROW COUNT STAYS 445 and the byte diff catches it:",
  "#                `vend_names_hp`, `hp_call_first_trace`, `hp_call_wait_trace`,",
  "#                `hp_call_second_trace`, `x_launch`. A harness that diffed row",
  "#                NAMES would have reported 0.",
  "# ===========================================================================",
  "",
])

# --------------------------------------------------------------------------
# THE VENDOR TAG AT THE `vend.trace` CALL SITES. `vend.trace(+v, cs)` is now
# `vend.trace(cs)`, so the `V_*` first argument goes. `Prog.of(V_CL(), ...)`
# KEEPS its tag -- that one is a `Prog` FIELD, not a table index -- so the
# replacement is anchored on the callee name and cannot reach it.
# --------------------------------------------------------------------------
def subst(dest: str, old: str, new: str) -> int:
  """apply `old -> new` to a destination IN PLACE, skipping string literals."""
  n = 0
  for i, ln in enumerate(DST[dest]):
    parts = re.split(r'("[^"]*")', ln)
    for j, p in enumerate(parts):
      if j % 2 == 0:
        n += p.count(old)
        parts[j] = p.replace(old, new)
    DST[dest][i] = "".join(parts)
  return n


# --------------------------------------------------------------------------
# QUALIFY: prefix every def owned by ANOTHER file, at its call sites only.
# A name inside a string literal is DATA, not a call site -- the tc_ptx unit
# rewrote a PTX register inside one and the row count did not move, so this
# replacer skips every string literal and every comment.
# --------------------------------------------------------------------------
def defs_of(lines: list[str]) -> set[str]:
  """every top-level NAME a module exports -- `def`s AND `type`s.

  MEASURED, and it is the whole bug this function had on its first version: a
  qualifier built from `def` names alone silently left every `type` unqualified,
  so `type CuDev ... t: Tr` read a `Tr` that does not exist in the importing
  file, and bend reported it four hundred lines away as `a declared constructor
  (unknown: True)` on a `Bool` pattern that was perfectly fine.
  """
  out = set()
  for ln in lines:
    m = re.match(r"def ([A-Za-z_][\w.]*)\(", ln) or re.match(r"type ([A-Za-z_][\w.]*) is", ln)
    if m:
      out.add(m.group(1))
  return out


CL_NAMES = defs_of(cl) | {"brow", "urow", "srow", "ush", "lrow", "ssh", "srowlist"}
CU_NAMES = defs_of(cu) - CL_NAMES


def qualify(dest: str, names: set[str], tag: str) -> int:
  """prefix every name in `names` with `tag`, IN PLACE, at call sites only.

  A name inside a string literal is DATA and a comment is prose; the tc_ptx unit
  rewrote a PTX REGISTER inside a string literal, both halves of the row moved
  together, and the row count did not move -- so this skips every literal and
  every comment line. The result is written back into `DST[dest]`, which is what
  the writer reads; returning a new list here silently discarded every prefix
  once already.
  """
  if not names:
    return 0
  pat = re.compile(r"(?<![\w.])(" + "|".join(sorted((re.escape(n) for n in names), key=len, reverse=True)) + r")(?![\w])")
  hits = 0
  for i, ln in enumerate(DST[dest]):
    if ln.lstrip().startswith("#"):
      continue
    # The DECLARATION head is never a call site: `def Tr.of(...)` must not
    # become `def CL.Tr.of(...)`, which would redefine the imported name in this
    # file and take it out of every other file's reach. So the head is cut off
    # before the substitution pass and the body is not.
    head = re.match(r"\s*(?:def|type)\s+[A-Za-z_][\w.]*", ln)
    off = head.end() if head else 0
    pre, body = ln[:off], ln[off:]
    parts = re.split(r'("[^"]*")', body)          # odd indices are string literals
    for j, p in enumerate(parts):
      if j % 2 == 1:
        continue
      p2, n = pat.subn(rf"{tag}.\1", p)
      hits += n
      parts[j] = p2
    DST[dest][i] = pre + "".join(parts)
  return hits


cl_tr = subst("cl", "vend.trace(V_CL(), ", "vend.trace(")
cu_tr = subst("cu", "vend.trace(V_CUDA(), ", "vend.trace(")
hp_tr = subst("hp", "vend.trace(V_HIP(), ", "vend.trace(")
# `t_cross` is the only block that reads the OTHER two files' traces, so its six
# `x_free_*`/`x_copy*_*` rows are the only `vend.trace(v, ...)` call sites that
# turn into a CROSS-module call rather than a local one.
x_tr_cl = subst("hp", "vend.trace(V_CL(), ", "CL.vend.trace(")
x_tr_cu = subst("hp", "vend.trace(V_CUDA(), ", "CU.vend.trace(")
assert (cl_tr, cu_tr, hp_tr, x_tr_cl, x_tr_cu) == (22, 23, 16, 3, 1), (
  cl_tr, cu_tr, hp_tr, x_tr_cl, x_tr_cu)
# THREE FALSE CLAIMS THE SPLIT MADE VISIBLE, each corrected with a measurement and
# each a COMMENT-ONLY edit (see the coordinator's note on the concurrent comment
# realignment pass, which is scoped elsewhere and touched none of these).
fix = subst("cl", "# --- 10: the REFUSAL paths, every `check` in the three files ---------------",
            "# --- 10: the REFUSAL paths, every CL `check` (cl:17-19) ----------------------\n"
            "# PORT-LOCAL CORRECTION: the pre-split heading read \"every `check` in the three\n"
            "# files\", and ALL 29 of its rows are `cl_refuse_*`. It was CL-only before the\n"
            "# split too. `t_cross`'s `x_free_*` rows are the three-file part.")
assert fix == 1, fix
fix = subst("cu", "# PART 2 -- CUDA. `ops_cuda.py`, all 136 lines.",
            "# PART 2 -- CUDA. `ops_cuda.py`. STALE-LINE NOTE: the pre-split header said\n"
            "# \"all 136 lines\" and cited `cu:132` and `cu:134-136`; MEASURED against this\n"
            "# tree `ops_cuda.py` is 129 lines, `count` is at :125 and `_wait_signal` at\n"
            "# :126. The citations are NOT renumbered here: `tinygrad/` is mid-rebase.")
assert fix == 1, fix
assert subst("cu", "# PART 4 -- CUDA. cu:17-136.", "# PART 4 -- CUDA. cu:17-129.") == 1
print("3 false claims corrected, with the measurement that corrects each")

# `t_cross` is the only block that reads all THREE vendor tables. The vendor tags
# it used are gone -- `vend.name` is per file -- so its eleven `x_<op>` rows are
# three MODULES' names joined with "|". It lives in `ops_hip.bend` because bend
# has no import cycle (MEASURED) and `ops_hip.bend` is the only one of the three
# that can import both others.
x_cl = subst("hp", "vend.name(V_CL(), ", "CL.vend.name(")
x_cu = subst("hp", "vend.name(V_CUDA(), ", "CU.vend.name(")
x_hp = subst("hp", "vend.name(V_HIP(), ", "vend.name(")
assert (x_cl, x_cu, x_hp) == (11, 11, 11), (x_cl, x_cu, x_hp)
print(f"t_cross's 11 three-way rows: {x_cl} CL. + {x_cu} CU. + {x_hp} local vend.name cells")
print(f"vend.trace(+v, cs) -> vend.trace(cs): {cl_tr} cl + {cu_tr} cu + {hp_tr} hp "
      f"call sites, plus t_cross's {x_tr_cl} CL. + {x_tr_cu} CU. cross reads")

# A PER-FILE name (`vend.name`, `t_vend`, `main`, ...) exists in all three files
# and is the destination's OWN, so qualifying it would call the OTHER file's
# version and silently print the wrong vendor's rows -- which is exactly what the
# first run of this script did: `ops_hip.bend` printed `vend_count_cl=23` as its
# own first row. The sets are therefore minus the destination's own names.
cu_hits = qualify("cu", CL_NAMES - defs_of(DST["cu"]), "CL")
# THE SPLIT-FORCED CALL-SITE EDIT, one of exactly two: before the split the
# file had ONE `OP_FINISH` emitter, `cl.sync`, and cu:82 and cu:80 both called it.
# A CUDA file cannot reach into the OpenCL file for its own synchronize.
cu_sync = subst("cu", "CL.cl.sync(", "cu.sync(")
assert cu_sync == 2, cu_sync

hp_cl = qualify("hp", CL_NAMES - defs_of(DST["hp"]), "CL")
hp_cu = qualify("hp", CU_NAMES - defs_of(DST["hp"]), "CU")
# bend does NOT re-export `Base` through an import -- MEASURED, `M.U32.add` is
# "a defined name: expected / observed" -- so `U32`/`Bool`/`List`/`String`/`IO`
# stay unqualified and only the file's OWN defs are prefixed. The check below is
# the one that matters: a prefixed `Base` name would not compile, and 300 of them
# would be a silent 300-site corruption if the qualifier were ever widened.
BASE = r"\b(?:CL|CU)\.(?:Bool|U32|F32|List|String|Char|IO|Maybe|Nat|Base)\b"
for _k in ("cu", "hp"):
  _bad = [(i + 1, ln) for i, ln in enumerate(DST[_k]) if re.search(BASE, ln)]
  if _bad:
    sys.exit(f"a Base name got a module prefix in ops_{_k}.bend: {_bad[:5]}")

# the import lines go in last, so the qualifier never sees them
# `../helpers.bend as H` is `iter_sig`'s `H.round_up_u32`, which moved into
# `ops_hip.bend` with the body, so HIP needs the import the CL file had.
DST["cu"] = ["import Base", "import ../helpers.bend as H", "import ./ops_cl.bend as CL", ""] + DST["cu"]
DST["hp"] = ["import Base", "import ../helpers.bend as H", "import ./ops_cl.bend as CL", "import ./ops_cuda.bend as CU", ""] + DST["hp"]

OUT = {"cl": ROOT / "tinybendygrad/runtime/ops_cl.bend",
       "cu": ROOT / "tinybendygrad/runtime/ops_cuda.bend",
       "hp": ROOT / "tinybendygrad/runtime/ops_hip.bend"}

# --------------------------------------------------------------------------
# THE SAFENET. Every `def` in the pre-split file must land in exactly one
# destination, exactly once -- or it is a silent loss. The six that the split
# FORCES out of existence are listed with the reason.
# --------------------------------------------------------------------------
DROPPED = {
  "V_CUDA": "nothing indexes it once vend.name/vend.count/vend.checked/vend.trace are per file",
  "V_HIP":  "ditto",
  "vend.name.at": "the Bool.pick ladder over three tables, one table per file now",
  "vend.checked": "per file, one body per vendor table",
  "chk_count.at": "per file, `v` is constant within a file",
  "chk_count": "per file",
  "vend.line": "per file",
  "vend.trace.put": "per file",
  "vend.trace.go": "per file",
  "vend.trace": "per file",
  "vend.name": "per file",
  "vend.count": "per file",
  "vend.cu.of": "moved, not dropped",
  "vend.hp.of": "moved, not dropped",
  "cu_unchecked": "moved, not dropped",
  "hp_unchecked": "moved, not dropped",
  "cu_err_code": "moved, not dropped",
  "Spec.host": "moved, not dropped",
  "cl.sync": "moved, not dropped -- CL's own",
}
src_defs = defs_of(L)
got: dict[str, list[str]] = {}
for k in ("cl", "cu", "hp"):
  for n in defs_of(DST[k]):
    got.setdefault(n, []).append(k)
lost = sorted(n for n in src_defs if n not in got)
added = sorted(n for n in got if n not in src_defs)
# the per-file defs are SUPPOSED to exist in all three files: that is the split.
PER_FILE = {"vend.name", "vend.count", "vend.checked", "chk_count", "chk_count.at",
            "vend.line", "vend.trace", "vend.trace.put", "vend.trace.go",
            "t_vend", "t_check", "t_err", "main"}
duped = sorted(n for n, ks in got.items() if len(ks) > 1 and n not in PER_FILE)
partial = sorted(n for n, ks in got.items() if n in PER_FILE and len(ks) != 3)
if partial:
  sys.exit(f"a PER-FILE def is not in all three files: {[(n, got[n]) for n in partial]}")
if duped:
  sys.exit(f"DUPLICATED defs, a name is in two files: {duped}")
unexplained = [n for n in lost if n not in DROPPED]
if unexplained:
  sys.exit(f"LOST defs with no reason: {unexplained}")
moved = [n for n in lost if DROPPED.get(n) == "moved, not dropped"]
gone = [n for n in lost if DROPPED.get(n) != "moved, not dropped"]
print(f"safenet: {len(src_defs)} source defs; {len(moved)} moved, {len(gone)} REMOVED, "
      f"{len(added)} added by the split")
print(f"safenet: REMOVED = {', '.join(gone)}")

print(f"qualifier: ops_cuda got {cu_hits} CL. call sites")
print(f"qualifier: ops_hip  got {hp_cl} CL. + {hp_cu} CU. call sites")

if "--write" in sys.argv:
  for k, p in OUT.items():
    body = "\n".join(DST[k])
    p.write_text(body if body.endswith("\n") else body + "\n")
    print(f"wrote {p.relative_to(ROOT)}  {len(DST[k])} lines")
else:
  for k in OUT:
    print(f"would write {OUT[k].relative_to(ROOT)}  {len(DST[k])} lines")