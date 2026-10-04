-- Resource Efficiency Tooltips: spellbook report
-- Lists every spellbook spell (all ranks) whose efficiency can be calculated, best first.

local _, ns = ...

local format = string.format

local ROW_HEIGHT = 20
local ICON_SIZE = 16
local GAP = 8
local PREFIX = "|cff80c8ffResource Efficiency Tooltips:|r "

-- Ratio columns are sortable; clicking one again goes back to sorting by each spell's best ratio.
local COLUMNS = {
    { key = "name", title = "Spell", width = 190, justify = "LEFT" },
    { key = "rank", title = "Rank", width = 64, justify = "LEFT" },
    { key = "cost", title = "Cost", width = 72, justify = "RIGHT" },
    { key = "damage", title = "Dmg / point", width = 110, justify = "RIGHT", sortable = true },
    { key = "heal", title = "Heal / point", width = 110, justify = "RIGHT", sortable = true },
    { key = "absorb", title = "Absorb / point", width = 110, justify = "RIGHT", sortable = true },
}

local CONTENT_WIDTH = 4 + ICON_SIZE + GAP
for _, col in ipairs(COLUMNS) do
    CONTENT_WIDTH = CONTENT_WIDTH + col.width + GAP
end

local frame, content, emptyText, footer
local headers = {}
local rows = {}
local data = {}
local sortKind -- nil = each spell's best ratio

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------

-- Returns { id, name, rank, icon } for every active spell in the player's spellbook.
local function GetSpellbookSpells()
    local spells, seen = {}, {}
    local function add(id, name, rank, icon)
        if id and name and not seen[id] then
            seen[id] = true
            spells[#spells + 1] = { id = id, name = name, rank = rank, icon = icon }
        end
    end

    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookItemInfo
        and Enum and Enum.SpellBookSpellBank and Enum.SpellBookItemType then
        local bank = Enum.SpellBookSpellBank.Player
        for t = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local line = C_SpellBook.GetSpellBookSkillLineInfo(t)
            if line and (line.offSpecID or 0) == 0 and not line.shouldHide then
                for slot = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                    local item = C_SpellBook.GetSpellBookItemInfo(slot, bank)
                    if item and item.itemType == Enum.SpellBookItemType.Spell and not item.isPassive then
                        add(item.spellID, item.name, item.subName, item.iconID)
                    end
                end
            end
        end
    elseif GetNumSpellTabs then
        local bookType = BOOKTYPE_SPELL or "spell"
        for t = 1, GetNumSpellTabs() do
            local _, _, offset, numSlots, _, offSpecID = GetSpellTabInfo(t)
            if (offSpecID or 0) == 0 then
                for slot = offset + 1, offset + numSlots do
                    local spellType, spellID = GetSpellBookItemInfo(slot, bookType)
                    if spellType == "SPELL" and not (IsPassiveSpell and IsPassiveSpell(slot, bookType)) then
                        local name, rank = GetSpellBookItemName(slot, bookType)
                        add(spellID, name, rank, GetSpellBookItemTexture(slot, bookType))
                    end
                end
            end
        end
    end
    return spells
end

local scanner

-- Builds a report row for a spell, or nil if its efficiency can't be calculated.
local function AnalyzeSpell(spell)
    if not scanner then
        scanner = CreateFrame("GameTooltip", "ResourceEfficiencyTooltipsScanner", nil, "GameTooltipTemplate")
    end
    scanner:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanner:SetSpellByID(spell.id)
    local costLine, resource, cost, lines = ns.ReadSpellTooltip(scanner)
    local rank = spell.rank
    if not rank or rank == "" then
        local right = _G[scanner:GetName() .. "TextRight1"]
        rank = right and right:IsShown() and right:GetText() or ""
    end
    scanner:Hide()
    if not costLine then return nil end

    cost = cost or ns.GetCostFromAPI(spell.id, resource)
    if not cost or cost <= 0 then return nil end

    local ratios = ns.ComputeRatios(lines, cost, ns.Normalize(spell.name))
    if #ratios == 0 then return nil end

    local row = { id = spell.id, name = spell.name, rank = rank, icon = spell.icon, cost = cost,
        resource = resource, best = 0 }
    for _, r in ipairs(ratios) do
        row[r.kind] = r
        row.best = math.max(row.best, r.ratio)
    end
    return row
end

local function SortValue(row)
    if sortKind then
        return row[sortKind] and row[sortKind].ratio
    end
    return row.best
end

local function CompareRows(a, b)
    local va, vb = SortValue(a), SortValue(b)
    if va ~= vb then
        if not va then return false end
        if not vb then return true end
        return va > vb
    end
    if a.best ~= b.best then return a.best > b.best end
    if a.name ~= b.name then return a.name < b.name end
    return a.cost < b.cost
end

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------

local function RatioText(r)
    if not r then return "" end
    local text = format("|c%s%s|r", ns.COLORS[r.kind], ns.FormatRatio(r.ratio))
    if r.comboPoints then text = text .. format(" |cff999999%dcp|r", r.comboPoints) end
    if r.aoe then text = text .. " |cff999999/tgt|r" end
    if r.perTick then text = text .. " |cff999999/tick|r" end
    return text
end

local function CreateRow(i)
    local row = CreateFrame("Frame", nil, content)
    row:SetSize(CONTENT_WIDTH, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
    row:EnableMouse(true)

    if i % 2 == 0 then
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 0.04)
    end
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.08)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.icon:SetPoint("LEFT", 4, 0)

    row.cells = {}
    local x = 4 + ICON_SIZE + GAP
    for _, col in ipairs(COLUMNS) do
        local cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cell:SetPoint("LEFT", x, 0)
        cell:SetWidth(col.width)
        cell:SetJustifyH(col.justify)
        cell:SetWordWrap(false)
        row.cells[col.key] = cell
        x = x + col.width + GAP
    end

    -- Hovering a row shows the spell's own (annotated) tooltip.
    row:SetScript("OnEnter", function(self)
        if not self.spellID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(self.spellID)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide or function() GameTooltip:Hide() end)

    rows[i] = row
    return row
end

local function Render()
    table.sort(data, CompareRows)

    for i, entry in ipairs(data) do
        local row = rows[i] or CreateRow(i)
        row.spellID = entry.id
        row.icon:SetTexture(entry.icon)
        row.cells.name:SetText(entry.name)
        row.cells.rank:SetText(entry.rank)
        row.cells.cost:SetText(format("%d |c%s%s|r", entry.cost, entry.resource.color, entry.resource.key))
        for _, kind in ipairs(ns.ORDER) do
            row.cells[kind]:SetText(RatioText(entry[kind]))
        end
        row:Show()
    end
    for i = #data + 1, #rows do
        rows[i]:Hide()
    end
    content:SetHeight(math.max(1, #data * ROW_HEIGHT))

    for key, header in pairs(headers) do
        local active = key == sortKind
        header.text:SetText(header.title .. (active and " v" or ""))
        if active then
            header.text:SetTextColor(1, 1, 1)
        else
            header.text:SetTextColor(1, 0.82, 0)
        end
    end
    emptyText:SetShown(#data == 0)
    footer:SetText(format("%d spells  -  sorted by %s  -  click a column to sort  -  "
        .. "/tgt per target, /tick per tick, 5cp at 5 combo points",
        #data, sortKind and (ns.LABELS[sortKind] .. " per point") or "best ratio"))
end

local function Refresh()
    data = {}
    for _, spell in ipairs(GetSpellbookSpells()) do
        local row = AnalyzeSpell(spell)
        if row then data[#data + 1] = row end
    end
    Render()
end

local function CreateReportFrame()
    frame = CreateFrame("Frame", "ResourceEfficiencyReportFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(CONTENT_WIDTH + 44, 480)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    tinsert(UISpecialFrames, frame:GetName()) -- close with Escape

    local title = frame.TitleText
    if not title then
        title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetPoint("TOP", 0, -5)
    end
    title:SetText("Spellbook Resource Efficiency")

    -- Column headers, aligned with the row cells.
    local x = 12 + 4 + ICON_SIZE + GAP
    for _, col in ipairs(COLUMNS) do
        local header = CreateFrame("Button", nil, frame)
        header:SetSize(col.width, ROW_HEIGHT)
        header:SetPoint("TOPLEFT", x, -30)
        header.title = col.title
        header.text = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        header.text:SetAllPoints()
        header.text:SetJustifyH(col.justify)
        header.text:SetText(col.title)
        if col.sortable then
            header:SetScript("OnClick", function()
                sortKind = (sortKind ~= col.key) and col.key or nil
                Render()
            end)
            header:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            headers[col.key] = header
        end
        x = x + col.width + GAP
    end

    local scroll = CreateFrame("ScrollFrame", "ResourceEfficiencyReportScroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -52)
    scroll:SetPoint("BOTTOMRIGHT", -32, 30)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(CONTENT_WIDTH, 1)
    scroll:SetScrollChild(content)

    emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("CENTER", scroll)
    emptyText:SetText("No spells in your spellbook have an efficiency that can be calculated.")

    footer = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    footer:SetPoint("BOTTOMLEFT", 14, 11)
    footer:SetPoint("BOTTOMRIGHT", -14, 11)
    footer:SetJustifyH("LEFT")
    footer:SetWordWrap(false)

    -- Keep the list current while the window is open: new spells, and weapon damage for
    -- weapon-based abilities (gear and shapeshift forms).
    frame:RegisterEvent("SPELLS_CHANGED")
    frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    frame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    frame:SetScript("OnEvent", function(self)
        if self:IsShown() then Refresh() end
    end)
    frame:SetScript("OnShow", Refresh)
end

function ns.ToggleReport()
    if not ns.supported then
        print(PREFIX .. "the report is only available on English (enUS / enGB) clients.")
        return
    end
    if not frame then
        CreateReportFrame()
        Refresh() -- OnShow doesn't fire for a frame that starts shown
        return
    end
    frame:SetShown(not frame:IsShown())
end
