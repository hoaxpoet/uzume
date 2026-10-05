import sys
from PIL import Image, ImageDraw
im = Image.open("ref.png").convert("RGB"); d = ImageDraw.Draw(im)
for x in range(0, 1672, 25):
    d.line([(x,0),(x,941)], fill=(255,255,255) if x%100==0 else ((150,150,150) if x%50==0 else (60,60,60)), width=1)
    if x%100==0: d.text((x+2,2), str(x), fill=(255,255,0))
for y in range(0, 941, 25):
    d.line([(0,y),(1672,y)], fill=(255,255,255) if y%100==0 else ((150,150,150) if y%50==0 else (60,60,60)), width=1)
    if y%100==0: d.text((2,y+2), str(y), fill=(255,255,0))
x0,y0,x1,y1 = map(int, sys.argv[1:5])
c = im.crop((x0,y0,x1,y1)); s = float(sys.argv[5]); c = c.resize((int(c.width*s), int(c.height*s)))
c.save(sys.argv[6])
