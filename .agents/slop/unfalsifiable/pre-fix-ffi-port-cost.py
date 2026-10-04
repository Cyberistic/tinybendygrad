#!/usr/bin/env python3
"""ffi-port-cost.py -- turn "can Bend call this library?" into a COUNT.

Two units concluded "the FFI wall is real" from different wrong premises:
one from "Bend has no per-function binding form", one from the absence of
dlopen. Both were wrong -- Bend inlines an imported .c into the C it emits,
and that .c may call anything the C compiler can link. This tool exists so a
third unit does not have to reach that conclusion from a fourth wrong premise.

It answers, for a given library or header:
  * how many entry points are involved (numerator AND denominator)
  * whether a shim is MECHANICALLY DERIVABLE from the declarations alone
  * what the per-function marshalling costs, by measured class
  * the exact cc line that links it

Every marshalling class below is labelled with how it was established. A class
marked MEASURED has a run in this repo behind it; a class marked ASSUMED has
not been run and must be before anyone relies on it.

Usage:
  ffi-port-cost.py libclang.dylib
  ffi-port-cost.py --symbols symbols.txt
  ffi-port-cost.py Index.h
  ffi-port-cost.py --symbols s.txt --header Index.h
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path

# --- the measured facts this repo established -------------------------------
#
# Bend 2.0.35. Every line here came from running something; the run is named.

# MEASURED: no F64, no U64, no I64, no I32, no U8.
#   `bend --check-only` on `law f: U64 -> IO(U64)` gives
#   "expected : a defined name / observed : U64".
#   Available scalar types: U32, F32, Nat, Bool, String.
ABSENT_TYPES = ("F64", "U64", "I64", "I32", "U8", "I16", "U16")

# MEASURED (e10 sweep, 32..63 bits): a Nat crosses the foreign boundary as a
# raw unboxed word for magnitudes up to 2^51-1, and the RUNTIME ABORTS above
# 2^52-1 with "bend: a Nat past the largest immediate 2^48-1".
# Note the message says 2^48; the observed cut is between 2^51 and 2^52.
NAT_MAX_BITS = 51

# MEASURED (e11): a Nat argument arrives in f[0] as term_tag == 0, i.e. a raw
# word. No boxing, no heap slot, one Term word of payload.

# MEASURED (e12): an f32 crosses losslessly as a Nat BIT PATTERN. Bend sent
# 0x3F800000, C read it as float 1.000000 and re-emitted the same 32 bits.

# MEASURED (e3): a Bend String is a cons list of code points, one heap cell
# per scalar, term_ctr(CID_SCON, loc) with the scalar at mem[loc] and the
# sealed tail at mem[loc+1], ended by term_pak(CID_SNIL, 0). It is NOT a char*,
# so a const char* parameter needs a walk (bend_str_to_c, ~12 lines, written
# once and reused by every string-taking function).

# MEASURED (e6/e8): a 64-bit driver handle crosses in one Term word via Nat,
# verified in-process against C's own reading of the same pointer.

# The cost of the whole mechanism, from e5 (three laws, one shim.c, one
# import, one cc): 3 functions cost 6 lines of law + 9 lines of C. So the
# marginal cost per function is ~3 lines of law + ~3 lines of C.

LAW_LINES_PER_FN = 3   # law sig (2 lines) + def/import (2 lines) / 1 fn
C_LINES_PER_FN = 3     # Term *_run(...) { return ...; } + io_eff line


@dataclass
class Arg:
    """One parameter or return value, classified by what it costs to move."""

    ctype: str
    kind: str
    how: str
    blocked: bool = False
    note: str = ""


@dataclass
class Fn:
    name: str
    ret: Arg | None
    args: list[Arg] = field(default_factory=list)

    @property
    def blocked(self) -> bool:
        return bool(self.ret and self.ret.blocked) or any(a.blocked for a in self.args)

    @property
    def max_class(self) -> str:
        if self.blocked:
            return "BLOCKED"
        if any(a.kind in ("OPAQUE", "VARARGS") for a in self.args):
            return "OPAQUE"
        if self.ret is not None and self.ret.kind == "OPAQUE":
            return "OPAQUE"
        if any(a.kind == "CBYVAL" for a in self.args) or (
                self.ret is not None and self.ret.kind == "CBYVAL"):
            return "CBYVAL"
        if any(a.kind == "CB" for a in self.args):
            return "CB"
        if any(a.kind == "PTR" for a in self.args):
            return "PTR"
        if any(a.kind in ("STR_IN", "STR_OUT") for a in self.args):
            return "STR"
        if self.ret is not None and self.ret.kind in ("STR_OUT", "STR_IN"):
            return "STR"
        return "SCALAR"


# --- classification --------------------------------------------------------

_PTR_RE = re.compile(r"\b(?:const\s+)?\w+\s*\**\s*(\w+)?$")


_PRIMS = {
    "void", "", "int", "unsigned", "unsigned int", "long", "unsigned long",
    "long long", "unsigned long long", "size_t", "ssize_t", "intptr_t",
    "uintptr_t", "ptrdiff_t", "char", "signed char", "unsigned char",
    "short", "unsigned short", "float", "double", "long double", "bool",
    "_Bool", "FILE",
}


def classify(ctype: str, is_return: bool) -> Arg:
    """Map a C type to the marshalling it costs in Bend.

    `is_return` matters: a `const char*` RETURN is two lines (io_str), while a
    `const char*` PARAMETER is the cons walk.

    The default arm is OPAQUE, not INT. An unrecognised named type is almost
    always a struct or a typedef of one, and guessing "integer" for it is how
    a tool reports 100% clean over a port that would not compile. An unexplained
    success is a defect, not a result.
    """
    t = " ".join(ctype.split())
    low = t.lower()

    if "..." in t:
        return Arg(t, "VARARGS", "no mechanical rule: arg count is unknown", True,
                   "needs a per-call-site decision")
    if "(*" in t or re.search(r"\(\s*\*\s*\w*\s*\)\s*\(", t):
        return Arg(t, "CB", "shim-side handle table", False,
                   "no measured round trip yet")

    if low in ("void", "", "none"):
        return Arg(t, "VOID", "nothing")

    if low == "float":
        return Arg(t, "F32", "F32, or Nat bit pattern (MEASURED lossless)")
    if low in ("double", "long double"):
        return Arg(t, "F64", "no Bend type: F64 is ABSENT", True,
                   "needs 2x U32 or a shim-side heap slot")

    if low in _CTYPES_INT:
        n = _CTYPES_INT[low]
        if n > NAT_MAX_BITS:
            return Arg(t, "F64", f"{low} is {n} bits; past the "
                                 f"2^{NAT_MAX_BITS}-1 Nat window", True,
                       "split into 2x U32")
        return Arg(t, "INT", f"{low}, {n} bits, fits Nat")

    if low in ("ctypes.c_double",):
        return Arg(t, "F64", "ctypes.c_double; F64 is ABSENT in Bend", True,
                   "split into 2x U32, or carry the bit pattern in a "
                   "shim-side heap slot")
    if low.startswith("cb:"):
        return Arg(t, "CB", "function-pointer parameter: shim-side handle table",
                   False, "no measured round trip yet")

    if low in ("ctypes.c_void_p", "*void", "c_void_p"):
        return Arg(t, "NAT", "Nat, 1 word (MEASURED for a 64-bit handle)")
    if low in ("ctypes.c_char_p", "*char"):
        k = "STR_OUT" if is_return else "STR_IN"
        how = ("io_str, 2 lines" if is_return
               else f"cons walk, bend_str_to_c, {NAT_MAX_BITS}-bit window")
        return Arg(t, k, how)

    # a struct the binding file gave a SIZE for: by value, size is known.
    # A by-value struct is NOT blocked: it is N Terms wide, one per 8 bytes.
    # What it needs is a LAYOUT CONVENTION, and the honest thing to report is
    # the byte count so the reader can judge the cost.
    m = re.match(r"^(?:struct_)?\w+\[(?P<n>\d+)\]$", t)
    if m:
        n = int(m.group("n"))
        words = -(-n // 8)
        return Arg(t, "CBYVAL",
                   f"{n}-byte struct by value = {words} Term word(s)", False,
                   "free if the layout convention is chosen once")

    if low in _PRIMS:
        if low in ("int", "unsigned", "unsigned int", "long", "unsigned long",
                   "long long", "unsigned long long", "size_t", "ssize_t",
                   "intptr_t", "uintptr_t", "ptrdiff_t"):
            return Arg(t, "INT", f"Nat (MEASURED to 2^{NAT_MAX_BITS}-1)")
        if low in ("short", "unsigned short", "signed char", "unsigned char", "char"):
            return Arg(t, "SMALLINT", f"Nat (MEASURED to 2^{NAT_MAX_BITS}-1)")
        return Arg(t, "INT", "U32")

    if low in ("char *", "char*", "const char *", "const char*"):
        k = "STR_OUT" if is_return else "STR_IN"
        how = ("io_str, 2 lines" if is_return
               else f"cons walk, bend_str_to_c, {NAT_MAX_BITS}-bit window")
        return Arg(t, k, how)

    if "*" in t:
        base = t.replace("const", "").replace("*", "").strip()
        if base.lower() in ("char", "void", ""):
            return Arg(t, "NAT", "Nat, 1 word (MEASURED for a 64-bit handle)")
        return Arg(t, "PTR", f"pointer to {base}: needs a Buffer/Buf contract",
                   False, "assume no contract exists yet; measure before relying")

    # Not a primitive. Either a struct/union by value, or a typedef of one.
    # A typedef of an INTEGER is the friendly case; a struct is not.
    return Arg(t, "OPAQUE", "named type: struct or typedef, unknown without "
                            "the real declaration", True,
                   "typedef of an int is free; anything else needs the struct")


# --- parsing ---------------------------------------------------------------

_PROTO_RE = re.compile(
    r"^\s*(?P<ret>[A-Za-z_][\w\s\*]*?)\s+"
    r"(?P<name>clang_[A-Za-z0-9_]+|MTL[A-Za-z0-9_]*|cl[A-Z][A-Za-z0-9_]*)\s*"
    r"\((?P<args>[^;{]*)\)\s*;",
    re.MULTILINE,
)
_STRIP_COMMENT = re.compile(r"/\*.*?\*/|//[^\n]*", re.DOTALL)


def parse_header(text: str) -> list[Fn]:
    text = _STRIP_COMMENT.sub(" ", text)
    out: list[Fn] = []
    for m in _PROTO_RE.finditer(text):
        raw = [a.strip() for a in m.group("args").split(",") if a.strip()]
        args: list[Arg] = []
        for a in raw:
            if a.lower() in ("void", ""):
                continue
            # drop the parameter name: last bare identifier
            mm = re.match(r"^(?P<ty>.*?[\s\*])(?P<nm>[A-Za-z_]\w*)$", a)
            ctype = mm.group("ty") if mm else a
            args.append(classify(ctype, False))
        out.append(Fn(m.group("name"), classify(m.group("ret"), True), args))
    return out


def symbols_from_dylib(path: str) -> tuple[list[str], str]:
    r = subprocess.run(["nm", "-gU", path], capture_output=True, text=True)
    if r.returncode != 0:
        return [], r.stderr.strip()
    names = [ln.split()[2] for ln in r.stdout.splitlines()
             if len(ln.split()) == 3 and ln.split()[1] in "TDBR"]
    strip = [n[1:] if n.startswith("_") else n for n in names]
    return strip, ""


def read_symbol_list(path: str) -> list[str]:
    return [ln.strip().lstrip("_") for ln in Path(path).read_text().splitlines()
            if ln.strip() and not ln.strip().startswith("#")]


# tinygrad's autogen ctypes binding is an EXACT signature source even when the
# vendor ships no C header, which is the case for Apple's libclang here. The
# idiom is a @dll.bind(return_ctype, arg_ctype, ...) line immediately above a
# `def clang_x(a: A, b: B) -> R: ...` stub. This parser reads it as a header.
#
# The file ALSO carries `X: TypeAlias = <expr>` for every opaque libclang type
# and `SIZE = n` for every by-value struct. Resolving those is mechanical and is
# what stops the classifier from calling a 24-byte struct an integer.
_BIND_RE = re.compile(r"^@dll\.bind\((?P<types>[^)]*)\)\s*$")
_PYDEF_RE = re.compile(
    r"^def\s+(?P<name>clang_[A-Za-z0-9_]+)\s*\((?P<args>[^)]*)\)\s*->\s*(?P<ret>[^:]+):")
_ALIAS_RE = re.compile(r"^(?P<name>[A-Za-z_]\w*):\s*TypeAlias\s*=\s*(?P<expr>.+?)\s*$")
_RECORD_RE = re.compile(r"^class\s+(?P<name>\w+)\(c\.Struct\)\s*:?\s*(?:pass)?\s*$")
_SIZE_RE = re.compile(r"^\s{2}SIZE\s*=\s*(?P<n>\d+)\s*$")

_CTYPES_INT = {
    "ctypes.c_uint32": 32, "ctypes.c_int32": 32, "ctypes.c_uint": 32,
    "ctypes.c_int": 32, "ctypes.c_uint8": 8, "ctypes.c_int8": 8,
    "ctypes.c_uint16": 16, "ctypes.c_int16": 16,
    "ctypes.c_uint64": 64, "ctypes.c_int64": 64, "ctypes.c_size_t": 64,
    "ctypes.c_ssize_t": 64,
}


class Types:
    """TypeAliases and struct sizes, resolved from the binding file itself."""

    def __init__(self, text: str) -> None:
        self.alias: dict[str, str] = {}
        self.size: dict[str, int] = {}
        cur: str | None = None
        in_record = False
        for line in text.splitlines():
            a = _ALIAS_RE.match(line)
            if a:
                self.alias[a.group("name")] = a.group("expr").strip()
                continue
            r = _RECORD_RE.match(line)
            if r:
                cur = r.group("name")
                in_record = True
                continue
            if line.startswith("@") or line.startswith("class ") or line.startswith("def "):
                in_record = False
                cur = None
                continue
            if in_record and cur:
                s = _SIZE_RE.match(line)
                if s:
                    self.size[cur] = int(s.group("n"))
        self._cache: dict[str, str] = {}

    def resolve(self, t: str, depth: int = 0) -> str:
        """Expand a TypeAlias to what it actually is, transitively."""
        t = t.strip()
        if t in self._cache or depth > 8:
            return self._cache.get(t, t)
        # a POINTER/CFUNCTYPE written directly in a @dll.bind line, not via an
        # alias: c.POINTER[X] is a pointer whatever X is, so resolve X for the
        # pointee's sake and keep the star
        inner = re.match(r"^c?(?:types)?\.?POINTER\[(?P<x>.+)\]$", t) or \
            re.match(r"^c\.POINTER\((?P<x>.+)\)$", t)
        if inner:
            out = "*" + self.resolve(inner.group("x"), depth + 1)
            self._cache[t] = out
            return out
        fnp = re.match(r"^c\.CFUNCTYPE\[.*\[(?P<x>.+)\]\]$", t)
        if fnp:
            out = "CB:" + self.resolve(fnp.group("x"), depth + 1)
            self._cache[t] = out
            return out
        arr = re.match(r"^c\.Array\[.*,\s*Literal\[(?P<n>\d+)\]\]$", t)
        if arr:
            out = f"*{self.resolve(t.split(',')[0].split('[')[1], depth + 1)}"
            self._cache[t] = out
            return out
        expr = self.alias.get(t)
        if expr is None:
            # a name that IS a record with a known SIZE: that is a by-value
            # struct, and its byte size is the whole marshalling question
            if t in self.size:
                out = f"{t}[{self.size[t]}]"
            else:
                out = t
            self._cache[t] = out
            return out
        # c.POINTER[X] is a pointer whatever X is
        inner = re.match(r"^c?\.?POINTER\[(?P<x>.+)\]$", expr) or \
            re.match(r"^ctypes\.POINTER\((?P<x>.+)\)$", expr)
        if inner:
            out = "*" + self.resolve(inner.group("x"), depth + 1)
        elif expr.startswith("struct_") or expr in self.size:
            out = expr + f"[{self.size.get(expr, '?')}]"
        else:
            out = self.resolve(expr, depth + 1)
        self._cache[t] = out
        return out


def parse_pybind(text: str) -> list[Fn]:
    T = Types(text)
    out: list[Fn] = []
    pending: list[str] | None = None
    for line in text.splitlines():
        b = _BIND_RE.match(line)
        if b:
            pending = [t.strip() for t in b.group("types").split(",") if t.strip()]
            continue
        d = _PYDEF_RE.match(line)
        if not d:
            continue
        nparams = len([a for a in d.group("args").split(",") if a.strip()])
        ctypes_ = pending or []
        ret_c = ctypes_[0] if ctypes_ else "void"
        arg_c = ctypes_[1:1 + nparams]
        # a short arg list means the bind line did not spell every type; the
        # Python annotation is then the better source for that position
        pyargs = [a.split(":", 1)[1].strip() if ":" in a else ""
                  for a in d.group("args").split(",") if a.strip()]
        args = [classify(T.resolve(arg_c[i] if i < len(arg_c)
                                   else (pyargs[i] or "int")), False)
                for i in range(nparams)]
        pyret = d.group("ret").strip()
        out.append(Fn(d.group("name"), classify(T.resolve(ret_c or pyret), True), args))
        pending = None
    return out


# --- reporting -------------------------------------------------------------

CLASS_NOTE = {
    "SCALAR": "nothing but Nat/U32/F32 -- free",
    "STR": "one reusable cons walk in, io_str out",
    "PTR": "needs a Buffer/Buf contract to exist first",
    "CB": "needs a shim-side handle table",
    "STRUCT": "per-struct decision, not mechanical",
    "CBYVAL": "struct by value -- N Term words, needs one layout convention",
    "OPAQUE": "named type -- struct or typedef, unresolvable from this source",
    "BLOCKED": "no Bend type or past the 2^51-1 Nat window",
}


def report(fns: list[Fn], lib: str, denom: int | None, origin: str) -> bool:
    names = [f.name for f in fns]
    uniq = sorted(set(names))
    print(f"library        : {lib}")
    print(f"symbols from  : {origin}")
    print(f"entry points  : {len(uniq)} unique declarations")
    if denom is not None:
        print(f"denominator   : {denom} symbols exported by the binary")
        print(f"coverage      : {len(uniq)}/{denom} = "
              f"{100.0 * len(uniq) / denom:.1f}%")
        if len(uniq) > denom:
            print("  !! more declarations than exported symbols -- the header "
                  "and the binary disagree; do not trust either count alone")
    print()

    by_class = Counter(f.max_class for f in fns)
    blocked = [f for f in fns if f.blocked]
    print("per-function marshalling cost, by worst class in the signature:")
    for cls, n in by_class.most_common():
        print(f"  {cls:8s} {n:5d}   {CLASS_NOTE.get(cls, '')}")
    print()

    if blocked:
        print(f"BLOCKED by an absent Bend type or the Nat window ({len(blocked)}):")
        for f in sorted(blocked, key=lambda x: x.name)[:25]:
            who = [a for a in ([f.ret] if f.ret else []) + f.args if a.blocked]
            print(f"  {f.name}: " + "; ".join(
                f"{a.ctype} -> {a.note}" for a in who))
        if len(blocked) > 25:
            print(f"  ... and {len(blocked) - 25} more")
        print()

    mechanical = len(uniq) - len({f.name for f in blocked})
    structish = len({f.name for f in fns if f.max_class in ("CBYVAL", "OPAQUE")})
    print(f"mechanically derivable : {mechanical}/{len(uniq)} "
          f"({100.0 * mechanical / max(1, len(uniq)):.0f}%) have no absent-type "
          f"blocker")
    print(f"need a layout decision : {structish} by-value struct or unresolvable type")
    print()
    print("SIZE, if written:")
    print(f"  Bend law lines : {LAW_LINES_PER_FN * len(uniq)}"
          f"   ({LAW_LINES_PER_FN} per function)")
    print(f"  C shim lines   : ~{C_LINES_PER_FN * len(uniq)}"
          f"   ({C_LINES_PER_FN} per function, plus ~15 shared marshalling helpers)")
    print(f"  runtime helpers: 1 for strings, 0 for scalars -- written once")
    print()
    print("LINK LINE:")
    print(f"  cc out.c {lib_flag(lib)} -o out")
    if "clang" in lib:
        print("  (Apple's libclang.dylib has an @rpath install name, so add")
        print("   -Wl,-rpath,/Library/Developer/CommandLineTools/usr/lib)")
    if "Metal" in lib:
        print("  (Metal pulls in ObjC Foundation: cc -x objective-c ...)")
    return not blocked


def lib_flag(lib: str) -> str:
    if "framework" in lib.lower() or lib in ("Metal", "OpenCL", "Foundation"):
        return "-framework " + lib
    return "-l" + lib


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("target", help="a .dylib/.so, a header, or a .py binding file")
    ap.add_argument("--header", help="parse this header for signatures")
    ap.add_argument("--symbols", help="file of one symbol per line")
    ap.add_argument("--pybind", action="store_true",
                    help="target is a @dll.bind ctypes binding (exact signatures)")
    ap.add_argument("--lib", help="link flag name (default: derived from target)")
    a = ap.parse_args()

    t = Path(a.target)
    denom: int | None = None
    origin = ""

    if a.pybind:
        if not t.exists():
            print(f"no such file: {t}", file=sys.stderr)
            return 2
        fns = parse_pybind(t.read_text(errors="replace"))
        origin = f"{t} (@dll.bind signatures, {len(fns)} parsed)"
        denom = len({f.name for f in fns})
        lib = a.lib or "clang"
        clean = report(fns, lib, denom, origin)
        return 0 if clean else 1

    if a.symbols:
        names = read_symbol_list(a.symbols)
        origin = f"{a.symbols} ({len(names)} lines)"
        lib = a.lib or "LIBSYM"
    elif t.suffix in (".h", ".hpp", ".def") or a.header:
        hp = Path(a.header or a.target)
        if not hp.exists():
            print(f"no such header: {hp}", file=sys.stderr)
            return 2
        fns = parse_header(hp.read_text(errors="replace"))
        origin = f"{hp} ({len(fns)} prototypes matched)"
        denom = len({f.name for f in fns}) or None
        lib = a.lib or "LIBSYM"
    else:
        names, err = symbols_from_dylib(str(t))
        if err:
            print(f"nm failed: {err}", file=sys.stderr)
            return 2
        origin = f"nm -gU {t} ({len(names)} defined symbols)"
        denom = len(set(names))
        lib = a.lib or t.stem.replace("lib", "")

    if a.header:
        hp = Path(a.header)
        fns = parse_header(hp.read_text(errors="replace"))
        named = set(names) if names else None
        if named is not None:
            fns = [f for f in fns if f.name in named] or fns
        denom = len(set(names)) if names else len({f.name for f in fns})
        origin += f" + {hp} ({len(fns)} signatures)"
    elif names and not a.symbols:
        # Signatures unavailable. Do NOT guess them -- that is the whole point.
        print(f"library        : {lib}")
        print(f"symbols from  : {origin}")
        print(f"entry points  : {len(set(names))}")
        print(f"denominator   : {denom} exported")
        print()
        print("NO SIGNATURES AVAILABLE. The count is real; the marshalling cost")
        print("is NOT, and will not be estimated from the names. Pass --header")
        print("with the real declarations, or run the count against a header that")
        print("ships with the library.")
        return 0
    else:
        return 2

    if a.symbols and not a.header:
        print(f"symbol list has no signatures; need --header to classify.")
        return 3

    clean = report(fns, lib, denom, origin)
    return 0 if clean else 1


if __name__ == "__main__":
    sys.exit(main())