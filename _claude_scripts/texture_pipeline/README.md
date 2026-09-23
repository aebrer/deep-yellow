# Floor texture pipeline

Tools for turning a full-bleed image-model material scan into a floor texture that
survives this game's renderer, plus the measurements that decide whether it is allowed to
ship. This is the pipeline behind the level -1 / 0 / 1 floor set and the exit-hole decal
(installed 2026-09-23).

For the older per-asset procedural pixel-art generators, see `../textures/<name>/generate.py`.
Those are 128px originals; this pipeline is for high-resolution scans that get
deliberately filtered down to what the renderer can resolve.

    venv/bin/python _claude_scripts/texture_pipeline/<tool>.py ...

## The one idea everything else follows from

`psx_base.gdshaderinc` scales UVs (`UV = UV * uv_scale + uv_offset`, vertex stage) and
*then* snaps them (`(floor(uv * pixel_snap_resolution) + 0.5) / pixel_snap_resolution`,
fragment stage, `pixel_snap_resolution` defaults to 128 from `utilities.gd`), sampling with
nearest filtering. So a floor never shows more than 128 texels per texture repeat, no
matter how large the PNG is, and it is **point-sampled**, not filtered.

`game_sim.py` reproduces that exactly. Never judge a floor texture from a filtered
preview: resizing with LANCZOS (or looking at the 1024 PNG in an image viewer) hides both
defects the player actually sees — it smooths away the soft banding along tile junctions,
and it removes the moiré that point sampling invents. Every number in this file came from
`game_sim`-based tools.

    python3 game_sim.py            # no CLI; import tiled()/snap_sample() into your own check

## Pipeline

| step | tool | what it is for |
|---|---|---|
| 1 | `make_tileable.py` | repair the wrap seam, flatten low frequencies, delete the generator's frame, colour-match, pre-filter |
| 2 | `polish.py` | add pile (carpet), keep placed objects out of whole-image passes, re-match colour after the repair |
| 3 | `add_grout.py` | draw crisp procedural grout over a ceramic surface scan |
| 4 | `make_hole.py` | build the one-tile exit-hole decal against the floor it will be drawn on |
| check | `banding.py`, `score.py` | the gates below |
| review | `tile_composite.py`, `blind_panel.py` | tiled sheets, and shuffled neutrally-named panels for a reviewer |

## Measurements that gate a texture

Numbers in brackets are what the shipped set actually scored, against the texture it
replaced.

1. **`banding.py`** — centre-cross and border-frame luma offsets, measured with a median
   per border line so a cardboard sheet or puddle does not register as a defect.
   Uniform materials must be inside **±1.5 luma**. [carpet 0.1–1.3, snow 0.0–1.3, was
   ±6–8] Meaningless on a gridded surface (a tile grid is meant to vary) and on a decal
   with a hole in it — use 2 and 4 there.
2. **`banding.py --lines`** — per-grid-line depth and spread. Spread under **5 luma**.
   [pool 2.0 columns / 4.4 rows, was 9.4]
3. **`score.py`** — `alias` is how much detail the point sampling invents (want near 1.0);
   `detail` and `grid` are only meaningful **relative to the texture being replaced**, never
   in isolation. [carpet 1.6× vs 2.6×, snow 1.2× vs 1.7×, pool 1.2× vs 2.0×]
4. **`banding.decal_join()`** — the step across the four joins around a one-tile decal,
   against the same four joins with an ordinary tile in place. Want **1.0**. [hole 0.99,
   was 1.24]
5. **Tone parity** — whole-image mean RGB within ~0.01 of the replaced texture, and check
   warm `R−B` separately. Brightness drift is invisible in a contact sheet and obvious in
   a lit room; a hue shift toward grey makes a carpet read as asphalt. [carpet warm +0.148
   vs +0.152, snow meanL 0.453 vs 0.454]

## Lessons, in order of how much they cost to learn the hard way

**Never ask the image model for a tileable texture.** Asking for tileability makes it paint
a soft band along the border — and that band *is* the "odd blur at the tile junctions"
complaint, because the band repeats at every junction. Generate a full-bleed material scan
and make it tileable afterwards.

**The generator frames every scan.** The outer few percent comes out a few luma darker and
the middle a few luma brighter. It is separable (one offset per row, one per column), and
separable banding is precisely what the eye reads as a grid once the tile repeats.
`--frame` subtracts it, measured per row/column. Do it *after* the seam repair, which adds
its own band.

- Use `--no-frame-mask` for uniform materials. The mask (`object_mask`) exists to exclude a
  hero object from the estimate, but on a noisy carpet it also catches grain and biases the
  result.
- Do **not** run `--frame` on a composed variant (cardboard, puddle). The object dominates
  the profile, and matching it drags a compensating gradient through the rest of the tile —
  measured worse than doing nothing (puddle centre −7.5 → −14.9 luma).

**Pre-filter to what the snap can resolve.** Anything above roughly 64 cycles per tile is
point-sampled and folds back as moiré. Incoherent grain folds back into more grain and is
harmless; a *coherent* weave or stripe folds back into a moving grid, which is what a
player calls a seam. `--antialias` is applied last so it also catches grain the seam repair
injects. `--antialias 2` took the carpet from 5.4× invented detail to 1.6×.

**Flatten the low frequencies, then put structure back on purpose.** `--flatten 0.85
--flatten-radius 200` removes the tonal mottle that repeats as a grid; on its own that
leaves a flat plane, which reads as wet asphalt. `polish.py --pile` re-adds directional
fibre at a scale that survives the downsample (`--pile-across 8 --pile-along 26` at 1024 ≈
1–3 texels). The pair is the answer — neither half works alone, and both the "too blurry"
and "too flat" complaints come from running only one of them.

**Match colour after the repair, on the ring, means only.** Three separate traps:

- `make_tileable.py` matches before rebuilding the border, and the repair moves the ring
  stats back. `polish.py --match` reapplies it as the last step.
- Match the outer ring, not the whole image, whenever the tile has a subject — the subject
  must not set the floor's colour.
- `--match-std 0` (mean only). Matching the reference's *contrast* copies the contrast of a
  blurry, over-flattened outgoing texture and undoes all the detail work.

**A decal that covers exactly one tile is a floor tile, not a sticker.** `make_hole.py`
low-passes the plate until its detail matches the floor's, removes its frame, matches the
*ring* (a whole-image match lets the black void drag the ground tone), then cross-fades its
border onto the floor's own pixels — which is what makes the join an ordinary ground-to-
ground join. Separately, it must be drawn with the lit shader (`shaders/psx_lit_decal.gdshader`,
material derived from the level's floor material in `grid_3d.gd`): an unshaded decal cannot
match a lit floor at any albedo, and that was the original "the hole is too bright" report.

**Keep grid lines off the wrap, and an integer number of texels wide.** A grout line
straddling the texture edge is drawn as two halves that come out a different depth from the
interior lines (9.4 luma spread → a heavier grid every 2 m). `add_grout.py --phase 0.5`
moves the join into a tile, where the tile's own edge hides it (spread 2.0). And 16px at
1024 is exactly 2 texels at the 128 snap; 20px would be 2.5 and would pop as the snap grid
shifts.

**Check a review finding before acting on it.** Reviewers caught the carpet's dark cross
(the seam repair band sitting at the tile centre) and the decal's bright frame, both real
and both fixed. The same reviewers reported 1-texel grout (it is 2, on a 16-texel pitch,
aligned to texel boundaries) and a pool floor that would blow out (it renders *darker* than
what it replaced, which was clipping to pure white). Reproduce the number first. When a
measurement disagrees with a reviewer, check whether their baseline was fair — comparing a
decal join against a *seam-repaired* floor's wrap join flatters the floor, not the decal.

**Expect to iterate on identity, not just seams.** The first carpet passed every seam
metric and still failed because it had drifted to neutral grey. Generate against the
outgoing texture as a reference image, and keep the outgoing file to match colour to:

    mkdir -p prev && git show HEAD:assets/levels/level_00/textures/carpet_brown.png > prev/carpet_brown.png

## Reproducing the shipped set

Reference the outgoing textures first (see above), then run from the project root. `polish
--match` targets the finished base carpet so the variant tiles agree with it, and
`make_hole` targets the installed snow so the decal matches what it is drawn over.

    P=_claude_scripts/texture_pipeline
    R=$P/raw

    # level -1 ground
    venv/bin/python $P/make_tileable.py $R/snow_dirt_raw.png snow.png \
        --band 28 --flatten 0.45 --frame 1.0 --no-frame-mask --antialias 2 \
        --match prev/snow_dirt.png --match-std 0

    # level 0 carpet — flatten hard, then add the pile back
    venv/bin/python $P/make_tileable.py $R/carpet_brown_raw.png carpet.png \
        --band 20 --flatten 0.85 --flatten-radius 200 --frame 0.85 --no-frame-mask \
        --antialias 2 --match prev/carpet_brown.png --match-std 0
    venv/bin/python $P/polish.py carpet.png FINAL_carpet_brown.png \
        --pile 0.030 --pile-along 26 --match prev/carpet_brown.png

    # level 0 variants — no --frame (see the frame lesson), pile protected off the subject
    venv/bin/python $P/make_tileable.py $R/carpet_cardboard_raw.png card.png \
        --band 20 --antialias 2 --match FINAL_carpet_brown.png --match-std 0
    venv/bin/python $P/polish.py card.png FINAL_carpet_cardboard.png \
        --pile 0.030 --pile-along 26 --match-object prev/carpet_cardboard.png \
        --protect-objects --match FINAL_carpet_brown.png

    venv/bin/python $P/make_tileable.py $R/carpet_puddle_raw.png pud.png \
        --band 20 --antialias 2 --match FINAL_carpet_brown.png --match-std 0
    venv/bin/python $P/polish.py pud.png FINAL_carpet_puddle.png \
        --pile 0.030 --pile-along 26 --protect-objects --match FINAL_carpet_brown.png

    # level 1 poolroom — ceramic scan, then procedural grout (the model cannot draw grout)
    venv/bin/python $P/make_tileable.py $R/pool_surface_raw.png pool.png \
        --band 20 --flatten 0.5 --frame 0.85 --no-frame-mask
    venv/bin/python $P/add_grout.py pool.png FINAL_pool_floor.png \
        --cells 8 --width 16 --tile-var 0.05 --grout 0.40,0.39,0.37

    # exit hole — built against the installed snow floor
    venv/bin/python $P/make_hole.py $R/exit_hole_raw.png \
        assets/levels/level_neg1/textures/snow_dirt.png FINAL_exit_hole.png \
        --std-blend 0.5 --grain 1.0 --blend-border 96

    # gates
    venv/bin/python $P/banding.py FINAL_*.png
    venv/bin/python $P/banding.py --lines FINAL_pool_floor.png
    venv/bin/python $P/score.py FINAL_carpet_brown.png prev/carpet_brown.png

Then install, reimport, and validate:

    godot --headless --path . --import
    godot --headless --path . --quit
    godot --headless --path . --script scripts/tools/verify_sprite_snap.gd

## Known gaps

- **Walls, ceilings and water were not redone.** They came out of the same generator and
  still carry the soft frame; `banding.py` will show it.
- **A variant tile's subject repeats once per tile.** Accepted, and the originals did the
  same. Breaking it means authoring 2–3 offset variants and registering them in
  `assets/level_00_mesh_library.tres`, not editing these textures.
- **Mipmaps and VRAM compression live in `*.import`, and those files must stay tracked.**
  They were ignored for a while, which meant a fresh clone re-imported the poolroom floor
  and the exit-hole decal without mipmaps — the crisp grout crawls at distance, and nothing
  on the importing machine shows it. If a floor looks different on someone else's build,
  diff its `.import` before suspecting the pixels.
- `raw/` holds the six scans that shipped (16 MB). Rejected generations are not kept; they
  are reproducible from the prompts in the git history of this branch.