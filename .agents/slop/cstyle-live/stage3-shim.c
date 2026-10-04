// stage3-shim.c -- the FFI side of Stage 3. APPENDED to the port's own emitted C text by
// `stage3.sh`, which then asserts with `cmp` that the text above this comment is
// byte-identical to what `cstyle.bend` produced. Nothing in here re-types a kernel.
//
// EVERY foreign def is `Term <name>_run(Env e, Term* f, IoWork* w)` plus one
// `io_eff(CID(<name>), <name>_run, 0)` in a constructor. MEASURED CONSTRAINTS, all three
// learned from `bend -o` output rather than from a parse-error message:
//   * the law must be REACHABLE from `main`, or no `CID_<LAW>` is emitted and `cc` fails
//     with "use of undeclared identifier CID_X". A declared-but-uncalled law is invisible.
//   * `CID(id)` for a law named `id` is rejected outright: "CID(id) names no constructor or
//     def". `ID`-shaped names are special; `lane` and `call_e4` were used instead.
//   * `Env` is BY VALUE. `Env* e` will not compile.
//
// WHY SO MANY ARGUMENTS PER CALL, and it is the linear-`Nat` rule rather than taste:
// ffi-experiment/EXPECTED.md measured that foreign values are consumed exactly once, and
// MEASURED again here on `Nat`: a `Nat` parameter spelled four times fails at the FIRST
// binder with "a (consumed more than once)". An address therefore crosses ONCE and the
// C side keeps it, which is what a real runtime does anyway -- `ops_cpu.py:72` keeps
// `self.fxn` and passes `ctypes.c_uint64(x)` per buffer rather than re-deriving an address.
#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <sys/mman.h>

// ONE REGION, BUMPED, NEVER FREED. `mmap` then bump is `HostAllocator._alloc`'s shape in
// `tinygrad/device.py`, and it is `ops_bend.bend`'s `raw_alloc` shape (:1476-1484) at the
// same time: one region, a top that only moves up, and no free.
static uint8_t *g_base = 0;
static uint64_t g_brk = 0;
// The one buffer the read side addresses by INDEX rather than by address, because Bend
// cannot hold a `Nat` twice and `outp` is already spent by the call.
static float *g_out = 0;

// `alloc_buf(nbytes) -> Nat`. The address comes back as a plain u64 in the Term word.
// A `Nat` and not a `U32` carries it: MEASURED on this machine a 64-byte malloc lands at
// 4317913024, which is > 2^32 and < 2^51 -- it fits `Nat` and does not fit `U32`.
Term alloc_buf_run(Env e, Term *f, IoWork *w) {
  uint64_t n = (uint64_t)f[0];
  if (!g_base) {
    g_base = (uint8_t *)mmap(0, 1u << 20, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (g_base == MAP_FAILED) { fprintf(stderr, "mmap failed\n"); return (Term)0; }
  }
  uint64_t a = (uint64_t)(uintptr_t)(g_base + g_brk);
  g_brk += (n + 15) & ~(uint64_t)15;
  fprintf(stderr, "C_ALLOC nbytes=%llu addr=%llu brk=%llu\n",
          (unsigned long long)n, (unsigned long long)a, (unsigned long long)g_brk);
  return (Term)a;
}

// `free_buf(addr) -> Nat` -- a NO-OP, exactly as `ops_bend.bend:1506` documents, and for
// the reason it gives: Bend's `Array`/`List` is affine, so a freed range has no second owner
// to hand it back to. It answers the address it was given.
Term free_buf_run(Env e, Term *f, IoWork *w) { return (Term)f[0]; }

// `fill4(addr, b0, b1, b2, b3) -> Nat` -- stores four 32-bit patterns and ANSWERS THE
// ADDRESS BACK, so Bend can then spend it on the call. The patterns cross as `Nat`s because
// ffi-experiment/EXPECTED.md measured that `f32` crosses losslessly as a `Nat` bit pattern
// and Bend has no `F64`/`I64` to widen it through.
Term fill4_run(Env e, Term *f, IoWork *w) {
  uint32_t *a = (uint32_t *)(uintptr_t)f[0];
  a[0] = (uint32_t)f[1];
  a[1] = (uint32_t)f[2];
  a[2] = (uint32_t)f[3];
  a[3] = (uint32_t)f[4];
  for (uint64_t i = 0; i < 4; i++) {
    float fv;
    __builtin_memcpy(&fv, &a[i], 4);
    fprintf(stderr, "C_FILL %llu 0x%08x %.9g\n", (unsigned long long)i, a[i], (double)fv);
  }
  return f[0];
}

// `call_e4(entry, outp, inp) -> Nat` -- THE KERNEL'S ENTRY POINT ARRIVES AS A `Nat`. No Bend
// code ever names `E_4`; it only ever holds its address and hands it here. It answers `outp`
// back because the read side needs it and a `Nat` cannot be held twice.
Term call_e4_run(Env e, Term *f, IoWork *w) {
  void (*fn)(float *, float *) = (void (*)(float *, float *))(uintptr_t)f[0];
  fn((float *)(uintptr_t)f[1], (float *)(uintptr_t)f[2]);
  g_out = (float *)(uintptr_t)f[1];
  return f[1];
}

// `lane(i) -> Nat` -- reads one lane of the buffer the last call wrote, and PRINTS it from C
// as well. Two independent readings of the same memory: the verdict is on BEND's number and
// C's is corroboration, so a disagreement between them is visible instead of averaged away.
Term lane_run(Env e, Term *f, IoWork *w) {
  uint32_t v;
  __builtin_memcpy(&v, &g_out[(uint64_t)f[0]], 4);
  float fv;
  __builtin_memcpy(&fv, &v, 4);
  fprintf(stderr, "C_LANE %llu 0x%08x %.9g\n", (unsigned long long)(uint64_t)f[0], v, (double)fv);
  return (Term)(u64)v;
}

// `e4_addr() -> Nat` -- the address OF the emitted kernel, taken here in C so that Bend
// never has to name it.
Term e4_addr_run(Env e, Term *f, IoWork *w) {
  uint64_t a = (uint64_t)(uintptr_t)&E_4;
  fprintf(stderr, "C_E4_ADDR %llu\n", (unsigned long long)a);
  return (Term)a;
}

static void __attribute__((constructor)) s3_use(void) {
  io_eff(CID(alloc_buf), alloc_buf_run, 0);
  io_eff(CID(free_buf), free_buf_run, 0);
  io_eff(CID(fill4), fill4_run, 0);
  io_eff(CID(call_e4), call_e4_run, 0);
  io_eff(CID(lane), lane_run, 0);
  io_eff(CID(e4_addr), e4_addr_run, 0);
}