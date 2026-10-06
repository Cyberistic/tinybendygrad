# renderer/tc.bend -- port of tinygrad/renderer/tc.py
#
# ONE BEND FILE PER UPSTREAM .py, AT THE SAME PATH. This was `renderer/tc_ptx.bend`,
# which held `tc.py` (141 lines) AND `ptx.py`; the 1:1 ruling separates them, and
# `renderer/tc_ptx.bend` is now the thinner half that CONSUMES this one. Nothing in
# `renderer/ptx.bend` needs repointing: it imports `tc_ptx.bend as P` and that file
# stays, with `import ./tc.bend as T` added.
#
# tc.py is the tensor-core TABLE: the `TensorCore` dataclass, the six quantities
# derived from it in `__post_init__` (`dims`, `used`, `base_upcast_axes`, `relabel`,
# `frag_coords`, `threads`), and the fourteen per-arch `TensorCore` values. Every one
# of those is a PURE FUNCTION of its eleven fields, which is why this half can be
# gated against CPython with no GPU, no driver and no codegen cache in the way -- 267
# of the 620 rows.
#
# THE MUTATION TABLE for tc.py's own rules (M1-M18) is in this file; the ptx.py half
# (M19-M50) is in `tc_ptx.bend`'s tail.
#
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
# `TensorCore` -- tc.py:138-11. FIVE FIELDS, SEVEN `U32` LISTS, because a
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
    r1(nm, "di", dt_name(Tc.di(t)), "f16"),
    r1(nm, "do", dt_name(Tc.dou(t)), "f32"),
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
    r1(nm, "di", dt_name(Tc.di(t)), "fp8e4m3"),
    r1(nm, "do", dt_name(Tc.dou(t)), "f32"),
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
    r1(nm, "di", dt_name(Tc.di(t)), "f16"),
    r1(nm, "do", dt_name(Tc.dou(t)), "f32"),
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
    r1(nm, "di", dt_name(Tc.di(t)), "f32"),
    r1(nm, "do", dt_name(Tc.dou(t)), "f32"),
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
    r1(nm, "di", dt_name(Tc.di(t)), "f16"),
    r1(nm, "do", dt_name(Tc.dou(t)), "f32"),
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
    r1(nm, "di", dt_name(Tc.di(t)), "f16"),
    r1(nm, "do", dt_name(Tc.dou(t)), "f32"),
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
    r1(nm, "di", dt_name(Tc.di(t)), "fp8e5m2"),
    r1(nm, "do", dt_name(Tc.dou(t)), "f32"),
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
    r1(nm, "di", dt_name(Tc.di(t)), "f32"),
    r1(nm, "do", dt_name(Tc.dou(t)), "f32"),
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

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(r_stage1())

#   M3  `used` concatenates B's blocks, not C's                  8
#   M4  `threads` reads frag_a[0]                              0  <-- BLIND
#   M4b `threads` reads frag_c[1]                               8
#   M5  `frag_coords`' accumulator starts at 1, not 0           24
#   M10 `pow2` shifts by n+1                                   259
#   M11 `supports_half` ends in SHR, not TRUNC                   2
#   M12 `supports_half`'s tuple is in dict order                 1
#   M13 `doesnt_support_half` appends instead of consing          1
#   M14 `tensor_cores` appends instead of consing                 3
#   M15 `supported_dtypes` appends instead of consing             0  <-- BLIND
#   M18 `tensor_cores` filters on dtype_OUT                      2
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
# M3 WAS ALSO A BLIND SPOT, and it is now closed. `Tc.used` feeds only
# `axis_coords`, which reads a MAX per axis -- and `__post_init__` forces A to
# cover every m and k coord and C to cover every n coord, so `A + C` and `A + B`
# have the same three maxima for EVERY legal tensor core. Swapping C for B
# moved nothing until the `used` row was added: the concatenation's own string
# differs even though everything computed from it agrees. A rule whose OUTPUT is
# an intermediate needs a row on the intermediate.
#