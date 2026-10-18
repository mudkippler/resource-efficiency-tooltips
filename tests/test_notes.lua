-- Forgone swing rage on next-swing abilities, the Shift notes, and Shift-only settings per part.

local T = dofile((arg[0]:match("^(.*)[/\\]") or ".") .. "/helpers.lua")
local ns = T.loadAddon()
local format = string.format
ns.db.coefficients = false -- keep the coefficient line out of these tooltips

local REAPER = { link = "|Hitem:12784|h[Arcanite Reaper]|h",
    lines = { { "Arcanite Reaper" }, { "Two-Hand", "Axe" }, { "153 - 256 Damage", "Speed 3.80" } } }
local SWORD = { link = "|Hitem:1|h[Sword]|h",
    lines = { { "Sword" }, { "One-Hand", "Sword" }, { "50 - 90 Damage", "Speed 2.60" } } }

-- The first ratio as "%.3f" (or "none") and the notes.
local function Ratio(text, cost, name, resourceKey)
    local r = ns.ComputeRatios({ ns.Normalize(text) }, cost, name, nil, T.resource(resourceKey))
    return r[1] and format("%.3f", r[1].ratio) or "none", r.notes
end
local function n(value) return format("%.3f", value) end

---------------------------------------------------------------------------
-- Forgone swing rage
---------------------------------------------------------------------------

local HS = "A strong attack that increases melee damage by 157."
local MAUL = "Increases the druid's next attack by 18 damage."
T.class = "WARRIOR"

T.weapon = REAPER
T.check("Heroic Strike, two-hand 3.80: 3.8 x 4.50 forgone", (Ratio(HS, 15, "heroic strike", "rage")), n(157 / (15 + 3.8 * 4.5)))
T.weapon = SWORD
T.check("Heroic Strike, one-hand 2.60: 2.6 x 3.46 forgone", (Ratio(HS, 15, "heroic strike", "rage")), n(157 / (15 + 2.6 * 3.46)))
T.check("Cleave forgoes rage too", (Ratio("A sweeping attack that does your weapon damage plus 5 to the target and his nearest ally.", 20, "cleave", "rage")),
    n(5 / (20 + 2.6 * 3.46)))
local scans = T.scans
Ratio(HS, 15, "heroic strike", "rage")
Ratio(HS, 15, "heroic strike", "rage")
T.check("weapon tooltip read once per item link", T.scans - scans, 0)
T.check("instant strike unaffected (Mortal Strike)", (Ratio("A vicious strike that deals weapon damage plus 85.", 30, "mortal strike", "rage")), n(185 / 30))
T.check("mana next-swing unaffected (Raptor Strike)", (Ratio("A strong attack that increases melee damage by 5.", 15, "raptor strike", "mana")), n(5 / 15))
T.weapon = nil
T.check("no weapon: unadjusted", (Ratio(HS, 15, "heroic strike", "rage")), n(157 / 15))
T.weapon = { link = "|Hitem:2|h[Odd]|h", lines = { { "Odd" } } }
T.check("weapon without a speed line: unadjusted", (Ratio(HS, 15, "heroic strike", "rage")), n(157 / 15))

T.class, T.weapon = "DRUID", SWORD
T.check("Maul as a Druid: flat 11 rage per swing, whatever the weapon", (Ratio(MAUL, 15, "maul", "rage")), n(18 / (15 + 11)))
T.weapon = REAPER
T.check("Maul with a two-hander: still 11", (Ratio(MAUL, 15, "maul", "rage")), n(18 / (15 + 11)))
local _, maulNotes = Ratio(MAUL, 15, "maul", "rage")
T.has("Bear Form note on Maul", table.concat(maulNotes, " | "), "The empowered swing generates no rage, so the 11 rage a Bear Form swing gives counts as cost too: 15 + 11 rage.")
T.has("no TEMP left", table.concat(maulNotes, " | "), nil, "TEMP")
T.weapon = SWORD
T.class = "MAGE"
T.check("other classes unadjusted", (Ratio(MAUL, 15, "maul", "rage")), n(18 / 15))
T.class = "WARRIOR"

---------------------------------------------------------------------------
-- Notes on the tooltip
---------------------------------------------------------------------------

local HEROIC_STRIKE = { "Heroic Strike", "15 Rage", "Next melee", HS }
-- The Shift keycap shown instead of the notes until Shift is held.
local KEY = [[ |TInterface\AddOns\ResourceEfficiencyTooltips\shift:16:32|t]]
local FIREBALL = { "Fireball", "30 Mana", "1.5 sec cast", "Hurls a fiery ball that causes 16 to 25 Fire damage and an additional 2 Fire damage over 4 sec." }

T.has("Shift up: key after the efficiency suffix when there's no DPS", T.show(HEROIC_STRIKE), "dmg/rage|r)" .. KEY .. " | Next melee", "generates no rage")
T.has("Shift up: key after the DPS suffix, outside the brackets", T.show(FIREBALL), "dps|r)" .. KEY .. " | Hurls")
local fbUp = T.show(FIREBALL)
T.has("Shift up: only one key (not on the cost line too)", fbUp, "dmg/mana|r) | 1.5 sec", "dmg/mana|r)" .. KEY)
T.has("Shift up: no hint line", T.show(HEROIC_STRIKE), nil, "Hold Shift")
T.shift = true
local shown = T.show(HEROIC_STRIKE)
T.has("Shift down: bonus note", shown, "Only the bonus damage counts, because the swing would have hit anyway.")
T.has("Shift down: rage note", shown, "The empowered swing generates no rage, so the 9.0 rage it would have given (2.60 speed, one-handed) counts as cost too: 15 + 9.0 rage.")
T.has("Shift down: no key", shown, nil, "shift:16:32")
T.shift = false
T.has("Frostbolt: no notes, no key", T.show({ "Frostbolt", "25 Mana", "1.5 sec cast", "Launches a bolt of frost, causing 18 to 20 Frost damage." }), nil, "shift:16:32")
T.shift = true
T.has("Fireball: DoT DPS note", T.show(FIREBALL), "DPS counts damage over time at the rate it ticks while you keep recasting")
T.has("Immolate: mostly-DoT note", T.show({ "Immolate", "25 Mana", "2 sec cast", "Burns the enemy for 11 Fire damage and then an additional 20 Fire damage over 15 sec." }), "Most of the damage is over time, so DPS is that effect alone")
T.has("Mortal Strike: weapon note", T.show({ "Mortal Strike", "30 Rage", "Instant", "A vicious strike that deals weapon damage plus 85." }), "Uses your current main-hand weapon damage (100 average).")
T.has("Bloodthirst: attack power note", T.show({ "Bloodthirst", "30 Rage", "Instant", "Instantly attack the target causing damage equal to 45% of your attack power." }), "Uses your current attack power (1000).")
T.has("Execute: conversion note", T.show({ "Execute", "15 Rage", "Instant", "Attempt to finish off a wounded foe, causing 125 damage and converting each extra point of rage into 3 additional damage." }), "Extra damage from spending more than the cost isn't counted.")
T.has("Mana Shield: drain note", T.show({ "Mana Shield", "50 Mana", "Instant", "Absorbs 120 damage, draining 2 mana per damage absorbed. Lasts 1 min." }), "Counts the 2 mana drained per point absorbed as cost too.")
ns.db.efficiency = false
T.has("efficiency off: its notes go too", T.show(HEROIC_STRIKE), nil, "Only the bonus")
ns.db.efficiency = true
T.shift = false

---------------------------------------------------------------------------
-- Shift-only settings
---------------------------------------------------------------------------

T.has("notes Shift-only, Shift up: key", T.show(HEROIC_STRIKE), KEY)
ns.db.notesShiftOnly = false
T.has("notes always: shown without Shift, no key", T.show(HEROIC_STRIKE), "Only the bonus damage counts", "shift:16:32")
ns.db.notesShiftOnly, ns.db.notes = true, false
T.has("notes off: no key, no notes", T.show(HEROIC_STRIKE), "dmg/rage", "shift:16:32")
ns.db.notes = true

ns.db.efficiencyShiftOnly = true
T.has("efficiency Shift-only, Shift up: no suffix and so no notes", T.show(HEROIC_STRIKE), "Next melee", "dmg/rage")
local redraws = 0
T.owner = { UpdateTooltip = function() redraws = redraws + 1; T.show(HEROIC_STRIKE) end }
T.shift = true
T.onEvent(nil, "MODIFIER_STATE_CHANGED", "LSHIFT", 1)
T.has("Shift press redraws with the suffix", T.dump(), "dmg/rage|r) | Next melee")
T.check("redrawn once", redraws, 1)
T.owner, T.shift = nil, false
ns.db.dpsShiftOnly = true
T.has("DPS Shift-only, Shift up: no DPS", T.show(FIREBALL), "1.5 sec cast", "dps")
local link = T.show(HEROIC_STRIKE, nil, ItemRefTooltip)
T.has("chat link, Shift up: Shift-only efficiency shown anyway", link, "dmg/rage")
T.has("chat link, Shift up: notes, not the key", link, "Only the bonus damage counts", "shift:16:32")

T.finish()
