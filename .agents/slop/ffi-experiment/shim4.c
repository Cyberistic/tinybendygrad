// E4: a real third-party shared library, linked with -lclang.
// NOTE: there are NO clang-c headers on this machine. The ABI is one line:
//   const char* clang_getClangVersion(void);
// That is the whole point — a shim does not need the SDK, only the ABI.
#include <string.h>
extern const char* clang_getClangVersion(void);

Term cver_run(Env e, Term* f, IoWork* w) {
  const char* v = clang_getClangVersion();
  return io_str(e, v, v ? strlen(v) : 0);
}

static void __attribute__((constructor)) shim4_use(void) {
  io_eff(CID(cver), cver_run, 0);
}