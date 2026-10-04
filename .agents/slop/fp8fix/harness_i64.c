/* FX-4 -- the i64 driver. Compiles the LIVE tinybendygrad/runtime/dtype.c against
 * context.h and calls dtype.c's OWN `div64_*_run` functions, so the arithmetic and
 * all four written zero branches are exercised as written.
 *
 * STATED BLIND SPOT (context.h): the tuple shim is mine, so this does NOT test the
 * tuple ABI. It tests the ARITHMETIC.
 *
 * Protocol: one request per line on stdin, one `name=value` row per line on stdout.
 *   I <defidx> <a> <b>   defidx 0..5 -> trunc, floor_div, floor_mod, cdiv, cmod, ceildiv
 * The answer is the 64-bit result as `hi:lo` in hex.
 *
 * THE CALLING CONVENTION, MEASURED (this harness SIGBUSed twice finding it, and the
 * second SIGBUS is why it is written down): `i64_of(e, t)` OPENS `t` THROUGH
 * `ctr_take`, so every i64 argument is a TUPLE HANDLE and a two-argument def's frame
 * is `{handle(a), handle(b)}` -- dtype.c:220 reads `f[0]` and `f[1]` as two handles,
 * not as the halves of one. That is NOT the fp8 convention two screens up:
 * `fp8_from_run` (dtype.c:165) casts `f[0]` straight to u32. Two conventions, one
 * file, and the difference is invisible until something is handed the wrong shape.
 */
#include <stdio.h>
#include "context.h"

/* dtype.c is #included ABOVE this file by the generated <tree>/unit_i64.c, in one
 * translation unit, because dtype.c's functions are `static`. */

static const char *NAMES[6] = {"trunc", "floor_div", "floor_mod", "cdiv", "cmod", "ceildiv"};

int main(void) {
  Env env;
  IoWork work;
  int idx;
  long long a, b;
  while (scanf(" I %d %lld %lld", &idx, &a, &b) == 3) {
    Term frame[2];
    Term r;
    frame[0] = io_tup(env, (Term)(u32)((u64)a >> 32), (Term)(u32)(u64)a);
    frame[1] = io_tup(env, (Term)(u32)((u64)b >> 32), (Term)(u32)(u64)b);
    r = (idx == 0 ? i64_run : idx == 1 ? div64_floor_run : idx == 2 ? div64_mod_run :
         idx == 3 ? div64_cdiv_run  : idx == 4 ? div64_cmod_run :
                   div64_ceildiv_run)(env, frame, &work);
    Term out[2];
    ctr_take(env, r, 2, out);
    printf("%s[%lld,%lld]=%08x:%08x\n", NAMES[idx], a, b,
           (unsigned)(u32)out[0], (unsigned)(u32)out[1]);
  }
  return 0;
}