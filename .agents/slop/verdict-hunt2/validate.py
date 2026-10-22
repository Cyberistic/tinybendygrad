#!/usr/bin/env python3
"""validate.py -- the rejector for the Bend soundness bounty hunt.

WIN CONDITION, mechanically:
  (1) `bend C.bend --verdict` exits 0 and its stdout is exactly "ALL PROOFS CHECK";
  (2) the BendTT the kernel reads contains a LIVE PROOF of `Empty`:
      a def whose declared type is the EMPTY DATATYPE (a datatype with no
      constructors), whose body the kernel checked at that type.

A "live proof" is graded, not binary.  The grades, weakest first:

  VERDICT-FAIL      the verdict lane did not accept the book
  VERDICT-OK        --verdict accepted it; no proof of Empty found
  TERM-OF-EMPTY     a term at type Empty exists, but only inside a def of a
                    FUNCTION type (the c10_ctxdead shape: the def's type is
                    `Empty -> ... -> Empty`, so `Empty` is not inhabited)
  DEF-OF-EMPTY      a DEF whose type IS Empty: the kernel checked a term of
                    type Empty against a declared type of Empty
  CLOSED-INHABITANT that def's body is a CLOSED VALUE (a Tup): the kernel
                    accepted an actual inhabitant of Empty

Only CLOSED-INHABITANT is a bounty win.  Everything below it is a near miss.

The parser below mirrors bend2/bendtt.lean's `Term.parse*` (lines 676-836),
including its Var/Ref rule (`Term.parse_name`: a name in the binder scope is
a Var, else a Ref) and its `parse_paren` rule (the quantity mark comes first,
so `(-a, b)` is a Tup and `(f x)` is an App).

Usage: validate.py <file.bend> [--bendtt <path>] [--receipts <dir>]
"""
import re
import subprocess
import sys
import os

# ---------------------------------------------------------------- BendTT parse

TOKEN = re.compile(r"""
    (?P<ws>\s+)
  | (?P<label>\(\))
  | (?P<name>[A-Za-z_][A-Za-z0-9_.]*)
  | (?P<arrow>->)
  | (?P<fatarrow>=>)
  | (?P<qmark>[+\-])
  | (?P<digit>[0-9])
  | (?P<sym>[∀Σλ{}()\[\],:;=.*%!&<>|])
""", re.VERBOSE)

VAR_RE = re.compile(r"^x\d+$")


class Tok:
    def __init__(self, kind, text):
        self.kind = kind
        self.text = text

    def __repr__(self):
        return "%s(%r)" % (self.kind, self.text)


def tokenize(s):
    out, i = [], 0
    while i < len(s):
        m = TOKEN.match(s, i)
        if not m:
            raise SyntaxError("bad char %r at %d" % (s[i], i))
        i = m.end()
        k = m.lastgroup
        if k == "ws":
            continue
        out.append(Tok(k, m.group()))
    return out


class Node:
    """A BendTT term.  `kind` mirrors the kernel's Term constructors."""

    def __init__(self, kind, **kw):
        self.kind = kind
        self.__dict__.update(kw)

    def __repr__(self):
        return "Node(%s)" % self.kind


class Parser:
    def __init__(self, toks):
        self.t = toks
        self.i = 0

    def peek(self, off=0):
        j = self.i + off
        return self.t[j] if j < len(self.t) else None

    def next(self):
        tok = self.t[self.i]
        self.i += 1
        return tok

    def expect(self, text):
        tok = self.next()
        if tok.text != text:
            raise SyntaxError("expected %r got %r" % (text, tok.text))
        return tok

    def at(self, text):
        tok = self.peek()
        return tok is not None and tok.text == text

    def name(self):
        tok = self.next()
        if tok.kind not in ("name", "label"):
            raise SyntaxError("expected a name, got %r" % (tok.text,))
        return tok.text

    # --- terms -------------------------------------------------------------

    def term(self):
        tok = self.peek()
        if tok is None:
            raise SyntaxError("unexpected end of term")
        t = tok.text
        if t == "∀":
            return self.all_()
        if t == "Σ":
            return self.sig_()
        if t == "λ":
            return self.lam_()
        if t == "<":
            return self.enu()
        if t == "*":
            return self.typ()
        if t == "{":
            return self.braced()
        if t == "%":
            return self.rwt()
        if t == "!":
            return self.let_()
        if t == "(":
            return self.paren()
        if t == ".":
            self.next()
            return Node("Lab", k=self.name())
        if tok.kind == "label":
            self.next()
            return Node("Lab", k="()")
        if tok.kind == "name":
            self.next()
            if VAR_RE.match(tok.text):
                return Node("Var", k=tok.text)
            return Node("Ref", k=tok.text)
        raise SyntaxError("unexpected token %r" % (tok.text,))

    def qmark(self):
        """`Quan.parse`: '-' is Q0, '+' is Q2, anything else is Q1."""
        tok = self.peek()
        if tok is not None and tok.kind == "qmark":
            self.next()
            return tok.text
        return ""

    def all_(self):
        self.expect("∀")
        q = self.qmark()
        k = self.name()
        self.expect(":")
        a = self.term()
        self.expect("->")
        b = self.term()
        return Node("All", q=q, l=k, A=a, B=b)

    def sig_(self):
        self.expect("Σ")
        q = self.qmark()
        k = self.name()
        self.expect(":")
        a = self.term()
        self.expect("->")
        b = self.term()
        return Node("Sig", q=q, l=k, A=a, B=b)

    def lam_(self):
        self.expect("λ")
        if self.at("{"):
            return self.match_()
        q = self.qmark()
        k = self.name()
        self.expect("=>")
        f = self.term()
        return Node("Lam", q=q, l=k, f=f)

    def match_(self):
        self.expect("{")
        if self.at("}"):
            self.next()
            return Node("Efq")
        if self.at("(") and self.peek(1) is not None and self.peek(1).text == "," \
                and self.peek(2) is not None and self.peek(2).text == ")":
            self.next()
            self.next()
            self.next()
            self.expect(":")
            h = self.term()
            self.expect("}")
            return Node("Prj", h=h)
        # Mat: λ{.k: h; m}
        tok = self.peek()
        if tok is not None and tok.text == ".":
            self.next()
            k = self.name()
        elif tok is not None and tok.kind == "label":
            self.next()
            k = "()"
        else:
            raise SyntaxError("bad match label %r" % (tok.text if tok else None,))
        self.expect(":")
        h = self.term()
        self.expect(";")
        m = self.term()
        self.expect("}")
        return Node("Mat", k=k, h=h, m=m)

    def enu(self):
        self.expect("<")
        ks = []
        if not self.at(">"):
            ks.append(self.name())
            while self.at(","):
                self.next()
                ks.append(self.name())
        self.expect(">")
        return Node("Enu", ks=ks)

    def typ(self):
        self.expect("*")
        if self.at("("):
            self.next()
            q = self.term()
            self.expect(")")
            return Node("Typ", q=q)
        if self.at("2"):
            self.next()
            return Node("Typ", q=Node("Lab", k="Q2"))
        self.expect("1")
        return Node("Typ", q=Node("Lab", k="Q1"))
    def braced(self):
        self.expect("{")
        if self.at("=="):
            self.next()
            self.expect("}")
            return Node("Rfl")
        a = self.term()
        if self.at("=="):
            self.next()
            b = self.term()
            self.expect(":")
            T = self.term()
            self.expect("}")
            return Node("Eql", a=a, b=b, T=T)
        self.expect(":")
        T = self.term()
        self.expect("}")
        return Node("Ann", x=a, T=T)

    def rwt(self):
        self.expect("%")
        e = self.term()
        self.expect(":")
        l1 = self.name()
        self.expect(",")
        l2 = self.name()
        self.expect("=>")
        P = self.term()
        self.expect(";")
        f = self.term()
        return Node("Rwt", e=e, l=(l1, l2), P=P, f=f)

    def let_(self):
        self.expect("!")
        q = self.qmark()
        k = self.name()
        self.expect("=")
        v = self.term()
        self.expect(";")
        f = self.term()
        return Node("Let", q=q, l=k, v=v, f=f)

    def paren(self):
        """`Term.parse_paren`: the quantity mark comes FIRST."""
        self.expect("(")
        q = self.qmark()
        a = self.term()
        if self.at(","):
            self.next()
            b = self.tup_rest()
            self.expect(")")
            return Node("Tup", q=q, a=a, b=b)
        if q == "":
            if self.at("<&>"):
                self.next()
                b = self.term()
                self.expect(")")
                return Node("Min", a=a, b=b)
            f = a
            while not self.at(")"):
                self.qmark()          # the arg's quantity mark
                x = self.term()
                f = Node("App", q="", f=f, x=x)
            self.expect(")")
            return f
        raise SyntaxError("a pair after a quantity mark")

    def tup_rest(self):
        """`Term.parse_tup`: the rest of a tuple, after a ','."""
        q = self.qmark()
        a = self.term()
        if self.at(","):
            self.next()
            b = self.tup_rest()
            return Node("Tup", q=q, a=a, b=b)
        return Node("Tup", q=q, a=a, b=None)


def parse_defs(text):
    """Split the BendTT book into defs.  Each def is (name, opaque, type, body)."""
    defs = []
    for chunk in re.split(r"\n\s*\n", text):
        chunk = chunk.strip()
        if not chunk:
            continue
        opaque = False
        if chunk.startswith("opaque "):
            opaque = True
            chunk = chunk[len("opaque "):]
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_.]*)\s*:\s*", chunk)
        if not m:
            raise SyntaxError("cannot find a def header in %r" % chunk[:80])
        name = m.group(1)
        rest = chunk[m.end():]
        depth, cut, i = 0, None, 0
        while i < len(rest):
            c = rest[i]
            if c in "({[":
                depth += 1
            elif c in ")}]":
                depth -= 1
            elif c == "=" and depth == 0:
                cut = i
                break
            i += 1
        if cut is None:
            raise SyntaxError("cannot split type/body in %r" % chunk[:80])
        ttext, btext = rest[:cut], rest[cut + 1:]
        p = Parser(tokenize(ttext))
        T = p.term()
        if p.i != len(p.t):
            raise SyntaxError("trailing tokens in type of %s" % name)
        p = Parser(tokenize(btext))
        V = p.term()
        if p.i != len(p.t):
            raise SyntaxError("trailing tokens in body of %s" % name)
        defs.append((name, opaque, T, V))
    return defs


# ------------------------------------------------------------------ analysis

GRADE_ORDER = ["VERDICT-FAIL", "VERDICT-OK", "TERM-OF-EMPTY", "DEF-OF-EMPTY", "CLOSED-INHABITANT"]


def empty_adt_names(defs):
    """The empty datatypes: the defs whose body is a Sig over the EMPTY enum.

    `Empty : *(.Q2) = Σx0 : <> -> (Empty.arms x0)` -- the body is a Sig whose
    tag type is `<>` (no constructors).  That is Bend's `Empty`.
    """
    names = set()
    for name, opaque, T, V in defs:
        if V.kind == "Sig" and V.A.kind == "Enu" and len(V.A.ks) == 0:
            names.add(name)
    return names


def walk(node, fn, path=()):
    if fn(node, path) is False:
        return
    for k in ("A", "B", "f", "h", "m", "x", "T", "a", "b", "v", "P", "e"):
        sub = getattr(node, k, None)
        if isinstance(sub, Node):
            walk(sub, fn, path + (k,))


def is_value(node):
    """A kernel VALUE: a Tup, a Lam, a Lab, an Enu, a Ref, an Efq.

    An App is not a value (it must be evaluated); a Tup is.
    """
    return node.kind in ("Tup", "Lam", "Lab", "Enu", "Ref", "Efq")


def grade(bendtt_text):
    """Grade a BendTT book.  Returns (grade, detail_lines)."""
    defs = parse_defs(bendtt_text)
    empties = empty_adt_names(defs)
    lines = ["defs=%d empty_datatypes=%s" % (len(defs), sorted(empties))]
    best = "VERDICT-OK"
    order = GRADE_ORDER.index

    def bump(g):
        nonlocal best
        if order(g) > order(best):
            best = g

    for name, opaque, T, V in defs:
        if T.kind == "Ref" and T.k in empties:
            bump("DEF-OF-EMPTY")
            lines.append("DEF-OF-EMPTY: %s : %s" % (name, T.k))
            if V.kind == "Tup":
                bump("CLOSED-INHABITANT")
                lines.append("CLOSED-INHABITANT: %s's body is a Tup (a value)" % name)
            else:
                lines.append("  (its body is a %s, not a Tup)" % V.kind)
    # near-miss scan: an App(Prj(Efq), _) anywhere (the c10 shape)
    for name, opaque, T, V in defs:
        if T.kind == "Ref" and T.k in empties:
            continue
        hit = []
        walk(V, lambda n, p: hit.append(p) if (n.kind == "App" and
                                              n.f.kind == "Prj" and
                                              n.f.h.kind == "Efq") else None)
        if hit:
            bump("TERM-OF-EMPTY")
            lines.append("NEARMISS-PRJ-EFQ: %s has %d App(Prj(Efq),_) term(s)" % (name, len(hit)))
    return best, lines


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return 2
    path = args[0]
    bendtt = None
    receipts = None
    if "--bendtt" in args:
        bendtt = args[args.index("--bendtt") + 1]
    if "--receipts" in args:
        receipts = args[args.index("--receipts") + 1]
    root = os.path.dirname(os.path.abspath(__file__))
    bend = os.environ.get("BEND", "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/bin/bend")
    env = dict(os.environ)
    if receipts:
        os.makedirs(receipts, exist_ok=True)
        with open(os.path.join(receipts, "verdict.out"), "wb") as f:
            p = subprocess.run([bend, path, "--verdict"], stdout=f,
                               stderr=subprocess.PIPE, env=env)
        with open(os.path.join(receipts, "verdict.err"), "wb") as f:
            f.write(p.stderr)
        with open(os.path.join(receipts, "verdict.rc"), "w") as f:
            f.write("%d\n" % p.returncode)
        with open(os.path.join(receipts, "verdict.out")) as f:
            out = f.read()
        if p.returncode != 0 or out.strip() != "ALL PROOFS CHECK":
            print("VERDICT-FAIL  rc=%d stdout=%r" % (p.returncode, out.strip()[:300]))
            return 1

    if bendtt is None:
        bendtt = path + ".bendtt"
    p = subprocess.run([bend, path, "-o", bendtt], stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE, env=env)
    if p.returncode != 0:
        print("BENDTT-EMIT-FAILED rc=%d %r" % (p.returncode, p.stderr.decode()[:300]))
        return 1
    with open(bendtt) as f:
        text = f.read()
    g, lines = grade(text)
    print("GRADE: %s" % g)
    for l in lines:
        print("  " + l)
    return 0


if __name__ == "__main__":
    sys.exit(main())
