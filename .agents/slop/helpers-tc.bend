# helpers-tc.bend -- THE GATE for the helpers.bend defs this port has added so far:
# `trange`, `GlobalCounters`, `Context`, and the 64-bit pair block (`i64_or`,
# `i64_and`, `i64_shl`, `i64_div`, `i64_mod`, `gcd`).
#
#   sh .agents/slop/helpers-tc-gate.sh
#
# Every row is compared against `.agents/slop/helpers-oracle.py`, which CALLS the
# real `tinygrad.helpers` defs. The diff IS the test; no row is typed from memory.
#
# Every def under test is reached THROUGH `H`, i.e. through the real
# tinybendygrad/helpers.bend. That matters: an earlier draft of this file DEFINED the
# three blocks locally and imported helpers.bend only for `Flags`, so it gated a COPY
# and a mutation of helpers.bend moved nothing. This file defines no `Counters`, no
# `Ctx`, no `Tqdm` and no `trange` of its own, and no `I64` arithmetic of its own --
# `rg '^def (trange|Context|GlobalCounters|H.Counters|i64_|gcd)'` over this file must
# find nothing.
import Base
import ./../../tinybendygrad/helpers.bend as H

# ===========================================================================
# the gate
# ===========================================================================

def p(+nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

def pu(+nm: String, n: U32) -> IO(Unit):
  p(nm, U32.show(n))

def row_df(nm: String, f: H.Flags) -> IO(Unit):
  match f:
    case H.Flags{nc, df, di, sd}: p(nm, df)

def row_di(nm: String, f: H.Flags) -> IO(Unit):
  match f:
    case H.Flags{nc, df, di, sd}: p(nm, di)

def row_nc(nm: String, f: H.Flags) -> IO(Unit):
  match f:
    case H.Flags{nc, df, di, sd}: pu(nm, Bool.to_u32(nc))

def join_step(first: Bool, acc: String, x: Nat) -> String:
  match first:
    case True{}: Nat.show(x)
    case False{}: String.append(String.append(acc, ","), Nat.show(x))

def join.go(xs: List<&2, Nat>, first: Bool, acc: String) -> String:
  match xs:
    case Nil{}: acc
    case x <> t: join.go(t, False{}, join_step(first, acc, x))

def key_step(first: Bool, acc: String, x: H.Mupd) -> String:
  match first:
    case True{}: U32.show(H.GlobalCounters.mupd_dev(x))
    case False{}: String.append(String.append(acc, ","), U32.show(H.GlobalCounters.mupd_dev(x)))

def join_key.go(xs: List<&2, H.Mupd>, first: Bool, acc: String) -> String:
  match xs:
    case Nil{}: acc
    case x <> t: join_key.go(t, False{}, key_step(first, acc, x))

def at_n(xs: List<&2, Nat>, n: Nat) -> Maybe<&2, Nat>:
  List.get(&2, Nat, xs, n)



def at_none(z: Bool) -> String:
  match z:
    case True{}: "none"
    case False{}: "0"

def at(z: Bool, m: Maybe<&2, Nat>) -> String:
  match m:
    case Some{x}: Nat.show(x)
    case None{}: at_none(z)

def len_s(+seq: List<&2, Nat>) -> String:
  Nat.show(List.length(&2, Nat, seq))

def first_s(+seq: List<&2, Nat>) -> String:
  at(Nat.is_eq(List.length(&2, Nat, seq), 0n), at_n(seq, 0n))

def last_s(+seq: List<&2, Nat>) -> String:
  at(Nat.is_eq(List.length(&2, Nat, seq), 0n), at_n(seq, Nat.sub(List.length(&2, Nat, seq), 1n)))

def seq_s(seq: List<&2, Nat>) -> String:
  join.go(seq, True{}, "")

def trange_go(+nm: String, tt: U32, a: String, b: String, c: String, d: String) -> IO(Unit):
  do IO<Unit>:
    p(String.concat([nm, "_len"]), a)
    p(String.concat([nm, "_first"]), b)
    p(String.concat([nm, "_last"]), c)
    p(String.concat([nm, "_seq"]), d)
    pu(String.concat([nm, "_t"]), tt)

def trange_rows(nm: String, +t: H.Tqdm) -> IO(Unit):
  match t:
    case H.Tqdm{tt, +seq}: trange_go(nm, tt, len_s(seq), first_s(seq), last_s(seq), seq_s(seq))

def c_devs(c: H.Counters) -> List<&2, H.Mupd>:
  match c:
    case H.Counters{ops, mem, t, k, used, devs}: devs

def keys_tail(z: Bool, xs: List<&2, H.Mupd>) -> String:
  match z:
    case True{}: ""
    case False{}: join_key.go(xs, True{}, "")

def at_dev(xs: List<&2, H.Mupd>, d: U32) -> U32:
  H.GlobalCounters.mupd_get(d, xs)

def gc_rows(+tag: String, +c: H.Counters) -> IO(Unit):
  match c:
    case H.Counters{ops, mem, t, k, used, devs}:
      do IO<Unit>:
        pu(String.concat([tag, "_ops"]), ops)
        pu(String.concat([tag, "_mem"]), mem)
        pu(String.concat([tag, "_kernels"]), k)
        pu(String.concat([tag, "_used"]), used)
        pu(String.concat([tag, "_dev0"]), at_dev(devs, 0))
        pu(String.concat([tag, "_dev3"]), at_dev(devs, 3))


# ONE chain, in the order the oracle ran its blocks, because CPython's counter bag
# is ONE process-global: `gc_init`'s two dev rows are READS of a `defaultdict`, and a
# read of a missing key INSERTS it, so they leave the key set as {0, 3} BEFORE the
# bumps touch device 3. The port models that read as `mem_used_add(c, dev, 0)` --
# adding zero to a missing key inserts it and reads back zero, which is exactly what
# CPython's `__missing__` does -- and the resulting insertion order is gated by
# `gc_default_keys`.
def g0() -> H.Counters: H.GlobalCounters.mem_used_add(H.GlobalCounters.mem_used_add(H.GlobalCounters.init(), 0, 0), 3, 0)
def g1() -> H.Counters: H.GlobalCounters.bump_ops(g0(), 5)
def g2() -> H.Counters: H.GlobalCounters.bump_ops(g1(), 7)
def g3() -> H.Counters: H.GlobalCounters.bump_mem(g2(), 1024)
def g6() -> H.Counters: H.GlobalCounters.bump_kernel(g3())
def g7() -> H.Counters: H.GlobalCounters.bump_kernel(g6())
def g8() -> H.Counters: H.GlobalCounters.bump_kernel(g7())
def g9() -> H.Counters: H.GlobalCounters.bump_mem_used(g8(), 4096)
def ga() -> H.Counters: H.GlobalCounters.mem_used_add(g9(), 3, 11)
def gb() -> H.Counters: H.GlobalCounters.mem_used_add(ga(), 3, 4)
def gc_seq() -> H.Counters: H.GlobalCounters.mem_used_add(gb(), 0, 1)

# --- the Context chain -----------------------------------------------------
#
# ONE chain, in the order the oracle ran its blocks, because upstream's module
# state LEAKS between them: the out-of-order pair leaves DEFAULT_FLOAT at
# "bfloat16" (:178 replays a snapshot, it does not unwind), and the oracle's
# `ctx_disj_*` rows read that leaked value. The port threads the same state.
def keys_rows(+c: H.Counters) -> IO(Unit):
  p("gc_default_keys", keys_tail(Nat.is_eq(List.length(&2, H.Mupd, c_devs(c)), 0n), c_devs(c)))

def r9v() -> H.Counters: H.GlobalCounters.mem_used_add(gc_seq(), 9, 0)

# --- the Context chain -----------------------------------------------------
#
# ONE chain, in the order the oracle ran its blocks, because upstream's module
# state LEAKS between them: the out-of-order pair leaves DEFAULT_FLOAT at
# "bfloat16" (:178 replays a snapshot, it does not unwind), and the oracle's
# `ctx_disj_*` rows read that leaked value. The port threads the same state.
def boot_go(+f: H.Flags) -> IO(Unit):
  do IO<Unit>:
    row_df("ctx_boot_df", f)
    row_di("ctx_boot_di", f)
    row_nc("ctx_boot_nc", f)

def boot_rows() -> IO(Unit):
  do IO<Unit>:
    f : H.Flags <- H.Flags.from_env()
    boot_go(f)

def second(ca: H.Ctx) -> H.Ctx:
  H.Context.__enter__(H.Context.inside(ca), [H.Context.arg("DEFAULT_FLOAT", "float64")])

def one_go(+c: H.Ctx) -> IO(Unit):
  do IO<Unit>:
    row_df("ctx_enter_df", H.Context.inside(c))
    row_di("ctx_enter_di", H.Context.inside(c))
    row_df("ctx_exit_df", H.Context.__exit__(c, H.Context.inside(c)))

def one_rows() -> IO(Unit):
  do IO<Unit>:
    f : H.Flags <- H.Flags.from_env()
    one_go(H.Context.__enter__(f, [H.Context.arg("DEFAULT_FLOAT", "bfloat16")]))

def lifo_go2(+ca: H.Ctx, +cb: H.Ctx) -> IO(Unit):
  do IO<Unit>:
    row_df("ctx_in2_df", H.Context.inside(cb))
    row_df("ctx_lifo_mid_df", H.Context.__exit__(cb, H.Context.inside(cb)))
    row_df("ctx_lifo_df", H.Context.__exit__(ca, H.Context.__exit__(cb, H.Context.inside(cb))))

def lifo_go(+ca: H.Ctx) -> IO(Unit):
  do IO<Unit>:
    lifo_go2(ca, second(ca))

def lifo_rows() -> IO(Unit):
  do IO<Unit>:
    f : H.Flags <- H.Flags.from_env()
    lifo_go(H.Context.__enter__(f, [H.Context.arg("DEFAULT_FLOAT", "bfloat16")]))

def ooo_go2(+ca: H.Ctx, +cb: H.Ctx) -> IO(Unit):
  do IO<Unit>:
    row_df("ctx_ooo_mid_df", H.Context.__exit__(ca, H.Context.inside(cb)))
    row_df("ctx_ooo_df", H.Context.__exit__(cb, H.Context.__exit__(ca, H.Context.inside(cb))))

def ooo_go(+ca: H.Ctx) -> IO(Unit):
  do IO<Unit>:
    ooo_go2(ca, second(ca))

def ooo_rows() -> IO(Unit):
  do IO<Unit>:
    f : H.Flags <- H.Flags.from_env()
    ooo_go(H.Context.__enter__(f, [H.Context.arg("DEFAULT_FLOAT", "bfloat16")]))

def ooo2_state(+ca: H.Ctx) -> H.Flags:
  H.Context.__exit__(second(ca), H.Context.__exit__(ca, H.Context.inside(second(ca))))

def ooo_state(f: H.Flags) -> H.Flags:
  ooo2_state(H.Context.__enter__(f, [H.Context.arg("DEFAULT_FLOAT", "bfloat16")]))

def disj_go2(+da: H.Ctx, +db: H.Ctx) -> IO(Unit):
  do IO<Unit>:
    row_df("ctx_disj_mid_df", H.Context.__exit__(da, H.Context.inside(db)))
    row_di("ctx_disj_mid_di", H.Context.__exit__(da, H.Context.inside(db)))
    row_df("ctx_disj_df", H.Context.__exit__(db, H.Context.__exit__(da, H.Context.inside(db))))
    row_di("ctx_disj_di", H.Context.__exit__(db, H.Context.__exit__(da, H.Context.inside(db))))

def disj_go(+f: H.Flags) -> IO(Unit):
  do IO<Unit>:
    disj_go2(H.Context.__enter__(f, [H.Context.arg("DEFAULT_INT", "int64")]),
      H.Context.__enter__(H.Context.inside(H.Context.__enter__(f, [H.Context.arg("DEFAULT_INT", "int64")])),
        [H.Context.arg("DEFAULT_FLOAT", "float64")]))

def disj_rows() -> IO(Unit):
  do IO<Unit>:
    f : H.Flags <- H.Flags.from_env()
    disj_go(ooo_state(f))

def nc_go(+tag: String, +c: H.Ctx) -> IO(Unit):
  do IO<Unit>:
    row_nc(String.concat([tag, "_enter"]), H.Context.inside(c))
    row_nc(String.concat([tag, "_exit"]), H.Context.__exit__(c, H.Context.inside(c)))

def nc_rows2(+f: H.Flags) -> IO(Unit):
  do IO<Unit>:
    u : Unit <- nc_go("ctx_nc", H.Context.__enter__(f, [H.Context.arg("NO_COLOR", "0")]))
    nc_go("ctx_empty", H.Context.__enter__(f, [H.Context.arg("NO_COLOR", "")]))

def nc_rows() -> IO(Unit):
  do IO<Unit>:
    f : H.Flags <- H.Flags.from_env()
    nc_rows2(f)

# ===========================================================================
# the 64-bit pair block: i64_or / i64_and / i64_shl / i64_div / i64_mod / gcd
#
# Every def under test is reached THROUGH `H`. The fixture is a PAIR OF WORDS rather
# than a decimal because `H.i64_text` prints the two halves: 2**63 has no `U32`
# image, so a decimal fixture would have to be transcribed on one side and derived on
# the other, and a transcription is exactly the kind of constant that is wrong and
# green. The `_a=` / `_b=` / `_x=` / `_k=` rows print the FIXTURE ITSELF, so a table
# that drifts between the two lanes shows up as a diff on the input.
#
# THE SMALL ROWS ARE THE CONTROL AND NOT THE TEST. A row whose two operands are both
# below 2**32 reads the same whether the divider carries its 65th bit, whether the
# shift's high arm comes from `lo` or from `hi`, and whether the floor correction is
# applied. So the table carries `pm_big` (2**63-1 over 2**62-1), `pm_mini` (-2**63),
# `pm_maxi` (2**63-1 over -1), `pm_ovf` (the one 64-bit overflow) and the three sign
# pairs, and `pm_gf` is small ON PURPOSE: it is a Fibonacci pair, so it is the row
# that reaches the `gcd` fuel bound instead of the 64-bit branches. `pm_gbig` exists
# because without it the `*_gcd` COLUMN is `0:1` on twelve of the fourteen rows, and a
# column that is constant over a suite is a column no mutation can move. It answers
# `1073741823:4294967295` -- a LARGE gcd, not merely a non-1 one -- so the column is
# wide as well as non-constant.
# ===========================================================================

def p64(nm: String, x: H.I64) -> IO(Unit):
  p(nm, H.i64_text(x))

def lit64(hi: U32, lo: U32) -> H.I64:
  H.i64_of_hi_lo(hi, lo)

def pair_go(+nm: String, ah: U32, al: U32, bh: U32, bl: U32) -> IO(Unit):
  +a = lit64(ah, al)
  +b = lit64(bh, bl)
  do IO<Unit>:
    p64(String.concat([nm, "_a"]), a)
    p64(String.concat([nm, "_b"]), b)
    p64(String.concat([nm, "_or"]), H.i64_or(a, b))
    p64(String.concat([nm, "_and"]), H.i64_and(a, b))
    p64(String.concat([nm, "_div"]), H.i64_div(a, b))
    p64(String.concat([nm, "_mod"]), H.i64_mod(a, b))
    p64(String.concat([nm, "_gcd"]), H.gcd(a, b))

def shift_go(+nm: String, xh: U32, xl: U32, +k: Nat) -> IO(Unit):
  +x = lit64(xh, xl)
  do IO<Unit>:
    p64(String.concat([nm, "_x"]), x)
    p(String.concat([nm, "_k"]), Nat.show(k))
    p64(String.concat([nm, "_shl"]), H.i64_shl(x, k))

def i64_rows() -> IO(Unit):
  do IO<Unit>:
    pair_go("pm_zero",  0, 0, 0, 0)
    pair_go("pm_zerod", 0, 7, 0, 0)
    pair_go("pm_small", 0, 5, 0, 3)
    pair_go("pm_big", 2147483647, 4294967295, 1073741823, 4294967295)
    pair_go("pm_nege", 4294967295, 4294967287, 4294967295, 4294967291)
    pair_go("pm_nepo", 4294967295, 4294967289, 0, 4)
    pair_go("pm_pone", 0, 7, 4294967295, 4294967292)
    pair_go("pm_mini", 2147483648, 0, 0, 3)
    pair_go("pm_maxi", 2147483647, 4294967295, 4294967295, 4294967295)
    pair_go("pm_ovf", 2147483648, 0, 4294967295, 4294967295)
    pair_go("pm_wide", 4294967295, 0, 0, 4294967295)
    pair_go("pm_gb", 2147483647, 4294967295, 2147483646, 4294967294)
    pair_go("pm_gbig", 2147483647, 4294967294, 1073741823, 4294967295)
    pair_go("pm_gneg", 4294967295, 4294967289, 0, 6)
    pair_go("pm_gf", 0, 2971215073, 0, 472537396)
    shift_go("sh_k0", 305419896, 2596069104, 0n)
    shift_go("sh_k1", 305419896, 2596069104, 1n)
    shift_go("sh_k31", 305419896, 2596069104, 31n)
    shift_go("sh_k32", 0, 1, 32n)
    shift_go("sh_k33", 0, 1, 33n)
    shift_go("sh_k63", 0, 1, 63n)
    shift_go("sh_k64", 0, 1, 64n)
    shift_go("sh_neg4", 4294967295, 4294967289, 4n)
    shift_go("sh_neg33", 4294967295, 4294967289, 33n)
    shift_go("sh_big63", 2147483647, 4294967295, 63n)

def main() -> IO(Unit):
  do IO<Unit>:
    trange_rows("trange_0", H.trange(0))
    trange_rows("trange_1", H.trange(1))
    trange_rows("trange_2", H.trange(2))
    trange_rows("trange_3", H.trange(3))
    trange_rows("trange_5", H.trange(5))

    gc_rows("gc_init", g0())
    gc_rows("gc_bumped", gc_seq())
    p("gc_default_read", U32.show(at_dev(c_devs(r9v()), 9)))
    keys_rows(r9v())
    gc_rows("gc_after", H.GlobalCounters.reset(gc_seq()))

    boot_rows()
    one_rows()
    lifo_rows()
    ooo_rows()
    disj_rows()
    nc_rows()
    i64_rows()
