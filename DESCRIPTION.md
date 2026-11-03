# Resource Efficiency Tooltips

**How much does each point of mana, rage or energy get you?** This addon adds the answer to spell tooltips, along with damage per second and the spell's coefficient, so you can compare ranks and abilities at a glance.

![image](https://media.forgecdn.net/attachments/description/1723554/description_2372a8be-570a-4826-b9c6-2fe309772349.png)

![image](https://media.forgecdn.net/attachments/description/1723554/description_82f3945a-e27d-4b1b-babc-f6903477523c.png)

![image](https://media.forgecdn.net/attachments/description/1723554/description_f3065553-a083-4621-9c39-5e1fbb72076e.png)

## Features

**Damage, healing or absorb per point** of mana, rage or energy, on the cost line.

**Damage per second** on the cast time line, for spells you can cast back to back (no cooldown, not a finisher or next-swing ability).
- Instants and fast casts use the global cooldown (1 sec for energy, 1.5 sec otherwise).
- Spells doing more than 45% of their damage over time show the DoT's damage over the cast time plus its duration. Immolate (11 on impact, 2 sec cast, 20 over 15 sec) is 20 / 17 = 1.2.
- Other DoTs count at the rate they tick while you recast, since recasting refreshes them. Flamestrike (120 on impact, 3 sec cast, 80 over 8 sec) is 120 / 3 + 80 / 8 = 50.
- Channels count their full damage over the channel.

**Spell coefficients**, the share of spell power a spell gains, on a line at the bottom, e.g. `Coefficient: 81.4%`. Spells with several parts list each one, e.g. Pyroblast's `100% Direct / 15% DoT`. Channels like Arcane Missiles show the value per missile or tick.

**Stat-scaled values filled in**, e.g. Arcane Wrath's "5% (612) of your maximum Mana" and Arcane Blast's "15% (45) of your Intellect". These aren't added to the efficiency or DPS numbers.

**Hold Shift for the details.** When a number's calculation isn't obvious, a small Shift key appears next to it. Hold Shift to see how it was worked out.

**In combat**, the game hides some values, such as weapon damage, attack power and stats. Numbers that need them show crossed swords (⚔) until combat ends.

**Spellbook report.** `/ret report` lists every spell and rank by efficiency, best first. Click a column to sort, and hover a row for the tooltip.

![image](https://media.forgecdn.net/attachments/description/1723554/description_f20ad2b8-8265-4cc2-8b39-3a0b72df08f4.png)

**Also:** works on `#showtooltip` macros, matches the rank you're looking at, and lets you turn each part on or off, or show it only while Shift is held (`/ret config`).

## How abilities are counted

- Damage and healing over time count over their full duration, and ranges like `31 to 45` use the average.
- Charges (Lightning Shield) count every charge, and repeating summons (Searing Totem) count their lifetime.
- Mana Shield includes the mana it drains.
- Instant weapon strikes (Sinister Strike, Mortal Strike, Shred, Claw, Bloodthirst) use your current weapon damage or attack power.
- Next-swing abilities (Heroic Strike, Cleave, Maul, Raptor Strike) count only their bonus, since the swing would happen anyway. Rage ones also count the rage that swing no longer gives: weapon speed × 3.46 (one-handed) or × 4.50 (two-handed) for Warriors, and 11 for Bear Form.
- Finishers are rated at 5 combo points.
- AoE is marked _per target_. Effects with no fixed duration are marked _per tick_.

## Commands

- `/ret` opens the settings and lists the commands.
- `/ret config` opens the settings.
- `/ret report` toggles the spellbook report.
- `/ret debug` prints how the last spell you hovered was read. Include it when reporting a wrong number.
- `/ret help` lists the commands.

![image](https://media.forgecdn.net/attachments/description/1723554/description_7dfc5877-00bd-484f-9175-77765af08e30.png)

## Limitations

- English clients only (enUS / enGB). Other locales turn the addon off rather than show wrong numbers.
- Numbers come from tooltip text, so talents, gear and buffs only count if the tooltip includes them.
- Rather than guess, the addon shows nothing for weapon imbues, Paladin seals and buffs that only change other damage or healing, and ignores bonus damage from spare rage or energy (Execute).
- Coefficients come from a built-in table of the game's spell data. Weapon damage isn't shown, since it doesn't scale with spell power.
- DPS ignores running out of resources and your auto attacks.
- The report mixes mana, rage and energy, which aren't worth the same per point. Compare within one resource.
- Spell descriptions vary a lot. If a number looks wrong or is missing, please open an issue with the `/ret debug` output.
