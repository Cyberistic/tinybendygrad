# tinybendygrad/runtime/support/nv/ip.bend -- port of tinygrad/runtime/support/nv/ip.py
#

# WHAT THIS FILE ACTUALLY IS, because the name misleads.
#
# `nv/ip.py` is NOT the NVOS ioctl attribute file. There is no `nv_ioctl`, no
# NV2080_ALLOC_MEMORY attribute table and no channel/allocation bitmask table in
# it: all of those live in `tinygrad/runtime/autogen/nv.py` and `nv_570.py`,
# which are GENERATED ctypes bindings. What ip.py is -- and what this file
# ports -- is the GSP RPC RING PROTOCOL and the two bootloaders that drive it:
#
#   * `NVRpcQueue` (:19-91) -- the msgqTxHeader ring, the RPC record layout, the
#     u64 checksum, the write-pointer advance, the wrap-around copy, the
#     response read and the wait.
#   * `NV_FLCN` (:93-283) -- pulling the Falcon ucode and booter out of VBIOS
#     and a `booter_load` image, and the DMA/start/halt sequence that runs one.
#   * `NV_FLCN_COT` (:285-344) -- the FSP message framing and the COT payload.
#   * `NV_GSP` (:346-661) -- the radix3 page tree, the WPR meta layout, the RM
#     alloc/control RPCs, the registry table, and the cpu-sequencer opcode
#     dispatch.
#
# So the STRUCT FIELD LAYOUTS this file uses are the load-bearing part, and they
# are all here under THE LAYOUTS: 54 ctypes structs, 413 fields, in declaration
# order, with byte offsets and widths. The generated block below is that
# transcription; `.agents/slop/nv_ip_gen.py` produced it out of CPython with no
# device present, and produced the gate rows from the same run.
#

# A disagreement with the task brief, REPORTED not reconciled.
#
# The brief said `ops_nv.bend` (3960 lines at this commit, committed, green) cites
# `nv/ip.py` by line and that those citations "point at nothing" until this file
# exists. IT DOES NOT. Measured:
#
#     $ grep -n "nv/ip\|nv_ip" tinybendygrad/runtime/ops_nv.bend   -> no hits
#     $ grep -c "nv/ip\|nv_ip" ops_nv.bend                          -> 0
#     $ grep -o "[A-Za-z0-9_/]*\.py" ops_nv.bend | sort | uniq -c
#        22 ops_nv.py   10 hcq2.py    2 tinygrad/runtime/ops_nv.py
#         2 realize.py   1 support/elf.py  1 oracle.py  1 mutate.py
#         1 helpers.py   1 diff.py     1 device.py    1 autogen/nv_570.py
#         1 tinygrad/runtime/autogen/nv_570.py
#
# `ops_nv.bend` cites `hcq2.py` ten times and `ops_nv.py` twenty-two, and
# `nv/ip.py` ZERO times. So there is no wall or row in that file for this port to
# contradict, and nothing in it constrains the choices below. That is the honest
# finding; it is not the same as agreement, and no row here is offered as
# corroboration of anything in ops_nv.bend.
#

# THE shared contract with hcq2, AND why it is not settled yet.
#
# `hcq2.py` overlaps this file on exactly one thing: the GSP command queue this
# file drives (`cmd_q`/`stat_q`, :387/:511) and the doorbell
# `NV_PGSP_QUEUE_HEAD[0].write(0x0)` at :55. RETIRED WALL, and this is what
# stub. It is 2272 lines with 284 defs and prints 360 gate rows, so there IS a
# second table and it CAN be contradicted. MEASURED against it: hcq2 prints no
# row for the ring's usable length, the wrap threshold or the msgqTxHeader
# field order, so nothing here is contradicted YET and nothing here is
# corroborated either -- "no row" is not "agreement". What this port fixes,
# and what the hcq2 port must agree with or report, is:
#
#   1. The queue header is `nv.msgqTxHeader` -- (version, size, msgSize,
#      msgCount, writePtr, flags, rxHdrOff, entryOff), 32 bytes, and
#      :384-385 writes (0, queue_size, 0x1000, (queue_size-0x1000)//0x1000, 0, 1,
#      sizeof(msgqTxHeader)). `q.of` is that and nothing else, and the `Q`
#      record's field order is the port's `Q.*` readers.
#   2. The ring's usable length is `msgSize*msgCount`, and the wrap threshold is
#      `wp*msgSize + msgSize*msgCount` -- i.e. `ring_len`, NOT `size`. :30 slices
#      the ring at `entryOff` but tinygrad/runtime/support/nv/ip.py:48 measures the wrap against `queue_mv`,
#      `len(self.queue_mv)`, which is `msgSize*msgCount`. `Q.ring_len` is the
#      second number and `Q.rx_hdr_off` is the first; a port that confuses them
#      readers that were never written; the contract above is carried by
#      `q.of` plus the `Q` record's own field order.)
#   3. The doorbell is a write of 0x0, once per RPC record, AFTER the write
#      pointer is advanced. Order is the gate; the rows are `ip_rp_*_order`
#      (the whole `send/qwrite/qwp/barrier/doorbell/wait` sequence as one
#      string) and `ip_door_*` (the value and the two architecture bits).
#

# THE SPLIT, stated once and then obeyed: a def here EITHER builds the argument
# of ONE call (pure, and the gate checks it) OR records that call in the trace
# (and the gate checks the ORDER). There is no third kind. Every seam is a trace
# tag and nothing else, so ORDER and IDENTITY are gateable even though none of
# the calls is made here.
#
# THE RAISE IS IN THE TRACE. `Tr.emit` records nothing once the seam has
# reported a failure, so a refusal shows up as a TRUNCATED trace and needs no
# guard of its own anywhere downstream. The failing call IS recorded -- it is
# what the seam refused -- so the rule is the same one ops_webgpu.bend uses for
# its four pop sites, and the row that pins it is named `ip_refuse_*`.
#


# THE SEAMS, named with their Python lines. These are FFI, not logic.
#
#   * every `ctypes` struct construction, and `bytes(x)`: the field VALUES are
#     real ctypes writes into a real buffer. This port reproduces the layouts
#     (THE LAYOUTS) and the U32-representable field values, and the ctypes
#     marshalling itself is the seam.
#       # TODO(p3) support/nv/ip.py:39  symbol=_send_rpc_record  rpc_message_header_v(...)
#       # TODO(p3) support/nv/ip.py:43  symbol=_send_rpc_record  GSP_MSG_QUEUE_ELEMENT(...)
#       # TODO(p3) support/nv/ip.py:146  symbol=prep_ucode FWSECLIC_READ_VBIOS_DESC(...)
#       # TODO(p3) support/nv/ip.py:147  symbol=prep_ucode FWSECLIC_FRTS_REGION_DESC(...)
#       # TODO(p3) support/nv/ip.py:374  symbol=init_rm_args MESSAGE_QUEUE_INIT_ARGUMENTS(...)
#       # TODO(p3) support/nv/ip.py:394  symbol=init_libos_args LibosMemoryRegionInitArgument(...)
#       # TODO(p3) support/nv/ip.py:438  symbol=init_wpr_meta GspFwWprMeta(common, ...)
#       # TODO(p3) support/nv/ip.py:530 rpc_alloc_memory_v(...)
#       # TODO(p3) support/nv/ip.py:551  symbol=rpc_rm_alloc rpc_gsp_rm_alloc_v(...)
#       # TODO(p3) support/nv/ip.py:582  symbol=rpc_rm_control rpc_gsp_rm_control_v(...)
#       # TODO(p3) support/nv/ip.py:595  symbol=rpc_set_page_directory struct_NV0080_CTRL_DMA_SET_PAGE_DIRECTORY_...
#       # TODO(p3) support/nv/ip.py:597 rpc_set_page_directory_v(...)
#       # TODO(p3) support/nv/ip.py:605  symbol=rpc_set_gsp_system_info GspSystemInfo(...)
#       # TODO(p3) support/nv/ip.py:612 rpc_unloading_guest_driver_v(...)
#       # TODO(p3) support/nv/ip.py:622  symbol=rpc_set_registry_table PACKED_REGISTRY_ENTRY(...)
#       # TODO(p3) support/nv/ip.py:626  symbol=rpc_set_registry_table PACKED_REGISTRY_TABLE(...)
#
#   * the `/dev/nvidia*` fds and the `nvdev` register file. `nvdev.include(...)`
#     (:99-105), `nvdev.wreg`/`rreg` (:231,:637), every `NV_P*` register, the
#     `mmio` views (:111) and `_alloc_boot_mem` (:167) are device memory this
#     file cannot reach.
#       # TODO(p3) support/nv/ip.py:99   self.nvdev.include("dev_gsp", "ga102")
#       # TODO(p3) support/nv/ip.py:111  symbol=prep_ucode  self.nvdev.mmio[0x300000//4:...]
#       # TODO(p3) support/nv/ip.py:167  symbol=__patch  self.nvdev._alloc_boot_mem(...)
#       # TODO(p3) support/nv/ip.py:199  symbol=init_hw  self.nvdev.NV_PGSP_FALCON_MAILBOX0.write
#
#   * `fetch_fw` (:174,:303,:402,:429) and `elf_loader` (:303) -- firmware
#     download and ELF parsing. The offsets read OUT of their results are
#     arithmetic and are ported (`prep_booter`, `init_gsp_image`,
#     `init_boot_binary_image`); the download and the parse are the seam.
#       # TODO(p3) support/nv/ip.py:174  symbol=prep_booter  fetch_fw(... "booter_load-570.144.bin" ...)
#       # TODO(p3) support/nv/ip.py:303  symbol=init_fmc_image  elf_loader(fetch_fw(... "fmc-570.144.bin" ...))
#       # TODO(p3) support/nv/ip.py:402  symbol=init_gsp_image  elf_loader(fetch_fw(... "gsp-570.144.bin" ...))
#       # TODO(p3) support/nv/ip.py:429  symbol=init_boot_binary_image  fetch_fw(... "bootloader-570.144.bin" ...)
#
#   * `wait_cond` (:22,:96,:213,:277,:288,:326,:640), `time.sleep` (:274,:641)
#     and `System.memory_barrier` (:52,:63,:78). `System.memory_barrier` IS a
#     trace call -- it is `C_BARRIER`, and its POSITION between the pointer store
#     and the doorbell is what `ip_tr_<i>_order` pins. `wait_resp` (:87-91) is a
#     trace call too (`C_WAIT_RESP`, then `C_RPC_RAISE` on the timeout). The
#     POLLING LOOPS are not: `wait_cond` and `time.sleep` are the seam, and no
#     trace tag claims to be either of them.
#       # TODO(p3) support/nv/ip.py:22  symbol=__init__   wait_cond(... "RPC queue not initialized")
#       # TODO(p3) support/nv/ip.py:52  symbol=_send_rpc_record   System.memory_barrier()  [PORTED: C_BARRIER]
#       # TODO(p3) support/nv/ip.py:274  time.sleep(0.1)
#       # TODO(p3) support/nv/ip.py:640  symbol=run_cpu_seq  wait_cond(lambda a, m: ...)
#
#   * the VBIOS scan (:110-143). It walks a firmware image with a
#     `match/case` over two code types and then walks three token tables; the
#     WALKS are over bytes this file does not have. The one thing ported is the
#     arithmetic that survives without the bytes -- `frts_offset` (:145),
#     `desc_v3` size arithmetic (tinygrad/runtime/support/nv/ip.py:139-143) -- and the refusal
#     at tinygrad/runtime/support/nv/ip.py:123 (`bit_header`).
#       # TODO(p3) support/nv/ip.py:111  symbol=prep_ucode  the PCI expansion ROM walk
#       # TODO(p3) support/nv/ip.py:123  assert bit_header.Signature == 0x00544942
#

# THE WALLS. Three, and each is named with the line that owns it.
#
# 1. THE 64-BIT WALL, in three separate places, and they are not the same place.
#    `base.bend` exports no 64-bit integer, so:
#      - `GSP_FW_WPR_META_MAGIC` = 15869187694674993331 (:442). ONE of the 65
#        integer constants ip.py names does not fit a U32. `ip_c_over64` names
#        it; it is not ported, and the WPR meta builder records the field as the
#        seam's.
#      - `maxUserVa=0x7ffffffff000` (:608) and the four `gpuPhys*Addr` fields of
#        `GspSystemInfo` (:605). Their OFFSETS and WIDTHS are in the layout table
#        -- 8-byte fields at their byte offsets -- and their VALUES are the
#        seam's. `GspSystemInfo` is 48 fields and 928 bytes and the port knows
#        all of that.
#      - `_checksum` (:32-36) sums u64 words. This one is NOT a wall and the
#        reason is the whole reason the checksum gate is worth having: the
#        accumulator is a XOR and `hi32(x) ^ lo32(x)` COMMUTES with XOR over the
#        words, so the whole checksum collapses to two U32 folds over the
#        TWENTY U32 words of `GSP_MSG_QUEUE_ELEMENT ++ rpc_message_header_v`.
#        `rp.cksum.xor` does that, and it needs the byte OFFSETS -- so it fails
#        on a wrong field order and a wrong offset, which a count gate would not.
#        It does NOT fail on a wrong endianness, because XOR is commutative: the
#        mutation table records the exchange of `rp.pickw`'s arms as an equivalent
#        mutant, and the comment above `rp.pickw` says so where a reader needs it.
#
#    Two more 64-bit facts live where they bite rather than here, because each is
#    one arithmetic chain and not a type boundary:
#      - `init_wpr_meta` (:434-455) SUBTRACTS from `vram_size`, so every offset it
#        computes exceeds 2**32 for any real card. See THE FIXTURES beside
#        `wpr.leg4` and `ip_wpr_vram_max`.
#      - `id8=int.from_bytes(bytes(f"LOG{name}", 'utf-8'), 'big')` (:395) is an
#        EIGHT-BYTE name read big-endian. See the note beside `libos` and
#        `ip_libos_id8_bytes`.
#      # TODO(p3) support/nv/ip.py:442  symbol=init_wpr_meta  GSP_FW_WPR_META_MAGIC
#      # TODO(p3) support/nv/ip.py:605  symbol=rpc_set_gsp_system_info  GspSystemInfo.gpuPhysAddr / maxUserVa
#
# 2. THE DICT WALL, and it is a soft one. `self.chan_runlists` (:348),
#    `self.runlists` (:475), `self.grctx_bufs` (:501), `ctxbufs` (:457) and the
#    `table` in `rpc_set_registry_table` (:617) are Python dicts, so they are
#    INSERTION-ORDERED, and two of them are read with a MISS HANDLER that
#    returns a default (`self.runlists.get(..., 0)` :557,
#    `(bufs or {}).get(buf, ...) :461`). That site is upstream's `promote_ctx`
#    (tinygrad/runtime/support/nv/ip.py:457 symbol=promote_ctx), and the port's
#    `List` here is the same information
#    plus an explicit key list, and every miss is an explicit arm. What is lost
#    is dict ITERATION order under mutation, which none of these sites relies on.
#
# 3. THE GENERATOR WALL. `self.nvdev.include("dev_gsp", "ga102")` (:99-105)
#    pulls a device REGISTER MAP at run time, and that map is where
#    `NV_PFALCON_FALCON_DMATRFCMD_SIZE_256B`, `..._MEM_TYPE_PHYSICAL` and
#    `NV_PFALCON2_FALCON_MOD_SEL_ALGO_RSA3K` come from -- `autogen/nv_570.py`
#    is not enough for them. So those three constants are NOT PORTED here and
#    NOT in `nv_ip_tables.bend`: they belong to whoever ports `ops_nv.py`'s
#    register table, and `fl.dma_chunk` takes its bit positions as parameters
#    for exactly that reason.
#      # TODO(p3) support/nv/ip.py:242  symbol=execute_hs  NV_PFALCON_FALCON_DMATRFCMD.encode(...)
#      # TODO(p3) support/nv/ip.py:253  symbol=execute_hs  NV_PFALCON2_FALCON_MOD_SEL_ALGO_RSA3K
#      # TODO(p3) support/nv/ip.py:99   the register map `include` produces
#
# CTYPES SHAPING is not a wall and is named once: `(FALCON_APPLICATION_INTERFACE_ENTRY_V1
# * hdr.entryCount)(...)` at :156 spells "an array of n descriptors", so the
# layout of `FALCON_APPLICATION_INTERFACE_ENTRY_V1` is one row of the table and
# the array is a `List`. `memoryview(...).cast('I'/'Q')` (tinygrad/runtime/support/nv/ip.py:306) is the
# same statement about width.
#


# STATUS
#   PORTED:      see WHAT IS PORTED, DEF BY DEF, below.
#   NOT PORTED:  the seams and the three walls above, each with a Python line.
#   PYTHON:      tinygrad/runtime/support/nv/ip.py:1-661 (the whole file)
#
# WHAT IS PORTED, DEF BY DEF. Every def named here EXISTS; the first draft of this
# table named forty-eight defs that were never written -- a device-init entry, a
# queue reader, a WPR-meta builder, a dispatch table -- which is what a plan
# written before the code looks like from the outside. The names below are the
# file's own namespaces.
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
# 1428 rows, and BOTH lanes print the same 57 KB. `ip.py` IS IN tinygrad's tree
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


import Base
import ../../../helpers.bend as H
import ../../../device.bend as D


# GENERATED by .agents/slop/nv_ip_gen.py. DO NOT HAND-EDIT -- if a row and this
# table disagree, one of the two is a transcription error and the differ says which.
# Every value below was read out of tinygrad/runtime/autogen/{nv,nv_570,pci}.py
# by that script, with NO DEVICE PRESENT.


# The 64 integer constants ip.py names that FIT a U32. A 1-th does not and is
# the 64-BIT WALL -- see THE WALLS in the file header. `Cn` IS the table, so the
# gate can ask for a value FROM a name and a name FROM a value over ONE transcription.
#
# The reverse arm is FIRST-WINS, and 8 names share the value 1:
#   GSP_DMA_TARGET_COHERENT_SYSTEM
#   GSP_FW_WPR_META_REVISION
#   LIBOS_MEMORY_REGION_CONTIGUOUS
#   LIBOS_MEMORY_REGION_LOC_SYSMEM
#   NVOS02_FLAGS_ALLOC_USER_READ_ONLY_YES
#   NVOS02_FLAGS_MAPPING_NO_MAP
#   NVOS02_FLAGS_PHYSICALITY_NONCONTIGUOUS
#   REGISTRY_TABLE_ENTRY_TYPE_DWORD
# so the generated (name-sorted) order is load-bearing for `const_name`.
# `ip_c_one_first` pins the winner and `ip_c_one_n` pins how many it beat.
type Cn is Data:
  Cn{name: String, v: U32}


def Cn.of(n: String, v: U32) -> Cn:
  Cn{n, v}


def Cn.name(c: Cn) -> String:
  match c:
    case Cn{+name, v}: name


def Cn.v(c: Cn) -> U32:
  match c:
    case Cn{name, +v}: v


def cn_table() -> List<&2, Cn>:
  List.concat(&2, Cn, [
    [Cn.of("ADA_COMPUTE_A", 51648), Cn.of("AMPERE_CHANNEL_GPFIFO_A", 50543), Cn.of("AMPERE_COMPUTE_B",
    51136)], [Cn.of("AMPERE_DMA_COPY_B", 51125), Cn.of("BIT_DATA_FALCON_DATA_V2_SIZE_4", 4),
    Cn.of("BIT_TOKEN_FALCON_DATA", 112)], [Cn.of("BLACKWELL_CHANNEL_GPFIFO_A", 51567),
    Cn.of("BLACKWELL_COMPUTE_B", 52928), Cn.of("BLACKWELL_DMA_COPY_B", 51893)],
    [Cn.of("FALCON_APPLICATION_INTERFACE_ENTRY_ID_DMEMMAPPER", 4), Cn.of("FALCON_UCODE_DESC_V3_SIZE_44", 44),
    Cn.of("FALCON_UCODE_ENTRY_APPID_FWSEC_PROD", 133)], [Cn.of("FERMI_VASPACE_A", 37105),
    Cn.of("GSP_DMA_TARGET_COHERENT_SYSTEM", 1), Cn.of("GSP_FW_WPR_META_REVISION", 1)],
    [Cn.of("LIBOS_MEMORY_REGION_CONTIGUOUS", 1), Cn.of("LIBOS_MEMORY_REGION_LOC_SYSMEM", 1),
    Cn.of("LIBOS_MEMORY_REGION_RADIX_PAGE_LOG2", 12)],
    [Cn.of("NV0080_CTRL_FIFO_GET_ENGINE_CONTEXT_PROPERTIES_ENGINE_ID_GRAPHICS", 0),
    Cn.of("NV0080_CTRL_FIFO_GET_ENGINE_CONTEXT_PROPERTIES_ENGINE_ID_GRAPHICS_PATCH", 16),
    Cn.of("NV01_DEVICE_0", 128)], [Cn.of("NV01_MEMORY_LIST_SYSTEM", 129), Cn.of("NV1_ROOT", 0),
    Cn.of("NV2080_CTRL_CMD_FIFO_GET_DEVICE_INFO_TABLE", 545263890)], [Cn.of("NV2080_CTRL_CMD_GPU_PROMOTE_CTX",
    545259819), Cn.of("NV2080_CTRL_CMD_INTERNAL_STATIC_KGR_GET_CONTEXT_BUFFERS_INFO", 545262130),
    Cn.of("NV2080_ENGINE_TYPE_NVDEC0", 19)], [Cn.of("NV20_SUBDEVICE_0", 8320),
    Cn.of("NV90F1_CTRL_CMD_VASPACE_COPY_SERVER_RESERVED_PDES", 2431713542),
    Cn.of("NVB0CC_CTRL_CMD_ALLOC_PMA_STREAM", 2966159621)],
    [Cn.of("NVB0CC_CTRL_CMD_INTERNAL_PERMISSIONS_INIT", 2966159875),
    Cn.of("NVB0CC_CTRL_CMD_POWER_REQUEST_FEATURES", 2966160129),
    Cn.of("NVC36F_CTRL_CMD_GPFIFO_GET_WORK_SUBMIT_TOKEN", 3278831880)], [Cn.of("NVC9B0_VIDEO_DECODER", 51632),
    Cn.of("NVCFB0_VIDEO_DECODER", 53168), Cn.of("NVDM_TYPE_COT", 20)],
    [Cn.of("NVOS02_FLAGS_ALLOC_USER_READ_ONLY_YES", 1), Cn.of("NVOS02_FLAGS_MAPPING_NO_MAP", 1),
    Cn.of("NVOS02_FLAGS_PHYSICALITY_NONCONTIGUOUS", 1)], [Cn.of("NV_BCRT_HASH_INFO_BASE_CODE_TYPE_VBIOS_BASE",
    0), Cn.of("NV_BCRT_HASH_INFO_BASE_CODE_TYPE_VBIOS_EXT", 224), Cn.of("NV_VGPU_MSG_EVENT_GSP_INIT_DONE",
    4097)], [Cn.of("NV_VGPU_MSG_EVENT_GSP_RUN_CPU_SEQUENCER", 4098),
    Cn.of("NV_VGPU_MSG_EVENT_MMU_FAULT_QUEUED", 4101), Cn.of("NV_VGPU_MSG_EVENT_OS_ERROR_LOG", 4102)],
    [Cn.of("NV_VGPU_MSG_FUNCTION_ALLOC_MEMORY", 4), Cn.of("NV_VGPU_MSG_FUNCTION_CONTINUATION_RECORD", 71),
    Cn.of("NV_VGPU_MSG_FUNCTION_GSP_RM_ALLOC", 103)], [Cn.of("NV_VGPU_MSG_FUNCTION_GSP_RM_CONTROL", 76),
    Cn.of("NV_VGPU_MSG_FUNCTION_GSP_SET_SYSTEM_INFO", 72), Cn.of("NV_VGPU_MSG_FUNCTION_SET_PAGE_DIRECTORY",
    54)], [Cn.of("NV_VGPU_MSG_FUNCTION_SET_REGISTRY", 73),
    Cn.of("NV_VGPU_MSG_FUNCTION_UNLOADING_GUEST_DRIVER", 47), Cn.of("NV_VGPU_MSG_RESULT_RPC_PENDING",
    4294967295)], [Cn.of("NV_VGPU_MSG_SIGNATURE_VALID", 1129337430), Cn.of("NV_VGPU_PTEDESC_IDR_NONE", 0),
    Cn.of("OFFSETOF_PCI_DATA_STRUCT_CODE_TYPE", 20)], [Cn.of("OFFSETOF_PCI_DATA_STRUCT_IMAGE_LEN", 16),
    Cn.of("OFFSETOF_PCI_EXP_ROM_PCI_DATA_STRUCT_PTR", 24), Cn.of("PCI_REVISION_ID", 8)],
    [Cn.of("PCI_ROM_IMAGE_BLOCK_SIZE", 512), Cn.of("PCI_SUBSYSTEM_VENDOR_ID", 44), Cn.of("PCI_VENDOR_ID", 0)],
    [Cn.of("REGISTRY_TABLE_ENTRY_TYPE_DWORD", 1)],
  ])


# ONE ctypes struct ip.py names: SIZE, the field COUNT, and the fields as
# "name@offset:bytes" IN DECLARATION ORDER.
#
# ORDER and width are the whole point. A transposed pair is a silently wrong
# register write, and a COUNT gate cannot see a transposition -- which is why
# each struct is one row carrying names, order, offsets AND widths at once, and
# `nf` is a SECOND, INDEPENDENT transcription of the field count (so a dropped
# or duplicated name in the string is caught by the count row and vice versa).
type St is Data:
  St{nm: String, nf: U32, size: U32, fields: String}


def St.nm(s: St) -> String:
  match s:
    case St{+nm, nf, size, fields}: nm


def St.fields(s: St) -> String:
  match s:
    case St{nm, nf, size, +fields}: fields


def St.nf(s: St) -> U32:
  match s:
    case St{nm, +nf, size, fields}: nf


def St.size(s: St) -> U32:
  match s:
    case St{nm, nf, +size, fields}: size

def st_msgqTxHeader() -> St:
  St{"msgqTxHeader", 8, 32, "version@0:4,size@4:4,msgSize@8:4,msgCount@12:4,writePtr@16:4,flags@20:4,rxHdrOff@24:4,entryOff@28:4"}


def st_rpc_message_header_v() -> St:
  St{"rpc_message_header_v", 8, 32, "header_version@0:4,signature@4:4,length@8:4,function@12:4,rpc_result@16:4,rpc_result_private@20:4,sequence@24:4,u@28:4"}


def st_GSP_MSG_QUEUE_ELEMENT() -> St:
  St{"GSP_MSG_QUEUE_ELEMENT", 6, 48, "authTagBuffer@0:16,aadBuffer@16:16,checkSum@32:4,seqNum@36:4,elemCount@40:4,padding@44:4"}


def st_BIT_HEADER_V1_00() -> St:
  St{"BIT_HEADER_V1_00", 7, 12, "Id@0:2,Signature@2:4,BCD_Version@6:2,HeaderSize@8:1,TokenSize@9:1,TokenEntries@10:1,HeaderChksum@11:1"}


def st_BIT_TOKEN_V1_00() -> St:
  St{"BIT_TOKEN_V1_00", 4, 8, "TokenId@0:1,DataVersion@1:1,DataSize@2:2,DataPtr@4:4"}


def st_BIT_DATA_FALCON_DATA_V2() -> St:
  St{"BIT_DATA_FALCON_DATA_V2", 1, 4, "FalconUcodeTablePtr@0:4"}


def st_FALCON_UCODE_TABLE_HDR_V1() -> St:
  St{"FALCON_UCODE_TABLE_HDR_V1", 6, 6, "Version@0:1,HeaderSize@1:1,EntrySize@2:1,EntryCount@3:1,DescVersion@4:1,DescSize@5:1"}


def st_FALCON_UCODE_TABLE_ENTRY_V1() -> St:
  St{"FALCON_UCODE_TABLE_ENTRY_V1", 3, 6, "ApplicationID@0:1,TargetID@1:1,DescPtr@2:4"}


def st_FALCON_UCODE_DESC_HEADER() -> St:
  St{"FALCON_UCODE_DESC_HEADER", 1, 4, "vDesc@0:4"}


def st_FALCON_UCODE_DESC_V3() -> St:
  St{"FALCON_UCODE_DESC_V3", 14, 44, "Hdr@0:4,StoredSize@4:4,PKCDataOffset@8:4,InterfaceOffset@12:4,IMEMPhysBase@16:4,IMEMLoadSize@20:4,IMEMVirtBase@24:4,DMEMPhysBase@28:4,DMEMLoadSize@32:4,EngineIdMask@36:2,UcodeId@38:1,SignatureCount@39:1,SignatureVersions@40:2,Reserved@42:2"}


def st_FWSECLIC_READ_VBIOS_DESC() -> St:
  St{"FWSECLIC_READ_VBIOS_DESC", 5, 24, "version@0:4,size@4:4,gfwImageOffset@8:8,gfwImageSize@16:4,flags@20:4"}


def st_FWSECLIC_FRTS_REGION_DESC() -> St:
  St{"FWSECLIC_FRTS_REGION_DESC", 5, 20, "version@0:4,size@4:4,frtsRegionOffset4K@8:4,frtsRegionSize@12:4,frtsRegionMediaType@16:4"}


def st_FWSECLIC_FRTS_CMD() -> St:
  St{"FWSECLIC_FRTS_CMD", 2, 44, "readVbiosDesc@0:24,frtsRegionDesc@24:20"}


def st_FALCON_APPLICATION_INTERFACE_HEADER_V1() -> St:
  St{"FALCON_APPLICATION_INTERFACE_HEADER_V1", 4, 4, "version@0:1,headerSize@1:1,entrySize@2:1,entryCount@3:1"}


def st_FALCON_APPLICATION_INTERFACE_ENTRY_V1() -> St:
  St{"FALCON_APPLICATION_INTERFACE_ENTRY_V1", 2, 8, "id@0:4,dmemOffset@4:4"}


def st_FALCON_APPLICATION_INTERFACE_DMEM_MAPPER_V3() -> St:
  St{"FALCON_APPLICATION_INTERFACE_DMEM_MAPPER_V3", 17, 64, "signature@0:4,version@4:2,size@6:2,cmd_in_buffer_offset@8:4,cmd_in_buffer_size@12:4,cmd_out_buffer_offset@16:4,cmd_out_buffer_size@20:4,nvf_img_data_buffer_offset@24:4,nvf_img_data_buffer_size@28:4,printfBufferHdr@32:4,ucode_build_time_stamp@36:4,ucode_signature@40:4,init_cmd@44:4,ucode_feature@48:4,ucode_cmd_mask0@52:4,ucode_cmd_mask1@56:4,multiTgtTbl@60:4"}


def st_struct_nvfw_bin_hdr() -> St:
  St{"struct_nvfw_bin_hdr", 6, 24, "bin_magic@0:4,bin_ver@4:4,bin_size@8:4,header_offset@12:4,data_offset@16:4,data_size@20:4"}


def st_struct_nvfw_hs_load_header_v2() -> St:
  St{"struct_nvfw_hs_load_header_v2", 6, 20, "os_code_offset@0:4,os_code_size@4:4,os_data_offset@8:4,os_data_size@12:4,num_apps@16:4,app@20:0"}


def st_struct_nvfw_hs_header_v2() -> St:
  St{"struct_nvfw_hs_header_v2", 9, 36, "sig_prod_offset@0:4,sig_prod_size@4:4,patch_loc@8:4,patch_sig@12:4,meta_data_offset@16:4,meta_data_size@20:4,num_sig@24:4,header_offset@28:4,header_size@32:4"}


def st_struct_nvfw_hs_load_header_v2_app() -> St:
  St{"struct_nvfw_hs_load_header_v2_app", 4, 16, "offset@0:4,size@4:4,data_offset@8:4,data_size@12:4"}


def st_GSP_FMC_BOOT_PARAMS() -> St:
  St{"GSP_FMC_BOOT_PARAMS", 4, 80, "initParams@0:4,bootGspRmParams@8:32,gspRmParams@40:16,gspSpdmParams@56:24"}


def st_GSP_ACR_BOOT_GSP_RM_PARAMS() -> St:
  St{"GSP_ACR_BOOT_GSP_RM_PARAMS", 6, 32, "target@0:4,gspRmDescSize@4:4,gspRmDescOffset@8:8,wprCarveoutOffset@16:8,wprCarveoutSize@24:4,bIsGspRmBoot@28:1"}


def st_GspFwWprMeta() -> St:
  St{"GspFwWprMeta", 46, 256, "magic@0:8,revision@8:8,sysmemAddrOfRadix3Elf@16:8,sizeOfRadix3Elf@24:8,sysmemAddrOfBootloader@32:8,sizeOfBootloader@40:8,bootloaderCodeOffset@48:8,bootloaderDataOffset@56:8,bootloaderManifestOffset@64:8,sysmemAddrOfSignature@72:8,sizeOfSignature@80:8,gspFwHeapFreeListWprOffset@72:4,unused0@76:4,unused1@80:8,gspFwRsvdStart@88:8,nonWprHeapOffset@96:8,nonWprHeapSize@104:8,gspFwWprStart@112:8,gspFwHeapOffset@120:8,gspFwHeapSize@128:8,gspFwOffset@136:8,bootBinOffset@144:8,frtsOffset@152:8,frtsSize@160:8,gspFwWprEnd@168:8,fbSize@176:8,vgaWorkspaceOffset@184:8,vgaWorkspaceSize@192:8,bootCount@200:8,partitionRpcAddr@208:8,partitionRpcRequestOffset@216:2,partitionRpcReplyOffset@218:2,elfCodeOffset@220:4,elfDataOffset@224:4,elfCodeSize@228:4,elfDataSize@232:4,lsUcodeVersion@236:4,partitionRpcPadding@208:16,sysmemAddrOfCrashReportQueue@224:8,sizeOfCrashReportQueue@232:4,lsUcodeVersionPadding@236:4,gspFwHeapVfPartitionCount@240:1,flags@241:1,padding@242:2,pmuReservedSize@244:4,verified@248:8"}


def st_GSP_RM_PARAMS() -> St:
  St{"GSP_RM_PARAMS", 2, 16, "target@0:4,bootArgsOffset@8:8"}


def st_NVDM_PAYLOAD_COT() -> St:
  St{"NVDM_PAYLOAD_COT", 11, 860, "version@0:2,size@2:2,gspFmcSysmemOffset@4:8,frtsSysmemOffset@12:8,frtsSysmemSize@20:4,frtsVidmemOffset@24:8,frtsVidmemSize@32:4,hash384@36:48,publicKey@84:384,signature@468:384,gspBootArgsSysmemOffset@852:8"}


def st_MESSAGE_QUEUE_INIT_ARGUMENTS() -> St:
  St{"MESSAGE_QUEUE_INIT_ARGUMENTS", 4, 32, "sharedMemPhysAddr@0:8,pageTableEntryCount@8:4,cmdQueueOffset@16:8,statQueueOffset@24:8"}


def st_GSP_ARGUMENTS_CACHED() -> St:
  St{"GSP_ARGUMENTS_CACHED", 5, 72, "messageQueueInitArguments@0:32,srInitArguments@32:12,gpuInstance@44:4,bDmemStack@48:1,profilerArgs@56:16"}


def st_LibosMemoryRegionInitArgument() -> St:
  St{"LibosMemoryRegionInitArgument", 5, 32, "id8@0:8,pa@8:8,size@16:8,kind@24:1,loc@25:1"}


def st_RM_RISCV_UCODE_DESC() -> St:
  St{"RM_RISCV_UCODE_DESC", 21, 84, "version@0:4,bootloaderOffset@4:4,bootloaderSize@8:4,bootloaderParamOffset@12:4,bootloaderParamSize@16:4,riscvElfOffset@20:4,riscvElfSize@24:4,appVersion@28:4,manifestOffset@32:4,manifestSize@36:4,monitorDataOffset@40:4,monitorDataSize@44:4,monitorCodeOffset@48:4,monitorCodeSize@52:4,bIsMonitorEnabled@56:4,swbromCodeOffset@60:4,swbromCodeSize@64:4,swbromDataOffset@68:4,swbromDataSize@72:4,fbReservedSize@76:4,bSignedAsCode@80:4"}


def st_NV2080_CTRL_GPU_PROMOTE_CTX_PARAMS() -> St:
  St{"NV2080_CTRL_GPU_PROMOTE_CTX_PARAMS", 10, 560, "engineType@0:4,hClient@4:4,ChID@8:4,hChanClient@12:4,hObject@16:4,hVirtMemory@20:4,virtAddress@24:8,size@32:8,entryCount@40:4,promoteEntry@48:512"}


def st_NV2080_CTRL_GPU_PROMOTE_CTX_BUFFER_ENTRY() -> St:
  St{"NV2080_CTRL_GPU_PROMOTE_CTX_BUFFER_ENTRY", 7, 32, "gpuPhysAddr@0:8,gpuVirtAddr@8:8,size@16:8,physAttr@24:4,bufferId@28:2,bInitialize@30:1,bNonmapped@31:1"}


def st_NV0000_ALLOC_PARAMETERS() -> St:
  St{"NV0000_ALLOC_PARAMETERS", 4, 120, "hClient@0:4,processID@4:4,processName@8:100,pOsPidInfo@112:8"}


def st_NV0080_ALLOC_PARAMETERS() -> St:
  St{"NV0080_ALLOC_PARAMETERS", 9, 56, "deviceId@0:4,hClientShare@4:4,hTargetClient@8:4,hTargetDevice@12:4,flags@16:4,vaSpaceSize@24:8,vaStartInternal@32:8,vaLimitInternal@40:8,vaMode@48:4"}


def st_NV2080_ALLOC_PARAMETERS() -> St:
  St{"NV2080_ALLOC_PARAMETERS", 1, 4, "subDeviceId@0:4"}


def st_NV_VASPACE_ALLOCATION_PARAMETERS() -> St:
  St{"NV_VASPACE_ALLOCATION_PARAMETERS", 7, 48, "index@0:4,flags@4:4,vaSize@8:8,vaStartInternal@16:8,vaLimitInternal@24:8,bigPageSize@32:4,vaBase@40:8"}


def st_NV2080_CTRL_FIFO_GET_DEVICE_INFO_TABLE_PARAMS() -> St:
  St{"NV2080_CTRL_FIFO_GET_DEVICE_INFO_TABLE_PARAMS", 4, 3212, "baseIndex@0:4,numEntries@4:4,bMore@8:1,entries@12:3200"}


def st_struct_NV90F1_CTRL_VASPACE_COPY_SERVER_RESERVED_PDES_PARAMS() -> St:
  St{"struct_NV90F1_CTRL_VASPACE_COPY_SERVER_RESERVED_PDES_PARAMS", 7, 184, "hSubDevice@0:4,subDeviceId@4:4,pageSize@8:8,virtAddrLo@16:8,virtAddrHi@24:8,numLevelsToCopy@32:4,levels@40:144"}


def st_struct_NV90F1_CTRL_VASPACE_COPY_SERVER_RESERVED_PDES_PARAMS_level() -> St:
  St{"struct_NV90F1_CTRL_VASPACE_COPY_SERVER_RESERVED_PDES_PARAMS_level", 4, 24, "physAddress@0:8,size@8:8,aperture@16:4,pageShift@20:1"}


def st_NV_MEMORY_DESC_PARAMS() -> St:
  St{"NV_MEMORY_DESC_PARAMS", 4, 24, "base@0:8,size@8:8,addressSpace@16:4,cacheAttrib@20:4"}


def st_NV_CHANNELGPFIFO_ALLOCATION_PARAMETERS() -> St:
  St{"NV_CHANNELGPFIFO_ALLOCATION_PARAMETERS", 27, 368, "hObjectError@0:4,hObjectBuffer@4:4,gpFifoOffset@8:8,gpFifoEntries@16:4,flags@20:4,hContextShare@24:4,hVASpace@28:4,hUserdMemory@32:32,userdOffset@64:64,engineType@128:4,cid@132:4,subDeviceId@136:4,hObjectEccError@140:4,instanceMem@144:24,userdMem@168:24,ramfcMem@192:24,mthdbufMem@216:24,hPhysChannelGroup@240:4,internalFlags@244:4,errorNotifierMem@248:24,eccErrorNotifierMem@272:24,ProcessID@296:4,SubProcessID@300:4,encryptIv@304:12,decryptIv@316:12,hmacNonce@328:32,tpcConfigID@360:4"}


def st_NV2080_CTRL_INTERNAL_STATIC_KGR_GET_CONTEXT_BUFFERS_INFO_PARAMS() -> St:
  St{"NV2080_CTRL_INTERNAL_STATIC_KGR_GET_CONTEXT_BUFFERS_INFO_PARAMS", 1, 1664, "engineContextBuffersInfo@0:1664"}


def st_rpc_alloc_memory_v() -> St:
  St{"rpc_alloc_memory_v", 10, 56, "hClient@0:4,hDevice@4:4,hMemory@8:4,hClass@12:4,flags@16:4,pteAdjust@20:4,format@24:4,length@32:8,pageCount@40:4,pteDesc@48:8"}


def st_struct_pte_desc_pte_pde() -> St:
  St{"struct_pte_desc_pte_pde", 2, 8, "pte@0:8,pde@0:8"}


def st_rpc_gsp_rm_alloc_v() -> St:
  St{"rpc_gsp_rm_alloc_v", 9, 32, "hClient@0:4,hParent@4:4,hObject@8:4,hClass@12:4,status@16:4,paramsSize@20:4,flags@24:4,reserved@28:4,params@32:0"}


def st_NVB0CC_CTRL_INTERNAL_PERMISSIONS_INIT_PARAMS() -> St:
  St{"NVB0CC_CTRL_INTERNAL_PERMISSIONS_INIT_PARAMS", 5, 5, "bAdminProfilingPermitted@0:1,bDevProfilingPermitted@1:1,bCtxProfilingPermitted@2:1,bVideoMemoryProfilingPermitted@3:1,bSysMemoryProfilingPermitted@4:1"}


def st_rpc_gsp_rm_control_v() -> St:
  St{"rpc_gsp_rm_control_v", 7, 24, "hClient@0:4,hObject@4:4,cmd@8:4,status@12:4,paramsSize@16:4,flags@20:4,params@24:0"}


def st_NVC36F_CTRL_CMD_GPFIFO_GET_WORK_SUBMIT_TOKEN_PARAMS() -> St:
  St{"NVC36F_CTRL_CMD_GPFIFO_GET_WORK_SUBMIT_TOKEN_PARAMS", 1, 4, "workSubmitToken@0:4"}


def st_struct_NV0080_CTRL_DMA_SET_PAGE_DIRECTORY_PARAMS_v1E_05() -> St:
  St{"struct_NV0080_CTRL_DMA_SET_PAGE_DIRECTORY_PARAMS_v1E_05", 7, 32, "physAddress@0:8,numEntries@8:4,flags@12:4,hVASpace@16:4,chId@20:4,subDeviceId@24:4,pasid@28:4"}


def st_rpc_set_page_directory_v() -> St:
  St{"rpc_set_page_directory_v", 4, 48, "hClient@0:4,hDevice@4:4,pasid@8:4,params@16:32"}


def st_GspSystemInfo() -> St:
  St{"GspSystemInfo", 48, 928, "gpuPhysAddr@0:8,gpuPhysFbAddr@8:8,gpuPhysInstAddr@16:8,gpuPhysIoAddr@24:8,nvDomainBusDeviceFunc@32:8,simAccessBufPhysAddr@40:8,notifyOpSharedSurfacePhysAddr@48:8,pcieAtomicsOpMask@56:8,consoleMemSize@64:8,maxUserVa@72:8,pciConfigMirrorBase@80:4,pciConfigMirrorSize@84:4,PCIDeviceID@88:4,PCISubDeviceID@92:4,PCIRevisionID@96:4,pcieAtomicsCplDeviceCapMask@100:4,oorArch@104:1,clPdbProperties@112:8,Chipset@120:4,bGpuBehindBridge@124:1,bFlrSupported@125:1,b64bBar0Supported@126:1,bMnocAvailable@127:1,chipsetL1ssEnable@128:4,bUpstreamL0sUnsupported@132:1,bUpstreamL1Unsupported@133:1,bUpstreamL1PorSupported@134:1,bUpstreamL1PorMobileOnly@135:1,bSystemHasMux@136:1,upstreamAddressValid@137:1,FHBBusInfo@138:10,chipsetIDInfo@148:10,acpiMethodData@160:676,hypervisorType@836:4,bIsPassthru@840:1,sysTimerOffsetNs@848:8,gspVFInfo@856:40,bIsPrimary@896:1,isGridBuild@897:1,pcieConfigReg@900:4,gridBuildCsp@904:4,bPreserveVideoMemoryAllocations@908:1,bTdrEventSupported@909:1,bFeatureStretchVblankCapable@910:1,bEnableDynamicGranularityPageArrays@911:1,bClockBoostSupported@912:1,bRouteDispIntrsToCPU@913:1,hostPageSize@920:8"}


def st_rpc_unloading_guest_driver_v() -> St:
  St{"rpc_unloading_guest_driver_v", 3, 8, "bInPMTransition@0:1,bGc6Entering@1:1,newLevel@4:4"}


def st_PACKED_REGISTRY_TABLE() -> St:
  St{"PACKED_REGISTRY_TABLE", 2, 8, "size@0:4,numEntries@4:4"}


def st_PACKED_REGISTRY_ENTRY() -> St:
  St{"PACKED_REGISTRY_ENTRY", 4, 16, "nameOffset@0:4,type@4:1,data@8:4,length@12:4"}


def st_rpc_run_cpu_sequencer_v17_00() -> St:
  St{"rpc_run_cpu_sequencer_v17_00", 4, 40, "bufferSizeDWord@0:4,cmdIndex@4:4,regSaveArea@8:32,commandBuffer@40:0"}


# nv.rpc_fns (224) and nv.rpc_events (36) as (id, name) IN INSERTION ORDER, which
# is the order :81's `.get` resolves against. The id spaces are DISJOINT --
# functions are 0..223 and events 4096..4131, overlap 0 -- so `rpc_fns.get(f,
# rpc_events.get(f, ...))` reaches its second arm for EVERY event id and its
# third arm for every id neither table has. `ip_d_*` pins all three arms.
type Ce is Data:
  Ce{id: U32, name: String}


def Ce.of(i: U32, n: String) -> Ce:
  Ce{i, n}


def Ce.id(c: Ce) -> U32:
  match c:
    case Ce{+id, name}: id


def Ce.name(c: Ce) -> String:
  match c:
    case Ce{id, +name}: name


def d_fns() -> List<&2, Ce>:
  List.concat(&2, Ce, [
    [Ce.of(0, "NV_VGPU_MSG_FUNCTION_NOP"), Ce.of(1, "NV_VGPU_MSG_FUNCTION_SET_GUEST_SYSTEM_INFO"), Ce.of(2,
    "NV_VGPU_MSG_FUNCTION_ALLOC_ROOT")], [Ce.of(3, "NV_VGPU_MSG_FUNCTION_ALLOC_DEVICE"), Ce.of(4,
    "NV_VGPU_MSG_FUNCTION_ALLOC_MEMORY"), Ce.of(5, "NV_VGPU_MSG_FUNCTION_ALLOC_CTX_DMA")], [Ce.of(6,
    "NV_VGPU_MSG_FUNCTION_ALLOC_CHANNEL_DMA"), Ce.of(7, "NV_VGPU_MSG_FUNCTION_MAP_MEMORY"), Ce.of(8,
    "NV_VGPU_MSG_FUNCTION_BIND_CTX_DMA")], [Ce.of(9, "NV_VGPU_MSG_FUNCTION_ALLOC_OBJECT"), Ce.of(10,
    "NV_VGPU_MSG_FUNCTION_FREE"), Ce.of(11, "NV_VGPU_MSG_FUNCTION_LOG")], [Ce.of(12,
    "NV_VGPU_MSG_FUNCTION_ALLOC_VIDMEM"), Ce.of(13, "NV_VGPU_MSG_FUNCTION_UNMAP_MEMORY"), Ce.of(14,
    "NV_VGPU_MSG_FUNCTION_MAP_MEMORY_DMA")], [Ce.of(15, "NV_VGPU_MSG_FUNCTION_UNMAP_MEMORY_DMA"), Ce.of(16,
    "NV_VGPU_MSG_FUNCTION_GET_EDID"), Ce.of(17, "NV_VGPU_MSG_FUNCTION_ALLOC_DISP_CHANNEL")], [Ce.of(18,
    "NV_VGPU_MSG_FUNCTION_ALLOC_DISP_OBJECT"), Ce.of(19, "NV_VGPU_MSG_FUNCTION_ALLOC_SUBDEVICE"), Ce.of(20,
    "NV_VGPU_MSG_FUNCTION_ALLOC_DYNAMIC_MEMORY")], [Ce.of(21, "NV_VGPU_MSG_FUNCTION_DUP_OBJECT"), Ce.of(22,
    "NV_VGPU_MSG_FUNCTION_IDLE_CHANNELS"), Ce.of(23, "NV_VGPU_MSG_FUNCTION_ALLOC_EVENT")], [Ce.of(24,
    "NV_VGPU_MSG_FUNCTION_SEND_EVENT"), Ce.of(25, "NV_VGPU_MSG_FUNCTION_REMAPPER_CONTROL"), Ce.of(26,
    "NV_VGPU_MSG_FUNCTION_DMA_CONTROL")], [Ce.of(27, "NV_VGPU_MSG_FUNCTION_DMA_FILL_PTE_MEM"), Ce.of(28,
    "NV_VGPU_MSG_FUNCTION_MANAGE_HW_RESOURCE"), Ce.of(29, "NV_VGPU_MSG_FUNCTION_BIND_ARBITRARY_CTX_DMA")],
    [Ce.of(30, "NV_VGPU_MSG_FUNCTION_CREATE_FB_SEGMENT"), Ce.of(31,
    "NV_VGPU_MSG_FUNCTION_DESTROY_FB_SEGMENT"), Ce.of(32, "NV_VGPU_MSG_FUNCTION_ALLOC_SHARE_DEVICE")],
    [Ce.of(33, "NV_VGPU_MSG_FUNCTION_DEFERRED_API_CONTROL"), Ce.of(34,
    "NV_VGPU_MSG_FUNCTION_REMOVE_DEFERRED_API"), Ce.of(35, "NV_VGPU_MSG_FUNCTION_SIM_ESCAPE_READ")],
    [Ce.of(36, "NV_VGPU_MSG_FUNCTION_SIM_ESCAPE_WRITE"), Ce.of(37,
    "NV_VGPU_MSG_FUNCTION_SIM_MANAGE_DISPLAY_CONTEXT_DMA"), Ce.of(38,
    "NV_VGPU_MSG_FUNCTION_FREE_VIDMEM_VIRT")], [Ce.of(39, "NV_VGPU_MSG_FUNCTION_PERF_GET_PSTATE_INFO"),
    Ce.of(40, "NV_VGPU_MSG_FUNCTION_PERF_GET_PERFMON_SAMPLE"), Ce.of(41,
    "NV_VGPU_MSG_FUNCTION_PERF_GET_VIRTUAL_PSTATE_INFO")], [Ce.of(42,
    "NV_VGPU_MSG_FUNCTION_PERF_GET_LEVEL_INFO"), Ce.of(43, "NV_VGPU_MSG_FUNCTION_MAP_SEMA_MEMORY"), Ce.of(44,
    "NV_VGPU_MSG_FUNCTION_UNMAP_SEMA_MEMORY")], [Ce.of(45, "NV_VGPU_MSG_FUNCTION_SET_SURFACE_PROPERTIES"),
    Ce.of(46, "NV_VGPU_MSG_FUNCTION_CLEANUP_SURFACE"), Ce.of(47,
    "NV_VGPU_MSG_FUNCTION_UNLOADING_GUEST_DRIVER")], [Ce.of(48, "NV_VGPU_MSG_FUNCTION_TDR_SET_TIMEOUT_STATE"),
    Ce.of(49, "NV_VGPU_MSG_FUNCTION_SWITCH_TO_VGA"), Ce.of(50, "NV_VGPU_MSG_FUNCTION_GPU_EXEC_REG_OPS")],
    [Ce.of(51, "NV_VGPU_MSG_FUNCTION_GET_STATIC_INFO"), Ce.of(52, "NV_VGPU_MSG_FUNCTION_ALLOC_VIRTMEM"),
    Ce.of(53, "NV_VGPU_MSG_FUNCTION_UPDATE_PDE_2")], [Ce.of(54, "NV_VGPU_MSG_FUNCTION_SET_PAGE_DIRECTORY"),
    Ce.of(55, "NV_VGPU_MSG_FUNCTION_GET_STATIC_PSTATE_INFO"), Ce.of(56,
    "NV_VGPU_MSG_FUNCTION_TRANSLATE_GUEST_GPU_PTES")], [Ce.of(57, "NV_VGPU_MSG_FUNCTION_RESERVED_57"),
    Ce.of(58, "NV_VGPU_MSG_FUNCTION_RESET_CURRENT_GR_CONTEXT"), Ce.of(59,
    "NV_VGPU_MSG_FUNCTION_SET_SEMA_MEM_VALIDATION_STATE")], [Ce.of(60,
    "NV_VGPU_MSG_FUNCTION_GET_ENGINE_UTILIZATION"), Ce.of(61, "NV_VGPU_MSG_FUNCTION_UPDATE_GPU_PDES"),
    Ce.of(62, "NV_VGPU_MSG_FUNCTION_GET_ENCODER_CAPACITY")], [Ce.of(63,
    "NV_VGPU_MSG_FUNCTION_VGPU_PF_REG_READ32"), Ce.of(64, "NV_VGPU_MSG_FUNCTION_SET_GUEST_SYSTEM_INFO_EXT"),
    Ce.of(65, "NV_VGPU_MSG_FUNCTION_GET_GSP_STATIC_INFO")], [Ce.of(66, "NV_VGPU_MSG_FUNCTION_RMFS_INIT"),
    Ce.of(67, "NV_VGPU_MSG_FUNCTION_RMFS_CLOSE_QUEUE"), Ce.of(68, "NV_VGPU_MSG_FUNCTION_RMFS_CLEANUP")],
    [Ce.of(69, "NV_VGPU_MSG_FUNCTION_RMFS_TEST"), Ce.of(70, "NV_VGPU_MSG_FUNCTION_UPDATE_BAR_PDE"), Ce.of(71,
    "NV_VGPU_MSG_FUNCTION_CONTINUATION_RECORD")], [Ce.of(72, "NV_VGPU_MSG_FUNCTION_GSP_SET_SYSTEM_INFO"),
    Ce.of(73, "NV_VGPU_MSG_FUNCTION_SET_REGISTRY"), Ce.of(74, "NV_VGPU_MSG_FUNCTION_GSP_INIT_POST_OBJGPU")],
    [Ce.of(75, "NV_VGPU_MSG_FUNCTION_SUBDEV_EVENT_SET_NOTIFICATION"), Ce.of(76,
    "NV_VGPU_MSG_FUNCTION_GSP_RM_CONTROL"), Ce.of(77, "NV_VGPU_MSG_FUNCTION_GET_STATIC_INFO2")], [Ce.of(78,
    "NV_VGPU_MSG_FUNCTION_DUMP_PROTOBUF_COMPONENT"), Ce.of(79, "NV_VGPU_MSG_FUNCTION_UNSET_PAGE_DIRECTORY"),
    Ce.of(80, "NV_VGPU_MSG_FUNCTION_GET_CONSOLIDATED_STATIC_INFO")], [Ce.of(81,
    "NV_VGPU_MSG_FUNCTION_GMMU_REGISTER_FAULT_BUFFER"), Ce.of(82,
    "NV_VGPU_MSG_FUNCTION_GMMU_UNREGISTER_FAULT_BUFFER"), Ce.of(83,
    "NV_VGPU_MSG_FUNCTION_GMMU_REGISTER_CLIENT_SHADOW_FAULT_BUFFER")], [Ce.of(84,
    "NV_VGPU_MSG_FUNCTION_GMMU_UNREGISTER_CLIENT_SHADOW_FAULT_BUFFER"), Ce.of(85,
    "NV_VGPU_MSG_FUNCTION_CTRL_SET_VGPU_FB_USAGE"), Ce.of(86,
    "NV_VGPU_MSG_FUNCTION_CTRL_NVFBC_SW_SESSION_UPDATE_INFO")], [Ce.of(87,
    "NV_VGPU_MSG_FUNCTION_CTRL_NVENC_SW_SESSION_UPDATE_INFO"), Ce.of(88,
    "NV_VGPU_MSG_FUNCTION_CTRL_RESET_CHANNEL"), Ce.of(89,
    "NV_VGPU_MSG_FUNCTION_CTRL_RESET_ISOLATED_CHANNEL")], [Ce.of(90,
    "NV_VGPU_MSG_FUNCTION_CTRL_GPU_HANDLE_VF_PRI_FAULT"), Ce.of(91,
    "NV_VGPU_MSG_FUNCTION_CTRL_CLK_GET_EXTENDED_INFO"), Ce.of(92, "NV_VGPU_MSG_FUNCTION_CTRL_PERF_BOOST")],
    [Ce.of(93, "NV_VGPU_MSG_FUNCTION_CTRL_PERF_VPSTATES_GET_CONTROL"), Ce.of(94,
    "NV_VGPU_MSG_FUNCTION_CTRL_GET_ZBC_CLEAR_TABLE"), Ce.of(95,
    "NV_VGPU_MSG_FUNCTION_CTRL_SET_ZBC_COLOR_CLEAR")], [Ce.of(96,
    "NV_VGPU_MSG_FUNCTION_CTRL_SET_ZBC_DEPTH_CLEAR"), Ce.of(97, "NV_VGPU_MSG_FUNCTION_CTRL_GPFIFO_SCHEDULE"),
    Ce.of(98, "NV_VGPU_MSG_FUNCTION_CTRL_SET_TIMESLICE")], [Ce.of(99, "NV_VGPU_MSG_FUNCTION_CTRL_PREEMPT"),
    Ce.of(100, "NV_VGPU_MSG_FUNCTION_CTRL_FIFO_DISABLE_CHANNELS"), Ce.of(101,
    "NV_VGPU_MSG_FUNCTION_CTRL_SET_TSG_INTERLEAVE_LEVEL")], [Ce.of(102,
    "NV_VGPU_MSG_FUNCTION_CTRL_SET_CHANNEL_INTERLEAVE_LEVEL"), Ce.of(103,
    "NV_VGPU_MSG_FUNCTION_GSP_RM_ALLOC"), Ce.of(104, "NV_VGPU_MSG_FUNCTION_CTRL_GET_P2P_CAPS_V2")],
    [Ce.of(105, "NV_VGPU_MSG_FUNCTION_CTRL_CIPHER_AES_ENCRYPT"), Ce.of(106,
    "NV_VGPU_MSG_FUNCTION_CTRL_CIPHER_SESSION_KEY"), Ce.of(107,
    "NV_VGPU_MSG_FUNCTION_CTRL_CIPHER_SESSION_KEY_STATUS")], [Ce.of(108,
    "NV_VGPU_MSG_FUNCTION_CTRL_DBG_CLEAR_ALL_SM_ERROR_STATES"), Ce.of(109,
    "NV_VGPU_MSG_FUNCTION_CTRL_DBG_READ_ALL_SM_ERROR_STATES"), Ce.of(110,
    "NV_VGPU_MSG_FUNCTION_CTRL_DBG_SET_EXCEPTION_MASK")], [Ce.of(111,
    "NV_VGPU_MSG_FUNCTION_CTRL_GPU_PROMOTE_CTX"), Ce.of(112,
    "NV_VGPU_MSG_FUNCTION_CTRL_GR_CTXSW_PREEMPTION_BIND"), Ce.of(113,
    "NV_VGPU_MSG_FUNCTION_CTRL_GR_SET_CTXSW_PREEMPTION_MODE")], [Ce.of(114,
    "NV_VGPU_MSG_FUNCTION_CTRL_GR_CTXSW_ZCULL_BIND"), Ce.of(115,
    "NV_VGPU_MSG_FUNCTION_CTRL_GPU_INITIALIZE_CTX"), Ce.of(116,
    "NV_VGPU_MSG_FUNCTION_CTRL_VASPACE_COPY_SERVER_RESERVED_PDES")], [Ce.of(117,
    "NV_VGPU_MSG_FUNCTION_CTRL_FIFO_CLEAR_FAULTED_BIT"), Ce.of(118,
    "NV_VGPU_MSG_FUNCTION_CTRL_GET_LATEST_ECC_ADDRESSES"), Ce.of(119,
    "NV_VGPU_MSG_FUNCTION_CTRL_MC_SERVICE_INTERRUPTS")], [Ce.of(120,
    "NV_VGPU_MSG_FUNCTION_CTRL_DMA_SET_DEFAULT_VASPACE"), Ce.of(121,
    "NV_VGPU_MSG_FUNCTION_CTRL_GET_CE_PCE_MASK"), Ce.of(122,
    "NV_VGPU_MSG_FUNCTION_CTRL_GET_ZBC_CLEAR_TABLE_ENTRY")], [Ce.of(123,
    "NV_VGPU_MSG_FUNCTION_CTRL_GET_NVLINK_PEER_ID_MASK"), Ce.of(124,
    "NV_VGPU_MSG_FUNCTION_CTRL_GET_NVLINK_STATUS"), Ce.of(125, "NV_VGPU_MSG_FUNCTION_CTRL_GET_P2P_CAPS")],
    [Ce.of(126, "NV_VGPU_MSG_FUNCTION_CTRL_GET_P2P_CAPS_MATRIX"), Ce.of(127,
    "NV_VGPU_MSG_FUNCTION_RESERVED_0"), Ce.of(128, "NV_VGPU_MSG_FUNCTION_CTRL_RESERVE_PM_AREA_SMPC")],
    [Ce.of(129, "NV_VGPU_MSG_FUNCTION_CTRL_RESERVE_HWPM_LEGACY"), Ce.of(130,
    "NV_VGPU_MSG_FUNCTION_CTRL_B0CC_EXEC_REG_OPS"), Ce.of(131,
    "NV_VGPU_MSG_FUNCTION_CTRL_BIND_PM_RESOURCES")], [Ce.of(132,
    "NV_VGPU_MSG_FUNCTION_CTRL_DBG_SUSPEND_CONTEXT"), Ce.of(133,
    "NV_VGPU_MSG_FUNCTION_CTRL_DBG_RESUME_CONTEXT"), Ce.of(134,
    "NV_VGPU_MSG_FUNCTION_CTRL_DBG_EXEC_REG_OPS")], [Ce.of(135,
    "NV_VGPU_MSG_FUNCTION_CTRL_DBG_SET_MODE_MMU_DEBUG"), Ce.of(136,
    "NV_VGPU_MSG_FUNCTION_CTRL_DBG_READ_SINGLE_SM_ERROR_STATE"), Ce.of(137,
    "NV_VGPU_MSG_FUNCTION_CTRL_DBG_CLEAR_SINGLE_SM_ERROR_STATE")], [Ce.of(138,
    "NV_VGPU_MSG_FUNCTION_CTRL_DBG_SET_MODE_ERRBAR_DEBUG"), Ce.of(139,
    "NV_VGPU_MSG_FUNCTION_CTRL_DBG_SET_NEXT_STOP_TRIGGER_TYPE"), Ce.of(140,
    "NV_VGPU_MSG_FUNCTION_CTRL_ALLOC_PMA_STREAM")], [Ce.of(141,
    "NV_VGPU_MSG_FUNCTION_CTRL_PMA_STREAM_UPDATE_GET_PUT"), Ce.of(142,
    "NV_VGPU_MSG_FUNCTION_CTRL_FB_GET_INFO_V2"), Ce.of(143,
    "NV_VGPU_MSG_FUNCTION_CTRL_FIFO_SET_CHANNEL_PROPERTIES")], [Ce.of(144,
    "NV_VGPU_MSG_FUNCTION_CTRL_GR_GET_CTX_BUFFER_INFO"), Ce.of(145,
    "NV_VGPU_MSG_FUNCTION_CTRL_KGR_GET_CTX_BUFFER_PTES"), Ce.of(146,
    "NV_VGPU_MSG_FUNCTION_CTRL_GPU_EVICT_CTX")], [Ce.of(147, "NV_VGPU_MSG_FUNCTION_CTRL_FB_GET_FS_INFO"),
    Ce.of(148, "NV_VGPU_MSG_FUNCTION_CTRL_GRMGR_GET_GR_FS_INFO"), Ce.of(149,
    "NV_VGPU_MSG_FUNCTION_CTRL_STOP_CHANNEL")], [Ce.of(150, "NV_VGPU_MSG_FUNCTION_CTRL_GR_PC_SAMPLING_MODE"),
    Ce.of(151, "NV_VGPU_MSG_FUNCTION_CTRL_PERF_RATED_TDP_GET_STATUS"), Ce.of(152,
    "NV_VGPU_MSG_FUNCTION_CTRL_PERF_RATED_TDP_SET_CONTROL")], [Ce.of(153,
    "NV_VGPU_MSG_FUNCTION_CTRL_FREE_PMA_STREAM"), Ce.of(154,
    "NV_VGPU_MSG_FUNCTION_CTRL_TIMER_SET_GR_TICK_FREQ"), Ce.of(155,
    "NV_VGPU_MSG_FUNCTION_CTRL_FIFO_SETUP_VF_ZOMBIE_SUBCTX_PDB")], [Ce.of(156,
    "NV_VGPU_MSG_FUNCTION_GET_CONSOLIDATED_GR_STATIC_INFO"), Ce.of(157,
    "NV_VGPU_MSG_FUNCTION_CTRL_DBG_SET_SINGLE_SM_SINGLE_STEP"), Ce.of(158,
    "NV_VGPU_MSG_FUNCTION_CTRL_GR_GET_TPC_PARTITION_MODE")], [Ce.of(159,
    "NV_VGPU_MSG_FUNCTION_CTRL_GR_SET_TPC_PARTITION_MODE"), Ce.of(160,
    "NV_VGPU_MSG_FUNCTION_UVM_PAGING_CHANNEL_ALLOCATE"), Ce.of(161,
    "NV_VGPU_MSG_FUNCTION_UVM_PAGING_CHANNEL_DESTROY")], [Ce.of(162,
    "NV_VGPU_MSG_FUNCTION_UVM_PAGING_CHANNEL_MAP"), Ce.of(163,
    "NV_VGPU_MSG_FUNCTION_UVM_PAGING_CHANNEL_UNMAP"), Ce.of(164,
    "NV_VGPU_MSG_FUNCTION_UVM_PAGING_CHANNEL_PUSH_STREAM")], [Ce.of(165,
    "NV_VGPU_MSG_FUNCTION_UVM_PAGING_CHANNEL_SET_HANDLES"), Ce.of(166,
    "NV_VGPU_MSG_FUNCTION_UVM_METHOD_STREAM_GUEST_PAGES_OPERATION"), Ce.of(167,
    "NV_VGPU_MSG_FUNCTION_CTRL_INTERNAL_QUIESCE_PMA_CHANNEL")], [Ce.of(168,
    "NV_VGPU_MSG_FUNCTION_DCE_RM_INIT"), Ce.of(169, "NV_VGPU_MSG_FUNCTION_REGISTER_VIRTUAL_EVENT_BUFFER"),
    Ce.of(170, "NV_VGPU_MSG_FUNCTION_CTRL_EVENT_BUFFER_UPDATE_GET")], [Ce.of(171,
    "NV_VGPU_MSG_FUNCTION_GET_PLCABLE_ADDRESS_KIND"), Ce.of(172,
    "NV_VGPU_MSG_FUNCTION_CTRL_PERF_LIMITS_SET_STATUS_V2"), Ce.of(173,
    "NV_VGPU_MSG_FUNCTION_CTRL_INTERNAL_SRIOV_PROMOTE_PMA_STREAM")], [Ce.of(174,
    "NV_VGPU_MSG_FUNCTION_CTRL_GET_MMU_DEBUG_MODE"), Ce.of(175,
    "NV_VGPU_MSG_FUNCTION_CTRL_INTERNAL_PROMOTE_FAULT_METHOD_BUFFERS"), Ce.of(176,
    "NV_VGPU_MSG_FUNCTION_CTRL_FLCN_GET_CTX_BUFFER_SIZE")], [Ce.of(177,
    "NV_VGPU_MSG_FUNCTION_CTRL_FLCN_GET_CTX_BUFFER_INFO"), Ce.of(178,
    "NV_VGPU_MSG_FUNCTION_DISABLE_CHANNELS"), Ce.of(179, "NV_VGPU_MSG_FUNCTION_CTRL_FABRIC_MEMORY_DESCRIBE")],
    [Ce.of(180, "NV_VGPU_MSG_FUNCTION_CTRL_FABRIC_MEM_STATS"), Ce.of(181,
    "NV_VGPU_MSG_FUNCTION_SAVE_HIBERNATION_DATA"), Ce.of(182,
    "NV_VGPU_MSG_FUNCTION_RESTORE_HIBERNATION_DATA")], [Ce.of(183,
    "NV_VGPU_MSG_FUNCTION_CTRL_INTERNAL_MEMSYS_SET_ZBC_REFERENCED"), Ce.of(184,
    "NV_VGPU_MSG_FUNCTION_CTRL_EXEC_PARTITIONS_CREATE"), Ce.of(185,
    "NV_VGPU_MSG_FUNCTION_CTRL_EXEC_PARTITIONS_DELETE")], [Ce.of(186,
    "NV_VGPU_MSG_FUNCTION_CTRL_GPFIFO_GET_WORK_SUBMIT_TOKEN"), Ce.of(187,
    "NV_VGPU_MSG_FUNCTION_CTRL_GPFIFO_SET_WORK_SUBMIT_TOKEN_NOTIF_INDEX"), Ce.of(188,
    "NV_VGPU_MSG_FUNCTION_PMA_SCRUBBER_SHARED_BUFFER_GUEST_PAGES_OPERATION")], [Ce.of(189,
    "NV_VGPU_MSG_FUNCTION_CTRL_MASTER_GET_VIRTUAL_FUNCTION_ERROR_CONT_INTR_MASK"), Ce.of(190,
    "NV_VGPU_MSG_FUNCTION_SET_SYSMEM_DIRTY_PAGE_TRACKING_BUFFER"), Ce.of(191,
    "NV_VGPU_MSG_FUNCTION_CTRL_SUBDEVICE_GET_P2P_CAPS")], [Ce.of(192,
    "NV_VGPU_MSG_FUNCTION_CTRL_BUS_SET_P2P_MAPPING"), Ce.of(193,
    "NV_VGPU_MSG_FUNCTION_CTRL_BUS_UNSET_P2P_MAPPING"), Ce.of(194,
    "NV_VGPU_MSG_FUNCTION_CTRL_FLA_SETUP_INSTANCE_MEM_BLOCK")], [Ce.of(195,
    "NV_VGPU_MSG_FUNCTION_CTRL_GPU_MIGRATABLE_OPS"), Ce.of(196,
    "NV_VGPU_MSG_FUNCTION_CTRL_GET_TOTAL_HS_CREDITS"), Ce.of(197,
    "NV_VGPU_MSG_FUNCTION_CTRL_GET_HS_CREDITS")], [Ce.of(198, "NV_VGPU_MSG_FUNCTION_CTRL_SET_HS_CREDITS"),
    Ce.of(199, "NV_VGPU_MSG_FUNCTION_CTRL_PM_AREA_PC_SAMPLER"), Ce.of(200,
    "NV_VGPU_MSG_FUNCTION_INVALIDATE_TLB")], [Ce.of(201, "NV_VGPU_MSG_FUNCTION_CTRL_GPU_QUERY_ECC_STATUS"),
    Ce.of(202, "NV_VGPU_MSG_FUNCTION_ECC_NOTIFIER_WRITE_ACK"), Ce.of(203,
    "NV_VGPU_MSG_FUNCTION_CTRL_DBG_GET_MODE_MMU_DEBUG")], [Ce.of(204, "NV_VGPU_MSG_FUNCTION_RM_API_CONTROL"),
    Ce.of(205, "NV_VGPU_MSG_FUNCTION_CTRL_CMD_INTERNAL_GPU_START_FABRIC_PROBE"), Ce.of(206,
    "NV_VGPU_MSG_FUNCTION_CTRL_NVLINK_GET_INBAND_RECEIVED_DATA")], [Ce.of(207,
    "NV_VGPU_MSG_FUNCTION_GET_STATIC_DATA"), Ce.of(208, "NV_VGPU_MSG_FUNCTION_RESERVED_208"), Ce.of(209,
    "NV_VGPU_MSG_FUNCTION_CTRL_GPU_GET_INFO_V2")], [Ce.of(210, "NV_VGPU_MSG_FUNCTION_GET_BRAND_CAPS"),
    Ce.of(211, "NV_VGPU_MSG_FUNCTION_CTRL_CMD_NVLINK_INBAND_SEND_DATA"), Ce.of(212,
    "NV_VGPU_MSG_FUNCTION_UPDATE_GPM_GUEST_BUFFER_INFO")], [Ce.of(213,
    "NV_VGPU_MSG_FUNCTION_CTRL_CMD_INTERNAL_CONTROL_GSP_TRACE"), Ce.of(214,
    "NV_VGPU_MSG_FUNCTION_CTRL_SET_ZBC_STENCIL_CLEAR"), Ce.of(215,
    "NV_VGPU_MSG_FUNCTION_CTRL_SUBDEVICE_GET_VGPU_HEAP_STATS")], [Ce.of(216,
    "NV_VGPU_MSG_FUNCTION_CTRL_SUBDEVICE_GET_LIBOS_HEAP_STATS"), Ce.of(217,
    "NV_VGPU_MSG_FUNCTION_CTRL_DBG_SET_MODE_MMU_GCC_DEBUG"), Ce.of(218,
    "NV_VGPU_MSG_FUNCTION_CTRL_DBG_GET_MODE_MMU_GCC_DEBUG")], [Ce.of(219,
    "NV_VGPU_MSG_FUNCTION_CTRL_RESERVE_HES"), Ce.of(220, "NV_VGPU_MSG_FUNCTION_CTRL_RELEASE_HES"), Ce.of(221,
    "NV_VGPU_MSG_FUNCTION_CTRL_RESERVE_CCU_PROF")], [Ce.of(222, "NV_VGPU_MSG_FUNCTION_CTRL_RELEASE_CCU_PROF"),
    Ce.of(223, "NV_VGPU_MSG_FUNCTION_NUM_FUNCTIONS")],
  ])

def d_events() -> List<&2, Ce>:
  List.concat(&2, Ce, [
    [Ce.of(4096, "NV_VGPU_MSG_EVENT_FIRST_EVENT"), Ce.of(4097, "NV_VGPU_MSG_EVENT_GSP_INIT_DONE"), Ce.of(4098,
    "NV_VGPU_MSG_EVENT_GSP_RUN_CPU_SEQUENCER")], [Ce.of(4099, "NV_VGPU_MSG_EVENT_POST_EVENT"), Ce.of(4100,
    "NV_VGPU_MSG_EVENT_RC_TRIGGERED"), Ce.of(4101, "NV_VGPU_MSG_EVENT_MMU_FAULT_QUEUED")], [Ce.of(4102,
    "NV_VGPU_MSG_EVENT_OS_ERROR_LOG"), Ce.of(4103, "NV_VGPU_MSG_EVENT_RG_LINE_INTR"), Ce.of(4104,
    "NV_VGPU_MSG_EVENT_GPUACCT_PERFMON_UTIL_SAMPLES")], [Ce.of(4105, "NV_VGPU_MSG_EVENT_SIM_READ"),
    Ce.of(4106, "NV_VGPU_MSG_EVENT_SIM_WRITE"), Ce.of(4107, "NV_VGPU_MSG_EVENT_SEMAPHORE_SCHEDULE_CALLBACK")],
    [Ce.of(4108, "NV_VGPU_MSG_EVENT_UCODE_LIBOS_PRINT"), Ce.of(4109,
    "NV_VGPU_MSG_EVENT_VGPU_GSP_PLUGIN_TRIGGERED"), Ce.of(4110,
    "NV_VGPU_MSG_EVENT_PERF_GPU_BOOST_SYNC_LIMITS_CALLBACK")], [Ce.of(4111,
    "NV_VGPU_MSG_EVENT_PERF_BRIDGELESS_INFO_UPDATE"), Ce.of(4112, "NV_VGPU_MSG_EVENT_VGPU_CONFIG"),
    Ce.of(4113, "NV_VGPU_MSG_EVENT_DISPLAY_MODESET")], [Ce.of(4114, "NV_VGPU_MSG_EVENT_EXTDEV_INTR_SERVICE"),
    Ce.of(4115, "NV_VGPU_MSG_EVENT_NVLINK_INBAND_RECEIVED_DATA_256"), Ce.of(4116,
    "NV_VGPU_MSG_EVENT_NVLINK_INBAND_RECEIVED_DATA_512")], [Ce.of(4117,
    "NV_VGPU_MSG_EVENT_NVLINK_INBAND_RECEIVED_DATA_1024"), Ce.of(4118,
    "NV_VGPU_MSG_EVENT_NVLINK_INBAND_RECEIVED_DATA_2048"), Ce.of(4119,
    "NV_VGPU_MSG_EVENT_NVLINK_INBAND_RECEIVED_DATA_4096")], [Ce.of(4120,
    "NV_VGPU_MSG_EVENT_TIMED_SEMAPHORE_RELEASE"), Ce.of(4121, "NV_VGPU_MSG_EVENT_NVLINK_IS_GPU_DEGRADED"),
    Ce.of(4122, "NV_VGPU_MSG_EVENT_PFM_REQ_HNDLR_STATE_SYNC_CALLBACK")], [Ce.of(4123,
    "NV_VGPU_MSG_EVENT_NVLINK_FAULT_UP"), Ce.of(4124, "NV_VGPU_MSG_EVENT_GSP_LOCKDOWN_NOTICE"), Ce.of(4125,
    "NV_VGPU_MSG_EVENT_MIG_CI_CONFIG_UPDATE")], [Ce.of(4126, "NV_VGPU_MSG_EVENT_UPDATE_GSP_TRACE"),
    Ce.of(4127, "NV_VGPU_MSG_EVENT_NVLINK_FATAL_ERROR_RECOVERY"), Ce.of(4128,
    "NV_VGPU_MSG_EVENT_GSP_POST_NOCAT_RECORD")], [Ce.of(4129, "NV_VGPU_MSG_EVENT_FECS_ERROR"), Ce.of(4130,
    "NV_VGPU_MSG_EVENT_RECOVERY_ACTION"), Ce.of(4131, "NV_VGPU_MSG_EVENT_NUM_EVENTS")],
  ])


# The 54 layouts as one list, in the order the generator found them. `st_nth`
# indexes it, so the gate can ask for the n-th layout and the ORDER of the
# table is itself checkable against `ip_st_order`.
def st_field_list() -> List<&2, St>:
  List.concat(&2, St, [
    [st_msgqTxHeader(), st_rpc_message_header_v(), st_GSP_MSG_QUEUE_ELEMENT()], [st_BIT_HEADER_V1_00(),
    st_BIT_TOKEN_V1_00(), st_BIT_DATA_FALCON_DATA_V2()], [st_FALCON_UCODE_TABLE_HDR_V1(),
    st_FALCON_UCODE_TABLE_ENTRY_V1(), st_FALCON_UCODE_DESC_HEADER()], [st_FALCON_UCODE_DESC_V3(),
    st_FWSECLIC_READ_VBIOS_DESC(), st_FWSECLIC_FRTS_REGION_DESC()], [st_FWSECLIC_FRTS_CMD(),
    st_FALCON_APPLICATION_INTERFACE_HEADER_V1(), st_FALCON_APPLICATION_INTERFACE_ENTRY_V1()],
    [st_FALCON_APPLICATION_INTERFACE_DMEM_MAPPER_V3(), st_struct_nvfw_bin_hdr(),
    st_struct_nvfw_hs_load_header_v2()], [st_struct_nvfw_hs_header_v2(),
    st_struct_nvfw_hs_load_header_v2_app(), st_GSP_FMC_BOOT_PARAMS()], [st_GSP_ACR_BOOT_GSP_RM_PARAMS(),
    st_GspFwWprMeta(), st_GSP_RM_PARAMS()], [st_NVDM_PAYLOAD_COT(), st_MESSAGE_QUEUE_INIT_ARGUMENTS(),
    st_GSP_ARGUMENTS_CACHED()], [st_LibosMemoryRegionInitArgument(), st_RM_RISCV_UCODE_DESC(),
    st_NV2080_CTRL_GPU_PROMOTE_CTX_PARAMS()], [st_NV2080_CTRL_GPU_PROMOTE_CTX_BUFFER_ENTRY(),
    st_NV0000_ALLOC_PARAMETERS(), st_NV0080_ALLOC_PARAMETERS()], [st_NV2080_ALLOC_PARAMETERS(),
    st_NV_VASPACE_ALLOCATION_PARAMETERS(), st_NV2080_CTRL_FIFO_GET_DEVICE_INFO_TABLE_PARAMS()],
    [st_struct_NV90F1_CTRL_VASPACE_COPY_SERVER_RESERVED_PDES_PARAMS(),
    st_struct_NV90F1_CTRL_VASPACE_COPY_SERVER_RESERVED_PDES_PARAMS_level(), st_NV_MEMORY_DESC_PARAMS()],
    [st_NV_CHANNELGPFIFO_ALLOCATION_PARAMETERS(),
    st_NV2080_CTRL_INTERNAL_STATIC_KGR_GET_CONTEXT_BUFFERS_INFO_PARAMS(), st_rpc_alloc_memory_v()],
    [st_struct_pte_desc_pte_pde(), st_rpc_gsp_rm_alloc_v(),
    st_NVB0CC_CTRL_INTERNAL_PERMISSIONS_INIT_PARAMS()], [st_rpc_gsp_rm_control_v(),
    st_NVC36F_CTRL_CMD_GPFIFO_GET_WORK_SUBMIT_TOKEN_PARAMS(),
    st_struct_NV0080_CTRL_DMA_SET_PAGE_DIRECTORY_PARAMS_v1E_05()], [st_rpc_set_page_directory_v(),
    st_GspSystemInfo(), st_rpc_unloading_guest_driver_v()], [st_PACKED_REGISTRY_TABLE(),
    st_PACKED_REGISTRY_ENTRY(), st_rpc_run_cpu_sequencer_v17_00()],
  ])


# THE SEED STEP OF A COUNTING FOLD, and nothing else.
#
# `Bool.pick(U32, c, a, b)` answers `a` when `c` is true and `b` when it is
# false, and the untaken arm does not reach the answer. So a fold written as
# `Bool.pick(U32, hit, x + 1, go(t, n))` answers `x + 1` when `hit` and NEVER
# calls `go` -- a fold that stops at the first element that matches. Measured:
# over `d_fns()` (ids 0..223) it printed `ip_d_fns_max=1`, because id 0 did not
# beat the seed 0 and id 1 did, so the walk ended one step in; `ip_d_ev_max`
# printed 4096 for 4131 the same way. Four folds were wrong this way and all
# four now compute the SEED in a `pick` and recurse OUTSIDE it.
#
# `const_of.go` and `ce_name.go` are NOT wrong: there the pick's TRUE arm is the
# accumulator, and dropping the walk IS the first-wins behaviour they mean.
def bump(hit: Bool, +n: U32) -> U32: Bool.pick(U32, hit, U32.inc(n), n)


type Cv is Data:
  Cv{hit: Bool, c: Cn}


def Cv.hit(v: Cv) -> Bool:
  match v:
    case Cv{+hit, c}: hit


def Cv.c(v: Cv) -> Cn:
  match v:
    case Cv{hit, +c}: c


def const_of.go(+xs: List<&2, Cn>, +a: Cv, +nm: String) -> Cv:
  match xs:
    case Nil{}: a
    case c <> t:
      Bool.pick(Cv, Cv.hit(a), a,
        Bool.pick(Cv, String.eq(Cn.name(c), nm), Cv{True{}, c}, const_of.go(t, a, nm)))


def const_of(nm: String) -> Cn: Cv.c(const_of.go(cn_table(), Cv{False{}, Cn.of("", 0)}, nm))


def const_name.go(+xs: List<&2, Cn>, +a: Cv, +v: U32) -> Cv:
  match xs:
    case Nil{}: a
    case c <> t:
      Bool.pick(Cv, Cv.hit(a), a,
        Bool.pick(Cv, U32.is_eq(Cn.v(c), v), Cv{True{}, c}, const_name.go(t, a, v)))


def const_name_n.go(+xs: List<&2, Cn>, +n: U32, +v: U32) -> U32:
  match xs:
    case Nil{}: n
    case c <> t: const_name_n.go(t, bump(U32.is_eq(Cn.v(c), v), n), v)


def const_name_n(v: U32) -> U32: const_name_n.go(cn_table(), 0, v)


# ONE walk per question. A two-arm `Bool.pick` over the fold's result walks the
# table TWICE and reads `v` twice, so the two answers are two defs -- which is
# the same `.go` split every other fold here uses.
def const_name_hit(v: U32) -> Bool: Cv.hit(const_name.go(cn_table(), Cv{False{}, Cn.of("", 0)}, v))


def const_name_of(v: U32) -> String:
  Cn.name(Cv.c(const_name.go(cn_table(), Cv{False{}, Cn.of("", 0)}, v)))


def const_name(+v: U32) -> String: Bool.pick(String, const_name_hit(v), const_name_of(v), "")


type Cev is Data:
  Cev{hit: Bool, name: String}


def Cev.hit(v: Cev) -> Bool:
  match v:
    case Cev{+hit, name}: hit


def Cev.name(v: Cev) -> String:
  match v:
    case Cev{hit, +name}: name


def ce_name.go(+xs: List<&2, Ce>, +a: Cev, +id: U32) -> Cev:
  match xs:
    case Nil{}: a
    case c <> t:
      Bool.pick(Cev, Cev.hit(a), a,
        Bool.pick(Cev, U32.is_eq(Ce.id(c), id), Cev{True{}, Ce.name(c)}, ce_name.go(t, a, id)))


def ce_name(xs: List<&2, Ce>, id: U32) -> String: Cev.name(ce_name.go(xs, Cev{False{}, ""}, id))


def ce_has(xs: List<&2, Ce>, id: U32) -> Bool: Cev.hit(ce_name.go(xs, Cev{False{}, ""}, id))


# A 0..15 ladder is NOT a three-way `U32` choice, so this one is legal where
# `case 0 / case 1 / case _:` over arbitrary U32 literals is refused with
# "a declared constructor (unknown: U32)". `chr_g` in the Stage C part is the
# OTHER spelling -- two `Bool.pick`s -- and both give the same digits, which is
# what `ip_d_lbl_miss_hex` checks against Python's `'%x'`.
def nib(c: U32) -> String:
  match c:
    case 0: "0"
    case 1: "1"
    case 2: "2"
    case 3: "3"
    case 4: "4"
    case 5: "5"
    case 6: "6"
    case 7: "7"
    case 8: "8"
    case 9: "9"
    case 10: "a"
    case 11: "b"
    case 12: "c"
    case 13: "d"
    case 14: "e"
    case 15: "f"
    case _: "?"


# Python's f'{v:x}' -- lowercase, NO leading zeros, and "0" for zero. TWO things
# the oracle found here, and both were wrong on the first run:
#   1. `U32.shrn(n, 4n)` is a SHIFT, not a nibble: `nib` has to be handed
#      `U32.shrn(n,4n) & 0xf`. Without the mask `hex8(999)` printed `3??` and the
#      oracle said `ev:3e7`.
#   2. `Bool.pick` answers its TRUE arm FIRST, so the thresholds run OUTSIDE-IN,
#      LARGEST FIRST -- and the answer for the largest is "drop NOTHING", because
#      `n >= 0x1000` already has four digits. Written the other way round
#      `hex8(4132)` printed `???`; with the order fixed but the largest branch
#      still dropping it printed `4`. Python's `'%x' % 4132` is `1024`.
# `String.drop` CONSUMES its string (measured), hence the `+s` on four arms of one
# `Bool.pick`.
def hex8.strip(+s: String, +n: U32) -> String:
  Bool.pick(String, U32.is_gt(n, 4095), s,
    Bool.pick(String, U32.is_gt(n, 255), String.drop(s, 1n),
      Bool.pick(String, U32.is_gt(n, 15), String.drop(s, 2n), String.drop(s, 3n))))


def hex8(+n: U32) -> String:
  hex8.strip(String.join([nib(U32.and(U32.shrn(n, 12n), 15)),
                          nib(U32.and(U32.shrn(n, 8n), 15)),
                          nib(U32.and(U32.shrn(n, 4n), 15)),
                          nib(U32.and(n, 15))], ""), n)


# :81 `nv.rpc_fns.get(hdr.function, nv.rpc_events.get(hdr.function,
# f'ev:{hdr.function:x}'))`. THREE arms, and the arm is DECIDED before the name is
# read: a two-arm `Bool.pick` over two `d_fns()` walks would read `f` four times.
# The ladder is DESCENDING because a `U32` literal arm is a prefix match for the
# successor relation and the ladder has to be ordered.
def rpc_arm(+f: U32) -> U32:
  Bool.pick(U32, ce_has(d_fns(), f), 1, Bool.pick(U32, ce_has(d_events(), f), 2, 3))


def rpc_label.go(a: U32, f: U32) -> String:
  match a:
    case 3: String.concat(["ev:", hex8(f)])
    case 2: ce_name(d_events(), f)
    case 1: ce_name(d_fns(), f)
    case _: String.concat(["ev:", hex8(f)])


def rpc_label(+f: U32) -> String: rpc_label.go(rpc_arm(f), f)


# THE GATE MOVED TO `gates/ip-gate.bend`.
#
# The rows are consumers: each calls a def above through `P.`, and the driver
# defines nothing this file needs -- the line `gates/README.md:173` draws. What
# went with them is the row fixtures and the wall notes that explain why a rule
# has no row.
#
# Their 1,428 expectations are CPython's: `oracles/tinybendygrad_runtime_support_nv_ip.bend.rows`
# records upstream's decoder run over the section blobs `nvdisasm` emitted, and the
# driver's output is byte-identical to it, sorted.
