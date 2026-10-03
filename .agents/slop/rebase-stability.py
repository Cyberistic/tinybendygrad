#!/usr/bin/env python3
"""rebase-stability.py -- the EVIDENCE a --record needs before it is allowed.

WHY THIS EXISTS. `rebase-gate.py --record` freezes whatever the tree printed at the moment
it ran. Two of the lanes in BASE_ORACLES can never report UNCHANGED afterwards, and one of
them is documented in that file's own comments: `elf.bend`'s oracle prints 14 `elf_built_*`
rows carrying the RUNTIME ADDRESSES of the libstub.dylib the fixtures link against, so ASLR
changes them on every process launch. Recording that lane freezes a lane whose verdict is
permanently RE-PORTED, and a permanently-RE-PORTED lane teaches the reader that RE-PORTED is
noise -- which is the exact failure a gate exists to prevent.

So --record must be gated on MEASUREMENT, and this is the measurement. For every wired port:

    run 1 and run 2 of run_port(), and record, per lane:
      n1, n2          row counts. A COUNT that moves between runs makes the lane unrecordable
                      even when every value agrees, because GUARD 1 is an absolute count and
                      would answer BROKEN (or RE-PORTED) at random.
      same            rows dicts compared whole, per lane. Not per row name -- agent-core.md
                      records that a name-comparing harness reported 0 for all 30 mutations.
      interp_eq_native  within EACH run, interpreted == native. A bend interpreter that
                      stack-overflows on 1 run in 20 prints NOTHING, so a partial run shows up
                      as interpreted != native. This is a free second witness on the lane that
                      `same` alone would rate as stable twice in a row.

RECORDABLE means: every lane's count is equal across both runs AND rows identical across both
runs AND interpreted == native within both runs. Anything else is EXCLUDED, and the reason is
carried in the output -- never a judgement call at record time.

  usage: .venv/bin/python .agents/slop/rebase-stability.py [--only PORT] [--workers N]
         writes .agents/slop/rebase/stability.json and prints one line per port

INVOKE WITH .venv/bin/python. The editable tinygrad install exists only there (3.12); under
/homebrew python3 every oracle dies with ModuleNotFoundError, which is GUARD 3, not a port bug.
"""
import argparse, concurrent.futures as cf, importlib.util, json, pathlib, sys

REPO = pathlib.Path(__file__).resolve().parents[2]
HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE / "rebase" / "stability.json"


def load_gate():
  spec = importlib.util.spec_from_file_location("rebase_gate", HERE / "rebase-gate.py")
  m = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(m)
  return m


def same(a, b):
  """Whole-dict equality, so a lost row and a changed row are the same failure here. Named
  rather than written inline so the reason string under it stays one line."""
  return a == b


def measure(port, oracle, runs=2):
  g = load_gate()
  bend = REPO / port
  seen, lanes_by_run = [], []
  for _ in range(runs):
    lanes, rows = g.run_port(bend, tuple(oracle), native=True)
    seen.append(rows)
    lanes_by_run.append(lanes)
  first = {k: len(v) for k, v in seen[0].items()}
  reasons = []
  for lane in first:
    counts = [len(r.get(lane, {})) for r in seen]
    if len(set(counts)) != 1:
      reasons.append(f"{lane}: ROW COUNT MOVED {counts}")
    elif not all(same(r.get(lane, {}), seen[0].get(lane, {})) for r in seen):
      keys = {k for r in seen for k in r.get(lane, {})}
      diff = sorted(k for k in keys if len({r.get(lane, {}).get(k) for r in seen}) > 1)
      reasons.append(f"{lane}: {len(diff)} row(s) differ between runs, e.g. {diff[:3]}")
  for i, lanes in enumerate(lanes_by_run):
    i_l, n_l = seen[i].get("interpreted", {}), seen[i].get("native", {})
    if "interpreted" in first and "native" in first and not same(i_l, n_l):
      d = sorted(set(i_l) ^ set(n_l)) or [k for k in set(i_l) & set(n_l) if i_l[k] != n_l[k]]
      reasons.append(f"run {i+1}: interpreted != native ({len(d)} rows), so at least one "
                     f"bend run was partial, e.g. {d[:3]}")
  dead = sorted(k for k, l in lanes_by_run[-1].items() if l["rc"] != 0 and k != "check")
  return {
    "port": port, "oracle": list(oracle), "runs": runs,
    "row_counts_run1": first,
    "row_counts_run2": {k: len(v) for k, v in seen[1].items()},
    "dead_lanes": dead,
    "shared": shared_of(seen[0]),
    "reasons": reasons,
    "recordable": not reasons,
  }


def shared_of(rows):
  """Row names the CPython lane corroborates, and whether any of them disagree. The number
  of claims the lane actually makes -- a gate's strength is the intersection, not the
  oracle's output size."""
  lanes = sorted(rows)
  out = {}
  for i, a in enumerate(lanes):
    for b in lanes[i + 1:]:
      sh = set(rows[a]) & set(rows[b])
      if sh:
        out[f"{a}|{b}"] = {
          "shared": len(sh),
          "disagree": sum(1 for k in sh if rows[a][k] != rows[b][k]),
        }
  return out


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--only", default=None)
  ap.add_argument("--runs", type=int, default=2)
  ap.add_argument("--workers", type=int, default=4)
  ap.add_argument("--out", default=str(OUT))
  a = ap.parse_args()
  g = load_gate()
  # run_port() writes its native binary to /tmp/rebase-gate/<BEND STEM>.bin, and two wired
  # ports share the stem `dtype` (dtype.bend, codegen/decomp/dtype.bend). Sharding is by STEM,
  # not by port, so the two never land in different workers and clobber each other's binary.
  stem = {p: pathlib.Path(p).stem for p in g.BASE_ORACLES}
  shard = {}
  for s in sorted({v for v in stem.values()}):
    shard.setdefault(len(shard) % a.workers, []).extend(
      p for p in sorted(g.BASE_ORACLES) if stem[p] == s)
  todo = [p for ps in shard.values() for p in ps if not a.only or a.only in p]
  res = {}
  with cf.ThreadPoolExecutor(max_workers=a.workers) as ex:
    fut = {ex.submit(measure, p, g.BASE_ORACLES[p], a.runs): p for p in todo}
    for f in cf.as_completed(fut):
      p = fut[f]
      try:
        r = f.result()
      except Exception as e:  # a measurement that crashed is NOT a stable lane
        r = {"port": p, "reasons": [f"measurement crashed: {e!r}"], "recordable": False}
      res[p] = r
      sh = ",".join(f"{k.split('|')[0][:6]}={v['shared']}" for k, v in r.get("shared", {}).items())
      print(f"{'REC ' if r['recordable'] else 'EXCL'} {p:<48} "
            f"rows {list(r.get('row_counts_run1', {}).values())} shared[{sh}] "
            f"{'; '.join(r['reasons']) or 'stable across %d runs' % a.runs}", flush=True)
  out = pathlib.Path(a.out)
  out.write_text(json.dumps(res, indent=1, sort_keys=True))
  print(f"\nwrote {out}")
  return 0


if __name__ == "__main__":
  sys.exit(main())
