# SPELLING unit — which of the three 64-bit spellings is canonical

The report is **`.agents/slop/SPELLING.md`**. This file is the reproduction recipe
and the harness inventory. Prefix **`S-`**. Nothing committed.

## Reproduce

```sh
# the ruling, and the generator/product byte-for-byte proof, with 5 controls
python3 .agents/slop/clangshim/apply-port-lane.py --check      # IN SYNC
python3 .agents/slop/spelling/roundtrip.py --plants

# the JS-lane measurement: what shape does H.I64 cross as?
# `bend -o` inlines an imported `.js` verbatim into ONE CJS scope, so the probe must
# be written in dtype.js's dialect and must live at a path the scratch `.bend` can name.
R=$PWD; W=$TMPDIR/s-jslane; rm -rf "$W"; mkdir -p "$W/.agents/slop/spelling" "$W/tinybendygrad"
cp tinybendygrad/helpers.bend "$W/tinybendygrad/"
cp .agents/slop/spelling/jslane-probe.js "$W/.agents/slop/spelling/"
cat > "$W/probe.bend" <<'EOF'
import Base
import ./tinybendygrad/helpers.bend as H

# The DISCRIMINATOR, and it needs no oracle: `Dt.i64_trunc` is the identity, so the
# reading that returns the bytes it was handed is the correct one.
def Probe(a: H.I64) -> IO(U32):
  import "./.agents/slop/spelling/jslane-probe.js"

def main() -> IO(Unit):
  do IO<Unit>:
    a0 : U32 <- Probe(H.i64_of_hi_lo(0, 1))
    IO.print("FIX 0:1      shipped_hi=" ++ U32.show(a0))
    a1 : U32 <- Probe(H.i64_of_hi_lo(7, 9))
    IO.print("FIX 7:9      shipped_hi=" ++ U32.show(a1))
    a2 : U32 <- Probe(H.i64_of_hi_lo(4294967295, 2147483648))
    IO.print("FIX int64min shipped_hi=" ++ U32.show(a2))
    a3 : U32 <- Probe(H.i64_of_hi_lo(4294967295, 4294967295))
    IO.print("FIX -1:uint  shipped_hi=" ++ U32.show(a3))
EOF
cd "$W" && "$R/bin/bend" probe.bend -o probe.js && node probe.js
```

## Inventory

| file | what it is |
|---|---|
| `roundtrip.py` | emitter → `apply-port-lane.fix` → product, compared by md5. 5 controls. `--plants` for the mutations. |
| `jslane-probe.js` | ONE question: what shape does `H.I64` cross the JS boundary as. Written in CJS-on-purpose; the emitted scope is one CJS scope and an ESM `import` is a `SyntaxError` that stops the probe. |
| `scratch.sh` | a `$TMPDIR` tree in which `libclang.bend`'s relative import resolves (needs `tinybendygrad/` **and** `.agents/slop/clangshim/`). |
| `NOTES.md` | this file. |

## Two of this unit's own controls moved, and neither was a failed disarm

Both are in `SPELLING.md` §6 and in `notes/bend2-constraints.md` at `S-10`: one
disarm **removed** the fix instead of re-expressing it, and one plant **added** the
call instead of **moving** it, so it proved nothing and reported FAIL. A control that
proves nothing reports FAIL and PASS identically.

## Rules for this unit

- Generator layer (`apply-port-lane.py`) and `.agents/slop/spelling/*` are mine.
- The live tree is read-only here **except** the one file whose generator I own, and
  that write went through the generator: `apply-port-lane.py` → product, `--check` `IN SYNC`.
- `runtime/dtype.js`, `runtime/dtype.c`, `helpers.bend`, `clangshim-gen.py` and
  `libclang-ffi.c` are other units'. **Verified byte-unchanged** (`git status --porcelain`).