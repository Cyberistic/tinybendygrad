== THE BASELINE, the snapshot as frozen ==
   cite.total                                       2624
   cite.checkable                                   1624
   cite.at_pin                                      760
   cite.only_older_revision                         376
   cite.at_no_revision                              488
   cite.at_no_revision_dangling                     14
   cite.ambient_relocated                           4
   cite.unverifiable_no_claim_about_the_file        240
   # pin-cite-gate: FAIL -- 14 citations name ONE upstream file and hold at NO upstream revision (a dangling claim)   (rc=1)
   the target row: at_pin  at_pin=HOLDS  present_in_file='gdrive_download'

== CONTROL ==
   the edited file is byte-identical to the snapshot: True
   cite.at_pin                                         760  (base 760)
   cite.only_older_revision                            376  (base 376)
   cite.at_no_revision                                 488  (base 488)
   cite.at_no_revision_dangling                         14  (base 14)
   cite.ambient_relocated                                4  (base 4)
   cite.unverifiable_no_claim_about_the_file           240  (base 240)
   # pin-cite-gate: FAIL -- 14 citations name ONE upstream file and hold at NO upstream revision (a dangling claim)   (rc=1)
   the target row: at_pin  at_pin=HOLDS  newest_rev=e6c7c3e499e8  present_in_file='gdrive_download'

== FALS-A ==
   the edited file is byte-identical to the snapshot: False
   cite.at_pin                                         759  (base 760)  <-- MOVED
   cite.only_older_revision                            376  (base 376)
   cite.at_no_revision                                 489  (base 488)  <-- MOVED
   cite.at_no_revision_dangling                         15  (base 14)  <-- MOVED
   cite.ambient_relocated                                4  (base 4)
   cite.unverifiable_no_claim_about_the_file           240  (base 240)
   # pin-cite-gate: FAIL -- 15 citations name ONE upstream file and hold at NO upstream revision (a dangling claim)   (rc=1)
   the target row: dangling  at_pin=NO  newest_rev=NONE  present_in_file='gdrive_download'

== FALS-B ==
   the edited file is byte-identical to the snapshot: False
   cite.at_pin                                         759  (base 760)  <-- MOVED
   cite.only_older_revision                            376  (base 376)
   cite.at_no_revision                                 489  (base 488)  <-- MOVED
   cite.at_no_revision_dangling                         15  (base 14)  <-- MOVED
   cite.ambient_relocated                                4  (base 4)
   cite.unverifiable_no_claim_about_the_file           240  (base 240)
   # pin-cite-gate: FAIL -- 15 citations name ONE upstream file and hold at NO upstream revision (a dangling claim)   (rc=1)
   the target row: dangling  at_pin=NO  newest_rev=NONE  present_in_file='gdown'

== FALS-C ==
   the edited file is byte-identical to the snapshot: False
   cite.at_pin                                         759  (base 760)  <-- MOVED
   cite.only_older_revision                            376  (base 376)
   cite.at_no_revision                                 489  (base 488)  <-- MOVED
   cite.at_no_revision_dangling                         14  (base 14)
   cite.ambient_relocated                                4  (base 4)
   cite.unverifiable_no_claim_about_the_file           241  (base 240)  <-- MOVED
   # pin-cite-gate: FAIL -- 14 citations name ONE upstream file and hold at NO upstream revision (a dangling claim)   (rc=1)
   the target row: unverifiable  at_pin=NO  newest_rev=NONE  present_in_file=''

