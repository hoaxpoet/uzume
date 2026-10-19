"""Render a Shadertoy single-pass shader (mainImage) headlessly with Mesa llvmpipe.
usage: python3 st_render.py shader.glsl outdir W H t0 t1 fps [params.json]
If params.json is given, per-frame uniforms are read from it (frames[i] dict, keys become
uniforms named u<Key> if declared in the shader; 't' drives iTime unless 'itime' present).
"""
import sys, os, json, numpy as np, moderngl
from PIL import Image

src = open(sys.argv[1]).read()
W, H = int(sys.argv[3]), int(sys.argv[4])
t0, t1, fps = float(sys.argv[5]), float(sys.argv[6]), float(sys.argv[7])
params = json.load(open(sys.argv[8]))['frames'] if len(sys.argv) > 8 else None
head = "#version 430\nuniform vec3 iResolution; uniform float iTime; out vec4 outColor;\n"
code = head + src + "\nvoid main(){ vec4 c; mainImage(c, gl_FragCoord.xy); outColor = vec4(c.rgb,1.0); }\n"
ctx = moderngl.create_standalone_context(backend='egl', require=430)
prog = ctx.program(vertex_shader="#version 430\nin vec2 p; void main(){gl_Position=vec4(p,0,1);}", fragment_shader=code)
vbo = ctx.buffer(np.array([-1, -1, 3, -1, -1, 3], 'f4').tobytes())
vao = ctx.vertex_array(prog, [(vbo, '2f', 'p')])
fbo = ctx.simple_framebuffer((W, H))
if 'iResolution' in prog: prog['iResolution'].value = (W, H, 1.0)
out = sys.argv[2]; os.makedirs(out, exist_ok=True)
n = int(round((t1 - t0) * fps))
for k in range(n):
    t = t0 + k / fps
    if params is not None:
        f = params[min(int(round(t * 30)), len(params) - 1)]
        for key, val in f.items():
            name = 'u' + key[0].upper() + key[1:]
            if name in prog:
                prog[name].value = tuple(val) if isinstance(val, list) else float(val)
        t = f.get('itime', t)
    if 'iTime' in prog: prog['iTime'].value = float(t)
    fbo.use(); fbo.clear(); vao.render()
    Image.frombytes('RGB', (W, H), fbo.read(components=3)).transpose(Image.FLIP_TOP_BOTTOM).save(f'{out}/f{k:04d}.png')
