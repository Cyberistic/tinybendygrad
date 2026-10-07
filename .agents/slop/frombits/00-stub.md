# FROMBITS — `def F32.from_bits`

Unit: `.agents/slop/frombits/`. **Nothing committed.** Owns `tinybendygrad/base.bend` and
`tinybendygrad/dtype.bend` only. Compiler **Bend 2.0.34** via `./bin/bend`. Rule prefix
`FB-`.

Status: STUB. Reading next.

## JOB

`DTYPEB.md` measured 6 red laws in `dtype.bend` down to ONE missing primitive:
`def F32.from_bits(bits: U32) -> F32`. `F32.bits` exists (bitcast); `F32.from_bits` does
not; `U32.to_f32` is the NUMERIC conversion and is not a substitute.
