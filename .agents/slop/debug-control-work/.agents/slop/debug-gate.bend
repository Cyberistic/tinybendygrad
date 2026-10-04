# debug-gate.bend -- THE GATE for the seven `DEBUG`-gated prints.
#
#   sh .agents/slop/debug-gate.sh
#
# THE ROWS MOVE. That is the whole point, and it is why the harness is run at FIVE
# levels (unset, 0, 1, 2, 3) and every one of them is diffed against CPython at the
# SAME level: the row NAMES are identical across all five and only the VALUES change.
# A row that passed at both level 0 and level 2 would be a row that cannot see the
# gate. None is like that -- `ar_*`, `st_bad`, `am*` and `mem_plan` are all EMPTY at
# levels unset/0/1 and carry the line at 2/3, except `mem_plan`, which is the ONE
# level-1 site and is empty only at unset/0.
#
# `.agents/slop/debug_oracle.py <level>` is the other side. It CALLS CPython with that
# `DEBUG` and prints the same row names; nothing here is typed from memory.
#
# ---------------------------------------------------------------------------
# WHAT IS UNDER TEST, AND WHERE IT LIVES. Every def is reached THROUGH the real
# port file, never redefined locally: `H.*` is tinybendygrad/helpers.bend,
# `A.*` is schedule/allreduce.bend, `M.*` is schedule/memory.bend, `St.*` is
# nn/state.bend, `AM.*` is runtime/support/am/amdev.bend. `rg '^def (mem_dbg|red_dbg|
# sd_dbg|am_dbg)'` over this file must find nothing -- a harness that gates a COPY is
# what made one unit's mutation table report 0 for all 30 entries.
# ---------------------------------------------------------------------------
import Base
import ./../../tinybendygrad/helpers.bend as H
import ./../../tinybendygrad/LAWS/spec.bend as S
import ./../../tinybendygrad/schedule/allreduce.bend as A
import ./../../tinybendygrad/schedule/memory.bend as M
import ./../../tinybendygrad/nn/state.bend as St
import ./../../tinybendygrad/runtime/support/am/amdev.bend as AM

# ===========================================================================
# ROW PRINTERS. `srow` takes a line of text, and a site below its gate answers
# `name=`, an EMPTY VALUE: the level-0 control is a row that is PRESENT and says
# nothing, not a row that is absent. A missing row is indistinguishable from a site
# that was never wired, which is the failure this unit is about.
# ===========================================================================
def srow(nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

def urow(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

def fired(empty: Bool) -> U32:
  match empty:
    case True{}: 0
    case _: 1

def fires(s: String) -> U32:
  fired(String.is_empty(s))

def b2u(b: Bool) -> U32:
  match b:
    case True{}: 1
    case _: 0

# ===========================================================================
# THE ENV READ. `H.debug()` is the mechanism this unit exists to wire. It is read ONCE
# in `main` and threaded to every site as the standing `dbg` parameter -- this
# repository's convention for a ContextVar (`schedule/allreduce.bend`'s header, "THE
# FLAGS ARE PARAMETERS"). So the five runs differ ONLY in the environment, which is
# exactly how the five CPython lanes differ.
#
# THE `+` ANNOTATION IS WHAT MAKES ONE READ SERVE FORTY ROWS. A bare `d : U32 <- ...`
# binding is single-use, and `+d <- H.debug()` is refused outright with "expected : a
# bound variable", so there is no spelling of a reusable bind. Handing the bound `d`
# to ONE `+d` function is the way: inside, `d` is reusable.
#
# TWO MORE SHAPES THIS FILE HAD TO LEARN, both measured and neither obvious:
#   * a `do IO<Unit>:` block accepts BINDINGS and then ONE final bare TERM. Two binds
#     followed by a bare call is "expected : a term (the keyword 'def' cannot head
#     one)", and the same block without a final term is "expected : a term / observed :
#     end of input". So every block here ends in `IO.print("")` or a bare call.
#   * `IO.bind` needs a `Type` witness for its `R`, which this file has no spelling
#     for, so `_ : Unit <-` is the composition form.
# ===========================================================================
def fired_of_ge(+d: U32, +k: U32) -> U32:
  b2u(H.debug_ge(d, k))

# ===========================================================================
# SITE 1 of 7 -- allreduce.py:16, `DEBUG >= 2`.
#
# `RING`   : ndev=4, numel=300000, RING=1 default, over the 256k threshold.
# `NAIVE`  : ndev=2, numel=100. Both empirical conditions fail.
# `ALL2ALL`: ndev=4, numel=100, ALL2ALL=2 -- the force override, which ignores both
#            empirical conditions, so it prints where the size test would say NAIVE.
# CPython, MEASURED by calling `handle_allreduce` (`.agents/slop/debug_oracle.py`
# `laneA_ar_*`):
#     RING ALLREDUCE 4x300000 | dtypes.f32
#     NAIVE ALLREDUCE 2x100 | dtypes.f32
#     ALL2ALL ALLREDUCE 4x100 | dtypes.f32
# `dtypes.f32` is `str(dtypes.f32)`, MEASURED, and it is the NAME not the alias:
# dtype.py's `__repr__` is `f"dtypes.{self.name}"`, so `str()` of it is the name.
# ===========================================================================
def ar_c_ring() -> A.Cfg: A.Cfg{1, 0, 256000, 0, True{}}
def ar_c_a2f() -> A.Cfg: A.Cfg{0, 2, 256000, 0, True{}}

def ar_ring(d: U32) -> String:
  A.red_dbg(d, A.red_sel(A.red_sh1(300000), 4, ar_c_ring()), 4, 300000, S.single())

def ar_naive(d: U32) -> String:
  A.red_dbg(d, A.red_sel(A.red_sh1(100), 2, ar_c_ring()), 2, 100, S.single())

def ar_a2(d: U32) -> String:
  A.red_dbg(d, A.red_sel(A.red_sh1(100), 4, ar_c_a2f()), 4, 100, S.single())

# ===========================================================================
# SITE 7 of 7 -- memory.py:59, `DEBUG >= 1`. THE ONLY LEVEL-1 SITE.
#
# The port's own plan fixture, rebuilt from `schedule/memory.bend`'s FIXTURE 2 and
# driven through `memory_plan_rewrite` exactly as its `p_*` rows are. CPython,
# MEASURED by calling `memory_plan_rewrite` over the same graph (`laneA_mem_0`):
#     memory reduced from 0.01 MB -> 0.01 MB, 5 -> 2 bufs
# Both MB values round to the SAME two decimals here (12032 and 11776 bytes), and
# that is deliberate: it is what makes this row sensitive to the CONDITION rather
# than to the arithmetic -- drop `!=` and the line disappears even though every
# number in it is still right.
# ===========================================================================
def mem_plan(d: U32) -> String:
  M.mem_dbg(d, M.mem_plan(M.proj_of()))

# THE `!=` CONDITION, REACHABLE. The one plan fixture this repository has DOES save
# bytes (omem 12032 against nmem 11776), so the suppressing arm of `memory.py:59` is
# never taken by `mem_plan` and "print only when there is a saving" and "always print"
# are the same function over that row. MEASURED: the mutation that drops the `!=` moved
# nothing until these two rows existed (`.agents/slop/debug-mutate.txt`). So the two
# sums are PARAMETERS here, and CPython is asked the same question the same way --
# `(omem := S/1e6) != (nmem := S/1e6)` evaluated on the two byte counts.
def mem_cond_same() -> String:
  M.mem_dbg_line(12032, 12032, 5, 2)

def mem_cond_diff() -> String:
  M.mem_dbg_line(12032, 11776, 5, 2)

# ===========================================================================
# SITE 2 of 7 -- state.py:260, `DEBUG >= 2`.
#
# `posixpath` and not `os.path`: `pickle` resolves `os.path.join` to `posixpath.join`,
# so the f-string's `{module}` is `posixpath` although the caller wrote `os.path`.
# MEASURED by calling `torch_load` on a real pickle (`laneA_st_0`):
#     WARNING: returning Dummy for posixpath join
# The two negative rows are the modules that ARE whitelisted (state.py:250) and must
# print NOTHING at any level -- a port whose whitelist test were inverted would pass
# the positive row and fail these.
# ===========================================================================
def st_bad(d: U32) -> String:
  St.sd_dbg(d, "posixpath", "join")

def st_ok1(d: U32) -> String:
  St.sd_dbg(d, "collections", "OrderedDict")

def st_ok2(d: U32) -> String:
  St.sd_dbg(d, "numpy", "ndarray")

# ===========================================================================
# SITES 3, 4, 5, 6 of 7 -- amdev.py:185, :225, :251, :254, all `DEBUG >= 2`.
#
# `devfmt` is `pci_dev.pcibus` (amdev.py:157), a string already in hand. CPython
# cannot produce these lines on this host -- MEASURED, `AMDev(0)` raises
# `AttributeError: 'int' object has no attribute 'pcibus'` -- so the oracle's LANE B
# `exec`s the exact source line at each cited position with the live `DEBUG` and a
# stand-in `self`, and the resulting text is what these rows carry.
# ===========================================================================
def am_malformed(d: U32) -> String: AM.am_dbg_malformed_of(d, "0000:01:00.0")
def am_boot(d: U32) -> String: AM.am_dbg_boot_of(d, "0000:01:00.0")
def am_ip(d: U32) -> String: AM.am_dbg_ip_of(d, "0000:01:00.0", "AM_GFX")
def am_final(d: U32) -> String: AM.am_dbg_final_of(d, "0000:01:00.0")

# ===========================================================================
# THE ENVIRONMENT ROWS. These are the only rows whose value is the ENVIRONMENT rather
# than a threaded parameter, and they are what separates "`DEBUG` is wired" from "the
# sites are gated": `env_value` is `H.debug()` read out of the process, and `env_ge*`
# is the same read through the threshold helper every site uses. They move with the
# environment in lockstep with the site rows, which is the point.
# ===========================================================================
def env_rows(+d: U32) -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- srow("env_value", U32.show(d))
    _ : Unit <- urow("env_ge1", fired_of_ge(d, 1))
    _ : Unit <- urow("env_ge2", fired_of_ge(d, 2))
    _ : Unit <- urow("env_ge3", fired_of_ge(d, 3))
    _ : Unit <- urow("env_ge4", fired_of_ge(d, 4))
    _ : Unit <- urow("env_ge5", fired_of_ge(d, 5))
    _ : Unit <- urow("env_ge6", fired_of_ge(d, 6))
    _ : Unit <- urow("env_ge7", fired_of_ge(d, 7))
    IO.print("")

# ===========================================================================
# THE PIN -- THE GRAPH, HELD FIXED, AND CHECKED.
#
# `DEBUG` CHANGES CONTROL FLOW, so a comparison ACROSS LEVELS is only meaningful if the
# graph cannot move when the level does. `.agents/slop/graphcmp-dbg.bend` solved this for
# graphs and the method transfers whole: hold the thing fixed BY CONSTRUCTION, then CHECK
# it rather than promise it.
#
# BY CONSTRUCTION: `pin_rows` takes NO LEVEL. It has no `dbg` parameter, so there is no
# code path on which the level reaches the plan, and the five numbers it prints cannot
# be a different plan at DEBUG=7 than at DEBUG=0 -- not "should not be", CANNOT be. The
# level enters only `site_rows`, which is a different function.
#
# BY CHECKING: `debug-gate.sh` DIGESTS these five rows plus every other level-invariant
# row, per level, and exits 2 -- a FAILURE, never a verdict -- if two levels disagree.
# A guard nobody can see fire is a guard that does not work; this one is a digest the
# harness recomputes and prints on every run.
#
# CPython's side of the same five numbers is read out of `memory_plan_rewrite`'s OWN
# frame with `sys.settrace` (`debug-gate.py`'s MEM_BODY), because the function returns a
# UOp and not a plan. Nothing here re-implements the plan: `M.mem_plan` is the ported
# `memory_plan_rewrite` and `M.proj_of` is the port's own FIXTURE 2, which is the graph
# `M`'s `p_*` rows already gate.
#
# FIVE ROWS AND NOT FOUR, and the fifth is the interesting one. `total_memory` is
# `sum(nbytes.values()) * 2` (memory.py:45), so CPython's `pin_nbytes` is the SUM read
# from the frame and this one is `pin_tot / 2`. A row that restated `pin_tot` would
# agree with a port that had forgotten the `* 2`; dividing makes the factor load-bearing.
# ===========================================================================
def pin_rows() -> IO(Unit):
  do IO<Unit>:
    +p : M.Planned <- IO.pure(M.Planned, M.mem_plan(M.proj_of()))
    _ : Unit <- urow("pin_bufs", U32.add(M.mem_len(M.Planned.bs(p)),
      M.mem_len(M.Planned.bs(p))))  # PLANTED: wrong at every level
    _ : Unit <- urow("pin_narenas", M.mem_len2(M.Planned.azs(p)))
    _ : Unit <- urow("pin_arenas", M.mem_sum_arena(M.Planned.azs(p)))
    _ : Unit <- urow("pin_tot", M.Planned.tot(p))
    _ : Unit <- urow("pin_nbytes", U32.div(M.Planned.tot(p), 2))
    IO.print("")

# ===========================================================================
# THE FIRES ROWS -- CUMULATIVITY, MEASURED, PER LEVEL, PER SITE.
#
# "Which of the seven gated sites fire when the level is L", as a comma-joined list of
# their names. Not a count: a count cannot name the site that stopped firing, and the
# whole question is per-site. Each of the seven is reached through its REAL port def --
# `M.mem_dbg`, `A.red_dbg`, `St.sd_dbg`, `AM.am_dbg_*_of` -- with the level as the
# threaded `dbg` parameter, so this is the port's own gate and not a harness re-derivation.
#
# THE ROW THAT MATTERS MOST IS THE EMPTY ONE. At L = 7 all seven must still fire. A port
# whose `DEBUG=4` behaved as `DEBUG=1` answers `fires_L7=mem` and CPython answers the
# full seven, so the level cannot silently stop being cumulative. Levels are cumulative
# upstream -- MEASURED by calling CPython's own sites at DEBUG=0..7, and every site fires
# at every level >= its threshold -- and this row is where the port is asked the same
# question rather than assumed to answer it.
#
# THE ORDER OF THE TWO LISTS IS THE CONTRACT: `site_fires` and the name list below are
# index-paired, and CPython pairs them by NAME. A site moved between the two lists would
# answer `mem,am185,...` against `ar,am185,...` and go red, which is the point of pairing
# by name on one side.
# ===========================================================================
# `match` CANNOT SCRUTINISE A COMPUTED VALUE, so each predicate gets its own `.of`
# arm and the wrapper supplies it -- the same two-def shape as `fired`/`fires` above,
# and MEASURED rather than guessed: `match String.is_empty(acc):` is refused with
# "a match cannot scrutinize a computed value: give it its own def".
#
# `+acc` IS LOAD-BEARING IN BOTH WRAPPERS AND MEASURED. A `String` binder is consumed by
# a read, so `fire_sep.of(String.is_empty(acc), acc)` -- which reads `acc` once for the
# predicate and hands it on -- is refused with "acc (consumed more than once)" unless the
# parameter is `+`. Same for `fire_add`'s arm, which reads `acc` both directly and inside
# `fire_sep(acc)`.
def fire_sep.of(e: Bool, +acc: String) -> String:
  match e:
    case True{}: ""
    case _: ","

def fire_sep(+acc: String) -> String:
  fire_sep.of(String.is_empty(acc), acc)

def fire_add.of(empty: Bool, +acc: String, nm: String) -> String:
  match empty:
    case True{}: acc
    case _: String.concat([acc, fire_sep(acc), nm])

def fire_add(+acc: String, nm: String, v: String) -> String:
  fire_add.of(String.is_empty(v), acc, nm)

# `ns` COMES FIRST IN THE SIGNATURE AND THE ORDER IS LOAD-BEARING, measured: a self-call's
# arguments are read LEFT TO RIGHT and each must be passed UNCHANGED until one SHRINKS.
# With `acc` first, `fire_join.go(fire_add(...), ns2, vs2)` is refused as "expected : a
# decreasing self-call" -- `ns2` changes in the SECOND slot before anything has shrunk.
# Putting the shrinking `ns` first makes its own tail `ns2` that first shrink and every
# later argument is then free to change. This is the same measured constraint
# `graphcmp-dbg.bend`'s `s_sites.go` records, for the same reason.
def fire_join.go(ns: List<&2, String>, vs: List<&2, String>, +acc: String) -> String:
  match ns vs:
    case Nil{} _: acc
    case _ Nil{}: acc
    case n1 <> ns2 v1 <> vs2: fire_join.go(ns2, vs2, fire_add(acc, n1, v1))

def fire_join(ns: List<&2, String>, vs: List<&2, String>) -> String:
  fire_join.go(ns, vs, "")

# `+n` BECAUSE THE LEVEL IS READ SEVEN TIMES IN ONE LIST LITERAL, and a `U32` binder is
# consumed by a read: `site_fires(n)` with a bare `n` is refused with
# "n (consumed more than once)" at the list. `fire_row` reads it once for the row name
# and once for `site_fires`, so it is `+` too.
def site_fires(+n: U32) -> List<&2, String>:
  [mem_plan(n), ar_ring(n), st_bad(n), am_malformed(n), am_boot(n), am_ip(n), am_final(n)]

def fire_row(+n: U32) -> IO(Unit):
  srow(String.concat(["fires_L", U32.show(n)]),
       fire_join(["mem", "ar", "st", "am185", "am225", "am251", "am254"], site_fires(n)))

def fires_rows() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- fire_row(0)
    _ : Unit <- fire_row(1)
    _ : Unit <- fire_row(2)
    _ : Unit <- fire_row(3)
    _ : Unit <- fire_row(4)
    _ : Unit <- fire_row(5)
    _ : Unit <- fire_row(6)
    _ : Unit <- fire_row(7)
    IO.print("")

# ===========================================================================
# THE THRESHOLDS, MEASURED RATHER THAN DECLARED. `thr_<site>` is "does this site's
# own line appear when the level is EXACTLY 1", computed by CALLING the site. It is
# the row that separates the one level-1 site from the six level-2 sites, and CPython's
# side is the same question answered by the live function's stdout. These rows are
# CONSTANT ACROSS ALL FIVE RUNS, and that is correct: they do not read the environment,
# they fix the THRESHOLD. A gate that asserted `thr_mem=1` and `thr_ar=0` in prose
# would be worth nothing; here both numbers are produced by the code under test.
# ===========================================================================
def thr_rows() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- urow("thr_mem", fires(mem_plan(1)))
    _ : Unit <- urow("thr_ar", fires(ar_ring(1)))
    _ : Unit <- urow("thr_st", fires(st_bad(1)))
    _ : Unit <- urow("thr_am185", fires(am_malformed(1)))
    _ : Unit <- urow("thr_am225", fires(am_boot(1)))
    _ : Unit <- urow("thr_am251", fires(am_ip(1)))
    _ : Unit <- urow("thr_am254", fires(am_final(1)))
    IO.print("")

# ===========================================================================
# `getenv_int`, DIRECTLY, on twenty-two texts with CPython's `int()` as the expected
# value. `"1_0"` and `"2_0_0"` are in here because `_` is legal BETWEEN digits and a
# port that read only `[0-9]` would refuse them; `"1_"`, `"_1"`, `"1__0"`, `""`,
# `"abc"`, `"2.0"`, `"1e3"`, `"0x2"` and `"_"` are in here because CPython REFUSES
# them and a port that accepted them would read a level CPython never had.
#
# A REFUSED TEXT ANSWERS THE DEFAULT HERE WHERE CPython RAISES `ValueError` AT IMPORT.
# That is a real narrowing -- a total language has no `raise` -- so it is a row pair
# rather than a comment: `gi_refuse_*` asks CPython's `int()` and this `gi_of_text`'s
# answer for the same text, and the two are compared side by side. `gi_m1_ge2` is the
# other narrowing: `int("-1")` is `-1` in CPython and a `U32` cannot hold a negative,
# so the port answers the default -- and since every threshold in tinygrad is
# `DEBUG >= N` with `N >= 0`, the two answers are indistinguishable at every site.
# ===========================================================================
# A REFUSAL ANSWERS THE DEFAULT, and that is how the harness can REPORT one without a
# second parser: `gi_of_text(s, 0)` and `gi_of_text(s, 7)` answer the SAME number
# exactly when the text was ACCEPTED -- a refusal answers each default and so the two
# differ. So the row is the value, or the word `ValueError` -- the same word CPython
# raises -- and both sides of the gate say it. Printing the port's `0` for a refusal
# instead would be a green row that hid a narrowing behind a different value, and
# printing `ValueError` unconditionally would make the eleven accepted rows lie.
#
# THE FLAG IS NAMED FOR WHAT IT MEANS, WHICH IS THE OPPOSITE OF WHAT I FIRST CALLED
# IT. `gi_leaks` was the first name and the first run answered `ValueError` for `0`,
# `1` and `007` -- i.e. it fired on every ACCEPTED text, because "leaks the default"
# is the refusal and the equality is the acceptance. Twenty-one rows of exactly the
# wrong answer is what caught it.
def gi_parsed(+s: String) -> Bool:
  U32.is_eq(H.gi_of_text(s, 0), H.gi_of_text(s, 7))

def gi_row.text(ok: Bool, +s: String) -> String:
  match ok:
    case True{}: U32.show(H.gi_of_text(s, 0))
    case _: "ValueError"

def gi_row.of(ok: Bool, nm: String, +s: String) -> IO(Unit):
  srow(nm, gi_row.text(ok, s))

def gi_row(nm: String, +s: String) -> IO(Unit):
  gi_row.of(gi_parsed(s), nm, s)

# THE NEGATIVE-VALUE NARROWING, AS THREE MEASURED ROWS. `int("-1")` is `-1` in
# CPython and a `U32` cannot hold a negative, so `gi_of_text` answers the default `0`.
# Every threshold in tinygrad is `DEBUG >= N` with `N >= 0`, so the two values are
# indistinguishable AT EVERY SITE -- and these three rows are the measurement of that
# claim rather than the claim: CPython's side is `int(-1 >= N)` on the real value and
# the harness's is `int(H.gi_of_text("-1", 0) >= N)`, and all three are 0 on both.
def gi_neg_rows() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- urow("gi_m1_ge1", fired_of_ge(H.gi_of_text("-1", 0), 1))
    _ : Unit <- urow("gi_m1_ge2", fired_of_ge(H.gi_of_text("-1", 0), 2))
    _ : Unit <- urow("gi_m1_ge3", fired_of_ge(H.gi_of_text("-1", 0), 3))
    IO.print("")

def gi_rows() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- gi_row("gi_0", "0")
    _ : Unit <- gi_row("gi_1", "1")
    _ : Unit <- gi_row("gi_2", "2")
    _ : Unit <- gi_row("gi_3", "3")
    _ : Unit <- gi_row("gi_00", "00")
    _ : Unit <- gi_row("gi_007", "007")
    _ : Unit <- gi_row("gi_1_0", "1_0")
    _ : Unit <- gi_row("gi_2_0_0", "2_0_0")
    _ : Unit <- gi_row("gi_sp2", " 2 ")
    _ : Unit <- gi_row("gi_tab2", "\t2\n")
    _ : Unit <- gi_row("gi_p2", "+2")
    _ : Unit <- gi_row("gi_refuse_1_", "1_")
    _ : Unit <- gi_row("gi_refuse__1", "_1")
    _ : Unit <- gi_row("gi_refuse_1__0", "1__0")
    _ : Unit <- gi_row("gi_refuse_us", "_")
    _ : Unit <- gi_row("gi_refuse_abc", "abc")
    _ : Unit <- gi_row("gi_refuse_dot", "2.0")
    _ : Unit <- gi_row("gi_refuse_exp", "1e3")
    _ : Unit <- gi_row("gi_refuse_hex", "0x2")
    _ : Unit <- gi_row("gi_refuse_empty", "")
    _ : Unit <- gi_neg_rows()
    IO.print("")

# ===========================================================================
# `mem_mb`, THE FORMATTER. Every `mem_mb_*` row is a MULTIPLE OF 256, which is the
# precondition `mem_mb`'s comment claims and the population the formatter is right on:
# MEASURED, half-even-on-the-rational agrees with CPython's own `%.2f` on all 156250
# multiples of 256 up to 40 MB. 128000, 384000 and 896000 are here because they sit
# NEAR the tie (`S % 10000 == 5000`) that the 256 block size makes unreachable, so
# they are the rows that would notice if a mutation widened the rounding.
#
# THE NON-MULTIPLES ARE NOT ROWS, DELIBERATELY. On bare integers the same code
# disagrees with CPython: CPython's `f"{0.015:.2f}"` is `'0.01'` where half-even on
# the rational `15/10000` answers `'0.02'`, because Python formats the BINARY FLOAT
# and the double for 0.015 sits below it. MEASURED, 483 such integers in the first
# 40000. A row in this file is diffed against CPython, so a row from that population
# would have to FAIL by construction -- putting it here would make the gate red for a
# documented narrowing, and leaving it out hides it. It is in
# `.agents/slop/notes/bend2-constraints.md` (appended, dated) and in the report.
# ===========================================================================
def mb_row(nm: String, n: U32) -> IO(Unit):
  srow(nm, M.mem_mb(n))

def mb_rows() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- mb_row("mem_mb_256_0", 0)
    _ : Unit <- mb_row("mem_mb_256_12032", 12032)
    _ : Unit <- mb_row("mem_mb_256_11776", 11776)
    _ : Unit <- mb_row("mem_mb_256_8388608", 8388608)
    _ : Unit <- mb_row("mem_mb_256_4194304", 4194304)
    _ : Unit <- mb_row("mem_mb_256_256000", 256000)
    _ : Unit <- mb_row("mem_mb_256_512000", 512000)
    _ : Unit <- mb_row("mem_mb_256_128000", 128000)
    _ : Unit <- mb_row("mem_mb_256_384000", 384000)
    _ : Unit <- mb_row("mem_mb_256_896000", 896000)
    IO.print("")

# ===========================================================================
# THE LEVEL SWEEP, in one place so the levels cannot drift from the oracle's. The
# `*_L0` / `*_L1` rows are the EXPLICIT level-1-vs-level-2 pair: for a `>= 2` site
# both are empty while the level-2 row above carries the line, and for `mem` `_L0` is
# empty and `_L1` is the line. One diff across two levels is what makes "level 1
# differs from level 2" a measurement rather than a claim.
# ===========================================================================
def sweep_row(+n: U32) -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- srow(String.concat(["mem_L", U32.show(n)]), mem_plan(n))
    _ : Unit <- srow(String.concat(["ar_ring_L", U32.show(n)]), ar_ring(n))
    _ : Unit <- srow(String.concat(["st_bad_L", U32.show(n)]), st_bad(n))
    _ : Unit <- srow(String.concat(["am185_L", U32.show(n)]), am_malformed(n))
    _ : Unit <- srow(String.concat(["am251_L", U32.show(n)]), am_ip(n))
    IO.print("")

def sweep_rows() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- sweep_row(0)
    _ : Unit <- sweep_row(1)
    _ : Unit <- sweep_row(2)
    IO.print("")

# ===========================================================================
# THE SEVEN SITE ROWS, AT THE LEVEL THE ENVIRONMENT SAYS.
# ===========================================================================
def site_rows(+d: U32) -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- srow("ar_ring", ar_ring(d))
    _ : Unit <- srow("ar_naive", ar_naive(d))
    _ : Unit <- srow("ar_a2", ar_a2(d))
    _ : Unit <- srow("mem_plan", mem_plan(d))
    _ : Unit <- srow("mem_cond_same", mem_cond_same())
    _ : Unit <- srow("mem_cond_diff", mem_cond_diff())
    _ : Unit <- srow("st_bad", st_bad(d))
    _ : Unit <- srow("st_ok1", st_ok1(d))
    _ : Unit <- srow("st_ok2", st_ok2(d))
    _ : Unit <- srow("am185", am_malformed(d))
    _ : Unit <- srow("am225", am_boot(d))
    _ : Unit <- srow("am251", am_ip(d))
    _ : Unit <- srow("am254", am_final(d))
    IO.print("")

# `main` READS THE ENVIRONMENT ONCE AND HANDS IT TO ONE FUNCTION. Two `_ <- rows(d)`
# binds in one block is "expected : d / observed : d (consumed more than once)" --
# so the bind is single-use even across calls, and the way out is to put EVERY row
# group inside the one `+d` function that receives it.
def all_rows(+d: U32) -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- env_rows(d)
    _ : Unit <- gi_rows()
    _ : Unit <- mb_rows()
    _ : Unit <- site_rows(d)
    _ : Unit <- thr_rows()
    _ : Unit <- sweep_rows()
    _ : Unit <- pin_rows()
    _ : Unit <- fires_rows()
    IO.print("")

def main() -> IO(Unit):
  do IO<Unit>:
    d : U32 <- H.debug()
    _ : Unit <- all_rows(d)
    IO.print("")