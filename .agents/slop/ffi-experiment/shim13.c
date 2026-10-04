// E10: the OBJC case. libclang is plain C: MTLCreateSystemDefaultDevice is a
// C function and the shim calls it by name. Metal's real surface is not C --
// it is -[MTLDevice newCommandQueue], an ObjC message send. So the shim has to
// reach objc_msgSend itself. THIS is the case that decides whether a driver
// backend is reachable, so it gets its own experiment.
#import <Metal/Metal.h>
#import <objc/message.h>
#import <objc/runtime.h>

// Method 1: declare the protocol locally and let the compiler emit the send.
//   @protocol(id<MTLDevice>) newCommandQueue
Term nq_proto_run(Env e, Term* f, IoWork* w) {
  id<MTLDevice> d = MTLCreateSystemDefaultDevice();
  id<MTLCommandQueue> q = [d newCommandQueue];
  return (Term)(u32)(q != nil);   // 1 = a live command queue came back
}

// Method 2: NO local @interface at all. Fetch the selector, look up the IMP,
//           and call objc_msgSend directly. Nothing about the ObjC type system
//           is needed -- only the runtime, which is a plain C library.
static id g_dev = nil;

Term nq_raw_run(Env e, Term* f, IoWork* w) {
  if (g_dev == nil) g_dev = MTLCreateSystemDefaultDevice();
  SEL sel = sel_registerName("newCommandQueue");
  IMP imp = [g_dev methodForSelector:sel];   // this IS an ObjC send, once
  id (*send)(id, SEL) = (id (*)(id, SEL))imp;
  id q = send(g_dev, sel);
  return (Term)(u32)(q != nil);
}

// Method 3: a buffer's length -- a property read, the most common driver
//           query there is.
static id g_buf = nil;

Term blen_run(Env e, Term* f, IoWork* w) {
  if (g_buf == nil) {
    g_dev = g_dev ? g_dev : MTLCreateSystemDefaultDevice();
    g_buf = [(id<MTLDevice>)g_dev newBufferWithLength:1024 options:0];
  }
  if (g_buf == nil) return (Term)0xFFFFFFFFull;   // sentinel: no buffer
  return (Term)(u64)[(id<MTLBuffer>)g_buf length];
}

static void __attribute__((constructor)) shim10_use(void) {
  io_eff(CID(nq_proto), nq_proto_run, 0);
  io_eff(CID(nq_raw), nq_raw_run, 0);
  io_eff(CID(blen), blen_run, 0);
}