"""stage3_ceiling.py -- HOW MUCH IS LEFT IN THE PYTHON LANE'S *SHAPE*, NOT ITS ARITHMETIC.

    .venv/bin/python .agents/slop/perf/stage3_ceiling.py

The lane is `tinygrad/runtime/ops_python.py`, a walker: per uop it does two list comprehensions
over `u.src_without_body`, a `getenv("TRACE")`, a chain of `is` tests, a dict lookup, and then a
call into `exec_alu` or `load`/`store`. stage3_gap.py measured 1.3 us per such step.

This measures the SAME arithmetic in the two shapes a Python program can have, so the gap
between them is the ceiling of any rewrite of the walker:

  WALKED   a dict of uop -> value, a src list rebuilt per step, a dispatch chain, a call per op
  INLINE   straight-line Python over the same values, no dict, no list, no dispatch, no call

Both compute the same expression. The ratio is what "compile the uop list once" could buy, and it
is the number that decides whether a codegen can clear 5.1x -- so it is measured rather than
promised.
"""
import statistics
import time

N = 20000     # inner iterations per sample
REPS = 12     # samples


def walked(vals: dict, srcs: dict[str, list[str]]) -> float:
  """one iteration of the walker's shape: rebuild src lists, chase the dict, dispatch by name"""
  out = 0.0
  for i in range(N):
    vals["rng"] = i
    for name in ("acc", "a", "b"):
      u = name
      src = [vals[s] for s in srcs[u]]
      if name == "acc":
        vals[u] = src[0]
      elif len(src) == 2:
        vals[u] = src[0] * src[1]
      else:
        vals[u] = src[0]
    out += vals["acc"]
  return out


def inline() -> float:
  """the same arithmetic with the dispatch resolved once, by the compiler"""
  out = 0.0
  acc = a = b = 0.0
  for i in range(N):
    a = i * 1.0001
    b = a + 0.5
    acc = a * b
    out += acc
  return out


def main() -> int:
  vals = {"acc": 0.0, "a": 0.0, "b": 0.0}
  srcs = {"acc": ["a", "b"], "a": ["rng"], "b": ["a"]}
  per = {}
  for f, arg in ((walked, (vals, srcs)), (inline, ())):
    samples = []
    for _ in range(REPS):
      t = time.perf_counter()
      f(*arg)
      samples.append(time.perf_counter() - t)
    per[f.__name__] = statistics.median(samples) / N * 1e6
    print(f"{f.__name__:8s} {per[f.__name__]:8.3f} us per inner iteration")
  print(f"ratio    {per['walked'] / per['inline']:8.2f}x  <- the ceiling for a codegen")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
