#!/usr/bin/env python3
"""Mutation harness for `wgsl_render_census-gate.py`.

ONE JOB: prove each claim has a mutation, and prove the POPULATION guard speaks
when the population is wrong. Two kinds of mutation are distinguished and the
report keeps them apart, because they fail for different reasons:

  VALUE        one row's ANSWER changes on the port side and the lane diff says
               which rows moved.
  POPULATION   the two sides stop agreeing on WHICH ROWS EXIST, and a row-count
               check must say so by name -- not "the census found no defect".

Every mutation is applied to a COPY of the tree's three files, the gate is run
against the copy through an environment override, and the copy is deleted. The
gate takes its paths from module constants, so the copy is run by importing the
gate module and rewriting the three paths -- the gate's own code is untouched.
"""
import subprocess
import sys

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GATE = ROOT / "gates" / "wgsl_render_census-gate.py"
ORACLE = ROOT / "gates" / "wgsl_render_census-oracle.py"
PORT = ROOT / "tinybendygrad" / "renderer" / "wgsl.bend"
PINS = ROOT / "gates" / "wgsl_render_census-pins.rows"


# The copies live BESIDE THE ORIGINALS, because a copy anywhere else cannot be
# run: `wgsl.bend` imports `./../uop/ops.bend` RELATIVE TO ITS OWN PATH and the
# oracle does `sys.path.insert(0, __file__.rsplit("/gates/", 1)[0])`. A copy in
# a tmpdir therefore reported `the substrate did not warm` -- which is a REFUSED
# exit for the wrong reason, and a harness that answers "the mutation was found"
# because the file could not be found at all has learned nothing.
MUT_PORT = ROOT / "tinybendygrad" / "renderer" / ".wgsl-mut.bend"
MUT_ORACLE = ROOT / "gates" / ".wgsl-mut-oracle.py"
MUT_PINS = ROOT / "gates" / ".wgsl-mut-pins.rows"
MUT_RUN = ROOT / "gates" / ".wgsl-mut-run.py"


def run_tree(port_text=None, oracle_text=None, pins_text=None):
    """Run the gate against a MUTATED COPY of the tree and return
    `(rc, stdout+stderr)`. Every copy is removed, including on a crash."""
    for dst, text, orig in ((MUT_PORT, port_text, PORT),
                            (MUT_ORACLE, oracle_text, ORACLE),
                            (MUT_PINS, pins_text, PINS)):
        dst.write_text(orig.read_text() if text is None else text)
    MUT_RUN.write_text(
        "import importlib.util, sys\n"
        "from pathlib import Path\n"
        f"spec = importlib.util.spec_from_file_location('g', {str(GATE)!r})\n"
        "m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)\n"
        f"m.PORT = Path({str(MUT_PORT)!r})\n"
        f"m.ORACLE = Path({str(MUT_ORACLE)!r})\n"
        f"m.PINS = Path({str(MUT_PINS)!r})\n"
        "m.BEND_SRC = None\n"
        # DIVERGES IS READ AT IMPORT TIME, so overriding m.PINS alone would leave
        # the mutated pins unused and every pin mutation a silent green.
        "m.DIVERGES, m.WHY = m._pins()\n"
        "sys.exit(m.main())\n")
    try:
        r = subprocess.run([sys.executable, str(MUT_RUN)], capture_output=True,
                           text=True, cwd=str(ROOT))
        return r.returncode, r.stdout + r.stderr
    finally:
        for p in (MUT_PORT, MUT_ORACLE, MUT_PINS, MUT_RUN):
            p.unlink(missing_ok=True)


PORT_T = PORT.read_text()
ORACLE_T = ORACLE.read_text()

# (label, kind, file, old, new)
MUTATIONS = [
    # -- VALUE: one row's answer on the port side.
    ("M37 sr_buchar's mask is 0xFF00", "VALUE", "port",
     'String.concat(["bitcast<u32>(", s, "&0xFF)"])',
     'String.concat(["bitcast<u32>(", s, "&0xFF00)"])'),
    ("M38 sr_bchar's shift is <<8", "VALUE", "port",
     'String.concat(["((i32(", s, "&0xFF)<<24)>>24)"])',
     'String.concat(["((i32(", s, "&0xFF)<<8)>>8)"])'),
    ("M39 sr_bshort stops sign-extending", "VALUE", "port",
     'String.concat(["((i32(", s, "&0xFFFF)<<16)>>16)"])',
     'String.concat(["i32(", s, "&0xFFFF)"])'),
    ("M40 sr_bany drops the type argument", "VALUE", "port",
     'String.concat(["bitcast<", type_map(d), ">(", s, ")"])',
     'String.concat(["bitcast<>(", s, ")"])'),
    ("M41 sr_bushort's half arm loses its vec2", "VALUE", "port",
     'String.concat(["bitcast<u32>(vec2<f16>(", s, ",0))"])',
     'String.concat(["bitcast<u32>(", s, ",0)"])'),
    ("M42 sr_rmw's atomicAdd loses its newline", "VALUE", "port",
     'String.concat(["\\n  atomicAdd(&", b, ",", nv, ");"])',
     'String.concat([" atomicAdd(&", b, ",", nv, ");"])'),
    ("M43 sr_lgate's select is a ternary", "VALUE", "port",
     'String.concat(["select(", v, ", ", render_load(i0, n0, d0, a0), ", ", g, ")"])',
     'String.concat(["(", g, " ? ", v, " : ", render_load(i0, n0, d0, a0), ")"])'),
    ("M44 sr_index never strips parens", "VALUE", "port",
     'String.concat([b, "[", Bool.pick(String, isadd, H.strip_parens(i), i), "]"])',
     'String.concat([b, "[", i, "]"])'),
    ("M49 sr_idx's guard is dropped", "VALUE", "port",
     'def sr_idx(pk: Bool, x: String) -> String: Bool.pick(String, pk, x, "NOMATCH")',
     'def sr_idx(pk: Bool, x: String) -> String: x'),
    ("M50 sr_ci32 truncates to 64 bits", "VALUE", "port",
     'def sr_ci32.trunc(+v: H.I64) -> H.I64: H.i64_of_i32(H.lo32(v))',
     'def sr_ci32.trunc(+v: H.I64) -> H.I64: v'),
    ("M51 sr_cuint forgets the u32 mask", "VALUE", "port",
     'def sr_cuint.masked(+v: H.I64) -> H.I64: H.i64_of_hi_lo(0, H.lo32(v))',
     'def sr_cuint.masked(+v: H.I64) -> H.I64: v'),
    ("M52 sr_buffer drops the space after the colon", "VALUE", "port",
     '" ", nm, ": array<",', 'nm, ":array<",'),
    ("M53 ssimp walks ONE cast, not the chain", "VALUE", "port",
     'def ssimp(+ar: O.Arena, +x: U32) -> U32: ss_go.go(4n, ar, x)',
     'def ssimp(+ar: O.Arena, +x: U32) -> U32: ss_go.go(2n, ar, x)'),
    ("M54 type_map's KeyError arm answers nothing", "VALUE", "port",
     'def type_map.miss(+dt: S.Dt) -> String: String.concat(["UNHANDLED(dtypes.", dt_name(dt), ")"])',
     'def type_map.miss(+dt: S.Dt) -> String: ""'),
    # -- POPULATION: the two sides stop agreeing on WHICH ROWS EXIST.
    ("P1 the port drops rule 16's whole row group", "POPULATION", "port",
     "r_rk_half_no(O.Arena.empty()), r_bd(), r_pt(), r_rk_alu(), r_rk_mixed(fx), r_rk_empty(), r_srs()])",
     "r_rk_half_no(O.Arena.empty()), r_bd(), r_pt(), r_rk_alu(), r_rk_mixed(fx), r_rk_empty()])"),
    ("P2 the port drops ONE row from a group", "POPULATION", "port",
     ',\n    r_sr("store", sr_store("B", "V"), "B = V;")])', "])"),
    ("P3 the ORACLE drops one rule's rows", "POPULATION", "oracle",
     '    r_(11, "bany", UOp(Ops.BITCAST, src=(ch,), arg=dtypes.float), {ch: "S"})\n', ''),
    ("P9 the port DUPLICATES a row name (count still matches)",
     "POPULATION", "port",
     'r_sr("bany", sr_bany(S.single(), "S"), "bitcast<f32>(S)")',
     'r_sr("bushort", sr_bany(S.single(), "S"), "bitcast<f32>(S)")'),
    ("P4 the port RENAMES a row (same count, new name)", "POPULATION", "port",
     'r_sr("bushort half", sr_bushort(True{}, "S"), "bitcast<u32>(vec2<f16>(S,0))")',
     'r_sr("bushort f16", sr_bushort(True{}, "S"), "bitcast<u32>(vec2<f16>(S,0))")'),
    ("P5 the pins lose a pinned divergence", "POPULATION", "pins",
     "code_for_op LOAD\tREFUSE:KeyError\tUNHANDLED(Ops.LOAD)\tLANE\n", ""),
    ("P6 a pin's PORT VALUE is edited", "POPULATION", "pins",
     "code_for_op FDIV\tREFUSE:KeyError\t(A/B)\tLANE",
     "code_for_op FDIV\tREFUSE:KeyError\t(A / B)\tLANE"),
    ("P7 the port's fixture axis drifts", "POPULATION", "port",
     'r_cu1("-1", 4294967295, 4294967295, "bitcast<u32>(-1)")',
     'r_cu1("-1", 0, 4294967295, "bitcast<u32>(-1)")'),
    ("P8 the oracle's fixture axis drifts", "POPULATION", "oracle",
     'SR_CI = [("7", 0, 7), ("-3", 4294967295, 4294967293), ("4294967295", 0, 4294967295),\n         ("4294967296", 1, 0)]',
     'SR_CI = [("7", 0, 7), ("-3", 0, 4294967293), ("4294967295", 0, 4294967295),\n         ("4294967296", 1, 0)]'),
]


def main():
    rc0, out0 = run_tree()
    print(f"UNMUTATED  rc={rc0}")
    if rc0 != 0:
        print(out0)
        return 1
    width = max(len(m[0]) for m in MUTATIONS)
    for label, kind, f, old, new in MUTATIONS:
        if f == "port":
            text = PORT_T
            if text.count(old) != 1:
                print(f"  {label:<{width}}  SKIPPED: {text.count(old)} matches "
                      f"for the pattern")
                continue
            rc, out = run_tree(port_text=text.replace(old, new))
        elif f == "oracle":
            text = ORACLE_T
            if text.count(old) != 1:
                print(f"  {label:<{width}}  SKIPPED: {text.count(old)} matches "
                      f"for the pattern")
                continue
            rc, out = run_tree(oracle_text=text.replace(old, new))
        else:
            text = PINS.read_text()
            if text.count(old) != 1:
                print(f"  {label:<{width}}  SKIPPED: {text.count(old)} matches "
                      f"for the pattern")
                continue
            rc, out = run_tree(pins_text=text.replace(old, new))
        said = [ln.strip() for ln in out.splitlines()
                if ": OK" not in ln
                and (ln.strip().startswith(("DISAGREE", "names_hold:", "norm_hold:",
                                            "rules_hold:", "fixtures_hold:",
                                            "divergences_hold:", "classes_hold:",
                                            "selfcheck_hold:", "axes_hold:",
                                            "dead_defs_hold:",
                                            "never_folding_cast_hold:",
                                            "pin_drift_hold:", "the substrate",
                                            "lane "))
                     or "appears " in ln)]
        verdict = "RED" if rc != 0 else "GREEN  <-- THE MUTATION WAS NOT FOUND"
        print(f"  {label:<{width}}  [{kind}]  rc={rc} {verdict}")
        # A RED THAT NAMES NOTHING is reported as such rather than as a pass: the
        # exit status said FAIL and the reason is the instrument's business, and
        # printing three of the last lines at least shows what it said.
        for ln in said[:5] or ([l.strip() for l in out.splitlines() if l.strip()][-2:] if rc else []):
            print(f"      {ln[:160]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())