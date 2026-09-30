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


def lint(path):
  text = strip_comments(open(path).read())
  bad = []
  for name, params, body in defs(text):
    window = list(params)
    stack = []  # (indent, kind)
    tail = "\n".join(l for _, l in body)
    for idx, (lineno, raw) in enumerate(body):
      stripped = raw.strip()
      if not stripped:
        continue
      indent = len(raw) - len(raw.lstrip())
      while stack and stack[-1][0] >= indent:
        stack.pop()
      m = re.match(r"match\s+(.+?):\s*$", stripped)
      if m:
        sus = m.group(1).split()
        rest = "\n".join(l for _, l in body[idx:])
        ahead = window[:window.index(sus[0])] if sus[0] in window else window
        blockers = [w for w in ahead
                    if re.search(r"(?<![\w.])" + re.escape(w) + r"(?![\w])", rest)]
        if sus[0] not in window or blockers:
          bad.append((lineno, name, stripped, " ".join(blockers) or "NOT-IN-WINDOW"))
        for s in sus:
          if s in window:
            window.remove(s)
        stack.append((indent, "match"))
        continue
      m = re.match(r"case\s+(.+?):\s*$", stripped)
      if m and stack:
        # every lowercase-initial identifier in a case pattern is a binder and
        # joins the window at this point, in the order written
        body_ = re.sub(r"[A-Z][A-Za-z0-9_]*(\{|,|\s|\(|$)", " ", m.group(1))
        for tok in reversed(re.split(r"[{}\[\]<>,\s]+", body_)):
          if re.fullmatch(r"[a-z_][A-Za-z0-9_]*", tok) and tok not in window:
            window.insert(0, tok)
        stack.append((indent, "case"))
        continue
      m = re.match(r"([A-Za-z_][A-Za-z0-9_]*)\s*=\s", stripped)
      if m:
        if m.group(1) not in window:
          window.insert(0, m.group(1))
        stack.append((indent, "let"))
        continue
  for lineno, name, line, win in bad:
    print(f"{path}:{lineno}: [{name}] `match` blocked by {win}\n    {line}")
  print(f"{len(bad)} violation(s) in {path}")
  return len(bad)


if __name__ == "__main__":
  rc = 0
  for p in sys.argv[1:]:
    rc |= bool(lint(p))
  sys.exit(rc)
