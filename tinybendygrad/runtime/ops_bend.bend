# ops_bend.bend -- port of tinygrad/runtime/ops_bend.py
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
# ===========================================================================
# WHAT IS PORTED, DEF BY DEF.
#
#   :90  LANES                    PORTED  `lanes`, `lanes_sorted`
#   :92  wire_dtype               PORTED  `wire_dtype` -- the NAME and the
#                                           refusal, message included
#   :103 wire_width               PORTED  `wire_width` (node.numel)
#   :110 wire_arg                 PORTED  `wire_arg` -- every arm but the float
#                                           CONST's `struct.pack` (WALL 2)
#   :133 encode                   PORTED  `encode`
#   :149 executor                 SEAM   the build/cache of the executor
#   :169 UOpLine                  PORTED  `Line`
#   :175 is_buf                   PORTED  `is_buf`
#   :178 buf_extent               PORTED  `buf_extent`
#   :180 parse                    PORTED  `parse`
#   :195 BendProgram.__init__     PORTED  `prog.of` -- in_bufs AND out_bufs
#   :211 BendProgram.__call__     PORTED  `prog.call` as a TRUNCATED TRACE
#   :231 BendCompiler.compile     PORTED  `compiler.of` -- pass-through
#   :234 BendRenderer             PORTED  `render`, `has_local`
#   :243 BendDevice.__init__      SEAM   HostAllocator + Compiled wiring
#
# ===========================================================================
# THE SPLIT, stated once and then obeyed. A def here EITHER builds the argument
# of ONE launch (pure, and the gate checks it) OR records that step in the trace
# (and the gate checks the ORDER). There is no third kind. That is what puts the
# `raise` in the trace, so a refusal appears as a truncated trace and no step
# needs a guard of its own.
#
# THE EMITTED TEXT IS A GATE, NOT A BOOLEAN. `String.concat` drops a literal
# silently, so a boolean about a string can be true while the string is wrong.
# `bend_encode_*` rows print the packet's own lines, and `emit.diff` prints the
# whole packet. Those rows are TEXT; the diff against CPython's packet is the
# check, and it is line for line.
#
# ===========================================================================
# THE THREE WALLS.
#
# 1. THE Op NUMBER IS NOT PORTED, AND THAT IS THE POINT. Python writes
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
#    TODO(p3) runtime/ops_bend.py:118  -- struct.pack('<f', u.arg).hex().
#
# 3. THE FFI SEAMS, named with their Python lines. None of these is an
#    `@extern`; they are steps in the trace, so the trace stays greppable.
#      :150-164  `executor()`  -- exists(), stat(), hashlib, subprocess.run
#               over ./bin/bend, os.replace. The build and the cache.
#      :214      `to_mv(b, nb)` -- a ctypes memoryview over a device pointer.
#      :217      `pkt.write_text(...)` -- the PACKET.in on disk.
#      :222      `subprocess.run([exe, pkt, gx, gy, gz, vals...])` -- the launch.
#      :225      `read_text()` of PACKET.out.
#      :228      `views[i][:] = bytes.fromhex(...)` -- the copy-back.
#      :232      `src.encode()` -- BendCompiler, which is a pass-through.
#      :219      `time.perf_counter()` -- the returned duration. Not modelled:
#               the only thing this port does with a time is hand it back, and
#               no caller of `Program.__call__` reads it (engine/realize.py:168
#               discards it).
#
# `ctypes` is not one of the seams: `to_mv` is the only ctypes in the file, and
# it is a VIEW over bytes the caller already owns. The port keeps the extent,
# which is what `in_bufs` is, and drops the pointer.
#
# ===========================================================================
# `has_local = False` (:238) is a CONSTANT the scheduler consults
# (opt/heuristic.py:163), so it is a `def` and not a field: a def nothing calls
# is invisible to every other check, and `bend_has_local` is its only reader.
#
# ===========================================================================
import ../helpers.bend as H

# ===========================================================================
# THE LANE TABLE. `LANES: frozenset = {int, uint, float, bool}` -- four lanes,
# plus the three names ops_bend.py passes through untouched because the
# executor parses them (`to_dtype` is `getattr(dtypes, name.lower())`).
# ===========================================================================

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

# ===========================================================================
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
# ===========================================================================

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

# ===========================================================================
# THE NODE LIST. `self.uops` -- the renderer's own list, already in post-order.
# ===========================================================================

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

# ===========================================================================
# `is_image_shape(shape)` :126 -- `shape is not None and len(shape)==3 and
# shape[-1]==4`. The two facts it reads are `ndim` and `last`, and the port
# computes the predicate itself: it is the DECISION, and a decision handed over
# by the seam is a decision the gate cannot check. What the seam supplies is
# `shape`, the repr, because the refusal message at :126 interpolates
# `s._shape` verbatim and Python's repr is `(2, 3, 4)`.
# ===========================================================================

def is_image_shape(ndim: U32, last: U32) -> Bool:
  Bool.and(U32.is_eq(ndim, 3), U32.is_eq(last, 4))

# ===========================================================================
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
# ===========================================================================

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

# ===========================================================================
# `is_buf(arg)` :177 -- `arg.startswith("k:param:") and
# arg.rsplit(":", 1)[1] in ("g", "l")`. THE `l` NEVER MATCHES, for the reason
# above: no PARAM can carry it. The test is ported as Python writes it and the
# row `bend_buf_l_never` says which inputs reach it.
#
# `buf_extent(arg)` :178 -- `int(arg.split(":")[2])`, the SECOND colon field of
# `k:param:<nbytes>:<letter>`, which is the byte count. The 0 is the IndexError
# Python raises on a field list shorter than three, which `is_buf` has already
# excluded.
# ===========================================================================

def is_buf(+arg: String) -> Bool:
  Bool.and(String.starts_with(arg, "k:param:"),
    Bool.or(String.ends_with(arg, ":g"), String.ends_with(arg, ":l")))

def field2(+arg: String) -> String:
  Maybe.default(&2, String, List.get(&2, String, String.split(arg, ':'), 2n), "")

def buf_extent(arg: String) -> U32: Maybe.default(&2, U32, U32.read(field2(arg)), 0)

# ===========================================================================
# `encode(uops) -> str` :133-145.
#
# THE TWO ASSERTS ARE PORTED AS REFUSALS, which is the only way a refusal can
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
# ===========================================================================

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
# ===========================================================================

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

# THE OFF-BY-ONE, AND IT IS THE REAL WALL. `take1` is `take_nat(xs, 1n)` and it
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
# SO THE HEADER'S WALL 4 WAS THE WRONG DEF. It blamed `String.split(s, NLCH())`,
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
# THE TRAILING EMPTY FIELD, DROPPED FROM THE END -- AND THIS IS A BUG FIX, not a
# spelling. The original dropped the HEAD (`case _ <> t: t`), which for
# `"4 a\n4 b\n4 c\n"` answers ["4 b", "4 c"] -- one line lost and the first
# line wrong. MEASURED on the first per-buffer run: `ms_b0_got` read the SECOND
# buffer's line and `ms_b2_got` read the trailing empty. The rows were doing their
# job; they caught a def that the earlier truncated single-row verdict could not
# see, because it compared a prefix with a prefix.
#
# THE HEAD IS REMOVED AND THEN THE LIST IS REBUILT, because there is no
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

# AND THE ENTRY HANDS OVER THE TAIL, so the last field of `xs` never becomes a
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
#   TODO(p3) runtime/ops_bend.py:180 -- split a packet into LINES.
def NLCH() -> Char: Maybe.default(&2, Char, String.get("\n", 0n), ' ')

# THE SPLIT, AND THE TRAILING EMPTY FIELD IS DROPPED because `encode` always ends
# the packet with a newline (ops_bend.py:145) and `String.split` KEEPS the empty
# field after it where `splitlines` does not. That one field is the whole
# difference, and `ms_line_count` is the row that would notice if it were not.
def split_lines(text: String) -> List<&2, String>:
  drop_final(String.split(text, NLCH()))

def split_all(s: String) -> List<&2, String>: String.split(s, NLCH())

# `int(s) for s in srcs` :189. `List.map` answers a `List<&1, ...>` when its
# element type is spelled `String`, and `Line.srcs` wants `&2`, so the map is
# written out: it is four lines and it keeps the two lists in one family.
# PREPEND, AND THAT IS THE FIX. The original APPENDED with
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
# AND THE WALK IS ORDER-PRESERVING, which the old one was not. `drop3`/`drop4`
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
# THE COUNT IS EXHAUSTED BY THE `Nat`, AND THE TAIL IS THE ANSWER -- collected
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

# `drop3` IS THE OLD THREE-NAME SPELLING, kept beside `drop4` because THE
# DIFFERENCE BETWEEN DROPPING THREE AND FOUR IS THE :188 BUG: the old code left the
# ARG in the srcs, so every :208 walk started from the wrong number.
def drop3(xs: List<&2, U32>) -> List<&2, U32>: drop_nat(xs, 3n)

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
# AND THIS IS WHERE THE ORIGINAL `drop_final` WAS DOING DOUBLE DUTY. It dropped
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
# ===========================================================================
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
# ===========================================================================

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
# THE REAL :208 WALK, AND THE `bases` TABLE IS A FALSE EQUIVALENCE. The file's own
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
# THE STEP IS TAKEN WHILE THE OP **IS** A CHAIN OP -- :208's
# `while self.uops[b].op in {...}: b = self.uops[b].srcs[0]-1`. The first version
# had the test INVERTED (`Bool.not(is_chain(...))` for the stop), so the chase never
# moved. MEASURED: `store_base.of` answered 11 where CPython answers 0.
# THE STEP IS TAKEN WHILE THE OP **IS** A CHAIN OP -- :208's
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
# AND `go_` IS RE-TESTED AT THE NEW `b` INSIDE THE PICK -- passing it through
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
# be read. THE SEED IS WRONG ONCE AND IT WAS HIDDEN: `in_bufs.of` seeded `hit` from
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


# THE ARMS WERE SWAPPED, and that is THE WALL -- not the line split, not
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
# ===========================================================================
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
# ===========================================================================

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

def prog.call(+p: Prog, +l: Launch, +t: Tr) -> Tr:
  Tr.walk(prog.steps(p, l), t)

# ===========================================================================
# `BendCompiler.compile` :232 -- `return src.encode()`, "pass-through: the source
# IS the packet". It is a def and not a field because it is the ONLY thing
# `Compiled` hands the program as `obj.lib`, and `Prog.src` is that same string.
# `bend_compiler_passthrough` is the row, and it is a tautology unless the two
# sides are different strings, which is why it compares `compiler.of` against
# `encode` rather than against a literal.
# ===========================================================================

def compiler.of(src: String) -> String: src

# `has_local = False` :238 -- the scheduler's lever (opt/heuristic.py:163), so it
# is a def rather than a field: a field nothing reads is invisible.
def has_local() -> Bool: False{}

# `BendDevice.__init__` :244 -- `super().__init__(device, HostAllocator(self),
# [BendRenderer], BendProgram)`. The renderer list and the Program CLASS are the
# two facts, and both are already in this file (`encode` and `prog.call`), so the
# device record is what is left: the allocator is a HostAllocator over the host
# pointer, which is WALL 3's neighbour and is not modelled.
type Dev is Data:
  Dev{name: String, has_local: Bool}

# ===========================================================================
# THE ALLOCATOR, AND MILESTONE 1: A BUFFER, A KERNEL, THE EXPECTED BYTES.
#
# Everything above this line is the port of ops_bend.py's ENCODER. What follows
# is what makes the BEND device a DEVICE rather than a formatter: device memory,
# and a launch. The two were absent -- `buffer_from`, `buffer_to`, `raw_alloc`
# and `raw_free` appear nowhere in this file, and `prog.call`'s six SEAM steps
# were steps in a trace with nothing behind them.
#
# ---------------------------------------------------------------------------
# WHAT "BEND'S OWN MEMORY" IS HERE, and why the allocator is this shape
# ---------------------------------------------------------------------------
# Bend has no `malloc` and no pointer. Its mutable memory is `Array`, and an
# `Array` is AFFINE -- the rule `ops_python.bend` is built around: "A `Data`
# record cannot hold a `List` or an `Array`; both are `Type`", so a store cannot
# be a field either. So the port cannot port `HostAllocator._alloc`, which is
# `mmap.mmap(-1, size)` and returns a raw address -- and there is no address.
#
# What IS ported is the CONTRACT: one byte store, a base offset per buffer, and
# an extent. `Buf` in `ops_python.bend:819` is exactly `Buf{base, w, e}` and
# `Mem.byte`/`Mem.put` at :855/:858 are exactly the read and the write. So the
# allocator here has the SAME shape as the executor's, deliberately: the wire is
# one wire, and two disagreeing memory models over it would be a second silent
# failure waiting to happen. `Buf` is not imported because a buffer allocated by
# the LAUNCHER and a buffer allocated by the EXECUTOR are different objects in
# different processes -- `executor()` is a `subprocess.run` at ops_bend.py:222 --
# and they agree only through the packet's hex.
#
# ---------------------------------------------------------------------------
# THE ALLOCATOR'S HONEST LIMITS, named before the rows rather than after
# ---------------------------------------------------------------------------
# `raw_alloc` BUMPS and `raw_free` is a NO-OP. That is not a shortcut, it is what
# `HostAllocator._free` (device.py:307) IS: it touches storage only under
# `if (remote:=getattr(self.dev, "remote", None)) is not None`, and BEND has no
# `remote`, so on this device Python's free releases nothing. A port that
# implemented reuse would be asserting behaviour the Python does not have.
#
# The one thing this CANNOT be is a real allocator with a free list, and that is
# a property of the substrate rather than of the port: Bend's `Array` is affine,
# so there is no second owner to hand a freed range to. Named, not hidden.
# ===========================================================================

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

# THE EMPTY STORE: no bytes, bump at 0. A `HostAllocator` over a fresh device has
# nothing mapped either, so 0 is the honest starting answer and not a sentinel.
def store() -> Store: Store.of(Nil{}, 0)

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

def alloc_mem(nbytes: U32, s: Store) -> Mem: first.of(raw_alloc(nbytes, s))

def alloc_store(nbytes: U32, s: Store) -> Store: second.of(raw_alloc(nbytes, s))

# `raw_free`: a NO-OP, and the row says so. See THE ALLOCATOR'S HONEST LIMITS.
# It answers the same `Mem`, so a caller that frees the last buffer and reads it
# back gets the bytes rather than a crash -- which is what Python does too.
def raw_free(+m: Mem) -> Mem: m

# THE HEX CODEC, and WHY IT IS SPELLED HERE RATHER THAN IMPORTED FROM
# `ops_python.bend`. That is a measured decision, not a preference:
#
#   * `ops_python.bend:261` does `import ../uop/ops.bend as O`, so importing
#     anything from it makes `ops_bend.bend` DEPEND ON `uop/ops.bend` -- which is
#     under single ownership and was MID-EDIT during this unit: its `vals.step` at
#     line 7686 refuses `match t:` with "a match on a parameter or field (this
#     name is a def or a consumed binder)". This file compiled clean before that
#     import and must not become hostage to another unit's transient breakage.
#     The dependency bought ONE nine-line fold. REPORTED, not fixed: `uop/ops.bend`
#     is not this unit's to touch.
#   * `ops_python.bend:398`'s `hexdig_str` is DEAD and WRONG -- see THE FINDING
#     above -- so reusing that side of the codec was never an option.
#
# THE NIBBLE RULES ARE `ops_python.bend:382-396` verbatim in shape: three range
# tests tell a digit from a lower-case letter from an upper-case one, and
# `hexdig_val` answers 0-15 for a hex character.
# `+c` ON EVERY ONE, because `Bool.and`/`Bool.or` read both operands and a
# parameter read twice is "consumed more than once" (MEASURED). This is why
# `ops_python.bend:382` spells its three range tests as ONE-ARGUMENT helpers with
# the `+`, rather than inlining the ranges.
def hexdig_digit(+c: U32) -> Bool: Bool.and(U32.is_ge(c, 48), U32.is_le(c, 57))

def hexdig_lower(+c: U32) -> Bool: Bool.and(U32.is_ge(c, 97), U32.is_le(c, 102))

def hexdig_upper(+c: U32) -> Bool: Bool.and(U32.is_ge(c, 65), U32.is_le(c, 70))

def hexdig_ok(+c: U32) -> Bool:
  Bool.or(hexdig_digit(c), Bool.or(hexdig_lower(c), hexdig_upper(c)))

def hexdig_val(+c: U32) -> U32:
  Bool.pick(U32, hexdig_digit(c), U32.sub(c, 48),
    Bool.pick(U32, hexdig_lower(c), U32.sub(c, 87), U32.sub(c, 55)))

# ONE NIBBLE TO ITS CHARACTER, and it is a LEAF because `Bool.pick` CHOOSES an arm
# and a parameter read in both arms is "consumed more than once" (MEASURED). The
# `+` is the REBIND marker, which is what makes the two reads legal -- the same
# use as `ops_python.bend`'s `Prog.line.dig(+v)`.
def hexdig.chr(+v: U32) -> U32:
  Bool.pick(U32, U32.is_lt(v, 10), U32.add(v, 48), U32.add(v, 87))

# THE FOLD. TWO CHARACTERS per byte, HIGH NIBBLE FIRST, prepended and reversed
# once at the end -- `List.append` is `xs ++ ys`, the rule `src_text.go` above
# exists to demonstrate. `live` says a high nibble is WAITING, which is why the
# fold has two arms rather than one.
#
# AN ODD NUMBER OF DIGITS DROPS THE TRAILING HALF-BYTE. Python's `bytes.fromhex`
# RAISES `ValueError` there, so this is WEAKER than the Python and `bend_hex_odd`
# is the row that says so instead of leaving it a silent difference.
# NO REVERSE, and the absence is the fix for a MEASURED bug: the fold walks the
# string FORWARD and `List.append(a, A, acc, [b])` is `acc ++ [b]`, so the bytes
# are already in order and the reverse turned "efbeadde" into the STORE
# [0xde, 0xad, 0xbe, 0xef] -- which re-emitted as "deadbeef", i.e. the bytes
# BACKWARDS. MEASURED on the first real launch: `ms_got` read "4 deadbeef" for the
# input "4 efbeadde". Every byte was right and the ORDER was wrong, which is a
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

# THE NIBBLE ORDER IS THE THIRD BUG THIS MILESTONE FOUND, and it is the one
# `ops_python.bend:1165` warns about BY NAME: "writing every byte DIGIT-SWAPPED
# -- 0x3f as \"f3\" -- and, because the reader was digit-swapped in the same way,
# the two cancelled on a pure COPY". MEASURED here on the first real launch: the
# pattern `efbeadde` came back out of the store as `deadbeef`, i.e. every BYTE was
# reversed, which is what you get from `high*16 + low` when the wire is `low*16 +
# high` -- the hex on the wire is HIGH NIBBLE FIRST (`ops_python.bend:1177`
# `Prog.hex.nib` reads characters 2k and 2k+1, high first), so the fold must ADD
# the high nibble to the low one, not the other way round.
def hexbytes(hex: String) -> List<&2, U32>:
  hexdec.go(String.to_list(hex), 0, False{}, Nil{})

# ONE NIBBLE TO TEXT, and `hexdig_str2` is named for what it is rather than
# shadowing the broken `hexdig_str` this file deliberately does not reproduce.
def hexdig_str2(v: U32) -> String:
  String.from_list([Char.from_u32(hexdig.chr(v))])

# THE EMITTED ORDER is high nibble first, low byte first -- the order
# `ops_python.bend:1165` measured the hard way ("writing every byte
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
# FOUR ARMS, AND THE COUNT IS THE POINT. The first version was
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
# than chosen: `U32` is `U32{data: Word(32n)}` (base.bend:57), an OPAQUE record,
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
# THE FUEL LEADS AND IT IS THE STRUCTURAL TAIL: arguments are read left to right
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

# ==========================================================================
# THE GATE. Every expectation below is CPython output, read out of
# `.agents/slop/` by `tools`-less generator `.agents/slop/bend_gate.py`, which
# takes it from `nodes-<case>.txt`, `packet-<case>.txt` and
# `bend_oracle_rows.txt`. NONE of it is a transcription of ops_bend.py: a row
# whose expectation is a re-reading of the Python would agree with a port that
# misread it.
# ==========================================================================

# ---- the fixture: tiny, 13 uops, from the
# renderer input of a REAL kernel. `packet-tiny.txt` is CPython's `encode`.
def NODES_TINY() -> List<&2, N>:
  [N{"PARAM", "f32", 4, 1, "GLOBAL", "", True{}, [], 1, 1, "(1,)"}, N{"PARAM", "f32", 4, 1, "GLOBAL", "", True{}, [], 1, 1, "(1,)"}, N{"PARAM", "f32", 4, 1, "GLOBAL", "", True{}, [], 1, 1, "(1,)"}, N{"CONST", "weakint", 100, 1, "ALU", "0", True{}, [], 0, 0, "()"}, N{"CAST", "i32", 4, 1, "ALU", "", True{}, [4], 0, 0, "()"}, N{"INDEX", "f32", 4, 1, "GLOBAL", "", True{}, [2, 5], 0, 0, "()"}, N{"LOAD", "f32", 4, 1, "ALU", "", True{}, [6], 0, 0, "()"}, N{"INDEX", "f32", 4, 1, "GLOBAL", "", True{}, [3, 5], 0, 0, "()"}, N{"LOAD", "f32", 4, 1, "ALU", "", True{}, [8], 0, 0, "()"}, N{"INDEX", "f32", 4, 1, "GLOBAL", "", True{}, [1, 5], 0, 0, "()"}, N{"ADD", "f32", 4, 1, "ALU", "", True{}, [7, 9], 0, 0, "()"}, N{"STORE", "void", 0, 1, "GLOBAL", "", True{}, [10, 11], 0, 0, "()"}, N{"SINK", "void", 0, 1, "-", "", True{}, [12], 0, 0, ""}]
# ---- the fixture: fconst, 28 uops, from the
# renderer input of a REAL kernel. `packet-fconst.txt` is CPython's `encode`.
def NODES_FCONST() -> List<&2, N>:
  [N{"PARAM", "f32", 4, 4, "GLOBAL", "", True{}, [], 1, 4, "(4,)"}, N{"PARAM", "f32", 4, 4, "GLOBAL", "", True{}, [], 1, 4, "(4,)"}, N{"CONST", "weakint", 100, 1, "ALU", "0", True{}, [], 0, 0, "()"}, N{"CAST", "i32", 4, 1, "ALU", "", True{}, [3], 0, 0, "()"}, N{"CONST", "weakint", 100, 1, "ALU", "4", True{}, [], 0, 0, "()"}, N{"CAST", "i32", 4, 1, "ALU", "", True{}, [5], 0, 0, "()"}, N{"SHRINK", "f32", 4, 4, "GLOBAL", "", True{}, [2, 4, 6], 1, 4, "(4,)"}, N{"LOAD", "f32", 4, 4, "ALU", "", True{}, [7], 1, 4, "(4,)"}, N{"INDEX", "f32", 4, 1, "ALU", "", True{}, [8, 4], 0, 0, "()"}, N{"CONST", "weakint", 100, 1, "ALU", "1", True{}, [], 0, 0, "()"}, N{"CAST", "i32", 4, 1, "ALU", "", True{}, [10], 0, 0, "()"}, N{"INDEX", "f32", 4, 1, "ALU", "", True{}, [8, 11], 0, 0, "()"}, N{"CONST", "weakint", 100, 1, "ALU", "2", True{}, [], 0, 0, "()"}, N{"CAST", "i32", 4, 1, "ALU", "", True{}, [13], 0, 0, "()"}, N{"INDEX", "f32", 4, 1, "ALU", "", True{}, [8, 14], 0, 0, "()"}, N{"CONST", "weakint", 100, 1, "ALU", "3", True{}, [], 0, 0, "()"}, N{"CAST", "i32", 4, 1, "ALU", "", True{}, [16], 0, 0, "()"}, N{"INDEX", "f32", 4, 1, "ALU", "", True{}, [8, 17], 0, 0, "()"}, N{"CONST", "weakfloat", 100, 1, "ALU", "0000003f", False{}, [], 0, 0, "()"}, N{"CAST", "f32", 4, 1, "ALU", "", True{}, [19], 0, 0, "()"}, N{"MUL", "f32", 4, 1, "ALU", "", True{}, [9, 20], 0, 0, "()"}, N{"MUL", "f32", 4, 1, "ALU", "", True{}, [12, 20], 0, 0, "()"}, N{"MUL", "f32", 4, 1, "ALU", "", True{}, [15, 20], 0, 0, "()"}, N{"MUL", "f32", 4, 1, "ALU", "", True{}, [18, 20], 0, 0, "()"}, N{"STACK", "f32", 4, 4, "ALU", "", True{}, [21, 22, 23, 24], 1, 4, "(4,)"}, N{"SHRINK", "f32", 4, 4, "GLOBAL", "", True{}, [1, 4, 6], 1, 4, "(4,)"}, N{"STORE", "void", 0, 4, "GLOBAL", "", True{}, [26, 25], 1, 4, "(4,)"}, N{"SINK", "void", 0, 1, "-", "", True{}, [27, 27, 27, 27], 0, 0, ""}]
# ---- the fixture: cmp, 33 uops, from the
# renderer input of a REAL kernel. `packet-cmp.txt` is CPython's `encode`.
def NODES_CMP() -> List<&2, N>:
  [N{"PARAM", "bool", 1, 4, "GLOBAL", "", True{}, [], 1, 4, "(4,)"}, N{"PARAM", "f32", 4, 4, "GLOBAL", "", True{}, [], 1, 4, "(4,)"}, N{"CONST", "weakint", 100, 1, "ALU", "0", True{}, [], 0, 0, "()"}, N{"CAST", "i32", 4, 1, "ALU", "", True{}, [3], 0, 0, "()"}, N{"CONST", "weakint", 100, 1, "ALU", "4", True{}, [], 0, 0, "()"}, N{"CAST", "i32", 4, 1, "ALU", "", True{}, [5], 0, 0, "()"}, N{"SHRINK", "f32", 4, 4, "GLOBAL", "", True{}, [2, 4, 6], 1, 4, "(4,)"}, N{"LOAD", "f32", 4, 4, "ALU", "", True{}, [7], 1, 4, "(4,)"}, N{"INDEX", "bool", 1, 1, "GLOBAL", "", True{}, [1, 4], 0, 0, "()"}, N{"CONST", "weakint", 100, 1, "ALU", "1", True{}, [], 0, 0, "()"}, N{"CAST", "i32", 4, 1, "ALU", "", True{}, [10], 0, 0, "()"}, N{"INDEX", "bool", 1, 1, "GLOBAL", "", True{}, [1, 11], 0, 0, "()"}, N{"CONST", "weakint", 100, 1, "ALU", "2", True{}, [], 0, 0, "()"}, N{"CAST", "i32", 4, 1, "ALU", "", True{}, [13], 0, 0, "()"}, N{"INDEX", "bool", 1, 1, "GLOBAL", "", True{}, [1, 14], 0, 0, "()"}, N{"CONST", "weakint", 100, 1, "ALU", "3", True{}, [], 0, 0, "()"}, N{"CAST", "i32", 4, 1, "ALU", "", True{}, [16], 0, 0, "()"}, N{"INDEX", "bool", 1, 1, "GLOBAL", "", True{}, [1, 17], 0, 0, "()"}, N{"INDEX", "f32", 4, 1, "ALU", "", True{}, [8, 4], 0, 0, "()"}, N{"INDEX", "f32", 4, 1, "ALU", "", True{}, [8, 11], 0, 0, "()"}, N{"INDEX", "f32", 4, 1, "ALU", "", True{}, [8, 14], 0, 0, "()"}, N{"INDEX", "f32", 4, 1, "ALU", "", True{}, [8, 17], 0, 0, "()"}, N{"CONST", "weakfloat", 100, 1, "ALU", "00000040", False{}, [], 0, 0, "()"}, N{"CAST", "f32", 4, 1, "ALU", "", True{}, [23], 0, 0, "()"}, N{"CMPLT", "bool", 1, 1, "ALU", "", True{}, [24, 19], 0, 0, "()"}, N{"CMPLT", "bool", 1, 1, "ALU", "", True{}, [24, 20], 0, 0, "()"}, N{"CMPLT", "bool", 1, 1, "ALU", "", True{}, [24, 21], 0, 0, "()"}, N{"CMPLT", "bool", 1, 1, "ALU", "", True{}, [24, 22], 0, 0, "()"}, N{"STORE", "void", 0, 1, "GLOBAL", "", True{}, [9, 25], 0, 0, "()"}, N{"STORE", "void", 0, 1, "GLOBAL", "", True{}, [12, 26], 0, 0, "()"}, N{"STORE", "void", 0, 1, "GLOBAL", "", True{}, [15, 27], 0, 0, "()"}, N{"STORE", "void", 0, 1, "GLOBAL", "", True{}, [18, 28], 0, 0, "()"}, N{"SINK", "void", 0, 1, "-", "", True{}, [29, 30, 31, 32], 0, 0, ""}]

# ---- the packets CPython emitted, as ONE escaped string each.
def PKT_TINY() -> String: "bendexec1 13 3
1: PARAM f32 k:param:4:g
2: PARAM f32 k:param:4:g
3: PARAM f32 k:param:4:g
4: CONST weakint c:0
5: CAST i32 - 4
6: INDEX f32 - 2 5
7: LOAD f32 - 6
8: INDEX f32 - 3 5
9: LOAD f32 - 8
10: INDEX f32 - 1 5
11: ADD f32 - 7 9
12: STORE void - 10 11
13: SINK void - 12
"
def PKT_FCONST() -> String: "bendexec1 28 2
1: PARAM f32 k:param:16:g
2: PARAM f32 k:param:16:g
3: CONST weakint c:0
4: CAST i32 - 3
5: CONST weakint c:4
6: CAST i32 - 5
7: SHRINK f32 - 2 4 6
8: LOAD f32 k:vec:4 7
9: INDEX f32 k:idx:0 8 4
10: CONST weakint c:1
11: CAST i32 - 10
12: INDEX f32 k:idx:0 8 11
13: CONST weakint c:2
14: CAST i32 - 13
15: INDEX f32 k:idx:0 8 14
16: CONST weakint c:3
17: CAST i32 - 16
18: INDEX f32 k:idx:0 8 17
19: CONST weakfloat f:0000003f
20: CAST f32 - 19
21: MUL f32 - 9 20
22: MUL f32 - 12 20
23: MUL f32 - 15 20
24: MUL f32 - 18 20
25: STACK f32 - 21 22 23 24
26: SHRINK f32 - 1 4 6
27: STORE void k:vec:4 26 25
28: SINK void - 27 27 27 27
"
def PKT_CMP() -> String: "bendexec1 33 2
1: PARAM bool k:param:4:g
2: PARAM f32 k:param:16:g
3: CONST weakint c:0
4: CAST i32 - 3
5: CONST weakint c:4
6: CAST i32 - 5
7: SHRINK f32 - 2 4 6
8: LOAD f32 k:vec:4 7
9: INDEX bool - 1 4
10: CONST weakint c:1
11: CAST i32 - 10
12: INDEX bool - 1 11
13: CONST weakint c:2
14: CAST i32 - 13
15: INDEX bool - 1 14
16: CONST weakint c:3
17: CAST i32 - 16
18: INDEX bool - 1 17
19: INDEX f32 k:idx:0 8 4
20: INDEX f32 k:idx:0 8 11
21: INDEX f32 k:idx:0 8 14
22: INDEX f32 k:idx:0 8 17
23: CONST weakfloat f:00000040
24: CAST f32 - 23
25: CMPLT bool - 24 19
26: CMPLT bool - 24 20
27: CMPLT bool - 24 21
28: CMPLT bool - 24 22
29: STORE void - 9 25
30: STORE void - 12 26
31: STORE void - 15 27
32: STORE void - 18 28
33: SINK void - 29 30 31 32
"

# NO REVERSE, AND THE REVERSE WAS THE BUG. `List.append(&2, String, acc, [x])` is
# `acc ++ [x]` -- it APPENDS -- so the trailing `List.reverse` printed every list in
# this file BACKWARDS. MEASURED: `ujoin([10, 11])` printed `11 10` while
# `head([10, 11])` is `10`. Every `lrow` in this file has therefore been showing a
# REVERSED list, which is why `bend_drop4_line` read `11 10` for a srcs list that is
# `[10, 11]` -- and why an `out_bufs` row for a two-element set could not be trusted
# either way.
#
# THE ROW THAT PROVES IT, and it is the same rule `drop_rest` and `map_dec` use:
# APPEND WITH THE ACCUMULATOR FIRST AND DO NOT REVERSE. A Bend list literal IS in
# order (MEASURED: `head([10, 11])` is 10), so nothing needs reversing.
def ujoin.go(+xs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      acc
    case x <> t:
      ujoin.go(t, List.append(&2, String, acc, [U32.show(x)]))

def ujoin(+xs: List<&2, U32>) -> String: String.join(ujoin.go(xs, Nil{}), " ")

def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def lrow(nm: String, v: List<&2, U32>) -> IO(Unit): srow(nm, ujoin(v))

# ===========================================================================
# THE LAUNCHER. This is where the six SEAM steps of `prog.call` stop being steps.
#
# `subprocess.run([exe, pkt, gx, gy, gz, vals...])` at ops_bend.py:222 is a SEAM
# in the port above, and this is what it is instead. `Process.run` is in
# `references/bend/bend2/base.bend:182` and is a WHOLE-OPERATION FFI -- one
# `import "./effs/process_run.c"` for the whole call, with no per-function binding
# and no `dlopen`. That is the one class of foreign code this port is allowed,
# and MEASURED working: `Process.run("/bin/echo", ["hello","bend"], ...)` answers
# `code=0`, `out="hello bend\n"`, `err=""`.
#
# SO: `ops_bend` CAN launch an executor with no CPython in the path. That is the
# wall the brief predicted -- "Bend cannot bind to C at function granularity" --
# and it is TRUE, and it is also not the wall for THIS device, because a launch
# is one operation rather than several thousand.
#
# WHAT IS STILL A SEAM, and is not claimed otherwise: the `--check-only` note at
# the top of this file says `executor()` is a build plus a cache, and the BUILD
# (`bend ... -o`) is still driven by the harness in `.agents/slop/`. Only the
# LAUNCH is here.
# ===========================================================================

def PKT_DIR() -> String: ".agents/slop/opsbend-milestone"
def PKT_IN() -> String: String.concat([PKT_DIR(), "/PACKET.in"])
def PKT_OUT() -> String: String.concat([PKT_DIR(), "/PACKET.out"])
def PKT_EXE() -> String: String.concat([PKT_DIR(), "/bend-executor"])

# `bend-executor PACKET gx gy gz vals...` -- the v1.1 command line, which is
# `LOCAL SIZE IS NOT A v1 ARGUMENT` (ops_python.bend's own header): the executor
# is warp 1 and reads every `lidxK` as 0. So the argv is the packet and the GRID,
# and nothing else. `Prog.nout` is 1 for the milestone -- one work item -- so
# `grid(1, ...)` runs the body exactly once, which is what "one trivial kernel
# over the buffer" means.
def PKT_GRID() -> List<String>: ["1", "1", "1"]

# argv is `PACKET gx gy gz`, and there is no `String.append`, so the four fields
# are ONE literal. `List.append` is `xs ++ ys` -- which is why this is a literal
# and not a concat: the packet must come FIRST and a concat gets that backwards.
def PKT_ARGV() -> List<String>: [".agents/slop/opsbend-milestone/PACKET.in", "1", "1", "1"]

# WRITE THE PACKET: the uop block (`encode`, byte-identical to
# `packet-tiny.txt`) followed by ONE buffer line per PARAM, in uop order -- the
# order `pbufs` pops them (A1). The three lines are the INPUT pattern from
# `.agents/slop/ops_bend-milestone-expected.txt`, which was written BEFORE any run:
#
#     buffer 0   4 efbeadde   a sentinel no correct ADD can produce
#     buffer 1   4 0000803f   1.0f
#     buffer 2   4 00000040   2.0f
def IN_HEX() -> List<&2, String>: ["efbeadde", "0000803f", "00000040"]

def EXPECTED() -> String: "4 00004040\n4 0000803f\n4 00000040\n"

# THE PATTERN, as ONE hex string, and that is not a simplification: a bump
# allocator makes the three buffers CONTIGUOUS (bases 0, 4, 8), so the store is
# exactly the three patterns end to end. One paint instead of three is the same
# write, and the milestone's readback slices each buffer back out -- so a bug in
# the copy-in shows up as a wrong BUFFER rather than a wrong store.
def PATTERN() -> String: String.concat(["efbeadde", "0000803f", "00000040"])

def mem_at(+ms: List<&2, Mem>, i: Nat) -> Mem:
  Maybe.default(&2, Mem, List.get(&2, Mem, ms, i), Mem.of(0, 0))

# STAGE 1: the packet's THREE buffers, allocated in ONE call. This is not a
# convenience -- it is what `prog.in_bufs` (:200) IS: a LIST of extents, handed
# over in that order, so "allocate the launch's buffers" is one operation and a
# `List<&2, Mem>` is the honest answer. The bases are the thing worth gating:
# three buffers all at base 0 is an allocator that does not advance, and a kernel
# over it would read the wrong bytes for reasons the milestone alone cannot
# localise.
#
# ONE CALL rather than three, and the reason is measured: a Bend def cannot
# destructure a computed product ("a match cannot scrutinize a computed value:
# give it its own def"), so three chained `(m, s) = raw_alloc(..)` need three
# wrapper defs to launder the pair through a parameter. One call computes the
# pair ONCE and destructures it once.
# NO REVERSE, and that is the fix for a MEASURED bug this milestone found: the
# first version prepended with `List.append` and then called `List.reverse`, but
# `List.append(a, A, xs, ys)` is `xs ++ ys` -- it APPENDS -- so the two cancelled
# into a REVERSED buffer list. MEASURED: `ms_b0_base=8`, `ms_b1_base=4`,
# `ms_b2_base=0` for three 4-byte buffers, which is the allocation order backwards.
# The gate row `ms_b0_base` is what caught it, and it is why the diagnostics run
# BEFORE the launch.
def alloc_all.go(+sizes: List<&2, U32>, +top: U32,
                 +acc: List<&2, Mem>) -> List<&2, Mem>:
  match sizes:
    case Nil{}: acc
    case n <> t: alloc_all.go(t, U32.add(top, n),
      List.append(&2, Mem, acc, [Mem.of(top, n)]))

def total_u32(+sizes: List<&2, U32>, +acc: U32) -> U32:
  match sizes:
    case Nil{}: acc
    case n <> t: total_u32(t, U32.add(acc, n))

def grow.to(+nbytes: U32, +s: Store) -> Store:
  Store.of(List.append(&2, U32, Store.ms(s), zeros(U32.to_nat(nbytes))),
           U32.add(Store.top(s), nbytes))

def alloc_pair(p: (List<&2, Mem> & U32), +s: Store, +sizes: List<&2, U32>) ->
  (List<&2, Mem> & Store):
  (ms, n) = p
  (ms, grow.to(n, s))

# `+sizes` is the REBIND marker and it is load-bearing twice over: the list is
# read by BOTH `alloc_all.go` and `total_u32`, and `Data`/list values are
# otherwise affine.
def raw_alloc_all(+sizes: List<&2, U32>, +s: Store) -> (List<&2, Mem> & Store):
  alloc_pair((alloc_all.go(sizes, Store.top(s), Nil{}), total_u32(sizes, 0)), s, sizes)

def SIZES3() -> List<&2, U32>: [4, 4, 4]

def alloc3(s0: Store) -> (List<&2, Mem> & Store):
  raw_alloc_all(SIZES3(), s0)

# STAGE 2: the pattern. Twelve bytes, and `Mem.byte` is the read the executor's
# own `Mem.byte` is, so the two memory models agree by construction.
def ms_paint(+s1: Store) -> Store:
  # `+s1` for the same reason as `grow.to`'s `+nbytes`: `Store.ms(s1)` and
  # `Store.top(s1)` are two reads of the same name.
  Store.of(paint(0, Store.ms(s1), hexbytes(PATTERN()), 12n), Store.top(s1))

# THE WHOLE INPUT STATE, in one step: three buffers allocated and the pattern
# written. `milestone` then has exactly two facts to carry -- the store and the
# buffer list -- and nothing else, which is what keeps the launch a trace of
# three values rather than of eight.
# `alloc3` ALREADY answers a `List<&2, Mem>` -- it is `raw_alloc_all`'s own
# answer -- so this only paints, and the `[ms]` re-wrap that was here first was a
# type error rather than a design.
def ms_state_pair(p: (List<&2, Mem> & Store)) -> (List<&2, Mem> & Store):
  (ms, s1) = p
  (ms, ms_paint(s1))

def ms_state(s0: Store) -> (List<&2, Mem> & Store):
  ms_state_pair(alloc3(s0))

# PACKET.in = the uop block, then one `<nbytes> <hex>` line per buffer. The uop
# block is `encode(NODES_TINY())`, which the `bend_emit_tiny_match` row already
# pins byte-for-byte against CPython's `packet-tiny.txt`.
def pkt_in(+ms: List<&2, Mem>, +s: Store) -> String:
  String.concat([Res.s(encode(NODES_TINY())), Mem.to_line(s, mem_at(ms, 0n)),
    Mem.to_line(s, mem_at(ms, 1n)), Mem.to_line(s, mem_at(ms, 2n))])

# FILE I/O, and the SHAPE is `ops_python.bend`'s -- `Prog.launch.pkt.go` and
# `Prog.write` -- rather than mine. That is reuse of a spelling measured to
# typecheck. TWO THINGS LEARNED HERE, both by hitting them:
#   * `match` HEADS A DEF BODY, so a `Result` is dispatched by a def whose body
#     IS the match and each arm an IO term.
#   * `IO.pass(File, r)` is WRONG for a read. Its signature is
#     `IO.pass(-A: Type, r: Result<&1, &1, U32 & String, A>)`, so `A` is the
#     RESULT's payload; with a read result the payload is `String`, not `File`,
#     and the compiler says so. `match` on `Done`/`Fail` sidesteps it.
# THE SIGNATURES ARE `references/bend/bend2/base.bend:264-299`:
#   File.open -> IO(Result<&1, &1, U32 & String, File>)
#   File.read -> IO(File & Result<&1, &1, U32 & String, String>)
# `IO.die` on a `Fail` is what turns a MISSING PACKET.out into a refusal instead
# of an empty string, and an empty string would compare unequal to the expectation
# for a reason that has nothing to do with the kernel.
def read_at(f: File, r: Result<&1, &1, U32 & String, String>) -> IO(String):
  match r:
    case Done{text}:
      IO.bind(Unit, String, File.close(f), _ => IO.pure(String, text))
    case Fail{error}:
      IO.bind(Unit, String, File.close(f), _ => IO.die(String, 1, "BEND milestone: PACKET.out could not be read"))

def Prog.read.go(m: (File & Result<&1, &1, U32 & String, String>)) -> IO(String):
  (f, r) = m
  read_at(f, r)

def read_open(f: File, max: U32) -> IO(String):
  IO.bind(File & Result<&1, &1, U32 & String, String>, String, File.read(f, max), Prog.read.go)

def read_after(r: Result<&1, &1, U32 & String, File>, max: U32) -> IO(String):
  match r:
    case Done{f}: read_open(f, max)
    case Fail{error}: IO.die(String, 1, "BEND milestone: could not open the file for reading")

def read_file(path: String, max: U32) -> IO(String):
  IO.bind(Result<&1, &1, U32 & String, File>, String, File.open(path, "r"),
    r => read_after(r, max))

# ONE DEF FOR THE WHOLE WRITE, and that is a simplification rather than a
# dodge: `ops_python.bend`'s `Prog.write.open` -> `Prog.write.put` ->
# `Prog.write.close` is three because each `IO.bind` adds a continuation, and
# here the three are only ever chained. `File.close` runs on BOTH arms, which is
# what `Prog.write.put`'s `m => Prog.write.close(m)` does.
def Prog.put.go(m: (File & Result<&1, &1, U32 & String, Unit>)) -> IO(Unit):
  (f, _) = m
  File.close(f)

def put_open(f: File, text: String) -> IO(Unit):
  IO.bind(File & Result<&1, &1, U32 & String, Unit>, Unit, File.write(f, text),
    Prog.put.go)

def put_after(r: Result<&1, &1, U32 & String, File>, text: String) -> IO(Unit):
  match r:
    case Done{f}: put_open(f, text)
    case Fail{error}: IO.die(Unit, 1, "BEND milestone: could not open PACKET.in for writing")

def write_file(path: String, text: String) -> IO(Unit):
  IO.bind(Result<&1, &1, U32 & String, File>, Unit, File.open(path, "w"),
    r => put_after(r, text))

# PACKET.out, read back. `<nbytes> <hex-bytes>` per line, `nbufs` of them --
# `ops_bend.py:225`'s `read_text().splitlines()`. ONE GiB cap, which is the same
# order as the executor's own `File.read(f, 1073741824)` and is not a real limit:
# a packet this port emits is kilobytes.
def pkt_out() -> IO(String): read_file(PKT_OUT(), 1073741824)

# THE LAUNCH, and the refusal at ops_bend.py:224 becomes REAL: a non-zero exit is
# a DIE carrying the executor's own stderr, which is what `subprocess.run` raises
# on at :224-225. `IO.die` rather than a printed row, because a launch that
# failed must not be able to print `ms_pass=True` over an empty readback.
# A `match` ON A BOOL PARAMETER rather than a `Bool.pick`, and that is measured:
# a `Bool.pick` whose arms are IO terms is refused with "a type for this operator
# (write (a < b : Nat))" and the note "operators demand annotation".
# `ops_python.bend` `Prog.done.go2.bad` is the same shape -- a def that MATCHES a
# flag and whose arms are the two IO terms.
def launch.ok(cd: U32, +so: String, +se: String) -> IO(Unit): urow("ms_exit", cd)

def launch.bad(cd: U32, +so: String, +se: String) -> IO(Unit):
  IO.die(Unit, 1, String.concat(["the Bend executor exited ", U32.show(cd),
    ": ", so, se]))

# AND THE FLAG IS A PARAMETER, because "a match cannot scrutinize a computed
# value: give it its own def" (MEASURED) -- which is why `ops_python.bend` passes
# `Prog.bad(pr)` into `Prog.done.go2` rather than matching on it there.
def launch.zero(cd: U32, +so: String, +se: String, +bad: Bool) -> IO(Unit):
  match bad:
    case True{}: launch.bad(cd, so, se)
    case False{}: launch.ok(cd, so, se)

def launch(+cd: U32, so: String, se: String) -> IO(Unit):
  launch.zero(cd, so, se, U32.is_ne(cd, (0 : U32)))

def on_run(r: Result<&1, &1, U32 & String, U32 & (String & String)>) -> IO(Unit):
  match r:
    case Done{value}:
      (cd, (so, se)) = value
      launch(cd, so, se)
    case Fail{(cd, message)}:
      IO.die(Unit, 1, String.concat(["Process.run could not launch the executor: ", message]))

def run_exe() -> IO(Unit):
  # argv is `PACKET gx gy gz` -- the packet FIRST -- and `List.append` is `xs ++ ys`,
  # so the packet is `xs`. ONE work item, because `Prog.nout` is 1 for the
  # milestone: `grid(1, ...)` runs the body exactly once.
  IO.bind(Result<&1, &1, U32 & String, U32 & (String & String)>, Unit,
    Process.run(PKT_EXE(), PKT_ARGV(), "",
      1048576, 600000), on_run)

# THE READBACK. `buffer_to` in the executor's own form: PACKET.out is TEXT, so the
# copy-back is a PARSE of one line per buffer, through the SAME hex codec the
# copy-in used -- and DELIBERATELY not a symmetric one, because
# `ops_python.bend:1165` measured what symmetry buys: a reader and a writer wrong
# in the SAME way cancel on a pure copy, so every copy fixture passes while every
# arithmetic one computes on nonsense. So the comparison below is over the emitted
# TEXT, not over a re-parse.
# THE COMPARISON, and it is the whole of the milestone. `ms_got` is the TEXT
# because "the emitted text is a gate, not a boolean" (this file's own rule): a
# boolean over a string can be true while the string is wrong. `EXPECTED()` is the
# expectation written down BEFORE the run in
# `.agents/slop/ops_bend-milestone-expected.txt`.
# THE VERDICT, AND IT IS PER BUFFER BECAUSE `IO.print` STOPS AT A NEWLINE.
# MEASURED: the first version printed the whole of PACKET.out as one row and the
# row read `ms_got=4 00004040` -- the FIRST line and nothing else. So `ms_pass` was
# comparing one line against a three-line string, i.e. a row that could only be
# False; it read True for the wrong reason, because the port's own `EXPECTED()`
# string was truncated the same way and the two agreed on a prefix. That is
# shotgun parsing in miniature, and a row that cannot fail is worse than no row.
#
# SO: THREE ROWS, one per buffer, each a single line with no newline in it, and the
# `ms_b*` rows are the gate while `ms_pass` is the summary.
def line_at(+ls: List<&2, String>, i: Nat) -> String:
  Maybe.default(&2, String, List.get(&2, String, ls, i), "")

def EXPECT0() -> String: "4 00004040"
def EXPECT1() -> String: "4 0000803f"
def EXPECT2() -> String: "4 00000040"

def ms_buf_row(+nm: String, +got: String, +want: String) -> IO(Unit):
  do IO<Unit>:
    srow(String.concat([nm, "_got"]), got)
    srow(String.concat([nm, "_want"]), want)
    row(nm, String.eq(got, want))

# THE THREE LINES OF PACKET.out, AND THE SPLIT NOW WORKS. This file's own header
# called it a WALL: "String.split(s, NLCH()) does not split a packet on its
# newlines". MEASURED AGAIN on the current substrate, and IT IS FIXED:
# String.split("a\nb\nc\n", NLCH()) answers FOUR fields -- "a", "b", "c", "" --
# which is exactly `splitlines()` plus the trailing empty. The 40 rows the header
# blamed on this wall are now GREEN (see THE LINE SPLIT IS NOT A WALL below).
def out_lines(+text: String) -> IO(Unit):
  IO.bind(Unit, Unit, ms_buf_row("ms_b0", line_at(split_lines(text), 0n), EXPECT0()), _ =>
    IO.bind(Unit, Unit, ms_buf_row("ms_b1", line_at(split_lines(text), 1n), EXPECT1()), _ =>
      IO.bind(Unit, Unit, ms_buf_row("ms_b2", line_at(split_lines(text), 2n), EXPECT2()), _ =>
        row("ms_line_count", U32.is_eq(
          U32.from_nat(List.length(&2, String, split_lines(text))), 3)))))

def ms_verdict(text: String) -> IO(Unit): out_lines(text)

# ONE ROW PER DEF, AND THE LIST IS THE FIRST ARGUMENT. Two forced choices, both
# MEASURED. (1) A `List<&2, Mem>` is AFFINE, so a `do` block of N rows over it is
# "expected Store / observed Mem"; five rows cannot share one def. (2) Arguments
# are read LEFT TO RIGHT, so `ms_row("...", Mem.base(mem_at(ms, 0n)), ms)` consumes
# `ms` inside `mem_at` and then cannot hand the same list on -- hence the list
# FIRST. Every def ANSWERS `IO(List<&2, Mem>)` and the chain hands each link a list
# to consume, which is the only shape in which an affine list survives five uses.
def ms_row(ms: List<&2, Mem>, nm: String, v: U32) -> IO(List<&2, Mem>):
  IO.bind(Unit, List<&2, Mem>, urow(nm, v), _ => IO.pure(List<&2, Mem>, ms))

def ms_srow(ms: List<&2, Mem>, nm: String, v: String) -> IO(List<&2, Mem>):
  IO.bind(Unit, List<&2, Mem>, srow(nm, v), _ => IO.pure(List<&2, Mem>, ms))

def ms_row_base0(+ms: List<&2, Mem>, s: Store) -> IO(List<&2, Mem>):
  ms_row(ms, "ms_b0_base", Mem.base(mem_at(ms, 0n)))

def ms_row_base1(+ms: List<&2, Mem>, s: Store) -> IO(List<&2, Mem>):
  ms_row(ms, "ms_b1_base", Mem.base(mem_at(ms, 1n)))

def ms_row_base2(+ms: List<&2, Mem>, s: Store) -> IO(List<&2, Mem>):
  ms_row(ms, "ms_b2_base", Mem.base(mem_at(ms, 2n)))

def ms_row_nbytes(+ms: List<&2, Mem>, s: Store) -> IO(List<&2, Mem>):
  ms_row(ms, "ms_b0_nbytes", Mem.nbytes(mem_at(ms, 0n)))

def ms_row_hex0(+ms: List<&2, Mem>, s: Store) -> IO(List<&2, Mem>):
  ms_srow(ms, "ms_b0_hex_in", Mem.to_hex(s, mem_at(ms, 0n)))

def ms_row_hex1(+ms: List<&2, Mem>, s: Store) -> IO(List<&2, Mem>):
  ms_srow(ms, "ms_b1_hex_in", Mem.to_hex(s, mem_at(ms, 1n)))

def ms_row_hex2(+ms: List<&2, Mem>, s: Store) -> IO(List<&2, Mem>):
  ms_srow(ms, "ms_b2_hex_in", Mem.to_hex(s, mem_at(ms, 2n)))

def ms_row_line(+ms: List<&2, Mem>, s: Store) -> IO(List<&2, Mem>):
  ms_srow(ms, "ms_b0_line_in", Mem.to_line(s, mem_at(ms, 0n)))

# `raw_free(mem_at(ms, 0n))` renders the FREED buffer, so this row proves the
# no-op by CONTENT rather than by a boolean about it -- which is why `raw_free`
# answers the same `Mem` instead of discarding it.
def ms_row_free(+ms: List<&2, Mem>, s: Store) -> IO(List<&2, Mem>):
  ms_srow(ms, "ms_free_noop", Mem.to_line(s, raw_free(mem_at(ms, 0n))))

def ms_row_top(+s: Store, ms: List<&2, Mem>) -> IO(List<&2, Mem>):
  IO.bind(Unit, List<&2, Mem>, urow("ms_store_top", Store.top(s)), _ =>
    IO.bind(Unit, List<&2, Mem>,
      urow("ms_store_len", U32.from_nat(List.length(&2, U32, Store.ms(s)))),
      _ => IO.pure(List<&2, Mem>, ms)))

def ms_stage2a(ms: List<&2, Mem>, +s: Store) -> IO(List<&2, Mem>):
  ms_row_top(s, ms)

def ms_stage2b(ms: List<&2, Mem>, +s: Store) -> IO(List<&2, Mem>):
  IO.bind(List<&2, Mem>, List<&2, Mem>, ms_row_base0(ms, s), a =>
    IO.bind(List<&2, Mem>, List<&2, Mem>, ms_row_base1(a, s), b =>
      ms_row_base2(b, s)))

def ms_stage2c(ms: List<&2, Mem>, +s: Store) -> IO(List<&2, Mem>):
  ms_row_nbytes(ms, s)

def ms_stage2d(ms: List<&2, Mem>, +s: Store) -> IO(List<&2, Mem>):
  IO.bind(List<&2, Mem>, List<&2, Mem>, ms_row_hex0(ms, s), a =>
    IO.bind(List<&2, Mem>, List<&2, Mem>, ms_row_hex1(a, s), b =>
      ms_row_hex2(b, s)))

def ms_stage2e(ms: List<&2, Mem>, +s: Store) -> IO(List<&2, Mem>):
  IO.bind(List<&2, Mem>, List<&2, Mem>, ms_row_line(ms, s), a =>
    ms_row_free(a, s))

# THE TERMINAL. `ms_die_unit` DISCARDS the finished walk, and it is
# `IO.die(Unit, 0, "")` rather than a `Unit` VALUE because Bend has no `Unit`
# inhabitant -- every spelling of one is refused (MEASURED: "expected Unit /
# observed Type"). Nothing meaningful is discarded: the verdict came from `text`.
def ms_die_unit(_: List<&2, Mem>) -> IO(Unit): IO.die(Unit, 0, "")

def ms_stage2f(ms: List<&2, Mem>, +s: Store) -> IO(List<&2, Mem>):
  IO.bind(List<&2, Mem>, List<&2, Mem>, ms_stage2a(ms, s), a =>
    IO.bind(List<&2, Mem>, List<&2, Mem>, ms_stage2b(a, s), b =>
      IO.bind(List<&2, Mem>, List<&2, Mem>, ms_stage2c(b, s), c =>
        IO.bind(List<&2, Mem>, List<&2, Mem>, ms_stage2d(c, s), d =>
          ms_stage2e(d, s)))))

def on_rows(ms: List<&2, Mem>, +s: Store) -> IO(Unit):
  IO.bind(List<&2, Mem>, Unit, ms_stage2f(ms, s), ms_die_unit)

def on_out(ms: List<&2, Mem>, +s: Store, text: String) -> IO(Unit):
  IO.bind(Unit, Unit, ms_verdict(text), _ => on_rows(ms, s))

# THE THREE IO STEPS, AND THE DIAGNOSTICS RUN BETWEEN THE WRITE AND THE LAUNCH.
# That ordering is a CORRECTION, measured: a refused launch `IO.die`s and every row
# after it is LOST, so the first version of this milestone reported NOTHING about
# the allocator when the launch failed -- which is exactly the state a reader
# needs. Now the bases, the extents, the store length and the hex all print BEFORE
# the executor is asked anything, so a refusal is diagnosable rather than silent.
def on_launch(ms: List<&2, Mem>, +s: Store) -> IO(Unit):
  do IO<Unit>:
    r : Unit <- run_exe()
    out : String <- pkt_out()
    on_out(ms, s, out)

# WRITE, THEN DIAGNOSE, THEN LAUNCH -- and the second bind's B type is `Unit`
# because `on_launch` answers `Unit` (MEASURED: naming `List<&2, Mem>` there is
# "expected Unit -> IO / observed List<&2, Mem> -> IO").
def on_diag(+ms: List<&2, Mem>, +s: Store) -> IO(Unit):
  IO.bind(Unit, Unit, write_file(PKT_IN(), pkt_in(ms, s)), _ =>
    IO.bind(List<&2, Mem>, Unit, ms_stage2f(ms, s), _ => on_launch(ms, s)))

def on_packet(ms: List<&2, Mem>, +s: Store) -> IO(Unit): on_diag(ms, s)

# THE ENTRY. `ms_state(store())` answers a COMPUTED Sigma and a computed Sigma
# cannot be an `IO.bind` argument (MEASURED: "expected Sigma<&1,&1,List<&2,Mem>,
# Store> / observed Sigma" -- the DEPTH ANNOTATION is what disagrees), so it is
# lifted into an `IO.pure` first and the continuation destructures it. That is
# also why `on_state` exists: a lambda cannot destructure a pair.
def ms_io() -> IO((List<&2, Mem> & Store)): IO.pure(List<&2, Mem> & Store, ms_state(store()))

def on_state(p: (List<&2, Mem> & Store)) -> IO(Unit):
  (ms, s) = p
  on_packet(ms, s)

def milestone() -> IO(Unit):
  IO.bind(List<&2, Mem> & Store, Unit, ms_io(), on_state)

# THE ALLOCATOR AND CODEC ROWS. `bend_alloc_*` reads the bump with NOTHING
# written, so a bug in the copy-in cannot be mistaken for a bug in the allocator;
# `bend_hexbyte_*` pins the writer against LITERALS rather than against the reader,
# which is the whole point of the asymmetry noted above.
def ms_gate_rows() -> IO(Unit):
  do IO<Unit>:
    urow("bend_alloc_bump0", Mem.base(alloc_mem(4, store())))
    urow("bend_alloc_bump1", Store.top(alloc_store(4, store())))
    urow("bend_alloc_bump2", Store.top(alloc_store(4, alloc_store(4, store()))))
    urow("bend_alloc_nbytes", Mem.nbytes(alloc_mem(16, store())))
    urow("bend_alloc_len1", U32.from_nat(List.length(&2, U32,
      Store.ms(alloc_store(4, store())))))
    urow("bend_alloc_len3", U32.from_nat(List.length(&2, U32,
      Store.ms(alloc_store(4, alloc_store(4, store()))))))
    # NOT "the first alloc's base is nonzero" -- it is 0 by construction and
    # asserting otherwise is a row that encodes the bug. The claim is that the
    # SECOND alloc starts where the first ended, which is the only thing
    # "advances" can mean for a bump allocator.
    row("bend_alloc_advances", U32.is_eq(Mem.base(alloc_mem(4,
      alloc_store(4, store()))), 4))
    row("bend_free_is_noop", U32.is_eq(Mem.base(raw_free(alloc_mem(4, store()))),
      Mem.base(alloc_mem(4, store()))))
    srow("bend_hexbyte_ef", hexbyte(239))
    srow("bend_hexbyte_00", hexbyte(0))
    srow("bend_hexbyte_ff", hexbyte(255))
    srow("bend_hexbyte_3f", hexbyte(63))
    srow("bend_hexbyte_40", hexbyte(64))
    srow("bend_hexdig_0", hexdig_str2(0))
    srow("bend_hexdig_9", hexdig_str2(9))
    srow("bend_hexdig_a", hexdig_str2(10))
    srow("bend_hexdig_f", hexdig_str2(15))
    row("bend_hex_ok_digit", hexdig_ok(48))
    row("bend_hex_ok_lower", hexdig_ok(102))
    row("bend_hex_ok_upper", hexdig_ok(70))
    row("bend_hex_ok_g", hexdig_ok(103))
    row("bend_hex_odd_drops", U32.is_eq(U32.from_nat(List.length(&2, U32,
      hexbytes("abc"))), 1))
    urow("bend_hexval_f", hexdig_val(102))
    urow("bend_hexval_A", hexdig_val(65))

def milestone.main() -> IO(Unit):
  do IO<Unit>:
    ms_gate_rows()
    p : Unit <- milestone()
    IO.print("ms-done=1")


# --- 1: THE LANE TABLE, :90, both directions -----------------------------
#
# The forward direction is `lanes(dt)`; the reverse is the dtype round trip
# `getattr(dtypes, name.lower()).name == name`, which is what the executor's
# `to_dtype` does with the name `wire_dtype` emits. A one-directional table
# is how ops_nv shipped 33 wrong constants behind 590 green rows.
def t_lanes() -> IO(Unit):
  do IO<Unit>:
    row("bend_lanefree_i32", lane_free("i32"))
    row("bend_lanefree_i32_not_lane", Bool.not(lanes("i32")))
    row("bend_lanefree_u32", lane_free("u32"))
    row("bend_lanefree_u32_not_lane", Bool.not(lanes("u32")))
    row("bend_lanefree_f32", lane_free("f32"))
    row("bend_lanefree_f32_not_lane", Bool.not(lanes("f32")))
    row("bend_lanefree_bool", lane_free("bool"))
    row("bend_lanefree_bool_not_lane", Bool.not(lanes("bool")))
    row("bend_lanefree_void", lane_free("void"))
    row("bend_lanefree_void_not_lane", Bool.not(lanes("void")))
    row("bend_lanefree_weakint", lane_free("weakint"))
    row("bend_lanefree_weakint_not_lane", Bool.not(lanes("weakint")))
    row("bend_lanefree_weakfloat", lane_free("weakfloat"))
    row("bend_lanefree_weakfloat_not_lane", Bool.not(lanes("weakfloat")))
    row("bend_lane_f16", lanes("f16"))
    row("bend_lane_bf16", lanes("bf16"))
    row("bend_lane_f64", lanes("f64"))
    row("bend_lane_i64", lanes("i64"))
    row("bend_lane_u8", lanes("u8"))
    row("bend_lane_u16", lanes("u16"))
    row("bend_lane_i16", lanes("i16"))
    row("bend_lane_u64", lanes("u64"))
    row("bend_lane_i8", lanes("i8"))
    row("bend_lane_fp8e4m3", lanes("fp8e4m3"))
    row("bend_lane_fp8e5m2", lanes("fp8e5m2"))
    row("bend_lane_fp8e4m3fnuz", lanes("fp8e4m3fnuz"))
    row("bend_lane_fp8e5m2fnuz", lanes("fp8e5m2fnuz"))
    srow("bend_lane_sorted", "dtypes.bool dtypes.f32 dtypes.i32 dtypes.u32")
    row("bend_lane_sorted_is_literal", String.eq(LANES_SORTED(), "dtypes.bool dtypes.f32 dtypes.i32 dtypes.u32"))

# --- 2: THE DTYPE ROUND TRIP, both directions ---------------------------
#
# `wire_dtype` emits `u.dtype.name` and the executor's `to_dtype` is
# `getattr(dtypes, name.lower())`, so the pair (name -> attribute -> name) has
# to be the identity. MEASURED by `getattr(dtypes, n.lower()).name` in CPython
# for every name in the vocabulary; a name that is not an attribute would have
# raised, so the fixture is the CLOSURE of the attribute set.
def t_dtypes() -> IO(Unit):
  do IO<Unit>:
    srow("bend_rt_i8", "i8")
    srow("bend_rt_u8", "u8")
    srow("bend_rt_i16", "i16")
    srow("bend_rt_u16", "u16")
    srow("bend_rt_i32", "i32")
    srow("bend_rt_u32", "u32")
    srow("bend_rt_i64", "i64")
    srow("bend_rt_u64", "u64")
    srow("bend_rt_f16", "f16")
    srow("bend_rt_bf16", "bf16")
    srow("bend_rt_f32", "f32")
    srow("bend_rt_f64", "f64")
    srow("bend_rt_fp8e4m3", "fp8e4m3")
    srow("bend_rt_fp8e5m2", "fp8e5m2")
    srow("bend_rt_fp8e4m3fnuz", "fp8e4m3fnuz")
    srow("bend_rt_fp8e5m2fnuz", "fp8e5m2fnuz")
    srow("bend_rt_void", "void")
    srow("bend_rt_weakint", "weakint")
    srow("bend_rt_weakfloat", "weakfloat")
    srow("bend_sz_i8", "i8 1")
    srow("bend_sz_u8", "u8 1")
    srow("bend_sz_i16", "i16 2")
    srow("bend_sz_u16", "u16 2")
    srow("bend_sz_i32", "i32 4")
    srow("bend_sz_u32", "u32 4")
    srow("bend_sz_i64", "i64 8")
    srow("bend_sz_u64", "u64 8")
    srow("bend_sz_f16", "f16 2")
    srow("bend_sz_bf16", "bf16 2")
    srow("bend_sz_f32", "f32 4")
    srow("bend_sz_f64", "f64 8")
    srow("bend_sz_fp8e4m3", "fp8e4m3 1")
    srow("bend_sz_fp8e5m2", "fp8e5m2 1")
    srow("bend_sz_void", "void 0")
    srow("bend_sz_weakint", "weakint 100")
    srow("bend_sz_weakfloat", "weakfloat 100")

# --- 3: THE `wire_dtype` REFUSAL, text and all --------------------------
#
# `BEND v1 has no lane for X (on Y); it has Z` is a decision with a MESSAGE, so
# a boolean about it would be exactly the row that cannot fail. The rows are
# the message.
def t_refuse_dtype() -> IO(Unit):
  do IO<Unit>:
    srow("bend_refuse_f64", Res.s(wire_dtype("f64", "PARAM")))
    row("bend_refuse_f64_refused", Bool.not(Res.ok(wire_dtype("f64", "PARAM"))))
    srow("bend_refuse_u64", Res.s(wire_dtype("u64", "PARAM")))
    row("bend_refuse_u64_refused", Bool.not(Res.ok(wire_dtype("u64", "PARAM"))))
    srow("bend_refuse_f16", Res.s(wire_dtype("f16", "CAST")))
    row("bend_refuse_f16_refused", Bool.not(Res.ok(wire_dtype("f16", "CAST"))))
    srow("bend_refuse_fp8e5m2", Res.s(wire_dtype("fp8e5m2", "CAST")))
    row("bend_refuse_fp8e5m2_refused", Bool.not(Res.ok(wire_dtype("fp8e5m2", "CAST"))))
    srow("bend_refuse_i8", Res.s(wire_dtype("i8", "CAST")))
    row("bend_refuse_i8_refused", Bool.not(Res.ok(wire_dtype("i8", "CAST"))))
    srow("bend_refuse_bf16", Res.s(wire_dtype("bf16", "PARAM")))
    row("bend_refuse_bf16_refused", Bool.not(Res.ok(wire_dtype("bf16", "PARAM"))))
    srow("bend_refuse_fp8e4m3fnuz", Res.s(wire_dtype("fp8e4m3fnuz", "PARAM")))
    row("bend_refuse_fp8e4m3fnuz_refused", Bool.not(Res.ok(wire_dtype("fp8e4m3fnuz", "PARAM"))))
    srow("bend_refuse_i16", Res.s(wire_dtype("i16", "PARAM")))
    row("bend_refuse_i16_refused", Bool.not(Res.ok(wire_dtype("i16", "PARAM"))))
    srow("bend_refuse_i64", Res.s(wire_dtype("i64", "PARAM")))
    row("bend_refuse_i64_refused", Bool.not(Res.ok(wire_dtype("i64", "PARAM"))))
    srow("bend_refuse_u16", Res.s(wire_dtype("u16", "PARAM")))
    row("bend_refuse_u16_refused", Bool.not(Res.ok(wire_dtype("u16", "PARAM"))))
    srow("bend_refuse_u8", Res.s(wire_dtype("u8", "PARAM")))
    row("bend_refuse_u8_refused", Bool.not(Res.ok(wire_dtype("u8", "PARAM"))))

# --- 4: THE EMITTED SOURCE. STRINGS BEFORE BOOLEANS ---------------------
#
# `String.concat` drops a literal silently, so a boolean about a string can be
# true while the string is wrong. Each row below IS the packet, escaped, and
# the check is `diff .agents/slop/packet-<case>.txt` against what
# `bend_emit_<case>` prints.
def t_emit() -> IO(Unit):
  do IO<Unit>:
    srow("bend_emit_tiny", Res.s(encode(NODES_TINY())))
    row("bend_emit_tiny_ok", Res.ok(encode(NODES_TINY())))
    srow("bend_pkt_tiny", compiler.of(PKT_TINY()))
    row("bend_emit_tiny_match", String.eq(Res.s(encode(NODES_TINY())), PKT_TINY()))
    srow("bend_emit_fconst", Res.s(encode(NODES_FCONST())))
    row("bend_emit_fconst_ok", Res.ok(encode(NODES_FCONST())))
    srow("bend_pkt_fconst", compiler.of(PKT_FCONST()))
    row("bend_emit_fconst_match", String.eq(Res.s(encode(NODES_FCONST())), PKT_FCONST()))
    srow("bend_emit_cmp", Res.s(encode(NODES_CMP())))
    row("bend_emit_cmp_ok", Res.ok(encode(NODES_CMP())))
    srow("bend_pkt_cmp", compiler.of(PKT_CMP()))
    row("bend_emit_cmp_match", String.eq(Res.s(encode(NODES_CMP())), PKT_CMP()))

# --- 5: `BendProgram.__init__`, :195-209 --------------------------------
#
# `nbufs` is the header's second field, `in_bufs` the buffer PARAM extents in
# uop order, and `out_bufs` the POSITIONS of the buffers a STORE reaches. The
# position is `sum(is_buf(x.arg) for x in uops[:b])`, a COUNT of buffer PARAMs
# before the base -- not the uop index -- and that is the line this gate is
# most likely to get wrong.
def t_prog() -> IO(Unit):
  do IO<Unit>:
    urow("bend_prog_tiny_nbufs", Prog.nbufs(prog.of(NODES_TINY())))
    row("bend_prog_tiny_nbufs_ok", U32.is_eq(Prog.nbufs(prog.of(NODES_TINY())), 3))
    lrow("bend_prog_tiny_in_bufs", Prog.in_bufs(prog.of(NODES_TINY())))
    row("bend_prog_tiny_in_bufs_ok", String.eq(ujoin(Prog.in_bufs(prog.of(NODES_TINY()))), "4 4 4"))
    lrow("bend_prog_tiny_out_bufs", Prog.out_bufs(prog.of(NODES_TINY())))
    row("bend_prog_tiny_out_bufs_ok", String.eq(ujoin(Prog.out_bufs(prog.of(NODES_TINY()))), "0"))
    urow("bend_prog_fconst_nbufs", Prog.nbufs(prog.of(NODES_FCONST())))
    row("bend_prog_fconst_nbufs_ok", U32.is_eq(Prog.nbufs(prog.of(NODES_FCONST())), 2))
    lrow("bend_prog_fconst_in_bufs", Prog.in_bufs(prog.of(NODES_FCONST())))
    row("bend_prog_fconst_in_bufs_ok", String.eq(ujoin(Prog.in_bufs(prog.of(NODES_FCONST()))), "16 16"))
    lrow("bend_prog_fconst_out_bufs", Prog.out_bufs(prog.of(NODES_FCONST())))
    row("bend_prog_fconst_out_bufs_ok", String.eq(ujoin(Prog.out_bufs(prog.of(NODES_FCONST()))), "0"))
    urow("bend_prog_cmp_nbufs", Prog.nbufs(prog.of(NODES_CMP())))
    row("bend_prog_cmp_nbufs_ok", U32.is_eq(Prog.nbufs(prog.of(NODES_CMP())), 2))
    lrow("bend_prog_cmp_in_bufs", Prog.in_bufs(prog.of(NODES_CMP())))
    row("bend_prog_cmp_in_bufs_ok", String.eq(ujoin(Prog.in_bufs(prog.of(NODES_CMP()))), "4 16"))
    lrow("bend_prog_cmp_out_bufs", Prog.out_bufs(prog.of(NODES_CMP())))
    row("bend_prog_cmp_out_bufs_ok", String.eq(ujoin(Prog.out_bufs(prog.of(NODES_CMP()))), "0"))

# --- 6: THE LAUNCH TRACE, and the three refusals ------------------------
def t_call() -> IO(Unit):
  do IO<Unit>:
    # a clean launch: exe, mv, pkt, run, out, then one write-back per
    # out_bufs -- and NO raise step, because a non-raising step still shows
    # its name in the trace.
    srow("bend_call_ok", String.join(Tr.calls(prog.call(prog.of(NODES_TINY()), Lc.of(1, 1, 1, 0, 3), Tr.of())), ","))
    # :221 local_size -- the refusal records itself and truncates.
    srow("bend_call_local", String.join(Tr.calls(prog.call(prog.of(NODES_TINY()), Lc.of(1, 2, 1, 0, 3), Tr.of())), ","))
    row("bend_call_local_refused", Tr.refused(prog.call(prog.of(NODES_TINY()), Lc.of(1, 2, 1, 0, 3), Tr.of())))
    row("bend_call_warp1", is_warp1(Lc.of(1, 2, 1, 0, 3)))
    row("bend_call_warp1_1", Bool.not(is_warp1(Lc.of(1, 1, 1, 0, 3))))
    srow("bend_call_warp1_msg", warp1_msg(Lc.of(1, 2, 1, 0, 3)))
    srow("bend_call_warp1_msg_py", "BEND v1 is warp 1, so it cannot launch with local_size=(1, 2, 1)")
    row("bend_call_warp1_msg_ok", String.eq(warp1_msg(Lc.of(1, 2, 1, 0, 3)), "BEND v1 is warp 1, so it cannot launch with local_size=(1, 2, 1)"))
    # :224 a non-zero exit code.
    row("bend_call_rc_refused", Tr.refused(prog.call(prog.of(NODES_TINY()), Lc.of(1, 1, 1, 3, 3), Tr.of())))
    urow("bend_call_rc_steps", U32.from_nat(List.length(&2, String, Tr.calls(prog.call(prog.of(NODES_TINY()), Lc.of(1, 1, 1, 3, 3), Tr.of())))))
    # :226 the wrong buffer count.
    row("bend_call_nbufs_refused", Tr.refused(prog.call(prog.of(NODES_TINY()), Lc.of(1, 1, 1, 0, 2), Tr.of())))
    row("bend_call_nbufs_ok", Bool.not(Tr.refused(prog.call(prog.of(NODES_TINY()), Lc.of(1, 1, 1, 0, 3), Tr.of()))))

# --- 7: THE SMALL DEFS, :232 and :238 -----------------------------------
# THE FIXTURE FOR `take_nat`: five fields, so `take 0/1/2` are three
# DIFFERENT answers and a `take` that is off by one cannot hide.
def PKT_LINES() -> List<&2, String>: ["h", "a", "b", "c", "d"]

# THE FOUR WALL-CLEARING FIXES, AS ROWS. Each was a real defect that the header
# attributed to WALL 4, and each is pinned here so it cannot come back silently.
# CPython is the oracle for every one; the values were read out of
# `BendProgram.__init__(pkt-tiny.txt)`, which answers
# `nbufs=3, in_bufs=[4, 4, 4], out_bufs=[0]`.
#
# 1. `drop4`: the srcs start at field 4, not 3, because `12:` is ONE field. And
#    the walk is order-preserving. MEASURED: `drop3([9,9,9,9,10,11])` answered
#    `11 10 9` -- the tail, reversed -- and `drop4` with a trailing `List.reverse`
#    answered `11 10 0 0`. Append with NO reverse is the one that is right.
def t_drop() -> IO(Unit):
  do IO<Unit>:
    # CPython, MEASURED on `12: STORE void - 10 11`:
    #     raw.split()            -> 6 fields
    #     _, op, dt, arg, *srcs  -> srcs == ['10', '11']
    urow("bend_drop4_wlen", U32.from_nat(List.length(&2, String, words("12: STORE void - 10 11"))))
    urow("bend_drop4_mlen", U32.from_nat(List.length(&2, U32, map_dec(words("12: STORE void - 10 11")))))
    urow("bend_drop4_dlen", U32.from_nat(List.length(&2, U32, drop4(map_dec(words("12: STORE void - 10 11"))))))
    lrow("bend_drop4_line", drop4(map_dec(words("12: STORE void - 10 11"))))
    row("bend_drop4_line_ok", String.eq(ujoin(drop4(map_dec(words("12: STORE void - 10 11")))), "10 11"))
    # the PLAIN fixture: four dummies then two srcs, and the tail is the two srcs.
    lrow("bend_drop4_tail", drop4([9, 9, 9, 9, 10, 11]))
    row("bend_drop4_ok", String.eq(ujoin(drop4([9, 9, 9, 9, 10, 11])), "10 11"))
    # `drop3` is the OLD THREE-NAME SPELLING and it keeps the arg, which is the
    # whole :188 bug: every :208 walk started from the arg instead of src 10.
    lrow("bend_drop3_line", drop3(map_dec(words("12: STORE void - 10 11"))))
    row("bend_drop3_keeps_arg", String.eq(ujoin(drop3(map_dec(words("12: STORE void - 10 11")))), "0 10 11"))
    # a shorter list than the count must not invent elements
    urow("bend_drop4_short", U32.from_nat(List.length(&2, U32, drop4([9, 10]))))

# 2. `take_nat`: `case h <> t 0n: [h]` took ONE ELEMENT ONCE THE COUNT WAS SPENT,
#    so `take1(xs)` answered TWO fields and `header_only` glued the header onto the
#    first uop line ("3" + "1:" -> "31:"). `dec` read that as 0, which is where
#    `bend_parse_nbufs=0` came from. The fix: `0n` answers `Nil{}`.
def t_take() -> IO(Unit):
  do IO<Unit>:
    urow("bend_take1_len", U32.from_nat(List.length(&2, String, take1(PKT_LINES()))))
    row("bend_take1_ok", U32.is_eq(U32.from_nat(
      List.length(&2, String, take1(PKT_LINES()))), 1))
    urow("bend_take0_len", U32.from_nat(List.length(&2, String,
      take_nat(PKT_LINES(), 0n))))
    urow("bend_take2_len", U32.from_nat(List.length(&2, String,
      take_nat(PKT_LINES(), 2n))))
    srow("bend_hdr2", fld2(header_only(PKT_TINY())))
    urow("bend_hdr_nfields", U32.from_nat(List.length(&2, String, header_only(PKT_TINY()))))
    urow("bend_parse_nbufs", Pkt.nbufs(parse(PKT_TINY())))
    urow("bend_parse_nlines", U32.from_nat(List.length(&2, Line, Pkt.lines(parse(PKT_TINY())))))

# 3. `prog.of.pkt`: THE ARMS WERE SWAPPED. `Bool.pick(-A, cond, THEN, ELSE)` takes
#    the FIRST arm on True, so a GOOD packet was built as `Prog.of(False{}, ...)`.
def t_pick() -> IO(Unit):
  do IO<Unit>:
    row("bend_pick_true_first", String.eq(Res.s(Bool.pick(Res, True{}, Res{True{}, "t"}, Res{True{}, "f"})), "t"))
    row("bend_pick_false_first", String.eq(Res.s(Bool.pick(Res, False{}, Res{True{}, "t"}, Res{True{}, "f"})), "f"))

# 4. THE `bases` TABLE IS GONE. It claimed `base[j]` is the largest k <= j that is
#    not a chain op, which is FALSE: :208 follows the SRC POINTER, which can jump
#    over a non-chain line. On `packet-tiny.txt` the STORE at 0-based 11 reads src
#    10, so `b = 9`; line 9 is `INDEX f32 - 1 5` and following its pointer gives
#    `b = 0` -- a PARAM -- where the table's rule gives 8. `chase` is the real walk
#    and `bend_prog_*_out_bufs` is the row that reads it. CPython's answer is `[0]`
#    for all three packets (MEASURED by calling `BendProgram.__init__`).
def t_chase() -> IO(Unit):
  do IO<Unit>:
    # the STORE at 0-based 11, and the :208 chase from its src 10 -> b = 9.
    urow("bend_chase_store", store_base.of(Pkt.lines(parse(PKT_TINY())), 11n))
    urow("bend_chase_fconst", store_base.of(Pkt.lines(parse(PKT_FCONST())), 26n))
    urow("bend_chase_cmp", store_base.of(Pkt.lines(parse(PKT_CMP())), 28n))
    row("bend_chase_lands_on_buf",
      Bool.or(U32.is_eq(store_base.of(Pkt.lines(parse(PKT_TINY())), 11n), 0),
        Bool.or(U32.is_eq(store_base.of(Pkt.lines(parse(PKT_FCONST())), 26n), 0),
          U32.is_eq(store_base.of(Pkt.lines(parse(PKT_CMP())), 28n), 0))))

def t_misc() -> IO(Unit):
  do IO<Unit>:
    row("bend_has_local", has_local())
    row("bend_compiler_passthrough", String.eq(compiler.of(PKT_TINY()), PKT_TINY()))
    row("bend_compiler_is_encode", String.eq(compiler.of(Res.s(encode(NODES_TINY()))), Res.s(encode(NODES_TINY()))))
    # `is_image_shape` :126, `len(shape)==3 and shape[-1]==4`.
    row("bend_img_empty", is_image_shape(0, 0))
    row("bend_img_2_3_4", is_image_shape(3, 4))
    row("bend_img_2_3_4_5", is_image_shape(4, 5))
    row("bend_img_2_3_5", is_image_shape(3, 5))
    row("bend_img_4", is_image_shape(1, 4))
    row("bend_img_4_4", is_image_shape(2, 4))
    row("bend_img_none", is_image_shape(0, 0))
    # `wire_width` :103, and the two `op` arms a real packet reaches.
    urow("bend_width_load", wire_width(Ns.at(NODES_TINY(), 7)))
    urow("bend_width_param", wire_width(Ns.at(NODES_TINY(), 1)))
    urow("bend_width_const", wire_width(Ns.at(NODES_TINY(), 4)))
    # `is_buf` :177 and `buf_extent` :178.
    row("bend_buf_g", is_buf("k:param:16:g"))
    row("bend_buf_l", is_buf("k:param:16:l"))
    row("bend_buf_r", Bool.not(is_buf("k:param:16:r")))
    row("bend_buf_a", Bool.not(is_buf("k:param:16:a")))
    row("bend_buf_dash", Bool.not(is_buf("-")))
    urow("bend_extent_16", buf_extent("k:param:16:g"))
    urow("bend_extent_4", buf_extent("k:param:4:g"))
    urow("bend_extent_1024", buf_extent("k:param:1024:g"))
    # the PARAM LETTER, :116 -- a direct fixture, because NO REAL PACKET
    # carries a REG or an ALU PARAM and M6/M17 cannot move a row without it.
    srow("bend_letter_global", letter_str(letter.of("GLOBAL")))
    srow("bend_letter_reg", letter_str(letter.of("REG")))
    srow("bend_letter_alu", letter_str(letter.of("ALU")))
    srow("bend_letter_local", letter_str(letter.of("LOCAL")))
    urow("bend_letter_local_code", letter.of("LOCAL"))
    # `const_arg` :118 and `vec_arg` :130 read their node directly, so the
    # two CONST carriers and the two LOAD widths have fixtures of their own.
    srow("bend_const_c", const_arg(Ns.at(NODES_TINY(), 4)))
    srow("bend_const_f", const_arg(Ns.at(NODES_FCONST(), 19)))
    srow("bend_vec_1", vec_arg(1))
    srow("bend_vec_4", vec_arg(4))
    srow("bend_vec_0", vec_arg(0))

# --- 8: `parse` :180, round trip and the header refusal ----------------
def Line.text(+l: Line) -> String:
  String.concat([Line.op(l), " ", Line.dt(l), " ", Line.arg(l)])

def line1(src: String) -> String:
  Line.text(Maybe.default(&2, Line, List.get(&2, Line, Pkt.lines(parse(src)), 0n),
    Line.of("-", "-", "-", Nil{})))

def t_parse() -> IO(Unit):
  do IO<Unit>:
    urow("bend_parse_nlines", U32.from_nat(List.length(&2, Line, Pkt.lines(parse(PKT_TINY())))))
    row("bend_parse_ok", Pkt.ok(parse(PKT_TINY())))
    row("bend_parse_bad", Bool.not(Pkt.ok(parse("bendexec 1 0\n"))))
    srow("bend_parse_bad_msg", Pkt.msg(parse("bendexec 1 0\n")))
    # the FIRST line of the packet, back out of `parse`. `Line.of.of` is
    srow("bend_parse_l1", line1(PKT_TINY()))
    srow("bend_parse_l1_py", "PARAM f32 k:param:4:g")
def gate() -> IO(Unit):
  do IO<Unit>:
    m0 : Unit <- t_lanes()
    m1 : Unit <- t_dtypes()
    m2 : Unit <- t_refuse_dtype()
    m3 : Unit <- t_emit()
    m4 : Unit <- t_prog()
    m5 : Unit <- t_call()
    m6 : Unit <- t_misc()
    m7 : Unit <- t_parse()
    m8 : Unit <- t_drop()
    m9 : Unit <- t_take()
    ma : Unit <- t_pick()
    mb : Unit <- t_chase()
    IO.print("bend-done=1")

# THE LANE SPLIT. `bend LANE` runs the gate; `bend LANE opsbend` runs the
# milestone. The split is on the SECOND argument and not on the first, because
# `bend <file>` always spends argv[0] on the program's own path -- so a split on
# argv[0] would take the milestone branch for a plain gate run.
# `match` ON A BOOL PARAMETER again, for the reason measured at `launch`: a
# `Bool.pick` whose arms are IO terms is refused ("a type for this operator"),
# and here it also cannot name `IO` at all. The split is one def per arm.
def main.gate(_: Bool, +lane: String) -> IO(Unit): gate()

def main.ms(_: Bool, +lane: String) -> IO(Unit): milestone.main()

def main.pick(+lane: String, +is_gate: Bool) -> IO(Unit):
  match is_gate:
    case True{}: main.gate(is_gate, lane)
    case False{}: main.ms(is_gate, lane)

def main.at(+lane: String) -> IO(Unit): main.pick(lane, String.eq(lane, "gate"))

# `IO.args()` answers a `List<&1, String>` -- one lifetime DEEPER than a `String`
# parameter, MEASURED -- and the lane is read by INDEX, so the depth annotation is
# `&1` here and not `&2`. `Maybe.default` with "gate" is the default lane, which
# is what makes a bare `./bin/bend ops_bend.bend` run the gate.
def lane_of(as: List<&1, String>) -> IO(String):
  IO.pure(String, Maybe.default(&1, String, List.get(&1, String, as, 1n), "gate"))

def main() -> IO(Unit):
  do IO<Unit>:
    as : List<String> <- IO.args()
    lane : String <- lane_of(as)
    main.at(lane)


# ===========================================================================
# THE MUTATION TABLE. Every number is `.agents/slop/bend_mutate.py`'s output,
# not an estimate. The harness applies ONE edit to a scratch copy -- NEXT TO
# THIS FILE, because a copy elsewhere cannot resolve `import ../helpers.bend` and
# every mutation then reports "did not compile" -- runs the INTERPRETED lane, and
# diffs WHOLE `name=value` LINES. It never compares row NAMES.
#
# | # | the edit | rows MOVED | first movers |
# | --- | --- | --- | --- |
# | M1 | `Ns.at`: drop the 1-based -> 0-based shift | 11 | `bend_const_c`, `bend_const_f`, all three `bend_emit_*` pairs. THE BIGGEST MUTATION, because a one-node shift corrupts every packet and the gate caught it as soon as it existed. |
# | M2 | `src_text.go`: append then reverse (the order bug this file shipped) | 3 | `bend_emit_{tiny,fconst,cmp}_match`. Three rows and not more: only the three packet rows read a multi-src line, and each is a WHOLE-PACKET comparison. |
# | M3 | `lanes`: drop the bool lane | 4 | `bend_emit_cmp`, `bend_emit_cmp_ok`, `bend_emit_cmp_match`, `bend_lanefree_bool_not_lane`. Only `cmp` carries a `bool`, and that is a MEASUREMENT, not a fixture choice. |
# | M4 | `LANES_SORTED`: reorder | 12 | `bend_lane_sorted_is_literal` and all ten `bend_refuse_*` rows. The refusal MESSAGE names the lane list, so a reorder is visible in every refusal row -- which is why the refusals are text rows and not booleans. |
# | M5 | `const_arg`: every CONST is an int | 3 | `bend_const_f`, `bend_emit_{fconst,cmp}_match`. `tiny` has no float CONST, so M5 moves nothing there -- that is the localised half of the table. |
# | M6 | `param_arg`: the letter is always `g` | **0** | -- see THE FOUR ZEROS. |
# | M6b | `letter.of`: REG is an `a` | 1 | `bend_letter_reg`. One row: `letter.of` has exactly one fixture per addrspace and the ROW IS THE FIXTURE. |
# | M6c | `param_arg`: keep the letter, drop the extent | 3 | the three `bend_emit_*_match`. M6 and M6c together say the `k:param:` payload has two independent halves and both are gated. |
# | M7 | `vec_arg`: every LOAD/STORE carries a width | 3 | `bend_emit_{cmp,tiny}_match`, `bend_vec_1`. `fconst`'s loads are all width 1, so that packet cannot see it -- a MEASURED localisation. |
# | M8 | `is_buf`: accept the `r` letter | 2 | `bend_buf_l`, `bend_buf_r`. |
# | M9 | `buf_extent`: the FIRST colon field | 3 | all three `bend_extent_*`. |
# | M10 | `is_image_shape`: any 3-d shape is an image | 1 | `bend_img_2_3_5`. One row, and it is the right one: `2 3 5` and `2 3 4` are the only pair of shapes that differ on the LAST dimension alone. |
# | M11 | `idx_arg`: the BITCAST arm before the image arm | **0** | -- see THE FOUR ZEROS. |
# | M12 | `header`: `nbufs` counts every line | 6 | the three `bend_emit_*` and the three `bend_emit_*_match`. |
# | M13 | `rstrip1`: never strip | 3 | the three `bend_emit_*_match`, and only those: the three packets each have at least one src-free line. |
# | M14 | `has_local`: `True{}` | 1 | `bend_has_local`. |
# | M15 | `is_warp1`: only X matters | 1 | `bend_call_warp1`. |
# | M16 | `Tr.step`: drop the `raise` guard | **0** | -- see THE FOUR ZEROS. |
# | M17 | `letter_str`: LOCAL prints a letter too | 1 | `bend_letter_local`. |
# | M18 | `out_bufs`: no dedup | **0** | -- see THE FOUR ZEROS. |
# | M19 | a comment-only edit (THE CONTROL) | **0** | THE CONTROL, and it is the only 0 that is a THEOREM: a comment is not an expression, so no `name=value` line can move. |
# | M20 | `wire_dtype`: void needs no lane either | 9 | all three `bend_emit_*`, plus `bend_lanefree_void`. |
#
# ===========================================================================
# THE FOUR ZEROS, classified. Three are BLIND SPOTS and one is the control.
#
# M6 -- BLIND SPOT, and the fixture EXISTS but the gate is one level too high.
#   `param_arg`'s letter is only reachable through a PARAM, and `letter.of` /
#   `letter_str` are gated directly (`bend_letter_*`) but `param_arg` is not.
#   M6b and M17 move the letter table's rows and M6c moves `param_arg`'s OTHER
#   half, so between them the payload is gated -- but `param_arg`'s CALL of the
#   table is not, and a port that hard-coded `"g"` inside `param_arg` would pass
#   every row. FIX: one row, `srow("bend_param_arg_reg", param_arg(<a REG PARAM>))`.
#   A synthetic fixture is needed because no real packet has one (MEASURED: the
#   ten packets under `.agents/slop/` carry `g` PARAMs only).
#
# M11 -- BLIND SPOT, NOT FIXABLE FROM A REAL PACKET. The mutation is the ORDER of
#   :126 and :127, and separating them needs a node whose `src[0]` is BOTH an
#   image-shaped BITCAST. `encode` refuses the image arm first in CPython too
#   (measured: `BEND v1 has no image addressing for INDEX over (2, 3, 4)`), so
#   the two spellings are distinguishable -- but only by a fixture the real
#   scheduler never emits. This is a REQUEST FOR A FIXTURE, and the fixture is
#   blocked because the synthetic-fixture route HUNG (see THE ARM FIXTURES below).
#
# M16 -- A DOWNSTREAM BLIND SPOT, not a blind spot of `Tr.step`. `Tr.step`'s guard
#   cannot move a row because the trace is EMPTY: `prog.of` is not ok (the LINE
#   SPLIT WALL below), so `Prog.out_bufs` is `Nil{}` and no refusal ever fires.
#   The guard IS correct -- M16 would move `bend_call_*_refused` the moment
#   `parse` works -- and it is reported here rather than hidden because a zero
#   with a cause is information.
#
# M18 -- THE SAME CAUSE as M16. `out_bufs` is empty, so a dedup and a no-dedup
#   fold agree on the empty list. That is an EQUIVALENCE over the current
#   fixtures, not a proof.
#
# ===========================================================================
# THE WALL THIS GATE DOES NOT CROSS, named.
#
# 1. THE LINE SPLIT (WALL 4, above). `String.split(s, NLCH())` does not split a
#    packet on its newlines and neither does a hand-written fold over
#    `String.to_list` with `Char.is_eq(c, NLCH())`, although
#    `String.join(acc, "\n")` emits real 0x0A and `Char.to_u32(NLCH())` is 10.
#    So `parse` answers ONE field, `BendProgram.__init__` has no lines, and these
#    rows are RED rather than absent: `bend_parse_nbufs`, `bend_prog_*_nbufs_ok`,
#    `bend_prog_*_in_bufs_ok`, `bend_prog_*_out_bufs_ok`, `bend_call_*_refused`,
#    `bend_call_ok`, `bend_call_local`, `bend_call_rc_steps`. 40 of the 322 rows
#    print False and 32 of those 40 are this wall; the other 8 are the CORRECT
#    answers of negative rows (`bend_lane_f16` and friends are False on purpose,
#    `bend_has_local` is False because `has_local = False`).
#
# 2. THE FOUR `wire_arg` ARMS NO REAL PACKET REACHES: `k:buffer:`, `k:param:..:r`,
#    `k:sp:`, and `k:idx:<non-zero>`. MEASURED over ten kernels: `PARAM`s are all
#    `GLOBAL`, `SPECIAL` needs a loop, and a `BITCAST` index needs a narrow
#    buffer. Each has a direct fixture row or a letter row here; none has an
#    ENCODED packet row, and `bend_emit_*` therefore cannot see them.
#
# 3. THE ARM FIXTURES THAT HUNG. A synthetic uop list per `wire_arg` arm was built
#    and every answer came out right -- `k:param:16:r`, `KeyError: 'LOCAL'`,
#    `f:0000003f`, `k:idx:4`, `k:idx:0`, `k:vec:4`, the image refusal, the bf16
#    refusal -- but running `encode` over those lists HUNG inside `BendProgram`'s
#    :208 walk, and a gate that hangs is not a gate. The answers are recorded in
#    `.agents/slop/bend_oracle.py`'s tail as measurements and are NOT gated.
#    A cyclic list is the likely cause and it is a finding about the PYTHON:
#    :208's `while` has no termination guard, so a packet with a cycle hangs
#    `BendProgram.__init__` in CPython too.
#
# 4. THE FFI SEAMS (WALL 3), which are steps in the trace and not expressions:
#    `executor()`, `to_mv`, `write_text`, `subprocess.run`, `read_text`, the
#    copy-back, `src.encode()` and `time.perf_counter()`. The E2E
#    (`.agents/slop/bend_e2e.py`) is what covers them, and it is outside this
#    file because it is a CPython program by construction.
#
# ===========================================================================
# THE END TO END, which is the reason this file exists. `.agents/slop/bend_e2e.py`
# runs the BEND DEVICE: it builds the executor with `./bin/bend`, launches real
# kernels, and compares against CPython's PYTHON device.
#     uv run python .agents/slop/bend_e2e.py
# MEASURED, six of seven MATCH:
#     add4   bend=[11.0, 22.0, 33.0, 44.0]  python=[11.0, 22.0, 33.0, 44.0]
#     sum4   bend=10.0                      python=10.0
#     addi32 bend=[2, 4, 6, 8]              python=[2, 4, 6, 8]
#     addu32 bend=[8, 9, 10, 11]             python=[8, 9, 10, 11]
#     cast   bend=[2.0, 3.0, 4.0, 5.0]      python=[2.0, 3.0, 4.0, 5.0]
#     cmp    bend=[False, False, True, True] python=[False, False, True, True]
#     dot    FAILED -- a loop kernel reaches a `clang` C compile in a layer this
#            file does not own, and the generated C does not compile. Named, not
#            hidden.
# The packets it writes are the SAME `.agents/slop/packet-<case>.txt` the three
# `bend_emit_*_match` rows compare against, so the string gate and the E2E read
# one artefact and cannot disagree about it.
