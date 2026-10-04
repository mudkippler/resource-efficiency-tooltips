# Resource Efficiency Tooltips

**How much does each point of mana, rage or energy actually buy you?** This addon adds the answer to the cost line of spell and ability tooltips. You can compare ranks and abilities at a glance without doing the maths yourself.

```
Frostbolt                     Rank 1
25 Mana  (0.76 dmg/mana)

Heroic Strike                 Rank 9
15 Rage  (10.5 dmg/rage)

Eviscerate                    Rank 1
35 Energy  (0.91 dmg/energy at 5 CP)
```

## Features

- **Damage, healing and absorb per point of resource** for mana, rage and energy. Each is colour-coded: orange for damage, green for healing and blue for absorbs.
- **Always matches the rank you're looking at.** Numbers come from the tooltip's own text, so every rank gives its own figure.
- **Spellbook report.** Type `/ret` to open a window listing every spell and rank in your spellbook that has a calculable efficiency, best first. Click a column header to sort by damage, healing or absorb, and hover a row to see the spell's tooltip.
- **Understands how abilities actually work:**
  - Damage-over-time and heal-over-time effects are added up over their full duration
  - Ranged damage like "31 to 45" uses the average
  - Spells with charges (e.g. Lightning Shield) count every charge
  - Summons that attack repeatedly (e.g. Searing Totem) count their damage over their lifetime
  - Mana Shield includes the mana it drains while absorbing
  - Instant weapon strikes (Sinister Strike, Mortal Strike, Shred, Claw…) count the full hit, using your current weapon damage
  - Abilities that empower your next swing (Heroic Strike, Maul, Cleave, Raptor Strike) count only the bonus damage, because the swing would have happened anyway
  - Finishers (Eviscerate, Rupture…) are rated at 5 combo points
- **Clear labels for special cases.** AoE abilities are marked *per target*, and effects with no fixed duration are marked *per tick*.
- **Doesn't guess.** Weapon imbues, Paladin seals, buffs that only change other damage or healing, and bonus damage from spare rage or energy are skipped, so you won't see misleading numbers.
- **Lightweight.** No configuration and no saved variables.

## Commands

- `/ret` opens or closes the spellbook report.
- `/ret debug` prints the parsed text of the last spell you hovered. This helps if you want to report a spell whose number looks wrong.

## Limitations

- **English clients only (enUS / enGB).** On other locales the addon turns itself off instead of showing wrong numbers.
- Values come from tooltip text. Talents, gear and buffs only count if the tooltip already includes them. The exception is weapon-based abilities, which use your current weapon damage and attack power.
- Mana, rage and energy share one list in the report, but a point of one isn't worth the same as a point of another. Compare within a resource for the fairest picture.
- Spell descriptions vary a lot. If a spell shows a strange number (or none), please open an issue and include the `/ret debug` output.
