16x16 NOW BEATS PYTHON (1.60x): the loop's Bool.pick burned the whole FUEL, and the real step count makes the uop walks visible

TWO DEFECTS, BOTH FOUND BY COUNTING IN THE COMPILER'S OWN C:

1. `case 1n+k: Bool.pick(Prog, Prog.over(pr), pr, run(k, Prog.step(pr)))` --
   Bool.pick EVALUATES BOTH ARMS, so the recursive arm ran after the program
   finished and every launch burned all of FUEL: the step counter read
   4 000 000 for a 16x16 packet AND 4 000 000 for a 32x32 one, two different
   programs, both exactly the fuel. Matching on the cursor `un` (which IS
   pc < n, and a List is a legal multi-scrutinee where a computed Bool is not)
   cut it to 17 970 / 93 917 steps.

2. Every per-step figure in sections 9 and 10 therefore divided by 4000000
   instead of 93917, which is why the sslot change measured 0 percent there.
   With the right denominator, Prog.src's five Uop.at walks per step are
   126 605 244 arity-11 copies = 1 348 per step = 1.39e9 field visits. Resolving
   each src's SLOT once at load, through a 2-field slot table rather than the
   11-field uop list, deletes them (126.6M -> 2.3M).

MEASURED
  16x16: PYTHON 538.08  BEND 336.46 ms/iter -> BEND is 1.60x FASTER (was 2.45x slower)
  32x32: PYTHON 2728.1  BEND 6137.17 ms/iter -> 2.25x slower (was 4.94x)
  ops_python_exec: PASS -- 153 fixtures, 365 rows x 2 lanes, 0 divergences
  max|diff vs CPU| 8.941e-08 and 3.576e-07 -- unchanged.

WHAT IS LEFT at 32x32 is 2 609 arity-2 (consecutive-cell) copies per step: the
arena's four spine walks per 4-byte access. Named, not fixed.
