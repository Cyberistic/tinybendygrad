"""Is mutation M7 a THEOREM or a FIXTURE REQUEST?

M7 replaces `least_upper.pick(or(is_zero(ma),is_zero(mb)), ma & mb)` with `... , ma`,
i.e. the meet stops ANDing the two masks and uses the LEFT one alone. It moved 0 rows.

Two things decide it: (a) do the port's masks have bit 0 set, and (b) can the lowest
set bit of `ma` ever differ from the lowest set bit of `ma & mb`? Both are answered by
COMPUTING the port's own mask constants against CPython's `_get_recursive_parents`.
"""
import sys; sys.path.insert(0, ".")
from tinygrad.dtype import dtypes, _get_recursive_parents, promo_lattice, least_upper_dtype

# fold.bend:169-189 `dt_by_rank`'s order, read off the source.
RANK = ["bool","weakint","i8","u8","i16","u16","i32","u32","i64","u64","weakfloat",
        "fp8e4m3","fp8e4m3fnuz","fp8e5m2","fp8e5m2fnuz","f16","bf16","f32","f64"]
ORDER = [getattr(dtypes, n) for n in RANK]

# fold.bend:137-166 `promo_mask`'s constants, transcribed from the source.
PORT_MASK = {"bool":524287,"weakint":524286,"i8":523604,"u8":524280,"i16":523600,
             "u16":524256,"i32":523584,"u32":524160,"i64":523520,"u64":523776,
             "weakfloat":523264,"fp8e4m3":493568,"fp8e4m3fnuz":495616,"fp8e5m2":499712,
             "fp8e5m2fnuz":507904,"f16":425984,"bf16":458752,"f32":393216,"f64":262144}

def cpython_mask(d):
  """`_get_recursive_parents` written as a bit mask over `dt_by_rank`'s order."""
  return sum(1 << ORDER.index(p) for p in _get_recursive_parents(d))

print("=== (a) does the port's constant equal CPython's mask, and is bit 0 set? ===")
print(f"{'dtype':<14}{'port':>10}{'cpython':>10}  agree  bit0")
bad = 0
for n in RANK:
  d = getattr(dtypes, n)
  pm, cm = PORT_MASK[n], cpython_mask(d)
  ok = pm == cm
  bad += not ok
  print(f"{n:<14}{pm:>10}{cm:>10}  {str(ok):<6} {pm & 1}")
print(f"{bad} constants disagree with CPython")

def lowest(m): return (m & -m).bit_length() - 1
def by_rank(m): return RANK[lowest(m)]

print("\n=== (b) can lowest(ma) differ from lowest(ma & mb)? ===")
diff = []
for a in ORDER:
  for b in ORDER:
    ma, mb = PORT_MASK[a.name], PORT_MASK[b.name]
    if lowest(ma) != lowest(ma & mb):
      diff.append((a.name, b.name, by_rank(ma), by_rank(ma & mb)))
print(f"  pairs where they differ: {len(diff)} of {len(ORDER)**2}")
for x in diff[:12]:
  print(f"    {x[0]:<8} & {x[1]:<8}: left-only gives {x[2]:<8} AND gives {x[3]}")

print("\n=== so is M7 a theorem? ===")
if not diff:
  print("  YES for every pair in the table: lowest(ma) == lowest(ma & mb), so `ma` and")
  print("  `ma & mb` name the SAME dtype and no fixture can separate them. Bit 0 is the")
  print("  reason: every non-void mask has bool (rank 0) in it, so the AND can never")
  print("  lower the lowest set bit below 0, and lowest(ma) is 0 whenever ma has bit 0.")
  print("  M7 is a THEOREM, not a coverage gap.")
else:
  print("  NO -- it is a FIXTURE REQUEST. These pairs separate it:")
  for x in diff:
    print(f"    ({x[0]}, {x[1]}) -> left-only {x[2]}, AND {x[3]}")

print("\n=== cross-check: is `ma & mb` == CPython's intersection? ===")
bad2 = 0
for a in ORDER:
  for b in ORDER:
    if PORT_MASK[a.name] & PORT_MASK[b.name] != cpython_mask(a) & cpython_mask(b): bad2 += 1
print(f"  {bad2} of {len(ORDER)**2} pairs disagree")
