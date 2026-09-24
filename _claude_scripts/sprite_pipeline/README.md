# Sprite pipeline

Tools and findings for replacing a sprite in DEEP YELLOW. Written while fixing the two
things Drew flagged after the high-resolution art pass: sprites that looked like
stock-asset-library objects — "not liminal, not mysterious, just mundane and perfectly
hyperreal" — and the player avatar, which had no rear view at all.

    venv/bin/python _claude_scripts/sprite_pipeline/<tool>.py ...

## The art direction rule, in numbers

Billboard sprites in this game withhold information. Measured over the sprites nobody
complained about, at the size the renderer actually samples them:

| sprite | opaque black kept | figure mean luma | figure dark % |
|---|---|---|---|
| drowner | 38.3% of canvas | 25.6 | 88.2 |
| bacteria_motherload | 38.2% | 40.6 | 72.6 |
| antigonous_notebook | 18.8% | 48.5 | 66.1 |
| smiler | 2.9% | 84.2 | 59.3 |

Against the ones flagged as mundane: **38% average dark pixels vs 14%**. Two registers
pass and one fails. Either the sprite is mostly darkness with a cold rim or internal light
(drowner, bacteria, smiler's eyes and grin), or it is totally featureless (ambassador is a
flat white cut-out and reads perfectly). What fails is **fully lit AND fully detailed** —
evenly illuminated, every strand and scratch resolved, product-shot framing. So the target
is not a style change. Photoreal rendering is fine; what has to go is the *completeness*.

Pull the authored brief before writing a prompt — `entity_registry.gd` (`visual_description`,
`clearance_info`) and each item's `visual_description` in `scripts/items/`. The sodden is
"A waterlogged humanoid shape drags itself through the shallow pool… the pale blue cast of
something left underwater too long." That is the brief; the old art ignored it and drew a
bright blue yeti.

## Getting a usable cutout

**Ask for a flat WHITE matte, never for darkness.** Prompting "most of the image is empty
darkness" makes the model paint a solid black field behind the subject, which renders as a
black card because sprites are alpha-cutout. Worse, that field is the same value as the
figure's own shadowed interior, so it cannot be keyed away without eating the art. Ask for
a plain flat white background and put the darkness *in the subject* — same separation, but
separable.

**Key only what is connected to the border.** The darkness inside the figure must survive:
the in-tone sprites keep a lot of opaque black, because the withheld information is the
art and the room's lighting will not supply it. `key_matte.py` flood-fills from the canvas
edges and stops at the silhouette, so a black body stays black and only the field goes.
It also ramps the alpha across the model's soft contact shadow (a single threshold leaves a
pale halo on a light floor, which is what knocked the mould-crusted binoculars runner-up
out of contention).

`transparent=true` on the generator works fine for brightly-lit subjects — the hazmat rear
view came out with a clean alpha channel. It is specifically the low-key, dark-dominant
subjects that need the white matte.

## Fitting a replacement into the old sprite's footprint

`fit_footprint.py`. A billboard's world size comes from its **canvas**, not its figure
(`Utilities.apply_snap_sprite` sizes entities on canvas WIDTH), so dropping a new
generation over an old PNG silently changes how big the creature is whenever the model
crops differently, and changes where its feet sit, because billboards are offset by a fixed
height. Scale the new figure to *contain* inside the old figure's visible box, preserving
its own aspect, then bottom-align and centre. Contain, not match-height: a crouched
replacement should stay crouched rather than being inflated to the old figure's height.
"Visible" means alpha >= 128, which is what the shader's alpha scissor keeps.

## Measuring detail, and what the measurement gets wrong

`rank_detail.py` ranks sprites by broadband grain relative to tonal range, sampled at the
PSX Sprite Detail size. It is a **pre-filter, not a verdict**:

- It caught the sodden (0.239, 5th worst of 33) and agreed with Drew.
- It **missed the binoculars** (0.173, mid-pack) while his eye flagged them immediately.
  What is wrong with the binoculars is specular precision — crisp scratches, sharp lens
  reflections — which is not broadband grain, so the metric cannot see it.
- It inflates flat, low-contrast sprites: the ambassador scored as an outlier with the
  *lowest* grain of any sprite, because the ratio divides by a tiny tonal range. Read the
  absolute `micro` column alongside the ratio.

After the replacements: sodden 0.239 → 0.125, binoculars 0.173 → 0.146, both below the
outlier threshold. The sodden's drop came mostly from contrast now being carried by shape
(silhouette against rim light) rather than by grain — which is the actual goal.

## Picking

Generate a handful of variants per asset with genuinely different *ideas*, not prompt
noise — for the sodden: kneeling / standing featureless / prone dragging. Composite them
over the **real floor at game scale** (snap the level's tile to 128, apply the level's
modulate, drop the sprite into one 2 m cell) and compare against the asset's in-game
neighbours, not against white. Then check the tone table above. A candidate that reads
well on white is not evidence of anything; the poolroom floor is bright white tile, which
is exactly why a near-black silhouette works there.

## Player avatar note

The avatar draws `hazmat_suit_back.png`, not the front view. Its sprite is billboarded and
the player's facing *is* the camera's forward grid direction, so the camera is always
behind him — a front view always reads as facing the wrong way. The front view stays what
the minimap and map overlay draw, where a visible visor is the better icon.

## Remaining offenders

Flagged by measurement and not yet replaced, worst first: mustard, wheatie_os,
tutorial_mannequin, trail_mix, almond_water, roman_coin, lucky_rabbits_foot. Mustard and
wheatie_os share a specific failure the metric doesn't name: **legible micro-typography**
— readable brand lettering at 128px, which is the most product-photo thing about them.
Prompts should keep label layout and colour blocks (so the object stays identifiable) and
drop readable letters.