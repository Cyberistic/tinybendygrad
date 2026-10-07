// libclang-ffi.c -- THE PORT'S SIDE OF THE JOIN.
//
// `tinybendygrad/runtime/autogen/libclang.bend` imports this file and declares one
// law per measurement it makes of libclang.  There is no clang-c header on this
// machine, so every prototype below is written out, and the ones that matter were
// MEASURED against the dylib rather than recalled:
//
//   otool -tvV -p _clang_getCursorSpelling libclang.dylib
//       movq  0x18(%rcx), %rdi     rcx = 0x10(%rbp), i.e. OFFSET 24 of the cursor
//   otool -tvV -p _clang_Type_getSizeOf libclang.dylib
//       movq  0x8(%rax), %r14      rax = 0x10(%rbp), i.e. offset 8
//       movq  0x10(%rax), %rax     i.e. offset 16
//   otool -tvV -p _clang_Type_getOffsetOf libclang.dylib
//       movaps 0x10(%rbp), %xmm0    copies 16 of the 24 CXType bytes
//       movq   0x20(%rbp), %rax     the `const char *` is the SECOND argument
//
// CXCursor is therefore {int kind; int xdata; const void *data[3]} = 32 bytes and
// NOT the 16 a first reading suggests.  Declaring `const void *data` segfaults
// inside libclang with no message at all, which is indistinguishable from
// STAGE4.md:119's `bend: memory fault`.
//
// WHY EVERY `_run` REPEATS THE WHOLE ROUND TRIP.  Every value in bend is LINEAR,
// `Nat` and `U32` alike (measured: `U32.show(i) ++ U32.show(i)` fails with
// `consumed more than once`), so `createIndex` then `parseTranslationUnit` then
// `getTranslationUnitCursor` then `getCursorType` then `getSizeOf` is five uses of
// four handles and is not expressible from bend at all.  Each `_run` performs the
// chain itself and returns ONE value.  A wall on CALLERS, not on bindings.
//
// WHY THE LAWS ARE NAMED FOR WHAT THEY MEASURE and not after the libclang
// function: `Type_report` is not `clang_Type_getSizeOf`.  It takes a field
// SELECTOR rather than a `CXType`, because a `CXType` is a 24-byte by-value struct
// that bend cannot hold between two calls.  The 324 trampolines keep their own
// names and signatures; these twelve do not collide with them.
//
// THE REFUSAL.  `clang_Type_getSizeOf`, `clang_Type_getAlignOf` and
// `clang_Type_getOffsetOf` all answer NEGATIVE on failure, and for an offset -5
// for a field name the record does not have.  A negative must not be passed
// through as a `Term`: it would read as an enormous `Nat`.  So all of them refuse
// the same way -- write `NEGATIVE_ANSWER raw=<n>` to stderr and return CL_REFUSED,
// 2^31-1, which is not a bit offset of any record on this target (that would be a
// 256 MB struct) and so cannot be mistaken for one.
//
// ONE MEASUREMENT, TWO READERS.  `Field_report` calls `clang_Type_getOffsetOf`
// ONCE, keeps the answer in one `long`, and derives both the bits and the bytes
// from it, exactly as `oracle.py` does.  bend's linearity is why the division
// cannot live in the .bend; the gate re-derives `offof_bytes * 8 == offof_bits`
// from the PRINTED row, which is what makes the division falsifiable from outside.
//
// ROW COUNT IS PART OF THE RESULT.  Every `_run` writes a `SAW` line to stderr
// BEFORE it can fail, so a missing row is a missing line rather than a silent
// success -- see `.agents/slop/LIBclang-live.md`.

#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stddef.h>
#include <dlfcn.h>

#include "fixture.h"

// ---- the ABI, measured (see the header comment) ---------------------------

typedef void *CXIndex, *CXTranslationUnit, *CXClientData;

typedef struct { int kind; int xdata; const void *data[3]; } CXCursor;  // 32 bytes
typedef struct { int kind; void *data[2]; } CXType;                      // 24 bytes
typedef struct { const void *data; unsigned private_flags; } CXString;   // 16 bytes
typedef struct { const char *Filename, *Contents; unsigned long Length; } CXUnsavedFile;

typedef enum { CXChildVisit_Break = 0, CXChildVisit_Continue = 1, CXChildVisit_Recurse = 2 } CXChildVisitResult;
typedef CXChildVisitResult (*CXCursorVisitor)(CXCursor, CXCursor, CXClientData);

extern CXIndex clang_createIndex(int, int);
extern CXTranslationUnit clang_parseTranslationUnit(CXIndex, const char *, const char **, int,
                                                    CXUnsavedFile *, unsigned, unsigned);
extern void clang_disposeTranslationUnit(CXTranslationUnit);
extern CXCursor clang_getTranslationUnitCursor(CXTranslationUnit);
extern unsigned clang_visitChildren(CXCursor, CXCursorVisitor, CXClientData);
extern CXString clang_getCursorSpelling(CXCursor);
extern CXString clang_getTypeSpelling(CXType);
extern const char *clang_getCString(CXString);
extern CXType clang_getCursorType(CXCursor);
extern long long clang_Type_getSizeOf(CXType);
extern long long clang_Type_getAlignOf(CXType);
extern long clang_Type_getOffsetOf(CXType, const char *);
extern const char *clang_getClangVersion(void);

// ---- the shared walk ------------------------------------------------------
//
// CL-2: the visitor returns Recurse (2).  Continue (1) walks Pair and top and
// stops, which is what hid Pair's fields once already.

static const char *CL_NAMES[] = CL_FIELD_NAMES;
static const char *CL_SPELL[] = CL_FIELD_SPELL;
static const char *CL_want;
static CXCursor CL_hit;

static CXChildVisitResult CL_visit(CXCursor c, CXCursor p, CXClientData d) {
  const char *s = clang_getCString(clang_getCursorSpelling(c));
  if (s && CL_hit.data[0] == 0 && CL_want && strcmp(s, CL_want) == 0) CL_hit = c;
  return CXChildVisit_Recurse;
}

// The whole chain, one selector in.  `sel` is 0..3 for a/b/c/the record; anything
// else answers "no such field" rather than reading past the table, so a wrong
// selector cannot be laundered into a plausible number.
//
// The translation unit is RETURNED, not disposed.  A CXType is a bare `{kind,
// data[2]}` whose `data` points into the TU's AST, so disposing here and asking
// the type anything afterwards is a use-after-free; measured, it reaches the
// caller as `bend: memory fault (machine stack overflow?)` with no C-side message,
// which is bend's SIGSEGV handler and names nothing.  The caller disposes, after
// its last use of the type.
static CXType CL_type_of(int sel, CXTranslationUnit *out_tu) {
  CXIndex ix = clang_createIndex(0, 0);
  CXUnsavedFile uf = { CL_FIXTURE_NAME, CL_FIXTURE_SRC, (unsigned long)strlen(CL_FIXTURE_SRC) };
  CXTranslationUnit tu = clang_parseTranslationUnit(ix, CL_FIXTURE_NAME, 0, 0, &uf, 1, 0);
  memset(&CL_hit, 0, sizeof CL_hit);
  CL_want = (sel >= 0 && sel < 4) ? CL_NAMES[sel] : 0;
  if (CL_want) clang_visitChildren(clang_getTranslationUnitCursor(tu), CL_visit, 0);
  fprintf(stderr, "SAW selector=%d name=%s found=%d\n", sel, CL_want ? CL_want : "(none)",
          CL_hit.data[0] != 0);
  *out_tu = tu;
  return CL_hit.data[0] ? clang_getCursorType(CL_hit) : (CXType){ 0, { 0, 0 } };
}

static int CL_ok(int sel) { return sel >= 0 && sel < 4; }

#define CL_REFUSED 0x7FFFFFFFu   /* 2^31-1: not a bit offset of any real record */

static Term CL_refuse(long long raw) {
  fprintf(stderr, "NEGATIVE_ANSWER raw=%lld -> CL_REFUSED\n", raw);
  return (Term)(u64)CL_REFUSED;
}

// A row's VALUE string, built in bend's own heap by io_str -- the same path
// `clang_getClangVersion` already proved (STAGE3.md, THE STRING LANE).  The C
// side formats and bend prints, so a wrong libclang answer is still a wrong row.
static Term CL_str(Env e, const char *buf, size_t n) {
  fprintf(stderr, "SAW text=%s\n", buf);
  return io_str(e, buf, n);
}

// `CL_TEXT` prints what libclang answered, then the formatted row, so the value
// is on stderr even when the formatting is the thing being looked at.
#define CL_TEXT(...)                                                          \
  do { char _b[512]; int _n = snprintf(_b, sizeof _b, __VA_ARGS__);            \
       fprintf(stderr, "SAW values=%s\n", _b);                                  \
       return CL_str(e, _b, (size_t)_n); } while (0)

#define CL_DROP(t) do { if ((t)) clang_disposeTranslationUnit(t); } while (0)

// ---- the laws -------------------------------------------------------------

// sizeOf, alignOf and the spelling of the selected field, or of the record at 3.
Term Type_report_run(Env e, Term *f, IoWork *w) {
  int sel = (int)(u32)f[0];
  if (!CL_ok(sel)) return CL_refuse(-1);
  CXTranslationUnit tu;
  CXType t = CL_type_of(sel, &tu);
  long long sz = clang_Type_getSizeOf(t), al = clang_Type_getAlignOf(t);
  // copy the spelling out BEFORE the TU goes: it is libclang's own buffer and the
  // format happens after the dispose.
  char sp[128];
  snprintf(sp, sizeof sp, "%s", clang_getCString(clang_getTypeSpelling(t)));
  fprintf(stderr, "SAW Type_report(%d) sizeOf=%lld alignOf=%lld spelling=%s\n", sel, sz, al, sp);
  CL_DROP(tu);
  if (sz < 0 || al < 0) return CL_refuse(sz < 0 ? sz : al);
  CL_TEXT("sizeOf=%lld alignOf=%lld spelling=%s", sz, al, sp);
}

// One clang_Type_getOffsetOf call, two readers of its answer (see the header).
Term Field_report_run(Env e, Term *f, IoWork *w) {
  int sel = (int)(u32)f[0];
  if (sel < 0 || sel > 2) { fprintf(stderr, "SAW Field_report(%d) rejected\n", sel); return (Term)(u64)CL_REFUSED; }
  CXTranslationUnit rec_tu, ft_tu;
  CXType rec = CL_type_of(3, &rec_tu), ft = CL_type_of(sel, &ft_tu);
  long bits = clang_Type_getOffsetOf(rec, CL_NAMES[sel]);
  fprintf(stderr, "SAW Field_report(%s) offof_bits=%ld offof_bytes=%ld\n", CL_NAMES[sel], bits, bits / 8);
  size_t off = sel == 0 ? offsetof(struct Pair, a) : sel == 1 ? offsetof(struct Pair, b) : offsetof(struct Pair, c);
  long long sz = clang_Type_getSizeOf(ft);
  const char *sp = clang_getCString(clang_getTypeSpelling(ft));
  CL_DROP(rec_tu);
  CL_DROP(ft_tu);
  if (bits < 0) return CL_refuse(bits);
  if (sz < 0) return CL_refuse(sz);
  // `spelling=` is libclang's answer and `c=` is the C declaration's own: two
  // derivations of the same fact, so a plant that moved one and not the other
  // would show up as a row that disagrees with itself.
  CL_TEXT("cdecl_off=%zu offof_bits=%ld offof_bytes=%ld sizeOf=%lld spelling=%s c=%s",
          off, bits, bits / 8, sz, sp, CL_SPELL[sel]);
}

// the trap CL-5 names, made into a ROW: an unknown name answers -5, which is a
// number and not a failure, so it is asked for on purpose and must be refused.
Term Field_offset_unknown_run(Env e, Term *f, IoWork *w) {
  CXTranslationUnit tu;
  CXType rec = CL_type_of(3, &tu);
  long v = clang_Type_getOffsetOf(rec, "nope");
  fprintf(stderr, "SAW Field_offset_unknown offof_bits=%ld\n", v);
  CL_DROP(tu);
  return v < 0 ? CL_refuse(v) : (Term)(u64)v;
}

// ---- the fixture's OWN labels and measurements -----------------------------
//
// The oracle reads these out of its shared FIELDS table.  The port reads them out
// of `fixture.h`, the C translation of the same bytes, so a label is a shared
// input on both sides and neither side types one into a row.

Term Field_name_run(Env e, Term *f, IoWork *w) {
  int i = (int)(u32)f[0];
  const char *s = CL_ok(i) ? CL_NAMES[i] : "(no such field)";
  fprintf(stderr, "SAW Field_name(%d)=%s\n", i, s);
  return io_str(e, s, strlen(s));
}

// RECORD CXCursor: the ABI size and every member's offset.  tinygrad's ctypes
// record says 32 as well; this is the independent measurement of why, and it is
// the answer to `libclang.bend`'s old "41 records and 130 fields not covered".
Term Record_report_run(Env e, Term *f, IoWork *w) {
  size_t sz = sizeof(CXCursor), k = offsetof(CXCursor, kind), x = offsetof(CXCursor, xdata),
         d = offsetof(CXCursor, data);
  fprintf(stderr, "SAW Record_report sizeof=%zu kind@%zu xdata@%zu data@%zu\n", sz, k, x, d);
  CL_TEXT("sizeof=%zu fields=kind@%zu,xdata@%zu,data@%zu", sz, k, x, d);
}

// The three words of `data`, which the oracle's `data@8` does not show.  8+8+8 is
// what makes the record 32 bytes rather than 16, and it is the whole reason the
// RECORD row is worth a port at all.
Term Record_words_run(Env e, Term *f, IoWork *w) {
  size_t sz = sizeof(CXCursor), d = offsetof(CXCursor, data);
  size_t words = sizeof(((CXCursor *)0)->data) / sizeof(void *);
  fprintf(stderr, "SAW Record_words data[%zu]@%zu,%zu,%zu sizeof=%zu\n", words, d, d + 8, d + 16, sz);
  CL_TEXT("sizeof=%zu data_words=%zu at=%zu,%zu,%zu", sz, words, d, d + 8, d + 16);
}

// The C spelling of the selected field, which is what the oracle's SIZE row is
// LABELLED with (the FIELD row is labelled with the name and carries it as `c=`).
Term Field_spell_run(Env e, Term *f, IoWork *w) {
  int i = (int)(u32)f[0];
  const char *s = CL_ok(i) ? CL_SPELL[i] : "(no such field)";
  fprintf(stderr, "SAW Field_spell(%d)=%s\n", i, s);
  return io_str(e, s, strlen(s));
}

Term Pair_size_run(Env e, Term *f, IoWork *w) {
  size_t v = sizeof(struct Pair);
  fprintf(stderr, "SAW Pair_size=%zu\n", v);
  return (Term)(u64)v;
}

Term Clang_version_run(Env e, Term *f, IoWork *w) {
  const char *s = clang_getClangVersion();
  fprintf(stderr, "SAW Clang_version=%s\n", s ? s : "(null)");
  return io_str(e, s, s ? strlen(s) : 0);
}

// The CLIB row, port-side.  The oracle answers it with ctypes' resolved path.  The
// port has no ctypes, so it asks the DYNAMIC LINKER which image the symbol it is
// actually calling came from -- the same question, answered by the loader rather
// than requested (CL-6).
Term Loaded_dylib_run(Env e, Term *f, IoWork *w) {
  Dl_info info;
  const char *p = (dladdr((void *)clang_getClangVersion, &info) && info.dli_fname) ? info.dli_fname : "(unknown)";
  fprintf(stderr, "SAW Loaded_dylib=%s\n", p);
  return io_str(e, p, strlen(p));
}

static void __attribute__((constructor)) cl_use(void) {
  io_eff(CID(Type_report), Type_report_run, 0);
  io_eff(CID(Field_report), Field_report_run, 0);
  io_eff(CID(Field_offset_unknown), Field_offset_unknown_run, 0);
  io_eff(CID(Field_name), Field_name_run, 0);
  io_eff(CID(Field_spell), Field_spell_run, 0);
  io_eff(CID(Record_words), Record_words_run, 0);
  io_eff(CID(Record_report), Record_report_run, 0);
  io_eff(CID(Pair_size), Pair_size_run, 0);
  io_eff(CID(Clang_version), Clang_version_run, 0);
  io_eff(CID(Loaded_dylib), Loaded_dylib_run, 0);
}