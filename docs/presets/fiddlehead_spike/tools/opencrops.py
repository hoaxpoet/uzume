import sys
from PIL import Image
B = dict(whole=(0,0,1672,941), left=(200,300,700,780), right=(1000,300,1450,780), top=(800,30,1250,300), centre=(650,300,1000,941))
r, g = Image.open("ref_open.png").convert("RGB"), Image.open(sys.argv[1]).convert("RGB").resize((1672, 941))
for k, b in B.items():
    w, h = b[2]-b[0], b[3]-b[1]; s = 0.54 if k == "whole" else min(2.5, 800 / max(w, h))
    a, c = r.crop(b).resize((int(w*s), int(h*s)), Image.LANCZOS), g.crop(b).resize((int(w*s), int(h*s)), Image.LANCZOS)
    o = Image.new("RGB", (a.width*2+10, a.height)); o.paste(a, (0,0)); o.paste(c, (a.width+10, 0)); o.save(f"{sys.argv[2]}_{k}.png")
