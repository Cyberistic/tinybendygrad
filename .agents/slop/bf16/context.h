/* BF16-GATE CONTEXT -- the shim. Copied from the fp8fix precedent's shape,
 * MINIMALLY: bf16_run(Env, Term*, IoWork*) touches none of bend's types except
 * the three parameter types, so the whole list is those three plus stdint/math.
 *
 * STATED BLIND SPOT, same as fp8fix's context.h: this shim is MINE, not bend's,
 * so it does NOT exercise the effect ABI (`io_eff`, `ctr_take`, `io_tup`). What
 * it does exercise is `bf16_run`'s BODY, verbatim out of the live dtype.c --
 * that is the subject of this gate. */
#ifndef BF16_CONTEXT_H
#define BF16_CONTEXT_H

#include <stdint.h>
#include <string.h>
#include <math.h>

typedef uint32_t u32;
typedef uint64_t u64;
typedef float f32;
typedef intptr_t Term;
typedef struct Env Env;
typedef struct IoWork IoWork;
struct Env { int unused; };
struct IoWork { int unused; };

static inline u32 f32_rewrap(f32 v) { u32 b; memcpy(&b, &v, 4); return b; }

#endif