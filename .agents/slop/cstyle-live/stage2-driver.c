/* stage2-driver.c -- the host program that CALLS the kernel `cstyle.bend` emitted.
 *
 * It is generated as a SEPARATE translation unit and the emitted text is `#include`d, so
 * the kernel text is compiled exactly as a compiler sees it, byte for byte, with nothing
 * added to it and nothing removed from it. `#include` rather than paste, because paste
 * would let an edit of the emitted file silently become a driver edit.
 *
 * INPUT AND OUTPUT ARE RAW BYTES IN FILES, not `printf("%g")`. Two reasons:
 *   - a decimal print rounds, so two rounded strings can agree while the bits differ;
 *   - endianness then cannot silently matter, because neither side is interpreted.
 *
 * `out` is PRE-FILLED with a sentinel no lane of `in + 1.0f` can produce, so a kernel that
 * wrote nothing leaves a file that is visibly NOT the answer rather than a zero-filled
 * file that reads as agreement with a zero oracle.
 */
#include <stdio.h>

#include "live_clang_full.c" /* the port's own emitted text, verbatim */

int main(int argc, char **argv) {
  if (argc != 3) { fprintf(stderr, "usage: %s in.bin out.bin\n", argv[0]); return 2; }
  float in[4], out[4];
  FILE *f = fopen(argv[1], "rb");
  if (!f) { perror(argv[1]); return 3; }
  if (fread(in, sizeof(float), 4, f) != 4) { fprintf(stderr, "short input\n"); return 3; }
  fclose(f);
  for (int i = 0; i < 4; i++) out[i] = -12345.0f;
  E_4(out, in);
  if (!(f = fopen(argv[2], "wb"))) { perror(argv[2]); return 4; }
  if (fwrite(out, sizeof(float), 4, f) != 4) { fprintf(stderr, "short write\n"); return 4; }
  return fclose(f) ? 5 : 0;
}