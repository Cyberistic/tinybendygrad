#!/usr/bin/env python3
"""dsp-gen.py -- inject the CPython `py=` half into every row of
`tinybendygrad/runtime/ops_dsp.bend` and drop the `# py=` comment.

THE GATE WAS NOT A GATE. All 496 rows carried their expectation in a trailing `# py=`
comment on the row that produced it, so nothing was compared and
`.agents/slop/dsp_gate_check.py` says so on every run. This script moves the expectation
INTO the row, as a third argument to `row`/`urow`/`srow`/`lrow`, which print

    <name> = [<the port's answer>]   py=[<CPython's answer>]

so the whole lane is a `diff` against `.agents/slop/dsp_oracle2.py rows`.

    .venv/bin/python .agents/slop/dsp-gen.py

THE VALUES COME FROM `dsp_oracle2.py`, NEVER FROM THE COMMENT. The comment is deleted
rather than kept: a comment that agrees with the row is precisely what made this file's
512 rows vacuous.
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
  """name -> printed value, straight from the oracle. `values` mode is
  `name<TAB>provenance<TAB>value`, and ONE value is multi-line (`dsp_link_script`), so a
  line that does not start with a `name<TAB>PROV<TAB>` header is a continuation."""
  r = subprocess.run([sys.executable, str(ORACLE), "values"],
                     capture_output=True, text=True, check=True).stdout
  out, key = {}, None
  for ln in r.split("\n"):
    m = re.match(r"^(\w+)\t(CPY|SRC|PORT)\t(.*)$", ln)
    if m:
      key = m.group(1)
      out[key] = m.group(3)
    elif key and ln.strip():
      out[key] += "\n" + ln
  return out


def literal(kind, v):
  """the third argument, in the shape the helper takes. A `urow` expectation is a
  number; a `row` one is a `Bool` LITERAL -- `True{}`/`False{}`, because Bend 2.0.34 has
  no bare `True` term (MEASURED: "expected : a defined name / observed : False"). An
  `srow`/`lrow` one is a Bend string literal, so it is escaped; ONE value is multi-line
  (`dsp_link_script`) and Bend DOES read `\\n` inside a string literal."""
  if kind == "urow":
    assert v.lstrip("-").isdigit(), f"not a number: {v!r}"
    return v
  if kind == "row":
    assert v in ("True", "False"), f"not a Bool: {v!r}"
    return f"{v}{{}}"
  esc = v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
  return f'"{esc}"'


def split_top(s):
  """split a call's argument text on its top-level commas -- a comma inside `(...)`,
  `[...]`, `{...}` or a string literal is not a separator."""
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
      in_str = True
      buf += c
    elif c in "([{":
      depth += 1
      buf += c
    elif c in ")]}":
      depth -= 1
      buf += c
    elif c == "," and depth == 0:
      out.append(buf)
      buf = ""
    else:
      buf += c
    i += 1
  out.append(buf)
  return out


def rewrite(gate, val):
  """IDEMPOTENT: a call is rebuilt from its NAME and its EXPRESSION, so running twice
  cannot append a second literal. The first version appended blindly and turned every
  row into a four-argument call, which is a parse error, not a gate."""
  out, i, n, missing = [], 0, 0, []
  while i < len(gate):
    m = CALL.search(gate, i)
    if not m:
      eol = gate.find("\n", i)
      eol = len(gate) if eol < 0 else eol
      # THROUGH the newline: dropping it merges every non-row line into the next one and
      # the file stops parsing. (It did, once, and the gate's 512 rows became 4.)
      out.append(re.sub(r'[ \t]*#\s*py=.*$', '', gate[i:eol + 1]))
      i = eol + 1
      continue
    name, kind = m.group(2), m.group(1)
    op = gate.index("(", m.start())
    d, q = 0, op
    while True:
      d += gate[q].count("(") - gate[q].count(")")
      if d == 0:
        break
      q += 1
    out.append(gate[i:m.start()])
    call = gate[m.start():q + 1]
    call = re.sub(r'[ \t]*#\s*py=.*$', '', call, flags=re.M)
    args = split_top(call[call.index("(") + 1:-1])
    assert args[0].strip() == f'"{name}"', (args[0], name)
    expr = args[1]
    if name not in val:
      missing.append(name)
      out.append(call)
    else:
      want = literal(kind, val[name])
      out.append(f'{kind}({args[0]}, {expr}, {want})')
      n += 1
    i = q + 1
  # a `# py=` on the line AFTER a multi-line call's close paren
  body = re.sub(r"\n[ \t]*#[ \t]*py=.*", "", "\n".join(out))
  return body, n, missing


def main():
  val = values()
  src = TARGET.read_text()
  lo = src.index("def t_rpcsc()")
  hi = src.index("def main()")
  body, n, missing = rewrite(src[lo:hi], val)
  if missing:
    raise SystemExit(f"{len(missing)} rows have no oracle value: {missing[:8]}")
  new = src[:lo] + body + src[hi:]
  if new == src:
    print(f"clean: {n} rows already compared")
    return 0
  TARGET.write_text(new)
  left = len(re.findall(r'#\s*py=', new))
  print(f"rewrote {n} rows: comment-carried -> compared; {left} `# py=` comments left")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())