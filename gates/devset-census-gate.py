#!/usr/bin/env python3
"""devset-census-gate.py -- THE PORT's HCQ DEVICE SET: every site that names it, the value as
written, and whether it is the set upstream declared AT THE PIN THE PORT CITES.

    .venv/bin/python gates/devset-census-gate.py
    .venv/bin/python gates/devset-census-gate.py --rows
    .venv/bin/python gates/devset-census-gate.py --root PORT_TREE --repo GIT_REPO

WHY THIS INSTRUMENT, AND IT IS NOT THE ONE THAT ALREADY EXISTS. `gates/vendordep-census-gate.py`
MEASURES THE FILE GRAPH, and its own header states the finding this file starts from: "`HCQ_DEVS`
is defined in `device.py` and merely IMPORTED by `hcq2.py`, and the port declares it in
`runtime/support/hcq2.bend`. A name-keyed census scores that pair as covered. It is not." THAT IS
THE WRONG-FILE HALF, and it is measured THERE. WHAT IS MEASURED NOWHERE IS THE VALUE HALF: which
devices are IN the port's set, whether the port's set is upstream's set, whether the port's
CITATION of that set resolves, and whether the port's LAG is attributed. Those are four different
questions, and this file asks all four.

THE POPULATION IS DISCOVERED BY A DIRECTORY WALK, NOT NAMED. `os.walk` over `tinybendygrad/` plus
`endswith(".bend")`, because `glob('*.bend')` returns `[]` when `.bend` files ARE on disk -- the
trap `AGENTS.md` records. A census that names its population by hand is a list.

THE PIN IS DISCOVERED BY A PROPERTY OF UPSTREAM, NOT BY A COMMIT LIST. The port's own header
declares which upstream file it is a port of (`PYTHON: tinygrad/runtime/support/hcq2.py:1-646`), so
the pin is "every upstream commit whose `hcq2.py` is 646 lines". That is a DISCOVERY, it is
STABLE (history is immutable), and it is checked against a SECOND, independent statement the port
makes -- the commit it names in `AT PIN `<hash>`` -- so the two must agree. Measured 2026-10-20:
the 646-line commits are `0a5776355` and `b786dca7b`, and both declare the same set at the same
line, so the pin is well-defined.

THE SET IS EVALUATED, NOT TRANSCRIBED. Upstream's line is
`HCQ_DEVS = frozenset(("NV", "QCOM", "CUDA", "NULL", "METAL")) | (frozenset(("AMD",)) if HCQ2 else
frozenset())` and this file PARSES it and evaluates it with `HCQ2=1` -- the branch the port's own
comment says it is. The port's side is parsed out of the `.bend` text. NEITHER SIDE IS A HUNDRED
LISTS, so a change to either is a change to the MEASUREMENT and not to a copy of it.

THE THREE PARALLEL TABLES ARE THE PORT'S OWN HAZARD, AND LANE 2 IS ABOUT IT. The port carries the
same six names in three places -- `HCQ_DEVS()` (ids), `dev_head.name()` (names) and `dev_name()`
(the id->name ladder) -- and NOTHING in the tree checks that they agree. `all_in` asks
`dev_id(dev_head(x)) != NO_HCQ_DEV`, so a name added to one table and not to another makes the
membership predicate disagree with the set, silently, with no row moving. Lane 2 is that check.

LANE 9 IS THE ONE THAT MAKES A LATER CHANGE FAIL. The port has no `UVM_DEVS` and no def of
`get_enqueue_devs` -- the only upstream consumer of `UVM_DEVS` -- so the missing constant has no
consumer. If somebody IMPLEMENTS `get_enqueue_devs` in the port, lane 9 goes RED and says the
constant is now required. A missing constant with no consumer and a missing constant with a
consumer are different defects, and only one of them is free.

THE EXITS ARE `gatekit`'s. `REFUSED` (3) when the port file or upstream is absent -- an absent
input is not a pass. `DEAD` (5) when no row was emitted. `FAIL` (1) when a lane is red.
"""

from __future__ import annotations

import ast
import os
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from gatekit import DEAD, FAIL, PASS, REFUSED, VERDICT  # noqa: E402

GATE_ROOT = HERE.parent
PORT_TREE = GATE_ROOT
GIT_REPO = GATE_ROOT

HCQ_PATH = "tinygrad/runtime/support/hcq2.py"
DEV_PATH = "tinygrad/device.py"
UPSTREAM = "refs/remotes/upstream/master"
PORT_HCQ = "tinybendygrad/runtime/support/hcq2.bend"
PORT_DEVICE = "tinybendygrad/device.bend"

SKIP_DIRS = {".git", ".venv", "references", "__pycache__", "node_modules"}
SYMBOLS = ("HCQ_DEVS", "UVM_DEVS")

# THE PORT's THREE TABLES, AND THE SHAPES THEY ARE WRITTEN IN.
DEV_ID = re.compile(r"^def HCQ_DEV_([A-Z0-9_]+)\(\) -> U32: (\d+)$", re.M)
SET_LIST = re.compile(r"^def HCQ_DEVS\(\) -> List<&2, U32>:\n\s*\[([^\]]*)\]", re.M)
NAME_LIST = re.compile(r"^def dev_head\.name\(\) -> List<&2, String>: \[([^\]]*)\]", re.M)
NAME_LADDER = re.compile(r"^def dev_name\(n: U32\) -> String:\n((?:  .*\n)+)", re.M)
LADDER_CASE = re.compile(r"case (\d+): \"([A-Z0-9_]+)\"")

# THE PORT's OWN DECLARATIONS, READ BY PATH.
PYTHON_RANGE = re.compile(r"PYTHON: " + re.escape(HCQ_PATH) + r":1-(\d+)")
TABLE_ROW = re.compile(r"^#\s+:(\d+)\s+HCQ_DEVS\b", re.M)
INLINE_CITE = re.compile(r"hcq2\.py:(\d+)")
NAMED_PIN = re.compile(r"AT PIN `([0-9a-f]{7,40})`")

ROWS_ONLY = False


def _retarget(argv: list[str]) -> None:
  """`--root PORT_TREE` re-points the port tree and `--repo GIT_REPO` the git repo, so the PLANT
  can mutate the port against the REAL upstream without the real tree being edited. They are
  SEPARATE because a scratch tree is not a git repo, and the pin lives in git."""
  global PORT_TREE, GIT_REPO
  if "--root" in argv:
    PORT_TREE = Path(argv[argv.index("--root") + 1]).resolve()
  if "--repo" in argv:
    GIT_REPO = Path(argv[argv.index("--repo") + 1]).resolve()


# --------------------------------------------------------------------- upstream


def git(*args: str) -> str:
  p = subprocess.run(("git",) + args, cwd=GIT_REPO, capture_output=True, text=True)
  if p.returncode:
    raise RuntimeError(f"git {' '.join(args)}: rc={p.returncode} {p.stderr.strip()}")
  return p.stdout


def git_opt(*args: str) -> str:
  """`git`, ABSENT -> "". A missing blob is a fact to report, not a crash."""
  p = subprocess.run(("git",) + args, cwd=GIT_REPO, capture_output=True, text=True)
  return p.stdout if p.returncode == 0 else ""


def batch_blobs(specs: list[str]) -> dict[str, str]:
  """`spec` -> text for many specs, in ONE `git cat-file --batch`.

  The CONTENT is read by SIZE and not by a delimiter: a `.py` file contains newlines, and a
  reader that split on one would truncate it.
  """
  if not specs:
    return {}
  p = subprocess.run(["git", "cat-file", "--batch"], cwd=GIT_REPO,
                     input=("\n".join(specs) + "\n").encode(), capture_output=True)
  out: dict[str, str] = {}
  buf, pos = p.stdout, 0
  for spec in specs:
    nl = buf.find(b"\n", pos)
    if nl < 0:
      break
    parts = buf[pos:nl].decode("utf-8", "replace").split()
    pos = nl + 1
    if len(parts) < 3 or parts[1] == "missing":
      continue
    size = int(parts[2])
    out[spec] = buf[pos:pos + size].decode("utf-8", "replace")
    pos += size + 1
  return out


def ev(node: ast.AST, flags: dict[str, object]) -> object:
  """The four node kinds upstream's constant line is made of, and nothing else.

  A `frozenset((...))` node's ARGUMENT is a TUPLE, and the tuple's STRINGS are the members --
  so the call SPLATS its argument rather than making a set of one tuple.
  """
  if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "frozenset":
    out: list[str] = []
    for a in node.args:
      v = ev(a, flags)
      out.extend(v if isinstance(v, (list, tuple, frozenset, set)) else [v])
    return frozenset(out)
  if isinstance(node, ast.Tuple):
    return [ev(e, flags) for e in node.elts]
  if isinstance(node, ast.Constant) and isinstance(node.value, str):
    return node.value
  if isinstance(node, ast.BinOp) and isinstance(node.op, ast.BitOr):
    return ev(node.left, flags) | ev(node.right, flags)
  if isinstance(node, ast.IfExp):
    return ev(node.body, flags) if ev(node.test, flags) else ev(node.orelse, flags)
  if isinstance(node, ast.Name) and node.id in flags:
    return flags[node.id]
  raise ValueError(f"unexpected node in upstream's constant: {ast.dump(node)}")


def eval_set(rhs: str, flags: dict[str, object] | None = None) -> frozenset[str]:
  """Upstream's `HCQ_DEVS = <rhs>`, EVALUATED. The branch flags default to `HCQ2=1`, which is
  the branch the port's own comment says it is."""
  tree = ast.parse(rhs.strip(), mode="eval")
  return frozenset(ev(tree.body, flags if flags is not None else {"HCQ2": 1, "frozenset": frozenset}))


def constant_in(text: str, name: str) -> tuple[int, str] | None:
  """`(line number, the RIGHT-HAND SIDE)` for upstream's `name = ...`, or None."""
  for i, ln in enumerate(text.splitlines(), 1):
    if ln.startswith(f"{name} = "):
      return i, ln[len(name) + 3:]
  return None


def upstream_set(rev: str) -> tuple[frozenset[str] | None, int, str]:
  """`(set, line, file)` for `HCQ_DEVS` at `rev`. The constant is in `device.py` at upstream HEAD
  and in `hcq2.py` before the move, and BOTH are read, so the file it is found in is a RESULT and
  not an assumption."""
  for path in (DEV_PATH, HCQ_PATH):
    text = git_opt("show", f"{rev}:{path}")
    if not text:
      continue
    hit = constant_in(text, "HCQ_DEVS")
    if hit:
      return eval_set(hit[1]), hit[0], path
  return None, 0, ""


def upstream_commits(path: str) -> list[str]:
  """The upstream commits that touched `path`, NEWEST FIRST."""
  return git("log", "--format=%H", UPSTREAM, "--", path).split()


def pin_commits(n_lines: int) -> list[str]:
  """The upstream commits whose `hcq2.py` is exactly `n_lines` lines -- the pin, DISCOVERED by
  the port's own declared line count and not by a list of commits."""
  revs = upstream_commits(HCQ_PATH)
  texts = batch_blobs([f"{r}:{HCQ_PATH}" for r in revs])
  out = []
  for r in revs:
    t = texts.get(f"{r}:{HCQ_PATH}")
    if t is not None and t.count("\n") == n_lines:
      out.append(r)
  return out


def set_history() -> list[tuple[str, frozenset[str]]]:
  """`[(commit, set)]` for every upstream commit whose DIFF mentions `HCQ_DEVS`, OLDEST FIRST.

  A member of the set can only appear in a commit whose diff rewrote the line, so this is the
  complete set of places the set changed, and the first commit carrying a member is that
  member's attribution. The attribution is therefore DISCOVERED and not written down.
  """
  revs = git("log", "--format=%H", "-G", "HCQ_DEVS", UPSTREAM, "--", DEV_PATH, HCQ_PATH).split()
  texts = batch_blobs([f"{r}:{p}" for r in revs for p in (DEV_PATH, HCQ_PATH)])
  out = []
  for r in reversed(revs):
    s = None
    for p in (DEV_PATH, HCQ_PATH):
      hit = constant_in(texts.get(f"{r}:{p}", ""), "HCQ_DEVS")
      if hit:
        s = eval_set(hit[1])
        break
    if s is not None:
      out.append((r, s))
  return out


# ----------------------------------------------------------------- the port


def port_text(rel: str) -> str:
  p = PORT_TREE / rel
  return p.read_text(encoding="utf-8", errors="replace") if p.is_file() else ""


def census() -> list[tuple[str, int, str, str]]:
  """`(relpath, line, symbol, the line as written)` for every port site naming a symbol.

  DISCOVERED by a DIRECTORY WALK. The port tree is walked, not a list of files.
  """
  out: list[tuple[str, int, str, str]] = []
  base = PORT_TREE / "tinybendygrad"
  for dp, dn, fn in os.walk(base):
    dn[:] = [d for d in dn if d not in SKIP_DIRS]
    for n in sorted(fn):
      if not n.endswith(".bend"):
        continue
      p = Path(dp) / n
      rel = str(p.relative_to(PORT_TREE))
      for i, ln in enumerate(p.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        for sym in SYMBOLS:
          if sym in ln:
            out.append((rel, i, sym, ln.rstrip()))
  return out


def port_tables(text: str) -> dict[str, object]:
  """The port's three tables, parsed. Absent pieces are None rather than a guess."""
  ids = {name: int(v) for name, v in DEV_ID.findall(text)}
  setm = SET_LIST.search(text)
  names = NAME_LIST.search(text)
  ladder = NAME_LADDER.search(text)
  set_ids = re.findall(r"HCQ_DEV_([A-Z0-9_]+)\(\)", setm.group(1)) if setm else None
  name_list = re.findall(r"\"([A-Z0-9_]+)\"", names.group(1)) if names else None
  lad = {int(i): nm for i, nm in LADDER_CASE.findall(ladder.group(1))} if ladder else None
  return {"ids": ids, "set_ids": set_ids, "names": name_list, "ladder": lad}


def port_set(text: str) -> list[str] | None:
  """The port's device set, in the order `HCQ_DEVS()` gives it, by NAME."""
  t = port_tables(text)
  if t["set_ids"] is None or not t["ids"]:
    return None
  if any(k not in t["ids"] for k in t["set_ids"]):
    return None
  return list(t["set_ids"])


def comment_block(text: str) -> list[str]:
  """The comment run that QUOTES upstream's definition -- the block the pin is named in.

  It is found by the QUOTATION, not by proximity to the `def`: the port's `def HCQ_DEVS()` is
  twenty lines below the comment that quotes upstream's line, because the six `HCQ_DEV_*` id
  defs sit between them. A block found by proximity would be the wrong block.
  """
  lines = text.splitlines()
  hit = next((i for i, ln in enumerate(lines) if "HCQ_DEVS = frozenset" in ln), -1)
  if hit < 0:
    return []
  start = hit
  while start > 0 and lines[start - 1].startswith("#"):
    start -= 1
  end = hit
  while end + 1 < len(lines) and lines[end + 1].startswith("#"):
    end += 1
  return lines[start:end + 1]


# ------------------------------------------------------------------- lanes

checks: list[tuple[bool, str]] = []
rows: dict[str, str] = {}


def report(name: str, ok: bool, evidence: list[str] | None = None) -> None:
  checks.append((ok, name))
  if ROWS_ONLY:
    return
  print(f"  {'PASS' if ok else 'FAIL'}  {name}")
  for e in evidence or []:
    print(f"        {e}")


def main(argv: list[str]) -> int:
  global ROWS_ONLY
  ROWS_ONLY = "--rows" in argv
  _retarget(argv)
  hcq = port_text(PORT_HCQ)
  dev = port_text(PORT_DEVICE)
  if not hcq:
    print(f"REFUSED  the port's {PORT_HCQ} is ABSENT under {PORT_TREE}", file=sys.stderr)
    return REFUSED
  if not git_opt("rev-parse", "--verify", UPSTREAM):
    print(f"REFUSED  {UPSTREAM} is ABSENT under {GIT_REPO}", file=sys.stderr)
    return REFUSED

  # -- L1 THE CENSUS -------------------------------------------------------------------
  sites = census()
  hcq_sites = [s for s in sites if s[2] == "HCQ_DEVS"]
  uvm_sites = [s for s in sites if s[2] == "UVM_DEVS"]
  files = sorted({s[0] for s in sites})
  if not ROWS_ONLY:
    print("PORT SITES -- every place the port names HCQ_DEVS or UVM_DEVS")
    for rel, ln, sym, text in sites:
      print(f"  {rel}:{ln}  {sym}  {text}")
    print()
  ok1 = bool(sites) and all(s[0].endswith(".bend") for s in sites) and files == [PORT_HCQ]
  report("1 the census is a DISCOVERY and every site is in ONE port file", ok1,
         [f"{len(sites)} site(s) in {len(files)} file(s): {files}",
          f"HCQ_DEVS={len(hcq_sites)} UVM_DEVS={len(uvm_sites)}"])
  rows["devset.port_sites"] = str(len(sites))
  rows["devset.port_sites_hcq"] = str(len(hcq_sites))
  rows["devset.port_sites_uvm"] = str(len(uvm_sites))
  rows["devset.port_files"] = str(len(files))
  rows["devset.port_file"] = PORT_HCQ

  # -- L2 THE PORT's THREE TABLES AGREE ----------------------------------------------
  t = port_tables(hcq)
  pset = port_set(hcq)
  by_id = {i: nm for nm, i in t["ids"].items()}
  ladder = t["ladder"] or {}
  ids_in_order = [t["ids"].get(k) for k in (t["set_ids"] or [])]
  consistent = (
    pset is not None and t["names"] is not None and ladder
    and pset == t["names"]
    and ids_in_order == list(range(1, len(pset) + 1))
    and all(by_id.get(i) == nm for i, nm in ladder.items())
    and sorted(ladder) == sorted(by_id)
    and len(set(pset)) == len(pset)
  )
  report("2 the port's THREE parallel tables agree with EACH OTHER", bool(consistent),
         [f"HCQ_DEVS() -> {pset}",
          f"dev_head.name() -> {t['names']}",
          f"dev_name() ladder -> {ladder}",
          f"HCQ_DEV_* ids -> {t['ids']}"])
  rows["devset.port_set"] = ",".join(pset) if pset else ""
  rows["devset.port_set_n"] = str(len(pset)) if pset else "0"
  rows["devset.port_three_tables"] = "AGREE" if consistent else "DISAGREE"

  # -- L3/L4/L5 THE PIN, THE CITATION, THE NAMED PIN -----------------------------------
  m = PYTHON_RANGE.search(hcq)
  n_lines = int(m.group(1)) if m else 0
  pins = pin_commits(n_lines) if n_lines else []
  row = TABLE_ROW.search(hcq)
  cited = int(row.group(1)) if row else 0
  block = comment_block(hcq)
  inline = [int(x) for x in INLINE_CITE.findall("\n".join(block))]
  named = NAMED_PIN.search("\n".join(block))
  named_pin = named.group(1) if named else ""
  if not pins:
    report("3 the PIN is DISCOVERED by the port's declared line count", False,
           [f"the port declares `PYTHON: {HCQ_PATH}:1-{n_lines}` and no upstream commit has a "
            f"{HCQ_PATH} of that length"])
    rows["devset.pin_commits"] = "0"
    rows["devset.pin_set"] = ""
    rows["devset.pin_fidelity"] = "NO-PIN"
    rows["devset.citation"] = "NO-PIN"
    rows["devset.pin_named"] = named_pin
    rows["devset.port_cited_line"] = str(cited)
  else:
    sets = upstream_set(pins[0])
    pin_set, pin_line, pin_file = sets
    report("3 the PIN is DISCOVERED by the port's own declared line count", True,
           [f"the port declares `PYTHON: {HCQ_PATH}:1-{n_lines}`",
            f"the upstream commits with a {n_lines}-line {HCQ_PATH}: "
            f"{', '.join(p[:12] for p in pins)}"])
    ok4 = all(upstream_set(p) == (pin_set, pin_line, pin_file) for p in pins)
    ok5 = (cited == pin_line) and bool(inline) and set(inline) == {cited}
    report("4 the port's CITED LINE resolves AT the pin", bool(ok5),
           [f"the port's table row says `:{cited}` and its comment says {inline or '(none)'}",
            f"at the pin the constant is at `{pin_file}:{pin_line}`",
            f"pin commits: {', '.join(p[:12] for p in pins)}"])
    report("5 every discovered pin declares the SAME set", bool(ok4),
           [f"set at each pin: {sorted({tuple(sorted(upstream_set(p)[0] or ())) for p in pins})}"])
    ok3 = bool(pin_set) and set(pset or ()) == set(pin_set)
    report("6 the port's set IS the pin's set", bool(ok3),
           [f"port: {sorted(pset or [])}", f"pin: {sorted(pin_set or [])}"])
    ok6 = bool(named_pin) and any(named_pin.startswith(p[:len(named_pin)]) for p in pins)
    report("7 the port NAMES its pin and the name is one of the discovered pins", bool(ok6),
           [f"the port's comment names `{named_pin or '(nothing)'}`",
            f"the discovered pins are {', '.join(p[:12] for p in pins)}"])
    rows["devset.pin_line_count"] = str(n_lines)
    rows["devset.pin_commits"] = ",".join(p[:12] for p in pins)
    rows["devset.pin_set"] = ",".join(sorted(pin_set)) if pin_set else ""
    rows["devset.pin_set_n"] = str(len(pin_set)) if pin_set else "0"
    rows["devset.pin_fidelity"] = "SAME" if ok3 else "DIFFERENT"
    rows["devset.citation"] = "RESOLVES" if ok5 else "UNRESOLVED"
    rows["devset.pin_named"] = named_pin
    rows["devset.port_cited_line"] = str(cited)

  # -- L8 THE LAG AND ITS CAUSE --------------------------------------------------------
  head_set, head_line, head_file = upstream_set(UPSTREAM)
  history = set_history()
  first_seen: dict[str, str] = {}
  for rev, s in history:
    for m2 in s:
      first_seen.setdefault(m2, rev)
  port_members = set(pset or ())
  lag = sorted((head_set or frozenset()) - port_members)
  extra = sorted(port_members - (head_set or frozenset()))
  attributed = {m2: first_seen.get(m2, "") for m2 in lag}
  ok8 = not extra
  report("8 the port has NO device upstream HEAD does not have", ok8,
         [f"upstream HEAD: {sorted(head_set or [])} at `{head_file}:{head_line}`",
          f"the port: {sorted(port_members)}",
          f"the port has that upstream lacks: {extra or 'none'}",
          f"the port LAGS upstream by: {lag or 'none'}",
          f"and each lag member is attributed to the upstream commit that added it: "
          f"{ {k: v[:12] for k, v in attributed.items()} }"])
  rows["devset.upstream_head_set"] = ",".join(sorted(head_set)) if head_set else ""
  rows["devset.upstream_head_set_n"] = str(len(head_set)) if head_set else "0"
  rows["devset.upstream_head_file"] = f"{head_file}:{head_line}"
  rows["devset.lag"] = ",".join(lag)
  rows["devset.lag_attributed"] = ",".join(f"{k}@{v[:12]}" for k, v in attributed.items())

  # -- L9 THE SET's HOME ---------------------------------------------------------------
  dev_names_hcq = "HCQ_DEVS" in dev
  dev_imports_hcq = bool(re.search(r"^\s*import\s+\S*hcq2\.bend\b", dev, re.M))
  hcq_imports_dev = bool(re.search(r"^\s*import\s+\S*device\.bend\b", hcq, re.M))
  ok9 = (not dev_names_hcq) and (not dev_imports_hcq) and hcq_imports_dev
  report("9 the constant lives in ONE file and moving it would be an IMPORT CYCLE", ok9,
         [f"{PORT_DEVICE} names HCQ_DEVS: {dev_names_hcq}",
          f"{PORT_DEVICE} imports hcq2.bend: {dev_imports_hcq} (a cycle: hcq2.bend imports "
          f"device.bend: {hcq_imports_dev})",
          "and NO port file imports hcq2.bend at all, so nothing reads the constant from "
          "anywhere but this file"])
  rows["devset.device_bend_names_it"] = str(dev_names_hcq)
  rows["devset.device_bend_imports_hcq2"] = str(dev_imports_hcq)
  rows["devset.hcq2_imports_device"] = str(hcq_imports_dev)

  # -- L10 THE PORT HAS HIP AND CL, SO AVAILABILITY DOES NOT SETTLE THE SET -------------
  reg = re.search(r"^def registry\(\) -> List<&2, DEnt>:\n((?:  .*\n)+)", dev, re.M)
  reg_heads = re.findall(r"DEnt\{\d+, \"([a-z0-9_]+)\"", reg.group(1)) if reg else []
  has_hip, has_cl = "hip" in reg_heads, "cl" in reg_heads
  report("10 the port HAS a HIP and a CL backend, so the set's membership is NOT settled by "
         "device availability", has_hip and has_cl,
         [f"the port's device registry: {reg_heads}",
          "so the port's set omitting HIP and CL is NOT 'Bend has fewer devices'"])
  rows["devset.port_has_hip"] = str(has_hip)
  rows["devset.port_has_cl"] = str(has_cl)

  # -- L11 UVM: ABSENT AND UNUSED ------------------------------------------------------
  enq_defs = re.findall(r"^def (enq\w*)", hcq, re.M)
  pin_uvm = any("UVM_DEVS" in git_opt("show", f"{p}:{HCQ_PATH}") for p in pins) if pins else False
  ok11 = not uvm_sites and not enq_defs and not pin_uvm
  report("11 the port's UVM_DEVS is ABSENT AND UNUSED: no `get_enqueue_devs` to need it", ok11,
         [f"the port's UVM_DEVS sites: {len(uvm_sites)}",
          f"the port's `get_enqueue_devs` defs (the only upstream consumer of UVM_DEVS): "
          f"{enq_defs or 'none'}",
          f"the pin declares UVM_DEVS: {pin_uvm} (upstream introduced it at a3178d228, "
          f"2026-10-13, AFTER the pin)",
          f"upstream HEAD declares UVM_DEVS: "
          f"{'yes' if 'UVM_DEVS' in git_opt('show', f'{UPSTREAM}:{DEV_PATH}') else 'no'}"])
  rows["devset.uvm_port_sites"] = str(len(uvm_sites))
  rows["devset.uvm_pin_declares"] = str(pin_uvm)
  rows["devset.port_get_enqueue_defs"] = str(len(enq_defs))

  if not rows:
    print("DEAD  emitted no rows", file=sys.stderr)
    return DEAD
  for k, v in rows.items():
    print(f"{k}={v}")
  failed = [n for ok, n in checks if not ok]
  if not ROWS_ONLY:
    print(f"# devset-census-gate: {len(checks) - len(failed)} of {len(checks)} PASS")
    if failed:
      print(f"# FAILED: {failed}")
  return FAIL if failed else PASS


if __name__ == "__main__":
  print(f"# exit vocabulary: {VERDICT}", file=sys.stderr)
  raise SystemExit(main(sys.argv[1:]))
