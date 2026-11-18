import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from cut import apply

F = "tinybendygrad/runtime/ops_metal.bend"

EDITS = [
  # ---- THE 144-LINE BLOCK. THE FOUR TRUNCATED SENTENCES ARE RESTORED FROM `394eae369`
  # (MEASURED, NOT WRITTEN FROM MEMORY), AND THE PROSE AROUND THE FACTS IS GONE.
  (4, 147, """# DOES it compose with cstyle.bend? YES, AND the seam is one binding.
#
# `cstyle.py:398-403` gives a Metal kernel EXACTLY ONE buffer argument --
# `constant args_t& args [[buffer(0)]]` -- with every global pointer and every ALU scalar packed
# into that struct. And `ops_metal.py:263` binds it with
# `cmd.setKernelBuffer_offset_atIndex(buf.meta, buf.offset + off, 0)`: buffer index 0, the ICB
# header Buffer, byte offset `off` (tinygrad/runtime/ops_metal.py:263 symbol=new_icb). `:264` then
# sets the geometry with `concurrentDispatchThreadgroups_threadsPerThreadgroup`
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
# (tinygrad/runtime/ops_metal.py:42-70). AND that is now measured rather than asserted -- see
# `t_seam`. Upstream's `compile` lives in `compile`.
#
# `compile` is FFI at EXACTLY TWO points: `MTLCodeGenServiceCreate` (:39) and
# `MTLCodeGenServiceBuildRequest` (:68). Both are already in the trace. Everything else in
# tinygrad/runtime/ops_metal.py:42-70 is a Python closure and a `struct`, and it is all ported and
# gated: the four-way `-std=` ladder, the `params` f-string, the 4-byte-padded source blob, the
# NUL, the 16-byte `<QQ` request header, the two blob lengths, the callback's `error == 0` arm AND
# its other arm, the header sum, the slice, and both refusals.
#
# THE THREE NUMBERS THE GATE READS OFF A REAL REPLY, all of them un-gated before:
#   * `reply[8:16]` is `(104, 0)` HERE, so `:50`'s slice starts at byte 104 of a 4580-byte reply
#     and the MTLB is 4476 bytes. `mt_liboff42` and `mt_liboff00` were the only fixtures and both
#     are synthetic.
#   * THE two blobs are different. The UNSLICED reply starts with a little-endian 3 and only the
#     SLICED `ret` carries `MTLB`. Reading the magic off the wrong one is off by 1112298570 and
#     still LOOKS like a magic -- which is `nv_query_litter` exactly: a port and an oracle agreeing
#     on a number neither of them read off the thing. `REPLY_LEAD` and `mt_reply_is_mtlb` exist so
#     that cannot happen quietly again.
#   * `error` is 0 for a kernel that compiled and 2 for one that did not, so `:47`'s `if error == 0`
#     is a comparison against two values this host produced.
#
# THE seam that remains is one pointer. `ctypes.byref(callback, -0x10)` is the address of the
# `invoke` field of an Apple BLOCK, and Bend can neither allocate a block descriptor nor name its
# sixteenth byte. Hand the seam an already-compiled MTLB and the submission path is complete; hand
# it a block and `compile` runs.
#
# THERE IS NO dtype-to-MTLPixelFormat TABLE IN ops_metal.py, and the brief asked for one.
# `grep -n PixelFormat tinygrad/runtime/ops_metal.py` is empty and `MTLPixelFormat` reaches this
# file only through `autogen/metal.py`, where it describes TEXTURES. A Metal buffer here is
# `newBufferWithLength_options(size, MTLResourceStorageModeShared)` -- a byte range, and a dtype
# changes how MANY bytes it covers (device.bend's `nbytes = size * itemsize`) and never how
# anything is named. THE TABLE IS IN `.agents/slop/tables/runtime-ops_metal-52.md` -- WHAT IS
# PORTED, DEF BY DEF.
#
# THREE defs were written and nothing reached them, and that is the finding this session started
# from. `icb_keep` -- upstream's `icbs` (tinygrad/runtime/ops_metal.py:267 symbol=new_icb) --,
# `dev.sync_scan`'s list (`sync_starts`, :276-281) and `cns_string` (:23, `to_ns_str`) each
# carried a comment saying a row checked it, and each was DEAD: correct, unread, and unreachable
# from `main`. A file whose gate prints 332 rows had a `Dev.nics` that was always 0, a profile scan
# that was a no-op, and a `newFunctionWithName:` with no name in it.
#
# `.agents/slop/dead-defs.py` is the tool -- name-based, and it blanks a def's own NAME in place
# rather than dropping the whole line, because most defs here are ONE LINE and dropping the line
# hides every constant they read. It found 17 dead defs on top of `main`. Fifteen are now live
# (four rows) and TWO are gone: the `Fq` record and its `fq()` constructor, a vestige of a shape
# the family fold no longer has -- `check_family` takes `f` as a PARAMETER, so a record bought
# nothing a string does not already do.
#
# THE FIVE WALLS.
#
# 1. A DYNAMIC LIBRARY LOAD (:18, :35). `DLL("CoreGraphics", "CoreGraphics")` is a module-level
#    `ctypes.CDLL` whose only job is to make `MTLCreateSystemDefaultDevice` resolvable
#    (https://developer.apple.com/documentation/metal/1433401-mtlcreatesystemdefaultdevice). There
#    is nothing to decide about it and nothing to gate.
#    TODO(p3) runtime/ops_metal.py:18  -- `DLL("CoreGraphics", "CoreGraphics")`.
#    TODO(p3) runtime/ops_metal.py:35  -- `DLL("MTLCompiler", "MTLCompiler")`.
#
# 2. AN NSString (:23, :247). `to_ns_str` is
#    `objc.msg("stringWithUTF8String:")(NSString, s.encode()).own()`. A `String` is a `String` here
#    and the SELECTOR is in the table, which is the part that decides anything; the OBJECT is the
#    seam's. `cns_string` records the selector and `dev.pipeline.fun` calls it, so the trace reads
#    `stringWithUTF8String:` -> `newFunctionWithName` -> `setComputeFunction:` -- the order
#    Python's argument evaluation produces, and NOT the order a name that "is a literal" would
#    produce. That was a dead def until this session and
#    TODO(p3) runtime/ops_metal.py:23  -- `stringWithUTF8String:` -> NSString.
#
# 3. PICKLE (:41). `__reduce__` exists only so a forked multiprocessing worker builds a fresh
#    `MTLCodeGenService`; it is `(MetalCompiler, ())` and it has no reader in this tree.
#    TODO(p3) runtime/ops_metal.py:41  symbol=__reduce__  -- the pickle hook.
#
# 4. A SUBPROCESS (:72-80). `disassemble` shells out to
#    `extra/disassemblers/applegpu/compiler_explorer.py` and prints stdout. It is a developer tool
#    with no caller in the port.
#    TODO(p3) runtime/ops_metal.py:72  symbol=disassemble  -- the SUBPROCESS.
#
# 5. THE UOp MATCHER (:185, :188). `pm_encode` and `pm_lower` match on UOps and their bodies are
#    UOp graphs, and building one needs `./uop/ops.bend` and the HCQ2 lowering this file does not
#    own, so the port carries neither. `pm_bufferize` WAS a third one and it is GONE from upstream
#    at the pin, so the port carries it no longer -- see the section that used to hold it. The
#    `pm_encode` and `pm_lower` rules are tinygrad/runtime/ops_metal.py:185-188.
#    TODO(p3) runtime/ops_metal.py:186  symbol=MetalQueue  -- `MetalQueue(s).encode()`.
#    TODO(p3) runtime/ops_metal.py:192  symbol=mtl_msg  -- the `pm_lower` fence poll.
#
# NOT A WALL, and named because it looks like one: every `mtl_msg` goes through
# `ccall(MSGSEND[ret], obj, sel, *args)`, and `ccall` builds a UOp `CUSTOM_FUNCTION` node. This
# file records the call in the trace instead, and the trace is the argument of the seam: what
# survives is the ORDER, the SELECTOR, and the ARITHMETIC, which is all the structure there is.
#
# THE TWO numbers that are not in the port at all, and why.
#
#  * `int(cb.GPUStartTime() * 1e9)` at :281. `base.bend` has no F64, so the nanosecond conversion
#    cannot happen here. `dev.sync` computes the WORD INDICES the scan visits and records
#    `waitUntilCompleted`, and the times themselves are the seam's.
#    TODO(p3) runtime/ops_metal.py:281  symbol=synchronize  -- `GPUStartTime/GPUEndTime * 1e9`.
#  * `f"{self.device} signal wait timed out"` and `f"Invalid Metal library. {ret!r}"` interpolate
#    a value this port has no spelling for (a `bytes` repr). The gate diffs the PREFIX of each,
#    beside CPython's own output, and says so in the row name.
#
# WHAT device.bend OWES this file, and it OWES it four things, all consumed:
#
#  1. `D.Bar` / `D.Bn` / `D.bnew` are the Buffer. `_alloc` (:179) and `new_icb` (:253) both RETURN
#     a Buffer, and `ops_metal.py:263` reads `buf.get_storage().meta` -- so the arena travels with
#     the answer, in `Made`, by the same rule `D.bnew` follows. `nbytes` is `size * itemsize` and
#     a view's offset ACCUMULATES, so neither is a field here.
#  2. `D.iter_sig` IS `layout_args`' engine. `tinygrad/runtime/support/hcq2.py:114-116
#     symbol=layout_args` is `[(offset + o, w) for (o, _), w in zip(TinyELF.iter_sig(...), words)]`
#     and `tinygrad/device.py:352-356 symbol=iter_sig` is what `D.iter_sig` ports. `q.layout` is the
#     one `zip` and nothing else -- re-deriving the rounding would be a SECOND transcription of
#     tinygrad/device.py:352 and the two could disagree silently.
#  3. `D.round_up` is `tinygrad/helpers.py:70 symbol=round_up`, and `off = round_up(self.nbytes,
#     256)` (:112) and `at = round_up(self.nbytes, 8)` (:118) are both it.
#  4. `D.recycled` is `Allocator.free`'s FOUR conjuncts, and `new_icb`'s
#     `BufferSpec(nolru=True)` -- GONE at this pin: upstream b41c51306 ("metal icb rm nolru")
#     recycled, which is a decision this file does not have to make and gets from `D.Bspec` by
#     naming it. `mt_nolru` is the row.
#
# NO PROOFS FAIL HERE, and the brief expected some. The Metal FFI calls are `@extern` seams in
# `dtype.bend`'s sense -- a `def ... -> IO(R)` whose body is two `import "./x.c"` lines -- and every
# one of them is expected to make its importer print PROOFS FAIL (constraint line 1868: the foreign
# notice is a "who names whom" closure, and `@unsafe` does not shrink it). This file does NOT take
# that route, because the WebGPU template does not: a Metal call is recorded in a `Tr` trace, so
# there is no foreign effect to declare and `--check-only` says ALL PROOFS CHECK. The seam is
# `Tr.emit`, the ORDER is the artefact, and `wgsl.bend`'s green lane is the precedent, not
# `dtype.bend`'s fourteen."""),
]

apply(F, EDITS)
