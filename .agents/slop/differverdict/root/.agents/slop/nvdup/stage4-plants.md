# STAGE 4 — THE PLANT / DISARM MATRIX, INCLUDING PROOF THE SELFTEST CAN FAIL

Two instruments, two matrices.  Every number below was produced by a run in this directory; the
raw output is beside each tool.

## 1. THE MULTIPLICITY MATRIX — `dup-gate.py --selftest`, **imported, not forked**

### 1a. `nir_llvmir`, a BYTE-IDENTICAL pair — the DISARM

```
[selftest base] the REAL captured pair: 205 shared names, 0 duplicate name(s), byte-identical=True
  cell     verdict  dup(port) dup(oracle)  byteIdent disagree
  clean    AGREE            0           0       True        0
  value    BROKEN           0           0      False        1
  name     BROKEN           1           1       True        0
  collide  BROKEN           1           1       True        0
SELFTEST OK                                            REAL rc = 0
```

| cell | injected | expected | measured |
|---|---|---|---|
| **clean** | nothing | **the DISARM**: AGREE, dup 0, byteIdent True | AGREE, 0/0, True, 0 ✅ |
| **value** | one token after the first `=` | caught, byte-identity breaks | BROKEN, 0/0, **False**, **disagree 1** ✅ |
| **name** | one row renamed onto an existing name, **both sides** | dup rises, lanes **still byte-identical** | BROKEN, **1/1**, **True**, **disagree 0** ✅ |
| **collide** | a row renamed onto a name whose value differs | dup rises | BROKEN, 1/1, True, 0 ✅ |

**A NAME plant leaves the two lanes byte-identical; a VALUE plant cannot.**  That is the whole
discriminator and it is the reason a name check that a value plant can turn green is not testing
the name.

### 1b. `ops_nv` — the lane this unit fixed, and **the selftest FAILS on it**

```
[selftest base] the REAL captured pair: 543 shared names, 11 duplicate name(s), byte-identical=False
  clean    BROKEN          11           0      False        0
  value    BROKEN          11           0      False        1
  name     BROKEN          12           1      False        0
[selftest assert] name must raise dup on BOTH sides with the lanes STILL byte-identical: False
SELFTEST FAILED   <<< the pair is NOT byte-identical, so the NAME plant cannot demonstrate the
                   byte-identity claim                                 REAL rc = 1
```

**`REAL rc = 1` IS THE PROOF THE SELFTEST CAN FAIL, and it is on the lane I fixed.**  Read it:
the base is `dup(port) 11 / dup(oracle) 0` — **my fix moved the oracle from 27 to 0 and the
selftest's `clean` cell is still red, on the port's 11.**  A red with no paired disarm proves
nothing about where it landed, and here the disarm says where it is: the PORT.  The tool also
names its own limit in the failure text rather than reporting a green it did not earn.

## 2. THE DEAD-ARM MATRIX — `nvdup-deadarm.py --selftest`, which is NEW and mine

It needed its own matrix because **the defect it guards emits nothing** and so cannot appear in
§1's census at all.  Two censuses, both run, and they see different things:

* **SITE census** — a `row(` line in the SOURCE that a `sys.settrace` line-tracer never saw execute.
* **LINE census** — a name printed more than once in the LANE (this is `dup-gate.py`'s, re-run
  here because the matrix needs it, and because one cell shows the two disagree).

```
[selftest] DISARM first: the UNPLANTED real file.  A control whose base is typed 0 is a control
           that cannot fire, so the base is measured and printed with the cells.
  clean      distinct row() LINES in source=337   CALLS executed=547   DEAD SITES=0   lane rows=547   DUPLICATE NAMES=0
  dead       distinct row() LINES in source=339   CALLS executed=548   DEAD SITES=1   lane rows=548   DUPLICATE NAMES=0
      DEAD SITE  line 1206   a row() that exists in the source and NEVER EXECUTES
  live       distinct row() LINES in source=338   CALLS executed=548   DEAD SITES=0   lane rows=548   DUPLICATE NAMES=0
  dup        distinct row() LINES in source=338   CALLS executed=548   DEAD SITES=0   lane rows=548   DUPLICATE NAMES=1
  longhand   distinct row() LINES in source=337   CALLS executed=547   DEAD SITES=0   lane rows=548   DUPLICATE NAMES=1

  [PASS] DISARM: the unplanted real file has NO dead site (0): True
  [PASS] DEAD: a row() in an unreachable try-arm IS seen (0 -> 1): True
  [PASS] LIVE: a row() that DOES execute is not called dead (0): True
  [PASS] DUP: a duplicate is NOT a dead site -- site census stays 0, LINE census rises to 1: True
  [PASS] LONGHAND: a duplicate that BYPASSES row() escapes the site census and the LINE census
         catches it -- the two censuses are not substitutes: True
DEADARM SELFTEST OK                                        REAL rc = 0
```

| cell | injected | expected | measured |
|---|---|---|---|
| **clean** | nothing | **the DISARM**: 0 dead, 0 dup | 0 dead, 0 dup ✅ |
| **dead** | `try: 1/0; row(dead) except: row(live)` | site census 0 → **1**, line census stays 0 | DEAD 1, DUP 0 ✅ |
| **live** | one top-level `row()` | site census stays **0** | DEAD 0 ✅ |
| **dup** | `row("nv_reloc_kind_n", 3)` — executes | site census stays **0**, line census 0 → **1** | DEAD 0, DUP 1 ✅ |
| **longhand** | `ROWS.append(("nv_reloc_kind_n","3"))` — bypasses `row()` | site census stays **0** (the selector is `^\s*row\(`), line census 0 → **1** | DEAD 0, DUP 1 ✅ |

**The `dup` and `longhand` cells are the load-bearing pair.**  They say a duplicate is **not** a
dead site and a row emitted without `row()` is invisible to the site census, so **neither census
substitutes for the other** — and the `longhand` cell exists so that limit is a printed number
and not a surprise.

## 3. PROOF THE DEAD-ARM SELFTEST CAN FAIL — run against the PRE-FIX file

```
$ .venv/bin/python .agents/slop/nvdup/nvdup-deadarm.py --file .agents/slop/nvdup/nv-oracle-PREFIX.py --selftest
  clean      distinct row() LINES in source=351   CALLS executed=574   DEAD SITES=4   lane rows=574   DUPLICATE NAMES=27
  [FAIL] DISARM: the unplanted real file has NO dead site (0): False
  [FAIL] DEAD:   a row() in an unreachable try-arm IS seen (0 -> 1): False
  [PASS] LIVE:   a row() that DOES execute is not called dead (0): True
  [FAIL] DUP:    a duplicate is NOT a dead site …: False
  [FAIL] LONGHAND: a duplicate that BYPASSES row() …: False
DEADARM SELFTEST FAILED                                       REAL rc = 1
```

**4 of 5 assertions go red against the pre-fix file and 5 of 5 pass against the fixed one, from
the same code.**  The DISARM assertion firing is what makes the green run mean anything: a
control whose base is hardcoded 0 cannot prove that it would have fired, and three controls on
this project were found disarmed, one leaving six lanes green.

**The census, before and after, on the same instrument:**

| file | `sha256` | dead sites | duplicate names | lane rows |
|---|---|---|---|---|
| `.agents/slop/nvdup/nv-oracle-PREFIX.py` (pre-fix) | `995767bf35fb0717` | **4** | 27 | 574 |
| `.agents/slop/nv-oracle.py` (live) | `6ce19734cb5a865b` | **0** | 0 | 547 |

and the four, verified against the file by line number rather than trusted from the tool:

```
:1139      row("nv_smemcfg_too_big", "False")
:1146      row("nv_smemcfg_msg_big", "")
:1154          row("nv_reloc_msg_%d" % _t, "")
:1159      row("nv_reloc_bad_refused", "False")
```

## 4. THREE MORE THINGS THAT FAILED, EACH PRODUCING A PLAUSIBLE WRONG ANSWER

Recorded because they are the same species as the defects, and because a harness that has never
been observed failing has not been tested.

1. **`wrap row()` by assignment does not work, and fails as `0`.**  The first
   `nvdup-trace.py` replaced `g["row"]` with a recording wrapper and re-`exec`'d the source —
   and `nv-oracle.py:29`'s own `def row` **reclaims the name on every exec**, so the run
   attributed **`0` calls against 574 printed lines**.  The assert on that line is what caught it.
   `sys.settrace` observes from outside and has no such problem.
2. **THE DEAD-ARM SELFTEST COULD NOT RUN AT ALL ON ITS FIRST ATTEMPT.**  The plant anchor carries
   the `if __name__ == "__main__":` line, so *appending* the plant to it dropped the plant INSIDE
   that block and the file's real body landed at the wrong indent:
   `IndentationError: expected an indented block after 'if'`.  A control that cannot run is not a
   control, and this one was broken for a reason with nothing to do with the defect it detects.
   The fix inserts **before** the anchor, and the reason is a comment at the call site.
3. **MY OWN FIXER NEARLY WROTE A BROKEN ORACLE.**  Deleting `nv_smemcfg_msg_big`'s dead arm left
   `try:` with only an `except:`.  `nvdup-fix-nv.py:run()` raises `SystemExit` on a non-zero
   oracle exit, so the `IndentationError` was reported and **nothing was written** — the census
   still read 27 afterwards.  Recorded because the shape — right about the intent, wrong about
   the text — is what `agent-core.md`'s hand-typed `py=` table is made of.

## 5. WHAT THE MATRIX CANNOT SHOW, SAID PLAINLY

* **§1's NAME cell is unavailable on `ops_nv`** because the two sides' bytes differ.  The
  byte-identity claim is carried by `nir_llvmir` alone, and `dup-gate.py` says so in its own
  failure text rather than reporting a green.
* **`disagree=[]` on `ops_nv` is a REAL measurement**, because the two sides' bytes differ
  (`f9b565af…` port vs `92c9e3a8…` oracle) — stated before the result, not after.
* **`nvdup-deadarm.py`'s site selector is textual** (`^\s*row\(`).  A row emitted through any
  other path is invisible to it, which is what the `longhand` cell measures.  It is a
  **source-level** census; `dup-gate.py` is a **lane-level** one; neither is sufficient alone.
* **The matrices were run under load** (six units live; `rebase-gate.py` reported
  `helpers.bend` moving under `ops_nv`'s run).  The dead-arm census reads the source tree and the
  oracle's own execution, so concurrent `.bend` edits cannot move it — but the `ops_nv` PORT lane
  capture could have been starved and was retried `0` times, with closure size printed.