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
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

HERE = Path(__file__).resolve().parent
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