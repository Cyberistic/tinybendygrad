GATE NORM -- one normaliser, one declared width per row, both lanes
  Bend 2.0.34: check, run, build and publish Bend programs.
  v26.8.1
  helper            /Users/cyberistic/src/tries/2026-09-30-tinybendygrad/.agents/slop/norm/canon.py
  rows asked for    8

| row | width | CPython (dtype.py, CALLED) | node show / bits | cc show / bits | verdict |
|---|---|---|---|---|---|
| `f16_1p1` | f32 | f16(1.1): `1.099609375` = `f32:3f8cc000` | `1.0996094` / `1066188800` | `1.0996094` / `1066188800` | **AGREE** |
| `f32_1p0` | f32 | 1.0: `1.0` = `f32:3f800000` | `1` / `1065353216` | `1` / `1065353216` | **AGREE** |
| `f64_2m40` | f32 | 1.0 + 2**-40, in f64: `1.0000000000009095` = `f32:3f800000` | `1` / `1065353216` | `1` / `1065353216` | **AGREE** |
| `nan_p0` | f32 | the quiet NaN: no decimal -- it is a NaN = `f32:7fc00000` | `nan` / `2143289344` | `nan` / `2143289344` | **AGREE** |
| `nan_p1` | f32 | the SAME NaN plus payload 1: no decimal -- it is a NaN = `f32:7fc00001` | `nan` / `2143289345` | `nan` / `2143289345` | **AGREE** |
| `nan_neg` | f32 | the same, sign set: no decimal -- it is a NaN = `f32:ffc00001` | `nan` / `4290772993` | `nan` / `4290772993` | **AGREE** |
| `fp8to_nan` | f32 | fp8_to_float(0x7F, fp8e5m2): no decimal -- it is a NaN = `f32:7fc00000` | `nan` / `2143289344` | `nan` / `2143289344` | **AGREE** |
| `bf16_1p5` | f32 | bf16(1.5): `1.5` = `f32:3fc00000` | `1.5` / `1069547520` | `1.5` / `1069547520` | **AGREE** |

## THE WIDTH IS WHAT DECIDES, on a value both lanes got right
  `1.0 + 2**-40` at f64 -> f64:3ff0000000001000   (`0x3ff0000000001000`, `e2e.sh:215`)
  `1.0 + 2**-40` at f32 -> f32:3f800000 == `1.0`'s own f32:3f800000
  so the SAME value is a DISAGREEMENT at f64 and an AGREEMENT at f32, and a
  normaliser that hard-codes one width cannot tell the reader which it answered.

## THE PLANTS, so this gate is shown able to FAIL
  plant repr(float(s)) -- jslane2/gen_f32_seam.py's `norm`: a DISAGREEMENT on 2 of 4 comparable rows ['f16_1p1', 'f64_2m40']
  plant f"{v:g}"       -- dc-oracle.py:131, mm-dt-gate.py:60: a DISAGREEMENT on 0 of 4 comparable rows []
  excluded from every plant, because CPython's own answer for them is a NaN and has NO decimal: ['nan_p0', 'nan_p1', 'nan_neg', 'fp8to_nan']
  plant f"{v:g}" is wrong in a way NO lane/oracle row can see: ['1.0000001', '1.0000002', '1.0000003'] are 3 DISTINCT f32 values and it spells them ['1'] -- 1 spelling for 3 values
  `canon` on the same three: ['f32:3f800001', 'f32:3f800002', 'f32:3f800003'] -- 3 spellings

## THE VERDICTS, NEVER SUMMED
  AGREE       8 ['f16_1p1', 'f32_1p0', 'f64_2m40', 'nan_p0', 'nan_p1', 'nan_neg', 'fp8to_nan', 'bf16_1p5']
  DISAGREE    0 []
  LANE-LOSS   0 []
  ?ABSENT     0 []
  | `fp8to_nan`: `F32.show` said `nan`, which `canon` REFUSES as `f32:?nan` -- this row is only decidable because it read `bits`
  | `nan_neg`: `F32.show` said `nan`, which `canon` REFUSES as `f32:?nan` -- this row is only decidable because it read `bits`
  | `nan_p0`: `F32.show` said `nan`, which `canon` REFUSES as `f32:?nan` -- this row is only decidable because it read `bits`
  | `nan_p1`: `F32.show` said `nan`, which `canon` REFUSES as `f32:?nan` -- this row is only decidable because it read `bits`

## NaN PAYLOADS, MEASURED AGAINST `tinybendygrad/base.bend:42`
  base.bend says `F32.bits(F32.from_bits(p))` collapses EVERY NaN onto
  0x7FC00000 in the JS lane because `comp.ts:539` hands the float to
  JavaScript, whose `NaN` is one value.  THAT IS HALF TRUE, and the half
  that is false is the half that matters here: node reads `nan_p1` back as 2143289345 and cc as 2143289345, and 0x7FC00001 IS 2143289345.
  SO THE PAYLOAD SURVIVES THE TYPED-ARRAY PATH ON BOTH LANES.  What does not
  survive it is a NaN MANUFACTURED BY JAVASCRIPT ITSELF: `0/0` packs as
  0x7fc00000.  The claim that survives is narrower and is the one a gate may
  rely on: A NaN THAT CROSSED AS A PATTERN KEEPS ITS PAYLOAD; a NaN made by
  arithmetic does not, and nothing can tell them apart downstream.
  `base.bend` is not this unit's file -- REPORTED, not edited.
