# Resource Efficiency Tooltips

A World of Warcraft **Forever** addon (`## Interface: 16001`) that appends damage / healing / absorb **per point of mana, rage or energy** to the cost line of spell tooltips, e.g. `15 Rage  (10.5 dmg/rage)`, **damage per second** to the cast time line, e.g. `1.5 sec cast  (12.7 dps)`, and a **spell coefficient** line at the bottom, e.g. `Coefficient: 42.9% Direct / 0% DoT`. `/ret config` toggles each part. It also has a `/ret report` spellbook report listing every spell and rank by efficiency. It's published on CurseForge by the author (tehraiden).

## Target client: WoW Forever only, no backwards compatibility

**This addon targets WoW Forever (`## Interface: 16001`) and its future builds only.** Older clients aren't supported and never will be: Classic Era, Season/Hardcore, Cataclysm/Mists Classic, retail, and earlier Forever builds. The user has said not to spend effort on backwards compatibility.

- Don't write fallbacks, shims or alternate code paths for older clients or APIs.
- Don't keep a legacy branch "just in case". If a branch is only there for an older client, remove it.
- A guard is only justified when it's genuinely unknown whether **Forever** has an API. Mark those guards as unconfirmed. Once in-game testing shows which API Forever has (e.g. `/dump C_SpellBook ~= nil`), drop the other branch.
- When a newer Forever build changes an API, update to the new one rather than supporting both.

## Repo layout and packaging rule

```
CLAUDE.md, DESCRIPTION.md, LICENSE, icon.png, *.zip   <- repo root: never shipped
scripts/                                      <- dev scripts (never shipped)
    Install-Addon.ps1                         <- copies the addon into the Forever beta client
    generate_spell_coefficients.py            <- regenerates SpellCoefficients.lua from the database
    Generate-ShiftKey.ps1                     <- renders shift.tga with ImageMagick
data/<date>/                                  <- spell database snapshot (spelldb.db, CSVs) and its SQL
tests/                                        <- regression suite: lua5.1 tests/run.lua (never shipped)
ResourceEfficiencyTooltips/                   <- the addon: EXACTLY what gets zipped for CurseForge
    ResourceEfficiencyTooltips.toc
    ResourceEfficiencyTooltips.lua            <- parser, tooltip hook, slash commands, startup line
    SpellCoefficients.lua                     <- ns.SPELL_COEFFICIENTS (generated; don't edit by hand)
    Report.lua                                <- /ret report spellbook report window
    Config.lua                                <- /ret config settings window (checkboxes)
    icon.tga                                  <- addon-list icon (64x64, 32-bit TGA with alpha)
    shift.tga                                 <- Shift keycap for the notes (128x64; made by scripts/Generate-ShiftKey.ps1)
```

- **Only shipped files go inside `ResourceEfficiencyTooltips/`.** Docs, tests, scripts, the CurseForge icon (`icon.png`) and release zips live in the repo root.
- **`DESCRIPTION.md`** is the CurseForge project description (Markdown, pasted in by hand). When features, commands or limitations change, update it too.
- **Release zips** are named `ResourceEfficiencyTooltips_<version>.zip` and contain the `ResourceEfficiencyTooltips/` folder. The user builds them.
- **Version** lives only in the `.toc` (`## Version:`). The startup chat line reads it via `GetAddOnMetadata`, so a bump is a one-line `.toc` change.
- **New `.lua` files** must be added to the `.toc` file list, after `ResourceEfficiencyTooltips.lua`, because `Report.lua` and `Config.lua` depend on what the main file puts on `ns`. `SpellCoefficients.lua` comes straight after the main file.
- **`## SavedVariables: ResourceEfficiencyTooltipsDB`** in the `.toc` holds the settings. Changing the `.toc` needs a full game restart, not `/reload`.
- **Installing for testing:** `powershell -ExecutionPolicy Bypass -File scripts\Install-Addon.ps1` replaces `Interface\AddOns\ResourceEfficiencyTooltips` in the Forever beta client (`C:\Program Files (x86)\World of Warcraft\_classic_beta_`, build 1.60.1.70450; `-GameDir` for another client) with an exact copy of the addon folder. `_beta_` is a different client. The game copy is a plain copy, not a link, so re-run the script after every change.
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
8. **Coefficient line.** After the suffixes, `Process` adds `Coefficient: …` (`COEFFICIENT_PREFIX`, colon included so a description that uses the word isn't matched) as the tooltip's last line via `AddLine`. It runs even when the tooltip has no cost or cast line. The text comes from `FormatCoefficients(spellID)`: one shown part is just `%g%%` (`81.4%`). Several shown parts are each labelled from `COEFFICIENT_KINDS` (`Direct` for damage and heal, `DoT`, `HoT`), sorted direct before periodic with effect order breaking ties, and joined with ` / `. So Immolate's data, DoT first, still reads `20% Direct / 13% DoT`. Parts whose kind has no entry (`weapon`, or anything new) are skipped, and so is the whole line if nothing is left, or there's no spell ID. `HasCoefficientLine` and `IsAnnotated` (which also matches the label) stop a second pass from adding it twice. In Shift-only mode, `Process` remembers GameTooltip in `shiftTooltip` (cleared by `OnTooltipCleared`). `MODIFIER_STATE_CHANGED` for LSHIFT/RSHIFT then calls `RefreshForShift`, which redraws the tooltip through its owner's `UpdateTooltip` or `OnEnter`. `Shown(part, tooltip)` treats every Shift-only part as shown on ItemRefTooltip, because a chat link isn't redrawn when Shift changes and Shift-clicking a link usually puts it in chat.
9. **Notes.** `ComputeRatios` (as `ratios.notes`) and `ComputeDPS` (`notes`) return sentences explaining calculations that aren't obvious: next-swing bonus only, Warrior forgone rage, the weapon damage or attack power used, Mana Shield's drain, ignored conversions, and DoTs in DPS. They're cached with their suffix and only shown when that suffix is shown. The notes go above the coefficient line. In Shift-only mode (`notesShiftOnly`, the default), GameTooltip shows a `<kbd>`-style Shift keycap (`SHIFT_KEY`, a `|T…shift:16:32|t` escape for `shift.tga`) until Shift is held. It goes right after the DPS suffix, outside the brackets, or after the efficiency suffix when there's no DPS (Heroic Strike), and it replaces a separate hint line. Notes only exist when a suffix was added, so there's always a line for the key. ItemRefTooltip always shows the notes (see `Shown`). The note lines aren't matched by `IsAnnotated`; a second pass bails on the suffix above them instead. To add a note for another special case, add a flag to `Analyze`'s result and a sentence in `ComputeRatios` or `ComputeDPS`.
10. **Stat values.** Last, `AddStatValues` inserts what a stat-scaled percentage is worth right now into the description, after the percentage. Arcane Wrath reads "equal to 5% (612) of your maximum Mana" (`UnitPowerMax`) and Arcane Blast "15% (45) of your Intellect" (effective `UnitStat` 4). The wordings are in `STAT_SCALINGS`, a general rule that isn't keyed by spell name, so add new stat wordings there. The value has its own colour (`STAT_VALUE_COLOR`), which `IsAnnotated` matches. A second read therefore bails rather than parsing the number as damage. That's why it runs after everything else, and why that colour must not be used anywhere else. No value is inserted when the stat is 0 (no mana). It isn't a setting.

`Analyze` returns a table (`totals`, `perTick`, `aoe`, `direct`, `directAoe`, `dots`, `dotUnknown`, `absorbDrain`, `comboPoints`, `duration`, `nextSwing`, `weaponSource`, `conversion`). `TickMultiplier` also returns each over-time clause's duration.

**Settings** live in `ns.db`: the defaults until `ADDON_LOADED`, then the saved variable `ResourceEfficiencyTooltipsDB`. Each of the four parts in `PARTS` (`efficiency`, `dps`, `coefficients`, `notes`) has an on/off key, all on by default, and a `<part>ShiftOnly` key, which defaults on for coefficients and notes only. `Shown(part)` checks both. Whenever any part is Shift-only, `Process` sets `shiftTooltip` for a GameTooltip spell, so `RefreshForShift` redraws it when Shift is pressed or released. Only the notes get a hint line; a Shift-only efficiency, DPS or coefficient part is simply absent until Shift is held. `Config.lua` is a small movable window with one checkbox per setting, opened by `ns.ToggleConfig()`. `Config.lua` builds its `OPTIONS` from its own `PARTS` list (keep it in step with the main file's), each followed by an indented "Only while Shift is held" option with `parent` set. Those are greyed out while their part is off. Changes apply the next time a tooltip is shown.

**Slash commands** are at the bottom of the main file. A bare `/ret` prints the help (`PrintHelp`) and opens the settings window. `/ret report` toggles the report, `/ret config` the settings, and `/ret debug` prints the last spell's parsed cast info, its coefficient and its lines. Any other argument opens the settings window.

`Report.lua` reuses the same code via `ns`: `ns.ReadSpellTooltip`, `ns.ComputeRatios`, `ns.GetCombatStats` (read once per refresh), `ns.GetCostFromAPI`, `ns.SpellKey`, `ns.FormatRatio`, `ns.ORDER/LABELS/COLORS/RESOURCES` and `ns.supported`. It scans spells with its own hidden tooltip, `ResourceEfficiencyTooltipsScanner`, which the hook ignores because it isn't in `TOOLTIPS`. It enumerates the spellbook with `C_SpellBook` if present, otherwise the `GetNumSpellTabs`/`GetSpellBookItemInfo` APIs. Both paths exist only because it's unconfirmed which one Forever has, not to support older clients. Once that's known, delete the unused one.

## Design decisions (agreed with the user; keep them consistent)

- **Amounts come from tooltip text**, so every rank gives its own number. The only live stats used are weapon damage and attack power, through `GetCombatStats` (`UnitDamage`, `UnitRangedDamage`, `UnitAttackPower`, wrapped in pcall).
- **Instant weapon strikes count the whole hit:** current average weapon damage × percent, plus the flat bonus. Examples: Sinister Strike, Backstab, Mortal Strike, Shred, Claw ("110% normal damage plus 115"), Aimed Shot ("increases *ranged* damage by N") and Bloodthirst (% of attack power).
- **Next-swing abilities count only their bonus**, because the auto attack would have landed anyway. Detected by wording ("increases *melee* damage by N" for Heroic Strike and Raptor Strike, "next attack by N" for Maul) or by name in `NEXT_SWING_SPELLS` for ones that read like instant strikes (Cleave).
- **An empowered swing generates no rage**, so rage-costing next-swing abilities (Heroic Strike, Cleave, Maul) cost their rage plus the rage that swing would have given. In WoW Forever an auto attack gives base main-hand speed × 3.46 rage with a one-handed weapon and × 4.50 with a two-handed one (`SWING_RAGE_ONE_HAND/TWO_HAND`). The speed is the weapon's base "Speed", read from its tooltip by `ReadMainHand` with its own hidden scanner (`ResourceEfficiencyTooltipsItemScanner`) and cached per item link. `UnitAttackSpeed` isn't used because it includes haste. Base speed is an assumption; the user gave the formula as "weapon speed". A Druid's Bear Form swing gives a flat 11 rage (`BEAR_SWING_RAGE`, confirmed in game by the user), whatever the weapon, so Maul doesn't read the weapon. `stats.bearForm` gives Maul its own note. Other classes aren't adjusted. A Warrior with no readable weapon isn't adjusted either. The results are in `stats.swingRage` (plus `swingSpeed`/`twoHand` for Warriors) from `GetCombatStats`, part of the cache key.
- **Finishers are rated at max combo points** and labelled "at 5 CP" in tooltips, "5cp" in the report.
- **Conversions are ignored** (`CONVERSION_PATTERNS`): Mana Burn's per-mana damage and Execute's per-extra-rage damage.
- **"Stacks up to N times" is not charges.** This was the Arcane Blast bug.
- **DPS only for spells cast back to back:** no cooldown, not next-swing, not a finisher. Instants use the GCD. Damage over time counts at its sustained rate while spamming (total ÷ max(duration, time per cast)), because recasting refreshes it rather than stacking it. Channels count everything over the channel. AoE is per target. DPS doesn't model resource limits or auto attacks.
- **Spell coefficients come from `SPELL_COEFFICIENTS`**, generated from the client's own spell data (the `SpellEffect` table, build 1.60.1.70450). They aren't derived from tooltips or formulas. Each spell is a list of `{ percent, kind }`, one per spell effect in `EffectIndex` order, e.g. `[133] = { { 42.9, "damage" }, { 0, "dot" } }`. The kind comes from `Effect`/`EffectAura`: `damage` (2), `heal` (10), `weapon` (7, 58, 64), `dot` (aura 3) and `hot` (aura 8). Show every part with its label, and never collapse them to one value. `weapon` parts are hidden, because they don't scale with spell power (Charge's 100%). The line says "Coefficient", not "spell power coefficient", because the data also gives 100% to `damage` effects on physical abilities like Kick.
- **Per-tick / per-target labels** appear when a duration can't be found, or the effect hits several targets.
- **English only.** `SUPPORTED_LOCALES` is enUS and enGB. Other locales leave tooltips untouched rather than show wrong numbers, and the report refuses to open.
- **Don't guess.** When something can't be calculated honestly, show nothing rather than a misleading number.
- **How ranks are grouped.** Everything is per rank except two name-keyed tables:
  - **Per rank:** amounts, durations and wording rules come from the tooltip text. Coefficients, the API cost and cooldown, and report rows are keyed by spell ID. Low ranks have their own lower coefficients, so coefficients must never be keyed by name. Spellbook tooltips stop reading at "Next rank", so the next rank's numbers never leak in.
  - **Per class:** forgone swing rage, the same for every rank.
  - **Per name:** `SHOT_INTERVALS` and `NEXT_SWING_SPELLS` are the escape hatch when wording alone is ambiguous, and they're meant to cover every rank. They're keyed by `SpellKey(name)`: lowercased, with any rank text ("Cleave (Rank 3)", "… Rank 2") stripped, so a title that includes the rank can't silently miss the lookup. A missed lookup would rate Cleave as a full weapon hit. The tooltip passes the title line, and the report passes the spellbook name. A name key also matches same-named NPC spells (37 spell IDs are called Cleave, 6 of them class spells), but only when the wording matches too, which is acceptable. Use a name key only when every rank behaves the same, and never for numbers that differ by rank.

## Adding support for a new tooltip wording

1. Get the exact text from the user: hover the spell in game and run `/ret debug`. It prints the parsed cast info (kind, seconds, cooldown), the coefficient and the normalized lines `Analyze` sees.
2. Prefer a general wording rule (a pattern in `WeaponAmount`, `ClauseKind`, `UNIT_WORDS`, `AOE_PATTERNS` or `CONVERSION_PATTERNS`) over a name-keyed special case.
3. Add it as a case to the matching suite in `tests/` (usually `test_parser.lua`), and run `lua5.1 tests/run.lua` to check for regressions.
4. Update the comments listing examples above the function you changed, since those comments are the catalogue of supported wordings.

## Regenerating the spell coefficients

`python scripts/generate_spell_coefficients.py` (optionally `--data data/<date>`; the default is the newest folder) does the following:

- Runs `SELECT_RET_SPELL_DATA_AS_LUA.sql` from the data folder against its `spelldb.db`. The database is opened read-only, so it's safe while a database browser has it open.
- Writes `SpellCoefficients.lua` with a header giving the generation time and source.
- Checks the result with `luac5.1 -p` before replacing the old file.

The query reads the base tables directly (`SpellEffect` and `SpellClassOptions`), not the `RET_SPELL_DATA` view. The output has no spaces or comments apart from the one-line generation timestamp, because the file ships and its size matters. To look up which spell an ID is, query `SpellName` in the database. It also filters `DifficultyID = 0`, because some spells have raid-difficulty copies of the same effect (Flame Spear, Blast Wave). The SQL files in `data/` use CRLF line endings, unlike the addon. To change the data, change the query and re-run the script; never edit `SpellCoefficients.lua` by hand.

## Testing outside the game

The regression suite lives in `tests/` (never shipped). Run it after every change, from anywhere:

```sh
lua5.1 tests/run.lua          # every suite; exit code 1 if anything fails
lua5.1 tests/test_parser.lua  # one suite
```

`run.lua` first compiles every `.lua` file the `.toc` lists, so new addon files are covered automatically. Then it runs each suite in its own interpreter, so one suite's stubs can't leak into another. The suites are:

| Suite | Covers |
|---|---|
| `test_parser.lua` | Per-point ratios, DPS, and cost and cast line reading (`ReadSpellTooltip`) |
| `test_coefficients.lua` | The coefficient line: labels, ordering, settings, second pass, Shift redraws |
| `test_notes.lua` | Forgone swing rage (Warrior, Bear Form), the Shift notes, Shift-only settings |
| `test_macro.lua` | The `SetAction` hook for `#showtooltip` macros and their spell IDs |
| `test_stat_values.lua` | Stat values inserted into descriptions (Arcane Wrath, Arcane Blast) |

These files are the catalogue of supported wordings and their expected numbers, so never fix a test by changing what it expects unless the user agreed to the new behaviour. Add a case for every new wording or fix, in the suite that covers it. A new suite has to be added to `SUITES` in `run.lua`.

`helpers.lua` provides:

- **WoW stubs:** 100 average melee and ranged damage, 1000 attack power, a Mage unless the suite changes it, enUS.
- **A fake GameTooltip:** `T.show(rows, spellID)` runs the TooltipDataProcessor post-call and returns the lines joined with ` | `.
- **Tooltip helpers:** `T.fakeTip` for `ReadSpellTooltip`, and `T.loadAddon()`, which loads the main file and `SpellCoefficients.lua` into a fresh `ns`.
- **Checks:** `T.check` (equal), `T.has` (contains / doesn't contain) and `T.finish`.
- **State a suite can change between cases:** `T.shift`, `T.class`, `T.maxMana`, `T.intellect`, `T.weapon` (the main hand's tooltip lines), `T.owner`, `T.actions`, `T.macroSpells`. It can also read `T.events`, `T.hooks`, `T.onEvent` and `T.postCall`.

When the addon starts calling a new WoW API at load or tooltip time, add a stub to `helpers.lua`. `Report.lua` and `Config.lua` need a real client, so they're only compiled. The tests can't cover in-game behaviour (real tooltips, real APIs, the windows), so changes there still need the user to test in game.

## Known gaps

- Multi-Shot style wording ("hitting 3 targets for an additional N damage") isn't handled.
- Whirlwind and other dual-wield strikes only use main-hand damage.
- The Classic finisher table format and some tooltip texts above were written from memory. Real in-game text may differ, so confirm with `/ret debug` output.
- Whether lower ranks appear in the report depends on the client's spellbook "show all ranks" behaviour.
- The report doesn't show DPS. Free spells only get DPS if their tooltip has a cast line, and percentage costs without the API only lose the efficiency part.
- The exact Forever cast and cooldown line wording ("Instant", "Channeled", "N sec cooldown") is assumed from Classic. Check `/ret debug`, which prints the parsed cast info.
- Mana, rage and energy share one sorted list in the report even though their points aren't comparable. This is accepted and documented in `DESCRIPTION.md`.
- Macros whose `#showtooltip` shows an item, or no spell, get no numbers.
- Coefficients only exist for spell IDs in `SPELL_COEFFICIENTS`. There's no formula fallback, and the values aren't used in the efficiency or DPS numbers.
- Shift redraws GameTooltip only. Chat-linked spells (ItemRefTooltip) show every Shift-only part instead.

## Conventions

- Match the existing style: file-level section banners (`-----` / `-- Section`), a comment above each function giving its purpose and return values, and lowercase example wordings in comments.
- Write for Forever's current API only (see "Target client"). Guard an API only when it's unconfirmed whether Forever has it, and never add a branch for an older client.
- Treat tooltip text as possibly secret (`issecretvalue`), as `ReadSpellTooltip` and `Process` do.
- Chat messages start with the coloured addon name (`|cff80c8ffResource Efficiency Tooltips|r`).
- Slash commands: `/ret` (help + settings), `/ret report`, `/ret config`, `/ret debug`, `/ret help`. A new command must also be added to the `help` output and to `DESCRIPTION.md`.
