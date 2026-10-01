# tinybendygrad/runtime/ops_metal.bend -- port of tinygrad/runtime/ops_metal.py
#
# THE HALF OF THE METAL CHAIN THAT SUBMITS. `renderer/cstyle.bend` already emits
# Metal kernel TEXT and its `kern2 METAL` rows are committed and green, so the
# shader half of this chain exists. This file is the other half: the 287 lines
# that turn a compiled program and a list of buffers into an
# `MTLComputePipelineState`, an indirect command buffer, and a committed
# command buffer.
#
# ---------------------------------------------------------------------------
# DOES IT COMPOSE WITH cstyle.bend? YES, AND THE SEAM IS ONE BINDING.
#
# `cstyle.py:398-403` gives a Metal kernel EXACTLY ONE buffer argument --
# `constant args_t& args [[buffer(0)]]` -- with every global pointer and every
# ALU scalar packed into that struct. And `ops_metal.py:263` binds it with
# `cmd.setKernelBuffer_offset_atIndex(buf.get_storage().meta, off, 0)`:
# buffer index 0, the ICB header Buffer, byte offset `off`. `:264` then sets the
# geometry with `concurrentDispatchThreadgroups_threadsPerThreadgroup(MTLSize
# (*dims[:3]), MTLSize(*dims[3:]))`, and `dims` is
# `(*prg.arg.global_size, *prg.arg.local_size)` at :116.
#
# So the four numbers the two files have to agree on, and DO, are:
#
#   1. ONE binding, at index 0.        `:256 setMaxKernelBufferBindCount(1)`
#   2. the struct's byte offset,       `:112 off = round_up(self.nbytes, 256)`
#   3. the global size and the local   `:116 dims = (*global_size, *local_size)`
#      size, as two MTLSizes,          `:264 MTLSize(*dims[:3]), MTLSize(*dims[3:])`
#   4. the entry point NAME,           `:247 newFunctionWithName(to_ns_str(name))`
#      which is `TinyELF.name`, the same string cstyle's `function_name`.
#
# The one thing still missing for a RUN on this host is `MetalCompiler.compile`
# (:42-71). **AND THAT IS NOW MEASURED RATHER THAN ASSERTED** -- see `t_seam`.
#
# `compile` is FFI at EXACTLY TWO points: `MTLCodeGenServiceCreate` (:39) and
# `MTLCodeGenServiceBuildRequest` (:68). Both are already in the trace. Everything
# else in :42-71 is a Python closure and a `struct`, and it is all ported and gated:
# the four-way `-std=` ladder, the `params` f-string, the 4-byte-padded source blob,
# the NUL, the 16-byte `<QQ` request header, the two blob lengths, the callback's
# `error == 0` arm AND its other arm, the header sum, the slice, and both refusals.
#
# What the gate could not say before this session was ANYTHING about a real reply,
# and the three numbers that turned out to matter were all un-gated:
#
#   * `reply[8:16]` is `(104, 0)` HERE, so `:50`'s slice starts at byte 104 of a
#     4580-byte reply and the MTLB is 4476 bytes. `mt_liboff42` and `mt_liboff00`
#     were the only fixtures and both are synthetic.
#   * THE TWO BLOBS ARE DIFFERENT. The UNSLICED reply starts with a little-endian
#     3 and only the SLICED `ret` carries `MTLB`. Reading the magic off the wrong
#     one is off by 1112298570 and still LOOKS like a magic -- which is
#     `nv_query_litter` exactly: a port and an oracle agreeing on a number neither
#     of them read off the thing. `REPLY_LEAD` and `mt_reply_is_mtlb` exist so
#     that cannot happen quietly again.
#   * `error` is 0 for a kernel that compiled and 2 for one that did not, so
#     `:47`'s `if error == 0` is a comparison against two values this host produced.
#
# **THE SEAM THAT REMAINS IS ONE POINTER.** `ctypes.byref(callback, -0x10)` is the
# address of the `invoke` field of an Apple BLOCK, and Bend can neither allocate a
# block descriptor nor name its sixteenth byte. Hand the seam an already-compiled
# MTLB and the submission path is complete; hand it a block and `compile` runs.
#
# ---------------------------------------------------------------------------
# THERE IS NO dtype-to-MTLPixelFormat TABLE IN ops_metal.py, and the brief asked
# for one. `grep -n PixelFormat tinygrad/runtime/ops_metal.py` is empty and
# `MTLPixelFormat` reaches this file only through `autogen/metal.py`, where it
# describes TEXTURES. A Metal buffer here is `newBufferWithLength_options(size,
# MTLResourceStorageModeShared)` -- a byte range, and a dtype changes how MANY
# bytes it covers (device.bend's `nbytes = size * itemsize`) and never how
# anything is named. So the two-directional table this file actually HAS is
# `enum_MTLGPUFamily` -- nineteen members, a name to an id and an id to an arch
# string -- and `check_family`'s REVERSED `next(filter(...))` and the `[12:]`
# slice are the two directions, gated by `mt_fam_*` and `mt_arch_*` with a
# last-wins mutation (M30) because `reversed()` is what makes it last-wins.
#
# ---------------------------------------------------------------------------
# THE SPLIT, stated once and then obeyed. A def here EITHER builds the argument
# of one objc call (pure, and the gate checks it) OR records that call in the
# trace (and the gate checks the ORDER). There is no third kind.
#
# ===========================================================================
# WHAT IS PORTED, DEF BY DEF.
#
#   :15  REQUEST_TYPE_COMPILE       PORTED  a constant
#   :18  DLL("CoreGraphics")        WALL 1  A DYNAMIC LIBRARY LOAD
#   :22  to_ns_str                  WALL 2  AN NSString, plus `@functools.cache`
#   :24  checked                    PORTED  the WRAPPER, i.e. the refusal
#   :29  class MetalCompiler        PORTED  the four tables and three refs
#   :35   support = DLL(MTLCompiler) WALL 1
#   :38   __init__                  PORTED  `dev.cgs`, the cachekey name
#   :41   __reduce__                WALL 3  PICKLE (a multiprocessing detail)
#   :42   compile                   PARTIAL  the layout and the refusals
#   :55   macos_major/metal_version PORTED  the four-way `-std=` ladder
#   :60   params                    PORTED  the f-string
#   :62   src_padded/params_padded  PORTED  the 4-byte pad and the NUL
#   :63   request                   PORTED  the 16-byte `<QQ` header
#   :69   raise ret                 PORTED  refusal 1
#   :70   assert MTLB/ENDT          PORTED  refusal 2 (and the magic numbers)
#   :72   disassemble               WALL 4  A SUBPROCESS
#   :85  HANDLES                    PORTED  the five handles
#   :86  SELECTORS                  PORTED  the thirteen selectors
#   :89  MSGSEND                    PORTED  two bindings, by return type
#   :91  mtl_sel                    PORTED  the index table (51 entries)
#   :93  mtl_cb / :94 mtl_enc       PORTED  two placeholders, both index 0
#   :96  mtl_msg                    PORTED  the call, its selector and its args
#   :101 mtl_poll                   PORTED  one msgSend
#   :105 MetalQueue.__init__        PORTED  the five accumulators
#   :109 exec                       PORTED  the whole argument layout
#   :111 args                       PORTED  `getaddr` is 8 bytes, a var is its own
#   :112 rows / :113 nbytes         PORTED  `layout_args` and the `max`
#   :116-121 dims / sizes / cmds    PORTED  the symbolic-size arm and the tuple
#   :123 wait                       PORTED  a no-op, ON PURPOSE
#   :124 timestamp / :125 signal    PORTED  two appends
#   :127 submit                     PORTED  the ICB size and the header
#   :129 the placeholder size       PORTED  and it EQUALS :253's buffer size
#   :131 patch                      PORTED  three zero rows at `zero`
#   :135 the sizes loop             PORTED  one msgSend per symbolic command
#   :138 run                        PORTED  thirteen calls, four arms
#   :166-168 the submit tail        PORTED  three paths
#   :174 _alloc                     PORTED  the storage mode and refusal 3
#   :179 BufferStorage              PORTED  gpuAddress then contents
#   :180 _free                      PORTED  synchronize, mark_resident, release
#   :185 _offset                    PORTED  `D.host_offset`, device.bend's own
#   :189 pm_encode / :192 pm_lower  WALL 5  THE UOp MATCHER
#   :196 __init__                   PORTED  the twelve statements, in order
#   :201 the queue refusal          PORTED  refusal 4
#   :204-206 the residency set      PORTED  three calls, conditional
#   :213 check_family               PORTED  the reverse lookup
#   :214 arch                       PORTED  `[12:]` of the family name
#   :216 pm_bufferize               PARTIAL the three rules, FIRST-WINS
#   :222 sels                       PORTED  18 u64 = 144 bytes, and the [3:5]
#   :228 mark_resident              PORTED  both paths, and they are exclusive
#   :239 new_slots                  PORTED
#   :243 pipeline                   PORTED  four calls and `checked` twice
#   :251 new_icb                    PORTED  the size and the eleven steps
#   :258 the ICB refusal           PORTED  refusal 5
#   :262 the local-size refusal     PORTED  refusal 6, PER COMMAND
#   :270 _wait_signal               PORTED  and refusal 7
#   :275 synchronize                PARTIAL the index arithmetic, not the times
#   :284-285 the autorelease pool   PORTED  pop-then-push, in that order
#   :267 the ICB weak-dict         PORTED  `icb_keep`, and it WAS NOT CALLED
#   :276-281 the profile scan      PORTED  `dev.sync_scan`, and it WAS NOT CALLED
#   :23   to_ns_str                PORTED  `cns_string`, and it WAS NOT WIRED
#   :42-71 compile                 CLOSED  all of it but the block pointer
#   --    THE CONSTANTS            PORTED  65 with a CPython authority, all gated
#
# ---------------------------------------------------------------------------
# THREE DEFS WERE WRITTEN AND NOTHING REACHED THEM, and that is the finding this
# session started from. `icb_keep` (:267), `dev.sync_scan`'s list (`sync_starts`,
# :276-281) and `cns_string` (:23) each carried a comment saying a row checked it,
# and each was DEAD: correct, unread, and unreachable from `main`. A file whose
# gate prints 332 rows had a `Dev.nics` that was always 0, a profile scan that was
# a no-op, and a `newFunctionWithName:` with no name in it.
#
# `.agents/slop/dead-defs.py` is the tool -- name-based, and it blanks a def's own
# NAME in place rather than dropping the whole line, because most defs here are ONE
# LINE and dropping the line hides every constant they read. It found 17 dead defs
# on top of `main`. Fifteen are now live (four rows) and TWO are gone: the `Fq`
# record and its `fq()` constructor, a vestige of a shape the family fold no longer
# has -- `check_family` takes `f` as a PARAMETER, so a record bought nothing a
# string does not already do.
#
# ===========================================================================
# THE FIVE WALLS.
#
# 1. A DYNAMIC LIBRARY LOAD (:18, :35). `DLL("CoreGraphics", "CoreGraphics")`
#    is a module-level `ctypes.CDLL` whose only job is to make
#    `MTLCreateSystemDefaultDevice` resolvable
#    (https://developer.apple.com/documentation/metal/1433401-mtlcreatesystemdefaultdevice).
#    There is nothing to decide about it and nothing to gate.
#    TODO(p3) runtime/ops_metal.py:18  -- `DLL("CoreGraphics", "CoreGraphics")`.
#    TODO(p3) runtime/ops_metal.py:35  -- `DLL("MTLCompiler", "MTLCompiler")`.
#
# 2. AN NSString (:23, :247). `to_ns_str` is
#    `objc.msg("stringWithUTF8String:")(NSString, s.encode()).own()`. A `String`
#    is a `String` here and the SELECTOR is in the table, which is the part that
#    decides anything; the OBJECT is the seam's. `cns_string` records the selector
#    and `dev.pipeline.fun` calls it, so the trace reads
#    `stringWithUTF8String:` -> `newFunctionWithName` -> `setComputeFunction:` --
#    the order Python's argument evaluation produces, and NOT the order a name that
#    "is a literal" would produce. That was a dead def until this session and
#    `mt_pipe_order` is the row that had been lying.
#    TODO(p3) runtime/ops_metal.py:23  -- `stringWithUTF8String:` -> NSString.
#
# 3. PICKLE (:41). `__reduce__` exists only so a forked multiprocessing worker
#    builds a fresh `MTLCodeGenService`; it is `(MetalCompiler, ())` and it has
#    no reader in this tree.
#    TODO(p3) runtime/ops_metal.py:41  -- `__reduce__`.
#
# 4. A SUBPROCESS (:72-80). `disassemble` shells out to
#    `extra/disassemblers/applegpu/compiler_explorer.py` and prints stdout. It
#    is a developer tool with no caller in the port.
#    TODO(p3) runtime/ops_metal.py:76  -- `subprocess.Popen` of compiler_explorer.
#
# 5. THE UOp MATCHER (:189, :192, :216). `pm_encode` and `pm_lower` match on
#    UOps and `pm_bufferize` PREPENDS three rules to `Compiled`'s, so the port
#    carries the three rules' PATTERNS and their first-wins fold and nothing
#    else: a rule's body is a UOp graph, and building one needs
#    `./uop/ops.bend` and the HCQ2 lowering this file does not own.
#    TODO(p3) runtime/ops_metal.py:190  -- `encode_submit(MetalQueue(submit))`.
#    TODO(p3) runtime/ops_metal.py:193  -- `mtl_poll(tl) if …timeline…`.
#    TODO(p3) runtime/ops_metal.py:217  -- the three `pm_bufferize` bodies.
#
# NOT A WALL, and named because it looks like one: every `mtl_msg` goes through
# `ccall(MSGSEND[ret], obj, sel, *args)`, and `ccall` builds a UOp
# `CUSTOM_FUNCTION` node. This file records the call in the trace instead, and
# the trace is the argument of the seam: what survives is the ORDER, the
# SELECTOR, and the ARITHMETIC, which is all the structure there is.
#
# ===========================================================================
# THE TWO NUMBERS THAT ARE NOT IN THE PORT AT ALL, and why.
#
#  * `int(cb.GPUStartTime() * 1e9)` at :281. `base.bend` has no F64, so the
#    nanosecond conversion cannot happen here. `dev.sync` computes the WORD
#    INDICES the scan visits and records `waitUntilCompleted`, and the times
#    themselves are the seam's.
#    TODO(p3) runtime/ops_metal.py:281  -- `GPUStartTime/GPUEndTime * 1e9`.
#  * `f"{self.device} signal wait timed out"` and
#    `f"Invalid Metal library. {ret!r}"` interpolate a value this port has no
#    spelling for (a `bytes` repr). The gate diffs the PREFIX of each, beside
#    CPython's own output, and says so in the row name.
#
# ===========================================================================
# WHAT device.bend OWES THIS FILE, and it OWES IT FOUR THINGS, all consumed:
#
#  1. `D.Bar` / `D.Bn` / `D.bnew` are the Buffer. `_alloc` (:179) and `new_icb`
#     (:253) both RETURN a Buffer, and `ops_metal.py:263` reads
#     `buf.get_storage().meta` -- so the arena travels with the answer, in
#     `Made`, by the same rule `D.bnew` follows. `nbytes` is `size * itemsize`
#     and a view's offset ACCUMULATES, so neither is a field here.
#  2. `D.iter_sig` IS `layout_args`' engine. `hcq2.py:74-76` is
#     `[(offset + o, w) for (o,_),w in zip(TinyELF.iter_sig(item sizes), words)]`
#     and `device.py:364-368` is what `D.iter_sig` ports. `q.layout` is the one
#     `zip` and nothing else -- re-deriving the rounding would be a SECOND
#     transcription of device.py:364 and the two could disagree silently.
#  3. `D.round_up` is `helpers.py:69`, and `off = round_up(self.nbytes, 256)`
#     (:112) and `at = round_up(self.nbytes, 8)` (:118) are both it.
#  4. `D.recycled` is `Allocator.free`'s FOUR conjuncts, and `new_icb`'s
#     `BufferSpec(nolru=True)` (:253) is one of them: a Metal ICB is NEVER
#     recycled, which is a decision this file does not have to make and gets
#     from `D.Bspec` by naming it. `mt_nolru` is the row.
#
# ===========================================================================
# NO PROOFS FAIL HERE, and the brief expected some. The Metal FFI calls are
# `@extern` seams in `dtype.bend`'s sense -- a `def ... -> IO(R)` whose body is
# two `import "./x.c"` lines -- and every one of them is expected to make its
# importer print PROOFS FAIL (constraint line 1868: the foreign notice is a
# "who names whom" closure, and `@unsafe` does not shrink it). This file does
# NOT take that route, because the WebGPU template does not: a Metal call is
# recorded in a `Tr` trace, so there is no foreign effect to declare and
# `--check-only` says ALL PROOFS CHECK. The seam is `Tr.emit`, the ORDER is the
# artefact, and `wgsl.bend`'s green lane is the precedent, not `dtype.bend`'s
# fourteen.
import Base
import ../helpers.bend as H
import ../device.bend as D
import ../LAWS/spec.bend as S

# ===========================================================================
# THE CONSTANTS. Every one of these is READ OUT OF tinygrad or out of
# `autogen/metal.py`, and the gate's expectation is generated by calling
# CPython -- see `.agents/slop/mt_oracle.py`, which `ast`-walks this same file
# for the selector order and opens a real `MetalDevice` for the arch, AND
# `.agents/slop/mt_constmap.py`, which is the HAND MAP.
#
# ---------------------------------------------------------------------------
# WHY THE HAND MAP EXISTS, since `ops_nv.bend` shipped 606 green rows with 33 of
# 219 constants WRONG. The gate tests GRAPHS; a constant answers to a generated
# header, so no number of rows finds a wrong one. `const-audit.py` was written to
# automate the diff and reaches **0 of these 106** by name -- the port RENAMES
# (`CMDTYPE_CONCURRENT` vs `MTLIndirectCommandTypeConcurrentDispatch`), abbreviates
# (`SEL_WAITFENCE` for `waitForFence:`) and sometimes means something else by the
# same name (`ADDR_SIZE` is `Ops.GETADDR`'s dtype, not a header field). Its
# `0 likely-WRONG` is NOT a verdict and is never quoted as one.
#
# `mt_constmap.py` is a 106-entry map from each name to the authority that
# answers for it, and EVERY value on the right is produced by running Python:
# `getattr(autogen/metal.py, NAME)` for the enums, CPython's `ast` on a NAMED line
# of `ops_metal.py` for the literals, a real `MetalDevice` for the family and the
# `sels` Buffer, `struct.calcsize` and `int.from_bytes` for the two struct facts,
# and -- for `DIM_WORDS` and `ALL_SYMS` -- a REAL KERNEL LAUNCHED through the real
# `MetalQueue.exec` on this host. The result: **65 compared, 0 wrong.** Two of the
# oracle's own authorities were wrong while it was being written (`HDR_ICB` and
# `ICB_OPTIONS` both picked the wrong int off a line carrying two), which is the
# `nv_query_litter` trap caught by insisting the AST say which int it is.
#
# THE 38 `CALL_*` NUMBERS ARE NOT CONSTANTS and are not audited as if they were:
# they are a port-internal tag space, and what can be wrong is the NAME -> meaning
# map, so the audit checks that map -- every tag against the `ops_metal.py` line
# that carries the selector the port claims, and the tag set for density.
# ===========================================================================

# ops_metal.py:15. "there aren't any docs or symbols" -- the port says so too.
def REQUEST_TYPE_COMPILE() -> U32: 13

# ops_metal.py:200, `newCommandQueueWithMaxCommandBufferCount(1024)`.
def QUEUE_MAX_CMDS() -> U32: 1024

# :143, `useResources:count:usage:`'s last argument. MTLResourceUsageRead|Write.
def USAGE_READ_WRITE() -> U32: 3

# `autogen/metal.py:46`, `MTLResourceStorageModeShared := 0`. It is a bit in
# `MTLResourceOptions` and the SHARED bit is the empty one, which is why a Metal
# buffer is host-visible with no option at all.
def STORAGE_MODE_SHARED() -> U32: 0

# :255, `desc.setCommandTypes(metal.MTLIndirectCommandTypeConcurrentDispatch)`.
# MEASURED: `enum_MTLIndirectCommandType[32] == MTLIndirectCommandTypeConcurrentDispatch`.
def CMDTYPE_CONCURRENT() -> U32: 32

# :256, `desc.setMaxKernelBufferBindCount(1)`. THE load-bearing number for the
# composability claim in the header: one binding, at index 0.
def KERNEL_BUF_BINDS() -> U32: 1

# :257, the `options` argument of the ICB call, and the `reflection` argument
# of the pipeline call at :249. Both are 0 -- `None`.
def ICB_OPTIONS() -> U32: 0
def MTL_PIPELINE_OPTION_NONE() -> U32: 0

# :147 `UOp.range(len(pipes))` and :166-168's `run` arities.
def RUN_COUNT_ALL() -> U32: 0

# :276-278 -- the profile scan is `range(5, buf.size, 4)`. FIVE words of header
# and FOUR words (two timestamps) per entry, and the gate reads both.
def SYNC_START() -> U32: 5
def SYNC_STEP() -> U32: 4
def SYNC_END_OFFSET() -> U32: 2

# :128 `zero = round_up(self.nbytes, 8)` and the THREE u64 zero rows at :131
# (`range(3)`), which together are the `+ 24` in both buffer sizes.
def ZERO_ALIGN() -> U32: 8
def ZERO_ROWS() -> U32: 3
def ICB_HEADER_PAD() -> U32: 24

# :112, `off = round_up(self.nbytes, 256)`. The argument block's alignment.
def ARG_ALIGN() -> U32: 256

# :120, `self.nbytes = at + 48` -- six u64s of symbolic sizes and the 8-byte
# round-up of the next block.
def SYM_BYTES() -> U32: 48
def DIM_WORDS() -> U32: 6
def DIM_SIZES() -> List<&2, U32>: [8, 8, 8, 8, 8, 8]

# :132, `args.bitcast(dtypes.uint64)[zero // 8 + 3:]` -- the header is three
# u64 words past `zero`, and every `header.index(i)` below is relative to it.
def HDR_SKIP() -> U32: 3

# `TinyELF` word offsets in the ICB header, from :266's
# `[icb.value, *commands, *pipes]` and :148's `header.index(1 + n + r)`.
def HDR_ICB() -> U32: 0
def HDR_CMD() -> U32: 1
def HDR_PIPE() -> U32: 1

# `getaddr` is uint64 (MEASURED: `Ops.GETADDR unsigned long 8`), so every
# global contributes eight bytes whatever its dtype. :111.
def ADDR_SIZE() -> U32: 8

# ===========================================================================
# THE SELECTOR TABLE. `mtl_sel` (:91) is `(HANDLES + SELECTORS).index(name)`,
# and the trace needs the SAME index space for the objc messages ops_metal.py
# sends outside `mtl_msg` -- `newBufferWithLength_options` is just as much an
# objc message as `commandBuffer` is, and the trace must be able to say which.
# So the table is HANDLES ++ SELECTORS ++ the direct selectors, and one
# `sel_ix` scans all fifty-one. `mt_sel_*` rows are diffed against
# `(HANDLES + SELECTORS).index(name)` called in CPython.
#
# `D.AEnt` is `{ix: U32, nm: String}` and is reused rather than retyped: a
# table row with its own index is the shape that survives Bend's matcher (see
# device.bend's header, constraint B).
# ===========================================================================
def sel_table() -> List<&2, D.AEnt>:
  # HANDLES, :85. Five, and index 3 and 4 are the two the sels table REWRITES
  # at :237 -- `self.sels.host.view(fmt='Q')[3:5] = [addressof(self.table),
  # len(self.resources)]`.
  [D.AEnt{0, "queue"}, D.AEnt{1, "event"}, D.AEnt{2, "fence"},
   D.AEnt{3, "resources"}, D.AEnt{4, "count"},
   # SELECTORS, :86. Thirteen, in the source's order and not sorted.
   D.AEnt{5, "commandBuffer"}, D.AEnt{6, "computeCommandEncoder"},
   D.AEnt{7, "waitForFence:"}, D.AEnt{8, "updateFence:"},
   D.AEnt{9, "encodeSignalEvent:value:"}, D.AEnt{10, "endEncoding"},
   D.AEnt{11, "commit"}, D.AEnt{12, "useResources:count:usage:"},
   D.AEnt{13, "executeCommandsInBuffer:withRange:"},
   D.AEnt{14, "concurrentDispatchThreadgroups:threadsPerThreadgroup:"},
   D.AEnt{15, "setComputePipelineState:"},
   D.AEnt{16, "dispatchThreadgroups:threadsPerThreadgroup:"},
   D.AEnt{17, "signaledValue"},
   # THE DIRECT ONES. `new` and `stringWithUTF8String:` are the two class
   # allocations, `retain` is `.own()` at :259, and `commit` appears AGAIN as
   # the residency set's, which is why `k` and not `sel` is the entry point.
   D.AEnt{18, "newCommandQueueWithMaxCommandBufferCount"},
   D.AEnt{19, "newResidencySetWithDescriptor_error"},
   D.AEnt{20, "addResidencySet"},
   D.AEnt{21, "newSharedEvent"},
   D.AEnt{22, "newFence"},
   D.AEnt{23, "supportsFamily"},
   D.AEnt{24, "newBufferWithLength_options"},
   D.AEnt{25, "gpuAddress"},
   D.AEnt{26, "contents"},
   D.AEnt{27, "retain"},
   D.AEnt{28, "release"},
   D.AEnt{29, "addAllocation:"},
   D.AEnt{30, "removeAllocation:"},
   D.AEnt{31, "newLibraryWithData_error"},
   D.AEnt{32, "newFunctionWithName"},
   D.AEnt{33, "setComputeFunction"},
   D.AEnt{34, "setSupportIndirectCommandBuffers"},
   D.AEnt{35, "newComputePipelineStateWithDescriptor_options_reflection_error"},
   D.AEnt{36, "maxTotalThreadsPerThreadgroup"},
   D.AEnt{37, "setCommandTypes"},
   D.AEnt{38, "setMaxKernelBufferBindCount"},
   D.AEnt{39, "newIndirectCommandBufferWithDescriptor_maxCommandCount_options"},
   D.AEnt{40, "indirectComputeCommandAtIndex"},
   D.AEnt{41, "setComputePipelineState"},
   D.AEnt{42, "setKernelBuffer_offset_atIndex"},
   D.AEnt{43, "concurrentDispatchThreadgroups_threadsPerThreadgroup"},
   D.AEnt{44, "setBarrier"},
   D.AEnt{45, "waitUntilCompleted"},
   D.AEnt{46, "waitUntilSignaledValue:timeoutMS:"},
   D.AEnt{47, "GPUStartTime"},
   D.AEnt{48, "GPUEndTime"},
   D.AEnt{49, "new"},
   D.AEnt{50, "stringWithUTF8String:"},
   D.AEnt{51, "localizedDescription"}]

# ops_metal.py:85, `HANDLES`. The five, as their own def because `sels` (:224)
# writes them in this order and `mark_resident` (:237) rewrites slots 3 and 4.
def handles() -> List<&2, String>:
  ["queue", "event", "fence", "resources", "count"]

# ops_metal.py:86, `SELECTORS`. Thirteen. `:89 MSGSEND` binds `objc_msgSend` by
# RETURN TYPE and there are exactly two bindings, so the port's `MSGSEND` has
# two entries and a msgSend with no `ret=` answers through the first.
def selectors() -> List<&2, String>:
  ["commandBuffer", "computeCommandEncoder", "waitForFence:", "updateFence:",
   "encodeSignalEvent:value:", "endEncoding", "commit", "useResources:count:usage:",
   "executeCommandsInBuffer:withRange:",
   "concurrentDispatchThreadgroups:threadsPerThreadgroup:",
   "setComputePipelineState:", "dispatchThreadgroups:threadsPerThreadgroup:",
   "signaledValue"]

# `MATCHES` with a ONE-element pattern and the SELECTORS list, so the
# direct-selector suffix starts at 18 and every HANDLES/SELECTORS index is
# unchanged. The `mt_sel_*` rows are what proves that.
def sel_ix.put(hit: Bool, at: U32, ix: U32, got: U32) -> U32:
  Bool.pick(U32, hit, at, got)

def sel_ix.go(n: Nat, +s: String, es: List<&2, D.AEnt>, +at: U32, got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match es:
        case Nil{}: got
        case D.AEnt{ix, nm} <> t:
          sel_ix.go(m, s, t, U32.add(at, 1), sel_ix.put(String.eq(nm, s), at, ix, got))

# :91 `mtl_sel(dev, name)` -- a 0-based `.index` over one table, and 0 is
# Python's `ValueError` answer rewritten as "no such selector", because a
# message with an unknown selector cannot be built.
def sel_ix(+s: String) -> U32:
  sel_ix.go(List.length(&2, D.AEnt, sel_table()), s, sel_table(), 0, 0)

# the handle and selector constants, named because `run` and `sels` both use
# them by index and a bare 7 in a trace row is not a reviewable thing.
def SEL_QUEUE() -> U32: 0
def SEL_EVENT() -> U32: 1
def SEL_FENCE() -> U32: 2
def SEL_RESOURCES() -> U32: 3
def SEL_COUNT() -> U32: 4
def SEL_COMMANDBUFFER() -> U32: 5
def SEL_COMPUTEENCODER() -> U32: 6
def SEL_WAITFENCE() -> U32: 7
def SEL_UPDATEFENCE() -> U32: 8
def SEL_SIGNALEVENT() -> U32: 9
def SEL_ENDENCODING() -> U32: 10
def SEL_COMMIT() -> U32: 11
def SEL_USERESOURCES() -> U32: 12
def SEL_EXECUTECMDS() -> U32: 13
def SEL_CONCDISPATCH() -> U32: 14
def SEL_SETPIPESTATE() -> U32: 15
def SEL_DISPATCH() -> U32: 16
def SEL_SIGNALEDVALUE() -> U32: 17

# :89 `MSGSEND = {ret: metal.dll.bind(ret)(metal.dll.objc_msgSend) for ret in
# (None, ctypes.c_void_p)}`. TWO bindings, keyed by return type, and the whole
# reason `mtl_msg` takes a `ret=` at all.
def MSGSEND_N() -> U32: 2
def RET_NONE() -> U32: 1
def RET_VOIDP() -> U32: 2

# :93 `mtl_cb` and :94 `mtl_enc` are `.index(0)` placeholders, so both are 0 and
# neither is a handle the trace can distinguish. That is Python's own loss of
# information and the port keeps it: the two placeholders differ by TAG.
def PLACEHOLDER_IX() -> U32: 0

# ===========================================================================
# THE CALL KINDS. `k` is the FFI ENTRY POINT, and for a `mtl_msg` the identity
# of the call is `sel` rather than `k` -- which is why `commit` can be both the
# command buffer's (SEL_COMMIT, CALL_MSGSEND) and the residency set's
# (SEL_COMMIT, CALL_RS_COMMIT), and `setComputePipelineState:` can be the
# encoder's (SEL_SETPIPESTATE) and `setComputePipelineState` the ICB command's.
# `arg` is the ONE argument the gate reads, and WHAT it is differs per kind:
#
#   CALL_NEWQUEUE    the max command buffer count        CALL_NEWBUFFER the size
#   CALL_NEWRESID    -                                  CALL_NEWEVENT  -
#   CALL_NEWFENCE    -                                  CALL_FAMILY    the family
#   CALL_GPUADDR     -                                  CALL_CONTENTS  -
#   CALL_RELEASE     -                                  CALL_RETAIN    -
#   CALL_RS_ADD      the buffer                         CALL_RS_DEL    the buffer
#   CALL_NEWLIB      -                                  CALL_NEWFUNC   -
#   CALL_SETCOMPFUNC -                                  CALL_SETICB    -
#   CALL_NEWPIPE     -                                  CALL_MAXTPG    -
#   CALL_SETCMDTYPE  CMDTYPE_CONCURRENT                 CALL_SETBINDS  1
#   CALL_NEWICB      the max command count              CALL_ICBCMD    the index
#   CALL_SETPIPELINE the command index                  CALL_SETKBUF   the offset
#   CALL_CONCDISP    the command index                  CALL_SETBAR    -
#   CALL_WAITSIG     the timeout ms                     CALL_WAITCOMP  -
#   CALL_MSGSEND     per selector, below
#   CALL_STORE       the word index being written
#
# THE `arg` OF A MSGSEND, and this is the table the order rows are checked
# against: commandBuffer 0, computeCommandEncoder 0, waitForFence: the fence
# handle, useResources:count:usage: the buffer COUNT, executeCommandsInBuffer-
# withRange: the range LENGTH, the dispatch pair the `zero` word index, the
# set/dispatch pair the word index, encodeSignalEvent:value: the signalled
# value, commit 0, setComputePipelineState: the word index of the pipeline.
# ===========================================================================
def CALL_CGS_CREATE() -> U32: 0
def CALL_CGS_BUILD() -> U32: 1
def CALL_SYSDEVICE() -> U32: 2
def CALL_NEWQUEUE() -> U32: 3
def CALL_NEWRESID() -> U32: 4
def CALL_ADDRESID() -> U32: 5
def CALL_NEWEVENT() -> U32: 6
def CALL_NEWFENCE() -> U32: 7
def CALL_FAMILY() -> U32: 8
def CALL_NEWBUFFER() -> U32: 9
def CALL_GPUADDR() -> U32: 10
def CALL_CONTENTS() -> U32: 11
def CALL_RELEASE() -> U32: 12
def CALL_RETAIN() -> U32: 13
def CALL_RS_ADD() -> U32: 14
def CALL_RS_DEL() -> U32: 15
def CALL_RS_COMMIT() -> U32: 16
def CALL_NEWLIB() -> U32: 17
def CALL_NEWFUNC() -> U32: 18
def CALL_SETCOMPFUNC() -> U32: 19
def CALL_SETICB() -> U32: 20
def CALL_NEWPIPE() -> U32: 21
def CALL_MAXTPG() -> U32: 22
def CALL_SETCMDTYPE() -> U32: 23
def CALL_SETBINDS() -> U32: 24
def CALL_NEWICB() -> U32: 25
def CALL_ICBCMD() -> U32: 26
def CALL_SETPIPELINE() -> U32: 27
def CALL_SETKBUF() -> U32: 28
def CALL_CONCDISP() -> U32: 29
def CALL_SETBAR() -> U32: 30
def CALL_WAITSIG() -> U32: 31
def CALL_WAITCOMP() -> U32: 32
def CALL_AUTORELPOP() -> U32: 33
def CALL_AUTORELPUSH() -> U32: 34
def CALL_MSGSEND() -> U32: 35
def CALL_STORE() -> U32: 36

# ===========================================================================
# THE TYPES.
# ===========================================================================

# ONE call and the one argument the gate reads. Three fields, and each is
# load-bearing: `k` for the direct calls (where the selector alone would not
# separate the residency set's `commit` from the command buffer's), `sel` for
# every message (where the selector IS the identity), `arg` for the six calls
# whose argument is a number tinygrad later compares.
type Call is Data:
  Call{k: U32, sel: U32, arg: U32}

# The three readers sit IMMEDIATELY above their first use, because `Tr.args.put`
# is three hundred lines below `type Call` and a def may only call a def declared
# above it. See device.bend's header for the same rule applied to `Telf`.
def Call.k(c: Call) -> U32:
  match c:
    case Call{k, sel, arg}: k

def Call.sel(c: Call) -> U32:
  match c:
    case Call{k, sel, arg}: sel

def Call.arg(c: Call) -> U32:
  match c:
    case Call{k, sel, arg}: arg

# The trace. `next` mints the handle ids, so 0 is reserved for `None` -- which
# is what lets `Dev.resid` be a plain `U32` and `residency.value is not None`
# be `resid != 0` without a `Maybe` field (a `Data` record may not hold one).
# `refused` is THE RAISE: once a refusal has happened `Tr.emit` records
# nothing, so a refusal shows up in the trace as a TRUNCATION and no step below
# needs a guard of its own.
type Tr is Data:
  Tr{calls: List<&2, Call>, next: U32, refused: Bool}

def Tr.of() -> Tr: Tr{Nil{}, 1, False{}}

def Tr.calls(+t: Tr) -> List<&2, Call>:
  match t:
    case Tr{calls, next, refused}: calls

def Tr.next(+t: Tr) -> U32:
  match t:
    case Tr{calls, next, refused}: next

def Tr.refused(t: Tr) -> Bool:
  match t:
    case Tr{calls, next, refused}: refused

# the id the NEXT emit mints, i.e. what the seam's call returns. Read BEFORE the
# emit, so ids are monotone in issue order.
def Tr.here(t: Tr) -> U32:
  match t:
    case Tr{calls, next, refused}: next

# `Tr.emit.go` is the seam: every objc message and every UOp store in this file
# goes through it, so the trace is the ordered list of calls the C side makes.
# `Bool.pick` evaluates BOTH arms, so the emitted call is a value built here
# and the guard is a parameter -- this is the port's `raise`.
def Tr.emit.go(+refused: Bool, k: U32, sel: U32, arg: U32,
               +calls: List<&2, Call>, +next: U32) -> Tr:
  Tr{Bool.pick(List<&2, Call>, refused, calls,
               List.append(&2, Call, calls, [Call{k, sel, arg}])),
     Bool.pick(U32, refused, next, U32.add(next, 1)), refused}

def Tr.emit(k: U32, sel: U32, arg: U32, t: Tr) -> Tr:
  match t:
    case Tr{calls, next, refused}: Tr.emit.go(refused, k, sel, arg, calls, next)

# THE RAISE, and the refusal sites are the port's OWN predicates rather than an
# opaque error pop: `queue.value is None` (:201), `mtl.value is None` (:177),
# `icb.value is None` (:258), `prod(dims[3:]) > mx` (:262), `not wait(...)`
# (:273), `isinstance(ret, Exception)` (:69) and the MTLB/ENDT assert (:70).
# `refused.at` is that raise, and each site spells its own condition so the
# gate can drive it: `mt_refuse_*` is one row family per site.
def Tr.refuse.at(refused: Bool, ok: Bool) -> Bool:
  Bool.or(refused, Bool.not(ok))

def Tr.refuse(t: Tr, ok: Bool) -> Tr:
  match t:
    case Tr{calls, next, refused}: Tr{calls, next, Tr.refuse.at(refused, ok)}

# ===========================================================================
# READING THE TRACE. Same three helpers the WebGPU template has, and the same
# one fix it needed: `Tr.has.go`'s FUEL IS THE TRACE LENGTH and the answer is
# `at == patlen`. With the fuel set to the PATTERN length it returns True after
# `patlen` entries without ever comparing `at`, and a REVERSED pattern matches
# -- which is why `mt_has_rejects` is the first row in the gate and why every
# order row below it is worth printing.
# ===========================================================================
def Tr.count.go(n: Nat, +k: U32, cs: List<&2, Call>, got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match cs:
        case Nil{}: got
        case Call{kk, ss, aa} <> t:
          Tr.count.go(m, k, t, U32.add(got, Bool.to_u32(U32.is_eq(kk, k))))

def Tr.count(k: U32, +cs: List<&2, Call>) -> U32:
  Tr.count.go(List.length(&2, Call, cs), k, cs, 0)

# a LEAF, because `Bool.pick` evaluates both arms and a recursive call inside
# one of them would branch the walk twice over.
def Tr.args.put(+c: Call, +k: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, U32.is_eq(Call.k(c), k),
            List.append(&2, U32, acc, [Call.arg(c)]), acc)

def Tr.args.go(n: Nat, +k: U32, cs: List<&2, Call>, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match cs:
        case Nil{}: acc
        case Call{kk, ss, aa} <> t: Tr.args.go(m, k, t, Tr.args.put(Call{kk, ss, aa}, k, acc))

def Tr.args(k: U32, +cs: List<&2, Call>) -> List<&2, U32>:
  Tr.args.go(List.length(&2, Call, cs), k, cs, Nil{})

def Tr.sels.go(n: Nat, +k: U32, cs: List<&2, Call>, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m:
      match cs:
        case Nil{}: acc
        case Call{kk, ss, aa} <> t:
          Tr.sels.go(m, k, t,
                     Bool.pick(List<&2, U32>, U32.is_eq(kk, k),
                               List.append(&2, U32, acc, [ss]), acc))

def Tr.count_s.go(n: Nat, +s: U32, cs: List<&2, Call>, got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match cs:
        case Nil{}: got
        case Call{kk, ss, aa} <> t:
          Tr.count_s.go(m, s, t, U32.add(got, Bool.to_u32(U32.is_eq(ss, s))))

# how many calls carried SELECTOR `s` -- the per-step count that `Tr.count` (per
# KIND) cannot give, because eleven of `run`'s thirteen calls share one kind.
def Tr.count_s(s: U32, +cs: List<&2, Call>) -> U32:
  Tr.count_s.go(List.length(&2, Call, cs), s, cs, 0)

def Tr.sels(k: U32, +cs: List<&2, Call>) -> List<&2, U32>:
  Tr.sels.go(List.length(&2, Call, cs), k, cs, Nil{})

# BOTH `k` and `sel` are compared, and `arg` as well, so a pattern pins the
# IDENTITY of each call and not only its kind. `mt_init_order` and `mt_run_order`
# say the queue is created BEFORE the residency set is asked for, and WHICH
# selector each step uses.
def Tr.has.step.same3(k1: U32, s1: U32, a1: U32, k2: U32, s2: U32, a2: U32) -> Bool:
  Bool.and(U32.is_eq(k1, k2),
    Bool.and(U32.is_eq(s1, s2), U32.is_eq(a1, a2)))

def Tr.has.step.hit(same: Bool, at: Nat) -> Nat:
  match same:
    case True{}: Nat.add(at, 1n)
    case False{}: at

def Tr.has.step(m: Maybe<&2, Call>, +c: Call, at: Nat) -> Nat:
  match m:
    case None{}: at
    case Some{+want}:
      Tr.has.step.hit(Tr.has.step.same3(Call.k(c), Call.sel(c), Call.arg(c),
                                       Call.k(want), Call.sel(want), Call.arg(want)), at)

def Tr.has.go(n: Nat, +patlen: Nat, cs: List<&2, Call>, +pat: List<&2, Call>,
              +at: Nat) -> Bool:
  match n:
    case 0n: Nat.is_eq(at, patlen)
    case 1n+m:
      match cs:
        case Nil{}: Nat.is_eq(at, patlen)
        case Call{kk, ss, aa} <> t:
          Tr.has.go(m, patlen, t, pat,
                    Tr.has.step(List.get(&2, Call, pat, at), Call{kk, ss, aa}, at))

def Tr.has(+cs: List<&2, Call>, +pat: List<&2, Call>) -> Bool:
  Tr.has.go(List.length(&2, Call, cs), List.length(&2, Call, pat), cs, pat, 0n)

def u32_list_eq(+a: List<&2, U32>, +b: List<&2, U32>) -> Bool:
  Bool.and(U32.is_eq(U32.from_nat(List.length(&2, U32, a)),
                     U32.from_nat(List.length(&2, U32, b))), H.u32_list_eq(a, b))

def str_eq.go(a: List<&2, String>, b: List<&2, String>, bad: Bool) -> Bool:
  match a:
    case Nil{}: Bool.not(bad)
    case x <> t:
      match b:
        case Nil{}: False{}
        case y <> u: str_eq.go(t, u, Bool.or(bad, Bool.not(String.eq(x, y))))

def str_list_eq(+a: List<&2, String>, +b: List<&2, String>) -> Bool:
  Bool.and(U32.is_eq(U32.from_nat(List.length(&2, String, a)),
                     U32.from_nat(List.length(&2, String, b))), str_eq.go(a, b, False{}))

# ===========================================================================
# THE REFUSAL MESSAGES. Every one of these is USER-VISIBLE -- they land in a
# Python traceback -- so each is a String built by `String.concat` and diffed
# against CPython's own `f`/`RuntimeError` output. `String.concat` DROPS A
# LITERAL SILENTLY, which is why the gate prints the string beside the boolean
# and never gates on a boolean about a string.
# ===========================================================================

# :201, `raise RuntimeError("Cannot allocate a new command queue")`. The whole
# message is a literal, so it must be a String and not a row about a Bool.
def msg_noqueue() -> String: "Cannot allocate a new command queue"

# :177, `raise MemoryError(f"Metal OOM while allocating {size=}")`. The `=`
# f-spec prints the name AND the value, so the text is "size=NNNN" and the
# digits are `U32.show`. `mt_oom_5` is diffed against CPython's own output.
def msg_oom(size: U32) -> String:
  String.concat(["Metal OOM while allocating size=", U32.show(size)])

# :258, `raise RuntimeError("create indirect command buffer failed, does your
# system support this?")`. A LITERAL, including the question mark, and the
# message that names the one thing a user can act on.
def msg_noicb() -> String:
  "create indirect command buffer failed, does your system support this?"

# :262, `raise RuntimeError(f"local size {dims[3:]} bigger than {mx}")`. A
# Python tuple repr: `(4, 1, 1) bigger than 1024`. The tuple's spelling is the
# port's, and `mt_local_4` says so.
def msg_local(lx: U32, ly: U32, lz: U32, mx: U32) -> String:
  String.concat(["local size (", U32.show(lx), ", ", U32.show(ly), ", ",
                 U32.show(lz), ") bigger than ", U32.show(mx)])

# :273, `raise RuntimeError(f"{self.device} signal wait timed out")`. The
# device name is the argument, so on `Device["METAL"]` with no index the PREFIX
# is EMPTY and the message is exactly the tail -- which is the case the gate
# diffs, because `d.device == ''` is MEASURED on this host.
def msg_timeout() -> String: " signal wait timed out"

# :70, `assert ret[:4] == b"MTLB" and ret[-4:] == b"ENDT", f"Invalid Metal
# library. {ret!r}"`. The `repr` is a `bytes` and has no spelling here, so the
# port builds the PREFIX and the seam appends the repr.
def msg_badlib() -> String: "Invalid Metal library. "

# :26, `raise RuntimeError(bytes(objc.msg("UTF8String")(err.localizedDescription
# )).decode())`. The whole message is the seam's -- it is whatever the
# Objective-C exception says -- so the port keeps the CALL and not the text.
# TODO(p3) runtime/ops_metal.py:26  -- `localizedDescription` -> RuntimeError.

# :69 `raise ret` and :52 `ret = CompileError(errorMessage.decode())` are both
# the seam's own text.
# TODO(p3) runtime/ops_metal.py:52  -- the callback's `errorMessage`.

# ===========================================================================
# ops_metal.py:29-71 -- MetalCompiler. The part of the Metal chain that produces
# an MTLB, and the part that is NOT a ctypes call: the three tables below are
# the whole of the request, and a C seam only has to hand over the bytes.
# ===========================================================================

# ops_metal.py:56,
#   `metal_version = "metal4.0" if macos_major >= 26 else "metal3.1" if
#                      macos_major >= 14 else "metal3.0" if macos_major >= 13
#                      else "macos-metal2.0"`
# FOUR arms and THREE `>=` tests, and writing it as two nested `Bool.pick`s
# rather than a `U32` ladder is not a style choice: a three-way choice over
# `U32` literals that are not 0/1/n is REFUSED with "a declared constructor
# (unknown: U32)" (constraint line 5182), and 26/14/13 are none of them.
# MEASURED on this host: macos_major 26 -> "metal4.0".
def metal_version.at(g26: Bool, g14: Bool, g13: Bool) -> String:
  Bool.pick(String, g26, "metal4.0",
            Bool.pick(String, g14, "metal3.1",
                      Bool.pick(String, g13, "metal3.0", "macos-metal2.0")))

def metal_version(+major: U32) -> String:
  metal_version.at(U32.is_ge(major, 26), U32.is_ge(major, 14), U32.is_ge(major, 13))

# :60 `params = f'-fno-fast-math -std={metal_version} --driver-mode=metal -x
# metal -fmodules-cache-path="{cache_dir}" -fno-caret-diagnostics'`. The whole
# string, because the gate diffs it against CPython's own f-string and a
# dropped literal inside `String.concat` is SILENT.
#
# `cache_dir` is `helpers.py`'s, which is a `Path` under the tinygrad cache
# directory and is therefore the seam's value -- but it is a PARAMETER and not a
# constant, so `mt_params_cache` can diff two different cache dirs and prove
# the interpolation site is where the source puts it.
def mtl_params(cache: String, mv: String) -> String:
  String.concat(["-fno-fast-math -std=", mv,
                 " --driver-mode=metal -x metal -fmodules-cache-path=\"", cache,
                 "\" -fno-caret-diagnostics"])

# :62, "source blob has to be padded to multiple of 4 but at least one
# 'b\x00' should be added, params blob just has to be null terminated":
#   `src_padded    = src + b'\x00'*(round_up(len(src) + 1, 4) - len(src))`
#   `params_padded = params + b'\x00'`
# The pad is `round_up(len+1, 4) - len`, NOT `round_up(len, 4) - len`: for
# `len == 4` the first is 4 and the second is 0, so the source blob always gets
# at least the one NUL the comment demands. `mt_pad4` is that row.
#
# MEASURED, and the first version of this def dropped the `- n`:
#   `mt_pad1` printed 4 where CPython says 3, `mt_pad7` printed 8 where CPython
# says 1, and `mt_psrc7` and `mt_req7` moved with them. Six rows and the
# diagnosis was one missing subtraction -- which is the argument for generating
# the expectation from the formula rather than from the port.
def csrc_pad(+n: U32) -> U32: U32.sub(D.round_up(U32.add(n, 1), 4), n)

def csrc_padded(+n: U32) -> U32: U32.add(n, csrc_pad(n))

def cparams_padded(n: U32) -> U32: U32.add(n, 1)

# :63, `struct.pack('<QQ', len(src_padded), len(params_padded))` -- a SIXTEEN
# byte little-endian header of two u64 lengths, and then the two blobs. The
# `<QQ` is 16 bytes and the port says so once, because `struct.calcsize` is
# not available and 8+8 is the only place the number lives.
def cstruct_qq() -> U32: 16

def creq_len(nsrc: U32, nparams: U32) -> U32:
  U32.add(cstruct_qq(), U32.add(csrc_padded(nsrc), cparams_padded(nparams)))

# :70, `assert ret[:4] == b"MTLB" and ret[-4:] == b"ENDT"`. Two FOUR-BYTE
# magics, read as little-endian u32s so the port can COMPARE them (the bytes
# themselves are the seam's). The values are `int.from_bytes(b"MTLB", "little")`
# and the same for `b"ENDT"`, and the gate prints them so a wrong endianness
# would be a wrong row rather than a silently-passing one.
def MTLB_MAGIC() -> U32: 1112298573
def ENDT_MAGIC() -> U32: 1413762629

# :50, THE NUMBER NOBODY MEASURED, now measured. `reply[8:16]` is two u32s -- a
# HEADER size and a WARNING size -- and `ret = reply[sum(...):]`. MEASURED by
# running `MTLCodeGenServiceBuildRequest` on this host and reading the blob the
# callback was handed: `(104, 0)`, so the MTLB starts at byte 104 of a 4580-byte
# reply and is 4476 bytes. `mt_liboff_host` is the row and `mt_liboff42` /
# `mt_liboff00` are the synthetic ones it is now checked against.
def REPLY_HDR() -> U32: 104
def REPLY_WARN() -> U32: 0

# THE ROW THAT KILLS THE `nv_query_litter` TRAP FOR THIS FILE. The UNSLICED reply
# does NOT start with `MTLB` -- it starts with `b'\x03\x00\x00\x00'`, a little-endian
# 3, and it is the SLICED `ret` that carries the magic. So a gate row that reads
# `MTLB_MAGIC` off the wrong one of the two blobs is wrong by 1112298570 and still
# LOOKS like a magic. MEASURED, not reasoned: `mt_reply_lead` prints the reply's
# own first word next to `mt_mtlb`, so the two can never be confused again.
def REPLY_LEAD() -> U32: 3

# :47, `if error == 0`. `error` is a `ctypes.c_int32` out-parameter, and this host
# answers 0 for a kernel that compiled and 2 for one that did not. MEASURED both
# arms by compiling a good and a bad kernel through the real call: `mt_err_ok0` and
# `mt_err_bad2` are the pair, and `mt_err_bad2` is the row that says the port's
# `cerr: Bool` is a `!= 0` and not a `== 2`.
def CB_ERR_OK() -> U32: 0
def CB_ERR_COMPILE() -> U32: 2

def cc_error_ok(err: U32) -> Bool: U32.is_zero(err)

# :55, `macos_major = int(platform.mac_ver()[0].split('.')[0])`. The host's macOS
# MAJOR version, injected rather than read -- the port cannot ask the kernel what
# it is running on, and the AGENTS.md rule is the same one that governs `now`: the
# value a production function needs arrives as an argument. It is a CONSTANT here
# so the gate can diff it against `platform.mac_ver()`, and `mt_ver_host` is the
# `-std=` string the REAL host compiles with.
def MACOS_MAJOR() -> U32: 26

# :50, `ret = reply[sum(struct.unpack('<LL', reply[8:16])):]` -- the data starts
# at header size + warning size, both u32s read out of bytes 8..16. The SLICE
# is the seam's; the SUM is the port's, and `mt_liboff` is its row. A reply
# with a zero header and a zero warning puts the data at byte 0.
def mtl_lib.off(hdr: U32, warn: U32) -> U32: U32.add(hdr, warn)

# :40, `super().__init__("compile_metal_direct")` -- the cachekey, and a NAME
# that shows up in `CACHEDB` and in a `WONTFIX` traceback, so it is a String.
def CACHEKEY() -> String: "compile_metal_direct"

# :39 `MTLCodeGenServiceCreate(b"tinygrad")`. One C call and the service handle.
def cgs_create(t: Tr) -> Tr:
  Tr.emit(CALL_CGS_CREATE, PLACEHOLDER_IX(), 0, t)

# :68, `MTLCodeGenServiceBuildRequest(self.cgs, None, REQUEST_TYPE_COMPILE,
# request, len(request), ctypes.byref(callback, -0x10))` -- six arguments of
# which the THIRD is the request type and the FIFTH is the request length. The
# last argument is the Apple BLOCK ABI, which is the seam and is not an
# argument at all as far as this port is concerned.
# TODO(p3) runtime/ops_metal.py:68  -- the block ABI, `byref(callback, -0x10)`.
def cgs_build(ibytes: U32, t: Tr) -> Tr:
  Tr.emit(CALL_CGS_BUILD, PLACEHOLDER_IX(), ibytes, t)

# The two refusals of `compile`, in the order the source reaches them. :69
# `if isinstance(ret, Exception): raise ret` is the callback having been handed
# a non-zero `error`, and :70 is the magic check. `ccompile.ok` is the second
# and the gate drives each in turn.
def ccompile.err(cerr: Bool, magic: Bool, t: Tr) -> Tr: Tr.refuse(t, cerr)
def ccompile.ok(head: U32, tail: U32, t: Tr) -> Tr:
  Tr.refuse(t, Bool.and(U32.is_eq(head, MTLB_MAGIC()), U32.is_eq(tail, ENDT_MAGIC())))

# :45-52, THE CALLBACK, as two arms over the `error` word. The port's `ccompile`
# takes `cerr: Bool` because a trace records that a refusal happened and not its
# code; `ccompile.of` keeps the CODE, so `:47`'s `if error == 0` is a comparison
# against a MEASURED value and not a Bool somebody chose. `err == 0` slices the
# header off and keeps the MTLB; anything else refuses.
#
# TWO `.at`s and not a `Bool.pick` with both arms inline: Bend is STRICT, so both
# would be BUILT and one discarded -- harmless here (`Tr.emit` is pure) and a trap
# the moment an arm is not.
def ccompile.slice(lead: U32, tail: U32, t: Tr) -> Tr:
  ccompile.ok(lead, tail, t)

def ccompile.slice.at(ok: Bool, lead: U32, tail: U32, t: Tr) -> Tr:
  match ok:
    case True{}: ccompile.slice(lead, tail, t)
    case False{}: Tr.refuse(t, False{})

def ccompile.of(err: U32, head: U32, tail: U32, ibytes: U32, t: Tr) -> Tr:
  ccompile.slice.at(cc_error_ok(err), head, tail, cgs_build(ibytes, cgs_create(t)))

def ccompile(cerr: Bool, head: U32, tail: U32, ibytes: U32, t: Tr) -> Tr:
  ccompile.ok(head, tail, cgs_build(ibytes, cgs_create(t)))

# :23 `to_ns_str`, and the `NSString` it makes is the seam. What the trace
# holds is the selector and the fact that the call happened.
def cns_string(t: Tr) -> Tr:
  Tr.emit(CALL_MSGSEND, sel_ix("stringWithUTF8String:"), 0, t)

# :204 and :246 and :254, `objc.msg("new", clsmeth=True)(SomeDescriptor)` --
# the same class allocation three times, and the same selector each time.
def cnew(t: Tr) -> Tr: Tr.emit(CALL_MSGSEND, sel_ix("new"), 0, t)

# ===========================================================================
# ops_metal.py:103-168 -- MetalQueue. Five accumulators at :107, the argument
# layout at :111-113, the symbolic arm at :117-120, the ICB at :129-132, the
# sizes loop at :135-136, `run` at :138-163 and the submit tail at :166-168.
# ===========================================================================

# ONE word of the argument block: its byte offset and its itemsize. :131's
# `patch(buf, self.rows + ...)` is a list of `(offset, uop)` pairs and the
# OFFSET plus the ITEMSIZE is everything the layout decides -- the uop itself is
# the graph, which is WALL 5.
type Row is Data:
  Row{off: U32, k: U32}

# ONE command, :121 `self.cmds.append((obj.lib, obj.name, dims, off))`. `lib`
# is the MTLB's identity as a U32 because bytes are the seam's; `name` is the
# ENTRY POINT and stays a String because cstyle.bend's `kern2 METAL` row names
# the function and the two strings have to be the same one. `sym` is the index
# into `Q.sizes` PLUS ONE, 0 for a command whose six dims are all constants.
type Cmd is Data:
  Cmd{lib: U32, name: String, dims: List<&2, U32>, off: U32, sym: U32}

# ONE entry of `self.sizes`, :118 `(len(self.cmds), at)` -- the command it
# belongs to and the byte offset of that command's six u64 dims.
type Sz is Data:
  Sz{ci: U32, at: U32}

# The first-occurrence index of a dedup and whether one was found. TWO fields
# because 0 is a legal index and Python's `next(..., 0)` at :213 is
# indistinguishable from "the first family", which is a different question.
type Seen is Data:
  Seen{got: U32, hit: Bool}

def Seen.got(s: Seen) -> U32:
  match s:
    case Seen{got, hit}: got

def Seen.hit(s: Seen) -> Bool:
  match s:
    case Seen{got, hit}: hit

# `self.stamps` is a list of UOps and the ONLY thing :157 and :166 read about
# it is its truthiness, so the port carries a COUNT and not a list.
type Q is Data:
  Q{rows: List<&2, Row>, cmds: List<&2, Cmd>, sizes: List<&2, Sz>, stamps: U32,
     nbytes: U32, npipes: U32, t: Tr}

def Q.of() -> Q: Q{Nil{}, Nil{}, Nil{}, 0, 0, 0, Tr.of()}

def Q.rows(+q: Q) -> List<&2, Row>:
  match q:
    case Q{rows, cmds, sizes, stamps, nbytes, npipes, t}: rows

def Q.cmds(+q: Q) -> List<&2, Cmd>:
  match q:
    case Q{rows, cmds, sizes, stamps, nbytes, npipes, t}: cmds

def Q.sizes(+q: Q) -> List<&2, Sz>:
  match q:
    case Q{rows, cmds, sizes, stamps, nbytes, npipes, t}: sizes

def Q.stamps(q: Q) -> U32:
  match q:
    case Q{rows, cmds, sizes, stamps, nbytes, npipes, t}: stamps

def Q.nbytes(q: Q) -> U32:
  match q:
    case Q{rows, cmds, sizes, stamps, nbytes, npipes, t}: nbytes

def Q.npipes(q: Q) -> U32:
  match q:
    case Q{rows, cmds, sizes, stamps, nbytes, npipes, t}: npipes

def Q.t(q: Q) -> Tr:
  match q:
    case Q{rows, cmds, sizes, stamps, nbytes, npipes, t}: t

def Q.ncmds(q: Q) -> U32: U32.from_nat(List.length(&2, Cmd, Q.cmds(q)))

# :123 `wait(self, dst, val, eq=False): pass` -- "the fence orders the queue",
# so the NO-OP is the port: `q.wait` returns its trace untouched and
# `mt_wait_noop` is the row that says a trace with a wait in it is the same
# trace as one without.
def q.wait(t: Tr) -> Tr: t

# :124 `timestamp(self, dst): self.stamps.append(dst)` and :125
# `signal(self, dst, val): self.value = val`. The first is a count and the
# second is a value, and they are the two things `run` and `submit` branch on.
def q.timestamp(q: Q) -> Q:
  match q:
    case Q{rows, cmds, sizes, stamps, nbytes, npipes, t}:
      Q{rows, cmds, sizes, U32.add(stamps, 1), nbytes, npipes, t}

# :125 `signal(self, dst, val): self.value = val`. The value is read by :162's
# `encodeSignalEvent:value:`, which is inside `run`, so it travels as `Run.val`
# and NOT as a field of the queue -- Python puts it on the queue because Python
# has a `self`, and Bend has none. `q.signal` is the queue unchanged and
# `mt_signal_keeps_nbytes` is the row that says the queue did not grow.
def q.signal(q: Q, v: U32) -> Q: q

# ===========================================================================
# THE ARGUMENT LAYOUT, :110-121, which is the part of this file that is pure
# logic and therefore the part worth checking.
#
#   args  = [bufs[i].getaddr(devs) for i in prg.arg.globals]
#         + [v.ccast(var.dtype) for v, var in zip(vals, prg.arg.vars)]
#   off   = round_up(self.nbytes, 256)
#   rows += layout_args(args, off)
#   self.nbytes = max([o + w.dtype.itemsize for o, w in rows], default=off + 8)
#
# `layout_args` is `hcq2.py:74-76` and its engine is `TinyELF.iter_sig`, which
# `device.bend` ALREADY ports as `D.iter_sig`. So `q.layout` is the one `zip` and
# the rounding belongs to device.bend -- a second transcription of
# device.py:364 could disagree with the first silently, and there would be no
# row in either file to see it.
# ===========================================================================
def q.items.bufs(n: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m: q.items.bufs(m, List.append(&2, U32, acc, [ADDR_SIZE()]))

# :111 -- every global is a `getaddr`, which is uint64 (MEASURED in CPython:
# `UOp.new_buffer("METAL",64,float32,16).getaddr(None).dtype` is
# `unsigned long`, itemsize 8), and every var is `ccast` to ITS OWN dtype. So
# the two halves contribute DIFFERENT widths and the globals come FIRST.
# `List.append(a, A, xs, ys)` is `xs ++ ys`, so the EIGHT-byte words are built
# first and the vars are appended AFTER them: :111 is `[globals] + [vals]`, and
# getting it the other way round moves every offset in the file. `mt_items_2_1`
# is the row and it is the FIRST gate row to catch a reversed concat.
def q.items(nbufs: Nat, +vars: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, q.items.bufs(nbufs, Nil{}), vars)

# The two nested matches are `iter_sig`'s output against the itemsizes -- the
# `zip` of `hcq2.py:76` -- and they are nested rather than a helper because a
# `.go`/`.put` PAIR OF ONE SELF-RECURSIVE FOLD IS MUTUAL RECURSION and is
# refused (constraint line 2917). `at` is `+` because the slot and the self-call
# both read it.
def q.layout.go(n: Nat, +at: U32, ss: List<&2, U32>, items: List<&2, U32>,
                acc: List<&2, Row>) -> List<&2, Row>:
  match n:
    case 0n: acc
    case 1n+m:
      match ss:
        case Nil{}: acc
        case s <> t:
          match items:
            case Nil{}: acc
            case k <> tk: q.layout.go(m, at, t, tk, List.append(&2, Row, acc, [Row{U32.add(at, s), k}]))

def q.layout(at: U32, +items: List<&2, U32>) -> List<&2, Row>:
  q.layout.go(List.length(&2, U32, items), at, D.iter_sig(items), items, Nil{})

# :113, `max([o + w.dtype.itemsize for o, w in rows], default=off + 8)`. The
# accumulator starts at 0 and that is safe because every `o + k` is positive, so
# `max(0, ...)` IS the max -- and 0 is also how the EMPTY case is recognised and
# answered with `off + 8`, one word, which is the size of a `first`/`count`
# pair. MEASURED: `max([], default=0+8) == 8`.
def q.end.go(n: Nat, at: U32, rs: List<&2, Row>, +acc: U32) -> U32:
  match n:
    case 0n: Bool.pick(U32, U32.is_zero(acc), U32.add(at, 8), acc)
    case 1n+m:
      match rs:
        case Nil{}: Bool.pick(U32, U32.is_zero(acc), U32.add(at, 8), acc)
        case Row{+off, +k} <> t:
          q.end.go(m, at, t, Bool.pick(U32, U32.is_gt(U32.add(off, k), acc), U32.add(off, k), acc))

def q.end(at: U32, +rs: List<&2, Row>) -> U32:
  q.end.go(List.length(&2, Row, rs), at, rs, 0)

# the layout as PAIRS, `(off, itemsize)`, so the gate can diff a list of numbers
# against tinygrad's own `layout_args` output. This is `bgl.flat`'s job in the
# WebGPU template and it is the only way the numbers are printable.
def q.flat(rs: List<&2, Row>, acc: List<&2, U32>) -> List<&2, U32>:
  match rs:
    case Nil{}: acc
    case Row{off, k} <> t: q.flat(t, List.append(&2, U32, List.append(&2, U32, acc, [off]), [k]))

# ===========================================================================
# THE THREE STEPS OF `exec`, :112-121, each its own def because each is one
# numbered line range of the Python and each is a different KIND of update.
# ===========================================================================

# :112, `off := round_up(self.nbytes, 256)`. The 256 is the argument block's
# alignment and it is the ONLY alignment in `exec`; the one at :118 is 8 and
# `mt_off256` and `mt_at8` are the rows that keep the two apart.
def q.exec.off(nbytes: U32) -> U32: D.round_up(nbytes, ARG_ALIGN())

# :113 and :112's append. `q.layout` is called TWICE because a `let` is affine
# and a pure call is cheaper to recompute than to name -- and `off` is the
# `max`'s `default`, so the same layout answers both.
def q.exec.rows(q: Q, +at: U32, +items: List<&2, U32>) -> Q:
  match q:
    case Q{+rows, cmds, sizes, stamps, nbytes, npipes, t}:
      Q{List.append(&2, Row, rows, q.layout(at, items)), cmds, sizes, stamps,
         q.end(at, q.layout(at, items)), npipes, t}

# :117, `if any(isinstance(d, UOp) for d in dims)`. A `List` of `Bool` is NOT a
# usable type in Bend (device.bend's measured constraint A: every reader of one
# is refused), so "which dims are symbolic" is a six-bit MASK and `q.any_sym`
# is "is it non-zero". The mask doubles as the builder of :121's tuple, where a
# symbolic dim becomes 1 -- NOT its value, which the ICB reads at dispatch time
# and which is why a symbolic kernel is one `run` per command.
def q.any_sym(m: U32) -> Bool: U32.is_ne(m, 0)

def q.sym_at(m: U32, i: U32) -> Bool: U32.is_eq(U32.and(U32.shrn(m, U32.to_nat(i)), 1), 1)

# :121, `tuple(1 if isinstance(d, UOp) else int(d) for d in dims)`. The APPEND
# is what keeps the order, because `List.append(a, A, xs, [x])` is `xs ++ [x]`.
def q.dim(m: U32, i: U32, d: U32) -> U32: Bool.pick(U32, q.sym_at(m, i), 1, d)

def q.dims.go(n: Nat, +m: U32, ds: List<&2, U32>, +i: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+p:
      match ds:
        case Nil{}: acc
        case d <> t: q.dims.go(p, m, t, U32.add(i, 1), List.append(&2, U32, acc, [q.dim(m, i, d)]))

def q.dims(m: U32, +ds: List<&2, U32>) -> List<&2, U32>:
  q.dims.go(List.length(&2, U32, ds), m, ds, 0, Nil{})

# :118, `at := round_up(self.nbytes, 8)`. EIGHT, not 256: the six u64 dims of a
# symbolic kernel are laid out at word alignment.
def q.exec.at(nbytes: U32) -> U32: D.round_up(nbytes, ZERO_ALIGN())

# :118-120, the symbolic arm: append `(len(self.cmds), at)` to `self.sizes`, lay
# out SIX u64s at `at` -- a `d.cast(uint64)` for a symbolic dim and a
# `UOp.const(d, uint64)` for a constant one, both eight bytes, which is the whole
# reason a mask is enough -- and then `self.nbytes = at + 48`.
#
# `ci` is `len(self.cmds)` as a PARAMETER and not read off the record, because
# `q.ncmds(q)` inside the rebuild would need the parameter twice and the whole
# `Data` record's worth of `+` binders to say so. `q.exec` computes it once from
# the queue it was handed, which is the same value: the append at :121 has not
# happened yet.
def q.exec.sizes.on(ci: U32, q: Q, +at: U32) -> Q:
  match q:
    case Q{rows, cmds, sizes, stamps, nbytes, npipes, t}:
      Q{List.append(&2, Row, rows, q.layout(at, DIM_SIZES())), cmds,
         List.append(&2, Sz, sizes, [Sz{ci, at}]), stamps,
         U32.add(at, SYM_BYTES()), npipes, t}

# a `match` may not scrutinise a CALL, so `if any(isinstance(d, UOp) ...)` is an
# `.at` whose Bool is a PARAMETER. `mt_sym_no` and `mt_sym_yes` are the pair and
# a mutation that made the arm unconditional moves only the first.
def q.exec.sizes.at(sym: Bool, ci: U32, +q: Q) -> Q:
  match sym:
    case True{}: q.exec.sizes.on(ci, q, q.exec.at(Q.nbytes(q)))
    case False{}: q

# :252 `pipes = dedup(c[:2] for c in cmds)` -- dedup on the (lib, name) PAIR,
# and the JOINT condition is the point: two commands with the same entry point
# and different libraries are TWO pipelines. `dedup` on either half alone is a
# different answer, and `mt_pipe_pair` is the fixture that sees it.
def q.pipe_of.take(+s: Seen, same: Bool, at: U32) -> Seen:
  Bool.pick(Seen, Seen.hit(s), s, Bool.pick(Seen, same, Seen{at, True{}}, s))

def q.pipe_of.go(n: Nat, +lib: U32, +nm: String, cs: List<&2, Cmd>, +at: U32, +s: Seen) -> Seen:
  match n:
    case 0n: s
    case 1n+m:
      match cs:
        case Nil{}: s
        case Cmd{+l2, +n2, ds, of, sy} <> t:
          q.pipe_of.go(m, lib, nm, t, U32.add(at, 1),
                       q.pipe_of.take(s, Bool.and(U32.is_eq(l2, lib), String.eq(n2, nm)), at))

# the first-occurrence index of `(lib, name)` among the commands, and whether
# there WAS one. `q.exec.cmd` reads both, hence the `Seen` and not a `U32`.
def q.pipe_of(lib: U32, nm: String, +cs: List<&2, Cmd>) -> Seen:
  q.pipe_of.go(List.length(&2, Cmd, cs), lib, nm, cs, 0, Seen{0, False{}})

# :121, `self.cmds.append((obj.lib, obj.name, dims, off))` -- plus the two things
# `submit` will need and Python computes later: which PIPE this command uses
# (`pipes` at :128) and whether it has SYMBOLIC sizes (`sizes` at :118, indexed
# plus one so 0 means "none").
def q.exec.cmd.on(q: Q, s: Seen, lib: U32, nm: String, ds: List<&2, U32>,
                  off: U32, mask: U32) -> Q:
  match q:
    case Q{rows, cmds, +sizes, stamps, nbytes, npipes, t}:
      Q{rows,
         List.append(&2, Cmd, cmds, [Cmd{lib, nm, ds, off,
           Bool.pick(U32, q.any_sym(mask), U32.add(U32.from_nat(List.length(&2, Sz, sizes)), 1), 0)}]),
         sizes, stamps, nbytes,
         U32.add(npipes, Bool.to_u32(Bool.not(Seen.hit(s)))), t}

def q.exec.cmd(+q: Q, +lib: U32, +nm: String, ds: List<&2, U32>, off: U32, mask: U32) -> Q:
  q.exec.cmd.on(q, q.pipe_of(lib, nm, Q.cmds(q)), lib, nm, ds, off, mask)

# ===========================================================================
# ops_metal.py:112-120 -- everything that happens BEFORE the command is
# appended. Its own def because :118's `len(self.cmds)` is read AFTER the rows
# are laid out and one `Q` cannot be named twice in a body.
def q.exec.pre(+q: Q, nbufs: Nat, vars: List<&2, U32>, +mask: U32) -> Q:
  q.exec.sizes.at(q.any_sym(mask), Q.ncmds(q),
                  q.exec.rows(q, q.exec.off(Q.nbytes(q)), q.items(nbufs, vars)))

# ops_metal.py:109-121 -- `exec`, in the order the source does it. THREE steps
# and the order is the claim: the offset, the layout and the symbolic arm, then
# the command.
def q.exec(+q: Q, nbufs: Nat, vars: List<&2, U32>, lib: U32, nm: String,
           ds: List<&2, U32>, +mask: U32) -> Q:
  a1 = q.exec.off(Q.nbytes(q))
  q.exec.cmd(q.exec.pre(q, nbufs, vars, mask), lib, nm, q.dims(mask, ds), a1, mask)

# ===========================================================================
# ops_metal.py:213-215 -- `check_family` and the arch string. THE TABLE IS THE
# POINT: `enum_MTLGPUFamily` has NINETEEN members and :213 reads it in REVERSE,
#
#   def check_family(f):
#     return next(filter(self.sysdevice.supportsFamily,
#                        reversed([v for v, nm in metal.enum_MTLGPUFamily.items()
#                                  if f in nm])), 0)
#
# so the answer is the LAST member whose NAME CONTAINS `f` that the device
# supports, and 0 when there is none. Walking FORWARD and keeping the LAST
# supported answer is the same number and it is one fold instead of two, and
# `mt_fam_apple9` beside `mt_fam_apple8` is the fixture pair that says the walk
# is a LAST-wins and not a FIRST-wins.
#
# The two calls are NOT SYMMETRIC and that is worth a row: "Mac" is a substring
# of `MTLGPUFamilyMacCatalyst1` and `MTLGPUFamilyMacCatalyst2` as well as of
# `Mac1` and `Mac2`, so `check_family("Mac")` asks about FOUR families and
# `check_family("Apple")` about TEN. MEASURED on this host:
# `check_family("Apple") == 1008` and `check_family("Mac") == 2002`.
# ===========================================================================
def families() -> List<&2, D.AEnt>:
  [D.AEnt{1001, "MTLGPUFamilyApple1"}, D.AEnt{1002, "MTLGPUFamilyApple2"},
   D.AEnt{1003, "MTLGPUFamilyApple3"}, D.AEnt{1004, "MTLGPUFamilyApple4"},
   D.AEnt{1005, "MTLGPUFamilyApple5"}, D.AEnt{1006, "MTLGPUFamilyApple6"},
   D.AEnt{1007, "MTLGPUFamilyApple7"}, D.AEnt{1008, "MTLGPUFamilyApple8"},
   D.AEnt{1009, "MTLGPUFamilyApple9"}, D.AEnt{1010, "MTLGPUFamilyApple10"},
   D.AEnt{2001, "MTLGPUFamilyMac1"}, D.AEnt{2002, "MTLGPUFamilyMac2"},
   D.AEnt{3001, "MTLGPUFamilyCommon1"}, D.AEnt{3002, "MTLGPUFamilyCommon2"},
   D.AEnt{3003, "MTLGPUFamilyCommon3"},
   D.AEnt{4001, "MTLGPUFamilyMacCatalyst1"}, D.AEnt{4002, "MTLGPUFamilyMacCatalyst2"},
   D.AEnt{5001, "MTLGPUFamilyMetal3"}, D.AEnt{5002, "MTLGPUFamilyMetal4"}]

# LAST-wins over the supported members whose name contains `f`, with 0 as
# Python's `next(..., 0)` default. `f` is a PARAMETER, not a field of a record:
# :213 and :215 pass "Apple" and "Mac" and :213 is called from two places, so a
# record would buy nothing a string cannot already do. `+sup` because the fold
# reads it once per row and the `Nat` fuel may not feed a second self-call.
def fam_scan.go(n: Nat, +sup: List<&2, U32>, +f: String, es: List<&2, D.AEnt>, got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match es:
        case Nil{}: got
        case D.AEnt{+ix, nm} <> t:
          fam_scan.go(m, sup, f, t,
                      Bool.pick(U32, Bool.and(String.contains(nm, f),
                                              List.contains(U32, U32.is_eq, sup, ix)),
                                ix, got))

# `sup` is the list of SUPPORTED family ids rather than a bitmask, because the
# ids are sparse (1001..1010, 2001, 2002, 3001..3003, 4001, 4002, 5001, 5002)
# and a mask would spend seventeen bits on seventeen rows that are ten wide.
# There are at most ten supported families, so the membership test is ten
# comparisons and it happens once per init.
def check_family(sup: List<&2, U32>, f: String) -> U32:
  fam_scan.go(List.length(&2, D.AEnt, families()), sup, f, families(), 0)

# :215, `arch = metal.enum_MTLGPUFamily[check_family("Apple") or
# check_family("Mac")][12:]`. TWO facts and they are both load-bearing:
#
#  1. the `or` is a FALLBACK, not a union -- "Apple" wins outright if it
#     answers, and only a zero reaches "Mac". `mt_arch_or` is that row;
#  2. `[12:]` drops the fourteen-character prefix `MTLGPUFamily`, leaving
#     `Apple8`, which is what :146 parses with `int(self.dev.arch[5:]) < 9` and
#     what cstyle.py:361 parses with `target.arch[5:]` for the tensor cores.
#     The name the port leaves is the SAME string the renderer reads, and
#     `mt_arch_slice` is the row that says so.
def FAM_PREFIX() -> Nat: 12n

# `enum_MTLGPUFamily[id]` -- the name for an id, first-wins, and "" for an id
# the table does not have. Python raises KeyError there and cannot: `or`
# answered 0 only when the device supports NOTHING, and `arch` is then never
# read, so the default is unreachable and is here only so the def is total.
def fam_nm.go(n: Nat, +id: U32, es: List<&2, D.AEnt>, got: String) -> String:
  match n:
    case 0n: got
    case 1n+m:
      match es:
        case Nil{}: got
        case D.AEnt{ix, nm} <> t:
          fam_nm.go(m, id, t, Bool.pick(String, U32.is_eq(ix, id), nm, got))

def fam_nm(id: U32) -> String:
  fam_nm.go(List.length(&2, D.AEnt, families()), id, families(), "")

def arch_of(fam: U32) -> String: String.drop(fam_nm(fam), FAM_PREFIX())

# the `or` of :215, as a two-arm choice on a Bool. `mt_arch_or` pins that an
# "Apple" answer is taken as it is and never compared against "Mac".
def dev.arch.apple(mac: U32, +apple: U32) -> U32:
  Bool.pick(U32, U32.is_eq(apple, 0), mac, apple)

# ===========================================================================
# ops_metal.py:187-220 -- MetalDevice, the twelve statements of `__init__` in
# their source order and the four fields the submission path reads.
#
# `resid` is a `U32` and not a `Maybe`, because a `Data` record may not hold a
# `Maybe` field and `Tr` reserves handle 0 for `None` -- which is what makes
# `:206`'s `self.residency.value is not None` and `:142`'s
# `self.dev.residency.value is None` two OPPOSITE reads of the same number.
# `mt_resid_flip` is the pair and it is the row that sees a `not` moved.
# ===========================================================================
type Dev is Data:
  Dev{sysdev: U32, queue: U32, resid: U32, event: U32, fence: U32,
      res: List<&2, U32>, nres: U32, arch: String, fam: U32, nics: U32,
      nslot: U32, sels_made: Bool, t: Tr}

def Dev.of() -> Dev:
  Dev{0, 0, 0, 0, 0, Nil{}, 0, "", 0, 0, 0, False{}, Tr.of()}

def Dev.at(d: Dev, t: Tr) -> Dev:
  match d:
    case Dev{sysdev, queue, resid, event, fence, res, nres, arch, fam, nics, nslot, sels_made, _}:
      Dev{sysdev, queue, resid, event, fence, res, nres, arch, fam, nics, nslot, sels_made, t}

def Dev.tr(d: Dev) -> Tr:
  match d:
    case Dev{sysdev, queue, resid, event, fence, res, nres, arch, fam, nics, nslot, sels_made, t}: t

def Dev.sysdev(d: Dev) -> U32:
  match d:
    case Dev{sysdev, queue, resid, event, fence, res, nres, arch, fam, nics, nslot, sels_made, t}: sysdev

def Dev.queue(d: Dev) -> U32:
  match d:
    case Dev{sysdev, queue, resid, event, fence, res, nres, arch, fam, nics, nslot, sels_made, t}: queue

def Dev.resid(d: Dev) -> U32:
  match d:
    case Dev{sysdev, queue, resid, event, fence, res, nres, arch, fam, nics, nslot, sels_made, t}: resid

def Dev.event(d: Dev) -> U32:
  match d:
    case Dev{sysdev, queue, resid, event, fence, res, nres, arch, fam, nics, nslot, sels_made, t}: event

def Dev.fence(d: Dev) -> U32:
  match d:
    case Dev{sysdev, queue, resid, event, fence, res, nres, arch, fam, nics, nslot, sels_made, t}: fence

def Dev.res(d: Dev) -> List<&2, U32>:
  match d:
    case Dev{sysdev, queue, resid, event, fence, res, nres, arch, fam, nics, nslot, sels_made, t}: res

def Dev.nres(d: Dev) -> U32:
  match d:
    case Dev{sysdev, queue, resid, event, fence, res, nres, arch, fam, nics, nslot, sels_made, t}: nres

def Dev.arch(d: Dev) -> String:
  match d:
    case Dev{sysdev, queue, resid, event, fence, res, nres, arch, fam, nics, nslot, sels_made, t}: arch

def Dev.fam(d: Dev) -> U32:
  match d:
    case Dev{sysdev, queue, resid, event, fence, res, nres, arch, fam, nics, nslot, sels_made, t}: fam

def Dev.nics(d: Dev) -> U32:
  match d:
    case Dev{sysdev, queue, resid, event, fence, res, nres, arch, fam, nics, nslot, sels_made, t}: nics

def Dev.nslot(d: Dev) -> U32:
  match d:
    case Dev{sysdev, queue, resid, event, fence, res, nres, arch, fam, nics, nslot, sels_made, t}: nslot

def Dev.sels_made(d: Dev) -> Bool:
  match d:
    case Dev{sysdev, queue, resid, event, fence, res, nres, arch, fam, nics, nslot, sels_made, t}: sels_made

# :142, `if self.dev.residency.value is None:` -- the ONE read, and `dev.has_res`
# is its negation, so the two call sites of the SAME fact (:142 and :229) spell
# it the same way. A `not` moved into either one of them moves `mt_resid_flip`
# and nothing else, which is why that row exists.
def dev.has_res(resid: U32) -> Bool: U32.is_ne(resid, 0)

def Dev.resid_ok(d: Dev) -> Bool: dev.has_res(Dev.resid(d))

# :197, `self.sysdevice = metal.MTLCreateSystemDefaultDevice()`. A C FUNCTION
# and not a message, so `sel` is 0 -- and it is the only C call in `__init__`.
def dev.sysdevice(t: Tr) -> Tr: Tr.emit(CALL_SYSDEVICE, PLACEHOLDER_IX(), 0, t)

# :200, `self.queue = self.sysdevice.newCommandQueueWithMaxCommandBufferCount(1024)`.
# The 1024 is the argument and it is a constant of the port: a Metal command
# queue holds at most 1024 command buffers, and `run` commits one per call.
def dev.queue(t: Tr) -> Tr:
  Tr.emit(CALL_NEWQUEUE, sel_ix("newCommandQueueWithMaxCommandBufferCount"), QUEUE_MAX_CMDS(), t)

# :201-202, `if self.queue.value is None: raise RuntimeError(msg_noqueue())`.
# THE FIRST REFUSAL and the only one in `__init__`.
def dev.queue_ok(ok: Bool, +d: Dev) -> Dev: Dev.at(d, Tr.refuse(Dev.tr(d), ok))

# :204, `rsd = ctypes.cast(objc.msg("new", clsmeth=True)(MTLResidencySetDescriptor),
# metal.MTLResidencySetDescriptor)` -- a CLASS allocation, and the same `new`
# selector as :246's `MTLComputePipelineDescriptor.new()` and :254's
# `MTLIndirectCommandBufferDescriptor.new()`. Three sites, one selector.
# :205, `self.residency = self.sysdevice.newResidencySetWithDescriptor_error(rsd, None)`.
#
# THERE IS NO REFUSAL HERE and that is a fact about the source, not an omission:
# :205-206 do not raise, they SKIP. A device with no residency set is a device
# whose :143 `useResources:count:usage:` runs instead, so `has` sets the FIELD
# and `mt_resid_excl` is the row that the two paths are alternatives.
def dev.residency(has: Bool, d: Dev) -> Dev:
  match d:
    case Dev{sysdev, queue, resid, event, fence, res, nres, arch, fam, nics, nslot, sels_made, +t}:
      +a2 = Tr.emit(CALL_NEWRESID, sel_ix("newResidencySetWithDescriptor_error"), 0,
                   cnew(t))
      Dev{sysdev, queue, Bool.pick(U32, has, Tr.here(a2), 0), event, fence, res,
           nres, arch, fam, nics, nslot, sels_made, a2}

# :206, `if self.residency.value is not None: self.queue.addResidencySet(self.residency)`.
def dev.add_residency(d: Dev) -> Dev:
  match d:
    case Dev{sysdev, queue, resid, event, fence, res, nres, arch, fam, nics, nslot, sels_made, t}:
      Dev{sysdev, queue, resid, event, fence, res, nres, arch, fam, nics, nslot, sels_made,
          Tr.emit(CALL_ADDRESID, sel_ix("addResidencySet"), 0, t)}

# a `match` may not scrutinise a CALL, so `if self.residency.value is not None` is
# an `.at` whose Bool is a PARAMETER. ONE `.at` for :206 and ONE for :229
# because the two differ in what they do, and a shared helper would need a tag.
def dev.add_residency.at(has: Bool, +d: Dev) -> Dev:
  match has:
    case True{}: dev.add_residency(d)
    case False{}: d

# :209, `self.event, self.fence = self.sysdevice.newSharedEvent(), self.sysdevice.newFence()`.
# A Python TUPLE assign, so the two calls are evaluated LEFT TO RIGHT and the
# event exists before the fence is asked for. `mt_handles_order` is that row and
# it is the only thing that sees the order.
def dev.handles(d: Dev) -> Dev:
  match d:
    case Dev{sysdev, queue, resid, event, fence, res, nres, arch, fam, nics, nslot, sels_made, +t}:
      +a1 = Tr.emit(CALL_NEWEVENT, sel_ix("newSharedEvent"), 0, t)
      +a2 = Tr.emit(CALL_NEWFENCE, sel_ix("newFence"), 0, a1)
      Dev{sysdev, queue, resid, Tr.here(a1), Tr.here(a2), res, nres, arch, fam,
           nics, nslot, sels_made, a2}

# :208, `self.resources, self.table = list[int](), (ctypes.c_uint64 * 1)()`. An
# empty list and a ONE-element table, and the one element is a zero the table
# never reads until the first `mark_resident` grows it. The table's length is
# `max(len(resources), 1)` at :234, which is TABLE_MIN, defined there.
def TABLE_MIN() -> U32: 1

def dev.table_len(+nres: U32) -> U32:
  Bool.pick(U32, U32.is_lt(nres, TABLE_MIN()), TABLE_MIN(), nres)

# :213's `check_family` is called TWICE and the result is stored, so the
# `supportsFamily` calls happen once per family probe and not once per candidate.
# `dev.family` records the probe of the family the device answered with.
def dev.family(+fam: U32, d: Dev) -> Dev:
  match d:
    case Dev{sysdev, queue, resid, event, fence, res, nres, arch, +f0, nics, nslot, sels_made, +t}:
      Dev{sysdev, queue, resid, event, fence, res, nres, arch, fam, nics, nslot, sels_made,
          Tr.emit(CALL_FAMILY, sel_ix("supportsFamily"), fam, t)}

# :215, `arch = enum_MTLGPUFamily[check_family("Apple") or check_family("Mac")][12:]`.
def dev.arch(a: U32, m: U32, +d: Dev) -> Dev:
  match d:
    case Dev{sysdev, queue, resid, event, fence, res, nres, arch, fam, nics, nslot, sels_made, t}:
      Dev{sysdev, queue, resid, event, fence, res, nres, arch_of(dev.arch.apple(m, a)), fam,
           nics, nslot, sels_made, t}

# ops_metal.py:196-220 -- `__init__`, in the order the twelve statements are
# written. The ORDER is the claim and `mt_init_order` is the row: the system
# device, then the queue (and the ONE refusal), then the residency set (and
# `addResidencySet` only if it exists), then the event and the fence, then the
# family probe, then the arch. `q_ok` drives the refusal and `has_res` is the
# residency set's EXISTENCE, which is not a refusal.
def dev.init(+apple: U32, +mac: U32, q_ok: Bool, +has_res: Bool) -> Dev:
  +a1 = Dev.at(Dev.of(), dev.sysdevice(Tr.of()))
  a2 = Dev.at(a1, dev.queue(Dev.tr(a1)))
  +a3 = dev.queue_ok(q_ok, a2)
  +a4 = dev.add_residency.at(has_res, dev.residency(has_res, a3))
  a5 = dev.handles(a4)
  a6 = dev.arch(apple, mac, dev.family(dev.arch.apple(mac, apple), a5))
  a6


def CALL_SELREG() -> U32: 37

# `CALL_NKIND = 38` WAS HERE, and it is gone because it was DEAD and UNCHECKABLE.
# It claimed to be the number of call kinds, nothing read it, and there is no table
# of kinds in this file to check it against -- the tags are inline literals in
# thirty-eight `Tr.emit` calls. A count that no table can contradict is a comment
# wearing a number's clothes. `mt_constmap.py` prints the tag set's density instead
# (`0..37 n=38 DENSE=True`), which is the same claim and IS checkable.

# ===========================================================================
# :222-237 -- `sels` and `mark_resident`, the two halves of the selector
# table's lifetime. THE FLAG IS THE MEMO: `@functools.cached_property` means the
# table is built the first time anything READS it, and :237's `if "sels" in
# self.__dict__` is that same fact. One `Bool` stands in for the memo, and
# `mt_sels_made` is the row.
#
# The Buffer itself is a SLOT in `D.Bar` rather than a record here, because
# :263 reads `buf.get_storage().meta` off the answer of `new_icb` and
# `device.bend`'s `Buffer` is already an arena slot -- so `nbytes` is
# `size * itemsize` and a view's offset ACCUMULATES, and neither is a field.
type Made is Data:
  Made{ar: D.Bar, ix: U32, t: Tr}

def Made.ar(+m: Made) -> D.Bar:
  match m:
    case Made{ar, ix, t}: ar

def Made.ix(+m: Made) -> U32:
  match m:
    case Made{ar, ix, t}: ix

def Made.t(+m: Made) -> Tr:
  match m:
    case Made{ar, ix, t}: t

# THREE readers, all of them `+m`: a `Made` is a `Data` record and reading two
# of its fields is two reads of the parameter, which needs the annotation.
def Made.nbytes(+m: Made) -> U32: D.nbytes(Made.ar(m), Made.ix(m))
def Made.addr(+m: Made) -> U32: D.Bn.addr(D.bar_at(Made.ar(m), Made.ix(m)))
def Made.off(+m: Made) -> U32: D.Bn.off(D.bar_at(Made.ar(m), Made.ix(m)))

# `Buffer(self.host, n, dt, ...)` in device.bend's own terms: the node is built
# here and `D.bnew` appends it and hands back BOTH the arena and the index, so
# the caller is handed the pair. THE ARENA RULE, and it is why `Made` exists --
# a def that builds a node and returns only its index hands the caller nothing
# and the node is eliminated along with the call.
def made.of(ar: D.Bar, dev: U32, size: U32, dt: S.Dt, addr: U32, sp: D.Bspec, t: Tr) -> Made:
  +f = D.bnew(ar, D.Bn{0, dev, size, dt, 0, 0, False{}, addr, sp})
  Made{D.BFound.ar(f), D.BFound.i(f), t}

def made.at(m: Made, t: Tr) -> Made:
  match m:
    case Made{ar, ix, _}: Made{ar, ix, t}

# :224, `vals = [self.queue.value, self.event.value, self.fence.value,
# ctypes.addressof(self.table), len(self.resources), *[objc.getsel(s).value for
# s in SELECTORS]]`. FIVE handles then THIRTEEN selectors. MEASURED on this host:
# `len(d.sels) == 18` and `d.sels.nbytes == 144`, and the buffer is `uint64` on
# `self.host` -- so the five handles are the first five u64 words and the
# thirteen selectors are the next thirteen. `mt_sels_len` is the count row and
# `mt_sels_sels` is the thirteen indices in the SELECTORS order.
def sels_len() -> U32: 18
def sels_bytes() -> U32: U32.mul(sels_len(), S.Dt.itemsize(S.uint64()))

# :237, `self.sels.host.view(fmt='Q')[3:5] = array.array('Q',
# [ctypes.addressof(self.table), len(self.resources)])`. TWO words, at indices
# 3 and 4 -- which are `HANDLES[3]` and `HANDLES[4]`, i.e. `resources` and
# `count`. That two-element slice is the ONLY thing `mark_resident`'s
# no-residency path writes, and it is a rewrite of two slots and not of the
# table, which is why the buffer never has to be rebuilt.
def SELS_RES() -> U32: 3
def SELS_CNT() -> U32: 4

# `*[objc.getsel(s.encode()).value for s in SELECTORS]` -- THIRTEEN
# `sel_registerName` calls, in the SELECTORS table's own order, and the buffer's
# last thirteen words are their return values. `getsel` is
# `functools.cache(lib.sel_registerName)`, so the CACHE is the table and the
# port's thirteen calls are what a cold table costs.
def selreg.go(n: Nat, ss: List<&2, String>, +i: U32, t: Tr) -> Tr:
  match n:
    case 0n: t
    case 1n+m:
      match ss:
        case Nil{}: t
        case s <> t2: selreg.go(m, t2, U32.add(i, 1),
                                Tr.emit(CALL_SELREG, sel_ix(s), i, t))

def selreg(t: Tr) -> Tr:
  selreg.go(List.length(&2, String, selectors()), selectors(),
           U32.add(SELS_CNT(), 1), t)

# :226, `Buffer(self.host, len(vals), dtypes.uint64, initial_value=...)` and
# then the `cached_property`'s memo.
def dev.sels(ar: D.Bar, dev: U32) -> Made:
  made.at(made.of(ar, dev, sels_len(), S.uint64(), 0, D.spec(), Tr.of()),
          selreg(Tr.of()))

def dev.sels_made.at(d: Dev) -> Dev:
  match d:
    case Dev{sysdev, queue, resid, event, fence, res, nres, arch, fam, nics, nslot, _, t}:
      Dev{sysdev, queue, resid, event, fence, res, nres, arch, fam, nics, nslot, True{}, t}

# ===========================================================================
# :228-237, `mark_resident`. TWO PATHS and they are MUTUALLY EXCLUSIVE, which
# is the load-bearing fact and not an optimisation:
#
#   if self.residency.value is not None:                 # a residency set exists
#     objc.msg("addAllocation:" if add else "removeAllocation:")(residency, mtl)
#     return objc.msg("commit")(residency)               # the commit is INSIDE
#   self.resources.append(...) if add else .remove(...)  # the table is NOT
#   self.table = (ctypes.c_uint64 * max(len(resources), 1))(*resources)
#   if "sels" in self.__dict__: self.sels.host.view('Q')[3:5] = [addr, count]
#
# The residency path does NOT touch `self.resources`, so the `count` handle the
# sels table carries is STALE on a device that has a residency set -- and that
# is correct, because the only reader of it (`:143`'s `useResources:count:usage:`)
# is in the path that only runs when there is NO residency set. The two guards
# are the SAME predicate, and `mt_resid_excl` is the row that sees a mutation
# making both paths run.
def dev.mark_resident.rs(mtl: U32, +add: Bool, t: Tr) -> Tr:
  a1 = Tr.emit(Bool.pick(U32, add, CALL_RS_ADD(), CALL_RS_DEL()),
               sel_ix(Bool.pick(String, add, "addAllocation:", "removeAllocation:")), mtl, t)
  Tr.emit(CALL_RS_COMMIT, sel_ix("commit"), 0, a1)

# :233, `self.resources.append(...) if add else self.resources.remove(...)`.
# `list.remove` RAISES when the value is absent and there is no port of that
# here, deliberately: :233 is only reached for a buffer `_alloc` has just made
# and `mark_resident(mtl, True)` has not yet been called for it.
def dev.mark_resident.res.at(has: Bool, mtl: U32, +add: Bool, +res: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, has, res,
            Bool.pick(List<&2, U32>, add, List.append(&2, U32, res, [mtl]), res))

# :234's `max(len(self.resources), 1)` -- the table is never empty, because
# `ctypes.addressof` of a zero-length array is the address of nothing and the
# sels table stores it. `mt_table_one` is the row.
def dev.mark_resident.nres.at(has: Bool, +add: Bool, +nres: U32) -> U32:
  Bool.pick(U32, has, nres,
            Bool.pick(U32, add, U32.add(nres, 1), U32.sub(nres, 1)))

# the two-word rewrite of :237. TWO stores, and the second one's argument is the
# NEW count, so `mt_sels_rewrite` is a COUNT row as well as an order row.
def dev.mark_resident.rewrite(+nres: U32, t: Tr) -> Tr:
  Tr.emit(CALL_STORE, SELS_CNT(), nres, Tr.emit(CALL_STORE, SELS_RES(), nres, t))

def dev.mark_resident.tab.at(made: Bool, nres: U32, t: Tr) -> Tr:
  match made:
    case True{}: dev.mark_resident.rewrite(nres, t)
    case False{}: t

# The whole of :228-237 in one def, because the two paths update three different
# fields and a `Bool.pick` between two complete `Tr`s is the honest shape: both
# arms are BUILT (that is what `Bool.pick` does) and one is chosen, and both are
# pure list constructions so building both costs nothing but time.
def dev.mark_resident(+mtl: U32, +add: Bool, d: Dev) -> Dev:
  match d:
    case Dev{sysdev, queue, +resid, event, fence, +res, +nres, arch, fam, nics, nslot, +sels_made, +t}:
      # `+nres` is read by the field and by the `nres.at` that decides the new
      # one, and `+res` by the field and by `res.at`. The two `nres.at` calls
      # MUST agree, which is why the trace arm is given the answer and not a
      # second walk: one fact, one fold, two readers.
      +n2 = dev.mark_resident.nres.at(dev.has_res(resid), add, nres)
      Dev{sysdev, queue, resid, event, fence,
          dev.mark_resident.res.at(dev.has_res(resid), mtl, add, res), n2, arch,
          fam, nics, nslot, sels_made,
          Bool.pick(Tr, dev.has_res(resid), dev.mark_resident.rs(mtl, add, t),
                    dev.mark_resident.tab.at(sels_made, n2, t))}

# :239-241, `new_slots`:
#   `self.profile_slots.add(buf := Buffer(self.host, n, dtypes.uint64, initial_value=bytes(8 * n)))`
# A HOST buffer of `n` u64s, zeroed, and a WEAK SET of them -- a `WeakSet[Buffer]`,
# so a buffer that dies takes its entry with it. The port carries the COUNT and
# not the set, and that is a real difference worth naming: `synchronize`'s
# `for buf in list(self.profile_slots)` would visit a buffer the port has
# dropped. What survives is the SIZE (`8 * n`, which is `sels_bytes`' u64
# stride) and the count.
def SLOTS_STRIDE() -> U32: 8
def new_slots_bytes(n: U32) -> U32: U32.mul(n, SLOTS_STRIDE())

# :240's `Buffer(self.host, n, dtypes.uint64, ...)`, and the WeakSet's add.
def dev.new_slots(ar: D.Bar, dev: U32, n: U32) -> Made:
  made.at(made.of(ar, dev, n, S.uint64(), 0, D.spec(), Tr.of()), Tr.of())

def dev.add_slot(d: Dev) -> Dev:
  match d:
    case Dev{sysdev, queue, resid, event, fence, res, nres, arch, fam, nics, nslot, sels_made, t}:
      Dev{sysdev, queue, resid, event, fence, res, nres, arch, fam, nics,
           U32.add(nslot, 1), sels_made, t}

# :215's `b.max_numel() > 4` -- :218's `ctx.new_slots(b.max_numel()) if
# b.max_numel() > 4 else None`. FOUR is the threshold and it is a real
# decision: a program with at most four dims has no timestamps to collect, so no
# slots buffer is made and no set is grown. `mt_slots_thresh` is the row and the
# `> 4` is a STRICT comparison -- `>= 4` would allocate for a 4-dim program.
def SLOTS_MIN() -> U32: 4
def dev.wants_slots(n: U32) -> Bool: U32.is_gt(n, SLOTS_MIN())

# :101, `mtl_poll(tl) = mtl_msg(tl, mtl_sel(tl.device, "event"), "signaledValue",
# ret=ctypes.c_void_p)`. ONE msgSend on the EVENT handle, and the timeline is
# the event -- the comment at :100 says so and this is the whole of it. The
# `ret=c_void_p` is why it is the SECOND `MSGSEND` binding, not the first.
def mtl_poll(d: Dev) -> Tr:
  Tr.emit(CALL_MSGSEND, SEL_SIGNALEDVALUE(), 0, Dev.tr(d))

# ===========================================================================
# :146, THE APPLE9 GUARD, and it is a DISJUNCTION whose two conjuncts are true
# on DIFFERENT devices. That is the fixture family the brief's "two rules claim
# one node" trap asks for, in the only form this file has:
#
#   arch       startswith("Apple")   int(arch[5:]) < 9   `or`    `and`
#   "Apple8"   true                 true  (8 < 9)       TRUE    TRUE
#   "Apple9"   true                 false (9 < 9)       FALSE   FALSE
#   "Apple10"  true                 false (10 < 9)      FALSE   FALSE
#   "Mac2"     false                true  (2 < 9)       TRUE    FALSE
#   "Metal4"   false                true  (4 < 9)       TRUE    FALSE
#
# THE DISJUNCTION IS ONLY VISIBLE ON THE LAST TWO, and the first version of this
# comment claimed that nothing is ever False and was WRONG: it was written from
# :145's comment ("before apple9 the encoder must use the pipelines") instead of
# from the code, and `mt_apple9_apple9` printing False is what caught it. The
# arm runs on Apple 8 and earlier and on every non-Apple family, and the two
# `mt_apple9_mac2` / `mt_apple9_metal4` rows are the ONLY pair an `or` read as
# an `and` can move -- so those two exist and the Apple rows exist to pin the
# other direction.
# ===========================================================================
def APPLE9() -> U32: 9
def APPLE_OFF() -> Nat: 5n

# `int(arch[5:])` -- the SLICE, not a parse of the whole. `int()` raises on
# "on1" and the `or` never reaches it there, because `not startswith("Apple")`
# has already answered True. `Nat.read` answers None instead and this maps it
# to 0, so the port is TOTAL where Python raises, and the value it reaches is
# never the one that would have raised.
def dev.apple_num.go(m: Maybe<&2, Nat>) -> U32:
  match m:
    case None{}: 0
    case Some{n}: U32.from_nat(n)

def dev.apple_num(arch: String) -> U32:
  dev.apple_num.go(Nat.read(String.drop(arch, APPLE_OFF())))

def dev.apple9(+arch: String) -> Bool:
  Bool.or(Bool.not(String.starts_with(arch, "Apple")),
          U32.is_lt(dev.apple_num(arch), APPLE9()))

# ===========================================================================
# `MTLSize`, the one struct the argument marshalling builds by name, and
# `prod(dims[3:])` -- the local size's product, which is what :262 compares
# against `maxTotalThreadsPerThreadgroup`.
# ===========================================================================
type MtlSize is Data:
  MtlSize{w: U32, h: U32, d: U32}

def MtlSize.w(s: MtlSize) -> U32:
  match s:
    case MtlSize{w, h, d}: w

def MtlSize.h(s: MtlSize) -> U32:
  match s:
    case MtlSize{w, h, d}: h

def MtlSize.d(s: MtlSize) -> U32:
  match s:
    case MtlSize{w, h, d}: d

# :264, `MTLSize(*dims[:3])` and `MTLSize(*dims[3:])` -- THREE fields each, and
# `dims` is `(*global_size, *local_size)` (:116), so `[:3]` is the GLOBAL size
# and `[3:]` the LOCAL. `mt_size_global` and `mt_size_local` are the pair and
# they are the composability claim: the renderer emits one dispatch and the
# device submits the six numbers that dispatch reads.
#
# `Maybe.default` rather than a `match`, because a `match` may not scrutinise
# `List.get` and a `Some{g}` binder is affine -- the escape is device.bend's
# `bar_at`, and it is here for the same reason: THREE reads of one list, each
# its own call, and no scrutinee.
# The index is a `U32` and not a `Nat` because it is read FOUR times here and a
# `Nat` cannot take a `+` (it is not `Data`); a `U32` can, for free. And the
# three `U32.to_nat` calls are spelled out because a `let` is affine: naming the
# conversion once would make the name two reads.
def mtl_size.at(+i: U32, +ds: List<&2, U32>) -> MtlSize:
  MtlSize{Maybe.default(&2, U32, List.get(&2, U32, ds, U32.to_nat(i)), 0),
          Maybe.default(&2, U32, List.get(&2, U32, ds, Nat.add(U32.to_nat(i), 1n)), 0),
          Maybe.default(&2, U32, List.get(&2, U32, ds, Nat.add(Nat.add(U32.to_nat(i), 1n), 1n)), 0)}

def mtl_size.g(+ds: List<&2, U32>) -> MtlSize: mtl_size.at(0, ds)
def mtl_size.l(+ds: List<&2, U32>) -> MtlSize: mtl_size.at(3, ds)

# :262, `prod(dims[3:])` -- the local size's product, and the right-hand side of
# the ONLY per-command refusal in this file.
def q.prod_l(+ds: List<&2, U32>) -> U32: H.prod_u32(List.drop(&2, U32, ds, 3n))

# ===========================================================================
# ops_metal.py:127-168 -- `submit` and `run`. THE ORDER IS THE PORT and the
# thirteen calls of `run` are the whole of the submission.
#
# `run` is a nested def with FOUR conditional arms -- no residency set, the
# apple9 pair, the stamps pair and `last` -- and the first row of the gate
# pins the thirteen-STATEMENT shape the source has, arms tagged, because an
# order claim with no fixture for each arm is decorative.
# ===========================================================================
def SLOT_PENDING() -> U32: 7
def SLOT_CBUF() -> U32: 5
def SLOT_STRIDE4() -> U32: 4

# :159, `slots.after(h).index(7 + 4 * first).store(0)` and :160,
# `slots.after(h).index(5 + 4 * first).store(cbuf)`. The `4 * first` is
# `SLOT_STRIDE4` -- four u64 words of timeline per command buffer, and the two
# slots are 5 and 7 of each group, i.e. the LAST and the SECOND-TO-LAST.
def slot_at(base: U32, first: U32) -> U32:
  U32.add(base, U32.mul(SLOT_STRIDE4(), first))

# ONE `run` invocation's own state (ops_metal.py:138). The nine fields are the
# four Python parameters, three derived numbers, the command buffer the first
# call mints, the signalled value, and the trace.
type Run is Data:
  Run{first: U32, count: U32, last: Bool, n: U32, np: U32, zero: U32, cbuf: U32,
      val: U32, t: Tr}

def Run.of(n: U32, np: U32, zero: U32, val: U32, first: U32, count: U32, last: Bool) -> Run:
  Run{first, count, last, n, np, zero, 0, val, Tr.of()}

def Run.first(+r: Run) -> U32:
  match r:
    case Run{first, count, last, n, np, zero, cbuf, val, t}: first

def Run.np(+r: Run) -> U32:
  match r:
    case Run{first, count, last, n, np, zero, cbuf, val, t}: np

def Run.zero(+r: Run) -> U32:
  match r:
    case Run{first, count, last, n, np, zero, cbuf, val, t}: zero

def Run.cbuf(+r: Run) -> U32:
  match r:
    case Run{first, count, last, n, np, zero, cbuf, val, t}: cbuf

def Run.count(+r: Run) -> U32:
  match r:
    case Run{first, count, last, n, np, zero, cbuf, val, t}: count

def Run.last(r: Run) -> Bool:
  match r:
    case Run{first, count, last, n, np, zero, cbuf, val, t}: last

def Run.t(+r: Run) -> Tr:
  match r:
    case Run{first, count, last, n, np, zero, cbuf, val, t}: t

def Run.at(r: Run, t: Tr) -> Run:
  match r:
    case Run{first, count, last, n, np, zero, cbuf, val, _}: Run{first, count, last, n, np, zero, cbuf, val, t}

# :139, `cbuf := mtl_msg(h, mtl_sel(self.devs, "queue"), "commandBuffer",
# ret=ctypes.c_void_p)` -- the FIRST call of every `run`, on the QUEUE handle,
# and the `cb.store(cbuf)` is a UOp store into `mtl_cb`'s placeholder.
def run.cmdbuf(d: Dev, r: Run) -> Run:
  match r:
    case Run{first, count, last, n, np, zero, cbuf, val, +t}:
      Run{first, count, last, n, np, zero, Tr.here(t), val,
           Tr.emit(CALL_MSGSEND, SEL_COMMANDBUFFER(), 0, t)}

# :140, `h = enc.store(mtl_msg(h, cb, "computeCommandEncoder", ret=ctypes.c_void_p))`
def run.encoder(d: Dev, r: Run) -> Run:
  match r:
    case Run{first, count, last, n, np, zero, cbuf, val, +t}:
      Run{first, count, last, n, np, zero, cbuf, val,
           Tr.emit(CALL_MSGSEND, SEL_COMPUTEENCODER(), 0, t)}

# :141, `h = mtl_msg(h, enc, "waitForFence:", mtl_sel(self.devs, "fence").load())`
# The FENCE handle rides on the call, and :152's `updateFence:` rides on the
# SAME handle -- so `mt_fence_pair` is the row that sees one of them changed.
def run.waitfence(d: Dev, r: Run) -> Run:
  match r:
    case Run{first, count, last, n, np, zero, cbuf, val, +t}:
      Run{first, count, last, n, np, zero, cbuf, val,
           Tr.emit(CALL_MSGSEND, SEL_WAITFENCE(), Dev.fence(d), t)}

# :143, `h = mtl_msg(h, enc, "useResources:count:usage:",
# mtl_sel(self.devs, "resources").load(), mtl_sel(self.devs, "count").load(), 3)`.
# The THIRD argument is the usage, `MTLResourceUsageRead | Write` = 3, and the
# second is `len(self.resources)` -- which :237 keeps current in the sels table
# and which is STALE whenever a residency set exists, because then this line
# never runs. That is `mt_resid_excl` again, from the other side.
def run.use_resources(d: Dev, r: Run) -> Run:
  match r:
    case Run{first, count, last, n, np, zero, cbuf, val, +t}:
      Run{first, count, last, n, np, zero, cbuf, val,
           Tr.emit(CALL_MSGSEND, SEL_USERESOURCES(), Dev.nres(d), t)}

# a `match` may not scrutinise a CALL, so each `if ...` is an `.at` whose Bool is
# a PARAMETER. FOUR `.at`s in `run` and no shared helper, because the four differ
# in what they skip and a shared one would need a tag.
def run.use_resources.at(nores: Bool, d: Dev, r: Run) -> Run:
  match nores:
    case True{}: run.use_resources(d, r)
    case False{}: r

# :147-148,
#   r = UOp.range(len(pipes), next(UOp.unique_num), dtype=dtypes.uint64)
#   h = mtl_msg(h, enc, "setComputePipelineState:", header.index(1 + n + r).load())
# ONE PER PIPE, and the word index is `1 + n + i` -- the header layout of :266,
# `[icb, *commands, *pipes]`, so the pipelines start at word `1 + n`. That is
# the same `1 + n` :148 and the row `mt_hdr_pipes` both use, and the two cannot
# disagree because there is one def.
def run.pipeline.go(nat: Nat, +i: U32, d: Dev, r: Run) -> Run:
  match nat:
    case 0n: r
    case 1n+p:
      match r:
        case Run{first, count, last, +n, np, zero, cbuf, val, +t}:
          run.pipeline.go(p, U32.add(i, 1), d,
                          Run{first, count, last, n, np, zero, cbuf, val,
                               Tr.emit(CALL_MSGSEND, SEL_SETPIPESTATE(),
                                       U32.add(U32.add(n, HDR_PIPE()), i), t)})

def run.pipeline(+r: Run, d: Dev) -> Run:
  run.pipeline.go(U32.to_nat(Run.np(r)), 0, d, r)

def run.pipeline.at(a9: Bool, d: Dev, r: Run) -> Run:
  match a9:
    case True{}: run.pipeline(r, d)
    case False{}: r

# :149, `h = mtl_msg(h, enc, "dispatchThreadgroups:threadsPerThreadgroup:",
# args.index(zero), args.index(zero)).end(r)` -- BOTH arguments are the SAME
# word, `zero`, so the dimensions of this dispatch are read from the ICB at run
# time rather than passed. That is what makes the symbolic arm of `exec`
# necessary and it is why `zero` is the one argument the row pins.
def run.dispatch(d: Dev, r: Run) -> Run:
  match r:
    case Run{first, count, last, n, np, +zero, cbuf, val, +t}:
      Run{first, count, last, n, np, zero, cbuf, val,
           Tr.emit(CALL_MSGSEND, SEL_DISPATCH(), zero, t)}

def run.dispatch.at(a9: Bool, d: Dev, r: Run) -> Run:
  match a9:
    case True{}: run.dispatch(d, r)
    case False{}: r

# :151, `h = mtl_msg(h, enc, "executeCommandsInBuffer:withRange:",
# header.after(h).index(0).load(), first, count)` -- word 0 of the header is the
# ICB (`[icb, *commands, *pipes]`, :266) and the RANGE is `[first, first+count)`.
def run.execute(d: Dev, r: Run) -> Run:
  match r:
    case Run{first, +count, last, n, np, zero, cbuf, val, +t}:
      Run{first, count, last, n, np, zero, cbuf, val,
           Tr.emit(CALL_MSGSEND, SEL_EXECUTECMDS(), count, t)}

# :152, `h = mtl_msg(h, enc, "updateFence:", mtl_sel(self.devs, "fence").load())`
def run.updatefence(d: Dev, r: Run) -> Run:
  match r:
    case Run{first, count, last, n, np, zero, +cbuf, val, +t}:
      Run{first, count, last, n, np, zero, cbuf, val,
           Tr.emit(CALL_MSGSEND, SEL_UPDATEFENCE(), Dev.fence(d), t)}

# :153, `h = mtl_msg(h, enc, "endEncoding")` -- no arguments at all, the only
# msgSend in `run` with none.
def run.endencoding(d: Dev, r: Run) -> Run:
  match r:
    case Run{first, count, last, n, np, +zero, cbuf, val, +t}:
      Run{first, count, last, n, np, zero, cbuf, val,
           Tr.emit(CALL_MSGSEND, SEL_ENDENCODING(), 0, t)}

# :159, `slots.after(h).index(7 + 4 * first).store(0)` -- the PENDING marker, the
# zero that says "no times for this command buffer yet", and it is stored
# BEFORE the command buffer itself, which is the whole of the dance :155-156
# describes ("MTL4 solves that dance"). `mt_run_stamps` is the order row.
def run.slot0(d: Dev, r: Run) -> Run:
  match r:
    case Run{+first, count, last, n, np, zero, cbuf, val, +t}:
      Run{first, count, last, n, np, zero, cbuf, val,
           Tr.emit(CALL_STORE, slot_at(SLOT_PENDING(), first), 0, t)}

# :160, `slots.after(h).index(5 + 4 * first).store(cbuf)`.
def run.slot1(d: Dev, r: Run) -> Run:
  match r:
    case Run{+first, count, last, n, np, zero, +cbuf, val, +t}:
      Run{first, count, last, n, np, zero, cbuf, val,
           Tr.emit(CALL_STORE, slot_at(SLOT_CBUF(), first), cbuf, t)}

# `+d` because :159 and :160 are TWO steps and both take the device: they
# address the same `slots` UOp, which is the seam's, and :219's `slots` field
# is where it comes from.
def run.stamps.at(stamps: Bool, +d: Dev, +r: Run) -> Run:
  match stamps:
    case True{}: run.slot1(d, run.slot0(d, r))
    case False{}: r

# :162, `if last: h = mtl_msg(h, cb, "encodeSignalEvent:value:",
# mtl_sel(self.devs, "event").load(), self.value)`. The EVENT handle and the
# value `signal` (:125) recorded -- and it is the ONLY place the value is used.
def run.signal(d: Dev, r: Run) -> Run:
  match r:
    case Run{first, count, last, n, np, zero, cbuf, +val, +t}:
      Run{first, count, last, n, np, zero, cbuf, val,
           Tr.emit(CALL_MSGSEND, SEL_SIGNALEVENT(), val, t)}

def run.signal.at(last: Bool, d: Dev, +r: Run) -> Run:
  match last:
    case True{}: run.signal(d, r)
    case False{}: r

# :163, `return mtl_msg(h, cb, "commit")` -- the LAST call, on the COMMAND
# BUFFER and not on the encoder, and the return that ends the run.
def run.commit(d: Dev, r: Run) -> Run:
  match r:
    case Run{first, count, last, n, np, zero, cbuf, val, +t}:
      Run{first, count, last, n, np, zero, cbuf, val,
           Tr.emit(CALL_MSGSEND, SEL_COMMIT(), 0, t)}

# ops_metal.py:138-163, in source order. THIRTEEN steps, four of them
# conditional, and no step needs a guard of its own: THE RAISE IS IN THE TRACE
# (see `Tr.emit`), so a refusal truncates this list rather than needing a
# `Bool` at each of the four arms.
def run.at(+d: Dev, +r: Run, nores: Bool, +a9: Bool, stamps: Bool) -> Tr:
  a1 = run.cmdbuf(d, r)
  a2 = run.encoder(d, a1)
  a3 = run.waitfence(d, a2)
  a4 = run.use_resources.at(nores, d, a3)
  a5 = run.pipeline.at(a9, d, a4)
  a6 = run.dispatch.at(a9, d, a5)
  a7 = run.execute(d, a6)
  a8 = run.updatefence(d, a7)
  a9b = run.endencoding(d, a8)
  b1 = run.stamps.at(stamps, d, a9b)
  b2 = run.signal.at(Run.last(r), d, b1)
  Run.t(run.commit(d, b2))

# ===========================================================================
# :127-136 and :166-168 -- `submit`. THE ICB GEOMETRY FIRST, and the two
# buffer sizes have to AGREE.
# ===========================================================================

# :129, `buf = UOp.placeholder((zero + 24 + 8 * (1 + n + len(pipes)),), dtypes.uint8,
# device=self.devs, volatile=True, tag=("mtl_icb", tuple(self.cmds), zero + 24))`
# and :253, `buf = Buffer(self.device, header + 8 * (1 + len(cmds) +
# len(pipes)), dtypes.uint8, options=BufferSpec(nolru=True), preallocate=True)`
# with `header = zero + 24` being the THIRD element of the tag at :130. THE TWO
# SIZES ARE SPELLED OUT SEPARATELY IN THE SOURCE and they must be the same
# number, so `mt_icb_sizes` is the row and a `+ 24` moved in one of them moves
# it and nothing else.
def icb_size(header: U32, n: U32, np: U32) -> U32:
  U32.add(header, U32.mul(ADDR_SIZE(), U32.add(1, U32.add(n, np))))

# :130's third tag element and :132's `args.bitcast(dtypes.uint64)[zero // 8 + 3:]`
# -- the SAME number reached from two directions: a byte offset on one side and a
# word index on the other. `zero // 8 + 3` words past `zero // 8` IS
# `zero + 24` bytes, and `mt_hdr_word` is the row that says the two agree.
def icb_header(zero: U32) -> U32: U32.add(zero, ICB_HEADER_PAD())

def hdr_word(zero: U32) -> U32: U32.add(U32.div(zero, ADDR_SIZE()), HDR_SKIP())

# :266, `buf.host.view(fmt='Q')[header // 8:] = array.array('Q', [icb.value,
# *[c.value for c in commands], *[self.pipeline(*p).value for p in pipes]])`. The
# layout is ICB, then the COMMANDS, then the PIPELINES, and every index
# `run` uses is relative to the header: word 0 is the ICB (:151), word
# `1 + ci` is command ci (:136) and word `1 + n + i` is pipeline i (:148).
# `mt_hdr_layout` is the row.
def hdr_icb() -> U32: HDR_ICB()
def hdr_cmd(ci: U32) -> U32: U32.add(HDR_CMD(), ci)
def hdr_pipe(n: U32, i: U32) -> U32: U32.add(U32.add(n, HDR_PIPE()), i)

# :135-136, the SYMBOLIC-SIZE loop, and it is BEFORE every `run` because it
# patches the ICB's dispatch sizes in place -- the sizes the `run` at :149 will
# later dispatch with. One msgSend per entry of `self.sizes`, at the byte offset
# of that command's six u64s, and :136's two arguments are
# `args.index(off)` and `args.index(off + 24)`.
def q.submit.sizes.go(nat: Nat, +i: U32, ss: List<&2, Sz>, t: Tr) -> Tr:
  match nat:
    case 0n: t
    case 1n+m:
      match ss:
        case Nil{}: t
        case Sz{ci, at} <> t2:
          q.submit.sizes.go(m, U32.add(i, 1), t2,
                            Tr.emit(CALL_MSGSEND, SEL_CONCDISPATCH(), at, t))

# :128, `n, zero, pipes = len(self.cmds), round_up(self.nbytes, 8), dedup(...)`.
# `zero` is the byte offset of the THREE zero u64s at `zero + 8 * i` (:131) and
# it is the same `zero` :149 dispatches with, so it is EIGHT-aligned and
# `mt_zero_align` is the row.
def q.submit.zero(nbytes: U32) -> U32: D.round_up(nbytes, ZERO_ALIGN())

# :131, `patch(buf, self.rows + [(zero + 8 * i, UOp.const(0, dtypes.uint64)) for
# i in range(3)])` -- THREE zero rows, at `zero`, `zero + 8` and `zero + 16`,
# and three is the `+ 24` in both buffer sizes. `mt_zero_rows` is the row.
def zero_row(i: U32, zero: U32) -> U32: U32.add(zero, U32.mul(ADDR_SIZE(), i))

# `self.stamps` decides between ONE `run` over the whole range and TWO runs,
# and `n > 1` decides between two runs and one. Both are the source's own words.
def q.syms(q: Q) -> Bool: U32.is_ne(Q.stamps(q), 0)

def q.many(q: Q, n: U32) -> Bool: Bool.and(q.syms(q), U32.is_gt(n, 1))

# THE THREE PATHS, and it is a THREE-WAY choice -- which is why it is two
# `Bool.pick`s and NOT a `U32` ladder: constraint line 5182, a three-way choice
# over literals that are not 0/1/n is refused on a `U32` with "a declared
# constructor (unknown: U32)".
#
#   :166 `if not self.stamps: return run(h, 0, n, True)`   -- one run, whole range
#   :167 `if n > 1: h = run(..., r, 1, False).end(r)`       -- the n-1 range
#   :168 `return run(h, n - 1, 1, True)`                    -- the LAST one
#
# so with stamps and n > 1 there are TWO `run`s and the first is NOT `last`, and
# the last call in the whole trace is the second `run`'s `commit`. `mt_submit_two`
# and `mt_submit_one` are the two rows and a mutation that made the first run
# `last` moves only the first.
def Run.of.t(n: U32, np: U32, zero: U32, val: U32, first: U32, count: U32,
             last: Bool, t: Tr) -> Run:
  Run{first, count, last, n, np, zero, 0, val, t}

# `+n` because `n` is BOTH the run's own field (`run`'s `n` parameter, which
# :148 reads as `1 + n + r`) and the run's `count` in the no-stamps path, where
# :166 is `run(h, 0, n, True)`. Python spells both `n` and so does the port.
def q.submit.nostamps(+d: Dev, +n: U32, np: U32, zero: U32, val: U32,
                       nores: Bool, a9: Bool, t: Tr) -> Tr:
  run.at(d, Run.of.t(n, np, zero, val, 0, n, True{}, t), nores, a9, False{})

# THE SECOND `run` STARTS FROM THE FIRST'S TRACE. That is not bookkeeping: :167
# is `h = run(h.after(r := UOp.range(n - 1, ...)), r, 1, False).end(r)` -- `h` is
# the ACCUMULATOR, threaded through both calls, and a port that gave each `run`
# a fresh trace would lose the first run's thirteen calls entirely. `mt_submit_two`
# is the row and it is the only one that can see it.
def q.submit.runs2(+d: Dev, +n: U32, +np: U32, +zero: U32, +val: U32, +nores: Bool,
                   +a9: Bool, +t: Tr) -> Tr:
  a1 = run.at(d, Run.of.t(n, np, zero, val, 0, 1, False{}, t), nores, a9, True{})
  run.at(d, Run.of.t(n, np, zero, val, U32.sub(n, 1), 1, True{}, a1), nores, a9, True{})

def q.submit.runs1(+d: Dev, +n: U32, +np: U32, +zero: U32, +val: U32, nores: Bool,
                   a9: Bool, t: Tr) -> Tr:
  run.at(d, Run.of.t(n, np, zero, val, 0, 1, True{}, t), nores, a9, True{})

# `Bool.pick` is STRICT: all THREE traces are built and one is chosen. That costs
# three `run`s' worth of list construction and is correct, because a trace is a
# pure list and the only side effect in this file is the RETURN value.
def q.submit.at(nostamps: Bool, many: Bool, +d: Dev, +n: U32, +np: U32, +zero: U32,
                +val: U32, +nores: Bool, +a9: Bool, +t: Tr) -> Tr:
  Bool.pick(Tr, nostamps, q.submit.nostamps(d, n, np, zero, val, nores, a9, t),
            Bool.pick(Tr, many, q.submit.runs2(d, n, np, zero, val, nores, a9, t),
                      q.submit.runs1(d, n, np, zero, val, nores, a9, t)))

# :127-168, the whole of `submit`. FOUR steps in source order: the sizes loop,
# the three locals, the three-way tail.
def q.submit(+d: Dev, +q: Q) -> Tr:
  +n = Q.ncmds(q)
  a1 = q.submit.sizes.go(List.length(&2, Sz, Q.sizes(q)), 0, Q.sizes(q), Q.t(q))
  q.submit.at(Bool.not(q.syms(q)), q.many(q, n), d, n, Q.npipes(q),
              q.submit.zero(Q.nbytes(q)), 0, Bool.not(Dev.resid_ok(d)),
              dev.apple9(Dev.arch(d)), a1)

# ===========================================================================
# :243-249 -- `pipeline`, `@functools.cache`d on `(lib, name)`. FOUR calls and
# TWO `checked` refusals, and the order inside :247 is the claim: Python
# evaluates `setComputeFunction`'s ARGUMENT first, so
# `newFunctionWithName(to_ns_str(name))` happens BEFORE
# `setComputeFunction(library.newFunctionWithName(...))`, not after it.
# `mt_pipe_order` is the row.
# ===========================================================================
# `checked`'s SECOND refusal, and the arm of `checked` that :249 is. The
# compiler's `ccompile` magic check is a DIFFERENT function and reusing it here
# was the first version's bug: it compares a library's head and tail against
# MTLB/ENDT and so every pipeline REFUSED. `mt_pipe_ok` is the row and it
# printed False for a week.
def dev.pipeline.f(pipe_ok: Bool, t: Tr) -> Tr:
  Tr.refuse(Tr.emit(CALL_NEWPIPE,
                    sel_ix("newComputePipelineStateWithDescriptor_options_reflection_error"),
                    0, t), pipe_ok)

def dev.pipeline.lib(+lib_ok: Bool, t: Tr) -> Tr:
  Tr.refuse(Tr.emit(CALL_NEWLIB, sel_ix("newLibraryWithData_error"), 0, t), lib_ok)

# :246, `descriptor = metal.MTLComputePipelineDescriptor.new()`
def dev.pipeline.desc(t: Tr) -> Tr: cnew(t)

# :247's THREE calls, in the order Python evaluates them:
#   `descriptor.setComputeFunction(library.newFunctionWithName(to_ns_str(name)))`
# Python evaluates the ARGUMENT before the call, so `to_ns_str` -- and with it the
# NSString WALL at :23 -- happens BEFORE `newFunctionWithName:`, and
# `setComputeFunction:` before that. THE ORDER IS THE CLAIM and `mt_pipe_calls` is
# the row: dropping the NSString moves nothing else, and a trace that starts at
# `newFunctionWithName:` reads as though the name were a literal, which is exactly
# the question the seam turns on.
def dev.pipeline.fun(t: Tr) -> Tr:
  Tr.emit(CALL_SETCOMPFUNC, sel_ix("setComputeFunction"), 0,
          Tr.emit(CALL_NEWFUNC, sel_ix("newFunctionWithName"), 0,
                  cns_string(t)))

# :248, `descriptor.setSupportIndirectCommandBuffers(True)` -- the flag that says
# this pipeline is going to be driven from an ICB, and it is why `new_icb` can
# exist at all. `mt_pipe_icb` is the row.
def dev.pipeline.icb(t: Tr) -> Tr:
  Tr.emit(CALL_SETICB, sel_ix("setSupportIndirectCommandBuffers"), 0, t)

# :243-249, the four steps in source order, and `checked`'s two refusals at the
# two sites `checked` wraps. `lib_ok` and `pipe_ok` drive them.
def dev.pipeline(+lib_ok: Bool, pipe_ok: Bool, t: Tr) -> Tr:
  dev.pipeline.f(pipe_ok,
                 dev.pipeline.icb(dev.pipeline.fun(dev.pipeline.desc(dev.pipeline.lib(lib_ok, t)))))

# :262, `if prod(dims[3:]) > (mx := state.maxTotalThreadsPerThreadgroup()): raise`.
# The local size's product against the pipeline's limit, and it is the ONLY
# per-command refusal in the file. The comparison is a STRICT `>` -- an exactly
# fitting local size is legal and `>=` would refuse it, which is why
# `mt_local_eq` (equal) and `mt_local_over` (one over) are the pair.
def local_ok(prod: U32, mx: U32) -> Bool: Bool.not(U32.is_gt(prod, mx))

# ===========================================================================
# :251-268 -- `new_icb`, the indirect command buffer. It is the LONGEST step
# list in the file and the one that decides whether a kernel can run at all, so
# the numbers are the composability claim:
#
#   ONE command buffer bind, at index 0     :256 setMaxKernelBufferBindCount(1)
#   the header's byte size                  :253 header + 8 * (1 + n + len(pipes))
#   six global/local numbers                :264 MTLSize(*dims[:3]), MTLSize(*dims[3:])
#   the entry point NAME                    :247 newFunctionWithName(to_ns_str(name))
#
# ===========================================================================

# :256, `desc.setMaxKernelBufferBindCount(1)`. ONE. And :263,
# `cmd.setKernelBuffer_offset_atIndex(buf.get_storage().meta, off, 0)`, puts it
# at index 0 -- which is the index cstyle's `constant args_t& args
# [[buffer(0)]]` reads. `mt_icb_binds` is the row and it is the single number
# the renderer and the device have to agree on.
def icb_binds() -> U32: KERNEL_BUF_BINDS()
def KERNEL_BUF_IX() -> U32: 0

# :253, `Buffer(self.device, header + 8 * (1 + len(cmds) + len(pipes)),
# dtypes.uint8, options=BufferSpec(nolru=True), preallocate=True)`. The Buffer is
# UINT8 and its spec is `nolru=True`, so device.bend's four-conjunct LRU policy
# says it is NEVER recycled: `mt_nolru` is the row and the decision is
# `D.recycled`'s, not this file's.
def icb_spec() -> D.Bspec: D.Bspec{False{}, False{}, False{}, True{}, False{}}

# `preallocate=True` is a BufferSpec flag device.bend does not model -- it is
# about WHEN the device memory is reserved, not whether it is recycled -- so the
# port carries the three flags `D.Bspec` has and the one it does not is a
# comment. `D.recycled` reads only `nolru` and `ext_ptr`, so the decision is
# unchanged and `mt_nolru` is unaffected.
def dev.new_icb(ar: D.Bar, dev: U32, +q: Q, header: U32) -> Made:
  made.of(ar, dev, icb_size(header, Q.ncmds(q), Q.npipes(q)), S.uint8(), 0,
          icb_spec(), Tr.of())

# :254, `desc = metal.MTLIndirectCommandBufferDescriptor.new()`
def icb_desc(t: Tr) -> Tr: cnew(t)

# :255, `desc.setCommandTypes(metal.MTLIndirectCommandTypeConcurrentDispatch)`.
# `ConcurrentDispatch` and NOT `concurrentDispatchThreads`: the ICB dispatches
# THREADGROUPS, which is what cstyle's kernel wants -- one invocation per
# workgroup -- and not individual threads. MEASURED: `enum_MTLIndirect-
# CommandType[32] == MTLIndirectCommandTypeConcurrentDispatch`.
def icb_cmdtype(t: Tr) -> Tr:
  Tr.emit(CALL_SETCMDTYPE, sel_ix("setCommandTypes"), CMDTYPE_CONCURRENT(), t)

# :256, and the ONE bind count.
def icb_binds1(t: Tr) -> Tr:
  Tr.emit(CALL_SETBINDS, sel_ix("setMaxKernelBufferBindCount"), icb_binds(), t)

# :257, `icb = self.sysdevice.newIndirectCommandBufferWithDescriptor_
# maxCommandCount_options(desc, max(len(cmds), 1), 0)`. `max(len(cmds), 1)` --
# never zero, because a zero-count ICB is not a thing -- and `0` for `options`.
def icb_max(+n: U32) -> U32: Bool.pick(U32, U32.is_zero(n), 1, n)

def icb_new(+n: U32, t: Tr) -> Tr:
  Tr.emit(CALL_NEWICB, sel_ix("newIndirectCommandBufferWithDescriptor_maxCommandCount_options"),
          icb_max(n), t)

# :258, `if icb.value is None: raise RuntimeError(msg_noicb())`. THE FIFTH
# REFUSAL, and its message is the one a user can act on.
def icb_ok(ok: Bool, t: Tr) -> Tr: Tr.refuse(t, ok)

# :259, `commands = [icb.indirectComputeCommandAtIndex(i).own() for i in
# range(len(cmds))]`. TWO calls per command -- the index and then `retain`, which
# is what `.own()` is -- and `mt_icb_cmds` is the count row for the pair.
def icb_cmd.go(nat: Nat, +i: U32, +n: U32, t: Tr) -> Tr:
  match nat:
    case 0n: t
    case 1n+m:
      icb_cmd.go(m, U32.add(i, 1), n,
                 Tr.emit(CALL_RETAIN, sel_ix("retain"), i,
                         Tr.emit(CALL_ICBCMD, sel_ix("indirectComputeCommandAtIndex"), i, t)))

def icb_cmds(+n: U32, t: Tr) -> Tr:
  icb_cmd.go(U32.to_nat(n), 0, n, t)

# :263, `cmd.setKernelBuffer_offset_atIndex(buf.get_storage().meta, off, 0)`.
# THE BIND. The buffer is the ICB header Buffer, the offset is the command's own
# `off` from :121, and the index is 0.
def icb_bind(off: U32, t: Tr) -> Tr:
  Tr.emit(CALL_SETKBUF, sel_ix("setKernelBuffer_offset_atIndex"), off, t)

# :264, `cmd.concurrentDispatchThreadgroups_threadsPerThreadgroup(MTLSize(*dims
# [:3]), MTLSize(*dims[3:]))`. The GLOBAL size and the LOCAL size, as two
# MTLSizes, and they are the four numbers the renderer and this file share.
def icb_disp(t: Tr) -> Tr:
  Tr.emit(CALL_CONCDISP, sel_ix("concurrentDispatchThreadgroups_threadsPerThreadgroup"),
          0, t)

# :265, `cmd.setBarrier()` -- the last call of every command's setup, and the one
# that says the commands in an ICB are ordered against each other.
def icb_barrier(t: Tr) -> Tr: Tr.emit(CALL_SETBAR, sel_ix("setBarrier"), 0, t)

# :261, `cmd.setComputePipelineState(state := self.pipeline(lib, name))` -- the
# PIPELINE is built here, per command, and the cache at :243 is what makes that
# cheap. So each command costs `pipeline`'s four calls as well, and
# `mt_icb_calls` is the row that counts them all.
def icb_pipeline(t: Tr) -> Tr: dev.pipeline(True{}, True{}, t)

# ONE command's five steps, :261-265, in source order. `off` is the command's
# own offset and `lib_ok`/`pipe_ok`/`local_ok` drive the refusals. THE ORDER IS
# THE CLAIM: the pipeline, then the bind, then the dispatch, then the barrier --
# and the `local_ok` refusal sits BETWEEN the pipeline and the bind, so a local
# size that is too big stops the command before it has a buffer bound at all.
def icb_cmd.setup(off: U32, +lib_ok: Bool, +pipe_ok: Bool, lo: Bool, t: Tr) -> Tr:
  a1 = icb_pipeline(t)
  a2 = Tr.refuse(a1, lo)
  a3 = icb_bind(off, a2)
  a4 = icb_disp(a3)
  icb_barrier(a4)

# :266, `buf.host.view(fmt='Q')[header // 8:] = array.array('Q', [icb.value,
# *[c.value for c in commands], *[self.pipeline(*p).value for p in pipes]])` --
# ONE store at word `header // 8`, and its payload is `1 + n + len(pipes)` words.
# `mt_icb_hdrstore` is the row.
def icb_hdr_word(header: U32) -> U32: U32.div(header, ADDR_SIZE())

def icb_store(header: U32, +n: U32, np: U32, t: Tr) -> Tr:
  Tr.emit(CALL_STORE, icb_hdr_word(header), U32.add(1, U32.add(n, np)), t)

# :267, `self.icbs[buf] = (icb, commands)` -- a `WeakKeyDictionary[Buffer,
# tuple]`, so an ICB Buffer that dies takes its entry with it. The port carries
# the COUNT and `mt_nics` is the row.
def icb_keep(d: Dev) -> Dev:
  match d:
    case Dev{sysdev, queue, resid, event, fence, res, nres, arch, fam, nics, nslot, sels_made, t}:
      Dev{sysdev, queue, resid, event, fence, res, nres, arch, fam,
           U32.add(nics, 1), nslot, sels_made, t}

# ops_metal.py:251-268, the whole of `new_icb` as a TRACE, in source order. The
# Buffer travels beside it in a `Made` because `device.bend`'s Buffer is a slot
# in an arena and the two cannot be separated.
# :260-265, the per-command loop, folded over the queue's commands. The
# refusal at :262 is PER COMMAND, so a fixture with ONE command cannot tell a
# per-command refusal from a whole-ICB one -- which is why `mt_icb_local_*` uses
# a two-command queue and `mt_icb_refuse` uses the ICB-level one at :258.
def icb_setup.go(nat: Nat, cs: List<&2, Cmd>, +lib_ok: Bool, +pipe_ok: Bool,
                 +lo: Bool, t: Tr) -> Tr:
  match nat:
    case 0n: t
    case 1n+m:
      match cs:
        case Nil{}: t
        case Cmd{lib, name, dims, off, sym} <> t2:
          icb_setup.go(m, t2, lib_ok, pipe_ok, lo,
                       icb_cmd.setup(off, lib_ok, pipe_ok, lo, t))

def icb_setup(+q: Q, lib_ok: Bool, pipe_ok: Bool, lo: Bool, t: Tr) -> Tr:
  icb_setup.go(List.length(&2, Cmd, Q.cmds(q)), Q.cmds(q), lib_ok, pipe_ok, lo, t)

def dev.icb(ar: D.Bar, dev: U32, +q: Q, +header: U32, ok: Bool) -> Made:
  +b = dev.new_icb(ar, dev, q, header)
  a1 = icb_desc(Made.t(b))
  a2 = icb_binds1(icb_cmdtype(a1))
  a3 = icb_new(Q.ncmds(q), a2)
  a4 = icb_ok(ok, a3)
  a5 = icb_cmds(Q.ncmds(q), a4)
  made.at(b, icb_store(header, Q.ncmds(q), Q.npipes(q), icb_setup(q, True{}, True{}, True{}, a5)))

# THE SAME, with the two `checked` refusals and the :262 local-size refusal
# driven. `mt_icb_refuse_n` is the row that sees the TRUNCATION at command 1 of
# two, and it is the only fixture in the file that can.
def dev.icb.rf(ar: D.Bar, dev: U32, +q: Q, +header: U32, ok: Bool, +lib_ok: Bool,
               +pipe_ok: Bool, +lo: Bool) -> Made:
  +b = dev.new_icb(ar, dev, q, header)
  a1 = icb_desc(Made.t(b))
  a2 = icb_binds1(icb_cmdtype(a1))
  a3 = icb_new(Q.ncmds(q), a2)
  a4 = icb_ok(ok, a3)
  a5 = icb_cmds(Q.ncmds(q), a4)
  made.at(b, icb_store(header, Q.ncmds(q), Q.npipes(q), icb_setup(q, lib_ok, pipe_ok, lo, a5)))


# ===========================================================================
# :174-185 -- MetalAllocator. FOUR methods and three of them are the interesting
# ones, and they are all thin over `device.bend`: `_alloc` makes a Buffer in the
# arena, `_offset` IS `D.host_offset`, and `_free` is a trace.
# ===========================================================================

# :175-176,
#   `mtl = metal.MTLBuffer(options.external_ptr) if options.external_ptr else
#          self.dev.sysdevice.newBufferWithLength_options(size, metal.MTLResourceStorageModeShared)`
# MEASURED: `MTLResourceStorageModeShared == 0` -- it is a bit in
# `MTLResourceOptions` and the SHARED bit is the EMPTY one, which is why a Metal
# buffer is host-visible with no option at all and why `mt_storagemode` being 0
# is a real row and not a placeholder.
def MTL_DEV() -> U32: 7

# :175's `MTLBuffer(options.external_ptr)` -- the external arm, ONE call and a
# different selector. `mt_alloc_ext` is the row; on this host `ext` is False
# everywhere, so the arm is exercised by the gate and by nothing else.
def alloc_ext(t: Tr) -> Tr: Tr.emit(CALL_MSGSEND, sel_ix("newBufferWithLength_options"), 0, t)

def alloc_size(size: U32, t: Tr) -> Tr:
  Tr.emit(CALL_NEWBUFFER, sel_ix("newBufferWithLength_options"), size, t)

# :179, `BufferStorage(mtl.gpuAddress(), mtl, MMIOInterface(c, size) if
# (c := mtl.contents()) else None)`. Python evaluates the three arguments LEFT
# TO RIGHT, so `gpuAddress` is asked for BEFORE `contents` is, and the Buffer's
# ADDRESS is the first of the two. `mt_alloc_order` is the row and it is the
# only thing that sees the order.
def alloc_addr(t: Tr) -> Tr: Tr.emit(CALL_GPUADDR, sel_ix("gpuAddress"), 0, t)
def alloc_contents(t: Tr) -> Tr: Tr.emit(CALL_CONTENTS, sel_ix("contents"), 0, t)

# :177, `if mtl.value is None: raise MemoryError(msg_oom(size))`. THE THIRD
# REFUSAL, and `size=` is Python's `=` f-spec, so the message names the VARIABLE
# and then its value. `mt_oom` diffs the string.
def alloc_ok(ok: Bool, t: Tr) -> Tr: Tr.refuse(t, ok)

# :174-179, `_alloc`, in source order: the buffer, the refusal, `mark_resident`,
# then the two handle reads of the BufferStorage.
# `mark_resident(mtl, True)` is handed the HANDLE the buffer call returned, which
# is `Tr.here` read BEFORE the refusal -- `Tr.refuse` does not advance the counter
# because a refused call mints nothing.
def alloc.of(ar: D.Bar, dev: U32, +size: U32, ext: Bool, ok: Bool, +d: Dev) -> Made:
  match d:
    case Dev{sysdev, queue, resid, event, fence, res, nres, arch, fam, nics, nslot, sels_made, +t}:
      +a1 = Bool.pick(Tr, ext, alloc_ext(t), alloc_size(size, t))
      +a2 = alloc_ok(ok, a1)
      a3 = Dev.tr(dev.mark_resident(Tr.here(a1), True{}, Dev.at(d, a2)))
      +b = made.of(ar, dev, size, S.uint8(), 0, D.spec(), a3)
      made.at(b, alloc_contents(alloc_addr(Made.t(b))))

# :180-184, `_free`:
#   self.dev.synchronize(); self.dev.mark_resident(storage.meta, False)
#   storage.meta.retain = False; storage.meta.release()
# THREE steps and the ORDER is the claim: a Metal free SYNCHRONIZES FIRST,
# because the fence that orders the queue is the only thing that knows whether
# the buffer is still being read, and the comment at :180 says exactly that
# ("metal doesn't track what a kernel reaches"). `mt_free_order` is the row.
# `retain = False` is a Python attribute, not a call, so the trace cannot see
# it and it is a comment here; what it does is stop `id_.__del__` from
# releasing, so that :184's explicit `release()` is the ONE release.
def alloc.free(t: Tr) -> Tr: Tr.emit(CALL_RELEASE, sel_ix("release"), 0, t)

# :185, `def _offset(self, buf, size, offset): return buf + offset`. THE SAME
# LINE as `device.py:330`'s `HostAllocator._offset`, and `D.host_offset` is that
# line ported -- so this is a one-line def that CONSUMES device.bend rather than
# re-deriving it, and `mt_offset` is the row that says the two agree.
def alloc_offset(buf: U32, off: U32) -> U32: D.host_offset(buf, off)

# :181's `self.dev.synchronize()`, the FIRST of the three.
def dev.sync(+t: Tr) -> Tr: t

# ===========================================================================
# :270-285 -- `_wait_signal` and `synchronize`.
# ===========================================================================

# :272-273,
#   `wait = objc.msg("waitUntilSignaledValue:timeoutMS:", ctypes.c_bool, [c_uint64, c_uint64])`
#   `if not wait(self.event, value, int(self.wait_timeout_ms)): raise RuntimeError(f"{self.device} signal wait timed out")`
# The TIMEOUT is the argument, and `int(self.wait_timeout_ms)` is a property of
# the base class and not of this file. `mt_waitsig` is the row and it is the
# SEVENTH refusal's own argument.
def dev.waitsig(tms: U32, +t: Tr) -> Tr:
  Tr.emit(CALL_WAITSIG, sel_ix("waitUntilSignaledValue:timeoutMS:"), tms, t)

# :273's refusal, and the message's device name is the PARAMETER.
def wait_ok(ok: Bool, +t: Tr) -> Tr: Tr.refuse(t, ok)

# :276-278, the profile scan,
#   `for start in range(5, buf.size, 4)`
# FIVE is where the scan starts and FOUR is its step, and both are load-bearing:
# five u64 words of header (the device's `timeline` is two words and the
# hwqueue's three more), and four words per entry because an entry is
# `[cmdbuf, pending, start, end]` -- a COMMAND BUFFER, a PENDING marker, a start
# time and an end time. `mt_sync_words` is the row and `mt_sync_start` /
# `mt_sync_step` are the two numbers in it.
# how many `start` values `range(5, size, 4)` yields: the number of FOUR-word
# groups after the five-word header, which is `ceil((size - 5) / 4)` and ZERO
# for a buffer that is not long enough -- and a `range` whose stop is below its
# start is empty in Python too.
# `ceildiv` and NOT `D.round_up`: `round_up(4, 4)` is 4 and `range(5, 9, 4)`
# has ONE element, so a `round_up` here answers 4 where Python answers 1. There
# is no `floor` in `base.bend`, and `round_up(n, a) // a` IS the ceiling
# division, so the pair of them is the honest spelling.
def ceildiv(+n: U32, +a: U32) -> U32: U32.div(D.round_up(n, a), a)

def sync_count(+size: U32) -> U32:
  Bool.pick(U32, U32.is_lt(size, SYNC_START()), 0,
            ceildiv(U32.sub(size, SYNC_START()), SYNC_STEP()))

# `range(5, size, 4)` as a LIST, so the gate can diff the actual indices and not
# only their count. `mt_sync_idx` is that row.
# NO REVERSE AT THE END, and that is worth a comment because every other fold in
# this file conses: `List.append(a, A, xs, ys)` is `xs ++ ys`, so an appending
# fold is already in order and a `List.reverse` reverses it. `mt_sync_idx17` is
# the row -- a fold that conses and reverses, and a fold that appends, disagree
# ONLY on lists of two or more, and `mt_sync_idx5` is the one-element fixture
# that is blind to it.
def sync_range.go(nat: Nat, +at: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match nat:
    case 0n: acc
    case 1n+m: sync_range.go(m, U32.add(at, SYNC_STEP()),
                             List.append(&2, U32, acc, [at]))

def sync_starts(size: U32) -> List<&2, U32>:
  sync_range.go(U32.to_nat(sync_count(size)), SYNC_START(), Nil{})

# :279-281, the inner body:
#   if slots[start] and not slots[start + 2]:
#     (cb := metal.MTLCommandBuffer(slots[start])).waitUntilCompleted()
#     slots[start], slots[start + 2] = int(cb.GPUStartTime()*1e9), int(cb.GPUEndTime()*1e9)
# THREE calls -- `waitUntilCompleted`, then the two times -- and the `+ 2` is the
# END time's slot, so a filled END is what "already collected" means. The
# `* 1e9` is WALL 6 (no F64) and the gate pins the three calls and the two slot
# indices, not the times.
def sync_end_slot(+start: U32) -> U32: U32.add(start, SYNC_END_OFFSET())


def sync_wait(+t: Tr) -> Tr: Tr.emit(CALL_WAITCOMP, sel_ix("waitUntilCompleted"), 0, t)
def sync_times(+start: U32, +t: Tr) -> Tr:
  Tr.emit(CALL_MSGSEND, sel_ix("GPUEndTime"), sync_end_slot(start),
          Tr.emit(CALL_MSGSEND, sel_ix("GPUStartTime"), start, t))

# :276-281 -- the scan, and the GUARD is `slots[start] and not slots[start+2]`,
# which is a Bool the device owns. `mt_sync_guard` is the pair.
def sync.one(start: U32, filled: Bool, +t: Tr) -> Tr:
  Bool.pick(Tr, filled, t, sync_times(start, sync_wait(t)))

# THE SCAN, :276-281, and this is what `sync_starts` exists for. It was written and
# never CALLED, so `dev.sync` was a no-op and the whole profile path -- the scan, the
# guard, `waitUntilCompleted`, the two timestamps -- was reachable only from the
# gate's own `sync.one` fixtures. THREE calls per GUARDED entry and zero for an
# unguarded one, which is what makes the guard worth a row: an unguarded scan of a
# 13-word buffer and a guarded one are the same trace unless the guard is there.
#
# `Nat` fuel first and it SHRINKS: `xs` shrinks by one cons per arm and `t` grows,
# so neither can lead (constraint "a growing accumulator cannot be the first
# parameter of a self-call").
def dev.sync.go(nat: Nat, xs: List<&2, U32>, +filled: Bool, +t: Tr) -> Tr:
  match nat:
    case 0n: t
    case 1n+m:
      match xs:
        case Nil{}: t
        case x <> t2: dev.sync.go(m, t2, filled, sync.one(x, filled, t))

# :276-281 over a slots buffer of `size` u64 words. The guard is PER ENTRY in Python
# (`slots[start] and not slots[start + 2]`) and the port carries ONE Bool, because a
# `Bool` LIST is not a usable type here -- device.bend's measured constraint, and the
# same reason `exec`'s symbolic test is a six-bit MASK.
def dev.sync_scan(+size: U32, filled: Bool, t: Tr) -> Tr:
  dev.sync.go(U32.to_nat(sync_count(size)), sync_starts(size), filled, t)

# :283-285,
#   super().synchronize(timeout)
#   if (pool := getattr(pools, "pool", None)) is not None: objc.lib.objc_autoreleasePoolPop(pool)
#   pools.pool = objc.lib.objc_autoreleasePoolPush()
# POP THEN PUSH, and that order is the whole of it: a pool is drained before the
# next is pushed, so the autoreleased objects of one submit are released before
# the next submit's are made. `mt_pool_order` is the row and a swap moves it.
def pool_pop(+t: Tr) -> Tr: Tr.emit(CALL_AUTORELPOP, PLACEHOLDER_IX(), 0, t)
def pool_push(+t: Tr) -> Tr: Tr.emit(CALL_AUTORELPUSH, PLACEHOLDER_IX(), 0, t)

def dev.pools.at(has: Bool, +t: Tr) -> Tr:
  match has:
    case True{}: pool_push(pool_pop(t))
    case False{}: pool_push(t)

# ===========================================================================
# :216-220 -- `pm_bufferize`, THE FIRST-WINS CLAIM, and it is the one the brief
# asks for: a node TWO rules both claim, where the ORDER decides.
#
#   self.pm_bufferize = PatternMatcher([
#     (UPat(Ops.PARAM, tag="mtl_sel"),    lambda ctx: ctx.sels),                      # M0
#     (UPat(Ops.PARAM, tag="slots", name="b"),
#                                    lambda ctx,b: ctx.new_slots(b.max_numel()) if b.max_numel() > 4 else None),  # M1
#     (UPat(Ops.PARAM, name="b"),         lambda ctx,b: ctx.new_icb(*b.tag[1:]) if isinstance(b.tag, tuple) and b.tag[0] == "mtl_icb" else None),  # M2
#   ]) + self.pm_bufferize
#
# The `+` is a LIST CONCATENATION and the rewrite is FIRST-WINS, so the three
# METAL rules are consulted BEFORE device.bend's three. That ordering is visible
# in exactly one place: M2 and `device.py:404`'s second rule carry the IDENTICAL
# pattern `UPat(Ops.PARAM, name="b")`, and a PARAM whose tag is `("mtl_icb", …)`
# gets a fresh ICB Buffer and NOT Compiled's program buffer. `mt_pmb_icb` is that
# row; `mt_pmb_cfunc` beside it is the fixture where a cfunc named `b` still gets
# M2's program buffer, because M2's `else None` means it fires but answers
# nothing and `device.bend`'s scan takes over.
# ===========================================================================

# The six fields the six patterns read. `tl` is `Compiled`'s first rule and is
# here so the tail is one call into `device.bend` and not a second transcription
# of it.
type PmbNode is Data:
  PmbNode{par: Bool, mtl_sel: Bool, slots: Bool, named_b: Bool, icb: Bool, tl: Bool}

def pmb_node(par: Bool, ms: Bool, sl: Bool, nb: Bool, ic: Bool, tl: Bool) -> PmbNode:
  PmbNode{par, ms, sl, nb, ic, tl}

def PmbNode.par(n: PmbNode) -> Bool:
  match n:
    case PmbNode{par, mtl_sel, slots, named_b, icb, tl}: par

def PmbNode.mtl_sel(n: PmbNode) -> Bool:
  match n:
    case PmbNode{par, mtl_sel, slots, named_b, icb, tl}: mtl_sel

def PmbNode.slots(n: PmbNode) -> Bool:
  match n:
    case PmbNode{par, mtl_sel, slots, named_b, icb, tl}: slots

def PmbNode.named_b(n: PmbNode) -> Bool:
  match n:
    case PmbNode{par, mtl_sel, slots, named_b, icb, tl}: named_b

def PmbNode.icb(n: PmbNode) -> Bool:
  match n:
    case PmbNode{par, mtl_sel, slots, named_b, icb, tl}: icb

def PmbNode.tl(n: PmbNode) -> Bool:
  match n:
    case PmbNode{par, mtl_sel, slots, named_b, icb, tl}: tl

# the three METAL patterns, as three predicates. `mt_pmb_*` is the family that
# exists so a mutation dropping one conjunct has a row that moves: M1's
# `> 4` and M2's `("mtl_icb", …)` are the two GUARDS, and neither is exercised
# by the other two rules' fixtures.
# EACH PATTERN STATES ITS OWN CONJUNCTS. The first version chained them --
# `pmb_m1 = pmb_m0 && slots && named_b` and `pmb_m2 = pmb_m0 && named_b &&
# icb` -- and `pmb_m0` carries `tag="mtl_sel"`, so BOTH of them silently
# required the `mtl_sel` tag as well. `mt_pmb_slots` and `mt_pmb_icb` answered
# 2 and 2 where the source answers 2 and 3, and nothing else in the gate could
# see it: M0's own fixture is the only one with `mtl_sel` set. The three
# patterns are:
#
#   M0  UPat(Ops.PARAM, tag="mtl_sel")
#   M1  UPat(Ops.PARAM, tag="slots", name="b")
#   M2  UPat(Ops.PARAM, name="b")            -- NO TAG
#
# and M2's MISSING TAG is the whole of the difference between M1 and M2.
def pmb_m0(+n: PmbNode) -> Bool: Bool.and(PmbNode.par(n), PmbNode.mtl_sel(n))
def pmb_m1(+n: PmbNode) -> Bool:
  Bool.and(PmbNode.par(n), Bool.and(PmbNode.slots(n), PmbNode.named_b(n)))

# M2's PATTERN IS `UPat(Ops.PARAM, name="b")` and NOTHING ELSE -- no
# `tag="slots"` and no `tag="mtl_sel"`. `mt_pmb_icb` is the row and it is the
# ONLY row in the family that can see the difference, because every other
# fixture is either an mtl_sel (M0) or a slots (M1) or neither (the tail).
def pmb_m2(+n: PmbNode) -> Bool:
  Bool.and(PmbNode.par(n), Bool.and(PmbNode.named_b(n), PmbNode.icb(n)))

# The three answers, interned so the gate can print one. 0 is Python's `None`,
# 1 is `ctx.sels`, 2 is a new_slots Buffer and 3 is a new_icb Buffer. `0` is
# ALSO "M1 or M2 fired and answered None", which is the case the `else None`
# writes down and the case a LAST-wins fold gets wrong.
def PMB_NONE() -> U32: 0
def PMB_SELS() -> U32: 1
def PMB_SLOTS() -> U32: 2
def PMB_ICB() -> U32: 3

# The step and the run, device.bend's own shape: the candidate answer, whether
# the rule FIRES, and the next index in one `Data` record, because a `Data`
# record may not hold a `Maybe` and the scan may not scrutinise a computed
# value.
# ONE RULE'S CANDIDATE: the arena it would have grown into, the answer it
# would have given, whether it FIRES, and the next rule index. Four things in
# one `Data` record because a `Data` record may not hold a `Maybe` and the scan
# may not scrutinise a computed value -- device.bend's `Step` shape, with the
# arena added because M1 and M2 both ALLOCATE.
type PmbStep is Data:
  PmbStep{ar: D.Bar, got: U32, fires: Bool, k: Nat}

def PmbStep.ar(s: PmbStep) -> D.Bar:
  match s:
    case PmbStep{ar, got, fires, k}: ar

def PmbStep.got(s: PmbStep) -> U32:
  match s:
    case PmbStep{ar, got, fires, k}: got

def PmbStep.fires(s: PmbStep) -> Bool:
  match s:
    case PmbStep{ar, got, fires, k}: fires

def PmbStep.k(s: PmbStep) -> Nat:
  match s:
    case PmbStep{ar, got, fires, k}: k

# The scan's state: the arena, whether a rule has answered, what it answered,
# and the NEXT RULE INDEX. The index is a FIELD and not a second parameter
# because a self-call's fuel may not feed both the self-call and the dispatch,
# and because `Nat` is not `Data` and cannot take a `+` -- `PmbRun.k` is a def
# rather than a field read for the same reason `Tr.calls` is.
type PmbRun is Data:
  PmbRun{ar: D.Bar, made: Bool, got: U32, k: Nat}

def PmbRun.ar(r: PmbRun) -> D.Bar:
  match r:
    case PmbRun{ar, made, got, k}: ar

def PmbRun.made(r: PmbRun) -> Bool:
  match r:
    case PmbRun{ar, made, got, k}: made

def PmbRun.got(r: PmbRun) -> U32:
  match r:
    case PmbRun{ar, made, got, k}: got

def PmbRun.k(r: PmbRun) -> Nat:
  match r:
    case PmbRun{ar, made, got, k}: k

# THE THREE METAL RULES, and each is one `PmbStep`. `ne` is `b.max_numel()`, the
# ONE input M1's guard reads, and it is a parameter rather than a field because a
# UOp's `max_numel` is a graph read (WALL 5) and its VALUE is all the decision
# uses. M1's guard is `> 4`; M2's is `isinstance(b.tag, tuple) and b.tag[0] ==
# "mtl_icb"`, which the `icb` field already is.
def pmb_m1.fires(+n: PmbNode, ne: U32) -> Bool:
  Bool.and(pmb_m1(n), dev.wants_slots(ne))

# M1 and M2 ALLOCATE, so their step grows the arena. The Buffer is a HOST
# `uint64` of `b.max_numel()` elements, which is :218's `new_slots` shape and
# :251's ICB header shape -- and `mt_pmb_grew` is the row that says a rule that
# FIRES and a rule that is KEPT are the same growth.
def pmb_grow(ar: D.Bar, ne: U32) -> D.Bar:
  D.BFound.ar(D.bnew(ar, D.Bn{0, MTL_DEV(), ne, S.uint64(), 0, 0, False{}, 0,
                             D.Bspec{False{}, True{}, False{}, True{}, False{}}}))

def pmb_step1(+ar: D.Bar, fires: Bool, ne: U32) -> PmbStep:
  Bool.pick(PmbStep, fires, PmbStep{pmb_grow(ar, ne), PMB_SLOTS(), True{}, 2n},
            PmbStep{ar, PMB_NONE(), False{}, 2n})

def pmb_step2(+ar: D.Bar, fires: Bool, ne: U32) -> PmbStep:
  Bool.pick(PmbStep, fires, PmbStep{pmb_grow(ar, ne), PMB_ICB(), True{}, 3n},
            PmbStep{ar, PMB_NONE(), False{}, 3n})

def pmb_step(k: Nat, ar: D.Bar, +n: PmbNode, +ne: U32) -> PmbStep:
  match k:
    case 0n: PmbStep{ar, PMB_SELS(), pmb_m0(n), 1n}
    case 1n: pmb_step1(ar, pmb_m1.fires(n, ne), ne)
    case _: pmb_step2(ar, pmb_m2(n), ne)

# FIRST-WINS, spelled out: a rule's answer replaces the accumulator only if it
# FIRES and the accumulator is still empty. `PmbRun.made` is the whole of
# `ops.bend`'s `pm_keep`, and it is what makes M0 beat M1 on a node that is BOTH
# an `mtl_sel` and a `slots` PARAM -- which cannot happen, because
# `UPat(Ops.PARAM, tag="mtl_sel")` and `tag="slots"` are DIFFERENT tags, and
# `mt_pmb_both` is the fixture that proves the two patterns are exclusive.
# THE INDEX ADVANCES ON A MISS TOO, and that is the second bug this gate found
# in its own port: `pmb_keep` returned the accumulator UNCHANGED when a rule did
# not fire, so the rule index stayed at 0, rule 0 was evaluated three times and
# rules 1 and 2 NEVER RAN. Every `pm_bufferize` answer was then the TAIL's, and
# `mt_pmb_icb` printed 2 where the source answers 3. The miss arm carries the
# new index and the OLD arena, the old flag and the old answer.
def pmb_keep(+r: PmbRun, +s: PmbStep) -> PmbRun:
  Bool.pick(PmbRun, Bool.and(PmbStep.fires(s), Bool.not(PmbRun.made(r))),
            PmbRun{PmbStep.ar(s), True{}, PmbStep.got(s), PmbStep.k(s)},
            PmbRun{PmbRun.ar(r), PmbRun.made(r), PmbRun.got(r), PmbStep.k(s)})

# `Nat` FUEL is the first parameter because a self-call must be visibly
# decreasing, and it may not feed both the self-call and the rule dispatch.
def pmb_go(fuel: Nat, +ar: D.Bar, +n: PmbNode, +ne: U32, +r: PmbRun) -> PmbRun:
  match fuel:
    case 0n: r
    case 1n+p:
      +s = pmb_step(PmbRun.k(r), ar, n, ne)
      pmb_go(p, ar, n, ne, pmb_keep(r, s))

def pmb_metal(+ar: D.Bar, +n: PmbNode, ne: U32) -> PmbRun:
  pmb_go(3n, ar, n, ne, PmbRun{ar, False{}, PMB_NONE(), 0n})

# `+ self.pm_bufferize` -- the TAIL of :220, and it is `device.bend`'s OWN scan
# called, not a second copy of it. `Compiled`'s three rules read `is_param`,
# `tag="timeline"` and `name="b"`, and the first two are the `PmbNode` fields
# that carry them across.
def pmb_tail(+ar: D.Bar, +n: PmbNode) -> PmbRun:
  +p = D.pmb_bufferize(ar, D.param(PmbNode.par(n), PmbNode.tl(n), PmbNode.named_b(n), False{}))
  PmbRun{D.Pmb.ar(p), True{}, D.Pmb.got(p), 0n}

# THE WHOLE OF :216-220. The `+` IS a list concatenation and `rewrite` is
# FIRST-WINS, so Metal's three rules are consulted BEFORE device.bend's three --
# and this is the only place that ordering is written down.
def pm_bufferize(+ar: D.Bar, +n: PmbNode, ne: U32) -> PmbRun:
  +a = pmb_metal(ar, n, ne)
  Bool.pick(PmbRun, PmbRun.made(a), a, pmb_tail(PmbRun.ar(a), n))

# ===========================================================================
# THE GATE. Every row is a claim about `ops_metal.py`'s TEXT, about a constant
# in `autogen/metal.py`, or about a LIVE `MetalDevice` on this host -- and every
# expectation is generated by `.agents/slop/mt_oracle.py`, which `ast`-walks this
# same Python file for the selector order and OPENS A REAL DEVICE for the arch,
# the family and the residency set. Nothing here is transcribed by hand.
#
# THE FIXTURES, and there are four of them:
#
#   fx_dev   METAL on THIS host: Apple8, a residency set, and the seven init
#            calls. MEASURED, not assumed.
#   fx_dev0  the same device with NO residency set, which is the configuration
#            that makes :143's `useResources:count:usage:` run -- and so the
#            only fixture in which all THIRTEEN of `run`'s calls appear.
#   fx_q     two commands sharing ONE pipeline, 2 global buffers and 1 var each,
#            the second with SYMBOLIC sizes. The shape of a 2-input 1-output
#            float kernel with a symbolic grid.
#   fx_run   fx_q submitted on fx_dev0 with no stamps: ONE `run` over (0, 2).
# ===========================================================================

def METAL_APPLE() -> U32: 1008
def METAL_MAC() -> U32: 2002

def fx_dev() -> Dev: dev.init(METAL_APPLE(), METAL_MAC(), True{}, True{})
def fx_dev0() -> Dev: dev.init(METAL_APPLE(), METAL_MAC(), True{}, False{})

# 2 global buffers, 1 var of 4 bytes, one MTLB (lib 1) named "kern", and the six
# numbers `(*global_size, *local_size)`.
def DIMS() -> List<&2, U32>: [8, 1, 1, 4, 1, 1]
def VARS() -> List<&2, U32>: [4]
def ALL_SYMS() -> U32: 63

# two `exec`s: the first constant, the second with all six dims symbolic. Both
# use the same (lib, name) so `pipes` is ONE.
def fx_q(mask: U32) -> Q:
  b1 = q.exec(Q.of(), 2n, VARS(), 1, "kern", DIMS(), 0)
  q.exec(b1, 2n, VARS(), 1, "kern", DIMS(), mask)

def fx_run(dev: Dev, mask: U32) -> Tr: q.submit(dev, fx_q(mask))

# the fixture's `zero`, :128's `round_up(self.nbytes, 8)` over BOTH commands.
# It is a def and not a literal because FIVE rows read it and they must all be
# the same number -- the first version of them hardcoded 256, which is the
# FIRST command's `off` rather than `zero`, and CPython answered 280. One `fx_zero`
# is what makes the family agree by construction.
def fx_zero() -> U32: q.submit.zero(Q.nbytes(fx_q(0)))

# :118's `at` for the fixture, read off the queue's OWN `sizes` list. The
# second command is the symbolic one, and `Sz.at` is the reader.
# the SIZE of `self.sizes` for the symbolic fixture -- one entry, because only
# the second command is symbolic. `mt_run_sym_n` and `mt_run_nosym_n` are the pair.



# ONE command, for :168's `run(h, n - 1, 1, True)` with n == 1
def one_cmd() -> Q: q.exec(Q.of(), 2n, VARS(), 1, "kern", DIMS(), 0)

# two commands with the given (lib, name) pairs -- the `pipes` dedup's fixture
def q2_pipe(l1: U32, l2: U32, n2: String) -> Q:
  q.exec(q.exec(Q.of(), 1n, [], l1, "kern", DIMS(), 0), 1n, [], l2, n2, DIMS(), 0)
def fx_t(dev: Dev) -> Tr: Tr.of()

def kinds(k: U32, t: Tr) -> List<&2, U32>: Tr.args(k, Tr.calls(t))
def sels_of(t: Tr) -> List<&2, U32>: Tr.sels(CALL_MSGSEND(), Tr.calls(t))
def store_slots(t: Tr) -> List<&2, U32>: Tr.sels(CALL_STORE(), Tr.calls(t))
def stores(t: Tr) -> List<&2, U32>: Tr.args(CALL_STORE(), Tr.calls(t))
def ncalls(k: U32, t: Tr) -> U32: Tr.count(k, Tr.calls(t))
def seen(t: Tr) -> U32: U32.from_nat(List.length(&2, Call, Tr.calls(t)))
def seq(t: Tr, pat: List<&2, Call>) -> Bool: Tr.has(Tr.calls(t), pat)

def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))

def ush(xs: List<&2, U32>, +sep: String, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case x <> t: ush(t, sep, U32.show(x) <> acc)

def lrow(nm: String, xs: List<&2, U32>) -> IO(Unit):
  IO.print(String.concat([nm, "=", String.join(ush(xs, ",", Nil{}), ",")]))

# --- 1: the selector table, :85-91 -------------------------------------------
# `mt_sel_ix_*` is `(HANDLES + SELECTORS).index(name)` called in CPython, so
# every one of the EIGHTEEN is diffed against Python's own `.index` and the rest
# against the table's position. `mt_sel_n` is the COUNT, which is the row that
# sees a dropped selector -- and a dropped selector makes no `mt_sel_ix_*` row
# move, because `.index` of a name that is not there is 0 and 0 is `queue`'s.
def sel_n() -> U32: U32.from_nat(List.length(&2, D.AEnt, sel_table()))
def sel_h() -> U32: U32.from_nat(List.length(&2, String, handles()))
def sel_s() -> U32: U32.from_nat(List.length(&2, String, selectors()))

def t_sel() -> IO(Unit):
  do IO<Unit>:
    urow("mt_sel_n", sel_n())
    urow("mt_sel_handles", sel_h())
    urow("mt_sel_selectors", sel_s())
    urow("mt_sel_queue", sel_ix("queue"))
    urow("mt_sel_event", sel_ix("event"))
    urow("mt_sel_fence", sel_ix("fence"))
    urow("mt_sel_resources", sel_ix("resources"))
    urow("mt_sel_count", sel_ix("count"))
    urow("mt_sel_cmdbuf", sel_ix("commandBuffer"))
    urow("mt_sel_encoder", sel_ix("computeCommandEncoder"))
    urow("mt_sel_waitfence", sel_ix("waitForFence:"))
    urow("mt_sel_updatefence", sel_ix("updateFence:"))
    urow("mt_sel_signalev", sel_ix("encodeSignalEvent:value:"))
    urow("mt_sel_endenc", sel_ix("endEncoding"))
    urow("mt_sel_commit", sel_ix("commit"))
    urow("mt_sel_useres", sel_ix("useResources:count:usage:"))
    urow("mt_sel_exec", sel_ix("executeCommandsInBuffer:withRange:"))
    urow("mt_sel_conc", sel_ix("concurrentDispatchThreadgroups:threadsPerThreadgroup:"))
    urow("mt_sel_setpipe", sel_ix("setComputePipelineState:"))
    urow("mt_sel_dispatch", sel_ix("dispatchThreadgroups:threadsPerThreadgroup:"))
    urow("mt_sel_sigval", sel_ix("signaledValue"))
    # the first DIRECT selector, and the two that are the SAME SPELLING as a
    # SELECTORS entry with a colon -- the collision the `k` field exists for.
    urow("mt_sel_newqueue", sel_ix("newCommandQueueWithMaxCommandBufferCount"))
    urow("mt_sel_seticb", sel_ix("setSupportIndirectCommandBuffers"))
    urow("mt_sel_icbpipe", sel_ix("setComputePipelineState"))
    urow("mt_sel_setkbuf", sel_ix("setKernelBuffer_offset_atIndex"))
    urow("mt_sel_concd", sel_ix("concurrentDispatchThreadgroups_threadsPerThreadgroup"))
    urow("mt_sel_new", sel_ix("new"))
    urow("mt_sel_nsstring", sel_ix("stringWithUTF8String:"))
    urow("mt_sel_localdesc", sel_ix("localizedDescription"))
    # a name that is not in the table at all
    urow("mt_sel_missing", sel_ix("noSuchSelector"))
    urow("mt_sels_len", sels_len())
    urow("mt_sels_bytes", sels_bytes())
    urow("mt_msgsend_n", MSGSEND_N())
    urow("mt_req_compile", REQUEST_TYPE_COMPILE())
    urow("mt_queue_max", QUEUE_MAX_CMDS())
    urow("mt_usage_rw", USAGE_READ_WRITE())
    urow("mt_storagemode", STORAGE_MODE_SHARED())
    urow("mt_cmdtype", CMDTYPE_CONCURRENT())
    urow("mt_ph_ix", PLACEHOLDER_IX())

# --- 2: the compiler, :40, :56, :60, :62-63, :70 -----------------------------
# The `metal_version` ladder is FOUR arms and the boundary between arm 2 and arm
# 3 is macOS 13, so `mt_ver12` and `mt_ver13` are the pair that sees `>= 13`
# read as `>= 14`.
def t_compiler() -> IO(Unit):
  do IO<Unit>:
    srow("mt_cgs_k", CACHEKEY())
    srow("mt_ver26", metal_version(26))
    srow("mt_ver25", metal_version(25))
    srow("mt_ver14", metal_version(14))
    srow("mt_ver13", metal_version(13))
    srow("mt_ver12", metal_version(12))
    srow("mt_params", mtl_params("CACHE", metal_version(26)))
    srow("mt_params2", mtl_params("/tinygrad/cache", metal_version(12)))
    # :62's `round_up(len(src) + 1, 4) - len(src)`. `mt_pad4` is THE row: a
    # `round_up(len, 4) - len` transcription answers 0 where the source says 1,
    # and 0 is what the other seven rows also say, so only the `len == 4` one
    # can see it.
    urow("mt_pad0", csrc_pad(0))
    urow("mt_pad1", csrc_pad(1))
    urow("mt_pad2", csrc_pad(2))
    urow("mt_pad3", csrc_pad(3))
    urow("mt_pad4", csrc_pad(4))
    urow("mt_pad5", csrc_pad(5))
    urow("mt_pad7", csrc_pad(7))
    urow("mt_psrc7", csrc_padded(7))
    urow("mt_psrc4", csrc_padded(4))
    urow("mt_ppar109", cparams_padded(109))
    urow("mt_req7", creq_len(7, 109))
    urow("mt_req1", creq_len(1, 109))
    urow("mt_qq", cstruct_qq())
    urow("mt_mtlb", MTLB_MAGIC())
    urow("mt_endt", ENDT_MAGIC())
    urow("mt_liboff42", mtl_lib.off(4, 2))
    urow("mt_liboff00", mtl_lib.off(0, 0))
    +a : Tr <- IO.pure(Tr, ccompile(True{}, MTLB_MAGIC(), ENDT_MAGIC(), 134, Tr.of()))
    urow("mt_compile_ok_calls", seen(a))
    row("mt_compile_ok", Bool.not(Tr.refused(a)))
    +b : Tr <- IO.pure(Tr, ccompile(False{}, MTLB_MAGIC(), ENDT_MAGIC(), 134, Tr.of()))
    row("mt_compile_err", Tr.refused(b))
    urow("mt_compile_err_calls", seen(b))
    +c : Tr <- IO.pure(Tr, ccompile(True{}, 0, ENDT_MAGIC(), 134, Tr.of()))
    row("mt_compile_bad", Tr.refused(c))
    urow("mt_compile_bad_calls", seen(c))
    row("mt_nsstring_sel", U32.is_eq(sel_ix("stringWithUTF8String:"), 50))

# --- 2b: THE SEAM, :42-71, MEASURED ------------------------------------------
# Every number below came out of running the REAL `MTLCodeGenServiceBuildRequest`
# on this host with an INSTRUMENTED callback (`.agents/slop/mt_compile_probe.py`),
# not out of reading `compile`. That is the difference between this section and a
# transcription: `reply[8:16] == (104, 0)` and `error == 2` are answers, and the
# two blobs' different first words are the reason `REPLY_LEAD` exists.
#
# WHAT IS STILL THE SEAM, and it is ONE call. `compile` is FFI at exactly two
# points: `MTLCodeGenServiceCreate` (:39) and `MTLCodeGenServiceBuildRequest` (:68).
# The SECOND of those takes `ctypes.byref(callback, -0x10)` -- a pointer to the
# `invoke` slot of an Apple BLOCK, and Bend cannot allocate a block descriptor, let
# alone name its 16th byte. Everything else in :42-71 is now ported and gated:
# the four-way `-std=` ladder, the f-string, the 4-byte source pad, the NUL, the
# 16-byte `<QQ` header, the two request lengths, the callback's `error == 0` arm
# and its other arm, the header sum, the slice, and both refusals.
def t_seam() -> IO(Unit):
  do IO<Unit>:
    # :55-56 -- the version THIS host compiles with, diffed against `platform.mac_ver()`.
    urow("mt_macos_major", MACOS_MAJOR())
    srow("mt_ver_host", metal_version(MACOS_MAJOR()))
    # :62-63 -- a REAL kernel's two blob lengths and the request they make.
    urow("mt_psrc238", csrc_padded(238))
    urow("mt_ppar145", cparams_padded(145))
    urow("mt_req238", creq_len(238, 145))
    # :50 -- the header the REAL reply carried, and the MTLB it therefore starts at.
    urow("mt_liboff_host", mtl_lib.off(REPLY_HDR(), REPLY_WARN()))
    urow("mt_reply_hdr", REPLY_HDR())
    urow("mt_reply_warn", REPLY_WARN())
    # THE TWO BLOBS. `mt_reply_lead` is the UNSLICED reply's first word and
    # `mt_mtlb` is the SLICED one's; `mt_lead_is_mtlb` says they are NOT the same,
    # which is the only reason the distinction can survive an edit.
    urow("mt_reply_lead", REPLY_LEAD())
    row("mt_reply_is_mtlb", U32.is_eq(REPLY_LEAD(), MTLB_MAGIC()))
    # :47 -- the callback's own test, against the codes this host really returned.
    urow("mt_err_ok", CB_ERR_OK())
    urow("mt_err_compile", CB_ERR_COMPILE())
    row("mt_cb_ok0", cc_error_ok(CB_ERR_OK()))
    row("mt_cb_bad2", cc_error_ok(CB_ERR_COMPILE()))
    # THE TWO ARMS AS TRACES. One compiles and keeps both calls; the other calls and
    # then refuses, and the call COUNT is the row that says the refusal is a
    # TRUNCATION and not a skip -- which is the whole template of this file.
    +g : Tr <- IO.pure(Tr, ccompile.of(CB_ERR_OK(), MTLB_MAGIC(), ENDT_MAGIC(), 402, Tr.of()))
    urow("mt_cb_ok_calls", seen(g))
    row("mt_cb_ok_live", Bool.not(Tr.refused(g)))
    +h : Tr <- IO.pure(Tr, ccompile.of(CB_ERR_COMPILE(), MTLB_MAGIC(), ENDT_MAGIC(), 402, Tr.of()))
    urow("mt_cb_bad_calls", seen(h))
    row("mt_cb_bad_refused", Tr.refused(h))
    # M49's FIXTURE. Dropping the ENDT conjunct of :70 moved NOTHING, because every
    # other fixture feeds `ok` a good pair -- and `MTLB_MAGIC` and `ENDT_MAGIC` are
    # constants, so the check was only ever asked a question it had already been
    # told the answer to. `mt_cb_badtail` is the negative half and without it the
    # check is untested. (A `0` is a request for a fixture, not a coverage claim.)
    +i : Tr <- IO.pure(Tr, ccompile.of(CB_ERR_OK(), MTLB_MAGIC(), 0, 402, Tr.of()))
    row("mt_cb_badtail", Tr.refused(i))
    +j : Tr <- IO.pure(Tr, ccompile.of(CB_ERR_OK(), 0, ENDT_MAGIC(), 402, Tr.of()))
    row("mt_cb_badhead", Tr.refused(j))

# --- 2c: THE THREE DEFS THAT WERE WRITTEN AND NEVER CALLED --------------------
# `str_list_eq`, `icb_keep` and `sync_starts` were all live in the file's own words
# -- one of them carries a comment saying a row checks it -- and NOTHING reached
# them, which is what `.agents/slop/dead-defs.py` found. Wiring them costs three
# rows and buys three things no other row has: the WHOLE selector table in one
# comparison, `:267`'s weak-dict count, and the profile SCAN rather than a single
# scan step.
def t_wired() -> IO(Unit):
  do IO<Unit>:
    # :85-86, both tables, element for element -- the rows `.index` cannot see,
    # because a reordered pair of selectors with the same COUNT keeps every index.
    row("mt_tbl_handles", str_list_eq(handles(), ["queue", "event", "fence", "resources", "count"]))
    row("mt_tbl_sels", str_list_eq(selectors(), ["commandBuffer", "computeCommandEncoder", "waitForFence:",
                                                 "updateFence:", "encodeSignalEvent:value:", "endEncoding",
                                                 "commit", "useResources:count:usage:",
                                                 "executeCommandsInBuffer:withRange:",
                                                 "concurrentDispatchThreadgroups:threadsPerThreadgroup:",
                                                 "setComputePipelineState:",
                                                 "dispatchThreadgroups:threadsPerThreadgroup:",
                                                 "signaledValue"]))
    # M54's FIXTURE, and it is the one that matters: the two rows above compare the
    # table against a COPY OF THE TABLE INSIDE THIS FILE, so their lengths always
    # agree and the ELEMENT comparison was never exercised -- deleting `str_eq.go`
    # from `str_list_eq` moved nothing. `mt_tbl_reorder` and `mt_tbl_wrong` are the
    # two negative halves: one swaps two names and one changes one, and a length
    # check alone sees NEITHER.
    row("mt_tbl_reorder", Bool.not(str_list_eq(selectors(), ["computeCommandEncoder", "commandBuffer", "waitForFence:",
                                                            "updateFence:", "encodeSignalEvent:value:", "endEncoding",
                                                            "commit", "useResources:count:usage:",
                                                            "executeCommandsInBuffer:withRange:",
                                                            "concurrentDispatchThreadgroups:threadsPerThreadgroup:",
                                                            "setComputePipelineState:",
                                                            "dispatchThreadgroups:threadsPerThreadgroup:",
                                                            "signaledValue"])))
    row("mt_tbl_wrong", Bool.not(str_list_eq(handles(), ["queue", "event", "fence", "count", "resources"])))
    # :267, `self.icbs[buf] = (icb, commands)` -- a WeakKeyDictionary, so its only
    # observable is how many entries are alive. Zero, then one.
    urow("mt_nics0", Dev.nics(fx_dev()))
    urow("mt_nics1", Dev.nics(icb_keep(fx_dev())))
    # :276-281, THE SCAN. `filled` is the END SLOT, so `True` means "already
    # collected" and does NOTHING, and `False` is the arm that waits and reads the
    # two timestamps. Three calls per entry, so 13 words = two entries of
    # `range(5, 13, 4)` = six calls. The polarity is worth a comment because the
    # obvious reading of "filled" is the opposite one and it silently halves the
    # count from 6 to 0.
    lrow("mt_sync_scan_idx", sync_starts(13))
    # M51's FIXTURE. `mt_sync_scan_idx` reads `sync_starts` DIRECTLY, so a scan that
    # walked one entry too few moved nothing -- the row never went through the def
    # under repair, and `sync_starts` is unchanged by such a bug.
    # The scan's COUNT through `dev.sync_scan` itself, at two sizes, because
    # `sync_starts` returns the same list for 13 and for 17 -- `sync_count` decides
    # the length and `sync_starts` only walks it -- so a scan that lost its last
    # entry is a COUNT bug and needs two sizes to be visible at all.
    urow("mt_sync_scan_calls21", seen(dev.sync_scan(21, False{}, Tr.of())))
    lrow("mt_sync_scan_idx21", sync_starts(21))
    +u : Tr <- IO.pure(Tr, dev.sync_scan(13, False{}, Tr.of()))
    urow("mt_sync_scan_calls", seen(u))
    row("mt_sync_scan_refused", Tr.refused(u))
    +w : Tr <- IO.pure(Tr, dev.sync_scan(13, True{}, Tr.of()))
    urow("mt_sync_noscan_calls", seen(w))
    # `size` below SYNC_START is an EMPTY range in Python, not a negative count.
    lrow("mt_sync_scan_small", sync_starts(4))
    urow("mt_sync_scan_small_calls", seen(dev.sync_scan(4, False{}, Tr.of())))

    # :247, the NSString, wired in -- `mt_pipe_order` and `mt_pipe_sels` are the
    # rows that see it and they are in `t_icb`; nothing is repeated here.


# --- 3: the init ORDER and the family table, :196-215 ------------------------
# `mt_init_order` pins the ORDER AND THE IDENTITY of all eight calls, and the
# oracle's `init_*` rows are the same statements read out of the AST.
def init_pat() -> List<&2, Call>:
  [Call{CALL_SYSDEVICE, PLACEHOLDER_IX(), 0},
   Call{CALL_NEWQUEUE, sel_ix("newCommandQueueWithMaxCommandBufferCount"), QUEUE_MAX_CMDS()},
   Call{CALL_MSGSEND, sel_ix("new"), 0},
   Call{CALL_NEWRESID, sel_ix("newResidencySetWithDescriptor_error"), 0},
   Call{CALL_ADDRESID, sel_ix("addResidencySet"), 0},
   Call{CALL_NEWEVENT, sel_ix("newSharedEvent"), 0},
   Call{CALL_NEWFENCE, sel_ix("newFence"), 0},
   Call{CALL_FAMILY, sel_ix("supportsFamily"), METAL_APPLE()}]

def t_init() -> IO(Unit):
  do IO<Unit>:
    +d : Dev <- IO.pure(Dev, fx_dev())
    +t : Tr <- IO.pure(Tr, Dev.tr(d))
    row("mt_init_order", seq(t, init_pat()))
    urow("mt_init_calls", seen(t))
    lrow("mt_init_sels", kinds(CALL_MSGSEND(), t))
    urow("mt_init_new_n", ncalls(CALL_MSGSEND(), t))
    lrow("mt_init_sels_only", sels_of(t))
    srow("mt_init_arch", Dev.arch(d))
    urow("mt_init_fam", Dev.fam(d))
    row("mt_init_resid", Dev.resid_ok(d))
    lrow("mt_init_queueargs", kinds(CALL_NEWQUEUE(), t))
    +d0 : Dev <- IO.pure(Dev, fx_dev0())
    row("mt_init_noresid", Bool.not(Dev.resid_ok(d0)))
    urow("mt_init_noresid_calls", seen(Dev.tr(d0)))
    lrow("mt_init_noresid_sels", kinds(CALL_MSGSEND(), Dev.tr(d0)))
    # the ONE refusal in __init__
    +dq : Dev <- IO.pure(Dev, dev.init(METAL_APPLE(), METAL_MAC(), False{}, False{}))
    row("mt_init_refused", Tr.refused(Dev.tr(dq)))
    urow("mt_init_refused_calls", seen(Dev.tr(dq)))
    srow("mt_msg_noqueue", msg_noqueue())
    # the family table, BOTH DIRECTIONS
    urow("mt_fam_n", U32.from_nat(List.length(&2, D.AEnt, families())))
    urow("mt_fam_apple8", check_family([1008], "Apple"))
    urow("mt_fam_apple8_9", check_family([1008, 1009], "Apple"))
    urow("mt_fam_apple9", check_family([1008, 1009], "Apple"))
    urow("mt_fam_apple_first", check_family([1001, 1002, 1003], "Apple"))
    urow("mt_fam_mac", check_family([2001, 2002], "Mac"))
    urow("mt_fam_mac_catalyst", check_family([2001, 2002, 4001, 4002], "Mac"))
    urow("mt_fam_none", check_family([2001, 2002], "Apple"))
    urow("mt_fam_apple9_family", check_family([1009], "Apple"))
    srow("mt_fam_nm", fam_nm(1008))
    srow("mt_fam_nm_metal", fam_nm(5002))
    srow("mt_fam_nm_missing", fam_nm(4242))
    srow("mt_arch_slice", arch_of(1008))
    srow("mt_arch_slice_mac", arch_of(2002))
    srow("mt_arch_slice_none", arch_of(0))
    urow("mt_arch_or_apple", dev.arch.apple(METAL_MAC(), METAL_APPLE()))
    urow("mt_arch_or_fallback", dev.arch.apple(METAL_MAC(), 0))
    urow("mt_arch_or_none", dev.arch.apple(0, 0))
    # the apple9 DISJUNCTION, and only the last two rows of the family can see
    # an `or` read as an `and`.
    row("mt_apple9_apple8", dev.apple9("Apple8"))
    row("mt_apple9_apple9", dev.apple9("Apple9"))
    row("mt_apple9_apple10", dev.apple9("Apple10"))
    row("mt_apple9_mac2", dev.apple9("Mac2"))
    row("mt_apple9_metal4", dev.apple9("Metal4"))
    urow("mt_apple_num_apple8", dev.apple_num("Apple8"))
    urow("mt_apple_num_apple9", dev.apple_num("Apple9"))
    urow("mt_apple_num_common", dev.apple_num("Common1"))
    urow("mt_apple_num_mac", dev.apple_num("Mac2"))

# --- 4: THE PER-CALL TRACE FOR A FIXED PIPELINE, :127-168 --------------------
# THIS IS THE PORT. The `run` sequence below is `mt_oracle.py`'s `run_order` row,
# which is an `ast` walk of ops_metal.py:138-163 -- so the expectation is the
# source's own statement order and a dropped or moved line moves a row.
#
# The fixture is fx_dev0 (NO residency set, so :143 runs) on Apple8 (so
# :146-149 run), with no stamps (so :157 does not) and `last` (so :162 does), and
# TWO commands sharing ONE pipeline. So the trace is the thirteen statements of
# `run` -- TWELVE msgSends and two UOp stores -- plus the ONE
# `setComputePipelineState:` that :148 emits per pipe.
# THE ELEVEN msgSENDS, with EVERY argument spelled, and the four that are not
# zero are the four the source computes: the FENCE handle (:141 and :152),
# `1 + n + i` (:148), `zero` (:149) and `count` (:151). Spelling them is what
# makes the row an IDENTITY check and not an order check -- the first version of
# this pattern had zeros in all four and printed False, which is a row that says
# nothing about the order and a bad way to learn that.
#
# THE FENCE HANDLE IS NOT ZERO and that is not an accident of the fixture: it is
# minted by the DEVICE's trace during `__init__` and the QUEUE's trace is a
# different one, which is faithful -- `MetalQueue.h` starts empty in Python too.
# So the handle is a number from another arena and the row spells it rather than
# pretending the two traces share a counter.
def run_pat(+d: Dev, +n: U32) -> List<&2, Call>:
  [Call{CALL_MSGSEND, SEL_COMMANDBUFFER(), 0},
   Call{CALL_MSGSEND, SEL_COMPUTEENCODER(), 0},
   Call{CALL_MSGSEND, SEL_WAITFENCE(), Dev.fence(d)},
   Call{CALL_MSGSEND, SEL_USERESOURCES(), Dev.nres(d)},
   Call{CALL_MSGSEND, SEL_SETPIPESTATE(), hdr_pipe(n, 0)},
   Call{CALL_MSGSEND, SEL_DISPATCH(), fx_zero()},
   Call{CALL_MSGSEND, SEL_EXECUTECMDS(), n},
   Call{CALL_MSGSEND, SEL_UPDATEFENCE(), Dev.fence(d)},
   Call{CALL_MSGSEND, SEL_ENDENCODING(), 0},
   Call{CALL_MSGSEND, SEL_SIGNALEVENT(), 0},
   Call{CALL_MSGSEND, SEL_COMMIT(), 0}]

def t_run() -> IO(Unit):
  do IO<Unit>:
    +d : Dev <- IO.pure(Dev, fx_dev0())
    +t : Tr <- IO.pure(Tr, q.submit(d, fx_q(0)))
    # THE MATCHER PINS ITSELF FIRST, because every order row below depends on it
    # being a real SUBSEQUENCE test. `Tr.has`'s fuel is the TRACE length and the
    # answer is `at == patlen`; get either half wrong and it answers True to
    # everything, which is the bug the WebGPU template's M23 documents.
    row("mt_has_reverse", Bool.not(seq(t, [Call{CALL_MSGSEND, SEL_COMMIT(), 0},
      Call{CALL_MSGSEND, SEL_COMMANDBUFFER(), 0}])))
    row("mt_has_absent", Bool.not(seq(t, [Call{CALL_MSGSEND, 99, 0}])))
    row("mt_has_absent3", Bool.not(seq(t, [Call{CALL_MSGSEND, SEL_DISPATCH(), 999}])))
    # A pattern that occurs ONLY LATE in the trace. The good matcher scans the
    # WHOLE trace; mutation M16 sets the fuel to the PATTERN length, so a
    # ONE-entry pattern would only ever look at entry 0. These three rows are
    # what makes M16 move more than one row, and they are the fixture the
    # WebGPU template's M23 says a subsequence matcher needs.
    +tl : Tr <- IO.pure(Tr, q.submit(fx_dev(), q.timestamp(fx_q(0))))
    row("mt_has_late", seq(tl, [Call{CALL_MSGSEND, SEL_COMMIT(), 0}]))
    row("mt_has_late2", seq(tl, [Call{CALL_STORE, slot_at(SLOT_PENDING(), 1), 0}]))
    row("mt_has_late_absent", Bool.not(seq(tl, [Call{CALL_MSGSEND, SEL_ENDENCODING(), 1}])))
    row("mt_run_order", seq(t, run_pat(d, 2)))
    urow("mt_run_calls", seen(t))
    lrow("mt_run_sels", sels_of(t))
    urow("mt_run_msgsend_n", ncalls(CALL_MSGSEND(), t))
    urow("mt_run_setpipe_n", Tr.count_s(SEL_SETPIPESTATE(), Tr.calls(t)))
    lrow("mt_run_exec_args", kinds(CALL_MSGSEND(), t))
    lrow("mt_run_disp_args", kinds(CALL_MSGSEND(), t))
    lrow("mt_run_setpipe_args", kinds(CALL_MSGSEND(), t))
    lrow("mt_run_useres_args", kinds(CALL_MSGSEND(), t))
    # WITH a residency set :143 is skipped -- THE MUTUAL EXCLUSION, and the
    # `nores` guard is :142's `self.dev.residency.value is None`.
    +tr : Tr <- IO.pure(Tr, q.submit(fx_dev(), fx_q(0)))
    urow("mt_run_res_calls", seen(tr))
    row("mt_run_res_nouseres", Bool.not(seq(tr, [Call{CALL_MSGSEND, SEL_USERESOURCES(), 0}])))
    # arch "Apple10": startswith("Apple") is true and 10 < 9 is false, so the
    # `or` is FALSE and BOTH :148 and :149 vanish. THE DISJUNCTION'S FIXTURE.
    +ta : Tr <- IO.pure(Tr, q.submit(dev.init(METAL_APPLE(), METAL_MAC(), True{}, False{}), fx_q(0)))
    urow("mt_run_a10_calls", seen(ta))
    row("mt_run_a10_nopipe", Bool.not(seq(ta, [Call{CALL_MSGSEND, SEL_SETPIPESTATE(), 0}])))
    row("mt_run_a10_nodisp", Bool.not(seq(ta, [Call{CALL_MSGSEND, SEL_DISPATCH(), 0}])))
    # SYMBOLIC sizes: :135-136 emits one
    # concurrentDispatchThreadgroups:threadsPerThreadgroup: PER entry of
    # `self.sizes`, BEFORE the `run`, and `exec` put ONE entry there.
    +ts : Tr <- IO.pure(Tr, q.submit(d, fx_q(ALL_SYMS())))
    # THE `at` IS 280 AND NOT ANY OF THE THREE NUMBERS A READER GUESSES. It is
    # :118's `round_up(self.nbytes, 8)` taken AFTER the SECOND command's argument
    # block, which is at 256 and twenty bytes long, so it is `round_up(276, 8)`.
    # The first two versions of this row wrote 0 and 24 and both printed False,
    # and both were the ROW being wrong about the arithmetic and not about the
    # order -- which is why `mt_run_sym_args` below prints the WHOLE argument
    # list and this row says only that the msgSend comes first.
    row("mt_run_sym_first", seq(ts, [Call{CALL_MSGSEND, SEL_CONCDISPATCH(), 280},
      Call{CALL_MSGSEND, SEL_COMMANDBUFFER(), 0}]))
    urow("mt_run_sym_conc", ncalls(CALL_MSGSEND(), ts))
    lrow("mt_run_sym_args", kinds(CALL_MSGSEND(), ts))
    urow("mt_run_sym_n", U32.from_nat(List.length(&2, Sz, Q.sizes(fx_q(ALL_SYMS())))))
    urow("mt_run_nosym_n", U32.from_nat(List.length(&2, Sz, Q.sizes(fx_q(0)))))
    # TWO `run`s when there are stamps and n > 1: :167 then :168, and the first
    # is NOT `last`, so `encodeSignalEvent:value:` appears ONCE and `commit`
    # twice.
    +t2 : Tr <- IO.pure(Tr, q.submit(d, q.timestamp(fx_q(0))))
    urow("mt_run_two_calls", seen(t2))
    urow("mt_run_two_signal", Tr.count_s(SEL_SIGNALEVENT(), Tr.calls(t2)))
    urow("mt_run_two_commit", Tr.count_s(SEL_COMMIT(), Tr.calls(t2)))
    urow("mt_run_two_stores", ncalls(CALL_STORE(), t2))
    lrow("mt_run_two_storevals", stores(t2))
    lrow("mt_run_two_storeslots", store_slots(t2))
    # ONE `run` when there are stamps and n == 1: :168 alone, with first = 0.
    +t3 : Tr <- IO.pure(Tr, q.submit(d, q.timestamp(one_cmd())))
    urow("mt_run_one_commit", Tr.count_s(SEL_COMMIT(), Tr.calls(t3)))
    urow("mt_run_one_signal", Tr.count_s(SEL_SIGNALEVENT(), Tr.calls(t3)))
    lrow("mt_run_one_storevals", stores(t3))
    lrow("mt_run_one_storeslots", store_slots(t3))
    lrow("mt_run_one_exec", kinds(CALL_MSGSEND(), t3))
    # :123 `wait` IS A NO-OP -- the comment says "the fence orders the queue".
    row("mt_wait_noop", U32.is_eq(seen(q.wait(fx_t(d))), 0))

# --- 5: the ICB geometry, :112-121, :128-132, :266 ---------------------------
def t_geometry() -> IO(Unit):
  do IO<Unit>:
    # :111 -- every global is a `getaddr` and so is EIGHT bytes, and every var is
    # its own width. `mt_items_*` is the claim that the two halves DIFFER.
    lrow("mt_items_2_1", q.items(2n, [4]))
    lrow("mt_items_0_0", q.items(0n, []))
    lrow("mt_items_3_2", q.items(3n, [4, 2]))
    # `layout_args`, MEASURED through tinygrad's own `layout_args`:
    #   [u64, i32] at 0 -> [0:8, 8:4];  [u64, f16, f16] at 256 -> 256, 264, 266
    lrow("mt_layout_2buf1var", q.flat(q.layout(0, q.items(2n, [4])), Nil{}))
    lrow("mt_layout_3buf", q.flat(q.layout(0, q.items(3n, [])), Nil{}))
    lrow("mt_layout_at256", q.flat(q.layout(256, q.items(1n, [2, 2])), Nil{}))
    lrow("mt_layout_1buf", q.flat(q.layout(0, q.items(1n, [])), Nil{}))
    # :113's `max(..., default=off + 8)` -- the `default` is the whole point and
    # `mt_end_empty` is the only row that reaches it.
    urow("mt_end_2buf1var", q.end(0, q.layout(0, q.items(2n, [4]))))
    urow("mt_end_3buf", q.end(0, q.layout(0, q.items(3n, []))))
    urow("mt_end_1buf", q.end(0, q.layout(0, q.items(1n, []))))
    urow("mt_end_empty", q.end(256, Nil{}))
    urow("mt_end_empty0", q.end(0, Nil{}))
    # the two alignments, 256 and 8, and they are NOT the same number
    urow("mt_off256_1", q.exec.off(1))
    urow("mt_off256_256", q.exec.off(256))
    urow("mt_off256_257", q.exec.off(257))
    urow("mt_at8_1", q.exec.at(1))
    urow("mt_at8_9", q.exec.at(9))
    urow("mt_zero", q.submit.zero(1))
    urow("mt_zero9", q.submit.zero(9))
    # :128-132 -- the ICB sizes, and they must AGREE. `FX_ZERO` is the fixture's
    # OWN `zero`, not a literal: the first version of these five rows hardcoded
    # 256, which is the FIRST command's `off`, and CPython's `zero` is 280 -- so
    # five rows were wrong by 24 and the oracle caught all five at once. ONE
    # `fx_zero` def is what makes the family agree by construction.
    urow("mt_hdr_word", hdr_word(fx_zero()))
    urow("mt_header", icb_header(fx_zero()))
    urow("mt_header_agree", U32.mul(hdr_word(fx_zero()), ADDR_SIZE()))
    urow("mt_icb_size", icb_size(icb_header(fx_zero()), 2, 1))
    urow("mt_icb_size0", icb_size(0, 0, 0))
    urow("mt_icb_sizes_agree", icb_size(icb_header(fx_zero()), 2, 1))
    lrow("mt_zero_rows", [zero_row(0, fx_zero()), zero_row(1, fx_zero()),
                          zero_row(2, fx_zero())])
    # :266's header layout: the ICB at word 0, the commands at 1.., the pipes at
    # 1+n..  -- the three indices :151, :136 and :148 all read.
    urow("mt_hdr_icb", hdr_icb())
    urow("mt_hdr_cmd0", hdr_cmd(0))
    urow("mt_hdr_cmd1", hdr_cmd(1))
    urow("mt_hdr_pipe0", hdr_pipe(2, 0))
    urow("mt_hdr_pipe1", hdr_pipe(2, 1))
    # :121's tuple, and :117's mask
    lrow("mt_dims_const", q.dims(0, DIMS()))
    lrow("mt_dims_all", q.dims(ALL_SYMS(), DIMS()))
    lrow("mt_dims_mixed", q.dims(8, DIMS()))
    lrow("mt_dims_one", q.dims(1, DIMS()))
    row("mt_sym_no", Bool.not(q.any_sym(0)))
    row("mt_sym_yes", q.any_sym(ALL_SYMS()))
    row("mt_sym_bit", q.sym_at(8, 3))
    row("mt_sym_nobit", q.sym_at(8, 4))
    # :264's two MTLSizes, and :262's product
    urow("mt_size_g0", MtlSize.w(mtl_size.g(DIMS())))
    urow("mt_size_g2", MtlSize.d(mtl_size.g(DIMS())))
    urow("mt_size_l0", MtlSize.w(mtl_size.l(DIMS())))
    urow("mt_size_l1", MtlSize.h(mtl_size.l(DIMS())))
    urow("mt_size_l2", MtlSize.d(mtl_size.l(DIMS())))
    urow("mt_prod_l", q.prod_l(DIMS()))
    urow("mt_prod_l_1", q.prod_l([8, 1, 1, 1, 1, 1]))
    row("mt_local_eq", local_ok(1024, 1024))
    row("mt_local_over", local_ok(1025, 1024))
    row("mt_local_under", local_ok(1023, 1024))
    # `exec`, end to end, for the fixture: nbytes after both commands
    urow("mt_exec_nbytes", Q.nbytes(fx_q(ALL_SYMS())))
    urow("mt_exec_nbytes_c", Q.nbytes(fx_q(0)))
    urow("mt_exec_ncmds", Q.ncmds(fx_q(0)))
    urow("mt_exec_nrows", U32.from_nat(List.length(&2, Row, Q.rows(fx_q(0)))))
    urow("mt_exec_nrows_s", U32.from_nat(List.length(&2, Row, Q.rows(fx_q(ALL_SYMS())))))
    # the (lib, name) dedup: SAME name + DIFFERENT lib is TWO pipelines. The
    # JOINT condition is the claim, and these three rows are the only fixtures
    # that can see a dedup on either half alone.
    urow("mt_pipe_same", Q.npipes(fx_q(0)))
    urow("mt_pipe_difflib", Q.npipes(q2_pipe(1, 2, "kern")))
    urow("mt_pipe_diffname", Q.npipes(q2_pipe(1, 1, "other")))
    urow("mt_pipe_of_0", Seen.got(q.pipe_of(1, "kern", Q.cmds(fx_q(0)))))
    urow("mt_pipe_of_new", Seen.got(q.pipe_of(9, "nope", Q.cmds(fx_q(0)))))
    row("mt_pipe_of_new_hit", Seen.hit(q.pipe_of(9, "nope", Q.cmds(fx_q(0)))))

# --- 6: the allocator, the residency table and `mark_resident`, :174-237 -----
def t_alloc() -> IO(Unit):
  do IO<Unit>:
    # :175-179, the ORDER of the three calls: the buffer, then the ADDRESS, then
    # the CONTENTS -- because Python evaluates the BufferStorage's three
    # arguments left to right and `gpuAddress()` is the first of them.
    +a : Made <- IO.pure(Made, alloc.of(D.bar_empty(), MTL_DEV(), 64, False{}, True{}, fx_dev0()))
    # the binder is `t1` and not `at`, because `x.at` is Bend's namespace
    # selector and a `do`-block binder named `at` reads as one.
    +t1 : Tr <- IO.pure(Tr, Made.t(a))
    row("mt_alloc_order", seq(t1, [Call{CALL_NEWBUFFER, sel_ix("newBufferWithLength_options"), 64},
      Call{CALL_GPUADDR, sel_ix("gpuAddress"), 0},
      Call{CALL_CONTENTS, sel_ix("contents"), 0}]))
    urow("mt_alloc_nbytes", Made.nbytes(a))
    lrow("mt_alloc_size_arg", kinds(CALL_NEWBUFFER(), t1))
    # the EXTERNAL arm, :175's `MTLBuffer(options.external_ptr)`
    +e : Made <- IO.pure(Made, alloc.of(D.bar_empty(), MTL_DEV(), 64, True{}, True{}, fx_dev0()))
    lrow("mt_alloc_ext_kinds", kinds(CALL_NEWBUFFER(), Made.t(e)))
    # the OOM refusal and its MESSAGE
    srow("mt_oom_64", msg_oom(64))
    srow("mt_oom_0", msg_oom(0))
    +o : Made <- IO.pure(Made, alloc.of(D.bar_empty(), MTL_DEV(), 64, False{}, False{}, fx_dev0()))
    row("mt_alloc_refused", Tr.refused(Made.t(o)))
    urow("mt_alloc_refused_calls", seen(Made.t(o)))
    # :185 `_offset` IS `device.py:330`'s, consumed rather than re-derived
    urow("mt_offset", alloc_offset(4096, 16))
    urow("mt_offset0", alloc_offset(4096, 0))
    # `D.Bar` really is the Buffer: the ICB's `nolru` says it is never recycled
    row("mt_nolru", Bool.not(D.recycled(True{}, True{}, icb_spec())))
    row("mt_lru_alloc", D.recycled(True{}, True{}, D.spec()))
    urow("mt_icb_binds", icb_binds())
    urow("mt_icb_ix", KERNEL_BUF_IX())
    urow("mt_icb_max0", icb_max(0))
    urow("mt_icb_max2", icb_max(2))
    # `mark_resident`, the TWO PATHS. With a residency set: TWO calls and
    # `resources` UNCHANGED. Without: NO residency call and TWO stores.
    +mr : Dev <- IO.pure(Dev, dev.mark_resident(7, True{}, fx_dev()))
    row("mt_resid_excl", u32_list_eq(kinds(CALL_RS_ADD(), Dev.tr(mr)), [7]))
    urow("mt_resid_excl_commits", ncalls(CALL_RS_COMMIT(), Dev.tr(mr)))
    urow("mt_resid_excl_stores", ncalls(CALL_STORE(), Dev.tr(mr)))
    urow("mt_resid_excl_nres", Dev.nres(mr))
    urow("mt_resid_excl_len", U32.from_nat(List.length(&2, U32, Dev.res(mr))))
    lrow("mt_resid_add_sels", sels_of(Dev.tr(mr)))
    +md : Dev <- IO.pure(Dev, dev.mark_resident(7, False{}, fx_dev()))
    lrow("mt_resid_del_sels", sels_of(Dev.tr(md)))
    # without a residency set, and with the sels table already made
    +m0 : Dev <- IO.pure(Dev, dev.mark_resident(7, True{}, dev.sels_made.at(fx_dev0())))
    lrow("mt_resid_stores", kinds(CALL_STORE(), Dev.tr(m0)))
    lrow("mt_resid_store_slots", store_slots(Dev.tr(m0)))
    urow("mt_resid_made", U32.from_nat(List.length(&2, U32, Dev.res(m0))))
    urow("mt_resid_nres0", Dev.nres(m0))
    # and WITHOUT the sels table, which is the `cached_property` guard
    +m1 : Dev <- IO.pure(Dev, dev.mark_resident(7, True{}, fx_dev0()))
    urow("mt_resid_nomade", ncalls(CALL_STORE(), Dev.tr(m1)))
    urow("mt_resid_nomade_nres", Dev.nres(m1))
    # :224's THIRTEEN `sel_registerName` calls, in the SELECTORS order
    +sm : Made <- IO.pure(Made, dev.sels(D.bar_empty(), MTL_DEV()))
    urow("mt_sels_sels", ncalls(CALL_SELREG(), Made.t(sm)))
    lrow("mt_sels_sel_args", kinds(CALL_SELREG(), Made.t(sm)))
    urow("mt_sels_n", Made.nbytes(sm))
    row("mt_sels_made", Dev.sels_made(fx_dev0()))
    row("mt_sels_unmade", Bool.not(Dev.sels_made(fx_dev0())))
    # the `cached_property`'s MEMO, set by `dev.sels_made.at` -- the positive half,
    # and without it the flag has a `False` row and no `True` one, which is a
    # conjunct with a fixture on one side only.
    row("mt_sels_made_set", Dev.sels_made(dev.sels_made.at(fx_dev0())))
    urow("mt_table_one0", dev.table_len(0))
    urow("mt_table_one1", dev.table_len(1))
    urow("mt_table_five", dev.table_len(5))
    # :239's slots, and :218's `max_numel() > 4`
    urow("mt_slots_bytes", new_slots_bytes(8))
    urow("mt_slots_bytes0", new_slots_bytes(0))
    row("mt_slots_thresh4", dev.wants_slots(4))
    row("mt_slots_thresh5", dev.wants_slots(5))
    urow("mt_slots_str", SLOTS_STRIDE())
    # :101 `mtl_poll` and :273 `_wait_signal`
    +p : Tr <- IO.pure(Tr, mtl_poll(fx_dev0()))
    lrow("mt_poll_sels", sels_of(p))
    urow("mt_poll_calls", seen(p))
    lrow("mt_waitsig_t", kinds(CALL_WAITSIG(), dev.waitsig(5000, Tr.of())))
    srow("mt_msg_timeout", msg_timeout())
    row("mt_wait_ok", Bool.not(Tr.refused(wait_ok(True{}, Tr.of()))))
    row("mt_wait_bad", Tr.refused(wait_ok(False{}, Tr.of())))
    srow("mt_msg_badlib", msg_badlib())
    srow("mt_msg_noicb", msg_noicb())
    srow("mt_msg_local", msg_local(4, 1, 1, 1024))
    srow("mt_msg_local_1", msg_local(1, 1, 1, 256))

# --- 7: the pipeline and the ICB, :243-268 -----------------------------------
# :247 is the ORDER row: Python evaluates `setComputeFunction`'s ARGUMENT, so
# `to_ns_str` happens FIRST of all, then `newFunctionWithName`, and only then
# `setComputeFunction`. The NSString is the THIRD call and it was missing from this
# pattern until `cns_string` was wired -- which is why `mt_pipe_order` is the row
# that would have caught it: `seq` compares the WHOLE list, so a missing call in
# the middle is a length mismatch and not a mismatch somebody has to notice.
def pipe_pat() -> List<&2, Call>:
  [Call{CALL_NEWLIB, sel_ix("newLibraryWithData_error"), 0},
   Call{CALL_MSGSEND, sel_ix("new"), 0},
   Call{CALL_MSGSEND, sel_ix("stringWithUTF8String:"), 0},
   Call{CALL_NEWFUNC, sel_ix("newFunctionWithName"), 0},
   Call{CALL_SETCOMPFUNC, sel_ix("setComputeFunction"), 0},
   Call{CALL_SETICB, sel_ix("setSupportIndirectCommandBuffers"), 0},
   Call{CALL_NEWPIPE, sel_ix("newComputePipelineStateWithDescriptor_options_reflection_error"), 0}]

def t_icb() -> IO(Unit):
  do IO<Unit>:
    +p : Tr <- IO.pure(Tr, dev.pipeline(True{}, True{}, Tr.of()))
    row("mt_pipe_order", seq(p, pipe_pat()))
    urow("mt_pipe_calls", seen(p))
    lrow("mt_pipe_sels", sels_of(p))
    row("mt_pipe_ok", Bool.not(Tr.refused(p)))
    +p1 : Tr <- IO.pure(Tr, dev.pipeline(False{}, True{}, Tr.of()))
    row("mt_pipe_librefuse", Tr.refused(p1))
    urow("mt_pipe_librefuse_calls", seen(p1))
    +p2 : Tr <- IO.pure(Tr, dev.pipeline(True{}, False{}, Tr.of()))
    row("mt_pipe_typerefuse", Tr.refused(p2))
    # :259's TWO calls per command, and :261-265's five per command
    +b : Made <- IO.pure(Made, dev.icb(D.bar_empty(), MTL_DEV(), fx_q(0), icb_header(fx_zero()), True{}))
    +bt : Tr <- IO.pure(Tr, Made.t(b))
    urow("mt_icb_calls", seen(bt))
    urow("mt_icb_nbytes", Made.nbytes(b))
    urow("mt_icb_cmds", ncalls(CALL_ICBCMD(), bt))
    urow("mt_icb_retain", ncalls(CALL_RETAIN(), bt))
    urow("mt_icb_bind", ncalls(CALL_SETKBUF(), bt))
    urow("mt_icb_bar", ncalls(CALL_SETBAR(), bt))
    urow("mt_icb_conc", ncalls(CALL_CONCDISP(), bt))
    lrow("mt_icb_kbuf_args", kinds(CALL_SETKBUF(), bt))
    lrow("mt_icb_cmd_args", kinds(CALL_ICBCMD(), bt))
    lrow("mt_icb_store", kinds(CALL_STORE(), bt))
    lrow("mt_icb_storeslots", store_slots(bt))
    # the per-command ORDER, :259 then :261-265. THE COUNTS (`mt_icb_cmds`,
    # `mt_icb_retain`) CANNOT see a swap of the two, which is what mutation M38
    # measured: 0 rows, and this row is the answer to that.
    # :259's list comprehension and :260's `zip` are TWO SEPARATE LOOPS: every
    # command handle is taken FIRST and only then is each one set up. The first
    # version of this pattern interleaved them and printed False, which is a row
    # that was wrong about the source and right about nothing.
    row("mt_icb_cmd_order", seq(bt, [Call{CALL_ICBCMD, sel_ix("indirectComputeCommandAtIndex"), 0},
      Call{CALL_RETAIN, sel_ix("retain"), 0},
      Call{CALL_ICBCMD, sel_ix("indirectComputeCommandAtIndex"), 1},
      Call{CALL_RETAIN, sel_ix("retain"), 1},
      Call{CALL_NEWPIPE, sel_ix("newComputePipelineStateWithDescriptor_options_reflection_error"), 0},
      Call{CALL_SETKBUF, sel_ix("setKernelBuffer_offset_atIndex"), 0},
      Call{CALL_CONCDISP, sel_ix("concurrentDispatchThreadgroups_threadsPerThreadgroup"), 0},
      Call{CALL_SETBAR, sel_ix("setBarrier"), 0},
      Call{CALL_NEWPIPE, sel_ix("newComputePipelineStateWithDescriptor_options_reflection_error"), 0},
      Call{CALL_SETKBUF, sel_ix("setKernelBuffer_offset_atIndex"), 256}]))
    row("mt_icb_ok", Bool.not(Tr.refused(bt)))
    row("mt_icb_order", seq(bt, [Call{CALL_MSGSEND, sel_ix("new"), 0},
      Call{CALL_SETCMDTYPE, sel_ix("setCommandTypes"), CMDTYPE_CONCURRENT()},
      Call{CALL_SETBINDS, sel_ix("setMaxKernelBufferBindCount"), 1},
      Call{CALL_NEWICB, sel_ix("newIndirectCommandBufferWithDescriptor_maxCommandCount_options"), 2},
      Call{CALL_ICBCMD, sel_ix("indirectComputeCommandAtIndex"), 0},
      Call{CALL_RETAIN, sel_ix("retain"), 0},
      Call{CALL_SETKBUF, sel_ix("setKernelBuffer_offset_atIndex"), 0},
      Call{CALL_CONCDISP, sel_ix("concurrentDispatchThreadgroups_threadsPerThreadgroup"), 0},
      Call{CALL_SETBAR, sel_ix("setBarrier"), 0},
      Call{CALL_STORE, U32.div(icb_header(fx_zero()), ADDR_SIZE()), 4}]))
    # the ICB refusal, :258
    +bn : Made <- IO.pure(Made, dev.icb(D.bar_empty(), MTL_DEV(), fx_q(0), icb_header(fx_zero()), False{}))
    row("mt_icb_refuse", Tr.refused(Made.t(bn)))
    urow("mt_icb_refuse_calls", seen(Made.t(bn)))
    # THE PER-COMMAND REFUSAL, :262, and it needs TWO commands to be visible:
    # with one command the truncation is the same length as with none, so the
    # COUNT row and the ORDER row are both blind to it on a one-command fixture.
    +c0 : Tr <- IO.pure(Tr, Made.t(dev.icb.rf(D.bar_empty(), MTL_DEV(), fx_q(0), icb_header(256), True{}, True{}, True{}, True{})))
    +c1 : Tr <- IO.pure(Tr, Made.t(dev.icb.rf(D.bar_empty(), MTL_DEV(), fx_q(0), icb_header(256), True{}, True{}, True{}, False{})))
    row("mt_icb_local_ok", Bool.not(Tr.refused(c0)))
    urow("mt_icb_local_ok_calls", seen(c0))
    row("mt_icb_local_refuse", Tr.refused(c1))
    urow("mt_icb_local_bad_calls", seen(c1))
    # :262 sits BETWEEN the pipeline and the bind, so a command whose local size
    # is too big is left with a pipeline and NO BUFFER. `mt_icb_local_bound` is
    # the negative row and it is the one that says the refusal is in the right
    # PLACE; the positive half only says the pipeline was built.
    row("mt_icb_local_pipeline", seq(c1, [Call{CALL_SETCOMPFUNC, sel_ix("setComputeFunction"), 0},
      Call{CALL_NEWPIPE, sel_ix("newComputePipelineStateWithDescriptor_options_reflection_error"), 0}]))
    row("mt_icb_local_bound", Bool.not(seq(c1, [Call{CALL_SETKBUF, sel_ix("setKernelBuffer_offset_atIndex"), 0}])))
    # the per-command `checked` refusals reach the same place
    +c2 : Tr <- IO.pure(Tr, Made.t(dev.icb.rf(D.bar_empty(), MTL_DEV(), fx_q(0), icb_header(256), True{}, False{}, True{}, True{})))
    row("mt_icb_librefuse", Tr.refused(c2))
    urow("mt_icb_librefuse_calls", seen(c2))
    # the OTHER `checked`, :249's, on the same fixture: the pipeline TYPE refusal
    # and the library refusal are the two sites `checked` wraps, and the second
    # is only reachable if the first passes.
    +c3 : Tr <- IO.pure(Tr, Made.t(dev.icb.rf(D.bar_empty(), MTL_DEV(), fx_q(0), icb_header(fx_zero()), True{}, True{}, False{}, True{})))
    row("mt_icb_typerefuse", Tr.refused(c3))
    urow("mt_icb_typerefuse_calls", seen(c3))

# --- 8: `synchronize`, :270-285 ------------------------------------------------
def t_sync() -> IO(Unit):
  do IO<Unit>:
    urow("mt_sync_start", SYNC_START())
    urow("mt_sync_step", SYNC_STEP())
    urow("mt_sync_end_off", SYNC_END_OFFSET())
    # `range(5, size, 4)` -- the count AND the list, because a wrong step gives
    # the right count for some sizes and the wrong list for all of them.
    urow("mt_sync_n0", sync_count(0))
    urow("mt_sync_n4", sync_count(4))
    urow("mt_sync_n5", sync_count(5))
    urow("mt_sync_n9", sync_count(9))
    urow("mt_sync_n13", sync_count(13))
    urow("mt_sync_n17", sync_count(17))
    urow("mt_sync_n21", sync_count(21))
    lrow("mt_sync_idx17", sync_range.go(3n, SYNC_START(), Nil{}))
    lrow("mt_sync_idx21", sync_range.go(4n, SYNC_START(), Nil{}))
    lrow("mt_sync_idx5", sync_range.go(1n, SYNC_START(), Nil{}))
    urow("mt_sync_end_slot5", sync_end_slot(5))
    urow("mt_sync_end_slot9", sync_end_slot(9))
    # :279-281 -- the guard, and the three calls it makes
    # :279's guard is `slots[start] and not slots[start + 2]` -- the body runs
    # when the command buffer is THERE and the END time is NOT, so `collected`
    # False is the fixture that does the work and `mt_sync_guard_*` is the PAIR
    # that says so.
    +g0 : Tr <- IO.pure(Tr, sync.one(5, False{}, Tr.of()))
    urow("mt_sync_guard_hits", seen(g0))
    lrow("mt_sync_guard_sels", sels_of(g0))
    lrow("mt_sync_guard_args", kinds(CALL_MSGSEND(), g0))
    +g1 : Tr <- IO.pure(Tr, sync.one(9, True{}, Tr.of()))
    urow("mt_sync_guard_miss", seen(g1))
    # :284-285 -- POP THEN PUSH
    +p : Tr <- IO.pure(Tr, dev.pools.at(True{}, Tr.of()))
    row("mt_pool_order", seq(p, [Call{CALL_AUTORELPOP, PLACEHOLDER_IX(), 0},
      Call{CALL_AUTORELPUSH, PLACEHOLDER_IX(), 0}]))
    +p0 : Tr <- IO.pure(Tr, dev.pools.at(False{}, Tr.of()))
    urow("mt_pool_nopop", ncalls(CALL_AUTORELPOP(), p0))
    urow("mt_pool_push", ncalls(CALL_AUTORELPUSH(), p0))

# --- 9: `pm_bufferize`, :216-220 -- THE FIRST-WINS CLAIM ----------------------
# M2 and `device.py:404`'s rule 2 carry the IDENTICAL pattern `UPat(Ops.PARAM,
# name="b")`, and the `+` PREPENDS, so a PARAM whose tag is `("mtl_icb", ...)`
# gets Metal's ICB and not Compiled's program buffer. `mt_pmb_icb` is that row.
def t_pmb() -> IO(Unit):
  do IO<Unit>:
    # M0: a PARAM tagged `mtl_sel`
    +a : PmbRun <- IO.pure(PmbRun, pm_bufferize(D.bar_empty(), pmb_node(True{}, True{}, False{}, False{}, False{}, False{}), 0))
    urow("mt_pmb_sels", PmbRun.got(a))
    urow("mt_pmb_sels_n", D.bar_next(PmbRun.ar(a)))
    # M1: a PARAM tagged `slots` AND named `b`, with max_numel 8
    +b : PmbRun <- IO.pure(PmbRun, pm_bufferize(D.bar_empty(), pmb_node(True{}, False{}, True{}, True{}, False{}, False{}), 8))
    urow("mt_pmb_slots", PmbRun.got(b))
    urow("mt_pmb_slots_n", D.bar_next(PmbRun.ar(b)))
    # M1's GUARD: max_numel 4 is NOT > 4, so M1 answers None and the TAIL --
    # `device.bend`'s own scan -- gives Compiled's program buffer. The answer is
    # 2 EITHER WAY and only the ARENA tells them apart: the tail's rule 1 grows
    # one Buffer too, so this row cannot see the guard, and `mt_pmb_grew` and
    # `mt_pmb_slots` are the pair that can.
    +b4 : PmbRun <- IO.pure(PmbRun, pm_bufferize(D.bar_empty(), pmb_node(True{}, False{}, True{}, True{}, False{}, False{}), 4))
    urow("mt_pmb_slots4", PmbRun.got(b4))
    # M2: a PARAM named `b` whose tag is an `mtl_icb` TUPLE
    +c : PmbRun <- IO.pure(PmbRun, pm_bufferize(D.bar_empty(), pmb_node(True{}, False{}, False{}, True{}, True{}, False{}), 8))
    urow("mt_pmb_icb", PmbRun.got(c))
    urow("mt_pmb_icb_n", D.bar_next(PmbRun.ar(c)))
    # THE TWO-RULES-CLAIM-ONE-NODE FIXTURE: M0's tag and M1's tag are different
    # in Python, so a node that is BOTH takes M0 -- which is what a first-wins
    # fold does and what a LAST-wins fold gets wrong.
    +e : PmbRun <- IO.pure(PmbRun, pm_bufferize(D.bar_empty(), pmb_node(True{}, True{}, True{}, True{}, True{}, False{}), 8))
    urow("mt_pmb_both", PmbRun.got(e))
    urow("mt_pmb_both_n", D.bar_next(PmbRun.ar(e)))
    # NOT a PARAM: no rule's pattern is a tag alone, so the TAIL answers.
    +f : PmbRun <- IO.pure(PmbRun, pm_bufferize(D.bar_empty(), pmb_node(False{}, True{}, True{}, True{}, True{}, True{}), 8))
    urow("mt_pmb_nonparam", PmbRun.got(f))
    urow("mt_pmb_grew", D.bar_next(PmbRun.ar(c)))
    urow("mt_pmb_nogrew", D.bar_next(PmbRun.ar(a)))
    # a cfunc named `b` that is NOT an ICB: M2's `else None`, so the answer is
    # Compiled's rule 2 -- and 2, never 3.
    +g : PmbRun <- IO.pure(PmbRun, pm_bufferize(D.bar_empty(), pmb_node(True{}, False{}, False{}, True{}, False{}, False{}), 8))
    urow("mt_pmb_cfunc", PmbRun.got(g))

# ===========================================================================
# --- 9: THE CONSTANTS THEMSELVES -------------------------------------------
# WHY THIS SECTION EXISTS, and it is the answer to ops_nv.bend, which shipped 606
# green rows with 33 of 219 constants WRONG. Every other section in this file tests
# a GRAPH. A wrong constant in a graph is visible; a wrong constant in a dead
# corner is not, and no amount of rows finds it -- the numbers answer to
# `autogen/metal.py` and to `ops_metal.py`'s literals, and neither was being read.
#
# So every numeric constant def that has a numeric authority gets a row HERE, and
# `.agents/slop/mt_constmap.py --rows` emits the same row names from CPython: the
# authority for `MTLB_MAGIC` is `int.from_bytes(b"MTLB", "little")`, for
# `CMDTYPE_CONCURRENT` it is `getattr(autogen.metal, ...)` , for `HDR_CMD` it is the
# int CPython's `ast` pulls out of `ops_metal.py:136`, and for `DIM_WORDS` it is
# `len(dims)` recorded off a REAL kernel launch through the REAL `MetalQueue.exec`.
# `mt_diff.py` then compares the two. A hand map is the map; CPython is the answer.
#
# ELEVEN of these were DEAD before this section -- declared, correct as far as I can
# tell, and read by NOTHING, so mutating any of them moved zero rows and no
# mutation in the table below could have found them. `mt_c_*` is what makes a
# constant with no reader into a constant that is checked.
# ===========================================================================
def t_const() -> IO(Unit):
  do IO<Unit>:
    urow("mt_c_request_type", REQUEST_TYPE_COMPILE())
    urow("mt_c_queue_max", QUEUE_MAX_CMDS())
    urow("mt_c_usage_rw", USAGE_READ_WRITE())
    urow("mt_c_storagemode", STORAGE_MODE_SHARED())
    urow("mt_c_cmdtype", CMDTYPE_CONCURRENT())
    urow("mt_c_binds", KERNEL_BUF_BINDS())
    urow("mt_c_icbopt", ICB_OPTIONS())
    urow("mt_c_pipeopt", MTL_PIPELINE_OPTION_NONE())
    urow("mt_c_run_count_all", RUN_COUNT_ALL())
    urow("mt_c_sync_start", SYNC_START())
    urow("mt_c_sync_step", SYNC_STEP())
    urow("mt_c_sync_end", SYNC_END_OFFSET())
    urow("mt_c_zero_align", ZERO_ALIGN())
    urow("mt_c_zero_rows", ZERO_ROWS())
    urow("mt_c_icb_pad", ICB_HEADER_PAD())
    urow("mt_c_arg_align", ARG_ALIGN())
    urow("mt_c_sym_bytes", SYM_BYTES())
    urow("mt_c_dim_words", DIM_WORDS())
    urow("mt_c_hdr_skip", HDR_SKIP())
    urow("mt_c_hdr_icb", HDR_ICB())
    urow("mt_c_hdr_cmd", HDR_CMD())
    urow("mt_c_hdr_pipe", HDR_PIPE())
    urow("mt_c_addr_size", ADDR_SIZE())
    urow("mt_c_sel_queue", SEL_QUEUE())
    urow("mt_c_sel_event", SEL_EVENT())
    urow("mt_c_sel_fence", SEL_FENCE())
    urow("mt_c_sel_resources", SEL_RESOURCES())
    urow("mt_c_sel_count", SEL_COUNT())
    urow("mt_c_sel_cmdbuf", SEL_COMMANDBUFFER())
    urow("mt_c_sel_encoder", SEL_COMPUTEENCODER())
    urow("mt_c_sel_waitfence", SEL_WAITFENCE())
    urow("mt_c_sel_updatefence", SEL_UPDATEFENCE())
    urow("mt_c_sel_signalev", SEL_SIGNALEVENT())
    urow("mt_c_sel_endenc", SEL_ENDENCODING())
    urow("mt_c_sel_commit", SEL_COMMIT())
    urow("mt_c_sel_useres", SEL_USERESOURCES())
    urow("mt_c_sel_exec", SEL_EXECUTECMDS())
    urow("mt_c_sel_conc", SEL_CONCDISPATCH())
    urow("mt_c_sel_setpipe", SEL_SETPIPESTATE())
    urow("mt_c_sel_dispatch", SEL_DISPATCH())
    urow("mt_c_sel_sigval", SEL_SIGNALEDVALUE())
    urow("mt_c_msgsend_n", MSGSEND_N())
    urow("mt_c_ret_none", RET_NONE())
    urow("mt_c_ret_voidp", RET_VOIDP())
    urow("mt_c_placeholder", PLACEHOLDER_IX())
    urow("mt_c_cstruct_qq", cstruct_qq())
    urow("mt_c_mtlb", MTLB_MAGIC())
    urow("mt_c_endt", ENDT_MAGIC())
    urow("mt_c_table_min", TABLE_MIN())
    urow("mt_c_sels_len", sels_len())
    urow("mt_c_sels_res", SELS_RES())
    urow("mt_c_sels_cnt", SELS_CNT())
    urow("mt_c_slots_stride", SLOTS_STRIDE())
    urow("mt_c_slots_min", SLOTS_MIN())
    urow("mt_c_apple9", APPLE9())
    urow("mt_c_slot_pending", SLOT_PENDING())
    urow("mt_c_slot_cbuf", SLOT_CBUF())
    urow("mt_c_slot_stride4", SLOT_STRIDE4())
    urow("mt_c_kbuf_ix", KERNEL_BUF_IX())
    urow("mt_c_pmb_none", PMB_NONE())
    urow("mt_c_pmb_sels", PMB_SELS())
    urow("mt_c_pmb_slots", PMB_SLOTS())
    urow("mt_c_pmb_icb", PMB_ICB())
    urow("mt_c_metal_apple", METAL_APPLE())
    urow("mt_c_metal_mac", METAL_MAC())
    urow("mt_c_all_syms", ALL_SYMS())

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_sel()
    b : Unit <- t_compiler()
    c : Unit <- t_init()
    d : Unit <- t_run()
    e : Unit <- t_geometry()
    f : Unit <- t_alloc()
    g : Unit <- t_icb()
    h : Unit <- t_sync()
    i : Unit <- t_pmb()
    j : Unit <- t_const()
    k : Unit <- t_seam()
    l : Unit <- t_wired()
    IO.print("mt-done=1")

# ===========================================================================
# THE MUTATION TABLE. Seventy-two entries over a 432-row gate, and every number
# below is the HARNESS'S OUTPUT, not an estimate:
# `.venv/bin/python .agents/slop/mt_mutate.py <this file>` applies one edit to a
# scratch copy BESIDE THIS FILE, runs the INTERPRETED lane, and diffs the row
# NAMES. It REFUSES a mutation whose `old` text does not match exactly once and
# prints `PATTERN MATCHES Nx -- NOT RUN`, because a table entry whose target line
# was hand-edited would otherwise read as "0 rows moved" and that is exactly the
# reading a blind spot must not be confused with. `.agents/slop/mt-table.py`
# rewrites the table below from the harness's output and REFUSES an id with no
# prose, so a row with an empty last column cannot happen.
#
# The useful column is "rows MOVED", because a mutation that moves nothing
# measures what this gate does NOT see.
#
# ---------------------------------------------------------------------------
# FOUR MOVE NOTHING, and only ONE of them is a control.
#
#  * M14 and M14c add a `+` to a parameter and nothing else. They cannot change
#    behaviour and are run BECAUSE "the edit that adds only a `+`" is the one an
#    LLM would most plausibly make by accident. M14b and M14e are the same two
#    edits made real, and they move 9 and 11 rows.
#  * M41 is the comment-only CONTROL. A table with no row that CANNOT move is a
#    table of coincidences.
#  * M26b is a FINDING ABOUT THE SOURCE. `device.py:404`'s second `pm_bufferize`
#    rule carries the IDENTICAL `name="b"` pattern, fires on every node Metal's
#    first rule fires on, and answers the same thing -- so Metal's rule is
#    REDUNDANT with `Compiled`'s on every input, and the only difference it can
#    make is to fire LESS. No fixture will ever change that.
#
# ---------------------------------------------------------------------------
# THREE MOVED NOTHING ON THE FIRST RUN AND WERE FIXED WITH A FIXTURE, which is
# the whole point of running the harness rather than reading the code:
#
#  * M49 dropped :70's ENDT conjunct and nothing moved, because every fixture fed
#    `ccompile.ok` a good pair and both magics are CONSTANTS -- the check was
#    asked a question it had been told the answer to. `mt_cb_badtail` and
#    `mt_cb_badhead` are the negative halves it needed.
#  * M51 dropped the scan's last entry and nothing moved, because `mt_sync_scan_idx`
#    read `sync_starts` DIRECTLY and `sync_starts` is unchanged by a wrong count.
#    The row has to go through `dev.sync_scan`, at two sizes.
#  * M54 deleted `str_list_eq`'s ELEMENT walk and nothing moved, because the two
#    table rows compare `handles()`/`selectors()` against a COPY OF THE SAME TABLE
#    INSIDE THIS FILE -- the lengths always agree. `mt_tbl_reorder` (two names
#    swapped) and `mt_tbl_wrong` (one name changed) are the negatives a length
#    check cannot see, and they are also the rows that make the positive pair worth
#    anything.
#
# ---------------------------------------------------------------------------
# AND THE CONSTANT SWEEP, which is the table's most important row and is not a
# single edit: `mt_mutate.py` adds 1 to EVERY numeric constant def, one at a time.
# **111 defs, 30 whose +1 moves nothing** -- and all 30 are the `CALL_*` tag
# space (29) plus `MTL_DEV` (a fixture device index). Every other constant in the
# file is now seen by at least one row, which was NOT true of eleven of them
# before this session because they had no reader at all.
#
# THE THIRTY ARE A GENUINE BLIND SPOT and must not be closed with rows that encode
# the bug. The `CALL_*` NUMBERS are a port-internal tag space: Python has no
# counterpart for "this call kind is 12", so a row printing the tag would only ever
# restate the assignment. What protects them runs the OTHER way -- `mt_constmap.py`
# checks each tag NAME against the `ops_metal.py` line that carries the selector
# the port claims (the `CLASS_BLACKWELL_COMPUTE_A`-holding-`_B` failure mode) and
# checks the tag set for density (`0..37 n=38 DENSE=True`). `MTL_DEV` is a fixture:
# it must be the device index `device.bend`'s `Bn.dev` compares against, and the
# right test is a row about `mem_used`, which is `device.bend`'s to write.
#
# | # | the edit | rows moved | what it is testing |
# | --- | --- | --- | --- |
# | M1 | csrc_pad drops the `- n` | 12  mt_pad1,mt_pad2,mt_pad3,mt_pad4,mt_pad5,mt_pad7 |  mt_pad1,mt_pad2,mt_pad3,mt_pad4,mt_pad5,mt_pad7 | | :62's `round_up(len+1,4) - len`. **A REAL PORT BUG THIS GATE FOUND**: the first version printed 4 where CPython says 3, and `mt_psrc7`/`mt_req7` moved with it. |
# | M2 | metal_version's `>= 13` becomes `>= 14` | 3  mt_params2,mt_ver12,mt_ver13 |  mt_params2,mt_ver12,mt_ver13 | | :56's four-arm ladder, and the 13/14 boundary. |
# | M3 | sel_ix cannot say `no name matched` | 34  mt_init_sels_only,mt_nsstring_sel,mt_pipe_sels,mt_poll_sels,mt_resid_add_sels,mt_resid_del_sels |  mt_init_sels_only,mt_nsstring_sel,mt_pipe_sels,mt_poll_sels,mt_resid_add_sels,mt_resid_del_sels | | the reverse lookup at all. Thirty-four rows, because every selector is looked up by name. |
# | M4 | q.items appends the vars BEFORE the globals | 6  mt_end_2buf1var,mt_exec_nbytes_c,mt_items_2_1,mt_items_3_2,mt_layout_2buf1var,mt_layout_at256 |  mt_end_2buf1var,mt_exec_nbytes_c,mt_items_2_1,mt_items_3_2,mt_layout_2buf1var,mt_layout_at256 | | :111's `[globals] + [vals]`. **A REAL PORT BUG**: `List.append` is `xs ++ ys`, so the first version built `[4,8,8]`. |
# | M5 | q.end's `default` is `at`, not `at + 8` | 2  mt_end_empty,mt_end_empty0 |  mt_end_empty,mt_end_empty0 | | :113's `default=off + 8`, and ONLY the two empty-rows fixtures reach it. |
# | M5b | q.end's `default` is `at + 16` | 2  mt_end_empty,mt_end_empty0 |  mt_end_empty,mt_end_empty0 | | the same two rows, so M5 is not a one-value accident. |
# | M6 | q.exec.off aligns to 64, not 256 | 20  mt_exec_nbytes,mt_exec_nbytes_c,mt_hdr_word,mt_header,mt_header_agree,mt_icb_cmd_order |  mt_exec_nbytes,mt_exec_nbytes_c,mt_hdr_word,mt_header,mt_header_agree,mt_icb_cmd_order | | :112's 256-byte argument alignment. |
# | M7 | run.encoder before run.cmdbuf | 4  mt_run_one_storevals,mt_run_order,mt_run_sels,mt_run_two_storevals |  mt_run_one_storevals,mt_run_order,mt_run_sels,mt_run_two_storevals | | :139 before :140 -- the FIRST TWO calls of every `run`. |
# | M8 | run.pipeline.at is inverted | 16  mt_run_a10_calls,mt_run_calls,mt_run_disp_args,mt_run_exec_args,mt_run_msgsend_n,mt_run_one_exec |  mt_run_a10_calls,mt_run_calls,mt_run_disp_args,mt_run_exec_args,mt_run_msgsend_n,mt_run_one_exec | | :146's arm, and the call count behind it. |
# | M9 | run.execute dispatches `first`, not `count` | 7  mt_run_disp_args,mt_run_exec_args,mt_run_one_exec,mt_run_order,mt_run_setpipe_args,mt_run_sym_args |  mt_run_disp_args,mt_run_exec_args,mt_run_one_exec,mt_run_order,mt_run_setpipe_args,mt_run_sym_args | | :151's `withRange:` length. Seven rows, and `mt_run_order` is one of them -- the pattern spells the argument. |
# | M10 | run.slot0 and run.slot1 swapped | 4  mt_run_one_storeslots,mt_run_one_storevals,mt_run_two_storeslots,mt_run_two_storevals |  mt_run_one_storeslots,mt_run_one_storevals,mt_run_two_storeslots,mt_run_two_storevals | | :159 before :160. Four rows and not one, because the two stores differ in BOTH their slot and their value. |
# | M11 | dev.apple9's `or` becomes an `and` | 17  mt_apple9_apple8,mt_run_a10_calls,mt_run_calls,mt_run_disp_args,mt_run_exec_args,mt_run_msgsend_n |  mt_apple9_apple8,mt_run_a10_calls,mt_run_calls,mt_run_disp_args,mt_run_exec_args,mt_run_msgsend_n | | :146's DISJUNCTION. Only `mt_apple9_apple8` of the seventeen is ABOUT the disjunction; the other sixteen are the trace, because the arm gates two of `run`'s thirteen calls. |
# | M12 | runs2's FIRST run is `last` | 3  mt_run_two_calls,mt_run_two_signal,mt_run_two_storevals |  mt_run_two_calls,mt_run_two_signal,mt_run_two_storevals | | :167's `last=False`, and the fact that `encodeSignalEvent:value:` then appears once. |
# | M13 | runs2 does NOT thread the trace | 5  mt_run_two_calls,mt_run_two_commit,mt_run_two_stores,mt_run_two_storeslots,mt_run_two_storevals |  mt_run_two_calls,mt_run_two_commit,mt_run_two_stores,mt_run_two_storeslots,mt_run_two_storevals | | `h` is the ACCUMULATOR through both `run` calls. A port that gave each `run` a fresh trace loses the first run's thirteen calls, and five rows say so. |
# | M14 | q.submit.at's no-stamps arm builds the STAMPS path | 0 | a mutation that cannot change behaviour, run because "the edit that adds only a `+`" is the one an LLM would most plausibly make by accident. It moves nothing, and the table is honest about that. |
# | M14b | q.submit.at's no-stamps arm builds the STAMPS path (real) | 9  mt_run_a10_calls,mt_run_calls,mt_run_disp_args,mt_run_exec_args,mt_run_order,mt_run_res_calls |  mt_run_a10_calls,mt_run_calls,mt_run_disp_args,mt_run_exec_args,mt_run_order,mt_run_res_calls | | :166's `if not self.stamps`. |
# | M14c | q.submit.at's many arm is selected when NOT many | 0 | see M14. |
# | M14e | q.submit.at's many arm is selected when NOT many (real) | 11  mt_has_late2,mt_run_one_commit,mt_run_one_exec,mt_run_one_storeslots,mt_run_one_storevals,mt_run_two_calls |  mt_has_late2,mt_run_one_commit,mt_run_one_exec,mt_run_one_storeslots,mt_run_one_storevals,mt_run_two_calls | | the three-way tail, and `mt_run_one_*` is in the eleven because the one-run fixture takes the `else` arm. |
# | M14d | q.submit.runs2 drops its SECOND run | 7  mt_has_late2,mt_run_two_calls,mt_run_two_commit,mt_run_two_signal,mt_run_two_stores,mt_run_two_storeslots |  mt_has_late2,mt_run_two_calls,mt_run_two_commit,mt_run_two_signal,mt_run_two_stores,mt_run_two_storeslots | | :168. Seven rows, and `mt_has_late2` is one of them -- a pattern that only occurs in the SECOND run. |
# | M15 | Tr.emit.go drops the `raise` guard | 6  mt_alloc_refused_calls,mt_icb_local_bad_calls,mt_icb_local_bound,mt_icb_refuse_calls,mt_init_refused_calls,mt_pipe_librefuse_calls |  mt_alloc_refused_calls,mt_icb_local_bad_calls,mt_icb_local_bound,mt_icb_refuse_calls,mt_init_refused_calls,mt_pipe_librefuse_calls | | THE RAISE. Every refusal TRUNCATION row, and only those. |
# | M16 | Tr.has.go's fuel is the PATTERN length | 6  mt_alloc_order,mt_has_late,mt_has_late2,mt_icb_cmd_order,mt_icb_local_pipeline,mt_icb_order |  mt_alloc_order,mt_has_late,mt_has_late2,mt_icb_cmd_order,mt_icb_local_pipeline,mt_icb_order | | THE MATCHER. `mt_has_late`/`mt_has_late2` exist for this and are the two rows the WebGPU template's M23 had to add. |
# | M17 | pipeline emits setComputeFunction BEFORE newFunctionWithName | 1  mt_pipe_order |  mt_pipe_order | | :247's argument-before-callee order. One row, and it is LOCALISED. |
# | M17b | pipeline drops the NSString as well | 8  mt_icb_calls,mt_icb_librefuse_calls,mt_icb_local_bad_calls,mt_icb_local_ok_calls,mt_icb_typerefuse_calls,mt_pipe_calls |  mt_icb_calls,mt_icb_librefuse_calls,mt_icb_local_bad_calls,mt_icb_local_ok_calls,mt_icb_typerefuse_calls,mt_pipe_calls | | :247's NSString. `pipe_pat` compares the WHOLE list, so a missing call in the MIDDLE is a length mismatch, and eight rows move because every ICB builds a pipeline per command. |
# | M18 | mark_resident runs BOTH paths | 1  mt_resid_excl_commits |  mt_resid_excl_commits | | :229-237's mutual exclusion. One row, and it is the commit COUNT. |
# | M19 | setMaxKernelBufferBindCount is 2 | 2  mt_icb_binds,mt_icb_order |  mt_icb_binds,mt_icb_order | | :256's ONE bind, which is the number cstyle's `[[buffer(0)]]` and this file have to agree on. |
# | M20 | icb_max drops the `max(..., 1)` | 1  mt_icb_max0 |  mt_icb_max0 | | :257's `max(len(cmds), 1)`. |
# | M21 | local_ok's `>` becomes `>=` | 1  mt_local_eq |  mt_local_eq | | :262's STRICT comparison; `mt_local_eq` is the only fixture at the boundary. |
# | M22 | sync_count uses round_up, not ceildiv | 8  mt_sync_n13,mt_sync_n17,mt_sync_n21,mt_sync_n9,mt_sync_scan_calls,mt_sync_scan_calls21 |  mt_sync_n13,mt_sync_n17,mt_sync_n21,mt_sync_n9,mt_sync_scan_calls,mt_sync_scan_calls21 | | `range(5, size, 4)`. **A REAL PORT BUG**: `round_up(4, 4)` is 4 and `range(5,9,4)` has one element. |
# | M23 | sync_range CONSES and reverses | 4  mt_sync_idx17,mt_sync_idx21,mt_sync_scan_idx,mt_sync_scan_idx21 |  mt_sync_idx17,mt_sync_idx21,mt_sync_scan_idx,mt_sync_scan_idx21 | | the append-vs-cons order. `mt_sync_idx5` is the one-element fixture that is BLIND to it, which is why `mt_sync_idx17` exists. |
# | M24 | sync.one's guard is inverted | 7  mt_sync_guard_args,mt_sync_guard_hits,mt_sync_guard_miss,mt_sync_guard_sels,mt_sync_noscan_calls,mt_sync_scan_calls |  mt_sync_guard_args,mt_sync_guard_hits,mt_sync_guard_miss,mt_sync_guard_sels,mt_sync_noscan_calls,mt_sync_scan_calls | | :279's `slots[start] and not slots[start + 2]`. |
# | M25 | the autorelease pool PUSHES before it POPS | 1  mt_pool_order |  mt_pool_order | | :284-285's pop-then-push. |
# | M26 | pmb_m2 requires the mtl_sel tag as well | 1  mt_pmb_icb |  mt_pmb_icb | | **A REAL PORT BUG**: M2's pattern is `UPat(Ops.PARAM, name="b")` with NO tag, and the first version chained it off M0. `mt_pmb_icb` printed 2 where the source answers 3. |
# | M26b | pmb_m1 requires the mtl_sel tag as well | 0 | see below. |
# | M26c | dev.pipeline.f keeps the COMPILER's magic check | 17  mt_icb_bar,mt_icb_bind,mt_icb_calls,mt_icb_cmd_order,mt_icb_conc,mt_icb_kbuf_args |  mt_icb_bar,mt_icb_bind,mt_icb_calls,mt_icb_cmd_order,mt_icb_conc,mt_icb_kbuf_args | | **A REAL PORT BUG**: `ccompile.ok(0, 0, ...)` compares a library's head against MTLB/ENDT and so EVERY pipeline refused. |
# | M26d | pmb_keep does not advance the rule index on a miss | 1  mt_pmb_icb |  mt_pmb_icb | | **A REAL PORT BUG**: the miss arm returned the accumulator unchanged, so rule 0 ran three times and rules 1 and 2 never ran. |
# | M26e | icb: every command is set up BEFORE the next handle is taken | 2  mt_icb_cmd_order,mt_icb_order |  mt_icb_cmd_order,mt_icb_order | | :259 and :260 are TWO SEPARATE LOOPS. |
# | M27 | pmb_keep is LAST-wins | 7  mt_pmb_both,mt_pmb_both_n,mt_pmb_cfunc,mt_pmb_sels,mt_pmb_slots,mt_pmb_slots4 |  mt_pmb_both,mt_pmb_both_n,mt_pmb_cfunc,mt_pmb_sels,mt_pmb_slots,mt_pmb_slots4 | | device.py:1611's `rewrite` is first-wins. |
# | M28 | icb_hdr_word divides by 4, not 8 | 2  mt_icb_order,mt_icb_storeslots |  mt_icb_order,mt_icb_storeslots | | :266's `view(fmt='Q')[header // 8]`. Found as a blind spot -- the row was missing and `mt_icb_storeslots` is the fix. |
# | M29 | icb_size drops the `+ 24` header | 3  mt_icb_nbytes,mt_icb_size,mt_icb_sizes_agree |  mt_icb_nbytes,mt_icb_size,mt_icb_sizes_agree | | :129 and :253 must spell the SAME number. |
# | M30 | fam_scan is FIRST-wins, not LAST-wins | 8  mt_fam_apple8,mt_fam_apple8_9,mt_fam_apple9,mt_fam_apple9_family,mt_fam_apple_first,mt_fam_mac |  mt_fam_apple8,mt_fam_apple8_9,mt_fam_apple9,mt_fam_apple9_family,mt_fam_apple_first,mt_fam_mac | | :213's `next(filter(..., reversed(...)))` is a LAST-wins over the dict. |
# | M31 | arch_of drops 5 characters, not 12 | 3  mt_arch_slice,mt_arch_slice_mac,mt_init_arch |  mt_arch_slice,mt_arch_slice_mac,mt_init_arch | | :215's `[12:]`. |
# | M32 | dev.arch.apple's `or` becomes an `and` | 5  mt_arch_or_apple,mt_arch_or_fallback,mt_init_arch,mt_init_fam,mt_init_order |  mt_arch_or_apple,mt_arch_or_fallback,mt_init_arch,mt_init_fam,mt_init_order | | :215's `or` is a FALLBACK, not a union. |
# | M33 | csrc_padded is off by one | 6  mt_psrc238,mt_psrc4,mt_psrc7,mt_req1,mt_req238,mt_req7 |  mt_psrc238,mt_psrc4,mt_psrc7,mt_req1,mt_req238,mt_req7 | | `len(src_padded)`. |
# | M34 | hdr_pipe is `n + 2`, not `n + 1` | 3  mt_hdr_pipe0,mt_hdr_pipe1,mt_run_order |  mt_hdr_pipe0,mt_hdr_pipe1,mt_run_order | | :148's `header.index(1 + n + r)`. |
# | M35 | selreg starts at word 0, not word 5 | 1  mt_sels_sel_args |  mt_sels_sel_args | | :224's five handles before the thirteen selectors. |
# | M36 | q.dims reads bit i+1, not bit i | 2  mt_dims_mixed,mt_dims_one |  mt_dims_mixed,mt_dims_one | | :121's `tuple(1 if isinstance(d, UOp) else int(d) for d in dims)` and the mask's bit order. |
# | M37 | alloc.of asks for contents BEFORE gpuAddress | 1  mt_alloc_order |  mt_alloc_order | | :179's three arguments, evaluated left to right. |
# | M38 | icb_cmds retains BEFORE it indexes | 2  mt_icb_cmd_order,mt_icb_order |  mt_icb_cmd_order,mt_icb_order | | :259's `indirectComputeCommandAtIndex(i).own()`. Found as a blind spot -- the two COUNT rows cannot see a swap and `mt_icb_cmd_order` is the fix. |
# | M39 | q.exec.sizes.at is unconditional | 28  mt_exec_nbytes_c,mt_exec_nrows,mt_exec_nrows_s,mt_hdr_word,mt_header,mt_header_agree |  mt_exec_nbytes_c,mt_exec_nrows,mt_exec_nrows_s,mt_hdr_word,mt_header,mt_header_agree | | :117's `if any(isinstance(d, UOp) for d in dims)`. |
# | M40 | dev.queue_max is 512 | 3  mt_c_queue_max,mt_init_queueargs,mt_queue_max |  mt_c_queue_max,mt_init_queueargs,mt_queue_max | | :200's 1024. |
# | M41 | a comment-only edit -- THE CONTROL | 0 | a table with no row that CANNOT move is a table of coincidences. |
# | M42 | the seam: `cc_error_ok` tests `err == 2` instead of `err == 0` | 4  mt_cb_bad2,mt_cb_bad_refused,mt_cb_ok0,mt_cb_ok_live |  mt_cb_bad2,mt_cb_bad_refused,mt_cb_ok0,mt_cb_ok_live | | :47's `if error == 0`. Four rows and not one, because inverting it also inverts `mt_cb_ok_live` -- which is what makes this a test of the arm rather than of the constant. |
# | M43 | the seam: the error arm does NOT refuse | 1  mt_cb_bad_refused |  mt_cb_bad_refused | | the error arm's RAISE. One row, and one is right: a refusal that still made both calls is exactly what `mt_cb_bad_calls` exists to distinguish from skipping them. |
# | M44 | the seam: the error arm refuses WITHOUT calling | 2  mt_cb_bad_calls,mt_cb_ok_calls |  mt_cb_bad_calls,mt_cb_ok_calls | | the error arm's ORDER -- refuse before the call rather than after. Two rows, and they are the two COUNT rows, so the table records that the port calls first and refuses second. |
# | M45 | the seam: `REPLY_HDR` is 100, the header the SYNTHETIC fixtures guessed | 2  mt_liboff_host,mt_reply_hdr |  mt_liboff_host,mt_reply_hdr | | :50's header sum, on the value a REAL reply carried. This is the row that did not exist before this session: `mt_liboff42` and `mt_liboff00` were synthetic and 104 was unreachable. |
# | M46 | the seam: `REPLY_LEAD` is MTLB -- the two blobs confused | 2  mt_reply_is_mtlb,mt_reply_lead |  mt_reply_is_mtlb,mt_reply_lead | | THE TWO BLOBS. Printing MTLB as the reply's leading word moves `mt_reply_is_mtlb` to True and the row then says the un-sliced reply carries the magic, which it does not. `nv_query_litter` in two rows. |
# | M47 | the seam: `CB_ERR_COMPILE` is 1 | 1  mt_err_compile |  mt_err_compile | | the compiler's error code. One row, because `CB_ERR_COMPILE` is also `cc_error_ok`'s input and M42 covers the consumer. |
# | M48 | the seam: `MACOS_MAJOR` is 15, so the host compiles with metal3.1 | 2  mt_macos_major,mt_ver_host |  mt_macos_major,mt_ver_host | | :55-56's ladder at the HOST's version, so the four-way ladder is checked at the value it will actually be asked about. |
# | M49 | the seam: the magic check drops the ENDT half | 1  mt_cb_badtail |  mt_cb_badtail | | :70's ENDT conjunct. **THIS MOVED 0 ROWS BEFORE THE FIXTURE.** Every fixture fed `ccompile.ok` a good pair, and both magics are CONSTANTS, so the check was only ever asked a question it had been told the answer to. `mt_cb_badtail` and `mt_cb_badhead` are the negative halves. |
# | M50 | the wiring: `dev.sync.go` drops the call and keeps walking | 2  mt_sync_scan_calls,mt_sync_scan_calls21 |  mt_sync_scan_calls,mt_sync_scan_calls21 | | :276-281's walk: drop the per-entry work and keep walking. Two rows and both are COUNT rows at two sizes, which is the fixture M51 needed. |
# | M51 | the wiring: `dev.sync_scan` misses the LAST entry | 2  mt_sync_scan_calls,mt_sync_scan_calls21 |  mt_sync_scan_calls,mt_sync_scan_calls21 | | the scan losing its LAST entry. **ALSO 0 BEFORE THE FIXTURE**: `mt_sync_scan_idx` read `sync_starts` DIRECTLY, so the row never went through the def under repair, and `sync_starts` is unchanged by such a bug. `mt_sync_scan_calls21` is the second size. |
# | M52 | the wiring: `dev.sync_scan` ignores the guard | 1  mt_sync_noscan_calls |  mt_sync_noscan_calls | | the guard, through the scan rather than through `sync.one`. One row, the guarded arm's count. |
# | M53 | the wiring: `icb_keep` adds ZERO -- :267 is entered and not counted | 1  mt_nics1 |  mt_nics1 | | :267's weak-dictionary count. One row, and adding ZERO is the mutation that matters: the entry is created and the count does not move, which is a bug an `nics`-reading gate would miss. |
# | M54 | the wiring: `str_list_eq` compares lengths only | 2  mt_tbl_reorder,mt_tbl_wrong |  mt_tbl_reorder,mt_tbl_wrong | | `str_list_eq`'s ELEMENT comparison. **ALSO 0 BEFORE THE FIXTURE**, and for a worse reason than M49: `mt_tbl_handles` and `mt_tbl_sels` compare the table against a copy of the table INSIDE THIS FILE, so the lengths always agree and deleting the element walk changed nothing. `mt_tbl_reorder` (same length, two names swapped) and `mt_tbl_wrong` (same length, one name changed) are the two negatives a length check cannot see. |
# | M54b | the wiring: `str_list_eq` returns True unconditionally | 2  mt_tbl_reorder,mt_tbl_wrong |  mt_tbl_reorder,mt_tbl_wrong | | the same walk made unconditional. Two rows and not four, because the two POSITIVE rows cannot tell. |
# | M55 | the constants: `ARG_ALIGN` is 128 | 21  mt_c_arg_align,mt_exec_nbytes,mt_exec_nbytes_c,mt_hdr_word,mt_header,mt_header_agree |  mt_c_arg_align,mt_exec_nbytes,mt_exec_nbytes_c,mt_hdr_word,mt_header,mt_header_agree | | :112's 256. Twenty-one rows and one of them is `mt_c_arg_align`; the other twenty are the layout, the header word and the ICB's byte offset, which is the composability claim. |
# | M56 | the constants: `SYNC_START` is 4 | 14  mt_c_sync_start,mt_sync_idx17,mt_sync_idx21,mt_sync_idx5,mt_sync_n13,mt_sync_n17 |  mt_c_sync_start,mt_sync_idx17,mt_sync_idx21,mt_sync_idx5,mt_sync_n13,mt_sync_n17 | | :278's scan start. Fourteen rows: the profile scan's count, its index list at three lengths, AND the new `mt_sync_scan_*` pair. |
# | M57 | the constants: `MTLB_MAGIC` is byte-swapped | 2  mt_c_mtlb,mt_mtlb |  mt_c_mtlb,mt_mtlb | | the magic's ENDIANNESS. Two rows and both would read as plausible -- this is the failure mode the seam's two-blob rows exist to make visible. |
# | M58 | the constants: `DIM_WORDS` is 3 | 1  mt_c_dim_words |  mt_c_dim_words | | `:116`'s `len(dims)`. One row, and one is a FINDING: `DIM_WORDS` feeds nothing but the fixture's symbolic mask, so before `mt_c_dim_words` existed it was invisible. `mt_c_all_syms` catches the mask. |
# | M59 | the constants: `ALL_SYMS` is 32, a NON-ALL symbolic mask | 2  mt_c_all_syms,mt_dims_all |  mt_c_all_syms,mt_dims_all | | (1 << len(dims)) - 1, on a NON-ALL mask. Two rows, and `mt_dims_all` is the one that would have caught a fixture that stopped being all-symbolic. |
# | M60 | the constants: `SEL_SIGNALEDVALUE` is 16 | 2  mt_c_sel_sigval,mt_poll_sels |  mt_c_sel_sigval,mt_poll_sels | | one of the eighteen selector indices. Two rows, and it is the LAST one, so a table that dropped its tail would still agree on the other seventeen -- which is why `mt_sel_n` counts. |
# | M61 | the constants: `HDR_ICB` is 1 -- the ICB word is 0 | 2  mt_c_hdr_icb,mt_hdr_icb |  mt_c_hdr_icb,mt_hdr_icb | | the ICB's word index. Two rows, and the `mt_hdr_icb` half is the one that is about the header layout rather than the trace. |
#
# SEVEN OF THESE MUTATIONS FOUND A REAL BUG IN THIS PORT, and every one of them
# was a DIFFERENT KIND of mistake --
#
#   M1/M33   an arithmetic omission (a missing subtraction)
#   M4       a reversed concatenation (`List.append` is `xs ++ ys`)
#   M22      the wrong helper (`round_up` is not `ceildiv`)
#   M23      a reverse applied to a fold that appends
#   M26      a predicate chained off the wrong rule
#   M26c     the wrong function called (the compiler's check on the pipeline)
#   M26d     an accumulator that did not advance on a miss
#
# and NOT ONE of them was a type error or a proof failure. `--check-only` said
# ALL PROOFS CHECK through all seven, which is the argument for the gate and the
# argument for generating its expectations from CPython rather than by hand.
#
# M3 (thirty-four rows) and M39 (twenty-eight) are the two widest, and neither is
# a shared bug: M3 moves every row that LOOKS A SELECTOR UP BY NAME, because
# `sel_ix` is called on both sides of the trace, and M39 moves every row that
# depends on `nbytes`, which is what :117's `if` decides. M6 (twenty) and M26c
# (seventeen) are the next two and each is one constant or one call under a
# whole subtree.
#
# M26b IS A BLIND SPOT AND IT IS ABOUT THE SOURCE, NOT THE GATE. M1's pattern is
# `UPat(Ops.PARAM, tag="slots", name="b")` and its body is
# `ctx.new_slots(b.max_numel()) if b.max_numel() > 4 else None`; `device.py:404`'s
# second rule is `UPat(Ops.PARAM, name="b")` -> a program Buffer, and it fires on
# EVERY node M1 fires on. So whenever M1 fires, `device.bend`'s rule 1 would have
# given the same ANSWER (2) and the same ARENA GROWTH (one Buffer). Adding
# `tag="mtl_sel"` to M1's predicate changes nothing observable, for any input.
# The only difference M1 can make is to fire LESS -- which is what the `> 4`
# guard and M26 show. **Metal's first `pm_bufferize` rule is REDUNDANT with
# `Compiled`'s second one, on every input, and the port says so rather than
# pretending the gate can see it.**
#
# WHAT THIS GATE STILL DOES NOT SEE, and it is a short list:
#
#  1. THE ObjC ARGUMENTS THEMSELVES. `Tr` records the call, the selector and ONE
#     number. `useResources:count:usage:` has three arguments and the port can
#     only read the count; `setKernelBuffer_offset_atIndex` has a buffer, an
#     offset and an index and the port can only read the offset; the dispatch's
#     MTLSizes are built by `mtl_size` and read by `mt_size_*`, and NOTHING checks
#     that the MTLSize `icb_disp` emits is the one `mtl_size.l` built -- the two
#     are one line apart and a swap moves nothing.
#  2. THE `getaddr` UOps THEMSELVES. `q.items` knows a global is EIGHT bytes
#     because `getaddr` is uint64 (MEASURED), and the ADDRESS each buffer
#     contributes is a graph write -- WALL 5. `mt_items_2_1` pins the WIDTHS and
#     nothing pins the VALUES.
#  3. THE COMPILER'S REQUEST BYTES. :62-63 are gated as LENGTHS
#     (`mt_psrc7`, `mt_ppar109`, `mt_req7`, `mt_qq`) and the sixteen bytes of
#     `struct.pack('<QQ', ...)` are the seam's. The MTLB/ENDT magics are gated
#     as NUMBERS (`mt_mtlb`, `mt_endt`) and the reply's bytes are not.
#  4. `checked`'s MESSAGE (:26). The port keeps the CALL and drops the text,
#     because the text is `localizedDescription` and there is nothing to decide
#     about it.
#  5. `int(cb.GPUStartTime() * 1e9)` (:281) -- no F64, so `dev.sync` records the
#     THREE calls and the two slot indices and not the nanoseconds.
#  6. `pm_encode` and `pm_lower` (:189, :192). Both are `UOp` MATCHERS whose
#     bodies build graphs, and the port carries neither. `pm_bufferize` IS gated
#     because its answers are Buffers and Buffers are the port's subject.
# ===========================================================================


# ===========================================================================
# THE LANES. `mt_diff.py` runs FIVE and compares them, and the number that
# matters is not "green" -- it is how many rows each oracle ANSWERS.
#
#   interpreted  the file, `bin/bend <file>`
#   native       `bin/bend <file> -o x && x`, and it must be BYTE IDENTICAL
#   graph        `.agents/slop/mt_rows.py`, the original 169-row graph oracle
#   const        `.agents/slop/mt_constmap.py --rows`, 72 rows, ONE PER CONSTANT
#                with a numeric authority -- `autogen/metal.py` by getattr,
#                `ops_metal.py` by CPython's `ast`, a real `MetalDevice` for the
#                family and the `sels` Buffer, and a REAL KERNEL LAUNCH for
#                `DIM_WORDS` and `ALL_SYMS`
#   seam         `.agents/slop/mt_seam_rows.py`, the REAL
#                `MTLCodeGenServiceBuildRequest` fired through Apple's block ABI
#                with an instrumented callback, for `:42-71`
#
# 432 rows, `ALL PROOFS CHECK`, interpreted == native, 253 oracle rows answered,
# **0 disagreements**, 6 oracle-only and 173 Bend-only. The oracle-only six are
# facts about a real MTLB that the port has no way to HOLD because it never sees
# the bytes (`mt_mtlb_ret`, `mt_endt_ret`, `mt_ret_bytes`, `mt_ret_is_mtlb`) and two
# pre-existing `*_and` fixtures.
#
# The `const` lane is the answer to `ops_nv.bend`'s 33 of 219. That file's gate
# tested graphs and its constants answered to a C header nobody read, so no number
# of rows could have found them; here the constants are ROWS, diffed against
# authorities produced by a different program from a different source. A wrong
# constant is now a `DIFFER`, not a coincidence.
