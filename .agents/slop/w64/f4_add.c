#include <stdint.h>
#include <string.h>

// W-4: one IEEE-754 binary64 add.
//
// WHY THE OPERANDS ARE TWO U32 AND NOT ONE 64-BIT WORD: `bend base --types`
// ships Nat/U32/F32 and no I64/U64/F64, and Nat tops out at 2^48-1 (W-1/W-2),
// so a Nat cannot carry a 64-bit pattern. Two U32 is the only split that stays
// inside what the port can already move. NO `double` crosses the boundary: the
// double exists only inside this function, reassembled from the two halves and
// written back out as two halves. So the libclang `double` blockage does not
// apply here, and this probe is what says whether that is true.
//
// THE RESULT LOW WORD goes into a global and is read by a SECOND foreign def,
// because a Bend Nat is linear -- one value cannot serve two calls -- so the
// pair cannot be returned as two values without knowing that marshalling path.

static uint64_t g_f64_lo = 0;

Term f64_add_run(Env e, Term *f, IoWork *w) {
  uint64_t a = ((uint64_t)(uint32_t)f[0] << 32) | (uint32_t)f[1];
  uint64_t b = ((uint64_t)(uint32_t)f[2] << 32) | (uint32_t)f[3];
  double x, y, z;
  uint64_t r;
  memcpy(&x, &a, 8);
  memcpy(&y, &b, 8);
  z = x + y;
  memcpy(&r, &z, 8);
  g_f64_lo = r & 0xffffffffu;
  return (Term)(u32)(uint32_t)(r >> 32);
}

Term f64_add_lo_run(Env e, Term *f, IoWork *w) {
  return (Term)(u32)(uint32_t)g_f64_lo;
}

static void __attribute__((constructor)) w4_use(void) {
  io_eff(CID(f64_add), f64_add_run, 0);
  io_eff(CID(f64_add_lo), f64_add_lo_run, 0);
}