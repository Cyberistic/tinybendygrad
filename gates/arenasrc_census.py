"""arenasrc_census.py -- THE POPULATION: EVERY WAY THE PORT PUTS A SIZE INTO A NODE.

    .venv/bin/python gates/arenasrc_census.py            # totals per class and per file
    .venv/bin/python gates/arenasrc_census.py --rows     # one row per site

THIS FILE IS ALSO THE LEXER. `gates/arenasrc_probe-check.py` and the one-shot migration
tool import `lex`, `statements`, `enclosing` and `span_of` from here rather than keeping a
second copy: the tree already lost two of nine gate drivers to a prune because an
instrument's parser lived somewhere the tree was clearing.

THE POPULATION IS A DIRECTORY WALK. `ROOT.rglob("*.bend")` over `tinybendygrad/`, then
every line. NOTHING HERE NAMES A FILE, A LINE, OR A CALLEE. `gates/paramarg_shape.bend`
and `gates/arenasrc_rows.bend` name a callee in their own source, which is the third
admissible form (a regex over the tree's own write sites, with the list admitted in the
source); a BASENAME SHAPE, A SUFFIX SET, AND A HAND LIST ARE NOT POPULATIONS.

TWO CLASSES, AND THEY ARE DIFFERENT DEFECTS THAT PRINT THE SAME ROW.

  `param_src`  a BUFFER/ALLOC/PARAM whose `src` came from `O.param_src`, which interned
               the size node into a THROWAWAY arena and handed back only the index. The
               node ends up its OWN parent: `Arena.src` answers the index, and the answer
               is wrong. This is the class this census was written for and it is now 0.

  `nil-src`    a param-shaped node (`AParam{...}` is its arg) built with `Nil{}` as `src`.
               Not a self-loop: `nsrc == 0`, so `ParamArg.size(ar, i)` -- which reads
               `src[0]` -- answers `None` and the node simply HAS NO SIZE. Both print
               `size=N`, and the acceptance rows cannot tell them apart, so the census
               has to. The `AParam` test is structural: a node owns a size only if its
               arg is the port's param record, so a new param-shaped kind is picked up
               without editing a list here.

WHY LINE-LOCAL LEXING. The first version kept one bracket stack per FILE and it was
wrong: `tinybendygrad/codegen/decomp/dtype-mut.bend:2646` carries the string `"# l2i\\n"`,
a `#` INSIDE a string, and a file-global pass whose string state is shifted by one quote
swallows the closing `"])`, leaving the stack open to EOF and refusing a file that parses.
`statements()` groups lines until the RUNNING bracket depth returns to 0, so a
multi-line call is one unit and a line that will not lex is a REFUSED STATEMENT, COUNTED,
never a silent skip.

MEASURED, Bend accepts BOTH quote characters: `tinybendygrad/uop/upat.bend:1426` is
`String.split(p, '}')`, and scanning that `}` as a bracket refuses the file.
"""
from __future__ import annotations

import bisect
import collections
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1] / "tinybendygrad"
QUOTES = "\"'"
OPEN = {"(": ")", "[": "]", "{": "}"}
CLOSE = {v: k for k, v in OPEN.items()}
SITE = re.compile(r"\bparam_src\(")
CONSTRUCTOR = re.compile(r"[A-Za-z_][A-Za-z0-9_.]*\.UOp\.new(?:\.\w+)?\(")


def lex(line: str) -> tuple[str, str | None]:
  """(code, refusal). `code` is the line with any trailing `#` comment blanked. A quote
  span is consumed left to right and a `#` outside one starts the comment, so an
  apostrophe inside a COMMENT is never mistaken for a literal. A quote with no partner on
  the line is a refusal, because guessing would move a bracket."""
  out: list[str] = []
  i, n = 0, len(line)
  while i < n:
    ch = line[i]
    if ch in QUOTES:
      j = i + 1
      while j < n and line[j] != ch:
        j += 2 if line[j] == "\\" else 1
      if j >= n:
        return "".join(out), f"UNTERMINATED {ch!r}"
      out.append(line[i:j + 1])
      i = j + 1
      continue
    if ch == "#":
      out.append(" " * (n - i))
      return "".join(out), None
    out.append(ch)
    i += 1
  return "".join(out), None


def depth_of(code: str) -> int:
  """Bracket depth of CODE. It SKIPS string spans: `uop/upat.bend:1437` is
  `fmt.go(String.split(fmt, '{'), ...)` and a naive character count reads that `'{'` as
  an opener."""
  d, i, n = 0, 0, len(code)
  while i < n:
    ch = code[i]
    if ch in QUOTES:
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


def split_top(body: str) -> list[str]:
  """top-level comma split of an argument list. `<`/`>` nest because `Maybe<&2, U32>`
  holds one; a string span is opaque."""
  out, cur, stack, i, n = [], [], [], 0, len(body)
  while i < n:
    ch = body[i]
    if ch in QUOTES:
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


def span_of(code: str, at: int) -> tuple[int, list[str]]:
  """(offset just past the closer, top-level args) for the call whose `(` is at `at`."""
  d, i, n = 0, at, len(code)
  while i < n:
    ch = code[i]
    if ch in QUOTES:
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
  """(offset of the enclosing call's `(`, its callee name), by a BACKWARD bracket walk
  over CODE only. The `(` is FOUND by the walk, never by `rindex("(", ...)`: the last `(`
  before a site belongs to whatever call sits inside the src expression
  (`O.Arena.empty()`), which is how a first draft read every five-argument call as a
  one-argument one."""
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


def statements(lines: list[str]):
  """[(first, last, code, refusals)] -- 1-based, inclusive. The depth is the RUNNING
  TOTAL, not the line's own: `uop/weak.bend:287` opens `Bool.pick(` and closes it on
  292, and a per-line test breaks on 293's blank line."""
  out, i, n = [], 0, len(lines)
  while i < n:
    first = i
    code, refusals, total = "", [], 0
    while i < n:
      c, why = lex(lines[i])
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


def walk():
  """[(relpath, first_line, code, refusals)] for every statement of every `.bend` file."""
  for p in sorted(ROOT.rglob("*.bend")):
    rel = str(p.relative_to(ROOT))
    for first, last, code, why in statements(p.read_text().split("\n")):
      yield p, rel, first, code, why


def census(rows: bool = False):
  """(rows, totals). `totals` carries the class counts AND the refusal counts, so a
  caller cannot report a green number without also reporting the holes."""
  rows_out: list[tuple[str, int, str, str, str]] = []
  per_class: collections.Counter = collections.Counter()
  per_file: collections.Counter = collections.Counter()
  refused = refused_carrying = 0
  for p, rel, first, code, why in walk():
    if why:
      refused += len(why)
      if any(SITE.search(code) for _ in [0]):
        refused_carrying += 1
      continue
    for m in SITE.finditer(code):
      if code[:m.start()].rstrip().endswith("def"):
        continue
      found = enclosing(code, m.start())
      who = found[1] if found else "<toplevel>"
      per_class[f"param_src/{who}"] += 1
      per_file[rel] += 1
      rows_out.append((rel, code.count("\n", 0, m.start()) + first, "param_src", who,
                       norm(code[found[0] - len(who):code.index(")", found[0]) + 1])[:76]
                       if found else ""))
    for m in CONSTRUCTOR.finditer(code):
      try:
        _end, args = span_of(code, m.end() - 1)
      except ValueError:
        continue
      if len(args) != 5 or norm(args[2]) != "Nil{}" or "AParam" not in args[3]:
        continue
      per_class[f"nil-src/{norm(args[1])}"] += 1
      per_file[rel] += 1
      rows_out.append((rel, code.count("\n", 0, m.start()) + first, "nil-src", norm(args[1]),
                       norm(code[m.start() - 10:m.end()])[:76]))
  totals = {"files": len(list(ROOT.rglob("*.bend"))),
            "refused_statements": refused,
            "refused_carrying_a_site": refused_carrying,
            "classes": per_class, "per_file": per_file}
  return rows_out, totals


def main() -> None:
  import sys
  rows_arg = "--rows" in sys.argv
  rows, totals = census(rows_arg)
  if rows_arg:
    for rel, ln, cls, who, txt in rows:
      print(f"{rel}:{ln}\t{cls}\t{who}\t{txt}")
  print(f"FILES-WALKED\t{totals['files']}")
  print(f"REFUSED-STATEMENTS\t{totals['refused_statements']}")
  print(f"REFUSED-STATEMENTS-CARRYING-A-SITE\t{totals['refused_carrying_a_site']}")
  for k, v in sorted(totals["classes"].items()):
    print(f"CLASS\t{k}\t{v}")
  print("--- per file ---")
  for k, v in sorted(totals["per_file"].items(), key=lambda kv: (-kv[1], kv[0])):
    print(f"FILE\t{k}\t{v}")


if __name__ == "__main__":
  main()