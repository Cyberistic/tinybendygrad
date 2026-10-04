#!/usr/bin/env python3
"""cidsweep: per-seam CID census — every `CID(...)`/`CID_*` NAME a seam needs, and
whether the enclosing `#ifdef CID(...)` covers it.  Rule CIDS-2.

The question is per-SEAM: "if a build reached exactly this one effect, which ids
does the pasted C name, and which of them does that build define?"

Two id CLASSES are demand-allocated identically (SZLANE CF-1 / SZ-1):
  * EFFECT ids      -- `CID(clang_createIndex)`, registered via io_eff
  * CONSTRUCTOR ids -- `CID(Nil)` / `CID(Con)` / `CID_SNIL` / `CID(SCon)`, used by
                       a packer/destructurer.  Guarding only the io_eff and not
                       the packer leaves an undeclared FUNCTION one step later.
"""
import os, re, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))

SEAMS = [
    "tinybendygrad/runtime/dtype.c",
    "tinybendygrad/runtime/sz.c",
    ".agents/slop/clangshim/libclang-tramp.c",
    ".agents/slop/clangshim/libclang-ffi.c",
]

CTOR = re.compile(r"\bCID_(?:[A-Z]+_)*(?:NIL|CON)\b")

def regions(lines):
    """[(start_idx, end_idx, guard_line_no_or_None)] for every #ifdef region."""
    out, stack = [], []
    for i, l in enumerate(lines):
        s = l.strip()
        if re.match(r"#\s*if", s):
            stack.append((i, "CID" in s))
        elif re.match(r"#\s*endif", s) and stack:
            st, iscid = stack.pop()
            if iscid: out.append((st, i, st + 1))
    return out

def main():
    print("=" * 92)
    print("CID CENSUS per seam — constructor ids named, and guard coverage")
    print("=" * 92)
    for p in SEAMS:
        full = os.path.join(ROOT, p)
        if not os.path.exists(full):
            print(f"\n{p}: MISSING"); continue
        lines = open(full, encoding="utf-8", errors="replace").read().splitlines()
        regs = regions(lines)
        ctors = []
        for i, l in enumerate(lines):
            for m in set(CTOR.findall(l)):
                cov = next((g for a, b, g in regs if a <= i <= b), False)
                ctors.append((i + 1, m, cov))
        eff = [(i + 1, l) for i, l in enumerate(lines)
               if "io_eff" in l and "CID" in l]
        eff_unguarded = [(n, t) for n, t in eff
                         if not any(a <= n - 1 <= b for a, b, _ in regs)]
        # which line ranges does each guard cover?
        print(f"\n{p}")
        print(f"  io_eff(CID(..)) registrations : {len(eff)}"
              f"   unguarded: {len(eff_unguarded)}")
        print(f"  #ifdef CID(..) regions        : {len(regs)}"
              + (f"  lines {[g for _, _, g in regs][:6]}{'…' if len(regs) > 6 else ''}" if regs else ""))
        print(f"  constructor ids named         : {len(ctors)}")
        for n, m, cov in ctors[:10]:
            where = f"INSIDE guard @L{cov}" if cov is not True and cov is not False else str(cov)
            print(f"      L{n:<6d} {m:<12s} {where}")
        if len(ctors) > 10: print(f"      … {len(ctors)-10} more")
        if eff_unguarded:
            print(f"  UNGUARDED registrations (first 4):")
            for n, t in eff_unguarded[:4]:
                print(f"      L{n:<6d} {t.strip()[:78]}")
            if len(eff_unguarded) > 4: print(f"      … {len(eff_unguarded)-4} more")

if __name__ == "__main__":
    main()
