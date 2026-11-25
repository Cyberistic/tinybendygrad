/* tstep-ref.c -- THE FORWARD HALF OF THE TRAINING STEP, WRITTEN LONGLAND IN C.
 *
 * This file exists to be a SECOND, INDEPENDENT WITNESS for `.agents/slop/browser/tstep-want.rows`.
 * The oracle there is CPython tinygrad building the same graph the fixture builds; the functions
 * below are the layer semantics written out by hand from the C the renderer emits, exactly as
 * `fchain-harness.c` writes them -- neither derived from the fixture nor from tinygrad. If the two
 * agree on `out` and `loss`, the oracle's FORWARD is pinned by two chains that share no code.
 *
 * The seed is `fchain-harness.c`'s `seed()`, and the target is the rule row 82 records:
 *   t[i] = ((i*11) % 43)/43 - 0.5
 */
#include <math.h>
#include <stdio.h>

#define NX 784
#define NW1 4
#define NW2 490
#define ND1 196
#define ND2 196
#define ND3 49
#define NOUT 10

static float x[NX], w1[NW1], w2[NW2], t[NOUT];
static float a1[ND1], a2[ND2], a3[ND3], out[NOUT];

static void seed(void) {
  for (int i = 0; i < NX; i++) x[i] = (float)((i * 37) % 97) / 97.0f - 0.5f;
  for (int i = 0; i < NW1; i++) w1[i] = (float)(i + 1) / 4.0f;
  for (int i = 0; i < NW2; i++) w2[i] = (float)((i * 13) % 61) / 61.0f - 0.4f;
  for (int i = 0; i < NOUT; i++) t[i] = (float)((i * 11) % 43) / 43.0f - 0.5f;
}

static void ref_conv(const float *in, const float *w, float *o) {
  for (int oy = 0; oy < 14; oy++)
    for (int ox = 0; ox < 14; ox++) {
      float acc = 0;
      for (int ky = 0; ky < 2; ky++)
        for (int kx = 0; kx < 2; kx++) acc += in[(2 * oy + ky) * 28 + 2 * ox + kx] * w[ky * 2 + kx];
      o[oy * 14 + ox] = acc;
    }
}

static void ref_relu(const float *in, float *o) { for (int i = 0; i < ND1; i++) o[i] = in[i] > 0 ? in[i] : 0; }

static void ref_pool(const float *in, float *o) {
  for (int oy = 0; oy < 7; oy++)
    for (int ox = 0; ox < 7; ox++) {
      float m = -INFINITY;
      for (int ky = 0; ky < 2; ky++)
        for (int kx = 0; kx < 2; kx++) { float v = in[(2 * oy + ky) * 14 + 2 * ox + kx]; if (v > m) m = v; }
      o[oy * 7 + ox] = m;
    }
}

static void ref_linear(const float *in, const float *w, float *o) {
  for (int j = 0; j < NOUT; j++) { float acc = 0; for (int i = 0; i < ND3; i++) acc += in[i] * w[10 * i + j]; o[j] = acc; }
}

static unsigned bits(float v) { unsigned u; __builtin_memcpy(&u, &v, 4); return u; }

int main(void) {
  seed();
  ref_conv(x, w1, a1);
  ref_relu(a1, a2);
  ref_pool(a2, a3);
  ref_linear(a3, w2, out);
  float loss = 0;
  for (int i = 0; i < NOUT; i++) { float d = out[i] - t[i]; loss += d * d; }
  for (int i = 0; i < NOUT; i++) printf("out_%d=%.9g\n", i, out[i]);
  printf("loss=%.9g\n", loss);
  printf("bits_out=");
  for (int i = 0; i < NOUT; i++) printf("%s%08x", i ? "," : "", bits(out[i]));
  printf("\nbits_loss=%08x\n", bits(loss));
  return 0;
}
