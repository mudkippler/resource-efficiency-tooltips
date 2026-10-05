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

-- Average weapon swing damage (including attack power) and attack power, used for abilities
-- that deal weapon damage. These change with gear, buffs and forms.
local function ReadCombatStats()
    local stats = {}
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
-- Returns multiplier, isPerTick (true when ticks were found but no duration).
local function TickMultiplier(clause, rest, lasts, shotInterval)
    if rest:find("over%s+%d") then return 1, false end -- already a total
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
    return math.max(1, math.floor(duration / interval + 0.5)), false
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
-- Returns isWeaponStrike, damage (nil when the needed stat isn't available).
local function WeaponAmount(clause, stats, isNextSwingSpell)
    local apPercent = clause:match("(%d+%.?%d*)%% of your attack power")
    if apPercent then
        return true, stats.ap and stats.ap * ToNum(apPercent) / 100
    end
    local percent = clause:match("(%d+%.?%d*)%% weapon damage") or clause:match("(%d+%.?%d*)%% normal damage")
        or clause:match("(%d+%.?%d*)%% damage plus")
    local bonus = clause:match("weapon damage plus (%d+%.?%d*)") or clause:match("normal damage plus (%d+%.?%d*)")
        or clause:match("%% damage plus (%d+%.?%d*)") or clause:match("(%d+%.?%d*) damage in addition to")
        or clause:match("(%d+%.?%d*) additional damage") or clause:match("ranged damage by (%d+%.?%d*)")
    local nextSwingBonus = clause:match("melee damage by (%d+%.?%d*)") or clause:match("next attack by (%d+%.?%d*)")
    if nextSwingBonus then
        return true, ToNum(nextSwingBonus)
    end
    if not (percent or bonus or clause:find("weapon damage") or clause:find("normal damage")) then
        return false
    end
    if isNextSwingSpell then
        return true, bonus and ToNum(bonus) or nil
    end
    local weapon = clause:find("ranged") and stats.ranged or stats.melee
    if not weapon then return true, nil end
    return true, weapon * (percent and ToNum(percent) / 100 or 1) + (bonus and ToNum(bonus) or 0)
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
--   direct[kind], directAoe[kind]: only what lands on impact (no over-time effects, charges or
--     summons), used for DPS;
--   absorbDrain: mana per point absorbed, or nil;
--   comboPoints: the combo points a finisher was rated at, or nil;
--   duration: seconds from "over N sec", "for N sec" or "lasts N sec" (a channel's length), or nil.
local function Analyze(lines, spellName, stats)
    local totals, perTick, aoe, direct, directAoe = {}, {}, {}, {}, {}
    local result = { totals = totals, perTick = perTick, aoe = aoe, direct = direct, directAoe = directAoe }
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
            local function add(value, mult, tick, overTime)
                totals[kind] = (totals[kind] or 0) + value * mult * charges
                perTick[kind] = perTick[kind] or tick
                aoe[kind] = aoe[kind] or sentenceIsAoE
                if not (overTime or tick or mult > 1 or charges > 1) then
                    direct[kind] = (direct[kind] or 0) + value
                    directAoe[kind] = directAoe[kind] or sentenceIsAoE
                end
            end
            for clause in clauses:gmatch("[^\2]+") do
                -- Checked before ClauseKind, which would reject Heroic Strike's "increases melee damage".
                local isWeaponStrike, weaponDamage = WeaponAmount(clause, stats, isNextSwingSpell)
                local clauseKind = ClauseKind(clause)
                if isWeaponStrike and not IsConversion(clause) then
                    kind = "damage"
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
                            local mult, tick = TickMultiplier(clause, rest, lasts, shotInterval)
                            add(value, mult, tick, IsOverTime(clause))
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
-- be calculated. stats defaults to the player's current GetCombatStats().
local function ComputeRatios(lines, cost, spellName, stats)
    local a = Analyze(lines, spellName, stats or GetCombatStats())
    local ratios = {}
    for _, kind in ipairs(ORDER) do
        local total = a.totals[kind]
        if total and total > 0 then
            -- Shields that drain mana as they absorb (Mana Shield) cost the cast plus the drain.
            local totalCost = cost
            if kind == "absorb" and a.absorbDrain then
                totalCost = cost + total * a.absorbDrain
            end
            ratios[#ratios + 1] = { kind = kind, ratio = total / totalCost, perTick = a.perTick[kind],
                aoe = a.aoe[kind], comboPoints = a.comboPoints }
        end
    end
    return ratios
end

-- Global cooldown in seconds: energy users (Rogues, cat form) have a 1 sec GCD.
local function GlobalCooldown(resource)
    return (resource and resource.key == "energy") and 1 or 1.5
end

-- Damage per second of casting a spell back to back. Only for spells that can be: no cooldown,
-- not a next-swing ability, not a combo point finisher. A cast takes its cast time, but never
-- less than the global cooldown (so instants use the GCD). Normal casts count only the damage
-- that lands on impact, because recasting doesn't stack a damage-over-time effect; channels count
-- everything they do over the channel.
-- cast: from ReadSpellTooltip; resource: the cost's resource (sets the GCD), may be nil.
-- Returns { dps, aoe } or nil.
local function ComputeDPS(lines, cast, spellName, stats, resource)
    if not cast or cast.kind == "nextswing" or (cast.cooldown and cast.cooldown > 0) then return nil end
    local a = Analyze(lines, spellName, stats or GetCombatStats())
    if a.comboPoints then return nil end
    local damage, isAoE, seconds
    if cast.kind == "channeled" then
        if a.perTick.damage then return nil end
        damage, isAoE, seconds = a.totals.damage, a.aoe.damage, a.duration
    else
        damage, isAoE, seconds = a.direct.damage, a.directAoe.damage, cast.seconds or 0
    end
    if not (damage and damage > 0 and seconds) then return nil end
    return { dps = damage / math.max(seconds, GlobalCooldown(resource)), aoe = isAoE }
end

local function BuildSuffix(lines, cost, resource, spellName, stats)
    local parts = {}
    for _, r in ipairs(ComputeRatios(lines, cost, spellName, stats)) do
        parts[#parts + 1] = format("|c%s%s %s/%s%s%s%s|r", COLORS[r.kind], FormatRatio(r.ratio),
            LABELS[r.kind], resource.key, r.comboPoints and format(" at %d CP", r.comboPoints) or "",
            r.perTick and " per tick" or "", r.aoe and " per target" or "")
    end
    if #parts == 0 then return false end
    return "  (" .. table.concat(parts, ", ") .. ")"
end

local function StatsKey(stats)
    return format("%.1f|%.1f|%.1f", stats.melee or 0, stats.ranged or 0, stats.ap or 0)
end

local function GetSuffix(lines, cost, resource, spellName)
    local stats = GetCombatStats()
    local key = format("ratio|%s|%s|%s|%s|%s", cost, resource.key, spellName or "", StatsKey(stats),
        table.concat(lines, "|"))
    return Cached(key, function() return BuildSuffix(lines, cost, resource, spellName, stats) end)
end

-- Suffix for the cast time line, e.g. "  (52.3 dps)", or false.
local function GetDPSSuffix(lines, cast, resource, spellName)
    local stats = GetCombatStats()
    local key = format("dps|%s|%s|%s|%s|%s|%s|%s", cast.kind, cast.seconds or "", cast.cooldown or 0,
        resource and resource.key or "", spellName or "", StatsKey(stats), table.concat(lines, "|"))
    return Cached(key, function()
        local r = ComputeDPS(lines, cast, spellName, stats, resource)
        if not r then return false end
        return format("  (|c%s%s dps%s|r)", COLORS.damage, FormatRatio(r.dps), r.aoe and " per target" or "")
    end)
end

-- True if a line already carries one of our suffixes ("dmg/rage", "52.3 dps").
local function IsAnnotated(text)
    if text:find("%d dps") then return true end
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

-- Settings; replaced by the saved variables on ADDON_LOADED.
local DEFAULTS = { efficiency = true, dps = true }
ns.db = {}
for k, v in pairs(DEFAULTS) do ns.db[k] = v end

local function Process(tooltip, spellID)
    if not tooltip or (tooltip.IsForbidden and tooltip:IsForbidden()) then return end
    local name = tooltip:GetName()
    if not name or not TOOLTIPS[name] then return end

    local costLine, resource, cost, lines, cast = ReadSpellTooltip(tooltip)
    if not lines then return end

    local titleLine = _G[name .. "TextLeft1"]
    local spellName = titleLine and titleLine:GetText()
    if spellName and issecret(spellName) then spellName = nil end
    ns.lastSpell = { name = spellName, id = spellID, lines = lines, cast = cast }
    spellName = spellName and Normalize(spellName)

    local changed = false
    if ns.db.efficiency and costLine then
        cost = cost or GetCostFromAPI(spellID, resource)
        local suffix = cost and cost > 0 and GetSuffix(lines, cost, resource, spellName)
        if suffix then
            costLine:SetText(costLine:GetText() .. suffix)
            changed = true
        end
    end
    if ns.db.dps and cast then
        if not cast.cooldown then cast.cooldown = GetCooldownFromAPI(spellID) end
        local suffix = GetDPSSuffix(lines, cast, resource, spellName)
        if suffix then
            cast.line:SetText(cast.line:GetText() .. suffix)
            changed = true
        end
    end
    if changed and tooltip:IsShown() then
        tooltip:Show() -- resize to fit the longer lines
    end
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

-- /ret: opens the spellbook efficiency report.
-- /ret config: opens the settings window.
-- /ret help: lists the commands.
-- /ret debug: prints the text of the last annotated spell tooltip, for debugging the parser.
SLASH_RESOURCEEFFICIENCYTOOLTIPS1 = "/ret"
SlashCmdList.RESOURCEEFFICIENCYTOOLTIPS = function(msg)
    local command = (msg or ""):lower():match("^%s*(%S*)")
    if command == "help" then
        print(PREFIX .. " commands:")
        print("  /ret - open or close the spellbook efficiency report")
        print("  /ret config - choose what the tooltips show")
        print("  /ret debug - print the parsed text of the last spell you hovered")
        print("  /ret help - show this list")
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
    for i, line in ipairs(last.lines) do
        print(format("  %d: %s", i, line))
    end
end

-- Loads the saved settings, then prints a startup line with the version from the .toc on login.
local GetMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("ADDON_LOADED")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self, event, loadedName)
    if event == "ADDON_LOADED" then
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
