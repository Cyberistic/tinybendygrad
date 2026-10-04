/* FX-3 -- THE CONTEXT, DECLARED BY ME, AND THE DEFICIT MEASURED NOT ASSUMED.
 *
 * WHY NOT bend's generated C. substrate-check.sh:134 builds its `cc` context from
 * `bend -o .agents/slop/guardfix/probe-c.bend`, and that route is CURRENTLY DEAD:
 *     ./bin/bend .agents/slop/guardfix/probe-c.bend -o gen.c  ->  rc 1, no emit
 *     expected : Nat / observed : U32 / Location: fp16_f32.norm / dtype.bend:687
 * `dtype.bend` is another unit's LIVE file, so the probe is red through no fault of
 * mine and substrate-check.sh prints NO INSTRUMENT for every `.c` file. Reported, not
 * worked around by editing their file.
 *
 * WHAT THIS FILE SUPPLIES, and it is SMALLER than the 190-error deficit
 * substrate-check.sh:97 measures for `cc -fsyntax-only dtype.c` alone, because this
 * instrument calls the two PURE halves and never the effect table:
 *
 *   fp8 lane   fp8_encode (dtype.c:47) is pure u32 arithmetic on an f32 pattern -- it
 *              touches no bend type at all. fp8_decode (dtype.c:90) needs f32,
 *              f32_rewrap and ldexpf. THE FIVE DEFINITIONS BELOW ARE THE WHOLE LIST.
 *   i64 lane   the four divmod run functions need Term/Env/IoWork/ctr_take/io_tup,
 *              and the pair shim below is MINE, NOT bend's. STATED BLIND SPOT: this
 *              instrument therefore does NOT test the tuple ABI -- DTYPE-ABI.md is
 *              where that lives, and the `dtype.c:205` ABI bug DTYPEB.md:143-145
 *              records was an ABI bug, not an arithmetic one. What it tests is that
 *              the ARITHMETIC of floor_div_mod/cdiv_of and the four written zero
 *              branches agree with CPython.
 */
#ifndef FP8FIX_CONTEXT_H
#define FP8FIX_CONTEXT_H

#include <stdint.h>
#include <string.h>
#include <math.h>

/* bend's generated C declares these; the two pure halves need no more. */
typedef uint32_t u32;
typedef uint64_t u64;
typedef float f32;
typedef intptr_t Term;
typedef struct Env Env;
typedef struct IoWork IoWork;
struct Env { int unused; };
struct IoWork { int unused; };

static inline u32 f32_rewrap(f32 v) { u32 b; memcpy(&b, &v, 4); return b; }

/* --- i64 lane only: the tuple shim. Two terms out, one Term in.
 * MEASURED, NOT GUESSED: `ctr_take` and `io_tup` take `Env` BY VALUE -- the first
 * build of this shim took `Env *` and cc said so by name. */
typedef struct { Term hi, lo; } FxPair;
static FxPair fx_pairs[4096];   /* MEASURED, NOT GUESSED: 102 i64 requests x 3 tuples
                                 * each = 306. The first cut had 64 and overflowed
                                 * silently at request 24 -- which is `I 3 m7_m4`, so
                                 * it invented a MISMATCH in a row that is correct. */
static int fx_np;
static Term io_tup(Env e, Term a, Term b) {
  if (fx_np < 4096) { fx_pairs[fx_np].hi = a; fx_pairs[fx_np].lo = b; }
  return (Term)(intptr_t)(++fx_np);
}
static void ctr_take(Env e, Term t, int n, Term *out) {
  FxPair *p = &fx_pairs[(intptr_t)t - 1];
  out[0] = p->hi; out[1] = p->lo;
}

#endif