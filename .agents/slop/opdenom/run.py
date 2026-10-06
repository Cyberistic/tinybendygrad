#!/usr/bin/env python3
"""opdenom/run.py -- the oracle's census under PLANTED graphs, one process per state.

WHY BEND IS NOT RUN HERE: the composition of the NOT-REACHED split is a property of the
PY-side per-op table (`tal.update(py["per_op"])`) and of the enum, so the bend stream moves
neither number. The orchestrator owns `bend` exclusively; this harness replaces
`graphcmp.emit_bend` with a function that returns the py rows, which keeps the census's own
`devs` precondition satisfiable (both sides open the same device) and exercises every
assertion in `main()` without spawning a compiler. It is a PLANT, and named as one.

ONE PROCESS PER STATE IS FORCED BY THE ORACLE, not by taste: `main()` REFUSES to run once
tinygrad is imported, because `DEV` freezes at import and a second census in the same process
would print a device it is not running on. So `.venv/bin/python run.py --all` re-invokes
itself once per state with `--state`, and each state's census is about the device it names.
"""
import contextlib, importlib.util, io, os, subprocess, sys
import collections

# THE CORPUS IS LIVE AND ANOTHER UNIT IS EDITING IT. `graphcmp.py` gained graphs `getaddr`,
# `mulacc`, `threefry`, `unshard` and `wmma` at 13:42 (MEASURED: 25 -> 30 graphs), and the
# `wmma` one raises mid-edit. A number quoted over a corpus nobody names is unauditable, so
# `OPDENOM_PIN` restricts this process to the graph list RECORDED in an artifact -- the
# like-for-like baseline is the 25 graphs in `runs/graphcmp/D/D0-coverage-census.txt`. The
# oracle itself does not need this: it discovers its denominator, so it follows the corpus.
_PIN = os.environ.get("OPDENOM_PIN")

os.environ["PYTHONHASHSEED"] = "0"
os.environ["LC_ALL"] = "C"
os.environ["DEV"] = "CPU"
sys.path.insert(0, ".agents/slop")
import graphcmp as G  # noqa: E402

WANT = ("NOT REACHED", "OF WHICH", "UNEXERCISED", "DENOMINATOR:", "COVERAGE:",
        "ORACLE SELFCHECK", "OPS PER ENUM SECTION")


def apply_pin() -> None:
  """Restrict `G.GRAPHS` to the list recorded in `OPDENOM_PIN`. DISCOVERED from the artifact
  (column 1 of its two-space-indented table), never typed, so a re-taken baseline pins itself."""
  if not _PIN:
    return
  names = {ln.split()[0] for ln in open(_PIN).read().splitlines()
           if ln.startswith("  ") and ln.split()}
  dropped = sorted(set(G.GRAPHS) - names)
  for k in dropped:
    del G.GRAPHS[k]
  print(f"# PINNED to {len(G.GRAPHS)} graphs from {_PIN} (dropped {dropped})")


def load_oracle():
  spec = importlib.util.spec_from_file_location("oracle", ".agents/slop/graphcmp-oracle.py")
  O = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(O)
  return O


def mirror(dev, graph, *a, **k):
  return (G.emit_py(graph, None), ["(emit_bend planted -- no bend process)"])


def drop_alloc_from_alu():
  """Remove ALLOC rows from one graph's py stream: one reached program op disappears."""
  orig = G.emit_py

  def fewer(graph, plant):
    rows = orig(graph, plant)
    return [r for r in rows if G.unchunks(r)[1] != "ALLOC"] if graph == "alu" else rows
  G.emit_py = fewer


PLANT_NOTE: list[str] = []


def drop_sole_op():
  """DISCOVERED, not chosen: find the op the corpus reaches in EXACTLY ONE graph, then drop
  it from that graph. `ALLOC` was the first attempt and it MOVED NOTHING -- sixteen graphs
  reach it, so removing it from one graph leaves the reached set untouched. The plant has to
  remove an op's LAST occurrence, so the op is picked by the corpus's own per-op graph count.

  LAZY, because tinygrad is not loaded until `main()` calls `load_tinygrad()`, and the
  oracle REFUSES to run once tinygrad is imported (DEV freezes at import). So the discovery
  happens on the first emitted graph, inside the run it is planting on."""
  orig = G.emit_py
  st: dict = {"done": False}

  def wrapper(graph, plant, *a, **k):
    if not st["done"]:
      graphs_of: collections.Counter = collections.Counter()
      for g in sorted(G.GRAPHS):
        graphs_of.update({G.unchunks(ln)[1] for ln in orig(g, None)})
      st["op"] = min(op for op, c in graphs_of.items() if c == 1)
      st["graph"] = next(g for g in sorted(G.GRAPHS)
                         if any(G.unchunks(ln)[1] == st["op"] for ln in orig(g, None)))
      st["done"] = True
      PLANT_NOTE.append(f"# PLANT: removed every `{st['op']}` row from graph `{st['graph']}` "
                        f"-- the ONE graph reaching it (discovered from the corpus, no bend)")
    rows = orig(graph, plant, *a, **k)
    return [r for r in rows if G.unchunks(r)[1] != st["op"]] if graph == st["graph"] else rows
  G.emit_py = wrapper


STATES = {"baseline": None, "drop-alloc": drop_alloc_from_alu, "drop-sole-op": drop_sole_op}


def one(state: str) -> int:
  apply_pin()
  O = load_oracle()
  G.emit_bend = mirror
  if STATES[state]:
    STATES[state]()
  buf = io.StringIO()
  with contextlib.redirect_stdout(buf):
    rc = O.main()
  print(f"===== STATE {state}  (rc={rc}) =====")
  for note in PLANT_NOTE:
    print(note)
  for ln in buf.getvalue().splitlines():
    if any(t in ln for t in WANT):
      print(ln)
  return rc


if __name__ == "__main__":
  if len(sys.argv) > 1 and sys.argv[1] == "--all":
    rc = 0
    for state in STATES:
      print()
      rc |= subprocess.run([sys.executable, __file__, state]).returncode
    sys.exit(rc)
  sys.exit(one(sys.argv[1] if len(sys.argv) > 1 else "baseline"))
