/* FX-2 -- the fp8 driver. Linked against bend's generated C context (build.py), so
 * `fp8_encode` and `fp8_decode` here are THE ONES IN tinybendygrad/runtime/dtype.c,
 * static and therefore visible in this translation unit.
 *
 * Protocol, one request per line on stdin, one `name=value` row per line on stdout:
 *   F <pattern> <kind>   fp8_encode(pattern, kind)   -- float_to_fp8 on an f32 pattern
 *   D <kind> <code>      fp8_decode(code, kind)      -- fp8_to_float
 * Rows are whole lines and the differ compares WHOLE LINES, never row names.
 */
#include <stdio.h>
#include "context.h"

/* dtype.c is #included ABOVE this file by the generated <tree>/unit_fp8.c, in one
 * translation unit, because `fp8_encode`/`fp8_decode` are `static`. */
int main(void) {
  char tag;
  unsigned long long a, b;
  while (scanf(" %c %llu %llu", &tag, &a, &b) == 3) {
    if (tag == 'F')       /* float_to_fp8: F <pattern> <kind> -> F[kind][pattern] */
      printf("F[%llu][%llu]=%u\n", b, a, (unsigned)fp8_encode((u32)a, (u32)b));
    else if (tag == 'D')  /* fp8_to_float:  D <kind> <code>    -> D[kind][code]    */
      printf("D[%llu][%llu]=%08x\n", a, b, (unsigned)fp8_decode((u32)b, (u32)a));
  }
  return 0;
}