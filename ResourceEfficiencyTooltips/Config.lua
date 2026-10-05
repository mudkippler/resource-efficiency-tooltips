-- Resource Efficiency Tooltips: settings window
-- Turns each part of the tooltip annotation on or off. Settings live in ns.db (saved variables).

local _, ns = ...

local OPTIONS = {
    { key = "efficiency", label = "Resource efficiency",
        tip = "Damage, healing or absorb per point of mana, rage or energy, on the cost line." },
    { key = "dps", label = "Damage per second",
        tip = "Damage per second of casting the spell back to back, on the cast time line. "
            .. "Only for spells without a cooldown." },
}

local frame
local checks = {}

local function CreateConfigFrame()
    frame = CreateFrame("Frame", "ResourceEfficiencyConfigFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(280, 60 + #OPTIONS * 28 + 20)
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
    title:SetText("Resource Efficiency Tooltips")

    for i, option in ipairs(OPTIONS) do
        local check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        check:SetSize(26, 26)
        check:SetPoint("TOPLEFT", 14, -32 - (i - 1) * 28)
        local label = check.Text or check.text
        if not label then
            label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            label:SetPoint("LEFT", check, "RIGHT", 2, 1)
        end
        label:SetFontObject("GameFontHighlight")
        label:SetText(option.label)
        check:SetScript("OnClick", function(self)
            ns.db[option.key] = self:GetChecked() and true or false
        end)
        check:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(option.label, 1, 1, 1)
            GameTooltip:AddLine(option.tip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        check:SetScript("OnLeave", GameTooltip_Hide or function() GameTooltip:Hide() end)
        check.key = option.key
        checks[i] = check
    end

    local note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("BOTTOMLEFT", 14, 12)
    note:SetPoint("BOTTOMRIGHT", -14, 12)
    note:SetJustifyH("LEFT")
    note:SetText("Changes apply the next time a tooltip is shown.")

    frame:SetScript("OnShow", function()
        for _, check in ipairs(checks) do
            check:SetChecked(ns.db[check.key] and true or false)
        end
    end)
end

function ns.ToggleConfig()
    if not frame then
        CreateConfigFrame()
        frame:GetScript("OnShow")() -- OnShow doesn't fire for a frame that starts shown
        return
    end
    frame:SetShown(not frame:IsShown())
end
