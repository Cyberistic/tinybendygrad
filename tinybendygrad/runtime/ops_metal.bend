# tinybendygrad/runtime/ops_metal.bend -- port of tinygrad/runtime/ops_metal.py
#
# THE half of the metal chain that submits. `renderer/cstyle.bend` already emits
# Metal kernel TEXT and its `kern2 METAL` rows are committed and green, so the
# shader half of this chain exists (`renderer/cstyle.bend`, 2314 lines, 228 rows).
# This file is the other half: the 287 lines of `tinygrad/runtime/ops_metal.py`
# that turn a compiled program and a list of buffers into an
# `MTLComputePipelineState`, an indirect command buffer, and a committed
# command buffer.
#

# DOES it compose with cstyle.bend? YES, AND the seam is one binding.
#
# `cstyle.py:398-403` gives a Metal kernel EXACTLY ONE buffer argument --
# `constant args_t& args [[buffer(0)]]` -- with every global pointer and every
# ALU scalar packed into that struct. And `ops_metal.py:263` binds it with
# `cmd.setKernelBuffer_offset_atIndex(buf.meta, buf.offset + off, 0)`:
# buffer index 0, the ICB header Buffer, byte offset `off` (tinygrad/runtime/ops_metal.py:263
# symbol=new_icb). `:264` then sets the geometry with `concurrentDispatchThreadgroups_threadsPerThreadgroup`
# (MTLSize(*dims[0:3]), MTLSize(*dims[3:])), and `dims` is
# `(*prg.arg.global_size, *prg.arg.local_size)` at tinygrad/runtime/ops_metal.py:140.
#
# So the four numbers the two files have to agree on, and DO, are:
#
#   1. ONE binding, at index 0.        `:256 setMaxKernelBufferBindCount(1)`
#   2. the struct's byte offset,       `:136 off = round_up(self.nbytes, 256)`
#   3. the global size and the local   `:140 dims = (*global_size, *local_size)`
#      size, as two MTLSizes,          `:264 MTLSize(*dims[:3]), MTLSize(*dims[3:])`
#   4. the entry point NAME,           `:247 newFunctionWithName(to_ns_str(name))`
#      which is `TinyELF.name`, the same string cstyle's `function_name`.
#
# The one thing still missing for a RUN on this host is `MetalCompiler.compile`
# (tinygrad/runtime/ops_metal.py:42-70). AND that is now measured rather than asserted -- see `t_seam`. Upstream's `compile` lives in `compile`.
#
# `compile` is FFI at EXACTLY TWO points: `MTLCodeGenServiceCreate` (:39) and
# `MTLCodeGenServiceBuildRequest` (:68). Both are already in the trace. Everything
# else in tinygrad/runtime/ops_metal.py:42-70 is a Python closure and a `struct`, and it is all ported and gated:
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
#   * THE two blobs are different. The UNSLICED reply starts with a little-endian
#     3 and only the SLICED `ret` carries `MTLB`. Reading the magic off the wrong
#     one is off by 1112298570 and still LOOKS like a magic -- which is
#     `nv_query_litter` exactly: a port and an oracle agreeing on a number neither
#     of them read off the thing. `REPLY_LEAD` and `mt_reply_is_mtlb` exist so
#     that cannot happen quietly again.
#   * `error` is 0 for a kernel that compiled and 2 for one that did not, so
#     `:47`'s `if error == 0` is a comparison against two values this host produced.
#
# THE seam that remains is one pointer. `ctypes.byref(callback, -0x10)` is the
# address of the `invoke` field of an Apple BLOCK, and Bend can neither allocate a
# block descriptor nor name its sixteenth byte. Hand the seam an already-compiled
# MTLB and the submission path is complete; hand it a block and `compile` runs.
#

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

# THE SPLIT, stated once and then obeyed. A def here EITHER builds the argument
# of one objc call (pure, and the gate checks it) OR records that call in the
# trace (and the gate checks the ORDER). There is no third kind.
#

# WHAT IS PORTED, DEF BY DEF.
#
#   :15  REQUEST_TYPE_COMPILE       PORTED  a constant
#   :18  DLL("CoreGraphics")        WALL 1  A DYNAMIC LIBRARY LOAD
#   :22  to_ns_str                  WALL 2  AN NSString, plus `@functools.cache`
#   :24  checked                    PORTED  the WRAPPER, i.e. the refusal
#   :29  class MetalCompiler        PORTED  the four tables and three refs
#   :35   support = DLL(MTLCompiler) WALL 1
#   :38   __init__                  PORTED  `cgs_create`, and the ENTRY name -- upstream creates the code-gen service in `__init__`
#                                               travels as `Cmd.name`
#   :41   __reduce__                WALL 3  PICKLE (a multiprocessing detail)
#   :42   compile                   PARTIAL  the layout and the refusals
#   tinygrad/runtime/ops_metal.py:60 macos_major/metal_version PORTED  the four-way `-std=` ladder
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
#   tinygrad/runtime/ops_metal.py:135 `args`         PORTED  `getaddr` is 8 bytes, a var is its own symbol=exec
#   tinygrad/runtime/ops_metal.py:136 `rows` / tinygrad/runtime/ops_metal.py:137 `nbytes` PORTED  `layout_args` and the `max` symbol=exec
#   :116-121 dims / sizes / cmds    PORTED  the symbolic-size arm and the tuple
#   :123 wait                       PORTED  a no-op, ON PURPOSE
#   :124 timestamp / :125 signal    PORTED  two appends
#   :127 submit                     PORTED  the ICB size and the header
#   :129 the placeholder size       PORTED  and it EQUALS :253's buffer size
#   tinygrad/runtime/ops_metal.py:155 patch          PORTED  three zero rows at `zero` symbol=submit
#   :135 the sizes loop             PORTED  one msgSend per symbolic command
#   :138 run                        PORTED  thirteen calls, four arms
#   :166-168 the submit tail        PORTED  three paths
#   :174 _alloc                     PORTED  the storage mode and refusal 3
#   :179 BufferStorage              PORTED  gpuAddress then contents
#   :180 _free                      PORTED  synchronize, mark_resident, release
#   :185 _offset                    PORTED  `D.host_offset`, device.bend's own -- upstream offsets a buffer in `_offset`
#   :185 pm_encode / :188 pm_lower  WALL 5  THE UOp MATCHER
#   :196 __init__                   PORTED  the twelve statements, in order
#   :201 the queue refusal          PORTED  refusal 4
#   :204-206 the residency set      PORTED  three calls, conditional
#   :213 check_family               PORTED  the reverse lookup
#   :214 arch                       PORTED  `[12:]` of the family name
#   :216 pm_bufferize               GONE    upstream deleted it; the section below
#   :222 sels                       PORTED  18 u64 = 144 bytes, and the [3:5]
#   :228 mark_resident              PORTED  both paths, and they are exclusive
#   tinygrad/runtime/ops_metal.py:238 `link_buffer`  GONE    upstream deleted `new_slots` (9ff6db7b0); `link_buffer` replaced it symbol=link_buffer
#   tinygrad/runtime/ops_metal.py:244 `pipeline`     PORTED  four calls and `checked` twice symbol=pipeline
#   :251 new_icb                    PORTED  the size and the eleven steps
#   :258 the ICB refusal           PORTED  refusal 5
#   :262 the local-size refusal     PORTED  refusal 6, PER COMMAND
#   :270 _wait_signal               PORTED  and refusal 7
#   :275 synchronize                PARTIAL the index arithmetic, not the times
#   :284-285 the autorelease pool   PORTED  pop-then-push, in that order
#   :267 the ICB weak-dict         PORTED  `icb_keep`, and it WAS not called -- upstream stores the ICB entry in `self.icbs`
#   tinygrad/runtime/ops_metal.py:276-281 the profile scan PORTED  `dev.sync_scan` -- upstream's `profile_slots` scan -- and it WAS NOT CALLED symbol=synchronize
#   :42-71 compile                 CLOSED  all of it but the block pointer
#   --    THE CONSTANTS            PORTED  65 with a CPython authority, all gated
#

# THREE defs were written and nothing reached them, and that is the finding this
# session started from. `icb_keep` -- upstream's `icbs` (tinygrad/runtime/ops_metal.py:267 symbol=new_icb) --, `dev.sync_scan`'s list (`sync_starts`,
# :276-281) and `cns_string` (:23, `to_ns_str`) each carried a comment saying a row checked it,
# and each was DEAD: correct, unread, and unreachable from `main`. A file whose
# gate prints 332 rows had a `Dev.nics` that was always 0, a profile scan that was
# a no-op, and a `newFunctionWithName:` with no name in it.
#
# `.agents/slop/dead-defs.py` is the tool -- name-based, and it blanks a def's own
# NAME in place rather than dropping the whole line, because most defs here are ONE
# LINE and dropping the line hides every constant they read. It found 17 dead defs
# on top of `main`. Fifteen are now live (four rows) and TWO are gone: the `Fq`
# has -- `check_family` takes `f` as a PARAMETER, so a record bought nothing a
# string does not already do.
#

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
#    TODO(p3) runtime/ops_metal.py:23  -- `stringWithUTF8String:` -> NSString.
#
# 3. PICKLE (:41). `__reduce__` exists only so a forked multiprocessing worker
#    builds a fresh `MTLCodeGenService`; it is `(MetalCompiler, ())` and it has
#    no reader in this tree.
#    TODO(p3) runtime/ops_metal.py:41  symbol=__reduce__  -- the pickle hook.
#
# 4. A SUBPROCESS (:72-80). `disassemble` shells out to
#    `extra/disassemblers/applegpu/compiler_explorer.py` and prints stdout. It
#    is a developer tool with no caller in the port.
#    TODO(p3) runtime/ops_metal.py:72  symbol=disassemble  -- the SUBPROCESS.
#
# 5. THE UOp MATCHER (:185, :188). `pm_encode` and `pm_lower` match on UOps and
#    their bodies are UOp graphs, and building one needs `./uop/ops.bend` and the
#    HCQ2 lowering this file does not own, so the port carries neither.
#    `pm_bufferize` WAS a third one and it is GONE from upstream at the pin, so
#    The `pm_encode` and `pm_lower` rules are tinygrad/runtime/ops_metal.py:185-188.
#    TODO(p3) runtime/ops_metal.py:186  symbol=MetalQueue  -- `MetalQueue(s).encode()`.
#    TODO(p3) runtime/ops_metal.py:192  symbol=mtl_msg  -- the `pm_lower` fence poll.
#
# NOT A WALL, and named because it looks like one: every `mtl_msg` goes through
# `ccall(MSGSEND[ret], obj, sel, *args)`, and `ccall` builds a UOp
# `CUSTOM_FUNCTION` node. This file records the call in the trace instead, and
# the trace is the argument of the seam: what survives is the ORDER, the
# SELECTOR, and the ARITHMETIC, which is all the structure there is.
#

# THE two numbers that are not in the port at all, and why.
#
#  * `int(cb.GPUStartTime() * 1e9)` at :281. `base.bend` has no F64, so the
#    nanosecond conversion cannot happen here. `dev.sync` computes the WORD
#    INDICES the scan visits and records `waitUntilCompleted`, and the times
#    themselves are the seam's.
#    TODO(p3) runtime/ops_metal.py:281  symbol=synchronize  -- `GPUStartTime/GPUEndTime * 1e9`.
#  * `f"{self.device} signal wait timed out"` and
#    `f"Invalid Metal library. {ret!r}"` interpolate a value this port has no
#    spelling for (a `bytes` repr). The gate diffs the PREFIX of each, beside
#    CPython's own output, and says so in the row name.
#

# WHAT device.bend OWES this file, and it OWES it four things, all consumed:
#
#  1. `D.Bar` / `D.Bn` / `D.bnew` are the Buffer. `_alloc` (:179) and `new_icb`
#     (:253) both RETURN a Buffer, and `ops_metal.py:263` reads
#     `buf.get_storage().meta` -- so the arena travels with the answer, in
#     `Made`, by the same rule `D.bnew` follows. `nbytes` is `size * itemsize`
#     and a view's offset ACCUMULATES, so neither is a field here.
#  2. `D.iter_sig` IS `layout_args`' engine. `tinygrad/runtime/support/hcq2.py:114-116 symbol=layout_args` is
#     `[(offset + o, w) for (o, _), w in zip(TinyELF.iter_sig(...), words)]`
#     and `tinygrad/device.py:352-356 symbol=iter_sig` is what `D.iter_sig` ports. `q.layout` is the one
#     `zip` and nothing else -- re-deriving the rounding would be a SECOND
#     transcription of tinygrad/device.py:352 and the two could disagree silently.
#  3. `D.round_up` is `tinygrad/helpers.py:70 symbol=round_up`, and `off = round_up(self.nbytes, 256)`
#     (:112) and `at = round_up(self.nbytes, 8)` (:118) are both it.
#  4. `D.recycled` is `Allocator.free`'s FOUR conjuncts, and `new_icb`'s
#     `BufferSpec(nolru=True)` -- GONE at this pin: upstream b41c51306 ("metal icb rm nolru")
#     recycled, which is a decision this file does not have to make and gets
#     from `D.Bspec` by naming it. `mt_nolru` is the row.
#

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


# THE CONSTANTS. Every one of these is READ OUT OF tinygrad or out of
# `autogen/metal.py`, and the gate's expectation is generated by calling
# CPython -- see `.agents/slop/mt_oracle.py`, which `ast`-walks this same file
# for the selector order and opens a real `MetalDevice` for the arch, AND
# `.agents/slop/mt_audit2.py`, which is the HAND MAP.
#

# WHY THE HAND MAP EXISTS, since `ops_nv.bend` shipped 606 green rows with 33 of
# 219 constants WRONG. The gate tests GRAPHS; a constant answers to a generated
# header, so no number of rows finds a wrong one. `const-audit.py` was written to
# automate the diff and reaches 0 of these by name -- the port RENAMES
# (`CMDTYPE_CONCURRENT` vs `MTLIndirectCommandTypeConcurrentDispatch`), abbreviates
# (`SEL_WAITFENCE` for `waitForFence:`) and sometimes means something else by the
# same name (`ADDR_SIZE` is `Ops.GETADDR`'s dtype, not a header field). Its
# `0 likely-WRONG` is NOT a verdict and is never quoted as one.
#

# TODO(p1): NOT a phase claim -- a severity (.agents/TODO.md:11110). THIS file is a port of a superseded `ops_metal.py`, and its whole
# selector/message layer has no referent in the tree any more. It was written
# against `7b6766c2f`; the tree is `ad117c928`, which DELETED `SELECTORS`,
# `mtl_sel`, the `sels` Buffer (renamed `handles`) and the `MSGSEND` DICT (now a
# LIST `[objc_msgSend, sel_registerName]`), and replaced `header.index(...)` and
# `slots.index(k + 4 * first)` with slices and `slots.shrink`. AUDITED IN FULL on
# 2026-10-02: 111 numeric constant defs, 0 wrong, 1 drift, 2 gone upstream.
# The 0 is real and the map is `.agents/slop/mt_audit2.py`, whose anchors are
# regexes -- `mt_constmap.py`'s `ops_metal.py:NNN` anchors all moved in the rebase
# and that oracle now emits 0 rows and exits 1. What is NOT fixed is the drift:
#
#   * `sels_len` 18 is `d.sels.size`; the tree's buffer is `handles` and is 5.
#   * `SEL_*` index `(HANDLES + SELECTORS).index(name)`, and `SELECTORS` is gone.
#   * `RET_VOIDP` names entry 2 of a dict; entry 2 of the tree's LIST is
#     `sel_registerName`, which is a different thing entirely.
#
# These are NOT five one-line fixes. They are one re-port of the queue layer, and
# changing any single constant alone would make this file internally INCONSISTENT
# with the rest of its model -- a worse state than being uniformly stale. The
# constants are right for what they claim to be; the CLAIM is stale.
#
# ALSO DEAD: `CALL_MAXTPG` and `CALL_SETPIPELINE` are declared and documented in
# the `arg` table below but never reach `Tr.emit` and no row names them, so the
# ICB trace is missing two objc calls `new_icb` really makes.
#
# THE 38 `CALL_*` NUMBERS are not constants and are not audited as if they were:
# they are a port-internal tag space, and what can be wrong is the NAME -> meaning
# map, so the audit checks that map -- every tag against the `ops_metal.py` line
# that carries the selector the port claims, and the tag set for density.


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


# THE call kinds. `k` is the FFI entry point, and for a `mtl_msg` the identity
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


# THE TYPES.


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


# READING THE TRACE. Same three helpers the WebGPU template has, and the same
# one fix it needed: `Tr.has.go`'s FUEL IS THE TRACE LENGTH and the answer is
# `at == patlen`. With the fuel set to the PATTERN length it returns True after
# `patlen` entries without ever comparing `at`, and a REVERSED pattern matches
# -- which is why `mt_has_rejects` is the first row in the gate and why every
# order row below it is worth printing.

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

def str_eq.go(a: List<&2, String>, b: List<&2, String>, bad: Bool) -> Bool:
  match a:
    case Nil{}: Bool.not(bad)
    case x <> t:
      match b:
        case Nil{}: False{}
        case y <> u: str_eq.go(t, u, Bool.or(bad, Bool.not(String.eq(x, y))))


# THE REFUSAL MESSAGES. Every one of these is USER-VISIBLE -- they land in a
# Python traceback -- so each is a String built by `String.concat` and diffed
# against CPython's own `f`/`RuntimeError` output. `String.concat` DROPS A
# LITERAL SILENTLY, which is why the gate prints the string beside the boolean
# and never gates on a boolean about a string.


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

# :26, `raise RuntimeError(bytes(objc.msg("UTF8String")(err.localizedDescription
# )).decode())`. The whole message is the seam's -- it is whatever the
# Objective-C exception says -- so the port keeps the CALL and not the text.
# TODO(p3) runtime/ops_metal.py:26  -- `localizedDescription` -> RuntimeError.

# :69 `raise ret` and :52 `ret = CompileError(errorMessage.decode())` are both
# the seam's own text.
# TODO(p3) runtime/ops_metal.py:52  -- the callback's `errorMessage`.


# ops_metal.py:29-71 -- MetalCompiler. The part of the Metal chain that produces
# an MTLB, and the part that is NOT a ctypes call: the three tables below are
# the whole of the request, and a C seam only has to hand over the bytes.


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

# THE row that kills the `nv_query_litter` TRAP for this file. The UNSLICED reply
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

# :23 `to_ns_str`, and the `NSString` it makes is the seam. What the trace
# holds is the selector and the fact that the call happened.
def cns_string(t: Tr) -> Tr:
  Tr.emit(CALL_MSGSEND, sel_ix("stringWithUTF8String:"), 0, t)

# :204 and :246 and :254, `objc.msg("new", clsmeth=True)(SomeDescriptor)` --
# the same class allocation three times, and the same selector each time.
def cnew(t: Tr) -> Tr: Tr.emit(CALL_MSGSEND, sel_ix("new"), 0, t)


# ops_metal.py:103-168 -- MetalQueue. Five accumulators at :107, the argument
# layout at :111-113, the symbolic arm at :117-120, the ICB at :129-132, the
# sizes loop at :135-136, `run` at :138-163 and the submit tail at :166-168.


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

# :125 `signal(self, dst, val): self.value = val`. The value is read by :162's
# `encodeSignalEvent:value:`, which is inside `run`, so it is a `Run` field and
# NOT a field of the queue -- Python puts it on the queue because Python
# has a `self`, and Bend has none. `q.signal` is the queue unchanged and
# `mt_signal_keeps_nbytes` is the row that says the queue did not grow.
def q.signal(q: Q, v: U32) -> Q: q


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
# `.go`/`.put` PAIR of one self-RECURSIVE FOLD IS mutual recursion and is
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


# THE THREE STEPS OF `exec`, :112-121, each its own def because each is one
# numbered line range of the Python and each is a different KIND of update.


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


# ops_metal.py:112-120 -- everything that happens BEFORE the command is
# appended. Its own def because :118's `len(self.cmds)` is read AFTER the rows
# are laid out and one `Q` cannot be named twice in a body.
def q.exec.pre(+q: Q, nbufs: Nat, vars: List<&2, U32>, +mask: U32) -> Q:
  q.exec.sizes.at(q.any_sym(mask), Q.ncmds(q),
                  q.exec.rows(q, q.exec.off(Q.nbytes(q)), q.items(nbufs, vars)))


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
#     what cstyle.py:363 parses with `target.arch[5:]` for the tensor cores.
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


# ops_metal.py:187-220 -- MetalDevice, the twelve statements of `__init__` in
# their source order and the four fields the submission path reads.
#
# `resid` is a `U32` and not a `Maybe`, because a `Data` record may not hold a
# `Maybe` field and `Tr` reserves handle 0 for `None` -- which is what makes
# `:206`'s `self.residency.value is not None` and `:142`'s
# `self.dev.residency.value is None` two OPPOSITE reads of the same number.
# `mt_resid_flip` is the pair and it is the row that sees a `not` moved.

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

def CALL_SELREG() -> U32: 37

# `CALL_NKIND = 38` WAS HERE, and it is gone because it was DEAD and UNCHECKABLE.
# It claimed to be the number of call kinds, nothing read it, and there is no table
# of kinds in this file to check it against -- the tags are inline literals in
# thirty-eight `Tr.emit` calls. A count that no table can contradict is a comment
# wearing a number's clothes. `mt_constmap.py` prints the tag set's density instead
# (`0..37 n=38 DENSE=True`), which is the same claim and IS checkable.


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
# :101, `mtl_poll(tl) = mtl_msg(tl, mtl_sel(tl.device, "event"), "signaledValue",
# ret=ctypes.c_void_p)`. ONE msgSend on the EVENT handle, and the timeline is
# the event -- the comment at :100 says so and this is the whole of it. The
# `ret=c_void_p` is why it is the SECOND `MSGSEND` binding, not the first.
def mtl_poll(d: Dev) -> Tr:
  Tr.emit(CALL_MSGSEND, SEL_SIGNALEDVALUE(), 0, Dev.tr(d))


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
# THE disjunction is only visible on the last two, and the first version of this
# comment claimed that nothing is ever False and was WRONG: it was written from
# :145's comment ("before apple9 the encoder must use the pipelines") instead of
# from the code, and `mt_apple9_apple9` printing False is what caught it. The
# arm runs on Apple 8 and earlier and on every non-Apple family, and the two
# `mt_apple9_mac2` / `mt_apple9_metal4` rows are the ONLY pair an `or` read as
# an `and` can move -- so those two exist and the Apple rows exist to pin the
# other direction.

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


# `MTLSize`, the one struct the argument marshalling builds by name, and
# `prod(dims[3:])` -- the local size's product, which is what :262 compares
# against `maxTotalThreadsPerThreadgroup`.

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


# ops_metal.py:127-168 -- `submit` and `run`. THE ORDER IS THE PORT and the
# thirteen calls of `run` are the whole of the submission.
#
# `run` is a nested def with FOUR conditional arms -- no residency set, the
# apple9 pair, the stamps pair and `last` -- and the first row of the gate
# pins the thirteen-STATEMENT shape the source has, arms tagged, because an
# order claim with no fixture for each arm is decorative.

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


# :127-136 and :166-168 -- `submit`. THE ICB GEOMETRY FIRST, and the two
# buffer sizes have to AGREE.


# :129, `buf = UOp.placeholder((zero + 24 + 8 * (1 + n + len(pipes)),), dtypes.uint8,
# device=self.devs, volatile=True, tag=("mtl_icb", tuple(self.cmds), zero + 24))`
# and :253, `buf = Buffer(self.device, header + 8 * (1 + len(cmds) +
# len(pipes)), dtypes.uint8, options=BufferSpec(nolru=True), preallocate=True)`
# with `header = zero + 24` being the THIRD element of the tag at :130. THE TWO
# SIZES are spelled out separately in the source and they must be the same
# number, so `mt_icb_sizes` is the row and a `+ 24` moved in one of them moves
# it and nothing else.
def icb_size(header: U32, n: U32, np: U32) -> U32:
  U32.add(header, U32.mul(ADDR_SIZE(), U32.add(1, U32.add(n, np))))

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

# THE second `run` STARTS from the first'S trace. That is not bookkeeping: :167
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


# :243-249 -- `pipeline`, `@functools.cache`d on `(lib, name)`. FOUR calls and
# TWO `checked` refusals, and the order inside :247 is the claim: Python
# evaluates `setComputeFunction`'s ARGUMENT first, so
# `newFunctionWithName(to_ns_str(name))` happens BEFORE
# `setComputeFunction(library.newFunctionWithName(...))`, not after it.
# `mt_pipe_order` is the row.

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


# :251-268 -- `new_icb`, the indirect command buffer. It is the LONGEST step
# list in the file and the one that decides whether a kernel can run at all, so
# the numbers are the composability claim:
#
#   ONE command buffer bind, at index 0     :256 setMaxKernelBufferBindCount(1)
#   the header's byte size                  :253 header + 8 * (1 + n + len(pipes))
#   six global/local numbers                :264 MTLSize(*dims[:3]), MTLSize(*dims[3:])
#   the entry point NAME                    :247 newFunctionWithName(to_ns_str(name))
#


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


# :174-185 -- MetalAllocator. FOUR methods and three of them are the interesting
# ones, and they are all thin over `device.bend`: `_alloc` makes a Buffer in the
# arena, `_offset` IS `D.host_offset`, and `_free` is a trace.


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

# :181's `self.dev.synchronize()`, the FIRST of the three.
def dev.sync(+t: Tr) -> Tr: t


# :270-285 -- `_wait_signal` and `synchronize`.


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

# :283-285,
#   super().synchronize(timeout)
#   if (pool := getattr(pools, "pool", None)) is not None: objc.lib.objc_autoreleasePoolPop(pool)
#   pools.pool = objc.lib.objc_autoreleasePoolPush()
# POP THEN PUSH, and that order is the whole of it: a pool is drained before the
# next is pushed, so the autoreleased objects of one submit are released before
# the next submit's are made. `mt_pool_order` is the row and a swap moves it.
def pool_pop(+t: Tr) -> Tr: Tr.emit(CALL_AUTORELPOP, PLACEHOLDER_IX(), 0, t)
def pool_push(+t: Tr) -> Tr: Tr.emit(CALL_AUTORELPUSH, PLACEHOLDER_IX(), 0, t)


# `pm_bufferize` IS GONE FROM UPSTREAM AT THE PIN, and this file's port of it
# is gone with it.
#
# The old upstream had, at `ops_metal.py:216-220`,
#   self.pm_bufferize = PatternMatcher([
#     (UPat(Ops.PARAM, tag="mtl_sel"),    lambda ctx: ctx.sels),                      # M0
#     (UPat(Ops.PARAM, tag="slots", name="b"),
#                                    lambda ctx,b: ctx.new_slots(b.max_numel()) if b.max_numel() > 4 else None),  # M1
#     (UPat(Ops.PARAM, name="b"),         lambda ctx,b: ctx.new_icb(*b.tag[1:]) if isinstance(b.tag, tuple) and b.tag[0] == "mtl_icb" else None),  # M2
#   ]) + self.pm_bufferize
# and `device.bend` carried `Compiled`'s two rules -- the TAIL of that `+`.
# AT THE PIN NONE OF IT IS THERE: `rg -n 'pm_bufferize' tinygrad/` answers
# NOTHING, `ops_metal.py` has no `new_slots` and no `self.sels`, and
# `device.py:374-377` carries `pm_encode`, `pm_lower`, `pm_link` and
# `link_bufs` -- with `link_buffer` a per-device method at `device.py:411`.
#
# WHAT REPLACED IT, and none of it is ported HERE yet:
#   :218  `Compiled.link_bufs |= {to_name(self.device, "handles"): lambda b:
#         self.handles}` -- M0's ANSWER (`ctx.sels`, renamed `self.handles`),
#         delivered by the registry instead of by a matcher. The KEY it
#         registers is `metal_0_handles`, and that is `device.bend`'s own
#         `tn_colon` row.
#   :238  `def link_buffer(self, b)` -- M1's ANSWER: a "slots" alloc of more
#         than four elements gets a HOST buffer of `b.max_numel() * 8` bytes.
#         The `> 4` half of that guard is `SLOTS_MIN`, and `mt_slots_thresh4`
#         and `mt_slots_thresh5` are its rows, and they stay.
#   :219  `Compiled.pm_link += ...` -- M2's ANSWER: the ICB is now built by the
#         LINK matcher, and `new_icb` (:251) survives as its BODY.
# The port of the registry and of its consumer lives in `device.bend` (the
# `lk_*` rows) and in `tinybendygrad/runtime/support/hcq2.bend`
# (`bufferize_buf`), and Metal's CONTRIBUTIONS to it are NOT ported.
#
# SO the seventeen rows that measured this block are gone, and so are the four
# mutation-table entries that were about it. They measured upstream code that
# does not exist, which is a row that can only ever agree.
#
# WHAT IS STILL PORTED OF METAL'S SIDE, and it is the part that survives: the
# `handles` buffer's five words, the `sels` table's rewrite of words 3 and 4,
# and `new_icb`'s size arithmetic (`icb_size`, `icb_header`, `mt_icb_*`).
