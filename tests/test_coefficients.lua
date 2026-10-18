-- The coefficient line at the bottom of spell tooltips: labels, ordering, settings and Shift redraws.
-- Uses the real SpellCoefficients.lua, so the spell IDs below must stay in the data.

local T = dofile((arg[0]:match("^(.*)[/\\]") or ".") .. "/helpers.lua")
local ns = T.loadAddon()

local FIREBALL = { "Fireball", "30 Mana", "1.5 sec cast", "Hurls a fiery ball that causes 16 to 25 Fire damage and an additional 2 Fire damage over 4 sec." }
local function Show(spellID, rows) return T.show(rows or FIREBALL, spellID) end

T.has("Shift-only, Shift up: no line", Show(133), "dmg/mana", "Coefficient:")
-- A chat link (ItemRefTooltip) isn't redrawn when Shift changes, so Shift-only parts show anyway.
local link = T.show(FIREBALL, 133, ItemRefTooltip)
T.has("chat link, Shift up: coefficient shown anyway", link, "| Coefficient: |cffffffff42.9% Direct / 0% DoT|r")
T.has("chat link: efficiency too", link, "dmg/mana")
T.shift = true
T.has("Shift-only, Shift down: last line", Show(133), "| Coefficient: |cffffffff42.9% Direct / 0% DoT|r")
T.has("Pyroblast: Direct and DoT", Show(11366), "Coefficient: |cffffffff100% Direct / 15% DoT|r")
T.has("Immolate: Direct first although the DoT is effect 0", Show(348), "Coefficient: |cffffffff20% Direct / 13% DoT|r")
T.has("Regrowth: Direct and HoT", Show(8936), "Coefficient: |cffffffff28.6% Direct / 7.1% HoT|r")
T.has("two direct parts keep effect order (Consecration)", Show(1280345), "Coefficient: |cffffffff0% Direct / 4.2% Direct|r")
T.has("one part: no label (Greater Heal)", Show(2060), "Coefficient: |cffffffff85.7%|r")
T.has("weapon-only spell (Charge): no line", Show(100), nil, "Coefficient:")
T.has("unknown spell: no line", Show(999999999), nil, "Coefficient:")
T.has("no spell ID: no line", Show(nil), nil, "Coefficient:")
T.shift = false

ns.db.coefficientsShiftOnly = false
T.has("always mode (Corruption)", Show(172), "Coefficient: |cffffffff20%|r")
T.has("spell without cost or cast line still gets it", Show(172, { "Corruption", "Corrupts the target." }), "Coefficient: |cffffffff20%|r")

-- Processing twice (the macro hook after the post-call) mustn't add a second line.
T.actions[1], T.macroSpells[7] = { "macro", 7 }, { 133 }
T.setTip(FIREBALL)
T.postCall(GameTooltip, { id = 133 })
T.hooks.SetAction(GameTooltip, 1)
local _, count = T.dump():gsub("Coefficient:", "")
T.check("second pass adds no second line", count, 1)

ns.db.coefficients = false
T.has("coefficients off", Show(133), "dmg/mana", "Coefficient:")
ns.db.coefficients, ns.db.efficiency, ns.db.dps = true, false, false
T.has("only coefficients on", Show(133), "Coefficient:", "dmg/mana")
ns.db.efficiency, ns.db.dps = true, true

-- Shift redraws through the owner's UpdateTooltip; releasing it redraws without the line.
ns.db.coefficientsShiftOnly = true
T.check("MODIFIER_STATE_CHANGED registered", T.events.MODIFIER_STATE_CHANGED, true)
local redraws = 0
T.owner = { UpdateTooltip = function() redraws = redraws + 1; Show(133) end }
Show(133)
T.shift = true
T.onEvent(nil, "MODIFIER_STATE_CHANGED", "LSHIFT", 1)
T.has("Shift press redraws with the line", T.dump(), "Coefficient:")
T.shift = false
T.onEvent(nil, "MODIFIER_STATE_CHANGED", "LSHIFT", 0)
T.has("Shift release redraws without it", T.dump(), nil, "Coefficient:")
T.onEvent(nil, "MODIFIER_STATE_CHANGED", "LCTRL", 1)
T.check("Ctrl doesn't redraw", redraws, 2)
T.setTip({ "Linen Cloth", "Trade Goods" })
T.onEvent(nil, "MODIFIER_STATE_CHANGED", "LSHIFT", 1)
T.check("no redraw once the tooltip shows an item", redraws, 2)
T.owner = nil

T.finish()
