# DTYPEB — unit log

`00-stub.md` was the first thing this unit put on disk (agent-core's FIRST ACTION rule),
at 22:22, before any reading. The result is `../DTYPEB.md`.

**14 -> 6.** Retired 8, and the 6 that remain are one missing primitive
(`F32.from_bits`, which does not exist on Bend 2.0.34). Reproduce:

```sh
python3 .agents/slop/dtypeb/run.py
```

`gate.txt` is the log of the run above. Nothing committed; `tinybendygrad/dtype.bend` is
untouched in the live tree; the patched file is `dtype.patched.bend` beside this note.