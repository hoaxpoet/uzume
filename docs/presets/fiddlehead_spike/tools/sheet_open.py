import sys, glob
from PIL import Image
B = [(200, 300, 700, 780), (1000, 300, 1450, 780), (800, 30, 1250, 300)]
for p in ["ref_open.png"] + sorted(glob.glob(sys.argv[1] + "/c_*.png")):
    im = Image.open(p).convert("RGB").resize((1672, 941)); tiles = [im.crop(b) for b in B]
    s = 1.5; tiles = [t.resize((int(t.width*s), int(t.height*s)), Image.LANCZOS) for t in tiles]
    W = sum(t.width for t in tiles) + 20; H = max(t.height for t in tiles); o = Image.new("RGB", (W, H)); x = 0
    for t in tiles: o.paste(t, (x, 0)); x += t.width + 10
    o.save(sys.argv[1] + "/sheet_" + p.split("/")[-1])
