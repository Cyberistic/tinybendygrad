# mixin/rand.bend -- tinygrad/mixin/rand.py, all 327 lines. `RandMixin`, which is
# ALSO the `Tensor` constructor for every random distribution in tinygrad.
#
# ---------------------------------------------------------------------------
# WHAT THIS FILE OWNS, MEASURED, AND IT IS NOT WHAT THE UNIT BRIEF INVENTORIED.
#
# The brief lists `arange`, `linspace`, `permute`, `randn`, `normal`, `uniform`,
# `bernoulli`, `multinomial` as living here. THREE OF THOSE EIGHT ARE NOT IN `rand.py`
# AT ALL and two more are in files this unit does not own:
#
#   `arange`    mixin/op.py:166         NOT ported anywhere (see the BORROWED BLOCK)
#   `linspace`  mixin/op.py:198         NOT ported anywhere
#   `permute`   mixin/movement.py:214   `mixin/movement.bend`'s `mxw_permute`, PORTED,
#                                     and CALLED below rather than re-implemented
#   `bernoulli` DOES NOT EXIST. `grep -rn "def bernoulli" tinygrad/` is EMPTY. tinygrad
#               spells it `randn` + a threshold, or `uniform(p) < p`; there is no
#               `bernoulli` symbol to port, and writing one would be inventing a def
#   `randn`     mixin/rand.py:106       MINE
#   `normal`    mixin/rand.py:141       MINE
#   `uniform`   mixin/rand.py:158       MINE
#   `multinomial` mixin/rand.py:251     MINE, and it is W5 below
#
# MEASURED: `grep -c "^  def " tinygrad/mixin/rand.py` gives TWENTY defs, and they are
# the twenty this file ports, in Python's order: `_threefry_random_bits` :12,
# `random_bits` :18, `_bits_to_rand` :32, `_rand` :40, `_next_counter` :46, `rand` :50,
# `rand_like` :70, `randn_like` :88, `randn` :106, `randint` :122, `normal` :141,
# `uniform` :158, `scaled_uniform` :176, `glorot_uniform` :192, `kaiming_uniform` :208,
# `kaiming_normal` :224, `randperm` :240, `multinomial` :251, `dropout` :278,
# `scaled_dot_product_attention` :298. The brief's eight is a list of things the EXAMPLE
# reaches, not a list of things this file contains.
#
# WHAT THE EXAMPLE REACHES THROUGH HERE IS FOUR OF ITS SIX, and that is worth saying
# because the brief says six: `examples/beautiful_mnist.py:25` calls `Tensor.randint(...)`,
# which is `randint` :122 -> `uniform` :158 -> `rand` :50, and
# `examples/beautiful_mnist.bend:78` records `TODO(p3) examples/beautiful_mnist.py:25`
# for exactly that. So the four this file closes for the example are `rand` :50,
# `randn` :106, `normal` :141 and `uniform` :158 -- the same four lines
# `mixin/creation.bend`'s header already named when it measured the same grep. The other
# two of the example's six are `arange` (op.py:166, via `_one_hot_along_dim` at op.py:1005
# and `binary_crossentropy` at op.py:1742) and `linspace`, and both are `W1` below.
#
# ---------------------------------------------------------------------------
# THE GENERATOR STATE, AND IT IS THE ONE DESIGN DECISION IN THIS FILE.
#
# Python's randomness is a MUTABLE, PER-DEVICE, PROCESS-WIDE pair of dicts plus a CLOCK
# (tensor.py:438-440) and a five-line `_next_counter` (tensor.py:460-471) that WRITES back
# into a device buffer. Four things about it are unportable and one is not, and the split
# IS the decision:
#
#   * `Tensor._seed: int = int(time.time())` is a CLOCK. It becomes an explicit `U32`
#     PARAMETER. A row that can print two different answers is not a row, and there is no
#     effect on this path to read a clock through.
#   * `hashlib.sha256(len(Tensor._device_seeds).to_bytes(4, "big"))` (tensor.py:462) builds
#     the key's first word from the DEVICE COUNT, so the key is not a function of the seed
#     alone. The port's key is a 1-D TWO-ELEMENT `uint32` TENSOR -- which is what Python's
#     own `Tensor(seed, dtype=dtypes.uint32)` is -- and it is a PARAMETER.
#   * `Tensor._device_rng_counters[device]` is replaced by a COUNTER TENSOR that is handed
#     IN, and `_next_counter`'s FIVE ARITHMETIC LINES are ported verbatim over it. That is
#     the whole decision, and it is the same discipline the arena uses: one owner, threaded
#     explicitly, never a global.
#   * `counter.assign(new_low.cat(new_high))` (tensor.py:468) is the device WRITE and it is
#     NOT PORTED. It is nine nodes -- `ALLOC/0 BUFFER/0 COPY/1 SHRINK/3 ADD/2 SHRINK/3 ADD/2
#     STACK/2 RESHAPE/2 STORE/2 AFTER/2`, MEASURED as nodes 40..55 of `Tensor.rand(2,3)` --
#     and every one of them exists to write a counter back to a device. So `rd_next`
#     returns the SAME `low.cat(high)` Python returns and drops the store.
#
# WHAT IS PORTED EXACTLY, including the borrow, because it is not what it looks like:
#
#     new_low  = counter[0:1] + (num & 0xffffffff)                     tensor.py:466
#     new_high = counter[1:2] + (num >> 32) + (new_low < counter[0])   tensor.py:467
#     low      = counter[0:1] - (num & 0xffffffff)                     tensor.py:469
#     high     = counter[1:2] - (num >> 32) - (counter[0] < (num & 0xffffffff))
#     return seed, low.cat(high)                                       tensor.py:471
#
# `low` and `high` read the ALREADY-STORED counter in Python -- the AFTER node -- and the
# port's `st_*` rows read the INJECTED one, so the two agree only because the injected
# counter IS the stored one. `st_after` is the row that makes that explicit: it is the
# same five lines with the counter the first call returned, so the borrow is exercised
# rather than assumed. `num == 0` is NOT the identity -- `high` still builds a `MUL` and
# an `ADD` for the `-(num >> 32)` term -- and `st_zero` is the row that says so.
# `(num & 0xffffffff)` is `num` itself for a `U32` (the mask is the identity) and
# `(num >> 32)` is `U32.shrn(num, 32n)`, which SATURATES to 0 past 31, so for every `num`
# a real shape produces it is 0 and that is the same answer. Both are one-line defs
# (`rd_mask`, `rd_hi32`) so the reader can see that they are simplifications and not
# accidents, and `st_big` is the row that shows the saturation.
#
# ---------------------------------------------------------------------------
# THE SIX WALLS, each at its Python line, each with what is specifically missing. NONE of
# the first five is a wall Bend cannot express; four are OWNERSHIP walls (the def lives in
# a file this unit may not write) and one is a device-state wall.
#
#   W1 mixin/op.py:166 `arange`, reached from rand.py:26. `arange` is
#      `full(...)._cumalu(0, Ops.ADD) + (start - step)`, `_cumalu` (op.py:752) is
#      `_pad_constant` (op.py:282) then `_pool` (movement.py:598) then `sum(-1)`, and
#      `_pool` needs `repeat` (movement.py:576) -> `expand` (movement.py:149) ->
#      `_broadcast_to` (movement.py:128) -> `broadcast_axes` (ops.py:89). `mixin/op.bend`
#      names the whole chain as ITS W4 and calls it "BUILDABLE, NOT CHECKABLE". The
#      BORROWED BLOCK below is those defs, SPECIALISED to the ONE case `arange` and
#      `_cumalu` reach, gated by `arange3` and `arange5`, and every one of them is
#      `op_`-prefixed and carries the owner file and line in its comment.
#      The specialisation is exact rather than convenient, and each step names the line
#      that makes it exact: `_cumalu`'s pad is `((shape[axis]-1, 0),)` (op.py:754) so both
#      pad entries are non-negative and `has_neg` is False (op.py:284);
#      `identity_element(Ops.ADD, dt)` is `0` (ops.py:61) so `if value == 0: return base`
#      fires (op.py:288) and `_pad_constant`'s `where` half is never built; `_pool` is
#      called with `stride=1, dilation=1` (op.py:755) so `s_` and `d_` are `(1,)`; and the
#      source is 1-D, so `noop` is empty and both halves of `_pool`'s last `permute`
#      collapse to `(1, 0)`. `broadcast_axes` is the only part with a real restriction and
#      it is the same one `creation.bend`'s W4 already argues: `resolve(s == 1,
#      default=False)` is `s == 1` for an `int`, so a CONCRETE `expand` is integer
#      arithmetic. The symbolic case is `mixin/op.bend`'s and is not here.
#      THIS IS THE W3 IN `examples/beautiful_mnist.bend:37`, and closing it removes ONE of
#      that file's two walls: `arange` stops being a wall there. It does NOT make W3
#      CHECKABLE, because `fold.bend:1622-1625` still defers PAD/SHRINK/EXPAND/PERMUTE and
#      an `arange`-rooted tensor's SHAPE is still `None{}`. `arange3_d` says so in its name.
#      TODO(p3) mixin/op.py:166  `arange` -- delete the `op_` block and call
#        `mixin/op.bend`'s `mo_arange` when that file grows it. `arange` is also reached by
#        `mixin/op.py:198 linspace`, `:215 eye`, `:233 _tri`, `:236 triu`, `:259 tril` and
#        `nn/__init__.py:370` (`_embedding_fwd`), so this block is worth more than
#        this file.
#   W2 mixin/op.py:731 `cat`, reached from rand.py:15, rand.py:29 and tensor.py:471.
#      `cat`'s all-equal-shapes arm is `stack(*args, dim).flatten(dim, dim+1)`, `stack`
#      (movement.py:256) is `_mop(Ops.STACK, arg=tensors[1:])` -- ops.py:831-834, which
#      needs `dtype_from_uop` and `ccast` and is `tensor.bend`'s own `TODO(p3)` -- and
#      `flatten` (movement.py:345) is a `reshape` to `prod(shape[0:2])`. `mixin/op.bend`
#      names the whole thing as ITS W6. PORTED: `op_cat1`, the TWO-operand all-equal
#      `dim=0` case, which is the only one `_threefry_random_bits`, `random_bits` and
#      `_next_counter` reach, gated by `tfb3`, `tfb6`, `bits6` and `st_six`.
#      TODO(p3) mixin/op.py:731  `cat`'s unequal-shape arm (`itertools.accumulate` plus a
#        `pad` and a `usum` per tensor) and its `dim != 0` case.
#   W3 mixin/op.py:74 `_getitem`, reached from rand.py:14 (`key[0]`, `key[1]`),
#      rand.py:101 (`src[0]`, `src[1]`) and tensor.py:466-470 (`counter[0:1]`, `counter[0]`).
#      `_getitem` matches on the Python TYPE of the index and `_parse_view_index`
#      (movement.py:86) answers a `dict` of five fields per index; `mixin/op.bend` names
#      the seven-way sum type as ITS W1. PORTED: `rd_take` (one non-negative `int` on axis
#      0, general in `ndim`), `rd_slice` (one half-open `slice` on axis 0) and `rd_scalar`
#      (the same read to 0 dims) -- a `SHRINK` and a `RESHAPE` each, and the only arms
#      this file reaches. Gated by `randn23`, `randn23h` and the `st_*` rows.
#      TODO(p3) mixin/op.py:74  `_getitem` for a negative int, a two-sided slice, an
#        `Ellipsis`, a `list`, a `Tensor` index or `None`.
#   W4 tinygrad/mixin/elementwise.py:500 `cos` and :830 `log`, reached from rand.py:103.
#      Both are three lines of already-ported ops -- `cos` is `((pi/2) - self.cast(...)
#      ).sin().cast(...)` and `log` is `self.log2() * math.log(2)` -- but
#      `mixin/elementwise.bend` has neither. PORTED: `rd_cos` and `rd_log`, each marked,
#      each CALLING `E.ew_sin` / `E.ew_log2` rather than re-deriving them.
#      TODO(p3) tinygrad/mixin/elementwise.py:500  `cos` for half/bfloat16, where
#        `least_upper_float` and `least_upper_dtype` are NOT the identity and the two folds
#        become CASTs.
#      TODO(p3) tinygrad/mixin/elementwise.py:830  `log`.
#   W5 rand.py:251 `multinomial`. With `replacement=False` it is
#      `(weight.rand_like(dtype=float32).log2() / weight).topk(num_samples, dim=1)[1]` and
#      `topk` (op.py:976) is a bitonic sort over four nested Python `for` loops plus
#      `.contiguous()` (`graph_rewrite`, P3, `mixin/op.bend`'s W5). With
#      `replacement=True` it is `weight.cumsum(1)` (op.py:770 -> `_cumalu` ->
#      `identity_element`, ops.py:61) then a broadcast div, a `rand`, a `>=`, a `sum(2)`
#      and a `permute`. PORTED: the `weight = self.unsqueeze(0) if self.ndim == 1 else
#      self` selection (rand.py:267) as `rd_multi`, both guards (rand.py:266, :268) as
#      `rd_multi_n`/`rd_multi_rep`, and the trailing `.cast(dtypes.int32)` (rand.py:276).
#      TODO(p3) mixin/rand.py:270  `multinomial`'s cdf arm -- `cumsum` -> `identity_element`.
#      TODO(p3) mixin/rand.py:275  `multinomial`'s Efraimidis-Spirakis arm -- `topk`.
#   W6 rand.py:278 `dropout` and rand.py:298 `scaled_dot_product_attention`.
#      `dropout`'s `if not TRAINING` (rand.py:294) reads `helpers.py`'s `TRAINING`
#      `ContextVar`, an environment seam and not a graph, so it is a `Bool` PARAMETER; the
#      three-way arm selection is PORTED and gated by `drop_arm0/1/2`, and the general arm's
#      body is a `TODO(p3)` because `.clone().where(self, 0) / (1.0 - p)` needs `where` over
#      a float mask and a division by a Python float whose promotion is not the same rule as
#      every other binop here. `scaled_dot_product_attention` needs `matmul`
#      (`mixin/op.bend`'s W8, a WMMA lowering with a device-specific arg), `tril` (op.py:259,
#      which is W1 again) and `repeat_interleave` (movement.py:560, unported). `softmax` and
#      `const_like` ARE ported and are CALLED.
#      TODO(p3) mixin/rand.py:296  `dropout`'s general arm -- `where` over a float mask.
#      TODO(p3) tinygrad/helpers.py  `TRAINING` -- the ContextVar read.
#      TODO(p3) mixin/rand.py:315  `scaled_dot_product_attention`'s GQA arm.
#      TODO(p3) mixin/rand.py:319  `scaled_dot_product_attention`'s matmul.
#      TODO(p3) mixin/rand.py:323  `scaled_dot_product_attention`'s causal mask.
#      TODO(p3) mixin/rand.py:327  `scaled_dot_product_attention`'s `attn_mask` arm.
#
# `rand_like` :70's multi-device arm is `creation.bend`'s W2 (`_multi_like` is a Python
# CALLBACK) and `randperm` :240 is `argsort` (op.py:965 -> the bitonic sort and
# `contiguous`, `mixin/op.bend`'s W5).
#   TODO(p3) mixin/rand.py:82  `rand_like`'s device-tuple arm.
#   TODO(p3) mixin/rand.py:249  `randperm` -- `argsort`.
#
# ---------------------------------------------------------------------------
# FIVE BEND RULES THIS FILE LEARNS, and the first is the one that cost the most.
#
#   1. A `U32` CANNOT BE READ TWICE IN ONE EXPRESSION AND CANNOT CARRY `+` AS A
#      PARAMETER, so every two-read `U32` expression here is split into two defs.
#      `_next_counter`'s `num` is read FOUR times across the five lines and `counter[0:1]`
#      in two of them, so `rd_next` is six defs rather than one, and `op_pool1`'s
#      `ceildiv`s each read `i` twice. This is device.bend's rule 3 reached from
#      arithmetic rather than from a buffer, and the `Data`-record answer is available here
#      too -- but a record cannot hold a graph, so the graph half is defs.
#   2. A `match` MAY NOT SCRUTINISE A CALL, so EVERY predicate in this file is a `Bool` or
#      a `U32` PARAMETER of the def that branches on it: `rd_rand`'s `contig`, `rd_btr`'s
#      `ub`, `rd_multi`'s `one`, `rd_drop`'s `arm`. There is no `if` in the file.
#   3. AN ARENA IS THE ONE A BUILD RETURNED. `rd_rand` hands `_bits_to_rand`'s tensor to
#      `rd_clone`, `rd_clone` hands `cr_empty_like`'s tensor to `cr_after`, and `op_cat1`
#      builds its STACK in the arena of the tensor that was made LAST. The gate's `n=`
#      counts and the ORDER of the toposort are the only rows that see it.
#   4. `case 1n+p:` SPENDS THE SCRUTINEE, so every walk that needs the current INDEX
#      threads it as a `U32` parameter; `rd_zeros`/`rd_tail` are the two list walks here and
#      neither needs one, which is the cheap case. `op_pool1` threads the source's `i` as a
#      parameter for the same reason `op_repeat1` does.
#   5. A `U32` LITERAL PATTERN IS A PREFIX MATCH, so `rd_nmant`, `rd_one_bits` and
#      `rd_uint_dt` list their arms ASCENDING (`case 8:` before `case 32:`) and end on
#      `case _:`. Written the other way round, `case 32:` claims every successor and the
#      `case 8:` arm is dead code that still checks.
#
# ---------------------------------------------------------------------------
# THE GATE. `main` prints one row per claim. Nothing is executed; every graph row is the
# SIGNATURE of the lazy graph, which needs no device.
#
#   sh $ORACLE_DIR/rd-gate.sh
#   .venv/bin/python $ORACLE_DIR/rd-truth.py                  > /tmp/py.txt
#   ./bin/bend tinybendygrad/mixin/rand.bend                  > /tmp/bd.txt
#   ./bin/bend tinybendygrad/mixin/rand.bend -o /tmp/bn && /tmp/bn > /tmp/bn.txt
#   diff /tmp/py.txt /tmp/bd.txt && diff /tmp/py.txt /tmp/bn.txt
#
# FOUR KINDS OF ROW, because four kinds of bug are invisible to the others.
#
#   <n>_g  THE FOUR FACTS IN ONE STRING -- node count, root op, root nsrc and the ROOT'S
#          SRC OP SEQUENCE -- and then the whole toposort. `CR.cr_row` is creation.bend's
#          printer and is CALLED, not copied. Its two halves are two SEPARATE walks
#          (`cr_srcops` over `Arena.srcs`, `cr_topo` over `UOp.toposort`) because a
#          countdown-driven src-ops walk printed `ALLOC|ALLOC|` for a two-src root while
#          every `nsrc=` stayed correct, and the sequence is the row that sees it.
#   <n>_d  shape and dtype off the FOLD, through the node the fold DOES answer:
#          `cr_d_root` reads `AFTER.src[0]`, because `fold.bend` cannot answer a graph
#          containing an EXPAND -- nodes 40..55 of `Tensor.rand(2,3)` are unanswerable and
#          nodes 56..68 read them, so the ABSENCE propagates upward along every edge. "Can
#          the fold answer X" is a property of the whole subgraph and not of X.
#          `arange*_t` is the dtype-only row, and its name says the shape is NOT gated
#          because `fold.bend:1629` answers `None{}` for an EXPAND's own shape.
#   st_*   THE GENERATOR STATE. Four rows over `_next_counter`'s five lines with the counter
#          INJECTED, and the expectations are CPython's own five lines run against
#          `Tensor([lo, hi], dtype=dtypes.uint32)` -- so they are CPython's answer and not
#          this port's. `st_zero` (`num = 0`), `st_six` (`num = 6`, the value `rand(2,3)`
#          uses), `st_after` (the counter `st_six` returned, fed back in, so the borrow is
#          exercised) and `st_big` (`num = 1 << 33`, where `U32.shrn`'s saturation is the
#          answer and the 64-bit half is not).
#   ref_*  THE REFUSALS, asked as CPython's OWN PREDICATES rather than as this port's
#          behaviour, because a pure Bend def cannot raise. `ref_rand_weak` is rand.py:63's
#          guard, `ref_uniform_lt` is rand.py:172's, `ref_normal_std` is rand.py:154's,
#          `ref_randint_int` is rand.py:136's, `ref_dropout_p` is rand.py:293's,
#          `ref_multi_n` is rand.py:266's and `ref_sdpa_dt` is rand.py:319's
#          `least_upper_dtype` -- a DTYPE and not a graph, so it is a shared row.
#
# THE TWO THINGS THIS GATE CANNOT SEE, said here rather than discovered later:
#
#   * `int(time.time())` (tensor.py:438). Every row supplies the key and the counter, and
#     the header's paragraph on the generator state is the reason. A row that read a clock
#     would differ from the oracle on every run and the diff would be noise.
#   * `counter.assign(...)` (tensor.py:468) -- the nine-node device-write block. It is in no
#     row, and `st_after` is where its EFFECT is pinned instead, by feeding the stored
#     counter back through the same five lines.
#
# THE MUTATION TABLE is at the FOOT of this file, measured, with the rows each one moves
# and the blind spots it exposed.
#
# ---------------------------------------------------------------------------
# GATE STATUS -- MEASURED 2026-10-02, AND THE GATE IS **RED**. 31 OF 49 SHARED ROWS MATCH
# AND 18 DO NOT. `ALL PROOFS CHECK` in both lanes and the two lanes print BYTE-IDENTICAL
# output; the disagreement is with CPython, and it is 18 graph rows out of the 18 graph rows
# the file prints. This section is the finding, not an apology, and it is here rather than
# in a report because a reader who runs the gate will otherwise think the file is broken.
#
#   WHAT IS GREEN, 31 rows, and it is every NON-GRAPH row:
#     * 17 `ref_*` REFUSALS: `ref_rand_weak_{f32,wf,h,i32}`, `ref_shape_u32`,
#       `ref_uniform_{lt,not}`, `ref_normal_{std,not}`, `ref_randint_{int,not}`,
#       `ref_dropout_{p,p1,p1n,not}`, `ref_multi_{n11,n23,n31,rep}`.
#     *  7 `ref_*` DTYPE ARITHMETIC: `ref_sdpa_dt`, `ref_shift_{f32,h}`,
#       `ref_one_bits_{f32,h}`, `ref_nmant_f32`, `ref_uint_dt_f32`.
#     *  2 `ref_*` COUNTS: `ref_bits_num23=6`, `ref_bits_num223=12` -- the two words
#       `random_bits` asks for, and the pair with `st_*` is what pins `rd_bits_num`.
#     *  3 `ref_drop_arm*`: `dropout`'s three-way arm selection (rand.py:294-295).
#     *  2 BEND-ONLY: `fold_np=False`, `fold5_np=False` -- "CAN THE FOLD ANSWER THIS
#       NODE'S DTYPE", which is the measurement that `arange` is BUILDABLE and NOT
#       CHECKABLE (`mixin/op.bend`'s W4) in two numbers. They have no oracle because
#       `fold.bend` is this port's own and CPython has no fold to ask.
#
#   WHAT IS RED, 18 rows, and it is EVERY GRAPH ROW:
#     st_{zero,six,after,max}_g   arange{3,5}_g   ctrl_arange3_g
#     tfb3_g   bits6_g   btr6_g
#     rand23_{g,d}   rand23nc_{g,d}   ctrl_rand_{g,d}   rand_like23_{g,d}
#
#   THE TWO ROOT CAUSES, both MEASURED, and the second is the one that has to be fixed
#   first because it takes the other three with it:
#
#   R1 -- THE ARENA, AND IT IS NOT "BUILD IN THE LAST ARENA". `bits6_g` prints
#     `n=1 op=RESHAPE nsrc=2 srcops=STACK|STACK topo=CONST/0` against CPython's `n=81`, and
#     `st_six_g` prints `n=2` against CPython's `n=20`. A toposort of ONE node means the
#     root's data src is not IN THE ARENA BEING WALKED, so the node is not a graph at all.
#     The cause is that `O.Arena` is affine and a def that BUILDS grows a COPY: a chain
#     like `rd_tfb -> rd_p64 -> rd_c64 -> mo_cast_t -> mo_cast_in -> F.folded(Tensor.ar(t))`
#     takes the arena off whichever tensor it is HANDED, and two operands built in
#     different copies name indices neither copy has. `randn_like`'s two `rd_take`s hang the
#     interpreter outright (`bend: memory fault (machine stack overflow?)` at
#     `randn_like23_g`), which is the notes' "an argument is evaluated before the callee
#     branches" reaching a self-edge. THE FIX IS THE WHOLE-FILE THREAD: every def that
#     builds takes `+ar: O.Arena` as an argument and rebases its operands with
#     `T.tn_new(ar, Tensor.u(t))` before building, which is the notes' own rule
#     ("every step threads `O.Found.ar(<previous binding>)`") applied to a file that has
#     not had it applied yet. `op_pool1` threads its `i` and `k` and gets its arena right for
#     the same reason, which is why `arange3_g` is 28 nodes and not 1.
#   R2 -- `arange` IS THREE NODES SHORT AND ITS ROOT IS A `CAST`. CPython's
#     `Tensor.arange(3, dtype=dtypes.uint32)` is `n=31 op=ADD nsrc=2 srcops=REDUCE|CONST`
#     and the port's is `n=28 op=CAST nsrc=1 srcops=ADD`. Two of the three are ONE defect:
#     (a) the trailing `.cast(dtype)` (op.py:195) is a FOLD in CPython -- the `_cumalu`
#     result is already `uint32` -- and `op_arange.cast` is NOT FOLDING here, which is
#     exactly op.bend's W9b: `mo_promote` remints a weak CONST instead of leaving it weak,
#     so `op_arange.add`'s `mo_bin_c(_, ADD, mo_ki(-1))` mints a `CAST` of the weakint
#     `-1` where CPython builds none. (b) the third node is `_pool`'s THIRD `shrink_to`,
#     which is a no-op in CPython and a `RESHAPE` here.
#   R3 -- `mxw_reshape` AND `mxw_stk` BUILD A `STACK` FOR A ONE-ELEMENT SHAPE ARG AND
#     CPython BUILDS A BARE `CONST`, which is why `op_pad`/`op_shr` are LOCAL copies here
#     and why the `arange3` diff has `STACK/1 RESHAPE/2` where CPython has `CONST/0`. The
#     two pairs were fixed for PAD and SHRINK (see `op_mop`) and NOT for RESHAPE, and
#     `op_expand_lead`'s `mxw_reshape(t, [])` and `rd_bits.cat`'s
#     `mxw_reshape(..., [2*n])` are the two RESHAPEs still carrying a one-element STACK.
#   R4 -- `randn_like` HANGS. `rd_take` on the `stack(self)` result is R1 again, and the
#     hang is a runaway `mxw_dims_of` fold over a graph whose arena is inconsistent. The
#     eleven rows that depend on it (`randn*`, `uniform*`, `randint*`, `normal*`,
#     `scaled_uniform*`, `glorot_uniform*`, `kaiming_*`, `randperm_rand`, `multi*`,
#     `drop_arm*`) are therefore NOT IN `main` and are UNMEASURED. They are stated here so
#     that "31 green" is not read as "49 green".
# ===========================================================================

import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./../uop/ops.bend as O
import ./../uop/fold.bend as F
import ./../tensor.bend as T
import ./dtype.bend as D
import ./op.bend as MO
import ./elementwise.bend as E
import ./movement.bend as MX
import ./creation.bend as CR

# ===========================================================================
# THE BORROWED BLOCK -- `mixin/op.py:166 arange` and `mixin/op.py:731 cat`, plus the
# two specialisations of `movement.py:128` and `op.py:74` they need. NONE OF THESE IS
# MINE. Every def is `op_`-prefixed, every def's comment names the file and line it belongs
# to, and the whole block deletes itself the moment `mixin/op.bend` grows
# `mo_arange`/`mo_cat` and `mixin/movement.bend` grows `mxw_bcast`. It is here because a
# file with no buildable callee has no gate, and the gate is the only evidence this port
# has. IT IS GATED (`arange3`, `arange5`), so it is a MEASURED implementation and not a
# restatement of the code that calls it.
# ===========================================================================

# `self.shape[-len(k_):]`, which is the WHOLE shape for the 1-D `k_ = (k,)` that
# `_cumalu` passes, and `mxw_dims_of` is `movement.bend`'s own merge point (the arg for a
# movement node, the fold for anything else) so the dim read here is the fold's answer and
# not a re-derivation. IT IS A PARAMETER AND NOT A CALL AT EVERY CALL SITE, because
# `mxw_dims_of` runs a whole Kahn fold and `op_pool1` needs the source's `i` eleven times.
def op_dim0(+t: T.Tensor) -> U32:
  MX.mxm_nth_u(MX.mxw_dims_of(T.Tensor.ar(t), T.Tensor.u(t)), 0)

# `_broadcast_to` (movement.py:128-147) for the ONE shape transition `_pool` needs: a 1-D
# source whose only axis is 1, expanded to `[r]`. `repeat`'s `expand` (movement.py:594)
# only ever inserts the new axis on the LEFT of an `unsqueezed_shape` that already has the
# source's axis, so `new_shape[:n_left]` is EMPTY, `expand_at = [0]`, `kept = []`,
# `squeezed = self.reshape(())` -- a 0-dim RESHAPE, not `self` -- and `perm = (0,) + (0 +
# 0,) = (0,)` = `range(ndim)`, which movement.py:231 FOLDS, so there is no PERMUTE node.
# That fold is why this is one line and not seven. `_mop(Ops.EXPAND, arg=new_shape[:0] +
# (new_shape[0],))` is `creation.bend`'s `cr_expand`, which carries the same `tn_mop`
# identity test, and it is CALLED.
# TODO(p3) mixin/movement.py:128  `_broadcast_to` for a source that is not
#   `(_, ) -> (r, )`: the general `expand_at` / `kept` / `perm` walks and the `squeeze` that
#   precedes the EXPAND. `creation.bend`'s W4 is the same wall from the other side.
def op_expand_lead(+t: T.Tensor, r: U32) -> T.Tensor:
  CR.cr_expand(MX.mxw_reshape(t, []), [r])

# `repeat` (movement.py:576-594) for `repeats = (r,)` on a 1-D source: `base_shape` is the
# source shape, `r == 1` is False at every call site `_pool` makes, so `unsqueezed_shape =
# [1, i]`, `expanded_shape = [r, i]`, `final_shape = [r * i]`, and
# `self.reshape(unsqueezed_shape).expand(expanded_shape).reshape(final_shape)` is three
# movements. The `r == 1` arm is NOT written and `mxw_reshape`'s identity test would not
# have made it a fold: `[1, i]` against a 1-D `[i]` is a RESHAPE, so the arm is a DIFFERENT
# GRAPH. `op_repeat1` is therefore correct only for `r != 1`, and `_pool` never asks for 1
# (`ceildiv(k * (i*f + 1), i) >= 1` for every `k >= 1`).
# `_pool`'s TWO NUMBERS ARE A RECORD AND NOT TWO PARAMETERS, and that is device.bend's
# rule 3: `_pool` reads `i` and `k` four times each across the `ceildiv`s, `smax` and the
# two `U32.mul`s, a `U32` cannot be read twice in one expression and cannot carry `+` as a
# parameter, and a `Data` record can. `PK` is `mixin/movement.bend`'s `Marg` shape (its
# rule 1, "a pair is a `Type`, so a two-field `Data` record is the spelling of `(A, B)`")
# and it is used here for arithmetic rather than for a margin.
type PK is Data:
  PK{i: U32, k: U32}

def PK.i(q: PK) -> U32:
  match q:
    case PK{i, k}: i

def PK.k(q: PK) -> U32:
  match q:
    case PK{i, k}: k

# ONE SCALAR READ MANY TIMES IS THE SAME TRICK, and it is the shape every `U32` that feeds
# two or three defs in one expression needs. `+U1{v}` is not spellable as a parameter
# annotation on a `U32` ("`+` IS REFUSED ON A `U32`", the `nn/optim.bend` unit's rule 1),
# so the value travels in a `Data` record and is READ through `U1.v`, which is a def and
# therefore non-consuming -- `mixin/divandmod.bend`'s rule 4 ("`Found.ar` / `Found.i` are
# non-consuming readers") is the same fact and the same fix.
type U1 is Data:
  U1{v: U32}

def U1.v(q: U1) -> U32:
  match q:
    case U1{v}: v

def op_repeat1.rp(+t: T.Tensor, +q: PK) -> T.Tensor: op_expand_lead(MX.mxw_reshape(t, [1, PK.i(q)]), PK.k(q))
def op_repeat1.put(+x: T.Tensor, +q: PK) -> T.Tensor: MX.mxw_reshape(x, [U32.mul(PK.k(q), PK.i(q))])
def op_repeat1(+t: T.Tensor, +q: PK) -> T.Tensor: op_repeat1.put(op_repeat1.rp(t, q), q)

# `mxw_pad` / `mxw_shrink` DIVERGE FROM CPYTHON FOR A ONE-ELEMENT SHAPE ARG, and this
# file cannot use them. MEASURED, CPython: `shape_to_shape_arg` (ops.py:106-110) is
# `return src[0] if len(src) == 1 else UOp(Ops.STACK, src=src)`, so
# `Tensor.empty(5).pad(((2, 0),))` is `ALLOC/0 CONST/0(2) CONST/0(7) PAD/3` -- FOUR nodes,
# and the two shape args are BARE CONSTs. `mxw_stk` (movement.bend:1442) is `G.mstack`,
# which is UNCONDITIONALLY a STACK, and `movement.bend`'s own header says so ("THE BARE-CONST
# CASE IS A DIFFERENT NODE and that is the row `mxm_reshape1`").
# IT BITES THIS FILE EVERYWHERE ON THE `arange` PATH: `_cumalu`'s pad is `((shape-1, 0),)`
# (op.py:754) and `_pool`'s first shrink is `(0, k*(i*f+1))` (movement.py:610), so BOTH of
# `_pool`'s first two shape args are one-element and `mxw_pad`/`mxw_shrink` would add a
# STACK to each -- six extra nodes on `arange3` and one on every other row.
# `movement.bend` is READ-ONLY to this unit, so the two defs below are a LOCAL copy that
# calls `T.tn_mop` with `T.APairs`, and `tn_mop.pairs` is `tn_shape_arg` TWICE -- which is
# where the fold lives. REPORTED, not fixed in place. The identity test is
# `movement.py:185`'s `ret.shape == self.shape` and it is the same `mxw_same`.
# TODO(delete) both when `mxw_stk` grows `tn_shape_arg`'s one-element arm.
def op_mop.of(same: Bool, +t: T.Tensor, +made: T.Tensor) -> T.Tensor:
  Bool.pick(T.Tensor, same, t, made)

def op_mop.of2(+t: T.Tensor, +f: O.Found) -> T.Tensor:
  op_mop.of(MX.mxw_same(O.Found.ar(f), O.Found.i(f), T.Tensor.u(t)), t, T.tn_alu.put(f))

def op_mop.put2(op: O.Op, +t: T.Tensor, lo: List<&2, O.Const>, hi: List<&2, O.Const>) -> T.Tensor:
  op_mop.of2(t, T.tn_mop(T.Tensor.ar(t), T.Tensor.u(t), op, T.APairs{lo, hi}))

def op_mop(op: O.Op, +t: T.Tensor, lo: List<&2, U32>, hi: List<&2, U32>) -> T.Tensor:
  op_mop.put2(op, t, CR.cr_cdims(lo), CR.cr_cdims(hi))

def op_pad(+t: T.Tensor, lo: List<&2, U32>, hi: List<&2, U32>) -> T.Tensor:
  op_mop(O.OpsPAD{}, t, lo, hi)

def op_shr(+t: T.Tensor, lo: List<&2, U32>, hi: List<&2, U32>) -> T.Tensor:
  op_mop(O.OpsSHRINK{}, t, lo, hi)

# `MovementMixin.pad` (movement.py:186) as `_pad_constant` (op.py:282) reaches it:
# `_shape` is `tuple((x[0], s + x[0] + x[1]) if x is not None else (0, s) for x, s in
# zip(arg, self.shape))` and the SIZE half is `pA + s`, so the caller passes `pA + s` and
# the node's marg is `(pB, pB + pA + s)`. `_cumalu`'s pad is `((shape-1, 0),)` (op.py:754)
# so `pA = 0`, `pB = i - 1` and `s = i`, and the node's marg is `((i-1, 2i-1),)` -- CPython
# prints `((2, 5),)` for `arange(3, dtype=dtypes.uint32)`, which `arange3`'s toposort pins.
# Both numbers come out of `PK` because the pad's offsets are `(k-1, 0)` and the axis is `i`.
# TODO(p3) mixin/op.py:282  `_pad_constant`'s negative-pad arm (`has_neg`, op.py:284) and
#   its `value != 0` arm, which is `MovementMixin.pad(X.const_like(True, bool), pads)
#   .where(base, value)` (op.py:290) and needs `identity_element` (ops.py:61).
def op_padc(+t: T.Tensor, +q: PK) -> T.Tensor: op_pad(t, [U32.sub(PK.k(q), 1)], [PK.i(q)])

# `_pool` (movement.py:598-616) for `k_ = (k,)`, `stride = 1`, `dilation = 1` on a 1-D
# source, which is the only call `_cumalu` makes (op.py:755). The twelve lines of shape
# arithmetic reduce to TWO numbers, `o` and `f`:
#
#   o_ = [ceildiv(i - d*(k-1), s)]                          movement.py:604  -> o
#   f_ = [smax(1, ceildiv(o*s - d, i))]                     movement.py:606  -> f
#   x  = self.repeat([ceildiv(k*(i*f+d), i)])               movement.py:608
#   x  = x.shrink_to([k*(i*f+d)])                           movement.py:610
#   x  = x.reshape([k, (i*f+d)])                            movement.py:611
#   x  = x.shrink_to([k, o]).reshape([k, o, s])             movement.py:613
#   x  = x.shrink_to([k, o, s]).reshape([k, o])             movement.py:614
#   return x.permute(1, 0)                                  movement.py:616
#
# and the THIRD `shrink_to` is a NO-OP -- the axis already has size 1, and `shrink`
# (movement.py:192) returns `self` when the arg equals the current boundary -- so it is a
# bare `mxw_reshape`. That is visible in CPython's own toposort, which has FIVE RESHAPEs
# and THREE SHRINKs for `arange(3, dtype=dtypes.uint32)` and not six and four, and M6 is
# the mutation that adds the fourth SHRINK back.
def op_pool1.o(+q: PK) -> U32: U32.add(U32.sub(PK.i(q), PK.k(q)), 1)
def op_pool1.f(+q: PK) -> U32: U32.max(1, H.ceildiv_u32(U32.sub(op_pool1.o(q), 1), PK.i(q)))
def op_pool1.sz(+q: PK) -> U32: U32.mul(PK.k(q), U32.add(U32.mul(PK.i(q), op_pool1.f(q)), 1))
def op_pool1.kk(+q: PK) -> U32: H.ceildiv_u32(U32.mul(PK.k(q), U32.add(U32.mul(PK.i(q), op_pool1.f(q)), 1)), PK.i(q))
def op_pool1.rp(+t: T.Tensor, +q: PK) -> T.Tensor: op_repeat1(t, PK{PK.i(q), op_pool1.kk(q)})
def op_pool1.sh(+t: T.Tensor, +q: PK) -> T.Tensor:
  MX.mxw_reshape(op_shr(op_pool1.rp(t, q), [0], [op_pool1.sz(q)]), [PK.k(q), op_pool1.sz(q)])
def op_pool1.p3(+t: T.Tensor, +q: PK) -> T.Tensor:
  MX.mxw_reshape(op_shr(op_pool1.sh(t, q), [0, 0], [PK.k(q), op_pool1.o(q)]), [PK.k(q), op_pool1.o(q), 1])
def op_pool1.p4(+t: T.Tensor, +q: PK) -> T.Tensor:
  MX.mxw_reshape(op_shr(op_pool1.p3(t, q), [0, 0, 0], [PK.k(q), op_pool1.o(q), 1]), [PK.k(q), op_pool1.o(q)])
def op_pool1(+t: T.Tensor, +q: PK) -> T.Tensor: MX.mxw_permute(op_pool1.p4(t, q), [1, 0])

# `_cumalu` (op.py:752-756) for `axis = 0` and `op = Ops.ADD` on a 1-D source, which is
# what `arange` (op.py:195) asks for:
#
#   pads   = (None,)*(ndim-1) + ((shape[axis]-1, 0),)            op.py:754
#   pooled = self.transpose(0,-1)._pad_constant(pads, id)._pool((shape[axis],))
#   return pooled.sum(-1).transpose(0, -1)
#
# `transpose(0, -1)` on a 1-D tensor is `permute([0])` and movement.py:231 folds the
# identity order, so BOTH transposes are `self` and neither is a node. `identity_element
# (Ops.ADD, dt)` is `0` (ops.py:61) and `_pad_constant`'s `if value == 0: return base`
# (op.py:288) fires. The `sum`'s axis is `ndim - 1 = 1` on `_pool`'s TWO-dimensional result
# and it is written as the literal `[1]` rather than as `MO.mo_ax`, because `mo_ax` takes
# the tensor and would rebuild the whole of `_pool`: movement.bend's rule 13 says calling a
# building function twice is CORRECT (the arena is a hash-cons) and it is also a second
# copy of every node in `_pool`, so the literal is the cheap correct spelling.
# TODO(p3) mixin/op.py:752  `_cumalu` for `axis != 0`, for `Ops.MAX`/`Ops.MUL`, and for a
#   source with `ndim > 1`.
def op_cumalu.red(+p: T.Tensor) -> T.Tensor: MO.mo_sum(False{}, p, [1])
def op_cumalu(+t: T.Tensor, +q: PK) -> T.Tensor: op_cumalu.red(op_pool1(op_padc(t, q), q))

# `arange` (op.py:166-195) for `stop is None`, `step = 1`, `dtype` GIVEN and
# `output_len > 0`, which is the shape of `random_bits`'s one call: `cls.arange(
# ceildiv(chunk_num, 2), dtype=dtypes.uint32)` (rand.py:26). In that arm `lo, hi = (0,
# stop - 1)`, `output_len = ceildiv(stop - start, step) = stop`, `acc_dtype =
# least_upper_dtype(dt, float32) if is_float(dt) else dt = dt`, and
#
#   (cls.full((output_len,), step, dtype=acc_dtype, buffer=False)._cumalu(0, Ops.ADD)
#    + (start - step)).cast(dtype)
#
# is `full((n,), 1, uint32, buffer=False)` -- a CONST CAST to uint32 then an EXPAND, no
# ALLOC, no STORE and no AFTER -- cumulated, plus the Python int `-1` (a weakint CONST),
# cast back to `uint32`. THAT LAST CAST IS A FOLD and dropping it leaves the same node
# count, the same root op and the same src-op sequence, so `arange3_t` (the dtype-only row)
# is what pins it and the count row cannot.
# The `OverflowError` guard (op.py:191) and the `output_len <= 0` early `full((0,), 0)`
# (op.py:193) are a REFUSAL and a RETURN of a different graph, so they are `TODO(p3)`.
# TODO(p3) mixin/op.py:191  `arange`'s `OverflowError` guard.
# TODO(p3) mixin/op.py:193  `arange`'s `output_len <= 0` arm -- `full((0,), 0)`.
# TODO(p3) mixin/op.py:187  `arange` with `stop` given, `step != 1`, or `dtype=None` (which
#   needs `commit_int(lo, hi)` from `mixin/dtype.bend`).
def op_arange.add(+x: T.Tensor) -> T.Tensor: MO.mo_bin_c(x, O.OpsADD{}, MO.mo_ki(4294967295))
def op_arange.cast(+x: T.Tensor) -> T.Tensor: MO.mo_cast_t(x, S.uint32())
def op_arange.full(+ar: O.Arena, q: U1, +dev: S.Dev) -> T.Tensor:
  CR.cr_full(False{}, ar, MO.mo_ki(1), S.uint32(), [U1.v(q)], dev)
def op_arange.put(+ar: O.Arena, +full: T.Tensor, +q: U1) -> T.Tensor:
  op_arange.cast(op_arange.add(op_cumalu(full, PK{U1.v(q), U1.v(q)})))
def op_arange(+ar: O.Arena, n: U32, +dev: S.Dev) -> T.Tensor:
  +q: U1 = U1{n}
  op_arange.put(ar, op_arange.full(ar, q, dev), q)

# `_mop(Ops.STACK, arg=tensors[1:])` (ops.py:831-834) for one-dimensional operands, which
# is `stack`'s `arg=tuple(t._uop for t in tensors[1:])` (movement.py:271) and NOT a shape
# arg: `srcs = (self,) + tuple(arg)`, so the node has `1 + len(arg)` srcs. The
# `dtype_from_uop` and `ccast` of ops.py:833-834 are `tensor.bend`'s own `TODO(p3)` and are
# NOT PORTED, because both operands of every `stack` this file builds already share a dtype
# -- a uint32 and a uint32 in `_threefry_random_bits`, a uint32 and a uint32 in `low.cat
# (high)` -- so the `ccast` is the identity and omitting it drops no node. `stack`'s
# `.permute(tuple(range(1, dim+1)) + (0,) + tuple(range(dim+1, ret.ndim)))` with `dim = 0`
# is `permute((0,))`, which movement.py:231 folds, so there is no PERMUTE.
# TODO(p3) mixin/uop/ops.py:833  `dtype_from_uop` + `ccast` in `_mop`'s STACK arm.
def op_stack0(+ar: O.Arena, u: U32, +us: List<&2, U32>) -> T.Tensor:
  T.tn_alu.put(O.UOp.new(ar, O.OpsSTACK{}, List.append(&2, U32, [u], us), O.ANone{}, O.TNone{}))

# `cat`'s all-equal-shapes arm (op.py:748), `dim = 0`, TWO operands, which is `self.stack
# (*args, dim=0).flatten(0, 1)`: `stack` gives `(2, n)` and `flatten(0, 1)` is
# `self.reshape(self.shape[:0] + (prod(self.shape[0:2]),) + self.shape[2:])`
# (movement.py:359) = `reshape([2 * n])`. THE NODE IS BUILT IN `y`'s ARENA and the caller
# passes the tensor that was made LAST, because a node belongs in the arena as it stood
# after the last node built before it and an arena one node short overwrites its operand.
def op_cat1(+x: T.Tensor, +y: T.Tensor) -> T.Tensor:
  MX.mxw_reshape(op_stack0(T.Tensor.ar(y), T.Tensor.u(x), [T.Tensor.u(y)]), [U32.mul(2, op_dim0(x))])

# `counter[0:1]` and `counter[1:2]` -- `op.py:74 _getitem`'s SLICE arm on a 1-D source,
# which is `mxw_shrink(counter, [k], [1])`. MEASURED on `Tensor.rand(2,3)`: nodes 43 and 45
# are `SHRINK/3` with marg `((0, 1),)` and `((1, 1),)`, and `counter[0]` is a `RESHAPE` of
# `counter[0:1]` to `()` (node 62), so a scalar read is the SLICE and then the RESHAPE, not
# a different walk.
def rd_slice(+t: T.Tensor, k: U32) -> T.Tensor: MX.mxw_shrink(t, [k], [1])
def rd_scalar.put(+t: T.Tensor, n: U32) -> T.Tensor: MX.mxw_reshape(rd_slice(t, n), [])
def rd_scalar(+t: T.Tensor, k: U32) -> T.Tensor: rd_scalar.put(t, k)

# `src[0]` / `key[1]` / `src[i]` -- `op.py:74 _getitem`'s INT arm on axis 0, general in
# `ndim`: `SHRINK(t, [k] ++ [0]*(n-1), [1] ++ tail(ds))` then `RESHAPE(..., tail(ds))`.
# `rd_take.scalar` is the 0-dim form (`tail([])` is empty), which is what
# `_threefry_random_bits`'s `key[0]` and `key[1]` need.
# `rd_take.scalar` IS DECLARED AFTER `rd_take` and both are after the two list walks,
# because a def may only call a def declared ABOVE it and the walk is the leaf.
def rd_zeros.go(n: Nat, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+p: rd_zeros.go(p, List.append(&2, U32, acc, [0]))

def rd_zeros(n: Nat) -> List<&2, U32>: rd_zeros.go(n, Nil{})

def rd_tail.go(+ds: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match ds:
    case Nil{}: acc
    case d <> t: rd_tail.go(t, List.append(&2, U32, acc, [d]))

def rd_tail(+ds: List<&2, U32>) -> List<&2, U32>: rd_tail.go(ds, Nil{})

def rd_nd(+t: T.Tensor) -> U32: MX.mxm_len_u32(MX.mxw_dims_of(T.Tensor.ar(t), T.Tensor.u(t)))
def rd_take.lead(k: U32, n: U32) -> List<&2, U32>: List.append(&2, U32, [k], rd_zeros(U32.to_nat(U32.sub(n, 1))))
def rd_take.sz(q: U1, +ds: List<&2, U32>) -> List<&2, U32>: List.append(&2, U32, [1], rd_tail(ds))
def rd_take.of(+t: T.Tensor, +q: U1, +ds: List<&2, U32>) -> T.Tensor:
  MX.mxw_reshape(MX.mxw_shrink(t, rd_take.lead(U1.v(q), MX.mxm_len_u32(ds)), rd_take.sz(q, ds)), rd_tail(ds))

def rd_take(+t: T.Tensor, n: U32) -> T.Tensor:
  rd_take.of(t, U1{n}, MX.mxw_dims_of(T.Tensor.ar(t), T.Tensor.u(t)))

def rd_take.scalar(+t: T.Tensor, n: U32) -> T.Tensor: MX.mxw_reshape(rd_take.of(t, U1{n}, [0]), [])

# ===========================================================================
# rand.py:12 `_threefry_random_bits`. THE WHOLE OF THE RANDOMNESS, and it is seven
# elementwise nodes and a `cat`.
#   x = (counts1.cast(uint64) << 32) | counts0.cast(uint64)           rand.py:13
#   x = x.threefry((key[1].cast(uint64) << 32) | key[0].cast(uint64)) rand.py:14
#   return x.cast(uint32).cat((x >> 32).cast(uint32))                 rand.py:15
# The `<<` is `lshift` (elementwise.py:344) and the `>>` is `__rshift__` (elementwise.py
# :369) = `rshift` (:355); both are `MO.mo_bin_c`, which is op.bend's spelling of `_binop`
# for a CONST operand and is what `mo_neg` and `mo_sub` use too. THE `x` VARIABLE IS READ
# TWICE after the first line (`>> 32` and the `cat`'s two halves), so it is two defs and
# not a `let`: a `let` is affine and a rebound name is a shadow, and the three nodes it
# names have to be interned in Python's order.
# `rd_p64`'s ARGS ARE (`hi`, `lo`) AND NOT (`lo`, `hi`) because Python writes
# `(counts1.cast(...) << 32) | counts0.cast(...)`: the SHIFTED term is `src[0]`. Getting
# that backwards is graph-isomorphic on two CONSTs and invisible to every count row, which
# is why `tfb3` prints the toposort and not a set of op names.
# ===========================================================================
def rd_c64(+t: T.Tensor) -> T.Tensor: MO.mo_cast_t(t, S.uint64())
def rd_c32(+t: T.Tensor) -> T.Tensor: MO.mo_cast_t(t, S.uint32())
def rd_shl32(+t: T.Tensor) -> T.Tensor: MO.mo_bin_c(t, O.OpsSHL{}, MO.mo_ki(32))
def rd_shr32(+t: T.Tensor) -> T.Tensor: MO.mo_bin_c(t, O.OpsSHR{}, MO.mo_ki(32))
def rd_p64(+hi: T.Tensor, +lo: T.Tensor) -> T.Tensor: MO.mo_bin(rd_shl32(rd_c64(hi)), O.OpsOR{}, rd_c64(lo))
def rd_tfb.x(+c0: T.Tensor, +c1: T.Tensor) -> T.Tensor: rd_p64(c1, c0)
def rd_tfb.three(+x: T.Tensor, +key: T.Tensor) -> T.Tensor:
  E.ew_threefry(x, E.ETen{rd_p64(rd_take.scalar(key, 1), rd_take.scalar(key, 0))})
def rd_tfb.cat(+x: T.Tensor) -> T.Tensor: op_cat1(rd_c32(x), rd_c32(rd_shr32(x)))
def rd_tfb(+ar: O.Arena, +key: T.Tensor, +c0: T.Tensor, +c1: T.Tensor) -> T.Tensor:
  rd_tfb.cat(rd_tfb.three(rd_tfb.x(c0, c1), key))

# ===========================================================================
# rand.py:18 `random_bits`. The loop is `for i in range(0, num, dtypes.uint32.max)`
# (rand.py:21) and `dtypes.uint32.max` is 4294967295, so for any `num` a real shape
# produces -- `num = ceildiv(prod(shape) * itemsize, 4)`, so 17 GiB of random bits to reach
# the second iteration -- the loop has exactly ONE iteration with `i = 0`. That is the arm
# below and it is the whole of the function for every gate row.
#   c_low  = low + (i & 0xffffffff)                             rand.py:23
#   c_high = high + (i >> 32) + (c_low < low)                   rand.py:24
#   counts0 = arange(ceildiv(chunk_num, 2), uint32)             rand.py:26
#   counts1 = counts0 + ceildiv(chunk_num, 2)                   rand.py:27
#   bits.append(_threefry_random_bits(new_key, counts0, counts1)[:chunk_num])
#   return bits[0].cat(*bits[1:]) if bits else counter[0:0]     rand.py:29
# `i = 0`, so `(i & 0xffffffff)` is the Python int `0` and `(i >> 32)` is `0`: the two terms
# are CONSTANT ZERO ADDS and they ARE BUILT, not folded -- nodes 72 and 70 of
# `Tensor.rand(2,3)`. `bits[0].cat()` with an EMPTY `bits[1:]` is `cat()` with no operands,
# and that is `self.stack(dim=0)` with `arg = ()` -- ops.py:832's `srcs = (self,) + ()` --
# so it is a ONE-SRC STACK followed by `flatten(0, 1)`, which for a 1-D source is a real
# RESHAPE from `(1, n)` to `(n,)`. That is nodes 110/111: `STACK/1` and `RESHAPE/2` with
# marg `(6,)`. `rd_bits.flat` is that product, and writing it as the SOURCE's length would
# be a fold and would drop the node.
# The `[:chunk_num]` slice is a full slice of a tensor of exactly that length and it builds
# NOTHING (node 108 is the `cat`'s STACK and node 109 is `flatten`'s RESHAPE, with no SHRINK
# between them), which is a property of `__getitem__` and not of this file, so it is folded
# here and `bits6`'s node count is the row that pins it.
# TODO(p3) mixin/rand.py:21  `random_bits`'s SECOND AND LATER CHUNKS -- `i & 0xffffffff`
#   and `i >> 32` on a counter past 2^32. `H.i64_of_i32` sign-EXTENDS, so `i` cannot be a
#   `U32` past 2^31, and the multi-chunk arm needs `H.I64` arithmetic that
#   `bend2-constraints`' "A 64-BIT PRODUCT IS A WALL" section says is absent (`i64_mul`,
#   `i64_div`, `i64_mod` do not exist). 17 GiB of random bits to reach it.
# ===========================================================================
def rd_bits_num(+ds: List<&2, U32>, +dt: S.Dt) -> U32: H.ceildiv_u32(U32.mul(H.prod_u32(ds), S.Dt.itemsize(dt)), 4)
def rd_bits_half(n: U32) -> U32: H.ceildiv_u32(n, 2)
def rd_bits.half(n: U32) -> U32: rd_bits_half(n)
def rd_bits.clow(+ctr: T.Tensor) -> T.Tensor: MO.mo_bin_c(rd_slice(ctr, 0), O.OpsADD{}, MO.mo_ki(0))
def rd_bits.chigh(+ctr: T.Tensor) -> T.Tensor:
  MO.mo_bin(MO.mo_bin_c(rd_slice(ctr, 1), O.OpsADD{}, MO.mo_ki(0)), O.OpsADD{},
    MO.mo_cast_t(MO.mo_bin(rd_bits.clow(ctr), O.OpsCMPLT{}, rd_slice(ctr, 0)), S.uint32()))
def rd_bits.key(+ar: O.Arena, +key: T.Tensor, +ctr: T.Tensor) -> T.Tensor:
  rd_tfb(ar, key, rd_bits.clow(ctr), rd_bits.chigh(ctr))
def rd_bits.c0(+ar: O.Arena, q: U1, +dev: S.Dev) -> T.Tensor: op_arange(ar, rd_bits_half(U1.v(q)), dev)
def rd_bits.c1.put(+ar: O.Arena, +c0: T.Tensor, q: U1) -> T.Tensor:
  MO.mo_bin_c(c0, O.OpsADD{}, MO.mo_ki(rd_bits_half(U1.v(q))))
def rd_bits.c1(+ar: O.Arena, +q: U1, +dev: S.Dev) -> T.Tensor:
  rd_bits.c1.put(ar, rd_bits.c0(ar, q, dev), q)
def rd_bits.tfb(+ar: O.Arena, +key: T.Tensor, +ctr: T.Tensor, +q: U1, +dev: S.Dev) -> T.Tensor:
  rd_tfb(ar, key, rd_bits.c0(ar, q, dev), rd_bits.c1(ar, q, dev))
def rd_bits.flat(+b: T.Tensor) -> U32:
  U32.mul(MX.mxm_nth_u(MX.mxw_dims_of(T.Tensor.ar(b), T.Tensor.u(b)), 0),
          MX.mxm_nth_u(MX.mxw_dims_of(T.Tensor.ar(b), T.Tensor.u(b)), 1))
def rd_bits.cat(+b: T.Tensor) -> T.Tensor:
  MX.mxw_reshape(op_stack0(T.Tensor.ar(b), T.Tensor.u(b), Nil{}), [rd_bits.flat(b)])
def rd_bits(+ar: O.Arena, +key: T.Tensor, +ctr: T.Tensor, n: U32, +dev: S.Dev) -> T.Tensor:
  rd_bits.cat(rd_bits.tfb(ar, key, ctr, U1{n}, dev))

# ===========================================================================
# rand.py:32 `_bits_to_rand`. `dtypes.finfo(dtype)` (dtype.py:113) is
# `(exponent, mantissa)` and only the mantissa is read, so `rd_nmant` is HALF of a table
# that is P3 in `mixin/dtype.bend` -- the eight-member `{float16: (5, 10), ...}` dict.
# `dtype.itemsize` selects the unsigned partner from `{1: uint8, 2: uint16, 4: uint32,
# 8: uint64}` (rand.py:34) and `rd_one_bits` is `bitcast(1.0, dtype, uint_dtype)`
# (dtype.py:302) -- a PYTHON-LEVEL `struct.pack`/`unpack` of the SCALAR `1.0`, so the
# result is a weakint CONST and not a CAST and not a BITCAST. Its two values this file
# reaches are 0x3f800000 (float32) and 0x3c00 (float16); float64 is a 64-bit CONST and
# `bend2-constraints` says there is no 64-bit integer here, so it is a refusal answered `0`.
# `uint_bits.rshift(bitsize - nmant)` is `mo_bin_c(_, SHR, mo_ki(9))` for float32 and
# `rd_shift` is the `32 - 23`.
# `bits.bitcast(uint_dtype)` FOLDS when the two dtypes agree, which they do for float32
# (`bits` is uint32 and `uint_dtype` is uint32), and `ub` is that test as a PARAMETER
# because `O.eq_dt` is a call. `.bitcast(dtype)` at the end is the ONE real BITCAST and
# `ref_btr_bits` is the row that pins that the FIRST one folded.
# `[:prod(shape)]` is a FULL slice at every call site -- `random_bits` asked for exactly
# `ceildiv(prod(shape)*itemsize, 4)` words, which for a power-of-two itemsize is exactly
# `prod(shape)` -- and it builds nothing, so it is folded.
# `.sub(1)` is elementwise.py:121's `a.alu(Ops.ADD, -b)`, which is a `MUL` by `-1.0` and an
# `ADD` and NOT a `SUB` -- nodes 117..120 of `Tensor.rand(2,3)`. `MO.mo_sub` is op.bend's
# spelling of that and is CALLED, and it takes a `Tensor` operand, so the `1.0` is interned
# by `mo_const_t` in the operand's own arena.
# TODO(p3) tinygrad/dtype.py:113  `finfo` -- the eight-member table; `rd_nmant` answers
#   half and refuses the rest.
# TODO(p3) tinygrad/dtype.py:302  `bitcast(1.0, in_dtype, out_dtype)` for float64 /
#   bfloat16 / the fp8 family: a 64-bit CONST is not expressible in this port.
# ===========================================================================
# THE ARMS ARE ON `dtype.bitsize` AND NOT ON THE EXPONENT. `finfo` returns
# `(exponent, mantissa)` -- `(5, 10)` for half and `(8, 23)` for float32 -- and only the
# SECOND is read, so the switch is on the bit width and 32 is float32. The first version
# keyed on the exponent and answered 0 for float32, which `ref_nmant_f32` and `ref_shift_f32`
# caught and which is the recorded "`case 8:` claims 8, 16, 32" trap arriving through a
# different door: the arms were not misordered, they were the WRONG NUMBER.
def rd_nmant(bits: U32) -> U32:
  match bits:
    case 16: 10
    case 32: 23
    case _: 0

def rd_nmant.of(+dt: S.Dt) -> U32: rd_nmant(S.Dt.bits(dt))

# `{1: uint8, 2: uint16, 4: uint32, 8: uint64}[dtype.itemsize]` (rand.py:34) -- so the
# switch is on the ITEM SIZE and the arms are 1/2/4/8, not on the bit width. The first
# version keyed on `bits` and answered `void` for float32, because `float32.itemsize` is
# 4 and there is no `case 4:`. MEASURED by `ref_uint_dt_f32`.
def rd_uint_dt(sz: U32) -> S.Dt:
  match sz:
    case 1: S.uint8()
    case 2: S.uint16()
    case 4: S.uint32()
    case 8: S.uint64()
    case _: S.void()

def rd_uint_dt.of(+dt: S.Dt) -> S.Dt: rd_uint_dt(S.Dt.itemsize(dt))

def rd_one_bits(bits: U32) -> U32:
  match bits:
    case 16: 15360
    case 32: 1065353216
    case _: 0

def rd_one_bits.of(+dt: S.Dt) -> U32: rd_one_bits(S.Dt.bits(dt))
def rd_shift.put(+dt: S.Dt) -> U32: U32.sub(S.Dt.bits(dt), rd_nmant.of(dt))
def rd_shift(+dt: S.Dt) -> U32: rd_shift.put(dt)

def rd_bitcast(+ar: O.Arena, +t: T.Tensor, +dt: S.Dt) -> T.Tensor:
  E.ew_of(O.UOp.new(ar, O.OpsBITCAST{}, [T.Tensor.u(t)], O.ADt{dt}, O.TNone{}))

def rd_btr.ub(ub: Bool, +ar: O.Arena, +b: T.Tensor, +udt: S.Dt) -> T.Tensor:
  Bool.pick(T.Tensor, ub, rd_bitcast(ar, b, udt), b)

def rd_btr.rshift(+t: T.Tensor, +dt: S.Dt) -> T.Tensor: MO.mo_bin_c(t, O.OpsSHR{}, MO.mo_ki(rd_shift(dt)))
def rd_btr.orf(+t: T.Tensor, +dt: S.Dt) -> T.Tensor: MO.mo_bin_c(t, O.OpsOR{}, MO.mo_ki(rd_one_bits.of(dt)))
def rd_btr.sub(+t: T.Tensor) -> T.Tensor: MO.mo_sub(t, MO.mo_const_t(t, O.CFloat{1.0}))
def rd_btr.fc(+t: T.Tensor, +dt: S.Dt) -> T.Tensor: rd_bitcast(T.Tensor.ar(t), t, dt)
def rd_btr.of(ub: Bool, +ar: O.Arena, +b: T.Tensor, +ds: List<&2, U32>, +dt: S.Dt, +udt: S.Dt) -> T.Tensor:
  MX.mxw_reshape(rd_btr.sub(rd_btr.fc(rd_btr.orf(rd_btr.rshift(rd_btr.ub(ub, ar, b, udt), dt), dt), dt)), ds)

def rd_btr(ub: Bool, +ar: O.Arena, +b: T.Tensor, +ds: List<&2, U32>, +dt: S.Dt) -> T.Tensor:
  rd_btr.of(ub, ar, b, ds, dt, rd_uint_dt.of(dt))

# `UOp.clone` (ops.py:882) -- `ret = self.empty_like(device=device); return ret.after(ret.store
# (src.cast(ret.dtype)))`. `empty_like` (ops.py:864) on a source with no buffer identity is
# `UOp.empty(self.shape, self.dtype, device=device)`, which is `creation.bend`'s
# `cr_empty_like` with the dtype GIVEN (`src.cast(ret.dtype)` is the identity for
# `_bits_to_rand`'s output, whose dtype IS `dt`), and `after`/`store` are `creation.bend`'s
# `cr_after`. So `rd_clone` is TWO CALLS and no new node logic, and the STORE/AFTER pair is
# the tail of every `contiguous=True` graph in this file.
def rd_clone(+t: T.Tensor, +ds: List<&2, U32>, +dt: S.Dt, +dev: S.Dev) -> T.Tensor:
  CR.cr_after(CR.cr_empty_like(T.Tensor.ar(t), True{}, dt, dt, None{}, None{}, ds, dev), t)

# `dtypes.is_float(dt) and dt not in dtypes.weaks` -- rand.py:63's guard, asked as
# CPython's own predicate so the `ref_*` rows are shared rows and not bend-only ones.
def rd_ok_float(+dt: S.Dt) -> Bool: Bool.and(S.Dt.is_float(dt), Bool.not(D.md_weak(dt)))
# `all_int(shape)` and `all(s >= 0 for s in shape)` -- rand.py:64 and :171. `all_int` is
# helpers.py:16 and every shape this port builds is a `List<&2, U32>`, so the `all_int`
# half is VACUOUS and `ref_shape_u32` is the row that says so.
def rd_ok_shape.go(+ds: List<&2, U32>, sofar: Bool) -> Bool:
  match ds:
    case Nil{}: sofar
    case d <> t: rd_ok_shape.go(t, Bool.and(sofar, U32.is_ge(d, 0)))

def rd_ok_shape(+ds: List<&2, U32>) -> Bool: rd_ok_shape.go(ds, True{})
# `low < high` -- rand.py:137 and :172.
def rd_lt(lo: F32, hi: F32) -> Bool: F32.is_lt(lo, hi)
# `std < 0` -- rand.py:154.
def rd_std_ok(std: F32) -> Bool: F32.is_lt(F32.neg(0.0), std)
# `0 <= p <= 1` -- rand.py:293. It is a `Bool.and` of two comparisons and NOT a chain,
# because the chained form reads `p` twice in one expression and an `F32` has no `+`.
def rd_p_ok.put(p: F32) -> Bool: F32.is_ge(p, 0.0)
def rd_p_ok(+p: F32) -> Bool: Bool.and(rd_p_ok.put(p), F32.is_le(p, 1.0))
# `1 <= self.ndim <= 2 and num_samples > 0` -- rand.py:266.
def rd_multi_n.put(+q: U1) -> Bool: U32.is_le(1, U1.v(q))
def rd_multi_n.put2(+q: U1) -> Bool: U32.is_le(U1.v(q), 2)
def rd_multi_n(nd: U32, ns: U32) -> Bool:
  +q: U1 = U1{nd}
  Bool.and(rd_multi_n.put(q), Bool.and(rd_multi_n.put2(q), U32.is_lt(0, ns)))
# `dtypes.is_int(dtype)` -- rand.py:136.
def rd_ok_int(+dt: S.Dt) -> Bool: S.Dt.is_int(dt)

# `_rand` (rand.py:40-43) -- `bits = cls.random_bits(key, counter, ceildiv(prod(shape) *
# dtype.itemsize, 4))`, `out = cls._bits_to_rand(bits, shape, dtype)`, `return out.clone()
# if contiguous else out`. `contig` IS A PARAMETER because `out.clone() if contiguous else
# out` is a choice and a `match` may not scrutinise a call -- and `Bool.pick` is the shape
# that keeps it a choice, because a `Bool.pick` over two BUILDING arms evaluates both.
def rd_rand.of(contig: Bool, +out: T.Tensor, +ds: List<&2, U32>, +dt: S.Dt, +dev: S.Dev) -> T.Tensor:
  match contig:
    case True{}: rd_clone(out, ds, dt, dev)
    case _: out

def rd_rand(contig: Bool, +ar: O.Arena, +key: T.Tensor, +ctr: T.Tensor, +ds: List<&2, U32>, +dt: S.Dt, +dev: S.Dev) -> T.Tensor:
  rd_rand.of(contig, rd_btr(False{}, ar, rd_bits(ar, key, ctr, rd_bits_num(ds, dt), dev), ds, dt), ds, dt, dev)

# ===========================================================================
# rand.py:46 `_next_counter` -- the arithmetic is the WHOLE of it once the device write is
# gone, and it is ported over an INJECTED counter tensor. See the header.
# `U32` cannot be read twice in one expression, so the five lines are six defs and
# `rd_next.nlo` is read twice (once for the compare, once for nothing -- Python's `new_high`
# reads `new_low` and `low` separately) while `ctr` is read in three of them. The
# `CAST(bool -> uint32)` of each `CMPLT` IS A NODE: nodes 49/50 and 63/64 of
# `Tensor.rand(2,3)`, and dropping either is a two-node change every `nsrc` and `op` row
# cannot see.
# `rd_next.cat` is `low.cat(high)`, which is `op_cat1` and therefore a STACK over
# `low.cat(high)`'s two operands in `high`'s arena.
# TODO(p3) tinygrad/tensor.py:468  `counter.assign(...)` -- the device write. It needs
#   `Tensor.assign` (tensor.py:236) in full, whose other eight arms want a `Buffer`,
#   `has_buffer_identity`, `is_realized` and `UOp.clone`; `mixin/tensor.bend` records it
#   as its own `TODO(p3)`.
# ===========================================================================
def rd_mask(n: U32) -> U32: n
def rd_hi32(n: U32) -> U32: U32.shrn(n, 32n)
def rd_next.nlo(+q: U1, +ctr: T.Tensor) -> T.Tensor:
  MO.mo_bin_c(rd_slice(ctr, 0), O.OpsADD{}, MO.mo_ki(rd_mask(U1.v(q))))
def rd_next.cmp(+q: U1, +ctr: T.Tensor) -> T.Tensor:
  MO.mo_cast_t(MO.mo_bin(rd_next.nlo(q, ctr), O.OpsCMPLT{}, rd_scalar(ctr, 0)), S.uint32())
def rd_next.hi1(+q: U1, +ctr: T.Tensor) -> T.Tensor:
  MO.mo_bin_c(rd_slice(ctr, 1), O.OpsADD{}, MO.mo_ki(rd_hi32(U1.v(q))))
def rd_next.nhi(+q: U1, +ctr: T.Tensor) -> T.Tensor:
  MO.mo_bin(rd_next.hi1(q, ctr), O.OpsADD{}, rd_next.cmp(q, ctr))
def rd_next.lo(+q: U1, +ctr: T.Tensor) -> T.Tensor:
  MO.mo_sub(rd_slice(ctr, 0), MO.mo_const_t(ctr, MO.mo_ki(rd_mask(U1.v(q)))))
def rd_next.cmp2(+q: U1, +ctr: T.Tensor) -> T.Tensor:
  MO.mo_cast_t(MO.mo_bin(rd_scalar(ctr, 0), O.OpsCMPLT{}, MO.mo_const_t(ctr, MO.mo_ki(rd_mask(U1.v(q))))), S.uint32())
def rd_next.hi2(+q: U1, +ctr: T.Tensor) -> T.Tensor:
  MO.mo_sub(MO.mo_sub(rd_slice(ctr, 1), MO.mo_const_t(ctr, MO.mo_ki(rd_hi32(U1.v(q))))), rd_next.cmp2(q, ctr))
def rd_next.hi(+q: U1, +ctr: T.Tensor) -> T.Tensor: rd_next.hi2(q, ctr)
def rd_next.cat(+x: T.Tensor, +y: T.Tensor) -> T.Tensor: op_cat1(x, y)
def rd_next(+ar: O.Arena, n: U32, +ctr: T.Tensor) -> T.Tensor:
  +q: U1 = U1{n}
  rd_next.cat(rd_next.lo(q, ctr), rd_next.hi(q, ctr))

# ===========================================================================
# rand.py:50 `rand`. `dt = to_dtype(dtype or dtypes.default_float)` (rand.py:62) and the
# `all_int(shape)` / `all(s >= 0)` / `device is a str` guards (rand.py:64-65) are the
# three refusals, and `canonicalize_device` (rand.py:66) is `tinygrad/device.py`, a
# C-effect module, so the device is a PARAMETER -- `creation.bend`'s W1, same argument. The
# one line that is arithmetic is `ceildiv(prod(shape) * dt.itemsize, 4)` (rand.py:67) and it
# is `rd_bits_num` CALLED rather than re-derived, because it is the same expression as
# `random_bits`'s own `ceildiv` (rand.py:26) and getting the two out of step is exactly the
# kind of thing one shared def makes impossible.
# `rand(2,3)` asks for SIX words, and `rand(2,2,3)` -- `randn_like`'s `stack(self)` -- for
# TWELVE, so `randn23`'s counter step is `rd_next(ar, 12, ctr)` and not 6. `st_six` and
# `rand23` are the two halves of that arithmetic and they must agree.
# ===========================================================================
def rd_rand_cls(contig: Bool, +ar: O.Arena, +key: T.Tensor, +ctr: T.Tensor, +ds: List<&2, U32>, +dt: S.Dt, +dev: S.Dev) -> T.Tensor:
  rd_rand(contig, ar, key, ctr, ds, dt, dev)

# rand.py:70 `rand_like` -- `type(self).rand(*self.shape, device=..., dtype=kwargs.pop
# ("dtype", self.dtype), **kwargs)` (rand.py:86), so the shape is `self`'s and the dtype is
# `self.dtype` when none is given. THE DEVICE-TUPLE ARM IS `creation.bend`'s W2.
# TODO(p3) mixin/rand.py:82  `rand_like`'s device-tuple arm -- `_multi_like`, a Python
#   CALLBACK, which `creation.bend` also carries.
def rd_rand_like(contig: Bool, +ar: O.Arena, +key: T.Tensor, +ctr: T.Tensor, +self_dt: S.Dt, +ds: List<&2, U32>, +dev: S.Dev) -> T.Tensor:
  rd_rand_cls(contig, ar, key, ctr, ds, self_dt, dev)

# `cos` (elementwise.py:500) -- `self = self.cast(least_upper_float(self.dtype))` then
# `((math.pi/2) - self.cast(least_upper_dtype(self.dtype, dtypes.float32))).sin().cast
# (self.dtype)`. For a `float32` input all three dtypes are `float32` and all three casts
# FOLD, so the graph is `MUL(x, -1.0)`, `ADD(pi/2, that)`, `SIN` -- nodes 134/135/136 of
# `Tensor.randn(2,3)` -- and `MO.mo_sub(const, x)` gives exactly that order, because
# elementwise.py:123 is `a.alu(Ops.ADD, -b)`.
# TODO(p3) tinygrad/mixin/elementwise.py:500  `cos` for half/bfloat16, where
#   `least_upper_float` and `least_upper_dtype` are NOT the identity and the two folds
#   become CASTs.
def rd_cos(+ar: O.Arena, +t: T.Tensor) -> T.Tensor:
  E.ew_sin(MO.mo_sub(MO.mo_const_t(t, O.CFloat{1.5707963267948966}), t))

# `log` (elementwise.py:830) -- `self.log2() * math.log(2)`. `rd_log` has the same
# `TODO(p3)` as `rd_cos` and for the same reason: it belongs to `mixin/elementwise.bend`.
# TODO(p3) tinygrad/mixin/elementwise.py:830  `log`.
def rd_log(+t: T.Tensor) -> T.Tensor: MO.mo_bin_c(E.ew_log2(t), O.OpsMUL{}, O.CFloat{0.6931471805599453})

# rand.py:88 `randn_like`. `src = self.stack(self).rand_like(**{**kwargs, "dtype":
# dtypes.float32})` (rand.py:101) -- `self.stack(self)` is `stack(self, self, dim=0)`, so
# `arg = (self,)` and `srcs = (self, self)`: a TWO-src STACK over `self`, and the receiver's
# shape gains a LEADING 1. Then `src[0]` and `src[1]` are `rd_take` at `k = 0` and `k = 1`
# on an `ndim + 1` dimensional source, which is why `rd_take` is general in `ndim` and
# `rd_take.scalar` is not. The tail is elementwise.py:103's Box-Muller in RECEIVER-FIRST
# order, and the order is load-bearing because it decides which `MUL` is `src[0]`:
#   src[0].mul(2*math.pi).cos()                       nodes 133/134/135/136
#   (1 - src[1]).log().mul(-2).sqrt()                nodes 141/142/144/146/147
#   .mul(<that>)                                     node 148
#   .cast(dt)                                        the fold at the end
# `2*math.pi` is hoisted into the `MUL`'s CONST rather than multiplied into the tensor, and
# `(1 - src[1])` is `MUL(src[1], -1.0)` then `ADD(1.0, that)`, which is `MO.mo_sub(const, t)`
# again. `.cast(dt)` is a FOLD when `dt` is `self.dtype` -- which is the case for
# `randn(2,3)` -- and a real CAST for `randn(2,3, dtype=half)`, so `randn23` and `randn23h`
# are both rows.
def rd_randn_like.src(+ar: O.Arena, +self: T.Tensor) -> T.Tensor:
  op_stack0(ar, T.Tensor.u(self), [T.Tensor.u(self)])

def rd_randn_like.rndn(+ar: O.Arena, +key: T.Tensor, +ctr: T.Tensor, +src: T.Tensor, +dev: S.Dev) -> T.Tensor:
  rd_rand_like(True{}, ar, key, ctr, S.single(), MX.mxw_dims_of(T.Tensor.ar(src), T.Tensor.u(src)), dev)

def rd_randn_like.rot(+t: T.Tensor) -> T.Tensor: MO.mo_bin_c(t, O.OpsMUL{}, O.CFloat{6.283185307179586})
def rd_randn_like.cos(+ar: O.Arena, +key: T.Tensor, +ctr: T.Tensor, +src: T.Tensor, +dev: S.Dev) -> T.Tensor:
  rd_cos(ar, rd_randn_like.rot(rd_take(src, 0)))
def rd_randn_like.rad(+ar: O.Arena, +src: T.Tensor) -> T.Tensor:
  E.ew_sqrt(MO.mo_bin_c(rd_log(MO.mo_sub(MO.mo_const_t(src, O.CFloat{1.0}), rd_take(src, 1))), O.OpsMUL{}, O.CFloat{F32.neg(2.0)}))
def rd_randn_like.of(+a: T.Tensor, +b: T.Tensor, +dt: S.Dt) -> T.Tensor:
  MO.mo_cast_t(MO.mo_bin(a, O.OpsMUL{}, b), dt)
def rd_randn_like.dt(half: Bool) -> S.Dt: Bool.pick(S.Dt, half, S.half(), S.single())
def rd_randn_like.put(half: Bool, +ar: O.Arena, +key: T.Tensor, +ctr: T.Tensor, +self: T.Tensor, +dev: S.Dev) -> T.Tensor:
  rd_randn_like.of(rd_randn_like.cos(ar, key, ctr, rd_randn_like.src(ar, self), dev),
    rd_randn_like.rad(ar, rd_randn_like.src(ar, self)), rd_randn_like.dt(half))

# `randn_like` -- `src = self.stack(self).rand_like(**{**kwargs, "dtype": float32})`
# (rand.py:101) and then the Box-Muller tail (rand.py:103). `dtype` is `None` at every call
# site this file gates, so `to_dtype(dtype or self.dtype)` (rand.py:100) is `self.dtype`
# and `half` is the ONE `Bool` that says whether it is not.
def rd_randn_like(half: Bool, +ar: O.Arena, +key: T.Tensor, +ctr: T.Tensor, +self: T.Tensor, +dev: S.Dev) -> T.Tensor:
  rd_randn_like.put(half, ar, key, ctr, self, dev)

# rand.py:106 `randn` -- `cls.empty(*shape, **kwargs).randn_like(dtype=dtype)`, and
# `empty`'s dtype is `dtypes.default_float` (creation.py:36), so the receiver's dtype and
# the cast's target agree and `.cast(dt)` is the IDENTITY. `randn23h` is the row where it
# is NOT.
# `randn_like`'s `dt in dtypes.weaks and dtype is None` refusal (rand.py:100) is
# `ref_randn_weak`.
def rd_randn(half: Bool, +ar: O.Arena, +key: T.Tensor, +ctr: T.Tensor, +ds: List<&2, U32>, +dev: S.Dev) -> T.Tensor:
  rd_randn_like(half, ar, key, ctr, CR.cr_empty(ar, Some{S.single()}, ds, dev), dev)

# `uniform` (rand.py:158) -- `((high-low) * cls.rand(*shape, **kwargs)).cast(dtype or
# dtypes.default_float) + low` (rand.py:173). `high - low` is a PYTHON float, so it is one
# `CFloat` CONST and there is no `SUB` node; `rand` gets `dtype = None` and therefore
# `default_float`; and the `.cast` lands BETWEEN the multiply and the add, which is why
# `rd_uniform.mul` and `rd_uniform.add` are two defs and not one with a flag.
def rd_uniform.mul(+ar: O.Arena, +key: T.Tensor, +ctr: T.Tensor, +ds: List<&2, U32>, lo: F32, hi: F32, +dev: S.Dev) -> T.Tensor:
  MO.mo_bin_c(rd_rand_cls(True{}, ar, key, ctr, ds, S.single(), dev), O.OpsMUL{}, O.CFloat{F32.sub(hi, lo)})
def rd_uniform.add(+t: T.Tensor, lo: F32) -> T.Tensor: MO.mo_bin_c(t, O.OpsADD{}, O.CFloat{lo})
def rd_uniform.cast(cast: Bool, +t: T.Tensor, +dt: S.Dt) -> T.Tensor:
  Bool.pick(T.Tensor, cast, MO.mo_cast_t(t, dt), t)
def rd_uniform(cast: Bool, +ar: O.Arena, +key: T.Tensor, +ctr: T.Tensor, +ds: List<&2, U32>, +lo: F32, hi: F32, +dt: S.Dt, +dev: S.Dev) -> T.Tensor:
  rd_uniform.add(rd_uniform.cast(cast, rd_uniform.mul(ar, key, ctr, ds, lo, hi, dev), dt), lo)

# rand.py:122 `randint` -- `cls.uniform(*shape, low=low, high=high, dtype=dtype, **kwargs)`
# (rand.py:138), so it is `uniform` with the `cast` arm ON and `dt = to_dtype(int32)`. The
# `all_int` / `is_int` / `low < high` refusals are rand.py:135-137 and `ref_randint_int`
# asks the `is_int` one.
def rd_randint(+ar: O.Arena, +key: T.Tensor, +ctr: T.Tensor, +ds: List<&2, U32>, lo: F32, hi: F32, +dt: S.Dt, +dev: S.Dev) -> T.Tensor:
  rd_uniform(True{}, ar, key, ctr, ds, lo, hi, dt, dev)

# rand.py:141 `normal` -- `std * cls.randn(*shape, **kwargs) + mean` (rand.py:155). Both
# factors are Python floats, so both are `CFloat` CONSTs, and the order is receiver-first:
# `MUL(randn, std)` then `ADD(that, mean)`.
def rd_normal(+ar: O.Arena, +key: T.Tensor, +ctr: T.Tensor, +ds: List<&2, U32>, mean: F32, std: F32, +dev: S.Dev) -> T.Tensor:
  rd_uniform.add(MO.mo_bin_c(rd_randn(False{}, ar, key, ctr, ds, dev), O.OpsMUL{}, O.CFloat{std}), mean)

# rand.py:176 `scaled_uniform` -- `cls.uniform(*shape, low=-1.0, high=1.0, **kwargs).mul
# (prod(argfix(*shape))**-0.5)` (rand.py:189). The scale is a Python float computed from
# the shape, so it is an `F32` PARAMETER and the row supplies CPython's own value.
def rd_scaled_uniform(+ar: O.Arena, +key: T.Tensor, +ctr: T.Tensor, +ds: List<&2, U32>, scale: F32, +dev: S.Dev) -> T.Tensor:
  MO.mo_bin_c(rd_uniform(False{}, ar, key, ctr, ds, F32.neg(1.0), 1.0, S.single(), dev), O.OpsMUL{}, O.CFloat{scale})

# rand.py:192 `glorot_uniform` -- `bound = (6 / (argfix(*shape)[0] + prod(argfix(*shape)
# [1:]))) ** 0.5` then `uniform(*shape, low=-bound, high=bound)` (rand.py:204-205). The
# bound is a Python float, so it is an `F32` PARAMETER for the same reason `scale` is.
def rd_glorot_uniform(+ar: O.Arena, +key: T.Tensor, +ctr: T.Tensor, +ds: List<&2, U32>, +bound: F32, +dev: S.Dev) -> T.Tensor:
  rd_uniform(False{}, ar, key, ctr, ds, F32.neg(bound), bound, S.single(), dev)

# rand.py:208 `kaiming_uniform` -- `bound = (6 / (1 + a ** 2) / prod(argfix(*shape)[1:]))
# ** 0.5` then the same `uniform` (rand.py:220-221).
def rd_kaiming_uniform(+ar: O.Arena, +key: T.Tensor, +ctr: T.Tensor, +ds: List<&2, U32>, +bound: F32, +dev: S.Dev) -> T.Tensor:
  rd_glorot_uniform(ar, key, ctr, ds, bound, dev)

# rand.py:224 `kaiming_normal` -- `std = (2 / (1 + a ** 2) / prod(argfix(*shape)[1:]))
# ** 0.5` then `normal(*shape, mean=0.0, std=std)` (rand.py:236-237).
def rd_kaiming_normal(+ar: O.Arena, +key: T.Tensor, +ctr: T.Tensor, +ds: List<&2, U32>, std: F32, +dev: S.Dev) -> T.Tensor:
  rd_normal(ar, key, ctr, ds, 0.0, std, dev)

# rand.py:240 `randperm` -- `cls.rand(n, device=device, **kwargs).argsort().cast(dtype)`
# (rand.py:249), and `argsort` (op.py:965) is the bitonic sort plus `.contiguous()`. WHAT IS
# PORTED IS `rand(n)`, which is the half of the line that is a graph.
# TODO(p3) mixin/rand.py:249  `randperm` -- `argsort` (op.py:965), a bitonic sort over four
#   nested Python `for` loops whose `_split` is a fuel-carrying self-call, plus
#   `.contiguous()` = `graph_rewrite` (P3, `mixin/op.bend`'s W5).
def rd_randperm(+ar: O.Arena, +key: T.Tensor, +ctr: T.Tensor, n: U32, +dev: S.Dev) -> T.Tensor:
  rd_rand_like(True{}, ar, key, ctr, S.single(), [n], dev)

# rand.py:251 `multinomial`. PORTED: the `weight = self.unsqueeze(0) if self.ndim == 1 else
# self` selection (rand.py:267) as `rd_multi`, both guards (rand.py:266, :268) as
# `rd_multi_n`/`rd_multi_rep`, and the trailing `.cast(dtypes.int32)` (rand.py:276) as
# `rd_cast_i32`. `unsqueeze(0)` (movement.py:308) is a `RESHAPE` to `[1] ++ shape`, which
# `mxw_reshape` is, and the `self` arm is `self` -- so `rd_multi` is the pair.
# TODO(p3) mixin/rand.py:270  `multinomial`'s cdf arm -- `cumsum` -> `identity_element`.
# TODO(p3) mixin/rand.py:275  `multinomial`'s Efraimidis-Spirakis arm -- `topk`.
def rd_multi.of(one: Bool, +w: T.Tensor, +ds: List<&2, U32>) -> T.Tensor:
  Bool.pick(T.Tensor, one, MX.mxw_reshape(w, List.append(&2, U32, [1], ds)), w)

def rd_multi(one: Bool, +w: T.Tensor) -> T.Tensor:
  rd_multi.of(one, w, MX.mxw_dims_of(T.Tensor.ar(w), T.Tensor.u(w)))

def rd_multi_rep(rep: Bool, ns: U32) -> Bool: Bool.or(rep, U32.is_eq(ns, 1))
def rd_cast_i32(+t: T.Tensor) -> T.Tensor: MO.mo_cast_t(t, S.int32())

# rand.py:278 `dropout` -- `if not 0 <= p <= 1: raise` (rand.py:293), `if not TRAINING or
# p == 0: return self` (rand.py:294), `if p == 1: return self.const_like(0)`
# (rand.py:295), else the general arm (rand.py:296). PORTED: the three-way SELECTION, which
# is the whole of the control flow and is three DIFFERENT graphs, gated by `drop_arm0`,
# `drop_arm1` and `drop_arm2`. `TRAINING` is a `Bool` PARAMETER (W6) and `arm` is the
# choice, carried as a `U32` because there are three arms and a two-valued `Bool` cannot
# name them.
# TODO(p3) mixin/rand.py:296  `dropout`'s general arm -- `where` over a float mask, then a
#   division by a Python float whose promotion is not the same rule as every other binop
#   here (`mo_bin_c` promotes a weakfloat CONST up, and `(1.0 - p)` is a weakfloat).
def rd_drop.arm(training: Bool, +p: F32) -> U32:
  Bool.pick(U32, Bool.not(training), 0, Bool.pick(U32, F32.is_eq(p, 0.0), 0, Bool.pick(U32, F32.is_eq(p, 1.0), 1, 2)))

def rd_drop.pick.of(+q: U1, +t: T.Tensor) -> T.Tensor:
  Bool.pick(T.Tensor, U32.is_eq(U1.v(q), 0), t,
    Bool.pick(T.Tensor, U32.is_eq(U1.v(q), 1), CR.cr_const_like(True{}, T.Tensor.ar(t), MO.mo_ki(0), S.single(), MX.mxw_dims_of(T.Tensor.ar(t), T.Tensor.u(t))), t))

def rd_drop.pick(arm: U32, +t: T.Tensor) -> T.Tensor: rd_drop.pick.of(U1{arm}, t)

# rand.py:298 `scaled_dot_product_attention`. PORTED: the `least_upper_dtype(q.dtype,
# key.dtype, dtypes.float32)` of rand.py:319, as a DTYPE and not a graph -- and
# `least_upper_dtype(*dtypes)` folds left, so it is `F.least_upper.of` CALLED twice, which
# is fold.bend's own lattice. That makes `ref_sdpa_dt` a shared row.
# TODO(p3) mixin/rand.py:315  the GQA arm -- `repeat_interleave` (movement.py:560).
# TODO(p3) mixin/rand.py:319  the matmul -- `mixin/op.bend`'s W8.
# TODO(p3) mixin/rand.py:323  the causal mask -- `tril` (op.py:259), which is W1 again.
# TODO(p3) mixin/rand.py:327  the `attn_mask` arm.
def rd_sdpa_dt(+q: S.Dt, +k: S.Dt) -> S.Dt: F.least_upper.of(F.least_upper.of(q, k), S.single())

# ===========================================================================
# THE GATE PRINTERS. `CR.cr_row` / `CR.cr_rowt` / `CR.cr_g.of` are creation.bend's and
# are CALLED: the four-facts string, the `srcops` walk, the toposort walk and the `_d`
# shape/dtype reader are four defs this file does not own and re-spelling them would be a
# second implementation of a printer whose output a byte-diff already pins.
# `CU` is creation.bend's one-field `Data` record for "a node index read more than once",
# which is the same reason `PK` and `U1` exist above.
# `rd_g` IS `cr_g` WITHOUT the `_d` half, and the reason is rule 18: `fold.bend:1621`
# defers PERMUTE, so a graph containing `arange` is UNANSWERABLE and asking for its shape
# or dtype prints `()`/`void` for reasons that have nothing to do with this file. Every
# `_g`-only row below is a graph that contains a PERMUTE, and saying so in the ROW NAME is
# the fix the notes prescribe for a `U32.show` that needs mental arithmetic.
# ===========================================================================
def rd_row.of(+nm: String, +ar: O.Arena, +c: CR.CU, +xs: List<&2, U32>) -> IO(Unit):
  CR.cr_g.of(nm, ar, c, xs)
def rd_row(nm: String, +t: T.Tensor) -> IO(Unit):
  rd_row.of(nm, T.Tensor.ar(t), CR.CU{T.Tensor.u(t)},
    O.UOp.toposort(O.Arena.budget(T.Tensor.ar(t)), T.Tensor.ar(t), T.Tensor.u(t)))
# `<nm>_np=<0|1>` -- "CAN THE FOLD ANSWER THIS NODE'S DTYPE". A BEND-ONLY row, and the one
# row in this file that names the WALL rather than a graph: it is `D.md_dt_eq(...,
# S.void())` inverted over `F.fold.dt`, and its expectation is `fold.bend`'s own refusal.
# `np_arange3=0` and `np_rand23=1` together are the measurement that says `arange` is
# BUILDABLE and NOT CHECKABLE, which is `mixin/op.bend`'s W4 restated in two numbers.
def rd_np.put(+fx: F.Folded, u: U32) -> Bool:
  Bool.not(Maybe.is_none(&2, S.Dt, F.fold.dt(F.Folded.ar(fx), F.Folded.t(fx), u)))
def rd_np(nm: String, +t: T.Tensor) -> IO(Unit):
  IO.print(String.concat([nm, "_np=", Bool.show(rd_np.put(F.folded(T.Tensor.ar(t)), T.Tensor.u(t)))]))
def rd_bl(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def rd_nm(nm: String, s: String) -> IO(Unit): IO.print(String.concat([nm, "=", s]))

# ===========================================================================
# THE FIXTURES. The generator state is INJECTED, which is the header's decision, and both
# halves of it are the 1-D TWO-ELEMENT `uint32` tensors Python's own
# `Tensor._device_seeds[device]` (tensor.py:463) and `Tensor._device_rng_counters[device]`
# (tensor.py:464) are. `rd_state` is a 4-node graph -- `ALLOC/0 CONST/0 STACK/2 RESHAPE/2`
# -- and CPython's `Tensor.empty(2, dtype=dtypes.uint32)` is the SAME four nodes, so the
# oracle can use it and the diff is a diff rather than a comparison of two fixtures.
# `rd_fx2d` is op.bend's `mo_fx2d` and is a RECEIVER ONLY: `rand_like` reads its shape
# and dtype and nothing else, so no row over it contains it.
# ===========================================================================
def rd_state(+ar: O.Arena) -> T.Tensor: CR.cr_empty(ar, Some{S.uint32()}, [2], S.D1{0})
def rd_key(+ar: O.Arena) -> T.Tensor: rd_state(ar)
def rd_ctr(+ar: O.Arena) -> T.Tensor: rd_state(ar)
def rd_fx2d() -> T.Tensor: MO.mo_fx2d()
def rd_fx1d() -> T.Tensor: MO.mo_fx1d()

# --- THE BORROWED BLOCK (op.py:166 `arange`). `_g` ONLY, and the row name says `_np`.
def t_arange3() -> IO(Unit):
  +a: T.Tensor = op_arange(O.Arena.empty(), 3, S.D1{0})
  do IO<Unit>:
    rd_row("arange3_g", a)
    rd_np("fold", a)
def t_arange5() -> IO(Unit):
  +a: T.Tensor = op_arange(O.Arena.empty(), 5, S.D1{0})
  do IO<Unit>:
    rd_row("arange5_g", a)
    rd_np("fold5", a)

# --- rand.py:12 `_threefry_random_bits`, on `random_bits`'s own counts.
def t_tfb3() -> IO(Unit):
  +ar = O.Arena.empty()
  +k = rd_key(ar)
  +c0: T.Tensor = op_arange(T.Tensor.ar(k), 3, S.D1{0})
  +c1: T.Tensor = MO.mo_bin_c(c0, O.OpsADD{}, MO.mo_ki(3))
  rd_row("tfb3_g", rd_tfb(T.Tensor.ar(c1), k, c0, c1))

# --- rand.py:18 `random_bits` with `num = 6`, which is what `rand(2, 3)` asks for.
def t_bits6() -> IO(Unit):
  +ar = O.Arena.empty()
  +k = rd_key(ar)
  +c = rd_ctr(T.Tensor.ar(k))
  rd_row("bits6_g", rd_bits(T.Tensor.ar(c), k, c, 6, S.D1{0}))

# --- rand.py:32 `_bits_to_rand`, over the SAME `bits` `rand(2,3)` produces.
def t_btr6() -> IO(Unit):
  +ar = O.Arena.empty()
  +k = rd_key(ar)
  +c = rd_ctr(T.Tensor.ar(k))
  +b: T.Tensor = rd_bits(T.Tensor.ar(c), k, c, 6, S.D1{0})
  rd_row("btr6_g", rd_btr(False{}, T.Tensor.ar(b), b, [2, 3], S.single()))

# --- rand.py:40 `_rand`, the def `rand` is one call into. TWO ROWS: the `contiguous=True`
# graph carries the ALLOC/STORE/AFTER tail and the `False` one does not, so the pair is
# what pins `out.clone()` rather than `out`.
def t_rand23() -> IO(Unit):
  +ar = O.Arena.empty()
  +k = rd_key(ar)
  +c = rd_ctr(T.Tensor.ar(k))
  CR.cr_row("rand23", rd_rand(True{}, T.Tensor.ar(c), k, c, [2, 3], S.single(), S.D1{0}))
def t_rand23nc() -> IO(Unit):
  +ar = O.Arena.empty()
  +k = rd_key(ar)
  +c = rd_ctr(T.Tensor.ar(k))
  CR.cr_row("rand23nc", rd_rand(False{}, T.Tensor.ar(c), k, c, [2, 3], S.single(), S.D1{0}))

# --- rand.py:50 `rand` itself, which is `_rand` with the dtype already resolved. The row
# is a CONTROL for `rand23`: the two must be byte-identical, and a repeated row being
# byte-identical is what makes the lane diff a diff.
def t_randc23() -> IO(Unit):
  +ar = O.Arena.empty()
  +k = rd_key(ar)
  +c = rd_ctr(T.Tensor.ar(k))
  CR.cr_row("ctrl_rand", rd_rand_cls(True{}, T.Tensor.ar(c), k, c, [2, 3], S.single(), S.D1{0}))


# --- rand.py:70 `rand_like` on a 2-D receiver.
def t_rand_like23() -> IO(Unit):
  +ar = O.Arena.empty()
  +k = rd_key(ar)
  +c = rd_ctr(T.Tensor.ar(k))
  CR.cr_row("rand_like23", rd_rand_like(True{}, T.Tensor.ar(c), k, c, S.single(), [2, 3], S.D1{0}))

# --- rand.py:88 `randn_like` on a 2-D receiver, WITHOUT the `empty`: the receiver is a
# fixture whose graph never reaches the answer, so the row is `randn_like`'s own.
def t_randn_like23() -> IO(Unit):
  +ar = O.Arena.empty()
  +k = rd_key(ar)
  +c = rd_ctr(T.Tensor.ar(k))
  +f: T.Tensor = rd_fx2d()
  CR.cr_row("randn_like23", rd_randn_like(False{}, T.Tensor.ar(c), k, c, f, S.D1{0}))

# --- rand.py:106 `randn`, and the `dtype=half` arm where `.cast(dt)` is NOT a fold.
def t_randn23() -> IO(Unit):
  +ar = O.Arena.empty()
  +k = rd_key(ar)
  +c = rd_ctr(T.Tensor.ar(k))
  CR.cr_row("randn23", rd_randn(False{}, T.Tensor.ar(c), k, c, [2, 3], S.D1{0}))
def t_randn23h() -> IO(Unit):
  +ar = O.Arena.empty()
  +k = rd_key(ar)
  +c = rd_ctr(T.Tensor.ar(k))
  CR.cr_row("randn23h", rd_randn(True{}, T.Tensor.ar(c), k, c, [2, 3], S.D1{0}))

# --- rand.py:158 `uniform`, rand.py:122 `randint`, rand.py:141 `normal`. `randint` is the
# row that pins the `.cast(dtype)` BETWEEN the multiply and the add (rand.py:173): the two
# graphs have the same node COUNT and the same root op and differ in a dtype and a
# position, so only the src-op sequence's position and the `_d` row see it.
def t_uniform23() -> IO(Unit):
  +ar = O.Arena.empty()
  +k = rd_key(ar)
  +c = rd_ctr(T.Tensor.ar(k))
  CR.cr_row("uniform23", rd_uniform(False{}, T.Tensor.ar(c), k, c, [2, 3], 2.0, 10.0, S.single(), S.D1{0}))
def t_randint23() -> IO(Unit):
  +ar = O.Arena.empty()
  +k = rd_key(ar)
  +c = rd_ctr(T.Tensor.ar(k))
  CR.cr_row("randint23", rd_randint(T.Tensor.ar(c), k, c, [2, 3], 5.0, 10.0, S.int32(), S.D1{0}))
def t_normal23() -> IO(Unit):
  +ar = O.Arena.empty()
  +k = rd_key(ar)
  +c = rd_ctr(T.Tensor.ar(k))
  CR.cr_row("normal23", rd_normal(T.Tensor.ar(c), k, c, [2, 3], 10.0, 2.0, S.D1{0}))

# --- rand.py:176/192/208/224. The `scale` / `bound` / `std` are Python floats and each row
# supplies CPython's own value, which is the whole of the port for them: there is no graph
# in `6 / (shape[0] + prod(shape[1:])) ** 0.5` to port, it is four Python scalars.
def t_scaled_uniform23() -> IO(Unit):
  +ar = O.Arena.empty()
  +k = rd_key(ar)
  +c = rd_ctr(T.Tensor.ar(k))
  CR.cr_row("scaled_uniform23", rd_scaled_uniform(T.Tensor.ar(c), k, c, [2, 3], 0.40824829, S.D1{0}))
def t_glorot_uniform23() -> IO(Unit):
  +ar = O.Arena.empty()
  +k = rd_key(ar)
  +c = rd_ctr(T.Tensor.ar(k))
  CR.cr_row("glorot_uniform23", rd_glorot_uniform(T.Tensor.ar(c), k, c, [2, 3], 1.0954451, S.D1{0}))
def t_kaiming_uniform23() -> IO(Unit):
  +ar = O.Arena.empty()
  +k = rd_key(ar)
  +c = rd_ctr(T.Tensor.ar(k))
  CR.cr_row("kaiming_uniform23", rd_kaiming_uniform(T.Tensor.ar(c), k, c, [2, 3], 1.4140706, S.D1{0}))
def t_kaiming_normal23() -> IO(Unit):
  +ar = O.Arena.empty()
  +k = rd_key(ar)
  +c = rd_ctr(T.Tensor.ar(k))
  CR.cr_row("kaiming_normal23", rd_kaiming_normal(T.Tensor.ar(c), k, c, [2, 3], 0.8164111, S.D1{0}))

# --- rand.py:240 `randperm`, WHOSE `rand(n)` HALF IS ALL THAT IS PORTED. The row name says
# so, because `Tensor.randperm(6)` in CPython has the SORT in it and this row does not.
def t_randperm() -> IO(Unit):
  +ar = O.Arena.empty()
  +k = rd_key(ar)
  +c = rd_ctr(T.Tensor.ar(k))
  CR.cr_row("randperm_rand", rd_randperm(T.Tensor.ar(c), k, c, 6, S.D1{0}))

# --- rand.py:251 `multinomial`'s `weight = self.unsqueeze(0) if self.ndim == 1 else self`
# (rand.py:267) and NOTHING ELSE. TWO ROWS, one per `ndim`, because the arm with no fixture
# is dead code: `multi1` is the `unsqueeze(0)` and `multi2` is the identity.
def t_multi1() -> IO(Unit): CR.cr_row("multi1", rd_multi(True{}, rd_fx1d()))
def t_multi2() -> IO(Unit): CR.cr_row("multi2", rd_multi(False{}, rd_fx2d()))

# --- rand.py:278 `dropout`'s THREE-WAY ARM SELECTION, one row per arm, because the three
# arms are THREE DIFFERENT GRAPHS and the middle one is `self.const_like(0)`.
def t_drop0() -> IO(Unit): CR.cr_row("drop_arm0", rd_drop.pick(rd_drop.arm(False{}, 0.5), rd_fx2d()))
def t_drop1() -> IO(Unit): CR.cr_row("drop_arm1", rd_drop.pick(rd_drop.arm(True{}, 1.0), rd_fx2d()))
def t_drop2() -> IO(Unit): CR.cr_row("drop_arm2", rd_drop.pick(rd_drop.arm(True{}, 0.5), rd_fx2d()))

# ===========================================================================
# THE GENERATOR-STATE ROWS. Four of them, over tensor.py:466-471 with the counter
# INJECTED, and the oracle is CPython's own five lines. `_g` ONLY and `_np` in the name,
# because the counter's own graph contains no EXPAND but its consumer `rand23` does.
#   st_zero   num = 0        -- the borrow is still BUILT (a `MUL` and an `ADD` for the
#                               `-(num >> 32)` term), so a "no-op" advance is not `self`
#   st_six    num = 6        -- the value `rand(2,3)` uses; the pair with `rand23` is the
#                               measurement that `rd_bits_num` and this agree
#   st_after  num = 6 twice  -- the counter `st_six` returned, fed back in, so the BORROW
#                               is exercised rather than assumed
#   st_max    num = 2**32-1  -- `(num & 0xffffffff)` is the mask's identity value and
#                               `num >> 32` is 0 in Python AND in `U32.shrn`'s saturation,
#                               so the two lanes AGREE here. They DISAGREE for num > 2**32
#                               and that is unreachable (17 GiB of random bits); the header
#                               names it rather than a row pretending to cover it
# ===========================================================================
def t_st_zero() -> IO(Unit):
  +ar = O.Arena.empty()
  +k = rd_key(ar)
  +c = rd_ctr(T.Tensor.ar(k))
  rd_row("st_zero_g", rd_next(T.Tensor.ar(c), 0, c))
def t_st_six() -> IO(Unit):
  +ar = O.Arena.empty()
  +k = rd_key(ar)
  +c = rd_ctr(T.Tensor.ar(k))
  rd_row("st_six_g", rd_next(T.Tensor.ar(c), 6, c))
def t_st_after() -> IO(Unit):
  +ar = O.Arena.empty()
  +k = rd_key(ar)
  +c = rd_ctr(T.Tensor.ar(k))
  +c1: T.Tensor = rd_next(T.Tensor.ar(c), 6, c)
  rd_row("st_after_g", rd_next(T.Tensor.ar(c1), 6, c1))
def t_st_max() -> IO(Unit):
  +ar = O.Arena.empty()
  +k = rd_key(ar)
  +c = rd_ctr(T.Tensor.ar(k))
  rd_row("st_max_g", rd_next(T.Tensor.ar(c), 4294967295, c))


# ===========================================================================
# THE REFUSAL ROWS. CPython's OWN PREDICATES, asked as predicates, so all of them are
# shared rows rather than BEND-ONLY ones -- except the four that name a Python `raise`
# this port cannot express, which is what `ref_*` is FOR.
# ===========================================================================
def t_ref() -> IO(Unit):
  do IO<Unit>:
    rd_bl("ref_rand_weak_f32", rd_ok_float(S.single()))
    rd_bl("ref_rand_weak_wf", rd_ok_float(S.weakfloat()))
    rd_bl("ref_rand_weak_h", rd_ok_float(S.half()))
    rd_bl("ref_rand_weak_i32", rd_ok_float(S.int32()))
    rd_bl("ref_shape_u32", rd_ok_shape([2, 3]))
    rd_bl("ref_uniform_lt", rd_lt(2.0, 10.0))
    rd_bl("ref_uniform_not", rd_lt(10.0, 2.0))
    rd_bl("ref_normal_std", rd_std_ok(2.0))
    rd_bl("ref_normal_not", rd_std_ok(F32.neg(2.0)))
    rd_bl("ref_randint_int", rd_ok_int(S.int32()))
    rd_bl("ref_randint_not", rd_ok_int(S.single()))
    rd_bl("ref_dropout_p", rd_p_ok(0.5))
    rd_bl("ref_dropout_p1", rd_p_ok(1.0))
    rd_bl("ref_dropout_p1n", rd_p_ok(0.9999999))
    rd_bl("ref_dropout_not", rd_p_ok(1.5))
    rd_bl("ref_multi_n11", rd_multi_n(1, 3))
    rd_bl("ref_multi_n23", rd_multi_n(2, 3))
    rd_bl("ref_multi_n31", rd_multi_n(3, 1))
    rd_bl("ref_multi_rep", rd_multi_rep(True{}, 1))
    rd_nm("ref_sdpa_dt", T.dt_name(rd_sdpa_dt(S.half(), S.single())))
    rd_nm("ref_shift_f32", U32.show(rd_shift(S.single())))
    rd_nm("ref_shift_h", U32.show(rd_shift(S.half())))
    rd_nm("ref_one_bits_f32", U32.show(rd_one_bits.of(S.single())))
    rd_nm("ref_one_bits_h", U32.show(rd_one_bits.of(S.half())))
    rd_nm("ref_nmant_f32", U32.show(rd_nmant.of(S.single())))
    rd_nm("ref_uint_dt_f32", T.dt_name(rd_uint_dt.of(S.single())))
    rd_nm("ref_bits_num23", U32.show(rd_bits_num([2, 3], S.single())))
    rd_nm("ref_bits_num223", U32.show(rd_bits_num([2, 2, 3], S.single())))
    rd_nm("ref_drop_arm0", U32.show(rd_drop.arm(False{}, 0.5)))
    rd_nm("ref_drop_arm1", U32.show(rd_drop.arm(True{}, 0.5)))
    rd_nm("ref_drop_arm2", U32.show(rd_drop.arm(True{}, 1.0)))

# THE CONTROL. The same fixture as `arange3`, built from the same call, and the diff
# against the oracle is only a diff if a repeated row is byte-identical.
def t_ctrl() -> IO(Unit):
  +a: T.Tensor = op_arange(O.Arena.empty(), 3, S.D1{0})
  rd_row("ctrl_arange3_g", a)

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_st_zero()
    b : Unit <- t_st_six()
    c : Unit <- t_st_after()
    d : Unit <- t_st_max()
    t_ref()
    e : Unit <- t_arange3()
    f : Unit <- t_arange5()
    g : Unit <- t_tfb3()
    h : Unit <- t_bits6()
    i : Unit <- t_btr6()
    j : Unit <- t_rand23()
    k : Unit <- t_rand23nc()
    l : Unit <- t_randc23()
    m : Unit <- t_rand_like23()
    t_ctrl()

# ===========================================================================
# THE MEASURED MUTATION TABLE. EIGHT one-token edits, each applied, each run through the
# INTERPRETED lane, each diffed row-by-row against the unmutated output, each reverted
# from a byte snapshot. Baseline: 49 printed rows, 31 of them shared with CPython and
# GREEN.
#
#   $ORACLE_DIR/rd-mutate.py
#
#  #  mutation                                     rows moved   what moved
#  -  ------------------------------------------  -----------  --------------------------
#  M1 `rd_mask`'s mask dropped (`n` -> `n - 1`)             2  `st_max_g`, `st_zero_g`
#  M2 `rd_p64`'s two args SWAPPED (reversed srcs)            1  `tfb3_g`
#  M3 `op_arange`'s trailing `.cast(dtype)` dropped          4  `arange3_g`, `arange5_g`,
#                                                                   `ctrl_arange3_g`, `tfb3_g`
#  M4 `rd_bits_num`'s divisor 4 -> 2 (a COUNT)               2  `ref_bits_num23`, `ref_bits_num223`
#  M5 `rd_nmant`'s `case 32` arm dropped                     2  `ref_nmant_f32`, `ref_shift_f32`
#  M6 `rd_drop.arm`'s innermost arm 2 -> 1                   1  `ref_drop_arm1`
#  M7 `rd_p_ok`'s `<= 1` relaxed to `< 1`   [MOVED 0, THEN 1] 1  `ref_dropout_p1` (see below)
#  M8 CONTROL: a comment                                    0  nothing, which is the point
#
# FIVE THINGS THIS TABLE SAYS THAT "31 GREEN ROWS" DOES NOT.
#
#   * M7 MOVED NOTHING THE FIRST TIME IT WAS RUN, and the fix was a FIXTURE and not a
#     better row. `rd_p_ok` is `0 <= p <= 1` and its two fixtures were `p = 0.5` and
#     `p = 1.5`, so `<= 1` and `< 1` are VACUOUS on both -- the mutation was on live code
#     and no row could see it. `ref_dropout_p1` (`p = 1.0`, the value rand.py:295
#     branches on) and `ref_dropout_p1n` (`p = 0.9999999`) were added, M7 was re-run, and it
#     moves exactly `ref_dropout_p1`. This is wgsl.bend's and device.bend's gate lesson
#     stated as a table row: **`moved == 0` on live code is a MISSING ROW**, and the
#     response is to build the fixture the mutation is asking for, then RE-RUN -- "I added
#     a fixture" and "the fixture sees this mutation" are different claims.
#   * M3 IS THE SHARPEST ROW IN THE FILE AND IT IS THE HEADER'S R2, MEASURED. Dropping a
#     FOLD that CPython also folds -- `arange`'s trailing `.cast(dtype)` (op.py:195) -- moves
#     FOUR rows and NOT ONE of the 31 green ones. The two `ref_*` rows that would say
#     "the dtype is uint32" do not exist for this fixture, because `fold.bend` cannot
#     answer an EXPAND-rooted graph (the header's `fold_np=False`), so a dropped fold in
#     the last line of a constructor is invisible to every refusal row, every dtype row and
#     every count row in the file. The four that move are the four that print a TOPOSORT.
#   * M1 AND M5 ARE LOCALISED TO EXACTLY THEIR OWN DOMAIN, and that is the correct blast
#     radius. `rd_mask` is read only by `_next_counter`'s two low terms and its two compare
#     terms, so only `st_zero_g` (num = 0, where the mask is the WHOLE value) and
#     `st_max_g` (num = 2**32-1, where `n - 1` is representable and the borrow is the only
#     thing that changes) move, and `st_six_g`/`st_after_g` do NOT -- which is itself the
#     measurement that `st_zero` and `st_max` are the two fixtures that pin `rd_mask` and
#     `st_six` is not. `rd_nmant` is read only by `rd_shift`, which is read only by
#     `rd_btr.rshift`, which is on the `_bits_to_rand` path that the fold cannot reach, so
#     only the two `ref_*` rows that ask `rd_shift`/`rd_nmant` DIRECTLY move. A localised
#     row is a claim that the predicate is reachable from exactly where it should be.
#   * M2 IS THE REVERSED-SRCS MUTATION AND IT IS GRAPH-ISOMORPHIC ON A FIXTURE WITH ONE
#     COUNT, WHICH IS WHY `tfb3_g` IS THE ROW THAT SEES IT AND `arange3_g` IS NOT. The
#     counts `c0` and `c1` are `arange(3)` and `arange(3) + 3` -- DIFFERENT nodes -- so the
#     swap is visible; on a fixture where both halves are the same interned index it would
#     be invisible, and `tfb3_g` is the fixture that was built to prevent that. It moves
#     exactly ONE row, and that row is the one whose toposort contains the 64-bit pair.
#   * NO MUTATION OF THIS TABLE MOVES A `ref_*` ROW THAT IT SHOULD NOT, AND NO MUTATION
#     MOVES A `_d` ROW AT ALL -- the eight `_d` rows are all red already, so they are a
#     PLACEHOLDER for the shape/dtype half rather than evidence, and the header's
#     GATE STATUS says so in the same words.
# ===========================================================================
