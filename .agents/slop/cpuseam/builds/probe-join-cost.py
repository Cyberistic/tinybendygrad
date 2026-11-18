#!/usr/bin/env python3
"""**THE **STRING **JOIN's **COPY **COUNT**, **PER **STATEMENT**, **FROM **THE **PORT's **OWN
**SHAPE** -- **⇒⇒† AND **THE **COST **IS **THE **NESTING**, **AND **THE **PRELUDE's **STRINGS **ARE
**IMMUTABLE**, **⇒⇒† AND **SO **THIS **IS **A **LANGUAGE **LIMIT** -- **⇒⇒† AND **THE **RENDER's
**BIGGEST **TERM **IS **THE **TEXT **ASSEMBLY** (§138.9)**.

**⇒⇒† AND **THE **PRECEDENT'S **FORM**: **THE **RENDERED **TEXT **OF **A **UOP **IS **A **LIST **OF
**PIECES**, **NOT **A **STRING** (MEASURED, `PARITY.md` §93: **THE **RENDERER **FED **77,500
**CHARACTERS **TO **`String.concat` **TO **EMIT **4,426** -- **A **17.5x **AMPLIFICATION** -- **BECAUSE
**EVERY **EXPRESSION **MATERIALISED **ITS **TEXT **AND **EVERY **PARENT **COPIED **IT **AGAIN**).

**⇒⇒† AND **THE **PRELUDE's **TWO **FUNCTIONS** (MEASURED, `references/bend/bend2/base.bend`):
```
def String.append(a: String, b: String) -> String:      # COPIES `a`, PUTS `b` AT THE END
  match a:
    case SNil{}: b
    case SCon{h, t}: SCon{h, String.append(t, b)}

def String.join.go(xs: List<&2, String>, h: String, +sep: String) -> String:   # RIGHT-NESTED
  match xs:
    case Nil{}: h
    case h2 <> t: String.append(h, String.append(sep, String.join.go(t, h2, sep)))

def String.concat(xs: List<&2, String>) -> String:        # RIGHT-NESTED
  match xs:
    case Nil{}: SNil{}
    case h <> t: String.append(h, String.concat(t))
```

**⇒⇒† AND **THE **ARITHMETIC**: **A **STATEMENT **WITH **`n` **PIECES **OF **`l` **CHARS **EACH**:
  · **`String.join(xs, "")`** **COPIES **`l * n * (n+1) / 2`** **CHARS** -- **⇒⇒† AND **THAT **IS
    **O(n²)**, **⇒⇒† AND **IT **IS **THE **PRELUDE's **RIGHT-NESTING**: **`h1` **IS **COPIED **`n`**
    **TIMES**, **`h2` **`n-1`**, **AND **SO **ON**.
  · **`String.concat([indent, joined, ";"])`** **COPIES **THE **WHOLE **JOINED **LINE **ONCE **MORE**.
  · **⇒⇒† AND **THE **TOTAL **IS **`l * n * (n+1) / 2` **PLUS **THE **LINE**, **⇒⇒† AND **SO **THE
    **AMPLIFICATION **IS **`n/2 + 1`**.

**⇒⇒† AND **AND **THE **ONLY **O(n) **FORM **NEEDS **A **MUTABLE **STRING**, **⇒⇒† AND **BEND's
**STRINGS **ARE **IMMUTABLE** -- **⇒⇒† AND **SO **THE **PORT's **ANSWER **MUST **BE **A **DIFFERENT
**DATA **SHAPE**, **NOT **A **DIFFERENT **JOIN** -- **⇒⇒† AND **THAT **IS **WHAT **THE **PIECES **ARE**:
**THE **STATEMENT's **TEXT **IS **ALREADY **A **LIST **OF **PIECES** **AND **THE **JOIN **IS **THE **ONLY
**PLACE **IT **BECOMES **A **STRING**.

**⇒⇒† AND **⇒⇒† AND **THERE **IS **A **SECOND **MULTIPLIER**: **`_render.decl`** **AND
**`_render.plain`** **BOTH **DO **`String.concat([... , String.join(l, ""), ...])`** -- **⇒⇒† AND **THE
**JOINED **STRING **IS **THEN **COPIED **INTO **THE **CONCAT** -- **⇒⇒† AND **SO **THE **STATEMENT's
**TEXT **IS **COPIED **AT **LEAST **TWICE **BEFORE **IT **IS **EVEN **STORED**.
"""

import sys

# **THE **PORT's **OWN **STATEMENT **FORMS** -- **THE **TEXT **IS **COPIED **TWICE**.
def copies(n_pieces: int, chars_per_piece: int = 6) -> int:
  """**THE **CHARACTERS **COPIED **TO **BUILD **ONE **STATEMENT**."""
  join = chars_per_piece * n_pieces * (n_pieces + 1) // 2
  line = chars_per_piece * n_pieces
  concat = line                       # **THE **JOINED **STRING **IS **COPIED **INTO **THE **CONCAT**
  return join + concat


if __name__ == "__main__":
  print("THE **STRING **COPY **COST **PER **STATEMENT**, **FROM **THE **PORT's **OWN **SHAPE**:")
  print(f"{'PIECES':>7} {'LINE':>6} {'COPIED':>8} {'AMPLIFICATION':>14}")
  for n in (2, 3, 4, 5, 6, 8, 10, 12, 16):
    line = n * 6
    c = copies(n)
    print(f"{n:7d} {line:6d} {c:8d} {c/line:13.1f}x")
  print()
  print("=>=>+ AND **THE **AMPLIFICATION **GROWS **WITH **THE **PIECE **COUNT**, **=>=>+ AND **AND **THE **STATEMENT's **TEXT **IS **COPIED **AT **LEAST **TWICE**: **ONCE **BY **THE **JOIN **AND **ONCE **BY **THE **CONCAT**.")
  print()
  print("=>=>+ AND **THE **PORT's **OWN **15 **`String.join` **CALL **SITES** -- **=>=>+ AND **THE **HOTTEST **ARE **`_render.plain` **AND **`_render.decl`**, **=>=>+ AND **AND **`rt`** (THE **ROW's **TEXT**) **IS **THE **THIRD**.")
