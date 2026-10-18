-- Parser regressions: damage / healing / absorb per point, DPS, and cost and cast line reading.
-- With 100 average weapon damage and 1000 attack power, as a Mage (no forgone swing rage).

local T = dofile((arg[0]:match("^(.*)[/\\]") or ".") .. "/helpers.lua")
local ns = T.loadAddon()
local format = string.format

---------------------------------------------------------------------------
-- Per point of resource
---------------------------------------------------------------------------

-- "damage=0.760 aoe tick cp5" for each kind ComputeRatios returns, comma separated.
local function Ratios(text, cost, name)
    local out = {}
    for _, r in ipairs(ns.ComputeRatios({ ns.Normalize(text) }, cost, ns.Normalize(name))) do
        out[#out + 1] = format("%s=%.3f%s%s%s", r.kind, r.ratio, r.aoe and " aoe" or "", r.perTick and " tick" or "",
            r.comboPoints and (" cp" .. r.comboPoints) or "")
    end
    return table.concat(out, ", ")
end

local function damage(value) return format("damage=%.3f", value) end

local RATIO_CASES = {
    { "Arcane Blast", "Blasts the target with energy, dealing 364 to 424 Arcane damage. Each time you cast Arcane Blast, the casting time is reduced while mana cost is increased. Effect stacks up to 3 times and lasts 8 sec.", 195, damage(394 / 195) },
    { "Frostbolt", "Launches a bolt of frost at the enemy, causing 18 to 20 Frost damage and slowing movement speed by 40% for 5 sec.", 25, damage(19 / 25) },
    { "Heroic Strike", "A strong attack that increases melee damage by 157.", 15, damage(157 / 15) },
    { "Raptor Strike", "A strong attack that increases melee damage by 5.", 15, damage(5 / 15) },
    { "Maul", "Increases the druid's next attack by 18 damage.", 15, damage(18 / 15) },
    { "Cleave", "A sweeping attack that does your weapon damage plus 5 to the target and his nearest ally.", 20, damage(5 / 20) .. " aoe" },
    { "Aimed Shot", "An aimed shot that increases ranged damage by 70.", 75, damage(170 / 75) },
    { "Mortal Strike", "A vicious strike that deals weapon damage plus 85 and wounds the target, reducing the effectiveness of any healing by 50% for 10 sec.", 30, damage(185 / 30) },
    { "Execute", "Attempt to finish off a wounded foe, causing 125 damage and converting each extra point of rage into 3 additional damage. Only usable on enemies that have less than 20% health.", 15, damage(125 / 15) },
    { "Whirlwind", "In a whirlwind of steel you attack up to 4 enemies within 8 yards, causing weapon damage from both melee weapons to each enemy.", 25, damage(100 / 25) .. " aoe" },
    { "Bloodthirst", "Instantly attack the target causing damage equal to 45% of your attack power.", 30, damage(450 / 30) },
    { "Rend", "Wounds the target causing them to bleed for 15 damage over 9 sec.", 10, damage(1.5) },
    { "Sinister Strike", "An instant strike that causes 3 damage in addition to your normal weapon damage.", 45, damage(103 / 45) },
    { "Backstab", "Backstab the target, causing 150% weapon damage plus 15 to the target.", 60, damage(165 / 60) },
    { "Shred", "Shred the target, causing 225% damage plus 54 to the target.", 60, damage(279 / 60) },
    { "Claw", "Claw the enemy, causing 110% normal damage plus 115.", 45, damage(225 / 45) },
    { "Claw", "Claw the enemy, causing 27 additional damage.", 45, damage(127 / 45) },
    { "Rake", "Rake the target for 19 damage and an additional 39 damage over 9 sec.", 40, damage(58 / 40) },
    { "Eviscerate", "Finishing move that causes damage per combo point:\n1 point: 6-10 damage\n2 points: 12-16 damage\n3 points: 18-22 damage\n4 points: 24-28 damage\n5 points: 30-34 damage", 35, damage(32 / 35) .. " cp5" },
    { "Rupture", "Finishing move that causes damage over time.\n1 point: 40 damage over 8 secs\n5 points: 136 damage over 16 secs", 25, damage(136 / 25) .. " cp5" },
    { "Kidney Shot", "Finishing move that stuns the target. Lasts longer per combo point:\n1 point: 1 sec\n5 points: 5 sec", 25, "" },
    { "Mana Burn", "Destroy 100 mana from a target. For each mana destroyed in this way the target takes 0.5 Shadow damage.", 50, "" },
}
for _, case in ipairs(RATIO_CASES) do
    T.check("ratio: " .. case[1], Ratios(case[2], case[3], case[1]), case[4])
end

---------------------------------------------------------------------------
-- DPS
---------------------------------------------------------------------------

-- "12.667" or "22.667 aoe", or "nil" when no DPS is shown.
local function DPS(text, kind, seconds, cooldown, resourceKey, name)
    local r = ns.ComputeDPS({ ns.Normalize(text) }, { kind = kind, seconds = seconds, cooldown = cooldown },
        ns.Normalize(name), nil, T.resource(resourceKey))
    if not r then return "nil" end
    return format("%.3f%s", r.dps, r.aoe and " aoe" or "")
end

local function n(value) return format("%.3f", value) end

-- { label, spell name, text, cast kind, cast seconds, cooldown, resource, expected }
local DPS_CASES = {
    { "Frostbolt 1.5 sec", "frostbolt", "Launches a bolt of frost at the enemy, causing 18 to 20 Frost damage and slowing movement speed by 40% for 5 sec.", "cast", 1.5, nil, "mana", n(19 / 1.5) },
    { "Arcane Blast 2.5 sec", "arcane blast", "Blasts the target with energy, dealing 364 to 424 Arcane damage. Effect stacks up to 3 times and lasts 8 sec.", "cast", 2.5, nil, "mana", n(394 / 2.5) },
    { "Fireball counts its DoT", "fireball", "Hurls a fiery ball that causes 16 to 25 Fire damage and an additional 2 Fire damage over 4 sec.", "cast", 1.5, nil, "mana", n(20.5 / 1.5 + 2 / 4) },
    { "Immolate", "immolate", "Burns the enemy for 11 Fire damage and then an additional 20 Fire damage over 15 sec.", "cast", 2, nil, "mana", n(11 / 2 + 20 / 15) },
    { "Corruption (DoT only)", "corruption", "Corrupts the target, causing 40 Shadow damage over 12 sec.", "instant", 0, nil, "mana", n(40 / 12) },
    { "cast under the GCD", "smite", "Smites an enemy for 15 to 20 Holy damage.", "cast", 1.0, nil, "mana", n(17.5 / 1.5) },
    { "Arcane Explosion", "arcane explosion", "Causes an explosion of arcane magic around the caster, causing 32 to 36 Arcane damage to all enemies within 10 yards.", "instant", 0, nil, "mana", "22.667 aoe" },
    { "Flamestrike", "flamestrike", "Calls down a pillar of fire, burning all enemies within the area for 55 to 71 Fire damage and an additional 48 Fire damage over 8 sec.", "cast", 3, nil, "mana", "27.000 aoe" },
    { "Flamestrike, the user's example", "flamestrike", "Calls down a pillar of fire, burning all enemies within the area for 120 Fire damage and an additional 80 Fire damage over 8 sec.", "cast", 3, nil, "mana", "50.000 aoe" },
    { "short DoT lands in full", "test", "Burns the enemy for 10 Fire damage and an additional 6 Fire damage over 2 sec.", "cast", 3, nil, "mana", n(16 / 3) },
    { "Rake with the energy GCD", "rake", "Rake the target for 19 damage and an additional 39 damage over 9 sec.", "instant", 0, nil, "energy", n(19 + 39 / 9) },
    { "Rend", "rend", "Wounds the target causing them to bleed for 15 damage over 9 sec.", "instant", 0, nil, "rage", n(15 / 9) },
    { "ticking DoT", "test", "Burns the enemy for 10 Fire damage and then 5 Fire damage every 3 sec for 15 sec.", "cast", 2, nil, "mana", n(10 / 2 + 25 / 15) },
    { "ticking DoT without a duration", "test", "Burns the enemy for 10 Fire damage and then 5 Fire damage every 3 sec.", "cast", 2, nil, "mana", "nil" },
    { "Sinister Strike with the energy GCD", "sinister strike", "An instant strike that causes 3 damage in addition to your normal weapon damage.", "instant", 0, nil, "energy", "103.000" },
    { "Hamstring", "hamstring", "Maims the enemy, causing 5 damage and slowing the enemy's movement by 50% for 15 sec.", "instant", 0, nil, "rage", n(5 / 1.5) },
    { "Mortal Strike has a cooldown", "mortal strike", "A vicious strike that deals weapon damage plus 85.", "instant", 0, 6, "rage", "nil" },
    { "Heroic Strike is next melee", "heroic strike", "A strong attack that increases melee damage by 157.", "nextswing", nil, nil, "rage", "nil" },
    { "Eviscerate is a finisher", "eviscerate", "Finishing move:\n1 point: 6-10 damage\n5 points: 30-34 damage", "instant", 0, nil, "energy", "nil" },
    { "Arcane Missiles channel", "arcane missiles", "Launches Arcane Missiles at the enemy, causing 24 Arcane damage each second for 3 sec.", "channeled", nil, nil, "mana", "24.000" },
    { "Mind Flay channel", "mind flay", "Assault the target's mind with Shadow energy, causing 75 Shadow damage over 3 sec and slowing their movement speed by 50%.", "channeled", nil, nil, "mana", "25.000" },
    { "Blizzard channel AoE", "blizzard", "Ice shards pelt the target area doing 200 Frost damage over 8 sec.", "channeled", nil, nil, "mana", "25.000 aoe" },
    { "Lightning Shield charges", "lightning shield", "The caster is surrounded by 3 balls of lightning. When a spell, melee or ranged attack hits the caster, the attacker will be struck for 13 Nature damage. This expends one lightning ball. Lasts 10 min.", "instant", 0, nil, "mana", "nil" },
    { "Searing Totem", "searing totem", "Summons a Searing Totem with 5 health at your feet for 30 sec that repeatedly attacks an enemy within 20 yards for 9 to 11 Fire damage.", "instant", 0, nil, "mana", n(130 / 30) },
}
for _, case in ipairs(DPS_CASES) do
    T.check("dps: " .. case[1], DPS(case[3], case[4], case[5], case[6], case[7], case[2]), case[8])
end

---------------------------------------------------------------------------
-- Cost and cast line reading
---------------------------------------------------------------------------

-- "resource|cost|cast kind|cast seconds|cooldown|description line count", or "none".
local function Read(left, right)
    local _, res, cost, lines, cast = ns.ReadSpellTooltip(T.fakeTip(left, right))
    if not lines then return "none" end
    return format("%s|%s|%s|%s|%s|%d", res and res.key or "-", tostring(cost), cast and cast.kind or "-",
        cast and tostring(cast.seconds) or "-", cast and tostring(cast.cooldown) or "-", #lines)
end

T.check("read: cost, cast time and range", Read({ "Frostbolt", "25 Mana", "1.5 sec cast", "Launches a bolt of frost, causing 18 to 20 Frost damage." }, { "Rank 1", "30 yd range" }), "mana|25|cast|1.5|nil|1")
T.check("read: cooldown on the right", Read({ "Mortal Strike", "30 Rage", "Instant", "A vicious strike that deals weapon damage plus 85." }, { "Rank 1", "Melee Range", "6 sec cooldown" }), "rage|30|instant|0|6|1")
T.check("read: next melee", Read({ "Heroic Strike", "15 Rage", "Next melee", "A strong attack that increases melee damage by 157." }, {}), "rage|15|nextswing|nil|nil|1")
T.check("read: no cost, minute cooldown", Read({ "Shield Wall", "Instant", "Reduces damage taken." }, { nil, "30 min cooldown" }), "-|nil|instant|0|1800|1")
T.check("read: efficiency already added", Read({ "Frostbolt", "25 Mana  (0.76 dmg/mana)", "1.5 sec cast" }, {}), "none")
T.check("read: DPS already added", Read({ "Frostbolt", "25 Mana", "1.5 sec cast  (12.7 dps)" }, {}), "none")
T.check("read: \"instantly\" isn't a cast line", Read({ "Instant Poison", "Instantly coats your weapon." }, {}), "none")

---------------------------------------------------------------------------
-- Name-keyed special cases cover every rank
---------------------------------------------------------------------------

T.check("SpellKey: bare name", ns.SpellKey("Cleave"), "cleave")
T.check("SpellKey: \"(Rank 3)\" in the title", ns.SpellKey("Cleave (Rank 3)"), "cleave")
T.check("SpellKey: \"Rank 2\" in the title", ns.SpellKey("|cffffffffSearing Totem|r Rank 2"), "searing totem")
T.check("SpellKey: a name ending in a number is left alone", ns.SpellKey("Test Spell 2"), "test spell 2")
-- If the rank stopped the NEXT_SWING_SPELLS lookup, Cleave would count the whole weapon hit (105/20).
local CLEAVE = "A sweeping attack that does your weapon damage plus 5 to the target and his nearest ally."
for _, title in ipairs({ "Cleave", "Cleave (Rank 3)" }) do
    T.has("Cleave stays next-swing with title \"" .. title .. "\"", T.show({ title, "20 Rage", "Instant", CLEAVE }),
        "20 Rage  (|cffff90400.25 dmg/rage per target|r)")
end

T.finish()
