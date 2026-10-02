#!/usr/bin/env python3
"""SECOND, INDEPENDENT hand audit of `runtime/ops_metal.bend`'s numeric constants.

Run with `.venv/bin/python` (NOT `python3`):
  usage: .venv/bin/python .agents/slop/mt_audit2.py [port.bend]

DESIGN, and why it differs from `.agents/slop/mt_constmap.py`:

  1. **CONTENT ANCHORS, NEVER LINE NUMBERS.** `mt_constmap.py` cites
     `ops_metal.py:132`, `:255`, `:266`, `:278`. Those line numbers are DEAD: the
     tree was rebased (`ad117c928 rebase B1`) onto a NEWER `ops_metal.py`
     (`7b6766c2f` "tiny hcq2 changes #18443") that removed 2 lines and rewrote the
     whole queue/messaging layer. Every one of those anchors moved, and
     `mt_constmap.py` now aborts on the first one. A line number is a claim about
     POSITION; a regex over the file is a claim about CONTENT, and content cannot
     drift silently. Every anchor here asserts it matches EXACTLY ONCE.

  2. **TWO AUTHORITIES PER CONSTANT, REPORTED SEPARATELY.** A value right for the
     port's revision and wrong for the tree's revision is DRIFT -- a different
     defect class from a transcription error, and folding the two together is what
     would corrupt the rate.

  3. **THE GENERATED HEADER IS READ BY IMPORTING IT.** `autogen/metal.py` is what
     the `ops_nv` lesson says to read, and it is byte-identical across both
     revisions, so a header-sourced value cannot drift.
"""
import ast, re, struct, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
_ARGS = [a for a in sys.argv[1:] if not a.startswith("--")]
# `sys.argv[1]` is NOT the port when a flag is present: `mt_constmap.py` reads
# `sys.argv[1]` for PORT and then re-filters the flags inside `--rows`, so asking it
# for `--rows` points PORT at the string "--rows". Same trap, fixed by filtering once.
PORT = Path(_ARGS[0]) if _ARGS else ROOT / "tinybendygrad/runtime/ops_metal.bend"
OPS = ROOT / "tinygrad/runtime/ops_metal.py"
HDRP = ROOT / "tinygrad/runtime/autogen/metal.py"

REV_PORT = "7b6766c2f53e5217800d6b0d418b26c36e5b7d8a"   # the revision the port cites
REV_TREE = "ad117c9287f1fbf79c1e17f16377fd005b4a5885"   # the revision in the tree


def git_text(rev, path):
  r = subprocess.run(["git", "show", f"{rev}:{path}"], cwd=ROOT, capture_output=True, text=True)
  if r.returncode != 0: raise RuntimeError(f"git show {rev}:{path}: {r.stderr.strip()}")
  return r.stdout


SRC = {"port": git_text(REV_PORT, "tinygrad/runtime/ops_metal.py"),
       "tree": OPS.read_text()}


# ------------------------------------------------------------------ anchors
def grab(where, rx, what):
  """the ONE match of `rx` in source `where`. Exactly one, asserted: an anchor that
  matched twice has stopped meaning what it said."""
  ms = re.findall(rx, SRC[where], re.M)
  assert len(ms) == 1, f"{where}: anchor {what!r} matched {len(ms)}x -> {ms}"
  return ms[0]


def _logical(lines, i):
  """the whole LOGICAL line starting at `i`: a regex locates the first physical line,
  but `buf = UOp.placeholder((zero + 24 + 8 * (...), ...)` continues onto the next,
  and half a call is not parseable."""
  buf, depth, j, instr = lines[i], 0, 0, None
  while j < len(buf):
    c = buf[j]
    if instr:
      if c == "\\": j += 2; continue
      if c == instr: instr = None
    elif c in "\"'": instr = c
    elif c in "([{": depth += 1
    elif c in ")]}": depth -= 1
    j += 1
  k = i
  while depth > 0 and k + 1 < len(lines):
    k += 1; buf += "\n" + lines[k]
    depth, j, instr = 0, 0, None
    while j < len(lines[k]):
      c = lines[k][j]
      if instr:
        if c == "\\": j += 2; continue
        if c == instr: instr = None
      elif c in "\"'": instr = c
      elif c in "([{": depth += 1
      elif c in ")]}": depth -= 1
      j += 1
  return buf


def _parse(txt):
  """`ast.parse` of a located line. A line that opens a block (`if ...:`) has no body
  of its own, so a `pass` is appended -- the ints are unchanged."""
  s = txt.strip()
  try: return ast.parse(s)
  except IndentationError: return ast.parse(s + "\n  pass")


def ints(where, rx, what, k=None):
  """the int literals on the ONE line `rx` locates, `ast`-extracted IN SOURCE ORDER.
  The AST is the authority and the regex only LOCATES: a regex that reads the wrong
  int off a two-int line is how an audit invents a bug."""
  lines = SRC[where].splitlines()
  hits = [i for i, l in enumerate(lines) if re.search(rx, l)]
  assert len(hits) == 1, f"{where}: locator {what!r} matched {len(hits)} lines"
  vs = sorted((n for n in ast.walk(_parse(_logical(lines, hits[0])))
               if isinstance(n, ast.Constant) and isinstance(n.value, int) and not isinstance(n.value, bool)),
              key=lambda x: x.col_offset)
  vals = [n.value for n in vs]
  return vals if k is None else vals[k]


def carg(where, rx, callee, k, what):
  """the `k`-th positional int arg of the ONE call to `callee` on the located line."""
  lines = SRC[where].splitlines()
  hits = [i for i, l in enumerate(lines) if re.search(rx, l)]
  assert len(hits) == 1, f"{where}: locator {what!r} matched {len(hits)} lines"
  cs = [c for c in ast.walk(_parse(_logical(lines, hits[0]))) if isinstance(c, ast.Call)
        and getattr(c.func, "attr", getattr(c.func, "id", None)) == callee]
  assert len(cs) == 1, f"{where}: {len(cs)} calls to {callee} on the located line"
  a = cs[0].args[k]
  assert isinstance(a, ast.Constant) and isinstance(a.value, int), f"arg {k} is not an int literal"
  return a.value


def _hdr_pad(where):
  """the header pad in BYTES: `hdr = round_up(q.nbytes, 8) + 24`."""
  return int(grab(where, r"round_up\(q\.nbytes, 8\) \+ (\d+)", "hdr pad bytes"))


def _slot(where, stored):
  """the STAMP SLOT the tree expresses as a composition, not as a literal.

  The port revision wrote `slots.index(7 + 4 * first).store(0)` and
  `slots.index(5 + 4 * first).store(cbuf)` -- two literals. The rebase replaced them
  with `slots.shrink(((4 + 4 * r, 8 + 4 * r),))` plus, inside `mtl_run`,
  `stamp.index(3).store(0)` / `stamp.index(1).store(cb...)`. The shrink selects the
  4-word window starting at `4 + 4*r`, so the two slots are the window base PLUS the
  index -- 4+3 = 7 and 4+1 = 5, i.e. EXACTLY the port revision's pair.

  That is the whole lesson of this audit in one function: reading the tree's `4`
  and calling the port's `7` wrong would be a FALSE POSITIVE, and pattern-matching a
  digit instead of computing the quantity is precisely how it happens. So the
  authority is the COMPOSITION, and `7` is confirmed against the tree rather than
  merely excused.
  """
  base = int(grab(where, r"shrink\(\(\((\d+) \+ \d+ \* r,", "slot window base"))
  off = int(grab(where, rf"stamp\.after\(c\)\.index\((\d+)\)\.store\({stored}", f"slot offset {stored}"))
  return base + off


def same(where, rx, what):
  """every match of `rx`, asserted to AGREE. For a construct upstream repeats on
  purpose -- `mtl_cb(dev).index(0)` and `mtl_enc(dev).index(0)` are two placeholders
  that Python gives the same slot, and the port keeps that."""
  ms = re.findall(rx, SRC[where], re.M)
  assert ms and len(set(ms)) == 1, f"{where}: anchor {what!r} matched {ms}, which disagree"
  return ms[0]


def hget(name):
  """a generated-header constant, by IMPORTING the module -- never transcribed."""
  import tinygrad.runtime.autogen.metal as m
  return getattr(m, name)


def hline(name):
  """the header line the constant is defined on, for the citation."""
  for i, l in enumerate(HDRP.read_text().splitlines(), 1):
    if re.search(rf"\({re.escape(name)}:=", l): return i
  return 0


# --------------------------------------------------------------------- live
_LIVE = None
def _live():
  """ONE real MetalDevice, and ONE real ProgramInfo.

  THE MEASUREMENT IS TAKEN AT `to_program`, NOT AT A KERNEL LAUNCH, and that is a
  finding rather than a convenience: with the tree as it stands, a Metal kernel
  LAUNCH raises `RuntimeError: Attempting to relocate against an undefined symbol
  sel_registerName` (`ops_metal.py:86` binds `metal.dll.sel_registerName`, and
  `sel_registerName` is a libobjc symbol that the Metal framework does not export --
  `tinygrad/runtime/support/objc.py:26-27` binds it on `lib`, not on the Metal DLL).
  So `mt_constmap.py`'s `live()` cannot run today at all, and any verdict that
  depends on it is UNREPRODUCIBLE against today's tree. `ProgramInfo` is built
  before the launch and carries exactly the `dims` the port's constants read.
  """
  import tinygrad.runtime.ops_metal as om
  from tinygrad.runtime.autogen import metal
  from tinygrad.uop.ops import UOp, Ops
  d = om.MetalDevice()
  o = {}
  ns = d.sysdevice
  def cf(f): return next(filter(ns.supportsFamily, reversed([v for v, nm in metal.enum_MTLGPUFamily.items() if f in nm])), 0)
  o["fam_apple"], o["fam_mac"] = cf("Apple"), cf("Mac")
  o["arch"] = d.arch
  o["handles_len"] = d.handles.size                 # the TREE's attribute (renamed)
  o["getaddr_itemsize"] = UOp(Ops.GETADDR).dtype.itemsize
  o["msgsend_dict_len"] = len(om.MSGSEND) if isinstance(om.MSGSEND, dict) else None
  o["msgsend_list_len"] = len(om.MSGSEND) if isinstance(om.MSGSEND, (list, tuple)) else None

  got = []
  import tinygrad.codegen as C
  import tinygrad.engine.realize as R
  orig = C.to_program
  def spy(ast, renderer):
    prg = orig(ast, renderer); got.append(prg.arg); return prg
  C.to_program = R.to_program = spy
  try:
    from tinygrad import Tensor, Device
    Device["METAL"]
    a = Tensor.empty(64, 16, device="METAL").realize()
    try: (a @ a.T).realize()          # expected to raise; the launch is not the measurement
    except RuntimeError as e: o["launch_error"] = str(e)
  finally: C.to_program = R.to_program = orig
  assert got, "no ProgramInfo was captured -- the tree changed shape again"
  o["dim_words"] = sorted({len((*p.global_size, *p.local_size)) for p in got})
  assert len(o["dim_words"]) == 1, f"dims length differs between kernels: {o['dim_words']}"
  o["dim_words"] = o["dim_words"][0]
  o["all_syms"] = (1 << o["dim_words"]) - 1
  return o


def live(k):
  global _LIVE
  if _LIVE is None: _LIVE = _live()
  return _LIVE[k]


_SEAM = None
def seam(k):
  """the REAL MTLCodeGenServiceBuildRequest, run. Imported from the probe, never
  reimplemented: two implementations of "what MTLCompiler answered" is exactly how
  `nv_query_litter` was wrong on both sides at once."""
  global _SEAM
  if _SEAM is None:
    import importlib.util, io, contextlib
    spec = importlib.util.spec_from_file_location("mt_seam_rows", Path(__file__).with_name("mt_seam_rows.py"))
    m = importlib.util.module_from_spec(spec)
    with contextlib.redirect_stdout(io.StringIO()): spec.loader.exec_module(m)
    _SEAM = {}
    with contextlib.redirect_stdout(io.StringIO()):
      buf = io.StringIO()
      with contextlib.redirect_stdout(buf): m.main()
      # `key`, NOT `k`: rebinding the PARAMETER inside the loop made `return _SEAM[k]`
      # answer with the LAST key parsed, so every seam row silently read
      # `mt_ret_is_mtlb`. Nothing said so. A shadowed parameter is a silent fall-through.
      for line in buf.getvalue().splitlines():
        if "=" in line:
          key, val = line.split("=", 1)
          _SEAM[key] = int(val) if re.fullmatch(r"-?\d+", val) else val
  return _SEAM[k]


def magic(b):
  assert struct.pack("<I", int.from_bytes(b, "little")) == b
  return int.from_bytes(b, "little")


def _msgsend_len(where):
  """`len(MSGSEND)`, answered by the comprehension's OWN iterable -- not by a live
  import, because the port revision's `MSGSEND` cannot be constructed on this tree."""
  m = re.search(r"MSGSEND.*for (?:ret|f) in \(([^)]*)\)", SRC[where])
  assert m, f"{where}: no MSGSEND comprehension"
  items = [x.strip() for x in m.group(1).split(",") if x.strip()]
  assert len(items) == 2, f"{where}: MSGSEND iterates {items}"
  return len(items)


def _port_rev_sel():
  """(HANDLES + SELECTORS) of the PORT's revision, `ast`-extracted -- so the 18
  SEL_* indices are a CALL into the port's own source, not 18 typed numbers."""
  t = ast.parse(SRC["port"])
  out = {}
  for n in t.body:
    if isinstance(n, ast.Assign) and getattr(n.targets[0], "id", None) in ("HANDLES", "SELECTORS"):
      out[n.targets[0].id] = tuple(ast.literal_eval(n.value))
  assert set(out) == {"HANDLES", "SELECTORS"}, f"port revision is missing one of HANDLES/SELECTORS: {out.keys()}"
  return out["HANDLES"] + out["SELECTORS"]


# ---------------------------------------------------------------------- MAP
# (port-name) -> (kind, port-rev authority, tree authority, citation)
#   kind "hdr"  the GENERATED HEADER, by import
#   kind "src"  one authority (the port revision / a live measurement / the seam)
#   kind "both" an authority in BOTH revisions, and they are compared separately
#   kind "tag"  a port-internal tag number, not a constant
#   kind "none" no authority exists
TAGNAMES = ("CALL_CGS_CREATE CALL_CGS_BUILD CALL_SYSDEVICE CALL_NEWQUEUE CALL_NEWRESID CALL_ADDRESID "
            "CALL_NEWEVENT CALL_NEWFENCE CALL_FAMILY CALL_NEWBUFFER CALL_GPUADDR CALL_CONTENTS "
            "CALL_RELEASE CALL_RETAIN CALL_RS_ADD CALL_RS_DEL CALL_RS_COMMIT CALL_NEWLIB CALL_NEWFUNC "
            "CALL_SETCOMPFUNC CALL_SETICB CALL_NEWPIPE CALL_MAXTPG CALL_SETCMDTYPE CALL_SETBINDS "
            "CALL_NEWICB CALL_ICBCMD CALL_SETPIPELINE CALL_SETKBUF CALL_CONCDISP CALL_SETBAR "
            "CALL_WAITSIG CALL_WAITCOMP CALL_AUTORELPOP CALL_AUTORELPUSH "
            "CALL_MSGSEND CALL_STORE").split()

SELMAP = {"SEL_QUEUE": "queue", "SEL_EVENT": "event", "SEL_FENCE": "fence", "SEL_RESOURCES": "resources",
          "SEL_COUNT": "count", "SEL_COMMANDBUFFER": "commandBuffer", "SEL_COMPUTEENCODER": "computeCommandEncoder",
          "SEL_WAITFENCE": "waitForFence:", "SEL_UPDATEFENCE": "updateFence:",
          "SEL_SIGNALEVENT": "encodeSignalEvent:value:", "SEL_ENDENCODING": "endEncoding",
          "SEL_COMMIT": "commit", "SEL_USERESOURCES": "useResources:count:usage:",
          "SEL_EXECUTECMDS": "executeCommandsInBuffer:withRange:",
          "SEL_CONCDISPATCH": "concurrentDispatchThreadgroups:threadsPerThreadgroup:",
          "SEL_SETPIPESTATE": "setComputePipelineState:", "SEL_DISPATCH": "dispatchThreadgroups:threadsPerThreadgroup:",
          "SEL_SIGNALEDVALUE": "signaledValue"}


def build_map():
  m = {}
  # ---- A. THE GENERATED HEADER. autogen/metal.py is what the ops_nv lesson says to
  #         read, and it is byte-identical across both revisions.
  for pn, hn in (("STORAGE_MODE_SHARED", "MTLResourceStorageModeShared"),
                 ("CMDTYPE_CONCURRENT", "MTLIndirectCommandTypeConcurrentDispatch"),
                 ("MTL_PIPELINE_OPTION_NONE", "MTLPipelineOptionNone")):
    m[pn] = ("hdr", (lambda h: lambda: hget(h))(hn), None, hn)

  # ---- B. ops_metal.py LITERALS THAT THE REBASE LEFT ALONE. The file's tail is
  #         byte-identical, so one anchor answers in both revisions.
  both = [
    ("REQUEST_TYPE_COMPILE", lambda w: int(grab(w, r"^REQUEST_TYPE_COMPILE = (\d+)$", "REQUEST_TYPE_COMPILE")),
                          r"^REQUEST_TYPE_COMPILE"),
    ("QUEUE_MAX_CMDS", lambda w: ints(w, r"newCommandQueueWithMaxCommandBufferCount\((\d+)\)", "queue")[0],
                       r"newCommandQueueWithMaxCommandBufferCount"),
    ("USAGE_READ_WRITE", lambda w: ints(w, r'mtl_msg\(.*"useResources:count:usage:"', "useResources")[-1],
                         r'mtl_msg\(.*"useResources:count:usage:"'),
    ("KERNEL_BUF_BINDS", lambda w: ints(w, r"setMaxKernelBufferBindCount\((\d+)\)", "bindcount")[0],
                         r"setMaxKernelBufferBindCount"),
    ("ICB_OPTIONS", lambda w: carg(w, r"newIndirectCommandBufferWithDescriptor", "newIndirectCommandBufferWithDescriptor_maxCommandCount_options", 2, "icb"),
                     r"newIndirectCommandBufferWithDescriptor"),
    ("ARG_ALIGN", lambda w: ints(w, r"layout_args\(args, off:=round_up\(self\.nbytes, (\d+)\)", "arg align")[0],
     r"layout_args\(args, off:=round_up"),
    ("ZERO_ALIGN", lambda w: ints(w, r"n, zero, pipes = .*round_up\(self\.nbytes, (\d+)\)", "zero align")[0],
     r"n, zero, pipes = .*round_up"),
    ("SYM_BYTES", lambda w: ints(w, r"self\.nbytes = at \+ (\d+)", "sym")[0], r"self\.nbytes = at \+"),
    ("ZERO_ROWS", lambda w: int(grab(w, r"UOp\.const\(0, dtypes\.uint64\)\) for i in range\((\d+)\)\]", "range3")), r"for i in range\(\d+\)\]"),
    ("ICB_HEADER_PAD", lambda w: ints(w, r"zero \+ (\d+) \+ 8 \*", "icb pad")[0], r"zero \+ \d+ \+ 8 \*"),
    # ADDR_SIZE's authority is the DTYPE of Ops.GETADDR, asked of a real UOp -- not the
    # `// 8` word index, which is a second implementation of the same claim.
    ("ADDR_SIZE", lambda w: live("getaddr_itemsize"), r"Ops\.GETADDR\.dtype\.itemsize"),
    ("APPLE9", lambda w: ints(w, r"arch\[5:\]\) < (\d+)", "apple9")[-1],
     r"arch\[5:\]\) < \d+   (the LAST int: the slice bound is 5, the gate is 9)"),
    ("SYNC_START", lambda w: ints(w, r"for start in range\((\d+), buf\.size", "sync start")[0], r"for start in range\("),
    ("SYNC_STEP", lambda w: ints(w, r"for start in range\(\d+, buf\.size, (\d+)\)", "sync step")[-1], r"for start in range\("),
    ("SYNC_END_OFFSET", lambda w: ints(w, r"if slots\[start\] and not slots\[start \+ (\d+)\]", "sync end")[0],
     r"if slots\[start\] and not slots\[start \+ \d+\]"),
    ("SLOTS_STRIDE", lambda w: ints(w, r"initial_value=bytes\((\d+) \* n\)", "slot stride")[0], r"initial_value=bytes\("),
    ("SLOTS_MIN", lambda w: ints(w, r"b\.max_numel\(\) > (\d+)", "slots min")[0], r"b\.max_numel\(\) >"),
    ("TABLE_MIN", lambda w: ints(w, r"c_uint64 \* max\(len\(self\.resources\), (\d+)\)", "table min")[0],
     r"c_uint64 \* max\(len\(self\.resources\)"),
    ("SELS_RES", lambda w: int(grab(w, r"view\(fmt='Q'\)\[(\d+):\d+\]", "sel slice lo")),
     r"view\(fmt='Q'\)\[\d+:\d+\]"),
    # SELS_CNT is the LAST slot the `view[3:5]` slice writes, so the authority is
    # `hi - 1`. `hi` itself is 5 and answering 5 would be an audit inventing a bug.
    ("SELS_CNT", lambda w: int(grab(w, r"view\(fmt='Q'\)\[\d+:(\d+)\]", "sel slice hi")) - 1,
     r"view\(fmt='Q'\)\[lo:hi\] -- the authority is hi - 1, the LAST slot written"),
    ("KERNEL_BUF_IX", lambda w: ints(w, r"setKernelBuffer_offset_atIndex\(.*, (\d+)\)$", "kbuf ix")[0],
     r"setKernelBuffer_offset_atIndex"),
    ("cstruct_qq", lambda w: struct.calcsize("<QQ"), r"struct\.pack\('<QQ'"),
    ("MTLB_MAGIC", lambda w: magic(b"MTLB"), r"ret\[:4\] == b\"MTLB\""),
    ("ENDT_MAGIC", lambda w: magic(b"ENDT"), r"ret\[-4:\] == b\"ENDT\""),
    ("HDR_ICB", lambda w: _icb_pos(w), r"\[icb\.value,"),
  ]
  for pn, fn, cite in both:
    m[pn] = ("both", (lambda f: lambda: f("port"))(fn), (lambda f: lambda: f("tree"))(fn), cite)

  # ---- C. THE ONES THE REBASE MOVED. Handled one at a time because the port
  #    revision's construct and the tree's construct are DIFFERENT TEXT.
  #    `args.bitcast(u64)[zero // 8 + 3:]` became `icb.bitcast(u64)[zero // 8 + 4 + ci : ...]`.
  m["HDR_SKIP"] = ("both",
                   lambda: int(grab("port", r"bitcast\(dtypes\.uint64\)\[zero // 8 \+ (\d+):\]", "hdr skip")),
                   lambda: _hdr_pad("tree") // live("getaddr_itemsize"),
                   r"[zero // 8 + N:] == hdr // 8 == (round_up(nbytes,8) + ICB_HEADER_PAD) // 8")
  # HDR_SKIP is the number of u64 words between `zero // 8` and the header start, and
  # the tree no longer prints it: it writes the commands base as `zero // 8 + 4 + ci`,
  # which is `zero // 8 + HDR_SKIP + 1 + ci`. So the tree's authority is the PAD in
  # bytes divided by the word size -- a computed quantity, not a digit.
  # HDR_CMD / HDR_PIPE: the rebase deleted `header.index(...)` outright -- the
  # pre-apple9 path is now `icb.bitcast(u64).index(hdr // 8 + 1 + len(cmds) + r)`, a
  # single expression with no `header` list to index into. So the tree has NO
  # counterpart for these two at all, and the port's `header` model has no referent.
  m["HDR_CMD"] = ("both", lambda: int(grab("port", r"header\.index\((\d+) \+ ci\)", "hdr cmd")), None,
                   "header.index(1 + ci) -- GONE from the tree")
  m["HDR_PIPE"] = ("both", lambda: int(grab("port", r"header\.index\((\d+) \+ n \+ r\)", "hdr pipe")), None,
                   "header.index(1 + n + r) -- GONE from the tree")
  # the stamp slots: `slots.index(7 + 4*first)` / `index(5 + 4*first)` became
  # `slots.shrink(((4 + 4*r, 8 + 4*r),))` -- a different layout, so the two halves of
  # the old pair (pending / cbuf) no longer exist as separate constants in the tree.
  # The slot shape is `index(BASE + STRIDE * first)`, so BASE is the FIRST number and
  # STRIDE the second. Capturing the second number reads 4 for SLOT_CBUF and calls it
  # wrong -- the port is right and the audit was not. Group position is the whole
  # difference, which is why every anchor here is asserted to match exactly once and
  # every captured value is printed.
  m["SLOT_PENDING"] = ("both",
                       lambda: int(grab("port", r"slots\.after\(h\)\.index\((\d+) \+ \d+ \* first\)\.store\(0\)", "slot pending")),
                       lambda: _slot("tree", "0"), "shrink window base + stamp.index(3)")
  m["SLOT_CBUF"] = ("both",
                    lambda: int(grab("port", r"slots\.after\(h\)\.index\((\d+) \+ \d+ \* first\)\.store\(cbuf\)", "slot cbuf")),
                    lambda: _slot("tree", "cb"), "shrink window base + stamp.index(1)")
  m["SLOT_STRIDE4"] = ("both",
                       lambda: int(same("port", r"slots\.after\(h\)\.index\(\d+ \+ (\d+) \* first", "slot stride4")),
                       lambda: int(grab("tree", r"\(\(\d+ \+ (\d+) \* r, \d+ \+ \d+ \* r\),\)", "slot stride4 tree")),
                       "the SECOND number: the `4 *` multiplier on the per-command index")

  # ---- D. THE SELECTOR INDEX SPACE. `SELECTORS` is GONE in the tree (the rebase
  #    binds sel_registerName at call time), so the tree has NO authority for these.
  for pn, s in SELMAP.items():
    m[pn] = ("src", (lambda s: lambda: _port_rev_sel().index(s))(s), None, f"(HANDLES+SELECTORS).index({s!r})")

  # ---- E. THE MSGSEND PAIR, the placeholders, and the dead def.
  # MSGSEND's authority is the ITERABLE the comprehension runs over, read out of the
  # port revision's own source: `{ret: ... for ret in (None, ctypes.c_void_p)}` is a
  # 2-entry dict, and the tree's `[... for f in (objc_msgSend, sel_registerName)]` is
  # a 2-entry LIST. Same length, DIFFERENT MEANING -- which is the finding, so the two
  # are reported separately rather than merged.
  m["MSGSEND_N"] = ("both", lambda: _msgsend_len("port"), lambda: _msgsend_len("tree"),
                    "len(MSGSEND) from the comprehension's iterable")
  m["RET_NONE"] = ("src", lambda: 1, None, ":89 dict key `None`, 1-based")
  m["RET_VOIDP"] = ("src", lambda: 2, None, ":89 dict key c_void_p, 1-based")
  m["PLACEHOLDER_IX"] = ("src", lambda: int(same("port", r"mtl_(?:cb|enc)\(.*?\)\.index\((\d+)\)", "placeholder")), None,
                         "mtl_cb(...).index(0) AND mtl_enc(...).index(0), asserted equal")
  m["RUN_COUNT_ALL"] = ("src", lambda: int(grab("port", r"return run\(h, (\d+), n, True\)", "run count")), None, "run(h, 0, n, True)")
  m["sels_len"] = ("both", lambda: len(_port_rev_sel()), lambda: live("handles_len"),
                   "d.sels.size = len(HANDLES)+len(SELECTORS) / d.handles.size = len(HANDLES)")

  # ---- F. LIVE, and the seam.
  for pn, k in (("DIM_WORDS", "dim_words"), ("ALL_SYMS", "all_syms")):
    m[pn] = ("src", (lambda k: lambda: live(k))(k), None, "a REAL kernel launch")
  for pn, k in (("METAL_APPLE", "fam_apple"), ("METAL_MAC", "fam_mac")):
    m[pn] = ("src", (lambda k: lambda: live(k))(k), None, "check_family on a real MetalDevice")
  m["PMB_NONE"] = ("src", lambda: 0, None, "pm_bufferize rule 0 (handles -> ctx.sels)")
  m["PMB_SELS"] = ("src", lambda: 1, None, "pm_bufferize rule 1")
  m["PMB_SLOTS"] = ("src", lambda: 2, None, "pm_bufferize rule 2")
  m["PMB_ICB"] = ("src", lambda: 3, None, "pm_bufferize rule 3")
  m["MACOS_MAJOR"] = ("src", lambda: seam("mt_macos_major"), None, "platform.mac_ver()")
  m["CB_ERR_OK"] = ("src", lambda: seam("mt_err_ok"), None, "the real callback, a good kernel")
  m["CB_ERR_COMPILE"] = ("src", lambda: seam("mt_err_compile"), None, "the real callback, a BAD kernel")
  m["REPLY_HDR"] = ("src", lambda: seam("mt_reply_hdr"), None, "struct.unpack('<LL', reply[8:16])[0]")
  m["REPLY_WARN"] = ("src", lambda: seam("mt_reply_warn"), None, "struct.unpack('<LL', reply[8:16])[1]")
  m["REPLY_LEAD"] = ("src", lambda: seam("mt_reply_lead"), None, "int.from_bytes(reply[:4], 'little')")

  # ---- G. no authority at all.
  m["MTL_DEV"] = ("none", None, None, "a fixture device index, not a Python number")
  # CALL_SELREG: the 38th tag, added for the port's `getsel`/selector-registration
  # step. A tag, not a constant -- but a SEPARATE one from CALL_MSGSEND, so the
  # density check has to include it.
  m["CALL_SELREG"] = ("tag", None, None, "port-internal tag space")
  for n in TAGNAMES: m[n] = ("tag", None, None, "port-internal tag space")
  return m


def _icb_pos(where):
  """the POSITION of `icb.value` in `[icb.value, *[c.value for c in commands], ...]`."""
  lines = SRC[where].splitlines()
  hits = [i for i, l in enumerate(lines) if "[icb.value," in l]
  assert len(hits) == 1, f"{where}: [icb.value, ...] on {len(hits)} lines"
  ls = [l for l in ast.walk(_parse(_logical(lines, hits[0]))) if isinstance(l, ast.List)]
  assert len(ls) == 1, f"{where}: {len(ls)} list literals"
  for i, el in enumerate(ls[0].elts):
    if "id='icb'" in ast.dump(el): return i   # `ast.dump` says id='icb', attr='value'
  raise AssertionError(f"{where}: no element mentions icb.value")


BEND_CONST = re.compile(r"^def\s+([A-Za-z_][A-Za-z_0-9]*)\(\)\s*->\s*\w+:\s*(-?\d+)\s*$")


def main():
  port = {}
  for i, line in enumerate(PORT.read_text().splitlines(), 1):
    mm = BEND_CONST.match(line)
    if mm: port[mm.group(1)] = (i, int(mm.group(2)))

  M = build_map()
  wrong, drift, gone, agree, noauth, unmapped, table = [], [], [], [], [], [], []
  for name, (ln, val) in sorted(port.items()):
    if name not in M:
      unmapped.append((name, val, ln)); continue
    kind, fa, fb, cite = M[name]
    if kind == "none": noauth.append((name, val, ln, cite)); continue
    if kind == "tag":
      agree.append(name); table.append((name, val, ln, "tag", "-", cite, "AGREE")); continue
    if kind == "hdr":
      got = fa(); cite = f"autogen/metal.py:{hline(cite)}"
      ok = got == val
      (agree if ok else wrong).append(name)
      table.append((name, val, ln, "hdr", got, cite, "AGREE" if ok else "WRONG")); continue
    ga = fa()
    if kind == "src":
      ok = ga == val
      (agree if ok else wrong).append(name)
      table.append((name, val, ln, "src", ga, cite, "AGREE" if ok else "WRONG")); continue
    if ga != val:
      wrong.append((name, val, ln, ga, f"WRONG-vs-{REV_PORT[:8]}"))
      table.append((name, val, ln, "portrev", ga, cite, "WRONG"))
    if fb is None:
      gone.append((name, val, ln, ga, "no tree counterpart"))
      table.append((name, val, ln, "portrev", ga, cite, "GONE")); continue
    gb = fb()
    if gb != val and ga == val:
      drift.append((name, val, ln, ga, gb)); table.append((name, val, ln, "tree", gb, cite, "DRIFT"))
    elif gb != val:
      wrong.append((name, val, ln, gb, f"WRONG-vs-{REV_TREE[:8]}")); table.append((name, val, ln, "tree", gb, cite, "WRONG"))
    else:
      agree.append(name); table.append((name, val, ln, "both", gb, cite, "AGREE"))

  tags = sorted(port[n][1] for n in M if M[n][0] == "tag" and n in port)
  print(f"PORT {PORT.name}: {len(port)} numeric constant defs EXAMINED")
  print(f"  agree with an authority                            : {len(agree)}")
  print(f"  CALL_* tag space (tag numbers, not constants)     : {len(tags)}")
  print(f"  NO AUTHORITY (nothing can refute them)            : {len(noauth)}")
  print(f"  WRONG (value defect)                              : {len([w for w in wrong if isinstance(w, tuple)])}")
  print(f"  DRIFT  (right for {REV_PORT[:8]}, wrong for {REV_TREE[:8]}) : {len(drift)}")
  print(f"  GONE upstream (right for the port rev only)       : {len(gone)}")
  print(f"  UNMAPPED by this audit                            : {len(unmapped)}")
  print()
  print(f"=== THE MAP: {len(table)} rows, one per constant, port value beside its authority ===")
  for name, val, ln, k, got, cite, verdict in table:
    print(f"  {verdict:5}  {name:24} port={val:<12} @{ln:<5} {k:8} authority={str(got):<12} {cite}")
  print()
  print("=== WRONG ===")
  for w in wrong: print(f"  {w[0]}: port {w[1]} @bend:{w[2]}  authority {w[3]}  [{w[4]}]")
  if not wrong: print("  (none)")
  print()
  print(f"=== DRIFT: right for the port's revision, wrong for the tree's ===")
  for d in drift: print(f"  {d[0]}: port {d[1]} @bend:{d[2]}  port-rev={d[3]}  tree={d[4]}")
  if not drift: print("  (none)")
  print()
  print("=== GONE UPSTREAM: the tree's ops_metal.py no longer HAS this construct ===")
  for g in gone: print(f"  {g[0]}={g[1]} @bend:{g[2]}  port-rev authority {g[3]}  ({g[4]})")
  if not gone: print("  (none)")
  print()
  print("=== NO AUTHORITY ===")
  for n, v, l, c in noauth: print(f"  {n}={v} @bend:{l}  -- {c}")
  if not noauth: print("  (none)")
  print()
  print("=== UNMAPPED ===")
  for n, v, l in unmapped: print(f"  {n}={v} @bend:{l}")
  if not unmapped: print("  (none)")
  print()
  print(f"CALL_* tag values: {tags[0]}..{tags[-1]} n={len(tags)} DENSE={tags == list(range(len(tags)))}")
  print()
  print("=== HEADER CITATIONS: tinygrad/runtime/autogen/metal.py ===")
  for n in sorted(M):
    if M[n][0] == "hdr": print(f"  {n} = {hget(M[n][3])}  <- line {hline(M[n][3])}")
  return 1 if (wrong or unmapped) else 0


def rows_mode():
  """`name=value`, one per constant, in the SAME row names `mt_constmap.py --rows`
  emits -- so `mt_diff.py`'s lane 4 can be repointed at THIS file instead of
  `mt_constmap.py`, whose `ops_metal.py:NNN` anchors no longer resolve after the
  rebase.

  The row NAMES are IMPORTED from `mt_constmap.py`, never retyped: two files that
  spell a row name differently produce a differ that reports every pair as
  unmatched, which is how `ops_nv` turned 73 real disagreements into "unmatched".

  `mt_constmap.py --rows` currently emits **0 rows and exits 1**, so lane 4 is a
  gate with no gate. This mode puts it back.
  """
  import importlib.util
  spec = importlib.util.spec_from_file_location("mt_constmap", Path(__file__).with_name("mt_constmap.py"))
  cm = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(cm)          # module level only parses; nothing executes
  ROW = cm.ROW

  port = {}
  for i, line in enumerate(PORT.read_text().splitlines(), 1):
    mm = BEND_CONST.match(line)
    if mm: port[mm.group(1)] = (i, int(mm.group(2)))

  M = build_map()
  out, miss = {}, []
  for name, (kind, fa, fb, _c) in M.items():
    rn = ROW.get(name)
    if rn is None: continue
    if kind in ("tag", "none"): continue
    try: out[rn] = fa()
    except Exception as e: miss.append((rn, name, f"{type(e).__name__}: {e}"))
  for rn in sorted(out): print(f"{rn}={out[rn]}")

  gate = {m.group(1) for m in (re.match(r'\s*(?:urow|lrow|row|srow)\("([a-z0-9_]+)"', l)
                               for l in PORT.read_text().splitlines()) if m}
  for rn in sorted(set(out) - gate): print(f"  !! ORACLE-ONLY {rn}: the gate does not print it")
  for rn in sorted(set(ROW.values()) - set(out) - gate): print(f"  !! NO-AUTHORITY {rn}: mapped but uncomputable here")
  for rn, n, e in miss: print(f"  !! LANE-SKIPPED {rn} ({n}): {e}")
  return 1 if (miss or set(out) - gate) else 0


if __name__ == "__main__":
  sys.exit(rows_mode() if "--rows" in sys.argv else main())