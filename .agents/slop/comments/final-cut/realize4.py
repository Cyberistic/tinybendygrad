import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from cut import apply

F = "tinybendygrad/engine/realize.bend"

# **THE **GATE'S **ROW **TABLE**: **A **LIST **OF **ROWS **WITH **WHAT **EACH **IS **FOR**, **⇒⇒†
# AND **A **LIST **OF **ROWS **IS **DATA**, **⇒⇒† AND **IT **MOVES **TO **THE **TABLE **FILE**.
EDITS = [
  (2199, 2295, """# THE GATE, and what each row is FOR, IS IN
# `.agents/slop/tables/engine-realize-2205.md` -- THE ROW NAMES AND WHAT EACH ONE PINS."""),
]

apply(F, EDITS)
