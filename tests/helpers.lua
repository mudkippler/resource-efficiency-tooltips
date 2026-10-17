-- Resource Efficiency Tooltips: shared test helpers
-- Stubs the WoW API the addon touches, fakes GameTooltip, loads the addon and counts results.
-- Each suite runs in its own interpreter (see run.lua), so the stubs are plain globals.
-- Load with: local T = dofile((arg[0]:match("^(.*)[/\\]") or ".") .. "/helpers.lua")

local T = { passes = 0, fails = 0 }
T.root = ((arg and arg[0] or ""):match("^(.*)[/\\]") or ".") .. "/.."

---------------------------------------------------------------------------
-- State the stubs read; suites change these between cases
---------------------------------------------------------------------------

T.shift = false        -- IsShiftKeyDown()
T.class = "MAGE"       -- UnitClass() class file; "WARRIOR" and "DRUID" get forgone swing rage
T.weapon = nil         -- main hand: { link = "...", lines = { { left, right }, ... } } as its tooltip shows
T.scans = 0            -- main-hand tooltip reads, to test the per-link cache
T.owner = nil          -- GameTooltip:GetOwner(), e.g. { UpdateTooltip = function() ... end }
T.actions = {}         -- action slot -> GetActionInfo() returns, e.g. { "macro", 7 }
T.macroSpells = {}     -- macro index -> GetMacroSpell() returns
T.events = {}          -- events the addon's frame registered
T.hooks = {}           -- hooksecurefunc(GameTooltip, name, f) -> T.hooks[name] = f
-- T.onEvent, T.postCall: the addon's OnEvent handler and TooltipDataProcessor post-call

---------------------------------------------------------------------------
-- WoW API stubs
---------------------------------------------------------------------------

MANA, RAGE, ENERGY = "Mana", "Rage", "Energy"
MANA_COST, RAGE_COST, ENERGY_COST = "%d Mana", "%d Rage", "%d Energy"
SlashCmdList = {}
WorldFrame = {}
Enum = { TooltipDataType = { Spell = 1 } }
TooltipDataProcessor = { AddTooltipPostCall = function(_, f) T.postCall = f end }

function GetLocale() return "enUS" end
function UnitDamage() return 90, 110 end            -- melee average 100
function UnitRangedDamage() return 3, 80, 120 end    -- ranged average 100
function UnitAttackPower() return 1000, 0, 0 end
function UnitClass() return T.class, T.class end
function IsShiftKeyDown() return T.shift end
function GetInventoryItemLink() return T.weapon and T.weapon.link end
function GetActionInfo(slot) return unpack(T.actions[slot] or {}) end
function GetMacroSpell(index) return unpack(T.macroSpells[index] or {}) end
function hooksecurefunc(_, name, f) T.hooks[name] = f end

local function FontString(text)
    return { t = text, GetText = function(s) return s.t end, SetText = function(s, v) s.t = v end,
        IsShown = function(s) return s.t ~= nil end }
end

-- Sets <name>TextLeftN / TextRightN like a real tooltip; rows are { left, right } or plain left text.
local function FillLines(name, rows)
    for i = 1, 30 do
        _G[name .. "TextLeft" .. i], _G[name .. "TextRight" .. i] = nil, nil
    end
    for i, row in ipairs(rows) do
        local left, right = row, nil
        if type(row) == "table" then left, right = row[1], row[2] end
        _G[name .. "TextLeft" .. i], _G[name .. "TextRight" .. i] = FontString(left), FontString(right)
    end
end

-- CreateFrame("Frame") records events and the OnEvent handler; CreateFrame("GameTooltip", name)
-- is the hidden item scanner, which shows T.weapon.
function CreateFrame(kind, name)
    if kind == "GameTooltip" then
        local rows = {}
        return {
            SetOwner = function() end,
            Hide = function() end,
            NumLines = function() return #rows end,
            SetInventoryItem = function()
                T.scans = T.scans + 1
                rows = T.weapon and T.weapon.lines or {}
                FillLines(name, rows)
            end,
        }
    end
    return {
        RegisterEvent = function(_, event) T.events[event] = true end,
        UnregisterEvent = function() end,
        SetScript = function(_, _, f) T.onEvent = f end,
    }
end

---------------------------------------------------------------------------
-- Fake GameTooltip
---------------------------------------------------------------------------

local tipRows, tipScripts = {}, {}
GameTooltip = {
    GetName = function() return "GameTooltip" end,
    NumLines = function() return #tipRows end,
    IsShown = function() return true end,
    Show = function() end,
    SetAction = function() end,
    GetOwner = function() return T.owner end,
    HookScript = function(_, script, f) tipScripts[script] = f end,
    AddLine = function(_, text)
        tipRows[#tipRows + 1] = text
        _G["GameTooltipTextLeft" .. #tipRows] = FontString(text)
    end,
}

-- Replaces GameTooltip's lines like a real Set* call does (OnTooltipCleared first).
function T.setTip(rows)
    if tipScripts.OnTooltipCleared then tipScripts.OnTooltipCleared() end
    tipRows = {}
    for i, row in ipairs(rows) do tipRows[i] = row end
    FillLines("GameTooltip", rows)
end

-- GameTooltip's left lines joined with " | ".
function T.dump()
    local out = {}
    for i = 1, #tipRows do out[i] = _G["GameTooltipTextLeft" .. i]:GetText() end
    return table.concat(out, " | ")
end

-- Shows a spell in GameTooltip through the TooltipDataProcessor post-call and returns T.dump().
function T.show(rows, spellID)
    T.setTip(rows)
    T.postCall(GameTooltip, { id = spellID })
    return T.dump()
end

-- A named tooltip for ns.ReadSpellTooltip, with left and right line texts.
function T.fakeTip(left, right)
    local rows = {}
    for i, text in ipairs(left) do rows[i] = { text, right[i] } end
    FillLines("FakeTip", rows)
    return { GetName = function() return "FakeTip" end, NumLines = function() return #left end }
end

---------------------------------------------------------------------------
-- Addon
---------------------------------------------------------------------------

-- Loads the main file and the coefficient data into a fresh namespace and returns it.
function T.loadAddon()
    local ns = {}
    for _, file in ipairs({ "ResourceEfficiencyTooltips.lua", "SpellCoefficients.lua" }) do
        assert(loadfile(T.root .. "/ResourceEfficiencyTooltips/" .. file))("ResourceEfficiencyTooltips", ns)
    end
    T.ns = ns
    return ns
end

function T.resource(key)
    for _, res in ipairs(T.ns.RESOURCES) do
        if res.key == key then return res end
    end
end

---------------------------------------------------------------------------
-- Results
---------------------------------------------------------------------------

local function Report(ok, label, detail)
    if ok then
        T.passes = T.passes + 1
    else
        T.fails = T.fails + 1
        print("FAIL " .. label .. "\n     " .. detail)
    end
end

-- Passes when got == want.
function T.check(label, got, want)
    Report(got == want, label, "got " .. tostring(got) .. ", want " .. tostring(want))
end

-- Passes when text contains find (if given) and not missing (if given), as plain text.
function T.has(label, text, find, missing)
    local ok = (not find or text:find(find, 1, true)) and not (missing and text:find(missing, 1, true))
    Report(ok and true or false, label, "in: " .. text .. (find and ("\n     want: " .. find) or "")
        .. (missing and ("\n     not: " .. missing) or ""))
end

-- Prints the totals and exits with 1 if anything failed.
function T.finish()
    print(string.format("%d passed, %d failed", T.passes, T.fails))
    os.exit(T.fails > 0 and 1 or 0)
end

return T
