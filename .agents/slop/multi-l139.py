#!/usr/bin/env python3
"""multi-l139.py -- does multi.py:139 divide by a PER-AXIS count or by the LEAKED loop
variable of the `for ax, rng in multi.sharding` loop at :131?

The line is executed AS WRITTEN, extracted from the installed tinygrad by `inspect` and run
through `exec`, so the answer is upstream's own text and not a transcription of it. The
comprehension's divisor is whatever `rng` names at :139, and `rng` is rebound nowhere
between :131 and :139.

Run it twice. It is byte-identical across runs.

    .venv/bin/python .agents/slop/multi-l139.py
"""
import inspect
import sys

sys.path.insert(0, '.')
import tinygrad.schedule.multi as M  # noqa: E402
from tinygrad.uop.ops import UOp, AxisType  # noqa: E402


def rng(n):
  """A real sharding range. `int(rng.vmax)+1` at :139 needs a UOp, not an int, so the
  fixture carries UOps and the printed form is `int(r.vmax)+1`."""
  return UOp.range(n, 0, AxisType.DEVICE)

# The :139 line, TAKEN FROM UPSTREAM rather than typed here.
LINE139 = next(l.strip() for l in inspect.getsource(M.reshape_multi).splitlines()
               if "new_shape = tuple(s//" in l)
LINE131 = next(l.strip() for l in inspect.getsource(M.reshape_multi).splitlines()
               if "for ax, rng in multi.sharding:" in l)
LINE133 = next(l.strip() for l in inspect.getsource(M.reshape_multi).splitlines()
               if "% count" in l)


def upstream_139(new_shape, sharding):
  """multi.py:131's loop, then :138-139 verbatim. `rng` is whatever the loop last bound."""
  # `multi` is only read for `.sharding`, and the loop over it is the thing being modelled,
  # so a one-field stand-in whose `.sharding` IS the fixture keeps upstream's own header
  # byte-for-byte instead of rewriting it.
  env = {"new_shardings": list(sharding), "new_shape": new_shape,
         "multi": type("M", (), {"sharding": list(sharding)})()}
  # the :131 header, from upstream, with the loop BODY supplied here as a no-op -- the body
  # is where `count` and `target` are computed, and `rng` is what :139 reads.
  exec(LINE131 + " pass", env)                             # noqa: S102 -- upstream's own header
  exec("new_axs = {a for a, _ in new_shardings}", env)    # noqa: S102 -- upstream's :138
  exec(LINE139, env)                                       # noqa: S102 -- upstream's :139
  return env["new_shape"]


def per_axis(new_shape, sharding):
  cnt = dict(sharding)
  return tuple(s // cnt[a] if a in cnt else s for a, s in enumerate(new_shape))


def main():
  print("upstream's own text, read by inspect (not transcribed):")
  print(f"  multi.py:131  {LINE131}")
  print(f"  multi.py:133  {LINE133}")
  print(f"  multi.py:139  {LINE139}")
  print("\n  `rng` is NOT rebound between :131 and :139, so :139's divisor is the LAST range "
        "in multi.sharding,\n  applied to EVERY sharded axis. There is no per-axis lookup on "
        "that line.")

  print("\nEXEC :138-139 verbatim vs the PER-AXIS reading:")
  print(f"  {'new_shape':<12} {'sharding':<16} {'upstream :139':<18} {'per-axis':<14} differ")
  cases = [((4, 6), [(0, 2), (1, 4)]), ((4, 6), [(0, 4), (1, 2)]),
           ((12, 18), [(0, 4), (1, 6)]), ((4, 6), [(0, 1), (1, 1)])]
  ndiff = 0
  for new_shape, counts in cases:
    sharding = [(ax, rng(c)) for ax, c in counts]
    up = upstream_139(new_shape, sharding)
    pa = per_axis(new_shape, counts)
    diff = up != pa
    ndiff += diff
    print(f"  {str(new_shape):<12} {str(counts):<16} {str(up):<18} {str(pa):<14} "
          f"{'YES' if diff else 'no'}")
  print(f"\n{ndiff} of {len(cases)} UNEQUAL-count shardings answer differently under the two "
        f"readings.")
  print("\nmulti.bend's `rs_local` (multi.bend:1313-1319) implements the PER-AXIS reading, "
        "through `ns_count`\n(multi.bend:1279-1283), which scans for the axis and returns "
        "THAT axis's count. On an\nUNEQUAL-count sharding the two disagree, and CPython is "
        "the side that says :139.")


if __name__ == "__main__":
  main()
