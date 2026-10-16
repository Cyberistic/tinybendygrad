#!/usr/bin/env python3
"""ptx_render_census-mutate.py -- what this census can and cannot see.

    .venv/bin/python gates/ptx_render_census-mutate.py           # run all
    .venv/bin/python gates/ptx_render_census-mutate.py M1 M14    # run some

A mutation is a (name, file, old, new) edit that must appear EXACTLY ONCE. The harness
writes a scratch copy, runs the census against it, and DIFFS THE THREE LANES against the
unmutated three. What moves is the measurement; what does NOT move is the more useful
half -- it names what this gate is blind to, and `AGENTS.md`'s rule is that a zero is a
DELIVERABLE, not a failure to report.

THE SCRATCH COPIES, AND WHY THEY ARE WHERE THEY ARE. `ptx.bend` does
`import ./tc_ptx.bend` and `import ./../uop/ops.bend`, both RELATIVE TO ITS OWN DIRECTORY,
and `bin/bend` resolves them from the FILE (`bin/bend`'s own comment: "`bin/bend` resolves
`import ./x.bend` relative to the FILE's own directory"). A copy anywhere else cannot
resolve them -- MEASURED, it fails with `no such file: .../tries/tinybendygrad/LAWS/spec.bend`,
a path that is not merely wrong but suggests the resolver lost a directory. So the port
copy is written BESIDE `ptx.bend` as `tinybendygrad/renderer/_ptxmut.bend` (the same shape
`.agents/slop/tcptx-mutate.py` already uses) and the driver copy BESIDE the census with its
`import ... as P` repointed. BOTH are removed in a `finally`, and the removal is asserted.

WHICH GUARD IS LOAD-BEARING, SAID HONESTLY
------------------------------------------
Three of these are caught by more than one mechanism, and pretending otherwise would be
the `cstyle` M8 mistake in the other direction -- naming a check because it is in the file
rather than because it is what went red.

  M10 -- the port lane loses its register rows. `gatekit`'s row COUNT catches it first and
    returns DEAD. `names_hold()` also catches it, and its contribution is the DIAGNOSIS: a
    count says "not 579 rows", a name list says "the oracle still has 579 and the port has
    287, and here is the first one the port lost."
  M11 -- two fixtures swap. The positional diff catches it as a wall of value mismatches.
    `names_hold()`'s contribution is naming it as an ORDER fault at one index.
  M12 -- one refusal flag flips. `axis_hold()`'s contribution is REAL and singular: it is
    the only check that compares the census's flag to the GENERATED `# REFUSES` line AND to
    the oracle's own `.mod=REFUSE:` rows, so a flag that drifts on one side only is red
    without any row value being wrong.
  M13 -- `claims_hold()`'s expected string is weakened to whatever the port emits. NOTHING
    ELSE SEES IT: the diff is untouched, `names_hold` is untouched, `axis_hold` is
    untouched, and only `pins_hold()` compares the pins file to the lanes. That is the one
    mutation in this table with a single mechanism, which is why it is in the table.
  M14 and M14b ARE THE GROUP-3a REGRESSIONS, and they exist BECAUSE THE FIX LANDED. The
  six rows they move LEFT `DIVERGES` when the fix landed, so no pin and no divergence can
  see them any more: `claims_hold()` is the only mechanism left that reads them, and a
  check never seen to fail is not a check. M14 is the `rg_alias` arm (six rows, back to
  `NONE`); M14b is the `rg_pick` arm (two rows, both `f37_twobufs`, and ZERO before that
  fixture existed).
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
BEND = ROOT / "bin" / "bend"
PY = ROOT / ".venv" / "bin" / "python"
PORT = ROOT / "tinybendygrad" / "renderer" / "ptx.bend"
PORT_MUT = ROOT / "tinybendygrad" / "renderer" / "_ptxmut.bend"
DRV = HERE / "ptx_render_census.bend"
DRV_MUT = HERE / "_ptxcensus_mut.bend"
AX_MUT = HERE / "_ptxaxis_mut.bend"
ORACLE = HERE / "ptx_render_census-oracle.py"
AXIS = HERE / "ptx_render_census_axis.bend"

PORT_MUTATIONS = [
    ("M1", "pf.of -- a LOAD's list flag: `max_numel > 1` becomes always false, so a vector "
           "LOAD answers a bare string. ptx.py:208.",
     'Bool.pick(Pf, is_op(op, O.OpsLOAD{}), pf1("val", pf.ty_of("", dt), nmn, U32.is_gt(nmn, 1)),',
     'Bool.pick(Pf, is_op(op, O.OpsLOAD{}), pf1("val", pf.ty_of("", dt), nmn, False{}),'),
    ("M2", "arm.of -- CONST leaves the skip list, so it reaches the prefix table and takes "
           "`no_pf()`. ptx.py:187. NOTE: ptx.bend's own notes predict this moves ZERO rows.",
     'Bool.pick(U32, is_any3(op, [O.OpsNOOP{}, O.OpsGROUP{}, O.OpsCONST{}]), A_SKIP(),',
     'Bool.pick(U32, is_any3(op, [O.OpsNOOP{}, O.OpsGROUP{}]), A_SKIP(),'),
    ("M3", "arm.of -- the REG-buffer arm moves BELOW the on-REG arm, so a REG BUFFER is "
           "read as a register load. ptx.py:197 before 200.",
     '  Bool.pick(U32, is_reg(op, addr), A_ALLOC(),\n  Bool.pick(U32, on_regsrc(op, addr), arm.regsrc(op, idx_ok),',
     '  Bool.pick(U32, on_regsrc(op, addr), arm.regsrc(op, idx_ok),\n  Bool.pick(U32, is_reg(op, addr), A_ALLOC(),'),
    ("M4", "on_regsrc -- the ALU arm of `src[0].addrspace in (REG, ALU)` is dropped, so a "
           "LOAD of a SPECIAL becomes a memory read. ptx.py:200.",
     '    Bool.or(O.eq_addr(addr, S.AReg{}), O.eq_addr(addr, S.Aalu{})))',
     '    O.eq_addr(addr, S.AReg{}))'),
    ("M5", "ssa_many -- the bump is ONE instead of `k`, so a four-element REG buffer leaves "
           "the counter at one. ptx.py:198/208 bump once per element.",
     '    ssa_many.ago(U32.to_nat(k), cnt_n(cs, key), cnt_bump(cs, key, ty, k), key))',
     '    ssa_many.ago(U32.to_nat(k), cnt_n(cs, key), cnt_bump(cs, key, ty, 1), key))'),
    ("M6", "fn_kp -- the digit range becomes `or(ge(48), le(57))`, i.e. EVERY character, so "
           "`to_function_name` is the identity. The bug ptx.bend's own notes record.",
     '  Bool.or(Bool.or(Bool.and(U32.is_ge(c, 48), U32.is_le(c, 57)),\n      Bool.and(U32.is_ge(c, 65), U32.is_le(c, 90))),',
     '  Bool.or(Bool.or(Bool.or(U32.is_ge(c, 48), U32.is_le(c, 57)),\n      Bool.and(U32.is_ge(c, 65), U32.is_le(c, 90))),'),
    ("M7", "reg_line -- the `.reg` TYPE comes from the key's FIRST field instead of the "
           "dtype field, so every declaration is `.reg .cast` / `.reg .reg`. ptx.py:165's "
           "`reg.split('_')[-2]`.",
     '  P.fmt(String.concat([".reg .", ty, " %", key, "<", U32.show(n), ">;"]))',
     '  P.fmt(String.concat([".reg .", key, " %", key, "<", U32.show(n), ">;"]))'),
    ("M8", "wk_spec.go -- ptx.py:227 PREPENDS each SPECIAL's `.reg .u32` line and this "
           "APPENDS, so the block reads `%g0, %g1, %g2` instead of `%g2, %g1, %g0`. "
           "THE FIRST DRAFT OF THIS MUTATION WAS A NO-OP and the SECOND WAS REFUSED, and "
           "both are worth recording: the first swapped `List.concat(&2, String, [[x], k])` "
           "for `List.append(&2, String, [x], k)`, and `List.append(a, b)` IS `a ++ b` in "
           "this Bend, so the two spell the SAME list -- a vacuous edit reporting zero rows "
           "moved, which is indistinguishable from a blind until you read the edit. The "
           "second targeted a `List.concat` the file does not contain and the harness's "
           "`exactly once` assertion caught it, which is the assertion earning its keep. The "
           "edit that WORKS is the two ARGUMENTS swapped, because `ptx.bend` is already "
           "prepending and `a ++ b` with the roles exchanged is an append.",
     '  Wal.rput(Wal.kset(w, List.append(&2, String, [P.fmt(line)], Wal.kern(w))), Rg{False{}, [reg]})',
     '  Wal.rput(Wal.kset(w, List.append(&2, String, Wal.kern(w), [P.fmt(line)])), Rg{False{}, [reg]})'),
    ("M9", "arm.regsrc -- a LOAD takes the A_PICK arm, so an on-REG LOAD SUBSCRIPTS the "
           "register instead of copying it. ptx.py:204. MOVED ZERO ROWS for as long as "
           "`rg_at(w, 0)` answered `NONE`, and the census blamed the alias defect for it -- "
           "which was true then and is FALSE now the fix has landed. The real cause is "
           "MEASURED: every on-ALU LOAD in the axis has `src[0]` = a SPECIAL, whose register "
           "is a SCALAR STRING, so `r[u.src[0]]` and `r[u.src[0]][0]` are the same string. "
           "`f38_regload` is the fixture that closes it -- a LOAD of a REG BUFFER, whose "
           "register is a four-element LIST. MEASURED with it: 2 rows moved, and they "
           "are ONE name (`f38_regload.r1`) on the two bend lanes, because the oracle lane "
           "does not move. `{%reg_f32_0, %reg_f32_1, %reg_f32_2, %reg_f32_3}` -> "
           "`%reg_f32_0`.",
     '  Bool.pick(U32, is_op(op, O.OpsLOAD{}), A_ALIAS(),\n  Bool.pick(U32, idx_ok, A_PICK(), A_REFUSE()))',
     '  Bool.pick(U32, False{}, A_ALIAS(),\n  Bool.pick(U32, idx_ok, A_PICK(), A_REFUSE()))'),
    ("M14", "THE REGRESSION FOR GROUP 3a, and it is THE SAME EDIT THE FIX WAS, reversed: "
            "ptx.bend's A_ALIAS arm reads `Wal.r[0]` (STEP ZERO) instead of `Wal.r[refs[0]]`, "
            "which is what ptx.py:189 (`self.r[u] = self.r[u.src[0]]`) and ptx.py:204 say. "
            "It targets the CALL SITE, not `rg_alias` itself, because `rg_pick` calls it too "
            "and mutating the def would move M14b's rows as well -- MEASURED, mutating the "
            "def moved 8 rows and mutating the call site moves 6. Those six rows LEFT "
            "DIVERGES when the fix landed, so nothing in the divergence table sees them any "
            "more and only `claims_hold()` reads them -- which is what makes this the one "
            "mutation that can prove that guard red rather than assume it. Expect SIX ROWS "
            "TO MOVE, back to `NONE`.",
     '    case 2: Wal.rput(w, rg_alias(w, s))',
     '    case 2: Wal.rput(w, rg_at(w, 0))'),
    ("M14b", "THE SAME REGRESSION IN THE OTHER ARM, and it is the one `f37_twobufs` was "
             "ADDED FOR: `rg_pick` reads `Wal.r[0]` instead of `Wal.r[refs[0]]`. MEASURED on "
             "the 579-row census it moves 2 rows and BOTH are `f37_twobufs`, so on the "
             "557-row census before the fixture it moved ZERO -- a correct-looking edit that "
             "no row could see, which is the `M9` shape with a DIFFERENT cause.",
     'rg_pick.pick(List.get(&2, String, Rg.p(rg_alias(w, s)), U32.to_nat(Wk.idx(s))))',
     'rg_pick.pick(List.get(&2, String, Rg.p(rg_at(w, 0)), U32.to_nat(Wk.idx(s))))'),
]

DRV_MUTATIONS = [
    ("M10", "MY OWN GUARD -- `step_one` stops PRINTING the rows it computed, so the port's "
            "lane loses its register rows. `gatekit`'s row COUNT catches it first and would "
            "say DEAD; `names_hold()` catches it too and says WHICH population changed. "
            "Both matter: a count says how many, a name list says which.",
     '''    case _ <> +t :
      do IO<Unit>:
        a : Unit <- pr(String.concat([nm, ".r", U32.show(i)]),
                       Maybe.default(&2, String, List.get(&2, String, rr, 0n), ""))
        return Unit{}''',
     '''    case _ <> +t :
      do IO<Unit>:
        return Unit{}'''),
    ("M11", "MY OWN GUARD -- two fixtures SWAP their AXIS INDICES, so the row names are the "
            "same SET in a different ORDER and every value is wrong. A positional diff "
            "reports it as a wall of value mismatches; `names_hold()` reports the FIRST "
            "INDEX and says the ORDER moved -- which is the diagnosis, not the symptom.",
     '    a : Unit <- one_at("f01_alu", False{}, 0)\n    b : Unit <- one_at("f02_counter", False{}, 1)',
     '    a : Unit <- one_at("f01_alu", False{}, 1)\n    b : Unit <- one_at("f02_counter", False{}, 0)'),
    ("M12", "MY OWN GUARD -- `f19_mixed` is declared a refusal. `axis_hold()` compares the "
            "flag to the generated `# REFUSES` line AND to the oracle's own rows.",
     '    s : Unit <- one_at("f19_mixed", False{}, 18)',
     '    s : Unit <- one_at("f19_mixed", True{}, 18)'),
    ("M13", "MY OWN GUARD -- `claims_hold()` is a Python edit, not a Bend one: the expected "
            "`barrier` value becomes what the port actually emits, so the pin is satisfied "
            "by construction and the check stops meaning anything.",
     None, None),
]


def lanes(driver):
    r = subprocess.run([str(BEND), str(driver)], capture_output=True, text=True)
    if r.returncode != 0:
        said = [l.strip() for l in (r.stderr or "").splitlines() if l.strip()][:6]
        print("      bend said: " + " | ".join(said))
    return {"bd": [l for l in r.stdout.splitlines() if l.strip() and "=" in l]}


def baseline():
    return lanes(DRV)["bd"]


def diff_rows(a, b):
    """By WHOLE `name=value` LINE and never by row NAME.

    `.agents/slop/tcptx-mutate.py` records that a name-comparing harness reported 0 for
    every mutation in two other units. A row NAME is stable while its VALUE moves, so
    comparing names compares nothing.
    """
    sa, sb = set(a), set(b)
    return len(sa ^ sb), [x for x in sorted(sa - sb)][:2], [x for x in sorted(sb - sa)][:2]


# `PORT_PRELUDE` USED TO CARRY M14's `refs0` helper -- a Bend `def` the harness wrote into
# the scratch copy, because at the time the FIX was the mutation and `ptx.bend` had no
# `refs`-aware reader of its own. `ptx.bend` HAS ONE NOW (`rg_src0`, MEASURED: the fix
# landed), so the prelude is EMPTY and `add_prelude` is a no-op kept only so the scratch
# copy is built by ONE code path whatever a future mutation needs. A helper that exists
# only to make a mutation apply is a helper that outlives its reason.
PORT_ANCHOR = "import ./../uop/ops.bend as O\n"
PORT_PRELUDE = ""

def refuse(why):
    """3, and the number the file already PRINTS.

    MEASURED, `main()` at :306-309 wraps `run_port_mutation()` in `except SystemExit` and
    writes `REFUSED: {e}` for each entry, so the word REFUSED was already in this file's
    output and only the code disagreed with it: a string handed to `SystemExit` is 1, which
    is FAIL. All three sites are one class -- a pattern this harness was written against is
    no longer uniquely present, so the edit cannot be applied -- and the class is the same one
    `tc_ptx_types-mutate.py:78` names with a byte-identical message. For `apply()` and
    `add_prelude()` this is LATENT, because the only caller is inside that `except`; for
    `run_guard_mutation()` it is live, because `main()` calls it at :324 with no handler."""
    print(f"== REFUSED, NOT A VERDICT: ptx_render_census-mutate: {why}", file=sys.stderr)
    raise SystemExit(3)


def apply(text, old, new):
    if text.count(old) != 1:
        refuse(f"the edit must appear EXACTLY ONCE; it appears {text.count(old)}")
    return text.replace(old, new)


def add_prelude(text):
    if text.count(PORT_ANCHOR) != 1:
        refuse(f"the import anchor appears {text.count(PORT_ANCHOR)} times, expected 1")
    return text.replace(PORT_ANCHOR, PORT_ANCHOR + PORT_PRELUDE)


def run_port_mutation(name, old, new, base):
    """THREE scratch copies, and the third one is not optional.

    MEASURED: with only the port and the driver repointed, the run answers
    `expected : List<&2, P.Wk> / observed : List<&2, ../tinybendygrad/renderer/ptx.Wk>`.
    Bend TYPES are nominal, `ptx.bend`'s `Wk` under `ptx` is not `ptx.bend`'s `Wk` under
    `_ptxmut`, and `ptx_render_census_axis.bend` spells `P.Wk` with ITS OWN import. So the
    axis is repointed too, and all three are removed in the `finally` and asserted after.
    """
    PORT_MUT.write_text(add_prelude(apply(PORT.read_text(), old, new)))
    DRV_MUT.write_text(DRV.read_text().replace(
        'import ./../tinybendygrad/renderer/ptx.bend as P',
        'import ./../tinybendygrad/renderer/_ptxmut.bend as P').replace(
        'import ./ptx_render_census_axis.bend as AX',
        'import ./_ptxaxis_mut.bend as AX'))
    AX_MUT.write_text(AXIS.read_text().replace(
        'import ./../tinybendygrad/renderer/ptx.bend as P',
        'import ./../tinybendygrad/renderer/_ptxmut.bend as P'))
    try:
        got = lanes(DRV_MUT)["bd"]
        n, only_base, only_mut = diff_rows(base, got)
        print(f"  {name}: {n} rows moved" if got else f"  {name}: THE LANE EMITTED NOTHING")
        for x in only_base[:3]:
            print(f"      base only : {x[:88]}")
        for x in only_mut[:3]:
            print(f"      mut  only : {x[:88]}")
        return n
    finally:
        for p in (PORT_MUT, DRV_MUT, AX_MUT):
            p.unlink(missing_ok=True)


def run_drv_mutation(name, old, new, base):
    DRV_MUT.write_text(apply(DRV.read_text(), old, new))
    try:
        got = lanes(DRV_MUT)["bd"]
        n, only_base, only_mut = diff_rows(base, got)
        print(f"  {name}: {n} rows moved in the PORT lane")
        for x in only_base[:2]:
            print(f"      base only : {x[:88]}")
        for x in only_mut[:2]:
            print(f"      mut  only : {x[:88]}")
        return n
    finally:
        DRV_MUT.unlink(missing_ok=True)


def run_guard_mutation(name):
    """M13 EDITS THE GATE'S OWN PYTHON, so it is run as a subprocess: the gate file is
    copied, the claim is weakened, the copy is EXECUTED, and the exit code is the reading."""
    txt = (HERE / "ptx_render_census-gate.py").read_text()
    old = '"barrier": "bar.sync\\\\t0;"'
    if txt.count(old) != 1:
        refuse(f"M13: the claim string appears {txt.count(old)} times, expected 1")
    d = Path(tempfile.mkdtemp())
    try:
        for f in ("ptx_render_census-gate.py",):
            shutil.copy(HERE / f, d / f)
        for f in HERE.glob("ptx_render_census*"):
            if f.suffix in (".bend", ".rows") and f.name != "_ptxcensus_mut.bend":
                shutil.copy(f, d / f.name)
        (d / "ptx_render_census-gate.py").write_text(
            (d / "ptx_render_census-gate.py").read_text().replace(old, '"barrier": "bar.sync"'))
        shutil.copy(HERE / "gatekit.py", d / "gatekit.py")
        r = subprocess.run([str(PY), str(d / "ptx_render_census-gate.py")],
                           capture_output=True, text=True, cwd=str(ROOT))
        moved = r.returncode != 0
        print(f"  {name}: the gate's own rc is {r.returncode} "
              f"({'RED, the weakened claim is caught' if moved else 'GREEN -- THE CLAIM IS DEAD'})")
        print(f"      {r.stdout.strip().splitlines()[-1][:100] if r.stdout.strip() else ''}")
        return 0 if moved else 1
    finally:
        shutil.rmtree(d, ignore_errors=True)


def main():
    want = set(sys.argv[1:])
    base = baseline()
    print(f"baseline: {len(base)} rows in the PORT lane")
    py = subprocess.run([str(PY), str(ORACLE)], capture_output=True, text=True)
    n, _, _ = diff_rows([l for l in py.stdout.splitlines() if "=" in l], base)
    print(f"oracle vs port, before any mutation: {n} rows differ (the declared divergences)")
    print("\nPORT MUTATIONS -- one edit in tinybendygrad/renderer/ptx.bend")
    for name, desc, old, new in PORT_MUTATIONS:
        if want and name not in want:
            continue
        print(f"  {name}: {desc}")
        try:
            run_port_mutation(name, old, new, base)
        except SystemExit as e:
            print(f"      REFUSED: {e}")
    print("\nDRIVER MUTATIONS -- MY OWN GUARDS, one edit in gates/ptx_render_census.bend")
    for name, desc, old, new in DRV_MUTATIONS:
        if want and name not in want:
            continue
        if old is None:
            continue
        print(f"  {name}: {desc}")
        run_drv_mutation(name, old, new, base)
    if not want or "M13" in want:
        print("\nGATE MUTATIONS -- MY OWN GUARDS, one edit in the GATE's own python")
        print("  M13: claims_hold()'s expected `barrier` value is weakened to whatever the "
              "port emits")
        run_guard_mutation("M13")
    for p in (PORT_MUT, DRV_MUT, AX_MUT):
        assert not p.exists(), f"{p} was left behind"
    print("\nno scratch file survived")
    return 0


if __name__ == "__main__":
    sys.exit(main())