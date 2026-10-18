-- Resource Efficiency Tooltips
-- Appends damage / healing / absorb per point of mana, rage or energy to the cost line of spell tooltips,
-- and damage per second to the cast time line of spells that can be cast back to back.
-- Amounts are read from the tooltip's own description text, so they match the rank being shown.

local addonName, ns = ...

local format = string.format
local issecret = issecretvalue or function() return false end

-- The description parser only understands English tooltip text.
local SUPPORTED_LOCALES = { enUS = true, enGB = true }

-- Only annotate tooltips players look at; other addons' hidden scanning tooltips must not
-- be modified (or shown).
local TOOLTIPS = { GameTooltip = true, ItemRefTooltip = true }

-- Start of the line added at the bottom of spell tooltips for SPELL_COEFFICIENTS (SpellCoefficients.lua).
-- The colon is part of it so a description that uses the word isn't mistaken for our line.
local COEFFICIENT_PREFIX = "Coefficient:"

-- Colour of the stat values inserted into descriptions (AddStatValues). Only used there, so
-- IsAnnotated can recognise a description we've already changed.
local STAT_VALUE_COLOR = "ff6fc3ff"

-- How each kind of part in SPELL_COEFFICIENTS is labelled when a spell shows several, and its
-- order: direct parts before periodic ones. "weapon" isn't listed: weapon damage scales with the
-- weapon, not spell power (Charge's 100%), so those parts aren't shown. Neither are kinds added
-- to the data later until they're given an entry here.
local COEFFICIENT_KINDS = {
    damage = { label = "Direct", order = 1 },
    heal = { label = "Direct", order = 1 },
    dot = { label = "DoT", order = 2 },
    hot = { label = "HoT", order = 2 },
}

local ORDER = { "damage", "heal", "absorb" }
local LABELS = { damage = "dmg", heal = "heal", absorb = "absorb" }
local COLORS = { damage = "ffff9040", heal = "ff40ff60", absorb = "ff80c8ff" }

-- A number followed by one of these words isn't a damage/healing amount ("10 yards", "40%", "5 sec").
local UNIT_WORDS = {
    "yd", "yard", "sec", "second", "min", "hour", "ms", "target", "enem", "member",
    "time", "charge", "stack", "combo", "point", "level", "health", "mana", "rage", "energy", "feet", "foot",
    "party", "raid", "group", "ally", "allies",
}

-- A sentence containing any of these hits multiple targets, so its ratio is per target.
local AOE_PATTERNS = {
    "enemies", "targets", "party members", "group members", "raid members", "allies",
    "target area", "area of effect", "in an area", "in a cone", "nearby", "nearest ally",
}

-- Clauses that convert spare resource into damage aren't part of the cast's own output:
-- Mana Burn's "for each mana destroyed ... takes 0.5 damage", Execute's "converting each extra
-- point of rage into 3 additional damage".
local CONVERSION_PATTERNS = {
    "each mana", "per mana", "each extra point", "extra rage", "extra energy", "additional rage",
    "additional energy",
}

-- Seconds between attacks for summons whose tooltip says "repeatedly attacks" without
-- giving an interval. Keyed by lowercase spell name.
local SHOT_INTERVALS = {
    ["searing totem"] = 2.4,
}

-- Abilities that empower the next melee swing but whose tooltip reads like an instant strike
-- ("weapon damage plus 5"). Keyed by lowercase spell name.
local NEXT_SWING_SPELLS = {
    ["cleave"] = true,
}

---------------------------------------------------------------------------
-- Text helpers
---------------------------------------------------------------------------

local function EscapePattern(s)
    return (s:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"))
end

local function ToNum(s)
    return tonumber((s:gsub("[,%.]$", "")))
end

local function Normalize(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("|T.-|t", ""):gsub("|H.-|h(.-)|h", "%1")
    -- Thousands separators: "1,234,567" -> "1234567"
    text = text:gsub("(%d),(%d%d%d)", "%1%2"):gsub("(%d),(%d%d%d)", "%1%2")
    return text:lower()
end

---------------------------------------------------------------------------
-- Resource cost
---------------------------------------------------------------------------

local POWER = (Enum and Enum.PowerType) or {}

-- key: shown after the ratio label ("dmg/rage"); word / costFormat: the client's own strings
-- ("Rage", "%d Rage"); power / name: identify the resource in GetSpellPowerCost results.
local RESOURCES = {
    { key = "mana", word = MANA, costFormat = MANA_COST, power = POWER.Mana or 0, name = "MANA",
        color = "ff4fa8ff" },
    { key = "rage", word = RAGE, costFormat = RAGE_COST, power = POWER.Rage or 1, name = "RAGE",
        color = "ffff4040" },
    { key = "energy", word = ENERGY, costFormat = ENERGY_COST, power = POWER.Energy or 3, name = "ENERGY",
        color = "ffffe040" },
}
for _, res in ipairs(RESOURCES) do
    local word = EscapePattern((type(res.word) == "string" and res.word or res.key):lower())
    res.patterns = {}
    if type(res.costFormat) == "string" then
        -- e.g. "%d Rage" -> "^([%d,%.]+) rage"
        local p = EscapePattern(res.costFormat:lower()):gsub("%%d", "([%%d,%%.]+)"):gsub("%%s", ".-")
        res.patterns[#res.patterns + 1] = "^" .. p
    end
    res.patterns[#res.patterns + 1] = "^([%d,%.]+)%s*" .. word
    res.percentPattern = "^[%d%.]+%%.-" .. word
end

-- Returns the resource and cost of a cost line (cost is nil for percentage costs such as
-- "12% of base mana"), or nil if the line isn't a cost line.
local function MatchCost(text)
    local lower = text:lower()
    for _, res in ipairs(RESOURCES) do
        for _, pattern in ipairs(res.patterns) do
            local num = lower:match(pattern)
            if num then
                return res, tonumber((num:gsub(",", "")))
            end
        end
        if lower:find(res.percentPattern) then
            return res, nil
        end
    end
end

local GetPowerCost = (C_Spell and C_Spell.GetSpellPowerCost) or GetSpellPowerCost

local function GetCostFromAPI(spellID, res)
    if not (GetPowerCost and spellID and res) then return nil end
    local ok, cost = pcall(function()
        for _, entry in ipairs(GetPowerCost(spellID) or {}) do
            if (entry.type == res.power or entry.name == res.name) and entry.cost and entry.cost > 0 then
                return entry.cost
            end
        end
    end)
    return ok and cost or nil
end

-- Rage an auto attack generates in WoW Forever. A Warrior's main hand: base weapon speed x 3.46
-- with a one-handed weapon, x 4.50 with a two-handed one. A Druid in Bear Form (Maul): a flat 11
-- per swing, whatever the weapon.
local SWING_RAGE_ONE_HAND, SWING_RAGE_TWO_HAND = 3.46, 4.50
local BEAR_SWING_RAGE = 11
local MAIN_HAND_SLOT = 16

local weaponCache = {} -- item link -> { speed, twoHand }, or false if the speed can't be read
local itemScanner

-- The main-hand weapon's base speed ("Speed 3.60", before haste, which UnitAttackSpeed includes) and
-- whether it's two-handed, read from its tooltip. Returns nil without a readable weapon.
local function ReadMainHand()
    local link = GetInventoryItemLink("player", MAIN_HAND_SLOT)
    if not link then return nil end
    local weapon = weaponCache[link]
    if weapon == nil then
        itemScanner = itemScanner
            or CreateFrame("GameTooltip", "ResourceEfficiencyTooltipsItemScanner", nil, "GameTooltipTemplate")
        itemScanner:SetOwner(WorldFrame, "ANCHOR_NONE")
        itemScanner:SetInventoryItem("player", MAIN_HAND_SLOT)
        local speed, twoHand = nil, false
        for i = 1, itemScanner:NumLines() do
            local left = _G["ResourceEfficiencyTooltipsItemScannerTextLeft" .. i]
            local right = _G["ResourceEfficiencyTooltipsItemScannerTextRight" .. i]
            local leftText = left and left:GetText()
            local rightText = right and right:IsShown() and right:GetText()
            if leftText and not issecret(leftText) and leftText == "Two-Hand" then twoHand = true end
            if rightText and not issecret(rightText) then
                speed = speed or tonumber(rightText:match("^Speed (%d+%.?%d*)"))
            end
        end
        itemScanner:Hide()
        weapon = speed and { speed = speed, twoHand = twoHand } or false
        weaponCache[link] = weapon
    end
    return weapon or nil
end

-- Average weapon swing damage (including attack power) and attack power, used for abilities
-- that deal weapon damage, and the rage an auto attack generates (swingRage), used for
-- next-swing abilities. These change with gear, buffs and forms.
local function ReadCombatStats()
    local stats = {}
    local _, class = UnitClass("player")
    if class == "WARRIOR" then
        -- Its own pcall, so a failed tooltip read doesn't lose the other stats.
        local ok, weapon = pcall(ReadMainHand)
        if ok and weapon then
            stats.swingSpeed, stats.twoHand = weapon.speed, weapon.twoHand
            stats.swingRage = weapon.speed * (weapon.twoHand and SWING_RAGE_TWO_HAND or SWING_RAGE_ONE_HAND)
        end
    elseif class == "DRUID" then
        stats.swingRage, stats.bearForm = BEAR_SWING_RAGE, true
    end
    if UnitDamage then
        local minDamage, maxDamage = UnitDamage("player")
        if minDamage and maxDamage and maxDamage > 0 then stats.melee = (minDamage + maxDamage) / 2 end
    end
    if UnitRangedDamage then
        local _, minDamage, maxDamage = UnitRangedDamage("player")
        if minDamage and maxDamage and maxDamage > 0 then stats.ranged = (minDamage + maxDamage) / 2 end
    end
    if UnitAttackPower then
        local base, pos, neg = UnitAttackPower("player")
        if base then stats.ap = base + (pos or 0) + (neg or 0) end
    end
    return stats
end

local function GetCombatStats()
    local ok, stats = pcall(ReadCombatStats)
    return ok and stats or {}
end

---------------------------------------------------------------------------
-- Description parsing
---------------------------------------------------------------------------

local function IsUnitWord(word)
    if word:sub(1, 1) == "%" then return true end
    for _, unit in ipairs(UNIT_WORDS) do
        if word:sub(1, #unit) == unit then return true end
    end
    return false
end

-- Finds the first amount in a clause ("31 to 45" or "31-45" averages to 38).
-- Returns the amount and the text that follows it.
local function FindAmount(clause)
    local pos = 1
    while true do
        local s, e, num = clause:find("(%d+%.?%d*)", pos)
        if not s then return nil end
        local value, rest = ToNum(num), clause:sub(e + 1)
        local _, e2, num2 = rest:find("^%s+to%s+(%d+%.?%d*)")
        if not e2 then
            _, e2, num2 = rest:find("^%s*%-%s*(%d+%.?%d*)")
        end
        if e2 then
            value = (value + ToNum(num2)) / 2
            rest = rest:sub(e2 + 1)
        end
        local word = rest:match("^%s*(%S*)")
        local before = clause:sub(1, s - 1)
        -- "by N" / "by up to N" modifies other damage or healing (Dampen Magic's "healing by up to 20").
        local isModifier = before:find("%f[%a]by%s*$") or before:find("%f[%a]by%s+up%s+to%s*$")
        if value and not isModifier and not IsUnitWord(word) and not before:find("level%s*$")
            and not before:find("rank%s*$") then
            return value, rest
        end
        pos = e + (e2 or 0) + 1
    end
end

local function ParseDuration(text, prefix)
    local sec = text:match(prefix .. "%s+(%d+%.?%d*)%s*sec")
    if sec then return ToNum(sec) end
    local min = text:match(prefix .. "%s+(%d+%.?%d*)%s*min")
    if min then return ToNum(min) * 60 end
    return nil
end

-- Turns a per-tick amount into a total: "26 damage each second for 3 sec" -> x3.
-- Summons that "repeatedly attack" use shotInterval (seconds) over their duration.
-- Returns multiplier, isPerTick (true when ticks were found but no duration), and the seconds
-- the effect lasts (nil if it isn't over time or no duration was found).
local function TickMultiplier(clause, rest, lasts, shotInterval)
    if rest:find("over%s+%d") then return 1, false, ParseDuration(rest, "over") end -- already a total
    local interval = rest:match("every%s+(%d+%.?%d*)%s*sec")
    interval = interval and ToNum(interval)
    if not interval and (rest:find("every%s+sec") or rest:find("each%s+sec") or rest:find("per%s+sec")) then
        interval = 1
    end
    if not interval and clause:find("repeatedly") then
        if not shotInterval then return 1, true end
        interval = shotInterval
    end
    if not interval or interval <= 0 then return 1, false end
    local duration = ParseDuration(rest, "for") or ParseDuration(clause, "for") or lasts
    if not duration then return 1, true end
    return math.max(1, math.floor(duration / interval + 0.5)), false, duration
end

local function IsConversion(clause)
    for _, pattern in ipairs(CONVERSION_PATTERNS) do
        if clause:find(pattern, 1, true) then return true end
    end
    return false
end

-- false = clause doesn't describe throughput (and stops inheriting), nil = inherit the previous kind.
local function ClauseKind(clause)
    if clause:find("yourself") or clause:find("himself") or clause:find("herself") or clause:find("itself") then
        return false
    end
    if clause:find("increas") or clause:find("reduc") or clause:find("decreas") then
        return false
    end
    if IsConversion(clause) then
        return false
    end
    if clause:find("absorb") then return "absorb" end
    -- "health" (e.g. a totem "with 5 health") isn't healing.
    if clause:gsub("health", ""):find("heal") then return "heal" end
    if clause:find("damage") then return "damage" end
    return nil
end

local WORD_NUMBERS = {
    two = 2, three = 3, four = 4, five = 5, six = 6, seven = 7, eight = 8, nine = 9, ten = 10,
}

-- Number of times a charge-based effect can trigger per cast, e.g. Lightning Shield's
-- "3 charges", "three charges", "can be hit by an attacker 3 times", or
-- "surrounded by 3 balls of lightning ... this expends one lightning ball".
local function ParseCharges(text)
    local suffixes = { "charges?", "times" }
    local expended = text:match("expends one ([%a%s]-)[%.,;]") or text:match("consumes one ([%a%s]-)[%.,;]")
    local noun = expended and expended:match("(%a+)%s*$")
    if noun then
        table.insert(suffixes, 1, noun:gsub("s$", "") .. "s?")
    end
    for _, suffix in ipairs(suffixes) do
        local pos = 1
        while true do
            local s, e, count = text:find("(%w+)%s+" .. suffix, pos)
            if not s then break end
            -- "stacks up to 4 times" (Arcane Blast) is a debuff stack limit, not charges.
            local isStackLimit = text:sub(1, s - 1):find("stacks?%s+up%s+to%s*$")
            local charges = tonumber(count) or WORD_NUMBERS[count]
            if charges and charges > 1 and not isStackLimit then return charges end
            pos = e + 1
        end
    end
    return 1
end

local function IsAoE(sentence)
    for _, pattern in ipairs(AOE_PATTERNS) do
        if sentence:find(pattern, 1, true) then return true end
    end
    return false
end

-- Mana drained per point of damage absorbed, e.g. Mana Shield's "draining 2 mana per damage absorbed".
local function ParseAbsorbDrain(text)
    if not text:find("absorb") then return nil end
    local mana, damage = text:match("(%d+%.?%d*) mana per (%d+%.?%d*) [%a%s]-damage")
    if mana then return ToNum(mana) / ToNum(damage) end
    mana = text:match("(%d+%.?%d*) mana per") or text:match("(%d+%.?%d*) mana for each")
        or text:match("drain%a* (%d+%.?%d*) mana") or text:match("cost%a* (%d+%.?%d*) mana")
    return mana and ToNum(mana)
end

-- Damage of a clause that strikes with a weapon. Instant strikes count the whole hit, using the
-- player's current weapon damage: "weapon damage plus 85", "150% weapon damage plus 15",
-- "110% normal damage plus 115" (Claw), "225% damage plus 54" (Shred), "3 damage in addition to
-- your normal weapon damage", "increases ranged damage by 70" (Aimed Shot) and "damage equal to
-- 45% of your attack power" (Bloodthirst). Abilities that empower the next melee swing replace
-- an auto attack that would have hit anyway, so only their bonus counts: "increases melee damage
-- by 157" (Heroic Strike), "next attack by 18 damage" (Maul) and NEXT_SWING_SPELLS.
-- Returns isWeaponStrike, damage (nil when the needed stat isn't available), isNextSwing, and the stat
-- an instant strike used ("melee", "ranged" or "ap"; nil for next-swing abilities).
local function WeaponAmount(clause, stats, isNextSwingSpell)
    local apPercent = clause:match("(%d+%.?%d*)%% of your attack power")
    if apPercent then
        return true, stats.ap and stats.ap * ToNum(apPercent) / 100, false, "ap"
    end
    local percent = clause:match("(%d+%.?%d*)%% weapon damage") or clause:match("(%d+%.?%d*)%% normal damage")
        or clause:match("(%d+%.?%d*)%% damage plus")
    local bonus = clause:match("weapon damage plus (%d+%.?%d*)") or clause:match("normal damage plus (%d+%.?%d*)")
        or clause:match("%% damage plus (%d+%.?%d*)") or clause:match("(%d+%.?%d*) damage in addition to")
        or clause:match("(%d+%.?%d*) additional damage") or clause:match("ranged damage by (%d+%.?%d*)")
    local nextSwingBonus = clause:match("melee damage by (%d+%.?%d*)") or clause:match("next attack by (%d+%.?%d*)")
    if nextSwingBonus then
        return true, ToNum(nextSwingBonus), true
    end
    if not (percent or bonus or clause:find("weapon damage") or clause:find("normal damage")) then
        return false
    end
    if isNextSwingSpell then
        return true, bonus and ToNum(bonus) or nil, true
    end
    local source = clause:find("ranged") and "ranged" or "melee"
    local weapon = stats[source]
    if not weapon then return true, nil, false, source end
    return true, weapon * (percent and ToNum(percent) / 100 or 1) + (bonus and ToNum(bonus) or 0), false, source
end

-- Finishers list an amount per combo point ("1 point: 6-10 damage" ... "5 points: 30-34 damage").
-- Keeps only the line for the most combo points, without its "5 points:" prefix.
-- Returns the lines and that number of combo points (nil if the spell isn't a finisher).
local function KeepMaxComboPoints(lines)
    local maxPoints = 0
    for _, line in ipairs(lines) do
        local points = tonumber(line:match("^%s*(%d+)%s+points?%s*:") or "")
        if points and points > maxPoints then maxPoints = points end
    end
    if maxPoints == 0 then return lines, nil end
    local kept = {}
    for _, line in ipairs(lines) do
        local points, rest = line:match("^%s*(%d+)%s+points?%s*:%s*(.*)")
        if not points then
            kept[#kept + 1] = line
        elseif tonumber(points) == maxPoints then
            kept[#kept + 1] = rest
        end
    end
    return kept, maxPoints
end

-- True if a clause's amount arrives over time rather than on impact: "39 damage over 9 sec",
-- "26 damage every 1 sec", "repeatedly attacks".
local function IsOverTime(clause)
    return clause:find("over%s+%d") or clause:find("every") or clause:find("each%s+sec")
        or clause:find("per%s+sec") or clause:find("repeatedly")
end

-- lines: normalized (lowercase) tooltip lines; spellName: lowercase spell name, if known;
-- stats: GetCombatStats() for weapon-based abilities.
-- Returns a table with:
--   totals[kind], perTick[kind], aoe[kind]: everything one cast does;
--   direct[kind], directAoe[kind]: only what lands on impact, used for DPS;
--   dots[kind]: list of { total, duration, aoe } for each over-time effect (damage over time,
--     ticks, summons that repeatedly attack), used for DPS;
--   dotUnknown[kind]: true if an over-time effect had no duration, so DPS can't be calculated;
--   charges count towards totals only, because they trigger when the caster is hit, not on cast;
--   absorbDrain: mana per point absorbed, or nil;
--   comboPoints: the combo points a finisher was rated at, or nil;
--   duration: seconds from "over N sec", "for N sec" or "lasts N sec" (a channel's length), or nil;
--   nextSwing: true for abilities that empower the next melee swing (WeaponAmount);
--   weaponSource: the stat an instant weapon strike used ("melee", "ranged" or "ap"), or nil;
--   conversion: true if a clause converting spare resource into damage was skipped.
local function Analyze(lines, spellName, stats)
    local totals, perTick, aoe, direct, directAoe, dots, dotUnknown = {}, {}, {}, {}, {}, {}, {}
    local result = { totals = totals, perTick = perTick, aoe = aoe, direct = direct, directAoe = directAoe,
        dots = dots, dotUnknown = dotUnknown }
    stats = stats or {}
    -- Descriptions can span several lines in one font string.
    local split = {}
    for _, line in ipairs(lines) do
        for part in line:gmatch("[^\n]+") do
            split[#split + 1] = part
        end
    end
    local comboPoints
    lines, comboPoints = KeepMaxComboPoints(split)
    local fullText = table.concat(lines, " ")
    -- Weapon imbues (Flametongue, Frostbrand, Windfury...) and Paladin seals scale with
    -- weapon hits, not casts.
    if fullText:find("imbue") or fullText:find("only one seal") or fullText:find("each melee attack") then
        return result
    end
    local lasts = ParseDuration(fullText, "lasts")
    result.comboPoints = comboPoints
    result.absorbDrain = ParseAbsorbDrain(fullText)
    result.duration = ParseDuration(fullText, "over") or ParseDuration(fullText, "for") or lasts
    local charges = ParseCharges(fullText)
    local shotInterval = spellName and SHOT_INTERVALS[spellName]
    local isNextSwingSpell = spellName and NEXT_SWING_SPELLS[spellName]
    for _, line in ipairs(lines) do
        local sentences = line:gsub("%.%s+", "\1")
        for sentence in sentences:gmatch("[^\1]+") do
            local kind
            local sentenceIsAoE = IsAoE(sentence)
            local clauses = sentence:gsub("%s+and%s+", "\2"):gsub(";", "\2")
            local function add(value, mult, tick, overTime, duration)
                totals[kind] = (totals[kind] or 0) + value * mult * charges
                perTick[kind] = perTick[kind] or tick
                aoe[kind] = aoe[kind] or sentenceIsAoE
                if charges > 1 then return end
                if overTime or tick or mult > 1 then
                    if duration and duration > 0 and not tick then
                        dots[kind] = dots[kind] or {}
                        table.insert(dots[kind], { total = value * mult, duration = duration, aoe = sentenceIsAoE })
                    else
                        dotUnknown[kind] = true
                    end
                else
                    direct[kind] = (direct[kind] or 0) + value
                    directAoe[kind] = directAoe[kind] or sentenceIsAoE
                end
            end
            for clause in clauses:gmatch("[^\2]+") do
                if IsConversion(clause) then result.conversion = true end
                -- Checked before ClauseKind, which would reject Heroic Strike's "increases melee damage".
                local isWeaponStrike, weaponDamage, isNextSwing, source = WeaponAmount(clause, stats, isNextSwingSpell)
                local clauseKind = ClauseKind(clause)
                if isWeaponStrike and not IsConversion(clause) then
                    kind = "damage"
                    result.nextSwing = result.nextSwing or isNextSwing
                    result.weaponSource = result.weaponSource or source
                    if weaponDamage and weaponDamage > 0 then
                        add(weaponDamage, 1, false, false)
                    end
                elseif clauseKind == false then
                    kind = nil
                else
                    kind = clauseKind or kind
                    if kind then
                        local value, rest = FindAmount(clause)
                        if value and value > 0 then
                            local mult, tick, duration = TickMultiplier(clause, rest, lasts, shotInterval)
                            add(value, mult, tick, IsOverTime(clause), duration)
                        end
                    end
                end
            end
        end
    end
    return result
end

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------

local function FormatRatio(ratio)
    if ratio >= 10 then return format("%.1f", ratio) end
    return format("%.2f", ratio)
end

-- Action button tooltips refresh several times a second; cache each suffix per tooltip text.
local cache = {}
local cacheKeys = {}
local CACHE_SIZE = 200

-- Returns the cached value for key, calling build() (which may return false) on a miss.
local function Cached(key, build)
    local value = cacheKeys[key]
    if value == nil then
        value = build()
        if #cache >= CACHE_SIZE then
            cacheKeys[table.remove(cache, 1)] = nil
        end
        cache[#cache + 1] = key
        cacheKeys[key] = value
    end
    return value
end

-- Returns a list of { kind, ratio, perTick, aoe, comboPoints } in ORDER, empty if nothing could
-- be calculated, with .notes: sentences explaining calculations that aren't obvious, shown while
-- Shift is held. stats defaults to the player's current GetCombatStats(); resource is the cost's
-- resource (RESOURCES entry), may be nil.
local function ComputeRatios(lines, cost, spellName, stats, resource)
    stats = stats or GetCombatStats()
    local a = Analyze(lines, spellName, stats)
    local ratios, notes = {}, {}
    ratios.notes = notes
    -- An empowered swing (Heroic Strike, Cleave, Maul) generates no rage, so the rage it would have
    -- given is spent too.
    local forgoneRage = a.nextSwing and resource and resource.key == "rage" and stats.swingRage
    for _, kind in ipairs(ORDER) do
        local total = a.totals[kind]
        if total and total > 0 then
            -- Shields that drain mana as they absorb (Mana Shield) cost the cast plus the drain.
            local totalCost = cost
            if kind == "absorb" and a.absorbDrain then
                totalCost = cost + total * a.absorbDrain
            elseif kind == "damage" and forgoneRage then
                totalCost = cost + forgoneRage
            end
            ratios[#ratios + 1] = { kind = kind, ratio = total / totalCost, perTick = a.perTick[kind],
                aoe = a.aoe[kind], comboPoints = a.comboPoints }
        end
    end
    if #ratios == 0 then return ratios end

    if a.nextSwing then
        notes[#notes + 1] = "Only the bonus damage counts, because the swing would have hit anyway."
    end
    if forgoneRage and stats.bearForm then
        notes[#notes + 1] = format("The empowered swing generates no rage, so the %g rage a Bear Form "
            .. "swing gives counts as cost too: %d + %g rage.", forgoneRage, cost, forgoneRage)
    elseif forgoneRage then
        notes[#notes + 1] = format("The empowered swing generates no rage, so the %.1f rage it would have "
            .. "given (%.2f speed, %s) counts as cost too: %d + %.1f rage.", forgoneRage, stats.swingSpeed,
            stats.twoHand and "two-handed" or "one-handed", cost, forgoneRage)
    end
    if a.weaponSource == "ap" and stats.ap then
        notes[#notes + 1] = format("Uses your current attack power (%d).", stats.ap)
    elseif a.weaponSource and stats[a.weaponSource] then
        notes[#notes + 1] = format("Uses your current %s weapon damage (%d average).",
            a.weaponSource == "ranged" and "ranged" or "main-hand", stats[a.weaponSource])
    end
    if a.absorbDrain and a.totals.absorb then
        notes[#notes + 1] = format("Counts the %g mana drained per point absorbed as cost too.", a.absorbDrain)
    end
    if a.conversion then
        notes[#notes + 1] = "Extra damage from spending more than the cost isn't counted."
    end
    return ratios
end

-- Global cooldown in seconds: energy users (Rogues, cat form) have a 1 sec GCD.
local function GlobalCooldown(resource)
    return (resource and resource.key == "energy") and 1 or 1.5
end

-- Damage per second of casting a spell back to back. Only for spells that can be: no cooldown,
-- not a next-swing ability, not a combo point finisher. A cast takes its cast time, but never
-- less than the global cooldown (so instants use the GCD).
-- Normal casts: impact damage / time per cast, plus each damage-over-time effect at the rate it
-- keeps ticking while recast: total / max(its duration, time per cast). Recasting refreshes the
-- effect rather than stacking it, so Flamestrike (120 on impact, 3 sec cast, 80 over 8 sec) is
-- 120/3 + 80/8 = 50; a DoT shorter than the cast time lands in full every cast.
-- Channels: everything they do over the channel.
-- cast: from ReadSpellTooltip; resource: the cost's resource (sets the GCD), may be nil.
-- Returns { dps, aoe, notes } or nil (notes as in ComputeRatios).
local function ComputeDPS(lines, cast, spellName, stats, resource)
    if not cast or cast.kind == "nextswing" or (cast.cooldown and cast.cooldown > 0) then return nil end
    local a = Analyze(lines, spellName, stats or GetCombatStats())
    if a.comboPoints then return nil end
    local gcd = GlobalCooldown(resource)
    if cast.kind == "channeled" then
        local damage, seconds = a.totals.damage, a.duration
        if a.perTick.damage or not (damage and damage > 0 and seconds) then return nil end
        return { dps = damage / math.max(seconds, gcd), aoe = a.aoe.damage, notes = {} }
    end
    if a.dotUnknown.damage then return nil end
    local seconds = math.max(cast.seconds or 0, gcd)
    local dps = (a.direct.damage or 0) / seconds
    local isAoE = a.directAoe.damage
    local dots = a.dots.damage or {}
    for _, dot in ipairs(dots) do
        dps = dps + dot.total / math.max(dot.duration, seconds)
        isAoE = isAoE or dot.aoe
    end
    if dps <= 0 then return nil end
    local notes = {}
    if #dots > 0 then
        notes[1] = "DPS counts damage over time at the rate it ticks while you keep recasting, because "
            .. "recasting refreshes it rather than stacking it."
    end
    return { dps = dps, aoe = isAoE, notes = notes }
end

-- Returns { suffix, notes } for the cost line; suffix is nil when nothing could be calculated.
local function BuildSuffix(lines, cost, resource, spellName, stats)
    local ratios = ComputeRatios(lines, cost, spellName, stats, resource)
    local parts = {}
    for _, r in ipairs(ratios) do
        parts[#parts + 1] = format("|c%s%s %s/%s%s%s%s|r", COLORS[r.kind], FormatRatio(r.ratio),
            LABELS[r.kind], resource.key, r.comboPoints and format(" at %d CP", r.comboPoints) or "",
            r.perTick and " per tick" or "", r.aoe and " per target" or "")
    end
    if #parts == 0 then return { notes = {} } end
    return { suffix = "  (" .. table.concat(parts, ", ") .. ")", notes = ratios.notes }
end

local function StatsKey(stats)
    return format("%.1f|%.1f|%.1f|%.2f", stats.melee or 0, stats.ranged or 0, stats.ap or 0, stats.swingRage or 0)
end

-- Returns the cost line suffix (or nil) and its notes.
local function GetSuffix(lines, cost, resource, spellName)
    local stats = GetCombatStats()
    local key = format("ratio|%s|%s|%s|%s|%s", cost, resource.key, spellName or "", StatsKey(stats),
        table.concat(lines, "|"))
    local entry = Cached(key, function() return BuildSuffix(lines, cost, resource, spellName, stats) end)
    return entry.suffix, entry.notes
end

-- Returns the cast time line suffix, e.g. "  (52.3 dps)" (or nil), and its notes.
local function GetDPSSuffix(lines, cast, resource, spellName)
    local stats = GetCombatStats()
    local key = format("dps|%s|%s|%s|%s|%s|%s|%s", cast.kind, cast.seconds or "", cast.cooldown or 0,
        resource and resource.key or "", spellName or "", StatsKey(stats), table.concat(lines, "|"))
    local entry = Cached(key, function()
        local r = ComputeDPS(lines, cast, spellName, stats, resource)
        if not r then return { notes = {} } end
        return { suffix = format("  (|c%s%s dps%s|r)", COLORS.damage, FormatRatio(r.dps),
            r.aoe and " per target" or ""), notes = r.notes }
    end)
    return entry.suffix, entry.notes
end

-- True if a line is one we added or already carries one of our suffixes ("dmg/rage", "52.3 dps",
-- "Coefficient: 42.9%") or stat values ("5% (612) of your maximum mana").
local function IsAnnotated(text)
    if text:find("%d dps") or text:find(COEFFICIENT_PREFIX, 1, true) then return true end
    if text:find("|c" .. STAT_VALUE_COLOR .. " (", 1, true) then return true end
    for _, res in ipairs(RESOURCES) do
        for _, label in pairs(LABELS) do
            if text:find(label .. "/" .. res.key, 1, true) then return true end
        end
    end
    return false
end

-- Cast time line: "1.5 sec cast", "instant", "channeled", "next melee" (Heroic Strike).
-- Returns kind ("cast", "instant", "channeled" or "nextswing") and the cast time in seconds.
local function MatchCast(text)
    local seconds = text:match("^(%d+%.?%d*) sec cast%s*$")
    if seconds then return "cast", ToNum(seconds) end
    if text:find("^instant%s*$") or text:find("^instant cast%s*$") then return "instant", 0 end
    if text:find("^channeled%s*$") then return "channeled", nil end
    if text:find("^next melee%s*$") or text:find("^next ranged%s*$") then return "nextswing", nil end
end

-- Cooldown in seconds from "6 sec cooldown" or "10 min cooldown", or nil.
local function MatchCooldown(text)
    local sec = text:match("^(%d+%.?%d*) sec cooldown")
    if sec then return ToNum(sec) end
    local min = text:match("^(%d+%.?%d*) min cooldown")
    return min and ToNum(min) * 60
end

-- Reads a named spell tooltip. Returns the cost font string, the resource, the cost (nil for
-- percentage costs), the normalized description lines and the cast info
-- { line = font string, kind, seconds, cooldown } (see MatchCast).
-- The cost values or cast are nil when the tooltip has no such line. Returns nothing if it has
-- neither, or is already annotated.
local function ReadSpellTooltip(tooltip)
    local name = tooltip:GetName()
    local costLine, resource, cost, cast, cooldown
    local lines = {}
    for i = 2, tooltip:NumLines() do
        local fontString = _G[name .. "TextLeft" .. i]
        local text = fontString and fontString:GetText()
        if text and not issecret(text) then
            if IsAnnotated(text) then return end
            local lower = Normalize(text)
            if lower:find("^next rank") then break end
            local lineResource, lineCost, castKind, castSeconds, lineCooldown
            if i <= 5 then
                if not costLine then lineResource, lineCost = MatchCost(lower) end
                if not lineResource and not cast then castKind, castSeconds = MatchCast(lower) end
                if not (lineResource or castKind) then lineCooldown = MatchCooldown(lower) end
                -- The range and cooldown sit to the right of the cost and cast lines.
                local right = _G[name .. "TextRight" .. i]
                local rightText = right and right:IsShown() and right:GetText()
                if rightText and not issecret(rightText) then
                    cooldown = cooldown or MatchCooldown(Normalize(rightText))
                end
            end
            if lineResource then
                costLine, resource, cost = fontString, lineResource, lineCost
            elseif castKind then
                cast = { line = fontString, kind = castKind, seconds = castSeconds }
            elseif lineCooldown then
                cooldown = cooldown or lineCooldown
            else
                lines[#lines + 1] = lower
            end
        end
    end
    if cast then cast.cooldown = cooldown end
    if not (costLine or cast) then return end
    return costLine, resource, cost, lines, cast
end

local GetBaseCooldown = GetSpellBaseCooldown

-- Cooldown in seconds from the API, for cooldowns the tooltip text didn't show; nil if unknown.
local function GetCooldownFromAPI(spellID)
    if not (GetBaseCooldown and spellID) then return nil end
    local ok, ms = pcall(GetBaseCooldown, spellID)
    return ok and type(ms) == "number" and ms / 1000 or nil
end

-- A spell's coefficients from SPELL_COEFFICIENTS as text. One part is just its percent ("81.4%");
-- several are labelled, direct parts first ("100% Direct / 15% DoT", Immolate's "20% Direct / 13% DoT").
-- Parts without a COEFFICIENT_KINDS entry are left out. Returns nil if the spell has no entry or
-- nothing to show.
local function FormatCoefficients(spellID)
    local parts = {}
    for i, part in ipairs(spellID and ns.SPELL_COEFFICIENTS[spellID] or {}) do
        local kind = COEFFICIENT_KINDS[part[2]]
        if kind then
            parts[#parts + 1] = { percent = part[1], label = kind.label, order = kind.order, index = i }
        end
    end
    if #parts == 0 then return nil end
    if #parts == 1 then return format("%g%%", parts[1].percent) end
    -- Effect order breaks ties, so the sort is stable.
    table.sort(parts, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.index < b.index
    end)
    local texts = {}
    for i, part in ipairs(parts) do
        texts[i] = format("%g%% %s", part.percent, part.label)
    end
    return table.concat(texts, " / ")
end

-- True if a tooltip already has our coefficient line.
local function HasCoefficientLine(tooltip, name)
    for i = 1, tooltip:NumLines() do
        local line = _G[name .. "TextLeft" .. i]
        local text = line and line:GetText()
        if text and not issecret(text) and text:find(COEFFICIENT_PREFIX, 1, true) then return true end
    end
    return false
end

-- Settings; replaced by the saved variables on ADDON_LOADED. Each part of the annotation has an
-- on/off key and a <part>ShiftOnly key that shows it only while Shift is held.
local PARTS = { "efficiency", "dps", "coefficients", "notes" }
local DEFAULTS = {
    efficiency = true, efficiencyShiftOnly = false,
    dps = true, dpsShiftOnly = false,
    coefficients = true, coefficientsShiftOnly = true,
    notes = true, notesShiftOnly = true,
}
ns.db = {}
for k, v in pairs(DEFAULTS) do ns.db[k] = v end

-- True if a part is on, and Shift is held when it's Shift-only.
local function Shown(part)
    return ns.db[part] and (not ns.db[part .. "ShiftOnly"] or IsShiftKeyDown())
end

local function AnyShiftOnly()
    for _, part in ipairs(PARTS) do
        if ns.db[part] and ns.db[part .. "ShiftOnly"] then return true end
    end
    return false
end

-- GameTooltip while it shows a spell and some part is Shift-only, so a Shift press can redraw it
-- (RefreshForShift); cleared whenever the tooltip is.
local shiftTooltip

-- Shown instead of the notes until Shift is held.
local SHIFT_HINT = "Hold Shift for additional info"

local function AppendNotes(notes, more)
    for _, note in ipairs(more or {}) do
        notes[#notes + 1] = note
    end
end

local STAT_INTELLECT = 4 -- UnitStat index

-- Description wordings that scale with a player stat, and the stat's current value: "spell damage
-- equal to 5% of your maximum mana" (Arcane Wrath), "you gain 15% of your intellect as spell damage"
-- (Arcane Blast). Patterns match the tooltip's own capitalisation.
local STAT_SCALINGS = {
    { pattern = "(%d+%.?%d*)%%( of your maximum [Mm]ana)",
        read = function() return UnitPowerMax("player", POWER.Mana or 0) end },
    { pattern = "(%d+%.?%d*)%%( of your [Ii]ntellect)",
        read = function() local _, intellect = UnitStat("player", STAT_INTELLECT); return intellect end },
}

-- Inserts what each STAT_SCALINGS percentage is worth right now, after the percentage:
-- "equal to 5% (612) of your maximum Mana". Returns true if a line changed. Runs after the tooltip
-- was read, and IsAnnotated stops a second pass, so the inserted number is never parsed as damage.
local function AddStatValues(tooltip, name)
    local changed = false
    for i = 2, tooltip:NumLines() do
        local line = _G[name .. "TextLeft" .. i]
        local text = line and line:GetText()
        if text and not issecret(text) then
            local new = text
            for _, scaling in ipairs(STAT_SCALINGS) do
                new = new:gsub(scaling.pattern, function(percent, rest)
                    local ok, stat = pcall(scaling.read)
                    if not (ok and type(stat) == "number" and stat > 0) then return nil end
                    return format("%s%%|c%s (%d)|r%s", percent, STAT_VALUE_COLOR,
                        math.floor(stat * ToNum(percent) / 100 + 0.5), rest)
                end)
            end
            if new ~= text then
                line:SetText(new)
                changed = true
            end
        end
    end
    return changed
end

local function Process(tooltip, spellID)
    if not tooltip or (tooltip.IsForbidden and tooltip:IsForbidden()) then return end
    local name = tooltip:GetName()
    if not name or not TOOLTIPS[name] then return end

    local changed = false
    -- Only filled when a suffix is added, so a second pass bails on that suffix before reaching
    -- the note lines (IsAnnotated).
    local notes = {}
    local costLine, resource, cost, lines, cast = ReadSpellTooltip(tooltip)
    if lines then
        local titleLine = _G[name .. "TextLeft1"]
        local spellName = titleLine and titleLine:GetText()
        if spellName and issecret(spellName) then spellName = nil end
        ns.lastSpell = { name = spellName, id = spellID, lines = lines, cast = cast }
        spellName = spellName and Normalize(spellName)

        if Shown("efficiency") and costLine then
            cost = cost or GetCostFromAPI(spellID, resource)
            if cost and cost > 0 then
                local suffix, suffixNotes = GetSuffix(lines, cost, resource, spellName)
                if suffix then
                    costLine:SetText(costLine:GetText() .. suffix)
                    AppendNotes(notes, suffixNotes)
                    changed = true
                end
            end
        end
        if Shown("dps") and cast then
            if not cast.cooldown then cast.cooldown = GetCooldownFromAPI(spellID) end
            local suffix, suffixNotes = GetDPSSuffix(lines, cast, resource, spellName)
            if suffix then
                cast.line:SetText(cast.line:GetText() .. suffix)
                AppendNotes(notes, suffixNotes)
                changed = true
            end
        end
    end

    -- Notes explain calculations that aren't obvious (Heroic Strike's forgone rage). In Shift-only
    -- mode GameTooltip shows a hint until Shift is held; ItemRefTooltip isn't redrawn on Shift, so
    -- it always shows them.
    if ns.db.notes and #notes > 0 then
        if not ns.db.notesShiftOnly or IsShiftKeyDown() or tooltip ~= GameTooltip then
            for _, note in ipairs(notes) do
                tooltip:AddLine(note, 0.8, 0.8, 0.8, true)
            end
        else
            tooltip:AddLine(SHIFT_HINT, 0.5, 0.5, 0.5)
        end
        changed = true
    end

    -- The coefficient gets its own line at the bottom, below everything else.
    local coefficients = ns.db.coefficients and FormatCoefficients(spellID)
    if coefficients and Shown("coefficients") and not HasCoefficientLine(tooltip, name) then
        tooltip:AddLine(format("%s |cffffffff%s|r", COEFFICIENT_PREFIX, coefficients), 0.5, 0.78, 1)
        changed = true
    end

    if tooltip == GameTooltip and (lines or coefficients) and AnyShiftOnly() then shiftTooltip = tooltip end

    if AddStatValues(tooltip, name) then changed = true end

    if changed and tooltip:IsShown() then
        tooltip:Show() -- resize to fit the longer lines
    end
end

-- Pressing or releasing Shift doesn't redraw a tooltip, so redraw it the way its owner does:
-- Blizzard buttons through UpdateTooltip, other frames through OnEnter.
local function RefreshForShift()
    if not (shiftTooltip and shiftTooltip:IsShown()) then return end
    local owner = shiftTooltip:GetOwner()
    local refresh = owner and (owner.UpdateTooltip or owner:GetScript("OnEnter"))
    if refresh then refresh(owner) end
end

-- For an action slot holding a macro, returns true and the spell its #showtooltip shows (nil if
-- unknown). Depending on the API Forever has (unconfirmed), GetActionInfo gives that spell directly
-- ("macro", spellID, "spell") or it comes from GetMacroSpell (spell ID, or name, rank, spellID).
local function GetMacroAction(slot)
    if not GetActionInfo then return false end
    local ok, isMacro, spellID = pcall(function()
        local actionType, id, subType = GetActionInfo(slot)
        if actionType ~= "macro" then return false end
        if subType == "spell" then return true, id end
        if GetMacroSpell and id then
            local first, _, third = GetMacroSpell(id)
            return true, (type(first) == "number" and first) or (type(third) == "number" and third) or nil
        end
        return true, nil
    end)
    return ok and isMacro, spellID
end

if not SUPPORTED_LOCALES[GetLocale()] then
    -- Leave tooltips alone rather than show wrong numbers.
elseif TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tooltip, data)
        Process(tooltip, data and data.id)
    end)
else
    GameTooltip:HookScript("OnTooltipSetSpell", function(self)
        local _, spellID = self:GetSpell()
        Process(self, spellID)
    end)
end

-- Macros with #showtooltip show the spell's tooltip, but through SetAction, which neither hook
-- above is guaranteed to see. Processing twice is harmless: IsAnnotated stops the second pass.
if SUPPORTED_LOCALES[GetLocale()] and hooksecurefunc and GameTooltip.SetAction then
    hooksecurefunc(GameTooltip, "SetAction", function(self, slot)
        local isMacro, spellID = GetMacroAction(slot)
        if isMacro then Process(self, spellID) end
    end)
end

if SUPPORTED_LOCALES[GetLocale()] then
    GameTooltip:HookScript("OnTooltipCleared", function() shiftTooltip = nil end)
end

ns.Analyze = Analyze
ns.ComputeRatios = ComputeRatios
ns.ComputeDPS = ComputeDPS
ns.ReadSpellTooltip = ReadSpellTooltip
ns.GetCostFromAPI = GetCostFromAPI
ns.Normalize = Normalize
ns.FormatRatio = FormatRatio
ns.ORDER, ns.LABELS, ns.COLORS, ns.RESOURCES = ORDER, LABELS, COLORS, RESOURCES
ns.supported = SUPPORTED_LOCALES[GetLocale()] or false

local PREFIX = "|cff80c8ffResource Efficiency Tooltips|r"

local function PrintHelp()
    print(PREFIX .. " commands:")
    print("  /ret report - open or close the spellbook efficiency report")
    print("  /ret config - choose what the tooltips show")
    print("  /ret debug - print the parsed text of the last spell you hovered")
    print("  /ret help - show this list")
end

-- /ret: opens the settings window and lists the commands.
-- /ret report: opens the spellbook efficiency report.
-- /ret config: opens the settings window.
-- /ret help: lists the commands.
-- /ret debug: prints the text of the last annotated spell tooltip, for debugging the parser.
SLASH_RESOURCEEFFICIENCYTOOLTIPS1 = "/ret"
SlashCmdList.RESOURCEEFFICIENCYTOOLTIPS = function(msg)
    local command = (msg or ""):lower():match("^%s*(%S*)")
    if command == "help" then
        PrintHelp()
        return
    end
    if command == "" then
        PrintHelp()
        ns.ToggleConfig()
        return
    end
    if command == "report" then
        ns.ToggleReport()
        return
    end
    if command == "config" then
        ns.ToggleConfig()
        return
    end
    if command ~= "debug" then
        ns.ToggleConfig()
        return
    end
    local last = ns.lastSpell
    if not last then
        print(PREFIX .. ": hover a spell with a cost or cast time first.")
        return
    end
    print(format("%s: %s (%s)", PREFIX, tostring(last.name), tostring(last.id)))
    local cast = last.cast
    if cast then
        print(format("  cast: %s, %s sec, cooldown %s", cast.kind, tostring(cast.seconds), tostring(cast.cooldown)))
    end
    print("  coefficient: " .. (FormatCoefficients(last.id) or "none"))
    for i, line in ipairs(last.lines) do
        print(format("  %d: %s", i, line))
    end
end

-- Loads the saved settings, prints a startup line with the version from the .toc on login, and
-- redraws the tooltip when Shift is pressed or released.
local GetMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("ADDON_LOADED")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:RegisterEvent("MODIFIER_STATE_CHANGED")
loginFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "MODIFIER_STATE_CHANGED" then
        if arg1 == "LSHIFT" or arg1 == "RSHIFT" then RefreshForShift() end
        return
    end
    if event == "ADDON_LOADED" then
        local loadedName = arg1
        if loadedName ~= addonName then return end
        self:UnregisterEvent("ADDON_LOADED")
        if type(ResourceEfficiencyTooltipsDB) ~= "table" then ResourceEfficiencyTooltipsDB = {} end
        for k, v in pairs(DEFAULTS) do
            if ResourceEfficiencyTooltipsDB[k] == nil then ResourceEfficiencyTooltipsDB[k] = v end
        end
        ns.db = ResourceEfficiencyTooltipsDB
        return
    end
    self:UnregisterEvent("PLAYER_LOGIN")
    local version = GetMetadata and GetMetadata(addonName, "Version")
    print(format("%s%s loaded. Type /ret help for commands.", PREFIX, version and (" v" .. version) or ""))
end)
