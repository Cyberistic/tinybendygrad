// STAGE 3 -- the FALSIFIABLE ROW. Four laws, one .c, one import, one cc.
//
// The rule this file exists to satisfy: NEVER compare either side to a
// constant. `ffi-experiment/run-all.sh` asserted `BEND_NAT 4307773504` and that
// address is ASLR-dependent, so the assertion was a transcription of one run.
//
// So every fact here is either
//   (a) C's reading of the SAME OBJECT against Bend's reading of it, in ONE
//       process, or
//   (b) a PLANT that must move the answer, paired with a DISARM that must not.
//
// THE CONTROLS, and what each one would look like if it were disarmed:
//   SAME_OBJ   clang_createIndex called once; C prints the handle it got to
//              stderr, Bend prints what it received. Equal => one object, read
//              twice. This is the comparison the whole row rests on.
//   TWO_RUNS   the SAME binary run twice; the two C_SAW addresses must DIFFER.
//              If they match, ASLR is off for this process and the row has
//              stopped measuring what it claims.
//   TWO_LIVE   two indices alive at once in ONE process; their addresses must
//              DIFFER. If two live handles were equal, "C and Bend agree on an
//              address" would be satisfied by a constant answer and would prove
//              nothing.
//   PLANT      clang_CXIndex_setGlobalOptions(ix, v) then
//              clang_CXIndex_getGlobalOptions(ix), all inside ONE foreign call.
//              getGlobalOptions must return v. The plant moves v from 0 to 5 to
//              7 and the answer must follow.
//   DISARM     the SAME v twice must give the SAME answer, and v=0 must give
//              0, which is libclang's own CXGlobalOpt_None. A harness where the
//              plant lands but the disarm also moves is measuring the harness.
//
// WHY THE ROUND TRIP IS ONE FOREIGN CALL: a Bend Nat is LINEAR (measured, every
// Nat in bend 2.0.35, not only foreign ones), so `set_opts(ix, v)` followed by
// `get_opts(ix)` is not expressible from Bend -- ix would be consumed twice.
// Doing both calls inside one _run is what makes the round trip writable at all.
//
// THE ADDRESS LANE, and the number nobody should read as a constant:
// clang_createIndex returns a heap pointer. macOS ASLR moves it every run.

#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef void* CXIndex;
extern CXIndex  clang_createIndex(int, int);
extern unsigned clang_CXIndex_getGlobalOptions(CXIndex);
extern void     clang_CXIndex_setGlobalOptions(CXIndex, unsigned);
extern const char* clang_getClangVersion(void);

#define PTR(t) ((void*)(uintptr_t)(t))

// (a) SAME_OBJ: C's own reading of the handle, to stderr, before it is returned.
Term same_run(Env e, Term* f, IoWork* w) {
  CXIndex ix = clang_createIndex((int)(u32)f[0], (int)(u32)f[1]);
  fprintf(stderr, "C_SAW HANDLE %llu\n", (unsigned long long)(uintptr_t)ix);
  return (Term)(u64)(uintptr_t)ix;
}

// TWO_LIVE: two indices alive simultaneously. Returns 1 when they differ.
Term two_live_run(Env e, Term* f, IoWork* w) {
  CXIndex a = clang_createIndex(0, 0);
  CXIndex b = clang_createIndex(0, 0);
  unsigned long long x = (unsigned long long)(uintptr_t)a;
  unsigned long long y = (unsigned long long)(uintptr_t)b;
  fprintf(stderr, "C_SAW TWO %llu %llu\n", x, y);
  return (Term)(u64)(x != y);
}

// PLANT / DISARM: the round trip, in one call, so one Nat is enough.
Term trip_run(Env e, Term* f, IoWork* w) {
  CXIndex ix = clang_createIndex(0, 0);
  clang_CXIndex_setGlobalOptions(ix, (unsigned)(u32)f[0]);
  unsigned got = clang_CXIndex_getGlobalOptions(ix);
  fprintf(stderr, "C_SAW TRIP set=%u got=%u\n", (unsigned)(u32)f[0], got);
  return (Term)(u64)got;
}

// The string case, because a const char* return is the one marshalling path the
// census could NOT fold into a word: the bytes are rebuilt in Bend's own heap.
Term cver_run(Env e, Term* f, IoWork* w) {
  const char* v = clang_getClangVersion();
  return io_str(e, v, v ? strlen(v) : 0);
}

static void __attribute__((constructor)) s3_use(void) {
  io_eff(CID(same),     same_run,     0);
  io_eff(CID(two_live), two_live_run, 0);
  io_eff(CID(trip),     trip_run,     0);
  io_eff(CID(cver),     cver_run,     0);
}