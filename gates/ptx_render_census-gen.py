#!/usr/bin/env python3
"""ptx_render_census-gen.py -- emit the BEND fixture axis from CPython's OWN graphs.

    .venv/bin/python gates/ptx_render_census-gen.py > gates/ptx_render_census_axis.bend

WHY A GENERATOR AND NOT A HAND LIST. `AGENTS.md`, doctrine 1: a population is a
generator's own declaration, loaded by path. `ptx.bend`'s OWN fixtures are a hand-written
transcription of the same graphs into `Wk` records, and the oracle that checked them
(`.agents/slop/ptx-s3-oracle.py`) and the script that generated the pins
(`.agents/slop/ptx-s3-gen.py`) are BOTH DELETED -- so nothing can check that transcription
today. Generating the axis from the graph itself removes the transcription from the
comparison entirely: the two lanes then differ only in NOTATION, never in CONTENT.

THE AXIS IS ANNOUNCED, NOT DISCOVERED, AND SAID SO. Every fixture here is an ARBITRARY
CHOICE of graph (which ops, which dtypes, which numels); no CPython call RETURNS "the list
of interesting PTX kernels". What is NOT admitted is the per-node transcription: `op`,
`dtype`, `addrspace`, `max_numel`, `arg`, the src indices, the CONST subscript and the
CONST-of-CAST flag are all READ OFF THE NODE CPYTHON BUILT.

ONE SHAPE IS A CHOICE, AND IT IS THE ONLY ONE: `Wk.nmn` is `u.max_numel()`. A REG BUFFER
of four elements and a LOAD of four elements both give 4, and ptx.py:198/208 read the same
number for both -- so there is nothing to choose.
"""
import ast
import hashlib
import importlib.util
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
src = (HERE / "ptx_render_census-oracle.py").read_text().split("if __name__")[0]
G = {"__name__": "gen"}
exec(compile(src, "oracle", "exec"), G)

UOp, Ops, FIXTURES, AddrSpace = G["UOp"], G["Ops"], G["FIXTURES"], G["AddrSpace"]
KernelInfo = G["KernelInfo"]

# `dtypes.__getattr__` SPELLS a dtype `i32`, `u32`, `f32`, `fp8_e4m3` ... -- the aliases the
# tinygrad laws call `int32`, `single`, `half`. This table is the ALIAS SPELLING and nothing
# else: it is a NAME map between two vocabularies, and it is asserted against
# `gates/ptx_render_census-oracle.py`'s own `tyo_*` axis by the gate, so a dtype that moves
# on one side only is red before any value is compared.
DT = {"void": "void", "bool": "boolean", "i8": "int8", "u8": "uint8", "i16": "int16",
      "u16": "uint16", "i32": "int32", "u32": "uint32", "i64": "int64",
      "u64": "uint64", "f16": "half", "bf16": "bfloat16", "f32": "single", "f64": "double",
      "fp8_e4m3": "fp8e4m3", "fp8_e5m2": "fp8e5m2", "fp8_e4m3fnuz": "fp8e4m3fnuz",
      "fp8_e5m2fnuz": "fp8e5m2fnuz", "weakint": "weakint", "weakfloat": "weakfloat",
      "index": "weakint"}
ADDR = {AddrSpace.REG: "AReg", AddrSpace.LOCAL: "ALocal", AddrSpace.GLOBAL: "AGlobal",
        AddrSpace.ALU: "Aalu", None: "Aalu"}


def dt_of(d):
    nm = d.name if hasattr(d, "name") else str(d).rsplit(".", 1)[-1]
    if nm not in DT:
        print(f"== REFUSED, NOT A VERDICT: ptx_render_census-gen: unmapped dtype {d!r} -- "
              f"DT covers {len(DT)} names and this one is not among them, so the axis "
              "cannot be emitted", file=sys.stderr)
        raise SystemExit(3)   # 3, NOT 1: this generator's whole job is to emit every node
                              # CPython built, and a name it cannot map is a node it cannot
                              # emit -- the lane measured nothing. A string was 1, which is
                              # FAIL, and FAIL says the answer was wrong. See the sibling
                              # `gates/crp_graph_census-oracle.py`, whose own docstring calls
                              # the same class "THE EMPTY POPULATION IS REFUSED, NOT RETURNED".
    return "S." + DT[nm] + "()"


def upstream_modules():
    """The `tinygrad.*` MODULES the oracle's own imports name, plus the modules that DEFINE
    the symbols it takes from them.

    WHY THE SECOND HALF IS NOT OPTIONAL, AND IT IS THE ENUM. The oracle says
    `from tinygrad.uop.ops import UOp, Ops, KernelInfo`, and `Ops` -- THE ENUM THIS WHOLE
    STORY IS ABOUT -- is not defined in `tinygrad/uop/ops.py`: `ops.py` re-exports it with
    `from tinygrad.uop import Ops, GroupOp`, and the ENUM lives in `tinygrad/uop/__init__.py`.
    So the oracle's DIRECT imports do not name the file the axis's op names come from, and a
    pin built from them alone would sit on everything EXCEPT the enum.

    THE SECOND HALF IS DERIVED, NOT TYPED: `Ops.__module__` is `"tinygrad.uop"`, and
    `importlib.util.find_spec` turns that into `tinygrad/uop/__init__.py`. A hand list of six
    paths is a list that rots the moment the oracle imports something new, which is the same
    defect as a hand list of gates, one level down.

    AND IT IS NOT THE TRANSITIVE CLOSURE, MEASURED: the closure over every `tinygrad.*`
    import of every `tinygrad.*` module reaches **88** files, `tinygrad/runtime/autogen/amd/*`
    among them, and a pin over those is a tripwire on upstream commits that cannot move this
    axis. Six files, each one of which can change a byte of the axis, is the population.
    """
    mods = set()
    for node in ast.walk(ast.parse(src)):
        if isinstance(node, ast.ImportFrom) and node.module and node.module.split(".")[0] == "tinygrad":
            mods.add(node.module)
            try:
                m = importlib.import_module(node.module)
            except Exception:
                continue
            for alias in node.names:
                obj = getattr(m, alias.name, None)
                where = getattr(obj, "__module__", None)
                if where and where.split(".")[0] == "tinygrad":
                    mods.add(where)
    return mods


def upstream_pin():
    """`[(repo-relative path, sha256)]` over the UPSTREAM FILES THE ORACLE READS.

    WHY A CONTENT PIN AND NOT A REVISION STRING. The axis is GENERATED, so "which upstream is it
    written against" is a question about the TREE it was generated from, and a revision string in
    a generated file is a transcription: it is true at the moment it is written and false at the
    next re-vendor, with nothing reading it. MEASURED, and this is the failure this pin exists
    for: the 2026-10-16 re-vendor of `tinygrad/` moved a BUFFER's size out of the arg and into a
    size CONST SRC, so CPython's own graphs gained a node, and this axis -- generated on 2026-10-15
    against the PRE-vendor tree -- was STALE BY +14 ROWS. Nothing said so: the axis's own bytes
    did not move, the gate that would have said so was REFUSED on a compile error, and a fixture
    against an unstated revision is a fixture against nobody.

    THE TREE'S OWN REVISION IS NOT WRITTEN HERE. `.agents/UPSTREAM-PIN.md` names it and
    `gates/pinned-tree-gate.py` re-derives it BY CONTENT every run, so a revision string in a
    generated file would be a SECOND copy of a pin that already has an instrument.
    """
    out = []
    for m in sorted(upstream_modules()):
        spec = importlib.util.find_spec(m)
        if spec is None or not spec.origin or not spec.origin.endswith(".py"):
            continue
        p = Path(spec.origin).resolve()
        try:
            rel = p.relative_to(ROOT)
        except ValueError:
            continue
        out.append((str(rel), hashlib.sha256(p.read_bytes()).hexdigest()))
    return out


def axis():
    """[(fixture name, sink name, [Wk source text])] read off CPython's own graphs."""
    out = []
    for name, build, fname in FIXTURES:
        root = build()
        sink = UOp(Ops.SINK, src=root if isinstance(root, tuple) else (root,),
                   arg=KernelInfo(fname if fname is not None else "test"))
        uops = list(sink.toposort())
        at = {id(u): i for i, u in enumerate(uops)}
        rows = []
        for u in uops:
            op = "O.Ops" + u.op.name + "{}"
            dt = dt_of(u.dtype)
            # `Wk.addr` IS `src[0]`'s ADDRSPACE for INDEX, SHRINK and LOAD, and the node's
            # OWN for everything else -- `ptx.bend`'s own header says so, and it is the only
            # way those two reads are told apart. MEASURED what happens when it is the
            # node's OWN: a LOAD whose src[0] is a GLOBAL INDEX has addrspace ALU, the port
            # takes ptx.py:200's REG/ALU branch, ALIASES the INDEX's register, and emits no
            # `.reg .f32 %val_f32_<4>;` at all -- four rows the oracle has.
            a = u.addrspace
            if u.op in (Ops.INDEX, Ops.SHRINK, Ops.LOAD) and u.src:
                a = u.src[0].addrspace
            addr = "S." + ADDR[a] + "{}"
            try:
                nmn = u.max_numel()
            except Exception:
                nmn = 1
            nm = ""
            if u.op is Ops.SPECIAL:
                nm = u.arg
            elif u.op is Ops.SINK:
                nm = u.arg.name if isinstance(u.arg, KernelInfo) else "test"
            refs = [at[id(s)] for s in u.src if id(s) in at]
            idx, idx_ok = 0, True
            if u.op in (Ops.INDEX, Ops.SHRINK) and len(u.src) > 1:
                s1 = u.src[1]
                idx_ok = s1.op is Ops.CAST and s1.src[0].op is Ops.CONST
                idx = int(s1.src[0].val) if idx_ok else 0
            rows.append(f'  P.Wk{{{op}, {dt}, {addr}, {nmn}, "{nm}", '
                        f'[{", ".join(str(r) for r in refs)}], {idx}, {"True{}" if idx_ok else "False{}"}}},')
        out.append((name, fname or "test", rows))
    return out


def main():
    print("# ==== GENERATED by gates/ptx_render_census-gen.py -- DO NOT EDIT ====")
    print("# Every Wk below is CPython's own node, read off the graph it built. The IMPORTS")
    print("# are here too because a Bend `import ... as X` is PER FILE: the axis cannot see")
    print("# the census file's `S`, `O` and `P`, and a generated body that names a type its")
    print("# own file has not imported does not compile (MEASURED, and the error is")
    print("# \"expected : a defined name\" pointing at the return type).")
    print("import Base")
    print("import ./../tinybendygrad/LAWS/spec.bend as S")
    print("import ./../tinybendygrad/uop/ops.bend as O")
    print("import ./../tinybendygrad/renderer/ptx.bend as P")
    print("# `Wk` IS `P.Wk`: ptx.bend DEFINES it and the axis imports ptx.bend, so the axis")
    print("# spells it qualified. A generated body that said `Wk` would not compile -- Bend")
    print("# resolves a name in the IMPORTING file, not in the file that defines it.")
    print("# UPSTREAM-PIN -- THE UPSTREAM CONTENT THIS AXIS WAS GENERATED FROM. A fixture")
    print("# against an unstated revision is a fixture against nobody, and a revision STRING")
    print("# rots: it is true when it is written and false at the next re-vendor with nothing")
    print("# reading it. So the pin is a sha256 over the files the ORACLE READS, derived from")
    print("# the oracle's own imports. `gates/ptx_render_census-gate.py` checks every line of")
    print("# it against the tree, and also checks that this file is byte-identical to what")
    print("# THIS generator produces now -- the two together are what makes a stale axis RED")
    print("# instead of a file that quietly describes yesterday's CPython.")
    for rel, digest in upstream_pin():
        print(f"# UPSTREAM-PIN {rel} {digest}")
    print("# ==== BEGIN GENERATED FIXTURES")
    names = [n for n, _, _ in axis()]
    print("# FIXTURES " + " ".join(names))
    # WHICH FIXTURES CPYTHON REFUSES IS DISCOVERED, NOT DECIDED. It is read by CALLING
    # `render` here, so the bend lane's "print no walk rows for these" rule is driven by
    # CPython's own refusals rather than by a hand list that could rot. The gate
    # re-derives it from the oracle lane and asserts the two agree.
    R, KernelInfo2 = G["R"], G["KernelInfo"]
    ref = []
    for name, build, fname in FIXTURES:
        root = build()
        sink = UOp(Ops.SINK, src=root if isinstance(root, tuple) else (root,),
                   arg=KernelInfo2(fname if fname is not None else "test"))
        try:
            R.render(list(sink.toposort()))
        except Exception:
            ref.append(name)
    print("# REFUSES " + " ".join(ref))
    for i, (name, _sname, rows) in enumerate(axis()):
        print(f"def ax{i:02d}() -> List<&2, P.Wk>:\n  [" + "\n  ".join(rows).rstrip(",") + "]")
    print("# ==== END GENERATED FIXTURES")
    return 0


if __name__ == "__main__":
    sys.exit(main())