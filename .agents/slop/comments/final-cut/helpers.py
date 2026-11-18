import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from cut import apply

F = "tinybendygrad/helpers.bend"

EDITS = [
  # ---- THE HEADER (19 lines) -> 8.
  (1, 19, """# helpers.bend -- tinygrad/helpers.py, the pure and I/O-reachable half.
#
# SCOPE. Four of helpers.py's 646 lines' worth of it is here: the pure list/string/number
# helpers (prod, dedup, argsort, ceildiv, ...); the ContextVar/Context flag machinery, as an
# immutable `Flags` record, plus `Context` itself as a snapshot that is threaded rather than
# pushed; `GlobalCounters`, as a threaded `Counters` record; and the two things that need the
# host, `lines` and `Timing`. The rest is I/O or dynamic Python and is listed, with a one-line
# reason each, in the NOT PORTED block at the end of this file.
#
# GATE. This file has no `main` -- it is imported by 88 others -- so its rows live in
# `.agents/slop/helpers-tc.bend` and are compared against `.agents/slop/helpers-oracle.py` by
# `sh .agents/slop/helpers-tc-gate.sh`, which runs CPython and both Bend lanes.
#
# `truncate` is not one of helpers.py's: it is dtype.py:289, it needs `dtypes`, and it lives in
# ./dtype.bend. The int arm is still P3 and dtype.bend says so."""),

  # ---- THE Flags block (31 lines) -- the COUNTED measurement and the coercion fact.
  (23, 53, """# Flags -- the pure port of ContextVar / Context
#
# helpers.py's ContextVar is a mutable cell keyed by string, and Context is a context manager
# that swaps a group of them and restores on exit. Bend has no global mutable state, so the
# cell becomes a field of an immutable record and the manager becomes "thread a different record
# through" -- which is what `Context(DEFAULT_FLOAT=...)` means. `Flags.defaults` is the module
# import; `Flags.from_env` is the `ContextVar.__init__` `getenv(key, default)`.
#
# The values stay `String` because that is what the ContextVars hold: `ContextVar("DEFAULT_FLOAT",
# "float32")` stores the string "float32" and `dtypes.default_float` calls `to_dtype` on it, so
# the dependency direction is the same as Python's (dtype imports helpers).
#
# The variable list is the subset these two files read, and it is 4 flags out of 146. COUNTED,
# not estimated: upstream declares 61 `ContextVar`s and 85 more read through a bare
# `getenv("KEY", ...)`, and `Flags` implements THREE of the 61 ContextVars -- NO_COLOR,
# DEFAULT_FLOAT, DEFAULT_INT -- plus SUM_DTYPE, which is a bare getenv (dtype.py:223) and not a
# ContextVar at all. So P6 is not a garbage-collection job: every one of the other 57 ContextVars
# is CONSUMED -- `DEBUG` has 119 reads and the lowest is `HCQ_CACHE_THRESH` with 1.
#
# P6 replaces this one record with the full list, and every def that takes a `Flags` keeps its
# shape -- but the SEMANTICS have to be settled first, because `getenv` is
# `type(default)(os.getenv(key, default))` (helpers.py:162), so the coercion is `int` for 51 of
# the 61, `str` for the rest, and `bool` for exactly three: PMA (ops_nv.py:27), SQTT and PMC
# (ops_amd.py:31,34), whose defaults are `abs(VIZ.value) >= 2`. The `bool` case is the one that
# reads as "any non-empty string is true"; the `int` case, which NO_COLOR is, reads an
# int-zero string as False, and that is the bug the old comment below was written on."""),

  # ---- the NO_COLOR coercion -- the MEASUREMENT and the ONE GAP.
  (61, 80, """# `NO_COLOR` is `ContextVar("NO_COLOR", 0)` (helpers.py:239), so `type(default)` is `int`
# and getenv coerces through `int`, NOT through `bool`. `bool(NO_COLOR)` is then
# `bool(int(...))`. MEASURED, 31 probes, live CPython (oracles/nocolor-oracle.rows vs the Bend
# lane):
#   "0", "00", "-0", "+0", "0 " and " 0" all read as 0 and leave COLOUR ON, and
#   "1", "2", "007", "+1", "-1", "1_0", " 1 ", "\\t2" and "2\\n" all read non-zero
#   and switch it OFF. So the rule is not "any text is truthy": that INVERTS every one of those
#   six zeros, and a default-environment gate cannot see an inversion because the default is the
#   only environment it ever runs.
# The Bend side of that comparison was never preserved: `.agents/slop/nocolor-bend.txt` has no
# successor at any path on any ref (its basename is absent from all 18110 paths
# `git rev-list --all --objects` names). Named here rather than quietly dropped.
# So: trim, drop one leading sign, and require what is left to be `[0-9_]` with at least one
# character other than '0'.
# `int()` REFUSES "", "0.0", "1e3", "false" and the rest -- tinygrad does not import -- and a
# refusal is not a value in a total language, so every refused string answers False. False is
# the DEFAULT reading (colour on), so the port never invents colour CPython would not have
# printed. The one measured gap is `Char.is_digit`, which is ASCII, so CPython's other decimal
# digits ("٣") read False here and True there."""),

  # ---- `getenv_int` -- the MEASURED probes and the narrowing.
  (140, 179, """# `getenv_int` -- the other arm of the same `getenv`. This is not a second environment
# mechanism: `IO.get_env` (references/bend/bend2/base.bend:185 symbol=IO.get_env) is the only
# reader and both arms call it. helpers.py:163 is the whole of `getenv`:
#
#     @functools.cache
#     def getenv(key:str, default:Any=0): return type(default)(os.getenv(key, default))
#
# so `default` CHOOSES THE COERCION and a default of `""` gives `str` (`getenv_str` above)
# while a default of `0` gives `int` (here). `DEBUG` is the ContextVar that needs the int arm --
# `DEBUG = ContextVar("DEBUG", 0)`, helpers.py:237 -- and `DEBUG >= 2` is a COMPARISON, so a
# `String` cell cannot carry it. Measured: with `DEBUG="2"` the live object is `<class 'int'> 2`,
# and `int(DEBUG >= 2)` is 1; `DEBUG=""` and `DEBUG="abc"` both make the IMPORT raise
# `ValueError: invalid literal for int() with base 10`, which tinygrad does not catch
# (`.agents/slop/debug_oracle.py`, `dbg_value_*` / `dbg_int_getenv_*` rows).
#
# `int()` IS NOT A REGEX. MEASURED, live CPython, 24 probes:
#   "0" 0   "1" 1   "2" 2   "3" 3   "00" 0   "007" 7   "1_0" 10   "2_0_0" 200
#   " 2 " 2   "\\t2\\n" 2   "+2" 2   "-1" -1
#   "" "_" "1_" "_1" "1__0" "abc" "2.0" "1e3" "0x2"  ALL ValueError
# So: trim, drop ONE leading `+`/`-`, and require what is left to be digits with `_` STRICTLY
# BETWEEN them and at least one digit present. `gi_of_text` is that rule as a three-state walk --
# PRE (no digit yet), MID (a digit just ended), PEND (a `_` just ended, so the next char MUST
# be a digit) -- and DEAD once refused, which is what stops a later digit from resurrecting a
# prefix that already failed.
#
# THE ONE MEASURED GAP IS `Char.is_digit`, which is ASCII: CPython's `int("٣")` is 3 and
# `gi_of_text("٣")` refuses. That is the SAME gap `no_color_of` above already documents for
# `nc_digits`, and it is left as it is rather than fixed twice.
#
# A LEADING `-` REFUSES rather than yielding a negative, and `getenv_int` then answers the
# DEFAULT. That is a real narrowing of CPython's `int`, so it is measured rather than argued:
# CPython's `int("-1")` is `-1` and every threshold in tinygrad is `DEBUG >= N` with `N >= 0`,
# so `-1 >= 2` and the default `0 >= 2` are both False. `debug_ge_neg` in
# `.agents/slop/debug-gate.bend` holds the two sides of that equivalence down. A `U32` cannot
# hold `-1` and the alternative -- an `I64` here and a comparison type change at each of the
# seven sites -- would buy a distinction no site can observe."""),

  # ---- `Context` (41 lines) -- the THREE LINES of upstream and the SNAPSHOT-NOT-STACK fact.
  (334, 374, """# Context -- `class Context(contextlib.ContextDecorator)`, helpers.py:170
#
# THE WHOLE MECHANIC IS THREE LINES of upstream and none of them is `with`:
#   __init__      self.kwargs = kwargs                                   (:171)
#   __enter__     snapshot every named cell, then overwrite it           (:175-176)
#   __exit__      write the snapshot back                                 (:178)
# `ContextVar._cache` (:181) is a class-level dict of cells, so "overwrite a cell" is a mutation
# of a module global and a `with` block is the scope that bounds it. Bend has neither, so the
# block becomes two calls and the snapshot is the VALUE the first one returns: `Context.__enter__`
# answers `Ctx`, which carries BOTH the snapshot and the record now in force, and
# `Context.__exit__` needs the snapshot and the current record to write it back. A caller cannot
# "enter" without doing both halves, because there is no separate enter step to forget.
#
# `old_context` IS A SNAPSHOT, NOT A STACK, and that is the load-bearing fact. `__exit__` (:178)
# replays `self.old_context` onto whatever is CURRENT; it does not pop. Two contexts on the SAME
# key, entered in order A then B and exited in the order A then B, leave the value A wrote, not
# the original -- measured, and it is the `ctx_ooo_df` row in `.agents/slop/helpers-oracle.py`. A
# port that pushed and popped a stack would answer the original value and be wrong. The gate
# nests the pair twice, once in order and once out of order, precisely to tell those two
# readings apart, and a third fixture with DISJOINT keys pins that `__exit__` writes back only
# its OWN kwargs.
#
# `CV` mirrors `Flags` field for field rather than holding one value, and the reason is a
# measurement: `__enter__` assigns the RAW kwarg into the cell and does NOT go back through
# getenv's `type(default)(...)` (:163). So `Context(NO_COLOR="0")` puts the STRING "0" in the
# cell, and `ContextVar.__bool__` (:188) is `bool(self.value)`, where `bool("0")` is True. At
# boot `no_color` is the COERCION of the env string and "0" reads False; inside a `Context` the
# same text reads True. One `String` slot could not carry both, so `CV` keeps the coerced bool
# AND the raw text and `Context.arg` (:171, the kwargs entry) is where the coercion happens ONCE,
# on the way IN. The snapshot (`Flags.snap1`, :175) therefore restores the boot bool and
# `ctx_nc_exit` is 0 where `ctx_nc_enter` is 1.
#
# `_recreate_cm` (:173) is NOT PORTED and there is nothing to port: it exists because
# `ContextDecorator` reuses `self`, so a RECURSIVE use of one instance would overwrite
# `self.old_context` with the inner call's snapshot. Here the snapshot is returned as a value
# instead of being written into the manager, so the hazard has no representation -- two nested
# uses of the same kwargs are two `Ctx` values and neither can reach the other."""),
]

apply(F, EDITS)
