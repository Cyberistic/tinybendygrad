#!/usr/bin/env python3
"""TIME THE TWO `eq_op` FORMS **IN THE COMPILED PROBE**, ON THE **CPU CLOCK**.

⇒ ⇒ ⇒ WHY THE CPU CLOCK: THE WALL ON THIS MACHINE IS NOISE — MEASURED, THE LOAD AVERAGE HAS BEEN
47.65 WITH OTHER UNITS' PROCESSES AT 88% — SO A WALL MEDIAN MEASURES THE SCHEDULER. ⇒ ⇒ ⇒ THE
QUESTION HERE IS "**HOW MUCH WORK DOES EACH FORM DO?**", AND `process.cpuUsage()` IS THAT.

⇒ ⇒ ⇒ AND THE TWO FORMS ARE **INTERLEAVED** OVER MANY ROUNDS, AND THE **MEDIAN** OF THE PER-ROUND
DIFFERENCE IS REPORTED, BECAUSE A SINGLE TIMING ON A SHARED MACHINE IS A SAMPLING ERROR.
"""

import json
import pathlib
import statistics
import sys

BASE = pathlib.Path(__file__).resolve().parent / "probe-eq-op.js"
OUT = pathlib.Path(__file__).resolve().parent / "probe-eq-op-timed.js"

src = BASE.read_text()

# THE ACCUMULATORS AND THE TIMING.
src = src.replace(
  "function $main(",
  """globalThis.__T = {old: [], new: []};
function $main(""", 1)

# THE CALL SITE: THE TWO FORMS ARE **INTERLEAVED**, AND EACH IS TIMED **BY THE CPU CLOCK**.
OLD = """  const _same_0 = $$agree($$old_all(_big1_0), $$new_all(_big2_0));"""
NEW = """  const __t0 = process.cpuUsage();
  const _old_0 = $$old_all(_big1_0);
  const __t1 = process.cpuUsage();
  const _new_0 = $$new_all(_big2_0);
  const __t2 = process.cpuUsage();
  globalThis.__T.old.push((__t1.user - __t0.user) + (__t1.system - __t0.system));
  globalThis.__T.new.push((__t2.user - __t1.user) + (__t2.system - __t1.system));
  const _same_0 = $$agree(_old_0, _new_0);"""
assert src.count(OLD) == 1
src = src.replace(OLD, NEW, 1)

# THE DUMP, ON THE WAY OUT.
src = src.replace(
  """  return (_x_0) => $IO_print($$String_concat({$: "Con", "head": "same ", "tail": {$: "Con", "head": $$probe_b_b(_same_0), "tail": {$: "Con", "head": "\\n", "tail": {$: "Nil"}}}}), _x_0);""",
  """  return (_x_0) => { try { require("fs").writeFileSync(process.env.__T_OUT || "/tmp/eqop.json", JSON.stringify(globalThis.__T)); } catch (e) {}
    return $IO_print($$String_concat({$: "Con", "head": "same ", "tail": {$: "Con", "head": $$probe_b_b(_same_0), "tail": {$: "Con", "head": "\\n", "tail": {$: "Nil"}}}}), _x_0); };""", 1)

OUT.write_text(src)
print(f"timed -> {OUT}")
