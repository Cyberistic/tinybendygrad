# A DIFFERENT type named Empty: it HAS a constructor, so it is inhabited and
# it is not the empty type.  Base is not imported, so this shadows nothing.
type Empty is Data:
  C0{}

def bad() -> Empty:
  C0{}
