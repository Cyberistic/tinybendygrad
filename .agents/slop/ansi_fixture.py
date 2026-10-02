#!/usr/bin/env python3
"""THE FIXTURE LIST for the `ansistrip` gate, in ONE place, so the CPython lane
and the Bend lane cannot drift: `.agents/slop/ansi_probe.bend` spells the same
entries as `p0()..pN()` and both are walked in this order.

The list is NOT uniform. Every entry before the bug was found carried the same
shape `ESC [ <digits> m` -- one `m` parameter run -- so a port that re-emitted
`ESC` plus ONE character agreed with CPython on all of them. `K` vs `...m` is
the discriminating axis and these entries are chosen to separate them:

  * `K` alone              `ESC [ K`      -- the FIRST alternative
  * `m` alone              `ESC [ m`      -- `.*?` of length ZERO
  * multi-parameter        `ESC [ 1;31;42 m`
  * `K` then more          `ESC [ K m`     -- proves `K` wins and `m` SURVIVES
  * `K` then params        `ESC [ K31m`    -- proves `K` wins and `31m` SURVIVES
  * params then `K`        `ESC [ 31mK`    -- proves `K` is only special in FIRST place
  * newline inside a run   `ESC [ 31\\nm`   -- `.` cannot cross a newline, so NO match
  * ESC inside a run       `ESC [ 1 ESC [ 2 m` -- `.*?` spans ESCs
  * ESC inside + `K`       `ESC [ ESC [ K \\n` -- the case that forces a RE-SCAN
  * unterminated           `ESC [ 31`, `ESC [`, `ESC`
  * bare `[`               `[31m`          -- a `[` with no ESC opens nothing
  * empty                  ``
"""
E = "\x1b"
FIXTURES = [
  "",                                     # empty input
  "plain",                                # no escape at all
  E,                                      # a lone ESC
  E + "[",                                 # ESC [ and nothing else
  E + "[31",                               # an unterminated parameter run
  "[31m",                                 # a bare `[` is not an opener
  "[",                                    # a bare `[`, alone
  "[x",                                   # a bare `[` then text
  E + "[K",                                # K alone, THE FIRST ALTERNATIVE
  E + "[Kx",                               # K alone then text -- the EATS-THE-x row
  E + "[Km",                               # K then m -- m SURVIVES
  E + "[K31m",                             # K then params -- 31m SURVIVES
  E + "[K[K",                              # K K
  E + "[31m",                              # m alone, `.*?` of length ZERO
  E + "[m",                                # m alone, nothing after
  E + "[mx",                               # m alone then text
  E + "[31mred" + E + "[0m",               # the two-parameter SGR row
  E + "[1;31;42mWARN" + E + "[0m",         # multi-parameter (three, `;`-separated)
  E + "[38;2;255;0;0mT" + E + "[0m",       # multi-parameter, five
  E + "[31mK",                             # params then a bare K
  E + "[31mK" + E + "[K",                  # params, K, then the K alternative
  E + "[1m" + E + "[0m" + E + "[0m",       # NESTED RESETS, back to back
  E + "[0m" + E + "[0m" + E + "[0m",       # three resets in a row
  E + "[31m\nm",                           # NEWLINE inside the run: `.` cannot cross it
  E + "[\nm",                              # newline as the FIRST body char
  E + "[31\nmred",                         # newline mid-run, then text
  E + "[\n" + E + "[31m",                   # a failed run, then a good one
  E + "[" + E + "[31m",                     # ESC inside the run
  E + "[" + E + "[31",                      # ESC inside an unterminated run
  E + "[" + E + "[K\n",                     # ESC then K inside: RE-SCAN territory
  E + "[" + E + "[Km",                      # ESC then K then m
  E + E,                                   # two ESCs
  E + E + "[31m",                          # ESC ESC [31m
  E + E + "x",                             # ESC ESC x
  E + "x",                                 # ESC that opens nothing
  E + "[31mx" + E + "y",                    # stray text around one escape
  E + "[31m" + E,                          # a good run then a lone ESC
  E + "]0;title",                          # an OSC introducer, no ESC
  "x" + E + "[K" + "y" + E + "[31mz",       # K-run and m-run in one string
  E + "[K\n",                              # K wins over the newline that follows it
  E + "[m\n",                              # m wins over the newline that follows it
  E + "[1" + E + "[0m" + E + "[K",          # m-run, then a nested opener, then K
  E + "[31m" + E + "[",                      # a good run then an unterminated opener
]
