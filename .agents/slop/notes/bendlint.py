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
    # pending PARAMETERS, in signature order. bend's match_flatten keeps an
    # ordered window of these (plus any `x = ...` locals, which take the head);
    # a match may only scrutinise the head. Case binders do NOT block: a var
    # column is a substitution, so `case h <> t: match h:` is legal.
    pend = list(params)
    lets = []
    bound = set()
    for idx, (lineno, raw) in enumerate(body):
      stripped = raw.strip()
      if not stripped:
        continue
      m = re.match(r"case\s+(.+?):\s*$", stripped)
      if m:
        pat = re.sub(r"[A-Z][A-Za-z0-9_]*(\{|,|\s|\(|$)", " ", m.group(1))
        bound |= {t for t in re.split(r"[{}\[\]<>,\s]+", pat)
                  if re.fullmatch(r"[a-z_][A-Za-z0-9_]*", t)}
        continue
      m = re.match(r"match\s+(.+?):\s*$", stripped)
      if m:
        sus = m.group(1).split()
        rest = "\n".join(l for _, l in body[idx:])
        ok = sus[0] in pend or sus[0] in bound
        if not ok:
          bad.append((lineno, name, stripped, "NOT-BOUND"))
        elif sus[0] in pend:
          # a case binder is substituted in and matchable whatever else is
          # pending; only a PARAMETER match obeys the pending-parameter order
          blockers = [w for w in pend[:pend.index(sus[0])]
                      if re.search(r"(?<![\w.])" + re.escape(w) + r"(?![\w])", rest)]
          blockers += [w for w in lets if w in rest.split()]
          if blockers:
            bad.append((lineno, name, stripped, " ".join(blockers)))
        for s in sus:
          if s in pend:
            pend.remove(s)
        continue
      m = re.match(r"([A-Za-z_][A-Za-z0-9_]*)\s*=\s", stripped)
      if m and m.group(1) not in lets:
        lets.append(m.group(1))
  for lineno, name, line, win in bad:
    print(f"{path}:{lineno}: [{name}] `match` blocked by {win}\n    {line}")
  print(f"{len(bad)} violation(s) in {path}")
  return len(bad)


if __name__ == "__main__":
  rc = 0
  for p in sys.argv[1:]:
    rc |= bool(lint(p))
  sys.exit(rc)
