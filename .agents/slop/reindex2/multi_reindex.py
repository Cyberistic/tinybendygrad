#!/usr/bin/env python3
"""`multi.bend`'s side of the GROUP/FLIP deletion. MEASUREMENT COPY ONLY.

Deletes `mu_own`'s tag 7 (`[OpsFLIP{}]`, upstream multi.py has no such rule), moves
tags 8..18 DOWN one in ONE SIMULTANEOUS pass -- a descending loop would catch the
name it just wrote -- and rebases `mu_ra_cfg.go`'s accumulator offset 19/20 -> 18/19.

Nothing here is transcribed: the tag map is `old -> old - 1` over the range read
out of the file, and the base offset is DERIVED from the surviving `mu_own` length.
"""

import re
import sys
from pathlib import Path

MULTI = Path("tinybendygrad/schedule/multi.bend")
TAG = re.compile(r"^(\s*\[?\s*O\.PMEntry\{)(\d+)(,)")


def retag(line: str, moved: dict[int, int]) -> str:
  """`O.PMEntry{8,` -> `O.PMEntry{7,` for every tag in `moved`, in one substitution.

  The optional `[` is the list's head: `mu_own` opens with `[O.PMEntry{0, ...`, and a
  regex that did not allow for it silently DROPPED tag 0 from the map's domain --
  which is the same class of blindness as reading a population off a suffix.
  """
  return TAG.sub(lambda m: f"{m.group(1)}{moved.get(int(m.group(2)), int(m.group(2)))}{m.group(3)}",
                 line)


def tags_of(lines: list[str]) -> list[int]:
  out = []
  for l in lines:
    m = TAG.match(l)
    if m:
      out.append(int(m.group(2)))
  return out


def main() -> int:
  src = MULTI.read_text()
  lines = src.splitlines(keepends=True)

  head = next(i for i, l in enumerate(lines) if l.startswith("def mu_own()"))
  tail = next(i for i in range(head + 1, len(lines)) if lines[i].startswith("def "))
  block = lines[head:tail]

  # 1. The FLIP rule. Its TAG is read off its own line -- `drop` is a line INDEX, and
  #    conflating the two is how a rule ends up renamed by the wrong amount.
  if not any("OpsFLIP{}" in l for l in block):
    sys.exit("mu_own carries no OpsFLIP{} rule")
  drop = [i for i, l in enumerate(block) if "OpsFLIP{}" in l]
  if len(drop) != 1:
    sys.exit(f"mu_own has {len(drop)} OpsFLIP rules, wanted 1")
  gone_tag = tags_of([block[drop[0]]])[0]

  # 2. The whole tag map is read OUT of the PRE-deletion block, so the pre-state is
  #    known to be dense 0..n-1; then the deleted line goes and the survivors above it
  #    move DOWN one in ONE SIMULTANEOUS pass (a descending loop would catch the name
  #    it just wrote and cascade it again).
  tags = tags_of(block)
  if tags != list(range(len(tags))):
    sys.exit(f"mu_own tags are not 0..{len(tags) - 1}: {tags}")
  del block[drop[0]]
  moved = {t: t - 1 for t in tags if t > gone_tag}
  after = [moved.get(t, t) for t in tags if t != gone_tag]
  if after != list(range(len(after))):
    sys.exit(f"the tag map is not dense after the move: {after}")
  block = [retag(l, moved) for l in block]

  lines[head:tail] = block

  # 3. `mu_src_src.of` IS A PER-TAG DISPATCH: a `match tag:` whose arms are the tag
  #    numbers, and renaming the defs a `match` names does NOT renumber its arms --
  #    the trap `spec.bend` records and that `shift_sh.py` handles by REBUILDING
  #    `sh_dispatch.go`. `mu_own` losing tag 7 must move those arms too, or a rule is
  #    asked another rule's src test.
  #
  #    MEASURED CONSEQUENCE OF SKIPPING IT, on this copy, before the fix:
  #    `r_full_su` (mu_claim_full on STORE-of-M0) answered 2 and now answers 1. A COUNT
  #    moving is not a renumbering, and `t_full_su` going red is the signal the brief
  #    says to stop on -- so the ladder is part of the edit, not a follow-up.
  #
  #    The map is UNIFORM for every arm at or above the deleted tag: the own half's
  #    tags drop one, and the ra half's drop one because `mu_ra_cfg`'s base drops one.
  ladder = re.compile(r"^(\s*case )(\d+)(\s*:)")
  lo = next(i for i, l in enumerate(lines) if l.startswith("def mu_src_src.of("))
  hi = next(i for i in range(lo + 1, len(lines)) if lines[i].startswith("def "))
  arms = [int(ladder.match(l).group(2)) for l in lines[lo:hi] if ladder.match(l)]
  if sorted(arms) != sorted(set(arms)):
    sys.exit(f"mu_src_src.of has duplicate arms: {arms}")
  if gone_tag not in arms:
    sys.exit(f"mu_src_src.of has no arm for the deleted tag {gone_tag}")
  moved_arms = {t: t - 1 for t in arms if t > gone_tag}
  new_arms = sorted(moved_arms.get(t, t) for t in arms if t != gone_tag)
  if len(new_arms) != len(set(new_arms)):
    sys.exit(f"the arm map COLLIDES: {new_arms}")
  out = []
  for l in lines[lo:hi]:
    m = ladder.match(l)
    if not m:
      out.append(l)
    elif int(m.group(2)) == gone_tag:
      continue
    else:
      out.append(ladder.sub(lambda mm: f"{mm.group(1)}{moved_arms.get(int(mm.group(2)), int(mm.group(2)))}{mm.group(3)}", l))
  lines[lo:hi] = out

  # 3. `mu_move_ops` loses the member, so the M6 inventory row moves with it. Scoped to
  #    the def's OWN BODY by line, because a bare `, O.OpsFLIP{}` elsewhere belongs to
  #    a different rule and this script must not be the thing that decides which.
  mv = next(i for i, l in enumerate(lines) if l.startswith("def mu_move_ops("))
  mv_end = next(i for i in range(mv + 1, len(lines)) if lines[i].startswith("def "))
  if sum(l.count("O.OpsFLIP{}") for l in lines[mv:mv_end]) != 1:
    sys.exit(f"mu_move_ops does not carry exactly one FLIP member")
  lines[mv:mv_end] = [l.replace(", O.OpsFLIP{}", "") for l in lines[mv:mv_end]]

  # 4. The base offset is DERIVED from the surviving `mu_own` length, not typed in.
  own_n = len(after)   # ENTRIES, not lines: the block carries comments and a blank
  old_late, old_early = 19, 20
  if own_n + 1 != old_late:
    sys.exit(f"mu_own is {own_n} entries, so the base {old_late} does not follow")
  src = "".join(lines)
  src, n = re.subn(rf"mu_ra_shift\({old_late},", f"mu_ra_shift({own_n},", src, count=1)
  src, m = re.subn(rf"mu_ra_shift\({old_early},", f"mu_ra_shift({own_n + 1},", src, count=1)
  if (n, m) != (1, 1):
    sys.exit(f"rebased the offsets {n}/{m} times, wanted 1/1")

  MULTI.write_text(src)
  print(f"mu_own {old_late + 1} -> {own_n} entries; "
        f"mu_ra_shift base {old_late}/{old_early} -> {own_n}/{own_n + 1}")
  return 0


if __name__ == "__main__":
  sys.exit(main())