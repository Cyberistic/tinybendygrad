# ops_bend.bend -- the BEND TARGET: the port of the PORT'S own `ops_bend.py` (the repo root -- upstream tinygrad HAS no `ops_bend.py` AT any revision; it was OURS until the purge c2a66ea41 moved it out of `tinygrad/`), WHICH forks upstream's `tinygrad/runtime/ops_python.py`
#
# THE BEND TARGET ITSELF. Every other port in this repo hands its IR to a
# GPU. This one compiles the port's own IR to Bend source and RUNS it, so the
# port can drive itself -- and, because the Python side is alive, the gate can
# diff the emitted source against CPython's line for line and, when the
# executor builds, execute the result.
#
# THE WIRE, v1.1 (ASCII text, one launch per packet). This is the executor's own
# format, taken from the header of tinybendygrad/runtime/ops_python.bend, which is
# authoritative for the spellings:
#
#   line 1      bendexec1 <nuops> <nbuffers>
#   uop lines   <idx>: <OP> <dtype|-> <arg|-> <src1> <src2> ...     1-based, in post-order
#   buffer ln   <nbytes> <hex-bytes>
#
# <idx> walks the renderer's own uop list in the order it arrives. That list is
# ALREADY in post-order: every uop's srcs sit at a lower index, except Ops.END
# and Ops.BACKEDGE, which point BACK at their Ops.RANGE by construction.
#
# <dtype> is the BARE dtype name -- "i32" "u32" "f32" "bool" "weakint" "void" --
# which is what the executor's to_dtype already parses. Only the four it ports
# (i32 u32 f32 bool) have one; a dtype outside them is that executor's wall 1,
# and wire_dtype raises NotImplementedError naming it rather than emitting a name
# it would refuse or misread.
#
# <arg> is `-` for every op that does not need a payload. Six ops carry one:
#
#   CONST   c:<decimal-int> for an int, f:<8 hex digits, the f32 bit pattern>
#           for a float. The c:/f: prefix is what tells the executor the two
#           weak carriers apart.
#   PARAM   k:param:<nbytes>:<g|l|r|a>. There are no DEFINE_* ops in this
#           tinygrad, so the addrspace rides here. g binds the next packet
#           buffer, r allocates zeros, a reads a `vals` entry. nbytes is
#           max_numel()*dtype.itemsize.
#   BUFFER  k:buffer:<nbytes>. Kernel-local scratch; allocates zeros and
#           consumes NO packet buffer.
#   SPECIAL k:sp:<gidx0|gidx1|gidx2|lidx0|lidx1|lidx2>. u.arg is already that name.
#   LOAD/STORE   k:vec:<max_numel>, `-` when it is 1. ops_python's LOAD and STORE
#           both branch on u.max_numel(), and a real reduce DOES vectorize --
#           measured 4 on LOAD and STORE in the packets under .agents/slop/ --
#           so this cannot be left implicit.
#   INDEX/SHRINK k:idx:<scale>. 0 is the ALU arm; otherwise the BITCAST scale
#           src[0].dtype.itemsize // src[0].src[0].dtype.itemsize; `-` is the
#           plain 1. The image arm needs src[0]'s shape and raises.
#
# <nbuffers> counts the PARAMs of addrspace g or l -- one buffer line each, in
# uop order, because ops_python pops pbufs in exactly that order.
#

# WHAT is ported, DEF BY DEF. THE port'S own defs are in `ops_bend.py` (REPO root; UPSTREAM has no `ops_bend.py` AT any revision) AND fork upstream's `tinygrad/runtime/ops_python.py`, SO every row below names the upstream construct it forks:
#
#   tinygrad/runtime/ops_python.py:186 `supported_dtypes`  LANES  PORTED  `lanes`, `lanes_sorted`
#   tinygrad/dtype.py:60 `name`  wire_dtype  PORTED  `wire_dtype` -- the NAME and the refusal,
#                        message included
#   tinygrad/runtime/ops_python.py:106 `itemsize`  wire_width  PORTED  `wire_width` (node.numel) symbol=__call__
#   tinygrad/runtime/ops_python.py:109 `arg`  wire_arg  PORTED  `wire_arg` -- every arm but the float
#                      CONST's `struct.pack` (WALL 2)
#   tinygrad/runtime/ops_python.py:184 `render`  encode  PORTED  `encode`
#   tinygrad/runtime/ops_python.py:184 `render`  executor  SEAM   the build/cache of the executor
#   tinygrad/runtime/ops_python.py:64 `uops`  UOpLine  PORTED  `Line` symbol=__call__
#   tinygrad/runtime/ops_python.py:107 `pargs`  is_buf  PORTED  `is_buf` symbol=__call__
#   tinygrad/runtime/ops_python.py:106 `itemsize`  buf_extent  PORTED  `buf_extent` symbol=__call__
#   tinygrad/runtime/ops_python.py:50 `uops`  parse  PORTED  `parse` symbol=__init__
#   tinygrad/runtime/ops_python.py:49 `__init__`  BendProgram.__init__  PORTED  `prog.of` -- in_bufs AND out_bufs
#   tinygrad/runtime/ops_python.py:55 `__call__`  BendProgram.__call__  PORTED  `prog.call` as a TRUNCATED TRACE
#   tinygrad/runtime/ops_python.py:164 `compile`  BendCompiler.compile  PORTED  `compiler.of` -- pass-through
#   tinygrad/runtime/ops_python.py:166 `PythonRenderer`  BendRenderer  PORTED  `render`, `has_local`
#   tinygrad/runtime/ops_python.py:189 `__init__`  BendDevice.__init__  SEAM   HostAllocator + Compiled wiring
#

# THE SPLIT, stated once and then obeyed. A def here EITHER builds the argument
# of ONE launch (pure, and the gate checks it) OR records that step in the trace
# (and the gate checks the ORDER). There is no third kind. That is what puts the
# `raise` in the trace, so a refusal appears as a truncated trace and no step
# needs a guard of its own.
#
# THE emitted text is a gate, NOT a boolean. `String.concat` drops a literal
# silently, so a boolean about a string can be true while the string is wrong.
# `bend_encode_*` rows print the packet's own lines, and `emit.diff` prints the
# whole packet. Those rows are TEXT; the diff against CPython's packet is the
# check, and it is line for line.
#

# THE THREE WALLS.
#
# 1. THE Op NUMBER is not ported, AND that is the point. Python writes
#    `u.op.name`, a STRING, on the wire, and `parse` reads op names back. So in
#    this file `op` is a String everywhere and there is NO `Ops` enum table to
#    transcribe. This is not a simplification: it is the same information
#    Python carries, and it means a wrong enum ordinal cannot produce a
#    silently wrong packet. The six ops with an arg are named by
#    `arg_kind(op)`.
#    The cost is stated rather than hidden: `Ops`-NUMBERED traces elsewhere in
#    this repo cannot be compared with these.
#
# 2. THE FLOAT CONST's `struct.pack('<f', u.arg).hex()` (:118). Bend's F32 has
#    no `to_bits` and no bitcast (`references/bend/bend2/base.bend` exports
#    `F32.min/max/clamp/lerp/square/hypot/round/pi/from_nat/to_nat` and
#    nothing that reads the representation), so the eight hex digits cannot be
#    computed here. `wire_arg` still OWNS THE ROUTING -- it is the only thing
#    that knows a float CONST is the `f:` arm -- and takes the digits from the
#    node. The row `bend_arg_const_float_is_f` pins the prefix and
#    `bend_wall_float_bits` records the seam.
#    TODO(p3) THE port's `runtime/ops_bend.bend` HEADER  symbol= -- the FLOAT CONST's `struct.pack('<f', u.arg).hex()` -- UPSTREAM'S `runtime/ops_bend.py` IS gone at this PIN, so this is a claim about the PORT's own encoder.
#
# 3. THE FFI SEAMS, named with their Python lines. None of these is an
#    `@extern`; they are steps in the trace, so the trace stays greppable.
#      :150-164  `executor()`  -- exists(), stat(), hashlib, subprocess.run
#               over ./bin/bend, os.replace. The build and the cache.
#      tinygrad/helpers.py:575 symbol=to_mv  `to_mv(b, nb)` -- a ctypes memoryview over a device pointer.
#      :217      `pkt.write_text(...)` -- the PACKET.in on disk.
#      :222      `subprocess.run([exe, pkt, gx, gy, gz, vals...])` -- the launch.
#      :225      `read_text()` of PACKET.out.
#      :228      `views[i][:] = bytes.fromhex(...)` -- the copy-back.
#      :232      `src.encode()` -- BendCompiler, which is a pass-through.
#      tinygrad/runtime/ops_python.py:56 symbol=__call__  `time.perf_counter()` -- the returned duration. Not modelled:
#               the only thing this port does with a time is hand it back, and
#               no caller of `Program.__call__` reads it (tinygrad/engine/realize.py:167 -- the `ets.append` line --
#               discards it).
#
# `ctypes` is not one of the seams: `to_mv` is the only ctypes in the file, and
# it is a VIEW over bytes the caller already owns. The port keeps the extent,
# which is what `in_bufs` is, and drops the pointer.
#

# `has_local = False` (tinygrad/renderer/__init__.py:68 symbol=has_local) is a CONSTANT the scheduler consults
# (opt/heuristic.py:163), so it is a `def` and not a field: a def nothing calls
# is invisible to every other check, and `bend_has_local` is its only reader.
#

import ../helpers.bend as H

# THE LANE TABLE. `LANES: frozenset = {int, uint, float, bool}` -- four lanes,
# plus the three names ops_bend.py passes through untouched because the
# executor parses them (`to_dtype` is `getattr(dtypes, name.lower())`).

def is_lane(+dt: String) -> Bool:
  Bool.or(String.eq(dt, "i32"), String.eq(dt, "u32"))

def lanes(+dt: String) -> Bool:
  Bool.or(is_lane(dt), Bool.or(String.eq(dt, "f32"), String.eq(dt, "bool")))

# the three names wire_dtype emits WITHOUT a lane check, :100.
def lane_free(+dt: String) -> Bool:
  Bool.or(String.eq(dt, "void"), Bool.or(String.eq(dt, "weakint"),
                                         String.eq(dt, "weakfloat")))

# `sorted(LANES, key=str)` :101, verbatim: dtypes.bool, dtypes.f32, dtypes.i32,
# dtypes.u32. Sorted by the SPELLING, which is what `key=str` gives.
def LANES_SORTED() -> String: "dtypes.bool dtypes.f32 dtypes.i32 dtypes.u32"

# `wire_dtype(u) -> str` and the NotImplementedError it raises, as ONE value:
# `ok=False` carries the MESSAGE, because "BEND v1 has no lane for X (on Y); it
# has Z" is a decision with a text and a gate that only compares booleans cannot
# see the text.
type Res is Data:
  Res{ok: Bool, s: String}

def wire_dtype(+dt: String, op: String) -> Res:
  Bool.pick(Res, Bool.or(lanes(dt), lane_free(dt)), Res{True{}, dt},
    Res{False{}, String.concat([
      "BEND v1 has no lane for dtypes.", dt, " (on ", op, "); it has ",
      LANES_SORTED()])})

# THE NODE. ONE UOp, reduced to the six things ops_bend.py's encoder reads off
# it and nothing else -- which is `UOpLine` (:169) plus the three fields `parse`
# throws away. Positions in `srcs` are 1-based and index THIS list, so `src0`
# is a lookup and the packet's own `<src1> <src2> ...` needs no translation.
#
#   op     u.op.name                    -- a String, because that is what the wire
#                                        carries and what `parse` reads back.
#   dt     u.dtype.name
#   sz     u.dtype.itemsize
#   numel  u.max_numel(), 1 for the ops with no shape (:103-108)
#   addr   u.addrspace.name, or "-" for the ops that have none
#   arg    u.arg as TEXT, EXCEPT a CONST where it is the payload digits the
#          `c:`/`f:` prefix is attached to: decimal for an int, the eight f32
#          bit-pattern hex digits for a float (WALL 2).
#   isint  isinstance(u.arg, int) -- the `c:`/`f:` discriminator, :118
#   srcs   1-based positions
#   shape  s._shape rendered, ONLY because `is_image_shape` (:126) reads it.
#          It is `""` for a shape that is not an image shape, so the reader is
#          `N.is_image` and the string is not otherwise consulted.

type N is Data:
  N{op: String, dt: String, sz: U32, numel: U32, addr: String, arg: String,
    isint: Bool, srcs: List<&2, U32>, ndim: U32, last: U32, shape: String}

def N.ndim(n: N) -> U32:
  match n:
    case N{op, dt, sz, numel, addr, arg, isint, srcs, ndim, last, shape}: ndim

def N.last(n: N) -> U32:
  match n:
    case N{op, dt, sz, numel, addr, arg, isint, srcs, ndim, last, shape}: last

def N.op(n: N) -> String:
  match n:
    case N{op, dt, sz, numel, addr, arg, isint, srcs, ndim, last, shape}: op

def N.dt(n: N) -> String:
  match n:
    case N{op, dt, sz, numel, addr, arg, isint, srcs, ndim, last, shape}: dt

def N.sz(n: N) -> U32:
  match n:
    case N{op, dt, sz, numel, addr, arg, isint, srcs, ndim, last, shape}: sz

def N.numel(n: N) -> U32:
  match n:
    case N{op, dt, sz, numel, addr, arg, isint, srcs, ndim, last, shape}: numel

def N.addr(n: N) -> String:
  match n:
    case N{op, dt, sz, numel, addr, arg, isint, srcs, ndim, last, shape}: addr

def N.arg(n: N) -> String:
  match n:
    case N{op, dt, sz, numel, addr, arg, isint, srcs, ndim, last, shape}: arg

def N.isint(n: N) -> Bool:
  match n:
    case N{op, dt, sz, numel, addr, arg, isint, srcs, ndim, last, shape}: isint

def N.srcs(n: N) -> List<&2, U32>:
  match n:
    case N{op, dt, sz, numel, addr, arg, isint, srcs, ndim, last, shape}: srcs

def N.shape(n: N) -> String:
  match n:
    case N{op, dt, sz, numel, addr, arg, isint, srcs, ndim, last, shape}: shape

# `u.max_numel()` with the `except RuntimeError: return 1` of :103-108 already
# folded in by the oracle. A def so the BARRIER arm has a reader: the table says
# 1 and the row below pins that a shape-carrying node is the ONLY other answer.
def wire_width(n: N) -> U32: N.numel(n)

# The bottom node, so `Ns.at` is TOTAL the way `Arena.node` is. A position the
# packet names is always in range; the bottom is what an out-of-range lookup
# reads, and its op name is `-` which no arm of wire_arg matches.
def N.bottom() -> N: N{"-", "-", 0, 1, "-", "", False{}, Nil{}, 0, 0, ""}

# THE NODE LIST. `self.uops` -- the renderer's own list, already in post-order.

# `i` is a WIRE POSITION -- 1-based, the number `encode` writes -- while a Bend
# list is 0-based, so the two differ by one. MEASURED: with `U32.to_nat(i)` the
# first read of every list landed on its second element.
def Ns.at(+us: List<&2, N>, +i: U32) -> N:
  Maybe.default(&2, N, List.get(&2, N, us, U32.to_nat(U32.sub(i, 1))), N.bottom())

# `self.src[i]`, with 0 for the IndexError Python raises on a short tuple.
def Ns.src(+us: List<&2, N>, +i: U32, k: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, N.srcs(Ns.at(us, i)), U32.to_nat(k)), 0)

# `self.src[0]` -- the one ops_bend.py writes most (:116, :124).
def Ns.src0(+us: List<&2, N>, i: U32) -> U32: Ns.src(us, i, 0)

def Ns.n(+us: List<&2, N>) -> U32:
  U32.from_nat(List.length(&2, N, us))

# `is_image_shape(shape)` :126 -- `shape is not None and len(shape)==3 and
# shape[-1]==4`. The two facts it reads are `ndim` and `last`, and the port
# computes the predicate itself: it is the DECISION, and a decision handed over
# by the seam is a decision the gate cannot check. What the seam supplies is
# `shape`, the repr, because the refusal message at :126 interpolates
# `s._shape` verbatim and Python's repr is `(2, 3, 4)`.

def is_image_shape(ndim: U32, last: U32) -> Bool:
  Bool.and(U32.is_eq(ndim, 3), U32.is_eq(last, 4))

# `wire_arg(u) -> str` :110-131, and the NotImplementedError at :126, as one
# `Res`. Every arm of :114-131 is ported; the float CONST's eight hex digits
# are WALL 2 and arrive in `N.arg`.
#
# THE ORDER IS PORTED AS THE ORDER, and it is load-bearing: :125 tests
# `s.addrspace is ALU`, :126 tests `is_image_shape`, :127 tests
# `s.op is BITCAST`. So a BITCAST over an image shape raises at :126 and never
# reaches :127, and an ALU-valued src[0] answers `k:idx:0` whatever its shape.
# `bend_arg_bitcast_image` and `bend_arg_alu_first` are the rows that separate
# the three.

# Which arm owns an op. 0 is "no payload", and every op Python never names
# answers "-". INDEX and SHRINK share 5, LOAD and STORE share 6, because Python
# writes them `u.op in (...)`.
def kind.of(+op: String) -> U32:
  Bool.pick(U32, String.eq(op, "BUFFER"), 1,
    Bool.pick(U32, String.eq(op, "PARAM"), 2,
      Bool.pick(U32, String.eq(op, "CONST"), 3,
        Bool.pick(U32, String.eq(op, "SPECIAL"), 4,
          Bool.pick(U32, Bool.or(String.eq(op, "INDEX"), String.eq(op, "SHRINK")), 5,
            Bool.pick(U32, Bool.or(String.eq(op, "LOAD"), String.eq(op, "STORE")), 6, 0))))))

# :116 `letter = "a" if u.addrspace is AddrSpace.ALU else
#          {"GLOBAL": "g", "REG": "r"}[u.addrspace.name]`.
#
# THE `l` ARM IS ABSENT, and that is a FINDING rather than a simplification.
# ops_bend.py:112-113 says "There is no `l` PARAM in practice -- ops_python gives
# LOCAL to BUFFER -- but the executor parses it, so it is spelled rather than
# refused", and :36 of the file's own header lists `k:param:<nbytes>:<g|l|r|a>`.
# The dict at :116 has keys GLOBAL and REG only, so a LOCAL PARAM raises
# `KeyError: 'LOCAL'` -- MEASURED in CPython, not reasoned about. The `l` letter
# is therefore UNREACHABLE, and a port that spelled it would be spelling
# something the Python does not do. `bend_arg_local_param` records the KeyError.
#   0 = a, 1 = g, 2 = r, 3 = the KeyError
def letter.of(+addr: String) -> U32:
  Bool.pick(U32, String.eq(addr, "ALU"), 0,
    Bool.pick(U32, String.eq(addr, "GLOBAL"), 1,
      Bool.pick(U32, String.eq(addr, "REG"), 2, 3)))

def letter_str(+k: U32) -> String:
  Bool.pick(String, U32.is_eq(k, 0), "a",
    Bool.pick(String, U32.is_eq(k, 1), "g", Bool.pick(String, U32.is_eq(k, 2), "r", "?")))

# :114 `f"k:buffer:{u.max_numel()*u.dtype.itemsize}"`.
def buf_arg(+n: N) -> String:
  "k:buffer:" ++ U32.show(U32.mul(wire_width(n), N.sz(n)))

# :117 `f"k:param:{u.max_numel()*u.dtype.itemsize}:{letter}"`.
def param_arg(+n: N) -> String:
  "k:param:" ++ U32.show(U32.mul(wire_width(n), N.sz(n))) ++ ":" ++ letter_str(letter.of(N.addr(n)))

# :118 `f"c:{u.arg:d}" if isinstance(u.arg, int) else f"f:{struct.pack('<f', u.arg).hex()"`.
# The PREFIX is the whole of what this port owns -- it is what tells the executor
# the two weak carriers apart -- and the digits are WALL 2.
def const_arg(+n: N) -> String:
  Bool.pick(String, N.isint(n), "c:" ++ N.arg(n), "f:" ++ N.arg(n))

# :119 `f"k:sp:{u.arg}"`.
def special_arg(+n: N) -> String: "k:sp:" ++ N.arg(n)

# :125-127, read off `s = u.src[0]`.
def idx_is_alu(+s: N) -> Bool: String.eq(N.addr(s), "ALU")
def idx_is_bitcast(+s: N) -> Bool: String.eq(N.op(s), "BITCAST")

# :127 `s.dtype.itemsize // s.src[0].dtype.itemsize` -- the BITCAST scale. Read
# along the INDEX's own chain, i -> src0 = s -> src0 = s.src[0], which is the
# same two hops Python makes and needs no position of its own.
def idx_scale(+us: List<&2, N>, +i: U32) -> U32:
  U32.div(N.sz(Ns.at(us, Ns.src0(us, i))), N.sz(Ns.at(us, Ns.src0(us, Ns.src0(us, i)))))

# :126 the refusal, verbatim except for the shape repr the seam supplies.
def idx_image_msg(+s: N) -> String:
  "BEND v1 has no image addressing for INDEX over " ++ N.shape(s)

# the whole INDEX/SHRINK arm :123-128.
def idx_arg(+us: List<&2, N>, +i: U32) -> Res:
  Bool.pick(Res, idx_is_alu(Ns.at(us, Ns.src0(us, i))), Res{True{}, "k:idx:0"},
    Bool.pick(Res, is_image_shape(N.ndim(Ns.at(us, Ns.src0(us, i))),
                                  N.last(Ns.at(us, Ns.src0(us, i)))),
      Res{False{}, idx_image_msg(Ns.at(us, Ns.src0(us, i)))},
      Bool.pick(Res, idx_is_bitcast(Ns.at(us, Ns.src0(us, i))),
        Res{True{}, "k:idx:" ++ U32.show(idx_scale(us, i))}, Res{True{}, "-"})))

# :130 `return "-" if (n := wire_width(u)) == 1 else f"k:vec:{n}"`.
def vec_arg(+n: U32) -> String:
  Bool.pick(String, U32.is_eq(n, 1), "-", "k:vec:" ++ U32.show(n))

# `wire_arg(u)` :110-131, arm by arm, IN PYTHON'S ORDER.
def wire_arg(+us: List<&2, N>, +i: U32) -> Res:
  Bool.pick(Res, U32.is_eq(kind.of(N.op(Ns.at(us, i))), 1), Res{True{}, buf_arg(Ns.at(us, i))},
    Bool.pick(Res, U32.is_eq(kind.of(N.op(Ns.at(us, i))), 2), Res{True{}, param_arg(Ns.at(us, i))},
      Bool.pick(Res, U32.is_eq(kind.of(N.op(Ns.at(us, i))), 3), Res{True{}, const_arg(Ns.at(us, i))},
        Bool.pick(Res, U32.is_eq(kind.of(N.op(Ns.at(us, i))), 4), Res{True{}, special_arg(Ns.at(us, i))},
          Bool.pick(Res, U32.is_eq(kind.of(N.op(Ns.at(us, i))), 5), idx_arg(us, i),
            Bool.pick(Res, U32.is_eq(kind.of(N.op(Ns.at(us, i))), 6),
              Res{True{}, vec_arg(wire_width(Ns.at(us, i)))}, Res{True{}, "-"}))))))

# `is_buf(arg)` :177 -- `arg.startswith("k:param:") and
# arg.rsplit(":", 1)[1] in ("g", "l")`. THE `l` NEVER MATCHES, for the reason
# above: no PARAM can carry it. The test is ported as Python writes it and the
# row `bend_buf_l_never` says which inputs reach it.
#
# `buf_extent(arg)` :178 -- `int(arg.split(":")[2])`, the SECOND colon field of
# `k:param:<nbytes>:<letter>`, which is the byte count. The 0 is the IndexError
# Python raises on a field list shorter than three, which `is_buf` has already
# excluded.

def is_buf(+arg: String) -> Bool:
  Bool.and(String.starts_with(arg, "k:param:"),
    Bool.or(String.ends_with(arg, ":g"), String.ends_with(arg, ":l")))

def field2(+arg: String) -> String:
  Maybe.default(&2, String, List.get(&2, String, String.split(arg, ':'), 2n), "")

def buf_extent(arg: String) -> U32: Maybe.default(&2, U32, U32.read(field2(arg)), 0)

# `encode(uops) -> str` :133-145.
#
# THE two asserts are ported as refusals, which is the only way a refusal can
# appear in this file: `encode` returns a `Res`, and `ok=False` carries the
# AssertionError's own text.
#
#   :139  `assert s in idx, f"{u.op.name} reads {s.op.name}, which is not in the uop list"`
#         A src position of 0 is the port's spelling of "not in idx": `Ns.src`
#         answers 0 for a short src tuple, and no real UOp sits at position 0.
#   :143  `assert idx[s] < i, f"{u.op.name} at {i} reads {s.op.name} at {idx[s]}: not post-order"`
#         `i` there is the 0-based `enumerate` index, so it is the position
#         MINUS ONE, while the line is written with `i+1`. Both are ported, and
#         they differ by one because that is what the Python says.
#
# `.rstrip()` at :144 is `rstrip1`: the only space it can ever remove is the one
# between <arg> and an EMPTY src list, because every other field is non-empty.

# `is_buf(wire_arg(u))` -- the test is on the ARG, not on the addrspace, because
# :140 counts what ops_python's `pbufs.pop(0)` would pop and :200 filters the
# same way. `a`, `r` and `-` all lose; `g` wins.
def Res.s(r: Res) -> String:
  match r:
    case Res{ok, s}: s

def Res.ok(r: Res) -> Bool:
  match r:
    case Res{ok, s}: ok

def Ns.binds_buffer(us: List<&2, N>, i: U32) -> Bool: is_buf(Res.s(wire_arg(us, i)))

# :140 `nbufs = sum(u.op is Ops.PARAM and u.addrspace is not AddrSpace.ALU for u in uops)`.
# THE FOLDS CARRY TWO LISTS, and that is a bug this file's own gate found. `us`
# is the WHOLE list and `rest` is the tail being walked. Threading the tail AS
# `us` looks natural and is WRONG: `Ns.at(us, i)` and `ls_at(ls, i)` are 1-based
# over the WHOLE list, so a tail-as-us fold reads one element late at every step.
# MEASURED on `packet-tiny.txt` (three `k:param:4:g` lines): the one-list fold
# answered `bendexec1 13 2` where CPython's header says 3, and `lines.go` refused
# the whole packet with `- reads -, which is not in the uop list`. `count_bufs`,
# `lines.go` and `out_go` all carry the pair for that reason.
def count_bufs(+us: List<&2, N>, +rest: List<&2, N>, +i: U32, +acc: U32) -> U32:
  match rest:
    case Nil{}:
      acc
    case n <> t:
      count_bufs(us, t, U32.add(i, 1),
        U32.add(acc, Bool.to_u32(Ns.binds_buffer(us, i))))

# `' '.join(str(idx[s]+1) for s in u.src)` -- the positions are already 1-based,
# so `str(idx[s]+1)` is `U32.show(s)` and the join is all that is left.
# PREPEND, then reverse. `List.append(a, A, xs, ys)` is `xs ++ ys`, so
# appending and reversing yields the REVERSED order -- MEASURED: the first
# version emitted `6: INDEX f32 - 5 2` where CPython's packet line is
# `6: INDEX f32 - 2 5`, on every line of every packet.
def src_text.go(+xs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case x <> t: src_text.go(t, List.append(&2, String, [U32.show(x)], acc))

def src_text(+xs: List<&2, U32>) -> String:
  String.join(src_text.go(xs, Nil{}), " ")

# :139's text. The src position is 0 or past the end, so the node read is
# `N.bottom` and its op name is `-`.
def notin_msg(+us: List<&2, N>, i: U32, s: U32) -> String:
  N.op(Ns.at(us, i)) ++ " reads " ++ N.op(Ns.at(us, s))
  ++ ", which is not in the uop list"

def order_msg(+us: List<&2, N>, i: U32, +s: U32, i0: U32) -> String:
  N.op(Ns.at(us, i)) ++ " at " ++ U32.show(i0) ++ " reads " ++ N.op(Ns.at(us, s))
  ++ " at " ++ U32.show(s) ++ ": not post-order"

# :143 over one node's srcs. `ok=False` is the not-post-order refusal.
def check_srcs(+us: List<&2, N>, +i: U32, +xs: List<&2, U32>, +i0: U32) -> Res:
  match xs:
    case Nil{}: Res{True{}, ""}
    case s <> t:
      Bool.pick(Res, Bool.or(U32.is_eq(s, 0), U32.is_gt(s, Ns.n(us))),
        Res{False{}, notin_msg(us, i, s)},
        Bool.pick(Res, U32.is_ge(s, i), Res{False{}, order_msg(us, i, s, i0)},
          check_srcs(us, i, t, i0)))

def rstrip1(+s: String) -> String:
  Bool.pick(String, String.ends_with(s, " "),
    String.take(s, Nat.sub(String.length(s), 1n)), s)

# ONE LINE :144, minus the rstrip. The dtype refusal wins over the arg refusal
# because :144 evaluates `wire_dtype(u)` before `wire_arg(u)` left to right.
def line_text(+us: List<&2, N>, +i: U32) -> Res:
  Bool.pick(Res, Res.ok(wire_dtype(N.dt(Ns.at(us, i)), N.op(Ns.at(us, i)))),
    Bool.pick(Res, Res.ok(wire_arg(us, i)),
      Res{True{}, rstrip1(String.concat([U32.show(i), ": ", N.op(Ns.at(us, i)),
        " ", Res.s(wire_dtype(N.dt(Ns.at(us, i)), N.op(Ns.at(us, i)))), " ",
        Res.s(wire_arg(us, i)), " ", src_text(N.srcs(Ns.at(us, i)))]))},
      Res{False{}, Res.s(wire_arg(us, i))}),
    wire_dtype(N.dt(Ns.at(us, i)), N.op(Ns.at(us, i))))

# :141-145, whole. `nbufs` is the SECOND header field, so it is computed first
# and the header is the head of the accumulator.
def header(+us: List<&2, N>) -> String:
  String.concat(["bendexec1 ", U32.show(Ns.n(us)), " ",
    U32.show(count_bufs(us, us, 1, 0))])

# The emitted LINE, unwrapped. A named def and not `Res.s(line_text(...))`
# inline: a `[Res.s(...)]` literal inside `List.append` infers `List<&1, String>`
# against an `xs` of `&2`, which the checker reports as "expected Res".
def line_of(+us: List<&2, N>, +i: U32) -> String: Res.s(line_text(us, i))

def lines.go(+us: List<&2, N>, +rest: List<&2, N>, +i: U32,
             +acc: List<&2, String>) -> Res:
  match rest:
    case Nil{}: Res{True{}, String.join(acc, "\n") ++ "\n"}
    case n <> t:
      Bool.pick(Res, Res.ok(check_srcs(us, i, N.srcs(n), U32.sub(i, 1))),
        Bool.pick(Res, Res.ok(line_text(us, i)),
          lines.go(us, t, U32.add(i, 1),
            List.append(&2, String, acc, [line_of(us, i)])),
          line_text(us, i)),
        check_srcs(us, i, N.srcs(n), U32.sub(i, 1)))

def encode(+us: List<&2, N>) -> Res:
  lines.go(us, us, 1, [header(us)])

# `parse(packet) -> (list[UOpLine], int)` :180-190, and `UOpLine` :169-173.
#
# THE DECODER IS NOT HERE ON PURPOSE, and the file says why at :181-182: "The
# executor decodes the SEMANTICS; this only recovers the shape BendProgram needs
# to marshal buffers, which is why it stops at op names and index lists." So
# `parse` gives back `Line{op, dt, arg, srcs}` and the semantics are the
# executor's wall, not this file's.
#
# `splitlines()` vs `split("\n")`: `encode` always ends the packet with "\n"
# (:145) and `String.split` KEEPS the empty field after it where `splitlines`
# does not, so `drop_final` is the whole difference, and it is one field.
#
# WHAT IS NOT PORTED: `_, nuops, nbufs = head.split()` at :185 raises ValueError
# on a header that is not exactly three fields. `parse` here answers 0 for both
# counts instead, so a malformed header is a WRONG ANSWER and not a refusal. That
# is stated because it is the one place `parse` is weaker than the Python, and
# `bend_parse_short_header` is the row that records it.

type Line is Data:
  Line{op: String, dt: String, arg: String, srcs: List<&2, U32>}

def Line.of(op: String, dt: String, arg: String, srcs: List<&2, U32>) -> Line:
  Line{op, dt, arg, srcs}

def Line.op(l: Line) -> String:
  match l:
    case Line{op, dt, arg, srcs}: op

def Line.dt(l: Line) -> String:
  match l:
    case Line{op, dt, arg, srcs}: dt

def Line.arg(l: Line) -> String:
  match l:
    case Line{op, dt, arg, srcs}: arg

def Line.srcs(l: Line) -> List<&2, U32>:
  match l:
    case Line{op, dt, arg, srcs}: srcs

# the header, `nbufs`, and the lines, in ONE record: Bend refuses to destructure
# a computed product, so a parser that returns a pair returns a triple here.
type Pkt is Data:
  Pkt{ok: Bool, msg: String, nbufs: U32, lines: List<&2, Line>}

def Pkt.of(ok: Bool, msg: String, nbufs: U32, lines: List<&2, Line>) -> Pkt:
  Pkt{ok, msg, nbufs, lines}

def Pkt.ok(p: Pkt) -> Bool:
  match p:
    case Pkt{ok, msg, nbufs, lines}: ok

def Pkt.msg(p: Pkt) -> String:
  match p:
    case Pkt{ok, msg, nbufs, lines}: msg

def Pkt.nbufs(p: Pkt) -> U32:
  match p:
    case Pkt{ok, msg, nbufs, lines}: nbufs

def Pkt.lines(p: Pkt) -> List<&2, Line>:
  match p:
    case Pkt{ok, msg, nbufs, lines}: lines

def fld0(xs: List<&2, String>) -> String:
  Maybe.default(&2, String, List.get(&2, String, xs, 0n), "")

def fld1(xs: List<&2, String>) -> String:
  Maybe.default(&2, String, List.get(&2, String, xs, 1n), "")

def fld2(xs: List<&2, String>) -> String:
  Maybe.default(&2, String, List.get(&2, String, xs, 2n), "")

def fld3(xs: List<&2, String>) -> String:
  Maybe.default(&2, String, List.get(&2, String, xs, 3n), "")

# THE off-BY-ONE, AND it is the real wall. `take1` is `take_nat(xs, 1n)` and it
# MUST answer exactly one field -- `header_only` joins the result and splits it on
# ' ', so a two-field answer glues the header onto the first uop line and every
# field after it shifts by one token.
#
# The original armed `case h <> t 0n: [h]`, which takes ONE ELEMENT WHEN THE COUNT
# IS ALREADY SPENT: `take_nat(xs, 1n)` matched `1n+np` with `np = 0n`, took `h`,
# then recursed `take_nat(t, 0n)` which took `h2` as well. MEASURED:
# `header_only` answered ["bendexec1", "13", "31:", "PARAM", ...] -- "3" and "1:"
# glued into "31:" -- so `dec` read it as 0 and `bend_parse_nbufs=0`,
# `bend_prog_*_nbufs_ok=False` and `bend_call_*_refused=False`.
#
# SO the header'S wall 4 WAS the wrong DEF. It blamed `String.split(s, NLCH())`,
# and the split is fine on this substrate (MEASURED: it answers four fields for
# "a\nb\nc\n"). The wall was `take_nat`'s spent-count arm.
def take_nat(+xs: List<&2, String>, n: Nat) -> List<&2, String>:
  match xs n:
    case Nil{} _:
      Nil{}
    case _ <> _ 0n:
      Nil{}
    case Nil{} 1n+np:
      Nil{}
    case h <> t 1n+np:
      List.append(&2, String, [h], take_nat(t, np))

# `body[:int(nuops)]` :187, and `raw` -- the first line, :183.
def take1(+xs: List<&2, String>) -> List<&2, String>: take_nat(xs, 1n)

# The field after the packet's final "\n", which `encode` always writes (:145)
# and which is therefore always empty. Dropping it UNCONDITIONALLY is exactly
# what `splitlines` does to a packet `encode` wrote; the emptiness is not tested
# because a packet whose last field is non-empty is not one `encode` produced,
# and saying so is cheaper than a second field for one bit.
# THE trailing empty field, DROPPED from the end -- AND this is a bug fix, not a
# spelling. The original dropped the HEAD (`case _ <> t: t`), which for
# `"4 a\n4 b\n4 c\n"` answers ["4 b", "4 c"] -- one line lost and the first
# line wrong. MEASURED on the first per-buffer run: `ms_b0_got` read the SECOND
# buffer's line and `ms_b2_got` read the trailing empty. The rows were doing their
# job; they caught a def that the earlier truncated single-row verdict could not
# see, because it compared a prefix with a prefix.
#
# THE HEAD IS removed and then the list is rebuilt, because there is no
# `List.drop_last`: the walk keeps the previous field and rebuilds.
# THE TAIL LEADS, and that is forced: arguments are read left to right and the
# call must be DECREASING on a STRUCTURALLY MATCHED column (MEASURED: "expected a
# decreasing self-call"). A computed `h` is not structural -- this file's own note
# says a call "shrinks no column and cannot be the fuel".
# `acc ++ [prev]`: APPEND, NO REVERSE. This took four attempts and each failure was
# a DISTINCT measurable wrong answer, which is why all four are recorded here:
#   (1) `prev` never updated, so every field was the first one -- MEASURED: all
#       three `ms_b*_got` rows read `4 00004040`.
#   (2) the walk seeded the accumulator with the whole list AND re-walked the tail,
#       so every field was duplicated -- MEASURED, the same three rows again.
#   (3) prepending with a trailing `List.reverse` came back 2, 1, 0 -- MEASURED:
#       `ms_b0_got` read `4 00000040` and `ms_b2_got` read `4 00004040`.
#   (4) dropping `h` from the recursive call left `prev` pinned, so the answer was
#       the LAST field alone -- MEASURED: all three rows read the empty string.
# APPEND WITH NO REVERSE IS RIGHT, and it is what `List.append(a, A, xs, ys)` means:
# `xs ++ ys`. `prev` is emitted on the way PAST it, and the entry seeds `prev` with
# the head while passing the TAIL, so the last field is never emitted.
def drop_final.go(+rest: List<&2, String>, +prev: String, +acc: List<&2, String>) ->
  List<&2, String>:
  match rest:
    case Nil{}:
      acc
    case h <> t:
      drop_final.go(t, h, List.append(&2, String, acc, [prev]))

# AND the entry hands over the tail, so the last field of `xs` never becomes a
# `prev` and is therefore never emitted. An intermediate version seeded the
# accumulator with the WHOLE list and then walked the tail, which DUPLICATED every
# field -- MEASURED, all three `ms_b*_got` rows read `4 00004040`.
def drop_final(xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case h <> t:
      drop_final.go(t, h, Nil{})
def norm2.go(xs: List<&1, String>, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      List.reverse(&2, String, acc)
    case h <> t:
      norm2.go(t, List.append(&2, String, acc, [h]))

def norm2(xs: List<&1, String>) -> List<&2, String>:
  norm2.go(xs, Nil{})

# THE NEWLINE CHARACTER. A `STRING` literal "\n" is a real 0x0A -- MEASURED:
# `String.join(acc, "\n")` emits real newlines -- but a CHAR literal '\n' is the
# two characters `\` and `n`, so `String.split(s, '\n')` split a packet on
# nothing. The fallback is unreachable (the literal has one character) and exists
# only because `Maybe.default` insists on one.
# THE LINE SPLIT IS A WALL IN bend 2.0.34, measured twice. A `STRING` literal
# "\n" IS a real 0x0A -- `String.join(acc, "\n")` emits real newlines and the
# packet rows are byte-identical to CPython's -- and `Char.to_u32(NLCH())` is 10.
# Yet `String.split(s, NLCH())` does not split a packet on its newlines, and a
# hand-written fold over `String.to_list(s)` comparing every char with
# `Char.is_eq(c, NLCH())` matches none of them either. Both routes leave
# `split_all` answering ONE field for a fourteen-line packet.
#
# What that costs, exactly: `parse` (:180) cannot recover the uop lines, so
# `BendProgram.__init__`'s `in_bufs`/`out_bufs` (:200-209) have no input and the
# rows that read them -- `bend_prog_*`, `bend_call_*`, `bend_parse_nbufs` -- are
# RED in this file rather than absent. They are reported as red rather than
# deleted, because a red row that names a wall is information and a deleted row
# is a lie.
#   TODO(p3) runtime/ops_bend.bend:1  symbol= -- split a packet into LINES -- UPSTREAM'S `runtime/ops_bend.py` IS GONE AT THIS PIN, so this is a claim about the PORT's own decoder.
def NLCH() -> Char: Maybe.default(&2, Char, String.get("\n", 0n), ' ')

# THE split, AND the trailing empty field is dropped because `encode` always ends
# the packet with a newline (ops_bend.py:145) and `String.split` KEEPS the empty
# field after it where `splitlines` does not. That one field is the whole
# difference, and `ms_line_count` is the row that would notice if it were not.
def split_lines(text: String) -> List<&2, String>:
  drop_final(String.split(text, NLCH()))

def split_all(s: String) -> List<&2, String>: String.split(s, NLCH())

# `int(s) for s in srcs` :189. `List.map` answers a `List<&1, ...>` when its
# element type is spelled `String`, and `Line.srcs` wants `&2`, so the map is
# written out: it is four lines and it keeps the two lists in one family.
# PREPEND, AND that is the fix. The original APPENDED with
# `List.append(&2, U32, acc, [v])` -- which is `acc ++ [v]` -- and then reversed
# once at the end, so the two composed into a REVERSED answer. MEASURED in
# isolation on CPython's own line: `map_dec(["12:","STORE","void","-","10","11"])`
# answered `0 0 0 0 10 11` printed, i.e. the underlying list was
# `[11, 10, 0, 0, 0, 0]`.
#
# THE MISREAD IS INVISIBLE ON ITS OWN and only showed up one fold downstream:
# `drop4` of that list returned `0 0` where CPython reads `10 11`, so
# `Line.srcs` on a STORE was `[0, 0]` and the :208 chase started from 0. `drop4` of
# the LITERAL `[0, 0, 0, 0, 10, 11]` answered `10 11` correctly in the same run --
# two answers from the same def differing only in where the list came from, which
# is the signature of a fold whose order depends on its input's construction.
def map_dec.go(xs: List<&2, String>, +acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      acc
    case h <> t:
      map_dec.go(t, List.append(&2, U32, acc,
        [Maybe.default(&2, U32, U32.read(h), 0)]))

def map_dec(xs: List<&2, String>) -> List<&2, U32>: map_dec.go(xs, Nil{})

def dec(s: String) -> U32: Maybe.default(&2, U32, U32.read(s), 0)

def header_only(s: String) -> List<&2, String>: String.split(String.join(take1(split_all(s)), ""), ' ')

# :188 `_, op, dtype, arg, *srcs = raw.split()` -- FOUR names before the star, so
# the srcs start at INDEX 4. MEASURED against CPython on `12: STORE void - 10 11`:
#     raw.split()           -> ['12:', 'STORE', 'void', '-', '10', '11']
#     _, op, dt, arg, *srcs -> srcs == ['10', '11']
# The file's old comment claimed "the `<idx>:` prefix and its colon are TWO fields,
# so the srcs start at field 3" -- but `12:` is ONE field, there being no space
# after the colon. So the old `drop3` left the `-` (the arg) in the srcs.
#
# destructured four cells and then appended `[h]` from the WRONG cell, so
# MEASURED: `drop4([9,9,9,9,10,11])` answered `11 10 9` -- the tail, reversed. That
# is why `ls_src0` read 0 and every :208 walk started from the wrong place.
#
# `List.append(a, A, xs, ys)` is `xs ++ ys`, so appending the tail's head onto an
# accumulator and reversing at the end is the ONLY order-preserving spelling, and
# the countdown is a `Nat` whose `1n+p` arm exhausts the list rather than
# saturating (MEASURED: a `U32` countdown with `U32.sub` saturates at 0 and runs
# off the end -- the trap `slice` hit).
# APPEND AND NO REVERSE. `List.append(a, A, xs, ys)` is `xs ++ ys`, so the
# accumulator is already in order and the trailing `List.reverse` was what made it
# backwards -- MEASURED, `drop4([9,9,9,9,10,11])` answered `11 10 0 0` with a
# reverse and `10 11` without. `acc` is returned as it stands.
# THE count is exhausted by the `Nat`, AND the tail is the answer -- collected
# into an accumulator and REVERSED ONCE AT THE END, never returned as the bare
# parameter.
#
# MEASURED, and this is the third distinct wrong answer this def produced, so all
# three are recorded because each was invisible while `out_bufs` was empty:
#   1. APPENDING every element walked past returns the FIRST n, not the tail --
#      MEASURED `drop4([9,9,9,9,10,11])` answered `9 9 9 9`.
#   2. Returning the list PARAMETER directly answers it BACKWARDS -- MEASURED, a
#      skip-then-return `dn` with n=0 on the same literal answered
#      `11 10 9 9 9 9`. So a `List` handed back out of a `match` arm is not the
#      list that went in, and a fold that SKIPS has to REBUILD.
#   3. A `List.reverse` on top of an append turns the answer backwards --
#      MEASURED `11 10` where CPython reads `10 11`.
# So: skip while the countdown lasts, append once it is spent, reverse once at the
# end. `List.append(a, A, xs, ys)` is `xs ++ ys`, which is why appending into an
# accumulator and reversing is the only order-preserving spelling available.
# `List.append(&2, U32, acc, [h])` -- THE ACCUMULATOR FIRST. MEASURED in isolation,
# and this is the single rule behind most of this unit's fold bugs:
#     app([10, 11]) with acc-first append  -> head 10   (in order)
#     all([10, 11]) with [h]-first "append" -> head 11  (REVERSED)
# `List.append(a, A, xs, ys)` is `xs ++ ys`, so the accumulator is `xs` and the new
# element is `ys`; putting the element first PREPENDS and the fold comes out
# backwards. Every fold here uses acc-first and NO `List.reverse`.
def drop_rest(+xs: List<&2, U32>, n: Nat, +acc: List<&2, U32>) -> List<&2, U32>:
  match xs n:
    case Nil{} _:
      acc
    case h <> t 0n:
      drop_rest(t, 0n, List.append(&2, U32, acc, [h]))
    case _ <> t 1n+p:
      drop_rest(t, p, acc)

def drop_nat(xs: List<&2, U32>, n: Nat) -> List<&2, U32>: drop_rest(xs, n, Nil{})

def drop4(xs: List<&2, U32>) -> List<&2, U32>: drop_nat(xs, 4n)

def words(s: String) -> List<&2, String>: String.split(s, ' ')

def one_line.of(+ws: List<&2, String>) -> Line:
  Line.of(fld1(ws), fld2(ws), fld3(ws), drop4(map_dec(ws)))

def one_line(s: String) -> Line: one_line.of(words(s))

def parse_body(+body: List<&2, String>, n: Nat, +acc: List<&2, Line>) -> List<&2, Line>:
  match body:
    case Nil{}:
      List.reverse(&2, Line, acc)
    case h <> t:
      parse_body(t, Nat.sub(n, 1n), List.append(&2, Line, [one_line(h)], acc))

# the `ValueError` at :184, `{head!r}` included: Python's repr of a str is the
# text in single quotes, and the text is a line of the packet under test.
def first_line(+src: String) -> String: String.join(take1(split_all(src)), "")

def bad_head(head: String) -> String:
  "BEND packet must start with bendexec1, got '" ++ head ++ "'"

def parse_bad(+src: String) -> Pkt:
  Pkt.of(False{}, bad_head(first_line(src)), 0, Nil{})

# `head, *body = packet.splitlines()` (:184) -- the HEADER IS DROPPED and then
# `body[:int(nuops)]` (:187) takes the uop lines.
#
# AND this is WHERE THE original `drop_final` WAS doing double duty. It dropped
# the HEAD, not the tail, and `body_of` relied on that: the head of a packet IS the
# header, so `drop_final` was silently the `head, *body` step. MEASURED: fixing
# `drop_final` to actually drop the TRAILING empty field -- which the milestone's
# per-buffer rows required -- turned `bend_parse_l1` from
# `PARAM f32 k:param:4:g` into `13 3 `, i.e. the header parsed as a uop line. The
# two jobs are now SEPARATE and each is named for what it does.
def drop_head(xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case _ <> t:
      t

def body_of(+src: String) -> List<&2, String>:
  take_nat(drop_head(split_lines(src)), U32.to_nat(dec(fld1(header_only(src)))))

def parse_ok(+src: String) -> Pkt:
  Pkt.of(True{}, "", dec(fld2(header_only(src))),
    parse_body(body_of(src), U32.to_nat(dec(fld1(header_only(src)))), Nil{}))

def parse(+src: String) -> Pkt:
  Bool.pick(Pkt, String.starts_with(first_line(src), "bendexec1 "),
    parse_ok(src), parse_bad(src))

# `BendProgram.__init__` :195-209. `self.src = obj.lib.decode()` is the ELF,
# which `BendCompiler.compile` :232 makes IDENTICAL to `encode`'s output
# ("pass-through: the source IS the packet"), so `prog.of` is
# `parse(encode(us))` -- the whole round trip, and the same one the Python runs.
#
# `in_bufs` :200 -- `[buf_extent(u.arg) for u in self.uops if is_buf(u.arg)]`.
# The order is ops_python's `pbufs` order: the PARAMs of addrspace g or l, by
# uop order (:40-41 of the header).
#
# `out_bufs` :204-209 -- the set a STORE can reach. The walk at :208 climbs out
# of INDEX/SHRINK/BITCAST/AFTER/STACK to the buffer PARAM underneath, and
# :209 records the buffer's POSITION, which is `sum(is_buf(x.arg) for x in
# uops[:b])` -- a count of buffer PARAMs before the one found, not the uop
# index. That is the load-bearing line of this def and it is why a position and
# an index cannot be confused here.

type Prog is Data:
  Prog{ok: Bool, msg: String, nbufs: U32, in_bufs: List<&2, U32>,
       out_bufs: List<&2, U32>, us: List<&2, N>}

def Prog.of(ok: Bool, msg: String, nbufs: U32, in_bufs: List<&2, U32>,
            out_bufs: List<&2, U32>, us: List<&2, N>) -> Prog:
  Prog{ok, msg, nbufs, in_bufs, out_bufs, us}

def Prog.ok(p: Prog) -> Bool:
  match p:
    case Prog{ok, msg, nbufs, in_bufs, out_bufs, us}: ok

def Prog.msg(p: Prog) -> String:
  match p:
    case Prog{ok, msg, nbufs, in_bufs, out_bufs, us}: msg

def Prog.nbufs(p: Prog) -> U32:
  match p:
    case Prog{ok, msg, nbufs, in_bufs, out_bufs, us}: nbufs

def Prog.in_bufs(p: Prog) -> List<&2, U32>:
  match p:
    case Prog{ok, msg, nbufs, in_bufs, out_bufs, us}: in_bufs

def Prog.out_bufs(p: Prog) -> List<&2, U32>:
  match p:
    case Prog{ok, msg, nbufs, in_bufs, out_bufs, us}: out_bufs

# `self.src` :196 -- `obj.lib.decode()`, and `BendCompiler.compile` :232 makes
# the ELF IDENTICAL to `encode`'s output, so the source IS the encoding. This
# reader is the whole of the packet for `__call__`: what the seam writes to
def Prog.us(p: Prog) -> List<&2, N>:
  match p:
    case Prog{ok, msg, nbufs, in_bufs, out_bufs, us}: us

# PACKET.in is `Prog.src` and nothing else.
def Prog.src(p: Prog) -> String: Res.s(encode(Prog.us(p)))

# THE CHAIN WALK AT :208 IS NOT A LOOP HERE, and the reason is measured: Bend
# descends only on a structurally MATCHED column
# (references/bend/tests/halt/threaded_state_after.bend writes
# `case 1n+p: go(p, acc+1)`), so `ls_src0(ls, p)` -- a call -- shrinks no column
# and cannot be the fuel. Re-deriving the walk upward answers the same question
# without a descent:
#
#   base[j] = the largest k <= j whose op is NOT in the chain set
#
# which is what `while uops[b].op in {…}: b = uops[b].srcs[0]-1` converges to,
# because the chain only ever moves DOWN the post-order list. `bases.go` is a
# fold over the list tail, so it needs no descent at all.
#
# The one difference is a list whose EVERY prefix is a chain op. Python's `b`
# would go to -1 and read `uops[-1]`, i.e. the LAST line; `base[j]` is 0 there,
# and `ls_at` answers the bottom line, whose arg is "-" and which `is_buf`
# rejects. So a packet whose first line is a chain op gets no write-back instead
# of a wrong one. `bend_prog_base_zero` is the row that records it.
def ls_at(+ls: List<&2, Line>, i: Nat) -> Line:
  Maybe.default(&2, Line, List.get(&2, Line, ls, i), Line.of("-", "-", "-", Nil{}))

# `self.uops[b].srcs[0]` (:208) -- THE HEAD, and `List.get` is not reading it.
# MEASURED: `Line.srcs` of the STORE at 0-based 11 is `10 11` (correct, and the
# `drop4` rows hold it), yet `ls_src0` over the same line answered `11`. The list
# came out of `drop4`'s accumulator and is consumed here one position late.
#
# THE HEAD IS TAKEN BY DESTRUCTURING, which is the rule the whole file obeys and the
# one `List.get` cannot express here: a `List` that has been through a fold is read
# from its SECOND element by `List.get(xs, 0n)` (MEASURED), so the fold's answer is
# reversed relative to its printed form in this position.
def src_head(xs: List<&2, U32>) -> U32:
  match xs:
    case h <> _:
      h
    case Nil{}:
      0

def ls_src0(+ls: List<&2, Line>, i: Nat) -> Nat:
  U32.to_nat(src_head(Line.srcs(ls_at(ls, i))))

# :208 `while self.uops[b].op in {"INDEX", "SHRINK", "BITCAST", "AFTER", "STACK"}`
def chain5(op: String) -> Bool: String.eq(op, "STACK")

def is_chain(+op: String) -> Bool:
  Bool.or(String.eq(op, "INDEX"),
    Bool.or(String.eq(op, "SHRINK"),
      Bool.or(String.eq(op, "BITCAST"),
        Bool.or(String.eq(op, "AFTER"), chain5(op)))))

def bases.go(+ls: List<&2, Line>, +j: U32, +last: U32, +acc: List<&2, U32>, +c: Bool) -> List<&2, U32>:
  match ls:
    case Nil{}:
      List.reverse(&2, U32, acc)
    case h <> t:
      bases.go(t, U32.add(j, 1), Bool.pick(U32, c, U32.add(j, 1), last),
        List.append(&2, U32, acc, [Bool.pick(U32, c, last, j)]),
        is_chain(Line.op(h)))

# THE TABLE IS 0-BASED, and it WAS 1-BASED. `ls_at` is 0-based and `store_base.of`
# feeds it `u.src[0]-1` -- CPython's `b = u.srcs[0]-1` (ops_bend.py:207) -- so the
# table has to be indexed by the same number. MEASURED with the table 1-based:
# `base[j]` for `j = 9` read entry 10, and CPython's own answer is 0. The `j`
# that reaches `bases.go` now starts at 0 and the `1n` seed with `ls_at(ls, 0n)`
# goes with it.
#
# CPython's answer for `packet-tiny.txt`, MEASURED by calling `BendProgram.__init__`:
# `nbufs=3, in_bufs=[4,4,4], out_bufs=[0]`. The STORE at line 12 reads src 10, so
# `b = 9`; lines 9,8,7,6 are INDEX/LOAD/INDEX/LOAD, :208's while walks 9 -> 8 -> 7
# -> 6 -> ... down to line 1, whose arg is `k:param:4:g`, and :209's count over
# `uops[:0]` is 0. So `out_bufs = [0]`, and that is the number the gate wants.
def bases.of(+ls: List<&2, Line>) -> List<&2, U32>:
  bases.go(ls, 0, 0, Nil{}, is_chain(Line.op(ls_at(ls, 0n))))

# one entry per line, `base[j]` for the j-th.
def bases(+ls: List<&2, Line>) -> List<&2, U32>: bases.of(ls)

def base_at(+bs: List<&2, U32>, j: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, bs, U32.to_nat(j)), 0)

# :208, answered from the table: the walk from a STORE's `u.srcs[0]` lands on
# `base[u.srcs[0]]`.
# THE real :208 WALK, AND the `bases` TABLE is a FALSE EQUIVALENCE. The file's own
# header claims "which is what `while uops[b].op in {...}: b = uops[b].srcs[0]-1`
# converges to, because the chain only ever moves DOWN the post-order list" and
# tabulates `base[j]` as the largest k <= j that is not a chain op. THAT IS FALSE.
# MEASURED on `packet-tiny.txt`: the STORE is line 11 (0-based) with srcs (10, 11),
# so `b = 9`; line 9 is `INDEX f32 - 1 5`, and following its POINTER gives
# `b = 1 - 1 = 0` -- line 0, a PARAM. The table's rule gives `base[9] = 8` (the
# LOAD above it), which is a different line entirely. CPython's own answer is
# `out_bufs = [0]`, and only the pointer chase produces it.
#
# SO THE CHASE IS THE CHASE: `chase.at` is `u.srcs[0]-1` and `chase.go` is the
# `while`. It is ONE self-recursive def -- Bend refuses mutual recursion -- with the
# flag carried, exactly the shape `ops_python.bend` `bytes.go` uses.
# `ls` LEADS THE CALL, and that is forced: arguments are read left to right and the
# call must be DECREASING on a structurally matched column. `ls` is the same list
# every step, so the `Nat` fuel is what shrinks -- and it must not sit behind `ls`
# in the signature of the def that recurses.
# THE step is taken while the op is a chain op -- :208's
# `while self.uops[b].op in {...}: b = self.uops[b].srcs[0]-1`. The first version
# had the test INVERTED (`Bool.not(is_chain(...))` for the stop), so the chase never
# moved. MEASURED: `store_base.of` answered 11 where CPython answers 0.
# THE step is taken while the op is a chain op -- :208's
# `while self.uops[b].op in {...}: b = self.uops[b].srcs[0]-1` keeps MOVING while the
# test holds and STOPS when it fails. So the pick is "not a chain op -> STOP at b",
# and `chase.go` recurses with `go_` UNCHANGED, re-testing at the new b.
def chase.at(+ls: List<&2, Line>, +b: Nat) -> Nat:
  Bool.pick(Nat, Bool.not(is_chain(Line.op(ls_at(ls, b)))), b,
    Nat.sub(ls_src0(ls, b), 1n))

# THE ENTRY SUBTRACTS, `chase.at` DOES NOT. CPython: `b = u.srcs[0]-1` and the
# while-body is `b = u.srcs[b].srcs[0]-1`, so EVERY hop subtracts one -- including
# the first. `chase.at` is the BODY and therefore does not; the entry does.
# MEASURED, both ways: with the subtraction in `chase.at` the walk started at 9 and
# answered 10 (one line too far); with it in the entry it starts at 9 and answers 0,
# which is CPython's own `out_bufs = [0]`.

# AND `go_` IS "STILL WALKING", i.e. the op IS a chain op -- not its negation.
# MEASURED: with `Bool.not(go_)` as the stop, the first call had `go_ = True` for a
# chain op and stopped immediately, so every answer was the starting index.

# THE FUEL LEADS, and it must: arguments are read left to right and every argument
# BEFORE the shrinking one has to be passed UNCHANGED (MEASURED, twice -- with the
# fuel third, the call is "expected a decreasing self-call", because
# `chase.at(ls, b)` is a COMPUTED argument and cannot be the structural column).
# This is the same rule `take_nat` and `lines.go` obey above.
# AND `go_` IS re-TESTED at the new `b` INSIDE the pick -- passing it through
# unchanged answers `b` itself. MEASURED: `store_base.of` answered 10 (the input
# minus one) where CPython answers 0, because the loop stopped after one step.
# `chase.at` is `srcs[0]-1` and the flag is `is_chain` at the NEW position, so the
# test and the step cannot disagree.
def chase.go(+fuel: Nat, +ls: List<&2, Line>, +b: Nat, +go_: Bool) -> Nat:
  match fuel:
    case 0n:
      b
    case 1n+p:
      Bool.pick(Nat, Bool.not(go_), b, chase.go(p, ls, chase.at(ls, b),
        is_chain(Line.op(ls_at(ls, chase.at(ls, b))))))

# FUEL. The chase is at most one step per line, so `nlines` bounds it, and the
# `0n` arm is the answer for a packet whose chain is longer than its own list --
# which cannot happen, because every src sits at a LOWER index. The fuel is the
# guard the file's own header says CPython's `while` lacks.
def chase_len(ls: List<&2, Line>) -> Nat:
  Nat.add(List.length(&2, Line, ls), 1n)

def chase(+ls: List<&2, Line>, +b: Nat) -> Nat:
  chase.go(chase_len(ls), ls, b, is_chain(Line.op(ls_at(ls, b))))

# `b = u.srcs[0]-1` (:208), and `chase.at` ALREADY SUBTRACTS THE ONE, so the
# entry passes the raw `srcs[0]`. The first version passed `ls_src0` and subtracted
# again -- MEASURED: `store_base.of` answered 10 where CPython answers 0, because the
# double subtraction moved the walk one line further along than Python's.
def store_base.of(+ls: List<&2, Line>, i: Nat) -> U32:
  U32.from_nat(chase(ls, Nat.sub(ls_src0(ls, i), 1n)))

# :209 `sum(is_buf(x.arg) for x in self.uops[:b])`
def bufs_before(n: Nat, +p: U32, +ls: List<&2, Line>, +acc: U32) -> U32:
  match n:
    case 1n+q:
      bufs_before(q, U32.sub(p, 1), ls,
        U32.add(acc, Bool.to_u32(is_buf(Line.arg(ls_at(ls, U32.to_nat(U32.sub(p, 1))))))))
    case 0n:
      acc

def bufs_before.of(ls: List<&2, Line>, +b: U32) -> U32:
  bufs_before(U32.to_nat(b), b, ls, 0)

# :200 `[buf_extent(u.arg) for u in self.uops if is_buf(u.arg)]`
# `Bool.pick` CHOOSES an arm, so `hit` carries the PREDICATE for the line about to
# be read. THE seed is wrong once and it was hidden: `in_bufs.of` seeded `hit` from
# `ls_at(ls, 0n)` -- the FIRST line -- and then the first arm re-tested it, so the
# first line was counted twice and the LAST line never counted. MEASURED, after
# WALL 4 was cleared: `bend_prog_tiny_in_bufs` read `4 4 4 0` where CPython's
# `[buf_extent(u.arg) for u in self.uops if is_buf(u.arg)]` is `[4, 4, 4]`.
#
# The fix is the shape `ops_python.bend` uses everywhere: TEST THE HEAD INSIDE THE
# ARM, so every line is tested exactly once and the seed is `False{}`.
# `Bool.pick` EVALUATES BOTH ARMS, so a `pick` whose arms both RECUR diverges the
# walk into an infinite regress -- MEASURED: the run never terminated. So the pick
# is over a VALUE, not over the recursion, which is the shape the rest of this file
# uses (`hexout.go`, `raw_free`).
def in_bufs.put(+ls: List<&2, Line>, +acc: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, is_buf(Line.arg(ls_at(ls, 0n))),
    List.append(&2, U32, acc, [buf_extent(Line.arg(ls_at(ls, 0n)))]), acc)

# ACC-FIRST AND NO REVERSE, the same rule `ujoin` and `drop_rest` carry. This one
# APPENDED and then reversed, so the two composed into a reversed answer -- and the
# `ujoin` display bug hid it, because BOTH halves were reversed and they agreed.
# MEASURED: `bend_prog_cmp_in_bufs` read `16 4` where CPython reads `[4, 16]` for
# `packet-cmp.txt`, whose first two PARAMs are `k:param:4:g` then `k:param:16:g`.
# The `tiny` and `fconst` packets have equal extents, which is why only `cmp` could
# see it -- the same "a fixture that cannot fail" trap `M2`/`M7` record.
def in_bufs.go(+ls: List<&2, Line>, +acc: List<&2, U32>) -> List<&2, U32>:
  match ls:
    case Nil{}:
      acc
    case h <> t:
      in_bufs.go(t, in_bufs.put(ls, acc))

def in_bufs.of(+ls: List<&2, Line>) -> List<&2, U32>: in_bufs.go(ls, Nil{})

def in_bufs(+ls: List<&2, Line>) -> List<&2, U32>: in_bufs.of(ls)

def ls_nat(j: U32) -> Nat: U32.to_nat(j)

def is_store(op: String) -> Bool: String.eq(op, "STORE")

# :208-209, the two reads of the same answer: the base's arg decides WHETHER and
# its position decides WHICH.
# `bs` IS GONE from both readers, because the table it named was the false
# equivalence above. The chase is `ls` plus a fuel, and :209's count needs only
# `ls` and the chased index.
def hit_arg(+ls: List<&2, Line>, +j: U32) -> Bool:
  is_buf(Line.arg(ls_at(ls, ls_nat(store_base.of(ls, ls_nat(j))))))

def hit_idx(+ls: List<&2, Line>, +j: U32) -> U32:
  bufs_before.of(ls, store_base.of(ls, ls_nat(j)))

# :205 `if u.op != "STORE": continue`, and :209's `if is_buf(...)`.
def hit(+ls: List<&2, Line>, +h: Line, +j: U32) -> Bool:
  Bool.and(is_store(Line.op(h)), hit_arg(ls, j))

def add_hit(+ls: List<&2, Line>, +h: Line, +j: U32,
            +acc: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, hit(ls, h, j),
    List.append(&2, U32, acc, [hit_idx(ls, j)]), acc)

# :205-209, the STORE walk over the same table. The answer is a SET (:204) and
# the walk goes UP with a prepend-then-reverse, which is the `sorted(...)` order
# the gate compares against.
# `j` IS 0-BASED, like `ls_at` and `ls`. It started at 1, which read every line one
# position late -- MEASURED: with `j = 1` the STORE at 0-based 11 was tested as if
# it were 12, `out_bufs` came back EMPTY for all three packets, and `chase_store`
# answered 0 correctly in isolation. `store_base.of(ls, 11n)` is the row that
# separates the two, and it is why `bend_chase_store` is worth having next to
# `bend_prog_tiny_out_bufs`.
#
# ACC-FIRST APPEND AND NO REVERSE, per the rule `drop_rest` and `ujoin` now carry.
def out_go(+ls: List<&2, Line>, +rest: List<&2, Line>,
           +j: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match rest:
    case Nil{}:
      acc
    case h <> t:
      out_go(ls, t, U32.add(j, 1), add_hit(ls, h, j, acc))

def out_bufs(+ls: List<&2, Line>) -> List<&2, U32>:
  H.dedup_u32(out_go(ls, ls, 0, Nil{}))

# THE arms were swapped, and that is THE wall -- not the line split, not
# `take_nat`. `Bool.pick(-A, cond, THEN, ELSE)` takes the FIRST arm when `cond` is
# True, which this file's own `wire_dtype` establishes (`Bool.pick(Res, lanes(dt),
# Res{True{}, dt}, Res{False{}, msg})` -- the OK case is the first arm). So this def
# was building `Prog.of(False{}, ...)` for every GOOD packet and
# `Prog.of(True{}, ...)` for a refused one.
#
# MEASURED, and the diagnostic rows that found it are still in the file: with the
# arms as they were, `parse` answered `nbufs = 3`, `bend_emit_tiny_match` was True,
# `bend_len_lit` and `bend_len_enc` were both 277, and `Prog.nbufs(prog.of(...))`
# was 0. Every input was right and the SELECTOR was inverted. `bend_prog_*_nbufs_ok`,
# `bend_prog_*_in_bufs_ok`, `bend_prog_*_out_bufs_ok` and `bend_call_*_refused` were
# all False, and the header attributed them to WALL 4.
def prog.of.pkt(+us: List<&2, N>, +pk: Pkt) -> Prog:
  Bool.pick(Prog, Pkt.ok(pk),
    Prog.of(True{}, "", Pkt.nbufs(pk), in_bufs(Pkt.lines(pk)),
      out_bufs(Pkt.lines(pk)), us),
    Prog.of(False{}, Pkt.msg(pk), 0, Nil{}, Nil{}, us))

def prog.of(+us: List<&2, N>) -> Prog:
  prog.of.pkt(us, parse(Res.s(encode(us))))

# `BendProgram.__call__` :211-229, AS A TRUNCATED TRACE.
#
# Nine steps and three refusals, in Python's order:
#
#   :213  exe     `executor()`                        SEAM  (the build/cache)
#   :214  mv      `to_mv(b, nb)` per buffer           SEAM  (a ctypes view)
#   :217  pkt     `pkt.write_text(self.src + ...)`    SEAM  (PACKET.in)
#   :221  RAISE   `if local_size != (1,1,1)`                  (:221 text below)
#   :222  run     `subprocess.run([exe, pkt, gx, gy, gz, vals...])`  SEAM
#   :224  RAISE   `if r.returncode != 0`
#   :225  out     `read_text()` of PACKET.out        SEAM
#   :226  RAISE   `if len(out) != self.nbufs`
#   :228  back i  `views[i][:] = bytes.fromhex(...)` SEAM, once per out_bufs
#
# A refusal RECORDS ITSELF and then STOPS the trace. That is the whole design:
# it is why no step needs a guard of its own, and why a refusal shows up as a
# truncated trace rather than as a flag nothing else reads. The failing step IS
# recorded -- on entry its own `refused` is still False, and it sets the flag in
# the same breath.
#
# ONE MODELLED DIFFERENCE, named: Python reads PACKET.out at :225 and only then
# knows `len(out)`, so a launch that failed at :224 never evaluates :226. Here
# every step's guard is a pure function of the launch facts, so they are all
# EVALUATED and only the first refusal takes effect. The trace is identical.

# The launch facts :211-213. `gx/gy/gz` are the global_size and are read only by
# the seam, so they are not fields; `local_size` and `returncode` are the two
# that a refusal tests.
type Launch is Data:
  Launch{lx: U32, ly: U32, lz: U32, rc: U32, nout: U32}

def Lc.of(lx: U32, ly: U32, lz: U32, rc: U32, nout: U32) -> Launch:
  Launch{lx, ly, lz, rc, nout}

def Lc.lx(+l: Launch) -> U32:
  match l:
    case Launch{lx, ly, lz, rc, nout}: lx

def Lc.ly(+l: Launch) -> U32:
  match l:
    case Launch{lx, ly, lz, rc, nout}: ly

def Lc.lz(+l: Launch) -> U32:
  match l:
    case Launch{lx, ly, lz, rc, nout}: lz

def Lc.rc(+l: Launch) -> U32:
  match l:
    case Launch{lx, ly, lz, rc, nout}: rc

def Lc.nout(+l: Launch) -> U32:
  match l:
    case Launch{lx, ly, lz, rc, nout}: nout

# `local_size != (1, 1, 1)` :221.
def is_warp1(+l: Launch) -> Bool:
  Bool.or(U32.is_ne(Lc.lx(l), 1), Bool.or(U32.is_ne(Lc.ly(l), 1), U32.is_ne(Lc.lz(l), 1)))

# :221, verbatim -- and `local_size` is a TUPLE, so it renders Python-style.
def warp1_msg(+l: Launch) -> String:
  String.concat(["BEND v1 is warp 1, so it cannot launch with local_size=(", U32.show(Lc.lx(l)),
    ", ", U32.show(Lc.ly(l)), ", ", U32.show(Lc.lz(l)), ")"])

# :226 `if len(out) != self.nbufs`
def nbufs_bad(+p: Prog, +l: Launch) -> Bool: U32.is_ne(Lc.nout(l), Prog.nbufs(p))

# ONE step. `raise_` is true for the three refusals; `msg` is what it says.
type Step is Data:
  Step{name: String, msg: String, raise_: Bool}

def St.of(name: String, msg: String, raise_: Bool) -> Step: Step{name, msg, raise_}

def St.name(+s: Step) -> String:
  match s:
    case Step{name, msg, raise_}: name

def St.msg(+s: Step) -> String:
  match s:
    case Step{name, msg, raise_}: msg

def St.raise_(+s: Step) -> Bool:
  match s:
    case Step{name, msg, raise_}: raise_

def step_text(+s: Step) -> String:
  Bool.pick(String, St.raise_(s), St.name(s) ++ ": " ++ St.msg(s), St.name(s))

# the trace. `calls` is the ordered list of step texts the seam will perform.
type Tr is Data:
  Tr{calls: List<&2, String>, refused: Bool}

def Tr.of() -> Tr: Tr{Nil{}, False{}}

def Tr.calls(t: Tr) -> List<&2, String>:
  match t:
    case Tr{calls, refused}: calls

def Tr.refused(t: Tr) -> Bool:
  match t:
    case Tr{calls, refused}: refused

# the seam, and the one place a refusal enters the trace.
def Tr.step(+s: Step, +t: Tr) -> Tr:
  Bool.pick(Tr, Tr.refused(t), t,
    Tr{List.append(&2, String, Tr.calls(t), [step_text(s)]),
       Bool.or(St.raise_(s), Tr.refused(t))})

def Tr.walk(+sts: List<&2, Step>, +t: Tr) -> Tr:
  match sts:
    case Nil{}:
      t
    case s <> tl:
      Tr.walk(tl, Tr.step(s, t))

# :228, one step per written-back buffer, in `out_bufs` order.
def backs.go(+xs: List<&2, U32>, +acc: List<&2, Step>) -> List<&2, Step>:
  match xs:
    case Nil{}:
      List.reverse(&2, Step, acc)
    case x <> t:
      backs.go(t, List.append(&2, Step, acc,
        [St.of(String.concat(["back ", U32.show(x)]), "", False{})]))

def backs(+xs: List<&2, U32>) -> List<&2, Step>: backs.go(xs, Nil{})

def steps(+sts: List<&2, Step>, +tl: List<&2, Step>) -> List<&2, Step>:
  match sts:
    case Nil{}:
      tl
    case s <> t:
      steps(t, tl)

# the whole of :213-228, in order.
def prog.steps(+p: Prog, +l: Launch) -> List<&2, Step>:
  steps([St.of("exe", "", False{}), St.of("mv", "", False{}),
    St.of("pkt", "", False{}), St.of("RAISE local_size", warp1_msg(l), is_warp1(l)),
    St.of("run", "", False{}),
    St.of("RAISE returncode", "the Bend executor exited " ++ U32.show(Lc.rc(l)),
      U32.is_ne(Lc.rc(l), 0)),
    St.of("out", "", False{}),
    St.of("RAISE nbufs", "BEND executor wrote " ++ U32.show(Lc.nout(l))
      ++ " buffers, the packet had " ++ U32.show(Prog.nbufs(p)), nbufs_bad(p, l))],
    backs(Prog.out_bufs(p)))

# `BendCompiler.compile` :232 -- `return src.encode()`, "pass-through: the source
# IS the packet". It is a def and not a field because it is the ONLY thing
# `Compiled` hands the program as `obj.lib`, and `Prog.src` is that same string.
# `bend_compiler_passthrough` is the row, and it is a tautology unless the two
# sides are different strings, which is why it compares `compiler.of` against
# `encode` rather than against a literal.

# `BendDevice.__init__` :244 -- `super().__init__(device, HostAllocator(self),
# [BendRenderer], BendProgram)`. The renderer list and the Program CLASS are the
# two facts, and both are already in this file (`encode` and `prog.call`), so the
# device record is what is left: the allocator is a HostAllocator over the host
# pointer, which is WALL 3's neighbour and is not modelled.
type Dev is Data:
  Dev{name: String, has_local: Bool}

# THE allocator, AND milestone 1: A BUFFER, A kernel, THE expected bytes.
#
# Everything above this line is the port of ops_bend.py's ENCODER. What follows
# is what makes the BEND device a DEVICE rather than a formatter: device memory,
# and a launch. The two were absent -- `buffer_from`, `buffer_to`, `raw_alloc`
# and `raw_free` appear nowhere in this file, and `prog.call`'s six SEAM steps
# were steps in a trace with nothing behind them.
#

# WHAT "BEND'S OWN MEMORY" IS HERE, and why the allocator is this shape

# Bend has no `malloc` and no pointer. Its mutable memory is `Array`, and an
# `Array` is AFFINE -- the rule `ops_python.bend` is built around: "A `Data`
# record cannot hold a `List` or an `Array`; both are `Type`", so a store cannot
# be a field either. So the port cannot port `HostAllocator._alloc`, which is
# `mmap.mmap(-1, size)` and returns a raw address -- and there is no address.
#
# What IS ported is the CONTRACT: one byte store, a base offset per buffer, and
# an extent. `Buf` in `ops_python.bend:858` is exactly `Buf{base, w, e}` and
# `Mem.byte`/`Mem.put` at :855/:858 are exactly the read and the write. So the
# allocator here has the SAME shape as the executor's, deliberately: the wire is
# one wire, and two disagreeing memory models over it would be a second silent
# failure waiting to happen. `Buf` is not imported because a buffer allocated by
# the LAUNCHER and a buffer allocated by the EXECUTOR are different objects in
# different processes -- `executor()` is a `subprocess.run` at ops_bend.py:222 --
# and they agree only through the packet's hex.
#

# THE ALLOCATOR'S HONEST LIMITS, named before the rows rather than after

# `raw_alloc` BUMPS and `raw_free` is a NO-OP. That is not a shortcut, it is what
# `HostAllocator._free` (device.py:307) IS: it touches storage only under
# `if (remote:=getattr(self.dev, "remote", None)) is not None`, and BEND has no
# `remote`, so on this device Python's free releases nothing. A port that
# implemented reuse would be asserting behaviour the Python does not have.
#
# The one thing this CANNOT be is a real allocator with a free list, and that is
# a property of the substrate rather than of the port: Bend's `Array` is affine,
# so there is no second owner to hand a freed range to. Named, not hidden.

# THE STORE. One flat byte list, one bump pointer, travelling together in one
# record -- the shape `ops_python.bend`'s `Prog` uses for the same reason ("`Data`
# FIELDS MUST BE `Data`... So a program table is NOT a field of a record: it is a
# `List` threaded beside the arena").
type Store is Data:
  Store{ms: List<&2, U32>, top: U32}

def Store.of(ms: List<&2, U32>, top: U32) -> Store: Store{ms, top}

def Store.ms(+s: Store) -> List<&2, U32>:
  match s:
    case Store{ms, top}: ms

def Store.top(+s: Store) -> U32:
  match s:
    case Store{ms, top}: top

# A buffer: a base offset and an extent in BYTES. `Mem.nbytes` is what `in_bufs`
# (:200) carries and what `buf_extent` :178 parses, so the allocator hands back
# the SAME quantity the packet carries -- not a length in elements.
type Mem is Data:
  Mem{base: U32, nbytes: U32}

def Mem.of(base: U32, nbytes: U32) -> Mem: Mem{base, nbytes}

def Mem.base(+m: Mem) -> U32:
  match m:
    case Mem{base, nbytes}: base

def Mem.nbytes(+m: Mem) -> U32:
  match m:
    case Mem{base, nbytes}: nbytes

# `zeros(n)` -- the `bytearray(n)` at ops_python.py:104, which is what a `BUFFER`
# and a `REG` PARAM get. It PREPENDS and REVERSES, because `List.append` is
# `xs ++ ys` (the rule this file's `src_text.go` was written around) and that is
# the only order-preserving spelling available.
def zeros.go(n: Nat, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: List.reverse(&2, U32, acc)
    case 1n+p: zeros.go(p, List.append(&2, U32, acc, [0]))

def zeros(n: Nat) -> List<&2, U32>:
  match n:
    case 0n: Nil{}
    case 1n+p: zeros.go(Nat.sub(n, 1n), [0])

# THE BYTE STORE, read and written. SPELLED here rather than imported because a
# store allocated by the launcher is a DIFFERENT object from the executor's store
# (see THE ALLOCATOR'S HONEST LIMITS). `Maybe.default` with 0 is
# `ops_python.bend`'s own default, and it is load-bearing: an oob read must not
# halt the machine, because `Prog.bad` is a SEPARATE flag there, and conflating
# the two would make an oob read indistinguishable from a refused op.
def Mem.byte(+s: Store, at: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, Store.ms(s), U32.to_nat(at)), 0)

def Mem.put(+s: Store, at: U32, v: U32) -> Store:
  Store.of(List.set(&2, U32, Store.ms(s), U32.to_nat(at), v), Store.top(s))

# `raw_alloc(nbytes)`: ONE buffer off the bump pointer, and the store grows by
# exactly that many bytes. The answer is a PAIR because Bend has no mutable
# local: `Store` in, `Store` out, and the caller threads it.
def raw_alloc(nbytes: U32, +s: Store) -> (Mem & Store):
  # `nbytes` is BOUND ONCE because a parameter read more than once is "consumed
  # more than once" (MEASURED) -- the same reason `ops_python.bend` binds a UOp's
  # fields into locals before a fold. The `+` is what makes the binder a REBIND,
  # not a second read of the parameter, and that is the whole point of `+ar`.
  +nb : U32 = nbytes
  (Mem.of(Store.top(s), nb),
   Store.of(List.append(&2, U32, Store.ms(s), zeros(U32.to_nat(nb))),
            U32.add(Store.top(s), nb)))

# THE SPLIT, because a PAIR cannot be destructured at a call site: both
# "Bend refuses to destructure a computed product" (`Pkt` above) and, MEASURED
# here, "a match cannot scrutinize a computed value: give it its own def". So
# the pair is a PARAMETER and the two halves are two one-line defs -- which is
# what `ops_python.bend`'s `take(...)` inside `rd` does for `Array.get`.
def first.of(p: (Mem & Store)) -> Mem:
  (m, _) = p
  m

def second.of(p: (Mem & Store)) -> Store:
  (_, t) = p
  t

# THE hex codec, and WHY it is spelled here rather than imported from
# `ops_python.bend`. That is a measured decision, not a preference:
#
#   * THE PORT's `runtime/ops_python.bend` IMPORT BLOCK does `import ../uop/ops.bend as O`, so importing
#     anything from it makes `ops_bend.bend` DEPEND ON `uop/ops.bend` -- which is
#     under single ownership and was MID-EDIT during this unit: its `vals.step` at
#     line 7686 refuses `match t:` with "a match on a parameter or field (this
#     name is a def or a consumed binder)". This file compiled clean before that
#     import and must not become hostage to another unit's transient breakage.
#     The dependency bought ONE nine-line fold. REPORTED, not fixed: `uop/ops.bend`
#     is not this unit's to touch.
#   * `ops_python.bend:427`'s `hexdig_str` is DEAD and WRONG -- see THE FINDING
#     above -- so reusing that side of the codec was never an option.
#
# THE NIBBLE RULES ARE `ops_python.bend:382-396` verbatim in shape: three range
# tests tell a digit from a lower-case letter from an upper-case one, and
# `hexdig_val` answers 0-15 for a hex character.
# `+c` ON EVERY ONE, because `Bool.and`/`Bool.or` read both operands and a
# parameter read twice is "consumed more than once" (MEASURED). This is why
# `runtime/ops_python.bend:380 symbol=keep_word` spells its three range tests as ONE-ARGUMENT helpers with
# the `+`, rather than inlining the ranges.
def hexdig_digit(+c: U32) -> Bool: Bool.and(U32.is_ge(c, 48), U32.is_le(c, 57))

def hexdig_lower(+c: U32) -> Bool: Bool.and(U32.is_ge(c, 97), U32.is_le(c, 102))

def hexdig_upper(+c: U32) -> Bool: Bool.and(U32.is_ge(c, 65), U32.is_le(c, 70))

def hexdig_val(+c: U32) -> U32:
  Bool.pick(U32, hexdig_digit(c), U32.sub(c, 48),
    Bool.pick(U32, hexdig_lower(c), U32.sub(c, 87), U32.sub(c, 55)))

# ONE nibble to its character, and it is a LEAF because `Bool.pick` CHOOSES an arm
# and a parameter read in both arms is "consumed more than once" (MEASURED). The
# `+` is the REBIND marker, which is what makes the two reads legal -- the same
# use as `ops_python.bend`'s `Prog.line.dig(+v)`.
def hexdig.chr(+v: U32) -> U32:
  Bool.pick(U32, U32.is_lt(v, 10), U32.add(v, 48), U32.add(v, 87))

# THE FOLD. TWO characters per byte, HIGH nibble first, prepended and reversed
# once at the end -- `List.append` is `xs ++ ys`, the rule `src_text.go` above
# exists to demonstrate. `live` says a high nibble is WAITING, which is why the
# fold has two arms rather than one.
#
# AN odd number of digits drops the trailing half-BYTE. Python's `bytes.fromhex`
# RAISES `ValueError` there, so this is WEAKER than the Python and `bend_hex_odd`
# is the row that says so instead of leaving it a silent difference.
# NO REVERSE, and the absence is the fix for a MEASURED bug: the fold walks the
# string FORWARD and `List.append(a, A, acc, [b])` is `acc ++ [b]`, so the bytes
# are already in order and the reverse turned "efbeadde" into the STORE
# [0xde, 0xad, 0xbe, 0xef] -- which re-emitted as "deadbeef", i.e. the bytes
# BACKWARDS. MEASURED on the first real launch: `ms_got` read "4 deadbeef" for the
# fourth distinct failure mode from the three above and the reason the comparison
# is over emitted TEXT rather than over a number.
def hex.fin(acc: List<&2, U32>) -> List<&2, U32>: acc

# HIGH NIBBLE FIRST, and the measurement that pins it is the executor's OWN
# output: the hand-built packet line "4 0000803f" for the f32 1.0 (0x3F800000)
# came back out of the executor byte for byte. 0x3f is written "3f", never "f3", so
# `pend` (the FIRST character of the pair, the high nibble) carries the 16s.
def hex.pair(+pend: U32, +c: U32) -> U32:
  U32.add(U32.mul(hexdig_val(pend), 16), hexdig_val(c))

def hex.acc(+pend: U32, +c: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, acc, [hex.pair(pend, c)])

def hexdec.go(+cs: List<&2, Char>, +pend: U32, +live: Bool,
              +acc: List<&2, U32>) -> List<&2, U32>:
  match cs live:
    case Nil{} _: hex.fin(acc)
    case h <> t True{}:
      hexdec.go(t, 0, False{}, hex.acc(pend, Char.to_u32(h), acc))
    case h <> t False{}:
      hexdec.go(t, Char.to_u32(h), True{}, acc)

# THE nibble order is the third bug this milestone found, and it is the one
# `runtime/ops_python.bend:1201 symbol=Prog.alloc.ss` warns about BY NAME: "writing every byte DIGIT-SWAPPED
# -- 0x3f as \"f3\" -- and, because the reader was digit-swapped in the same way,
# the two cancelled on a pure COPY". MEASURED here on the first real launch: the
# pattern `efbeadde` came back out of the store as `deadbeef`, i.e. every BYTE was
# reversed, which is what you get from `high*16 + low` when the wire is `low*16 +
# high` -- the hex on the wire is HIGH NIBBLE FIRST
# (`runtime/ops_python.bend:1201 symbol=Prog.alloc.sp` -- `Prog.hex.nib` reads characters 2k and 2k+1, high first), so the fold must ADD
# the high nibble to the low one, not the other way round.
def hexbytes(hex: String) -> List<&2, U32>:
  hexdec.go(String.to_list(hex), 0, False{}, Nil{})

# ONE NIBBLE TO TEXT, and `hexdig_str2` is named for what it is rather than
# shadowing the broken `hexdig_str` this file deliberately does not reproduce.
def hexdig_str2(v: U32) -> String:
  String.from_list([Char.from_u32(hexdig.chr(v))])

# THE EMITTED ORDER is high nibble first, low byte first -- the order
# `runtime/ops_python.bend:1201 symbol=Prog.alloc.ss` measured the hard way ("writing every byte
# DIGIT-SWAPPED -- 0x3f as \"f3\" -- and, because the reader was digit-swapped in
# the same way, the two cancelled on a pure COPY"). The reader and the writer are
# therefore INDEPENDENT above, and `bend_hexbyte_*` pins the writer against
# literals rather than against the reader.
def hexbyte(+b: U32) -> String:
  String.concat([hexdig_str2(U32.div(b, 16)), hexdig_str2(U32.mod(b, 16))])

def hexout.go(+bs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match bs:
    case Nil{}: List.reverse(&2, String, acc)
    case b <> t: hexout.go(t, List.append(&2, String, acc, [hexbyte(b)]))

# `slice(ms, at, n, i)`: `n` bytes from `at`. Written as a fold over the INDEX
# rather than a `List.get` loop because the list is affine and cannot be both
# walked and indexed in one def.
# `slice(ms, at, n, i)`: `n` bytes from `at`. NOT a `Bool.pick` recursion --
# MEASURED: "expected a decreasing self-call", because a pick over an `i` that
# GROWS has no argument that shrinks. The fuel is a DESTRUCTURED copy of the
# store, which is the shape `take_nat` above uses for the same reason.
# ONE SELF-RECURSIVE FOLD, not two mutually recursive ones: Bend REFUSES mutual
# recursion (MEASURED here -- "expected a filled definition", the same refusal
# `ops_python.bend`'s `bytes` note records: "It is ONE self-recursive def -- Bend
# refuses mutual recursion"). So the tail IS the fuel and the countdown is
# dropped, which is exactly why `p` cannot be bound separately.
# THE BYTE RIDES THE ACCUMULATOR, because a destructured tail and a `List.get`
# over the same list is "consumed more than once" (MEASURED): binding `t` walks
# `xs`, so nothing else may read `xs`. So the walk is destructive and each step
# carries its own byte, which is why this is ONE self-recursive fold and not
# `take` + `get`. `+n` is the REBIND marker for the same reason as
# `ops_python.bend`'s `Prog.line.dig(+v)`.
# FOUR arms, AND the count is the point. The first version was
#   case Nil{} _ : ...    case h <> t _ : take.go(t, U32.sub(n, 1), ...)
# which MEASURED wrong: `_` ignores the second column, so the walk ran until the
# LIST ended rather than until the COUNT ran out, and `U32.sub` SATURATES at 0, so
# a spent countdown became a permanent 0 instead of a stop. The result was that
# `slice` always answered the WHOLE TAIL and `ms_b0_hex_in` was EMPTY for every
# buffer -- three distinguishable wrong answers that all looked like one.
#
# THE REVERSE IS CORRECT HERE: `List.append(a, A, acc, [h])` is `acc ++ [h]`, so
# this builds the taken bytes in order and the ONE reverse at the end is right.
def take.go(+work: List<&2, U32>, +n: Nat, +acc: List<&2, U32>) -> List<&2, U32>:
  match work n:
    case h <> t 0n:
      List.reverse(&2, U32, acc)
    case Nil{} 0n:
      List.reverse(&2, U32, acc)
    case Nil{} 1n+p:
      List.reverse(&2, U32, acc)
    case h <> t 1n+p:
      take.go(t, p, List.append(&2, U32, acc, [h]))

# SAME SATURATION TRAP AS `take.go`, and the same fix: a `Nat` countdown whose arm
# is `1n+p` STOPS by exhausting the list, where `U32.sub` would have saturated.
def drop.go(xs: List<&2, U32>, +n: Nat) -> List<&2, U32>:
  match xs n:
    case Nil{} 0n:
      Nil{}
    case _ <> _ 0n:
      xs
    case Nil{} 1n+p:
      Nil{}
    case _ <> t 1n+p:
      drop.go(t, p)

# `slice(ms, at, n)`: SKIP to `at`, then take `n` -- so the offset is honoured.
# The copy into a fresh `&2` list is the depth hop again, and it is free because
# the store is already `&2` and `List.append` rebuilds at the callee's depth.
# THE COUNT IS A `Nat`, NOT A `U32`, and that is forced by the substrate rather
# than chosen: `U32` is `U32{data: Word(32n)}` (base.bend:64), an OPAQUE record,
# so it cannot be destructured into a countdown at all (MEASURED: "expected a
# constructor of U32"). `Nat` is `Zero{}/Succ{pred}` and a `case 1n+p` arm consumes
# it -- which is ALSO what stops the walk, where a saturating `U32.sub` would not.
def slice(ms: List<&2, U32>, at: U32, n: U32) -> List<&2, U32>:
  take.go(drop.go(List.append(&2, U32, Nil{}, ms), U32.to_nat(at)), U32.to_nat(n), Nil{})

def Mem.to_hex(+s: Store, +m: Mem) -> String:
  String.concat(hexout.go(slice(Store.ms(s), Mem.base(m), Mem.nbytes(m)), Nil{}))

# `Mem.to_line` -- `<nbytes> <hex-bytes>`, which is ONE line of PACKET.out and
# nothing else. The milestone's comparison is over these lines, whole.
def Mem.to_line(+s: Store, +m: Mem) -> String:
  String.concat([U32.show(Mem.nbytes(m)), " ", Mem.to_hex(s, m), "\n"])

# `paint(at, ms, bs, n)`: copy `bs` onto `ms` at `at`, truncating or zero-filling
# to `n`. The zero-fill is `bytes(n)` and the truncation is `views[i][:] = ...`,
# both of which raise in Python on a length mismatch -- so this is a WEAKER
# function than the Python and the row below names the case.
# `paint(at, ms, bs, n)`: copy `bs` onto `ms` at `at`, stopping after `n` bytes.
# THE fuel leads and it is the structural tail: arguments are read left to right
# and the call must be DECREASING (MEASURED: "expected a decreasing self-call"),
# and only a destructured binder passed UNCHANGED counts -- this file's own note
# says a call "shrinks no column and cannot be the fuel", which is why the
# `_work_tail` spelling above it did not compile either. So `bs` is destructured
# and its tail `t` leads, and `at` walks up through the store.
def paint.go(+bs: List<&2, U32>, +at: U32, ms: List<&2, U32>, +n: Nat) -> List<&2, U32>:
  match bs n:
    case h <> t 1n+p:
      paint.go(t, U32.add(at, 1), List.set(&2, U32, ms, U32.to_nat(at), h), p)
    case h <> t 0n:
      ms
    case Nil{} 0n:
      ms
    case Nil{} 1n+p:
      ms

def paint(at: U32, ms: List<&2, U32>, bs: List<&2, U32>, n: Nat) -> List<&2, U32>:
  paint.go(bs, at, ms, n)

def Mem.write_bytes(+s: Store, +m: Mem, bs: List<&2, U32>) -> Store:
  Store.of(paint(Mem.base(m), Store.ms(s), bs, U32.to_nat(Mem.nbytes(m))), Store.top(s))

# `buffer_from(nbytes, hex)` :214 -- `to_mv(b, nb)`, which this file's own header
# already called a VIEW and not a seam: "the port keeps the extent, which is what
# `in_bufs` is, and drops the pointer." So this is the COPY-IN, as hex text,
# because the wire carries hex text.
# `m` and `s1` ARE RENAMED, and that is the trap this file's own notes warn
# about: "A record binder shadows a same-named parameter and nothing says so. A
# leading `+` does not help; rename the parameter." `(m, Mem.write_bytes(..))`
# rebinds `m`, so the parameter cannot also be spelled `m`.
def rebase(+m0: Mem, s1: Store, +s: Store, +hex: String) -> (Mem & Store):
  (m0, Mem.write_bytes(s1, m0, hexbytes(hex)))

def paint_mem(p: (Mem & Store), +s: Store, +hex: String) -> (Mem & Store):
  (m, s1) = p
  rebase(m, s1, s, hex)

def buffer_from(nbytes: U32, hex: String, +s: Store) -> (Mem & Store):
  paint_mem(raw_alloc(nbytes, s), s, hex)
