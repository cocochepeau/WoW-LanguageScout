-- =========================================
-- LanguageScout
-- Anniversary-Client (neues Menu + Settings API)
-- =========================================

local addonName, ns = ...

-- Forever uses regional first-name/surname identities, not name/realm pairs.
local interfaceVersion = GetBuildInfo and select(4, GetBuildInfo())
ns.UsesSurnames = RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled()
    or (interfaceVersion and interfaceVersion >= 16000 and interfaceVersion < 20000) or false
ns.IsSecret = function(value)
    if issecretvalue and issecretvalue(value) then
        return true
    end
    if canaccessvalue and canaccessvalue(value) ~= true then
        return true
    end
    return false
end
ns.CanInspectUnit = function(unit)
    if ns.IsSecret(unit) or not unit then return false end
    if UnitGUID and ns.IsSecret(UnitGUID(unit)) then return false end
    if UnitIsPlayer and ns.IsSecret(UnitIsPlayer(unit)) then return false end
    return true
end

if type(LanguageScoutDB) ~= "table" then
    LanguageScoutDB = {}
end
if type(LanguageScoutDB.players) ~= "table" then
    LanguageScoutDB.players = {}
end
if type(LanguageScoutCharacterDB) ~= "table" then
    LanguageScoutCharacterDB = {}
end

local CharacterDB = LanguageScoutCharacterDB

-- Retain language-sharing compatibility with users on older addon releases.
local ADDON_PREFIX = "LMARK"
local ADDON_VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version"))
    or (GetAddOnMetadata and GetAddOnMetadata(addonName, "Version"))
    or "0"
local SUPPORTED_LANGUAGES = { "DE", "ES", "RU", "UA", "FR", "IT", "SV", "NO", "DA", "TR", "PL", "PT", "NL", "CZSK" }
local SUPPORTED_LANGUAGE_LOOKUP = {}
local DEFAULT_MARK_DISABLED_LANGUAGES = {
    IT = true,
    SV = true,
    NO = true,
    DA = true,
    TR = true,
    PL = true,
    PT = true,
    NL = true,
    CZSK = true,
}
local CLIENT_LANGUAGE_BY_LOCALE = {
    deDE = "DE",
    esES = "ES",
    esMX = "ES",
    frFR = "FR",
    itIT = "IT",
    ptBR = "PT",
    ptPT = "PT",
    ruRU = "RU",
    ukUA = "UA",
    svSE = "SV",
    nbNO = "NO",
    nnNO = "NO",
    daDK = "DA",
    trTR = "TR",
    plPL = "PL",
    nlNL = "NL",
    csCZ = "CZSK",
    skSK = "CZSK",
}

local L = ns.L
local GetLanguageDisplayName = ns.GetLanguageDisplayName

for _, lang in ipairs(SUPPORTED_LANGUAGES) do
    SUPPORTED_LANGUAGE_LOOKUP[lang] = true
end

ns.ADDON_PREFIX = ADDON_PREFIX
ns.ADDON_VERSION = ADDON_VERSION
ns.CharacterDB = CharacterDB
ns.SUPPORTED_LANGUAGES = SUPPORTED_LANGUAGES
ns.RefreshAutoDetectPanel = ns.RefreshAutoDetectPanel or function() end
ns.MarkKnownPlayersDirty = ns.MarkKnownPlayersDirty or function() end
ns.MarkUndoneGuessesDirty = ns.MarkUndoneGuessesDirty or function() end
ns.RefreshOwnLanguageDisplay = ns.RefreshOwnLanguageDisplay or function() end
ns.SyncNewPlayerLanguage = ns.SyncNewPlayerLanguage or function() end
ns.SyncOwnLanguage = ns.SyncOwnLanguage or function() end
ns.TryAutoDetectFromUnit = ns.TryAutoDetectFromUnit or function() end
ns.RequestLanguageFromUnit = ns.RequestLanguageFromUnit or function() end

local function IsSupportedLanguage(lang)
    return SUPPORTED_LANGUAGE_LOOKUP[lang] == true
end

ns.IsSupportedLanguage = IsSupportedLanguage

local function GetStoredPlayerLanguage(playerKey)
    local record = playerKey and LanguageScoutDB.players[playerKey]
    if type(record) == "table" and IsSupportedLanguage(record.lang) then
        return record.lang
    end
end

ns.GetStoredPlayerLanguage = GetStoredPlayerLanguage

local function GetDefaultLanguageMarkEnabled(lang)
    return IsSupportedLanguage(lang) and not DEFAULT_MARK_DISABLED_LANGUAGES[lang]
end

ns.GetDefaultLanguageMarkEnabled = GetDefaultLanguageMarkEnabled

local function SetLanguageDropdownSelection(dropdown, lang)
    UIDropDownMenu_SetSelectedValue(dropdown, lang)
    if lang then
        UIDropDownMenu_SetText(dropdown, GetLanguageDisplayName(lang))
    else
        UIDropDownMenu_SetText(dropdown, L("AUTO_LANGUAGE"))
    end
end

ns.SetLanguageDropdownSelection = SetLanguageDropdownSelection

local function Trim(value)
    if ns.IsSecret(value) or type(value) ~= "string" then
        return
    end

    return value:match("^%s*(.-)%s*$")
end

ns.Trim = Trim

local function PrintChatMessage(message)
    if not message or message == "" then
        return
    end

    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(message)
    else
        print(message)
    end
end

ns.PrintChatMessage = PrintChatMessage

local function NormalizeRealm(realm)
    local cleanedRealm = Trim(realm)
    if not cleanedRealm or cleanedRealm == "" then
        return
    end

    return cleanedRealm:gsub("%s+", "")
end

ns.NormalizeRealm = NormalizeRealm

local cachedPlayerRealm

local function ReadPlayerRealm()
    local normalizedRealm = GetNormalizedRealmName and GetNormalizedRealmName()
    if normalizedRealm and normalizedRealm ~= "" then
        return NormalizeRealm(normalizedRealm)
    end

    local realmName = GetRealmName and GetRealmName()
    return NormalizeRealm(realmName)
end

local function GetPlayerRealm()
    if cachedPlayerRealm and cachedPlayerRealm ~= "" then
        return cachedPlayerRealm
    end

    cachedPlayerRealm = ReadPlayerRealm()
    return cachedPlayerRealm
end

ns.GetPlayerRealm = GetPlayerRealm

ns.RefreshPlayerRealm = function()
    local previousRealm = cachedPlayerRealm
    cachedPlayerRealm = ReadPlayerRealm()
    if cachedPlayerRealm ~= previousRealm then
        if type(ns.ClearPlayerNameCache) == "function" then
            ns.ClearPlayerNameCache()
        end
        if type(ns.MarkPlayerLanguageCacheDirty) == "function" then
            ns.MarkPlayerLanguageCacheDirty()
        end
    end

    return cachedPlayerRealm
end

local function EnsureAutoDetectWordsTable()
    if type(LanguageScoutDB.autoDetectWords) ~= "table" then
        LanguageScoutDB.autoDetectWords = {}
    end

    for lang, words in pairs(LanguageScoutDB.autoDetectWords) do
        if not IsSupportedLanguage(lang) or type(words) ~= "table" then
            LanguageScoutDB.autoDetectWords[lang] = nil
        else
            local cleanedWords = {}
            local seenWords = {}
            for _, word in ipairs(words) do
                local cleanedWord = Trim(word)
                if cleanedWord and cleanedWord ~= "" and not seenWords[cleanedWord] then
                    table.insert(cleanedWords, cleanedWord)
                    seenWords[cleanedWord] = true
                end
            end
            LanguageScoutDB.autoDetectWords[lang] = cleanedWords
        end
    end
end

ns.EnsureAutoDetectWordsTable = EnsureAutoDetectWordsTable

local function EnsureLanguageOptionsTable()
    if type(LanguageScoutDB.languageOptions) ~= "table" then
        LanguageScoutDB.languageOptions = {}
    end

    for lang in pairs(LanguageScoutDB.languageOptions) do
        if not IsSupportedLanguage(lang) then
            LanguageScoutDB.languageOptions[lang] = nil
        end
    end

    for _, lang in ipairs(SUPPORTED_LANGUAGES) do
        local options = LanguageScoutDB.languageOptions[lang]
        if type(options) ~= "table" then
            options = {}
            LanguageScoutDB.languageOptions[lang] = options
        end

        if options.mark == nil then
            options.mark = GetDefaultLanguageMarkEnabled(lang)
        else
            options.mark = options.mark ~= false
        end
        options.autoDetect = options.autoDetect ~= false
    end
end

ns.EnsureLanguageOptionsTable = EnsureLanguageOptionsTable

local function IsLanguageMarkEnabled(lang)
    if not IsSupportedLanguage(lang) then
        return false
    end

    local languageOptions = LanguageScoutDB.languageOptions
    local options = type(languageOptions) == "table" and languageOptions[lang]
    if type(options) ~= "table" or options.mark == nil then
        return GetDefaultLanguageMarkEnabled(lang)
    end

    return options.mark ~= false
end

ns.IsLanguageMarkEnabled = IsLanguageMarkEnabled

local function IsLanguageAutoDetectEnabled(lang)
    if not IsSupportedLanguage(lang) then
        return false
    end

    local languageOptions = LanguageScoutDB.languageOptions
    local options = type(languageOptions) == "table" and languageOptions[lang]
    return type(options) ~= "table" or options.autoDetect ~= false
end

ns.IsLanguageAutoDetectEnabled = IsLanguageAutoDetectEnabled

local function SetLanguageOption(lang, optionName, enabled)
    if not IsSupportedLanguage(lang) then
        return false
    end

    EnsureLanguageOptionsTable()
    LanguageScoutDB.languageOptions[lang][optionName] = enabled and true or false
    if optionName == "autoDetect" and ns.ClearAutoDetectTextCache then
        ns.ClearAutoDetectTextCache()
    end
    return true
end

ns.SetLanguageMarkEnabled = function(lang, enabled)
    return SetLanguageOption(lang, "mark", enabled)
end

ns.SetLanguageAutoDetectEnabled = function(lang, enabled)
    return SetLanguageOption(lang, "autoDetect", enabled)
end

local function EnsureCharacterDatabaseDefaults()
    -- Preserve the existing global preference as the initial value for each
    -- character. The legacy value stays available for characters that log in later.
    if CharacterDB.displayFlagsInGuild == nil then
        CharacterDB.displayFlagsInGuild = LanguageScoutDB.displayFlagsInGuild ~= false
    end
end

ns.IsGuildChatFlagDisplayEnabled = function()
    return CharacterDB.displayFlagsInGuild ~= false
end

local CHAT_DETECTION_CHANNELS = {
    { key = "channel", labelKey = "AUTO_DETECT_CHANNEL_PUBLIC" },
    { key = "guild", labelKey = "AUTO_DETECT_CHANNEL_GUILD" },
    { key = "party", labelKey = "AUTO_DETECT_CHANNEL_PARTY" },
    { key = "raid", labelKey = "AUTO_DETECT_CHANNEL_RAID" },
    { key = "instance", labelKey = "AUTO_DETECT_CHANNEL_INSTANCE" },
    { key = "say", labelKey = "AUTO_DETECT_CHANNEL_SAY" },
    { key = "yell", labelKey = "AUTO_DETECT_CHANNEL_YELL" },
}
local CHAT_DETECTION_CHANNEL_BY_EVENT = {
    CHAT_MSG_CHANNEL = "channel",
    CHAT_MSG_GUILD = "guild",
    CHAT_MSG_PARTY = "party",
    CHAT_MSG_PARTY_LEADER = "party",
    CHAT_MSG_RAID = "raid",
    CHAT_MSG_RAID_LEADER = "raid",
    CHAT_MSG_INSTANCE_CHAT = "instance",
    CHAT_MSG_INSTANCE_CHAT_LEADER = "instance",
    CHAT_MSG_SAY = "say",
    CHAT_MSG_YELL = "yell",
}
local chatDetectionChannelKeys = {}
for _, channel in ipairs(CHAT_DETECTION_CHANNELS) do
    chatDetectionChannelKeys[channel.key] = true
end
ns.CHAT_DETECTION_CHANNELS = CHAT_DETECTION_CHANNELS

local function EnsureChatDetectionChannels()
    if type(LanguageScoutDB.chatDetectionChannels) ~= "table" then
        LanguageScoutDB.chatDetectionChannels = {}
    end
    local channels = LanguageScoutDB.chatDetectionChannels
    for key in pairs(channels) do
        if not chatDetectionChannelKeys[key] then channels[key] = nil end
    end
    for key in pairs(chatDetectionChannelKeys) do
        channels[key] = channels[key] ~= false
    end
end

ns.SetChatDetectionChannelEnabled = function(key, enabled)
    if not chatDetectionChannelKeys[key] then return false end
    EnsureChatDetectionChannels()
    LanguageScoutDB.chatDetectionChannels[key] = enabled and true or false
    return true
end

ns.IsChatDetectionChannelEnabled = function(event)
    if not LanguageScoutDB.autoDetect then return false end
    local key = CHAT_DETECTION_CHANNEL_BY_EVENT[event]
    if not key then return false end
    local channels = LanguageScoutDB.chatDetectionChannels
    return type(channels) ~= "table" or channels[key] ~= false
end

local OUTGOING_CHANNEL_KEYS = {
    CHANNEL = "channel", GUILD = "guild", PARTY = "party", RAID = "raid",
    INSTANCE_CHAT = "instance", SAY = "say", YELL = "yell",
}

local function EnsureOutgoingPrefixChannels()
    if type(LanguageScoutDB.outgoingPrefixChannels) ~= "table" then
        LanguageScoutDB.outgoingPrefixChannels = {}
    end
    local channels = LanguageScoutDB.outgoingPrefixChannels
    for key in pairs(channels) do
        if not chatDetectionChannelKeys[key] then channels[key] = nil end
    end
    for key in pairs(chatDetectionChannelKeys) do
        channels[key] = channels[key] ~= false
    end
end

ns.SetOutgoingPrefixChannelEnabled = function(key, enabled)
    if not chatDetectionChannelKeys[key] then return false end
    EnsureOutgoingPrefixChannels()
    LanguageScoutDB.outgoingPrefixChannels[key] = enabled and true or false
    return true
end

ns.IsOutgoingPrefixChannelEnabled = function(chatType)
    if LanguageScoutDB.prefixOutgoingMessages == false or ns.IsSecret(chatType) then return false end
    local key = OUTGOING_CHANNEL_KEYS[chatType]
    return key ~= nil and LanguageScoutDB.outgoingPrefixChannels[key] ~= false
end

local VALID_PLAYER_LANGUAGE_SOURCES = {
    automatic = true,
    sync = true,
    guild = true,
    manual = true,
}

local function EnsurePlayerLanguagesTable()
    if type(LanguageScoutDB.players) ~= "table" then
        LanguageScoutDB.players = {}
    end

    local legacyMetadata = type(LanguageScoutDB.playerLanguageMetadata) == "table"
        and LanguageScoutDB.playerLanguageMetadata or nil

    for playerKey, value in pairs(LanguageScoutDB.players) do
        local record = type(value) == "table" and value or nil
        local lang = record and record.lang or value
        local source = record and record.source or nil
        local updatedAt = record and record.updatedAt or nil
        local metadata = legacyMetadata and legacyMetadata[playerKey]

        if (not VALID_PLAYER_LANGUAGE_SOURCES[source] or type(updatedAt) ~= "number" or updatedAt < 0)
            and type(metadata) == "table"
            and VALID_PLAYER_LANGUAGE_SOURCES[metadata.source]
            and type(metadata.updatedAt) == "number"
            and metadata.updatedAt >= 0
        then
            source = metadata.source
            updatedAt = metadata.updatedAt
        end

        if type(playerKey) ~= "string"
            or playerKey == ""
            or not IsSupportedLanguage(lang)
        then
            LanguageScoutDB.players[playerKey] = nil
        else
            if not VALID_PLAYER_LANGUAGE_SOURCES[source]
                or type(updatedAt) ~= "number"
                or updatedAt < 0
            then
                source = nil
                updatedAt = nil
            else
                updatedAt = math.floor(updatedAt)
            end

            if not record then
                record = {}
                LanguageScoutDB.players[playerKey] = record
            end
            record.lang = lang
            record.source = source
            record.updatedAt = updatedAt
            record.selfReported = source == "sync" and record.selfReported == true or nil
        end
    end

    -- Versions through 1.8.3 stored provenance in a second table keyed by the
    -- same player name. The data is merged above and the redundant table is no
    -- longer persisted.
    LanguageScoutDB.playerLanguageMetadata = nil
end

local function EnsureDatabaseDefaults()
    EnsurePlayerLanguagesTable()
    -- Undo rejections survive reloads and old peers replaying inferred entries.
    if type(LanguageScoutDB.rejectedPlayerLanguages) ~= "table" then
        LanguageScoutDB.rejectedPlayerLanguages = {}
    end
    for playerKey, languages in pairs(LanguageScoutDB.rejectedPlayerLanguages) do
        if type(playerKey) ~= "string" or playerKey == "" or type(languages) ~= "table" then
            LanguageScoutDB.rejectedPlayerLanguages[playerKey] = nil
        else
            for lang, rejected in pairs(languages) do
                if not IsSupportedLanguage(lang) or rejected ~= true then
                    languages[lang] = nil
                end
            end
            if not next(languages) then
                LanguageScoutDB.rejectedPlayerLanguages[playerKey] = nil
            end
        end
    end
    -- Older versions persisted a large derived player-to-guild cache. It is
    -- session-only now, so scrub any legacy copy whenever the database is checked.
    LanguageScoutDB.playerGuilds = nil
    if LanguageScoutDB.myLanguage ~= nil and LanguageScoutDB.myLanguage ~= "" and not IsSupportedLanguage(LanguageScoutDB.myLanguage) then
        LanguageScoutDB.myLanguage = nil
    end

    LanguageScoutDB.autoDetect = LanguageScoutDB.autoDetect ~= false
    EnsureChatDetectionChannels()
    LanguageScoutDB.prefixOutgoingMessages = LanguageScoutDB.prefixOutgoingMessages ~= false
    EnsureOutgoingPrefixChannels()
    LanguageScoutDB.syncGuild = LanguageScoutDB.syncGuild ~= false
    LanguageScoutDB.syncParty = LanguageScoutDB.syncParty ~= false
    LanguageScoutDB.autoMarkFeedback = LanguageScoutDB.autoMarkFeedback ~= false
    LanguageScoutDB.autoDetectPetNames = LanguageScoutDB.autoDetectPetNames ~= false
    LanguageScoutDB.autoDetectGuildNames = LanguageScoutDB.autoDetectGuildNames ~= false
    LanguageScoutDB.manualMarkFeedback = LanguageScoutDB.manualMarkFeedback ~= false
    LanguageScoutDB.displayFlagsInChat = LanguageScoutDB.displayFlagsInChat ~= false
    LanguageScoutDB.displayFlagsInTooltip = LanguageScoutDB.displayFlagsInTooltip ~= false
    LanguageScoutDB.displayFlagsInLFG = LanguageScoutDB.displayFlagsInLFG ~= false
    LanguageScoutDB.debugPerformance = LanguageScoutDB.debugPerformance == true

    local debugThreshold = tonumber(LanguageScoutDB.debugPerformanceThreshold)
    if not debugThreshold or debugThreshold < 1 then
        debugThreshold = 10
    end
    LanguageScoutDB.debugPerformanceThreshold = debugThreshold

    EnsureLanguageOptionsTable()
    EnsureAutoDetectWordsTable()
    EnsureCharacterDatabaseDefaults()
    if type(ns.EnsureGuildLanguagesTable) == "function" then
        ns.EnsureGuildLanguagesTable()
    end
end

ns.EnsureDatabaseDefaults = EnsureDatabaseDefaults

EnsureDatabaseDefaults()

local debugLastMessageByLabel = {}
local tooltipDebugTraceRemaining = 0
local syncDebugTraceRemaining = 0
local lastAutomaticDetection

local function GetDebugTimeMs()
    if debugprofilestop then
        return debugprofilestop()
    end

    if GetTime then
        return GetTime() * 1000
    end

    return 0
end

local function GetDebugTimestamp()
    if date then
        return date("%H:%M:%S")
    end

    local elapsedSeconds = math.floor((GetTime and GetTime()) or 0)
    return string.format("+%02d:%02d", math.floor(elapsedSeconds / 60), elapsedSeconds % 60)
end

ns.DebugPerfStart = function()
    if not (LanguageScoutDB and LanguageScoutDB.debugPerformance) then
        return
    end

    return GetDebugTimeMs()
end

ns.DebugPerfStop = function(label, startTime, detail, forceOutput)
    if not startTime or not (LanguageScoutDB and LanguageScoutDB.debugPerformance) then
        return
    end

    label = label or "unknown"

    local elapsed = GetDebugTimeMs() - startTime
    local threshold = tonumber(LanguageScoutDB.debugPerformanceThreshold) or 10
    if not forceOutput and elapsed < threshold then
        return
    end

    local now = GetDebugTimeMs()
    local lastMessage = debugLastMessageByLabel[label] or 0
    if not forceOutput and now > 0 and (now - lastMessage) < 3000 then
        return
    end

    debugLastMessageByLabel[label] = now

    local suffix = ""
    if detail and detail ~= "" then
        suffix = " (" .. tostring(detail) .. ")"
    end

    PrintChatMessage(string.format(
        L("DEBUG_PERF_MESSAGE"),
        GetDebugTimestamp(),
        label,
        elapsed,
        suffix
    ))
end

ns.ConsumeTooltipDebugTrace = function()
    if tooltipDebugTraceRemaining <= 0 then
        return false
    end

    tooltipDebugTraceRemaining = tooltipDebugTraceRemaining - 1
    return true
end

ns.DebugSyncEvent = function(eventName, detail)
    if syncDebugTraceRemaining <= 0 then
        return
    end

    syncDebugTraceRemaining = syncDebugTraceRemaining - 1
    local suffix = ""
    if detail and detail ~= "" then
        suffix = " (" .. tostring(detail) .. ")"
    end

    PrintChatMessage(string.format(
        L("DEBUG_SYNC_EVENT_MESSAGE"),
        GetDebugTimestamp(),
        tostring(eventName or "UNKNOWN"),
        suffix
    ))
end

ns.IsSyncDebugTraceActive = function()
    return syncDebugTraceRemaining > 0
end

local function GetDetectionTimestamp()
    if GetServerTime then
        return GetServerTime()
    end
    if time then
        return time()
    end
    return 0
end

local function FormatDetectionTimestamp(timestamp)
    timestamp = tonumber(timestamp)
    if not timestamp or timestamp <= 0 then
        return L("UNKNOWN")
    end
    if date then
        return date("%Y-%m-%d %H:%M", timestamp)
    end
    return tostring(timestamp)
end

local function PrintLastAutomaticDetection()
    local detection = lastAutomaticDetection
    if not detection then
        PrintChatMessage(L("DEBUG_LAST_DETECTION_NONE"))
        return
    end

    PrintChatMessage(string.format(
        L("DEBUG_LAST_DETECTION_MESSAGE"),
        detection.playerName,
        GetLanguageDisplayName(detection.lang),
        FormatDetectionTimestamp(detection.detectedAt),
        detection.reason or L("UNKNOWN")
    ))
end

local function UndoLastAutomaticDetection(expectedPlayerName, expectedLang)
    local detection = lastAutomaticDetection
    if not detection
        or detection.playerName ~= expectedPlayerName
        or detection.lang ~= expectedLang
    then
        PrintChatMessage(L("AUTO_UNDO_EXPIRED"))
        return
    end

    local record = LanguageScoutDB.players[detection.playerName]
    if type(record) ~= "table"
        or record.lang ~= detection.lang
        or record.source ~= "automatic"
    then
        lastAutomaticDetection = nil
        PrintChatMessage(L("AUTO_UNDO_EXPIRED"))
        return
    end

    local rejectPlayerLanguage = ns.RejectAutomaticPlayerLanguage
    if type(rejectPlayerLanguage) ~= "function"
        or not rejectPlayerLanguage(detection.playerName, detection.lang)
    then
        PrintChatMessage(L("AUTO_UNDO_EXPIRED"))
        return
    end

    lastAutomaticDetection = nil
    PrintChatMessage(string.format(L("AUTO_UNDO_SUCCESS"), detection.playerName))
end

if hooksecurefunc and SetItemRef then
    hooksecurefunc("SetItemRef", function(link)
        if type(link) ~= "string" then
            return
        end
        local playerName, lang = link:match("^languagescoutundo:([^:]+):([A-Z]+)$")
        if playerName and lang then
            UndoLastAutomaticDetection(playerName, lang)
        end
    end)
end

local function PrintDebugStatus()
    local state = LanguageScoutDB.debugPerformance and L("DEBUG_STATUS_ENABLED") or L("DEBUG_STATUS_DISABLED")
    PrintChatMessage(string.format(
        L("DEBUG_STATUS_MESSAGE"),
        state,
        tonumber(LanguageScoutDB.debugPerformanceThreshold) or 10
    ))
end

SLASH_LANGUAGESCOUTDEBUG1 = "/lsdebug"
SLASH_LANGUAGESCOUTDEBUG2 = "/languagescoutdebug"
SlashCmdList.LANGUAGESCOUTDEBUG = function(msg)
    EnsureDatabaseDefaults()

    local arg = Trim(msg or "") or ""
    local loweredArg = string.lower(arg)
    local threshold = tonumber(arg) or tonumber(arg:match("^threshold%s+([%d%.]+)$"))

    if loweredArg == "last" then
        PrintLastAutomaticDetection()
        return
    end

    if loweredArg == "records" or loweredArg == "stats" then
        local getRecordCounts = ns.GetRecordCounts
        if type(getRecordCounts) ~= "function" then
            PrintChatMessage("|cffff3333LanguageScout record statistics are unavailable.|r")
            return
        end

        local counts = getRecordCounts()
        PrintChatMessage(string.format(
            L("DEBUG_RECORDS_MESSAGE"),
            counts.playerLanguages or 0,
            counts.managedAutomaticPlayerLanguages or 0,
            counts.automaticCleanupThreshold or 0,
            counts.playerGuilds or 0,
            counts.playerGuildLimit or 0,
            counts.guildLanguages or 0,
            counts.customKeywords or 0
        ))
        return
    end

    if loweredArg == "test" then
        local runTests = ns.RunAutoDetectSelfTests
        if type(runTests) ~= "function" then
            PrintChatMessage("|cffff3333LanguageScout self-test is unavailable.|r")
            return
        end

        local passed, total, failures = runTests()
        local runPetTests = ns.RunPetNameSelfTests
        if type(runPetTests) == "function" then
            local petPassed, petTotal, petFailures = runPetTests()
            passed = passed + petPassed
            total = total + petTotal
            for _, failure in ipairs(petFailures or {}) do
                failures[#failures + 1] = "pet name: " .. failure
            end
        end
        local color = passed == total and "|cff33ff99" or "|cffff3333"
        PrintChatMessage(string.format(
            "%sLanguageScout self-test: %d/%d passed.|r",
            color,
            passed,
            total
        ))
        for _, failure in ipairs(failures or {}) do
            PrintChatMessage("|cffff3333LanguageScout self-test:|r " .. failure)
        end
        return
    end

    local tooltipTraceCountText = loweredArg:match("^tooltip%s*(%d*)$")
    if tooltipTraceCountText ~= nil then
        local tooltipTraceCount = tonumber(tooltipTraceCountText) or 10
        tooltipTraceCount = math.max(1, math.min(50, math.floor(tooltipTraceCount)))
        tooltipDebugTraceRemaining = tooltipTraceCount
        LanguageScoutDB.debugPerformance = true
        PrintChatMessage(string.format(L("DEBUG_TOOLTIP_TRACE_MESSAGE"), tooltipTraceCount))
        return
    end

    local syncTraceCountText = loweredArg:match("^sync%s*(%d*)$")
    if syncTraceCountText ~= nil then
        local syncTraceCount = tonumber(syncTraceCountText) or 30
        syncTraceCount = math.max(1, math.min(200, math.floor(syncTraceCount)))
        syncDebugTraceRemaining = syncTraceCount
        PrintChatMessage(string.format(L("DEBUG_SYNC_TRACE_MESSAGE"), syncTraceCount))
        return
    end

    if threshold then
        if threshold < 1 then
            threshold = 1
        end

        LanguageScoutDB.debugPerformanceThreshold = threshold
        LanguageScoutDB.debugPerformance = true
        PrintDebugStatus()
        return
    end

    if loweredArg == "on" or loweredArg == "enable" or loweredArg == "enabled" then
        LanguageScoutDB.debugPerformance = true
        PrintDebugStatus()
        return
    end

    if loweredArg == "off" or loweredArg == "disable" or loweredArg == "disabled" then
        LanguageScoutDB.debugPerformance = false
        PrintDebugStatus()
        return
    end

    if loweredArg == "status" then
        PrintDebugStatus()
        return
    end

    LanguageScoutDB.debugPerformance = not LanguageScoutDB.debugPerformance
    PrintDebugStatus()
end

local function GetClientLanguage()
    local locale = GetLocale and GetLocale()
    return locale and CLIENT_LANGUAGE_BY_LOCALE[locale]
end

local function GetPreferredLanguage()
    if not (C_AccountServices and C_AccountServices.GetPreferredPlaySettings and GetAvailableLocaleInfo) then
        return
    end

    local ok, loaded, localeID = pcall(C_AccountServices.GetPreferredPlaySettings)
    if not ok or ns.IsSecret(loaded) or ns.IsSecret(localeID) or loaded ~= true then
        return
    end

    -- Resolve IDs through the client instead of assuming numeric locale IDs.
    local localesOK, locales = pcall(GetAvailableLocaleInfo, true)
    if not localesOK or type(locales) ~= "table" then return end
    for _, locale in ipairs(locales) do
        if locale.localeId == localeID then
            return CLIENT_LANGUAGE_BY_LOCALE[locale.localeName]
        end
    end
end

local function GetOwnEffectiveLanguage()
    if IsSupportedLanguage(LanguageScoutDB.myLanguage) then
        return LanguageScoutDB.myLanguage
    end

    if ns.UsesSurnames then
        -- An unavailable or unsupported preference must not become a different
        -- language just because the UI uses a supported client locale.
        return GetPreferredLanguage()
    end
    return GetClientLanguage()
end

ns.GetOwnEffectiveLanguage = GetOwnEffectiveLanguage

local function ShowManualLanguageMarkedMessage(playerName, lang)
    if not LanguageScoutDB.manualMarkFeedback then
        return
    end

    local languageName = GetLanguageDisplayName(lang)
    local message = string.format(L("MANUAL_MARKED_MESSAGE"), playerName, languageName)
    PrintChatMessage(message)
end

ns.ShowManualLanguageMarkedMessage = ShowManualLanguageMarkedMessage

local function ShowAutoLanguageMarkedMessage(playerName, lang, reason, allowUndo)
    if allowUndo then
        lastAutomaticDetection = {
            playerName = playerName,
            lang = lang,
            reason = reason,
            detectedAt = GetDetectionTimestamp(),
        }
    end

    if not LanguageScoutDB.autoMarkFeedback then
        return
    end

    local languageName = GetLanguageDisplayName(lang)
    local message = string.format(L("AUTO_MARKED_MESSAGE"), playerName, languageName, reason or L("UNKNOWN"))
    if allowUndo then
        message = message .. string.format(
            " |cff33ff99|Hlanguagescoutundo:%s:%s|h[%s]|h|r",
            playerName,
            lang,
            L("UNDO")
        )
    end
    PrintChatMessage(message)
end

ns.ShowAutoLanguageMarkedMessage = ShowAutoLanguageMarkedMessage

local loginRefreshFrame = CreateFrame("Frame")
loginRefreshFrame:RegisterEvent("PLAYER_LOGIN")
if ns.UsesSurnames and C_AccountServices and C_AccountServices.GetPreferredPlaySettings then
    loginRefreshFrame:RegisterEvent("PREFERRED_PLAY_SETTINGS_UPDATED")
end
loginRefreshFrame:SetScript("OnEvent", function(_, event)
    if event == "PREFERRED_PLAY_SETTINGS_UPDATED" then
        ns.RefreshOwnLanguageDisplay()
        if not IsSupportedLanguage(LanguageScoutDB.myLanguage) then
            ns.SyncOwnLanguage()
        end
        return
    end
    if ns.UsesSurnames and C_AccountServices and C_AccountServices.RequestPreferredPlaySettings then
        pcall(C_AccountServices.RequestPreferredPlaySettings)
    end
    if type(ns.RefreshPlayerRealm) == "function" then
        ns.RefreshPlayerRealm()
    end

    EnsureDatabaseDefaults()

    ns.RefreshOwnLanguageDisplay()

    if C_Timer and C_Timer.After and type(ns.RefreshAutoDetectPanel) == "function" then
        C_Timer.After(0, function()
            if type(ns.RefreshAutoDetectPanel) == "function" then
                ns.RefreshAutoDetectPanel()
            end
        end)
    end
end)
