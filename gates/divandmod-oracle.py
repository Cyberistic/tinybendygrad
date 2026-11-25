#!/usr/bin/env python3
"""divandmod-oracle.py -- CPython IS THE ORACLE, AND IT IS IN THE TREE.

    .venv/bin/python gates/divandmod-oracle.py                    # upstream's answers
    .venv/bin/python gates/divandmod-oracle.py --compare FILE     # diff against the port
    .venv/bin/python gates/divandmod-oracle.py --cases FILE       # another case file

ONE FILE, TWO READERS.  `gates/divandmod-cases.rows` holds the GRAPHS, and
this file READS IT and builds the same graphs in CPython -- so the port (whose
driver reads the same file) and the oracle cannot be measuring two different
graphs.  A hand-written pair of fixtures has that defect by construction.

THE ANSWER IS THE CANONICAL FORM OF THE TREE, AND IT IS THE PORT's OWN FORM:
AN OP NAME, THEN THE SRCS IN PARENTHESES, AND A CONST AS ITS VALUE AND A PARAM
AS ITS NAME.  MEASURED 2026-11-24: the port's `P.dm_sh2` PRINTS EXACTLY THIS,
AND UPSTREAM's `render` PRINTS A SIMILAR BUT NOT IDENTICAL FORM, SO THE
ORACLE PRINTS THE PORT's FORM AND THE TWO DIFF AS STRINGS.

THE THREE VERDICTS, AND THEY ARE DISTINCT AND NOT SYNONYMS:

    ANSWERED <form>  upstream's arm rewrote the graph, and the form is what it
                     rewrote TO.
    nofold           upstream's arm did NOT rewrite the graph.
    RAISED <Name>    upstream RAISED, and the name is the exception's class.

EXIT: 0 the port agrees with upstream on every case · 1 they disagree · 3 REFUSED
(a case file or a graph the reader cannot build).
"""

import argparse
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

CASES = os.path.join(ROOT, "gates", "divandmod-cases.rows")

from tinygrad.uop.ops import UOp, Ops, ParamArg
from tinygrad import dtypes
from tinygrad.uop.divandmod import fold_divmod_general

# THE PARAMs ARE SIZED, AND THE SIZE IS PART OF THE VOCABULARY AND NOT A
# CONSTANT OF THIS FILE: A PARAM WITH AN EMPTY `as_shape` MAKES `_shape` RAISE
# `IndexError` (ops.py:351) AND UPSTREAM's ARM THEN RAISES INSTEAD OF
# ANSWERING.  MEASURED 2026-11-24.
PARAM_SIZE = 4


def read_cases(path):
    """`(name, op, k, c, n, d)` per case, and COMMENTS AND BLANKS ARE SKIPPED."""
    out = []
    with open(path) as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if "|" not in line:
                continue
            parts = [p.strip() for p in line.split("|")]
            if len(parts) != 6:
                print("REFUSED: %s: a case has %d fields and the shape has six"
                      % (parts[0], len(parts)))
                return None
            out.append((parts[0], parts[1], *[int(x) for x in parts[2:]]))
    return out


def mk_param(name):
    sz = UOp(Ops.CONST, (), PARAM_SIZE)
    return UOp(Ops.PARAM, (sz,), ParamArg(0, dtypes.weakint, name=name))


def const(v):
    return UOp(Ops.CONST, (), v)


def form(u):
    """THE PORT's CANONICAL FORM.

    AND IT IS THE PORT's OWN LABELS: `Ops.NAME` FOR AN OP, `P<name>` FOR A
    PARAM AND `CONST(v)` FOR A CONST -- `P.dm_lab`'s THREE FORMS.  MEASURED
    2026-11-24: THE DRIVER's FORM AND THIS ONE ARE THE SAME, AND A FORM THAT
    DIFFERS IN ITS SPELLING IS A FORM THAT COMPARES NOTHING.

    AND A PARAM AND A CONST ARE LEAVES: A PARAM's ONE SRC IS ITS **SIZE
    CONST** AND NOT A VALUE (`ops.py:62`), SO RENDERING IT WOULD PUT THE SIZE
    IN THE FORM.
    """
    if u.op is Ops.CONST:
        return "Ops.CONST(%d)" % u.arg
    if u.op is Ops.PARAM:
        return "P" + (u.arg.name or "")
    return "Ops.%s(%s)" % (u.op.name, ",".join(form(s) for s in u.src))


def build(op, k, c, n, d):
    """THE FIXED SHAPE, AND IT IS THE ARM's OWN SHAPE."""
    root_op = Ops.MOD if op == "MOD" else Ops.DIV
    if op == "MODCONST":
        # `(c7%c4 + c5)%c2` -- EVERY LEAF IS A CONST.
        inner = const(k).alu(Ops.MOD, const(c))
        terms = [inner] + [const(5 + i) for i in range(n)]
        num = terms[0]
        for t in terms[1:]:
            num = num.alu(Ops.ADD, t)
        return num.alu(Ops.MOD, const(d))
    if op == "DIVCONST":
        return const(k).alu(Ops.DIV, const(c))
    if op in ("FRDIV", "FRMOD"):
        # AND THE `factor_remainder` SHAPE, AND IT IS `(d*a*k + b + ...) op
        # (c*d)` WITH **`d` A VARIABLE** -- AND THE VARIABLE IS THE WHOLE POINT,
        # BECAUSE A CONST DIVISOR PUTS THE ARM BEHIND `divide_by_gcd`
        # (divandmod.py:72-76), WHOSE `gcd` IS AN `EXPAND` AND NOT A `CONST`,
        # AND UPSTREAM THEN **RAISES** `AssertionError`.  MEASURED 2026-11-25:
        # EVERY CONST-DIVISOR SHAPE RAISED.
        #
        # AND THE VARIABLES ARE UPSTREAM's `UOp.variable` (ops.py:973-975) -- A
        # PARAM WITH **NO SRCS**, SO ITS `_shape` IS `()` AND
        # `x.const_like(0)` IS A **BARE `CONST 0`** AND NOT AN `EXPAND`.
        #
        # AND THE SHAPE IS UPSTREAM's OWN TEST's SHAPE
        # (test/null/test_uop_symbolic.py:584-590) AND NOT A NEW ONE.
        root_op = Ops.MOD if op == "FRMOD" else Ops.DIV
        a = UOp.variable("a", 0, 10)
        d = UOp.variable("d", 1, 10)
        b = UOp.variable("b", 0, 10)
        ad = a.alu(Ops.MUL, d)
        if k != 1:
            ad = ad.alu(Ops.MUL, const(k))
        num = ad.alu(Ops.ADD, b)
        for i in range(n):
            num = num.alu(Ops.ADD, const(k + i))
        den = d.alu(Ops.MUL, const(c)) if c != 1 else d
        return num.alu(root_op, den)
    if op in ("GCDMOD", "GCDDIV"):
        # AND THE `divide_by_gcd` SHAPE, AND IT IS `(c0 + 2x) % (2x)` -- A
        # NUMERATOR WHOSE CONSTANT TERM MAKES IT **NOT EXACTLY DIVISIBLE**, AND A
        # DIVISOR THAT IS ITSELF A MUL SO THE GCD IS **2** AND NOT 1.
        root_op = Ops.MOD if op == "GCDMOD" else Ops.DIV
        mx = mk_param("x").alu(Ops.MUL, const(k))
        num = const(n).alu(Ops.ADD, mx)
        return num.alu(root_op, mx)
    # `(x%k + y + z)%c`
    inner = mk_param("x").alu(Ops.MOD, const(k))
    terms = [inner] + [mk_param(chr(ord("y") + i)) for i in range(n)]
    num = terms[0]
    for t in terms[1:]:
        num = num.alu(Ops.ADD, t)
    return num.alu(root_op, const(d))


def answer(root):
    """THE VERDICT FOR ONE GRAPH."""
    try:
        got = fold_divmod_general(root)
    except ZeroDivisionError:
        return "RAISED ZeroDivisionError"
    except Exception as e:  # upstream's own crash on a graph it cannot answer
        return "RAISED %s" % type(e).__name__
    if got is None:
        return "nofold"
    return "ANSWERED %s" % form(got)


def upstream(cases):
    out = {}
    for name, op, k, c, n, d in cases:
        try:
            root = build(op, k, c, n, d)
        except Exception as e:
            print("REFUSED: %s: cannot build: %s" % (name, e))
            return None
        out[name] = answer(root)
    return out


def port_answers(path):
    """THE PORT's DRIVER's OUTPUT, AND IT IS READ AS `name=answer` PAIRS."""
    out = {}
    with open(path) as f:
        for raw in f:
            line = raw.strip()
            if not line or "=" not in line:
                continue
            name, val = line.split("=", 1)
            out[name.strip()] = val.strip()
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cases", default=CASES)
    ap.add_argument("--compare", help="the port's driver output to diff against")
    args = ap.parse_args()
    cases = read_cases(args.cases)
    if cases is None:
        return 3
    up = upstream(cases)
    if up is None:
        return 3
    if args.compare is None:
        for name, _, _, _, _, _ in cases:
            print("%s=%s" % (name, up[name]))
        return 0
    port = port_answers(args.compare)
    bad = []
    if len(port) != len(cases):
        bad.append("the port's driver printed %d rows and the case file has %d cases"
                   % (len(port), len(cases)))
    for (name, _, _, _, _, _) in cases:
        p = port.get(name)
        u = up[name]
        if p != u:
            bad.append("%s: port=%s upstream=%s" % (name, p, u))
    for b in bad:
        print("DIVERGES " + b)
    print("divandmod-oracle: %d cases, %d agree, %d diverge"
          % (len(cases), len(cases) - len(bad), len(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
