# Alfvén concept look-spike (scratch, not engine code)

The CPU stand-in that produced `docs/VISUAL_REFERENCES/alfven/`. Pseudo-spectral 2D MHD —
a **different numerical scheme** from the shipping GPU Jacobi projection. Keep it for
reference-frame regeneration and A/B comparison; it is not a porting source and imports
nothing from Uzume.

- `alfven.py` — the driven solver used for the reference film (rfft, Hou-Li filter, re-seed).
- `rmhd.py`   — the earlier complex-FFT version; kept because the two killed spikes ran on it.
- `film.py`   — the render pass (palette, filmic curve, seam bloom). The Metal fragment
                shader should reproduce THIS, not invent its own look.
- `audio.py`  — band envelopes + D-026-style deviation primitives from a fixture track.

Regenerate the reference film:
    python3 audio.py so_what
    ALF_N=256 ALF_TAG=v3 ALF_RESEED=170 python3 alfven.py so_what 576 0.074
    python3 film.py film_so_what_v3 so_what 720

Requires numpy, scipy, pillow. Expects `so_what.wav` decoded from
`UzumeEngine/Tests/Fixtures/tempo/so_what.m4a`.
