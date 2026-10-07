# EXPECTATIONS — written BEFORE running. Corrections recorded at the bottom.

Reproduce with: `zsh .agents/slop/ffi-experiment/run-all.sh [DANGLING: this instrument was DELETED by the 2026-10-05 prune and is not in git]`  (8/8 PASS)

## WHAT I EXPECTED FIRST, AND WHAT ACTUALLY HAPPENED

### E1 — libc `strlen`, C-local string
Expected `SLEN 14`. **Got `SLEN 13`.** My hand-count was wrong: `tiny`+`bendy`+
`grad` = 4+5+4 = 13. Verified three ways before accepting it: `len()` = 13,
`wc -c` = 13, and a standalone C program calling `strlen` = 13. The code was
right; the expectation was the bug.

### E3 — libc `getenv` out, Bend `String` in
Expected `ENV BARBAZ` (assumed `getenv` returns the value directly).
**Got `ENV barbaz`.** Assumption wrong, mechanism right: `getenv` returns the
value, I had reasoned about uppercase for no reason. `MARSHAL 13` — I wrote "9"
in the expectation, which was simply not a count of anything.

### E4 — libclang
Expected output containing `clang version`. **Got
`Apple clang version 17.0.0 (clang-1700.6.3.2)`.** Correct.
BUT the first run **FAILED AT STEP 4**, not step 3: `bend -o` ok, `cc` ok, LINK
ok, run died with dyld error 134 (`@rpath/libclang.dylib`, no LC_RPATH). I had
predicted a clean run. The link was never the problem.

### E5 — three laws, one shim.c
Expected `19` (1 + 10 + 8). **Got `19`.** Correct. First attempt FAILED AT STEP 1
because I wrote `IO.print(a(1) + b(2) + c(3))`; foreign `IO` calls must be bound
one at a time with `<-`. Not an FFI limit.

### E6/E8 — Metal
Expected a non-zero handle and a live command queue. **Got both**, and
`BUFFER_LENGTH 1024` exactly.
Two step-1 failures first: Bend has no `if/then/else` expression, and a `match`
cannot appear inside a `do IO<...>` block.

## WHERE THE REAL LIMITS ARE (none of them are the FFI)

1. **`Env` by value, not `Env*`.** Cost me two compile errors before noticing.
2. **No `U64`, `I64`, `I32`, `U8`, or `F64`.** Available: `U32 F32 Nat Bool String`.
3. **`Nat` works to 2^51-1 and aborts at 2^52-1**, while its own error message
   says `2^48-1`. Measured by sweeping 32..63 bits, not read off the message.
4. **A Bend `String` is a cons list of code points**, not a `char*`. Sealed cells
   need `ctr_take` + `spare_free`.
5. **`==` is only the type.** Equality is `T.is_eq(a, b)`. Fails for `Nat` AND `U32`.
6. **`match` may only scrutinise a parameter or a field** — not a computed value,
   not a local binder, not inside a `do` block. Every conditional is a helper.
7. **Foreign values are linear**: `(consumed more than once)`.
8. **Apple's libclang has an `@rpath` install name** — needs `-Wl,-rpath`.
9. **ObjC frameworks need `cc -x objective-c`**; the error appears inside
   `Foundation.h` and reads like a corrupt SDK header.

## THINGS I GOT WRONG THAT THE TOOL CAUGHT

- First run of `ffi-port-cost.py` on real libclang signatures reported
  **324/324 SCALAR** — entirely false. `CXString` and `CXCursor` are structs and
  the classifier fell through to a default integer. Fixed by making the default
  arm OPAQUE.
- Overcorrecting then reported **324/324 BLOCKED** — also false. Resolving
  `TypeAlias` lines and `SIZE` from the binding file gives the true answer:
  **307/324 derivable, 17 blocked** (all by int64/uint64/double).
- `grep -c '^MTL_EXPORT'` = 153 is NOT Metal's C surface. `MTL_EXPORT` is the
  availability macro; the declaration macro is `MTL_EXTERN`, and the real answer
  is **8**.
- The first version of `run-all.sh` asserted `BEND_NAT 4307773504`. That address
  is ASLR-dependent and changed every run. The correct assertion compares C's
  reading to Bend's reading **of the same process**, never either to a constant.

## DENOMINATORS
- libclang: **552** exported `clang_*` symbols in Apple's dylib (nm, measured).
  **324** carry exact signatures in tinygrad's own binding.
  (`support/autogen.py` references 47 — closest to the "46" I was handed.)
- Metal: 96 headers, **8** C functions, **80** protocols, **788** methods,
  **1424** properties.