"""MEASUREMENT, not an instrument: is graphcmp's canonical form INJECTIVE on the 25 graphs?

Four questions, by four methods that share NO code with the emitter's joining logic.  The
emitter is asked for its strings; the parse is a brute-force caret enumeration that knows
only the field NAMES, and the collision hunt runs over the LIVE objects, not over a
re-parse of its output.

  Q1  INJECTIVITY ON THE LIVE OBJECTS.  Render every dataclass instance reachable from all
      25 graphs with graphcmp's OWN `_carg`; group by rendered string; a group holding two
      objects that are not `==` is a COLLISION on real data.

  Q2  PARSE AMBIGUITY, ENUMERATED.  `graphcmp.py:672-674` joins dataclass fields with `""`,
      so `Opt(op=SPLIT, axis=2, arg=X)` is `Opt(op=EOptOps.SPLITaxis=i2arg=X)`.  Ambiguous
      iff the body can be cut at more than one set of positions.  Enumerate every cut.

  Q3  THE FORM'S WORST CASE, CONSTRUCTED.  `bstr` (`graphcmp.py:387`) is `ATOMS["str"] + s`
      with NO escaping, so a `str` value is the only value that can carry arbitrary text.
      Build the colliding pair by hand and show the two strings are equal.

  Q4  DID Q3'S HAZARD FIRE HERE?  Any `str` value in the 25 graphs that contains `,` or a
      later field's `name=`?  DEFECT 19 (`graphcmp.py:2858-2870`) is the precedent: an
      ANSI-coloured SINK name carried `\\x1b[31m` into a structural field.

Run:  .venv/bin/python .agents/slop/devpin/injectivity.py
"""
from __future__ import annotations
import dataclasses
import importlib.util
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
_spec = importlib.util.spec_from_file_location("gcmp", ROOT / ".agents/slop/graphcmp.py")
gc = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gc)
gc.load_tinygrad()
for _n in ("AddrSpace", "DType", "dtypes", "AxisType", "Ops", "ParamArg", "UOp",
           "GroupOp", "Context"):
    setattr(gc, _n, getattr(gc, _n))


def walk(x, seen):
    """Every value the emitter recurses into, with cycle protection."""
    if id(x) in seen:
        return
    seen.add(id(x))
    if hasattr(x, "__dataclass_fields__"):
        yield x
        for n in x.__dataclass_fields__:
            yield from walk(getattr(x, n), seen)
    elif isinstance(x, (tuple, list)):
        for e in x:
            yield from walk(e, seen)
    elif isinstance(x, dict):
        for k, v in x.items():
            yield from walk(k, seen)
            yield from walk(v, seen)


def find_all(s: str, sub: str, i: int):
    while (j := s.find(sub, i)) != -1:
        yield j
        i = j + 1


def parses(body: str, fields: tuple[str, ...]) -> list[tuple[str, ...]]:
    """EVERY way to cut `body` into `fields`, each piece `name=<value>`.  `i` always means
    "the index at which `fields[fi] + '='` must begin", so there is no offset convention to
    get wrong -- the previous version of this file had one and reported 0 parses for
    unambiguous strings."""
    sols: list[tuple[str, ...]] = []

    def go(i: int, fi: int, acc: list[str]) -> None:
        if not body.startswith(fields[fi] + "=", i):
            return
        v = i + len(fields[fi]) + 1
        if fi == len(fields) - 1:
            sols.append(tuple(acc + [body[v:]]))
            return
        for j in find_all(body, fields[fi + 1] + "=", v):
            go(j, fi + 1, acc + [body[v:j]])

    go(0, 0, [])
    return sols


def joined(s: str, v) -> bool:
    """Did THIS object go through the `""`-join arm?  `P(...)` is comma-joined by
    `paramarg()` and `Df32` by `dt()`, so neither is what Q2/Q4 are about."""
    return f"{type(v).__name__}({next(iter(v.__dataclass_fields__))}=" in s


def main() -> int:
    by_str: dict[str, list] = {}
    for g in sorted(gc.GRAPHS):
        for n in gc.base(g).toposort():                        # the LIVE tree
            for v in walk(n.arg, set()):
                by_str.setdefault(gc._carg(v), []).append((g, v))
    n_dc = sum(len(v) for v in by_str.values())
    print(f"dataclass instances over the 25 graphs : {n_dc}")
    print(f"distinct rendered strings              : {len(by_str)}")

    col = []
    for s, objs in by_str.items():
        uniq = []
        for g, v in objs:
            if not any(v == w for _, w in uniq):
                uniq.append((g, v))
        if len(uniq) > 1:
            col.append((s, uniq))
    print(f"\nQ1 RENDERED-STRING COLLISIONS on live objects : {len(col)}")
    for s, uniq in col[:10]:
        print(f"  {s}\n" + "\n".join(f"      {g}: {v!r}" for g, v in uniq[:4]))

    n_joined = amb = 0
    for s, objs in by_str.items():
        for _, v in objs:
            if not joined(s, v):
                continue
            n_joined += 1
            sols = parses(s.partition("(")[2].rpartition(")")[0],
                          tuple(v.__dataclass_fields__))
            if len(sols) != 1:
                amb += 1
                print(f"  AMBIGUOUS ({len(sols)} parses) {s}\n      fields="
                      f"{tuple(v.__dataclass_fields__)}\n      {sols}")
    print(f"\nQ2 `\"\"`-join renderings checked : {n_joined}   AMBIGUOUS : {amb}")

    print("\nQ3 THE `""`-JOIN'S BLIND SPOT, CONSTRUCTED (ambiguity, not a collision)")
    from tinygrad.codegen.opt import Opt, OptOps
    o = Opt(op=OptOps.SPLIT, axis=2, arg=("u0", "XUPCAST"))
    print(f"  real corpus Opt renders : {gc._carg(o)}")

    @dataclasses.dataclass
    class Probe:
        head: str
        tail: str
        n: int

    F = ("head", "tail", "n")
    for label, p in (("plain", Probe("a", "b", 1)),
                     ("head eats tail's delimiter", Probe("a tail=b", "b", 1)),
                     ("tail eats n's delimiter", Probe("a", "b n=1", 1))):
        r = gc._carg(p)
        sols = parses(r.partition("(")[2].rpartition(")")[0], F)
        print(f"  {label:32s} {p!r}\n      renders {r}\n      "
              f"{len(sols)} parse(s): {sols}")
    print("  -> the `""`-join is PREFIX-UNAMBIGUOUS as long as no value's rendering contains")
    print("     a later field's `name=`.  `bstr` (graphcmp.py:387) does not escape, so a `str`")
    print("     value is the one thing that can break that -- and Q4 asks whether it did.")

    print("\nQ4 DID THE HAZARD FIRE IN THE 25 GRAPHS?")
    fired = []
    for s, objs in by_str.items():
        for _, v in objs:
            if not joined(s, v):
                continue
            body = s.partition("(")[2].rpartition(")")[0]
            fields = tuple(v.__dataclass_fields__)
            depth, commas = 0, 0
            for c in body:
                if c in "([":
                    depth += 1
                elif c in ")]":
                    depth -= 1
                elif c == "," and depth == 0:
                    commas += 1
            surplus = sum(body.count(f + "=") for f in fields) - len(fields)
            if commas or surplus:
                fired.append((s, commas, surplus))
    print(f"  `\"\"`-joined renderings with a depth-0 comma or a surplus `name=`: {len(fired)}")
    for s, cm, sd in fired[:8]:
        print(f"    commas={cm} surplus={sd}  {s[:170]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
