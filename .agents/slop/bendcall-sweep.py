#!/usr/bin/env python3
"""bendcall-sweep.py -- resolve every base-library call site in the port and check
its argument order against the definition in references/bend/bend2/base.bend.

Why a checker and not a grep (measured, today):  `IxMap.es(rm)` in
schedule/indexing.bend matches a bare `Map\.\w+\(` grep while being a LOCAL def,
and `Map.get` is only a Map call because `Map` is a type in base.bend.  A grep
cannot tell those apart, so this resolves namespaces from the import lines.

Three checks, in descending severity:
  ARITY    call arity != def arity                      (compiler usually catches)
  ZEROSWAP a value-zero literal sits in a slot the def annotates as a String KEY
  SAMETYPE two params share an annotation and the two args differ in zero-literalness

Usage:  bendcall-sweep.py [--all] [--fns Map.get,List.append]
"""
from __future__ import annotations  # noqa

import os
import re
import sys
from dataclasses import dataclass, field

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BASE = os.path.join(ROOT, "references/bend/bend2/base.bend")
SCAN_DIRS = ["tinybendygrad", "examples", "langs"]

# ---------------------------------------------------------------- parsing


def split_top(s: str) -> list[str]:
    """Split on commas at paren/bracket/brace depth 0 and angle depth 0.

    String and char literals are skipped whole, so `"{0}.arg"` does not throw the
    brace depth off and split `String.concat(["a", b])` into two arguments.
    Angle depth only counts a `<` that directly follows an identifier char, so
    `Map<&2, String>` is one argument.
    """
    out: list[str] = []
    cur: list[str] = []
    depth = angle = 0
    i, n = 0, len(s)
    while i < n:
        c = s[i]
        if c in "\"'":
            i = _scan_literal(s, i, cur)
            continue
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif c == "<" and i > 0 and (s[i - 1].isalnum() or s[i - 1] in "_>"):
            angle += 1
        elif c == ">" and angle > 0:
            angle -= 1
        if c == "," and depth <= 0 and angle <= 0:
            out.append("".join(cur).strip())
            cur = []
            i += 1
            continue
        cur.append(c)
        i += 1
    tail = "".join(cur).strip()
    # a TRAILING COMMA is legal and appears in the port (`ex_rngs(one_sh(3, 4), )`),
    # so a final empty argument is dropped rather than counted against the arity
    if tail == "" and out:
        return out
    out.append(tail)
    return out


def _scan_literal(s: str, i: int, cur: list[str]) -> int:
    """Copy a `"`/`'` literal starting at i into cur; return the index past it.

    Backslash-escapes matter: `ops_dsp.bend:1178` holds one C string containing
    `volatile(\\"r0 = %1; ... trap0(#1)` and without escape handling the scanner
    stops at the `\"`, so `trap0(` and `Kind(` inside the ASM read as calls.
    """
    q, n, j = s[i], len(s), i + 1
    while j < n:
        if s[j] == "\\":
            j += 2
            continue
        if s[j] == q:
            j += 1
            break
        j += 1
    cur.append(s[i: min(j, n)])
    return j


def match_paren(s: str, open_at: int) -> int:
    depth = 0
    i, n = open_at, len(s)
    while i < n:
        c = s[i]
        if c in "\"'":
            i = _scan_literal(s, i, [])
            continue
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def mask_comments(src: str) -> str:
    """Blank `#` comments AND string-literal interiors, preserving every offset.

    WITHOUT masking the COMMENTS THE TOOL CRIES WOLF: every `.bend` file in this
    port explains the very rules it breaks, so a `#`-unaware scan reports
    `Map.get(String, "", m, nm)` from the prose documenting the fix.

    The string interiors go too, because `"Or("` inside `String.concat(["Or(", a,
    b, ")"])` is a `Or(` that reads as a call to base's `Or(-A: Type, -B: Type)`
    -- two phantom TYPE findings from one line.  Quotes are left in place so a
    zero-string argument still classifies as a zero.
    """
    out = list(src)
    i, n = 0, len(src)
    while i < n:
        if src[i] == "#":
            while i < n and src[i] != "\n":
                out[i] = " "
                i += 1
        elif src[i] in "\"'":
            start = i
            end = _scan_literal(src, i, [])
            for k in range(start + 1, min(end, n) - 1):
                if out[k] != "\n":
                    out[k] = " "
            i = end
        else:
            i += 1
    return "".join(out)


@dataclass
class Def:
    name: str
    params: list[str]
    file: str
    line: int
    ret: str = ""

    @property
    def arity(self) -> int:
        return len(self.params)

    def annot(self, i: int) -> str:
        p = self.params[i]
        if ":" not in p:
            return ""
        return p.split(":", 1)[1].strip()

    def binder(self, i: int) -> str:
        return self.params[i].split(":", 1)[0].strip().lstrip("-+")


DEF_RE = re.compile(r"^def\s+([A-Za-z_][\w.]*)\s*\(")
DEF_SOLO_RE = re.compile(r"^def\s+([A-Za-z_][\w.]*)\s*:")
LAW_HDR_RE = re.compile(r"^law\s+([A-Za-z_][\w.]*)\s*:\s*$")
FOR_RE = re.compile(r"^for\s+(~|-|\+)?([A-Za-z_]\w*)\s*:\s*(.+?)\s*$")
KEYWORDS = {"case", "match", "def", "law", "type", "import", "let", "in", "do", "if", "else",
            "return", "yield", "then", "where", "as", "and", "or", "not", "is", "IO"}
IMPORT_RE = re.compile(r"^import\s+(\S+)(?:\s+as\s+([A-Za-z_]\w*))?\s*$")
TYPE_RE = re.compile(r"^type\s+([A-Za-z_][\w.]*)\b")
LAW_RE = re.compile(r"^law\s+([A-Za-z_][\w.]*)\s*:\s*$")


_DEFS_CACHE: dict[str, dict[str, "Def"]] = {}


def parse_defs(path: str) -> dict[str, Def]:
    if path in _DEFS_CACHE:
        return _DEFS_CACHE[path]
    _DEFS_CACHE[path] = _parse_defs(path)
    return _DEFS_CACHE[path]


def _parse_defs(path: str) -> dict[str, Def]:
    """Parse `def NAME(params) -> Ret:` including headers wrapped over lines.

    `base.bend` writes `List.contains`'s four params across two lines, so a
    line-at-a-time reader records arity 0 and then flags all four of its call
    sites as ARITY errors -- a checker bug that reads as a port bug.  Measured.
    """
    src = open(path).read()
    lines = src.split("\n")
    defs: dict[str, Def] = {}
    i = 0
    while i < len(lines):
        line = lines[i]
        m = DEF_RE.match(line)
        if not m:
            ms = DEF_SOLO_RE.match(line)
            if ms:
                defs[ms.group(1)] = Def(ms.group(1), [], path, i + 1, "")
            i += 1
            continue
        open_at = line.index("(", m.start(1) + len(m.group(1)) - 1)
        head, j = line, i
        while match_paren(head, open_at) < 0 and j + 1 < len(lines):
            j += 1
            head += "\n" + lines[j]
        close = match_paren(head, open_at)
        if close < 0:
            i += 1
            continue
        body = head[open_at + 1: close]
        rest = head[close + 1:]
        rm = re.match(r"\s*->\s*([^:]+):", rest)
        ret = rm.group(1).strip() if rm else ""
        params = split_top(body) if body.strip() else []
        defs[m.group(1)] = Def(m.group(1), params, path, i + 1, ret)
        i = j + 1
    return defs


def _parse_laws(path: str) -> dict[str, Def]:
    """`law NAME:` / `for a: T` / ret -- the signature of a NATIVE primitive.

    `F32.neg`, `F32.add`, `Word.add` and ~300 other primitives have NO `def` in
    base.bend: they are compiler intrinsics whose arity and types are declared
    only by a `law` block.  Without reading those, 63 `F32.neg` call sites read
    as "unresolved" and are silently NOT examined -- the failure mode this
    whole checker exists to prevent.
    """
    lines = open(path).read().split("\n")
    laws: dict[str, Def] = {}
    i, n = 0, len(lines)
    while i < n:
        m = LAW_HDR_RE.match(lines[i])
        if not m:
            i += 1
            continue
        params: list[str] = []
        ret = ""
        j = i + 1
        while j < n:
            ln = lines[j].strip()
            if not ln or ln.startswith("#"):
                j += 1
                continue
            fm = FOR_RE.match(ln)
            if fm:
                params.append(f"{fm.group(1) or ''}{fm.group(2)}: {fm.group(3)}")
                j += 1
                continue
            if ln.startswith("law ") or ln.startswith("def ") or ln.startswith("type "):
                break                      # next declaration: the block is over
            ret = ln                      # the LAST such line is the return type
            j += 1
        laws.setdefault(m.group(1), Def(m.group(1), params, path, i + 1, ret))
        i = j if j > i + 1 else i + 1
    return laws


def parse_file(path: str) -> dict:
    src = open(path).read()
    lines = src.split("\n")
    imports: list[tuple[str, str]] = []
    for line in lines:
        m = IMPORT_RE.match(line)
        if m:
            imports.append((m.group(1), m.group(2) or ""))
    return {"defs": parse_defs(path), "imports": imports, "src": src, "lines": lines}


# ---------------------------------------------------------------- zero/type shape

ZERO_LITERALS = {"0", "0n", '""', "''", "False{}", "True{}", "Unit{}", "Nil{}", "0.0", "-0"}
# a slot the def calls a key
KEYISH = re.compile(r"\b(key|kb|k\b|name)", re.I)
# a bare constant: a number, a Nat, a string, or `0n`
LITERAL = re.compile(r"""(-?\d+n?|0x[0-9a-fA-F]+|"[^"]*"|'[^']*')""")


TYPE_RE_SHAPE = re.compile(r"^~?([A-Z][\w]*|\w+\.[A-Z][\w]*)"
                           r"(<[^<>]*(<[^<>]*>)?[^<>]*>)?$")
# `IO(Unit)`, `File & Result<...>`, `(U32 & U32)`, `U32 -> Bool` -- all TYPE slots
TYPE_WRAPPED = re.compile(r"^~?[A-Z]\w*(<.*>)?\s*(\(.*\)|&.*)$")
TYPE_PARENED = re.compile(r"^~?\(.*\)$")
TYPE_ARROW = re.compile(r"^~?[A-Z].*->.*$")


def arg_shape(a: str) -> str:
    """zero | quant | type | value.

    Bend's TYPE arguments are not one shape: `List<&2, U32>` (generic
    application), `IO(Unit)` (effect application), `File & Result<...>` (an
    intersection) and `(U32 & U32)` (a parenthesised pair) are all TYPE slots.
    Recognising only the first form reported 17 phantom VALUETYPE findings.
    `~A` is the explicit-type-application sigil, so it is stripped first.
    """
    a = a.strip()
    if a in ZERO_LITERALS:
        return "zero"
    if re.fullmatch(r"~?&\d+", a):
        return "quant"
    if TYPE_RE_SHAPE.match(a) or TYPE_WRAPPED.match(a) \
            or TYPE_PARENED.match(a) or TYPE_ARROW.match(a):
        return "type"
    return "value"


# ---------------------------------------------------------------- call extraction

CALL_RE = re.compile(r"(?<![.\w])([A-Za-z_][\w]*(?:\.[A-Za-z_]\w*)*)\s*\(")


def find_calls(src: str) -> list[tuple[str, int, list[str], int]]:
    """-> (name, offset_of_open_paren, args, line_number)"""
    out = []
    for m in CALL_RE.finditer(src):
        name = m.group(1)
        if name.split(".")[0] in KEYWORDS:
            continue
        # a bare '(' preceded by `def NAME ` is a definition, not a call
        pre = src[max(0, m.start() - 6): m.start()]
        if re.search(r"\bdef\s+$", pre):
            continue
        open_at = m.end() - 1
        close = match_paren(src, open_at)
        if close < 0:
            continue
        inner = src[open_at + 1: close]
        args = split_top(inner) if inner.strip() else []
        line = src.count("\n", 0, m.start()) + 1
        out.append((name, open_at, args, line))
    return out


def check_call(name: str, d: Def, args: list[str], rel: str, line: int,
               findings: list, show_all: bool, is_base: bool) -> None:
    """`is_base` gates the heuristic checks.

    ZEROKEY/LITKEY/SWAP read the binder NAME to guess which slot is a key.  That
    is trustworthy in base.bend, whose `key: String` really is a key, and NOT
    trustworthy for the port's own defs: `def row(k: String, v: String)` is a
    GATE LABEL, and its first argument is a constant in every one of its ~900
    call sites.  So for local defs only ARITY and VALUETYPE run unattended.
    """
    kinds = [arg_shape(a) for a in args]
    if show_all:
        print(f"{rel}:{line}: {name}/{d.arity} -> {d.ret} :: {args}")
    if len(args) != d.arity:
        findings.append(("ARITY", rel, line, name, args,
                         f"def {d.name} takes {d.arity}: {d.params}"))
        return
    for i, a in enumerate(args):
        an, sh = d.annot(i), kinds[i]
        iskey = bool(KEYISH.search(d.binder(i)))
        iskind = bool(re.match(r"^(Kind\(|Quant$|Type$|Data$|&\d)", an))
        if sh == "zero" and iskey and is_base:
            findings.append(("ZEROKEY", rel, line, name, args,
                             f"arg {i+1} is the value zero `{a}` but param is "
                             f"`{d.binder(i)}: {an}` -- a KEY slot"))
        if iskind and sh == "value":
            findings.append(("VALUETYPE", rel, line, name, args,
                             f"arg {i+1} is `{a}` but param is "
                             f"`{d.binder(i)}: {an}` -- a KIND slot"))
        if iskind and sh == "zero":
            findings.append(("ZEROTYPE", rel, line, name, args,
                             f"arg {i+1} is the value zero `{a}` in "
                             f"`{d.binder(i)}: {an}` -- a KIND slot"))
    if not is_base:
        return
    # `List.append(a, A, xs, ys)` IS `xs ++ ys`: a cons written FIRST is the HEAD,
    # so a fold that walks DOWN and accumulates UP must REVERSE its accumulator
    # before answering, or it builds the list backwards.  `helpers.bend`'s
    # `ansistrip` and `sz.bend`'s `added` both do.  966 call sites are too many to
    # read, so the check is structural: a list literal in slot 3 with a bare name
    # in slot 4 is the shape, and it type-checks because both are `List<a, A>`.
    if name == "List.append" and len(args) >= 4 \
            and re.fullmatch(r"\[[^\[\]]*\]", args[2]) \
            and re.fullmatch(r"[a-z_]\w*", args[3]):
        findings.append(("HEADTAIL", rel, line, name, args,
                         f"arg 3 is the literal {args[2]} and arg 4 is `{args[3]}`; "
                         f"`List.append` IS `{args[2]} ++ {args[3]}` -- cons is HEAD"))
    for i in range(d.arity):
        for j in range(i + 1, d.arity):
            ai, aj = d.annot(i), d.annot(j)
            if not ai or ai != aj:
                continue
            ki, kj = bool(KEYISH.search(d.binder(i))), bool(KEYISH.search(d.binder(j)))
            if ki == kj:
                continue
            keyi, valj = (i, j) if ki else (j, i)
            if kinds[keyi] == "zero" and kinds[valj] != "zero":
                findings.append(("SWAP", rel, line, name, args,
                                 f"arg {keyi+1} (`{d.binder(keyi)}`) is the zero "
                                 f"`{args[keyi]}` while arg {valj+1} "
                                 f"(`{d.binder(valj)}`) is not -- both `{ai}`"))
            # A LITERAL in a key slot is a transposition candidate: no key in this
            # port is spelled as a bare constant, and a transposition puts the
            # other argument's literal exactly here.  This is the SILENT case --
            # `Map.set(a, V, m, v, "k")` type-checks when V = String.
            if i and ki and LITERAL.fullmatch(args[i]) and not LITERAL.fullmatch(args[j]):
                findings.append(("LITKEY", rel, line, name, args,
                                 f"arg {i+1} (`{d.binder(i)}`) is the literal "
                                 f"`{args[i]}` and arg {j+1} (`{d.binder(j)}`) "
                                 f"is not -- both `{ai}`"))


def main() -> None:
    argv = sys.argv[1:]
    only = None
    if "--fns" in argv:
        only = set(argv[argv.index("--fns") + 1].split(","))
    show_all = "--all" in argv
    scan_local = "--local" in argv
    unresolved: dict[str, int] = {}

    base_defs = parse_defs(BASE)
    for nm, d in _parse_laws(BASE).items():
        base_defs.setdefault(nm, d)
    base_types = set()
    for line in open(BASE):
        m = TYPE_RE.match(line)
        if m:
            base_types.add(m.group(1))

    files: list[str] = []
    for d in SCAN_DIRS:
        for root, _, names in os.walk(os.path.join(ROOT, d)):
            for nm in names:
                if nm.endswith(".bend") and not nm.endswith(".mut.bend"):
                    files.append(os.path.join(root, nm))
    files.sort()

    findings = []
    examined = 0
    calls_seen: dict[str, int] = {}

    for path in files:
        info = parse_file(path)
        mask = mask_comments(info["src"])
        own = info["defs"]
        own_types = set()
        for line in info["lines"]:
            m = TYPE_RE.match(line)
            if m:
                own_types.add(m.group(1))
        # alias -> list of files
        alias: dict[str, list[str]] = {}
        for target, asname in info["imports"]:
            if target.startswith("."):
                ap = os.path.normpath(os.path.join(os.path.dirname(path), target))
            elif target == "Base":
                ap = BASE
            else:
                continue
            if not os.path.exists(ap):
                continue
            alias.setdefault(asname or os.path.basename(ap)[:-5], []).append(ap)

        def resolve(name: str) -> tuple[str, Def | None]:
            """Map a call-site name to (defining file, Def).

            An import ALIAS is a namespace prefix, so `O.Found.i` with
            `import ./ops.bend as O` is the def `Found.i` IN ops.bend, and both
            `O.` and a bare `Found.i` must find it.  Resolving only the full
            dotted name left 13,621 call sites unexamined on the first run --
            a green result from 40% coverage, which is worse than no result.
            """
            # 1. local def in this file
            if name in own:
                return path, own[name]
            # 2. alias-qualified: strip the alias, look the tail up in the target
            if "." in name:
                head, rest = name.split(".", 1)
                for ap in alias.get(head, []):
                    d = base_defs if ap == BASE else parse_defs(ap)
                    if name in d:
                        return ap, d[name]
                    if rest in d:
                        return ap, d[rest]
            # 3. unqualified import
            for targets in alias.values():
                for ap in targets:
                    d = base_defs if ap == BASE else parse_defs(ap)
                    if name in d:
                        return ap, d[name]
            # 4. base
            if name in base_defs:
                return BASE, base_defs[name]
            return "", None

        for name, open_at, args, line in find_calls(mask):
            dpath, d = resolve(name)
            if d is None:
                unresolved[name] = unresolved.get(name, 0) + 1
                continue
            if dpath != BASE:
                if scan_local:
                    examined += 1
                    calls_seen[name] = calls_seen.get(name, 0) + 1
                    check_call(name, d, args, os.path.relpath(path, ROOT), line,
                               findings, show_all, False)
                continue
            if only and name not in only:
                continue
            examined += 1
            calls_seen[name] = calls_seen.get(name, 0) + 1
            check_call(name, d, args, os.path.relpath(path, ROOT), line,
                       findings, show_all, True)

    print(f"\n=== call sites examined: {examined} across {len(files)} files "
          f"(base only: {not scan_local}) ===")
    for k, v in sorted(calls_seen.items(), key=lambda kv: -kv[1]):
        print(f"  {v:4d}  {k}")
    print(f"\n=== unresolved names: {len(unresolved)} distinct, "
          f"{sum(unresolved.values())} sites (not counted as examined) ===")
    for k, v in sorted(unresolved.items(), key=lambda kv: -kv[1])[:25]:
        print(f"  {v:4d}  {k}")
    print(f"\n=== findings: {len(findings)} ===")
    for kind, rel, line, name, args, why in findings:
        print(f"[{kind}] {rel}:{line}: {name}{tuple(args)}\n        {why}")


if __name__ == "__main__":
    main()