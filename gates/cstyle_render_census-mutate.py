#!/usr/bin/env python3
"""Mutation harness for `cstyle_render_census-gate.py`. This gate HAD NONE, which is why a
whole session could read it green and never learn that half its claims had no mutation.

    .venv/bin/python gates/cstyle_render_census-mutate.py

ONE JOB: every claim the gate makes is either MOVED by a mutation or is named here as a claim
with no mutation. A mutation that moves zero rows is a DELIVERABLE, not a shrug -- it is a
coverage gap (the row exists but nothing reads the field the mutation touched) or a DEAD def
(nothing calls it), and the report says which.

THE PORT COPY LIVES BESIDE THE ORIGINAL. `cstyle.bend` imports `./../uop/ops.bend` RELATIVE TO
ITS OWN PATH and the oracle does `sys.path.insert(0, __file__.rsplit("/gates/", 1)[0])`, so a
copy anywhere else cannot be run and would report "the mutation was found" for the wrong reason.
Same shape as `wgsl_render_census-mutate.py:35-38`, and for the same measured reason.

KIND is what the mutation is FOR, and the two are reported apart because they fail differently:

  REFUSAL  the mutation removes or mutes a REFUSAL, so the row must move off its pinned
           refusal token. Nine of the fifteen pins are of this kind and none of them existed
           as a checkable claim before `UNHANDLED` -- they were `""` on both sides of a pin.
  INPUT    the mutation makes a row's ANSWER depend on a field the fixture varies. These are
           the mutations that answer "is there a row whose value cannot change", which is the
           failure `amd_dsl_census` found as `String.eq("vdst","vdst")`: a renderer that always
           takes one branch prints plausible text for an input it never read.
  VALUE    a rendering, not a refusal.
  MARKER   the oracle's `REFUSE:` prefix, which is this lane's own vocabulary.
"""
import subprocess
import sys

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BEND = ROOT / "bin" / "bend"
PY = ROOT / ".venv" / "bin" / "python"
GATE = ROOT / "gates" / "cstyle_render_census-gate.py"
ORACLE = ROOT / "gates" / "cstyle_render_census-oracle.py"
DRIVER = ROOT / "gates" / "cstyle_render_census.bend"
PORT = ROOT / "tinybendygrad" / "renderer" / "cstyle.bend"

# TWO COPIES, NOT ONE, AND THE SECOND IS THE WHOLE LESSON. `Gate.bend` is the DRIVER
# (`gates/cstyle_render_census.bend`), and the driver reaches the port by an IMPORT PATH:
# `import ./../tinybendygrad/renderer/cstyle.bend as C` (line 66). Pointing `GATE.bend` at a
# mutated COPY of `cstyle.bend` therefore runs the PORT as if it were the driver -- it has no
# `main`, emits zero rows, and `gatekit.py:_lane` reports `lane bd.out did not produce 358
# rows in 25 tries (the flake)`, exit DEAD. That reading is about a mis-wired harness and
# looks exactly like the machine-stack flake it is not. So the port is copied AND the driver's
# import line is rewritten to name the copy.
#
# THE COPY IS NOT DOT-PREFIXED, AND THAT IS ALSO MEASURED: `cstyle-mut.bend` as an import
# target gives `Error: - expected : an import path of plain names (letters, digits, _ and -)`
# and the gate REFUSES (3). `wgsl_render_census-mutate.py` gets away with `.wgsl-mut.bend`
# only because there the mutated file IS the driver, which `bend` runs by argv and never
# imports by name. Both copies are removed in `finally`.
MUT_PORT = ROOT / "tinybendygrad" / "renderer" / "cstyle-mut.bend"
MUT_BEND = ROOT / "gates" / "cstyle-mut-driver.bend"
MUT_ORACLE = ROOT / "gates" / "cstyle-mut-oracle.py"
MUT_RUN = ROOT / "gates" / "cstyle-mut-run.py"
# INSIDE `gates/artifacts/`, which `Gate._ensure_dir` already creates (`gatekit.py:_ensure_dir`
# builds the MODULE-level `ART`, not `self.dir`). A mutant directory outside it does not exist,
# and `_lane`'s `out.write_text` then raises inside the retry loop -- which surfaces as DEAD
# with "did not produce 358 rows in 25 tries", a verdict about the flake that is really about
# a missing directory. `gates/artifacts/` is `.gitignore`d, so the mutants leave no trace.
MUT_ART = ROOT / "gates" / "artifacts" / "cstyle-mut"

DRIVER_IMPORT = "import ./../tinybendygrad/renderer/cstyle.bend as C"
DRIVER_MUT_IMPORT = "import ./../tinybendygrad/renderer/cstyle-mut.bend as C"


def stage(port_text=None, oracle_text=None):
    """Write the mutant copies. The driver copy is what `bend` runs; the port copy is what it
    imports. Both are removed by `unstage`."""
    for dst, text, orig in ((MUT_PORT, port_text, PORT), (MUT_ORACLE, oracle_text, ORACLE)):
        dst.write_text(orig.read_text() if text is None else text)
    driver = DRIVER.read_text()
    assert driver.count(DRIVER_IMPORT) == 1, "the driver's import of the port is not unique"
    MUT_BEND.write_text(driver.replace(DRIVER_IMPORT, DRIVER_MUT_IMPORT))


def unstage():
    for p in (MUT_PORT, MUT_BEND, MUT_ORACLE, MUT_RUN):
        p.unlink(missing_ok=True)


def run_gate():
    """The gate's VERDICT on the staged mutant, with its own code untouched: the runner imports
    it and rewrites the resolved paths on the `Gate` instance."""
    MUT_RUN.write_text(
        "import importlib.util, sys\n"
        "from pathlib import Path\n"
        f"spec = importlib.util.spec_from_file_location('g', {str(GATE)!r})\n"
        "m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)\n"
        f"m.GATE.bend = Path({str(MUT_BEND)!r})\n"
        f"m.GATE.oracle = Path({str(MUT_ORACLE)!r})\n"
        f"m.GATE.dir = Path({str(MUT_ART)!r})\n"
        "sys.exit(m.gate(m.GATE, 'mutant', checks=m.port_artifact_claims))\n")
    try:
        r = subprocess.run([str(PY), str(MUT_RUN)], capture_output=True, text=True, cwd=str(ROOT))
        return r.returncode, r.stdout + r.stderr
    finally:
        MUT_RUN.unlink(missing_ok=True)


def read_rows(text):
    out = {}
    for line in text.splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            out[k] = v
    return out


def capture_lanes():
    """`{row: value}` from the mutant's OWN oracle and driver, run directly.

    NOT read out of `gates/artifacts/`, and that is measured, not preferred: `gatekit` clears
    the artifact directory before any check can fail (`gatekit.py`'s `_clear` note -- "both
    gates go rc=2 with an EMPTY directory"), so a RED run leaves no lane file and the harness
    read `NO LANES` for all eleven mutations while the gate was in fact catching every one.
    Running the two lanes by hand is what makes the reading independent of the verdict, which
    is the whole point: a mutation that moves rows must be COUNTED, not inferred from rc.
    """
    o = subprocess.run([str(PY), str(MUT_ORACLE)], capture_output=True, text=True, cwd=str(ROOT))
    b = subprocess.run([str(BEND), str(MUT_BEND)], capture_output=True, text=True, cwd=str(ROOT))
    out = {f"py:{k}": v for k, v in read_rows(o.stdout).items()}
    out.update({f"bd:{k}": v for k, v in read_rows(b.stdout).items()})
    return out


def rows_moved(base, now):
    """The rows whose VALUE differs from the unmutated run, `lane:name` qualified."""
    return {k for k in set(base) | set(now) if base.get(k) != now.get(k)}


# (label, kind, file, old, new). `old` must be a UNIQUE substring: an anchor that appears
# twice would mutate an unrelated arm and the reading would name the wrong row.
MUTATIONS = [
    # -- REFUSAL. Each of the nine was `""` on the port side until this session; a mutation
    # back to `""` is the reading that says the pin is load-bearing rather than decorative.
    ("M1 base's dropped-arm answer is nothing again", "REFUSAL", "port",
     "    case _: cfo_unhandled(op)", '    case _: ""'),
    ("M2 Clang keeps the four it DELETED (arms removed)", "REFUSAL", "port",
     "    case O.OpsEXP2{}: cfo_unhandled(op)\n"
     "    case O.OpsSIN{}: cfo_unhandled(op)\n"
     "    case O.OpsLOG2{}: cfo_unhandled(op)\n"
     "    case O.OpsRECIPROCAL{}: cfo_unhandled(op)\n", ""),
    ("M3 the empty workitem dict answers nothing again", "REFUSAL", "port",
     "    case _: witem_miss(k)", '    case _: ""'),
    ("M4 base float4 is the empty string again", "REFUSAL", "port",
     '    case _: "None"', '    case _: ""'),
    # -- INPUT. These answer "can this row's value move at all", which is the class
    # `amd_dsl_census` found as a literal compared with itself.
    ("M5 the ALU refusal stops naming its op", "INPUT", "port",
     'def cfo_unhandled(op: O.Op) -> String: '
     'String.concat(["UNHANDLED(Ops.", O.Ops.name.of(op), ")"])',
     'def cfo_unhandled(op: O.Op) -> String: "UNHANDLED(Ops.X)"'),
    ("M6 the workitem refusal stops naming its key", "INPUT", "port",
     'def witem_miss(+k: String) -> String: '
     'String.concat(["UNHANDLED(code_for_workitem[", k, "])"])',
     'def witem_miss(+k: String) -> String: "UNHANDLED(code_for_workitem[g])"'),
    ("M7 the workgroup axis is off by one letter", "INPUT", "port",
     "Char.from_u32(U32.add(120, n))", "Char.from_u32(U32.add(121, n))"),
    ("M8 render_index never strips parens", "INPUT", "port",
     "Bool.pick(String, idx_arg_is_add(O.Arena.arg(ar, idx)), H.strip_parens(iname), iname)",
     "iname"),  # MEASURED 0 of 358 rows, rc=0, before `ri_lit_*` existed. Moves 3 of 361 now.
    # -- VALUE. A rendering, not a refusal.
    ("M9 the unary ALU template loses its parens", "VALUE", "port",
     'def cfo_unary(nm: String, +x: String) -> String: String.concat([nm, "(", x, ")"])',
     'def cfo_unary(nm: String, +x: String) -> String: String.concat([nm, x])'),
    ("M10 the reciprocal template is the unary one", "VALUE", "port",
     'def cfo_recip(+x: String) -> String: String.concat(["(1/", x, ")"])',
     'def cfo_recip(+x: String) -> String: String.concat(["(1", x, ")"])'),
    # -- MARKER. The oracle's own vocabulary; `wgsl_render_census-oracle.py:222` and
    # `amd_dsl_census-oracle.py:120` are the two precedents for it.
    ("M11 the oracle drops the REFUSE marker", "MARKER", "oracle",
     'return f"REFUSE:{type(e).__name__}"', "return type(e).__name__"),
]

# M8 IS THE ONE THAT ANSWERED NOTHING, and it is why this file exists rather than a list of
# asserts. The census drove ONE shape of `render_index`'s index arg, `arg=(Ops.ADD, 0)`, and on
# that node CPython's `idx.arg == Ops.ADD` is FALSE -- a tuple never equals an enum -- AND the
# port's `idx_arg_is_add` is FALSE, because the fix that closed the `ri_add_*` defect moved it
# from `AReduce{ADD,0}` to `AOpLit{op}` and `AReduce` is not `AOpLit`. BOTH lanes took the
# do-not-strip arm and agreed, so `H.strip_parens` had NO ROW ANYWHERE: the branch the census's
# central FINDING was about was the one branch with no rows on it. MEASURED 0 of 358, rc=0.
#
# `ri_lit_*` drives `AOpLit{OpsADD{}}` -- what `upat.py:26`'s `UOp(Ops.PYLITERAL,
# arg=self.op[0])` builds, and the only shape CPython strips on -- and M8 now moves 3.
#
# THAT IS THE POINT OF THE WHOLE FILE. A fix that makes a branch UNREACHED is
# indistinguishable from a fix that makes it unreachable, the gate is rc=0 in both worlds, and
# the row named after the defect (`ri_add_*`: an ADD fixture rendering `(a+b)`) reads like a
# paren-stripping test while testing none. Only a mutation that moves nothing separates them.


def main():
    stage()
    base, rc0 = capture_lanes(), run_gate()[0]
    unstage()
    print(f"-- unmutated: rc={rc0}, {len(base)} lane rows")
    if rc0 != 0 or len(base) != 722:      # 361 py + 361 bd
        print("-- the unmutated tree does not reproduce; nothing below would mean anything")
        return 1
    moved, still_green = [], []
    for label, kind, target, old, new in MUTATIONS:
        path = PORT if target == "port" else ORACLE
        text = path.read_text()
        if text.count(old) != 1:
            print(f"!! {label}: anchor appears {text.count(old)} times -- NOT RUN")
            still_green.append((label, kind, "ANCHOR NOT UNIQUE"))
            continue
        mutated = text.replace(old, new)
        try:
            stage(port_text=mutated) if target == "port" else stage(oracle_text=mutated)
            names = rows_moved(base, capture_lanes())
            rc = run_gate()[0]
        finally:
            unstage()
        if rc == 0 or not names:
            still_green.append((label, kind, f"rc={rc} rows={len(names)}"))
            print(f"!! {label}: rc={rc}, {len(names)} row(s) moved -- CAUGHT NOTHING")
            continue
        moved.append((label, kind, len(names)))
        short = sorted(names)
        shown = ", ".join(n.split(":", 1)[1] for n in short if n.startswith("bd:") or True)
        print(f"ok {label}: rc={rc}, {len(short)} row(s): {shown}")
    print(f"\n== {len(moved)} of {len(MUTATIONS)} mutations moved rows")
    if still_green:
        print("== DELIVERABLE -- these moved NOTHING, and each is named rather than re-run:")
        for label, kind, why in still_green:
            print(f"   {label}  [{kind}]  {why}")
    return 1 if still_green else 0


if __name__ == "__main__":
    raise SystemExit(main())
