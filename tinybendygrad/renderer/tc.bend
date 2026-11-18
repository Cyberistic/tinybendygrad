# renderer/tc.bend -- the tensor-core TABLE from `tinygrad/renderer/tc.py` AT THE
# PIN `5c2bf39d6c4b` (149 LINES).  IT IS THE `TensorCore` DATACLASS (FIVE
# fields, tc.py:6-14), THE SIX QUANTITIES DERIVED FROM IT (`axis_coords`,
# `relabel`, `frag_coords`, `dims`, `threads`, `base_upcast_axes`), AND THE
# SIXTEEN per-arch `TensorCore` VALUES.  Every one of those is a PURE FUNCTION
# of those five fields, which is why this half can be gated against CPython
# with no GPU, no driver and no codegen cache in the way -- 289 of the 623 rows.

import Base
import ./../LAWS/spec.bend as S
import ./../uop/ops.bend as O

# THE GATE PRIMITIVES. `r` IS wgsl.bend's ROW BUILDER: A ROW IS A VALUE HERE,
# SO A GROUP OF THEM IS A `String` AND THE WHOLE GATE IS ONE PRINT.  `r` TAKES
# THE `py=` HALF AS AN ARGUMENT BECAUSE `tc_ptx.bend` CALLS IT TOO.  IN THIS
# FILE EVERY `py=` ARGUMENT IS DERIVED.

def r(+nm: String, +got: String, +want: String) -> String:
  String.concat([nm, " = [", got, "]   py=[", want, "]\n"])

def bs(+x: Bool) -> String: Bool.pick(String, x, "True", "False")

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

# COORDS. tc.py SPELLS A COORDINATE AS THE TWO-CHARACTER STRING "m0" AND READS

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
def cd_keeps(+ax: U32, +cs: List<&2, U32>) -> List<&2, U32>:
  match cs:
    case Nil{}   : Nil{}
    case c <> +t : Bool.pick(List<&2, U32>, U32.is_eq(cd_ax(c), ax), List.append(&2, U32, [c], cd_keeps(ax, t)), cd_keeps(ax, t))

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

# COORD LITERALS. Every coordinate in every table tc.py writes by hand, so they
# are defs rather than inline `cd(3, 1)` calls: `cd(3, 1)` is `mk(3)`.

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

# `TensorCore` -- tc.py:6-14. FIVE FIELDS, SEVEN `U32` LISTS, because a
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

def Tc.alla(+t: Tc) -> List<&2, U32>: cc2(Tc.la(t), Tc.ea(t))
def Tc.allb(+t: Tc) -> List<&2, U32>: cc2(Tc.lb(t), Tc.eb(t))
def Tc.allc(+t: Tc) -> List<&2, U32>: cc2(Tc.lc(t), Tc.ec(t))

# `f[1] + f[0]` -- ELEMENT bits then LANE bits. `__post_init__`'s A/B k check
# reads this order, and `relabel` reads `f[0] + f[1]`, so the two concatenations
# are both spelled and neither is derived from the other.
def Tc.ealla(+t: Tc) -> List<&2, U32>: cc2(Tc.ea(t), Tc.la(t))
def Tc.eallb(+t: Tc) -> List<&2, U32>: cc2(Tc.eb(t), Tc.lb(t))

# :12 `axis_coords` -- "tile bit of each tc axis in creation order, n then m

def Tc.used(+t: Tc) -> List<&2, U32>: cc4(Tc.la(t), Tc.ea(t), Tc.lc(t), Tc.ec(t))

def Tc.axis_coords(+t: Tc) -> List<&2, U32>:
  +u = Tc.used(t)
  cc3(ur0(U32.to_nat(cd_cnt(u, AX_N())), AX_N()), ur0(U32.to_nat(cd_cnt(u, AX_M())), AX_M()), ur0(U32.to_nat(cd_cnt(u, AX_K())), AX_K()))

# :33 `base_upcast_axes` -- "element slots, most significant bit first: upcast

def Tc.bu(+t: Tc) -> List<&2, U32>:
  List.reverse(&2, U32, cc2(cd_keeps(AX_K(), Tc.axis_coords(t)), Tc.ec(t)))

# :29 `dims` -- `n, m, k = (sum(c[0]==d for c in axis_coords) for d in "nmk")`
# then `(2n, 2m, 2k)`, the tile's N, M, K. Three defs, not one returning
# a triple: Bend has no tuple and no `Data` record may hold a `Maybe`, and a
# three-field record here would need three more reader defs for one call site.

def Tc.dims_n(+t: Tc) -> U32: pow2(cd_cnt(Tc.axis_coords(t), AX_N()))
def Tc.dims_m(+t: Tc) -> U32: pow2(cd_cnt(Tc.axis_coords(t), AX_M()))
def Tc.dims_k(+t: Tc) -> U32: pow2(cd_cnt(Tc.axis_coords(t), AX_K()))

def Tc.dims(+t: Tc) -> String: String.join([U32.show(Tc.dims_n(t)), U32.show(Tc.dims_m(t)), U32.show(Tc.dims_k(t))], ",")

# :32 `threads` -- `2len(self.frag_c[0])`: "threads that construct the warp".
def Tc.threads(+t: Tc) -> U32: pow2(ln(Tc.lc(t)))

# :16 `relabel` -- "tc axis -> fragment slot axis, per operand":

type Kv is Data:
  Kv{ks: List<&2, U32>, vs: List<&2, U32>}

def Kv.ks(k: Kv) -> List<&2, U32>:
  match k:
    case Kv{ks, vs}: ks

def Kv.vs(k: Kv) -> List<&2, U32>:
  match k:
    case Kv{ks, vs}: vs

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

# `"{c}={y}"` PER PAIR, IN KEY ORDER, COMMA-JOINED.  `Kv.join` DESTRUCTURES AND
# HANDS THE TWO LISTS TO `kv_join`, BECAUSE A TWO-SCRUTINEE `match` CANNOT
# SCRUTINIZE TWO CALLS (CONVENTION 4), AND `kv_join` CONSES AND REVERSES
# BECAUSE `zip` WALKS TWO LISTS THAT COME OUT OF ONE DESTRUCTURING AND SO SHARE
# ONE BINDER.
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

def fc_lanes(k: Nat, +n: U32, +elems: Nat, +la: List<&2, U32>, +ea: List<&2, U32>, +ax0: U32, +ax1: U32) -> List<&2, String>:
  match k:
    case 0n : Nil{}
    case 1n+m:
      xs = fc_lanes(m, U32.add(n, 1), elems, la, ea, ax0, ax1)
      List.append(&2, String, [String.join(fc_lane.elems(elems, 0, n, la, ea, ax0, ax1), ",")], xs)

def fc_str(lanes: Nat, elems: Nat, +la: List<&2, U32>, +ea: List<&2, U32>, ax0: U32, ax1: U32) -> String:
  String.join(fc_lanes(lanes, 0, elems, la, ea, ax0, ax1), ",")

# THE FNV-1a DIGEST, because `frag_coords`'s OWN STRING IS 22 647 CHARACTERS AT

def fnv.go(+s: String, h: U32) -> U32:
  match s:
    case SNil{}     : h
    case SCon{c, t} : fnv.go(t, U32.mul(U32.xor(h, Char.to_u32(c)), 16777619))

def fnv(+s: String) -> U32: fnv.go(s, 2166136261)

def dgst(+s: String) -> String: String.concat(["len=", U32.show(U32.from_nat(String.length(s))), " fnv=", U32.show(fnv(s))])

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
#
# "each own bit appears once, only lane bits may be foreign and k never is"
# -- tc.py:39, upstream's comment ON THE ASSERTION BLOCK, AND IT IS THE
# ONE-LINE VERSION OF THE THREE CLAUSES THAT ARE NOT OBVIOUS:
#   * "EACH OWN BIT APPEARS ONCE." THE `nodup` CLAUSE. A FRAGMENT MAY NOT USE
#     THE SAME TILE BIT TWICE, BECAUSE TWO BITS THAT SELECTED THE SAME BIT
#     OF THE TILE WOULD MAKE THE FRAGMENT'S ADDRESSING AMBIGUOUS -- TWO
#     DIFFERENT LANE INDICES WOULD MAP TO THE SAME TILE COORDINATE.
#   * "ONLY LANE BITS MAY BE FOREIGN." THE `own <= set(f[0]+f[1])` AND
#     `set(f[0]+f[1]) <= own | mn-coords` CLAUSES. A FOREIGN BIT IS ONE THAT
#     IS NOT ON THE OPERAND'S OWN AXES, AND THE ONLY AXES A FOREIGN BIT MAY
#     COME FROM ARE `m` AND `n` -- THE `mn-coords` -- BECAUSE THE `k` AXIS IS
#     SHARED BY A AND B AND A FOREIGN `k` BIT WOULD PUT THE SAME TILE BIT IN
#     TWO DIFFERENT PLACES.
#   * "AND K NEVER IS." THE `k` AXIS IS NEVER FOREIGN. THE PORT SAYS THIS
#     TWICE: `Tc.used` IS A'S LANE + A'S ELEMENT + C'S LANE + C'S ELEMENT
#     AND **NOT** B'S, AND THE REASON IS GIVEN AT `Tc.used` BELOW --
#     "`k` never is a foreign bit and the post-init assertion checks it".
#
# SO THE ASSERTION IS NOT A SANITY CHECK ON THE TABLES; IT IS THE STATEMENT
# OF WHICH BITS MAY BE SHARED, AND IT IS WHY `Tc.used` MAY LEAVE B OUT.
#
# AND THE `own` SET IS `coords` FILTERED TO THE OPERAND'S TWO AXES: FOR A IT
# IS THE `m` AND `k` COORDS, FOR B THE `k` AND `n`, FOR C THE `m` AND `n`.
# WHICH IS WHY `Tc.own` TAKES TWO AXES AND WHY THE PORT'S `cover` TAKES
# `ax0, ax1` RATHER THAN A LETTER.
def mem(+xs: List<&2, U32>, +x: U32) -> Bool:
  match xs:
    case Nil{}   : False{}
    case h <> +t : Bool.or(U32.is_eq(h, x), mem(t, x))

# `set(b) <= set(a)` -- every element of `b` occurs in `a`. THE ARGUMENT ORDER IS
# THE OTHER WAY ROUND from `<=`: `<=` reads `own <= all`, which is `sub(all,
# own)`, and writing `sub(own, all)` inverts the assertion. MEASURED: rdna3's
def sub(+a: List<&2, U32>, +b: List<&2, U32>) -> Bool:
  match b:
    case Nil{}   : True{}
    case h <> +t : Bool.and(mem(a, h), sub(a, t))

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

# :26 `mma` -- NVIDIA `mma.m16n8kK`:
#
#   k, g = [f"k{i}" for i in range(int(math.log2(K)))], int(math.log2(4//di.itemsize))
#   lane, elem = tuple(k[g:g+2]), tuple(k[:g]+k[g+2:])
#   frag_a=(lane+("m0","m1","m2"), elem[:g]+("m3",)+elem[g:]), frag_b=(lane+("n0","n1","n2"), elem),
#   frag_c=(("n1","n2","m0","m1","m2"), ("n0","m3"))
#
# `g` is how many k bits ride in a 32-bit REGISTER (the "2g k in a 32-bit reg"
# the comment names), so it is `log2(4//itemsize)`: half gives g=1, fp8 gives
# g=0. `elem[:g] + ("m3",) + elem[g:]` is where m3 -- "A row+8" -- is spliced
# in, and it is a SPLICE not an append, which is the whole reason a fragment
# shape is not just a suffix of `k`.
#
# THE LANE LIST'S OWN ORDER, WHICH UPSTREAM NAMES AND WHICH IS NOT DERIVABLE
# FROM THE ARITHMETIC: "lane is threadID_in_group (2 k bits) then groupID
# (m0-m2)" -- tc.py:54. THE LANE INDEX IS THE CONCATENATION OF TWO

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

def mfma(+kk: U32, di: S.Dt, dou: S.Dt) -> Tc:
  +ks = ur0(U32.log2(kk), AX_K())
  +kl = U32.log2(U32.div(U32.min(kk, 64), 4))
  +lane = List.take(&2, U32, List.drop(&2, U32, ks, kl), 2n)
  +elem = cc2(List.take(&2, U32, ks, kl), List.drop(&2, U32, ks, Nat.add(kl, 2n)))
  Tc{di, dou, cc2(m0123(), lane), elem, cc2(n0123(), lane), elem, cd6(nk(0), nk(1), nk(2), nk(3), mk(2), mk(3)), cd2(mk(0), mk(1))}

# THE TABLES. tc.py:50-149, in Python's order, each a `List<&2, Tc>`. The

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
#
# SEVEN (di,do) PAIRS, NOT FOUR. tc.py:78-81 builds one TensorCore per pair:
def rdna4_of(di: S.Dt, dou: S.Dt) -> Tc:
  Tc{di, dou, cd5(m0(), m1(), m2(), m3(), kkb(2)), cd3(kkb(0), kkb(1), kkb(3)),
    cd5(nk(0), nk(1), nk(2), nk(3), kkb(2)), cd3(kkb(0), kkb(1), kkb(3)), cd5(nk(0), nk(1), nk(2), nk(3), m3()), cd3(m0(), m1(), m2())}

def amd_rdna4() -> List<&2, Tc>:
  [rdna4_of(S.half(), S.single()), rdna4_of(S.half(), S.half()), rdna4_of(S.bfloat16(), S.single()),
   rdna4_of(S.bfloat16(), S.bfloat16()), rdna4_of(S.fp8e4m3(), S.single()), rdna4_of(S.fp8e5m2(), S.single()),
   rdna4_of(S.int8(), S.int32())]

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

def get_cuda(+ver: U32) -> List<&2, Tc>:
  Bool.pick(List<&2, Tc>, U32.is_ge(ver, 89), cuda_sm89(),
    Bool.pick(List<&2, Tc>, U32.is_ge(ver, 80), cuda_sm80(),
      Bool.pick(List<&2, Tc>, U32.is_ge(ver, 75), cuda_sm75(), Nil{})))

# `get_amd(arch)`: `{"gfx942": amd_cdna3, "gfx950": amd_cdna4, "gfx1200":
# amd_rdna4, "gfx1201": amd_rdna4}.get(arch, amd_rdna3)` (tc.py:99) -- the DEFAULT
def get_amd(nm: String) -> List<&2, Tc>:
  match nm:
    case "gfx942" : amd_cdna3()
    case "gfx950" : amd_cdna4()
    case "gfx1200": amd_rdna4()
    case "gfx1201": amd_rdna4()
    case _:        amd_rdna3()

# THE STAGE 1 GATE. 289 rows, every one a STRING beside CPython's own string.
#
#   * 16 tables x (a length row + one row per MEMBER).  The member row is
#     `di->do/N,M,K`, so it pins the table's CONTENTS AND ITS ORDER -- a
#     reversed concatenation moves the rows.
#   * 8 distinct FRAGMENT SHAPES x 25 rows: the five dtype/fragment fields,
#     `axis_coords`, `used`, `base_upcast_axes`, `threads`, `dims`, both
#     `relabel` dicts, all three `frag_coords` (as a digest -- see the note by
#     `dgst`), `__post_init__`'s lane count, its `distinct`/`cover` pair PER
#     OPERAND, and the `ka == kb` A/B-k-agreement check.
#   * 6 `get_cuda` arches and 5 `get_amd` arch names, including the two that
#     take `get_amd`'s DEFAULT arm.
#
# 16 + 62 + 200 + 11 = 289, and MEASURED 2026-10-22 against
def rd(+nm: String, +got: String) -> String: r(nm, got, got)

def r1(+nm: String, +f: String, +got: String) -> String: rd(nm ++ "." ++ f, got)

# `f"tc/{dims}/{dtype_in.name},{dtype_out.name}"` -- the row PREFIX, built by
# the port so a wrong dims or a swapped dtype pair renames its own rows.
def tc_nm(+t: Tc) -> String:
  String.concat(["tc/", Tc.dims(t), "/", dt_name(Tc.di(t)), ",", dt_name(Tc.dou(t))])

def tc_pair(+t: Tc) -> String: String.concat([dt_name(Tc.di(t)), "->", dt_name(Tc.dou(t)), "/", Tc.dims(t)])

def tln(ts: List<&2, Tc>) -> String: U32.show(U32.from_nat(List.length(&2, Tc, ts)))

def tc_pairs(+ts: List<&2, Tc>) -> String:
  match ts:
    case Nil{}   : ""
    case h <> +t : String.concat([dt_name(Tc.di(h)), "->", dt_name(Tc.dou(h)), Bool.pick(String, List.is_empty(&2, Tc, t), "", ","), tc_pairs(t)])

# ONE def for every table's member rows. The `py=` half is the member's OWN
# rendering, so the walk carries no second list: the table is the ONLY copy of
# the (di,do) pairs, and a pair that moves moves both halves of its row.
def r_tcs(+ts: List<&2, Tc>, +i: U32, +nm: String) -> String:
  match ts:
    case Nil{}   : ""
    case h <> +t :
      +p = tc_pair(h)
      rest = r_tcs(t, U32.add(i, 1), nm)
      String.concat([rd("tc." ++ nm ++ "[" ++ U32.show(i) ++ "]", p), rest])
def cuda_81616_rows() -> String: r_tcs(cuda_81616(), 0, "cuda_81616")

def r_tbl_cuda_81616() -> String: String.concat([rd("tc.cuda_81616.len", tln(cuda_81616())), cuda_81616_rows()])
def cuda_81632_f8_rows() -> String: r_tcs(cuda_81632_f8(), 0, "cuda_81632_f8")
def cuda_8168_f16_rows() -> String: r_tcs(cuda_8168_f16(), 0, "cuda_8168_f16")
def cuda_8168_tf32_rows() -> String: r_tcs(cuda_8168_tf32(), 0, "cuda_8168_tf32")
def cuda_sm75_rows() -> String: r_tcs(cuda_sm75(), 0, "cuda_sm75")
def cuda_sm80_rows() -> String: r_tcs(cuda_sm80(), 0, "cuda_sm80")
def cuda_sm89_rows() -> String: r_tcs(cuda_sm89(), 0, "cuda_sm89")
def amd_rdna3_rows() -> String: r_tcs(amd_rdna3(), 0, "amd_rdna3")
def amd_rdna4_rows() -> String: r_tcs(amd_rdna4(), 0, "amd_rdna4")
def amd_cdna_161616_rows() -> String: r_tcs(amd_cdna_161616(), 0, "amd_cdna_161616")
def amd_cdna_161632_rows() -> String: r_tcs(amd_cdna_161632(), 0, "amd_cdna_161632")
def amd_cdna_1616128_rows() -> String: r_tcs(amd_cdna_1616128(), 0, "amd_cdna_1616128")
def amd_cdna3_161632_rows() -> String: r_tcs(amd_cdna3_161632(), 0, "amd_cdna3_161632")
def amd_cdna3_rows() -> String: r_tcs(amd_cdna3(), 0, "amd_cdna3")
def amd_cdna4_rows() -> String: r_tcs(amd_cdna4(), 0, "amd_cdna4")
def metal_rows() -> String: r_tcs(metal(), 0, "metal")
def r_tbl_cuda_81632_f8() -> String: String.concat([rd("tc.cuda_81632_f8.len", tln(cuda_81632_f8())), cuda_81632_f8_rows()])
def r_tbl_cuda_8168_f16() -> String: String.concat([rd("tc.cuda_8168_f16.len", tln(cuda_8168_f16())), cuda_8168_f16_rows()])
def r_tbl_cuda_8168_tf32() -> String: String.concat([rd("tc.cuda_8168_tf32.len", tln(cuda_8168_tf32())), cuda_8168_tf32_rows()])
def r_tbl_cuda_sm75() -> String: String.concat([rd("tc.cuda_sm75.len", tln(cuda_sm75())), cuda_sm75_rows()])
def r_tbl_cuda_sm80() -> String: String.concat([rd("tc.cuda_sm80.len", tln(cuda_sm80())), cuda_sm80_rows()])
def r_tbl_cuda_sm89() -> String: String.concat([rd("tc.cuda_sm89.len", tln(cuda_sm89())), cuda_sm89_rows()])
def r_tbl_amd_rdna3() -> String: String.concat([rd("tc.amd_rdna3.len", tln(amd_rdna3())), amd_rdna3_rows()])
def r_tbl_amd_rdna4() -> String: String.concat([rd("tc.amd_rdna4.len", tln(amd_rdna4())), amd_rdna4_rows()])
def r_tbl_amd_cdna_161616() -> String: String.concat([rd("tc.amd_cdna_161616.len", tln(amd_cdna_161616())), amd_cdna_161616_rows()])
def r_tbl_amd_cdna_161632() -> String: String.concat([rd("tc.amd_cdna_161632.len", tln(amd_cdna_161632())), amd_cdna_161632_rows()])
def r_tbl_amd_cdna_1616128() -> String: String.concat([rd("tc.amd_cdna_1616128.len", tln(amd_cdna_1616128())), amd_cdna_1616128_rows()])
def r_tbl_amd_cdna3_161632() -> String: String.concat([rd("tc.amd_cdna3_161632.len", tln(amd_cdna3_161632())), amd_cdna3_161632_rows()])
def r_tbl_amd_cdna3() -> String: String.concat([rd("tc.amd_cdna3.len", tln(amd_cdna3())), amd_cdna3_rows()])
def r_tbl_amd_cdna4() -> String: String.concat([rd("tc.amd_cdna4.len", tln(amd_cdna4())), amd_cdna4_rows()])
def r_tbl_metal() -> String: String.concat([rd("tc.metal.len", tln(metal())), metal_rows()])

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
    r1(nm, "di", dt_name(Tc.di(t)))
    r1(nm, "do", dt_name(Tc.dou(t)))
    r1(nm, "frag_a", cd_join(Tc.alla(t)))
    r1(nm, "frag_b", cd_join(Tc.allb(t)))
    r1(nm, "frag_c", cd_join(Tc.allc(t)))
    r1(nm, "axis_coords", cd_join(Tc.axis_coords(t)))
    # `axis_coords`'s INTERMEDIATE on its own row. It is UNOBSERVABLE through
    r1(nm, "used", cd_join(Tc.used(t)))
    r1(nm, "base_upcast_axes", cd_join(Tc.bu(t)))
    r1(nm, "threads", U32.show(Tc.threads(t)))
    r1(nm, "dims", Tc.dims(t))
    r1(nm, "relabel.0", Tc.relabel.a(t))
    r1(nm, "relabel.1", Tc.relabel.b(t))
    r1(nm, "frag_coords.0", dgst(fc_of.of(0, t)))
    r1(nm, "frag_coords.1", dgst(fc_of.of(1, t)))
    r1(nm, "frag_coords.2", dgst(fc_of.of(2, t)))
    r1(nm, "lanes", Tc.lanes(t))
    r1(nm, "distinct.mk", bs(Tc.distinct(t, Tc.la(t), Tc.ea(t))))
    r1(nm, "cover.mk", bs(Tc.cover(t, Tc.la(t), Tc.ea(t), 1, 2)))
    r1(nm, "distinct.kn", bs(Tc.distinct(t, Tc.lb(t), Tc.eb(t))))
    r1(nm, "cover.kn", bs(Tc.cover(t, Tc.lb(t), Tc.eb(t), 2, 0)))
    r1(nm, "distinct.mn", bs(Tc.distinct(t, Tc.lc(t), Tc.ec(t))))
    r1(nm, "cover.mn", bs(Tc.cover(t, Tc.lc(t), Tc.ec(t), 1, 0)))
    r1(nm, "ka", cd_join(Tc.kab_a(t)))
    r1(nm, "kb", cd_join(Tc.kab_b(t)))
    r1(nm, "kab_eq", bs(Tc.kab_eq(t)))
  ])

def ts0() -> Tc: mma(16, S.half(), S.single())

def r_tcd1(+t: Tc) -> String:
  +nm = tc_nm(t)
  String.concat([
    r1(nm, "di", dt_name(Tc.di(t)))
    r1(nm, "do", dt_name(Tc.dou(t)))
    r1(nm, "frag_a", cd_join(Tc.alla(t)))
    r1(nm, "frag_b", cd_join(Tc.allb(t)))
    r1(nm, "frag_c", cd_join(Tc.allc(t)))
    r1(nm, "axis_coords", cd_join(Tc.axis_coords(t)))
    r1(nm, "used", cd_join(Tc.used(t)))
    r1(nm, "base_upcast_axes", cd_join(Tc.bu(t)))
    r1(nm, "threads", U32.show(Tc.threads(t)))
    r1(nm, "dims", Tc.dims(t))
    r1(nm, "relabel.0", Tc.relabel.a(t))
    r1(nm, "relabel.1", Tc.relabel.b(t))
    r1(nm, "frag_coords.0", dgst(fc_of.of(0, t)))
    r1(nm, "frag_coords.1", dgst(fc_of.of(1, t)))
    r1(nm, "frag_coords.2", dgst(fc_of.of(2, t)))
    r1(nm, "lanes", Tc.lanes(t))
    r1(nm, "distinct.mk", bs(Tc.distinct(t, Tc.la(t), Tc.ea(t))))
    r1(nm, "cover.mk", bs(Tc.cover(t, Tc.la(t), Tc.ea(t), 1, 2)))
    r1(nm, "distinct.kn", bs(Tc.distinct(t, Tc.lb(t), Tc.eb(t))))
    r1(nm, "cover.kn", bs(Tc.cover(t, Tc.lb(t), Tc.eb(t), 2, 0)))
    r1(nm, "distinct.mn", bs(Tc.distinct(t, Tc.lc(t), Tc.ec(t))))
    r1(nm, "cover.mn", bs(Tc.cover(t, Tc.lc(t), Tc.ec(t), 1, 0)))
    r1(nm, "ka", cd_join(Tc.kab_a(t)))
    r1(nm, "kb", cd_join(Tc.kab_b(t)))
    r1(nm, "kab_eq", bs(Tc.kab_eq(t)))
  ])

def ts1() -> Tc: mma(32, S.fp8e4m3(), S.single())

def r_tcd2(+t: Tc) -> String:
  +nm = tc_nm(t)
  String.concat([
    r1(nm, "di", dt_name(Tc.di(t)))
    r1(nm, "do", dt_name(Tc.dou(t)))
    r1(nm, "frag_a", cd_join(Tc.alla(t)))
    r1(nm, "frag_b", cd_join(Tc.allb(t)))
    r1(nm, "frag_c", cd_join(Tc.allc(t)))
    r1(nm, "axis_coords", cd_join(Tc.axis_coords(t)))
    r1(nm, "used", cd_join(Tc.used(t)))
    r1(nm, "base_upcast_axes", cd_join(Tc.bu(t)))
    r1(nm, "threads", U32.show(Tc.threads(t)))
    r1(nm, "dims", Tc.dims(t))
    r1(nm, "relabel.0", Tc.relabel.a(t))
    r1(nm, "relabel.1", Tc.relabel.b(t))
    r1(nm, "frag_coords.0", dgst(fc_of.of(0, t)))
    r1(nm, "frag_coords.1", dgst(fc_of.of(1, t)))
    r1(nm, "frag_coords.2", dgst(fc_of.of(2, t)))
    r1(nm, "lanes", Tc.lanes(t))
    r1(nm, "distinct.mk", bs(Tc.distinct(t, Tc.la(t), Tc.ea(t))))
    r1(nm, "cover.mk", bs(Tc.cover(t, Tc.la(t), Tc.ea(t), 1, 2)))
    r1(nm, "distinct.kn", bs(Tc.distinct(t, Tc.lb(t), Tc.eb(t))))
    r1(nm, "cover.kn", bs(Tc.cover(t, Tc.lb(t), Tc.eb(t), 2, 0)))
    r1(nm, "distinct.mn", bs(Tc.distinct(t, Tc.lc(t), Tc.ec(t))))
    r1(nm, "cover.mn", bs(Tc.cover(t, Tc.lc(t), Tc.ec(t), 1, 0)))
    r1(nm, "ka", cd_join(Tc.kab_a(t)))
    r1(nm, "kb", cd_join(Tc.kab_b(t)))
    r1(nm, "kab_eq", bs(Tc.kab_eq(t)))
  ])

def ts2() -> Tc: mma(8, S.half(), S.single())

def r_tcd3(+t: Tc) -> String:
  +nm = tc_nm(t)
  String.concat([
    r1(nm, "di", dt_name(Tc.di(t)))
    r1(nm, "do", dt_name(Tc.dou(t)))
    r1(nm, "frag_a", cd_join(Tc.alla(t)))
    r1(nm, "frag_b", cd_join(Tc.allb(t)))
    r1(nm, "frag_c", cd_join(Tc.allc(t)))
    r1(nm, "axis_coords", cd_join(Tc.axis_coords(t)))
    r1(nm, "used", cd_join(Tc.used(t)))
    r1(nm, "base_upcast_axes", cd_join(Tc.bu(t)))
    r1(nm, "threads", U32.show(Tc.threads(t)))
    r1(nm, "dims", Tc.dims(t))
    r1(nm, "relabel.0", Tc.relabel.a(t))
    r1(nm, "relabel.1", Tc.relabel.b(t))
    r1(nm, "frag_coords.0", dgst(fc_of.of(0, t)))
    r1(nm, "frag_coords.1", dgst(fc_of.of(1, t)))
    r1(nm, "frag_coords.2", dgst(fc_of.of(2, t)))
    r1(nm, "lanes", Tc.lanes(t))
    r1(nm, "distinct.mk", bs(Tc.distinct(t, Tc.la(t), Tc.ea(t))))
    r1(nm, "cover.mk", bs(Tc.cover(t, Tc.la(t), Tc.ea(t), 1, 2)))
    r1(nm, "distinct.kn", bs(Tc.distinct(t, Tc.lb(t), Tc.eb(t))))
    r1(nm, "cover.kn", bs(Tc.cover(t, Tc.lb(t), Tc.eb(t), 2, 0)))
    r1(nm, "distinct.mn", bs(Tc.distinct(t, Tc.lc(t), Tc.ec(t))))
    r1(nm, "cover.mn", bs(Tc.cover(t, Tc.lc(t), Tc.ec(t), 1, 0)))
    r1(nm, "ka", cd_join(Tc.kab_a(t)))
    r1(nm, "kb", cd_join(Tc.kab_b(t)))
    r1(nm, "kab_eq", bs(Tc.kab_eq(t)))
  ])

def ts3() -> Tc: mma(8, S.single(), S.single())

def r_tcd4(+t: Tc) -> String:
  +nm = tc_nm(t)
  String.concat([
    r1(nm, "di", dt_name(Tc.di(t)))
    r1(nm, "do", dt_name(Tc.dou(t)))
    r1(nm, "frag_a", cd_join(Tc.alla(t)))
    r1(nm, "frag_b", cd_join(Tc.allb(t)))
    r1(nm, "frag_c", cd_join(Tc.allc(t)))
    r1(nm, "axis_coords", cd_join(Tc.axis_coords(t)))
    r1(nm, "used", cd_join(Tc.used(t)))
    r1(nm, "base_upcast_axes", cd_join(Tc.bu(t)))
    r1(nm, "threads", U32.show(Tc.threads(t)))
    r1(nm, "dims", Tc.dims(t))
    r1(nm, "relabel.0", Tc.relabel.a(t))
    r1(nm, "relabel.1", Tc.relabel.b(t))
    r1(nm, "frag_coords.0", dgst(fc_of.of(0, t)))
    r1(nm, "frag_coords.1", dgst(fc_of.of(1, t)))
    r1(nm, "frag_coords.2", dgst(fc_of.of(2, t)))
    r1(nm, "lanes", Tc.lanes(t))
    r1(nm, "distinct.mk", bs(Tc.distinct(t, Tc.la(t), Tc.ea(t))))
    r1(nm, "cover.mk", bs(Tc.cover(t, Tc.la(t), Tc.ea(t), 1, 2)))
    r1(nm, "distinct.kn", bs(Tc.distinct(t, Tc.lb(t), Tc.eb(t))))
    r1(nm, "cover.kn", bs(Tc.cover(t, Tc.lb(t), Tc.eb(t), 2, 0)))
    r1(nm, "distinct.mn", bs(Tc.distinct(t, Tc.lc(t), Tc.ec(t))))
    r1(nm, "cover.mn", bs(Tc.cover(t, Tc.lc(t), Tc.ec(t), 1, 0)))
    r1(nm, "ka", cd_join(Tc.kab_a(t)))
    r1(nm, "kb", cd_join(Tc.kab_b(t)))
    r1(nm, "kab_eq", bs(Tc.kab_eq(t)))
  ])

def ts4() -> Tc: rdna3_of(S.half(), S.single())

def r_tcd5(+t: Tc) -> String:
  +nm = tc_nm(t)
  String.concat([
    r1(nm, "di", dt_name(Tc.di(t)))
    r1(nm, "do", dt_name(Tc.dou(t)))
    r1(nm, "frag_a", cd_join(Tc.alla(t)))
    r1(nm, "frag_b", cd_join(Tc.allb(t)))
    r1(nm, "frag_c", cd_join(Tc.allc(t)))
    r1(nm, "axis_coords", cd_join(Tc.axis_coords(t)))
    r1(nm, "used", cd_join(Tc.used(t)))
    r1(nm, "base_upcast_axes", cd_join(Tc.bu(t)))
    r1(nm, "threads", U32.show(Tc.threads(t)))
    r1(nm, "dims", Tc.dims(t))
    r1(nm, "relabel.0", Tc.relabel.a(t))
    r1(nm, "relabel.1", Tc.relabel.b(t))
    r1(nm, "frag_coords.0", dgst(fc_of.of(0, t)))
    r1(nm, "frag_coords.1", dgst(fc_of.of(1, t)))
    r1(nm, "frag_coords.2", dgst(fc_of.of(2, t)))
    r1(nm, "lanes", Tc.lanes(t))
    r1(nm, "distinct.mk", bs(Tc.distinct(t, Tc.la(t), Tc.ea(t))))
    r1(nm, "cover.mk", bs(Tc.cover(t, Tc.la(t), Tc.ea(t), 1, 2)))
    r1(nm, "distinct.kn", bs(Tc.distinct(t, Tc.lb(t), Tc.eb(t))))
    r1(nm, "cover.kn", bs(Tc.cover(t, Tc.lb(t), Tc.eb(t), 2, 0)))
    r1(nm, "distinct.mn", bs(Tc.distinct(t, Tc.lc(t), Tc.ec(t))))
    r1(nm, "cover.mn", bs(Tc.cover(t, Tc.lc(t), Tc.ec(t), 1, 0)))
    r1(nm, "ka", cd_join(Tc.kab_a(t)))
    r1(nm, "kb", cd_join(Tc.kab_b(t)))
    r1(nm, "kab_eq", bs(Tc.kab_eq(t)))
  ])

def ts5() -> Tc: rdna4_of(S.half(), S.single())

def r_tcd6(+t: Tc) -> String:
  +nm = tc_nm(t)
  String.concat([
    r1(nm, "di", dt_name(Tc.di(t)))
    r1(nm, "do", dt_name(Tc.dou(t)))
    r1(nm, "frag_a", cd_join(Tc.alla(t)))
    r1(nm, "frag_b", cd_join(Tc.allb(t)))
    r1(nm, "frag_c", cd_join(Tc.allc(t)))
    r1(nm, "axis_coords", cd_join(Tc.axis_coords(t)))
    r1(nm, "used", cd_join(Tc.used(t)))
    r1(nm, "base_upcast_axes", cd_join(Tc.bu(t)))
    r1(nm, "threads", U32.show(Tc.threads(t)))
    r1(nm, "dims", Tc.dims(t))
    r1(nm, "relabel.0", Tc.relabel.a(t))
    r1(nm, "relabel.1", Tc.relabel.b(t))
    r1(nm, "frag_coords.0", dgst(fc_of.of(0, t)))
    r1(nm, "frag_coords.1", dgst(fc_of.of(1, t)))
    r1(nm, "frag_coords.2", dgst(fc_of.of(2, t)))
    r1(nm, "lanes", Tc.lanes(t))
    r1(nm, "distinct.mk", bs(Tc.distinct(t, Tc.la(t), Tc.ea(t))))
    r1(nm, "cover.mk", bs(Tc.cover(t, Tc.la(t), Tc.ea(t), 1, 2)))
    r1(nm, "distinct.kn", bs(Tc.distinct(t, Tc.lb(t), Tc.eb(t))))
    r1(nm, "cover.kn", bs(Tc.cover(t, Tc.lb(t), Tc.eb(t), 2, 0)))
    r1(nm, "distinct.mn", bs(Tc.distinct(t, Tc.lc(t), Tc.ec(t))))
    r1(nm, "cover.mn", bs(Tc.cover(t, Tc.lc(t), Tc.ec(t), 1, 0)))
    r1(nm, "ka", cd_join(Tc.kab_a(t)))
    r1(nm, "kb", cd_join(Tc.kab_b(t)))
    r1(nm, "kab_eq", bs(Tc.kab_eq(t)))
  ])

def ts6() -> Tc: mfma(128, S.fp8e5m2(), S.single())

def r_tcd7(+t: Tc) -> String:
  +nm = tc_nm(t)
  String.concat([
    r1(nm, "di", dt_name(Tc.di(t)))
    r1(nm, "do", dt_name(Tc.dou(t)))
    r1(nm, "frag_a", cd_join(Tc.alla(t)))
    r1(nm, "frag_b", cd_join(Tc.allb(t)))
    r1(nm, "frag_c", cd_join(Tc.allc(t)))
    r1(nm, "axis_coords", cd_join(Tc.axis_coords(t)))
    r1(nm, "used", cd_join(Tc.used(t)))
    r1(nm, "base_upcast_axes", cd_join(Tc.bu(t)))
    r1(nm, "threads", U32.show(Tc.threads(t)))
    r1(nm, "dims", Tc.dims(t))
    r1(nm, "relabel.0", Tc.relabel.a(t))
    r1(nm, "relabel.1", Tc.relabel.b(t))
    r1(nm, "frag_coords.0", dgst(fc_of.of(0, t)))
    r1(nm, "frag_coords.1", dgst(fc_of.of(1, t)))
    r1(nm, "frag_coords.2", dgst(fc_of.of(2, t)))
    r1(nm, "lanes", Tc.lanes(t))
    r1(nm, "distinct.mk", bs(Tc.distinct(t, Tc.la(t), Tc.ea(t))))
    r1(nm, "cover.mk", bs(Tc.cover(t, Tc.la(t), Tc.ea(t), 1, 2)))
    r1(nm, "distinct.kn", bs(Tc.distinct(t, Tc.lb(t), Tc.eb(t))))
    r1(nm, "cover.kn", bs(Tc.cover(t, Tc.lb(t), Tc.eb(t), 2, 0)))
    r1(nm, "distinct.mn", bs(Tc.distinct(t, Tc.lc(t), Tc.ec(t))))
    r1(nm, "cover.mn", bs(Tc.cover(t, Tc.lc(t), Tc.ec(t), 1, 0)))
    r1(nm, "ka", cd_join(Tc.kab_a(t)))
    r1(nm, "kb", cd_join(Tc.kab_b(t)))
    r1(nm, "kab_eq", bs(Tc.kab_eq(t)))
  ])

def ts7() -> Tc: metal_of(S.single(), S.single())

def r_tcds() -> String:
  String.concat([r_tcd0(ts0()), r_tcd1(ts1()), r_tcd2(ts2()), r_tcd3(ts3()), r_tcd4(ts4()), r_tcd5(ts5()), r_tcd6(ts6()), r_tcd7(ts7())])

def r_gc_75() -> String: rd("get_cuda sm_75", tc_pairs(get_cuda(75)))
def r_gc_80() -> String: rd("get_cuda sm_80", tc_pairs(get_cuda(80)))
def r_gc_86() -> String: rd("get_cuda sm_86", tc_pairs(get_cuda(86)))
def r_gc_89() -> String: rd("get_cuda sm_89", tc_pairs(get_cuda(89)))
def r_gc_90() -> String: rd("get_cuda sm_90", tc_pairs(get_cuda(90)))
def r_gc_100() -> String: rd("get_cuda sm_100", tc_pairs(get_cuda(100)))
def r_ga_gfx942() -> String: rd("get_amd gfx942", tc_pairs(get_amd("gfx942")))
def r_ga_gfx950() -> String: rd("get_amd gfx950", tc_pairs(get_amd("gfx950")))
def r_ga_gfx1200() -> String: rd("get_amd gfx1200", tc_pairs(get_amd("gfx1200")))
def r_ga_gfx1201() -> String: rd("get_amd gfx1201", tc_pairs(get_amd("gfx1201")))
def r_ga_gfx1100() -> String: rd("get_amd gfx1100", tc_pairs(get_amd("gfx1100")))

def r_stage1() -> String:
  String.concat([r_tbl_cuda_81616(), r_tbl_cuda_81632_f8(), r_tbl_cuda_8168_f16(), r_tbl_cuda_8168_tf32(),
    r_tbl_cuda_sm75(), r_tbl_cuda_sm80(), r_tbl_cuda_sm89(), r_tbl_amd_rdna3(), r_tbl_amd_rdna4(),
    r_tbl_amd_cdna_161616(), r_tbl_amd_cdna_161632(), r_tbl_amd_cdna_1616128(), r_tbl_amd_cdna3_161632(),
    r_tbl_amd_cdna3(), r_tbl_amd_cdna4(), r_tbl_metal(), r_tcds(), r_gc_75(), r_gc_80(), r_gc_86(),
    r_gc_89(), r_gc_90(), r_gc_100(), r_ga_gfx942(), r_ga_gfx950(), r_ga_gfx1200(), r_ga_gfx1201(), r_ga_gfx1100()])

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(r_stage1())

# the mutation table, re-measured 2026-10-22. The number is rows that MOVE in
# the lane of the file that OWNS the def the rule edits, and it is POSITIONAL:
# a `diff` is positional, so a dropped row shifts every row after it. The
# CONTENT column says how many rows actually say something different.
#
#   THE tc.py RULES -- the defs are in THIS file, so the lane is THIS file's
#   290 lines (289 rows and `IO.print`'s framing newline):
#   M1  the coord packing is (bit << 1) | axis, not << 2      262   249 changed
#   M2  axis code k = 3, not 2                                 16    14 changed
#   M3  `used` concatenates B's blocks, not C's                  8     8 changed
#   M4  `threads` reads frag_a[0]                              0  <-- BLIND
#   M4b `threads` reads frag_c[1]                               8     8 changed
#   M5  `frag_coords`' accumulator starts at 1, not 0           24    24 changed
#   M6  the coord shift uses the AXIS, not the BIT              24    24 changed
#   M7  (CONTROL: a comment-only edit)                          0
#   M8  `mma`'s fragment_c lane ends at m3, not m2              28    28 changed
#   M9  FNV-1a's offset basis is off by one                     24    24 changed
#   M10 `pow2` shifts by n+1                                   262   249 changed
#
#   THE ptx.py RULES -- the defs are in `tc_ptx.bend` and the ROWS are that
#   file's, so the lane is `tc_ptx.bend`'s 344 lines. They are recorded HERE
#   because this foot is where the tree has them:
#   M11 `supports_half` ends in SHR, not TRUNC                   2
#   M12 `supports_half`'s tuple is in dict order                 1
#   M13 `doesnt_support_half` appends instead of consing          1
#   M14 `tensor_cores` appends instead of consing                 3
#   M15 `supported_dtypes` appends instead of consing             0  <-- BLIND
#   M18 `tensor_cores` filters on dtype_OUT                      2
#
# two of these numbers moved, and the delta is exactly the three rows
# `amd_rdna4` GAINED: M1 and M10 were 259 and are 262. They were measured
# over a table with FOUR (di,do) pairs; upstream has SEVEN.
#
# and two rules in the tree's own harness could not be applied at all. The
# harness aims every edit at `tc_ptx.bend` and spells the tc.py type as `Tc`,
# which the SPLIT renamed to `T.Tc` -- so M14 and M18 matched NOTHING until
# the qualification was adapted, and M1-M10 (whose defs are in THIS file)
# cannot be applied in `tc_ptx.bend` at all. A rule whose edit does not
# apply is not a measurement.
#
# the plants, and what each one names. a mutation asks what the file's own
# output does; a PLANT asks whether the GATE goes red, and that is the
# question a fix has to answer. Measured 2026-10-22 against
# `gates/tc_ptx_render-oracle.py stage1`:
#
#   P1  `amd_rdna4` loses its last PAIR            RED -- 4 rows of content:
#                                                  `tc.amd_rdna4.len`,
#                                                  `tc.amd_rdna4[6]` (gone),
#                                                  `get_amd gfx1200`,
#                                                  `get_amd gfx1201`
#   P2  a `py=` LITERAL beside a correct table     RED -- 1 row: the row's two
#                                                  halves disagree, `[7]` and
#                                                  `py=[4]`
#   P3  CONTROL: a comment-only edit              GREEN -- 0 rows
#
# P1 IS THE DEFECT THIS FILE HAD, and the four rows it names are exactly the
# four that were wrong. P2 IS THE CLASS PLANTED BACK: a derived `py=` half
# cannot disagree with the row it is in and a literal could -- which is why
# 71 of this file's 286 cells were wrong and the file still agreed with
# itself.
# M4 IS A BLIND SPOT NO FIXTURE CAN CLOSE, and it is not a fixture gap. tc.py:43