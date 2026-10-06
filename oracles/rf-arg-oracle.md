### CLAIM COUNTS (first wins -- pm_add_buffers has several CALL patterns)
ab_claim_clik = 1
nic_claim_clik = 1
### ab_7 -- drop RESHAPEs on KERNEL, rangeify.py:267
ab7_clik_own  = ab7_clik = op_is_call=1 nsrc=2 src0_is_b4=0 arg_is_own_kernel=1 arg_is_none=0 is_self=0
ab7_clik0_own = ab7_clik0 = op_is_call=1 nsrc=2 src0_is_b4=0 arg_is_own_kernel=0 arg_is_none=1 is_self=0
ab7_clik_arg_is_object = 1
ab7_clik_arg_would_be_none = 0
### no_indexing_calls -- rangeify.py:143-158
nic_clik_own  = nic_clik = op_is_call=1 nsrc=2 src0_is_b4=0 arg_is_own_kernel=1 arg_is_none=0 is_self=0
nic_clik_arg_is_object = 1
### the OTHER two repaired sites: the arg is genuinely None there
raf_after_arg_is_none = 1 | op_is_AFTER = 1
mstack_arg_is_none = 1
ct8_claim_mstack = 0
