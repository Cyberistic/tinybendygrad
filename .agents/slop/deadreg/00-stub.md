# deadreg — unit stub

Owner: `tinybendygrad/runtime/dtype.c` + `tinybendygrad/runtime/dtype.js` ONLY.
Job: classify the 10 C + 1 JS registrations that `dtype.bend` no longer calls;
decide stage 8's true denominator; remove dead registrations; re-point or retire
stage 8. Never invoke `./bin/bend` bare — use `checks/bounded.py`.
