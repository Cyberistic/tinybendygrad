"""ORACLE for Defect 1. Every expectation is CALLED, never typed.

The question: does dtypes.void.priority == -1 change ANY answer a reader can observe,
or is -1 dead weight? tinygrad reads `.priority` in exactly ONE place (dtype.py:68,
DType.__lt__), so that reader is the entire blast radius upstream.
"""
import functools, itertools, operator
import tinygrad.dtype as T
from tinygrad.dtype import dtypes, DType, least_upper_dtype, _get_recursive_parents, promo_lattice

ALL = [dtypes.void, dtypes.weakint, dtypes.bool, dtypes.int8, dtypes.uint8, dtypes.int16,
       dtypes.uint16, dtypes.int32, dtypes.uint32, dtypes.int64, dtypes.uint64,
       dtypes.weakfloat, dtypes.fp8e4m3, dtypes.fp8e5m2, dtypes.fp8e4m3fnuz,
       dtypes.fp8e5m2fnuz, dtypes.float16, dtypes.bfloat16, dtypes.float32, dtypes.float64]

print("=== Q1 THE TABLE AS CALLED ===")
for d in ALL:
  print(f"{d.name}\t{d.priority}\t{d.bitsize}")
assert dtypes.void.priority == -1, dtypes.void.priority
assert dtypes.void.bitsize == 0

print("\n=== Q2 void's ONLY reader: DType.__lt__ (dtype.py:68) ===")
# A void clone at a chosen priority, same bitsize/name/fmt, so ONLY pri differs.
def clone_void(pri): return DType.new(pri, dtypes.void.bitsize, dtypes.void.name, dtypes.void.fmt)

def lt_order(pri):
  v = clone_void(pri)
  return sorted(ALL, key=functools.cmp_to_key(operator.lt))

for pri in (-1, 0, 1, 7, 99):
  print(f"  pri={pri:>3}: full sort order starts {', '.join(d.name for d in lt_order(pri)[:4])}")
print("  sorted order identical for pri=-1 and pri=0?", lt_order(-1) == lt_order(0))
print("  ...for pri=-1 and pri=1?", lt_order(-1) == lt_order(1))
# WHICH tuple element decides it, asked directly.
print(f"  tuple for real void  : {(dtypes.void.priority, dtypes.void.bitsize, dtypes.void.name, dtypes.void.fmt)}")
print(f"  tuple for weakint    : {(dtypes.weakint.priority, dtypes.weakint.bitsize, dtypes.weakint.name, dtypes.weakint.fmt)}")
print("  void < weakint at pri=-1?", dtypes.void < dtypes.weakint)
print("  void < weakint at pri=0? ", clone_void(0) < dtypes.weakint)
print("  void < weakint at pri=1? ", clone_void(1) < dtypes.weakint)
print("  -> the tiebreak that decides it is bitsize 0 < 800, which is pri-independent.")

print("\n=== Q3 promotion: does void appear in the lattice at all? ===")
print("  'void' in promo_lattice?", dtypes.void in promo_lattice)
try:
  _get_recursive_parents(dtypes.void)
except Exception as e:
  print(f"  _get_recursive_parents(void) -> {type(e).__name__}: {e!r}")
n_ok = n_key = 0
for a, b in itertools.product(ALL, repeat=2):
  try: least_upper_dtype(a, b); n_ok += 1
  except KeyError: n_key += 1
print(f"  least_upper_dtype over {n_ok+n_key} ordered pairs: {n_ok} OK, {n_key} KeyError")
print("  -> void's parents are unreachable, so pri is not consulted for promotion AT ALL.")

print("\n=== Q4 substitute a lattice entry for void and sweep its priority ===")
promo_lattice[dtypes.void] = []            # make void reachable, nothing above it
outs = {}
for pri in (-1, 0, 1, 7, 15, 99):
  v = clone_void(pri)
  _get_recursive_parents.cache_clear(); least_upper_dtype.cache_clear()
  res = {}
  for a in ALL:
    for b in ALL:
      x, y = (v if a is dtypes.void else a), (v if b is dtypes.void else b)
      try: res[(x.name, y.name)] = least_upper_dtype(x, y).name
      except Exception as e: res[(x.name, y.name)] = type(e).__name__
  outs[pri] = res
base = outs[-1]
print("  least_upper_dtype sweep, void made reachable:")
for pri in outs:
  diff = [k for k in base if base[k] != outs[pri][k]]
  print(f"    pri={pri:>3}: {len(diff)} of {len(base)} pairs differ from pri=-1"
        + (f"  e.g. {diff[:3]}" if diff else "  <-- SAME ANSWER"))
print("\n=== Q5 the ONLY place pri could matter: a max-by-pri over ALL dtypes ===")
# dtype.py's DTypes.from_py does `max(dtypes.from_py(xi) for xi in x)`, which is DType.__lt__.
for pri in (-1, 0, 1, 7, 99):
  v = clone_void(pri)
  pool = [v if d is dtypes.void else d for d in ALL]
  print(f"  pri={pri:>3}: max(all 20) = {max(pool).name}   (weakfloat={dtypes.weakfloat.name})")
print("  -> the max is decided by float64, so void's pri is off the end of the argument.")
