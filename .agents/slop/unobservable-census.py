#!/usr/bin/env python3
"""THE UNOBSERVABLE-ROW CENSUS -- static half, rigorous version.

A gate row is `name=value`. The row is a test only if some substitution of the
behaviour it claims to test changes `value`. This tool computes, from the row
TEXT ALONE, exactly how many behaviours the row provably CANNOT distinguish.
No mutation, no second run, no second lane.

    THE METRIC. Let V be a row value and T its token word (split on comma,
    space, brackets). A transposition of two positions i<j of T changes V iff
    T[i] != T[j]. So

        blind_swaps(V) = sum over distinct tokens t of C(|{i : T[i]==t}|, 2)

    is the NUMBER of distinct orderings of the things V displays that produce
    byte-identical output. `blind_swaps(V) == 0` means V is a faithful encoding
    of its token order -- the row can see every reordering. `blind_swaps(V) > 0`
    means that many reorderings are invisible, and no fixture on that row will
    ever catch one. This is a THEOREM about the string, not a suspicion.

    Two special cases fall out and are reported separately because they are the
    defect classes the project has already paid for:
      * `ORDER-DEAD`: every token is the same token. Every permutation is the
        same string. The `1,1` / `INS INS INS INS` shape.
      * `NO-STATE`: V has no tokens, or V is a single bare constant. The row
        cannot distinguish anything at all.

    THE CROSS-ROW HALF. Order is often split across SIBLING rows (`gt_ops0..5`),
    where the index lives in the NAME. Then a transposition of two sibling
    VALUES is invisible iff the two values are equal. So a sibling family is
    scanned too, and the number of equal-valued sibling pairs is reported as
    `sibling_blind`. `gt_ops4=WHERE`/`gt_ops5=WHERE` is invisible to a swap; a
    harness that diffs whole `name=value` lines sees nothing.

ROW NAMES CONTAIN SPACES and lanes print DIFFERENT FORMATS (`name=value`,
`name = [v]  py=[w]`), so the name is everything up to the first `=` or `:` and
never a whitespace split. A line with no separator is prose, not a row.

Usage:
  .venv/bin/python .agents/slop/unobservable-census.py                 # every wired oracle
  .venv/bin/python .agents/slop/unobservable-census.py --all            # every committed txt
  .venv/bin/python .agents/slop/unobservable-census.py --detail FILE
  .venv/bin/python .agents/slop/unobservable-census.py --detail FILE --top 40
"""
from __future__ import annotations

import math
import pathlib
import re
import sys
from collections import defaultdict

ROOT = pathlib.Path(__file__).resolve().parents[2]
SLOP = ROOT / ".agents" / "slop"
RUNS = SLOP / "runs"

NAME_RE = re.compile(r"^(?P<name>[^=:]*?)\s*(?P<sep>=|:)\s*(?P<val>.*)$")


def rows_of(path: pathlib.Path) -> list[tuple[str, str]]:
    out = []
    for line in path.read_text(errors="replace").splitlines():
        s = line.rstrip()
        if not s or s.lstrip().startswith("#"):
            continue
        m = NAME_RE.match(s)
        if m is None or not m.group("name").strip():
            continue
        out.append((m.group("name").strip(), m.group("val").strip()))
    return out


def tokens(val: str) -> list[str]:
    v = val.strip().strip("[]()")
    return [t for t in re.split(r"[,\s]+", v) if t]


def blind_swaps(tok: list[str]) -> int:
    """Transpositions of `tok` that leave the word byte-identical."""
    n = defaultdict(int)
    for t in tok:
        n[t] += 1
    return sum(c * (c - 1) // 2 for c in n.values())


def classify(val: str) -> tuple[int, str]:
    """(blind_swaps, verdict) for one row value.

    A ONE-token value has no order of its own to get wrong, so it is not
    ORDER-DEAD; blind_swaps is 0 because C(1,2)==0. It is reported as SCALAR so
    a reader can see it is a total with no ordering claim attached.
    """
    t = tokens(val)
    if not t:
        return 0, "NO-STATE"
    if len(t) == 1:
        return 0, "SCALAR"
    if len(set(t)) == 1:
        return blind_swaps(t), "ORDER-DEAD"
    b = blind_swaps(t)
    return b, ("order-exact" if b == 0 else "order-weak")


def families(names: list[str]) -> dict[str, list[int]]:
    """Group row names by an optional trailing integer: `gt_ops0` -> `gt_ops`.

    This is the shape that puts the index in the NAME, which is exactly where
    cross-row order lives and exactly where a `name=value` diff is blind to a
    swap of two equal siblings.
    """
    f: dict[str, list[int]] = defaultdict(list)
    for i, n in enumerate(names):
        m = re.match(r"^(.*?)(\d+)$", n)
        f[m.group(1) if m else n].append(i)
    # A family must be a CONTIGUOUS 0..k-1 run, or it is a coincidence: `so_libz_so_6`,
    # `so_libz_so_06` and `so_libz_so_06_txt` share a stem and share nothing else.
    out: dict[str, list[int]] = {}
    for k, idxs in f.items():
        if len(idxs) < 2:
            continue
        nums = []
        for i in idxs:
            m2 = re.match(r".*?(\d+)$", names[i])
            nums.append(int(m2.group(1)) if m2 else -1)
        if nums != list(range(len(idxs))):
            continue
        out[k] = idxs
    return out


def sibling_blind(vals: list[str]) -> int:
    """Equal-valued sibling pairs: transpositions invisible across rows."""
    n = defaultdict(int)
    for v in vals:
        n[v] += 1
    return sum(c * (c - 1) // 2 for c in n.values())


def analyse(path: pathlib.Path) -> dict:
    rows = rows_of(path)
    names = [r[0] for r in rows]
    vals = [r[1] for r in rows]
    per_row = []
    for (nm, v) in rows:
        b, verdict = classify(v)
        per_row.append({"name": nm, "val": v, "blind": b, "verdict": verdict})
    fam = families(names)
    sib = 0
    sib_fams = []
    for fname, idxs in fam.items():
        s = sibling_blind([vals[i] for i in idxs])
        sib += s
        if s:
            sib_fams.append((fname, s, len(idxs)))
    return {
        "path": path,
        "n": len(rows),
        "rows": per_row,
        "order_dead": sum(1 for r in per_row if r["verdict"] == "ORDER-DEAD"),
        "no_state": sum(1 for r in per_row if r["verdict"] == "NO-STATE"),
        "scalar": sum(1 for r in per_row if r["verdict"] == "SCALAR"),
        "order_weak": sum(1 for r in per_row if r["verdict"] == "order-weak"),
        "blind_total": sum(r["blind"] for r in per_row),
        "sib_blind": sib,
        "sib_fams": sorted(sib_fams, key=lambda r: -r[1]),
    }


WIRED = {
    # oracle txt -> the port whose rows it is the expected side of
    "runs/base_runtime_ops_cl.bend.txt": "runtime/ops_cl+ops_cuda+ops_hip",
    "runs/base_c.bend.txt": "renderer/cstyle",
    "late-oracle.txt": "codegen/late/{linearizer,regalloc,gater}",
    "runs/base_codegen_rewriter.bend.txt": "codegen/{simplify,late/coalesce,gpudims}",
    "xd1/gd-oracle.txt": "codegen/gpudims",
    "ops_cpu_null-pre-split.txt": "runtime/ops_cpu_null",
    "bnxt_oracle.txt": "runtime/ops_bend",
    "dsp_py.txt": "runtime/ops_dsp",
    "tc_ptx-pre-split.txt": "renderer/tc_ptx",
    "dt-py.txt": "codegen/decomp/dtype",
    "naming-gate-baseline.txt": "naming-gate",
}


def main(argv: list[str]) -> int:
    detail = "--detail" in argv
    allf = "--all" in argv
    top = 40
    if "--top" in argv:
        top = int(argv[argv.index("--top") + 1])
    if detail:
        targets = [a for a in argv if not a.startswith("--") and a not in {"40", str(top)}]
        for t in targets:
            p = (SLOP / t).resolve()
            if not p.exists():
                p = pathlib.Path(t).resolve()
            r = analyse(p)
            print(f"=== {p}  {r['n']} rows")
            print(f"    ORDER-DEAD {r['order_dead']}  order-weak {r['order_weak']}  "
                  f"NO-STATE {r['no_state']}  blind_swaps {r['blind_total']}  "
                  f"sibling_blind {r['sib_blind']}")
            worst = sorted(r["rows"], key=lambda x: -x["blind"])[:top]
            for w in worst:
                if w["blind"]:
                    print(f"    {w['verdict']:10} blind={w['blind']:<4} {w['name']}={w['val']}")
            if r["sib_fams"]:
                print("    -- sibling families with equal-valued pairs --")
                for fname, s, k in r["sib_fams"]:
                    print(f"       {fname}[{k}]  sibling_blind={s}")
        return 0
    files = []
    for rel, port in WIRED.items():
        p = SLOP / rel
        if p.exists():
            files.append((port, p))
    if allf:
        for p in sorted(SLOP.rglob("*.txt")):
            if p.stat().st_size < 4_000_000:
                files.append((p.stem, p))
    seen, out = set(), []
    for port, p in files:
        rp = p.resolve()
        if rp in seen:
            continue
        seen.add(rp)
        out.append((port, analyse(p)))
    out.sort(key=lambda r: -r[1]["order_dead"])
    print("=" * 96)
    print("UNOBSERVABLE-ROW CENSUS -- static half (blind-transposition count, proven from the row text)")
    print("=" * 96)
    print(f"{'port':40} {'rows':>6} {'DEAD':>6} {'weak':>6} {'NO-STATE':>9} "
          f"{'blind_sw':>9} {'sib_bl':>8}")
    T = [0] * 6
    for port, r in out:
        print(f"{port[:40]:40} {r['n']:>6} {r['order_dead']:>6} {r['order_weak']:>6} "
              f"{r['no_state']:>9} {r['blind_total']:>9} {r['sib_blind']:>8}")
        T = [a + b for a, b in zip(T, [r["n"], r["order_dead"], r["order_weak"],
                                       r["no_state"], r["scalar"], r["blind_total"]])]
        print(f"   ({port[:38]:38} scalar={r['scalar']})")
    print("-" * 96)
    print(f"{'TOTAL':40} {T[0]:>6} {T[1]:>6} {T[2]:>6} {T[3]:>9} {T[4]:>9} {T[5]:>8}")
    print()
    print("DEAD = every token identical: provably blind to EVERY ordering. weak = some.")
    print("blind_sw = number of reorderings of a row's own tokens it cannot see.")
    print("sib_bl = number of reorderings of SIBLING rows (index in the NAME) it cannot see.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
