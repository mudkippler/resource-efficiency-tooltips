-- Resource Efficiency Tooltips
-- Appends damage / healing / absorb per point of mana, rage or energy to the cost line of spell tooltips.
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

-- lines: normalized (lowercase) tooltip lines; spellName: lowercase spell name, if known;
-- stats: GetCombatStats() for weapon-based abilities.
-- Returns totals[kind], perTick[kind], aoe[kind], absorbDrain (mana per point absorbed, or nil),
-- comboPoints (the combo points a finisher was rated at, or nil).
local function Analyze(lines, spellName, stats)
    local totals, perTick, aoe = {}, {}, {}
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
        return totals, perTick, aoe, nil
    end
    local lasts = ParseDuration(fullText, "lasts")
    local charges = ParseCharges(fullText)
    local shotInterval = spellName and SHOT_INTERVALS[spellName]
    local isNextSwingSpell = spellName and NEXT_SWING_SPELLS[spellName]
    for _, line in ipairs(lines) do
        local sentences = line:gsub("%.%s+", "\1")
        for sentence in sentences:gmatch("[^\1]+") do
            local kind
            local sentenceIsAoE = IsAoE(sentence)
            local clauses = sentence:gsub("%s+and%s+", "\2"):gsub(";", "\2")
            local function add(value, mult, tick)
                totals[kind] = (totals[kind] or 0) + value * mult * charges
                perTick[kind] = perTick[kind] or tick
                aoe[kind] = aoe[kind] or sentenceIsAoE
            end
            for clause in clauses:gmatch("[^\2]+") do
                -- Checked before ClauseKind, which would reject Heroic Strike's "increases melee damage".
                local isWeaponStrike, weaponDamage = WeaponAmount(clause, stats, isNextSwingSpell)
                local clauseKind = ClauseKind(clause)
                if isWeaponStrike and not IsConversion(clause) then
                    kind = "damage"
                    if weaponDamage and weaponDamage > 0 then
                        add(weaponDamage, 1, false)
                    end
                elseif clauseKind == false then
                    kind = nil
                else
                    kind = clauseKind or kind
                    if kind then
                        local value, rest = FindAmount(clause)
                        if value and value > 0 then
                            add(value, TickMultiplier(clause, rest, lasts, shotInterval))
                        end
                    end
                end
            end
        end
    end
    return totals, perTick, aoe, ParseAbsorbDrain(fullText), comboPoints
end

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------

local function FormatRatio(ratio)
    if ratio >= 10 then return format("%.1f", ratio) end
    return format("%.2f", ratio)
end

-- Action button tooltips refresh several times a second; cache the suffix per tooltip text.
local cache = {}
local cacheKeys = {}
local CACHE_SIZE = 200

-- Returns a list of { kind, ratio, perTick, aoe, comboPoints } in ORDER, empty if nothing could
-- be calculated. stats defaults to the player's current GetCombatStats().
local function ComputeRatios(lines, cost, spellName, stats)
    local totals, perTick, aoe, absorbDrain, comboPoints = Analyze(lines, spellName, stats or GetCombatStats())
    local ratios = {}
    for _, kind in ipairs(ORDER) do
        local total = totals[kind]
        if total and total > 0 then
            -- Shields that drain mana as they absorb (Mana Shield) cost the cast plus the drain.
            local totalCost = cost
            if kind == "absorb" and absorbDrain then
                totalCost = cost + total * absorbDrain
            end
            ratios[#ratios + 1] = { kind = kind, ratio = total / totalCost, perTick = perTick[kind],
                aoe = aoe[kind], comboPoints = comboPoints }
        end
    end
    return ratios
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

local function GetSuffix(lines, cost, resource, spellName)
    local stats = GetCombatStats()
    local key = format("%s|%s|%s|%.1f|%.1f|%.1f|%s", cost, resource.key, spellName or "", stats.melee or 0,
        stats.ranged or 0, stats.ap or 0, table.concat(lines, "|"))
    local suffix = cacheKeys[key]
    if suffix == nil then
        suffix = BuildSuffix(lines, cost, resource, spellName, stats)
        if #cache >= CACHE_SIZE then
            cacheKeys[table.remove(cache, 1)] = nil
        end
        cache[#cache + 1] = key
        cacheKeys[key] = suffix
    end
    return suffix
end

-- True if a line already carries our suffix ("dmg/rage").
local function IsAnnotated(text)
    for _, res in ipairs(RESOURCES) do
        for _, label in pairs(LABELS) do
            if text:find(label .. "/" .. res.key, 1, true) then return true end
        end
    end
    return false
end

-- Reads a named spell tooltip. Returns the cost font string, the resource, the cost (nil for
-- percentage costs) and the normalized description lines; returns nothing if there's no mana,
-- rage or energy cost or the tooltip is already annotated.
local function ReadSpellTooltip(tooltip)
    local name = tooltip:GetName()
    local costLine, resource, cost
    local lines = {}
    for i = 2, tooltip:NumLines() do
        local fontString = _G[name .. "TextLeft" .. i]
        local text = fontString and fontString:GetText()
        if text and not issecret(text) then
            if IsAnnotated(text) then return end
            local lower = Normalize(text)
            if lower:find("^next rank") then break end
            local lineResource, lineCost
            if not costLine and i <= 5 then
                lineResource, lineCost = MatchCost(lower)
            end
            if lineResource then
                costLine, resource, cost = fontString, lineResource, lineCost
            else
                lines[#lines + 1] = lower
            end
        end
    end
    if not costLine then return end
    return costLine, resource, cost, lines
end

local function Process(tooltip, spellID)
    if not tooltip or (tooltip.IsForbidden and tooltip:IsForbidden()) then return end
    local name = tooltip:GetName()
    if not name or not TOOLTIPS[name] then return end

    local costLine, resource, cost, lines = ReadSpellTooltip(tooltip)
    if not costLine then return end

    cost = cost or GetCostFromAPI(spellID, resource)
    if not cost or cost <= 0 then return end

    local titleLine = _G[name .. "TextLeft1"]
    local spellName = titleLine and titleLine:GetText()
    if spellName and issecret(spellName) then spellName = nil end
    ns.lastSpell = { name = spellName, id = spellID, lines = lines }
    local suffix = GetSuffix(lines, cost, resource, spellName and Normalize(spellName))
    if not suffix then return end

    costLine:SetText(costLine:GetText() .. suffix)
    if tooltip:IsShown() then
        tooltip:Show() -- resize to fit the longer line
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
ns.ReadSpellTooltip = ReadSpellTooltip
ns.GetCostFromAPI = GetCostFromAPI
ns.Normalize = Normalize
ns.FormatRatio = FormatRatio
ns.ORDER, ns.LABELS, ns.COLORS, ns.RESOURCES = ORDER, LABELS, COLORS, RESOURCES
ns.supported = SUPPORTED_LOCALES[GetLocale()] or false

local PREFIX = "|cff80c8ffResource Efficiency Tooltips|r"

-- /ret: opens the spellbook efficiency report.
-- /ret help: lists the commands.
-- /ret debug: prints the text of the last annotated spell tooltip, for debugging the parser.
SLASH_RESOURCEEFFICIENCYTOOLTIPS1 = "/ret"
SlashCmdList.RESOURCEEFFICIENCYTOOLTIPS = function(msg)
    local command = (msg or ""):lower():match("^%s*(%S*)")
    if command == "help" then
        print(PREFIX .. " commands:")
        print("  /ret - open or close the spellbook efficiency report")
        print("  /ret debug - print the parsed text of the last spell you hovered")
        print("  /ret help - show this list")
        return
    end
    if command ~= "debug" then
        ns.ToggleReport()
        return
    end
    local last = ns.lastSpell
    if not last then
        print(PREFIX .. ": hover a spell with a mana, rage or energy cost first.")
        return
    end
    print(format("%s: %s (%s)", PREFIX, tostring(last.name), tostring(last.id)))
    for i, line in ipairs(last.lines) do
        print(format("  %d: %s", i, line))
    end
end

-- Startup line with the version from the .toc.
local GetMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    local version = GetMetadata and GetMetadata(addonName, "Version")
    print(format("%s%s loaded. Type /ret help for commands.", PREFIX, version and (" v" .. version) or ""))
end)
