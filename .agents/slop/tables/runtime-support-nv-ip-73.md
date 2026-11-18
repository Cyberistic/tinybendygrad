<!-- FROM: tinybendygrad/runtime/support/nv/ip.bend:73 -->
# BLOCK:
# WHAT IS PORTED, DEF BY DEF. Every def named here EXISTS; the first draft of this
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
# END BLOCK
