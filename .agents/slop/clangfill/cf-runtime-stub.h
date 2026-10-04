// A STUB of bend's C runtime, for the STANDALONE syntax gate only.
//
// `.agents/slop/clangshim/libclang-tramp.c` is SPLICED into the program bend
// emits, so `io_str`, `io_cbuf`, `io_hand_v`, `Term`, `Env`, `IoWork` and `CID`
// are already in scope there and declaring them here would be a redefinition.
// The standalone gate compiles the file on its own, and without these names it
// cannot see a single one of its own mistakes -- it stops at `unknown type name
// 'Term'` and never reaches the row that is wrong.
//
//   cc -fsyntax-only -include cf-runtime-stub.h -I <shim> libclang-tramp.c
//
// It declares the SEAM and nothing else, so a mistake in this file is still
// reported: the stub defines no macro this file uses for its own logic.
#ifndef CF_RUNTIME_STUB_H
#define CF_RUNTIME_STUB_H

#include <stddef.h>
#include <stdint.h>

typedef uint64_t u64;
typedef uint32_t u32;
typedef uint8_t  u8;
typedef u64 Term;
typedef struct Env Env;
typedef struct IoWork IoWork;
struct Env { u64 mem[64]; };
struct IoWork {
  Term cont;
  Term item;
  int  fd;
};

static inline u64 heap_alloc(Env e, u32 cls) { (void)e; (void)cls; return 0; }
static inline u32 cls_fit(u32 n) { return n; }
static inline Term term_ctr(u64 cid, u64 at) { (void)cid; (void)at; return 0; }
static inline Term io_exec(Env e, IoWork *w) { (void)e; (void)w; return 0; }
#define TERM_HOLE ((Term)0)
static inline u32 cid_arity(u64 cid) { (void)cid; return 0; }

#define TAG_PAK 1u
#define LOC_MASK ((u64)0xFFFFFFFFFFull)

static inline u64 term_aux(Term t) { (void)t; return 0; }
static inline u64 term_loc(Term t) { (void)t; return 0; }
static inline u64 term_pak(u64 cid, u64 v) { (void)cid; return v; }
static inline u64 io_hand_v(Term t) { return t; }
static inline u64 io_hand(u64 v) { return v; }
static inline char *io_cbuf(Env e, Term s, u64 *n, u64 cons) {
  (void)e; (void)cons; *n = 0; static char b[1]; return b;
}
static inline Term io_str(Env e, const char *p, u64 n) { (void)e; (void)p; (void)n; return 0; }
static inline void *io_mem(void *p) { return p; }
#define CID(k) 0u
#define FID(k) 0u
#define SCon 0u

struct IoEff { void *run; u32 ask; };
static struct IoEff io_eff_rows[4];
static inline void io_eff(u64 cid, Term (*run)(Env, Term *, IoWork *), u32 ask) {
  if (cid < 4) { io_eff_rows[cid].run = (void *)run; io_eff_rows[cid].ask = ask; }
}
#endif