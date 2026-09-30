#!/usr/bin/env python3
# tenths(t, l) must be round(10*t/l) exactly as CPython's format(t/l, '.1f') rounds
# the double. At an exact tie the double is not the tie (unless it is dyadic), so
# the answer is decided by which way RN((2q+1)/20) fell -- which is a function of
# (2q+1) mod 5 and the binade of (2q+1)/20, and nothing else.
import random


def tie_up(q):
  p = 2 * q + 1
  g = p.bit_length() - 1                      # U32.log2
  if g == 0: k = 3
  elif g == 1: k = 1
  else: k = ((2 - g) & 3) if (5 << (g - 2)) <= p else ((3 - g) & 3)
  m5 = (1, 2, 4, 3)[k]                        # 2**k mod 5
  return (p % 5) * m5 % 5 >= 3


def tenths(t, l):
  n = 10 * t
  q, r = divmod(n, l)
  two = 2 * r
  if two > l: return q + 1
  if two < l: return q
  m = (2 * q + 1) % 20
  if m == 5 or m == 15: return q + 1 if q & 1 else q   # dyadic: the tie is exact
  return q + 1 if tie_up(q) else q


def show(t, l):
  q = tenths(t, l)
  return "%d.%d" % (q // 10, q % 10)


if __name__ == '__main__':
  bad = n = 0
  for l in range(1, 300):
    for t in range(0, 4000):
      n += 1
      if show(t, l) != format(t / l, ".1f"):
        bad += 1
        if bad < 6: print("BAD", t, l, show(t, l), format(t / l, ".1f"))
  print("exhaustive", n, "bad", bad)
  r = random.Random(11)
  bad = 0
  for _ in range(3000000):
    t = r.randint(0, 1 << 20)
    l = r.randint(1, 1 << 16)
    if show(t, l) != format(t / l, ".1f"):
      bad += 1
      if bad < 6: print("BAD", t, l, show(t, l), format(t / l, ".1f"))
  print("random 3e6 bad", bad)
