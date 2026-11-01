"""Prototype of the EXACT f32 -> CPython-repr formatter, before porting it to Bend.

The port needs repr(float(f32)) -- the shortest decimal D with float64(D) == x -- and the tree
has only F32.show, which is the shortest F32 round-trip and therefore a DIFFERENT string
(`1.442695` against CPython's `1.4426950216293335`) for every value that is not exactly a short
decimal. This file works the algorithm out in a language with bignums so the Bend port can be
checked against it line for line.
"""
import struct, random, sys


def bits(x: float) -> int:
  return struct.unpack("<I", struct.pack("<f", x))[0]


def dec_of(N: int, t: int):
  """value = N * 2^t as (digits, exp) with value = int(digits) * 10^exp."""
  if t >= 0:
    return str(N << t), 0
  return str(N * 5 ** (-t)), t


def cmp(a, b):
  """compare two positive (digits, exp) decimals."""
  e = min(a[1], b[1])
  A, B = a[0] + "0" * (a[1] - e), b[0] + "0" * (b[1] - e)
  A, B = A.lstrip("0") or "0", B.lstrip("0") or "0"
  if len(A) != len(B):
    return -1 if len(A) < len(B) else 1
  return (A > B) - (A < B)


def cands(digits: str, exp: int, p: int):
  """the p-significant-digit candidates NEAREST the value, closest first.

  CHECKING ONLY THE CORRECTLY-ROUNDED CANDIDATE IS NOT ENOUGH, and this is the subtlety that
  cost the first two versions of this file: when the nearest candidate falls just OUTSIDE the
  rounding interval, the NEXT one along is still inside. MEASURED: 2^-97 rounds to
  ...094e-30 (which is below lo and reads back as the neighbour), while ...095e-30 is in the
  interval and is the string CPython prints. So the loop must offer BOTH neighbours.
  """
  if len(digits) <= p:
    return [(digits.rstrip("0") or "0", exp)]
  head, rest = digits[:p], digits[p:]
  e = exp + len(rest)
  up = str(int(head) + 1)
  if len(up) > p:
    up, e_up = up[:p], e + 1
  else:
    e_up = e
  # half-to-even decides WHICH is closer when the tail is exactly a half; otherwise the lead digit
  # of the tail does, and the preferred candidate is the one the rounding would pick.
  tie = rest[0] == "5" and rest[1:].strip("0") == ""
  prefer_up = rest[0] > "5" or (rest[0] == "5" and not tie) or (tie and int(head[-1]) % 2 == 1)
  down, upp = (head.rstrip("0") or "0", e), (up.rstrip("0") or "0", e_up)
  return [upp, down] if prefer_up else [down, upp]


def exact(x: float):
  b = bits(x)
  be, frac = (b >> 23) & 0xFF, b & 0x7FFFFF
  if be == 0:
    M, e = frac, -149
  else:
    M, e = frac | 0x800000, be - 127 - 23
  return M, e


def bound(M: int, e: int, s: int, step: int = 54):
  """x + s*half_ulp, as a decimal: (M*2^(step-b) + s) * 2^(e+b-step)."""
  b = M.bit_length()
  return dec_of(M * (1 << (step - b)) + s, e + b - step)


def is_pow2(M: int) -> bool:
  return M == 1 << (M.bit_length() - 1)


def format_digits(D: str, E: int) -> str:
  dp = len(D) + E
  if -3 <= dp <= 16:
    if dp <= 0:
      return "0." + "0" * (-dp) + D
    if dp >= len(D):
      return D + "0" * (dp - len(D)) + ".0"
    return D[:dp] + "." + D[dp:]
  e = dp - 1
  mant = D[0] + ("." + D[1:] if len(D) > 1 else "")
  return mant + "e" + ("+" if e >= 0 else "-") + f"{abs(e):02d}"


def py_repr(x: float) -> str:
  b = bits(x)
  if b in (0x80000000, 0):
    return "-0.0" if b else "0.0"
  sign = "-" if b >> 31 else ""
  if ((b >> 23) & 0xFF) == 0xFF:
    return sign + ("nan" if b & 0x7FFFFF else "inf")
  M, e = exact(x)
  D, E = dec_of(M, e)
  # trailing zeros are absorbed into E, NEVER dropped: "43431769050439315619840" x 10^0 is not
  # "4343176905043931561984" x 10^0, and the first version of this file made exactly that mistake.
  while len(D) > 1 and D.endswith("0"):
    D, E = D[:-1], E + 1
  # THE LOWER BOUND IS NOT ALWAYS A FULL HALF-ULP AWAY: at a power of two the f64 grid is twice
  # as fine just below, so the interval is ASYMMETRIC. MEASURED: 2^-98 wanted lo = x - 2^-151 and
  # the symmetric form gave x - 2^-150, which then accepted a 16-digit candidate CPython rejects.
  lo = bound(M, e, -1, 55 if is_pow2(M) else 54)
  hi = bound(M, e, 1)
  for p in range(1, 18):
    for cd, ce in cands(D, E, p):
      if cmp((cd, ce), lo) >= 0 and cmp((cd, ce), hi) <= 0:
        return sign + format_digits(cd, ce)
  raise AssertionError("no p round-tripped")


if __name__ == "__main__":
  vals = []
  rnd = random.Random(7)
  for _ in range(20000):
    vals.append(struct.unpack("<f", struct.pack("<I", rnd.getrandbits(32)))[0])
  vals += [0.0, 1.0, -1.0, 0.5, 3.0, 1e-7, 1e16, 1e15, 1e-4, 1e-5, 1.4426950408889634,
           0.1, 1 / 3, 1e38, 1e-38, 5.9e-39, 3.4028235e38, 1.1754944e-38, 2 ** -30]
  vals = [v for v in vals if v == v and abs(v) != float("inf")]
  bad = 0
  for v in vals:
    want, got = repr(float(struct.unpack("<f", struct.pack("<f", v))[0])), py_repr(v)
    if want != got:
      bad += 1
      if bad <= 8:
        print("MISMATCH", want, got)
  print(f"checked {len(vals)} bad {bad}")
  sys.exit(1 if bad else 0)
