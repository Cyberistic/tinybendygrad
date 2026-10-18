#!/usr/bin/env python3
"""apply_a.py -- SHAPE (A): thread the arena by rewriting the `param_src` idiom.

`UOp.new(ar, KIND, param_src(ar, SIZE), ARG, TAG)` becomes
`UOp.new.param(ar, KIND, SIZE, ARG, TAG)` -- same arity, same arena expression, and
`UOp.new.param` is the only spelling `ops.bend` itself declares safe, because it interns
the size node into `ar` and then interns the node into the GROWN `ar`.

THE POPULATION IS THE CENSUS'S, NOT A LIST. `census.py` discovers every `param_src(`
site by walking `tinybendygrad/**/*.bend`; this reads the same lexer and rewrites only
what it finds. Nothing here names a file, a line, or a callee -- `UOp.new` is matched as a
SUFFIX (`endswith`), so a file that imports ops as `X` instead of `O` is handled by the
same code.

THE ONE CLAIM THAT MUST BE CHECKED, NOT ASSUMED. The rewrite is sound only if
`param_src`'s arena argument IS `UOp.new`'s arena argument, textually. If a site ever
passed two different arenas, `UOp.new.param` would intern the size into `UOp.new`'s arena
where the old code interned it into another one -- a behaviour change, not a repair. Every
site is compared and a mismatch is a REFUSAL that aborts the whole run.

STATEMENTS, NOT LINES. `uop/weak.bend:288` and `uop/validate.bend:1950` write
`O.UOp.new(ar, K, O.param_src(ar, None{}),` and close the call on the NEXT line, so a
line-local rewriter sees an unbalanced call and gives up on a site that is perfectly
well-formed. A statement is accumulated until the bracket depth returns to 0.

usage: .venv/bin/python apply_a.py [--apply] [--verbose]
"""
from __future__ import annotations

import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import census  # noqa: E402  -- the lexer is shared, not copied

ROOT = census.ROOT
OPEN, CLOSE = census.OPEN, census.CLOSE
SITE = re.compile(r"\bparam_src\(")


def split_top(body: str) -> list[str]:
  """top-level comma split of an argument list. `<`/`>` nest because `Maybe<&2, U32>`
  holds one; a string span is opaque."""
  out, cur, stack, i, n = [], [], [], 0, len(body)
  while i < n:
    ch = body[i]
    if ch in census.QUOTES:
      j = i + 1
      while j < n and body[j] != ch:
        j += 2 if body[j] == "\\" else 1
      cur.append(body[i:j + 1])
      i = j + 1
      continue
    if ch in OPEN:
      stack.append(OPEN[ch])
    elif ch in CLOSE and stack and stack[-1] == ch:
      stack.pop()
    elif ch == "<":
      stack.append(">")
    elif ch == ">" and stack and stack[-1] == ">":
      stack.pop()
    if ch == "," and not stack:
      out.append("".join(cur))
      cur = []
    else:
      cur.append(ch)
    i += 1
  out.append("".join(cur))
  return out


def norm(s: str) -> str:
  return " ".join(s.split())


def depth_of(code: str) -> int:
  """Bracket depth of CODE. It SKIPS string spans, because `uop/upat.bend:1437` is
  `fmt.go(String.split(fmt, '{'), ...)` and a naive character count reads that `'{'` as
  an opener -- which is how the first version of this function reported nine files as
  holding an unclosed statement."""
  d, i, n = 0, 0, len(code)
  while i < n:
    ch = code[i]
    if ch in census.QUOTES:
      i += 1
      while i < n and code[i] != ch:
        i += 2 if code[i] == "\\" else 1
      i += 1
      continue
    if ch in OPEN:
      d += 1
    elif ch in CLOSE:
      d -= 1
    i += 1
  return d


def span_of(code: str, at: int) -> tuple[int, list[str]]:
  """(offset just past the closer, top-level args) for the call whose `(` is at `at`."""
  d, i, n = 0, at, len(code)
  while i < n:
    ch = code[i]
    if ch in census.QUOTES:
      j = i + 1
      while j < n and code[j] != ch:
        j += 2 if code[j] == "\\" else 1
      i = j + 1
      continue
    if ch in OPEN:
      d += 1
    elif ch in CLOSE:
      d -= 1
      if d == 0:
        return i + 1, split_top(code[at + 1:i])
    i += 1
  raise ValueError("UNBALANCED")


def enclosing(code: str, at: int) -> tuple[int, str] | None:
  """(offset of the enclosing call's `(`, its callee name), by a backward bracket walk
  over CODE only. The `(` is FOUND by the walk, not by `rindex("(", ...)`: the last `(`
  before a `param_src` site belongs to whatever call sits inside the src expression
  (`O.Arena.empty()`), which is how the first draft of this file read every five-argument
  call as a one-argument one."""
  debt = 0
  for i in range(at - 1, -1, -1):
    ch = code[i]
    if ch in CLOSE:
      debt += 1
    elif ch in OPEN:
      if debt == 0:
        j = i - 1
        while j >= 0 and (code[j].isalnum() or code[j] in "._"):
          j -= 1
        return i, code[j + 1:i]
      debt -= 1
  return None


def rewrite(code: str) -> tuple[list[tuple[int, int, str]], list[str]]:
  """([(start, end, replacement)] in statement offsets, refusals). Non-overlapping by
  construction: every replacement covers a whole call, and a site's call encloses it."""
  out: list[tuple[int, int, str]] = []
  refusals: list[str] = []
  pos = 0
  while (m := SITE.search(code, pos)) is not None:
    pos = m.end()
    if code[:m.start()].rstrip().endswith("def"):
      continue
    found = enclosing(code, m.start())
    if found is None:
      refusals.append("no enclosing call")
      continue
    open_at, who = found
    if not who.endswith("UOp.new"):
      refusals.append(f"enclosing callee is {who!r}, not a UOp.new")
      continue
    try:
      end, args = span_of(code, open_at)
    except ValueError:
      refusals.append(f"unbalanced call for the {who} holding the site")
      continue
    if len(args) != 5:
      refusals.append(f"{who} has {len(args)} args, expected 5")
      continue
    pm = re.match(r"^[A-Za-z_][A-Za-z0-9_.]*\.param_src\((.*)\)$", args[2].strip(), re.S)
    if not pm:
      refusals.append(f"src arg is {norm(args[2])[:60]!r}, not a param_src call")
      continue
    pargs = split_top(pm.group(1))
    if len(pargs) != 2:
      refusals.append(f"param_src has {len(pargs)} args, expected 2")
      continue
    if norm(pargs[0]) != norm(args[0]):
      refusals.append(f"ARENAS DIFFER: {who} builds in {norm(args[0])!r} but param_src "
                      f"interned the size into {norm(pargs[0])!r}")
      continue
    # The replacement SPAN starts at the callee NAME, not at its `(`: `code[open_at:end]`
    # begins at the bracket, so a replacement text carrying `who` again prints
    # `O.UOp.newO.UOp.new.param` -- which is what the first application did, on fold.bend,
    # in 23 places, and bend reported it as `observed : O.UOp.newO.UOp.new.param`.
    out.append((open_at - len(who), end,
                f"{who}.param({norm(args[0])}, {norm(args[1])}, {norm(pargs[1])}, "
                f"{norm(args[3])}, {norm(args[4])})"))
  return out, refusals


def statements(lines: list[str]):
  """[(first, last, code, refusals)] -- 1-based, inclusive line numbers.

  The depth is the RUNNING TOTAL, not the line's own: `uop/weak.bend:287` opens
  `Bool.pick(` and closes it on 292, and a per-line test breaks on 293's blank line --
  which is how the first version of this function reported "unbalanced call" for a call
  that is perfectly well formed."""
  out, i, n = [], 0, len(lines)
  while i < n:
    first = i
    code, refusals, total = "", [], 0
    while i < n:
      c, why = census.lex(lines[i])
      refusals += [f"line {i + 1}: {why}"] if why else []
      code += " " * len(lines[i]) if why else c
      i += 1
      if why:
        break
      total += depth_of(c)
      if total <= 0:
        break
    if total > 0:
      refusals.append(f"statement opens {total} bracket(s) and never closes them")
    out.append((first + 1, i, code, refusals))
  return out


def splice(code: str, reps: list[tuple[int, int, str]]) -> str:
  for a, b, txt in sorted(reps, key=lambda r: -r[0]):
    code = code[:a] + txt + code[b:]
  return code


def plan(path: pathlib.Path) -> tuple[list[tuple[int, int, str]], list[str]]:
  """([(first, last, new statement text)], refusals) for one file."""
  lines = path.read_text().split("\n")
  edits, refusals = [], []
  for first, last, code, why in statements(lines):
    rel = f"{path.relative_to(ROOT)}:{first}"
    # A statement this lexer cannot read is a REFUSAL, and it is FATAL only when it could
    # hide a site -- an unlexable statement elsewhere in the tree is a named hole in the
    # INSTRUMENT, not a reason to refuse to repair the 62 sites it can see. Both numbers
    # are printed, so the hole is a row and not a silence.
    refusals += [f"{rel} REFUSED-STATEMENT {w}"
                 + (" CARRYING-A-SITE" if census.SITE.search(code) else "")
                 for w in why]
    reps, rs = rewrite(code)
    for r in rs:
      refusals.append(f"{rel} {r} CARRYING-A-SITE")
    if reps:
      edits.append((first, last, splice(code, reps)))
  return edits, refusals


def main() -> None:
  apply = "--apply" in sys.argv
  verbose = "--verbose" in sys.argv
  refused: list[str] = []
  fatal = 0
  total = 0
  edits: list[tuple[pathlib.Path, list]] = []
  for p in sorted(ROOT.rglob("*.bend")):
    e, rs = plan(p)
    refused += rs
    fatal += sum(1 for r in rs if r.endswith("CARRYING-A-SITE"))
    if e:
      total += len(e)
      edits.append((p, e))
      if verbose:
        print(f"{p.relative_to(ROOT)}: {len(e)} statement(s)")
  for r in refused:
    print(r)
  print(f"\n{'TOTAL' if apply else 'PLAN'} {total} sites"
        f" | REFUSED statements {len(refused)} of which CARRYING-A-SITE {fatal}")
  if fatal:
    print("NOTHING APPLIED: a partial migration is a build break, not a partial result.")
    sys.exit(1)
  if apply:
    for p, e in edits:
      lines = p.read_text().split("\n")
      for first, last, code in sorted(e, key=lambda x: -x[0]):
        new = code.split("\n")
        lines[first - 1:last] = new + [""] * max(0, last - first + 1 - len(new))
      p.write_text("\n".join(lines))
    print("APPLIED")


if __name__ == "__main__":
  main()