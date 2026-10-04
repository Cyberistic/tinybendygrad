# 04 — "307/324 mechanically derivable" (libclang)

**VERDICT: CAN-FAIL** — 307 → 306 with one `c_int64` in one `@dll.bind` tuple.
**But the sibling `coverage: 324/324 = 100.0%` on the same run is CANNOT-FAIL: it
is `X/X`, and 66% of the "mechanically derivable" set is called "not mechanical"
by the same tool.**

Reproduced from the live tree, matching the committed
`.agents/slop/ffi-experiment/libclang-cost.txt` byte for byte:

```
.venv/bin/python .agents/slop/ffi-port-cost.py --pybind tinygrad/runtime/autogen/libclang.py
    entry points  : 324      mechanically derivable : 307/324 (95%)
    denominator   : 324      coverage      : 324/324 = 100.0%
    BLOCKED       : 17       need a layout decision : 203
```

## Subject and instrument

- **Subject:** the 324 `@dll.bind` signatures in
  `tinygrad/runtime/autogen/libclang.py` — specifically which have no
  absent-Bend-type blocker.
- **Instrument:** `mechanical = len(uniq) - len({f.name for f in blocked})`
  (`ffi-port-cost.py:445`).

**`mechanical` is a not-count of blockers, not a count of derivations.** Nothing
is derived. The set called "mechanically derivable" is defined by the *absence*
of a recorded blocker, where the blocker rule is a three-type test: 64-bit
integer or double past the 2^51−1 Nat window. So the honest reading of 307/324 is
**"307 signatures avoid three specific C types."**

## Plant — CAN-FAIL: 307 → 306

Three plants failed before this one, and the reasons are the audit's most useful
output, because each was a plant that did not land:

1. `clang_Type_getSizeOf` — chosen without reading the tool's own BLOCKED list.
   It is **already blocked** for its `c_int64` *return*, so adding an `int64`
   argument could not move anything.
2. `"(ctypes.c_int64, "` inserted after `(` — that adds a **bare parameter with
   no annotation**. `parse_pybind` reads an untyped name, not a type.
3. The Python **annotation** `:int` → `:ctypes.c_int64` — also inert, because
   `parse_pybind` (lines 377–390) reads the **`@dll.bind` decorator's ctypes
   tuple** and consults the annotation only as a fallback for positions the
   decorator did not cover. Verified by calling the parser: with the annotation
   set to `c_int64` it still reports `ctypes.c_int32` for that argument.

**The landing plant** rewrites the decorator of a declaration the tool's own
BLOCKED list excludes:

```
@dll.bind(CXIndex, ctypes.c_int32, ctypes.c_int32)      # before
@dll.bind(CXIndex, ctypes.c_int32, ctypes.c_int64)      # after

mechanically derivable : 306/324   (was 307/324)
BLOCKED                : 18        (was 17)
```

The harness asserts the plant landed (`c_int64` count +1) so this cannot
silently degrade into a no-op again.

**Disarm:** a comment appended to a copy of the binding file → `307/324`,
`324/324`, unchanged.

## FINDING A — `coverage: 324/324 = 100.0%` is `X/X`

`ffi-port-cost.py`:

```
line 418   uniq  = sorted(set([f.name for f in fns]))
line 496   denom = len({f.name for f in fns})        # the --pybind path
line 420   print(f"denominator   : {denom} symbols exported by the binary")
line 421   print(f"coverage      : {len(uniq)}/{denom} = ...")
```

`denom` **is** `uniq`. The line is labelled "symbols exported by the binary" and
**no binary is read on this path**. The guard at line 423
(`if len(uniq) > denom:` → *"the header and the binary disagree; do not trust
either count alone"*) is **unreachable** here, because `denom` is derived from
`uniq`.

**Plant A proves it.** Delete one declaration from a copy of `libclang.py`:

```
entry points  : 323   (was 324)
coverage      : 323/323   (was 324/324)
```

**Coverage stays at 100.0% with 323 of libclang's 324 declarations gone.** That
is a self-comparison reporting a coverage result — the brief's exact shape. (The
`--symbols` path at line 520 takes `denom` from an external file and is a real
comparison; the `--pybind` path is the one that produced the committed artifact.)

## FINDING B — the run contradicts itself about two thirds of the 307

```
mechanically derivable : 307
need a layout decision : 203     (CBYVAL or OPAQUE)
BLOCKED                : 17
```

`max_class` (lines 97–108) returns a **single** value and tests `blocked`
**first**, so no function can be both `BLOCKED` and `CBYVAL`/`OPAQUE`.
Therefore **all 203 layout-decision functions are inside the 307** —
**203/307 = 66%**. And the tool's own `CLASS_NOTE` table labels them:

```
CBYVAL : "struct by value -- N Term words, needs one layout convention"
STRUCT : "per-struct decision, not mechanical"
```

**So the same run prints "mechanically derivable: 307" and then, about 203 of
those 307, "needs a layout convention" / "not mechanical."** The word
*derivable* is not earned for those 203. A defensible restatement is
**"104/324 are mechanical outright; 203 need a per-struct layout decision; 17 are
blocked."**

## Reproduce

```
env -u PYTHONPATH LC_ALL=C .venv/bin/python .agents/slop/audit/ffi-port-cost-audit.py
```

Under a minute. Every plant is a copy in `$TMPDIR`; the live binding file and the
live tool are never written.