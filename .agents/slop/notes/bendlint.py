#!/usr/bin/env python3
"""Static checker for the Bend binder-window rules.

bend 2.0.34's match_flatten keeps an ORDERED window of open binders (the
def's parameters, then whatever a case pattern binds). A match may only
scrutinise the value at the HEAD of that window; a var column can skip a
binder only when every skipped column is itself a var pattern. In practice
that means: within one def, matches must appear in parameter order, and a
case binder becomes matchable only after the match that produced it.

`bend --check-only` reports ONE failure per run, which makes a 1500 line
file take hundreds of round trips. This walks the file once and prints
every violation with its line number.
"""
import re
import sys

DEF_RE = re.compile(r"^def\s+([A-Za-z0-9_.]+)\s*\(", re.M)


def strip_comments(text):
  """Blank out `#` comments, keeping line numbering and column count."""
  out = []
  for line in text.split("\n"):
    res, in_str, q = "", False, ""
    i = 0
    while i < len(line):
      c = line[i]
      if in_str:
        res += c
        if c == "\\" and i + 1 < len(line):
          res += line[i + 1]
          i += 2
          continue
        if c == q:
          in_str = False
      elif c in "\"'":
        in_str, q = True, c
        res += c
      elif c == "#":
        res += " " * (len(line) - i)
        break
      else:
        res += c
      i += 1
    out.append(res)
  return "\n".join(out)


def defs(text):
  """Yield (name, params, body_start_line, body) for every top-level def."""
  lines = text.split("\n")
  i = 0
  while i < len(lines):
    m = DEF_RE.match(lines[i])
    if not m:
      i += 1
      continue
    name = m.group(1)
    # the parameter list may wrap over several lines
    j, depth, buf = i, 0, ""
    while j < len(lines):
      buf += lines[j] + "\n"
      depth += lines[j].count("(") - lines[j].count(")")
      if depth <= 0 and "(" in buf:
        break
      j += 1
    params = buf[buf.index("(") + 1: buf.rindex(")")]
    names = []
    for chunk in re.split(r",(?![^<(\[]*[>)\]])", params):
      chunk = re.sub(r"^\s*\+", "", chunk.strip())
      mm = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\s*:", chunk)
      if mm:
        names.append(mm.group(1))
      elif chunk.strip():
        names.append(chunk.strip())
    # the body is every following line indented past the `def`
    base = len(lines[i]) - len(lines[i].lstrip())
    k = j + 1
    body = []
    while k < len(lines):
      ln = lines[k]
      if ln.strip() and (len(ln) - len(ln.lstrip())) <= base:
        break
      body.append((k + 1, ln))
      k += 1
    yield name, names, body
    i = k


def tree(body):
  """Group a def body into a nesting tree keyed by indentation.

  bend scopes each `case` row independently -- `match a: case X: match b:` and
  `case Y: match b:` are separate worlds -- so a flat scan of the lines cannot
  tell a legal sibling from a use-after-consume. The tree can.
  """
  root = {"kind": "def", "line": 0, "kids": []}
  stack = [(-1, root)]
  for lineno, raw in body:
    stripped = raw.strip()
    if not stripped:
      continue
    indent = len(raw) - len(raw.lstrip())
    while stack and stack[-1][0] >= indent:
      stack.pop()
    parent = stack[-1][1]
    m = re.match(r"match\s+(.+?):\s*$", stripped)
    kind = "match" if m else "case" if re.match(r"case\s", stripped) else "leaf"
    node = {"kind": kind, "line": lineno, "text": stripped, "kids": []}
    parent["kids"].append(node)
    stack.append((indent, node))
  return root


def binders(pat):
  pat = re.sub(r"[A-Z][A-Za-z0-9_]*(\{|,|\s|\(|$)", " ", pat)
  return {t for t in re.split(r"[{}\[\]<>,\s]+", pat)
          if re.fullmatch(r"[a-z_][A-Za-z0-9_]*", t)}


def walk(name, node, pend, bound, lets, bad):
  """`pend` is the ordered window of open PARAMETERS; `bound` the case
  binders, which are matchable whatever else is pending; `lets` the locals,
  which take the head and so block everything.

  `lets` accumulates across the SIBLINGS of one body, because a body is a
  sequence: `case Sb{p}: t = Zb{}; match p:` is exactly the shape bend bans.
  """
  for kid in node["kids"]:
    # a let is a sibling of the match it blocks, so it is handled HERE rather
    # than inside a recursive call that would scope it away
    lm = re.match(r"([A-Za-z_][A-Za-z0-9_]*)\s*=\s", kid["text"])
    if lm:
      lets = lets + [lm.group(1)]
      continue
    if kid["kind"] == "match":
      sus = kid["text"][6:-1].split()
      first = sus[0]
      if first not in pend and first not in bound:
        bad.append((kid["line"], name, kid["text"], "NOT-BOUND"))
        continue
      if first in lets:
        bad.append((kid["line"], name, kid["text"],
                    f"let {first} (a match cannot scrutinize a local binder)"))
        continue
      if lets:
        bad.append((kid["line"], name, kid["text"],
                    "let " + lets[0] + " (a local bound above the match)"))
        continue
      # a case binder is substituted in and matchable whatever else is pending.
      # For a PARAMETER match, every pending parameter ahead of the scrutinee
      # must be dead -- being USED is fine, being MATCHED later is not, which is
      # what the recursion below would discover.
      ahead = pend[:pend.index(first)] if first in pend else []
      for w in ahead:
        if matched_later(kid, w):
          bad.append((kid["line"], name, kid["text"], w))
          break
      nxt = [p for p in pend if p not in sus]
      for kid2 in kid["kids"]:
        if kid2["kind"] == "case":
          walk(name, kid2, nxt, bound | binders(kid2["text"][5:-1]), lets, bad)
        else:
          walk(name, kid2, nxt, bound, lets, bad)
      continue
    if kid["kind"] == "case":
      walk(name, kid, pend, bound | binders(kid["text"][5:-1]), lets, bad)
      continue
    walk(name, kid, pend, bound, lets, bad)




def matched_later(node, name):
  for kid in node["kids"]:
    if kid["kind"] == "match" and kid["text"][6:-1].split()[0] == name:
      return True
    if matched_later(kid, name):
      return True
  return False


def lint(path):
  text = strip_comments(open(path).read())
  bad = []
  for name, params, body in defs(text):
    walk(name, tree(body), list(params), set(), [], bad)
  for lineno, name, line, win in bad:
    print(f"{path}:{lineno}: [{name}] `match` blocked by {win}\n    {line}")
  print(f"{len(bad)} violation(s) in {path}")
  return len(bad)


if __name__ == "__main__":
  rc = 0
  for p in sys.argv[1:]:
    rc |= bool(lint(p))
  sys.exit(rc)
