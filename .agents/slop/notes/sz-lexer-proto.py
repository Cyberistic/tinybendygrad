#!/usr/bin/env python3
# The lexer prototype: a byte-level transcription of the tokenizer sz.py gets from
# CPython's tokenize, written so it can be lifted into Bend one def at a time.
# NOT a deliverable -- it exists so the differential test can run against something
# faster to iterate on than the type checker. Same def names, same order as sz.bend.
#
# Acc = (i, tok, lines, last, line, blank)
# St  = ('T',) | ('C', back) | ('L', q, back, close, tri)
import os, sys, token, tokenize

OP2EQ = frozenset(map(ord, '!%&*+-/:<=>@^|'))   # the operators that pair with '='
OP2SAME = frozenset(map(ord, '*/<>'))            # ** // << >> : the operators doubled
OP3 = frozenset(map(ord, '*/<>'))                # and those plus '='
PFX1 = frozenset('bruf')
PFX2 = frozenset(('br', 'rb', 'fr', 'rf'))
HEX = frozenset(map(ord, '0123456789abcdefABCDEF'))
OCT = frozenset(map(ord, '01234567'))
BIN = frozenset(map(ord, '01'))
DEC = frozenset(map(ord, '0123456789'))
QUOTES = frozenset((34, 39))
JSUF = frozenset((106, 74))
ESUF = frozenset((101, 69))
SGN = frozenset((43, 45))
NL = 10
CR = 13
BS = 92
HASH = 35
LBRACE = 123
RBRACE = 125
DOT = 46
EQ = 61

UNTERM_F = "unterminated f-string literal (detected at line 1)"
UNTERM_S = "unterminated string literal (detected at line 1)"
UNTERM_T = "EOF in multi-line string"


class Err(Exception):
  pass


def op_len(c0, c1, c2):
  if c0 == DOT: return 3 if (c1 == DOT and c2 == DOT) else 1
  two = (c1 == EQ and c0 in OP2EQ) or (c1 == c0 and c0 in OP2SAME) or (c0 == 45 and c1 == 62)
  return (3 if (c2 == EQ and c0 in OP3) else 2) if two else 1


def is_digit(c): return 48 <= c <= 57
def is_name0(c): return (65 <= c <= 90) or (97 <= c <= 122) or c == 95 or c >= 128
def is_name(c): return is_digit(c) or is_name0(c)


def ds(bs, i, cls):
  """[0-9](?:_?[0-9])* over digit class cls. bs[i] must already be in cls."""
  n = 0
  while True:
    if i + n + 1 < len(bs) and bs[i + n] == 95 and bs[i + n + 1] in cls: n += 2
    elif i + n < len(bs) and bs[i + n] in cls: n += 1
    else: return i + n


def exponent(bs, i):
  if i < len(bs) and bs[i] in ESUF:
    j = i + 1
    if j < len(bs) and bs[j] in SGN: j += 1
    if j < len(bs) and is_digit(bs[j]): return ds(bs, j, DEC)
  return 0


def number(bs, i):
  """The end of the Number regex at i; the caller has checked one can start here."""
  c0 = bs[i]
  if c0 == DOT:
    j = ds(bs, i + 1, DEC)
  elif c0 == 48 and i + 2 < len(bs):
    k = bs[i + 1]
    if k in (120, 88) and bs[i + 2] in HEX: return ds(bs, i + 2, HEX)
    elif k in (98, 66) and bs[i + 2] in BIN: return ds(bs, i + 2, BIN)
    elif k in (111, 79) and bs[i + 2] in OCT: return ds(bs, i + 2, OCT)
    j = ds(bs, i, DEC)
  else:
    j = ds(bs, i, DEC)
  if c0 != DOT and j < len(bs) and bs[j] == DOT:
    j = ds(bs, j + 1, DEC) if (j + 1 < len(bs) and is_digit(bs[j + 1])) else j + 1
  e = exponent(bs, j)
  if e: j = e
  return j + 1 if (j < len(bs) and bs[j] in JSUF) else j


def prefix(bs, i):
  """(end, is_f) of the string prefix at i, or None. The prefix is followed by a quote."""
  if bs[i] in QUOTES: return i, False
  if i + 1 < len(bs) and bs[i + 1] in QUOTES:
    a = chr(bs[i]).lower()
    if a in PFX1: return i + 1, a == 'f'
  if i + 2 < len(bs) and bs[i + 2] in QUOTES:
    a, b = chr(bs[i]).lower(), chr(bs[i + 1]).lower()
    if a + b in PFX2: return i + 2, 'f' in (a, b)
  return None


def quote3(bs, j):
  """(end of the opening quotes, is_triple) for the quote that starts at j."""
  q = bs[j]
  if j + 2 < len(bs) and bs[j + 1] == q and bs[j + 2] == q: return j + 3, 1
  return j + 1, 0


def strbody(bs, i, q, tri, what):
  """The end of a plain string body, plus its newline count. Raises on EOF."""
  n, m = 0, len(bs)
  while True:
    if i >= m: raise Err(what)
    c = bs[i]
    if c == BS:
      if i + 1 >= m: raise Err(what)
      n += 1 if bs[i + 1] == NL else 0
      i += 2
    elif c == NL:
      if not tri: raise Err(what)
      n += 1
      i += 1
    elif c == CR and i + 1 < m and bs[i + 1] == NL:
      if not tri: raise Err(what)
      n += 1
      i += 2
    elif c == q:
      if not tri: return i + 1, n
      if i + 2 < m and bs[i + 1] == q and bs[i + 2] == q: return i + 3, n
      i += 1
    else:
      i += 1


def bumpm(acc, fromline, endline):
  """One counted token, from line `fromline` to line `endline`."""
  i, tok, lines, last, line, blank = acc
  lo = fromline if fromline > last else last + 1
  if endline >= lo: return (i, tok + 1, lines + endline - lo + 1, endline, line, blank)
  return (i, tok + 1, lines, last, line, blank)


def bump(acc): return bumpm(acc, acc[4], acc[4])


def lit(bs, st, acc):
  """Inside an f-string literal or format spec. st = ('L', q, back, close, tri)."""
  i, n = acc[0], len(bs)
  mode, depth, q, back, close, tri = st
  c = bs[i]
  if c == LBRACE:
    if not close and i + 1 < n and bs[i + 1] == LBRACE: return st, (i + 2, *acc[1:])
    return ('C', 0, 0, st, 0, 0), bump((i + 1, *acc[1:]))
  if c == RBRACE:
    if not close and i + 1 < n and bs[i + 1] == RBRACE: return st, (i + 2, *acc[1:])
    if close: return back, bump((i + 1, *acc[1:]))
    raise Err("f-string: single '}' is not allowed")
  if c == q:
    if tri and (i + 2 >= n or bs[i + 1] != q or bs[i + 2] != q): return st, (i + 1, *acc[1:])
    if not tri: return back, (i + 1, *acc[1:])
    return back, (i + 3, *acc[1:])
  if c == BS:
    if i + 1 < n and bs[i + 1] == q: return st, (i + 2, *acc[1:])
    if i + 1 < n and bs[i + 1] == NL: return st, (i + 2, acc[1], acc[2], acc[3], acc[4] + 1, True)
    if i + 2 < n and bs[i + 1] == CR and bs[i + 2] == NL:
      return st, (i + 3, acc[1], acc[2], acc[3], acc[4] + 1, True)
    return st, (i + 1, *acc[1:])
  if c == NL:
    if not tri: raise Err(UNTERM_F)
    return st, (i + 1, acc[1], acc[2], acc[3], acc[4] + 1, True)
  if c == CR and i + 1 < n and bs[i + 1] == NL:
    if not tri: raise Err(UNTERM_F)
    return st, (i + 2, acc[1], acc[2], acc[3], acc[4] + 1, True)
  return st, (i + 1, *acc[1:])


def lex(bs, st, acc):
  n = len(bs)
  while True:
    if st[0] == 'L':
      if acc[0] >= n: raise Err(UNTERM_F)
      st, acc = lit(bs, st, acc)
      continue
    i = acc[0]
    if i >= n: return acc[1], acc[2]
    c = bs[i]
    if c == 32 or c == 9 or c == 12: acc = (i + 1, *acc[1:])
    elif c == NL: acc = (i + 1, acc[1], acc[2], acc[3], acc[4] + 1, True)
    elif c == CR and i + 1 < n and bs[i + 1] == NL:
      acc = (i + 2, acc[1], acc[2], acc[3], acc[4] + 1, True)
    elif c == HASH:
      while i < n and bs[i] not in (NL, CR): i += 1
      acc = (i, acc[1], acc[2], acc[3], acc[4], False)
    elif c == BS:
      if i + 1 < n and bs[i + 1] == NL: acc = (i + 2, acc[1], acc[2], acc[3], acc[4] + 1, True)
      elif i + 2 < n and bs[i + 1] == CR and bs[i + 2] == NL:
        acc = (i + 3, acc[1], acc[2], acc[3], acc[4] + 1, True)
      elif i + 1 < n: raise Err("unexpected character after line continuation character")
      else: raise Err("unexpected EOF in multi-line statement")
    else:
      p = prefix(bs, i)
      if p is not None:
        j, isf = p
        start, tri = quote3(bs, j)
        q = bs[j]
        if isf:
          # an f-string's body is not a plain string: the '{' fields inside it
          # are tokens, so only the opening quote is consumed here
          acc = (start, *acc[1:])
          st = ('L', 0, q, st, 0, tri)
          continue
        e, nl = strbody(bs, start, q, tri, UNTERM_T if tri else UNTERM_S)
        blank, fromline = acc[5], acc[4]
        acc = (e, acc[1], acc[2], acc[3], fromline + nl, blank)
        if not is_docstring(tri and j == i and q == 34, blank): acc = bumpm(acc, fromline, acc[4])
        continue
      if is_digit(c) or (c == DOT and i + 1 < n and is_digit(bs[i + 1])):
        e = number(bs, i)
        acc = (e, acc[1], acc[2], acc[3], acc[4], False)
        acc = bump(acc)
      elif is_name0(c):
        j = i
        while j < n and is_name(bs[j]): j += 1
        acc = (j, acc[1], acc[2], acc[3], acc[4], False)
        acc = bump(acc)
      else:
        e = i + op_len(c, bs[i + 1] if i + 1 < n else 0, bs[i + 2] if i + 2 < n else 0)
        acc = (e, acc[1], acc[2], acc[3], acc[4], False)
        # bracket depth: a ':' only opens a format spec at the field's top level,
        # and a '}' only closes the field there
        if st[0] == 'C':
          if c == 40 or c == 91 or c == 123: st = ('C', st[1] + 1, *st[2:])
          elif c == 41 or c == 93: st = ('C', st[1] - 1, *st[2:])
          elif c == 125 and st[1] == 0: st = st[3]
          elif c == 125: st = ('C', st[1] - 1, *st[2:])
          elif c == 58 and st[1] == 0: st = ('L', 0, st[3][2], st[3], 1, st[3][5])
        acc = bump(acc)


def is_docstring(q3, blank): return q3 and blank


def is_docstring_py(t):
  return t.type == token.STRING and t.string.startswith('"""') and t.line.strip().startswith('"""')


def py_stats(bs):
  src = bs.decode('utf-8', 'replace')
  toks = [t for t in tokenize.generate_tokens(iter(src.splitlines(True)).__next__)
          if t.type in (token.OP, token.NAME, token.NUMBER, token.STRING) and not is_docstring_py(t)]
  return len(toks), len(set([x for t in toks for x in range(t.start[0], t.end[0] + 1)]))


def bend_stats(bs): return lex(list(bs), ('T', 0, 0, None, 0, 0), (0, 0, 0, 0, 1, True))


if __name__ == '__main__':
  bad = n = 0
  for root, _, files in os.walk(sys.argv[1] if len(sys.argv) > 1 else 'tinygrad'):
    for f in sorted(files):
      if not f.endswith('.py'): continue
      p = os.path.join(root, f)
      src = open(p, 'rb').read()
      try: a = py_stats(src)
      except Exception as e: a = ('ERR', str(e)[:44])
      try: b = bend_stats(src)
      except Exception as e: b = ('ERR', str(e)[:44])
      n += 1
      if a != b:
        bad += 1
        if bad < 12: print("MISMATCH", p, "py", a, "bend", b)
  print("files", n, "mismatches", bad)
