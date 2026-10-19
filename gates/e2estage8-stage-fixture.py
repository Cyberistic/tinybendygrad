# FROZEN FIXTURE -- DATA, NOT A PROGRAM.
#
# `.agents/slop/e2estage8/verdicts.py` READS this file with `Path.read_text()` and regexes it. Nothing
# imports it and nothing executes it, and the name deliberately does NOT end in `-gate.py`: MEASURED
# 2026-10-19, `checks/gatesweep.py:167` declares `SUFFIX = "-gate.py"` and sweeps `gates/*-gate.py` by
# directory walk, so a fixture named like a gate would be RUN as one and would fail for having no
# driver.
#
# It is the CONTROL for `gates/e2estage8-stage-selftest.py`: three stages, ONE consistent declared
# denominator (`/3` on every banner and three call sites to disagree with), and countable rows in two
# of them. **A PLANT IS ONLY A PLANT IF THE UNPLANTED FIXTURE IS GREEN**, because a fixture that is
# already red scores every plant as a success.
"""A FROZEN THREE-STAGE FIXTURE GATE.

Its module docstring is the PROSE reader's population: a STAGE table, then an `EXIT STATUS` header.
The census cuts the table at that header BY NAME, not by line number, because the next edit moves
line numbers and a table that runs into the exit codes reads them as stages -- which is how the
`PROSE names [0] the CODE does not emit` finding happened.

  1  oracle (CPython)
  2  port (pure bend, no GPU)
  3  gate

EXIT STATUS
    0  every stage passed
    1  a stage failed
"""
def say(line):
    print(line)


def main():
    say("== 1/3 oracle (CPython)")
    say("== 2/3 port (pure bend, no GPU)")
    say("== 3/3 gate")