the citations that named the PORT's own symbols, and the pointers that rotted: 63 unverifiable and 95 WRONG-LINE, both to ZERO

The port's upstream citations named the PORT's own vocabulary -- `pra_len`, `fds_of`,
`mrender.*`, `cl_err_code`, `arch_of`, `q_init`, `wait_signal`, `hp_err_of`, `icb_keep`,
`cns_string`, `magic_ok`, `Sec.is_progbits`, `vol`, `lidx`, `cerr_depth`, `rb_1`, `tn_rop`,
`dedup`, `Scheduler`, `max_pool`, `Spec` -- and upstream does not contain any of them, so no
re-point could make the claim hold: THE FIX IS THE PROSE. Each of the 63 is rewritten to say
what upstream ACTUALLY does, in upstream's own vocabulary, with the upstream construct named
in backticks (which is what `gates/pin-cite-gate.py` reads as the claim). Where upstream's
construct is GONE at this pin -- `CUDAQueue` and `pm_bufferize` (c0c13ea51), `HIPProgram` and
`HIPProgram.__del__` (d33d97ca7), the HIP `check` -- the prose says so and names the survivor.

The second class is the port's OWN pointers to ITSELF: 95 `WRONG-LINE` rows whose cited line
no longer holds the construct the comment means. Each pointer now lands on the construct.

MEASURED, same instruments, same tree state, restricted to this slice's 27 files:
  pin-cite-gate.py    unverifiable 63 -> 0    dangling 0 -> 0    at_no_revision 4 -> 4 (all
                     four PRE-EXISTING and not in this slice's row set)
  bendcite-gate.py   WRONG-LINE 95 -> 0      DANGLING-LINE 0 -> 0   ABSENT-FILE 0 -> 0
  todo-cite-gate.py  0 WRONG-LINE / 0 WRONG-SYMBOL / 0 UNRESOLVABLE, before and after

ALL 27 FILES COMPILE: `.venv/bin/python checks/bounded.py --mb 2048 -- ./bin/bend <file>`,
one at a time, every verdict token WITHIN-LIMITS.

THE COMMENT-ONLY PROOF: 25 of the 27 files strip to the SAME code hash as HEAD under
`checks/port-compile-gate.py`'s `strip_comments()`. THE TWO THAT DO NOT are
`extra/models/clip.bend` and `extra/models/mask_rcnn.bend`, and the difference is FOUR
`D.refuse("...")` DIAGNOSTIC STRINGS whose stale `.bend:NN` citation had to move -- a refusal
message is a human-readable address, no gate parses it, and the refusal still fires on the
same arm with the same count.

THE PLANTS are TEXT EDITS ON COPIES under `.agents/slop/unv1/plant/`: breaking one upstream
construct NAME moves its pin-cite row from `at_pin` to `unverifiable`; breaking one re-pointed
port-to-port pointer moves its bendcite row from `RESOLVES` to `WRONG-LINE`. The byte-identical
control stays green.

No `symbol=` was added: `gates/pin-cite-gate.py` reads backticks and `gates/todo-cite-gate.py`
reads `symbol=`, and a `symbol=` next to an upstream citation is a NEW way to be wrong when it
names a PORT symbol, a builtin, or a construct from a different upstream file.

NOT FIXED, and why: 4 `at_no_revision` rows in `renderer/llvmir.bend` and `tensor.bend` were
`at_no_revision` BEFORE and AFTER -- they are not this slice's rows. The tree-wide
`todo-cite-gate.py` rc stays 1 on 4 `WRONG-SYMBOL` rows in `examples/test_pkl_imagenet.bend`,
`mixin/elementwise.bend` and `uop/ops.bend`, which this slice does not own.
`tinybendygrad/nn/datasets.bend` is untouched.
