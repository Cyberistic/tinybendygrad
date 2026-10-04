// E1: the shared-library call. slen_run calls strlen from libc, which the
// linker resolves at cc time. Nothing about this is header-only.
#include <string.h>

Term slen_run(Env e, Term* f, IoWork* w) {
  return (Term)(u32)strlen("tinybendygrad");
}

static void __attribute__((constructor)) slen_use(void) {
  io_eff(CID(slen), slen_run, 0);
}