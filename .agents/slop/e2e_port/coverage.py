#!/usr/bin/env python3
"""e2e_port/coverage.py -- HOW MUCH OF THE PORT IS EXECUTION, WITH THE DENOMINATOR.

    .venv/bin/python .agents/slop/e2e_port/coverage.py <port-rows.txt> <lane-log>...

WHY THIS FILE EXISTS.  `cstyle-gate.py:554` builds BOTH of its lanes from
`subprocess.CompletedProcess([], 0, pathlib.Path(a.port_stdout).read_text(), "")`,
so every one of its rows is a comparison of two RECORDED TEXTS.  A reader who is
handed "227/227 green" and not the denominator will quote it as a computational
claim.  This file puts the denominator in the artefact's own output, and it is
COUNTED, never typed:

  * the row SET and the fragment/kernel split come from `portexec/census.py`'s own
    `classify`, imported rather than re-implemented, so these numbers cannot drift
    away from the committed census;
  * every row that looks like C is written to its own file and handed to `cc`, and
    the accept/reject counts are what `cc` said;
  * the EXECUTED rows are read out of the LANE LOGS -- `run-kernel.sh` prints
    `PORT ROW : <name>` and `PASS [n] n u32 words bit-identical`, so the marking is
    the lane's own claim, cross-checked here against the row set: a name that is in
    the 227 counts against the 227, and a name that is not counts outside them.

THE ALu ROWS ARE NAMED OUT LOUD HERE.  `kern2 BASE alu` and `kern2 CLANG alu` pair an
ALU-space SIGNATURE (`const float alu0_1, const float alu1_1`) with the gate's
`g_kernel()` BODY, which references `data1_4`/`data0_4`; `renderer_oracle.py:551-552`
hands upstream the SAME mismatched pair, so both lanes of the text gate agree on a
string no compiler has ever accepted.  Those rows cannot be falsified by execution
and this stage does not use either of them.
"""
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent.parent.parent / ".agents" / "slop" / "portexec"))
from census import PREAMBLE, classify            # noqa: E402  -- the committed classifier
from exec_harness import port_rows                # noqa: E402

ROW_RE = re.compile(r"^\s*PORT ROW\s*:\s*(.+?)\s*$", re.M)
PASS_RE = re.compile(r"^PASS \[(\d+)\] (\d+) u32 words bit-identical", re.M)
DIFF_RE = re.compile(r"diff bytes: (\d+)")


def pct(n, d):
    return "  --  " if not d else f"{100.0 * n / d:5.2f}%"


def main():
    rows = port_rows(pathlib.Path(sys.argv[1]))
    logs = [pathlib.Path(p) for p in sys.argv[2:]]
    total = len(rows)

    # ---- the executed rows, read out of the lane logs' OWN claims -------------
    # THE ROW KEYS CARRY TRAILING SPACES -- `kern2 CLANG      ` is a fixed-width gate
    # name -- and the lane log prints the name stripped of them, so the membership test
    # is done on stripped keys and the CANONICAL key is what gets reported.  The first
    # version tested the stripped name against the raw dict, found nothing, and counted
    # `kern2 CLANG` as a kernel OUTSIDE the 227: a denominator error of one, made by a
    # whitespace comparison, in the one table whose whole job is the denominator.
    canon = {k.strip(): k for k in rows}
    executed_in, executed_out, claims = 0, 0, []
    for lg in logs:
        t = lg.read_text()
        row, ok, diff = ROW_RE.search(t), PASS_RE.search(t), DIFF_RE.search(t)
        if not (row and ok and diff):
            claims.append((lg.name, "NO PASS CLAIM -- this lane is not counted as execution", "", 0))
            continue
        name, n, d = row.group(1), int(ok.group(1)), diff.group(1)
        claim = f"EXECUTED, {n} words, diff {d} bytes"
        if name in canon:
            executed_in += 1
            claims.append((canon[name], claim, "one of the 227", n))
        else:
            executed_out += 1
            claims.append((name, claim, f"NOT one of the {total} rows", n))

    # ---- the text/compilable split, counted by asking `cc` -------------------
    # THE SCRATCH DIRECTORY IS `tempfile`'s, NEVER THIS FILE'S DIRECTORY.  A
    # committed `.agents/slop/e2e_port/` that collects `.c` droppings is a tree
    # nobody can `git status` cleanly.
    cdir = pathlib.Path(tempfile.mkdtemp(prefix="e2e-port-census."))
    frag, kernels, acc, rej = 0, [], [], []
    try:
        for name, val in sorted(rows.items()):
            kind, _ = classify(name, val)
            if kind != "kernel":
                frag += 1
                continue
            f = cdir / (re.sub(r"[^A-Za-z0-9]+", "_", name.strip()) + ".c")
            f.write_text(PREAMBLE + val.replace("\\n", "\n"))
            r = subprocess.run(["cc", "-c", "-o", "/dev/null", str(f)], capture_output=True, text=True)
            # THE PATH IS STRIPPED.  `census.py:54` keeps the first stderr line, which
            # on this machine is 90 characters of temporary path and no message at all;
            # this is the second measured defect in that file.
            msg = re.sub(r"^.*?:\d+:\d+: ", "", (r.stderr.strip().splitlines() or [""])[0])
            (acc if r.returncode == 0 else rej).append((name.strip(), msg))
            kernels.append(name)
    finally:
        shutil.rmtree(cdir, ignore_errors=True)

    def line(label, count):
        print(f"  {label:<58} {count:>4}  {pct(count, total)}")

    line("rows in the port's own stdout  (THE DENOMINATOR)", total)
    line("TEXT ONLY -- a fragment, not a translation unit", frag)
    line("C SOURCE -- a `void N(...)` signature and a body", len(kernels))
    line("  ...of those, `cc` ACCEPTS on this machine", len(acc))
    line("  ...of those, `cc` REJECTS", len(rej))
    line("  ...of those, EXECUTED here and compared against CPython", executed_in)
    # NO PERCENTAGE ON THIS ROW, and there is a reason.  A count of artefacts that are
    # NOT in the set, expressed as a share of the set, is the denominator error this
    # table exists to stop -- `portexec/README.md:53` writes "2 of 227 rows have been
    # executed" two lines after listing one row of the 227 plus one kernel that is
    # explicitly "NOT among the 227 rows".
    print(f"  {'kernels EXECUTED that are NOT among those rows':<58} {executed_out:>4}      --")
    print(f"  {'-' * 74}")
    print(f"  STILL TEXT: {total - executed_in} of {total} rows "
          f"({pct(total - executed_in, total).strip()})."
          f"   EXECUTED: {executed_in} of {total} ({pct(executed_in, total).strip()}).")
    print(f"  Executed C artefacts in total, counting the one outside the rows: "
          f"{executed_in + executed_out}.")
    print("\n  -- what each lane log claims, and whether its row is one of the rows --")
    for name, claim, where, n in claims:
        print(f"    {name:<46} {claim:<44} {where}")

    print(f"\n  -- the {len(rej)} REJECTIONS, with cc's own words (temporary paths stripped) --")
    for name, msg in rej:
        print(f"    {name:<20} {msg}")

    print("\n  *** THE UNFALSIFIABLE PAIR, AND WHY IT IS NOT COUNTED HERE. ***")
    print("      `kern2 BASE alu` and `kern2 CLANG alu` pair an ALU-space SIGNATURE with the")
    print("      gate's `g_kernel()` BODY, which names `data1_4`; `renderer_oracle.py:551-552`")
    print("      hands upstream the SAME mismatched pair, so BOTH lanes of the text gate agree")
    print("      on a string no compiler has ever accepted. No execution can falsify them.")
    print("      THIS STAGE USES NEITHER ROW: its executed kernel is `emit-mm.bend`'s four-buffer")
    print("      `mm`, which is not one of the 227 rows at all, so it has no py= twin to agree with.")
    print(json.dumps({"rows": total, "fragments": frag, "c_source": len(kernels),
                      "cc_accepts": len(acc), "cc_rejects": len(rej),
                      "executed_of_the_rows": executed_in,
                      "executed_outside_the_rows": executed_out,
                      "still_text": total - executed_in}, indent=1))


if __name__ == "__main__":
    main()
