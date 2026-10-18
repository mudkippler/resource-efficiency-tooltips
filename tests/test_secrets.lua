-- Secret values in combat: wherever a number can't be calculated because a stat, cost, cooldown or
-- tooltip line it needs is secret, the crossed swords icon shows in brackets instead.

local T = dofile((arg[0]:match("^(.*)[/\\]") or ".") .. "/helpers.lua")
local ns = T.loadAddon()
ns.db.coefficients = false -- keep the coefficient line out of these tooltips

local ICON = "|TInterface\\CharacterFrame\\UI-StateIcon:18:18:0:0:64:64:32:64:0:31|t"
local SUFFIX = "  (" .. ICON .. ")"
local NOTE = "Something this needs is hidden during combat, so it shows again after combat."

local SHRED = { "Shred", "60 Energy", "Instant", "Shred the target, causing 225% damage plus 54 to the target." }
local CLAW = { "Claw", "45 Energy", "Instant", "Claw the enemy, causing 110% normal damage plus 115." }
local BLOODTHIRST = { "Bloodthirst", "30 Rage", "Instant", "Instantly attack the target causing damage equal to 45% of your attack power." }
local FROSTBOLT = { "Frostbolt", "25 Mana", "1.5 sec cast", "Launches a bolt of frost at the enemy, causing 18 to 20 Frost damage." }
local ARCANE_BLAST = { "Arcane Blast", "50 Mana", "2.5 sec cast",
    "Blasts the target with energy, dealing 34 to 38 Arcane damage. Each time you cast Arcane Blast, you gain 15% of your Intellect as Spell Damage." }
local ARCANE_WRATH = { "Arcane Wrath", "100 Mana", "2.5 sec cast",
    "Launches a projectile of pure Arcane energy at the enemy target, causing 122 to 146 Arcane damage. This spell gains additional Spell Damage equal to 5% of your maximum Mana." }
local HEROIC_STRIKE = { "Heroic Strike", "15 Rage", "Next melee", "A strong attack that increases melee damage by 157." }
local SWORD = { link = "|Hitem:1|h[Sword]|h",
    lines = { { "Sword" }, { "One-Hand", "Sword" }, { "50 - 90 Damage", "Speed 2.60" } } }

---------------------------------------------------------------------------
-- Weapon damage and attack power (Shred, Claw, Bloodthirst)
---------------------------------------------------------------------------

T.secrets.melee = true
local shown = T.show(SHRED)
T.has("Shred: icon instead of efficiency", shown, "60 Energy" .. SUFFIX)
T.has("Shred: icon instead of DPS", shown, "Instant" .. SUFFIX)
T.has("Shred: no numbers", shown, nil, "dmg/energy")
T.has("Claw: icon instead of efficiency", T.show(CLAW), "45 Energy" .. SUFFIX)
T.has("Bloodthirst doesn't need weapon damage", T.show(BLOODTHIRST), "dmg/rage")
T.has("spells without weapon damage are unaffected (Frostbolt)", T.show(FROSTBOLT), "dmg/mana")
T.has("Heroic Strike's bonus doesn't need weapon damage", T.show(HEROIC_STRIKE), "dmg/rage")
T.secrets.melee = nil

T.secrets.ap = true
T.has("Bloodthirst: icon when attack power is secret", T.show(BLOODTHIRST), "30 Rage" .. SUFFIX)
T.secrets.ap = nil

-- After combat the cached icon mustn't stick.
T.has("Shred after combat: numbers again", T.show(SHRED), "dmg/energy")

-- The note explains the icon, once, while Shift is held.
T.secrets.melee = true
T.shift = true
shown = T.show(SHRED)
local _, notes = shown:gsub(NOTE:gsub("%p", "%%%0"), "")
T.check("Shred, Shift: secret note once", notes, 1)
T.shift = false
T.has("Shred, Shift up: Shift key after the icon", T.show(SHRED), "Instant" .. SUFFIX .. " |T")
T.secrets.melee = nil

---------------------------------------------------------------------------
-- Stat values (Arcane Blast, Arcane Wrath)
---------------------------------------------------------------------------

T.secrets.intellect = true
shown = T.show(ARCANE_BLAST)
T.has("Arcane Blast: icon instead of the Intellect value", shown, "you gain 15%|cff6fc3ff (" .. ICON .. ")|r of your Intellect")
T.has("Arcane Blast: efficiency doesn't need it", shown, "dmg/mana")
T.secrets.intellect = nil
T.secrets.maxMana = true
T.has("Arcane Wrath: icon instead of the mana value", T.show(ARCANE_WRATH), "equal to 5%|cff6fc3ff (" .. ICON .. ")|r of your maximum Mana")
T.secrets.maxMana = nil
T.has("Arcane Blast after combat: the value again", T.show(ARCANE_BLAST), "15%|cff6fc3ff (45)|r of")

---------------------------------------------------------------------------
-- Forgone swing rage (the weapon's tooltip)
---------------------------------------------------------------------------

T.class, T.weapon = "WARRIOR", SWORD
T.secrets.weapon = true
T.has("Heroic Strike: icon when the weapon can't be read", T.show(HEROIC_STRIKE), "15 Rage" .. SUFFIX)
T.secrets.weapon = nil
T.has("Heroic Strike after combat: not cached as unreadable", T.show(HEROIC_STRIKE),
    string.format("%.2f dmg/rage", 157 / (15 + 2.6 * 3.46)))
T.class, T.weapon = "MAGE", nil

---------------------------------------------------------------------------
-- Tooltip text
---------------------------------------------------------------------------

shown = T.show({ "Frostbolt", "25 Mana", "1.5 sec cast", T.SECRET })
T.has("secret description: icon instead of efficiency", shown, "25 Mana" .. SUFFIX)
T.has("secret description: icon instead of DPS", shown, "1.5 sec cast" .. SUFFIX)
T.has("secret title: icon", T.show({ T.SECRET, "25 Mana", "1.5 sec cast", FROSTBOLT[4] }), "25 Mana" .. SUFFIX)
T.has("secret cooldown text: DPS icon only", T.show({ "Frostbolt", "25 Mana", { "1.5 sec cast", T.SECRET }, FROSTBOLT[4] }),
    "25 Mana  (|cffff9040")
T.has("secret cooldown text: DPS icon", T.show({ "Frostbolt", "25 Mana", { "1.5 sec cast", T.SECRET }, FROSTBOLT[4] }),
    "1.5 sec cast" .. SUFFIX)

-- A second pass (the macro hook after the post-call) bails on the icon.
T.secrets.melee = true
T.actions[1], T.macroSpells[7] = { "macro", 7 }, { 5221 }
T.setTip(SHRED)
T.postCall(GameTooltip, { id = 5221 })
T.hooks.SetAction(GameTooltip, 1)
local _, icons = T.dump():gsub("UI%-StateIcon", "")
T.check("second pass adds no second icon", icons, 2)
T.secrets.melee = nil

T.finish()
