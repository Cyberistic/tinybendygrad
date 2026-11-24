/* fchain-harness.c -- RUN the four rendered kernels and check them against a reference.
 *
 * This is the first artifact in the tree that EXECUTES port-rendered C. It needs no device, no
 * Developer mode and no tinygrad: `cc` compiles the kernels' own text, and the reference below is
 * the layer semantics written out longhand from the C the renderer emitted.
 *
 * EACH STAGE IS CHECKED AGAINST BOTH CHAINS, and the two answers differ in what they can see:
 *   act  -- the stage's output from the ACTUAL previous stage (so a bad stage propagates)
 *   ref  -- the stage's output from the REFERENCE chain (so a bad stage is localised)
 * A stage that matches `ref` but not `act` was fed something wrong, not computed something wrong.
 */
#include <math.h>
#include <stdio.h>
#include "fchain-kernels.c"

#define NX 784
#define ND1 196
#define ND2 196
#define ND3 49
#define NOUT 10

static float x[NX], w1[4], w2[490];
static float a1[ND1], a2[ND2], a3[ND3], aout[NOUT];   /* actual chain   */
static float r1[ND1], r2[ND2], r3[ND3], rout[NOUT];   /* reference chain */
static float r1c[ND1], r2c[ND2], r3c[ND3], routc[NOUT]; /* the reference chain, kept whole for --dump */

static void seed(void) {
  for (int i = 0; i < NX; i++) x[i] = (float)((i * 37) % 97) / 97.0f - 0.5f;
  for (int i = 0; i < 4; i++) w1[i] = (float)(i + 1) / 4.0f;
  for (int i = 0; i < 490; i++) w2[i] = (float)((i * 13) % 61) / 61.0f - 0.4f;
}

static void ref_conv(const float *in, const float *w, float *out) {
  for (int oy = 0; oy < 14; oy++)
    for (int ox = 0; ox < 14; ox++) {
      float acc = 0;
      for (int ky = 0; ky < 2; ky++)
        for (int kx = 0; kx < 2; kx++) acc += in[(2 * oy + ky) * 28 + 2 * ox + kx] * w[ky * 2 + kx];
      out[oy * 14 + ox] = acc;
    }
}

static void ref_relu(const float *in, float *out) { for (int i = 0; i < ND1; i++) out[i] = in[i] > 0 ? in[i] : 0; }

static void ref_pool(const float *in, float *out) {
  for (int oy = 0; oy < 7; oy++)
    for (int ox = 0; ox < 7; ox++) {
      float m = -INFINITY;
      for (int ky = 0; ky < 2; ky++)
        for (int kx = 0; kx < 2; kx++) { float v = in[(2 * oy + ky) * 14 + 2 * ox + kx]; if (v > m) m = v; }
      out[oy * 7 + ox] = m;
    }
}

static void ref_linear(const float *in, const float *w, float *out) {
  for (int j = 0; j < NOUT; j++) { float acc = 0; for (int i = 0; i < ND3; i++) acc += in[i] * w[10 * i + j]; out[j] = acc; }
}

static double maxdiff(const float *a, const float *b, int n) {
  double m = 0;
  for (int i = 0; i < n; i++) { double d = fabs((double)a[i] - b[i]); if (d > m) m = d; }
  return m;
}

static int check(const char *name, const float *act, const float *ref, int n) {
  double d = maxdiff(act, ref, n);
  printf("%s: %s  max-abs-diff=%.3e\n", name, d < 1e-5 ? "OK" : "FAIL", d);
  return d < 1e-5;
}

/* `--dump`: the REFERENCE chain as RAW BIT PATTERNS, so a GPU can be compared word for word.
 * The seed and the four `ref_*` functions above are the oracle; this prints them and nothing else. */
static void dumpline(const char *nm, const float *a, int n) {
  printf("%s=", nm);
  for (int i = 0; i < n; i++) { unsigned u; __builtin_memcpy(&u, &a[i], 4); printf("%s%08x", i ? "," : "", u); }
  printf("\n");
}

int main(int argc, char **argv) {
  seed();

  k0(a1, x, w1);
  ref_conv(x, w1, r1);  for (int i = 0; i < ND1; i++) r1c[i] = r1[i];
  int ok = check("conv", a1, r1, ND1);

  k1(a2, a1);
  ref_relu(a1, r2);
  ref_relu(r1, r1);                     /* r1 becomes relu(conv) for the reference chain */
  ok &= check("relu(actual-input)", a2, r2, ND2);
  ok &= check("relu(reference-chain)", a2, r1, ND2);

  for (int i = 0; i < ND2; i++) r2c[i] = r2[i];
  k2(a3, a2);
  ref_pool(a2, r3);
  ok &= check("pool(actual-input)", a3, r3, ND3);
  ref_pool(r1, r2);                     /* r2 becomes pool(relu(conv)) for the reference chain */
  ok &= check("pool(reference-chain)", a3, r2, ND3);

  for (int i = 0; i < ND3; i++) r3c[i] = r3[i];
  k3(aout, a3, w2);
  ref_linear(a3, w2, rout);
  ok &= check("linear(actual-input)", aout, rout, NOUT);
  ref_linear(r2, w2, rout);
  ok &= check("linear(reference-chain)", aout, rout, NOUT);
  /* THE REFERENCE CHAIN'S OWN WORDS, kept before `--dump` can see them. `routc` was first written
   * AFTER the dump's early return -- so `--dump` printed an all-zero `out` while the checks above
   * were comparing two NON-zero buffers. A copy below the exit is not a copy. */
  for (int i = 0; i < NOUT; i++) routc[i] = rout[i];

  /* `--dump`: THE REFERENCE CHAIN AS RAW BIT PATTERNS, so a GPU can be compared word for word.
   * This is the SAME `ref_*` chain the verdict above used, printed instead of compared. */
  if (argc > 1 && argv[1][0] == '-' && argv[1][1] == '-') {
    dumpline("x", x, NX); dumpline("w1", w1, 4); dumpline("w2", w2, 490);
    /* BOTH CHAINS: `h1..out` are the REFERENCE chain (what the GPU must match), `a1..aout` are
     * what the C kernels produced -- two rows per stage, so "both are zero" cannot pass as agreement. */
    dumpline("h1", r1c, ND1); dumpline("h2", r2c, ND2); dumpline("h3", r3c, ND3);
    dumpline("out", routc, NOUT);
    dumpline("a1", a1, ND1); dumpline("a2", a2, ND2); dumpline("a3", a3, ND3); dumpline("aout", aout, NOUT);
    return 0;
  }
  printf("VERDICT: %s\n", ok ? "ALL FOUR KERNELS AGREE" : "A KERNEL DISAGREES");
  return ok ? 0 : 1;
}
