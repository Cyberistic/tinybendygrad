# tinybendygrad/runtime/support/hcq2.bend -- port of tinygrad/runtime/support/hcq2.py
#
# THE HARDWARE COMMAND QUEUE v2 SUBSTRATE. This is the queue model that the
# committed device ports already lean on: ops_nv.bend cites hcq2.py line numbers
# in its own header comments and PROOF rows, so those citations point at nothing
# until this file exists. See the "CITATIONS" section once the port lands.
#

# THE SPLIT, stated once and then obeyed: a def here EITHER builds the argument
# of one device call (pure, and the gate checks it) OR records that call in the
# trace (and the gate checks the ORDER). There is no third kind. Every seam is
# a trace tag and nothing else, so ORDER and IDENTITY are gateable even though
# none of them is made here.
#

# WHAT IS PORTED, DEF BY DEF. `hcq2.py` is 646 lines and most of it is a
# `graph_rewrite` over the UOp ARENA, which `uop/ops.bend` owns and this file
# must not re-derive. What survives as PURE ARITHMETIC is the queue model, and
# that is what is here.
#
#   hcq2.py:16 `HCQ_CACHE_THRESH`         PORTED  symbol=HCQ_CACHE_THRESH
#   tinygrad/device.py:19 `HCQ_DEVS`        PORTED  `HCQ_DEV_*` BOTH directions symbol=HCQ_DEVS
#   hcq2.py:29 `all_devices_in`           PORTED  `all_in` symbol=all_devices_in
#   hcq2.py:31 `get_enqueue_devs`          PORTED  `enq_*` (the table + refusals) symbol=get_enqueue_devs
#   hcq2.py:39 `unwrap_view`               PORTED  `view_*` (the offset arithmetic) symbol=unwrap_view
#   hcq2.py:45 `unwrap_lane`               PORTED  `lane_of` symbol=unwrap_lane
#   tinygrad/helpers.py:21 `to_name`       PORTED  symbol=to_name -- hcq2.py CALLS it in `make_submit`
#   hcq2.py:52 `timeline`                  PORTED  `tl*` symbol=timeline
#   hcq2.py:53 `timeline_value`            PORTED  symbol=timeline_value
#   hcq2.py:60 `make_submit`               PORTED  `submit_of` + `Tr` SUBMIT symbol=make_submit
#   hcq2.py:114 `layout_args`              PORTED  `layout` -- THE CITED ONE symbol=layout_args
#   hcq2.py:118 `pack_args`                PORTED  `pack` symbol=pack_args
#   hcq2.py:129 `cstruct`                  PORTED  `cstruct` FIELD ORDER symbol=cstruct
#   hcq2.py:234 `slot`                     PORTED  `slot` symbol=slot
#   hcq2.py:235 `queue_signal`             PORTED  `qsig` symbol=queue_signal
#   hcq2.py:236 `stamps`                   PORTED  `stamps` -- the `n -> n*2` symbol=stamps
#   hcq2.py:238 `_wait_ins`                PORTED  `waits` + `Tr` WAIT symbol=_wait_ins
#   hcq2.py:241 `_start_ins`               PORTED  `start` + `Tr` BARRIER/WAIT symbol=_start_ins
#   hcq2.py:244 `_build_queues`            PORTED  `build_queues` -- THE ORDER symbol=_build_queues
#   hcq2.py:288 `_finalize_batch`          PORTED  `finalize` + `Tr` FENCE/SUBMIT symbol=_finalize_batch
#   hcq2.py:311 `sched_batches`            PORTED  `copyq`, `qname_of`, `nqueues` symbol=sched_batches
#   hcq2.py:357 `__init__`                 PORTED  `hwq` symbol=__init__
#   hcq2.py:364 `q`                        PORTED  symbol=q -- THE WORD SEQUENCE
#   hcq2.py:377 `loop`                     PORTED  `loop_*` symbol=loop
#   hcq2.py:385 `memory_barrier`           PORTED  a no-op (records nothing) symbol=memory_barrier
#   hcq2.py:386 `submit`                   PORTED  `Tr.raise` -- THE REFUSAL symbol=submit
#   hcq2.py:93 `_is_link_patch`            PORTED  `is_link` (the ladder) symbol=_is_link_patch
#   hcq2.py:100 `patch`                    PORTED  `pkey` (the group key) symbol=patch
#   GONE upstream at this pin, each named with the construct that SURVIVED it:
#   `select_lane` (folded into upstream's `unwrap_lane`, tinygrad/runtime/support/hcq2.py:45 symbol=unwrap_lane),
#   `CDTYPE` (`dtypes.uints` at tinygrad/runtime/support/hcq2.py:130), `cfield` (`7d2420e64`;
#   `cstruct` at tinygrad/runtime/support/hcq2.py:129 reads the fields),
#   `STAGING_SIZE`/`STAGING_SLOTS` (`6816873ad`), `epilogue_queue` (`dc9af790e`,
#   the queues are built by `_build_queues` at :244), and `sched_tl`/`staging_chunk`,
#
# EVERY line number in both tables is a PIN NUMBER -- the upstream revision this
# tree vendors (`5c2bf39d6c4b`, whose `tinygrad/runtime/support/hcq2.py` is 563
# LINES). THE header was first written against a 646-LINE revision, SO NONE OF its
# NUMBERS survived the MOVE, AND mixing the two silently is what makes a citation
# UNRESOLVABLE, WHICH is the whole subject of the next block.
#
#   hcq2.py:73 `hcq_fence`               PORTED  `fence` + `Tr` FENCE symbol=hcq_fence -- `encode_fence` IS GONE upstream at this pin (`dc9af790e`)
#   hcq2.py:387 `encode`                 PORTED  `Tr` SUBMIT -- this is what the old
#                                            `encode_submit` row meant. `bdddaad21`
#                                            folded `encode_submit` INTO this
#                                            method, so `:479-481` is gone and the
#                                            replacement is ONE line, not a def.
#   hcq2.py:389 `encode_cmdbuf`          WALL 4  its blob arithmetic is UNREACHABLE
#                                            from a gate row (GAP 8). This row was
#                                            `:455-477 bufferize_cmdbuf PORTED
#                                            pad128/rt_patch/dword_at` and none of
#                                            those three names is a def here.
#   hcq2.py:416 `hoist_links`            WALL 1  a UPat over an AFTER symbol=hoist_links
#   hcq2.py:423 `pm_lift_deps`           WALL 1  the old `pm_renumber` row symbol=pm_lift_deps
#   hcq2.py:461 `lower_call`             WALL 1  the input TABLE is GONE
#                                            (`cff94ae88`) and with it the
#                                            128-byte merge, so this row's old
#                                            `slots_of` claim had no counterpart
#   hcq2.py:535 `hcq_compile`            PORTED  `compile_seq` -- THE INIT ORDER symbol=hcq_compile
#   hcq2.py:552 `hcq_link`               PORTED  `link_seq` symbol=hcq_link
#

# THE WALLS, named once each with the `hcq2.py` line that owns them.
#
# 1. THE uop arena -- THE reason that stood here was FALSE. MEASURED 2026-10-06: `graph_rewrite` IS a def (`codegen/__init__.bend:298`;
#    `uop/spec.bend:2725 symbol=kernel_graph_rewrite` `kernel_graph_rewrite`),
#    `UOp.toposort` IS a def
#    (`uop/ops.bend:3404 symbol=UOp.toposort`), and the port writes rules as `pm_*` defs over
#    `PMEntrys` returning `Maybe<&2, U32>` / `Verdict` (`uop/ops.bend:4047 symbol=PMEntrys`,
#    `:4033 symbol=Verdict`). So "every UPat/PatternMatcher/toposort reads and writes the UOp
#    graph" is NOT the blocker. The real blocker per rule is the absent symbol
#    its body calls: the SHAPED `UOp.param` (only the shape-less arm is ported,
#    upstream's `view_as` IS ABSENT FROM THE PORT (upstream's is `tinygrad/uop/ops.py:1236`), so that
#    arm has NO def to cite), `HCQInfo` (`CallInfo`
#    dropped `aux`, `uop/ops.bend:1145 symbol=CallInfo`), the realized-buffer/engine family
#    (`Buffer`/`_resolve`/`lower_and_compile`) and the `HWQueue` device methods.
#    THE `PORTED` TABLE above is not a witness for these: its helper names
#    (`view_*`, `pkey`, `submit_of`, `build_queues`, `finalize`, `hwq`, `enq_*`)
#    have 0 defs here (`pkey` is `renderer/ptx.bend:231 symbol=pkey`, a different function).
#    WALL(p3) tinygrad/runtime/support/hcq2.py:141   `pm_replace_buffers` symbol=pm_replace_buffers -- BLOCKED: needs the shaped `UOp.param` (`view_as` absent).
#    WALL(p3) tinygrad/runtime/support/hcq2.py:148   `pm_unwrap_multi` symbol=pm_unwrap_multi -- BLOCKED: rule body unwritten here (`UOp.mselect`/`UOp.replace` are defs at `ops.bend`; no `def pm_unwrap_multi` in this file).

#    WALL(p3) tinygrad/runtime/support/hcq2.py:180   `pm_insert_copy_staging` symbol=pm_insert_copy_staging -- BLOCKED: needs `Buffer`/`_resolve`/`lower_and_compile`.
#    WALL(p3) tinygrad/runtime/support/hcq2.py:336   `q_rewrite` symbol=q_rewrite -- BLOCKED: needs the `HWQueue` device methods (`exec`/`copy`/`encdec`)..
#    WALL(p3) tinygrad/runtime/support/hcq2.py:458   `pm_encode` -- BLOCKED: `pm_hcq_encode` is GONE upstream at this pin (`ad189c030`) and the matcher is `Compiled.pm_encode`; it needs `hcq_fence` (the `UPat.custom_function` target), `unwrap_view`/`patch`/`timeline`/`timeline_value` (the body's helpers): MEASURED, zero defs of each across `tinybendygrad/`.
#
#    WALL(p3) tinygrad/runtime/support/hcq2.py:423   `pm_lift_deps` symbol=pm_lift_deps -- BLOCKED: rule body unwritten here (`graph_rewrite` x3 / `UOp.after` x27 / `dedup` x2 are all defs; no `def pm_lift_deps` in this file).

#    WALL(p3) tinygrad/runtime/support/hcq2.py:452   -- BLOCKED: needs the shaped `UOp.param` and
#    `UOp.substitute` (uop/ops.bend:514 symbol=GroupOp.commutative, open TODO) -- the row `pm_lift`.
#    WALL(p3) tinygrad/runtime/support/hcq2.py:458   -- BLOCKED: needs `HCQInfo`; `CallInfo` has no `aux` (`uop/ops.bend:1157`) -- the row `pm_encode`.
#    TODO(p3) runtime/support/hcq2.py:552  symbol=hcq_link -- `Compiled.pm_link` -- the link matcher upstream declares at module level (upstream line 478) and rewrites with in `hcq_link`.
#
#    THREE names that were on this list and are not any more, each because
#    upstream RENAMED it and one because upstream DELETED it. The rename is not
#    cosmetic: the bodies moved too, so re-pointing the name and calling it done
#    would be a lie of the same shape as the name it replaced.
#      pm_patches  -> `pm_hoist_links` (:421). `hoist_links` moved from section
#                     3.2 "split" to 3.3 "lift" AND its `partition` predicate
#                     grew a case: `s.op is Ops.STORE and _is_link_patch(s)`
#                     became `(s.src[0] if s.op is Ops.END else s).op is
#                     Ops.STORE and _is_link_patch(s)` -- a store OR ITS LOOP.
#      pm_renumber -> `pm_lift` (:452). The RANGE rule's `arg` tuple also
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
# 2. FFI AND CTYPES. `ccall` (:125), `cstruct`'s `ctypes.sizeof` (:129-133),
#    and the `_ioctl` family -- upstream's `_do_ioctl` IS its root -- in
#    `tinygrad/runtime/support/c.py:6-15`, and upstream's `_do_ioctl` IS at
#    tinygrad/runtime/support/c.py:6 (`_do_ioctl`), and upstream's `_IO`,
#    `_IOW`, `_IOR` and `_IOWR` ARE the four wrappers at
#    tinygrad/runtime/support/c.py:14-17 (`_IO` IS the first of them). `cfield` IS GONE upstream
#    at this pin (`7d2420e64`): `cstruct` (:129) reads `struct_t._real_fields_`
#    where `cfield` read `getattr(...).offset/.size`. `dtype.bend`'s fourteen
#    `def ... -> IO(R)` + `import "./x.c"` seams make every IMPORTER print
#    `SOME PROOFS FAIL`; this file follows the ops_webgpu lane instead and records
#    the call in a `Tr`, so it is ALL PROOFS CHECK and the seam stays greppable.
#    TODO(p3) tinygrad/runtime/support/hcq2.py:125   `ccall` symbol=ccall -- `ctypes` marshalling.
#    TODO(p3) runtime/support/c.py:66  symbol=_resolve -- `cfield` is GONE upstream at this pin; `Field._resolve` is the shape that replaced it -- the ctypes field descriptor, not a `getattr`.
#    `cfunc_buf` WAS ON THIS LIST AND IS DELETED, not renamed. Upstream
#    `bdddaad21` ("ccall by symbol", #18521) deleted the function AND its caller
#    in `device.py` (`pm_bufferize`'s third rule), because `ccall` no longer needs
#    a `Buffer` to hold the C function pointer -- the placeholder UOp went with it
#    and `ccall` is now `UOp.custom_function(fn.__name__, dtype=ret).call(...)`.
#    So there is no `# TODO(p3)` left to write: there is nothing upstream to defer.
#
# 3. A `String` IS a linked list of `Char`s WITH one visible constructor, so
#    `to_name` (:61) is `String.split` + `String.join` + `String.to_lower`, and
#    `String.replace` DOES NOT EXIST. The fold is ported; the CHARACTER-level
#    lower-casing inside `String.to_lower` is base.bend's, not this file's.
#    HEADER-ONLY file now, and its header's `to_name` stage names upstream's
#    `to_name` (tinygrad/helpers.py:21 symbol=to_name), whose `.replace(":", "_")`
#    IS the character-level copy this sentence is about -- while `hq2_toname_*`
#    rows are generated by CALLING
#    `hcq2.to_name`, so the two implementations are checked against one oracle.
#
# 4. THE 64-BIT WALL. `base.bend` exports `Word`, not `Word(64n)`, so a u64
#    VALUE is not one number here. `HWQueue.q` (:364-376) masks `v` with
#    `1 << 8*n - 1` and writes `n` little-endian bytes, which for `n == 8` is
#    both halves of a u64; `W` therefore carries `lo` AND `hi` and the byte
#    sequence is exact. What is NOT computable is a u64 ARITHMETIC. `nbytes` is
#    the only one this file ever needed, and it is `size * itemsize` in `U32`.
#
#    THIS wall used to name a DEF THAT does not exist. It said "`slots_of`
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

# CITATIONS -- what the NV path already assumes about this file.

# THE port's OWN `ops_nv.bend` IS a header-ONLY file now: it has ZERO `def`
# DECLARATIONS, so a pointer into its BODY names a line that does not exist.
# What it DOES carry is its own STAGE header, and the STAGE header names the
# UPSTREAM construct each stage was ported from. So the citations below are
# UPSTREAM citations, and the PORT's own `ops_nv.bend` is named as the PORT's own.
#
# upstream's `layout_args` (tinygrad/runtime/support/hcq2.py:114 symbol=layout_args)
#   is called from upstream's `ops_nv.py` -- upstream's `layout_args` IS the
#   callee there, at tinygrad/runtime/ops_nv.py:178, and
#   the PORT's `ops_nv.bend` STAGE 2 header records that same `layout_args`
#   trace. MEASURED IN CPython (`.agents/slop/hcq2-probe.py`, run with
#   DEV=NULL so no device is present):
#     layout_args(3x uint64, 0)      -> 0, 8, 16
#     layout_args(6 mixed, 0)        -> 0, 4, 8, 16, 24, 28
#     layout_args(3x uint64, 512)    -> 512, 520, 528
#     layout_args(6 mixed, 512)      -> 512, 516, 520, 528, 536, 540
#   `0, 4, 8, 16, 24, 28` for the mixed list: the file is header-only, so the
#   claim lives here, against `hcq2.layout_args` itself. The `512` base is
#   upstream's `qmd_sz` (tinygrad/runtime/ops_nv.py:135), and the five entries
#   `512, 520, 528, 536, 540` are the 3-buffer-and-2-u32 list, of which CPython
#   agrees on all
#   five once the two `uint32` vars are appended to the three `uint64` buffers
#   (`buf3_var2` is five words: 0,8,16,24,28 relative -> 512,520,528,536,540
#   with 540 the trailing var). The `0, 4, 8, 16, 24, 28` is the
#   SAME SIX-WORD mixed list at base 0.
# upstream's `to_name` (tinygrad/helpers.py:21 symbol=to_name) is called from
#   upstream's `ops_nv.py` at tinygrad/runtime/ops_nv.py:127 (`to_name` IS the
#   callee there) and :137, and the
#   PORT's `ops_nv.bend` STAGE 4 header records the same `to_name`: CONFIRMED,
#   same
#   formula, and `hq2_toname_*` below are the same rows from this side.
# upstream's `ops_nv.py:386` cites `hcq2`'s `nv_iowr` arm `if made.status != 0`;
#   upstream's `ops_nv.py:178` cites `NVQueue.q` (hcq2.py:366). upstream's `HWQueue`
#   IS the class that holds
#   that `q` method and it is at :335 (`HWQueue` IS the class), so `NVQueue` has
#   NO upstream counterpart
#   at this pin. `q` is PORTED as `q` below; the ioctl arm
#   is ops_nv's own FFI seam and is not this file's.
# upstream's `ops_nv.py` notes that the NV path goes through these queues. That
#   is the claim `q` and `Tr` SUBMIT below carry -- `hwq` is named here but is
#   NOT a def in this file (2 occurrences in this header, 0 defs), and
#   the `HWQueue.encode` METHOD. What `Tr` SUBMIT carries is that one submission
#   ends in exactly one `submit` call, which is the part of `encode` that is not
#   the queue's own body.
#

# AGREEMENT WITH `runtime/support/nv/ip.bend`, answered from the PYTHON.
#
# That file asked three things to be agreed or contradicted (its own header,
# "THE SHARED CONTRACT WITH hcq2"): the `nv.msgqTxHeader` queue header, the
# ring's usable length, and the doorbell. ALL THREE ARE `nv/ip.py`'s AND NOT
# `hcq2.py`'s, AND NONE OF them appears in the 563 LINES this file ports.
# MEASURED, not assumed:
#
#   $ grep -n "msgqTxHeader\|ring_len\|queue_mv\|doorbell\|cmd_q\|stat_q\
#               q_size\|MAX_BUFS" tinygrad/runtime/support/hcq2.py
#   (no output)
#   $ grep -n "msgqTxHeader\|ring_len\|doorbell" tinygrad/runtime/support/nv/ip.py
#   22, 23, 26, 47, 51, 64, 384, 385
#
# So `q_size`/pack factors, the front-end sizes, the completion-ring geometry and
# the MAX_BUFS/fence counts the brief grouped under "per-queue constants" ARE NOT
# IN `hcq2.py` -- they are in `ops_nv.py` (which is `ops_nv.bend`, green and
# read-only) and in `nv/ip.py` (`nv/ip.bend`). THIS file does not carry them and
# ITS OWN HEADER SAYS SO, because claiming a per-queue constant that lives in a
# sibling would be a fabricated table. The constants `hcq2.py` really owns are the
# four at the top: `HCQ_CACHE_THRESH`, `HCQ_DEVS`, `CDTYPE`, and
# `STAGING_SIZE`/`STAGING_SLOTS` -- all four gated BOTH ways, the last two GONE upstream.
#
# THE one genuinely shared surface is the submission path, and it does not
# contradict: `ip.bend`'s `Tr` is `&2` lists of ioctl records with its own `Cx`
# payload type, this file's `Tr` is `&2` lists of `Call{k, a, b, c}` recording
# `hcq_fence`, `make_submit` and `HWQueue.submit`. Neither file names a symbol of
# the other and neither carries a table the other reads, so there is nothing to
# reconcile -- REPORTED, not reconciled, because reconciling would mean editing a
# read-only file. WHAT a third file will have to agree with: that the doorbell
# write happens AFTER the write pointer advances (`ip.bend`'s point 3) and that
#   this file's `_finalize_batch` orders `hcq_fence` BEFORE the submits (:288's
# `make_submit(...).after(fence, *submits[-1:])`). Both are ORDER claims about
# DIFFERENT halves of one submission, and the gate rows for this file's half are
# `hq2_b*_full`.
#

# STATUS: ALL three stages landed and checked.
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
# THE 120 ROWS CPYTHON HAS and this port does not are not coverage and not
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

# THE CONSTANTS, and each one is gated BOTH WAYS. A value that does not name
# its own value is a wrong submission waiting for a driver.

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

def dev_head.name() -> List<&2, String>: ["NV", "QCOM", "CUDA", "NULL", "METAL", "AMD"]

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

def STAGING_SIZE() -> U32: 134217728
def STAGING_SLOTS() -> U32: 2
def staging_slot_bytes() -> U32: U32.div(STAGING_SIZE(), STAGING_SLOTS())

def staging_chunk(it: U32) -> U32: U32.div(staging_slot_bytes(), it)

type Call is Data:
  Call{k: U32, a: U32, b: U32, c: U32}

type Tr is Data:
  Tr{calls: List<&2, Call>, next: U32, bad_at: U32, seen: U32, refused: Bool}

type Qd is Data:
  Qd{blob: List<&2, U32>, ps: List<&2, U32>}

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

# READING THE TRACE. `Tr.seq` is the `a` of every call with tag `k`, IN ORDER
# -- for a queue that is the sequence of slot indices and for the batch that is
# the sequence of step kinds. `Tr.count` is how many. `Tr.has` is "contains this
# (k, a, b, c) sequence, in order", and it is a real SUBSEQUENCE test: the fuel
# is the TRACE length and the answer is `at == patlen` (the bug ops_webgpu.bend
# measured, where a fuel set to the PATTERN length made a reversed pattern match).

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

def nats_eq(+a: List<&2, U32>, +b: List<&2, U32>) -> Bool: H.u32_list_eq(a, b)

# hcq2.py:63 `to_name(*parts) = "_".join(parts).replace(":", "_").lower()`.
#
# THE ORDER IS THE CLAIM: the replace is on the ORIGINAL case and the lower is
# LAST, so `to_name("submit", "NV", "COMPUTE:0")` is `submit_nv_compute_0` and
# not `submit_nv_compute:0`. `String.split` THROWS THE SEPARATORS AWAY, so the
# tail has to be re-joined with them -- upstream's `to_name`
# (tinygrad/helpers.py:21 symbol=to_name) IS that join, and the PORT's own
# `ops_nv.bend` NO LONGER CARRIES the row that measured this exact
# bug and got `ring_compute0` where CPython prints `ring_compute_0`.
#
# `dev.bend`'s `rest_of` is the same fix with `:` where this needs `_`.

def to_name.norm(+s: String) -> String:
  String.to_lower(String.join(String.split(s, ':'), "_"))

# `List.append(a, A, xs, ys)` is `xs ++ ys`, so the accumulator below is already
# in FORWARD order and the fold ends with a plain `String.concat`. Reversing it
# is the bug the PORT's own `ops_nv.bend` NO LONGER CARRIES measured and
# recorded: it printed
# `0COMPUTE_` where CPython prints `COMPUTE_0`.
def to_name.go(parts: List<&2, String>, +acc: List<&2, String>) -> String:
  match parts:
    case Nil{}: String.concat(acc)
    case h <> Nil{}: String.concat(List.append(&2, String, acc, [to_name.norm(h)]))
    case h <> t: to_name.go(t, List.append(&2, String, acc, [String.concat([to_name.norm(h), "_"])]))

def to_name(+parts: List<&2, String>) -> String: to_name.go(parts, Nil{})

def all_in.go(+ds: List<&2, String>, nm: String, hit: Bool) -> Bool:
  match ds:
    case Nil{}: hit
    case h <> t: all_in.go(t, nm, Bool.or(hit, U32.is_ne(dev_id(dev_head(h)), NO_HCQ_DEV())))

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

def layout_off.go(n: Nat, as: List<&2, Arg>, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match as:
        case Nil{}: acc
        case a <> t: layout_off.go(m, t, List.append(&2, U32, acc, [Arg.at(a)]))

def layout_k.go(n: Nat, as: List<&2, Arg>, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match as:
        case Nil{}: acc
        case a <> t: layout_k.go(m, t, List.append(&2, U32, acc, [Arg.k(a)]))

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

def fld_at.go(n: Nat, fs: List<&2, Fld>, +nm: String, d: U32) -> U32:
  match n:
    case 0n: d
    case 1n+m:
      match fs:
        case Nil{}: d
        case +f <> t: fld_at.go(m, t, nm, Bool.pick(U32, String.eq(Fld.name(f), nm), Fld.at(f), d))

def fld_sz.go(n: Nat, fs: List<&2, Fld>, +nm: String, d: U32) -> U32:
  match n:
    case 0n: d
    case 1n+m:
      match fs:
        case Nil{}: d
        case +f <> t: fld_sz.go(m, t, nm, Bool.pick(U32, String.eq(Fld.name(f), nm), Fld.sz(f), d))

def fld_sizeof.go(n: Nat, fs: List<&2, Fld>, +last: U32, +size: U32) -> U32:
  match n:
    case 0n: size
    case 1n+m:
      match fs:
        case Nil{}: size
        case +f <> t: fld_sizeof.go(m, t, U32.add(Fld.at(f), Fld.sz(f)),
                                    U32.max(size, U32.add(Fld.at(f), Fld.sz(f))))

def fld_names.go(n: Nat, fs: List<&2, Fld>, +acc: List<&2, String>) -> List<&2, String>:
  match n:
    case 0n: acc
    case 1n+m:
      match fs:
        case Nil{}: acc
        case f <> t: fld_names.go(m, t, List.append(&2, String, acc, [Fld.name(f)]))

def fld_offs.go(n: Nat, fs: List<&2, Fld>, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match fs:
        case Nil{}: acc
        case f <> t: fld_offs.go(m, t, List.append(&2, U32, acc, [Fld.at(f)]))

def fld_szlist.go(n: Nat, fs: List<&2, Fld>, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match fs:
        case Nil{}: acc
        case f <> t: fld_szlist.go(m, t, List.append(&2, U32, acc, [Fld.sz(f)]))

def fld_real.go(n: Nat, fs: List<&2, Fld>, +got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match fs:
        case Nil{}: got
        case +f <> t: fld_real.go(m, t, U32.add(got, Bool.to_u32(cdtype.is(Fld.sz(f)))))

def fld_cdt.go(n: Nat, fs: List<&2, Fld>, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match fs:
        case Nil{}: acc
        case +f <> t: fld_cdt.go(m, t, List.append(&2, U32, acc, [cdtype_of(Fld.sz(f))]))

def fld_name.go(n: Nat, fs: List<&2, Fld>, +at: U32, d: String) -> String:
  match n:
    case 0n: d
    case 1n+m:
      match fs:
        case Nil{}: d
        case +f <> t: fld_name.go(m, t, at, Bool.pick(String, U32.is_eq(Fld.at(f), at), Fld.name(f), d))

def fstr.go(n: Nat, xs: List<&2, String>, +acc: List<&2, String>) -> List<&2, String>:
  match n:
    case 0n: acc
    case 1n+m:
      match xs:
        case Nil{}: acc
        case h <> t: fstr.go(m, t, List.append(&2, String, acc, [String.concat([" ", h])]))

def asc.go(n: Nat, +xs: List<&2, U32>, prev: U32) -> Bool:
  match n:
    case 0n: True{}
    case 1n+m:
      match xs:
        case Nil{}: True{}
        case h <> t: asc.go(m, t, h) && U32.is_le(prev, h)

def ush(xs: List<&2, U32>, +sep: String, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case h <> t: ush(t, sep, List.append(&2, String, acc, [String.concat([sep, U32.show(h)])]))

def joined(+xs: List<&2, U32>, +sep: String) -> String:
  String.drop(String.concat(ush(xs, sep, Nil{})), String.length(sep))

def bstr(+xs: List<&2, U32>) -> String: joined(xs, "")

def brow(nm: String, +xs: List<&2, U32>) -> IO(Unit):
  IO.print(String.concat([nm, "=", bstr(xs)]))

# THE batch: hcq2.py:209-311. THE fence and completion model, and almost all of
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

def DEV_N0() -> U32: 1
def DEV_N() -> U32: 2
def Q_COMPUTE() -> U32: 1
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
# `seenq` MUST see the tail and not the list: the head is the candidate, so
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

def stamp_n(+bs: List<&2, E>, +tag: U32, +profile: Bool) -> U32:
  Bool.pick(U32, profile, U32.add(U32.add(nq(bs, DEV_N0()), 1), U32.mul(2, tag)), 0)

def slot_words(+bs: List<&2, E>, profile: Bool) -> U32:
  U32.add(U32.add(nq(bs, DEV_N0()), 1),
          Bool.pick(U32, profile, U32.mul(2, U32.from_nat(List.length(&2, E, bs))), 0))

def peer_slot_words(profile: Bool) -> U32: Bool.pick(U32, profile, 7, 1)

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

# `signal_tags` (:230) -- THE LAST-WINS RULE, and it is the rule most likely to
# be got wrong, because `self.last` holds ONE tag per queue:
#   {tag for (dev, q), tag in self.last.items() if q != epilogue(dev) or (dev, q) in peers}
# so only the LAST call on a queue can signal. `two` answers `1` (not `0 1`) and
# `revis` answers `2` (not `0 1 2`): that is the whole content of the rule, and
# no single-queue fixture with one call could ever see it.
#
# THE second disjunct is vacuous in every fixture and the gate says so.
# `(dev, q) in peers` is True for every queue that runs a call on a device whose
# `Device.canonicalize` differs from the enqueue device, which under DEV=NULL is
# every batch (`canonicalize('NULL:0')` is `'NULL'`). A fixture that made it
# False needs a device with no peers, and no NULL batch has one. So the gate
# cannot separate `q != epi` from `or (dev, q) in peers`, and `hq2_b*_sig_*` are
# rows about the LAST-WINS half alone. That is a reported blind spot.

def epi(+bs: List<&2, E>, +dev: U32) -> U32:
  Bool.pick(U32, U32.is_eq(nq(bs, dev), 1), qfirst(qlist(bs, dev)), Q_COMPUTE())

# THE QUEUE NAMES, because `epilogue_queue` (:235) answers a STRING and the gate
# compares strings against `ctx.epilogue_queue(dev)`.
def qname(q: U32) -> String:
  match q:
    case 1: "COMPUTE:0"
    case 2: "COPY:0"
    case _: "COPY:1"

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

# `DepsTracker.access_resources` (:182-207) reduced to WHO OVERLAPS WHOM, and
# `_wait_ins` (:242-252) which turns that into the WAIT list.
#
# :191 collects every producer whose WRITE range overlaps a READ of this call;
# :192 adds, for each range this call WRITES, every producer whose READ range
# overlaps it -- a write must follow a prior read of the same buffer. With two
# whole buffers per call and no suballocation:
#   overlap(i, t) = (r(i) == w(t)) or (w(i) == w(t)) or (w(i) == r(t))

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

# `_start_ins` (:254-256) -- `INS(("barrier", void), ())` and then ONE WAIT ON
# THE DEVICE TIMELINE per device in `[dev, *sorted(peers[(dev, queue)])]`. So
# it is a BARRIER, then `1 + npeers` TIMELINE waits, and the peer's wait is what
# makes the first queue of a device wait for the work another device already did
# on its memory. Under DEV=NULL `peers[('NULL:0', q)] == {'NULL'}` for every
# queue, so `start_n` is 3 for `NULL:0` and 2 for the canonicalized `NULL` --
# whose peers key is ABSENT, and that is why its epilogue queue starts with
# only ONE timeline wait.

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

# `_build_queues` (:258-283) -- THE ORDER, and it is the load-bearing part of the
# whole file:
#
#   :263  first use of a queue -> `_start_ins(devices[0], queue)`
#   :266  ts_ins = one TIMESTAMP per stamp slot
#   :267  `q += waits + ts_ins[:1] + [call] + ts_ins[1:]`
#         -- THE call goes between the two timestamps, never outside them
#   :270  `if tag in ctx.signal_tags: q += [INS(("store", ...))]`
#   :276  the epilogue waits for every OTHER queue of the device and every peer
#         queue that touched it, then
#   :278  BUMPS the device timeline -- and :281 adds `_start_ins` first if the
#         epilogue queue is one with no calls of its own.
#
# So every queue's stream is
#   [BARRIER, TIMELINE waits...] ++ dependency waits ++ [pre-TIMESTAMP] ++ CALL
#   ++ [post-TIMESTAMP] ++ [SIGNAL if this tag is the queue's LAST] ++ epilogue.

# `_build_queues` (:258-283) -- THE ORDER, and it is the load-bearing part of the
# whole file:
#
#   :263  first use of a queue -> `_start_ins(devices[0], queue)`
#   :266  ts_ins = one TIMESTAMP per stamp slot
#   :267  `q += waits + ts_ins[:1] + [call] + ts_ins[1:]`
#         -- THE call goes between the two timestamps, never outside them
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

# THE EPILOGUE TAIL (:273-282), appended to the device's epilogue queue.
# `epi_waits(dev)` is
#   (every OTHER queue of dev) + (every (dev, queue) key of peers that `dev` is a
#   member of), and for `NULL:0` the second set is EMPTY -- its peers hold the
#   NAME `'NULL'`, not `'NULL:0'` -- while for `NULL` the first set is empty and
#   the second is every queue that ran a call. That asymmetry is the whole of
# `hq2_bthree_q_NULL_COMPUTE0` and it is a string comparison in Python and an id
# comparison here.

def epi_waits_n(+bs: List<&2, E>, +dev: U32) -> U32:
  Bool.pick(U32, U32.is_eq(dev, DEV_N0()), U32.sub(nq(bs, dev), 1), npairs(bs))

def tl_wait(dev: U32) -> Ins: Ins{I_WAIT(), TIMELINE_MARK(), dev, 0}

# A self-CALL may not pass a computed fuel (`Nat.sub(n, 1n)` is not decreasing),
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

# THE WHOLE QUEUE STREAM, in the ORDER `_build_queues` returns it: every distinct
# (device, queue) pair in first-use order, and then -- LAST -- the canonicalized
# PEER device's epilogue queue, which exists only because
# `canonicalize('NULL:0')` is `'NULL'` and which holds no calls of its own (:281).

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

def count_kind.go(n: Nat, +xs: List<&2, Ins>, +k: U32, got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match xs:
        case Nil{}: got
        case x <> t: count_kind.go(m, t, k, U32.add(got, Bool.to_u32(U32.is_eq(Ins.k(x), k))))

def count_kind(+xs: List<&2, Ins>, k: U32) -> U32: count_kind.go(List.length(&2, Ins, xs), xs, k, 0)

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

def prev_last_of(+bs: List<&2, E>, +tag: U32) -> U32:
  Bool.pick(U32, U32.is_eq(prevt(bs, tag), tag), 0, prevt(bs, tag))

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

def ins_str.go(n: Nat, +xs: List<&2, Ins>, +acc: List<&2, String>) -> List<&2, String>:
  match n:
    case 0n: acc
    case 1n+m:
      match xs:
        case Nil{}: acc
        case +x <> t: ins_str.go(m, t, List.append(&2, String, acc, [String.concat([" ", iname(x)])]))

def head_of.at(m: Maybe<&2, U32>) -> U32:
  match m:
    case Some{g}: g
    case None{}: 0

type Al is Data:
  Al{has_name: Bool, name: String, dev: String, dev_ix: U32, n: U32, dt: S.Dt}

type Bz is Data:
  Bz{ar: D.Bar, level: U32, kind: U32, buf: U32, nb: U32, dev: String}

def HCQ_RUNTIME_DEV() -> String: "CPU"

# `max(b.max_numel(), 1)` -- upstream's `max`, and it is what makes a
# ZERO-element alloc allocate one element rather than none.
def bz_max1(+n: U32) -> U32:
  Bool.pick(U32, U32.is_zero(n), 1, n)

# `BufferSpec(cpu_access=True)` -- the ALLOCATION path's spec (device.py:88's
# five flags, in its order).
def bz_spec() -> D.Bspec:
  D.Bspec{False{}, True{}, False{}, False{}, False{}}

# `Compiled.timeline`'s spec: `BufferSpec(host=True, uncached=True,
# cpu_access=True)` (device.py:414).
def bz_tl_spec() -> D.Bspec:
  D.Bspec{True{}, True{}, True{}, False{}, False{}}

# A FRESH buffer in the arena. `D.root` takes the ELEMENT count and the
# dtype, and `Bn.nbytes` is `size * itemsize`, so a 16-byte buffer is 16
# `uint8`s.
def bz_new(+ar: D.Bar, dev_ix: U32, n: U32, dt: S.Dt, sp: D.Bspec) -> D.BFound:
  D.bnew(ar, D.root(dev_ix, n, dt, sp))

# THE UNNAMED PATH. `UOp.new_buffer(b.device, b.max_numel(), b.dtype)` -- a
# FRESH buffer, NOT linked, sized `max_numel * itemsize` -- NO `max(..., 1)`,
# which is the allocation path's and not this one's -- with the DEFAULT spec,
# and PLACED ON THE ALLOC'S OWN DEVICE.
def bz_unnamed2(f: D.BFound, dev: String, n: U32, dt: S.Dt) -> Bz:
  match f:
    case D.BFound{ar, i}: Bz{ar, 0, 2, i, U32.mul(n, S.Dt.itemsize(dt)), dev}

def bz_unnamed(+ar: D.Bar, +dev: String, +dev_ix: U32, +n: U32, +dt: S.Dt) -> Bz:
  bz_unnamed2(bz_new(ar, dev_ix, n, dt, D.spec()), dev, n, dt)

# THE ALLOCATION PATH. `Buffer(dev.device, max(b.max_numel(), 1) *
# b.dtype.itemsize, options=spec, preallocate=True)` -- a FRESH buffer, on the
# RUNTIME device.
def bz_alloc2(f: D.BFound, n2: U32, dt: S.Dt) -> Bz:
  match f:
    case D.BFound{ar, i}: Bz{ar, 4, 2, i, U32.mul(n2, S.Dt.itemsize(dt)), HCQ_RUNTIME_DEV()}

def bz_alloc(+ar: D.Bar, +dev_ix: U32, +n: U32, +dt: S.Dt) -> Bz:
  bz_alloc2(bz_new(ar, dev_ix, bz_max1(n), dt, bz_spec()), bz_max1(n), dt)

# A REGISTRY or HOOK hit. The buffer that won is an EXISTING arena slot and
# ITS SIZE IS ITS OWN: upstream never resizes a registered buffer to fit the
# alloc -- the `owned` branch hands the registry's buffer straight to
# `UOp.from_buffer` -- so this reads the SLOT and not the alloc.
def bz_hit2(nb: U32, ar: D.Bar, level: U32, kind: U32, buf: U32) -> Bz:
  Bz{ar, level, kind, buf, nb, HCQ_RUNTIME_DEV()}

def bz_nb(+ar: D.Bar, buf: U32) -> U32:
  D.nbytes(ar, buf)

# THE FOUR-WAY. Level 0 is the UNNAMED path and it returns before the
# resolution, so the only level that arrives here besides the three hits is
# 4 -- allocate.
def bz_pick(+level: U32, +kind: U32, +buf: U32, +nb: U32, +ar: D.Bar,
            +dev_ix: U32, +n: U32, +dt: S.Dt) -> Bz:
  match level:
    case 1: bz_hit2(nb, ar, 1, kind, buf)
    case 2: bz_hit2(nb, ar, 2, kind, buf)
    case 3: bz_hit2(nb, ar, 3, 2, buf)
    case _: bz_alloc(ar, dev_ix, n, dt)

# THE NAMED PATH. `link_resolve` asks the registry's PLAIN key first, then the
# registry's DEVICE-SCOPED key, then the device's own `link_buffer`, and
# answers the four-way with the LEVEL, the Buffer-vs-CALLABLE KIND and the
# ARENA SLOT of the buffer that won.
def bz_of(r: D.LkRes, +ar: D.Bar, +dev_ix: U32, +n: U32, +dt: S.Dt) -> Bz:
  match r:
    case D.LkRes{level, kind, +buf}:
      bz_pick(level, kind, buf, bz_nb(ar, buf), ar, dev_ix, n, dt)

def bz_named(+regs: List<&2, D.Lk>, +hook: D.Hook, +ar: D.Bar, +name: String,
             +dev: String, +dev_ix: U32, +n: U32, +dt: S.Dt) -> Bz:
  bz_of(D.link_resolve(regs, Maybe.pure(&2, String, name), dev, hook),
        ar, dev_ix, n, dt)

def bz_ix_cpu() -> U32: 7
def bz_tl_arena2(f: D.BFound) -> D.Bar:
  match f:
    case D.BFound{ar, i}: ar

def bz_reg_dev() -> List<&2, D.Lk>: [D.Lk{D.to_name(["CPU", "mine"]), 0, 2}]
def bz_al_n(name: String, dev: String, dev_ix: U32, n: U32) -> Al:
  Al{True{}, name, dev, dev_ix, n, S.uint8()}
