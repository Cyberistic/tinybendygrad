# MY OWN FIX WAS READING ONE FIFTH OF ITS POPULATION: `(?:^|\s)` cannot see a path in backticks

**2026-10-15, HEAD `8680284c8`.** Found while verifying a claim from a dispatched unit, not by looking.

## THE DEFECT IS IN THE FIX I LANDED TWO TURNS AGO

`checks/repro-paths.py`'s `REF` was, until today:

```python
REF = re.compile(r"(?:^|\s)((?:\.agents/slop/|checks/|gates/)[\w./-]*\.[A-Za-z0-9]+)")
```

Removing the SUFFIX SET was the right fix — that part stands, and it is what removed the false DANGLING
and the false RESOLVE. But the **anchor** was never right: `(?:^|\s)` requires the path to begin the
line or follow whitespace, and **markdown writes a path inside BACKTICKS**:

```markdown
    `.agents/slop/coldness/coldness.py` prints the table
       ^ the character before the path is a backtick, not whitespace
```

The same is true of `"…"` in Python source, which is how `checks/rn-gate.py:74` spells it:

```python
ORACLE = [".agents/slop/xd1/render-gate-oracle.py", "--gate"]
```

**MEASURED, same 543 committed reports, same everything else:**

| | named | resolve | dangling |
| --- | ---: | ---: | ---: |
| `REF` as landed | 716 | 608 | 108 |
| anchor widened to `(?<![\w/.])` | **3473** | **3041** | **434** |
| delta | **+2757** | +2433 | +326 |

`3473 / 716 = 4.9×`. **The instrument was seeing about one fifth of its own population**, and every
number it has printed — including the `108` in `DANGLING-TRIAGE.md` — carries that factor.

`LOST by widening: NONE`, so this is a strict superset, not a trade.

## WHY IT MATTERS MORE THAN A MISSED ROW

The one class that was invisible is the class that hurts. `.agents/slop/xd1/render-gate-oracle.py` is
invoked **by literal** from `checks/rn-gate.py:74`; it is **absent from disk**, **absent from HEAD**,
and its whole directory `.agents/slop/xd1/` is gone. **A live gate names an oracle that does not
exist**, and `repro-paths.py` — the instrument whose entire subject is "every path a report names must
exist" — could not see it, because a quote mark stood where a space would have had to be.

That is doctrine 1 one level below the clause I wrote into `AGENTS.md` two turns ago: an instrument
that cannot see its population cannot be wrong, because it cannot be anything. **The suffix set made it
blind by NAME; the anchor makes it blind by CONTEXT, and the second is harder to notice because the
paths it misses are the ones written correctly.**

## NOT LANDED, AND WHY

Widening takes `DANGLING` from **108** to **434**, and `DANGLING-TRIAGE.md` MEASURED that essentially
none of the 108 were a live instrument missing a required input — they are finished units' reports
naming their own pruned tools. The 326 new rows are overwhelmingly the same shape. So landing it alone
buys a five-times-larger pile of the same noise and no new signal, and **prefer refuse to repair**
applies: the population and the CLAIM have to move together, and moving the claim is the redesign
already refused in `DANGLING-TRIAGE.md`.

**THIS IS THE SECOND TIME THIS SESSION THAT A MEASUREMENT I PROUDGED WAS WRONG** — the first was
calling 7 of 15 dangling rows "dangerous" when they were the gate citing its own docstring. Both times
the error was mine, both times the correction made the instrument look WORSE, and both times the
honest report is worth more than the tidy one.

## Reproduce

```
.venv/bin/python - <<'EOF'
import importlib.util, re, pathlib
R = pathlib.Path.cwd()
s = importlib.util.spec_from_file_location("rp", R/"checks/repro-paths.py")
rp = importlib.util.module_from_spec(s); s.loader.exec_module(rp)
WIDE = re.compile(r"(?<![\w/.])((?:\.agents/slop/|checks/|gates/)[\w./-]*\.[A-Za-z0-9]+)")
def scan(rx):
    return {m.group(1) for rel in rp.committed_reports()
            for m in rx.finditer(rp.report_text(rel)) if not rp.PATTERN.search(m.group(1))}
print(len(scan(rp.REF)), len(scan(WIDE)))
EOF
```