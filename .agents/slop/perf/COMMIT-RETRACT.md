RETRACTED: the 401-term_drops-per-allocation reading was counted BEFORE the trivial-term test, so it counted immediates; five instruments, five self-invalidations

term_drop's first act is `if (!term_triv(t) && term_rfc(t))`, and my counter
incremented at the TOP OF THE FUNCTION -- so it counted every immediate field of
every record as a "drop". 2412939949 is a count of CALLS, most one branch each,
and says nothing about the heap.

The fix to the counter did not settle it either: splitting at the term_triv test
gave drop_triv=0 for 2.4 BILLION calls, which is implausible -- so that
instrumentation landed somewhere term_triv never answers true. A number whose own
control says "never trivial" is a number to disbelieve, and I disbelieve my own.

Also: the runtime takes options only between +RTS and -RTS, so section 6.3's
`--threads 1` test NEVER REACHED THE RUNTIME, and the +RTS forms exit in 0.00 s
with no output and rc=0 -- they ran nothing. That is NOT reported as a speedup.

FIVE INSTRUMENTS, FIVE SELF-INVALIDATIONS: the ablation control ran 70 steps not
18000; the Mem.put ablation changed the program; the drop counter counted
immediates; its fix reported zero trivial terms; --threads never reached the
runtime. The honest conclusion is that I do not have an instrument in this tree
that can attribute the cost.

No stage is met. 533 ms vs 29973 ms, one bit-exact 3.7 percent change landed,
census 153 fixtures / 0 divergences.
