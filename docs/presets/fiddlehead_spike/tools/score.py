import sys
from edgefine import edgefine; from aspect import aspect; from pinnagap import pinnagap
print(f"{'':44s} fine-edge lit  aspect gaps dark   (ref 0.44 0.62 1.85 2.8 0.15)")
for p in sys.argv[1:]:
    e, l = edgefine(p); g, d = pinnagap(p); print(f"{p:44s} {e:.2f}  {l:.2f}  {aspect(p):.2f}  {g:.1f}  {d:.2f}")
