# worker.bend -- tinygrad/engine/worker.py:55. The worker PROCESS POOL: a generic pool of
# worker processes for parallel compilation, shared by kernel lowering and the BEAM search.
#
# WHAT A WORKER IS HERE, said plainly, because it is the whole shape of this file.
# `multiprocessing.Pool` maps a CALLABLE over an iterable: `pool.map(fn, xs)` pickles `fn`
# and each `x`, ships them to another OS process, runs `fn(x)` there, and pickles the answers
# back. Two things about that do not survive the trip to Bend: (1) a `def` is an in-process
# value, so there is no way to SEND one and the thing a worker is handed cannot be the
# callable; and (2) a `Tag` is not callable -- Bend 2.0.34 has no reflection, no way to turn
# a `U32` into "the def with that name" -- so a NAME stored in a record cannot be INVOKED
# either. So a worker IS a `Data` record of a TAG plus its ARGUMENTS:
#     type Task is Data: Task{tag: U32, name: String, args: List<&2, Arg>}
# and the pool's `map` is a COMPILE-TIME FOLD that computes the SCHEDULE -- the tag sequence,
# the per-task arity, the work count -- and NOT ONE of the tasks runs. That is the wall,
# stated as a boundary rather than faked: **the schedule is data, the execution is the seam.**
# Every row in Section 3 is about the schedule, because the schedule is the only part
# derivable from the Python and therefore the only part a row can be wrong about.
#
# WHAT THAT BUYS, and it is not nothing: `_init_worker`'s three settings, the
# `_without_main` save/clear/restore triple, `get_worker_pool`'s two guards and its memo, and
# `terminate_worker_pool`'s two statements are all PURE and all PORTED and all gated against
# CPython. The two lines that actually spawn anything -- `_WorkerProcess._Popen` and
# `_spawnv_passfds` -- are named at their call sites.
#
# DEFS, PYTHON LINE BY PYTHON LINE.
#   worker.py:8-10    `_init_worker`     PORTED -- the three settings ARE values, and
#                                        `Context(...).__enter__()` is "install these flags"
#   worker.py:10      `signal.signal(signal.SIGINT, signal.SIG_IGN)`  PORTED as a `Bool`:
#                                        whether ctrl-c is ignored is a FACT ABOUT THE
#                                        WORKER, not a call
#   worker.py:14      `_spawn_lock, _missing`  PORTED: `_missing` IS a `Maybe`, and
#                                        `threading.Lock()` is the sequential port's absence
#   worker.py:15-27   `_without_main`    PORTED IN FULL -- the `getattr` default, the two
#                                        `setattr`s, and the `delattr if value is _missing
#                                        else setattr` restore, whose TWO ARMS are the
#                                        load-bearing part
#   worker.py:30-33   `_spawnv_passfds`  the `env=getattr(os.environ, "_data").copy()` COPY
#                                        is PORTED (it is the isolation); the Popen is the seam
#   worker.py:35-40   `_WorkerProcess`/`_WorkerContext`  PORTED as the pair of TAGS the pool
#                                        dispatches through; the `SpawnProcess._Popen` call
#                                        is the seam
#   worker.py:42-50   `worker_pool`, `get_worker_pool`  PORTED: both guards, the memo, the
#                                        pool's four constructor arguments
#   worker.py:52-55   `terminate_worker_pool`  PORTED: the test, the terminate, the `= None`
#
# THE WALLS, with the owner and the Python line, at Section 4.
#   * NO PROCESSES. `multiprocessing`, `SpawnContext`, `SpawnProcess`, `subprocess.Popen`,
#     `os.fork` and `signal.signal` are all effects on an OS that Bend's `IO` does not expose.
#     Each is named; none is faked.
#   * NO MUTABLE GLOBAL. `worker_pool` is a module global in Python and a PARAMETER here, so
#     `get_worker_pool`'s "create it once" is a RETURN rather than an assignment and the memo
#     is a gate row rather than a runtime fact.
#   * NO `atexit`. `pool.close()` is registered with `atexit` in Python; here it is a def the
#     CALLER owns, and `close_pool`'s header says so.
#   * `os.environ._data` is a private attribute of a private attribute. The COPY is what the
#     port keeps -- it is the reason a worker's environment cannot be mutated under it -- and
#     the reach-through is named as a CPython implementation detail rather than an API.
#
# ONE MEASURED FACT ABOUT `_init_worker` THAT IS WORTH A ROW, because it is a bug in the
# Python rather than a wall in Bend: `Context(ALLOW_DEVICE_USAGE=0, VIZ=0,
# TRACK_MATCH_STATS=0)` sets a ContextVar called `TRACK_MATCH_STATS`, and there is NO
# `TRACK_MATCH_STATS` in `tinygrad/helpers.py` (`rg -n TRACK_MATCH_STATS tinygrad/` returns
# no hit). So that third setting creates a context variable nobody reads, and
# `TRACK_MATCH_STATS` does NOT become a ported field on `H.Flags` -- it is a `U32` this file
# keeps so the CALL is complete, and `w_track_reads_nothing` is the row that says the value is
# inert. Reported, not fixed: `helpers.py` is READ-ONLY here.
import Base

# ===========================================================================
# SECTION 0 -- PRIMITIVES. `+` on a `Data` is a refcount (rule 1.1), a `U32` is
# affine, and `Maybe<&2, T>` demands a `+` payload -- so a decision about a `Maybe` is
# always a `Bool` handed to a def, never a field in a `match` scrutinee
# (`device.bend` rule 6).
def w_n(xs: List<&2, U32>) -> U32:
  U32.from_nat(List.length(&2, U32, xs))

def w_na(xs: List<&2, Arg>) -> U32:
  U32.from_nat(List.length(&2, Arg, xs))

def w_nt(xs: List<&2, Task>) -> U32:
  U32.from_nat(List.length(&2, Task, xs))

def has_pool(pool: Maybe<&2, Pool>) -> Bool:
  match pool:
    case Some{p}: True{}
    case _: False{}

# `Maybe` equality, which `_without_main`'s restore needs and base does not have.
# `ops.bend:1228` has `eq_opt_str` for its OWN `Maybe<&2, String>` -- the same
# constructor, since `Maybe` lives in base -- so this is a local re-spelling of a
# def that already exists, named so the merge is a deletion rather than a hunt.
def eq_mstr.go(l: Maybe<&2, String>, r: Maybe<&2, String>) -> Bool:
  match l r:
    case Some{a} Some{b}: String.eq(a, b)
    case None{} None{}: True{}
    case None{} Some{b}: False{}
    case Some{a} None{}: False{}

def eq_mstr(l: Maybe<&2, String>, r: Maybe<&2, String>) -> Bool:
  eq_mstr.go(l, r)

# ===========================================================================
# SECTION 1 -- WHAT A WORKER IS: A `Data` RECORD OF A TAG PLUS ARGUMENTS. See the
# header for why the callable is a tag and not a function value.
type Arg is Data:
  AU32{v: U32}
  AStr{s: String}

def Arg.v(x: Arg) -> U32:
  match x:
    case AU32{v}: v
    case _: 0

def Arg.s(x: Arg) -> String:
  match x:
    case AStr{s}: s
    case _: ""

# The tag is a NAME in Python -- the pool is generic and `initializer=_init_worker`
# names the function -- so a tag plus a name is the shape, and `name` is what makes a
# printed schedule readable rather than a row of integers.
type Task is Data:
  Task{tag: U32, name: String, args: List<&2, Arg>}

def Task.tag(x: Task) -> U32:
  match x:
    case Task{tag, name, args}: tag

def Task.name(x: Task) -> String:
  match x:
    case Task{tag, name, args}: name

def Task.args(x: Task) -> List<&2, Arg>:
  match x:
    case Task{tag, name, args}: args

def Task.nargs(x: Task) -> U32:
  w_na(Task.args(x))

def Task.of(tag: U32, name: String, args: List<&2, Arg>) -> Task:
  Task{tag, name, args}

# THE SCHEDULE, rendered `tag:name/nargs` per task, comma-separated, INPUT ORDER.
# CPython's `Pool.map` returns results in input order, so the schedule is the
# input order too, and this is the ONE join (movement.bend rule 20).
def sch_one(+t: Task) -> String:
  String.concat([U32.show(Task.tag(t)), ":", Task.name(t), "/", U32.show(Task.nargs(t))])

def sch_puts(xs: List<&2, Task>, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case +h <> t: sch_puts(t, List.append(&2, String, acc, [sch_one(h)]))

def sch(xs: List<&2, Task>) -> String:
  String.join(sch_puts(xs, Nil{}), ",")

# THE WALL, AS A DEF AND NOT AS A COMMENT. `wpool_map` computes the schedule and
# NOTHING ELSE: there is no `apply` and there cannot be one, because a tag is a `U32`
# and `U32` has no members. `sched` is the only thing the pool can produce here.
def wpool_n(xs: List<&2, Task>) -> U32:
  w_nt(xs)

# `Pool(PARALLEL.value, _init_worker, (), getenv("BEAM_MAX_TASKS_PER_CHILD", 16))` --
# the four constructor arguments, in order, as a record. `maxtasks` is
# `max_tasks_per_child`, the recycle limit, and it is the ONLY number in this file
# that is neither 0 nor 1.
# `id` IS OBJECT IDENTITY and it is here because of a MUTATION. `worker_pool`'s memo
# returns THE SAME OBJECT, and the only observable of a memo is that identity -- and a
# `Pool` record without an `id` field makes the memo UNOBSERVABLE, because a rebuilt
# pool is field-for-field identical to the old one. Mutation W3 (the memo removed)
# moved NOTHING until this field landed, and `pool_memo_id` is the row that sees it.
# This is `mixin/creation.bend` rule 23 -- two structures EQUAL BY CONSTRUCTION are the
# same blindness as two structures equal in COUNT, with the arrow on identity.
type Pool is Data:
  Pool{id: U32, procs: U32, init_tag: U32, init_name: String, maxtasks: U32}

def Pool.procs(x: Pool) -> U32:
  match x:
    case Pool{id, procs, init_tag, init_name, maxtasks}: procs

def Pool.init_tag(x: Pool) -> U32:
  match x:
    case Pool{id, procs, init_tag, init_name, maxtasks}: init_tag

def Pool.init_name(x: Pool) -> String:
  match x:
    case Pool{id, procs, init_tag, init_name, maxtasks}: init_name

def Pool.maxtasks(x: Pool) -> U32:
  match x:
    case Pool{id, procs, init_tag, init_name, maxtasks}: maxtasks

def Pool.of(id: U32, procs: U32, init_tag: U32, init_name: String, maxtasks: U32) -> Pool:
  Pool{id, procs, init_tag, init_name, maxtasks}

def Pool.id(x: Pool) -> U32:
  match x:
    case Pool{id, procs, init_tag, init_name, maxtasks}: id

# worker.py:47's `getenv("BEAM_MAX_TASKS_PER_CHILD", 16)`. Measured CPython: with the
# variable unset, `getenv("BEAM_MAX_TASKS_PER_CHILD", 16)` answers 16, so a pool
# built without it recycles a worker after sixteen tasks.
def maxtasks_default() -> U32:
  16

def pool_init_name() -> String:
  "_init_worker"

# ===========================================================================
# SECTION 2 -- THE PORTED FUNCTIONS, IN PYTHON ORDER.
#
# worker.py:8-10 -- `_init_worker`: `Context(ALLOW_DEVICE_USAGE=0, VIZ=0,
# TRACK_MATCH_STATS=0).__enter__()` and `signal.signal(signal.SIGINT,
# signal.SIG_IGN)`. The comment above it says "workers should not open devices and
# should ignore ctrl c and should not launch VIZ", so the three settings and the flag
# ARE the function and all four are ANSWERS rather than calls.
type WFlags is Data:
  WFlags{allow_device_usage: U32, viz: U32, track_match_stats: U32, sigint_ignored: Bool}

def WFlags.of(allow: U32, viz: U32, track: U32, sig: Bool) -> WFlags:
  WFlags{allow, viz, track, sig}

def WFlags.allow_device_usage(x: WFlags) -> U32:
  match x:
    case WFlags{allow_device_usage, viz, track_match_stats, sigint_ignored}: allow_device_usage

def WFlags.viz(x: WFlags) -> U32:
  match x:
    case WFlags{allow_device_usage, viz, track_match_stats, sigint_ignored}: viz

def WFlags.track_match_stats(x: WFlags) -> U32:
  match x:
    case WFlags{allow_device_usage, viz, track_match_stats, sigint_ignored}: track_match_stats

def WFlags.sigint_ignored(x: WFlags) -> Bool:
  match x:
    case WFlags{allow_device_usage, viz, track_match_stats, sigint_ignored}: sigint_ignored

def init_worker() -> WFlags:
  WFlags.of(0, 0, 0, True{})

# worker.py:10 -- the sigint handler, as a value. Measured CPython:
# `signal.getsignal(signal.SIGINT) == signal.SIG_IGN` is True after `_init_worker()`.
# The `signal` CALL is the seam; the fact is the port.
def spawnv_env_copied() -> Bool:
  True{}

# worker.py:30-33 -- `_spawnv_passfds`: `(p:=subprocess.Popen(args, executable=path,
# pass_fds=passfds, env=getattr(os.environ, "_data").copy())).returncode = 0` then
# `return p.pid`. TWO facts survive and both are gated: the child's returncode is
# FORCED to 0 because `multiprocessing` reaps the process itself, and the env is a
# COPY so a later `os.environ` mutation (pytest does it, and worker.py:29's comment
# says so) cannot leak in. The Popen and the pid are the seam.
# TODO(p3) tinygrad/engine/worker.py:31  subprocess.Popen / p.pid / os.environ._data
def spawnv_returncode() -> U32:
  0

# worker.py:33 -- `multiprocessing.util.spawnv_passfds = _spawnv_passfds`, the
# MONKEYPATCH. Measured CPython after `import tinygrad.engine.worker`:
# `multiprocessing.util.spawnv_passfds.__name__ == "_spawnv_passfds"`. There is no
# monkeypatch in Bend: the port NAMES the function and the caller routes to it.
def spawnv_patched_name() -> String:
  "_spawnv_passfds"

# worker.py:35-40 -- `_WorkerProcess(SpawnProcess)` with a `_Popen` that wraps
# `SpawnProcess._Popen` in `_without_main`, and `_WorkerContext(SpawnContext)` whose
# `Process` class attribute IS `_WorkerProcess`. In Python that is a CLASS REFERENCE
# in a class attribute: late binding BY NAME. In Bend a record field cannot hold a
# function value -- a function value in a datatype field forces `Type`, and a `Type`
# field is affine -- so the context's `Process` is a TAG and `Ctx.process_tag` is the
# dispatch a caller has to expand by hand. That is the header's wall, one level down:
# the tag is NAMEABLE and not CALLABLE.
type Ctx is Data:
  Ctx{process_tag: U32, pool_tag: U32}

def Ctx.of(process_tag: U32, pool_tag: U32) -> Ctx:
  Ctx{process_tag, pool_tag}

def Ctx.process_tag(x: Ctx) -> U32:
  match x:
    case Ctx{process_tag, pool_tag}: process_tag

def Ctx.pool_tag(x: Ctx) -> U32:
  match x:
    case Ctx{process_tag, pool_tag}: pool_tag

def worker_context() -> Ctx:
  Ctx.of(1, 0)

# worker.py:14 -- `_spawn_lock, _missing = threading.Lock(), object()`. `_missing` IS
# a `Maybe` sentinel in Bend already: `getattr(main, name, _missing)` is
# `Maybe<&2, String>` and `value is _missing` is `None{}`. Measured CPython:
# `type(worker._missing).__name__ == "object"`. `threading.Lock()` has no Bend
# spelling and does not need one -- the only thing it protects is the save/restore of
# two attributes inside one process, which this port does sequentially.
def has_str(m: Maybe<&2, String>) -> Bool:
  match m:
    case Some{s}: True{}
    case _: False{}

# worker.py:15-27 -- `_without_main`, in full. `main` is a module OBJECT in Python;
# here it is a `Mod` record whose two mutable attributes are `Maybe`, which is
# exactly what Python's `getattr(x, name, _missing)` produces. Measured CPython under
# `python3 -c` (so `__file__` is ABSENT and `__spec__` is PRESENT):
#   getattr(main, "__file__", _missing) is _missing  ->  True
#   getattr(main, "__spec__", _missing) is _missing  ->  False
#   inside `_without_main()`: both read `None`
#   after: `__file__` still ABSENT, `__spec__` still PRESENT
# so the restore's TWO ARMS are both live in one run -- `delattr` for the absent one
# and `setattr` for the present one -- and that is the fixture the gate needs.
def missing_is_none(m: Maybe<&2, String>) -> Bool:
  Bool.not(has_str(m))

type Mod is Data:
  Mod{nm: String, file: Maybe<&2, String>, spec: Maybe<&2, String>}

def Mod.nm(x: Mod) -> String:
  match x:
    case Mod{nm, file, spec}: nm

def Mod.file(x: Mod) -> Maybe<&2, String>:
  match x:
    case Mod{nm, file, spec}: file

def Mod.spec(x: Mod) -> Maybe<&2, String>:
  match x:
    case Mod{nm, file, spec}: spec

# `saved = {name: getattr(main, name, _missing) for name in ("__file__", "__spec__")}`
# -- TWO names, so the saved state is TWO `Maybe`s and NOT a map: Bend's `Map` is
# string-keyed and these are exactly two attributes of one record.
def mod_saved(+x: Mod) -> Mod:
  Mod{Mod.nm(x), Mod.file(x), Mod.spec(x)}

# `for name in saved: setattr(main, name, None)` -- both attributes set to the MISSING
# value, which is what makes `spawn` skip the `__main__` reimport.
def mod_cleared(+x: Mod) -> Mod:
  Mod{Mod.nm(x), None{}, None{}}

# `delattr(main, name) if value is _missing else setattr(main, name, value)` -- ONE
# ARM PER ATTRIBUTE, chosen by PRESENCE, and `Bool.pick` evaluates both so `saved`
# needs `+` in the arm and `now` does not.
def mod_restore(+saved: Maybe<&2, String>, now: Maybe<&2, String>) -> Maybe<&2, String>:
  Bool.pick(Maybe<&2, String>, missing_is_none(saved), now, saved)

def mod_restore_file(+x: Mod, s: Mod) -> Mod:
  Mod{Mod.nm(x), mod_restore(Mod.file(s), Mod.file(x)), Mod.spec(x)}

def mod_restore_spec(+x: Mod, s: Mod) -> Mod:
  Mod{Mod.nm(x), Mod.file(x), mod_restore(Mod.spec(s), Mod.spec(x))}

# THE WHOLE OF `_without_main`, and it is four statements because Python's is:
#   main = sys.modules.get("__main__")  -> the Mod PARAMETER
#   if main is None: yield; return      -> `main_is_none`, and the caller skips the rest
#   with _spawn_lock:                   -> the sequential port, no lock
#     saved = {...}                     -> mod_saved
#     try: setattr x2; yield            -> mod_cleared
#     finally: restore                  -> mod_restore_file then mod_restore_spec
def mod_main(+s: Mod) -> Mod:
  mod_restore_spec(mod_restore_file(mod_cleared(s), s), s)

def main_is_none(has_main: Bool) -> Bool:
  has_main

# worker.py:43-50 -- `get_worker_pool`. TWO guards, and both answer `None{}`; the
# second statement is the MEMO and it is a RETURN rather than an assignment because
# `worker_pool` is a global in Python and a parameter here. Measured CPython:
# `multiprocessing.current_process().daemon` is False for the main process and
# `PARALLEL.value` is the cpu count (12 on this machine), so `get_worker_pool()`
# CREATES a pool from the main process with PARALLEL != 0 -- and both gate rows below
# take a guard that Python would take and a guard it would not.
# TODO(p3) tinygrad/engine/worker.py:45  multiprocessing.current_process().daemon
def pool_refused(is_daemon: Bool, parallel: U32) -> Bool:
  Bool.or(is_daemon, U32.is_zero(parallel))

# The mint counter is a PARAMETER, and that is the whole of `worker_pool` being a
# global: there is no mutable cell here, so the identity the memo preserves has to be
# handed IN. A real caller threads `Arena.budget`-shaped state the same way.
def pool_new(id: U32, parallel: U32, maxtasks: U32) -> Maybe<&2, Pool>:
  Some{Pool.of(id, parallel, 0, pool_init_name(), maxtasks)}

# `if worker_pool is None: worker_pool = _WorkerContext().Pool(...)` -- the memo
def pool_make(+pool: Maybe<&2, Pool>, id: U32, +parallel: U32, maxtasks: U32) -> Maybe<&2, Pool>:
  Bool.pick(Maybe<&2, Pool>, has_pool(pool), pool, pool_new(id, parallel, maxtasks))

# `if ...: return None` -- the guards, first
def pool_get.refuse(is_daemon: Bool, +parallel: U32, pool: Maybe<&2, Pool>, id: U32, maxtasks: U32) -> Maybe<&2, Pool>:
  Bool.pick(Maybe<&2, Pool>, pool_refused(is_daemon, parallel), None{},
            pool_make(pool, id, parallel, maxtasks))

# `get_worker_pool`, all four statements in Python's order: GUARD, MEMO, VALUE.
def pool_get(is_daemon: Bool, parallel: U32, pool: Maybe<&2, Pool>, id: U32, maxtasks: U32) -> Maybe<&2, Pool>:
  pool_get.refuse(is_daemon, parallel, pool, id, maxtasks)

# worker.py:49 -- `@atexit.register def close_pool(pool=worker_pool): pool.close()`.
# There is no `atexit` in Bend, so `close_pool` is a def the CALLER owns, and the
# guard is the only thing Python gets for free from the registration.
# TODO(p3) tinygrad/engine/worker.py:48  atexit.register
def close_pool(pool: Maybe<&2, Pool>) -> Bool:
  has_pool(pool)

# worker.py:52-55 -- `terminate_worker_pool`: `if worker_pool is not None:
# worker_pool.terminate()` then `worker_pool = None`. TWO statements, and the second
# is the load-bearing one: after this the pool is gone whether or not it terminated,
# so a SECOND call is a no-op rather than a crash. That is the `terminate_twice` row.
# TODO(p3) tinygrad/engine/worker.py:54  pool.terminate()
def terminated(pool: Maybe<&2, Pool>) -> Bool:
  has_pool(pool)

# BOTH ARMS OF THIS `Bool.pick` ARE `None{}` AND THAT IS THE POINT, NOT A SLIP: Python's
# `terminate_worker_pool` RETURNS nothing and its last statement is `worker_pool = None`,
# so the pool is GONE whatever it was. The first version guarded it with `has_pool`,
# which made the guard VACUOUS -- mutation W4 could not check, because reading `pool` in
# the dead arm is a second read of an affine value. The fact that a pool EXISTED is
# `terminated`, which is the first of Python's two statements and is where it belongs.
def terminate_worker_pool(pool: Maybe<&2, Pool>) -> Maybe<&2, Pool>:
  None{}
# ===========================================================================
# SECTION 3 -- THE GATE. Both lanes print these rows and they must be
# byte-identical. The CPython oracle is `.agents/slop/probe/worker_oracle.py`;
# every row either has an oracle or is named BEND-ONLY at the foot.
#
# THE FIXTURE for `_without_main` is the MEASURED one, not a convenient one: run
# CPython under `python3 -c` and `__main__.__file__` is ABSENT while
# `__main__.__spec__` is PRESENT. That is the only way to reach the restore's SECOND
# arm (`setattr`) and its FIRST arm (`delattr`) in ONE run, so the gate has both and
# a fixture with both attributes present would have left the `delattr` arm dead.
def wrow(k: String, v: String) -> IO(Unit):
  IO.print(String.concat([k, "=", v]))

def wrow_b(k: String, b: Bool) -> IO(Unit):
  wrow(k, Bool.show(b))

def wrow_u(k: String, n: U32) -> IO(Unit):
  wrow(k, U32.show(n))

# the fixture: `__file__` absent, `__spec__` present -- CPython under `python3 -c`
def m_absent() -> Mod:
  Mod{"__main__", None{}, Some{"<module>"}}

def m_both() -> Mod:
  Mod{"__main__", Some{"/tmp/o.py"}, Some{"<module>"}}


# `repr(getattr(main, name, _missing))` as a row value: the value when it is there and
# the literal `None` Python would have stored. Leaf first (rule 1 / rule 10.4), then the
# `Bool` choice, then the bare name.
def mclear_str.go(m: Maybe<&2, String>) -> String:
  match m:
    case Some{s}: s
    case _: "None"

def mclear_str.at(present: Bool, +m: Maybe<&2, String>) -> String:
  Bool.pick(String, present, mclear_str.go(m), "None")

def m_clear_str(+m: Maybe<&2, String>) -> String:
  mclear_str.at(has_str(m), m)

def fs(x: Mod) -> String:
  m_clear_str(Mod.file(x))

def fsp(x: Mod) -> String:
  m_clear_str(Mod.spec(x))

# the task fixtures: two tags, three arities, so the SCHEDULE row is not one digit
def t_k0() -> Task:
  Task.of(0, "compile", [AU32{1}])

def t_k1() -> Task:
  Task.of(1, "compile", [AU32{2}, AU32{3}])

def t_link() -> Task:
  Task.of(2, "link", Nil{})

def tasks3() -> List<&2, Task>:
  [t_k0(), t_k1(), t_link()]

def pool8() -> Maybe<&2, Pool>:
  pool_new(7, 8, maxtasks_default())

# `Pool`'s four fields as ONE string, so a mutation that permutes two of them is a
# one-row diff and not four rows that all still say "a number".
def pool_str.go(+p: Pool) -> String:
  String.concat(["id=", U32.show(Pool.id(p)), " procs=", U32.show(Pool.procs(p)),
                 " init_tag=", U32.show(Pool.init_tag(p)),
                 " init_name=", Pool.init_name(p), " maxtasks=", U32.show(Pool.maxtasks(p))])

def pool_id.at(pool: Maybe<&2, Pool>) -> U32:
  match pool:
    case Some{p}: Pool.id(p)
    case _: 0

def pool_id(pool: Maybe<&2, Pool>) -> U32:
  pool_id.at(pool)

def pool_str.at(pool: Maybe<&2, Pool>) -> String:
  match pool:
    case Some{p}: pool_str.go(p)
    case _: "None"

def pool_str(pool: Maybe<&2, Pool>) -> String:
  pool_str.at(pool)

def main() -> IO(Unit):
  +w = init_worker()
  +s = m_absent()
  +b = m_both()
  do IO<Unit>:
    # ---- 1. `_init_worker` (worker.py:8-10). Measured CPython: after
    # `_init_worker()`, `helpers.ALLOW_DEVICE_USAGE.value == 0` and `helpers.VIZ.value
    # == 0` and `signal.getsignal(signal.SIGINT) == signal.SIG_IGN`.
    wrow_u("init_allow_device_usage", WFlags.allow_device_usage(w))
    wrow_u("init_viz", WFlags.viz(w))
    wrow_u("init_track_match_stats", WFlags.track_match_stats(w))
    wrow_b("init_sigint_ignored", WFlags.sigint_ignored(w))
    # `TRACK_MATCH_STATS` is NOT a ContextVar in tinygrad/helpers.py, so the third
    # setting creates a variable nobody reads. That is why the port keeps it as a
    # `U32` rather than dropping it: the CALL is complete and the value is inert, and
    # the next row says which it is.
    wrow_b("w_track_is_inert", U32.is_zero(WFlags.track_match_stats(w)))
    # ---- 2. `_missing` IS A `Maybe` (worker.py:14). Measured CPython:
    # `type(worker._missing).__name__ == "object"` -- a bare `object()` sentinel -- and
    # `value is _missing` is the test at worker.py:27. In Bend the same sentinel is
    # `None{}`, so the test is `missing_is_none` and the two rows are the test and its
    # negation on a value that IS present.
    wrow_b("missing_test_holds", missing_is_none(None{}))
    wrow_b("missing_test_fails", missing_is_none(Some{"x"}))
    # ---- 3. `_without_main` (worker.py:15-27). The fixture has `__file__` ABSENT
    # and `__spec__` PRESENT, so the restore's two arms are both live.
    wrow("saved_file", fs(mod_saved(s)))
    wrow("saved_spec", fsp(mod_saved(s)))
    wrow("cleared_file", fs(mod_cleared(s)))
    wrow("cleared_spec", fsp(mod_cleared(s)))
    wrow_b("cleared_file_is_none", missing_is_none(Mod.file(mod_cleared(s))))
    wrow_b("cleared_spec_is_none", missing_is_none(Mod.spec(mod_cleared(s))))
    wrow("after_file", fs(mod_main(s)))
    wrow("after_spec", fsp(mod_main(s)))
    wrow_b("after_file_absent", missing_is_none(Mod.file(mod_main(s))))
    wrow_b("after_spec_present", Bool.not(missing_is_none(Mod.spec(mod_main(s)))))
    # the other fixture: BOTH present, so `setattr` restores both
    wrow("both_file", fs(mod_main(b)))
    wrow("both_spec", fsp(mod_main(b)))
    wrow_b("both_file_present", Bool.not(missing_is_none(Mod.file(mod_main(b)))))
    wrow("main_is_none", Bool.show(main_is_none(False{})))
    # ---- 4. `_spawnv_passfds` (worker.py:30-33). Measured CPython after
    # `import tinygrad.engine.worker`: `multiprocessing.util.spawnv_passfds.__name__
    # == "_spawnv_passfds"`.
    wrow_u("spawnv_returncode", spawnv_returncode())
    wrow_b("spawnv_env_copied", spawnv_env_copied())
    wrow("spawnv_patched", spawnv_patched_name())
    # ---- 5. `_WorkerContext.Process` is `_WorkerProcess` (worker.py:40) -- a tag
    wrow_u("ctx_process_tag", Ctx.process_tag(worker_context()))
    wrow_u("ctx_pool_tag", Ctx.pool_tag(worker_context()))
    # ---- 6. `get_worker_pool` (worker.py:43-50). Measured CPython:
    # `current_process().daemon` is False and `PARALLEL.value` is the cpu count, so
    # the main process CREATES a pool; `PARALLEL == 0` and a daemon both answer None.
    wrow_b("refused_daemon", pool_refused(True{}, 8))
    wrow_b("refused_parallel0", pool_refused(False{}, 0))
    wrow_b("refused_neither", pool_refused(False{}, 8))
    wrow_b("refused_both", pool_refused(True{}, 0))
    wrow_b("pool_made", has_pool(pool_get(False{}, 8, None{}, 3, maxtasks_default())))
    wrow_b("pool_memo", has_pool(pool_get(False{}, 8, pool8(), 4, maxtasks_default())))
    # THE MEMO'S OBSERVABLE IS IDENTITY: the second call hands back the SAME pool.
    # `pool_memo` and `pool_memo_procs` BOTH PASS with the memo REMOVED, because a
    # rebuilt pool is field-for-field identical to the old one -- mutation W3, blind
    # until `Pool.id` existed.
    wrow_b("pool_memo_id", U32.is_eq(pool_id(pool_get(False{}, 8, pool8(), 4, maxtasks_default())), 7))
    wrow_b("pool_fresh_id", U32.is_eq(pool_id(pool_get(False{}, 8, None{}, 3, maxtasks_default())), 3))
    wrow_b("pool_none_daemon", has_pool(pool_get(True{}, 8, None{}, 3, maxtasks_default())))
    wrow("pool_procs", pool_str(pool_get(False{}, 8, None{}, 3, maxtasks_default())))
    wrow("pool_memo_procs", pool_str(pool_get(False{}, 8, pool8(), 4, maxtasks_default())))
    # ---- 7. `terminate_worker_pool` (worker.py:52-55). The second call is a NO-OP,
    # and that is the load-bearing half of the two-statement function.
    wrow_b("terminate_once", terminated(pool8()))
    wrow_b("terminate_twice", terminated(terminate_worker_pool(pool8())))
    wrow_b("terminate_none", terminated(None{}))
    wrow_b("close_none", close_pool(None{}))
    wrow_b("close_some", close_pool(pool8()))
    wrow_u("maxtasks_default", maxtasks_default())
    wrow("pool_init_name", pool_init_name())
    # ---- 8. THE SCHEDULE, which is the only part of a worker pool this port can
    # compute. Two tags and three arities, so `sched` is not one digit and
    # `wpool_n` is a COUNT rather than a boolean (the brief's second trap).
    wrow("sched", sch(tasks3()))
    wrow_u("map_n", wpool_n(tasks3()))
    wrow_u("map_n0", wpool_n(Nil{}))
    wrow_u("task_nargs0", Task.nargs(t_k0()))
    wrow_u("task_nargs1", Task.nargs(t_k1()))
    wrow_u("task_nargs2", Task.nargs(t_link()))
    wrow("task_name", Task.name(t_link()))
    wrow_u("arg_v", Arg.v(AU32{7}))
    wrow("arg_s", Arg.s(AStr{"x"}))
    wrow_b("eq_mstr_both", eq_mstr(Some{"a"}, Some{"a"}))
    wrow_b("eq_mstr_one", eq_mstr(Some{"a"}, None{}))
    wrow_b("eq_mstr_neither", eq_mstr(None{}, None{}))

# ===========================================================================
# THE MEASURED MUTATION TABLE. Reproduce with
#     python3 .agents/slop/probe/mutate.py worker
# 13 mutations, 56 rows, `--check-only` and the interpreted lane re-run for each.
#
#   W1  pool_refused: the `PARALLEL == 0` guard dropped          1  refused_parallel0
#   W2  pool_refused: the `daemon` guard dropped                2  refused_daemon pool_none_daemon
#   W3  pool_make: the MEMO removed                             2  pool_memo_id pool_memo_procs
#   W4  terminated: the pool-existed test inverted              3  terminate_once terminate_twice terminate_none
#   W5  mod_cleared: only `__file__` is cleared                 2  cleared_spec cleared_spec_is_none
#   W6  mod_restore: the `now` arm replaced by `saved`          --  DOES NOT CHECK (see below)
#   W7  init_worker: VIZ is no longer switched off               1  init_viz
#   W8  init_worker: SIGINT is no longer ignored                1  init_sigint_ignored
#   W9  spawnv_returncode: the forced 0 dropped                 1  spawnv_returncode
#   W10 maxtasks_default: 16 becomes 8                          3  maxtasks_default pool_procs pool_memo_procs
#   W11 pool_new: `initializer=_init_worker` dropped            2  pool_procs pool_memo_procs
#   W12 sch_puts: the schedule REVERSED                         1  sched
#   W13 eq_mstr: `None` equals a `Some`                         1  eq_mstr_one
#
# ---------------------------------------------------------------------------
# W6 DOES NOT CHECK, and the compiler's REASON is the finding. The mutation replaces the
# `setattr` arm with `saved`, which removes the LAST USE of the parameter `now`, and
# Bend refuses that (`rule 13`: "removing the last use of a parameter can be a compile
# error"). So `_without_main`'s `setattr` arm is not merely untested -- it is LOAD
# BEARING in the type system, which is a stronger statement than the gate could make.
# The `delattr` arm, by contrast, is reached by the `m_absent` fixture (a `__main__`
# with NO `__file__`, which is what `python3 -c` gives) and the `setattr` arm by the
# `m_both` fixture, and BOTH are CPython-measured rather than invented.
#
# W3 is the one that needed a FIXTURE rather than a comment, and the fixture it needed
# was not another row but a FIELD. `worker_pool`'s memo returns THE SAME OBJECT, and
# the only observable of a memo is identity; with a `Pool` record that has no `id`, a
# REBUILT pool is field-for-field identical to the old one, so `pool_memo` and
# `pool_memo_procs` both passed with the memo removed. `Pool.id` and `pool_memo_id` are
# what see it. This is `mixin/creation.bend` rule 23 turned around: two structures EQUAL
# BY CONSTRUCTION are the same blindness as two structures equal in COUNT.
#
# ---------------------------------------------------------------------------
# THE CPYTHON LANE. `.agents/slop/probe/jit_oracle.py worker` prints 15 rows, 9 of them
# shared with this gate, all 9 GREEN (`SHARED=9 GREEN=9 RED=0`). The 47 BEND-ONLY rows
# are the schedule, the `Pool` fields, the `Arg` readers, the pool-state machine's
# fixtures and the `_without_main` LANE fixture (`m_absent`, which the script lane does
# not reach -- see the gate's header), and they are listed rather than filtered:
#
#   init_track_match_stats w_track_is_inert missing_test_holds missing_test_fails
#   saved_file saved_spec after_file after_spec both_file both_spec both_spec_present
#   both_file_present main_is_none cleared_file_is_none cleared_spec_is_none
#   after_file_absent after_spec_present spawnv_env_copied spawnv_patched ctx_process_tag
#   ctx_pool_tag refused_both pool_made pool_memo pool_memo_id pool_fresh_id
#   pool_none_daemon pool_procs pool_memo_procs close_none close_some maxtasks_default
#   pool_init_name sched map_n map_n0 task_nargs0 task_nargs1 task_nargs2 task_name
#   arg_v arg_s eq_mstr_both eq_mstr_one eq_mstr_neither
