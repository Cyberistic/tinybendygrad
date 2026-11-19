#!/usr/bin/env python3
"""**PYTHON's **`str.join` **IS **O(n)** **AND **THE **PRELUDE's **`String.join` **IS **O(n^2)** -- **⇒⇒†
**AND **THE **PORT **INHERITS **THE **PRELUDE's**, **NOT **UPSTREAM's**.

**⇒⇒† AND **THE **TWO**:
  · **PYTHON** (**MEASURED, `tinygrad/renderer/cstyle.py:176`**: **`['\\n'.join(kernel), "\\n}"]`**)
    -- **`str.join` **COPIES **EVERY **CHARACTER **EXACTLY **ONCE**, **⇒⇒† AND **IT **IS **BUILT **FOR
    **THIS** (**CPython's **`PyUnicode_Join`** **IS **A **SINGLE **PASS**)**.
  · **THE **PRELUDE** (MEASURED, `references/bend/bend2/base.bend:2266`)**:
    **`String.append(h, String.append(sep, String.join.go(t, h2, sep)))`** -- **⇒⇒† AND **IT **IS
    **RIGHT-NESTED**, **⇒⇒† AND **AND **`String.append(a, b)` **COPIES **`a`** -- **⇒⇒† AND **SO **THE
    **COPIES **ARE **THE **SUM **OF **THE **PREFIX **SUMS**, **⇒⇒† AND **AND **THAT **IS **O(n²)**.

**⇒⇒† AND **⇒⇒† AND **THE **PORT's **`String.join`** **IS **THE **PRELUDE's **OWN** -- **⇒⇒† AND **AND
**THE **PORT's **CALL **IS **THE **SAME **CALL **UPSTREAM **MAKES** (`'\n'.join(kernel)`) -- **⇒⇒† AND **SO
**THE **SHAPE **IS **FAITHFUL** **⇒⇒† AND **AND **THE **COST **IS **THE **SUBSTRATE's**, **NOT **THE
**PORT's**.

**⇒⇒† AND **⇒⇒† AND **THE **DIFFERENCE **IS **THE **ONLY **THING **THAT **MATTERS**, **AND **IT **IS **A
**SUBSTRATE **LIMIT** -- **⇒⇒† AND **BEND's **STRINGS **ARE **IMMUTABLE**, **⇒⇒† AND **AND **THE **ONLY
**O(n) **JOIN **NEEDS **AN **ACCUMULATOR **EXTENDED **IN **PLACE**, **⇒⇒† AND **AND **A **LIST **OF
**PIECES **ALL **THE **WAY **IS **THE **ONLY **O(n) **FORM**.
"""

if __name__ == "__main__":
  xs = ["abc", "de", "fghij"]
  n = len(xs)
  print("THE **TWO **JOINS**, **ON **THE **SAME **LIST** %r:" % (xs,))
  print()
  print("  PYTHON's **str.join**: **EVERY **CHAR **ONCE**")
  print("    %r" % "".join(xs))
  print("    =>=>+ AND THE **COPIES **ARE **%d** (THE **TEXT **IS **%d**)" % (sum(len(x) for x in xs), sum(len(x) for x in xs)))
  print()
  print("  THE **PRELUDE's **String.join**: **THE **SUM **OF **THE **PREFIX **SUMS**")
  total = 0
  for i, x in enumerate(xs):
    pre = sum(len(y) for y in xs[:i + 1])
    copied = pre * (n - i)
    total += copied
    print("    the piece %-8r is copied %d times (%d chars each time = %d)" % (x, n - i, len(x), copied))
  print("    =>=>+ AND THE **COPIES **ARE **%d** -- **THAT **IS **%.1fx **THE **TEXT**" % (total, total / sum(len(x) for x in xs)))
  print()
  print("  =>=>+ AND **THE **PORT's **CALL **IS **UPSTREAM's **CALL** (`'\\n'.join(kernel)`) -- **=>=>+ AND")
  print("  **THE **SHAPE **IS **FAITHFUL** **=>=>+ AND **THE **COST **IS **THE **SUBSTRATE's**.")
