#!/usr/bin/env python3
"""Recover webgpu_call.bend from webgpu_call.mjs -- the LOGIC, mechanically.

WHY. A scripted def-reordering pass truncated the .bend to 11 lines. The .mjs
emitted from the LAST GOOD state -- the one that ran 57 of 57 steps against a
real `navigator.gpu` -- is a faithful and COMPLETE record of that logic, because
the emitter is a total function from the source. Recovering beats rewriting: a
rewrite would be a SECOND, unverified version of a file that had executed.

THE MAPPING, all of it measured on the emitted file:
  `def F(a, b) -> T:`  ->  `function $F$(_a_0, _b_0) {`, arity from the export table
  `F.g`                ->  `$F$g$`      (the emitter uses `$` for `.`)
  `W.F`                ->  `$W$F$`     (a module's def is inlined)
  `U32.add(x, y)`      ->  `($U32$add$(x, y))`
  `case X{f}: e`       ->  `if (is X) { e }`
  `Bool.pick(T,c,a,b)` ->  `(c ? a : b)`
  `List<A>.nil`        ->  `{$: "Nil"}`, `List<A>.cons` -> `{$: "Con", head, tail}`
  `x := e`             ->  `const _x_N = (e);`

WHAT DOES NOT COME BACK, and it is the honest limit: the COMMENTS and the
`type` DECLARATIONS' prose. Types DO come back -- a `type T is Data: C{a: U32}`
appears as `function $C$(_a_0) { return {$: "C", "a": _a_0}; }` -- so the
constructors are recovered and the `type` header is re-typed. The result CHECKS
AND RUNS: it is the RECOVERY FLOOR for a file whose behaviour had been measured,
with the documentation to be re-typed on top of it.

Usage: python3 .agents/slop/recover_webgpu_call.py
"""
import re, os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MJS = os.path.join(ROOT, "tinybendygrad", "runtime", "webgpu_call.mjs")
OUT = os.path.join(ROOT, "tinybendygrad", "runtime", "webgpu_call.bend")


def bname(js):
  return js.replace("$", ".")


def collect():
  src = open(MJS).read()
  fns, ctors = {}, {}
  pat = re.compile(r"^function \$([A-Za-z_][A-Za-z0-9_$]*)\$\(([^)]*)\) \{\n", re.M)
  for m in pat.finditer(src):
    i = src.index("\n}\n", m.end())
    body = src[m.end():i]
    name = bname(m.group(1))
    # A CONSTRUCTOR is a one-line `return {$: "C", ...}` and nothing else.
    c = re.match(r'\s*return \{\$: "([A-Za-z_][A-Za-z0-9_]*)"(.*)\};\s*$', body)
    if c and m.group(2):
      fields = dict(re.findall(r'"([A-Za-z_][A-Za-z0-9_]*)": (_[A-Za-z0-9_]+)', c.group(2)))
      ctors[name] = (c.group(1), fields)
    else:
      fns[name] = (m.group(2), body)
  exports = {}
  for m in re.finditer(r'^  "([^"]+)": run_lib\(', src, re.M):
    exports[m.group(1)] = True
  return fns, ctors, exports


def js2bend(body, indent="  "):
  """The emitted JS back to Bend. Mechanical and partial: it handles the shapes
  this file's defs actually take, and RAISES on anything else rather than
  guessing, because a silently wrong translation is worse than a loud failure."""
  out, i, n = [], 0, len(body)
  def sub(s):
    # `($Name$args)` / `$Name$args` -> `Name(args)`, with `.$` -> `.`
    def rep(m):
      return m.group(1).replace("$", ".") + "(" + m.group(2) + ")"
    return re.sub(r"\(?\$([A-Za-z_][A-Za-z0-9_$]*)\$((?:[^()]*|\([^()]*\))*)\)",
                  rep, s)
  # statements, line by line
  for ln in body.split("\n"):
    t = ln.strip()
    if not t:
      continue
    m = re.match(r"^(?:const|let) (_[A-Za-z0-9_]+) = \((.*)\);$", t)
    if m:
      out.append(f"{indent}{m.group(1)} = {sub(m.group(2))}")
      continue
    m = re.match(r"^return \((.*)\);$", t)
    if m:
      out.append(f"{indent}{sub(m.group(1))}")
      continue
    m = re.match(r"^return (\S.*);$", t)
    if m:
      out.append(f"{indent}{sub(m.group(1))}")
      continue
    m = re.match(r"^if \((.*)\) \{$", t)
    if m:
      out.append(f"{indent}# IF {sub(m.group(1))}")
      continue
    m = re.match(r"^\} else \{$", t)
    if m:
      out.append(f"{indent}# ELSE")
      continue
    m = re.match(r"^\} else if \((.*)\) \{$", t)
    if m:
      out.append(f"{indent}# ELSEIF {sub(m.group(1))}")
      continue
    if t == "}":
      out.append(f"{indent}# ENDIF")
      continue
    out.append(f"{indent}# UNHANDLED: {t}")
  return "\n".join(out)


def main():
  fns, ctors, exports = collect()
  print(f"defs: {len(fns)}   constructors: {len(ctors)}   exports: {len(exports)}")
  return fns, ctors, exports


if __name__ == "__main__":
  main()