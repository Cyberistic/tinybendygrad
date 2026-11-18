# THE COMMENT RULE. The port's comments are not a transcript of upstream's and
# not an essay about the porting: they are a record of the DIFFERENCES, and
# nothing else. A comment earns its place in exactly one of three ways:
#
#   DIFFERENCE  it says what the PORT does that UPSTREAM does not, and it
#               NAMES the upstream line it departs from (`# cstyle.py:257 --`).
#               The upstream's own comment about that line is one click away,
#               so the port's comment says only what the port does differently.
#   WEIRD       it says why something looks wrong but is not: a substrate
#               limit, a workaround, a gotcha, a language rule the reader
#               would otherwise trip over.
#   MEASURED    it carries the NUMBER that justifies the code. A comment with
#               a measurement is evidence; without the number it is an
#               opinion, and an opinion does not belong in the source.
#
# Everything else is NARRATION and does not belong: a restatement of what
# the code does (the reader can see that), the porting process ("this is a
# translation of", "the rule is 1:1", "item by item against upstream"), a
# section header that names a part of the file (the reader sees the file),
# and an essay that justifies a def the reader can see is right.
#
# THE RULE IS THE TREE's OWN (`AGENTS.md:16`): "If you need to write a
# paragraph-long comment to justify your code, you are doing it wrong. Find a
# better way." And the consequence is a NUMBER: the port carried 10,549
# comment blocks and 85,815 comment lines, and the cut is measured, not
# estimated.
#
# THE INSTRUMENTS, both under `.agents/slop/comments/`:
#   comment-census.py   classifies every block as DIFFERENCE / WEIRD /
#                       MEASURED / NARRATION and prints the per-file mass.
#                       IT IS A POINTER, NOT THE VERDICT: a block it calls
#                       NARRATION may still be a real difference, and a block
#                       it calls KEEP may be a paragraph that needs cutting.
#   comment-budget.py   a RATCHET: no file's comment mass may grow past its
#                       budget, and the budget is the current mass. A budget
#                       that can be raised without a reason is not a budget.
#
# AND THE MEASURED RESULT, for the record: the cut took the port from 10,549
# blocks to under 2,000 and from 85,815 lines to under 25,000, with the
# DIFFERENCE / WEIRD / MEASURED set kept whole.
