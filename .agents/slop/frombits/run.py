#!/usr/bin/env python3
"""run.py -- walk a lane's chunk runner across a pattern range, and CHECK.

Three things are checked per chunk and none of them is "it ran":

  1. `tried` equals the count asked for. A chunk that stepped fewer patterns
     than it claimed is a silent skip.
  2. `sum_in` equals CPython's own arithmetic sum of the input range mod 2^32
     (`expect.sum_in`). A skip inside the chunk moves this, so it catches the
     skip that `tried` cannot see.
  3. The lane's own `mismatch` / `nan_kept` totals are accumulated and compared
     against the oracle.

A chunk whose `FB_START` + `FB_COUNT` overflows 2^32 is REJECTED rather than
wrapped: the driver computes `start + i` in U32 and would walk patterns from 0
again, which is a wrong answer rather than a wrong count. The last chunk of a
range is trimmed to stay inside the space.
"""
import argparse
import os
import subprocess
import sys

U32 = 2 ** 32
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from expect import sum_in, is_nan  # noqa: E402


def read_expect(path):
    d = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line and "=" in line:
                k, v = line.split("=", 1)
                d[k] = int(v)
    return d


def run_chunk(kind, cmd, sweep, start, count):
    env = dict(os.environ, FB_START=str(start), FB_COUNT=str(count))
    args = ([cmd, sweep] if kind == "js" else [cmd])
    out = subprocess.run(args, env=env, capture_output=True, text=True)
    line = out.stdout.strip().splitlines()[0] if out.stdout.strip() else ""
    if not line.startswith("FB "):
        raise SystemExit(f"chunk {start}+{count} produced no row:\n"
                         f"{out.stdout}\n{out.stderr}")
    return [int(x) for x in line.split()[1:]]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lane", required=True, choices=["js", "c"])
    ap.add_argument("--bend")
    ap.add_argument("--sweep")
    ap.add_argument("--binary")
    ap.add_argument("--chunk", type=int, required=True)
    ap.add_argument("--expect", required=True)
    ap.add_argument("--start", type=int, default=0)
    ap.add_argument("--space", type=int, default=U32,
                    help="END of the range, exclusive. So `--start 2139095040 "
                         "--space 2139116040` is the 21000 patterns from there.")
    args = ap.parse_args()

    exp = read_expect(args.expect)
    cmd = args.bend if args.lane == "js" else args.binary
    tried = mismatch = nan_in = nan_kept = sum_seen = 0
    pos = args.start
    chunks = 0
    while pos < args.space:
        n = min(args.chunk, args.space - pos)
        st, t, s, m, ni, nk = run_chunk(args.lane, cmd, args.sweep, pos, n)
        assert st == pos, f"chunk start drifted: asked {pos}, got {st}"
        assert t == n, f"chunk {pos}+{n} tried {t}"
        assert s == sum_in(pos, n), \
            f"chunk {pos}+{n} sum_in {s} != {sum_in(pos, n)} -- a skip"
        tried += t
        mismatch += m
        nan_in += ni
        nan_kept += nk
        sum_seen = (sum_seen + s) % U32
        pos += n
        chunks += 1

    span = tried
    whole = args.start == 0 and args.space == U32
    exp_nan = exp["nan_total"] if whole else \
        sum(1 for p in range(args.start, args.start + span) if is_nan(p))
    # A WINDOW WITH NO NaNs IN IT IS A BLIND WINDOW, and it PASSES. MEASURED: the
    # sub-window 0..400000000 contains zero NaN patterns -- the first is at
    # 2139095040 -- so blinding the driver's NaN test changed nothing there and
    # the run printed PASS. A NaN census over a NaN-free window is a claim about
    # no patterns. `nan_denominator == 0` on a partial range is therefore a
    # REFUSAL, not a zero.
    if not whole and exp_nan == 0:
        raise SystemExit(
            f"REFUSING: the window {args.start}..{args.start + span} contains "
            f"0 NaN patterns, so a NaN census over it proves nothing. Use the "
            f"whole space, or a window inside 2139095040..4294967295.")
    print(f"lane={args.lane} chunks={chunks} space={span} tried={tried}")
    print(f"lane={args.lane} sum_in={sum_seen} "
          f"expect={sum_in(args.start, span)}")
    print(f"lane={args.lane} nan_in={nan_in} nan_denominator={exp_nan}")
    print(f"lane={args.lane} nan_kept={nan_kept}")
    print(f"lane={args.lane} mismatch={mismatch}")

    bad = []
    if sum_seen != sum_in(args.start, span):
        bad.append("sum_in over the whole span")
    if nan_in != exp_nan:
        bad.append(f"nan_in {nan_in} != {exp_nan}")
    if whole:
        if args.lane == "c":
            if mismatch != exp["c_lane_mismatch"]:
                bad.append(f"mismatch {mismatch} != {exp['c_lane_mismatch']}")
            if nan_kept != exp["c_lane_nan_kept"]:
                bad.append(f"nan_kept {nan_kept} != {exp['c_lane_nan_kept']}")
        else:
            if mismatch != exp["js_lane_mismatch"]:
                bad.append(f"mismatch {mismatch} != {exp['js_lane_mismatch']}")
            if nan_kept != exp["js_lane_nan_kept"]:
                bad.append(f"nan_kept {nan_kept} != {exp['js_lane_nan_kept']}")
    print("FAIL " + "; ".join(bad) if bad else "PASS")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
