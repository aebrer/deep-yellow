---
name: generate-texture
description: >
  Generate a tileable texture asset for Deep Yellow using the virtuous cycle
  workflow. Use when Drew asks to "generate a texture", "create a texture",
  "make a texture", mentions needing a new texture for walls/floors/ceilings/
  entities/items, or says anything about procedural texture generation.
  Handles the full creator→critic→revision cycle with sub-agents.
---

# Generate Texture — Virtuous Cycle Workflow

Procedural texture generation using the iterative creator/critic sub-agent cycle.
You are the **conductor** — you never create or critique textures yourself.

## Your Role

```
YOU ARE: Orchestra conductor
YOU ARE NOT: Musician

You NEVER: write generate.py, run scripts, read output.png, critique textures
You ONLY: spawn agents → wait → synthesize feedback → repeat
```

## Prerequisites

- Python venv: `/home/drew/projects/deep_yellow/venv/`
- Output convention: `_claude_scripts/textures/<texture_name>/generate.py` → `output.png`
- All textures must be **tileable/seamless** unless explicitly stated otherwise

## Quick Start

Ask Drew:
1. **What texture?** (e.g., "yellow wallpaper", "concrete floor", "rusty metal door")
2. **Dimensions?** (default: 128×128)
3. **Any reference?** (Backrooms wiki page, photo, description)

Then enter the cycle.

## The Cycle

### State Machine

Track your state explicitly. You may ONLY perform the allowed actions for your current state.

```
CURRENT STATE: [ SPAWNING_CREATOR | AWAITING_CREATOR | PREPARING_CRITICS | AWAITING_CRITICS | SYNTHESIZING | DONE ]
```

| State | Allowed Actions | Forbidden |
|-------|----------------|-----------|
| SPAWNING_CREATOR | Spawn ONE creator agent via Task tool | Writing code, spawning critics |
| AWAITING_CREATOR | Wait for creator agent to return | Anything else |
| PREPARING_CRITICS | Copy output.png to /tmp with random hash name | Reading the image yourself |
| AWAITING_CRITICS | Spawn comparison + blind critic agents, wait | Analyzing images yourself |
| SYNTHESIZING | Read critic reports, draft revision notes | Spawning agents, editing code |
| DONE | Report to Drew, move file into place | Starting new iterations |

### Anti-Pattern Checklist (Before EVERY Action)

```
[ ] Am I about to write/edit generate.py myself? → STOP, spawn creator
[ ] Am I spawning agents in parallel during the cycle? → STOP, go sequential
[ ] Am I giving blind critic ANY context? → STOP, check for info leakage
[ ] Am I reading/analyzing output.png myself? → STOP, that's the critics' job
[ ] Am I using anything other than the Task tool to spawn agents? → STOP
```

---

## Step-by-Step

### Step 1: Gather Requirements

Confirm with Drew:
- Texture description (visual style, colors, patterns, weathering)
- Dimensions (default 128×128)
- Reference material (URLs, descriptions, existing textures to match)
- Material destination (which .tres file, what surface type)

### Step 2: Spawn Creator Agent

**State: SPAWNING_CREATOR**

Spawn a Task agent (`subagent_type: "general-purpose"`) with this context:

```
You are a procedural texture creator. Your job:

1. Create a Python script at: _claude_scripts/textures/<NAME>/generate.py
2. The script MUST output: _claude_scripts/textures/<NAME>/output.png
3. Requirements: <FULL DESCRIPTION FROM DREW + ANY REVISION NOTES>

Technical requirements:
- Run in venv: /home/drew/projects/deep_yellow/venv/
- Install any needed packages (pip install)
- Texture MUST be tileable/seamless
- Use modulo wrapping for ALL pixel operations: img_array[y % SIZE, x % SIZE]
- Pattern dimensions must divide texture size evenly
- PIL ImageDraw clips at boundaries — use pixel-level drawing with modulo for wrapping
- You have full creative freedom: PIL, NumPy, noise libraries, Cairo, etc.

Steps:
1. Create the generate.py script
2. Install dependencies if needed: cd /home/drew/projects/deep_yellow && source venv/bin/activate && pip install <packages>
3. Run: cd /home/drew/projects/deep_yellow && source venv/bin/activate && cd _claude_scripts/textures/<NAME> && python generate.py
4. Verify output.png was created and check its dimensions

If this is a REVISION, here is what the critics said: <CRITIC FEEDBACK>
Modify the existing generate.py to address their feedback.
```

**Then WAIT for the creator to finish.**

### Step 3: Prepare for Critics

**State: PREPARING_CRITICS**

Copy the output to a neutral location to prevent information leakage to the blind critic:

```bash
cp _claude_scripts/textures/<NAME>/output.png /tmp/texture_review_$(openssl rand -hex 4).png
```

Note the random filename for the blind critic.

### Step 4: Spawn Critics

**State: AWAITING_CRITICS**

Spawn TWO Task agents (these CAN run in parallel — they're independent):

**Comparison Critic** (`subagent_type: "general-purpose"`):
```
You are a texture quality critic. Review the texture at:
  _claude_scripts/textures/<NAME>/output.png

It should match this description: <ORIGINAL REQUIREMENTS>

Evaluate:
1. Does it match the visual description? (colors, patterns, style)
2. Does it look tileable? (check edges — do left/right and top/bottom align?)
3. Any obvious artifacts, banding, or generation errors?
4. Overall quality assessment

Be specific about any issues. "Looks good" is not helpful — describe what you see.
```

**Blind Critic** (`subagent_type: "general-purpose"`):
```
You are a texture reviewer. Look at the image at:
  /tmp/<RANDOM_HASH_FILENAME>.png

Describe what you see. Be specific about:
1. What does this image depict?
2. Does it look like it would tile seamlessly? (check edges)
3. Any artifacts, oddities, or quality issues?
4. What is the overall impression?

Just describe what you observe — no other context is needed.
```

**CRITICAL**: The blind critic gets ONLY the /tmp path. No texture name, no description, no context.

**Then WAIT for both critics to return.**

### Step 5: Synthesize Feedback

**State: SYNTHESIZING**

Read both critic reports. Decide:

- **Both approve** → Move to Step 6 (DONE)
- **Issues found** → Draft specific revision notes, return to Step 2

Revision notes should be actionable:
- "Reduce saturation by 20%" not "looks too bright"
- "Fix tiling — left edge doesn't match right edge, use modulo wrapping" not "tiling is off"
- "Add subtle vertical lines every 32px" not "needs more detail"

Share the synthesis with Drew and confirm whether to iterate or accept.

### Step 6: Finalize

**State: DONE**

Report to Drew:
- Show the final texture path: `_claude_scripts/textures/<NAME>/output.png`
- Summarize what the critics said
- Note how many iterations it took
- Ask if Drew wants to test it in-game or if any manual tweaks are needed

If Drew needs the texture imported into a Godot material (.tres), help with that as a separate step.

---

## Iteration History

Optionally save iteration snapshots:

```
_claude_scripts/textures/<NAME>/
├── generate.py          # Final script
├── output.png           # Final texture
└── iterations/          # History (optional)
    ├── v1.png
    ├── v2.png
    └── v3.png
```

## Key Lessons (from real usage)

- **Tiling is the hardest part** — expect 2-4 iterations minimum for seamless tiling
- **PIL ImageDraw clips at boundaries** — pixel-level drawing with modulo is more reliable
- **Pattern dimensions must divide texture size** — 32px repeat on 128px = 4 clean repeats
- **"Serviceable" tiling is often good enough** — tiny imperfections are fine for game textures
- **Drew's corrections save iterations** — relay user feedback verbatim to the creator
- **Typical cycle: 3-7 iterations** — don't rush, the cycle exists for a reason

## Notes

- The creator agent has full creative freedom with Python — any library, any technique
- Always activate the venv before running: `source /home/drew/projects/deep_yellow/venv/bin/activate`
- Blind critic information leakage is the #1 workflow failure — be paranoid about it
- You can spawn comparison + blind critics in parallel (they're independent)
- Everything else is strictly sequential
