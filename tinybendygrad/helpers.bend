# helpers.bend -- tinygrad/helpers.py, the pure and I/O-reachable half.
#
# SCOPE. tinygrad/helpers.py is 646 lines and four of them are this port:
#   - the pure list/string/number helpers (prod, dedup, argsort, ceildiv, ...)
#   - the ContextVar/Context flag machinery, as an immutable `Flags` record, plus
#     `Context` itself as a snapshot that is threaded rather than pushed
#   - `GlobalCounters`, as a threaded `Counters` record: six fields and `reset`
#   - the two things that need the host: `lines` (a file) and `Timing` (a clock)
# The rest is I/O or dynamic Python and is listed, with a one-line reason each,
# in the NOT PORTED block at the end of this file.
#
# GATE. This file has no `main` -- it is imported by 88 others -- so its rows live in
# `.agents/slop/helpers-tc.bend` and are compared against `.agents/slop/helpers-oracle.py`
# by `sh .agents/slop/helpers-tc-gate.sh`, which runs CPython and both Bend lanes.
# That gate covers `trange`, `GlobalCounters`, `Context` and the 64-bit pair block
# (`i64_or`, `i64_and`, `i64_shl`, `i64_div`, `i64_mod`, `gcd`): 199 shared rows.
# `sh .agents/slop/helpers-i64-mutate.sh` is the mutation table for the last six --
# twelve mutations, two per helper, plus two commutativity controls that move nothing
# -- and `.agents/slop/helpers-i64-mutations.txt` is its output.
#
# `truncate` is not one of helpers.py's: it is dtype.py:296, it needs `dtypes`,
# and it lives in ./dtype.bend. See dtype.bend `def truncate`.

import Base

# ===========================================================================
# Flags -- the pure port of ContextVar / Context
#
# helpers.py's ContextVar is a mutable cell keyed by string, and Context is a
# context manager that swaps a group of them and restores on exit. Bend has no
# global mutable state, so the cell becomes a field of an immutable record and
# the manager becomes "thread a different record through" -- which is what
# `Context(DEFAULT_FLOAT=...)` means. `Flags.defaults` is the module import;
# `Flags.from_env` is the `ContextVar.__init__` `getenv(key, default)`.
#
# The values stay `String` because that is what the ContextVars hold:
# `ContextVar("DEFAULT_FLOAT", "float32")` stores the string "float32" and
# `dtypes.default_float` calls `to_dtype` on it, so the dependency direction is
# the same as Python's (dtype imports helpers).
#
# The variable list is the subset these two files read, and it is 4 flags out of
# 146. COUNTED, not estimated: upstream declares 61 `ContextVar`s (helpers.py:236-290
# plus device.py:18, uop/ops.py:1623-1624, hcq2.py:18, ops_nv.py:27, ops_amd.py:31-34)
# and 85 more read through a bare `getenv("KEY", ...)`, and `Flags` implements THREE
# of the 61 ContextVars -- NO_COLOR, DEFAULT_FLOAT, DEFAULT_INT -- plus SUM_DTYPE,
# which is a bare getenv (dtype.py:223) and not a ContextVar at all. An earlier
# version of this comment said "~40 ContextVars" and was wrong by 21; the count is
# `.agents/slop/env-coercion-table.txt` PART 1, which is 56 int-default and 8
# str-default getenv calls measured by spying on os.getenv before the import.
# So P6 is not a garbage-collection job. Every one of the other 57 ContextVars is
# CONSUMED: `DEBUG` has 119 reads and the lowest is `HCQ_CACHE_THRESH` with 1.
#
# P6 replaces this one record with the full list, and every def that takes a
# `Flags` keeps its shape -- but the SEMANTICS have to be settled first, because
# `getenv` is `type(default)(os.getenv(key, default))` (helpers.py:162), so the
# coercion is `int` for 51 of the 61, `str` for the rest, and `bool` for exactly
# three: PMA (ops_nv.py:27), SQTT and PMC (ops_amd.py:31,34), whose defaults are
# `abs(VIZ.value) >= 2`. MEASURED: `.agents/slop/env-coercion-table.txt` PART 2 is
# the coercion matrix and PART 7 walks NO_COLOR end to end. The `bool` case is the
# one that reads as "any non-empty string is true"; the `int` case, which NO_COLOR
# is, reads an int-zero string as False, and that is the bug the old comment below
# was written on.
# ===========================================================================

type Flags is Data:
  Flags{no_color: Bool, default_float: String, default_int: String, sum_dtype: String}

def Flags.defaults() -> Flags:
  Flags{False{}, "float32", "int32", "float32"}

# `NO_COLOR` is `ContextVar("NO_COLOR", 0)` (helpers.py:239), so `type(default)`
# is `int` and getenv coerces through `int`, NOT through `bool`. `bool(NO_COLOR)`
# is then `bool(int(...))`. MEASURED, 31 probes, live CPython
# (.agents/slop/nocolor-oracle.txt vs .agents/slop/nocolor-bend.txt):
#   "0", "00", "-0", "+0", "0 " and " 0" all read as 0 and leave COLOUR ON, and
#   "1", "2", "007", "+1", "-1", "1_0", " 1 ", "\t2" and "2\n" all read non-zero
#   and switch it OFF. So the rule is not "any text is truthy": that INVERTS
#   every one of those six zeros, and a default-environment gate cannot see an
#   inversion because the default is the only environment it ever runs.
# So: trim, drop one leading sign, and require what is left to be `[0-9_]` with
# at least one character other than '0'.
# `int()` REFUSES "", "0.0", "1e3", "false" and the rest -- tinygrad does not
# import -- and a refusal is not a value in a total language, so every refused
# string answers False. False is the DEFAULT reading (colour on), so the port
# never invents colour CPython would not have printed. The one measured gap is
# `Char.is_digit`, which is ASCII, so CPython's other decimal digits ("٣") read
# False here and True there.
def nc_sign(+s: String) -> Bool:
  Bool.or(String.starts_with(s, "+"), String.starts_with(s, "-"))

def nc_body(sgn: Bool, s: String) -> List<&2, Char>:
  match sgn:
    case True{}: String.to_list(String.drop(s, 1n))
    case False{}: String.to_list(s)

def nc_digits(+s: String) -> List<&2, Char>:
  nc_body(nc_sign(s), String.trim(s))

def nc_in(+h: Char) -> Bool:
  Bool.or(Char.is_digit(h), U32.is_eq(Char.to_u32(h), 95))

# `ok` is "every character so far was in `[0-9_]`" and `nz` is "a non-'0' has been
# seen". A RECORD, not two parameters, because Bend has no projection: a fold that
# carries two Bools beside its list needs a hand-written reader per field.
type Nc is Data:
  Nc{ok: Bool, nz: Bool}

def nc_ok(+n: Nc) -> Bool:
  match n:
    case Nc{ok, nz}: ok

def nc_nz(+n: Nc) -> Bool:
  match n:
    case Nc{ok, nz}: nz

# a digit advances `nz` and keeps `ok`; an underscore keeps both (Python allows one
# BETWEEN digits and the probe list has "1_0"); anything else clears `ok` for good.
def nc_step(ok: Bool, isdig: Bool, inclass: Bool, nz: Bool, +h: Char) -> Nc:
  match isdig:
    case True{}: Nc{ok, Bool.or(nz, U32.is_ne(Char.to_u32(h), 48))}
    case False{}:
      match inclass:
        case True{}: Nc{ok, nz}
        case False{}: Nc{False{}, nz}

def nc_walk(cs: List<&2, Char>, +n: Nc) -> Nc:
  match cs:
    case Nil{}: n
    case +h <> t: nc_walk(t, nc_step(nc_ok(n), Char.is_digit(h), nc_in(h), nc_nz(n), h))

def no_color_of.go(+n: Nc) -> Bool:
  Bool.and(nc_ok(n), nc_nz(n))

def no_color_of(v: String) -> Bool:
  no_color_of.go(nc_walk(nc_digits(v), Nc{True{}, False{}}))

def getenv_str.go(v: Result<&1, &1, U32 & String, String>, d: String) -> String:
  match v:
    case Done{value}: value
    case Fail{error}: d

def getenv_str(k: String, d: String) -> IO(String):
  do IO<String>:
    v : Result<&1, &1, U32 & String, String> <- IO.get_env(k)
    return getenv_str.go(v, d)

# ===========================================================================
# `getenv_int` -- THE OTHER ARM OF THE SAME `getenv`. This is NOT a second
# environment mechanism: `IO.get_env` (base.bend:172) is the only reader and both
# arms call it. helpers.py:163 is the whole of `getenv`:
#
#     @functools.cache
#     def getenv(key:str, default:Any=0): return type(default)(os.getenv(key, default))
#
# so `default` CHOOSES THE COERCION and a default of `""` gives `str` (`getenv_str`
# above) while a default of `0` gives `int` (here). `DEBUG` is the ContextVar that
# needs the int arm -- `DEBUG = ContextVar("DEBUG", 0)`, helpers.py:237 -- and
# `DEBUG >= 2` is a COMPARISON, so a `String` cell cannot carry it. Measured: with
# `DEBUG="2"` the live object is `<class 'int'> 2`, and `int(DEBUG >= 2)` is 1;
# `DEBUG=""` and `DEBUG="abc"` both make the IMPORT raise
# `ValueError: invalid literal for int() with base 10`, which tinygrad does not
# catch (`.agents/slop/debug_oracle.py`, `dbg_value_*` / `dbg_int_getenv_*` rows).
#
# `int()` IS NOT A REGEX. MEASURED, live CPython, 24 probes:
#   "0" 0   "1" 1   "2" 2   "3" 3   "00" 0   "007" 7   "1_0" 10   "2_0_0" 200
#   " 2 " 2   "\t2\n" 2   "+2" 2   "-1" -1
#   "" "_" "1_" "_1" "1__0" "abc" "2.0" "1e3" "0x2"  ALL ValueError
# So: trim, drop ONE leading `+`/`-`, and require what is left to be digits with
# `_` STRICTLY BETWEEN them and at least one digit present. `gi_of_text` is that
# rule as a three-state walk -- PRE (no digit yet), MID (a digit just ended), PEND
# (a `_` just ended, so the next char MUST be a digit) -- and DEAD once refused,
# which is what stops a later digit from resurrecting a prefix that already failed.
#
# THE ONE MEASURED GAP IS `Char.is_digit`, which is ASCII: CPython's `int("٣")` is
# 3 and `gi_of_text("٣")` refuses. That is the SAME gap `no_color_of` above already
# documents for `nc_digits`, and it is left as it is rather than fixed twice.
#
# A LEADING `-` REFUSES rather than yielding a negative, and `getenv_int` then
# answers the DEFAULT. That is a real narrowing of CPython's `int`, so it is
# measured rather than argued: CPython's `int("-1")` is `-1` and every threshold in
# tinygrad is `DEBUG >= N` with `N >= 0`, so `-1 >= 2` and the default `0 >= 2` are
# both False. `debug_ge_neg` in `.agents/slop/debug-gate.bend` holds the two sides
# of that equivalence down. A `U32` cannot hold `-1` and the alternative -- an
# `I64` here and a comparison type change at each of the seven sites -- would buy a
# distinction no site can observe.
# ===========================================================================
# PRE 0, MID 1, PEND 2, DEAD 3, and `v` is the digits so far.
type Gi is Data:
  Gi{st: U32, v: U32}

# A `match` MAY ONLY SCRUTINEE A PARAMETER OR A FIELD BINDER, and both of these are
# refused with "a match cannot scrutinize a computed value: give it its own def":
#   `match gi_dead(st)`        and        `match U32.is_eq(st, 3)`
# So the whole state transition is ONE indexed read, `gi_tab()[st*3 + kind]`, rather
# than three one-comparison arms. A 12-entry table is shorter than the four defs it
# replaces and it cannot drift out of step with them, because there is only one.
#
#      kind:  DIG 0   UND 1   OTHER 2
#   PRE 0  ->  [   1,      3,       3  ]   a LEADING `_` is a refusal
#   MID 1  ->  [   1,      2,       3  ]   a `_` is legal only between digits
#   PEND 2 ->  [   1,      3,       3  ]   a `_` must be FOLLOWED by a digit
#   DEAD 3 ->  [   3,      3,       3  ]   DEAD IS ABSORBING
def gi_tab() -> List<&2, U32>:
  [1, 3, 3, 1, 2, 3, 1, 3, 3, 3, 3, 3]

def gi_index(st: U32, kind: Nat) -> U32:
  U32.add(U32.mul(st, 3), U32.from_nat(kind))

def gi_nxt(st: U32, kind: Nat) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, gi_tab(), U32.to_nat(gi_index(st, kind))), 3)

def gi_acc(v: U32, kind: Nat, d: U32) -> U32:
  match kind:
    case 0n: U32.add(U32.mul(v, 10), d)
    case _: v

def gi_kind.of(dig: Bool, und: Bool) -> Nat:
  match dig:
    case True{}: 0n
    case False{}:
      match und:
        case True{}: 1n
        case _: 2n

def gi_kind(+h: Char) -> Nat:
  gi_kind.of(Char.is_digit(h), U32.is_eq(Char.to_u32(h), 95))

def gi_step(st: U32, v: U32, +h: Char) -> Gi:
  Gi{gi_nxt(st, gi_kind(h)), gi_acc(v, gi_kind(h), U32.sub(Char.to_u32(h), 48))}

def Gi.st(g: Gi) -> U32:
  match g:
    case Gi{st, v}: st

def Gi.v(g: Gi) -> U32:
  match g:
    case Gi{st, v}: v

# `nc_walk` above is the shape: the accumulator is the LAST parameter and the head is
# destructured `+h <> t`, so the only shrinking argument in the self-call is the tail.
def gi_go(cs: List<&2, Char>, +g: Gi) -> Gi:
  match cs:
    case Nil{}: g
    case +h <> t: gi_go(t, gi_step(Gi.st(g), Gi.v(g), h))

# `+` ON A STRING PARAMETER IS WHAT MAKES IT REUSABLE, and it is the same annotation
# `nc_sign` uses on its own `+s`. Without it, reading `t` twice is refused with
# "expected : t / observed : t (consumed more than once)", which is a DIFFERENT
# message from the `U32` case above and reads like the same bug.
def gi_signed(+t: String) -> Bool:
  Bool.or(String.starts_with(t, "+"), String.starts_with(t, "-"))

def gi_body(sgn: Bool, +t: String) -> List<&2, Char>:
  match sgn:
    case True{}: String.to_list(String.drop(t, 1n))
    case _: String.to_list(t)

def gi_neg(+t: String) -> Bool:
  String.starts_with(t, "-")

# THE ACCEPTANCE TEST IS `st == MID`, ONE COMPARISON, and that is the whole point of
# the four-state walk rather than a separate "seen a digit" flag:
#
#   MID is reachable from a prefix that is a legal `int` literal AND ends on a digit.
#   PRE means no digit yet -- only `""` can end here, and `int("")` raises.
#   PEND means a trailing `_` -- `int("1_")` raises.
#   DEAD means a refused prefix -- `int("1__0")`, `int("abc")`, `int("2.0")` raise.
#
# So `st == 1` and "CPython would have accepted it" are the same predicate over every
# reachable state. A `U32` is single-use, so a `gi_ok(st)` that needed both `DEAD` and
# `nodig` could not exist anyway: it would read `st` twice and be refused with
# "consumed more than once".
def gi_take(st: U32, v: U32, d: U32) -> U32:
  match st:
    case 1: v
    case _: d

def Gi.take(g: Gi, d: U32) -> U32:
  match g:
    case Gi{st, v}: gi_take(st, v, d)

def gi_of_text.walk(+t: String, sgn: Bool, d: U32) -> U32:
  Gi.take(gi_go(gi_body(sgn, t), Gi{0, 0}), d)

def gi_of_text.go(neg: Bool, sgn: Bool, +t: String, d: U32) -> U32:
  match neg:
    case True{}: d
    case _: gi_of_text.walk(t, sgn, d)

def gi_of_text(+s: String, d: U32) -> U32:
  gi_of_text.go(gi_neg(s), gi_signed(s), String.trim(s), d)

def getenv_int.go(v: Result<&1, &1, U32 & String, String>, d: U32) -> U32:
  match v:
    case Done{value}: gi_of_text(value, d)
    case Fail{error}: d

def getenv_int(k: String, d: U32) -> IO(U32):
  do IO<U32>:
    v : Result<&1, &1, U32 & String, String> <- IO.get_env(k)
    return getenv_int.go(v, d)

# `DEBUG`, at helpers.py:237's own value and helpers.py:163's own coercion. THE
# NAME IS UPSTREAM'S: the port spells a ContextVar it has decided to thread as the
# ContextVar's own name, so a reader of `debug()` does not have to know that it was
# renamed to `getenv_int("DEBUG", 0)` underneath.
def debug() -> IO(U32):
  getenv_int("DEBUG", 0)

# THE THRESHOLD, spelled once for all seven sites. `ContextVar.__ge__` is
# `self.value >= x` (helpers.py:193) and `self.value` is the int `getenv` built, so
# `DEBUG >= 2` is an INTEGER comparison and nothing else. Six sites pass 2 and
# `schedule/memory.py:59` passes 1 -- MEASURED, not read off a comment: the oracle
# extracts the right-hand side out of each site's own source line with
# `re.search(r"DEBUG\s*>=\s*(\d+)", src)` and prints it as `thr_<site>`, and
# `thr_mem=1` while `thr_ar=thr_st=thr_am185=thr_am225=thr_am251=thr_am254=2`.
def debug_ge(dbg: U32, n: U32) -> Bool:
  U32.is_ge(dbg, n)

# THE PRINT, AND THE HALF OF THE SITE THAT IS NOT A BRANCH. `if DEBUG >= N: print(f"…")`
# is "build the line iff the gate is open, then write it", and here the two halves are
# separate defs for a reason that is not stylistic: the gate is a PARAMETER (see
# `schedule/allreduce.bend`'s header, "THE FLAGS ARE PARAMETERS"), and a def that
# both branches on a parameter and hands the branch's text onward gives a gate row
# nothing to diff at level 0 -- the row would simply be absent, which is
# indistinguishable from a site that was never wired. So each site answers
# line-or-`""` and this writes it, and `""` writes NOTHING: the level-0 control is a
# row present with an empty value, not a missing row.
def debug_print.of(empty: Bool, s: String) -> IO(Unit):
  match empty:
    case True{}: IO.pure(Unit, Unit{})
    case _: IO.print(s)

def debug_print(+s: String) -> IO(Unit):
  debug_print.of(String.is_empty(s), s)

def Flags.of(nc: String, df: String, di: String, sd: String) -> Flags:
  Flags{no_color_of(nc), df, di, sd}

def Flags.from_env() -> IO(Flags):
  do IO<Flags>:
    nc : String <- getenv_str("NO_COLOR", "")
    df : String <- getenv_str("DEFAULT_FLOAT", "float32")
    di : String <- getenv_str("DEFAULT_INT", "int32")
    sd : String <- getenv_str("SUM_DTYPE", "float32")
    return Flags.of(nc, df, di, sd)

# ===========================================================================
# Context -- `class Context(contextlib.ContextDecorator)`, helpers.py:170
#
# THE WHOLE MECHANIC IS THREE LINES of upstream and none of them is `with`:
#   __init__      self.kwargs = kwargs                                   (:171)
#   __enter__     snapshot every named cell, then overwrite it           (:175-176)
#   __exit__      write the snapshot back                                 (:178)
# `ContextVar._cache` (:181) is a class-level dict of cells, so "overwrite a cell"
# is a mutation of a module global and a `with` block is the scope that bounds it.
# Bend has neither, so the block becomes two calls and the snapshot is the VALUE
# the first one returns: `Context.__enter__` answers `Ctx`, which carries BOTH the
# snapshot and the record now in force, and `Context.__exit__` needs the snapshot and
# the current record to write it back. A caller cannot "enter" without doing both
# halves, because there is no separate enter step to forget.
#
# `old_context` IS A SNAPSHOT, NOT A STACK, and that is the load-bearing fact.
# `__exit__` (:178) replays `self.old_context` onto whatever is CURRENT; it does not
# pop. Two contexts on the SAME key, entered in order A then B and exited in the
# order A then B, leave the value A wrote, not the original -- measured, and it is
# the `ctx_ooo_df` row in `.agents/slop/helpers-oracle.py`. A port that pushed and
# popped a stack would answer the original value and be wrong. The gate nests the
# pair twice, once in order and once out of order, precisely to tell those two
# readings apart, and a third fixture with DISJOINT keys pins that `__exit__` writes
# back only its OWN kwargs.
#
# `CV` mirrors `Flags` field for field rather than holding one value, and the reason
# is a measurement: `__enter__` assigns the RAW kwarg into the cell and does NOT go
# back through getenv's `type(default)(...)` (:163). So `Context(NO_COLOR="0")` puts
# the STRING "0" in the cell, and `ContextVar.__bool__` (:188) is `bool(self.value)`,
# where `bool("0")` is True. At boot `no_color` is the COERCION of the env string and
# "0" reads False; inside a `Context` the same text reads True. One `String` slot
# could not carry both, so `CV` keeps the coerced bool AND the raw text and
# `Context.arg` (:171, the kwargs entry) is where the coercion happens ONCE, on the
# way IN. The snapshot (`Flags.snap1`, :175) therefore restores the boot bool and
# `ctx_nc_exit` is 0 where `ctx_nc_enter` is 1.
#
# `_recreate_cm` (:173) is NOT PORTED and there is nothing to port: it exists because
# `ContextDecorator` reuses `self`, so a RECURSIVE use of one instance would
# overwrite `self.old_context` with the inner call's snapshot. Here the snapshot is
# returned as a value instead of being written into the manager, so the hazard has
# no representation -- two nested uses of the same kwargs are two `Ctx` values and
# neither can reach the other.
# ===========================================================================

type CV is Data:
  CV{k: String, nc: Bool, v: String}

type Ctx is Data:
  Ctx{old_context: List<&2, CV>, entered: Flags}

# the kwargs entry, `Context(DEFAULT_FLOAT="bfloat16")`
def Context.arg(k: String, +v: String) -> CV:
  CV{k, Bool.not(String.is_empty(v)), v}

def Context.cv_key(cv: CV) -> String:
  match cv:
    case CV{k, nc, v}: k

# `{k: ContextVar._cache[k].value for k in self.kwargs}` (:175)
def Flags.snap1.go(k: String, nc: Bool, df: String, di: String, sd: String) -> CV:
  match k:
    case "NO_COLOR": CV{"NO_COLOR", nc, ""}
    case "DEFAULT_FLOAT": CV{"DEFAULT_FLOAT", nc, df}
    case "DEFAULT_INT": CV{"DEFAULT_INT", nc, di}
    case _: CV{"SUM_DTYPE", nc, sd}

def Flags.snap1(f: Flags, k: String) -> CV:
  match f:
    case Flags{nc, df, di, sd}: Flags.snap1.go(k, nc, df, di, sd)

def Flags.snap.go(+f: Flags, cvs: List<&2, CV>, acc: List<&2, CV>) -> List<&2, CV>:
  match cvs:
    case Nil{}: acc
    case cv <> t: Flags.snap.go(f, t, List.append(&2, CV, acc, [Flags.snap1(f, Context.cv_key(cv))]))

def Flags.snap(f: Flags, cvs: List<&2, CV>) -> List<&2, CV>:
  Flags.snap.go(f, cvs, Nil{})

# `for k, v in kwargs.items(): ContextVar._cache[k].value = v` (:176), and the same
# loop again for the restore in `__exit__` (:178). Both are "write these keys", so
# both are `Flags.put`; LAST wins, which is what building a dict does.
#
# TODO(p6) helpers.py:176  `ContextVar._cache[k]` is a KeyError for a name that is
# not a ContextVar. `Flags` holds 4 of the 61, so an unknown key has nowhere to go and
# lands on SUM_DTYPE. Loud rather than silent: the alternative is a no-op that cannot
# be told from a correct write.
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
# prod -- functools.reduce(operator.mul, x, 1). NOTE the Python comment: it
# returns int 1 if x is empty regardless of the type of x. `List.foldl` wants a
# closure, so this is its own recursive def.
# ===========================================================================

def prod_u32(xs: List<&2, U32>) -> U32:
  match xs:
    case Nil{}:
      1
    case h <> t:
      (U32.mul(h, prod_u32(t)) : U32)

def prod_nat(xs: List<&2, Nat>) -> Nat:
  match xs:
    case Nil{}:
      1n
    case h <> t:
      Nat.mul(h, prod_nat(t))

# ===========================================================================
# dedup -- list(dict.fromkeys(x)): first occurrence wins, retains list order.
# Bend's Map is string-keyed only, so the set is a linear scan.
# ===========================================================================

def dedup_u32.put(seen: Bool, h: U32, r: List<&2, U32>) -> List<&2, U32>:
  match seen:
    case True{}: r
    case False{}: h <> r

def dedup_u32.go(+x: U32, +r: List<&2, U32>) -> List<&2, U32>:
  dedup_u32.put(List.contains(U32, U32.is_eq, r, x), x, r)

def dedup_u32(xs: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: Nil{}
    case h <> t: dedup_u32.go(h, dedup_u32(t))

def dedup_str.put(seen: Bool, h: String, r: List<&2, String>) -> List<&2, String>:
  match seen:
    case True{}: r
    case False{}: h <> r

def dedup_str.go(+x: String, +r: List<&2, String>) -> List<&2, String>:
  dedup_str.put(List.contains(String, String.eq, r, x), x, r)

def dedup_str(xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case h <> t: dedup_str.go(h, dedup_str(t))

# ===========================================================================
# argfix -- `def argfix(*x)`. Bend has no variadics and no tuple type, so the
# Python shapes become three defs:
#   argfix([a,b])         -> argfix_seq([a,b])   (x[0] is a tuple or list)
#   argfix(a)             -> argfix1(a)          (one non-sequence argument)
#   argfix(a, b)          -> argfix2(a, b)
# Python raises ValueError when a sequence arrives alongside other arguments;
# `argfix_bad` is that ValueError, answered as a Maybe so a caller can branch.
# The two-argument `argfix` that tinygrad actually calls everywhere is
# argfix2/argfix_seq, so no third arm is missing in practice.
# ===========================================================================

def argfix_bad(sequence_with_others: Bool) -> Maybe<&1, U32>:
  match sequence_with_others:
    case True{}: Some{0}
    case False{}: None{}

def argfix1(a: U32) -> List<&2, U32>:
  [a]

def argfix2(a: U32, b: U32) -> List<&2, U32>:
  [a, b]

def argfix_seq(xs: List<&2, U32>) -> List<&2, U32>:
  xs

# ===========================================================================
# argsort -- `type(x)(sorted(range(len(x)), key=x.__getitem__))`.
# https://stackoverflow.com/questions/3382352/equivalent-of-numpy-argsort-in-basic-python
# Python's sort is stable, so the index breaks ties by position: compare
# (value, index). `List.sort` wants a closure, so the comparison is a top-level
# def over an (index, value) pair.
# ===========================================================================

type Ix is Data:
  Ix{i: U32, v: U32}

def ix_le.tie(same: Bool, i: U32, j: U32) -> Bool:
  match same:
    case True{}: U32.is_le(i, j)
    case False{}: True{}

def ix_le.cmp(le: Bool, v: U32, w: U32, i: U32, j: U32) -> Bool:
  match le:
    case True{}: ix_le.tie(U32.is_eq(v, w), i, j)
    case False{}: False{}

def ix_le(a: Ix, b: Ix) -> Bool:
  match a b:
    case Ix{i, +v} Ix{j, +w}: ix_le.cmp(U32.is_le(v, w), v, w, i, j)

# the list is field 1 so the recursive call's first argument is the shrinking one
def ix_of.go(xs: List<&2, U32>, +i: U32) -> List<&2, Ix>:
  match xs:
    case Nil{}: Nil{}
    case h <> t: Ix{i, h} <> ix_of.go(t, U32.add(i, 1))

def ix_of(xs: List<&2, U32>) -> List<&2, Ix>:
  ix_of.go(xs, 0)

# `List.map` takes its element closure by template, and the template wants a
# List<&1, A> while `List.sort` hands back a List<&2, A>, so the projection is
# written out here rather than fought over.
def ix_index(i: Ix) -> U32:
  match i:
    case Ix{k, v}: k

def ix_map(l: List<&2, Ix>) -> List<&2, U32>:
  match l:
    case Nil{}: Nil{}
    case i <> t: ix_index(i) <> ix_map(t)

def argsort_u32(xs: List<&2, U32>) -> List<&2, U32>:
  ix_map(List.sort(Ix, ix_le, ix_of(xs)))

# ===========================================================================
# all_same -- `all(x == items[0] for x in items)`, which works for empty input.
# The head is peeled once and every other element is compared against it.
# ===========================================================================

def all_same_u32.go(xs: List<&2, U32>, +head: U32) -> Bool:
  match xs:
    case Nil{}: True{}
    case h <> t: Bool.and(U32.is_eq(h, head), all_same_u32.go(t, head))

def all_same_u32(xs: List<&2, U32>) -> Bool:
  match xs:
    case Nil{}: True{}
    case h <> t: all_same_u32.go(t, h)

def all_same_str.go(xs: List<&2, String>, +head: String) -> Bool:
  match xs:
    case Nil{}: True{}
    case h <> t: Bool.and(String.eq(h, head), all_same_str.go(t, head))

def all_same_str(xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}: True{}
    case h <> t: all_same_str.go(t, h)

# ===========================================================================
# get_shape -- `def get_shape(x) -> tuple[int, ...]`
#
# DEVIATION, stated: Python walks any object with `__len__` and `__getitem__`,
# and NOTE `str` is special because iterating it still yields strs. Bend has no
# duck typing, so the input is the `Nest` tree below: `Ns` is a scalar, `Nl` is
# a sequence -- the same information Python reads off the object, made explicit
# at the boundary.
#
# Python returns () for a scalar, for a string, and for an object whose `.shape`
# is (); it raises ValueError for an inhomogeneous shape. Those are three
# outcomes, so they are three constructors and none of them is a silent None. A
# sequence of scalars is NOT (): get_shape([1,2]) is (2,) and get_shape([]) is
# (0,).
# ===========================================================================

type ShapeRes is Data:
  SNoShape{}                      # Python: ()
  SShape{dims: List<&2, U32>}     # Python: a tuple of ints, possibly ()
  SBad{why: String}               # Python: ValueError("inhomogeneous shape")

def u32_list_eq(a: List<&2, U32>, b: List<&2, U32>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case h <> t h2 <> t2: Bool.and(U32.is_eq(h, h2), u32_list_eq(t, t2))
    case _ _: False{}

type Nest is Data:
  Ns{v: U32}
  Nl{ss: List<&2, Nest>}

# `ShapeRes.of` is Python's `if not all_same(subs): raise; (len(subs),) +
# subs[0]`, so a sequence of scalars has shape (n,), not (), and an empty
# sequence has shape (0,). The all_same walk is ONE def carrying the state
# Python's generator carries: `ref` is the first non-() child's dims and `bad`
# is "a () met a non()". The child list is the FIRST argument so the recursion
# decreases structurally and the rest of the state is free.
#
# The three rules are Python's `all_same`:
#   all ()        -> (n,)            every child is a scalar
#   all equal d   -> (n,) + d        the homogeneous case
#   anything else -> SBad            Python's ValueError
#
# the first child sets the reference: a scalar leaves it None, a shape sets it
def ShapeRes.dims.head(s0: ShapeRes) -> Maybe<&2, List<&2, U32>>:
  match s0:
    case SShape{d}: Some{d}
    case SNoShape{}: None{}
    case SBad{why}: None{}

# has a shaped child disagreed with the reference so far?
def ShapeRes.dims.same(ref: Maybe<&2, List<&2, U32>>, d2: List<&2, U32>) -> Bool:
  match ref:
    case None{}: False{}
    case Some{d}: Bool.not(u32_list_eq(d, d2))

def ShapeRes.dims.ref.put(ref: Maybe<&2, List<&2, U32>>, d2: List<&2, U32>) ->
  Maybe<&2, List<&2, U32>>:
  match ref:
    case None{}: Some{d2}
    case Some{d}: ref

def ShapeRes.dims.ans(ref: Maybe<&2, List<&2, U32>>, n: U32) -> ShapeRes:
  match ref:
    case None{}: SShape{[n]}
    case Some{d}: SShape{n <> d}

# Python's three-way all_same is the inner match: a child that is itself SBad
# poisons, a scalar child means the shape is (n,) so a shaped sibling is
# inhomogeneous, and a shaped child must agree with the reference.
def ShapeRes.dims(r: List<&2, ShapeRes>, bad: Bool, +ref: Maybe<&2, List<&2, U32>>,
  n: U32) -> ShapeRes:
  match r bad:
    case Nil{} True{}: SBad{"inhomogeneous shape"}
    case Nil{} False{}: ShapeRes.dims.ans(ref, n)
    case SBad{why} <> _ True{}: SBad{why}
    case SBad{why} <> _ False{}: SBad{why}
    case SNoShape{} <> _ False{}: SBad{"inhomogeneous shape"}
    case SNoShape{} <> _ True{}: SBad{"inhomogeneous shape"}
    case SShape{+d2} <> t True{}: SBad{"inhomogeneous shape"}
    case SShape{+d2} <> t False{}:
      ShapeRes.dims(t, ShapeRes.dims.same(ref, d2), ShapeRes.dims.ref.put(ref, d2), n)

def ShapeRes.of.walk(ss: List<&2, ShapeRes>, n: U32) -> ShapeRes:
  match ss:
    case Nil{}: SShape{Nil{}}
    case s0 <> r: ShapeRes.dims(r, False{}, ShapeRes.dims.head(s0), n)

def ShapeRes.of(+ss: List<&2, ShapeRes>) -> ShapeRes:
  ShapeRes.of.walk(ss, U32.from_nat(List.length(&2, ShapeRes, ss)))

# `get_shape` in Python is a mutual recursion: a node's shape is built from its
# children's shapes, and computing a child's shape recurses. Bend has no mutual
# recursion, so the walk below carries a STACK of open groups, each holding the
# children's shapes seen so far. A list of lists cannot be consed in one term
# (the `<>` operator infers a single element type), so both levels are records.
type Frame is Data:
  Frame{v: List<&2, ShapeRes>}

type Stk is Data:
  Stk{fs: List<&2, Frame>}

def stk.init() -> Stk:
  Stk{Nil{}}

# append a child's shape to the innermost open group
def stk.grow(fv: List<&2, ShapeRes>, t: List<&2, Frame>, v: ShapeRes) -> List<&2, Frame>:
  g = {Frame{List.append(&2, ShapeRes, fv, [v])} : Frame}
  g <> t

def stk.push(xs: List<&2, Frame>, v: ShapeRes) -> List<&2, Frame>:
  match xs:
    case Nil{}: [Frame{[v]}]
    case f <> t:
      match f:
        case Frame{fv}: stk.grow(fv, t, v)

def stk.push2(s: Stk, v: ShapeRes) -> Stk:
  match s:
    case Stk{fs}: Stk{stk.push(fs, v)}

# open a new (empty) frame on top of the current one
def stk.open(s: Stk) -> Stk:
  match s:
    case Stk{fs}: Stk{Frame{Nil{}} <> fs}

def stk.peek(s: Stk) -> List<&2, ShapeRes>:
  match s:
    case Stk{fs}:
      match fs:
        case Nil{}: Nil{}
        case f <> _:
          match f:
            case Frame{fv}: fv

# push a child's shape onto the frame BELOW the top one, and drop the top: this
# is what closing a group does, once its own shape has been computed from it
def stk.unpush(xs: List<&2, Frame>, v: ShapeRes) -> List<&2, Frame>:
  match xs:
    case Nil{}: [Frame{[v]}]
    case g <> t:
      match g:
        case Frame{gv}: stk.grow(gv, t, v)

# a node's children go in front of the pending work, with a GC after them
def st.splice(ss: List<&2, Nest>, t: List<&2, GIn>) -> List<&2, GIn>:
  match ss:
    case Nil{}: t
    case n <> r: GN{n} <> st.splice(r, t)

# the same splice for a list that stays a list of Nests (fully_flatten)
def st.spread(ss: List<&2, Nest>, t: List<&2, Nest>) -> List<&2, Nest>:
  match ss:
    case Nil{}: t
    case n <> r: n <> st.spread(r, t)

# The work list: GN opens a node, GC closes the group it opened.
type GIn is Data:
  GN{n: Nest}
  GC{}

# ONE def, ONE recursion, everything inlined. Python's get_shape is a mutual
# recursion (a node's shape is built from its children's shapes, and computing a
# child's shape recurses); Bend has no mutual recursion, so the children go on
# an explicit work list and the open groups on an explicit stack, which unties
# the knot into a single self-call. `k` is the FIRST parameter so `match k` then
# `match ws` then `match st` follows binder order, and every recursive call
# passes `p` in the first slot. The fuel is a backstop: the work list is finite
# by construction, and running out answers SBad rather than hanging.
#
# The three outcomes are Python's all_same over the children, computed in
# ShapeRes.of when a GC pops a frame:
#   all ()        -> (n,)
#   all equal d   -> (n,) + d
#   anything else -> SBad (Python's ValueError)
def get_shape.go(k: Nat, ws: List<&2, GIn>, st: Stk) -> ShapeRes:
  match k:
    case 0n: SBad{"shape nested too deeply"}
    case Succ{p}:
      match ws:
        case Nil{}: ShapeRes.of(stk.peek(st))
        case GC{} <> t:
          match st:
            case Stk{fs}:
              match fs:
                case Nil{}: get_shape.go(p, t, Stk{Nil{}})
                case f <> rest:
                  match f:
                    case Frame{fv}: get_shape.go(p, t, Stk{stk.unpush(rest, ShapeRes.of(fv))})
        case GN{n} <> t:
          match n:
            case Ns{v}: get_shape.go(p, t, stk.push2(st, SNoShape{}))
            case Nl{ss}: get_shape.go(p, st.splice(ss, {GC{} : GIn} <> t), stk.open(st))

# The backstop fuel, a fixed budget rather than the tree's exact node count (that
# would itself be a mutual recursion). BACKSTOP only: every node is opened once
# (one GN) and closed once (one GC), so the walk always terminates on its own.
def nest_nodes() -> Nat:
  1000000n

# a scalar is (), so a leaf root is answered before the walk starts
def get_shape.root(n: Nest, k: Nat) -> ShapeRes:
  match n:
    case Ns{v}: SNoShape{}
    case Nl{ss}: get_shape.go(k, [GN{n}], stk.init())

def get_shape(n: Nest) -> ShapeRes:
  get_shape.root(n, nest_nodes())

# is_image_shape -- `shape is not None and len(shape) == 3 and shape[-1] == 4`.
# Python's None is the "not a shape" answer, which is SNoShape or SBad here.
def is_image_shape.tail(last: Maybe<&2, U32>) -> Bool:
  match last:
    case Some{x}: U32.is_eq(x, 4)
    case None{}: False{}

def is_image_shape.dims(three: Bool, d: List<&2, U32>) -> Bool:
  match three:
    case True{}: is_image_shape.tail(List.last(&2, U32, d))
    case False{}: False{}

def is_image_shape.rank(r: ShapeRes) -> List<&2, U32>:
  match r:
    case SNoShape{}: Nil{}
    case SBad{why}: Nil{}
    case SShape{d}: d

def is_image_shape.go(+d: List<&2, U32>) -> Bool:
  match d:
    case Nil{}: False{}
    case _: is_image_shape.dims(U32.is_eq(U32.from_nat(List.length(&2, U32, d)), 3), d)

def is_image_shape(r: ShapeRes) -> Bool:
  is_image_shape.go(is_image_shape.rank(r))

# all_int -- True when every element is a Python int. On a `Nest` that is exactly
# "no Nl node anywhere": an Nl node is a sequence by construction and a sequence
# is not an int. If the ROOT is an Nl the answer is already False and if it is an
# Ns there is nothing below it, so this checks the root alone.
def all_int_nest(n: Nest) -> Bool:
  match n:
    case Ns{v}: True{}
    case Nl{ss}: False{}

# fully_flatten -- `[x for li in l for x in fully_flatten(li)]` over the same
# Nest tree, with Python's guard that a non-sequence (and a string) is `[l]`.
# ONE def over a work list with a `Nat` fuel in the first slot, because splicing
# children in front of the pending work GROWS the list. Leaves accumulate in
# `acc` and are reversed at the end, so the document order is the tree's
# preorder.
def fully_flatten.go(k: Nat, ws: List<&2, Nest>, acc: List<&2, Nest>) -> List<&2, Nest>:
  match k:
    case 0n: List.reverse(&2, Nest, acc)
    case Succ{p}:
      match ws:
        case Nil{}: List.reverse(&2, Nest, acc)
        case Ns{v} <> t: fully_flatten.go(p, t, Ns{v} <> acc)
        case Nl{ss} <> t: fully_flatten.go(p, st.spread(ss, t), acc)

def fully_flatten_nest(n: Nest) -> List<&2, Nest>:
  match n:
    case Ns{v}: [n]
    case Nl{ss}: fully_flatten.go(nest_nodes(), ss, Nil{})

# flatten -- `[item for sublist in l for item in sublist]`
def flatten_u32(l: List<&2, List<&2, U32>>) -> List<&2, U32>:
  List.concat(&2, U32, l)

# ===========================================================================
# F32 text
#
# `F32.show` is a law with no body -- it is an axiom -- and so is every other F32
# law, so the port needs its own F32 formatter. `f"{x:.2f}"` (time_to_str,
# size_to_str, colorize_float) has no base equivalent either. `f32_fixed` walks
# the decimal expansion of the f32 two digits at a time, which is printf's
# `%.2f` on a value that came out of an f32.
# ===========================================================================

# 0x7F800000 is the f32 exponent field; all ones means inf or nan, and the
# mantissa being non-zero distinguishes nan from inf
def f32_exp_all_ones(+x: F32) -> Bool:
  U32.is_eq(U32.and(F32.bits(x), 2139095040), 2139095040)

def f32_is_nan(+x: F32) -> Bool:
  Bool.and(f32_exp_all_ones(x), Bool.not(U32.is_zero(U32.and(F32.bits(x), 8388607))))

def f32_is_finite(+x: F32) -> Bool:
  Bool.not(f32_exp_all_ones(x))

def f32_is_neg(+x: F32) -> Bool:
  U32.is_ge(F32.bits(x), 2147483648)

# The decimal digits after the point. The state is a `Frac` record (remainder,
# digits so far) advanced by a top-level step, so the recursion is one structural
# descent on the digit count.
type Frac is Data:
  Frac{f: F32, acc: String}

def f32_frac.next(+f: F32) -> F32:
  F32.sub(F32.mul(f, 10.0), U32.to_f32(F32.to_u32(F32.mul(f, 10.0))))

def f32_frac.digit(+f: F32) -> Char:
  Char.from_u32(U32.add(48, F32.to_u32(F32.mul(f, 10.0))))

def f32_frac.step(+f: F32, acc: String) -> Frac:
  Frac{f32_frac.next(f), String.append(acc, String.from_list([f32_frac.digit(f)]))}

def f32_frac.put(fr: Frac) -> String:
  match fr:
    case Frac{f, acc}: acc

def f32_frac.go(n: Nat, fr: Frac) -> String:
  match n:
    case 0n: f32_frac.put(fr)
    case Succ{p}:
      match fr:
        case Frac{f, acc}: f32_frac.go(p, f32_frac.step(f, acc))

def f32_fixed.put(neg: Bool, s: String) -> String:
  match neg:
    case True{}: String.append("-", s)
    case False{}: s

# `f"{x:.2f}"` on a value that came out of an f32: the integer part, a point,
# and `dp` digits walked off the remainder.
def f32_fixed.text3(neg: Bool, ip: U32, dp: Nat, frac: Frac) -> String:
  f32_fixed.put(neg, String.append(String.append(U32.show(ip), "."),
    f32_frac.go(dp, frac)))

def f32_fixed.text2(neg: Bool, dp: Nat, m: F32, +ip: U32) -> String:
  f32_fixed.text3(neg, ip, dp, Frac{F32.sub(m, U32.to_f32(ip)), ""})

def f32_fixed.text1(+m: F32, dp: Nat, neg: Bool) -> String:
  f32_fixed.text2(neg, dp, m, F32.to_u32(F32.trunc(m)))

def f32_fixed.text(x: F32, dp: Nat, m: F32) -> String:
  f32_fixed.text1(m, dp, f32_is_neg(x))

def f32_fixed.body(+x: F32, dp: Nat) -> String:
  f32_fixed.text1(F32.abs(x), dp, f32_is_neg(x))

def f32_fixed.special.inf(neg: Bool) -> Maybe<&1, String>:
  match neg:
    case True{}: Some{"-inf"}
    case False{}: Some{"inf"}

def f32_fixed.special.fin(fin: Bool, neg: Bool) -> Maybe<&1, String>:
  match fin:
    case True{}: None{}
    case False{}: f32_fixed.special.inf(neg)

def f32_fixed.special(nan: Bool, fin: Bool, neg: Bool) -> Maybe<&1, String>:
  match nan:
    case True{}: Some{"nan"}
    case False{}: f32_fixed.special.fin(fin, neg)

def f32_fixed.go(special: Maybe<&1, String>, x: F32, dp: Nat) -> String:
  match special:
    case Some{s}: s
    case None{}: f32_fixed.body(x, dp)

def f32_fixed(+x: F32, dp: Nat) -> String:
  f32_fixed.go(f32_fixed.special(f32_is_nan(x), f32_is_finite(x), f32_is_neg(x)), x, dp)

def f32_is_int_valued(fin: Bool, +x: F32) -> Bool:
  match fin:
    case False{}: False{}
    case True{}: F32.is_eq(F32.floor(x), x)

# The shortest decimal that reads back, the way Python's repr does. |x| >= 2^32
# is out of range for U32.to_u32 and prints as its low word; that is the F32
# boundary and no f64 port of this formatter can do better in a U32.
def f32_show.put2(iv: Bool, x: F32, neg: Bool) -> String:
  match iv:
    case True{}: f32_fixed.put(neg, U32.show(F32.to_u32(F32.abs(x))))
    case False{}: f32_fixed.body(x, 6n)

def f32_show.put(+iv: Bool, +x: F32) -> String:
  f32_show.put2(iv, x, f32_is_neg(x))

def f32_show.special(nan: Bool, fin: Bool, neg: Bool) -> Maybe<&1, String>:
  match nan:
    case True{}: Some{"nan"}
    case False{}:
      match fin:
        case True{}: None{}
        case False{}:
          match neg:
            case True{}: Some{"-inf"}
            case False{}: Some{"inf"}

def f32_show.go2(s: Maybe<&1, String>, +x: F32) -> String:
  match s:
    case Some{t}: t
    case None{}: f32_show.put(f32_is_int_valued(f32_is_finite(x), x), x)

def f32_show.go(x: F32, s: Maybe<&1, String>) -> String:
  f32_show.go2(s, x)

def f32_show(+x: F32) -> String:
  f32_show.go(x, f32_show.special(f32_is_nan(x), f32_is_finite(x), f32_is_neg(x)))

# Python's f-string field width is a right-justified minimum width: s.rjust(w)
def pad.n.go(gt: Bool, w: U32, n: U32) -> U32:
  match gt:
    case True{}: U32.sub(w, n)
    case False{}: 0

def pad.n(+w: U32, +n: U32) -> U32:
  pad.n.go(U32.is_gt(w, n), w, n)

def pad_left.blank(s: String, w: U32) -> String:
  String.repeat(" ", U32.to_nat(pad.n(w, U32.from_nat(String.length(s)))))

def pad_left(+s: String, w: U32) -> String:
  String.append(pad_left.blank(s, w), s)

def pad_right(+s: String, w: U32) -> String:
  String.append(s, pad_left.blank(s, w))

# ===========================================================================
# colored -- `f"\u001b[{10*background+60*(color.upper()==color)+30+index}m{st}
# \u001b[0m"`, which replaces the termcolor library. The colour is a U32 index
# into ['black','red','green','yellow','blue','magenta','cyan','white']; Python
# raises ValueError on a name outside it, so `colored` takes `Maybe<&1, U32>` and
# None is Python's `color is None`, which returns the plain string. NO_COLOR is a
# ContextVar, so it arrives inside the `Flags` record.
# ===========================================================================

def color_code(ci: U32, background: Bool) -> U32:
  (U32.add(U32.add(U32.mul(Bool.to_u32(background), 10), 30), ci) : U32)

def esc(u: U32) -> String:
  String.from_list([Char.from_u32(27), Char.from_u32(91), Char.from_u32(u), Char.from_u32(109)])

def color_of(s: String) -> Maybe<&1, U32>:
  match s:
    case "black": Some{0}
    case "red": Some{1}
    case "green": Some{2}
    case "yellow": Some{3}
    case "blue": Some{4}
    case "magenta": Some{5}
    case "cyan": Some{6}
    case "white": Some{7}
    case _: None{}

def colored.put(color: Maybe<&1, U32>, st: String, background: Bool) -> String:
  match color:
    case None{}: st
    case Some{ci}: String.append(String.append(esc(color_code(ci, background)), st), "\u{1b}[0m")

def colored.flag(nc: Bool, st: String, color: Maybe<&1, U32>, background: Bool) -> String:
  match nc:
    case True{}: st
    case False{}: colored.put(color, st, background)

def colored.go(f: Flags, st: String, color: Maybe<&1, U32>, background: Bool) -> String:
  match f:
    case Flags{nc, df, di, sd}: colored.flag(nc, st, color, background)

def colored(f: Flags, st: String, color: Maybe<&1, U32>, background: Bool) -> String:
  colored.go(f, st, color, background)

# colorize_float -- f"{x:7.2f}x", green below 0.75, red above 1.15, else yellow
def colorize_float.hi(gt: Bool) -> Maybe<&1, U32>:
  match gt:
    case True{}: Some{1}
    case False{}: Some{3}

def colorize_float.pick(lt: Bool, gt: Bool) -> Maybe<&1, U32>:
  match lt:
    case True{}: Some{2}
    case False{}: colorize_float.hi(gt)

def colorize_float(f: Flags, +x: F32) -> String:
  colored(f, String.append(pad_left(f32_fixed(x, 2n), 7), "x"),
    colorize_float.pick(F32.is_lt(x, 0.75), F32.is_gt(x, 1.15)), False{})

# ===========================================================================
# time_to_str -- `next((f"{t*d:{w}.2f}{pr}" for d,pr in [(1,"s "),(1e3,"ms")]
# if t > 10/d), f"{t*1e6:{w}.2f}us")`: seconds above 10, milliseconds above
# 0.01, microseconds below. The generator is the fold a match replaces.
# ===========================================================================

def time_to_str.ms(t: F32, w: U32) -> String:
  String.append(pad_left(f32_fixed(F32.mul(t, 1000.0), 2n), w), "ms")

def time_to_str.us(t: F32, w: U32) -> String:
  String.append(pad_left(f32_fixed(F32.mul(t, 1000000.0), 2n), w), "us")

def time_to_str.pick(gt10: Bool, gt001: Bool, t: F32, w: U32) -> String:
  match gt10:
    case True{}: String.append(pad_left(f32_fixed(t, 2n), w), "s ")
    case False{}:
      match gt001:
        case True{}: time_to_str.ms(t, w)
        case False{}: time_to_str.us(t, w)

def time_to_str(+t: F32, w: U32) -> String:
  time_to_str.pick(F32.is_gt(t, 10.0), F32.is_gt(t, 0.01), t, w)

# size_to_str -- the first of GB/MB/KB that s reaches, else "<s> B". Python
# divides by a power of two with `/`, so the quotient is an f32.
def size_to_str.mb(s: U32) -> String:
  String.append(f32_fixed(F32.div(U32.to_f32(s), 1048576.0), 2n), " MB")

def size_to_str.kb(s: U32) -> String:
  String.append(f32_fixed(F32.div(U32.to_f32(s), 1024.0), 2n), " KB")

def size_to_str.pick(gb: Bool, mb: Bool, kb: Bool, s: U32) -> String:
  match gb:
    case True{}: String.append(f32_fixed(F32.div(U32.to_f32(s), 1073741824.0), 2n), " GB")
    case False{}:
      match mb:
        case True{}: size_to_str.mb(s)
        case False{}:
          match kb:
            case True{}: size_to_str.kb(s)
            case False{}: String.append(U32.show(s), " B")

def size_to_str(+s: U32) -> String:
  size_to_str.pick(U32.is_ge(s, 1073741824), U32.is_ge(s, 1048576), U32.is_ge(s, 1024), s)

# ===========================================================================
# ansistrip -- `re.sub('\x1b\[(K|.*?m)', '', s)` (helpers.py:48).
#
# THE REGEX MATCHES A RUN OF ARBITRARY LENGTH, SO NOTHING MAY DECIDE BEFORE THE
# RUN'S END IS SEEN. `.*?m` is non-greedy and unbounded: a walker that emits as it
# goes has already emitted too much by the time it learns whether the sequence was
# `K` or `31m`. Bend 2.0.34 offers no way to look ahead, and all three of these
# are MEASURED:
#
#   * forward references are rejected outright -- "expected : a filled definition
#     (an unfilled law is a dead claim: live code cannot use it)". So a state
#     machine may NOT be split into a driver and a stepper: that is mutual
#     recursion and it does not compile. ONE def, ONE recursion, ONE table.
#   * a `case`-bound list TAIL IS LINEAR -- "expected : t, observed : t (consumed
#     more than once)" -- so a look-ahead over the rest of the input and a walk
#     over the rest of the input cannot both live in one arm.
#   * a self-call argument must be a SYNTACTIC TAIL -- "expected : a decreasing
#     self-call" -- so neither `String.drop(s, n)` nor `List.append(t, [h])` may
#     step the cursor by more than one character.
#
# SO THE RUN IS EMITTED OPTIMISTICALLY AND UN-EMITTED ON A MATCH. `acc` is
# REVERSED, so prepending is O(1) and a run's characters are already on TOP of
# `acc` when its terminator arrives: dropping the run is `List.drop(acc, n)` for
# the count `n` of characters put there. One pass, no look-ahead, no flush, no
# re-scan, no rollback.
#
# The state is two def PARAMETERS and not a record, because `Nat` and `List` are
# both linear and a `case`-bound name may be used ONCE: a record pattern that
# binds `n` cannot also name `n` in the arm ("expected : n, observed : n (consumed
# more than once)"). So `acc`, `n` and `q` are passed through and never matched:
#
#   q = 0n  normal
#   q = 1n  an ESC is pending and has emitted nothing yet
#   q = 2n  inside a run whose body is still empty
#   q = 3n  inside a run with at least one body character
#
# `q` is a match position, and the char code is folded into the LIST pattern as
# `Chr{27}`, because a Bend `match` may only scrutinise a def parameter or a
# record FIELD -- never `Char.to_u32(h)` ("a match cannot scrutinize a computed
# value") and never a `case`-bound binder ("this name is a def or a consumed
# binder"). A `Nat` in a multi-scrutinee position is also checked for
# exhaustiveness while a `Nat` inside a record pattern is not, which is the whole
# of why the state is parameters.
#
# The three ways a run ends:
#   * 'm'  -- `.*?` of length ZERO, so `ESC[m` is a whole run. Reachable from 2n
#             and 3n.
#   * 'K'  -- and ONLY with an empty body, because `(K|.*?m)` tries `K` first and
#             alternation is ordered. Reachable only from 2n. Rows `ansi_10`
#             ("ESC[Km" -> "m") and `ansi_11` ("ESC[K31m" -> "31m") pin that;
#             `ansi_19` ("ESC[31mK" -> "K") pins the other side, that a 'K' after
#             a body is ordinary text.
#   * '\n' -- `.` does not cross a newline, so a newline before any 'm' fails the
#             whole `.*?m` alternative and NOTHING matches. Every character of the
#             run is then left in the output, which is `re.sub`'s "no match at i:
#             emit s[i], retry at i+1" carried out one character at a time. Rows
#             `ansi_24`, `ansi_25` and `ansi_26` pin that.
#
# MEASURED against CPython on a 43-fixture corpus (`.agents/slop/ansi_oracle.py`
# vs `.agents/slop/ansi_probe.bend`, gate `.agents/slop/ansi_gate.py`): 28 of 43
# rows were red before this rewrite.
#
# THE ONE RESIDUAL DIVERGENCE, and it is a wall rather than an oversight. A run
# that FAILS (newline before the terminator, or end of input) must be re-read by
# `re.sub` from its '[' -- and a body can itself contain a complete `ESC[K`,
# which that re-read strips. This walk cannot re-read: the body has already been
# emitted and would have to be read a second time, and a list tail is linear. So
# the body is emitted verbatim. Row `ansi_29` ("\x1b[\x1b[K\n") is the witness:
# CPython answers "\x1b[\n", this port answers "\x1b[\x1b[K\n". The differ NAMES
# the row rather than hiding it. Closing it needs a nested three-state tracker for
# `ESC` `[` `K` inside a body, which is 13 more table arms; that is a scoping
# decision, not a proof that Bend cannot do it.
# ===========================================================================

# prepending emits LAST, so this puts the pending ESC immediately before whatever
# follows it, and `List.drop` on the FRONT of `acc` removes the run's most recent
# characters.
def ansistrip.esc(acc: List<&2, Char>) -> List<&2, Char>:
  List.append(&2, Char, [Char.from_u32(27)], acc)

# the '[' is put on TOP of the ESC-prepended `acc`, because prepending emits LAST
# and '[' comes after ESC in the output. Getting this the other way round swaps
# the two and turns every "\x1b[" into "[\x1b" -- rows `ansi_03` and `ansi_24`
# caught it. `acc` is spent once, by `esc`, and never named again.
def ansistrip.esc_brk(acc: List<&2, Char>) -> List<&2, Char>:
  List.append(&2, Char, [Char.from_u32(91)], ansistrip.esc(acc))

# `acc` is spent by `List.reverse`, so it cannot also sit in the other arm of a
# `Bool.pick`. The reverse happens first and the pending ESC is prepended to the
# REVERSED list, which is the same string: reversing `[ESC] ++ rev` gives
# `rev ++ [ESC]`.
def ansistrip.done.at(acc: List<&2, Char>, esc: Bool) -> List<&2, Char>:
  match esc:
    case True{}: ansistrip.esc(acc)
    case False{}: acc

def ansistrip.done(esc: Bool, acc: List<&2, Char>) -> List<&2, Char>:
  ansistrip.done.at(List.reverse(&2, Char, acc), esc)

def ansistrip.go(cs: List<&2, Char>, acc: List<&2, Char>, n: Nat, q: Nat) -> List<&2, Char>:
  match cs, q:
    # AT END OF INPUT. A run in progress cannot match -- its terminator never came
    # -- so it stays in the output, and a pending ESC is emitted because nothing
    # ever followed it.
    case Nil{}, 0n: ansistrip.done(False{}, acc)
    case Nil{}, 1n: ansistrip.done(True{}, acc)
    case Nil{}, 2n: ansistrip.done(False{}, acc)
    case Nil{}, 3n: ansistrip.done(False{}, acc)
    # `q` NEVER EXCEEDS 3n -- no arm below writes a larger one -- and this is here
    # only because a `Nat` multi-scrutinee is checked for exhaustiveness.
    case Nil{}, Succ{_p}: ansistrip.done(False{}, acc)
    # NORMAL. An ESC emits nothing and opens a pending one.
    case Chr{27} <> t, 0n: ansistrip.go(t, acc, 0n, 1n)
    case Chr{c} <> t, 0n: ansistrip.go(t, Chr{c} <> acc, n, 0n)
    # A PENDING ESC. '[' opens a run and both of its characters go on the count;
    # an ESC emits the pending one and opens a fresh pending one; anything else
    # emits the pending ESC and then the character.
    case Chr{91} <> t, 1n: ansistrip.go(t, ansistrip.esc_brk(acc), 2n, 2n)
    case Chr{27} <> t, 1n: ansistrip.go(t, ansistrip.esc(acc), n, 1n)
    case Chr{c} <> t, 1n: ansistrip.go(t, Chr{c} <> ansistrip.esc(acc), n, 0n)
    # A RUN WITH AN EMPTY BODY, where 'K' is the first alternative and matches.
    # A MATCH DROPS THE RUN AND RESETS `n`, which is never read outside a run --
    # and `n` is linear, so it may be spent by the drop and not also carried.
    case Chr{75} <> t, 2n: ansistrip.go(t, List.drop(&2, Char, acc, n), 0n, 0n)
    case Chr{109} <> t, 2n: ansistrip.go(t, List.drop(&2, Char, acc, n), 0n, 0n)
    # A NEWLINE FAILS THE RUN and is then ordinary text itself, so it is emitted
    # like any other character -- `re.sub` retries at i+1 and reaches it.
    case Chr{10} <> t, 2n: ansistrip.go(t, Chr{10} <> acc, n, 0n)
    case Chr{c} <> t, 2n: ansistrip.go(t, Chr{c} <> acc, Nat.add(n, 1n), 3n)
    # A RUN WITH A BODY, where 'K' is ordinary text and only 'm' ends the run.
    case Chr{109} <> t, 3n: ansistrip.go(t, List.drop(&2, Char, acc, n), 0n, 0n)
    case Chr{10} <> t, 3n: ansistrip.go(t, Chr{10} <> acc, n, 0n)
    case Chr{c} <> t, 3n: ansistrip.go(t, Chr{c} <> acc, Nat.add(n, 1n), 3n)
    case Chr{c} <> t, Succ{_p}: ansistrip.go(t, Chr{c} <> acc, Nat.add(n, 1n), 3n)

def ansistrip(s: String) -> String:
  String.from_list(ansistrip.go(String.to_list(s), Nil{}, 0n, 0n))

def ansilen(s: String) -> Nat:
  String.length(ansistrip(s))

def ansipad(+s: String, w: U32) -> String:
  String.append(s, String.repeat(" ", U32.to_nat(pad.n(w, U32.from_nat(ansilen(s))))))

# ===========================================================================
# make_tuple -- `(x,)*cnt` when x is an int, else `tuple(x)`. Two arms, two
# defs: the int arm repeats, the sequence arm is the identity.
# ===========================================================================

def make_tuple_rep.go(n: Nat, +x: U32) -> List<&2, U32>:
  match n:
    case 0n: Nil{}
    case Succ{p}: x <> make_tuple_rep.go(p, x)

def make_tuple_rep(x: U32, cnt: U32) -> List<&2, U32>:
  make_tuple_rep.go(U32.to_nat(cnt), x)

def make_tuple_of(x: U32) -> List<&2, U32>:
  [x]

# to_tuple -- `x if isinstance(x, tuple) else (x,)`. A List is already the
# sequence form, so the only work is wrapping a scalar.
def to_tuple_u32(x: U32) -> List<&2, U32>:
  [x]

def to_tuple_seq(xs: List<&2, U32>) -> List<&2, U32>:
  xs

# ===========================================================================
# flat_to_grouped
# `(padding_left, padding_right, padding_top, padding_bottom, ...)` ->
# `(..., (padding_top, padding_bottom), (padding_left, padding_right))`, i.e.
# `tuple(zip(padding[-2::-2], padding[::-2]))`: pair the elements up from the END,
# so [a,b,c,d] -> [(c,d),(a,b)] and [a,b,c] -> [(b,c)] and [a,b] -> [(a,b)] and
# [a] -> []. The pairs, read FORWARD, are the consecutive pairs starting at index
# (n mod 2), and the answer is that list reversed.
# ===========================================================================

def fg_pairs(p: List<&2, U32>) -> List<&2, List<&2, U32>>:
  match p:
    case h <> t:
      match t:
        case g <> r: [h, g] <> fg_pairs(r)
        case Nil{}: Nil{}
    case Nil{}: Nil{}

def fg_skip(n: Nat, xs: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: xs
    case Succ{p}:
      match xs:
        case Nil{}: Nil{}
        case _ <> t: fg_skip(p, t)

def flat_to_grouped(+padding: List<&2, U32>) -> List<&2, List<&2, U32>>:
  List.reverse(&2, List<&2, U32>, fg_pairs(fg_skip(Nat.mod(List.length(&2, U32, padding), 2n), padding)))

# ===========================================================================
# resolve_pool_pads -- int -> [p] * 2*dims; a sequence of 2*dims -> as is; a
# sequence of dims -> `[p for p in padding for _ in range(2)][::-1]`. Python
# raises ValueError on any other length, and that is the Maybe.
# ===========================================================================

def resolve_pool_pads_int.go(n: Nat, +p: U32) -> List<&2, U32>:
  match n:
    case 0n: Nil{}
    case Succ{q}: p <> resolve_pool_pads_int.go(q, p)

def resolve_pool_pads_int(p: U32, dims: U32) -> List<&2, U32>:
  resolve_pool_pads_int.go(U32.to_nat(U32.mul(2, dims)), p)

def pool_pads_dup.go(ps: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match ps:
    case Nil{}: List.reverse(&2, U32, acc)
    case +h <> t: pool_pads_dup.go(t, List.append(&2, U32, acc, [h, h]))

def pool_pads_dup(p: List<&2, U32>) -> List<&2, U32>:
  pool_pads_dup.go(p, Nil{})

def resolve_pool_pads.pick(isdims: Bool, p: List<&2, U32>) -> Maybe<&1, List<&2, U32>>:
  match isdims:
    case True{}: Some{pool_pads_dup(p)}
    case False{}: None{}

def resolve_pool_pads.step(istwodims: Bool, isdims: Bool, p: List<&2, U32>, dims: U32) ->
  Maybe<&1, List<&2, U32>>:
  match istwodims:
    case True{}: Some{p}
    case False{}: resolve_pool_pads.pick(isdims, p)

def resolve_pool_pads.n(two: Bool, dims: Bool, p: List<&2, U32>, dims2: U32) ->
  Maybe<&1, List<&2, U32>>:
  resolve_pool_pads.step(two, dims, p, dims2)

def resolve_pool_pads(+p: List<&2, U32>, +dims: U32) -> Maybe<&1, List<&2, U32>>:
  resolve_pool_pads.n(U32.is_eq(U32.from_nat(List.length(&2, U32, p)), U32.mul(2, dims)),
    U32.is_eq(U32.from_nat(List.length(&2, U32, p)), dims), p, dims)

# ===========================================================================
# _is_balanced / strip_parens
# `_is_balanced(s)` is "no prefix closes more than it opens, and the depths end
# at zero". The depth is a U32, so underflow is the wrap past 2^31. `s[1:-1]` and
# `fst[:1]` / `fst[-1:]` are String.drop and String.take.
# ===========================================================================

def bal.next.step(c: U32, d: U32) -> U32:
  match c:
    case 40: U32.add(d, 1)
    case 41: U32.sub(d, 1)
    case _: d

def bal.next(h: Char, d: U32) -> U32:
  bal.next.step(Char.to_u32(h), d)

def bal.under(nd: U32) -> Bool:
  U32.is_ge(nd, 2147483648)

# the walk carries its depth as a record rather than as two parameters: the depth
# has to be matched (for the end test) while the char list is matched for the walk
type Depth is Data:
  Depth{d: U32, under: Bool}

def bal.depth(st: Depth) -> U32:
  match st:
    case Depth{d, under}: d

def bal.spilled(st: Depth) -> Bool:
  match st:
    case Depth{d, under}: under

def bal.step(spilled: Bool, +nd: U32) -> Depth:
  match spilled:
    case True{}: Depth{nd, True{}}
    case False{}: Depth{nd, bal.under(nd)}

def bal.end(st: Depth) -> Bool:
  match st:
    case Depth{d, under}:
      match under:
        case True{}: False{}
        case False{}: U32.is_zero(d)

def bal.walk(cs: List<&2, Char>, +st: Depth) -> Bool:
  match cs:
    case Nil{}: bal.end(st)
    case +h <> t: bal.walk(t, bal.step(bal.spilled(st), bal.next(h, bal.depth(st))))

def is_balanced(s: String) -> Bool:
  bal.walk(String.to_list(s), Depth{0, False{}})

def strip_parens.inner(+fst: String) -> String:
  String.take(String.drop(fst, 1n), Nat.sub(String.length(fst), 2n))

def is_wrapped.both(starts: Bool, ends: Bool, +fst: String) -> Bool:
  match starts:
    case True{}:
      match ends:
        case True{}: is_balanced(strip_parens.inner(fst))
        case False{}: False{}
    case False{}: False{}

def is_wrapped(+fst: String) -> Bool:
  is_wrapped.both(String.starts_with(fst, "("), String.ends_with(fst, ")"), fst)

def strip_parens.go(wrapped: Bool, +fst: String) -> String:
  match wrapped:
    case True{}: strip_parens.inner(fst)
    case False{}: fst

def strip_parens(+fst: String) -> String:
  strip_parens.go(is_wrapped(fst), fst)

# ===========================================================================
# Signed 32-bit arithmetic on a U32 bit pattern
#
# Bend has no signed integers, so a signed value is its two's complement bit
# pattern and every comparison is a sign test.
# ===========================================================================

def i32_is_neg(x: U32) -> Bool:
  U32.is_ge(x, 2147483648)

def i32_neg(x: U32) -> U32:
  U32.sub(0, x)

# asr -- Bend's two shifts are both LOGICAL, so a negative value needs its top
# `m` bits put back after the shift. The fill is the whole WORD 0xFFFFFFFF and
# NOT the sign bit: shifting the sign bit right answers 1 rather than a run of
# ones. The count is clamped to 31, and that is not a workaround but the WHOLE
# answer past 31: floor(v/2^n) is -1 when v < 0 and 0 when v >= 0 once n reaches
# 32, and the clamped form is exactly that number.
def asr(+v: U32, n: Nat) -> U32:
  +m = Nat.min(n, 31n)
  U32.or(U32.shrn(v, m), U32.shln(i32_neg(U32.shrn(v, 31n)), Nat.sub(32n, m)))

def i32_abs(neg: Bool, x: U32) -> U32:
  match neg:
    case True{}: i32_neg(x)
    case False{}: x

# cdiv and floordiv both need "the two signs differ". Python gets it from `x*y<0`;
# multiplying first would overflow in 32 bits and could flip the answer, so the XOR
# of the two sign bits is used.
def cdiv_sign(x: U32, y: U32) -> Bool:
  Bool.xor(i32_is_neg(x), i32_is_neg(y))

# python floor div and mod: `x//y if y != 0 else 0`
def floordiv_i32.exact(ax: U32, ay: U32) -> Bool:
  U32.is_zero(U32.mod(ax, ay))

def floordiv_i32.trunc.put(neg: Bool, q: U32) -> U32:
  match neg:
    case True{}: i32_neg(q)
    case False{}: q

# floordiv -- `x//y if y != 0 else 0`: truncate toward zero, and step DOWN one
# more only when the division was inexact AND the two signs DIFFER. For a
# same-sign division the truncation already IS the floor, so the step belongs to
# the opposite-sign case alone.
def floordiv_i32.trunc.exact(exact: Bool, neg: Bool, q: U32) -> U32:
  match exact:
    case True{}: floordiv_i32.trunc.put(neg, q)
    case False{}:
      match neg:
        case True{}: floordiv_i32.trunc.put(neg, U32.add(q, 1))
        case False{}: q

def floordiv_i32.trunc(neg: Bool, exact: Bool, q: U32) -> U32:
  floordiv_i32.trunc.exact(exact, neg, q)

def floordiv_i32.pick(zero: Bool, neg: Bool, exact: Bool, ax: U32, ay: U32) -> U32:
  match zero:
    case True{}: 0
    case False{}: floordiv_i32.trunc(neg, exact, U32.div(ax, ay))

def floordiv_i32(+x: U32, +y: U32) -> U32:
  floordiv_i32.pick(U32.is_zero(y), cdiv_sign(x, y),
    floordiv_i32.exact(i32_abs(i32_is_neg(x), x), i32_abs(i32_is_neg(y), y)),
    i32_abs(i32_is_neg(x), x), i32_abs(i32_is_neg(y), y))

# ===========================================================================
# WHICH OF THE TWO PAIRS IS WHICH. `cdiv_i32_go`/`cmod_i32` TRUNCATE toward zero
# (helpers.py:73-74, C semantics, `-7 // 4` is `-1`) and
# `floordiv_i32`/`floormod_i32` FLOOR (helpers.py:76-77, Python's `//` and `%`,
# `-7 // 4` is `-2`). Both are correct, both are exported, and they are NOT
# duplicates: `ceildiv` is `-(num // -amt)` and `round_up` is
# `(num+amt-1)//amt*amt`, and BOTH are floors, so neither can be spelled with a
# truncating division. Picking the wrong pair is a wrong answer, not a slower
# right one.
# ===========================================================================

# cstyle div and mod: `abs(x)//abs(y)*(1,-1)[x*y<0] if y != 0 else 0`
def cdiv_i32.put(neg: Bool, q: U32) -> U32:
  match neg:
    case True{}: i32_neg(q)
    case False{}: q

def cdiv_i32(zero: Bool, neg: Bool, q: U32) -> U32:
  match zero:
    case True{}: 0
    case False{}: cdiv_i32.put(neg, q)

def cdiv_i32_go(+x: U32, +y: U32) -> U32:
  cdiv_i32(U32.is_zero(y), cdiv_sign(x, y),
    U32.div(i32_abs(i32_is_neg(x), x), i32_abs(i32_is_neg(y), y)))

def cmod_i32(+x: U32, +y: U32) -> U32:
  U32.sub(x, U32.mul(cdiv_i32_go(x, y), y))

def floormod_i32(+x: U32, +y: U32) -> U32:
  U32.sub(x, U32.mul(floordiv_i32(x, y), y))

# The unsigned readings of the same four. Python's // and % on a non-negative
# int are U32.div and U32.mod, and U32.div(a, 0) = 0 / U32.mod(a, 0) = a is
# exactly tinygrad's zero-divisor branch.
def floordiv_u32(x: U32, y: U32) -> U32:
  U32.div(x, y)

def floormod_u32(+x: U32, +y: U32) -> U32:
  U32.sub(x, U32.mul(U32.div(x, y), y))

def cdiv_u32(x: U32, y: U32) -> U32:
  U32.div(x, y)

def cmod_u32(+x: U32, +y: U32) -> U32:
  U32.sub(x, U32.mul(cdiv_u32(x, y), y))

# ===========================================================================
# ceildiv / round_up / round_down / next_power2
#
# ceildiv -- `if hasattr(num,'vmin') and num.vmin >= 0 and amt > 0: (num+amt-1)//
# amt`, else `-(num // -amt)`. The first arm is there to avoid C/Python division
# mismatch, and it duck-types on a UOp; there is no UOp in this phase, and the
# two arms agree on ints, so the integer port is the second one, which is total
# over negatives as well. It spells `-(num // -amt)`: the DIVISOR is negated, the
# dividend is not. SYMBOLIC CASE, LATER PHASE (P3, uop/symbolic.bend): it needs
# `vmin`, the bound a Variable carries in the arena, and comes back as
# `ceildiv_uop(num: UOp, amt: UOp)`.
# ===========================================================================

def ceildiv_i32(num: U32, amt: U32) -> U32:
  i32_neg(floordiv_i32(num, i32_neg(amt)))

# div0 -- Python raises ZeroDivisionError for x//0; tinygrad guards floordiv and
# cdiv with `if y != 0 else 0` but NOT ceildiv or round_up, which raise. Bend is
# total, so the guarded reading (0) is the one every zero-divisor def here answers.
def div0(zero: Bool, v: U32) -> U32:
  match zero:
    case True{}: 0
    case False{}: v

# overflow-free: (num+amt-1)/amt wraps at num+amt-1 > 2^32-1 (measured: 2**32-1
# with amt 2**20 answered 0 where CPython says 4096); num/amt + (num%amt != 0)
# is exact on the whole U32 domain.
def ceildiv_u32(+num: U32, +amt: U32) -> U32:
  div0(U32.is_zero(amt), U32.add(U32.div(num, amt), Bool.to_u32(U32.is_ne(U32.mod(num, amt), 0))))

def round_up_i32(num: U32, +amt: U32) -> U32:
  U32.mul(floordiv_i32(U32.add(U32.add(num, amt), 4294967295), amt), amt)

def round_down_i32(num: U32, amt: U32) -> U32:
  i32_neg(round_up_i32(i32_neg(num), amt))

def round_up_u32(num: U32, +amt: U32) -> U32:
  U32.mul(ceildiv_u32(num, amt), amt)

def round_down_u32(num: U32, amt: U32) -> U32:
  i32_neg(round_up_u32(i32_neg(num), amt))

# `1 if x == 0 else 1 << (x-1).bit_length()`: the smallest power of two that is
# >= x, with 0 answering 1. The fold needs a fuel because p grows rather than
# shrinks; 33 steps cover every x a U32 holds. x > 2^31 has no representable
# answer (Python answers 2^32) and is documented as such.
def next_power2.go(k: Nat, lt: Bool, +x: U32, +p: U32) -> U32:
  match k:
    case 0n: p
    case Succ{q}:
      match lt:
        case True{}: next_power2.go(q, U32.is_lt(U32.add(p, p), x), x, U32.add(p, p))
        case False{}: p

def next_power2(+x: U32) -> U32:
  next_power2.go(33n, U32.is_lt(1, x), x, 1)

# ===========================================================================
# 64-bit words
#
# helpers.py's lo32 / hi32 / data64 / data64_le all say "Any is sint", so the
# value they take is a signed 64-bit int. Bend has no 64-bit word, so it is the
# pair of halves in two's complement. Build one with i64_of_i32 (sign-extends)
# or i64_of_hi_lo.
# ===========================================================================

type I64 is Data:
  I64{hi: U32, lo: U32}

def match_hi(neg: Bool) -> U32:
  match neg:
    case True{}: 4294967295
    case False{}: 0

def i64_of_i32(+x: U32) -> I64:
  I64{match_hi(i32_is_neg(x)), x}

def i64_of_hi_lo(hi: U32, lo: U32) -> I64:
  I64{hi, lo}

def lo32(x: I64) -> U32:
  match x:
    case I64{hi, lo}: lo

def hi32(x: I64) -> U32:
  match x:
    case I64{hi, lo}: hi

# A signed comparison of two's complement pairs. Two's complement compares
# correctly as UNSIGNED words whenever the signs agree, so the only case that
# needs the sign is when they differ -- and then it is decided outright. `U32.cmp`
# answers a Cmp and Cmp is a datatype, so the head comparison arrives as the two
# Bools it decides and the low word only matters when the high words are equal.
def i64_cmp.lt(lt: Bool) -> Cmp:
  match lt:
    case True{}: LT{}
    case False{}: GT{}

def i64_cmp.mag(eq: Bool, lt: Bool, eql: Bool, ltl: Bool) -> Cmp:
  match eq:
    case True{}:
      match eql:
        case True{}: EQ{}
        case False{}: i64_cmp.lt(ltl)
    case False{}: i64_cmp.lt(lt)

def i64_cmp.sgn(an: Bool, +ah: U32, +al: U32, bn: Bool, +bh: U32, +bl: U32) -> Cmp:
  match an bn:
    case True{} False{}: LT{}
    case False{} True{}: GT{}
    case True{} True{}: i64_cmp.mag(U32.is_eq(ah, bh), U32.is_lt(ah, bh),
      U32.is_eq(al, bl), U32.is_lt(al, bl))
    case False{} False{}: i64_cmp.mag(U32.is_eq(ah, bh), U32.is_lt(ah, bh),
      U32.is_eq(al, bl), U32.is_lt(al, bl))

def i64_cmp(+a: I64, +b: I64) -> Cmp:
  i64_cmp.sgn(i32_is_neg(hi32(a)), hi32(a), lo32(a),
    i32_is_neg(hi32(b)), hi32(b), lo32(b))

def i64_is_neg(x: I64) -> Bool:
  i32_is_neg(hi32(x))

def i64_le(a: I64, b: I64) -> Bool:
  Cmp.is_le(i64_cmp(a, b))

# An I64 prints as its two words, so a value never has to leave U32 to be read.
# `hi:lo` rather than a decimal because 2^63 has no U32 image, and a dump the
# oracle can diff line for line is worth more here than a prettier one.
def i64_show(hi: U32, lo: U32) -> String:
  String.concat([U32.show(hi), ":", U32.show(lo)])

def i64_text(+x: I64) -> String:
  i64_show(hi32(x), lo32(x))

# 64-bit add and subtract, so a boundary generator can step either side of a
# limit without an effect. Carrying into the high word is all either has to get
# right, and U32's wrap does that for free.
# THE BORROW AND THE CARRY ARE NOT OPTIONAL. Computing the low word with U32s wrap
# and then subtracting the high words is arithmetically WRONG for every borrow:
# `5 - 7` answered hi=0 lo=4294967294, where Python answers hi=4294967295 lo=4294967294
# (that is -2). The low word was right and the high word was wrong, which is the worst
# shape for a bug: `i64_cmp` and `i64_le` were already correct, so any comparison built
# on the sum or difference read a value that disagreed with itself. Found by the onnx
# units i64 halving (nn/onnx.bend, which carries a local repair with these lines named).
#
# Borrow is `lo_a < lo_b`; carry is `lo_a + lo_b < lo_a`, which is U32s wrap detecting
# its own overflow. Both are exact because the low-word arithmetic cannot fail.
def i64_add(+a: I64, +b: I64) -> I64:
  +lo = U32.add(lo32(a), lo32(b))
  +carry = Bool.pick(U32, U32.is_lt(lo, lo32(a)), 1, 0)
  i64_of_hi_lo(U32.add(U32.add(hi32(a), hi32(b)), carry), lo)

def i64_sub(+a: I64, +b: I64) -> I64:
  +lo = U32.sub(lo32(a), lo32(b))
  +borrow = Bool.pick(U32, U32.is_lt(lo32(a), lo32(b)), 1, 0)
  i64_of_hi_lo(U32.sub(U32.sub(hi32(a), hi32(b)), borrow), lo)

# ===========================================================================
# The rest of the 64-bit ALU: bitwise, the shift, the division, the gcd.
#
# All four are two's complement pair operations, so the sign is a property of the
# HIGH WORD and nothing below has to know about it. `i64_add`/`i64_sub` above are
# the two that had to carry and borrow; these are the rest.
#
# `uop/fold.bend`'s `mm.*` block is THIS ARITHMETIC WRITTEN LOCALLY, and its own
# header asks for these to land here first so that it can be deleted rather than
# kept in step. `mixin/dtype.bend` records the same wall from the other side: its
# `Dt.i64_floor_div` / `Dt.i64_cdiv` are `IO(..)` EFFECT SEAMS, so `_min_max`
# cannot call them, and a pure pair operation is the only shape a fold has.
# ===========================================================================

# `a | b` and `a & b`, WORD-WISE, and that is exact rather than approximate: the
# infinite-precision and the 64-bit two's complement readings of `&` and `|` agree
# bit for bit, and `U32`'s wrap IS the 64-bit one. No sign fixup, ever.
def i64_or(+a: I64, +b: I64) -> I64:
  i64_of_hi_lo(U32.or(hi32(a), hi32(b)), U32.or(lo32(a), lo32(b)))

def i64_and(+a: I64, +b: I64) -> I64:
  i64_of_hi_lo(U32.and(hi32(a), hi32(b)), U32.and(lo32(a), lo32(b)))

# "this pair is zero", which is `AND` and NOT `or`. `or` answers true for (0, 5) as
# well as for (0, 0), and that is how a zero magnitude reads as nonzero.
def i64_is_zero(x: I64) -> Bool:
  match x:
    case I64{hi, lo}: Bool.and(U32.is_zero(hi), U32.is_zero(lo))

# A single low bit, and the high word is 0 because neither of its three callers can
# carry into it: the floor correction is at most one, the restoring divider's
# quotient bit sits at a position below 64, and the negation's `+ 1` cannot reach
# past the low word.
def i64_bit(b: U32) -> I64:
  i64_of_hi_lo(0, b)

def i64_one() -> I64:
  i64_bit(1)

def i64_zero() -> I64:
  i64_of_hi_lo(0, 0)

# Two's complement negation is `~x + 1`, and THE `+ 1` CARRIES OUT OF THE LOW WORD
# into the high one -- which is `i64_add` above, already carrying, rather than a
# second copy of the arithmetic. Spelled as `i64_of_hi_lo(~hi, ~lo + 1)` it is the
# plausible version and it is WRONG for every value whose low word is all ones:
# `|0|` comes out 0xFFFFFFFF_00000000 and `-0` comes out 0xFFFFFFFF_00000001, and
# those are `pm_wide_div` and `pm_maxi_mod` in the gate.
#
# `i64_abs` is the same expression with the sign read off the value, and the two are
# NOT one def because they disagree on exactly one input: negating the most negative
# value overflows and taking its magnitude does not.
def i64_not(+x: I64) -> I64:
  i64_of_hi_lo(U32.not(hi32(x)), U32.not(lo32(x)))

def i64_neg(neg: Bool, +x: I64) -> I64:
  Bool.pick(I64, neg, i64_add(i64_not(x), i64_one()), x)

def i64_abs(+x: I64) -> I64:
  i64_neg(i64_is_neg(x), x)

# ---- THE SHIFT -------------------------------------------------------------
#
# `U32.shl` is a ONE-BIT shift and `U32.shln(x, n)` is the n-bit one, so the amount
# is a `Nat`; and `U32.shln` SATURATES to 0 past 31, which is why an amount of 32 or
# more is built out of the low word alone rather than by shifting twice.
#
# `k == 0` AND `k == 32` ARE THE TWO AMOUNTS WHERE THE TWO FORMS MEET, and both are
# answered by the SAME arm: `U32.shrn(lo, 32n)` is 0 and `U32.shln(hi, 0n)` is `hi`.
# That is why the test is `k <= 32` and not `k < 32`.
#
# FOR `k >= 32` THE HIGH WORD COMES FROM `lo` AND ONLY FROM `lo`: `a * 2**k` has high
# word `lo * 2**(k-32)` plus `hi * 2**k` reduced mod 2**32, and the second term is 0
# for every k past 31. Reading `hi` there drops the low word entirely and answers 0
# for `1 << 63`.
#
# THE AMOUNT IS MODULO 2**64, and that is the WIDTH rather than a choice: `1 << 64` is
# `2**64` in Python and 0 here, because the pair is 64 bits wide. `Nat.sub`
# TRUNCATES, so the eagerly-evaluated other arm of the `Bool.pick` is harmless -- for
# `k > 32` it shifts by 0 and the arm is discarded anyway.
def i64_shl.lo(+hi: U32, +lo: U32, +k: Nat) -> I64:
  i64_of_hi_lo(U32.or(U32.shln(hi, k), U32.shrn(lo, Nat.sub(32n, k))), U32.shln(lo, k))

def i64_shl.hi(lo: U32, k: Nat) -> I64:
  i64_of_hi_lo(U32.shln(lo, Nat.sub(k, 32n)), 0)

def i64_shl.put(low: Bool, +hi: U32, +lo: U32, +k: Nat) -> I64:
  Bool.pick(I64, low, i64_shl.lo(hi, lo, k), i64_shl.hi(lo, k))

def i64_shl(+x: I64, +k: Nat) -> I64:
  i64_shl.put(U32.is_le(U32.from_nat(k), 32), hi32(x), lo32(x), k)

# ===========================================================================
# THE 64-STEP UNSIGNED RESTORING DIVIDER
#
# STEP `k` READS DIVIDEND BIT `k` AND WRITES QUOTIENT BIT `k` -- the same index on
# both sides, which is the whole of restoring division -- so the walk counts DOWN
# from 64 and the first bit processed is bit 63 of each.
#
# THE 65TH BIT IS CARRIED AND NOT LOST. `r` is below `d` before every step, so
# `2r + bit` is below `2d` and needs 65 bits; a `U32` shift by 1 drops the top of the
# high word, and that bit is the one that decides the compare below. EVERY FIXTURE
# WITH BOTH OPERANDS BELOW 2**32 READS THE SAME WHETHER IT IS CARRIED OR NOT, so
# `div_2p63_2p62` -- `2**63-1` over `2**62-1` -- is the row that makes this block a
# test rather than a shape check, and `div_1_neg` is its signed twin.
# ===========================================================================

type DivSt is Data:
  DivSt{q: I64, r: I64, up: Bool, sub: Bool}

# `a < b` on the two words, UNSIGNED. The high word decides on its own unless the two
# are equal, and only then does the low word.
def u64_lt(+ah: U32, al: U32, +bh: U32, bl: U32) -> Bool:
  Bool.or(U32.is_lt(ah, bh), Bool.and(U32.is_eq(ah, bh), U32.is_lt(al, bl)))

# STEP `k` READS BIT `k` OF THE DIVIDEND, and `U32.shrn` is a shift and NOT a
# `& 1`, so both arms mask. `Nat.sub` truncating is what makes the other arm of the
# pick harmless: for `k < 32` it reads bit 0 of the high word and throws it away.
def div_bit(bh: U32, bl: U32, +k: Nat) -> U32:
  Bool.pick(U32, U32.is_lt(U32.from_nat(k), 32), U32.and(U32.shrn(bl, k), 1),
    U32.and(U32.shrn(bh, Nat.sub(k, 32n)), 1))

# `r = 2r + bit`. `i64_of_hi_lo` rather than a shift of the whole pair because the
# low word's carry out IS the high word's bit 0, which `U32`'s wrap already computed.
def div_shift(s: DivSt, bit: U32) -> DivSt:
  match s:
    case DivSt{+q, +r, up, sub}:
      DivSt{q, i64_of_hi_lo(U32.or(U32.shln(hi32(r), 1n), U32.shrn(lo32(r), 31n)),
        U32.or(U32.shln(lo32(r), 1n), bit)), U32.is_eq(U32.shrn(hi32(r), 31n), 1), False{}}

# `(up, r) >= d`: ONE subtract is enough, because the invariant is `r < d` before the
# step, so `up` alone already decides the comparison. The compare is `>= d` and NOT
# `<= d`: subtracting on every step where the remainder is merely BELOW the divisor
# answers a quotient of all ones for any dividend smaller than the divisor.
#
# `i64_sub` IS the wrapping unsigned subtract, and not by luck of the sign bit:
# two's complement and unsigned subtraction mod 2**64 are the same bit pattern, and
# the borrow is what keeps the high word right.
def div_fit.put(q: I64, r: I64, d: I64, ge: Bool) -> DivSt:
  match ge:
    case True{}: DivSt{q, i64_sub(r, d), False{}, True{}}
    case False{}: DivSt{q, r, False{}, False{}}

# The compare is a CALL, so it is a `Bool` PARAMETER and the `match` is in the def
# below. One level of `.put`, not two: the alternative is a `Bool.pick` over a record
# it has just built, which needs `+` on both arms for a state nothing else reads.
def div_fit(s: DivSt, +d: I64) -> DivSt:
  match s:
    case DivSt{+q, +r, up, sub}:
      div_fit.put(q, r, d,
        Bool.or(up, Bool.not(u64_lt(hi32(r), lo32(r), hi32(d), lo32(d)))))

# THE QUOTIENT BIT IS AT POSITION `k`, so setting it is an OR of `1 << k` -- which
# REUSES `i64_or` and `i64_shl` above rather than a third shift written here, and an
# unset bit is an OR of zero. So the two arms of the choice collapse into one
# expression and the state's own `sub` flag is the whole of the branch.
def div_qbit(k: Nat, s: DivSt) -> DivSt:
  match s:
    case DivSt{+q, +r, up, sub}:
      DivSt{i64_or(q, i64_shl(i64_bit(Bool.to_u32(sub)), k)), r, up, False{}}

def div_step(+k: Nat, s: DivSt, +n: I64, d: I64) -> DivSt:
  div_qbit(k, div_fit(div_shift(s, div_bit(hi32(n), lo32(n), k)), d))

# The fuel is the FIRST parameter because the self-call's decreasing argument must
# come first, and 64 steps read all 64 bits MSB first. `p` is the only argument of the
# call that is a strict subterm of its parameter, so everything after it is free. The
# `+` is on the SCRUTINEE and not on the binder: `case 1n+p:` spends `p` on the match
# and the step needs it twice, once as the fuel and once as the bit index.
# The answer is UNWRAPPED HERE rather than by a caller, because a `match` on the
# call's own result is a computed scrutinee and this walk has to return one.
def div_loop(+k: Nat, +n: I64, +d: I64, s: DivSt) -> DivMod:
  match k:
    case 0n:
      match s:
        case DivSt{q, r, up, sub}: DivMod{q, r}
    case 1n+p: div_loop(p, n, d, div_step(p, s, n, d))

# ===========================================================================
# `floordiv` / `floormod` ON THE PAIR (helpers.py:76-78) and `math.gcd`
# ===========================================================================

type DivMod is Data:
  DivMod{q: I64, r: I64}

def divmod_q(d: DivMod) -> I64:
  match d:
    case DivMod{q, r}: q

def divmod_r(d: DivMod) -> I64:
  match d:
    case DivMod{q, r}: r

# `i64_div` FLOORS, and it does not truncate, and the difference is a whole unit:
# helpers.py:77 `floordiv(x, y) = x//y` answers -2 for `-7 // 4` where a truncating
# division answers -1. So the truncated MAGNITUDE quotient is stepped UP by one and
# the sign set when the division was INEXACT and the two signs DIFFER; for a
# same-sign division the truncation already IS the floor. That is the same split
# `floordiv_i32` above makes on one word, and it is a split rather than a formula
# because the correction is not symmetric in the signs.
def i64_divmod.up(flip: Bool, r: I64) -> Bool:
  Bool.and(flip, Bool.not(i64_is_zero(r)))

def i64_divmod.q(+d: DivMod, +flip: Bool) -> I64:
  +r = divmod_r(d)
  i64_neg(flip, i64_add(divmod_q(d), i64_bit(Bool.to_u32(i64_divmod.up(flip, r)))))

# THE REMAINDER'S SIGN IS THE DIVISOR'S, which is Python's `%` and NOT a property of
# the magnitudes: `7 % -4` is -1 and `-7 % -4` is -3 and both are negative. Its
# MAGNITUDE is `|a| % |b|` except in the one case where the quotient was stepped up,
# where it is the divisor's magnitude MINUS that remainder -- and that is the only
# place here the divisor's magnitude is needed, so `mb` is a parameter of this def and
# not of the one above.
def i64_divmod.r(d: DivMod, flip: Bool, bn: Bool, mb: I64) -> I64:
  +r = divmod_r(d)
  i64_neg(bn, Bool.pick(I64, i64_divmod.up(flip, r), i64_sub(mb, r), r))

def i64_divmod.put(+d: DivMod, an: Bool, +bn: Bool, mb: I64) -> DivMod:
  +flip = Bool.xor(an, bn)
  DivMod{i64_divmod.q(d, flip), i64_divmod.r(d, flip, bn, mb)}

# THE ZERO DIVISOR ANSWERS THE DIVIDEND FOR THE REMAINDER AND NOT 0, and that is a
# claim about helpers.py:78 rather than about arithmetic: `floormod(x, 0)` is
# `x - floordiv(x,0)*0` and `floordiv(x, 0)` is 0, so the remainder is the dividend.
# A restoring divider run on a zero divisor answers a quotient of all ones, so the
# zero case is a `match` on a `Bool` PARAMETER -- `i64_is_zero(b)` is a call and a
# call cannot be a scrutinee. `div_loop` is evaluated eagerly even for it, which costs
# 64 steps and is the price of not having two entry points.
def i64_divmod.of(zero: Bool, a: I64, +b: I64, d: DivMod) -> DivMod:
  match zero:
    case True{}: DivMod{i64_zero(), a}
    case False{}: i64_divmod.put(d, i64_is_neg(a), i64_is_neg(b), i64_abs(b))

# `i64` and NOT `u64` because the signs are read here and nowhere else, and the
# magnitudes handed to the walk are the only unsigned pair in the block.
def i64_divmod(+a: I64, +b: I64) -> DivMod:
  i64_divmod.of(i64_is_zero(b), a, b, div_loop(64n, i64_abs(a), i64_abs(b),
    DivSt{i64_zero(), i64_zero(), False{}, False{}}))

def i64_div(a: I64, b: I64) -> I64:
  divmod_q(i64_divmod(a, b))


# ---- `i64_dec`: Python's `str(int)`, a SIGNED DECIMAL -----------------------
#
# `i64_text` (above) is the two-word `hi:lo` form and it is DELIBERATELY not this.
# It is right for a gate, where `2147483648:0` says more about a bit pattern than a
# digit string does, and every existing row in the tree prints it. What it cannot do
# is `str(val)`, and `print_uops` (tinygrad/uop/render.py:18) needs exactly that: it
# prints `f"{x.val}"` for a CONST src, where `i64_text` on 4 is `0:4` and CPython
# prints `4`.
#
# WHY IT IS NOT A ONE-LINE. Bend has no signed integers (see the 64-bit block header
# above), so a signed value IS its two's complement bit pattern and the decimal has
# to be built by dividing a MAGNITUDE, with the sign carried beside it.
#
# AND THE FOLD RUNS ON A `Nat` FUEL, WHICH IS THE WHOLE SHAPE. Every step's next
# value is a CALL -- `i64_divmod(divmod_q(d), 10)` -- and Bend REFUSES a computed
# self-call argument: "expected : a decreasing self-call (arguments are read left to
# right: each passed unchanged until one shrinks)". A `match` binder is the only
# accepted shrink, and there is no binder for a computed quotient. The `Nat` fuel
# supplies one (`case 1n+g`), and it is cheap because `Nat` only ever reaches 20
# here. MEASURED, not assumed: eight arrangements were tried -- `go`/`step`, `go`/
# `acc`/`put2`, a `Bool.pick` zero test, a `match` on a `Bool` parameter for lazy
# branching, and a `Step` data type -- and every one of them is either mutually
# recursive (which Bend refuses: "expected : a filled definition") or passes a
# computed argument. The `-law` block that `Nat.show` uses to declare its own
# `go -> fin -> go` cycle is BASE-ONLY syntax; the leading `-` marks a builtin, and
# a user file is told "expected : 'def', 'type' or 'law'".
#
# SO THE FUEL IS DELIBERATELY ONE MORE THAN THE DIGIT COUNT. 2**63-1 is nineteen
# digits and the fuel is 20, so the fold always emits exactly 20 digits and the
# surplus ones are the surplus ZEROS of the magnitude -- which is why `i64_dec.trim`
# exists and why it runs on the REVERSED list: the surplus digits are the MOST
# significant, so on a least-significant-first list they are at the TAIL, and
# trimming the head of the unreversed list removes nothing. (MEASURED: trimming
# before the reverse printed `00000000000000012345`.)
def i64_dec.go(f: Nat, +acc: List<&2, U32>, +d: DivMod) -> List<&2, U32>:
  match f:
    case 0n:
      acc
    case 1n+g:
      i64_dec.go(g, List.append(&2, U32, acc, [lo32(divmod_r(d))]), i64_divmod(divmod_q(d), i64_of_i32(10)))

# `Nil` KEEPS ONE DIGIT, so 0 prints as "0" and not as the empty string. The head
# test is a `Bool.pick` and not a `match` guard because Bend's `match` takes no
# guard expression, and the `+cs` parameter is the only argument the recursion needs
# -- the tail `t` IS the shrink, which is the shape `uncast_const.walk.go` uses.
def i64_dec.trim(+cs: List<&2, U32>) -> List<&2, U32>:
  match cs:
    case Nil{}:
      [0]
    case c <> t:
      Bool.pick(List<&2, U32>, U32.is_zero(c), i64_dec.trim(t), List.append(&2, U32, [c], t))

# Most-significant first, so each digit is APPENDED. A digit is a `U32` and not a
# `Char` because `U32.show` on a digit renders the NUMBER -- `U32.show(48)` is
# "48" -- so the character goes through `Char.from_u32` and `String.from_list`.
# MEASURED: without that, 0 printed as "48".
def i64_dec.text(+cs: List<&2, U32>, +acc: String) -> String:
  match cs:
    case Nil{}:
      acc
    case c <> t:
      i64_dec.text(t, String.append(acc, String.from_list([Char.from_u32(U32.add(c, 48))])))

# THE SIGN IS PREPENDED TO THE WHOLE BODY, and the order matters: pushing a "-" onto
# the head of a not-yet-reversed list would put it on the LAST character.
def i64_dec.put(neg: Bool, +body: String) -> String:
  Bool.pick(String, neg, String.append("-", body), body)

def i64_dec.narrow(+x: I64) -> String:
  i64_dec.put(i64_is_neg(x),
    i64_dec.text(i64_dec.trim(List.reverse(&2, U32, i64_dec.go(20n, Nil{}, i64_divmod(i64_abs(x), i64_of_i32(10))))), SNil{}))

# THE ONE VALUE WHOSE MAGNITUDE DOES NOT FIT, and it is ONE value because the range
# is [-2**63, 2**63-1]: |int64.min| = 2**63, and Bend's `I64` cannot hold 2**63.
# `i64_abs` therefore answers int64.min FOR int64.min -- MEASURED, it returns
# `2147483648:0` unchanged and `i64_is_neg` on that is still True -- so the fold
# would divide a NEGATIVE magnitude and read its digits off a two's complement word.
# Rather than print a wrong answer, this def answers the `hi:lo` bit pattern, which
# is what `i64_text` is for and is the same fallback `viz/serve.bend`'s `dec_of`
# already takes for a value that does not fit.
#
# THE TEST IS THE OBSERVED OVERFLOW AND NOT A MAGIC CONSTANT: "negating left the
# value negative". So it stays true if the range ever widens, and it cannot be
# satisfied by a value that merely happens to be negative.
def i64_dec.of(wide: Bool, +x: I64) -> String:
  Bool.pick(String, wide, i64_text(x), i64_dec.narrow(x))

def i64_dec(+x: I64) -> String:
  i64_dec.of(Bool.and(i64_is_neg(x), i64_is_neg(i64_abs(x))), x)
def i64_mod(a: I64, b: I64) -> I64:
  divmod_r(i64_divmod(a, b))

# `math.gcd(a, b)`, and it is NOT a signed division: the answer is NON-NEGATIVE, and
# that is `math.gcd`'s own guarantee rather than a property of the pair, which is why
# the magnitudes go in. `math.gcd(0, 0)` is 0 and `math.gcd(a)` is `abs(a)`, and both
# fall out of the loop -- the `b == 0` compare sends them straight to `a`.
#
# THE LOOP TESTS `b` AND NOT THE REMAINDER, and that is the load-bearing detail:
# testing `a % b == 0` reaches `i64_mod(a, 0)`, whose zero-divisor answer is the
# DIVIDEND, so `gcd(A, 0)` would recurse to `(0, A)` and answer 0.
#
# THE FUEL IS NOT DECORATIVE. The self-call's second and third arguments are `b` and
# `a % b` and BOTH are computed, so no argument of it is a strict subterm of its
# parameter and the decrease check has nothing to stop at. 128n is the round number
# above Lamé's 92, which is the bound for a pair of magnitudes below 2**64. And
# because `Bool.pick` is STRICT the loop always runs to the fuel, which is the cost of
# not being able to `match` on `i64_is_zero(b)`.
def gcd.go(k: Nat, +a: I64, +b: I64) -> I64:
  match k:
    case 0n: a
    case 1n+p: Bool.pick(I64, i64_is_zero(b), a, gcd.go(p, b, i64_mod(a, b)))

def gcd(a: I64, b: I64) -> I64:
  gcd.go(128n, i64_abs(a), i64_abs(b))

# data64 -- `(data >> 32, data & 0xFFFFFFFF)`; data64_le swaps it. Python's >> is
# arithmetic and the high half of a two's complement 64-bit word IS the
# arithmetic shift, so the pair already comes out in that order.
def data64_hi(r: U32 & U32) -> U32:
  (hi, lo) = r
  hi

def data64_lo(r: U32 & U32) -> U32:
  (hi, lo) = r
  lo

def data64(x: I64) -> U32 & U32:
  match x:
    case I64{hi, lo}: (hi, lo)

def data64_le(x: I64) -> U32 & U32:
  match x:
    case I64{hi, lo}: (lo, hi)

def to_be32(+val: U32) -> U32:
  U32.or(U32.or(U32.shln(U32.and(val, 255), 24n), U32.shln(U32.and(U32.shrn(val, 8n), 255), 16n)),
    U32.or(U32.shln(U32.and(U32.shrn(val, 16n), 255), 8n), U32.and(U32.shrn(val, 24n), 255)))

# to_be64 -- `to_be32(val >> 32) | (to_be32(val & 0xFFFFFFFF) << 32)`, so the
# high word is the byte swap of the LOW word and the low word of the HIGH one.
def to_be64(val: I64) -> I64:
  match val:
    case I64{hi, lo}: I64{to_be32(lo), to_be32(hi)}

# getbits -- `(value >> start) & ((1 << (end - start + 1)) - 1)`. U32.shln
# saturates to 0 past 31, so a 32-wide mask is 0 - 1 = 0xFFFFFFFF, which is the
# right answer; a width over 32 saturates too and is documented.
def bit_mask(w: Nat) -> U32:
  U32.sub(U32.shln(1, w), 1)

def getbits(value: U32, +start: Nat, end: Nat) -> U32:
  U32.and(U32.shrn(value, start), bit_mask(Nat.add(Nat.sub(end, start), 1n)))

# i2u -- `value if value >= 0 else (1 << bits) + value`
def i2u(neg: Bool, bits: Nat, value: U32) -> U32:
  match neg:
    case True{}: U32.add(U32.shln(1, bits), value)
    case False{}: value

# ===========================================================================
# merge_dicts
#
# `{k:v for d in ds for k,v in d.items()}` after checking that no key carries two
# values. Bend's `Map` is string-keyed with an awkward `Map.get`, so a list of
# pairs is the honest representation: it is what `d.items()` yields, it keeps
# insertion order, and the conflict scan is a fold. `None` is Python's RuntimeError
# "contains different values for the same key".
# ===========================================================================

type KV is Data:
  KV{k: String, v: U32}

def kv_key(kv: KV) -> String:
  match kv:
    case KV{k, v}: k

def kv_val(kv: KV) -> U32:
  match kv:
    case KV{k, v}: v

def kv_find.hit(same: Bool, kv: KV) -> Maybe<&1, U32>:
  match same:
    case True{}: Some{kv_val(kv)}
    case False{}: None{}

def kv_find.pick(found: Maybe<&1, U32>, same: Bool, kv: KV) -> Maybe<&1, U32>:
  match found:
    case Some{v}: Some{v}
    case None{}: kv_find.hit(same, kv)

# the scan folds rather than returning early, because first match wins and `pick`
# keeps whatever `found` already holds
def kv_find.go(l: List<&2, KV>, +k: String, found: Maybe<&1, U32>) -> Maybe<&1, U32>:
  match l:
    case Nil{}: found
    case +kv <> t: kv_find.go(t, k, kv_find.pick(found, String.eq(kv_key(kv), k), kv))

def kv_find(l: List<&2, KV>, k: String) -> Maybe<&1, U32>:
  kv_find.go(l, k, None{})

def kv_conflict.pick(found: Maybe<&1, U32>, kv: KV) -> Bool:
  match found:
    case None{}: False{}
    case Some{v}: U32.is_ne(v, kv_val(kv))

# a repeat of the SAME value is not a conflict; Python dedups the pair set first
def kv_conflict(seen: List<&2, KV>, +kv: KV) -> Bool:
  kv_conflict.pick(kv_find(seen, kv_key(kv)), kv)

# The flag rides in the accumulator, not beside the list, so the walk is one call
type Merged is Data:
  Merged{bad: Bool, seen: List<&2, KV>}

def merged_seen(m: Merged) -> List<&2, KV>:
  match m:
    case Merged{bad, seen}: seen

def merged_bad(m: Merged) -> Bool:
  match m:
    case Merged{bad, seen}: bad

def merged_of(bad: Bool, seen: List<&2, KV>) -> Merged:
  Merged{bad, seen}

def merge_dicts.add(conflict: Bool, kv: KV, +m: Merged) -> Merged:
  match conflict:
    case True{}: merged_of(True{}, merged_seen(m))
    case False{}: merged_of(merged_bad(m), List.append(&2, KV, merged_seen(m), [kv]))

def merge_dicts.go(l: List<&2, KV>, +m: Merged) -> Merged:
  match l:
    case Nil{}: m
    case +kv <> t:
      merge_dicts.go(t, merge_dicts.add(kv_conflict(merged_seen(m), kv), kv, m))

# None is Python's RuntimeError: a key carried two different values
def merge_dicts.pick(m: Merged) -> Maybe<&1, List<&2, KV>>:
  match m:
    case Merged{bad, seen}:
      match bad:
        case True{}: None{}
        case False{}: Some{seen}

def merge_dicts(ds: List<&2, List<&2, KV>>) -> Maybe<&1, List<&2, KV>>:
  match ds:
    case Nil{}: Some{Nil{}}
    case d0 <> r: merge_dicts.pick(merge_dicts.go(List.concat(&2, KV, r), merged_of(False{}, d0)))

# ===========================================================================
# partition -- `for s in itr: (ret[0] if fxn(s) else ret[1]).append(s)`.
# `fxn` is a Python callback and a Bend closure cannot be stored, so the predicate
# is a `Sel` tag and each tag is a top-level def. part_test's tags:
# 0 = x > 0, 1 = x < 0, 2 = x == 0, 3 = x is even, anything else = keep all.
# The accumulator is a record so the recursion never needs a `+` on a list;
# `partition` still answers Python's (kept, dropped) pair.
# ===========================================================================

type Parted is Data:
  Parted{yes: List<&2, U32>, no: List<&2, U32>}

# binder order: p is field 1, keep is field 2
def part_put(p: Parted, keep: Bool, h: U32) -> Parted:
  match p:
    case Parted{yes, no}:
      match keep:
        case True{}: Parted{h <> yes, no}
        case False{}: Parted{yes, h <> no}

def part_test(sel: U32, x: U32) -> Bool:
  match sel:
    case 0: U32.is_gt(x, 0)
    case 1: U32.is_lt(x, 0)
    case 2: U32.is_zero(x)
    case 3: U32.is_even(x)
    case _: True{}

def part_go(xs: List<&2, U32>, +sel: U32, p: Parted) -> Parted:
  match xs:
    case Nil{}: p
    case +h <> t: part_go(t, sel, part_put(p, part_test(sel, h), h))

def part_out(p: Parted) -> List<&2, U32> & List<&2, U32>:
  match p:
    case Parted{yes, no}: (yes, no)

def part_yes(r: List<&2, U32> & List<&2, U32>) -> List<&2, U32>:
  (a, b) = r
  a

def part_no(r: List<&2, U32> & List<&2, U32>) -> List<&2, U32>:
  (a, b) = r
  b

def partition(sel: U32, itr: List<&2, U32>) -> List<&2, U32> & List<&2, U32>:
  part_out(part_go(itr, sel, Parted{Nil{}, Nil{}}))

# ===========================================================================
# unwrap / get_single_element
#
# Both Python functions are `assert`s, and an assertion is not a value, so a
# total def cannot say "the caller promised". The faithful total form therefore
# takes the fallback the caller would have died for. `get_single(xs)` answers
# None when the length is not 1, the only case Python's assert rejects.
# ===========================================================================

def unwrap_or(m: Maybe<&1, U32>, d: U32) -> U32:
  match m:
    case Some{v}: v
    case None{}: d

def get_single(xs: List<&2, U32>) -> Maybe<&1, U32>:
  match xs:
    case Nil{}: None{}
    case h <> t:
      match t:
        case Nil{}: Some{h}
        case _: None{}

# ===========================================================================
# GlobalCounters -- `class GlobalCounters`, helpers.py:302
#
# SIX ClassVars (helpers.py:303-308) and one `@staticmethod reset` (:309-310). The
# class has no methods beyond `reset` and no instances anywhere: every write is
# `GlobalCounters.<name> = ...` or `GlobalCounters.<name> += ...` on the CLASS.
#
# THE MUTABLE-STATE ANSWER, since it is the question this block exists to settle.
# Upstream's state lives in the class object and every reader sees the last write.
# Bend has no mutable globals, no `Ref`, no store and no closures, so the state is a
# `Data` VALUE that is threaded: `Counters` in, `Counters` out, and each `bump_*` is
# the one-line rebuild that upstream's `+=` is. That is not a weaker counter, it is
# the same counter:
#   - it COUNTS. `bump_ops` adds `d` to the value that came IN, so a sequence of five
#     bumps accumulates, and the gate runs exactly that sequence and prints the total
#     after each step (`gc_init_ops`, `gc_bumped_ops`) against live CPython.
#   - it CANNOT GO STALE, which is the property a mutable global does not have. There
#     is no second copy to read, so a reader that forgets to thread the newest record
#     gets the OLD value -- a wrong answer the gate can see, not a silently shared
#     cell that is right until someone forgets to update it.
# What threading costs is the caller: `GlobalCounters.reset()` upstream is a statement
# and `GlobalCounters.reset(GlobalCounters.reset())` here is a value the caller must
# use. That is the whole price and it is paid at the one place that owns the record.
#
# `mem_used` and `mem_used_per_device` are the interesting half and `reset` is why:
# the tuple at :310 names FOUR fields, and the source says on :324-325 that the other
# two are "NOT reset". A `reset` that zeroed all six would be a plausible-looking bug
# that no test of the four would catch, so the gate reads `mem_used` and the per-device
# counts AFTER a reset (`gc_after_used`, `gc_after_dev0`, `gc_after_dev3`).
#
# `time_sum_s` is a CPython `float`, i.e. an F64, and it is the one field that cannot
# be incremented here: `base.bend` has no F32 addition. `F32.add` is a `law`
# (base.bend:1556) -- an axiom with no body -- and live code may not call a law, so a
# float accumulator has no expression. The field is carried, typed `F32`, and is
# never written here; `.agents/slop/helpers-oracle.py` measures what CPython does with
# it and prints those rows to STDERR so they are recorded without being diffed.
# TODO(p4) helpers.py:305  `time_sum_s` needs the engine's clock, which is a C effect.
# ===========================================================================

type Counters is Data:
  Counters{global_ops: U32, global_mem: U32, time_sum_s: F32, kernel_count: U32,
           mem_used: U32, mem_used_per_device: List<&2, Mupd>}

def GlobalCounters.init() -> Counters:
  Counters{0, 0, 0.0, 0, 0, Nil{}}

# `reset` (:310). `used` and `devs` ride through UNCHANGED on purpose; see the header.
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

# `mem_used_per_device` is a `defaultdict(int)` (:306) and two of its facts are not a
# number. A READ of a missing key INSERTS a zero, so `mem_used_per_device[9]` on a
# fresh counter answers 0 AND adds key 9. And the key set is INSERTION-ordered, so
# CPython prints {0, 3, 9} as "0,3,9" while a dense row vector indexed by device
# would print "0,1,2,3" -- four keys where Python has three, and a wrong key SET is
# worse than a wrong count because it is also a different `len`. So this is the
# `merge_dicts` idiom already used in this file for Python dicts: a list of pairs,
# which is what `d.items()` yields and what keeps insertion order.
#
# The read-insert is why `mem_used_add(c, dev, 0)` is the port of a dict READ: adding
# zero to a missing key inserts it and reads back zero, which is exactly what
# `defaultdict.__missing__` does. The gate relies on that -- `gc_init`'s two device
# rows are reads, and they leave the key set as {0, 3} before any bump runs.
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

# not found, so append; found, so the rebuilt list already holds the new value
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
# Timing
#
# `class Timing(contextlib.ContextDecorator)`: __enter__ stamps
# time.perf_counter_ns(), __exit__ prints f"{prefix}{et*1e-6:6.2f} ms". A `with`
# is not a term, so the shape becomes a stamp and a report and the caller keeps
# the two calls adjacent.
# ===========================================================================

def Timing.now() -> IO(Nat):
  IO.now()

def Timing.report.text(prefix: String, st: Nat, en: Nat) -> String:
  String.append(String.append(prefix,
    pad_left(f32_fixed(F32.div(U32.to_f32(U32.from_nat(Nat.sub(en, st))), 1000000.0), 2n), 6)), " ms")

def Timing.report.go(enabled: Bool, s: String) -> IO(Unit):
  match enabled:
    case True{}: IO.print(s)
    case False{}: IO.pure(Unit, Unit{})

def Timing.report(enabled: Bool, prefix: String, st: Nat, en: Nat) -> IO(Unit):
  Timing.report.go(enabled, Timing.report.text(prefix, st, en))

# ===========================================================================
# trange -- `def trange(n:int, **kwargs) -> tqdm[int]`, helpers.py:619
#
# The entire body is `return tqdm(range(n), total=n, **kwargs)`, so a `trange` IS its
# `range(n)` with a total attached, and there are no `kwargs` to pass: every call
# site in tinygrad is a bare `trange(k)` (`examples/beautiful_mnist.py:39` is the one
# this block was added for). `Tqdm` therefore holds exactly what `trange` supplies:
# the sequence and the total.
#
# `Tqdm.t` IS THE TOTAL, and the name is upstream's: `tqdm.__init__` (:587) does
# `self.st, self.i, self.n, self.skip, self.t = ..., total`. There is no `total`
# ATTRIBUTE -- the first draft of the oracle hand-typed `t.total` and CPython answered
# `AttributeError: 'tqdm' object has no attribute 'total'`, which is why every row
# here is generated by calling the def instead of by reading it.
#
# The parameter is `U32`, which is the wall. CPython's `n` is an `int` and
# `trange(-3)` answers `t.t == -3` with an EMPTY sequence, because `range(-3)` is
# empty while `total=-3` is a real, negative integer; `base.bend` declares `Nat`,
# `U32` and `F32` and no signed type, so the port does not have a way to hold that and
# `trange(-3)` is a TYPE ERROR rather than a silent 4294967293. Strengthening the
# argument is the same answer `head :: NonEmpty a -> a` gives, and the cost is that
# one upstream input is unrepresentable rather than wrong.
#
# `tqdm`'s presentation state -- `disable`, `desc`, `unit`, `rate`, `n`, `i` and the
# bar itself -- is NOT PORTED, as the NOT PORTED block at the foot of this file says,
# and `trange` does not invent it. One measured consequence is worth recording because
# it is counter-intuitive: `tqdm.__init__`'s `disable` DEFAULT is `False`, not `None`
# (:585), so the `sys.stderr.isatty()` arm is never taken by `trange` and the bar IS
# drawn into a pipe. That is why `.agents/slop/helpers-tc-gate.sh` compares stdout
# only, and why the oracle's `disable` / `desc` / `unit` / `rate` rows go to stderr.
# ===========================================================================

type Tqdm is Data:
  Tqdm{t: U32, seq: List<&2, Nat>}

def trange(+n: U32) -> Tqdm:
  Tqdm{n, List.range(U32.to_nat(n))}

# ===========================================================================
# lines / printable
#
# `lines(fn)` opens a file and readlines()s it, answering [] on FileNotFound or
# OSError; Bend's File.read answers a Result and [] is the Fail arm.
# `printable(loc)` is lines(loc[0])[loc[1]-1].strip() with IndexError ->
# "<missing>".
# ===========================================================================

def lines.done(f: File, value: String) -> IO(List<&2, String>):
  IO.bind(Unit, List<&2, String>, File.close(f),
    u => IO.pure(List<&2, String>, String.lines(value)))

def lines.close(f: File) -> IO(List<&2, String>):
  IO.bind(Unit, List<&2, String>, File.close(f), u => IO.pure(List<&2, String>, Nil{}))

def lines.split(r: File & Result<&1, &1, U32 & String, String>) -> IO(List<&2, String>):
  match r:
    case (f, Done{value}): lines.done(f, value)
    case (f, Fail{error}): lines.close(f)

def lines.read(f: File, max: U32) -> IO(List<&2, String>):
  IO.bind(File & Result<&1, &1, U32 & String, String>, List<&2, String>,
    File.read(f, max), r => lines.split(r))

def lines.go(r: Result<&1, &1, U32 & String, File>) -> IO(List<&2, String>):
  match r:
    case Done{value}: lines.read(value, 33554432)
    case Fail{error}: IO.pure(List<&2, String>, Nil{})

def lines(path: String) -> IO(List<&2, String>):
  IO.bind(Result<&1, &1, U32 & String, File>, List<&2, String>,
    File.open(path, "r"), r => lines.go(r))

def printable.go(got: Maybe<&2, String>) -> String:
  match got:
    case Some{s}: String.trim(s)
    case None{}: "<missing>"

def printable.pick(line: U32, ls: IO(List<&2, String>)) -> IO(String):
  do IO<String>:
    got : List<&2, String> <- ls
    return printable.go(List.get(&2, String, got, Nat.sub(U32.to_nat(line), 1n)))

def printable(path: String, line: U32) -> IO(String):
  printable.pick(line, lines(path))

# ===========================================================================
# NOT PORTED -- tinygrad/helpers.py, and why
#
# The 64-bit signed div/mod (ceildiv64, cdiv64, cmod64, floordiv64, floormod64)
# and the 64-bit integer truncation are C effects, not pure defs: a signed
# 64-bit quotient and a 2^64-1 bound have no U32 encoding. They are declared in
# ./dtype.bend next to the runtime/dtype.c that implements them.
#
# The ContextVar variable LIST is 3 of 61 (the count is measured at the top of this
# file, and the "~40" this line used to carry was wrong by 21). The rest (DEBUG, BEAM,
# NOOPT, DEV, CACHELEVEL, ...) is phase P6: they need FIELDS on the record, and the
# save/restore MECHANIC they need is already ported above -- `Context.__enter__`
# snapshots named keys and `Context.__exit__` writes them back, so P6 is a wider
# `Flags` and a wider `Flags.snap1.go` dispatch, not a new mechanism.
#
# `Target` and `Target.parse` are phase P6 too: they exist to parse DEV, and DEV
# only exists once there is a device to point at.
# `classproperty` is a descriptor: it makes an attribute read as a function.
# Bend has no descriptors, no class of methods and no `getattr`, and every
# ported def here is a top-level function, so there is nothing for it to
# attach to.
# `fromimport(mod, frm)` is a dynamic import. The set of modules is not known
# until the whole port exists, and Bend's imports are leading lines resolved
# before any def runs, so this becomes a compile-time import in the file that
# needs the name.
# `canonicalize_strides` and `strides_for_shape` are `functools.cache`d over
# tuples and belong to shape.bend, which owns the layout IR.
# `getenv` is ported here as `getenv_str` (the `type(default) is str` arm) and
# `getenv_int` (the `int` arm), because Flags and the dtype defaults need the first
# and `DEBUG` needs the second; between them they keep Python's
# `type(default)(os.getenv(key, default))` shape.
# `get_child`, `word_wrap`, `pad_bytes`, `pluralize`, `polyN`,
# `to_function_name`, `select_by_name`, `select_first_inited`,
# `suppress_finalizing`, `panic`, `stderr_log` and `temp` are string, regex and
# reflection helpers for the interpreter-facing surfaces (viz, the object
# dumper, the error printer). They are ported with the module that uses them.
# `is_numpy_ndarray` is a type-identity test against numpy, and numpy is a C
# effect; it is a predicate on the interop layer, not on a Bend value.
# The sqlite disk cache (cache_dir, CACHEDB, db_connection, diskcache_clear,
# diskcache_get, diskcache_put, diskcache, _db_tables, _db_connection, VERSION)
# is a persistent object store with pickle values. Bend has no pickle and no
# object graph to store, so the cache becomes the C-effect arena of P6 and this
# is replaced rather than ported.
# The HTTP machinery (fetch, fetch_fw, _ensure_downloads_dir) is urllib plus a
# temp file plus an atomic rename. It is I/O of exactly the kind the master
# plan puts in runtime/, and its only callers are the weight downloaders.
# The ctypes helpers (from_mv, to_mv, mv_address, to_char_p_p, flat_mv) wrap a
# Python address into a memoryview. Bend's `Array<T>` is already a reference-
# counted buffer, so the arena in P6 owns the memory and these become the
# arena's accessors rather than a port of the casts.
# `trange` IS ported above, as the `range(n)` and the total that `tqdm(range(n),
# total=n)` is. What is left of `tqdm` is its terminal progress bar: ANSI redraw, a
# width from shutil.get_terminal_size and a rate heuristic, plus `disable`, `desc`,
# `unit`, `unit_scale`, `rate`, `n` and `i`. It is pure presentation over a loop the
# caller already owns; the port prints a line per kernel instead (viz.bend, P8).
# `t.__enter__`/`t.__exit__` are the same close-the-bar pair as `Timing` above, which
# IS ported, so the only reason `tqdm` is not is the bar itself.
# `copyreg.pickle(types.CodeType/ModuleType)`, `_serialize_code`,
# `_reconstruct_code` and `_serialize_module` make Python objects picklable.
# Bend has no code objects and no modules to pickle.
# The cProfile-backed `Profiling`, `perf_counter_us`, `TracingKey`,
# `ProfileEvent`, `ProfileRangeEvent`, `ProfilePointEvent`, `cpu_events`,
# `cpu_profile`, `profile_marker` and `_format_fcn` are the Python profiler.
# The events are real behaviour (viz.bend asserts on them) but the data source
# is CPython's own frame stack, which does not exist in Bend; they are rebuilt
# in P8 on the IO.now clock, which is why `Timing` above is ported and
# `Profiling` is not.
# `GlobalCounters` is ported above as `Counters`: six fields, `init`, `reset`, five
# bumps and the per-device dict, threaded like the arena rather than global. Its
# remaining gap is `time_sum_s`, which needs an F32 add that `base.bend` does not
# have (`F32.add` is a law at base.bend:1556), so in P4 the engine's clock writes
# that one field. Nothing else in the class is outstanding.
# `disable_gc` and the DEBUG_GC `gc.callbacks` hook control CPython's collector.
# Bend's collector is the reference count in the runtime, which no def can
# switch off, so these have no meaning here.
# `count` and `Metadata` are tiny value helpers with no caller in the two files
# this phase ports: `Metadata` rides on UOp (P3) and `count` is Python's own
# itertools.count spelled out.
