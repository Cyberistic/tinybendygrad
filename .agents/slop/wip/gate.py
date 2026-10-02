"""Row-keyed diff of the cstyle gate against LIVE CPython.

    python3 .agents/slop/wip/gate.py [port.bend] [oracle.py]

THREE LANES, and the third one is the only authority:

  1. INTERPRETED  `bin/bend <port>`                -- the port's own print
  2. NATIVE       `bin/bend <port> -o bin && bin`  -- the same program compiled
  3. CPython      `oracle.py` under DEV=NULL       -- THE AUTHORITY

WHAT THIS FILE USED TO CLAIM, because a gate that lies is worse than no gate: it
compared the port's `[bend]` half against the `py=` literal INSIDE the port and
printed "GREEN n / m rows match CPython byte for byte" without ever starting
CPython. That is `device.bend`'s `sig=0 4 5` defect with better branding -- the
expectation was the thing under test, so 104 of 227 rows could disagree while the
summary line said they matched. The baked literal is still compared below, and it
is labelled a PORT ARTEFACT. It is never called CPython again.

THE THREE PROPERTIES THIS FILE IS BUILT TO HAVE:

  * it NAMES ITS AUTHORITY on every summary line;
  * it COUNTS ROWS FROM BOTH SIDES and prints both, because "0 disagreed" over
    "0 compared" is the most expensive lie a gate can tell;
  * 0 ROWS COMPARED IS A FAILURE -- if the oracle dies, prints nothing, or matches
    no row name, this exits 1 having said which of the three happened.

Row names are matched with internal whitespace collapsed: the port pads its labels
(`tmap CLANG `) and the oracle does not, and an exact match would report 185
unmatched rows for a spelling difference. Rows that still have no counterpart are
printed by name as UNREFUTABLE, never counted green.
"""

import os, re, subprocess, sys, tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
HERE = os.path.dirname(os.path.abspath(__file__))
BEND = os.path.join(ROOT, "bin", "bend")
SRC = os.path.join(ROOT, "tinybendygrad/renderer/cstyle.bend")
ORACLE = os.path.join(HERE, "cstyle_oracle.py")
# A COMPILED ARTEFACT, not an oracle, so it belongs in the temp cache: the ORACLE
# must live beside the port tree because its relative imports resolve there.
BIN = os.path.join(tempfile.gettempdir(), "cstyle-gate", "native.bin")

PORT_ROW = re.compile(r"^(?P<nm>.*?) = \[(?P<bend>.*)\]   py=\[(?P<py>.*)\]$")
ORACLE_ROW = re.compile(r"^(?P<nm>.*?) = \[(?P<cp>.*)\]$")


def die(msg, *detail):
  print(msg)
  for d in detail:
    print(d)
  sys.exit(1)


def parse(text, rx, groups, tag):
  """name -> the named groups. Returns the unreadable lines too: a gate that
  silently drops a row it cannot parse is a gate reporting a smaller run."""
  rows, bad = {}, []
  for line in text.split("\n"):
    if not line.strip():
      continue
    m = rx.match(line)
    if m is None:
      bad.append((tag, line))
    elif " ".join(m.group("nm").split()) in rows:
      bad.append((tag, "DUPLICATE ROW NAME: " + m.group("nm")))
    else:
      rows[" ".join(m.group("nm").split())] = tuple(m.group(g) for g in groups)
  return rows, bad


def main():
  src = os.path.join(ROOT, sys.argv[1]) if len(sys.argv) > 1 else SRC
  oracle = os.path.join(ROOT, sys.argv[2]) if len(sys.argv) > 2 else ORACLE

  # lane 1 -- interpreted
  a = subprocess.run([BEND, src], cwd=ROOT, capture_output=True, text=True)
  if a.returncode != 0:
    die("INTERPRETED LANE DID NOT RUN rc %d" % a.returncode, a.stdout[-1500:], a.stderr[-1500:])
  port, bad = parse(a.stdout, PORT_ROW, ("bend", "py"), "interpreted")

  # lane 2 -- native. `-o -` writes ZERO bytes on Bend 2.0.34 (the backend is
  # chosen by extension), so the binary is named and its size is checked.
  os.makedirs(os.path.dirname(BIN), exist_ok=True)
  build = subprocess.run([BEND, src, "-o", BIN], cwd=ROOT, capture_output=True, text=True)
  if build.returncode != 0 or not os.path.exists(BIN) or os.path.getsize(BIN) == 0:
    die("NATIVE LANE DID NOT RUN: build rc %d, %d bytes at %s"
        % (build.returncode, os.path.getsize(BIN) if os.path.exists(BIN) else 0, BIN),
        build.stderr[-1500:])
  b = subprocess.run([BIN], cwd=ROOT, capture_output=True, text=True)
  if b.returncode != 0:
    die("NATIVE LANE DID NOT RUN rc %d" % b.returncode, b.stderr[-1500:])
  native, nbad = parse(b.stdout, PORT_ROW, ("bend", "py"), "native")

  # lane 3 -- the authority. Exit status IS consulted here, unlike --check-only.
  print("AUTHORITY: %s -- live CPython, DEV=NULL, exit status consulted"
          % os.path.relpath(oracle, ROOT))
  o = subprocess.run([sys.executable, oracle], cwd=ROOT, capture_output=True, text=True,
                     env=dict(os.environ, DEV="NULL"))
  if o.returncode != 0:
    die("ORACLE DID NOT RUN rc %d" % o.returncode, o.stderr[-1500:])
  cpy, obad = parse(o.stdout, ORACLE_ROW, ("cp",), "cpython")
  if not cpy:
    die("ORACLE DID NOT RUN: %s printed 0 rows" % os.path.relpath(oracle, ROOT))

  for tag, line in bad + nbad + obad:
    print("UNPARSED %s: %r" % (tag, line))

  both = sorted(set(port) & set(cpy))
  only_port, only_cpy = sorted(set(port) - set(cpy)), sorted(set(cpy) - set(port))
  print("\nROWS COUNTED, EACH SIDE SEPARATELY (names whitespace-collapsed)")
  print("  interpreted port rows        : %d" % len(port))
  print("  native port rows             : %d" % len(native))
  print("  CPython oracle rows          : %d" % len(cpy))
  print("  COMPARED port<->CPython      : %d" % len(both))
  print("  port rows with no oracle row : %d  (UNREFUTABLE, not green)" % len(only_port))
  print("  oracle rows with no port row : %d" % len(only_cpy))
  if not both:
    die("\nFAIL: 0 ROWS COMPARED -- the oracle ran and matched no row name.")
  if set(port) != set(native):
    print("\nINTERPRETED vs NATIVE name sets differ by %d" % len(set(port) ^ set(native)))
  red = [n for n in both if port[n][0] != cpy[n][0]]
  print("\nVERDICT vs CPython: %d compared, %d DISAGREE, %d agree"
        % (len(both), len(red), len(both) - len(red)))
  for n in red:
    print("  RED %s\n    bend   : [%s]\n    cpython : [%s]" % (n, port[n][0], cpy[n][0]))
  for n in only_cpy:
    print("  ORACLE-ONLY %s cpython=[%s] bend=ABSENT" % (n, cpy[n][0]))

  # The port's own baked `py=` literal: a PORT ARTEFACT, never an authority.
  lit = [n for n in port if port[n][0] != port[n][1]]
  with_bend = [n for n in lit if n in cpy and cpy[n][0] == port[n][0]]
  with_py = [n for n in lit if n in cpy and cpy[n][0] == port[n][1]]
  print("\nPORT-BAKED `py=` LITERAL -- an artefact OF the port, NOT an authority:")
  print("  %d of %d baked literals disagree with the port's own [bend] half."
        % (len(lit), len(port)))
  print("  live CPython sides WITH the port  : %d  -> the baked literal is wrong text" % len(with_bend))
  print("  live CPython sides with baked py  : %d  -> THE PORT IS WRONG" % len(with_py))
  print("  no CPython row to adjudicate      : %d  -> unfalsifiable either way"
        % len([n for n in lit if n not in cpy]))
  for n in with_py:
    print("    PORT DISAGREES WITH CPYTHON %s bend=[%s] baked=[%s] cpython=[%s]"
          % (n, port[n][0], port[n][1], cpy[n][0]))
  for n in sorted(set(port) - set(cpy)):
    print("  UNREFUTABLE (no oracle row) %s" % n)

  problems = len(bad) + len(nbad) + len(obad) + len(red) + len(with_py) + len(with_bend) \
      + len(set(port) ^ set(native))
  print("\nPROBLEMS: %d  (each unrefutable baked literal counts: a wrong expectation"
        " left in the port is a defect even where no oracle row can prove it)" % problems)
  return 1 if problems else 0


if __name__ == "__main__":
  sys.exit(main())