#!/usr/bin/env python
# helpers-oracle.py -- the CPython side of the `trange` / `GlobalCounters` /
# `Context` gate for tinybendygrad/helpers.bend.
#
#   DEFAULT_FLOAT=f16 DEFAULT_INT=i64 NO_COLOR=0 \
#     .venv/bin/python .agents/slop/helpers-oracle.py
#
#   sh .agents/slop/helpers-tc-gate.sh        # runs it, both Bend lanes, and diffs
#
# EVERY row is produced by CALLING the real defs in tinygrad/helpers.py:637
# (`trange`), :319 (`GlobalCounters`) and :187 (`Context`). Nothing here is typed
# from memory; `cat` the file if you want to check a row.
#
# WALL 2, MEASURED AND HONOURED: `getenv` is `@functools.cache`d (helpers.py:162),
# so a `ContextVar`'s value is read from the environment ONCE at import and every
# later read is that constant. A process that read the default env can never see a
# non-default one. So the gate runs this file with the non-default env it wants and
# the Bend lane with the SAME env, and every `Context` row's answer is then a
# function of the ENVIRONMENT rather than of the hard-coded default -- which is the
# whole point of the `ctx_boot_*` and `ctx_exit_df` rows.
#
# STDOUT is the gate. Every measurement that the port cannot reproduce goes to
# STDERR with a `#ungated` prefix, so it is measured and kept but never diffed.
# Those are: `tqdm`'s `disable`/`desc`/iterator type (presentation state, declared
# NOT PORTED in helpers.bend), `ContextVar._cache`'s key set (61 ContextVars
# upstream, 4 in this file's `Flags`), and `time_sum_s` after an increment, which
# is `F32.add` -- a LAW at base.bend:1556, which live code may not call.
import sys
from tinygrad.helpers import trange, GlobalCounters, Context, ContextVar

def s(v) -> str: return str(v)
def un(tag: str, v) -> None: print(f"#ungated {tag}={s(v)}", file=sys.stderr)

# ---------------------------------------------------------------- trange
# helpers.py:637  `def trange(n:int, **kwargs) -> tqdm[int]: return tqdm(range(n),
# total=n, **kwargs)`. So `t.iterable` IS `range(n)` and `t.t` IS the total it was
# GIVEN (helpers.py:587 stores it in `t`, and there is no `total` attribute -- the
# first draft of this oracle hand-typed `t.total` and raised
# `AttributeError: 'tqdm' object has no attribute 'total'`). LENGTH, FIRST, LAST and
# the JOINED SEQUENCE are all printed because `trange(3)` and a range that started at
# 1 print the same three values, and only the first element and the length tell them
# apart.
for n in (0, 1, 2, 3, 5):
  t = trange(n)
  xs = list(t)
  print(f"trange_{n}_len={s(len(xs))}")
  print(f"trange_{n}_first={'none' if len(xs) == 0 else s(xs[0])}")
  print(f"trange_{n}_last={'none' if len(xs) == 0 else s(xs[-1])}")
  print(f"trange_{n}_seq={','.join(s(x) for x in xs)}")
  print(f"trange_{n}_t={s(t.t)}")
  un(f"trange_{n}_iterable", type(t.iterable).__name__)
  # `tqdm.__init__`'s `disable` default is `False`, not `None` (helpers.py:585), so
  # the `sys.stderr.isatty()` arm is never taken by `trange` and the bar is drawn
  # even into a pipe. MEASURED with isatty False: `disable False`. That is why the
  # gate compares STDOUT only -- the bar goes to stderr.
  un(f"trange_{n}_disable", int(t.disable))
  un(f"trange_{n}_desc", repr(t.desc))
  un(f"trange_{n}_unit", repr(t.unit))
  un(f"trange_{n}_rate", t.rate)

# ------------------------------------------------------- GlobalCounters
# helpers.py:319 `class GlobalCounters`, six ClassVars: global_ops, global_mem,
# time_sum_s, kernel_count, mem_used, mem_used_per_device. The last is a
# `defaultdict(int)` whose whole point is that READING a missing key INSERTS a 0,
# which is what `gc_default_*` below exercises.
G = GlobalCounters
def gc(tag: str) -> None:
  print(f"{tag}_ops={s(G.global_ops)}")
  print(f"{tag}_mem={s(G.global_mem)}")
  print(f"{tag}_kernels={s(G.kernel_count)}")
  print(f"{tag}_used={s(G.mem_used)}")
  print(f"{tag}_dev0={s(G.mem_used_per_device[0])}")
  print(f"{tag}_dev3={s(G.mem_used_per_device[3])}")
  un(f"{tag}_time_s", G.time_sum_s)

gc("gc_init")
G.global_ops += 5
G.global_ops += 7
G.global_mem += 1024
G.kernel_count += 1
G.kernel_count += 1
G.kernel_count += 1
G.mem_used += 4096
G.mem_used_per_device[3] += 11
G.mem_used_per_device[3] += 4
G.mem_used_per_device[0] += 1
G.time_sum_s += 0.25          # NOT GATED -- see the header
G.time_sum_s += 0.125         # NOT GATED -- see the header
gc("gc_bumped")
# the defaultdict read that was never written: this INSERTS 0 at key 9
print(f"gc_default_read={s(G.mem_used_per_device[9])}")
# INSERTION order, not sorted: CPython's dict is insertion-ordered and the order is
# observable, so this row says {3, 0, 9} reads back "3,0,9". A dense row vector
# indexed by device would answer "0,1,2,3" -- four keys where Python has three --
# which is why `mem_used_per_device` is an assoc list and not an array.
print(f"gc_default_keys={','.join(s(k) for k in G.mem_used_per_device)}")
# helpers.py:327 `def reset(): ...global_ops, global_mem, time_sum_s,
# kernel_count = 0,0,0.0,0` -- mem_used and mem_used_per_device are NOT in that tuple
# and the source says so on :324-325 ("NOTE: this is not reset"). The `gc_after_*`
# rows are that negative case: a reset that zeroed all six would move them.
G.reset()
gc("gc_after")

# ------------------------------------------------------------- Context
# helpers.py:187. `__enter__` snapshots `ContextVar._cache[k].value` for every kwarg
# and then overwrites those cells; `__exit__` writes the snapshot back. The snapshot
# is PER INSTANCE, not a stack, so exiting two contexts out of order does NOT unwind
# to the original values -- it replays the OLDER snapshot onto whatever is current.
# `ctx_ooo_df` is that row and it is the whole reason the port threads a snapshot
# record instead of popping a stack.
print(f"ctx_boot_df={s(ContextVar._cache['DEFAULT_FLOAT'].value)}")
print(f"ctx_boot_di={s(ContextVar._cache['DEFAULT_INT'].value)}")
print(f"ctx_boot_nc={s(int(bool(ContextVar._cache['NO_COLOR'].value)))}")

a = Context(DEFAULT_FLOAT="bfloat16")
a.__enter__()
print(f"ctx_enter_df={s(ContextVar._cache['DEFAULT_FLOAT'].value)}")
print(f"ctx_enter_di={s(ContextVar._cache['DEFAULT_INT'].value)}")
a.__exit__()
print(f"ctx_exit_df={s(ContextVar._cache['DEFAULT_FLOAT'].value)}")

# two contexts OVERLAPPING on the same key, exited in order
c1 = Context(DEFAULT_FLOAT="bfloat16"); c2 = Context(DEFAULT_FLOAT="float64")
c1.__enter__(); c2.__enter__()
print(f"ctx_in2_df={s(ContextVar._cache['DEFAULT_FLOAT'].value)}")
c2.__exit__()
print(f"ctx_lifo_mid_df={s(ContextVar._cache['DEFAULT_FLOAT'].value)}")
c1.__exit__()
print(f"ctx_lifo_df={s(ContextVar._cache['DEFAULT_FLOAT'].value)}")

# the same two, exited OUT OF ORDER
c1 = Context(DEFAULT_FLOAT="bfloat16"); c2 = Context(DEFAULT_FLOAT="float64")
c1.__enter__(); c2.__enter__()
c1.__exit__()          # restores the boot value, overwriting c2's float64
print(f"ctx_ooo_mid_df={s(ContextVar._cache['DEFAULT_FLOAT'].value)}")
c2.__exit__()          # restores c1's bfloat16, NOT the boot value
print(f"ctx_ooo_df={s(ContextVar._cache['DEFAULT_FLOAT'].value)}")
un("ctx_ooo_leaked_df", ContextVar._cache['DEFAULT_FLOAT'].value)

# DISJOINT keys, exited out of order. `__exit__` writes back only ITS OWN kwargs, so
# c1 exiting first cannot revert c2's DEFAULT_FLOAT. A port that restored the whole
# snapshot RECORD instead of the snapshot KEY LIST fails `ctx_disj_mid_df`. Note the
# starting value is bfloat16, not the boot f16: the out-of-order pair above LEAKED
# it, and `__exit__` replayed a snapshot rather than unwinding.
d1 = Context(DEFAULT_INT="int64"); d2 = Context(DEFAULT_FLOAT="float64")
d1.__enter__(); d2.__enter__()
d1.__exit__()
print(f"ctx_disj_mid_df={s(ContextVar._cache['DEFAULT_FLOAT'].value)}")
print(f"ctx_disj_mid_di={s(ContextVar._cache['DEFAULT_INT'].value)}")
d2.__exit__()
print(f"ctx_disj_df={s(ContextVar._cache['DEFAULT_FLOAT'].value)}")
print(f"ctx_disj_di={s(ContextVar._cache['DEFAULT_INT'].value)}")

# helpers.py:189 `ContextVar.__bool__` is `bool(self.value)` and `__enter__` assigns
# the RAW kwarg into the cell -- it does NOT go back through getenv's
# `type(default)(...)`. So `Context(NO_COLOR="0")` puts the STRING "0" in the cell
# and `bool("0")` is True, where the env read of NO_COLOR="0" is the int 0 and False.
# `ctx_boot_nc` above is 0 for exactly that env; this row is 1. It is the only row in
# the file where the port must NOT reuse `no_color_of`.
n1 = Context(NO_COLOR="0"); n1.__enter__()
print(f"ctx_nc_enter={s(int(bool(ContextVar._cache['NO_COLOR'].value)))}")
n1.__exit__()
print(f"ctx_nc_exit={s(int(bool(ContextVar._cache['NO_COLOR'].value)))}")
# The EMPTY string is the pair that pins the RESTORE. The gate runs with
# NO_COLOR=1, so the boot value is 1; `Context(NO_COLOR="")` makes it 0 on the way in
# and `__exit__` must put the 1 back. With `Context(NO_COLOR="0")` alone both rows
# read 1 and a snapshot that hard-coded False would be invisible -- measured: that is
# mutation M-r, and it moved NOTHING until this row existed.
n2 = Context(NO_COLOR=""); n2.__enter__()
print(f"ctx_empty_enter={s(int(bool(ContextVar._cache['NO_COLOR'].value)))}")
n2.__exit__()
print(f"ctx_empty_exit={s(int(bool(ContextVar._cache['NO_COLOR'].value)))}")

# 61 ContextVars upstream; this file's `Flags` holds 4. Measured, not gated.
un("ctx_key_count", len(ContextVar._cache))
un("ctx_keys", ",".join(sorted(ContextVar._cache)))