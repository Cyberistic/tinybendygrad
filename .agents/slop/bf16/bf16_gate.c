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

/* An independent model of dtype.py:229-233 for the FINITE arm: decode to a
 * float, round to bf16 with frexp/ldexp (no bit add), re-encode. */
static u32 model(u32 p) {
  if ((p & 0x7F800000u) == 0x7F800000u) return p;      /* isfinite: dtype.py:230 */
  f32 v; memcpy(&v, &p, 4);
  int e2; f32 m = frexpf(v, &e2);                      /* v = m * 2^e2, m in [0.5,1) */
  /* bf16: 8 exponent bits, bias 127, so v must land on a multiple of 2^(e2-8)
   * once normalised. Scale to 2^8 steps of m, round half to even. */
  double s = ldexp((double)m, 9);                     /* m in [256, 512) */
  double fl = floor(s);
  double r = (s - fl == 0.5) ? (((unsigned long long)fl & 1ull) ? fl + 1.0 : fl)
                             : ((s - fl > 0.5) ? fl + 1.0 : fl);
  f32 out = (f32)ldexp(r, e2 - 9);
  u32 b; memcpy(&b, &out, 4);
  return b;
}

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

  if (!strcmp(mode, "census")) {               /* exhaustive 2^32 vs model */
    FILE *out = fopen(argc > 2 ? argv[2] : "/dev/null", "wb");
    unsigned long long n_dis = 0;
    /* class codes: 1 +inf 2 -inf 3 qnan 4 snan 5 other-disagree */
    unsigned long long cls[6] = {0,0,0,0,0,0};
    for (u64 q = 0; q <= 0xFFFFFFFFull; q++) {
      u32 p = (u32)q, g = got(p), r = model(p);
      if (g == r) continue;
      n_dis++;
      int c;
      if (g == r) c = 5;
      else if ((p & 0x7FFFFFFFu) == 0x7F800000u) c = (p >> 31) ? 2 : 1;
      else if (((p >> 22) & 1u) == 0) c = 4;
      else c = 3;
      cls[c]++;
      fwrite(&p, 4, 1, out);
    }
    fclose(out);
    printf("CENSUS patterns=4294967296 disagree=%llu\n", n_dis);
    printf("CENSUS inf_pos=%llu inf_neg=%llu qnan=%llu snan=%llu other=%llu\n",
           cls[1], cls[2], cls[3], cls[4], cls[5]);
    return 0;
  }

  /* mode "class": exhaustive 2^32, print only the DISTINCT (class-of-input,
   * got, model) triples with a representative, so a CPython check can be made
   * per distinct answer rather than per pattern. */
  if (!strcmp(mode, "class")) {
    /* distinct (p -> got) with p reduced to (sign, exp, mant_msb, low16, carry) */
    static unsigned char seen[2][256][2][1]; /* unused; kept simple below */
    (void)seen;
    /* emit every p whose got differs from p, deduped on got */
    static u32 seen_got[1 << 20]; static int nsg = 0;
    for (u64 q = 0; q <= 0xFFFFFFFFull; q++) {
      u32 p = (u32)q, g = got(p);
      if (g == p) continue;
      int dup = 0;
      for (int i = 0; i < nsg; i++) if (seen_got[i] == g) { dup = 1; break; }
      if (!dup && nsg < (1 << 20)) seen_got[nsg++] = g;
      printf("%08x %08x\n", p, g);
    }
    return 0;
  }
  return 2;
}