#!/usr/bin/env python3
"""FILL the 324 libclang trampolines, through the generator.

`tinybendygrad/runtime/autogen/libclang.bend` is a PRODUCT.  `ag-emit.bend` emits
one template 324 times and every body came out `None{}`.  This module is the
second half of the generator: it turns each `def ... -> Maybe<&2, T>:\n  None{}`
in that product into a `law` + `def` whose body is ONE `import`, and it emits
one C `_run` per row into `.agents/slop/clangshim/libclang-tramp.c`.  Nothing is
written by hand per function: `abi.py` derives every carrier class and this file
splices, so `emitter -> fix -> product` stays one reproducible pipeline.

    python3 .agents/slop/clangfill/fill.py --check    # IN SYNC
    python3 .agents/slop/clangfill/fill.py            # rewrite the .c

A `file:line` into the product is a coordinate, not a binding (a header-only
change moves every body), so this file names `clang_*` and nothing else.
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import abi  # noqa: E402

REPO = abi.REPO
SHIM = REPO / ".agents" / "slop" / "clangshim"
PRODUCT_C = SHIM / "libclang-tramp.c"
PINNED = "/Library/Developer/CommandLineTools/usr/lib/libclang.dylib"
IMPORT_REL = "../../../.agents/slop/clangshim/libclang-tramp.c"
CSTR_CAP = 4096

# THE ANCHORS.  bend's every value is LINEAR, so a real `CXTranslationUnit` cannot
# be handed to two laws from bend; the fixture supplies it instead, and every
# substituted argument says `fixed` in its row.  A parameter no fixture can supply
# is left NULL, which is what libclang itself reads as "no object" -- inventing one
# would be a fabricated argument, not a binding.
# KEYED BY THE ABI TYPE, NOT BY THE PARAMETER NAME.  Keyed by name it fired ZERO
# times: `clang_getCursorKind`'s parameter is `_0` and `clang_parseTranslationUnit`'s
# are `CIdx`/`source_filename`/`unsaved_files`, so no name in the 324 is
# `CXTranslationUnit` and every substituted argument was silently a zero Term.  All
# 312 executed rows were being called with NULLs and the census said so --
# `ROWS called with at least one NULL argument 278` -- and nobody read that line as
# a defect in the FILL.  The parameter NAME is upstream's; the TYPE is the ABI.
FIXTURE_PTR = {"CXIndex": "cf_index()", "CXTranslationUnit": "cf_tu()", "CXFile": "cf_file()"}
FIXTURE_BOX = {
    "CXCursor": "cf_cursor()", "CXType": "cf_type()", "CXString": "cf_string()",
    "CXSourceLocation": "cf_loc()", "CXSourceRange": "cf_range()",
    "CXTUResourceUsage": "cf_usage()",
}
ROW_CLASS = {abi.VOID: "void", abi.INT: "int", abi.FLT: "double", abi.CSTR: "cstr",
             abi.PTR: "ptr", abi.BOX: "box"}
# A box's first word is printed in HEX, so the gate's `0x[0-9a-f]{6,}` mask catches
# it when it IS a pointer -- `CXSourceLocation`'s first word is `ptr_data[0]` -- and
# leaves it visible when it is a small integer like `CXCursor.kind`.  Printed in
# DECIMAL a pointer is `92237168`, the mask does not match it, and DETERMINISM
# answered 46 rows moved between two runs of ONE binary.
ROW_FMT = {abi.INT: "%llu", abi.FLT: "%f", abi.CSTR: "%s", abi.PTR: "%p",
           abi.BOX: "0x%08x"}


def exported(lib=PINNED):
    """The dylib's own symbol table.  A row missing here is VERSION SKEW: no
    declaration of it links, and saying so beats emitting one."""
    out = subprocess.run(["nm", "-gU", lib], capture_output=True, text=True).stdout
    return {ln.split()[-1].lstrip("_") for ln in out.splitlines() if ln.strip()}


def c_proto_n(spelling, structs, stars=0, incomplete=()):
    """One ABI spelling -> (C type, carrier class).

    Peel every leading `c.POINTER[...]` into STARS, then classify the BASE:

      * a SCALAR base with no stars is the scalar; with stars it is a pointer to
        the scalar, and a pointer to a scalar is a pointer, so the class is PTR;
      * `ctypes.c_char` is the `const char *` walk, one direction or the other;
      * a BY-VALUE base is a record, and with stars it is a pointer to records;
      * an INCOMPLETE base -- upstream gives it a `SIZE` but no row is ever bare,
        so it is only ever named after a `*` -- is a record, never a pointer;
      * anything else is an OPAQUE HANDLE, which in `clang-c/Index.h` is already a
        pointer, so the stars replace nothing and add nothing.

    Two drafts of this file read `c.POINTER[c.POINTER[CXCursor]]` as a type named
    `c.POINTER[CXCursor]` and then appended a star to a type that already had one,
    and the C compiler refused the file for exactly the right reason both times.
    """
    m = re.fullmatch(r"c\.POINTER\[(.+)\]", spelling)
    if m:
        return c_proto_n(m.group(1), structs, stars + 1, incomplete)
    if spelling in abi.SCALARS:
        ct, cls = abi.SCALARS[spelling]
        if not stars:
            return ct, cls
        if spelling == "ctypes.c_void_p":
            return "void *", abi.PTR
        return ct.rstrip() + " " + "*" * stars, abi.PTR
    if spelling.startswith("c.CFUNCTYPE"):
        return abi.fn_c(spelling), abi.PTR
    if spelling == "ctypes.c_char":
        return "const char " + "*" * stars, (abi.CSTR if stars == 1 else abi.PTR)
    if spelling in structs or spelling in incomplete:
        cls = abi.BOX if stars == 0 else abi.PTR
        # `.strip()` and not `spelling + " "`: the trailing space survives into the
        # declaration as `(CXCursor  *)`, and a `FIXTURE_BOX.get("CXCursor ")` MISSES
        # on it -- so every record argument silently stayed the zero record, 312 rows
        # executed, and not one of them ever saw the fixture's cursor.  A whitespace
        # mismatch disabled the whole fixture and every row still looked like a row.
        return ((spelling + " " + "*" * stars).strip() if stars else spelling), cls
    # An OPAQUE HANDLE is already a pointer: `clang-c/Index.h` spells it
    # `typedef void *CXIndex`, so a bare `CXIndex` PARAMETER is `CXIndex` and not
    # `CXIndex *`.  Writing the star anyway gave every one of the 225 pointer
    # parameters a `void **` in the declaration and in the prototype, which passes
    # the right register and lies about the type in two places.
    return ((spelling + " " + "*" * stars).strip() if stars else spelling), abi.PTR


def plan():
    """Every row -> a dict, plus the declaration sets the emitted C needs."""
    syms = exported()
    bare = abi.by_value_structs()
    resolved, size, _f = abi.ctypes_structs()
    enums = abi.enums()
    byval = sorted(n for n in bare if resolved.get(n, n) in size)
    # `CXUnsavedFile` only ever appears as a POINTER in the 324 rows, so
    # derivation 1 says "incomplete type" -- but the FIXTURE parses with one by
    # value, so it is forced complete here instead of being written out by hand.
    struct_c, size_of, resolved = abi.struct_defs(byval + ["struct_CXUnsavedFile"])
    # An INCOMPLETE base: upstream gives it a SIZE but no row is ever bare, so it
    # is a record that is only ever named after a `*` and needs no definition.
    bases = {b for s in abi.spellings() for b in abi.peel(s)}
    incomplete = sorted(b for b in bases if b in size and b not in struct_c
                        and not b.startswith(("ctypes.", "c.")))
    rows = []
    for name, ret, params in abi.rows():
        rct, rcls = (("void", abi.VOID) if ret == "None"
                     else c_proto_n(ret, struct_c, incomplete=incomplete))
        ps = []
        for pn, pb in params:
            pct, pcls = c_proto_n(pb, struct_c, incomplete=incomplete)
            ps.append((pn, pb, pct, pcls, abi.bend_type(pb, struct_c)))
        rows.append(dict(name=name, ret=ret, rbend=abi.bend_type(ret, struct_c),
                         rct=rct, rcls=rcls, ps=ps, ok=name in syms, n=len(params)))
    # An opaque handle is a name that is NOT an upstream struct, NOT a scalar and
    # NOT an upstream enum -- each of those three is its own derivation.
    handles = sorted(n for n in bare if resolved.get(n, n) not in size
                     and n not in abi.SCALARS and n not in enums
                     and not n.startswith(("ctypes.", "c.")))
    # A POINTER's base name, peeled all the way down, that nothing above declared.
    ptr_only = sorted(set(incomplete) | {b for b in bases
                                         if b not in size and b not in handles
                                         and b not in struct_c and b not in abi.SCALARS
                                         and b not in enums and not b.startswith(("ctypes.", "c."))})
    return rows, struct_c, size_of, handles, ptr_only, enums, syms


# ------------------------------------------------------------------ the C text
HEADER = r'''// libclang-tramp.c -- GENERATED by `.agents/slop/clangfill/fill.py`.  DO NOT
// EDIT; `fill.py --check` prints `IN SYNC` or this file was not made by the
// generator.  One `_run` per `@dll.bind` trampoline in `.agents/slop/ag-libclang.tramp`,
// every one DERIVED from that row and from upstream's own ctypes table.
//
// EVERY PROTOTYPE BELOW IS WRITTEN OUT because there is no `clang-c/Index.h` on
// this machine, and each is derived from the ctypes spelling tinygrad's own
// generator recorded -- the SAME spelling `ag-emit.bend` turned into the bend
// signature, so a bend signature and its C declaration have ONE source.
//
// ONE WORD IS NOT ENOUGH FOR A STRUCT.  A `Term` is one word.  `CXCursor` is 32
// bytes and `CXType` is 24, so a by-value record travels as a C-heap BOX whose
// address is a bend HANDLE (`io_hand`/`io_hand_v`, comp.ts:5440) -- the runtime's
// own encoding for a pointer put into a Term and taken out again, and the one
// `File` and `Socket` already use.
//
// THE `const char*` WALK, BOTH DIRECTIONS, because a C string is not a number:
//     String -> char*   io_cbuf(e, f[i], &n, CID(SCon))   comp.ts:5591, you free
//     char* -> String   io_str(e, p, n)                   comp.ts:5640
// Both are RUNTIME code and already in every emitted program, so the walk is a
// CALL and not a thing this file had to build.  `io_cbuf` CONSUMES the cons list,
// so it is a one-way door, exactly as a bend `String` is a one-way value.
//
// THE ZERO IS A FIXTURE.  bend's every value is linear, so a real handle cannot be
// handed to two laws; a parameter arriving as zero is taken from a real clang
// index over `fixture.h`.  Every row prints the arguments it ACTUALLY called
// with, so a substituted one is visible in the row and not only in this comment.
//
// `io_eff`'s THIRD ARGUMENT IS NOT THE ARITY.  It is the NEED: 0 runs at once,
// `IO_READ` parks until the handle in `f[0]` is readable and `IO_TIME` parks for
// `f[0]` milliseconds (comp.ts:5990).  Arity comes from the law's own cid through
// `cid_arity` (comp.ts:5769).  Every registration below is 0.
//
// EVERY REGISTRATION IS INSIDE `#ifdef CID(name)`, and that is the whole reason
// the file compiles at all.  bend emits a `CID` ONLY for a law something CALLS --
// `grep -c '^#define CID_'` on a build whose main reaches two laws answers 24, and
// the only two law ids in it are those two -- so a law nothing calls has no id to
// name, and the first build answered with 324 undeclared `CID_CLANG_*`.  `#ifdef`
// is the mechanism bend's own guide documents for exactly this ("A constructor the
// program does not use has no id, so `#ifdef CID(Name)` tests for it",
// `references/bend/guide/EFFECTS.md:39`), so an unreached law is UNREGISTERED
// rather than miscompiled.  The consequence is honest and is the report's second
// number: a body is EXECUTED only where something reaches the law that owns it.

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stddef.h>

#include "fixture.h"

// ---- the handles: every name that is NOT an upstream c.Struct and appears BARE
// ---- in a trampoline row.  In `clang-c/Index.h` each is `typedef void *NAME`.
@@HANDLES@@

// ---- the by-value records, rebuilt from upstream's `register_fields`: name,
// ---- ctypes type and byte offset, all of them CPython's own measurements.
@@STRUCTS@@

// ---- records only ever used THROUGH a pointer.  An incomplete type is the whole
// ---- declaration a `T *` parameter needs.
@@PTRONLY@@

// ---- the ENUMS, one per `enum_<name>` dict upstream declares.  An enum is four
// ---- bytes BY VALUE and not an opaque pointer, so it must not also appear in the
// ---- handle list above; the two sets are separate derivations and this is where
// ---- they meet.
@@ENUMS@@

// ---- the prototypes, one per row that the PINNED dylib EXPORTS -------------
@@PROTOS@@

// ---- the carriers ------------------------------------------------------------

#define CF_UNTAG(t) (term_aux(t) == TAG_PAK ? io_hand_v(t) : 0)
#define CF_ROW(...) fprintf(stderr, "SAW " __VA_ARGS__)
#define CF_CAP @CAP@

static void *cf_box(const void *p, size_t n) {
  void *q = io_mem(malloc(n));
  memcpy(q, p, n);
  return q;
}

// THE WALK, bend `String` -> `const char *`.  A ZERO Term is the fixture's own
// filename: the 21 `c.POINTER[ctypes.c_char]` PARAMETERS are declared as a
// `Ptr_CChar` value in bend, and a nullary Data constructor is a zero Term, so the
// substitute is recorded in the row and not hidden in this comment.
static const char *cf_cstr(Env e, Term t) {
  u64 n = 0;
  const char *p;
  if (t == 0) return CL_FIXTURE_NAME;
  p = io_cbuf(e, t, &n, CID(SCon));
  return p == NULL ? "" : p;
}

// THE WALK, `const char *` -> bend `String`, and the row.
static Term cf_text(Env e, const char *p) {
  size_t n = p == NULL ? 0 : strlen(p);
  if (n > CF_CAP) n = CF_CAP;
  return io_str(e, p == NULL ? "" : p, n);
}

static Term cf_num(unsigned long long v) { return (Term)(u64)v; }

static Term cf_flt(double d) {
  union { double d; u64 u; } b;
  b.d = d;
  return (Term)b.u;
}

// ---- the fixture: a real clang index over `fixture.h`'s own bytes ---------
//
// The walk RETURNS Recurse.  Continue stops at `Pair` and finds no field, which
// is how the fixture's fields went missing once already (`libclang-ffi.c`, CL-2).
static CXIndex cf_index_x;
static CXTranslationUnit cf_tu_x;
static CXCursor cf_hit_x;

// CXChildVisit_Recurse is 2 in `clang-c/Index.h` and the enum above declares only
// value 0, so the walk returns the NUMBER: CL-2 in `libclang-ffi.c` measured that
// Continue stops at `Pair` and finds no field at all.
static CXChildVisitResult cf_visit(CXCursor c, CXCursor p, CXClientData d) {
  const char *s = clang_getCString(clang_getCursorSpelling(c));
  if (s != NULL && strcmp(s, "@SEL@") == 0) cf_hit_x = c;
  return (CXChildVisitResult)2;
}

static CXIndex cf_index(void) {
  if (cf_index_x == NULL) cf_index_x = clang_createIndex(0, 0);
  return cf_index_x;
}

static CXTranslationUnit cf_tu(void) {
  if (cf_tu_x == NULL) {
    CXUnsavedFile uf = { CL_FIXTURE_NAME, CL_FIXTURE_SRC, (unsigned long)strlen(CL_FIXTURE_SRC) };
    cf_tu_x = clang_parseTranslationUnit(cf_index(), CL_FIXTURE_NAME, 0, 0, &uf, 1, 0);
    CF_ROW("anchor tu=%p\n", (void *)cf_tu_x);
  }
  return cf_tu_x;
}

static CXCursor cf_cursor(void) {
  if (cf_hit_x.data[0] == NULL) {
    cf_tu();
    clang_visitChildren(clang_getTranslationUnitCursor(cf_tu_x), cf_visit, 0);
    CF_ROW("anchor cursor kind=%u found=%d\n", (unsigned)cf_hit_x.kind, cf_hit_x.data[0] != NULL);
  }
  return cf_hit_x;
}

static CXType cf_type(void) { return clang_getCursorType(cf_cursor()); }
static CXFile cf_file(void) { return clang_getFile(cf_tu(), CL_FIXTURE_NAME); }
static CXString cf_string(void) { return clang_getTypeSpelling(cf_type()); }
static CXSourceLocation cf_loc(void) { return clang_getCursorLocation(cf_cursor()); }
static CXSourceRange cf_range(void) { return clang_getCursorExtent(cf_cursor()); }
static CXTUResourceUsage cf_usage(void) { return clang_getCXTUResourceUsage(cf_tu()); }

// ---- the rows the PINNED dylib does NOT export, measured with `nm -gU` and
// ---- not recalled.  libclang 17.0.0 dropped them; a declaration of one would
// ---- not LINK, so the row refuses and says so.
@@ABSENT@@

@@RUNS@@

@@REGS@@

// ---- THE ANCHOR: the `const char*` WALK, both directions, on a real call ----
//
// bend supplies the filename as a String; `io_cbuf` turns it into the `char *`
// libclang parses, and `clang_getCString` comes back the other way through
// `io_str`.  Both halves are the same runtime code the other 21 `cstr` rows use,
// and this is the one row where the bend side hands over a real `String` rather
// than a zero the carriers substitute.
Term Tramp_anchor_run(Env e, Term *f, IoWork* w) {
  (void)w;
  // `f[0]` must be an `SCon` cell and not merely a pointer: `term_aux(f[0])` is the
  // cons id and the walk below is what `io_cbuf` expects.  A hand-checked run
  // printed it, and the reason it is NOT a row here is that it is a property of
  // the RUNTIME's marshalling, which is either right for all 21 `cstr` rows or
  // wrong for all 21 -- 21 identical rows would be 21 of the same fact.
  if (term_aux(f[0]) != CID(SCon)) { CF_ROW("anchor argument is not an SCon\n"); }
  const char *nm = cf_cstr(e, f[0]);
  CXIndex ix = clang_createIndex(0, 0);
  CXUnsavedFile uf = { (char *)CL_FIXTURE_NAME, (char *)CL_FIXTURE_SRC, (unsigned long)strlen(CL_FIXTURE_SRC) };
  CXTranslationUnit tu = clang_parseTranslationUnit(ix, nm, 0, 0, &uf, 1, 0);
  CF_ROW("anchor name=%s tu=%p\n", nm == NULL ? "(null)" : nm, (void *)tu);
  if (tu == NULL) return cf_text(e, "anchor: parse failed");
  const char *spell = clang_getCString(clang_getTranslationUnitSpelling(tu));
  CF_ROW("anchor spelling=%s\n", spell == NULL ? "(null)" : spell);
  clang_disposeTranslationUnit(tu);
  return cf_text(e, spell == NULL ? "anchor: (null)" : spell);
}

static void __attribute__((constructor)) cf_drive_use(void) {
#ifdef CID(Tramp_anchor)
  io_eff(CID(Tramp_anchor), Tramp_anchor_run, 0);
#endif
}
'''


def _args(r):
    return ", ".join("p%d" % i for i in range(len(r["ps"])))


def _sig(r):
    """`name[class,...] arg=<f> arg=<f>` -- the one format string every row uses."""
    cls = ",".join([ROW_CLASS[c] for _n, _b, _t, c, _y in r["ps"]]) or "void"
    # the parameter NAME goes into the format string as TEXT, so it is spliced in
    # here and never survives as a conversion.  A draft emitted `%%s=` instead --
    # right, because C prints `%%` as `%`, so the row read `%s=0` instead of
    # `excludeDeclarationsFromPCH=0` and looked like a conversion it did not have.
    got = " ".join("%s=%s" % (pn, ROW_FMT[c]) for pn, _b, _t, c, _y in r["ps"])
    fmt = "%s [%s] %s" % (r["name"], cls, got)
    vals = []
    for i, (_n, _b, t, c, _y) in enumerate(r["ps"]):
        if c == abi.CSTR:
            vals.append('p%d == NULL ? "(null)" : p%d' % (i, i))
        elif c == abi.INT:
            vals.append("(unsigned long long)p%d" % i)
        elif c == abi.BOX:
            # the BOX's first word, NOT its address.  An address is a malloc result
            # and differs between two runs of one binary; the first word is `kind`
            # for a CXCursor and `int_data` for the rest, and it is 0 for a record
            # the fixture never found and non-zero for one it did.  With the address
            # here, `PLANT-sel` moved 0 rows because every masked row was identical.
            # The SUBSTITUTED value, not the frame's.  Printing `q%d` printed the
            # box bend handed over -- always NULL, because a nullary Data
            # constructor is a zero Term -- so every row read `C=0` whatever the
            # fixture found, `PLANT-sel` moved 0 rows, and the fixture was invisible
            # to the whole instrument.  `p%d` is the local AFTER the carrier
            # substituted, so its first word is the record libclang was given.
            vals.append("(unsigned)*(unsigned *)&p%d" % i)
        else:
            vals.append("(void *)p%d" % i)
    return fmt, vals


def run_body(r):
    L = ["Term %s_run(Env e, Term *f, IoWork* w) {" % r["name"]]
    fmt, vals = _sig(r)
    for i, (pn, _b, ct, cl, _y) in enumerate(r["ps"]):
        if cl == abi.BOX:
            L.append("  void *q%d = (%s *)CF_UNTAG(f[%d]);" % (i, ct, i))
            fix = FIXTURE_BOX.get(ct)
            L.append("  %s p%d = q%d != NULL ? *(%s *)q%d : (%s)%s;"
                     % (ct, i, i, ct, i, ct, fix if fix else "{0}"))
        elif cl == abi.PTR and "(*)" in ct:
            L.append("  %s = (%s)(uintptr_t)CF_UNTAG(f[%d]);"
                     % (param_decl(ct, "p%d" % i), ct, i))
        elif cl == abi.PTR:
            L.append("  %s p%d = (%s)CF_UNTAG(f[%d]);" % (ct, i, ct, i))
            if ct in FIXTURE_PTR:
                L.append("  if (p%d == NULL) p%d = %s;" % (i, i, FIXTURE_PTR[ct]))
        elif cl == abi.CSTR:
            L.append("  const char *p%d = cf_cstr(e, f[%d]);" % (i, i))
        elif cl == abi.FLT:
            L.append("  { union { u64 u; double d; } b; b.u = (u64)f[%d]; p%d = b.d; }" % (i, i))
        elif "(*)" in ct:
            L.append("  %s = (%s)(uintptr_t)CF_UNTAG(f[%d]);"
                     % (param_decl(ct, "p%d" % i), ct, i))
        else:
            L.append("  %s p%d = (%s)(%s)f[%d];"
                     % (ct, i, ct, "u32" if ct in ("int", "unsigned") else "u64", i))
    av = (", " + ", ".join(vals)) if vals else ""
    rc, ct = r["rcls"], r["rct"]
    call = "%s(%s)" % (r["name"], _args(r))
    if rc == abi.VOID:
        L.append('  CF_ROW("%s\\n"%s);' % (fmt, av))
        L.append("  %s;" % call)
        L.append("  return term_pak(CID(Unit), 0);")
    elif rc == abi.CSTR:
        L.append("  const char *r = %s;" % call)
        L.append('  CF_ROW("%s -> cstr=%%s\\n"%s, r == NULL ? "(null)" : r);' % (fmt, av))
        L.append("  return cf_text(e, r);")
    elif rc == abi.FLT:
        L.append("  double r = %s;" % call)
        L.append('  CF_ROW("%s -> double %%.1f\\n"%s, r);' % (fmt, av))
        L.append("  return cf_flt(r);")
    elif rc == abi.BOX:
        L.append("  %s r = %s;" % (ct, call))
        # The answer stays an ADDRESS, and that is a DELIBERATE blind spot, not an
        # oversight.  The first word instead (measured, twice) makes the row
        # NON-DETERMINISTIC for the 40 `CXString` answers, whose first word IS a
        # libclang pointer: DISARM-comment then moved 64 rows and reported FAIL,
        # which is a correct report of a non-deterministic instrument.  So the
        # address is printed and MASKED by the gate, and what makes the rows
        # deterministic is the mask and not the row.
        L.append('  CF_ROW("%s -> box %%p\\n"%s, (void *)&r);' % (fmt, av))
        L.append("  return io_hand((u64)cf_box(&r, sizeof r));")
    elif rc == abi.PTR:
        L.append("  %s r = %s;" % (ct, call))
        L.append('  CF_ROW("%s -> ptr %%p\\n"%s, (void *)r);' % (fmt, av))
        L.append("  return io_hand((u64)r);")
    else:
        L.append("  %s r = %s;" % (ct, call))
        L.append('  CF_ROW("%s -> int %%lld\\n"%s, (long long)r);' % (fmt, av))
        L.append("  return cf_num((unsigned long long)r);")
    L.append("}")
    return "\n".join(L)


def struct_order(struct_c):
    """A record whose field POINTS at another record needs that one declared first:
    `CXTUResourceUsage` names `CXTUResourceUsageEntry`, and alphabetical order puts
    the user before the pointee, so `cc` reported an unknown type name for a
    declaration this file itself emits two lines later."""
    names = set(struct_c)
    order, seen = [], set()

    def deps(k):
        # ANY mention counts, not only `T *`: `struct_CXCursorAndRangeVisitor` has
        # a `CXSourceRange visit(...)` field BY VALUE, and that is the dependency
        # that put a record after its own user and named an unknown type.
        return {n for n in re.findall(r"\b(\w+)\b", struct_c[k])
                if n in names and n != k}

    def visit(k):
        if k in seen:
            return
        seen.add(k)
        for d in sorted(deps(k)):
            visit(d)
        order.append(k)

    for k in sorted(names):
        visit(k)
    return order


def param_decl(ctype, name):
    """`void (*)(void *)` + `p0` is not a declaration; `void (*p0)(void *)` is.

    A function-pointer parameter needs the NAME INSIDE the parentheses, so the
    name cannot simply be appended the way every other type takes it.
    """
    m = re.fullmatch(r"(.+) \(\*\)\((.*)\)", ctype)
    if m:
        return "%s (*%s)(%s)" % (m.group(1), name, m.group(2))
    return "%s %s" % (ctype, name)


def emit(rows, struct_c, handles, ptr_only, enums, sel):
    protos = "\n".join("extern %s %s(%s);" % (
        r["rct"], r["name"],
        ", ".join(param_decl(t, "p%d" % i) for i, (_n, _b, t, _c, _y) in enumerate(r["ps"])) or "void")
        for r in rows if r["ok"])
    # A FUNCTION per absent row, because a bare statement is not C at file scope.
    # The answer is `(Term)0`, which is the nullary value of every ABI type this
    # product mints -- `term_pak(CID(U32), 0)` was tried first and does NOT compile,
    # because bend emits no id for a type no law's argument mentions (CF-1 again).
    absent = "\n\n".join(
        "Term %s_run(Env e, Term *f, IoWork* w) {\n"
        '  (void)e; (void)f; (void)w; CF_ROW("%s absent from the pinned dylib\\n");\n'
        "  return (Term)0;\n}" % (r["name"], r["name"])
        for r in rows if not r["ok"])
    runs = "\n\n".join(run_body(r) for r in rows if r["ok"])
    # ALL 324, the four absent ones included: a `_run` with no registration leaves
    # `io_eff_rows[cid].run` NULL and bend answers `an alien request`, which reads
    # as a fault in the row and is really a missing line in this file.
    # ONE `#ifdef` PER REGISTRATION.  See the header: bend emits a `CID` only for
    # a law something CALLS, so `io_eff(CID(x), ...)` for an unreached law is an
    # undeclared identifier and the file does not compile.  `#ifdef` is the guard
    # bend's own guide documents (`references/bend/guide/EFFECTS.md:39`).
    regs = ("static void __attribute__((constructor)) cf_use(void) {\n"
            + "\n".join("#ifdef CID(%s)\n  io_eff(CID(%s), %s_run, 0);\n#endif"
                        % (r["name"], r["name"], r["name"])
                        for r in rows) + "\n}\n")
    return (HEADER.replace("@@HANDLES@@", "\n".join("typedef void *%s;" % n for n in handles))
            .replace("@@STRUCTS@@", "\n\n".join(struct_c[k] for k in struct_order(struct_c)))
            .replace("@@PTRONLY@@", "\n".join("typedef struct %s %s;" % (n, n) for n in ptr_only))
            .replace("@@ENUMS@@", "\n".join(
                "typedef enum { %s_0 = 0 } %s;" % (n, n) for n in sorted(enums)))
            .replace("@@PROTOS@@", protos)
            .replace("@@ABSENT@@", absent)
            .replace("@@RUNS@@", runs)
            .replace("@@REGS@@", regs)
            .replace("@SEL@", sel)
            .replace("@CAP@", str(CSTR_CAP)))


# ------------------------------------------------------------------ the bend
DEF_RE = re.compile(r"def (clang_\w+)\(([^)]*)\) -> Maybe<&2, (\w+)>:\n  None\{\}\n")


def bodies(text, rel=IMPORT_REL):
    """Replace every `None{}` trampoline body with a `law` + `import`.

    The old text is read OUT OF THE PRODUCT, so the parameter NAMES and the ABI
    types in the new `law` are the product's own and cannot drift from them.  The
    marker is `-> Maybe<&2,`, which the new text does not contain, so this is
    idempotent and `--check` can say so.

    One more law comes with the fill, at the foot of the trampolines:
    `Tramp_anchor` is the one row where bend hands over a real `String`, so the
    `const char*` walk runs on bytes bend made.  It does not collide with the ten
    FFI-lane laws further down, which are named after what they MEASURE
    (`Type_report`, `Record_words`, ...).

    IT IS THE GATE, NOT THE PRODUCT, THAT CALLS THE 324.  bend emits a `CID` only
    for a law something CALLS, so an unreached law has no id and its `io_eff`
    registration cannot compile -- hence the `#ifdef` in the C.  A body is
    therefore executed only where something reaches its law, and reaching all 324
    needs a 324-arm `match` over an index: `.agents/slop/clangfill/gate.py`
    generates it, because a `do` block cannot call 324 different arities.
    """
    n = [0]

    def sub(m):
        name, params, ret = m.group(1), m.group(2), m.group(3)
        bits = [p.strip() for p in params.split(",")] if params else []
        names = [b.split(":")[0].strip() for b in bits]
        # the law's signature is over TYPES (`law Type_report: U32 -> IO(String)`),
        # not over the parameter names; a NAME there is `expected : a defined name`.
        types = [b.split(":", 1)[1].strip() for b in bits]
        sig = "".join("%s -> " % t for t in types)
        n[0] += 1
        return ("law %s:\n  %sIO(%s)\n\ndef %s(%s):\n  import \"%s\"\n"
                % (name, sig, ret, name, ", ".join(names), rel))

    out = DEF_RE.sub(sub, text)
    return out, n[0]


DRIVE_LAWS = '''# ---- THE FILL: what replaced the 324 `None{}` bodies, and how it is measured.
#
# Every trampoline above is now a `law` with its ONE ABI parameter types and its
# ONE return type, over the SAME names `ag-emit.bend` emitted, with a body that is
# one `import` of `.agents/slop/clangshim/libclang-tramp.c`.  That file is
# GENERATED by `.agents/slop/clangfill/fill.py` from the SAME
# `.agents/slop/ag-libclang.tramp` rows, so a bend signature and a C declaration
# have one source; `--check` on both scripts says `IN SYNC` or neither happened.
#
# ONE WORD IS NOT ENOUGH FOR A STRUCT, so `CXCursor`, `CXType`, `CXString`,
# `CXSourceLocation`, `CXSourceRange`, `CXIdxLoc`, `CXToken` and `CXTUResourceUsage`
# travel as a C-heap BOX whose address is a bend HANDLE.  A `const char*` is a
# WALK in both directions -- `io_cbuf` out of a bend String, `io_str` back into
# one -- and both are bend RUNTIME code, already in every emitted program.
#
# 320 of the 324 names are EXPORTED by the pinned dylib (`nm -gU`) and got a real
# call.  The other FOUR are not, and a declaration of one would not link:
# `clang_getOffsetOfBase`, `clang_getTypePrettyPrinted`, `clang_visitCXXBaseClasses`
# and `clang_isBeforeInTranslationUnit`.  Their `_run` REFUSES and says so.  That
# is version skew against libclang 17.0.0, not a language wall.
#
# THE ONE EXTRA LAW.  `Tramp_anchor` is the row where bend hands over a real
# `String` filename, so the `const char*` walk runs on bytes bend made and a real
# `clang_parseTranslationUnit` answers with a real translation unit.

law Tramp_anchor:
  String -> IO(String)

def Tramp_anchor(name):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

'''


def with_drive(text):
    """Put the two fill laws in, in ONE place whatever else has been appended.

    `ag-emit.bend` defines `emit_tail` and never calls it, so the raw emitter
    output has NO `main` at all: the first `main` in the product arrives with the
    FFI lane.  Anchoring on `def main()` therefore inserted on the SECOND pass and
    not the first, and `--check` failed on a file that was correct -- which is the
    whole failure mode `apply-port-lane.py --check` exists to catch, caught on the
    generator instead.  The anchor is the lane, which the applier appends first.
    """
    if "# ---- THE FILL:" in text:
        return text
    anchor = "# ---- THE FFI LANE"
    if anchor in text:
        return text.replace(anchor, DRIVE_LAWS + anchor, 1)
    return text.rstrip("\n") + "\n\n" + DRIVE_LAWS


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    rows, struct_c, size_of, handles, ptr_only, enums, syms = plan()
    sel = "a"
    text = emit(rows, struct_c, handles, ptr_only, enums, sel)
    have = PRODUCT_C.read_text() if PRODUCT_C.is_file() else ""
    ok = sum(1 for r in rows if r["ok"])
    print("rows %d  exported %d  absent %d  handles %d  byval %d  ptr-only %d  enums %d"
          % (len(rows), ok, len(rows) - ok, len(handles), len(struct_c), len(ptr_only),
             len(enums)))
    print("c-locers per class:", {k: sum(1 for r in rows for _n, _b, _t, c, _y in r["ps"] if c == k)
                                  for k in (abi.INT, abi.FLT, abi.CSTR, abi.PTR, abi.BOX)})
    if a.check:
        print("IN SYNC" if text == have else "OUT OF SYNC")
        return 0 if text == have else 1
    PRODUCT_C.write_text(text)
    print("%s: %d -> %d bytes" % (PRODUCT_C.relative_to(REPO), len(have), len(text)))
    return 0


if __name__ == "__main__":
    sys.exit(main())