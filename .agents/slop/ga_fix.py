#!/usr/bin/env python3
"""Emit the FIXTURE and the GATE for tinybendygrad/renderer/amd/generate.bend.

Both come from ONE source of truth: the fixture builders in `ga-oracle.py`,
which the ORACLE also calls.  Nothing here is transcribed by hand -- the same
dict that `generate.write_ins` was called with is the dict that becomes bend
literals, and every `py=` literal is a row of `ga-oracle.txt`.

The fixture is NOT uniform.  Every encoder has a distinct op, the bit widths
span 6/7/8/9/13/18 bits so each `field_def` arm has at least one hit, and the
`types` table gives VOP1 op 0 both an ordinary `vdst` and no `literal`, so the
suffix-only exclusion is visible.

Run:  .venv/bin/python .agents/slop/ga_fix.py > /tmp/gagate.txt
then paste/append /tmp/gagate.txt to the .bend file.
"""
import json
import pathlib
import sys

_HERE = pathlib.Path("/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/.agents/slop")
sys.path.insert(0, str(_HERE))
import contextlib, importlib.util, io  # noqa: E402
# `ga-oracle.py` has a HYPHEN, so it is not importable by name: load it by path.
_spec = importlib.util.spec_from_file_location("ga_oracle", str(_HERE / "ga-oracle.py"))
O = importlib.util.module_from_spec(_spec)
with contextlib.redirect_stdout(io.StringIO()):   # it PRINTS its 876 rows at import
    _spec.loader.exec_module(O)

OUT = []


def w(s=""):
    OUT.append(s)


def bq(s):
    """A bend String literal.  `\"` and `\\` need escaping -- AND SO DOES A NEWLINE:
    the emitter rows carry the whole emitted FILE joined with real newlines, and a
    raw newline inside a `"..."` literal ends the literal.  bend then reports
    "expected : a closing \" observed : end of input" against the LAST row, which
    points at the wrong line entirely."""
    out = s.replace("\\", "\\\\").replace('"', '\\"')
    return '"' + out.replace("\n", "\\n") + '"'


# ---------------------------------------------------------------------------
# FIXTURES
# ---------------------------------------------------------------------------
def fx_encodings():
    w("# ---- THE FIXTURE.  Built by `.agents/slop/ga_fix.py` from the SAME dicts")
    w("# `ga-oracle.py` hands to `generate.write_ins`, so the port's fixture and")
    w("# CPython's input cannot drift apart.")
    w("def fx_encs() -> List<&2, EC>:")
    es = O.fixture_encodings()
    parts = []
    for nm in sorted(es):
        flds, bits = es[nm]
        fl = ["Fld.of(%s, %d, %d)" % (bq(f), h, l) for f, h, l in flds]
        parts.append("EC.of(%s, [%s], %s, %s)" % (
            bq(nm), ", ".join(fl), bq(bits), "True{}"))
    w("  [" + ", ".join(parts) + "]")
    w()


def fx_enums():
    w("def fx_eos() -> List<&2, EO>:")
    ns = O.fixture_enums()
    parts = []
    for fmt in sorted(ns):
        ops = ["OP.of(%d, %s)" % (o, bq(ns[fmt][o])) for o in sorted(ns[fmt])]
        parts.append("EO.of(%s, [%s])" % (bq(fmt), ", ".join(ops)))
    w("  [" + ", ".join(parts) + "]")
    w()


def fx_types():
    w("def fx_tys() -> List<&2, TY>:")
    ts = O.fixture_types()
    parts = []
    for (nm, base) in sorted(ts):
        fs = []
        for f in sorted(ts[(nm, base)]):
            df, size, ot = ts[(nm, base)][f]
            fs.append("OI{%s, %s, %d, %s}" % (bq(f), bq(df if df else ""), size,
                                               bq(ot if ot else "")))
        parts.append("TY{%s, %s, [%s]}" % (bq(nm), bq(base), ", ".join(fs)))
    w("  [" + ", ".join(parts) + "]")
    w()


def fx_fmts():
    w("def fx_fbs() -> List<&2, FB>:")
    parts = ["FB{%s, %d}" % (bq(k), O.all_fmts[k]) for k in sorted(O.all_fmts)]
    w("  [" + ", ".join(parts) + "]")
    w()


def fx_sfx():
    """`suffix_only_ops` -- {"_LIT": {"VOP1": {0}}, "_MFMA": {"VOP3P": {44}}}."""
    w("# `suffix_only_ops`, the {suffix: {fmt: {opcode}}} table.  A FOURTH nested")
    w("# shape, because a dict of dicts of sets has no Bend spelling and the class")
    w("# folds need it three different ways (restrict the base class, widen the")
    w("# variant, choose the helper's class).")
    w("def fx_ssx() -> List<&2, SS>:")
    sfx = O.fixture_suffix_only_ops()
    parts = []
    for k in sfx:
        gs = ", ".join("SG{%s, [%s]}" % (bq(f), ", ".join(str(o) for o in sorted(v)))
                       for f, v in sfx[k].items())
        parts.append("SS{%s, [%s]}" % (bq(k), gs))
    w("  [" + ", ".join(parts) + "]")
    w()

def fx_ots():
    w("def fx_ots() -> List<&2, String>:")
    w("  [" + ", ".join(bq(o) for o in sorted(O.all_op_types)) + "]")
    w()


# ---------------------------------------------------------------------------
# THE GATE ROWS.  `py=` literals come from `ga-oracle.txt`, keyed by row name.
# ---------------------------------------------------------------------------
ORACLE = {}
ORACLE_KEYS = []
for ln in (_HERE / "ga-oracle.txt").read_text().split("\n"):
    if " = [" in ln and ln.endswith("]"):
        nm, val = ln.split(" = [", 1)
        if nm not in ORACLE:
            ORACLE[nm] = val[:-1]
            ORACLE_KEYS.append(nm)
    elif ln.startswith("ORACLE ROW COUNT = "):
        print(f"# ORACLE ROW COUNT = {ln.split('= ')[1]}", file=sys.stderr)


def py(nm):
    if nm not in ORACLE:
        raise SystemExit(f"NO ORACLE ROW NAMED {nm!r} -- refusing to invent one")
    return ORACLE[nm]


def srow(nm, call):
    """One `nm = [port]   py=[cpython]` row."""
    w("  g(%s, %s, %s)" % (bq(nm), call, bq(py(nm))))


def tag_join(tag):
    """The oracle's `tag | line` rows, joined -- the whole emitted FILE as ONE
    string, so a changed character moves the row and a count row cannot hide it.

    READ THE FILE AGAIN rather than reading `ORACLE`: every BLANK line of an
    emitted file is a row named `tag | `, so the name-keyed dict above keeps one
    of the four and the joined file loses three separators.  That is how
    `common.py` came out with no blank line before `class Fmt(Enum):` -- a wrong
    expectation spliced from a correct oracle, and it disagreed with the PORT,
    which was right."""
    out = []
    for ln in (_HERE / "ga-oracle.txt").read_text().split("\n"):
        if " = [" in ln and ln.endswith("]"):
            nm, val = ln.split(" = [", 1)
            if nm.startswith(tag + " |"):
                out.append(val[:-1])
    return "\n".join(out)


def glrow(nm, call, tag):
    w("  gl(%s, %s, %s)" % (bq(nm), call, bq(tag_join(tag))))


def gate():
    w()
    w("def g(nm: String, got: String, want: String) -> IO(Unit):")
    w("  IO.print(String.concat([nm, \" = [\", got, \"]   py=[\", want, \"]\"]))")
    w()
    w("# THE EMITTER ROWS ARE ONE ROW PER EMITTED FILE, the file JOINED by newline.")
    w("# A count row would be identical for a dropped member, a dropped alias, a")
    w("# swapped `default=NULL` and a reordered field; a string diff is not.  This is")
    w("# the renderer convention 2 applied to a GENERATOR: the answer is the file.")
    w("def gl(nm: String, got: List<&2, String>, want: String) -> IO(Unit):")
    w("  g(nm, String.join(got, \"\\n\"), want)")
    w()
    w("def main() -> IO(Unit):")
    w("  do IO<Unit>:")
    for nm in ("strip_enc", "norm_field", "map_flat"):
        for k in ORACLE_KEYS:
            if k.startswith(nm + " "):
                arg = k[len(nm) + 1:]
                # NOT a dict of three f-strings: python evaluates EVERY value of a
                # dict literal, so `arg.split("/")[1]` blew up on a `strip_enc` row.
                # A third hung run, and the cause was eager evaluation.
                if nm == "map_flat":
                    call = f'map_flat({bq(arg.split("/")[0])}, {bq(arg.split("/")[1])})'
                else:
                    call = f'{nm}({bq(arg)})'
                srow(k, call)
    w("  IO.print(\"\")")


def fx_pcode():
    """`pcode` -- `{(name, opcode): pseudocode}`.  `extract_pcode` is WALL 5, so
    the FIXTURE is the dict the oracle hands `write_pcode`, verbatim: the values
    are `json.dumps` of the dict `G.extract_pcode` returned, re-read here so the
    port's input and CPython's input cannot drift."""
    w("# `pcode`, `{(name, opcode): pseudocode}`.  `extract_pcode` is WALL 5 (bend")
    w("# 2.0.34 has F32 and no F64), so the FIXTURE is the dict the oracle read")
    w("# back out of `G.extract_pcode`, decoded from the same `json.dumps` text.")
    w("def fx_ps() -> List<&2, PK>:")
    ps = json.loads(O.PCODE_OUT)
    parts = ["PK{%s, %d, %s}" % (bq(k.split("|")[0]), int(k.split("|")[1]), bq(v))
             for k, v in sorted(ps.items())]
    w("  [" + ", ".join(parts) + "]")
    w()


def main_section():
    w()
    w("# ===========================================================================")
    w("# THE GATE.")
    w("#")
    w("# EVERY `py=` LITERAL BELOW IS A ROW OF `.agents/slop/ga-oracle.txt`, WHICH")
    w("# CALLS generate.py's OWN FUNCTIONS -- `_strip_enc`, `_norm_field`,")
    w("# `_map_flat`, and the four emitters, whose emitted FILES are read back.  No")
    w("# `py=` here was typed by a human; `.agents/slop/ga_fix.py` splices them in")
    w("# from the oracle, and it REFUSES to emit a row whose name is not in the")
    w("# oracle file.  That is the rule five files in this project broke by hand")
    w("# (`cstyle` 17/215, `ops_nv` 33/219, `rdma` one hex digit, `amdev` 7/80,")
    w("# `ops_qcom` one table entry).")
    w("# ===========================================================================")
    gate()


if __name__ == "__main__":
    fx_encodings()
    fx_enums()
    fx_types()
    fx_fmts()
    fx_ots()
    fx_sfx()
    fx_pcode()
    main_section()
    ins = "write_ins(fx_encs(), fx_eos(), fx_ssx(), fx_tys(), %s)"
    pc = "write_pcode(fx_ps(), fx_eos(), %s)"
    for tag, call in (("enum rdna3", "write_enum(fx_eos())"),
                      ("operands rdna3", "write_operands(fx_tys(), fx_eos(), %s)" % bq("rdna3")),
                      ("ins rdna3", ins % bq("rdna3")),
                      ("ins cdna", ins % bq("cdna")),
                      ("pcode rdna3", pc % bq("rdna3")),
                      ("pcode cdna", pc % bq("cdna")),
                      ("common", "write_common(fx_fbs(), fx_ots())")):
        glrow(tag, call, tag)
    print("\n".join(OUT))