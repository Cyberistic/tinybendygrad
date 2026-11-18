import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from cut import apply

F = "tinybendygrad/runtime/ops_python.bend"

EDITS = [
  # ---- THE RENDERER / COMPILER / DEVICE HALF (79 lines) -> 47. THE TWO TRUNCATED
  # SENTENCES ARE RESTORED, AND THE CPython-vs-port TABLE IS THE DATA.
  (3006, 3084, """# THE RENDERER / COMPILER / DEVICE HALF -- ops_python.py:33-44 and :159-186
#
# the central question, answered: how does this file represent a python literal?
#
# `PythonRenderer.render` (:180) is `base64.b64encode(pickle.dumps(uops)).decode()` and its
# OUTPUT is a Python object: `bytes` holding a pickle, which is a Python OBJECT GRAPH written
# in a byte language -- and `UOp.arg` is a Python object of whatever type the rewrite that
# built it chose (a tuple, a list, a dtype, a numpy array, an `Attr`). No such value exists in
# Bend and none can: a dynamic value is precisely what a statically typed language refuses.
#
# So the port does not represent one and does not fake one. It gives the same information a
# different, total, byte-exact spelling:
#
#   CPython                    this port
#
# The last row is the load-bearing one. A Python `bytes` and a Bend `List<&2, Char>` carry the
# SAME total information about the SAME program; the port chose the spelling a total language
# can inspect, and the seam (`ops_bend.py`'s `BendProgram`) reads it back.
#
# `PythonCompiler.compile` (:160) is the opposite case and is ported EXACTLY:
# `base64.b64decode(src)` is a character-level transform with nothing dynamic in it, bytes
# included. That asymmetry is the answer, not an evasion -- the defs whose output is static get
# the real transform, and the one whose output is a Python object graph gets a wire and says so.
#
# what is not ported, stated here rather than discovered later:
#   * `wmma`'s fragment arithmetic (:35-43) needs `tcore.frag_coords()`, a three-way (row, col)
#     layout from `renderer/tc.py`, which this project has not ported, and its `arg` is a
#     `(dims, dtype_in, threads)` tuple. The core LOOKUP and the two ASSERTIONS are ported and
#     gated; the multiply-accumulate is WALL 2 and stays there.
#   * `supported_dtypes`' INHERITED half (:182) filters `super().supported_dtypes()`, a set this
#     file does not own. The filter itself -- `d != dtypes.half or sys.version_info >= (3, 12)` --
#     is ported and gated; the set is a seam.
#   * `render`'s pickle. See above. The v1 wire is the port's counterpart and is gated by
#     `.agents/slop/bend_packets.py`, not here.
#
# ---- PythonCompiler.compile, :160. base64.b64decode(src) ------------------
#
# WALL 5, AND IT IS A REAL ONE. `base64.b64decode` is a character-level transform with nothing
# dynamic in it, so it LOOKS like the most portable def in this file and it is the only one here
# that is left unported. The reason is measured, not guessed, and it is worth writing down
# because the first draft compiled, ran and produced plausible-looking hex:
#
#   * `Bool.pick` EVALUATES BOTH ARMS. A losing arm that computes
#     `Char.from_u32(U32.sub(v, 10))` for `v < 10` is `Char.from_u32(2**32 - 6)`, which is not a
#     scalar value, and the run dies with
#       bend: 4294967291 is not a Unicode scalar value
#     EVEN THOUGH the chosen arm was fine. (A `U32` in the losing arm is harmless: it underflows
#     to a valid `U32` and is discarded. The trap is specific to a CHECKED type.) The
#     nibble/byte printers below dodge it.
#   * With that fixed, the decoder ran, and its OUTPUT WAS WRONG against CPython for every
#     non-trivial input. Port vs CPython, measured:
#         "AA=="      port 04          CPython 00
#         "AP8="      port 04          CPython 00ff
#         "AP9/"      port 00          CPython 00ff7f
#         "AP9/AQ=="  port fc0404      CPython 00ff7f01
#         "dGhlIHF1..." port 9481c5ac... CPython 7468652071...
#     The byte COUNTS were wrong too (3 where CPython says 4 on the last one).
# `U32.shrn` is NOT the culprit -- measured `U32.shrn(4160, 16n) = 0` and
# `U32.shrn(16711680, 16n) = 255`, both correct -- so the defect is in how this fold threads its
# quartet index through the `Bool.pick` selects, and it was NOT found inside the time this unit
# had.
#
# There ARE two `pyc_*` rows, and neither of them runs the transform -- that is what they are
# FOR, and it is the honest limit rather than a gap. `compile` IS `base64.b64decode`: measured
# `PythonCompiler.compile.__func__ is base64.b64decode` is False, but `compile(src) ==
# base64.b64decode(src)` on every fixture, i.e. it IS the function under another name. What the
# port can decide WITHOUT a working quartet fold is the IDENTITY, so it declares which
# transform each of the two names performs and compares them:
#   * `pyc_is_b64decode` -- the transform `compile` performs IS the transform `base64.b64decode`
#     performs.
#   * `pyc_refused` -- its negation, the port's spelling of "it is not".
# the oracle can say more, and does: `B64_HOLDS` calls `compile` on eight fixtures and compares
# the BYTES, which is an empirical identity where this row is a declared one. That is the one
# row in this census where the port's answer is the weaker fact, and the gate says so rather
# than letting a green run read
# TODO(p3) runtime/ops_python.py:164  symbol=compile -- the base64 quartet fold."""),

  # ---- THE STORE (30 lines) -- the SECOND DEFECT and the MEASUREMENT. KEEP IT WHOLE.
  (1116, 1145, """# THE STORE: the packet's bytes in packet order, then `nbytes` zeros for each scratch
# buffer (ops_python.py:101,104 allocate `bytearray(n)`, and two scratch buffers must not share
# bytes).
#
# the zeros go after the packet's bytes, and there are `w*e` of them.
#
# `Prog.bases` gives the scratch buffer the base that FOLLOWS the packet's
#
# MEASURED 2026-10-26, and this was the port's SECOND defect, hidden behind the first: with the
# zeros PREPENDED and counted in ELEMENTS, every packet with a scratch `BUFFER` was shifted by `e`
# BYTES -- the packet's own bytes sat at the wrong offset, so every load and every store read
# and wrote the wrong place. The shift is visible in the tree's OWN census: `bool.maxpair.0.b1`
# is `0100010001000100` upstream and `0001000100010001` in the port -- the same bytes, shifted
# right by ONE, because that fixture's scratch is `k:buffer:1` (a bool, `w=1`, so `e=1`). The
# port's OWN conv packet has a `k:buffer:64` scratch (an f32, `w=4`, so `e=16`) and is shifted
# by 16 bytes -- four floats.
# - every pinned divergence of the "loop-carried local reduction family" and of the
# "VECTOR-STORE LANE family" IS THIS SHIFT, and the pin file's diagnosis ("a nested END jumps to
# the inner head") is a DIFFERENT STORY.
#
# the order is the other half: prepending the zeros puts the packet's bytes at offset
# `len(zeros)` while `Prog.bases` says their base is 0, so the shift is `len(zeros)` however the
# zeros are counted. The zeros belong AT THE END, and the one reversal that puts them there is
# the SAME reversal the byte order needs.
# 64 bytes per chunk, ONCE, at load: O(n) here and O(n/64 + 64) per store afterwards. `n`
# counts a chunk DOWN, so every self-call consumes the head -- Bend refuses a call whose first
# argument did not visibly shrink, and `List.drop` is not visible to that check."""),

  # ---- the STORE's conversion (25 lines) -- a BUG THAT WAS FOUND. KEEP IT.
  (2430, 2454, """# the value in the BUFFER's own TYPE, and why the STORE converts at all.
# ops_python.py:29-33's `_store` writes
#     if (w:=m.nbytes // len(m)) >= dtype.itemsize: m[i] = to_storage_scalar(v, dtype)
# into the BUFFER's own memoryview, and `m`'s element TYPE is the BUFFER's own
# (`storage_fmt_for_dtype(u.dtype)`, ops_python.py:99) -- SO THE VALUE IS converted to the
# BUFFER and is not written as its own BITS. the two agree when the value's dtype is the
# BUFFER's (the common case) and differ when they are not: a BOOL stored into an F32 BUFFER is
# upstream's `m[0] = True`, which IS 1.0f, AND NOT THE INTEGER 1.
# MEASURED 2026-10-26 on `alu.CMPNE.f`: CPython's output buffer 0 IS
# `0000803f00000000` (1.0f) and the port's was `0100000000000000` (the integer 1).
#
# the conversion is the CAST's conversion and not a second one: upstream's CAST is
# `truncate.get(u.dtype)(u.dtype.const(x))` AND upstream's STORE is `m[i] = value` INTO A
# MEMORYVIEW OF THE BUFFER'S TYPE, AND `DType.const` (dtype.py:84) and the memoryview are the
# same conversion for the four v1 lanes. so `Prog.cast.dt` is reused here, and it is the identity
# when the two DTYPES ARE THE SAME.
# the STORE's per-lane invariants, looked up once.
#
# The old lane loop called `Prog.buf(p, u)` eight times per lane -- twice inside `store.bits`,
# twice in `store.addr`, again in `store.open`, and `store.i` re-reads it -- and every one of
# those is `Prog.src`: an arena read with its `Maybe`. A four-lane store made ~32 arena reads to
# write 4 elements, and `Prog_store_lane_at` is in the executor's own profile. Everything except
# the VALUE is the same for every lane, so it is bound once in `Sb`."""),

  # ---- the run loop (27 lines) -- the MEASURED FUEL BURN. The THREE NEAR-DUPLICATE
  # PARAGRAPHS about the pair are the SAME FACT THREE TIMES.
  (2759, 2785, """# ONE def for the whole loop, and it has to be ONE: Bend refuses mutual recursion, so `run`
# and a separate `run.at` cannot both exist. The shape that works is MEASURED, not guessed:
#   * `match` on the FUEL, with the termination test as the `Bool.pick` GUARD.
#   * the countdown comes FIRST in the self-call: arguments are read left to right and nothing
#     rebuilt may precede the one that shrinks, and `Prog.step(pr)` is rebuilt.
#   * `+pr` because `Bool.pick` evaluates both arms and each consumes `pr`.
# => and the termination test is a match on the cursor, not a `Bool.pick` guard.
# MEASURED: `Bool.pick` EVALUATES BOTH ARMS, so the old body --
# `Bool.pick(Prog, Prog.over(pr), pr, run(k, Prog.step(pr)))` -- ran the recursive arm even after
# the program had finished, and EVERY LAUNCH BURNED THE WHOLE OF `FUEL`: the step counter read
# 4 000 000 for a 16x16 packet AND 4 000 000 for a 32x32 one, two different programs, both
# exactly the fuel, while the answers stayed right because the guard threw the work away. `un` IS
# `pc < n`, so `match f un` both stops and is a legal scrutinee (a computed Bool is not).
# the step's pair has to be split to reach the cursor, and a computed pair cannot be matched, so
# it is handed to a def whose PARAMETER is that pair
# the LOOP matches the fuel and the pair together. `run` has to take its next cursor from the
# step's RESULT, and the result is a computed `Prog & Array<Elem>` -- which cannot be matched.
# Matching the fuel and the pair in one `match f av:` gives the record as a BINDER, so its `un`
# is matched at a deeper level and the post-step cursor is reachable without splitting anything."""),

  # ---- the CAST arm (19 lines) -- a BUG THAT WAS FOUND (the float-to-int arm). KEEP IT.
  (2169, 2187, """# :134 CAST -- `values[u] = [truncate.get(u.dtype, lambda dt: dt)(u.dtype.const(x))
# for x in src_values[0]]` (ops_python.py:137-138). `DType.const` (dtype.py:84) IS the value
# conversion: `float(val)` for a FLOAT, `bool(val)` for a BOOL, and `int(val)` for an integer --
# python's truncation toward zero. `truncate.get` (dtype.py:289) IS THEN THE RANGE:
# `ctypes.c_int32(...)`/`ctypes.c_uint32(...)`.
#
# the FLOAT-to-integer arm was the FLOAT's own bit pattern. it read
# `F32.bits(F32.trunc(f_of(e)))`, WHICH IS THE BIT PATTERN OF THE FLOAT 1.0 (0x3F800000) and not
# the integer 1 (0x00000001) that `int(1.0)` is. measured 2026-10-26: `f32.bitcast.0`'s OUTPUT
# BUFFER 0 WAS CPYTHON'S `01000000020000000300000004000000...` (the integers 1,2,3,4) and the
# port's was `0000803f0000004000004040000080...` (the floats' own bit patterns). the same arm is
# what `x.abs().cast(dtypes.int32)` goes through, so it also broke `f32.shl.0`, `f32.shr.0` AND
# `f32.cmod.0` -- FOUR of the 29 pinned rows.
# `int(x)` AS THE TWO's-COMPLEMENT BITS OF A 32-BIT INT. `F32.to_u32` truncates toward zero,
# which is half of what is wanted, but it clamps a NEGATIVE TO ZERO: MEASURED 2026-10-26,
# `F32.to_u32(-1.0)` IS 0 AND NOT 4294967295. so the magnitude is taken and the sign is put back
# by the subtraction, which is the two's complement of the magnitude."""),

  # ---- the src index (18 lines) -- the MEASUREMENT and the DEAD-DEF NOTE.
  (1487, 1504, """# a src index: 1-based on the wire, 0-based here, refused when `U32.read` refuses the
# spelling. The bounds check is `Uop.at`'s: an index past the packet answers the bottom, and the
# bottom of an INDEX is the zero this walk then reads.
#
# THE `+1`/`-1` IS THE WHOLE OF `uop_to_index`, and it is the only reason `Prog.dispatch`'s END
# arm (:2025) may read `Uop.src1(u)` where ops_python.py:70 reads `i =
# self.uop_to_index[u.src[1]]` -- an INDEX LOOKUP CPython performs at dispatch time. The port
# performs it HERE, once, for every src, because the wire's `<src>` field IS that index:
# `ops_bend.encode` (ops_bend.py:135) builds `idx = {u: i for i, u in enumerate(uops)}` -- the
# SAME comprehension ops_python :49 builds -- and writes `str(idx[s]+1)` (ops_bend.py:142).
# MEASURED today, on a real `encode` output: the wire field equals `uop_to_index[src]+1` for every
# src of every uop, and on the END line the port's pc (2 - 1) equals `uop_to_index[END.src[1]]`
# (1). So `Uop.src1(u)` IS that lookup, and it is not an END special case: `Prog.src` and
# `Prog.slot` read every other src the same way. A predecessor of this comment put the claim on
# a def that was DEAD -- it returned `Nil{}` and was called by nothing -- and a comment citing a
# dead def as its evidence is not evidence."""),
]

apply(F, EDITS)
