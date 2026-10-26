#!/usr/bin/env python3
"""THE PLANTS: FOUR ONE-LINE BREAKAGES THAT PUT THE 29 DIVERGENCES BACK.

    .venv/bin/python .agents/slop/vslane/plant.py <plant> [<plant> ...]

**THE POINT OF A PLANT IS THAT IT PUTS THE DIVERGENCES BACK.** A FIX WITH NO
PLANT IS A CLAIM; A FIX WITH A PLANT IS A CAUSE.

THE PLANTS ARE APPLIED TO A **COPY** OF THE PORT'S OWN TREE, IN
`.agents/slop/vslane/plant/tree/`, AND THE COPY IS BUILT WITH THE TREE'S OWN
`bin/bend`. **THE PORT'S FILES ARE NEVER TOUCHED** -- the copy is what breaks.

WHY A COPY AND NOT THE LIVE FILE: `ops_python.bend`'s imports are RELATIVE
(`import ../base.bend as F`), so a mutated copy has to sit at the same depth in
a tree that holds the same neighbours. THE COPY IS A WHOLE `tinybendygrad/`
TREE, SO THE RELATIVE IMPORTS RESOLVE INSIDE IT AND NOTHING ELSE IS NEEDED.

THE MEASUREMENT IS THE TREE'S OWN: `.agents/slop/execfix/census.py`'s runner,
over the tree's own fixture file, against CPython's own rows
(`.agents/slop/vslane/oracle.rows`).

**EACH PLANT NAMES THE EXACT BYTES IT REPLACES**, SO A PLANT THAT STOPS
FIRING IS A PLANT THAT NO LONGER DESCRIBES THE FILE -- NOT A MYSTERY.
"""
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / ".agents" / "slop" / "execfix"))
import census  # noqa: E402

TREE = HERE / "plant" / "tree"
BEND = ROOT / "bin" / "bend"

# (name, relative path, the bytes the fix introduced, the bytes the plant puts back,
#  the fixtures whose rows the plant must make diverge again)
PLANTS = {
    "where": (
        "tinybendygrad/uop/symbolic.bend",
        "def f32_where(cond: Bool, b: F32, c: F32) -> F32: Bool.pick(F32, cond, b, c)",
        "def f32_where(cond: Bool, b: F32, c: F32) -> F32: Bool.pick(F32, cond, c, b)",
        ["f32.sqrt.0", "f32.log2.0", "f32.exp2.0", "f32.recip.0"],
    ),
    "cmpne": (
        "tinybendygrad/uop/symbolic.bend",
        "    case O.OpsCMPNE{} I3{2, +a, +b, _}: Some{sy_bool_c(U32.is_ne(a, b))}",
        "    case O.OpsCMPNE{} I3{2, +a, +b, _}: Some{sy_bool_c(U32.is_eq(a, b))}",
        ["i32.sqrt.0", "u32.ne.0", "bool.ne.0", "bool.neg.0", "bool.sub.0", "bool.matmul.0"],
    ),
    "cast": (
        "tinybendygrad/runtime/ops_python.bend",
        "      Bool.pick(Elem, S.Dt.is_float(src), elem_of(f32_int_bits(f_of(e)), dst),",
        "      Bool.pick(Elem, S.Dt.is_float(src), elem_of(F32.bits(F32.trunc(f_of(e))), dst),",
        ["f32.bitcast.0", "f32.shl.0", "f32.shr.0", "f32.cmod.0"],
    ),
    "store": (
        "tinybendygrad/runtime/ops_python.bend",
        "  Elem.bits(Prog.cast.dt(Buf.dt(Prog.buf(p, u)), Elem.dt(Prog.store.elem(p, u, j)),\n"
        "    Prog.store.elem(p, u, j)))",
        "  Elem.bits(Prog.store.elem(p, u, j))",
        ["alu.CMPNE.f"],
    ),
}


def rows(path):
    out = {}
    for ln in pathlib.Path(path).read_text().splitlines():
        if "=" in ln:
            k, v = ln.split("=", 1)
            out[k] = v
    return out


def build_tree():
    """A FRESH COPY OF THE PORT'S TREE, so a plant can never leak into the next one."""
    if TREE.exists():
        shutil.rmtree(TREE)
    TREE.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(ROOT / "tinybendygrad", TREE / "tinybendygrad")


def plant(name):
    if name == "all":
        # THE WHOLE PINNED POPULATION, READ FROM THE TREE's OWN PINS FILE.
        pins = [l.split()[0].rsplit(".b", 1)[0] for l in
                (ROOT / "gates" / "ops_python_exec-pins.rows").read_text().splitlines()
                if l.strip() and not l.startswith("#")]
        # EVERY FIX AT ONCE, WHICH IS THE **JOINT** CONTROL: THE BASE ROWS ARE
        # WHAT THE TREE ANSWERED WITH ALL FOUR BUGS PRESENT, SO REVERTING ALL
        # FOUR MUST REPRODUCE THEM BYTE FOR BYTE.
        names = [k for k in PLANTS if k != "all"]
    else:
        names = [name]
    fixtures = set()
    for nm in names:
        rel, new, old, fx = PLANTS[nm]
        path = TREE / rel
        src = path.read_text()
        if new not in src:
            raise SystemExit(f"== REFUSED, NOT A VERDICT: the plant {nm!r} does not describe "
                             f"{rel} -- the bytes it replaces are NOT in the file")
        path.write_text(src.replace(new, old, 1))
        fixtures |= set(fx)
    if name == "all":
        fixtures = set(pins)
    return sorted(fixtures)


def build(name):
    exe = TREE.parent / f"bend-executor-{name}"
    src = TREE / "tinybendygrad" / "runtime" / "ops_python.bend"
    r = subprocess.run([str(BEND), str(src), "-o", str(exe)], capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f"== REFUSED, NOT A VERDICT: the plant {name!r} did not build:\n"
                         f"{(r.stdout + r.stderr).strip()[-800:]}")
    return exe


def run(exe, fixtures):
    import tempfile
    got = {}
    with tempfile.TemporaryDirectory(prefix="vslane-plant-") as td:
        td = pathlib.Path(td)
        for n, a, p in census.fixtures():
            if n not in fixtures:
                continue
            for row in census.run_one(exe, td, n, a, p):
                k, v = row.split("=", 1)
                got[k] = v
    return got


def main():
    want = sys.argv[1:] or (["all"] + sorted(PLANTS))
    py = rows(HERE / "oracle.rows")
    bad = 0
    for name in want:
        build_tree()
        fixtures = plant(name)
        exe = build(name)
        got = run(exe, fixtures)
        div = [k for k in sorted(got) if py.get(k) is not None and py[k] != got[k]]
        print(f"== PLANT {name}: {len(div)} of {len(got)} rows diverge again")
        for k in div:
            print(f"   {k}\n     py {py.get(k)}\n     bd {got[k]}")
        if not div:
            print("   == THE PLANT DID NOT PUT THE DIVERGENCES BACK -- THE PLANT IS NOT A CAUSE")
            bad += 1
    shutil.rmtree(TREE.parent, ignore_errors=True)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
