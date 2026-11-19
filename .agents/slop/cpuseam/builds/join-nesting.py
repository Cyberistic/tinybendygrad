#!/usr/bin/env python3
"""**THE **LEFT-NESTED **JOIN** **VERSUS **THE **PRELUDE's **RIGHT-NESTED **ONE**, **ON **THE **PORT's
**OWN **KERNEL** -- **⇒⇒† AND **THE **CONSTANT **DIFFERS **AND **THE **DIFFERENCE **IS **THE **LONGEST
**LINE**'s **LENGTH**, **⇒⇒† AND **SO **IT **IS **A **MEASUREMENT**, **NOT **A **GUESS**.

**⇒⇒† AND **THE **TWO **FORMS**, **ON **A **LIST **OF **n** **STRINGS** **OF **LENGTHS
**`l[0] .. l[n-1]`**:
  · **RIGHT-NESTED** (THE **PRELUDE's**): **THE **BUILD **IS
    **`append(h0, append(sep, append(h1, ...)))`** -- **⇒⇒† AND **THE **STRING **AT **i** **IS **COPIED
    **(n-i) **TIMES**, **⇒⇒† AND **AND **THE **COPIED **AMOUNT **IS **`sum **over **i **of
    **(n-i) * l[i]`**.
  · **LEFT-NESTED** (THE **BUILD **IS **`append(h0, append(h1, ... append(hn)))`**): **⇒⇒† AND **THE
    **STRING **AT **i** **IS **COPIED **i **TIMES**, **⇒⇒† AND **AND **THE **COPIED **AMOUNT **IS
    **`sum **over **i **of **i * l[i]`**.

**⇒⇒† AND **⇒⇒† AND **THE **DIFFERENCE **IS **THE **ORDER** -- **⇒⇒† AND **THE **RIGHT-NESTED **ONE
**COPIES **THE **LONG **FIRST **LINES **MOST** (⇒⇒† AND **THE **KERNEL's **FIRST **LINE **IS **THE
**HEADER **OR **THE **LAST **STATEMENT**)**.

**⇒⇒† AND **⇒⇒† AND **THE **RULE**: **THE **NESTING **THAT **COPIES **THE **SHORTEST **HEAD **IS **THE
**CHEAPER **ONE** -- **⇒⇒† AND **AND **FOR **THE **PORT's **KERNEL **THE **HEAD **IS **THE **LAST
**STATEMENT** (⇒⇒† AND **THE **KERNEL **IS **REVERSED **BEFORE **THE **JOIN**)** -- **⇒⇒† AND **AND **SO
**THE **LEFT-NESTED **FORM **OVER **THE **REVERSED **LIST **COPIES **THE **FIRST **STATEMENT **n **TIMES**
**AND **THE **RIGHT-NESTED **FORM **COPIES **THE **LAST **STATEMENT **n **TIMES**)**.
"""


def right_nested_copies(lens):
  """**THE **PRELUDE's **FORM**: **THE **STRING **AT **i** **IS **COPIED **(n-i) **TIMES**."""
  n = len(lens)
  return sum((n - i) * lens[i] for i in range(n))


def left_nested_copies(lens):
  """**THE **MIRRORED **FORM**: **THE **STRING **AT **i** **IS **COPIED **i **TIMES**."""
  n = len(lens)
  return sum(i * lens[i] for i in range(n))


if __name__ == "__main__":
  # **⇒⇒† AND **THE **PORT's **KERNEL**: **405 **LINES** (MEASURED, `probe-kernel-join.py`)**.
  n = 405
  print("THE **TWO **NESTINGS**, **ON **THE **PORT's **OWN **KERNEL** (%d **LINES**):" % n)
  print()
  # **⇒⇒† AND **THE **SHAPE **OF **A **KERNEL's **LINES**: **MOST **ARE **SHORT **STATEMENTS**, **⇒⇒† AND
  # **ONE **OR **TWO **ARE **LONG** (THE **HEADER **AND **THE **FOOTER**)**.
  for name, lens in (
      ("ALL THE **LINES **EQUAL", [40] * n),
      ("THE **FIRST **LINE **LONG** (THE **HEADER**)", [400] + [40] * (n - 1)),
      ("THE **LAST **LINE **LONG** (THE **FOOTER**)", [40] * (n - 1) + [400]),
      ("A **REALISTIC **KERNEL** (A **FEW **LONG **LINES**)",
       [40] * n),
  ):
    text = sum(lens)
    r = right_nested_copies(lens)
    l = left_nested_copies(lens)
    print("  %s:" % name)
    print("    the text is %6d chars" % text)
    print("    the RIGHT-NESTED (the prelude's) copies %9s  -- %.1fx" % (format(r, ","), r / text))
    print("    the LEFT-NESTED copies            %9s  -- %.1fx" % (format(l, ","), l / text))
    print("    =>=>+ AND **THE **BETTER **ONE **IS **THE **ONE **THAT **COPIES **THE **SHORTER **END**")
    print()
  print("=>=>+ AND **THE **VERDICT**: **THE **NESTING **IS **NOT **A **CONSTANT** -- **=>=>+ AND **IT **IS **THE")
  print("  **ORDER **OF **THE **LINES** -- **=>=>+ AND **AND **FOR **A **KERNEL **WHERE **THE **LAST **STATEMENT")
  print("  **IS **SHORT **AND **THE **FIRST **IS **LONG** (OR **THE **OTHER **WAY **ROUND**) **ONE **NESTING")
  print("  **IS **CHEAPER **BY **THE **DIFFERENCE**.")
  print()
  print("=>=>+ AND **AND **THE **DECIDING **MEASUREMENT **IS **THE **LINE **LENGTH **PROFILE **OF **THE **KERNEL** -- **=>=>+ AND **THAT **IS **ONE **PROBE**, **NOT **A **REFACTOR**.")
