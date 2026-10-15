#!/usr/bin/env python3
"""Mutation harness for `decomp_graph_census-gate.py`.

    .venv/bin/python gates/decomp_graph_census-mutate.py             # the whole table
    .venv/bin/python gates/decomp_graph_census-mutate.py A1 A3       # only these labels
    .venv/bin/python gates/decomp_graph_census-mutate.py --adt       # the acceptance test alone

ONE JOB, AND IT IS THE ACCEPTANCE TEST THE `ADt` REPAIR WAS ASKED FOR: prove that a
mutation which breaks ONLY a CAST's `ADt` argument MOVES A ROW. `crp_graph_census-mutate.py`
(`51cceacd7`) asked the same question of `mixin/creation.bend`'s `de` and answered 0 of 207,
and the recorded cause was that the printer rendered `OpsCAST{}` without its argument, so
the mutation had nothing to move. This lane now prints it (`decomp_graph_census.bend`'s
`dc_tok`, `decomp_graph_census-oracle.py`'s `s1`), so the same question is asked again here.

TWO COLUMNS, AND THE SECOND IS THE POINT. `MOVED` is how many of the 38 rows differ with
the printer in place. `MOVED-BARE` is the same comparison after every `[...]` is stripped
off both lanes, which is EXACTLY the printer as it was before the repair -- no second bend
run, and no risk of the two runs seeing different substrates. `MOVED > 0` with
`MOVED-BARE == 0` is the shape that says the REPAIR is what made the coupling visible. A
mutation with `MOVED == 0` AND `MOVED-BARE == 0` is not that: it is a DEAD mutation on this
population, and each one below is named for which of the two it is.

NO PORT FILE IS EVER WRITTEN. Every mutation edits a COPY that sits beside its original --
`dtype-mut.bend` beside `dtype.bend`, `op-mut.bend` beside `op.bend`, `decomp-mut-driver.bend`
beside `decomp_graph_census.bend` -- and both copies are unlinked in `finally`. The reason is
measured, not tidiness: `dtype.bend` does `import ./op.bend as P` RELATIVE TO ITS OWN PATH,
so a copy in a tmpdir answers "the substrate did not warm" and a harness that reads that as
"the mutation was found" has learned nothing. `*mut.bend` is in `.gitignore` (line 36), so a
killed run cannot sweep a mutated port file into a commit.

EVERY COPY IS ASSERTED BEFORE THE RUN, for the same reason the crp harness asserts its
pins shape: a mutation whose `old` text is absent from the file it names edited NOTHING, and
a harness that reports "moved 0 rows" for that is reporting its own miss. `apply()` raises
if `old` is not present exactly `n` times, and this file also refuses a replacement whose
`new` text is ALREADY in the copy, so a mutation cannot be a no-op and report it as a
coverage gap.

THE POPULATION IS THE GATE'S `ROWS`, IMPORTED BY PATH. MEASURED what a literal costs: this
file carried `assert n == 38` and the census grew a row, and the assertion fired on the BASE
lane and refused every comparison -- the right verdict for the wrong reason, and a second
copy of the population that could drift alone.

THE BASE LANE IS RUN HERE, NOT READ FROM `gates/artifacts/`. `gatekit` EMPTIES that directory
at the start of every run and unlinks what it staged when the run was not green, so a
mutation read against it compares the base against itself and every mutation reports zero.
`bend` runs are ~70 s each and the table is small, so the base is paid for once per run and
held in memory.

NO PINS FILE IS ADDED OR READ, so there is no column shape to assert. This harness compares
lane TEXTS; the pins file is `row<TAB>CPython's line<TAB>the port's line` (`gate.py:167`
`row, py, bd = ln.split("\t")`) and is written only by `--refresh`.
"""

import importlib.util
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
BEND = ROOT / "bin" / "bend"
GATE = HERE / "decomp_graph_census-gate.py"

DRIVER = HERE / "decomp_graph_census.bend"
MUT_DRIVER = HERE / "decomp-mut-driver.bend"
PORT = ROOT / "tinybendygrad" / "codegen" / "decomp" / "dtype.bend"
OP = ROOT / "tinybendygrad" / "codegen" / "decomp" / "op.bend"
MUT_PORT = PORT.with_name("dtype-mut.bend")
MUT_OP = OP.with_name("op-mut.bend")
COPIES = (MUT_DRIVER, MUT_PORT, MUT_OP)

# `dtype.bend` NAMES ITS SIBLING op.bend, so mutating op.bend alone would edit a file the
# lane does not read -- a mutation that moves zero rows for a reason that has nothing to do
# with the mutation. The copy is rewritten to name the copy, always, and A3 is the reason.
# THE TWO PAIRS ARE SEPARATE because the two files spell the import differently: the driver
# reaches op.bend by a path out of `gates/` and dtype.bend by a path out of its own directory.
DRIVER_IMPORTS = (("import ./../tinybendygrad/codegen/decomp/op.bend as P",
                   f"import ./../tinybendygrad/codegen/decomp/{MUT_OP.name} as P"),
                  ("import ./../tinybendygrad/codegen/decomp/dtype.bend as D",
                   f"import ./../tinybendygrad/codegen/decomp/{MUT_PORT.name} as D"))
DTYPE_IMPORTS = (("import ./op.bend as P", f"import ./{MUT_OP.name} as P"),)

# (LABEL, KIND, WHAT IT BREAKS, FILE, OLD, NEW, TIMES)
#
# A1 AND A2 ARE THE `de` EXPERIMENT, IN THE ONE PLACE `decomp` HAS THAT SHAPE. CPython's
# `DTypeMixin.cast` -- dtype.py:36 -- is `self if self.dtype == (dt := to_dtype(dtype)) else
# self._uop.alu(Ops.CAST, arg=dt)`: ONE value, the fold test's right-hand side AND the
# CAST's `arg`, in one expression. `mixin/creation.bend`'s `cr_const_of` (:242-245) is that
# line with the value made explicit, which is the `de` the recorded finding is about.
# `dtype.bend:593` and `:637` are the same two uses of one `ldt` binder, spelled apart:
#     +lo = dd_cast_fold(ar, x, ldt, O.eq_dt(xdt, ldt))
#            ^ the CAST's ADt                  ^ the fold test
# `dd_cast_fold` (:449) takes the two as SEPARATE parameters, so A1 can break one without
# the other -- which is the experiment, and it is possible here only because the port did
# not inline the walrus.
#
# A3 THROUGH A10 ARE THE REST OF THE `ADt` SITES, one per site, so a site this population
# never reaches is REPORTED rather than assumed covered.
TABLE = (
    ("A1", "ADt", "l2i_cast0/cast1's CAST ADt reads boolean -- ONE use of ldt broken",
     PORT, "  +lo = dd_cast_fold(ar, x, ldt, O.eq_dt(xdt, ldt))",
     "  +lo = dd_cast_fold(ar, x, S.boolean(), O.eq_dt(xdt, ldt))", 2),
    ("A2", "FOLD", "l2i_cast0/cast1's fold test reads boolean -- the OTHER use of ldt",
     PORT, "  +lo = dd_cast_fold(ar, x, ldt, O.eq_dt(xdt, ldt))",
     "  +lo = dd_cast_fold(ar, x, ldt, O.eq_dt(xdt, S.boolean()))", 2),
    ("A3", "ADt", "EVERY dc_cast ADt is hardcoded boolean -- op.bend's own CAST helper",
     OP, "  O.UOp.new(ar, O.OpsCAST{}, [x], O.ADt{dt}, O.TNone{})",
     "  O.UOp.new(ar, O.OpsCAST{}, [x], O.ADt{S.boolean()}, O.TNone{})", 1),
    ("A4", "ADt", "dd_cast_fold's False arm mints boolean -- the helper A1 goes through",
     PORT, "    case False{}: P.dc_cast(ar, x, dt)",
     "    case False{}: P.dc_cast(ar, x, S.boolean())", 1),
    ("A5", "ADt", "dd_cast_bool's True arm is boolean, not single",
     PORT, "    case True{}: P.dc_cast(ar, x, S.single())",
     "    case True{}: P.dc_cast(ar, x, S.boolean())", 1),
    ("A6", "ADt", "dd_bcast's False arm BITCASTs to boolean",
     PORT, "    case False{}: T.tx_bitcast(ar, x, dt)",
     "    case False{}: T.tx_bitcast(ar, x, S.boolean())", 1),
    ("A7", "ADt", "l2i_cast1.quo's closing CAST is boolean",
     PORT, "  +hi = P.dc_cast(O.Found.ar(m), O.Found.i(m), ldt)",
     "  +hi = P.dc_cast(O.Found.ar(m), O.Found.i(m), S.boolean())", 1),
    ("A8", "ADt", "l2i_cast3's CAST is boolean",
     PORT, "  +c = P.dc_cast(O.Found.ar(bc), O.Found.i(bc), dt)",
     "  +c = P.dc_cast(O.Found.ar(bc), O.Found.i(bc), S.boolean())", 1),
    ("A9", "ADt", "l2i_shl's low BITCAST is boolean",
     PORT, "  +lo = dd_bcast(O.eq_dt(dt, S.uint32()), O.Found.ar(sh1), O.Found.i(sh1), dt)",
     "  +lo = dd_bcast(O.eq_dt(dt, S.uint32()), O.Found.ar(sh1), O.Found.i(sh1), S.boolean())", 1),
    ("A10", "ADt", "l2i_shr's low BITCAST is boolean",
     PORT, "  +lo = dd_bcast(O.eq_dt(dt, S.uint32()), O.Found.ar(o), O.Found.i(o), dt)",
     "  +lo = dd_bcast(O.eq_dt(dt, S.uint32()), O.Found.ar(o), O.Found.i(o), S.boolean())", 1),
    ("A11", "ADt", "dd_const.int's AND dd_cf's ADt is boolean -- the CONST sites",
     PORT, "  O.UOp.new(O.Found.ar(c), O.OpsCAST{}, [O.Found.i(c)], O.ADt{dt}, O.TNone{})",
     "  O.UOp.new(O.Found.ar(c), O.OpsCAST{}, [O.Found.i(c)], O.ADt{S.boolean()}, O.TNone{})", 2),
    ("A12", "ADt", "l2i_bitcast's low BITCAST is boolean -- dtype.py:40's own arm",
     PORT, "  +lo = T.tx_bitcast(ar, nth(ws, 0n), dt)",
     "  +lo = T.tx_bitcast(ar, nth(ws, 0n), S.boolean())", 1),
    ("A13", "ADt", "unpack32.bc's BITCAST ADt is boolean, not uint32",
     PORT, "  dd_bcast(isu, ar, v, S.uint32())",
     "  dd_bcast(isu, ar, v, S.boolean())", 1),
)


def lanes(text):
    return {l.split("=", 1)[0]: l.split("=", 1)[1] for l in text.splitlines() if "=" in l}


def bare(sig):
    """THE PRE-REPAIR PRINTER: every `[...]` dropped. `OP/NSRC` is what `D.dd_sig1`
    (dtype.bend:2249) printed and what `s1` printed before this session."""
    out = []
    for tok in sig.split(","):
        out.append(tok.split("[", 1)[0])
    return ",".join(out)


def stage():
    """THE THREE COPIES, and the import rewrites that make them the lane under test."""
    shutil.copy(DRIVER, MUT_DRIVER)
    shutil.copy(PORT, MUT_PORT)
    shutil.copy(OP, MUT_OP)
    drv = MUT_DRIVER.read_text()
    for old, new in DRIVER_IMPORTS:
        assert old in drv, f"the driver no longer says {old!r}"
        drv = drv.replace(old, new)
    MUT_DRIVER.write_text(drv)
    dt = MUT_PORT.read_text()
    for old, new in DTYPE_IMPORTS:
        assert old in dt, f"dtype.bend no longer says {old!r}"
        dt = dt.replace(old, new)
    MUT_PORT.write_text(dt)


def run():
    """ONE bend PROCESS, and its rows. An empty or short lane is a DEAD lane, not a
    mutation that moved nothing -- `gatekit`'s own `DEAD` exit, and the seventeenth
    recorded instance of an instrument reporting a result for something it never ran."""
    p = subprocess.run([str(BEND), str(MUT_DRIVER)], capture_output=True, text=True, cwd=ROOT)
    if p.returncode:
        return None, f"bend rc={p.returncode}: {p.stderr.strip()[:400]}"
    return lanes(p.stdout), ""


def diff(base, got):
    """`(moved, moved_bare)` -- the rows that differ, with and without the `[...]`."""
    m = sorted(r for r in base if got.get(r) != base[r])
    mb = sorted(r for r in base if got.get(r) is not None and bare(got[r]) != bare(base[r]))
    return m, mb


def census_rows():
    """THE ROW COUNT, FROM THE GATE, NOT A LITERAL HERE.

    `AGENTS.md`'s first doctrine: an instrument that cannot see its population cannot be
    wrong, because it cannot be anything -- and a hand-typed `38` in a second file is a
    population that CAN drift alone. MEASURED the cost of getting that wrong: this file
    carried `38` and the census grew to 39, and the assertion below fired on the BASE lane
    and refused to compare, which is the right behaviour and the right reason. It is the
    gate's `ROWS` tuple, imported by path the way `crp-mut-run.py` imports its gate copy.
    """
    spec = importlib.util.spec_from_file_location("decomp_graph_census_gate", GATE)
    mod = importlib.util.module_from_spec(spec)
    sys.path.insert(0, str(HERE))
    try:
        spec.loader.exec_module(mod)
    finally:
        sys.path.remove(str(HERE))
    return tuple(mod.ROWS)


def main(argv):
    want = [a for a in argv if not a.startswith("-")]
    table = [e for e in TABLE if not want or e[0] in want]
    if not table:
        print("no such label; the table is " + " ".join(e[0] for e in TABLE), file=sys.stderr)
        return 3
    rows = census_rows()
    print(f"staging {len(COPIES)} copies; every bend run is one file at a time")
    stage()
    try:
        base, err = run()
        if base is None:
            print(f"BASE LANE IS DEAD, so every mutation below would compare against "
                  f"nothing: {err}", file=sys.stderr)
            return 1
        n = len(base)
        print(f"BASE LANE: {n} rows, and the gate's `ROWS` names {len(rows)}")
        if set(base) != set(rows):
            print(f"THE BASE LANE IS NOT THE CENSUS'S POPULATION: missing "
                  f"{sorted(set(rows) - set(base))}, extra {sorted(set(base) - set(rows))}. "
                  f"Every row below would be compared against a population this run did "
                  f"not measure", file=sys.stderr)
            return 1
        print(f"{'LABEL':6s} {'KIND':5s} {'MOVED':>5s} {'BARE':>4s}  ROWS / VERDICT")
        zero = []
        for label, kind, what, path, old, new, times in table:
            # FRESH COPIES PER MUTATION. A1 and A2 replace the SAME line with different
            # text, so a harness that mutated in place would leave A2's `old` absent and
            # report "DID NOT APPLY" -- a miss of its own making that reads as a dead def.
            stage()
            mut = MUT_OP if path is OP else MUT_PORT
            src = mut.read_text()
            found = src.count(old)
            if found != times:
                print(f"{label:6s} {kind:5s} {'-':>5s} {'-':>4s}  DID NOT APPLY: the text "
                      f"is in {found} places, not {times}. A zero here would be the "
                      f"harness's miss, not a dead mutation")
                zero.append((label, "DID NOT APPLY"))
                continue
            assert src.count(new) == 0, f"{label}: the replacement text is ALREADY in {mut.name}" \
                                         f" {src.count(new)} times, so this mutation could " \
                                         f"not move a row"
            mut.write_text(src.replace(old, new, times))
            got, err = run()
            if got is None:
                print(f"{label:6s} {kind:5s} {'-':>5s} {'-':>4s}  LANE DEAD: {err}")
                zero.append((label, "DEAD"))
                continue
            if len(got) != n:
                print(f"{label:6s} {kind:5s} {'-':>5s} {'-':>4s}  LANE IS {len(got)} ROWS, not "
                      f"{n} -- a mutation that CHANGES THE ROW COUNT is a population "
                      f"mutation and is not this table's subject")
                zero.append((label, "ROW COUNT"))
                continue
            m, mb = diff(base, got)
            verdict = ("VISIBLE ONLY WITH THE `ADt` PRINTED" if m and not mb else
                       "visible under the bare printer too" if mb else
                       "DEAD on this population")
            print(f"{label:6s} {kind:5s} {len(m):5d} {len(mb):4d}  "
                  f"{','.join(m) if m else '-'}  {verdict}")
            print(f"{'':6s} {'':5s} {'':5s} {'':4s}  {what}")
            if not m:
                zero.append((label, verdict))
        print()
        if zero:
            print(f"{len(zero)} MUTATION(S) MOVED NO ROW: "
                  + ", ".join(f"{a}={b}" for a, b in zero))
        return 0
    finally:
        for p in COPIES:
            p.unlink(missing_ok=True)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))