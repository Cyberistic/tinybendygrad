# helpers-tc-standalone.bend -- the EXACT text of the three blocks being added to
# tinybendygrad/helpers.bend, plus the gate that exercises them, in one file with no
# imports of helpers.bend. It exists so the port text can be compiled and run green
# BEFORE it lands in the file 88 other files import.
import Base

type Flags is Data:
  Flags{no_color: Bool, default_float: String, default_int: String, sum_dtype: String}

def getenv_str.go(v: Result<&1, &1, U32 & String, String>, d: String) -> String:
  match v:
    case Done{value}: value
    case Fail{error}: d

def getenv_str(k: String, d: String) -> IO(String):
  do IO<String>:
    v : Result<&1, &1, U32 & String, String> <- IO.get_env(k)
    return getenv_str.go(v, d)

def Flags.of(+nc: String, df: String, di: String, sd: String) -> Flags:
  Flags{Bool.or(String.eq(nc, "1"), String.eq(nc, "")), df, di, sd}

def Flags.from_env() -> IO(Flags):
  do IO<Flags>:
    nc : String <- getenv_str("NO_COLOR", "")
    df : String <- getenv_str("DEFAULT_FLOAT", "float32")
    di : String <- getenv_str("DEFAULT_INT", "int32")
    sd : String <- getenv_str("SUM_DTYPE", "float32")
    return Flags.of(nc, df, di, sd)

# ===========================================================================
# GlobalCounters -- helpers.py:319
# ===========================================================================

type Counters is Data:
  Counters{global_ops: U32, global_mem: U32, time_sum_s: F32, kernel_count: U32,
           mem_used: U32, mem_used_per_device: List<&2, Mupd>}

def GlobalCounters.init() -> Counters:
  Counters{0, 0, 0.0, 0, 0, Nil{}}

def GlobalCounters.reset(c: Counters) -> Counters:
  match c:
    case Counters{ops, mem, t, k, used, devs}: Counters{0, 0, 0.0, 0, used, devs}

def GlobalCounters.bump_ops(c: Counters, d: U32) -> Counters:
  match c:
    case Counters{ops, mem, t, k, used, devs}: Counters{U32.add(ops, d), mem, t, k, used, devs}

def GlobalCounters.bump_mem(c: Counters, d: U32) -> Counters:
  match c:
    case Counters{ops, mem, t, k, used, devs}: Counters{ops, U32.add(mem, d), t, k, used, devs}

def GlobalCounters.bump_kernel(c: Counters) -> Counters:
  match c:
    case Counters{ops, mem, t, k, used, devs}: Counters{ops, mem, t, U32.add(k, 1), used, devs}

def GlobalCounters.bump_mem_used(c: Counters, d: U32) -> Counters:
  match c:
    case Counters{ops, mem, t, k, used, devs}: Counters{ops, mem, t, k, U32.add(used, d), devs}

# `mem_used_per_device` is a `defaultdict(int)`, and two of its facts are not a
# number: READING a missing key INSERTS a zero (`mem_used_per_device[9]` answers 0
# AND adds key 9), and the key set is insertion-ordered, so {3, 0, 9} reads back
# "3,0,9" and a dense row vector indexed by device would answer "0,1,2,3" -- four
# keys where Python has three. So this is the `merge_dicts` idiom already used
# above for Python dicts: a list of pairs, which is what `d.items()` yields.
type Mupd is Data:
  Mupd{dev: U32, n: U32}

def GlobalCounters.mupd_dev(m: Mupd) -> U32:
  match m:
    case Mupd{dev, n}: dev

def GlobalCounters.mupd_num(m: Mupd) -> U32:
  match m:
    case Mupd{dev, n}: n

def GlobalCounters.mupd_put.step(same: Bool, +e: Mupd, +dev: U32, +n: U32, out: List<&2, Mupd>) -> List<&2, Mupd>:
  List.append(&2, Mupd, out, [Bool.pick(Mupd, same, Mupd{dev, n}, e)])

def GlobalCounters.mupd_put.end(found: Bool, +dev: U32, n: U32, out: List<&2, Mupd>) -> List<&2, Mupd>:
  match found:
    case True{}: out
    case False{}: List.append(&2, Mupd, out, [Mupd{dev, n}])

def GlobalCounters.mupd_put.go(xs: List<&2, Mupd>, +dev: U32, +n: U32, found: Bool, out: List<&2, Mupd>) -> List<&2, Mupd>:
  match xs:
    case Nil{}: GlobalCounters.mupd_put.end(found, dev, n, out)
    case +e <> t: GlobalCounters.mupd_put.go(t, dev, n, Bool.or(found, U32.is_eq(GlobalCounters.mupd_dev(e), dev)),
      GlobalCounters.mupd_put.step(U32.is_eq(GlobalCounters.mupd_dev(e), dev), e, dev, n, out))

def GlobalCounters.mupd_put(dev: U32, n: U32, xs: List<&2, Mupd>) -> List<&2, Mupd>:
  GlobalCounters.mupd_put.go(xs, dev, n, False{}, Nil{})

def GlobalCounters.mupd_get.pick(found: U32, same: Bool, +e: Mupd) -> U32:
  match same:
    case True{}: GlobalCounters.mupd_num(e)
    case False{}: found

def GlobalCounters.mupd_get.go(xs: List<&2, Mupd>, +dev: U32, found: U32) -> U32:
  match xs:
    case Nil{}: found
    case +e <> t: GlobalCounters.mupd_get.go(t, dev, GlobalCounters.mupd_get.pick(found, U32.is_eq(GlobalCounters.mupd_dev(e), dev), e))

def GlobalCounters.mupd_get(dev: U32, xs: List<&2, Mupd>) -> U32:
  GlobalCounters.mupd_get.go(xs, dev, 0)

def GlobalCounters.mem_used_add(c: Counters, +dev: U32, +d: U32) -> Counters:
  match c:
    case Counters{ops, mem, t, k, used, +devs}:
      Counters{ops, mem, t, k, used,
        GlobalCounters.mupd_put(dev, U32.add(GlobalCounters.mupd_get(dev, devs), d), devs)}

# ===========================================================================
# Context -- helpers.py:187
# ===========================================================================

type CV is Data:
  CV{k: String, nc: Bool, v: String}

type Ctx is Data:
  Ctx{old_context: List<&2, CV>, entered: Flags}

def Context.arg(k: String, +v: String) -> CV:
  CV{k, Bool.not(String.is_empty(v)), v}

def Flags.snap1.go(k: String, nc: Bool, df: String, di: String, sd: String) -> CV:
  match k:
    case "NO_COLOR": CV{"NO_COLOR", nc, ""}
    case "DEFAULT_FLOAT": CV{"DEFAULT_FLOAT", nc, df}
    case "DEFAULT_INT": CV{"DEFAULT_INT", nc, di}
    case _: CV{"SUM_DTYPE", nc, sd}

def Flags.snap1(f: Flags, k: String) -> CV:
  match f:
    case Flags{nc, df, di, sd}: Flags.snap1.go(k, nc, df, di, sd)

def Context.cv_key(cv: CV) -> String:
  match cv:
    case CV{k, nc, v}: k

def Flags.snap.go(+f: Flags, cvs: List<&2, CV>, acc: List<&2, CV>) -> List<&2, CV>:
  match cvs:
    case Nil{}: acc
    case cv <> t: Flags.snap.go(f, t, List.append(&2, CV, acc, [Flags.snap1(f, Context.cv_key(cv))]))

def Flags.snap(f: Flags, cvs: List<&2, CV>) -> List<&2, CV>:
  Flags.snap.go(f, cvs, Nil{})

def Flags.put1.go(k: String, cnnc: Bool, v: String, nc: Bool, df: String, di: String, sd: String) -> Flags:
  match k:
    case "NO_COLOR": Flags{cnnc, df, di, sd}
    case "DEFAULT_FLOAT": Flags{nc, v, di, sd}
    case "DEFAULT_INT": Flags{nc, df, v, sd}
    case _: Flags{nc, df, di, v}

def Flags.put2(cv: CV, nc: Bool, df: String, di: String, sd: String) -> Flags:
  match cv:
    case CV{k, cnnc, v}: Flags.put1.go(k, cnnc, v, nc, df, di, sd)

def Flags.put1(f: Flags, cv: CV) -> Flags:
  match f:
    case Flags{nc, df, di, sd}: Flags.put2(cv, nc, df, di, sd)

def Flags.put.go(cvs: List<&2, CV>, acc: Flags) -> Flags:
  match cvs:
    case Nil{}: acc
    case cv <> t: Flags.put.go(t, Flags.put1(acc, cv))

def Flags.put(f: Flags, cvs: List<&2, CV>) -> Flags:
  Flags.put.go(cvs, f)

def Context.__enter__(+f: Flags, +cvs: List<&2, CV>) -> Ctx:
  Ctx{Flags.snap(f, cvs), Flags.put(f, cvs)}

def Context.inside(c: Ctx) -> Flags:
  match c:
    case Ctx{old_context, entered}: entered

def Context.old(c: Ctx) -> List<&2, CV>:
  match c:
    case Ctx{old_context, entered}: old_context

def Context.__exit__(c: Ctx, f: Flags) -> Flags:
  Flags.put(f, Context.old(c))

# ===========================================================================
# trange -- helpers.py:637
# ===========================================================================

type Tqdm is Data:
  Tqdm{t: U32, seq: List<&2, Nat>}

def trange(+n: U32) -> Tqdm:
  Tqdm{n, List.range(U32.to_nat(n))}


# ===========================================================================
# the gate
# ===========================================================================

def p(+nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

def pu(+nm: String, n: U32) -> IO(Unit):
  p(nm, U32.show(n))

def row_df(nm: String, f: Flags) -> IO(Unit):
  match f:
    case Flags{nc, df, di, sd}: p(nm, df)

def row_di(nm: String, f: Flags) -> IO(Unit):
  match f:
    case Flags{nc, df, di, sd}: p(nm, di)

def row_nc(nm: String, f: Flags) -> IO(Unit):
  match f:
    case Flags{nc, df, di, sd}: pu(nm, Bool.to_u32(nc))

def join_step(first: Bool, acc: String, x: Nat) -> String:
  match first:
    case True{}: Nat.show(x)
    case False{}: String.append(String.append(acc, ","), Nat.show(x))

def join.go(xs: List<&2, Nat>, first: Bool, acc: String) -> String:
  match xs:
    case Nil{}: acc
    case x <> t: join.go(t, False{}, join_step(first, acc, x))

def key_step(first: Bool, acc: String, x: Mupd) -> String:
  match first:
    case True{}: U32.show(GlobalCounters.mupd_dev(x))
    case False{}: String.append(String.append(acc, ","), U32.show(GlobalCounters.mupd_dev(x)))

def join_key.go(xs: List<&2, Mupd>, first: Bool, acc: String) -> String:
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

def trange_rows(nm: String, +t: Tqdm) -> IO(Unit):
  match t:
    case Tqdm{tt, +seq}: trange_go(nm, tt, len_s(seq), first_s(seq), last_s(seq), seq_s(seq))

def c_devs(c: Counters) -> List<&2, Mupd>:
  match c:
    case Counters{ops, mem, t, k, used, devs}: devs

def keys_tail(z: Bool, xs: List<&2, Mupd>) -> String:
  match z:
    case True{}: ""
    case False{}: join_key.go(xs, True{}, "")

def at_dev(xs: List<&2, Mupd>, d: U32) -> U32:
  GlobalCounters.mupd_get(d, xs)

def gc_rows(+tag: String, +c: Counters) -> IO(Unit):
  match c:
    case Counters{ops, mem, t, k, used, devs}:
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
def g0() -> Counters: GlobalCounters.mem_used_add(GlobalCounters.mem_used_add(GlobalCounters.init(), 0, 0), 3, 0)
def g1() -> Counters: GlobalCounters.bump_ops(g0(), 5)
def g2() -> Counters: GlobalCounters.bump_ops(g1(), 7)
def g3() -> Counters: GlobalCounters.bump_mem(g2(), 1024)
def g6() -> Counters: GlobalCounters.bump_kernel(g3())
def g7() -> Counters: GlobalCounters.bump_kernel(g6())
def g8() -> Counters: GlobalCounters.bump_kernel(g7())
def g9() -> Counters: GlobalCounters.bump_mem_used(g8(), 4096)
def ga() -> Counters: GlobalCounters.mem_used_add(g9(), 3, 11)
def gb() -> Counters: GlobalCounters.mem_used_add(ga(), 3, 4)
def gc_seq() -> Counters: GlobalCounters.mem_used_add(gb(), 0, 1)

# --- the Context chain -----------------------------------------------------
#
# ONE chain, in the order the oracle ran its blocks, because upstream's module
# state LEAKS between them: the out-of-order pair leaves DEFAULT_FLOAT at
# "bfloat16" (:178 replays a snapshot, it does not unwind), and the oracle's
# `ctx_disj_*` rows read that leaked value. The port threads the same state.
def keys_rows(+c: Counters) -> IO(Unit):
  p("gc_default_keys", keys_tail(Nat.is_eq(List.length(&2, Mupd, c_devs(c)), 0n), c_devs(c)))

def r9v() -> Counters: GlobalCounters.mem_used_add(gc_seq(), 9, 0)

# --- the Context chain -----------------------------------------------------
#
# ONE chain, in the order the oracle ran its blocks, because upstream's module
# state LEAKS between them: the out-of-order pair leaves DEFAULT_FLOAT at
# "bfloat16" (:178 replays a snapshot, it does not unwind), and the oracle's
# `ctx_disj_*` rows read that leaked value. The port threads the same state.
def boot_go(+f: Flags) -> IO(Unit):
  do IO<Unit>:
    row_df("ctx_boot_df", f)
    row_di("ctx_boot_di", f)
    row_nc("ctx_boot_nc", f)

def boot_rows() -> IO(Unit):
  do IO<Unit>:
    f : Flags <- Flags.from_env()
    boot_go(f)

def second(ca: Ctx) -> Ctx:
  Context.__enter__(Context.inside(ca), [Context.arg("DEFAULT_FLOAT", "float64")])

def one_go(+c: Ctx) -> IO(Unit):
  do IO<Unit>:
    row_df("ctx_enter_df", Context.inside(c))
    row_di("ctx_enter_di", Context.inside(c))
    row_df("ctx_exit_df", Context.__exit__(c, Context.inside(c)))

def one_rows() -> IO(Unit):
  do IO<Unit>:
    f : Flags <- Flags.from_env()
    one_go(Context.__enter__(f, [Context.arg("DEFAULT_FLOAT", "bfloat16")]))

def lifo_go2(+ca: Ctx, +cb: Ctx) -> IO(Unit):
  do IO<Unit>:
    row_df("ctx_in2_df", Context.inside(cb))
    row_df("ctx_lifo_mid_df", Context.__exit__(cb, Context.inside(cb)))
    row_df("ctx_lifo_df", Context.__exit__(ca, Context.__exit__(cb, Context.inside(cb))))

def lifo_go(+ca: Ctx) -> IO(Unit):
  do IO<Unit>:
    lifo_go2(ca, second(ca))

def lifo_rows() -> IO(Unit):
  do IO<Unit>:
    f : Flags <- Flags.from_env()
    lifo_go(Context.__enter__(f, [Context.arg("DEFAULT_FLOAT", "bfloat16")]))

def ooo_go2(+ca: Ctx, +cb: Ctx) -> IO(Unit):
  do IO<Unit>:
    row_df("ctx_ooo_mid_df", Context.__exit__(ca, Context.inside(cb)))
    row_df("ctx_ooo_df", Context.__exit__(cb, Context.__exit__(ca, Context.inside(cb))))

def ooo_go(+ca: Ctx) -> IO(Unit):
  do IO<Unit>:
    ooo_go2(ca, second(ca))

def ooo_rows() -> IO(Unit):
  do IO<Unit>:
    f : Flags <- Flags.from_env()
    ooo_go(Context.__enter__(f, [Context.arg("DEFAULT_FLOAT", "bfloat16")]))

def ooo2_state(+ca: Ctx) -> Flags:
  Context.__exit__(second(ca), Context.__exit__(ca, Context.inside(second(ca))))

def ooo_state(f: Flags) -> Flags:
  ooo2_state(Context.__enter__(f, [Context.arg("DEFAULT_FLOAT", "bfloat16")]))

def disj_go2(+da: Ctx, +db: Ctx) -> IO(Unit):
  do IO<Unit>:
    row_df("ctx_disj_mid_df", Context.__exit__(da, Context.inside(db)))
    row_di("ctx_disj_mid_di", Context.__exit__(da, Context.inside(db)))
    row_df("ctx_disj_df", Context.__exit__(db, Context.__exit__(da, Context.inside(db))))
    row_di("ctx_disj_di", Context.__exit__(db, Context.__exit__(da, Context.inside(db))))

def disj_go(+f: Flags) -> IO(Unit):
  do IO<Unit>:
    disj_go2(Context.__enter__(f, [Context.arg("DEFAULT_INT", "int64")]),
      Context.__enter__(Context.inside(Context.__enter__(f, [Context.arg("DEFAULT_INT", "int64")])),
        [Context.arg("DEFAULT_FLOAT", "float64")]))

def disj_rows() -> IO(Unit):
  do IO<Unit>:
    f : Flags <- Flags.from_env()
    disj_go(ooo_state(f))

def nc_go(+c: Ctx) -> IO(Unit):
  do IO<Unit>:
    row_nc("ctx_nc_enter", Context.inside(c))
    row_nc("ctx_nc_exit", Context.__exit__(c, Context.inside(c)))

def nc_rows() -> IO(Unit):
  do IO<Unit>:
    f : Flags <- Flags.from_env()
    nc_go(Context.__enter__(f, [Context.arg("NO_COLOR", "0")]))

def main() -> IO(Unit):
  do IO<Unit>:
    trange_rows("trange_0", trange(0))
    trange_rows("trange_1", trange(1))
    trange_rows("trange_2", trange(2))
    trange_rows("trange_3", trange(3))
    trange_rows("trange_5", trange(5))

    gc_rows("gc_init", g0())
    gc_rows("gc_bumped", gc_seq())
    p("gc_default_read", U32.show(at_dev(c_devs(r9v()), 9)))
    keys_rows(r9v())
    gc_rows("gc_after", GlobalCounters.reset(gc_seq()))

    boot_rows()
    one_rows()
    lifo_rows()
    ooo_rows()
    disj_rows()
    nc_rows()
