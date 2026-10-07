CLAIM (unit ADEV): .agents/slop/graphcmp.py .agents/slop/graphcmp.bend .agents/slop/graphcmp-oracle.py

TAKEN 2026-10-04. md5 AT MY TAKE (this is my baseline):
  graphcmp.py        67b454db08a2fa910a7927a313a57859
  graphcmp.bend      ec2984228ab735401e230e6c27147767
  graphcmp-oracle.py 9f47db7830523b41068a1196808c118b

*** BOTH graphcmp.py and graphcmp.bend HAVE ALREADY MOVED SINCE DENOM'S TAKE ***
(c7096ee7 / 9e5299b7). graphcmp-oracle.py still matches. That is collision five.
Whoever moved them: not me. My edits are diffed from the md5s ABOVE.

(The DENOM unit re-claimed the same three read-only; I supersede by appending here.)

I do NOT touch: base.bend, dtype.bend, runtime/dtype.js, .agents/slop/clangshim/**,
any other .bend, runtime/**, uop/**, helpers.bend, renderer/**, tinygrad/**, LAWS/**,
PROOF*.bend, rebase-gate.py, cstyle-gate.py, reader-*, e2e*, abi_gate.py, jsfix_*,
another unit slop tree.  Scratch in $TMPDIR.  Commit NOTHING.

Job: the COPY/ADev normal-form decision (g_allred DISAGREE).
Rule prefix: ADEV-

---
# RELEASED 2026-10-04 by unit `adev`. The three files are free to edit again.

Final md5s of my work (revert-tested; a real revert of the pre-fix state was re-run and
the restore was md5-verified against these):

  graphcmp.py        4a0d2467b7e70d701afac68091394f40
  graphcmp.bend      184f7edd80404c8b7aedb33beb28bcd8
  graphcmp-oracle.py 9f47db7830523b41068a1196808c118b   UNTOUCHED all along

WHAT I CHANGED, so a later collision has something to attribute:

* `graphcmp.py` -- `dev()` DELETED (it existed only to flatten a device tuple; both call
  sites now say `_carg`); one new `carg` arm `if op is Ops.COPY: return _carg(x)`; two new
  plants `plant_devpair` / `plant_devdisarm` and two `PLANTS` entries.
* `graphcmp.bend` -- ONE body changed: `devs` now wraps `n(..)` instead of `bstr(...)`.

`g_allred` reads AGREE, `selfcheck` OK, `control` OK, and all 25 graphs re-measured:
23 AGREE / 2 DISAGREE (`lin`, `loop` — deliberate). NOT COMMITTED.
