# tc_ptx.bend -- tinygrad/renderer/tc.py (141 lines) AND tinygrad/renderer/
# ptx.py (231 lines), in ONE file because the two are one feature: `ptx.py:4`
# imports `tc`, `PTXRenderer.__init__` picks its `tensor_cores` out of
# `tc.get_cuda`, and `render_wmma` reads the fragment tables `tc.py` builds.
#
# THE CONVENTIONS are `renderer/__init__.bend`'s HEADER, read in full; this file
# obeys all twelve. The four that bite hardest here:
#
#   1. A RENDERER IS A `Data` RECORD OF ITS OPTIONS, not a class. Python's
#      `PTXRenderer` has ten class attributes (`suffix`, the three maxima,
#      `code_for_op`, `extra_matcher`, `kernel_prefix`, `barrier`, `types`,
#      `mem_types`, `cast_types`) and `tc.TensorCore` has five fields; both are
#      records here and `ptx_of(arch)` IS the inheritance -- one constructor per
#      device, nothing mutating after it. Python's `__init__` mutating
#      `self.extra_matcher` (ptx.py:147) is a mutation too, and it is a wall
#      (the rules are rewrites), so it is named rather than faked.
#   2. THE GATE IS A STRING DIFF, NEVER A BOOLEAN ABOUT STRINGS. Every row
#      prints `<name> = [BEND]   py=[CPYTHON]` and the `py=` half is a literal
#      transcribed from `.agents/slop/tcptx-oracle.py` run against this
#      `tinygrad/`. `String.concat` drops a literal silently, so a row that
#      said "the asm is right" would survive a missing `;`.
#   4. A `match` MAY ONLY SCRUTINISE A PARAMETER OR A PATTERN BINDER, so every
#      record field has a hand-written reader (there is no `value.field` sugar
#      and no generated projection -- brief rules 26 and 27) and every
#      derived-property dispatch takes its `Bool`/`U32` as a parameter.
#   6. A RECORD LITERAL AND A RECORD PATTERN BOTH NAME EVERY FIELD.
#
# ---------------------------------------------------------------------------
# THE GATE. 620 rows: 286 from tc.py and 334 from ptx.py, plus the one
# framing newline `IO.print` supplies at the end. The oracle's `rows`
# is a plain concatenation of the two stages, so the Bend side is ONE print --
# `IO.print`'s own newline is the only frame, and it is the one `"\n"` the
# oracle's `sys.stdout.write(... + "\n")` supplies.
#   python3 .agents/slop/tcptx-oracle.py rows > .agents/slop/tcptx/pyall.txt
#   ./bin/bend tinybendygrad/renderer/tc_ptx.bend > /tmp/bd_i.txt
#   ./bin/bend tinybendygrad/renderer/tc_ptx.bend -o /tmp/tcptx && /tmp/tcptx > /tmp/bd_n.txt
#   diff /tmp/bd_i.txt .agents/slop/tcptx/pyall.txt && diff /tmp/bd_n.txt .agents/slop/tcptx/pyall.txt
# `stage1` and `stage2` print the halves, 286 and 334 rows, for a localised
# diff when a row moves.
#
# THE MUTATION TABLE is at the foot of the file, measured with
# `.agents/slop/tcptx-mutate.py`.
#
# ---------------------------------------------------------------------------
# THE STAGES, and what landed in each
#
#   STAGE 1  DONE, 286 rows. tc.py. `TensorCore`'s five fields as a `Data`
#            record, the coord packing, `axis_coords`, `base_upcast_axes`,
#            `dims`, `threads`, `relabel`, `frag_coords`, `__post_init__`'s
#            four assertions, `mma`, `mfma`, the sixteen tables, `get_cuda`,
#            `get_amd`, `metal`, and the three `pm_validate_wmma_*` matchers'
#            GUARDS (their rewrite BODIES are walls -- `.bitcast` is
#            `TODO(p3) ops.py:<line>` in ops.bend).
#   STAGE 2  DONE, 334 rows. ptx.py's emitters: `render_val`, the twenty-one
#            `asm_for_op` entries, `supports_half` / `doesnt_support_half`,
#            `ptx_matcher`'s rule count, `mem_type`, `modifier`,
#            `render_wmma` and its `dt_map`s, `PTXRenderer`'s ten class
#            constants, `supported_dtypes`, `tensor_cores`, `fmt`, and
#            `render_kernel`'s HEADER.
#   STAGE 3  NOT STARTED. `render`'s naming walk -- the `ssa` counter, the
#            register map, the `.reg` declarations, the `prod` over the local
#            dims -- and the kernel BODY, which is what `render_kernel` takes
#            as its `BODY` line here. Every STAGE 2 row names a wall for a
#            stage 3 thing rather than faking one.
# ---------------------------------------------------------------------------

import Base
import ./../LAWS/spec.bend as S
import ./../uop/ops.bend as O

# ===========================================================================
# THE GATE PRIMITIVES. `r` is wgsl.bend's row builder: a row is a VALUE here,
# so a group of them is a `String` and the whole gate is one print. The `py=`
# half is a LITERAL, which is what makes the diff a diff -- it cannot be the
# same expression as the `got=` half.
# ===========================================================================

def r(+nm: String, +got: String, +want: String) -> String:
  String.concat([nm, " = [", got, "]   py=[", want, "]\n"])

def bs(+x: Bool) -> String: Bool.pick(String, x, "True", "False")

# `","`-joined decimals. The list is WALKED to build the join, so `<>` (a
# prepend) is what keeps the order; `List.append(acc, [x])` would reverse it.
def ushow(+xs: List<&2, U32>) -> String:
  match xs:
    case Nil{}   : ""
    case h <> +t : String.concat([U32.show(h), Bool.pick(String, List.is_empty(&2, U32, t), "", ","), ushow(t)])

def ln(bs: List<&2, U32>) -> U32: U32.from_nat(List.length(&2, U32, bs))

def pow2(n: U32) -> U32: U32.shln(1, U32.to_nat(n))

# `S.Dt.nm` has no reader in spec.bend (four readers exist and `nm` is not one
# of them), so this is the fifth. MERGE POINT: when spec.bend grows `Dt.nm`,
# this becomes a call.
def dt_name(+d: S.Dt) -> String:
  match d:
    case S.Dt{pri, bits, cls, nm}: nm

# ===========================================================================
# COORDS. tc.py spells a coordinate as the two-character string "m0" and reads
# `c[0]` (the axis letter) and `int(c[1:])` (the bit index) off it. A packed
# `U32` is the same pair -- `(bit << 2) | axis`, with n=0, m=1, k=2 -- and it
# turns both reads into a mask and a shift, which is what `frag_coords` does
# once per bit per coordinate. `cd_str` is the only place the spelling comes
# back, and it is a gate row, so the packing is checked against CPython's own
# strings rather than against itself.
#
# AXIS CODES are the one place a literal replaces a letter, so they are named:
# `AX_N`, `AX_M`, `AX_K`. `"nmk"[0]` is n, and tc.py iterates `for d in "nmk"`,
# so the axis ORDER is n, m, k in `axis_coords` and in `cd_keeps`' callers.
# ===========================================================================

def AX_N() -> U32: 0
def AX_M() -> U32: 1
def AX_K() -> U32: 2

def cd(+bit: U32, +ax: U32) -> U32: U32.or(U32.shln(bit, 2n), ax)

def cd_ax(+c: U32) -> U32: U32.and(c, 3)

def cd_bit(+c: U32) -> U32: U32.shrn(c, 2n)

# `f"{d}{i}"` for one axis. The bit index is 0..7 in every table tc.py builds
# (the largest is cdna's K=128 -> k6), so `&7` cannot lose one and the
# `Maybe.default` arm is only here because `String.get` answers a `Maybe`.
def cd_letter(+ax: U32) -> String:
  match ax:
    case 0: "n"
    case 1: "m"
    case _: "k"

def cd_digit(bit: U32) -> String:
  String.from_list([Maybe.default(&2, Char, String.get("0123456789", U32.to_nat(U32.and(bit, 7))), Char.from_u32(48))])

def cd_str(+c: U32) -> String: String.concat([cd_letter(cd_ax(c)), cd_digit(cd_bit(c))])

def cd_join(+cs: List<&2, U32>) -> String:
  match cs:
    case Nil{}   : ""
    case c <> +t : String.concat([cd_str(c), Bool.pick(String, List.is_empty(&2, U32, t), "", ","), cd_join(t)])

# `cd_cnt(cs, ax)` -- `1 + max([int(c[1:]) for c in axis_coords() if c[0]==d],
# default=-1)`, so the count is 0 for an axis nothing uses.
#
# THE `default=-1` IS CARRIED BY `bit + 1`, not by a sentinel. MEASURED: seeding
# `best` with `0xffffffff` (the U32 spelling of Python's `-1`) and taking
# `U32.max(bit, best)` NEVER picks a coordinate, because `0xffffffff` is the
# largest U32 -- so `axis_coords` came back EMPTY and `dims` printed `1,1,1` for
# all sixteen tables. It typechecked, it ran, and every `.len` row stayed green.
# Carrying `bit + 1` makes the empty answer 0 and the count the max, with no
# sentinel and no wrap.
def cd_cnt1(+cs: List<&2, U32>, +ax: U32, +best: U32) -> U32:
  match cs:
    case Nil{}   : best
    case c <> +t : cd_cnt1(t, ax, Bool.pick(U32, U32.is_eq(cd_ax(c), ax), U32.max(U32.add(cd_bit(c), 1), best), best))

def cd_cnt(+cs: List<&2, U32>, ax: U32) -> U32: cd_cnt1(cs, ax, 0)

# `keep the coords on one axis, IN ORDER`. TWO self-calls in one arm, which is
# legal: both take the same `+` list TAIL, so nothing is consumed twice
# (measured, `.agents/slop/probe-tcptx.bend` PROBE 5 -- the failure is a
# non-`+` second argument, not the double self-call).
#
# THE ORDER IS THE WHOLE OF IT. `List.append(a, A, xs, ys)` is `xs ++ ys`, so
# `List.append(cd_keeps(ax, t), [c])` puts `c` LAST and returns every list in
# REVERSE -- the ledger's standing trap. MEASURED here
# (`.agents/slop/probe-cc.bend`): `append(rec(t), [c])` gave `6,1,2` for the
# input `[2,1,6]` in BOTH lanes, and `[c] ++ rec(t)` gave `2,1,6`. It is not a
# Bend bug and not a lazy-argument bug (binding the self-call to a local first
# changes nothing); it is `xs ++ ys` read as `ys ++ xs`.
def cd_keeps(+ax: U32, +cs: List<&2, U32>) -> List<&2, U32>:
  match cs:
    case Nil{}   : Nil{}
    case c <> +t : Bool.pick(List<&2, U32>, U32.is_eq(cd_ax(c), ax), List.append(&2, U32, [c], cd_keeps(ax, t)), cd_keeps(ax, t))

# `list.append(a, -A, xs, ys)` is `xs ++ ys`; three and four is `List.concat`.
def cc2(a: List<&2, U32>, b: List<&2, U32>) -> List<&2, U32>: List.append(&2, U32, a, b)
def cc3(a: List<&2, U32>, b: List<&2, U32>, +c: List<&2, U32>) -> List<&2, U32>: List.concat(&2, U32, [a, b, c])
def cc4(a: List<&2, U32>, b: List<&2, U32>, +c: List<&2, U32>, +d: List<&2, U32>) -> List<&2, U32>: List.concat(&2, U32, [a, b, c, d])

# `list(range(n))` for `n <= 8`.
#
# MEASURED (`.agents/slop/probe-ur.bend`): `List.append(&2, U32, ur(m),
# [f(k)])` is REFUSED with `expected : m / observed : m (consumed more than
# once)`, and so is `U32.from_nat(k)` anywhere in the arm -- the arm may not so
# much as READ the fuel it is descending. The working shape threads the
# element as a `+U32` that GROWS from 0 and CONSES it
# (`List.append(a, A, [i], xs)` is `[i] ++ xs`), so `i` is the value and `m` is
# the fuel. And the direction matters: APPENDING here gives `2,1,0`, because
# the recursion builds the TAIL first. Every fragment table in this file hangs
# off this one def, so both facts are load-bearing.
def ur(k: Nat, +ax: U32, +i: U32) -> List<&2, U32>:
  match k:
    case 0n : Nil{}
    case 1n+m:
      xs = ur(m, ax, U32.add(i, 1))
      List.append(&2, U32, [cd(i, ax)], xs)

def ur0(k: Nat, ax: U32) -> List<&2, U32>: ur(k, ax, 0)

# ===========================================================================
# COORD LITERALS. Every coordinate in every table tc.py writes by hand, so they
# are defs rather than inline `cd(3, 1)` calls: `cd(3, 1)` is `mk(3)`, and a
# reader comparing tc.py's `("m0","m1","m2")` to a row of `mk(0) mk(1) mk(2)`
# has nothing to hold onto.
# ===========================================================================

def mk(b: U32) -> U32: cd(b, AX_M())
def nk(b: U32) -> U32: cd(b, AX_N())
def kkb(b: U32) -> U32: cd(b, AX_K())

def cd1(a: U32) -> List<&2, U32>: [a]
def cd2(a: U32, b: U32) -> List<&2, U32>: [a, b]
def cd3(a: U32, b: U32, +c: U32) -> List<&2, U32>: [a, b, c]
def cd4(a: U32, b: U32, +c: U32, d: U32) -> List<&2, U32>: [a, b, c, d]
def cd5(a: U32, b: U32, +c: U32, d: U32, e: U32) -> List<&2, U32>: [a, b, c, d, e]
def cd6(a: U32, b: U32, +c: U32, d: U32, e: U32, +f: U32) -> List<&2, U32>: [a, b, c, d, e, f]

def m0() -> U32: mk(0)
def m1() -> U32: mk(1)
def m2() -> U32: mk(2)
def m3() -> U32: mk(3)
def m01() -> List<&2, U32>: cd2(mk(0), mk(1))
def m012() -> List<&2, U32>: cd3(mk(0), mk(1), mk(2))
def m0123() -> List<&2, U32>: cd4(mk(0), mk(1), mk(2), mk(3))
def n012() -> List<&2, U32>: cd3(nk(0), nk(1), nk(2))
def n0123() -> List<&2, U32>: cd4(nk(0), nk(1), nk(2), nk(3))

# ===========================================================================
# `TensorCore` -- tc.py:8-11. FIVE FIELDS, SEVEN `U32` LISTS, because a
# fragment is Python's `(lane_bits, element_bits)` pair and Bend has no tuple
# (brief: a `Data` record per pair would cost four more reader defs and read
# worse). The lane list comes first in every constructor because tc.py's
# `f[0] + f[1]` order is load-bearing for `relabel`, `base_upcast_axes` and
# `frag_coords`.
# ===========================================================================

type Tc is Data:
  Tc{di: S.Dt, dou: S.Dt, la: List<&2, U32>, ea: List<&2, U32>, lb: List<&2, U32>, eb: List<&2, U32>, lc: List<&2, U32>, ec: List<&2, U32>}

def Tc.di(+t: Tc) -> S.Dt:
  match t:
    case Tc{di, dou, la, ea, lb, eb, lc, ec}: di

def Tc.dou(+t: Tc) -> S.Dt:
  match t:
    case Tc{di, dou, la, ea, lb, eb, lc, ec}: dou

def Tc.la(+t: Tc) -> List<&2, U32>:
  match t:
    case Tc{di, dou, la, ea, lb, eb, lc, ec}: la

def Tc.ea(+t: Tc) -> List<&2, U32>:
  match t:
    case Tc{di, dou, la, ea, lb, eb, lc, ec}: ea

def Tc.lb(+t: Tc) -> List<&2, U32>:
  match t:
    case Tc{di, dou, la, ea, lb, eb, lc, ec}: lb

def Tc.eb(+t: Tc) -> List<&2, U32>:
  match t:
    case Tc{di, dou, la, ea, lb, eb, lc, ec}: eb

def Tc.lc(+t: Tc) -> List<&2, U32>:
  match t:
    case Tc{di, dou, la, ea, lb, eb, lc, ec}: lc

def Tc.ec(+t: Tc) -> List<&2, U32>:
  match t:
    case Tc{di, dou, la, ea, lb, eb, lc, ec}: ec

# the two operands' lane+element concatenations, as `f[0] + f[1]` reads them
def Tc.alla(+t: Tc) -> List<&2, U32>: cc2(Tc.la(t), Tc.ea(t))
def Tc.allb(+t: Tc) -> List<&2, U32>: cc2(Tc.lb(t), Tc.eb(t))
def Tc.allc(+t: Tc) -> List<&2, U32>: cc2(Tc.lc(t), Tc.ec(t))

# `f[1] + f[0]` -- ELEMENT bits then LANE bits. `__post_init__`'s A/B k check
# reads this order, and `relabel` reads `f[0] + f[1]`, so the two concatenations
# are both spelled and neither is derived from the other.
def Tc.ealla(+t: Tc) -> List<&2, U32>: cc2(Tc.ea(t), Tc.la(t))
def Tc.eallb(+t: Tc) -> List<&2, U32>: cc2(Tc.eb(t), Tc.lb(t))

# ===========================================================================
# :12 `axis_coords` -- "tile bit of each tc axis in creation order, n then m
# then the k unrolls. split j of a dim is bit j".
#
#     used = self.frag_a[0] + self.frag_a[1] + self.frag_c[0] + self.frag_c[1]
#     return [f"{d}{i}" for d in "nmk" for i in range(1+max([int(c[1:]) for c in used if c[0] == d], default=-1))]
#
# `used` is A's lane, A's element, C's lane, C's element -- B is NOT in it,
# because `k` never is a foreign bit and the post-init assertion checks it.
# ===========================================================================

def Tc.used(+t: Tc) -> List<&2, U32>: cc4(Tc.la(t), Tc.ea(t), Tc.lc(t), Tc.ec(t))

def Tc.axis_coords(+t: Tc) -> List<&2, U32>:
  +u = Tc.used(t)
  cc3(ur0(U32.to_nat(cd_cnt(u, AX_N())), AX_N()), ur0(U32.to_nat(cd_cnt(u, AX_M())), AX_M()), ur0(U32.to_nat(cd_cnt(u, AX_K())), AX_K()))

# ===========================================================================
# :33 `base_upcast_axes` -- "element slots, most significant bit first: upcast
# then reduce": `(tuple(c for c in self.axis_coords() if c[0] == "k") +
# self.frag_c[1])[::-1]`. The REVERSE is load-bearing (relabel's `[::-1]` on a
# prefix of this list is what makes a fragment's k unroll read the same way in
# A and B) so it is written, not implied.
# ===========================================================================

def Tc.bu(+t: Tc) -> List<&2, U32>:
  List.reverse(&2, U32, cc2(cd_keeps(AX_K(), Tc.axis_coords(t)), Tc.ec(t)))

# ===========================================================================
# :29 `dims` -- `n, m, k = (sum(c[0]==d for c in axis_coords) for d in "nmk")`
# then `(2**n, 2**m, 2**k)`, the tile's N, M, K. Three defs, not one returning
# a triple: Bend has no tuple and no `Data` record may hold a `Maybe`, and a
# three-field record here would need three more reader defs for one call site.
# ===========================================================================

def Tc.dims_n(+t: Tc) -> U32: pow2(cd_cnt(Tc.axis_coords(t), AX_N()))
def Tc.dims_m(+t: Tc) -> U32: pow2(cd_cnt(Tc.axis_coords(t), AX_M()))
def Tc.dims_k(+t: Tc) -> U32: pow2(cd_cnt(Tc.axis_coords(t), AX_K()))

def Tc.dims(+t: Tc) -> String: String.join([U32.show(Tc.dims_n(t)), U32.show(Tc.dims_m(t)), U32.show(Tc.dims_k(t))], ",")

# :32 `threads` -- `2**len(self.frag_c[0])`: "threads that construct the warp".
def Tc.threads(+t: Tc) -> U32: pow2(ln(Tc.lc(t)))

# ===========================================================================
# :16 `relabel` -- "tc axis -> fragment slot axis, per operand":
#
#     return [{c: y for y,c in zip(self.frag_c[0] + self.base_upcast_axes()[:len(f[1])][::-1], f[0]+f[1])} for f in (frag_a, frag_b)]
#
# The KEYS are `f[0]+f[1]` and the dict therefore prints in THAT order, so the
# zip is walked key-first and the values are the same order. `[:len(f[1])]` is a
# PREFIX of `base_upcast_axes`, then reversed -- so `take` then `reverse`, and
# the order matters (relabel of cdna's K=128 is where a reversed prefix would
# show).
# ===========================================================================

type Kv is Data:
  Kv{ks: List<&2, U32>, vs: List<&2, U32>}

def Kv.ks(k: Kv) -> List<&2, U32>:
  match k:
    case Kv{ks, vs}: ks

def Kv.vs(k: Kv) -> List<&2, U32>:
  match k:
    case Kv{ks, vs}: vs

# `frag_c[0] + self.base_upcast_axes()[:len(f[1])][::-1]`
def Kv.of_a(+t: Tc) -> Kv: Kv{Tc.alla(t), cc2(Tc.lc(t), List.reverse(&2, U32, List.take(&2, U32, Tc.bu(t), U32.to_nat(ln(Tc.ea(t))))))}
def Kv.of_b(+t: Tc) -> Kv: Kv{Tc.allb(t), cc2(Tc.lc(t), List.reverse(&2, U32, List.take(&2, U32, Tc.bu(t), U32.to_nat(ln(Tc.eb(t))))))}
def kv_join(xs: List<&2, U32>, ys: List<&2, U32>) -> String:
  match xs ys:
    case Nil{} Nil{}    : ""
    case Nil{} _         : ""
    case _     Nil{}     : ""
    case x <> +xt y <> +yt: String.concat([String.concat([cd_str(x), "=", cd_str(y)]), Bool.pick(String, List.is_empty(&2, U32, xt), "", ","), kv_join(xt, yt)])

def Kv.join(k: Kv) -> String:
  match k:
    case Kv{ks, vs}: kv_join(ks, vs)


def Tc.relabel.a(+t: Tc) -> String: Kv.join(Kv.of_a(t))
def Tc.relabel.b(+t: Tc) -> String: Kv.join(Kv.of_b(t))

# `"{c}={y}"` per pair, in KEY order, comma-joined. `Kv.join` DESTRUCTURES
# and hands the two lists to `kv_join`, because a two-scrutinee `match` cannot
# scrutinise two CALLS (convention 4), and `kv_join` conses and reverses because
# `zip` walks two lists that come out of ONE destructuring and so share a
# binder (the "returning the tail instead of the input" rule).


# ===========================================================================
# :19 `frag_coords` -- `[operand][lane][element] -> tile coordinate`:
#
#   def coord(f, ax, lane, elem):
#     return tuple(sum(((v>>j)&1) << int(c[1:]) for bits,v in zip(f, (lane, elem)) for j,c in enumerate(bits) if c[0] == d) for d in ax)
#
# `enumerate(bits)` RESTARTS at j=0 for the element list -- that is `zip(f,
# (lane, elem))`, two independent enumerations, and NOT one over `f[0]+f[1]`.
# Getting that wrong is invisible in a count and visible in every value, which
# is why the gate rows are digests of the whole string (see the gate note).
#
# THE AXIS ORDER is per operand: "mk" for A, "kn" for B, "mn" for C. So the
# two numbers a cell prints are `ax0` then `ax1` and the caller names them,
# rather than this def returning a fixed-order triple.
# ===========================================================================

# one bit list's contribution to one axis
# one bit list's contribution to one axis. `Bool.pick(A, c, a, b)` answers `a`
# WHEN `c` IS TRUE, so the MATCHING branch is the THIRD argument -- written the
# other way round this reads correctly and swaps the two arms of the sum, which
# is a plausible wrong coordinate rather than a compile error (the ledger's rule
# 9, hit for real here).
def cacc.go(+bs: List<&2, U32>, +v: U32, +j: U32, +d: U32, +acc: U32) -> U32:
  match bs:
    case Nil{}   : acc
    case c <> +t : cacc.go(t, v, U32.add(j, 1), d, Bool.pick(U32, U32.is_eq(cd_ax(c), d),
      U32.add(acc, U32.shln(U32.and(U32.shrn(v, U32.to_nat(j)), 1), U32.to_nat(cd_bit(c)))), acc))

def cacc(+bs: List<&2, U32>, v: U32, +d: U32) -> U32: cacc.go(bs, v, 0, d, 0)

def cacc2(+la: List<&2, U32>, +ea: List<&2, U32>, +lane: U32, +elem: U32, +d: U32) -> U32:
  U32.add(cacc(la, lane, d), cacc(ea, elem, d))

def fc_cell(+la: List<&2, U32>, +ea: List<&2, U32>, +lane: U32, +elem: U32, +ax0: U32, +ax1: U32) -> String:
  String.concat([U32.show(cacc2(la, ea, lane, elem, ax0)), ",", U32.show(cacc2(la, ea, lane, elem, ax1))])

# one lane's elements, in order. `n` GROWS and `k` (the remaining count) is the
# FIRST parameter, so the self-call decreases left to right.
def fc_lane.elems(k: Nat, +n: U32, +lane: U32, +la: List<&2, U32>, +ea: List<&2, U32>, +ax0: U32, +ax1: U32) -> List<&2, String>:
  match k:
    case 0n : Nil{}
    case 1n+m:
      xs = fc_lane.elems(m, U32.add(n, 1), lane, la, ea, ax0, ax1)
      List.append(&2, String, [fc_cell(la, ea, lane, n, ax0, ax1)], xs)

# every lane, each lane comma-joined
def fc_lanes(k: Nat, +n: U32, +elems: Nat, +la: List<&2, U32>, +ea: List<&2, U32>, +ax0: U32, +ax1: U32) -> List<&2, String>:
  match k:
    case 0n : Nil{}
    case 1n+m:
      xs = fc_lanes(m, U32.add(n, 1), elems, la, ea, ax0, ax1)
      List.append(&2, String, [String.join(fc_lane.elems(elems, 0, n, la, ea, ax0, ax1), ",")], xs)

def fc_str(lanes: Nat, elems: Nat, +la: List<&2, U32>, +ea: List<&2, U32>, ax0: U32, ax1: U32) -> String:
  String.join(fc_lanes(lanes, 0, elems, la, ea, ax0, ax1), ",")

# ===========================================================================
# THE FNV-1a DIGEST, because `frag_coords`'s own string is 22 647 characters at
# cdna's K=128 and hard-coding the eight shapes' worth of them would put ~180 KB
# of literals in this file -- past the interpreter's measured 28 988-BYTE PER-FILE
# CLIFF (`bend2-constraints.md`, "The interpreter's per-file byte cliff"). A
# digest is a STRING beside CPython's string, catches every dropped literal that
# a sample would miss, and costs six defs. CPython computes it independently in
# the oracle. The row also carries `len=`, so a truncation is visible rather
# than inferred.
# ===========================================================================

def fnv.go(+s: String, h: U32) -> U32:
  match s:
    case SNil{}     : h
    case SCon{c, t} : fnv.go(t, U32.mul(U32.xor(h, Char.to_u32(c)), 16777619))

def fnv(+s: String) -> U32: fnv.go(s, 2166136261)

def dgst(+s: String) -> String: String.concat(["len=", U32.show(U32.from_nat(String.length(s))), " fnv=", U32.show(fnv(s))])

# ===========================================================================
# :44-88 `__post_init__` -- the four assertions. Python `assert`s; a port has
# no assert form, so each becomes a `Bool` and the gate says which arm is
# which. `coords` here is `axis_coords()`, and `own` is the coords on the
# operand's two axes.
#
#   for f,dims in zip((frag_a, frag_b, frag_c), ("mk","kn","mn")):
#     own = {c for c in coords if c[0] in dims}
#     assert len(f[0]) == len(frag_c[0])
#     assert len(set(f[0]+f[1])) == len(f[0]+f[1]) and set(f[1]) <= own <= set(f[0]+f[1]) <= own | {c for c in coords if c[0] in "mn"}
#
# so FOUR clauses, and the chain is `set(f[1]) <= own`, `own <= set(f[0]+f[1])`
# and `set(f[0]+f[1]) <= own | mn-coords`. The last one is a union so testing
# against `own ++ mn-coords` as a LIST is the same statement.
# ===========================================================================

def mem(+xs: List<&2, U32>, +x: U32) -> Bool:
  match xs:
    case Nil{}   : False{}
    case h <> +t : Bool.or(U32.is_eq(h, x), mem(t, x))

# `set(b) <= set(a)` -- every element of `b` occurs in `a`. THE ARGUMENT ORDER IS
# THE OTHER WAY ROUND from `<=`: `<=` reads `own <= all`, which is `sub(all,
# own)`, and writing `sub(own, all)` inverts the assertion. MEASURED: rdna3's
# `cover.mk` printed `False` with the arguments the intuitive way round, because
# its A fragment carries the FOREIGN bit `n0`, which is in `all` and in the
# mn-coords but NOT in `own(mk)` -- exactly the case the assertion exists for.
def sub(+a: List<&2, U32>, +b: List<&2, U32>) -> Bool:
  match b:
    case Nil{}   : True{}
    case h <> +t : Bool.and(mem(a, h), sub(a, t))

# `len(set(xs)) == len(xs)`
def nodup(+xs: List<&2, U32>) -> Bool:
  match xs:
    case Nil{}   : True{}
    case h <> +t : Bool.and(Bool.not(mem(t, h)), nodup(t))

# `cd_drops` is `cd_keeps` with the test negated: `{c for c in coords if c[0] in
# "mn"}` is "everything that is not k", and writing it as `keeps(k)` would be a
# bug that a gate row over a table with no unused axis cannot see.
def cd_drops(+ax: U32, +cs: List<&2, U32>) -> List<&2, U32>:
  match cs:
    case Nil{}   : Nil{}
    case c <> +t : Bool.pick(List<&2, U32>, U32.is_ne(cd_ax(c), ax), List.append(&2, U32, [c], cd_drops(ax, t)), cd_drops(ax, t))

# `set(f[0]+f[1]) <= own | {c for c in coords if c[0] in "mn"}`
def Tc.own(+t: Tc, ax0: U32, ax1: U32) -> List<&2, U32>:
  +cs = Tc.axis_coords(t)
  cc2(cd_keeps(ax0, cs), cd_keeps(ax1, cs))

def Tc.mn_coords(+t: Tc) -> List<&2, U32>: cd_drops(AX_K(), Tc.axis_coords(t))

# "distinct bits covering <dims>" -- three clauses, and they are reported
# SEPARATELY by the gate so a dropped one is a moved row, not a silent True.
def Tc.distinct(+t: Tc, la: List<&2, U32>, +ea: List<&2, U32>) -> Bool: nodup(cc2(la, ea))
def Tc.cover(+t: Tc, la: List<&2, U32>, +ea: List<&2, U32>, ax0: U32, ax1: U32) -> Bool:
  +all = cc2(la, ea)
  +own = Tc.own(t, ax0, ax1)
  Bool.and(sub(own, ea), Bool.and(sub(all, own), sub(cc2(own, Tc.mn_coords(t)), all)))

# `len(f[0]) == len(frag_c[0])` for all three operands, as a "TTF"-shaped string.
def Tc.lanes(+t: Tc) -> String:
  +lc = ln(Tc.lc(t))
  String.concat([bs(U32.is_eq(ln(Tc.la(t)), lc)), bs(U32.is_eq(ln(Tc.lb(t)), lc)), bs(U32.is_eq(ln(Tc.lc(t)), lc))])

# "A and B must relabel k identically": `[c for c in f[1]+f[0] if c[0]=="k"]`,
# ELEMENT BITS FIRST -- the opposite order from `relabel`'s `f[0]+f[1]`.
def Tc.kab_a(+t: Tc) -> List<&2, U32>: cd_keeps(AX_K(), Tc.ealla(t))
def Tc.kab_b(+t: Tc) -> List<&2, U32>: cd_keeps(AX_K(), Tc.eallb(t))
def eq_cs(+xs: List<&2, U32>, +ys: List<&2, U32>) -> Bool:
  match xs ys:
    case Nil{} Nil{}    : True{}
    case Nil{} _         : False{}
    case _     Nil{}     : False{}
    case x <> xt y <> yt : Bool.and(U32.is_eq(x, y), eq_cs(xt, yt))

def Tc.kab_eq(+t: Tc) -> Bool: eq_cs(Tc.kab_a(t), Tc.kab_b(t))


# ===========================================================================
# :26 `mma` -- NVIDIA `mma.m16n8kK`:
#
#   k, g = [f"k{i}" for i in range(int(math.log2(K)))], int(math.log2(4//di.itemsize))
#   lane, elem = tuple(k[g:g+2]), tuple(k[:g]+k[g+2:])
#   frag_a=(lane+("m0","m1","m2"), elem[:g]+("m3",)+elem[g:]), frag_b=(lane+("n0","n1","n2"), elem),
#   frag_c=(("n1","n2","m0","m1","m2"), ("n0","m3"))
#
# `g` is how many k bits ride in a 32-bit REGISTER (the "2**g k in a 32-bit reg"
# the comment names), so it is `log2(4//itemsize)`: half gives g=1, fp8 gives
# g=0. `elem[:g] + ("m3",) + elem[g:]` is where m3 -- "A row+8" -- is spliced
# in, and it is a SPLICE not an append, which is the whole reason a fragment
# shape is not just a suffix of `k`.
# ===========================================================================

def c_mma_lane() -> List<&2, U32>: cd5(nk(1), nk(2), mk(0), mk(1), mk(2))
def c_mma_elem() -> List<&2, U32>: cd2(nk(0), mk(3))

def mma(+kk: U32, +di: S.Dt, dou: S.Dt) -> Tc:
  +ks = ur0(U32.log2(kk), AX_K())
  +g = U32.log2(U32.div(4, S.Dt.itemsize(di)))
  +lane = List.take(&2, U32, List.drop(&2, U32, ks, g), 2n)
  +elem = cc2(List.take(&2, U32, ks, g), List.drop(&2, U32, ks, Nat.add(g, 2n)))
  Tc{di, dou, cc2(lane, m012()), cc3(List.take(&2, U32, elem, g), cd1(m3()), List.drop(&2, U32, elem, g)),
     cc2(lane, n012()), elem, c_mma_lane(), c_mma_elem()}

# `frag_c` for `mma` is FIXED -- `("n1","n2","m0","m1","m2")` / `("n0","m3")` --
# because the accumulator layout depends on neither K nor the dtype, which is
# why it is two literal defs and not a slice of `elem`.

# ===========================================================================
# :77 `mfma` -- AMD 16x16xK. "A[i,k] is item k%K_L of lane i + 16*(k//K_L),
# K_L = K/4; fp8 K=128 is two K=64 halves, k//64 the high item (7.1.5.1)".
#
#   k, kl = [f"k{i}" ...], int(math.log2(min(K, 64)//4))
#   lane, elem = tuple(k[kl:kl+2]), tuple(k[:kl]+k[kl+2:])
#
# `min(K, 64)` is what makes K=128's k axis k0..k6 with the two SHARED k bits at
# kl=4; a `K` instead of `min(K, 64)` would give kl=5 and a different shape.
# `# NOTE: fp6 and fp4 K=128 keep K_L = 32 and would need their own case` is
# upstream's note about the ones this table does not carry.
# ===========================================================================

def mfma(+kk: U32, di: S.Dt, dou: S.Dt) -> Tc:
  +ks = ur0(U32.log2(kk), AX_K())
  +kl = U32.log2(U32.div(U32.min(kk, 64), 4))
  +lane = List.take(&2, U32, List.drop(&2, U32, ks, kl), 2n)
  +elem = cc2(List.take(&2, U32, ks, kl), List.drop(&2, U32, ks, Nat.add(kl, 2n)))
  Tc{di, dou, cc2(m0123(), lane), elem, cc2(n0123(), lane), elem, cd6(nk(0), nk(1), nk(2), nk(3), mk(2), mk(3)), cd2(mk(0), mk(1))}
# ===========================================================================
# THE TABLES. tc.py:44-141, in Python's order, each a `List<&2, Tc>`. The
# `cuda_*` and `amd_*` tables are `Tc` records so a mutation can be aimed at
# one of them and `List.length` can be read without a call.
#
# `cuda_sm80 = cuda_81616 + cuda_8168_f16 + cuda_8168_tf32` and
# `cuda_sm89 = cuda_sm80 + cuda_81632_f8` are CONCATENATIONS, and the ORDER is
# what the gate pins: a `get_cuda` row and a `cuda_sm89[i]` row both move if a
# concatenation is reversed.
# ===========================================================================

def cuda_81616() -> List<&2, Tc>: [mma(16, S.half(), S.single()), mma(16, S.bfloat16(), S.single()), mma(16, S.half(), S.half())]
def cuda_81632_f8() -> List<&2, Tc>: [mma(32, S.fp8e4m3(), S.single()), mma(32, S.fp8e5m2(), S.single())]
def cuda_8168_f16() -> List<&2, Tc>: [mma(8, S.half(), S.single()), mma(8, S.half(), S.half())]
def cuda_8168_tf32() -> List<&2, Tc>: [mma(8, S.single(), S.single())]
def cuda_sm75() -> List<&2, Tc>: cuda_8168_f16()
def cuda_sm80() -> List<&2, Tc>: List.concat(&2, Tc, [cuda_81616(), cuda_8168_f16(), cuda_8168_tf32()])
def cuda_sm89() -> List<&2, Tc>: List.concat(&2, Tc, [cuda_sm80(), cuda_81632_f8()])

# (16,16,16) rdna3 -- `frag_a=(("m0","m1","m2","m3","n0"), ("k0","k1","k2","k3"))`,
# `frag_b=(("n0","n1","n2","n3","m0"), ("k0","k1","k2","k3"))`,
# `frag_c=(("n0","n1","n2","n3","m0"), ("m1","m2","m3"))` -- a FOREIGN lane bit
# (n0 in A, m0 in B) and every k bit in the element list. Four (di,do) pairs, so
# the fragments are written ONCE and the four records differ only in dtypes.
def rdna3_of(di: S.Dt, dou: S.Dt) -> Tc:
  Tc{di, dou, cd5(m0(), m1(), m2(), m3(), nk(0)), cd4(kkb(0), kkb(1), kkb(2), kkb(3)),
    cd5(nk(0), nk(1), nk(2), nk(3), m0()), cd4(kkb(0), kkb(1), kkb(2), kkb(3)), cd5(nk(0), nk(1), nk(2), nk(3), m0()), cd3(m1(), m2(), m3())}

def amd_rdna3() -> List<&2, Tc>:
  [rdna3_of(S.half(), S.single()), rdna3_of(S.half(), S.half()), rdna3_of(S.bfloat16(), S.single()), rdna3_of(S.int8(), S.int32())]

# (16,16,16) rdna4 -- `frag_a=(("m0","m1","m2","m3","k2"), ("k0","k1","k3"))`:
# k2 is the FOREIGN lane bit and k0,k1,k3 the elements.
def rdna4_of(di: S.Dt, dou: S.Dt) -> Tc:
  Tc{di, dou, cd5(m0(), m1(), m2(), m3(), kkb(2)), cd3(kkb(0), kkb(1), kkb(3)),
    cd5(nk(0), nk(1), nk(2), nk(3), kkb(2)), cd3(kkb(0), kkb(1), kkb(3)), cd5(nk(0), nk(1), nk(2), nk(3), m3()), cd3(m0(), m1(), m2())}

def amd_rdna4() -> List<&2, Tc>:
  [rdna4_of(S.half(), S.single()), rdna4_of(S.half(), S.half()), rdna4_of(S.bfloat16(), S.single()), rdna4_of(S.bfloat16(), S.bfloat16())]

def amd_cdna_161616() -> List<&2, Tc>: [mfma(16, S.half(), S.single()), mfma(16, S.bfloat16(), S.single())]
def amd_cdna_161632() -> List<&2, Tc>: [mfma(32, S.fp8e5m2(), S.single()), mfma(32, S.fp8e4m3(), S.single()), mfma(32, S.half(), S.single()), mfma(32, S.bfloat16(), S.single())]
def amd_cdna_1616128() -> List<&2, Tc>: [mfma(128, S.fp8e5m2(), S.single()), mfma(128, S.fp8e4m3(), S.single())]
def amd_cdna3_161632() -> List<&2, Tc>: [mfma(32, S.fp8e5m2fnuz(), S.single()), mfma(32, S.fp8e4m3fnuz(), S.single())]
def amd_cdna3() -> List<&2, Tc>: List.concat(&2, Tc, [amd_cdna3_161632(), amd_cdna_161616()])
def amd_cdna4() -> List<&2, Tc>: List.concat(&2, Tc, [amd_cdna_1616128(), amd_cdna_161632(), amd_cdna_161616()])

# (8,8,8) metal -- `frag_a=(("k1","m0","m1","k2","m2"), ("k0",))`,
# `frag_b=(("n1","k0","k1","n2","k2"), ("n0",))`,
# `frag_c=(("n1","m0","m1","n2","m2"), ("n0",))` -- A's k bits are LANE bits and
# B's n0 sits in its ELEMENT list, the two inversions of every CUDA table.
def metal_of(di: S.Dt, dou: S.Dt) -> Tc:
  Tc{di, dou, cd5(kkb(1), m0(), m1(), kkb(2), m2()), cd1(kkb(0)),
    cd5(nk(1), kkb(0), kkb(1), nk(2), kkb(2)), cd1(nk(0)), cd5(nk(1), m0(), m1(), nk(2), m2()), cd1(nk(0))}

def metal() -> List<&2, Tc>:
  [metal_of(S.single(), S.single()), metal_of(S.half(), S.single()), metal_of(S.half(), S.half()),
   metal_of(S.bfloat16(), S.single()), metal_of(S.bfloat16(), S.bfloat16())]

# `get_cuda(arch)`: `cuda_sm89 if (ver:=int(arch[3:])) >= 89 else cuda_sm80 if
# ver >= 80 else cuda_sm75 if ver >= 75 else []`.
def get_cuda(+ver: U32) -> List<&2, Tc>:
  Bool.pick(List<&2, Tc>, U32.is_ge(ver, 89), cuda_sm89(),
    Bool.pick(List<&2, Tc>, U32.is_ge(ver, 80), cuda_sm80(),
      Bool.pick(List<&2, Tc>, U32.is_ge(ver, 75), cuda_sm75(), Nil{})))

# `get_amd(arch)`: `{"gfx942": amd_cdna3, "gfx950": amd_cdna4, "gfx1200":
# amd_rdna4, "gfx1201": amd_rdna4}.get(arch, amd_rdna3)` (tc.py:98) -- the DEFAULT
# is `amd_rdna3`, NOT `amd_cdna3`, and that is the arm every unlisted arch name
# takes. `get_amd gfx1100` is the row that pins it; `gfx942` would not, because
# it is one of the four keys.
def get_amd(nm: String) -> List<&2, Tc>:
  match nm:
    case "gfx942" : amd_cdna3()
    case "gfx950" : amd_cdna4()
    case "gfx1200": amd_rdna4()
    case "gfx1201": amd_rdna4()
    case _:        amd_rdna3()

# ===========================================================================
# THE STAGE 1 GATE. 267 rows, every one a STRING beside CPython's own string.
#
#   * 16 tables x (a length row + one row per MEMBER).  The member row is
#     `di->do/N,M,K`, so it pins the table's CONTENTS AND ITS ORDER -- a
#     reversed concatenation moves the rows.
#   * 8 distinct FRAGMENT SHAPES x 24 rows: the five dtype/fragment fields,
#     `axis_coords`, `base_upcast_axes`, `threads`, `dims`, both `relabel`
#     dicts, all three `frag_coords` (as a digest -- see the note by `dgst`),
#     `__post_init__`'s lane count, its `distinct`/`cover` pair PER OPERAND, and
#     the `ka == kb` A/B-k-agreement check.
#   * 6 `get_cuda` arches and 5 `get_amd` arch names, including the two that
#     take `get_amd`'s DEFAULT arm.
#
# THE REPRESENTATIVES are named here rather than picked by index so that a
# mutation of one table moves only that table's rows, and a mutation of
# `mma`/`mfma`/`rdna3_of`/`rdna4_of`/`metal_of` moves BOTH (the shape and the
# table), which is the localisation the mutation table records.
# ===========================================================================

def r1(+nm: String, +f: String, +got: String, +want: String) -> String: r(nm ++ "." ++ f, got, want)

# `f"tc/{dims}/{dtype_in.name},{dtype_out.name}"` -- the row PREFIX, built by
# the port so a wrong dims or a swapped dtype pair renames its own rows.
def tc_nm(+t: Tc) -> String:
  String.concat(["tc/", Tc.dims(t), "/", dt_name(Tc.di(t)), ",", dt_name(Tc.dou(t))])

# `f"{dtype_in.name}->{dtype_out.name}/{dims}"` -- a table member.
def tc_pair(+t: Tc) -> String: String.concat([dt_name(Tc.di(t)), "->", dt_name(Tc.dou(t)), "/", Tc.dims(t)])

def tln(ts: List<&2, Tc>) -> String: U32.show(U32.from_nat(List.length(&2, Tc, ts)))

# `,".join(dtype_in->dtype_out for t in table)" -- `get_cuda`/`get_amd`.
def tc_pairs(+ts: List<&2, Tc>) -> String:
  match ts:
    case Nil{}   : ""
    case h <> +t : String.concat([dt_name(Tc.di(h)), "->", dt_name(Tc.dou(h)), Bool.pick(String, List.is_empty(&2, Tc, t), "", ","), tc_pairs(t)])

# ONE def for every table's member rows: the py literal is a LIST parameter and
# the walk is a two-scrutinee match, because a row's `py=` half must be its own
# literal and there are 67 of them.
def r_tcs(+ts: List<&2, Tc>, +ps: List<&2, String>, +i: U32, +nm: String) -> String:
  match ts ps:
    case Nil{} _     : ""
    case _     Nil{} : ""
    case h <> +t p <> +pt :
      rest = r_tcs(t, pt, U32.add(i, 1), nm)
      String.concat([r("tc." ++ nm ++ "[" ++ U32.show(i) ++ "]", tc_pair(h), p), rest])
def cuda_81616_rows() -> String: r_tcs(cuda_81616(), ["half->float/8,16,16", "__bf16->float/8,16,16", "half->half/8,16,16"], 0, "cuda_81616")



def r_tbl_cuda_81616() -> String: String.concat([r("tc.cuda_81616.len", tln(cuda_81616()), "3"), cuda_81616_rows()])
def cuda_81632_f8_rows() -> String: r_tcs(cuda_81632_f8(), ["float8_e4m3->float/8,16,32", "float8_e5m2->float/8,16,32"], 0, "cuda_81632_f8")
def cuda_8168_f16_rows() -> String: r_tcs(cuda_8168_f16(), ["half->float/8,16,8", "half->half/8,16,8"], 0, "cuda_8168_f16")
def cuda_8168_tf32_rows() -> String: r_tcs(cuda_8168_tf32(), ["float->float/8,16,8"], 0, "cuda_8168_tf32")
def cuda_sm75_rows() -> String: r_tcs(cuda_sm75(), ["half->float/8,16,8", "half->half/8,16,8"], 0, "cuda_sm75")
def cuda_sm80_rows() -> String: r_tcs(cuda_sm80(), ["half->float/8,16,16", "__bf16->float/8,16,16", "half->half/8,16,16", "half->float/8,16,8", "half->half/8,16,8", "float->float/8,16,8"], 0, "cuda_sm80")
def cuda_sm89_rows() -> String: r_tcs(cuda_sm89(), ["half->float/8,16,16", "__bf16->float/8,16,16", "half->half/8,16,16", "half->float/8,16,8", "half->half/8,16,8", "float->float/8,16,8", "float8_e4m3->float/8,16,32", "float8_e5m2->float/8,16,32"], 0, "cuda_sm89")
def amd_rdna3_rows() -> String: r_tcs(amd_rdna3(), ["half->float/16,16,16", "half->half/16,16,16", "__bf16->float/16,16,16", "signed char->int/16,16,16"], 0, "amd_rdna3")
def amd_rdna4_rows() -> String: r_tcs(amd_rdna4(), ["half->float/16,16,16", "half->half/16,16,16", "__bf16->float/16,16,16", "__bf16->__bf16/16,16,16"], 0, "amd_rdna4")
def amd_cdna_161616_rows() -> String: r_tcs(amd_cdna_161616(), ["half->float/16,16,16", "__bf16->float/16,16,16"], 0, "amd_cdna_161616")
def amd_cdna_161632_rows() -> String: r_tcs(amd_cdna_161632(), ["float8_e5m2->float/16,16,32", "float8_e4m3->float/16,16,32", "half->float/16,16,32", "__bf16->float/16,16,32"], 0, "amd_cdna_161632")
def amd_cdna_1616128_rows() -> String: r_tcs(amd_cdna_1616128(), ["float8_e5m2->float/16,16,128", "float8_e4m3->float/16,16,128"], 0, "amd_cdna_1616128")
def amd_cdna3_161632_rows() -> String: r_tcs(amd_cdna3_161632(), ["float8_e5m2fnuz->float/16,16,32", "float8_e4m3fnuz->float/16,16,32"], 0, "amd_cdna3_161632")
def amd_cdna3_rows() -> String: r_tcs(amd_cdna3(), ["float8_e5m2fnuz->float/16,16,32", "float8_e4m3fnuz->float/16,16,32", "half->float/16,16,16", "__bf16->float/16,16,16"], 0, "amd_cdna3")
def amd_cdna4_rows() -> String: r_tcs(amd_cdna4(), ["float8_e5m2->float/16,16,128", "float8_e4m3->float/16,16,128", "float8_e5m2->float/16,16,32", "float8_e4m3->float/16,16,32", "half->float/16,16,32", "__bf16->float/16,16,32", "half->float/16,16,16", "__bf16->float/16,16,16"], 0, "amd_cdna4")
def metal_rows() -> String: r_tcs(metal(), ["float->float/8,8,8", "half->float/8,8,8", "half->half/8,8,8", "__bf16->float/8,8,8", "__bf16->__bf16/8,8,8"], 0, "metal")
def r_tbl_cuda_81632_f8() -> String: String.concat([r("tc.cuda_81632_f8.len", tln(cuda_81632_f8()), "2"), cuda_81632_f8_rows()])
def r_tbl_cuda_8168_f16() -> String: String.concat([r("tc.cuda_8168_f16.len", tln(cuda_8168_f16()), "2"), cuda_8168_f16_rows()])
def r_tbl_cuda_8168_tf32() -> String: String.concat([r("tc.cuda_8168_tf32.len", tln(cuda_8168_tf32()), "1"), cuda_8168_tf32_rows()])
def r_tbl_cuda_sm75() -> String: String.concat([r("tc.cuda_sm75.len", tln(cuda_sm75()), "2"), cuda_sm75_rows()])
def r_tbl_cuda_sm80() -> String: String.concat([r("tc.cuda_sm80.len", tln(cuda_sm80()), "6"), cuda_sm80_rows()])
def r_tbl_cuda_sm89() -> String: String.concat([r("tc.cuda_sm89.len", tln(cuda_sm89()), "8"), cuda_sm89_rows()])
def r_tbl_amd_rdna3() -> String: String.concat([r("tc.amd_rdna3.len", tln(amd_rdna3()), "4"), amd_rdna3_rows()])
def r_tbl_amd_rdna4() -> String: String.concat([r("tc.amd_rdna4.len", tln(amd_rdna4()), "4"), amd_rdna4_rows()])
def r_tbl_amd_cdna_161616() -> String: String.concat([r("tc.amd_cdna_161616.len", tln(amd_cdna_161616()), "2"), amd_cdna_161616_rows()])
def r_tbl_amd_cdna_161632() -> String: String.concat([r("tc.amd_cdna_161632.len", tln(amd_cdna_161632()), "4"), amd_cdna_161632_rows()])
def r_tbl_amd_cdna_1616128() -> String: String.concat([r("tc.amd_cdna_1616128.len", tln(amd_cdna_1616128()), "2"), amd_cdna_1616128_rows()])
def r_tbl_amd_cdna3_161632() -> String: String.concat([r("tc.amd_cdna3_161632.len", tln(amd_cdna3_161632()), "2"), amd_cdna3_161632_rows()])
def r_tbl_amd_cdna3() -> String: String.concat([r("tc.amd_cdna3.len", tln(amd_cdna3()), "4"), amd_cdna3_rows()])
def r_tbl_amd_cdna4() -> String: String.concat([r("tc.amd_cdna4.len", tln(amd_cdna4()), "8"), amd_cdna4_rows()])
def r_tbl_metal() -> String: String.concat([r("tc.metal.len", tln(metal()), "5"), metal_rows()])




# `frag_coords`' AXIS ORDER is per operand -- 'mk', 'kn', 'mn' -- and the
# `oi` selector is a parameter, not a computed value (convention 4).
def fc_a(+t: Tc) -> String: fc_str(U32.to_nat(pow2(ln(Tc.la(t)))), U32.to_nat(pow2(ln(Tc.ea(t)))), Tc.la(t), Tc.ea(t), AX_M(), AX_K())
def fc_c(+t: Tc) -> String: fc_str(U32.to_nat(pow2(ln(Tc.lc(t)))), U32.to_nat(pow2(ln(Tc.ec(t)))), Tc.lc(t), Tc.ec(t), AX_M(), AX_N())
def fc_b(+t: Tc) -> String: fc_str(U32.to_nat(pow2(ln(Tc.lb(t)))), U32.to_nat(pow2(ln(Tc.eb(t)))), Tc.lb(t), Tc.eb(t), AX_K(), AX_N())



def fc_of.of(oi: U32, +t: Tc) -> String:
  match oi:
    case 0: fc_a(t)
    case 1: fc_b(t)
    case _: fc_c(t)


def r_tcd0(+t: Tc) -> String:
  +nm = tc_nm(t)
  String.concat([
    r1(nm, "di", dt_name(Tc.di(t)), "half"),
    r1(nm, "do", dt_name(Tc.dou(t)), "float"),
    r1(nm, "frag_a", cd_join(Tc.alla(t)), "k1,k2,m0,m1,m2,k0,m3,k3"),
    r1(nm, "frag_b", cd_join(Tc.allb(t)), "k1,k2,n0,n1,n2,k0,k3"),
    r1(nm, "frag_c", cd_join(Tc.allc(t)), "n1,n2,m0,m1,m2,n0,m3"),
    r1(nm, "axis_coords", cd_join(Tc.axis_coords(t)), "n0,n1,n2,m0,m1,m2,m3,k0,k1,k2,k3"),
    # `axis_coords`'s INTERMEDIATE on its own row. It is UNOBSERVABLE through
    # `axis_coords`: `__post_init__` asserts A covers every m and k coord and C
    # covers every n coord, and `axis_coords` reads a MAX per axis -- so
    # `used = A + C` and `used = A + B` give the same three maxima for EVERY
    # valid TensorCore, and swapping C for B in `Tc.used` moves no other row in
    # this file. The concatenation's own STRING is what differs, so it is a row.
    r1(nm, "used", cd_join(Tc.used(t)), "k1,k2,m0,m1,m2,k0,m3,k3,n1,n2,m0,m1,m2,n0,m3"),
    r1(nm, "base_upcast_axes", cd_join(Tc.bu(t)), "m3,n0,k3,k2,k1,k0"),
    r1(nm, "threads", U32.show(Tc.threads(t)), "32"),
    r1(nm, "dims", Tc.dims(t), "8,16,16"),
    r1(nm, "relabel.0", Tc.relabel.a(t), "k1=n1,k2=n2,m0=m0,m1=m1,m2=m2,k0=k3,m3=n0,k3=m3"),
    r1(nm, "relabel.1", Tc.relabel.b(t), "k1=n1,k2=n2,n0=m0,n1=m1,n2=m2,k0=n0,k3=m3"),
    r1(nm, "frag_coords.0", dgst(fc_of.of(0, t)), "len=1215 fnv=3939875115"),
    r1(nm, "frag_coords.1", dgst(fc_of.of(1, t)), "len=559 fnv=2736630555"),
    r1(nm, "frag_coords.2", dgst(fc_of.of(2, t)), "len=559 fnv=3208275915"),
    r1(nm, "lanes", Tc.lanes(t), "TrueTrueTrue"),
    r1(nm, "distinct.mk", bs(Tc.distinct(t, Tc.la(t), Tc.ea(t))), "True"),
    r1(nm, "cover.mk", bs(Tc.cover(t, Tc.la(t), Tc.ea(t), 1, 2)), "True"),
    r1(nm, "distinct.kn", bs(Tc.distinct(t, Tc.lb(t), Tc.eb(t))), "True"),
    r1(nm, "cover.kn", bs(Tc.cover(t, Tc.lb(t), Tc.eb(t), 2, 0)), "True"),
    r1(nm, "distinct.mn", bs(Tc.distinct(t, Tc.lc(t), Tc.ec(t))), "True"),
    r1(nm, "cover.mn", bs(Tc.cover(t, Tc.lc(t), Tc.ec(t), 1, 0)), "True"),
    r1(nm, "ka", cd_join(Tc.kab_a(t)), "k0,k3,k1,k2"),
    r1(nm, "kb", cd_join(Tc.kab_b(t)), "k0,k3,k1,k2"),
    r1(nm, "kab_eq", bs(Tc.kab_eq(t)), "True"),
  ])

def ts0() -> Tc: mma(16, S.half(), S.single())

def r_tcd1(+t: Tc) -> String:
  +nm = tc_nm(t)
  String.concat([
    r1(nm, "di", dt_name(Tc.di(t)), "float8_e4m3"),
    r1(nm, "do", dt_name(Tc.dou(t)), "float"),
    r1(nm, "frag_a", cd_join(Tc.alla(t)), "k2,k3,m0,m1,m2,k0,k1,m3,k4"),
    r1(nm, "frag_b", cd_join(Tc.allb(t)), "k2,k3,n0,n1,n2,k0,k1,k4"),
    r1(nm, "frag_c", cd_join(Tc.allc(t)), "n1,n2,m0,m1,m2,n0,m3"),
    r1(nm, "axis_coords", cd_join(Tc.axis_coords(t)), "n0,n1,n2,m0,m1,m2,m3,k0,k1,k2,k3,k4"),
    r1(nm, "used", cd_join(Tc.used(t)), "k2,k3,m0,m1,m2,k0,k1,m3,k4,n1,n2,m0,m1,m2,n0,m3"),
    r1(nm, "base_upcast_axes", cd_join(Tc.bu(t)), "m3,n0,k4,k3,k2,k1,k0"),
    r1(nm, "threads", U32.show(Tc.threads(t)), "32"),
    r1(nm, "dims", Tc.dims(t), "8,16,32"),
    r1(nm, "relabel.0", Tc.relabel.a(t), "k2=n1,k3=n2,m0=m0,m1=m1,m2=m2,k0=k3,k1=k4,m3=n0,k4=m3"),
    r1(nm, "relabel.1", Tc.relabel.b(t), "k2=n1,k3=n2,n0=m0,n1=m1,n2=m2,k0=k4,k1=n0,k4=m3"),
    r1(nm, "frag_coords.0", dgst(fc_of.of(0, t)), "len=2591 fnv=3274290231"),
    r1(nm, "frag_coords.1", dgst(fc_of.of(1, t)), "len=1199 fnv=1735828139"),
    r1(nm, "frag_coords.2", dgst(fc_of.of(2, t)), "len=559 fnv=3208275915"),
    r1(nm, "lanes", Tc.lanes(t), "TrueTrueTrue"),
    r1(nm, "distinct.mk", bs(Tc.distinct(t, Tc.la(t), Tc.ea(t))), "True"),
    r1(nm, "cover.mk", bs(Tc.cover(t, Tc.la(t), Tc.ea(t), 1, 2)), "True"),
    r1(nm, "distinct.kn", bs(Tc.distinct(t, Tc.lb(t), Tc.eb(t))), "True"),
    r1(nm, "cover.kn", bs(Tc.cover(t, Tc.lb(t), Tc.eb(t), 2, 0)), "True"),
    r1(nm, "distinct.mn", bs(Tc.distinct(t, Tc.lc(t), Tc.ec(t))), "True"),
    r1(nm, "cover.mn", bs(Tc.cover(t, Tc.lc(t), Tc.ec(t), 1, 0)), "True"),
    r1(nm, "ka", cd_join(Tc.kab_a(t)), "k0,k1,k4,k2,k3"),
    r1(nm, "kb", cd_join(Tc.kab_b(t)), "k0,k1,k4,k2,k3"),
    r1(nm, "kab_eq", bs(Tc.kab_eq(t)), "True"),
  ])

def ts1() -> Tc: mma(32, S.fp8e4m3(), S.single())

def r_tcd2(+t: Tc) -> String:
  +nm = tc_nm(t)
  String.concat([
    r1(nm, "di", dt_name(Tc.di(t)), "half"),
    r1(nm, "do", dt_name(Tc.dou(t)), "float"),
    r1(nm, "frag_a", cd_join(Tc.alla(t)), "k1,k2,m0,m1,m2,k0,m3"),
    r1(nm, "frag_b", cd_join(Tc.allb(t)), "k1,k2,n0,n1,n2,k0"),
    r1(nm, "frag_c", cd_join(Tc.allc(t)), "n1,n2,m0,m1,m2,n0,m3"),
    r1(nm, "axis_coords", cd_join(Tc.axis_coords(t)), "n0,n1,n2,m0,m1,m2,m3,k0,k1,k2"),
    r1(nm, "used", cd_join(Tc.used(t)), "k1,k2,m0,m1,m2,k0,m3,n1,n2,m0,m1,m2,n0,m3"),
    r1(nm, "base_upcast_axes", cd_join(Tc.bu(t)), "m3,n0,k2,k1,k0"),
    r1(nm, "threads", U32.show(Tc.threads(t)), "32"),
    r1(nm, "dims", Tc.dims(t), "8,16,8"),
    r1(nm, "relabel.0", Tc.relabel.a(t), "k1=n1,k2=n2,m0=m0,m1=m1,m2=m2,k0=n0,m3=m3"),
    r1(nm, "relabel.1", Tc.relabel.b(t), "k1=n1,k2=n2,n0=m0,n1=m1,n2=m2,k0=m3"),
    r1(nm, "frag_coords.0", dgst(fc_of.of(0, t)), "len=559 fnv=3208275915"),
    r1(nm, "frag_coords.1", dgst(fc_of.of(1, t)), "len=255 fnv=4242223531"),
    r1(nm, "frag_coords.2", dgst(fc_of.of(2, t)), "len=559 fnv=3208275915"),
    r1(nm, "lanes", Tc.lanes(t), "TrueTrueTrue"),
    r1(nm, "distinct.mk", bs(Tc.distinct(t, Tc.la(t), Tc.ea(t))), "True"),
    r1(nm, "cover.mk", bs(Tc.cover(t, Tc.la(t), Tc.ea(t), 1, 2)), "True"),
    r1(nm, "distinct.kn", bs(Tc.distinct(t, Tc.lb(t), Tc.eb(t))), "True"),
    r1(nm, "cover.kn", bs(Tc.cover(t, Tc.lb(t), Tc.eb(t), 2, 0)), "True"),
    r1(nm, "distinct.mn", bs(Tc.distinct(t, Tc.lc(t), Tc.ec(t))), "True"),
    r1(nm, "cover.mn", bs(Tc.cover(t, Tc.lc(t), Tc.ec(t), 1, 0)), "True"),
    r1(nm, "ka", cd_join(Tc.kab_a(t)), "k0,k1,k2"),
    r1(nm, "kb", cd_join(Tc.kab_b(t)), "k0,k1,k2"),
    r1(nm, "kab_eq", bs(Tc.kab_eq(t)), "True"),
  ])

def ts2() -> Tc: mma(8, S.half(), S.single())

def r_tcd3(+t: Tc) -> String:
  +nm = tc_nm(t)
  String.concat([
    r1(nm, "di", dt_name(Tc.di(t)), "float"),
    r1(nm, "do", dt_name(Tc.dou(t)), "float"),
    r1(nm, "frag_a", cd_join(Tc.alla(t)), "k0,k1,m0,m1,m2,m3,k2"),
    r1(nm, "frag_b", cd_join(Tc.allb(t)), "k0,k1,n0,n1,n2,k2"),
    r1(nm, "frag_c", cd_join(Tc.allc(t)), "n1,n2,m0,m1,m2,n0,m3"),
    r1(nm, "axis_coords", cd_join(Tc.axis_coords(t)), "n0,n1,n2,m0,m1,m2,m3,k0,k1,k2"),
    r1(nm, "used", cd_join(Tc.used(t)), "k0,k1,m0,m1,m2,m3,k2,n1,n2,m0,m1,m2,n0,m3"),
    r1(nm, "base_upcast_axes", cd_join(Tc.bu(t)), "m3,n0,k2,k1,k0"),
    r1(nm, "threads", U32.show(Tc.threads(t)), "32"),
    r1(nm, "dims", Tc.dims(t), "8,16,8"),
    r1(nm, "relabel.0", Tc.relabel.a(t), "k0=n1,k1=n2,m0=m0,m1=m1,m2=m2,m3=n0,k2=m3"),
    r1(nm, "relabel.1", Tc.relabel.b(t), "k0=n1,k1=n2,n0=m0,n1=m1,n2=m2,k2=m3"),
    r1(nm, "frag_coords.0", dgst(fc_of.of(0, t)), "len=559 fnv=2483337883"),
    r1(nm, "frag_coords.1", dgst(fc_of.of(1, t)), "len=255 fnv=2880975211"),
    r1(nm, "frag_coords.2", dgst(fc_of.of(2, t)), "len=559 fnv=3208275915"),
    r1(nm, "lanes", Tc.lanes(t), "TrueTrueTrue"),
    r1(nm, "distinct.mk", bs(Tc.distinct(t, Tc.la(t), Tc.ea(t))), "True"),
    r1(nm, "cover.mk", bs(Tc.cover(t, Tc.la(t), Tc.ea(t), 1, 2)), "True"),
    r1(nm, "distinct.kn", bs(Tc.distinct(t, Tc.lb(t), Tc.eb(t))), "True"),
    r1(nm, "cover.kn", bs(Tc.cover(t, Tc.lb(t), Tc.eb(t), 2, 0)), "True"),
    r1(nm, "distinct.mn", bs(Tc.distinct(t, Tc.lc(t), Tc.ec(t))), "True"),
    r1(nm, "cover.mn", bs(Tc.cover(t, Tc.lc(t), Tc.ec(t), 1, 0)), "True"),
    r1(nm, "ka", cd_join(Tc.kab_a(t)), "k2,k0,k1"),
    r1(nm, "kb", cd_join(Tc.kab_b(t)), "k2,k0,k1"),
    r1(nm, "kab_eq", bs(Tc.kab_eq(t)), "True"),
  ])

def ts3() -> Tc: mma(8, S.single(), S.single())

def r_tcd4(+t: Tc) -> String:
  +nm = tc_nm(t)
  String.concat([
    r1(nm, "di", dt_name(Tc.di(t)), "half"),
    r1(nm, "do", dt_name(Tc.dou(t)), "float"),
    r1(nm, "frag_a", cd_join(Tc.alla(t)), "m0,m1,m2,m3,n0,k0,k1,k2,k3"),
    r1(nm, "frag_b", cd_join(Tc.allb(t)), "n0,n1,n2,n3,m0,k0,k1,k2,k3"),
    r1(nm, "frag_c", cd_join(Tc.allc(t)), "n0,n1,n2,n3,m0,m1,m2,m3"),
    r1(nm, "axis_coords", cd_join(Tc.axis_coords(t)), "n0,n1,n2,n3,m0,m1,m2,m3,k0,k1,k2,k3"),
    r1(nm, "used", cd_join(Tc.used(t)), "m0,m1,m2,m3,n0,k0,k1,k2,k3,n0,n1,n2,n3,m0,m1,m2,m3"),
    r1(nm, "base_upcast_axes", cd_join(Tc.bu(t)), "m3,m2,m1,k3,k2,k1,k0"),
    r1(nm, "threads", U32.show(Tc.threads(t)), "32"),
    r1(nm, "dims", Tc.dims(t), "16,16,16"),
    r1(nm, "relabel.0", Tc.relabel.a(t), "m0=n0,m1=n1,m2=n2,m3=n3,n0=m0,k0=k3,k1=m1,k2=m2,k3=m3"),
    r1(nm, "relabel.1", Tc.relabel.b(t), "n0=n0,n1=n1,n2=n2,n3=n3,m0=m0,k0=k3,k1=m1,k2=m2,k3=m3"),
    r1(nm, "frag_coords.0", dgst(fc_of.of(0, t)), "len=2431 fnv=3155196267"),
    r1(nm, "frag_coords.1", dgst(fc_of.of(1, t)), "len=2431 fnv=3614521043"),
    r1(nm, "frag_coords.2", dgst(fc_of.of(2, t)), "len=1215 fnv=3946414587"),
    r1(nm, "lanes", Tc.lanes(t), "TrueTrueTrue"),
    r1(nm, "distinct.mk", bs(Tc.distinct(t, Tc.la(t), Tc.ea(t))), "True"),
    r1(nm, "cover.mk", bs(Tc.cover(t, Tc.la(t), Tc.ea(t), 1, 2)), "True"),
    r1(nm, "distinct.kn", bs(Tc.distinct(t, Tc.lb(t), Tc.eb(t))), "True"),
    r1(nm, "cover.kn", bs(Tc.cover(t, Tc.lb(t), Tc.eb(t), 2, 0)), "True"),
    r1(nm, "distinct.mn", bs(Tc.distinct(t, Tc.lc(t), Tc.ec(t))), "True"),
    r1(nm, "cover.mn", bs(Tc.cover(t, Tc.lc(t), Tc.ec(t), 1, 0)), "True"),
    r1(nm, "ka", cd_join(Tc.kab_a(t)), "k0,k1,k2,k3"),
    r1(nm, "kb", cd_join(Tc.kab_b(t)), "k0,k1,k2,k3"),
    r1(nm, "kab_eq", bs(Tc.kab_eq(t)), "True"),
  ])

def ts4() -> Tc: rdna3_of(S.half(), S.single())

def r_tcd5(+t: Tc) -> String:
  +nm = tc_nm(t)
  String.concat([
    r1(nm, "di", dt_name(Tc.di(t)), "half"),
    r1(nm, "do", dt_name(Tc.dou(t)), "float"),
    r1(nm, "frag_a", cd_join(Tc.alla(t)), "m0,m1,m2,m3,k2,k0,k1,k3"),
    r1(nm, "frag_b", cd_join(Tc.allb(t)), "n0,n1,n2,n3,k2,k0,k1,k3"),
    r1(nm, "frag_c", cd_join(Tc.allc(t)), "n0,n1,n2,n3,m3,m0,m1,m2"),
    r1(nm, "axis_coords", cd_join(Tc.axis_coords(t)), "n0,n1,n2,n3,m0,m1,m2,m3,k0,k1,k2,k3"),
    r1(nm, "used", cd_join(Tc.used(t)), "m0,m1,m2,m3,k2,k0,k1,k3,n0,n1,n2,n3,m3,m0,m1,m2"),
    r1(nm, "base_upcast_axes", cd_join(Tc.bu(t)), "m2,m1,m0,k3,k2,k1,k0"),
    r1(nm, "threads", U32.show(Tc.threads(t)), "32"),
    r1(nm, "dims", Tc.dims(t), "16,16,16"),
    r1(nm, "relabel.0", Tc.relabel.a(t), "m0=n0,m1=n1,m2=n2,m3=n3,k2=m3,k0=m0,k1=m1,k3=m2"),
    r1(nm, "relabel.1", Tc.relabel.b(t), "n0=n0,n1=n1,n2=n2,n3=n3,k2=m3,k0=m0,k1=m1,k3=m2"),
    r1(nm, "frag_coords.0", dgst(fc_of.of(0, t)), "len=1215 fnv=1686690643"),
    r1(nm, "frag_coords.1", dgst(fc_of.of(1, t)), "len=1215 fnv=3829953183"),
    r1(nm, "frag_coords.2", dgst(fc_of.of(2, t)), "len=1215 fnv=1606384943"),
    r1(nm, "lanes", Tc.lanes(t), "TrueTrueTrue"),
    r1(nm, "distinct.mk", bs(Tc.distinct(t, Tc.la(t), Tc.ea(t))), "True"),
    r1(nm, "cover.mk", bs(Tc.cover(t, Tc.la(t), Tc.ea(t), 1, 2)), "True"),
    r1(nm, "distinct.kn", bs(Tc.distinct(t, Tc.lb(t), Tc.eb(t))), "True"),
    r1(nm, "cover.kn", bs(Tc.cover(t, Tc.lb(t), Tc.eb(t), 2, 0)), "True"),
    r1(nm, "distinct.mn", bs(Tc.distinct(t, Tc.lc(t), Tc.ec(t))), "True"),
    r1(nm, "cover.mn", bs(Tc.cover(t, Tc.lc(t), Tc.ec(t), 1, 0)), "True"),
    r1(nm, "ka", cd_join(Tc.kab_a(t)), "k0,k1,k3,k2"),
    r1(nm, "kb", cd_join(Tc.kab_b(t)), "k0,k1,k3,k2"),
    r1(nm, "kab_eq", bs(Tc.kab_eq(t)), "True"),
  ])

def ts5() -> Tc: rdna4_of(S.half(), S.single())

def r_tcd6(+t: Tc) -> String:
  +nm = tc_nm(t)
  String.concat([
    r1(nm, "di", dt_name(Tc.di(t)), "float8_e5m2"),
    r1(nm, "do", dt_name(Tc.dou(t)), "float"),
    r1(nm, "frag_a", cd_join(Tc.alla(t)), "m0,m1,m2,m3,k4,k5,k0,k1,k2,k3,k6"),
    r1(nm, "frag_b", cd_join(Tc.allb(t)), "n0,n1,n2,n3,k4,k5,k0,k1,k2,k3,k6"),
    r1(nm, "frag_c", cd_join(Tc.allc(t)), "n0,n1,n2,n3,m2,m3,m0,m1"),
    r1(nm, "axis_coords", cd_join(Tc.axis_coords(t)), "n0,n1,n2,n3,m0,m1,m2,m3,k0,k1,k2,k3,k4,k5,k6"),
    r1(nm, "used", cd_join(Tc.used(t)), "m0,m1,m2,m3,k4,k5,k0,k1,k2,k3,k6,n0,n1,n2,n3,m2,m3,m0,m1"),
    r1(nm, "base_upcast_axes", cd_join(Tc.bu(t)), "m1,m0,k6,k5,k4,k3,k2,k1,k0"),
    r1(nm, "threads", U32.show(Tc.threads(t)), "64"),
    r1(nm, "dims", Tc.dims(t), "16,16,128"),
    r1(nm, "relabel.0", Tc.relabel.a(t), "m0=n0,m1=n1,m2=n2,m3=n3,k4=m2,k5=m3,k0=k4,k1=k5,k2=k6,k3=m0,k6=m1"),
    r1(nm, "relabel.1", Tc.relabel.b(t), "n0=n0,n1=n1,n2=n2,n3=n3,k4=m2,k5=m3,k0=k4,k1=k5,k2=k6,k3=m0,k6=m1"),
    r1(nm, "frag_coords.0", dgst(fc_of.of(0, t)), "len=11295 fnv=2304681711"),
    r1(nm, "frag_coords.1", dgst(fc_of.of(1, t)), "len=11295 fnv=4134083867"),
    r1(nm, "frag_coords.2", dgst(fc_of.of(2, t)), "len=1215 fnv=407250415"),
    r1(nm, "lanes", Tc.lanes(t), "TrueTrueTrue"),
    r1(nm, "distinct.mk", bs(Tc.distinct(t, Tc.la(t), Tc.ea(t))), "True"),
    r1(nm, "cover.mk", bs(Tc.cover(t, Tc.la(t), Tc.ea(t), 1, 2)), "True"),
    r1(nm, "distinct.kn", bs(Tc.distinct(t, Tc.lb(t), Tc.eb(t))), "True"),
    r1(nm, "cover.kn", bs(Tc.cover(t, Tc.lb(t), Tc.eb(t), 2, 0)), "True"),
    r1(nm, "distinct.mn", bs(Tc.distinct(t, Tc.lc(t), Tc.ec(t))), "True"),
    r1(nm, "cover.mn", bs(Tc.cover(t, Tc.lc(t), Tc.ec(t), 1, 0)), "True"),
    r1(nm, "ka", cd_join(Tc.kab_a(t)), "k0,k1,k2,k3,k6,k4,k5"),
    r1(nm, "kb", cd_join(Tc.kab_b(t)), "k0,k1,k2,k3,k6,k4,k5"),
    r1(nm, "kab_eq", bs(Tc.kab_eq(t)), "True"),
  ])

def ts6() -> Tc: mfma(128, S.fp8e5m2(), S.single())

def r_tcd7(+t: Tc) -> String:
  +nm = tc_nm(t)
  String.concat([
    r1(nm, "di", dt_name(Tc.di(t)), "float"),
    r1(nm, "do", dt_name(Tc.dou(t)), "float"),
    r1(nm, "frag_a", cd_join(Tc.alla(t)), "k1,m0,m1,k2,m2,k0"),
    r1(nm, "frag_b", cd_join(Tc.allb(t)), "n1,k0,k1,n2,k2,n0"),
    r1(nm, "frag_c", cd_join(Tc.allc(t)), "n1,m0,m1,n2,m2,n0"),
    r1(nm, "axis_coords", cd_join(Tc.axis_coords(t)), "n0,n1,n2,m0,m1,m2,k0,k1,k2"),
    r1(nm, "used", cd_join(Tc.used(t)), "k1,m0,m1,k2,m2,k0,n1,m0,m1,n2,m2,n0"),
    r1(nm, "base_upcast_axes", cd_join(Tc.bu(t)), "n0,k2,k1,k0"),
    r1(nm, "threads", U32.show(Tc.threads(t)), "32"),
    r1(nm, "dims", Tc.dims(t), "8,8,8"),
    r1(nm, "relabel.0", Tc.relabel.a(t), "k1=n1,m0=m0,m1=m1,k2=n2,m2=m2,k0=n0"),
    r1(nm, "relabel.1", Tc.relabel.b(t), "n1=n1,k0=m0,k1=m1,n2=n2,k2=m2,n0=n0"),
    r1(nm, "frag_coords.0", dgst(fc_of.of(0, t)), "len=255 fnv=1788109291"),
    r1(nm, "frag_coords.1", dgst(fc_of.of(1, t)), "len=255 fnv=1788109291"),
    r1(nm, "frag_coords.2", dgst(fc_of.of(2, t)), "len=255 fnv=1788109291"),
    r1(nm, "lanes", Tc.lanes(t), "TrueTrueTrue"),
    r1(nm, "distinct.mk", bs(Tc.distinct(t, Tc.la(t), Tc.ea(t))), "True"),
    r1(nm, "cover.mk", bs(Tc.cover(t, Tc.la(t), Tc.ea(t), 1, 2)), "True"),
    r1(nm, "distinct.kn", bs(Tc.distinct(t, Tc.lb(t), Tc.eb(t))), "True"),
    r1(nm, "cover.kn", bs(Tc.cover(t, Tc.lb(t), Tc.eb(t), 2, 0)), "True"),
    r1(nm, "distinct.mn", bs(Tc.distinct(t, Tc.lc(t), Tc.ec(t))), "True"),
    r1(nm, "cover.mn", bs(Tc.cover(t, Tc.lc(t), Tc.ec(t), 1, 0)), "True"),
    r1(nm, "ka", cd_join(Tc.kab_a(t)), "k0,k1,k2"),
    r1(nm, "kb", cd_join(Tc.kab_b(t)), "k0,k1,k2"),
    r1(nm, "kab_eq", bs(Tc.kab_eq(t)), "True"),
  ])

def ts7() -> Tc: metal_of(S.single(), S.single())

def r_tcds() -> String:
  String.concat([r_tcd0(ts0()), r_tcd1(ts1()), r_tcd2(ts2()), r_tcd3(ts3()), r_tcd4(ts4()), r_tcd5(ts5()), r_tcd6(ts6()), r_tcd7(ts7())])

def r_gc_75() -> String: r("get_cuda sm_75", tc_pairs(get_cuda(75)), "half->float,half->half")
def r_gc_80() -> String: r("get_cuda sm_80", tc_pairs(get_cuda(80)), "half->float,__bf16->float,half->half,half->float,half->half,float->float")
def r_gc_86() -> String: r("get_cuda sm_86", tc_pairs(get_cuda(86)), "half->float,__bf16->float,half->half,half->float,half->half,float->float")
def r_gc_89() -> String: r("get_cuda sm_89", tc_pairs(get_cuda(89)), "half->float,__bf16->float,half->half,half->float,half->half,float->float,float8_e4m3->float,float8_e5m2->float")
def r_gc_90() -> String: r("get_cuda sm_90", tc_pairs(get_cuda(90)), "half->float,__bf16->float,half->half,half->float,half->half,float->float,float8_e4m3->float,float8_e5m2->float")
def r_gc_100() -> String: r("get_cuda sm_100", tc_pairs(get_cuda(100)), "half->float,__bf16->float,half->half,half->float,half->half,float->float,float8_e4m3->float,float8_e5m2->float")
def r_ga_gfx942() -> String: r("get_amd gfx942", tc_pairs(get_amd("gfx942")), "float8_e5m2fnuz->float,float8_e4m3fnuz->float,half->float,__bf16->float")
def r_ga_gfx950() -> String: r("get_amd gfx950", tc_pairs(get_amd("gfx950")), "float8_e5m2->float,float8_e4m3->float,float8_e5m2->float,float8_e4m3->float,half->float,__bf16->float,half->float,__bf16->float")
def r_ga_gfx1200() -> String: r("get_amd gfx1200", tc_pairs(get_amd("gfx1200")), "half->float,half->half,__bf16->float,__bf16->__bf16")
def r_ga_gfx1201() -> String: r("get_amd gfx1201", tc_pairs(get_amd("gfx1201")), "half->float,half->half,__bf16->float,__bf16->__bf16")
def r_ga_gfx1100() -> String: r("get_amd gfx1100", tc_pairs(get_amd("gfx1100")), "half->float,half->half,__bf16->float,signed char->int")

def r_stage1() -> String:
  String.concat([r_tbl_cuda_81616(), r_tbl_cuda_81632_f8(), r_tbl_cuda_8168_f16(), r_tbl_cuda_8168_tf32(),
    r_tbl_cuda_sm75(), r_tbl_cuda_sm80(), r_tbl_cuda_sm89(), r_tbl_amd_rdna3(), r_tbl_amd_rdna4(),
    r_tbl_amd_cdna_161616(), r_tbl_amd_cdna_161632(), r_tbl_amd_cdna_1616128(), r_tbl_amd_cdna3_161632(),
    r_tbl_amd_cdna3(), r_tbl_amd_cdna4(), r_tbl_metal(), r_tcds(), r_gc_75(), r_gc_80(), r_gc_86(),
    r_gc_89(), r_gc_90(), r_gc_100(), r_ga_gfx942(), r_ga_gfx950(), r_ga_gfx1200(), r_ga_gfx1201(), r_ga_gfx1100()])

# ===========================================================================
# ptx.py. `PTXRenderer`'s class attributes are the OPTS of a device, so they are
# a `Data` record and `ptx_of(ver)` is the inheritance (convention 1). Python
# MUTATES `self.extra_matcher` in `__init__` when `int(arch[3:]) < 80`
# (ptx.py:147); that mutation is a WALL -- the rules it appends are rewrites --
# and it is named at `ptx_of` rather than faked.
#
# `self.compiler` (ptx.py:145) is `runtime/support/compiler_cuda.py` and is a C
# effect in the port's own boundary table, so `ptx_of` does not carry it:
#   TODO(p3) ptx.py:145  self.compiler -- NVPTXCompiler / PTXCompiler
# ===========================================================================
type Px is Data:
  Px{suffix: String, prefix: String, barrier: String, gmax: List<&2, U32>, lmax: List<&2, U32>, smax: U32, ver: U32}

def Px.suffix(p: Px) -> String:
  match p:
    case Px{suffix, prefix, barrier, gmax, lmax, smax, ver}: suffix

def Px.prefix(p: Px) -> String:
  match p:
    case Px{suffix, prefix, barrier, gmax, lmax, smax, ver}: prefix

def Px.barrier(p: Px) -> String:
  match p:
    case Px{suffix, prefix, barrier, gmax, lmax, smax, ver}: barrier

def Px.gmax(p: Px) -> List<&2, U32>:
  match p:
    case Px{suffix, prefix, barrier, gmax, lmax, smax, ver}: gmax

def Px.lmax(p: Px) -> List<&2, U32>:
  match p:
    case Px{suffix, prefix, barrier, gmax, lmax, smax, ver}: lmax

def Px.smax(p: Px) -> U32:
  match p:
    case Px{suffix, prefix, barrier, gmax, lmax, smax, ver}: smax

def Px.ver(p: Px) -> U32:
  match p:
    case Px{suffix, prefix, barrier, gmax, lmax, smax, ver}: ver

# `CUDARenderer.global_max/local_max/shared_max` -- ptx.py:139 inherits them and
# does not override, so they are constants of the record and the gate says where
# they came from.
def px_gmax() -> List<&2, U32>: [2147483647, 65535, 65535]
def px_lmax() -> List<&2, U32>: [1024, 1024, 64]
def px_smax() -> U32: 49152

# `kernel_prefix` (ptx.py:151-154) and `barrier` (ptx.py:155). The TAB in the
# barrier is spelled `tab()` because a literal TAB inside a string is invisible
# in a diff and `String.concat` would hide it.
def px_p0() -> String: ".version VERSION"
def nl() -> String: String.from_list([Char.from_u32(10)])
def px_p1() -> String: ".target TARGET"
def px_p2() -> String: ".address_size 64"
def px_p3() -> String: ".visible .entry"





def px_prefix() -> String:
  String.concat([px_p0(), nl(), px_p1(), nl(), px_p2(), nl(), px_p3()])


def tab() -> String: String.from_list([Char.from_u32(9)])


def px_barrier() -> String: String.concat(["bar.sync", tab(), "0;"])

# `suffix = "PTX"` -- ptx.py:138.
def px_suffix() -> String: "PTX"

# THE INHERITANCE: one constructor per device. `ver` is `int(arch[3:])`, the
# only per-arch thing `__init__` uses besides `tc.get_cuda`.
def ptx_of(+ver: U32) -> Px: Px{px_suffix(), px_prefix(), px_barrier(), px_gmax(), px_lmax(), px_smax(), ver}

# ===========================================================================
# `types` / `mem_types` / `cast_types` -- ptx.py:156-161.
#
#   types:       int8 s16, int16 s16, int32 s32, int64 s64, uint8 u16,
#               uint16 u16, uint32 u32, uint64 u64, float16 f16, float32 f32,
#               float64 f64, bool pred
#   mem_types:  {**types, int8: s8, uint8: u8, bool: u8, float16: b16}
#   cast_types: {**types, int8: s8, uint8: u8}
#
# The two derived tables are `types` with FOUR and TWO keys replaced, so they are
# `types` with an override and not a second twelve-arm ladder. DISPATCH IS ON
# `pri`, which is a unique key over the twelve keys -- the eight fp8/weak
# priorities are NOT keys and take the KeyError arm (a row of its own). `pri` is
# not unique over ALL of `dtypes` (fp8e4m3 and fp8e4m3fnuz share pri 10), which
# is why dtype EQUALITY anywhere in this file is `O.eq_dt` and never `pri`.
# ===========================================================================
def types_pri(pri: U32) -> String:
  match pri:
    case 0:  "pred"
    case 1:  "s16"
    case 2:  "u16"
    case 3:  "s16"
    case 4:  "u16"
    case 5:  "s32"
    case 6:  "u32"
    case 7:  "s64"
    case 8:  "u64"
    case 12: "f16"
    case 14: "f32"
    case 15: "f64"
    case _:   ""

def types_of(+dt: S.Dt) -> String:
  match dt:
    case S.Dt{pri, bits, cls, nm}: types_pri(pri)

def mem_types_of(+dt: S.Dt) -> String:
  match dt:
    case S.Dt{pri, bits, cls, nm}:
      match pri:
        case 1:  "s8"
        case 2:  "u8"
        case 0:  "u8"
        case 12: "b16"
        case _:   types_pri(pri)

def cast_types_of(+dt: S.Dt) -> String:
  match dt:
    case S.Dt{pri, bits, cls, nm}:
      match pri:
        case 1: "s8"
        case 2: "u8"
        case _:  types_pri(pri)

# ===========================================================================
# `mem_type(x)` -- ptx.py:59: `'shared' if x.addrspace == AddrSpace.LOCAL else
# 'global'`. Two addresses are LOCAL or not, and the `else` is the answer for
# every other AddrSpace, so this is a two-arm match on the addrspace.
# ===========================================================================
def mem_type(addr: S.Addr) -> String:
  match addr:
    case S.ALocal{}: "shared"
    case _:          "global"

# ===========================================================================
# :11 `render_val(x, dtype)` --
#
#   if dtypes.is_float(dtype):
#     if dtype == dtypes.double: return "0d%02X..." % tuple(struct.pack("d",x)[::-1])
#     if dtype == dtypes.half:   return "0x%02X%02X" % tuple(struct.pack("e",x)[::-1])
#     return "0f%02X%02X%02X%02X" % tuple(struct.pack("f",x)[::-1])
#   return str(int(x)) + ("U" if dtypes.is_unsigned(dtype) else "")
#
# `[::-1]` on a LITTLE-ENDIAN `struct.pack` is BIG-ENDIAN hex, so the two/hex four
# are just the float's bits read out most-significant byte first -- and `F32.bits`
# is an intrinsic, so both float arms are arithmetic.
#
#   TODO(p3) ptx.py:13  render_val's DOUBLE arm -- `struct.pack("d", ...)` is 64
#                       bits and U32 is the widest type Bend has. Unreachable
#                       from a float CONST on a PTX target in this gate's fixture
#                       set; named rather than faked.
#   TODO(p3) ptx.py:16  render_val's SIGNED-INTEGER arm -- `str(int(x))` needs a
#                       signed decimal and Bend has no signed type. The
#                       UNSIGNED arm is ported and gated; the signed one is not.
#
# `bits` is the float's BIT PATTERN in the float arms and the integer's VALUE in
# the integer arm -- see the note on the two numeric parameters below.
# ===========================================================================
def hexdig() -> String: "0123456789ABCDEF"

def hex1(+x: U32) -> String:
  String.from_list([Maybe.default(&2, Char, String.get(hexdig(), U32.to_nat(U32.and(x, 15))), Char.from_u32(63))])

# `%02X` FOUR TIMES is `hex4` and EIGHT TIMES is `hex8`: Python's `"0x%02X%02X"`
# is two BYTES (four hex digits) for a half and `"0f%02X%02X%02X%02X"` is four
# bytes (eight digits) for a float. Writing `hex2` as two digits is the same
# off-by-a-nibble mistake as shifting by 12 instead of 28 -- MEASURED: the first
# version printed `0f0000` for 3.5 and `0x54` for 0.3330078125, and every
# `render_val` float row moved with the `.len`-free text.
def hex4(+x: U32) -> String: String.concat([hex1(U32.shrn(x, 12n)), hex1(U32.shrn(x, 8n)), hex1(U32.shrn(x, 4n)), hex1(x)])

def hex8(+x: U32) -> String:
  String.concat([hex1(U32.shrn(x, 28n)), hex1(U32.shrn(x, 24n)), hex1(U32.shrn(x, 20n)), hex1(U32.shrn(x, 16n)),
    hex1(U32.shrn(x, 12n)), hex1(U32.shrn(x, 8n)), hex1(U32.shrn(x, 4n)), hex1(x)])

# `struct.pack("e", x)` -- IEEE binary16 of an F32, rounded TOWARD ZERO, because
# `struct` truncates the mantissa and the gate's four values (0.0, 1.0, -2.5,
# 0.3330078125) are all NORMAL and all exactly representable, so the
# round-to-nearest-even tie never fires.
#
# NAMED, NOT PORTED: the SUBNORMAL range (f32 exponent 0) and the OVERFLOW to
# infinity, which `struct.pack` reaches with a biased shift. Both answer
# `f16.zero` -- sign bit only -- which is WRONG for a real subnormal, so this is
# a truncation of the encoding and not IEEE binary16, and the header says so.
def f16_exp(+b: U32) -> U32: U32.and(U32.shrn(b, 23n), 255)

def f16_man(+b: U32) -> U32: U32.and(b, 8388607)

def f16_sgn(+b: U32) -> U32: U32.shrn(b, 31n)

# the 127 - 15 REBIAS, wrapped: an exponent below 112 gives a huge `e`, which is
# outside 1..=30 and so takes the `f16.zero` arm.
def f16.normal(+b: U32, +e: U32) -> U32:
  U32.or(U32.or(U32.shln(f16_sgn(b), 15n), U32.shln(e, 10n)), U32.shrn(f16_man(b), 13n))
def f16.zero(+b: U32) -> U32: U32.shln(f16_sgn(b), 15n)


def f16bits(x: F32) -> U32:
  +b = F32.bits(x)
  +e = U32.sub(f16_exp(b), 112)
  Bool.pick(U32, Bool.and(U32.is_ge(e, 1), U32.is_le(e, 30)), f16.normal(b, e), f16.zero(b))



# NOTE the two numeric parameters: `x` is the FLOAT and `v` the INTEGER, and
# the two never meet. Carrying ONE U32 instead -- which is what the first version
# of this def did -- is wrong for half, because `struct.pack("e", x)` re-ENCODES
# the value into binary16 rather than truncating the binary32 pattern: 1.0f32 is
# 0x3F800000 and half(1.0f32) is 0x3C00, so the high two bytes are NOT the answer.
def render_val_f(+x: F32, is_half: Bool) -> String:
  Bool.pick(String, is_half, String.concat(["0x", hex4(f16bits(x))]), String.concat(["0f", hex8(F32.bits(x))]))

def render_val_u(+v: U32, is_unsigned: Bool) -> String:
  Bool.pick(String, is_unsigned, String.concat([U32.show(v), "U"]), U32.show(v))

def render_val(is_float: Bool, is_half: Bool, is_unsigned: Bool, +x: F32, +v: U32) -> String:
  Bool.pick(String, is_float, render_val_f(x, is_half), render_val_u(v, is_unsigned))

# `Dtf` -- the three dtype FACTS `asm_for_op` and `string_rewrite` read. A
# `match` may not scrutinise `S.Dt.is_bool(dt)`, so a def that branches on them
# takes the record (convention 4). One record, three fields, three readers, and
# it is the ONLY way a dtype reaches a branch in this file.
type Dtf is Data:
  Dtf{is_bool: Bool, is_int: Bool, is_float: Bool}

def Dtf.is_bool(d: Dtf) -> Bool:
  match d:
    case Dtf{is_bool, is_int, is_float}: is_bool

def Dtf.is_int(d: Dtf) -> Bool:
  match d:
    case Dtf{is_bool, is_int, is_float}: is_int

def Dtf.is_float(d: Dtf) -> Bool:
  match d:
    case Dtf{is_bool, is_int, is_float}: is_float

def Dtf.of(+dt: S.Dt) -> Dtf: Dtf{S.Dt.is_bool(dt), S.Dt.is_int(dt), S.Dt.is_float(dt)}

# ===========================================================================
# `asm_for_op` -- ptx.py:18-36. TWENTY-ONE lambdas keyed by op, so ONE def with a
# `match` on the op (convention 1: no closures in a record, and the brief's rule
# 31 says a table of closures would be unprintable).
#
# It returns `List<&2, String>` because Python's is `str` for twenty of the
# twenty-one and a TWO-ELEMENT LIST for WHERE-on-bool. Collapsing that to one
# string would hide the fact that the bool arm emits two kernel lines, so the
# list is kept and the gate joins with `" ;; "` on both sides.
#
# `name` is `ctx.types[dtype]` -- "s32", "f16", "pred" -- and `name[1:]` is
# `String.drop(name, 1n)`: the `.b32` / `.b16` / `.b64` suffix every bitwise arm
# spells. `SHL` is `shl.b{name[1:]}` and the other bitwise arms are
# `{and,or,xor}.b{name[1:]}`.
# ===========================================================================
def op_asm(op: O.Op, +d: String, +a: String, +b: String, +c: String, +name: String, +f: Dtf) -> List<&2, String>:
  match op:
    case O.OpsRECIPROCAL{}: [String.concat([Bool.pick(String, Dtf.is_float(f), "rcp.approx.", "rcp."), name, " ", d, ", ", a, ";"])]
    case O.OpsEXP2{}      : [String.concat(["ex2.approx.", name, " ", d, ", ", a, ";"])]
    case O.OpsLOG2{}      : [String.concat(["lg2.approx.", name, " ", d, ", ", a, ";"])]
    case O.OpsSIN{}       : [String.concat(["sin.approx.", name, " ", d, ", ", a, ";"])]
    case O.OpsSQRT{}      : [String.concat(["sqrt.approx.", name, " ", d, ", ", a, ";"])]
    case O.OpsTRUNC{}     : [String.concat(["cvt.rzi.", name, ".", name, " ", d, ", ", a, ";"])]
    case O.OpsSHR{}       : [String.concat(["shr.", name, " ", d, ", ", a, ", ", b, ";"])]
    case O.OpsSHL{}       : [String.concat(["shl.b", String.drop(name, 1n), " ", d, ", ", a, ", ", b, ";"])]
    case O.OpsADD{}       : [String.concat([Bool.pick(String, Dtf.is_bool(f), "or.", "add."), name, " ", d, ", ", a, ", ", b, ";"])]
    case O.OpsMUL{}       : [String.concat([Bool.pick(String, Dtf.is_bool(f), "and", "mul"), Bool.pick(String, Dtf.is_int(f), ".lo", ""), ".", name, " ", d, ", ", a, ", ", b, ";"])]
    case O.OpsXOR{}       : Bool.pick(List<&2, String>, Dtf.is_bool(f), [String.concat(["xor.pred ", d, ", ", a, ", ", b, ";"])], [String.concat(["xor.b", String.drop(name, 1n), " ", d, ", ", a, ", ", b, ";"])])
    case O.OpsAND{}       : Bool.pick(List<&2, String>, Dtf.is_bool(f), [String.concat(["and.pred ", d, ", ", a, ", ", b, ";"])], [String.concat(["and.b", String.drop(name, 1n), " ", d, ", ", a, ", ", b, ";"])])
    case O.OpsOR{}        : Bool.pick(List<&2, String>, Dtf.is_bool(f), [String.concat(["or.pred ", d, ", ", a, ", ", b, ";"])], [String.concat(["or.b", String.drop(name, 1n), " ", d, ", ", a, ", ", b, ";"])])
    case O.OpsCDIV{}      : [String.concat(["div.", name, " ", d, ", ", a, ", ", b, ";"])]
    case O.OpsCMOD{}      : [String.concat(["rem.", name, " ", d, ", ", a, ", ", b, ";"])]
    case O.OpsMAX{}       : [String.concat(["max.", name, " ", d, ", ", a, ", ", b, ";"])]
    case O.OpsCMPEQ{}     : [String.concat(["setp.eq.", name, " ", d, ", ", a, ", ", b, ";"])]
    case O.OpsCMPLT{}     : [String.concat(["setp.lt.", name, " ", d, ", ", a, ", ", b, ";"])]
    case O.OpsCMPNE{}     : [String.concat(["setp.", Bool.pick(String, Dtf.is_float(f), "neu", "ne"), ".", name, " ", d, ", ", a, ", ", b, ";"])]
    case O.OpsMULACC{}    : [String.concat([Bool.pick(String, Dtf.is_float(f), "fma.rn.", "mad.lo."), name, " ", d, ", ", a, ", ", b, ", ", c, ";"])]
    case O.OpsWHERE{}     : Bool.pick(List<&2, String>, Dtf.is_bool(f),
      [String.concat(["@", a, " mov.", name, " ", d, ", ", b, ";"]), String.concat(["@!", a, " mov.", name, " ", d, ", ", c, ";"])],
      [String.concat(["selp.", Bool.pick(String, String.eq(name, "f16"), "b16", name), " ", d, ", ", b, ", ", c, ", ", a, ";"])])
    case _: []

# ===========================================================================
# :38-39 `supports_half` / `doesnt_support_half`. The first is a SEVEN-TUPLE
# LITERAL, so its order is the LITERAL's -- EXP2,ADD,MUL,MAX,CMPLT,WHERE,TRUNC --
# and NOT `asm_for_op`'s key order, which would put TRUNC second. The second is
# `tuple(op for op in asm_for_op.keys() if op not in supports_half)`, so it is
# DERIVED from the first and the twenty-one keys, in the dict's own order. The
# seven names therefore live in exactly ONE place, `supports_half`, and the
# membership test reads it -- so a wrong name moves BOTH rows, and a right name
# in the wrong position moves the first.
# ===========================================================================
def supports_half() -> List<&2, O.Op>:
  [O.OpsEXP2{}, O.OpsADD{}, O.OpsMUL{}, O.OpsMAX{}, O.OpsCMPLT{}, O.OpsWHERE{}, O.OpsTRUNC{}]

# `op not in supports_half` -- `O.eq_op` is a def, which `List.contains` wants as
# a function VALUE (a closure is not one).
def in_sh(+o: O.Op) -> Bool: List.contains(~O.Op, O.eq_op, supports_half(), o)

def asm_keys() -> List<&2, O.Op>:
  [O.OpsRECIPROCAL{}, O.OpsEXP2{}, O.OpsLOG2{}, O.OpsSIN{}, O.OpsSQRT{}, O.OpsTRUNC{}, O.OpsSHR{}, O.OpsSHL{},
   O.OpsADD{}, O.OpsMUL{}, O.OpsXOR{}, O.OpsAND{}, O.OpsOR{}, O.OpsCDIV{}, O.OpsCMOD{}, O.OpsMAX{}, O.OpsCMPEQ{},
   O.OpsCMPLT{}, O.OpsCMPNE{}, O.OpsMULACC{}, O.OpsWHERE{}]

# A DROP-FILTER over `asm_for_op`'s key order. The head goes in FRONT of the
# tail's answer (`List.append(..., [o], rest)` is `[o] ++ rest`) and the
# recursion is called ONCE through the `+rest` binder: a `Bool.pick` with the
# self-call in both arms calls it TWICE, and a self-call SPENDS the list it
# walks, so the first arm's answer comes back spent. The version that also ran
# a `List.reverse` on top printed the fourteen names backwards.
def dsh.go(+ops: List<&2, O.Op>, +acc: List<&2, O.Op>) -> List<&2, O.Op>:
  match ops:
    case Nil{}   : acc
    case o <> +t :
      +rest = dsh.go(t, acc)
      Bool.pick(List<&2, O.Op>, in_sh(o), rest, List.append(&2, O.Op, [o], rest))

def doesnt_support_half() -> List<&2, O.Op>: dsh.go(asm_keys(), Nil{})

# ===========================================================================
# :78 `modifier(a, b)` -- `'.rzi' if is_int(a) and is_float(b) else '.rn' if
# is_float(a) and (a.itemsize < b.itemsize or is_int(b) or b == bool) else ''`.
# Three clauses, ANDed in two pairs; the gate runs all 9x6 dtype pairs because
# the third clause alone distinguishes float->float from half->float.
# ===========================================================================
def modifier(+fa: Dtf, +fb: Dtf, +a: S.Dt, +b: S.Dt) -> String:
  Bool.pick(String, Bool.and(Dtf.is_int(fa), Dtf.is_float(fb)), ".rzi",
    Bool.pick(String, Bool.and(Dtf.is_float(fa), Bool.or(U32.is_lt(S.Dt.itemsize(a), S.Dt.itemsize(b)),
      Bool.or(Dtf.is_int(fb), O.eq_dt(b, S.boolean())))), ".rn", ""))
# ===========================================================================
# THE STAGE 2 GATE -- ptx.py's emitters. Every row is a STRING beside CPython's.
#
#   * `render_val` over half / float / unsigned -- the three PORTED arms. The
#     signed-integer and double arms are walls and are NOT rows.
#   * `asm_for_op`'s twenty-one entries over five dtypes with `name` FIXED at
#     "s32" (105 rows) -- that isolates the DTYPE branch -- plus five ops over
#     all twelve dtypes with `name = ctx.types[dt]` (60 rows), which isolates
#     the NAME branch: `shl.b{name[1:]}`, `xor.b{name[1:]}`, `selp.b16`.
#   * `supports_half` / `doesnt_support_half` as NAME LISTS in the dict's own
#     order, which is what the tuple comprehension preserves.
#   * `modifier` over all 54 dtype pairs.
#   * the three dtype tables, the two maxima, the suffix, the barrier (TAB
#     escaped) and the kernel prefix split one row per line plus a COUNT.
#   * `supported_dtypes` and `tensor_cores` for three arches.
# ===========================================================================
def pm_n_rules() -> U32: 8


def r_pmx_n() -> String: r("ptx_matcher rules", U32.show(pm_n_rules()), "8")

# `ptx_matcher` (ptx.py:40-57) is SEVEN rules and every one is a graph REWRITE:
# three bool-only algebra rewrites, an upcast to float32, two bool-buffer
# uint8 views and two uint casts of a shift amount. Each builds a NEW node
# (`x.replace(src=(...))`, `UOp(x.op, src=..., arg=...)`), and the arena is
# `Type`, so a rule returning an index the caller cannot dereference is the
# wall `uop/divandmod.bend`'s header already names. THE COUNT is the row that
# is derivable here; the seven rewrites are:
#   TODO(p3) ptx.py:42  bool NE -> x^y
#   TODO(p3) ptx.py:43  bool EQ -> (x^y)^True
#   TODO(p3) ptx.py:44  bool LT -> (x^True)&y
#   TODO(p3) ptx.py:46  upcast the half ops that do not support half
#   TODO(p3) ptx.py:49  bool LOAD through a uint8 view (needs with_storage)
#   TODO(p3) ptx.py:52  bool STORE through a uint8 view
#   TODO(p3) ptx.py:55  SHL with a non-uint shift amount -> cast
#   TODO(p3) ptx.py:56  SHR with a non-uint shift amount -> cast

# `render_val` -- `F32.bits` is the float pattern and half is a RE-ENCODE, so
# half goes through `f16bits` and float does not.
def r_rv1(+nm: String, flt: Bool, half_: Bool, uns: Bool, +x: F32, +v: U32, py: String) -> String:
  r("render_val " ++ nm, render_val(flt, half_, uns, x, v), py)

def r_rvs() -> String:
  String.concat([r_rv1("half 0.0", True{}, True{}, False{}, 0.0, 0, "0x0000"), r_rv1("half 1.0", True{}, True{}, False{}, 1.0, 0, "0x3C00"), r_rv1("half -2.5", True{}, True{}, False{}, F32.neg(2.5), 0, "0xC100"), r_rv1("half 0.3330078125", True{}, True{}, False{}, 0.3330078125, 0, "0x3554"), r_rv1("float 0.0", True{}, False{}, False{}, 0.0, 0, "0f00000000"), r_rv1("float 1.0", True{}, False{}, False{}, 1.0, 0, "0f3F800000"), r_rv1("float -2.5", True{}, False{}, False{}, F32.neg(2.5), 0, "0fC0200000"), r_rv1("float 3.5", True{}, False{}, False{}, 3.5, 0, "0f40600000"), r_rv1("unsigned int 0", False{}, False{}, True{}, 0.0, 0, "0U"), r_rv1("unsigned int 7", False{}, False{}, True{}, 0.0, 7, "7U"), r_rv1("unsigned int 4294967295", False{}, False{}, True{}, 0.0, 4294967295, "4294967295U"), r_rv1("unsigned char 255", False{}, False{}, True{}, 0.0, 255, "255U")])

# `asm_for_op`'s twenty-one arms with `name` FIXED at "s32", so the row is about
# the DTYPE branch alone.
def r_asm1(+opn: String, +op: O.Op, +dt: S.Dt, +name: String, py: String) -> String:
  r("asm " ++ opn ++ " " ++ dt_name(dt), String.join(op_asm(op, "%d", "%a", "%b", "%c", name, Dtf.of(dt)), " ;; "), py)

def r_asms() -> String:
  String.concat([r_asm1("RECIPROCAL", O.OpsRECIPROCAL{}, S.single(), "s32", "rcp.approx.s32 %d, %a;"), r_asm1("EXP2", O.OpsEXP2{}, S.single(), "s32", "ex2.approx.s32 %d, %a;"), r_asm1("LOG2", O.OpsLOG2{}, S.single(), "s32", "lg2.approx.s32 %d, %a;"), r_asm1("SIN", O.OpsSIN{}, S.single(), "s32", "sin.approx.s32 %d, %a;"), r_asm1("SQRT", O.OpsSQRT{}, S.single(), "s32", "sqrt.approx.s32 %d, %a;"), r_asm1("TRUNC", O.OpsTRUNC{}, S.single(), "s32", "cvt.rzi.s32.s32 %d, %a;"), r_asm1("SHR", O.OpsSHR{}, S.single(), "s32", "shr.s32 %d, %a, %b;"), r_asm1("SHL", O.OpsSHL{}, S.single(), "s32", "shl.b32 %d, %a, %b;"), r_asm1("ADD", O.OpsADD{}, S.single(), "s32", "add.s32 %d, %a, %b;"), r_asm1("MUL", O.OpsMUL{}, S.single(), "s32", "mul.s32 %d, %a, %b;"), r_asm1("XOR", O.OpsXOR{}, S.single(), "s32", "xor.b32 %d, %a, %b;"), r_asm1("AND", O.OpsAND{}, S.single(), "s32", "and.b32 %d, %a, %b;"), r_asm1("OR", O.OpsOR{}, S.single(), "s32", "or.b32 %d, %a, %b;"), r_asm1("CDIV", O.OpsCDIV{}, S.single(), "s32", "div.s32 %d, %a, %b;"), r_asm1("CMOD", O.OpsCMOD{}, S.single(), "s32", "rem.s32 %d, %a, %b;"), r_asm1("MAX", O.OpsMAX{}, S.single(), "s32", "max.s32 %d, %a, %b;"), r_asm1("CMPEQ", O.OpsCMPEQ{}, S.single(), "s32", "setp.eq.s32 %d, %a, %b;"), r_asm1("CMPLT", O.OpsCMPLT{}, S.single(), "s32", "setp.lt.s32 %d, %a, %b;"), r_asm1("CMPNE", O.OpsCMPNE{}, S.single(), "s32", "setp.neu.s32 %d, %a, %b;"), r_asm1("MULACC", O.OpsMULACC{}, S.single(), "s32", "fma.rn.s32 %d, %a, %b, %c;"), r_asm1("RECIPROCAL", O.OpsRECIPROCAL{}, S.half(), "s32", "rcp.approx.s32 %d, %a;"), r_asm1("EXP2", O.OpsEXP2{}, S.half(), "s32", "ex2.approx.s32 %d, %a;"), r_asm1("LOG2", O.OpsLOG2{}, S.half(), "s32", "lg2.approx.s32 %d, %a;"), r_asm1("SIN", O.OpsSIN{}, S.half(), "s32", "sin.approx.s32 %d, %a;"), r_asm1("SQRT", O.OpsSQRT{}, S.half(), "s32", "sqrt.approx.s32 %d, %a;"), r_asm1("TRUNC", O.OpsTRUNC{}, S.half(), "s32", "cvt.rzi.s32.s32 %d, %a;"), r_asm1("SHR", O.OpsSHR{}, S.half(), "s32", "shr.s32 %d, %a, %b;"), r_asm1("SHL", O.OpsSHL{}, S.half(), "s32", "shl.b32 %d, %a, %b;"), r_asm1("ADD", O.OpsADD{}, S.half(), "s32", "add.s32 %d, %a, %b;"), r_asm1("MUL", O.OpsMUL{}, S.half(), "s32", "mul.s32 %d, %a, %b;"), r_asm1("XOR", O.OpsXOR{}, S.half(), "s32", "xor.b32 %d, %a, %b;"), r_asm1("AND", O.OpsAND{}, S.half(), "s32", "and.b32 %d, %a, %b;"), r_asm1("OR", O.OpsOR{}, S.half(), "s32", "or.b32 %d, %a, %b;"), r_asm1("CDIV", O.OpsCDIV{}, S.half(), "s32", "div.s32 %d, %a, %b;"), r_asm1("CMOD", O.OpsCMOD{}, S.half(), "s32", "rem.s32 %d, %a, %b;"), r_asm1("MAX", O.OpsMAX{}, S.half(), "s32", "max.s32 %d, %a, %b;"), r_asm1("CMPEQ", O.OpsCMPEQ{}, S.half(), "s32", "setp.eq.s32 %d, %a, %b;"), r_asm1("CMPLT", O.OpsCMPLT{}, S.half(), "s32", "setp.lt.s32 %d, %a, %b;"), r_asm1("CMPNE", O.OpsCMPNE{}, S.half(), "s32", "setp.neu.s32 %d, %a, %b;"), r_asm1("MULACC", O.OpsMULACC{}, S.half(), "s32", "fma.rn.s32 %d, %a, %b, %c;"), r_asm1("RECIPROCAL", O.OpsRECIPROCAL{}, S.boolean(), "s32", "rcp.s32 %d, %a;"), r_asm1("EXP2", O.OpsEXP2{}, S.boolean(), "s32", "ex2.approx.s32 %d, %a;"), r_asm1("LOG2", O.OpsLOG2{}, S.boolean(), "s32", "lg2.approx.s32 %d, %a;"), r_asm1("SIN", O.OpsSIN{}, S.boolean(), "s32", "sin.approx.s32 %d, %a;"), r_asm1("SQRT", O.OpsSQRT{}, S.boolean(), "s32", "sqrt.approx.s32 %d, %a;"), r_asm1("TRUNC", O.OpsTRUNC{}, S.boolean(), "s32", "cvt.rzi.s32.s32 %d, %a;"), r_asm1("SHR", O.OpsSHR{}, S.boolean(), "s32", "shr.s32 %d, %a, %b;"), r_asm1("SHL", O.OpsSHL{}, S.boolean(), "s32", "shl.b32 %d, %a, %b;"), r_asm1("ADD", O.OpsADD{}, S.boolean(), "s32", "or.s32 %d, %a, %b;"), r_asm1("MUL", O.OpsMUL{}, S.boolean(), "s32", "and.s32 %d, %a, %b;"), r_asm1("XOR", O.OpsXOR{}, S.boolean(), "s32", "xor.pred %d, %a, %b;"), r_asm1("AND", O.OpsAND{}, S.boolean(), "s32", "and.pred %d, %a, %b;"), r_asm1("OR", O.OpsOR{}, S.boolean(), "s32", "or.pred %d, %a, %b;"), r_asm1("CDIV", O.OpsCDIV{}, S.boolean(), "s32", "div.s32 %d, %a, %b;"), r_asm1("CMOD", O.OpsCMOD{}, S.boolean(), "s32", "rem.s32 %d, %a, %b;"), r_asm1("MAX", O.OpsMAX{}, S.boolean(), "s32", "max.s32 %d, %a, %b;"), r_asm1("CMPEQ", O.OpsCMPEQ{}, S.boolean(), "s32", "setp.eq.s32 %d, %a, %b;"), r_asm1("CMPLT", O.OpsCMPLT{}, S.boolean(), "s32", "setp.lt.s32 %d, %a, %b;"), r_asm1("CMPNE", O.OpsCMPNE{}, S.boolean(), "s32", "setp.ne.s32 %d, %a, %b;"), r_asm1("MULACC", O.OpsMULACC{}, S.boolean(), "s32", "mad.lo.s32 %d, %a, %b, %c;"), r_asm1("RECIPROCAL", O.OpsRECIPROCAL{}, S.uint32(), "s32", "rcp.s32 %d, %a;"), r_asm1("EXP2", O.OpsEXP2{}, S.uint32(), "s32", "ex2.approx.s32 %d, %a;"), r_asm1("LOG2", O.OpsLOG2{}, S.uint32(), "s32", "lg2.approx.s32 %d, %a;"), r_asm1("SIN", O.OpsSIN{}, S.uint32(), "s32", "sin.approx.s32 %d, %a;"), r_asm1("SQRT", O.OpsSQRT{}, S.uint32(), "s32", "sqrt.approx.s32 %d, %a;"), r_asm1("TRUNC", O.OpsTRUNC{}, S.uint32(), "s32", "cvt.rzi.s32.s32 %d, %a;"), r_asm1("SHR", O.OpsSHR{}, S.uint32(), "s32", "shr.s32 %d, %a, %b;"), r_asm1("SHL", O.OpsSHL{}, S.uint32(), "s32", "shl.b32 %d, %a, %b;"), r_asm1("ADD", O.OpsADD{}, S.uint32(), "s32", "add.s32 %d, %a, %b;"), r_asm1("MUL", O.OpsMUL{}, S.uint32(), "s32", "mul.lo.s32 %d, %a, %b;"), r_asm1("XOR", O.OpsXOR{}, S.uint32(), "s32", "xor.b32 %d, %a, %b;"), r_asm1("AND", O.OpsAND{}, S.uint32(), "s32", "and.b32 %d, %a, %b;"), r_asm1("OR", O.OpsOR{}, S.uint32(), "s32", "or.b32 %d, %a, %b;"), r_asm1("CDIV", O.OpsCDIV{}, S.uint32(), "s32", "div.s32 %d, %a, %b;"), r_asm1("CMOD", O.OpsCMOD{}, S.uint32(), "s32", "rem.s32 %d, %a, %b;"), r_asm1("MAX", O.OpsMAX{}, S.uint32(), "s32", "max.s32 %d, %a, %b;"), r_asm1("CMPEQ", O.OpsCMPEQ{}, S.uint32(), "s32", "setp.eq.s32 %d, %a, %b;"), r_asm1("CMPLT", O.OpsCMPLT{}, S.uint32(), "s32", "setp.lt.s32 %d, %a, %b;"), r_asm1("CMPNE", O.OpsCMPNE{}, S.uint32(), "s32", "setp.ne.s32 %d, %a, %b;"), r_asm1("MULACC", O.OpsMULACC{}, S.uint32(), "s32", "mad.lo.s32 %d, %a, %b, %c;"), r_asm1("RECIPROCAL", O.OpsRECIPROCAL{}, S.int32(), "s32", "rcp.s32 %d, %a;"), r_asm1("EXP2", O.OpsEXP2{}, S.int32(), "s32", "ex2.approx.s32 %d, %a;"), r_asm1("LOG2", O.OpsLOG2{}, S.int32(), "s32", "lg2.approx.s32 %d, %a;"), r_asm1("SIN", O.OpsSIN{}, S.int32(), "s32", "sin.approx.s32 %d, %a;"), r_asm1("SQRT", O.OpsSQRT{}, S.int32(), "s32", "sqrt.approx.s32 %d, %a;"), r_asm1("TRUNC", O.OpsTRUNC{}, S.int32(), "s32", "cvt.rzi.s32.s32 %d, %a;"), r_asm1("SHR", O.OpsSHR{}, S.int32(), "s32", "shr.s32 %d, %a, %b;"), r_asm1("SHL", O.OpsSHL{}, S.int32(), "s32", "shl.b32 %d, %a, %b;"), r_asm1("ADD", O.OpsADD{}, S.int32(), "s32", "add.s32 %d, %a, %b;"), r_asm1("MUL", O.OpsMUL{}, S.int32(), "s32", "mul.lo.s32 %d, %a, %b;"), r_asm1("XOR", O.OpsXOR{}, S.int32(), "s32", "xor.b32 %d, %a, %b;"), r_asm1("AND", O.OpsAND{}, S.int32(), "s32", "and.b32 %d, %a, %b;"), r_asm1("OR", O.OpsOR{}, S.int32(), "s32", "or.b32 %d, %a, %b;"), r_asm1("CDIV", O.OpsCDIV{}, S.int32(), "s32", "div.s32 %d, %a, %b;"), r_asm1("CMOD", O.OpsCMOD{}, S.int32(), "s32", "rem.s32 %d, %a, %b;"), r_asm1("MAX", O.OpsMAX{}, S.int32(), "s32", "max.s32 %d, %a, %b;"), r_asm1("CMPEQ", O.OpsCMPEQ{}, S.int32(), "s32", "setp.eq.s32 %d, %a, %b;"), r_asm1("CMPLT", O.OpsCMPLT{}, S.int32(), "s32", "setp.lt.s32 %d, %a, %b;"), r_asm1("CMPNE", O.OpsCMPNE{}, S.int32(), "s32", "setp.ne.s32 %d, %a, %b;"), r_asm1("MULACC", O.OpsMULACC{}, S.int32(), "s32", "mad.lo.s32 %d, %a, %b, %c;")])

# THE NAME BRANCH. `name = ctx.types[dt]`, so `name[1:]` is `drop(name, 1n)` and
# the SAME op over twelve dtypes gives twelve different suffixes -- including
# `shl.bred` for bool, because `types[bool]` is `pred`. That is what Python
# emits and it is the row that catches a `name[1:]` read as `name[1]`.
def r_asm2_1(+opn: String, +op: O.Op, +dt: S.Dt, py: String) -> String:
  r("asm2 " ++ opn ++ " " ++ dt_name(dt), String.join(op_asm(op, "%d", "%a", "%b", "%c", types_of(dt), Dtf.of(dt)), " ;; "), py)

def r_asm2s() -> String:
  String.concat([r_asm2_1("ADD", O.OpsADD{}, S.int8(), "add.s16 %d, %a, %b;"), r_asm2_1("SHL", O.OpsSHL{}, S.int8(), "shl.b16 %d, %a, %b;"), r_asm2_1("XOR", O.OpsXOR{}, S.int8(), "xor.b16 %d, %a, %b;"), r_asm2_1("MULACC", O.OpsMULACC{}, S.int8(), "mad.lo.s16 %d, %a, %b, %c;"), r_asm2_1("WHERE", O.OpsWHERE{}, S.int8(), "selp.s16 %d, %b, %c, %a;"), r_asm2_1("TRUNC", O.OpsTRUNC{}, S.int8(), "cvt.rzi.s16.s16 %d, %a;"), r_asm2_1("ADD", O.OpsADD{}, S.int16(), "add.s16 %d, %a, %b;"), r_asm2_1("SHL", O.OpsSHL{}, S.int16(), "shl.b16 %d, %a, %b;"), r_asm2_1("XOR", O.OpsXOR{}, S.int16(), "xor.b16 %d, %a, %b;"), r_asm2_1("MULACC", O.OpsMULACC{}, S.int16(), "mad.lo.s16 %d, %a, %b, %c;"), r_asm2_1("WHERE", O.OpsWHERE{}, S.int16(), "selp.s16 %d, %b, %c, %a;"), r_asm2_1("TRUNC", O.OpsTRUNC{}, S.int16(), "cvt.rzi.s16.s16 %d, %a;"), r_asm2_1("ADD", O.OpsADD{}, S.int32(), "add.s32 %d, %a, %b;"), r_asm2_1("SHL", O.OpsSHL{}, S.int32(), "shl.b32 %d, %a, %b;"), r_asm2_1("XOR", O.OpsXOR{}, S.int32(), "xor.b32 %d, %a, %b;"), r_asm2_1("MULACC", O.OpsMULACC{}, S.int32(), "mad.lo.s32 %d, %a, %b, %c;"), r_asm2_1("WHERE", O.OpsWHERE{}, S.int32(), "selp.s32 %d, %b, %c, %a;"), r_asm2_1("TRUNC", O.OpsTRUNC{}, S.int32(), "cvt.rzi.s32.s32 %d, %a;"), r_asm2_1("ADD", O.OpsADD{}, S.int64(), "add.s64 %d, %a, %b;"), r_asm2_1("SHL", O.OpsSHL{}, S.int64(), "shl.b64 %d, %a, %b;"), r_asm2_1("XOR", O.OpsXOR{}, S.int64(), "xor.b64 %d, %a, %b;"), r_asm2_1("MULACC", O.OpsMULACC{}, S.int64(), "mad.lo.s64 %d, %a, %b, %c;"), r_asm2_1("WHERE", O.OpsWHERE{}, S.int64(), "selp.s64 %d, %b, %c, %a;"), r_asm2_1("TRUNC", O.OpsTRUNC{}, S.int64(), "cvt.rzi.s64.s64 %d, %a;"), r_asm2_1("ADD", O.OpsADD{}, S.uint8(), "add.u16 %d, %a, %b;"), r_asm2_1("SHL", O.OpsSHL{}, S.uint8(), "shl.b16 %d, %a, %b;"), r_asm2_1("XOR", O.OpsXOR{}, S.uint8(), "xor.b16 %d, %a, %b;"), r_asm2_1("MULACC", O.OpsMULACC{}, S.uint8(), "mad.lo.u16 %d, %a, %b, %c;"), r_asm2_1("WHERE", O.OpsWHERE{}, S.uint8(), "selp.u16 %d, %b, %c, %a;"), r_asm2_1("TRUNC", O.OpsTRUNC{}, S.uint8(), "cvt.rzi.u16.u16 %d, %a;"), r_asm2_1("ADD", O.OpsADD{}, S.uint16(), "add.u16 %d, %a, %b;"), r_asm2_1("SHL", O.OpsSHL{}, S.uint16(), "shl.b16 %d, %a, %b;"), r_asm2_1("XOR", O.OpsXOR{}, S.uint16(), "xor.b16 %d, %a, %b;"), r_asm2_1("MULACC", O.OpsMULACC{}, S.uint16(), "mad.lo.u16 %d, %a, %b, %c;"), r_asm2_1("WHERE", O.OpsWHERE{}, S.uint16(), "selp.u16 %d, %b, %c, %a;"), r_asm2_1("TRUNC", O.OpsTRUNC{}, S.uint16(), "cvt.rzi.u16.u16 %d, %a;"), r_asm2_1("ADD", O.OpsADD{}, S.uint32(), "add.u32 %d, %a, %b;"), r_asm2_1("SHL", O.OpsSHL{}, S.uint32(), "shl.b32 %d, %a, %b;"), r_asm2_1("XOR", O.OpsXOR{}, S.uint32(), "xor.b32 %d, %a, %b;"), r_asm2_1("MULACC", O.OpsMULACC{}, S.uint32(), "mad.lo.u32 %d, %a, %b, %c;"), r_asm2_1("WHERE", O.OpsWHERE{}, S.uint32(), "selp.u32 %d, %b, %c, %a;"), r_asm2_1("TRUNC", O.OpsTRUNC{}, S.uint32(), "cvt.rzi.u32.u32 %d, %a;"), r_asm2_1("ADD", O.OpsADD{}, S.uint64(), "add.u64 %d, %a, %b;"), r_asm2_1("SHL", O.OpsSHL{}, S.uint64(), "shl.b64 %d, %a, %b;"), r_asm2_1("XOR", O.OpsXOR{}, S.uint64(), "xor.b64 %d, %a, %b;"), r_asm2_1("MULACC", O.OpsMULACC{}, S.uint64(), "mad.lo.u64 %d, %a, %b, %c;"), r_asm2_1("WHERE", O.OpsWHERE{}, S.uint64(), "selp.u64 %d, %b, %c, %a;"), r_asm2_1("TRUNC", O.OpsTRUNC{}, S.uint64(), "cvt.rzi.u64.u64 %d, %a;"), r_asm2_1("ADD", O.OpsADD{}, S.half(), "add.f16 %d, %a, %b;"), r_asm2_1("SHL", O.OpsSHL{}, S.half(), "shl.b16 %d, %a, %b;"), r_asm2_1("XOR", O.OpsXOR{}, S.half(), "xor.b16 %d, %a, %b;"), r_asm2_1("MULACC", O.OpsMULACC{}, S.half(), "fma.rn.f16 %d, %a, %b, %c;"), r_asm2_1("WHERE", O.OpsWHERE{}, S.half(), "selp.b16 %d, %b, %c, %a;"), r_asm2_1("TRUNC", O.OpsTRUNC{}, S.half(), "cvt.rzi.f16.f16 %d, %a;"), r_asm2_1("ADD", O.OpsADD{}, S.single(), "add.f32 %d, %a, %b;"), r_asm2_1("SHL", O.OpsSHL{}, S.single(), "shl.b32 %d, %a, %b;"), r_asm2_1("XOR", O.OpsXOR{}, S.single(), "xor.b32 %d, %a, %b;"), r_asm2_1("MULACC", O.OpsMULACC{}, S.single(), "fma.rn.f32 %d, %a, %b, %c;"), r_asm2_1("WHERE", O.OpsWHERE{}, S.single(), "selp.f32 %d, %b, %c, %a;"), r_asm2_1("TRUNC", O.OpsTRUNC{}, S.single(), "cvt.rzi.f32.f32 %d, %a;"), r_asm2_1("ADD", O.OpsADD{}, S.double(), "add.f64 %d, %a, %b;"), r_asm2_1("SHL", O.OpsSHL{}, S.double(), "shl.b64 %d, %a, %b;"), r_asm2_1("XOR", O.OpsXOR{}, S.double(), "xor.b64 %d, %a, %b;"), r_asm2_1("MULACC", O.OpsMULACC{}, S.double(), "fma.rn.f64 %d, %a, %b, %c;"), r_asm2_1("WHERE", O.OpsWHERE{}, S.double(), "selp.f64 %d, %b, %c, %a;"), r_asm2_1("TRUNC", O.OpsTRUNC{}, S.double(), "cvt.rzi.f64.f64 %d, %a;"), r_asm2_1("ADD", O.OpsADD{}, S.boolean(), "or.pred %d, %a, %b;"), r_asm2_1("SHL", O.OpsSHL{}, S.boolean(), "shl.bred %d, %a, %b;"), r_asm2_1("XOR", O.OpsXOR{}, S.boolean(), "xor.pred %d, %a, %b;"), r_asm2_1("MULACC", O.OpsMULACC{}, S.boolean(), "mad.lo.pred %d, %a, %b, %c;"), r_asm2_1("WHERE", O.OpsWHERE{}, S.boolean(), "@%a mov.pred %d, %b; ;; @!%a mov.pred %d, %c;"), r_asm2_1("TRUNC", O.OpsTRUNC{}, S.boolean(), "cvt.rzi.pred.pred %d, %a;")])

# WHERE's three FORMS: the TWO-ELEMENT LIST on bool, `selp.b16` when the name is
# f16 (PTX has no `selp.f16`), and `selp.<name>` otherwise. Keeping the list means
# the bool arm's TWO kernel lines stay visible in the row.
def r_where() -> String:
  String.concat([r("asm WHERE float", String.join(op_asm(O.OpsWHERE{}, "%d", "%a", "%b", "%c", "f16", Dtf.of(S.single())), " ;; "), "selp.b16 %d, %b, %c, %a;"),
    r("asm WHERE bool", String.join(op_asm(O.OpsWHERE{}, "%d", "%a", "%b", "%c", "f16", Dtf.of(S.boolean())), " ;; "), "@%a mov.f16 %d, %b; ;; @!%a mov.f16 %d, %c;"),
    r("asm WHERE b16f32", String.join(op_asm(O.OpsWHERE{}, "%d", "%a", "%b", "%c", "f32", Dtf.of(S.single())), " ;; "), "selp.f32 %d, %b, %c, %a;")])

# `",".join(ops.Ops)` over `asm_for_op`'s own key order: `supports_half` is the
# seven-name tuple and `doesnt_support_half` the fourteen-name complement, and the
# ORDER is what the dict comprehension preserves.
def op_names(+ops: List<&2, O.Op>) -> String:
  match ops:
    case Nil{}   : ""
    case o <> +t : String.concat([O.Ops.name.of(o), Bool.pick(String, List.is_empty(&2, O.Op, t), "", ","), op_names(t)])

def r_sh() -> String:
  String.concat([r("supports_half", op_names(supports_half()), "EXP2,ADD,MUL,MAX,CMPLT,WHERE,TRUNC"), r("doesnt_support_half", op_names(doesnt_support_half()), "RECIPROCAL,LOG2,SIN,SQRT,SHR,SHL,XOR,AND,OR,CDIV,CMOD,CMPEQ,CMPNE,MULACC")])

# `modifier` over all 54 dtype pairs. The third clause alone separates
# float->float (empty) from half->float (`.rn`), so every pair is a row.
def r_mod1(+nm: String, +a: S.Dt, +b: S.Dt, py: String) -> String:
  r("modifier " ++ nm, modifier(Dtf.of(a), Dtf.of(b), a, b), py)

def r_mods() -> String:
  String.concat([r_mod1("signed char,signed char", S.int8(), S.int8(), ""), r_mod1("signed char,int", S.int8(), S.int32(), ""), r_mod1("signed char,float", S.int8(), S.single(), ".rzi"), r_mod1("signed char,half", S.int8(), S.half(), ".rzi"), r_mod1("signed char,bool", S.int8(), S.boolean(), ""), r_mod1("signed char,double", S.int8(), S.double(), ".rzi"), r_mod1("short,signed char", S.int16(), S.int8(), ""), r_mod1("short,int", S.int16(), S.int32(), ""), r_mod1("short,float", S.int16(), S.single(), ".rzi"), r_mod1("short,half", S.int16(), S.half(), ".rzi"), r_mod1("short,bool", S.int16(), S.boolean(), ""), r_mod1("short,double", S.int16(), S.double(), ".rzi"), r_mod1("int,signed char", S.int32(), S.int8(), ""), r_mod1("int,int", S.int32(), S.int32(), ""), r_mod1("int,float", S.int32(), S.single(), ".rzi"), r_mod1("int,half", S.int32(), S.half(), ".rzi"), r_mod1("int,bool", S.int32(), S.boolean(), ""), r_mod1("int,double", S.int32(), S.double(), ".rzi"), r_mod1("unsigned char,signed char", S.uint8(), S.int8(), ""), r_mod1("unsigned char,int", S.uint8(), S.int32(), ""), r_mod1("unsigned char,float", S.uint8(), S.single(), ".rzi"), r_mod1("unsigned char,half", S.uint8(), S.half(), ".rzi"), r_mod1("unsigned char,bool", S.uint8(), S.boolean(), ""), r_mod1("unsigned char,double", S.uint8(), S.double(), ".rzi"), r_mod1("unsigned int,signed char", S.uint32(), S.int8(), ""), r_mod1("unsigned int,int", S.uint32(), S.int32(), ""), r_mod1("unsigned int,float", S.uint32(), S.single(), ".rzi"), r_mod1("unsigned int,half", S.uint32(), S.half(), ".rzi"), r_mod1("unsigned int,bool", S.uint32(), S.boolean(), ""), r_mod1("unsigned int,double", S.uint32(), S.double(), ".rzi"), r_mod1("float,signed char", S.single(), S.int8(), ".rn"), r_mod1("float,int", S.single(), S.int32(), ".rn"), r_mod1("float,float", S.single(), S.single(), ""), r_mod1("float,half", S.single(), S.half(), ""), r_mod1("float,bool", S.single(), S.boolean(), ".rn"), r_mod1("float,double", S.single(), S.double(), ".rn"), r_mod1("half,signed char", S.half(), S.int8(), ".rn"), r_mod1("half,int", S.half(), S.int32(), ".rn"), r_mod1("half,float", S.half(), S.single(), ".rn"), r_mod1("half,half", S.half(), S.half(), ""), r_mod1("half,bool", S.half(), S.boolean(), ".rn"), r_mod1("half,double", S.half(), S.double(), ".rn"), r_mod1("bool,signed char", S.boolean(), S.int8(), ""), r_mod1("bool,int", S.boolean(), S.int32(), ""), r_mod1("bool,float", S.boolean(), S.single(), ""), r_mod1("bool,half", S.boolean(), S.half(), ""), r_mod1("bool,bool", S.boolean(), S.boolean(), ""), r_mod1("bool,double", S.boolean(), S.double(), ""), r_mod1("double,signed char", S.double(), S.int8(), ".rn"), r_mod1("double,int", S.double(), S.int32(), ".rn"), r_mod1("double,float", S.double(), S.single(), ""), r_mod1("double,half", S.double(), S.half(), ""), r_mod1("double,bool", S.double(), S.boolean(), ".rn"), r_mod1("double,double", S.double(), S.double(), "")])

def r_types1(+nm: String, +dt: S.Dt, py: String) -> String:
  r("types " ++ nm, types_of(dt), py)

def r_mem_types1(+nm: String, +dt: S.Dt, py: String) -> String:
  r("mem_types " ++ nm, mem_types_of(dt), py)

def r_cast_types1(+nm: String, +dt: S.Dt, py: String) -> String:
  r("cast_types " ++ nm, cast_types_of(dt), py)

# `PTXRenderer.types` over all TWELVE of its keys, in the dict's own order --
# which is the order `R.types.items()` reports. `mem_types` and `cast_types` are
# `{**types, ...}` overrides of the same twelve keys, so they repeat the whole
# table and differ only at the four and two overridden entries.
def r_tabs() -> String:
  String.concat([r_types1("signed char", S.int8(), "s16"), r_types1("short", S.int16(), "s16"), r_types1("int", S.int32(), "s32"), r_types1("long", S.int64(), "s64"), r_types1("unsigned char", S.uint8(), "u16"), r_types1("unsigned short", S.uint16(), "u16"), r_types1("unsigned int", S.uint32(), "u32"), r_types1("unsigned long", S.uint64(), "u64"), r_types1("half", S.half(), "f16"), r_types1("float", S.single(), "f32"), r_types1("double", S.double(), "f64"), r_types1("bool", S.boolean(), "pred")])

def r_mc_tabs() -> String:
  String.concat([r_mem_types1("signed char", S.int8(), "s8"), r_mem_types1("short", S.int16(), "s16"), r_mem_types1("int", S.int32(), "s32"), r_mem_types1("long", S.int64(), "s64"), r_mem_types1("unsigned char", S.uint8(), "u8"), r_mem_types1("unsigned short", S.uint16(), "u16"), r_mem_types1("unsigned int", S.uint32(), "u32"), r_mem_types1("unsigned long", S.uint64(), "u64"), r_mem_types1("half", S.half(), "b16"), r_mem_types1("float", S.single(), "f32"), r_mem_types1("double", S.double(), "f64"), r_mem_types1("bool", S.boolean(), "u8"), r_cast_types1("signed char", S.int8(), "s8"), r_cast_types1("short", S.int16(), "s16"), r_cast_types1("int", S.int32(), "s32"), r_cast_types1("long", S.int64(), "s64"), r_cast_types1("unsigned char", S.uint8(), "u8"), r_cast_types1("unsigned short", S.uint16(), "u16"), r_cast_types1("unsigned int", S.uint32(), "u32"), r_cast_types1("unsigned long", S.uint64(), "u64"), r_cast_types1("half", S.half(), "f16"), r_cast_types1("float", S.single(), "f32"), r_cast_types1("double", S.double(), "f64"), r_cast_types1("bool", S.boolean(), "pred")])

# THE KeyError ARM. `PTXRenderer.types` has no key for the eight fp8 dtypes nor
# for bfloat16, and nothing on a PTX target asks for one -- so the unreachable
# arm is a row of its own rather than a silent `""`. The port has no exception,
# so the arm answers a MARKER and the row says which marker.
def ifmiss(+s: String) -> String: Bool.pick(String, String.is_empty(s), "KeyError", s)

def r_tabs_miss() -> String:
  String.concat([r("types float8_e4m3", ifmiss(types_of(S.fp8e4m3())), "KeyError"), r("types __bf16", ifmiss(types_of(S.bfloat16())), "KeyError")])


# `CUDARenderer.global_max/local_max/shared_max`, `suffix`, `barrier` (with its TAB
# escaped so a dropped TAB is a diff), and `kernel_prefix` ONE ROW PER LINE plus a
# COUNT -- a re-wrapped four-line string would hide a dropped line.
def px_prefix_lines() -> U32: 4
def px_pline(+i: U32) -> String:
  match i:
    case 0: px_p0()
    case 1: px_p1()
    case 2: px_p2()
    case _:  px_p3()
def bslash() -> String: String.from_list([Char.from_u32(92)])

# `\t` and `\n` AS TEXT. This is not an alias for `esc`: it is how a `py=` half
# has to be SPELLED, because a Bend `"…\t…"` literal holds a real TAB and the
# oracle's `repr()` holds a backslash and a `t`.
def btab() -> String: String.concat([bslash(), "t"])

def bnl() -> String: String.concat([bslash(), "n"])

def esc1(+c: Char) -> String:
  Bool.pick(String, U32.is_eq(Char.to_u32(c), 9), btab(),
    Bool.pick(String, U32.is_eq(Char.to_u32(c), 10), bnl(), String.from_list([c])))

def esc.go(+s: String, +acc: String) -> String:
  match s:
    case SNil{}     : acc
    case SCon{c, t} : esc.go(t, String.concat([acc, esc1(c)]))

def esc(+s: String) -> String: esc.go(s, "")

# CPython's `repr(str)`, which is what the oracle's `fmt` rows put on BOTH
# halves -- `'mov.b32 %r0, %r1;'` as the row NAME and `'\tmov.b32\t\t%r0, %r1;'`
# as the value. So the row name is quoted too, and quoting it is what makes a
# leading `$` visible instead of being the first character of the name.
def q(+s: String) -> String: String.concat(["'", esc(s), "'"])



def r_consts() -> String:
  String.concat([r("barrier", esc(px_barrier()), String.concat(["bar.sync", btab(), "0;"])), r("suffix", px_suffix(), "PTX"), r("global_max", ushow(px_gmax()), "2147483647,65535,65535"), r("local_max", ushow(px_lmax()), "1024,1024,64"), r("shared_max", U32.show(px_smax()), "49152"), r("kernel_prefix.lines", U32.show(px_prefix_lines()), "4"), r("kernel_prefix[0]", px_pline(0), ".version VERSION"), r("kernel_prefix[1]", px_pline(1), ".target TARGET"), r("kernel_prefix[2]", px_pline(2), ".address_size 64"), r("kernel_prefix[3]", px_pline(3), ".visible .entry")])



# `Renderer.supported_dtypes` (__init__.py:85) is
# `set(dtypes.all) - ({double} if long is emulated else set())`, which is
# `renderer/__init__.bend`'s row and depends on `EMULATED_DTYPES`. What is
# PORTED here is the PTX OVERRIDE (ptx.py:230-231) over the SCALAR dtypes, and
# the base is named as a PROJECTION rather than silently narrowed:
#   TODO(p3) ptx.py:230  supported_dtypes' BASE set -- `dtypes.all` minus an
#                        emulated long; owned by renderer/__init__.bend:85
def px_base_dtypes() -> List<&2, S.Dt>:
  [S.boolean(), S.int8(), S.int16(), S.int32(), S.int64(), S.uint8(), S.uint16(), S.uint32(),
   S.uint64(), S.half(), S.bfloat16(), S.single(), S.double()]

# `(d != dtypes.half or int(self.target.arch[3:]) >= 53) and d not in
# dtypes.fp8s+(dtypes.bfloat16,)`. bfloat16 IS in the projected base so that
# clause bites; the fp8 clause does not, because the projection has no fp8.
def sd_keep(+ver: U32, +dt: S.Dt) -> Bool:
  Bool.and(Bool.or(Bool.not(O.eq_dt(dt, S.half())), U32.is_ge(ver, 53)), Bool.not(O.eq_dt(dt, S.bfloat16())))

# A KEEP-FILTER. The recursion is called ONCE, through the `+rest` binder, and
# the head is put in FRONT with `List.append(..., [d], rest)` -- which is
# `[d] ++ rest`, not `rest ++ [d]`, and the difference is the whole set's order.
# The tempting one-liner `Bool.pick(c, f(t), d <> f(t))` calls the recursion
# TWICE, and a self-call SPENDS the list it walks (rules 2 and 7-DUP): the first
# call's answer came back EMPTY and all three rows printed `[__bf16]`.
def sd12.go(+ver: U32, +acc: List<&2, S.Dt>, +ds: List<&2, S.Dt>) -> List<&2, S.Dt>:
  match ds:
    case Nil{}   : acc
    case d <> +t :
      +rest = sd12.go(ver, acc, t)
      Bool.pick(List<&2, S.Dt>, sd_keep(ver, d), List.append(&2, S.Dt, [d], rest), rest)

def supported_dtypes(+ver: U32) -> List<&2, S.Dt>: sd12.go(ver, Nil{}, px_base_dtypes())

# `",".join(sorted(d.name ...))` -- `supported_dtypes` returns a SET, which has
# no order, so the gate sorts the names. `List.sort` needs the comparison as a
# function VALUE, which rule 31 says is a def reference (not a closure).
def str_le(a: String, b: String) -> Bool: String.is_le(a, b)

def sorted_names(+ns: List<&2, String>) -> String: String.join(List.sort(String, str_le, ns), ",")

# the same sort over DTYPES, via their names -- a `Map` cannot be keyed by a
# record in Bend and `List.sort` needs a `Data` element with an order, so the
# names are sorted and the gate prints them.
def dt_name_list(+ds: List<&2, S.Dt>) -> List<&2, String>:
  match ds:
    case Nil{}   : Nil{}
    case d <> +t : dt_name(d) <> dt_name_list(t)

def sorted_dt_names(+ds: List<&2, S.Dt>) -> String:
  String.join(List.sort(String, str_le, dt_name_list(ds)), ",")


# `supported_dtypes`: PTXRenderer's override drops the eight fp8 dtypes and bfloat16
# whatever the arch, and half only below sm_53 -- so sm_53, sm_75 and sm_80 print
# the SAME set, and having all three rows is what says so.
def r_sd(+ver: U32, py: String) -> String:
  r("supported_dtypes sm_" ++ U32.show(ver), sorted_dt_names(supported_dtypes(ver)), py)

# `self.tensor_cores = [x for x in tc.get_cuda(arch) if x.dtype_in in (dtypes.half,
# dtypes.float)]` -- ptx.py:146. The filter is on `dtype_in`, NOT `dtype_out`, so
# an fp8 table drops out entirely and a half->half table stays.
def dsh_half.keep(+t: Tc) -> Bool: Bool.or(O.eq_dt(Tc.di(t), S.half()), O.eq_dt(Tc.di(t), S.single()))

# The comprehension keeps `get_cuda`'s order, so the head goes in FRONT of the
# tail's answer -- `List.append(..., [t], rest)` is `[t] ++ rest`. The version
# that appended at the END printed all five entries BACKWARDS, and the version
# that called the recursion twice inside the `Bool.pick` printed one entry.
def dsh_half.go(+ts: List<&2, Tc>, +acc: List<&2, Tc>) -> List<&2, Tc>:
  match ts:
    case Nil{}   : acc
    case t <> +r :
      +rest = dsh_half.go(r, acc)
      Bool.pick(List<&2, Tc>, dsh_half.keep(t), List.append(&2, Tc, [t], rest), rest)

def ptx_tensor_cores(+ver: U32) -> List<&2, Tc>: dsh_half.go(get_cuda(ver), Nil{})

def r_tc_arch(+ver: U32, py: String) -> String:
  r("PTX tensor_cores sm_" ++ U32.show(ver), tc_pairs(ptx_tensor_cores(ver)), py)




def r_ptx_sds() -> String:
  String.concat([r_sd(75, "bool,double,float,half,int,long,short,signed char,unsigned char,unsigned int,unsigned long,unsigned short"), r_sd(53, "bool,double,float,half,int,long,short,signed char,unsigned char,unsigned int,unsigned long,unsigned short"), r_sd(80, "bool,double,float,half,int,long,short,signed char,unsigned char,unsigned int,unsigned long,unsigned short")])

def r_ptx_tcs() -> String:
  String.concat([r_tc_arch(75, "half->float,half->half"), r_tc_arch(80, "half->float,half->half,half->float,half->half,float->float"), r_tc_arch(89, "half->float,half->half,half->float,half->half,float->float")])

# THE ROW ORDER IS THE ORACLE'S, group for group, because the gate is a byte
# diff and a diff is positional. `ptx_matcher rules`, `asm_for_op` (dtype rows
# then WHERE's three forms), `asm_for_op` again over the real names, the half
# tuples, `modifier`, `render_val`, the three tables, the constants, then
# `supported_dtypes` and `tensor_cores`.

# ===========================================================================
# THE ESCAPE, because `PTXRenderer.barrier` contains a real TAB
# ("bar.sync\t0;") and `render_kernel` contains real NEWLINES, and neither is
# visible in a one-line row. CPython's `repr` escapes them and the oracle escapes
# them, so the Bend side escapes them the same way -- which also means a DROPPED
# tab is a diff rather than a shorter line.
# ===========================================================================





# ===========================================================================
# `fmt` -- ptx.py:164.
#
#     def fmt(line): return line if line[0]=="$" else "\t" + line.replace(" ", "\t" if len(line.split(" ")[0]) > 7 else "\t\t", 1)
#
# `$` lines are INLINED ASM and pass through untouched; everything else is
# indented by a TAB and its FIRST space becomes ONE TAB (mnemonic longer than
# seven characters) or TWO. The `1` on `replace` is load-bearing: without it
# EVERY space in the line would become a tab.
# ===========================================================================
def fmt_israw(+line: String) -> Bool: String.eq(String.take(line, 1n), "$")

# `line.split(" ")[0]` -- the mnemonic, i.e. everything before the first space.
def fmt_head(+cs: List<&2, Char>, +acc: List<&2, Char>) -> List<&2, Char>:
  match cs:
    case Nil{}   : acc
    case +c <> +t : Bool.pick(List<&2, Char>, U32.is_eq(Char.to_u32(c), 32), acc,
      List.concat(&2, Char, [acc, [c], fmt_head(t, acc)]))

def fmt_head_str(+line: String) -> String: String.from_list(fmt_head(String.to_list(line), Nil{}))

def fmt_wide(+line: String) -> Bool: U32.is_gt(U32.from_nat(String.length(fmt_head_str(line))), 7)

# `line.replace(" ", rep, 1)`
def fmt_rep(+cs: List<&2, Char>, +rep: String, +acc: List<&2, Char>) -> List<&2, Char>:
  match cs:
    case Nil{}   : acc
    case +c <> +t : Bool.pick(List<&2, Char>, U32.is_eq(Char.to_u32(c), 32),
      List.concat(&2, Char, [acc, String.to_list(rep), t]),
      List.concat(&2, Char, [acc, [c], fmt_rep(t, rep, acc)]))

def tab2() -> String: String.concat([tab(), tab()])

def fmt_rep_of(+line: String) -> String: Bool.pick(String, fmt_wide(line), tab(), tab2())

def fmt(+line: String) -> String:
  Bool.pick(String, fmt_israw(line), line, String.concat([tab(), String.from_list(fmt_rep(String.to_list(line), fmt_rep_of(line), Nil{}))]))

# ===========================================================================
# `render_wmma(ctx, wmma)` -- ptx.py:61-76. THE `mma.sync` SPELLING, and the
# only place in this file where the ACCUMULATOR layout is named in text.
#
#   for src, regs in zip(wmma.src, ctx.wmma_r):
#     for i, reg in enumerate(regs):
#       if (elems_per_reg := 4 // src.dtype.itemsize) == 1: yield f"mov.b32 {reg}, {ctx.r[src][i]};"
#       else: yield f"mov.b32 {reg}, {{{', '.join(ctx.r[src][i*e:(i+1)*e])}}};"
#   dt_map_in, dt_map_out = {float: "tf32", half: "f16"}, {float: "f32", half: "f16"}
#   yield f'mma.sync.aligned.m{M}n{N}k{K}.row.col.{dt_map_out[dtype_out]}.{dt_map_in[dtype_in]}.{dt_map_in[dtype_in]}.{dt_map_out[dtype_out]}{" "*12}' + ...
#   for i, reg in enumerate(ctx.wmma_r[2]): ... unpack ...
#
# The accumulator is C's dtype and the two inputs are `dtype_in`, so the C pack
# line uses `epr(dtype_out)` and the C unpack line uses it too -- getting that
# wrong changes the number of registers, not the text, which is why the gate
# runs FOUR fixtures: half/float, half/half, float/float and a one-element pack.
# ===========================================================================
def dtmap_in(dt: S.Dt) -> String: Bool.pick(String, O.eq_dt(dt, S.single()), "tf32", "f16")

def dtmap_out(dt: S.Dt) -> String: Bool.pick(String, O.eq_dt(dt, S.single()), "f32", "f16")

# `ctx.wmma_r` (the pack registers) and `ctx.r[src]` (the value registers) of A,
# B, C and the OUTPUT. Seven lists, seven readers, because `ctx.r[u]` is
# `str | list[str]` and a `Data` record may not hold a `Maybe`.
type Wmr is Data:
  Wmr{ra: List<&2, String>, rb: List<&2, String>, rc: List<&2, String>, wa: List<&2, String>, wb: List<&2, String>, wc: List<&2, String>, ro: List<&2, String>}

def Wmr.ra(w: Wmr) -> List<&2, String>:
  match w:
    case Wmr{ra, rb, rc, wa, wb, wc, ro}: ra

def Wmr.rb(w: Wmr) -> List<&2, String>:
  match w:
    case Wmr{ra, rb, rc, wa, wb, wc, ro}: rb

def Wmr.rc(w: Wmr) -> List<&2, String>:
  match w:
    case Wmr{ra, rb, rc, wa, wb, wc, ro}: rc

def Wmr.wa(w: Wmr) -> List<&2, String>:
  match w:
    case Wmr{ra, rb, rc, wa, wb, wc, ro}: wa

def Wmr.wb(w: Wmr) -> List<&2, String>:
  match w:
    case Wmr{ra, rb, rc, wa, wb, wc, ro}: wb

def Wmr.wc(w: Wmr) -> List<&2, String>:
  match w:
    case Wmr{ra, rb, rc, wa, wb, wc, ro}: wc

def Wmr.ro(w: Wmr) -> List<&2, String>:
  match w:
    case Wmr{ra, rb, rc, wa, wb, wc, ro}: ro

# `4 // dtype.itemsize` -- how many elements ride in ONE 32-bit register. `1` for
# fp32/tf32 and `2` for half and fp8, and the `== 1` test is what chooses between
# the bare register name and the `{a, b}` pair in BOTH the pack and unpack lines.
def epr(+dt: S.Dt) -> U32: U32.div(4, S.Dt.itemsize(dt))

def at(+xs: List<&2, String>, +i: U32) -> String: Maybe.default(&2, String, List.get(&2, String, xs, U32.to_nat(i)), "")

# `', '.join(regs[i*e:(i+1)*e])` with `e == 2`, the only packed case. It is a
# SLICE, and Python's slice CLAMPS at the end of the list -- the `a1` fixture has
# one value register and asks for `[0:2]`, so it joins ONE name. Reading two
# fixed indices instead joined a `""` for the missing one and printed
# `{%va0, }`, which is a register list with a hole in it.
def slice2(+xs: List<&2, String>, +i: U32) -> String:
  String.join(List.take(&2, String, List.drop(&2, String, xs, U32.to_nat(U32.mul(i, 2))), 2n), ", ")

def pack_line(+one: Bool, +reg: String, +regs: List<&2, String>, +i: U32) -> String:
  Bool.pick(String, one, String.concat(["mov.b32 ", reg, ", ", at(regs, i), ";"]),
    String.concat(["mov.b32 ", reg, ", {", slice2(regs, i), "};"]))

def unpack_line(+one: Bool, +reg: String, +regs: List<&2, String>, +i: U32) -> String:
  Bool.pick(String, one, String.concat(["mov.b32 ", at(regs, i), ", ", reg, ";"]),
    String.concat(["mov.b32 {", slice2(regs, i), "}, ", reg, ";"]))

# `for i, reg in enumerate(regs)` over the PACK registers, appending in order.
def pack_all(+regs: List<&2, String>, +ws: List<&2, String>, +one: Bool, +acc: List<&2, String>) -> List<&2, String>:
  match ws:
    case Nil{}   : acc
    case w <> +t : pack_all(regs, t, one, List.append(&2, String, acc, [pack_line(one, w, regs, U32.from_nat(List.length(&2, String, acc)))]))

def unpack_all(+regs: List<&2, String>, +ws: List<&2, String>, +one: Bool, +acc: List<&2, String>) -> List<&2, String>:
  match ws:
    case Nil{}   : acc
    case w <> +t : unpack_all(regs, t, one, List.append(&2, String, acc, [unpack_line(one, w, regs, U32.from_nat(List.length(&2, String, acc)))]))

def j(+xs: List<&2, String>) -> String: String.join(xs, ", ")

def sp12() -> String: String.repeat(" ", 12n)

# THE SPELLING. `{acc}, {a}, {b}, {acc}` -- the accumulator is passed TWICE, once
# in and once out, and `dtmap_in` appears twice and `dtmap_out` twice, so the
# string is `out.in.in.out` with TWELVE SPACES after it.
def mma_line(n: U32, m: U32, k: U32, +di: S.Dt, +dou: S.Dt, +w: Wmr) -> String:
  String.concat(["mma.sync.aligned.m", U32.show(m), "n", U32.show(n), "k", U32.show(k), ".row.col.",
    dtmap_out(dou), ".", dtmap_in(di), ".", dtmap_in(di), ".", dtmap_out(dou), sp12(),
    "{", j(Wmr.wc(w)), "}, {", j(Wmr.wa(w)), "}, {", j(Wmr.wb(w)), "}, {", j(Wmr.wc(w)), "};"])

# `list(render_wmma(ctx, wmma))` -- three pack groups, the one `mma.sync` line,
# then the unpack, in Python's order.
def render_wmma(n: U32, m: U32, k: U32, +di: S.Dt, +dou: S.Dt, +w: Wmr) -> List<&2, String>:
  +o1 = U32.is_eq(epr(di), 1)
  +o2 = U32.is_eq(epr(dou), 1)
  List.concat(&2, String, [pack_all(Wmr.ra(w), Wmr.wa(w), o1, Nil{}), pack_all(Wmr.rb(w), Wmr.wb(w), o1, Nil{}),
    pack_all(Wmr.rc(w), Wmr.wc(w), o2, Nil{}), [mma_line(n, m, k, di, dou, w)], unpack_all(Wmr.ro(w), Wmr.wc(w), o2, Nil{})])

# ===========================================================================
# `render_kernel` -- ptx.py:163-169. THE HEADER, one row per emitted line.
#
#     kernel = '\n'.join(map(fmt, [f".reg .{reg.split('_')[-2]} %{reg}<{cnt}>;" for reg,cnt in regs] + kernel + ["ret;"]))
#     local_dims = [u.src[0] for u in uops if u.op is Ops.SPECIAL and u.arg[0] == "l"]
#     launch_bounds = prod([d.vmax for d in local_dims])
#     params = ',\n\t'.join([f".param .{'u64' if u.addrspace is GLOBAL else types[u.dtype]} {name}" for name,u in bufs])
#     return f"{kernel_prefix.format(launch_bounds=lb)} {function_name} (\n\t{params}\n)\n.maxntid {lb}\n{{\n{kernel}\n}}"
#
# The BODY is `fmt` over the kernel lines plus the `.reg` declarations and the
# trailing `ret;`, and that is STAGE 3 -- it needs the `render` naming walk. What
# is here is the header, and the gate runs it with the body spelled `BODY` so a
# dropped LINE is a moved row rather than a re-wrapped string.
#
# `launch_bounds = prod([d.vmax for d in local_dims])` reads each local
# dimension's bound off the SPECIAL's src, which is the naming walk's fold and so
# is stage 3 as well; the header takes the product as a PARAMETER here.
# ===========================================================================
# `.param .{'u64' if u.addrspace is GLOBAL else types[u.dtype]} {name}` -- a
# GLOBAL buffer is a 64-bit pointer whatever its dtype, and a non-GLOBAL one is
# the dtype's PTX name. `is_glob` is the Bool, because `S.Addr` would drag the
# whole address-space enum in to read one bit of it.
type Pr is Data:
  Pr{nm: String, is_glob: Bool, dt: S.Dt}

def Pr.text(p: Pr) -> String:
  match p:
    case Pr{nm, is_glob, dt}: String.concat([".param .", Bool.pick(String, is_glob, "u64", types_of(dt)), " ", nm])

# lines 0..3 -- the prefix's four lines, with `.visible .entry` taking the NAME
def rk_head(nm: String) -> List<&2, String>:
  [px_p0(), px_p1(), px_p2(), String.concat([px_p3(), " ", nm, " ("])]

# One line per `.param`, each carrying the leading TAB that the template puts
# before `params` and the `'\n\t'` that `','.join` puts after every COMMA. The
# comma rides at the END of every line but the last, so a dropped comma is a
# diff on that line and a dropped TAB is a diff on every line.
def rk_param_lines(+ps: List<&2, Pr>, acc: List<&2, String>) -> List<&2, String>:
  match ps:
    case Nil{}   : acc
    case p <> +t : rk_param_lines(t, List.append(&2, String, acc, [String.concat([tab(), Pr.text(p),
      Bool.pick(String, List.is_empty(&2, Pr, t), "", ",")])]))

# `)`, `.maxntid lb`, `{`, the body, `}`
def rk_close(lb: U32, +body: List<&2, String>) -> List<&2, String>:
  List.concat(&2, String, [[")"], [String.concat([".maxntid ", U32.show(lb)])], ["{"], body, ["}"]])

def rk_lines(nm: String, lb: U32, +ps: List<&2, Pr>, +body: List<&2, String>) -> List<&2, String>:
  List.concat(&2, String, [rk_head(nm), rk_param_lines(ps, Nil{}), rk_close(lb, body)])


# `render_wmma` -- the four fixtures the oracle runs. Each names (N,M,K), the two
# dtypes and the seven register lists; the three cover `epr == 1` (fp32),
# `epr == 2` (half) and a ONE-ELEMENT pack, which is the case where the
# `{a, b}` branch would index past the end.
def w_a4() -> Wmr: Wmr{["%va0", "%va1", "%va2", "%va3"], ["%vb0", "%vb1", "%vb2", "%vb3"], ["%wc0", "%wc1"], ["%wi0_0", "%wi0_2"], ["%wi1_0", "%wi1_2"], ["%wi2_0", "%wi2_1"], ["%vo0", "%vo1"]}
def w_a1() -> Wmr: Wmr{["%va0"], ["%vb0"], ["%wc0", "%wc1"], ["%wi0_0"], ["%wi1_0"], ["%wi2_0", "%wi2_1"], ["%vo0", "%vo1"]}
def w_a2() -> Wmr: Wmr{["%va0", "%va1"], ["%vb0", "%vb1"], ["%wc0"], ["%wi0_0"], ["%wi1_0"], ["%wi2_0"], ["%vo0", "%vo1"]}
def w_a3() -> Wmr: Wmr{["%va0", "%va1"], ["%vb0", "%vb1"], ["%wc0", "%wc1"], ["%wi0_0", "%wi0_1"], ["%wi1_0", "%wi1_1"], ["%wi2_0", "%wi2_1"], ["%vo0", "%vo1"]}

def r_wm1(+nm: String, n: U32, m: U32, k: U32, +di: S.Dt, +dou: S.Dt, +w: Wmr, py: String) -> String:
  r("render_wmma " ++ nm, String.join(render_wmma(n, m, k, di, dou, w), " ;; "), py)

def r_wms() -> String:
  String.concat([r_wm1("a4", 16, 8, 16, S.half(), S.single(), w_a4(), "mov.b32 %wi0_0, {%va0, %va1}; ;; mov.b32 %wi0_2, {%va2, %va3}; ;; mov.b32 %wi1_0, {%vb0, %vb1}; ;; mov.b32 %wi1_2, {%vb2, %vb3}; ;; mov.b32 %wi2_0, %wc0; ;; mov.b32 %wi2_1, %wc1; ;; mma.sync.aligned.m8n16k16.row.col.f32.f16.f16.f32            {%wi2_0, %wi2_1}, {%wi0_0, %wi0_2}, {%wi1_0, %wi1_2}, {%wi2_0, %wi2_1}; ;; mov.b32 %vo0, %wi2_0; ;; mov.b32 %vo1, %wi2_1;"), r_wm1("a1", 16, 8, 16, S.half(), S.single(), w_a1(), "mov.b32 %wi0_0, {%va0}; ;; mov.b32 %wi1_0, {%vb0}; ;; mov.b32 %wi2_0, %wc0; ;; mov.b32 %wi2_1, %wc1; ;; mma.sync.aligned.m8n16k16.row.col.f32.f16.f16.f32            {%wi2_0, %wi2_1}, {%wi0_0}, {%wi1_0}, {%wi2_0, %wi2_1}; ;; mov.b32 %vo0, %wi2_0; ;; mov.b32 %vo1, %wi2_1;"), r_wm1("a2", 8, 8, 8, S.half(), S.half(), w_a2(), "mov.b32 %wi0_0, {%va0, %va1}; ;; mov.b32 %wi1_0, {%vb0, %vb1}; ;; mov.b32 %wi2_0, {%wc0}; ;; mma.sync.aligned.m8n8k8.row.col.f16.f16.f16.f16            {%wi2_0}, {%wi0_0}, {%wi1_0}, {%wi2_0}; ;; mov.b32 {%vo0, %vo1}, %wi2_0;"), r_wm1("a3", 8, 8, 8, S.single(), S.single(), w_a3(), "mov.b32 %wi0_0, %va0; ;; mov.b32 %wi0_1, %va1; ;; mov.b32 %wi1_0, %vb0; ;; mov.b32 %wi1_1, %vb1; ;; mov.b32 %wi2_0, %wc0; ;; mov.b32 %wi2_1, %wc1; ;; mma.sync.aligned.m8n8k8.row.col.f32.tf32.tf32.f32            {%wi2_0, %wi2_1}, {%wi0_0, %wi0_1}, {%wi1_0, %wi1_1}, {%wi2_0, %wi2_1}; ;; mov.b32 %vo0, %wi2_0; ;; mov.b32 %vo1, %wi2_1;")])

# the `dt_map`s on their own, over all four dtype pairs, because they are the
# ONLY place `render_wmma` reads a dtype for a NAME and the four map rows are
# what a `tf32`/`f16` mix-up moves.
def dtmap_name(+di: S.Dt, +dou: S.Dt) -> String:
  String.concat([dtmap_out(dou), ".", dtmap_in(di), ".", dtmap_in(di), ".", dtmap_out(dou)])

def r_dtm1(+nm: String, +di: S.Dt, +dou: S.Dt, py: String) -> String:
  r("wmma dtmap " ++ nm, dtmap_name(di, dou), py)


def r_dtms() -> String:
  String.concat([r_dtm1("half,half", S.half(), S.half(), "f16.f16.f16.f16"), r_dtm1("half,float", S.half(), S.single(), "f32.f16.f16.f32"), r_dtm1("float,half", S.single(), S.half(), "f16.tf32.tf32.f16"), r_dtm1("float,float", S.single(), S.single(), "f32.tf32.tf32.f32")])

# `fmt` -- the FIVE line shapes: an INLINED `$` line passes through untouched, a
# SHORT mnemonic gets TWO tabs for its first space, a LONG one (> 7 chars) gets
# ONE, and a line with NO space at all gets none. `ret;` is a row twice because
# the oracle's fixture list has it twice, and a gate that only runs the distinct
# shapes would not notice a row that moved.
def r_fmt1(+line: String, py: String) -> String:
  r(String.concat(["fmt ", q(line)]), q(fmt(line)), py)

def r_fmts() -> String:
  String.concat([r_fmt1("mov.b32 %r0, %r1;", String.concat(["'", btab(), "mov.b32", btab(), btab(), "%r0, %r1;'"])), r_fmt1("ret;", String.concat(["'", btab(), "ret;'"])), r_fmt1("$LDG.E R1, [R2];", String.concat(["'", "$LDG.E R1, [R2];'"])), r_fmt1("shl.b32", String.concat(["'", btab(), "shl.b32'"])), r_fmt1("ret;", String.concat(["'", btab(), "ret;'"]))])

# `render_kernel` -- the header, ONE ROW PER EMITTED LINE plus a count, with the
# body spelled `BODY`. The `.reg` declarations and the trailing `ret;` are the
# naming walk's, and they are STAGE 3. A dropped LINE is a moved row rather than
# a re-wrapped string, which is the whole reason the count row exists: without
# it, losing line 5 and gaining line 9 is invisible to a per-line diff.
def rk1.go(+nm: String, +ls: List<&2, String>, +i: U32, acc: String) -> String:
  match ls:
    case Nil{}   : acc
    case l <> +t : rk1.go(nm, t, U32.add(i, 1), String.concat([acc,
      r(String.concat(["render_kernel ", nm, "[", U32.show(i), "]"]), esc(l), esc(l))]))

def rk1(+nm: String, +ls: List<&2, String>, cnt: String) -> String:
  String.concat([r(String.concat(["render_kernel ", nm, ".lines"]), U32.show(U32.from_nat(List.length(&2, String, ls))), cnt),
    rk1.go(nm, ls, 0, "")])

# The TWO fixtures the oracle runs: one GLOBAL float plus one LOCAL int32 at
# 128 threads, and one GLOBAL uint32 at 256. Together they cover both branches
# of `Pr.text` (`u64` and `types_of`) and both param-line shapes (a COMMA after
# the first param and none after the last).
# data1 is a LOCAL float, not an int32: `types[int32]` and a hard-coded
# `"s32"` agree, so an int32 fixture cannot tell `types[u.dtype]` from a
# literal. A float spells `.param .f32` and only the dtype table can say so.
def k1_ps() -> List<&2, Pr>: [Pr{"data0", True{}, S.single()}, Pr{"data1", False{}, S.single()}]
def k2_ps() -> List<&2, Pr>: [Pr{"data0", True{}, S.uint32()}]

def r_rks() -> String:
  String.concat([rk1("k1", rk_lines("k1", 128, k1_ps(), ["BODY"]), "11"), rk1("k2", rk_lines("k2", 256, k2_ps(), ["BODY"]), "10")])

def r_stage2() -> String:
  String.concat([r_pmx_n(), r_asms(), r_where(), r_asm2s(), r_sh(), r_mods(), r_rvs(), r_tabs(),
    r_tabs_miss(), r_mc_tabs(), r_consts(), r_ptx_sds(), r_ptx_tcs(), r_wms(), r_dtms(), r_rks(), r_fmts()])

# ONE print for the WHOLE table, so `IO.print`'s own newline is the only frame and
# the oracle's single trailing `"\n"` is its match. There is deliberately no
# separator between the two stages: the oracle's `rows()` is a plain
# concatenation, so a `nl()` here would be a line CPython never printed.
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat([r_stage1(), r_stage2()]))

# ===========================================================================
# THE MUTATION TABLE. Measured 2026-10-02 with
# `.agents/slop/tcptx-mutate.py`: one textual edit at a time, each row diffed
# against the unmutated 620. "moved" is the number of rows that changed; the
# driver prints which. Four edits move nothing and that is the point of them.
#
#   M1  the coord packing is (bit << 1) | axis, not << 2      259
#   M2  axis code k = 3, not 2                                 16
#   M3  `used` concatenates B's blocks, not C's                  8
#   M4  `threads` reads frag_a[0]                              0  <-- BLIND
#   M4b `threads` reads frag_c[1]                               8
#   M5  `frag_coords`' accumulator starts at 1, not 0           24
#   M6  the coord shift uses the AXIS, not the BIT              24
#   M7  (CONTROL: a comment-only edit)                          0
#   M8  `mma`'s fragment_c lane ends at m3, not m2              28
#   M9  FNV-1a's offset basis is off by one                     24
#   M10 `pow2` shifts by n+1                                   259
#   M11 `supports_half` ends in SHR, not TRUNC                   2
#   M12 `supports_half`'s tuple is in dict order                 1
#   M13 `doesnt_support_half` appends instead of consing          1
#   M14 `tensor_cores` appends instead of consing                 3
#   M15 `supported_dtypes` appends instead of consing             0  <-- BLIND
#   M16 the `not in fp8s + (bf16,)` clause is dropped            3
#   M17 the `arch >= 53` clause is dropped                        3
#   M18 `tensor_cores` filters on dtype_OUT                      2
#   M19 `modifier`'s first clause widens to int->bool            5
#   M20 `modifier`'s second clause loses `or b == bool`          3
#   M21 `shl.b{name}` -- the `[1:]` is dropped                   17
#   M22 `xor.b{name}` -- the `[1:]` is dropped                   15
#   M23 `selp.{name}` -- PTX has no `selp.f16`                    2
#   M24 MUL's `.lo` is not integer-only                          2
#   M25 CMPNE's `neu`/`ne` arms are swapped                      5
#   M26 MULACC picks on is_int, not is_float                     15
#   M27 TRUNC's second type name is a literal `"s32"`            11
#   M28 (CONTROL: a comment-only edit)                            0
#   M29 `render_val`'s two float spellings are swapped            8
#   M30 (CONTROL: a comment-only edit)                            0
#   M31 `hex4` takes nibbles 7..4, not 3..0                       3
#   M32 `epr` is 2 // itemsize, not 4                            4
#   M33 the pack join is "," not ", "                            2
#   M34 `fmt`'s one-tab/two-tab arms are swapped                  1
#   M35 the mnemonic threshold is `>= 7`, not `> 7`              1
#   M36 a `$` line is indented anyway                             1
#   M37 `fmt` replaces EVERY space, not the first                 1
#   M38 a non-GLOBAL `.param` name is a literal `"s32"`           1
#   M39 the function name is not after `.visible .entry`          2
#   M40 `render_kernel` drops the closing `}`                    17  -2 lines
#   M41 the k1 LOCAL buffer is a double, not a float              1
#   M42 the body is emitted after the close, not inside           8
#   M43 `btab()` returns a real tab, not `\` + `t`                8
#   M44 `q()` quotes with brackets, not apostrophes               5
#   M45 the mma separator is eleven spaces, not twelve            4
#   M46 the accumulator is passed once, not twice                 4
#   M47 `dt_map_out[float]` is "tf32", not "f32"                  5
#   M48 the archs are 53, 75, 80 -- not 75, 53, 80               2
#   M49 the dtype tables are in sorted order, not dict order       1
#   M50 (CONTROL: a comment-only edit)                            0
#
# WHAT THE TABLE SAYS.
#
# M4 IS A BLIND SPOT NO FIXTURE CAN CLOSE, and it is not a fixture gap. tc.py:43
# ASSERTS `len(f[0]) == len(self.frag_c[0])` for all three fragments, so A, B
# and C have the same LANE COUNT in every legal TensorCore and `threads`' three
# candidate readers are the same function. M4b is the control that proves the
# row is not simply insensitive: it reads `frag_c[1]`, whose length the
# assertion does NOT pin, and it moves all eight `threads` rows. So the row is
# live and the ambiguity is upstream's, and the honest record is that
# `Tc.threads` could read `lb` and this gate would not know.
#
# M15 IS A BLIND SPOT BY CONSTRUCTION. `PTXRenderer.supported_dtypes` returns a
# SET (ptx.py:230), and a set has no order in CPython, so the gate SORTS the
# names before printing them -- which means a filter that conses and a filter
# that appends are indistinguishable. M14 is the same question on a value
# CPython DOES order, and it moves three rows. The difference between M14 and
# M15 is the whole subject of this file: a gate is only as sharp as the ORDER
# the oracle can observe, and `set` is a place where it cannot.
#
# M3 WAS ALSO A BLIND SPOT, and it is now closed. `Tc.used` feeds only
# `axis_coords`, which reads a MAX per axis -- and `__post_init__` forces A to
# cover every m and k coord and C to cover every n coord, so `A + C` and `A + B`
# have the same three maxima for EVERY legal tensor core. Swapping C for B
# moved nothing until the `used` row was added: the concatenation's own string
# differs even though everything computed from it agrees. A rule whose OUTPUT is
# an intermediate needs a row on the intermediate.
#
# M43 IS WHY THE GATE IS A BYTE DIFF. A `py=` half that held a real TAB instead
# of `\` + `t` renders identically in a terminal and differs in the file, and it
# is the only mutation here that a human reading both lanes side by side would
# call green.
#
# M27 AND M38 ARE WHY A FIXTURE IS NOT ENOUGH. M27 (`TRUNC`'s second type name)
# moved NOTHING while every one of the 105 `asm` rows said `cvt.rzi.s32.s32`:
# the 105-row grid fixes `name` at "s32" to isolate the DTYPE branch, so the
# NAME branch of a four-argument lambda was ungated. Adding TRUNC to the
# twelve-dtype name grid moved it to 11. M38 is the same shape: the k1 fixture's
# non-GLOBAL buffer was an int32, and `types[int32] == "s32"`, so a hard-coded
# `"s32"` was indistinguishable from the dtype table. It is a LOCAL FLOAT now.
#
# M1 AND M10 MOVE 259 ROWS EACH and neither is interesting on its own -- both
# reach every coord and every count. They are in the table because a table that
# only lists interesting mutations cannot tell a reader which rules are
# load-bearing for the WHOLE file.
#
# FOUR CONTROLS, M7, M28, M30 and M50, are whitespace-only edits, and each
# moves nothing. They are what makes the other forty-six numbers mean something:
# a harness that reports "0 rows" for everything would look identical on the
# four blind spots.
# ===========================================================================
