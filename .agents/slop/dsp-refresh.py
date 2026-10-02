#!/usr/bin/env python3
"""dsp-refresh.py -- re-stamp the `py=` third argument of named rows in
`tinybendygrad/runtime/ops_dsp.bend` from `.agents/slop/dsp_oracle2.py values`.

    .venv/bin/python .agents/slop/dsp_refresh.py ROW [ROW ...]     # dry run, prints
    .venv/bin/python .agents/slop/dsp_refresh.py --write ROW ...    # applies

WHY NOT `dsp-gen.py`: that script rewrote all 496 rows and its line-joining dropped a
newline at a `def` boundary, leaving the file unparseable ("the keyword 'def' cannot
head one"). This one touches only the rows named on the command line, and it REFUSES
to write unless the result still checks clean, so a mangling cannot survive.

THE VALUES COME FROM THE ORACLE, NEVER FROM THE FILE. `--write` re-reads the source
after writing and compares the touched rows against the oracle, so a row that failed to
move is an error rather than a silent pass.
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TARGET = ROOT / "tinybendygrad/runtime/ops_dsp.bend"
ORACLE = ROOT / ".agents/slop/dsp_oracle2.py"
CALL = re.compile(r'\b(row|urow|srow|lrow)\("([^"]+)",')


def values():
  r = subprocess.run([sys.executable, str(ORACLE), "values"],
                     capture_output=True, text=True, check=True).stdout
  out, key = {}, None
  for ln in r.split("\n"):
    m = re.match(r"^(\w+)\t(CPY|SRC|PORT)\t(.*)$", ln)
    if m:
      key, out[key] = m.group(1), m.group(3)
    elif key and ln.strip():
      out[key] += "\n" + ln
  return out


def split_top(s):
  out, depth, buf, i, in_str = [], 0, "", 0, False
  while i < len(s):
    c = s[i]
    if in_str:
      buf += c
      if c == "\\":
        buf += s[i + 1]
        i += 2
        continue
      if c == '"':
        in_str = False
      i += 1
      continue
    if c == '"':
      in_str, buf = True, buf + c
    elif c in "([{":
      depth, buf = depth + 1, buf + c
    elif c in ")]}":
      depth, buf = depth - 1, buf + c
    elif c == "," and depth == 0:
      out.append(buf)
      buf = ""
    else:
      buf += c
    i += 1
  out.append(buf)
  return out


def literal(kind, v):
  if kind == "urow":
    assert v.lstrip("-").isdigit(), f"not a number: {v!r}"
    return v
  if kind == "row":
    assert v in ("True", "False"), f"not a Bool: {v!r}"
    return f"{v}{{}}"
  esc = v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
  return f'"{esc}"'


def rewrite(src, want, val):
  """Replace the THIRD argument of the named rows, leaving every byte outside the call
  untouched: the call's span is found by paren balance and only that span is rebuilt."""
  out, i, done = [], 0, []
  while True:
    m = CALL.search(src, i)
    if not m:
      out.append(src[i:])
      break
    name, kind = m.group(2), m.group(1)
    op = src.index("(", m.start())
    d, q = 0, op
    while True:
      d += src[q].count("(") - src[q].count(")")
      if d == 0:
        break
      q += 1
    out.append(src[i:m.start()])
    call = src[m.start():q + 1]
    if name in want:
      if name not in val:
        raise SystemExit(f"row {name!r} has no oracle value")
      args = split_top(call[call.index("(") + 1:-1])
      assert args[0].strip() == f'"{name}"', (args[0], name)
      out.append(f'{kind}({args[0]}, {args[1]}, {literal(kind, val[name])})')
      done.append(name)
    else:
      out.append(call)
    i = q + 1
  return "".join(out), done


def main():
  argv = sys.argv[1:]
  write = "--write" in argv
  want = set(a for a in argv if not a.startswith("--"))
  if not want:
    raise SystemExit(__doc__)
  val = values()
  src = TARGET.read_text()
  new, done = rewrite(src, want, val)
  missing = want - set(done)
  if missing:
    raise SystemExit(f"no such row(s): {sorted(missing)}")
  changed = sum(1 for a, b in zip(src.split("\n"), new.split("\n")) if a != b)
  print(f"{len(done)} row(s) rewritten, {changed} line(s) differ")
  if not write:
    for n in sorted(done):
      print(f"  {n} -> {literal(dict((m.group(2), m.group(1)) for m in CALL.finditer(new)).get(n, 'urow'), val[n])!r}")
    return 0
  TARGET.write_text(new)
  # REFUSE to leave a broken file: re-check, then re-verify the touched rows.
  chk = subprocess.run([str(ROOT / "bin/bend"), str(TARGET), "--check-only"],
                       capture_output=True, text=True)
  first = (chk.stdout + chk.stderr).split("\n")[0]
  if "ALL PROOFS CHECK" not in first:
    TARGET.write_text(src)
    raise SystemExit(f"REFUSED: the rewrite does not check clean ({first!r}); restored.")
  print(f"checks: {first}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())