import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from cut import apply

F = "tinybendygrad/engine/realize.bend"

# **THE **MERGED **LINE**: **TWO **`[b]` **ENTRIES **ON **ONE **LINE**, **⇒⇒† AND **THE **LIST
# **IS **ONE **ENTRY **PER **LINE**, **⇒⇒† AND **SO **THE **MERGE **IS **A **TRUNCATION **AND
# **NOT **A **CUT**.
EDITS = [
  (46, 47, """#                                             is a WALL in codegen/kernel.bend
# [b] realize.py:60   first_run_cache       -- a process-global `set[bytes]`"""),
]

apply(F, EDITS)
