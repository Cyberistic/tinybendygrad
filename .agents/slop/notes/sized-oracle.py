import sys; sys.path.insert(0, '.')
from tinygrad.uop.ops import _align_left                     # noqa: E402
from tinygrad.helpers import is_image_shape                  # noqa: E402

# `sized` is the (count, dims) pair every Bend shape walk carries; CPython has no
# such type, so the pair is spelled out here and `pad_to` is the fold's own name
# for `_align_left`'s per-shape half.
def sized(s): return (len(s), tuple(s))
def pad_to(s, max_dim): return (len(s), (1,)*(max_dim-len(s))+tuple(s))

def hx(s): return ' '.join(str(x) for x in s) or '-'

for tag, s in (('[2,3]', (2, 3)), ('[4]', (4,)), ('[2]', (2,)), ('[]', ())):
  print(f'sized({tag}) = {sized(s)}')
  print(f'  head={hx(sized(s)[1][:1])} last={hx(sized(s)[1][-1:])}')
for tag, s, m in (('([2,3],3)', (2, 3), 3), ('([4],3)', (4,), 3),
                  ('([2,3],2)', (2, 3), 2), ('([2],2)', (2,), 2),
                  ('([],3)', (), 3), ('([2,3,4],4)', (2, 3, 4), 4)):
  print(f'pad_to({tag}) = {hx(pad_to(s, m)[1])}')

# the two order-sensitive readers the commit named
print('is_image_shape((4,32,32)) =', is_image_shape((4, 32, 32)))
print('is_image_shape((32,32,4))  =', is_image_shape((32, 32, 4)))
print('_align_left((2,3),(4,))    =', _align_left((2, 3), (4,)))
print('_align_left((4,32,32),(2,3)) =', _align_left((4, 32, 32), (2, 3)))
