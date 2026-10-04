#!/usr/bin/env python3
"""cidsweep census v2 — the CORRECT empty-body detector.

CENSUS v1 REPORTED 478 `inline None{` PER FILE.  THAT WAS A FALSE POSITIVE:
`case _: None{}` is a MATCH ARM, not an empty body, and 460 of the 478 were
exactly that.  Rule CIDS-1.  This version only counts a `None{}` that IS the
body: a whole-line `None{}` whose immediately-preceding non-blank line is a
header ending in `:`.
"""
import os, re, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
SCOPE_DIRS = ["tinybendygrad", "langs", "examples", "extra"]

def rel(p): return os.path.relpath(p, ROOT)

def bend_files():
    out = []
    for d in SCOPE_DIRS:
        for dp, _dn, fn in os.walk(os.path.join(ROOT, d)):
            for f in fn:
                if f.endswith(".bend"): out.append(os.path.join(dp, f))
    return sorted(out)

def classify(txt):
    lines = txt.splitlines()
    empty = []            # None{} that IS a body
    arms = 0              # `case ...: None{}` / `match ...: None{}` -- a REFUSAL ARM
    inline_empty = []     # `def f(..): None{}` on one line
    declared = 0
    for i, l in enumerate(lines):
        s = l.strip()
        if re.match(r"^(def|law)\s+\S", l): declared += 1
        if re.fullmatch(r"None\s*\{\s*\}", s):
            # find preceding non-blank
            j = i - 1
            while j >= 0 and not lines[j].strip(): j -= 1
            prev = lines[j].strip() if j >= 0 else ""
            if prev.endswith(":") and not re.match(r"^(case|match)\b", prev):
                empty.append(i + 1)
            else:
                arms += 1
        m = re.match(r"^(?:def|law)\s+[^:]*(?:->[^:]*)?:\s*None\{\s*\}\s*$", s)
        if m: inline_empty.append(i + 1)
    return declared, empty, inline_empty, arms

def main():
    print("=" * 84)
    print("CENSUS v2 — .bend EMPTY BODIES (None{} as a body, not a match arm)")
    print("=" * 84)
    print(f"{'file':60s} {'declared':>8s} {'EMPTY':>6s} {'match-arm None{}':>16s}")
    rows = []
    td = te = ta = 0
    for p in bend_files():
        txt = open(p, encoding="utf-8", errors="replace").read()
        d, e, ie, a = classify(txt)
        td += d; ta += a
        if e or ie:
            rows.append((rel(p), d, e, ie, a))
        te += len(e) + len(ie)
    for r in sorted(rows, key=lambda x: -(len(x[2]) + len(x[3]))):
        print(f"{r[0]:60s} {r[1]:8d} {len(r[2])+len(r[3]):6d} {r[4]:16d}"
              + ("   lines " + ",".join(map(str, r[2] + r[3])) if len(r[2]) + len(r[3]) <= 12 else ""))
    print(f"\n.bend files scanned                      : {len(bend_files())}")
    print(f"declared bodies (def + law)              : {td}")
    print(f"EMPTY bodies                             : {te}")
    print(f"refusal match-arms `case X: None{{}}`     : {ta}   (NOT empty bodies)")

    print()
    print("=" * 84)
    print("CENSUS v2b — .c seams: declared vs empty function bodies")
    print("=" * 84)
    for path in ["tinybendygrad/runtime/dtype.c", "tinybendygrad/runtime/sz.c",
                 ".agents/slop/clangshim/libclang-tramp.c",
                 ".agents/slop/clangshim/libclang-ffi.c"]:
        full = os.path.join(ROOT, path)
        if not os.path.exists(full): continue
        txt = open(full, encoding="utf-8", errors="replace").read()
        lines = txt.splitlines()
        fns = []; empt = []
        for i, l in enumerate(lines):
            m = re.match(r"^(?:static\s+)?(?:Term|void|int|u64|U32|I64|char|double|size_t)[A-Za-z0-9_ \*]*\s"
                         r"([A-Za-z_][A-Za-z0-9_]*)\s*\([^;]*\)\s*\{", l)
            if m:
                # find matching close brace at col 0
                k = i + 1; body = []
                while k < len(lines) and lines[k] != "}":
                    body.append(lines[k].strip()); k += 1
                b = [x for x in body if x and not x.startswith("//") and not x.startswith("/*")]
                fns.append(m.group(1))
                if not b: empt.append((i + 1, m.group(1)))
        print(f"\n{path}")
        print(f"  function definitions   : {len(fns)}")
        print(f"  EMPTY bodies           : {len(empt)}  {empt if empt else ''}")

    print()
    print("=" * 84)
    print("CENSUS v2c — .js seams: arrow-fn bodies that are empty")
    print("=" * 84)
    for path in ["tinybendygrad/runtime/dtype.js", "tinybendygrad/runtime/sz.js"]:
        full = os.path.join(ROOT, path)
        txt = open(full, encoding="utf-8", errors="replace").read()
        n_decl = len(re.findall(r"\bfunction\b", txt))
        n_arrow = len(re.findall(r"=>", txt))
        n_empty = len(re.findall(r"=>\s*\{\s*\}", txt)) + len(re.findall(r"=>\s*(?:null|undefined)\s*;", txt))
        print(f"\n{path}")
        print(f"  `function` decls : {n_decl}    `=>` arrows : {n_arrow}    EMPTY arrow bodies : {n_empty}")

if __name__ == "__main__":
    main()
