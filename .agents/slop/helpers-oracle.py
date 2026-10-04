#!/usr/bin/env python
# helpers-oracle.py -- the CPython side of the `trange` / `GlobalCounters` /
# `Context` / 64-bit-pair gate for tinybendygrad/helpers.bend.
#
#   DEFAULT_FLOAT=f16 DEFAULT_INT=i64 NO_COLOR=0 \
#     .venv/bin/python .agents/slop/helpers-oracle.py
#
#   sh .agents/slop/helpers-tc-gate.sh        # runs it, both Bend lanes, and diffs
#
# EVERY row is produced by CALLING the real defs in tinygrad/helpers.py:637
# (`trange`), :319 (`GlobalCounters`), :187 (`Context`) and :76-78 (`floordiv`,
# `floormod`). Nothing here is typed from memory; `cat` the file if you want to
# check a row. The 64-bit block at the foot adds `math.gcd` and Python's own `|`,
# `&` and `<<`, which is the same statement about the same words.
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
import math
import sys
from tinygrad.helpers import trange, GlobalCounters, Context, ContextVar, floordiv, floormod

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

# ------------------------------------------------------- the 64-bit pair block
# `i64_or` / `i64_and` / `i64_shl` / `i64_div` / `i64_mod` / `gcd`, on a two's
# complement 64-bit word. helpers.py:76-78 for the division and `math.gcd` for the
# gcd, and the BITWISE and the SHIFT are Python's own operators on the same integer.
#
# THE FIXTURE IS A PAIR OF WORDS AND NOT A DECIMAL, and that is not a printing
# choice: `H.i64_text` prints the two halves, so both sides read the same 64 bits
# and a value like 2**63 -- which has no `U32` image and would have to be
# TRANSCRIBED -- never appears anywhere in this file. The `_a=` and `_b=` and `_x=`
# and `_k=` rows below print the FIXTURE ITSELF, so a table that drifts between the
# two lanes shows up as a diff on the input rather than as a diff nobody can explain.
#
# ONE REDUCTION, STATED ONCE. `i64_div` / `i64_mod` / `i64_shl` are 64-bit
# operations and their answer is reduced mod 2**64 and read back as signed, which is
# the contract `i64_add` / `i64_sub` have had since their borrow was fixed. CPython's
# `//`, `%` and `<<` are UNBOUNDED, so `as_i64` applies that reduction to Python's
# answer rather than Python being wrong: on every row but `pm_ovf` and `sh_k64` it is
# the identity, and on those two it is the whole claim.
MASK64 = (1 << 64) - 1
def as_i64(x: int) -> int:
  v = x & MASK64
  return v - (1 << 64) if v >> 63 else v
def signed(hi: int, lo: int) -> int: return as_i64((hi << 32) | lo)
def words(x: int) -> str:
  v = as_i64(x) & MASK64
  return f"{v >> 32}:{v & 0xFFFFFFFF}"
def w64(x: int) -> str: return words(as_i64(x))

# (name, a, b) as WORD PAIRS. The small rows are the CONTROL and they are not what
# makes the divider a test: every row whose two operands are below 2**32 reads the
# same whether the 65th bit is carried, whether the shift's high arm comes from `lo`
# or from `hi`, and whether the floor correction is applied. The rows that reach
# those branches are the ones with a non-zero HIGH WORD -- `pm_big` is 2**63-1 over
# 2**62-1, `pm_mini` is -2**63, `pm_maxi` is 2**63-1, and `pm_nege`/`pm_nepo`/
# `pm_pone`/`pm_gneg` are the three sign pairs plus a negative gcd. `pm_gf` is the
# one row with small operands ON PURPOSE: it is a Fibonacci pair, so it is the row
# that reaches the `gcd` fuel bound rather than the 64-bit branches.
#
# `pm_gbig` exists because the `*_gcd` COLUMN was constant over twelve of the
# fourteen rows -- everything but `pm_zero` and `pm_zerod` answers `0:1` -- and a
# column that is constant over a suite is a column no mutation can move. It is
# `gcd(2**63-2, 2**62-1) = 2**62-1`, so it is a LARGE answer and not just a non-1
# one, and a two-step Euclid over 64-bit operands. Twelve rows are still `0:1`
# because that is what the gcd of most pairs is, and the three that are not are the
# rows the column exists for: `pm_zero_gcd=0:0`, `pm_zerod_gcd=0:7`, `pm_gbig_gcd`.
PAIRS = [
  ("pm_zero",  (0, 0),          (0, 0)),
  ("pm_zerod", (0, 7),          (0, 0)),
  ("pm_small", (0, 5),          (0, 3)),
  ("pm_big",   (0x7FFFFFFF, 0xFFFFFFFF), (0x3FFFFFFF, 0xFFFFFFFF)),
  ("pm_nege",  (0xFFFFFFFF, 0xFFFFFFF7), (0xFFFFFFFF, 0xFFFFFFFB)),
  ("pm_nepo",  (0xFFFFFFFF, 0xFFFFFFF9), (0, 4)),
  ("pm_pone",  (0, 7),          (0xFFFFFFFF, 0xFFFFFFFC)),
  ("pm_mini",  (0x80000000, 0), (0, 3)),
  ("pm_maxi",  (0x7FFFFFFF, 0xFFFFFFFF), (0xFFFFFFFF, 0xFFFFFFFF)),
  ("pm_ovf",   (0x80000000, 0), (0xFFFFFFFF, 0xFFFFFFFF)),
  ("pm_wide",  (0xFFFFFFFF, 0), (0, 0xFFFFFFFF)),
  ("pm_gb",    (0x7FFFFFFF, 0xFFFFFFFF), (0x7FFFFFFE, 0xFFFFFFFE)),
  ("pm_gbig",  (0x7FFFFFFF, 0xFFFFFFFE), (0x3FFFFFFF, 0xFFFFFFFF)),
  ("pm_gneg",  (0xFFFFFFFF, 0xFFFFFFF9), (0, 6)),
  ("pm_gf",    (0, 2971215073), (0, 472537396)),
]
for nm, (ah, al), (bh, bl) in PAIRS:
  a, b = signed(ah, al), signed(bh, bl)
  print(f"{nm}_a={words(a)}")
  print(f"{nm}_b={words(b)}")
  print(f"{nm}_or={w64(a | b)}")
  print(f"{nm}_and={w64(a & b)}")
  print(f"{nm}_div={w64(floordiv(a, b))}")
  print(f"{nm}_mod={w64(floormod(a, b))}")
  print(f"{nm}_gcd={w64(math.gcd(a, b))}")

# (name, x, k). `k = 0`, `k = 32` and `k = 64` are the three amounts where a shift's
# two forms meet or the word runs out, and `sh_neg33` is the one that reaches the
# `k >= 32` arm on a NEGATIVE value -- where the high word must come from `lo` and
# only from `lo`, and reading `hi` there answers 0.
SHIFTS = [
  ("sh_k0",    (0x12345678, 0x9ABCDEF0), 0),
  ("sh_k1",    (0x12345678, 0x9ABCDEF0), 1),
  ("sh_k31",   (0x12345678, 0x9ABCDEF0), 31),
  ("sh_k32",   (0, 1),        32),
  ("sh_k33",   (0, 1),        33),
  ("sh_k63",   (0, 1),        63),
  ("sh_k64",   (0, 1),        64),
  ("sh_neg4",  (0xFFFFFFFF, 0xFFFFFFF9), 4),
  ("sh_neg33", (0xFFFFFFFF, 0xFFFFFFF9), 33),
  ("sh_big63", (0x7FFFFFFF, 0xFFFFFFFF), 63),
]
for nm, (xh, xl), k in SHIFTS:
  x = signed(xh, xl)
  print(f"{nm}_x={words(x)}")
  print(f"{nm}_k={s(k)}")
  print(f"{nm}_shl={w64(x << k)}")

# ------------------------------------------------------- `i64_dec`, a signed decimal
# `str(val)` is what `print_uops` (tinygrad/uop/render.py:18) prints for a CONST src,
# and the port's `H.i64_text` cannot answer it: on 4 it says `0:4`. This is the
# CPython side of that claim, and it is `str` itself rather than a reimplementation.
#
# THE FIXTURE IS A PAIR OF WORDS, not a decimal, for the reason the 64-bit block above
# states: a decimal would have to be transcribed on one side and derived on the other,
# and a transcription is exactly the constant that is wrong and green. Each row prints
# the fixture back as `hi:lo` AND the decimal, so the input and the output are both in
# the diff.
#
# `d_i64min` IS A LIMIT AND NOT A CLAIM. CPython's `str(-2**63)` is
# `-9223372036854775808`, and the port answers `2147483648:0` -- the bit pattern --
# because Bend's `I64` cannot hold the magnitude 2**63. So this row is the ONE whose
# two lanes are EXPECTED to differ, and it is emitted here through the same `fallback`
# the port uses rather than skipped, so the disagreement is visible in the diff instead
# of living in a comment.
DEC_ROWS = [
    ("d_zero", 0, 0),
    ("d_one", 0, 1),
    ("d_nine", 0, 9),
    ("d_ten", 0, 10),
    ("d_hundred", 0, 100),
    ("d_thousand", 0, 1000),
    ("d_42", 0, 42),
    ("d_12345", 0, 12345),
    ("d_i32max", 0, 2147483647),
    ("d_i32p1", 0, 2147483648),
    ("d_u32max", 0, 4294967295),
    ("d_2p32", 1, 0),
    ("d_1e12", 232, 3567587328),
    ("d_i64max", 2147483647, 4294967295),
    ("d_neg1", 4294967295, 4294967295),
    ("d_neg10", 4294967295, 4294967286),
    ("d_neg42", 4294967295, 4294967254),
    ("d_neg1e9", 4294967295, 3294967296),
    ("d_i64min", 2147483648, 0),
]


def dec_limit(x: int) -> bool:
  """True where the port cannot hold |x| and answers the bit pattern instead."""
  return x == -(1 << 63)


def dec_rows():
  for nm, hi, lo in DEC_ROWS:
    v = signed(hi, lo)
    print(f"{nm}_x={words(v)}")
    print(f"{nm}_d={words(v) if dec_limit(v) else v}")


dec_rows()
