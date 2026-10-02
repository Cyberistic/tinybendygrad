# Bend 2: the constraints that decide how tinygrad gets ported

Everything here was **measured** against the pinned checkout in `vendor/bend`
(bend 2.0.34), not read off the docs. Where the docs and the compiler
disagree, the compiler wins. Every claim has a reproducer.

Reproduce anything here with:


## INDEX (added 2026-10-02 -- THE NUMBERING IS BROKEN, READ THIS FIRST)

**Two agents each appended their own numbered series, so rule NUMBERS REPEAT.**
`rg '^### ' ` finds the list below in FILE ORDER; the number column is what the
prose says, and it is not unique. A reference to "rule 32" is ambiguous between the
`List.foldl` rule and the `Bool.pick` rule, for example. Positions (line numbers) are
unique and stable -- cite those until this is renumbered. Renumbering was rejected
because dozens of files and comments cite rules BY NUMBER, and a renumber would
silently invalidate every one of them.

| # | line | title |
|---|---|---|
| 1 | 598 | No forward references, and the error lies about the cause |
| 2 | 612 | A self-call SPENDS the list it walks, so a walk cannot return it |
| 3 | 630 | A `Data` record is how a list travels with something derived from it |
| 4 | 640 | A two-scrutinee `match` must cover the cross product, and `_` counts |
| 5 | 658 | `Nat` and `U32` are different types, and only `Nat` hands out a tail |
| 6 | 681 | A `do` block has no statement limit, and bare calls are statements |
| 7 | 695 | A `List` table is O(n²) and `Array` cannot fix it |
| 8 | 703 | FIVE bugs that all typechecked, and what caught them |
| 1 (DUP) | 1194 | A `Data` RECORD PARAMETER NEEDS `+` FOR TWO READS. IT IS NOT IMPLICITLY COPYABLE |
| 2 (DUP) | 1213 | AN UNUSED `+` PARAMETER IS ACCEPTED |
| 3 (DUP) | 1223 | `+` CANNOT BE SPELLED ON A `Maybe` PARAMETER |
| 4 (DUP) | 1247 | A ONE-FIELD RECORD'S PATTERN MUST NAME ITS FIELD |
| 5 (DUP) | 1260 | A TWO-SCRUTINEE `match` NEEDS ONE PATTERN PER SCRUTINEE, AND `_ _` IS THE COVER |
| 6 (DUP) | 1271 | A THREE-SCRUTINEE `match` WITH A `Nat` COUNTDOWN HAS NO `0n` ARM |
| 7 (DUP) | 1285 | A SELF-CALL DRIVEN BY A `Nat` COUNTDOWN MUST PASS THE SHRINKING ARGUMENT FIRST |
| 1 (DUP) | 1355 | `def f.b(...)` MUST BE DECLARED BEFORE `def f.a(...)` THAT CALLS IT |
| 2 (DUP) | 1365 | A `Some{g}` BINDER OVER A `Data` RECORD IS AFFINE: TWO READS NEED `Some{+g}` |
| 3 (DUP) | 1373 | `Nat` LITERALS ONLY BIND IN A `Nat` CONTEXT, AND `Bool.to_u32` IS NOT ONE |
| 4 (DUP) | 1381 | A RECORD PATTERN MAY NAME FEWER FIELDS THAN THE RECORD HAS -- SILENTLY |
| 5 (DUP) | 1389 | BEND IS STRICT: AN ARGUMENT IS EVALUATED BEFORE THE CALLEE BRANCHES |
| 6 (DUP) | 1404 | A GROWING ACCUMULATOR CANNOT BE THE FIRST PARAMETER OF A SELF-CALL |
| 7 (DUP) | 1412 | A `Data` RECORD CAN CARRY THE `Maybe` A PARAMETER CANNOT |
| 8 (DUP) | 1419 | AN `IO<Unit>` `do` BLOCK CAN ONLY BIND AN `IO` |
| 1 (DUP) | 1430 | A `Maybe` PATTERN BINDER CANNOT BE READ TWICE |
| 2 (DUP) | 1453 | A COMMUTATIVE `alu` BUILDS AN `is_any`, SO A `+` PATTERN IS A DISJUNCTION |
| 3 (DUP) | 1463 | `dm_which`-STYLE DISJUNCTIONS ARE NOT DISTINGUISHABLE BY ONE FIXTURE FAMILY |
| 4 (DUP) | 1471 | AN INDEX IS ONLY MEANINGFUL IN THE ARENA THAT PRODUCED IT, AND `+` DOES NOT ENFORCE IT |
| 5 (DUP) | 1484 | `floor` IS NOT AVAILABLE AND MUST NOT BE ASSUMED FROM A HELPER NAMED `floordiv` |
| 6 (DUP) | 1502 | A NESTED-FORWARD TREE PRINTER IS A MUTUAL RECURSION, AND BEND REFUSES IT |
| 1 (DUP) | 1517 | A `Maybe` IS READ ONCE AND CANNOT BE `+`, SO "TEST IT AND USE IT" IS TWO DEFS |
| 2 (DUP) | 1543 | `Maybe<a, A>` IS INVARIANT IN ITS USAGE COUNT |
| 3 (DUP) | 1553 | A `find`-STYLE RECORDER IS USUALLY A FOLD WITH AN INVERTED `Bool`, AND THAT IS THE BUG |
| 4 (DUP) | 1563 | `ops.bend`'s `Arena.empty()` SPENDS INDEX 0, SO EVERY FIXTURE IS OFF BY ONE |
| 5 (DUP) | 1574 | A FIXTURE BUILDER THAT RETURNS AN INDEX THROWS THE GROWN ARENA AWAY |
| 6 (DUP) | 1590 | `List.append(a, A, xs, ys)` IS `xs ++ ys`, AND A FOLD THAT USES IT ACCUMULATES IN REVERSE |
| 7 (DUP) | 1600 | TWO RULES THAT CLAIM ONE NODE AND **AGREE** CANNOT SEE FIRST-WINS |
| 1 (DUP) | 1620 | AN ARM AFTER A `case _:` IS **DEAD CODE**, AND BEND DOES NOT SAY SO |
| 2 (DUP) | 1648 | A GATE THAT NEVER CALLS THE FUNCTION UNDER REPAIR IS BLIND, AND IT IS NOT AN ACCIDENT |
| 3 (DUP) | 1664 | `+` IS NEEDED ON A `Data` PARAMETER USED **TWICE IN ONE EXPRESSION**, NOT TWICE IN A BODY |
| 4 (DUP) | 1675 | `U32.show` ON A NEGATIVE `i32` IS THE BIT PATTERN, SO A GATE MUST SAY SO |
| 5 (DUP) | 1684 | A `(Bool, Bool)` FLAG PAIR IS NOT INTERCHANGEABLE, AND WHICH HALF IS CONSULTED IS THE WHOLE DEFI |
| 6 (DUP) | 1703 | FLOOR AND TRUNCATION ARE TWO FUNCTIONS AND BOTH GET PORTED, SO "DELETE THE DUPLICATE" IS USUALLY |
| 7 (DUP) | 1721 | A COMPILED ARENA MAKES A `Dt` A KEY, SO A `Cls` COMPARISON IS NOT A COSMETIC BUG EVEN WHEN EVERY |
| 8 (DUP) | 1733 | `.venv/bin/python`, NOT `python3`, FOR A GATE THAT IMPORTS THE ORACLE |
| 1 (DUP) | 1868 | `--check-only`'s FOREIGN NOTICE IS A "WHO NAMES WHOM" CLOSURE, AND `@unsafe` DOES NOT SHRINK IT |
| 2 (DUP) | 1885 | A `U32` LITERAL PATTERN IS A PREFIX MATCH, AND THE ERROR SAYS NOTHING USEFUL |
| 3 (DUP) | 1897 | `Data` TYPES ARE NOMINAL, so two records with the same fields are TWO TYPES |
| 4 (DUP) | 1908 | TWO SELF-CALLS IN ONE ARM IS REFUSED EVEN WITH TWO DIFFERENT `Nat` FUELS |
| 5 (DUP) | 1922 | A LIST SELF-CALL MUST SHRINK ITS FIRST ARGUMENT, SO A GROWING ACCUMULATOR GOES SECOND |
| 6 (DUP) | 1933 | AN `IO` EFFECT IS NOT A VALUE: `f(walk(...))` IS A TYPE ERROR, `f`'s arg must be pure |
| 7 (DUP) | 1944 | A `match` CANNOT FOLLOW A `<-` BIND INSIDE A `do` BLOCK |
| 8 (DUP) | 1955 | THE INTERPRETER'S PER-FILE BYTE CLIFF IS 28987/28988, NOT 32768 |
| 9 | 1969 | THE INTERPRETED LANE RE-CHECKS THE WHOLE FILE ON EVERY RUN, SO BISECTING A CLIFF IS DOMINATED BY |
| 1 (DUP) | 1979 | A `match` ON A `String` NEEDS A `case _:`, AND WITHOUT ONE THE ERROR IS A PARSE ERROR |
| 2 (DUP) | 2000 | `String.take`, `String.drop` and `String.split` CONSUME THE STRING |
| 3 (DUP) | 2014 | `IO.args()` ANSWERS `List<&1, String>`, NOT `List<&2, String>` |
| 4 (DUP) | 2026 | `List.get` ANSWERS A `Maybe`, AND `String.get` ANSWERS A `Maybe<Char>` |
| 5 (DUP) | 2038 | `String.to_u32` DOES NOT EXIST; `Char.to_u32` DOES, AND IT RETURNS A CODEPOINT |
| 6 (DUP) | 2049 | A `match` INSIDE A `do` BLOCK IS REFUSED, SO DISPATCH GETS ITS OWN DEF |
| 1 (DUP) | 2065 | `Map.put` IS NOT `Map.set`, AND `Map.put` LOSES KEYS |
| 2 (DUP) | 2071 | `Map.get` ANSWERS A `Sigma`, NOT A `Maybe` |
| 3 (DUP) | 2079 | A RECORD PATTERN MUST NAME EVERY FIELD, IMPORTED RECORD OR NOT |
| 4 (DUP) | 2087 | `case +h <> t:` -- `+` ON A PATTERN BINDER RESOLVES "TWO READS IN ONE EXPRESSION" |
| 5 (DUP) | 2094 | A SELF-CALL WITH A COMPUTED ARGUMENT IN FRONT OF THE TAIL IS NOT DECREASING |
| 6 (DUP) | 2100 | A `Nat` COUNTDOWN IS THE ONLY COUNTDOWN A U32 LOOP GETS |
| 7 (DUP) | 2106 | `Bool.pick(-A, c, a, b)` ANSWERS `a` WHEN `c` IS TRUE -- AND GETTING IT BACKWARDS EMITS A PLAUSI |
| 1 (DUP) | 2146 | A `match` MAY NOT SCRUTINISE A COMPUTED VALUE -- THE `.go` SPLIT IS NOT OPTIONAL |
| 2 (DUP) | 2158 | THE `+` PROPAGATES ONE READER DOWN, AND `List<&2, T>` IS NOT `List<&1, T>` |
| 3 (DUP) | 2173 | A `Maybe` FROM `List.get` NEEDS THE SPLIT EVEN INSIDE A `match` HEAD POSITION |
| 4 (DUP) | 2185 | AN ARENA IS A `Data`, AND `Found.ar` / `Found.i` ARE NON-CONSUMING READERS |
| 5 (DUP) | 2199 | AN UNFILLED LAW IS A HARD ERROR, SO A DEF MUST BE DEFINED BEFORE IT IS CALLED |
| 1 (DUP) | 2236 | A FOLD THAT ALSO CARRIES A CHANGED-BIT MUST `or` THE WHOLE LIST, NOT THE HEAD |
| 2 (DUP) | 2244 | `+` ON A `Data` FIELD BINDER IS A COPY AND IS NEEDED TO USE IT TWICE |
| 3 (DUP) | 2249 | A `match` CANNOT SCRUTINISE A COMPUTED VALUE -- GIVE IT ITS OWN DEF |
| 4 (DUP) | 2256 | A DEF MUST BE DEFINED BEFORE IT IS CALLED, AND THAT IS NOT DEF ORDER |
| 5 (DUP) | 2265 | A `Nat` FUEL BOUND IS A BOUND, AND A WAITLIST MAKES IT MUCH LOOSER |
| 1 (DUP) | 2320 | A 64-BIT PRODUCT IS A WALL, NOT A TODO: `base.bend` DOES NOT EXPORT `Word` |
| 2 (DUP) | 2336 | TWO FIXTURE BUILDERS THAT RETURN AN INDEX ARE THE SAME TRAP AS ONE |
| 3 (DUP) | 2349 | A GATE ROW THAT SAYS WHAT A BOOLEAN CANNOT IS NOT OPTIONAL |
| 4 (DUP) | 2363 | A `list`-TAIL FOLD THAT MUST HAND SOMETHING BACK CARRIES IT IN A RECORD |
| 1 (DUP) | 2825 | A `Data` RECORD PATTERN IS CAPPED AT 28 FIELDS, AND THE ERROR IS A BARELY PARSEABLE "a `Fix` pat |
| 2 (DUP) | 2834 | A `match` ON A `Nat` COUNTDOWN AND A LIST IN ONE ARM NEEDS THE COUNTDOWN FIRST, AND `p` MAY NOT  |
| 3 (DUP) | 2853 | A NODE-COUNT FOLD MUST ADD ITS `+1` TO THE ACCUMULATOR, NOT TO THE HEAD |
| 4 (DUP) | 2863 | A `Data` RECORD FIELD READ TWICE THROUGH A FIELD ACCESSOR NEEDS `+`, AND `+` ON THE RECORD IS NO |
| 5 (DUP) | 2876 | A RULE THAT GROWS THE ARENA RETURNS `(Arena, answer)` AND THE ANSWER MUST BE A `Data` RECORD, NO |
| 6 (DUP) | 2885 | THE GATE NEEDS A ROW THAT READS AN INDEX OR AN OP, NOT A LENGTH -- MEASURED TWICE IN ONE FILE |
| 1 (DUP) | 2906 | `case 1n+p:` IS A PREFIX MATCH TOO, AND IT IS WORSE THAN `case 0n:` |
| 2 (DUP) | 2917 | A `.go`/`.step` PAIR IS MUTUAL RECURSION, SO THE SELF-CALL MUST BE AN ARGUMENT |
| 3 (DUP) | 2926 | A `match` ON A LIST SPENDS IT, AND `[head] ++ tail-of-tail` LOSES AN ELEMENT |
| 4 (DUP) | 2935 | AN ARENA IS THE ONE A BUILD RETURNED, NOT THE ONE THAT WENT IN |
| 1 (DUP) | 3097 | A def that returns a BARE INDEX DISCARDS ITS ARENA |
| 2 (DUP) | 3132 | AN ELISION MUST HAND BACK THE ARENA IT WAS GIVEN |
| 3 (DUP) | 3148 | A DTYPE PROJECTION IS NOT IDEMPOTENT |
| 4 (DUP) | 3166 | `F32.to_u32` IS A TRUNCATION IN THE NATIVE LANE AND UNFOLDED IN THE INTERPRETER |
| 5 (DUP) | 3191 | A SELF-CALL NEEDS `Nat` FUEL FIRST, AND THE FUEL IS NOT THE COUNTER |
| 6 (DUP) | 3220 | TWO dtype GUARDS ON THE SAME VALUE ARE NOT NEGATIONS OF EACH OTHER |
| 7 (DUP) | 3231 | A `match` MAY NOT SCRUTINISE A CALL, SO A dtype TEST IS A PARAMETER |
| 8 (DUP) | 3242 | WRITE FLOAT COEFFICIENTS AS FULL DECIMALS, AND NEGATIVES AS `F32.neg` |
| 1 (DUP) | 3298 | A `do IO<Unit>:` BODY MUST END WITH A BARE TERM, NOT A `<-` BINDING |
| 2 (DUP) | 3307 | A SELF-CALL MUST BE LEXICALLY INSIDE THE DEF THAT OWNS THE FUEL MATCH |
| 3 (DUP) | 3316 | A RECURSIVE ARENA REBUILD MUST BE BUILT ON THE INNER NODE'S ARENA |
| 4 (DUP) | 3324 | `Maybe.map(&2, T, ...)` NEEDS A `Data` RESULT, AND `.bind` READS DIFFERENTLY |
| 5 (DUP) | 3330 | `O.ParamArg`'s FIELD ORDER IS NOT THE PROSE ORDER |
| 6 (DUP) | 3340 | A `Data` UNION'S CONSTRUCTORS ARE CONSTRUCTORS, NOT NAMES -- AND `O.OpsCMPLT{}` IS ONE |
| 7 (DUP) | 3350 | A RECURSION WITH A BOUND AND NO COUNTDOWN STOPS ON THE EMPTY TAIL |
| 8 (DUP) | 3358 | `dtype.bend`'s FOURTEEN SEAMS MAKE EVERY IMPORTER RED, AND `@unsafe` IS NOT THE FIX |
| 9 (DUP) | 3467 | `F32` HAS NO SOURCE-LEVEL OPS, NO NEGATIVE LITERALS, AND IEEE `is_eq` |
| 10 | 3499 | FOUR MORE, ALL MEASURED BY THE `codegen/opt` UNIT (2026-10-02) |
| 11 | 3516 | FIVE MORE, ALL MEASURED BY THE `nn/state` + `nn/__init__` UNIT (2026-10-02) |
| 1 (DUP) | 3572 | A LIST OF `Bool` IS NOT A USABLE TYPE |
| 2 (DUP) | 3593 | A PATTERN BINDER MUST NOT SHADOW A DEF NAME, and the error names the CONSTRUCTOR |
| 3 (DUP) | 3608 | `+` ON A PATTERN BINDER IS THE SPELLING FOR "TWO READS IN ONE EXPRESSION" |
| 4 (DUP) | 3625 | A NESTED `match` ARM MAY NOT CALL A `Type.def` |
| 5 (DUP) | 3639 | A DEF MAY NOT CALL A NAMESPACE THAT A PARAMETER SHADOWS |
| 6 (DUP) | 3652 | `case True{} True{}:` IS A FINE ARM AND `case _ _:` AFTER IT IS FINE, BUT A `+` PARAMETER AND A  |
| 7 (DUP) | 3662 | A `U32` THAT IS BOTH A LOOKUP KEY AND A FALLBACK VALUE BELONGS IN THE NODE |
| 1 (DUP) | 3704 | `case 1n+p:` DESTROYS THE SCRUTINEE — THE ARM CANNOT READ THE CURRENT COUNT |
| 2 (DUP) | 3723 | SPLITTING A SELF-RECURSIVE STEP TO AVOID A DOUBLE READ CREATES MUTUAL RECURSION |
| 3 (DUP) | 3740 | `Bool` HAS NO `U32.show`, AND THE CONVERSION IS `Bool.pick` — THERE IS NO `Bool.match` |
| 4 (DUP) | 3751 | `String.join(xs, sep)` TAKES THE LIST FIRST, AND `String.concat(xs)` TOO |
| 5 (DUP) | 3758 | `IO.print` TAKES A `String`, AND A `do IO<Unit>` BLOCK CAN ONLY BIND AN `IO` |
| 6 (DUP) | 3765 | `List.take(xs, 0n)` IS THE EMPTY LIST AND `List.append(a, A, xs, ys)` IS `xs ++ ys` |
| 7 (DUP) | 3773 | A FIXTURE MUST INTERN ITS SHAPE ARGS THROUGH ONE BUILDER, AND A LIST OF RAW INTS IS NOT A LIST O |
| 11 (DUP) | 3789 | AN ARGUMENT IS EVALUATED BEFORE THE CALLEE BRANCHES, SO AN INTERNING INSIDE AN ARGUMENT BUILDS A |
| 12 | 3804 | A `list` SELF-CALL MAY PASS A LIST TAIL FIRST AND A `U32` ARENA SECOND, AND THAT IS THE ONLY ORD |
| 13 | 3820 | THE "INTERN ONCE, READ TWICE" FIX IS MUTUAL RECURSION IN A WALK |
| 14 | 3834 | A GATE ROW THAT PRINTS A `srcops` SEQUENCE MUST PUT ALL FOUR FACTS IN ONE STRING |
| 15 | 3844 | A SHAPE ARG BUILT BY A WALK MUST APPEND, AND THE BUG IS INVISIBLE IN THE COUNT |
| 16 | 3854 | `Arena.node` ANSWERS THE BOTTOM FOR AN INDEX PAST THE END, SO A STALE ARENA GIVES AN EMPTY ANSWE |
| 17 | 3862 | A GATE MUST HAVE A NON-MOVEMENT FIXTURE OR A `match`'s CATCH-ALL ARM IS DEAD CODE |
| 18 | 3883 | AN UNANSWERABLE NODE POISONS ITS CONSUMERS, SO "CAN THE FOLD ANSWER X" IS A PROPERTY OF THE WHOL |
| 19 | 3921 | A FOLD THAT NEEDS AN INDEX MUST USE `Arena.srcs`, NOT A COUNT AND A RE-DERIVED INDEX |
| 20 | 3940 | A LIST-OF-STRINGS FOLD MUST END IN `String.join`, NOT IN A BAKED-IN SEPARATOR |
| 21 | 3959 | `+r = R{a, b}` NEEDS AN ANNOTATION; `+r = f(...)` DOES NOT |
| 22 | 3977 | A BYTE-DIFFED GATE MUST NOT INHERIT A PRINTER WHOSE OUTPUT HAS TRAILING WHITESPACE |
| 23 | 3990 | THE `int_*_new` SHAPE -- "HOW MANY DID THE SECOND CALL MINT" -- IS A ROW CLASS OF ITS OWN, AND I |
| 1 (DUP) | 4024 | AN ARENA IS AFFINE, SO A DEF THAT BUILDS **GROWS A COPY** -- AND THE FIX IS TO THREAD `+ar` THRO |
| 2 (DUP) | 4057 | A `U32` LITERAL PATTERN IS A PREFIX MATCH **FOR THE SUCCESSOR RELATION ONLY**, SO `case 8:` DOES |
| 3 (DUP) | 4078 | `mxw_reshape` / `mxw_shrink` / `mxw_pad` BUILD A `STACK` FOR A ONE-ELEMENT SHAPE ARG AND CPYTHON |
| 4 (DUP) | 4104 | `+p: F32` IS ACCEPTED, SO THE `U32` "TWO READS NEED A RECORD" RULE IS NOT A `U32` RULE |
| 5 (DUP) | 4113 | `+dev: S.Dev` ON A `Data` PARAM IS FREE AND A GLOBAL `+` SWEEP IS THE FASTEST FIX FOR A WHOLE FI |
| 6 (DUP) | 4123 | A `def X.of` CHAIN MUST BE DECLARED LEAF-FIRST **AND** `X.of` MUST IMMEDIATELY PRECEDE `X` -- SO |
| 7 (DUP) | 4139 | `def f.g` and `def F.g` ON A LOCALLY-DECLARED `Data` RECORD NEED A READER DEF, A FIELD PROJECTIO |
| 8 (DUP) | 4149 | THE ORACLE'S `print("k=", v)` HAS A TRAILING SPACE AND IT IS HALF THE DIFF |
| 9 (DUP) | 4159 | A `.bend` FILE CAN `ALL PROOFS CHECK` IN BOTH LANES, PRINT LANE-IDENTICAL OUTPUT, AND STILL BE W |
| 24 | 4174 | `Emit` AND `Halt` BELONG TO BASE's `IO.OP` — A LOCAL `type Emit` IS A DUPLICATE |
| 25 | 4192 | `volatile` IS A RESERVED WORD AND CANNOT BE A FIELD NAME |
| 26 | 4221 | A FIELD IS READ `Type.field(value)` -- THERE IS NO `value.field` SUGAR |
| 27 | 4242 | THERE IS NO AUTO-GENERATED FIELD PROJECTION AT ALL -- AND RULE 26's `T.mutable(t)` EXAMPLE IS WR |
| 28 | 4289 | A `Bool` PARAMETER DOES NOT MAKE A TWO-DEF SPLIT OF ONE RECURSION LEGAL -- IT IS STILL MUTUAL RE |
| 29 | 4321 | `+` ON A LATER PARAMETER DOES NOT DISTURB THE DECREASE CHECK ON THE FIRST ONE |
| 30 | 4335 | `+` ON A `U32` IS FREE, AND A `Nat` `match` WITH `case 0n:` THEN `case 1n+m:` IS THE WHOLE COUNT |
| 31 | 4348 | NO LIST COMPREHENSIONS -- BUT CLOSURES EXIST AND `List` IS FULLY ERGONOMIC |
| 32 | 4385 | `List.foldl` REPLACES THE HAND-ROLLED `.go` ACCUMULATOR PAIR — WITH ONE TRAP |
| 1 (DUP) | 4440 | A `Bool` PARAMETER IS AFFINE TOO -- `+hit: Bool` is ACCEPTED AND IS OFTEN WHAT YOU WANT |
| 2 (DUP) | 4449 | `go`/`put` IS NOT A `.of` SPLIT: IT IS MUTUAL RECURSION, AND A LIST-TAIL FOLD WITH A HEAD THAT I |
| 3 (DUP) | 4467 | `T.tn_len` IS `shape[0]`, NOT `numel` -- AND IT ANSWERS A `Sint`'s ARENA INDEX, NOT ITS VALUE |
| 4 (DUP) | 4477 | `H.dedup_u32` BUILDS ITS ANSWER IN REVERSE, AND NO ROW IN THE TREE NOTICES |
| 5 (DUP) | 4490 | `T.tn_dims` ANSWERS A SHAPE AND `List.is_empty` ON IT ANSWERS `_shape == ()`, WHICH IS THE LAST  |
| 6 (DUP) | 4503 | `List.drop(&2, U32, xs, U32.to_nat(n))` IS A POSITIONAL SLICE, AND A HAND- WRITTEN FILTER THAT C |
| 7 (DUP) | 4515 | A `.of` LEAF THAT IS ONLY EVER CALLED FROM ONE PLACE STILL COSTS A ROW, AND THE HONEST MOVE IS T |
| 8 (DUP) | 4525 | THE `Data` RECORD FOR "A FOLD THAT ANSWERS A LIST AND A FACT ABOUT IT" IS NOW FIVE INSTANCES IN  |
| 1 (DUP) | 4541 | THE `.of` SPLIT IS REQUIRED AT **EVERY** SCRUTINEE POSITION, NOT ONLY AT THE TOP OF A BODY |
| 2 (DUP) | 4559 | A PATTERN BINDER THAT SHADOWS A **FIELD NAME** IS REPORTED AS AN ARITY ERROR |
| 3 (DUP) | 4580 | `+` ON A `U32` THAT IS THE **FIRST** ARGUMENT OF A LIST-TAIL SELF-CALL CHECKS |
| 4 (DUP) | 4600 | A GATE **COLUMN** THAT IS CONSTANT OVER THE WHOLE SUITE IS A COLUMN NO MUTATION CAN MOVE |
| 5 (DUP) | 4617 | A CHAINED REDUCE SEPARATES FIRST-WINS FROM LAST-WINS **ONLY IF THE TWO OPS DIFFER** |
| 6 (DUP) | 4633 | A MUTATION DESCRIBED AS "DROP THE GUARD" MAY BE SOMETHING ELSE ENTIRELY, AND ONLY THE VALUE SAYS |
| 1 (DUP) | 4655 | A COUNTDOWN ARM MAY NOT SO MUCH AS READ ITS OWN FUEL -- AND THE ESCAPE IS A `+U32` THAT GROWS |
| 2 (DUP) | 4680 | `List.append(A, R, rec(t), [x])` IS `reverse`, NOT A BUG -- IT IS `rec(t) ++ [x]` |
| 3 (DUP) | 4702 | `U32.shln(a, n)` IS `a << n` -- BUT `U32.shl(a)` IS `a << 1`, SO `shln(a, 0n) = a` |
| 4 (DUP) | 4712 | A U32 SENTINEL FOR A PYTHON `default=-1` MUST NOT BE `0xffffffff` WHEN THE FOLD IS `max` |
| 5 (DUP) | 4732 | `sub(b) <= sub(a)` IS `sub(a, b)` WITH THE ARGUMENTS BACKWARDS, AND `<=` READS THE OTHER WAY |
| 6 (DUP) | 4741 | A `match` ON A `String` NEEDS THE ARM ORDER OF THE LITERAL, AND A MISSING `"gfx942"` ARM IS DEAD |
| 7 (DUP) | 4750 | A GATE'S ORACLE MUST REPRODUCE `IO.print`'s OWN NEWLINE, OR THE LAST ROW NEVER MATCHES |
| 8 (DUP) | 4760 | TWO SELF-CALLS IN ONE ARM ARE LEGAL WHEN EVERY SHARED ARGUMENT IS `+` |
| 9 (DUP) | 4768 | `do` IS A RESERVED WORD AND CANNOT BE A RECORD FIELD |
| 1 (DUP) | 4789 | `Pair` IS A BASE CONSTRUCTOR, SO A TWO-FIELD `Data` RECORD NEEDS A NEW NAME |
| 2 (DUP) | 4799 | A UNION CONSTRUCTOR IS NOT A TYPE, SO A READER FOR ONE ARM CANNOT BE WRITTEN |
| 3 (DUP) | 4818 | A FOLD OVER A FUNCTION PARAMETER IS IMPOSSIBLE, SO A TABLE ROW IS AN EXPLICIT LITERAL |
| 4 (DUP) | 4835 | A `U32` LITERAL ARM LADDER MUST BE IN DESCENDING ORDER |
| 5 (DUP) | 4845 | `H.I64` HAS NO `Word`, SO `floor(x/2)` IS HAND-WRITTEN -- AND THE LOW WORD'S FILL COMES FROM THE |
| 6 (DUP) | 4864 | `helpers.bend`'s `i64_add` AND `i64_sub` NEITHER CARRY NOR BORROW -- REPORTED, NOT FIXED |
| 7 (DUP) | 4885 | A FIRST-WINS `Any` GUARD INSIDE AN ELIGIBILITY FOLD IS A BUG THE FIX MAKES WORSE |
| 8 (DUP) | 4901 | A COUNT ROW AND THE TABLE IT COUNTS ARE TWO INDEPENDENT TRANSCRIPTIONS |
| 9 (DUP) | 4914 | AN UNUSED `+` PARAMETER IS ACCEPTED, SO A MUTATION CAN FIND A PARAMETER THAT IS NOT LOAD-BEARING |
| 32 (DUP) | 4930 | **`Bool.pick` IS STRICT *AND* IT IS AFFINE-TOO, SO A BRANCH THAT BUILDS A STRUCTURE MUST BIND IT |
| 33 | 4958 | **A `.go`/`.step` SPLIT OF ONE SELF-RECURSIVE FOLD IS MUTUAL RECURSION AND IS REFUSED; THE `If`  |
| 34 | 4974 | **A `U32` HAS NO CONSTRUCTORS, SO `case 0: ... case 1: ... case _:` ON A `U32` IS "a declared co |
| 35 | 4986 | **`Wv{Bool, U32}` IS THE ANSWER TO "A `Maybe` BOTH ARMS OF A `Bool.pick` NEED", AND IT IS NOT A  |
| 36 | 5008 | **A `String` IS NOT `List<&2, Char>` -- `List.length(&2, Char, s)` IS A TYPE ERROR, AND `String. |
| 37 | 4930 | **AN ASSOC-LIST PUT WHOSE MISS ARM RETURNS THE TAIL IS A SILENT `del`** |
| 38 | 5013 | **`Bool.and`/`Bool.or` DO NOT SHORT-CIRCUIT, SO PYTHON'S `or` IS A `Bool.pick`** |
| 39 | 5030 | **A `Bool.pick` CANNOT GATE A MUTATING CALL, AND A `match` CANNOT BRANCH ON A CALL -- SO THE VERDICT IS A ONE-FIELD RECORD AND THE `match` TAKES A BINDER** |
| 40 | 5057 | **A BARE PARAM IS LONE AND A `+` PARAM IS DROPPABLE; EVERY VALUE IN BOTH ARMS OF A `Bool.pick` MUST BE `+`, AND A `List.sort` COMPARATOR MUST READ EACH ARGUMENT ONCE** |
| 41 | 5080 | **A 3-ELEMENT CONS COVER DOES NOT COVER THE 1- AND 2-ELEMENT LISTS, AND THE ERROR POINTS AT THE `Nil{}` ARM** |
| 42 | 5098 | **A `List` ACCUMULATOR WALK NEEDS THE SHRINKING BINDER BEFORE THE FIRST CALL** |
| 43 | 5113 | **A MULTI-LINE RECORD LITERAL, OR A CALL INSIDE ONE, IS REFUSED AND THE ERROR POINTS AT THE NEXT `def`** |
| 44 | 5124 | **A PYTHON `None` IN A `U32` FIELD IS A SENTINEL OUTSIDE THE KEY SPACE PLUS A NAMED PREDICATE, AND EVERY MEMBERSHIP TEST MUST GO THROUGH IT** |
| 37 | 5021 | **A PARAMETER MAY NOT SHADOW A DEF NAME, AND THE ERROR NAMES THE CONSTRUCTOR** (an extension of  |
| RF1 | 8148 | **A `.f()` CHAIN PUTS THE OP PASSED TO `f` AT THE PATTERN'S ROOT, SO `pdict`'s KEY IS THAT ONE AND NOT THE RECEIVER'S** |
| RF2 | 8158 | **`Bool.and(x, True{})` IS `x` AND `Bool.or(x, True{})` IS `True{}`, SO A FOLD WITH AN ALL-TRUE BASE IS NOT A SUBSET TEST UNDER `or`** |
| RF3 | 8172 | **A FIXTURE WHOSE EVERY NODE HAS AN `ANone` ARG CANNOT GATE AN ARG-BEARING REWRITE, AND THE FIXTURE THAT FIXES IT IS NOT THE OBVIOUS ONE** |
| RF4 | 8184 | **A GATE THAT FOLDS `F.folded(ar)` OVER AN ARENA SNAPSHOT CANNOT READ A NODE INTERNED AFTER THAT SNAPSHOT** |
| RF5 | 8192 | **A CALL THAT FORGETS ONE ARGUMENT TO A `def X.n` READS AS A PARTIAL APPLICATION, AND RENAMING EVERYTHING DOES NOT CHANGE THE MESSAGE** |
| RF6 | 8200 | **A RULE BODY WITH NO PATTERN TEST OF ITS OWN IS A HOLE, AND THE MUTATION THAT FINDS IT MAKES A REJECT SET VACUOUS** |
| RF7 | 8210 | **A STUB ARM THAT IS A CONSTANT IS A CLAIM ABOUT THE WHOLE DATATYPE, AND `Bool.not` OF IT INVERTS THE TEST** |

**11 numbers repeat: 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 32.**  The seven rules measured
while fixing `schedule/rangeify.bend`'s `ct` table are numbered `RF1`-`RF7` and start
at LINE 8146 of this file, because the integers in the series above are taken.

    ./bin/bend FILE.bend              # check, then run main (interpreted)
    ./bin/bend FILE.bend -o FILE      # compile to a native binary, run it
    ./bin/bend FILE.bend --check-only # check only
    ./bin/bend PROOF.bend             # the laws gate

---

## 1. The five rules that shape every line of the port

### 1.1 Affinity: a value is used at most once

The default binder `x: T` means *Lone* — at most one use. Reusing it is a
type error:

    def c2():
      TLam{f => TLam{x => TApp{f, TApp{f, x}}}}
    #| - expected : f
    #| - observed : f (consumed more than once)

* `+x: T` licenses many uses, but **only if `T` is `Data`**. It costs a
  runtime reference count, not a copy.
* `Type`-kinded things are *never* copyable: function values, `Array<T>`,
  every handle (`File`, `Socket`, …), `IO<A>`, and any datatype declared
  `is Type` — regardless of what its fields are.
* Dropping a value is free. Only *reusing* one is an error.
* Matching a `+` value hands out `+` fields. To make a field of a plain
  value reusable, write `+name` in the pattern.

tinygrad reuses values constantly (`self.src[0]` twice, a UOp in two
dicts), so this is the #1 source of port friction and the #1 thing for a
reviewer to check.

### 1.2 Scrutinees follow binder order

**This is the trap that costs the most time.** A `match` may inspect a
parameter or a pattern binder, never a projection and never a computed
value — *and the scruts must be matched in the order they were bound.*

    type Dt is Data:
      Dt{pri: U32, bits: U32, sgn: Bool, fl: Bool, nm: String}

    # FAILS: fl is field 4, sgn is field 3 -- out of order
    match d:
      case Dt{pri, bits, sgn, fl, nm}:
        match fl:            # <- 4th
          case False{}:
            match sgn:       # <- 3rd, rejected
    #| - message : a match on a parameter or field
    #|             (this name is a def or a consumed binder: give the value its own def)

    # WORKS: in binder order
    match sgn fl:            # <- 3rd then 4th
      case True{} True{}:  None{}
      case True{} False{}: Some{bits}
      case False{} True{}: None{}
      case False{} False{}: Some{0}

Matching **two fields at once** (`match a b:` / `case P Q:`) is the
idiomatic fix, and the checker verifies the rows are exhaustive.

Related, same family:

* A projection (`d.fl`) is not a valid scrutinee — destructure first.
* A computed value is not a valid scrutinee (`match f(x):`). Give it its
  own `def` and match the parameter.
* A `let`-bound name is not a valid scrutinee either.
* A `match` **must head the def body**. It cannot appear inside a `do`
  block: hoist the match out, and return a `do` block from each arm.
* A nested `match` inside a `case` arm is fine.

### 1.3 Operators need their type in the enclosing parens

    (a + b : U32)      # U32.add(a, b)
    (a .&. b : U32)    # U32.and  -- bitwise is DOTTED
    (a << n : U32)     # U32.shln -- the shift count is a Nat
    (a >> n : U32)     # U32.shrn -- LOGICAL; saturates to 0 past 31

Braces do **not** namespace: `{2n * 3n : Nat}` is rejected. A bare operator
is rejected. Space both sides — `>>` glued to a non-space never fires, and
`+`/`-` glued to a name heads a binder, which is why `1n+p` is a `Nat`
literal and not addition.

### 1.4 No `if`, and no `return` in a pure def

`if` is an ordinary identifier now. A branch is a `match` on `True{}` /
`False{}`, usually in its own helper. A pure `def` body is just a term;
`return` only exists inside a `do` block.

### 1.5 Recursion must visibly descend

The checker requires each argument of a self-call to be passed unchanged
until one is a structurally smaller part of its parameter. Almost no
tinygrad loop satisfies this, so the escape is:

    @unsafe                      # on its OWN LINE, above the def
    def fib(n: U32) -> U32:      # or the sugar `def fib?(n: U32) -> U32:`
      ...

`@unsafe` also lifts mutual recursion and the "call a def declared below
me" restriction. A file using it prints `SOME PROOFS FAIL` and names every
def that relies on it — that is the price, and it is the right one, because
it is greppable. **Every `@unsafe` must be recorded in `AFFINITY.tsv`** with
why the termination check cannot apply, and a reviewer must reject any new
one that is not on the list.

`bend f.bend -o f` compiles `@unsafe` code happily; only the *check*
complains.

---

## 2. The numeric situation: this is the good news

Bend has **only `Nat`, `U32`, `F32`**. No signed integers, no 64-bit, no
`f16`/`f64`. But:

**`F32` arithmetic works natively.** The `law F32.add: ...` declarations in
`base.bend` are not missing implementations — they are *axioms* the
compiler recognises and emits as intrinsics. Verified:

    F32.add(1.5, 2.25) = 3.75      F32.sqrt(2.0) = 1.4142135
    F32.div(1.0, 0.0)  = inf       F32.exp(1.0)  = 2.7182817
    F32.log2(8.0)      = 3          F32.sin(0.5)  = 0.47942555
    F32.bits(1.0)      = 1065353216  F32.to_u32(2.9) = 2
    U32.to_f32(3)      = 3          F32.is_lt(1.5, 2.25) = True

So the whole float layer is free. Two consequences:

* **F32 laws are unprovable.** The guide is blunt: "F32 is axiomatic:
  nothing about floating point can be proven." So `LAWS.bend` must not
  claim anything about `F32` arithmetic, `exp`, `log`, `sin`, … It can
  claim things about *shape* and *structure*, which is where the spec's
  content actually is. Stated as a rule in the master plan.
* **Bend's own `F32` laws cannot be filled from outside** — `def F32.add`
  is a duplicate declaration, and `def Base.F32.add` is "no law named
  Base.F32.add is in scope". So do not try; just use them.

`Nat` is **unary** (`Zero{}`/`Succ{pred}`) and capped at 2^48-1. It is fine
as a small tag and a recursion counter, and a wrong choice for tensor
indices. `U32` it is, with `Nat` only where the spec is naturally
symbolic (axis numbers, sizes, `Nat` in the `lawof` positions).

Integer semantics, all verified or read off the intrinsics:

* `U32.add/sub/mul` **wrap** mod 2^32. `U32.sub(0, 1) = 4294967295`.
* `U32.div(a, 0) = 0` and `U32.mod(a, 0) = a` — the dividend, not a trap.
  This matches tinygrad's `floordiv`/`floormod` on a zero divisor, but it
  does **not** match C, so generated C must guard.
* `U32.shl/shr` shift by one; `shln/shrn` take a `Nat` and saturate to 0
  past 31. **Both are logical** — there is no arithmetic shift, which
  `divides`/`const_factor`/`_min_max` all need. Write `asr` by hand:

      def asr(+v: U32, n: Nat) -> U32:
        U32.or(U32.shrn(v, n), U32.shrn(U32.shrn(v, 31n), n))

* No rotate, no popcount, no leading/trailing zeros. `U32.log2` exists.
  `threefry` and the SHA/KECCAK round need these; they get written.

## 3. The collections situation

* `List<T>` is a singly-linked list. `List.length(a, -A, xs)` takes the
  **quantity as the first argument**, so `List.length(&1, U32, xs)` and
  `List.length(&2, U32, xs)` are different calls. Easy to get wrong.
* `Map` is string-keyed only. You cannot key it by `U32`. For a UOp arena
  keyed by node index, use an `Array` of options, not a `Map`.
* `Array<T>` is a persistent balanced tree (`ALeaf`/`ANode`), **not** a
  flat buffer. `a[i]` is `Array<U32>`-only and wraps the index; other
  element types need `Array.get`/`Array.swap`/`Array.set`. `Array.clone`
  is the explicit deep copy. It is `is Type`, so it has exactly one owner
  and can never be duplicated for free.
* **`Maybe<&2, T>` demands a `+` (reusable) payload.** If the payload is
  affine, use `Maybe<&1, T>`. Getting this backwards produces a misleading
  "a match on a parameter or field" error several lines away from the real
  cause. This cost real time; it is listed here so it costs nobody else
  time.

## 4. Effects, and where tinygrad's `runtime/` lands

A foreign effect is a `def` returning `IO(R)` whose whole body is two
imports:

    def Clock.now() -> IO(U32):
      import "./clock.c"
      import "./clock.js"

Verified working in both lanes (`bend f.bend` and `bend f.bend -o f`).
Rules that matter:

* The **return type must be spelled `IO(...)`** — "return type aliases are
  not unfolded". So an effect cannot return a type alias.
* The `.c` file registers `io_eff(CID(Name), run, need)`. `CID(Name)`
  resolves in the *declaring file's* namespace first. `#ifdef CID(Name)`
  tests whether the program uses it at all.
* Return a `Bool` as `term_pak(CID(True{}), 0)` — but `CID_BOOL` is only
  defined if the program uses `Bool`, so prefer returning a `U32` and
  converting in Bend.
* Arguments: a `U32` is `(u32)f[0]`, a `String` via `io_cstr(e, f[0], &n)`
  (a `malloc`ed copy you free), a handle via `io_hand_v(f[0])`.
* `Process.run` works and is how the port reaches `clang`, exactly as
  tinygrad reaches it. Verified end to end.
* A user handle type is a **WONTFIX** (`WONTFIX.txt` #825): handle types
  are laws only Base may leave unfilled. Workaround: reuse a Base handle
  law and put a pointer or an `(index, generation)` pair in the 56-bit
  value. `chan.c` is the reference for the generation scheme.

### The boundary this draws in the port

| tinygrad | goes where |
| --- | --- |
| `dtype`, `helpers`, `uop/spec`, `uop/symbolic`, `schedule`, `codegen`, `renderer/cstyle` | **pure Bend** — string building is `String.append`, and the laws live here |
| `runtime/*`, `device.py`, memory, the compiler subprocess | **C effects** — exactly as tinygrad uses ctypes and shells out to clang |
| `ops_cpu` LLVM path | **dropped**, use `clang`. tinygrad already prefers `ClangRenderer`; deleting `CPULLVMRenderer` from the renderer list is the whole change |

## 5. The test format, which the port must adopt

Every `tests/<ns>/*.bend` file ends with the `#|` lines its run must print.
`#|` is not syntax; it is the expectation. So the port's own test harness is
"a `.bend` file plus its expected output", which is a good fit: the ported
`test/` can keep tinygrad's *file* structure while Bend's checker does the
comparison.

## 6. The one architectural decision the laws forced

`uop/ops.py` hash-conses UOps through `UOpMetaClass.ucache` keyed on
`(op, src, arg, tag, type(arg))`, and the range graph has **back-edges**, so
the graph is cyclic. `UOp.__eq__` is deliberately **identity**, and the test
suite leans on it (`assertIs`, `id(uop)`, `toposort` ordering).

So the compilation IR **cannot** be a pure inductive tree. It must be an
arena: a UOp is a `U32` index into an append-only table, which gives O(1)
identity, O(1) sharing, and cycles. That is also what tinygrad itself does
(`UOp.unique_num` is a monotonic slot counter that must never be reset).

Consequences, and they are expensive:

* `UOp` as a `U32` is `Data`, so handles are freely copyable at zero cost —
  the DAG-sharing problem disappears. This is the one place Bend's model is
  *better* than Python's.
* The arena is affine (`Array`), so exactly one owner exists and it must be
  threaded explicitly through every function as `(ctx, value)`.
* Therefore **the laws cannot cover the compilation IR.** They cover the
  *pure spec IR* in `bendgrad/LAWS/spec.bend`, which is a tree and whose
  derived properties (dtype, shape, device, addrspace, min_max) are total
  functions of the node. That is exactly what `spec/tinyspec.tex` states,
  so nothing is lost — but it is why `LAWS.bend` is a separate artefact
  from the arena.
* ~~A rewrite rule needs the arena, so it cannot be a closure (a closure is
  single-use and cannot capture an affine value). Rules become **top-level
  `def`s taking and returning `ctx`**, dispatched by an explicit tag.~~

  **RETRACTED — the capture half is false.** A closure captures an affine `Nat`
  fine; see "Closures: capturing is fine, STORING is the constraint" at the end
  of this file. Rules stay lambdas.

  What survives is narrower: a **function value in a datatype field forces
  `Type`, not `Data`**, so the rule TABLE is linear and one walk consumes it.
  `graph_rewrite` is called many times, so it cannot take the table as a
  parameter — it builds one per call, or takes a thunk that makes a fresh one.
  That is one function signature, not a restructuring of the rule language, and
  `PatternMatcher` is closer to a mechanical transliteration than this note
  claimed.

## 7. Reviewer checklist for the port

Reject a change that:

1. adds an `@unsafe` not in `AFFINITY.tsv`;
2. introduces a `+` where the type is not `Data` (or vice versa — a missing
   `+` that forces a copy, or a spurious one that leaks a reference);
3. branches on a value out of binder order, or on a projection/computed
   value;
4. reimplements something `base.bend` already provides — check
   `bend base` and `bend base --types` first;
5. silently changes behaviour when the Python raised or returned `None` —
   the port has no exceptions, so a Python `RuntimeError` is `IO.die`, and a
   Python `None` is `Maybe`. Neither is optional.
6. drops a Python edge case. tinygrad's spec has *tri-state* rules (accept /
   no-opinion / reject) and its tests assert exact kernel counts and exact
   `repr` strings. Both are behaviour and both are covered by tests that
   must keep passing.

## Explicit fuel instead of @unsafe (measured on 2.0.34)

The project rule is that any Turing completeness must be approved first, and the
answer was no `@unsafe`: thread a `Nat` fuel argument instead. Four facts, each
established by bisection against the pinned compiler, not by reading the guide.

1. **Fuel is the FIRST parameter.** The decrease check reads a recursive call's
   arguments left to right, stopping at the first that is a strict subterm of its
   corresponding parameter. Put the shrinking argument first. Everything after it
   is free.

2. **`case 2n+p:` yields TWO independent strict subterms.** That is how one arm
   makes two decreasing calls: one takes `n`, the other `p`. Marking either `+`
   *breaks* the check -- a reusable binder stops counting as a subterm. Two
   calls, two ordinary binders.

3. **The checker only honours `2n+p` when a `1n+p` sibling is present.** A def
   whose only fuel arm is `2n+p:` is rejected; add `case 1n+p: f(p, i)` and it
   passes. The sibling need not be reachable in practice. bendgrad/LAWS/spec.bend
   makes it meaningful: odd fuel burns one unit and re-enters, so fuel is counted
   in pairs and a caller with an odd budget is rounded down rather than lied to.

4. **A recursive call must be a tail expression, or bound to a local first.**
   `pair(go(..), go(..))` fails; `hd = go(..)` then `tl = go(..)` then
   `pair(hd, tl)` also fails when the def returns a `Maybe`; the reliable form is
   one self-call per arm with a single binder, or the `2n+p` pair above.

What all of this rules out: mutual recursion. Two functions that call each other
cannot both be checked, so the shape and dtype folds are ONE def each over a
type that covers both cases:

    type Item is Data:
      One{s: Sp}          # a node
      Many{xs: List<&2, Sp>}   # a list, for Index's index list and Stack's operands

The guide says exactly this -- "two mutually recursive functions become one def
with an extra argument selecting which to run" -- and `Item` is that argument.

Cost: every call site now passes a depth. A caller that under-counts gets
`None`, which is the honest answer for "past this depth the property is
unknown", never a wrong shape.

## Correction: numeric patterns are first-match prefix matches

The fuel section above is wrong in its central claim, and the mistake cost a
commit. Measured, not read:

```
match fuel:
  case 0n: 0
  case 1n+p: 1
  case 2n+p: 2
  case 3n+p: 3

fuel 0..4  ->  1 1 1 1 1      # 1n+p claims every successor
```

`1n+p` matches ANY positive Nat. `2n+p` is not a disjoint "even" case; it is
"at least 2", and it only fires if it is listed *before* `1n+p`. Swapping the
arms gives `2 2 2 2 2`. So any `case 2n+p:` placed after `case 1n+p:` is dead
code that still typechecks — and a fold built that way answers `None` for
everything, because fuel walks down to zero one unit at a time.

Also: `2n+p` binds **only** `p`. The `2n` is a literal, not `2` times a binder.

## The real rule for a descent

Two facts, both established by bisection:

1. **A recursive call must be a tail expression, or bound to a local first.**
   `ca(go(a), go(b))` is rejected; `x = go(a)` then `y = go(b)` then `ca(x, y)`
   is accepted.
2. **A recursive call must pass a field of its own parameter**, either bare or
   re-wrapped in the *same* constructor. `go(One{t})` from `One{Pas{t}}` is
   fine. `go(Pair{Node{l}, Node{r}})` from `Node{Bin{l,r}}` is rejected — a
   constructed sibling is not a subterm.

Together these mean: **every recursive call needs its own field.** Which in
turn means a fold that maps a recursive function over a list, and then combines
the results, is impossible without fuel — because the head and the tail come
out of ONE destructured list and so share a binder. `+` on that binder stops it
counting as a subterm. There is no arrangement that avoids this.

Bounded arity sidesteps it entirely and needs no fuel at all:

```
type Sp is Data:
  Buf{v: U32}
  Idx2{t: Sp, a: Sp, b: Sp}
  Idx3{t: Sp, a: Sp, b: Sp, c: Sp}

def shape(s: Sp) -> Maybe<&2, U32>:
  match s:
    case Buf{v}: Some{v}
    case Idx2{t, a, b}:
      r = ca(shape(a), shape(b))
      ca(shape(t), r)
```

`ALL PROOFS CHECK`, no `@unsafe`, no fuel. Every descent is a distinct field.
Verified on both the interpreted and compiled lanes.

## Writing a Bend proof: the syntax that costs time

Measured while proving `Shape.max_dim(x, x) == x`. Each of these was a compile
error before it was a rule.

1. **A def with no return type is a law proof.** `def helper(v):` is parsed as
   "fill the law named `helper`". A plain helper must spell its type:
   `def nat_max_idem(+v: Nat) -> {Nat.max(v, v) == v : Nat}:`. The return type is
   an equation, so the helper is a proof of it.

2. **Binders used twice need `+`.** `def nat_max_idem(v)` then using `v` in two
   places is "consumed more than once". `+v` fixes it, at the cost of a refcount.

3. **The `%proof : P` motive is written against the goal AFTER the match, not
   before.** This is the one that cost the most. In

   ```
   case 1n+p:
     %ih : {Nat.max(p, p) == p : Nat}
   ```

   the goal is `1n+Nat.max(p, p) == 1n+p`, so the motive must be
   `{1n+Nat.max(p, p) == 1n+_ : Nat}`. Writing the pre-match equation is silently
   accepted and does nothing.

4. **Constructor names are module-qualified in motives.** Inside a motive you
   write `S.SN{...}`, not `SN{...}` — "expected a declared constructor
   (LAWS/spec.Sdim declares LAWS/spec.SN)".

5. **`Equal.cong(A, B, f, a, b, e)` congrues a function of ONE argument.** A
   two-argument `f` is refused. To lift a proof about a list tail into a proof
   about the whole list, fix the head first:

   ```
   def cons_head(h: Sdim) -> (List<&2, Sdim> -> List<&2, Sdim>): t => h <> t
   c = Equal.cong(List<&2, Sdim>, List<&2, Sdim), cons_head(Shape.max_dim(x, x)),
                  zip_max(xs, xs), xs, ih)
   ```

   `c`'s type is `{Shape.max_dim(x, x) <> xs == Shape.max_dim(x, x) <> xs}`.
   Getting from there to the goal needs a rewrite under a list constructor,
   which is rule 3's hard case — see `zip_max_idempotent` in `PROOF.bend`.

6. **A trailing comma at end of line breaks a call.** `Equal.cong(A, B,\n  f, ...)`
   is a parse error; keep the call on one line.

## Under a list constructor, congr and trans -- not `%` rewrites

Rule 3 above says a `%proof : P` motive is written against the goal after the
match. It does not say what to do when the rewrite target sits **under a list
constructor**. Measured on `zip_max(s, s) == s`:

Every `%ih : P` shape was **accepted and did nothing**:

- `{zip_max(xs, xs) == xs}` — goal unchanged
- `{zip_max(xs, xs) == _}` — goal unchanged
- `{md <> zip_max(xs, xs) == md <> _}` — goal unchanged
- `{_ <> xs == md <> xs}` — goal unchanged
- `{_ == x <> xs}` — lands on the wrong endpoint

What works is congruence plus transitivity. `Equal.cong(A, B, f, a, b, e)` is
the workhorse, and it has one hard requirement: **`f` must be unary**. A cons
has two arguments, so it is split by fixing one side:

```bend
def cons_head(h: Sdim) -> (List<&2, Sdim> -> List<&2, Sdim>): t => h <> t
def cons_tail(t: List<&2, Sdim>) -> (Sdim -> List<&2, Sdim>):  h => h <> t

c1 = Equal.cong(List<&2, Sdim>, List<&2, Sdim>, cons_head(md), zip_max(xs, xs), xs, ih)
c2 = Equal.cong(Sdim,            List<&2, Sdim>, cons_tail(xs), md, x, mh)
Equal.trans(List<&2, Sdim>, left, mid, end, c1, c2)
```

`c1` lifts the tail proof, `c2` lifts `max_dim`'s, they share the middle term
`md <> xs`, and `Equal.trans` does the substitution that `%` refused to.

Four more measured details, all of which cost an iteration:

7. **A bare `h <> t` as a local's right-hand side is "cannot infer"**, and so is
   one in a call argument. Route it through a typed `snoc(h, t)` def rather than
   annotating every use — `h <> t` also breaks the parser inside a `#` comment.
8. **`md`, `mh`, `zmx` all need `+`.** Each is used twice: once to build the
   congruence function and once in the `Equal.trans` endpoints.
9. **A nested call in an argument breaks the parser.** `cons_head(md)` written
   inline as `Equal.cong`'s third argument gives "expected a term, observed
   `)`". Bind it to a local first: `f1 = cons_head(md)`.
10. **A `def` with no return type is a law proof**, so a helper that shares a
    name with a law in scope must spell its type. `max_dim_idem` needed
    `-> {Shape.max_dim(x, x) == x : Sdim}` before it would parse as a helper.

The general lesson: **if a rewrite under a constructor is refused, reach for
`Equal.cong` and `Equal.trans` rather than more motive shapes.** The motive
grammar is for equalities that line up; congruence is for the ones that do not.

## Closures: capturing is fine, STORING is the constraint

An earlier draft of the master plan said closures "cannot capture affine values"
and prescribed restructuring every rewrite rule into a top-level def threading an
explicit ctx. **That was wrong**, and cost an afternoon to disprove. Measured:

```bend
# CAPTURING AN AFFINE VALUE: fine.
def maker(n: Nat) -> Rule:
  R{x => (x + U32.from_nat(n) : U32)}
```
`ALL PROOFS CHECK`, evaluates to 8. So tinygrad's `lambda x: ...` rules port as
lambdas. Do not restructure them.

What is actually true, and it is a real constraint, just a different one:

1. **A function value in a datatype field forces `Type`, not `Data`.**
   ```bend
   type Rule is Data:
     R{pat: Pat, f: (U32 -> U32)}     # REJECTED: expected Data, observed Type
   type Rule is Type:
     R{pat: Pat, f: (U32 -> U32)}     # ALL PROOFS CHECK
   ```
   Function types are linear, so a record holding one is linear.

2. **Therefore a table of rules is linear, and one walk consumes it.**
   ```bend
   def twice() -> U32:
     t = table()
     a = walk(t, 5)
     walk(t, a)      # REJECTED: t (consumed more than once)
   ```

3. **Pattern dispatch on a separate `Data` field is fine**, and the pattern can
   be matched by a helper that also calls the function:
   ```bend
   def apply(p: Pat, f: U32 -> U32, n: U32) -> U32:
     match p:
       case PSink{}: f(n)
       case PAdd{}:  f(n)
   ```

Two syntax rules that cost iterations and are not recorded anywhere:
- a `match` pattern with a **function-typed field** destructures as
  `case R{pat, f} <> rest:` — inline `case r:` then `match r:` is
  `a R pattern with 2 fields`;
- the same, an `apply`/`walk` pair must be ordered `apply` before `walk`, since
  a def may only call defs declared above it. The mutual shape (walk calls
  apply, apply mentions the type) is fine as long as it is not mutual.

WHAT THIS COSTS `uop/spec.py`, which is the reason it was worth measuring: the
rule list is walked once per `graph_rewrite` call, and `graph_rewrite` is called
many times over a graph. So `graph_rewrite` cannot take the table as a
parameter. It either constructs the table itself, or takes a thunk that makes a
fresh one each call. That is a question about ONE function signature -- not about
restructuring the rule language.

## THE ENGINE SHAPE for a rewrite rule table

Measured over thirteen wrong shapes. `.agents/slop/notes/engine-shape.bend` is a
working, runnable model — `ALL PROOFS CHECK`, and it prints `27` because the
arena ends as `[2, 7]` after two passes.

```bend
type Arena is Type: Nodes{items: List<&2, U32>}
type Rule  is Type: R{use: (Arena -> Arena)}

def engine_pass(rules: List<Rule>, a: Arena) -> Arena:
  match rules:
    case Nil{}: a
    case R{use} <> rest: engine_pass(rest, use(a))
```

**The rule returns the ARENA, not a pair.** This is the whole trick. Twelve
shapes failed before this one, and they all failed the same way:

- a rule returning `(Arena & U32)` works, but then the pass must `match` on the
  rule's result — and **a `match` may not scrutinise a computed value**, so
  `match apply(r, a):` is refused;
- giving it a helper def doesn't help, because the helper has to call back into
  the pass, and that is **mutual recursion**, which is also refused;
- ordering the helper above the pass just moves the error to
  `expected a filled definition ... observed use_go`.

Returning the arena removes the destructuring entirely, so there is no helper
and no cycle. ONE recursive def does it.

Three more rules this cost:

1. **`case R{use} <> rest:` destructures a rule in the cons position.** The
   nested `case r:` then `match r:` form is `a R pattern with 2 fields`.
2. **A `match` cannot head a lambda body either.** `R{a => match a: ...}` is
   refused; the rule calls a named helper, which must then be declared ABOVE it.
3. **The arena is `Type`, so a rule consumes it and returns the new one.** That
   is not a workaround, it is right: applying a rule *grows* the arena, so
   ownership should move with it.

And the constraint that survives from the retraction: **the table is linear**, so
a second pass rebuilds it (`pass2(prev)` calls `engine_pass(table(), prev)`).
That is the entire structural cost to `uop/spec.py`, and it is one call site.

## Writing a Kahn worklist, which is how the folds get expressed

Measured on `tinybendygrad/uop/fold.bend`: the derived properties of
`tinygrad/uop/ops.py` as ONE topological fold, `ALL PROOFS CHECK` on both lanes
with no `@unsafe`. This is the shape every recursive property in the port wants,
so the rules it forced are the rules that decide the port.

**THE HEADLINE, and §8 is the evidence: a fold that TERMINATES is not a fold that
is CORRECT.** All five bugs below were `ALL PROOFS CHECK` and four printed
plausible output. Termination is the easy half and it is not the half that is
tested.

### 1. No forward references, and the error lies about the cause

    def caller(n: U32) -> U32:  helper(n)
    def helper(n: U32) -> U32:  U32.add(n, 1)
    #| - expected : a filled definition (an unfilled law is a dead claim:
    #|             live code cannot use it)
    #| - observed : helper

So **declaration order is a hard ordering constraint** (Python's order is not
reusable), and the message is the one the compiler also gives for a law
declaration left unfilled — a mis-ordered def and a dead `def foo:` stub are
indistinguishable. My order came out of a Tarjan SCC pass over the def graph
(`slop_topo.py`, since deleted): 0 SCCs, so a plain topological order.

### 2. A self-call SPENDS the list it walks, so a walk cannot return it

    def len2(xs: List<&2, U32>) -> Nat:
      Nat.add(List.length(&2, U32, xs), List.length(&2, U32, xs))
    #| - expected : xs
    #| - observed : xs (consumed more than once)

`+xs` fixes exactly this, and it is accepted on a `List` (measured — `+` is
refused only for `Type`-kinded values: functions, `Array<T>`, handles, `IO`):

    def len2(+xs: List<&2, U32>) -> Nat:  ...        # ALL PROOFS CHECK

But `+` licenses *the caller's* uses, not the callee's: a self-call still
consumes its argument, so the recursive arm's value is the **tail**. A fold that
must return both the list it walked and a number derived from it has to rebuild
the list in reverse and `List.reverse` it. Two of the five bugs below are this,
and both were silent.

### 3. A `Data` record is how a list travels with something derived from it

Bend has no tuple, so a fold step that needs `(shapes, max_dim)` needs a record:

    type Shapes is Data: Shapes{ds: List<&2, Sized>, m: Nat}

and the record is `Data` precisely so the step can read both fields. This is
*not* a workaround: a fold that answers a node's `dtype` and its `shape` has two
values to hand on, and the arena hands out one.

### 4. A two-scrutinee `match` must cover the cross product, and `_` counts

    match xs b:
      case Nil{} True{}: 0
      case Nil{} False{}: 1
      case h <> t True{}: h
    #| - expected : cases for False
    #| - observed : {}

A wildcard is a cover, not a gap: `case Nil{} _:` and `case h <> t _:` check, and
so does a match of two wildcards. So the rule is plain exhaustiveness over the
product of the scrutinees' constructors — which is what forces an
accumulator-carrying walk to enumerate `Nil`/`cons` × `True`/`False` rather than
return early. **This is why "just return `None` when the answer is no" is not
available**: an early return from the middle of a walk needs a def that calls
back into the walk, and that is mutual recursion, which is refused (1.5). The
flag rides along instead.

### 5. `Nat` and `U32` are different types, and only `Nat` hands out a tail

    U32.is_eq(List.length(&2, U32, xs), 1)
    #| - expected : U32
    #| - observed : Nat

`List.length` returns `Nat`, so every length comparison is
`Nat.is_eq(n, U32.to_nat(x))`. `Nat.to_u32` **does not exist** —
`expected : a defined name / observed : Nat.to_u32`; use `U32.from_nat` and
`U32.to_nat`. Numeric patterns are not uniform: `case 0:` on a `U32` and
`case Some{0}:` on a `Maybe<U32>` both check, while `Nat`'s `1n+p` is a
first-match prefix (see the correction above) **and is the only pattern that
binds a smaller Nat**. So a countdown has to be a `Nat`:

    def down(c: U32) -> U32:
      match c:
        case 0: 0
        case _: down(U32.sub(c, 1))
    #| - expected : a decreasing self-call (arguments are read left to right:
    #|             each passed unchanged until one shrinks)

`U32` literals pattern fine; what `U32` cannot do is *descend*.

### 6. A `do` block has no statement limit, and bare calls are statements

    def main() -> IO(Unit):
      do IO<Unit>:
        IO.print("bare")            # a bare call is a statement
        a : Unit <- IO.print("x")
        IO.print("bare again")
        IO.print("done")            # and the LAST line is a term, not a statement

Measured: 256 bound statements check, and the *only* thing the block insists on
is that it ends in a term — leaving the final term off gives `expected : a term /
observed : end of input`, which reads like a truncation bug and is not one. So a
5-row test table is one `do` block, not five defs.

### 7. A `List` table is O(n²) and `Array` cannot fix it

`Array.get` computes `i & (n-1)`, so `Array.set` cannot grow a table: a resolved
table that is built by appending **has** to be a `List`, and every read is a
walk. One walk per src of a popped node, plus one per consumer released. Slow and
checkable beats fast and unprovable — the alternative was an `Array` whose
`set` silently writes the wrong cell.

### 8. FIVE bugs that all typechecked, and what caught them

A `List` fold is where a port stops being a transliteration, and the failures are
silent, so they are worth writing down. Every one of these five was `ALL PROOFS
CHECK` and four of them printed plausible output:

1. **A countdown that does not count down.** `case c <> t 0n: c <> Kahn.dec.go(t, p)`
   keeps the head and recurses. It typechecks, and the fuel runs out.
2. **The edges, backwards.** Kahn lowers a node's *successors*, not its srcs.
   Releasing a node's own srcs leaves every node whose src is the arena's bottom
   unanswered forever — a fold that terminates, answers one node, and is wrong
   about the rest.
3. **Membership where the count is wanted.** `u in node.src` is a `Bool`, and a
   node that names the same src twice has **two** edges into it: Python's
   `UOp(Ops.BACKEDGE, src=(self, loop, cond))` with `self is cond` is exactly
   that. The consumer's count never reaches zero and the fold silently drops one
   node out of five. The fix is a count of occurrences, and it is a one-word
   change that a Bool cannot express.
4. **Index order is not resolution order.** `List.get(out, i)` on a table built
   by appending as the fold answers nodes reads the wrong entry; the table is in
   *resolution* order, so the read is a search.
5. **Returning the tail instead of the input** (§2), twice.

**The lesson: in a Bend port, "the fold terminates and prints" is not a test.**
Four of these five reached a green run. What caught them was a row whose value
Python specifies — `dtype(CONST(3)) is weakint`, `shape(ADD) == (4,)`,
`ended_ranges(BACKEDGE) == src[1:2]` — and then **running the mutation both
ways**, which is the half that is easy to skip and the half that is the test:

| mutation | rows that moved | measured by |
| --- | --- | --- |
| `ended_of.one` (the BACKEDGE arm) `src[1:2]` → `src[0:1]` | `cycle_safe` only | re-run, 2026-09-30 |
| `Kahn.degree` from an occurrence count to a `Bool` membership | `shape_ok` **and** `device_ok`; `cycle_safe` stays `True` | re-run, 2026-09-30 |

The FIRST row is the clean case and the SECOND is the correction. An earlier
version of this table claimed "one row each", measured on a mutation of
`Kahn.src_count` rather than of `Kahn.degree`. Re-running it as a mutation of
`Kahn.degree` — the occurrence count itself, made a membership test — moves TWO
rows, and notably leaves `cycle_safe` `True`.

Which is the more interesting fact, and worth stating plainly: the two rows are
NOT independent, and the suite is weaker than five green rows suggest. A
membership test under-counts the in-edges of any node an operator lists twice, so
it perturbs the *derived values* (`shape`, `device`) and not the *termination*
claim. `cycle_safe` is the row that was supposed to be about the worklist, and
it is the one that does not notice.

The lesson is not "one row each" — it is that a mutation table has to be
MEASURED, and re-measured when the mutation is re-targeted, or it becomes a
claim about a mutation nobody ran.
row `False` means the rows are not independent and the suite is weaker than it
looks — which is worth knowing before, not after.

## A CLOSURE IN A DATATYPE FIELD MUST TAKE ALL-AFFINE ARGUMENTS

The rule that decides how `uop/spec.py` has to be written. Minimal case in
`.agents/slop/notes/closure-shared-arg-wall.bend`:

```bend
def needs_twice(+ar: A, i: U32) -> V: ...
type R is Type: Shared{test: (A -> U32 -> V)}
def r() -> R: Shared{needs_twice}
```

is rejected with `expected : @_:A -> @_:U32 -> V` / `observed : @+ar:A ->
@i:U32 -> V`. The `+` is part of the function's TYPE, and a field cannot spell
it: `+A`, `A&2`, `&2 A`, `A<2>`, `((A&2) -> U32 -> V)` and `(A&2) -> (U32 -> V)`
were each tried and each is a parse or type error.

**So a rule table cannot hand a rule a shared value.** `spec.py`'s rules need
several nodes -- `x.src[0]`, `x.base`, `x.arg` -- and the arena is `Type`, so it
cannot be shared into a closure at all.

The resolution, and the working model is
`.agents/slop/notes/spec-classifier-shape.bend`:

**the engine hands each rule a SNAPSHOT, not the arena.** One node, flattened,
`Data`. The rule DESTRUCTURES it once, and the binders are then separate values
each usable once and each readable field by field -- so a rule can reach every
node it needs, provided they arrive in one record.

Two more measured rules from the same model:

- **The classifier's accumulator is the VERDICT, not the arena.** The rewrite
  engine's rule rewrites the arena; a spec rule only judges a node, so the pass
  threads `True`/`False`/`Skip` and `keep` is a leaf. The naive port of the
  rewrite shape has the wrong accumulator and its `keep` has to call the pass
  back, which is the same mutual-recursion wall one layer up.
- **`when(cond, v)` is `if cond: v else None` and `when_bad(cond, v)` is
  `if not cond: v else None`.** Both are leaves, and they are what keep a rule
  ONE def instead of three, because a `match` may not scrutinise a call. Almost
  every rule body in `spec.py` is one of those two shapes.

## `UPat.match` AND `upat_interpret`: THE SHAPE, AND WHY IT IS NOT THE REWRITER

`ops.py:1537` and `ops.py:1566`. These drive `spec.py`, so they are the unblocker
for the critical path, and they are NOT the same problem as the rewrite engine
above. Measured by analysis against the ported `UPat`; the model is not written
yet, so treat this as a design with its risks stated, not as a result.

Python threads a mutable `dict[str, UOp]` and returns
`list[dict[str, UOp]]` -- a CARTESIAN PRODUCT over the bindings -- and then calls
the rule as `real_fxn(**match)`. Three things change.

**1. THE STORE MUST BE A COPYABLE `Data` RECORD, not a bare list.** `is_any` is
`flatten([x.match(uop, store.copy()) for x in self.src[0]])` -- one COPY of the
store per alternative -- and a bare `List` is spent when read, so this is already
a type error. Same reason `fold.bend`'s `Table` wraps its list and
`spec-classifier-shape.bend`'s `Snap` is a record. This is the recurring Bend
shape: anything a fold reads twice, or branches over, gets a `Data` wrapper.

**2. `store.setdefault(name, uop) is not uop` BECOMES AN INDEX IDENTITY TEST,
and it is strictly MORE precise than Python's.** Python compares object identity;
UPats and UOps are both arena indices, so the test is "the bound index differs
from this one". This is not a weakening: two structurally equal UOps ARE the
same object in the arena, so the index test is the identity test. Worth stating
because the port is easy to read as a loosening.

**3. A RULE IS `(Store -> Verdict)`, NOT A KEYWORD CALL.** `real_fxn(**match)`
names its arguments, and a Bend closure cannot be called with keyword arguments.
So every rule reads its own captures out of the store. The upside is real: ONE
rule type instead of one per arity, and `is_any` and the commutative
permutations need no special case because the product already multiplies.

THE STORE, in full. `Bind{name: U32, uop: U32}` -- a name is a pattern-arena
concept, the node is a UOp arena index, and the two must not be confused.
`setdefault` is the only place `UPat.match` can reject on a name alone, and it
answers `Maybe<Store>`: `None` is "this name is already bound elsewhere".

THE WALK. `is_any` recurses over the PATTERN's `src`; every other arm recurses
over the NODE's `src`. Then the six rejection tests (op, name, dtype, arg, tag,
length) and either `[store]` for the leaf or the zip:

    for uu, vv in zip(uop.src, vp):
      for s in stores: new_stores.extend(vv.match(uu, s))

That zip is the whole reason `match` returns a list, and it is the part most
likely to hit a wall: it is a fold that MULTIPLIES a list, and every step reads
the pattern arena and the UOp arena.

RISKS, stated before writing it rather than after:

- Two arenas and a store means three things read per step. If any of them needs
  to be read twice, the `+` wall from the section above applies -- and a `+`
  cannot be spelled in a closure TYPE, though these are plain defs so it can.
- The `Data`-wrapper rule from (1) has to hold for the store at EVERY point in
  the zip, or the multiply will not type.
- A rule that reads a node other than the one it matched is a SECOND arena read
  and the `+` annotation, which is legal in a def but makes the rule's signature
  part of the table's type. Same trap as `spec.py`'s `Snap`.

## THE STORE PORTED; THE WALK IS BLOCKED ON `is_any`

Follow-up to the section above, with a runnable model:
`.agents/slop/notes/matcher-store.bend`. `ALL PROOFS CHECK`, both lanes,
`insert_1_then_3=13 same=1 conflict=0`.

**THE STORE IS DONE, and it confirms the recorded design.** `Store` is a `Data`
record wrapping `List<&2, Bind>`, and `Bind{name: U32, uop: U32}` keeps the name
(a pattern-arena concept) and the node (a UOp arena index) apart.

- `insert_1_then_3=13` — `setdefault` on an empty store INSERTS: one binding, and
  it is bound to node 3.
- `same=1` — the same name on the SAME node is NOT a reject. This is the identity
  test, and it is the case that would be easy to get wrong by testing only
  "is the name present".
- `conflict=0` — the same name on a DIFFERENT node IS a reject, and this is the
  one place `UPat.match` can fail on a name alone.

`Store.setdefault.find` also demonstrates the fix for a wall the earlier
sections describe: walking a list with an early exit needs mutual recursion if the
decision gets its own def, and the fixpoint script showed the oscillation
directly. The answer is to evaluate the tail walk EAGERLY and let a leaf `go` pick
between two already-computed answers. That costs a full tail walk even when the
answer is in the head, which is the price of a linear store and is fine here.

**THE WALK IS NOT DONE, and the wall is `is_any`.** `is_any` is the one arm that
recurses over the PATTERN's own src, and it recurses back into the walk. Every
attempt produced mutual recursion, refused, in this specific shape:

    def pmatch(...)          = pmatch.of(pat_at(p, i), ...)   # read the pattern
    def pmatch.of(...)       = pmatch.any(...)
    def pmatch.any.of(...)   = pmatch.is_any(alts0(up), ...)  # or pmatch.op
    def pmatch.is_any(...)   = pmatch(a, ...)                  # BACK

The read is a CALL, so it cannot be inlined into the `match` that needs its
result, so it becomes a def, so the chain is a cycle. `pmatch.op` and the six
rejection tests are the same shape one level down.

Two escapes are visible and NEITHER is written yet, so this is a lead rather
than an answer:

1. **Hoist the `is_any` flatten out of the recursion.** Pass the alternative list
   IN, already extracted, so `pmatch` never calls the thing that calls it. The
   flatten itself needs no recursion -- it is a fold over a list of pattern
   indices.
2. **Make the entry point non-recursive.** The pattern read, the `is_any`
   decision, and the alternative extraction all happen in a def that
   `pmatch` never calls, and `pmatch` takes the pattern and the alternatives as
   PARAMETERS.

Either way the cost is that the six rejection tests each become a `Bool` that
crosses a def boundary, because a `match` may not scrutinise a call. Measured
while building this: `U32.is_eq(n, name)` in a match arm is refused, and the
working idiom is to compute it in the arm and pass it to a def as a parameter --
`Store.setdefault.pick(U32.is_eq(n, name), ...)`, the same shape as
`intern.find.pick`.

**A MEASURED RULE THIS COST AND DID NOT RECORD:** removing the last use of a
parameter is a compile error in some positions -- a mutation that made `eq`
unused stopped the file checking. So an unused parameter is not free to leave
behind, which matters because the natural way to write a rejection test as a
one-line helper leaves `eq` unused in the `False` arm.

## THE COMPILED FORM IS THE RIGHT TARGET, AND IT SUPERSEDES THE INTERPRETER

This supersedes the two sections above it. Measured 2026-09-30 by reading
`tinygrad/uop/upat.py` rather than by porting, and the reading changed the plan.

**TINYGRAD SHIPS TWO MATCHERS AND THE INTERPRETER IS THE FALLBACK.**
`ops.py:1588` is `compiled=bool(getenv("UPAT_COMPILE", 1))` -- default 1, so
`upat_compile` is the live path and `upat_interpret` is not.

**AND THE INTERPRETER CARRIES EVERY AWKWARDNESS, WHILE THE COMPILER ELIMINATES
EACH ONE:**

| interpreter | compiler (`upat.py`) |
| --- | --- |
| mutable `dict` store, `.copy()`ed | `Ops.STORE` is a node in a pattern IR; at emit it is straight-line `x = uop.src[0]` |
| `-> list[dict[str, UOp]]`, a cartesian product | alternatives become `OR` of `AND` (`upat.py:63`); no early exit, nothing to multiply |
| `is_any` flattens, recursing over the PATTERN's own src (`:18`) | `AND(OR(clause for s in src[0]))` -- a disjunction, so that recursion is not there |
| `itertools.repeat` threads the store per src | `all([... for x in base.src])`, a fold |

So the store is an artifact of the interpreter needing a mutable accumulator, and
the wall I hit -- `is_any` recursing back into the walk -- is a wall in the
FALLBACK path. Target the compiled form and `Store`, `setdefault`, the product
and the flatten all disappear. The store was DELETED rather than kept: it is a correct
implementation of a component that should not exist, and leaving it invites the
next agent to build on it.

**THE BIG WIN, AND IT IS NOT OBVIOUS: THE RULE TABLE BECOMES `Data`.** Every
constraint in the sections above about a table being linear -- because a closure
in a datatype field forces `Type` -- applies ONLY to the interpreter, whose rules
are closures. A compiled rule is a TOP-LEVEL DEF named by a tag, so the table is
`CRule{tag, ops, rej}` and is copyable. It can be read twice. `spec.py` and
`schedule` stop paying the linear-table cost entirely, and the `+Arena ->
...` closure wall does not arise because there are no closures.

**THE TRADE, STATED AND NOT ASSUMED AWAY.** One def per pattern instead of one
data entry, so `spec.py`'s 82 rules become 82 defs. That is more LOC, which this
project treats as a quality measure. Against it: each rule is individually
readable and individually gateable, and `movement`/`symbolic`/`schedule` reuse
one shape. It is a real trade, not a free win.

**ONE THING TO CHECK BEFORE COMMITTING, because it may be a divergence.** The
interpreter REJECTS when a name rebinds to a different node
(`store.setdefault(...) is not uop`). The compiled `Ops.STORE` (`upat.py:33`)
just overwrites, and the identity check appears only in the `repeat` arm
(`:54-58`). If a pattern can bind one name to two different nodes, the two paths
disagree. That is either an ill-formed pattern or a bug in one of them, and it
should be settled deliberately rather than papered over by porting the
interpreter "faithfully".

## THE NAME-REBIND QUESTION, SETTLED: THE TWO PATHS AGREE

The loose end from the section above, measured rather than left open. I claimed
the interpreter REJECTS a name rebinding to a different node while the compiled
`Ops.STORE` overwrites, and that this might be a divergence. **It is not.**

`upat.py:100-105` builds a `dict_stores` and, on a duplicate, emits the identity
comparison as an ordinary clause -- with the comment "duplicate store is an
identity compare":

    if store.src[0] in dict_stores:
      new_src.append(UOp(Ops.CUSTOM, src=(dict_stores[store.src[0]], store.src[1]),
                                        arg=("{0} is {1}", dtypes.void)))

So the interpreter states the constraint IMPLICITLY, as a store rejection, and
the compiler states it EXPLICITLY, as an `is`. Same constraint, two spellings.
The compiled form is therefore safe to target, and the check ports to an index
comparison -- `U32.is_eq` on two `U32` arena indices, which is the same thing
`Store.setdefault.same` did.

**AND IT IS LOAD-BEARING, not decorative.** Scanned all 213 files under
`tinygrad/` for a pattern binding one name more than once. Three:

| where | names | verdict |
| --- | --- | --- |
| `uop/symbolic.py:180` | `c` twice | SAFE -- the two are `is_any` ALTERNATIVES, and `is_any` copies the store per alternative, so they never meet |
| `mixin/gradient.py:101` | `dest` twice | **LOAD-BEARING** -- bound to `src[0]` AND to `src[1].src[0]`, two different nodes, so the rule only matches when they are the same node |
| `schedule/__init__.py:182` | `r` three times | **LOAD-BEARING** -- the same `RANGE` node in three positions |

`gradient.py:101` is the clearest statement of intent:

    UPat(Ops.AFTER, src=(UPat(name="dest"), UPat(Ops.STORE, src=(UPat(name="dest"), UPat()))))

"the buffer being stored into is the AFTER's own source" IS this rebind. Without
the identity check the rule would match strictly more nodes than intended, and it
would typecheck and run. So a compiled rule that binds a name twice must emit the
`is` check, and that is a rule to enforce while porting `gradient.py` and
`schedule/`, not a footnote.

## ELEVEN MORE RULES, MEASURED IN `uop/upat.bend`

Every one of these cost a wrong answer or a refused file, so they are measured
and not inferred. The first three change the SHAPE of a recursive port; the rest
are sharp edges.

**1. THERE IS NO MUTUAL RECURSION.** `A` may not call `B` when `B` calls `A`, in
either order, and the error is the actively misleading `expected : a filled
definition (an unfilled law is a dead claim: live code cannot use it)` pointing
at the LATER call. Reproduced in three lines:

```python
def even(n: Nat) -> Bool:
  match n:
    case 0n: True{}
    case 1n+p: odd(p)          # "expected : a filled definition ... observed : odd"
def odd(n: Nat) -> Bool: ...
```

Consequence for a port: **each recursive descent must be ONE self-recursive
def**, and everything it needs on the way down must be a leaf. Python's
`_get_clause` is a mutual recursion with its own `src` arms and it took three
self-recursive defs here (`get_clause.go`, `rend.go`, `proc`) plus flags to keep
the arms apart. A visitor that dispatches through a table wants a cycle; it has
to be flattened into one match first.

**2. A SELF-CALL MUST BE DECREASING, READ LEFT TO RIGHT.** `expected : a
decreasing self-call (arguments are read left to right: each passed unchanged
until one shrinks)`. So in `def f(fuel, +tree)`, the recursive call must be
`f(fuel', smaller)` -- the arguments BEFORE the one that shrinks are passed
unchanged, and the fuel is what shrinks, so **the fuel is the first parameter of
every self-recursive def**, which is why `proc_fix(f: Nat, +t: C)` reads
backwards from the Python. A subterm counts as shrinking: `f(fuel, t)` on a list
tail is fine.

**3. THE SAME FUEL MAY NOT BE PASSED TO TWO SELF-CALLS IN ONE ARM.** The error is
`expected : p -- observed : p (consumed more than once)`, reported at the
`case 1n+p:` PATTERN, which sends you looking at the pattern instead of the body.
`flatands.go` gets out of it with `+q = p` and passes `q` to both; that is the
fix, and it is a `let` precisely because a `let` is a shared reference and a
pattern binder is not.

**4. A SELF-CALL MAY NOT FORWARD-REFERENCE.** Every callee of a self-call must
already be defined, so a self-recursive def sits at the BOTTOM of its own
dependency chain -- which is what a topological sort gives you for free, and what
hand-ordering gets wrong. Same error as rule 1, so check the order first.

**5. A `match` KILLS EVERY NAME BOUND EARLIER IN THE SAME BODY** -- parameters
AND pattern binders. `match br:` then `match op:` (where `op` came from
`case C{op, lit, k} <> t:`) gives `a match on a parameter or field (this name is
a def or a consumed binder)`. A def that dispatches on two flags must read them
in ONE `match` per arm, never as two nested ones: `rend.go` repeats `br` inside
all four op arms for exactly this reason, and it costs four lines to save a
refused file.

**6. `case p <> t:` ON A `String` GIVES YOU THE FIRST CHARACTER.** `String` is
`List<&2, Char>`, so the head/tail pattern that reads a `List<&2, String>`'s
first element also matches inside the `String` itself. The symptom is a value
that is one character long where a whole piece was expected -- and the piece that
is lost is always the one AFTER it, because `head_or` then answers the empty
tail. There is no `List.split` in `base.bend`; the fix is to take the element as
a whole and let a helper def destructure it.

**7. `List.append(a, -A, xs, ys)` IS `xs ++ ys`.** Prepending is
`List.append(a, A, [x], xs)`. A recursive `map`/`filter` that writes
`append(fold(t), [head])` compiles, typechecks, runs, and returns every list in
REVERSE -- and the reversed list is still a list of the right type, so nothing
downstream complains. Six separate folds in `upat.bend` had it; the only reason
it was caught is that the port is gated on CPython's exact output.

**8. `String.concat` IS NOT A NO-OP ON EMPTY PIECES.** It is `SNil{}` for `Nil{}`
and `h + concat(t)` otherwise, so a format substitution built from pieces
concatenates to the right string even when a piece is `""`. That is how a
dropped literal stays invisible: `"{0}.op is {1}"` rendered as `"uopa0"` with no
error anywhere. Compare against a known-good string, never against a type.

**9. `Bool.pick(-A, c, a, b)` ANSWERS `a` WHEN `c` IS TRUE.** Obvious, and worth
writing down because the natural reading of the call site
`Bool.pick(List<&2, C>, is_empty(xs), [x], xs)` is the other way round; getting
it backwards silently swaps two arms of every dispatch that uses it.

**10. A `do` BLOCK MUST BE THE LAST EXPRESSION OF A DEF BODY.** A bare
statement or a `do` block followed by another expression is
`expected : a term -- observed : '.'`, and a `do` block whose type is `IO(Unit)`
followed by the function's value is `expected : a term -- observed : end of
input`. A pure function cannot print mid-body: put the effect in a wrapper that
RETURNS the value (`String.concat([IO.print(x), ...])`) or in `main`.

**11. `proc(t)` SPELLED TWICE IS TWO WALKS, NOT A SHARED BINDING.** A `let` is
affine, so `n = proc(t)` followed by two uses of `n` is
`expected : n -- observed : n (consumed more than once)`; `+n = proc(t)` is the
shared form, and `Bool.pick(C, eq_c(t, proc(t)), proc(t), recheck(proc(t)))` with
`proc` pure is a legitimate way to say "call it three times" when a fixpoint test
needs both the old and the new value. Purity makes the repetition free of state
and only expensive in time.

## WHAT THE UPAT PORT COST, IN ORDER

The three recursive rules above are why `upat.bend` is 2.3k lines for 186 lines
of Python, and the count is not padding: the alternative is a self-recursive def
with seven `Bool` parameters and a `match` per arm, which is what `rend.go` and
`get_clause.go` are. The other half of the cost is `do_process_and`, whose
`found` is read in five places and is therefore threaded through four
`Maybe`-returning helpers (`of0` .. `of6`) that exist only to keep the flag out of
a record. Both are the direct consequence of rules 1-3, and both would be one
line each in a language with mutual recursion and a mutable local.

## EXTENDING THE DIFFERENTIAL ORACLE: THE a{n} ORDER HOLDS, AND IT FOUND A BUG

The compiler's nine rows are CPython's own `_get_code` output, which is the right
kind of evidence, but none of them spends more than one or two `a{n}`s — so the
NUMBERING, which the port makes a separate pre-order pass, was untested. The
oracle extends in one command. The probe is
`.agents/slop/notes/upat-anum-probe.bend`; run it and run CPython's `_get_code`
on the same patterns and diff.

**THE ORDERING HOLDS.** Four patterns, four levels deep, up to four `a{n}`s, all
MATCH CPython byte for byte:

| pattern | `a{n}` spent | result |
| --- | --- | --- |
| `UPat(Ops.ADD, src=(UPat(Ops.MUL, name="x"), UPat(Ops.CAST, name="y")))` | `a0 a1 a2` | MATCH |
| `UPat(Ops.CALL, src=(UPat(Ops.PARAM, name="dst"), UPat(Ops.RANGE, name="r")))` | `a0 a1 a2` | MATCH |
| `UPat.any(UPat(Ops.MUL, name="a"), UPat(Ops.SUB, name="b"))` | `a0 a1` | MATCH |
| `UPat(Ops.INDEX, src=(UPat(Ops.ADD, src=(UPat(Ops.MUL, name="m"), UPat(Ops.SUB, name="s"))), UPat(name="i")))` | `a0 a1 a2 a3` | MATCH |

So the deviation reported in the compiler commit — Python numbering inside
`pm_renderer`, the port numbering in a separate pre-order pass — is NOT observable
in the generated source, through four levels. It remains a structural difference
between the two implementations, so it is not disproved, only unexercised less
than feared.

**AND THE SAME PROBE FOUND A REAL BUG -- whose first diagnosis was WRONG.**

The `repeat` arm (`src=UPat(...)`, which is `itertools.repeat`) sometimes returns
`None` where CPython returns a full `compiled_match`. The first reading was "it
resolves its child only at pattern index 0", because the passing fixture used
`SOne{0}` and the failing one used `SOne{1}`. **That is falsified.** The
discriminating experiment is one variable:

| fixture | repeat child at | an UNREFERENCED pattern in the arena | port |
| --- | --- | --- | --- |
| `p_rep_at0` | index 0 | no | full code, MATCHES CPython |
| `p_rep_dangling` | index 1 | yes, one var no parent references | **`None`** |
| `p_rep_nested` | index 1 | yes, same shape | **`None`** |

So the repeat index is NOT the trigger. **A pattern in the arena that no parent
references is.** Same structure, same `SOne{1}`, and adding one dangling pattern
turns working code into `None`.

Two candidates eliminated while narrowing it, which is the useful part:

- `alt_ys` reads the repeat's index correctly (`case O.UpRepeat{x}: [x]`), so the
  index is not being dropped.
- `broken_of` is NOT recursive -- it checks only the top-level UPat's own `src` --
  and on these shapes it does not fire, so it is not rejecting them either.

That leaves the failure downstream, in the repeat arm of `get_clause.go` (the
`case alt <> at:` branch, where the walk descends with `alts = Nil{}` and
`ys = alt_ys(alt)`) or in `final_render` / `code_of`. The walk appears to be
sensitive to the arena containing patterns the root's subtree does not reach, and
the natural suspect is anything driven by arena POSITION or by a FIXPOINT over the
whole arena rather than by the pattern's own subtree -- `pm_proc` is a fixpoint,
and if it enumerates the arena rather than the reachable tree, a dangling pattern
is exactly the kind of node that would change the round count.

`repeat` nested inside `is_any` also returns `None` where CPython emits both
branches -- and there CPython numbers PER BRANCH, both branches using `a0`, which
is a third thing the nine rows could not see. Whether that is the same cause is
NOT established.

WHY THIS MATTERS BEYOND THE PORT. `UPat.var` and `cvar` are INTERNED, so a name
built once and reused across rules leaves entries in a pattern arena. If a rule
builder ever creates a pattern it does not reference -- which `UPat.or_any` does
when it appends a named copy alongside the original -- then this is reachable in
ordinary use and not only from a hand-built fixture. That is worth checking before
assuming the bug is confined to probes.

THE LESSON, which is the point of doing this at all: nine rows against a real
oracle is strong evidence about the cases the rows cover and NO evidence about
the rest. The cheapest possible extension — six more patterns through the same
oracle — turned an "unverified deviation" into a "verified ordering plus a
concrete bug". Neither was findable by reading the code.

## SIX MORE RULES, MEASURED 2026-09-30 WHILE PORTING `uop/spec.py`

Appended, not edited. All six are Bend 2.0.34 and all six were found by porting
84 rules; each one cost at least one compile cycle.

### 1. A `Data` RECORD PARAMETER NEEDS `+` FOR TWO READS. IT IS NOT IMPLICITLY COPYABLE

    type CRules is Data:
      CRules{rs: List<&2, U32>}
    def CRules.rs(rs: CRules) -> List<&2, U32>:
      match rs:
        case CRules{rs}: rs
    def cr_rewrite(rs: CRules, ar: U32, i: U32) -> U32:
      cr_scan.rs(rs, ar, i, CRules.rs(rs), 0)
    #| - expected : rs
    #| - observed : rs (consumed more than once)

`+rs` fixes it and nothing else does. This CORRECTS the claim in
`compiled-matcher-shape.bend`'s header -- "the table is `Data`, so `rs` is COPYABLE
and readable twice" -- and the model's `cr_rewrite` is a live instance of the
error, unreachable only because nothing calls it yet. `Data` makes a record
shareable ACROSS functions; it does not make the PARAMETER readable twice inside
one body. Same for `F.Folded` and for `O.Arena`.

### 2. AN UNUSED `+` PARAMETER IS ACCEPTED

    def q1(+fx: F.Folded, self: U32) -> Verdict: VSkip{}
    #| ALL PROOFS CHECK

So `+` can be applied UNIFORMLY to a parameter without a dead-parameter error, and
a driver can pass an argument a rule does not need. Worth knowing because the
alternative -- annotating only where the compiler complains -- is exactly the
manual loop `share.py` automates.

### 3. `+` CANNOT BE SPELLED ON A `Maybe` PARAMETER

    def facts(+m: Maybe<&1, ParamArg>) -> Bool: ...
    #| - expected : Data
    #| - observed : Type

`Maybe` is a `Type`, and the `+`-notes section above already says `+` is refused
for `Type`-kinded values. The consequence is the one that cost the most here: a
`Maybe` can be read ONCE, so every answer it carries has to travel together, and a
`Data` record CANNOT HOLD A `Maybe` FIELD. So a `Maybe<ParamArg>` becomes a
`Data` record of `Bool`s (and a third `Data` type for the device's three states),
not a record of `Maybe`s:

    type DevOpt is Data:
      DNo{}
      DOne{tag: U32}
      DMany{tags: List<&2, U32>}
    type Pa is Data:
      Pa{ok: Bool, size: Bool, dev: DevOpt, buf: Bool, vrange: Bool}

This is a recurring shape and it is not a workaround: Bend has no `Data` field
that can hold a `Maybe`, so ANY record that would naturally hold a list of
optional answers has to be flattened to a tree of `Data`.

### 4. A ONE-FIELD RECORD'S PATTERN MUST NAME ITS FIELD

    match a:
      case ADt{}: True{}
    #| - message : a ADt pattern with 1 field

    match a:
      case ADt{dt}: True{}      # checks, and the unused binder is fine

A zero-field constructor takes `{}` and a one-field constructor takes `{name}` --
`{}` is never "ignore the fields". And an UNUSED pattern binder is accepted, which
is what makes `case ADt{dt}: True{}` a one-line `isinstance(x.arg, DType)`.

### 5. A TWO-SCRUTINEE `match` NEEDS ONE PATTERN PER SCRUTINEE, AND `_ _` IS THE COVER

    match a b:
      case Some{x} Some{y}: ...
      case _: False{}
    #| - expected : 2 patterns (one per scrutinee)
    #| - observed : '_'

The fix is `case _ _: False{}`. This is the rule-4 note above with the spelling:
a wildcard is a cover, and it is a cover PER POSITION.

### 6. A THREE-SCRUTINEE `match` WITH A `Nat` COUNTDOWN HAS NO `0n` ARM

    match xs want n:
      case Nil{} Nil{} 0n: True{}
      case _ _ 1n+p: ...
    #| - expected : a constructor of U32 (missing, or already matched)

The note above already says a `Nat`'s `0n` is a first-match PREFIX that claims its
successors, and it already says to use `List.get`. What is new here is that this
bites in a THREE-scrutinee match too -- `case _ _ 1n+p:` after a `0n` arm is dead
for the same reason, and the `0n` arm swallows the whole countdown. For two lists
compared for equality there is no countdown at all: `ops.bend`'s `eq_op_list` is
the right tool and the countdown was 20 lines of nothing.

### 7. A SELF-CALL DRIVEN BY A `Nat` COUNTDOWN MUST PASS THE SHRINKING ARGUMENT FIRST

    def go(xs: List<&2, U32>, k: Nat, acc: U32) -> U32:
      match xs k:
        case Nil{} _: acc
        case h <> t 0n: ...
        case h <> t 1n+p: go(p, t, ...)     # REFUSED
    #| - expected : a decreasing self-call
    #|   (arguments are read left to right: each passed unchanged until one shrinks)

`go(t, p, ...)` is the only spelling. The two-scrutinee `match` reads its
scrutinees in declaration order, and the decrease check reads the arguments in
declaration order, so the countdown has to be the SECOND parameter for both to
line up. `fold.bend`'s `Arena.at.go` and `Kahn.dec.go` already have it in that
shape; the reason they do is this.

## RUNTIME "MEMORY FAULT" / MACHINE STACK OVERFLOW, IN THIS CODEBASE'S TERMS

Bend 2 runs on HVM2, so a stack overflow is not a CPU stack overflow — it is the
runtime exhausting its memory NODES, because recursion builds interaction-net
graph rather than moving an instruction pointer. The symptom is a hang or a
memory fault, and it looks identical to an infinite loop. Three causes, ordered by
how often they have actually bitten here.

**1. A FOLD WHOSE FUEL NEVER REACHES ZERO.** This is the common one, and it has
bitten twice in this repo. Both times the cause was a bound derived from
something that is NOT what the fold is walking:

- The Kahn fold in \`fold.bend\` seeds its worklist from \`Arena.next(ar) + edges\`
  — one push per zero-src node PLUS one per edge. The arena is a DAG by
  construction (\`UOp.make\` only names src indices already appended, so every src
  index is strictly less than its consumer's), so the arithmetic terminates. If
  the bound is derived from anything else, the worklist never drains.
- \`UPat.repeat\` is Python's \`itertools.repeat\`: an UNBOUNDED alternative. It is
  a VARIANT (\`UpRepeat\`), not an infinite list, precisely so nothing enumerates
  it — \`required_len\` and \`strict_length\` are what bound the read. A fold that
  walks \`UpRepeat\` without that bound never terminates.

**2. A BOUND THAT DOES NOT DECREASE.** Measured while porting the pattern
compiler: a self-call must be DECREASING and read LEFT TO RIGHT, and the same
fuel may not feed two self-calls in one arm. A self-call that passes the fuel on
unchanged, or passes it after a value that already consumed it, is an infinite
net. \`upat.bend\` makes fuel the FIRST parameter of every self-recursive def for
exactly this reason.

**3. AN AFFINITY VIOLATION THAT EXPONENTIATES NODES.** \`Data\` makes a record
shareable ACROSS functions but does NOT make the PARAMETER readable twice — the
parameter still needs \`+\`. Getting that wrong typechecks, and the net it builds
duplicates subtrees instead of sharing them, so node count grows with depth rather
than with width. The \`+Arena -> ...\` closure wall is the same fact seen from the
other side, which is why the port has no closures.

**HOW TO LOCALISE, in the order that has worked:**

- Run the INTERPRETED lane first. If the native lane hangs and the interpreter
  does not, it is a compilation/backend issue, not your logic. If BOTH hang, it is
  a non-terminating walk.
- \`--check-only\` passing tells you nothing here. Both a terminating and a
  non-terminating fold check.
- Bisect by making a fold's accumulator a COUNT and printing it, so you can see
  which node it stalls on. \`fold.bend\`'s \`Table\` is a \`Data\` record precisely so
  it can be read while a walk is in flight.
- Compile to a local target and inspect, as a last resort — but in this repo the
  interpreted-lane split plus a count has been enough every time.

**WHAT DOES NOT HELP:** raising a timeout. Every occurrence here was a genuine
non-termination, and each one cost 120s of waiting to learn nothing.

## EIGHT MORE RULES, MEASURED 2026-09-30 WHILE PORTING `uop/weak.py`

### 1. `def f.b(...)` MUST BE DECLARED BEFORE `def f.a(...)` THAT CALLS IT
The "no forward references" rule bites hardest in the `name.phase` naming
convention, because the reading order a human expects (outer call first, helper
below) is the order the checker refuses. `weak.py`'s port lost four cycles to it:
`derived_dtypes.hold`, `commit_srcs_at.bare`, `wk_dt_const.sealed_pick` and
`wk_blocked.of` each had to be moved ABOVE its own caller. The error reads
`expected : a filled definition (an unfilled law is a dead claim: live code cannot
use it) / observed : <name>`, which does not say "declared too late" at all. The
existing driver `tools/hoist.py` fixes it; the tell is the error text above.

### 2. A `Some{g}` BINDER OVER A `Data` RECORD IS AFFINE: TWO READS NEED `Some{+g}`
`Found` is `Data`, which makes it shareable ACROSS functions, but a binder pulled
out of a `Maybe` is a normal affine binder. Measured on
`case Some{g}: wk_dt(refold(g), wk_src1(refold(g), O.Found.i(g)))` -- two reads of
`g` and the error is `expected : g / observed : g (consumed more than once)`.
`+` in the PATTERN position (`Some{+g}`) is the fix, not `+` on the `Maybe`
parameter, which rule 3 of the section above forbids.

### 3. `Nat` LITERALS ONLY BIND IN A `Nat` CONTEXT, AND `Bool.to_u32` IS NOT ONE
`Nat.add(n, 1)` is `expected : Nat / observed : U32`; `Nat.add(n, 1n)` is fine.
There is a `Bool.to_u32` and NO `Bool.to_nat`, so a COUNT over a predicate needs
its own two-arm def:
    def nat_of(b: Bool) -> Nat:
      match b: case True{}: 1n case False{}: 0n
This is the same shape as `Cmp` being a datatype that a `match` can scrutinise.

### 4. A RECORD PATTERN MAY NAME FEWER FIELDS THAN THE RECORD HAS -- SILENTLY
`case Fix{fx, wl, a, c, b, bs}` against a SEVEN-field `Fix` is ACCEPTED and the
missing field is a wildcard. So a partially-updated record type is caught ("a Fix
pattern with 6 fields") but a partially-updated PATTERN is not: it compiles, reads
whatever is in the un-named slot, and the gate row that depends on it goes quietly
wrong. When a `Data` record gains a field, EVERY `case` of it must be updated by
hand, and `--check-only` will not tell you.

### 5. BEND IS STRICT: AN ARGUMENT IS EVALUATED BEFORE THE CALLEE BRANCHES
    def pick2(some: Bool, dt: ODt, fx, self, ss) -> O.Arena:
      pick(some, go(ss, walk_seed(Folded.ar(fx)), fx, ODt.dt(dt)), fx, self)
The `dt is None` arm of `commit_weak_consts` is Python's identity, but `go` is an
ARGUMENT, so it runs on that arm too: the walk mints nodes, and `pick` then hands
back the GROWN arena. It typechecks, it checks, and the gate row that counts arena
nodes is the only thing that sees it. To keep a branch LAZY the work must be inside
a `match` ARM of a def whose FIRST parameter is the flag:
    def walked(some: Bool, dt: ODt, fx, self, ss) -> O.Arena:
      match some:
        case True{}: replace_walk(go(ss, walk_seed(...), fx, ODt.dt(dt)), fx, self)
        case False{}: O.Folded.ar(fx)
The general rule: **a flag parameter makes the arms cheap, it does not make the
arguments lazy.**

### 6. A GROWING ACCUMULATOR CANNOT BE THE FIRST PARAMETER OF A SELF-CALL
Rule 7 of "ELEVEN MORE RULES" makes the SHRINKING argument first when the fuel is a
`Nat`. The same holds when the fuel is a LIST and the accumulator GROWS: a
`Walk{arena, srcs}` in the first slot is a `expected : a decreasing self-call`.
`commit_srcs_at.go(ss, w, fx, dt, bare)` is the shape; `w` in the first slot is
not. Same cause as the `Nat` case: arguments are read left to right, each passed
unchanged until one shrinks, and `Walk` never shrinks.

### 7. A `Data` RECORD CAN CARRY THE `Maybe` A PARAMETER CANNOT
`dt: DType|None` is read once PER SRC in `commit_weak_consts`, and `+` cannot be
spelled on a `Maybe` parameter (rule 3 above). The port that works is a two-field
record -- a `Bool` plus the value -- which is rule 15's own spelling (`spec.bend`
does it for `Pa`, `fold.bend` for `Sized`). Same for `derived_dtypes`' answer:
`Dts{some: Bool, meet, result}`, read once for `bare` and once for the pair.

### 8. AN `IO<Unit>` `do` BLOCK CAN ONLY BIND AN `IO`
    f = g_fix()                                  # expected : a pattern
    f : Fix <- pure(g_fix())                     # expected : a defined name: pure
    f : Unit <- row(...)                         # OK -- what fold.bend's main does
A pure value cannot be bound in the block at all, so a fixture has to be passed to
each row as a PARAMETER (`main` calls `g_fix()` per row) or wrapped in an IO for no
reason. For an 11-node fixture the repeated `g_fix()` is free; for a real arena it
would not be, and the honest shape is `Folded` carried in the caller's parameters.

## FIVE MORE RULES, MEASURED 2026-09-30 WHILE PORTING `uop/divandmod.bend`

### 1. A `Maybe` PATTERN BINDER CANNOT BE READ TWICE

`bend2-constraints` rule 3 says a `Data` record PARAMETER needs `+` for two reads
in one body. A binder from `case Some{f}:` is the same restriction and there is
no spelling for it:

    def hit(m: Maybe<&2, Found>) -> U32:
      match m:
        case Some{f}: Found.ar(f) + Found.i(f)      # refused: f, consumed more than once
        case None{}: 0

The fix is to hand `f` to a def and put `+` on THAT:

    def hit.put(ar: Arena, +f: Found) -> U32: Found.ar(f) + Found.i(f)
    def hit(m: Maybe<&2, Found>) -> U32:
      match m:
        case Some{f}: hit.put(arena, f)
        case None{}: 0

So rule 4 ("`+` cannot be spelled on a `Maybe`") and rule 3 meet: the binder is
unfixable and the parameter is not. **This is not the same as a `Maybe`
PARAMETER, which `+` handles normally** — it is specifically the binder.

### 2. A COMMUTATIVE `alu` BUILDS AN `is_any`, SO A `+` PATTERN IS A DISJUNCTION

`UPat.alu` (ops.py:1533-1536) passes `list(asrc) if op in GroupOp.Commutative
else asrc`, and `GroupOp.Commutative` is `{MUL, MAX, CMPNE, CMPEQ, XOR, OR, AND,
ADD}`. So `UPat.cvar("a") + UPat.cvar("c")` is `is_any` over BOTH ORDERS and a
port that writes "src0 is the CONST" drops one alternative, typechecks, and is
wrong on every fixture with the operands the other way round. **There is no
`reject set` and no `on` flag that catches it**; the two-sided fixture is the
only thing that does.

### 3. `dm_which`-STYLE DISJUNCTIONS ARE NOT DISTINGUISHABLE BY ONE FIXTURE FAMILY

Two rules each with one commutative `is_any` ("which side is the CONST" and
"which side is the quotient") move the SAME mutation set from one fixture family,
because from outside the question is the same question. See `divandmod.bend`'s
mutation table, notes 1 and 2. Separating them needs a fixture where the two
answers DISAGREE, not more fixtures of the same shape.

### 4. AN INDEX IS ONLY MEANINGFUL IN THE ARENA THAT PRODUCED IT, AND `+` DOES NOT ENFORCE IT

`+x = O.UOp.new(O.Found.ar(previous), ...)` binds an index into the arena it was
built in. Building `+b` from `O.Found.ar(a)` when `b` should have been threaded
through an INTERMEDIATE node silently reuses index `n` for a DIFFERENT node, and
every read of `Found.i(b)` in the later chain then reads the wrong node. Measured:
a fixture PARAM created and then dropped from the thread aliased a `FLOORDIV`
three nodes later, and the gate printed `div25=FLOORDIV` for a node whose divisor
was a PARAM. `share.py` and `hoist.py` cannot see this — it is not a `+` or an
order error — **so the last arena threaded is the thing to re-read when a label is
wrong.** Symptom to recognise: a node's src prints as a plausible index but the
wrong `op`.

### 5. `floor` IS NOT AVAILABLE AND MUST NOT BE ASSUMED FROM A HELPER NAMED `floordiv`

`H.floordiv_i32` in `helpers.bend:1097` adds one whenever the division is
inexact and IGNORES the sign, so it is correct for a negative dividend and for an
exact division and WRONG (off by +1) for a non-negative dividend with an inexact
division — which is most of them. Measured: `6 // 4 == 2`, `10 // 3 == 4`,
`1000 // 7 == 143`, `6 % 4 == -2`, against Python's `1, 3, 142, 2`.

**The general rule: a port that depends on floor semantics must TEST the helper
against the Python answer before using it, and a correct local copy with the
upstream bug named is better than a gate that pins wrong numbers.** `divandmod.bend`
carries `dm_floordiv` / `dm_floormod` for exactly this, with the one-line fix and
the removal condition written down. `H.asr` is broken the same way (see that
file's header): `shrn(v,31)` is the sign BIT, so `shrn(shrn(v,31), n)` is 0 for
every `n >= 1` and `H.asr(-1, 1) == 2147483647` where the answer is `4294967295`.
Both are UNUSED and UNTESTED in `helpers.bend`, which is why ten green rows in
another unit never saw them.

### 6. A NESTED-FORWARD TREE PRINTER IS A MUTUAL RECURSION, AND BEND REFUSES IT

`print(node) -> fold(srcs) -> print(src)` is two mutually recursive defs. A `Nat`
fuel does not rescue it: a binop spends one fuel on TWO self-calls, and rule 5
forbids that. The honest answer is to make the DEPTH a parameter of the printer
(`dm_sh1` / `dm_sh2` in `divandmod.bend`) and pick the depth the ANSWERS need —
two levels with CONST VALUES printed reproduces Python's trees exactly for that
file's rules. **When a printer cannot be recursive, printing less but printing
VALUES beats printing more but printing op names.**

## SEVEN MORE RULES, MEASURED 2026-09-30 WHILE PORTING `uop/symbolic.py`

Appended, not edited. All seven are Bend 2.0.34 and each one cost a wrong answer
or a refused file.

### 1. A `Maybe` IS READ ONCE AND CANNOT BE `+`, SO "TEST IT AND USE IT" IS TWO DEFS

`Maybe<&1, T>` is a `Type`, `+` is refused on it (section "THREE" of the
`spec.py` notes), and it is read once. So the Python

```python
if c is not None: ... c ...
```

is three defs, not one, and the test crosses as a `Bool` **beside** the value:

```bend
def rm_0.ok(hit: Bool, ok: Bool, +x: F.Folded, +u: U32, z: U32) -> Maybe<&1, U32>: ...
def rm_0.of(hit: Bool, z: Maybe<&1, U32>, +x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  match z:
    case Some{v}: rm_0.ok(hit, True{}, x, u, v)
    case _: rm_0.ok(hit, False{}, x, u, 0)
```

Writing `Bool.pick(Maybe<&1, U32>, Maybe.is_some(&1, U32, z), Some{f(z)}, None{})`
is `expected : Data / observed : Type` on the `+z` that `share.py` helpfully
adds — **and `share.py` will add it every time**, because the error it is fixing
is real. That is a loop: run `share.py`, get the `+`, get the `Data`/`Type`
error, restructure, run `share.py` again. The fix is to notice that the shape is
wrong, not to add annotations.

### 2. `Maybe<a, A>` IS INVARIANT IN ITS USAGE COUNT

`Maybe<&1, O.Const>` and `Maybe<&2, O.Const>` are DIFFERENT types and are not
interchangeable in a call. A `Data` field cannot hold a `Maybe` at all, and a
helper that takes a `Maybe` parameter inherits whichever count its call site
spells. The measured cost was a chain of `sy_maybe_c` / `sy_maybe_c2` — two
three-line defs with identical bodies — because a FOLD's answer is `&1` and a
`sy_val` out of `fold.bend` is `&2`. It is not worth deduplicating into a
typeclass; it is worth knowing before the second one surprises you.

### 3. A `find`-STYLE RECORDER IS USUALLY A FOLD WITH AN INVERTED `Bool`, AND THAT IS THE BUG

`const_i64` was written `Bool.not(Cmp.is_eq(...))` — "the value is NOT `n`" —
inside a def named `p_is_const_0`. It typechecked, it ran, and it inverted every
caller. The mutation that catches it is one character (`is_eq` -> `not is_eq`)
and it moved **three** rows at once, because the predicate is shared by
`sym_6.pat` and `sym_8`'s shape. A shared predicate is a shared blast radius:
the mutation table should always include one, because "which rows does this one
comparison own" is not answerable by reading the rule that uses it.

### 4. `ops.bend`'s `Arena.empty()` SPENDS INDEX 0, SO EVERY FIXTURE IS OFF BY ONE

`# the arena starts with the bottom at index 0, so Arena.next is next(UOp.unique_num)
# with the first slot already spent` (ops.bend:925). So a graph of two nodes has
indices 1 and 2, and `Arena.next` is 3. Four of this file's gate rows were `0`
because every hard-coded index was one short, and `Arena.node` answering
`Arena.bottom()` for an index past the end means a mis-indexed fixture answers
`None{}` rather than raising — so the symptom is a rule that silently does not
fire. **The fixture's own node count is a gate row** (`lay`), and it is the row
that would have caught it.

### 5. A FIXTURE BUILDER THAT RETURNS AN INDEX THROWS THE GROWN ARENA AWAY

`Arena` is affine, so `sy_cast(ar, ...)` grows a *copy* and the caller keeps the
old one. A builder written as `-> U32` therefore produces a graph whose last
node is not in the store, and `fx_castbad` answered `Arena.next == 1` for a graph
of two nodes. **EVERY construction in a fixture must return a `Found`**, and a
chain is `+a = ...` then `+b = ...` off `O.Found.ar(a)` — which is the same
shape `fold.bend`'s `g_keys` uses.

The deeper form of the same fact is the wall this file stands on: a rule
returning `Maybe<&1, U32>` that GREW the arena gives the caller an index it
cannot dereference. `Maybe<&1, O.Found>` is expressible (`Found` is `Data`), so
that is the shape a growing rule should have; it was not written here because
it touches every rule body, and it is the first thing to change when the tables
grow past thirteen entries.

### 6. `List.append(a, A, xs, ys)` IS `xs ++ ys`, AND A FOLD THAT USES IT ACCUMULATES IN REVERSE

Already recorded ("THE SAME FOLDS..." / rule 7) and re-measured while porting
`pm_remove_invalid`'s `src=tuple(...)` and `pm_clean_up_group_sink`'s
`flatten`. Both read correctly and both are reversed. `List.reverse` at the end
of the walk is the fix and it costs one call. The new datum is that a fold whose
accumulator is a `List` of `List` (the sink-flatten case) has the SAME trap one
level up: `H.flatten_u32` is `List.concat`, so it flattens the accumulated list
of lists and the order is whatever the accumulation produced.

### 7. TWO RULES THAT CLAIM ONE NODE AND **AGREE** CANNOT SEE FIRST-WINS

Already the brief's trap and it is worth stating with the measured result. The
first `first` fixture was `GROUP(GROUP(C(7)))`: tags 11 (`GROUP(x)` -> `x`) and
12 (the flatten) both claim the outer GROUP, and the first-wins -> last-wins
mutation moved **NOTHING** — because `flatten([inner.src])` happens to rebuild
the inner GROUP, so both answers are the same index. The fix is a fixture whose
two answers genuinely differ (`GROUP(SINK(C(7)))`: tag 11 answers the SINK,
tag 12 answers a fresh GROUP over `[1]`), and with it M1 moves exactly `first`.
Two rows with two-sided fixtures in the same file (`rebind0`, `xorb0`) had the
same shape of failure and the same cure: ask for the *absence* of a rewrite, not
for a particular index, on the negative side. `eq_u(m, 0)` is satisfied by any
wrong-but-present answer and witnesses nothing.


## EIGHT MORE RULES, MEASURED 2026-09-30 FIXING `eq_cls.sel` AND `floordiv_i32`

Appended, not edited. All eight are Bend 2.0.34 and each one cost a wrong answer
or a change that would have compiled and done nothing.

### 1. AN ARM AFTER A `case _:` IS **DEAD CODE**, AND BEND DOES NOT SAY SO

This is the one that changes how you write a catch-all ladder, and it is
invisible in the source: the arm is right there, spelled correctly, and never
runs. Measured, with every arm answering a distinct number:

    type C is Data: A{} B{} Cc{}
    match x: case A{}: 1; case _: 99; case Cc{}: 3     # A=1  Cc=99

`case _:` claims every remaining tag, so anything written after it is
unreachable. Bend 2.0.34 accepts it silently -- no error, no warning, and
`--check-only` still says `ALL PROOFS CHECK`.

**So the last constructor of a sum type is spelled `case _:`, and every other one
is spelled out.** That is not a style choice, it is the only placement that can
work, and it is the shape this repo's own `eq_const.sel` already uses: `Const`
is `CBool CInt CFloat CInvalid`, the ladder writes the first three and gives
`CInvalid` the catch-all. Arm ORDER among the explicit ones does not matter --
measured, `case Cc/B/A` and `case A/B/Cc` agree -- so "where do I put the new
arm" is answered by "which one is last in the type's declaration", not by
`dtype.py`'s priority order.

Corollary for the "just append the missing arm" instinct: appending to a ladder
that already ends in `case _:` is the ONE edit guaranteed to do nothing. If a
`match` over a sum type has an `N`-armed version and the type has `N+1`
constructors, the fix is to make constructor `N` explicit and move the catch-all
onto constructor `N+1`.

### 2. A GATE THAT NEVER CALLS THE FUNCTION UNDER REPAIR IS BLIND, AND IT IS NOT AN ACCIDENT

`uop/ops.bend` had twelve rows and all twelve were green while `eq_dt(weakfloat,
weakfloat)` was `False` and two structurally identical `CAST(..., weakfloat)`
nodes built FOUR arena nodes where two would do. Nothing was flaky and nothing
was mis-transcribed; the twelve rows simply never mentioned a dtype except
`S.void()` and `S.boolean()` in fixtures, and `eq_dt` is reached only through
`eq_arg.ADt`.

**The test for "is this gate blind to X" is one grep: does any row's fixture
carry a value of X's type?** If not, the gate cannot see X, and the first thing
to add is a row whose EXPECTATION COMES FROM THE ORACLE (`dtypes.weakfloat ==
dtypes.weakfloat` in CPython), not one whose expectation is what the code
prints. A row that asks "is it equal to itself" for every member of a
seven-member type is a better gate than none, and it took one line per member.

### 3. `+` IS NEEDED ON A `Data` PARAMETER USED **TWICE IN ONE EXPRESSION**, NOT TWICE IN A BODY

`Bool.and(eq_dt(x, y), Bool.not(eq_dt(y, x)))` is refused with
`expected : y / observed : y (consumed more than once)`, and the fix is
`(+x: S.Dt, +y: S.Dt)`. This is not the affine rule ("a binder is used at most
once") -- the same two values are used once each in every `eq_node`/`eq_paramarg`
ladder in `uop/ops.bend` and those compile, because they go through a `match`
that BINDS a fresh name per case. The distinction that matters: passing a binder
to two calls in the same expression needs `+`; passing it to two calls in two
DIFFERENT `case` arms does not. Getting this backwards costs a rebuild.

### 4. `U32.show` ON A NEGATIVE `i32` IS THE BIT PATTERN, SO A GATE MUST SAY SO

`-7` in a U32 is `4294967289`, and a gate row that prints the raw U32 next to a
comment saying `-7` is a gate that needs mental arithmetic to read -- which is
the failure the repo already hit once. The fix that costs nothing: put the
pattern in the ROW NAME (`ok_fd_4294967289_4`) rather than in a comment, and have
the Python oracle print `v & 0xFFFFFFFF`, so both sides are in the same alphabet
and `diff` is the test. Sign is then visible in the number, not inferred.

### 5. A `(Bool, Bool)` FLAG PAIR IS NOT INTERCHANGEABLE, AND WHICH HALF IS
###    CONSULTED IS THE WHOLE DEFINITION

`floordiv_i32.trunc.exact(exact, neg, q)` was right for exact divisions, right
for negative dividends, and wrong for same-sign inexact divisions: it applied
`q + 1` on the inexact arm unconditionally. The arithmetic is not subtle --
`x // y` is the truncation, and the truncation is ALREADY the floor whenever the
two signs agree, so the step belongs to the opposite-sign case alone (`-7 // 4`
is `-2` because `-1` truncates but `-2` floors). It went unnoticed because the
two wrong cells and the two right cells interleave, and the fixture set happened
to hold the right ones.

**So a two-flag ladder wants a truth table written out before it is written in
Bend, and it wants the fixture set to hold one row per cell.** All four cells
here are cheap: same-sign/inexact, same-sign/exact, opposite-sign/inexact,
opposite-sign/exact. A sign matrix is the same idea and generalises: four
combinations of `(x<0, y<0)` times inexact/exact is eight rows, and it is what
`.agents/slop/dm.bend` now holds.

### 6. FLOOR AND TRUNCATION ARE TWO FUNCTIONS AND BOTH GET PORTED, SO "DELETE
###    THE DUPLICATE" IS USUALLY THE WRONG MOVE

`helpers.bend` carries `floordiv_i32`/`floormod_i32` (helpers.py:76-77, Python's
`//` and `%`, i.e. FLOOR) beside `cdiv_i32_go`/`cmod_i32` (helpers.py:73-74, C
semantics, i.e. TRUNCATE). They are not a stale duplicate of each other, and
`ceildiv` (`-(num // -amt)`) and `round_up` (`(num+amt-1)//amt*amt`) are floors
that CANNOT be spelled with the truncating pair -- measured, `ceildiv(10,4)` is 3
and neither `-cdiv(10,-4)` (2) nor `-cdiv(-10,-4)` (-2) gives it, and
`round_up(-10,4)` is -8 while `cdiv(-7,4)*4` is -4.

So when two same-shaped functions disagree, **check what the CALLERS need before
proposing to delete one.** A caller is the evidence; three callers all wanting
FLOOR is what settles it. And when a wrong def sits beside a right one, the fix
is to make the wrong one right AND say in a comment which pair is which, because
the next reader cannot tell an intentional pair of functions from an accidental
copy.

### 7. A COMPILED ARENA MAKES A `Dt` A KEY, SO A `Cls` COMPARISON IS NOT A COSMETIC
###    BUG EVEN WHEN EVERY FIXTURE IS A DIFFERENT `pri`

`eq_dt` also compares `pri` and `bits`, so a conflated `Cls` is invisible on any
pair of DIFFERENT dtypes -- `eq_dt(weakfloat, half)` was already `False` because
`9 != 12`. The only reachable symptom is a dtype compared to ITSELF, and the only
code that does that is the hash-cons table, so the gate needs a row that builds a
node twice and counts nodes, not a row that compares two dtypes. Building the
smallest such node is worth the trouble: `bottom + CONST + CAST + CAST` is three
nodes when the two CASTs intern and four when they do not, and the count is a
number the oracle can be asked for.

### 8. `.venv/bin/python`, NOT `python3`, FOR A GATE THAT IMPORTS THE ORACLE

`tinygrad.helpers` imports cleanly under the system `python3`, but the house
invocation pattern is `uv run --with tabulate python3` / `.venv/bin/python`, and
`mutate-*.py` scripts that shell out to a gate should use the venv explicitly so
they do not depend on the ambient `PYTHONPATH`. Related and cheap: a shell gate
script that `cd`s must use an ABSOLUTE path for its own siblings -- `$0` is
relative to wherever it was invoked from, and `$(dirname "$0")/../..` from
`.agents/slop/tools/` is `.agents/`, not the repo root. That cost two rounds.

## MEASURED: the Bend INTERPRETER has a hard 32 KiB input cliff

The generic advice is that a Bend "machine stack overflow" is a runaway expansion.
That was wrong for the one case we actually hit. Measured on a pure-whitespace
`.js` input, so the LEXER NEVER RUNS:

| input | interpreter |
| --- | --- |
| 4 KiB .. 24 KiB | exit 0 |
| 32768 B | exit 1, `bend: memory fault (machine stack overflow?)` |
| 49152 B, 65536 B | exit 1, ditto |

The COMPILED lane reads 96 KiB of the same input, and tinygrad's own `ops.py` at
110 KB, without complaint. So:

- the threshold is exactly 32768, which is a HOST constant, not a property of our
  recursion depth -- the `.js` lane splits on whitespace and is shallow, yet it
  dies at the same byte count as the tokenizing `.py` lane;
- the diagnostic message says "stack overflow", which sends you looking for a
  non-terminating or over-deep fold in YOUR code. There is none here. **If the
  failing input is at or above 32 KiB and the compiled lane is fine, stop hunting
  and use the compiled lane.**

This BOUNDS THE GATE, which is the part worth writing down: an interpreted lane
cannot exercise any fixture of 32 KiB or more. Those rows are compiled-lane-only,
and a file whose gate claims otherwise is overstating what it checked.

The earlier reading of this -- "a fold whose fuel never reaches zero", which is
cause 1 in the section above -- was right in general and wrong here. Both
descriptions produce the same message, so distinguish them by INPUT SIZE first:
small input that hangs is our bug; input at or above 32 KiB that dies is the host.

## TWO BENCHMARK LESSONS, BOTH LEARNED THE EXPENSIVE WAY ON `sz`

**1. "x100-x1000 slower" was asserted from MECHANISM and was wrong.** Before
measuring, the claim was made that the port was 100-1000x slower than CPython,
derived from: a Bend `String` being a linked list of `Char`s, `String.trim` being
`reverse . trim_start . reverse` (three rebuilds per line), `lex` doing
`chars(s) = List.reverse(chars.go(...))` (two full copies of the file), and every
`U32` op being a net node rather than a machine instruction. Every one of those
facts is real and measured. **The product of them was never measured, and it is not
the slowdown.** The compiled lane lands in CPython's own range. Mechanism explains
a cost's *existence*; it never predicts its *magnitude*. Estimate, then measure,
and never let the estimate be the finding.

**2. Process-per-invocation timing cannot measure anything this fast.** Timings
taken that way were dominated by startup and were non-monotonic in input size --
native got FASTER as the tree grew (0.154s -> 0.049s), and CPython took 1.18s,
then 0.41s, then 0.15s for MORE input. An empty tree costs 0.00s, so a real
workload needs to be big enough to swamp it, or measure in-process with min-of-N.

**AND THE ONE THAT MATTERS MOST: compare like with like, or you will "find" a bug
that is not there.** Diffing `/tmp/sz .` (full display, including directory
aggregate rows) against CPython's bare `gen_stats()` (flat file table only) showed
"124 files vs 114" and looked like ten spurious directory rows. It was the harness.
Running the real CLI on both sides gives **byte-identical output on the real
`tinygrad/` tree, 131 of 133 lines, the only two differences being `ops: 77` and
`flags: 55`** -- the two `len(Ops)` / `len(ContextVar._cache)` reflection lines
`sz.bend` documents as not portable. A synthetic fixture suite said nothing about
this, because it never contained a real repository.

A speed or equality claim is worthless until you have checked the two sides do the
SAME WORK. This repo already had one instance of that class shipped (a dropped
index aliased a FLOORDIV and printed a plausible answer) and one gate row that
merely restated the code. Check the output before quoting the number.

## CORRECTION to the "32 KiB cliff" entry above -- the number was not reproducible

The entry above claims the interpreter dies at EXACTLY 32768 bytes and calls it a
host constant. **That precision is false.** Re-running the identical 24576-byte
case: it read `exit=0` on a quiet machine and `TIMEOUT >45s` on a loaded one. Load
average was 38.8 on 12 cores -- 3.2x oversubscribed -- at the time of the failing
run.

So the correct statement is:

- there IS a size-dependent failure in the INTERPRETER, and the compiled lane is
  unaffected;
- the threshold is NOT a fixed byte count. It moves with available CPU and memory,
  so ">= 32 KiB dies, below that it is fine" is NOT a usable rule and must not be
  relied on or written into a plan;
- what survives from the original entry is the DIAGNOSTIC: if the interpreter dies
  and the compiled lane is fine, stop hunting for a non-terminating fold in your
  own code. That is still good advice, because the failure really is the host's.

This is the third time in this session that a confident number written into these
notes turned out to be an artifact of when it was measured: first "x100-x1000
slower" (mechanism, never measured), then "124 vs 114 files" (a harness that
compared the full display against a bare `gen_stats`), now "exactly 32768" (a
quiet machine). **Measure under load, or do not claim precision.** A specific
number with no error bar is worse than a range, because the next agent cannot tell
which part to distrust.

## PEER-LANGUAGE REFERENCE SOLUTIONS, FOR THE WALLS THIS PORT KEEPS HITTING

Every wall hit in the sz/render work is a solved problem elsewhere. Not measured-Bend
rules; references so the next agent does not re-derive them.

1. NO MUTATION / accumulators threaded through recursion. Reference: Koka's
   PERCEUS reuse analysis (Xie & Leijen, OOPSLA 2021) -- "Functional but In-Place"
   (FBIP); uniqueness types in Clean (1995); Lean 4 reuses uniquely-owned nodes.
   Bend HAS the static half (+ and &n ownership) but not the reuse pass, which is
   why Array.set does not mutate in place (see the fold.bend Table note).

2. String IS A LINKED LIST OF CHARS (String.trim = two reverses; lex copies the
   file twice via chars() + List.reverse). Reference: Haskell's `text` library
   (the community treats String=[Char] as a mistake it migrated off); Roc built
   packed UTF-8 Str from day one. Until Bend ships packed strings, hot paths
   should consume a char list in ONE pass; do not call String.trim in a loop.

3. NO os.walk / filesystem effects in base.bend. Not a research problem: just
   library maturity (Haskell System.Directory). Keep the foreign effect + TODO.

4. Dev loop where every expectation is manufactured by a hand CPython round trip,
   and bugs slip that reading cannot see. Reference: PROPERTY-BASED TESTING --
   QuickCheck (Claessen & Hughes, ICFP 2000), Hypothesis in Python. State the
   property `forall src. lexer(src) == cpython_tokenize(src)` and generate; the
   sz 4 lexer bugs and the upat repeat bug are exactly what a generator finds.

5. List.append O(n) / spent-on-read accumulators. Reference: Bagwell's HAMT
   (2000) -> Clojure's persistent vectors. Reach for a tree-shaped accumulator
   before threading a List, when the fold is hot.

## NINE MORE RULES, MEASURED 2026-09-30 SPLITTING THE FILESYSTEM WALK OUT OF `sz.bend`

### 1. `--check-only`'s FOREIGN NOTICE IS A "WHO NAMES WHOM" CLOSURE, AND `@unsafe`
###    DOES NOT SHRINK IT

`bend2/main.ts`'s `book_promises` seeds a `bad` set with every def that is
`@unsafe` OR foreign, then floods back along every "names" edge (a def's type and
its body term). So the count is a REACHABILITY closure and the only way to shrink
it is to shrink the set of defs that name the foreign one. Measured on `sz.bend`:
marking `Sz.read_dir` and `Sz.is_dir` `@unsafe` left the count at exactly what it
was, because both were already in the seed set as foreign. `@unsafe` is a promise
you make, not an exemption you take.

The practical consequence is an ARCHITECTURAL one, and it is the same for every
port that needs the filesystem: keep the impure loop in as few defs as possible and
give the pure consumers a value parameter. In `sz.bend` that took the notice from
10 defs to 7 -- the two effects, the three defs of the walk, and the mode dispatch
that has to call it -- and left the lexer, both tables and `gen_diff` proving.

### 2. A `U32` LITERAL PATTERN IS A PREFIX MATCH, AND THE ERROR SAYS NOTHING USEFUL

`case 1: ...` then `case 0: ...` is refused, because `1` claims every successor, so
the `0` arm is dead and the match is not exhaustive. The message is

    - expected : cases for True
    - observed : \{}

which is the checker explaining its `Empty`-match DEFAULT against `Bool`, not your
arm order. Write `case 0:` first, or end with `case _:`. (Same fact as §1.1 rule
9 here, but the diagnostic is the trap, and the first wall cost twenty minutes.)

### 3. `Data` TYPES ARE NOMINAL, so two records with the same fields are TWO TYPES

    type D1 is Data: D1{a: String, b: String}
    type D2 is Data: D2{a: String, b: String}
    def take(d: D2) -> String: ...
    take(make())            #| - expected : D2 / observed : D1

Useful, not a nuisance: it is how `sz.bend` keeps the walk's worklist of
directories (`Dir`) distinct from the list of files it answers with (`It`), even
though both are a path to read and a path to print.

### 4. TWO SELF-CALLS IN ONE ARM IS REFUSED EVEN WITH TWO DIFFERENT `Nat` FUELS

    def p4(k: Nat, j: Nat, n: U32) -> U32:
      match k:
        case 0n: n
        case 1n+r: p4(j, r, U32.add(n, 1))
    #| - expected : a decreasing self-call
    #|             (arguments are read left to right: each passed unchanged until one shrinks)

So a def cannot fold over two lists by recursing twice per arm. This is why
`os.walk` cannot become ONE def over a worklist of directories AND a list of that
directory's names, and why the per-name loop has to be a def of its own that the
caller calls once per directory.

### 5. A LIST SELF-CALL MUST SHRINK ITS FIRST ARGUMENT, SO A GROWING ACCUMULATOR GOES SECOND

    sz.rows(List.append(&2, Row, xs, [rr]), rest)     #| expected : rest, observed : rest
                                                      #|  (consumed more than once) / not decreasing
    sz.rows(rest, List.append(&2, Row, xs, [rr]))     # WORKS

Read left to right, each argument is passed unchanged until one shrinks, so the
tail comes first. The consequence worth remembering: the accumulator may then be
read only ONCE per arm, which rules out the `Bool.pick(cond, rec(xs'), rec(xs))`
shape and wants the pick hoisted into its own `x : List<...> =` binding first.

### 6. AN `IO` EFFECT IS NOT A VALUE: `f(walk(...))` IS A TYPE ERROR, `f`'s arg must be pure

    sz.one(walk(16777216n, Nil{}, [Sz.root(".")]))
    #| - expected : List<&2, Dir>
    #| - observed : @-R:Type -> @k:(@_:List<&2, Dir> -> IO.OP<R>) -> IO.OP<R>

`do` blocks desugar to binds, so an effect in an argument position is read as the
CONSUMER of a bind that has not happened. Bind it in the enclosing block and pass
the name. A `Bool.pick` branch, by contrast, MAY be a `do` block -- that is how
`sz.main` gets three different walks out of three arms.

### 7. A `match` CANNOT FOLLOW A `<-` BIND INSIDE A `do` BLOCK

    do IO<U32>:
      s : String <- IO.get_env("X")
      match s:                  #| - expected : a term (a match heads a def body, not a term)
        case SNil{}: ...

Same rule as everywhere else, restated because the do-block looks like a scope: the
`match` must be the whole body of a def whose parameter is the scrutinee. (So
`sz.main` is a def that takes the argv and matches, and `main` only reads argv.)

### 8. THE INTERPRETER'S PER-FILE BYTE CLIFF IS 28987/28988, NOT 32768

Measured by bisection on both lanes of `sz.bend`, twice, on a 63-space `.js` file
and on an `x=1\n` `.py` file:

    largest passing   28987 bytes
    first failing     28988 bytes   bend: memory fault (machine stack overflow?)

The two lanes AGREE byte for byte, the 63-space `.js` file never runs the lexer
and has the same cliff, and two `.py` files totalling 29000 bytes are fine in the
same process -- so it is a per-file limit on the host, not a lexer depth and not a
per-process total. The "about 32 KB" figure in `spec/sz.md` came from testing only
round sizes (4096..24576, then 32768). Bisect it, do not sample it.

### 9. THE INTERPRETED LANE RE-CHECKS THE WHOLE FILE ON EVERY RUN, SO BISECTING A CLIFF
###    IS DOMINATED BY THE CHECK, NOT BY THE PROBE

Each `./bin/bend FILE.bend ARGS` pays a full proof of all 220 defs before it reads a
byte of the tree, so 21 bisection steps is 21 proofs. If you are measuring something
in the interpreted lane, either budget 20s+ per probe or move the measurement into
the compiled lane and only spot-check the boundary in the interpreted one.

## NINE MORE RULES #2, MEASURED 2026-10-01 WRITING THE `uop/upat.bend` FUZZ DRIVER

### 1. A `match` ON A `String` NEEDS A `case _:`, AND WITHOUT ONE THE ERROR IS A PARSE ERROR

String-literal cases work on a `String` parameter. What does NOT work is leaving
the match without a catch-all, and the diagnostic points at the wrong thing
entirely -- it is a PARSE error about an SCon, at the `match` line, naming a
`{}` that appears nowhere near:

    def pick(tag: String) -> S2:
      match tag:
        case "x": S2A{1}      #| - expected : cases for SCon
        case "t": S2B{2}      #| - observed : \{}
                              #| Location: pick

`String` is a linked list of `Char` and the element type is not closed, so the
match is not exhaustive and the checker says so in the shape it has for a data
type. Adding `case _: S2B{0}` fixes it. THE TRAP IS THE MESSAGE: it reads like
"SCon" and it names `{}`, so the natural reaction is to go looking for an SCon in
the arms, and there is none -- a `SNone{}` three lines down is a red herring.
Measured on both an SCon-returning def and a two-constructor one; the return
type is irrelevant, only the missing catch-all matters.

### 2. `String.take`, `String.drop` and `String.split` CONSUME THE STRING

Every one of them takes their `String` by value, so a def that needs both the
head and the tail of one string needs `+`:

    def src.of2(s: String) -> O.SrcArg:      #| - expected : s
      drv.src.of(String.take(s, 1n),        #| - observed : s (consumed more than once)
        String.drop(s, 1n))

`+s: String` works because `String` is a linked list, so the cost is a reference
count like any other `Data`. This is the general case of rule 1.1 showing up
where nobody expects it: reading a string in two pieces is the most ordinary
thing a parser does.

### 3. `IO.args()` ANSWERS `List<&1, String>`, NOT `List<&2, String>`

A dispatcher that takes the argv tail must be spelled `&1`:

    def dispatch(ps: List<&2, String>) -> IO(Unit):   #| - expected : List<&2, String>
      ...                                            #| - observed : List<&1, String>

`sz.bend`'s `sz.main` takes `List<&1, Dir>` for the same reason. Reading an `IO`
value and then handing its payload to a helper is the only place the lifetime
shows up, and it is the difference between a file that checks and one that does
not.

### 4. `List.get` ANSWERS A `Maybe`, AND `String.get` ANSWERS A `Maybe<Char>`

    String.join(List.get(&2, String, xs, 0n), "")    #| - expected : List<&2, String>
                                                    #| - observed : Maybe<&2, String>
    String.get("abc", 1n)                            #| - expected : String
                                                    #| - observed : Maybe<&2, Char>

So every positional read needs a total wrapper (`upat.bend` grows two: `drv.one`
for `String` and `drv.nth` for `U32`), and `String.split(s, sep)` always answers
at least one piece -- `String.split("", ',')` is `[""]`, NOT `Nil{}` -- so a
`List.is_empty` test on a split result is the wrong emptiness test.

### 5. `String.to_u32` DOES NOT EXIST; `Char.to_u32` DOES, AND IT RETURNS A CODEPOINT

    String.to_u32("42")     #| - expected : a defined name
                            #| - observed : String.to_u32
    Char.to_u32('4')        # 52   (so a digit is `U32.sub(Char.to_u32(c), 48)`)

A decimal parse is therefore a fold over `String.to_list(s)` feeding
`U32.add(U32.mul(acc, 10), ...)`. `String.show` is also absent -- `U32.show`,
`Bool.show` and `Nat.show` are the printers -- and `String.is_empty` is absent
while `List.is_empty` is present, which reads as a typo rather than a gap.

### 6. A `match` INSIDE A `do` BLOCK IS REFUSED, SO DISPATCH GETS ITS OWN DEF

    def main() -> IO(Unit>Unit):
      do IO<Unit>:
        as : List<String> <- IO.args()
        match drv.rest(as):        #| - expected : a term (a match heads a def body, not a term)
          case Nil{}: gate()       #| - observed : 'match'

Same as rule 7 below, and it is the reason `upat.bend`'s `main` is three lines
over a `dispatch` def: argv is an effect, the choice on it is a match, and the
two cannot be one body. The `dispatch` def is the whole of the pattern -- it is
what `sz.bend` does with `sz.one`/`sz.two` and what every argument-reading
`main` in the port has to look like.

## SEVEN MORE RULES, MEASURED 2026-10-01 WHILE PORTING `uop/render.py`

### 1. `Map.put` IS NOT `Map.set`, AND `Map.put` LOSES KEYS
`Map.put` on a one-entry `MLeaf` is `MLeaf{k, x}` -- it REPLACES the leaf and drops
the old key. Three sequential puts gave `d[1]=three d[2]= d[3]=`. `Map.set` is the
inserting one and gives `d[1]=one d[2]=two d[3]=three`. If you are building a dict,
use `Map.set`.

### 2. `Map.get` ANSWERS A `Sigma`, NOT A `Maybe`
    def get.of(r: Sigma<&1, &1, Map<&2, String>, _ => String>) -> String:
      match r:
        case Tuple{m, v}: v
    def get(a: Acc, k: String) -> String: get.of(Map.get(String, "", Acc.mm(a), k))
The `Sigma` type annotation IS the parameter type; `Maybe.default(.., Map.get(..))`
is `expected : Data -- observed : Quant`. `Map.has` is the same shape with `Bool`.

### 3. A RECORD PATTERN MUST NAME EVERY FIELD, IMPORTED RECORD OR NOT
`case O.ParamArg{slot}` is `a ops.ParamArg pattern with 13 fields`. This CORRECTS
the "may name fewer fields" note above: that was measured on a SEVEN-field record
and does not generalise -- and it does not generalise to locally-declared records
either (a three-field `Loc` with `case Loc{a}` is refused the same way). ops.bend
already carries all thirteen ParamArg accessors, which is why the repr reads
through `O.ParamArg.size(pa)` rather than destructuring.

### 4. `case +h <> t:` -- `+` ON A PATTERN BINDER RESOLVES "TWO READS IN ONE EXPRESSION"
Two answers out of one comparison that both feed one expression is the shape
    Bool.or(U32.is_lt(h, g), Bool.and(U32.is_eq(h, g), lt_u32(t, u)))
and neither `h` nor `g` can be a `let` (affine). `case +h <> t:` is the spelling
and it works because `U32` is `Data`. A helper def does NOT rescue it: it calls
back into the walk and that is the mutual recursion Bend refuses.

### 5. A SELF-CALL WITH A COMPUTED ARGUMENT IN FRONT OF THE TAIL IS NOT DECREASING
    def tr_all(+ss, +ar, +tr): match ss: case s <> t: tr_all(ar, tr_set(tr, s), t)
is refused; `tr_all(t, ar, tr_set(tr, s))` -- list FIRST -- is accepted. So the
shrinking argument has to be the FIRST parameter whenever another argument is a
computed value.

### 6. A `Nat` COUNTDOWN IS THE ONLY COUNTDOWN A U32 LOOP GETS
`tuple(range(n))` for a `U32` n cannot be a `U32` self-call (`expected : a
decreasing self-call`); it has to be `range_tuple.go(n: Nat, +p: Nat, acc)` with
`case 1n+p:` consing `U32.from_nat(p)`. The consed value and the fuel are the same
`p`, which is why `p` is `+`.

### 7. `Bool.pick(-A, c, a, b)` ANSWERS `a` WHEN `c` IS TRUE -- AND GETTING IT
###    BACKWARDS EMITS A PLAUSIBLE STRING
`CallInfo(None, None, False, False)` for every dtype is what a flipped `Bool.pick`
looks like: it typechecks, it runs, and it is a string, not a crash. Three gate
rows over void / int32 / weakint caught it. `acall_void` also had to stop testing
`pri == 0` -- `S.void()` and `S.weakint()` BOTH have priority 0, so the void test
is `cls == CVoid`.

## THE UPAT DEDUP DIVERGENCE, ROOT-CAUSE CHAIN (2026-10-01, depth-8 fuzz case)

Symptom: same tag-filter node reachable via two clause branches gets ONE `a{n}`
in CPython (`tag in a2` everywhere) but a FRESH number per path in the port
(`tag in a7`), so the compiled text and the dyn_lookup arity differ. Gate rows
stay green; only the fuzzer at --max-depth 8 sees it.

Chain, each link verified by reading the code:

1. `wrap` is ONE walk over the WHOLE processed clause tree, threading a Bind
   list `d` and a counter `n` (upat.bend wrap.go / wrap.found). The dedup env
   IS global -- the bug is NOT a per-clause reset.
2. The dedup KEY is `eq_lit(Bind.lit(b), lit)` -- Lit VALUE equality.
3. `eq_lit` covers every Lit constructor, including LTag via O.eq_tag_list.
4. `O.eq_tag_list` compares lists ELEMENT-WISE IN ORDER. Python's tag filter
   is a FROZENSET. Order-sensitive list equality vs set semantics -- the same
   defect family as eq_cls (missing CWeakFloat arm) and eq_addr (Aalu answered
   as AReg): an equality predicate that does not match Python's semantics.
5. Python's `wrap` dedups by CLAUSE-NODE IDENTITY (each clause graph node is
   wrapped once), not by literal value. The port's value-keyed dedup and
   Python's node-keyed dedup agree on TREE-shaped patterns and diverge on
   DAG-shaped ones, where get_clause materialises one arena node into several
   clause positions.

The fix must make the port's dedup agree with CPython's on the harness case
(upatfuzz --seeds 51 --max-depth 8). Candidate directions, in order of
fidelity: (a) key the dedup by clause-node identity as Python does; (b) make
the list equalities set-semantics where Python's are sets; measure which one
CPython's _get_clause actually exhibits BEFORE choosing -- read upat.py.

## FIVE MORE RULES, MEASURED 2026-10-01 WRITING THE `uop/divandmod.bend` FUZZ DRIVER

### 1. A `match` MAY NOT SCRUTINISE A COMPUTED VALUE -- THE `.go` SPLIT IS NOT OPTIONAL

    def dmc.num(s: String) -> U32:
      match String.starts_with(s, "-"):        #| - message : a parameter or field scrutinee
        case True{}: ...                       #| - observed: (a match cannot scrutinize a computed value)

The rule is already known for a PROJECTION (`n.f` parses as a name lookup); this
is the same rule for a CALL. Every `def f(x) -> T: match g(x): ...` must become
`def f.go(gx: T, x: T) -> R: match gx: ...` + `def f(x) -> R: f.go(g(x), x)`.
The error names the scrutinee expression, which is the useful half: it points at
the CALL, not at the `match`.

### 2. THE `+` PROPAGATES ONE READER DOWN, AND `List<&2, T>` IS NOT `List<&1, T>`

    def dmc.den.mul(ar: O.Arena, m: U32) -> U32:
      U32.mul(dmc.den.c(ar, O.Arena.src0(ar, m)), dmc.den.c(ar, O.Arena.src(ar, m, 1)))
      #| - expected : m     - observed : m (consumed more than once)
      #| Context: - ar : O.Arena
    def dmc.den.mul(ar: O.Arena, +m: U32) -> U32: ...   #| - expected : ar  - observed : ar (consumed more than once)
    def dmc.den.mul(+ar: O.Arena, +m: U32) -> U32: ...  # ok

The compiler does NOT tell you the whole chain: it stops at the first parameter
it can blame, names THAT one, and prints the rest as `Context:`. Fixing the named
one exposes the next, so the arithmetic above took four compiles to green. The
lesson is that `+` is transitive UP the call chain, not just local to one def --
budget an edit per error rather than assuming one error is one fix.

### 3. A `Maybe` FROM `List.get` NEEDS THE SPLIT EVEN INSIDE A `match` HEAD POSITION

    def dmc.two() -> List<&2, O.Op>:
      match List.get(&2, O.PMEntry, O.PMEntrys.es(dm_table()), 2n):
        case Some{e}: O.PMEntry.ops(e)      #| - message : a parameter or field scrutinee
        case None{}: Nil{}

Rule 1 again, and it is the one that bites a PARSER hardest because a parser is
mostly `match` over `Maybe`s read out of a list. The split is mechanical and
`upat.bend`'s `drv.one` / `drv.nth` are the precedent: one total reader per
element type, and the `match` reads a PARAMETER.

### 4. AN ARENA IS A `Data`, AND `Found.ar` / `Found.i` ARE NON-CONSUMING READERS

    def dmc.of.put(+f: O.Found) -> String:
      dmc.of.put.go(dm_zero(O.Found.ar(f), O.Found.i(f)),
                    div_and_mod_symbolic(F.folded(O.Found.ar(f)), O.Found.i(f)))   # ok

Three reads of one `+Found` check, because `Found.ar`/`Found.i` are
`def Found.ar(f: Found) -> Arena` -- no `+`. So a LINEAR record's readers need
no `+` themselves and a `+` value can be read any number of times THROUGH them.
This is the opposite of `String.take`/`String.drop` (rule 2 of the `upat.bend`
set above, which DO consume), and the two being opposite is the whole trap:
whether a reader consumes depends on whether the type is a linked list or a
record.

### 5. AN UNFILLED LAW IS A HARD ERROR, SO A DEF MUST BE DEFINED BEFORE IT IS CALLED

    def dmc.of.put(+f: O.Found) -> String:
      dmc.of.put.go(...)                       #| - expected : a filled definition
                                               #| - observed : dmc.of.put.go   (an unfilled law is a dead claim)

Bend is order-sensitive top-to-bottom. The `go`-before-caller convention that
makes rule 1's split work is ALSO what makes this necessary, and the two rules
pull in the same direction: **define the leaf `match` first, call it second**.
Reading order top-to-bottom is the one habit that satisfies both.

## SYMBOLIC.BEND — TWO FINDINGS FROM THE FUZZ ATTEMPT (file restored to green)

The symbolic fuzz agent broke the file mid-driver and was rescued by restoring
its last verified copy (`_sym_dbg.bend`). Its driver work was discarded; these
two READING findings survive and are ungated:

1. sym_10 (symbolic.py:463, `UPat.var("x") * UPat.var("x")`) is a REAL DIVERGENCE
   the port's own header half-documents: Python's UPat cache INTERNS BY NAME, so
   the second `var("x")` is the same STORE that the first overwrites -- the
   compiled form matches 1/(x*y) too. The port's `p_same` check is STRicter, so
   it matches strictly FEWER nodes than Python. The gate's `sym_rebind` pair
   covers only sym_7 and sym_8. Decide: match Python (drop the check) or record
   the divergence as deliberate; either way it needs a row.

2. symbolic.py:124 `((x%y)%y -> x%y)` is DEFERRED but invisible: absent from
   sym_table AND from the TODO block, so `skip=114`'s arithmetic does not count
   it. A rule absent from both is a bookkeeping hole, whatever the reason.

Driver lessons (its design notes are in the file history): the s-expr tokenizer,
Frm/St arena builder, and IO.args() convention were sound; the fz_jobs fuel must
be ONE Nat split across branches -- a rebuilt `[a] <> rest` is rejected by the
checker ("expected a decreasing self-call"), and List.range(4096n) is not in
Base's surface the way it was used.

## FOUR MORE RULES, MEASURED 2026-10-01 WHILE FIXING THE UPAT WAITLIST

### 1. A FOLD THAT ALSO CARRIES A CHANGED-BIT MUST `or` THE WHOLE LIST, NOT THE HEAD
`proc.go` returns `Pg{cs, ch}` per LIST, and the list's `ch` has to be
`Bool.or(head's ch, tail's ch)`. Returning the head's bit alone type-checks,
`--check-only` is green, and the gate is green, and the fold is wrong: a parent
reading `b.ch` sees only its FIRST child, so it runs while a LATER sibling is
still moving. Caught by `store_ord` and `deep` below, and by `upatfuzz` seed 40.
`proc.join` is one line and it is the whole difference between the two builds.

### 2. `+` ON A `Data` FIELD BINDER IS A COPY AND IS NEEDED TO USE IT TWICE
`case Pg{+cs, ch}:` then `C{op, lit, cs}` and `do_process_and(op, lit, cs)` in one
expression. Without the `+`: `cs (consumed more than once)`. The same on a
parameter (`def f(+a: Pg, +r: Pg)`) and on a list binder (`case +c <> t`).

### 3. A `match` CANNOT SCRUTINISE A COMPUTED VALUE -- GIVE IT ITS OWN DEF
    match Pg.ch(b):                     #| - expected : a term
                                        #| - observed : 'match'
`match b: case Pg{cs, ch}:` then `match ch:` nests, and the record binder is the
scrutinisee. This is why `proc.node` is a separate def from `proc.step` rather
than one `Bool.pick`.

### 4. A DEF MUST BE DEFINED BEFORE IT IS CALLED, AND THAT IS NOT DEF ORDER
`proc.node` calling `proc.go` is fine in either order, but a def calling a LATER
def is `a filled definition (an unfilled law is a dead claim)` -- a message that
names the callee and not the caller, so it reads like a `LAWS.bend` problem. And
`dbg.go` calling `dbg.node` calling `dbg.go` is refused outright: MUTUAL RECURSION
IS OUT, so a recursive printer has to carry its own fuel AND its own name
(`dbg.op` for the leaf case) instead of splitting into two mutually recursive
defs. Same answer as rule 5 of the SEVEN MORE RULES, reached from the other side.

### 5. A `Nat` FUEL BOUND IS A BOUND, AND A WAITLIST MAKES IT MUCH LOOSER
`proc_fix` used to be a fixpoint on a DEPTH (splice one AND level per round) and
`8 * len(upats)` was ample. It is now the `unified_rewrite` WAITLIST -- a node
runs its rule only when its children are final -- and the deepest shape the
fuzzer reaches needs 33 to 48 ROUNDS for FIVE arena UPats, i.e. 9 to 12 rounds
per UPat. `8n` was short by four rounds and the port answered `NONE` where
CPython answered five lines of clause. `12n` is the smallest multiplier that
reaches the fixpoint; the file uses `32n`. A BOUND may be over-provisioned and
costs nothing -- an under-provisioned one is a silent wrong answer, and it is
the WORST failure mode in the file because every other row still passes.

## FOUR MORE GENERAL RULES, MOVED OUT OF movement.bend AND weak.bend 2026-10-01

A pass over `uop/movement.bend` and `uop/weak.bend` cut their comments back to tinygrad's
shape. These four were general Bend rules living in those files' headers; they are recorded
here so the next agent does not re-derive them from a file that no longer states them.

1. **A PAIR IS A `Type`, SO A TWO-FIELD `Data` RECORD IS THE SPELLING OF `(A, B)` -- AND A
   `Type` CANNOT BE A LIST ELEMENT.** Already recorded for `Found` ("an `Arena & U32` pair
   is a `Type` and cannot carry a `+`", this file's THE ENGINE SHAPE) and for `Seen.parts`;
   what the files were also carrying locally is the LIST half: refused with
   `expected : Data / observed : Type`. That is why movement.bend's `Marg` -- Python's
   `(o, n)` margin pair -- is a two-field `Data` record and not the tuple
   `(H.I64 & H.I64)`: `List<&2, H.I64 & H.I64>` does not compile.

2. **A `Maybe` CANNOT BE A FOLD'S ACCUMULATOR.** `Maybe<a, A>` is affine and has no `+`
   spelling, so it cannot be threaded through a recursive walk. Two consequences seen in the
   port: a fold whose accumulator would be a `Maybe` is written as TWO folds over the same
   list (movement.bend's `as_shape.allc` + `as_shape.vals`, splitting
   `tuple(s.val if s.op is CONST else ssimplify(s) ...)`), and an answer that must be read
   twice is hoisted into a `Data` record carrying a `Bool` plus the value (weak.bend's
   `Dts` for `derived_dtypes`, `ODt` for `commit_weak_consts`'s `dt:DType|None`).

3. **THE FOLD-VERDICT SHAPE: ONE DEF, THE ELEMENT'S VERDICT AS A PARAMETER.** A fold over a
   list whose accumulator is a `Bool` and whose step needs to READ the accumulator cannot be
   written `.go` + wrapper: the wrapper would call the fold and then need the fold to call
   it back, which is mutual recursion. The port's shape is a single def taking the
   accumulator as a PARAMETER and matching on the ELEMENT in the head -- movement.bend's
   `mp_ident.at` and `mp_5.each.at`, whose comments both name the reason. Same family as "a
   `match` may not scrutinise a computed value" above; this is the fold-shaped escape from
   it.

4. **A LIST BINDER, LIKE A PARAMETER, IS READ-AT-MOST-ONCE.** `case m <> t:` with `m` of
   record type gives an affine binder, so `Marg.o(m)` and `Marg.n(m)` in one expression is
   refused exactly as a parameter used twice would be. `+` on the pattern binder fixes it
   (the render.bend entry "`case +h <> t:` -- `+` ON A PATTERN BINDER RESOLVES TWO READS IN
   ONE EXPRESSION"), or hoist the pair into a def taking the record whole, which is what
   movement.bend's `marg_pair.of` does.

## FOUR MORE RULES, MEASURED 2026-10-01 WHILE PORTING `uop/divandmod.bend` and
## `uop/symbolic.py`

Appended, not edited. All four are Bend 2.0.34 / substrate facts, so they were
cut out of the two `.bend` headers where they had drifted into file-local prose.

### 1. A 64-BIT PRODUCT IS A WALL, NOT A TODO: `base.bend` DOES NOT EXPORT `Word`

`Word.mul` is the only widening multiply in Bend 2, and `base.bend` does not
export `Word`'s constructors -- `match Word.mul(64n, ...)` from outside the file
is refused with "a declared constructor (unknown: Word.Nil)". So a magic multiplier
(anything needing a 64-bit product) cannot be written from a `.bend` file at all,
and that is a wall of ONE export: either `Word` and `WCon` become public, or the
port writes the product as four `U32` multiplies and a carry chain (`U32.mul`
already truncates mod 2^32, so it composes).

The same wall one level up: `H.I64{hi,lo}` exists in `helpers.bend` with
`i64_add` / `i64_sub` / `i64_cmp` and NOT `i64_mul` / `i64_div` / `i64_mod`. So
`UOp._min_max` and `const_factor` are blocked on arithmetic, not just on shape.
`_min_max` is the unlock for five of `divandmod.bend`'s TODOs and nine of
`symbolic.bend`'s, which is why it is the first item in both "WHAT NEXT" lists.

### 2. TWO FIXTURE BUILDERS THAT RETURN AN INDEX ARE THE SAME TRAP AS ONE

The `divandmod.bend` version (`Arena` is affine, so a fixture builder that returns
`-> U32` throws the grown arena away) is recorded above as "A FIXTURE BUILDER THAT
RETURNS AN INDEX THROWS THE GROWN ARENA AWAY". The `symbolic.bend` variant is
slightly different and worth separating: there the rule table itself returns
`Maybe<&1, U32>`, so a gate row cannot read the rewritten node back at all, because
`Arena.node` answers `Arena.bottom` for an index past the end. The rows that work
around it are "did the rule fire" (a `Bool`) plus "what is the value" (computed by
calling `exec_alu` directly). **`Maybe<&1, O.Found>` is the shape a growing rule
should have** -- `Found` is `Data`, so it is expressible -- and it is the first
change to make when a rule table passes a dozen entries.

### 3. A GATE ROW THAT SAYS WHAT A BOOLEAN CANNOT IS NOT OPTIONAL

`x // x -> 1` needs TWO rows: one where the two srcs are the SAME node and one where
they are two DIFFERENT nodes. Drop `U32.is_eq` from the pattern and the positive row
still passes -- so the pair is the only thing that can see the identity check
disappear. Two instances in this port (`sym_7`/`rebind`+`rebind0` and
`sym_8`/`xorb`+`xorb0`), both measured.

The negative side must ask for ABSENCE, not for an index: written as `eq_u(m, 0)`
the row is satisfied by any wrong-but-present answer. Ask `Maybe.is_none`.

And the same shape for first-wins: a fixture where the two claiming rules AGREE
cannot distinguish first-wins from last-wins at all.

### 4. A `list`-TAIL FOLD THAT MUST HAND SOMETHING BACK CARRIES IT IN A RECORD

`upat.bend` records "A `Data` RECORD IS HOW A LIST TRAVERS WITH SOMETHING DERIVED
FROM IT" for `Shapes{ds, m}`. The `symbolic.bend` form is the same fact one level
up: an s-expr builder pushes a frame on `(`, pops it on `)`, and the finished node
has to get OUT to the frame above -- which a list tail cannot carry, because the
tail is the only thing that survives the recursion. So the answer rides in the
STATE (`St{ar, stk, root}`) rather than in a return value, and the walk is one
def. The same shape is `exec_alu`'s `Opr{fit, bits, f}` and `rm_0.ok`'s
`(hit: Bool, ok: Bool, ..., z: U32)`: whenever a fold must answer both a thing and
a fact about it, both travel together.

## SZ PERFORMANCE BASELINE, MEASURED 2026-10-01 (load recorded, min-of-N, floors subtracted)

Whole tree (114 files, 25591 lines, 2.04 MB): compiled sz.bend work = 165 ms vs
CPython gen_stats 369 ms at load 27-34 -> 2.24x FASTER. Per-file lexing of
uop/ops.py (110 KB): 8.1 ms vs 18.4 ms at load 47. Ordering stable across a 3x
load swing (min +-3%). Verdict: keep as-is; the owner ruled, and the profile
backs it (the per-char step's 5-deep call chain dominates, not the state width).

A measured-and-reverted option exists: deleting chars()'s two per-file copies
(String-fuel lexer) is -18% tree / -11% file and -7 LOC, byte-identical, patch
at /tmp/opencode/szbench/OPTION-string-fuel.patch. Not applied: owner said keep;
the mutation table was not re-run under it.

TWO SEMANTICS FINDINGS (decisions, not speed):
1. Fuzz seed 13 fails at --seeds 30 on the KNOWN rounding divergence: 109/20 =
   5.45, CPython %.1f formats the double 5.4500000000000002 as 5.5, exact
   rational rounds 5.4. So 'fuzz-green at 30 seeds' was never true; the real
   tree is green because no counted file hits an exact tie. Record before
   anyone treats a red --seeds 30 as a regression.
2. LATENT .js-LANE DIVERGENCE: base.bend Char.is_space = {0x20} U [9,13]; Python
   str.isspace also holds 0x1c-0x1f, 0x85, 0xa0, 0x1680, 0x2000-0x200a, 0x2028,
   0x2029, 0x202f, 0x205f, 0x3000. A line like \x1c//c counts for the port, not
   CPython. sz.bend's is_hspace already includes 28-31 (internally inconsistent).
   No tree file and no fuzz fragment hits it -- latent, not live.

---
Measured on 2.0.34 while porting `tinybendygrad/mixin/dtype.bend`. Four new rules, and
one correction to an old one.

1. `def some: U32 == other` is REFUSED -- "expected a term, observed '='". There is no
   `==` on `U32`; it is `U32.is_eq(a, b)`. This is separate from rule 9 below, which is
   about `+`/`-` needing an annotation. A sed that writes `==` produces a parse error
   whose message names `':'`, not the operator, so it reads like a match-syntax bug.

2. `case _ <: f(x)` is NOT the catch-all spelling of a numeric countdown. It parses as
   "expected a term, observed ':'". `case _:` is the catch-all; and when the scrutinee
   is a `Nat` that is also the fuel, destructure it as `case Succ{p}:` and recurse on `p`
   (the shape helpers.bend:399 and :474 already use). That gives a decreasing self-call
   with no `Nat.sub` and therefore no type annotation, which is the real point.

3. A def whose name merely LOOKS like a qualified name is not rescued by existing: writing
   `F.Founded` instead of `F.Folded` compiles to "expected a defined name, observed
   'F.Founded'", which is indistinguishable from rule 1 (no forward reference) unless you
   notice the name is misspelled. Check the spelling before hoisting anything.

4. CORRECTION to the brief's rule 4 area: `Maybe<&1, T>` and `Maybe<&2, T>` are NOT
   interchangeable in a parameter position, and the error names the LIFETIME, not the
   type -- "expected : Maybe<&2, U32>, observed : Maybe<&1, U32>". A `Data` field holding
   `List<&2, Maybe<&2, U32>>` pins its consumer helpers to `&2`; every shared file that
   passes a `Maybe` around already uses `&2` (fold.bend:270, helpers.bend:435). Do not
   write `&1` in a helper that receives one of those.

5. `Some{v}` with an unused binder is REFUSED -- "a Some pattern with 1 field" (this is
   rule 14 in the brief, re-measured, and it applies to `Maybe` as well as to records).
   The one-line shape `case Some{}: False{}` is NOT available. For a predicate that
   ignores the payload the honest spelling is a tautology on the payload, e.g.
   `case Some{u}: Bool.not(U32.is_zero(U32.sub(u, u)))`, which reads as "always False"
   without naming a sentinel. CAUTION: that shape is easy to get wrong in the other
   direction -- see the mutation note in mixin/dtype.bend, where `u32_none` was first
   written `Bool.not(U32.is_zero(v))`, which is TRUE for any non-zero value and silently
   inverted the whole refusal test. A `Some` arm that is supposed to be a constant False
   is the highest-risk line in a gate file.

---

## Measured by the `schedule/memory.py` port, 2026-10-01. Reproducers in this section.

### A. `List.append` IS `xs ++ ys` -- IT APPENDS. It is the single most expensive
###    misreading in this port, and everything downstream of it looks like a Bend bug.

`List.append(a, -A, xs, ys)` (base.bend:822) is `xs ++ ys`: **`ys` lands at the
TAIL.** So an accumulator fold written `List.append(&2, T, acc, [x])` builds the list
in FORWARD order, and one written `List.append(&2, T, [x], acc)` PREPENDS.

Reproducer, one line, `.agents/slop/notes/probe-list.bend`:

    List.append(&2, U32, [9], [8])        -- head 9, second 8
    List.append(&2, U32, [8], [9])        -- head 8, second 9

**Both `List.append` and `List.reverse` are correct.** `List.reverse` reverses a
literal list, a computed list, a one-field record and a three-field record
(`probe-list.bend`, `probe-list2.bend`). An earlier revision of this file claimed
`List.reverse` "silently stops reversing once the fold is two steps deep". **That
claim is FALSE and is retracted**: the accumulator in that experiment was being read
backwards because the code PREPENDED where it meant to append, and the reverse was
faithfully reversing a list that was already the wrong way round.

`List.sort` is correct and STABLE -- see section B.

### B. `List.sort` IS STABLE, AND A COMPARATOR THAT SAYS FALSE IN BOTH DIRECTIONS
###    SORTS IN REVERSE. The comparator is where the bug is, always.

`List.merge.step` (base.bend:1015-1023) takes `x`, the FIRST run's head, whenever
`le(x, y)` holds, and `le` is a `<=`. That is a stable merge. Measured with
`.agents/slop/notes/probe-sort-stability.bend`: tied runs of 2, 4 and 6 came back in
input order, and `[k2,k1,k2,k1,k1,k2]` came back `[k1,k1,k1,k2,k2,k2]` with each key
class in input order.

**The failure mode is a comparator that returns `False` for every DIFFERING key** --
"only ties are comparable". It typechecks, it proves, and it makes `List.sort` return
the list in REVERSE key order, because a comparator that says False in both directions
makes every merge take the second run's head. There is no diagnostic anywhere in that
chain. If a sort output looks reversed, check the comparator before you check
`List.sort`:

    def ev_cmp(same: Bool, ai: U32, ao: U32, bi: U32, bo: U32) -> Bool:
      match same:
        case True{}: U32.is_le(ao, bo)   # the tie-break
        case _: U32.is_le(ai, bi)        # NOT False{} -- this is the whole key

This was measured, not guessed: it is the bug that moved sixteen rows of
`schedule/memory.bend`'s gate at once, and the count row stayed green throughout.

`List.sort`'s comparator parameter type is `~A -> A -> Bool`, so `+` on its parameters
is REFUSED -- "expected : @_:Ev -> @_:Ev -> Bool, observed : @+a:Ev -> @+b:Ev -> Bool".
It is the one place in the `schedule/` port where `+` had to be REMOVED rather than
added.

### B. A "match on the hit, else recurse" PAIR IS MUTUAL RECURSION, and a
###    `found: Bool` ACCUMULATOR IS THE ONLY SPELLING THAT COMPILES.

    def find(hit: Bool, ls: List<&2, A>, k: A) -> Bool:      # looks fine
      match hit:
        case True{}: True{}
        case _: find.go(ls, k)                                 # ... and calls BELOW

    def find.go(ls, k):
      match ls:
        case e <> t: find(hit(e, k), t, k)                     # ... which calls UP

One of the two is always a forward reference. The shape that works is a fuel def whose
only `match` is on the fuel, with the Bool folded into an accumulator:

    def find(fuel: Nat, ls: List<&2, A>, k: A, found: Bool) -> Bool:
      match fuel:
        case 0n: found
        case 1n+p: find(p, List.tail(&2, A, ls), k, Bool.or(found, hit(...)))

`Bool.or`/`Bool.and` on an accumulator is the general answer to "find the first /
find the last" over a list, and it is what `mem_first_i` and `mem_last_i` in
`schedule/memory.bend` are.

### C. FUEL IS `len` FOR A TERMINAL FOLD AND `len+1` FOR AN INSERTING ONE. Getting
###    them the same way round is how a value lands in a list twice.

A fuel fold whose `Nil{}` arm RETURNS THE ACCUMULATOR needs `fuel = len`: `case 1n+p:`
consumes the head immediately, so `len` already visits the last element and `len+1`
visits one past the end. A fold whose `Nil{}` arm INSERTS needs `len+1`, for the same
reason. In `schedule/memory.bend` both spellings are live in the same file:

| fold | `Nil{}` arm | fuel |
| --- | --- | --- |
| `mem_touch` | returns the accumulator | `len` |
| `mem_first_i` / `mem_last_i` | returns the accumulator | `len` |
| `mem_lane_in` | returns the accumulator | `len` |
| `mem_scan` (the kernel walk) | returns the accumulator | `len` |

and the inserting case, which was the bug: a rebuild-on-every-touch fold whose last step
appends a new entry. With `len` it never reaches the insert and the value is lost; with
`len+1` the `Nil{}` arm runs on a call that already found the entry and appends a
DUPLICATE unless the insert is gated on a `found` flag threaded through the fold. Both
failure modes were measured (a buffer in `first_appearance` twice, then a buffer in it
zero times).

### D. `List.head` ANSWERS A `Maybe`, NOT A VALUE.

    def red_head_of(m: Maybe<&2, U32>) -> U32: Maybe.default(&2, U32, m, 0)
    def red_head(+xs: List<&2, U32>) -> U32: red_head_of(List.head(&2, U32, xs))

`Maybe.default`'s FIRST argument is the LIFETIME, and it must match what `List.get` /
`List.head` return (`&2`). A one-line `red_head` that inlined both runs out of lifetime
budget the moment it is read twice, which is what makes the `.of` split look arbitrary
until you hit it. `schedule/allreduce.bend` calls it `red_head` and
`schedule/memory.bend` calls it `mem_head`; the two are the same def.

### E. A TWO-SCRUTINEE `match` WITH A `Nat` COUNTDOWN NEEDS NO `0n` ARM ONLY IF
###    THE COUNTDOWN IS NOT ALSO A PATTERN BINDER. `case 1n+p _ <> t:` is REFUSED.

    #| - expected : 2 patterns (one per scrutinee)
    #| - observed : '1n+p Nil{} _'
    match fuel todo:
      case 0n _: ...
      case 1n+p Nil{} _: ...          # <- two scrutinees, one pattern

This is rule 14 in the brief with a `Nat` added, and it is worth stating because the
error says "patterns", not "scrutinees". The two-dimensional match is not available;
split the fuel check into its own def.


## Appendix, measured in `tinybendygrad/schedule/__init__.bend` (2026-10-01)

Five shapes that cost that file most of its compile cycles, all of them REFUSALS
or near-misses. A probe for each is at `.agents/slop/notes/p-sc-{1..5}.bend`.

### A. A `match` nested inside a `case h <> t:` LIST arm is REFUSED

    def go(fuel: Nat, cls: U32, xs: List<&2, U32>, acc: U32) -> List<&2, U32>:
      match fuel:
        case 0n: acc
        case 1n+p:
          match xs:
            case Nil{}   : acc
            case +x <> t :
              match cls:                      #| - message : a match on a parameter or field
                case 0: ...                   #|             (this name is a def or a consumed
    #|                                          #|              binder: give the value its own def)

Refused for a `Bool`, a `U32` and a `List` scrutinee alike. A List arm may hold a
CALL (`body(next, acc)` is fine) but never a `match`. Two escapes, and the port
uses both:

1. Put the decision in a PARAMETER and match it in the def's own body. `st.go`
   takes `cls: U32` and matches `fuel cls` two-scrutininee, so the pop and the
   decision live in one def.
2. Split the def and let exactly one of the pair recurse. `ln_go.pop` holds the
   List arm and calls `ln_go`, which is declared ABOVE it. A cycle is impossible
   because only one member recurses.

### B. A `match` nested inside a `Data`-RECORD arm: Bool refused, Nat and List fine

    def pick(is_k: Bool, s: U32, sp: Split) -> Split:      #| - message : a match on a parameter
      match sp:                                            #|             or field ...
        case Split{ks, ds}:                                #|
          match is_k:                                      #| <-- REFUSED

while `case Split{ks, ds}: match n: case 0n:` and `case Split{ks, ds}: match ys:`
both pass, and `match t: case Nil{}: ... case x <> rest: <a call>` passes. So the
refusal is about the INNER scrutinee's KIND, and the cheap answer is a
TWO-SCRUTINEE match over two `Bool` PARAMETERS, which needs no nesting at all:

    def sp_put(ker: Bool, aft: Bool) -> U32:
      match ker aft:
        case True{}  _       : 0
        case False{} True{}  : 1
        case False{} False{} : 2

### C. A self-call may not pass a COMPUTED argument before the SHRINKING one

    ka_go(Bool.or(found, U32.is_eq(j, key)), t, key)   #| - expected : a decreasing self-call
    ka_go(t, Bool.or(found, U32.is_eq(j, key)), key)   #| OK

"read left to right: each passed unchanged until one shrinks". So an accumulator
that ACCUMULATES has to sit after the list argument, which is why `found` is
`ka_go`'s SECOND parameter in `ka_go` / `da_go` / `wa_go`.

### D. A `Bool` match IS legal in a numeric arm, which makes the `.step` helper a MUTUAL RECURSION

    def unwrap.go(fuel: Nat, go: Bool, +ar: O.Arena, +s: U32) -> U32:
      match fuel:
        case 0n   : s
        case 1n+p :
          match go:
            case True{} : unwrap.go(p, sc_go(ar, sc_src0(ar, s)), ar, sc_src0(ar, s))
            case False{}: s

This is what `Topo.step` cannot do: `step` needs `n in cache` (a call) and a
decision, and a helper holding that decision has to call back into the fold, so
the pair is mutual and declaration order makes one member a forward reference --
reported as "an unfilled law is a dead claim: live code cannot use it", which is
the message for a MIS-ORDERED def and not for a dead stub. Making the decision a
parameter removes the cycle and the helper with it.

### E. `List.append` is `xs ++ ys`, so a REBUILD scan must cons and an ACCUMULATOR must append

    # rebuild -- the entry goes back IN FRONT of the rebuilt tail
    List.append(&2, Dep, [Dep{j, d + n}], r)      #| OK
    List.append(&2, Dep, r, [Dep{j, d + n}])      #| OK TOO, AND WRONG

Both compile, the second silently relocates the entry to the end, and `List.length`
of the rebuilt table does not move -- which is the shape of bug this port keeps
finding: three such scans here cost an afternoon (`in_degree` ended up with five
keys for three kernels and a Kahn loop that never drained). An accumulator is the
other way round, so the SAME builtin is right and wrong in adjacent arms.

## TWO REPORTS AND THREE RULES, MEASURED 2026-10-01 PORTING `schedule/rangeify.py`
## R1 and R2 FIXED 2026-10-01 -- see the FIXED sections below for the evidence and for
## FOUR more defects the two reports could not see.

### R1. FIXED: `mp_nsrc_ge` IS NOW `n <= nsrc`, AND THE FIX IS NOT THE WHOLE STORY.

    # `len(x.src) >= n` -- `allow_any_len=True`'s "at least n srcs". `U32.is_ge`, NOT
    # `U32.is_lt(n, nsrc)`: the name is the whole contract, and one arity is the entire
    # content of a rule's arity test. A `len(x.src) == n` test is `mp_nsrc_is` -- this is
    # `>=` and nothing else, so `mp_5.one`'s STRICT two-tuple is `mp_nsrc_is`, not this.
    def mp_nsrc_ge(ar: O.Arena, i: U32, n: U32) -> Bool:
      U32.is_ge(mp_nsrc(ar, i), n)

The report was right that the name and the body disagreed, and right that the
distance is one arity. It was WRONG that `mp_nsrc_ge(ar, i, 2)` "passes on a
three-src node" was the defect's whole reach: the fix is `U32.is_ge`, and the
second half is that **`mp_5.one` should not have been calling this at all**. Its
pattern is `UPat(INDEX, src=(UPat.var("src"), UPat(CONST)))` -- a two-TUPLE, so
`strict_length` is on and the test is `== 2`, which is `mp_nsrc_is`. With
`U32.is_ge` in place, `mp_5.one` now reads `mp_nsrc_is(ar, x, 2)`.

MEASURED, `mop-mut.py` M2 (revert `mp_nsrc_ge` to `n < nsrc`): moves TWO rows,
`const_idx2` and `idx_pick` -- both the two-src INDEXes, which a `> 2` test
rejects. M9 (relax `mp_5.one` to `>= 2`): moves NOTHING, because every stacked
element in the fixture is a two-src INDEX, so the stricter and looser tests agree
on this fixture. The arity test is load-bearing (M2 proves it) and M9 records
that the gate does not yet separate `==` from `>=` there.

### R2. FIXED: `hop_self` WAS INVERTED, AND THE GATE WAS PINNING IT. FOURTEEN ROWS
###     DEPENDED ON THAT FIXTURE-BREAKING BUG.

    # `ret is not uop` -- ops.py:1611. ... `drop` is "the answer IS self, OR the answer
    # IS none", and `True` must answer NOTHING: keeping `self` and dropping a genuinely
    # new node is the inverse of ops.py:1610 and of this comment, and `t_ret_new` is the
    # row that pins it.
    def hop_self.of(drop: Bool, +r: Hop) -> Hop:
      match drop:
        case True{}: Hop{hop_ar(r), 0}
        case False{}: r

The report was right, and its own last paragraph was the important part: "do not
read the zeros as `hop_self`". It was right for a reason stronger than it gave.
**The gate's own fixture index list was missing the arena's bottom**, so
`G.at(g, n)` was one node PAST the one every row's comment names. That is a THIRD
defect, in the gate rather than in a rule, and it is what made half the rows read
0 and masked the rest.

THE THREE FIXES, and the evidence for each, all in
`tinybendygrad/uop/movement.bend`'s mutation table (`mop-mut.py`):

| fix | mutation | rows moved |
| --- | --- | --- |
| `hop_self`'s arms | M1 | **14** |
| `mp_nsrc_ge` | M2 | 2 |
| `G.ix` gets the bottom's 0 | M11 | **17** |

M1's fourteen are `ret_new` plus every row that reads a FIRED rule's answer:
`shrink1_ns`, `shrink1_marg`, `reshape_pick`, `permute_merge`, `permute_noop`,
`stack_idx`, `const_idx2`, `const_idx3`, `const_idx5`, `rej_pair`, `idx_idx`,
`idx_pick`, `idx_shaped`. The report measured four of them (`const_idx2` 0 -> 40,
`const_idx3` 0 -> 3, `rej_pair` 0 -> 40, `ret_new` 1 -> 0) and read the other ten as
"0 either way". They read 0 either way **because the rows were addressing the wrong
node**: the values 40, 3 and 40 it recorded were the answers for IX3 and IX5, not
for the IX2 and IX3 the rows name. `schedule/rangeify.bend`'s M1 measured its LOCAL
`rf_self` and was right to; it now has a corrected reason to keep not calling
`M.hop_self`, and `M.hop_first`/`M.hop_next` are still correct and still reused.

`ret_new` is the row and it now reads **0**, not 1: `Hop{empty, 3}` against `self 2`
is `ret is not None and ret is not uop`, so the answer SURVIVES. The gate was
asserting "a rule that built a new node was dropped".

**THE PAIRS ARE NOT INDEPENDENT, and the new table says so.** M14 (last-wins in
`hop_first`) moves M1's thirteen rows and NOT `ret_new`: `hop_self` and the fold
are the same defect seen from two sides, both "the answer survives when it should
not", and neither mutation substitutes for the other. And M6 -- `mp_ident.at`
reading an arg ELEMENT as an arena index, which killed `mp_4` entirely -- moves
one row, `permute_noop`, which M1 also moves. A 26-row gate whose rows are
overlapping in this way is weaker than "26 green" suggests, and the table is where
that is visible.

The notes' standing rules held up and are worth repeating at the fix:
**a row that cannot fail is a restatement, and a gate that agrees with a bug is
worse than no gate.** `t_ret_new` agreed with the inversion.

## FOUR MORE DEFECTS IN `movement.bend`, FOUND WHILE FIXING R1 AND R2
### 2026-10-01. NONE OF THEM IS VISIBLE FROM `movement.py`; ALL FOUR ARE PORT ERRORS.

`movement.py` is correct in all four places. These are transliteration mistakes, and
three of the four typechecked and printed plausible output.

| where | the port did | CPython does | mutation |
| --- | --- | --- | --- |
| `mp_index.pick` | answered `new_srcs[0].val`, the VALUE | `self.src[val]`, a NODE INDEX (ops.py:223) | M3, 1 row |
| `mp_replace` | read the arg off `self` | `replace(arg=...)` REPLACES it (ops.py:252) | M4, 1 row |
| `mp_3` | composed the permutation from `x2`'s SRCS | from `x2.ARG` -- a list of INTS | M5, 1 row |
| `mp_ident.at` | read an arg ELEMENT as an ARENA INDEX | compares `x.arg[k] == k`, two INTS | M6, 1 row |

**AND THE ONE THAT IS NOT A PORT ERROR AT ALL: `marg.go` REVERSED THE MARGIN.**
`List.append(&2, A, r, [x])` puts `x` at the END of `r`, so a fold that appends on
the way UP builds its list backwards. MEASURED, reproducer
`.agents/slop/notes/probe-append.bend` (prints `1` for the head of a `[1,2,3]` built
by accumulating-append, so it appends). `marg.go` was accumulating on the way up;
`marg_zip.go` and `as_shape.vals.go` were already right. Only `shrink2_marg` moved
(M7, 1 row), because a ONE-element margin is order-blind -- and every single-margin
row in the gate stayed correct while the two-element one did not.

**FIVE OF THESE SIX ARE THE SAME SHAPE, and the shape is the lesson.** Four of them
read a PYTHON INT as a BEND ARENA INDEX, or answered a VALUE where CPython answers an
INDEX. `x.arg` is a tuple of ints; `x.src` is a tuple of UOps; `new_srcs[0].val` is
an int; `self.src[val]` is a UOp. The port has one `U32` for all of them, and Bend
cannot tell which is which, so the type checker will not catch the confusion. The
gate is the only thing that can, which is the argument for a mutation table over a
check-and-run: **M3, M4, M5 and M6 are four independent single-row mutations, and
four rows that each move exactly one is a far stronger statement than 26 green.**

### AND THE RULE THE FIXTURE GOT WRONG, WHICH IS NOT ANY OF THE ABOVE

`G.ix` was missing the arena's bottom, so `G.at(g, n)` was one node past the one every
row's comment named. Seventeen rows depend on that (M11) and it is the single biggest
mutation in the table. A fixture that renumbers its own nodes is a fixture whose rows
cannot be checked by reading them: the row says `shrink1` and the code rewrites S3.
The oracle (`.agents/slop/notes/mop-truth3.py`) prints the whole index map, and it is
the reason a diff of the two gates is now the acceptance test rather than a reading
exercise.

### WHAT A CONSUMER SHOULD DO ABOUT IT

`schedule/rangeify.bend` still implements `ret is not uop` locally as `rf_self`. That
was the right call and it is now better justified: `M.hop_self` was wrong, and M14
(last-wins in `M.hop_first`, which `rangeify` DOES call) moved thirteen rows when it
was mutated. If `rangeify` wants the local `rf_self` replaced by the now-correct
`M.hop_self`, M1 and M14 are the two measurements to re-run. `M.hop_first` and
`M.hop_next` are unchanged and still correct.

### R3. `Bool` HAS NO `U32.show`, SO EVERY GATE ROW PAYS A `Bool -> U32` STEP.

    def b2u(b: Bool) -> U32:
      match b:
        case True{} : 1
        case False{}: 0

Not a deep rule, but it is a per-row cost and it has a SHAPE: a row that
computes a `Bool` cannot print it, so the conversion has to be threaded through
81 call sites or hoisted into one def. Hoist it, and put it ABOVE the fixture
rather than inside `main` -- `Bool.match` is the only branch, and there is no
`U32.from_bool`.

### R4. `List.sort`'s COMPARATOR IS `A -> A -> Bool` WITH ONE BINDER, SO A KEY THAT
###     LIVES IN THE ARENA HAS TO TRAVEL IN A `Data` RECORD.

    def List.sort(~A: Data, ~le: A -> A -> Bool, xs: List<&2, A>) -> List<&2, A>

The comparator takes TWO elements but binds ONE, and it answers `Bool`, not a
`Cmp` (`Cmp` is for `Order`/`Min`/`Max`). So "sort these indices by the key in
arena slot `k`" is not expressible: the closure cannot close over `ar`, and it
cannot take `ar` as a second argument because there is no second argument. The
port packs the pair first.

    type Rk is Data:
      Rk{k: U32, i: U32}

and sorts `List<&2, Rk>` with `le` reading `Rk.k`. The list then has to be
unpacked. That is the same "a `list`-tail fold that must hand something back
carries it in a record" shape as the memory.py note, one level down: there the
record carries an accumulator, here it carries a sort key.

### R5. A `Data` RECORD WITH A FIELD NAMED AFTER A KEYWORD IS A SYNTAX ERROR, AND
###     `where` IS A KEYWORD.

Not worth a rule of its own except as a name-collision list while porting:
`where`, `match`, `case`, `type`, `def`, `let`, `if`, `else`, `do`, `fold`. The
port needed a `where`-shaped local and had to pick another name. Hit it once,
recorded so the next port does not spend the compile cycle on it.

## SIX MORE RULES, MEASURED 2026-10-01 WHILE PORTING `mixin/gradient.py`

### 1. A `Data` RECORD PATTERN IS CAPPED AT 28 FIELDS, AND THE ERROR IS A BARELY
###     PARSEABLE "a `Fix` pattern with 28 fields"

`spec.bend`'s largest record is `Shrunk`; a fixture record of 29 `U32` fields is
refused with `- message : a Fix pattern with 28 fields` and NO position hint. The
workaround is to REUSE an unused field rather than add one: a gate fixture rarely
needs every slot it declares, so renaming an unused slot to the new meaning costs
nothing and keeps the record inside the cap.

### 2. A `match` ON A `Nat` COUNTDOWN AND A LIST IN ONE ARM NEEDS THE COUNTDOWN
###     FIRST, AND `p` MAY NOT BE BOUND IN TWO ARMS EVEN FOR THE EMPTY-LIST ONE

A depth-first node count over a DAG wants `match fuel todo: case 1n+p s <> t: ...`
plus a cover. The cover cannot be `case 0n _:` AND `case 1n+p Nil{}:` together,
because `p` is consumed by the arm that uses it and binding it in a second arm is
`expected : p / observed : p (consumed more than once)`. So the EMPTY-LIST case is
reached by the cover arm `case _ _:` and the countdown binds `p` exactly once:

    def size(+fuel: Nat, +ar: O.Arena, todo: List<&2, U32>, acc: U32) -> U32:
      match fuel todo:
        case 1n+p s <> t: U32.add(U32.add(1, size(p, ar, O.Arena.srcs(ar, s), 0)),
                                  size(fuel, ar, t, 0))
        case _ _: acc

This is also the ONE legal spelling of "two self-calls in one arm": the two calls
get DIFFERENT fuel (`p` into the head, `fuel` unchanged into the tail), so rule 5's
"the same fuel may not feed two self-calls" is satisfied without a helper def.

### 3. A NODE-COUNT FOLD MUST ADD ITS `+1` TO THE ACCUMULATOR, NOT TO THE HEAD

The shape above looks right and returns a count that is one LOW for a leaf, because
`case _ _: acc` also catches the `Nil{}` case and returns without counting. The
fix is `U32.add(U32.add(acc, U32.add(1, ...)), ...)` rather than
`U32.add(U32.add(1, ...), ...)`. What caught it was a CONTROL row: `size_const`
must be 2 (`CAST(CONST)`) and it printed 1. The lesson is the general one -- a
recursive counter needs a fixture whose answer is known independently, or the
off-by-one is indistinguishable from a wrong rule.

### 4. A `Data` RECORD FIELD READ TWICE THROUGH A FIELD ACCESSOR NEEDS `+`, AND
###     `+` ON THE RECORD IS NOT ENOUGH -- THE CALL IS

`F.fold.dt(F.Folded.ar(fx), F.Folded.t(fx), i)` reads `fx` twice. `+fx` on the
parameter is required and NOT sufficient: the first accessor CONSUMES the value
before the second is evaluated (Bend is strict -- "an argument is evaluated before
the callee branches"). `uop/spec.bend` avoids this with `sp_ar`/`sp_tb`, two
one-read helpers. When the helpers are in another file and importing that file is
undesirable, pass the two fields as SEPARATE PARAMETERS:

    def gr_0.dt(ar: O.Arena, tb: F.Table, self: U32) -> Maybe<&2, S.Dt>:
      dt_of(F.fold.dt(ar, tb, self))

### 5. A RULE THAT GROWS THE ARENA RETURNS `(Arena, answer)` AND THE ANSWER MUST
###     BE A `Data` RECORD, NOT A `Maybe`

`pm_gradient`'s rules return `tuple[UOp|None, ...]`, `None` meaning "keep
scanning". A `Maybe` of a list cannot be a `Data` field, so the answer is two
constructors -- `GFired{gs, ar}` and `GSkip{}` -- which also lets `gs` carry the
GROWN arena. A hole in `gs` is index 0, which is not an invention: `Arena.empty`
spends index 0 on `Arena.bottom` and `UOp.is_none(u) = U32.is_zero(u)`.

### 6. THE GATE NEEDS A ROW THAT READS AN INDEX OR AN OP, NOT A LENGTH -- MEASURED
###     TWICE IN ONE FILE

Two mutations in `mixin/gradient.bend` produced the CORRECT ANSWER LENGTH while
being wrong, and both were invisible until a row read something else:

* `gs_keep` under LAST-WINS: every scan-level answer is identical because only one
  rule ever fires in the fixture. Only a row calling `gs_keep` on two `GFired`
  values moved.
* `x.eq(y)` spelled as `CMPEQ` instead of `CMPNE`-then-`CMPNE`: `max_n0` is 21
  either way, because the two spellings have the same node COUNT. Only a row
  reading `Arena.op` of the node `eq` built moved.

The generalisation of the existing "two rules agree and the gate cannot see it"
note: it is not only rules that collide, it is any check whose oracle is a COUNT
rather than a STRUCTURE. `pow_n0` is 23 in the port and 24 in Python for a third
reason and the same rule applies -- see the file's header, where the disagreement
is recorded rather than fitted away.

## FOUR MORE RULES, MEASURED 2026-10-01 PORTING `tinygrad/tensor.py`

### 1. `case 1n+p:` IS A PREFIX MATCH TOO, AND IT IS WORSE THAN `case 0n:`
The note above says a numeric `case 0n:` is a first-match prefix and so is not
exhaustive. `1n+p` is the SAME trap and more dangerous, because the arm reads like a
test for "one or more" and silently claims every larger count, leaving the arm after it
DEAD CODE. `shape_to_shape_arg`'s three arms were written
`case 0n: ... case 1n+p: <the one-element case> case _: <the many case>` and the
one-element case fired for 2, 3, 4, ... — so a shape arg of `[2, 2]` (two CONSTs, one
interned index) built a bare CONST where the oracle says a two-src STACK. There is no
diagnostic; the `case _:` is simply unreachable. The fix is the idiom every other
dispatch uses: compute a `Bool` with `Nat.is_eq(n, 1n)` and pass it in.

### 2. A `.go`/`.step` PAIR IS MUTUAL RECURSION, SO THE SELF-CALL MUST BE AN ARGUMENT
There is no `|>` and a def body is one expression, so a walk that needs both a two-way
choice and a descent cannot be written as `match cond: case A: ... case B: self(tail)`.
The working shape is `Bool.pick(TYPE, cond, <the A value>, <the self-call>)`: both
branches are evaluated (Bend is strict), so the self-call runs whether or not the branch
is taken, and the accumulator is still correct because the discarded branch's value is
thrown away. The LIST must be the first parameter so the tail is the self-call's first
argument. Two instances in `tensor.bend`: `tn_rop.ins` and `tn_rop.ne1`.

### 3. A `match` ON A LIST SPENDS IT, AND `[head] ++ tail-of-tail` LOSES AN ELEMENT
`case s <> t:` destructures the scrutinee, so the arm cannot re-wrap the list. A SECOND
destructuring `case u <> v:` and then `[s] ++ v` drops `u` SILENTLY. It is invisible on a
one-element list and it is visible on a list of two equal interned indices, which is
exactly what a shape arg like `[2, 2]` is. The fix is to compute the LENGTH before the
match and hand the whole list to the constructor, which is also what makes the duplicate
case correct: `UOp(Ops.STACK, src=(c, c))` is a two-src node and hash-consing keys on the
src tuple, so it is a different node from `STACK(c)`.

### 4. AN ARENA IS THE ONE A BUILD RETURNED, NOT THE ONE THAT WENT IN
Every arena-taking def that BUILDS must return the `Found` the build gave it. Passing the
incoming `Arena` forward typechecks, compiles, and yields an index that points into the
arena as it was BEFORE the node was interned. The symptoms are all plausible numbers and
none of them raises: a node that reads as the `ABad` bottom (`NOOP/0`), an EMPTY
toposort, a node whose src count is wrong, and a `replace`-style shape comparison that
answers "not equal" for two equal shapes. Three separate graph-building defs and three
gate fixtures had it, and the gate caught them only because every row is derived from
CPython. The tell is a row that is `0`, or a COUNT that is smaller than it should be,
with no error anywhere.

## F. TWO AGENTS PORTED `schedule/multi.py` CONCURRENTLY. The oracles AGREE;
##    the file is contested and only one agent may write it.

Measured 2026-10-01 while porting `schedule/multi.py`. The brief says "Create
ONLY the one .bend file named in your unit", and `multi.bend` was named in mine
AND was being written by someone else at the same time: a 232-line file I wrote
was overwritten within 60 seconds, and the replacement grew 288 -> 398 -> 461
lines while I watched it across four 30-second samples. The two files use
incompatible prefixes for the same concepts (`Cfg`/`Sh`/`Nd` vs `Cfg`/`MPat`,
`mu_*` vs `mt_*`), so merging them is not mechanical -- every one of ~60 call
sites would have to be renamed, and the `MPat`/`Nd` split is a real design
difference (pattern columns vs. per-source node state), not a spelling one.

THE ORACLE CROSS-CHECK IS WHAT IS WORTH KEEPING. Both agents independently wrote
a CPython oracle for the same file:

    .agents/slop/notes/sched-multi-truth.py   (mine, 380 lines, 471 rows)
    .agents/slop/multi-rows.py                (theirs, 213 rows)

and all 25 `early_reject` sets, all 25 op sets, `own_n`/`ra_n`/`ea_n`, the
28-op ALU set and the 6-op Movement set AGREE, computed from
`M.multi_pm.patterns`, `M.replace_allreduce.patterns` and
`M._early_allreduce.patterns` respectively. The ONE apparent disagreement,
`pm_len=25` vs `own_n=19`, is a NAMING difference and not a value difference:
`own_n` counts `multi_py:282-310`'s own list and `all_n` counts
`multi_py:311`'s `PatternMatcher([...19...]) + replace_allreduce`, which is 25.
Both numbers are right and both are rows.

THE GENERAL RULE, and it is the one that cost the work: TWO INDEPENDENT
TRANSCRIPTIONS OF THE SAME PYTHON TABLE THAT AGREE IS STRONG EVIDENCE BOTH ARE
RIGHT, AND IS CHEAPER THAN EITHER MUTATION TABLE. A transcription error -- a
misread `early_reject`, a wrong `required_len`, a GroupOp set with one member
missing -- shows up as a DISAGREEMENT. Neither agent's own gate can find it,
because a gate compares against the code in its own file. Cross-checking two
oracles that were written from the same Python finds the class of bug a
self-consistent gate is blind to by construction.

A cheaper and more general form: when a port's subject is DATA rather than
control flow -- a rule table, an op table, a dispatch order -- write the oracle
FIRST and print a hash or a sorted dump of the whole structure, so two runs can
be diffed as files instead of compared row by row. `diff <(a.py) <(b.py)` on the
dumps answers in one command what 25 row-by-row comparisons answer in a script.

## SIX MORE RULES, MEASURED 2026-10-01 PORTING `nn/optim.py`

Every one of these cost a compile cycle or a wrong gate row, and every one is a
consequence of an earlier rule rather than a new law. The file is
`tinybendygrad/nn/optim.bend` and its header records each at the def.

1. **A `Data` record parameter needs `+` for two reads even when the reads are in ONE
   argument position.** `fold.bend`'s `ones.go(+n: Nat, acc)` is the precedent; the
   nn form is a `Tensor` read for its arena and again for its index
   (`op_ar(t), T.Tensor.u(t)`). `+` on a `List` parameter also works, which the `List` is
   a Type-kinded thing should not predict:
   `def op_filter.go(want: Bool, +xs: List<&2, T.Tensor>)` checks.
2. **`Bool.pick` is STRICT, so a two-arm walk over a `List` needs the list `+`.**
   `Bool.pick(List<&2, U32>, want, op_filter.tgo(xs, Nil{}), op_filter.fgo(xs, Nil{}))`
   with a plain `xs` is "consumed more than once". Measured, and it is the difference
   between a two-arm filter and an uncompilable one.
3. **A `match` on TWO scrutinees is `case P Q:`, and a `Data` variant whose pattern has
   ONE field must NAME it**: `case False{} S.Dn{tags}:` — `S.Dn{}` is rejected with
   "a ../LAWS/spec.Dn pattern with 1 field".
4. **A nested `match` whose scrutinees are PATTERN BINDERS is refused** ("a match on a
   parameter or field (this name is a def or a consumed binder)"). `op_nop` matches
   `Optim{...}` and then needs to branch on `fused` and `device`, both binders. The
   shape that works is a `.arm` def taking them as PARAMETERS, which is the same
   Bool-parameter rule as everywhere else and costs one extra def.
5. **`Nat` binders in `case 1n+p:` cannot be read twice, and the fix is `+n: Nat` on
   the SCRUTINEE, not on the binder.** `def axes.go(+n: Nat, acc)` with
   `case 1n+p: axes.go(p, ...)` checks; without the `+` the error is "expected: p /
   observed: p (consumed more than once)" even though `p` appears once in the source.
6. **THE ARENA RULE, AND IT IS THE ONE THAT MATTERS.** `O.Arena.empty()` inside a
   helper that builds a node produces a node the rest of the graph cannot see, and it
   typechecks and prints a plausible number. Measured five distinct failures in one
   file: a bare-`U32` helper (every graph row printed `1 NOOP/0`), a stale `ar` on
   `op_sub` (`op_apply` printed `0`), a fresh arena in a `Bool.pick` re-wrap
   (`op_nesterov` printed `1 BUFFER/0`), the unary helpers `sqrt`/`reciprocal`/`cmplt`/
   `neg`, and `op_mulf` interning its CONST into a NEWER arena than the MUL that
   consumes it. **The rule is: a node belongs in the arena as it stood after the last
   node built before it, so every helper takes the arena where it is not already
   carried and takes a `Tensor` where it is.** `Tensor` is exactly the `Arena & U32`
   pair, which is what `O.Found` is for and why `tn_alu.of` returns a `Tensor` rather
   than a `U32`.
7. **A gate row that builds a graph twice per row silently gates the wrong graph.**
   `sig(nm, st_ar(s), op_trust(st_ar(s), ...))` calls `g_step()` twice, so the fixtures
   are in one arena and the graph in another, and every row printed `1 NOOP/0`. The
   `n=` COUNT is what makes it visible: a one-node signature is never a right answer
   here. Read the arena off the built `Tensor`, not off the fixture.

## 2026-10-01, mixin/elementwise.bend -- rule 6 has a SECOND HALF, and it is the
## one that bites

Rule 6 above ("a node belongs in the arena as it stood after the last node built
before it") is about a node being built in the WRONG arena. There is a second
failure that rule 6's fix does not cover, and it is worse because `next` looks right.

**THE FAILURE: two builds from the same base produce SIBLING arenas, and "take the
longer" does not find a store containing both.** Rule 6's remedy for a two-operand
build is to pick the longer of `x`'s and `y`'s arenas before building. That is sound
ONLY when one is an append-only extension of the other. It is NOT when both operands
have already minted into their own copies: then both arenas are `base ++ [one node]`,
the same length, and index `k` holds a DIFFERENT node in each. Taking the longer picks
one, and the other operand's freshly minted node is simply absent -- it reads back as
whatever the winner put at index `k`.

The symptom is silent and is why this took a while: the arity is right, the count is
plausible, and the graph is wrong. `sub`'s int arm printed `4 CONST/0 BUFFER/0 MUL/2
ADD/2` where CPython prints `6 BUFFER/0 CAST/1 BUFFER/0 CONST/0 MUL/2 ADD/2` -- a
missing BUFFER and a missing CAST, with both operands still 2-src.

**THE FIX, and it is a discipline rather than a helper.** Three rules together:

1. **A def that may mint takes the arena as an ARGUMENT and builds there.** Not
   `Tensor.ar(t)` -- an argument. `Tensor.ar(t)` is only correct while nothing has
   been minted since `t` was made, which is exactly the condition that has stopped
   holding by the time a second operand is used.
2. **A def that mints NOTHING still rebase onto the arena it was handed** on every
   arm, including the two no-op arms. An arm that returns `t` unchanged hands back a
   tensor carrying the arena as it was BEFORE its sibling minted, and the next build
   in that stale store takes an index a real node already holds. This is the rule that
   fixed `ew_add_f`, and it costs one `T.tn_new` per arm.
3. **The promotions are SEQUENTIAL and the second takes the arena the first grew.**
   Not a fold threaded down, and not two parallel mints.

**COROLLARY: a helper that builds over two operands which are NOT the pair being
combined needs the rebase written out.** `div`'s float arm is
`cast_if_int(a) * reciprocal(b)`: `cast` grows the arena, and `b` must be rebased
onto the grown store before `reciprocal` builds in it, or the `MUL` names the `cast`.
`ew_alu2`'s `ew_join` only covers the pair it is combining.

**COROLLARY 2: `arena.next` is NOT a containment test.** Two sibling arenas of equal
length are indistinguishable by it, so any "pick the bigger store" rule is reading a
number that does not mean what it looks like. The store is only ever an extension
because the code made it one.

**AND THE FOLD VERSION OF THE SAME TRAP.** Rule: never accept a `+fx: F.Folded` as a
parameter to a def that builds. A `F.Folded` is a fold of ONE arena and goes stale
the moment the callee mints, and the failure is the *silent* one -- `wk_dt` of an
index past the end answers `void`, `void` is not in `dtypes.weaks`, so every operand
takes the CAST arm and you get right ops with right arities and wrong dtypes. Thread
the arena (or take the fold from the tensor AT THE POINT OF USE, `ew_fx`) and the
staleness becomes unrepresentable. Measured here on `ew_ge`/`ew_eq`, which took a fold
from the caller, then built a CMPLT, then cast the result against the PRE-BUILD fold.

## EIGHT MORE RULES, MEASURED 2026-10-01 PORTING `codegen/transcendental.py`

Every one of these cost a full gate round-trip. The gate is
`.agents/slop/tx-arena.txt` — 891 STRING rows, and the interpreted lane, the
native lane, and the Python oracle have to be byte-identical, so "it type-checks"
is worth nothing here on its own.

### 1. A def that returns a BARE INDEX DISCARDS ITS ARENA

The rule at line 558 ("the rule returns the ARENA, not a pair") has a mirror
image, and this port is the case where BOTH are read. `ops.bend`'s `Arena` is
`Data` holding a `List<&2, Node>`, and a build appends to it, so the arena *is*
the side effect and the index is not. A def that builds nodes and returns only
`U32` therefore hands the caller nothing: Bend eliminates the call, and every
node it built goes with it.

    def ph_i(+ar: O.Arena, +e: U32) -> O.Found:     # right: the pair comes back
      +a = tx_cast(ar, e, S.uint64())
      +b = tx_ci(O.Found.ar(a), 32)
      tx_alu2(O.Found.ar(b), O.OpsFLOORDIV{}, O.Found.i(a), O.Found.i(b))

    def ph_i(+ar: O.Arena, +e: U32) -> U32:         # wrong: the CAST is dropped
      +a = tx_cast(ar, e, S.uint64())               # ... unless the caller reads .ar
      ...

**The tell is a count row that is silently short.** The first version of
`payne_hanek_reduction` passed the post-`frexp` arena to all four of
`ph_ia`/`ph_i`/`ph_ec`/`ph_off`; `ph_i`'s CAST was eliminated because only its
index was read, and `n_ph` came out **60 against 116** with three rows reading
slots that did not exist. There is no error, no proof failure, and `--check-only`
still says `ALL PROOFS CHECK`.

**Corollary, the one that makes it expensive: two bindings that both read
`ar(n)` for the same `n` produce SIBLING arenas.** `+a = f(n)` and `+b = g(n)`
are each `base ++ [one node]`, the same length, index `k` holding a different node
in each — which is the tensor case already written up at the top of this file, one
level down. And `f(ar, ..) .. f(ar, ..)` written twice lets the compiler pick
either order, so the two nodes' indices are not even determined by the source.

So the discipline is one sentence: **every step threads
`O.Found.ar(<previous binding>)`, and a def that may mint returns the pair.**

### 2. AN ELISION MUST HAND BACK THE ARENA IT WAS GIVEN

`mixin/dtype.py`'s `cast` is a no-op when the dtype already matches, and a port
that models the no-op as "return the index" throws the arena away — the caller's
next node then lands in a store that does not contain this one. The elision has
to be the *same pair, with no node added*:

    def tx_cast_same.go(+ar: O.Arena, +x: U32, +dt: S.Dt, same: Bool) -> O.Found:
      match same:
        case True{}: O.Found{ar, x}
        case False{}: tx_cast(ar, x, dt)

This is the tensor rule at the end of this file ("a def that mints nothing still
rebases onto the arena it was handed, on every arm, including the no-op arms")
specialised to a `(store, index)` pair.

### 3. A DTYPE PROJECTION IS NOT IDEMPOTENT

`rintk`'s output dtype is the int of the same name
(`{float64: int64, float32: int32, float16: int16}[d.dtype]`). Once that is a
def, `tx_int_dt(tx_int_dt(x))` is **not** `tx_int_dt(x)`: `tx_int_dt` matches on
`pri` 12 / 14 / else, and `int32` is `pri` 5, so the second application answers
`int64`.

The port had `tx_rintk` apply it internally (mirroring line 24, which reads
`d.dtype`) *and* a caller pass an already-converted dtype. **Every count row was
correct and three rows were wrong**: `a_cw 23`, `a_xsinf 39`, `a_xsin 143` printed
`CAST,long,22` where the oracle says `CAST,int,22`. Nothing else moved — same
nodes, same arity, same count, a different dtype on three CASTs.

**Rule: a derived-dtype helper goes at exactly ONE place, and the def that mirrors
the Python helper that reads `.dtype` is that place.** Every other caller passes
the dtype of the *operand* the Python code would have had in hand.

### 4. `F32.to_u32` IS A TRUNCATION IN THE NATIVE LANE AND UNFOLDED IN THE INTERPRETER

`F32.to_u32` is a law, and the two lanes do not agree about it:

    def main() -> U32: U32.add(F32.to_u32(2.9), U32.mul(F32.to_u32(F32.neg(0.0)), 1000))

    ./bin/bend  ->  U32.add(F32.to_u32(2.9), U32.mul(F32.to_u32(F32.neg(0.0)), 1000))
    native      ->  2

The interpreter has no body and prints the residual term; the backend
constant-folds it to a truncation. So it is not a lane-divergence bug you can
diff your way to, and it is not a bit pattern either. **The bit pattern is the
datatype field, and it is a constructor so `--check-only` covers it:**

    def tx_fbits(f: F32) -> U32:
      match f:
        case F32{data}: U32{data}

Verified against `struct.pack('<f', .)` on the gate's own rows:
`0.3183098861837907` -> `1050868099`, `0.3183098861837907 / 2.0**24` ->
`849541507`, `2.0**24` -> `1266679808`, `-0.5` -> `3204448256`, and the rest all
agree in both lanes. `F32.bits` (line 131 of these notes) also agrees; it is a law
too, so prefer the destructor on general grounds, and **`to_u32` is the one to
never reach for** — the name reads like a bitcast and the value is a truncation.

### 5. A SELF-CALL NEEDS `Nat` FUEL FIRST, AND THE FUEL IS NOT THE COUNTER

Python's `_take` recurses on a COMPILE-TIME bound (`count+offset <
len(two_over_pi_f) - 1`), so Bend needs a fuel parameter, and the fuel and the
Python `count` are **different numbers**: for `offset = k` there are `6 - k` levels
and `count` runs `0..5-k`.

    def ph_take(+k: Nat, +c: U32, +ar: O.Arena, +i: U32, +an: O.Found,
                 +off: U32) -> O.Found:
      match k:
        case 0n: O.Found{ar, O.Found.i(an)}
        case 1n+p:
          +cc = tx_ci(ar, c)
          +ne = tx_alu2(O.Found.ar(cc), O.OpsCMPNE{}, i, O.Found.i(cc))
          +in = ph_take(p, U32.add(c, 1), O.Found.ar(ne), i, an, off)
          +t = tx_ci64(O.Found.ar(in), H.i64_of_hi_lo(0, two_over_pi(U32.add(c, off))))
          tx_alu3(O.Found.ar(t), O.OpsWHERE{}, O.Found.i(ne), O.Found.i(in), O.Found.i(t))

`Nat` first, so the recursive binder is `p`. Reading one Nat as both makes the
CMPNE compare against 6 instead of 0, misses `i.ne(0)` entirely, and shifts every
node by one. **And the base case returns the PAIR** (rule 1) — `O.Found{ar, O.Found.i(an)}`,
not the index.

**The receiver-first order inside the arm is load-bearing too.** Python evaluates
`i.ne(count).where(_take(...), an.const_like(...))` receiver-first, so the six
CMPNEs come OUTERMOST FIRST (`a_ph36`..`a_ph43`) and the six WHEREs INNERMOST
FIRST (`a_ph45`..`a_ph54`). The `+` binder is also what keeps the recursive call
alive at all; without it the self-call is unused and eliminated.

### 6. TWO dtype GUARDS ON THE SAME VALUE ARE NOT NEGATIONS OF EACH OTHER

`cody_waite_reduction` has `d.dtype == dtypes.float64` (line 123/146) and
`x.dtype == dtypes.float16` (line 133) — two independent facts about one dtype, so
two Bool parameters. Collapsing them ("not float64" -> "float32") sends float16
down the float32 chain, and since a float16 that builds the float32 chain is a
*wrong tree* rather than a missing one, nothing in the gate would have said so.
Same shape as `decomp.bend`'s `cls`/`cplx` split. Also note `Bool.not(f16)` is
only sound because the *third* dtype case (`bfloat16`) cannot reach
`cody_waite_reduction` — `TRANSCENDENTAL_DTYPES` is `half, float, double`.

### 7. A `match` MAY NOT SCRUTINISE A CALL, SO A dtype TEST IS A PARAMETER

Already recorded (lines 562, 793, 905). One more data point: `cw_quadrant` needs
`d.dtype == float64` for BOTH the `rintk(d * m_1_pi - qdh)` arm and the float32
arm, and the caller already has the `S.Dt`; so the flag is `d64: Bool` with **no
`+`** and the caller passes `tx_d64(dt)`. The `+` would be a lie — the call
carries no arena.

The `+` is also how you spot the sibling mistake: a def parameter that is
`O.Arena`-returning is `+`; a plain predicate is not.

### 8. WRITE FLOAT COEFFICIENTS AS FULL DECIMALS, AND NEGATIVES AS `F32.neg`

Bend's float parser is not reliable at every exponent: `6.1e-5` and `1e-4` do not
parse at all, while `0.000061` does. A coefficient table is a place where one
dropped digit is silent — `String.concat` shows you the number it got, not the
number you meant — so **full decimals everywhere**, and `F32.neg(0.5)` rather
than a leading `-`. A dropped digit in a truncated float also cannot be caught by
a count row, which is the argument for string-diffing the CONST rows.

## THE SHAPE OF A GATE THAT ACTUALLY BITES

Worth stating once, because four separate bugs got past the type checker here and
this is the reason they did not get past the gate:

- **STRING-DIFF THE CONSTS AND THE DTYPES, NOT JUST THE COUNTS.** Every count row
  stayed correct through a wrong CAST dtype (rule 3), a dropped arena (rule 1) and
  an off-by-one fuel (rule 5). A `n_<tag>` row is necessary and nowhere near
  sufficient.
- **RUN BOTH LANES.** A count row can be right in the interpreter and wrong in the
  binary, which is the whole content of rule 4.
- **MUTATE THE FILE AND MEASURE WHICH ROWS MOVE.** Thirteen mutations, all of which
  still pass `--check-only`; four of them move exactly ONE row
  (`a_xexp2#32`, `a_xpow#31`, `a_ph#99`, `sw7`). A gate with no single-row claims
  cannot see a single-row mistake, and the `sw30`/`sw7` pair exists only because
  `xsin`'s `switch_over` is a parameter — the shape does not depend on the value,
  so both rows are read at the same slot and only the value row can tell.

## `Maybe<&2, S.Dt>` in a def signature is position-sensitive (measured on 2.0.34)

Found by `codegen/kernel.bend`, and it cost four bisection cycles because the
reported location is the WRONG line -- bend blames the signature while the file
that differs is a blank line earlier or later.

Repro, all three files under `tinybendygrad/codegen/`, same imports:

    A: head -179 kernel.bend  + "\n\ndef kn_dt(tb: F.Table, ar: O.Arena, i: U32) -> Maybe<&2, S.Dt>: ..."
       -> ALL PROOFS CHECK
    B: head -179 kernel.bend  + "\ndef kn_dt(...): ..."     (one blank)   -> ALL PROOFS CHECK
    C: head -182 kernel.bend                                  (same bytes) -> SOME PROOFS FAIL
                                            - expected : a term
                                            - observed : ']'

B and C are byte-identical in the region bend points at -- verified with a byte
diff -- and neither the def name nor the blank-line count changes the outcome, so
**do not spend time bisecting blank lines against this one.** The workaround is
the only thing worth keeping: put the `Maybe` through a def whose return type is
already known to parse (`Bool`), or go through `fold.bend`'s `F.dt_is` /
`F.Folded` instead of carrying an `S.Dt` value.

`Maybe<&2, List<&2, O.Sint>>` in a signature is fine, and the same file with the
def named `bb` instead of `kn_dt` is fine, so the trigger is the annotation in
that POSITION, not the name and not the blank lines.

## FIVE MORE RULES, MEASURED 2026-10-02 WRITING `renderer/__init__.bend` and
## `renderer/cstyle.bend`

### 1. A `do IO<Unit>:` BODY MUST END WITH A BARE TERM, NOT A `<-` BINDING
    def main() -> IO(Unit):
      do IO<Unit>:
        _ : Unit <- p2(7)
        _ : Unit <- p3(8)          # "expected : a term, observed : end of input"
and a def whose body is a `do` block must be the LAST def in the file -- a `def`
after it is "expected : a term, the keyword 'def' cannot head one". Both cost two
compile cycles to find. Every other file in the tree already puts `main` last.

### 2. A SELF-CALL MUST BE LEXICALLY INSIDE THE DEF THAT OWNS THE FUEL MATCH
A `def` may only call defs declared ABOVE it, so a NON-recursive rebuild helper
must sit above the recursion -- that is fine, because it holds no self-call. But
`hoist.py` cannot fix a helper that DOES hold one: with
`ws -> ws.pick.of -> ws_deep -> ws` the cycle is unresolvable by reordering, and
the tool reports "no progress on ws at line 51" after eight rounds. The fix is to
move the guard Bool into a PARAMETER of the recursive def, so the inner `match`
scrutinises a parameter (legal) and the self-call is one expression in one arm.

### 3. A RECURSIVE ARENA REBUILD MUST BE BUILT ON THE INNER NODE'S ARENA
`O.Found.ar(inner)`, not the arena passed in. An arena only GROWS, so the passed
arena is a PREFIX and the inner node's index is not in it: the outer node's src0
then points past the end and `Arena.arg` answers the bottom's `ABad`. This is
INVISIBLE -- it typechecks, it runs, and it prints a plausible wrong string.
MEASURED: `INDEX float src0=?` where CPython prints `float`. The outer
op/arg/tag are still read from the OLD arena, which is correct.

### 4. `Maybe.map(&2, T, ...)` NEEDS A `Data` RESULT, AND `.bind` READS DIFFERENTLY
`Maybe.map(&1, S.Dt, m, d => d)` is "expected : Type, observed : Maybe<&2, S.Dt>"
-- the third argument is a QUANTIFIER over the RESULT and `S.Dt` is not the
`Data` being mapped. The tree's own convention is better and shorter anyway: skip
`Maybe` combinators entirely and `match` the fold read in a `.of` def.

### 5. `O.ParamArg`'s FIELD ORDER IS NOT THE PROSE ORDER
ops.bend:697-711 declares `... volatile, image, buffer, bind_on_realize, val`,
while the header lists `val` before `addrspace`. A record literal built from the
prose order compiles until it hits `bind_on_realize` -- "expected : Maybe<&2, U32>
observed : Bool" -- because the eighth field is `addrspace: S.Addr` and the ninth
is `device: Maybe<&2, S.Dev>`. Read the declaration, not the comment. This is
rule 3 of `bend2-constraints` (a record pattern must name every field) biting
from the other side: a record LITERAL must too, and the compiler's error names
the position, not the mistake.

### 6. A `Data` UNION'S CONSTRUCTORS ARE CONSTRUCTORS, NOT NAMES -- AND `O.OpsCMPLT{}` IS ONE
A pattern binder `case MnBn{c}:` binds `c` AFFINE, and a `case MnConv{cin, cout, k}:` arm
whose body reads `k` twice needs `case MnConv{cin, cout, +k}:`, which the compiler
refuses. The fix is not `+` on the binder: a `Data` record parameter still needs a `+`
for two reads, and a pattern binder CANNOT carry one. The fix is a `.go` DEF whose
parameters can -- `mn_conv_w.go(+cin, +cout, +k)` called from the arm -- which is the same
answer `mo_reshape.pick` and `tn_rop.ne1` already give. MEASURED: four arms in
`examples/beautiful_mnist.bend` (the conv weight shape, the BatchNorm row, the padding
row, `mn_shape_str`) each cost one compile cycle before becoming a `.go` def.

### 7. A RECURSION WITH A BOUND AND NO COUNTDOWN STOPS ON THE EMPTY TAIL
`x.sequential(ll[:-1])` -- "every layer but the last" -- does not want a `Nat` countdown
when the tail IS the test: `case l <> Nil{}: acc` and `case l <> +t: recurse(t, ...)`.
MEASURED: the countdown spelling (`mn_head13.go(Nat.pred(n), ...)`) does not compile at
all, because `n` is then read in the arm's head AND unused in its tail and the compiler
reports "consumed more than once". The tail test is shorter, has no unused parameter, and
is the same condition Python writes.

### 8. `dtype.bend`'s FOURTEEN SEAMS MAKE EVERY IMPORTER RED, AND `@unsafe` IS NOT THE FIX
MEASURED (2026-10-02): `bend tinybendygrad/dtype.bend --check-only` prints
```
SOME PROOFS FAIL
Error: 14 defs rely on unsafe or foreign code:
- Dt.bf16  Dt.fp16  Dt.fp8_from  Dt.fp8_to
- Dt.i64_trunc  Dt.i64_floor_div  Dt.i64_floor_mod  Dt.i64_cdiv  Dt.i64_cmod  Dt.i64_ceildiv
- float_to_bf16  float_to_fp16  float_to_fp8  fp8_to_float
```
The cause is not a defect in the seams. `bend base --types` for the pinned 2.0.34
has NO `F16`, `I64`, `F64` or `U64` -- only `U32`/`F32` (`Word(32n)`), `Nat`,
`Bool` -- so a pure-Bend fp16 round-trip or a floored 64-bit div/mod is not
writable, and the C seam is the correct engineering, not a shortcut.

Two dead ends, both measured, so nobody walks them again:
1. `@unsafe` does NOT silence it. The guide is explicit: "@unsafe ... falls
   outside Bend's proof-guarantees: `bend` runs it, but a check prints SOME
   PROOFS FAIL and names every def that relies on it". `@unsafe def` also is not
   the spelling (`unsafe def` is a parse error: "expected : 'def', 'type' or
   'law'"); the sugar is `def f?`.
2. The checker reports the IMPORT CLOSURE, not the file's own defs. A file that
   never mentions a seam still goes red, and a file that mentions it thrice gets
   named once per def, not once per use. `wgsl.bend` prints ALL PROOFS CHECK
   precisely because it does not import `dtype`.

CONSEQUENCE FOR EVERY UNIT: importing `dtype.bend` means your `--check-only` is
permanently red and that redness is NOT evidence about your work. Gate on the
two lanes printing identically (string rows), which is the project's rule
anyway; do not spend a cycle trying to make the checker green. Splitting the
seams into their own module WOULD make most files green again and was rejected:
one file per Python file is the prime directive.

## MEASURED 2026-10-02, renderer/wgsl.bend: list ORDER is a per-call-site choice and
## `String.join` is HEAD-FIRST (and the brief's rule 6 is INVERTED)

The brief's "MEASURED Bend 2.0.34 rules" item 6 says:

    6. Re-wrapping a list TAIL in any constructor is rejected. A head is fine
       (`[x] ++ rest` via `List.append` is a prepend). `List.append(a, A, xs, ys)`
       is `xs ++ ys`.

The first half is right. The parenthetical is BACKWARDS, and it cost three hours
and one shipped bug. Four facts, measured on a probe (`.agents/slop/wgsl_lprobe.bend`
shape), and only together do they fix the direction:

    `case h <> t` on a list LITERAL is head-first: ["a","b","c"] walks a,b,c.
    `x <> rest` is a PREPEND, so `h <> f(t)` rebuilds the list head-first.
    `List.append(acc, [x])` is an APPEND, so it rebuilds the list TAIL-first.
    `String.join` is HEAD-FIRST.

So the constructor is chosen by WHERE THE LIST GOES NEXT, and there is no default:

  - a fold whose result reaches `String.join`  ->  `List.append(acc, [x])`
  - a fold whose result is WALKED by `case h <> t`  ->  `x <> rest`

Getting it backwards typechecks, runs, and silently reverses whatever it built.
`renderer/wgsl.bend` M4/M5/M6 are the three mutations that do exactly this, and
each moves three rows -- `rk_bindings` and `rk_body` are the localised rows and
`rk alu` / `rk mixed` are the whole-shaders. The practical tell: a list built by
`List.append(acc, [x])` inside a `case h <> t:` walk comes out BACKWARDS, and the
error is a reversed shader, not a type error.

Corollary for a fold that feeds BOTH a walk and a join (a sort, a partition): the
walk is the one that is order-sensitive and the join is not, so build for the walk.

## The corollary about GATES, which cost a real bug: a predicate with no row is a
## predicate no mutation can find.

`is_packed` is three clauses and decides whether a buffer renders as
`array<atomic<u32>>` or `array<u32>`. This port shipped it with its third clause
INVERTED (ANDing `addr_is_reg` where tinygrad negates it), which made the whole
packed path -- `atomic<u32>`, `atomicLoad`, the `atomicAnd`/`atomicAdd` read-
modify-write -- dead code, because no buffer a shader reads is a REGISTER.

It typechecked. It passed 100+ rows. The ONLY row that moved was one line of a
700-character module row, and only after the `is_packed`/`buf_map`/`packed_size`
rows were added -- 40 rows, and the mutation table went from "M1 moves 1 row" to
"M1 moves 36". Two rules, both from this:

  - EVERY predicate needs its own row, called DIRECTLY, over the domain that
    discriminates it. A predicate reachable only through a big composed string
    has one bit of coverage per big string, and a module row's diff does not
    localise.
  - A mutation table is how you find out which rows you do not have. `moved == 0`
    on a mutation of live code is a MISSING ROW, not a passing test. The four
    zero-move mutations in `wgsl-mutate.py` named three missing row classes
    (`render_load` has none at all; the sort needs a fixture whose walk order
    differs from its sort order; one control edit).

## `match` cannot scrutinise a computed Maybe, and the fix is a `.of` helper whose
## name is NOT a def the body calls -- which then trips "unfilled law".

Refusing `match F.fold.addr(ar, tb, u):` (a CALL scrutinee) is the brief's rule 2.
The usual fix is `def w_addr.of(m): match m: ...; def w_addr(ar, tb, u) = w_addr.of(...)`.
That works. What does NOT work is splitting a SELF-RECURSIVE def the same way:
`def ls_ins.of(...): Bool.pick(..., ls_ins(x, t))` with `ls_ins` below it is
refused as "an unfilled law" (a law may not call live code), and putting `ls_ins`
above it is a forward reference. A self-recursive def keeps its decision inline --
`case h <> t: Bool.pick(..., x <> acc, h <> ls_ins(x, t))` compiles fine, as
`uop/render.bend`'s `u32_ins` shows. So: the `.of` split is for CALLS, never for
the self-call.

## `Bool.and` is not short-circuiting, and neither is the `Bool` in a fold

Not a Bend rule, a note on the shape: `Bool.and(U32.is_lt(...), Bool.not(O.eq_dt(...)))`
reads like short-circuiting and is not, so both calls are evaluated and both must
typecheck. In a `case 0n:`-style fold that means the `0n` arm cannot be written as
"skip the expensive call" -- it has to be `Bool.pick`, which IS lazy in its arms.

### 9. `F32` HAS NO SOURCE-LEVEL OPS, NO NEGATIVE LITERALS, AND IEEE `is_eq`
MEASURED (2026-10-02), four facts about the pinned 2.0.34 that between them cost
five compile cycles and would cost the next agent the same:

1. **`bend base F32` prints NINE defs and none of them are arithmetic.** The rest
   exist only as LAWS -- `grep "^law F32\."` lists `add sub mul div mod pow neg
   abs sqrt exp log sin cos ... is_eq is_ne is_lt bits read show to_u32`. They are
   compiler builtins with no body to read, so `bend base --names` and grepping for
   `def F32.add` both come up empty and the natural conclusion ("F32 has no
   arithmetic, this port must have rolled its own") is wrong.
2. **A NEGATIVE FLOAT LITERAL DOES NOT PARSE.** `def f() -> F32: -0.0` fails with
   "expected : a name / observed : '0'" -- the lexer takes `-` as a binder. Write
   `F32.neg(0.0)`. There is no float bitcast either (`dtype.bend:537` records this
   for the wide-dtype seams), so a bit pattern is reachable only via `F32.bits` on
   the way OUT.
3. **`F32.is_eq` is IEEE and `UOp.key` is a hash over the packed arg, so CONST
   IDENTITY MUST BE BITWISE.** The two cells where they disagree disagree in
   OPPOSITE directions, both measured live in CPython:
   `Tensor(0.0)._uop is Tensor(-0.0)._uop` -> **False** (0x00000000 vs 0x80000000)
   `Tensor(nan)._uop is Tensor(nan)._uop` -> **True** (0x7fc00000 both)
   So an IEEE test in an interning predicate collapses two distinct CONSTs in the
   first cell AND re-mints one identical node in the second. `U32.is_eq(F32.bits(a),
   F32.bits(b))` is the comparison the key performs. Keep `F32.is_eq` where the
   question really is a value question (`decomp.bend:126` asks "is this 1.0?").
   Every sibling of that predicate is already bitwise -- `eq_bool` is a xor,
   `eq_op` is the U32 tag, `eq_i64` is `H.i64_cmp` -- which is how you can tell a
   predicate that drifted from one that never had to.
4. **`{expr}` INTERPOLATION IN AN `IO.print` STRING DOES NOT FIRE.** `"is_eq={F32.is_eq(a, b)}"`
   prints the template verbatim, braces and all, with NO error -- a probe that looks
   like it ran and produced data. Use the tree's idiom: `String.concat([...])` with
   `Bool.show` / `U32.show` / `F32.show`.

### 10. FOUR MORE, ALL MEASURED BY THE `codegen/opt` UNIT (2026-10-02)
1. **A NEWLINE AFTER `Bool.and(` LEAVES IT UNAPPLIED.** The next line parses as the
   first argument and the whole nest collapses into one function value:
   "expected : Bool, observed : @b:Bool -> Bool". Same family as `case 0n:` quietly
   claiming every successor -- one construct, two unrelated-looking errors.
2. **`match rs hit:` WITH `hit` AS AN ACCUMULATOR IS WRONG FOR A FILTER.** The arms
   consume `h` and hand the NEXT call the CURRENT `hit`. Write a `_put(helper)` that
   takes the element and the accumulator and returns the next accumulator.
3. **`+` IS REFUSED ON A `U32`, AND A `U32` CANNOT BE READ TWICE IN ONE EXPRESSION.**
   So `a == 0 or a > 1` and `0 < a <= 2` are both unwritable as written. The exact
   rewrites are `a != 1` and `a - 1 <= 1` (using `U32`'s wrap), or thread the value
   through a `Data` record. Both rewrites are gated, not asserted.
4. **`def X.of(...)` MUST BE DECLARATED IMMEDIATELY BEFORE `def X(...)`, and the whole
   call chain must be in declaration order.** `X.of` before `X` fails with the
   misleading "a filled definition" -- which reads like a proof obligation, not an
   ordering rule.

### 11. FIVE MORE, ALL MEASURED BY THE `nn/state` + `nn/__init__` UNIT (2026-10-02)
1. **A `Char` LITERAL IS A VALID MATCH PATTERN, AND IT IS THE ONLY WAY TO SPELL A
   CHOICE-PLUS-DESCENT WALK.** `case '.':` scrutinees a BINDER and consumes `c` once
   per arm, so a walk like `drop(cs, acc)` needs no `Bool` at all:

   ```bend
   def drop(cs: List<&2, Char>, +acc: List<&2, Char>) -> List<&2, Char>:
     match cs:
       case Nil{}: List.reverse(&2, Char, acc)
       case c <> t:
         match c:
           case '.': drop(t, acc)
           case _: drop(t, List.append(&2, Char, acc, [c]))
   ```

   This is the FOURTH shape found for that problem and the cheapest. `Char.is_eq(c,
   ...)` is a CALL and a `match` may not scrutinise one (rule 2); `Bool.pick` evaluates
   both arms and consumes `c` twice; and hoisting the `Bool` into a second def makes
   the two defs MUTUALLY recursive, which Bend refuses. A literal dodges all three.
   **The trap: a bare `case '.':` is not `lstrip`.** Dropping every dot gives
   `a..b..` -> `ab` where Python's `str.strip('.')` gives `a..b`; a head-run strip needs
   a "seen a non-dot yet" flag, and a `Data` sum type carrying it is the answer.
2. **`case 0n:` DOES NOT MATCH A `U32` AT ALL.** "expected : a constructor of U32
   (missing, or already matched)". So a countdown and the INDEX IT COUNTS must have
   different types: `def f(n: Nat, +i: U32, ...)` with `U32.to_nat(ndim)` at the entry.
   And there is **no `Nat.to_u32`** in base (only `U32.to_nat`), so a value that has to
   come OUT of a `Nat` countdown needs a second `U32` parameter rather than a
   conversion. For a negative axis, `-1-m` is built as
   `H.i64_of_hi_lo(0xFFFFFFFF, 0xFFFFFFFF - m)` -- the two's complement pair -- and not
   by subtraction.
3. **`List.append` AT THE TAIL AND `h <> acc` AT THE HEAD ARE DIFFERENT ORDERS, AND
   ONLY THE SECOND ONE NEEDS A `List.reverse`.** An accumulator built with
   `List.append(&2, T, acc, [x])` is ALREADY in order; a final `List.reverse` undoes the
   walk. This cost two gate rows (`bn_mask`, `bn_axes` both came out reversed) and it is
   the exact inverse of `state.bend`'s walk, which conses onto the head and so does
   reverse. **Read the accumulator's construction before you add a reversal.**
4. **`Bool.pick` IS THE ONLY WAY TO PUT A SELF-CALL IN A CHOICE-POSITION WITHOUT
   MUTUAL RECURSION, and it costs a `+` on every value both arms touch.** Rule 3's
   `_put(helper)` shape works when the two arms are VALUES; when one arm is the
   recursive call, `Bool.pick(T, cond, a, self_call(t, e))` is the shape, and `f`/`e`
   need `+` because `pick` evaluates both. The LIST must still be the first parameter:
   rule 5 reads left to right and stops at the first argument that shrinks, so a
   parameter that GROWS in the self call (`seen`) has to come second.
5. **BARE `False`/`True` IS A PARSE ERROR IN A CALL ARGUMENT BUT `False{}` IS NOT
   OPTIONAL EITHER WAY.** `T.flag(x, False)` gives "expected : a defined name, observed
   : False" while `Bool.show(...)` and a `match` scrutinee are the only places a bare
   `False` ever worked. **Write `False{}`/`True{}` in every value position** (rule 8 is
   about patterns; this is the value case it does not cover).

## SEVEN MORE RULES, MEASURED 2026-10-02 WRITING `device.bend`

The gate is 107 printed rows checked against the `tinygrad.device` oracle, both
lanes byte-identical, plus a 30-entry mutation table at the foot of the file.
Every rule below cost a compile cycle; the reproducer for each is a three-line
`.bend` file.

### 1. A LIST OF `Bool` IS NOT A USABLE TYPE

`List<&2, Bool>` is ACCEPTED as a parameter annotation and then refused by
every reader of one:

    def f(oks: List<&2, Bool>) -> Bool:
      match oks:
        case Nil{}: False{}
        case h <> t: h
    #| - message : a match on a parameter or field
    #|             (this name is a def or a consumed binder: give the value its own def)

which is the message you get for a PROJECTION and not for a list, so it sends
you looking for a `Data` field access. `List.get(&2, Bool, xs, 0n)` and
`List.length(&2, Bool, xs)` both report "expected a defined name": `Bool` does
not resolve in a `Kind` position. A `Bool` FIELD of a `Data` record is fine, and
so is `List<&2, Rec>` where `Rec` wraps the flag.

The fix that also removed a zip fold: availability/deprecation/mock-ness are a
U32 BITMASK read with `U32.shrn`/`U32.and` against the row's own index.

### 2. A PATTERN BINDER MUST NOT SHADOW A DEF NAME, and the error names the CONSTRUCTOR

    type Telf is Data: Telf{nm: String, sigs: List<&2, U32>}
    def Telf.name(x: Telf) -> String:
      match x:
        case Telf{name, sig}: name
    #| - message : a declared constructor (unknown: Telf)

The binder `name` shadows the def `Telf.name`, and the error points at
`Telf` -- the thing that is perfectly well declared. `case Bn{... spec}: spec`
fails the same way when the file also has `def spec()`. This is the same defect
the existing "A `Data` RECORD PATTERN ... " family has, one level up, and it is
worth grepping for: a binder named after any def in the file is a landmine whose
error message names something innocent.

### 3. `+` ON A PATTERN BINDER IS THE SPELLING FOR "TWO READS IN ONE EXPRESSION"

`+` is documented for parameters and for list heads, and the binder case is the
one that unblocks arithmetic. A `U32` is affine and cannot take a `+` as a
PARAMETER, so `(n+a-1)//a*a` -- `a` three times -- is a `Data` record of the two
operands with the `+` on the binder:

    type Amt is Data: Amt{n: U32, a: U32}
    def round_up.go(x: Amt) -> U32:
      match x:
        case Amt{n, +a}: U32.mul(round_up2(a, U32.add(n, U32.sub(a, 1))), a)

`Flags`, `Cap`, `Step` and `Run` in `device.bend` are the same trick for the same
reason, and the generalisation is the useful part: **when a `U32`/`Nat` is read
more than once in one expression, put the operands in a `Data` record and `+` the
binders.** That is cheaper than a `.go` split per read and it composes.

### 4. A NESTED `match` ARM MAY NOT CALL A `Type.def`

    def bnew.go(ns: List<&2, Bn>, b: Bn, ix: U32) -> BFound:
      match b:
        case Bn{...}:
          BFound{List.append(&2, Bn, Bar.nodes(ar), [...]), ix}
    #| - expected : Bar
    #| - observed : List<&2, Bn>

Inside a `Data` record arm, `Type.def(x)` is read as the TYPE applied to the
arm's binder, and the error is about the argument. Hoist the call above the
`match` and pass the value in. The same shape also bit `too_big`, where
`Bool.and(a, Bool.and(b, c))` with a shared `U32` produced the identical message.

### 5. A DEF MAY NOT CALL A NAMESPACE THAT A PARAMETER SHADOWS

    def isig.go(sig: List<&2, U32>, ...) -> ...:
      ...
        case Nil{}: acc
        case _ <> t: sig.go(t, ...)      # sig is the PARAMETER
    #| - expected : a term
    #| - observed : '.'

A parameter named `sig` makes `sig.go` a name lookup on the parameter. Every
`case k <> t:` fold in a file that also has a namespace called `t` has this
landmine -- and the error points at the fold, not at the binder.

### 6. `case True{} True{}:` IS A FINE ARM AND `case _ _:` AFTER IT IS FINE, BUT A `+` PARAMETER AND A `+` FIELD ARE NOT THE SAME THING

`def recycled(glru: Bool, lru: Bool, sp: Bspec)` reads `glru` and `lru` once each
and works. What does NOT work is `match glru lru Bspec.nolru(sp) ...` -- a
`Data` field is not a legal scrutinee even when the record is the parameter, so
the two flags have to travel as a two-field record (`Flags`) and be destructured
by the binder. This is `spec.bend`'s `DevOpt` shape and it is the ONLY reason
that shape exists; the `Maybe`-field prohibition and the non-scrutinee-field
prohibition are the same rule seen from two sides.

### 7. A `U32` THAT IS BOTH A LOOKUP KEY AND A FALLBACK VALUE BELONGS IN THE NODE

`base_of` needs the buffer's own index as an ANSWER (Python's `self._base if
self._base is not None else self`) AND the node to read `has_base` out of, and
`U32` is affine so the index cannot be passed twice. A `Slot{b: Bn, i: U32}`
record does NOT fix it -- `slot(ar, i) = Slot{bar_at(ar, i), i}` reads `i` twice,
and the fix-up `bar_at.make(ns, n) = Slot{..., n}` then reads `n` twice, one
level down. The fix that works is to put the index IN the node (`Bn.self_ix`),
stamp it at append time, and read it back off the record the append returned
(`BFound{ar, bar_next(ar) - 1}`). Three attempts failed before that one; the
tell in every case is the same error, "expected : i, observed : i (consumed more
than once)", and the generalisation is: **a value that is both a key and a
result belongs in the record you looked it up in, not beside it.**

## A GATE LESSON, AND IT IS THE SAME ONE THREE TIMES

`device.bend`'s first mutation table had three rows that moved NOTHING, and
none of them was a bad mutation:

* dropping `is_param` from `pm_bufferize` rules 0, 1 and 2 -- every fixture was
  a PARAM, so the conjunct was vacuously true. The fix was three NEGATIVE
  fixtures: a node that is not a PARAM, one named `b` that is not a PARAM, and
  one tagged `timeline` that is not a PARAM.
* lower-casing the `ALLOW_DEVICE_USAGE` list -- every fixture passed a
  lower-case spelling, so again the conjunct was vacuous. The fix was
  `allow_lower`, the spelling that must NOT be allowed.
* and then, WITH that fixture in place, the mutation STILL moved nothing,
  because the mutation touched the `DISK` branch and the rows exercise the
  `PYTHON` one.

So: **a mutation that moves nothing is information about the GATE, and the
response is to build the fixture it is asking for -- twice, if the first fixture
was for the wrong conjunct.** The third case is the one worth remembering: after
adding a fixture, RE-RUN the mutation, because "I added a fixture" and "the
fixture sees this mutation" are different claims.

## SEVEN MORE RULES, MEASURED 2026-10-02 WRITING `mixin/movement.bend`

Appended, not edited. All seven are Bend 2.0.34 and each one cost a compile cycle or a
wrong answer. The first is the one that cost the most and it generalises further than
it looks.

### 1. `case 1n+p:` DESTROYS THE SCRUTINEE — THE ARM CANNOT READ THE CURRENT COUNT

This is distinct from the recorded "`1n+p` is a first-match prefix" rule, and it is the
single most expensive fact in this port. `match k: case 1n+p:` binds `p` as a strict
subterm of `k` for the decrease check AND SPENDS `k`: the arm can no longer mention the
name `k` at all. Every walk that needs the current INDEX — not the tail — must thread
that index as its own parameter. Measured, three refusals and one working spelling:

```python
# REFUSED: expected p / observed p (consumed more than once) -- reported AT THE `1n+p:`
# PATTERN, so it reads like a pattern-syntax bug and is not one
List.append(&2, U32, [ix], go(p, nn, U32.add(ix, 1)))              # ix as a param: WORKS
List.append(&2, U32, [U32.from_nat(k)], go(p, nn))                 # reads k: REFUSED
List.append(&2, U32, [U32.add(nn, 2*U32.from_nat(p))], go(p, nn))  # reads p: REFUSED
```

The error text names `p` in all three cases and the CAUSE is `k`. Diagnosing this costs
a cycle every time because the compiler is pointing at the one binder that is fine.

### 2. SPLITTING A SELF-RECURSIVE STEP TO AVOID A DOUBLE READ CREATES MUTUAL RECURSION

Rule 3's remedy is "split the step into a `.go` and a `.put`". That works when the split
is between a WALK and its DECISION, and it is REFUSED when the split is between a
self-recursive walk and its own STEP — because the step calls back into the walk, and
the walk calls the step, and that is mutual recursion in either declaration order:

```
def w.go(k: Nat, ...) -> R:
  match k:
    case 1n+p: w.put(p, ...)          # w.put needs w.go  -> MUTUAL, refused
```

The working shape is ONE def whose arm both recurses and does the work, with the
element's contribution computed by a LEAF. The cost is that the leaf's own arguments
must not include the fuel.

### 3. `Bool` HAS NO `U32.show`, AND THE CONVERSION IS `Bool.pick` — THERE IS NO `Bool.match`

`base.bend` has `Bool.pick(-A, c, a, b)` and no `Bool.match`, so a gate row that computes
a `Bool` pays a two-arm conversion at every call site. Hoist it:

```bend
def b2u(b: Bool) -> U32: Bool.pick(U32, b, 1, 0)
```

`U32.show` and `Nat.show` exist; `String.show` and `String.to_u32` do not.

### 4. `String.join(xs, sep)` TAKES THE LIST FIRST, AND `String.concat(xs)` TOO

Both take a LIST of pieces, so `String.concat("a", b)` is `expected : List<&2, String> /
observed : String`. And `String.join(",", xs)` — the natural Python reading — is the same
error. `String.join(xs, sep)` is right. The failure is silent in neither direction: it is
a type error at the first call, which is the good case.

### 5. `IO.print` TAKES A `String`, AND A `do IO<Unit>` BLOCK CAN ONLY BIND AN `IO`

The first is one line. The second is recorded for `uop/weak.bend` and it recurred here:
`m : MxMarg <- pure(...)` is `expected : a defined name / observed : pure`, so a PURE
fixture value is a `let` in the caller and a PARAMETER of the printing def. The cost is
one extra parameter per row def; the alternative is recomputing the pure value per row.

### 6. `List.take(xs, 0n)` IS THE EMPTY LIST AND `List.append(a, A, xs, ys)` IS `xs ++ ys`

The second is recorded. The first is new and it is a TRAP rather than a rule: a fixture
that takes a prefix of length 0 gets `Nil{}` and a fold over it produces an EMPTY answer
that reads as a correct empty shape. It cost one cycle here — a four-dim shape came out
with its two leading dims missing, and the `List.take` of length 0 in the debugger was
the whole diagnosis.

### 7. A FIXTURE MUST INTERN ITS SHAPE ARGS THROUGH ONE BUILDER, AND A LIST OF RAW INTS IS NOT A LIST OF ARENA INDICES

`shape_to_shape_arg` (ops.py:106) turns python ints into CONST nodes. A fixture that
writes `UOp.new(ar, OpsSTACK{}, [0, 1, 2, 3], ...)` builds a STACK whose "srcs" are the
raw VALUES 0..3 read as arena indices — index 0 is the arena's BOTTOM, so the reader
answers the bottom's `ANone` arg and the value comes out 0. It typechecks, the node count
is right, the `nsrc` is right, and every marg element reads 0. The one row that sees it
is the one that prints the marg's VALUES, and it is the reason this file has a separate
`*_marg` row next to every `*_shape` row.

## SEVEN MORE RULES, MEASURED 2026-10-02 WRITING THE WRITE HALF OF `mixin/movement.bend`

Appended, not edited, continuing the count from 11. All seven are Bend 2.0.34 and each one
cost a compile cycle or a wrong answer. The first is the most dangerous silent failure in
this port so far.

### 11. AN ARGUMENT IS EVALUATED BEFORE THE CALLEE BRANCHES, SO AN INTERNING INSIDE AN ARGUMENT BUILDS A SELF-EDGE

`O.UOp.new(ar, op, [u, O.Found.i(G.c1(ar, v))], ...)` is the obvious spelling and it
produces a node whose SECOND SRC IS ITSELF:

```python
add=n=8 op=Ops.ADD nsrc=2 srcops=Ops.RESHAPE|Ops.CONST   # correct
# add=n=6 op=Ops.ADD nsrc=2 srcops=Ops.RESHAPE|Ops.ADD   # what the obvious spelling gives
```

`G.c1(T.Tensor.ar(t), v)` interned into a COPY of the arena, and the index it returned is
the slot the ADD was about to occupy. The fix is to intern into a `let` FIRST and build
in the resulting arena -- which is the notes' existing "BEND IS STRICT" rule, reached from
a new direction. **The tell is a src-op sequence that names the root's own op.**

### 12. A `list` SELF-CALL MAY PASS A LIST TAIL FIRST AND A `U32` ARENA SECOND, AND THAT IS THE ONLY ORDER

`mxw_stk` walks a list of dims and grows an arena per dim. The decrease check wants the
list first, and the arena second:

```bend
def mxw_stk(+vs: List<&2, U32>, +ar: O.Arena, +acc: List<&2, U32>) -> O.Found:
  match vs:
    case Nil{}: G.mstack(ar, acc)
    case v <> t: mxw_stk(t, O.Found.ar(G.c1(ar, v)), ...)     # list FIRST
```

Walking a LIST rather than a `Nat` countdown is the reason this is one def with no fuel:
the tail `t` is a strict subterm of `vs`, so the check is satisfied by the first argument
and there is nothing to thread.

### 13. THE "INTERN ONCE, READ TWICE" FIX IS MUTUAL RECURSION IN A WALK

`+f = G.c1(ar, v)` then reading `Found.ar(f)` and `Found.i(f)` is obviously right and it
needs a def boundary, and in a self-recursive walk the def calls back into the walk. The
workable forms, all measured in this file:

- a straight-line fixture (`stk4` for a fixed arity);
- a `Data` record carrying the accumulator;
- **call the pure function twice.** `O.UOp.new` and `O.UOp.const` are pure given an
  arena -- the arena carries the intern table, so the second call finds the node the first
  one added -- so `Found.ar(g(ar,v))` beside `Found.i(g(ar,v))` is CORRECT, not lucky.

That last one cost a cycle to convince me of and is the reason it is written down.

### 14. A GATE ROW THAT PRINTS A `srcops` SEQUENCE MUST PUT ALL FOUR FACTS IN ONE STRING

Four separate rows let a fixture drop one. The mutation that made this concrete: SWAPPING
A PAD'S TWO SHAPE ARGS (`self|a|b` to `self|b|a`) leaves the root op, the src count and
almost the node count alone, and it moved exactly TWO of seventy rows -- the two where an
identity test happened to fire. A gate carrying `op` and `nsrc` but not the sequence is
completely blind to it. `mxw_sig` prints `n= op= nsrc= srcops=` as one string for exactly
this reason, and the cost is that a mutation in the PRINTER then invalidates a quarter of
the suite (measured: 25 of 70 rows).

### 15. A SHAPE ARG BUILT BY A WALK MUST APPEND, AND THE BUG IS INVISIBLE IN THE COUNT

The second time in this file (the first was the printer). `mxw_stk` walks the dim list
DOWN and accumulates UP, and `List.append(&2, U32, [i], acc)` puts the new index at the
FRONT, so a STACK for `[1, 4, 8, 8]` came out `STACK(8, 8, 4, 1)`. The node count was
right, the root op was right, the `nsrc` was right. The symptom was an EMPTY shape,
because `mxm_as_shape` read a first element of 8 where the base had 1 and the identity
test could not match. **The general rule: an accumulator fold over DIMENSIONS has to say
which end it adds to, in a comment, because the type and the count cannot see it.**

### 16. `Arena.node` ANSWERS THE BOTTOM FOR AN INDEX PAST THE END, SO A STALE ARENA GIVES AN EMPTY ANSWER NOT A WRONG ONE

`mxw_reshape`'s identity test reading `T.Tensor.ar(t)` (the base's arena) with
`T.Tensor.u(made)` (the made node's index) returned `False` for a no-op reshape, so
`reshape` to the shape it already had BUILT a RESHAPE where CPython returns `self`. The
usual symptom of the aliasing rule is a wrong node; this one is a MISSING node, because
the bottom's shape is the empty list and the empty list does not equal anything.

### 17. A GATE MUST HAVE A NON-MOVEMENT FIXTURE OR A `match`'s CATCH-ALL ARM IS DEAD CODE

`mxw_shape_of`'s `case _ False{}` arm -- the one that answers a NON-movement op from the
fold -- had no fixture, so mutating it to `Nil{}` moved NOTHING. The reason every movement
row missed it: the one non-movement node they reached (the BUFFER under a RESHAPE) is a
node `fold.bend` does not answer, so its answer is the empty list EITHER WAY. The fix is a
non-movement node the fold DOES answer -- `ADD` inherits its shape from its src -- and the
row is `add_shape`.

This is the mirror image of the recorded "an arm after a `case _:` is dead code" rule: a
catch-all with no fixture is equally invisible, and a `case _` that is only reached by
nodes nothing else reaches is the same defect wearing a different hat.

## SIX MORE RULES, MEASURED 2026-10-02 WRITING `mixin/creation.bend`
## (items continue the count from 17)

Appended, not edited. Four of these six are substrate facts about `uop/fold.bend` and
`uop/ops.bend` that a caller must know and cannot read off either file's header; the
other two are Bend syntax. Each one cost a compile cycle or a wrong answer, and the
reproducers are named.

### 18. AN UNANSWERABLE NODE POISONS ITS CONSUMERS, SO "CAN THE FOLD ANSWER X" IS A
###     PROPERTY OF THE WHOLE SUBGRAPH, NOT OF X

This is the most expensive thing in this section and it is not in `fold.bend`'s header.

`fold.bend` answers `Ops.EXPAND` with `None{}` for the SHAPE (fold.bend:1629,
"`marg` -> `as_shape` -> `ssimplify`"). `Ops.STORE` and `Ops.AFTER` are `store_ds` and
`thru0` (fold.bend:730, :726), and BOTH read `src[0]`'s `Derived` -- so they are answered
when their `src[0]` is answered. But a Kahn worklist does not resolve a node until all
of its own srcs are resolved, so:

    MEASURED over `Tensor.full((2,3),42)`, nine nodes, one arena:
      1 ALLOC     dt=yes shape=yes
      2 CONST 2   dt=yes shape=yes
      3 CONST 3   dt=yes shape=yes
      4 STACK     dt=yes shape=yes
      5 RESHAPE   dt=yes shape=yes
      6 CONST 42  dt=yes shape=yes
      7 EXPAND    dt=NO  shape=NO      <- fold.bend:1629
      8 STORE     dt=NO  shape=NO      <- its src[1] is the EXPAND
      9 AFTER     dt=NO  shape=NO      <- src[1] is the STORE

So one unanswerable node three levels down makes the ROOT unanswerable, and a gate row
that asks the fold about the root of ANY graph containing an EXPAND gets `void` and `()`
for reasons that have nothing to do with its own code.

**THE CONSEQUENCE FOR EVERY CALLER, and it is a design decision rather than a workaround:
decide WHICH node to fold, not whether to fold.** The AFTER's own answer is `thru0`, i.e.
literally `AFTER.src[0]`'s, so folding `AFTER.src[0]` is not a weakening -- it is the
same answer obtained from the node the fold can reach. `mixin/creation.bend`'s `cr_d_root`
does exactly that, names the measurement, and its `_d` rows are still gated. The
alternative -- computing the shape from the construction -- is a row that restates the
code, which is the thing the gate exists to prevent.

This also retires a reading of `fold.bend`'s header: "the fold reports the absence and
the caller decides" is true PER NODE and misleading PER GRAPH, because the absence
propagates upward along every edge.

### 19. A FOLD THAT NEEDS AN INDEX MUST USE `Arena.srcs`, NOT A COUNT AND A RE-DERIVED
###     INDEX

    def srcops.go(+ar: O.Arena, +c: CU, n: Nat) -> String:      # the WRONG shape
      match n:
        case 0n:   ""
        case 1n+p: ... O.Arena.op(ar, O.Arena.src(ar, CU.u(c), 0)) ... cr_srcops.go(ar, c, p)

Every row printed `ALLOC|ALLOC|` for a two-src root. It checked, ran, and printed a
plausible string; the only reason it was caught is that the row carried `nsrc=2` beside
it. The fix is one call:

    O.Arena.srcs(ar, u)   # -> List<&2, U32>, and the walk needs no index at all

This is the same class as the recorded `mxm_as_shape.go` slip (an accumulator read
backwards) and it generalises the pair "walk a list" / "index into a structure": if the
walk needs `xs[k]`, take `xs` and walk it. `Arena.srcs` is already the substrate's own
answer for `x.src`, and `Tensor`'s `Tensors.ts` is the same idea for a record.

### 20. A LIST-OF-STRINGS FOLD MUST END IN `String.join`, NOT IN A BAKED-IN SEPARATOR

There are now four recorded spellings of "join a list of strings" in this port and the
first three each cost a row. The one that costs nothing is:

    List.append(&2, String, acc, [piece])   # APPEND, in walk order
    String.join(xs, " ")                    # HEAD-FIRST, and no trailing separator

`String.concat([acc, piece, " "])` needs a head test to avoid a trailing separator;
`String.concat([acc, cr_topo.go(List.tail(xs), ...), " "])` DROPS THE HEAD (and leaves a
trailing space). Both were written, both compiled, and both were caught only by the
CPython byte diff -- because the shape row reads `(2,3)` and the buggy one reads `(3,2)`,
which is a REAL wrong answer rather than a formatting one.

The general form, and it is the same for `U32` lists rendered with `U32.show`: **build a
`List<&2, String>` with `List.append` and hand it to `String.join` once, at the end.**
`List.append` is already the "which end does this list go next" decision from the wgsl
entry; `String.join` removes the other half of it.

### 21. `+r = R{a, b}` NEEDS AN ANNOTATION; `+r = f(...)` DOES NOT

    def f() -> U32:
      +r = R{1, 2}      #| - expected : an annotated term (cannot infer)
                        #| - observed : R{1, 2}
      R.a(r)

    def f() -> U32:
      +r: R = R{1, 2}   # ok
      R.a(r)

Three lines, no imports, both lanes. A `let`-bound RECORD LITERAL needs its type spelled;
a `let`-bound def call does not, because a def's return type is already known (upat.bend
rule "a computed value is not a valid scrutinee" has the same shape). It bites the
FIRST time in a file, which is usually a `CU{u: index}` or a `Fixed{n: U32}` helper
record, and it costs a cycle each time because the message names the record rather than
the `+`.

### 22. A BYTE-DIFFED GATE MUST NOT INHERIT A PRINTER WHOSE OUTPUT HAS TRAILING WHITESPACE

`mixin/op.bend`'s shared signature printer `mo_sig.go` emits `" "` after every node, so
every row built from it ends in a space. `mixin/creation.bend` needs the same toposort
string, reused it, and then the CPython oracle needed `.rstrip()` to match -- a
formatting asymmetry in the one comparison that is supposed to be exact. Four local lines
(`cr_topo.go` + `String.join`, rule 20) removed the asymmetry and made the rows readable
in a diff.

The general form: **a shared printer that another file's gate already diffs is a shared
FORMAT CONTRACT, and inheriting it means inheriting its whitespace.** When a new gate
reuses one, check `tail -c 1` on a row before the oracle is written, not after.

### 23. THE `int_*_new` SHAPE -- "HOW MANY DID THE SECOND CALL MINT" -- IS A ROW CLASS OF
###     ITS OWN, AND IT IS THE ONLY ONE THAT SEES `UOpMetaClass.ucache`

tinygrad hash-conses every UOp, so a second `Tensor.full((2,3), 42)` re-uses the CONST,
the STACK and the EXPAND and mints only the ALLOC/RESHAPE/STORE/AFTER. **Both graphs
have a nine-node toposort**, so `n=`, `op=`, `nsrc=` and the toposort are all identical
and every one of them is blind to the whole question.

The row that answers it is

    <n>_new = |{u in b.toposort() : u is not any(v in a.toposort())}|

with `is` in CPython and `U32.is_eq` on arena indices in Bend -- which is the same test,
because `ops.bend:940` says the index IS the identity. Two things about it worth keeping:

* the COUNT is not enough, and a second Bool row asking directly ("is the node that must
  be shared, shared?") is what localises the failure. In `creation.bend` the count row
  `int_full_new` moved 3 mutations and the Bool row `int_full_expand` moved exactly ONE
  that nothing else saw: reversing the STORE's two srcs. Same count, same op, same nsrc,
  same toposort, same src op sequence.
* the CPython oracle must count the same way. A `len(UOp.ucache)`-shaped row will not do:
  the cache holds WEAKREFS and entries not in the delta get collected, so the same
  program answers a different number on a second run.

This is the "it is not only rules that collide, it is any check whose oracle is a COUNT
rather than a STRUCTURE" note from `mixin/gradient.bend`, stated for the specific case
where the two structures are EQUAL in count by construction.

## NINE MORE RULES, MEASURED 2026-10-02 WRITING `mixin/rand.bend` (items continue from 23)

Appended, not edited. All nine are Bend 2.0.34 or substrate facts, and each one cost a
compile cycle or a wrong answer. Rules 1, 2 and 3 are the ones that cost the most and the
first two are the reason that file's gate is red rather than green.

### 1. AN ARENA IS AFFINE, SO A DEF THAT BUILDS **GROWS A COPY** -- AND THE FIX IS TO THREAD `+ar`
###    THROUGH EVERY BUILDING DEF, NOT TO "BUILD IN THE LAST ARENA"

The recorded rule (`codegen/transcendental.py` rule 1) is "every step threads
`O.Found.ar(<previous binding>)`". Measured while porting `mixin/rand.py`, the part that is
easy to believe and easy to get wrong is that **taking the arena off a tensor you were
HANDED is not the same thing as threading it**, because every def that builds along the way
has already grown a copy that you do not have a handle on:

    rd_tfb -> rd_p64 -> rd_c64 -> MO.mo_cast_t -> MO.mo_cast_in -> F.folded(T.Tensor.ar(t))

`mo_cast_in` re-folds the arena off its own argument and hands back a tensor whose arena is
that fold's, which is a copy. Two operands built through two such chains are in two
SIBLING arenas, and a node built in one of them names an index the other does not have.

**THE SYMPTOM IS A TOPOSORT OF ONE NODE, WHICH LOOKS LIKE A BUG IN THE PRINTER.**

    bits6_g=1 op=RESHAPE nsrc=2 srcops=STACK|STACK topo=CONST/0     <- the port
    bits6_g=81 op=RESHAPE nsrc=2 srcops=STACK|CONST topo=CONST/0 CAST/1 ...  <- CPython

and `st_six_g=2` against CPython's `st_six_g=20`. The root's data src is not in the arena
being walked, so the "graph" is one node. **It also HANGS** when a `mxw_dims_of` fold runs
over it: `mixin/rand.bend`'s `randn_like23_g` dies with
`bend: memory fault (machine stack overflow?)`, which the notes' RUNAWAY-EXPANSION section
sends you looking for a non-terminating fold in your own code. There is none; the arena is
inconsistent and the fold over it does not terminate.

The generalisation, and it is the shape of every multi-file port in this repo: **a def that
may mint takes the arena as an ARGUMENT and rebases its operands with
`T.tn_new(ar, T.Tensor.u(t))` before building.** A node index is valid in every EXTENSION
of the arena it was interned into, so rebasing into a longer arena is always sound; what is
unsound is a def that picks its own arena off an operand it was handed.

### 2. A `U32` LITERAL PATTERN IS A PREFIX MATCH **FOR THE SUCCESSOR RELATION ONLY**, SO `case 8:`
###    DOES NOT SWALLOW `case 32:` -- AND THAT IS THE GOOD NEWS AND THE BAD NEWS

The recorded rule is "`case 1:` claims every successor", and
`codegen/opt` unit rule 10.3 restates it as "a `U32` literal pattern is a prefix match".
MEASURED here, the generalisation is FALSE and the narrow form is true: `case 8:` does NOT
claim 16, 32 or anything above it. `rd_one_bits`' arms `case 16: 15360 / case 32: 1065353216`
both fire on their own value (measured: `ref_one_bits_h=15360`, `ref_one_bits_f32=1065353216`).

**THE BAD NEWS IS WHAT ELSE IT DOES NOT CATCH, and the cost is a whole gate row.** The same
def spelled `case 8: 23 / case 16: 10 / case _: 0` -- arms on the EXPONENT where the switch
is on the BIT WIDTH -- compiles, checks, runs and answers `0` for float32. The
`case _:` is a real cover, so exhaustiveness is satisfied and nothing is dead. Two rows
(`ref_nmant_f32`, `ref_shift_f32`) caught it, and the mutation that drops the `case 32:`
arm moves EXACTLY those two and nothing else.

So the useful statement is: **a numeric arm ladder is only as good as the number it switches
on, and the compiler cannot see that number.** The recorded "prefix match" rule bites on the
ONE literal that generates all successors; the general hazard is that a `case _:` cover makes
a WRONG-NUMBERED ladder indistinguishable from a right one.

### 3. `mxw_reshape` / `mxw_shrink` / `mxw_pad` BUILD A `STACK` FOR A ONE-ELEMENT SHAPE ARG AND
###    CPYTHON BUILDS A BARE `CONST` -- SO A FILE THAT NEEDS CPYTHON'S ANSWER MUST CALL
###    `T.tn_mop` WITH `T.ADims`/`T.APairs` INSTEAD

`shape_to_shape_arg` (ops.py:106-110) is `return src[0] if len(src) == 1 else UOp(Ops.STACK,
src=src)`. MEASURED in CPython: `Tensor.empty(5).pad(((2, 0),))` is
`ALLOC/0 CONST/0(2) CONST/0(7) PAD/3` -- FOUR nodes, and the two shape args are BARE CONSTs.
`movement.bend`'s `mxw_stk` is `G.mstack`, which is UNCONDITIONALLY a STACK, and
`movement.bend`'s OWN header says so ("THE BARE-CONST CASE IS A DIFFERENT NODE and that is
the row `mxm_reshape1`").

**SO `T.tn_shape_arg.k`'s `one` arm is the ONLY spelling of CPython's rule, and it is
reachable only through `T.tn_mop`/`T.ADims`/`T.APairs` -- not through any `mxw_*` wrapper.**
`creation.bend` gets it right for free because `cr_mop` calls `T.tn_mop`; a file that
reaches for `mxw_reshape` gets a different graph for a one-element shape. `_cumalu`'s pad
is `((shape-1, 0),)` (op.py:754) and `_pool`'s first shrink is `(0, k*(i*f+1))`
(movement.py:610), so on the `arange` path BOTH of `_pool`'s first two shape args are
one-element and every `mxw_*` call adds a STACK.

The identity test is affected too, and the notes' `mxm_reshape1` row is the same fact from
the other side: `mxm_as_shape` reads `Arena.srcs` and a bare CONST has none, so a one-element
RESHAPE is un-answered for a SECOND and independent reason. `mixin/rand.bend` carries local
`op_pad`/`op_shr` for this and names the owner file, because `movement.bend` is read-only
there. **A file that needs CPython's graph has to own the one-element case itself until
`mxw_stk` grows `tn_shape_arg`'s fold.**

### 4. `+p: F32` IS ACCEPTED, SO THE `U32` "TWO READS NEED A RECORD" RULE IS NOT A `U32` RULE

`rd_p_ok(+p: F32) -> Bool: Bool.and(rd_p_ok.put(p), F32.is_le(p, 1.0))` checks, so a
two-read `F32` is a `+` parameter and a two-read `U32` is NOT (`+` is refused on a `U32`,
`nn/optim` unit rule 1). The `U32` answer is the `Data` record and the reader def
(`mixin/rand.bend`'s `U1`/`U1.v`), which is `device.bend`'s rule 3. Having both answers in
one file is what made the distinction visible: the rule is about the KIND, not about
"numbers".

### 5. `+dev: S.Dev` ON A `Data` PARAM IS FREE AND A GLOBAL `+` SWEEP IS THE FASTEST FIX FOR A
###    WHOLE FILE OF `Device` PASSED ONWARD

Twenty-five `S.Dev` parameters in `mixin/rand.bend` needed `+`, because `device` is threaded
from the fixture through six layers and read once per layer. `creation.bend` has the same
parameter. A blanket `dev: S.Dev)` -> `+dev: S.Dev)` sweep compiled first try. An UNUSED `+`
parameter is accepted (`uop/spec.bend` rule 2), so the sweep cannot break a def that does
not read it -- which is exactly why a uniform annotation is safe here and a uniform
annotation on a `U32` is not.

### 6. A `def X.of` CHAIN MUST BE DECLARED LEAF-FIRST **AND** `X.of` MUST IMMEDIATELY PRECEDE
###    `X` -- SO THE THREE-LINK CHAIN READS BOTTOM-UP

`codegen/opt` unit rule 10.4 records the one-def version. The three-link version, and it is
what "a `match` may not scrutinise a call" forces whenever a choice needs a call's result:

    def op_mop.of(same: Bool, +t, +made) -> T.Tensor: ...   # the LEAF
    def op_mop.of2(+t, +f) -> T.Tensor: op_mop.of(MX.mxw_same(...), t, T.tn_alu.put(f))
    def op_mop.put2(op, +t, lo, hi) -> T.Tensor: op_mop.of2(t, T.tn_mop(...))
    def op_mop(op, +t, lo, hi) -> T.Tensor: op_mop.put2(op, t, CR.cr_cdims(lo), CR.cr_cdims(hi))

Written in the order the reader wants (outer first) every one of the three is a forward
reference, and the error is "a filled definition (an unfilled law is a dead claim)". So the
chain is declared leaf-first and READ bottom-up, and the naming is what makes it legible:
`.of` is the leaf, `.of2` the next, `.put2` the next, and the bare name the wrapper.

### 7. `def f.g` and `def F.g` ON A LOCALLY-DECLARED `Data` RECORD NEED A READER DEF, A FIELD
###    PROJECTION IS NOT ONE, AND A ONE-FIELD READER IS REFUSED

`def PK.i(q: PK) -> U32: match q: case PK{i}: i` is refused with
`a PK pattern with 2 fields` -- the two-field rule from `renderer/cstyle.bend` rule 5, reached
from a record whose fields are all `U32`. And `PK.i(q)` as a BARE projection is
"a defined name, observed : PK.i", so a locally-declared record has no projection syntax at
all: a reader def is the only way, and it is the shape `ops.bend`'s `CU.u`,
`movement.bend`'s `MxMarg.ds` and `tensor.bend`'s `Tensors.ts` already use.

### 8. THE ORACLE'S `print("k=", v)` HAS A TRAILING SPACE AND IT IS HALF THE DIFF

`creation.bend` rule 22, re-measured. `print("ref_x=", True)` prints `ref_x= True` and the
Bend row prints `ref_x=True`, so a byte diff reports 31/49 mismatches on a file where 31/49
match. `print("k=" + str(v))` is the fix, and the generalisation is: **write the oracle's
row strings the same way the port's are, before the first diff, not after the first
confusing one.** The same row of this table and the `fold_np`/`fold5_np` BEND-ONLY rows are
the other half: a row with no oracle is a `BEND-ONLY` row and it belongs in a named list, not
in a silent filter.

### 9. A `.bend` FILE CAN `ALL PROOFS CHECK` IN BOTH LANES, PRINT LANE-IDENTICAL OUTPUT, AND
###    STILL BE WRONG AGAINST CPYTHON -- SO "THE GATE IS GREEN" IS NOT A PROPERTY OF THE FILE

`mixin/rand.bend` measured 2026-10-02: `ALL PROOFS CHECK`, interpreted and native lanes
byte-identical, 49 printed rows, 31 shared with CPython and GREEN, 18 RED. All 31 green rows
are NON-GRAPH rows (refusals, dtype arithmetic, counts) and all 18 red rows are GRAPH rows.
The two lanes agreeing with each other says the port is DETERMINISTIC; it says nothing about
whether the port is RIGHT, and the only thing that says that is the third lane.

**THE SHARP FORM OF IT, and it is the cheapest diagnostic in this section:** a row that is
RED can be a *printer* problem (rule 8 above) and a row that is GREEN can be a
*reachability* problem (a `ref_*` predicate that nothing in the file calls). Measure the
green count BY ROW CLASS, not in aggregate. "31/49" is uninformative; "31/31 non-graph rows
and 0/18 graph rows" names the defect in one sentence.

### 24. `Emit` AND `Halt` BELONG TO BASE's `IO.OP` — A LOCAL `type Emit` IS A DUPLICATE
MEASURED (2026-10-02, cost the renderer/cstyle unit its whole run: the agent died
mid-rename and left a file that would not check). Bend's Base declares
`type IO.OP<-R: Type> is Type:` with constructors `Emit{value: R}` and
`Halt{code, message}`, so the names `Emit` and `Halt` are TAKEN in the flat
constructor namespace. Declaring your own `type Emit is Data:` fails with
    expected : a fresh constructor name (duplicate declaration: Emit)
which reads like a duplicate in YOUR file and is not: `grep -rn "type Emit is Data"`
returns exactly one hit, and `Emit` appears nowhere else in the port. It is not
shadowing either -- an aliased import (`import ./__init__.bend as R`) does not help,
because Base itself is imported unqualified.

THE FIX IS TO ESCAPE THE NAME, not to invent a different concept for it: `Emit_`,
with a comment naming the wall and Base's owner. Same precedent as `@function_` in
`examples/beautiful_mnist.ts`. `bend base 2>/dev/null | grep -n Emit` is the check,
and it costs one second -- do it BEFORE naming a record, not after the file is 2000
lines deep.

### 25. `volatile` IS A RESERVED WORD AND CANNOT BE A FIELD NAME
MEASURED (2026-10-02, three-line probe, ~30 seconds versus a 90-second compile of
the file that hit it). A record field named `volatile` does not even parse:

    type T is Data:
      T{volatile: Bool}
    def rd(t: T) -> Bool: t.volatile
    -- expected : a defined name / observed : t.volatile

There is nothing wrong with the declaration and nothing in Base defines `volatile`
(`bend base --names | grep volatile` is empty), so unlike rule 24 this is the LEXER
holding the name, not a namespace collision. CONFIRMED with the correct spelling
(rule 26) so the two are not confused: `T.mutable(t)` compiles and `T.volatile(t)`
fails with the same message. tinygrad's `ParamArg` has a `volatile` field, so every
port that mirrors that record hits this. ESCAPE IT: `volatile_`, with a comment
naming the reserved word -- same precedent as `Emit_` in rule 24 and `@function_`
in the TS example.

CAUTION, and this cost an hour: this rule was FIRST observed as `t.volatile`
failing, which is really rule 26 wearing a disguise. `volatile_` did not fix that
error, because the syntax was wrong, not the name. When a probe disagrees with a
rule, suspect the rule you have not yet measured.

THE LESSON, which is the real content of both rules: before naming a record after
the Python, check the name is AVAILABLE. Two commands, both about a second:
`bend base --names | tr ',' '\n' | grep -i <name>` for a Base collision (rule 24)
and a three-line probe for a reserved word (this rule). Both were found by an agent
dying mid-file and the coordinator re-deriving the cause from a parse error.

### 26. A FIELD IS READ `Type.field(value)` -- THERE IS NO `value.field` SUGAR
MEASURED (2026-10-02, three-line probes). `def rd(t: T) -> Bool: t.mutable` does
NOT parse:

    expected : a defined name / observed : t.mutable

and it fails identically whether `t` is `+`-affine or plain, so this is not rule 5.
The working spelling is the namespace-qualified projection, which is what the rest
of this port already does everywhere: `T.mutable(t)`, `T.Tensor.u(t)`,
`O.Arena.op(ar, u)`, `S.Dt.cls(d)`. A `match` arm must still name EVERY field
(`case T{mutable, image}: ...`), or it reports "a T pattern with 2 fields".

This is why the tree reads the way it does. `value.field` is the Python/C reflex
and it is silently unavailable; the projection-def idiom is not a style choice, it
is the only spelling. A 1960-line file written in the Python reflex does not merely
have a few errors -- it has one per field read, and each costs a compile cycle to
discover because the checker reports only the FIRST. When a dead agent leaves a
large file that does not check, COUNT the errors in the file's idiom before you
start patching: if it is this mistake, it is a mechanical rewrite (one sed-shaped
pass plus a hand pass for nested ones), not a debugging session.

### 27. THERE IS NO AUTO-GENERATED FIELD PROJECTION AT ALL -- AND RULE 26's `T.mutable(t)`
###     EXAMPLE IS WRONG, THOUGH ITS VERDICT ABOUT `t.mutable` IS RIGHT

MEASURED (2026-10-02, cost `renderer/cstyle.bend` a compile cycle and, more
importantly, would have sent the next agent looking for a Bend feature that does not
exist). Rule 26 says the working spelling is the namespace-qualified projection and
gives `T.mutable(t)` as compiling. **For a LOCALLY-DECLARED record it does not
compile.** The three-line probe, run one line at a time because the checker reports
only the first:

```bend
import Base
type T is Data:
  T{mutable: Bool}
def rd(t: T) -> Bool: t.mutable
#| - expected : a defined name
#| - observed : t.mutable
def rd2(t: T) -> Bool: T.mutable(t)
#| - expected : a defined name
#| - observed : T.mutable          <-- rule 26 says this COMPILES
```

And the rule-25 escape does not help either: `T2{volatile_: Bool}` with
`T2.volatile_(t)` is refused the same way. So rule 26's VERDICT (`t.mutable` is
unavailable) is right and its SPELLING is not, and the reason the tree looks like
rule 26 says is that **every `Type.field` reader in the port is a hand-written
`def`**. `ops.bend` declares `Arena.op` / `Arena.src` / `Found.ar` / `Node.tag`;
`spec.bend` declares `Dt.bits` / `Dt.cls` / `Sp.shape`; `cstyle.bend` declares
twenty-two of them for its own four records. There is no record in the tree whose
reader is generated, and there cannot be one: the reader needs a `match` that names
EVERY field, and the compiler does not know the field list at the point a reader
would be needed.

THE CORRECT RULE, THEN: a field is read `Type.field(value)` **and `def
Type.field(x: Type) -> T: match x: case Type{f1, f2, ..., fn}: fi` is written out
by hand for every field.** Cost: two lines per field, and renaming a field is one
edit per reader. What it buys back: the reader is a real def, so it is nameable in a
comment, mutable in a mutation, and identical in shape whether the record is local or
imported.

THE PART THAT HAD BEEN MISREAD FOR TWO RULES: "the only spelling is
`Type.field(value)`" is true of the CALL and false of the DEFINITION. Rule 24
(`Emit` is Base's), rule 25 (`volatile` is reserved) and rule 26 (`value.field`) all
described the call site. This one describes the declaration, and it is the reason
the same three escapes (`Emit_`, `volatile_`, and twenty-two `Type.field` readers)
appear together at the top of a file that touches four local records.

### 28. A `Bool` PARAMETER DOES NOT MAKE A TWO-DEF SPLIT OF ONE RECURSION LEGAL -- IT IS
###     STILL MUTUAL RECURSION, AND THE COUNTDOWN MUST BE THE REMAINING COUNT

MEASURED (2026-10-02) building HIP's and CUDA's prefix clauses, which are "emit
clause 0, then 1, then 2, ... up to a per-device count". The natural shape is a
pair, because a `match` may not scrutinise a computed value:

```
def go(..., k, acc): at(U32.is_eq(k, count), ..., k, acc)     # compute the Bool
def at(same, ..., k, acc): match same: ... go(..., k+1, ...)    # consume the Bool
```

That is mutual recursion and it is refused -- but the FIRST error is the misleading
one, `expected : a filled definition ... observed : go`, because `go` is declared
below `at`. Fix the order and the mutual-recursion refusal arrives. Convention 9 in
`renderer/__init__.bend` already says the self-call must live inside the def that
owns the `match`; this is the measured consequence, and it forces ONE def:

```
def dev_prefix.go(rem: Nat, ..., k: U32, acc: ...) -> ...:
  match rem:
    case 0n: acc
    case 1n+m: dev_prefix.go(m, ..., U32.add(k, 1), add(acc, clause(..., k)))
```

**THE COUNTDOWN IS THE REMAINING CLAUSE COUNT AND NOT THE LOOP INDEX**, and that is
the whole shape rather than a style choice: `k` only GROWS, the decrease checker
reads the first argument that shrinks, and so a `k`-first signature fails with
`expected : a decreasing self-call`. Passing `count - k` in first and incrementing
`k` inside is what makes one def enough. It also happens to read better: `rem` is the
question ("is there anything left?") and `k` is bookkeeping.

### 29. `+` ON A LATER PARAMETER DOES NOT DISTURB THE DECREASE CHECK ON THE FIRST ONE

MEASURED (2026-10-02), same def. The self-call above passes `rem` (shrinks, first),
then `dev`, `u`, `vecs`, `ockl`, `ocml`, `cdna4`, `k` and `acc`. Three of those are
read twice in the one arm and need `+`: `cdna4` (once in `prefix_clause`, once in the
self-call) and `k` (once in the self-call's arithmetic, once in `prefix_clause`).
`+` on them is accepted and `ALL PROOFS CHECK` holds.

This is worth one line because the fuel sections above say twice that "marking either
`+` breaks the check -- a reusable binder stops counting as a subterm". That is true
**only for the binder that does the shrinking**. A `+` on the SEVENTH argument of a
nine-argument self-call cannot affect the decrease, and refusing to add it (on the
theory that it might) makes the arm impossible.

### 30. `+` ON A `U32` IS FREE, AND A `Nat` `match` WITH `case 0n:` THEN `case 1n+m:` IS
###     THE WHOLE COUNTDOWN

MEASURED (2026-10-02), same def, and both halves of it are things the sections above
state only in fragments. `+k: U32` is accepted: `U32` is `Data`, so a `+` costs a
reference count and nothing else (`rand.bend`'s rule 4 already said this for `F32`).
And `match rem: case 0n: acc; case 1n+m: ...` is exhaustive and correct -- `1n+p` IS
a first-match prefix (the correction section's point), and it is correct HERE
precisely because the `0n` arm is listed first, so the prefix pattern never sees a
zero. The prefix semantics are not a hazard in a countdown; they are a hazard in a
`match` whose arms are *intended* to be disjoint, which is the only place the
correction actually applies.

### 31. NO LIST COMPREHENSIONS -- BUT CLOSURES EXIST AND `List` IS FULLY ERGONOMIC
MEASURED (2026-10-02, five probes). Three facts, and the third one retracts a
standing instruction in the agent brief.

1. **THERE IS NO COMPREHENSION SYNTAX.** `[U32.add(x, 1) for x in xs]` fails with
       expected : a term (the keyword 'for' cannot head one)
   and `[x for x in xs() if p(x)]` likewise. The guide never mentions the word.
   CONSEQUENCE: a Python comprehension is NOT a source of our line-count excess,
   because the Bend equivalent is also one call -- `List.map(~A, ~B, f, xs)` is the
   same length as `[f(x) for x in xs]`. Anyone blaming comprehensions for the 2.28x
   is looking in the wrong place.
2. **CLOSURES AND DEF REFERENCES BOTH WORK.** `x => U32.add(x, 1)` is a closure;
   a plain def may be passed as a function value and called as many times as you
   like (the guide is explicit: "unlike a closure, may be called as many times as").
   Multi-arg function types are curried: `U32 -> U32 -> U32`.
3. **THE ARITY QUANTIFIER IS HOW YOU CALL THE `List` FOLDS.** A `List` is
   `List<a, A>` where `a` is the arity, so a cons list is `List<&2, U32>` and you
   pass the arity to the fold:
       List.filter(~U32, big, xs)                     -- f is 1-ary, the ELEMENT
       List.foldl(~&2, ~U32, ~U32, addn, xs, 0)       -- f is 2-ary, (acc, elem)
       List.any(~&2, ~U32, big, xs)
   All three compile. Note `List.map` takes `List<A>` (whole-list element type) and
   so infers `&1` unless you pass the arity explicitly -- that inference is what
   makes a map over a cons list look like it "lost" a level.

**WHAT THIS RETRACTS.** The agent brief has said for days that rule tables must be
copyable `Data` "so there are no closures". That was my assumption, not a
measurement, and it is wrong: closures and def references both work. The rule
tables are still plain `Data` -- copyable, gateable, mutation-testable, and a
closure per rule would make a table unprintable -- but the REASON is now the gate
and the table, not a language limitation. Do not tell the next agent that Bend
lacks closures; it has them. The real cost of our line count is elsewhere: one
hand-written reader per record field (3,499 of them), ~81 duplicated dispatch
scans, ~1,316 two-arm `Maybe` reads, and comment density -- and a share of the
`.put`/`.go` helper proliferation is self-inflicted when `List.foldl` with a
top-level 2-ary def would do.

### 32. `List.foldl` REPLACES THE HAND-ROLLED `.go` ACCUMULATOR PAIR — WITH ONE TRAP
MEASURED (2026-10-02), converting four folds in `nn/state.bend` and four in
`nn/__init__.bend`. Both gates came back BYTE-IDENTICAL to the pre-rewrite output
(14 and 24 rows, zero `False`), so this is behaviour-preserving and not a hope.

    # BEFORE -- four lines and a .go name per fold
    def sd_keys.go(es: List<&2, Ent>, acc: String) -> String:
      match es:
        case Nil{}: acc
        case e <> t: sd_keys.go(t, String.concat([acc, Ent.k(e), ","]))
    def sd_keys(es: List<&2, Ent>) -> String: sd_keys.go(es, "")

    # AFTER -- one line, CLOSED step inlined as a lambda
    def sd_keys(es: List<&2, Ent>) -> String:
      List.foldl(~&2, ~Ent, ~String,
        (acc: String) => (e: Ent) => String.concat([acc, Ent.k(e), ","]), es, "")

THE TRAP, and it cost two cycles: **the third `~` argument is the ACCUMULATOR's type,
not the element's.** `List.foldl(~a, ~A, ~B, f, xs, acc)` has `f: B -> A -> B`, so
for a `List<&2, Ent>` folded into a `List<&2, Ent>` you write `~List<&2, Ent>` as
`~B`, not `~Ent`. The error is precise and points at the `f`:
    expected : @_:Ent -> @_:Ent -> Ent
    observed : @acc:List<&2, Ent> -> @e:Ent -> List<&2, Ent>
Note how it names the types it wanted -- `Ent -> Ent -> Ent`, i.e. it inferred `~B`
from the step's RETURN type and then wanted the parameter to match.

THE OTHER TRAP: **a `~` template position must be CLOSED.** A lambda that captures a
runtime value is refused:
    expected : a template applied to closed ~ arguments
    (sep is a variable here, not comptime: pass it at run time)
So a step that needs a runtime parameter must be a TOP-LEVEL def taking it as an
ordinary argument, and the fold is called with that def. That is the shape to reach
for when a fold is parameterised, and `nn/state.bend`'s `sd_update.step` is the
worked example. A top-level def at a `~` position is called freely (rule 31), so
there is no reason to prefer a closure when you need a parameter.

WHAT DOES NOT CONVERT: a fold whose accumulator is PREPENDED and then reversed. The
reverse has to stay outside the fold (`get_parameters`), because moving it into the
step reverses once per element -- which is exactly the `List.append`/`List.reverse`
pairing rule from the wgsl unit, in a new costume. And a fold over an ARENA cannot
use `List.foldl` at all: the arena is affine and threaded with `+`, which no `List`
combinator threads.

FILE SIZE, for the record: `nn/state.bend` 834 -> 832 and `nn/__init__.bend` 845 ->
834, i.e. 13 lines from 8 folds, and it scales: the tree has ~97 hand-rolled `.go`/
`.step` folds of this shape and 3,499 one-line field readers.

## EIGHT MORE RULES, MEASURED 2026-10-02 PORTING `tinygrad/function.py`

Appended, not edited. All eight are Bend 2.0.34 or substrate facts, each one found
while writing a 1946-line port of a 113-line Python file -- which is itself the
headline: **the ratio in this tree is 17:1 for a file that is four predicates and a
rule table**, and the reason is that every one of these rules turns a two-line Python
statement into a three-def chain. Each rule below cost at least one compile cycle.

### 1. A `Bool` PARAMETER IS AFFINE TOO -- `+hit: Bool` is ACCEPTED AND IS OFTEN
###    WHAT YOU WANT

`Fired.of(hit, Bool.pick(FnCtx, hit, ...))` is `expected : hit / observed : hit
(consumed more than once)`. `+hit: Bool` fixes it. Every rule in this file says
"`+` is refused on a `U32`", and this is the half that is easy to forget: a `Bool` is
`Data`, so it takes `+`, and a flag that is read once to decide and once to report
(the "did this rule fire" flag) is the commonest two-read in a rule table.

### 2. `go`/`put` IS NOT A `.of` SPLIT: IT IS MUTUAL RECURSION, AND A LIST-TAIL FOLD
###    WITH A HEAD THAT IS ALSO THE ACCUMULATOR NEEDS THE RECORD FORM

Writing a fold whose STEP takes the head and whose walk takes the tail gives
`go -> put -> go`, which is refused as mutual recursion (`expected : a filled
definition (an unfilled law is a dead claim)`, reported at the LATER def). The
working shape is ONE recursive def whose arm calls a leaf:

    def of(xs: List<&2, U32>, +d: Dedup) -> Dedup:
      match xs:
        case Nil{}: d
        case x <> t: of(t, put(x, d))          # x read ONCE, in the call
    def put(x: U32, +d: Dedup) -> Dedup: ...    # x read once more, here

so the head binder is read once per def rather than twice in one def. Measured on a
dedup fold; the same shape is `sz.rows`'s `.step`, and the `.of`/`.put` naming that
suggests otherwise costs a cycle.

### 3. `T.tn_len` IS `shape[0]`, NOT `numel` -- AND IT ANSWERS A `Sint`'s ARENA
###    INDEX, NOT ITS VALUE

`tensor.bend`'s `tn_len.first` is `Some{O.Sint.u(d)}`. So `tn_len` answers the
ARENA INDEX of a `SInt` node, which is `0` for every concrete `SI{4}` and therefore
prints as a zero size for every one-dimensional fixture. `max_numel` is a PRODUCT of
the shape and has to be folded by the caller. This bit a gate that printed
`size=0` on a buffer whose shape is `(4,)` -- and the row that would have caught it
was the one printing the SHAPE, not the one printing the size.

### 4. `H.dedup_u32` BUILDS ITS ANSWER IN REVERSE, AND NO ROW IN THE TREE NOTICES

`H.dedup_u32.put` is `case False{}: h <> r` -- a PREPEND -- and `dedup_u32(xs)` is
`case h <> t: dedup_u32.go(h, dedup_u32(t))`, so the head is processed LAST. Measured:
`H.dedup_u32([1, 7, 1])` answers `[7, 1]`. For a membership SET that is
indistinguishable from correct and no existing row could see it. For an ORDERED
dedup -- `call_uops` in `function.py`, whose ORDER IS THE SLOT NUMBERING because
`subs = {x: x.param_like(i) for i,x in enumerate(call_uops)}` -- it is a silent
answer-value inversion. **The general form: `dedup` as a SET is order-blind and
`dedup` as a LIST is not, so a caller that needs the order must check which one the
helper is.** Reported, not fixed (`helpers.bend` was read-only to that unit); the
caller carries a local append-based dedup with the reason in its header.

### 5. `T.tn_dims` ANSWERS A SHAPE AND `List.is_empty` ON IT ANSWERS `_shape == ()`,
###    WHICH IS THE LAST CONJUNCT OF `UOp.is_variable` -- so THE FOLD CAN BE A
###    GATED CONJUNCT AND NOT JUST A READER

`is_implicit_storage`'s `x.is_variable` is `op is PARAM and arg is ParamArg and
vmin_vmax is not None and addrspace is ALU and _shape == ()`. Four of the five are
`match` arms on `Op` and `Arg`; the fifth needs the fold. Ported as
`fn_scalar(f) = List.is_empty(&2, O.Sint, tn_dims(tn_new(ar, u)))` with the
`Maybe`'s `None` arm answering `False{}` -- and that is worth saying: **an UNANSWERED
node is not a scalar**, so the total wrapper needs no sentinel and the row that
separates the shape conjunct from the other three (`iis_var_1d`: same node, `size=4`)
is the only one that can see it.

### 6. `List.drop(&2, U32, xs, U32.to_nat(n))` IS A POSITIONAL SLICE, AND A HAND-
###    WRITTEN FILTER THAT COMPARES THE COUNT AGAINST THE NODE INDEX IS WRONG IN A
###    DIRECTION NO COUNT ROW SEES

`function.py:84` is `[x for x in call_uops[num_explicit:] if ...]` where
`num_explicit` is a LENGTH. The first port wrote `U32.is_ge(u, num_explicit)` -- a
count against a POSITION -- which on a one-element list answers `1/1` where the
slice answers `1/0`, and on a two-element list answers `2/2`. Two of the three rows
moved and one did not, which is the signature. **A slice is `List.drop`, and the row
that pins it prints BOTH ends of the range** (`imp_tail=1/0`), because the two ends
disagree exactly when the slice is a count.

### 7. A `.of` LEAF THAT IS ONLY EVER CALLED FROM ONE PLACE STILL COSTS A ROW, AND
###    THE HONEST MOVE IS TO DELETE IT WHEN THE MERGE IS CHEAP

Half of this file's LOC is `.of`/`.of2`/`.of3` chains that exist only because a
`U32` cannot be read twice in one expression. Two of them (`fn_imp_row.of2`,
`pctx_table.put`) were written, found to be a single extra call, and folded back
into their caller. **A driver that adds a layer should ask whether the layer is
load-bearing before it is commented**, because a commented no-op layer is worse than
no layer: it reads as a decision and is not one.

### 8. THE `Data` RECORD FOR "A FOLD THAT ANSWERS A LIST AND A FACT ABOUT IT" IS
###    NOW FIVE INSTANCES IN ONE FILE, AND THAT IS NOT A COINCIDENCE

`Dedup{r}`, `Ren{n, inv, acc}`, `Imp{n, rows}`, `BsSt{h, self, acc}`,
`Ix{i, acc}`, `FnSt{ar, start}`, `FnCtx{us, inv, start, added, slot}`. Each one
exists because a counter or a flag had to travel beside a list and a `U32` cannot
carry it twice. **The record count of a Bend port is a direct count of its
"two things at once" sites, and it is the number to look at when a file feels
expensive** -- this file is 113 Python lines and 1946 Bend lines and roughly a third
of the second number is these records plus the readers that carry them.

## SIX MORE RULES, MEASURED 2026-10-02 WRITING `mixin/reduce.bend` (items continue from 31)

Appended, not edited. All six are Bend 2.0.34 or gate facts. Four of them cost a
compile cycle and the last two are the kind that cost a whole table.

### 1. THE `.of` SPLIT IS REQUIRED AT **EVERY** SCRUTINEE POSITION, NOT ONLY AT THE TOP OF A BODY
Rule 2 (and its four restatements) is always written as "a `def f(x)` whose body
is `match g(x):`". Here the scrutinee is a `case` ARM's `match`, and it is still
refused:

    def rc_arg.put(got: Bool, +r: RcRed, +ar: O.Arena, u: U32) -> RcRed:
      match got:                              # a PARAMETER -- legal
        case True{}: r
        case _: match O.Arena.arg(ar, u):      #| - message : a parameter or field scrutinee
          case O.AReduce{rop, num_axes}: ...

`got` is a parameter and the outer match is legal, so the error reads as if it were
about the *nesting*. It is not: it is about the inner scrutinee, and the fix is the
same two-def `rc_arg.of(got, a, r)` / `rc_arg.put(got, r, ar, u)` every other `.of`
split in the port uses. **A `match` in the catch-all arm of another `match` is a
scrutinee position like any other; the `.of` leaf has to be a named def, and that
def must be declared immediately above.**

### 2. A PATTERN BINDER THAT SHADOWS A **FIELD NAME** IS REPORTED AS AN ARITY ERROR
The recorded "a pattern binder must not shadow a def name" rule names the wrong
thing in the message. Here the shadow is a FIELD of the record being CONSTRUCTED,
no def of that name exists, and the error is the arity message:

    def rc_arg.of(got: Bool, +a: O.Arg, +r: RcRed) -> RcRed:
      match got:
        case True{}: r
        case _: match a:
          case O.AReduce{rop, num_axes}: RcRed{found, True{}, rop, num_axes}
                                          #| - expected : RcRed with 3 fields
                                          #| - observed : RcRed{found, True{}, rop, num_axes}

`found` was bound by an enclosing `case RcRed{...}` and used as the first FIELD of a
four-argument literal of the same record; the checker counts the literal's
arguments as three because the binder is not in scope after the `match`. Renaming
the field (`ok`) fixes it in one edit, and the `Data` union is what makes the
collision possible at all. **The tell is a `X pattern with N fields` error on a
literal whose arity is visibly correct: look for a binder of the same name in an
enclosing arm before counting arguments.**

### 3. `+` ON A `U32` THAT IS THE **FIRST** ARGUMENT OF A LIST-TAIL SELF-CALL CHECKS
The fuel sections say "marking either `+` breaks the check -- a reusable binder stops
counting as a subterm". That is exactly and only true of **the binder that does the
shrinking**, and rule 29 already showed `+` on the SEVENTH of nine. This is the
other end of the same rule, measured on a fold whose first parameter is a `U32` and
whose shrink is in the SECOND:

    def rc_axs.go(+td: U32, xs: List<&2, Ax>, +acc: List<&2, U32>) -> List<&2, U32>:
      match xs:
        case Nil{}: acc
        case +a <> t: rc_axs.go(td, t, List.append(&2, U32, acc,
          [M.mo_resolve(Ax.neg(a), Ax.dim(a), td)]))

`ALL PROOFS CHECK`, with `td` read twice in one arm (once in `mo_resolve`, once in
the self-call) and `+a` on the binder. Without `+td` it is
`expected : td / observed : td (consumed more than once)`. So the rule to carry is
one clause, not a position: **the shrinking argument may not be `+`; nothing else
may not.** (`+td: U32` also confirms rand.bend's rule 30 from the other side -- a
`U32` parameter takes `+` freely.)

### 4. A GATE **COLUMN** THAT IS CONSTANT OVER THE WHOLE SUITE IS A COLUMN NO MUTATION CAN MOVE
`uop/weak.bend` recorded "a gate that never calls the function under repair is
blind"; the test for that is one grep. The same blindness has a COLUMN-shaped form
and it is cheaper to miss, because the column is present, non-empty and plausible on
every row:

    red=<ROP>/<num_axes>

Every row of `reduce.bend` printed `red=.../1` or `red=.../0` until one fixture was
added with a DIFFERENT value in it (`axis=(0,1)`, giving `red=ADD/2`), so the
`num_axes` half of the column was a constant for the whole first mutation run and
no mutation in the file could move it -- `num_axes` is built in `tensor.bend`. **The
test is one line: does any row's expectation DIFFER from every other row's, in this
column?** If not, the column is decoration and should either be dropped or given a
fixture. (Same family as the `nd=` count row in `mixin/render.py`'s `switch_over`,
which is why that file needed two rows reading the same slot.)

### 5. A CHAINED REDUCE SEPARATES FIRST-WINS FROM LAST-WINS **ONLY IF THE TWO OPS DIFFER**
The brief's standing trap is "if your table has no node that TWO rules both claim,
a first-wins-vs-conjunction bug moves NOTHING". Here the collision is in a SEARCH,
not a rule table, and the fixture that resolves it is narrower than it looks:

    f.any(axis=0).all(axis=0)     -> reduce ends MAX/1 and MUL/1   SEPARATES
    f.sum(axis=0).sum(axis=0)     -> reduce ends ADD/1 and ADD/1   INVISIBLE

Both graphs hold two REDUCEs, and in both the search walks the toposort in the same
order, but the two `red=` answers are identical in the second case, so the policy is
unobservable. MEASURED: inverting the walk's "already found" guard moved 22 rows for
`any().all()` and the same mutation on `sum().sum()` would have moved none. **Pick
the chained fixture so the two reduces have different OPS, not merely the same
count** -- and note that this is the same reason `log_softmax`'s `e`/`m` choice is
unfalsifiable in `mixin/op.bend`'s M8: graph-isomorphic programs, not wrong ones.

### 6. A MUTATION DESCRIBED AS "DROP THE GUARD" MAY BE SOMETHING ELSE ENTIRELY, AND ONLY THE VALUE SAYS WHICH
The harness reports the rows a mutation moved, by name. Two mutations reported the
same twenty-two rows and were assumed to be testing the same thing:

    M10  read `AAllred` instead of `AReduce`   -> 22 rows, every one to `red=none`
    M18  INVERT the `ok` guard (True->False)   -> 22 rows, every one to `red=none`

M18 was described as "drop the guard so the LAST reduce wins", and the description
was wrong: inverting the guard makes the accumulator never record anything at all,
so it is a second copy of M10 rather than a first-wins test. The real
first-wins-vs-last-wins mutation is to delete the `match got:` line entirely, and
that one moves exactly ONE row (`chain_any`, rule 5). **Print the moved row's
VALUE, not just its name, before writing the mutation's description** -- the two
questions "which rows" and "what they became" have different answers, and only the
second one distinguishes three mutations that share the first.

## NINE MORE RULES, MEASURED 2026-10-02 WRITING `renderer/tc_ptx.bend`

Appended, not edited. Bend 2.0.34. Each one cost a wrong answer that typechecked
and ran; every reproducer is in `.agents/slop/probe-cc.bend`,
`.agents/slop/probe-ur.bend` or `.agents/slop/probe-tcptx.bend`.

### 1. A COUNTDOWN ARM MAY NOT SO MUCH AS READ ITS OWN FUEL -- AND THE ESCAPE IS A `+U32` THAT GROWS

`List.append(&2, U32, ur(m), [U32.sub(U32.from_nat(k), 1)])` is REFUSED with
`expected : m / observed : m (consumed more than once)`, reported at the
`case 1n+m:` PATTERN so it reads like a duplicated binder. It is not: `m` is
read exactly once. The arm may not READ `k` at all -- `List.append(&2, U32,
ur(m), [U32.from_nat(k)])` fails the same way, and so does binding `k` to a
local FIRST. The working shape threads the element as a `+U32` that GROWS from
zero and CONSES it:

```
def ur(k: Nat, +i: U32) -> List<&2, U32>:
  match k:
    case 0n : Nil{}
    case 1n+m:
      xs = ur(m, U32.add(i, 1))
      List.append(&2, U32, [i], xs)
```

`+` on `i` is required (it is read in the recursive arm and in the body), and
that does NOT break the decrease check -- rule 29 already says so, and this is
the second instance. NOTE THE DIRECTION: appending `[i]` instead of consing it
gives `2,1,0`, because the recursion builds the tail first. `ur(3n, 0)` is the
reproducer and prints `0,1,2` when correct.

### 2. `List.append(A, R, rec(t), [x])` IS `reverse`, NOT A BUG -- IT IS `rec(t) ++ [x]`

The ledger has this ("a recursive map/filter that writes `append(fold(t),
[head])` returns every list in REVERSE"), and it was still walked into, so the
reproducer is now three lines and the shape is pinned:

```
def fa(+xs: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}   : Nil{}
    case c <> +t : List.append(&2, U32, fa(t), [c])

fa([2,1,6])   ==> 6,1,2      # reverse, BOTH lanes
[c] ++ fa(t)  ==> 2,1,6      # correct
```

Two measurements that stop the misdiagnosis. It is **NOT** the double self-call
(`Bool.pick(..., fa(t) wrapped, fa(t))` fails the same way with one call), and it
is **NOT** a lazy-argument ordering bug (binding the self-call to a local first
changes nothing). And `--check-only` is clean throughout. The only tell is that
the list is the right length with the right elements.

### 3. `U32.shln(a, n)` IS `a << n` -- BUT `U32.shl(a)` IS `a << 1`, SO `shln(a, 0n) = a`

Already stated in section 2 ("`U32.shl`/`shr` shift by one"), and the trap is
that `shln` and `shl` are different by one, so a `(bit << 2)` written as
`U32.shln(bit, U32.to_nat(bit))` -- "shift by the bit" -- silently becomes
`bit << bit`. Measured: a packed-coordinate constructor of that shape printed
`k0` for what should be `k1`, and 26 distinct gate rows moved. There is no
arithmetic error to look for; the encoding was just wrong at one place and
right everywhere else.

### 4. A U32 SENTINEL FOR A PYTHON `default=-1` MUST NOT BE `0xffffffff` WHEN THE FOLD IS `max`

`1 + max([...], default=-1)` ported as `U32.add(fold(cs, 0xffffffff), 1)` where
`fold` starts at the sentinel and takes `U32.max(bit, best)`, is a silent
zero: `0xffffffff` is the largest `U32`, so it WINS every comparison and the
maximum is never updated. Measured: `axis_coords()` came back EMPTY and
`dims` printed `1,1,1` for all sixteen tables, with every table-length row
still green. The fix needs no sentinel and no wrap -- carry `bit + 1` as the
contribution, so "nothing on this axis" is 0 and the maximum IS the count:

```
def cd_cnt1(+cs, +ax, best) -> U32:  # best starts at 0
  ... U32.max(U32.add(cd_bit(c), 1), best) ...
def cd_cnt(+cs, ax) -> U32: cd_cnt1(cs, ax, 0)
```

GENERALISE IT: **a Python sentinel of `-1`/`0`/`None` becomes a U32 whose
`max`/`min`/`or` behaviour under the sentinel's fold has to be re-derived, not
translated.** A count that should be positive and prints `0` is the symptom.

### 5. `sub(b) <= sub(a)` IS `sub(a, b)` WITH THE ARGUMENTS BACKWARDS, AND `<=` READS THE OTHER WAY

Writing a subset helper as `sub(a, b) -> every element of b is in a` and then
translating `own <= all` as `sub(own, all)` inverts the assertion. Measured:
rdna3's `__post_init__` `cover.mk` printed `False` with every other row green,
because rdna3's A fragment carries the FOREIGN bit `n0`, which is in `all` and
in the mn-coords but not in `own(mk)` -- precisely the case the assertion exists
for. The `f(1) <= f(2)` reading is `sub(f(2), f(1))`.

### 6. A `match` ON A `String` NEEDS THE ARM ORDER OF THE LITERAL, AND A MISSING `"gfx942"` ARM IS DEAD CODE

A `match nm: case "gfx950": ... case "gfx1200": ... case "gfx1201": ... case _:
...` where `nm` is `"gfx942"` answers the CATCH-ALL, not a missing arm -- and
the checker's exhaustiveness is happy because the element type is not closed.
So a dict with four keys and a default ports to FOUR literal arms plus the
catch-all, and dropping one key silently reroutes that key to the default. The
row that finds it is the one whose value differs from the default's.

### 7. A GATE'S ORACLE MUST REPRODUCE `IO.print`'s OWN NEWLINE, OR THE LAST ROW NEVER MATCHES

The Bend side builds the whole table as one `String` and prints it once, so
`IO.print` appends a newline AFTER the last row's own. An oracle that
`sys.stdout.write("".join(rows))` is one byte short and every diff ends with a
spurious `279d278`. `wgsl-oracle.py` gets this right for free because it
`print`s one row at a time. Either `sys.stdout.write(rows() + "\n")` on the
oracle side or `String.trim_end` on the Bend side; do not leave it to a
reviewer's `diff | head`.

### 8. TWO SELF-CALLS IN ONE ARM ARE LEGAL WHEN EVERY SHARED ARGUMENT IS `+`

`Bool.pick(List<&2, U32>, is_eq, List.append(&2, U32, f(ax, t), [c]), f(ax, t))`
compiles and runs once `ax` is `+`. Measured; the failure when it does not is
`expected : ax / observed : ax (consumed more than once)`, which names the
SHARED argument and not the duplication. This is the shape a filter needs, and
rule 3's "a `Maybe` binder is the same restriction" does not extend to it.

### 9. `do` IS A RESERVED WORD AND CANNOT BE A RECORD FIELD

`Tc{di: S.Dt, do: S.Dt, ...}` is `expected : a name (got the keyword 'do')`,
which points at the record declaration and reads like a duplicate field. Same
family as rules 24 and 25 (`Emit`, `volatile`): the name is TAKEN, the fix is
to escape it (`dou`), and the check is `bend base --names | tr ',' '\n' |
grep <name>` before naming a record after a Python attribute. tinygrad's
`TensorCore` has `dtype_out`; the port spells it `dou` because the whole file
elsewhere says `di`/`dou` and the asymmetry is worth the escape.

---

## NINE MORE RULES, MEASURED 2026-10-02 WRITING `nn/onnx.bend`

Appended, not edited, continuing the count from 31. All nine are Bend 2.0.34 or
substrate facts; the file is `tinybendygrad/nn/onnx.bend`, its gate is 123 rows
diffed byte-for-byte against a CPython oracle that calls tinygrad's own tables
AND its own nested helpers, and its mutation table is 21 entries of which ONE
moves nothing (and that one is the control) and one more is a documented BLIND
SPOT.

### 1. `Pair` IS A BASE CONSTRUCTOR, SO A TWO-FIELD `Data` RECORD NEEDS A NEW NAME

Rule 24 (`Emit`/`Halt` are Base's) is not the only reserved name in this port.
`type Pair is Data:` is `expected : a fresh name (duplicate declaration: Pair)`,
and `grep` over `base.bend` finds no `Pair` because it is a CONSTRUCTOR, not a
def. The escape is the same shape as `Emit_` and `volatile_`: `Hal` (halves),
with the owner named at the declaration. **The lesson generalises: before naming
a record after the Python, the check is a three-line probe that declares AND
constructs it -- a name can be free in `bend base --names` and taken anyway.**

### 2. A UNION CONSTRUCTOR IS NOT A TYPE, SO A READER FOR ONE ARM CANNOT BE WRITTEN

Rule 27 says a field is read `Type.field(value)` with a hand-written reader. It
does not say what happens when the type is a multi-constructor `Data` UNION:

```
type A is Data:  Aa{v: U32}  Ab{nm: String}
def Aa.v(a: Aa) -> U32: ...     #| - expected : a defined name / observed : Aa
def Aa.v(a: A) -> U32: ...       #| - expected : cases for Aa, Ab, ...
```

The namespace `Aa.v` is fine; the PARAMETER TYPE `Aa` is not a name. So a
payload reader for one arm must take the WHOLE union and match all the arms to
stay exhaustive, and a nested `match` on the binder is refused on top of that
(rule `divandmod` 1). Forty lines of ladder for five payloads with no caller is
padding, and the honest answer is the TAG reader plus a comment recording the
measurement. **`AVal` in `nn/onnx.bend` is the worked example: eight constructors,
one tag reader, no payload readers.**

### 3. A FOLD OVER A FUNCTION PARAMETER IS IMPOSSIBLE, SO A TABLE ROW IS AN EXPLICIT LITERAL

```
def m.go(cs, f: U32 -> String, acc): m.go(t, f, List.append(.., [f(c)]))
#| - expected : f / observed : f (consumed more than once)
def m.go(cs, +f: U32 -> String, acc): ...
#| - expected : Data / observed : Type    (a function value is `Type`)
```

`+` is refused on a function value because a function in a datatype field forces
`Type` -- the same fact as the `List.sort` comparator note. **So "project every
cell of this table" cannot be one generic fold; it is a LITERAL LIST of the
projections, joined once.** The cost is that the code appears twice (once in the
driving list, once in the row) and the mutation table needs an entry for exactly
that. `List.foldl(~&2, ~U32, ~U32, f, xs, acc)` is unaffected -- only folds that
TAKE the function as a parameter are.

### 4. A `U32` LITERAL ARM LADDER MUST BE IN DESCENDING ORDER

The recorded form ("`case 1:` claims every successor") is true and the trap is
avoidable by ordering: listed high-to-low, `case 16:` claims 16..max and every
lower arm below it still fires on its own value. Listed low-to-high, the second
arm is dead. Measured on a thirteen-entry `OnnxDataType` table, codes `1,2,3,4,5,
6,7,9,10,11,12,13,16`, all with `Some{...}` payloads. **Every numeric ladder in
this port should be written descending; it costs nothing and it removes the only
silent failure the recorded rule describes.**

### 5. `H.I64` HAS NO `Word`, SO `floor(x/2)` IS HAND-WRITTEN -- AND THE LOW WORD'S FILL COMES FROM THE HIGH WORD

`U32.shrn` is LOGICAL, so `floor(x/2)` on a 64-bit word is not two shifts. The
correct identities, from "bit i of the result is bit i+1 of x":

```
lo' = (lo >>> 1) | ((hi & 1) << 31)      # UNCONDITIONAL -- a bit SHUFFLE
hi' = (hi >>> 1) | (sign ? 1<<31 : 0)    # the ONLY sign extension
```

**THREE bugs, all `ALL PROOFS CHECK`, and `-5` answers correctly under all three**
(its `lo & 1` is 1) so only an EVEN negative exposes them: the fill not
conditional on the sign (`floor(3/2)` -> `-2147483647`); the low word's fill
taken from its own bit 0; the high word's fill taken from the low word's bit 0.
The general lesson is the existing "an even fixture hides an odd defect" family in
a new place: **when a word is split across two cells, the cell you did not think
about is the one that is wrong, and a fixture at the value where both cells agree
is not a fixture.**

### 6. `helpers.bend`'s `i64_add` AND `i64_sub` NEITHER CARRY NOR BORROW -- REPORTED, NOT FIXED

`H.i64_sub(a, b) = i64_of_hi_lo(sub(hi32(a), hi32(b)), sub(lo32(a), lo32(b)))`
subtracts the two words INDEPENDENTLY. MEASURED against CPython:

| case | CPython | `H.i64_sub` / `H.i64_add` |
| --- | --- | --- |
| `5 - 7` | `4294967295:4294967294` | `0:4294967294` -- no borrow |
| `1 - (-1)` | `0:2` | `1:2` -- no borrow |
| `(-1) + (-1)` | `4294967295:4294967294` | `4294967294:4294967294` -- no carry |
| `(-1) + 1` | `0:0` | `4294967295:0` -- no carry |

`H.i64_cmp` / `i64_le` ARE correct -- they compare the signs first -- so only the
arithmetic is affected, and the defect is invisible on every pair whose low words
do not borrow. `helpers.bend:1238-1243`. `nn/onnx.bend` carries a local
`onx_isub` with the owner lines named; **`i64_add` has the same defect and NO
caller in this port yet**, so the two are one report and one of them is currently
latent. Anything downstream that adds or subtracts `H.I64` values across a word
boundary is affected, and the file's own `_min_max` consumers are the obvious
next ones.

### 7. A FIRST-WINS `Any` GUARD INSIDE AN ELIGIBILITY FOLD IS A BUG THE FIX MAKES WORSE

`_select_op`'s `{impl_opset.version: impl_fxn for impl_opset, impl_fxn in
impl.items() if domain == required.domain and version <= required.version}` then
`eligible_ops[max(...)]` is a fold that must KEEP every eligible row. Two
plausible ports, both wrong, both `ALL PROOFS CHECK`:
- `eligible and not found_yet` -- FIRST-WINS. `Softmax` at opset 13 answers
  `softmax_1` instead of `softmax_13`.
- `eligible and found_yet` -- ANSWER `None` for every versioned op, because
  eligibility now requires a hit to already exist.

The correct shape has NO accumulator term in the eligibility test at all: it is
a property of ONE candidate against the required opset. **The tell is an
accumulator `Bool` that appears in the PREDICATE rather than in the result --
`found_yet` belongs in `hit`, never in `eligible`.**

### 8. A COUNT ROW AND THE TABLE IT COUNTS ARE TWO INDEPENDENT TRANSCRIPTIONS

Measured in `nn/onnx.bend`: `onnx_ops_n` counts `onnx_ops()`'s own literal, so
DELETING an arm from a DIFFERENT table (`onx_odt_name`'s `BOOL`) moves
`onnx_odt_rt`, `onnx_odt_all` and `onnx_odt_tbl` and leaves the count green. Same
for a same-length MISSPELL: `onnx_ops_n` stays `True` and only the table string
moves. This is the `mixin/creation` rule 23 / `mixin/gradient` rule 6 family
("it is not only rules that collide, it is any check whose oracle is a COUNT
rather than a STRUCTURE") stated as a limitation of MY OWN gate rather than
someone else's. **The mitigation that works: the count row names what it counts
("the count of `onnx_ops`'s own literal"), and the mutation table has a
DELETED-ARM entry and a MISSPELL entry as separate mutations.**

### 9. AN UNUSED `+` PARAMETER IS ACCEPTED, SO A MUTATION CAN FIND A PARAMETER THAT IS NOT LOAD-BEARING

`onx_sel_max` threads `hit`, `bv` and `bi` through its fold. Mutating `bv`'s
update (`U32.max(bv, …)` -> `bv`) moves NOTHING, because `bv` feeds only the max
COMPARISON and the answer is the `bi` string. Mutating `bi`'s pick moves ELEVEN
rows. **Both mutations are the same rule and only one is localised**, which is the
"two rules over one row, so neither is localised" note from `movement.bend` --
found here by the mutation table rather than by reading, and it is the cheapest
use of a mutation table there is: it names the parameter that is decoration.

## SIX MORE RULES, MEASURED 2026-10-02 WRITING `uop/validate.bend`

Appended, not edited, continuing the count from 31. All six are Bend 2.0.34 and
each one cost at least one compile cycle. The first two are the expensive ones
and the fourth is the one that silently emptied a whole gate.

### 32. **`Bool.pick` IS STRICT *AND* IT IS AFFINE-TOO, SO A BRANCH THAT BUILDS A
###     STRUCTURE MUST BIND IT WITH `+` FIRST -- AND THE STRUCTURE IS THE PARAMETER**

`Bool.pick(TYPE, cond, a, self_call(...))` evaluates BOTH arms, which is the
recording everyone has. What is NOT recorded is the consequence when the two arms
build a GROWING value:

    def uops_to_z3.of(ar: O.Arena, ms: List<&2, MRng>, snk: O.Found) -> Vz:
      vz_walk(vz_drop_sink(vz_topo(O.Arena.budget(ar), ar, F.folded(ar), ...)), ...)

That checks, it runs, and the toposort comes back EMPTY on every row -- so a
sixteen-row gate prints `[] |  |  | 0` sixteen times with no error anywhere. The
cause is the same shape as `mixin/rand.bend`'s rule 1: `O.UOp.sink` GROWS the
arena, so the `ar` passed as the FIRST argument is the PRE-SINK store and the
SINK index is not in it.

**THE FIX IS ONE `let`, and it is the same fix as everywhere else:**

    +snk = O.UOp.sink(ar, [idx, gate])
    uops_to_z3.of(O.Found.ar(snk), ms, snk)

Two data points from the same file, both measured: the FIXTURE version
(`dv2(nm, fx_var(ar, ...), fx_const_bool(ar, ...), ms)`) builds the PARAM in one
COPY of `ar` and the mask in ANOTHER, and the PORT version above builds the SINK
in a copy and hands `.of` the original. **A `Bool.pick`-shaped argument list
whose arguments each GROW is the most expensive spelling mistake in this port,
and the symptom is an EMPTY ANSWER rather than an error.**

### 33. **A `.go`/`.step` SPLIT OF ONE SELF-RECURSIVE FOLD IS MUTUAL RECURSION AND
###     IS REFUSED; THE `If` GOES IN THE `1n+p:` ARM INLINE**

    def z3_shift.go(k, ...) = match k: case 1n+p: z3_shift.step(p, ...)
    def z3_shift.step(k, ...) = z3_shift.go(k, ...)      # <-- MUTUAL, refused

The working shape is one def whose arm both recurses and builds:

    case 1n+p: z3_shift.go(p, is_shr, z3_shift.armed(is_shr, a, b, lo, i), b, lo, U32.add(i, 1))

where `armed` is a LEAF. This is the notes' movement.bend rule 2 again, now with a
`Nat` fuel and a growing term accumulator: the accumulator goes AFTER the
shrinking list/fuel and the leaf holds the `If`. A scripted topological sort
FINDS the cycle and refuses, which is a cheap way to notice it before the
compiler does.

### 34. **A `U32` HAS NO CONSTRUCTORS, SO `case 0: ... case 1: ... case _:` ON A `U32`
###     IS "a declared constructor (unknown: U32)"**

The brief's rule 9 and rand.bend's rule 2 both talk about numeric ladders, and
every file in the tree writes `case 0:` .. `case 25:` on a `U32` tag and it works
-- because those ladders are CONSECUTIVE from zero and the checker accepts them.
A THREE-WAY choice over `U32` literals that are NOT 0/1/n (`case 0 / case 1 /
case _:` for a bit-op tag 0/1/2) is refused outright with a message that names a
CONSTRUCTOR you never wrote. **Write a three-way `U32` choice as two
`Bool.pick`s**, which is what `bv_op`, `ren_9.b2.mk` and `ren_10.mk` do. Three
instances in one file; all three cost a cycle each.

### 35. **`Wv{Bool, U32}` IS THE ANSWER TO "A `Maybe` BOTH ARMS OF A `Bool.pick`
###     NEED", AND IT IS NOT A `+`**

    def z3_and.pw(nb: Bool, m: Maybe<&1, U32>, +a: Z, +b: Z) -> Maybe<&1, Z>:
      Bool.pick(Maybe<&1, Z>, nb, z3_and.pw2(Z.num(b), m, a), z3_and.bv(m, a, b))
      #| - expected : m
      #| - observed : m (consumed more than once)

Three fixes were tried and only one works: a second def that re-reads `m` (still
two reads in the CALLER), a `+bv = ...` let (`+bv can be used many times, so its
type must be Data` -- a `Maybe` is a `Type`), and the pair. The pair is three
lines and it composes:

    def wv(m: Maybe<&1, U32>) -> Wv: match m: case Some{w}: Wv{True{}, w}
                                            case None{}: Wv{False{}, 0}

`Maybe.default` does NOT work because it needs a default VALUE and there is no
correct zero for a bit-vector width. **This generalises the notes' "a `Data`
record cannot hold a `Maybe`" into the FOLD case: whenever a `Maybe` crosses a
`Bool.pick`, decompose it into a `Bool` plus the value at the point where it is
produced, not at each use.**

### 36. **A `String` IS NOT `List<&2, Char>` -- `List.length(&2, Char, s)` IS A TYPE
###     ERROR, AND `String.is_empty` DOES NOT EXIST**

    def empty_str(acc: String) -> Bool: List.length(&2, Char, acc)   #| expected List<&2, Char>
    def empty_str(acc: String) -> Bool: String.to_list(acc)         #| the match works on THIS

`String` is its own datatype with `SCon{head, tail}`; it is not definitionally a
`Char` list even though the guide says it is one, so a quantified `List` fold
needs `String.to_list` first. There is no `String.is_empty` in base (recorded
earlier) and `List.is_empty` does not take a `String`, so **"is this string
empty" is a two-def thing**: `to_list` then `case Nil{}`. Three occurrences in
`validate.bend` and each one cost a cycle.

### 37. **A PARAMETER MAY NOT SHADOW A DEF NAME, AND THE ERROR NAMES THE
###     CONSTRUCTOR** (an extension of device.bend rule 2, to `List` binders)

    def Sol.find.go(+es: List<&2, Bind>, k: U32) -> Maybe<&1, Z>:
      match es:
        case Bind{u: v, t} <> rest: ...
    #| - expected : a term
    #| - observed : ':'

`case Bind{u: v, ...}` is not the rename syntax -- Bend has none. And renaming the
BINDER to a parameter's name is refused with "a declared constructor (unknown:
Bind)" naming the TYPE, which is perfectly well declared. **Rename the
PARAMETER** (`k`, not `u`), which is what `Sol.find.go` and `Sol.mm.go` do.

## TEN MORE RULES, MEASURED 2026-10-02 WRITING `engine/jit.bend` + `engine/worker.bend`
Appended, not edited, continuing the count from 31. All ten are Bend 2.0.34 or facts
about a shared file, and each one cost a compile cycle or a wrong answer. Rules 1, 2
and 6 are the ones that cost the most and rule 1 is the one that pays for the file.

### 1. A FOLD WHOSE STATE IS (CARRIED, ACCUMULATED) IS TWO PARAMETERS, NOT A `Data`
###     RECORD -- AND WHEN THE CARRIED THING IS WHAT GROWS, THE FUEL GOES FIRST
MEASURED (2026-10-02, `jit.bend` `_check_no_non_tensor_return`). The shape every fold
in this tree uses for "answer both a thing and a fact about it" is a `Data` record with
a fold accumulator (`Dts{some, meet, result}` in `weak.bend`, `Marg{o, n}` in
`movement.bend`). It does not work when the thing is a WORKLIST that a sequence GROWS,
and the reason is a PAIR of refusals that look unrelated:

```
def nr_go(xs, p: Pend) -> Pend:
  case +h <> t: nr_go(nr_next(h, t), nr_bad(h, p))
#| - expected : a decreasing self-call
#| - observed : nr_go                     <-- the first argument is a CALL

def nr_go(xs, p: Pend) -> Pend:
  case +h <> t:
    match nr_step(h, p, t):
      case Pend{+todo, bd}: nr_go(todo, Pend{todo, bd})
#| - message : a parameter or field scrutinee (a match cannot scrutinize a computed value)
```

The worklist grows (`[t, kids]`), so it is not a strict subterm of `xs` and the
decrease check refuses; and returning the new worklist so the arm can destructure it is
refused because a `match` may not scrutinise a call. The fix is BOTH of the sanctioned
answers at once and there is no third:

```python
def nr_go(fuel: Nat, xs: List<&2, JRet>, bad: Maybe<&2, String>) -> Maybe<&2, String>:
  match fuel:
    case 0n: bad
    case 1n+p:
      match xs:
        case Nil{}: bad
        case +h <> t: nr_go(p, nr_next(h, t), nr_bad(h, bad))
```

A `Nat` FUEL is the first parameter, everything after it is free (rules 1.5/28/30), and
a nested `match` inside an arm IS legal (rule 1.2's last bullet). `+todo` on the BINDER
is what hands the worklist to its own self-call (rule 1.1's last bullet). The `Pend`
record then costs a `Data` type, four readers and a third def for NOTHING, so it goes.

**THE GENERAL FORM, and it is the useful half:** *a fold that accumulates a `Maybe` or a
`Bool` does not need a record -- it needs the accumulator as a second parameter. Reach
for the record only when the accumulated thing is a STRUCTURE you have to read back in
the arms.* `Dts{some, meet, result}` needs it because `result` is a field read by a
later pass; `nr_go`'s accumulator is a `Maybe` read once at the end.

### 2. `Bool.pick` WITH A SELF-CALL FORCES THE **WHOLE** `pick` INLINE, AND THE `+`
###     GOES ON THE PATTERN BINDERS -- NOT ON THE PARAMETERS
MEASURED (2026-10-02, a STABLE STRING SORT, and it is the fourth spelling of this
problem). Rule 11.4 says `Bool.pick` is the only way to put a self-call in a
choice position. What it does NOT say is that you may factor either arm out:

```
def srt_ins.here(x, h, t): List.append(&2, String, [x, h], t)      # the TRUE arm
def srt_ins.go(x, h, t): h <> srt_ins(x, t)                        # the FALSE arm
case +h <> t: Bool.pick(List<&2,String>, String.is_lt(x, h), srt_ins.here(x, h, t), srt_ins.go(x, h, t))
#| - expected : a filled definition (an unfilled law is a dead claim)
#| - observed : srt_ins                <-- `srt_ins.go` is BELOW its caller
```

Extracting either half makes the extracted leaf recurse back into the walk, which is
mutual recursion in either declaration order. So the entire `Bool.pick` -- condition,
both arms, self-call -- is ONE term in the arm, and every value both arms touch needs a
reusable binding: `case +h <> +t:` (both binders), not `+` on anything else. `t` appears
in `[x, h] ++ t` and in `srt_ins(x, t)`; `h` appears in `is_lt(x, h)` and in `h <> ...`.

**AND THE BUG IT CAUGGED, which is the reason this is worth writing down.** The first
version returned `[x, h]` where it needed `[x, h] ++ t`, and `srt_ins(x, t)` where it
needed `h <> srt_ins(x, t)`. It compiled, it checked, it ran, and
`ssort(["b","a","c"])` answered **`c`** -- one element, having silently discarded two.
The row that saw it was a COUNT-ish row (`sort_exprs`), not a boolean, which is the
"pin a COUNT, not a boolean" note from `mixin/creation.bend` paying for itself a third
time.

### 3. A SELF-RECURSIVE WALK WHOSE FIRST ARGUMENT IS A `U32` FAILS THE DECREASE CHECK,
###    AND THE ERROR NAMES THE WALK
MEASURED (2026-10-02). `cap_written.go(ar, xs, acc)` compiled and checked and was
REFUSED on a later edit:

```
def cap_written.go(ar: O.Arena, xs: List<&2, U32>, acc: List<&2, U32>) -> ...
  case +h <> t: cap_written.go(ar, t, cw_step(ar, acc, h))
#| - expected : a decreasing self-call
#| - observed : cap_written.go
```

An arena is `Data` and does not SHRINK, so the checker reads past it to `xs`, finds
`t`, and is happy -- until the arm has to read `ar` twice, `+ar` goes on, and the
`+` argument breaks the subterm relation (rule "Explicit fuel" item 2, restated by
`renderer/__init__` rule 29 for a different reason). **THE SHRINKING LIST MUST BE THE
FIRST PARAMETER OF EVERY SELF-RECURSIVE WALK, and an arena threaded alongside it always
has to go second.** Four defs in `jit.bend` have this shape and all four had to be
rewritten: `cap_written.go`, `cap_concrete.go`, `prep_input_uops.go`, `ii_reprs.go`.

### 4. `+` ON A `String` AND ON A `U32` IS FREE, AND `List.contains`'s `+x` PROPAGATES
###    THE REQUIREMENT TO ITS CALLER
MEASURED (2026-10-02). Two things the "two reads need a record" family gets wrong:

```python
def srt_ins(+x: String, acc) -> ...      # ACCEPTED. `+` on a String costs nothing.
def ii_flat(+ar: O.Arena, +v: U32) -> ...  # ACCEPTED. Confirms rand.bend rule 4/30.
def j_add(+x: U32, +acc: List<&2, U32>)   # `List.contains(U32, U32.is_eq, acc, x)`'s
                                          # `+x` in ITS OWN signature is a REQUIREMENT ON
                                          # THE CALLER, so `x` must be `+` here too.
```

The third is the one that costs a cycle: base's `def List.contains(~A: Data, ~eq, xs, +x:
A)` looks like it COPIES the element internally, so passing an affine `x` seems free,
and the refusal is `expected : x / observed : x (consumed more than once)` pointing at
the `x` in the caller's own signature.

### 5. A `Maybe` FIELD OF A `Data` RECORD IS FINE, AND `Maybe.is_some(a, -A, m)` IS
###    HOW YOU TEST IT
MEASURED (2026-10-02). **This RETRACTS the standing "a `Data` record cannot hold a
`Maybe` field -- flatten to `Bool`s plus a third `Data` type" note, for 2.0.34.**
`Pend{todo: List<&2, JRet>, bad: Maybe<&2, String>}` and `Slot{slot, nm:
Maybe<&2, String>}` (realize.bend:1432) and `CallInfo{name: Maybe<&2, String>, ...}`
all check. What IS still true is the narrower `device.bend` rule 6: a `Data` FIELD may
not be a `match` SCRUTINEE. So a decision about a `Maybe` still needs a `Bool.pick` or
a `Bool` hand-off, and `Maybe.is_some(&2, Cap, Jit.cap(j))` is the test -- a reader that
must answer a `Bool` cannot return the `Maybe` field:

```
def Jit.has_cap(j: Jit) -> Bool:
  match j:
    case Jit{has_fxn, cnt, cap, prune}: cap
#| - expected : Bool
#| - observed : Maybe<&2, Cap>
```

### 6. `List<A>` IN A LITERAL IS `&1` AND THE ERROR NAMES THE FIELD TYPE, NOT THE ARITY
MEASURED (2026-10-02). `O.ProgramInfo`'s `global_size` is `List<&2, H.I64>` and a
helper returning `[H.i64_of_i32(1), ...]` is inferred `&1`:

```
- expected : List<&2, H.I64>
- observed : List<&1, H.I64>
Location: fx_prog_arg
  O.AProgram{O.ProgramInfo{fx_i64(), fx_i64(), Nil{}, Nil{}, outs, ins}}
```

The caret points at `fx_i64()`, which is a perfectly ordinary list literal, and the
message says nothing about arity. The fix is the arity in the RETURN TYPE
(`def fx_sizes() -> List<&2, H.I64>`), and the generalisation is rule 31's
"`List.map` infers `&1`" with the confusable case: **any `List` LITERAL passed into a
struct field is `&1` until the helper's return type says otherwise.**

### 7. `List.contains(q, xs, x)` TAKES THE LIST BEFORE THE ELEMENT, AND `List.get`
###    TAKES THE QUANTIFIER, THEN THE ELEMENT TYPE, THEN THE LIST
MEASURED (2026-10-02) — `device.bend` rule 7 and `codegen/opt` rule 10, both restated
because both were re-learned in one afternoon. `j_add` was written
`List.contains(U32, U32.is_eq, acc, xs)` meaning "is the LIST `xs` in `acc`", and the
refusal is `expected : U32 / observed : List<&2, U32>` -- it took `xs` as the ELEMENT.
`List.get(a, -A, xs, n)` returns a `Maybe`, and `&1` and `&2` are DIFFERENT types with
no conversion (rule 6 here).

### 8. `def X.of` MUST IMMEDIATELY PRECEDE `def X`, AND A SCRIPT THAT MOVES A BLOCK
###    CAN SILENTLY DELETE IT
Rule 10.4 again, and the failure mode is worth naming: a `python3` "move this def above
its caller" helper that computes a block's end as "the next line starting with `def `"
DELETED `def j_at` outright (the wrapper it moved `j_at.go` above), and the checker then
reported `expected : a defined name / observed : j_at` on a call 570 lines away. The
def count is the cheap detector and it is in the brief for this reason:

    grep -c "^\(def\|type\) " tinybendygrad/engine/jit.bend

### 9. A GATE ROW THAT ASKS FOR THE `return` OF A PURE-BENDING DEF MUST BE A DEBUILT
###    `Maybe`-to-`String` ROW, BECAUSE `"unprintable"` IS ALSO WHAT AN ABSENT ANSWER
###    PRINTS
MEASURED (2026-10-02). `jit.bend` has eleven rows whose value is a
`Maybe<&2, String>` rendered by `j_str`, and `j_str(None{}) == "unprintable"`. So
`replay_ok=unprintable` and `pickle_ok=unprintable` and `ret_none=unprintable` are three
rows with the SAME value, and a mutation that turns one of them into a refusal is
invisible to the other two. `creation.bend` rule 8's advice generalises past trailing
whitespace: **when one printer serves both "no answer" and "an answer the port cannot
reproduce", the rows are not independent, and the shared value is a hole in the gate.**
The fix is a second printer for the absent case (`""`), and it is the difference between
"three rows" and "eleven rows".

### 10. `String.is_lt` IS A REAL `Bool` AND `Bool.pick` OVER A `List<&2, T>` IS A REAL
###     `List<&2, T>` -- BUT NEITHER FIXES A `Bool.pick` THAT DROPS A LIST TAIL
MEASURED (2026-10-02), and it is the companion to rule 2 here. Three probes isolate the
three pieces so the next agent does not have to:

```
Bool.pick(List<&2,String>, True{},  ["x","h"], ["q"])       ->  x,h
Bool.pick(List<&2,String>, False{}, ["x","h"], ["q"])       ->  q
String.is_lt("a", "b")                                       ->  True
srt_ins("a", ["b","c"]) with `[x,h]` and `srt_ins(x,t)`     ->  a,b     (t LOST)
```

The last line is the only wrong one and no probe but a VALUE probe finds it: the code
typechecks, checks in both lanes, and returns a list two elements shorter than it should
be. `List.append(a, A, xs, ys)` is `xs ++ ys` (rule 6) so the repair is
`List.append(&2, String, [x, h], t)`, not `[x, h] ++ t`.

---

## SEVEN MORE RULES, MEASURED 2026-10-02 WRITING `renderer/tc_ptx.bend` (STAGE 2)

Appended, not edited. Bend 2.0.34. Each one cost a diff, and the first two are the
expensive kind: the code typechecked, checked in both lanes, and printed a plausible
wrong answer.

### 1. A SELF-CALL IN BOTH ARMS OF A `Bool.pick` COMES BACK SPENT -- `Bool.pick` IS
###    STRICT IN BOTH ARMS AND A SELF-CALL SPENDS THE LIST IT WALKS (rules 2 / 7-DUP)
MEASURED (2026-10-02) on a keep-filter over a `List<&2, T>`, and it is the natural
one-liner for a filter:

```python
def keep(+ds: List<&2, Dt>) -> List<&2, Dt>:
  match ds:
    case Nil{}   : Nil{}
    case d <> +t : Bool.pick(List<&2, Dt>, keep_d(d), keep(t), d <> keep(t))
```

`Bool.pick(A, c, a, b)` is an ordinary 5-argument function, so BOTH `keep(t)` calls
run, and the second one walks a list the first has already consumed. The result is not
an error and not a wrong order: it is a list containing only the LAST element, on
every prefix. Measured, all three `supported_dtypes` rows printed `[__bf16]`.

The shape that works calls the recursion ONCE, through a `+rest` binder, and conses in
front of it:

```python
def keep(+ds: List<&2, Dt>, +acc: List<&2, Dt>) -> List<&2, Dt>:
  match ds:
    case Nil{}   : acc
    case d <> +t :
      +rest = keep(t, acc)
      Bool.pick(List<&2, Dt>, keep_d(d), List.append(&2, Dt, [d], rest), rest)
```

`List.append(a, A, [d], rest)` is `[d] ++ rest` -- the head goes in FRONT. Writing
`List.append(&2, Dt, rest, [d])` typechecks, runs, and REVERSES the answer, which is a
one-row diff on a five-element list and a 259-row diff on `pow2`. **So: one recursive
call per arm pair, through a binder, and the cons is `append(..., [x], rest)`.**

### 2. A PYTHON LIST SLICE CLAMPS; READING `e` FIXED INDICES WITH AN `""` DEFAULT DOES
###    NOT, AND THE RESULT IS A DELIMITER WITH NOTHING AFTER IT
MEASURED (2026-10-02) on `', '.join(regs[i*e:(i+1)*e])` with `e == 2`. The first port
read two indices and defaulted an out-of-range one to `""`:

```python
def slice2(+xs: List<&2, String>, +i: U32) -> String:
  String.join([at(xs, U32.mul(i, 2)), at(xs, U32.add(U32.mul(i, 2), 1))], ", ")
```

`regs[0:2]` on a ONE-element list is `["%va0"]`, so CPython joins one name; the port
joined `"%va0"` and `""` and printed `mov.b32 %wi0_0, {%va0, };` -- a register list with
a hole in it, and a string that is a perfectly plausible PTX line. The generalisation
is not about slices: **any time a port replaces a Python SLICE with N indexed reads, the
port has changed the answer for every input shorter than N, and the fixture has to
contain one.** `List.drop(a, A, xs, n)` then `List.take(a, A, xs, 2n)` is the slice, and
`List.take` already has the `0n` case so there is no separate empty-guard to forget.

### 3. A BEND STRING LITERAL HOLDS A REAL TAB, SO A `py=` HALF TRANSCRIBED FROM
###    CPYTHON'S `repr()` HAS TO BE SPELLED, NOT TYPED
MEASURED (2026-10-02). The gate rows are `<name> = [BEND]   py=[CPYTHON]`, and CPython
puts `repr()` on both halves, so the oracle's `py=` half contains the two characters
`\` and `t` where the Bend half contains a TAB. Writing the literal in Bend as
`"'\tmov.b32\t\t%r0, %r1;'"` typechecks, runs, and is RED -- and the diff is invisible in
a terminal, because a tab and a backslash-t are the same width:

```python
def bslash() -> String: String.from_list([Char.from_u32(92)])
def btab() -> String: String.concat([bslash(), "t"])
```

This is the one mutation in the table (M43) that a human reading both lanes side by
side would call green. **It is the whole argument for a BYTE diff over a
term-by-term comparison, and it belongs in the same file as the gate that needs it.**

### 4. `List.contains(~A, eq, xs, +x)` TAKES A DEF, SO A MEMBERSHIP TEST REPLACES A
###    TWENTY-ONE-ARM LADDER THAT ENCODED THE SAME SET TWICE
MEASURED (2026-10-02). `asm_for_op` is a 21-key dict and `supports_half` is a 7-tuple
literal. The first port wrote an `op_key(o) -> U32` ladder PLUS a `Bool` ladder over the
indices PLUS the key list: three copies of the same twenty-one names. With
`List.contains(~O.Op, O.eq_op, supports_half(), o)` the seven names live in ONE place,
`doesnt_support_half` is derived from that same place, and a wrong name moves BOTH rows
of the gate at once (measured: 2 rows) instead of one. `O.eq_op` is a def, which is what
`~eq` wants -- a closure is not a def and the call is refused. Cost: the two copies of
the op names, 24 lines.

### 5. A `String` PARAMETER USED TWICE IN ONE DEF NEEDS `+` EVEN WHEN IT IS NOT A
###    `Data` RECORD, AND THE ERROR POINTS AT THE SIGNATURE, NOT AT THE USE
MEASURED (2026-10-02), restating rules 1-DUP and 2-DUP for the `String` case, which is
the shape an indexed row builder takes:

```
def rk1.go(+nm: String, +ls: List<&2, String>, +i: U32, acc: String) -> String:
#| - expected : nm
#| - observed : nm (consumed more than once)
```

It is reported on the `nm` in the SIGNATURE, before the reader has looked at the body,
and the same message appears for the caller's parameter when the callee takes it. So a
def that builds `nm ++ "[" ++ show(i) ++ "]"` and recurses needs `+nm` in both the
`.go` and the entry point, and the compiler will not tell you which one it wants.

### 6. A GATE ROW ORDER IS PART OF THE CONTRACT, AND CPython's ORDER IS NOT ALWAYS THE
###    ORDER THAT LOOKS NATURAL -- `diff` IS POSITIONAL, SO A `set` IS A HOLE
MEASURED (2026-10-02) three ways in one file, all of which were caught only by the byte
diff and not by any per-row comparison:
  * `supported_dtypes` returns a `set` (ptx.py:230), so the gate SORTS the names, and
    a keep-filter that conses is then indistinguishable from one that appends. Measured:
    the cons-vs-append mutation moves 0 rows there and 3 rows on `tensor_cores`, whose
    value CPython DOES order. **Where the oracle has to normalise, the gate loses a
    dimension, and the mutation table is where you find out which dimension.**
  * `supports_half` is a tuple LITERAL, so its order is the literal's
    (`EXP2,ADD,MUL,MAX,CMPLT,WHERE,TRUNC`) and not the dict's, which would put TRUNC
    second. One row moves, and the derived complement does not.
  * `PTXRenderer.types` is a dict, so its rows come in INSERTION order, and a gate that
    sorts them moves one row when the order is wrong and zero rows when a value is
    wrong for a dtype that appears once.

### 7. A RULE WHOSE OUTPUT IS AN INTERMEDIATE NEEDS A ROW ON THE INTERMEDIATE, AND
###    WHEN AN UPSTREAM ASSERTION MAKES IT UNOBSERVABLE, THE ROW HAS TO BE ADDED
###    ANYWAY
MEASURED (2026-10-02) twice, and both cases are PROVABLY unobservable rather than
merely unobserved, which is the part worth writing down:

  * `TensorCore.threads` is `2**len(frag_c[0])`, and `__post_init__` (tc.py:43) ASSERTS
    `len(f[0]) == len(frag_c[0])` for all three fragments. A, B and C therefore have the
    same lane count in every legal tensor core, and the three candidate readers are the
    same function. No fixture can separate them, and the mutation table says 0. The
    control that proves the ROW is not insensitive reads `frag_c[1]` instead, whose
    length the assertion does not pin: 8 rows.
  * `axis_coords` reads `used = frag_a + frag_c` and takes a MAX per axis, and
    `__post_init__` forces A to cover every m and k coord and C to cover every n coord,
    so `A + C` and `A + B` have the same three maxima for every legal tensor core.
    Swapping C for B moved nothing until a row on `used` ITSELF was added, because the
    concatenation's string differs even though everything computed from it agrees.

The generalisation: **a mutation that moves nothing is not automatically a fixture
gap.** Before widening the fixture, ask whether the upstream code makes the two
answers equal, and if it does, put a row on the intermediate value -- the string --
rather than on the numbers derived from it.

---

## SIX MORE, MEASURED-BY-DERIVATION 2026-10-02 WRITING `runtime/ops_disk.bend`
+ `nn/datasets.bend` (the `runtime/` FFI unit)

Appended, not edited. **HONESTY NOTE FIRST, and it applies to this whole section:**
that unit ran with NO SHELL AND NO COMPILER -- the session's tool catalog was device
control only -- so none of these six is a MEASUREMENT against bend 2.0.34. They are
DERIVED from rules already in this file plus the constraint catalogue, and the two
Bend-syntax ones (#1 and #4) are the ones a compiler may contradict. #2, #3, #5 and
#6 are about GATES and TOOLING and hold regardless of whether Bend agrees.

1. **A `match` ON A CALL IS REFUSED EVEN FOR `Bool.and(a, b)` OVER TWO PARAMETERS,
   SO A TWO-FLAG PREDICATE COSTS A `.at`/`pick` PAIR.** The recorded shape ("compute
   a Bool in the arm and pass it to a def as a parameter") does not spell what
   happens when the Bool is the WHOLE scrutinee. This is refused:

   ```python
   def shard.at(ioring: Bool, use_ioring: Bool, ..., d: Dev) -> ShOut:
     match Bool.and(ioring, use_ioring):       # a CALL as the scrutinee
       case True{}:  shard_ioring(...)
       case False{}: shard_at(...)
   ```

   and the working shape is two defs, the leaf first:

   ```python
   def shard.at(go: Bool, ..., +d: Dev) -> ShOut:     # the DECISION
     match go: case True{}: A   case False{}: B
   def shard.pick(ioring: Bool, use_ioring: Bool, ..., +d: Dev) -> ShOut:
     shard.at(Bool.and(ioring, use_ioring), ..., d)  # the PREDICATE, in one place
   ```

   `+d` on the `.at` is needed because `d` is read in BOTH arms, and `+` on a later
   parameter does not disturb anything (rule 29). This is the fourth recorded spelling
   of the same problem and it is the one that fits a two-flag dispatch.

2. **A WHOLE-TRACE COMPARISON IS UNUSABLE UNTIL THE FIXTURE'S OWN CONSTRUCTION IS OUT
   OF THE TRACE, SO EVERY GATE THAT WANTS `seq_eq` NEEDS A `reset`.** `ops_webgpu.bend`
   already has `Tr.reset` ("an EMPTY trace that keeps `bad_at` and `popn`"). The
   generalisation is the RULE, and it is the first thing to check when writing a
   total-sequence row: *is the fixture's own setup in the trace?* In
   `ops_disk.bend` every device fixture carries `dev_init`'s four calls plus
   `_might_open`'s six, so `seq_eq(Dev.tr(x), [Call{K_CLOSE(), 0}])` is `False` for a
   perfectly correct close. The fix is a `dev_reset` that empties the trace and keeps
   the DEVICE STATE, and it is a gate mechanism rather than a port of anything -- say
   so where it is defined, because otherwise the next reader looks for a Python line
   it came from.

3. **A NORMALISING FUNCTION COLLAPSES ITS OWN FIXTURES, SO N STRING ROWS BECOME ONE
   VALUE ROW AND N-1 BOOLEAN ROWS.** `shm_name(filename(device))` is
   `"/" + filename[4:].lstrip("/")`, and `lstrip` makes the NUMBER OF LEADING SLASHES
   irrelevant: `disk:shm:dk`, `disk:shm:/dk` and `disk:shm://dk` all answer `/dk`, and
   `disk:shm:` and `disk:shm://///` both answer `/`. Five `srow`s would have been TWO
   CONSTANT COLUMNS that no mutation could move (rule 4 of the `reduce` unit). What
   works is one `srow` per distinct value and one `row(..., String.eq(x, THE_VALUE))`
   per fixture -- five independent claims, each of which fails if `String.drop` or the
   `lstrip` walk breaks. **The test for whether a fixture family needs this treatment is
   one grep: do two of the fixtures produce the same string?** If yes, only one of them
   is a value row.

4. **`getattr(M, "X", default)` IS VACUOUS WHENEVER THE DEFAULT IS ONLY REACHABLE ON A
   PLATFORM WHERE `M.X` IS ABSENT -- AND THEN THE PARAMETER MUST BE DROPPED, NOT
   KEPT.** `ops_disk.py:81` is
   `MAP_POPULATE = getattr(mmap, "MAP_POPULATE", 0 if OSX else 0x008000)`, and the only
   platform without the attribute is the one whose default is `0`, so both spellings
   answer the same two numbers and an `has: Bool` parameter is a conjunct no fixture
   can falsify. The port says so in a comment and takes ONE `osx: Bool`. The SAME
   argument does NOT apply to `getattr(os,"O_DIRECT",0)` at :33, because Linux HAS the
   attribute and macOS does not -- so `open_direct` keeps its parameter and gets a row
   per cell. **tinygrad uses `getattr` in dozens of places, so this is a rule and not
   an anecdote: before porting a `getattr` default, ask which platforms can reach it,
   and if only one, do not give the port a parameter for it.** That is the
   "an accumulator Bool that appears in the PREDICATOR rather than in the RESULT"
   tell (`_select_op`) applied to Python's own idiom.

5. **A PYTHON `try/except OSError` AROUND A SYSCALL THAT THE PORT RECORDS PRODUCES THE
   SAME TRACE ON BOTH PATHS, SO THE `except` IS NOT A BRANCH AND TAKES NO PARAMETER.**
   `ops_disk.py:33-34` is `try: os.open(f, O_RDWR|O_CREAT|O_DIRECT) except OSError:
   os.open(f, O_RDWR|O_CREAT)`, and an honest trace records the ATTEMPT as well as the
   RETRY -- so the port emits both opens, in that order, with their own flags, and
   `dev_file.open.at` takes no Bool at all. The header has to SAY this, because the
   instinct is to write `.at(ok, ...)` and then invent a fixture for a flag that
   changes nothing. **Generalise: an `except` that is swallowed makes the two arms
   CONVERGE, and a gate row per arm is then a row per nothing.** The mirror image is
   equally worth stating -- an `assert` raises, so it DIVERGES, so it does want a
   parameter and a truncation, and the two kinds must not be ported the same way.

6. **A MUTATION HARNESS MUST PUT THE MUTANT IN THE ORIGINAL DIRECTORY, NOT A TEMPDIR,
   BECAUSE A `.bend` FILE'S RELATIVE IMPORTS RESOLVE NEXT TO IT.** Measured while
   writing `.agents/slop/dk-mutate.py`: `shutil.copyfile(src, tmpdir)` produces a file
   whose `import ./../helpers.bend as H` cannot resolve, so every mutation reads as
   "DEAD" for a reason that has nothing to do with the mutation. Copy to
   `os.path.dirname(src)/.<id>-mutant.bend` and delete it in a `finally`. The second
   half of the same lesson: **an edit whose `old` text is not FOUND must print
   "EDIT NOT FOUND", not "0 rows moved"** -- otherwise a table entry whose target line
   has been edited by hand silently becomes a claim that the mutation moves nothing,
   and that is the exact reading the notes say a blind spot must not be confused
   with.

AND THE FINDING THAT IS ABOUT THE PYTHON RATHER THAN ABOUT BEND, recorded because it
cost the unit an entire planned gate section:

7. **`tinygrad/runtime/ops_disk.py` HAS NO DTYPE-TO-SUFFIX TABLE, and neither does any
   other file it can reach.** The brief for this unit asked for "the dtype-to-suffix
   table, both directions" as a gate target and there is no such table: a `DiskBuffer`
   is a raw `mmap` window, so a dtype changes how many BYTES the window covers and never
   how the file is named, and `nbytes` is `size * itemsize` (`device.bend`) which is
   the whole of a dtype's reach into the file. `grep -rn suffix tinygrad/` finds hits
   only in `renderer/cstyle.py`, `runtime/ops_dsp.py` and the autogen bindings. **The
   lesson for the next brief: check that the artefact named in the acceptance criteria
   EXISTS before designing a gate section for it.** A gate target that is not in the
   source is either a different file's target or a mis-transcription, and either way it
   costs a section.

---

## TWELVE MORE RULES, MEASURED 2026-10-02 WRITING `runtime/ops_metal.bend`

Appended, not edited. The file is `tinybendygrad/runtime/ops_metal.bend` (3486
lines, 329 gate rows), its gate is diffed byte-for-byte against BOTH Bend lanes
AND a 167-row CPython oracle, and its mutation table is 48 entries of which TWO
move nothing and one of those two is a blind spot ABOUT THE PYTHON.

### 1. A `+` PARAMETER MAY BE ADDED BY A MUTATION, AND IT IS A `+`-ONLY MUTATION
    THAT MOVES NOTHING
The mutation table needs an entry for "the edit that adds only a `+`", because
that is the edit an LLM (or a tired human) makes by accident when a parameter is
reported as "consumed more than once" and the temptation is to paper over it
instead of finding the second read. Run it: it moves 0 rows, and that is the
measurement. **A mutation table with a `+`-only entry and a comment-only entry
has two independent controls**, and they are different controls -- the comment
one proves the harness diffs something, the `+` one proves a syntactically
plausible repair is not a semantic one. `M14` and `M14c` in `ops_metal.bend` are
the two; `M41` is the comment control.

### 2. `List.append(a, A, xs, ys)` IS `xs ++ ys`, SO A FOLD THAT APPENDS IS
    ALREADY IN ORDER -- AND THE BUG IS THE `List.reverse` THAT "FIXES" IT
Measured, and it cost two rows. `sync_range.go` had
`case 0n: List.reverse(&2, U32, acc)` copied from `ush`, which CONSES, and the
fold appends. **The two shapes disagree only on lists of two or more**, so a
one-element fixture is blind to it; `mt_sync_idx5` is the one-element fixture and
`mt_sync_idx17` is the three-element one that caught the reverse. The same trap
bit `q.items`: :111 is `[globals] + [vals]` and building it as
`q.items.bufs(nbufs, vars)` gives `[vals] ++ [globals]`, which moves EVERY
offset in the file. **A `List.append` fold needs no `reverse`, and saying so at
the fold is cheaper than discovering it in the gate.**

### 3. `round_up` IS NOT `ceildiv`, AND `round_up(n, a) // a` IS
`D.round_up(4, 4)` is 4. `range(5, 9, 4)` has ONE element, and a `sync_count`
that used `round_up` where the source says `len(range(...))` answered 4. There
is no `floor` in `base.bend` (rule 5 at line 1484) and `helpers.bend`'s
`ceildiv_u32` exists but the cleanest spelling is the pair:

    def ceildiv(n: U32, a: U32) -> U32: U32.div(D.round_up(n, a), a)

**Any `range(a, b, step)` whose COUNT you ported with `round_up` is wrong**, and
`range` is everywhere in a runtime backend. Gate the COUNT and the LIST: the list
is what catches a wrong step, the count is what catches a wrong base.

### 4. A `Tr`-STYLE SUBSEQUENCE MATCHER NEEDS A FIXTURE THAT MATCHES **LATE**
The WebGPU template's M23 is about the FUEL being the pattern length, and its
fix was a reversed pattern -- which does NOT catch it, because a reversed pattern
fails under the broken matcher too. **The fixture that catches it is a
ONE-element pattern that occurs only at the END of the trace**: the good matcher
scans the whole trace, the broken one only ever looks at entry 0, so the row
flips. `mt_has_late` and `mt_has_late2` in `ops_metal.bend` are those two rows
and they are the only reason M16 moves 6 rows instead of 4.

### 5. A RULE PREDICATE CHAINED OFF THE WRONG RULE IS A SILENT REACHABILITY BUG
`pm_bufferize`'s three Metal rules are
`tag="mtl_sel"`, `tag="slots" + name="b"`, and `name="b"` with NO tag. The port
wrote `m1 = m0 && slots && named_b` and `m2 = m0 && named_b && icb`, and `m0`
carries `tag="mtl_sel"` -- so BOTH of them silently required the mtl_sel tag as
well and M2 answered 2 (the tail's answer) where the source answers 3. **A
predicate must state its own pattern's conjuncts; a shared prefix is only
sound when the patterns really are nested.** `device.py:403`'s own table has the
same shape (rules 2 and 3 carry the IDENTICAL pattern) and the file says so.

### 6. AN ADVANCE MUST HAPPEN ON A MISS TOO
A first-wins rule scan whose accumulator is `(arena, made, got, k)` returned the
accumulator UNCHANGED when a rule did not fire -- so the rule index never moved,
rule 0 was evaluated three times and rules 1 and 2 NEVER RAN. Every answer was
the tail's and every answer looked plausible. **The miss arm of a first-wins
`keep` has to carry the NEW index, the OLD arena, the OLD flag and the OLD
answer**; only the index changes. Two rows caught it: the answer and the arena
length, and the arena length is the one that says "nothing was allocated".

### 7. `Bool.pick` IS STRICT, SO A THREE-WAY CHOICE COSTS THREE ARMS
`q.submit.at` picks between three `run` paths and `Bool.pick` BUILDS all three.
That is correct (a trace is a pure list, so building three costs time and
nothing else) and it is worth a comment, because the instinct is that it is a
side effect. **A three-way choice over `U32` literals that are not 0/1/n is
REFUSED** (rule 34 at line 5182), so this is not a style question: two nested
`Bool.pick`s is the ONLY spelling available, and the two `Bool` guards are the
source's own words (`if not self.stamps`, `if n > 1`).

### 8. TWO SEPARATE LOOPS OVER THE SAME LIST ARE NOT INTERLEAVED
`:259 commands = [icb.indirectComputeCommandAtIndex(i).own() for i in ...]` and
then `:260 for cmd, (...) in zip(commands, cmds):` are TWO loops: every handle is
taken first and only then is each one set up. A gate pattern that interleaves
them (`icb0, retain0, pipeline0, icb1, retain1, ...`) is wrong about the source
and right about nothing, and it is a mistake you make while reading rather than
while typing. `mt_icb_cmd_order` is the row that pins the real order and M26e is
the mutation that moves it.

### 9. A COUNT ROW CANNOT SEE A SWAP, AND THE FIX IS AN ORDER ROW
`mt_icb_cmds` and `mt_icb_retain` are counts, so swapping
`indirectComputeCommandAtIndex` and `retain` moved 0 rows (M38). `mt_icb_cmd_order`
is the fix and it moves 2. **The general form: two calls of the same family whose
ORDER is the claim need one subsequence row, and the counts are then redundant
rather than load-bearing.**

### 10. A `do`-BLOCK BINDER NAMED `at` READS AS A NAMESPACE SELECTOR
`+at : Tr <- IO.pure(Tr, ...)` inside `do IO<Unit>:` fails with
`expected : List<&2, Call>, observed : Tr` -- an error that names a TYPE the
binder never mentions, because `x.at` is Bend's namespace selector and a `do`
binder spelled `at` is read as one. **Rename it (`t1`) and say why in the
comment**, because the next person will make the same edit. Same family as the
reserved names (rules 24, 25, 35, `do`): check `./bin/bend base --names` before
naming a binder after a selector.

### 11. `String.concat` DROPS A LITERAL SILENTLY, AND A GATE THAT PRINTS THE
    STRING BESIDE THE BOOLEAN IS THE ONLY THING THAT SEES IT
`mt_params` and the five `mt_msg_*` rows print the STRING, not a boolean about
it, and the oracle builds the same string from ops_metal.py's own f-string. Two
of the seven real bugs this gate found were found ONLY because the expectation is
generated by CALLING CPython: `csrc_pad` dropped a subtraction that no boolean
row about the pad would have named, and the ICB header rows were off by 24
because they hardcoded the first command's `off` where the source means `zero`.

### 12. A `mt`-STYLE TABLE OF `(k, sel, arg)` NEEDS THREE FIELDS, NOT ONE
`mtl_msg` is `ccall(MSGSEND[ret], obj, sel, *args)` and `sel` IS the identity of
the call; a DIRECT objc message is identified by its own kind. One field cannot
carry both, and two of the table's entries collide by NAME -- `commit` is the
command buffer's AND the residency set's, and `setComputePipelineState` is the
encoder's AND the ICB command's. So the record is `(k: U32, sel: U32, arg: U32)`
and the header says which half identifies which family. **A table of selector
NAMES is also the only place a `+` on a `String` is unavoidable**, because
`sel_ix` reads a name twice per row.

## THE FINDING THAT IS ABOUT THE PYTHON, NOT ABOUT BEND

`ops_metal.py:218`'s first `pm_bufferize` rule,
`UPat(Ops.PARAM, tag="slots", name="b")` -> `ctx.new_slots(b.max_numel()) if
b.max_numel() > 4 else None`, is **REDUNDANT with `device.py:404`'s second rule on
every input**: that rule is `UPat(Ops.PARAM, name="b")` -> a program Buffer, it
fires on every node the first one fires on, and it gives the same answer class
(2) and the same arena growth (one Buffer). Adding `tag="mtl_sel"` to the first
rule's predicate is an UNOBSERVABLE change -- mutation M26b moves 0 rows, and the
reason is in the source and not in the gate. **The only difference the first rule
can make is to fire LESS**, which is what its `> 4` guard does.

**The lesson, and it is the same one the `ops_disk` unit recorded:** a gate row
that cannot fail is not a row. Before designing a section for a conjunct,
ask whether a DIFFERENT RULE would have produced the same answer for the same
input, and if so the conjunct is documentation and the gate should say so in the
table rather than pretend otherwise.

## EIGHT MORE RULES, MEASURED 2026-10-02 WRITING `renderer/nir_llvmir.bend` (STAGE 1)

Appended, not edited, continuing the count from 37. Bend 2.0.34. Each one cost a
wrong answer that typechecked, checked in both lanes, and printed a plausible
string; every reproducer is in `.agents/slop/nl/`.

### 1. **`List.foldl`'s STEP IS A `~` TEMPLATE POSITION TOO, SO A PARTIAL APPLICATION IS NOT CLOSED**

The recorded form is "a `~` template position must be CLOSED, so a step that
captures a runtime value has to be a top-level def". The step is `f`, and `~f` is
in `List.foldl`'s signature, so a step that is a def CALL is refused:

```python
def step(k: U32) -> (List<&2, U32> -> U32 -> List<&2, U32>):
  acc => x => List.append(&2, U32, acc, [U32.add(x, k)])
def go(k: U32, xs: List<&2, U32>) -> List<&2, U32>:
  List.foldl(~&2, ~U32, ~List<&2, U32>, step(k), xs, Nil{})
#| - expected : a template applied to closed ~ arguments
#|               (k is a variable here, not comptime: pass it at run time)
```

`step(k)` is a def call and a call is not closed; `~k` cannot be spelled either.
**SO A FOLD THAT NEEDS A RUNTIME PARAMETER IN ITS STEP IS A HAND-ROLLED `.go`,
and the hand-rolled fold is shorter than the fight.** The same is true of
`List.map(~A, ~B, f, xs)` and `List.any`. This REFINES rather than retracts the
recorded rule: it says a step that needs a *captured* value is a top-level def,
and this says the def cannot be one you applied to an argument.

### 2. **`Bool.pick` IS STRICT, SO `Bool.pick(..., keep(d), ...)` RUNS `keep(d)` ON THE ELEMENTS IT KEEPS -- BUT A FILTER'S PREDICATE STILL HAS TO BE INSIDE THE ARM**

Two measurements on one filter, and they are different facts. `Bool.pick` being
strict is recorded; what is NOT recorded is that it makes a predicate ARGUMENT
run once per element for the elements it *keeps*, so the predicate must be a
parameter of the WALK rather than an argument of the `pick`. The shape that works
is `tc_ptx`'s keep-filter verbatim:

```python
def sd.cpu.go(+ts: List<&2, S.Dt>, +x86: Bool, +osx: Bool) -> List<&2, S.Dt>:
  match ts:
    case Nil{}   : Nil{}
    case h <> +t :
      +rest = sd.cpu.go(t, x86, osx)
      Bool.pick(List<&2, S.Dt>, Bool.not(sd.drop_cpu(h, x86, osx)), List.append(&2, S.Dt, [h], rest), rest)
```

**AND THE HALF THAT COST THE ROW: `Bool.pick` ANSWERS ITS SECOND ARGUMENT WHEN
THE CONDITION IS TRUE, so a KEEP filter is `Bool.pick(..., keep(d), [d] ++ rest,
rest)`.** Passing the predicate's own name (`drop(d)`) is the one-character
mistake that turns `supported_dtypes` into "the four fp8 dtypes" -- precisely the
set the filter removes. It typechecked, it ran, and it printed a plausible
dtype list; `sd cpullvm x86_64 osx=True` was the row.

### 3. **A RECURSION THAT RETURNS THE TRANSFORMED TAIL HAS NO ACCUMULATOR, SO A BRANCH THAT EMITS NOTHING RETURNS NOTHING AT ALL**

```python
def fp8_split2(+cs: List<&2, Char>, drop: Bool) -> String:      # the WRONG shape
  match cs:
    case Nil{}   : ""
    case +h <> +t :
      +rest = fp8_split2(t, fp8_is_colon(h))
      Bool.pick(String, Bool.and(drop, fp8_is_sp(h)), "", ...concat(rest))
```

This is `str.replace(": ", ":\n  ")` ported as a character walk, and the
"emit nothing" arm answered `""` for the **entire remainder**: a 1048-character
string came back as 57, and the rendered prefix was a perfectly plausible
three-line function header. The fix is one `acc` parameter, and the general form
is the notes' jit.bend rule 1: *a fold needs the accumulator even when every arm
looks like it returns something.* `+acc` on top of that, because both arms read it.

### 4. **A `match` ON A `String` PARAMETER WITH LITERAL ARMS AND A `case _:` COVER IS LEGAL AND IS WHAT A PYTHON `dict` OF NAMES PORTS TO**

`ldt`'s float arm is eight literals and a catch-all, dispatching on `nm`:

```python
def ldt.fp(nm: String) -> String:
  match nm:
    case "float8_e4m3": "i8"
    ...
    case _: "KeyError"
```

The recorded rule ("a `match` ON A `String` NEEDS THE ARM ORDER OF THE LITERAL")
is about a ladder of DISTINCT keys and a missing arm: here every key is spelled
and the catch-all is last, which is exactly the shape that rule prescribes.
`CHECK` on 2.0.34, and it is the natural port of a `{dtype.name: name}` dict that
a `Data` record cannot hold.

### 5. **`List.concat` IS `(a, A, xss: List<a, List<a, A>>) -> List<a, A>` -- IT TAKES A LIST OF LISTS, NOT TWO LISTS**

Not in the ledger, and the error is
`expected : List<&2, List<&2, S.Dt>> / observed : List<&2, S.Dt>` at the CALL, so
it reads like an arity error on the element type. `List.append(a, A, xs, ys)` is
`xs ++ ys` and is the binary one; `List.concat` is the unary one. To join two
lists: `List.concat(&2, T, [xs, ys])`.

### 6. **AN INSERTION SORT'S ELSE ARM MUST CARRY THE HEAD, AND THE HEAD IS ALREADY IN THE RECURSION'S ANSWER -- SO THE ARM IS `[x,h] ++ rest` OR `[h,x] ++ rest`**

Measured twice on the same def, and both wrong versions `ALL PROOFS CHECK` and
produced a **thirteen-slot list with five duplicates in it**:

* returning `rest` on the else arm DROPS every element that lost a comparison;
* building `[x, h] ++ rest` where `rest` already carries `x` DUPLICATES `x`.

The shape that works is `jit`'s `srt_ins` -- the whole `Bool.pick` inline with
`+h <> +t` binders -- and the rule is that `rest` is the sorted tail PLUS `x`, so
the arm only decides which side of `h` `x` lands on. **A sorted-name row is the
only thing that catches either bug: `code_for_op.len` stayed GREEN through both**,
because the list really did have thirteen slots.

### 7. **`List.get` ANSWERS A `Maybe`, AND `Maybe.default`'s DEFAULT MAKES A MISSING ELEMENT AND AN EMPTY STRING THE SAME ROW**

Measured while truncating a generated oracle. `nth(xs, i)` is
`Maybe.default(&2, String, List.get(&2, String, xs, U32.to_nat(i)), "")`, and
that `""` means a row indexed past the end of a list is INDISTINGUISHABLE from a
row whose value is the empty string. `barrier` ends in a newline, so
`barrier.split("\n")` yields four pieces and the fourth is `""` -- and dropping it
moved `barrier.lines` and NOTHING ELSE, because `barrier[3]` reads `""` either
way. **This is rule jit.bend 9 ("when one printer serves both 'no answer' and an
answer", the rows are not independent) in a new place**: the fix is a count row,
and here the count row was the ONLY witness of a dropped element.

### 8. **`List` ELEMENT LITERALS IN A RECORD FIELD ARE `&1` UNLESS A HELPER'S RETURN TYPE SAYS OTHERWISE** (restatement, re-measured)

`Llvm{..., gmax: [2415919103, 2415919103, 2415919103], ...}` is
`expected : List<&2, U32> / observed : List<&1, U32>` with the caret on the
element, and jit.bend rule 6 already records it. The instance that cost a cycle
here is worth the restatement because the field is the SECOND of nine: the error
names the element type and nothing else, and the fix is in a def three hundred
lines away (`Llvm_of`'s return type).

---

**THE GENERATED-ORACLE PATTERN, which is what made this stage's gate worth
anything.** `.agents/slop/nl/nl-oracle.py` has TWO modes: `rows` prints the gate
text (`<name> = [BEND]   py=[CPYTHON]`, computed by calling live CPython) and
`bend` prints the **row-builder source for the .bend file** from the same run.
The generated text is pasted verbatim into the port under a header that says how
to regenerate it. So a `py=` literal cannot be typed, cannot be stale, and cannot
disagree with the oracle -- and the first draft's five bugs (M1, M27, M28, M35 and
the `count` arm) were all found by a byte diff that no amount of reading would
have run. **The generalisation: for any port whose gate is a string diff, write
the oracle's second mode first.** It costs one `def emit(...)` and it removes the
entire class of "the expectation was wrong" findings -- which `cstyle.bend`
measured at 17 of 215.

## 37. AN ASSOC-LIST PUT WHOSE MISS ARM RETURNS THE TAIL IS A SILENT `del`

A `dict[k] = v` port is a cons walk with a Bool arm, and the shape that falls out
first is "found -> rewrite, not found -> recurse past it". **That not-found arm
must carry the whole walked PREFIX, not the tail**, because returning the tail
drops every key before the miss. Measured on `tinybendygrad/codegen/late.bend`'s
`tb_ins.go`, where the miss arm was `r`:

    def tb_ins.go(+pre, +k, +v, +vs, rest) -> List<&2, RaEn>:
      match rest:
        case Nil{}  : List.append(&2, RaEn, [RaEn{k, v, vs}], rest)
        case +e <> +r : Bool.pick(..., <rewrite in place>, r)     # <-- the `del`

Symptom: the table answers correctly for every key that SURVIVED and the second
`put` empties it. A `tb_keys` probe printed `[12]` for one key and `[]` for two.
**The general form: a replace-or-append walk is `cons(head, rec(tail))`, never
`rec(tail)` -- and the same mistake in an accumulator walk is a silent truncation,
not a crash.** Two of the seven table types in that file had it and one did not,
which is the signature of a shape that looks right.

## 38. `Bool.and` / `Bool.or` DO NOT SHORT-CIRCUIT, SO PYTHON'S `or` IS A `Bool.pick`

`x.op is Ops.SINK or u.src[1] in deps[x]` (linearizer.py:68) is a short-circuit `or`.
`Bool.or(a, b)` evaluates BOTH sides, and `Bool.and(False, anything)` is False, so
the whole predicate becomes False for every SINK -- and a SINK is where the edges
come from. `cfg_edges` printed nothing. The fix is `Bool.pick` used as a VALUE
CHOICE:

    def cfg_nest.dep(+ar, +c, +u, +x) -> Bool:
      Bool.pick(Bool, lt_is_sink(O.Arena.op(ar, u)), True{},
                List.contains(U32, U32.is_eq, tb_vs(Cfg.dp(c), x), O.Arena.src(ar, u, 1)))

**The general form: `A or B` where `B` is expensive, ill-defined on some inputs, or
has a side effect is `Bool.pick(cond, true, B)`, never `Bool.or`.** The discarded
branch still runs -- that is the price -- so this only fixes a FALSE being folded
in, not a wasted evaluation.

## 39. A `Bool.pick` CANNOT GATE A MUTATING CALL, AND A `match` CANNOT BRANCH ON A CALL

Two restrictions meet at `continue`:

* `Bool.pick(T, c, a, b)` evaluates BOTH arms, so `Bool.pick(RaSt, skip, s,
  fill(v, i, s))` runs `fill` on the skip path -- and `fill` calls `alloc`, which
  POPS out of `live`, so the skip path corrupts the state.
* `match` may scrutinise only a PARAMETER or a pattern BINDER, never a call, so
  `match lt_arm(skip):` is refused with "a parameter or field scrutinee (a match
  cannot scrutinize a computed value: give it its own def)".

The shape that works is a **one-field record carrying the verdict**, computed by a
leaf, handed to the branching def as a PARAMETER, and destructured as a BINDER:

    type Lt2 is Data: Lt2{go: Bool}
    def ra_prol.arm(ins: RaTb, c: List<&2, U32>) -> Lt2:
      Bool.pick(Lt2, ra_subset(ins, c, True{}), Lt2{True{}}, Lt2{False{}})
    def ra_prol.one(arm: Lt2, c: List<&2, U32>, +v: U32, s: RaSt, cx: RaCx, +i: U32) -> RaSt:
      match arm:
        case Lt2{go}: Bool.pick(RaSt, go, <the mutation>, s)

A one-element `List<&2, Bool>` works for the same reason and costs a list. **The
general form: any `if c: <effectful> else <state>` becomes (1) a leaf that turns `c`
into a one-field `Data` record, (2) a def that takes the RECORD as a parameter, and
(3) a `match` on the binder whose arms are `Bool.pick`s over the state.** The same
trick is the only way to get a *computed* branch, and it composes with rule 33.

## 40. A `Bool` BARE PARAM IS LONE; A `Bool` `+` PARAM IS DROPPABLE, AND THAT IS THE ONLY WAY TO READ IT TWICE

The reported error is "expected : b / observed : b (consumed more than once)" and
the fix is `+b`. It bites every `Bool.pick`, because the two arms both run: **any
value mentioned in both arms of a `Bool.pick` must be `+`**, and the message names
the value, not the def. Measured: 60-odd defs in one file, and the first draft
annotated almost none of them.

The two are NOT the same, and the difference is the whole of rule 35's second half:
`+` means DROPPABLE, so a `+` value MAY be duplicated. `List.sort`'s comparator,
by contrast, is typed `@a -> @b -> Bool` with NO annotation, and a `+` there is
refused:

    expected : @_:Sb -> @_:Sb -> Bool
    observed : @a:Sb -> @+b:Sb -> Bool

**So a comparator must read each of its two arguments EXACTLY ONCE, which is why
every composite key in this codebase is packed into a single `U32` first**
(`lt_key` = `rc * 64 + offset`, `cfg_order`/`se_sort` = an axis id, the drafted
`sorted_uses` = `d * 2^20 + f * 2^10 + r`). A lexicographic chain over three
fields cannot be a comparator; `def ra_su.lex(a: Sk, b: Sk)` reading `Sk.d(a)` twice
is refused and the honest fix is the pack, with its bound stated in the header.

## 41. A `match` ARM LIST MUST COVER THE WALK LIST'S WHOLE SHAPE, AND A 3-ELEMENT CONS COVER IS NOT OBVIOUS

`cfg_edge` walks `zip`'s pairs and the first draft had

    case Nil{}         : ed
    case +x <> +y <> +r : ...
    case _ <> _        : ed

which does not elaborate: bend reports **"expected : cases for Nil"** for the
`case Nil{}` arm that is TEXTUALLY FIRST, and names `{}` as the observed term --
so the message points at the wrong arm and the real problem is the cover. Notes
7 and 6 already record that `case _ <>` cannot cover `Nil{}` and that `case _ <> _`
is the only CONS cover; what is new here is that **a 3-element cover
(`x <> y <> r`) does not obviously cover the 1- and 2-element lists, and the honest
shape is `List.is_empty` on the tail plus a 2-element pattern**:

    case +x <> +r : Bool.pick(RaTb, List.is_empty(&2, U32, r), ed, <recurse>)

## 42. A `List` ACCUMULATOR WALK NEEDS THE SHRINKING ARGUMENT BEFORE ANY COMPUTED ONE

bend's termination check reads a self-call's arguments LEFT TO RIGHT and wants
every argument before the first shrinking one to be UNCHANGED. So

    case +v <> +r : lt_deg(loops, ra_lr.put(loops, lr, v), r)      # REFUSED
    case +v <> +r : lt_deg(loops, r, ra_lr.put(loops, lr, v))      # accepted

with the error "expected : a decreasing self-call (arguments are read left to
right: each passed unchanged until one shrinks)". This is rules 5 (DUP) with
the part that is easy to miss: it is not "put the walk list first", it is **"put
the SHRINKING BINDER before the first CALL"**, and a fold's accumulator is a call.
Five drafted folds in `late.bend` needed re-ordering for it, and the ones that
already worked all had the shape `<unchanged...>, <binder>, <computed...>`.

## 43. A MULTI-LINE RECORD LITERAL OR CALL IS REFUSED, AND THE ERROR POINTS AT THE CLOSING BRACE

`Sb{cfg_cnt(vs, deps, x, 0),\n     x}` and
`[O.PMEntry{0, List.append(...,\n   [...])}]` both give "expected : a term,
observed : '}'" or "expected : a term (the keyword 'def' cannot head one), observed
: 'def'" at the NEXT definition. **So a record literal and a call inside one are
each single-line in this Bend**, and the fix is a leaf that takes the parts
(`ra_su_key.pack`) rather than a continuation indent. Related and cheaper: a
`match` scrutinee that is a CALL fails even when the call returns the right type,
which is rule 34.

## 44. A `U32` FIELD CANNOT BE NEGATED, SO A PYTHON `default=-1` / `default=None` IS A SENTINEL AND THE SENTINEL MUST NOT BE A LEGAL KEY

`linearizer.py`'s `extra` is `u.arg.slot or None`, `regalloc.py`'s `rdef` is `None or
a Register`, and `x.replace` keeps `arg` -- all of them "a `U32` that is not
meaningful". `0xFFFFFFFF` works because it is a value no table in this file stores
as a KEY, and the file names it `u32_none()` after `UOp.is_none`. But the
sentinel then has to be REJECTED everywhere a real value is compared: `ra_is_reg`
is `!= u32_none()` and `List.contains` against a real register list rejects it
without a second test. **The general form: a "None" in a `U32` field needs (1) a
sentinel outside the key space, (2) a named predicate for "is a value", and (3)
every comparison against a real list to go through (2) -- and a `Bool.pick` that
folds a sentinel into a membership test is a silent extra edge.**

## 45. `Bool.pick(A, c, a, b)` ANSWERS `a` WHEN `c` IS TRUE -- SO IT REPLACES, IT DOES NOT EXTEND

Measured while porting `runtime/ops_nv.py`. Three separate bugs in one file came
from the same three-word slip, and it is worth naming because the mistake looks
like an append:

    Bool.pick(List<&2, Call>, refused, calls, List.append(&2, Call, calls, new))

is CORRECT (the guard picks the old list when `refused`) and

    Bool.pick(List<&2, Call>, refused, calls, new)

is "append nothing when refused" -- which a reader expects -- and is actually
"REPLACE the trace with the new call". `ops_nv.bend`'s first `nvm.emit.go` was
the second form and `nv_sem_signal` printed only the `NON_STALL_INTERRUPT`: the
semaphore's four words were gone and the boolean rows were all still True. The
general rule: **`Bool.pick` is a selector, so any arm that reads a value the
other arm also reads must build the WHOLE value.** When one arm extends the other,
the extension goes INSIDE the arm.

## 46. A `match` ON A `Nat` COUNTDOWN MAY NOT READ ITS OWN FUEL, BUT A `U32` INDEX MAY BE READED BY A `.pick` THAT IS INSIDE THE ARM

The counterexample that costs the most time is not a rule, it is a SHAPE. A first-
wins scan whose answer is "the index of the match, or the list length if there is
none" cannot be written with a `got` accumulator seeded at 0, because 0 is a
LEGAL index and `found < len(keys)` then reads a miss as a hit at index 0. Two
facts together:

* the accumulator is seeded with `len(list)` and the MATCH SETS IT to the current
  index, so a later non-match keeps it (first-wins falls out for free), and
* the hit test becomes `found < len(list)` and not `found != 0`.

`pc.find` in `ops_nv.bend` is the worked example and `nv_pc_grow_3` is the row
that died. The shape generalises to every "which entry does this key name"
question, and the wrong version passes every boolean row about membership.

## 47. `U32.shrn(a, n)` IS `a >> n` -- THE INDEX IS THE SHIFT, NOT THE SHIFT PLUS ONE

`arch_low` and `sass_of` both wanted `>> 4` and both were written `U32.shrn(x,
1n)`, which halves. Nothing catches it: the interpreter and the compiler AGREE
(`F32.to_u32`'s two-lane disagreement at line 3166 is a DIFFERENT pair of lanes),
and `sm_version >> 8` -- which is `shrn(x, 8n)` -- is right, so the mistake looks
confirmed by a neighbouring correct use. `nv_arch_89=sm_068` versus CPython's
`sm_08` is the whole measurement: 137 >> 1 rather than 137 >> 4. Related: the
notes at 4702 say `U32.shln(a, 0n) = a`, and this says the same for `shrn`; both
are the "the index IS the shift" convention.

## 48. A SECOND `def X.of` FOR A RECORD NOBODY USES IS A DUPLICATE DECLARATION, NOT A LATER-WINS

Rewriting a `Data` record's readers in place (`PC{n: ...}` to `PC{cnt: ...}`)
and leaving the old block behind gives "expected : a fresh name (duplicate
declaration: X.of)" naming a line that looks fine in isolation. The recovery is
to delete the OLD SPAN by line range and re-check, not to rename the new one:
a rename leaves two readers and the surviving one is whichever the linker saw
last, which is the one you just wrote and the one that does not compile.

## 49. A `Data` RECORD'S READER CANNOT BE NAMED AFTER ITS FIELD

`type PC is Data: PC{n: U32, ...}` with `def PC.n(p: PC) -> U32` is REFUSED with
"expected : a fresh name", and the message does not say why. It is the same rule
as rule 38 (a binder shadowing a field name), one level out: the reader and the
field live in the same namespace for the checker. `Bn` and `RL` avoid it by naming
the fields `size`/`off`/`shift` and the readers `Bn.size`/`Rl.shift` -- which is
only legal because the field is `off` and the reader is `off`; `PC.n` is not, and
the fields became `cnt`/`uid`/`misses`/`hits`/`keys`/`ords`.
---

## APPENDED 2026-10-02 by the `ops_cpu_null` port. NUMBERS CONTINUE FROM 49.

Ten rules, all measured in `tinybendygrad/runtime/ops_cpu_null.bend` (the port
of `tinygrad/runtime/ops_cpu.py` + `ops_null.py`). Reproducers are the three-lane
gate the file ends with: `./bin/bend <file>`, `./bin/bend -o /tmp/x <file>` and
a CPython oracle, diffed row by row.

### 50. `h <> t` CONSES **ONE ELEMENT**: `[a, b] <> xs` IS A TYPE ERROR, AND THERE IS NO `List.cons`

The one I lost the most time to. In `nprog.streams.go` the obvious mutation of
`List.append(&2, U32, ps, [ix, sz])` is `[ix, sz] <> ps`, and it is REFUSED with
`expected : U32` / `observed : List` pointing at the literal. `<>` is
`cons(&n, T, head, tail)` with `head: T`; a two-element list is not a `T`. The
mutation that expresses the same thing is `ix <> (sz <> ps)`.

There is also **no `List.cons`** to reach for: `List.cons(&2, U32, 0, xs)` gives
`expected : a defined name`. `<>` is the only spelling. And `List.show` is not
`(A, List<&n, A>) -> String` either -- a probe that prints with it fails with
`expected : U32 -> String` before reaching the real complaint.

### 51. A LITERAL `True{}`/`False{}` IN A LATER `Bool` SLOT OF A CALL IS A PARSE ERROR REPORTED AT THE **ARGUMENT**

`prog.init(True{}, True{}, ..., False{}, False{})` fails at the argument with a
caret under an earlier one. Two named constants (`fx_win()`, `fx_remote()`) and
it compiles. Anything past the first `Bool` slot is where it breaks, which makes
the reported position useless for finding the literal. **Bind the booleans.**

### 52. A NESTED CALL INSIDE `Bool.not(...)` BREAKS THE PARSER; INSIDE `Bool.pick(...)` IT IS FINE

`Bool.not(seq(Prog.t(p), [Call{...}]))` refuses; `Bool.pick(List<&2, U32>, c,
List.append(...), ps)` -- a call in an arm -- has been in every file here for
weeks. The difference is the ARITY: `Bool.not` takes one term and the parser
treats the argument as a pattern; `Bool.pick` takes four and does not. Bind the
inner value with `+` locals first.

This is the precise boundary of the rule at the old #39 ("a `match` cannot branch
on a call"), and it is narrower than that rule reads: the prohibition is on
`match` scrutinees and on single-argument wrappers, not on `Bool.pick` arms.

### 53. `Bool.pick(T, c, a, b)` ANSWERS `a` WHEN `c` -- SO THE FALSE ARM IS THE CONTINUATION, NOT THE RESET

Half an hour went into `nr.zero_of.go`, where `got` is an accumulator and the
outer pick reads `Bool.pick(U32, U32.is_zero(got), <inner>, got)`. Writing `0`
for the last argument -- which reads as "not found yet, so reset" -- makes the
fold forget every hit on the next row and answers the not-found value for
**every** name in the table at once. Thirteen rows moved together, which is the
only reason it was caught. `Bool.pick` is a pick, not a fold.

### 54. NO IMPLICIT `Bool` -> `U32`: `U32.add(x, Bool.to_u32(b))` IS THE ONLY SPELLING, AND `U32.mul`/`or`/`and` NEED `(a op b : T)`

`U32.add(got, Bool.to_u32(...))` is fine; `U32.add(got, b)` is `expected : U32`
/ `observed : Bool`. Separately the bare infix forms refuse without a type
ascription: `U32.and(a, b)`, `U32.or(a, b)` and `U32.mul(a, b)` are all fine as
calls, and `a | b` / `a & b` / `a * b` are all REFUSED without `(a | b : U32)`.
`U32.add` and `U32.sub` are the two that do not need it. There is no pattern
here, which is why it costs the same every time.

### 55. `Nat` LITERALS CAP AT `4294967295n` -- FACTOR THEM

`itertools.count(1 << 40, 1 << 32)` ports as `Nat.mul(1024n, 1073741824n)` and
`Nat.mul(2n, 2147483648n)`. Writing `1099511627776n` fails. The factors must each
fit, so a 64-bit value needs the base in units of `2^30` or `2^32`. This is the
only place in this port where the 64-bit wall does not bite.

### 56. A MULTI-LINE CALL EXPRESSION CANNOT BE THE RIGHT-HAND SIDE OF A `<-` BIND

```
p : X <-
  f(a,
    b)
```
is a parse error at the following line. A single-line call is fine; so is
splitting the arguments into `+` locals first and binding the single-line result.
The same restriction applies to a `def` body written as a bare call spanning
lines -- split it into the `match` form the compiler wants.

### 57. A `match` THAT WRITES TWO ARMS WHICH ARE THE SAME CALL IS A REDUNDANCY, NOT A DECISION

`cpu.rt_lib_name` was three arms:
`case True{} _ : "System"` / `case False{} True{} : cpu.rt_lib_name.os(win)` /
`case False{} False{} : cpu.rt_lib_name.os(win)`. The lower two are the same
expression, and the mutation "replace the WIN arm with its literal" moved no row
-- correctly, because it is an equivalence. Two `Bool.pick`s are 3 lines where
the `match` was 6, and the mutation then moves a row. **A `match` arm that is
another arm is a `Bool.pick` that has not been noticed yet.**

### 58. A MATCHER THAT IS ONLY EVER ASKED TO **REJECT** ANSWERS `False` FOR EVERY FUEL

This is `ops_webgpu.bend`'s old M23, reintroduced and STILL not caught here. The
fuel of `Tr.has.go` was the pattern length instead of the trace length. The gate
had two rows and both were rejections:
`Bool.not(seq(trace, [FXN, PROFILE]))` and `Bool.not(seq(trace, [PING]))`. With
the fuel truncated to `len(pat)` the walk reads the first `len(pat)` calls, which
for a two-call pattern is one call, which cannot match a two-call pattern -- so it
answers `False`, which is what the rows demanded. **Both rows pass.**

The row that kills it is a one-call pattern at index 1 of a two-call trace: real
answer `True`, short fuel cannot reach index 1. Three rows were added
(`cpu_has_accepts_plain`, `cpu_has_accepts_lvp`, `cpu_has_rejects_wrong_arg`) and
the mutation then moves two of them. The general form: **a predicate needs a row
that says `True` before its rows mean anything.**

### 59. A `Bool.pick` GUARD THAT IS `is_zero(acc)` MAKES "FIRST WINS" **UNTESTABLE** WHEN NO TWO TABLE KEYS ARE EQUAL

Two folds here -- `EvA.step` and `nr.zero_of.go` -- carry an accumulator plus an
`is_zero` guard, which is "first wins". Flipping either to last-wins moved **no
row**, and that is not a hole in the gate: `Nk.same` IS Python's tuple equality
and `null_events` is a dict, so it never holds two equal keys; the thirteen zero
table names are thirteen separately measured ops, so at most one matches. Given
"no equal pair", first-wins and last-wins are the same function.

The lesson is about the TABLE, not the fold: **before writing a row for a
first/last-wins fold, check that two equal keys are reachable. If they are not,
the fold is a redundancy the source's data structure already made unreachable,
and the honest note says so.** Planting a duplicate key to make the mutation bite
would assert a state the program cannot be in.

### 60. THE DEAD-DEF AUDIT IS THREE LINES OF REGEX AND IT FINDS REAL DEAD CODE

Ten defs in this file had **no reference from any gate row**, and nine of them
were genuinely unreachable from `main` (`Tr.next`, `nr.nwords`, `ndev.encode_n`,
`ndev.renderers_n`, `nr.ts_offset`, `nr.submit_root`, `nprog.event_ids`,
`nprog.evs.go`, `ref`, `cpu.mem_commit`/`cpu.mem_reserve`). Two were constants
whose rows read the LIST instead of the def, so the def was a restatement of a
number that could drift; one was an alias (`ref` for `key`).

The closure that works: strip comments, split top-level `def` blocks, map every
token to its block (last dotted segment is the key -- namespaced defs are
`mod.leaf` and the leaf is unique per file here), BFS from `main`, diff. Do NOT
report "short name not in a row name" as unreachability: gate rows are named
`cpu_arch_amd64`, not `cpu.arch_of`, so every namespaced def looks dead.

Two of the finds turned into quality wins rather than deletions. `Tr.next` was a
second field in the trace record whose rewind nothing could observe, so it was
replaced by `List.length(&2, Call, Tr.calls(t))` -- one fewer field, one fewer
invariant, and the mutation that broke the rewind became inexpressible. The other
two constants were wired to the expression they were standing in for
(`cpu.wr_flags = page_xrw | mem_commit | mem_reserve`, `Nul.enc` holding the
name LIST rather than its length).

### 61. A GATE ROW IS NOT A TEST. IT IS AN ORACLE DIFF, AND ITS VALUE IS THE POINT

Every row here is `name=value`, and the value comes from CPython. A row that
asserts "the port agrees with itself" is a tautology: `--check-only` passes,
`./bin/bend` and the oracle both print it, and a wrong port that was written to
match its own mistake is green three ways. The mutation table is what makes the
rows mean something -- a row no mutation can move is a row that documents an
assumption and nothing else.

Which brings up the shape that DID work here: **three lanes, byte-identical.**
`./bin/bend f.bend` (interpreted), `./bin/bend -o /tmp/x f.bend && /tmp/x`
(native), and `python3 -c` against the real modules. 308 rows, `diff` clean. The
native lane is not redundant with the interpreter -- they compile the same source
by different routes and have caught each other.
## APPENDED 2026-10-02 by the `ops_cl` port. NUMBERS CONTINUE FROM 61.

Three files, one device: `ops_cl.py` (130 lines), `ops_cuda.py` (136),
`ops_hip.py` (71) -> `tinybendygrad/runtime/ops_cl.bend`. No `@extern` seams (a
deliberate departure from `dtype.bend`): the TRACE is the seam, and
`vend.name(vendor, op)` reads each trace entry back as its C symbol, which is why
`--check-only` stays GREEN and the gate can run at all.

Three lanes, 447 rows, `diff` clean: `./bin/bend f.bend`,
`./bin/bend -o /tmp/x f.bend && /tmp/x`, and a CPython oracle that imports
`autogen.opencl` / `autogen.cuda` with NO device present. 50 mutations, 47 move
at least one row, 1 control, 2 blind spots.

### 62. A TABLE INDEXED BY OP CANNOT BE SELF-CHECKED BY ITS OWN CONSISTENCY. KEY IT BY SYMBOL

The vendor table is `List<String>` indexed by op, one list per vendor. Three
transcriptions of the same table were made -- the port (indexed by op), the
oracle (keyed by symbol, `SYM2OP`), and the `NOT_A_CALL` allowlist (from a regex
over the sources) -- and they AGREED on a wrong index for two months' worth of
reasoning: `cuModuleLoadData` and `hipModuleLoadData` were at `OP_BUILD` (12)
while `clCreateProgramWithBinary` was at `OP_PRG_FROM_BIN` (11), so the emitted
trace printed `(128)` with an EMPTY name where the module load belonged.

Two things fixed it, and both are worth the ink:

* **the trace reads the table back**. `vend.trace` prints `vend.name(v,
  Call.op(c))`, so a cell that does not agree with the emitter that writes it
  prints `""` and the row is a hole in a trace somebody is reading by eye.
* **scan the sources and CLAIM every symbol**. The oracle regexes
  `\bcl\.([A-Za-z_]\w*)` out of the three files and asserts every hit is either in
  the table or in `NOT_A_CALL`. That assertion found 11 unclaimed symbols on the
  first run -- all typedefs and enum members -- and after that any real symbol
  that is not claimed is a FAILURE, not an omission. An allowlist is a claim about
  the world; it has to be checked against the world.

The second finding is about the *shape* of the allowlist. `hipMemcpyHostToDevice`
and `hipMemcpyDeviceToHost` are NOT calls -- they are `hipMemcpyKind` members --
and the first version of the oracle put them nowhere. The lesson: for a
`is not a call` list, ask "what does this name DENOTE", not "does this name look
like a function".

### 63. A PYTHON F-STRING IS NOT A TABLE. `"c_int%d" % bits` IS TOTAL

`getattr(ctypes, f"c_int{dt.bitsize}")` was ported as a four-way match on
`{8, 16, 32, 64}` with everything else answering `"c_int32"`. It printed
`c_int32` for a 7-bit dtype; CPython prints `c_int7`. The whole port is

```
def ct.typename(bits: U32) -> String: String.concat(["c_int", u32_dec(bits)])
```

eleven lines and a `Nat` ladder deleted, and it is now correct on the WHOLE `U32`
domain rather than at four points. The mutation `ct-typename-four-way` reinstates
the table and moves exactly one row, `ct_int7` -- which is the row that exists
only because the four-way reading was wrong once already.

The gate row that pins it must be OFF-GRID. `ct_int8/16/32/64` are satisfied by
both readings. A table that is wrong only off-grid needs a fixture off-grid.

### 64. THE BASE COMES OFF THE FOLD'S LAST STEP, NEVER ITS FIRST

`cu:104-105`'s `size = max([o + w.dtype.itemsize ...], default=8) - 8` was ported
as a fold that subtracted 8 on EVERY step:

```
def cu.launch_size.at(+end, +best) -> U32:
  U32.sub(Bool.pick(U32, U32.is_lt(best, end), end, best), CU_KERNARGS_BASE())
```

which is `max(ends) - 8` only when the maximum happens to arrive last. Fed
`[40, 12, 24]` it answers 16. Two rows catch it -- `cu_size_unsorted` (32, not 16)
and `cu_size_empty` (0, not 8) -- and the second one is the giveaway that the
`default=8` was never a `default` at all: it is an initial ACCUMULATOR, so the
subtraction belongs to the terminal arm.

**A `default` in a `max`/`min` is an initial accumulator. It is not a zero case
you can peel off at the end and it is not a guard you can put in front.**

### 65. A `+` PARAMETER IS CONSUMED ONCE. A PLAIN ONE TOO

`Bool.or(Bool.not(has_host), Bool.not(aligned))` compiles only if `has_host`
appears once. Reading it twice is

```
- expected : has_host
- observed : has_host (consumed more than once)
```

and the fix is a rebind, `+hh = has_host`, which then also forces the rebind to be
read -- so `no_host` has to be its own name rather than a second `Bool.not(hh)`.
Four `U32`/`Bool` shapes in this file were written this way (`cu.map_err.at`,
`hp.fields.at`, and each one has a mutation that would otherwise have been a
silent "consumed more than once" compile error rather than a value diff.

### 66. A `SIG` FIELD ORDER THAT NAMES ITSELF WRONG WILL BE "FIXED" BACKWARDS

`Sig{..., w, h}` with `w` = `shape[0]` and `h` = `shape[1]`: the field names say
the opposite of what `img.desc_w` (which reads `Sig.h`) proves they are. Reading
`cl.pitch` -- `(round_up(shape[1], 256) if OSX else shape[1]) * 4 * dt.itemsize`
-- "shape[1] is the width and `cl.pitch` rounds `h`, so it is wrong" is a
plausible, confident, and incorrect repair, and the oracle can be transposed in
the same direction at the same time, which is exactly what happened.

The fix is not a comment, it is the NAMES: `Sig{..., h, w}`, `Sig.w` = `shape[1]`,
`Sig.h` = `shape[0]`, `img.desc_w = Sig.w`. Then `cl_pitch_osx_257_4` and
`cl_pitch_osx_4_257` are 2048 and 4096 -- a pair of fixtures that differ ONLY in
which extent is 257, so the transposition is inexpressible.

**When two rules read the same field, one fixture per ORIENTATION is the gate.
One fixture plus two rules is a coin flip.**

### 67. A `dict.get(k, d)` INSIDE AN F-STRING HAS NO TEST TO PORT

cl:18 is `f"OpenCL Error {status}: {cl_errors.get(status, 'Unknown error')}"`.
The first port added a `Bool` test -- `.get(status) is not None` -- and picked
between `cl_err_of(status)` and the default string. Both arms are EQUAL: when the
test is false, `cl_err_of` IS the default string. So the pick was a tautology, the
test was dead, and `cl_err_msg` was four lines where one `String.concat` does.

MEASURED: the mutation `cl-err-msg-readds-default-pick` reinstates the pick and
moves ZERO of the 447 rows -- `cl_err_p999` prints `OpenCL Error 999: Unknown
error` either way. A default that is the lookup's OWN default is not a branch. The
same held for `cu_err_msg`, and `cl_err_hit` / `cu_err_hit` were deleted with them.

### 68. ONE-BASED ORDINALS MAKE THE `bad_at != 0` CONJUNCT DEAD CODE

`Tr.hit` was `and(not(is_zero(bad_at)), is_eq(add(hits, 1), bad_at))`. The
ordinals are one-based, so `bad_at = 0` -- the value `Tr.of` starts with -- is
compared against `hits + 1 >= 1` and can never be equal. The conjunct is
unreachable-by-construction; the mutation `tr-hit-readds-dead-conjunct` puts it
back and moves nothing. Deleted, with the reasoning in the comment so the next
reader does not add it back as a guard.

**If "never" is the ZERO of your counter, say so in the type's comment, because
the guard that expresses it is not free and is not observable.**

### 69. A `List.append` FOLD MUST NOT `List.reverse` AT THE END

Both `iter_sig.go` and `hp_buf_offsets.go` built with `List.append(&2, U32, acc,
[x])` -- which APPENDS -- and then answered `List.reverse(&2, U32, acc)` at the
terminal arm. Every offset list was backwards: `hp_val_offsets_3_32` printed
`36,32,28,24` where CPython's `TinyELF.iter_sig` yields `24,28,32,36`. Five rows
moved once this was found (`hp_buf_offsets_3`, `hp_val_offsets_3_32`,
`hp_val_offsets_3_mixed`, `hp_val_offsets_1_mixed`, `hp_val_offsets_2_odd`).

The two ways to build a list in Bend have OPPOSITE names' intuitions: `x <> rest`
CONSES (so a forward walk must reverse) and `List.append(xs, [x])` APPENDS (so it
must not). The mutation table makes the cost visible: `vend-trace-reversed` and
`arg-strs-reversed` are both one edit and both move 3+ rows.

### 70. THE BRANCH KEY MAY NOT BE THE FLAG YOU NAMED THE ARGUMENT AFTER

`cu._map` was ported as `cu.map_err(device, has_host, aligned)` on the reasoning
that "no host interface" is the message. cu:86's `if host is None` is INSIDE
`if buf.device.startswith("CUDA")`, and cu:87 RETURNS before the alignment
question is ever asked -- so a CUDA device WITH a host raises nothing, and a
NON-CUDA device with NO host raises the ALIGNMENT message (cu:88's `or`). The
discriminator is the device NAME. Three arguments cannot express it; the signature
is `cu.map_err(device, is_cuda, has_host, aligned)` and the gate pins all six
cases, two of which refuse and four of which are `""`.

`cu-map-err-keyed-on-host` (swapping `is_cuda` and `aligned` in the def) moves
ONE row out of six. A permutation that only shows up on one case of six is worth
six rows, not one.

### 71. `len(fields)` IS THE SUM OF BOTH LISTS, AND THE LAST FIELD IS THE ONE THAT COUNTS

hp:42 is `init_c_struct_t(fields[-1][2] + ctypes.sizeof(fields[-1][1]) if
len(fields) else 0, ...)` over `fields = [f{i} ...] + [v{i} ...]`. Two mistakes
were live at once: the emptiness test read the BUFFER count (`nf`) where the
Python reads `len(fields)`, and the "last offset" came from the value list even
when the value list was empty (so a buffers-only signature answered 0 where the
Python answers `nf*8`). `hp.fields` now takes `(nf, iszs)`, works the choice once,
and the gate has a row for each arm: `hp_fields_0_empty` (0), `hp_fields_3_novals`
(24), `hp_fields_0_1val` (4), `hp_fields_1_1val` (9).

### 72. A MUTATION THAT COMPILES IS A WEAKER KILL THAN ONE THAT MOVES A ROW

Four of the fifty mutations were rejected by the type checker rather than by the
gate, and the driver reports the two counts separately. A type error means the
mutation was ill-formed, not that the gate saw anything -- `[a] <> acc` is
rejected because `<>` on a list literal does not cons, `nf` used twice is
"consumed more than once", and `CL_UNKNOWN()` in a position bend considers an
unfilled law is a dead claim. Those three were rewritten as `List.reverse`
mutations, which is the honest way to test an appending fold anyway.

The lesson for the fold idiom specifically: the mutation you WANT for "this fold
reverses" is `List.append(..., List.reverse(&2, String, acc), [x])`, not
`[x] <> acc`. The second one never reaches the gate.

### 73. A CONTROL IS A MUTATION THAT MUST MOVE NOTHING, AND IT IS COUNTED SEPARATELY

`comment-only` is in the table and reports `CONTROL OK`. Without it, a driver that
diffed the wrong thing -- the mutant file's own path, a stale binary, a changed
row count -- would report every mutation as a kill and look perfect. It moves 0
rows for the same reason a broken port does: it changed nothing. Two blind spots
that are ALSO zero-move are only distinguishable because the control is in the
same run.

## A DRIVER CONSTANT AUDITED AGAINST THE ORACLE IS WORTH MORE THAN A GATE ROW, AND IT FINDS WHAT NO ROW CAN

Measured in `tinybendygrad/runtime/ops_nv.bend` (2026-10-02). `nv_570.py` is
generated ctypes bindings, so every driver constant is READABLE from Python:

    .venv/bin/python .agents/slop/nv-constaudit.py   # every `def X() -> U32: n`
    .venv/bin/python .agents/slop/nv-mutate.py       # rows each mutation moves

The first audit found **33 of 219 constants wrong** in a file whose gate was
already printing 590 green rows. Two of the shapes are worth naming because
neither is visible to any row:

1. **A `getattr(nv_gpu, f"{reg}_{k}")[1]` SHIFT and a `getattr(nv_gpu, f"{reg}_{k}_{v}")`
   VALUE are two different lookups of the same prefix.** A bitfield tuple is
   `(hi, lo)`, so `[1]` is the shift; the value lives on the *longer* name. An
   audit that maps only the value lookup will not notice a wrong shift, and a
   wrong shift collides two adjacent fields without changing any printed word
   count. Audit both, by both routes.

2. **A CONSTANT USED AS A TRACE LABEL AND A CONSTANT COMPARED FOR EQUALITY MUST
   BE AUDITED DIFFERENTLY.** In ops_nv the `rm_alloc`/`uvm`/`NV_ESC_*` words are
   port-internal ORDINALS standing for opaque driver handles, so their real
   values are wrong *on purpose*; the eleven `CLASS_*` ids and
   `BLACKWELL_COMPUTE_A` are compared against real driver values and must be
   right. An audit that cannot tell them apart reports ~22 false positives and
   gets ignored, which is worse than not running it. The discriminator is one
   question: **is this number ever compared with `is_eq`/`is_ge` against
   something the driver produced?**

### THE TAUTOLOGY THAT A WHOLE CLASS OF ROWS HIDES, and it is a NAME problem

`qmd.ver.of(compute) = QMD_VER5 if compute >= CLASS_BLACKWELL_COMPUTE_A()`. The
gate row was

    row("nv_qmd_ver_bwa", qmd.ver.of(BLACKWELL_COMPUTE_A()))     # 0 rows moved

The row passes the THRESHOLD in as its own INPUT, so both sides of the
comparison move together and the row answers 5 for every value the constant can
hold. MEASURED: mutating the constant moved ZERO rows, while the same file's
mutations M1-M28 each moved 1-23. **Renaming it `CLASS_...` does not fix this** --
it is still the same number on both sides. The fix is to write the literal:

    row("nv_qmd_ver_bwa", qmd.ver.of(52672))                     # 3 rows moved

A constant that is both a threshold and a plausible input is TAUTOLOGICAL by
name. Whenever a def's parameter and a constant it reads share a value, the
fixture must supply a LITERAL, and the general rule is: **a gate row whose
expected value is a def of the thing under test is not a test.** The cheap
detector is the zero-move mutation, which is why a table needs a *control*
entry: without one, "0 rows moved" is ambiguous between a blind spot and a
harness that diffed the wrong thing.

### A NEGATIVE ROW WHOSE NAME CONTRADICTS ITS OWN VALUE IS A LIE THAT READS AS A PASS

`brow("nv_notifier_not_bufferized", notifier_bufferized())` printed `False`,
because `notifier_bufferized()` is `False{}` -- i.e. the row claimed "not
bufferized" while printing False. 21 of the 596 rows print False, and in a file
whose rows are read as claims, a row whose name and value disagree trains the
reader to stop reading the name. Name every row FOR WHAT IT ANSWERS. Most of the
surviving False rows here are genuine negative cases and are the point: an
Ampere mask must NOT contain `BLACKWELL_COMPUTE_B`, a chained launch emits NO
words, `notifier` is NOT in the `:660` bufferize tuple. Those read as
`nv_has_bwcomp=False` and `nv_notifier_bufferized=False` -- false is the claim.

### 74. A `Data` RECORD WITH NO FIELD PROJECTIONS COSTS A `+` PER READER CALL SITE

`match d: case D{a, b}: a` consumes `d`. So `Bool.and(D.a(d), D.b(d))` is
"consumed more than once" -- and **putting `+` on the READER does not help**:
`def D.a(+d: D)` still fails at the call site, because the *call* of a
non-reflexive argument position needs a value it may keep, and `d` is plain.
Measured in `runtime/ops_disk.bend` against a 16-field `Dev`, which is 16 readers
and every two-field read a separate `+` at the CALLER:

    def dev_is_open(+d: Dev) -> Bool: Bool.and(Dev.has_size(d), Dev.has_mem(d))

This is rule 1 of the `nn/optim.bend` section ("a `Data` record parameter needs
`+` for two reads") with the direction pinned: the `+` is on the CALLER's
parameter, never on the reader's. A reflex on the reader looks like the fix and
is not.

### 75. A `match` BINDER MAY SHADOW AN IN-SCOPE PARAMETER, AND `x = f(x)` THEN COMPILES AND DOES NOTHING

    def dev_sized(+size: U32, d: Dev) -> Dev:
      match d:
        case Dev{name, size, hs, ...}: Dev{name, size, True{}, ...}

This is `self.size = size` and it typechecks, sets the flag, and leaves the OLD
size -- because the binder shadows the parameter and the body writes the field to
itself. Found by `dk_open_size` printing `0` after an open of 10000. **The fix is
`_` in the pattern**: `case Dev{name, _, hs, ...}: Dev{name, size, True{}, ...}`.

The general form: **a `match` over a value that contains a field whose name is
also a parameter of the enclosing def will shadow it.** Rule 4 of the `optim`
section ("a nested `match` on pattern binders is refused") covers reading a binder
twice; this is the adjacent trap and it is SILENT -- no diagnostic, no type error,
just a no-op assignment. A cheap detector: a gate row that prints a field the def
was supposed to set.

### 76. `Tr.emit(k, a, Tr.emit(k2, b, t))` APPENDS THE **INNER** CALL FIRST

The inner emit is the value the outer one appends, so nesting two records the
SECOND call first. Three sites in `ops_disk.bend` got it wrong for the same reason
and all three were order bugs: `dev_file.open.at` (the `:34` retry before the
`:33` ask), `alloc_copyout.osx` (`SEEK` before `FILEIO`) and `dev_ioring.mmaps`
(offsets 0, CQ, SQES emitted SQES, CQ, 0). The fix is one step per call:

    +a: Dev = dev_put(d, Tr.emit(K_MMAP(), 0, Dev.tr(d)))
    +b: Dev = dev_put(a, Tr.emit(K_MMAP(), IORING_OFF_CQ_RING(), Dev.tr(a)))
    dev_put(b, Tr.emit(K_MMAP(), IORING_OFF_SQES(), Dev.tr(b)))

The trap is general and it is not about traces: **in any strict `Bool.pick`-shaped
language, a nested call that appends inverts the source order.** Rule 2 of the
`optim` section already says `Bool.pick` is strict; this is the ORDER consequence
of nesting a state-accumulating call inside it.

### 77. A GATE MECHANISM THAT EMPTIES THE TRACE MUST RUN **BEFORE** THE STEP UNDER TEST

`dev_reset` (this file's `Tr.reset`) exists so a whole-trace comparison can look at
one step in isolation, because every fixture carries `dev_init`'s four io_uring
calls in front of it. Calling it on the RESULT of the step deletes exactly the calls
the row is about: `dk_close_exactly_two` was `False` against an empty trace, and
`dk_close_shm_only_unmap` was `False` for the same reason -- it looked like a
port bug and was a gate bug.

    WRONG   seq_eq(Dev.tr(dev_reset(c)), [...])        # the step is gone
    RIGHT   seq_eq(Dev.tr(c_after_reset_before_step), [...])

There is a second-order rule here, and it is the one that took the measurement: for
a fold of SEVERAL steps (`dk_two_free_exactly_two`), the reset goes after the step
that must record NOTHING and before the one under test, because the first free's
"no calls" is itself a claim the row set makes. One reset per row, placed between
the two steps it separates.

### 78. A HOST CONSTANT IS A PLATFORM FACT WITH TWO CELLS, AND HARD-CODING ONE IS A QUIET LINUX-ONLY PORT

`ops_disk.py` reads `os.O_CREAT`, `getattr(os,"O_DIRECT",0)`,
`getattr(mmap,"MAP_POPULATE",...)`, `getattr(mmap,"MADV_HUGEPAGE",None)` and
`mmap.PAGESIZE`. On macOS/arm64 those are 512, 0, 0, absent and **16384** -- and
`PAGESIZE` changes the shard ARITHMETIC, not just a trace argument, so a hardcoded
4096 is a port that is Linux-only with nothing saying so.

The fix is one parameter, the `osx` Bool the fixtures already carry, and the
oracle **asserts the second cell against the host**:

    assert mmap.PAGESIZE == 16384, "port's macOS cell is stale"
    assert getattr(mmap, "MADV_HUGEPAGE", None) is None, "macOS gained one"

That assertion is what makes the two-cell claim a measurement rather than a table
of numbers: if a future CPython adds `MADV_HUGEPAGE` the oracle FAILS instead of
quietly agreeing with the port. **Every host constant gets both cells and both
cells get a row** -- which is the same rule as rule 3 of the `webgpu` section
("five fixtures collapse to two values, so the equalities have to BE the rows"),
applied to constants instead of strings.

### 79. A `U32` WRAP IS A DIVERGENCE FROM CPython AND THE GATE CANNOT PRINT BOTH SIDES

`U32` has no signed type, so a port cannot state CPython's answer for a term that
goes negative -- `4096 - 4096 - 6144` is `-2048` in Python and `4294965248` in a
`U32`, and the `min` that follows picks `2048` here and `-2048` there. Three
things together make this survivable, and all three are needed:

1. **The gate prints the wrapped term, the answer, and the cover**, so the gap is
   visible as three numbers rather than as prose.
2. **The oracle carries the CPython answer as an ASSERTION**, not as a row:
   `assert shard_read_u32(...) != shard_read(...)`. If a future `U32` stops
   wrapping, the oracle fails instead of agreeing with itself.
3. **The divergence is named where it happens**, and the fixture that produces it
   is labelled as the fixture that produces it -- fixture D is "the short mapping",
   not "the wrap fixture, by the way".

`ops_disk.py` cannot reach the state at all: it relies on
`fd_offset + total_copy_size <= src.device.size`. So this is a port limitation, not
a source bug, and a saturating subtraction would invent a rule Python does not
have.

### 80. A MUTATION THAT MOVES NOTHING IS A MISSING FIXTURE UNTIL PROVEN OTHERWISE, AND THE PROOF IS A FIXTURE

Two of the 56 mutations measured `0/0` on first run, and BOTH were gaps in the
fixture set rather than redundant rules:

- **`:92`'s second conjunct** (`OSX and self.dev.fd is not None`). The gate had one
  shm fixture and it was a LINUX device, so `Dev.osx` was False and the FIRST
  conjunct already decided the arm. The mutation was invisible because the
  fixture could not REACH the conjunct. A second fixture -- `shm` AND `OSX` -- kills
  it.
- **`:104`'s `+ minor_offset`.** For three of four shard fixtures `size + minor`
  rounds up to the same page count `size` alone does (5000+100 and 5000+904 both
  give 8192, and so does 5000). The skew was invisible. A fifth fixture with
  `minor < seg_len` AND `size + minor > PAGESIZE` kills it.

The rule generalises the `control`-row lesson in section 73: a control tells you
`0/0` is meaningful, and then **`0/0` on a non-control means the fixture set does
not reach the rule.** The reflex to write is "add a fixture", not "this rule is
covered by the row for its first conjunct". Both of these rules ARE covered -- by
the other conjunct, and by the other fixtures -- and that is exactly what makes
them invisible.

### 81. `range(0, n, 0)` RAISES IN CPYTHON. A `U32` DIV-BY-ZERO IS NOT THAT

The port's `shard_n` answers 0 for `seg_len == 0` because `U32.div(x, 0) = 0` is
documented behaviour, and the header said "an empty `range` in Python". **That is
false**: `range(0, 12288, 0)` raises `ValueError: range() arg 3 must not be zero`.
Nothing in `_copyout_sharded` can pass 0, so the state is unreachable in the
source, but the COMMENT was a claim about CPython and it was wrong.

The fix is the harness rather than the code: `assert seg0_raises()` in the oracle,
so if CPython ever changes, the oracle says so. **The general form: any comment of
the form "X does not happen in Python because ..." is a claim about another
language and belongs in an assertion in the oracle, not in a prose comment in the
port.**

### 82. A HAND-WRITTEN ORACLE ROW IS A CHANGE DETECTOR, AND TWO HAND-WRITTEN ONES AGREE

The oracle's job is to ASK CPython, not to transcribe a reading of the source.
Two rows in `nv-oracle.py` were literals: `row("nv_query_litter_n", 2)` and
`row("nv_fault_refuses_viddec", "False")`. The gate agreed with the first --
both said 2 -- and the differ reported **0 disagreements**, while
`nv_570.__dict__` says THREE of the five `_query_gpu_info` requests have no
`NV2080_CTRL_GR_INFO_INDEX_<R>` at all and fall back to the LITTER table. The
gate's own table was wrong too, and the two wrong readings matched.

The rows now ask:

```python
def _q_litter(r):
    return getattr(g, 'NV2080_CTRL_GR_INFO_INDEX_' + r.upper(), None) is None
```

which is the same expression `ops_nv.py:665` evaluates. **The test for an oracle
row is "would this line still be right if I had misread the source?" A literal
answers no. Ask the module, the class attribute or the driver dict -- anything
reachable from the import -- and a misreading stops being possible.**

### 83. THE DIFFER KEYS ON THE ROW NAME, SO A MISSPELL IS A COVERAGE HOLE IN BOTH DIRECTIONS

`nv-diff.py` joins on the row NAME, so a claim the two sides spell differently
appears as *unmatched*, not as *disagreement*, and reads as "the oracle knows
something extra". `nv-oracle.py` emitted `nv_slmtot_1_48428` where the gate
printed `nv_slm_1_48428`; twelve rows sat uncompared for a whole stage and the
summary line still said 0 disagreements. The same shape hid five `nv_toname_*`
rows (the parts joined in the other order) and two rows printed TWICE in the gate,
where a name-keyed dict keeps the last and the first is dead.

**After adding a row, grep its name in BOTH files. "It is in the oracle" is not
"it is checked"; the differ prints an unmatched count for exactly this and it is
the count to read first.**

### 84. TWO CLAIMS MUST NOT SHARE A ROW PREFIX. NAME A ROW FOR WHAT IT ANSWERS

`nv_slm_*` meant `slm_per_thread` in the gate and the buffer size in the oracle,
so a total row and a per-thread row had the same six fixture suffixes and every
value in the table looked plausible. They are now `nv_slmp_*` and `nv_slmtot_*`.
The general form: **a row prefix is a namespace, and a namespace that holds two
different quantities cannot be read.** When a fixture list is already six long and
a seventh claim arrives, that is the moment to rename the prefix, not to add a
seventh suffix under the old one.

Related and equally cheap: `nv_notifier_not_bufferized` printed `False` and
`nv_vid_unk_is_none_new` was written `Bool.not(vid_unk_none(2097152))`, so the row
printed `True` where the claim is `False`. **A row's name must survive reading
its value: "is_none" next to True is a bug in one of the two.**


---

# APPENDED BY `runtime/ops_amd.bend` (2026-10-02). NUMBERING CONTINUES FROM 49
# (the 50-61 block below was written against a revision whose last rule was 49;
# a later appender has since added material, so check `rg -n '^## ' ` before
# citing a number and prefer LINE POSITIONS, per THE INDEX at the top).

## 50. BEND 2.0.34 HAS NO HEX LITERALS, AND `U32.shl` IS `U32.shln` WITH A `Nat` SHIFT

`0x1FF` is a parse error ("expected : a numeric literal"), so every hex constant
in a port becomes decimal. `U32.shl` is not a defined name either, and the error
is "expected : a type for this operator (write (a << b : Nat))" pointing at the
CALLER, not at the operator. The real name is `U32.shln(a: U32, b: Nat)`, so
`U32.shln(1, 20n)` and `U32.shln(1, MY_CONST())` needs `U32.to_nat(MY_CONST())`.
A bare `1 << 20` is refused ("expected : Nat / observed : U32") because `<<` on a
`Nat` resolves to `Nat.shln`, which does not exist. MEASURED while porting
`ops_amd.bend`; this cost six compile cycles and was the most-repeated mistake
in that file.

## 51. A `U32` SELF-CALL WHOSE FIRST ARGUMENT IS THE SHRINKING ONE IS REFUSED

`def hx.go(v: U32)` calling `hx.go(U32.div(v, 16))` gives "expected : a
decreasing self-call (arguments are read left to right: each passed unchanged
until one shrinks)" -- a `U32` self-call needs a `Nat` COUNTDOWN as its first
parameter, exactly like a list walk. So a `%x` formatter over an UNBOUNDED value
needs a fuel this tree does not have.

**The workaround is a STATED BOUND, not a recursion.** `hx.sh` formats two
digits and its callers bound the input themselves (`(trgt // 100) % 100` and
`trgt % 100` are both under 100). The bound is in the def's comment and the
boundary fixture (`v == 255`) is a gate row. A total function over a proved
subset, with the subset written down.

## 52. `Bool.pick` EVALUATES BOTH ARMS, SO A GUARD AND A SELF-CALL CANNOT SHARE AN ARM

`Bool.pick(T, guard, f(x), g(x))` evaluates `f` and `g` BOTH, so a recursive `g`
runs even when the guard is `True` -- and a `g` that is only decreasing UNDER
the guard diverges. Two workarounds, both used in `ops_amd.bend`: put the
recursion behind a def whose own base case the guard implies (`Tr.refuse.go` is
idempotent, so re-refusing is cheap and terminates), or make the recursive call
unconditionally terminating by peeling digits (`hx.lead` returns `""` below 16,
so the `else` arm's `hx.go(v/16)` always reaches `hx.go(0)` and stops).

## 53. A `List.append` FOLD MUST **NOT** `List.reverse` AT THE END, AND GETTING IT WRONG IS INVISIBLE TO EVERY LENGTH AND TOTAL

`List.append(A, xs, ys)` is `xs ++ ys` (see the rule at line 1590), so a fold
that APPENDS is already in order; the `List.reverse` in `ops_webgpu.bend`'s
`ush` is there because THAT fold prepends. Copying the `ush` shape into an
appending fold prints every list BACKWARDS with every length, every sum and every
count correct. MEASURED: 19 rows moved and no total moved. Same class as a byte
total being blind to a `BLOB`-vs-`WORD` kind.

## 54. `String` HAS EXACTLY ONE VISIBLE CONSTRUCTOR, SO A `match` ON IT CANNOT NAME THE EMPTY CASE

`match s:` with `case "":` or `case Con{c, t}:` gives "expected : a constructor
of String (missing, or already matched)" and prints the internal shape
`\{Con: (c => t => c)\}`. `String.is_empty` exists, so a per-character `lower()`
/ `replace()` is NOT expressible: the fold needs a base case the `match` cannot
write, and there is no `String.map` and no lambda (`fn c:` is a parse error).
`hcq2.py:66`'s `to_name` fold is therefore a WALL in Bend; the workaround is
rule 51's -- keep the RESULT for the five queue names the device can produce, as
a TABLE, and gate that.

## 55. `U32.or` / `U32.and`, NOT `bor` / `band`; AND `U32.div` IS FLOOR

The whole `U32` name set, MEASURED by
`rg -oE '\bU32\.[a-z_0-9]+' tinybendygrad/uop/ops.bend tinybendygrad/helpers.bend | sort -u`:
`add and cmp div from_nat is_eq is_even is_ge is_gt is_le is_lt is_ne is_zero mod
mul or shln shrn sub to_f32 to_nat to_u32`. There is no `bor`, no `band`, no
`shl`, no `shr`. **`U32.div` is FLOOR** and there is no `ceildiv` on `U32` --
`H.ceildiv_u32` and `H.floordiv_u32` are the two, and picking the wrong one for
a Python `//` is a silent off-by-one at every boundary. MEASURED:
`ops_amd.bend`'s `pd.lds` used `ceildiv` for `//` and read 512 granules back
as 2. Do the grep FIRST, because writing `U32.bor` produces "expected : a defined
name" pointing at the CALLER's return type, which reads like a return-type error
and is not one.

## 56. A `Data` RECORD'S READER CANNOT BE NAMED AFTER ITS FIELD, AND `Type.a.b` CHAINS ARE NOT NESTED DEFINITIONS

`type Gr is Data: Gr{g: U32, l: U32}` then `def Gr.g(x: Gr) -> U32` is fine, but
`def pkt.shape.seeds()` after `def pkt.shape()` gives "expected : a term (the
keyword 'def' cannot head one)" -- a two-segment dotted name is not a `Type.def`
two levels deep. Use one segment (`pkt.sh_seeds`).

## 57. A SCRIPTED BLOCK MOVE MUST ASSERT `end > start`, OR IT DELETES THE SPAN BETWEEN

`s[:a] + s[b:]` with `b < a` -- which happens the moment the block already sits
after the anchor -- silently DELETES everything from `b` to `a`. `ops_amd.bend`
lost 841 lines including its entire gate to this and the recovery was to rewrite
the tail. `.agents/slop/tools/hoist.py` is safe because it moves one `def` at a
time and re-checks after each; an ad-hoc multi-block splice is not. Assert and
print the line count.

## 58. TWO PYTHON FLOOR TRAPS THAT A `U32` PORT FALLS INTO TWICE

Not Bend rules -- PORTING rules, recorded because they cost two real bugs in
`ops_amd.bend` and the same traps will hit the next unit. (a) `ceildiv` is
`-(a // -b)` in `helpers.py`, so reaching for `H.ceildiv_u32` on a Python `//`
is wrong at every boundary. (b) `(raw & 0x1FFFFFFF) * 32` in a `U32` WRAPS
rather than saturating -- the SQTT write pointer is up to 2^34, and the first
version of that def computed it in `U32` and printed 4294967264 where CPython
prints 17179869152. It is an `H.I64` and an `i64row`, which is what
`ops_nv.bend` does for the same reason. Both were caught by the oracle; neither
would be caught by a hand-typed expectation.

## 59. A GATE THAT PRINTS `name=value` MUST DIFF THE VALUES, NOT THE ROW NAMES

`ops_webgpu.bend`'s mutation table diffs row NAMES, which measures only
ADDITIONS and REMOVALS. Every mutation in `ops_amd.bend` changes VALUES and
changes no name, so a name-diff harness reports `0 moved` for all twenty-seven
of them -- including the one that is SUPPOSED to be a blind spot. Diff the
`name=value` pairs. `.agents/slop/amd_mutate.py` does; treat the name-diff in
the older tables as "not yet measured".

## MEASURED BY THE `runtime/ops_rdma` + `ops_npy` + `nn/torch` UNIT (2026-10-02)

Three four-line-to-one-hundred-and-sixty-nine-line files, all three green in
both lanes and against a CPython oracle. Six rules, none of them a restatement of
an existing one.

**A `Bool` PARAMETER IS AFFINE EVEN WHEN THE `Bool` IS ONLY USED ONCE.** The rule
at position 4440 says `+hit: Bool` is accepted. This is the companion: a `Bool`
parameter that feeds a `Bool.pick` whose arms BOTH read it is "consumed more than
once" and needs `+`, even though `Bool.pick` looks like one read. Seen twice, in
`Tr.raise.at` and in `Tr.refuse.go`. Reproducer: `def f(+c: Bool, +a: A) -> A:
Bool.pick(A, c, a, a)`.

**A `Data` RECORD LITERAL NEEDS EVERY FIELD AND THE ERROR NAMES THE *FIRST*
MISSING ONE.** `Tr{Bool.pick(...), Bool.pick(...)}` against a three-field `Tr`
reports `expected : Tr with 3 fields` and points at the whole literal, so the
second `True{}` is not obviously the missing piece. The fix is mechanical and
costs one compile cycle each: `Tr{calls, next, refused}`.

**A `match` MAY NOT BE NESTED INSIDE A `Data` MATCH ON A `Bool` FIELD, AND
`Bool.pick` IS THE ONLY WAY OUT.** `match t: case Tr{+calls, refused}: match ok:
…` is refused with "a match on a parameter or field (this name is a def or a
consumed binder)". `ops_webgpu.bend` nests `match is_buf:` inside a `Pass` match
and THAT is fine -- the difference is that the nested scrutinee there is a
PARAMETER and here it was a `+` binder. Reproducer: the `Tr.raise.at` shape in
`nn/torch.bend`; the working alternative is two `Bool.pick`s with both arms total.

**`U32.shln` AND `U32.shrn` WANT A `Nat` LITERAL, NOT A `U32`.** `U32.shln(1, l)`
where `l: U32` fails with `expected : Nat, observed : U32`. `U32.shln(a)` (no `n`)
is `a << 1`, so the unary form is not an escape. `U32.to_nat` converts, or a
`…_NAT()` constant carries the `n` suffix -- which is what `MSN_PSN_AT_NAT()` and
`MSN_SLOT_HI_AT_NAT()` in `ops_rdma.bend` are. Same rule as position 2038 for
`String.to_u32`, and the same trap: the error names the argument type and not the
operator.

**`List.append(a, A, xs, ys)` IS `xs ++ ys`, SO A FOLD THAT USES IT AS ITS
ACCUMULATOR STEP MUST NOT `List.reverse` AT THE END.** `ops_webgpu.bend`'s
`bgl.flat` and `dev.uniform_bytes.go` reverse because they CONS with `h <> acc`.
A fold that appends and then reverses produces the reverse of the input, which
typechecks and prints a plausible-looking list. Measured twice in one session:
`torch.bend`'s `posix.go` printed `yp.c/b/a` for `a/b/c.py`, and
`ops_rdma.bend`'s `chunks_of` printed `4,262144` for `[262144, 1]`. THE ROWS THAT
CAUGHT IT ARE THE ONES WITH AN ASYMMETRIC INPUT: every symmetric fixture agrees
either way, so a fold needs a two-element unequal fixture before it can be
checked at all.

**A `U32` FIXTURE THAT READS A COUNTER *BEFORE* THE BUMP THAT INCREMENTS IT
UNDERFLOWS, AND THE GATE PRINTS 4294967294 INSTEAD OF AN ERROR.** `seq.after(*bumps)
.index(0).load() - wqes` at ops_rdma.py:126 reads the counter AFTER the store at
:123, so a fixture that hands in the pre-bump value computes `0 - 2` and a `U32`
wraps silently. The port was right and the FIXTURE was wrong; the oracle
disagreed on two rows and both were the fixture's. `FX_SEQ_AFTER` /
`FX_PSN_AFTER` in `ops_rdma.bend` exist because of this, and the rule generalises:
**a port of a load-after-a-store takes the post-store value as its parameter, and
the parameter is named so the reader cannot tell.**

### AND ONE FINDING THAT IS NOT ABOUT BEND AT ALL

`rdma_copies` builds its doorbell argument as `(slot | epoch << 24) | ring_db`
where `ring_db = db_value(qpn, SQ, 0, 0)`, and `ins` casts every int to
`UOp.const(s, dtypes.uint32)`. `db_value`'s low half is `index & 0xffffff |
epoch << 24` with BOTH arguments 0 at every call site (ops_rdma.py:130-131), so
`ring_db`'s low 32 bits are 0, the OR is a no-op, and the uint32 cast drops the
high half — the only part that names WHICH QUEUE the doorbell is for. MEASURED:
`db_value(5, DBC_DBC_TYPE_SQ, 0, 0) == 288230397626548224` and
`288230397626548224 & 0xffffffff == 0`. `ops_rdma.bend` is faithful to this and
the header says `REPORTED, NOT FIXED`; `rdma_db_hi_dropped`, `rdma_db_lo_zero` and
`rdma_db_or_noop` are the rows. Whether the generated SDMA code recovers the xid
is a question for the owner of `ops_rdma.py`, and the general lesson is the one
the brief keeps restating: **a trace that records the CALL but not its ARGUMENTS
cannot see a dropped argument, so the argument belongs in a record the def
RETURNS.**

---

## APPENDED BY `examples/beautiful_mnist.bend`, 2026-10-02 — numbering continues from rule
## 59 above (the INDEX AT THE TOP OF THIS FILE EXISTS BECAUSE RULE NUMBERS REPEAT ACROSS
## SECTIONS; CITE LINE POSITIONS, NOT NUMBERS)

### 60. `Nil{}` IS "NO AXES", NOT "ALL AXES", AND THE TWO SPELL DIFFERENT GRAPHS

`reduce.py:15` reduces `axis=None` to `tuple(range(self.ndim))`. A port that
spells the all-axes case as `Nil{}` passes `[]`, and `tn_rop` treats that as a
no-op: the node is not built at all. There is NO ERROR and no empty node — the
result is the input, and a signature simply has one node fewer.

MEASURED on `Y.const_like(True, dtypes.bool)` with `Y` of shape `(4,)`:

    mo_sum(False{}, m, Nil{})  -> 4 CONST/0 CONST/0 EXPAND/2 CAST/1
    mo_sum(False{}, m, [0])    -> 5 CONST/0 CONST/0 EXPAND/2 CAST/1 REDUCE/1   == CPython

and CPython's own `sum()` and `sum(0)` print the same `5 CONST/0 CONST/0 EXPAND/2
CAST/1 REDUCE/1`. **THE REDUCE IS THE ONLY DIFFERENCE AND A NODE COUNT IS THE ONLY
ROW THAT SEES IT**, because the root op, the `nsrc` and the src op SEQUENCE are all
unchanged — a signature-only gate cannot tell `CAST` from `CAST, REDUCE`.

THE GENERAL FORM: **an "everything" argument in a Python API whose default is
`None` is NOT the empty list.** `axis=None`, `keepdims=False` vs `keepdim=0`,
`dims=()` in a torch-ported call: each has a spelling that means "all" and a
spelling that means "none", and in Bend they are different values. `mn_last_axis`
(`MO.mo_ax(True{}, x, 4294967295)`) already spells the negative axis explicitly for
the same reason; the all-axes case was simply never spelled.

### 61. A DEF THAT NO GATE ROW CALLS IS NOT TESTED, AND `mn_loss` WAS ONE FOR A WHOLE FILE

`examples/beautiful_mnist.bend` printed 25 shared rows and none of them reached
`mn_step` or `mn_loss`, so rule 60 above sat in the middle of `mn_loss`'s body,
undetected, until a `unverified_step` row called it. The defect was not a missing
mechanism: every op was ported and green in its own file.

THE TEST FOR THIS IS NOT "did I write a row for it" but "**can a MUTATION of this
def move any row**", and the answer for `mn_loss` and `mn_step` was NOTHING for
four distinct edits: the mask's dim, the mask's arena, `mn_step`'s arena, and
`mn_loss`'s outer reduce.

SO: **after closing a wall, re-run the mutation table against the CLOSING edit and
not against the pre-existing rows.** A wall closure that no row can see is a claim,
not a gate, and it is the most likely shape of a silent regression because the diff
looks like an improvement.

### 62. A SQUARE MODEL CANNOT TELL THE HEIGHT READ FROM THE WIDTH READ

Every shape in `examples/beautiful_mnist.bend` is square (`(1,1,28,28)` in, every
kernel `k x k`), so at every step `o_h == o_w`. MEASURED: mutating `mn_conv_out` to
read its WIDTH from the HEIGHT's index moved NOTHING across all fourteen walk rows.
Fourteen square layers structurally cannot see it, and no mutation of any square row
ever will.

THE GENERAL FORM: **a shape walk over a model whose dims are all equal has one
free index it cannot check per step.** The fix is not a better assertion but ONE
fixture that breaks the symmetry, gated against the same CPython call on that
fixture — here `nn.Conv2d(1, 32, 5)` on `(1,1,28,30)`, row `mdl_pool_ns`. A
non-square fixture in a square model is not a fake fixture; it is the only fixture
that can fail.

### 63. A `Data` LIST ELEMENT MATCHES IN A TWO-SCRUTINEE `match`, SO A LAYER CAN BE THE
###     STOP CONDITION WITHOUT A `Bool`

`def pool_in.go(+ls: List<&2, MnLayer>, +s: MnShape) -> MnShape:` with arms
`case Nil{}: s` / `case MnPool{} <> +t: s` / `case l <> +t: <recurse>` typechecks and
runs. It is the way to stop a walk on a VALUE without splitting the def in two.

WHY IT MATTERS: the obvious spelling is a `Bool.is_pool(l)` parameter plus an
`.at`/`.go` pair, and that is MUTUAL RECONSTRUCTION — `at` calls `go` and `go` calls
`at` — which Bend refuses. The notes' rule 5 (mutual recursion is refused) applies
to a two-def dispatch exactly as it applies to a self-call, and the fix is the same:
keep the recursion in ONE def and let the `match` do the dispatch.

### 64. `IO.print` AND `MO.mo_sig_t` CANNOT BE FOLLOWED BY `IO.print` IN THE SAME BODY

`def t_x() -> IO<Unit): MO.mo_sig_t("a", x)` then `IO.print(...)` on the next line
is `expected : 'def', 'type' or 'law' / observed : 'I'`. The implicit-return form
(`def f() -> IO(Unit):` followed by bare statements) admits AT MOST ONE terminal
`IO` call; two need two defs. `t_w3b` and `t_w3` in `examples/beautiful_mnist.bend`
are two defs for that reason and it is not a style choice.

THE SAME SHAPE BITES A `+x = CALL` FOLLOWED BY AN `IO` CALL: the local must be
bound before the `IO` statement because a `do IO<Unit>:` block may not carry `+`
lets at all (`expected : a pattern` at the `+ar = ...` line).

---

## Session 2026-10-02 — `runtime/ops_metal.bend` (the const map, and the seam)

Numbering continues from rule 64 at line 7090, which is the last numbered entry
above. These are 65-70.

### 65. A DEAD-DEF AUDIT MUST BLANK THE DEF'S NAME IN PLACE, NOT DROP THE WHOLE LINE

Name-based reachability ("is this identifier mentioned anywhere but its own
header?") is the cheapest dead-code check there is, and the obvious
implementation gets it wrong in the direction that matters. `ops_metal.bend` has
one-line defs:

    def q.submit.zero(nbytes: U32) -> U32: D.round_up(nbytes, ZERO_ALIGN())

Strip every `^def ` line from the body before searching and this constant reads as
UNREAD -- and so do eleven more, including `ARG_ALIGN`, `DIM_WORDS` and every
`HDR_*`. MEASURED: the strip-the-line version reports 29 dead defs where the
blank-the-name version reports 17, and all 12 of the difference are false. Replace
the header with spaces (`DEF.sub("  ", line)`) and keep the rest of the line.

The general statement: **a source line can be both a declaration and a use.** Any
tool that removes declarations before searching for uses is measuring its own
regex.

### 66. `Tr.refuse(t, ok)` REFUSES WHEN `ok` IS FALSE, SO A DELIBERATE REFUSAL IS
###     `Tr.refuse(t, False{})` -- AND `Bool.pick` ANSWERS ITS SECOND ARGUMENT WHEN
###     TRUE, SO A GUARD NAMED `filled` READS BACKWARDS

Both of these bit in one edit. The seam's callback arm is `if error == 0: keep the
MTLB else: raise`, and the port wrote it as
`Bool.pick(Tr, cc_error_ok(err), <keep>, <raise>)`. `Bool.pick(-A, c, a, b)`
answers `a` when `c` is TRUE (rule at line 2106), so `<keep>` was correct -- but the
`else` arm was written `Tr.refuse(t, True{})`, and `Tr.refuse(t, ok)` refuses when
`ok` is FALSE, so the error arm did NOT refuse and `mt_cb_bad_refused` printed
`False`. The count rows were all correct, which is why it took reading the row name
rather than the counts to find it.

Same session, the mirror image: `sync.one`'s parameter is `filled` meaning "the END
slot is already filled", so `True` means DO NOTHING. The obvious reading of the name
is the opposite one, and the scan silently went from six calls to zero.

THE RULE: **a `Bool` parameter's name must say which value means WHAT, and a `Bool`
you chose yourself has no default meaning.** `ok` in `Tr.refuse` and `filled` in
`sync.one` are both port-invented, and both were wrong on first write.

### 67. A HOST VALUE INJECTED AS A CONSTANT IS STILL AUDITABLE, AND `MACOS_MAJOR`
###     IS THE PATTERN

`compile` needs `platform.mac_ver()[0]`'s major version to pick `-std=`, and Bend
cannot ask the kernel what it is running on. Making it a plain `def MACOS_MAJOR()
-> U32: 26` looks like a hardcoded assumption and is not: the gate prints it, and
the oracle prints `int(platform.mac_ver()[0].split('.')[0])`, and the differ
compares. Same rule as `now` -- inject it -- except the injection site is a
constant rather than a parameter, so the audit reaches it instead of skipping over
it. **A fixture value with a name nobody can check is a magic number; the same
value with an oracle row is a measurement.**

### 68. A CONSTANT WITH NO READER IS A CONSTANT NO MUTATION CAN FIND, AND THAT IS
###     THE WHOLE `ops_nv` LESSON IN ONE LINE

`mt_mutate.py`'s constant sweep does `+1` on every numeric constant def and reports
which ones move nothing. MEASURED on `ops_metal.bend` after this session: **112
defs, 31 blind, and all 31 are the `CALL_*` tag space plus two fixtures.** Before
it, eleven of them were blind for a different and much more embarrassing reason --
they had no reader at all.

The 31 that remain are **genuinely unfixable and must be reported as such**, in the
same spirit as the `pc.find` blind spot: the `CALL_*` NUMBERS are a port-internal
tag space with no Python counterpart, so a row printing them would encode the
current assignment rather than test it. What protects them is the other direction --
`mt_constmap.py` checks each tag NAME against the `ops_metal.py` line carrying the
selector the port claims, which is the `CLASS_BLACKWELL_COMPUTE_A`-holding-`_B`
failure mode, and checks the tag set for density.

**A mutation that moves nothing is a REQUEST FOR A FIXTURE until you have asked
what the number is FOR. Then it is a finding, and the finding is written down.**

### 69. A GATE CANNOT SHRINK AND A WIRE-UP CAN MOVE ROWS: SAY WHICH, AND WHY

Wiring `cns_string` into `dev.pipeline.fun` -- a def that existed, was correct, and
was called by nothing -- added one objc message to every pipeline, so seven rows
changed value (`mt_pipe_calls` 6 -> 7, `mt_icb_calls` 27 -> 29, `mt_pipe_sels` 49
-> 49,50) and NO row disappeared. That is the shape a legitimate change has, and it
is worth stating in the file because "the gate must not shrink" reads like "the
output must not change" until you have moved a row on purpose.

### 70. A REAL FFI CALL THROUGH `ctypes` RUNS ON THE HOST, SO THE PORT'S ORACLE CAN
###     BE THE CALL

`ops_metal.py:68`'s `ctypes.byref(callback, -0x10)` is the Apple block ABI and it is
a genuine Bend wall. But from CPython it WORKS: `.agents/slop/mt_seam_rows.py` fires
the real `MTLCodeGenServiceBuildRequest` on a good and a bad kernel and reads what
came back. Three numbers that no amount of reasoning would have produced:

  * `reply[8:16]` is `(104, 0)`, so `:50`'s slice starts at byte 104 of 4580.
  * the UNSLICED reply's first word is `3`, and only the SLICED `ret` carries
    `MTLB` -- reading the magic off the wrong blob is off by 1112298570 and still
    LOOKS like a magic, which is `nv_query_litter` again;
  * `error` is `0` on success and `2` on a compile error, so `:47`'s
    `if error == 0` is a comparison against two real answers.

**A wall in the PORT is not a wall in the ORACLE.** Ask the driver; do not reason
about it. (And the trap in the middle one: `struct.unpack('<LL', ret[8:16])` on the
POST-slice answer reads `(2164260873, 196634)`, a 2 GB "header", because the slice
already moved. Instrument the callback, do not re-read the answer.)

---

# 2026-10-02 -- the `runtime/ops_qcom` unit. Numbering CONTINUES from 64 above.

### 65. A `U32` LITERAL WITH A LEADING ZERO AND NO `0x` IS NOT A LITERAL

`ctz(0000003f)` is `expected : a numeric literal`. `0x3f` and `63` are both fine;
`0000003f` is not. It matters for generated tables whose keys are zero-padded
hex strings: the generator has to `int(v, 16)` and emit the decimal, or emit
`0x`-prefixed. MEASURED by the `runtime/ops_qcom` gate, which formats every
fixture key as `%08x` and got a parse error on the first `ctz` row.

### 66. A COUNTDOWN ARM MAY NOT READ ITS OWN FUEL, AND `at_of(at, m)` IS SUCH A READ

`case 1n+m: f(m, r, g(at_of(at, m), f, t))` is refused with `expected : m /
observed : m (consumed more than once)`. The existing rule (the "+U32 that
grows" escape) applies, and the fix here is to WALK THE INDEX LIST IN PARALLEL
with the value list and use the parallel head:

    case f <> r:
      match at:
        case Nil{}: t
        case a <> rest: go(m, r, rest, step(a, f, t))

`a` IS the resolved index because the index list is already in issue order.
`runtime/ops_qcom`'s `flush.go` and `exec.pre2` are both this shape. The
alternative -- passing the whole `at` list down and indexing it -- is exactly
what is refused.

### 67. `List.length(a, T, xs)` INSIDE AN ARGUMENT TO A `+xs` PARAM IS A SECOND READ OF `xs`

`f(+xs)` where the body is `g(List.length(&2, T, xs), xs)` reports `expected : xs /
observed : xs (consumed more than once)`. Two separate defs is the fix
(`f` binds nothing, `f.of` takes the list twice), and it is the same
`.of`-split rule as everywhere else. MEASURED on `Tr.args`, `layout_args.of`
and `pack_args.sorted`.

### 68. AN INSERTION SORT NEEDS A PREFIX ACCUMULATOR *AND* THE TAIL, AND BOTH ARE MISSABLE

`Bool.pick(List<&2, U32>, U32.is_le(o, h), List.append(&2, U32, carried, [o]),
List.append(&2, U32, t, [h]))` is `carried ++ [o]` in BOTH arms: the `False` arm
drops `carried` and the `True` arm drops `t`. Three separate bugs, each of which
compiles:

  - both arms identical -> the sort is an append and the order is the input's;
  - `carried` dropped -> the sort is a `List.reverse`;
  - `t` dropped -> the sort SWALLOWS an element, which is invisible for a
    sorted input and is the whole difference for an unsorted one.

The fix is `pack_args.cat(List.append(&2, U32, carried, [o]), t)` -- i.e.
`carried ++ [o] ++ t` as two appends -- and it is worth a row PER input shape:
the five `qc_pa_*` rows in `runtime/ops_qcom` agree on sorted inputs while the
`unsorted` one does not, which is exactly this bug surviving to the end.

### 69. SEEDING A FOLD'S ACCUMULATOR WITH THE LIST IT WALKS IS A GROWING INPUT

`sort(len(offs), offs, offs)` makes `List.append(acc, [o])` grow the list the
`match` is destructuring, so the walk sees its own output and terminates on a
LENGTH that no longer matches the list. The answer is one element SHORT and it is
invisible for a one-element input. Seed with `Nil{}`.

### 70. A `.of` SPLIT IS REQUIRED WHEN A FOLD'S RESULT IS PASSED BACK IN AS AN ARGUMENT

`Tr.args.go(m, k, t, Tr.args.put(Call{kk, aa}, k, acc))` typechecks, and so
does every other one-shot version, but the def ORDER then has to be manual and
gets it wrong. `.agents/slop/tools/hoist.py` fixes the order in one round where
ten hand edits did not; the failure mode is `expected : a filled definition /
observed : <the callee>` at the definition you already moved.

### 71. `exec.tail_of`-STYLE READERS ARE WRONG WHEN THE LAST CALL IS A CACHE FLUSH

Not a Bend rule, a porting rule that cost two rounds: on a ring queue the LAST
`cmd` of a kernel launch is the trailing cache flush, not the dispatch, so a
reader that takes "everything after the last register write" answers the flush.
The two readers have to be named separately (`last_cmd` and `dispatch`) and the
pair is what makes either a claim.

**NUMBERING WARNING, MEASURED WHILE APPENDING THIS.** Rules 65-70 ALREADY EXIST
above at lines 6444-6516 (the `SIG` field order, the `dict.get` in an f-string, the
one-based ordinals, the `List.reverse` fold, the branch key). This is the third
collision and it is why the INDEX at the top of this file exists. Cite **line
positions**, never numbers: the seven rules above are at **lines 7109-7207**.

---

## ops_dsp.bend (2026-10-02, the C-backend-for-a-DSP wrapper) — 8 more rules

Numbering continues from the **ops_webgpu/ops_metal** append, whose last rule sits at
line **7207** ("on a ring queue the LAST cmd of a kernel launch is the trailing cache
flush"). This is the **fourth** numbering collision; cite **line positions**.
The EIGHT rules below are at **lines 7295-7376**. Measured on bend 2.0.34.

1. **A `def f.b(...)` CALLING `f.a(...)` MUST BE DECLARED AFTER IT, AND THE ERROR
   SAYS "unfilled law", NOT "forward reference".** `def alloc.alloc(...)` matching
   `case True{}: alloc.alloc.mock(...)` where `.mock` is declared later reports
   `expected : a filled definition (an unfilled law is a dead claim: live code
   cannot use it)`. The `match` never runs and `a` is neither a def nor a
   constructor, so the same class-0/1/2 dispatcher and the same fix apply. Costs a
   full round if you read it as a proof error.

2. **`U32.shl` IS A ONE-BIT SHIFT AND `U32.shr` A ONE-BIT RIGHT SHIFT.**
   `base.bend:1389` defines `U32.shl(a: U32) -> U32` as `Word.shl(32n, x)` — one
   bit. The n-bit forms are `U32.shln(a, n: Nat)` and `U32.shrn(a, n: Nat)`. So
   `a << 24` is `U32.shln(a, 24n)` and **every shift AMOUNT is a `Nat` literal**, not
   a `U32` value: a bit-packing function whose field positions are runtime numbers
   is not writable here at all.

3. **A `case <String literal>` BINDS THE SCRUTINEE, SO A `case _:` ARM LOSES THE
   PARAMETER.** `def dt_fmt.double(nm) : match nm: case "double": "d"; case _: dt_fmt.i32()`
   fails with `expected : String / observed : @nm:String -> String`. Splitting one
   table across two `f.a`/`f.b` defs by a literal arm therefore does not work; the
   table has to be ONE `match`. (Which is what the `.i32`/`.double` split for a
   13-arm table was for, and it was a mistake.)

4. **A `case 1n+m:` ARM BINDS `m`, SO A BODY THAT ALSO READS THE SCRUTINEE `n`
   CANNOT USE EITHER TWICE — AND `n` ALONE PASSED ALONGSIDE `m` IS ALREADY TWO
   USES.** MEASURED, three variants, all refused:
   `f.go(m, [f.at(n)])`, `f.go(m, [f.at(m)])` and `f.go(n, m, acc)` each give
   `expected : m / observed : m (consumed more than once)`. The working shape is a
   **list destructuring with the index list as the fuel**: `match ix: case i <> t:
   f(t, [at(i)])` over `List.range(n)`. `case Nil{}: ...` covers the end. This is the
   same rule as "a self-call must pass the shrinking argument first", wearing a
   different hat: the countdown's *tail* is the fuel and the countdown itself is
   spent.

5. **A `Bool` AND A `U32` DO NOT COMPARE.** `U32.is_eq(Param.is_alu(p), nat)` with
   two `Bool`s gives `expected : U32 / observed : Bool`. `base.bend` has no
   `Bool.eq`; the working one-liner is `Bool.not(Bool.xor(a, b))`. Worth its own
   def because it appears in every count fold.

6. **A RECORD PATTERN'S BINDER SHADOWS A PARAMETER OF THE SAME NAME — AND NOTHING
   SAYS SO.** `def alloc.offset(+b: DspBuf, size: U32, off: U32)` with
   `case DspBuf{id, va, size, offset, ...}: DspBuf{id, ..., size, ...}` typechecks,
   passes `--check-only`, and keeps the **parent's** size. `+` on the parameter does
   not help: the parameter is never read at all. MEASURED against CPython's
   `_offset`, which reports the view's 256 where the port reported 1024. **Rename
   the parameter** (`nsz`), never the binder: a record pattern may name FEWER
   fields than the record has, so dropping the `size` binder is the cheap fix when
   the new value is not needed.

7. **A MUTATION HARNESS MUST DIFF THE WHOLE `name=value` LINE, NOT THE ROW NAME.**
   With a name-only diff, **all 68** mutations of `ops_dsp.bend` read "0 rows
   moved", including the six that are real bugs in the port's first draft. The
   NAME never changes when a VALUE does, which is what most mutations do. This is
   the same failure the `mt_mutate.py` note at line ~7180 describes for a different
   reason ("a table entry whose target line was hand-edited would read as 0"), and
   it is worth stating separately because the fix is one character of comparison.

8. **A SCRATCH COPY OF A `.bend` FILE MUST SIT IN THE SOURCE'S OWN DIRECTORY.**
   Already in the metal note at line ~7165; repeated here because `dsp_mutate.py`
   walked into it again with a `tempfile.mkdtemp()` scratch dir, and every mutation
   then read `-- DID NOT COMPILE / RUN --`, which looks like a table of broken
   mutations rather than a broken harness. A `-- DID NOT COMPILE / RUN --` line in
   a mutation table is ALWAYS a harness bug until proved otherwise.

**THE PORTING RULE THAT PAID FOR ITSELF TWICE, and is worth repeating.** Generate
every gate expectation by CALLING CPython, never by transcribing it, and then CHECK
the transcriptions mechanically. `ops_dsp.bend` had **420** `py=` rows and the
first run of `.agents/slop/dsp_gate_check.py` found **35** disagreements, of which
**six were real port bugs** (`attrs_of`'s head/tail order, `dt_itemsize`'s missing
fp8 arms, `compiler_args_first`'s two arms swapped, `alloc.offset`'s shadowed size,
`open_lib_bad`'s unsigned compare for a signed test, and `link_lines`' separator
which was wrong TWICE — a leading newline and then a reversed order). Six is roughly
what `renderer/cstyle.bend`'s 215 hand-typed expectations produced, at a fifth of the
row count. The mechanical check is four lines of regex and it is the difference
between "I diffed it" and "I checked it".

## `uop/fold.bend` (2026-10-02, the five movement shapes) — 9 more rules
## (items continue the count from 44; numbers are NOT unique — cite line POSITIONS)

Appended, not edited. All nine are Bend 2.0.34, each cost at least one compile cycle
or one wrong answer that typechecked and ran, and every reproducer is in
`.agents/slop/oracles/`. This unit wrote five `_shape` arms (`expand_ds`, `pad_ds`,
`shrink_ds`, `perm_ds`, `flip_ds`) into a file that already had the Kahn worklist, so
these are the rules for adding an arm to an existing recursive fold.

### 1. A THREE-SCRUTINEE `match` OVER THREE `Maybe`s IS FINE; OVER A `List` AND TWO
###     `Maybe`s IT IS NOT

```bend
match a b c:                                   # three Maybe<&1, U32>
  case Some{x} Some{y} Some{z}: ...
  case _ _ _: False{}                          # FINE -- `_ _ _` covers

match ps os szs:                                # List, Maybe, Maybe
  case p <> pt, Some{o} Some{z}: ...           # REFUSED, and the error names the FIRST
  #| - expected : a constructor of Maybe        #   scrutinee, not the one that is wrong
```

The scrutinees must share a shape. The fix is to make all three the same type: keep
the two `Maybe` answers as `Maybe<&2, List<&2, O.Sint>>` through a NON-recursive
`.of`/`.os`/`.oz` chain (a chain is free, only a *cycle* is refused) and hand the walk
three plain lists. `.agents/slop/oracles/fold-probe-mvt2.bend` P6 is the working
shape and `pad_shrink.go` is it in the port.

### 2. A LIST-PATTERN HEAD **AND** A `Maybe` PATTERN CANNOT SHARE ONE ARM, BUT A
###     PLAIN-LIST WALK WITH A THREE-SCRUTINEE `match` IS THE WHOLE ANSWER

This is the same fact as rule 1 seen from the other side, and it is worth its own
entry because the working form is smaller than the four attempts that failed first:
a `.go`/`.step`/`.put` split of ONE self-recursive walk is mutual recursion (each part
calls the other), and `List.last`/`List.tail` in place of the pattern head satisfies
the decrease check but needs a THIRD def for the heads — which is back to two. One def,
three plain lists, one three-scrutinee `match`, and `Nil Nil Nil` / `_ _ _` does the
rest.

### 3. `List.get` IS THE RANGE TEST, AND WRITING AN EXPLICIT ONE IS A SECOND SOURCE
###     OF TRUTH FOR THE SAME FACT

`sorted(marg) != list(range(len(ps)))` is "every index in range AND no index repeats".
The first half is *already* `List.get(ps, y)` answering `None` for `y >= len(ps)`, and
writing `U32.is_lt(y, n)` beside it is the same check twice. The mutation that proves
it: force the threaded `n` to `2^32-1` and **no row moves**. So `perm.go` carries no `n`
at all, `perm_n` is deleted, and `mv_permlen` is the row that keeps the surviving half
honest. **A mutation that moves nothing is a claim about the CODE, not only about the
gate — check whether the code is saying the same thing twice before adding a fixture.**

### 4. AN `m`-OP MOVEMENT FIXTURE HASH-CONS, SO REUSING A `shape_to_shape_arg`
###     BUILDER FOR A DIFFERENT SHAPE SILENTLY BUILDS A SMALLER GRAPH

`g_mv_st23` is right for the RESHAPE and WRONG for a pad's offsets, because
`shape_to_shape_arg((0,1))` interns `CONST(0)` and `CONST(1)` and the arena already
holds them. The result was a six-node graph where CPython had twelve, and the node
count was the only row that saw it. This is the arena rule (bend2-constraints "a node
belongs in the arena as it stood after the last node built before it") landing on a
FIXTURE: `rg` for every builder and give each SHAPE its own, or the node count is a
transcription of the mistake.

### 5. A PYTHON `RESHAPE` PRODUCT CHECK IS `prod(ps) == prod(marg)`, SO THE BUFFER
###     SIZE MUST BE THE PRODUCT OF THE SHAPE

`RESHAPE(BUFFER(12), STACK(2,3))` is refused by CPython with `bad reshape: (12,) ->
(2, 3)` and by this fold with `resh_reject`. A two-dim fixture therefore needs
`size=6`, not `size=12`, and getting it wrong reads `ABSENT` on the movement node
above it — which looks like a bug in the movement arm. `g_mv_r23`'s header names it.

### 6. A `+` BINDING IS REFUSED IN A PLAIN BODY AND IN A `do IO<Unit>` BLOCK

```
def f(+x: Perm, +ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  +r = g(x)                      # REFUSED: expected a term, observed '+'
```
and
```
def main() -> IO(Unit>:
  do IO<Unit>:
    +a = build()                # REFUSED: expected a pattern (a binder or a constructor)
    (a, b) = probe()            # REFUSED the same way
```
So the two uses of a value are either ONE expression, or a def that takes it as a
parameter. `perm_ds.of` reads `ps` twice through `perm_n` and the walk, which is why
its `Some` binder is `Some{+p}`.

### 7. A `do IO<Unit>` BLOCK CANNOT BIND A TUPLE, SO A FIXTURE BUILDER THAT MAKES
###     TWO NODES IS CALLED FROM TWO `IO` DEFS THAT EACH REBUILD THEIR OWN

`O.UOp.new` is pure given an arena (the arena carries the intern table), so
`show_sym()` and `show_plain()` each call the builder and the second call finds the
node the first one added. That is the notes' "call the pure function twice" form, and
it is the only spelling that works where a `do` block cannot hold the values.
`.agents/slop/oracles/probe-su.bend` is the reproducer.

### 8. `Data` TYPES ARE NOMINAL AND `X.of` MAY NOT BE CALLED BEFORE `X`'s WHOLE CHAIN
###     IS DECLARED — BUT THE ERROR NAMES THE LAST DEF, NOT THE ONE TO MOVE

The recorded "no forward references" error is about a def whose NAME is unresolved.
The harder case is `perm_ds.of_walk` — legal text, correct order, and still "an unfilled
law is a dead claim" until the `perm_ds` chain below it is in place. The escape that
always works is to INLINE: `dt_of_if(Perm.ok(walk(...)), ...)` with the record built
inline, which is both shorter and the form that checks.

### 9. A REFUSAL AND A PYTHON `raise` ARE THE SAME PRINTED STRING, AND THAT IS A
###     CHOICE THE ORACLE MUST MATCH RATHER THAN A PROPERTY OF EITHER SIDE

This file prints `ABSENT` for "no entry in the resolved table" and `RAISE` for "the
entry is there and has no shape". CPython's oracle has to print `ABSENT` for a raise
too, or every refusing row is a permanent diff. The one row where the fold refuses and
CPython ANSWERS is then the ONLY line of the diff — `mv_expsym` — and it is the honest
place for the `ssimplify` divergence to live. **A gate that prints one string for "the
port cannot" and another for "Python cannot" cannot tell you which happened; make them
the same string and name the exceptions.**

---

## APPENDED 2026-10-02 by the `codegen/late.bend` regalloc unit. NUMBERING CONTINUES
## FROM THE `1..9` SERIES ABOVE (restarted at 1 by that series); these are `RA-1..RA-8`
## and are named by their `RA-` PREFIX so no number collides with anything above.

### RA-1. `Bool.pick` CHOOSES AN ARM AND DOES NOT SEQUENCE ONE, SO IT IS NOT AN `if`
###        AROUND A RECURSIVE CALL — THE DISCARDED ARM TAKES THE REST OF THE LIST WITH IT

`Bool.pick(T, c, a, b)` evaluates BOTH arms and answers one. Written as

    case v <> +r : Bool.pick(T, cond, step(t, v), walk(t, r))          # WRONG

the arm that satisfies `cond` answers `step(t, v)` and the walk over `r` is DISCARDED,
so a filter over a list silently keeps only its head. Three folds in
`tinybendygrad/codegen/late.bend` were written that way — `ra_lr.d1`, `ra_tw.go` and
`ra_blk.go` — and the live ranges came out with ONE index per uop
(`ra0_lr=v0>6:1 5 9`, where CPython says `1,5,9` for a vreg used three times). The
correct shape puts the pick on the ACCUMULATOR and the walk around it:

    case v <> +r : walk(r, Bool.pick(T, cond, step(t, v), t))          # RIGHT

`Bool.pick` is also **strict**, which is the other half: both arms run, so a discarded
arm that RECURSES is exponential in the list length and an arm that MUTATES is not
discardable at all. The rule that survives both: **`Bool.pick` on a value, `match` on a
`Bool` PARAMETER for control flow.** Reproducer: `.agents/slop/ra-mutate.py`'s
`live range: the backward walk becomes forward` row is the symptom.

### RA-2. A SKIP WHOSE TWO ARMS BOTH RECURSE CANNOT BE A `match`-ON-A-BOOL GUARD DEF,
###        BECAUSE THE GUARD DEF AND THE WALK ARE A MUTUAL RECURSION

Every `continue` that must skip work wants a guard def that matches on a `Bool`
parameter, because `match` may not scrutinise a call. When the SKIPPED arm and the
TAKEN arm each continue the walk — deduplicating a sorted list, where skipping and
stepping both recurse — the guard def and the walk call each other and bend refuses it
with "mutual recursion is refused". The way out is a single walk whose per-element
decision is a `Bool.pick` on a PURE helper: `Bool.pick(T, skip, s, do(e, s, i))`,
which is sound precisely because `do` does not recurse. `ra_w.go` in
`tinybendygrad/codegen/late.bend` is the worked example, and the comment there says why
the discarded arm must not recurse.

### RA-3. AN ASSOC LIST'S `put` APPENDS ITS LIST VALUE, SO "REPLACE THE BUCKET" IS A
###        DIFFERENT PRIMITIVE AND THE OBVIOUS SPELLING ANSWERS `old ++ old ++ x`

A `dict[k] = v` over a flat pair list reads like one operation and is two:
`tb_pput` replaces one PAIR, `tb_put` APPENDS `vs` to the existing bucket, and
`insert_before.setdefault(i, []).append(p)` is the append while
`reals.setdefault(i, {})[v] = live[v]` is the REPLACE. Writing the replace as
`tb_put(t, k, 0, tb_pput(vs, k, r))` — appending the whole recomputed bucket — answers
`old ++ new`, so a bucket written three times carries five pairs and a gate row that
sorts them prints one virtual three times: the right LENGTH and the wrong GRAPH.
`tb_vput` in `tinybendygrad/codegen/late.bend` is the three-line replace. The same trap
in scalar clothing is `lr[v].append(n)` written as `tb_put(t, v, 0, old ++ [n])`, which
answers `old ++ old ++ [n]`.

### RA-4. A `0`-MEANS-ABSENT TABLE READER IS A TRAP THE MOMENT INDEX 0 IS A REAL VALUE

`tb_get(t, k)` answers `0` for a missing key, which is the house convention and is
RIGHT for an arena whose index 0 is the bottom node. It is WRONG for a universe of
machine registers, where index 0 is `rax`: `if tb_get(live, v) != none` says "every vreg
holding rax is unloaded", so every use of one refills it, and the first symptom is a
row that is right on every register except zero. **Ask `tb_has(t, v)` and read `tb_get`
only once the key is known to be there.** Measured in
`tinybendygrad/codegen/late.bend`: the mutation moves `ra0_a5`, `ra0_a6`, `ra0_a7`,
every spills/before row and `rw_none`.

### RA-5. A REDUCTION THAT MUST WIN THE FIRST CANDIDATE AND THEN LOSE EVERY TIE NEEDS A
###        SEED FLAG, BECAUSE NO DISTANCE SEED CAN DO BOTH

`max(gen, key=...)` starts from the first element, so a fold written as
`keep if incumbent > challenger` loses the first candidate whenever its key is 0 — and a
key of 0 is not exotic (it is "a use at exactly `i`"). Seeding with a value above every
real key fixes the first candidate and then WINS every tie. `RaBd` in
`tinybendygrad/codegen/late.bend` therefore carries a `f: Bool` meaning "this is the
seed", and the fold answers `Bool.or(RaBd.f(a), incumbent < challenger)`.

### RA-6. A LIST OF PAIRS NEEDS A TWO-ELEMENT ARM BEFORE THE ONE-ELEMENT COVER, AND
###        `case +x <> y <> +q` NEVER SEES THE LAST PAIR

`case +x <> y <> +q` matches three or more, so a pair list that is EVEN by construction
ends with a pair only the `case _ <> _` cover can see — and that cover is the
"unreachable" one in the existing helpers. `ra_pairs.go` needs
`case +k <> r <> +q` / `case +k <> r` / `case _ <> _`, in that order. The error when the
2-element arm is missing is **"expected cases for Nil" pointing at a `case Nil{}` arm
that is textually first**, which is why that draft looked like a `Nil` problem at all.

### RA-7. A `List.sort` COMPARATOR MAY READ SEVERAL DISTINCT FIELDS OF EACH ARGUMENT,
###        AND A `String` IN THE KEY IS A REASON TO USE LEVELS RATHER THAN A PACKED `U32`

The recorded rule is that `List.sort`'s comparator has BARE parameters, so each argument
may be read ONCE. That is one read PER FIELD, not one per argument: `case Su{+d, +f, +n,
+x, v} Su{+e, +g, +m, +y, w}` with a `+` on four binders is exactly the permission, and a
four-level lexicographic comparator nests two helpers (`helpers.bend`'s `ix_le` shape).
So the "pack the sort key into one `U32`" trick — which is right for `lt_key`
(`rc * 64 + offset`, both bounded by a gated row) — is NOT forced when one component is
a `String`, and packing it would need a name-to-number rank the port does not have.

### RA-8. `--check-only` ON A FILE THAT IMPORTS `uop/fold.bend` IS NOT A CLEAN SIGNAL
###        WHILE ANOTHER AGENT IS EDITING `fold.bend` — AND A WARM CACHE HIDES IT

During this unit `tinybendygrad/uop/fold.bend` carried an in-flight mutual recursion
(`pad_shrink.go` <-> `pad_shrink.step`) that made **every** cold compile of a file
importing it fail with "an unfilled law is a dead claim" — including `late.bend`
untouched, whose 83 rows were being served from a warm cache and looked fine. The
symptom to recognise: the error names a def that is NOT IN YOUR FILE and a line number
that is NOT IN YOUR FILE. Iterate on a probe that imports only what the unit needs
(`Base`, `helpers.bend`, `ops.bend`), and treat a `late.bend --check-only` failure whose
location is outside the file as somebody else's edit until proven otherwise.

### RA-9. `+` ON A *CALLEE'S* PARAMETER IS A CONSUMPTION — SO AN AFFINE PARAMETER MAY
###        NOT BE READ TWICE EVEN THOUGH IT MAY BE *DECLARED* TWICE-READABLE

Measured on four one-liners: `def lin1(a: U32, b: U32) -> U32: U32.add(a, b)` is
legal, `def lin2(a: U32, b: U32) -> U32: Bool.pick(U32, U32.is_lt(a, b), a, b)`
fails with `b (consumed more than once)`, and the same body with `+a +b` passes. So
`Bool.pick`'s value arms are `+` params: passing `b` there CONSUMES it, and the
error is reported at the second read. The declaration (`b: U32` vs `+b: U32`) is
not where the decision is made — the CALLER's use of it is. The practical rule:
**when a value reaches a `Bool.pick` / a `.of` split, that value is spent, and the
only way to spend it twice is `+` on the parameter that holds it.** This is why
`hit: Bool` threaded through a pick-and-recurse step is always an error and the
fix is never to re-read it.

### RA-10. A `match` MAY NOT SCRUTINISE A COMPUTED VALUE **OR A LOCAL BINDER** — THE
###         ONLY LEGAL SCRUTINEES ARE A PARAMETER AND A PATTERN BINDER

`match Bool.and(U32.is_lt(a, b), c):` is `a match cannot scrutinize a computed
value: give it its own def`, and `x = O.Arena.op(ar, s)` followed by `match x:` is
the SAME error with different words: `a match cannot scrutinize a local binder`.
There is no third spelling. Two shapes always work: `def t(op: O.Op) -> Bool: match
op: ...` (the scrutinee is a parameter) or a two-scene match
(`case ARange{ids, at} OpsRANGE{}: ...` inside `def t(arg, op): match arg op:`).
**Any `match` whose head contains a call is a porting bug, and the error text is
the tell.**

### RA-11. `List.get` OVER `List<&2, Bool>` ANSWERS `None` FOR EVERY INDEX — AND A
###         `Maybe.default` THEN TURNS THE PREDICATE INTO A CONSTANT

`List.get(&2, U32, [0,1,0], 1n)` is `1`; the same call with `&2, Bool` over
`[False, False]` is `None`. Measured while porting `argsort`: `ix_asc_marked` read
a `List<&2, Bool>` through `Maybe.default(..., False)`, so EVERY index read as
unplaced, the selection sort always chose slot 0, and all seven `argsort*` rows
came out as the constant index 0 — with `--check-only` green and the type
checker satisfied. **A `Bool` list is a trap: carry `U32` flags (`0`/`1`) instead
and test with `U32.is_zero`.** The same caution applies to `List.length`, which
has no `&2, Bool` instantiation at all.

### RA-12. A `Data` BUILDER'S ARGUMENTS ARE EVALUATED LEFT TO RIGHT, SO A FIXTURE THAT
###         STORES `Arena.empty()` BESIDE A VALUE BUILT IN A GROWN ARENA KEEPS THE
###         STALE ONE

`IxF{O.Arena.empty(), ix_rngs.go(...)}` stores the arena that was empty BEFORE the
walk ran, so every node index read back as `NOOP` and eighteen gate rows printed
`NOOP,NOOP`. The fix is not `let` (rule RA-10) but to **return the pair from the
walk**: `case 0n: IxF{ar, acc}` where `ar` is the arena the walk was last handed.
The tell is a gate row full of the BOTTOM op's name: `NOOP` everywhere means "the
index is not in the arena you are reading", not "the builder made a NOOP".

### RA-13. A WALK WHOSE COUNTER STARTS AT `0n` AND MATCHES ON **THAT COUNTER** TAKES
###         `case 0n` ON THE FIRST STEP — THE DECREASE AND THE POSITION MUST BE TWO
###         PARAMETERS

`def pad.go(k: Nat, n: U32, acc) match k: case 0n: acc` with `pad(2)` gives `[]`,
so every "is index `k` placed" read said "not placed" and the whole sort
collapsed. Two shapes fix it: match on the COUNT (`pad.go(n: Nat, acc)`) when the
index is only needed via `List.get`, or carry `n` FIRST and `k` second when both
are needed (`pad_flags.go(n: Nat, k: Nat, ...)` — rule 29, `+` on a later
parameter does not disturb the first one's decrease). **If a walk produces the
EMPTY result for a non-empty input, look at which parameter the `match` is on
before looking at the accumulator.**

### RA-14. `Bool.pick(T, c, a, b)` ANSWERS `a` WHEN `c` IS TRUE AND EVALUATES BOTH
###         ARMS — SO AN INVERSION IS SILENT AND AN INVERSION IS COMMON

Three separate inversions in one unit, all green under `--check-only`, all caught
only by the oracle diff: `ix_bag.of` (`0`/`sub` swapped), `ix_nr_is_one`
(`== 1`/`!= 1` swapped) and `ix_asc_mark` (`p`/`1` swapped). The cheap defence is a
mutation table: invert each `Bool.pick` and record how many rows moved. A decision
that is written, commented and never CALLED also moves nothing, and that is the
other half of the same table — `ix_mv_flip_is_add`, `ix_mv_shrink_is_add` and
`ix_ds_take` were all three dead before it was run, each with a full comment
explaining what it was for.

## SIX MORE RULES, ALL MEASURED 2026-10-02 BY THE `runtime/support/hcq2` UNIT

Numbering continues from the previous series in this file (which started at 10
and 11 near line 3499); rule NUMBERS REPEAT across units, so cite the section
position, not a number.

### 1. `+` ON A `Data` PARAMETER IS NOT SAFE ACROSS A SELF-CALL

A fold that takes the element as a `+E` parameter and reads it AFTER the
recursive call in the same argument list reads a STALE value:

    def go(n: Nat, +h: E, +rest: List<&2, E>, +acc: List<&2, E>) -> List<&2, E>:
      ...
        case True{}: go(m, ehd(rest), List.tail(&2, E, rest),
                         List.append(&2, E, acc, [h]))

`h` is the head as it was on ENTRY, but the walk had already advanced past it, so
the fold emitted `1 1 2` for elements whose queue ids are `1 2 3`. Taking the
element out of the parameter list and reading it from `rest` fixes it, and
`rest` is `+` so it is legal to read three times. Reproducer and the fix are in
`tinybendygrad/runtime/support/hcq2.bend` at `qlist.go` / `pairs.go`.

### 2. ONE `+` PARAMETER PASSED TO TWO ARGUMENTS OF ONE CALL ALIASES

`f(g(acc), acc)` with `acc` a `+List` is accepted and is WRONG: `g` consumes its
argument and `f`'s other argument then sees a consumed list. Reproducer:
`step3(t, sep, put3(first(acc), h, sep, acc))` printed `14 2 8 4 1 ` where
`1 4 2 8 4 1 ` is right, in BOTH the interpreted and the native lane. The same
expression with the TEST and the VALUE inside ONE function (`f1(acc, h)` doing
its own `Bool.pick(List.is_empty(acc), ...)`) is correct. So the rule is
narrower than "`+` fixes a double read": `+` fixes two reads INSIDE one
expression, and it does not fix two reads as two ARGUMENTS of one call.

### 3. `List.append(a, A, xs, ys)` IS `xs ++ ys`, SO A FOLD THAT APPENDS IS FORWARD

This is already implied by the index near line 1590 but the SIGN is worth
stating, because the opposite reading is natural: `List.append(acc, [x])`
APPENDS. A gate that reversed the accumulator therefore printed `compute_0nvsubmit`
for `submit_nv_compute_0`, and `hq2.py:63`'s fold printed the parts BACKWARDS until
the reverse was deleted. The separator handling has the same shape: "no separator
on the first element" needs a `List.is_empty` test, which rule 2 above makes
unsafe, so put the separator in FRONT of every element and `String.drop` the
first one -- `String.length(sep)` is the count, so a two-character separator
works with no extra def.

### 4. A SELF-CALL MAY NOT PASS A COMPUTED `Nat` FUEL

`times.go(Nat.sub(n, 1n), ...)` is refused with "expected : a decreasing
self-call"; the fuel has to be DESTRUCTURED (`case 1n+m:`) and `m` passed
through. This is the same rule as `List.range.go` in base.bend and it is
separate from the "fuel is the FIRST parameter" rule: that one is about ORDER and
this one is about the argument being a COMPUTATION rather than a binding.

### 5. `Nat` AND `U32` IN A FUEL POSITION: `List.length` IS A `Nat` AND A `.go`
###    THAT TAKES `Nat` MUST NOT BE FED `U32.from_nat(...)`

`List.length(a, A, xs) -> Nat`, so a call `go(List.length(...), ...)` is right
and `go(U32.from_nat(List.length(...)), ...)` is a type error -- and the error
names `expected : Nat observed : U32` at the `List.length` call, which reads
like `List.length` is wrong rather than the wrapper. The wrapper is wrong.

### 6. A GATE ROW THAT READS A BOOL CANNOT SEE A FOLD THAT DROPPED ITS MIDDLE
###    ELEMENT

Two folds over the same list with the same first-use rule disagreed on the
MIDDLE element (`sig_tags` answered `0 2` where CPython answers `0 1 2`) while
every count row and every boolean row agreed. The fix was not a better fixture --
it was DELETING the second fold and deriving both readers from one. A gate cannot
see a second implementation drifting from the first unless a row reads the list
itself, and even then only if that list has an interior.

### 7. A MUTATION HARNESS MUST COMPARE VALUES, NOT ROW NAMES

`.agents/slop/hcq2-mutate.py`'s first version diffed row NAMES and reported `0`
for all thirty edits, which reads exactly like thirty blind spots. A mutation
changes what a row SAYS and never what a row is CALLED. This is the M30 trap in
a different hat and it is worth checking in any harness before believing a table
of zeros.

---

## TEN MORE RULES, MEASURED 2026-10-02 WRITING `runtime/support/am/amdev.bend`

Appended, not edited, continuing the count from the `codegen/opt` unit's 11. The
file is `tinybendygrad/runtime/support/am/amdev.bend`, its gate is 551 rows
diffed against a CPython oracle (`.agents/slop/amdev_oracle.py` 1870 rows) that
DRIVES `AMFirmware.__init__` and seven `AMDev` methods for real, its mutation
table is 18 measured entries, and both lanes print 564 identical rows.

### 1. `Tr.emit` APPENDS, SO THE ARGUMENT THAT READS **LAST** MUST BE THE **OUTER** CALL

`Tr.rd_cfg(cap, 1, Tr.rd_cfg(cap + 1, 1, t))` records `cap + 1` FIRST. The list
append is `xs ++ [x]`, the INNER call is evaluated first, and it has already
appended by the time the outer one runs. So a trace of "read the register, then
read the register again" needs the second read spelled OUTSIDE. This is invisible
on every fixture where the two arms of a `Bool.pick` have different lengths --
`aspm_link` reads one address per probe -- and shows up only on the fixture that
reads two in one step. MEASURED: `aspm.probe`'s order was backwards and only
`ama_aspm_chain` saw it. The general form: **a trace of a two-step sequence is
written outside-in, and the obvious inside-out spelling silently reverses it.**

### 2. `U32.shln` SATURATES PAST 31, AND THE RESULT IS A **PLAIN WRONG NUMBER**

`U32.shln(1, 34n)` answers `0`. So does `1 << 39`. Two places wanted a 64-bit
value and got a silent zero: `indirect_wreg_pcie`'s `1 << 34` (the PCIe window's
extension bit, and the whole reason `pc.addr_hi` exists as a two-word function)
and the palloc ladder's `1 << (i + 12)` for `i >= 20`. `beautiful_mnist`'s agent
found the same family as "a `Nil` that means everything"; this is its twin --
**a saturating shift is a zero that typechecks, and `U32.from_nat` will happily
print it.** The cure is the same: ask for the TWO WORDS and make the test
`palloc.big(i)`, which is itself a row.

### 3. A `U32` SHIFT IS `U32.shln` AND A ONE-ARG `U32.shl` IS `<< 1`

`U32.shl(a)` is `a << 1`; `U32.shln(a, n)` is `a << n`. The two-argument form is
NOT `U32.shl`, and writing it that way gives `expected : a function type,
observed : U32` -- which names the *argument* and not the function. The confusion
is worth recording because the error points at the wrong line entirely.

### 4. A `U32` SHIFT TAKES A `Nat`, AND `Nat.sub(...)` NEEDS `U32.from_nat` TO GO BACK

`U32.shln(a, U32.to_nat(x))` is the idiom for a shift whose amount is a runtime
`U32`, and `U32.sub(a, U32.from_nat(Nat.sub(n, 1n)))` is the idiom for an index
walk. Mixing them gives `expected : Nat, observed : U32` at the `U32.sub` call,
which reads like the WRAPPER is wrong rather than the conversion.

### 5. A LIST-DRIVEN SEARCH MUST CARRY AN INDEX AND A BEST **SEPARATELY**

The first two-way-lookup walk carried ONE counter and incremented it on
non-match. Every lookup then answered the LAST element of the table, and the gate
caught it because `amh_of_1` said `MP0` and `amh_rev_gc` said 255 -- both of which
are the last row. Carrying `i` and `best` separately and updating `best` only on a
match is the fix, and `best` must start at the LENGTH so "no match" is out of
range and `List.get` answers `None`. Then `:400`'s dict comprehension's
OVERWRITE semantics falls out of the same shape: the search is for the LAST match,
not the first, and `UVD_HWID`/`VCN_HWID` being both 12 is what proves it.

### 6. A COUNTDOWN BINDER `m` MAY BE READ ONCE PER ARM, SO A SECOND USE IS A DEF

`case 1n+m:` then `f(m, g(m, ...))` is `m consumed more than once` even though
`g` takes `m` as a parameter. The escape is a one-line `.at`-named sibling
(`amaprow.at(i, ...)`), not a `+` on the binder. This is the same shape as rule
`32`'s `Bool.pick` affinity and it bites on every fold that needs an index and an
element of the same list.

### 7. AN `IO<Unit>` DEF MAY NOT HAVE A `<-` BIND AT ITS TOP LEVEL

`t_layout() -> IO<Unit>: +a : Unit <- sfrow(...)` is `expected : def, type or
law, observed : ':'`. The `<-` binds belong inside a `do IO<Unit>:` block, and
`a` `do` block may contain no `match` at all, which is why every dispatch in this
file is its own def and the gate rows are bare statements.

### 8. A GATE LIST ROW SHOULD BE ONE ROW PER ELEMENT, NOT A JOIN

`jrow("...", xs)` prints `|a|b|c` and an oracle disagreement about WHICH element
is wrong is invisible; two of this file's disagreements (`aids_full4`, the ASPM
read addresses) were exactly that. `amaprow`/`aidsrow` print one row per element
with the index in the NAME, and the mutation table's `ama_aspm_chain_rd_1` /
`ama_aspm_chain_rd_2` pair is readable precisely because they are separate rows.
A join is for a list whose LENGTH is the claim; everything else wants elements.

### 9. A MUTATION HARNESS'S SCRATCH COPY MUST LIVE **IN THE TREE**

`import ../../../helpers.bend` is a RELATIVE path, so a copy under `$TMPDIR` cannot
resolve it and EVERY mutation reports "did not compile". Read as a table that is
twenty-two blind spots. The `amdev` harness printed exactly that before the copy
was moved beside the original. Same family as the `strcmp`/`dirname` note above:
**an absolute-looking path in a message can be relative in its effect.**

### 10. PYTHON SHORT-CIRCUITS AND `Bool.pick` DOES NOT, SO A `while` GUARD IS TWO GUARDS

`while cap and cap not in seen and read_config(cap, 1) != 0x10` reads the
register only when the first two conjuncts hold. Written as one predicate and one
unconditional emit, the port over-reads -- four reads where CPython makes three.
Splitting the guard into `pre` (guards the READ) and `more` (guards the BODY) is
the fix, and the two are genuinely different claims: `more` is :151's condition,
`pre` is Python's evaluation order.

## NINE MORE RULES, MEASURED 2026-10-02 PORTING `runtime/support/am/ip.py` TO
## `tinybendygrad/runtime/support/am/ip.bend`. NUMBERING CONTINUES the `1..10`
## SERIES ABOVE (restarted by that series); these are `1..9` again, so CITE THE
## LINE POSITIONS, not the numbers. Drivers: `.agents/slop/ip_sweep.py`,
## `.agents/slop/ip_mutate.sh`.

### 1. `Nat.sub` TRUNCATES AT ZERO; IT IS NOT A SATURATING SUBTRACT

`base.bend:573` is `case 0n _: 0n`, so `Nat.sub(a, b)` is `max(0, a - b)` with no
flag and no trap. MEASURED: `sub(3n,10n) = 0n`, `sub(31n,33n) = 0n`,
`sub(18n,32n) = 0n`, `sub(50n,32n) = 18n`. A helper that means "shift this unless
it is at least 32" and writes the amount as `Nat.sub(32n, n)` therefore computes a
*smaller* number, not zero, for every `n` above 32 -- a plain wrong number with no
error. Compare with `U32.sub` (line 3 of the `1..10` series above), which is the
one that wraps. The branch has to be `U32.is_ge`, not a `Nat` subtraction.

### 2. `H.data64_hi` / `H.data64_lo` DESTRUCTURE THE PAIR, SO ON `data64_le` THEY ARE SWAPPED

`helpers.bend:1261-1275` gives `data64(x) = (hi, lo)` and `data64_le(x) = (lo, hi)`,
and `data64_hi`/`data64_lo` just bind `(hi, lo) = r` and pick a position. They do
not know which producer made the pair. MEASURED on one word with distinct halves:
`lo(data64(x)) = 0x55667788`, `lo(data64_le(x)) = 0x11223344`, `hi(data64(x)) =
0x11223344`, `hi(data64_le(x)) = 0x55667788`. So `data64_lo(data64_le(x))` is
silently the HIGH half, a plain wrong number. This is the same shape as rule 9 of
the `1..10` series: a name that reads like an accessor and is really a position.

### 3. `H.getbits(value, start, end)` TAKES THE **IN-WORD** PAIR, NOT A SHIFT AND A WIDTH

`helpers.bend:1294` is `value >> start & ((1 << (end - start + 1)) - 1)`, so the
second argument is the LOW bit and the third is the HIGH bit of the field, and
rule 1 applies to `end - start`. MEASURED: `getbits(v, 8, 15) = 51` (CPython agrees),
but `getbits(v, 8, 7) = 1` and `getbits(v, 15, 8) = 0` -- a descending pair yields a
ONE-bit mask where CPython raises `ValueError: negative shift count`. A port that
has a global `hi` and a global `lo` and passes a derived width as the third
argument is passing a shift where a bit index belongs, and rule 1 hides it.

### 4. A GATE ROW THAT RE-TRANSCRIBES A PYTHON EXPRESSION WILL AGREE WITH A PORT THAT MISREADS IT

`lo, _ = data64_le(x)` in the oracle is a transcription of `*data64_le(x)`, and a
star-unpack is not a two-target bind. The port dropped the high word, the oracle
dropped the high word, and **all 447 rows agreed on a sixteen-word PM4 packet that
`ip.py:108-110` builds as seventeen**. Both lanes green, both wrong, and the
mutation table could not see it because the gate agreed. MEASURED by asking
CPython for `len(pkt(...))`: 17. An expectation is only an expectation if it CALLS
the thing; a hand-written restatement of a line proves the restatement.

### 5. A `*`-UNPACK AND AN INDEX ARE DIFFERENT CARDINALITIES, SO A LIST LITERAL NEEDS ITS OWN LENGTH ROW

The same fix as rule 4 has a mechanical half: gate `len()` of every list literal
whose length Python fixes, because a `def` that forgets one element still checks and
still prints. `amp_kiq_pkt_n_a/n_b/n_c` existed and said 16. The rule generalises
to every variadic Python construct: `*xs`, `**kw`, `(*a, *b)`, generator `yield`.

### 6. A MUTATION THAT NEVER APPLIED REPORTS **0**, WHICH IS INDISTINGUISHABLE FROM AN EQUIVALENCE

`ip_mutate.sh` splits its edit expression on `|||`. One row shipped a single `|`,
`split` raised, the scratch stayed pristine, and the diff of the pristine file
against the pristine base is 0 -- printed next to 42 real measurements as if it were
a measurement. The harness now asserts `len(parts) == 2` and both halves non-empty
and prints `HARNESS-FAIL` instead. The general form: **a mutation runner must
distinguish "the edit did not land" from "the edit changed nothing"**, because the
second is a finding and the first is a broken instrument. Same family as rule 7 of
the `1..10` series (scratch must live in the tree) -- a harness that fails silently
reports twenty-two blind spots as truth.

### 7. A DEF MAY NOT CALL A SIBLING DEFINED LATER IN THE FILE

`expected : a filled definition (an unfilled law is a dead claim: live code cannot
use it)`. A mutation that rewrites `mqd.qsize` to reach for `sdma.rbsize` -- the
more honest spelling of "qsize is really rbsize" -- does not compile, because
`sdma.rbsize` is defined 8 lines further down. It reads as COMPILE-FAIL, which is
indistinguishable from a real breakage. Inline the wrong formula instead; that is
the same mutation and it is expressible.

### 8. AN UNREAD CONSTANT IS NOT A PORT, AND A LEAF SWEEP IS WHAT PROVES IT

Perturbing every numeric constant by one unit: 46 of them had **zero call sites**
anywhere in the file -- no def read them and no gate row printed them, so no
mutation of them could ever move a row. They were deleted and all three lanes
re-verified byte-identical, which is the point: a def with no call site is
provably behaviour-preserving to remove, so keeping it is only cost. This is the
sweep's real dividend. A mutation table is not only a way to find bugs; it is the
only mechanical way to find the part of the port that is not a port.

### 9. TWO PYTHON LINES MAY SHARE AN F-STRING REGISTER NAME, SO A NAME-ONLY KEY IS NOT A KEY

Sixteen of the 115 register field names in `ip.bend` are f-strings
(`regCP_{cntl_reg}_CNTL`, `regIH_RB_CNTL{suf}`, `{reg_pref}_64`, ...) and nine of
them appear on two lines each. A neighbour-swap of the FIELD NAME is therefore a
genuine equivalence for those rows and moves nothing, while a swap of the LINE
moves every row. `Row` is keyed on `(ln, reg)` for exactly this reason, and the
measurement is what says so: `REG:<n>` moves on 115 of 115, `REG:<n>@name` moves on
106 of 115, and the nine that do not are MEASURED to share their neighbour's name.

---

## APPENDED BY schedule/rangeify.bend (the `mp_replace` ARG repair)

Numbers continue from whatever the preceding block ends at -- see the header
INDEX at the top of this file, because rule NUMBERS have now repeated four times
and this block deliberately does NOT renumber. Cite these by position: they are
the rules after the `ip.bend` §9 block at line ~7945.

### 1. A SIGNATURE WIDENING IN ONE FILE IS A TYPE ERROR IN EVERY CALLER IN THE REPO

`movement.bend`'s `mp_replace` went from `(op, ar, self, src)` to
`(op, arg, ar, self, src)` in `e959ece3798f`. That commit fixed `movement.bend`'s
own two call sites and left FOUR in `schedule/rangeify.bend`, so rangeify stopped
compiling with `expected : O.Arg`. The bisect is four commands: list the
revisions that touched each file, read the def at each, and the widening commit is
the only difference. `jj log -r 'ancestors(@) & files(<the def's file>)'` is the
command that finds it.

THE LESSON, and it is the one worth keeping: the breaking commit fixed a real bug
and was CORRECT on its own terms. A change that is right in the file you own is
still a change to every caller's type. Widening a parameter is not a local edit.
Before widening a def that other files import, `grep -rn` its name across the
tree and fix the call sites in the same commit.

### 2. THE BINDING ARGUMENT ORDER IS WHAT SAYS WHICH `O.Arg` A REBUILD PASSES

`UOp.replace` (ops.py:252) is
`new_args = (kwargs.pop("op", self.op), kwargs.pop("src", self.src), kwargs.pop("arg", self.arg), kwargs.pop("tag", self.tag))`,
so a rule that replaces ONLY `src` passes `self`'s OWN arg, and a rule that
replaces only `arg` passes a DIFFERENT one. Making `arg` an explicit parameter is
what stops `mp_replace` reading it off `self` -- and reading it off `self` is
wrong precisely for the arg-replacing rule. So when a rebuild's signature gains an
`arg`, the argument is not decoration: it is the only place the distinction lives,
and `mp_arg(ar, self)` vs `O.ANone{}` is a semantic choice, not a type choice.

### 3. A COMPILED FILE IS NOT A GATE. NEITHER IS A ROW OVER A FIXTURE THAT CANNOT SEE THE REPAIR.

Four call sites were repaired by passing each node's own arg. Every node the four
rules can reach in that fixture is an AFTER, an MSTACK or a CALL, and ALL of them
are given `ANone` -- and an AFTER's and an MSTACK's arg is `None` in CPython too
(measured: `raf_after_arg_is_none = 1`, `mstack_arg_is_none = 1`). So the obvious
row, `eq_arg(rebuilt_arg, original_arg)`, is `eq_arg(ANone, ANone)`: TRUE for a
correct port AND for one that hardcodes `ANone`, which is precisely the mistake
that silences this type error. A green `--check-only` on 2743 lines plus 84
existing rows would have been ZERO evidence.

THE FIXTURE HAD TO GAIN A NODE. A CALL's arg is a `Kernel`, so
`CALL(IXSTG, RS)` carrying `AKernel{KernelInfo.of()}` is the node that separates
the two spellings, and its `ANone` twin one row away is the negative. Generalise:
**when repairing an argument-passing defect, ask what the fixture's value at that
position is, and if every reachable node carries the same value, the property is
unobservable and the gate needs a new node.** `eq_arg(x, y)` DISPATCHES ON `x` and
matches `y` (ops.bend:1559), so the expected arg goes first.

### 4. `UOp` DOES NOT VALIDATE `arg` AGAINST `op`, SO A "STRUCTURALLY IMPOSSIBLE" BLIND SPOT MAY BE A FIXTURE REQUEST

M1 and M4 (answering `ANone` at the AFTER site and at the MSTACK site) moved 0
rows. The tempting conclusion is "AFTER and MSTACK args are always `None`, so
these are theorems". MEASURED, and it is false: `UOp(Ops.MSTACK, src, arg=<a
Range>)`, `arg=KernelInfo()` and `arg=ParamArg(...)` all construct without
complaint, and so do the same three on an AFTER. `ops.py` does not type-check
`arg` against `op`. So a zero at an arg site is a REQUEST FOR A FIXTURE -- one node
of that op carrying a different arg -- and not a theorem, until you have actually
tried to build the node that separates the two answers. The honest zero is a
theorem only when the distinguishing node CANNOT BE CONSTRUCTED.

### 5. A COMMENT THAT PROMISES A ROW IS NOT A ROW, AND FORCING THE RULE'S CLAIM IS HOW YOU CATCH IT

`ct_4`'s comment says "`ct_4_ans` is the row"; `ct_8`'s says "`ct_8_ans` is the
row". `grep -n ct_8_ans` finds the comment and NOTHING else -- neither name is in
`main`. The mechanical proof that a def is ungated is to force its CLAIM test to
`True{}` and diff whole `name=value` lines: M11 moved 0 rows, so no row in the
file can see `ct_4` at all, whatever it does. Do that once per rule whose comment
promises a row. (Same class as the three defs `schedule/indexing.bend`'s agent
found written, commented and never called.)

### 6. FOR A `.f` PATTERN, THE ACCEPT SET IS THE OUTER NODE, AND `UPat.var` MAKES THE REPLACE AN IDENTITY

`UPat(Ops.MSTACK, src=(UPat.var("s"),)).f(Ops.INDEX, allow_any_len=True,
name="idx")` rewrites the INDEX -- `name="idx"` is on the OUTER pattern -- and
`idx.replace(src=(s,)+idx.src[1:])` with `s = idx.src[0]` is an IDENTITY replace,
so `hop_self` turns it into "no answer". Measured on the Python side:
`pm_const_buffer_folding.rewrite(mst)` is `None` -- the MSTACK alone is never
claimed. A port whose table entry carries the SUB-pattern's op (`{MSTACK}`) while
its body reads the OUTER node's op is therefore gating on an op the body then
rejects, and the rule can never fire. Check `rewrite(<sub-pattern node>) is None`
in CPython before believing an accept set built from the sub-pattern.

## Bend 2.0.34 -- facts learned porting `tinybendygrad/runtime/support/nv/ip.bend`

### 1. `Bool.pick` ANSWERS THE ARM IT TAKES AND THE OTHER ARM NEVER REACHES THE ANSWER

`def Bool.pick(-A: Type, c: Bool, a: A, b: A) -> A` matches on `c`, so a
self-call placed in the UNTROKEN arm of a `Bool.pick` is unreachable for the
values that select the other arm. Measured, not inferred: a fold written

    Bool.pick(T, eq, x, go(t, y))

recovers from `y` but never advances past the first `eq`, so
`Bool.pick(U32, hit, x + 1, go(t, n))` printed `ip_d_fns_max=1` against
CPython's `223`. The consequence is bigger than the bug: **a fold that means to
keep walking cannot express it with `Bool.pick` at all**, and what looks like a
policy in the guard is really a consequence of where the recursion sits.

    # FIRST-WINS (never recurses past a match), the `Bool.pick` shape:
    Bool.pick(Cv, Cv.hit(a), a, Bool.pick(Cv, eq, Cv{True{}, c}, go(t, a, v)))

    # LAST-WINS (recurses from the CALLER), the shape that actually walks:
    Bool.pick(Cv, eq, Cv{True{}, c}, a)        # as a separate def
    case c <> t: go(t, step(c, a, v), v)

Flipping the guard in the first -- `Bool.and(Cv.hit(a), Bool.not(U32.is_eq(...)))`
and every rearrangement of it -- is a NO-OP, because `go` sits inside the arm
that is dropped. So when a mutation of a guard moves zero rows, ask whether the
mutation was reachable before concluding the rule is untested. Eight of the
rules in this port were written that way at least once.

### 2. NO FORWARD REFERENCES: a use of an unseen name is a HOLE, NOT A DEF

    def rp.late(...) -> Tr: rp.bumped(seq, handle, rp.door(e))   # rp.bumped below
    - expected : a filled definition (an unfilled law is a dead claim:
      live code cannot use it)
    - observed : rp.bumped

The message names "a law" and shows the callee, which reads like a type error and
is not one. The helper must be defined BETWEEN the def that reads the parameters
it threads and the def that uses it. This is also why the file is assembled from
parts and then topologically reordered: the source order of a `.bend` file is a
dependency order, so a rule whose threads run through two defs cannot be cut at
one of them, and a mutation harness that injects one def has to inject it in the
right SLOT.

### 3. `Bool.and` IS LAZY, `Bool.or` IS LAZY, AND NEITHER IS COMMUTATIVE IN ITS EVALUATION

    def Bool.and(a, b): match a: case False{}: False{}; case True{}: b
    def Bool.or(a, b):  match a: case False{}: b;        case True{}: True{}

`Bool.and(False, <diverging>)` answers `False{}`. Anything that must be evaluated
for its effect cannot go inside one of these, and in a port where the second
argument is the expensive one the evaluation order is observable through
interpreter timing.

### 4. A PATTERN BINDER CANNOT BE READ TWICE, AND A PARAMETER SHADOWED BY ONE IS SILENT

    def tr.at(+t: Tr, seq: U32) -> Tr:            # `seq` is BOTH
      match t:
        case Tr{calls, wp, +seq, handle, fail_at, refused}: seq   # the FIELD
      Tr{calls, wp, seq, handle, fail_at, refused}

No error, no arity complaint -- the binder wins and the parameter is unreadable.
`tr.at` became a no-op: all seven requests printed `ip_rp_<i>_seq1=1` and every
checksum was the sequence-0 value. The compiler reports a shadowing collision
ONLY when the binder's name also matches a record field name elsewhere in the
pattern. **A parameter and a pattern binder must not share a name, and the
temptation to give them the same name is strongest exactly where the code is
shortest.**

    # observed : refused (consumed more than once)

is the *other* half of the same rule: two matches of one binder, e.g. reading
`Tr.calls(e)` and `Tr.refused(e)` off the same consumed `e`. The message names
the field, not the twice.

### 5. NO HEX LITERALS IN BEND 2.0.34

    def f() -> U32: 0x544942
    - expected : a numeric literal
                         ^
    - observed : 0x544942

The caret sits on the `x`, so the message reads like a lexing complaint about the
character. Every constant from a C or Python source is a DECIMAL literal and has
to be transcribed, which is a real error source: `ref.bit_sig` carried 5444674
where `0x544942` is 5523778, and no row could see it because the row
`ip_refuse_bit_sig_val` printed the same wrong constant back. A gate cannot check
a transcription against itself; it needs CPython.

### 6. DEAD DEFS ARE INVISIBLE TO A BASE-NAME AUDIT

A def named `rp.pair.hi` is scored alive by the several hundred uses of the
`rp` namespace, and `def rp.acc` was scored alive by the three COMMENTS that
mention it. A name-based audit over 584 defs found 4 dead; matching the FULL
dotted name with comments and strings stripped first found 30. Two of those 30
were an abandoned design -- `type Wv` plus `rp.acc`, `rp.pair.hi`, `rp.pair.lo`,
which threaded a `{h, l}` record through a recursion instead of running two
walks. `Bool.pick` is why the record version never worked (see 1 above), and the
leftovers sat there through 1174 green rows because a dead def cannot fail.

The reliable test is not reachability but the mechanical one: force the def's
CLAIM to `True{}` and diff whole `name=value` lines.

### 7. THE 32 KiB INTERPRETER CLIFF DOES NOT REPRODUCE FOR REAL `.bend` CONTENT

The note elsewhere in this log records a cliff past 32 KiB of interpreted
definitions. 185 KB of real defs across 543 top-level definitions interpret in
0.12 s, and the compiled lane prints the same 57 KB of rows. Whatever the cliff
was measured against, it was not a large `.bend` file.

## SEVEN MORE RULES, MEASURED 2026-10-02 FIXING `schedule/rangeify.bend`'s `ct` TABLE
### 1. A `.f()` CHAIN PUTS THE OP PASSED TO `f` AT THE PATTERN'S ROOT, SO `pdict`'s KEY IS THAT ONE AND NOT THE RECEIVER'S
`def f(self, op, **kwargs): return UPat(op, src=(self,), **kwargs)` REBUILDS the
pattern with `op` as the ROOT. `PatternMatcher` keys `pdict` on `p.op` and
`rewrite` looks the node up with `pdict.get(uop.op)`, so for every `.f()` entry
the KEY is the op handed to `f` and the receiver's op is the CHILD's and belongs
in the rule's body test. The two are different ops on the same two-node shape, and
a table carrying the wrong one makes a rule UNFIREABLE rather than wrong: the
engine never looks the node up at all, so no error and no wrong answer -- just
silence. Measured over all nine `pm_const_buffer_folding` entries: roots
`INDEX AFTER END STAGE STAGE STAGE INDEX INDEX INDEX`, i.e. ALL NINE are
single-op sets, while `early_reject` -- which IS the child's op -- is non-empty for
three of them. The port had the child's op in five of the nine `ops` sets.

### 2. `Bool.and(x, True{})` IS `x` AND `Bool.or(x, True{})` IS `True{}` -- SO A FOLD WITH AN `ALL TRUE` BASE IS NOT A SUBSET TEST UNDER `or`
`rf_early.go` folds a reject set with `and` over a base case `True{}`. Swapping
`and` for `or` therefore does NOT give "the same function on a singleton set", as
a previous revision of `rangeify.bend`'s own mutation table asserted as a PROOF:
it makes the whole reject test VACUOUS, because the first `or` against the base
case absorbs. That assertion was REFUTED by measurement once the fixture had a
node whose reject set was satisfied by an op in the WRONG src position -- the
mutation then moved a row, 1 -> 0. The lesson is not about `or`; it is that a
mutation whose documented justification is an algebraic identity needs the
identity to be re-measured when the fixture grows, because "this cannot move a
row" is a claim about the FIXTURE as much as about the fold.

### 3. A FIXTURE WHOSE EVERY NODE HAS AN `ANone` ARG CANNOT GATE AN ARG-BEARING REWRITE, AND THE FIXTURE THAT FIXES IT IS NOT THE OBVIOUS ONE
`mp_replace` was widened to take `arg` because `UOp.replace` (ops.py:252) takes it
as a kwarg, and four call sites in `rangeify.bend` were left on the old form. The
repaired rows could not see the repair: every node the four rules can reach in
that fixture was an AFTER, an MSTACK or a CALL with `ANone`, and an AFTER's and an
MSTACK's arg is `None` in CPython TOO, so `eq_arg(rebuilt, original)` was
`eq_arg(ANone, ANone)` -- true for a correct port AND for one that hardcoding
`ANone`. The fix is not "give a fixture node a non-`ANone` arg" but "give one a
non-`ANone` arg ON THE OP THAT THE RULE REBUILDS, and check the fold reaches it":
an INDEX carries a `(axis_id, AxisType)` pair in CPython (prepare.py:70 passes
`arg=idx.arg`) and `ops.bend` has it as `O.ARange{ids, at}`. `UOp` does NOT
type-check `arg` against `op`, which is what makes such a node constructible at
all.

### 4. A GATE THAT FOLDS `F.folded(ar)` OVER AN ARENA SNAPSHOT CANNOT READ A NODE INTERNED AFTER THAT SNAPSHOT
`g()` builds the fixture as one `+`-consumed chain and then hands
`F.folded(O.Found.ar(<the LAST node>))` to the `G` record. Adding a node AFTER the
`F.folded(...)` call and listing it in `G.ix` compiles, checks, and reads the
arena's BOTTOM node -- `Arena.at` answers `None` past the end and the bottom's op
is `OpsNOOP`, so `lay` (the length) rises while every property of the new node
reads as the bottom. Symptom: a row naming a brand-new node prints 0 while a row
naming its own INPUT also prints 0, and `mp_op` on it answers 4 (`OpsNOOP`).
MEASURED here: `rgd=60 axis=LOOP op=4` for a node the list said was 63.

### 5. A DEF NAMED `X.n` NEXT TO `def X.go` IS A METHOD, AND A CALL THAT FORGETS ONE ARGUMENT SAYS SO AS A PARTIAL APPLICATION
`def ct_claim_n(ts, ar, ix) -> U32` called as `ct_claim_n(ct_table(), g_ar(g()))`
reports `expected : U32, observed : @ix:U32 -> U32` -- which reads like the
def is a method with a receiver. It is not: the def is fine and the CALL is one
argument short, and Bend reports the resulting partial application against the
declared return type. Renaming the def, its parameters, its helper and its arity
all fail to change the message, so the cheap way to recognise this shape is the
ARITY of the call, not the name in the error.

### 6. A RULE BODY WITH NO PATTERN TEST OF ITS OWN IS A HOLE, AND THE MUTATION THAT FINDS IT IS THE ONE THAT MAKES A REJECT SET VACUOUS
A rewrite whose claim lives entirely in its table entry is one `rf_early` mutation
away from firing on a node the pattern does not match -- because `early_reject`
is satisfied by an op in ANY src while a `(UPat(...),)` first-src pattern needs it
at src[0]. Measured: with the body ungated, `INDEX(RANGE, AFTER)` was claimed by
a rule whose pattern is `INDEX(AFTER, ...)` and was rebuilt. Gating the body on the
same predicate the pattern spells costs nothing and is what makes the reject sets
provably redundant.

### 7. AN INNER `Maybe` IN A FOLD'S RESULT IS "THIS NODE HAS NO VALUE"; AN UNRESOLVED NODE IS "THE FOLD CANNOT ANSWER" -- AND A STUB ARM INVERTS BOTH
A predicate written `Bool.not(<stub that is always False>)` answers `True` for
every value it is given, which is a silent inversion rather than a missing case.
Here `s.device is None` was spelled "not (a device is deviceless)" over an
`S.Dev`, and `S.Dev` has no deviceless member, so the answer was `True` for every
device-BEARING node -- and every node the old fixture could reach had a deviceless
`s`, so the inversion was invisible. The general rule: a stub arm that is a
constant is a claim about the whole datatype, and it should be the value that
makes the surrounding `match` TOTAL and OBVIOUSLY so, not the one that flips the
test.

## Bend 2.0.34 -- facts from the CONSTANT AUDIT of `runtime/ops_cl.bend` and `runtime/ops_webgpu.bend`
Numbering continues from the seven rules of "SEVEN MORE RULES, MEASURED 2026-10-02 FIXING
`schedule/rangeify.bend`'s `ct` TABLE", which end at the file's last line 8232. Positions,
not numbers, are the citation key (rule NUMBERS REPEAT across units).

### 1. A SYMBOL-SET CHECK CANNOT SEE AN INDEX TRANSPOSITION, AND THAT IS EXACTLY THE BUG IT WAS BUILT FOR
`.agents/slop/cl_vendor_scan.py` asserts that every `cuda.X` in `ops_cuda.py` is a cell in
`vend.cu`. I moved `cuModuleLoadData` from `OP_PRG_FROM_BIN`(11) to `OP_BUILD`(12) -- the
transposition that scan was written to find originally -- and it reported **0 problems**. A
right table and a transposed table hold exactly the same 21 CUDA symbols, so any check that
compares a table to a SET is blind to it by construction. The sufficient half is per-ROW: the
`(vendor, python line, op tag)` triple that each `Tr.emit(OP_X(), ...)` site carries, checked
against what CPython's AST says that python line calls (`.agents/slop/cl_emit_map.py`). Both
halves are needed -- the set check catches a missing or phantom symbol, the row check catches
the misindex -- and "my scan passed" means nothing until a control has been applied to it.
**Every constant oracle must be shipped with a mutation it is supposed to fail.**

### 2. `+1` ON A TAG SPACE MEASURES COLLISIONS; A COLLISION-FREE VALUE MEASURES PINS
`CALL_CREATE+1 == CALL_WAIT`, so every `Tr.args(CALL_CREATE, ...)` starts counting the waits
and eleven rows move for a reason unrelated to pinning a value. Re-running the sweep with
`12345678` (measured absent from both files' constants and rows) drops `ops_webgpu` from 37
constants that "move" to **22**, and the 45 that stay put are constants whose gate rows compare
the trace against **the same constant on both sides**. That is `device.bend`'s `sig=0 4 5`
rule at full size: `row("wg_init_exact", u32_list_eq(created(t), [OBJ_INSTANCE, OBJ_QUEUE]))`
moves nothing when `OBJ_INSTANCE` moves, because both sides moved. A row whose expected value
is a `def` of the thing under test is not a row, and it is invisible under BOTH sweeps -- only
the oracle sees it.

### 3. AN F-STRING IS A LITERAL *AND* CODE, SO "STRIP THE STRINGS" IS NOT A FILTER
The first `cl_vendor_scan.py` removed every `"..."` before looking for `hip.hipGetErrorString`
and reported it a PHANTOM CELL, because `ops_hip.py:10` writes that symbol inside an f-string:
`f"HIP Error {status}, {ctypes.string_at(hip.hipGetErrorString(status)).decode()}"`. Reading
`ast.Attribute` nodes and taking the line from the node gets both cases right and also handles
the f-string. The same applies to an int: `ast.parse("b,4)[0] // (16 if ... else 1)")` is a
SyntaxError, so index EVERY literal of the whole module by the lines it SPANS
(`lineno..end_lineno`) rather than parsing one line at a time.

### 4. A CONSTANT THAT APPEARS ON BOTH SIDES OF ITS OWN COMPARISON CANNOT BE MUTATED AT ALL
`vend.name(v, op)` compares `v` against `V_CUDA()`/`V_HIP()` and every gate row passes
`V_CL()`/`V_CUDA()`/`V_HIP()` as the ARGUMENT, so `V_HIP + 1` and `V_HIP = 12345678` both
leave all 445 rows byte-identical (MEASURED). The only property the port pins is that the three
are DISTINCT, which `V_CL+1` and `V_CUDA+1` both break. The honest classification is
PORT-INTERNAL TAG, and the honest report says its VALUE is unconstrained rather than claiming
`2` was verified.

### 5. A LADDER WHOSE LAST ARM IS `case _` CANNOT MUTATE ITS LAST INPUT -- THAT IS A THEOREM
`sync_name.two.at` matches `case 1n..5n` and answers `case _: sync_name.workdone2()`, so
`SYNC_WORK_DONE` is 6 and 12345678 and 4294967295 are the same function over every input.
A row that moved would be a test that cannot fail. The corollary is a latent trap worth naming:
a SEVENTH `SYNC_*` id would silently answer `workdone`, so the ladder works by EXHAUSTION and a
new arm must be added in both places.

### 6. `mmap.PAGESIZE` IS HOST-DEPENDENT, SO A `U32` CONSTANT CANNOT BE ITS PORT
`PAGE_SIZE = 4096` at `ops_cl.bend` claimed "mmap.PAGESIZE is 4096 on every platform tinygrad
supports". MEASURED on this host (arm64 darwin): `mmap.PAGESIZE == 16384`. Neither 4096 nor
16384 is the port -- a 64K-page aarch64 Linux answers 65536 -- so the class of constant that
cannot be ported is a HOST PARAMETER and must be labelled as one. Its only reader was
`urow("cu_page_size", PAGE_SIZE())`, a row that prints the constant, and no logic consumed it
(`cu.map_err.at` takes `aligned: Bool`, the seam's answer). The general rule: when a port has to
carry a host fact, the honest deliverable is the measurement and BOTH host values, not a
literal and a universal claim about it.

### 7. A DOCUMENTED WALL THAT DOES NOT EXIST COSTS AN ORACLE, AND NO GATE ROW CAN NOTICE
`ops_cl.bend`'s WALL 7 claimed `import tinygrad.runtime.autogen.hip` raises "failed to load
library hip" on this machine, and therefore that there was no oracle for its 1277 `hip*`
symbols. MEASURED: the import succeeds, all 1277 resolve with correct `restype`, and
`hipMemcpyHostToDevice`/`hipMemcpyDeviceToHost` answer 1 and 2 by `getattr`. A lazy `ctypes`
`_FuncPtr` only fails when CALLED, and a call needs a device -- so "no runtime" and "no
constants" are different facts and only the second one was ever written down. `HIP_H2D`/`HIP_D2H`
were in fact CORRECT, and now they are VERIFIED. Always try the import before recording a wall.

### 8. DEAD DEFS: A `def` THE HEADER TABLE CALLS "PORTED" CAN STILL BE UNREACHABLE
`prune_dead.py` (full dotted name, whole identifier, comments and strings stripped, a def's own
line blanked but the REST of it kept) found 28 dead defs of 508 in `ops_cl.bend` and 11 of 275
in `ops_webgpu.bend`, confirmed by `dead-defs2.py`. Seven are numeric constants. Three of the
webgpu ones are worth more than their length: `dev.synchronize`, `copy.copyout` and `prog.del`
are written, named PORTED in the header's WHAT IS PORTED table, and reachable from nothing --
and that is WHY `SYNC_WORK_DONE` is blind, which is how a dead def and a blind constant turn out
to be one finding. `dead-defs.py` scores `Dev.of` alive because `CuDev.of` contains it, so a
base-name audit under-reports and its "clean" is not clean.

### 9. THE ORACLE CAN BE WRONG WHILE YOU WRITE IT, AND ONLY THE AST CATCHES IT
Restating `mt_constmap.py`'s finding in a second file: writing `cl_constmap.py` I first pinned
`HP_VARGS_FLAG` to the FIRST int on `hp:43`, which is the `(ctypes.c_void_p * 5)` word COUNT,
and `HP_VARGS_KIND` to the first on `hp:44`, which is the `3`. Both were wrong authorities and
both agreed with nothing -- the port's `1` and `2` are right -- so the differ reported two
"disagreements" over the ORACLE's mistake, not the port's. What caught them was insisting on
POSITIONAL indices (`at=1`, `at=2`) because the line carries three ints, and refusing to write
a regex where the line carries two. When a port and an oracle disagree, establish which of the
two read the line wrong BEFORE concluding the port has a bug.

## MEASURED BY THE `runtime/support/system` UNIT (2026-10-02) -- numbering continues from the
## `1..9` series that ends at line 8320 (the `runtime/support/nv/ip` unit). Rule NUMBERS REPEAT
## across every series in this file; cite LINE POSITIONS.

**1. `Bool.pick` DOES SHORT-CIRCUIT ON A TERM IN BEND 2.0.34, SO A FOLD BUILT ON IT IS
FIRST-HIT AND NOT LAST-HIT.** The rule at position 6038 and the one at 6021 both say `Bool.pick`
"EVALUATES BOTH ARMS", and for the MUTATING cases that is right -- a `Bool.pick` cannot gate a
`List.append`. But `Bool.pick(U32, guard, a, f(v, t, n+1))` where the recursive call is PURE does
NOT force the recursion. MEASURED, one line: `f(1, [9,1,1,7], 0)` printed `1`, the FIRST hit, and
`f(5, [9,1,1,7], 0)` printed `999`, so the walk does stop. The consequence is a REAL DIVERGENCE
and not a style point: the direction a Python `{v: k for k, v in table}` mirrors is LAST-hit, so a
`Bool.pick` table walk answers the other one. Where the table is INJECTIVE the two are THEOREMS
and equal (`RemoteCmd`'s sixteen names, the nine `struct.calcsize` format codes); where it is not
(`MAP_SHARED` and `PROT_READ` are both 1, `MAP_PRIVATE` and `PROT_WRITE` are both 2) they are not,
and the file has to say which it is. Before writing a table walk, decide FIRST-hit or LAST-hit and
put it in the comment -- an unqualified "the same as the dict comprehension" is wrong.

**2. A `Do` BLOCK WHOSE LAST STATEMENT IS AN `IO` BIND, FOLLOWED BY A COMMENT AND THEN A `def`,
IS A PARSE ERROR.** `bend` reports `expected : a term (the keyword 'def' cannot head one)` pointing
at the `def`, which reads like a missing `end` and is not one: every def body before it is
balanced. Bare calls ARE statements (the rule at position 695), so making the last child call a
bare statement instead of `x : Unit <- f()` fixes it. This cost two rounds of a ten-minute loop
before the pattern was visible.

**3. A `Data` BINDER IN A `do` BLOCK IS AFFINE UNLESS IT IS `+`, AND A `Tr` NEEDS SIX READS.**
`t : Tr <- IO.pure(Tr, ...)` followed by five `Tr.count(...)` rows gives
`expected : t / observed : t (consumed more than once)`. The fix is `+t : Tr <- IO.pure(Tr, ...)`,
which is what `ops_webgpu.bend` does for `+d : Dev`. It is NOT the same as the `+` on a `def`
parameter (position 1194): a do-block binder and a parameter are separate. A `Meta` needs it too,
and the error names whichever binder the checker reaches first, which is NOT necessarily the one
you are reading about.

**4. A THREE-SEGMENT DOTTED NAME AFTER A NULLARY DEF IS PARSED AS A CALL, NOT A NAME.**
`def sib.fns() -> List<&2, U32>` followed by `def sib.fns.go(...)` gives
`expected : a defined name / observed : sib.fns.go` -- `sib.fns` is nullary, so `.go` reads as a
field access on its RESULT. `Tr.emit.go` works because `Tr.emit` takes arguments. The rule at
position 6001 covers two segments; the nullary case is the three-segment one. Rename the nullary
def or take an argument.

**5. A `U32` SELF-CALL IS REFUSED, A `Nat` SELF-CALL CANNOT READ ITS OWN FUEL, AND SO `take n` /
`drop n` OVER A LIST NEEDS A TWO-SCRUTINEE `match` ON THE CROSS PRODUCT.** `f(n: Nat, xs)` with
`case 1n+m:` cannot also compute an index from `n`, and `f(n: U32, ...)` is refused outright
(position 6847). The working shape is

    match n xs:
      case 0n _a: <the whole list>
      case 1n+m Nil{}: <the empty base>
      case 1n+m h <> t: <recurse on t>

Three arms, not two, because two bounds is the honest shape -- and it is a case where the extra
arm is genuinely reachable (`take 3` of a two-element list). A `Nat` countdown DOES work when the
value rides a SECOND `+` that grows (`vis.count_at`, `sib.walk`, `hx.bitlen.go`): the countdown
is argument one and the accumulator is argument two or three. What is impossible is reading the
countdown itself after the arm spends it.

**6. A MUTATED CONSTANT WITH NO ROW IS A ZERO, AND THE CONSTANT IS USUALLY ONE YOU JUST GOT
WRONG.** `PAGEFRAME_MASK_HI` is `(1 << 55) - 1`'s high word. I wrote `0x7ffffff` for `0x7fffff`,
the CPython oracle caught it BEFORE any row existed, and then mutation M4 -- perturb that constant
-- moved **nothing**, because no row read it. Two rows later it moves 1. This is rule 8 of the
`1..9` series ("an unread constant is not a port") arriving as a zero rather than as a sweep, and
the two halves of a SPLIT 64-BIT CONSTANT are exactly the ones nobody writes a row for because
each half "looks obviously right". Write the row for both halves, and write a third that says
they DIFFER -- a mask whose halves are equal is a 32-bit mask wearing a 64-bit hat.

**7. A MATCHER NEEDS A ROW THAT CAN FAIL, AND THE ONLY WAY TO KNOW IS TO HARD-WIRE IT.**
`Tr.has` hard-wired to `True{}` moved **0** rows, because every order row in `system.bend` was
`True` in the baseline. Asking for `sy_has_absent`, `sy_has_reversed`, `sy_has_wrong_arg` and
`sy_has_wrong_str` immediately found a REAL BUG: `Tr.step.at` matched on the `at` COUNTER and
returned `at + 1` for the `0n` arm WITHOUT COMPARING, so the matcher answered True for a pattern
element that never occurred. `at` is a count of matched elements, not a fuel to split on -- there
is no third meaning. This is `ops_webgpu`'s M23 for the third time in this repo, and it is the
single highest-yield row set in the file: five rows, one real bug, and it took ten minutes.

**8. A GATE ROW WHOSE NAME PROMISES A VALUE AND WHOSE VALUE IS SOMETHING ELSE IS A CHANGE-DETECTOR.**
`elemsize` answered the INDEX into its table, so `sy_el_B` printed `0` next to a row named for
`struct.calcsize("B")` -- a gate reading "the element size of B is 0". No mutation could detect it,
because the mutation would change the index and the oracle was also reading the index. Split the
two directions into two defs (`elemsize` the value, `elemsize.at` the index) and give the index its
own row names. The general form: when a table is keyed, ASK WHICH of the key and the value your
row prints, and if the answer is "the key", rename the row.

**9. A `U32` SUM WRAPS, SO AN ORACLE THAT COMPUTES IT IN PYTHON INTEGERS ANSWERS THE OPPOSITE.**
`u64.carried(0xfffffffc, 0x2000)` is True in `U32` -- the sum wraps to `0x1ffc` and
`0x1ffc < 0xfffffffc` -- and the first differ said False, because `0xfffffffc + 0x2000` in Python is
`0x10001ffc`. Every `U32` arithmetic expectation in a CPython oracle must be masked with
`& 0xffffffff`, and the mask belongs in the ORACLE, not in a comment. The same trap took
`(cap >> 4).bit_length() - 1` for a `cap < 0x10`, where Python's shift is negative and the port's
is `0xFFFFFF00`-ish.

**10. A HOST-DEPENDENT CONSTANT MUST BE A DEF OF THE PLATFORM FLAG, AND THE HOST IS NOT THE
TARGET.** `mmap.MAP_ANONYMOUS` is `0x20` on Linux and `0x1000` on macOS, and `mmap.PAGESIZE` is
`4096` and `16384`. Reading the host's value puts `0x1000` into `reserve_va`'s flag OR (off by
3968 on every platform the port targets) and flips `alloc_sysmem`'s `size > PAGESIZE` test for every
request below 16 KiB. The same `0`-vs-`4096` mistake killed `(1 << 55) - 1 >> 32`: `0x10000000000`
is 2**40 so the answer is `0x100`, and `4096` came from reading it as 2**44. Rule: a constant whose
source line mentions `OSX`, `sys.platform`, `getattr(mmap, ...)` or `PAGESIZE` is a def OF a flag
in the port and takes the flag as an argument at every call site.

# ===========================================================================
# APPENDED BY `schedule/prepare.bend` (the unit that ports
# `tinygrad/schedule/prepare.py`).  Numbering CONTINUES FROM the block above --
# this file's rule numbers have now collided four times, so cite POSITIONS.  The
# last rule of the block above is numbered 10 inside its own section and sits at
# the end of the file, so these are 11..20 of THAT section, appended at the end.
# Measured on Bend 2.0.34, `bin/bend`.
# ===========================================================================

**11. A BUILDER MUST BE HANDED THE ARENA, AND MUST USE THE ONE `UOp.new` RETURNS.** Two
separate defects, both silent, both found by a gate that compares an arena INDEX.
  * A builder that reads `O.Found.ar(x)` to get its arena builds into the arena as it stood
    BEFORE `x` was interned. The new node's index is then relative to a stale arena and every
    later index is wrong. Every fixture in `prepare.bend` was wrong until every builder took
    `+ar: O.Arena` as its FIRST parameter and used THAT.
  * `UOp.make` APPENDS, so the arena `O.UOp.new` returns is one node longer than the one it took
    (`ops.bend:2031`, `Found{made, UOp.of(made, ...)}`). Reading the new index against the arena
    you PASSED gives you `Arena.next`, and `Arena.op` on that index is the arena's BOTTOM -- so the
    row prints `NOOP` with nsrc 0 and a shape of `ERR`. Symptom: every row that BUILDS reads
    `1|NOOP|0||ERR|ERR` while every row that only rewrites is right. Fix: take the answer from
    `O.Found.ar(f)` / `O.Found.i(f)`, never from the arena you passed in.
  Together these are the reason a Bend fixture builder threads one arena top to bottom and never
  calls `O.Arena.empty()` after the first node.

**12. `Arena.src_to` IS `srcs[:k]` AND `Arena.src_from` IS `srcs[k:]` -- THE NAMES ARE FROM
BOTH ENDS AND READ THE OPPOSITE WAY ROUND.** `ops.bend:1000` and `:1010`. `u.src[1:]` is
`Arena.src_from(ar, i, 1)`. Writing `src_to(ar, i, 1)` gives `srcs[:1]`, i.e. `src[0]`, and the
node it builds has a plausible op and a plausible nsrc -- only the src op SEQUENCE is wrong, which
is exactly the kind of defect the four-facts gate exists to catch. Measured: it cost one full
debug cycle in `prepare.bend` and it is the same shape as `ops_cl`'s inverted field names.

**13. `ops.bend`'s `UOp.after`, `UOp.end` and `UOp.mstack` BUILD `srcs ++ [self]`; PYTHON BUILDS
`(self,)+srcs`.** `ops.bend:2085`, `:2094`, `:2103` all do
`UOp.new(ar, OpsAFTER{}, List.append(&2, U32, srcs, [self]), ...)`, and `List.append(x, A, xs, ys)`
is `xs ++ ys`, so the node lands LAST where `ops.py:621` puts it FIRST. An AFTER built by
`ops.bend` has srcs `[END, BUFFER]` where CPython has `[BUFFER, END]`: same op, same nsrc, same
shape, and the four-facts gate's src op SEQUENCE is the only thing that sees it. REPORTED to
`ops.bend`'s owner from `schedule/prepare.bend`; that file builds its own AFTER with
`List.append(&2, U32, [self], O.Arena.src_from(ar, n, 1))` and does NOT use the helper.
`UOp.after.go` and `UOp.end.go` also answer `Found{ar, self}` for an EMPTY `srcs`, which matches
Python's `if len(src) else self`, so only the ORDER is wrong.

**14. A SELF-RECURSIVE DEF WITH A TWO-LEVEL DISPATCH MUST BE SPLIT INTO A DESCENDING PASS AND A
FOLD, AND THE SPINE IS THE FUEL.** `walk_mop` (prepare.py:40-43) is a loop condition plus a
per-node rewrite, and Bend refuses every shape that looks natural:
  * a `match` may only scrutinise a PARAMETER, so `if hop(u) ... elif is AFTER(u) ...` cannot be
    two nested matches over computed `Bool`s;
  * the only self-recursive def may have ONE decreasing argument in ONE arm, so the loop
    condition and the node rewrite cannot both dispatch in the same def;
  * mutual recursion is refused, so an entry def above the walk and a worker below it is out.
  The shape that works is `Kahn`'s (`fold.bend:2641-2653`): ONE self-recursive def whose fuel is a
  `List<&2, Nat>` (the tail shrinks, so it is the decreasing first argument), which collects a
  SPINE, and a SEPARATE fold over the spine's TAIL. Two details are load-bearing:
  * the spine is built by PREPENDING (`List.append(&2, U32, [me], acc)` is `[me] ++ acc`), so it
    comes out deepest-first, which is the order Python unwinds the recursion in. Appending instead
    (`acc ++ [me]`) is a 10-row mutation in `prepare.bend` and every `wm_after_*` row moves.
  * the self-call may only pass the fuel's TAIL, so a def CANNOT empty the fuel. "Stop at the
    terminal node" therefore needs a `done: Bool` in the state record, because a `match` on a
    record's FIELD BINDER is legal where a `match` on a computed value is not -- and `done` is the
    only difference between `fold.bend`'s drain and `prepare.bend`'s stop.

**15. A RECORD BINDER IS READ-ONCE AND A `Data` MATCH MUST NAME EVERY CONSTRUCTOR, BUT A `let`
WITH `+` IS A *SHAREABLE PARAMETER* AND ITS READS ARE NOT ORDERED.** `case WmSp{ar, me, acc}:
WmSp{ar, me, pr_wm_pre(me, acc), ...}` fails with "`me` consumed more than once" even though
`me` is a binder and not a parameter -- the fix is a reader def (`WmSp.me(st)`) plus `+st`, or a
field named something other than the parameter. Separately, the node field of a state record is
named `me` in `prepare.bend` purely because `self` SHADOWED the `self` parameter with nothing to
say so (agent-core.md names this trap; here the symptom was a bare "consumed more than once" with
no mention of shadowing).

**16. `Bool.pick` IS THE ONLY WAY TO WRITE A CONDITIONAL THAT IS NOT A `match`, AND THAT IS EXACTLY
WHAT MAKES AN IDENTITY TEST WRITABLE.** `Bool.pick(T, cond, a, b)` evaluates both arms and picks, so
it needs no scrutinee and accepts a computed `Bool`. `walk_mop`'s whole AFTER rule is
`(b := walk_mop(u.src[0])) is not u.src[0]`, which as a `match` would need the answer and the test
in one scrutinee; as a `Bool.pick` it is one expression:
`Bool.pick(U32, U32.is_eq(b, s0), n, <build>)`. Every rule body in `prepare.py` that reads
"if a computed test then a value" wants `Bool.pick`, and every rule body that reads "if a computed
test then a DIFFERENT SHAPE" does not -- `Bool.pick` also fails on a `Data` type with `&2`
(`expected : Type, observed : Quant`), which is the trap for `match`-shaped answers.

**17. A `Data` RECORD WITH AN `I64` FIELD HAS A NAME FOR IT AND IT IS THE FOURTH FIELD.**
`LAWS/spec.bend:78`, `Dt{pri, bits, cls, nm}` -- so a dtype's CPython `name` is one binder
(`case S.Dt{pri, bits, cls, nm}: nm`) and not a table. Corollary for shapes: `H.i64_text`
(helpers.bend:1232) prints an I64 as `hi:lo` because "an I64 prints as its two words", which is
right for a 64-bit pointer and WRONG for a shape dim, where CPython prints the plain integer. A
gate that prints a shape through `H.i64_text` gets `0:4` where CPython has `4`, and no shape row
can ever match until the rendering is `H.lo32` plus a sign from `H.i64_is_neg`.

**18. A CPython `UOp.const` IS `CONST(CAST(CONST))` AND AN ORACLE THAT BUILDS A BARE `CONST`
IS OFF BY ONE NODE ON EVERY TOPOSORT SIZE.** `ops.py:638` returns
`UOp(Ops.CONST, arg=dtype.const(b), src=()).cast(dtype)` and `.cast` on a CONST REBUILDS it at the
dtype, so `UOp.const(n)` interns CONST, then CAST, then CONST again. A shape arg that must be a
bare CONST (`as_shape` reads `s.val` off each element, ops.py:811, and a CAST has no `.val`) is
`UOp(Ops.CONST, src=(), arg=I32.const(n))` -- ONE node. The symptom is a toposort size that is
one or three too small against CPython for every fixture that contains a shape, with every op,
nsrc and src op sequence correct: it is invisible to anything but a COUNT, and it is invisible in
the opposite direction to a port bug, so the fix is to align the oracle's node shape with the
port's before comparing anything.

**19. `O.ATuple` IS `List<&2, U32>`, WHICH ERASES PERMUTE'S AND FLIP'S MARG TYPES.** `ops.bend:763`.
`ops.py:430` refuses a FLIP whose arg is not all `bool`, so a FLIP's arg is a bool TUPLE and a
PERMUTE's is an int tuple, and nothing in the compiled IR says which. A fixture that writes
`ATuple{[1, 0]}` for a FLIP builds a node CPython would refuse. This is a WALL on the marg TYPE,
not on the marg VALUE, and `schedule/indexing.bend`'s `argsort` rows are unaffected because they
read values.

**20. `S.float32()` DOES NOT EXIST; `LAWS/spec.bend` NAMES THE DTYPES.** `S.int32()` (spec.bend:678),
`S.half()`, `S.single()` (689), `S.double()`, `S.uint32()`, `S.weakfloat()`, `S.bfloat16()` and the
fp8 family are module-level defs, and `S.single()` is the 32-bit float -- there is no `float32`.
Searching for a `Dt` CONSTRUCTOR rather than a reader is the wrong first move here: `Dt` is a
four-field `Data` record and every dtype is a `Dt{...}` literal inside a named def.

### 10. SIX UNSIGNED-64 ARITHMETIC TRAPS, ALL MEASURED 2026-10-02 (the `_min_max` unit)

Numbering continues from rule 9 (line ~7820, the `ip.bend` name-vs-line rule) and
rule 10/11 at lines 3499/3516; as the INDEX says, numbers are not unique, so these
are cited by position -- the tail of this file.

The subject is the arithmetic core that `uop/fold.bend`'s `_min_max` section carries
as `mm.u64.*` / `mm.dm.*`, gated by `.agents/slop/mm-gate.py` (72 rows, byte-identical
to CPython on the interpreted AND the `-o` lane) with a 21-entry mutation table at
`.agents/slop/mm-mutate.py`. **20 of the 21 move rows; the one that does not has a
proof (item 6).** Every rule below is a bug that was IN the code and produced a
plausible number.

1. **`Bool.or(is_zero(lo), is_zero(hi))` DOES NOT MEAN "the pair is zero".** It means
   "SOME word is zero", which is true for `(0, 5)` as well as for `(0, 0)`. With it,
   `2**32` came out as a product of zero and `(1:0) * (1:0)` answered `0:0` instead of
   `OVER`. The predicate that every overflow test wants is `and`. This is the
   `(Bool, Bool)` flag-pair trap at line 1684 in its purest form: the name says "zero",
   the code says "at least one half", and nothing complains. Mutation M5, 4 rows.

2. **AN UNSIGNED SUBTRACT'S UNDERFLOW TEST IS `a < b`, NOT `result < a`.** The second is
   what an ADD overflows on, and it is silently the wrong predicate for a subtraction:
   `0 - 2**32` wraps to a value GREATER than `a`, so `result < a` reads as "no
   underflow" and the port answers `4294967295:0` where CPython has nothing
   representable. `helpers.bend:1238` records the related borrow-into-the-high-word
   bug for i64; this is its unsigned sibling and it is a DIFFERENT predicate.
   Mutations M3 (7 rows) and M4 (1 row).

3. **IN A 64x64 PRODUCT THE TWO ACCUMULATORS ARE LIMB 1 AND LIMB 2 -- THE WORDS, NOT
   PARTIAL WORDS.** So every bit of the second one is already above `2**64` and the
   overflow test is `u != 0 or t3.hi != 0`. Three wrong spellings, all measured:
   `t3.hi + (u >> 32) != 0` WRAPS a U32 and reads as zero for a product that
   overflowed; `u << 32` in the high word SATURATES TO 0 (the `1 << 34` trap); and
   dropping `t3.hi` needs the fixture `mul_2p48sq` to be caught at all, which is why
   `2**48 * 2**48` is in the gate. Mutations M6 (1 row) and M7 (8 rows).

4. **`U32.mul` WRAPS, SO A 32x32 PRODUCT CANNOT BE OVERFLOW-TESTED; A 16x16 ONE CAN.**
   `U32.mul(a,b)/a == b` holds for a wrapped product of a particular size as readily
   as for an exact one, so the "obvious" 32-wide schoolbook is wrong in a way no
   single flag catches. A 16x16 product is BELOW `2**32`, so `U32.mul` is exact on it
   and four of them accumulate with every column sum under `2**20` -- no wrap test at
   all. Mutations M8 (8 rows) and M9 (5 rows). This is the cheapest arithmetic fact in
   the whole note.

5. **FOR A LEFT SHIFT PAST 31 THE HIGH WORD COMES FROM `al` AND ONLY FROM `al`.**
   `a * 2**k` has high word `al * 2**(k-32)` plus `ah * 2**k` reduced mod `2**32`, and
   the second term is 0 for every `k` past 31. Reading `ah` there drops the low word
   entirely and answers `0:0` for `1 << 63`, which is `2147483648:0`. Symmetrically, the
   FIT test is `a >= 2**(64-k)`, which is one word and one shift, and it must be `and`
   -- `or` fits every divisor-shaped word and answers a value where CPython says OVER
   (`1 << 64` is the row that notices). Mutations M10 (4 rows), M11 (3 rows), M12 (2),
   M13 (7).

6. **RESTORING DIVISION SUBTRACTS WHEN THE REMAINDER REACHED THE DIVISOR, NOT WHEN IT
   IS BELOW IT, AND STEP `k` READS AND WRITES BIT `k`.** Two separate halves of one
   algorithm, and both are `le`-vs-`ge` / `63-k`-vs-`k` mistakes:
   * `dm.fit` with `le` subtracts on every step where the remainder is merely below
     the divisor, which for any dividend smaller than the divisor is EVERY step. The
     answer is a quotient of all ones and a remainder equal to the dividend. 16 rows.
   * The dividend bit and the quotient bit are at the SAME index; counting down from
     63 is what makes the first bit processed the most significant of each. Writing
     `63 - k` for both is self-consistent and wrong. 13 rows.
   * `Bool.pick` names the arm it PICKS, so a flag that says "the low word" has to
     select the low arm. Swapping the two arms reads every dividend bit out of the
     wrong half and the quotient comes out zero. 17 rows -- the largest of the table.
   * `case 32n:` is an EXACT match and not a range, so a two-arm match on it answers
     True for `k = 63`; `U32.is_lt(U32.from_nat(k), 32)` is the whole test. 8 rows.
   * THE 65th BIT OF THE REMAINDER IS UNREACHABLE, and that is a THEOREM rather than a
     gap. Forcing it to `False{}` moves NOTHING (mutation M20), and the reason is that
     `r < d` before a step, so `r >= 2**63` needs `d > 2**63`, and a divisor above
     `2**63` cannot have had a subtraction yet (`2r + b < 2**63` for every pre-subtract
     `r`), so `r < 2**63` at every step. Carrying the bit is free; testing it is
     ungated; and this is the third category agent-core.md asks for.

7. **THE BIT COUNT IS NOT AVAILABLE, AND THAT IS A STRUCTURAL FACT, NOT A TODO.**
   `int(x).bit_length()` needs a walk whose zero test cannot be a `match` scrutinee
   (Bend refuses a call, so `u64.is_zero(...)` is out), whose growing counter cannot
   lead a self-call (each argument must pass unchanged until one shrinks, and a `U32`
   that halves is not a shrink as far as the checker is concerned), and whose test and
   step cannot be two defs (mutual recursion is refused). A `List` tail IS a shrink,
   which is why `toposort` and `dts_of` are walks -- but a three-scrutinee `match` over
   `(List, U32, U32)` refuses the repeated `_ _` placeholders. The dodge that WORKS for
   `shl` is to avoid the count: `shl` overflows iff `a >= 2**(64-k)`, one word and one
   shift. There is no such dodge for a bare bit count.

## MEASURED BY THE `runtime/support/usb` UNIT (2026-10-02) -- numbering continues from the
## `1..9` series that ends at line 8320 (the `runtime/support/nv/ip` unit). Rule NUMBERS REPEAT
## across every series in this file; cite LINE POSITIONS, and this block starts after line 8618.

1. **A `+` PARAMETER MAY BE READ MANY TIMES; A PLAIN ONE MAY BE READ ONCE.** `Tr.emit.go`
   reads `refused` four times and `next` twice, and it works, because every one of them is
   `+`. So `+` means "REBINDABLE", not "linear". The corollary is the trap: handing a `+`
   slot to a function that takes it as a PLAIN parameter MOVES it, and every later read of
   the slot sees whatever the callee left. A walk that tested a SEEN SET with
   `List.contains(~A, ~eq, seen, x)` and then consed `x <> seen` emitted ZERO rows and every
   seen set read as already-full, because `List.contains` takes `+x` and had taken `x`.

2. **`+D<..>` IS NOT "MAKE THIS BINDING REBINDABLE".** A pattern binder cannot be read
   twice, and prefixing the pattern with `+` fails to parse -- `+` on a datatype means
   `+D<..>` sets `D`'s leading quantities to `&2`. The way out is to rebind AFTER the
   pattern: `case Ent{v, nm} <> t:` then `+vv = v` / `+nn = nm`.

3. **`<>` IS HEAD-THEN-TAIL, AND THE LEFT SIDE MUST BE THE HEAD.** `ix_index(i) <> ix_map(t)`
   conses a SCALAR onto a list; `enum_both(...) <> enum_rows.go(...)` does not, because the
   left side is a `List` and the head slot wants a `String`. To join two LISTS use
   `List.append(&2, T, xs, ys)` or `List.concat`. A pattern `Ent{..} <> t` is the same
   operator read backwards.

4. **A `match` OVER A `Nat` IS NOT TOTAL WITHOUT A `case 1n+m:` ARM.** `case 0n:` ..
   `case 99n:` .. `case _:` all fail with "expected: a constructor of U32 (missing, or
   already matched)", including the wildcard. So a 24-arm symbol ladder has to be a walk
   over a list, and a 3-arm match over a status byte has to be a `Bool.pick` nest.

5. **A `do IO<Unit>:` BLOCK CANNOT BE FOLLOWED BY A `def`.** The block runs to the end of
   the enclosing def, so a section of twenty-two `IO.print`s is one
   `IO.print(lines_of(concat_str([...])))` and not twenty-two bindings. This is the sibling
   of the "a bare expression arm and a `do` arm have different types" note: both come from
   the same place, the block is a STATEMENT form.

6. **THE PARITY OF A LIST LITERAL IS INFERRED FROM THE EXPECTED TYPE, EXCEPT FOR A
   `List.concat`/`List.map` TEMPLATE ARGUMENT.** `[a, b, c]` adapts to `List<&2, String>`
   when the callee says so (which is why a flat row list works), but `List.map(~A, ~B, ~f,
   xs)` wants a template it cannot infer from and the error names the FIELD type rather
   than the arity. A fold written as `h <> go(t)` avoids it entirely.

7. **A DECREASING SELF-CALL'S SHRINKING ARGUMENT MUST COME FIRST.** "Arguments are read
   left to right: each passed unchanged until one shrinks." `fields.go(ix, rest)` with
   `rest` second is refused; `fields.go(rest, ix)` is accepted. The same rule refuses
   `sym_at.go(Nat.add(m, 1n), t2)`: a GROWING first argument is not a shrink, so put the
   list first and the counter second.

8. **`List.length(&2, T, xs)` CONSUMES `xs`,** so `f(xs, List.length(&2, T, xs))` needs
   `+xs`. And `Bool.to_u32` returns `U32`, so `Nat.add(at, Bool.to_u32(...))` is a type
   error -- wrap it, `Nat.add(at, U32.to_nat(Bool.to_u32(...)))`.

9. **MATCHING A LIST BY MATCHING THE FUEL ALONE LOSES THE LIST.** `usb_enum.walk` took a
   device list the port did not have (`libusb_get_device_list` returns a POINTER) and
   matched an always-empty one, so every fixture produced ONE device whatever `n` said. The
   count IS the fuel when the container is the seam's.

10. **A HAND-TYPED CONSTANT IS A COIN FLIP, AND TWO OF 119 WERE WRONG IN ONE FILE.**
    `SENTINEL_MAGIC` was 1363148800 where `0x51000000` is 1358954496; `FAST_P1_MASK` was
    215 where `0b11011111` is 223. Both were caught by generating the expectation from
    CPython, and a hex spelling IN THE COMMENT is not enough -- the comment said `0x51000000`
    and the value said `0x51400000`. The check that generalises is a map from the Bend def
    to an AST POSITION in the Python file, so the VALUE comes from the source text and a
    wrong value is not expressible; a wrong POSITION is, and it is loud.

11. **WHEN A PORT'S TABLE LOSES AN ENTRY BECAUSE THE ORACLE WAS RIGHT, THE RULE IT WAS
    TESTING LOSES ITS FIXTURE.** `enum_libusb_class_code` really does bind
    `LIBUSB_CLASS_IMAGE:=6` and then `LIBUSB_CLASS_PTP:=6`, so IMAGE is a module global and
    NOT a dict entry. Correcting the table to nineteen entries removed the only repeated
    value in twenty-one tables and LAST-wins became unobservable -- mutation M36 fell to 0
    rows. The fix is a SYNTHETIC table built to have the collision, not a comment.

12. **A U32 SUBTRACTION WRAPS WHERE PYTHON'S DOES NOT, AND `U32.max` KEEPS THE WRAP.**
    `(size - CHUNK).maximum(0)` is 0 for `size < CHUNK` in Python and 4294967295 in a U32,
    and `U32.max(4294967295, 0)` is 4294967295. The clamp has to be an explicit
    `Bool.pick(is_ge(size, CHUNK), U32.sub(...), 0)`. The boundary fixture is the one that
    catches it: a size one below the threshold.

13. **`U32.shln(1, 32n)` IS 0 AND `U32.sub(0, 1)` IS 4294967295,** so
    `((1 << (8*size)) - 1)` at `size == 4` is right BY ACCIDENT. Measure it with a row
    (`usb_pcie_mask_4`) or the next person will "fix" the saturating shift.

14. **`String.split` THROWS THE SEPARATORS AWAY, SO A FIELD LIST IS A ROUND TRIP.** The
    gate prints `String.join(map(names), " ")` and diffs THAT against the header's field
    names, never the literal: a row that printed the literal would be a tautology, and a
    field COUNT passes a transposed pair. `ops_cl`'s unit found `Sig`'s names INVERTED and
    a USB descriptor with a transposed pair is a silently wrong transfer.

15. **THE ORDER OF A NESTED `f(g(x))` IN C IS ARGUMENTS-FIRST, AND AN AST PRE-ORDER WALK
    REPORTS THE OUTER CALL FIRST.** `checked(libusb.libusb_get_device_descriptor)(
    libusb.libusb_get_device(handle), ...)` on one line calls GET_DEVICE first. An oracle
    that walks the AST pre-order will disagree with any trace, and the disagreement looks
    like a port bug. Visit `n.args` before `n.func`, and visit `n.func` at all when it is a
    `Call` (`checked(X)(...)` has the symbol inside the callee).

16. **`checked(...)` IS A REFUSAL SITE AND A BARE `libusb.*` CALL IS NOT, AND THAT SPLIT IS
    THE WHOLE OF A TRACE'S `raise` BEHAVIOUR.** `checked` (:13-18) raises when the return
    code is negative. If every step emits through one function, `bad_at` fires at exactly
    one ordinal and every other "refusal" fixture prints the FULL trace -- a row that looks
    like a gate and is not one. `libusb_free_device_list(devs, 1)` and `libusb_ref_device`
    are raw; the descriptor read is checked; `usb_enum_refused_5_fires` and
    `usb_enum_refused_6_raw_no_fire` are one row apart and say so.

---

## renderer/isa/x86.bend -- measured 2026-10-02. NUMBERING CONTINUES FROM THE LAST
## APPENDED SERIES IN THIS FILE; rule numbers here are NEW and the file's INDEX AT ITS
## TOP is already known to be ambiguous, so CITE THESE BY POSITION (grep for the title).

### `Bool.pick` OVER A `List` WITH A SHARED ACCUMULATOR IS NOT SAFE TO REASON ABOUT

`Bool.pick(-A, c, a, b)` returns `a` when `c` and `b` otherwise, and it EVALUATES BOTH
ARMS. Over a list that means the accumulator is passed to both arms, and a fold whose
two arms differ only in WHICH list they return printed two different plausible wrong
answers in one sitting -- `Reg.wgpr_list.go` printed the class BACKWARDS with the
arguments `(cond, acc, append)`, and printed ONLY `rsp` with the arguments
`(cond, append, acc)`. Every element-wise reading of both versions was correct. The
`grp.*` rows use the same `Bool.pick` over a `List<&2, String>` and are right, so the
rule is not "Bool.pick is broken" -- it is that the arm that CONSUMES a shared list is
the one to suspect.

THE SHAPE THAT DOES NOT MISBEHAVE: make the decision an ARM INDEX and branch with
`match` on it in a second def. See `Reg.wgpr_push.go` in `x86.bend`.

### `String.concat` PREPENDS, AND `String.reverse` REVERSES THE WHOLE STRING

So a string accumulator built by prepending and reversed at the end is correct ONLY
when every element is a fixed-length token. With variable-length elements it reverses
each one too: `RegNames.go` printed ",xar,xcr" for `[rax, rcx]`, and `Hex.bytes.go`
printed the byte `0xc3` as `23` and dropped half of every instruction. Build a
`List<&2, String>` and use `String.join` instead -- `List.append(xs, ys)` is `xs ++ ys`
(base.bend:822) so a fold onto a list is ALREADY in order and needs no reversal. The
four sites in `x86.bend` that got this wrong were `RegNames.go`, `Op.set_names.go`,
`Enc.missing.go` and `Hex.bytes.go`, and each was caught by a JOINED-STRING row rather
than a count -- a count row was green for all four.

### A `match` ON AN ARM INDEX IS NOT COSMETIC, AND `Bool` MAKES A BAD ARM

`match <computed Bool>:` is refused ("a parameter or field scrutinee"), so every
threshold has to become `Bool.pick(U32, cond, 1, 0)` and then a `match` on that index in
a second def. The `Bool.pick(U32, ...)` is the ONLY place the branch is written, so an
arm index is what every threshold in a file goes through, and a def that needs three
different threshold tests needs three indices or a nested `Bool.pick`.

### BEND 2.0.34 HAS NO `0x` LITERAL

`0x8B` is a parse error naming the `x` ("expected : a numeric literal"). A port of a
table written in hex source literals must convert every one to decimal, and the
conversion is where the mistakes land -- `x86.bend`'s `encodings` table is 77 decimal
opcodes converted by hand and every one is checked against CPython's own `ast` reading
of the source. `0b1111` IS supported.

### `U32.shln` / `U32.shrn` TAKE A `Nat` AMOUNT, AND A `Nat` LITERAL ONLY BINDS IN A
### `Nat` CONTEXT

`U32.shln(a: U32, n: Nat)` and `U32.shrn(a: U32, n: Nat)` (base.bend:1399, :1406), so a
byte offset in BITS is `Nat.mul(8n, i)` on the `Nat` side -- `U32.shln(U32.from_nat(i),
3n)` is a type error, not a coercion. There is no `>>` on `U32`: `U32.shr` is a ONE-BIT
shift and the n-bit one is `shrn`/`shln`.

### A SELF-CALL DRIVEN BY A `Nat` COUNTDOWN MUST PUT THE COUNTDOWN FIRST, AND
### `U32.inc(i)` IS NOT RECOGNISED AS ONE

`Enc.imm_int` walks `n` bytes with a `Nat` countdown and Bend accepts
`Enc.imm_int(U32.inc(i), n, imm, ...)`. With `U32.inc(i)` as the argument and a `U32`
parameter it is refused as "a decreasing self-call" -- a `U32` countdown is not a
decreasing argument to Bend and a `Nat` one is, so the countdown's TYPE is the thing
that makes the recursion typecheck, not its position alone.

### `FastEnum` CONTINUES THE BASE ENUM'S NUMBERING

`x86.py`'s `X86Ops` is a `FastEnum` whose `auto()` continues from `tinygrad.uop.Ops`,
so its eighty-nine members are numbered FROM 78, not from 0. A port that reads "an
`auto()` enum is 0..n-1" produces eighty-nine plausible wrong numbers and a CORRECT
`len()`, and no count row sees it. Gated in BOTH directions, which is the only reason
the mistake was caught at all.

### TWO THINGS WRONG WITH THE GATE HARNESS, BOTH MEASURED HERE

  1. A REFERENCE FILE MUST CARRY THE ANSWER HALF TOO. The oracle's `rows` mode emits
     `NAME = [CPYTHON]   py=[CPYTHON]` -- the answer half filled with CPython's own
     answer, because the reference's claim is "this is what the answer must be". A
     reference of only `py=[...]` halves diffs against every line.
  2. REGENERATING GENERATED ROWS MUST REMOVE THEM BY NAME, NOT BY POSITION. A
     topological sort of the file reorders the defs, so a splice at a banner leaves the
     previous run's `Gate.rows0` above it; a dedup pass then keeps the STALE copy and
     the gate shows rows from an oracle two fixes old. Cost three confusing diffs.

## APPENDED FROM `runtime/support/rdma/bnxtdev.bend`

Numbering continues from the position above (this file is append-only and its rule
NUMBERS have already collided three times, so cite the `##` SECTION HEADING, not a
number). Six measured rules; every one cost a compile cycle or a bisect on that file.

### A `do` BLOCK'S LAST LINE MUST BE A BARE MONADIC ACTION

    def f(x: U32) -> IO(Unit):
      do IO<Unit>:
        a : Unit <- g(x)          # a BINDING -- fine anywhere except last
        g(x)                      # the last line: a bare action

A block whose last line is a BINDING does not terminate, and the parse error is
reported at the NEXT `def`, which reads like that def is malformed and is not. Three
of these on `bnxtdev.bend` (`t_const`, `db_row`, `t_db`) each cost a bisect, and the
symptom actively points at the wrong line. `.agents/slop/dobind.py` checks a whole
file for it in one pass; the first version of that checker tested the opposite
condition and found none of the three.

### A `def` NAME MAY CONTAIN A DOT, AND A DEPENDENCY SCANNER MUST NOT SPLIT ON IT

Bend names are `foo.bar` all over (`Tr.has.step`, `mask_nibs.go`, `pbl.build_top`).
A tool that resolves an identifier by splitting on `.` and looking up the head turns
`mask_nibs.go` into a SELF-dependency, so a real forward reference is reported as
clean and the file does not compile with a message naming a callee. Check the WHOLE
dotted token against the def table first, and only then fall back to the head as a
namespace. `.agents/slop/depord.py` got this wrong first and hid one forward
reference for several cycles.

### A COUNTDOWN BINDER IS CONSUMED BY THE `match`, SO A POSITION RIDES BESIDE IT

`case 1n+m:` spends `m`, so `f(nth_at(xs, m), m)` reads it twice and is refused. The
fuel must also be the FIRST parameter (a self-call whose fuel is the fourth argument
is refused outright, with no mention of fuel). The shape that works, and the one
every fold in this tree uses:

    def walk(n: Nat, ix: U32, +xs: List<&2, T>) -> T:
      match n:
        case 0n: base
        case 1n+m: walk(m, U32.inc(ix), xs)

`ix` is a plain `U32` and needs `+` if read twice; `xs` needs `+` if the match and
the recursive call both use it.

### A `do`-BLOCK `=` BINDING IS AFFINE LIKE A PARAMETER

`nm : String = ...` read five times needs `+nm`. Only `<-` MONADIC binds and `match`
pattern binders are exempt. Eleven of these on `bnxtdev.bend`, each one compile
cycle. `.agents/slop/affine.py` finds them for a whole file at once -- and it must
report the line the name is BOUND on, not the line of the `def`, or the fixer
off-by-ones and re-applies forever.

### `Bool.pick` EVALUATES BOTH ARMS, SO A `U32` OP INSIDE ONE NEEDS A `Nat`

`Bool.pick(U32, c, a, b)` type-checks both arms, so `U32.and(x, U32.shrn(y, 8n))` in
an arm demands a `Nat` shift inside a `U32` operation and is refused with
`expected : Nat / observed : U32`. The two failure shapes look identical from the
outside -- both report at the NEXT `def` -- and cost a bisect each here: a mask
written as a shift (`U32.shrn(U32.and(x, 255n))`) and a mask written as a mask
(`U32.and(U32.shrn(x, 8n), 255n)`, which is what it should be).

### AN UNCLOSED PAREN IN A DEF BODY REPORTS AT THE NEXT TOP-LEVEL `def`

Four of these on `bnxtdev.bend`: `wqe.words` (four nested `List.append`), `bs.extra_at`
(eight nested `Bool.pick`), and two `urow` rows. `.agents/slop/paren.py` checks
paren balance PER TOP-LEVEL DEF; its first version stopped scanning when the depth
returned to zero, which for a one-expression-per-line body is the FIRST body line,
so it checked one line and found none of them. An EXTRA paren is not detectable this
way at all -- the depth balances at a higher level -- and a prefix bisect over the
body is the only tool for that one.

---

## APPENDIX 2026-10-02 (drift pass) — six rules about GATES, not about Bend

Numbering continues from the tail of the file above; these are unnumbered and cited by
position like everything else here. None of these is a Bend constraint — they are all
about a measurement that lies, and three of the six were found by being wrong here.

### A PORT WHOSE GATE HAS NO CPYTHON LANE CANNOT SEE UPSTREAM DRIFT. AT ALL.

The strongest rule here, and it is structural rather than accidental. A row's expected
value is a literal inside the `.bend` file, so **re-vendoring the Python moves nothing** —
not one row, not for any port. The row is compared against the port's *own* recorded
expectation. So "I re-vendored `x.py` and no row moved" is **not** evidence of anything
unless a CPython lane actually re-computes the expected value.

Measured across this pass:

| port | rows | CPython lane | can it see drift? |
|---|---|---|---|
| `runtime/support/hcq2.bend` | 360 | `hcq2-oracle.py` + `hq2-oracle2.py` | yes |
| `runtime/ops_metal.bend` | 432 | `mt_rows.py` (167→169) | yes |
| `renderer/cstyle.bend` | 227 | `wip/cstyle_oracle.py` (210) | yes |
| `codegen/opt/postrange.bend` | 48 | **NONE** | **no** |
| `codegen/opt/heuristic.bend` | 10 | **NONE** | **no** |
| `uop/ops.bend` | 22 | **NONE** | **no** |

`postrange` is the painful one: its 48 rows cover `upcastable_dims`, `unrollable_dims`,
`upcast_size`, `upcasted`, `axes_of`, `split_targets`, `group_for_reduces` and the
UNROLL `amt <= 32` check — and its mutation table asserts all three behaviours upstream
has since **deleted**. It is well covered and blind at the same time, because coverage
of the port's own model is not coverage of Python.

### THE GATE ROW THAT COMPARES A `[bend]` HALF TO A `py=` HALF IN ITS OWN FILE IS A TAUTOLOGY

`renderer/cstyle.bend` prints `nm = [<computed>]   py=[<literal>]`, and
`.agents/slop/wip/gate.py` parses that pair and reports the count that matches as
"matches CPython byte for byte". It never runs `cstyle_oracle.py`. The `py=` half is a
**string typed into the port**, so the row asserts the port against itself — the exact
shape `agent-core.md` records for `device.bend`'s `sig=0 4 5`. The wording makes it worse:
a reader sees "GREEN 227 / 227 rows match CPython" and believes a Python was consulted.

The honest form is the one `hcq2` uses: the CPython lane prints the same `name=value`
lines and a *separate* script diffs them, so a stale Python shows up as a row that no
longer appears at all rather than as a self-consistent green.

Corollary, measured here: when the two halves DO disagree, the gate does catch it — it
reported `GREEN 123 / 227` with the 104 red rows printed beside each other. The tautology
is invisible only while they agree, which is exactly when it does no harm.

### `renderer-oracle.py` IS NOT `cstyle_oracle.py`, AND NEITHER COVERS THE OTHER

Two files, same directory, wildly different row sets. `tools/renderer-oracle.py cstyle`
emits **15 whole-kernel `k*` rows**; `wip/cstyle_oracle.py` emits **210 component rows**.
A flat `name=value` diff of the first against `cstyle.bend` shows **zero shared names** —
which reads as "the gate compares nothing" and is in fact "these are different oracles for
different files". Before reporting an empty intersection as a finding, check that both
sides are the same oracle. (It cost this pass one wrong claim.)

### A PINNED PYTHON TREE EXTRACTED WITH `git archive` IS THE ONLY HONEST ORACLE FOR A DIFF

`git checkout upstream/master -- <one file>` leaves a tree that mixes two commits, and
CPython will import it happily until an `ImportError` names the coupling — or, worse,
will import it and compute something that is true of neither commit. `78d482262` alone
is enough to make `tinygrad` unimportable, because `postrange.py` at the pin imports
`axis_to_pos`, which that commit deletes.

Both trees, whole, side by side, answers the question in one command and has no mixed state:

```bash
git archive 6c3d401cf324 tinygrad | tar -x -C /tmp/pin-tree
git archive upstream/master tinygrad | tar -x -C /tmp/up-tree
```

The oracle scripts then need their hardcoded `sys.path.insert(ROOT)` rewritten — most of
them point at the repo root, so they silently measure the *working tree* while you think
you are measuring the archive. `sed` the `parents[3]` join to `os.getcwd()`.

### `bend` 2.0.34 HAS NO `-r`, AND `-o -` WRITES NOTHING

The "native lane" in `.agents/slop/hcq2-diff.py` is `bend <f> -o -` then `bend -r <bin>`.
Both halves are dead: `-r` is not an option (`bend: unknown option -r`) and `-o -` writes
**0 bytes** to a file named `-`, because `-o` selects the backend by *extension*. So the
lane silently returned an empty string and `hcq2-diff.py` reported a clean run having
compared nothing. The working form needs a real extension:

```bash
./bin/bend <f> -o /tmp/lane.bin && chmod +x /tmp/lane.bin && /tmp/lane.bin
```

An empty lane is not a failure, which is the whole danger: a harness that cannot run its
own second lane is indistinguishable from one that passed it.

### A FIRST GATE READING THAT DOES NOT REPRODUCE IS A FINDING, NOT A TYPO

`wip/gate.py` printed `GREEN 227 / 227` once and `GREEN 123 / 227` on every one of three
immediate re-runs, with the port byte-stable across three runs by `md5` and unmodified
against `HEAD`. Both numbers are recorded here because the reproducible one is the only
one that may be acted on, and because a harness that has two answers is a harness whose
"green" means nothing until the second one is explained.

---

## HEADER-CLAIM AUDIT (cross-cutting unit, 2026-10-02)

Appended after position 8876. Numbering does not continue -- these are findings
about PROSE, not about the language. The index at the top of this file does not
list them; find them by position.

### PROSE IS NOT CHECKED BY ANYTHING IN THIS REPO, SO A FALSE CLAIM IS FREE

Three committed files shipped a confident false header claim before this audit,
and every check the repo has passed on all three:

1. `runtime/ops_nv.bend` -- a `WHAT IS PORTED, DEF BY DEF` table naming **28 defs
   that were never written**, under a `STAGES ... ALL FOUR LANDED AND CHECKED`
   banner. `qmd.read`/`qmd.write`/`qmd.of`/`qmd.set_addr`/`qmd.set_release`,
   `pc.key`, `iface.classes`, `iface.pc_root`, `iface.err_str`, `flags.of`,
   `q.nvm`, `cq.init`, `cq.prev_reset`, `pd.kernargs_size`, `pd.cbuf0`, `pd.vars`,
   `dev.ifaces`, `dev.arch_of`, `dev.sass_of`, `dev.fifos`, `dev.new_fifo`,
   `dev.ensure_local`, `dev.vid_hw`, `dev.reg_chunk`, `GPFifo`, `alloc.alloc`,
   `va.uvm_top`, `iface.cls`. The file also carried **11 rows printed TWICE**
   under the same name (600 unique names from 611 lines) and a `543 + 56 + 4`
   row split that sums to **603**, not to the 600 it claimed.

2. `runtime/ops_rdma.bend` -- a 32-entry `WHAT IS PORTED` table naming 32 defs
   that do not exist. Every one was a RENAME that happened after the table was
   written; not one was a missing port. `iface.of` is `Iface.of`.

3. `runtime/support/nv/ip.bend` -- a wall reading "`hcq2.bend` is still a 29-line
   STUB", which was true when written and stayed true in the prose after
   `hcq2.bend` grew to **2272 lines / 284 defs / 360 rows**. A stale wall is the
   most expensive kind of false claim, because a reader who trusts it stops
   looking for the second table that could contradict this one.

**The rule: a header that says "stage 1 of 4, and here is exactly what stages
2-4 are" is a good header. A header claiming four stages when one landed is not.
Retract loudly, in the file, naming what was claimed and what is true.**

### A COUNT CLAIM IS CHECKED AGAINST THE WRONG FILE IF YOU DO NOT NAME IT

`"tc_ptx.py (141 lines)"` and `"the 287 lines of ops_metal.py"` are claims about
PYTHON and are true. `"renderer/cstyle.bend (287 lines)"` is a claim about a
`.bend` and is FALSE -- cstyle.bend is 2314. The three claims are
indistinguishable to a reader and to a regex. Spell the extension every time.

`"hcq2.bend ... 2272 lines with 284 defs"` -- 284 is `^(def|type)` count, 275 is
`^def` only. Pick one and say which.

### A BARE BASENAME IS AN AMBIGUOUS CITATION AND AN AMBIGUOUS WALL IS NOT A WALL

`dtype.py` exists at `tinygrad/dtype.py`, `tinygrad/mixin/dtype.py` AND
`tinygrad/codegen/decomp/dtype.py`. `op.py` at `tinygrad/mixin/op.py` and
`tinygrad/codegen/decomp/op.py`. `movement.py` at `tinygrad/mixin/` and
`tinygrad/uop/`. A wall writing `dtype.py:220` cannot be checked by anyone,
including by the person who wrote it. Four `mixin/*.bend` files carried these;
the line numbers were all CORRECT and the citation was still unverifiable.

### THE TWO LANES CAN DIVERGE AND NOTHING NOTICES

`mixin/elementwise.bend` claimed "both lanes are byte-identical to CPython" and
carried a `cmp /tmp/py.txt /tmp/bd.txt &&` recipe. Measured:

    bend = 72 rows, cpython (ew-gate.py) = 69 rows
    ew_promo_nc, ew_dt_promo_nc, ew_op_promo_nc have NO oracle counterpart

Those three were added when `g_promo_nonconst` closed the M13 conjunct defect.
The oracle script predates the fixture, so their expectations are a PARAGRAPH.
Three rows whose oracle is prose are the weakest rows in a file and the header
now names them. **A `cmp` recipe in a header is a claim about two artifacts, and
the artifacts are the only evidence; run it.**

### A MUTATION NAME IS NOT A DEF NAME, AND A REJECTED DESIGN IS NOT A CLAIM

`rp.seq.after_door`, `const_name.last_wins`, `dc_s2.pat`, `mn_pool_in.at` read
exactly like `def` names in prose and are not defs -- they are entries in
`.agents/slop/*_mutations.txt` or an explicitly DELETED first design. Both are
honest claims and both were near-misses for an automated checker. Name the
namespace: `the mutation rp.seq.after_door`, `a first design that was deleted`.

### DEAD DEFS, MEASURED, ALL 93 FILES: **1112 of 21717** (19 files at zero)

Worst: `runtime/support/am/amdev.bend` 122/470, `uop/ops.bend` 85/435,
`runtime/ops_nv.bend` 69/630, `runtime/support/system.bend` 55/540,
`helpers.bend` 46/254, `runtime/ops_qcom.bend` 45/497,
`runtime/support/memory.bend` 40/382, `dtype.bend` 35/95,
`runtime/ops_rdma.bend` 32/333. `runtime/support/nv/ip.bend` is 0/543 -- the file
that was audited hardest is also the only one with no dead weight, which is the
argument for the audit rather than against it.

`.agents/slop/dead-defs2.py` measures this; `dead-defs.py` (base-name matching)
undercounts by a factor of four on any namespaced file.

### A CROSS-FILE SUBSTRATE PRUNE IS A HALF-SPACE EDIT AND NOTHING CATCHES IT

Four `device.bend` readers (`DEnt.cls`, `Bn.self_ix`, `Bn.base`, `Bn.spec`)
deleted as "provably unread" took down SIX importers in one step:
`runtime/ops_nv.bend`, `schedule/multi.bend`, `mixin/rand.bend`,
`engine/jit.bend`, `function.bend`, `uop/fold.bend`. The `Bn` RECORD still had
the fields; only the readers were gone, so `grep 'self_ix' device.bend` still
matched and the file still read as complete.

**The pruner must prove unread ACROSS the import closure, not inside one file.**
A def is unread if nothing calls it, and the callers are in other files.

---

## 2026-10-02 — the dtype rename unit (tinygrad `793abbb`, "modernize tinygrad's dtype to match rust")

Numbering continues from the end of the file above; rule numbers collide across
units, so cite POSITIONS.

### A `+` PARAMETER AND A `+` CASE BINDER MAY ONLY BE PASSED **BARE**

`case Some{+left}` and `use2(+a, h)` both fail with

```
- expected : a bound variable
- observed : a^-1
```

and so does `use2(a, +h)`. A `+` binder is already in the `^-1` state, so
passing it *as* `+` is a second reversal of a value that has none left. Only a
**plain** binder (`case h <> t:`) may be passed either way.

Corollary, and this is the one that costs an afternoon: **a `+` parameter may be
read as many times as you like, but every read passes it BARE.** So
`def lut_row(+a: S.Dt, +b: S.Dt)` reading `b` twice is fine, and
`case Some{left}` (a plain field of a plain `Maybe` parameter) reading `left` and
handing it to `lut_row` is not, because `lut_row`'s parameter is `+` and the call
must then reverse it.

### A SELF-CALL'S ARGUMENTS ARE READ LEFT TO RIGHT, AND THE FOLDS THAT SATISFY IT

`lut_rows.go(+a, ds, acc)` cannot be written as
`case +h <> t: lut_rows.go(+a, +t, String.append(acc, lut_row(+a, +h)))`:

```
- expected : a decreasing self-call (arguments are read left to right:
  each passed unchanged until one shrinks)
```

and moving `+a` to the third position gives `observed : a^-1`, because the
argument before it already consumed it. Three shapes that DO satisfy it, all
measured in `tinybendygrad/test/dtype_oracle.bend`:

| need | shape |
|---|---|
| a value used by two arms | `case +h <> +t:` |
| a value reused after a self-call | bind it first: `+r = f(...)`, then the self-call |
| a shrinking accumulator as the last argument | `case +h <> t:` plus `+r = ...` |

### A `+` DO-BINDING, NOT A PLAIN ONE, FOR A LIST USED TWICE

`main` reading the same `List<&2, S.Dt>` in seven `IO.print` calls needs
`+all : List<&2, S.Dt> <- IO.pure(...)`. A plain `all : ...` gives
`expected : all / observed : all (consumed more than once)`. A List is a `Type`
and a `+` on a `List` parameter is fine — `lop.dts.go(+ds: List<&2, S.Dt>, ...)`
already does it — so the restriction is on *how many times*, not on the type.

### CARRYING AN OUTER KEY DOWN A FOLD: PASS THE FULL LIST, NOT THE TAIL

The obvious `for h in dtypes.all(): for j in dtypes.all():` written as
`lut_rows.go(h, ds, "")` inside a fold over `ds` iterates the **tail**, so the
block is the upper triangle — 153 rows for 17 dtypes, not 289. `can_lossless_cast`
is NOT symmetric, so that silently drops half the table it is the gate for. The
full list has to ride as a `+` parameter alongside the shrinking one.

### A NAME TABLE HAS THREE VOCABULARIES AND ONLY ONE OF THEM IS `DType.name`

tinygrad has, for the same dtype: the **attribute** (`dtypes.bfloat16`), the
**name field** (`"__bf16"` before `793abbb`, `"bf16"` after) and a third,
unrelated table in **ONNX**'s vocabulary (`onnx_odt_key` answers `"float"`,
`"int32"`, `"bfloat16"` for ONNX integer codes). A rename that sweeps all three
corrupts the ONNX table; one that sweeps none leaves a lookup dead. `nn/onnx.bend`
is the worked example of the third: its `dtbl` row is INSENSITIVE to the rename
(it walks ONNX codes and prints `dt_name`, so both sides move together) while its
name table did not move at all.

### `repr` IS NOT `name`, AND UPSTREAM DELETED THE MAP THAT BRIDGED THEM

`DType.__repr__` was `f"dtypes.{INVERSE_DTYPES_DICT[self.name]}"` and is now
`f"dtypes.{self.name}"`, and `INVERSE_DTYPES_DICT` is GONE. It used to print the
**alias**: `repr(dtypes.float32)` was `dtypes.float`, because `"float"` is a later
key in `DTYPES_DICT` than `"float32"` and the inverse comprehension let the last
one win. So `uop/render.bend`'s twenty-arm `dt_attr` table is not renamed, it is
**deleted** — with name and attribute spelled the same there is nothing left to
map — and every gate row printing a dtype's repr changes value.

### THE CHEAPEST DETECTOR FOR A NAME-LAYER CHANGE IS A `repr`-PRINTING ROW

For this rename: `dtype.bend`'s own gate printed every dtype's `name` 17 + 289 +
289 + 51 + 8 + 14112 times and **not one answer moved** — only the name column,
in lockstep on both lanes. 14 766 rows, 1 declared pre-existing deviation. If the
arithmetic had moved, that gate would have said so in one run; had it not been
built, the 300-odd downstream sites would have been found by grep instead, which
finds the sites and not the damage.

### A COMMITTED GATE CAN BE A FILE THAT DOES NOT COMPILE

`tinybendygrad/test/dtype_oracle.bend` was committed, referenced by its own
header, and had **four** reversibility errors — the first attempt at a nested
fold over a dtype list. Nothing in the tree ran it. "The oracle is committed" and
"the oracle was ever executed" are different facts, and only the second one makes
a gate. It is worth an `ALL PROOFS CHECK` in CI, or a line in the TODO that says
who ran it.

### A SCRIPTED RENAME NEEDS ITS OWN ACCEPTANCE TEST, OR IT WILL BE WRONG TWICE

Two silent-damage instances from one script, both caught only by reading the
output rather than by the exit status:

* the quoted literal was rebuilt as `line[:start] + q + NEW + q + line[end:]`,
  which keeps the opening quote twice and drops the trailing one — and the
  membership test was against the QUOTED key while the regex captured the
  UNQUOTED one, so it reported "0 case keys renamed" on a file full of them.
* the same script was pointed at `to_dtype_of`, which is keyed by the ATTRIBUTE
  name, and "renamed" `"half"` to `"f16"` there — **deleting** an attribute
  spelling while adding nothing.

The rules that came out of it: compare against the barename, never the quoted
one; rebuild as `line[:start] + line[start] + NEW + line[end_of_name:]`; scope a
rename to a **named list of defs**, because "every `case "<str>":` in the file" is
not a definition of the safe set; and after any scripted edit, `git diff` the
whole file and read it.

### A FROZEN UPSTREAM SNAPSHOT IS NOT OURS TO MIGRATE

`.agents/slop/opstree/tinygrad/` is a verbatim copy of upstream, taken by another
unit so its oracle can run against a fixed tree. It carries 875 `dtypes.<old>`
spellings and every one of them must STAY, because its entire value is that it
matches upstream byte for byte. A rename sweep run with `--include='*.py'` over
`.agents/slop` will rewrite it, and the sweep's own report is the only place that
says so. Exclude by path and say why in the tool.

### CORRECTION TO THE SECTION ABOVE: only TWO of those four `device.bend` readers cost anything

MEASURED 2026-10-02, cross-cutting dead-def pass, with an alias-resolving
tree-wide checker. `runtime/ops_nv.bend:2729,2733,2734,2730` is the ONLY importer
that reads them, and it reads only `Bn.base` and `Bn.self_ix`, as `D.Bn.base` and
`D.Bn.self_ix`. `DEnt.cls` and `Bn.spec` have **zero** uses in the whole tree:

    grep -rn --include='*.bend' 'DEnt.cls' tinybendygrad/   # nothing outside device.bend
    grep -rn --include='*.bend' 'Bn.spec'  tinybendygrad/   # nothing outside device.bend

Deleting `DEnt.cls` and `Bn.spec` and keeping `Bn.base`/`Bn.self_ix` leaves
`device.bend` at `ALL PROOFS CHECK`, 107 rows byte-identical, both lanes
identical, and all six named importers still `ALL PROOFS CHECK`. So the note
above over-claims by two, and the over-claim matters: it makes the four look
like a load-bearing substrate when two of them are four lines of nothing.

### AN IMPORT ALIAS IS THE NAME, NOT THE MODULE, AND TWO PLACES GET THAT WRONG

A cross-file dead-def checker resolves `import ./op.bend as M` and must then
search for **`M.mo_prod`**, not `op.mo_prod` and not `mo_prod`. Both wrong forms
were measured here and both report a LIVE def as dead:

  * searching the MODULE name missed every `M.`-qualified call, and
  * `import ./op.bend` already carries the extension, so appending another
    `.bend` to the target resolved nothing at all -- also silently.

And a third, in the same function: naming the generator variable `c` shadowed
the file's stripped-lines list `c`, so `'\n'.join(c)` joined a STRING'S
CHARACTERS and matched nothing. A checker that cannot fail is not a checker:
after three bugs it still agreed with the broken per-file pruners on all 13
files it was checked against, and the only reason it was caught is that the
COMPILER caught the deletion first.

### A HEADER ROW THAT SAYS `PORTED` IS A USE, AND DELETING THE DEF MAKES THE LIE BIGGER

`runtime/ops_webgpu.bend`'s WHAT IS PORTED table named `dev.synchronize`,
`copy.copyout` and `prog.del`. All three were written, all three were named
PORTED, and all three were reachable from nothing -- the header claim was the
only thing keeping them alive, and the table is why `SYNC_WORK_DONE` read as a
covered enum member when no code ever emitted it. Deleting the defs and leaving
the table would have turned a dead def into a documented lie. **Deleting a def
means deleting its row in the header's ported-list, or rewriting it as DEAD with
the reason**, and the rewrite is the part a reviewer can check.

### PIN THE LITERAL, BUT `urow(nm, 140)` IS WORSE THAN WHAT IT REPLACED

The self-asserting shape is `row("x", f(CONST()))` -- the expectation is a def of
the thing it checks, so no edit to the constant can move the row. Two of the
three fixes, and the two shapes:

    WRONG  urow("wg_alloc_usage", alloc.usage())          # assertion? no. data row.
    RIGHT  urow("wg_alloc_usage", 140)                   # WORSE: a number with no
                                                          # link to the code at all.
    RIGHT  row("wg_alloc_usage", U32.is_eq(alloc.usage(), 140))

The middle form was written first, caught in review, and replaced. **Removing
the call removes the test.** The literal belongs on one side of a comparison
that still makes the call.

### A CONSTANT IS ONLY WORTH A LITERAL IF IT REACHES A REAL CALL -- SPLIT THEM BY WHERE THEY COME FROM

The ~45 self-asserting rows in `ops_webgpu.bend` are not one problem, they are
three, and the split is a fact about `tinygrad/runtime/autogen/webgpu.py` (which
IMPORTS: its enum dicts are readable by `importlib`, so every literal can be
read out of it rather than typed):

  a. REAL wgpu values. `WGPUBufferUsage_*`, `enum_WGPUFeatureName`,
     `enum_WGPUBufferMapState`. All confirmed against the module. These are the
     ones worth pinning, and nine now are.
  b. PORT-INVENTED TAGS. There is **no `WGPUObjectType` in `autogen/webgpu.py`**,
     so `OBJ_*` is the trace's own object-kind id, and `CALL_*` is the trace's
     own opcode. A wrong one cannot be a wrong register write. Their rows still
     check identity and order, which no fixture can separate from the numbering
     -- so RECORD the blindness instead of pinning numbers that are not claims.
  c. `SYNC_*` 1..6 is the port's INDEX into the six `synchronous`-wrapped calls,
     not a wgpu value: all six real calls pass the same
     `WGPUCallbackMode_WaitAnyOnly` (=1). Pinning 4 in a row about the fourth
     call's status name would look like coverage and be none.

### ROW COUNTS MUST COUNT NON-BLANK LINES, OR A FILE THAT PRINTS A BLANK SEPARATOR FAKES A LOSS

`uop/weak.bend` and `schedule/allreduce.bend` print a blank line between rows.
`wc -l` counted 104 and 50; `grep -c .` counts 52 and 48. Measuring with `wc -l`
reported "104 -> 103 rows" and "50 -> 48 rows" for two files where NOTHING was
deleted, and the first reading of that was "a deletion moved a row". No row
moved. **Diff whole `name=value` lines and count the non-blank ones**, which is
the same rule as the harness rule at the top of `agent-core.md` -- the counting
has the same trap as the comparing.

### WHEN THE LIVE SUBSTRATE IS MID-EDIT, `--check-only` THERE PROVES NOTHING

`uop/fold.bend` was being edited while this pass ran, so `mixin/*`,
`schedule/*` and `uop/*` all reported `SOME PROOFS FAIL` naming `bnd.sn.neg`,
which is in `fold.bend` and not in the file under test. The committed versions
of those files fail IDENTICALLY, which is the one-line way to tell "I broke it"
from "someone else is": **put the committed copy beside the edited one and read
the first line of both.**

Two more traps in that workspace, both measured:

  * bend 2.0.34 caches by PATH, so overwriting a file IN PLACE and re-running it
    returns the PREVIOUS file's rows. Every variant needs its own path
    (`_f1_x.bend`, `_f2_x.bend`), which is also how relative imports stay
    resolvable -- a `$TMPDIR` copy cannot resolve `import ../helpers.bend`.
  * `jj restore` run from INSIDE a `jj workspace` resolved to the MAIN working
    copy and silently undid four deletions in `tinybendygrad/device.bend`. The
    files came back byte-identical to `@-` with no error anywhere. Inside a
    scratch workspace, only ever `cp`; never run `jj` there.

---

## FROM THE `uop/fold.bend` `_min_max` OP-TABLE UNIT (2026-10-02, the `bit_length` + dtype-limit + ladder unit)

Numbering continues from the last series in this file. The integers below start at **45**;
positions are what is unique, so cite these by the heading.

### 45. **A `match` TAKES THE FIRST CASE THAT MATCHES, SO A SECOND ARM ON THE SAME CONSTRUCTOR IS DEAD CODE -- AND AN ARM THAT ANSWERS `None` SKIPS PAST IT**

`Ops.AND` has TWO arms in `_min_max` (ops.py:1110 and :1128): the integer mask, and the
`bool` dtype's `and`. The second is reachable exactly when the first is not -- the integer
one is gated on `dtypes.is_int(self.dtype)`. Both natural spellings are wrong:

* two `case O.OpsAND{}` arms: the second is dead, because a `match` takes the FIRST arm
  whose pattern matches and both patterns are the same constructor;
* `case O.OpsAND{}: <int arm>` then `case _: <bool arm>`: the integer arm RETURNS A
  `Maybe`, so a `None` leaves `mm.bin.arm` as the arm's own answer and the `case _:` is
  never consulted.

Measured cost: every `andb_*` gate row answered `bool`'s own limits. The fix is ONE
dispatch def over the dtype's class:

```bend
def mm.bin.and(bl: Bool, +d: S.Dt, +s0: Bnd2, +s1: Bnd2) -> Maybe<&2, Bnd2>:
  match bl:
    case True{}: Some{mm.bin.and_bool.go(s0, s1)}
    case False{}: mm.bin.and_int(bnd_bin.and_gate(s1, d), s0, s1)
```

### 46. **AN ARM LIST AND A `Maybe`-RETURNING DISPATCH ARE THE SAME SHAPE, AND THE `Maybe` IS THE FALL-THROUGH**

`_min_max`'s `GroupOp.Binary` block is entered for thirteen ops and only ELEVEN of them
have an arm, and Python falls THROUGH to the arms below the block rather than answering.
So the block's return type is `Maybe<&2, Bnd2>` and the fall-through is one def:

```bend
def mm.MM2.get(m: Maybe<&2, Bnd2>, fb: Bnd2) -> Bnd2:
  match m:
    case Some{x}: x
    case None{}: fb
```

Inverting `get` moves 90 of a 127-row gate. `Maybe.default` is the WRONG shape here because
the fallback is a call that must be built either way and `default` hides which half fired.

### 47. **THE SIGNED ORDER OVER `(sign, unsigned magnitude)` IS FOUR CASES, NOT TWO -- AND THE TWO-CASE SPELLING IS `ALL PROOFS CHECK`**

For `a < b` with `a`, `b` each a `Bool` sign plus an unsigned 64-bit magnitude:

| `na` | `nb` | answer |
|---|---|---|
| `neg` | `neg` | `|a| > |b|` |
| `neg` | non-neg | **always true** |
| non-neg | `neg` | always false |
| non-neg | non-neg | `|a| < |b|` |

The collapsed spelling -- "if `a` is negative compare the magnitudes backwards" -- is wrong
on the middle two rows, which is every comparison of a negative against a non-negative.
Measured: `max(-3, 4)` answered `-3` and `cmplt(-3, 4)` answered `False`, on **53 of 123
rows**. It terminates, typechecks and prints.

### 48. **A NEGATION IS THE SIGN AND NOTHING ELSE; THE `- 1` BELONGS TO `~`, NOT TO `-`**

`-x` is `SNok{Bool.not(neg), mag}` -- the magnitude is already `|x|`. `~x = -x - 1`, so the
`+ 1` is `bnd.not`'s and NOT `bnd.sn.neg`'s, because a subtraction IS a sum of a negation
and putting the `+ 1` there makes `x - y` one too low on every SUB row (`3 - 4` answered
`-2`, `5 - 5` answered `-1`).

### 49. **A SIGN-AND-MAGNITUDE REPRESENTATION NEEDS A CANONICAL ZERO, OR `-0` IS A SECOND VALUE**

`0 * -5` builds `SNok{True, 0}`. That is the same Python int as `0` and a DIFFERENT `Bnd`,
so a gate that prints the bound as a string sees the difference. Normalise at the one
constructor every value passes through (`bnd.sn.put`), not at the twenty call sites.

### 50. **A `Bool` HAS NO `is_eq` IN BEND 2.0.34, AND EQUALITY IS THE NEGATION OF `xor`**

`Bool.and` / `Bool.or` / `Bool.xor` / `Bool.not` are the whole of it. `a == b` is
`Bool.not(Bool.xor(a, b))`. Getting it backwards inverts every sign test in a section at
once: one such mutation moved 51 of 127 rows. (`U32` has `is_eq`; `Bool` does not.)

### 51. **`mm.u64.is_zero(+hi, lo)` TAKES TWO WORDS, AND PASSING ONLY THE HIGH WORD MAKES A NON-ZERO READ AS ZERO**

The committed `mm.u64.join` uses `mm.u64.is_zero(H.hi32(t3), 0)` ON PURPOSE -- it is testing
the high word alone. Three new call sites copied the shape and meant "is the whole pair
zero", so `neg(4)` answered `0`, `shr` of a negative answered garbage, and `bnd.nz` called
every non-zero bound zero. **`Nat` is the trap here and not `U32`:** `mm.u64.is_zero` takes
two `U32`s and reads fine; `U32.is_gt(mm.bl64(...), 64)` needs `64` as a `U32` literal, and
`32n` in the same position is a `Nat` and a type error.

### 52. **`Bool.pick` BUILDS BOTH ARMS, SO A SHARED `Maybe`-SHAPED RESULT MUST BE A PARAMETER**

`def Bool.pick(-A: Type, c: Bool, a: A, b: A) -> A` is a `match`, and an argument is built
before the call. So the idiom for "a computed `Bool` cannot be a scrutinee" is to compute it
at the CALL SITE and pass it: `mm.bin.sh(k, s0, lft)`, `mm.bin.and(bl, d, s0, s1)`,
`mm.range(vd, srcs, d)`. Ten of this section's defs exist only because of that, and each is
one parameter.

### 53. **`List.get` OVER A `List<&2, T>` IS FINE, BUT A SRC LIST BUILDER MUST INTERNS ITS ELEMENTS THROUGH ONE CONSTRUCTOR**

`lf_c2(a, b) -> [Bnd2{a, a}, Bnd2{b, b}]` is a two-element list literal and `List.get(&2,
Bnd2, xs, 1)` reads the second one correctly. The trap is the OTHER direction: a `List<Bnd2>`
built by a `List.foldl` over a `List<Bnd>` needs `List.append(&2, Bnd2, acc, [Bnd2{x, x}])` --
accumulator FIRST -- and the fold's step cannot be a lambda with a `+`, because a `+` is
part of a function value's TYPE and a field cannot spell it (the closure-shared-arg wall).
**Four arities were less code than the wall** for a list of at most four elements.

### 54. **`F32` HAS NO LITERAL AND NO NEGATIVE LITERAL, SO A PYTHON FLOAT FIXTURE IS AN ARITHMETIC EXPRESSION**

`F32.from_nat(1n)` is `1`, not `1.5` -- the family this file keeps re-measuring. A fixture
whose CPython value is `1.5` has to be written `F32.div(F32.from_nat(3n), F32.from_nat(2n))`,
and a negative one `F32.neg(...)` of that. `F32.div(0, 0)` is the one NaN Bend can build,
which is what makes a NaN-CONST row possible at all. (`F32` DOES have `is_eq` and it is
IEEE, so `not isnan(v)` IS `v == v` -- there is no `is_nan` and none is needed.)

### 55. **A `match` ON A TWO-SCRUTINEE `match` NEEDS `_ _`, NOT `_` -- AND A ONE-SCRUTINEE `match` NEEDS `_`**

`case _: False{}` after two scrutinees is `expected : 2 patterns (one per scrutinee)`.
Different arity, same rule, and the error names the place rather than the count. Worth one
line because the fix is mechanical and the error is not.

### 56. **A CONCURRENT AGENT'S IN-FLIGHT EDIT IN AN IMPORTED FILE LOOKS EXACTLY LIKE YOUR OWN REGRESSION, AND THE ERROR NAME TELLS THEM APART**

`fold.bend` imports `ops.bend`. Mid-session `ops.bend` went red three times at three
DIFFERENT defs (`EqAx.pairs`, then `Rng.srcops`), each with `--check-only` reporting
`SOME PROOFS FAIL` and a `Location:` line that is NOT in the importing file's line numbering
range. `grep -c EqAx fold.bend` is `0`, which is the proof. **The discriminator is: is the
named def in your file?** If not, it is not yours, do not edit it, and say so in the report
-- and capture your gate output BEFORE it goes red, because you will not get a green
`--check-only` back until that agent finishes.

---

## APPENDED 2026-10-02 (gate-harness pass) -- rules 57-64. Numbering continues from
## rule 56 at line 9442, which is the last rule before this block.
## *** THESE NUMBERS ARE AMBIGUOUS AND THE FILE SAYS SO AT ITS TOP. 57-64 already
## *** exist at lines 7060-7099 (a different unit's series). CITE THE POSITIONS:
## *** the gate-harness rules are lines 9457-9549, and the file-order `rg '^### '`
## *** list is the only unambiguous index.

### 57. **`bend <file> -o -` WRITES ZERO BYTES AND `bend -r` DOES NOT EXIST, SO A
### NATIVE LANE BUILT THAT WAY COMPARES NOTHING AND SAYS NOTHING**

Bend 2.0.34 chooses the backend by the output file's EXTENSION (`bend --help`: "build a
binary, or C, JS, .mjs or BendTT by extension"), so `-o -` is not "write to stdout", it is
"write to a file with no extension". Measured: `bend tinybendygrad/runtime/support/hcq2.bend -o -`
exits **0** and writes **0 bytes**. There is also no `-r` flag. `hcq2-diff.py` ran exactly
that and then executed the resulting 0-byte file, so the lane had no rows to disagree with,
and the summary line read `rows: interpreted=360 native=0 cpython=163` -- a lane with
nothing to say, phrased like a lane that agreed. **The native lane is `bend <f> -o <f>.bin`
then RUN `<f>.bin`, and the build must be size-checked**, because a cache that stored the
0-byte artefact makes the lane dead again after the command is fixed.

### 58. **`0` ROWS COMPARED AND `0` ROWS DISAGREED PRINT THE SAME `0`.**

Measured on `drift-gate.py`, the generic three-lane driver: run with no `--oracle`, it wrote
an empty `cpython.txt`, `rows()` returned `{}`, every disagreement set was empty, and it
printed `== THREE LANES AGREE ==` with **exit 0**. A harness must therefore (a) refuse to
report agreement unless `COMPARED > 0`, (b) print the count from EACH side, and (c) treat a
lane with 0 rows as a lane that DID NOT RUN. `diff` does not save you either: `diff a b` over
two EMPTY files is silent, and `bend`'s compiler error dump lands in the same file as the
rows, so "the port disagrees with CPython on 71 rows" and "the port did not compile" are the
same output unless `wc -l` is run first.

### 59. **A `py=` LITERAL INSIDE THE PORT IS NOT AN ORACLE, AND A HARNESS THAT READS
### ONE MUST NOT PRINT THE WORD "CPython".**

`wip/gate.py` compared cstyle's `[bend]` half against the `py=` literal **in cstyle.bend**
and printed `GREEN 133 / 227 rows match CPython byte for byte` without ever starting CPython.
`cstyle_oracle.py` existed, ran, and was never called. This is `device.bend`'s `sig=0 4 5`
defect with better branding. Run the oracle, name it on every summary line, and report the
baked literal separately as a PORT ARTEFACT. Measured on the fixed gate: 94 of 227 baked
literals disagree with the port's own output and **live CPython sides with the PORT in 54 of
them and with the literal in 0** -- so those 94 rows are stale text in the port, not port bugs,
and only a real oracle could have told the two apart.

### 60. **A NAME-KEYED DICT SILENTLY DROPS EVERY ROW THAT REUSES A NAME. PUT THE
### DISAMBIGUATOR IN THE ROW NAME, NOT ONLY IN THE ROW.**

`agent-core.md` says a name-comparing harness reported 0 for all 30 mutations in one unit.
The mechanism, measured: `cstyle_oracle.py` emitted `rd BASE ` **7 times** (once per dtype)
and `cfo BASE ` **20 times** (once per op/dtype), so `{name: value}` kept one of each and
discarded 99 rows -- and the row COUNT it printed (127) was the count of a dict that had
already thrown the rest away. The port had no problem: `rd_row` appends the dtype name and
`cfo_row` appends op and dtype. **The oracle's names must carry the same disambiguator, and
a differ must treat a duplicate row name as an error rather than as a redefinition.**

### 61. **AN AUTHORITY AND A FIXTURE MUST BE THE SAME QUESTION. A ROW WHOSE PORT FIXTURE
### CPython CANNOT BUILD IS NOT A WEAKER ROW, IT IS AN UNFALSIFIABLE ONE.**

`mixin/elementwise.bend`'s `ew_promo_nc` builds its graph from a BUFFER of a weak dtype.
CPython cannot build that: `Tensor.empty(..., dtype=dtypes.weakint)` raises `cannot create
storage for weak dtype` at `tinygrad/mixin/creation.py:37`. So that row has no CPython
counterpart and never had. The CPython-reachable weak-not-const fixture is an ALGEBRAIC
result (`Tensor(3)+Tensor(5)`), whose graph is `7 CONST/0 CONST/0 ADD/2 CAST/1 CONST/0
CAST/1 ADD/2 ` against the port's `5 BUFFER/0 ADD/2 CAST/1 BUFFER/0 ADD/2 `. The two rows
that READ A DERIVED VALUE of that graph (`ew_dt_promo_nc`, `ew_op_promo_nc`) agree with
CPython and are real gates. **When a port's fixture is unreachable in CPython, say so in the
port's header with the exception -- do not print the nearest CPython row and call it the
same fixture.**

### 62. **A LANE THAT DIED OF THE ENVIRONMENT MUST SAY WHICH LANE AND WHY, IN ONE LINE.**

`mt_diff.py` on this host: lane 4, `mt_constmap.py`, launches a real `DEV=CPU` kernel and
clang rejects it, so the oracle exits 1 and the old wrapper `sys.exit(f"FAILED {cmd}\n...")`
printed 165 lines of C errors with no statement of what had not run. That reads like a gate
result. Now every lane reports `LANE DID NOT RUN [<lane>]: <cmd> exited N` plus the last six
stderr lines, and the run ends `GATE DID NOT RUN: at least one lane produced no output.
Nothing was compared.` **Print the tail of the failure, never the trace.**

### 63. **A HARNESS YOU HAVE NOT SEEN FAIL IS A HARNESS YOU HAVE NOT TESTED. PERTURB A
### COPY BESIDE THE SOURCE.**

The port under test usually belongs to a live agent, so the perturbation cannot be an edit.
It can be a copy **in the port's own directory** -- a relative `import ./x.c` does not
resolve from `$TMPDIR` (that is what produced 22 phantom blind spots in one unit), so the
copy has to sit where the imports resolve. A dotted name (`.gateprobe_<unit>.bend`) keeps it
out of a reader's eye; delete it the moment the red output is captured. Give the harness a
port ARGUMENT for this, the way `drift-gate.py` and `mt_diff.py` already do. Measured, all
four: cstyle `9 -> 10` disagreements naming `under signed char`;
`hcq2_pack_empty_8: bend='P16' cpython='P8'`; `mt_ver13: oracle='metal3.0' bend='metal3.1'`;
`ew_wd_bool=True -> False`. One changed token, one named row.

### 64. **A SUMMARY THAT COUNTS "FALSE" OVER A FILE THAT ALSO PRINTS TEXT IS REPORTING A
### NUMBER IT CANNOT BACK.**

`renderer/isa/x86.bend` reports `0 False` across 722 rows, and ~80 of those rows are bare
string concatenations with **no `Bool` in them at all**
(`"direct.JMP = [" ++ Hex.bytes(...) ++ "]   py=[e900000000]"`), so the `False` count never
covered them and a diff against the oracle found 160 differing lines. **A harness that
summarises a file's health must separate assertions from printed text and print both counts**,
or `0` is a number about a subset wearing a label about the whole file. Same shape as rule
58, one level up: a count over an unnamed subset.

---

## FROM `renderer/isa/x86.bend` — the `Enc.emit` root-cause unit (2026-10-02)

Numbering continues from the position above (this file is append-only and its rule
NUMBERS have already collided three times, so CITE THE POSITIONS: this block starts
immediately after the `renderer/isa/x86.bend` rule 64 that reports `0 False` over a file
of which 80 rows contain no `Bool`). Nine rules; six of them are about a MEASUREMENT
that lies, and three are about Bend.

### `&` BINDS TIGHTER THAN `==` IN PYTHON, SO `x == 1 & y >> 2` IS NOT `x == 1 and y >= 4`

`tinygrad/renderer/isa/x86.py:560` reads

```python
if w | r | _x | b | (reg_sz == 1 & reg >> 2) | (rm_sz == 1 & rm >> 2) | (demote and disp_uop is None and rm >= 4):
```

and `&` binds tighter than `==`, so the two clauses are `reg_sz == (1 & (reg >> 2))` and
`rm_sz == (1 & (rm >> 2))` -- a test for `reg_sz` being **ZERO** for registers 0-3 and
8-11 and **ONE** for 4-7 and 12-15. The port read it as `== 1 and >= 4`, which is false for
every register below 4, so the null `0x40` REX byte that `MOVi` and all four `SET*`
instructions carry disappeared and every byte after it shifted. **This is the one class of
Python that a mechanical 1:1 port cannot read correctly by eye, and it is worth grepping
for in every Python file this project ports:** `rg -n '== *\d+ *[&|^]' tinygrad/`.

### AN ORACLE THAT RE-TRANSCRIBES ITS SUBJECT'S CONTROL FLOW IS A FOURTH ROUTE INTO THE RE-TRANSCRIPTION TRAP

`agent-core.md` names three: a hand-typed literal, a re-typed `py=` half, and a row whose
expected value is a def of the thing under test. The x86 oracle had a fourth, and it is the
one that hides best because the oracle is *code*:

`enc_inputs()` re-implemented `encode`'s three address arms (x86.py:600-616) to work out
what numbers to hand `Enc.emit`. It was wrong in three places simultaneously --

  * `reg_uop = rest[0] if x.dtype is not dtypes.void else None` where the source says
    `_encode(x, ...) if x.dtype is not dtypes.void else _encode(rest[0], ...)`. **The
    condition was inverted**, so `CMP`'s `reg` came out 5 where CPython has 2.
  * **NEITHER arm honoured the `if reg is None` fork.** `reg` is a parameter of the
    `encodings` entry (`SHL: encode(x, 0xD3, reg=4)`), and `_encode` only overwrites it when
    `reg_uop is not None`. The port was handed 0 for `SHL`, `SUBi`, `CMPi`, `IDIV`,
    `VPSRLDQ` -- every MODRM reg field of those five wrong.
  * `vvvv` was a hardcoded list of four op names, so `VPSRLDQ` -- which x86.py:610 passes
    `x` as `vvvv_uop` -- got 0 and emitted the VEX byte `f9` where CPython has `e9`.

So the port was not wrong about the Python: it was faithfully implementing a description
that was wrong about the Python. **The fix is to stop describing and start measuring:**

```python
inner = next(c for c in encode.__code__.co_consts
             if hasattr(c, "co_name") and c.co_name == "_encode")
sys.settrace(tracer)          # freeze the frame at the first line where all five
                              # operands are bound -- x86.py:547, before the mask at :567
```

A closure's code object is in `co_consts` and is NOT reachable as an attribute, and the
inner frame's `f_locals` carries its `nonlocal` REBOUND value (measured: `reg` shows 5 for
`SUBi`, not the stale parameter copy from the outer frame). Two lessons: **an oracle must
read its subject's state, not restate its subject's logic**; and **when the subject is a
closure, `co_consts` is where the inner frame is.**

### `U32.sub` WRAPS, SO A PYTHON FIELD WIDTH IS NOT A SUBTRACTION

`f"{mnem:7s}"` is `7 - len(mnem)` spaces, with zero for a name of seven or more. `U32.sub`
is `Word.sub(32n, x, y)` and WRAPS, so `7 - 9` is 4294967294 and `String.repeat(" ", ...)`
of that is not a padding, it is a hang. The port first wrote `U32.min(7, w)` -- the other
wrong answer, three spaces too few for every short mnemonic -- and **the fixture set had no
mnemonic over seven characters**, so `VCVTSI2SS` (nine) would have been the first thing to
hang rather than the first thing to be caught. Two rules: a saturating clamp is
`Bool.pick(U32, U32.is_ge(w, k), 0, U32.sub(k, w))` and not `U32.min`; **and a bound's
saturating behaviour is only tested by a fixture that crosses the bound.**

### A COUNTDOWN THAT DECREMENTS WITH ITS INPUT DROPS NOTHING

Porting `s[:-1]` as a countdown over the string:

```bend
case SCon{h, t} 1n+p: SCon{h, droplast.go(t, p)}   # WRONG: p = n - 1 and t is one shorter
```

keeps the invariant `n == length(s)`, so the base case is never reached and the function
is the identity. `Asm.mnem("X86Ops.MOVm")` answered `movm`. The two-line total spelling is

```bend
String.reverse(String.drop(String.reverse(s), 1n))
```

`String.drop` is total at every length and needs no proof obligation, which is worth more
than the walk. **A hand-written walk must be checked against a length that is NOT a
function of the input's length.**

### `List.concat(a, A, xss)` IS NOT AN APPEND, AND `List.append(a, A, xs, ys)` IS `xs ++ ys`

`List.concat` takes ONE argument and flattens one level, so `dsts ++ srcs` is
`List.concat(&2, String, [a, b])` and NOT `List.concat(&2, String, a, b)` (which type-errors
with `expected : List<&2, List<&2, String>>`, because the four-argument call parses as a
list of two lists and then tries to use the first as a quantifier).

The second half is the third measured instance in this file of `List.append` reordering: a
per-element text walk written `List.append(tail, [head])` reverses the operand list, and
`asm.L3` printed `rcx, rsp, rdx` where CPython prints `rdx, rsp, rcx`. **The head must be the
FIRST argument**, and the accumulator the second. Note the asymmetry that makes this survive
review: appending to an accumulator (`List.append(acc, [x])`) is correct and is what almost
every fold in the tree does, so the reversed form is the *unusual* one and looks like a
typo rather than an inversion.

### A ROW NAME MAY NOT CONTAIN THE DELIMITER THE REFERENCE PARSER USES

The oracle's `rows` mode extracts the answer half as `ref[ref.index("[") + 1:ref.rindex("]")]`.
That is correct while every row name is free of `[`, and it silently produced
`py=[rsp + rcx*4 + 8], rdx = [True]` for a row whose name is an assembly line. **A parser
that finds a delimiter with `index` is one row name away from reading the wrong span**, and
the fix is `rindex` on the *separator* (`ref.rindex(" = [")`), not a wider regular
expression. The rows themselves were fine and the REFERENCE was wrong, which is the
inversion that costs the most time to see.

### A GATE FILE GENERATED BY HAND IS A GENERATED FILE, AND A GENERATED FILE NEEDS A GENERATOR

`x86.bend` shipped 9878 lines of which **7900 were blank** -- the previous agent's tooling
wrote each def on a 50-line pitch. Collapsing the runs (`re.sub(r"\n{3,}", "\n\n", s)`)
took it to 2228 with the output byte-identical, and blank lines are not significant to the
parser. Separately, the 760 row literals were being hand-edited against a generator; they
are now written by `x86-gen.py`, which replaces the `Gate.rowsN()` blocks wholesale and
exits 1 on `--check` when they are stale. **A generated artefact that is edited by hand has
two authors and no merge rule**, and the row count is the only cheap detector.

### A CONSTANTS SWEEP FINDS CONSTANTS. EVERY DEFECT IN THIS ENCODER WAS LOGIC.

The `+1`-on-every-literal sweep over 707 literals moved 502 and left **205 blind**, and not
one of the nine defects `Enc.emit` had was among them: the duplicated opcode, the
big-endian immediate, the inverted `mod == 0` displacement, the misread `&`/`==`
precedence, the `disp_uop is None` clause in the wrong predicate, the two `we` selectors
reading the wrong sizes, the six-byte `JMP`, and the undemoted opcode byte were **all**
predicates and joins. The rules sweep (`.agents/slop/x86/x86-rules.py`, 48 entries, one
per ported rule) moves rows on every one of them. **Run both: the constants sweep's value
is its BLIND LIST, which is a list of fixtures to add, and the rules sweep's value is its
own coverage.**

### THE BLIND LIST IS A FIXTURE LIST, AND MOST OF IT IS ONE MISSING FIXTURE

Of the 205 blind constants, the largest class -- 45 legacy `Enc.of` entries x 3 of their 4
numeric fields -- is a THEOREM: `pp` and `we` are read only on the VEX path and `reg` only
when `has_reg` is `True`, so for an entry with `sel == 0` they are unobservable, and the
`enc.*` rows are what check them for the entries where they matter. The genuinely
actionable class is narrower and is one hole: **every fixture puts the destination in
`reg`/`idx`/`base` 0-7**, so `Enc.gt0`, `Enc.b1`'s zero arm and the REX R/X bit weights are
never exercised, `Enc.arm16`'s `sz == 2` never fires (so the `0x66` prefix has no row at
all), and `Enc.modrm_of`'s `rm == 0b101` clause -- which the source comment called "a gate row
of its own" -- has no rbp/r13 base fixture and is unobservable. **A comment claiming a clause
is gated is not evidence that it is.**
