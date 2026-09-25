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

**Always pass `transparent: true`.** This is the default path, not a special case. Without
it the model paints its own idea of a background — a flat white field, or a **magenta** one
(its training-time stand-in for alpha) — and that has to be keyed off, which is where the
pale-halo, white-speck and grey-wash defects all come from. Dark subjects are fine: the
drowner, which is nearly all black, came back through RGBA with a clean silhouette and
0.97/0.98 IoU against the shipped sprite. RGBA output arrives ready to composite.

**Ask for a cut-out with NO cast shadow** — "uniform pure white, hard edges, no contact
shadow, no reflection, no ground plane". A soft contact shadow is the most expensive thing
to key around: it pools under the object and between its parts, and no flood-fill can reach
it without also eating legitimate pale art (a fogged binocular lens is achromatic grey,
exactly like the wash, only dimmer; and the wash hides *behind* the shadow's dark core, so
connectivity can't route past it either). Cutting the shadow out costs one prompt line.

**Do not pass a reference image that contains a shadow.** The model copies the shadow out of
the reference and ignores the prompt. Regenerate text-only.

### Fallback: keying an image that came back opaque

Only for re-using older generations — prefer RGBA output above.

**Ask for a flat WHITE matte, never for darkness.** Prompting "most of the image is empty
darkness" makes the model paint a solid black field behind the subject, which renders as a
black card because sprites are alpha-cutout. Worse, that field is the same value as the
figure's own shadowed interior, so it cannot be keyed away without eating the art. Ask for
a plain flat white background and put the darkness *in the subject* — same separation, but
separable.

**Key only what is connected to the border, and cut hard.** The darkness inside the figure
must survive: the in-tone sprites keep a lot of opaque black, because the withheld
information is the art and the room's lighting will not supply it. `key_matte.py` flood-fills
from the canvas edges and stops at the silhouette, so a black body stays black and only the
field goes. The alpha is cut hard, never ramped: ramping across the model's contact shadow
leaves semi-transparent pixels whose RGB is still the field's colour, and those survive the
0.5 alpha cut and blend as pale specks. Undoing the blend is impossible — an un-premultiply
of pure white is still white at any alpha.

## Fitting a replacement into the old sprite's footprint

`fit_footprint.py`. A billboard's world size comes from its **canvas**, not its figure
(`Utilities.apply_snap_sprite` sizes entities on canvas WIDTH), so dropping a new
generation over an old PNG silently changes how big the creature is whenever the model
crops differently, and changes where its feet sit, because billboards are offset by a fixed
height. Scale the new figure to *contain* inside the old figure's visible box, preserving
its own aspect, then bottom-align and centre. Contain, not match-height: a crouched
replacement should stay crouched rather than being inflated to the old figure's height.
"Visible" means alpha >= 128, which is what the shader's alpha scissor keeps.

## Idle animation

Every entity and item animates as a 4-frame horizontal strip — the same shape
`barrel_fire` always shipped with. `assemble_frames.py` builds the strip; switching a sprite
on is one dict entry: `EntityRenderer.ENTITY_SPRITESHEETS` or
`ItemRenderer.ITEM_SPRITESHEETS`. Node construction is shared in
`scripts/world/animated_billboard.gd` (entities and items used to need separate copies).

Per sprite:

1. Generate frame 2 and frame 3 from the **shipped sprite as the reference image**, with
   `transparent: true`, asking for one clearly visible change and nothing else.
2. `assemble_frames.py base.png f2.png f3.png <name>_spritesheet.png --anchor bottom|centre --gif preview.gif`
3. `qa_sheet.py sheet.png ...` renders every frame through the same alpha cut the shader
   applies, on a dim room grey. Reading a 2048px atlas is how a frame that lost a limb,
   grew a black fin, or drifted off its floor line gets installed.
4. Watch the GIF, then read the IoU it prints.
5. Register the entry, `--import`, run
   `godot --headless --path . res://scenes/tools/verify_sprite_snap.tscn`. Commit the strip
   **and its `.import` file** — those are version-controlled now.

### Which colour knobs to turn off

`assemble_frames.py` matches each generated frame's per-channel means onto the base frame,
because the generator drifts colour (a greenish cast on a coin, a blown-out brass knuckles).
Two deviations from the default are deliberate:

* **`--level-brightness` for items.** Matching normally keeps the *overall* brightness change
  and removes only the per-channel cast — right for the vending machine and the glowing
  bacteria, where brightness IS the animation. For a static object the model's brightness
  drift is far larger than the highlight slide that was asked for, so items level it out too.
* **`--no-match-colour` for anything whose animation is a colour change.** A dead tube's
  orange ember or a dead dome's green pulse would otherwise be corrected straight back out
  as if it were a cast.

### Ceiling fixtures are a pair

A fixture's on and off states are separate strips (`CEILING_FIXTURE_SHEETS` in
`entity_renderer.gd`), because `LightFixtureBehavior` already swaps lit/dead art every turn.
Both states animate: the lit tube buzzes at 8 fps, the dead one struggles to strike at 2.
They are laid flat under the ceiling plane rather than billboarded, so they assemble with
`--anchor centre`.

**Hold the silhouette.** The first poolroom frame grew a 200-pixel drip hanging below the
housing. IoU barely noticed (a hairline is almost no area) but the loop popped: a drip that
appears and vanishes is a rendering bug, not weather. Say so in the prompt — "nothing may
stick out beyond the housing, no drips, no strands".

Playback order is baked into the strip as `1,2,3,2`: neutral, sway, neutral, sway-back. Two
generated frames give a cycle that closes with no pop, at two generations per sprite.

**The contract is what the game draws.** Billboards use `ALPHA_CUT_DISCARD` at 0.5, so
everything under alpha 128 is discarded — the generator's low-alpha haze (measured at
9-10/255) never reaches the screen, and neither does a sprite's own faintest art. Frames are
binarised at 128 and judged on that rendered silhouette, and preview renders apply the same
cut. A normal image viewer shows defects the player never sees and hides ones they do.

**Amplitude.** barrel_fire — the reference Drew holds up — has adjacent-frame IoU of
0.87-0.93 and a bbox that swings 385 to 458 px. Prompts phrased as "a few percent" come back
too tame (IoU 0.97, barely moves). Ask for a clearly visible change.

**What drifts.** Solid subjects hold: drowner 0.97/0.98. Sparse, ghost-like subjects do not:
the smiler came back at 0.36, because when only 5% of the canvas is sprite the model invents
mass (bigger grin, violet glow) rather than swaying it. Keeping that jank is a deliberate
call — it suits the chaotic liminal tone — but the IoU is printed per sprite so a QA pass can
pick out the ones that went too far.

`--anchor bottom` for anything standing on the floor (feet must not float or sink),
`--anchor centre` for floating things (the smiler's face, hanging fixtures).


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