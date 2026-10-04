#include <stdlib.h>
static u32 popcount_shim(u32 x) { u32 n = 0; while (x) { n += x & 1u; x >>= 1; } return n; }
Term a_run(Env e, Term* f, IoWork* w) { return popcount_shim((u32)f[0]); }
Term b_run(Env e, Term* f, IoWork* w) { return (u32)__builtin_popcountll((u32)f[0]) * 10u; }
Term c_run(Env e, Term* f, IoWork* w) { return (u32)sizeof(long); }
static void __attribute__((constructor)) shim5_use(void) {
  io_eff(CID(a), a_run, 0);
  io_eff(CID(b), b_run, 0);
  io_eff(CID(c), c_run, 0);
}
