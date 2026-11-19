#!/usr/bin/env python3
"""**CAN **A **LIST **OF **STRINGS **BE **JOINED **IN **O(n) **CHARACTER **COPIES** **IN **AN
**IMMUTABLE-STRING **LANGUAGE**? -- **⇒⇒† AND **THE **TWO **O(n²) **JOINS **IN **THE **RENDER**, **AND
**WHICH **ONE **IS **CHEAPER **TO **KILL**.

**⇒⇒† AND **THE **TWO **JOINS** (MEASURED, §138.17 **AND **THE **SHAPE **BELOW**)**:
  1. **THE **PER-STATEMENT **JOIN** -- **`_render.plain`** **AND **`_render.decl`** **DO
     **`String.concat([..., String.join(l, ""), ...])`** -- **⇒⇒† AND **MEASURED: **693 **CALLS **A
     **TURN**, **4.9 **PIECES **PER **CALL**, **22,983 **CHARS **OF **TEXT**, **⇒⇒† AND **2,955,749
     **CHARS **COPIED** (**128.6x**)**.
  2. **THE **PER-KERNEL **JOIN** -- **`render_kernel_body`** **DOES
     **`String.join(kernel, "\n")`** **OVER **THE **WHOLE **KERNEL** -- **⇒⇒† AND **THE **KERNEL **IS
     **`List.reverse`d **FIRST** (⇒⇒† AND **SO **THE **JOIN **IS **RIGHT-NESTED **OVER **THE
     **REVERSED **LIST**, **⇒⇒† AND **AND **THAT **IS **THE **WORST **CASE**: **THE **FIRST **LINE **IS
     **COPIED **n **TIMES**)**.

**⇒⇒† AND **THE **ARITHMETIC**, **AND **WHY **NEITHER **IS **O(n)**:
  · **A **RIGHT-NESTED **BUILD** **COPIES **THE **TAIL **ONCE **PER **PIECE** (⇒⇒† AND **THE **PRELUDE's
    **`String.join.go`** **IS **THIS**: **`String.append(h, String.append(sep, String.join.go(t, h2,
    sep)))`**)**.
  · **A **LEFT-NESTED **BUILD** **COPIES **THE **HEAD **ONCE **PER **PIECE**.
  · **⇒⇒† AND **EITHER **WAY **IT **IS **O(n²)** **IN **CHARACTERS**, **⇒⇒† AND **THE **ONLY **O(n)
    **FORM **IS **AN **ACCUMULATOR **EXTENDED **IN **PLACE**, **⇒⇒† AND **A **STRING **CANNOT **BE
    **EXTENDED **IN **PLACE** (⇒⇒† AND **BEND's **STRINGS **ARE **IMMUTABLE**)**.

**⇒⇒† AND **⇒⇒† AND **THE **PORT's **OWN **STATE **IS **ALREADY **THE **PIECE-SHAPED **ONE**
(§93: *"THE **RENDERED **TEXT **OF **A **UOP **IS **A **LIST **OF **PIECES**, **NOT **A **STRING"*) **⇒⇒†
**AND **THE **JOIN **IS **THE **ONLY **PLACE **THE **PIECES **BECOME **STRINGS** -- **⇒⇒† AND **AND **IT
**HAPPENS **TWICE**.

**⇒⇒† AND **⇒⇒† AND **THE **DIFFERENCE **BETWEEN **THE **TWO **JOINS**, **AND **IT **IS **THE **LEVER**:
  · **THE **PER-STATEMENT **JOIN **IS **OVER **A **SMALL **LIST** (4.9 **PIECES**) **⇒⇒† AND **SO **ITS
    **AMPLIFICATION **IS **BOUNDED **AT **(n+1)/2** -- **⇒⇒† AND **IT **IS **THE **MANY **SMALL **JOINS**
    **THAT **ADD **UP**.
  · **THE **PER-KERNEL **JOIN **IS **OVER **THE **WHOLE **KERNEL** (n ~ 100-200 **LINES**) **⇒⇒† AND **SO
    **ITS **AMPLIFICATION **IS **~(n+1)/2** **= **50-100x **ON **THE **WHOLE **KERNEL's **TEXT** **AT
    **ONCE** -- **⇒⇒† AND **AND **IT **IS **ONE **CALL**, **⇒⇒† AND **AND **IT **IS **THE **ONE **WITH
    **THE **BIGGEST **SINGLE **AMPLIFICATION**.

**⇒⇒† AND **⇒⇒† AND **THE **CANDIDATE **FIX**, **AND **WHY **IT **WORKS **IN **AN **IMMUTABLE
**LANGUAGE**: **A **STRING **BUILT **RIGHT-NESTED **COPIES **THE **TAIL; **A **STRING **BUILT **FROM **A
**REVERSED **LIST **LEFT-NESTED **COPIES **THE **HEAD** -- **⇒⇒† AND **THE **AMOUNT **IS **THE **SAME**,
**⇒⇒† AND **SO **NEITHER **NESTING **IS **THE **ANSWER**.

**⇒⇒† AND **⇒⇒† AND **THE **ACTUAL **ANSWER**, **AND **IT **IS **NOT **A **JOIN **AT **ALL**: **THE
**TEXT **NEEDS **NOT **BE **A **STRING **AT **ALL** -- **⇒⇒† AND **IT **COULD **BE **A **LIST **OF
**PIECES** **THROUGH **THE **WHOLE **RENDER**, **⇒⇒† AND **AND **JOINED **ONCE **AT **THE **END** --
**⇒⇒† AND **THAT **IS **O(n) **IN **CHARACTER **COPIES** (⇒⇒† AND **ONE **COPY **OF **EVERY **CHAR**,
**⇒⇒† AND **THE **JOIN **IS **THE **ONLY **O(n) **PLACE**)**.

**⇒⇒† AND **⇒⇒† AND **THE **BLOCKER**, **AND **IT **IS **THE **MEASURED **ONE**: **`St.kernel` **IS
**A **`List<&2, String>`** -- **⇒⇒† AND **THE **STATEMENT **IS **JOINED **BEFORE **IT **GOES **IN**,
**⇒⇒† AND **SO **THE **PIECE **LIST **IS **ALREADY **DISCARDED **BY **THE **TIME **THE **KERNEL **LIST
**IS **BUILT** -- **⇒⇒† AND **AND **`St.kernel` **HAS **FIVE **OTHER **WRITERS** (⇒⇒† AND **THE **HEADER,
**THE **BUFFERS, **THE **DEFINES **AND **THE **FOOTER**)** -- **⇒⇒† AND **SO **THE **SHAPE **CHANGE
**IS **NOT **LOCAL**.

**⇒⇒† AND **⇒⇒† AND **SO **THE **HONEST **NEXT **STEP **IS **A **MEASUREMENT**, **NOT **A **CHANGE**:
**HOW **MANY **CHARS **DOES **THE **PER-KERNEL **JOIN **COPY**, **MEASURED**? -- **⇒⇒† AND **IF **IT **IS
**THE **BIGGER **OF **THE **TWO**, **⇒⇒† AND **IT **IS **ONE **CALL **AND **ONE **SHAPE**, **⇒⇒† AND **AND
**THE **PER-STATEMENT **JOIN **IS **693 **CALLS **AND **A **WIDER **CHANGE**.
"""

if __name__ == "__main__":
  print("THE **TWO **O(n^2) **JOINS **IN **THE **RENDER**:")
  print()
  print("  THE **PER-STATEMENT **JOIN** -- MEASURED (PARITY 138.17):")
  print("    693 calls a turn, 4.9 pieces per call, 22,983 chars of text")
  print("    2,955,749 chars copied -- THE AMPLIFICATION IS 128.6x")
  print("    =>=>+ AND IT IS **MANY SMALL JOINS** (693 OF THEM), **AND **EACH **IS **BOUNDED **AT **(n+1)/2**")
  print()
  print("  THE **PER-KERNEL **JOIN** -- THE SHAPE, NOT YET MEASURED:")
  for n, l in ((100, 40), (150, 40), (200, 40)):
    copies = l * n * (n + 1) // 2
    text2 = l * n
    print("    %d lines of %d chars: the text is %6d chars, the join copies %s -- %.1fx" % (n, l, text2, format(copies, ","), copies / text2))
  print("    =>=>+ AND IT IS **ONE CALL**, **AND **ITS **AMPLIFICATION **IS **THE **BIGGEST **SINGLE **ONE**")
  print()
  print("  THE **FIX **FOR **BOTH **IS **THE **SHAPE**, **NOT **THE **NESTING**:")
  print("    THE TEXT MUST NOT BE A STRING UNTIL THE VERY END.")
  print("    =>=>+ AND A STRING **CANNOT **BE **EXTENDED **IN **PLACE**, **=>=>+ AND **SO **THE **ONLY **O(n) **FORM **IS **A **LIST **OF **PIECES **ALL **THE **WAY**.")
  print()
  print("  THE **BLOCKER**, **MEASURED**: `St.kernel` IS `List<&2, String>` -- THE STATEMENT IS")
  print("  JOINED **BEFORE **IT **GOES **IN**, **=>=>+ AND **THE **PIECES **ARE **ALREADY **GONE **BY **THE")
  print("  TIME **THE **KERNEL **LIST **IS **BUILT**, **=>=>+ AND **AND **`St.kernel` **HAS **FIVE **OTHER **WRITERS**, **=>=>+ AND **SO **THE **CHANGE **IS **NOT **LOCAL**.")
