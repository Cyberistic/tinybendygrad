#!/usr/bin/env python3
"""clangshim-gen.py -- derive ONE libclang shim from the port's own committed
bindings, and report what it cost per function.

THE REFUSAL UNDER TEST
  tinybendygrad/runtime/autogen/libclang.bend:15-16 says bend "has no
  per-function FFI: its only form is a whole-operation effect -- a `def`
  returning IO plus an `import` of a C file -- which for this header would mean
  324 C files and 324 hand-written shims."
  Both halves are testable. This file is the test.

INPUTS (all committed, all READ-ONLY; nothing here writes the repo tree)
  .agents/slop/ag-libclang.tramp        324 rows: name|retbind|rethint|(pname|pbind|phint)*
  tinygrad/runtime/autogen/libclang.py  TypeAlias graph + struct SIZE
  tinybendygrad/runtime/autogen/libclang.bend   the Bend signatures (read for the
                                       cross-check, and for the param NAMES)
The ctypes resolver is IMPORTED from ffi-port-cost.py, never re-implemented.

MARSHALLING POLICY -- one rule, no per-function decisions, two Bend types
  C class                     Bend law        C side
  --------------------------------------------------------------------------
  int/uint/char/short (32b)   Nat             (T)(u32)f[i]     -> (u64)r
  any pointer, void*          Nat             ((T)PTR(f[i]))    -> (uintptr_t)r
  by-value struct, N bytes    Nat (address)   SBY(T,i) local   -> park(&r)
  const char*  PARAMETER      String          bend_cstr walk   (written once)
  const char*  RETURN         String          io_str           (written once)
  void                        Unit            call, term_pak(Unit,0)
  int64/uint64/size_t/double  BLOCKED -- no Bend type past the Nat window
  function pointer            BLOCKED -- Bend has no function value

  A by-value struct is an OPAQUE union of the right SIZE with 8-byte alignment,
  so it can be passed and returned over the ABI without the field layout. That is
  the whole convention and it is ~1 line per struct type. It is also the honest
  limit: a shim can hand a struct across, and cannot read a field of it.

USAGE
  clangshim-gen.py --out $DIR          writes $DIR/shim.c and $DIR/shim.bend
  clangshim-gen.py --list             the census, no files written
"""

from __future__ import annotations

import argparse
import importlib.util
import re
import sys
from collections import Counter
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
_spec = importlib.util.spec_from_file_location(
    "ffi_port_cost", REPO / ".agents" / "slop" / "ffi-port-cost.py")
fpc = importlib.util.module_from_spec(_spec)
sys.modules["ffi_port_cost"] = fpc
_spec.loader.exec_module(fpc)

TRAMP = REPO / ".agents" / "slop" / "ag-libclang.tramp"
PYBIND = REPO / "tinygrad" / "runtime" / "autogen" / "libclang.py"
BEND = REPO / "tinybendygrad" / "runtime" / "autogen" / "libclang.bend"

# resolved ctypes spelling -> (class, C type spelling, Bend law type)
VOID, INT, PTR, BYVAL, CB, I64, F64, STRI, STRO = (
    "VOID", "INT", "PTR", "BYVAL", "CB", "I64", "F64", "STR_IN", "STR_OUT")

# ctypes spelling -> C spelling, and C spelling -> width. ONE table, because two
# is how a classifier ends up reporting a clean 308 while emitting
# `extern void* clang_getFile(..., ctypes.c_char*)` -- a spelling no C compiler
# accepts, which is exactly what the first run of this file did.
_PRIM = {
    "ctypes.c_void_p": "*void", "ctypes.c_char": "char",
    "ctypes.c_wchar": "wchar_t", "ctypes.c_bool": "_Bool",
    "ctypes.c_int8": "signed char", "ctypes.c_uint8": "unsigned char",
    "ctypes.c_int16": "short", "ctypes.c_uint16": "unsigned short",
    "ctypes.c_int32": "int", "ctypes.c_uint32": "unsigned",
    "ctypes.c_int": "int", "ctypes.c_uint": "unsigned",
    "ctypes.c_int64": "long long", "ctypes.c_uint64": "unsigned long long",
    "ctypes.c_ssize_t": "long", "ctypes.c_size_t": "unsigned long",
    "ctypes.c_float": "float", "ctypes.c_double": "double",
    "void": "*void", "void*": "*void",
    "int": "int", "unsigned": "unsigned", "unsigned int": "unsigned",
    "long": "long", "unsigned long": "unsigned long",
    "long long": "long long", "unsigned long long": "unsigned long long",
    "size_t": "unsigned long", "ssize_t": "long",
}
_BITS = {"char": 8, "signed char": 8, "unsigned char": 8, "_Bool": 8,
         "wchar_t": 32, "short": 16, "unsigned short": 16, "int": 32,
         "unsigned": 32, "float": 32, "long": 64, "unsigned long": 64,
         "long long": 64, "unsigned long long": 64, "double": 64}


_SIZE_RE = re.compile(r"\[(?P<n>\d+)\]$")


def canon(t: str) -> str:
    """A resolved ctypes spelling as a C spelling. Pointers canonicalise too:
    `c.POINTER[size_t]` resolves to `*ctypes.c_uint64`, which is a pointer to a
    64-bit integer and not an unknown type; and `c.POINTER[CXSourceLocation]`
    resolves to `*CXSourceLocation[24]`, whose `[24]` is the SIZE of a
    by-value struct and must not survive into a pointer type."""
    t = " ".join(t.split())
    if t.startswith("*"):
        # RECURSIVE: ctypes.POINTER[c_char] resolves to `**ctypes.c_char`
        # wherever the pointee is itself a POINTER spelling, and a non-recursive
        # strip leaves `ctypes.` to reach the C emitter as a type name.
        return "*" + canon(_SIZE_RE.sub("", t[1:].strip()))
    return _PRIM.get(t, t)


_BEND_KEYWORDS = {"def", "type", "law", "match", "case", "do", "return", "for",
                  "exs", "where", "is", "import", "Type", "Data", "Kind",
                  "Quant"}


def bend_name(n: str) -> str:
    """A binding parameter's Bend-side label.

    The parameter NAME is only ever a Bend binder -- the C side takes its
    arguments positionally out of `f[]` -- so a keyword collision is a rename
    here and nothing else. MEASURED over all 138 distinct parameter names in the
    trampoline: exactly one collides, `type`, in `clang_Type_getObjCEncoding`.
    (agent-core.md records two collisions among tinygrad DEF names; this is a
    different namespace and it has its own list.)
    """
    return "_" + n if n in _BEND_KEYWORDS else n


def classify(t: str, is_ret: bool):
    """One row of the policy table. Returns (class, ctype, bend_type).

    A function-pointer PARAMETER is NOT blocked: it crosses as a Nat holding the
    address of a shim-owned stub, one stub per distinct callback signature. The
    stub reports nothing back (it counts, or returns CXChildVisit_Continue), so
    the call is real and the answer goes through the ordinary return channel. A
    function-pointer RETURN would need a callback Bend cannot make, and no row
    in these 324 has one.
    """
    t = canon(t)
    if t in ("None", "", "void"):
        return VOID, "void", "Unit"
    if t == "*char":
        return (STRO, "char*", "String") if is_ret else (STRI, "char*", "String")
    if t == "*void":
        return PTR, "void*", "Nat"
    if t.startswith("*"):
        # lstrip: `c.POINTER[c.POINTER[c_char]]` is `char**`, and `t[1:]` would
        # spell it `*char*` -- a type no C compiler accepts.
        return PTR, t.lstrip("*") + "*", "Nat"
    if t.startswith("CB:"):
        # The ctype is void*: a callback crosses as one Term word holding a
        # stub's address, and the stub's REAL type comes from cb_sig, which
        # parses c.CFUNCTYPE[R, [A, B]] itself.
        #
        # The tail after "CB:" is NOT usable. ffi-port-cost.py's Types.resolve
        # matches `c\.CFUNCTYPE\[.*\[(.+)\]\]`, and for a MULTI-argument
        # CFUNCTYPE that group is the ARGUMENT LIST, so it resolves
        # CXInclusionVisitor to
        #   CB:ctypes.c_void_p, c.POINTER[CXSourceLocation], ctypes.c_uint32, ...
        # -- a comma-separated string no C compiler accepts. Its COUNTS are
        # unaffected (CB was never blocked), so the 307/17 it reports stands;
        # its per-argument spelling is unusable, and that is a second defect in
        # the committed cost tool beside the one named in libclang.bend's header.
        return CB, "void*", "Nat"
    m = re.match(r"^(\w+)\[(\d+)\]$", t)
    if m:
        return f"BYVAL{m.group(2)}", m.group(1), "Nat"
    if t in ("float", "double"):
        return F64 if t == "double" else INT, t, "Nat"
    if t in _BITS:
        return (I64 if _BITS[t] > 32 else INT), t, "Nat"
    raise SystemExit(f"UNRESOLVED ctype {t!r} -- the classifier must be extended, "
                     f"not guessed")


_CB_RE = re.compile(r"^c\.CFUNCTYPE\[(?P<ret>.*?), \[(?P<args>.*)\]\]$")


def cb_sig(raw: str, T) -> tuple[str, str, str]:
    """A callback binding -> (C type name, stub return type, stub parameter list).

    The stub must have the callee's EXACT signature, because libclang CALLS it:
    a wrong arity or a wrong return is an ABI mismatch, not a slow path. The
    binding is either the alias NAME (`CXCursorVisitor`) or the spelling itself
    (`c.CFUNCTYPE[None, [ctypes.c_void_p]]`), and c.CFUNCTYPE[R, [A, B]] carries
    both halves, so the stub is derived from the same TypeAlias graph rather than
    guessed. An inline spelling has no alias name, so the stub is named after the
    function and parameter that carry it.
    """
    spelled = T.alias.get(raw.strip(), raw.strip())
    m = _CB_RE.match(spelled)
    if not m:
        raise SystemExit(f"callback spelling {spelled!r} is not c.CFUNCTYPE[...]")
    name = raw.strip() if re.match(r"^\w+$", raw.strip()) else raw.strip()
    rcl, _, _ = classify(T.resolve(m.group("ret")), True)
    if rcl == VOID:
        rs = "void"
    elif rcl == INT:
        rs = "unsigned"
    else:
        raise SystemExit(f"callback return class {rcl} has no stub form")
    ps = []
    for i, a in enumerate(x for x in m.group("args").split(",") if x.strip()):
        acl, act, _ = classify(T.resolve(a), False)
        if acl.startswith("BYVAL") or acl == PTR:
            ps.append(f"{act} a{i}")
        elif acl == INT:
            ps.append(f"{act} a{i}")
        else:
            raise SystemExit(f"callback arg class {acl} has no stub form")
    return name, rs, ", ".join(ps)


def rows():
    for line in TRAMP.read_text().splitlines():
        if not line.strip():
            continue
        f = line.split("|")
        assert len(f) >= 3 and (len(f) - 3) % 3 == 0, line
        yield {"name": f[0], "ret": f[1], "rethint": f[2],
               "params": [(f[3 + 3 * i], f[4 + 3 * i], f[5 + 3 * i])
                          for i in range((len(f) - 3) // 3)]}


def plan(T):
    """Resolve every row into the policy table, and record why one is blocked."""
    out = []
    for r in rows():
        rc, rct, rb = classify(T.resolve(r["ret"]), True)
        ps = [classify(T.resolve(p[1]), False) for p in r["params"]]
        blockers = [c for c in [rc] + [p[0] for p in ps] if c in (I64, F64)]
        cbs, cbname = {}, [None] * len(r["params"])
        for i, (pc, p) in enumerate(zip([q[0] for q in ps], r["params"])):
            if pc == CB:
                nm, rs, psig = cb_sig(p[1], T)
                nm = nm if re.match(r"^\w+$", nm) else f"{r['name']}_{p[0]}"
                cbs[nm] = (rs, psig)
                cbname[i] = nm
        out.append({"name": r["name"], "hint": r["rethint"],
                    "rct_raw": T.resolve(r["ret"]),
                    "pct_raw": [T.resolve(p[1]) for p in r["params"]],
                    "pname": [p[0] for p in r["params"]],
                    "rc": rc, "rct": rct, "rb": rb,
                    "pc": [p[0] for p in ps], "pct": [p[1] for p in ps],
                    "pb": [p[2] for p in ps],
                    "cbs": cbs, "cbname": cbname,
                    "blockers": sorted(set(blockers))})
    return out


# --------------------------------------------------------------------------
# emission
# --------------------------------------------------------------------------

# THE CALL CENSUS, and the fork it needs.
#
# MEASURED (STAGE3.md, three laws): bend emits a `#define CID_<k>` only for a
# foreign def REACHABLE FROM main. An `io_eff(CID(k), ...)` for a law main never
# calls is an UNDECLARED macro in the emitted C. So a census cannot dispatch
# through a table and a helper: main must call every law DIRECTLY, or there is
# no `bend -o` output at all -- a law with no row in main is a TODO.
#
# MEASURED: laws called with a zero argument WILL crash -- most want a live
# CXIndex or CXTranslationUnit -- so each _run forks. A forked heap is
# copy-on-write, so a Term the CHILD allocated is not a Term in the PARENT:
# every answer travels back through a pipe as bytes and the parent rebuilds it.
# That is why a `const char*` return is piped as BYTES and turned into a Bend
# String in the parent: the census does not report an empty string for a library
# that answered.
SHIM_FORK = r"""


static void shim_put(int fd, const void* p, size_t n) {
  while (n > 0) {
    ssize_t k = write(fd, p, n);
    if (k <= 0) break;
    p = (const char*)p + k;
    n -= (size_t)k;
  }
}

static int shim_take(int fd, void* p, size_t n) {
  char* q = (char*)p;
  while (n > 0) {
    ssize_t k = read(fd, q, n);
    if (k <= 0) break;
    q += k;
    n -= (size_t)k;
  }
  return n == 0;
}

static pid_t shim_spawn(int fd[2]) {
  fflush(NULL);   // fork() duplicates an unflushed stdout buffer into the
                  // child, and every _run forks: without this the run prints
                  // each line once per fork that followed it.
  if (pipe(fd) != 0) return -1;
  pid_t pid = fork();
  if (pid < 0) return -1;
  if (pid == 0) {
    close(fd[0]);
    return 0;
  }
  close(fd[1]);
  return pid;
}

// A word answer: one Term's worth, read back from the child. *why names the
// child's fate so a failure is ATTRIBUTED rather than counted:
//   0 the call returned       1 the child exited non-zero
//   2 the child took a signal 3 the pipe delivered nothing
static Term shim_word(pid_t pid, int fd, int* why, int* st_out) {
  u64 val = 0;
  int got = shim_take(fd, &val, sizeof val);
  int st = 0;
  waitpid(pid, &st, 0);
  *st_out = st;
  *why = WIFEXITED(st) ? (WEXITSTATUS(st) == 0 ? 0 : 1)
                       : (WIFSIGNALED(st) ? 2 : 1);
  if (!got && *why == 0) *why = 3;
  return (Term)val;
}

// A string answer: the BYTES, rebuilt in the parent's heap.
static Term shim_text(Env e, pid_t pid, int fd, int* why, int* st_out) {
  u64 n = 0;
  int got = shim_take(fd, &n, sizeof n);
  char buf[65536];
  if (n > sizeof buf) n = sizeof buf;
  int body = got && (n == 0 || shim_take(fd, buf, (size_t)n));
  int st = 0;
  waitpid(pid, &st, 0);
  *st_out = st;
  *why = WIFEXITED(st) ? (WEXITSTATUS(st) == 0 ? 0 : 1)
                       : (WIFSIGNALED(st) ? 2 : 1);
  if (!body && *why == 0) { *why = 3; return io_str(e, "", 0); }
  return io_str(e, buf, n);
}

// No answer: only the fact that the call returned.
static Term shim_none(pid_t pid, int fd, int* why, int* st_out) {
  int st = 0;
  waitpid(pid, &st, 0);
  *st_out = st;
  *why = WIFEXITED(st) ? (WEXITSTATUS(st) == 0 ? 0 : 1)
                       : (WIFSIGNALED(st) ? 2 : 1);
  return term_pak(CID(Unit), 0);
}

// g_why is the per-row attribution and g_st the child's RAW wait status, so a
// failure names its own cause instead of being a count.
//   0 the call returned            1 the child exited non-zero (status in g_st)
//   2 the child took a signal      3 the pipe delivered nothing
//   4 the law was never called
static Term g_ok[CLANGSHIM_ROWS];
static int g_why[CLANGSHIM_ROWS];
static int g_st[CLANGSHIM_ROWS];
"""

# The census READER. It calls nothing: main already called every law directly
# (see the note above), and each _run recorded its own outcome in g_ok. Reading
# the flag here rather than out of the _run's return value is what keeps the row
# honest for a void-returning law, whose answer carries no information at all.
CENSUS_RUN = r"""
Term census_run(Env e, Term* f, IoWork* w) {
  u32 i = (u32)f[0];
  if (i >= CLANGSHIM_ROWS) return (Term)0;
  fprintf(stderr, "CALL %-52s %-26s status=0x%x sig=%d\n", g_names[i],
          g_why[i] == 0 ? "ok" :
          g_why[i] == 1 ? "FAILED-child-nonzero-exit" :
          g_why[i] == 2 ? "FAILED-child-signal" :
          g_why[i] == 3 ? "FAILED-pipe-empty" : "NEVER-RUN",
          g_st[i], WIFSIGNALED(g_st[i]) ? WTERMSIG(g_st[i]) : 0);
  return (Term)(u64)(g_why[i] == 0 ? 1u : 1u << g_why[i]);
}
"""

PRELUDE = r"""// GENERATED by .agents/slop/clangshim/clangshim-gen.py -- do not edit.
//
// ONE file, N bindings, ONE import, ONE cc. There are no clang-c headers on this
// machine; every declaration below is written from the port's own committed
// bindings (.agents/slop/ag-libclang.tramp + tinygrad/runtime/autogen/
// libclang.py), so a committed SIGNATURE is the complete input for a call.
//
// THE MARSHALLING CONVENTION, once, for every function here:
//   int/uint        one Term word, low 32 bits. A NEGATIVE int crosses as its
//                   two's-complement bit pattern, not as a negative Nat.
//   any pointer     one Term word = the address. Bend has no U64; Nat is a
//                   working U64 to 2^51-1 (MEASURED, ffi-experiment/e8).
//   by-value struct the CALLER passes an address and the shim reads SIZE bytes;
//                   the shim returns an address of a parked copy. The struct is
//                   an OPAQUE union: right size, 8-byte aligned, no fields. So a
//                   shim can pass and return a libclang struct over the ABI and
//                   CANNOT read a field of it -- that is the honest boundary.
//   const char* IN  a Bend String is a cons list of code points, not a char*, so
//                   bend_cstr walks it. Written ONCE, used by every string
//                   parameter.
//   const char* OUT io_str, two lines.
//   void            term_pak(CID(Unit), 0).
//   int64/uint64/double and function pointers: NO LAW EMITTED. Named per
//                   function in the BLOCKED table at the foot of shim.bend.

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <sys/wait.h>
#include <unistd.h>

#define PTR(t)   ((void*)(uintptr_t)(t))
#define SZ       256

// A parked struct is a value the callee returned by value; it must outlive the
// call, so it lives in a ring the shim owns rather than on the stack.
static unsigned char g_park[SZ][48];
static unsigned       g_park_n;
static void* park(const void* p, unsigned n) {
  void* q = g_park[g_park_n++ % SZ];
  memcpy(q, p, n);
  return q;
}

// A by-value struct parameter. f[i] == 0 is legal and means "a zeroed struct",
// so a caller with no object to pass is not a crash -- it is a wrong answer,
// which is the same thing every other zero argument is.
#define SBY(T, i) ({ T v_; if (PTR(f[i]) == 0) memset(&v_, 0, sizeof v_); \
                        else memcpy(&v_, PTR(f[i]), sizeof v_); v_; })

// Bend String -> char*. The cons walk, written once (MEASURED, e3).
static char* bend_cstr(Env e, Term t) {
  char* buf = (char*)malloc(4096);
  u32    n   = 0;
  while (term_aux(t) != CID(SNil)) {
    Term g[2];
    u64  sp = ctr_take(e, t, 2, g);
    buf[n++] = (char)g[0];
    t = g[1];
    spare_free(e, cls_fit(2), sp);
  }
  buf[n] = 0;
  return buf;
}
"""

# The callback stubs. libclang CALLS these, so each carries the callee's exact
# signature; the derived body is "do nothing, report Continue", which is a
# legal visitor answer and keeps the return on the ordinary return channel.
CB_STUB = """
// {name}: a visitor Bend cannot build. libclang calls it; the stub reports
// Continue (1) or nothing, and the call's own answer comes back as usual.
static {ret} {name}_stub({ps}) {{ {body} }}
"""


def emit(p, out_dir: Path, probe: bool = False,
          exclude: set[str] | None = None) -> dict:
    """Write shim.c and shim.bend for every row with no blocker and no exclusion."""
    drop = exclude or set()
    kept = [x for x in p if not x["blockers"] and x["name"] not in drop]
    blocked = [x for x in p if x["blockers"]]
    # by-value struct type names and their SIZE, from the resolved rows
    sizes = {}
    for x in kept:
        for t in [x["rct_raw"]] + x["pct_raw"]:
            m = re.match(r"^(\w+)\[(\d+)\]$", t)
            if m:
                sizes[m.group(1)] = int(m.group(2))

    c, b = [], []
    c.append("#define CLANGSHIM_ROWS %d\n" % len(kept) +
             (SHIM_FORK + PRELUDE if probe else PRELUDE))
    # Every struct the bindings only ever name behind a pointer needs a forward
    # declaration and nothing else: the ABI never touches its layout.
    # Every NAMED type the declarations mention must be declared exactly once.
    # A type used BY VALUE gets a union of its real SIZE; a type only ever
    # behind a pointer gets a one-byte opaque typedef, because the ABI only ever
    # needs its address. Naming them per use site is how the first run of this
    # emitted `extern void* clang_getFile(..., CXSourceRangeList*)` for a type
    # it had never declared -- a name that reads like it is fine and is not.
    opaque = sorted({nm for x in kept
                    for t in [canon(x["rct_raw"])] + [canon(q) for q in x["pct_raw"]]
                    # lstrip, not [1:]: `c.POINTER[CXTranslationUnit]` really is
                    # a DOUBLE pointer, because CXTranslationUnit is itself
                    # `c.POINTER[struct_CXTranslationUnitImpl]`. Only the base
                    # name needs declaring, and it is declared once.
                    for nm in [_SIZE_RE.sub("", t.lstrip("*"))] if t.startswith("*")
                    and nm not in sizes
                    and nm not in _BITS and nm != "void"
                    and nm not in set(_PRIM.values())})
    for nm in opaque:
        c.append(f"typedef struct {nm} {{ unsigned char _b[1]; }} {nm};")
    if opaque:
        c.append("")
    for nm, sz in sorted(sizes.items()):
        c.append(f"typedef union {{ unsigned char _b[{sz}]; unsigned long long _a; "
                 f"double _d; }} {nm};")
    c.append("")

    # callback stubs, one per distinct callback signature, before any use
    cbs = {}
    for x in kept:
        cbs.update(x["cbs"])
    # A callback needs a FUNCTION-POINTER TYPE as well as a body: the shim casts
    # shim_cb()'s answer to that type, and libclang calls through it. libclang
    # also CALLS the stub, so the signature must be the callee's, not a guess.
    for nm, (rs, ps) in sorted(cbs.items()):
        c.append(f"typedef {rs} (*{nm})({ps or 'void'});")
    # the bodies first: _stub_addr below takes their addresses
    for nm, (rs, ps) in sorted(cbs.items()):
        body = "return 1;" if rs != "void" else "return;"
        c.append(CB_STUB.format(name=nm, ret=rs, ps=ps or "void",
                                body=body).strip())
    c.append("// shim_cb(t) resolves a Nat to its stub. 0 selects the default stub,")
    c.append("// so a caller with no callback still passes a callable.")
    for nm, (rs, ps) in sorted(cbs.items()):
        c.append(f"static void* {nm}_stub_addr(void) "
                 f"{{ return (void*)&{nm}_stub; }}")
    c.append("static void* shim_cb(Term t) {")
    c.append("  switch (t) {")
    for i, nm in enumerate(sorted(cbs)):
        c.append(f"    case {i + 1}: return {nm}_stub_addr();")
    c.append(f"    default: return {sorted(cbs)[0]}_stub_addr();")
    c.append("  }")
    c.append("}")
    c.append("")

    # One flag per row, declared before any _run writes it.

    # extern declarations, one per function, parameter names as in the binding
    for x in kept:
        ps = ", ".join(f"{t} {n}" for t, n in zip(x["pct"], x["pname"])) or "void"
        c.append(f"extern {x['rct']} {x['name']}({ps});")
    c.append("")

    # The _run bodies. Each one FORKS: 308 of 308 called with a zero argument
    # will crash (see SHIM_FORK), and a census needs all 308 rows, not the
    # length of the prefix before the first segfault.
    for row, x in enumerate(kept):
        args, pre = [], []
        for i, (cl, ct) in enumerate(zip(x["pc"], x["pct"])):
            if cl == INT:
                args.append(f"({ct})(u32)f[{i}]")
            elif cl == PTR:
                args.append(f"(({ct})PTR(f[{i}]))")
            elif cl == STRI:
                q = f"a{i}"
                pre.append(f"    char* {q} = bend_cstr(e, f[{i}]);")
                args.append(q)
            elif cl.startswith("BYVAL"):
                pre.append(f"    {ct} v{i} = SBY({ct}, {i});")
                args.append(f"v{i}")
            elif cl == CB:
                pre.append(f"    {x['cbname'][i]} v{i} = "
                           f"({x['cbname'][i]})shim_cb(f[{i}]);")
                args.append(f"v{i}")
            else:
                raise SystemExit(f"unhandled param class {cl}")
        cl, ct, nm = x["rc"], x["rct"], x["name"]
        call = f"{nm}({', '.join(args)})"
        # The census forks; the plain shim does not. Both forms are MEASURED,
        # and the difference is the whole cost of crash isolation: 8 lines per
        # binding. `ffi-port-cost.py` estimated ~3 C lines from a three-function
        # experiment, which is the PLAIN form's shape -- so the plain number is
        # the one to compare against the estimate, and the forked number is what
        # a 305-row census costs on top.
        if not probe:
            body = [f"Term {nm}_run(Env e, Term* f, IoWork* w) {{"] + pre
            if cl == VOID:
                body += [f"  {call};", "  return term_pak(CID(Unit), 0);"]
            elif cl == INT:
                body += [f"  {ct} r = {call};", "  return (Term)(u64)(u32)r;"]
            elif cl == PTR:
                body += [f"  {ct} r = {call};",
                         "  return (Term)(u64)(uintptr_t)r;"]
            elif cl.startswith("BYVAL"):
                body += [f"  {ct} r = {call};",
                         "  return (Term)(u64)(uintptr_t)park(&r, sizeof r);"]
            elif cl == STRO:
                body += [f"  char* r = {call};",
                         "  return io_str(e, r, (u64)(r ? strlen(r) : 0));"]
            else:
                raise SystemExit(f"unhandled return class {cl}")
            body.append("}")
            c += body
            continue
        body = [f"Term {nm}_run(Env e, Term* f, IoWork* w) {{",
                "  int why = 0, stw = 0, fd[2] = {0, 0};",
                "  Term out;",
                "  pid_t pid = shim_spawn(fd);",
                "  if (pid == 0) {"]
        body += pre
        if cl == VOID:
            body += [f"    {call};", "    _exit(0);", "  }",
                     "  out = shim_none(pid, fd[0], &why, &stw);"]
        elif cl == INT:
            body += [f"    u64 v = (u64)(u32)({call});",
                     "    shim_put(fd[1], &v, sizeof v);", "    _exit(0);", "  }",
                     "  out = shim_word(pid, fd[0], &why, &stw);"]
        elif cl == PTR:
            body += [f"    u64 v = (u64)(uintptr_t)({ct})({call});",
                     "    shim_put(fd[1], &v, sizeof v);", "    _exit(0);", "  }",
                     "  out = shim_word(pid, fd[0], &why, &stw);"]
        elif cl.startswith("BYVAL"):
            body += [f"    {ct} s = ({call});",
                     "    void* q = park(&s, sizeof s);",
                     "    u64 v = (u64)(uintptr_t)q;",
                     "    shim_put(fd[1], &v, sizeof v);", "    _exit(0);", "  }",
                     "  out = shim_word(pid, fd[0], &why, &stw);"]
        elif cl == STRO:
            body += [f"    char* r = ({call});",
                     "    u64 n = (u64)(r ? strlen(r) : 0);",
                     "    shim_put(fd[1], &n, sizeof n);",
                     "    if (n) shim_put(fd[1], r, (size_t)n);",
                     "    _exit(0);", "  }",
                     "  out = shim_text(e, pid, fd[0], &why, &stw);"]
        else:
            raise SystemExit(f"unhandled return class {cl}")
        # The attribution is recorded BEFORE the return. An earlier version put
        # it after `return shim_*`, which is dead code -- and the harness then
        # reported 305/305 "the call returned".
        body += [f"  g_ok[{row}] = (Term)(u64)(why == 0);"
                 f" g_why[{row}] = why; g_st[{row}] = stw;",
                 "  return out;",
                 "}"]
        c += body

    if probe:
        # The census reader is a foreign def too, so it needs a CID and a
        # registration; io_eff_rows[CENSUS].run is otherwise NULL and the first
        # call err_fails with no name in the message. So it is emitted BEFORE
        # the constructor that registers it.
        c.append(f"#undef ROWS")
        c.append("static const char* g_names[CLANGSHIM_ROWS] = {")
        for i in range(0, len(kept), 3):
            c.append("  " + ", ".join(f'"{x["name"]}"' for x in kept[i:i + 3])
                     + ("," if i + 3 < len(kept) else ""))
        c.append("};")
        c.append(CENSUS_RUN)
        c.append("")

    # g_why must NOT start at 0. `why == 0` means "the call returned", so a
    # zero-initialised array reports OK for every row whose _run never reached
    # its own assignment -- and the FIRST version of this harness did exactly
    # that: 305/305 green alongside 15 `bend: memory fault` lines on stderr.
    # 4 is "the law was never called".
    if probe:
        c.append("static void __attribute__((constructor)) clangshim_mark_never(void) {")
        c.append("  for (u32 i = 0; i < CLANGSHIM_ROWS; i++) "
                 "{ g_why[i] = 4; g_st[i] = 0; }")
        c.append("}")
        c.append("")
    c.append("static void __attribute__((constructor)) clangshim_use(void) {")
    for x in kept:
        c.append(f"  io_eff(CID({x['name']}), {x['name']}_run, 0);")
    if probe:
        c.append("  io_eff(CID(census), census_run, 0);")
    c.append("}")
    c.append("")

    # ---- the Bend side: one law + one def per function ---------------
    b.append("# GENERATED by .agents/slop/clangshim/clangshim-gen.py -- do not edit.")
    b.append("# ONE import for every law below, ONE .c, ONE cc:")
    b.append("#   bend shim.bend -o shim.gen.c")
    b.append("#   cc shim.gen.c -L/Library/Developer/CommandLineTools/usr/lib -lclang \\")
    b.append("#      -Wl,-rpath,/Library/Developer/CommandLineTools/usr/lib -o shim.out")
    b.append("import Base")
    b.append("")
    for x in kept:
        b.append(f"law {x['name']}:")
        # a nullary law has no domain and no arrow: `law cver: IO(String)`
        dom = " -> ".join(x["pb"] + [f"IO({x['rb']})"])
        b.append(f"  {dom}")
        b.append("")
        b.append(f"def {x['name']}"
                 f"({', '.join(bend_name(n) for n in x['pname'])}):")
        b.append('  import "./shim.c"')
        b.append("")
    if blocked:
        b.append("# NOT EMITTED, and why -- every one is a real Bend limit, not a gap:")
        b.append("#   I64  no 64-bit integer type in Bend, so there is no law")
        b.append("#   F64  no F64 in Bend")
        for x in sorted(blocked, key=lambda y: y["name"]):
            b.append(f"#   {','.join(x['blockers']):24s} {x['name']}")
    if probe:
        n = len(kept)
        b.append("")
        b.append("# THE CALL CENSUS. main calls EVERY law DIRECTLY, once each, with the")
        b.append("# argument policy of zero for the parameter's class. Three reasons, all")
        b.append("# measured:")
        b.append("#   * a law main never calls is a TODO and `bend -o` refuses the file;")
        b.append("#   * a law main never calls gets NO `#define CID_<k>`, so the")
        b.append("#     io_eff(CID(k), ...) the shim emits is an undeclared macro;")
        b.append("#   * ONE live binder at a time, because holding n of them makes")
        b.append("#     main's frame wider than bend's WIDE=247 and the whole file")
        b.append("#     dies with \"an arity over 247\".")
        b.append("# Each _run forks, so one segfault costs one row and not the other 307.")
        b.append("law census:")
        b.append("  Nat -> IO(Nat)")
        b.append("")
        b.append("def census(i):")
        b.append('  import "./shim.c"')
        b.append("")
        b.append("def main() -> IO(Unit):")
        b.append("  do IO<Unit>:")
        for i, x in enumerate(kept):
            # The law's parameter types are Nat or String (two Bend types, one
            # marshalling convention), and a bare integer literal infers U32, so
            # a Nat argument must be written 0n.
            args = ['""' if b == "String" else "0n" for b in x["pb"]]
            call = f"{x['name']}({', '.join(args)})"
            # The answer is BOUND AND DROPPED, not printed. Two reasons, both
            # measured: a `void`-returning law has no printable answer, and
            # Nat.show aborts the whole run with "a Nat past the largest
            # immediate 2^48-1" on any answer above 2^51. The value lane is
            # Stage 3's job, in a program of its own.
            b.append(f"    v{i} : {x['rb']} <- {call}")
        for i, x in enumerate(kept):
            b.append(f'    q{i} : Nat <- census({i}n)')
            b.append(f'    IO.print("P{i} " ++ Nat.show(q{i}))')
    if not probe:
        # `bend -o` needs a caller for EVERY law or it emits no CID for the rest,
        # so even a plain shim gets a main. Without the fork this main DIES at
        # the first law that needs a live handle, which is why the census forks:
        # this main exists to make the file BUILD, not to run to completion.
        b.append("def main() -> IO(Unit):")
        b.append("  do IO<Unit>:")
        for i, x in enumerate(kept):
            args = ['""' if b == "String" else "0n" for b in x["pb"]]
            b.append(f"    v{i} : {x['rb']} <- "
                     f"{x['name']}({', '.join(args)})")
        b.append('    IO.print("SMOKE_END")')
    (out_dir / "shim.c").write_text("\n".join(c) + "\n")
    (out_dir / "shim.bend").write_text("\n".join(b) + "\n")
    return {"kept": kept, "blocked": blocked, "sizes": sizes,
            "c_lines": len(c), "bend_lines": len(b)}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", help="directory to write shim.c and shim.bend into")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--probe", action="store_true",
                    help="also emit the census law + main that CALL all of them")
    ap.add_argument("--exclude", action="append", default=[],
                    help="drop a binding by name; only for a symbol the LINKER "
                         "reported undefined, and every one is printed")
    a = ap.parse_args()

    T = fpc.Types(PYBIND.read_text())
    p = plan(T)

    missing = set(a.exclude)
    unknown = missing - {x["name"] for x in p}
    if unknown:
        raise SystemExit(f"--exclude names not in the bindings: {sorted(unknown)}")
    kept = [x for x in p if not x["blockers"] and x["name"] not in missing]
    blocked = [x for x in p if x["blockers"]]
    if missing:
        print(f"EXCLUDED by name (the linker reported these undefined): "
              f"{len(missing)} {sorted(missing)}")
    print(f"trampoline rows            : {len(p)}")
    print(f"laws emitted               : {len(kept)}")
    print(f"NOT emitted (each named)   : {len(blocked)}")
    for cl, n in sorted(Counter(tuple(x["blockers"]) for x in blocked).items()):
        print(f"  {','.join(cl):24s} {n}")
    if a.list:
        for x in sorted(blocked, key=lambda y: y["name"]):
            print(f"  {x['name']:52s} {','.join(x['blockers'])}")
        return 0
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    r = emit(p, out, probe=a.probe, exclude=missing)
    n = len(r["kept"])
    print(f"\nshim.c    : {r['c_lines']} lines for {n} bindings "
          f"= {r['c_lines'] / n:.2f} lines/binding "
          f"(the {len(PRELUDE.splitlines())}-line prelude and "
          f"{len(r['sizes'])} struct typedefs are inside that)")
    print(f"shim.bend : {r['bend_lines']} lines for {n} laws "
          f"= {r['bend_lines'] / n:.2f} lines/law "
          f"(header and the {len(blocked)}-row blocked table are inside that)")
    print(f"structs   : {len(r['sizes'])} opaque unions {sorted(r['sizes'].items())}")
    return 0


if __name__ == "__main__":
    sys.exit(main())