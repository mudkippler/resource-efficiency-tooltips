-- Macros with #showtooltip: the GameTooltip:SetAction hook annotates them, and finds their spell ID.

local T = dofile((arg[0]:match("^(.*)[/\\]") or ".") .. "/helpers.lua")
local ns = T.loadAddon()
ns.db.coefficientsShiftOnly = false -- show the coefficient, which needs the spell ID

local FROSTBOLT = { "Frostbolt", "25 Mana", "1.5 sec cast", "Launches a bolt of frost, causing 18 to 20 Frost damage." }

-- Hovers action slot `slot` showing Frostbolt and returns the tooltip and the spell ID Process saw.
local function Hover(slot)
    ns.lastSpell = nil
    T.setTip(FROSTBOLT)
    T.hooks.SetAction(GameTooltip, slot)
    return T.dump(), ns.lastSpell and ns.lastSpell.id
end

T.actions = {
    [1] = { "macro", 5 },             -- spell from GetMacroSpell: name, rank, spellID
    [2] = { "macro", 6 },             -- spell from GetMacroSpell: just the spellID
    [3] = { "macro", 116, "spell" },  -- GetActionInfo gives the spell directly
    [4] = { "macro", 8 },             -- macro showing no spell
    [5] = { "spell", 116 },           -- plain spell: left to the spell tooltip hook
}
T.macroSpells = { [5] = { "Frostbolt", "Rank 1", 116 }, [6] = { 116 } }

T.check("SetAction hooked", type(T.hooks.SetAction), "function")
for slot, label in ipairs({ "macro, name/rank/spellID", "macro, spellID only", "macro, \"spell\" subtype" }) do
    local tip, id = Hover(slot)
    T.has(label .. ": efficiency and DPS", tip, "dmg/mana|r) | 1.5 sec cast  (|cffff904012.7 dps|r)")
    T.check(label .. ": spell ID", id, 116)
    T.has(label .. ": coefficient from the spell ID (Frostbolt rank 1)", tip, "Coefficient: |cffffffff40.7%|r")
end
local tip, id = Hover(4)
T.has("macro without a spell ID: still annotated", tip, "dmg/mana")
T.check("macro without a spell ID: no ID", id, nil)
T.has("macro without a spell ID: no coefficient", tip, nil, "Coefficient:")
tip = Hover(5)
T.has("plain spell: the SetAction hook leaves it alone", tip, nil, "dmg/mana")

T.finish()
