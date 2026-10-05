import sys
from PIL import Image
# boxes in reference coords (1672x941): whole, coil, coil-rim, inner coil, lower pinnae, stalk
B = dict(whole=(0,0,1672,941), coil=(800,40,1240,620), rim=(1000,60,1240,330), inner=(860,250,1100,480),
         lower=(380,450,900,941), upper_left=(500,150,800,560))
def pair(ref, got, tag):
    r, g = Image.open(ref).convert("RGB"), Image.open(got).convert("RGB").resize((1672,941))
    for k, b in B.items():
        w, h = b[2]-b[0], b[3]-b[1]; s = min(1.0, 900/max(w,h)) if k=="whole" else max(1.0, 700/max(w,h))
        a, c = r.crop(b).resize((int(w*s), int(h*s))), g.crop(b).resize((int(w*s), int(h*s)))
        out = Image.new("RGB", (a.width*2+10, a.height)); out.paste(a, (0,0)); out.paste(c, (a.width+10,0))
        out.save(f"{tag}_{k}.png")
pair(sys.argv[1], sys.argv[2], sys.argv[3])
