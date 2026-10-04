// E8: the decisive Nat round-trip, INSIDE ONE PROCESS so ASLR cannot
// confound it. The shim prints the driver handle to stderr in C and returns
// the same value as a Bend Nat; main prints what Bend received. Same process,
// same address, so the two lines must agree.
#import <Metal/Metal.h>
#include <stdio.h>

// returns the handle three ways at once: low32, high32, and full-as-Nat
Term mlo_run(Env e, Term* f, IoWork* w) {
  id<MTLDevice> d = MTLCreateSystemDefaultDevice();
  return (Term)(u32)(uintptr_t)d;              // low 32
}

Term mhi_run(Env e, Term* f, IoWork* w) {
  id<MTLDevice> d = MTLCreateSystemDefaultDevice();
  return (Term)(u32)((u64)(uintptr_t)d >> 32);  // high 32
}

Term mnat_run(Env e, Term* f, IoWork* w) {
  id<MTLDevice> d = MTLCreateSystemDefaultDevice();
  u64 a = (u64)(uintptr_t)d;
  fprintf(stderr, "C_SAW lo=%u hi=%u full=%llu\n",
          (u32)a, (u32)(a >> 32), (unsigned long long)a);
  return (Term)a;   // full 64-bit address in the Term word
}

static void __attribute__((constructor)) shim8_use(void) {
  io_eff(CID(mlo), mlo_run, 0);
  io_eff(CID(mhi), mhi_run, 0);
  io_eff(CID(mnat), mnat_run, 0);
}