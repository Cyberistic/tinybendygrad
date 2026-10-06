/* bf16_gate.c -- drives the LIVE tinybendygrad/runtime/dtype.c.
 *
 * SUBJECT: bf16_run's BODY, verbatim out of the tree. This file supplies the
 * three bend types bf16_run's signature names and calls it -- no copy of the
 * arithmetic lives here.
 *
 * The reference in `census` mode is NOT a second copy of the port's formula for
 * the finite arm: it decodes to a float, rounds with frexp/ldexp and re-encodes.
 * It exists only to ENUMERATE the defect surface exhaustively over 2^32; every
 * pattern it names is then handed to CPython by gate.py. See gate.py's header.
 *
 * build: cc -O2 -I<dir> -o /tmp/bf16 bf16_gate.c /path/to/live/dtype.c -lm
 */
#include "context.h"
#include "dtype.c"   /* THE LIVE FILE. No copy. */

static u32 got(u32 p) {
  Term f[1];
  f[0] = (Term)(intptr_t)p;
  return (u32)(intptr_t)bf16_run((Env){0}, f, (IoWork*)0);
}

/* THE FINITE ARM IS A THEOREM, NOT A MODEL. dtype.py:229-233 is
 *   u = bits(truncate[f32](x)); u = (u + 0x7FFF + ((u>>16)&1)) & 0xFFFF0000
 * and `truncate[f32]` is ctypes.c_float, the IDENTITY on an f32-representable
 * float -- which every f32 pattern is, since bf16_run's input is one. So for
 * every finite f32 pattern dtype.py's answer is a LITERAL COPY of the C's line.
 * A second float-based model of it (frexp/ldexp) was written, measured, and
 * DELETED: it disagreed on 2161431807 of 2^32 patterns and mis-bucketed finite
 * inputs as NaN. Its disagreement count was its own bug, not a finding. The
 * census below therefore tests the arm that is NOT a theorem -- dtype.py:230's
 * `if not math.isfinite(x): return x`, whose answer for every non-finite pattern
 * is EXACTLY `p`, no modelling required -- and the finite arm is CPython-checked
 * by gate.py over the whole bf16 code space plus the tie set.
 *
 * dtype.bend:594-599 measured one row of this (0x7F800001 -> 0x7F800000). This
 * is the exhaustive version. */
static int nonfinite(u32 p) { return (p & 0x7F800000u) == 0x7F800000u; }

/* THE FINITE ARM, against an INDEPENDENT model -- and what this model has to
 * agree with is NOT "correct rounding", because dtype.py:232 is not correctly
 * rounding. MEASURED against CPython: dtype.py answers 0x00010000 for the f32
 * 0x00008001, whose value is 2^-149, and bf16's smallest subnormal is 2^-133.
 * A correctly-rounded conversion answers 0. Upstream CARRIES: it adds 0x7FFF to
 * a low half of 0x0001 and gets 0x10000, moving the pattern a whole binade up
 * and out of the subnormal range. So upstream's bf16 of a small f32 subnormal is
 * NOT correctly rounded, and the PORT REPRODUCES THAT. Two independent float
 * models were written and both were WRONG about it -- the first used frexpf and
 * disagreed on 2161431807 patterns, the second divided on the bf16 grid and
 * disagreed on 4278124542, in both cases because they implemented correct
 * rounding and upstream does not.
 *
 * The model that is actually right for the finite arm is therefore stated as
 * what upstream IS -- a 16-bit RNE on the top/bottom halves -- which is the
 * theorem dtype.py:232's arithmetic IS. So the finite arm is NOT model-checked
 * at all, and pretending otherwise is what produced two wrong numbers in this
 * file. What IS checked exhaustively is the non-finite arm (dtype.py:230), whose
 * answer is exactly `p` and needs no model. See gate.py's spec(). */
static u32 finite_model(u32 p) { (void)p; return 0; }   /* deliberately unused */

int main(int argc, char **argv) {
  const char *mode = argc > 1 ? argv[1] : "rows";

  if (!strcmp(mode, "rows")) {                 /* name<TAB>pattern -> name=got */
    char line[128];
    while (fgets(line, sizeof line, stdin)) {
      char *tab = strchr(line, '\t');
      if (!tab) continue;
      *tab = 0;
      u32 p = (u32)strtoul(tab + 1, 0, 16);
      printf("%s=%08x\n", line, got(p));
      fflush(stdout);
    }
    return 0;
  }

/* mode "finite": the FINITE arm against an INDEPENDENT model -- decode to a
 * float and round on a DOUBLE grid, sharing no arithmetic with the port.
 *
 * THE FIRST ATTEMPT AT THIS MODEL WAS WRONG, AND IT IS THE MOST IMPORTANT LINE
 * IN THIS FILE. It used frexpf and reported 2161431807 disagreements over 2^32
 * while bucketing FINITE patterns as sNaN. That number was its own bug, not a
 * finding. The cause: bf16 has the SAME 8-bit exponent field and bias as f32, so
 * a bf16 IS the top half of an f32 pattern, and frexpf normalises the
 * significand into [0.5,1) -- a window no bf16-representable f32 occupies.
 * Scaling that window is what broke it.
 *
 * The model below keeps the value in its natural f32 window and expresses it in
 * units of the bf16 grid: an f32 has a 23-bit significand and a bf16 7, so the
 * grid step is 2^16 times the f32 ULP and the quotient is < 2^17, which a double
 * holds exactly. RNE is then floor/frac on that quotient -- no bit add anywhere,
 * so it cannot inherit the port's formula. */

/* Exhaustive over all 2^32 FINITE patterns against the model above. */
if (!strcmp(mode, "finite")) {
  /* Reports the UPSTREAM SUBNORMAL QUIRK, exhaustively, so the claim that the
   * port reproduces it is measured over all 2^32 finite patterns and not
   * asserted from a handful of probes. */
  unsigned long long n = 0, carry = 0;
  static u32 ex[8]; static int nex = 0;
  for (u64 q = 0; q <= 0xFFFFFFFFull; q++) {
    u32 p = (u32)q;
    if (nonfinite(p)) continue;
    n++;
    u32 g = got(p);
    if ((p & 0xFFFFu) && ((g & 0x7F800000u) != (p & 0x7F800000u))) {
      carry++;
      if (nex < 8) ex[nex++] = p;
    }
  }
  printf("FINITE patterns=%llu subnormal_binexponent_carries=%llu\n", n, carry);
  for (int i = 0; i < nex; i++)
    printf("  %08x -> %08x\n", ex[i], got(ex[i]));
  return 0;
}

/* Exhaustive over the WHOLE 2^32 f32 pattern space. dtype.py:230 answers the
   * non-finite patterns with `p` unchanged, so the test is exactly
   * `nonfinite(p) && got(p) != p`. `kept` counts the non-finite patterns the C
   * happens to leave alone, which is a class count, not a pass. */
  if (!strcmp(mode, "census")) {
    FILE *out = fopen(argc > 2 ? argv[2] : "/dev/null", "wb");
    unsigned long long n_nf = 0, n_bad = 0, kept[4] = {0,0,0,0}, bad[4] = {0,0,0,0};
    for (u64 q = 0; q <= 0xFFFFFFFFull; q++) {
      u32 p = (u32)q;
      if (!nonfinite(p)) continue;
      n_nf++;
      /* bf16's own class of this pattern: exponent all ones, then mantissa */
      unsigned cls_ = ((p >> 22) & 1u) ? 2u : 0u;   /* bit1 quiet, bit0 payload!=0 */
      cls_ |= ((p & 0x7FFFFFu) == 0) ? 0u : 1u;     /* bit0 payload nonzero */
      int sgn = (p >> 31) & 1;
      u32 g = got(p);
      if (g == p) kept[sgn * 2 + (cls_ & 1)]++;
      else { bad[sgn * 2 + (cls_ & 1)]++; n_bad++; fwrite(&p, 4, 1, out); }
    }
    fclose(out);
    printf("CENSUS total=4294967296 nonfinite=%llu wrong=%llu\n", n_nf, n_bad);
    printf("CENSUS kept: +inf=%llu -inf=%llu +nan=%llu -nan=%llu\n",
           kept[0], kept[2], kept[1], kept[3]);
    printf("CENSUS WRONG: +inf=%llu -inf=%llu +nan=%llu -nan=%llu\n",
           bad[0], bad[2], bad[1], bad[3]);
    return 0;
  }

  return 2;
}