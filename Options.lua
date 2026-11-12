local _, ns = ...

if not Settings then
    return
end

local L = ns.L
local SUPPORTED_LANGUAGES = ns.SUPPORTED_LANGUAGES
local FullName = ns.FullName
local ParseFullName = ns.ParseFullName
local ParseGuildKey = ns.ParseGuildKey
local GetLanguageDisplayName = ns.GetLanguageDisplayName
local GetPlayerRealm = ns.GetPlayerRealm
local NormalizeGuildName = ns.NormalizeGuildName
local PrintChatMessage = ns.PrintChatMessage
local RemovePlayerLanguage = ns.RemovePlayerLanguage
local RemovePlayerLanguagesBySource = ns.RemovePlayerLanguagesBySource
local SetPlayerLanguage = ns.SetPlayerLanguage
local SetStoredGuildLanguage = ns.SetStoredGuildLanguage
local SetLanguageDropdownSelection = ns.SetLanguageDropdownSelection
local Trim = ns.Trim
local EnsureAutoDetectWordsTable = ns.EnsureAutoDetectWordsTable
local EnsureLanguageOptionsTable = ns.EnsureLanguageOptionsTable
local GetDefaultLanguageMarkEnabled = ns.GetDefaultLanguageMarkEnabled
local EnsureGuildLanguagesTable = ns.EnsureGuildLanguagesTable
local CharacterDB = ns.CharacterDB
local ADDON_TITLE = "LanguageScout"
local PLAYER_SOURCE_KEYS = {
    manual = "PLAYER_SOURCE_MANUAL",
    automatic = "PLAYER_SOURCE_AUTOMATIC",
    sync = "PLAYER_SOURCE_SYNC",
    confirmed = "PLAYER_SOURCE_CONFIRMED",
    guild = "PLAYER_SOURCE_GUILD",
}
local PLAYER_SOURCE_FILTER_ORDER = { "manual", "confirmed", "automatic", "sync", "guild", "legacy" }
local PLAYER_SORT_LABEL_KEYS = {
    name = "SORT_NAME",
    oldest = "SORT_OLD_TO_NEW",
    newest = "SORT_NEW_TO_OLD",
}
local PLAYER_SORT_ORDER = { "name", "oldest", "newest" }

local function GetPanelTitle(labelKey)
    return ADDON_TITLE .. ": " .. L(labelKey)
end

local function GetPlayerSourceDisplayName(source, selfReported, channelHint)
    if source == "automatic" and channelHint then return L("PLAYER_SOURCE_CHANNEL") end
    if source == "sync" and selfReported then source = "confirmed" end
    return L(PLAYER_SOURCE_KEYS[source] or "PLAYER_SOURCE_LEGACY")
end

local function GetPlayerSourceFilterValue(source, selfReported)
    if source == "sync" and selfReported then return "confirmed" end
    return PLAYER_SOURCE_KEYS[source] and source or "legacy"
end

local function RegisterPanelCategory(parentCategory, panelFrame, labelKey)
    local registeredCategory
    if Settings.RegisterCanvasLayoutSubcategory and parentCategory then
        registeredCategory = Settings.RegisterCanvasLayoutSubcategory(parentCategory, panelFrame, L(labelKey))
    else
        registeredCategory = Settings.RegisterCanvasLayoutCategory(panelFrame, GetPanelTitle(labelKey))
    end

    Settings.RegisterAddOnCategory(registeredCategory)
    return registeredCategory
end

local function ApplyMouseWheelScrolling(scrollFrame, listContainer, rowStep)
    scrollFrame:SetScript("OnMouseWheel", function(_, delta)
        local current = scrollFrame:GetVerticalScroll()
        local max = math.max(0, listContainer:GetHeight() - scrollFrame:GetHeight())
        local step = rowStep * 3
        local nextValue = current - (delta * step)

        if nextValue < 0 then
            nextValue = 0
        elseif nextValue > max then
            nextValue = max
        end

        scrollFrame:SetVerticalScroll(nextValue)
    end)
end

local function InitializeLanguageDropdown(dropdown, includeAutoOption, getSelectedValue, onSelectLanguage)
    UIDropDownMenu_Initialize(dropdown, function()
        if includeAutoOption then
            local autoInfo = UIDropDownMenu_CreateInfo()
            autoInfo.text = L("AUTO_LANGUAGE")
            autoInfo.value = nil
            autoInfo.func = function()
                onSelectLanguage(nil)
                SetLanguageDropdownSelection(dropdown, nil)
            end
            autoInfo.checked = (getSelectedValue() == nil)
            UIDropDownMenu_AddButton(autoInfo)
        end

        for _, lang in ipairs(SUPPORTED_LANGUAGES) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = GetLanguageDisplayName(lang)
            info.value = lang
            info.func = function()
                onSelectLanguage(lang)
                SetLanguageDropdownSelection(dropdown, lang)
            end
            info.checked = (getSelectedValue() == lang)
            UIDropDownMenu_AddButton(info)
        end
    end)
end

local function QueuePanelRefresh(panelFrame, refreshFunc, ...)
    if not (C_Timer and C_Timer.After) then
        return
    end

    local delays = { ... }
    if #delays == 0 then
        delays[1] = 0
    end

    for _, delay in ipairs(delays) do
        C_Timer.After(delay, function()
            if panelFrame and panelFrame:IsShown() then
                refreshFunc()
            end
        end)
    end
end

local function RefreshDetectionTargets()
    ns.TryAutoDetectFromUnit("mouseover")
    ns.TryAutoDetectFromUnit("target")
    ns.TryAutoDetectFromUnit("focus")
end

local function BindEnterToButton(editBox, button)
    editBox:SetScript("OnEnterPressed", function()
        button:Click()
    end)
end

local function CreateCheckbox(parent, anchorTarget, offsetY, labelKey, onClick, offsetX)
    local checkbox = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    checkbox:SetPoint("TOPLEFT", anchorTarget, "BOTTOMLEFT", offsetX or 0, offsetY)
    checkbox.Text:SetText(L(labelKey))
    checkbox:SetScript("OnClick", onClick)
    return checkbox
end

local CHECKBOX_GRID_COLUMN_WIDTH = 260
local CHECKBOX_GRID_ROW_HEIGHT = 40

local function PlaceCheckboxInGrid(checkbox, anchorTarget, column, row)
    checkbox:ClearAllPoints()
    checkbox:SetPoint(
        "TOPLEFT",
        anchorTarget,
        "BOTTOMLEFT",
        (column * CHECKBOX_GRID_COLUMN_WIDTH) - 2,
        -10 - (row * CHECKBOX_GRID_ROW_HEIGHT)
    )
    checkbox.Text:SetWidth(215)
    checkbox.Text:SetJustifyH("LEFT")
    checkbox.Text:SetJustifyV("TOP")
end

local function UpdateScrollChildRect(scrollFrame)
    if scrollFrame.UpdateScrollChildRect then
        scrollFrame:UpdateScrollChildRect()
    end
end

local function HideRows(rows)
    for _, row in ipairs(rows) do
        row:Hide()
    end
end

-- Shared renderer for the addon's small static list UIs.
local function RefreshListRows(entries, rows, createRow, listContainer, scrollFrame, emptyText, rowHeight, setRowContent)
    HideRows(rows)

    if #entries == 0 then
        listContainer:SetHeight(rowHeight)
        scrollFrame:SetVerticalScroll(0)
        emptyText:Show()
        UpdateScrollChildRect(scrollFrame)
        return
    end

    emptyText:Hide()

    for index, entry in ipairs(entries) do
        local row = rows[index] or createRow(index)
        setRowContent(row, entry, index)
        row:Show()
    end

    listContainer:SetHeight(#entries * rowHeight)
    UpdateScrollChildRect(scrollFrame)
end

local function CollectSortedEntries(sourceTable, mapEntry, sortFunc)
    local entries = {}
    for key, value in pairs(sourceTable or {}) do
        table.insert(entries, mapEntry(key, value))
    end

    table.sort(entries, sortFunc)
    return entries
end

local function RemoveFirstMatchingValue(list, predicate)
    if not list then
        return false
    end

    for index, value in ipairs(list) do
        if predicate(value, index) then
            table.remove(list, index)
            return true
        end
    end

    return false
end

local panel = CreateFrame("Frame")
local languagesPanel = CreateFrame("Frame")
local autoDetectPanel = CreateFrame("Frame")
local syncPanel = CreateFrame("Frame")
local guildPanel = CreateFrame("Frame")
local resetPanel = CreateFrame("Frame")
local undonePanel = CreateFrame("Frame")
local outgoingPanel = CreateFrame("Frame")
local nameplatePanel = CreateFrame("Frame")

-- Settings canvas frames must start hidden so their first category visit
-- reliably produces OnShow and initializes the page immediately.
panel:Hide()
languagesPanel:Hide()
autoDetectPanel:Hide()
syncPanel:Hide()
guildPanel:Hide()
resetPanel:Hide()
undonePanel:Hide()
outgoingPanel:Hide()
nameplatePanel:Hide()

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText(ADDON_TITLE)

local dropdown = CreateFrame("Frame", nil, panel, "UIDropDownMenuTemplate")
dropdown:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -16, -20)
UIDropDownMenu_SetWidth(dropdown, 120)

local effectiveLanguageText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
effectiveLanguageText:SetPoint("LEFT", dropdown, "RIGHT", 8, 2)
effectiveLanguageText:SetWidth(340)
effectiveLanguageText:SetJustifyH("LEFT")

ns.RefreshOwnLanguageDisplay = function()
    local lang = ns.GetOwnEffectiveLanguage()
    local languageName = ns.IsSupportedLanguage(lang) and GetLanguageDisplayName(lang)
        or L("EFFECTIVE_LANGUAGE_UNAVAILABLE")
    effectiveLanguageText:SetText(string.format(L("EFFECTIVE_LANGUAGE"), languageName))
    if ns.RefreshOutgoingPrefixPanel then ns.RefreshOutgoingPrefixPanel() end
end

InitializeLanguageDropdown(dropdown, true,
    function()
        return LanguageScoutDB.myLanguage
    end,
    function(lang)
        LanguageScoutDB.myLanguage = nil
        if lang then
            LanguageScoutDB.myLanguage = lang
        end
        ns.RefreshOwnLanguageDisplay()
        ns.SyncOwnLanguage()
    end
)

SetLanguageDropdownSelection(dropdown, LanguageScoutDB.myLanguage)

local knownTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
knownTitle:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 16, -28)
knownTitle:SetText(L("KNOWN_PLAYERS"))

local addPlayerBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
addPlayerBox:SetSize(220, 20)
addPlayerBox:SetPoint("TOPLEFT", knownTitle, "BOTTOMLEFT", 0, -12)
addPlayerBox:SetAutoFocus(false)
addPlayerBox:SetMaxLetters(60)

local addLangDropdown = CreateFrame("Frame", nil, panel, "UIDropDownMenuTemplate")
addLangDropdown:SetPoint("LEFT", addPlayerBox, "RIGHT", -8, -2)
UIDropDownMenu_SetWidth(addLangDropdown, 110)

local selectedAddLanguage = "DE"

InitializeLanguageDropdown(addLangDropdown, false,
    function()
        return selectedAddLanguage
    end,
    function(lang)
        selectedAddLanguage = lang
    end
)

SetLanguageDropdownSelection(addLangDropdown, selectedAddLanguage)

local addPlayerButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
addPlayerButton:SetSize(80, 22)
addPlayerButton:SetPoint("LEFT", addLangDropdown, "RIGHT", -10, 2)
addPlayerButton:SetText(L("ADD"))

local helperText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
helperText:SetPoint("TOPLEFT", addPlayerBox, "BOTTOMLEFT", 4, -8)
helperText:SetText(L("FORMAT_HELP"))

local manualFeedbackCheckbox = CreateCheckbox(panel, helperText, -10, "MANUAL_MARK_FEEDBACK", function(self)
    LanguageScoutDB.manualMarkFeedback = self:GetChecked() and true or false
end, -2)

local displayFlagsInChatCheckbox = CreateCheckbox(panel, manualFeedbackCheckbox, -8, "DISPLAY_FLAGS_IN_CHAT", function(self)
    LanguageScoutDB.displayFlagsInChat = self:GetChecked() and true or false
end)

local displayFlagsInTooltipCheckbox = CreateCheckbox(panel, displayFlagsInChatCheckbox, -8, "DISPLAY_FLAGS_IN_TOOLTIP", function(self)
    LanguageScoutDB.displayFlagsInTooltip = self:GetChecked() and true or false
end)

local displayFlagsInGuildCheckbox = CreateCheckbox(panel, displayFlagsInTooltipCheckbox, -8, "DISPLAY_FLAGS_IN_GUILD", function(self)
    CharacterDB.displayFlagsInGuild = self:GetChecked() and true or false
end)

local displayFlagsInLFGCheckbox = CreateCheckbox(panel, displayFlagsInGuildCheckbox, -8, "DISPLAY_FLAGS_IN_LFG", function(self)
    LanguageScoutDB.displayFlagsInLFG = self:GetChecked() and true or false
end)

PlaceCheckboxInGrid(manualFeedbackCheckbox, helperText, 0, 0)
PlaceCheckboxInGrid(displayFlagsInChatCheckbox, helperText, 1, 0)
PlaceCheckboxInGrid(displayFlagsInTooltipCheckbox, helperText, 0, 1)
PlaceCheckboxInGrid(displayFlagsInGuildCheckbox, helperText, 1, 1)
PlaceCheckboxInGrid(displayFlagsInLFGCheckbox, helperText, 0, 2)

local function RestoreRecommendedDefaults()
    LanguageScoutDB.myLanguage = nil
    LanguageScoutDB.autoDetect = true
    LanguageScoutDB.autoDetectLanguageChannels = true
    for _, channel in ipairs(ns.CHAT_DETECTION_CHANNELS) do
        ns.SetChatDetectionChannelEnabled(channel.key, true)
        ns.SetOutgoingPrefixChannelEnabled(channel.key, true)
    end
    LanguageScoutDB.prefixOutgoingMessages = true
    LanguageScoutDB.syncGuild = true
    LanguageScoutDB.syncParty = true
    LanguageScoutDB.autoMarkFeedback = true
    LanguageScoutDB.autoDetectPetNames = true
    LanguageScoutDB.autoDetectGuildNames = true
    LanguageScoutDB.manualMarkFeedback = true
    LanguageScoutDB.displayFlagsInChat = true
    LanguageScoutDB.displayFlagsInTooltip = true
    LanguageScoutDB.displayFlagsInGuild = true
    LanguageScoutDB.displayFlagsInLFG = true
    ns.SetNameplateFlagPosition("off")
    LanguageScoutDB.debugPerformance = false
    LanguageScoutDB.debugPerformanceThreshold = 10
    CharacterDB.displayFlagsInGuild = true

    EnsureLanguageOptionsTable()
    for _, lang in ipairs(SUPPORTED_LANGUAGES) do
        ns.SetLanguageMarkEnabled(lang, GetDefaultLanguageMarkEnabled(lang))
        ns.SetLanguageAutoDetectEnabled(lang, true)
    end

    SetLanguageDropdownSelection(dropdown, nil)
    ns.RefreshOwnLanguageDisplay()
    manualFeedbackCheckbox:SetChecked(true)
    displayFlagsInChatCheckbox:SetChecked(true)
    displayFlagsInTooltipCheckbox:SetChecked(true)
    displayFlagsInGuildCheckbox:SetChecked(true)
    displayFlagsInLFGCheckbox:SetChecked(true)

    if type(ns.UpdatePetDetectionEvents) == "function" then
        ns.UpdatePetDetectionEvents()
    end
    if type(ns.RefreshPetOwnerMappings) == "function" then
        ns.RefreshPetOwnerMappings()
    end
    RefreshDetectionTargets()
    if type(ns.SyncOwnLanguage) == "function" then
        ns.SyncOwnLanguage()
    end
    if type(ns.RefreshAutoDetectPanel) == "function" then
        ns.RefreshAutoDetectPanel()
    end
    if type(ns.RefreshLanguagesPanel) == "function" then
        ns.RefreshLanguagesPanel()
    end

    PrintChatMessage(L("RESTORE_DEFAULTS_DONE"))
end

StaticPopupDialogs["LANGUAGESCOUT_RESTORE_DEFAULTS"] = {
    text = L("RESTORE_DEFAULTS_CONFIRM"),
    button1 = YES,
    button2 = NO,
    OnAccept = RestoreRecommendedDefaults,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local restoreDefaultsButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
restoreDefaultsButton:SetSize(210, 22)
restoreDefaultsButton:SetPoint(
    "TOPLEFT",
    helperText,
    "BOTTOMLEFT",
    CHECKBOX_GRID_COLUMN_WIDTH,
    -10 - (2 * CHECKBOX_GRID_ROW_HEIGHT)
)
restoreDefaultsButton:SetText(L("RESTORE_RECOMMENDED_DEFAULTS"))
restoreDefaultsButton:SetScript("OnClick", function()
    StaticPopup_Show("LANGUAGESCOUT_RESTORE_DEFAULTS")
end)

local playerSearchLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
playerSearchLabel:SetPoint("TOPLEFT", helperText, "BOTTOMLEFT", 4, -132)
playerSearchLabel:SetText(L("SEARCH_PLAYERS"))

local playerSearchBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
playerSearchBox:SetSize(220, 20)
playerSearchBox:SetPoint("LEFT", playerSearchLabel, "RIGHT", 10, 0)
playerSearchBox:SetAutoFocus(false)
playerSearchBox:SetMaxLetters(60)
playerSearchBox:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
end)
playerSearchBox:SetScript("OnEscapePressed", function(self)
    self:SetText("")
    self:ClearFocus()
end)

local selectedPlayerLanguageFilter
local selectedPlayerSourceFilter
local selectedPlayerSort = "name"
local RefreshKnownPlayerView

local playerLanguageFilterDropdown = CreateFrame("Frame", nil, panel, "UIDropDownMenuTemplate")
playerLanguageFilterDropdown:SetPoint("TOPLEFT", playerSearchLabel, "BOTTOMLEFT", -16, -10)
UIDropDownMenu_SetWidth(playerLanguageFilterDropdown, 120)

local function SetPlayerLanguageFilterSelection()
    UIDropDownMenu_SetSelectedValue(playerLanguageFilterDropdown, selectedPlayerLanguageFilter)
    UIDropDownMenu_SetText(
        playerLanguageFilterDropdown,
        selectedPlayerLanguageFilter
            and GetLanguageDisplayName(selectedPlayerLanguageFilter)
            or L("ALL_LANGUAGES")
    )
end

UIDropDownMenu_Initialize(playerLanguageFilterDropdown, function()
    local allInfo = UIDropDownMenu_CreateInfo()
    allInfo.text = L("ALL_LANGUAGES")
    allInfo.checked = selectedPlayerLanguageFilter == nil
    allInfo.func = function()
        selectedPlayerLanguageFilter = nil
        SetPlayerLanguageFilterSelection()
        RefreshKnownPlayerView()
    end
    UIDropDownMenu_AddButton(allInfo)

    for _, lang in ipairs(SUPPORTED_LANGUAGES) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = GetLanguageDisplayName(lang)
        info.value = lang
        info.checked = selectedPlayerLanguageFilter == lang
        info.func = function()
            selectedPlayerLanguageFilter = lang
            SetPlayerLanguageFilterSelection()
            RefreshKnownPlayerView()
        end
        UIDropDownMenu_AddButton(info)
    end
end)

SetPlayerLanguageFilterSelection()

local playerSourceFilterDropdown = CreateFrame("Frame", nil, panel, "UIDropDownMenuTemplate")
playerSourceFilterDropdown:SetPoint("LEFT", playerLanguageFilterDropdown, "RIGHT", -8, 0)
UIDropDownMenu_SetWidth(playerSourceFilterDropdown, 150)

local function SetPlayerSourceFilterSelection()
    UIDropDownMenu_SetSelectedValue(playerSourceFilterDropdown, selectedPlayerSourceFilter)
    UIDropDownMenu_SetText(
        playerSourceFilterDropdown,
        selectedPlayerSourceFilter
            and GetPlayerSourceDisplayName(selectedPlayerSourceFilter)
            or L("ALL_SOURCES")
    )
end

UIDropDownMenu_Initialize(playerSourceFilterDropdown, function()
    local allInfo = UIDropDownMenu_CreateInfo()
    allInfo.text = L("ALL_SOURCES")
    allInfo.checked = selectedPlayerSourceFilter == nil
    allInfo.func = function()
        selectedPlayerSourceFilter = nil
        SetPlayerSourceFilterSelection()
        RefreshKnownPlayerView()
    end
    UIDropDownMenu_AddButton(allInfo)

    for _, source in ipairs(PLAYER_SOURCE_FILTER_ORDER) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = GetPlayerSourceDisplayName(source)
        info.value = source
        info.checked = selectedPlayerSourceFilter == source
        info.func = function()
            selectedPlayerSourceFilter = source
            SetPlayerSourceFilterSelection()
            RefreshKnownPlayerView()
        end
        UIDropDownMenu_AddButton(info)
    end
end)

SetPlayerSourceFilterSelection()

local playerSortDropdown = CreateFrame("Frame", nil, panel, "UIDropDownMenuTemplate")
playerSortDropdown:SetPoint("LEFT", playerSourceFilterDropdown, "RIGHT", -8, 0)
UIDropDownMenu_SetWidth(playerSortDropdown, 125)

local function SetPlayerSortSelection()
    UIDropDownMenu_SetSelectedValue(playerSortDropdown, selectedPlayerSort)
    UIDropDownMenu_SetText(playerSortDropdown, L(PLAYER_SORT_LABEL_KEYS[selectedPlayerSort]))
end

UIDropDownMenu_Initialize(playerSortDropdown, function()
    for _, sortMode in ipairs(PLAYER_SORT_ORDER) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = L(PLAYER_SORT_LABEL_KEYS[sortMode])
        info.value = sortMode
        info.checked = selectedPlayerSort == sortMode
        info.func = function()
            selectedPlayerSort = sortMode
            SetPlayerSortSelection()
            RefreshKnownPlayerView()
        end
        UIDropDownMenu_AddButton(info)
    end
end)

SetPlayerSortSelection()

local playerListHeader = CreateFrame("Frame", nil, panel)
playerListHeader:SetSize(500, 18)
playerListHeader:SetPoint("TOPLEFT", playerLanguageFilterDropdown, "BOTTOMLEFT", 16, -10)

local playerNameHeader = playerListHeader:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
playerNameHeader:SetPoint("LEFT", 0, 0)
playerNameHeader:SetWidth(180)
playerNameHeader:SetJustifyH("LEFT")
playerNameHeader:SetText(L("PLAYER_NAME"))

local playerLanguageHeader = playerListHeader:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
playerLanguageHeader:SetPoint("LEFT", 185, 0)
playerLanguageHeader:SetWidth(75)
playerLanguageHeader:SetJustifyH("LEFT")
playerLanguageHeader:SetText(L("LANGUAGE"))

local playerSourceHeader = playerListHeader:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
playerSourceHeader:SetPoint("LEFT", 265, 0)
playerSourceHeader:SetWidth(135)
playerSourceHeader:SetJustifyH("LEFT")
playerSourceHeader:SetText(L("ENTRY_SOURCE"))

local playerRemoveHeader = playerListHeader:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
playerRemoveHeader:SetPoint("RIGHT", 0, 0)
playerRemoveHeader:SetWidth(90)
playerRemoveHeader:SetJustifyH("CENTER")
playerRemoveHeader:SetText(L("REMOVE"))

local rowStep = 24

local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", playerListHeader, "BOTTOMLEFT", -4, -4)
scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 20)
scrollFrame:EnableMouseWheel(true)

local listContainer = CreateFrame("Frame", nil, scrollFrame)
listContainer:SetSize(500, 1)
scrollFrame:SetScrollChild(listContainer)

local emptyText = listContainer:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
emptyText:SetPoint("TOPLEFT", 4, -4)
emptyText:SetText(L("NO_PLAYERS"))

local playerRows = {}
local allKnownPlayerEntries = {}
local knownPlayerEntries = {}
local knownPlayersDirty = true
local knownPlayerDefaultVisibleRows = 24
local RefreshKnownPlayers

ns.MarkKnownPlayersDirty = function()
    knownPlayersDirty = true
end

local function TryAddKnownPlayer(rawInput, lang)
    local name, realm = ParseFullName(rawInput)
    local fullName = FullName(name, realm)
    if not fullName then
        return
    end

    if SetPlayerLanguage(fullName, lang, true, "manual") then
        ns.ShowManualLanguageMarkedMessage(fullName, lang)
        return true
    end
end

local function FormatPlayerUpdatedAt(updatedAt)
    local timestamp = tonumber(updatedAt)
    if not timestamp or timestamp <= 0 then
        return L("UNKNOWN")
    end

    if date then
        return date("%Y-%m-%d %H:%M", timestamp)
    end

    return tostring(timestamp)
end

local function ShowKnownPlayerTooltip(row)
    local entry = row and row.entry
    if not entry then
        return
    end

    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(entry.playerName, 1, 1, 1)
    GameTooltip:AddDoubleLine(L("LANGUAGE"), GetLanguageDisplayName(entry.lang), 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine(L("ENTRY_SOURCE"), GetPlayerSourceDisplayName(entry.source, entry.selfReported, entry.channelHint), 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine(L("LAST_UPDATED"), FormatPlayerUpdatedAt(entry.updatedAt), 1, 0.82, 0, 1, 1, 1)
    if entry.channelHint then GameTooltip:AddDoubleLine(L("CHANNEL_EVIDENCE"), entry.channelHint, 1, 0.82, 0, 1, 1, 1) end
    GameTooltip:Show()
end

local function CreatePlayerRow(index)
    local row = CreateFrame("Frame", nil, listContainer)
    row:SetSize(500, 22)

    row.nameText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.nameText:SetPoint("LEFT", 0, 0)
    row.nameText:SetJustifyH("LEFT")
    row.nameText:SetWidth(180)

    row.languageText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.languageText:SetPoint("LEFT", 185, 0)
    row.languageText:SetJustifyH("LEFT")
    row.languageText:SetWidth(75)

    row.removeButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.removeButton:SetSize(90, 20)
    row.removeButton:SetPoint("RIGHT", 0, 0)
    row.removeButton:SetText(L("REMOVE"))

    row.sourceText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.sourceText:SetPoint("LEFT", 265, 0)
    row.sourceText:SetJustifyH("LEFT")
    row.sourceText:SetWidth(135)

    row:EnableMouse(true)
    row:EnableMouseWheel(true)
    row:SetScript("OnEnter", ShowKnownPlayerTooltip)
    row:SetScript("OnLeave", function(self)
        if GameTooltip:IsOwned(self) then
            GameTooltip:Hide()
        end
    end)
    row:SetScript("OnMouseWheel", function(_, delta)
        local mouseWheelHandler = scrollFrame:GetScript("OnMouseWheel")
        if mouseWheelHandler then
            mouseWheelHandler(scrollFrame, delta)
        end
    end)

    playerRows[index] = row
    return row
end

local function SetKnownPlayerDisplayName(row, fullPlayerName)
    local shortPlayerName, playerRealm = ParseFullName(fullPlayerName)
    local ownRealm = GetPlayerRealm()
    if shortPlayerName and playerRealm and ownRealm and playerRealm == ownRealm then
        row.nameText:SetText(shortPlayerName)
        return
    end

    row.nameText:SetText(fullPlayerName)
    if row.nameText:GetStringWidth() <= row.nameText:GetWidth() then
        return
    end

    row.nameText:SetText(shortPlayerName or fullPlayerName)
end

local function GetKnownPlayerVisibleRowCount()
    local viewportHeight = scrollFrame:GetHeight() or 0
    if viewportHeight <= 0 then
        return knownPlayerDefaultVisibleRows
    end

    return math.max(1, math.ceil(viewportHeight / rowStep) + 2)
end

local function GetKnownPlayerSearchText()
    return string.lower(Trim(playerSearchBox:GetText()) or "")
end

local function GetKnownPlayerSortTimestamp(entry)
    return tonumber(entry and entry.updatedAt) or 0
end

local function SortKnownPlayerEntries(entries)
    table.sort(entries, function(a, b)
        if selectedPlayerSort == "oldest" or selectedPlayerSort == "newest" then
            local aTimestamp = GetKnownPlayerSortTimestamp(a)
            local bTimestamp = GetKnownPlayerSortTimestamp(b)
            if aTimestamp ~= bTimestamp then
                if selectedPlayerSort == "oldest" then
                    return aTimestamp < bTimestamp
                end
                return aTimestamp > bTimestamp
            end
        end

        return a.playerName < b.playerName
    end)
end

local function ApplyKnownPlayerSearchFilter()
    local searchText = GetKnownPlayerSearchText()
    if searchText == ""
        and selectedPlayerLanguageFilter == nil
        and selectedPlayerSourceFilter == nil
        and selectedPlayerSort == "name"
    then
        knownPlayerEntries = allKnownPlayerEntries
        return
    end

    local filteredEntries = {}
    for _, entry in ipairs(allKnownPlayerEntries) do
        local matchesSearch = searchText == ""
            or string.find(string.lower(entry.playerName), searchText, 1, true)
        local matchesLanguage = selectedPlayerLanguageFilter == nil
            or entry.lang == selectedPlayerLanguageFilter
        local matchesSource = selectedPlayerSourceFilter == nil
            or GetPlayerSourceFilterValue(entry.source, entry.selfReported) == selectedPlayerSourceFilter
        if matchesSearch and matchesLanguage and matchesSource then
            filteredEntries[#filteredEntries + 1] = entry
        end
    end
    SortKnownPlayerEntries(filteredEntries)
    knownPlayerEntries = filteredEntries
end

local function RenderKnownPlayerRows()
    local entryCount = #knownPlayerEntries
    if entryCount == 0 then
        HideRows(playerRows)
        listContainer:SetHeight(rowStep)
        scrollFrame:SetVerticalScroll(0)
        local hasActiveFilter = GetKnownPlayerSearchText() ~= ""
            or selectedPlayerLanguageFilter ~= nil
            or selectedPlayerSourceFilter ~= nil
        emptyText:SetText(hasActiveFilter and L("NO_SEARCH_RESULTS") or L("NO_PLAYERS"))
        emptyText:Show()
        UpdateScrollChildRect(scrollFrame)
        return
    end

    emptyText:Hide()
    listContainer:SetHeight(entryCount * rowStep)

    local firstEntryIndex = math.floor((scrollFrame:GetVerticalScroll() or 0) / rowStep) + 1
    local visibleRowCount = GetKnownPlayerVisibleRowCount()
    for rowIndex = 1, visibleRowCount do
        local row = playerRows[rowIndex] or CreatePlayerRow(rowIndex)
        local entryIndex = firstEntryIndex + rowIndex - 1
        local entry = knownPlayerEntries[entryIndex]

        if entry then
            row.entry = entry
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", listContainer, "TOPLEFT", 0, -((entryIndex - 1) * rowStep))

            SetKnownPlayerDisplayName(row, entry.playerName)
            row.languageText:SetText(GetLanguageDisplayName(entry.lang))
            row.sourceText:SetText(GetPlayerSourceDisplayName(entry.source, entry.selfReported, entry.channelHint))
            row.removeButton:SetScript("OnClick", function()
                RemovePlayerLanguage(entry.playerName)
                RefreshKnownPlayers()
            end)
            row:Show()
        else
            row.entry = nil
            row:Hide()
        end
    end

    for rowIndex = visibleRowCount + 1, #playerRows do
        playerRows[rowIndex]:Hide()
    end

    UpdateScrollChildRect(scrollFrame)
end

RefreshKnownPlayers = function()
    if knownPlayersDirty then
        allKnownPlayerEntries = CollectSortedEntries(LanguageScoutDB.players, function(playerName, record)
            return {
                playerName = playerName,
                lang = type(record) == "table" and record.lang or nil,
                source = type(record) == "table" and record.source or nil,
                selfReported = type(record) == "table" and record.selfReported == true or nil,
                channelHint = type(record) == "table" and record.channelHint or nil,
                updatedAt = type(record) == "table" and record.updatedAt or nil,
            }
        end, function(a, b)
            return a.playerName < b.playerName
        end)

        knownPlayersDirty = false
    end

    ApplyKnownPlayerSearchFilter()
    RenderKnownPlayerRows()
end


RefreshKnownPlayerView = function()
    scrollFrame:SetVerticalScroll(0)
    ApplyKnownPlayerSearchFilter()
    RenderKnownPlayerRows()
end

scrollFrame:HookScript("OnVerticalScroll", RenderKnownPlayerRows)
playerSearchBox:SetScript("OnTextChanged", function()
    RefreshKnownPlayerView()
end)

addPlayerButton:SetScript("OnClick", function()
    if TryAddKnownPlayer(addPlayerBox:GetText(), selectedAddLanguage) then
        addPlayerBox:SetText("")
        RefreshKnownPlayers()
    end
end)

BindEnterToButton(addPlayerBox, addPlayerButton)

local function RefreshMainControls()
    SetLanguageDropdownSelection(dropdown, LanguageScoutDB.myLanguage)
    ns.RefreshOwnLanguageDisplay()
    SetLanguageDropdownSelection(addLangDropdown, selectedAddLanguage)
    manualFeedbackCheckbox:SetChecked(LanguageScoutDB.manualMarkFeedback ~= false)
    displayFlagsInChatCheckbox:SetChecked(LanguageScoutDB.displayFlagsInChat ~= false)
    displayFlagsInTooltipCheckbox:SetChecked(LanguageScoutDB.displayFlagsInTooltip ~= false)
    displayFlagsInGuildCheckbox:SetChecked(CharacterDB.displayFlagsInGuild ~= false)
    displayFlagsInLFGCheckbox:SetChecked(LanguageScoutDB.displayFlagsInLFG ~= false)
end

local function RefreshMainPanel()
    RefreshMainControls()
    RefreshKnownPlayers()
end

-- Initialize lightweight controls without eagerly building the saved-player list.
RefreshMainControls()

panel:SetScript("OnShow", function()
    RefreshMainPanel()

    QueuePanelRefresh(panel, RefreshMainPanel)
end)

-- Large saved-data lists are refreshed lazily when their settings page opens.
ApplyMouseWheelScrolling(scrollFrame, listContainer, rowStep)

local category
local languagesCategory
local autoCategory
local syncCategory
local guildCategory
local resetCategory

local function OpenLanguageScoutSettings()
    if Settings.OpenToCategory and category and category.GetID then
        Settings.OpenToCategory(category:GetID())
        return
    end

    if InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory("LanguageScout")
        InterfaceOptionsFrame_OpenToCategory("LanguageScout")
    end
end

SLASH_LANGUAGESCOUT1 = "/languagescout"
SLASH_LANGUAGESCOUT2 = "/ls"
SlashCmdList.LANGUAGESCOUT = OpenLanguageScoutSettings

local languagesTitle = languagesPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
languagesTitle:SetPoint("TOPLEFT", 16, -16)
languagesTitle:SetText(GetPanelTitle("LANGUAGES"))

local languagesDescription = languagesPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
languagesDescription:SetPoint("TOPLEFT", languagesTitle, "BOTTOMLEFT", 0, -10)
languagesDescription:SetWidth(560)
languagesDescription:SetJustifyH("LEFT")
languagesDescription:SetText(L("LANGUAGES_DESCRIPTION"))

local languagesScrollFrame = CreateFrame("ScrollFrame", nil, languagesPanel, "UIPanelScrollFrameTemplate")
languagesScrollFrame:SetPoint("TOPLEFT", languagesDescription, "BOTTOMLEFT", -2, -16)
languagesScrollFrame:SetPoint("BOTTOMRIGHT", languagesPanel, "BOTTOMRIGHT", -30, 20)
languagesScrollFrame:EnableMouseWheel(true)

local languagesListContainer = CreateFrame("Frame", nil, languagesScrollFrame)
languagesListContainer:SetSize(560, math.max(1, (#SUPPORTED_LANGUAGES - 1) * 42 + 34))
languagesScrollFrame:SetScrollChild(languagesListContainer)
ApplyMouseWheelScrolling(languagesScrollFrame, languagesListContainer, 42)

local function ForwardLanguageMouseWheel(_, delta)
    local handler = languagesScrollFrame:GetScript("OnMouseWheel")
    if handler then handler(languagesScrollFrame, delta) end
end

local function RefreshLanguageScrollRange()
    UpdateScrollChildRect(languagesScrollFrame)
    local maxScroll = math.max(0, languagesListContainer:GetHeight() - languagesScrollFrame:GetHeight())
    languagesScrollFrame:SetVerticalScroll(math.min(languagesScrollFrame:GetVerticalScroll(), maxScroll))
end

languagesScrollFrame:HookScript("OnSizeChanged", RefreshLanguageScrollRange)

local languageOptionRows = {}

for index, lang in ipairs(SUPPORTED_LANGUAGES) do
    local rowLang = lang
    local row = CreateFrame("Frame", nil, languagesListContainer)
    row:SetSize(560, 34)
    row:SetPoint("TOPLEFT", languagesListContainer, "TOPLEFT", 2, -((index - 1) * 42))
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", ForwardLanguageMouseWheel)

    row.languageText = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.languageText:SetPoint("LEFT", 0, 0)
    row.languageText:SetWidth(150)
    row.languageText:SetJustifyH("LEFT")
    row.languageText:SetText(GetLanguageDisplayName(rowLang))

    row.markCheckbox = CreateFrame("CheckButton", nil, row, "InterfaceOptionsCheckButtonTemplate")
    row.markCheckbox:SetPoint("LEFT", 160, 0)
    row.markCheckbox.Text:SetText(L("LANGUAGE_MARK"))
    row.markCheckbox:EnableMouseWheel(true)
    row.markCheckbox:SetScript("OnMouseWheel", ForwardLanguageMouseWheel)
    row.markCheckbox:SetScript("OnClick", function(self)
        ns.SetLanguageMarkEnabled(rowLang, self:GetChecked())
    end)

    row.autoDetectCheckbox = CreateFrame("CheckButton", nil, row, "InterfaceOptionsCheckButtonTemplate")
    row.autoDetectCheckbox:SetPoint("LEFT", 330, 0)
    row.autoDetectCheckbox.Text:SetText(L("LANGUAGE_AUTODETECT"))
    row.autoDetectCheckbox:EnableMouseWheel(true)
    row.autoDetectCheckbox:SetScript("OnMouseWheel", ForwardLanguageMouseWheel)
    row.autoDetectCheckbox:SetScript("OnClick", function(self)
        ns.SetLanguageAutoDetectEnabled(rowLang, self:GetChecked())
        if self:GetChecked() then
            RefreshDetectionTargets()
        end
    end)

    languageOptionRows[rowLang] = row
end

local function RefreshLanguagesPanel()
    EnsureLanguageOptionsTable()
    for _, lang in ipairs(SUPPORTED_LANGUAGES) do
        local row = languageOptionRows[lang]
        row.markCheckbox:SetChecked(ns.IsLanguageMarkEnabled(lang))
        row.autoDetectCheckbox:SetChecked(ns.IsLanguageAutoDetectEnabled(lang))
    end
    RefreshLanguageScrollRange()
end

ns.RefreshLanguagesPanel = RefreshLanguagesPanel
RefreshLanguagesPanel()

languagesPanel:SetScript("OnShow", function()
    RefreshLanguagesPanel()
    QueuePanelRefresh(languagesPanel, RefreshLanguagesPanel)
end)

local autoTitle = autoDetectPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
autoTitle:SetPoint("TOPLEFT", 16, -16)
autoTitle:SetText(GetPanelTitle("AUTO_DETECT"))

local autoDescription = autoDetectPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
autoDescription:SetPoint("TOPLEFT", autoTitle, "BOTTOMLEFT", 0, -10)
autoDescription:SetText(L("AUTO_DETECT_DESCRIPTION"))

local autoWordBox = CreateFrame("EditBox", nil, autoDetectPanel, "InputBoxTemplate")
autoWordBox:SetSize(220, 20)
autoWordBox:SetPoint("TOPLEFT", autoDescription, "BOTTOMLEFT", 0, -14)
autoWordBox:SetAutoFocus(false)
autoWordBox:SetMaxLetters(80)

local autoLangDropdown = CreateFrame("Frame", nil, autoDetectPanel, "UIDropDownMenuTemplate")
autoLangDropdown:SetPoint("LEFT", autoWordBox, "RIGHT", -8, -2)
UIDropDownMenu_SetWidth(autoLangDropdown, 110)

local selectedAutoLanguage = "DE"

InitializeLanguageDropdown(autoLangDropdown, false,
    function()
        return selectedAutoLanguage
    end,
    function(lang)
        selectedAutoLanguage = lang
    end
)

SetLanguageDropdownSelection(autoLangDropdown, selectedAutoLanguage)

local addWordButton = CreateFrame("Button", nil, autoDetectPanel, "UIPanelButtonTemplate")
addWordButton:SetSize(110, 22)
addWordButton:SetPoint("LEFT", autoLangDropdown, "RIGHT", -10, 2)
addWordButton:SetText(L("ADD_WORD"))

local autoHelperText = autoDetectPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
autoHelperText:SetPoint("TOPLEFT", autoWordBox, "BOTTOMLEFT", 4, -8)
autoHelperText:SetText(L("AUTO_DETECT_HELP"))

local chatChannelCheckboxes = {}
local languageChannelsCheckbox
local function RefreshChatChannelControls()
    for _, channel in ipairs(ns.CHAT_DETECTION_CHANNELS) do
        local checkbox = chatChannelCheckboxes[channel.key]
        if checkbox then
            checkbox:SetChecked(LanguageScoutDB.chatDetectionChannels[channel.key] ~= false)
            checkbox:SetEnabled(LanguageScoutDB.autoDetect ~= false)
        end
    end
    if languageChannelsCheckbox then
        languageChannelsCheckbox:SetChecked(LanguageScoutDB.autoDetectLanguageChannels ~= false)
        languageChannelsCheckbox:SetEnabled(LanguageScoutDB.autoDetect ~= false)
    end
end

local autoDetectChatCheckbox = CreateCheckbox(autoDetectPanel, autoHelperText, -10, "AUTO_DETECT_CHAT", function(self)
    LanguageScoutDB.autoDetect = self:GetChecked() and true or false
    RefreshChatChannelControls()
end, -2)

local autoFeedbackCheckbox = CreateCheckbox(autoDetectPanel, autoDetectChatCheckbox, -8, "AUTO_MARK_FEEDBACK", function(self)
    LanguageScoutDB.autoMarkFeedback = self:GetChecked() and true or false
end)

local autoDetectPetNamesCheckbox = CreateCheckbox(autoDetectPanel, autoFeedbackCheckbox, -8, "AUTO_DETECT_PET_NAMES", function(self)
    LanguageScoutDB.autoDetectPetNames = self:GetChecked() and true or false
    if type(ns.UpdatePetDetectionEvents) == "function" then
        ns.UpdatePetDetectionEvents()
    end
    if LanguageScoutDB.autoDetectPetNames then
        ns.RefreshPetOwnerMappings()
        RefreshDetectionTargets()
    end
end)

local autoDetectGuildNamesCheckbox = CreateCheckbox(autoDetectPanel, autoDetectPetNamesCheckbox, -8, "AUTO_DETECT_GUILD_NAMES", function(self)
    LanguageScoutDB.autoDetectGuildNames = self:GetChecked() and true or false
    if LanguageScoutDB.autoDetectGuildNames then
        RefreshDetectionTargets()
    end
end)

PlaceCheckboxInGrid(autoDetectChatCheckbox, autoHelperText, 0, 0)
PlaceCheckboxInGrid(autoFeedbackCheckbox, autoHelperText, 1, 0)
PlaceCheckboxInGrid(autoDetectPetNamesCheckbox, autoHelperText, 0, 1)
PlaceCheckboxInGrid(autoDetectGuildNamesCheckbox, autoHelperText, 1, 1)
languageChannelsCheckbox = CreateCheckbox(autoDetectPanel, autoHelperText, -10, "AUTO_DETECT_LANGUAGE_CHANNELS", function(self)
    LanguageScoutDB.autoDetectLanguageChannels = self:GetChecked() and true or false
end)
PlaceCheckboxInGrid(languageChannelsCheckbox, autoHelperText, 0, 2)

local chatChannelsTitle = autoDetectPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
chatChannelsTitle:SetPoint("TOPLEFT", autoHelperText, "BOTTOMLEFT", 0, -136)
chatChannelsTitle:SetText(L("AUTO_DETECT_CHANNELS"))

for index, channel in ipairs(ns.CHAT_DETECTION_CHANNELS) do
    local checkbox = CreateCheckbox(autoDetectPanel, chatChannelsTitle, -10, channel.labelKey, function(self)
        ns.SetChatDetectionChannelEnabled(channel.key, self:GetChecked())
    end)
    PlaceCheckboxInGrid(checkbox, chatChannelsTitle, (index - 1) % 2, math.floor((index - 1) / 2))
    chatChannelCheckboxes[channel.key] = checkbox
end

local autoScrollFrame = CreateFrame("ScrollFrame", nil, autoDetectPanel, "UIPanelScrollFrameTemplate")
autoScrollFrame:SetPoint("TOPLEFT", chatChannelsTitle, "BOTTOMLEFT", -2, -176)
autoScrollFrame:SetPoint("BOTTOMRIGHT", autoDetectPanel, "BOTTOMRIGHT", -30, 20)
autoScrollFrame:EnableMouseWheel(true)

local autoListContainer = CreateFrame("Frame", nil, autoScrollFrame)
autoListContainer:SetSize(500, 1)
autoScrollFrame:SetScrollChild(autoListContainer)

local autoEmptyText = autoListContainer:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
autoEmptyText:SetPoint("TOPLEFT", 4, -4)
autoEmptyText:SetText(L("AUTO_DETECT_EMPTY"))

local autoRows = {}

local function RemoveAutoDetectWord(lang, word)
    local langWords = LanguageScoutDB.autoDetectWords and LanguageScoutDB.autoDetectWords[lang]
    if not langWords then
        return
    end

    RemoveFirstMatchingValue(langWords, function(existingWord)
        return existingWord == word
    end)

    if #langWords == 0 then
        LanguageScoutDB.autoDetectWords[lang] = nil
    end

    if type(ns.MarkAutoDetectKeywordsDirty) == "function" then
        ns.MarkAutoDetectKeywordsDirty(lang)
    end
end

local function TryAddAutoDetectWord(lang, rawWord)
    local word = Trim(rawWord)
    if not word or word == "" then
        return
    end

    EnsureAutoDetectWordsTable()
    LanguageScoutDB.autoDetectWords[lang] = LanguageScoutDB.autoDetectWords[lang] or {}

    for _, existing in ipairs(LanguageScoutDB.autoDetectWords[lang]) do
        if existing == word then
            return true
        end
    end

    table.insert(LanguageScoutDB.autoDetectWords[lang], word)
    if type(ns.MarkAutoDetectKeywordsDirty) == "function" then
        ns.MarkAutoDetectKeywordsDirty(lang)
    end
    return true
end

local function CreateAutoWordRow(index)
    local row = CreateFrame("Frame", nil, autoListContainer)
    row:SetSize(460, 22)

    if index == 1 then
        row:SetPoint("TOPLEFT", 0, 0)
    else
        row:SetPoint("TOPLEFT", autoRows[index - 1], "BOTTOMLEFT", 0, -2)
    end

    row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.text:SetPoint("LEFT", 4, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWidth(360)

    row.removeButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.removeButton:SetSize(90, 20)
    row.removeButton:SetPoint("RIGHT", 0, 0)
    row.removeButton:SetText(L("REMOVE"))

    autoRows[index] = row
    return row
end

local function RefreshAutoWords()
    EnsureAutoDetectWordsTable()
    local entries = {}
    for lang, words in pairs(LanguageScoutDB.autoDetectWords) do
        for _, word in ipairs(words) do
            entries[#entries + 1] = { lang = lang, word = word }
        end
    end

    table.sort(entries, function(a, b)
        if a.lang == b.lang then
            return a.word < b.word
        end
        return a.lang < b.lang
    end)

    RefreshListRows(entries, autoRows, CreateAutoWordRow, autoListContainer, autoScrollFrame, autoEmptyText, rowStep, function(row, entry)
        row.text:SetText(GetLanguageDisplayName(entry.lang) .. " - " .. entry.word)
        row.removeButton:SetScript("OnClick", function()
            RemoveAutoDetectWord(entry.lang, entry.word)
            RefreshAutoWords()
        end)
    end)
end

addWordButton:SetScript("OnClick", function()
    if TryAddAutoDetectWord(selectedAutoLanguage, autoWordBox:GetText()) then
        autoWordBox:SetText("")
        RefreshAutoWords()
    end
end)

BindEnterToButton(autoWordBox, addWordButton)

local function RefreshAutoDetectControls()
    SetLanguageDropdownSelection(autoLangDropdown, selectedAutoLanguage)
    autoDetectChatCheckbox:SetChecked(LanguageScoutDB.autoDetect ~= false)
    autoFeedbackCheckbox:SetChecked(LanguageScoutDB.autoMarkFeedback ~= false)
    autoDetectPetNamesCheckbox:SetChecked(LanguageScoutDB.autoDetectPetNames ~= false)
    autoDetectGuildNamesCheckbox:SetChecked(LanguageScoutDB.autoDetectGuildNames ~= false)
    RefreshChatChannelControls()
end

ns.RefreshAutoDetectPanel = function()
    RefreshAutoDetectControls()
    RefreshAutoWords()
end

-- Initialize lightweight controls without eagerly building the keyword list.
RefreshAutoDetectControls()

autoDetectPanel:SetScript("OnShow", function()
    ns.RefreshAutoDetectPanel()

    QueuePanelRefresh(autoDetectPanel, ns.RefreshAutoDetectPanel)
end)

ApplyMouseWheelScrolling(autoScrollFrame, autoListContainer, rowStep)

do
    local undoneTitle = undonePanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    undoneTitle:SetPoint("TOPLEFT", 16, -16)
    undoneTitle:SetText(GetPanelTitle("UNDONE_GUESSES"))

    local description = undonePanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", undoneTitle, "BOTTOMLEFT", 0, -10)
    description:SetWidth(520)
    description:SetJustifyH("LEFT")
    description:SetText(L("UNDONE_GUESSES_DESCRIPTION"))

    local header = CreateFrame("Frame", nil, undonePanel)
    header:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -18)
    header:SetSize(500, 18)
    local nameHeader = header:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    nameHeader:SetPoint("LEFT", 0, 0)
    nameHeader:SetText(L("PLAYER_NAME"))
    local languageHeader = header:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    languageHeader:SetPoint("LEFT", 235, 0)
    languageHeader:SetText(L("LANGUAGE"))

    local undoneScroll = CreateFrame("ScrollFrame", nil, undonePanel, "UIPanelScrollFrameTemplate")
    undoneScroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", -2, -6)
    undoneScroll:SetPoint("BOTTOMRIGHT", undonePanel, "BOTTOMRIGHT", -30, 20)
    undoneScroll:EnableMouseWheel(true)
    local list = CreateFrame("Frame", nil, undoneScroll)
    list:SetSize(500, 1)
    undoneScroll:SetScrollChild(list)
    local empty = list:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    empty:SetPoint("TOPLEFT", 4, -4)
    empty:SetText(L("NO_UNDONE_GUESSES"))

    local rows = {}
    local function CreateUndoneRow(index)
        local row = CreateFrame("Frame", nil, list)
        row:SetSize(500, 26)
        row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -((index - 1) * 30))
        row.nameText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        row.nameText:SetPoint("LEFT", 0, 0)
        row.nameText:SetWidth(225)
        row.nameText:SetJustifyH("LEFT")
        row.languageText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        row.languageText:SetPoint("LEFT", 235, 0)
        row.languageText:SetWidth(115)
        row.languageText:SetJustifyH("LEFT")
        row.allowButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.allowButton:SetSize(140, 22)
        row.allowButton:SetPoint("RIGHT", 0, 0)
        row.allowButton:SetText(L("ALLOW_AGAIN"))
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            if not self.guess then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.guess.playerName, 1, 1, 1)
            GameTooltip:AddDoubleLine(L("LANGUAGE"), GetLanguageDisplayName(self.guess.lang), 1, 0.82, 0, 1, 1, 1)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function(self)
            if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        end)
        rows[index] = row
        return row
    end

    local function RefreshUndoneGuesses()
        local entries = {}
        for playerName, languages in pairs(LanguageScoutDB.rejectedPlayerLanguages or {}) do
            for lang, rejected in pairs(languages) do
                if rejected == true and ns.IsSupportedLanguage(lang) then
                    entries[#entries + 1] = { playerName = playerName, lang = lang }
                end
            end
        end
        table.sort(entries, function(a, b)
            if a.playerName == b.playerName then return a.lang < b.lang end
            return a.playerName < b.playerName
        end)
        RefreshListRows(entries, rows, CreateUndoneRow, list, undoneScroll, empty, 30, function(row, entry)
            row.guess = entry
            row.nameText:SetText(entry.playerName)
            row.languageText:SetText(GetLanguageDisplayName(entry.lang))
            row.allowButton:SetScript("OnClick", function()
                ns.AllowPlayerLanguageAgain(entry.playerName, entry.lang)
            end)
        end)
        local maxScroll = math.max(0, list:GetHeight() - undoneScroll:GetHeight())
        undoneScroll:SetVerticalScroll(math.min(undoneScroll:GetVerticalScroll(), maxScroll))
    end

    ns.MarkUndoneGuessesDirty = function()
        if undonePanel:IsShown() then RefreshUndoneGuesses() end
    end
    undonePanel:SetScript("OnShow", RefreshUndoneGuesses)
    ApplyMouseWheelScrolling(undoneScroll, list, 30)
end

local syncTitle = syncPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
syncTitle:SetPoint("TOPLEFT", 16, -16)
syncTitle:SetText(GetPanelTitle("SYNC"))

local syncDescription = syncPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
syncDescription:SetPoint("TOPLEFT", syncTitle, "BOTTOMLEFT", 0, -10)
syncDescription:SetWidth(520)
syncDescription:SetJustifyH("LEFT")
syncDescription:SetText(L("SYNC_DESCRIPTION"))

local guildSyncCheckbox = CreateCheckbox(syncPanel, syncDescription, -18, "SYNC_GUILD", function(self)
    LanguageScoutDB.syncGuild = self:GetChecked() and true or false
end)

local partySyncCheckbox = CreateCheckbox(syncPanel, guildSyncCheckbox, -10, "SYNC_PARTY", function(self)
    LanguageScoutDB.syncParty = self:GetChecked() and true or false
end)

PlaceCheckboxInGrid(guildSyncCheckbox, syncDescription, 0, 0)
PlaceCheckboxInGrid(partySyncCheckbox, syncDescription, 1, 0)

local function RefreshSyncPanel()
    guildSyncCheckbox:SetChecked(LanguageScoutDB.syncGuild ~= false)
    partySyncCheckbox:SetChecked(LanguageScoutDB.syncParty ~= false)
end

-- Canvas frames can already be considered shown while Settings registers them,
-- so the first category visit does not reliably produce a fresh OnShow event.
-- Initialize the controls immediately as well as on later visits.
RefreshSyncPanel()

syncPanel:SetScript("OnShow", function()
    RefreshSyncPanel()
    QueuePanelRefresh(syncPanel, RefreshSyncPanel, 0, 0.05)
end)

local guildTitle = guildPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
guildTitle:SetPoint("TOPLEFT", 16, -16)
guildTitle:SetText(GetPanelTitle("GUILD_ASSIGNMENTS"))

local guildDescription = guildPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
guildDescription:SetPoint("TOPLEFT", guildTitle, "BOTTOMLEFT", 0, -10)
guildDescription:SetWidth(520)
guildDescription:SetJustifyH("LEFT")
guildDescription:SetText(L("GUILD_ASSIGNMENTS_DESCRIPTION"))

local addGuildBox = CreateFrame("EditBox", nil, guildPanel, "InputBoxTemplate")
addGuildBox:SetSize(220, 20)
addGuildBox:SetPoint("TOPLEFT", guildDescription, "BOTTOMLEFT", 0, -14)
addGuildBox:SetAutoFocus(false)
addGuildBox:SetMaxLetters(60)

local addGuildLangDropdown = CreateFrame("Frame", nil, guildPanel, "UIDropDownMenuTemplate")
addGuildLangDropdown:SetPoint("LEFT", addGuildBox, "RIGHT", -8, -2)
UIDropDownMenu_SetWidth(addGuildLangDropdown, 110)

local selectedGuildLanguage = "DE"

InitializeLanguageDropdown(addGuildLangDropdown, false,
    function()
        return selectedGuildLanguage
    end,
    function(lang)
        selectedGuildLanguage = lang
    end
)

SetLanguageDropdownSelection(addGuildLangDropdown, selectedGuildLanguage)

local addGuildButton = CreateFrame("Button", nil, guildPanel, "UIPanelButtonTemplate")
addGuildButton:SetSize(80, 22)
addGuildButton:SetPoint("LEFT", addGuildLangDropdown, "RIGHT", -10, 2)
addGuildButton:SetText(L("ADD"))

local guildHelperText = guildPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
guildHelperText:SetPoint("TOPLEFT", addGuildBox, "BOTTOMLEFT", 4, -8)
guildHelperText:SetText(L("GUILD_FORMAT_HELP"))

local guildScrollFrame = CreateFrame("ScrollFrame", nil, guildPanel, "UIPanelScrollFrameTemplate")
guildScrollFrame:SetPoint("TOPLEFT", guildHelperText, "BOTTOMLEFT", -2, -12)
guildScrollFrame:SetPoint("BOTTOMRIGHT", guildPanel, "BOTTOMRIGHT", -30, 20)
guildScrollFrame:EnableMouseWheel(true)

local guildListContainer = CreateFrame("Frame", nil, guildScrollFrame)
guildListContainer:SetSize(520, 1)
guildScrollFrame:SetScrollChild(guildListContainer)

local guildEmptyText = guildListContainer:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
guildEmptyText:SetPoint("TOPLEFT", 4, -4)
guildEmptyText:SetText(L("NO_GUILDS"))

local guildRows = {}
local guildRowStep = 30
local editingGuildKey

local function ClearGuildEditor()
    editingGuildKey = nil
    addGuildBox:SetText("")
end

local function StartGuildEdit(guildKey, lang)
    editingGuildKey = guildKey
    addGuildBox:SetText(guildKey)
    selectedGuildLanguage = lang or selectedGuildLanguage
    SetLanguageDropdownSelection(addGuildLangDropdown, selectedGuildLanguage)
    addGuildBox:SetFocus()
    addGuildBox:HighlightText()
end

local function RemoveGuildAssignment(guildKey)
    LanguageScoutDB.guildLanguages[guildKey] = nil
    if editingGuildKey == guildKey then
        ClearGuildEditor()
    end
end

local function TrySaveGuildAssignment(rawInput, lang)
    local guildInput = Trim(rawInput)
    if not guildInput or guildInput == "" then
        return
    end

    local guildName, guildRealm = ParseGuildKey(guildInput)
    guildName = NormalizeGuildName(guildName)
    guildRealm = guildRealm or GetPlayerRealm()

    if not guildName or guildName == "" then
        return
    end

    if editingGuildKey and editingGuildKey ~= "" and editingGuildKey ~= guildInput then
        LanguageScoutDB.guildLanguages[editingGuildKey] = nil
    end

    SetStoredGuildLanguage(guildName, guildRealm, lang)
    ClearGuildEditor()
    return true
end

local function CreateGuildRow(index)
    local row = CreateFrame("Frame", nil, guildListContainer)
    row:SetSize(500, 26)

    if index == 1 then
        row:SetPoint("TOPLEFT", 0, 0)
    else
        row:SetPoint("TOPLEFT", guildRows[index - 1], "BOTTOMLEFT", 0, -4)
    end

    row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.text:SetPoint("LEFT", 4, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWidth(290)

    row.editButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.editButton:SetSize(80, 20)
    row.editButton:SetPoint("RIGHT", -96, 0)
    row.editButton:SetText(L("EDIT"))

    row.removeButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.removeButton:SetSize(90, 20)
    row.removeButton:SetPoint("RIGHT", 0, 0)
    row.removeButton:SetText(L("REMOVE"))

    guildRows[index] = row
    return row
end

local function RefreshGuildAssignments()
    EnsureGuildLanguagesTable()

    local entries = CollectSortedEntries(LanguageScoutDB.guildLanguages, function(guildKey, lang)
        return { guildKey = guildKey, lang = lang }
    end, function(a, b)
        return a.guildKey < b.guildKey
    end)

    RefreshListRows(entries, guildRows, CreateGuildRow, guildListContainer, guildScrollFrame, guildEmptyText, guildRowStep, function(row, entry, index)
        local guildName, guildRealm = ParseGuildKey(entry.guildKey)
        local rowText = guildName or entry.guildKey
        local currentLang = LanguageScoutDB.guildLanguages[entry.guildKey]
        if guildRealm and guildRealm ~= "" then
            rowText = rowText .. " (" .. guildRealm .. ")"
        end
        if currentLang and currentLang ~= "" then
            rowText = rowText .. " - " .. GetLanguageDisplayName(currentLang)
        end

        row.text:SetText(rowText)

        row.editButton:SetScript("OnClick", function()
            StartGuildEdit(entry.guildKey, currentLang)
        end)

        row.removeButton:SetScript("OnClick", function()
            RemoveGuildAssignment(entry.guildKey)
            RefreshGuildAssignments()
        end)
    end)
end

addGuildButton:SetScript("OnClick", function()
    if TrySaveGuildAssignment(addGuildBox:GetText(), selectedGuildLanguage) then
        RefreshGuildAssignments()
    end
end)

BindEnterToButton(addGuildBox, addGuildButton)

local function RefreshGuildPanel()
    SetLanguageDropdownSelection(addGuildLangDropdown, selectedGuildLanguage)
    RefreshGuildAssignments()
end

local function QueueGuildPanelRefresh()
    QueuePanelRefresh(guildPanel, RefreshGuildPanel, 0, 0.05)
end

local function TryRefreshGuildPanelAfterLayout()
    if not guildPanel or not guildPanel:IsShown() then
        return
    end

    local width = guildPanel:GetWidth() or 0
    local height = guildPanel:GetHeight() or 0
    if width <= 0 or height <= 0 then
        return
    end

    RefreshGuildPanel()
end

guildPanel:SetScript("OnShow", function()
    RefreshGuildPanel()
    QueueGuildPanelRefresh()

    guildPanel:SetScript("OnUpdate", function(self)
        self:SetScript("OnUpdate", nil)
        if self:IsShown() then
            RefreshGuildPanel()
        end
    end)
end)

guildPanel:SetScript("OnSizeChanged", function()
    TryRefreshGuildPanelAfterLayout()
end)

ApplyMouseWheelScrolling(guildScrollFrame, guildListContainer, guildRowStep)

local resetTitle = resetPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
resetTitle:SetPoint("TOPLEFT", 16, -16)
resetTitle:SetText(GetPanelTitle("RESET"))

local resetDescription = resetPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
resetDescription:SetPoint("TOPLEFT", resetTitle, "BOTTOMLEFT", 0, -10)
resetDescription:SetWidth(520)
resetDescription:SetJustifyH("LEFT")
resetDescription:SetText(L("RESET_DESCRIPTION"))

local function RemoveSavedPlayerEntriesBySource(source, resultKey)
    local removedCount = 0
    if type(RemovePlayerLanguagesBySource) == "function" then
        removedCount = RemovePlayerLanguagesBySource(source)
    end
    PrintChatMessage(string.format(L(resultKey), removedCount))
end

StaticPopupDialogs["LANGUAGESCOUT_REMOVE_AUTOMATIC_ENTRIES"] = {
    text = L("REMOVE_AUTOMATIC_ENTRIES_CONFIRM"),
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        RemoveSavedPlayerEntriesBySource("automatic", "REMOVE_AUTOMATIC_ENTRIES_DONE")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["LANGUAGESCOUT_REMOVE_SYNC_ENTRIES"] = {
    text = L("REMOVE_SYNC_ENTRIES_CONFIRM"),
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        RemoveSavedPlayerEntriesBySource("sync", "REMOVE_SYNC_ENTRIES_DONE")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function WipeAllLanguageScoutData()
    wipe(LanguageScoutDB)
    wipe(CharacterDB)

    if ReloadUI then
        ReloadUI()
        return
    end

    if type(ns.EnsureDatabaseDefaults) == "function" then
        ns.EnsureDatabaseDefaults()
    end
    PrintChatMessage(L("WIPE_ALL_DATA_DONE"))
end

StaticPopupDialogs["LANGUAGESCOUT_WIPE_ALL_DATA"] = {
    text = L("WIPE_ALL_DATA_CONFIRM"),
    button1 = YES,
    button2 = NO,
    OnAccept = WipeAllLanguageScoutData,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local removeAutomaticEntriesButton = CreateFrame("Button", nil, resetPanel, "UIPanelButtonTemplate")
removeAutomaticEntriesButton:SetSize(460, 24)
removeAutomaticEntriesButton:SetPoint("TOPLEFT", resetDescription, "BOTTOMLEFT", 0, -20)
removeAutomaticEntriesButton:SetText(L("REMOVE_AUTOMATIC_ENTRIES"))
removeAutomaticEntriesButton:SetScript("OnClick", function()
    StaticPopup_Show("LANGUAGESCOUT_REMOVE_AUTOMATIC_ENTRIES")
end)

local removeSyncEntriesButton = CreateFrame("Button", nil, resetPanel, "UIPanelButtonTemplate")
removeSyncEntriesButton:SetSize(460, 24)
removeSyncEntriesButton:SetPoint("TOPLEFT", removeAutomaticEntriesButton, "BOTTOMLEFT", 0, -12)
removeSyncEntriesButton:SetText(L("REMOVE_SYNC_ENTRIES"))
removeSyncEntriesButton:SetScript("OnClick", function()
    StaticPopup_Show("LANGUAGESCOUT_REMOVE_SYNC_ENTRIES")
end)

local wipeAllDataButton = CreateFrame("Button", nil, resetPanel, "UIPanelButtonTemplate")
wipeAllDataButton:SetSize(460, 24)
wipeAllDataButton:SetPoint("TOPLEFT", removeSyncEntriesButton, "BOTTOMLEFT", 0, -28)
wipeAllDataButton:SetText(L("WIPE_ALL_DATA"))
wipeAllDataButton:GetFontString():SetTextColor(1, 0.25, 0.25)
wipeAllDataButton:SetScript("OnClick", function()
    StaticPopup_Show("LANGUAGESCOUT_WIPE_ALL_DATA")
end)

do
    local outgoingTitle = outgoingPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    outgoingTitle:SetPoint("TOPLEFT", 16, -16)
    outgoingTitle:SetText(GetPanelTitle("OUTGOING_MESSAGES"))

    local description = outgoingPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", outgoingTitle, "BOTTOMLEFT", 0, -12)
    description:SetWidth(560)
    description:SetJustifyH("LEFT")
    description:SetText(L("OUTGOING_MESSAGES_DESCRIPTION"))

    local master = CreateCheckbox(outgoingPanel, description, -16, "PREFIX_OUTGOING_MESSAGES", function(self)
        LanguageScoutDB.prefixOutgoingMessages = self:GetChecked() and true or false
        ns.RefreshOutgoingPrefixPanel()
    end)

    local preview = outgoingPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    preview:SetPoint("TOPLEFT", master, "BOTTOMLEFT", 4, -12)
    preview:SetWidth(560)
    preview:SetJustifyH("LEFT")

    local channelsTitle = outgoingPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    channelsTitle:SetPoint("TOPLEFT", preview, "BOTTOMLEFT", 0, -24)
    channelsTitle:SetText(L("OUTGOING_PREFIX_CHANNELS"))

    local checkboxes = {}
    for index, channel in ipairs(ns.CHAT_DETECTION_CHANNELS) do
        local checkbox = CreateCheckbox(outgoingPanel, channelsTitle, -10, channel.labelKey, function(self)
            ns.SetOutgoingPrefixChannelEnabled(channel.key, self:GetChecked())
        end)
        PlaceCheckboxInGrid(checkbox, channelsTitle, (index - 1) % 2, math.floor((index - 1) / 2))
        checkboxes[channel.key] = checkbox
    end

    ns.RefreshOutgoingPrefixPanel = function()
        local enabled = LanguageScoutDB.prefixOutgoingMessages ~= false
        master:SetChecked(enabled)
        local language = ns.GetOwnEffectiveLanguage()
        local tag = ns.IsSupportedLanguage(language) and ("[" .. language .. "]")
            or L("EFFECTIVE_LANGUAGE_UNAVAILABLE")
        preview:SetText(string.format(L("OUTGOING_PREFIX_PREVIEW"), tag))
        for key, checkbox in pairs(checkboxes) do
            checkbox:SetChecked(LanguageScoutDB.outgoingPrefixChannels[key] ~= false)
            checkbox:SetEnabled(enabled)
        end
    end
    outgoingPanel:SetScript("OnShow", ns.RefreshOutgoingPrefixPanel)
    ns.RefreshOutgoingPrefixPanel()
end

do
    local heading = nameplatePanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    heading:SetPoint("TOPLEFT", 16, -16)
    heading:SetText(GetPanelTitle("NAMEPLATES"))

    local description = nameplatePanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -12)
    description:SetWidth(560)
    description:SetJustifyH("LEFT")
    description:SetText(L("NAMEPLATES_DESCRIPTION"))

    local label = nameplatePanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -24)
    label:SetText(L("NAMEPLATE_FLAG_POSITION"))

    local positionDropdown = CreateFrame("Frame", nil, nameplatePanel, "UIDropDownMenuTemplate")
    positionDropdown:SetPoint("TOPLEFT", label, "BOTTOMLEFT", -16, -8)
    UIDropDownMenu_SetWidth(positionDropdown, 160)
    local labels = { off = "NAMEPLATE_FLAG_OFF", left = "NAMEPLATE_FLAG_LEFT", right = "NAMEPLATE_FLAG_RIGHT" }
    UIDropDownMenu_Initialize(positionDropdown, function()
        for _, position in ipairs({ "off", "left", "right" }) do
            local info = UIDropDownMenu_CreateInfo()
            info.text, info.value = L(labels[position]), position
            info.checked = LanguageScoutDB.nameplateFlagPosition == position
            info.func = function() ns.SetNameplateFlagPosition(position) end
            UIDropDownMenu_AddButton(info)
        end
    end)
    ns.RefreshNameplateOptions = function()
        local position = LanguageScoutDB.nameplateFlagPosition
        UIDropDownMenu_SetSelectedValue(positionDropdown, position)
        UIDropDownMenu_SetText(positionDropdown, L(labels[position] or labels.off))
    end
    nameplatePanel:SetScript("OnShow", ns.RefreshNameplateOptions)
    ns.RefreshNameplateOptions()
end

category = Settings.RegisterCanvasLayoutCategory(panel, "LanguageScout")
Settings.RegisterAddOnCategory(category)

languagesCategory = RegisterPanelCategory(category, languagesPanel, "LANGUAGES")
autoCategory = RegisterPanelCategory(category, autoDetectPanel, "AUTO_DETECT")
syncCategory = RegisterPanelCategory(category, syncPanel, "SYNC")
RegisterPanelCategory(category, outgoingPanel, "OUTGOING_MESSAGES")
RegisterPanelCategory(category, nameplatePanel, "NAMEPLATES")
guildCategory = RegisterPanelCategory(category, guildPanel, "GUILD_ASSIGNMENTS")
resetCategory = RegisterPanelCategory(category, resetPanel, "RESET")
RegisterPanelCategory(category, undonePanel, "UNDONE_GUESSES")
