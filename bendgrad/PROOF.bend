import ./LAWS.bend as L
import ./LAWS/spec.bend as S

# tinyspec "Movement Ops": Reshape is "Reinterpret in row-major order.
# prod s_k = prod s'_k". The shape column of Reshape IS the dst list, so its count
# is prod dst, and the spec's constraint is the whole content of the law.
def L.reshape_preserves_numel(t, dst, premise):
  premise

# Same row, other side of the constraint: the shape column alone fixes the count.
def L.reshape_numel_is_the_new_shape(t, dst):
  {==}

# tinyspec "Movement Ops": Permute is "Reorder axes", shape "src[0].shape", so
# the count is src[0]'s by construction.
def L.permute_preserves_numel(t, order):
  {==}

# Same, Flip: "Reverse along flagged axes", shape "src[0].shape".
def L.flip_preserves_numel(t, flags):
  {==}

# tinyspec "Movement Ops": Pad places T "in an invalid-filled output of shape
# s'_k", so the count is the new shape's and the fill pattern never enters it.
def L.pad_numel_is_the_new_shape(t, off, size):
  {==}

# tinyspec "Movement Ops": Shrink "Keep s'_k elements starting at offset o_k per
# axis", so the count is the narrowed shape's.
def L.shrink_numel_is_the_new_shape(t, off, size):
  {==}

# tinyspec "Movement Ops": Shrink is the "Inverse of Pad". Its shape column is
# again s', so shrinking out of a pad of that size returns the original count.
def L.pad_shrink_round_trip(t, off, size, premise):
  premise

# tinyspec "Marker Ops -- identity on data". The derived-properties table has no
# Detach row, so the port reads both properties as src[0]; this pins that dtype.
def L.detach_preserves_dtype(a):
  {==}

# Same marker-op reading, the shape column.
def L.detach_preserves_numel(a):
  {==}

# tinyspec "Movement Ops": Stack is "Join along a newly created leading axis",
# so a Stack of t and n more operands counts n+1 times t. The premise names t's
# shape so both sides reduce; the two rewrites put it in on the left, then on
# the right, and the products are the same fold.
def L.stack_numel_is_the_leading_axis_times_the_operands(t, rest, bs, premise):
  match bs:
    case S.Sh{bds}:
      %Equal.sym(Maybe<&2, S.Shape>, S.Sp.shape(t), Some{S.Sh{bds}}, premise) : {Maybe.default(&2, Nat, S.on_shape_nat(S.on_shape(_, s => Some{S.Shape.prepend(S.SN{Nat.add(List.length(&2, S.Sp, rest), 1n)}, s)}), sh => Some{S.prod(S.Shape.to_dims(sh))}), 0n) == Nat.mul(Nat.add(List.length(&2, S.Sp, rest), 1n), Maybe.default(&2, Nat, S.on_shape_nat(S.Sp.shape(t), sh => Some{S.prod(S.Shape.to_dims(sh))}), 0n)) : Nat}
      %Equal.sym(Maybe<&2, S.Shape>, S.Sp.shape(t), Some{S.Sh{bds}}, premise) : {Nat.mul(Nat.add(List.length(&2, S.Sp, rest), 1n), S.prod(bds)) == Nat.mul(Nat.add(List.length(&2, S.Sp, rest), 1n), Maybe.default(&2, Nat, S.on_shape_nat(_, sh => Some{S.prod(S.Shape.to_dims(sh))}), 0n)) : Nat}
      {==}
