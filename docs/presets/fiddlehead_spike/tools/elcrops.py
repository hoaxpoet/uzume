import sys
from PIL import Image
B = dict(pinna=(600,560,900,760), rim=(1080,120,1240,330), coil=(860,250,1100,480), left=(480,180,660,640), whole=(0,0,1672,941))
r, g = Image.open("ref.png").convert("RGB"), Image.open(sys.argv[1]).convert("RGB").resize((1672, 941))
for k, b in B.items():
    w, h = b[2]-b[0], b[3]-b[1]; s = 0.54 if k == "whole" else min(3.0, 800 / max(w, h))
    a, c = r.crop(b).resize((int(w*s), int(h*s)), Image.LANCZOS), g.crop(b).resize((int(w*s), int(h*s)), Image.LANCZOS)
    o = Image.new("RGB", (a.width*2+10, a.height)); o.paste(a, (0,0)); o.paste(c, (a.width+10, 0)); o.save(f"{sys.argv[2]}_{k}.png")
