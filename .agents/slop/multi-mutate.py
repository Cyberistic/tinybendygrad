#!/usr/bin/env python3
"""Mutate multi.bend's OWN logic and record which gate rows move.

WHY. A gate that prints 321 rows and nothing is 0 proves the rows are
non-degenerate but not that they WATCH anything. Each mutation below changes one
decision the port makes and the interesting measurement is which rows answer
differently. A mutation that no row catches is a row-shape hole, and a mutation
that flips a whole half of the table is a gate that cannot be trusted at that
granularity.

EVERY mutation here is a change of DECISION, never a change of type: the file
must still compile, because a mutation that fails to build measures nothing
about the gate. `bsn`/`mu_ss_axis`/`ix_div` are chosen for that reason -- their
wrong answers are VALUES, not refusals, which is what makes them dangerous.

USAGE.  python3 .agents/slop/multi-mutate.py [BASE_LANE]
where BASE_LANE defaults to /tmp/mi.txt. The file is restored even on failure.
"""
import subprocess, sys, pathlib, re, os

ROOT = pathlib.Path(__file__).resolve().parents[2]
BEND = ROOT / "tinybendygrad/schedule/multi.bend"
CHECK = ROOT / ".agents/slop/tools/multi-check.sh"
TMP = pathlib.Path(os.environ.get("TMPDIR", "/tmp")) / "many"

MUTS = [
    ("M01", "rs_local.one.of", "drop the sharding test: divide EVERY axis",
     "  mu_pick(sharded, rs_local.one.div(div, d, c), d)",
     "  rs_local.one.div(div, d, c)"),
    ("M02", "pi_step", "tuple.index first-wins -> last-wins",
     "def pi_step(p: Pi, hit: Bool, i: Nat) -> Pi:\n  match hit:\n    case True{} : Pi{i, True{}}\n    case False{}: p",
     "def pi_step(p: Pi, hit: Bool, i: Nat) -> Pi:\n  match hit:\n    case True{} : Pi{i, True{}}\n    case False{}: Pi{i, False{}}"),
    ("M03", "mu_ss_axis", "drop the RIGHT-ALIGNMENT shift",
     "  U32.sub(axis, U32.from_nat(Nat.sub(out_n, src_n)))", "  axis"),
    ("M04", "ml_kind.rest", "WHOLE answers BCAST: never copy_multi",
     "    case True{}: 1", "    case True{}: 2"),
    ("M05", "ix_div", "strided pattern divides by the residue, not shard_sz",
     "def ix_div(diff: U32, shard_sz: U32) -> U32:\n  U32.div(diff, shard_sz)",
     "def ix_div(+diff: U32, shard_sz: U32) -> U32:\n  U32.div(diff, ix_mod(diff, shard_sz))"),
    ("M06", "mu_claimed", "drop the necessary condition: first-wins, not a conjunction",
     "  mu_and2(O.pm_claimed(ops, ar, self), mu_early(ar, self, rej))",
     "  O.pm_claimed(ops, ar, self)"),
    ("M07", "rd_low_dt", "drop `half` from the (bfloat16, half) pair",
     "  Bool.or(O.eq_dt(dt, S.bfloat16()), O.eq_dt(dt, S.half()))",
     "  O.eq_dt(dt, S.bfloat16())"),
    ("M08", "st_off.of", "drop the axis > 0 guard: U32.sub WRAPS at axis 0",
     "    case True{} : mu_sym_dim()", "    case True{} : U32.sub(axis, 1)"),
    ("M09", "mu_baxes", "len(out) >= len(src) -> len(out) > len(src)",
     "def mu_baxes(+src: List<&2, U32>, +out: List<&2, U32>) -> Maybe<&2, List<&2, U32>>:\n  mu_baxes.of(U32.is_ge(",
     "def mu_baxes(+src: List<&2, U32>, +out: List<&2, U32>) -> Maybe<&2, List<&2, U32>>:\n  mu_baxes.of(U32.is_gt("),
    ("M10", "mu_ra_cfg.go", "swap the LATE_ALLREDUCE tag shift 19 <-> 20",
     "    case True{} : mu_ra_shift(19, mu_ra_base(), acc)\n"
     "    case False{}: mu_ra_shift(20, mu_ra_base(), List.append(&2, O.PMEntry, acc, [mu_ea0()]))",
     "    case True{} : mu_ra_shift(20, mu_ra_base(), acc)\n"
     "    case False{}: mu_ra_shift(19, mu_ra_base(), List.append(&2, O.PMEntry, acc, [mu_ea0()]))"),
    ("M11", "mu_exp_keep", "drop the out[nleft+i] != 1 conjunct",
     "  Bool.and(mu_ones(s), mu_not_one(mu_at(out, U32.to_nat(U32.add(nleft, U32.from_nat(i))))))",
     "  mu_ones(s)"),
    ("M12", "fl_of.put", "the non-zero filter keeps the ZERO indices",
     "    case True{} : acc\n    case False{}: List.append(&2, U32, acc, [U32.from_nat(i)])",
     "    case True{} : List.append(&2, U32, acc, [U32.from_nat(i)])\n    case False{}: acc"),
]


def run():
    r = subprocess.run([str(CHECK)], capture_output=True, text=True)
    return r.returncode, r.stdout, r.stderr


def rows(text):
    out = {}
    for line in text.splitlines():
        m = re.fullmatch(r"(t_\w+)=(-?\d+)", line.strip())
        if m:
            out[m.group(1)] = int(m.group(2))
    return out


def main():
    base_lane = sys.argv[1] if len(sys.argv) > 1 else "/tmp/mi.txt"
    src = BEND.read_text()
    base = rows(pathlib.Path(base_lane).read_text())
    if not base:
        sys.exit(f"no t_ rows in {base_lane}")
    print(f"baseline {base_lane}: {len(base)} rows\n")
    try:
        for mid, target, why, old, new in MUTS:
            n = src.count(old)
            if n != 1:
                print(f"{mid} {target:16s} SKIP: {n} sites for the anchor")
                continue
            BEND.write_text(src.replace(old, new))
            code, out, err = run()
            if code != 0:
                print(f"{mid} {target:16s} BUILD FAILED (measures nothing)")
                print("    " + err.strip().splitlines()[1][:90] if len(err.strip().splitlines()) > 1 else "")
                BEND.write_text(src)
                continue
            got = rows(out)
            moved = sorted(k for k in base if k in got and base[k] != got[k])
            lost = sorted(set(base) - set(got))
            print(f"{mid} {target:16s} {len(moved):3d} rows moved"
                  + (f", {len(lost)} lost" if lost else "")
                  + f"   [{why}]")
            print("    " + " ".join(moved[:26]) + (" ..." if len(moved) > 26 else ""))
            BEND.write_text(src)
    finally:
        BEND.write_text(src)
    print("\nfile restored")


main()
