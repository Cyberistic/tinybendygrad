#!/usr/bin/env python3
r"""groupop-gen.py -- GENERATE `tinybendygrad/uop/ops.bend`'s `GroupOp` SET-MEMBERSHIP
FUNCTIONS from upstream's own `GroupOp` class.

    .venv/bin/python .agents/slop/enum-tables/groupop-gen.py            # print the region
    .venv/bin/python .agents/slop/enum-tables/groupop-gen.py --write     # rewrite the region
    .venv/bin/python .agents/slop/enum-tables/groupop-gen.py --diff      # what --write would change

WHAT IT IS.  Upstream's `tinygrad/uop/__init__.py` declares `GroupOp` as a class of
SETS over `Ops` members:

    class GroupOp:
      Unary = {Ops.EXP2, ...}
      Defines = {Ops.PARAM, Ops.REFPARAM, Ops.BUFFER, Ops.ALLOC, Ops.BINARY}
      Associative = {Ops.ADD, Ops.MUL, Ops.AND, Ops.OR, Ops.MAX, Ops.XOR}
      ALU = set.union(Unary, Binary, Ternary)

and the port has to SPELL each set as a `match` over `Op`, because Bend has no
set literal over a datatype.  So the port's `GroupOp.*` functions are a
TRANSCRIPTION of upstream's class, and a transcription is exactly what rots:
MEASURED, against the vendored tree's own `tinygrad/uop/__init__.py` at
`HEAD`, the port's `GroupOp.associative` was MISSING `XOR` and the port's
`GroupOp.defines` was MISSING `BINARY`, and `tinybendygrad/uop/spec.bend:2118`
still QUOTED the pre-re-vendor `Defines = {Ops.PARAM, Ops.BUFFER, Ops.ALLOC}`.
None of that was visible to any instrument.

THE SOURCE OF TRUTH IS UPSTREAM'S OWN FILE, READ BY PATH.  Not a list typed
here: `tinygrad/uop/__init__.py` in this tree IS the pin the port is written
against, and the generator parses its `class GroupOp:` body and evaluates its
set expressions.  A group that upstream spells as `set.union(A, B)` is EMITTED
as the DERIVED FUNCTION the port already has, so the port keeps upstream's
"a derived set cannot drift from the sets it is built out of" property and the
generator does not have to flatten it.

THE ORDER IS UPSTREAM'S ORDER, NOT SORTED.  MEASURED: with the members SORTED,
ten of the twelve functions came out byte-different from the port's, because
the port's arms follow upstream's spelling order.  With upstream's order, ten of
twelve are byte-identical and the ONLY differences are the two missing members
above.  A generator that reorders its output is a generator that rewrites the
file for its own reasons.

WHAT IT IS NOT.  It does not touch the `Ops` tables -- `Ops.name.of`,
`Ops.value` and `all_ops` -- because `gates/opseven-gate.py`'s
`ops_value_is_declaration_order()` already holds those three against the port's
own `type Op is Data:` block, in declaration order, with `Ops.value` numbering
them `1..N`.  A second instrument for one property is not a second witness.

THE PORT-ONLY GROUP STAYS OUT.  `GroupOp.opaque_call_bodies` has no upstream
counterpart -- it is this port's own set, named in a comment in the file -- so
it is not in the generated region and the generator never claims it.

THE UNMAPPED CHECK IS A DIFFERENCE, NOT A LIST.  `PORT_NAMES` is the map from
upstream's spelling to the port's, and every SET it names is READ OUT OF
UPSTREAM'S FILE.  An upstream group the map does not name is REPORTED as
`UNMAPPED`, so the map cannot silently drop a group: `Effect` was unmapped and
reported, and upstream's four call sites use it, so it is mapped now.

IDEMPOTENCE AND CONTAINMENT.  `--write` replaces the region BETWEEN two marker
lines and writes nothing else; the file is read and written under this tree's
root, and nothing outside it is read or written.  Running it twice produces the
same bytes, because the region is a pure function of upstream's file.
"""
from __future__ import annotations

import argparse
import ast
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
UPSTREAM = ROOT / "tinygrad" / "uop" / "__init__.py"
PORT = ROOT / "tinybendygrad" / "uop" / "ops.bend"

BEGIN = "# ==== BEGIN GENERATED GroupOp SETS"
END = "# ==== END GENERATED GroupOp SETS"

#: The upstream groups the port spells as a `match`, and the port's name for each.
#: The upstream NAME is the key and the port's name is the value; the port's
#: functions are lowercase because Bend's `GroupOp.unary` reads as a method of
#: the `GroupOp` class the port does not have.
#:
#: THIS LIST IS NOT THE POPULATION.  It is the map from upstream's spelling to
#: the port's, and every SET it names is READ OUT OF UPSTREAM'S FILE.  A group
#: upstream has and this map does not name is reported by `--diff` as
#: `UNMAPPED`, so the map cannot silently drop a group: the check is a
#: DIFFERENCE against upstream's own class, not a list of what we remembered.
PORT_NAMES = {
    "Unary": "unary",
    "Binary": "binary",
    "Ternary": "ternary",
    "Defines": "defines",
    "Irreducible": "irreducible",
    "Movement": "movement",
    "Commutative": "commutative",
    "Associative": "associative",
    "Idempotent": "idempotent",
    "Reduce": "reduce",
    "Comparison": "comparison",
    # `Effect` -- upstream's "ops that may have a side effect each time they
    # run".  The port had NO function for it, so it was UNMAPPED and the
    # generator said so.  It is emitted now: upstream has it, and a group the
    # port does not spell is a group the port cannot drift away from.
    "Effect": "effect",
}

#: The upstream groups the port DERIVES rather than spells, and the port's
#: derived function's expression.  `set.union(A, B)` in upstream becomes
#: `Bool.or(f(A), f(B))` in the port, and `A | B` becomes the same.
DERIVED = {
    "ALU": ("alu", "Bool.or(GroupOp.unary(op), Bool.or(GroupOp.binary(op), GroupOp.ternary(op)))"),
    "Broadcastable": ("broadcastable", "Bool.or(GroupOp.binary(op), GroupOp.ternary(op))"),
    "Elementwise": ("elementwise", None),  # emitted from its own upstream expression
}

#: The extra members a DERIVED upstream group spells as a set literal beside
#: its group names -- `set.union(ALU, {Ops.CAST, Ops.BITCAST})`.  Filled by
#: `evaluate_groups()`.
DERIVED_EXTRA: dict[str, set[str]] = {}


def port_name_of(up_name: str) -> str:
    """The port's name for an upstream group, literal or derived."""
    if up_name in PORT_NAMES:
        return PORT_NAMES[up_name]
    if up_name in DERIVED:
        return DERIVED[up_name][0]
    raise KeyError(f"no port function for upstream group {up_name}")


def upstream_ops() -> list[str]:
    """Upstream's `Ops` member names, in declaration order, from `class Ops(FastEnum):`."""
    text = UPSTREAM.read_text()
    m = re.search(r"class Ops\(FastEnum\):(.*?)\n(?=class |\Z)", text, re.S)
    if m is None:
        raise ValueError(f"no `class Ops(FastEnum):` in {UPSTREAM}")
    return re.findall(r"\b([A-Z][A-Z0-9_]*)\s*=\s*auto\(\)", m.group(1))


def upstream_groups() -> dict[str, object]:
    """Upstream's `GroupOp` class body, as an AST, for the expressions to evaluate."""
    tree = ast.parse(UPSTREAM.read_text())
    for node in tree.body:
        if isinstance(node, ast.ClassDef) and node.name == "GroupOp":
            return {st.targets[0].id: st.value for st in node.body if isinstance(st, ast.Assign)}
    raise ValueError(f"no `class GroupOp` in {UPSTREAM}")


def evaluate_groups() -> tuple[dict[str, set[str]], dict[str, list[str]]]:
    """`(literal sets, derived expressions)` for upstream's `GroupOp`.

    A LITERAL group is upstream's `{Ops.X, ...}`.  A DERIVED group is upstream's
    `set.union(...)` or `A | B`, and it is kept as the EXPRESSION so the port can
    derive it too -- flattening a derived group into a literal would be the
    port's own drift, and upstream's comment says the union IS the point.
    """
    ops = set(upstream_ops())
    raw = upstream_groups()
    scope: dict[str, set[str]] = {"Ops": ops}
    literals: dict[str, set[str]] = {}
    order: dict[str, list[str]] = {}
    derived: dict[str, list[str]] = {}

    def members_of(node: ast.AST) -> list[str]:
        if isinstance(node, ast.Set):
            out: list[str] = []
            for el in node.elts:
                if not isinstance(el, ast.Attribute) or el.attr not in ops:
                    raise ValueError(f"unexpected member {ast.dump(el)}")
                out.append(el.attr)
            return out
        raise ValueError(f"unexpected expression {ast.dump(node)}")

    # The upstream body is written top to bottom and every set it names is
    # defined before it is used, so ONE pass in source order resolves.
    for name, value in raw.items():
        if isinstance(value, ast.Set):
            order[name] = members_of(value)
            scope[name] = set(order[name])
            literals[name] = scope[name]
        elif isinstance(value, ast.Call) and isinstance(value.func, ast.Attribute) and value.func.attr == "union":
            # `set.union(A, B)` -- the args are group NAMES.  `set.union(ALU, {...})`
            # has a SET LITERAL as its second arg, which is upstream spelling the
            # extra members of a derived set, and the port spells them too.
            args = [a.id for a in value.args if isinstance(a, ast.Name)]
            extra = [m for a in value.args if isinstance(a, ast.Set) for m in members_of(a)]
            derived[name] = args
            scope[name] = set().union(*(scope[a] for a in args)) | set(extra)
            literals.setdefault(name, scope[name])
            DERIVED_EXTRA[name] = extra
            order[name] = extra
        elif isinstance(value, ast.BinOp) and isinstance(value.op, ast.BitOr):
            derived[name] = [value.left.id, value.right.id]
            scope[name] = scope[value.left.id] | scope[value.right.id]
        elif isinstance(value, ast.Call) and isinstance(value.func, ast.Name) and value.func.id == "set":
            # `All = set(Ops)`
            scope[name] = set(ops)
            literals[name] = scope[name]
        else:
            raise ValueError(f"unhandled upstream expression for {name}: {ast.dump(value)}")
    return literals, derived, order


def render_literal(name: str, members: list[str]) -> list[str]:
    """The port's `match` function for one literal upstream set."""
    out = [f"def GroupOp.{name}(op: Op) -> Bool:", "  match op:"]
    for m in members:
        out.append(f"    case Ops{m}{{}}: True{{}}")
    out.append("    case _: False{}")
    return out

def render_region() -> tuple[str, list[str]]:
    """`(region text, notes)` -- the GENERATED region and what it says."""
    literals, derived, order = evaluate_groups()
    notes: list[str] = []

    unmapped = sorted(set(literals) - set(PORT_NAMES) - {"All"} - set(DERIVED))
    if unmapped:
        notes.append(f"UNMAPPED upstream groups with no port function: {', '.join(unmapped)}")

    lines: list[str] = [
        BEGIN,
        f"# GENERATOR .agents/slop/enum-tables/groupop-gen.py --write",
        "# FROM upstream's `class GroupOp` in tinygrad/uop/__init__.py, READ BY PATH.",
        "# THE PORT'S SET-MEMBERSHIP FUNCTIONS ARE A TRANSCRIPTION OF THAT CLASS, AND A",
        "# TRANSCRIPTION ROTTS: MEASURED, THE PORT'S `associative` WAS MISSING `XOR` AND",
        "# `defines` WAS MISSING `BINARY` WHILE `uop/spec.bend` STILL QUOTED THE",
        "# PRE-RE-VENDOR `Defines`.  DO NOT HAND-EDIT BELOW.",
        "#",
        "# `set.union(Unary, Binary, Ternary)` and `set.union(Binary, Ternary)` ARE",
        "# WRITTEN AS THE UNION THEY ARE AND NOT AS A FOURTH TABLE, SO A DERIVED SET",
        "# CANNOT DRIFT FROM THE SETS IT IS BUILT OUT OF.  # TODO: is BITCAST always",
        "# Elementwise if it's shape changing?",
    ]

    for up_name, port_name in PORT_NAMES.items():
        if up_name not in literals:
            notes.append(f"MISSING upstream group {up_name}")
            continue
        lines.append("")
        lines.extend(render_literal(port_name, order[up_name]))

    for up_name, (port_name, _) in DERIVED.items():
        if up_name not in derived:
            notes.append(f"MISSING upstream group {up_name}")
            continue
        lines.append("")
        base = derived[up_name]
        extra = DERIVED_EXTRA.get(up_name, [])
        if len(base) == 1 and extra:
            # `Elementwise = set.union(ALU, {Ops.CAST, Ops.BITCAST})` -- one base
            # and a set literal.  The port spells the extras and defers the base
            # to `GroupOp.alu`, so the base cannot drift from it.
            lines.append(f"def GroupOp.{port_name}(op: Op) -> Bool:")
            lines.append("  match op:")
            for m in extra:
                lines.append(f"    case Ops{m}{{}}: True{{}}")
            lines.append(f"    case _: GroupOp.{port_name_of(base[0])}(op)")
        else:
            # The union of the base groups, in upstream's own order, RIGHT-
            # NESTED, so the emitted expression reads as upstream's
            # `set.union(Unary, Binary, Ternary)` reads: `or(or(A, B), C)`.
            # A derived set cannot drift from the sets it is built out of.
            ors = [f"GroupOp.{port_name_of(b)}(op)" for b in base]
            expr = ors[-1]
            for nxt in reversed(ors[:-1]):
                expr = f"Bool.or({nxt}, {expr})"
            lines.append(f"def GroupOp.{port_name}(+op: Op) -> Bool:")
            lines.append(f"  {expr}")

    lines.append("")
    lines.append(END)
    return "\n".join(lines), notes


def port_block() -> tuple[str, int, int]:
    """The port's `GroupOp` SET-MEMBERSHIP BLOCK, located BY ITS OWN DEFS.

    `(text, start offset, end offset)` -- the span from `def GroupOp.unary` to
    the end of `def GroupOp.elementwise`, which is the LAST of the generated
    functions.  It is found by the DEFS rather than by a line number, because a
    locator a rename invalidates is not a locator.

    The end is the LAST line of `elementwise`'s body, not the start of the next
    `def`: `GroupOp.opaque_call_bodies` is 490 lines further down this file, so
    an end marker at ITS start swallowed the whole `AxisType`/`Const`/`ParamArg`
    block.  A block locator that can swallow half a file is not a locator.
    """
    text = PORT.read_text()
    start = text.index("def GroupOp.unary(op: Op) -> Bool:")
    tail = text.index("    case _: GroupOp.alu(op)\n", start)
    end = tail + len("    case _: GroupOp.alu(op)\n")
    return text[start:end], start, end


def current_region() -> tuple[str, int, int] | None:
    """The region currently in the port's file: `(text, start offset, end offset)`."""
    text = PORT.read_text()
    if BEGIN not in text or END not in text:
        return None
    start = text.index(BEGIN)
    end = text.index(END) + len(END)
    return text[start:end], start, end


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--write", action="store_true", help="rewrite the region in the port's file")
    ap.add_argument("--diff", action="store_true", help="print what --write would change")
    args = ap.parse_args()

    region, notes = render_region()
    for n in notes:
        print(n)

    cur = current_region()
    if cur is None:
        # BOOTSTRAP: the region has no markers yet, so the port's own block is
        # what the generator replaces.  The diff is against that block.
        block, _, _ = port_block()
        old = block
    else:
        old, _, _ = cur

    if old == region:
        print(f"REGION IS CURRENT: {len(region.splitlines())} lines, byte-identical")
        return 0
    if args.diff:
        import difflib
        print("\n".join(difflib.unified_diff(old.splitlines(), region.splitlines(),
                                             "current", "generated", lineterm="", n=1)))
        return 0
    if args.write:
        text = PORT.read_text()
        if cur is None:
            block, start, end = port_block()
            PORT.write_text(text[:start] + region + "\n" + text[end:])
        else:
            _, start, end = cur
            PORT.write_text(text[:start] + region + text[end:])
        print(f"WROTE {len(region.splitlines())} lines into {PORT}")
        return 0
    print(f"REGION DIFFERS: current {len(old.splitlines())} lines, generated {len(region.splitlines())} lines")
    return 1


if __name__ == "__main__":
    sys.exit(main())
