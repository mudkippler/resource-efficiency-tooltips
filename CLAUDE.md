# Resource Efficiency Tooltips

A World of Warcraft **Forever** addon (`## Interface: 16001`) that appends damage / healing / absorb **per point of mana, rage or energy** to the cost line of spell tooltips, e.g. `15 Rage  (10.5 dmg/rage)`, and **damage per second** to the cast time line, e.g. `1.5 sec cast  (12.7 dps)`. `/ret config` toggles each part. It also has a `/ret report` spellbook report listing every spell and rank by efficiency. It's published on CurseForge by the author (tehraiden).

## Target client: WoW Forever only, no backwards compatibility

**This addon targets WoW Forever (`## Interface: 16001`) and its future builds only.** Older clients aren't supported and never will be: Classic Era, Season/Hardcore, Cataclysm/Mists Classic, retail, and earlier Forever builds. The user has said not to spend effort on backwards compatibility.

- Don't write fallbacks, shims or alternate code paths for older clients or APIs.
- Don't keep a legacy branch "just in case". If a branch is only there for an older client, remove it.
- A guard is only justified when it's genuinely unknown whether **Forever** has an API. Mark those guards as unconfirmed. Once in-game testing shows which API Forever has (e.g. `/dump C_SpellBook ~= nil`), drop the other branch.
- When a newer Forever build changes an API, update to the new one rather than supporting both.

## Repo layout and packaging rule

```
CLAUDE.md, DESCRIPTION.md, LICENSE, icon.png, *.zip   <- repo root: never shipped
ResourceEfficiencyTooltips/                   <- the addon: EXACTLY what gets zipped for CurseForge
    ResourceEfficiencyTooltips.toc
    ResourceEfficiencyTooltips.lua            <- parser, tooltip hook, slash commands, startup line
    Report.lua                                <- /ret report spellbook report window
    Config.lua                                <- /ret config settings window (two checkboxes)
    icon.tga                                  <- addon-list icon (64x64, 32-bit TGA with alpha)
```

- **Only shipped files go inside `ResourceEfficiencyTooltips/`.** Docs, tests, scripts, the CurseForge icon (`icon.png`) and release zips live in the repo root.
- **`DESCRIPTION.md`** is the CurseForge project description (Markdown, pasted in by hand). When features, commands or limitations change, update it too.
- **Release zips** are named `ResourceEfficiencyTooltips_<version>.zip` and contain the `ResourceEfficiencyTooltips/` folder. The user builds them.
- **Version** lives only in the `.toc` (`## Version:`). The startup chat line reads it via `GetAddOnMetadata`, so a bump is a one-line `.toc` change.
- **New `.lua` files** must be added to the `.toc` file list, after `ResourceEfficiencyTooltips.lua`, because `Report.lua` and `Config.lua` depend on what the main file puts on `ns`.
- **`## SavedVariables: ResourceEfficiencyTooltipsDB`** in the `.toc` holds the settings. Changing the `.toc` needs a full game restart, not `/reload`.
- **`IconTexture`** in the `.toc` points at `icon` with no extension; WoW resolves `icon.tga`. WoW textures need power-of-two sizes, and PNG isn't relied on.

## Environment

- Windows. WoW runs **Lua 5.1**, so there's no `goto`, integer division or `utf8` library.
- **Lua 5.1.5** (LuaBinaries) is installed in `C:\tools\lua51` and is on the user `PATH`. The executables are `lua5.1.exe` and `luac5.1.exe`; there's no `lua.exe`. A shell started before the install won't have it on `PATH`, so use the full path (`/c/tools/lua51/lua5.1.exe` in Git Bash) when `lua5.1` isn't found.
- Plain Lua 5.1 differs from WoW's in both directions. It has `io`, `os`, `require` and `loadfile`, which WoW removes, so don't use them in addon code. It lacks WoW's additions (`bit`, `strsplit`, `wipe`, `tinsert`, `hooksecurefunc` and the game API), so tests stub what they need.
- Files use **LF** line endings, 4-space indentation and UTF-8.
- Testing in game needs the user: a full game restart for `.toc` or new-file changes, `/reload` for Lua edits, and `/console scriptErrors 1` to see Lua errors.

## How it works (ResourceEfficiencyTooltips.lua)

The pipeline, top to bottom in the file:

1. **Hook.** `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, …)` if present, otherwise `GameTooltip:HookScript("OnTooltipSetSpell")`. It is unconfirmed which of the two Forever has. Macro buttons (`#showtooltip`) go through `GameTooltip:SetAction`, which neither hook is guaranteed to see, so a `hooksecurefunc` on `SetAction` also calls `Process` when `GetMacroAction` says the slot holds a macro. The spell ID comes from `GetActionInfo`'s `"spell"` subtype or from `GetMacroSpell`. Processing a tooltip twice is safe, because `IsAnnotated` stops the second pass. Only tooltips named in `TOOLTIPS` (GameTooltip, ItemRefTooltip) are annotated. Other addons' hidden scanning tooltips must never be modified.
2. **`ReadSpellTooltip(tooltip)`** walks `<Name>TextLeftN`. Within the first 5 lines it finds the cost line with `MatchCost`, the cast line with `MatchCast` ("1.5 sec cast", "instant", "channeled", "next melee"; anchored so "instantly…" doesn't match) and the cooldown with `MatchCooldown`, usually on `TextRightN` (mana, rage or energy from `RESOURCES`, built from the client's `MANA_COST`/`RAGE_COST`/`ENERGY_COST` globals). Every other line is `Normalize`d (colour codes and links stripped, thousands separators removed, lowercased). It stops at "Next rank", and bails if `IsAnnotated` finds our suffix already there.
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
6. **`ComputeDPS`** is damage ÷ max(cast time, GCD). The GCD is 1 sec for energy and 1.5 sec otherwise. It returns nil when there's a cooldown (tooltip text, or `GetSpellBaseCooldown` as a backstop in `Process`), for next-swing abilities and for finishers. Normal casts add `direct` ÷ time per cast to each entry in `dots` at total ÷ max(its duration, time per cast). Recasting refreshes a DoT rather than stacking it, so Flamestrike (120 on impact, 3 sec cast, 80 over 8 sec) is 120/3 + 80/8 = 50. A DoT with no duration (`dotUnknown`) means no DPS. Charges count towards neither. Channels use the full total over `duration`.
7. **`GetSuffix` / `GetDPSSuffix`** build the coloured suffixes and cache them through `Cached` in a 200-entry FIFO, keyed on cost or cast info, resource, name, combat stats and lines. Action-button tooltips refresh several times a second, so the cache matters. `Process` applies each suffix only if its `ns.db` setting is on.

`Analyze` returns a table (`totals`, `perTick`, `aoe`, `direct`, `directAoe`, `dots`, `dotUnknown`, `absorbDrain`, `comboPoints`, `duration`). `TickMultiplier` also returns each over-time clause's duration.

**Settings** live in `ns.db`: the defaults until `ADDON_LOADED`, then the saved variable `ResourceEfficiencyTooltipsDB` (`efficiency`, `dps`, both default true). `Config.lua` is a small movable window with one checkbox per setting, opened by `ns.ToggleConfig()`. Changes apply the next time a tooltip is shown.

**Slash commands** are at the bottom of the main file. A bare `/ret` prints the help (`PrintHelp`) and opens the settings window. `/ret report` toggles the report, `/ret config` the settings, and `/ret debug` prints the last spell's parsed cast info and lines. Any other argument opens the settings window.

`Report.lua` reuses the same code via `ns`: `ns.ReadSpellTooltip`, `ns.ComputeRatios`, `ns.GetCostFromAPI`, `ns.Normalize`, `ns.FormatRatio`, `ns.ORDER/LABELS/COLORS/RESOURCES` and `ns.supported`. It scans spells with its own hidden tooltip, `ResourceEfficiencyTooltipsScanner`, which the hook ignores because it isn't in `TOOLTIPS`. It enumerates the spellbook with `C_SpellBook` if present, otherwise the `GetNumSpellTabs`/`GetSpellBookItemInfo` APIs. Both paths exist only because it's unconfirmed which one Forever has, not to support older clients. Once that's known, delete the unused one.

## Design decisions (agreed with the user; keep them consistent)

- **Amounts come from tooltip text**, so every rank gives its own number. The only live stats used are weapon damage and attack power, through `GetCombatStats` (`UnitDamage`, `UnitRangedDamage`, `UnitAttackPower`, wrapped in pcall).
- **Instant weapon strikes count the whole hit:** current average weapon damage × percent, plus the flat bonus. Examples: Sinister Strike, Backstab, Mortal Strike, Shred, Claw ("110% normal damage plus 115"), Aimed Shot ("increases *ranged* damage by N") and Bloodthirst (% of attack power).
- **Next-swing abilities count only their bonus**, because the auto attack would have landed anyway. Detected by wording ("increases *melee* damage by N" for Heroic Strike and Raptor Strike, "next attack by N" for Maul) or by name in `NEXT_SWING_SPELLS` for ones that read like instant strikes (Cleave).
- **Finishers are rated at max combo points** and labelled "at 5 CP" in tooltips, "5cp" in the report.
- **Conversions are ignored** (`CONVERSION_PATTERNS`): Mana Burn's per-mana damage and Execute's per-extra-rage damage.
- **"Stacks up to N times" is not charges.** This was the Arcane Blast bug.
- **DPS only for spells cast back to back:** no cooldown, not next-swing, not a finisher. Instants use the GCD. Damage over time counts at its sustained rate while spamming (total ÷ max(duration, time per cast)), because recasting refreshes it rather than stacking it. Channels count everything over the channel. AoE is per target. DPS doesn't model resource limits or auto attacks.
- **Per-tick / per-target labels** appear when a duration can't be found, or the effect hits several targets.
- **English only.** `SUPPORTED_LOCALES` is enUS and enGB. Other locales leave tooltips untouched rather than show wrong numbers, and the report refuses to open.
- **Don't guess.** When something can't be calculated honestly, show nothing rather than a misleading number.
- Name-keyed special cases (`SHOT_INTERVALS`, `NEXT_SWING_SPELLS`) use lowercase spell names and are the escape hatch when wording alone is ambiguous.

## Adding support for a new tooltip wording

1. Get the exact text from the user: hover the spell in game and run `/ret debug`. It prints the parsed cast info (kind, seconds, cooldown) and the normalized lines `Analyze` sees.
2. Prefer a general wording rule (a pattern in `WeaponAmount`, `ClauseKind`, `UNIT_WORDS`, `AOE_PATTERNS` or `CONVERSION_PATTERNS`) over a name-keyed special case.
3. Add it as a case to the harness below, and re-run every case to check for regressions.
4. Update the comments listing examples above the function you changed, since those comments are the catalogue of supported wordings.

## Testing outside the game

There's no committed test suite. Write the harness as a `.lua` file in the session scratchpad, not the repo, and run it from the repo root with the installed interpreter.

**Syntax check** every shipped file after an edit:

```sh
for f in ResourceEfficiencyTooltips/*.lua; do luac5.1 -p "$f" && echo "ok $f"; done
```

**Parser tests** stub the WoW globals the main file touches at load time, load it with `assert(loadfile("ResourceEfficiencyTooltips/ResourceEfficiencyTooltips.lua"))("ResourceEfficiencyTooltips", ns)`, and call `ns.ComputeRatios({ ns.Normalize(text) }, cost, ns.Normalize(name))` or `ns.ComputeDPS`. Run it with `lua5.1 <scratchpad>/test.lua`:

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

To test cost and cast line detection, fake a tooltip with `GetName`/`NumLines` and set `_G["FakeTipTextLeftN"]` (with `GetText`) and `_G["FakeTipTextRightN"]` (with `GetText` and `IsShown`, for cooldowns). To test the macro hook, also define `hooksecurefunc` (capture the function), `GameTooltip.SetAction`, `GetActionInfo` and `GetMacroSpell` before loading. `Report.lua` and `Config.lua` need a real client, so only syntax-check them.

If the native interpreter isn't available, the same Lua runs under Python's `lupa` (`python -m pip install --quiet --target <scratchpad>/pylibs lupa`, then `from lupa import lua51`).

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

DPS cases (`ns.ComputeDPS(lines, { kind, seconds, cooldown }, name, nil, resource)`):

| Spell | Cast | Expected | Covers |
|---|---|---|---|
| Frostbolt (18 to 20) | 1.5 sec | 12.67 | basic |
| Fireball (16 to 25 + 2 over 4 sec) | 1.5 sec | 20.5/1.5 + 2/4 = 14.17 | DoT at its own rate |
| Flamestrike (120 + 80 over 8 sec, all enemies) | 3 sec | 50 per target | DoT refreshed by recasting |
| 10 + 6 over 2 sec | 3 sec | 16/3 | DoT shorter than the cast lands in full |
| Corruption (40 over 12 sec) | instant | 3.33 | DoT only |
| Searing Totem (9 to 11, repeatedly, 30 sec) | instant | 130/30 | summon as DoT |
| 5 every 3 sec, no duration | 2 sec | nothing | `dotUnknown` |
| Smite (15 to 20) | 1.0 sec | 11.67 | GCD floor |
| Arcane Explosion (32 to 36, all enemies) | instant, mana | 22.67 per target | instant uses 1.5 GCD |
| Sinister Strike | instant, energy | 103 | 1 sec energy GCD |
| Arcane Missiles (24 each second for 3 sec) | channeled | 24 | channel |
| Blizzard (200 over 8 sec) | channeled | 25 per target | channel AoE |
| Lightning Shield | instant | nothing | charges |
| Mortal Strike (6 sec cooldown), Heroic Strike (next melee), Eviscerate | — | nothing | not repeatable |

## Known gaps

- Multi-Shot style wording ("hitting 3 targets for an additional N damage") isn't handled.
- Whirlwind and other dual-wield strikes only use main-hand damage.
- The Classic finisher table format and some tooltip texts above were written from memory. Real in-game text may differ, so confirm with `/ret debug` output.
- Whether lower ranks appear in the report depends on the client's spellbook "show all ranks" behaviour.
- The report doesn't show DPS. Free spells only get DPS if their tooltip has a cast line, and percentage costs without the API only lose the efficiency part.
- The exact Forever cast and cooldown line wording ("Instant", "Channeled", "N sec cooldown") is assumed from Classic. Check `/ret debug`, which prints the parsed cast info.
- Mana, rage and energy share one sorted list in the report even though their points aren't comparable. This is accepted and documented in `DESCRIPTION.md`.
- Macros whose `#showtooltip` shows an item, or no spell, get no numbers.
- Spell power coefficients aren't shown. The client has no API for them and tooltips don't include them. The options discussed were a hard-coded table per spell (with a level penalty for low ranks), the Classic cast-time ÷ 3.5 rules marked as an estimate, or both. It's undecided: first find out whether Forever has +spell damage gear, and whether tooltip numbers already include spell power.

## Conventions

- Match the existing style: file-level section banners (`-----` / `-- Section`), a comment above each function giving its purpose and return values, and lowercase example wordings in comments.
- Write for Forever's current API only (see "Target client"). Guard an API only when it's unconfirmed whether Forever has it, and never add a branch for an older client.
- Treat tooltip text as possibly secret (`issecretvalue`), as `ReadSpellTooltip` and `Process` do.
- Chat messages start with the coloured addon name (`|cff80c8ffResource Efficiency Tooltips|r`).
- Slash commands: `/ret` (help + settings), `/ret report`, `/ret config`, `/ret debug`, `/ret help`. A new command must also be added to the `help` output and to `DESCRIPTION.md`.
