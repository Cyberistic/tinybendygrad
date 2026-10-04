// E7: what does a wide value actually cost at the boundary?
// Bend 2.0.35 has no U64 (measured: "expected : a defined name / observed :
// U64"). So a 64-bit driver quantity -- a pointer, a handle, a byte size --
// has no native Bend type. Two candidate carriers, measured here.
#import <Metal/Metal.h>

// U32 carrier: how many bits survive?
Term u32_probe(Env e, Term* f, IoWork* w) {
  // full 64-bit handle from the driver, narrowed to the Term word
  id<MTLDevice> d = MTLCreateSystemDefaultDevice();
  u64 addr = (u64)(uintptr_t)d;
  return (Term)(u32)(addr >> 32);   // the HIGH half, as U32
}

// Nat carrier: what is a Nat on the C side? Print its shape.
Term nat_probe(Env e, Term* f, IoWork* w) {
  return (Term)(u32)(term_tag(f[0]));
}

Term mdev_hi_run(Env e, Term* f, IoWork* w) {
  id<MTLDevice> d = MTLCreateSystemDefaultDevice();
  return (Term)(u32)((u64)(uintptr_t)d >> 32);
}

Term mdev_full_run(Env e, Term* f, IoWork* w) {
  id<MTLDevice> d = MTLCreateSystemDefaultDevice();
  return (Term)(u64)(uintptr_t)d;   // full address in one Term word
}

Term mtag_run(Env e, Term* f, IoWork* w) {
  return (Term)(u32)term_tag(f[0]);
}

static void __attribute__((constructor)) shim7_use(void) {
  io_eff(CID(mdev_hi), mdev_hi_run, 0);
  io_eff(CID(mdev_full), mdev_full_run, 0);
  io_eff(CID(mtag), mtag_run, 0);
}