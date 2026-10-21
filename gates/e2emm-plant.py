#!/usr/bin/env python3
"""gates/e2emm-plant.py -- the vals re-derivation, and the control that it does not move the record.

Does not run checks/e2e.py, checks/e2e.sh, or bend. The fixture's main() is not called.

  A  the old call on a real ProgramInfo raises AttributeError on vals.
  B  the new call returns the re-derived bindings, and a buffer param is not one of them.
  C  THE CONTROL: an object that still has vals() writes the same record either way.
     An extra non-variable in kernel_params does not change that record.
"""
import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIX = ROOT / "checks/.e2e-fixture/e2e_mm.py"


def load():
  spec = importlib.util.spec_from_file_location("e2e_mm_fixture", FIX)
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod


class V:
  def __init__(self, expr, variable=True):
    self.expr = expr
    self.is_variable = variable


class Nameless:
  """A buffer param. Measured: name is None, and .expr asserts."""
  is_variable = False

  @property
  def expr(self):
    raise AssertionError("name is None")


class Prg:
  def __init__(self, params):
    self.kernel_params = tuple(params)


class Old:
  """The deleted method, on an object that still has the field."""
  def __init__(self, variables, extra=()):
    self.vars = tuple(variables)
    self.kernel_params = tuple(variables) + tuple(extra)

  def vals(self, var_vals):
    try:
      return tuple(var_vals[k.expr] for k in self.vars)
    except KeyError as e:
      raise RuntimeError(f"unbound Variable {e}") from None


def record(vals):
  return {"names": [], "global": [1, 1, 1], "local": [1, 1, 1], "vals": list(vals)}


def main():
  mod = load()
  from tinygrad.uop.ops import ProgramInfo

  info = ProgramInfo()
  assert not hasattr(info, "vals") and not hasattr(info, "vars")
  assert not hasattr(info, "kernel_params") and hasattr(info, "params")
  try:
    info.vals({})
  except AttributeError as e:
    assert "vals" in str(e), e
  else:
    print("A: old call returned", file=sys.stderr)
    sys.exit(1)

  vv = {"i": 3, "j": 7}
  got = mod.launch_vals(Prg([Nameless(), V("i"), V("buf", False), V("j")]), {**vv, "buf": 9})
  if got != [3, 7]:
    print(f"B: new call returned {got}, not the variable bindings", file=sys.stderr)
    sys.exit(1)
  if mod.launch_vals(Prg([Nameless()]), {}) != []:
    print("B: a buffer-only program is not an empty vals", file=sys.stderr)
    sys.exit(1)
  try:
    mod.launch_vals(Prg([V("missing")]), {})
  except RuntimeError as e:
    assert "unbound Variable" in str(e), e
  else:
    print("B: unbound variable returned", file=sys.stderr)
    sys.exit(1)

  old = Old([V("i"), V("j")])
  if record(old.vals(vv)) != record(mod.launch_vals(old, vv)):
    print("C: control record moved", file=sys.stderr)
    sys.exit(1)
  wider = Old([V("i")], extra=(Nameless(),))
  if record(wider.vals({"i": 3})) != record(mod.launch_vals(wider, {"i": 3})):
    print("C: a non-variable kernel_param changed the record", file=sys.stderr)
    sys.exit(1)

  # A derivation that does not filter is_variable either asserts or changes the record.
  try:
    blind = [vv.get(p.expr) for p in Prg([Nameless(), V("i")]).kernel_params]
  except AssertionError:
    blind = None
  if blind == [3]:
    print("falsification: an unfiltered walk matched the re-derivation", file=sys.stderr)
    sys.exit(1)

  print("A AttributeError on vals")
  print("B re-derived [i, j], buffer excluded, unbound raises")
  print("C control record unchanged")
  print("e2emm-plant=OK")


if __name__ == "__main__":
  main()
