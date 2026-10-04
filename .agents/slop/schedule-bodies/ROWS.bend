# ------------------------------------------------------------------
    # THE TWELVE'S ROWS. `py=` is `sb-oracle.py`'s printed output. None typed.
    #
    # 1  is_store_after -- __init__.py:217-218
    # ------------------------------------------------------------------
    row("isa_SA_B", b2u(is_store_after(rb.ar(), rb.sab())))
    row("isa_SA_A", b2u(is_store_after(rb.ar(), rb.saa())))
    row("isa_SA_S", b2u(is_store_after(rb.ar(), rb.sas())))
    row("isa_SA_E", b2u(is_store_after(rb.ar(), rb.sae())))
    row("isa_K", b2u(is_store_after(rb.ar(), rb.k())))
    # the READER the AND is built on, as a CODE: a PARAM is 3 and an ALLOC is 14,
    # so a port that read `base` for `unsharded_base` is caught by the VALUE and
    # not only by the boolean above.
    row("usb_SA_A", gate.code2(sc_op(rb.ar(), O.UOp.unsharded_base(O.Arena.budget(rb.ar()), rb.ar(), sc_src0(rb.ar(), rb.saa())))))
    row("usb_SA_B", gate.code2(sc_op(rb.ar(), O.UOp.unsharded_base(O.Arena.budget(rb.ar()), rb.ar(), sc_src0(rb.ar(), rb.sab())))))
    row("usb_K", gate.code2(sc_op(rb.ar(), O.UOp.unsharded_base(O.Arena.budget(rb.ar()), rb.ar(), sc_src0(rb.ar(), rb.k())))))
    row("usb_nsrc_SA_B", sc_nsrc(rb.ar(), rb.sab()))
    row("usb_nsrc_SA_A", sc_nsrc(rb.ar(), rb.saa()))
    # ------------------------------------------------------------------
    # 2/3  CallifyCtx + collect_stores -- __init__.py:192-197, 220-221
    # ------------------------------------------------------------------
    +c1 = collect_stores(callify_ctx(), rb.ar(), rb.sab())
    row("cs_len1", rcs_len(Cw.c(c1)))
    row("cs_op1", gate.code2(sc_op(rb.ar(), rcs_get(Cw.c(c1), 0n))))
    row("cs_none1", b2u(rmn(Cw.a(c1))))
    +c2 = cs_run(callify_ctx(), rb.ar(), rb.calls())
    row("cs_len2", rcs_len(c2))
    row("cs_ops2", rcs_codes(CallifyCtx.stores(c2), rb.ar()))
    row("cs_dup2", rcs_same(1n, 2n, c2))
    row("cs_ord2", rcs_same(0n, 1n, c2))
    row("cs_reps", U32.from_nat(List.length(&2, U32, CallifyCtx.replacements(c2))))
    row("cs_allocs", raa(c2))
    row("cs_views", U32.from_nat(List.length(&2, U32, CallifyCtx.views(c2))))
    # ------------------------------------------------------------------
    # 4  lower_sink_to_linear -- __init__.py:124-126, THE GUARD
    # ------------------------------------------------------------------
    row("lsl_none_ki", b2u(rmn(lower_sink_to_linear(rb.ar(), rb.lki()))))
    row("lsl_none_nopre", b2u(rmn(lower_sink_to_linear(rb.ar(), rb.lnp()))))
    row("lsl_none_nosink", b2u(rmn(lower_sink_to_linear(rb.ar(), rb.lnosink()))))
    row("lsl_ok_plain", b2u(lower_sink_to_linear.p_ok(rb.ar(), rb.lp())))
    row("lsl_ok_ki", b2u(lower_sink_to_linear.p_ok(rb.ar(), rb.lki())))
    row("lsl_ok_nopre", b2u(lower_sink_to_linear.p_ok(rb.ar(), rb.lnp())))
    row("lsl_ok_nosink", b2u(lower_sink_to_linear.p_ok(rb.ar(), rb.lnosink())))
    row("lsl_p_sink", b2u(lower_sink_to_linear.p_sink(rb.ar(), rb.lp())))
    row("lsl_p_ki", b2u(lower_sink_to_linear.p_ki(rb.ar(), rb.lki())))
    row("lsl_p_noki", b2u(lower_sink_to_linear.p_ki(rb.ar(), rb.lp())))
    row("lsl_p_pre", b2u(lower_sink_to_linear.p_pre(rb.ar(), rb.lp())))
    row("lsl_p_nopre", b2u(lower_sink_to_linear.p_pre(rb.ar(), rb.lnp())))
    # ------------------------------------------------------------------
    # 5/6  copy_kernel_to_store :161 -- simplify_copy_kernel :165 (GUARD)
    # `disk` is the DISK TAG SET, tag 1. `cks_same` and `cks_cross` are ONE ROW
    # APART and differ only in `dst.device == src.device`.
    # ------------------------------------------------------------------
    rows("cks_same", rnone(copy_kernel_to_store([1], rb.ar(), rb.k(), rb.pc(), rb.pc2())))
    rows("cks_cross", rnone(copy_kernel_to_store([1], rb.ar(), rb.ks(), rb.pd(), rb.pc())))
    rows("cks_disk", rnone(copy_kernel_to_store([1], rb.ar(), rb.ks(), rb.pd(), rb.pc2())))
    rows("cks_rev", rnone(copy_kernel_to_store([1], rb.ar(), rb.ks(), rb.pc(), rb.pd())))
    +cg = rfirst_found(copy_kernel_to_store([1], rb.ar(), rb.ks(), rb.pd(), rb.pc()))
    rows("cks_call_code", rnone.of(O.Arena.op(O.Found.ar(cg), O.Found.i(cg))))
    row("cks_call_nsrc", sc_nsrc(O.Found.ar(cg), O.Found.i(cg)))
    row("cks_call_s0", gate.code2(sc_op(O.Found.ar(cg), sc_src0(O.Found.ar(cg), O.Found.i(cg)))))
    row("cks_call_s1", gate.code2(sc_op(O.Found.ar(cg), sc_src(O.Found.ar(cg), O.Found.i(cg), 1))))
    +cs_ = sc_src0(O.Found.ar(cg), O.Found.i(cg))
    row("cks_store_code", gate.code2(sc_op(O.Found.ar(cg), cs_)))
    row("cks_store_nsrc", sc_nsrc(O.Found.ar(cg), cs_))
    row("cks_store_s0", gate.code2(sc_op(O.Found.ar(cg), sc_src0(O.Found.ar(cg), cs_))))
    row("cks_store_s1", gate.code2(sc_op(O.Found.ar(cg), sc_src(O.Found.ar(cg), cs_, 1))))
    row("cks_store_same", b2u(U32.is_eq(sc_src0(O.Found.ar(cg), cs_), rb.pd())))
    row("cks_store_same1", b2u(U32.is_eq(sc_src(O.Found.ar(cg), cs_, 1), rb.pc())))
    row("cks_tail_same", b2u(U32.is_eq(sc_src(O.Found.ar(cg), O.Found.i(cg), 1), rb.pd())))
    row("cks_head_new", b2u(Bool.not(U32.is_eq(cs_, rb.bo()))))
    rows("sck_same", rb2s(simplify_copy_kernel.ok([1], rb.ar(), rb.pc(), rb.pc2())))
    rows("sck_cross", rb2s(simplify_copy_kernel.ok([1], rb.ar(), rb.pd(), rb.pc())))
    # ------------------------------------------------------------------
    # 7  assert_all_same_devices -- __init__.py:157-159
    # ------------------------------------------------------------------
    rows("asd_none", rasd(rb.ar(), rb.bo()))
    rows("asd_one", rasd(rb.ar(), rb.sin()))
    rows("asd_two", rasd(rb.ar(), rb.sin2(rb.ar())))
    rows("asd_diff", rasd(rb.ar(), rb.sind(rb.ar())))
    row("asd_ndev_none", rdevs(rb.ar(), rb.bo()))
    row("asd_ndev_one", rdevs(rb.ar(), rb.sin()))
    row("asd_ndev_two", rdevs(rb.ar(), rb.sin2(rb.ar())))
    row("asd_ndev_diff", rdevs(rb.ar(), rb.sind(rb.ar())))
    row("asd_ops_two", rdevops(rb.ar(), rb.sin2(rb.ar())))
    row("asd_ops_diff", rdevops(rb.ar(), rb.sind(rb.ar())))
    row("asd_topo_two", rtopo(rb.ar(), rb.sin2(rb.ar())))
    row("asd_topo_diff", rtopo(rb.ar(), rb.sind(rb.ar())))
    # ------------------------------------------------------------------
    # 8  apply_binds -- __init__.py:110-112, THE THREE-ARM DISPATCH
    # ------------------------------------------------------------------
    row("ab_C_LIN", apply_binds(rb.ar(), rb.cl()))
    row("ab_C_PROG", apply_binds(rb.ar(), rb.cp()))
    row("ab_C_PLN", apply_binds(rb.ar(), rb.cn()))
    row("ab_LIN", apply_binds(rb.ar(), rb.lin()))
    row("ab_BO", apply_binds(rb.ar(), rb.bo()))
    row("ab_C_KS", apply_binds(rb.ar(), rb.ks()))
    row("ab_iscall_C_LIN", b2u(sc_is(rb.ar(), rb.cl(), O.OpsCALL{})))
    row("ab_iscall_C_PROG", b2u(sc_is(rb.ar(), rb.cp(), O.OpsCALL{})))
    row("ab_iscall_LIN", b2u(sc_is(rb.ar(), rb.lin(), O.OpsCALL{})))
    row("ab_iscall_BO", b2u(sc_is(rb.ar(), rb.bo(), O.OpsCALL{})))
    row("ab_body_C_LIN", gate.code2(sc_op(rb.ar(), rb_body(rb.ar(), rb.cl()))))
    row("ab_body_C_PROG", gate.code2(sc_op(rb.ar(), rb_body(rb.ar(), rb.cp()))))
    row("ab_body_C_PLN", gate.code2(sc_op(rb.ar(), rb_body(rb.ar(), rb.cn()))))
    row("ab_body_LIN", gate.code2(sc_op(rb.ar(), rb_body(rb.ar(), rb.lin()))))
    # ------------------------------------------------------------------
    # 9  canonicalize_alloc -- __init__.py:235-237. THE SLOT ARITHMETIC.
    # ------------------------------------------------------------------
    +k1 = canonicalize_alloc(callify_ctx(), rb.ar(), rb.al())
    rows("ca_slot1", rca_slot(k1))
    row("ca_n1", raa(CaPut.c(k1)))
    row("ca_same1", b2u(Maybe.is_some(&2, U32, aa_get(CaPut.c(k1), rb.al()))))
    rows("ca_name1", rca_name(k1))
    +k2 = canonicalize_alloc(CaPut.c(k1), rb.ar(), rb.a2())
    rows("ca_slot2", rca_slot(k2))
    row("ca_n2", raa(CaPut.c(k2)))
    +k3 = canonicalize_alloc(CaPut.c(k2), rb.ar(), rb.al())
    rows("ca_slot3", rca_slot(k3))
    row("ca_n3", raa(CaPut.c(k3)))
    row("ca_repeat", rca_same(k1, k3))
    +k4 = canonicalize_alloc(callify_ctx(), rb.ar(), rb.an())
    row("ca_neg_none", b2u(Maybe.is_some(&2, U32, aa_get(CaPut.c(k4), rb.an()))))
    row("ca_neg_n", raa(CaPut.c(k4)))
    rows("ca_noarg", rnone_of(canonicalize_alloc(callify_ctx(), rb.ar(), rb.noarg(rb.ar()))))