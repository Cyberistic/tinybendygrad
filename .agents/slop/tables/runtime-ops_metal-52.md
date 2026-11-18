<!-- FROM: tinybendygrad/runtime/ops_metal.bend:52 -->
# BLOCK:
# WHAT IS PORTED, DEF BY DEF.
#
#   :15  REQUEST_TYPE_COMPILE       PORTED  a constant
#   :18  DLL("CoreGraphics")        WALL 1  A DYNAMIC LIBRARY LOAD
#   :22  to_ns_str                  WALL 2  AN NSString, plus `@functools.cache`
#   :24  checked                    PORTED  the WRAPPER, i.e. the refusal
#   :29  class MetalCompiler        PORTED  the four tables and three refs
#   :35   support = DLL(MTLCompiler) WALL 1
#   :38   __init__                  PORTED  `cgs_create`, and the ENTRY name -- upstream creates the code-gen service in `__init__`
#                                               travels as `Cmd.name`
#   :41   __reduce__                WALL 3  PICKLE (a multiprocessing detail)
#   :42   compile                   PARTIAL  the layout and the refusals
#   tinygrad/runtime/ops_metal.py:60 macos_major/metal_version PORTED  the four-way `-std=` ladder
#   :60   params                    PORTED  the f-string
#   :62   src_padded/params_padded  PORTED  the 4-byte pad and the NUL
#   :63   request                   PORTED  the 16-byte `<QQ` header
#   :69   raise ret                 PORTED  refusal 1
#   :70   assert MTLB/ENDT          PORTED  refusal 2 (and the magic numbers)
#   :72   disassemble               WALL 4  A SUBPROCESS
#   :85  HANDLES                    PORTED  the five handles
#   :86  SELECTORS                  PORTED  the thirteen selectors
#   :89  MSGSEND                    PORTED  two bindings, by return type
#   :91  mtl_sel                    PORTED  the index table (51 entries)
#   :93  mtl_cb / :94 mtl_enc       PORTED  two placeholders, both index 0
#   :96  mtl_msg                    PORTED  the call, its selector and its args
#   :101 mtl_poll                   PORTED  one msgSend
#   :105 MetalQueue.__init__        PORTED  the five accumulators
#   :109 exec                       PORTED  the whole argument layout
#   tinygrad/runtime/ops_metal.py:135 `args`         PORTED  `getaddr` is 8 bytes, a var is its own symbol=exec
#   tinygrad/runtime/ops_metal.py:136 `rows` / tinygrad/runtime/ops_metal.py:137 `nbytes` PORTED  `layout_args` and the `max` symbol=exec
#   :116-121 dims / sizes / cmds    PORTED  the symbolic-size arm and the tuple
#   :123 wait                       PORTED  a no-op, ON PURPOSE
#   :124 timestamp / :125 signal    PORTED  two appends
#   :127 submit                     PORTED  the ICB size and the header
#   :129 the placeholder size       PORTED  and it EQUALS :253's buffer size
#   tinygrad/runtime/ops_metal.py:155 patch          PORTED  three zero rows at `zero` symbol=submit
#   :135 the sizes loop             PORTED  one msgSend per symbolic command
#   :138 run                        PORTED  thirteen calls, four arms
#   :166-168 the submit tail        PORTED  three paths
#   :174 _alloc                     PORTED  the storage mode and refusal 3
#   :179 BufferStorage              PORTED  gpuAddress then contents
#   :180 _free                      PORTED  synchronize, mark_resident, release
#   :185 _offset                    PORTED  `D.host_offset`, device.bend's own -- upstream offsets a buffer in `_offset`
#   :185 pm_encode / :188 pm_lower  WALL 5  THE UOp MATCHER
#   :196 __init__                   PORTED  the twelve statements, in order
#   :201 the queue refusal          PORTED  refusal 4
#   :204-206 the residency set      PORTED  three calls, conditional
#   :213 check_family               PORTED  the reverse lookup
#   :214 arch                       PORTED  `[12:]` of the family name
#   :216 pm_bufferize               GONE    upstream deleted it; the section below
#   :222 sels                       PORTED  18 u64 = 144 bytes, and the [3:5]
#   :228 mark_resident              PORTED  both paths, and they are exclusive
#   tinygrad/runtime/ops_metal.py:238 `link_buffer`  GONE    upstream deleted `new_slots` (9ff6db7b0); `link_buffer` replaced it symbol=link_buffer
#   tinygrad/runtime/ops_metal.py:244 `pipeline`     PORTED  four calls and `checked` twice symbol=pipeline
#   :251 new_icb                    PORTED  the size and the eleven steps
#   :258 the ICB refusal           PORTED  refusal 5
#   :262 the local-size refusal     PORTED  refusal 6, PER COMMAND
#   :270 _wait_signal               PORTED  and refusal 7
#   :275 synchronize                PARTIAL the index arithmetic, not the times
#   :284-285 the autorelease pool   PORTED  pop-then-push, in that order
#   :267 the ICB weak-dict         PORTED  `icb_keep`, and it WAS not called -- upstream stores the ICB entry in `self.icbs`
#   tinygrad/runtime/ops_metal.py:276-281 the profile scan PORTED  `dev.sync_scan` -- upstream's `profile_slots` scan -- and it WAS NOT CALLED symbol=synchronize
#   :42-71 compile                 CLOSED  all of it but the block pointer
#   --    THE CONSTANTS            PORTED  65 with a CPython authority, all gated
# END BLOCK
