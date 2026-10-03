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
    the emitter rows carry the whole emitted FILE, and a raw newline inside a `"..."`
    literal ends the literal.  bend then reports "expected : a closing \" observed :
    end of input" against the LAST row, which points at the wrong line entirely.

    `glrow` feeds this the ORACLE'S ALREADY-ESCAPED text (see ga-oracle.py's `R`),
    so the doubling of `\\` above is what turns the oracle's two-character `\\n` into
    a bend literal holding those same two characters -- and the port, which never
    scans `want`, prints exactly what the oracle escaped.  One transform, both sides.
    """
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
# THE GATE ROWS.  `py=` literals come from the oracle's ROWS, read off the
# IMPORTED MODULE and not off `ga-oracle.txt`.
#
# This used to parse the text file and reassemble each emitter file out of its
# `tag | line` rows.  That is GONE and it is not a style choice.  The text file
# now holds ESCAPED one-line rows -- which is the whole point, a line-keyed parser
# cannot see a row whose value contains a newline -- and they cannot be unescaped
# back without destroying `write_pcode`'s repr'd `\n`, because after `R` a real
# newline and a literal `\n` are the same two characters.  Reading `O.ROWS`
# sidesteps the round trip and removes the bug that lived in it: every BLANK line
# of an emitted file was a row named `tag | `, so the name-keyed dict kept one of
# four separators and the reassembled file lost three -- which is how `common.py`
# came out with no blank line before `class Fmt(Enum):`, a WRONG expectation
# spliced from a correct oracle that then disagreed with the RIGHT port.
# ---------------------------------------------------------------------------
ORACLE = {}
ORACLE_KEYS = []
for nm, val in O.ROWS:
    if nm not in ORACLE:
        ORACLE[nm] = val
        ORACLE_KEYS.append(nm)
print(f"# ORACLE ROW COUNT = {len(O.ROWS)}", file=sys.stderr)


def py(nm):
    if nm not in ORACLE:
        raise SystemExit(f"NO ORACLE ROW NAMED {nm!r} -- refusing to invent one")
    return ORACLE[nm]


def srow(nm, call):
    """One `nm = [port]   py=[cpython]` row."""
    w("  g(%s, %s, %s)" % (bq(nm), call, bq(py(nm))))


def glrow(nm, call, tag):
    """One emitter FILE, as `nm | 0 .. nm | N-1` plus `nm lines`.

    The gate's row parser splits lane output on newlines, so a row whose value
    contains one is invisible: one whole-file row became 335 fragments whose NAMES
    are the first token before an `=` inside the generated Python.  The obvious fix
    -- `cstyle.bend:1760`'s `esc_row`, a newline turned into `\\` `n` -- DOES NOT
    RUN HERE, and neither does the row it would fix: a `String` is an `SCon` spine
    (references/bend/bend2/base.bend:1848) and the interpreter has no tail call, so
    a 16,815-character value is 16,815 nested frames.  Measured: 4,000 characters
    works, 8,000 overflows, and the real whole-file row succeeded 5 times in 12 --
    the SAME as the unescaped original, so that flake predates this change.

    So the answer is one row per emitted LINE, which builds no string longer than a
    line.  The INDEX is the key because the emitted text repeats (four blank lines,
    `  saddr = SSrcField(31, 24, default=NULL)` in four classes), and the count row
    the index from hiding a dropped LAST line: `wc` is CPython's count, the port's
    is its own list length, so a disagreement between them is a real row.

    `want` comes from `O.EMITTED[tag]` -- the oracle's RAW emitted text -- and NOT
    from a reassembly of the rows above, because every blank line of an emitted file
    is the row `tag | ` and a name-keyed reassembly loses three of the four blank
    separators.  That is not hypothetical: it produced a `py=` literal for `common`
    with no blank line before `class Fmt(Enum):`, a wrong expectation spliced from a
    correct oracle that disagreed with the RIGHT port."""
    w("  gl(%s, %s, %s, %s)" % (bq(nm), call, bq(O.EMITTED[tag]), bq(py(tag + " lines"))))


def gate():
    w()
    w("def g(nm: String, got: String, want: String) -> IO(Unit):")
    w("  IO.print(String.concat([nm, \" = [\", got, \"]   py=[\", want, \"]\"]))")
    w()
    w("# THE EMITTER ROWS ARE ONE ROW PER EMITTED LINE, `nm | <index>`, PLUS `nm lines`.")
    w("#")
    w("# A count row alone would be identical for a dropped member, a dropped alias, a")
    w("# swapped `default=NULL` and a reordered field; the 634 line rows are what see")
    w("# those, and they are the renderer convention 2 applied to a GENERATOR: the")
    w("# answer is the FILE, one line at a time.")
    w("#")
    w("# AND IT MUST BE PER LINE, MEASURED TWICE OVER.")
    w("#")
    w("# The row parser splits lane output on newlines, so one whole-file row became 335")
    w("# fragments whose NAMES are the first token before an `=` inside the generated")
    w("# Python (`FLAT_LOAD_DWORD`, `encoding`, `saddr`, ...): 233 row names for 91 rows,")
    w("# 84 shared with the oracle, the other 149 naming text the oracle names")
    w("# `tag | line`.  The fix `cstyle.bend:1760` suggests -- `esc_row`, a newline turned")
    w("# into `\\` `n` -- FAILS TWICE OVER.  `String.split` is one frame per CHARACTER")
    w("# (base.bend:2009) and the file is 16,815 characters; and even given the lines as")
    w("# a list, `String.join` is O(total length) in stack depth because base.bend:1980")
    w("# appends onto a prefix that grows (base.bend:1806).  Probe: 177 lines of 95")
    w("# characters, 6 of 6 through `String.concat`, and the real file 10 of 20 through")
    w("# either join.  THE ORIGINAL, ONE WHOLE-FILE ROW AND NO ESCAPE AT ALL, WAS 5 OF")
    w("# 12 -- so the flake predates this change and no lane on this port was reliably")
    w("# runnable.")
    w("#")
    w("# A per-line row builds no string longer than one emitted line, so it cannot reach")
    w("# that ceiling.  `want` stays ONE literal and is walked in lockstep with `got`:")
    w("# `String.take` and `String.drop` (base.bend:1932/1941) recurse over the PREFIX")
    w("# they consume, which is one line, never the file.  And no escaping is needed at")
    w("# all -- which also removes cstyle's `\\` `n` ambiguity outright, a real concern")
    w("# here because `write_pcode` emits `{code!r}` (generate.py:497) and CPython's own")
    w("# output holds a literal `\\` `n` inside a pcode body.")
    w("#")
    w("# `lines` is not a coverage claim, it is the ONE hole the index opens: an index")
    w("# cannot see a dropped LAST line.  `wc` is CPython's count and the port's is its")
    w("# own list length, so they are two numbers from two places.")
    w("def gl.go(+nm: String, got: List<&2, String>, +w: String, wc: String, +i: Nat) -> IO(Unit):")
    w("  match got:")
    w("    case Nil{}:")
    w("      g(String.concat([nm, \" lines\"]), U32.show(U32.from_nat(i)), wc)")
    w("    case +h <> t:")
    w("      do IO<Unit>:")
    w("      g(String.concat([nm, \" | \", U32.show(U32.from_nat(i))]), h, String.take(w, String.length(h)))")
    w("      gl.go(nm, t, String.drop(w, Nat.add(String.length(h), 1n)), wc, Nat.add(i, 1n))")
    w()
    w("def gl(nm: String, got: List<&2, String>, want: String, wc: String) -> IO(Unit):")
    w("  do IO<Unit>:")
    w("  gl.go(nm, got, want, wc, 0n)")
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
    # `operands cdna` is here because the oracle EMITS it and it was the one
    # emitter file the port never showed: `write_operands` takes `arch` and uses
    # it in exactly one line, the import (generate.py:471), so the two arch files
    # differ in one token and a gate that only diffed rdna3 could not see an
    # `arch` argument dropped or hard-coded.  `write_enum` takes NO arch
    # (generate.py:273), so there is no `enum cdna` -- the oracle does not emit one
    # either, and a second row for the same bytes is a row that cannot fail.
    for tag, call in (("enum rdna3", "write_enum(fx_eos())"),
                      ("operands rdna3", "write_operands(fx_tys(), fx_eos(), %s)" % bq("rdna3")),
                      ("operands cdna", "write_operands(fx_tys(), fx_eos(), %s)" % bq("cdna")),
                      ("ins rdna3", ins % bq("rdna3")),
                      ("ins cdna", ins % bq("cdna")),
                      ("pcode rdna3", pc % bq("rdna3")),
                      ("pcode cdna", pc % bq("cdna")),
                      ("common", "write_common(fx_fbs(), fx_ots())")):
        glrow(tag, call, tag)
    print("\n".join(OUT))