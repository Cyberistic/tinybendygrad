import Base
import ./LAWS/spec.bend as S

def both(a: Bool, b: Bool) -> Bool:
  match a:
    case True{}: b
    case False{}: False{}

def main() -> Bool: both(True{}, True{})
