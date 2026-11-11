local _, ns = ...

local L = ns.L
local FullName = ns.FullName
local UnitName = ns.ReadUnitName
local GetGuildContextForPlayerKey = ns.GetGuildContextForPlayerKey
local GetLanguageDisplayName = ns.GetLanguageDisplayName
local IsKnownEnemyPlayer = ns.IsKnownEnemyPlayer
local IsOpposingFactionUnit = ns.IsOpposingFactionUnit
local NormalizeGuildName = ns.NormalizeGuildName
local NormalizePlayerKey = ns.NormalizePlayerKey
local ResolveChatAuthorPlayerKey = ns.ResolveChatAuthorPlayerKey
local ParseFullName = ns.ParseFullName
local PrintChatMessage = ns.PrintChatMessage
local ResolveContextPlayer = ns.ResolveContextPlayer
local RemovePlayerLanguage = ns.RemovePlayerLanguage
local SetPlayerLanguage = ns.SetPlayerLanguage
local SetPlayerLanguagesBulk = ns.SetPlayerLanguagesBulk
local SetStoredGuildLanguage = ns.SetStoredGuildLanguage
local IsGuildChatFlagDisplayEnabled = ns.IsGuildChatFlagDisplayEnabled
local SUPPORTED_LANGUAGES = ns.SUPPORTED_LANGUAGES
local FLAG_TEXTURE_PREFIX = "Interface\\AddOns\\LanguageScout\\flags\\"
local flagTextureMarkupCache = {}
local playerLanguageLookupCache = {}
local playerLanguageLookupCacheSize = 0
local playerLanguageByShortName = {}
local playerLanguageCacheDirty = true
local PLAYER_LANGUAGE_LOOKUP_CACHE_LIMIT = 1000
local pendingGuildMarkRequest
local whoResultsRoutedToUi = false

local function SetWhoResultsRoutedToUi(enabled)
    if C_FriendList and C_FriendList.SetWhoToUi then
        C_FriendList.SetWhoToUi(enabled)
        whoResultsRoutedToUi = enabled
        return true
    end

    if SetWhoToUI then
        SetWhoToUI(enabled)
        whoResultsRoutedToUi = enabled
        return true
    end

    return false
end

local function ResetWhoResultsRouting()
    if whoResultsRoutedToUi then
        SetWhoResultsRoutedToUi(false)
    end
end

local function ClearPlayerLanguageLookupCache()
    wipe(playerLanguageLookupCache)
    playerLanguageLookupCacheSize = 0
end

local function RememberPlayerLanguageLookup(cacheKey, lang)
    if playerLanguageLookupCache[cacheKey] == nil then
        if playerLanguageLookupCacheSize >= PLAYER_LANGUAGE_LOOKUP_CACHE_LIMIT then
            ClearPlayerLanguageLookupCache()
        end

        playerLanguageLookupCacheSize = playerLanguageLookupCacheSize + 1
    end

    playerLanguageLookupCache[cacheKey] = lang or false
end

local function RebuildPlayerLanguageCache()
    wipe(playerLanguageByShortName)

    for storedPlayerKey, record in pairs(LanguageScoutDB.players) do
        local storedLang = type(record) == "table" and record.lang or nil
        local storedShortName = ParseFullName(storedPlayerKey)
        if storedShortName and storedLang then
            local existingLang = playerLanguageByShortName[storedShortName]
            if existingLang == nil then
                playerLanguageByShortName[storedShortName] = storedLang
            elseif existingLang ~= storedLang then
                -- A realm-less name is unsafe when the same short name has
                -- conflicting language assignments on different realms.
                playerLanguageByShortName[storedShortName] = false
            end
        end
    end

    playerLanguageCacheDirty = false
end

local function GetPlayerLanguage(rawName, allowShortNameFallback)
    if ns.IsSecret(rawName) then return end
    if not rawName or rawName == "" then
        return
    end

    if not allowShortNameFallback or ns.UsesSurnames then
        local playerKey = NormalizePlayerKey(rawName)
        local record = playerKey and LanguageScoutDB.players[playerKey]
        return record and record.lang
    end

    local cacheKey = rawName
    local cachedLang = playerLanguageLookupCache[cacheKey]
    if cachedLang ~= nil then
        return cachedLang or nil
    end

    local playerKey = NormalizePlayerKey(rawName)
    if playerKey and LanguageScoutDB.players[playerKey] then
        local lang = LanguageScoutDB.players[playerKey].lang
        RememberPlayerLanguageLookup(cacheKey, lang)
        return lang
    end

    -- Group browser entries may omit the realm, so we keep a short-name cache
    -- instead of rescanning the whole player table on every visible row update.
    -- Chat and tooltip paths intentionally skip this fallback to stay O(1).
    local shortName = ParseFullName and ParseFullName(rawName)
    if not shortName then
        RememberPlayerLanguageLookup(cacheKey, nil)
        return
    end

    if playerLanguageCacheDirty then
        RebuildPlayerLanguageCache()
    end

    local lang = playerLanguageByShortName[shortName]
    RememberPlayerLanguageLookup(cacheKey, lang)
    return lang or nil
end

ns.MarkPlayerLanguageCacheDirty = function()
    playerLanguageCacheDirty = true
    if playerLanguageLookupCacheSize > 0 then
        ClearPlayerLanguageLookupCache()
    end
end

local function GetFlagTextureMarkup(lang, size)
    if not lang then
        return ""
    end

    size = size or 14
    local cacheKey = lang .. ":" .. size
    local cachedMarkup = flagTextureMarkupCache[cacheKey]
    if cachedMarkup then
        return cachedMarkup
    end

    cachedMarkup = "|T" .. FLAG_TEXTURE_PREFIX .. lang .. ".tga:" .. size .. "|t"
    flagTextureMarkupCache[cacheKey] = cachedMarkup
    return cachedMarkup
end

local function EnsureLegacyLFGFlagTexture(row, region)
    if not row or row.LanguageScoutLegacyFlag then
        return row and row.LanguageScoutLegacyFlag
    end

    if not region or type(row.CreateTexture) ~= "function" then
        return
    end

    local texture = row:CreateTexture(nil, "OVERLAY")
    texture:SetSize(16, 12)
    texture:SetPoint("LEFT", region, "RIGHT", 4, 0)
    texture:Hide()
    row.LanguageScoutLegacyFlag = texture
    return texture
end

local function ResetLegacyLFGRowFlag(row)
    if row and row.LanguageScoutLegacyFlag then
        row.LanguageScoutLegacyFlag:Hide()
    end
end

local function UpdateLegacyLFGRowFlag(row, lang)
    if not row or not row.Name or type(row.Name.GetText) ~= "function" then
        return
    end

    local texture = EnsureLegacyLFGFlagTexture(row, row.Name)
    if not texture then
        return
    end

    if not lang then
        texture:Hide()
        return
    end

    texture:SetTexture(FLAG_TEXTURE_PREFIX .. lang .. ".tga")
    texture:Show()
end

local legacyLFGBrowseHookRegistered = false
local legacyLFGUpdateHookRegistered = false
local legacyLFGEntryInitHookRegistered = false
local legacyLFGFlagRows = {}

local function IsFrame(value)
    if type(value) ~= "table" then
        return false
    end

    if type(value.GetObjectType) ~= "function" or type(value.CreateTexture) ~= "function" then
        return false
    end

    local ok, objectType = pcall(value.GetObjectType, value)
    if not ok then
        return false
    end

    return objectType == "Frame" or objectType == "Button"
end

local function VisitFrameTree(frame, visitor, visited)
    if not IsFrame(frame) or visited[frame] then
        return
    end

    visited[frame] = true
    visitor(frame)

    for _, region in ipairs({ frame:GetRegions() }) do
        visitor(region, frame)
    end

    for _, child in ipairs({ frame:GetChildren() }) do
        VisitFrameTree(child, visitor, visited)
    end
end

local function IsLegacyLFGResultRow(frame)
    return IsFrame(frame)
        and type(frame.resultID) == "number"
        and frame.Name
        and type(frame.Name.GetText) == "function"
end

local function GetLegacyLFGLeaderLanguage(resultID)
    if not resultID or not C_LFGList or not C_LFGList.GetSearchResultLeaderInfo then
        return
    end

    local leaderInfo = C_LFGList.GetSearchResultLeaderInfo(resultID)
    if not leaderInfo then
        return
    end

    local leaderName = leaderInfo.name or leaderInfo.leaderName or leaderInfo.fullName
    return leaderName and GetPlayerLanguage(leaderName, true)
end

local function UpdateLegacyLFGEntryRow(frame)
    if not IsLegacyLFGResultRow(frame) then
        return
    end

    local lang = GetLegacyLFGLeaderLanguage(frame.resultID)
    if lang then
        UpdateLegacyLFGRowFlag(frame, lang)
        legacyLFGFlagRows[frame] = true
    else
        ResetLegacyLFGRowFlag(frame)
        legacyLFGFlagRows[frame] = nil
    end
end

local function UpdateLegacyLFGBrowseText()
    local debugStart = ns.DebugPerfStart and ns.DebugPerfStart()
    local browseFrame = _G.LFGBrowseFrame
    if not browseFrame or not browseFrame:IsVisible() or LanguageScoutDB.displayFlagsInLFG == false then
        for row in pairs(legacyLFGFlagRows) do
            ResetLegacyLFGRowFlag(row)
        end
        wipe(legacyLFGFlagRows)
        if ns.DebugPerfStop then
            ns.DebugPerfStop("LFG:UpdateBrowseText", debugStart, "hidden or disabled")
        end
        return
    end

    for row in pairs(legacyLFGFlagRows) do
        ResetLegacyLFGRowFlag(row)
    end
    wipe(legacyLFGFlagRows)

    -- Classic reuses visible browser rows while scrolling, so stale flag
    -- textures must be cleared before we apply them to the current results.
    local visited = {}
    VisitFrameTree(browseFrame, function(frame)
        if not IsLegacyLFGResultRow(frame) then
            return
        end

        if type(frame.IsVisible) == "function" and not frame:IsVisible() then
            return
        end

        UpdateLegacyLFGEntryRow(frame)
    end, visited)

    if ns.DebugPerfStop then
        ns.DebugPerfStop("LFG:UpdateBrowseText", debugStart)
    end
end

local function RegisterLegacyLFGHooks()
    if legacyLFGBrowseHookRegistered then
        return
    end

    local browseFrame = _G.LFGBrowseFrame
    if not IsFrame(browseFrame) then
        return
    end

    -- Classic updates browser rows through UpdateResults and entry init, so
    -- these hooks are enough to keep flags in sync without retail-only paths.
    if not legacyLFGUpdateHookRegistered and type(browseFrame.UpdateResults) == "function" then
        hooksecurefunc(browseFrame, "UpdateResults", function()
            UpdateLegacyLFGBrowseText()
        end)
        legacyLFGUpdateHookRegistered = true
    end

    if not legacyLFGEntryInitHookRegistered and type(LFGBrowseSearchEntry_Init) == "function" then
        hooksecurefunc("LFGBrowseSearchEntry_Init", function(entry)
            UpdateLegacyLFGEntryRow(entry)
        end)
        legacyLFGEntryInitHookRegistered = true
    end

    browseFrame:HookScript("OnShow", function()
        UpdateLegacyLFGBrowseText()
    end)
    legacyLFGBrowseHookRegistered = true
end

local function TryRegisterLFGHooks()
    if not hooksecurefunc then
        return
    end

    RegisterLegacyLFGHooks()
end

local function HandleTooltipSetUnit(self, forceDebugOutput)
    local _, unit = self:GetUnit()
    if ns.IsSecret(unit) or not ns.CanInspectUnit(unit) then return nil, "RestrictedUnit" end
    if not unit then
        return nil, "NoUnit"
    end

    if not UnitIsPlayer(unit) then
        ns.TryAutoDetectFromUnit(unit)
        return unit, "NonPlayer"
    end

    local name, realm = UnitName(unit)
    if not name then
        return unit, "UnnamedPlayer"
    end

    local lookupStart = ns.DebugPerfStart and ns.DebugPerfStart()
    local fullName = FullName(name, realm)
    local lang = GetPlayerLanguage(fullName, false)
    local playerState = lang and "KnownPlayer" or "UnknownPlayer"
    if not lang then
        ns.TryAutoDetectFromUnit(unit, fullName)
    end

    if LanguageScoutDB.displayFlagsInTooltip == false then
        if ns.DebugPerfStop then
            ns.DebugPerfStop("Tooltip:LanguageLookup:" .. playerState, lookupStart, unit .. ", flags disabled", forceDebugOutput)
        end
        return unit, playerState
    end

    if not lang then
        lang = GetPlayerLanguage(fullName, false)
    end
    if ns.DebugPerfStop then
        ns.DebugPerfStop("Tooltip:LanguageLookup:" .. playerState, lookupStart, unit, forceDebugOutput)
    end
    if not lang then
        return unit, playerState
    end

    local renderStart = ns.DebugPerfStart and ns.DebugPerfStart()
    self:AddLine(" ")
    self:AddLine(L("LANGUAGE") .. ": " .. GetFlagTextureMarkup(lang, 16) .. " " .. GetLanguageDisplayName(lang))
    self:Show()
    if ns.DebugPerfStop then
        ns.DebugPerfStop("Tooltip:LanguageRender:" .. playerState, renderStart, unit, forceDebugOutput)
    end
    return unit, playerState
end

local function OnTooltipSetUnit(self)
    local forceDebugOutput = ns.ConsumeTooltipDebugTrace and ns.ConsumeTooltipDebugTrace()
    local debugStart = ns.DebugPerfStart and ns.DebugPerfStart()
    local unit, playerState = HandleTooltipSetUnit(self, forceDebugOutput)
    if ns.DebugPerfStop then
        ns.DebugPerfStop("Tooltip:SetUnit:" .. (playerState or "Unknown"), debugStart, unit, forceDebugOutput)
    end
end

local hasModernUnitTooltipHook = TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
    and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit

-- TBC exposes parts of the modern tooltip API, but its reliable unit-tooltip
-- notification remains OnTooltipSetUnit. Prefer the modern post-call only on
-- Forever, where the legacy script is unavailable; keep it as a final fallback
-- for clients that do not expose the legacy script at all.
if ns.UsesSurnames and hasModernUnitTooltipHook then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
        if tooltip == GameTooltip then OnTooltipSetUnit(tooltip) end
    end)
elseif GameTooltip:HasScript("OnTooltipSetUnit") then
    GameTooltip:HookScript("OnTooltipSetUnit", OnTooltipSetUnit)
elseif hasModernUnitTooltipHook then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
        if tooltip == GameTooltip then OnTooltipSetUnit(tooltip) end
    end)
end

local function ChatFilter(_, event, msg, author, ...)
    if ns.IsSecret(msg) then return false, msg, author, ... end
    local debugStart = ns.DebugPerfStart and ns.DebugPerfStart()

    if LanguageScoutDB.displayFlagsInChat == false then
        if ns.DebugPerfStop then
            ns.DebugPerfStop("ChatFilter:" .. tostring(event), debugStart, "flags disabled")
        end
        return false, msg, author, ...
    end

    if event == "CHAT_MSG_GUILD" and not IsGuildChatFlagDisplayEnabled() then
        if ns.DebugPerfStop then
            ns.DebugPerfStop("ChatFilter:" .. tostring(event), debugStart, "guild flags disabled")
        end
        return false, msg, author, ...
    end

    local guid = select(10, ...)
    local playerKey = ResolveChatAuthorPlayerKey(author, guid)
    local record = playerKey and LanguageScoutDB.players[playerKey]
    local lang = record and record.lang
    if lang then
        msg = GetFlagTextureMarkup(lang, 14) .. " " .. msg
    end

    if ns.DebugPerfStop then
        ns.DebugPerfStop("ChatFilter:" .. tostring(event), debugStart, playerKey)
    end

    return false, msg, author, ...
end

for _, eventName in ipairs({
    "CHAT_MSG_CHANNEL",
    "CHAT_MSG_GUILD",
    "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_INSTANCE_CHAT",
    "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_SAY",
    "CHAT_MSG_YELL",
}) do
    ChatFrame_AddMessageEventFilter(eventName, ChatFilter)
end

local function RegisterContextMenu(menuName)
    Menu.ModifyMenu(menuName, function(_, rootDescription, contextData)
        local fullName = ResolveContextPlayer(contextData)
        if not fullName then
            return
        end

        local contextGuildName
        local contextGuildRealm
        if contextData and ns.CanInspectUnit(contextData.unit) and UnitIsPlayer(contextData.unit) then
            local _, playerRealm = UnitName(contextData.unit)
            contextGuildRealm = playerRealm
            contextGuildName = GetGuildInfo and GetGuildInfo(contextData.unit)
        else
            contextGuildName, contextGuildRealm = GetGuildContextForPlayerKey(fullName)
        end

        rootDescription:CreateDivider()
        rootDescription:CreateTitle(L("SET_LANGUAGE"))

        for _, lang in ipairs(SUPPORTED_LANGUAGES) do
            if ns.IsLanguageMarkEnabled(lang) then
                rootDescription:CreateButton(GetLanguageDisplayName(lang), function()
                    SetPlayerLanguage(fullName, lang, true, "manual")
                    ns.ShowManualLanguageMarkedMessage(fullName, lang)
                end)
            end
        end

        if contextGuildName then
            local isEnemy = IsKnownEnemyPlayer and IsKnownEnemyPlayer(fullName) or false
            if contextData
                and contextData.unit
                and UnitExists(contextData.unit)
                and IsOpposingFactionUnit
            then
                isEnemy = IsOpposingFactionUnit(contextData.unit)
            end

            local guildSubmenu
            for _, lang in ipairs(SUPPORTED_LANGUAGES) do
                if ns.IsLanguageMarkEnabled(lang) then
                    guildSubmenu = guildSubmenu or rootDescription:CreateButton(L("MARK_GUILD"), function() end)
                    guildSubmenu:CreateButton(GetLanguageDisplayName(lang), function()
                        StaticPopup_Show("LANGUAGESCOUT_MARK_GUILD", nil, nil, {
                            guildName = contextGuildName,
                            guildRealm = contextGuildRealm,
                            lang = lang,
                            playerKey = fullName,
                            isEnemy = isEnemy,
                        })
                    end)
                end
            end
        end

        rootDescription:CreateButton(L("REMOVE"), function()
            RemovePlayerLanguage(fullName)
        end)
    end)
end

if Menu and Menu.ModifyMenu then
    for _, menuName in ipairs({
        "MENU_UNIT_PLAYER",
        "MENU_UNIT_ENEMY_PLAYER",
        "MENU_UNIT_FRIEND",
        "MENU_UNIT_PARTY",
        "MENU_UNIT_RAID_PLAYER",
        "MENU_UNIT_GUILD",
        "MENU_UNIT_CHAT_ROSTER",
        "MENU_UNIT_COMMUNITIES_CHAT",
        "MENU_UNIT_CHAT_LINE",
        "MENU_CHAT_ROSTER",
        "MENU_CHAT_LINE",
    }) do
        RegisterContextMenu(menuName)
    end
end

local function BuildGuildWhoQuery(guildName)
    local normalizedGuildName = NormalizeGuildName(guildName)
    if not normalizedGuildName then
        return
    end

    return string.format('g-"%s"', normalizedGuildName)
end

local function StartGuildWhoMarking(requestData)
    if not requestData or not ns.IsSupportedLanguage(requestData.lang) then
        return
    end

    if pendingGuildMarkRequest and not requestData.isEnemy then
        PrintChatMessage(L("MARK_GUILD_BUSY"))
        return
    end

    local query = BuildGuildWhoQuery(requestData.guildName)
    if not query then
        return
    end

    if not SetStoredGuildLanguage(requestData.guildName, requestData.guildRealm, requestData.lang) then
        return
    end

    if requestData.playerKey then
        SetPlayerLanguage(requestData.playerKey, requestData.lang, false, "guild")
    end

    if requestData.isEnemy then
        PrintChatMessage(string.format(
            L("MARK_GUILD_SAVED"),
            NormalizeGuildName(requestData.guildName),
            GetLanguageDisplayName(requestData.lang)
        ))
        return
    end

    local sendWhoQuery
    if C_FriendList and C_FriendList.SendWho then
        sendWhoQuery = C_FriendList.SendWho
    elseif SendWho then
        sendWhoQuery = SendWho
    end

    if not sendWhoQuery then
        PrintChatMessage(L("MARK_GUILD_UNAVAILABLE"))
        return
    end

    pendingGuildMarkRequest = {
        guildName = NormalizeGuildName(requestData.guildName),
        lang = requestData.lang,
    }
    local activeRequest = pendingGuildMarkRequest

    if C_Timer and C_Timer.After then
        C_Timer.After(10, function()
            if pendingGuildMarkRequest == activeRequest then
                pendingGuildMarkRequest = nil
                ResetWhoResultsRouting()
                PrintChatMessage(L("MARK_GUILD_TIMEOUT"))
            end
        end)
    end

    PrintChatMessage(string.format(L("MARK_GUILD_STARTED"), pendingGuildMarkRequest.guildName, GetLanguageDisplayName(requestData.lang)))

    -- Route results through the WHO result list. This avoids chat spam
    -- without suppressing unrelated CHAT_MSG_SYSTEM messages.
    SetWhoResultsRoutedToUi(true)

    local ok = pcall(sendWhoQuery, query)
    if not ok then
        pendingGuildMarkRequest = nil
        ResetWhoResultsRouting()
        PrintChatMessage(L("MARK_GUILD_UNAVAILABLE"))
    end
end

StaticPopupDialogs["LANGUAGESCOUT_MARK_GUILD"] = {
    text = " ",
    button1 = YES,
    button2 = NO,
    OnShow = function(self, data)
        if data and self.Text then
            self.Text:SetFormattedText(L("MARK_GUILD_CONFIRM"), data.guildName, GetLanguageDisplayName(data.lang))
        end
    end,
    OnAccept = function(_, data)
        StartGuildWhoMarking(data)
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = STATICPOPUP_NUMDIALOGS,
}

local function GetWhoResult(index)
    if C_FriendList and C_FriendList.GetWhoInfo then
        local info = C_FriendList.GetWhoInfo(index)
        if info then
            return info.fullName or info.name, info.fullGuildName or info.guild or info.guildName
        end
    end

    if GetWhoInfo then
        local playerName, guildName = GetWhoInfo(index)
        return playerName, guildName
    end
end

local guildWhoFrame = CreateFrame("Frame")
guildWhoFrame:RegisterEvent("WHO_LIST_UPDATE")
guildWhoFrame:SetScript("OnEvent", function()
    local requestData = pendingGuildMarkRequest
    if not requestData then
        return
    end

    local resultCount = 0
    if C_FriendList and C_FriendList.GetNumWhoResults then
        resultCount = C_FriendList.GetNumWhoResults() or 0
    elseif GetNumWhoResults then
        resultCount = GetNumWhoResults() or 0
    end

    -- WHO results arrive asynchronously and may include similarly named guilds
    -- on other realms, so we re-check the normalized guild name before marking.
    local matchedPlayerKeys = {}
    local matchedPlayerLookup = {}
    for index = 1, resultCount do
        local playerName, guildName = GetWhoResult(index)
        if playerName and NormalizeGuildName(guildName) == requestData.guildName then
            local playerKey = NormalizePlayerKey(playerName)
            if playerKey and not matchedPlayerLookup[playerKey] then
                matchedPlayerLookup[playerKey] = true
                matchedPlayerKeys[#matchedPlayerKeys + 1] = playerKey
            end
        end
    end

    -- WHO_LIST_UPDATE is global and can also belong to the player or another
    -- addon. Keep waiting when the result set does not contain our guild.
    if #matchedPlayerKeys == 0 then
        return
    end

    pendingGuildMarkRequest = nil
    ResetWhoResultsRouting()

    local markedCount = SetPlayerLanguagesBulk and SetPlayerLanguagesBulk(matchedPlayerKeys, requestData.lang, "guild") or 0
    if not SetPlayerLanguagesBulk then
        for _, playerKey in ipairs(matchedPlayerKeys) do
            if SetPlayerLanguage(playerKey, requestData.lang, false, "guild") then
                markedCount = markedCount + 1
            end
        end
    end

    PrintChatMessage(string.format(L("MARK_GUILD_RESULT"), markedCount, requestData.guildName, GetLanguageDisplayName(requestData.lang)))
end)

local lfgHookFrame = CreateFrame("Frame")
lfgHookFrame:RegisterEvent("PLAYER_LOGIN")
lfgHookFrame:RegisterEvent("ADDON_LOADED")
lfgHookFrame:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
lfgHookFrame:RegisterEvent("LFG_LIST_APPLICANT_LIST_UPDATED")
lfgHookFrame:RegisterEvent("LFG_LIST_APPLICANT_UPDATED")
lfgHookFrame:SetScript("OnEvent", function()
    TryRegisterLFGHooks()
    UpdateLegacyLFGBrowseText()
end)
