# Resource Efficiency Tooltips

A World of Warcraft **Forever** addon (`## Interface: 16001`) that appends damage / healing / absorb **per point of mana, rage or energy** to the cost line of spell tooltips, e.g. `15 Rage  (10.5 dmg/rage)`. It also has a `/ret` spellbook report listing every spell and rank by efficiency. It's published on CurseForge by the author (mudkippler).

## Repo layout and packaging rule

```
CLAUDE.md, DESCRIPTION.md, icon.png, *.zip    <- repo root: never shipped
ResourceEfficiencyTooltips/                   <- the addon: EXACTLY what gets zipped for CurseForge
    ResourceEfficiencyTooltips.toc
    ResourceEfficiencyTooltips.lua            <- parser, tooltip hook, slash commands, startup line
    Report.lua                                <- /ret spellbook report window
    icon.tga                                  <- addon-list icon (64x64, 32-bit TGA with alpha)
```

- **Only shipped files go inside `ResourceEfficiencyTooltips/`.** Docs, tests, scripts, the CurseForge icon (`icon.png`) and release zips live in the repo root.
- **`DESCRIPTION.md`** is the CurseForge project description (Markdown, pasted in by hand). When features, commands or limitations change, update it too.
- **Release zips** are named `ResourceEfficiencyTooltips_<version>.zip` and contain the `ResourceEfficiencyTooltips/` folder. The user builds them.
- **Version** lives only in the `.toc` (`## Version:`). The startup chat line reads it via `GetAddOnMetadata`, so a bump is a one-line `.toc` change.
- **New `.lua` files** must be added to the `.toc` file list, after `ResourceEfficiencyTooltips.lua`, because `Report.lua` depends on what the main file exports on `ns`.
- **`IconTexture`** in the `.toc` points at `icon` with no extension; WoW resolves `icon.tga`. WoW textures need power-of-two sizes, and PNG isn't relied on.

## Environment

- Windows, no system Lua installed. WoW runs **Lua 5.1**, so there's no `goto`, integer division or `utf8` library.
- Files use **LF** line endings, 4-space indentation and UTF-8.
- Testing in game needs the user: a full game restart for `.toc` or new-file changes, `/reload` for Lua edits, and `/console scriptErrors 1` to see Lua errors.

## How it works (ResourceEfficiencyTooltips.lua)

The pipeline, top to bottom in the file:

1. **Hook.** `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, …)` on modern clients, falling back to `GameTooltip:HookScript("OnTooltipSetSpell")`. Only tooltips named in `TOOLTIPS` (GameTooltip, ItemRefTooltip) are annotated. Other addons' hidden scanning tooltips must never be modified.
2. **`ReadSpellTooltip(tooltip)`** walks `<Name>TextLeftN`. Within the first 5 lines it finds the cost line with `MatchCost` (mana, rage or energy from `RESOURCES`, built from the client's `MANA_COST`/`RAGE_COST`/`ENERGY_COST` globals). Every other line is `Normalize`d (colour codes and links stripped, thousands separators removed, lowercased). It stops at "Next rank", and bails if `IsAnnotated` finds our suffix already there.
3. **Cost.** A percentage cost ("12% of base mana") falls back to `GetCostFromAPI` (`C_Spell.GetSpellPowerCost` or `GetSpellPowerCost`).
4. **`Analyze(lines, spellName, stats)`** is the heart of the parser. It returns per-kind totals plus flags:
   - Splits multi-line descriptions on `\n`, then `KeepMaxComboPoints` keeps only the highest "N points:" line of a finisher table.
   - Bails entirely on weapon imbues, Paladin seals and "each melee attack" effects (they scale with swings, not casts).
   - `lasts` (from "lasts N sec") and `ParseCharges` (charges or "N times", excluding "stacks up to N times") apply to the whole spell.
   - Text splits into sentences (`. `) and then clauses (` and `, `;`). Each clause is either:
     - a **weapon strike** (`WeaponAmount`, checked first), or
     - classified by `ClauseKind`: `false` means not throughput and resets the inherited kind; `nil` means inherit the previous clause's kind. Then `FindAmount` takes the first real number (skipping `UNIT_WORDS` like yards, sec, %, combo points, and "by N" modifiers; averaging "X to Y" and "X-Y"), and `TickMultiplier` turns per-tick amounts into totals.
   - A sentence matching `AOE_PATTERNS` marks its amounts as *per target*.
5. **`ComputeRatios`** gives total ÷ cost per kind. For absorbs, `ParseAbsorbDrain` adds Mana Shield's drain to the cost.
6. **`GetSuffix`** builds the coloured suffix and caches it in a 200-entry FIFO, keyed on cost, resource, name, combat stats and lines. Action-button tooltips refresh several times a second, so the cache matters.

`Report.lua` reuses the same code via `ns`: `ns.ReadSpellTooltip`, `ns.ComputeRatios`, `ns.GetCostFromAPI`, `ns.Normalize`, `ns.FormatRatio`, `ns.ORDER/LABELS/COLORS/RESOURCES` and `ns.supported`. It scans spells with its own hidden tooltip, `ResourceEfficiencyTooltipsScanner`, which the hook ignores because it isn't in `TOOLTIPS`. It enumerates the spellbook with `C_SpellBook` when available, otherwise the legacy `GetNumSpellTabs`/`GetSpellBookItemInfo` APIs. Both paths are guarded, because it isn't known which one this client has.

## Design decisions (agreed with the user; keep them consistent)

- **Amounts come from tooltip text**, so every rank gives its own number. The only live stats used are weapon damage and attack power, through `GetCombatStats` (`UnitDamage`, `UnitRangedDamage`, `UnitAttackPower`, wrapped in pcall).
- **Instant weapon strikes count the whole hit:** current average weapon damage × percent, plus the flat bonus. Examples: Sinister Strike, Backstab, Mortal Strike, Shred, Claw ("110% normal damage plus 115"), Aimed Shot ("increases *ranged* damage by N") and Bloodthirst (% of attack power).
- **Next-swing abilities count only their bonus**, because the auto attack would have landed anyway. Detected by wording ("increases *melee* damage by N" for Heroic Strike and Raptor Strike, "next attack by N" for Maul) or by name in `NEXT_SWING_SPELLS` for ones that read like instant strikes (Cleave).
- **Finishers are rated at max combo points** and labelled "at 5 CP" in tooltips, "5cp" in the report.
- **Conversions are ignored** (`CONVERSION_PATTERNS`): Mana Burn's per-mana damage and Execute's per-extra-rage damage.
- **"Stacks up to N times" is not charges.** This was the Arcane Blast bug.
- **Per-tick / per-target labels** appear when a duration can't be found, or the effect hits several targets.
- **English only.** `SUPPORTED_LOCALES` is enUS and enGB. Other locales leave tooltips untouched rather than show wrong numbers, and the report refuses to open.
- **Don't guess.** When something can't be calculated honestly, show nothing rather than a misleading number.
- Name-keyed special cases (`SHOT_INTERVALS`, `NEXT_SWING_SPELLS`) use lowercase spell names and are the escape hatch when wording alone is ambiguous.

## Adding support for a new tooltip wording

1. Get the exact text from the user: hover the spell in game and run `/ret debug`, which prints the normalized lines `Analyze` sees.
2. Prefer a general wording rule (a pattern in `WeaponAmount`, `ClauseKind`, `UNIT_WORDS`, `AOE_PATTERNS` or `CONVERSION_PATTERNS`) over a name-keyed special case.
3. Add it as a case to the harness below, and re-run every case to check for regressions.
4. Update the comments listing examples above the function you changed, since those comments are the catalogue of supported wordings.

## Testing outside the game

There's no committed test suite. Run the parser under real Lua 5.1 through Python's `lupa`, installed into the session scratchpad rather than the repo:

```sh
python -m pip install --quiet --target <scratchpad>/pylibs lupa
```

The harness stubs the WoW globals the main file touches at load time, loads it with `loadstring(src)('ResourceEfficiencyTooltips', ns)`, and calls `ns.ComputeRatios({ ns.Normalize(text) }, cost, ns.Normalize(name))`:

```lua
MANA, RAGE, ENERGY = "Mana", "Rage", "Energy"
MANA_COST, RAGE_COST, ENERGY_COST = "%d Mana", "%d Rage", "%d Energy"
function GetLocale() return "enUS" end
GameTooltip = { HookScript = function() end }
SlashCmdList = {}
function CreateFrame() return { RegisterEvent = function() end, SetScript = function() end } end
function UnitDamage() return 90, 110 end            -- melee average 100
function UnitRangedDamage() return 3, 80, 120 end    -- ranged average 100
function UnitAttackPower() return 1000, 0, 0 end
```

Use `from lupa import lua51` so it matches WoW's Lua. To test cost-line detection, fake a tooltip with `GetName`/`NumLines` and set the `_G["FakeTipTextLeftN"]` objects to have a `GetText` method. Syntax-check `Report.lua` with `loadstring`; it needs a real client to run.

Regression cases that passed (cost → expected damage per point, with 100 average weapon damage and 1000 attack power):

| Spell | Cost | Expected | Covers |
|---|---|---|---|
| Arcane Blast (364 to 424) | 195 mana | 394/195 | stack limit isn't charges |
| Frostbolt (18 to 20) | 25 mana | 0.76 | basic range |
| Heroic Strike ("increases melee damage by 157") | 15 rage | 157/15 | next swing, bonus only |
| Raptor Strike ("increases melee damage by 5") | 15 | 5/15 | next swing |
| Maul ("next attack by 18 damage") | 15 rage | 18/15 | next swing |
| Cleave ("weapon damage plus 5 … nearest ally") | 20 rage | 5/20, per target | `NEXT_SWING_SPELLS` |
| Aimed Shot ("increases ranged damage by 70") | 75 | 170/75 | ranged strike |
| Mortal Strike ("weapon damage plus 85") | 30 rage | 185/30 | instant strike |
| Execute ("125 damage … each extra point of rage into 3") | 15 rage | 125/15 | conversion ignored |
| Whirlwind ("weapon damage to each enemy") | 25 rage | 100/25, per target | AoE weapon |
| Bloodthirst ("45% of your attack power") | 30 rage | 450/30 | attack power |
| Rend ("15 damage over 9 sec") | 10 rage | 1.5 | damage over time |
| Sinister Strike ("3 damage in addition to your normal weapon damage") | 45 energy | 103/45 | instant strike |
| Backstab ("150% weapon damage plus 15") | 60 energy | 165/60 | percent strike |
| Shred ("225% damage plus 54") | 60 energy | 279/60 | percent strike |
| Claw ("110% normal damage plus 115") / old ("27 additional damage") | 45 energy | 225/45 / 127/45 | both wordings |
| Rake ("19 damage and an additional 39 damage over 9 sec") | 40 energy | 58/40 | not a weapon strike |
| Eviscerate (5 points: 30-34) | 35 energy | 32/35, 5 CP | finisher table |
| Rupture (5 points: 136 damage over 16 secs) | 25 energy | 136/25, 5 CP | finisher damage over time |
| Kidney Shot, Mana Burn | — | nothing | no false positives |

## Known gaps

- Multi-Shot style wording ("hitting 3 targets for an additional N damage") isn't handled.
- Whirlwind and other dual-wield strikes only use main-hand damage.
- The Classic finisher table format and some tooltip texts above were written from memory. Real in-game text may differ, so confirm with `/ret debug` output.
- Whether lower ranks appear in the report depends on the client's spellbook "show all ranks" behaviour.
- Mana, rage and energy share one sorted list in the report even though their points aren't comparable. This is accepted and documented in `DESCRIPTION.md`.

## Conventions

- Match the existing style: file-level section banners (`-----` / `-- Section`), a comment above each function giving its purpose and return values, and lowercase example wordings in comments.
- Guard every client API that may not exist on this client (`C_Spell`, `C_SpellBook`, `C_AddOns`, `TooltipDataProcessor`, `Enum.*`), falling back to the legacy global.
- Treat tooltip text as possibly secret (`issecretvalue`), as `ReadSpellTooltip` and `Process` do.
- Chat messages start with the coloured addon name (`|cff80c8ffResource Efficiency Tooltips|r`).
- Slash commands: `/ret` (report), `/ret debug`, `/ret help`. A new command must also be added to the `help` output and to `DESCRIPTION.md`.
