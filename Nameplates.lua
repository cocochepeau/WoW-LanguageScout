local _, ns = ...

local FLAG_TEXTURE_PREFIX = "Interface\\AddOns\\LanguageScout\\flags\\"
local flags = setmetatable({}, { __mode = "k" })
local flagUnits = setmetatable({}, { __mode = "k" })
local trackedUnits, activeFlags = {}, {}
local frame = CreateFrame("Frame")
local elapsedSinceUpdate = 0

local function IsAccessible(object)
    if ns.IsSecret(object) or not object then return false end
    return not (object.IsForbidden and object:IsForbidden())
end

local function HideFlag(flag)
    if IsAccessible(flag) then flag:Hide() end
end

local function ClearUnit(unit)
    local flag = activeFlags[unit]
    if flag and flagUnits[flag] == unit then
        HideFlag(flag)
        flagUnits[flag] = nil
    end
    activeFlags[unit] = nil
end

local function ResolveNameplateRegions(plate)
    -- Plater v663 uses a lowercase unitFrame and switches CurrentUnitNameString
    -- between the regular health-bar label and ActorNameSpecial in name-only mode.
    local platerFrame = plate.unitFrame
    if ns.IsSecret(platerFrame) then return end
    if platerFrame then
        if not IsAccessible(platerFrame) then return end
        local active = platerFrame.PlaterOnScreen
        if ns.IsSecret(active) then return end
        if active then
            local name = plate.CurrentUnitNameString
            if ns.IsSecret(name) then return end
            if not name then
                local healthBar = platerFrame.healthBar
                if ns.IsSecret(healthBar) then return end
                if healthBar then
                    if not IsAccessible(healthBar) then return end
                    name = healthBar.unitName
                end
                if ns.IsSecret(name) then return end
                if not name then name = platerFrame.unitName end
            end
            return platerFrame, name
        end
    end
    -- Plater can leave selected plate types under Blizzard's control.
    local unitFrame = plate.UnitFrame
    if IsAccessible(unitFrame) then return unitFrame, unitFrame.name end
end

local function UpdateUnit(unit)
    ClearUnit(unit)
    if not ns.CanInspectUnit(unit) or not UnitIsPlayer(unit) then return end
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return end
    -- Never request forbidden plates, even when the client exposes that option.
    local plate = C_NamePlate.GetNamePlateForUnit(unit, false)
    if not IsAccessible(plate) then return end
    local unitFrame, name = ResolveNameplateRegions(plate)
    if not IsAccessible(unitFrame) then return end
    local displayedUnit = unitFrame.unit
    if not ns.IsSecret(displayedUnit) and not displayedUnit then displayedUnit = unitFrame.namePlateUnitToken end
    if ns.IsSecret(displayedUnit) or (displayedUnit and displayedUnit ~= unit) then return end
    if not IsAccessible(name) or not name.IsShown then return end
    local shown = name:IsShown()
    if ns.IsSecret(shown) or not shown then return end
    if name.IsVisible then
        local visible = name:IsVisible()
        if ns.IsSecret(visible) or not visible then return end
    end
    -- Share the label's parent so flags inherit the same visibility and alpha,
    -- including when Plater hides its health bar or uses a special name label.
    local parent = unitFrame
    if name.GetParent then parent = name:GetParent() end
    if not IsAccessible(parent) then return end

    local playerName, realm = ns.ReadUnitName(unit)
    local key = playerName and ns.FullName(playerName, realm)
    local record = key and LanguageScoutDB.players[key]
    local language = type(record) == "table" and record.lang
    if not ns.IsSupportedLanguage(language) then return end

    -- Font strings can be wider than their visible text. Account for alignment
    -- so the flag sits beside the name rather than at the edge of the health bar.
    local width = name.GetWidth and name:GetWidth()
    local textWidth = name.GetStringWidth and name:GetStringWidth()
    local justify = "LEFT"
    if name.GetJustifyH then justify = name:GetJustifyH() end
    if ns.IsSecret(width) or ns.IsSecret(textWidth) or ns.IsSecret(justify) then return end
    if type(width) ~= "number" or type(textWidth) ~= "number" or width <= 0 or textWidth <= 0 then return end
    local unusedWidth = math.max(0, width - textWidth)
    local position = LanguageScoutDB.nameplateFlagPosition
    local offset = 0
    if justify == "CENTER" then
        offset = unusedWidth / 2
    elseif (position == "left" and justify == "RIGHT") or (position == "right" and justify == "LEFT") then
        offset = unusedWidth
    end

    local flag = flags[parent]
    if not flag then
        if not parent.CreateTexture then return end
        flag = parent:CreateTexture(nil, "OVERLAY", nil, 7)
        flags[parent] = flag
        flag:SetSize(18, 12)
    end
    if not IsAccessible(flag) then return end
    flag:ClearAllPoints()
    if position == "left" then
        flag:SetPoint("RIGHT", name, "LEFT", offset - 4, 0)
    else
        flag:SetPoint("LEFT", name, "RIGHT", -offset + 4, 0)
    end
    flag:SetTexture(FLAG_TEXTURE_PREFIX .. language .. ".tga")
    flag:Show()
    flagUnits[flag] = unit
    activeFlags[unit] = flag
end

local function UpdateTrackedUnits()
    for unit in pairs(trackedUnits) do UpdateUnit(unit) end
end

local function OnUpdate(_, elapsed)
    elapsedSinceUpdate = elapsedSinceUpdate + elapsed
    if elapsedSinceUpdate < 0.2 then return end
    elapsedSinceUpdate = 0
    -- A bounded refresh of visible units handles pooled frames, name visibility,
    -- and saved-language changes without touching Blizzard's name text or scripts.
    UpdateTrackedUnits()
end

ns.RefreshNameplateFlags = function()
    if LanguageScoutDB.nameplateFlagPosition == "off" then
        frame:SetScript("OnUpdate", nil)
        for _, flag in pairs(flags) do HideFlag(flag) end
        wipe(trackedUnits)
        wipe(activeFlags)
        elapsedSinceUpdate = 0
        return
    end
    frame:SetScript("OnUpdate", OnUpdate)
    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
            if IsAccessible(plate) then
                local unit
                if plate.GetUnit then unit = plate:GetUnit() end
                if not ns.IsSecret(unit) then
                    if not unit then unit = plate.namePlateUnitToken end
                    if not ns.IsSecret(unit) and not unit then
                        local platerFrame = plate.unitFrame
                        if IsAccessible(platerFrame) then unit = platerFrame.namePlateUnitToken end
                    end
                    if not ns.IsSecret(unit) and type(unit) == "string" then trackedUnits[unit] = true end
                end
            end
        end
    end
    UpdateTrackedUnits()
end

for _, event in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_NAME_UPDATE",
    "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "ADDON_LOADED", "CVAR_UPDATE" }) do
    frame:RegisterEvent(event)
end
frame:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_REMOVED" then
        if ns.IsSecret(unit) or type(unit) ~= "string" then return end
        trackedUnits[unit] = nil
        ClearUnit(unit)
    elseif event == "NAME_PLATE_UNIT_ADDED" or event == "UNIT_NAME_UPDATE" then
        if LanguageScoutDB.nameplateFlagPosition == "off" or ns.IsSecret(unit) or type(unit) ~= "string" then return end
        if event == "NAME_PLATE_UNIT_ADDED" then trackedUnits[unit] = true end
        if trackedUnits[unit] then UpdateUnit(unit) end
    else
        ns.RefreshNameplateFlags()
    end
end)

ns.RefreshNameplateFlags()
