# User Item Descriptions

Design specifications for items to implement. These are the source of truth for item mechanics.

---

## BODY Items

### Brass Knuckles
- +1 attack per turn (can probably use cooldown for this?)
- Improve strength scaling
- Both effects scale with item level

### Baseball Bat
- Add a multiplier to body damage, scales with item level
- Changes attack to "swing bat"

### Wheatie-O's Cereal
- Increase BODY stat by +1 per level

### Trail Mix
- Ziploc bag of assorted trail mix
- Improve hp regen
- Rarest of the bunch

### Shovel
- Changes BODY attack to "Shovel Hit" (physical)
- Sweeping attack that hits an adjacent enemy AND the two tiles next to it (perpendicular to the line between the player and the target)
- Also improves item spawn rate
- Item spawn rate improvement scales with item level

### Siren's Cords
- EPIC rarity BODY item
- Transforms BODY attack to "Siren Scream" (sound-based AOE)
- Adds "sound" tag, removes "melee" tag
- Changes attack pattern to AOE_AROUND (like whistle)
- +0.5 range per level
- Synergizes with Coach's Whistle (sound damage multiplier applies!)
- Example combo: Brass Knuckles + Siren's Cords + Coach's Whistle = multiple sound AOE attacks per turn

---

## MIND Items

### Binoculars
- Should increase PERCEPTION dramatically
- Scale moderately with level

### Coach's Whistle
- Double damage if the MIND attack is sound based
- Need to add tags to attacks for this
- Scales as it levels up

### Siren's Cords (MOVED TO BODY)
- See BODY section

### Drinking Bird
- One of those water sipping bird toys, as featured on the Simpsons
- Description: "For the thinking man, now with Verve!"
- Gives a %-based reduction to all cooldowns
- % scales with item level (asymptotically reaches 50% reduction around level 20)

### Telepathic Punching Item (TBD)
- Something that turns the MIND attack from a whistle to telepathic punching
- Design not finalized

---

## NULL Items

### Lucky Rabbit's Foot
- For a small mana cost and small cooldown
- Has a small chance to reset another item's cooldown randomly
- Chance improves with level

### Roman Coin
- Improves mana regen

### Antigonous Family Notebook
- RARE item
- Increase corruption by some amount per item level
- Big increase to NULL stat
- With enough mana: negates the next damage source once per cooldown
