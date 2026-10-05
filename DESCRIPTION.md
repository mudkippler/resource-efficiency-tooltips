# Resource Efficiency Tooltips

**How much does each point of mana, rage or energy actually get you?** This addon adds the answer to the cost line of spell and ability tooltips, as well the damage per second to the cast time line. You can compare ranks and abilities at a glance without doing the math yourself.

![image](https://media.forgecdn.net/attachments/description/1723554/description_554b66e5-35dd-4643-8756-fd4722196c50.png)

## Features

**Damage/Healing per Mana/Energy/Rage**: Self explanatory.

**Damage per second** for spells you can cast back to back: average damage divided by the cast time. Instant spells use the global cooldown (1 sec for energy abilities, 1.5 sec otherwise), and casts faster than the global cooldown are rounded up to it. It's only shown for spells without a cooldown, and not for finishers or next-swing abilities like Heroic Strike. Damage over time counts at the rate it keeps ticking while you recast the spell. Recasting refreshes it rather than stacking it, so Flamestrike with 120 damage on impact, a 3 sec cast and 80 damage over 8 sec is 120 / 3 + 80 / 8 = 50 DPS. Channeled spells (Arcane Missiles, Blizzard) count their full damage over the channel. AoE spells show DPS _per target_.

**Choose what you see.** Type `/ret config` to turn the efficiency or the DPS part of the tooltip on or off.

**Always matches the rank you're looking at.** Numbers come from the tooltip's own text, so every rank gives its own figure.

**Spellbook report.** Type `/ret report` to open a window listing every spell and rank in your spellbook that has a calculable efficiency, best first. Click a column header to sort by damage, healing or absorb, and hover a row to see the spell's tooltip.

![image](https://media.forgecdn.net/attachments/description/1723554/description_f20ad2b8-8265-4cc2-8b39-3a0b72df08f4.png)

**Understands how abilities actually work:** Damage-over-time and heal-over-time effects are added up over their full duration

Damage with variance like `31 to 45` uses the average

Spells with charges (e.g. Lightning Shield) count every charge

Summons that attack repeatedly (e.g. Searing Totem) count their damage over their lifetime

Mana Shield includes the mana it drains while absorbing

Instant weapon strikes (Sinister Strike, Mortal Strike, Shred, Claw…) count the full hit, using your current weapon damage

Abilities that empower your next swing (Heroic Strike, Maul, Cleave, Raptor Strike) count only the bonus damage, because the swing would have happened anyway

Finishers (Eviscerate, Rip, Rupture…) are rated at 5 combo points.

**Clear labels for special cases.** AoE abilities are marked _per target_, and effects with no fixed duration are marked _per tick_.

**Doesn't guess.** Weapon imbues, Paladin seals, buffs that only change other damage or healing, and bonus damage from spare rage or energy are skipped, so you won't see misleading numbers.

**Lightweight.** Two settings, saved per account, and nothing else.

## Commands

`/ret` opens the settings window and lists the commands.

`/ret report` opens or closes the spellbook report.

`/ret config` opens the settings window, where you can turn the efficiency and DPS parts of the tooltip on or off.

![image](https://media.forgecdn.net/attachments/description/1723554/description_3fdb5a7c-ca7d-4967-9a44-1a7ce9f478f1.png)

`/ret debug` prints the parsed text of the last spell you hovered. This helps if you want to report a spell whose number looks wrong.

`/ret help` lists the commands.

## Limitations

**English clients only (enUS / enGB).** On other locales the addon turns itself off instead of showing wrong numbers.

Values come from tooltip text. Talents, gear and buffs only count if the tooltip already includes them. The exception is weapon-based abilities, which use your current weapon damage and attack power.

DPS is the damage of casting a spell back to back. It doesn't account for running out of mana, rage or energy, or for your auto attacks.

Mana, rage and energy share one list in the report, but a point of one isn't worth the same as a point of another. Compare within a resource for the fairest picture.

Spell descriptions vary a lot. If a spell shows a strange number (or none), please open an issue and include the `/ret debug` output.