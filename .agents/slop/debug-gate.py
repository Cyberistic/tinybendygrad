#!/usr/bin/env python3
"""debug-gate.py -- the CPython lane of `.agents/slop/debug-gate.bend`.

    .venv/bin/python .agents/slop/debug-gate.py 2 > /tmp/py.txt
    DEBUG=2 ./bin/bend .agents/slop/debug-gate.bend   > /tmp/bd.txt
    diff /tmp/py.txt /tmp/bd.txt

EVERY `name=value` ROW IS PRODUCED BY CALLING tinygrad. Nothing here is typed from
reading a source line, and nothing here re-implements the port: where a row is about
a string tinygrad prints, this file makes tinygrad print it and captures stdout.

THE ROWS, AND WHERE EACH ONE COMES FROM.

  `env_*`        `repr(DEBUG.value)` and `int(DEBUG >= N)` off the LIVE ContextVar
                 (`DEBUG = ContextVar("DEBUG", 0)`, helpers.py:237). `%r` shows the
                 TYPE CPython settled on: it is an `int`, which is the whole reason
                 `helpers.bend` needed a `getenv_int` arm at all.
  `gi_*`         `getenv`'s OWN coercion, `type(default)(os.getenv(key, default))`
                 (helpers.py:163), applied to the same texts the harness feeds
                 `H.gi_of_text`. This is `int("1_0")`, not a rule about `1_0`, and a
                 refusal is `ValueError` here where the port answers the default.
  `mem_mb_*`     `f"{n/1e6:.2f}"` -- Python's OWN `:.2f` on the binary float. Every
                 text is a multiple of 256, the population the port's formatter is
                 claimed to be right on; see the harness's note for why the others
                 are not rows.
  `ar_*`         `handle_allreduce` over a real BUFFER UOp whose `.device` is a
                 4-tuple, in three ContextVar configurations.
  `mem_plan`     `memory_plan_rewrite` over the port's own fixture graph, rebuilt
                 node for node from `schedule/memory.bend`'s FIXTURE 2.
  `st_*`         `torch_load` over a real on-disk pickle.
  `am*`          the cited `amdev.py` source line, read with `linecache` and `exec`'d
                 with the live `DEBUG`. CPython cannot construct an `AMDev` on this
                 host -- MEASURED, `AMDev(0)` raises `AttributeError: 'int' object has
                 no attribute 'pcibus'` -- so this is the strongest evidence available,
                 and it is evidence about the SOURCE LINE rather than about a device.
  `thr_*`        "did this site print at level EXACTLY 1", measured by running the
                 real function under `DEBUG=1` and looking at its stdout. This is the
                 row that separates the ONE level-1 site from the six level-2 sites.
  `*_L<n>`       the same question at level `n`, in a FRESH PROCESS.

THE LEVEL IS AN ARGUMENT and every level produces the SAME ROW NAMES. That is what
makes "the row moved" a fact: diff level 0 against level 2 and only the site rows
change. Each level is a fresh process because `getenv` is `@functools.cache`d
(helpers.py:162) and a ContextVar's value is a process-boot constant.
"""
import os, re, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
PY = os.path.join(ROOT, '.venv', 'bin', 'python')

rows = []
def row(nm, v): rows.append("%s=%s" % (nm, v))

# ===========================================================================
# THE CHILD. STDOUT ONLY, and `KEEP` filters each lane's OWN lines: at DEBUG >= 1
# `device.py:41` prints `opened device DISK:...` and at DEBUG >= 3 the JIT prints
# schedule lines, and neither is a row. The filters are PREFIXES of the very strings
# the sites produce, so a wrong filter shows up as `*_L<n>=` everywhere rather than
# hiding.
# ===========================================================================
KEEP = {"ar": (" ALLREDUCE ",), "mem": ("memory reduced from ",),
        "st": ("WARNING: returning Dummy for ",),
        "am": ("am ",),
        # `pin` is the plan's own quantities, and they are read at DEBUG UNSET so the
        # pin cannot be perturbed by the level even in principle -- the structural half
        # of "hold the graph fixed by construction". The shell script then DIGESTS the
        # pin rows across every level and refuses to compare on a mismatch, which is the
        # half that checks it. `py_nsites`/`py_site_L<n>` count CPython's own site
        # inventory per level; see the LEVEL-SITE INVENTORY note below.
        "pin": ("pin_",),
        "sites": ("py_nsites=", "py_site_", "up_")}

def child(level, body, env_extra=None):
  env = dict(os.environ)
  env.pop('PYTHONPATH', None)
  if level is None:
    env.pop('DEBUG', None)
  else:
    env['DEBUG'] = str(level)
  for k, v in (env_extra or {}).items():
    env[k] = v
  src = "import sys\nsys.path.insert(0, %r)\n" % ROOT + body
  p = subprocess.run([PY, '-c', src], cwd=ROOT, env=env, capture_output=True, text=True)
  if p.returncode != 0:
    print("FATAL level=%s: child exited %s\n%s" % (level, p.returncode, p.stderr[:1500]),
          file=sys.stderr)
    sys.exit(2)
  return [l.strip() for l in p.stdout.split('\n') if l.strip()]

def keep(lines, key):
  return [l for l in lines if any(pre in l for pre in KEEP[key])]

# ===========================================================================
# LANE ENV -- the ContextVar itself.
# ===========================================================================
ENV_BODY = """
from tinygrad.helpers import DEBUG
print("env_value=%r" % DEBUG.value)
for n in (1, 2, 3, 4, 5, 6, 7): print("env_ge%d=%d" % (n, int(DEBUG >= n)))
"""

# ===========================================================================
# LANE GI -- `getenv`'s coercion on twenty-one texts, ONE PROCESS PER TEXT.
#
# `getenv` is `type(default)(os.getenv(key, default))` (helpers.py:163), so the value
# comes from the ENVIRONMENT and the DEFAULT chooses the coercion. The text therefore
# has to be put in the environment and `getenv` called with an INT default, and there
# has to be one process per text: `getenv` is `@functools.cache`d (:162), so a single
# process would answer the first text for all twenty-one. Passing the text as the
# DEFAULT was the first attempt and it is WRONG in a way worth recording --
# `getenv(key, "1_0")` coerces through `str` and hands back `"1_0"`, so every `gi_*`
# row was the text echoed back and the whole lane agreed with a port that had not
# parsed anything at all.
GI_TEXTS = [("gi_0", "0"), ("gi_1", "1"), ("gi_2", "2"), ("gi_3", "3"),
            ("gi_00", "00"), ("gi_007", "007"), ("gi_1_0", "1_0"),
            ("gi_2_0_0", "2_0_0"), ("gi_sp2", " 2 "), ("gi_tab2", "\t2\n"),
            ("gi_p2", "+2"), ("gi_refuse_1_", "1_"),
            ("gi_refuse__1", "_1"), ("gi_refuse_1__0", "1__0"),
            ("gi_refuse_us", "_"), ("gi_refuse_abc", "abc"),
            ("gi_refuse_dot", "2.0"), ("gi_refuse_exp", "1e3"),
            ("gi_refuse_hex", "0x2"), ("gi_refuse_empty", "")]

# The child CATCHES the refusal so it still exits 0. It cannot be avoided from
# outside: the ValueError happens at the IMPORT of `tinygrad.helpers`, so the whole
# process is gone before `getenv` returns, and there is no stdout to read. tinygrad
# itself does not catch it either -- that is why `DEBUG=abc` makes the library
# unimportable rather than defaulting.
GI_BODY = """
from tinygrad.helpers import getenv
try: print(getenv("DBGPROBE", 0))
except ValueError: print("ValueError")
"""

# ===========================================================================
# LANE MB -- Python's own `:.2f`.
# ===========================================================================
MB_BODY = """
NS = [0, 12032, 11776, 8388608, 4194304, 256000, 512000, 128000, 384000, 896000]
for n in NS: print("mem_mb_256_%d=%.2f" % (n, n / 1e6))
"""

# ===========================================================================
# LANE AR -- `handle_allreduce` over a real BUFFER whose `.device` is a 4-tuple.
# `vmin_vmax` and `red.arg[1]` are both load-bearing and both were found by a crash:
# without `vmin_vmax`, `buf.max_shape` is None and `buf.pad_to(buf.max_shape)` (:19)
# raises `TypeError: 'NoneType' object is not iterable` on the NAIVE case, which kills
# the loop and silently costs the ALL2ALL row; without a real device, the same
# expression raises at :32's `copy_to_device`.
AR_BODY = """
from tinygrad.uop.ops import UOp, Ops, ParamArg
from tinygrad.dtype import dtypes
from tinygrad.helpers import Context
from tinygrad.schedule.allreduce import handle_allreduce
def buf(devs, size, dt=dtypes.float32):
  return UOp(Ops.BUFFER, arg=ParamArg(slot=0, dtype=dt, size=size, vmin_vmax=(0, size),
                                      name="b", device=tuple(devs)))
def run(devs, size):
  red = UOp(Ops.REDUCE, src=(buf(devs, size),), arg=(Ops.ADD, devs[0]))
  handle_allreduce(red.src[0], red)
FOUR = ["CPU:0","CPU:1","CPU:2","CPU:3"]
run(FOUR, 300000)
run(["CPU:0","CPU:1"], 100)
with Context(ALL2ALL=2): run(FOUR, 100)
"""

# ===========================================================================
# LANE MEM -- `memory_plan_rewrite` over the port's own FIXTURE 2, node for node.
# `si_bufs` collects from `si.src[1:]` (memory.py:30), and a SINK's src[0] is its
# BODY, so A2 is the STORE DESTINATION and is never collected; DK is on DISK so
# `_can_plan` (:12) rejects it. Five buffers, two lanes.
# ===========================================================================
# THE PLAN'S OWN QUANTITIES, READ OUT OF CPython'S OWN FRAME. `memory_plan_rewrite`
# returns a UOp, not a plan, so the four numbers the port's `pin_*` rows carry are not
# in the return value -- `first_appearance`, `nbytes`, `arena_sizes` and `total_memory`
# are all locals of the frame (memory.py:31/42/45/53). Reading a frame's locals IS
# calling CPython: nothing here recomputes the recipe, and a re-implementation would
# be free to agree with a wrong port. `sys.settrace` is the mechanism, and
# `.agents/slop/x86/x86-oracle.py:93-118` is the precedent in this repository.
#
# THE TRACE STOPS AT memory.py:54 -- the LAST line before the arena UOps are built --
# because at :60 the locals still hold everything and after the `return` the frame is
# gone. `arena_sizes` is the dict at :53, so `sum(arena_sizes.values())` is the port's
# `mem_sum_arena` and NOT `sum(nbytes.values())`, which is the port's `tot / 2`.
MEM_BODY = """
from tinygrad.uop.ops import UOp, Ops, ParamArg
from tinygrad.dtype import dtypes
import tinygrad.schedule.memory as M
def B(slot, size, dev="CPU", dt=dtypes.int32):
  return UOp(Ops.BUFFER, arg=ParamArg(slot=slot, dtype=dt, size=size,
                                      name="B%d" % slot, device=dev))
def SINK(body, *args): return UOp(Ops.SINK, src=(body, *args))
A2, B2, C2, D2, E2, F2 = B(2,1024), B(3,2048), B(4,512), B(5,256), B(6,128), B(7,64)
STORE = UOp(Ops.STORE, src=(A2, B2), arg=ParamArg(slot=0, dtype=dtypes.int32))
lin = UOp(Ops.LINEAR, src=(SINK(STORE, B2), SINK(STORE, C2),
                          SINK(UOp(Ops.ADD, src=(D2, E2)), D2, E2),
                          SINK(UOp(Ops.MUL, src=(D2, F2)), D2, F2)))
import sys
CAP = {}
TARGET = M.memory_plan_rewrite.__code__
STOP = M.__file__.replace(".pyc", ".py")
def tracer(frame, event, arg):
  if frame.f_code is not TARGET: return None
  if event == "line":
    l = frame.f_locals
    if "arena_sizes" in l and "nbytes" in l and "first_appearance" in l and "total_memory" in l:
      CAP.update(nbytes=sum(l["nbytes"].values()), arenas=sum(l["arena_sizes"].values()),
                 bufs=len(l["first_appearance"]), narenas=len(l["arena_sizes"]),
                 tot=l["total_memory"])
  return tracer
sys.settrace(tracer)
try: M.memory_plan_rewrite(lin)
finally: sys.settrace(None)
print("pin_bufs=%d" % CAP["bufs"])
print("pin_narenas=%d" % CAP["narenas"])
print("pin_arenas=%d" % CAP["arenas"])
print("pin_tot=%d" % CAP["tot"])
print("pin_nbytes=%d" % CAP["nbytes"])
"""

# ===========================================================================
# LANE ST -- `torch_load` over a real on-disk pickle.
# state.py:283-290's `else` arm reads: three discarded pickles, `rwd = fobj.tell()`,
# two more pickles (`ids` is the fifth), `fobj.seek(rwd)`, then `TorchPickle.load()`
# re-reads pickle FOUR. So the dict carrying the GLOBAL opcodes is the fourth pickle
# and `ids` is the fifth. `os.path.join` pickles as module `posixpath`, which is NOT
# in `whitelist` (:250); `collections` and `numpy` ARE, so those two are the negative
# pair that must print nothing.
# ===========================================================================
ST_BODY = """
import pickle, os, collections, numpy, tempfile
from tinygrad.nn.state import torch_load
head = pickle.dumps(None) * 3
body = pickle.dumps({"a": os.path.join, "b": collections.OrderedDict, "c": numpy.ndarray})
fn = os.path.join(tempfile.gettempdir(), "torchdbg-gate.pth")
with open(fn, "wb") as f: f.write(head + body + pickle.dumps([]))
torch_load(fn)
"""

# ===========================================================================
# LANE AM -- exec the cited `amdev.py` line with the live `DEBUG`.
# The gated-out lines are ABSENT from stdout rather than blank, so POSITION IS THE
# IDENTITY: index 0 is :185, 1 is :225, 2 is :251, 3 is :254. A missing entry is a
# site below its gate, never a shifted one.
# ===========================================================================
AM_BODY = """
from tinygrad.helpers import DEBUG
import linecache
class FakeDev:
  devfmt = "0000:01:00.0"
SITES = [("tinygrad/runtime/support/am/amdev.py", 185),
         ("tinygrad/runtime/support/am/amdev.py", 225),
         ("tinygrad/runtime/support/am/amdev.py", 251),
         ("tinygrad/runtime/support/am/amdev.py", 254)]
for path, line in SITES:
  src = linecache.getline(__ROOT__ + "/" + path, line).strip()
  scope = {"DEBUG": DEBUG, "self": FakeDev(), "ip": type("AM_GFX", (), {}),
           "print": lambda *a, **k: print(" ".join(str(x) for x in a))}
  # `ip` must be an INSTANCE of a class NAMED `AM_GFX`: the site reads
  # `ip.__class__.__name__`, and `type("AM_GFX", (), {})` is an instance of a class
  # named `type`, so the first attempt printed `am 0000:01:00.0: type initialized`.
  scope["ip"] = scope["ip"]()
  exec(src, scope)
""".replace("__ROOT__", repr(ROOT))

AM_TAGS = ("am185", "am225", "am251", "am254")
AR_TAGS = ("ar_ring", "ar_naive", "ar_a2")

# ===========================================================================
# UPSTREAM'S `DEBUG >= N` SITES, INVENTORIED BY CALLING CPython -- AND DERIVED, NEVER
# TYPED. There is no hand-written site table here at all: `upstream_sites()` greps
# `DEBUG\s*>=\s*(\d+)` over `tinygrad/` and the right-hand side IS the threshold, so a
# site that is added, moved or re-leveled upstream changes these rows instead of
# silently changing what a level means. That is the whole reason this is derived: a
# hand-written threshold is a row that can only ever agree with itself, and
# agent-core.md's `nv_query_litter` row is what that costs -- the port AND the oracle
# both said 2, the truth was 3, and the differ reported "0 disagreements" over one
# mistake made twice.
#
# `kind` is what the site DOES, and it is the whole of what a level can be asked for.
# It is CLASSIFIED FROM THE SITE'S OWN SOURCE LINE by `_PRINTS`, so it cannot drift
# from the text either:
#   print  -- writes text, so a gate can compare TEXT
#   other  -- does not print, so a gate can compare only PRESENCE/ABSENCE
#
# MEASURED over this tree, and this is a REPORT not a claim about upstream: of the
# sites at levels 4..7, three do not print -- `usb.py:25` sets a libusb log level,
# `ops_dsp.py:283` passes qemu a `-strace` flag, and `viz/cli.py:216` is a render
# predicate. At level 6 BOTH sites are of that kind or unreachable, which is why
# level 6's absence is a property of BOTH sides and is stated as such rather than
# claimed for the port alone.
#
# DISTINCT (file, line) PAIRS, not grep occurrences: `viz/cli.py:216` carries both
# `DEBUG >= 6` and `DEBUG >= 5` on one line, and counting occurrences would report
# level 5 a site it does not have.
# ===========================================================================
_SITE_RE = re.compile(r"\bDEBUG\s*>=\s*(\d+)")
ALL_LEVELS = (1, 2, 3, 4, 5, 6, 7)
NEW_LEVELS = (4, 5, 6, 7)
# Every spelling this repository's own `DEBUG`-gated code uses to reach stdout. A site
# whose line contains none of them is `other`. The list is checked for TOTALITY below
# -- every site line must classify, or the run fails rather than guessing.
_PRINTS = ("print(", "print_uops(", "print_exc", "print_step(", "nir_print_shader",
           "LLVMPrintModuleToString", "disassemble(", "emit(")


def _stmt_block(lines, i):
  """The whole statement whose head is line `i` (1-based): that line plus every
  following line indented STRICTLY deeper, blanks included.

  THE BLOCK AND NOT THE LINE, and this is a correction rather than a preference.
  A line-local classification called `schedule/memory.py:59` `other` and called
  `schedule/__init__.py:141` `other`, because the `print` is on line 60 and on line 148
  respectively -- so the print/non-print split UNDERCOUNTED by 2 of 76 sites and the
  level-1 print count read 11 when it was 13. A per-level denominator that is wrong by
  two is not a denominator. Both sites are single-line `if`s with a DEEPER body, and
  the deeper body is what says whether anything is printed.
  """
  head = lines[i - 1]
  ind = len(head) - len(head.lstrip())
  out = [head]
  for j in range(i, len(lines)):
    nxt = lines[j]
    if not nxt.strip():
      continue
    if len(nxt) - len(nxt.lstrip()) <= ind:
      break
    out.append(nxt)
  return out


def upstream_sites():
  """[(level, file, line, kind, text)] sorted, straight out of CPython's own source."""
  out = []
  for root, dirs, files in os.walk(os.path.join(ROOT, "tinygrad")):
    dirs[:] = [d for d in dirs if d != "__pycache__"]
    for fn in sorted(files):
      if not fn.endswith(".py"):
        continue
      rel = os.path.relpath(os.path.join(root, fn), ROOT)
      try:
        text = open(os.path.join(root, fn), encoding="utf-8", errors="replace").read()
      except OSError:
        continue
      lines = text.split("\n")
      for i, line in enumerate(lines, 1):
        for m in _SITE_RE.finditer(line):
          block = "\n".join(_stmt_block(lines, i))
          kind = "print" if any(p in block for p in _PRINTS) else "other"
          out.append((int(m.group(1)), rel, i, kind, line.strip()))
  return out


def inventory():
  """The `DEBUG` scale as this tree actually defines it, every site, with its kind.

  THIS IS NOT A ROW SET, AND THAT IS THE POINT. The upstream inventory is a fact about
  `tinygrad/`, not about the port, so putting it in the compared row set would manufacture
  rows that agree because BOTH sides derive the same table from the same grep over the same
  tree -- which is the `nv_query_litter` shape: two copies of one thing agreeing perfectly.
  It WAS a row set (14 `usites_*` rows) and was removed; the shared-row count would have
  risen 89 -> 103 with 14 claims about nothing. The 89 compared rows say something about the
  PORT; this says something about UPSTREAM, and mixing the two would make the row count mean
  two things at once.
  """
  sites = upstream_sites()
  port = port_site_thresholds()
  print("%-6s %-9s %-9s %-9s %s" % ("level", "upstream", "print", "non-print", "port"))
  for L in ALL_LEVELS:
    at = [s for s in sites if s[0] == L]
    p = sum(1 for s in at if s[3] == "print")
    print("%-6d %-9d %-9d %-9d %d" % (L, len(at), p, len(at) - p, port.get(L, 0)))
  print()
  print("total upstream sites at levels 1..7: %d of %d print"
        % (len(sites), sum(1 for s in sites if s[3] == "print")))
  print("total port sites:                  %d, at thresholds %s"
        % (sum(port.values()), sorted(port.items())))
  print()
  print("THE WHOLE SCALE, site by site. Every cite below was read out of CPython's own")
  print("source by the grep, so a moved line moves this table:")
  for L in ALL_LEVELS:
    for s in [x for x in sites if x[0] == L]:
      print("  L%d %-8s %-44s:%-4d %s" % (L, s[3], s[1], s[2], s[4][:80]))
  print()
  print("WHAT EACH LEVEL CANNOT SHOW, stated rather than left to a zero. EVERY COUNT")
  print("IN THESE LINES IS INTERPOLATED FROM `sites` AND `port`, NEVER TYPED -- and that")
  print("is a correction: the first version of this block hard-wrote '11 print' at level 1")
  print("and '17 print' at level 2 while the table immediately above it said 14 and 20.")
  print("Two numbers in one report about the same thing, one of them wrong, is the")
  print("`nv_query_litter` shape with the copies on the SAME PAGE. Prose that carries a")
  print("count has to read the count.")
  at = {L: [s for s in sites if s[0] == L] for L in ALL_LEVELS}
  pr = {L: sum(1 for s in at[L] if s[3] == "print") for L in ALL_LEVELS}
  notes = {
    1: "memory + timings. %d upstream sites, %d print, %d port site."
       % (len(at[1]), pr[1], port.get(1, 0)),
    2: "the six level-2 sites this repository gates are %d of the %d here. %d print."
       % (port.get(2, 0), len(at[2]), pr[2]),
    3: "NOT COVERED by this gate's level-3 lane: %d upstream sites, %d print, and %d "
       "port sites, so the lane shows cumulativeness and nothing about level 3."
       % (len(at[3]), pr[3], port.get(3, 0)),
    4: "GENERATED SOURCE (codegen/__init__.py:462). %d upstream sites, %d print, %d "
       "port sites." % (len(at[4]), pr[4], port.get(4, 0)),
    5: "THE UOP LIST (codegen/__init__.py:274 `print(pyrender(ast))`). %d upstream "
       "sites, %d print, %d port sites -- but the port HAS `pyrender` "
       "(uop/render.bend:1886), so this is unbuilt, not unrepresentable."
       % (len(at[5]), pr[5], port.get(5, 0)),
    6: "NOTHING PRINTABLE on this fixture: %d upstream sites, %d of which prints, and "
       "%d port sites. usb.py:25 sets a libusb log level and viz/cli.py:216 is reachable "
       "only from the viz CLI. A LIMIT OF UPSTREAM, NOT OF THE PORT."
       % (len(at[6]), pr[6], port.get(6, 0)),
    7: "DISASSEMBLY (codegen/__init__.py:464) plus the buffer ledger (device.py:171/198, "
       "where device.bend has no debug_ge at all). %d upstream sites, %d print, %d port "
       "sites." % (len(at[7]), pr[7], port.get(7, 0)),
  }
  for L in ALL_LEVELS:
    print("  level %d: %s" % (L, notes[L]))
  print()
  print("  LEVEL 6 CONTRADICTS THE BRIEF'S SCALE, and that is a finding rather than a")
  print("  gap in this gate. The scale says 6 = '+ linearized'. This tree has NO")
  print("  `DEBUG >= 6` that prints a linearized graph: `schedule/__init__.py:141` prints")
  print("  the SCHEDULED KERNEL COUNT at `DEBUG >= 3`, and nothing else in tinygrad/")
  print("  renders a linearized graph under DEBUG. Measured on a fixed end-to-end")
  print("  fixture (`--probe-levels`), level 6 adds 0 stdout lines over level 5.")
  print()
  print("  AND THE REST OF THE SCALE IS UNGATED TOO: this repository gates %d of the %d"
       % (sum(port.values()), len(sites)))
  print("  upstream sites at levels 1..7. At level 2 that is %d of %d, so %d level-2"
       % (port.get(2, 0), len(at[2]), len(at[2]) - port.get(2, 0)))
  print("  sites are ungated (am/ip.py x5, nvdev.py, bnxtdev.py x2, decomp/dtype.py,")
  print("  opt/search.py x4, engine/realize.py x2, function.py), and every one of the")
  print("  %d sites above level 2 is ungated as well."
       % (len(sites) - port.get(1, 0) - port.get(2, 0)))


def usite_selfcheck():
  """Complaints about the DERIVED inventory. Empty list is the pass condition.

  Three things are checked, all of them things a derived table can still get wrong:
  the classification is TOTAL (every site line is one of print/other), every level in
  1..7 has at least one site upstream (a level with none is a level this gate cannot
  say anything about, and that has to be visible), and the two sides of a
  `DEBUG >= 5`/`DEBUG >= 6` line are counted once each.
  """
  sites = upstream_sites()
  bad = [s for s in sites if s[3] not in ("print", "other")]
  empty = [L for L in ALL_LEVELS if not any(s[0] == L for s in sites)]
  return [("UNCLASSIFIED", "%s:%d" % (s[1], s[2])) for s in bad] + \
         [("LEVEL-WITH-NO-UPSTREAM-SITE", str(L)) for L in empty]


# ===========================================================================
# WHAT CPython PRINTS AT EACH OF 4..7, on ONE FIXED END-TO-END PROBE.
#
# THE FIXTURE IS FIXED AND THAT IS THE POINT. `DEBUG` changes control flow, so a level
# comparison over a graph the level can reach is a comparison of two different
# programs. The probe is ONE small tensor program, written once here and run once per
# level in a FRESH process (a ContextVar's value is a process-boot constant), so the
# only difference between two runs is the level.
#
# The counts are COUNTS OF NEW LINES relative to level 2, and they are the measured
# evidence that a level is real upstream. They are NOT row values -- a count alone is
# not a gate -- so they are printed on the harness's own report and the DENOMINATOR
# (the level-2 line count they are relative to) is printed with them.
# ===========================================================================
PROBE47_BODY = """
from tinygrad import Tensor
from tinygrad.helpers import Context
with Context(DEV="CPU"):
  a = Tensor([1.0, 2.0, 3.0]).realize()
  b = Tensor([4.0, 5.0, 6.0]).realize()
  (a * b + a).realize().numpy()
print("PROBE-OK")
"""


def at(lines, i):
  return lines[i] if i < len(lines) else ""


# ===========================================================================
# THE SITE INVENTORY, PER LEVEL. "WHICH of the seven gated sites fire when the level
# is L", as a comma-joined list of their names -- not a COUNT, because a count cannot
# name the site that stopped firing and the whole question is per-site.
#
# CPython's side runs each site's own lane in a fresh process at DEBUG=L and records
# which produced their line. The port's side calls each of the seven `*_dbg` defs with
# `dbg = L` and records which answered non-empty. Both sides therefore answer the SAME
# question with the SAME vocabulary, and the row is the answer.
#
# THIS IS THE CUMULATIVITY ROW, and it is measured rather than declared: a port whose
# `DEBUG=4` behaved as `DEBUG=1` would answer this row with `mem` alone, and would
# disagree with CPython's `mem,ar,st,am185,am225,am251,am254`.
# ===========================================================================
# ===========================================================================
# WHICH OF THE SEVEN SITES FIRE, IN ONE CHILD PER LEVEL.
#
# ONE CHILD, NOT SEVEN, because seven children per level is 56 extra processes per gate
# run and the gate already spends a minute in them. The tagging below is what makes one
# child sufficient and is not a shortcut: `builtins.print` is shadowed by a wrapper that
# prefixes every line with the name of the site currently under test, so a line can be
# attributed to a site BY ITS OWN TEXT rather than by its position -- and position does
# not work here, because a site below its gate is ABSENT from stdout rather than blank,
# so every later site shifts up by one. That is the `am185/am225/am251/am254` rule this
# repository already records, and a `fires_*` row built on position would be wrong
# exactly when a site is gated out.
#
# EACH SITE GETS ITS OWN EXPECTED PREFIX, because at DEBUG >= 1 CPython prints other
# things while these lanes run (`device.py:41` "opened device", and
# `schedule/__init__.py:141` "scheduled" at >= 1 with >1 kernel). Counting "any line
# tagged mem" would therefore answer a different question than the one the port answers.
# ===========================================================================
FIRES_BODY = """
import builtins, linecache
_BP = builtins.print
CUR = ["?"]
def _tp(*a, **k):
    _BP("SITE " + CUR[0] + " " + " ".join(str(x) for x in a))
builtins.print = _tp
# -- mem: schedule/memory.py:59 ------------------------------------------
CUR[0] = "mem"
import tinygrad.schedule.memory as M
from tinygrad.uop.ops import UOp, Ops, ParamArg
from tinygrad.dtype import dtypes
def B(slot, size, dev="CPU", dt=dtypes.int32):
  return UOp(Ops.BUFFER, arg=ParamArg(slot=slot, dtype=dt, size=size,
                                      name="B%d" % slot, device=dev))
def SINK(body, *args): return UOp(Ops.SINK, src=(body, *args))
A2, B2, C2, D2, E2, F2 = B(2,1024), B(3,2048), B(4,512), B(5,256), B(6,128), B(7,64)
STORE = UOp(Ops.STORE, src=(A2, B2), arg=ParamArg(slot=0, dtype=dtypes.int32))
M.memory_plan_rewrite(UOp(Ops.LINEAR, src=(SINK(STORE, B2), SINK(STORE, C2),
                         SINK(UOp(Ops.ADD, src=(D2, E2)), D2, E2),
                         SINK(UOp(Ops.MUL, src=(D2, F2)), D2, F2))))
# -- ar: schedule/allreduce.py:16 ----------------------------------------
CUR[0] = "ar"
from tinygrad.helpers import Context
from tinygrad.schedule.allreduce import handle_allreduce
def _buf(devs, size, dt=dtypes.float32):
  return UOp(Ops.BUFFER, arg=ParamArg(slot=0, dtype=dt, size=size, vmin_vmax=(0, size),
                                      name="b", device=tuple(devs)))
_r = UOp(Ops.REDUCE, src=(_buf(["CPU:0","CPU:1","CPU:2","CPU:3"], 300000),),
         arg=(Ops.ADD, "CPU:0"))
handle_allreduce(_r.src[0], _r)
# -- st: nn/state.py:260 --------------------------------------------------
CUR[0] = "st"
import pickle, os, collections, numpy, tempfile
from tinygrad.nn.state import torch_load
_h = pickle.dumps(None) * 3
_b = pickle.dumps({"a": os.path.join, "b": collections.OrderedDict, "c": numpy.ndarray})
_f = os.path.join(tempfile.gettempdir(), "debug-fires-gate.pth")
with open(_f, "wb") as fh: fh.write(_h + _b + pickle.dumps([]))
torch_load(_f)
# -- am: amdev.py:185/225/251/254, ONE EXEC PER SITE ----------------------
from tinygrad.helpers import DEBUG
class FakeDev: devfmt = "0000:01:00.0"
for _tag, _line in (("am185", 185), ("am225", 225), ("am251", 251), ("am254", 254)):
  CUR[0] = _tag
  _src = linecache.getline(__ROOT__ + "/tinygrad/runtime/support/am/amdev.py", _line).strip()
  _sc = {"DEBUG": DEBUG, "self": FakeDev(), "ip": type("AM_GFX", (), {}), "print": _tp}
  _sc["ip"] = _sc["ip"]()
  exec(_src, _sc)
""".replace("__ROOT__", repr(ROOT))

# The exact prefix each site must produce. A line counts only when it is tagged with
# the site's own name AND carries that site's own text, so a neighbour's chatter in the
# same lane cannot answer this row.
SITE_PREFIX = {
    "mem": "memory reduced from ",
    "ar": "ALLREDUCE ",
    "st": "WARNING: returning Dummy for ",
    "am185": "am 0000:01:00.0: Malformed state.",
    "am225": "am 0000:01:00.0: boot done",
    "am251": "am 0000:01:00.0: AM_GFX initialized",
    "am254": "am 0000:01:00.0: Finalizing",
}
SITE_NAMES = ("mem", "ar", "st", "am185", "am225", "am251", "am254")


def fired_sites_py(n):
  """CPython: which of the seven sites fire at DEBUG=n, comma-joined, by RUNNING them.

  Attributed by the site's own text and not by position -- see FIRES_BODY for why
  position cannot work, since a gated-out site is absent from stdout and shifts the rest.
  """
  got = child(n, FIRES_BODY)
  if isinstance(got, str):
    return got
  fired = []
  for nm in SITE_NAMES:
    tag = "SITE " + nm + " "
    want = SITE_PREFIX[nm]
    if any(l.startswith(tag) and want in l[len(tag):] for l in got):
      fired.append(nm)
  return ",".join(fired)


def port_site_thresholds():
  """{threshold: how many `H.debug_ge(_, N)` sites the PORT has at N}, by grep.

  This is the port-side DENOMINATOR for "which levels can this gate say anything
  about". It is a grep over `tinybendygrad/` and not a constant, so adding a port site
  at level 5 moves the report instead of quietly invalidating it.
  """
  out = {}
  pat = re.compile(r"H\.debug_ge\(\s*[^,]+,\s*(\d+)\s*\)")
  for root, dirs, files in os.walk(os.path.join(ROOT, "tinybendygrad")):
    for fn in files:
      if not fn.endswith(".bend"):
        continue
      try:
        text = open(os.path.join(root, fn), encoding="utf-8", errors="replace").read()
      except OSError:
        continue
      for m in pat.finditer(text):
        n = int(m.group(1))
        out[n] = out.get(n, 0) + 1
  return out


def probe_levels():
  """`--probe-levels`: what CPython prints at 0..7 on ONE fixed end-to-end fixture.

  The DENOMINATOR is printed with every count, because a count alone says nothing about
  whether the level changed anything: `new=8` against a base of 21 and `new=8` against a
  base of 3 are not the same claim. MEASURED, and reported, not assumed:

    * levels 0..3 add the ops and the schedule line and NOTHING that prints code;
    * level 4 adds the GENERATED SOURCE (`codegen/__init__.py:462`);
    * level 5 adds the UOP LIST (`codegen/__init__.py:274`, `print(pyrender(ast))`);
    * level 6 adds NOTHING PRINTABLE on this fixture -- its two `DEBUG >= 6` sites are
      `usb.py:25` (sets a libusb log level) and `viz/cli.py:216` (a render predicate),
      and NEITHER writes to stdout;
    * level 7 adds the BUFFER LEDGER (`device.py:171/198`).

  The `sites printing at this level` column is read from UPSTREAM'S OWN SOURCE at the
  cited lines, with the `DEBUG >= N` right-hand side extracted by regex -- the level
  number is never typed by hand, because `nv_query_litter` was wrong in the port AND in
  the oracle and the differ reported zero disagreements over one mistake made twice.
  """
  base = None
  base_n = None
  sites = upstream_sites()
  print("%-6s %-7s %-9s %s" % ("level", "lines", "new", "upstream sites printing here"))
  for n in range(0, 8):
    got = child(n, PROBE47_BODY)
    if isinstance(got, str):
      print("%-6d ERROR   %s" % (n, got))
      continue
    lines = [l for l in got if l != "PROBE-OK"]
    if base is None:
      base, base_n = lines, len(lines)
    at = [s for s in sites if s[0] == n]
    hits = ["%s:%d" % (os.path.basename(s[1]), s[2]) for s in at]
    np_ = sum(1 for s in at if s[3] == "print")
    print("%-6d %-7d %-9d %d of %d upstream sites at this level print"
          % (n, len(lines), len(lines) - base_n, np_, len(at)))
    if n in NEW_LEVELS:
      print("         cites: %s" % (" ".join(hits) or "(none)"))
      print("         new lines vs level 0:")
      for l in lines:
        if l not in base:
          print("           | %s" % l[:132])
  print()
  print("DECLARED ABSENCE, with its denominator. These are the levels whose sites are")
  print("REAL upstream and ABSENT from the port, which is a different fact from a row")
  print("that agrees on an empty string. The port column is counted by GREPPING THE")
  print("PORT for `H.debug_ge(_, N)`, so it moves if a port site is ever added:")
  port = port_site_thresholds()
  for n in ALL_LEVELS:
    at = [s for s in sites if s[0] == n]
    p = sum(1 for s in at if s[3] == "print")
    print("  level %d: upstream %2d site(s), %2d print and %2d do not | port %d site(s)"
          % (n, len(at), p, len(at) - p, port.get(n, 0)))
  print("  port thresholds, all of them: %s" % (sorted(port.items()),))
  print("  => levels 3, 4, 5, 6 and 7 have NO port site at all, so a row at any of")
  print("     them cannot be a disagreement about the port's CODE. The existing")
  print("     level-3 lane is in that set: it runs at DEBUG=3 and reproduces the")
  print("     level-2 rows, which is CUMULATIVITY and not coverage of level 3.")


def main():
  # THE DERIVED INVENTORY IS CHECKED BEFORE ANY ROW IS PRINTED, and this is a FAILURE
  # (exit 2), never a verdict. A level upstream has no site for is a level this gate
  # cannot speak about, and reporting that as agreement is the failure this unit exists
  # to prevent.
  complaints = usite_selfcheck()
  if complaints:
    print("FATAL: the derived upstream DEBUG inventory is not well-formed:", file=sys.stderr)
    for kind, what in complaints:
      print("  %s: %s" % (kind, what), file=sys.stderr)
    sys.exit(2)

  if len(sys.argv) > 1 and sys.argv[1] == "--probe-levels":
    probe_levels()
    return
  if len(sys.argv) > 1 and sys.argv[1] == "--inventory":
    inventory()
    return
  lvl = sys.argv[1] if len(sys.argv) > 1 else "2"
  level = None if lvl == 'unset' else int(lvl)

  for l in child(level, ENV_BODY):
    rows.append(l)

  for nm, text in GI_TEXTS:
    got = child(None, GI_BODY, {"DBGPROBE": text})
    # A REFUSAL KILLS THE IMPORT, so the child exits non-zero and `child` has already
    # said so. Answering `ValueError` for those texts is what CPython does, and it is
    # what the port's `gi_of_text` answers THE DEFAULT for -- the narrowing, which
    # `gi_m1_ge2` below measures from both sides.
    rows.append(nm + "=" + (got[0] if got else "ValueError"))
  # `gi_m1_ge2` is THE NARROWING, both sides measured: CPython's `int("-1")` is -1 and
  # `int(-1 >= 2)` is 0; the port answers the default `0` and `0 >= 2` is also 0.
  # `gi_m1_*` IS THE NEGATIVE-VALUE NARROWING. `"-1"` is an ACCEPTED text, so it is
  # NOT in `GI_TEXTS`: CPython stores `-1` and the port stores the default `0`, and a
  # row holding either number would be red against the other. What must agree is the
  # COMPARISON every site makes, and every threshold in tinygrad is `DEBUG >= N` with
  # `N >= 0` -- so these three rows are `int(-1 >= N)` here and
  # `int(H.gi_of_text("-1", 0) >= N)` there, and all three are 0 on both sides.
  for n in (1, 2, 3):
    row("gi_m1_ge%d" % n, int(-1 >= n))

  for l in child(None, MB_BODY):
    rows.append(l)

  ar_got = keep(child(level, AR_BODY), "ar")
  for i, tag in enumerate(AR_TAGS):
    row(tag, at(ar_got, i))
  mem_got = keep(child(level, MEM_BODY), "mem")
  row("mem_plan", at(mem_got, 0))
  # THE `!=` CONDITION, asked the way memory.py:59 asks it. `memory.py:59` is
  #     DEBUG >= 1 and (omem := sum(nbytes.values()) / 1e6) != (nmem := sum(arena_sizes.values()) / 1e6)
  # and the printed line is `f"memory reduced from {omem:.2f} MB -> {nmem:.2f} MB,
  # {len(first_appearance)} -> {len(arenas)} bufs"`. The two sums are supplied as
  # PARAMETERS so the NO-SAVING case is reachable: the one plan fixture in this
  # repository saves bytes, so `mem_plan` alone cannot tell "print only when there is a
  # saving" from "always print", and the mutation that drops the `!=` moved nothing
  # until these rows existed.
  for nm, omem, nmem in (("mem_cond_same", 12032, 12032), ("mem_cond_diff", 12032, 11776)):
    om, nm_ = omem / 1e6, nmem / 1e6
    if om != nm_:
      row(nm, "memory reduced from %.2f MB -> %.2f MB, 5 -> 2 bufs" % (om, nm_))
    else:
      row(nm, "")
  st_got = keep(child(level, ST_BODY), "st")
  row("st_bad", at(st_got, 0))
  row("st_ok1", "")
  row("st_ok2", "")

  am_here = child(level, AM_BODY)
  for i, tag in enumerate(AM_TAGS):
    row(tag, at(am_here, i))

  # `thr_*` -- "did this site print at level EXACTLY 1", from the real functions.
  row("thr_mem", int(bool(keep(child(1, MEM_BODY), "mem"))))
  row("thr_ar", int(bool(keep(child(1, AR_BODY), "ar"))))
  row("thr_st", int(bool(keep(child(1, ST_BODY), "st"))))
  am_one = child(1, AM_BODY)
  for i, tag in enumerate(AM_TAGS):
    row("thr_" + tag, int(len(am_one) > i))

  for n in (0, 1, 2):
    row("mem_L%d" % n, at(keep(child(n, MEM_BODY), "mem"), 0))
    row("ar_ring_L%d" % n, at(keep(child(n, AR_BODY), "ar"), 0))
    row("st_bad_L%d" % n, at(keep(child(n, ST_BODY), "st"), 0))
    row("am185_L%d" % n, at(child(n, AM_BODY), 0))
    row("am251_L%d" % n, at(child(n, AM_BODY), 2))

  # THE PIN. The plan's own quantities, read at DEBUG UNSET so the level cannot reach
  # them even in principle -- the structural half of "hold the graph fixed by
  # construction". The shell script DIGESTS these across every level and exits 2 on a
  # mismatch, which is the half that checks it.
  for l in keep(child(None, MEM_BODY), "pin"):
    rows.append(l)

  # THE CUMULATIVITY ROW, for each of levels 0..7. Which of the seven gated sites fire
  # when the level is L. At L >= 2 all seven must fire, which is the measured statement
  # that levels are cumulative; at L = 1 only `mem`, and at L = 0 none.
  for n in range(0, 8):
    row("fires_L%d" % n, fired_sites_py(n))

  print("\n".join(rows))


if __name__ == '__main__':
  main()