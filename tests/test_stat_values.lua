-- Stat values inserted into descriptions that scale with a player stat (Arcane Wrath, Arcane Blast).
-- 12240 max mana and 300 Intellect, from helpers.lua.

local T = dofile((arg[0]:match("^(.*)[/\\]") or ".") .. "/helpers.lua")
local ns = T.loadAddon()
ns.db.coefficients, ns.db.notes = false, false -- keep these tooltips to the description
local format = string.format

local VALUE = "|cff6fc3ff (%d)|r"

local ARCANE_WRATH = { "Arcane Wrath", "100 Mana", "2.5 sec cast",
    "Launches a projectile of pure Arcane energy at the enemy target, causing 122 to 146 Arcane damage. This spell gains additional Spell Damage equal to 5% of your maximum Mana." }
local ARCANE_BLAST = { "Arcane Blast", "50 Mana", "2.5 sec cast",
    "Blasts the target with energy, dealing 34 to 38 Arcane damage. Each time you cast Arcane Blast, you gain 15% of your Intellect as Spell Damage and the mana cost of Arcane Blast is increased by 175%. Effect stacks up to 4 times and lasts 15 sec from time of initial application." }

local shown = T.show(ARCANE_WRATH)
T.has("Arcane Wrath: 5% of 12240 max mana after the 5%", shown, "equal to 5%" .. format(VALUE, 612) .. " of your maximum Mana.")
T.has("Arcane Wrath: efficiency is the hit only, not the 612", shown, format("100 Mana  (|cffff9040%.2f dmg/mana|r)", 134 / 100))
T.has("Arcane Wrath: DPS is the hit only", shown, format("2.5 sec cast  (|cffff9040%.1f dps|r)", 134 / 2.5))

shown = T.show(ARCANE_BLAST)
T.has("Arcane Blast: 15% of 300 Intellect after the 15%", shown, "you gain 15%" .. format(VALUE, 45) .. " of your Intellect as Spell Damage")
T.has("Arcane Blast: the mana cost increase is left alone", shown, "is increased by 175%. Effect stacks")
T.has("Arcane Blast: efficiency is the hit only", shown, format("50 Mana  (|cffff9040%.2f dmg/mana|r)", 36 / 50))

-- The values follow the player's stats.
T.maxMana, T.intellect = 2000, 151
T.has("max mana changes the value", T.show(ARCANE_WRATH), "5%" .. format(VALUE, 100) .. " of")
T.has("Intellect changes the value, rounded", T.show(ARCANE_BLAST), "15%" .. format(VALUE, 23) .. " of") -- 22.65
T.maxMana, T.intellect = 0, 300
T.has("no mana (Warrior): no value", T.show(ARCANE_WRATH), "equal to 5% of your maximum Mana.", "|cff6fc3ff")
T.maxMana = 12240

-- A second pass (the macro hook after the post-call) mustn't insert twice or count 612 as damage,
-- including when no suffix was added to stop it earlier.
T.actions[1], T.macroSpells[7] = { "macro", 7 }, { 1326082 }
T.setTip(ARCANE_WRATH)
T.postCall(GameTooltip, { id = 1326082 })
T.hooks.SetAction(GameTooltip, 1)
local _, count = T.dump():gsub("|cff6fc3ff", "")
T.check("second pass inserts nothing", count, 1)
T.has("second pass doesn't count 612 as damage", T.dump(), format("%.1f dps", 134 / 2.5))

-- With efficiency and DPS hidden there's no suffix, so only the inserted value can stop a second pass.
ns.db.efficiencyShiftOnly, ns.db.dpsShiftOnly = true, true
T.setTip(ARCANE_WRATH)
T.postCall(GameTooltip, { id = 1326082 })
T.has("no suffix, value inserted", T.dump(), "5%" .. format(VALUE, 612), "dmg/mana")
T.check("the changed description stops a second read", (select(4, ns.ReadSpellTooltip(GameTooltip))), nil)
T.hooks.SetAction(GameTooltip, 1)
_, count = T.dump():gsub("|cff6fc3ff", "")
T.check("second pass inserts nothing (no suffix)", count, 1)
ns.db.efficiencyShiftOnly, ns.db.dpsShiftOnly = false, false

T.has("other wordings untouched", T.show({ "Evocation", "Channeled", "Restores 15% of base mana every 2 sec." }), "15% of base mana", "|cff6fc3ff")

T.finish()
