#!/usr/bin/env python3
"""realize_kernel_args-gate.py -- THE PIN's `get_call_kernel_args` AGAINST THE PORT's.

    .venv/bin/python gates/realize_kernel_args-gate.py

NINETEEN ROWS, THREE LANES (THE ORACLE, THE PORT'S INTERPRETED DRIVER, AND THE PORT'S
COMPILED DRIVER), ZERO DECLARED DIVERGENCES.

**WHY THIS GATE EXISTS AT ALL.** THE BIG CENSUS (`gates/realize_graph_census-gate.py`)
HAS A `var` DRIVER, AND AFTER THE MIGRATION FROM THE DELETED `get_call_var_uops` TO THE
PIN's `get_call_kernel_args` THAT DRIVER **CANNOT COMPARE**: MEASURED, THE PIN's
`get_call_kernel_args` READS `s.is_bound_var` OVER `call.src[1:]`, AND `ops.py:1011`'s
`is_variable` READS `self._shape`, WHICH FOR A PARAM IS `self.src[0].as_shape` -- SO A
PARAM WITH NO `src` RAISES IndexError. THE BIG CENSUS's FIXTURE MIRRORS THE PORT's
`main_arena`, WHOSE PARAMS HAVE NO `src`, SO 21 OF ITS 23 `var_*` ROWS ARE
`raise=IndexError` ON THE CPython SIDE. **A DRIVER THAT CANNOT COMPARE IS A DRIVER
THAT MEASURED NOTHING, AND THE ANSWER IS NOT TO DROP THE ROWS: IT IS TO GIVE THE
FUNCTION A FIXTURE IT CAN ANSWER ON.** THIS GATE IS THAT FIXTURE -- THE PORT's OWN
`plants_arena`, WHOSE PARAMS ARE BUILT BY `UOp.param` (WHICH ALWAYS GIVES A PARAM A
SRC) AND WHOSE PROGRAMs HAVE THE PIN's COMPILED SHAPE `src=(sink, linear)` (BECAUSE THE
PIN's `UOp.kernel_params` READS `self.src[1].src`).

**WHERE IT CAME FROM.** THE PORT UNIT'S OWN UNTRACKED INSTRUMENT,
`.agents/slop/realizepin/plants-oracle.py`, MOVED INTO GIT BESIDE THIS GATE AS
`gates/realize_kernel_args-oracle.py` AND REWRITTEN TO PRINT THE PORT's ROW SPELLING.
`.agents/slop/` IS THE DIRECTORY THIS TREE IS PRUNING, AND THE TREE HAS ALREADY LOST AN
INSTRUMENT THAT WAY (`worker_oracle.py`, RECOVERED FROM A BLOB). **A GATE'S REQUIRED
INPUT BELONGS BESIDE THE GATE IN GIT -- AND NOT IN `gates/artifacts/`, WHICH IS
`.gitignore`d AND WHERE GATE RUNS WRITE, SO ONE `rm -rf gates/artifacts` DELETES
ANYTHING KEPT THERE AND GIT CANNOT RESTORE IT.**

**THE DEVICE IS THE ONE THING THESE ROWS CANNOT SEE, AND IT IS CHECKED INSTEAD.** THE
PIN TAKES A DEVICE **TUPLE** (`devs`) AND THE PORT TAKES ONE `S.Dev`; THE BRIDGE IS THE
CALL's OWN DEVICE (`tinygrad/engine/realize.py:41`'s `get_call_kernels` READS IT FROM
`to_tuple(call.src[1].device)`), AND EVERY PLANT HERE IS ON "CPU". NEITHER LANE PRINTS
THE DEVICE, SO `device_holds()` READS BOTH SIDES' SOURCE AND HOLDS THAT THEY AGREE:
THE ORACLE PASSES `("CPU",)` AND THE PORT PASSES `cpu_dev()`, AND THE PLANT FIXTURE's
OWN BUFFERS ARE ON THE SAME DEVICE. THE DEVICE IS COMPARED WHERE IT IS COMPARABLE AT
ALL -- THE BIG CENSUS's `var` DRIVER, OVER THE TWO-DEVICE BUFFER, WHERE THE DEVICE's
COUNT IS IN THE GETADDR's PAYLOAD.
"""

import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))

from gatekit import Gate, gate  # noqa: E402

# THE NINETEEN ROWS, IN THE DRIVER's OWN ORDER. `gatekit` refuses the run if a lane
# disagrees with this count, so the count is a MEASUREMENT of the lanes and not a typed
# inventory.
ROWS = ("ka_none_len", "ka_none_addr", "ka_zero_len", "ka_zero_cast",
        "ka_unb_len", "ka_unb_param", "ka_unb_slotless", "ka_unb_arglen",
        "ka_af_len", "ka_af_p0", "ka_af_a1", "ka_af_slotless",
        "ka_bf_len", "ka_bf_a0", "ka_bf_p1", "ka_bf_slotless",
        "ka_sh_len", "ka_sh_cast", "ka_sh_a0")

# ZERO DECLARED DIVERGENCES. Every row is a COMPARED row, and this gate was written
# AFTER the port of the function, so a divergence here would be the gate disagreeing
# with CPython rather than a known gap being pinned. THE DEVICE IS NOT COMPARED HERE
# AND THAT IS STATED IN THE HEADER, NOT HIDDEN.
DIVERGING = ()

PORT = ROOT / "tinybendygrad" / "engine" / "realize.bend"
ORACLE = HERE / "realize_kernel_args-oracle.py"

GATE = Gate(
  "realize_kernel_args-gate",
  bend="realize_kernel_args.bend",
  oracle="realize_kernel_args-oracle.py",
  rows=len(ROWS),
  compared=len(ROWS) - len(DIVERGING),
  diverges={},
  pins=[(lane, r) for lane in ("py", "bd", "bn") for r in ROWS],
)


def _def_body(src: str, name: str) -> str | None:
  """A DEF's BODY: THE LINES AFTER ITS `def` LINE, UP TO THE NEXT `def` OR A BLANK LINE
  FOLLOWED BY A COMMENT. A REGEX OVER THE WHOLE FILE MATCHES THE `def` LINE TOO, AND A
  SIGNATURE IS NOT A CALL SITE."""
  m = re.search(r"^def %s\(" % re.escape(name), src, re.M)
  if m is None:
    return None
  out = []
  for ln in src[m.end():].split("\n")[1:]:
    if ln.startswith("def ") or ln.startswith("#"):
      break
    out.append(ln)
  return "\n".join(out)


def device_holds(census: Path | None = None) -> bool:
  """THE DEVICE BOTH LANES PASS, HELD AGAINST BOTH LANES' OWN SOURCE.

  THE PIN TAKES A DEVICE TUPLE AND THE PORT TAKES ONE `S.Dev`, AND NEITHER LANE PRINTS
  THE DEVICE -- SO A CALL THAT COMPILED AND PASSED THE WRONG DEVICE WOULD BE INVISIBLE
  HERE. **SO THE CLAIM IS MADE ABOUT THE SOURCE INSTEAD OF ABOUT A ROW**, AND IT IS
  THREE CLAIMS: THE ORACLE PASSES A ONE-DEVICE TUPLE, THE PORT PASSES ITS OWN
  `cpu_dev()`, AND THE PLANT FIXTURE's BUFFERS ARE ON THE SAME DEVICE.

  `device.bend:757`'s `dev_name` IS NOT A WAY TO COMPARE THE DEVICE: IT IS THE OTHER
  TABLE, AND IT DISAGREES WITH `device.bend:344`'s `tag_of` -- `tag_of("CPU")` IS 0 AND
  `dev_name(0)` IS THE EMPTY STRING, WHILE `dev_name(6)` IS "CL" AND `tag_of("DISK")` IS
  6. **THE PORT HAS NO DEVICE NAME TO PRINT FOR `S.D1{0}`, AND THE COUNT IS WHAT THE
  BIG CENSUS COMPARES.**
  """
  ok = True
  port = PORT.read_text()
  oracle = ORACLE.read_text()

  m = re.search(r'^DEVS = (\([^)]*\))', oracle, re.M)
  if m is None or m.group(1) != '("CPU",)':
    print(f"  device_holds: the oracle's DEVS is {m.group(1) if m else None!r}, not "
          "('CPU',) -- the device the two lanes pass is not the one this gate holds")
    ok = False

  # THE PORT's CALL SITE, AND IT IS ONE DEF'S BODY AND NOT THE DEF'S OWN SIGNATURE:
  # `realize.bend`'s `ka_of` CALLS `get_call_kernel_args(ar, c, rz_body(ar, c),
  # cpu_dev())`. A REGEX OVER THE WHOLE FILE ALSO MATCHES THE `def` LINE, WHICH IS A
  # SIGNATURE AND NOT A CALL, AND A CHECK THAT FIRES ON A SIGNATURE IS A CHECK THAT
  # FIRES ON THE DECLARATION OF THE FUNCTION IT IS ABOUT.
  body = _def_body(port, "ka_of")
  if body is None:
    print("  device_holds: `ka_of` is not a def in realize.bend, so the port's call to "
          "`get_call_kernel_args` cannot be read")
    return False
  if "cpu_dev()" not in body:
    print("  device_holds: `ka_of` does not pass `cpu_dev()` -- the device the pin's "
          "callers pass is not the one the port passes")
    ok = False

  # **AND THE CENSUS's OWN CALL SITE, WHICH IS WHERE THE WRONG-DEVICE PLANT LIVES.**
  # `gates/realize_graph_census.bend`'s `rs_d_var` CALLS `get_call_kernel_args` WITH THE
  # CALL's OWN DEVICE (`rs_call_dev(a, n)`), AND NOT A CONSTANT: THE FIXTURE HAS A
  # TWO-DEVICE BUFFER (`rs_x64`/`rs_x65`), SO A CONSTANT WOULD PASS THE WRONG DEVICE ON
  # THAT ROW. **THE DEVICE IS IN NO NODE SHAPE, SO THE ONLY WAY A WRONG DEVICE IS
  # VISIBLE IS THE GETADDR's PAYLOAD, WHICH CARRIES THE DEVICE's COUNT -- AND THAT IS
  # WHY THE COUNT IS PRINTED.** A CONSTANT HERE IS A COMPILE-TIME-OK CALL THAT PASSES
  # THE WRONG DEVICE, WHICH IS THE WORSE OF THE TWO FAILURES.
  census = HERE / "realize_graph_census.bend" if census is None else census
  if census.is_file():
    cbody = _def_body(census.read_text(), "rs_d_var")
    if cbody is None:
      print("  device_holds: `rs_d_var` is not a def in the census driver, so the "
            "census's device call cannot be read")
      ok = False
    elif "rs_call_dev" not in cbody:
      print("  device_holds: the census's `rs_d_var` does not pass `rs_call_dev(a, n)` "
            "-- it passes a CONSTANT device, and the fixture has a TWO-DEVICE buffer")
      ok = False
  else:
    print("  device_holds: the census driver is not there, so its device call cannot be "
          "read")
    ok = False

  # THE PLANT FIXTURE's OWN BUFFERS ARE ON THE SAME DEVICE: `_buf` BUILDS THEM WITH
  # "CPU", AND `cpu_dev()` IS `S.D1{0}` -- THE PORT's TAG FOR EVERY DEVICE THAT IS NOT
  # DISK, NPY OR PYTHON (`device.bend:344`'s `tag_of`).
  if '"CPU"' not in oracle:
    print("  device_holds: the oracle's plant fixture does not build its buffers on "
          "'CPU'")
    ok = False
  if not re.search(r"^def cpu_dev\(\) -> S\.Dev:\n  S\.D1\{0\}", port, re.M):
    print("  device_holds: the port's cpu_dev() is not `S.D1{0}`")
    ok = False
  return ok


def main() -> int:
  return gate(
    GATE,
    f"realize_kernel_args-gate: {len(ROWS)} rows compared exactly on the port's own "
    "plant fixture -- the pin's `get_call_kernel_args` (realize.py:17, the function "
    "that REPLACED the deleted `get_call_var_uops`) against the port's port of it, with "
    "the slotless var read, the bound-value CONST, the `.ccast(p.dtype)` and the buffer "
    "arm's `getaddr` all measured; the DEVICE is held against both lanes' source and "
    "is not in these rows, and that is stated rather than hidden",
    checks=lambda: device_holds(),
  )


if __name__ == "__main__":
  sys.exit(main())
