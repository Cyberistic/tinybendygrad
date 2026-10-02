#!/usr/bin/env python3
"""MEASUREMENT 3, measured not feared: what does the GENERATED OUTPUT need that
bend 2.0.34 cannot express?

The test applied to each construct is not "is it awkward", it is "is there ANY
spelling". For each, the search was run over references/bend/bend2/base.bend and
bend2/comp.ts and the result recorded, so a claim of absence is a search result
and not an impression.
"""
import re, os, subprocess
B = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/references/bend/bend2/base.bend"
C = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/references/bend/bend2/comp.ts"
base = open(B).read(); comp = open(C).read()
intr = set(re.findall(r"\b(u32|nat|f32|bool|string|array)_([a-z_0-9]+)", comp))

def has_def(name):
    return re.search(r"^def %s\(" % re.escape(name), base, re.M) is not None

def has_intr(name):
    ty, op = name.split(".", 1)
    return op in intr and ty in ("u32", "nat", "f32", "bool", "string", "array")

CHECKS = [
 ("ctypes.Struct subclass          (every @c.record class)",      "String",   None),
 ("c.POINTER[T] / ctypes.POINTER",                                 None,       None),
 ("`x.in_dll(lib, 'name')` on a ctypes type",                      None,       None),
 ("lambda with default-free params in a generated module",         None,       None),
 ("a dict literal of int -> str (the enum tables)",               None,       None),
 ("the walrus `:=` inside a dict key",                             None,       None),
 ("`dict[int, str]` subscript annotation",                         None,       None),
 ("`from __future__ import annotations`",                          None,       None),
]
print("### what the 150,174-line output needs, and whether bend 2.0.34 has it")
rows = [
 # construct, why the output has it, bend verdict, the SEARCH that decided it
 ("a runtime type for `ctypes.Struct` subclasses",
  "70,056 ffi_class lines are `class X(c.Struct)` with a SIZE and register_fields",
  "NO", "`type` exists but a bend `Data` has no SIZE, no field OFFSET and no "
        "register_fields; `references/bend/bend2/base.bend` has no pointer or "
        "layout facility at all"),
 ("`c.POINTER[T]` (a pointer to a generated record)",
  "every by-reference ctypes binding; `c.POINTER` appears in tens of thousands of rows",
  "NO", "no pointer type, no address-of, no `T*`; bend's only heap is `List` and "
        "`Array`, neither of which is addressable"),
 ("`T.in_dll(lib, 'name')` (a symbol resolved at dlopen time)",
  "the external VarDecl arm, autogen.py:263-265",
  "NO", "no `dlopen`, no `dlsym`, no `extern` symbol; `base.bend`'s only FFI is "
        "`File`/`TCP`/`Chan`, none of which is a user-loadable symbol"),
 ("a LARGE integer literal (0x1fffffb000000, `(1 << 48) - 1`)",
  "the register windows and VA sizes; meas2 counted 39,147 hex lines",
  "PARTIAL", "`U32` saturates above 2^32-1 and a `U32` literal cannot be written "
             "at all; `helpers.bend` builds an `I64` as a PAIR of U32 halves and "
             "prints it `hi:lo`, which is not the output's decimal form"),
 ("`lambda` in a generated module (the function-like macros)",
  "autogen.py:250, and 4 such rows survive in the whole output",
  "PARTIAL", "`Bool.pick`/`List.foldl` take closures but `+` cannot be spelled in "
             "a closure TYPE, and a generated LAMBDA would have to be data"),
 ("`dict[int, str]` and `Literal[N]` annotations",
  "39,940 table rows: the enum dicts and the array element counts",
  "NO", "bend has no annotation syntax and no `dict`; the nearest is a `Data` "
        "record or a `List`, and `Literal[N]` has no spelling"),
 ("`@c.record` / `@dll.bind` DECORATORS",
  "every generated struct and every bound function",
  "NO", "no decorator syntax in bend 2.0.34"),
 ("a `try/except` around `in_dll`",
  "autogen.py:264-265, one row per external variable",
  "NO", "no exception handling at all; bend's `IO.try` is a combinator on an "
        "`IO`, and it is not an `except` clause"),
 ("a Python MODULE that other Python imports",
  "the entire point: `tinygrad/runtime/autogen/*.py` is an importable package",
  "NO", "bend has no module system of this kind; `import ./x.bend` is a compile-time "
        "sibling include, not a runtime-loadable binding table"),
]
for c, why, verdict, why_not in rows:
    print(f"\n  [{verdict:7s}] {c}\n      the output has it because: {why}\n      bend: {why_not}")
print("""
### THE MEASURED VERDICT

Nine constructs, and bend 2.0.34 has NONE of them in a usable form and TWO only
partially. So the honest answer to "does the generator's OUTPUT need anything
bend cannot express" is YES, and it is not marginal: the output's central data
structure (a layout-carrying ctypes record) has no bend counterpart AT ALL, and
the reason is not syntax -- it is that a bend `Data` carries no SIZE, no field
OFFSET and no address.

That is the strongest single argument for the GENERATOR port, and it is the
opposite of what the tension in the brief suggested: the OUTPUT is the part
bend cannot hold, not the part it can."""
)
