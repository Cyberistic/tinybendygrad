// t1_wire.c -- the argument wire of the `Dt.i64_*` seam, read TWO ways.
//
// THE QUESTION. `runtime/dtype.c:205-206` reads an `H.I64` argument as
//
//     return (s64)(((u64)(u32)f[0] << 32) | (u32)f[1]);
//
// i.e. it assumes the two halves arrive as two consecutive words of the effect
// argument frame. This file asks whether they do.
//
// THE METHOD IS A DIFFERENTIAL, NOT AN ORACLE. `H.i64_of_hi_lo` is the identity,
// so for every pair `x`, a CORRECT reader answers `x`. Two readers are applied to
// the SAME received bytes and exactly one of them is the identity. Nothing here
// asserts what a wrong answer looks like -- "it is a heap address" is not a
// prediction this file makes and does not need. The identity is definitional, so
// WHICH reader is it is a measurement.
//
//   wire_flat    f[0], f[1]              -- dtype.c:206's rule
//   wire_boxed   ctr_take(f[0], 2, o)    -- through the argument's own Term
//
// `ctr_take` is the runtime's own field reader (it handles a static payload as
// well as a heap one), so `wire_boxed` is not a reader I invented.

static Term wire_flat(Env e, Term* f, IoWork* w) {
  return io_tup(e, (Term)(intptr_t)(u32)f[0], (Term)(intptr_t)(u32)f[1]);
}

static Term wire_boxed(Env e, Term* f, IoWork* w) {
  Term o[2];
  ctr_take(e, f[0], 2, o);
  return io_tup(e, o[0], o[1]);
}

// The PLANT: the halves swapped. It must move every row whose two halves
// DIFFER and must not move a single row whose halves are equal, which is why
// the fixture set is half equal-halves on purpose.
static Term wire_boxed_swap(Env e, Term* f, IoWork* w) {
  Term o[2];
  ctr_take(e, f[0], 2, o);
  return io_tup(e, o[1], o[0]);
}

// The DISARM: a different EXPRESSION for `wire_boxed`, not a different function.
// `U32.or(x, 0)` is x for every x, so this rewrites the program without changing
// the answer, and the only correct moved-set is the empty one.
static Term wire_boxed_same(Env e, Term* f, IoWork* w) {
  Term o[2];
  ctr_take(e, f[0], 2, o);
  return io_tup(e, (Term)(intptr_t)(u32)(o[0] | 0u), (Term)(intptr_t)(u32)(o[1] | 0u));
}

#ifdef CID_WIRE_FLAT
static void __attribute__((constructor)) wire_flat_use(void) { io_eff(CID(WIRE_FLAT), wire_flat, 0); }
#endif
#ifdef CID_WIRE_BOXED
static void __attribute__((constructor)) wire_boxed_use(void) { io_eff(CID(WIRE_BOXED), wire_boxed, 0); }
#endif
#ifdef CID_WIRE_BOXED_SWAP
static void __attribute__((constructor)) wire_boxed_swap_use(void) { io_eff(CID(WIRE_BOXED_SWAP), wire_boxed_swap, 0); }
#endif
#ifdef CID_WIRE_BOXED_SAME
static void __attribute__((constructor)) wire_boxed_same_use(void) { io_eff(CID(WIRE_BOXED_SAME), wire_boxed_same, 0); }
#endif