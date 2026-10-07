// STAGE 1: ONE binding, from the committed file to a linked binary.
//
// The input is one line of tinybendygrad/runtime/autogen/libclang.bend:1080
// (the def signature) plus .agents/slop/ag-libclang.tramp:5 (the ctypes
// spelling). The C declaration below is written from THAT, because there is no
// clang-c header on this machine -- which is the claim: a committed SIGNATURE
// is a complete input for a call.
//
//   CXIndex clang_createIndex(int, int)      CXIndex = ctypes.c_void_p
//
// 3 C lines for the shim (macro, _run, io_eff) is the whole per-function cost.

#include <stdint.h>
typedef void* CXIndex;
extern CXIndex clang_createIndex(int, int);

#define PTR(t) ((void*)(uintptr_t)(t))

Term clang_createIndex_run(Env e, Term* f, IoWork* w) {
  return (Term)(u64)(uintptr_t)clang_createIndex((int)(u32)f[0], (int)(u32)f[1]);
}

static void __attribute__((constructor)) s1_use(void) {
  io_eff(CID(clang_createIndex), clang_createIndex_run, 0);
}