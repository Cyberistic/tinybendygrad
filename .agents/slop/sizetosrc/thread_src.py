#!/usr/bin/env python3
"""thread_src.py -- build every BUFFER/ALLOC/PARAM through `UOp.new.param`.

72f98ffe0 ("move size from ParamArg to src (#18624)") put the element count in
`src[0]` for BUFFER (`ops.py:829`), ALLOC (`ops.py:1187`) and PARAM (`ops.py:1222`),
and gave `variable`/`range_var` an EMPTY STACK (`ops.py:1003`).

An `Arena` is an IMMUTABLE value, so the size node must be interned and its arena
carried into the node's own interning. Two spellings exist today and only one is safe:

    UOp.new(ar, OpsKIND{}, O.param_src(ar, SIZE), arg, tag)   UNSAFE -- self-loop
    UOp.new.param(ar, OpsKIND{}, SIZE, arg, tag)              SAFE

`param_src` drops the arena its size node was interned into, so the index names
nothing in the caller's arena and the node ends up pointing at itself. MEASURED on
`.agents/slop/sizetosrc/paramsrc_probe.bend`; `ops.bend`'s `UOp.new.param` note has
the numbers. This converts both the `Nil{}` sites (size recovered from the AParam
helper's own argument list) and the `param_src` sites (size read out of the call).

Arguments are found by BALANCED scanning, not by a regular expression: `S.uint64()`
and `Some{"slots"}` are both arguments and a `[^()]*` pattern declines to match a call
it cannot see the end of. A site it cannot parse is a REFUSAL, never a silent skip.

usage: .venv/bin/python thread_src.py FILE... [--apply]
       without --apply it prints the PLAN and rewrites nothing.
"""
from __future__ import annotations
import argparse, pathlib, re, sys

PAIRS = {"(": ")", "[": "]", "{": "}"}
#: helper -> (index of the `size` argument, expected argument count). A `None` index means
#: the helper carries no size and its node gets the empty STACK. Every entry here was read
#: out of that helper's OWN signature (`def <helper>(...)`); a helper that is not listed is
#: REFUSED, because inventing its size index is how a migration goes quietly wrong.
SIZE_ARG = {"alloc": (1, 2), "allocbuf": (1, 3), "paramf": (1, 3), "paramd": (2, 5),
            "allocd": (2, 3), "var": (None, 1), "mn_pbuf": (1, 3)}
KIND = re.compile(r"^\s*(O\.)?Ops(BUFFER|ALLOC|PARAM)\{\}\s*$")
APARAM = re.compile(r"^\s*(O\.)?AParam\{(\w+)\((.*)\)\}\s*$", re.S)
PARAMSRC = re.compile(r"^\s*(O\.)?param_src\(\s*(.+?)\s*,\s*(.+?)\s*\)$", re.S)


def split_top(body: str) -> list[str]:
  """top-level comma split; `<`/`>` nest because `Maybe<&2, U32>` holds one, and a
  string literal is opaque."""
  out, cur, stack = [], [], []
  i = 0
  while i < len(body):
    ch = body[i]
    if ch == '"':
      j = i + 1
      while j < len(body) and body[j] != '"':
        j += 2 if body[j] == "\\" else 1
      cur.append(body[i:j + 1]); i = j + 1; continue
    if ch in PAIRS: stack.append(PAIRS[ch])
    elif ch in ")]}>" and stack and ch == stack[-1]: stack.pop()
    elif ch == "<": stack.append(">")
    elif ch == ">" and stack and stack[-1] == ">": stack.pop()
    if ch == "," and not stack:
      out.append("".join(cur)); cur = []
    else:
      cur.append(ch)
    i += 1
  out.append("".join(cur))
  return out


def calls(s: str, path: pathlib.Path, pat: str = r"\bUOp\.new\("):
  """(start, end, args) for every call matching `pat` -- balanced, so a nested call
  (`O.AParam{alloc(0)}`, `S.uint64()`) is ONE argument and not three."""
  for m in re.finditer(pat, s):
    i, depth, start = m.end(), 1, m.end()
    while i < len(s) and depth:
      ch = s[i]
      if ch == '"':
        i += 1
        while i < len(s) and s[i] != '"':
          i += 2 if s[i] == "\\" else 1
      elif ch in PAIRS: depth += 1
      elif ch in ")]}": depth -= 1
      i += 1
    if depth:
      sys.exit(f"{path}: UNBALANCED UOp.new( at line {s[:m.start()].count(chr(10)) + 1} -- REFUSED")
    yield m.start(), i - 1, split_top(s[start:i - 1])


class Refusal(Exception):
  """A site this tool will not rewrite. NEVER a guess and never a silent skip: the
  migration is a build-or-nothing change (bend enforces exact arity and reports one
  error at a time), so a site left half-migrated is a red tree, not a partial result."""


def size_of(path: pathlib.Path, s: str, ln: int, src: str, arg: str) -> str:
  """the size expression for a node whose src is not yet the size node."""
  ps = PARAMSRC.match(src)
  if ps:
    return ps.group(3)
  if src.strip() != "Nil{}":
    raise Refusal(f"src {src.strip()[:50]!r} is neither Nil{{}} nor param_src(..)")
  am = APARAM.match(arg)
  if not am:
    raise Refusal(f"{arg.strip()[:60]!r} is not AParam{{HELPER(..)}}")
  helper, hargs = am.group(2), split_top(am.group(3))
  if helper not in SIZE_ARG:
    raise Refusal(f"unknown helper {helper!r} -- the size is not recoverable from the "
                  f"arg list, and it is NOT a param_src site, so guessing would invent it")
  idx, want = SIZE_ARG[helper]
  if len(hargs) != want:
    raise Refusal(f"{helper} has {len(hargs)} args, expected {want}")
  return "None{}" if idx is None else "Some{" + hargs[idx].strip() + "}"


def plan_for(path: pathlib.Path, s: str):
  plan, skipped, refused = [], [], []
  for start, end, args in calls(s, path):
    ln = s[:start].count("\n") + 1
    if len(args) != 5 or not KIND.match(args[1]):
      skipped.append((ln, " ".join(a.strip() for a in args)[:88])); continue
    arena, op, src, arg, tag = (a.strip() for a in args)
    try:
      size = size_of(path, s, ln, src, arg)
    except Refusal as e:
      refused.append((ln, str(e), arg.strip()[:80])); continue
    new = f"UOp.new.param({arena}, {op}, {size}, {arg}, {tag})"
    plan.append((ln, s[start:end + 1], new))
  return plan, skipped, refused


def main() -> None:
  ap = argparse.ArgumentParser()
  ap.add_argument("files", nargs="+")
  ap.add_argument("--apply", action="store_true")
  ap.add_argument("--verbose", action="store_true", help="print every rewritten site")
  a = ap.parse_args()
  total = refused_total = 0
  plans = {}
  for f in a.files:
    p = pathlib.Path(f)
    s = p.read_text()
    plan, skipped, refused = plan_for(p, s)
    plans[f] = plan
    for ln, old, new in plan:
      if a.verbose: print(f"{p}:{ln}\n  - {old}\n  + {new}")
    total += len(plan); refused_total += len(refused)
    print(f"{p}: {len(plan)} sites -> UOp.new.param")
    for ln, why, arg in refused:
      print(f"  REFUSED {p}:{ln} {why}")
      print(f"          arg = {arg}")
  print(f"\nTOTAL {total} rewritten, {refused_total} REFUSED")
  if refused_total:
    print("NOTHING APPLIED: a partial migration is a build break, not a partial result.")
    sys.exit(1)
  if a.apply:
    for f, plan in plans.items():
      p = pathlib.Path(f)
      s = p.read_text()
      out, last = [], 0
      for ln, old, new in plan:
        i = s.index(old, last)
        out.append(s[last:i]); out.append(new); last = i + len(old)
      out.append(s[last:])
      p.write_text("".join(out))
    print("APPLIED")


if __name__ == "__main__":
  main()