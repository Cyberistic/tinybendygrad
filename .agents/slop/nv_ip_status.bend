# ===========================================================================
# STATUS
#   PORTED:      see WHAT IS PORTED, DEF BY DEF, below.
#   NOT PORTED:  the seams and the three walls above, each with a Python line.
#   PYTHON:      tinygrad/runtime/support/nv/ip.py:1-661 (the whole file)
#
# WHAT IS PORTED, DEF BY DEF. Every def named here EXISTS; the first draft of this
# table named forty-eight defs that were never written (`ip.init_hw`, `q.init`,
# `gsp.wpr_meta`, `seq.table`, ...), which is what a plan written before the code
# looks like from the outside. The names below are the file's own namespaces.
#
#   GENERATED   cn_table / cn_rows / cn_names             the 64 U32 constants
#               st_<struct> / st_rows / st_sum_*          the 54 layouts, 413 fields
#               ce_rows / ce_min / ce_max                 the two dispatch tables
#               const_of / const_name / const_name_n       both directions
#               rpc_label / overlap / hex8                the row printers
#   QUEUE       Q / q.of / rp.{msg_size,msg_count,        :19-31 the header, the ring
#               ring_len,entry_off,hdr_len,phdr_len,      length `msgSize*msgCount`,
#               max_payload,length,elem,total,off,first,   `max_payload`, the record
#               wraps,wp_after}                            arithmetic :38-55
#   CHECKSUM    rp.{word,word2,which,w_*,fold,acc4,       :32-36 the 64-bit XOR, folded
#               wordof,pickw,finish,cksum.xor,nu64,nwords} into two U32 folds
#   TRACE       Cx / Tr / tr.{hit,put,put2,emit,go,show,   :38-55 the five calls, the
#               tagname,one,sep,at,put_seq,fail}           refusals, the render
#               rp.{record..trace,wp2,wp3,put_wp,barrier,
#               bump,door,bumped,bumped2,cont_n,cont_more,
#               cont_func,rx_up,rx_elems,rx_after,rx_tag}
#   RPC         rpc.{func_alloc,am2,am3,minted,wait,       :526-536 alloc, :534 send,
#               raise,raise2,ra_plen,rc_plen,runlist_key,  :535 wait, :84 the raise,
#               nvdec_add,nvdec0,runlist_miss}              :557 the runlist addend
#               am.{page_ok,pages_ok2,pages_ok4,plen}      :527 the page assert
#               hgen.{first,next,n,nxt7,go}                :348 the handle generator
#   FALCON      fl.{frts_offset,desc_sig,order,falcon,    :186-283 the register order
#               sec2,ctx_dma,imem,sec,dmactl,allow_phys,
#               reset_engines,dma_chunk,chunks,alias,
#               startcpu,riscv_core1,riscv_core0,init_n,
#               init_order}                               :212-234
#   WPR META    wpr.{leg..leg9,fmc} / over.fixtures_fit   :434-455 both branches
#   LIBOS       radix.{npages,offs}                        :401-423
#               bdf.{lo,mid,fn,as_int}                      :605 :608
#   PMA         pma.{is_one,phys,nomap,ro,flags,all_ones}  :345 the flag shifts
#   CLASSES     cls.{one,gpfifo,compute,dma,viddec,gp2,    :538-569
#               cp2,dm2,vd2,join4,row}
#   REGISTRY    ctx.{go,idxlist,keys3,rows,cfg_rows}       :616-627 the whole layout
#   CPU SEQ     seq.{n,words,name,ops,count,walk,prog_n,   :629-661 the opcode table,
#               prog_ops,wordlist,join,joinu,at,next_skip,  the walk, the five ops
#               put,opslist,join5} / seq_walk.go
#   FSP         fsp.{w0,w1,pad,tot,words,tail,head,        :328-344 the framing and
#               tail_off,aincw,aincr,trace,tr2,tr3,put,     the four calls in order
#               ememd,do_tail,do_head,nvmd_cot}
#   GRCTX       grctx.{keylist,keys,walk,row,size,virt,    :468-508 the map, the
#               phys,local,n,sep,tag,reuse,reuses_10,        GRBufDesc table
#               count_local,early,early2,join,join1,local_n}
#   DOORBELL    door.{bit30,rl_shift,gb2_bit,token}        :590-591 the token
#   INIT ORDER  gsp.{init_order,init_n,priv_root}           :444-455, :519
#   REFUSALS    ref.{bit_sig,wpr2,mbx,active,fsp_len,      :123, :194, :207, :210,
#               frts,mailbox,pages_ok,pages_go,bad_op,       :332, :453, :527, :660,
#               timeout}                                     :661, :91
#   GATE        t_tables / t_arith / t_trace / t_refuse / t_misc / main
#
# NOT PORTED, and each one is a SEAM or a WALL, never a simplification:
#   the device MMIO map and every register value written to it
#   the VBIOS byte scan at :110-169 -- the offsets are ported, the bytes are not
#   the payload bytes of every RPC (:526-569 assemble the framing, the fields are
#     the device's) and the `pay` term of the checksum fold
#   the one 64-BIT CONSTANT that does not fit a U32
#   `init_sw` and `init_hw` themselves, which are no-ops plus an include list --
#     the include ORDER is ported as data and the includes are not
# ---------------------------------------------------------------------------
# THE MUTATION TABLE, in prose, because the file itself is the thing under test.
#
# `python3 .agents/slop/nv_ip_mutate.py` applies ONE textual edit per rule to this
# file, runs the interpreted lane, and records how many rows moved. Thirty-seven
# mutations: thirty-three move at least one row, and FOUR cannot move any row
# because the mutant is the same function.
#
#   rd.trunc            `x - x%m` for `x/m*m`. Euclidean division gives
#                       x == q*m + r with 0 <= r < m, so subtracting r gives q*m.
#   rp.cont_more.ge     `>` -> `>=`. At plen == max_payload both guards reach
#                       `cdiv(0, max_payload) == 0`, so `rp.cont_n` answers 1.
#   rp.pickw.swap       exchange `hi` and `lo`. `rp.finish` XORs the two
#                       accumulators together, so permuting the twenty words
#                       between them is the identity -- the ENDIANNESS assumption
#                       is not gateable through the checksum at all.
#   rp.which.last_word  clamp 19 -> 18. Words 18 and 19 are both zero slots with
#                       no `rp.word2` arm, so both answer 0.
#
# Two fixtures closed the spots that were NOT arithmetic:
#
#   rp.elem.no_header   dropping the 32-byte header from `elemCount` moved NO
#                       rows, because all seven requests are small enough that
#                       `plen + 48` and `plen + 80` round to the same element
#                       count. The header matters only in the band
#                       `4096k - 79 <= plen <= 4096k - 49`, so `ip_rp_elem_4017`,
#                       `_4047` and `_4048` are the fixtures; it now moves four.
#   rp.word2.*          the twenty `ip_rp_<i>_w<k>` rows exist for this. The folded
#                       checksum sees the SET of words and their byte OFFSETS but
#                       not which index each came from, so pinning every index
#                       separately is what makes a zeroed arm move something.
#
# Two mutations found defects that prose did not:
#
#   rp.put_wp.arms_swapped   moved 8 rows, and found that the ONLY guard in the
#       file -- the one that stops the write pointer advancing past a refusal --
#       had its arms the wrong way round, so it did the opposite of its comment.
#       The oracle that missed it had tabulated `wp` BY HAND.
#   rpc.func_alloc.is_tag    moved 2 rows, and found `C_ALLOC_MEM()` passed to
#       `rp.record` WHERE PYTHON PASSES A FUNCTION ID: the alloc trace claimed to
#       send function 8 and sent 4. The trace tag and the RPC id are different
#       things, and the holes in the tag space are where the confusion lived.
#
# `rp.seq.after_door` moves exactly ONE row, `ip_refuse_at5_seq`: the sequence bump
# sits between the barrier and the doorbell (:52, :54, :55), and rung after the
# doorbell that row would read 0. Before those rows existed the position was a
# comment, and a comment cannot fail.
#
# `const_name.last_wins` is instructive for a different reason: flipping a guard
# around the existing self-call does NOTHING, because `Bool.pick` DROPS the
# untaken arm and the fold returns at the first match without ever recursing.
# First-wins is not a policy in `const_name.go` -- it is a consequence of where
# the self-call sits, and last-wins needs the recursion to move into the CALLER.
# That is the substrate fact the whole file is built on.
# ---------------------------------------------------------------------------
# THE FOUR GATE SECTIONS, and what each one can be wrong about.
#   t_tables   the 54 layouts, the 64 constants both directions, the two
#              dispatch tables. A transposed field, a wrong offset, a wrong
#              width, a wrong constant, a wrong first-wins winner.
#   t_arith    the allocator arithmetic: queue sizing, radix3, WPR meta (both
#              branches), the registry table layout, bdf_as_int, the PMA flag
#              shifts, the ctx-buffer map, the FRTS offset.
#   t_trace    the request trace for a FIXED request list: one RPC record per
#              request, the write-pointer advance, the doorbell, the handle
#              sequence, the cpu-sequencer ops, the FSP framing, the falcon
#              register order, and the init order.
#   t_refuse   each refusal: what the trace looks like after it.
#
# 1394 rows, and BOTH lanes print the same 57 KB. `ip.py` IS IN tinygrad's tree
# at the revision this port follows, so every expectation in the gate was
# produced by CALLING CPython on it -- never typed. Five units have now been
# bitten by a hand-typed expectation, and the fifth was the worst: the Stage E
# trace truncations were tabulated by hand, the table had the fault position
# backwards, and so it AGREED with a port whose write-pointer guard was
# inverted -- five green rows over a bug. `.agents/slop/nv_ip_oracle4.py` now
# EXECUTES `_send_rpc_record` with the fault raised and reads `tx.writePtr` off
# the struct, and a table of expected values cannot be wrong in the same way
# twice. The CPython runs are `nv_ip_gen.py`, `nv_ip_oracle.py`,
# `nv_ip_oracle3.py` and `nv_ip_oracle4.py`, all in the tree.
# ===========================================================================
