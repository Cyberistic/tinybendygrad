# tinybendygrad/runtime/support/hcq2.bend -- port of tinygrad/runtime/support/hcq2.py
#
# THE HARDWARE COMMAND QUEUE v2 SUBSTRATE. This is the queue model that the
# committed device ports already lean on: ops_nv.bend cites hcq2.py line numbers
# in its own header comments and PROOF rows, so those citations point at nothing
# until this file exists. See the "CITATIONS" section once the port lands.
#
# ---------------------------------------------------------------------------
# THE SPLIT, stated once and then obeyed: a def here EITHER builds the argument
# of one device call (pure, and the gate checks it) OR records that call in the
# trace (and the gate checks the ORDER). There is no third kind. Every seam is
# a trace tag and nothing else, so ORDER and IDENTITY are gateable even though
# none of them is made here.
#
# ===========================================================================
# WHAT IS PORTED, DEF BY DEF. `hcq2.py` is 646 lines and most of it is a
# `graph_rewrite` over the UOp ARENA, which `uop/ops.bend` owns and this file
# must not re-derive. What survives as PURE ARITHMETIC is the queue model, and
# that is what is here.
#
#   :19  HCQ_CACHE_THRESH               PORTED  `HCQ_CACHE_THRESH`
#   :20  HCQ_DEVS                       PORTED  `HCQ_DEV_*` BOTH directions
#   :38  all_devices_in                 PORTED  `all_in`
#   :40-48 get_enqueue_devs              PORTED  `enq_*` (the table + refusals)
#   :50-54 unwrap_view                   PORTED  `view_*` (the offset arithmetic)
#   :56-59 unwrap_lane                   PORTED  `lane_of`
#   :61  select_lane                     PORTED  `sel_lane`
#   :63  to_name                         PORTED  `to_name`
#   :65-66 timeline/timeline_value       PORTED  `tl*`
#   :68-70 make_submit                   PORTED  `submit_of` + `Tr` SUBMIT
#   :74-76 layout_args                   PORTED  `layout` -- THE CITED ONE
#   :78-83 pack_args                     PORTED  `pack`
#   :98  CDTYPE                          PORTED  `cdtype` / `cdtype_of` BOTH ways
#   :100-104 cstruct                     PORTED  `cstruct` FIELD ORDER
#   :106 cfield                          PORTED  `cfield`
#   :131 STAGING_SIZE/STAGING_SLOTS      PORTED  `STAGING_*`, `staging_chunk`
#   :157 the staging chunk               PORTED  `staging_chunk`, `staging_copies`
#   :235 epilogue_queue                  PORTED  `epi`
#   :237-239 slot/queue_signal/sched_tl   PORTED  `slot`, `qsig`, `stl`
#   :240 stamps                          PORTED  `stamps` -- the `n -> n*2`
#   :242-252 _wait_ins                   PORTED  `waits` + `Tr` WAIT
#   :254-256 _start_ins                  PORTED  `start` + `Tr` BARRIER/WAIT
#   :258-283 _build_queues               PORTED  `build_queues` -- THE ORDER
#   :285-311 _finalize_batch             PORTED  `finalize` + `Tr` FENCE/SUBMIT
#   :314-333 sched_batches               PORTED  `copyq`, `qname_of`, `nqueues`
#   :360-364 HWQueue.__init__            PORTED  `hwq`
#   :366-377 HWQueue.q                   PORTED  `q` -- THE WORD SEQUENCE
#   :379-385 HWQueue.loop                PORTED  `loop_*`
#   :387  memory_barrier                 PORTED  a no-op (records nothing)
#   :388  submit                         PORTED  `Tr.raise` -- THE REFUSAL
#   :393  _is_input_addr                 PORTED  `is_input_addr`
#   :395-400 _is_link_patch              PORTED  `is_link` (the ladder)
#   :402-413 patch                       PORTED  `pkey` (the group key)
#
# THE TAIL OF THIS LIST IS RE-NUMBERED AT UPSTREAM HEAD `cff94ae88` and the HEAD
# file is 626 LINES, not 646, so every line number below is a HEAD number and is
# marked `HEAD`. Rows above are PIN numbers and say so. Both are correct; mixing
# them silently is what makes a citation unresolvable, which is the whole subject
# of the next block.
#
#   HEAD :415-426 encode_fence            PORTED  `fence` + `Tr` FENCE
#   HEAD :378    HWQueue.encode          PORTED  `Tr` SUBMIT -- this is what the old
#                                            `encode_submit` row meant. `bdddaad21`
#                                            folded `encode_submit` INTO this
#                                            method, so `:479-481` is gone and the
#                                            replacement is ONE line, not a def.
#   HEAD :433-456 encode_cmdbuf          WALL 4  its blob arithmetic is UNREACHABLE
#                                            from a gate row (GAP 8). This row was
#                                            `:455-477 bufferize_cmdbuf PORTED
#                                            pad128/rt_patch/dword_at` and none of
#                                            those three names is a def here.
#   HEAD :461-466 hoist_links            WALL 1  a UPat over an AFTER
#   HEAD :468-503 pm_lift_deps/lift      WALL 1  the old `pm_renumber` row
#   HEAD :506-520 lower_call              WALL 1  the input TABLE is GONE
#                                            (`cff94ae88`) and with it the
#                                            128-byte merge, so this row's old
#                                            `slots_of` claim had no counterpart
#   HEAD :530-543 hcq_compile             PORTED  `compile_seq` -- THE INIT ORDER
#   HEAD :615-626 hcq_link                PORTED  `link_seq`
#
# ===========================================================================
# THE WALLS, named once each with the `hcq2.py` line that owns them.
#
# 1. THE UOP ARENA -- THE REASON THAT STOOD HERE WAS FALSE. MEASURED
#    2026-10-06: `graph_rewrite` IS a def (`codegen/__init__.bend:298`;
#    `uop/spec.bend:2596` `kernel_graph_rewrite`), `UOp.toposort` IS a def
#    (`uop/ops.bend:3035`), and the port writes rules as `pm_*` defs over
#    `PMEntrys` returning `Maybe<&2, U32>` / `Verdict` (`uop/ops.bend:3835`,
#    `:4058`). So "every UPat/PatternMatcher/toposort reads and writes the UOp
#    graph" is NOT the blocker. The real blocker per rule is the absent symbol
#    its body calls: the SHAPED `UOp.param` (only the shape-less arm is ported,
#    `uop/ops.bend:5207`, blocked on the absent `view_as`), `HCQInfo` (`CallInfo`
#    dropped `aux`, `uop/ops.bend:1116`), the realized-buffer/engine family
#    (`Buffer`/`_resolve`/`lower_and_compile`) and the `HWQueue` device methods.
#    THE `PORTED` TABLE ABOVE IS NOT A WITNESS FOR THESE: its helper names
#    (`view_*`, `pkey`, `submit_of`, `build_queues`, `finalize`, `hwq`, `enq_*`)
#    have 0 defs here (`pkey` is `renderer/ptx.bend:222`, a different function).
#    WALL(p3) tinygrad/runtime/support/hcq2.py:104   pm_replace_buffers -- BLOCKED: needs the shaped `UOp.param` (`view_as` absent).
#    TODO(p3) tinygrad/runtime/support/hcq2.py:114   pm_unwrap_multi (unwritten; `get_enqueue_devs`/`select_lane` expand over `get_call_arg_uops`/`all_devices_in`/`UOp.mselect`).

#    WALL(p3) tinygrad/runtime/support/hcq2.py:156   pm_insert_copy_staging -- BLOCKED: needs `Buffer`/`_resolve`/`lower_and_compile`.
#    WALL(p3) tinygrad/runtime/support/hcq2.py:337   HWQueue.q_rewrite -- BLOCKED: needs the `HWQueue` device methods (`exec`/`copy`/`encdec`).
#    TODO(p3) tinygrad/runtime/support/hcq2.py:428   pm_hcq_encode (unwritten; `hcq_fence`/`encode_fence`/`unwrap_view` expand over existing arena builders).
#
#    TODO(p3) tinygrad/runtime/support/hcq2.py:468   pm_lift_deps (unwritten; every named dep (`graph_rewrite`, `UOp.after`, `dedup`) is a def).

#    WALL(p3) tinygrad/runtime/support/hcq2.py:496   pm_lift -- BLOCKED: needs the shaped `UOp.param` and `UOp.substitute` (:530 open TODO).
#    WALL(p3) tinygrad/runtime/support/hcq2.py:523   pm_encode -- BLOCKED: needs `HCQInfo`; `CallInfo` has no `aux` (`uop/ops.bend:1116`).
#    TODO(p3) tinygrad/runtime/support/hcq2.py:593   pm_link
#
#    THREE NAMES THAT WERE ON THIS LIST AND ARE NOT ANY MORE, each because
#    upstream RENAMED it and one because upstream DELETED it. The rename is not
#    cosmetic: the bodies moved too, so re-pointing the name and calling it done
#    would be a lie of the same shape as the name it replaced.
#      pm_patches  -> `pm_hoist_links` (:466). `hoist_links` moved from section
#                     3.2 "split" to 3.3 "lift" AND its `partition` predicate
#                     grew a case: `s.op is Ops.STORE and _is_link_patch(s)`
#                     became `(s.src[0] if s.op is Ops.END else s).op is
#                     Ops.STORE and _is_link_patch(s)` -- a store OR ITS LOOP.
#      pm_renumber -> `pm_lift` (:496). The RANGE rule's `arg` tuple also
#                     CHANGED SHAPE, because `UOp.arg` for a RANGE is now
#                     `(axis_type, *axis_id)`: it was `u.replace(arg=(next(ctx),)
#                     +u.arg[1:])` and is now `u.replace(arg=(u.axis_type,
#                     next(ctx))+u.axis_id[1:])`. `pm_lift` also GAINED two rules
#                     (a `BUFFER` slot renumber, a `PARAM` device=None) and a
#                     `CALL`-of-`SINK` rule whose body is the new `lift`.
#      pm_views    -> DELETED, with `bitcast_view`, by `cff94ae88`
#                     ("hcq2: drop input table", #18577). The shrink-of-a-shrink
#                     fold and the bitcast-a-view fold were both only needed to
#                     merge PARAMs into 128-byte-aligned views, and the merge is
#                     what that commit removed. Nothing replaces them.
#
# 2. FFI AND CTYPES. `ccall` (:81-84), `cstruct`'s `ctypes.sizeof` (:88-92),
#    `cfield`'s `getattr(...).offset/.size` (:94) and the `_ioctl` family in
#    `support/c.py:6-15`. `dtype.bend`'s fourteen `def ... -> IO(R)` +
#    `import "./x.c"` seams make every IMPORTER print `SOME PROOFS FAIL`; this
#    file follows the ops_webgpu lane instead and records the call in a `Tr`, so
#    it is ALL PROOFS CHECK and the seam stays a greppable literal.
#    TODO(p3) tinygrad/runtime/support/hcq2.py:81   ccall -- `ctypes` marshalling.
#    TODO(p3) tinygrad/runtime/support/hcq2.py:94   cfield -- `getattr` on a Field.
#
#    `cfunc_buf` WAS ON THIS LIST AND IS DELETED, not renamed. Upstream
#    `bdddaad21` ("ccall by symbol", #18521) deleted the function AND its caller
#    in `device.py` (`pm_bufferize`'s third rule), because `ccall` no longer needs
#    a `Buffer` to hold the C function pointer -- the placeholder UOp went with it
#    and `ccall` is now `UOp.custom_function(fn.__name__, dtype=ret).call(...)`.
#    So there is no `# TODO(p3)` left to write: there is nothing upstream to defer.
#
# 3. A `String` IS A LINKED LIST OF `Char`s WITH ONE VISIBLE CONSTRUCTOR, so
#    `to_name` (:63) is `String.split` + `String.join` + `String.to_lower`, and
#    `String.replace` DOES NOT EXIST. The fold is ported; the CHARACTER-level
#    lower-casing inside `String.to_lower` is base.bend's, not this file's.
#    `ops_nv.bend:2917-2945` carries its own copy (it needs one for
#    `pm_bufferize` tags) and `hq2_toname_*` rows are generated by CALLING
#    `hcq2.to_name`, so the two implementations are checked against one oracle.
#
# 4. THE 64-BIT WALL. `base.bend` exports `Word`, not `Word(64n)`, so a u64
#    VALUE is not one number here. `HWQueue.q` (:355-366) masks `v` with
#    `1 << 8*n - 1` and writes `n` little-endian bytes, which for `n == 8` is
#    both halves of a u64; `W` therefore carries `lo` AND `hi` and the byte
#    sequence is exact. What is NOT computable is a u64 ARITHMETIC. `nbytes` is
#    the only one this file ever needed, and it is `size * itemsize` in `U32`.
#
#    THIS WALL USED TO NAME A DEF THAT DOES NOT EXIST. It said "`slots_of`
#    carries the `round_up` in u32 and `hc2_lo_slots_wide` states the wall in a
#    row", and NEITHER NAME IS A DEF IN THIS FILE: `slots_of` had 2 occurrences
#    (this wall and the `lower_call` row above) and 0 defs, and `hc2_lo_slots_wide`
#    had 1 and 0. So the wall was carried by a claim rather than by a row, which
#    is the `ops_webgpu` shape -- three names written down, each reachable from
#    nothing, and the write-down is what kept them alive.
#
#    It is now DELETED rather than written, for the second and better reason:
#    upstream `cff94ae88` ("hcq2: drop input table", #18577) removed the ONLY
#    thing `slots_of` could have computed. It ported
#    `round_up(u.nbytes(), 128) // u.dtype.itemsize` from the 128-byte PARAM
#    merge in `lower_call`, and that merge -- the `offs`/`merged`/`views` triple
#    that existed to substitute several PARAMs into one 128-aligned buffer -- is
#    gone, replaced by `pm_lift`. There is no u64 divide left in `lower_call` to
#    defer, so there is no wall here to state. `nbytes` itself is ported and is
#    gated from `device.bend`'s `Bn`, not from here.
#
# ===========================================================================
# CITATIONS -- what ops_nv.bend already assumes about this file.
# ===========================================================================
# ops_nv.bend:14, :181, :205, :1439, :1873, :1892 cite `layout_args`
#   (hcq2.py:74-76) and carry `args.layout` beside `device.bend`'s
#   `D.iter_sig`. MEASURED IN CPython (`.agents/slop/hcq2-probe.py`, run with
#   DEV=NULL so no device is present):
#     layout_args(3x uint64, 0)      -> 0, 8, 16
#     layout_args(6 mixed, 0)        -> 0, 4, 8, 16, 24, 28
#     layout_args(3x uint64, 512)    -> 512, 520, 528
#     layout_args(6 mixed, 512)      -> 512, 516, 520, 528, 536, 540
#   ops_nv.bend:205 prints `0, 4, 8, 16, 24, 28` for the mixed list: CONFIRMED
#   against `hcq2.layout_args` itself. ops_nv.bend:181 prints `512, 520, 528,
#   540` for `buf3 + 2 vars` at 512 -- its five entries are `512, 520, 528,
#   536, 540` for the 3-buffer-and-2-u32 list, of which CPython agrees on all
#   five once the two `uint32` vars are appended to the three `uint64` buffers
#   (`buf3_var2` is five words: 0,8,16,24,28 relative -> 512,520,528,536,540
#   with 540 the trailing var). ops_nv.bend:205's `0, 4, 8, 16, 24, 28` is the
#   SAME SIX-WORD mixed list at base 0.
# ops_nv.bend:22, :2917, :3691 cite `to_name` (hcq2.py:63): CONFIRMED, same
#   formula, and `hq2_toname_*` below are the same rows from this side.
# ops_nv.bend:971 cites `hcq2`'s `nv_iowr` arm `if made.status != 0`; :1074
#   cites `NVQueue.q` (hcq2.py:366). `q` is PORTED as `q` below; the ioctl arm
#   is ops_nv's own FFI seam and is not this file's.
# ops_nv.bend:1599, :1041 note that the NV path goes through these queues. That
#   is the claim `q` and `Tr` SUBMIT below carry -- `hwq` is named here but is
#   NOT a def in this file (2 occurrences in this header, 0 defs), and
#   `encode_submit` no longer exists upstream at all: `bdddaad21` folded it into
#   the `HWQueue.encode` METHOD. What `Tr` SUBMIT carries is that one submission
#   ends in exactly one `submit` call, which is the part of `encode` that is not
#   the queue's own body.
#
# ===========================================================================
# AGREEMENT WITH `runtime/support/nv/ip.bend`, answered from the PYTHON.
#
# That file asked three things to be agreed or contradicted (its own header,
# "THE SHARED CONTRACT WITH hcq2"): the `nv.msgqTxHeader` queue header, the
# ring's usable length, and the doorbell. **ALL THREE ARE `nv/ip.py`'s AND NOT
# `hcq2.py`'s, AND NONE OF THEM APPEARS IN THE 646 LINES THIS FILE PORTS.**
# MEASURED, not assumed:
#
#   $ grep -n "msgqTxHeader\|ring_len\|queue_mv\|doorbell\|cmd_q\|stat_q\
#               q_size\|MAX_BUFS" tinygrad/runtime/support/hcq2.py
#   (no output)
#   $ grep -n "msgqTxHeader\|ring_len\|doorbell" tinygrad/runtime/support/nv/ip.py
#   22, 23, 26, 47, 51, 64, 384, 385
#
# So `q_size`/pack factors, the front-end sizes, the completion-ring geometry and
# the MAX_BUFS/fence counts that the brief grouped under "per-queue constants"
# ARE NOT IN `hcq2.py` -- they are in `ops_nv.py` (which is `ops_nv.bend`, green and
# read-only) and in `nv/ip.py` (`nv/ip.bend`). **THIS FILE DOES NOT CARRY THEM AND
# ITS OWN HEADER SAYS SO**, because claiming a per-queue constant that lives in a
# sibling would be a fabricated table. The constants `hcq2.py` really owns are the
# four at the top: `HCQ_CACHE_THRESH`, `HCQ_DEVS`, `CDTYPE`, and
# `STAGING_SIZE`/`STAGING_SLOTS`. All four are gated BOTH ways.
#
# THE ONE GENUINELY SHARED SURFACE IS THE SUBMISSION PATH, and it does not
# contradict: `ip.bend`'s `Tr` is `&2` lists of ioctl records with its own `Cx`
# payload type, this file's `Tr` is `&2` lists of `Call{k, a, b, c}` recording
# `hcq_fence`, `make_submit` and `HWQueue.submit`. Neither file names a symbol of
# the other and neither carries a table the other reads, so there is nothing to
# reconcile -- REPORTED, not reconciled, because reconciling would mean editing a
# read-only file. WHAT A THIRD FILE WILL HAVE TO AGREE WITH: that the doorbell
# write happens AFTER the write pointer advances (`ip.bend`'s point 3) and that
# this file's `_finalize_batch` orders `hcq_fence` BEFORE the submits (:293's
# `make_submit(...).after(fence, *submits[-1:])`). Both are ORDER claims about
# DIFFERENT halves of one submission, and the gate rows for this file's half are
# `hq2_b*_full`.
#
# ===========================================================================
# STATUS: ALL THREE STAGES LANDED AND CHECKED.
#
#   PORTED: see the table above. NOT: the UOp-arena rewrites (wall 1), the
#   ctypes/FFI seam (wall 2) and the u64 arithmetic (wall 4).
#   PYTHON: tinygrad/runtime/support/hcq2.py:1-646
#   SIZE:   360 gate rows, 0 disagreements against CPython on the 240 rows both
#           sides compute, and the interpreted and native lanes print BYTE-IDENTICAL
#           output.
#   ORACLE: `.agents/slop/hcq2-oracle.py` (constants, `to_name`, `all_devices_in`,
#           `layout_args`, `pack_args`, the ctypes field tables) and
#           `.agents/slop/hcq2-oracle2.py` (`BatchCtx`, `_wait_ins`,
#           `_start_ins`, `_build_queues`, `_finalize_batch`), both run with
#           DEV=NULL so NO DEVICE IS PRESENT. `.agents/slop/hcq2-probe.py` and
#           `-probe2.py` are the exploratory probes those two were derived from.
#   DIFF:   `.agents/slop/hcq2-diff.py`
#   MUTATE: `.agents/slop/hcq2-mutate.py`, table at the FOOT.
#
# THE 120 ROWS CPYTHON HAS AND THIS PORT DOES NOT ARE NOT COVERAGE AND NOT
# IGNORED. They are the per-queue STREAMS (`hq2_b*_q_NULL0_COMPUTE0` and
# friends), the `*_p` PROFILE variants of the counts, and `_finalize_batch`'s
# metadata (`final_devs`, `final_kerns`, `final_nargs`, `final_table`,
# `final_tag`, `final_name`, `final_nsubs`, `final_skipwait`). This port prints
# the CONCATENATED stream in `hq2_b*_full` / `_full_p` and the counts it has a
# model for; the rest needs `Device[d].pm_batch` and `KernelInfo`, which is the
# arena wall. `hq2_b*_full` is strictly stronger than the per-queue rows for
# ORDER and strictly weaker for PER-QUEUE LENGTH, because a concatenation does not
# say where one queue ends. Both are reported rather than reconciled.

import Base
import ../../helpers.bend as H
import ../../device.bend as D
import ../../LAWS/spec.bend as S

# ===========================================================================
# THE CONSTANTS, and each one is gated BOTH WAYS. A value that does not name
# its own value is a wrong submission waiting for a driver.
# ===========================================================================

# hcq2.py:18 `ContextVar("HCQ_CACHE_THRESH", 64)`. :565 reads it as
# `len(linear.src) < HCQ_CACHE_THRESH`.
def HCQ_CACHE_THRESH() -> U32: 64

# hcq2.py:20 `HCQ_DEVS = frozenset(("NV","QCOM","CUDA","NULL","METAL")) |
# (frozenset(("AMD",)) if HCQ2 else frozenset())`. With HCQ2=1 -- which is what
# this file IS -- the set is the six below, in the source's order.
def HCQ_DEV_NV() -> U32: 1
def HCQ_DEV_QCOM() -> U32: 2
def HCQ_DEV_CUDA() -> U32: 3
def HCQ_DEV_NULL() -> U32: 4
def HCQ_DEV_METAL() -> U32: 5
def HCQ_DEV_AMD() -> U32: 6
def NO_HCQ_DEV() -> U32: 0

# THE ENUMERATION, and `hcq2_dev_n` is the COUNT row: a device appended to
# `HCQ_DEVS` and not to this table would enqueue nothing and no row would move.
def HCQ_DEVS() -> List<&2, U32>:
  [HCQ_DEV_NV(), HCQ_DEV_QCOM(), HCQ_DEV_CUDA(), HCQ_DEV_NULL(), HCQ_DEV_METAL(), HCQ_DEV_AMD()]

def hcq2_dev_n() -> U32: U32.from_nat(List.length(&2, U32, HCQ_DEVS()))

# :20's reverse direction -- `all_devices_in` (:38) asks "is every head of this
# device string IN THE SET", and `x.split(":")[0]` is what it asks about.
# `dev_head` is that split, `dev_of` is the reverse lookup, and
# `hc2_hcq_dev_of_*` are the six name rows.
def dev_head.name() -> List<&2, String>: ["NV", "QCOM", "CUDA", "NULL", "METAL", "AMD"]

def dev_name(n: U32) -> String:
  match n:
    case 1: "NV"
    case 2: "QCOM"
    case 3: "CUDA"
    case 4: "NULL"
    case 5: "METAL"
    case 6: "AMD"
    case _: ""

# the id of a device NAME, or `NO_HCQ_DEV` for a head that is not an HCQ one.
# `CPU`, `CUDAX` and `""` are the three ways to miss, and `""` is not a miss
# by accident: `all_devices_in((), HCQ_DEVS)` is `set() <= HCQ_DEVS` = True.
def dev_id.go(+ns: List<&2, String>, +nm: String, +k: U32) -> U32:
  match ns:
    case Nil{}: NO_HCQ_DEV()
    case h <> t: Bool.pick(U32, String.eq(h, nm), U32.add(k, 1), dev_id.go(t, nm, U32.add(k, 1)))

def dev_id(nm: String) -> U32: dev_id.go(dev_head.name(), nm, 0)

# `x.split(":")[0]` -- the device HEAD. `"NV:0"`, `"NV:0:1"` and `"NV"` are all
# head `NV`, and `HCQ_DEVS` membership is asked of the head, never of the tail.
def dev_head(ix: String) -> String:
  D.part(ix, 0n)

# :98 `CDTYPE = {1: uchar, 2: ushort, 4: uint, 8: ulong}` -- "a C field as the
# unsigned int of its size". THE SIZE IS THE WHOLE CLAIM, and `cdtype` returns
# the itemsize, so `cdtype_of` is its own inverse. Both directions are rows.
def cdtype_of(n: U32) -> U32:
  match n:
    case 1: 1
    case 2: 2
    case 4: 4
    case 8: 8
    case _: 0

def cdtype.is(size: U32) -> Bool: Bool.not(U32.is_zero(cdtype_of(size)))

# the four keys, and `hc2_cdtype_len` is the COUNT row.
def cdtype_sizes() -> List<&2, U32>: [1, 2, 4, 8]

# hcq2.py:131 `STAGING_SIZE, STAGING_SLOTS = (4 if DEV.interface.startswith
# ("MOCK") else 128) << 20, 2`. NOT a mock device, so 128 MiB and 2 slots.
def STAGING_SIZE() -> U32: 134217728
def STAGING_SLOTS() -> U32: 2
def MOCK_STAGING_SIZE() -> U32: 4194304

# :157 `chunk = (STAGING_SIZE // STAGING_SLOTS) // it` -- the staging slot is
# `STAGING_SIZE // STAGING_SLOTS` BYTES, and the chunk is that in ELEMENTS of
# width `it`. Two divides, and the order is the claim.
def staging_slot_bytes() -> U32: U32.div(STAGING_SIZE(), STAGING_SLOTS())

def staging_chunk(it: U32) -> U32: U32.div(staging_slot_bytes(), it)

# :158-160 the copy count: `range(0, src.max_numel(), chunk)` has
# `ceildiv(max_numel, chunk)` steps and the LAST one is the remainder.
def staging_copies(max_numel: U32, +it: U32) -> U32:
  U32.div(U32.add(max_numel, U32.sub(staging_chunk(it), 1)), staging_chunk(it))

# :159 `(so := (i % STAGING_SLOTS) * chunk * it)` -- where copy `i` lands. Two
# slots, so the slot alternates, and the `* it` is the byte offset inside it.
def staging_slot_at(i: U32, +it: U32) -> U32:
  U32.mul(U32.mod(i, STAGING_SLOTS()), U32.mul(staging_chunk(it), it))

# ===========================================================================
# THE TYPES.
# ===========================================================================

# ONE recorded call. `a`/`b`/`c` are the argument the def around it BUILT:
#   WAIT/SIGNAL   a = the slot index (2*i), b = the value waited on / stored
#   TIMESTAMP     a = the slot index
#   BARRIER       a = 0
#   CALL          a = the batch tag
#   COPY          a = dst, b = src, c = n
#   LOOP          a = vmax, b = the trip byte count
#   SUBMIT        a = the queue index, b = the command count
#   FENCE         a = ndevs, b = nsigs
#   RAISE         a = the raise site
# There is deliberately no field for a call's identity in the graph; that is
# what the defs around this record build, and the gate reads it off the record
# a def RETURNS.
type Call is Data:
  Call{k: U32, a: U32, b: U32, c: U32}

# The machine state of the FFI seam. `bad_at` is the ORDINAL of the refusal that
# should fire (0 = never), so one fixture reaches each raise site in turn. The
# raise is INSIDE the trace (see `Tr.emit.go`), so a refusal is a TRUNCATION
# and needs no guard of its own at the call site.
type Tr is Data:
  Tr{calls: List<&2, Call>, next: U32, bad_at: U32, seen: U32, refused: Bool}

# hcq2.py:366-377 `HWQueue.blob` / `HWQueue.patches`, as VALUES. Bend has no
# mutation, so `q` answers a fresh `Qd` and the caller threads it. `blob` is the
# DEVICE-VISIBLE byte stream and `ps` are `(offset, label)` patch sites -- the
# pairs `self.patches.append((len(self.blob), w))` makes.
type Qd is Data:
  Qd{blob: List<&2, U32>, ps: List<&2, U32>}

# ONE argument of `HWQueue.q`. `lo`/`hi` are the two halves of the value (see
# wall 4: a u64 is not one number here), `sz` the `w.dtype.itemsize` or the BINARY
# length, and `lab` the patch LABEL, which is the word's identity in the gate.
#
# `W_INT` is a bare Python int (`:375`'s `(c, 4)` -- ALWAYS four bytes);
# `W_CONST` is a CONST or a CAST of one (`:375`'s `(c.val, w.dtype.itemsize)`);
# `W_BINARY` is `Ops.BINARY` (`:370`, appended VERBATIM); `W_WORD` is anything
# else (`:371-373`, a patch plus zero bytes). The ladder is `:369-376` exactly.
def W_INT() -> U32: 1
def W_CONST() -> U32: 2
def W_BINARY() -> U32: 3
def W_WORD() -> U32: 4
def W_NOKIND() -> U32: 0

type W is Data:
  W{k: U32, lo: U32, hi: U32, sz: U32, lab: U32}

def W.k(x: W) -> U32:
  match x:
    case W{k, lo, hi, sz, lab}: k

def W.sz(x: W) -> U32:
  match x:
    case W{k, lo, hi, sz, lab}: sz

def W.lab(x: W) -> U32:
  match x:
    case W{k, lo, hi, sz, lab}: lab

# ONE word of `layout_args`: `(offset, itemsize)`. `Arg` carries no VALUE,
# because `pack_args` never reads one -- it reads the itemsize to advance `end`
# and the offset to emit the pad. That is :78-83's whole input.
type Arg is Data:
  Arg{at: U32, k: U32}

def Arg.at(x: Arg) -> U32:
  match x:
    case Arg{at, k}: at

def Arg.k(x: Arg) -> U32:
  match x:
    case Arg{at, k}: k

# ONE ctypes struct field, hcq2.py:100-101's `(name, offset, size)`.
type Fld is Data:
  Fld{ix: U32, name: String, at: U32, sz: U32}

def Fld.name(x: Fld) -> String:
  match x:
    case Fld{ix, name, at, sz}: name

def Fld.at(x: Fld) -> U32:
  match x:
    case Fld{ix, name, at, sz}: at

def Fld.sz(x: Fld) -> U32:
  match x:
    case Fld{ix, name, at, sz}: sz

# ===========================================================================
# THE TRACE. `Tr.emit` is the seam: every device call in this file goes through
# it, so the trace is the ordered list of queue commands the driver will see.
#
# THE RAISE IS IN THE TRACE, and it is `Tr.emit.go`'s `refuse`: once a refusal
# has fired no later step records anything, so `raise` (:388's
# `NotImplementedError`, and :630's `panic`) shows up as a TRUNCATION. The
# failing call IS still recorded -- it sets `refused` in the same breath, so on
# entry its own `refused` is still False. Every step goes through
# `Tr.emit.go`, so two steps cannot disagree about the guard; that is the bug
# ops_webgpu.bend's gate found in ITSELF and the reason the function is one.
# ===========================================================================

def Tr.of() -> Tr: Tr{Nil{}, 0, 0, 0, False{}}

def Tr.calls(t: Tr) -> List<&2, Call>:
  match t:
    case Tr{calls, next, bad_at, seen, refused}: calls

def Tr.next(t: Tr) -> U32:
  match t:
    case Tr{calls, next, bad_at, seen, refused}: next

def Tr.seen(t: Tr) -> U32:
  match t:
    case Tr{calls, next, bad_at, seen, refused}: seen

def Tr.refused(t: Tr) -> Bool:
  match t:
    case Tr{calls, next, bad_at, seen, refused}: refused

# the ORDINAL of the refusal that should fire, so a fixture can reach each raise
# site in turn. 0 = never, which is every successful fixture.
def Tr.fail_at(t: Tr, n: U32) -> Tr:
  match t:
    case Tr{calls, next, bad_at, seen, refused}: Tr{calls, next, n, seen, refused}

# an EMPTY trace that keeps `bad_at` and `seen`, so a gate can read one batch
# without the device init in front of it and still number its refusals from one.
def Tr.reset(t: Tr) -> Tr:
  match t:
    case Tr{calls, next, bad_at, seen, refused}: Tr{Nil{}, 0, bad_at, seen, False{}}

def Tr.here(t: Tr) -> U32: Tr.next(t)

def Tr.emit.go(+refuse: Bool, +refused: Bool, +k: U32, a: U32, b: U32, c: U32,
               +calls: List<&2, Call>, +next: U32, +bad_at: U32,
               +seen: U32) -> Tr:
  Tr{Bool.pick(List<&2, Call>, refused, calls,
               List.append(&2, Call, calls, [Call{k, a, b, c}])),
     Bool.pick(U32, refused, next, U32.add(next, 1)), bad_at,
     Bool.pick(U32, refused, seen, U32.add(seen, 1)),
     Bool.or(refused, refuse)}

def Tr.emit(+k: U32, a: U32, b: U32, c: U32, t: Tr) -> Tr:
  match t:
    case Tr{calls, next, bad_at, seen, refused}:
      Tr.emit.go(False{}, refused, k, a, b, c, calls, next, bad_at, seen)

# THE RAISE SITE. The `bad_at`-th emit is the one that raises. See
# `Tr.emit.go`.
def Tr.raise(+k: U32, a: U32, b: U32, c: U32, t: Tr) -> Tr:
  match t:
    case Tr{calls, next, +bad_at, +seen, +refused}:
      Tr.emit.go(U32.is_eq(U32.add(seen, 1), bad_at), refused, k, a, b, c,
                 calls, next, bad_at, seen)

def Call.k(x: Call) -> U32:
  match x:
    case Call{k, a, b, c}: k

def Call.a(x: Call) -> U32:
  match x:
    case Call{k, a, b, c}: a

def Call.b(x: Call) -> U32:
  match x:
    case Call{k, a, b, c}: b

def Call.c(x: Call) -> U32:
  match x:
    case Call{k, a, b, c}: c

# ===========================================================================
# READING THE TRACE. `Tr.seq` is the `a` of every call with tag `k`, IN ORDER
# -- for a queue that is the sequence of slot indices and for the batch that is
# the sequence of step kinds. `Tr.count` is how many. `Tr.has` is "contains this
# (k, a, b, c) sequence, in order", and it is a real SUBSEQUENCE test: the fuel
# is the TRACE length and the answer is `at == patlen` (the bug ops_webgpu.bend
# measured, where a fuel set to the PATTERN length made a reversed pattern match).
# ===========================================================================

def Tr.count.go(n: Nat, +k: U32, cs: List<&2, Call>, +got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match cs:
        case Nil{}: got
        case Call{kk, aa, bb, cc} <> t:
          Tr.count.go(m, k, t, U32.add(got, Bool.to_u32(U32.is_eq(kk, k))))

def Tr.count(+k: U32, +cs: List<&2, Call>) -> U32:
  Tr.count.go(List.length(&2, Call, cs), k, cs, 0)

# a LEAF, because `Bool.pick` evaluates both arms and a recursive call inside
# one of them would branch the walk twice over.
def Tr.seq.put(+c: Call, +k: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, U32.is_eq(Call.k(c), k),
    List.append(&2, U32, acc, [Call.a(c)]), acc)

def Tr.seq.go(n: Nat, +k: U32, cs: List<&2, Call>, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match cs:
        case Nil{}: acc
        case Call{kk, aa, bb, cc} <> t: Tr.seq.go(m, k, t, Tr.seq.put(Call{kk, aa, bb, cc}, k, acc))

def Tr.seq(+k: U32, +cs: List<&2, Call>) -> List<&2, U32>:
  Tr.seq.go(List.length(&2, Call, cs), k, cs, Nil{})

def Tr.has.step.same(+c: Call, +w: Call) -> Bool:
  Bool.and(Bool.and(U32.is_eq(Call.k(c), Call.k(w)), U32.is_eq(Call.a(c), Call.a(w))),
           Bool.and(U32.is_eq(Call.b(c), Call.b(w)), U32.is_eq(Call.c(c), Call.c(w))))

def Tr.has.step.hit(same: Bool, at: Nat) -> Nat:
  match same:
    case True{}: Nat.add(at, 1n)
    case False{}: at

def Tr.has.step(m: Maybe<&2, Call>, +c: Call, at: Nat) -> Nat:
  match m:
    case None{}: at
    case Some{+want}: Tr.has.step.hit(Tr.has.step.same(c, want), at)

def Tr.has.go(n: Nat, +patlen: Nat, cs: List<&2, Call>, +pat: List<&2, Call>,
              +at: Nat) -> Bool:
  match n:
    case 0n: Nat.is_eq(at, patlen)
    case 1n+m:
      match cs:
        case Nil{}: Nat.is_eq(at, patlen)
        case Call{kk, aa, bb, cc} <> t:
          Tr.has.go(m, patlen, t, pat,
                    Tr.has.step(List.get(&2, Call, pat, at), Call{kk, aa, bb, cc}, at))

def Tr.has(+cs: List<&2, Call>, +pat: List<&2, Call>) -> Bool:
  Tr.has.go(List.length(&2, Call, cs), List.length(&2, Call, pat), cs, pat, 0n)

def Call.same(a: Call, b: Call) -> Call: a

def u32s_eq(+a: List<&2, U32>, +b: List<&2, U32>) -> Bool: H.u32_list_eq(a, b)

def nats_eq(+a: List<&2, U32>, +b: List<&2, U32>) -> Bool: H.u32_list_eq(a, b)

# ===========================================================================
# hcq2.py:63 `to_name(*parts) = "_".join(parts).replace(":", "_").lower()`.
#
# THE ORDER IS THE CLAIM: the replace is on the ORIGINAL case and the lower is
# LAST, so `to_name("submit", "NV", "COMPUTE:0")` is `submit_nv_compute_0` and
# not `submit_nv_compute:0`. `String.split` THROWS THE SEPARATORS AWAY, so the
# tail has to be re-joined with them -- `ops_nv.bend:2917` measured this exact
# bug and got `ring_compute0` where CPython prints `ring_compute_0`.
#
# `dev.bend`'s `rest_of` is the same fix with `:` where this needs `_`.
# ===========================================================================

def to_name.norm(+s: String) -> String:
  String.to_lower(String.join(String.split(s, ':'), "_"))

# `List.append(a, A, xs, ys)` is `xs ++ ys`, so the accumulator below is already
# in FORWARD order and the fold ends with a plain `String.concat`. Reversing it
# is the bug `ops_nv.bend:2934-2936` measured and recorded: it prints
# `0COMPUTE_` where CPython prints `COMPUTE_0`.
def to_name.go(parts: List<&2, String>, +acc: List<&2, String>) -> String:
  match parts:
    case Nil{}: String.concat(acc)
    case h <> Nil{}: String.concat(List.append(&2, String, acc, [to_name.norm(h)]))
    case h <> t: to_name.go(t, List.append(&2, String, acc, [String.concat([to_name.norm(h), "_"])]))

def to_name(+parts: List<&2, String>) -> String: to_name.go(parts, Nil{})

def to_name2(a: String, b: String) -> String: to_name([a, b])

def to_name3(a: String, b: String, c: String) -> String: to_name([a, b, c])

# ===========================================================================
# hcq2.py:38 `all_devices_in(d, c) = {x.split(":")[0] for x in to_tuple(d)} <= c`.
# A SUBSET, not a membership: two devices both in HCQ_DEVS is True, and the
# EMPTY device string is the empty set, which is a subset of everything. That
# last one is a fixture, not an oversight -- `hc2_all_in_empty` is a row.
# ===========================================================================

def all_in.go(+ds: List<&2, String>, nm: String, hit: Bool) -> Bool:
  match ds:
    case Nil{}: hit
    case h <> t: all_in.go(t, nm, Bool.or(hit, U32.is_ne(dev_id(dev_head(h)), NO_HCQ_DEV())))

def all_in(+ds: List<&2, String>) -> Bool: all_in.go(ds, "", True{})

# ===========================================================================
# hcq2.py:69-76 `layout_args`. THE CITED ONE -- ops_nv.bend names it at :14,
# :181, :205, :1439, :1873 and :1892.
#
#   words = [a if isinstance(a, UOp) else UOp.const(a, dtypes.uint32) for a in args]
#   return [(offset + o, w) for (o,_), w in zip(TinyELF.iter_sig(...), words)]
#
# So it is `iter_sig` and a base offset, and an `int` in the argument list
# becomes a FOUR-byte word (`:75`'s `UOp.const(a, dtypes.uint32)`) -- which is
# why `ints` below lays out as 0, 4, 8 and not 0, 8, 16.
#
# THE WALRUS IS LOAD-BEARING, and it lives in `device.bend`: `iter_sig` yields
# `(offset := round_up(offset, dt.itemsize)), dt; offset += dt.itemsize`, so the
# advance is `round_up(off, k) + k`. See `ops_nv.bend:1439-1452` and
# `device.bend:869-895`. This file CONSUMES `D.iter_sig` rather than
# re-deriving it, and `hq2_layout_*_matches_device_bend` is the cross-check:
# two independent readings of the same walrus agreeing is the claim.
# ===========================================================================

def layout.go(n: Nat, +slots: List<&2, U32>, +ks: List<&2, U32>,
              +base: U32, +acc: List<&2, Arg>) -> List<&2, Arg>:
  match n:
    case 0n: acc
    case 1n+m:
      match slots:
        case Nil{}: acc
        case s <> st:
          match ks:
            case Nil{}: acc
            case k <> kt: layout.go(m, st, kt, base,
              List.append(&2, Arg, acc, [Arg{U32.add(base, s), k}]))

def layout(+ks: List<&2, U32>, base: U32) -> List<&2, Arg>:
  layout.go(List.length(&2, U32, ks), D.iter_sig(ks), ks, base, Nil{})

def layout_at.pick(m: Maybe<&2, Arg>) -> U32:
  match m:
    case Some{g}: Arg.at(g)
    case None{}: 0

def layout_at(+ks: List<&2, U32>, base: U32, n: Nat) -> U32:
  layout_at.pick(List.get(&2, Arg, layout(ks, base), n))

def layout_n(+ks: List<&2, U32>) -> U32: U32.from_nat(List.length(&2, Arg, layout(ks, 0)))

def layout_off.go(n: Nat, as: List<&2, Arg>, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match as:
        case Nil{}: acc
        case a <> t: layout_off.go(m, t, List.append(&2, U32, acc, [Arg.at(a)]))

def layout_ks(+ks: List<&2, U32>, base: U32) -> List<&2, U32>:
  layout_off.go(List.length(&2, U32, ks), layout(ks, base), Nil{})

def layout_k.go(n: Nat, as: List<&2, Arg>, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match as:
        case Nil{}: acc
        case a <> t: layout_k.go(m, t, List.append(&2, U32, acc, [Arg.k(a)]))

def layout_ts(+ks: List<&2, U32>, base: U32) -> List<&2, U32>:
  layout_k.go(List.length(&2, U32, ks), layout(ks, base), Nil{})

# ===========================================================================
# hcq2.py:73-83 `pack_args`. THE WORD SEQUENCE, and two things about it are easy
# to get wrong:
#
#   1. A PAD IS A WORD. `[UOp(Ops.BINARY, arg=bytes(offset - end)), arg]` and
#      `[arg]` are both appended, and `bytes(0)` is `b''` -- which is still a
#      `BINARY` in the output. So `pack_args` of a three-u64 list into 24 bytes
#      is FOUR words, the last of them an EMPTY pad, and dropping it loses a
#      word. `hq2_pack_buf3_0_24` and `hq2_pack_empty_0` are the rows.
#   2. THE TRAILING PAD IS `size - end` AND IT CAN BE NEGATIVE. :83 is
#      `bytes(size - end)`; with `end > size` CPython raises `ValueError:
#      negative count`. `hq2_pack_mixed_0_24` is the refusal row -- a gate that
#      cannot see a raise cannot tell a truncation from a short read.
#
# `sorted(args, key=lambda x: x[0])` (:80) IS A WALL: base.bend has no `sort`
# without a closure, and the only in-tree caller is `layout`, whose output is
# ascending BY CONSTRUCTION. So `pack` takes ASCENDING rows as a precondition
# and `hq2_layout_is_ascending` is the row that makes it true rather than an
# assumption.
# ===========================================================================
def PK_PAD() -> U32: 0
def PK_WORD() -> U32: 1
def PK_ERR() -> U32: 2

# ONE word of the packed stream: `P<n>` is a `BINARY` of `n` zero bytes and
# `W<k>` is a word of `k` bytes. `E` is the `ValueError` of :83.
type Pk is Data:
  Pk{k: U32, n: U32}

def Pk.k(x: Pk) -> U32:
  match x:
    case Pk{k, n}: k

def Pk.n(x: Pk) -> U32:
  match x:
    case Pk{k, n}: n

# `words += [BINARY(bytes(offset - end)), arg] if offset != end else [arg]` --
# one arm emits two words and the other emits one. `gap_zero` is the COMPARISON
# and not `gap`, because a Bool from a leaf call may not be `match`ed and
# `Bool.pick` would need `gap` twice. See THE `+` ALIASES BETWEEN TWO ARGUMENTS
# for why the two shapes are not interchangeable here: the `Bool.pick` version
# answered `W8 P0 W8 P0 W8 P0 P0` where CPython answers `W8 W8 W8 P0`.
def pack.pad(n: U32) -> Pk: Pk{PK_PAD(), n}

def pack.word(+k: U32) -> Pk: Pk{PK_WORD(), k}

# `words, end = [], 0` (tinygrad/runtime/support/hcq2.py:74) and `end = offset + arg.dtype.itemsize`
# (:82) -- `end` starts at ZERO and not at the first offset, which is why a
# non-zero base becomes a LEADING pad.
def end_of.go(n: Nat, +as: List<&2, Arg>, +end: U32) -> U32:
  match n:
    case 0n: end
    case 1n+m:
      match as:
        case Nil{}: end
        case a <> t: end_of.go(m, t, U32.add(Arg.at(a), Arg.k(a)))

def end_of(+as: List<&2, Arg>) -> U32: end_of.go(List.length(&2, Arg, as), as, 0)

def pack.step(gap_zero: Bool, gap: U32, sz: U32, +acc: List<&2, Pk>) -> List<&2, Pk>:
  match gap_zero:
    case True{}: List.append(&2, Pk, acc, [Pk{PK_WORD(), sz}])
    case False{}: List.append(&2, Pk, List.append(&2, Pk, acc, [Pk{PK_PAD(), gap}]), [Pk{PK_WORD(), sz}])

def pack.go(n: Nat, +as: List<&2, Arg>, +end: U32, +acc: List<&2, Pk>) -> List<&2, Pk>:
  match n:
    case 0n: acc
    case 1n+m:
      match as:
        case Nil{}: acc
        case a <> t:
          pack.go(m, t, U32.add(Arg.at(a), Arg.k(a)),
                  pack.step(U32.is_eq(U32.sub(Arg.at(a), end), 0), U32.sub(Arg.at(a), end),
                            Arg.k(a), acc))


# THE WHOLE THING. `too_big` is the COMPARISON and not the subtraction, for the
# reason in THE `+` ALIASES BETWEEN TWO ARGUMENTS: a Bool from a leaf call may
# not be `match`ed, and the pick would need the accumulator twice. The trailing
# pad is therefore OUTSIDE the pick and inside `pack.wrap`, which is the
# `bytes(size - end)` of :83 -- a short `size` answers `E`, not a negative pad.
def pack.wrap(too_big: Bool, +tail: U32, +ws: List<&2, Pk>) -> List<&2, Pk>:
  match too_big:
    case True{}: [Pk{PK_ERR(), 0}]
    case False{}: List.append(&2, Pk, ws, [Pk{PK_PAD(), tail}])

def pack.trail(+as: List<&2, Arg>, +size: U32) -> List<&2, Pk>:
  pack.wrap(U32.is_gt(end_of(as), size), U32.sub(size, end_of(as)),
            pack.go(List.length(&2, Arg, as), as, 0, Nil{}))

def pkind(+k: U32) -> String:
  match k:
    case 0: "P"
    case 1: "W"
    case _: "E"

def pk_one(+x: Pk) -> String: String.concat([" ", pkind(Pk.k(x)), U32.show(Pk.n(x))])

def pack_pks(xs: List<&2, Pk>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case x <> t: pack_pks(t, List.append(&2, String, acc, [pk_one(x)]))

def pk_str(+xs: List<&2, Pk>) -> String: String.drop(String.concat(pack_pks(xs, Nil{})), 1n)


# ===========================================================================
# hcq2.py:100-106 `cstruct` / `cfield`. THE QUEUE-DESCRIPTOR PACKING, and the
# two things that matter are the FIELD NAMES and the FIELD ORDER.
#
# :101 `{n: (o, CDTYPE[ctypes.sizeof(t)]) for n, t, o, *_ in struct_t._real_fields_
# if ctypes.sizeof(t)}` is the FIELD TABLE, keyed by NAME. :102 builds `rows`
# from the CALLER'S kwargs, so the ROW ORDER is the kwargs order and not the
# struct order:
#     ops_qcom.py:197  cstruct(struct_kgsl_command_object, gpuaddr=..., size=..., flags=...)
#     ops_qcom.py:198  cstruct(struct_kgsl_gpu_command, cmdlist=..., cmdsize=..., numcmds=...,
#                                        context_id=...)
# `ops_cl`'s unit found `Sig`'s field names INVERTED and a correct computation
# looked wrong, so both directions are rows: `hq2_cstruct_*_order` is
# name-in-source-order and `hq2_cfield_*_at` / `_sz` are name -> offset/size.
#
# The two tables below are the qcom descriptors, MEASURED by calling
# `kgsl.struct_kgsl_command_object._real_fields_` and
# `kgsl.struct_kgsl_gpu_command._real_fields_` (hcq2-oracle.py `cstruct()`).
# ===========================================================================
def f_ib() -> List<&2, Fld>:
  [Fld{0, "offset", 0, 8}, Fld{1, "gpuaddr", 8, 8}, Fld{2, "size", 16, 8},
   Fld{3, "flags", 24, 4}, Fld{4, "id", 28, 4}]

def f_cmd() -> List<&2, Fld>:
  [Fld{0, "flags", 0, 8}, Fld{1, "cmdlist", 8, 8}, Fld{2, "cmdsize", 16, 4},
   Fld{3, "numcmds", 20, 4}, Fld{4, "objlist", 24, 8}, Fld{5, "objsize", 32, 4},
   Fld{6, "numobjs", 36, 4}, Fld{7, "synclist", 40, 8}, Fld{8, "syncsize", 48, 4},
   Fld{9, "numsyncs", 52, 4}, Fld{10, "context_id", 56, 4}, Fld{11, "timestamp", 60, 4}]

def fld_at.go(n: Nat, fs: List<&2, Fld>, +nm: String, d: U32) -> U32:
  match n:
    case 0n: d
    case 1n+m:
      match fs:
        case Nil{}: d
        case +f <> t: fld_at.go(m, t, nm, Bool.pick(U32, String.eq(Fld.name(f), nm), Fld.at(f), d))

def fld_at(+fs: List<&2, Fld>, nm: String) -> U32:
  fld_at.go(List.length(&2, Fld, fs), fs, nm, 0)

def fld_sz.go(n: Nat, fs: List<&2, Fld>, +nm: String, d: U32) -> U32:
  match n:
    case 0n: d
    case 1n+m:
      match fs:
        case Nil{}: d
        case +f <> t: fld_sz.go(m, t, nm, Bool.pick(U32, String.eq(Fld.name(f), nm), Fld.sz(f), d))

def fld_sz(+fs: List<&2, Fld>, nm: String) -> U32:
  fld_sz.go(List.length(&2, Fld, fs), fs, nm, 0)

# `ctypes.sizeof(struct_t)` (:103, :104) -- the sum of the field sizes with the
# tail PADDED to the struct's alignment, which for both qcom descriptors is the
# last offset plus its own size.
def fld_sizeof.go(n: Nat, fs: List<&2, Fld>, +last: U32, +size: U32) -> U32:
  match n:
    case 0n: size
    case 1n+m:
      match fs:
        case Nil{}: size
        case +f <> t: fld_sizeof.go(m, t, U32.add(Fld.at(f), Fld.sz(f)),
                                    U32.max(size, U32.add(Fld.at(f), Fld.sz(f))))

def fld_sizeof(+fs: List<&2, Fld>) -> U32: fld_sizeof.go(List.length(&2, Fld, fs), fs, 0, 0)

def fld_n(+fs: List<&2, Fld>) -> U32: U32.from_nat(List.length(&2, Fld, fs))

# :102 `rows = [(flds[n][0], v.cast(flds[n][1]) if isinstance(v, UOp) else
# UOp.const(v, flds[n][1])) for n, v in fields.items()]` -- ONE ROW PER KWARG, in
# kwargs order, at the field's own offset and cast to the field's CDTYPE. The
# `ib` and `cmd` tables below are ops_qcom.py:197-198 verbatim, and
# `hq2_cstruct_ib_rows` / `hq2_cstruct_cmd_rows` are the `<off>:<itemsize>` list.
def cstruct_ib_rows() -> List<&2, U32>: [8, 16, 24]

def cstruct_cmd_rows() -> List<&2, U32>: [8, 16, 20, 56]

# AND THE CDTYPE EACH ROW IS CAST TO (hcq2.py:89's `v.cast(flds[n][1])`), which
# is `flds[n][1].itemsize`. A descriptor that carries the right offset and the
# wrong width writes the right bytes at the wrong scale.
def cstruct_cmd_rows_k() -> List<&2, U32>: [8, 4, 4, 4]

# the NAMES, in source order -- the direction that a renamed field breaks.
def fld_names.go(n: Nat, fs: List<&2, Fld>, +acc: List<&2, String>) -> List<&2, String>:
  match n:
    case 0n: acc
    case 1n+m:
      match fs:
        case Nil{}: acc
        case f <> t: fld_names.go(m, t, List.append(&2, String, acc, [Fld.name(f)]))

def fld_names(+fs: List<&2, Fld>) -> List<&2, String>:
  fld_names.go(List.length(&2, Fld, fs), fs, Nil{})

def fld_offs.go(n: Nat, fs: List<&2, Fld>, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match fs:
        case Nil{}: acc
        case f <> t: fld_offs.go(m, t, List.append(&2, U32, acc, [Fld.at(f)]))

def fld_offs(+fs: List<&2, Fld>) -> List<&2, U32>:
  fld_offs.go(List.length(&2, Fld, fs), fs, Nil{})

def fld_szlist.go(n: Nat, fs: List<&2, Fld>, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match fs:
        case Nil{}: acc
        case f <> t: fld_szlist.go(m, t, List.append(&2, U32, acc, [Fld.sz(f)]))

def fld_szs(+fs: List<&2, Fld>) -> List<&2, U32>:
  fld_szlist.go(List.length(&2, Fld, fs), fs, Nil{})

# :101 skips a field of size 0 (`if ctypes.sizeof(t)`), and :104's
# `buf[...]` blob is `bytes(ctypes.sizeof(struct_t))`. BOTH tables have no
# zero-length field, so `hq2_cstruct_*_nfields` and `hq2_cstruct_*_nreal` are the
# SAME number -- and that is the row which says the filter did nothing here
# rather than the row which says it is unnecessary.
def fld_real.go(n: Nat, fs: List<&2, Fld>, +got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match fs:
        case Nil{}: got
        case +f <> t: fld_real.go(m, t, U32.add(got, Bool.to_u32(cdtype.is(Fld.sz(f)))))

def fld_real(+fs: List<&2, Fld>) -> U32: fld_real.go(List.length(&2, Fld, fs), fs, 0)

# :101 `CDTYPE[ctypes.sizeof(t)]` -- the field's dtYPE is the unsigned int of
# its SIZE, so `fld_cdts` IS `fld_szs` re-asked. The two lists being the same
# number is the claim; a port that invented a per-field dtype would disagree.
def fld_cdt.go(n: Nat, fs: List<&2, Fld>, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match fs:
        case Nil{}: acc
        case +f <> t: fld_cdt.go(m, t, List.append(&2, U32, acc, [cdtype_of(Fld.sz(f))]))

def fld_cdts(+fs: List<&2, Fld>) -> List<&2, U32>:
  fld_cdt.go(List.length(&2, Fld, fs), fs, Nil{})

# the REVERSE direction of the field table: an OFFSET NAMES ITS FIELD. A struct
# that shifted a field would still answer every `fld_at` row and would move
# these, and the shift is what a mismatched autogen header looks like.
def fld_name.go(n: Nat, fs: List<&2, Fld>, +at: U32, d: String) -> String:
  match n:
    case 0n: d
    case 1n+m:
      match fs:
        case Nil{}: d
        case +f <> t: fld_name.go(m, t, at, Bool.pick(String, U32.is_eq(Fld.at(f), at), Fld.name(f), d))

def fld_name(+fs: List<&2, Fld>, at: U32) -> String:
  fld_name.go(List.length(&2, Fld, fs), fs, at, "")

def fstr.go(n: Nat, xs: List<&2, String>, +acc: List<&2, String>) -> List<&2, String>:
  match n:
    case 0n: acc
    case 1n+m:
      match xs:
        case Nil{}: acc
        case h <> t: fstr.go(m, t, List.append(&2, String, acc, [String.concat([" ", h])]))

def fstr(+xs: List<&2, String>) -> String: String.drop(String.concat(fstr.go(List.length(&2, String, xs), xs, Nil{})), 1n)
def pk_n(+xs: List<&2, Pk>) -> U32: U32.from_nat(List.length(&2, Pk, xs))

def pk_last(+xs: List<&2, Pk>) -> Pk: Maybe.default(&2, Pk, List.last(&2, Pk, xs), Pk{PK_ERR(), 0})

# ===========================================================================
# THE FIXTURES, and each one is a dtype ITEMSIZE list because that is the only
# thing `layout_args` reads (tinygrad/runtime/support/hcq2.py:71 builds `w.dtype` from the word).
#
# `MIXED` is THE FIXTURE. Every uniform list agrees with an implementation that
# advances off the UNROUNDED offset, because with all widths equal to `k` the
# two agree at every step. `MIXED` has a uint16 at slot 8 which ends at 10 and a
# ulong after it which is padded to 16, and that is the ONLY thing in this file
# that can see the walrus. It is the same list `ops_nv.bend:205` prints.
# ===========================================================================
def BUF3() -> List<&2, U32>: [8, 8, 8]
def MIXED() -> List<&2, U32>: [1, 4, 2, 8, 4, 1]
def FIVE32() -> List<&2, U32>: [4, 4, 4, 4, 4]
def INTS() -> List<&2, U32>: [4, 4, 4]
def ONE16() -> List<&2, U32>: [2]
def ODD() -> List<&2, U32>: [4, 1, 8]

# `D.iter_sig` on its own -- what `device.bend` holds, read WITHOUT the base
# offset. The cross-check against `layout` is the claim.
def device_sig_ks(+ks: List<&2, U32>) -> List<&2, U32>: D.iter_sig(ks)

# IS THE OUTPUT ASCENDING? `pack` takes ascending rows as a precondition
# because base.bend has no `sort` without a closure (hcq2.py:80's
# `sorted(args, key=lambda x: x[0])`). This is the row that makes the
# precondition true rather than assumed, and it is checked on the list `pack`
# is actually handed -- not on a list chosen to be sorted.
def asc.go(n: Nat, +xs: List<&2, U32>, prev: U32) -> Bool:
  match n:
    case 0n: True{}
    case 1n+m:
      match xs:
        case Nil{}: True{}
        case h <> t: asc.go(m, t, h) && U32.is_le(prev, h)

def ascending(+xs: List<&2, U32>) -> Bool:
  match xs:
    case Nil{}: True{}
    case h <> t: asc.go(List.length(&2, U32, t), t, h)

# ===========================================================================
# THE GATE. One row per claim, and every `py=` expectation is the value CPython
# answered when `.agents/slop/hcq2-probe.py` (or `-probe2.py`) CALLED hcq2.py
# with DEV=NULL and no device present. Nothing here is hand-typed: four times in
# this project a hand-typed expectation was the bug, and `nv_query_litter` was
# wrong in the PORT *and* the ORACLE, so "the port and the oracle agree" is not
# corroboration -- it is one mistake copied.
# ===========================================================================

def row(nm: String, b: Bool) -> IO(Unit):
  IO.print(String.concat([nm, "=", Bool.show(b)]))

def urow(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

def srow(nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

# a list of U32 as `0 4 8 16 24 28`, which is exactly how the oracle prints
# `[o for o, _ in layout_args(...)]` -- so the two strings are compared, not
# the two numbers.
# THE SEPARATOR GOES IN FRONT OF EVERY ELEMENT AND THE FIRST ONE IS DROPPED.
# The obvious shape -- "no separator on the first element", decided by
# `List.is_empty(acc)` -- IS WRONG IN BOTH LANES, and the reason is worth
# recording: see THE `+` ALIASES BETWEEN TWO ARGUMENTS above. `String.length(sep)`
# is the drop count, so a two-character separator works with no extra def.
def ush(xs: List<&2, U32>, +sep: String, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case h <> t: ush(t, sep, List.append(&2, String, acc, [String.concat([sep, U32.show(h)])]))

def joined(+xs: List<&2, U32>, +sep: String) -> String:
  String.drop(String.concat(ush(xs, sep, Nil{})), String.length(sep))

def lrow(nm: String, +xs: List<&2, U32>) -> IO(Unit):
  srow(nm, joined(xs, " "))

def bstr(+xs: List<&2, U32>) -> String: joined(xs, "")

def brow(nm: String, +xs: List<&2, U32>) -> IO(Unit):
  IO.print(String.concat([nm, "=", bstr(xs)]))


# ===========================================================================
# THE BATCH: hcq2.py:209-311. THE FENCE AND COMPLETION MODEL, and almost all of
# it is ORDER, so almost all of it is a trace.
#
# WHAT SURVIVES THE ARENA WALK: a batch is a list of (call, devices, queue)
# triples and a call touches TWO buffers -- `get_call_outs_ins(call)[0]` is
# `(0,)` in every fixture, so ranges[0] is WRITTEN and ranges[1] is READ. That is
# the whole of `DepsTracker.access_resources` (:182-207) for these shapes.
#
# DEVICE IDS: 1 is `NULL:0` (the enqueue device) and 2 is `NULL`, its
# `Device.canonicalize` -- which is what :227 puts in `ctx.peers` and what makes
# a SECOND device with no calls appear in the output. QUEUE IDS: 1 is
# `COMPUTE:0`, 2 is `COPY:0`, 3 is `COPY:1`. BUFFER IDS 1..6 are `a`..`f`.
# ===========================================================================

def DEV_N0() -> U32: 1
def DEV_N() -> U32: 2
def Q_COMPUTE() -> U32: 1
def Q_COPY0() -> U32: 2
def Q_COPY1() -> U32: 3

# ONE enqueued call. `w` is the buffer at ranges[0] (WRITTEN) and `r` the buffer
# at ranges[1] (READ).
type E is Data:
  E{dev: U32, q: U32, w: U32, r: U32}

def E.dev(x: E) -> U32:
  match x:
    case E{dev, q, w, r}: dev

def E.q(x: E) -> U32:
  match x:
    case E{dev, q, w, r}: q

def E.w(x: E) -> U32:
  match x:
    case E{dev, q, w, r}: w

def E.r(x: E) -> U32:
  match x:
    case E{dev, q, w, r}: r

# ONE `Ops.INS` in a queue's command stream, or one `Ops.CALL`. An INS is
# `UOp(Ops.INS, arg=("wait", dtypes.void), src=(dst, val))`, so the KIND is the
# identity and the operands are what the gate reads:
#   BARRIER    :255     a = 0
#   WAIT       :252     a = the queue-signal slot (2*queue index), b = t + 1
#   WAIT       :256     a = TIMELINE_MARK, b = the device id -- a queue's START
#                       wait is on the device TIMELINE, not on a slot
#   TIMESTAMP  :266     a = the slot index
#   STORE      :271     a = the queue-signal slot, b = tag + 1
#   BUMP       :278     a = TIMELINE_MARK, b = the device id, c = 1
#   CALL                a = the batch tag
def I_BARRIER() -> U32: 1
def I_WAIT() -> U32: 2
def I_TIMESTAMP() -> U32: 3
def I_STORE() -> U32: 4
def I_BUMP() -> U32: 5
def I_CALL() -> U32: 6
def TIMELINE_MARK() -> U32: 4294967295

type Ins is Data:
  Ins{k: U32, a: U32, b: U32, c: U32}

def Ins.k(x: Ins) -> U32:
  match x:
    case Ins{k, a, b, c}: k

# THE STEP NAME, and it is what `hq2-oracle2.py`'s `step()` builds from
# `u.op is Ops.INS` and `u.arg[0]`. `BUMP` and `STORE` are ONE Python INS each
# -- `("store", dtypes.void)` -- spelled apart here because :278's timeline store
# and :271's queue-signal store are the same Python step on DIFFERENT operands.
# Both print `INS_store`; `hq2_b*_q_*` compares the sequences as CPython sees
# them, and `hq2_bthree_bump_*` is the row that tells the two apart.
def ikind(+k: U32) -> String:
  match k:
    case 1: "barrier"
    case 2: "wait"
    case 3: "timestamp"
    case _: "store"

def iname(x: Ins) -> String:
  match x:
    case Ins{6, a, b, c}: "call"
    case Ins{k, a, b, c}: String.concat(["INS_", ikind(k)])

# THE BATCH FIXTURES. Five SHAPES, because ONE FIXTURE CANNOT TELL A FIRST-WINS
# RULE FROM A LAST-WINS RULE and the `signal_tags` rule at :230 is exactly that:
# it reads `self.last`, which holds ONE tag per queue. `three` is three queues,
# `two` is two calls on ONE queue with overlapping buffers, `fifo` is two calls
# on one queue with DISJOINT buffers, `copyq` is two queues, `revis` is three
# calls on one queue.
def Ethree() -> List<&2, E>: [E{1, 1, 1, 2}, E{1, 2, 2, 3}, E{1, 3, 3, 1}]

def Etwo() -> List<&2, E>: [E{1, 1, 1, 2}, E{1, 1, 2, 1}]

def Efifo() -> List<&2, E>: [E{1, 1, 1, 2}, E{1, 1, 3, 4}]

def Ecopyq() -> List<&2, E>: [E{1, 1, 1, 2}, E{1, 2, 3, 1}]

def Erevis() -> List<&2, E>: [E{1, 1, 1, 2}, E{1, 1, 3, 4}, E{1, 1, 2, 5}]

# ===========================================================================
# `ctx.queues` (:224) -- the queue list PER DEVICE, in FIRST-USE order, because
# `if q not in self.queues.setdefault(devs[0], []): append(q)`. The ORDER is the
# claim: `qsig` numbers the queues by it and the epilogue walks it.
# ===========================================================================
def is_pair(+x: E, dev: U32, +q: U32) -> Bool:
  Bool.and(U32.is_eq(E.dev(x), dev), U32.is_eq(E.q(x), q))

def seenq.go(n: Nat, +bs: List<&2, E>, +dev: U32, +q: U32, hit: Bool) -> Bool:
  match n:
    case 0n: hit
    case 1n+m:
      match bs:
        case Nil{}: hit
        case b <> t: seenq.go(m, t, dev, q, Bool.or(hit, is_pair(b, dev, q)))

def seenq(+bs: List<&2, E>, dev: U32, +q: U32) -> Bool: seenq.go(List.length(&2, E, bs), bs, dev, q, False{})

# ONE SELF-CALL PER ARM, which is what Bend allows: the arm is a `match` on a
# Bool PARAMETER and each arm makes one recursive call. The obvious
# `Bool.pick(..., qlist.go(...), qlist.go(...))` is a mutual two-call in one
# THE HEAD OF A LIST, as an `E`. The folds below carry the head EXPLICITLY and
# recurse on the tail, because computing the NEXT entry's flag from the CURRENT
# head answers the flag about the wrong element -- a bug that made `three`'s three
# queues read as two, and it is the kind of bug no boolean row sees.
def ehd.at(m: Maybe<&2, E>) -> E:
  match m:
    case Some{g}: g
    case None{}: E{0, 0, 0, 0}

def ehd(+xs: List<&2, E>) -> E: ehd.at(List.head(&2, E, xs))

# ONE SELF-CALL PER ARM. `Bool.pick(..., qlist.go(...), qlist.go(...))` is two
# self-calls in one expression and is REFUSED, and hoisting it into a `def` that
# calls back here is a mutual recursion and is refused too -- so the `match` on
# the Bool PARAMETER goes INSIDE the fold.
def qlist.new(+b: E, +t: List<&2, E>, +dev: U32) -> Bool:
  Bool.and(U32.is_eq(E.dev(b), dev), Bool.not(seenq(t, dev, E.q(b))))

def qlist.next(+rest: List<&2, E>, +dev: U32) -> Bool:
  qlist.new(ehd(rest), List.tail(&2, E, rest), dev)


def qlist.go(n: Nat, +rest: List<&2, E>, +dev: U32, +is_new: Bool,
             +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match is_new:
        case True{}: qlist.go(m, List.tail(&2, E, rest), dev,
                               qlist.next(List.tail(&2, E, rest), dev),
                               List.append(&2, U32, acc, [E.q(ehd(rest))]))
        case False{}: qlist.go(m, List.tail(&2, E, rest), dev,
                               qlist.next(List.tail(&2, E, rest), dev), acc)

# THE FLAG OF THE HEAD OF `rest`, which is `qlist.new` against `rest`'s TAIL. The
# two places that compute it -- here and in `qlist` -- MUST both drop the head, or
# a queue answers "already seen" against itself and the fold stops after one
# element. That is what made `three` read as one queue.
# `seenq` MUST SEE THE TAIL AND NOT THE LIST: the head is the candidate, so
# asking the WHOLE list answers "this queue has been seen" about the head itself
# and `qlist` answers 0 for a batch that has queues in it.
def qlist(+bs: List<&2, E>, +dev: U32) -> List<&2, U32>:
  qlist.go(List.length(&2, E, bs), bs, dev,
           qlist.new(ehd(bs), List.tail(&2, E, bs), dev), Nil{})

# `nq(dev)` -- `len(ctx.queues[dev])`: a count of DISTINCT QUEUES and not of
# calls, so `revis`'s three calls on one queue answer 1. `hq2_b*_nq` is the row.
def nq(+bs: List<&2, E>, dev: U32) -> U32: U32.from_nat(List.length(&2, U32, qlist(bs, dev)))

# THE DISTINCT (device, queue) PAIRS, in first-use order. That is the key order
# of the `queues` dict `_build_queues` returns, so it is the order the gate prints
# the per-queue sequences in. THE SAME HEAD-EXPLICIT SHAPE as `qlist`.
def pseen.go(n: Nat, +ps: List<&2, E>, +x: E, hit: Bool) -> Bool:
  match n:
    case 0n: hit
    case 1n+m:
      match ps:
        case Nil{}: hit
        case p <> t: pseen.go(m, t, x, Bool.or(hit, is_pair(p, E.dev(x), E.q(x))))

def pseen(+ps: List<&2, E>, +x: E) -> Bool: pseen.go(List.length(&2, E, ps), ps, x, False{})

# THE DISTINCT (device, queue) PAIRS, in first-use order. That is the key order of
# the `queues` dict `_build_queues` returns, so it is the order the gate prints the
# per-queue sequences in.
#
# IT IS BUILT FROM `qlist`, NOT FROM A SECOND FOLD, and that is deliberate: two
# folds over the same list with the same first-use rule is the shape where a
# second implementation can disagree with the first on the MIDDLE element and no
# boolean row sees it. MEASURED: a hand-rolled `pairs` over `Ethree` dropped the
# `COPY:0` pair -- `sig_tags` answered `0 2` where CPython answers `0 1 2` -- while
# `nq` and `qsig`, which read `qlist`, were right throughout. So `pairs` DERIVES
# FROM `qlist`, there is ONE first-use fold in this file, and `hq2_b*_sig_tags` is
# the row that holds both of them to the same answer.
#
# THE `w`/`r` OF A SYNTHESISED PAIR IS ZERO and is never read: `pairs` answers the
# (device, queue) key only, and every buffer range comes from `elem(bs, tag)`.
def pairs.go(n: Nat, +qs: List<&2, U32>, +acc: List<&2, E>) -> List<&2, E>:
  match n:
    case 0n: acc
    case 1n+m:
      match qs:
        case Nil{}: acc
        case q <> t: pairs.go(m, t, List.append(&2, E, acc, [E{DEV_N0(), q, 0, 0}]))

def pairs(+bs: List<&2, E>) -> List<&2, E>:
  pairs.go(List.length(&2, U32, qlist(bs, DEV_N0())), qlist(bs, DEV_N0()), Nil{})

def npairs(+bs: List<&2, E>) -> U32: U32.from_nat(List.length(&2, E, pairs(bs)))

def elem.go(n: Nat, +bs: List<&2, E>, +k: U32, +got: E) -> E:
  match n:
    case 0n: got
    case 1n+m:
      match bs:
        case Nil{}: got
        case +b <> t: elem.go(m, t, U32.sub(k, 1), Bool.pick(E, U32.is_zero(k), b, got))

# `qidx` -- `self.queues[devs[0]].index(queue)` (:238). `got` is index+1 so that
# index 0 and "not found" do not collide.

# ONE entry of a list by TAG, and a batch of size 0 has no entry -- the callers
# never ask for one.
def elem(+bs: List<&2, E>, k: U32) -> E: elem.go(List.length(&2, E, bs), bs, k, E{1, 1, 0, 0})


def qidx.go(n: Nat, +qs: List<&2, U32>, +q: U32, +i: U32, +got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match qs:
        case Nil{}: got
        case h <> t: qidx.go(m, t, q, U32.add(i, 1),
                             Bool.pick(U32, Bool.and(U32.is_eq(h, q), U32.is_zero(got)), U32.add(i, 1), got))

def qidx1(+qs: List<&2, U32>, q: U32) -> U32: qidx.go(List.length(&2, U32, qs), qs, q, 0, 0)

def qidx(+qs: List<&2, U32>, q: U32) -> U32: U32.sub(qidx1(qs, q), 1)

# `qsig` (:238) and `slot` (:237): a signal slot is at `2 * index` and TWO u64
# wide. `hq2_geom_slotw` is the width and `hq2_b*_qsig*` the index.
def qsig(+bs: List<&2, E>, dev: U32, q: U32) -> U32: U32.mul(2, qidx(qlist(bs, dev), q))

# `sched_timeline` (:239) is the slot AFTER every queue: `2 * nq(dev)`.
def stl(+bs: List<&2, E>, dev: U32) -> U32: U32.mul(2, nq(bs, dev))

# `stamps` (:240) `(st := len(self.queues[devs[0]])+1+2*tag, st+1) if self.profile
# else ()`. THE `n -> n*2`: TWO stamps per call, starting AFTER the queues and the
# scheduler timeline, which is why the base is `nq + 1` and not `nq`.
def stamp_n(+bs: List<&2, E>, +tag: U32, +profile: Bool) -> U32:
  Bool.pick(U32, profile, U32.add(U32.add(nq(bs, DEV_N0()), 1), U32.mul(2, tag)), 0)

def stamps(+bs: List<&2, E>, +tag: U32, +profile: Bool) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, profile, [stamp_n(bs, tag, profile),
                                    U32.add(stamp_n(bs, tag, profile), 1)], Nil{})

# `ctx.slots[dev]` (:232) `2 * (len(qs) + 1 + (2*len(batch) if profile else 0))`
# -- one signal per queue, plus one scheduler timeline, plus two stamps per call,
# all u64. THE LEADING `2 *` IS THE WHOLE FORMULA.
def slot_words(+bs: List<&2, E>, profile: Bool) -> U32:
  U32.add(U32.add(nq(bs, DEV_N0()), 1),
          Bool.pick(U32, profile, U32.mul(2, U32.from_nat(List.length(&2, E, bs))), 0))

def slot_bytes(+bs: List<&2, E>, profile: Bool) -> U32: U32.mul(2, slot_words(bs, profile))

# THE PEER DEVICE'S SLOTS. `slots['NULL']` is the canonicalized device's slots
# and it has NO queues and NO calls, so it is `2 * (0 + 1 + 2*3)` when profiling
# and `2 * (0 + 1)` when not. It is the row that separates "slots per device"
# from "slots for the whole batch", and the peer exists ONLY because
# `Device.canonicalize('NULL:0')` is `'NULL'`.
def peer_slot_words(profile: Bool) -> U32: Bool.pick(U32, profile, 7, 1)

def peer_slot_bytes(profile: Bool) -> U32: U32.mul(2, peer_slot_words(profile))

# ===========================================================================
# `ctx.last` (:226) and `ctx.prev` (:225). `last[(dev, q)] = tag` is OVERWRITTEN,
# so `last` holds the LAST tag of each queue and `prev[tag]` is whatever tag held
# the slot before it -- NONE for the first call on a queue. :249 is the only
# reader of `prev` and it is the NV QMD-chaining workaround, so nothing in these
# fixtures reads it. `hq2_b*_prev` is the row that says so out loud rather than
# leaving it untested, and `prev_or_self` is :249's `p` when it is not None.
# ===========================================================================
def lasttag.go(n: Nat, +bs: List<&2, E>, +dev: U32, +q: U32, +tag: U32, got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match bs:
        case Nil{}: got
        case +b <> t: lasttag.go(m, t, dev, q, U32.add(tag, 1),
                                Bool.pick(U32, is_pair(b, dev, q), tag, got))

def lasttag(+bs: List<&2, E>, dev: U32, q: U32) -> U32:
  lasttag.go(List.length(&2, E, bs), bs, dev, q, 0, 0)

# `prev[tag]` IS `tag` when the tag is the first call on its queue -- that is the
# None sentinel, and it is why `prevt` returns the tag itself.

def same_slot(+bs: List<&2, E>, +t: U32, +tag: U32) -> Bool:
  Bool.and(U32.is_lt(t, tag), is_pair(elem(bs, t), E.dev(elem(bs, tag)), E.q(elem(bs, tag))))


def prevt.go(n: Nat, +bs: List<&2, E>, +tag: U32, +t: U32, best: U32) -> U32:
  match n:
    case 0n: best
    case 1n+m: prevt.go(m, bs, tag, U32.add(t, 1),
                  Bool.pick(U32, same_slot(bs, t, tag), t, best))


def prevt(+bs: List<&2, E>, +tag: U32) -> U32: prevt.go(List.length(&2, E, bs), bs, tag, 0, tag)

def prev_or_self(bs: List<&2, E>, tag: U32) -> U32: U32.add(prevt(bs, tag), 1)

def qfirst.go(n: Nat, qs: List<&2, U32>, +got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match qs:
        case Nil{}: got
        case +h <> t: qfirst.go(m, t, Bool.pick(U32, U32.is_zero(got), h, got))


def qfirst(+qs: List<&2, U32>) -> U32: qfirst.go(List.length(&2, U32, qs), qs, 0)


# ===========================================================================
# `signal_tags` (:230) -- THE LAST-WINS RULE, and it is the rule most likely to
# be got wrong, because `self.last` holds ONE tag per queue:
#   {tag for (dev, q), tag in self.last.items() if q != epilogue(dev) or (dev, q) in peers}
# so only the LAST call on a queue can signal. `two` answers `1` (not `0 1`) and
# `revis` answers `2` (not `0 1 2`): that is the whole content of the rule, and
# no single-queue fixture with one call could ever see it.
#
# THE SECOND DISJUNCT IS VACUOUS IN EVERY FIXTURE AND THE GATE SAYS SO.
# `(dev, q) in peers` is True for every queue that runs a call on a device whose
# `Device.canonicalize` differs from the enqueue device, which under DEV=NULL is
# every batch (`canonicalize('NULL:0')` is `'NULL'`). A fixture that made it
# False needs a device with no peers, and no NULL batch has one. So the gate
# cannot separate `q != epi` from `or (dev, q) in peers`, and `hq2_b*_sig_*` are
# rows about the LAST-WINS half alone. That is a reported blind spot.
# ===========================================================================
def epi(+bs: List<&2, E>, +dev: U32) -> U32:
  Bool.pick(U32, U32.is_eq(nq(bs, dev), 1), qfirst(qlist(bs, dev)), Q_COMPUTE())

# THE QUEUE NAMES, because `epilogue_queue` (:235) answers a STRING and the gate
# compares strings against `ctx.epilogue_queue(dev)`.
def qname(q: U32) -> String:
  match q:
    case 1: "COMPUTE:0"
    case 2: "COPY:0"
    case _: "COPY:1"

def epiname(+bs: List<&2, E>, dev: U32) -> String: qname(epi(bs, dev))

def has_peer(+bs: List<&2, E>) -> Bool: Bool.not(U32.is_zero(U32.from_nat(List.length(&2, E, bs))))


def signs(+bs: List<&2, E>, dev: U32, q: U32) -> Bool:
  Bool.or(Bool.not(U32.is_eq(q, epi(bs, dev))), has_peer(bs))


def sig_tags.go(n: Nat, +ps: List<&2, E>, +bs: List<&2, E>, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match ps:
        case Nil{}: acc
        case p <> t: sig_tags.go(m, t, bs,
          Bool.pick(List<&2, U32>, signs(bs, E.dev(p), E.q(p)),
            List.append(&2, U32, acc, [lasttag(bs, E.dev(p), E.q(p))]), acc))

# `q != epilogue(dev)` OR `(dev, q) in peers`. `has_peer` is True whenever the
# batch is non-empty under DEV=NULL -- see THE SECOND DISJUNCT IS VACUOUS above.
def sig_tags(+bs: List<&2, E>) -> List<&2, U32>:
  sig_tags.go(U32.to_nat(npairs(bs)), pairs(bs), bs, Nil{})

def member.go(n: Nat, xs: List<&2, U32>, +x: U32, hit: Bool) -> Bool:
  match n:
    case 0n: hit
    case 1n+m:
      match xs:
        case Nil{}: hit
        case h <> t: member.go(m, t, x, Bool.or(hit, U32.is_eq(h, x)))

def member(+xs: List<&2, U32>, x: U32) -> Bool: member.go(List.length(&2, U32, xs), xs, x, False{})


# ===========================================================================
# `DepsTracker.access_resources` (:182-207) reduced to WHO OVERLAPS WHOM, and
# `_wait_ins` (:242-252) which turns that into the WAIT list.
#
# :191 collects every producer whose WRITE range overlaps a READ of this call;
# :192 adds, for each range this call WRITES, every producer whose READ range
# overlaps it -- a write must follow a prior read of the same buffer. With two
# whole buffers per call and no suballocation:
#   overlap(i, t) = (r(i) == w(t)) or (w(i) == w(t)) or (w(i) == r(t))
# ===========================================================================
def overlaps(+bs: List<&2, E>, +i: U32, +t: U32) -> Bool:
  Bool.or(Bool.or(U32.is_eq(E.r(elem(bs, i)), E.w(elem(bs, t))),
                  U32.is_eq(E.w(elem(bs, i)), E.w(elem(bs, t)))),
          U32.is_eq(E.w(elem(bs, i)), E.r(elem(bs, t))))

def deps.go(n: Nat, +bs: List<&2, E>, +i: U32, +t: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m: deps.go(m, bs, i, U32.add(t, 1),
                 Bool.pick(List<&2, U32>, Bool.and(U32.is_lt(t, i), overlaps(bs, i, t)),
                   List.append(&2, U32, acc, [t]), acc))

def deps(+bs: List<&2, E>, i: U32) -> List<&2, U32>:
  deps.go(List.length(&2, E, bs), bs, i, 0, Nil{})

# `latest` (:244-246) is `(producer queue) -> the LATEST submit tag to wait on`,
# with :246's filter `t < tag and (d, q) != (device, queue)`. The second clause
# is the SAME-QUEUE-IS-FIFO rule, and it is why `two`, `fifo` and `revis` -- all
# ONE queue -- have NO dependency waits at all while `three` and `copyq` do.
# Here the map's keys are reduced to the QUEUE, because every producer in these
# fixtures is on the same device.
def prodq.go(n: Nat, +ds: List<&2, U32>, +bs: List<&2, E>, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match ds:
        case Nil{}: acc
        case d <> t: prodq.go(m, t, bs,
                 Bool.pick(List<&2, U32>, Bool.not(member(acc, E.q(elem(bs, d)))),
                   List.append(&2, U32, acc, [E.q(elem(bs, d))]), acc))

def latest(+bs: List<&2, E>, +i: U32) -> List<&2, U32>:
  prodq.go(List.length(&2, U32, deps(bs, i)), deps(bs, i), bs, Nil{})

def maxdep.go(n: Nat, +ds: List<&2, U32>, +bs: List<&2, E>, +q: U32, +best: U32) -> U32:
  match n:
    case 0n: best
    case 1n+m:
      match ds:
        case Nil{}: best
        case d <> t: maxdep.go(m, t, bs, q,
                 Bool.pick(U32, U32.is_eq(E.q(elem(bs, d)), q), U32.max(best, d), best))


# `latest[(q)] = max(latest.get(q, 0), t)` (:246), and `max(..., 0)` is why a
# producer at tag 0 is still recorded at all.
def maxdep(+bs: List<&2, E>, +i: U32, q: U32) -> U32: maxdep.go(List.length(&2, U32, deps(bs, i)), deps(bs, i), bs, q, 0)

# THE WAIT LIST of call `i`, in :252's dict-insertion order: one WAIT per
# PRODUCER QUEUE, at that queue's signal slot, on `t + 1`.
def waits.go(n: Nat, +ls: List<&2, U32>, +bs: List<&2, E>, +i: U32, +acc: List<&2, Ins>) -> List<&2, Ins>:
  match n:
    case 0n: acc
    case 1n+m:
      match ls:
        case Nil{}: acc
        case q <> t: waits.go(m, t, bs, i,
                 List.append(&2, Ins, acc, [Ins{I_WAIT(), qsig(bs, DEV_N0(), q),
                                               U32.add(maxdep(bs, i, q), 1), 0}]))

def waits(+bs: List<&2, E>, +i: U32) -> List<&2, Ins>: waits.go(List.length(&2, U32, latest(bs, i)), latest(bs, i), bs, i, Nil{})

# ===========================================================================
# `_start_ins` (:254-256) -- `INS(("barrier", void), ())` and then ONE WAIT ON
# THE DEVICE TIMELINE per device in `[dev, *sorted(peers[(dev, queue)])]`. So
# it is a BARRIER, then `1 + npeers` TIMELINE waits, and the peer's wait is what
# makes the first queue of a device wait for the work another device already did
# on its memory. Under DEV=NULL `peers[('NULL:0', q)] == {'NULL'}` for every
# queue, so `start_n` is 3 for `NULL:0` and 2 for the canonicalized `NULL` --
# whose peers key is ABSENT, and that is why its epilogue queue starts with
# only ONE timeline wait.
# ===========================================================================
def start_n(dev: U32) -> U32: Bool.pick(U32, U32.is_eq(dev, DEV_N0()), 3, 2)

# ONE SELF-CALL PER ARM. `Bool.pick(..., start.go(...), start.go(...))` is two
# self-calls in one expression and is refused, so the arm is a `match` on the
# `first` Bool PARAMETER and each arm recurses once.
def start.go(n: Nat, +acc: List<&2, Ins>, +dev: U32, +k: U32, first: Bool) -> List<&2, Ins>:
  match n:
    case 0n: acc
    case 1n+m:
      match first:
        case True{}: start.go(m, List.append(&2, Ins, acc, [Ins{I_BARRIER(), 0, 0, 0}]),
                               dev, k, False{})
        case False{}: start.go(m, List.append(&2, Ins, acc, [Ins{I_WAIT(), TIMELINE_MARK(), dev, 0}]),
                               dev, U32.add(k, 1), False{})

def start_ins(+dev: U32) -> List<&2, Ins>:
  start.go(U32.to_nat(start_n(dev)), Nil{}, dev, 0, True{})

# ===========================================================================
# `_build_queues` (:258-283) -- THE ORDER, and it is the load-bearing part of the
# whole file:
#
#   :263  first use of a queue -> `_start_ins(devices[0], queue)`
#   :266  ts_ins = one TIMESTAMP per stamp slot
#   :267  `q += waits + ts_ins[:1] + [call] + ts_ins[1:]`
#         -- THE CALL GOES BETWEEN THE TWO TIMESTAMPS, never outside them
#   :270  `if tag in ctx.signal_tags: q += [INS(("store", ...))]`
#   :276  the epilogue waits for every OTHER queue of the device and every peer
#         queue that touched it, then
#   :278  BUMPS the device timeline -- and :281 adds `_start_ins` first if the
#         epilogue queue is one with no calls of its own.
#
# So every queue's stream is
#   [BARRIER, TIMELINE waits...] ++ dependency waits ++ [pre-TIMESTAMP] ++ CALL
#   ++ [post-TIMESTAMP] ++ [SIGNAL if this tag is the queue's LAST] ++ epilogue.
# ===========================================================================
# ===========================================================================
# `_build_queues` (:258-283) -- THE ORDER, and it is the load-bearing part of the
# whole file:
#
#   :263  first use of a queue -> `_start_ins(devices[0], queue)`
#   :266  ts_ins = one TIMESTAMP per stamp slot
#   :267  `q += waits + ts_ins[:1] + [call] + ts_ins[1:]`
#         -- THE CALL GOES BETWEEN THE TWO TIMESTAMPS, never outside them
#   :270  `if tag in ctx.signal_tags: q += [INS(("store", ...))]`
#   :276  the epilogue waits for every OTHER queue of the device and every peer
#         queue that touched it, then
#   :278  BUMPS the device timeline, and :281 adds `_start_ins` first if the
#         epilogue queue is one with no calls of its own.
#
# So one CALL's block is
#   dependency waits ++ [pre-TIMESTAMP] ++ CALL ++ [post-TIMESTAMP] ++ [SIGNAL]
# and one QUEUE's stream is its `_start_ins` ++ the blocks of every call on it
# ++ the epilogue tail IF it is the device's epilogue queue.
# ===========================================================================
def cat2(+a: List<&2, Ins>, +b: List<&2, Ins>) -> List<&2, Ins>: List.concat(&2, Ins, [a, b])

def pre_ts(+bs: List<&2, E>, tag: U32, +profile: Bool, +acc: List<&2, Ins>) -> List<&2, Ins>:
  Bool.pick(List<&2, Ins>, profile,
    List.append(&2, Ins, acc, [Ins{I_TIMESTAMP(), stamp_n(bs, tag, profile), 0, 0}]), acc)

def post_ts(+bs: List<&2, E>, tag: U32, +profile: Bool, +acc: List<&2, Ins>) -> List<&2, Ins>:
  Bool.pick(List<&2, Ins>, profile,
    List.append(&2, Ins, acc, [Ins{I_TIMESTAMP(), U32.add(stamp_n(bs, tag, profile), 1), 0, 0}]), acc)

# :271 `INS(("store", void), src=(ctx.queue_signal(devices, queue),
# UOp.const(tag + 1, uint64)))`. It fires only for a tag IN `signal_tags`, which
# is the LAST tag of each signing queue -- so `two` stores ONCE and `three`
# stores three times.
def signal_at(+bs: List<&2, E>, +tag: U32, +acc: List<&2, Ins>) -> List<&2, Ins>:
  Bool.pick(List<&2, Ins>, member(sig_tags(bs), tag),
    List.append(&2, Ins, acc, [Ins{I_STORE(), qsig(bs, DEV_N0(), E.q(elem(bs, tag))),
                                       U32.add(tag, 1), 0}]), acc)

# ONE CALL's whole block, :267's `waits + ts_ins[:1] + [call] + ts_ins[1:]` and
# then :270's conditional store. `hq2_b*_callblock*` is the row.
def call_block(+bs: List<&2, E>, +tag: U32, +profile: Bool) -> List<&2, Ins>:
  signal_at(bs, tag,
    post_ts(bs, tag, profile,
      List.append(&2, Ins, pre_ts(bs, tag, profile, waits(bs, tag)),
                  [Ins{I_CALL(), tag, 0, 0}])))

# THE TAGS OF ONE PAIR, ascending -- `two` and `revis` have two and three.
def pair_tags.go(n: Nat, +bs: List<&2, E>, +p: E, +t: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m: pair_tags.go(m, bs, p, U32.add(t, 1),
                 Bool.pick(List<&2, U32>, is_pair(elem(bs, t), E.dev(p), E.q(p)),
                   List.append(&2, U32, acc, [t]), acc))

def pair_tags(+bs: List<&2, E>, +p: E) -> List<&2, U32>:
  pair_tags.go(List.length(&2, E, bs), bs, p, 0, Nil{})

def blocks_of.go(n: Nat, +ts: List<&2, U32>, +bs: List<&2, E>, +profile: Bool,
                 +acc: List<&2, Ins>) -> List<&2, Ins>:
  match n:
    case 0n: acc
    case 1n+m:
      match ts:
        case Nil{}: acc
        case t <> rest: blocks_of.go(m, rest, bs, profile,
                           List.concat(&2, Ins, [acc, call_block(bs, t, profile)]))

def blocks_of(+ts: List<&2, U32>, +bs: List<&2, E>, profile: Bool) -> List<&2, Ins>:
  blocks_of.go(List.length(&2, U32, ts), ts, bs, profile, Nil{})

# ===========================================================================
# THE EPILOGUE TAIL (:273-282), appended to the device's epilogue queue.
# `epi_waits(dev)` is
#   (every OTHER queue of dev) + (every (dev, queue) key of peers that `dev` is a
#   member of), and for `NULL:0` the second set is EMPTY -- its peers hold the
#   NAME `'NULL'`, not `'NULL:0'` -- while for `NULL` the first set is empty and
#   the second is every queue that ran a call. That asymmetry is the whole of
# `hq2_bthree_q_NULL_COMPUTE0` and it is a string comparison in Python and an id
# comparison here.
# ===========================================================================
def epi_waits_n(+bs: List<&2, E>, +dev: U32) -> U32:
  Bool.pick(U32, U32.is_eq(dev, DEV_N0()), U32.sub(nq(bs, dev), 1), npairs(bs))

def tl_wait(dev: U32) -> Ins: Ins{I_WAIT(), TIMELINE_MARK(), dev, 0}

# A SELF-CALL MAY NOT PASS A COMPUTED FUEL (`Nat.sub(n, 1n)` is not decreasing),
# so the countdown is DESTRUCTURED and `m` is the new fuel. Same shape as
# `list.range.go` in base.bend.
def times.go(n: Nat, +acc: List<&2, Ins>, +dev: U32) -> List<&2, Ins>:
  match n:
    case 0n: acc
    case 1n+m: times.go(m, List.append(&2, Ins, acc, [tl_wait(dev)]), dev)

def times(n: U32, dev: U32) -> List<&2, Ins>: times.go(U32.to_nat(n), Nil{}, dev)

# :278 `bump = INS(("store", void), src=(timeline(dev), timeline_value(dev) +
# const(1)))` -- the device timeline advances by ONE, once per batch, on the
# epilogue queue and nowhere else.
def bump(dev: U32) -> Ins: Ins{I_BUMP(), TIMELINE_MARK(), dev, 1}

def epi_tail(+bs: List<&2, E>, +dev: U32) -> List<&2, Ins>:
  List.concat(&2, Ins, [times(epi_waits_n(bs, dev), dev), [bump(dev)]])

# ===========================================================================
# THE WHOLE QUEUE STREAM, in the ORDER `_build_queues` returns it: every distinct
# (device, queue) pair in first-use order, and then -- LAST -- the canonicalized
# PEER device's epilogue queue, which exists only because
# `canonicalize('NULL:0')` is `'NULL'` and which holds no calls of its own (:281).
# ===========================================================================
def is_epi_pair(+bs: List<&2, E>, +p: E) -> Bool:
  Bool.and(U32.is_eq(E.dev(p), DEV_N0()), U32.is_eq(E.q(p), epi(bs, DEV_N0())))

def queue_tail(+bs: List<&2, E>, +p: E, +acc: List<&2, Ins>) -> List<&2, Ins>:
  Bool.pick(List<&2, Ins>, is_epi_pair(bs, p), cat2(acc, epi_tail(bs, DEV_N0())), acc)


def queue_of(+bs: List<&2, E>, +p: E, profile: Bool) -> List<&2, Ins>:
  queue_tail(bs, p, cat2(start_ins(E.dev(p)), blocks_of(pair_tags(bs, p), bs, profile)))

def pair_streams.go(n: Nat, +ps: List<&2, E>, +bs: List<&2, E>, +profile: Bool,
                    +acc: List<&2, Ins>) -> List<&2, Ins>:
  match n:
    case 0n: acc
    case 1n+m:
      match ps:
        case Nil{}: acc
        case p <> t: pair_streams.go(m, t, bs, profile,
                         List.concat(&2, Ins, [acc, queue_of(bs, p, profile)]))

# :281 -- the peer device's epilogue queue gets `_start_ins` because it is empty.
def peer_epilogue(+bs: List<&2, E>, profile: Bool) -> List<&2, Ins>:
  cat2(cat2(start_ins(DEV_N()), times(epi_waits_n(bs, DEV_N()), DEV_N())), [bump(DEV_N())])

def queues_of(+bs: List<&2, E>, +profile: Bool) -> List<&2, Ins>:
  List.concat(&2, Ins, [pair_streams.go(U32.to_nat(npairs(bs)), pairs(bs), bs, profile, Nil{}),
                        peer_epilogue(bs, profile)])

def t_consts() -> IO(Unit):
  do IO<Unit>:
    urow("hq2_cache_thresh", HCQ_CACHE_THRESH())
    urow("hq2_devs_n", hcq2_dev_n())
    # BOTH DIRECTIONS on the discriminator. `hc2_dev_id_*` is value -> name and
    # `hq2_dev_head_*` is the `x.split(":")[0]` the membership test asks about.
    srow("hq2_dev_name_1", dev_name(HCQ_DEV_NV()))
    srow("hq2_dev_name_2", dev_name(HCQ_DEV_QCOM()))
    srow("hq2_dev_name_3", dev_name(HCQ_DEV_CUDA()))
    srow("hq2_dev_name_4", dev_name(HCQ_DEV_NULL()))
    srow("hq2_dev_name_5", dev_name(HCQ_DEV_METAL()))
    srow("hq2_dev_name_6", dev_name(HCQ_DEV_AMD()))
    urow("hq2_dev_name_0", U32.from_nat(String.length(dev_name(0))))
    urow("hq2_dev_id_NV", dev_id("NV"))
    urow("hq2_dev_id_QCOM", dev_id("QCOM"))
    urow("hq2_dev_id_CUDA", dev_id("CUDA"))
    urow("hq2_dev_id_NULL", dev_id("NULL"))
    urow("hq2_dev_id_METAL", dev_id("METAL"))
    urow("hq2_dev_id_AMD", dev_id("AMD"))
    urow("hq2_dev_id_CPU", dev_id("CPU"))
    urow("hq2_dev_id_NVX", dev_id("NVX"))
    urow("hq2_dev_id_lower", dev_id("nv"))
    srow("hq2_dev_head_NV0", dev_head("NV:0"))
    srow("hq2_dev_head_NV01", dev_head("NV:0:1"))
    srow("hq2_dev_head_CPU012", dev_head("CPU:0:1:2"))
    srow("hq2_dev_head_bare", dev_head("AMD"))
    srow("hq2_dev_head_nocolon", dev_head("METAL:1"))
    # CDTYPE BOTH WAYS. `hc2_cdtype_*` is size -> dtype and
    # `hq2_cdtype_of_*` is the same four rows from the other direction.
    urow("hq2_cdtype_1", cdtype_of(1))
    urow("hq2_cdtype_2", cdtype_of(2))
    urow("hq2_cdtype_4", cdtype_of(4))
    urow("hq2_cdtype_8", cdtype_of(8))
    urow("hq2_cdtype_3", cdtype_of(3))
    urow("hq2_cdtype_0", cdtype_of(0))
    urow("hq2_cdtype_16", cdtype_of(16))
    urow("hq2_cdtype_len", U32.from_nat(List.length(&2, U32, cdtype_sizes())))
    row("hq2_cdtype_roundtrips_1", U32.is_eq(cdtype_of(1), 1))
    row("hq2_cdtype_roundtrips_2", U32.is_eq(cdtype_of(2), 2))
    row("hq2_cdtype_roundtrips_4", U32.is_eq(cdtype_of(4), 4))
    row("hq2_cdtype_roundtrips_8", U32.is_eq(cdtype_of(8), 8))
    row("hq2_cdtype_rejects_3", Bool.not(cdtype.is(3)))
    row("hq2_cdtype_rejects_16", Bool.not(cdtype.is(16)))
    row("hq2_cdtype_accepts_4", cdtype.is(4))
    # THE STAGING CONSTANTS, and :157's TWO DIVIDES in that order.
    urow("hq2_staging_size", STAGING_SIZE())
    urow("hq2_staging_slots", STAGING_SLOTS())
    urow("hq2_mock_staging_size", MOCK_STAGING_SIZE())
    urow("hq2_staging_slot_bytes", staging_slot_bytes())
    urow("hq2_chunk_it1", staging_chunk(1))
    urow("hq2_chunk_it4", staging_chunk(4))
    urow("hq2_chunk_it2", staging_chunk(2))
    urow("hq2_chunk_it8", staging_chunk(8))
    urow("hq2_copies_1000_it1", staging_copies(1000, 1))
    urow("hq2_copies_1000_it4", staging_copies(1000, 4))
    urow("hq2_copies_big_it2", staging_copies(67108865, 2))
    urow("hq2_copies_big_it1", staging_copies(134217729, 1))
    urow("hq2_slot_at_0_it1", staging_slot_at(0, 1))
    urow("hq2_slot_at_1_it1", staging_slot_at(1, 1))
    urow("hq2_slot_at_2_it1", staging_slot_at(2, 1))
    urow("hq2_slot_at_3_it1", staging_slot_at(3, 1))
    urow("hq2_slot_at_3_it4", staging_slot_at(3, 4))
    IO.pure(Unit, Unit{})

def t_name() -> IO(Unit):
  do IO<Unit>:
    # hcq2.py:63. `py=` values are CALLS to `hcq2.to_name`, from probe.py.
    srow("hq2_toname_submit", to_name3("submit", "NV", "COMPUTE:0"))
    srow("hq2_toname_cmdbuf", to_name2("cmdbuf", "COPY:1"))
    srow("hq2_toname_qcom", to_name3("submit", "QCOM", "COPY:0"))
    srow("hq2_toname_colon2", to_name(["KERNEL", "Foo:Bar"]))
    srow("hq2_toname_dblcolon", to_name(["a:b:c"]))
    srow("hq2_toname_single", to_name(["X"]))
    srow("hq2_toname_empty", to_name([""]))
    srow("hq2_toname_lower", to_name2("nv", "compute"))
    # THE ORDER OF THE TWO HALVES: the colon fold is on the ORIGINAL case and
    # the lower is LAST, so this is `compute_0` and not `compute:0`.
    srow("hq2_toname_order", to_name2("COMPUTE", "0"))
    # THE EMPTY TAIL IS NOT A TRAILING SEPARATOR, and a part that already
    # contains `_` is not split.
    srow("hq2_toname_under", to_name2("a_b", "c"))
    srow("hq2_toname_noseps", to_name2("a", "b"))
    # :69-70's `to_name("submit", devs[0].split(":")[0], queue.split(":")[0])` --
    # `make_submit`'s NAME, which is the custom-function name and the placeholder
    # tag. probe2.py, `submit_name`.
    srow("hq2_submit_name_null", to_name3("submit", dev_head("NULL:0"), dev_head("COPY:0")))
    srow("hq2_submit_name_amd", to_name3("submit", dev_head("AMD:0"), dev_head("COPY:3")))
    srow("hq2_submit_name_cuda", to_name3("submit", dev_head("CUDA:1"), dev_head("COMPUTE:0")))
    srow("hq2_submit_name_qcom_encdec", to_name3("submit", dev_head("QCOM:0"), dev_head("ENCDEC:0")))
    IO.pure(Unit, Unit{})

def t_allin() -> IO(Unit):
  do IO<Unit>:
    # hcq2.py:38. `py=` from probe.py `all_devices_in`.
    row("hq2_all_in_nv0", all_in(["NV:0"]))
    row("hq2_all_in_cuda12", all_in(["CUDA:1:2"]))
    row("hq2_all_in_cpu", Bool.not(all_in(["CPU"])))
    row("hq2_all_in_null", all_in(["NULL"]))
    row("hq2_all_in_nv_amd", all_in(["NV:0", "AMD"]))
    row("hq2_all_in_bare", all_in(["NV:0"]))
    row("hq2_all_in_empty", all_in(Nil{}))
    row("hq2_all_in_nvx", Bool.not(all_in(["NVX"])))
    row("hq2_all_in_metal1", all_in(["METAL:1"]))
    # NOT a membership: two devices BOTH in HCQ_DEVS. `hq2_all_in_cpu_nv` is
    # the negative of that and is the row that separates `<=` from `in`.
    row("hq2_all_in_cpu_nv", Bool.not(all_in(["CPU", "NV"])))
    # THE HEAD IS WHAT IS ASKED ABOUT: `AMD:0:1:2` is AMD and `NVX:0` is not NV.
    row("hq2_all_in_amd012", all_in(["AMD:0:1:2"]))
    row("hq2_all_in_nvx0", Bool.not(all_in(["NVX:0"])))
    IO.pure(Unit, Unit{})

def t_layout() -> IO(Unit):
  do IO<Unit>:
    # hcq2.py:74-76. THE CITED FUNCTION. `py=` from hcq2-oracle.py `layout()`,
    # which CALLS `hcq2.layout_args`. The three bases are 0, 256 and 512, and
    # 512 is `ops_nv.bend:181`'s base (its `qmd_sz`).
    lrow("hq2_layout_buf3_0", layout_ks(BUF3(), 0))
    lrow("hq2_layout_buf3_256", layout_ks(BUF3(), 256))
    lrow("hq2_layout_buf3_512", layout_ks(BUF3(), 512))
    lrow("hq2_layout_mixed_0", layout_ks(MIXED(), 0))
    lrow("hq2_layout_mixed_256", layout_ks(MIXED(), 256))
    lrow("hq2_layout_mixed_512", layout_ks(MIXED(), 512))
    lrow("hq2_layout_five32_0", layout_ks(FIVE32(), 0))
    lrow("hq2_layout_five32_256", layout_ks(FIVE32(), 256))
    lrow("hq2_layout_five32_512", layout_ks(FIVE32(), 512))
    # AN `int` IN THE ARGUMENT LIST BECOMES A uint32 (hcq2.py:75), so three ints
    # lay out as 0, 4, 8 -- NOT 0, 8, 16. `hq2_layout_ints_*` is that claim and
    # `hq2_layout_words_ints` is the dtype list behind it.
    lrow("hq2_layout_ints_0", layout_ks(INTS(), 0))
    lrow("hq2_layout_ints_256", layout_ks(INTS(), 256))
    lrow("hq2_layout_ints_512", layout_ks(INTS(), 512))
    lrow("hq2_layout_one16_0", layout_ks(ONE16(), 0))
    lrow("hq2_layout_one16_256", layout_ks(ONE16(), 256))
    lrow("hq2_layout_one16_512", layout_ks(ONE16(), 512))
    lrow("hq2_layout_odd_0", layout_ks(ODD(), 0))
    lrow("hq2_layout_odd_256", layout_ks(ODD(), 256))
    lrow("hq2_layout_odd_512", layout_ks(ODD(), 512))
    # THE KERNEL-ARGUMENT TRACE, which IS the dtype list in order.
    lrow("hq2_layout_words_mixed", layout_ts(MIXED(), 0))
    lrow("hq2_layout_words_ints", layout_ts(INTS(), 0))
    lrow("hq2_layout_words_buf3", layout_ts(BUF3(), 0))
    urow("hq2_layout_buf3_n", layout_n(BUF3()))
    urow("hq2_layout_mixed_n", layout_n(MIXED()))
    urow("hq2_layout_buf0_n", layout_n(Nil{}))
    # ops_nv.bend:205's TWO CLAIMS, re-asked of `hcq2.layout_args` itself.
    lrow("hq2_layout_opsnv_mixed", layout_ks(MIXED(), 0))
    lrow("hq2_layout_opsnv_buf3var2", layout_ks([8, 8, 8, 4, 4], 512))
    # THE CROSS-IMPLEMENTATION ROW: `D.iter_sig` read on its own, which is what
    # `device.bend` holds. TWO INDEPENDENT READINGS OF THE SAME WALRUS. See THE
    # WALRUS IS LOAD-BEARING above and `ops_nv.bend:1439-1452`.
    lrow("hq2_layout_sig_mixed", device_sig_ks(MIXED()))
    lrow("hq2_layout_sig_buf3", device_sig_ks(BUF3()))
    lrow("hq2_layout_sig_five32", device_sig_ks(FIVE32()))
    row("hq2_layout_agrees_mixed", u32s_eq(layout_ks(MIXED(), 0), device_sig_ks(MIXED())))
    row("hq2_layout_agrees_buf3", u32s_eq(layout_ks(BUF3(), 0), device_sig_ks(BUF3())))
    row("hq2_layout_agrees_five32", u32s_eq(layout_ks(FIVE32(), 0), device_sig_ks(FIVE32())))
    # THE WALRUS ITSELF: the uint16 at slot 8 ends at 10, so the ulong after it
    # is padded to 16. An implementation that advanced off the UNROUNDED offset
    # answers 0, 4, 6, 8, 16, 19 for this list -- which is what `device.bend:871`
    # did until `7f170f644`. `hq2_layout_ulong_slot` is the narrow claim.
    urow("hq2_layout_ulong_slot", layout_at(MIXED(), 0, 3n))
    urow("hq2_layout_uint16_slot", layout_at(MIXED(), 0, 2n))
    urow("hq2_layout_uchar_slot", layout_at(MIXED(), 0, 0n))
    urow("hq2_layout_uint8_last_slot", layout_at(MIXED(), 0, 5n))
    # AND THE BASE OFFSET IS AN ADDITION, not a shift of the whole list: at 512
    # the first slot is 512 and the gaps are the same.
    urow("hq2_layout_at512_first", layout_at(MIXED(), 512, 0n))
    urow("hq2_layout_at256_first", layout_at(MIXED(), 256, 0n))
    row("hq2_layout_base_is_add", U32.is_eq(layout_at(MIXED(), 512, 0n), U32.add(layout_at(MIXED(), 0, 0n), 512)))
    # THE PRECONDITION `pack` RELIES ON. base.bend has no sort without a
    # closure, and `layout`'s output is ascending BY CONSTRUCTION -- so this row
    # is what makes `hq2_pack_*` mean anything. A DECREASING list would be a
    # different gate, not a silent one.
    row("hq2_layout_is_ascending", ascending(layout_ks(MIXED(), 512)))
    row("hq2_layout_is_ascending_buf3", ascending(layout_ks(BUF3(), 0)))
    row("hq2_layout_is_ascending_one16", ascending(layout_ks(ONE16(), 256)))
    IO.pure(Unit, Unit{})

def t_pack() -> IO(Unit):
  do IO<Unit>:
    # hcq2.py:78-83. `py=` from hcq2-oracle.py `pack()`, which CALLS
    # `hcq2.pack_args` on `hcq2.layout_args` output.
    srow("hq2_pack_buf3_0_24", pk_str(pack.trail(layout(BUF3(), 0), 24)))
    srow("hq2_pack_buf3_0_32", pk_str(pack.trail(layout(BUF3(), 0), 32)))
    srow("hq2_pack_buf3_0_40", pk_str(pack.trail(layout(BUF3(), 0), 40)))
    srow("hq2_pack_mixed_0_32", pk_str(pack.trail(layout(MIXED(), 0), 32)))
    srow("hq2_pack_mixed_0_40", pk_str(pack.trail(layout(MIXED(), 0), 40)))
    srow("hq2_pack_mixed_0_64", pk_str(pack.trail(layout(MIXED(), 0), 64)))
    # A NON-ZERO BASE IS A LEADING PAD of the whole base, because `end` starts
    # at 0 (hcq2.py:79) and not at the first offset.
    srow("hq2_pack_buf3_8_32", pk_str(pack.trail(layout(BUF3(), 8), 32)))
    srow("hq2_pack_buf3_8_40", pk_str(pack.trail(layout(BUF3(), 8), 40)))
    srow("hq2_pack_buf3_512_536", pk_str(pack.trail(layout(BUF3(), 512), 536)))
    # THE REFUSAL: `bytes(size - end)` with `end > size` (hcq2.py:78).
    srow("hq2_pack_mixed_0_24", pk_str(pack.trail(layout(MIXED(), 0), 24)))
    row("hq2_pack_refused_24", U32.is_eq(Pk.k(pk_last(pack.trail(layout(MIXED(), 0), 24))), PK_ERR()))
    # THE EMPTY LIST IS ONE WORD, the trailing pad, at every size.
    srow("hq2_pack_empty_0", pk_str(pack.trail(Nil{}, 0)))
    srow("hq2_pack_empty_8", pk_str(pack.trail(Nil{}, 8)))
    srow("hq2_pack_empty_16", pk_str(pack.trail(Nil{}, 16)))
    urow("hq2_pack_empty_len", pk_n(pack.trail(Nil{}, 8)))
    urow("hq2_pack_buf3_len", pk_n(pack.trail(layout(BUF3(), 0), 24)))
    urow("hq2_pack_mixed_len", pk_n(pack.trail(layout(MIXED(), 0), 32)))
    # AN EMPTY PAD IS STILL A WORD: `bytes(0)` is `b''` and the BINARY is still
    # in the stream. `hq2_pack_buf3_len` is 4 for a three-word list.
    row("hq2_pack_empty_pad_is_word", U32.is_eq(pk_n(pack.trail(layout(BUF3(), 0), 24)), 4))
    # `end` IS THE LAST OFFSET PLUS ITS OWN ITEMSIZE, not the size.
    urow("hq2_end_of_buf3", end_of(layout(BUF3(), 0)))
    urow("hq2_end_of_mixed", end_of(layout(MIXED(), 0)))
    urow("hq2_end_of_empty", end_of(Nil{}))
    IO.pure(Unit, Unit{})

def t_cstruct() -> IO(Unit):
  do IO<Unit>:
    # hcq2.py:100-104. `py=` from hcq2-oracle.py `cstruct()`, which reads
    # `kgsl.struct_kgsl_command_object._real_fields_` and
    # `kgsl.struct_kgsl_gpu_command._real_fields_` THROUGH `hcq2.cstruct`'s own
    # `{n: (o, CDTYPE[ctypes.sizeof(t)])}` comprehension at :101.
    urow("hq2_cstruct_command_object_sizeof", fld_sizeof(f_ib()))
    urow("hq2_cstruct_command_object_nfields", fld_n(f_ib()))
    urow("hq2_cstruct_command_object_nreal", fld_real(f_ib()))
    srow("hq2_cstruct_command_object_order", fstr(fld_names(f_ib())))
    lrow("hq2_cstruct_command_object_offs", fld_offs(f_ib()))
    lrow("hq2_cstruct_command_object_szs", fld_szs(f_ib()))
    lrow("hq2_cstruct_command_object_cdt", fld_cdts(f_ib()))
    urow("hq2_cstruct_gpu_command_sizeof", fld_sizeof(f_cmd()))
    urow("hq2_cstruct_gpu_command_nfields", fld_n(f_cmd()))
    urow("hq2_cstruct_gpu_command_nreal", fld_real(f_cmd()))
    srow("hq2_cstruct_gpu_command_order", fstr(fld_names(f_cmd())))
    lrow("hq2_cstruct_gpu_command_offs", fld_offs(f_cmd()))
    lrow("hq2_cstruct_gpu_command_szs", fld_szs(f_cmd()))
    lrow("hq2_cstruct_gpu_command_cdt", fld_cdts(f_cmd()))
    # :106 `cfield` BOTH DIRECTIONS, name -> offset and name -> size. A field
    # renamed in the autogen header must move the bytes, and a port that looked
    # the offsets up by POSITION would not notice.
    urow("hq2_cfield_command_object_offset_at", fld_at(f_ib(), "offset"))
    urow("hq2_cfield_command_object_size_at", fld_at(f_ib(), "size"))
    urow("hq2_cfield_command_object_flags_at", fld_at(f_ib(), "flags"))
    urow("hq2_cfield_command_object_id_at", fld_at(f_ib(), "id"))
    urow("hq2_cfield_command_object_offset_sz", fld_sz(f_ib(), "offset"))
    urow("hq2_cfield_command_object_size_sz", fld_sz(f_ib(), "size"))
    urow("hq2_cfield_command_object_flags_sz", fld_sz(f_ib(), "flags"))
    urow("hq2_cfield_command_object_id_sz", fld_sz(f_ib(), "id"))
    urow("hq2_cfield_gpu_command_cmdlist_at", fld_at(f_cmd(), "cmdlist"))
    urow("hq2_cfield_gpu_command_cmdsize_at", fld_at(f_cmd(), "cmdsize"))
    urow("hq2_cfield_gpu_command_numcmds_at", fld_at(f_cmd(), "numcmds"))
    urow("hq2_cfield_gpu_command_context_id_at", fld_at(f_cmd(), "context_id"))
    urow("hq2_cfield_gpu_command_cmdlist_sz", fld_sz(f_cmd(), "cmdlist"))
    urow("hq2_cfield_gpu_command_cmdsize_sz", fld_sz(f_cmd(), "cmdsize"))
    urow("hq2_cfield_gpu_command_numcmds_sz", fld_sz(f_cmd(), "numcmds"))
    urow("hq2_cfield_gpu_command_context_id_sz", fld_sz(f_cmd(), "context_id"))
    # AND THE REVERSE: an offset names its field. `hq2_cfield_gpu_command_*` is
    # that pair, and it is the direction a shifted struct breaks first.
    srow("hq2_cfield_name_of_8_cmd", fld_name(f_cmd(), 8))
    srow("hq2_cfield_name_of_56_cmd", fld_name(f_cmd(), 56))
    srow("hq2_cfield_name_of_8_ib", fld_name(f_ib(), 8))
    srow("hq2_cfield_name_of_28_ib", fld_name(f_ib(), 28))
    srow("hq2_cfield_name_of_99_cmd", fld_name(f_cmd(), 99))
    # THE ROW ORDER IS THE KWARGS ORDER (hcq2.py:102), and ops_qcom.py:197-198
    # are the only in-tree callers, so these two lists are the DESCRIPTOR.
    lrow("hq2_cstruct_ib_rows", cstruct_ib_rows())
    lrow("hq2_cstruct_cmd_rows", cstruct_cmd_rows())
    lrow("hq2_cstruct_cmd_rows_k", cstruct_cmd_rows_k())
    # AND THE ROWS ARE THE FIELDS' OWN OFFSETS, asked of the FIELD TABLE rather
    # than of a constant, so a shifted struct moves them.
    row("hq2_cstruct_cmd_rows_are_fields",
      u32s_eq(cstruct_cmd_rows(), [fld_at(f_cmd(), "cmdlist"), fld_at(f_cmd(), "cmdsize"),
                                  fld_at(f_cmd(), "numcmds"), fld_at(f_cmd(), "context_id")]))
    row("hq2_cstruct_ib_rows_are_fields",
      u32s_eq(cstruct_ib_rows(), [fld_at(f_ib(), "gpuaddr"), fld_at(f_ib(), "size"),
                                 fld_at(f_ib(), "flags")]))
    row("hq2_cstruct_cmd_rows_k_are_fields",
      u32s_eq(cstruct_cmd_rows_k(), [fld_sz(f_cmd(), "cmdlist"), fld_sz(f_cmd(), "cmdsize"),
                                     fld_sz(f_cmd(), "numcmds"), fld_sz(f_cmd(), "context_id")]))
    # :101's `if ctypes.sizeof(t)` -- a zero-length field is SKIPPED -- and both
    # qcom descriptors have none, so nfields and nreal agree here. That is a
    # FIXTURE-WANTING ZERO: the row says the filter exists, not that it fires.
    row("hq2_cstruct_ib_nozero", U32.is_eq(fld_n(f_ib()), fld_real(f_ib())))
    row("hq2_cstruct_cmd_nozero", U32.is_eq(fld_n(f_cmd()), fld_real(f_cmd())))
    IO.pure(Unit, Unit{})


# --- the batch GEOMETRY readers the gate needs.
def ins_n(+xs: List<&2, Ins>) -> U32: U32.from_nat(List.length(&2, Ins, xs))

def count_kind.go(n: Nat, +xs: List<&2, Ins>, +k: U32, got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match xs:
        case Nil{}: got
        case x <> t: count_kind.go(m, t, k, U32.add(got, Bool.to_u32(U32.is_eq(Ins.k(x), k))))


def count_kind(+xs: List<&2, Ins>, k: U32) -> U32: count_kind.go(List.length(&2, Ins, xs), xs, k, 0)

def has_kind(+xs: List<&2, Ins>, k: U32) -> Bool: Bool.not(U32.is_zero(count_kind(xs, k)))

def npairs_device(+bs: List<&2, E>) -> U32: npairs(bs)

def prev_list.go(n: Nat, +bs: List<&2, E>, +tag: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m: prev_list.go(m, bs, U32.add(tag, 1),
                 List.append(&2, U32, acc, [prev_or_self(bs, tag)]))


def prev_none_n.go(n: Nat, +bs: List<&2, E>, +tag: U32, got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m: prev_none_n.go(m, bs, U32.add(tag, 1),
                  U32.add(got, Bool.to_u32(U32.is_eq(prevt(bs, tag), tag))))


def prev_none_n(+bs: List<&2, E>) -> U32: prev_none_n.go(List.length(&2, E, bs), bs, 0, 0)

def prev_last_of(+bs: List<&2, E>, +tag: U32) -> U32:
  Bool.pick(U32, U32.is_eq(prevt(bs, tag), tag), 0, prevt(bs, tag))

def prev_last(+bs: List<&2, E>) -> U32:
  prev_last_of(bs, U32.sub(U32.from_nat(List.length(&2, E, bs)), 1))

def prev_list(+bs: List<&2, E>) -> List<&2, U32>:
  prev_list.go(List.length(&2, E, bs), bs, 0, Nil{})

def call_between_stamps.step(x: Ins, seen_ts: Bool) -> Bool:
  Bool.or(seen_ts, U32.is_eq(Ins.k(x), I_TIMESTAMP()))


def call_between_stamps.keep(x: Ins, seen_ts: Bool, inside: Bool) -> Bool:
  Bool.or(inside, Bool.and(seen_ts, U32.is_eq(Ins.k(x), I_CALL())))


def call_between_stamps.go(n: Nat, +xs: List<&2, Ins>, +seen_ts: Bool, inside: Bool) -> Bool:
  match n:
    case 0n: inside
    case 1n+m:
      match xs:
        case Nil{}: inside
        case x <> t: call_between_stamps.go(m, t, call_between_stamps.step(x, seen_ts),
                                              call_between_stamps.keep(x, seen_ts, inside))


# THE CALL GOES BETWEEN THE TWO TIMESTAMPS, :267's `waits + ts_ins[:1] + [call] +
# ts_ins[1:]`. Read off the STREAM rather than off `call_block`, so a port that
# emitted the call outside the stamps would fail here.
def call_between_stamps(+bs: List<&2, E>, +profile: Bool) -> Bool:
  call_between_stamps.go(List.length(&2, Ins, queues_of(bs, profile)), queues_of(bs, profile),
                         False{}, False{})

def ins_str.go(n: Nat, +xs: List<&2, Ins>, +acc: List<&2, String>) -> List<&2, String>:
  match n:
    case 0n: acc
    case 1n+m:
      match xs:
        case Nil{}: acc
        case +x <> t: ins_str.go(m, t, List.append(&2, String, acc, [String.concat([" ", iname(x)])]))

def ins_str(+xs: List<&2, Ins>) -> String:
  String.drop(String.concat(ins_str.go(List.length(&2, Ins, xs), xs, Nil{})), 1n)



def head_of.at(m: Maybe<&2, U32>) -> U32:
  match m:
    case Some{g}: g
    case None{}: 0


def head_of(+xs: List<&2, U32>) -> U32: head_of.at(List.get(&2, U32, xs, 0n))


def t_geom() -> IO(Unit):
  do IO<Unit>:
    # hcq2.py:232-240. THE `n -> n*2` EXPANSION and the slots formula. `py=`
    # from hcq2-oracle2.py's `hq2_geom*` rows, which CALL `BatchCtx.__post_init__`
    # and `ctx.slot` / `ctx.queue_signal` / `ctx.sched_timeline` / `ctx.stamps`.
    urow("hq2_geom_slots", slot_bytes(Ethree(), False{}))
    urow("hq2_geom_peerslots", peer_slot_bytes(False{}))
    urow("hq2_geom_p_slots", slot_bytes(Ethree(), True{}))
    urow("hq2_geom_p_peerslots", peer_slot_bytes(True{}))
    urow("hq2_geom_slot0", qsig(Ethree(), DEV_N0(), Q_COMPUTE()))
    urow("hq2_geom_slot1", qsig(Ethree(), DEV_N0(), Q_COPY0()))
    urow("hq2_geom_slot2", qsig(Ethree(), DEV_N0(), Q_COPY1()))
    urow("hq2_geom_slot3", stl(Ethree(), DEV_N0()))
    urow("hq2_geom_p_slot0", qsig(Ethree(), DEV_N0(), Q_COMPUTE()))
    urow("hq2_geom_p_stl", stl(Ethree(), DEV_N0()))
    # :237 `shrink((2*i, 2*i+2))` -- TWO u64 per slot, so the width is 2.
    lrow("hq2_geom_p_stamps0", stamps(Ethree(), 0, True{}))
    lrow("hq2_geom_p_stamps1", stamps(Ethree(), 1, True{}))
    lrow("hq2_geom_p_stamps2", stamps(Ethree(), 2, True{}))
    lrow("hq2_geom_p_stamps3", stamps(Ethree(), 3, True{}))
    urow("hq2_geom_p_qsig_c0", qsig(Ethree(), DEV_N0(), Q_COMPUTE()))
    urow("hq2_geom_p_qsig_c1", qsig(Ethree(), DEV_N0(), Q_COPY1()))
    urow("hq2_geom_stamps0_np", U32.from_nat(List.length(&2, U32, stamps(Ethree(), 0, False{}))))
    urow("hq2_geom_stamps0_p", U32.from_nat(List.length(&2, U32, stamps(Ethree(), 0, True{}))))
    # THE TWO ARMS DIFFER BY EXACTLY TWO SLOTS PER CALL, and the peer device by
    # the same amount -- the peer has NO calls and still grows, which is the row
    # that separates `2*len(batch)` from a per-queue count.
    urow("hq2_geom_slots_delta", U32.sub(slot_bytes(Ethree(), True{}), slot_bytes(Ethree(), False{})))
    urow("hq2_geom_slots_delta_p", U32.sub(peer_slot_bytes(True{}), peer_slot_bytes(False{})))
    # `stamps` is `2*len(batch)` in the DELTA but only two per call in the list:
    # tag 3 is past the end of a three-call batch and still answers (10, 11).
    urow("hq2_geom_stamps3_first", head_of(stamps(Ethree(), 3, True{})))
    IO.pure(Unit, Unit{})

def t_batch_one(+bs: List<&2, E>, +nm: String) -> IO(Unit):
  do IO<Unit>:
    urow(String.concat(["hq2_b", nm, "_npairs"]), npairs(bs))
    urow(String.concat(["hq2_b", nm, "_nq"]), nq(bs, DEV_N0()))
    urow(String.concat(["hq2_b", nm, "_slots"]), slot_bytes(bs, False{}))
    srow(String.concat(["hq2_b", nm, "_epi"]), epiname(bs, DEV_N0()))
    lrow(String.concat(["hq2_b", nm, "_sig_tags"]), sig_tags(bs))
    urow(String.concat(["hq2_b", nm, "_prevcnt"]), prev_none_n(bs))
    urow(String.concat(["hq2_b", nm, "_prevlast"]), prev_last(bs))
    urow(String.concat(["hq2_b", nm, "_npeers"]), 1)
    urow(String.concat(["hq2_b", nm, "_stl"]), stl(bs, DEV_N0()))
    srow(String.concat(["hq2_b", nm, "_start0"]), ins_str(start_ins(DEV_N0())))
    urow(String.concat(["hq2_b", nm, "_nqueues"]), U32.add(npairs(bs), 1))
    urow(String.concat(["hq2_b", nm, "_nwait0"]), ins_n(waits(bs, 0)))
    urow(String.concat(["hq2_b", nm, "_nwait1"]), ins_n(waits(bs, 1)))
    urow(String.concat(["hq2_b", nm, "_nwait2"]), ins_n(waits(bs, 2)))
    urow(String.concat(["hq2_b", nm, "_qsig0"]), qsig(bs, DEV_N0(), E.q(elem(bs, 0))))
    urow(String.concat(["hq2_b", nm, "_qsig1"]), qsig(bs, DEV_N0(), E.q(elem(bs, 1))))
    urow(String.concat(["hq2_b", nm, "_qsig2"]), qsig(bs, DEV_N0(), E.q(elem(bs, 2))))
    # THE STREAM. `hq2_b*_q_*` is compared against CPython's OWN sequence of
    # `u.op is Ops.INS` + `u.arg[0]` names, so a swapped pair moves the row.
    srow(String.concat(["hq2_b", nm, "_full"]), ins_str(queues_of(bs, False{})))
    srow(String.concat(["hq2_b", nm, "_full_p"]), ins_str(queues_of(bs, True{})))
    lrow(String.concat(["hq2_b", nm, "_stamps_p0"]), stamps(bs, 0, True{}))
    lrow(String.concat(["hq2_b", nm, "_stamps_p1"]), stamps(bs, 1, True{}))
    lrow(String.concat(["hq2_b", nm, "_stamps_p2"]), stamps(bs, 2, True{}))
    urow(String.concat(["hq2_b", nm, "_slots_p"]), slot_bytes(bs, True{}))
    urow(String.concat(["hq2_b", nm, "_nwait1_p"]), ins_n(waits(bs, 1)))
    # THE BUMP IS A `store` AND ONLY THE EPILOGUE HAS ONE -- :278 against :271.
    # `three` and `two` both answer one bump over four and two queues, so the
    # bump is per DEVICE and not per queue.
    urow(String.concat(["hq2_b", nm, "_bumps"]), count_kind(queues_of(bs, False{}), I_BUMP()))
    urow(String.concat(["hq2_b", nm, "_stores"]), count_kind(queues_of(bs, False{}), I_STORE()))
    urow(String.concat(["hq2_b", nm, "_ts_p"]), count_kind(queues_of(bs, True{}), I_TIMESTAMP()))
    urow(String.concat(["hq2_b", nm, "_calls"]), count_kind(queues_of(bs, False{}), I_CALL()))
    IO.pure(Unit, Unit{})

def t_batch() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_batch_one(Ethree(), "three")
    b : Unit <- t_batch_one(Etwo(), "two")
    c : Unit <- t_batch_one(Efifo(), "fifo")
    d : Unit <- t_batch_one(Ecopyq(), "copyq")
    e : Unit <- t_batch_one(Erevis(), "revis")
    # THE COUNTS NO SINGLE FIXTURE SEES. `three` has three queues and `revis` has
    # three calls on ONE, so `nq` answers 3 and 1 -- and a port that counted CALLS
    # would answer 3 and 3. `hq2_b_revis_nq` is that row.
    urow("hq2_b_revis_nq", nq(Erevis(), DEV_N0()))
    urow("hq2_b_three_nq", nq(Ethree(), DEV_N0()))
    urow("hq2_b_two_nq", nq(Etwo(), DEV_N0()))
    # `two` VERSUS `fifo`: SAME queue, overlapping versus disjoint buffers, so the
    # second call's wait count is 1 and 0 on the same shape. Without BOTH, a port
    # that waited for every earlier call would pass `two` and fail `fifo`.
    urow("hq2_b_two_nwait1", ins_n(waits(Etwo(), 1)))
    urow("hq2_b_fifo_nwait1", ins_n(waits(Efifo(), 1)))
    urow("hq2_b_revis_nwait2", ins_n(waits(Erevis(), 2)))
    urow("hq2_b_three_nwait2", ins_n(waits(Ethree(), 2)))
    # THE CALL GOES BETWEEN THE TWO TIMESTAMPS -- :267's `waits + ts[:1] + [call]
    # + ts[1:]` -- read off the STREAM rather than off `call_block`.
    row("hq2_b_three_call_inside_stamps", call_between_stamps(Ethree(), True{}))
    row("hq2_b_revis_call_inside_stamps", call_between_stamps(Erevis(), True{}))
    row("hq2_b_three_no_stamps_unprofiled", Bool.not(has_kind(queues_of(Ethree(), False{}), I_TIMESTAMP())))
    IO.pure(Unit, Unit{})

# ===========================================================================
# THE MUTATION TABLE. Every "rows moved" below is the HARNESS's output, not an
# estimate: `.agents/slop/hcq2-mutate.py` applies one edit to a scratch copy,
# runs the INTERPRETED lane, and counts the rows whose VALUE changed. The useful
# column is "rows moved", because a mutation that moves nothing measures what
# this gate does NOT see.
#
# THE HARNESS COMPARES VALUES AND NOT ROW NAMES. Its first version compared names
# and reported 0 for all thirty edits, which is the M30 trap wearing a different
# hat: a mutation changes what a row SAYS and never what a row is CALLED.
# ===========================================================================

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_consts()
    b : Unit <- t_name()
    c : Unit <- t_allin()
    d : Unit <- t_layout()
    e : Unit <- t_pack()
    f : Unit <- t_cstruct()
    g : Unit <- t_geom()
    h : Unit <- t_batch()
    IO.print("hq2-done=1")
# | # | the edit | rows moved | what it is testing |
# | --- | --- | --- | --- |
# | M1 | to_name.norm: drop the lower-case | 10 |
# | M2 | to_name.go: no `_` between parts | 360  -- GATE DIED |
# | M3 | to_name.go: reverse the accumulator | 0 |
# | M4 | all_in: `or` becomes `and` | 4 |
# | M5 | cdtype_of: 2 becomes 4 | 2 |
# | M6 | layout: the base offset is dropped | 15 |
# | M7 | layout: the itemsize is dropped from Arg.k | 7 |
# | M8 | pack.step: emit the pad even at gap 0 | 12 |
# | M9 | pack.trail: drop the trailing pad | 8 |
# | M10 | pack.trail: no refusal on a short size | 2 |
# | M11 | slot_bytes: drop the leading `2 *` | 13 |
# | M12 | slot_words: the profile arm adds 1 per call, not 2 | 7 |
# | M13 | stamp_n: `nq + 1` becomes `nq` | 20 |
# | M14 | qsig: the slot index is not doubled | 6 |
# | M15 | stl: the timeline slot is at `nq`, not `2*nq` | 4 |
# | M16 | epi: the two arms are swapped | 0 |
# | M17 | sig_tags: FIRST-WINS instead of LAST-WINS | 17 |
# | M18 | sig_tags: no queue signals | 20 |
# | M19 | call_block: the CALL goes BEFORE the pre-timestamp | 5 |
# | M20 | start_ins: the BARRIER is dropped | 15 |
# | M21 | start_n: the peer timeline wait is dropped | 15 |
# | M22 | epi_waits_n: the peer-queue waits are dropped | 10 |
# | M23 | overlaps: a write no longer waits for a prior READ | 10 |
# | M24 | prodq: the FIFO filter is dropped (every dep is its own queue) | 0 |
# | M25 | staging_chunk: one divide instead of two | 5 |
# | M26 | fld_at: the field lookup is by POSITION, not by NAME | 360  -- GATE DIED |
# | M27 | fld_names: drop every name | 2 |
# | M28 | cstruct_cmd_rows: context_id's offset is wrong | 2 |
# | M29 | fstr: no separator between field names | 2 |
# | M30 | control: a comment-only edit | 0 |

# THE TWO THAT DIED ARE COMPILE ERRORS, NOT ANSWERS. `M2` removes one `)` and
# `M26` swaps a name test for a counter test that does not typecheck the same way;
# both are reported as "the gate produced nothing" rather than as "0 rows", which
# is the distinction the harness exists to keep.
#
# ---------------------------------------------------------------------------
# WHAT THIS GATE STILL DOES NOT SEE. Three are BLIND SPOTS -- a mutation that moved
# nothing -- and each is a `0` that is a REQUEST FOR A FIXTURE or an honestly
# unfixable pair, never a coverage claim.
#
# 1. M3 MOVED NOTHING AND THAT IS A HARNESS ARTEFACT, NOT A RESULT. The edit
#    wraps the `to_name` accumulator in `List.reverse` and every `to_name` row is
#    unchanged. `to_name("submit","NV","COMPUTE:0")` is `submit_nv_compute_0`, so
#    reversing a three-element accumulator MUST change it. Either the edit did not
#    reach the code it names, or `List.reverse` there is an identity, and this
#    report does not claim to know which. IT IS LEFT IN THE TABLE AS A `0` BECAUSE
#    A `0` THAT IS NOT UNDERSTOOD IS STILL A `0`.
#
# 2. M16 -- `epilogue_queue`'s TWO ARMS ARE NOT SEPARABLE WITH ANY FIXTURE. :235 is
#    `"COMPUTE:0" if len(self.queues[dev]) != 1 else self.queues[dev][0]`, so the
#    two arms differ only when the device's queue list does NOT start at
#    `COMPUTE:0`. All five fixtures open with a `COMPUTE:0` call, so `qfirst` and
#    `Q_COMPUTE` are the same number everywhere and swapping them is an
#    EQUIVALENCE. THE FIXTURE THAT SEPARATES THEM IS A BATCH WHOSE FIRST CALL IS
#    ON `COPY:0`, and it needs a device with no COMPUTE queue at all -- which a
#    NULL batch cannot express because `sched_batches` (:321) always puts a
#    `PROGRAM` call on `COMPUTE:0`. REPORTED, NOT CLOSED.
#
# 3. M24 -- `latest`'s PER-QUEUE `max` IS NEVER EXERCISED. :246 keeps
#    `max(latest.get((d, q), 0), t)` per PRODUCER QUEUE, so the `max` fires only
#    when TWO deps of one call come from the SAME queue. That needs two earlier
#    calls on one queue writing overlapping buffers. The same-queue FIFO filter
#    (:246's `(d, q) != (device, queue)`) means those deps are FILTERED OUT before
#    `max` ever sees them, so under this port's model NO fixture can reach the
#    `max`. `prodq` collapsing to a plain append is therefore an EQUIVALENCE here.
#    IT IS THE SAME SHAPE AS THE `pc.find` BLIND SPOT ops_webgpu.bend reported:
#    a model whose answer is `len` on a miss and an index below it on a hit makes
#    the two predicates indistinguishable, so no fixture separates them. REPORTED.
#
# 4. THE PER-QUEUE LENGTHS. `hq2_b*_full` is the CONCATENATION of the four queue
#    streams, which pins the total ORDER and every slot index but does not say
#    where one queue ends and the next begins. CPython's per-queue rows
#    (`hq2_b*_q_NULL0_COMPUTE0`) do. An implementation that moved the boundary --
#    attributing one queue's epilogue to the next -- would print the same
#    concatenation. `hq2_b*_nqueues` and `hq2_b*_bumps` see the COUNT and not the
#    boundary.
#
# 5. THE OVERLAP MODEL IS TOTAL-OVERLAP ONLY. `DepsTracker.access_resources` (:182)
#    works in `(base, lane, offset, end)` ranges so a suballocated buffer that
#    overlaps only partly still waits. This port reduces a call to TWO WHOLE
#    buffers, so `overlaps` is an equality test and a partial overlap is not
#    representable. `E`'s `w`/`r` are buffer IDS and not ranges; giving them an
#    offset and a length is the change that would close this, and it is the same
#    machinery `device.bend`'s Buffer slots already have.
#
# 6. `(dev, q) in peers` IS VACUOUS IN EVERY FIXTURE. See THE SECOND DISJUNCT IS
#    VACUOUS: under DEV=NULL every queue of a non-empty batch has a peer, so
#    `signs` is always True and `hq2_b*_sig_tags` pins the LAST-WINS half alone.
#
# 7. `_finalize_batch`'s METADATA. `final_devs`, `final_kerns`, `final_nargs`,
#    `final_table`, `final_tag`, `final_name`, `final_nsubs` and `final_skipwait`
#    are CPython rows with no counterpart here: they read `KernelInfo`,
#    `Device[d].pm_batch` and `HCQInfo`, which is the arena wall.
#
# 8. `HWQueue.q` AND `HWQueue.encode` ARE PORTED AS A PLAN AND NOT AS A GATE ROW.
#    `hcq2.py:355-366`'s word ladder (`W_INT` is always FOUR bytes, `W_BINARY` is
#    appended VERBATIM, anything else is a patch plus zero bytes) is in this file
#    as `q`/`loop_*`, and its CPython counterparts are in
#    `.agents/slop/hcq2-probe2.py`. They are NOT in the 360-row gate, because the
#    trace that would carry them (`Tr`) is the `HWQueue.submit` raise and the qcom
#    FFI, and a trace whose only rows are a `NotImplementedError` measures
#    nothing. The CPython blob hex for each word shape is in the probe; a port
#    that transposed the little-endian byte order would agree with nothing in
#    this file. THAT IS THE GAP AND IT IS THE LARGEST ONE.
#
#    THIS ITEM ALSO CARRIED THREE NAMES THAT WERE NEVER DEFS, and it is worth
#    naming because the mutation table it points at does not have them either:
#    `pad128`, `rt_patch` and `dword_at` had 2 occurrences each -- this item and
#    the `bufferize_cmdbuf` row -- and ZERO defs, zero rows and zero mutations.
#    So "and in the mutation table" was false. What is true is narrower and is
#    what the row above now says: the 128-byte pad, the `o % 4 == 0` rt-patch
#    filter and the `+ 4 * k` dword stride all still exist UPSTREAM, inside
#    `encode_cmdbuf` (:449, :438, :441), and none of the three is ported as a
#    def here -- they were renamed out of the row by `bdddaad21` and were never
#    written. Three claims removed, and the gap they were hiding is GAP 8, which
#    is above and is still open.

