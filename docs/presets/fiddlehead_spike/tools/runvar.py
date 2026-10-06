# Render variants with explicit env dicts (zsh doesn't word-split $VARS — a batch ran with knobs missing).
import os, subprocess, sys, json, itertools, re
def run(env, out, u="1"):
    e = dict(os.environ, W="1672", H="941", **{k: str(v) for k, v in env.items()})
    r = subprocess.run(["./fh5", "still", u, out], env=e, capture_output=True, text=True).stderr.strip()
    return r
if __name__ == "__main__":
    base = json.loads(sys.argv[1]); grid = json.loads(sys.argv[2]); outdir = sys.argv[3]
    os.makedirs(outdir, exist_ok=True)
    keys = list(grid)
    for vals in itertools.product(*[grid[k] for k in keys]):
        env = dict(base, **dict(zip(keys, vals)))
        name = "c_" + "_".join(f"{k.split('_')[0].lower()}{v}" for k, v in zip(keys, vals)) + ".png"
        print(name, run(env, os.path.join(outdir, name)))
