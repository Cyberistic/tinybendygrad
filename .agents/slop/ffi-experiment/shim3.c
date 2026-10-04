#include <stdlib.h>

// The per-function marshalling cost, measured, not asserted.
//
// A Bend String is a singly-linked list of Unicode code points: each cell is
// term_ctr(CID_SCON, loc) with the scalar at mem[loc] and the sealed tail at
// mem[loc+1], terminated by term_pak(CID_SNIL, 0). There is no char* anywhere
// in it, so a C callee expecting `const char*` needs this walk first.

// Walk the cons chain into a fresh NUL-terminated buffer. Returns malloc'd.
static char* bend_str_to_c(Env e, Term t) {
  char* buf = (char*)malloc(4096);
  u32 n = 0;
  while (term_aux(t) != CID_SNIL) {
    Term f[2];
    u64 sp = ctr_take(e, t, 2, f);
    buf[n++] = (char)f[0];
    t = f[1];
    spare_free(e, cls_fit(2), sp);
  }
  buf[n] = 0;
  return buf;
}

// E2: getenv -> Bend String. Proves the return direction.
Term env_run(Env e, Term* f, IoWork* w) {
  const char* v = getenv("FOO");
  return io_str(e, v, v ? strlen(v) : 0);
}

// E3: Bend String in -> const char* -> strlen -> length out. Proves the
// argument direction AND that the shared-lib call happens on marshalled data.
Term slen2_run(Env e, Term* f, IoWork* w) {
  char* c = bend_str_to_c(e, f[0]);
  u32 n = (u32)strlen(c);
  free(c);
  return (Term)n;
}

static void __attribute__((constructor)) shim3_use(void) {
  io_eff(CID(env), env_run, 0);
  io_eff(CID(slen2), slen2_run, 0);
}