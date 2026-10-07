#!/usr/bin/env python3
"""THE GATE-SURFACE TABLE: declared verdicts vs verdicts this unit could MAKE a gate emit.

    .venv/bin/python .agents/slop/coindependent/vocab.py  --rows > vocab.rows
    .venv/bin/python .agents/slop/coindependent/probe.py         # writes probe.json
    .venv/bin/python .agents/slop/coindependent/twostate.py --rows > twostate.rows
    .venv/bin/python .agents/slop/coindependent/surface.py

THE NUMBER NOBODY WROTE DOWN: per gate, `declared / reached / difference`. A gate with 5 declared
verdicts of which 1 was ever produced has a 1/5 real surface. The denominator is the DISCOVERED
population from `vocab.py`; the reached column is what `probe.py` and `twostate.py` actually got.

`NOT-TESTED` is NOT `unreachable`. A gate whose only states need `bend` is reported `(needs bend)`
and counted in neither the reached nor the unreachable total, because this unit refused to start
the port compiler and an instrument that has not tried cannot call a verdict dead.
"""
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent

# States this unit could NOT present, by gate, and WHY. This is a hand list OF REFUSALS, which is
# the correct shape: what an instrument could not try is not a population the tree declares.
NEEDS_BEND = {
    "checks/substrate.py", "checks/abi_gate.py", "checks/abi4_gate.py", "checks/both-census.py",
    "checks/census.py", "checks/cl-port-gate.py", "checks/gate_norm.py", "checks/jsfix_gate.py",
    "checks/repair-dupes.py", "checks/vz_gate.py", "checks/e2e.py", "checks/e2e.sh",
    "checks/run-f64.sh", "checks/run-port-mm.sh", "checks/run-all.sh", "checks/substrate-check.sh",
    "checks/sb-gate.sh", "checks/walk-mutate.sh", "gates/beautiful-mnist-gate.py",
    "gates/mixin-op-gate.py", "gates/bc-u32-gate.py", "gates/ew-consts-gate.py",
    "gates/ew-explog-gate.py", "gates/i64-shl-gate.py", "gates/i64-shr-gate.py",
    "gates/ops-core-gate.py", "gates/render_val_s-gate.py", "gates/replace-gate.py",
    "gates/tn_bitwise_not-gate.py", "gates/tn_contiguous_backward-gate.py", "gates/tn_detach-gate.py",
    "gates/tn_dunder_neg-gate.py", "gates/tn_logical_not-gate.py", "gates/tn_neg-gate.py",
    "gates/tn_sin_log2_exp2_rsqrt-gate.py", "gates/tn_sqrt-gate.py",
    "gates/tn_trunc_reciprocal_threefry-gate.py", "gates/tn_where-gate.py", "gates/uop_cast-gate.py",
    "gates/wk-eval-gate.py", "gates/wk-f32-gate.py", "gates/wk-cd-gate.py",
}


def load_vocab():
    rows = []
    for line in (HERE / "vocab.rows").read_text().splitlines()[1:]:
        f = line.split("\t")
        if len(f) < 3:
            continue
        exits = set(int(x) for x in f[2].split(",") if x.strip().isdigit())
        rows.append({"path": f[0], "reason": f[1], "exits": exits})
    return rows


def load_observed():
    obs = {}
    pr = HERE / "probe.rows"
    if pr.is_file():
        for line in pr.read_text().splitlines()[1:]:
            f = line.split("\t")
            if len(f) >= 3 and f[2].isdigit():
                obs.setdefault(f[0], set()).add(int(f[2]))
    ts = HERE / "twostate.rows"
    if ts.is_file():
        for line in ts.read_text().splitlines()[1:]:
            f = line.split("\t")
            if len(f) >= 3 and f[2].isdigit():
                obs.setdefault(f[0], set()).add(int(f[2]))
    return obs


def resolve(path, known):
    """A probe may name a gate by bare stem (`no-txt`) or by path. Return the population path."""
    if path in known:
        return path
    for k in known:
        if pathlib.Path(k).stem == pathlib.Path(path).stem:
            return k
    return None



def main(argv):
    vocab = load_vocab()
    entries = [v for v in vocab if v["reason"] in ("py-main", "sh")]
    known = {v["path"] for v in entries}
    obs_raw = load_observed()
    obs = {}
    for k, s in obs_raw.items():
        if (rp := resolve(k, known)):
            obs.setdefault(rp, set()).update(s)
    print(f"# {len(entries)} entry point(s); {len(obs)} presented at least one state "
          f"without `bend`\n")
    print(f"{'path':44} {'declared':10} {'reached':10} {'diff'}")
    tot_d = tot_r = 1  # 1 seeds so an empty table is not vacuously 0
    tested = 0
    refused_only = []
    for v in entries:
        d = v["exits"]
        r = obs.get(v["path"], set())
        if v["path"] in NEEDS_BEND and not r:
            print(f"{v['path']:44} {'/'.join(map(str, sorted(d))) or '-':10} "
                  f"{'(needs bend)':10} -")
            continue
        tested += 1
        tot_d += len(d)
        tot_r += len(d & r)
        if d == {3} and v["path"] not in NEEDS_BEND:
            refused_only.append(v["path"])
        print(f"{v['path']:44} {'/'.join(map(str, sorted(d))) or '-':10} "
              f"{'/'.join(map(str, sorted(r))) or '(none)':10} "
              f"{len(d) - len(d & r)}")
    print(f"\n# TOTALS over the {tested} gates this unit presented (the `needs bend` set excluded):")
    print(f"#   declared exit-codes           : {tot_d - 1}")
    print(f"#   declared codes REACHED        : {tot_r - 1}")
    print(f"#   declared-but-not-reached      : {(tot_d-1) - (tot_r-1)}")
    print(f"#   gates whose ONLY declared code is REFUSED (cannot go green) : "
          f"{len(refused_only)}")
    for p in refused_only:
        print(f"#     {p}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
