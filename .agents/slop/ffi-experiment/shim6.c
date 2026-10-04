// E6: a real GPU DRIVER backend, not libc and not libclang. Metal.framework
// ships with macOS, so it needs no install — the same situation every driver
// backend is in.
//
// The signature that matters is the driver signature: an opaque handle comes
// back out. MTLCreateSystemDefaultDevice returns `id<MTLDevice>`, a pointer to
// an ObjC object the shim never inspects. Bend has no ObjC, so the shim hands
// the raw 64-bit address back as a Term and Bend treats it as an opaque U64.
// That is the whole marshalling story for a handle: load, widen, done.
#import <Metal/Metal.h>

Term mdev_run(Env e, Term* f, IoWork* w) {
  id<MTLDevice> d = MTLCreateSystemDefaultDevice();
  return (Term)(u64)(uintptr_t)d;
}

Term mname_run(Env e, Term* f, IoWork* w) {
  id<MTLDevice> d = MTLCreateSystemDefaultDevice();
  if (d == nil) return io_str(e, "", 0);
  const char* n = [[d name] UTF8String];
  return io_str(e, n, (u64)strlen(n));
}

static void __attribute__((constructor)) shim6_use(void) {
  io_eff(CID(mdev), mdev_run, 0);
  io_eff(CID(mname), mname_run, 0);
}