local _, ns = ...

local L = ns.L
local GetPlayerRealm = ns.GetPlayerRealm
local IsSupportedLanguage = ns.IsSupportedLanguage
local NormalizeRealm = ns.NormalizeRealm
local Trim = ns.Trim
local AUTOMATIC_PLAYER_LANGUAGE_CLEANUP_THRESHOLD = 10000
local AUTOMATIC_PLAYER_LANGUAGE_EVICTION_BATCH_SIZE = 100
local AUTOMATIC_PLAYER_LANGUAGE_CLEANUP_ENABLED = false
local MAX_SESSION_PLAYER_GUILD_ENTRIES = 10000

local playerLanguageEntryCount = 0
local managedAutomaticPlayerLanguageEntryCount = 0
local largePlayerLanguageRecordWarningShown = false

local MANAGED_PLAYER_LANGUAGE_SOURCES = {
    automatic = true,
    sync = true,
    guild = true,
}

local function NormalizePlayerLanguageSource(source)
    if source == "manual" or MANAGED_PLAYER_LANGUAGE_SOURCES[source] then
        return source
    end
    return "automatic"
end

local function GetCurrentTimestamp()
    if GetServerTime then
        return GetServerTime()
    end
    if time then
        return time()
    end
    return 0
end

local function RecountPlayerLanguageEntries()
    local count = 0
    local managedAutomaticCount = 0
    if type(LanguageScoutDB.players) == "table" then
        for _, record in pairs(LanguageScoutDB.players) do
            count = count + 1
            if type(record) == "table" and MANAGED_PLAYER_LANGUAGE_SOURCES[record.source] then
                managedAutomaticCount = managedAutomaticCount + 1
            end
        end
    end

    playerLanguageEntryCount = count
    managedAutomaticPlayerLanguageEntryCount = managedAutomaticCount
    return count
end

RecountPlayerLanguageEntries()

local sessionPlayerGuilds = {}
local sessionPlayerGuildEntryCount = 0

-- Player-to-guild mappings are derived from live unit and roster data. Older
-- versions persisted this cache indefinitely; keep it session-only instead.
LanguageScoutDB.playerGuilds = nil

local function SurnameFullName(name, surname)
    name, surname = Trim(name), Trim(surname)
    if not name or name == "" then return end
    local separators = Constants and Constants.CharacterNameSeparatorConsts
    local separator = separators and separators.CHARACTERNAME_SURNAME_SEPARATOR or " "
    local first, last = name:find(separator, 1, true)
    if not first and separator ~= " " then
        first, last = name:find(" ", 1, true)
    end
    if first then
        surname = Trim(name:sub(last + 1))
        name = Trim(name:sub(1, first - 1))
    end
    -- Never guess a surname from the realm or match by first name alone.
    if not name or name == "" or not surname or surname == "" then return end
    if name:find("[:%c|]") or surname:find("[:%c|]") then return end
    return name .. separator .. surname
end

local function ReadUnitName(unit)
    local name, second
    if ns.UsesSurnames and UnitNameUnmodified then
        name, second = UnitNameUnmodified(unit)
    else
        name, second = UnitName(unit)
    end
    if ns.IsSecret(name) or ns.IsSecret(second) then return end
    if ns.UsesSurnames then
        -- Return no realm: the second API result is a surname in Forever.
        return SurnameFullName(name, second)
    end
    return name, second
end

ns.ReadUnitName = ReadUnitName
local UnitName = ReadUnitName

local function ParseNameWithOptionalRealm(rawName)
    if ns.UsesSurnames then return SurnameFullName(rawName), nil end
    if ns.IsSecret(rawName) then return end
    if not rawName or rawName == "" then
        return
    end

    local cleanedName = Trim(rawName)
    if not cleanedName or cleanedName == "" then
        return
    end

    local name, realm = cleanedName:match("^([^%-]+)%-(.+)$")
    if name and realm then
        return Trim(name), NormalizeRealm(realm)
    end

    return cleanedName, nil
end

local function FullName(name, realm)
    if ns.UsesSurnames then return SurnameFullName(name, realm) end
    local cleanedName = Trim(name)
    if not cleanedName or cleanedName == "" then
        return
    end

    local normalizedRealm = NormalizeRealm(realm)
    if not normalizedRealm or normalizedRealm == "" then
        normalizedRealm = GetPlayerRealm()
    end

    if not normalizedRealm or normalizedRealm == "" then
        return cleanedName
    end

    return cleanedName .. "-" .. normalizedRealm
end

ns.FullName = FullName

local function ParseFullName(rawName)
    return ParseNameWithOptionalRealm(rawName)
end

ns.ParseFullName = ParseFullName

local normalizedPlayerKeyCache = {}
local normalizedPlayerKeyCacheSize = 0
local NORMALIZED_PLAYER_KEY_CACHE_LIMIT = 1000
local playerKeyByGUID = {}
local playerKeyByGUIDSize = 0
local PLAYER_KEY_GUID_CACHE_LIMIT = 1000

local function ClearNormalizedPlayerKeyCache()
    wipe(normalizedPlayerKeyCache)
    normalizedPlayerKeyCacheSize = 0
    wipe(playerKeyByGUID)
    playerKeyByGUIDSize = 0
end

ns.ClearPlayerNameCache = ClearNormalizedPlayerKeyCache

local function RememberNormalizedPlayerKey(rawName, playerKey)
    if normalizedPlayerKeyCache[rawName] == nil then
        if normalizedPlayerKeyCacheSize >= NORMALIZED_PLAYER_KEY_CACHE_LIMIT then
            ClearNormalizedPlayerKeyCache()
        end

        normalizedPlayerKeyCacheSize = normalizedPlayerKeyCacheSize + 1
    end

    normalizedPlayerKeyCache[rawName] = playerKey or false
end

local function NormalizePlayerKey(rawName)
    if ns.IsSecret(rawName) then return end
    if not rawName or rawName == "" then
        return
    end

    local cachedPlayerKey = normalizedPlayerKeyCache[rawName]
    if cachedPlayerKey ~= nil then
        return cachedPlayerKey or nil
    end

    local parsedName, parsedRealm = ParseFullName(rawName)
    local playerKey = FullName(parsedName, parsedRealm)
    RememberNormalizedPlayerKey(rawName, playerKey)
    return playerKey
end

ns.NormalizePlayerKey = NormalizePlayerKey

local function ResolvePlayerKeyFromGUID(guid)
    if ns.IsSecret(guid) or type(guid) ~= "string" or guid == "" or not GetPlayerInfoByGUID then
        return
    end

    local cachedPlayerKey = playerKeyByGUID[guid]
    if cachedPlayerKey then
        return cachedPlayerKey
    end

    local ok, _, _, _, _, _, name, second = pcall(GetPlayerInfoByGUID, guid)
    if not ok or ns.IsSecret(name) or ns.IsSecret(second) then
        return
    end

    local playerKey
    if ns.UsesSurnames then
        -- Forever may return the complete name in one field or split first name
        -- and surname across the legacy name/realm result positions.
        playerKey = NormalizePlayerKey(SurnameFullName(name, second))
    else
        playerKey = NormalizePlayerKey(FullName(name, second))
    end

    if playerKey then
        if playerKeyByGUIDSize >= PLAYER_KEY_GUID_CACHE_LIMIT then
            wipe(playerKeyByGUID)
            playerKeyByGUIDSize = 0
        end
        playerKeyByGUID[guid] = playerKey
        playerKeyByGUIDSize = playerKeyByGUIDSize + 1
    end

    return playerKey
end

local function ResolveChatAuthorPlayerKey(author, guid)
    local playerKey = NormalizePlayerKey(author)
    if playerKey then
        return playerKey
    end

    -- Never fall back to a bare Forever first name. The sender GUID is the
    -- only safe way to recover the complete first-name/surname identity.
    return ResolvePlayerKeyFromGUID(guid)
end

ns.ResolveChatAuthorPlayerKey = ResolveChatAuthorPlayerKey

local function GetShortPlayerName(rawName)
    local parsedName = ParseFullName(rawName)
    return parsedName
end

local function NormalizeGuildName(guildName)
    local cleanedGuildName = Trim(guildName)
    if not cleanedGuildName or cleanedGuildName == "" then
        return
    end

    return cleanedGuildName
end

ns.NormalizeGuildName = NormalizeGuildName

local function BuildGuildKey(guildName, realm)
    local normalizedGuildName = NormalizeGuildName(guildName)
    if not normalizedGuildName then
        return
    end

    local normalizedRealm = NormalizeRealm(realm)
    if not normalizedRealm or normalizedRealm == "" then
        normalizedRealm = GetPlayerRealm()
    end

    if not normalizedRealm or normalizedRealm == "" then
        return normalizedGuildName
    end

    return normalizedGuildName .. "-" .. normalizedRealm
end

local function ParseGuildKey(guildKey)
    local cleanedGuildKey = Trim(guildKey)
    if not cleanedGuildKey or cleanedGuildKey == "" then
        return
    end

    local guildName, realm = cleanedGuildKey:match("^(.*)%-(.-)$")
    if guildName and realm and realm ~= "" then
        return guildName, realm
    end

    return cleanedGuildKey, nil
end

ns.ParseGuildKey = ParseGuildKey

local function EnsureGuildLanguagesTable()
    if type(LanguageScoutDB.guildLanguages) ~= "table" then
        LanguageScoutDB.guildLanguages = {}
        return
    end

    for guildKey, lang in pairs(LanguageScoutDB.guildLanguages) do
        if type(guildKey) ~= "string"
            or guildKey == ""
            or not IsSupportedLanguage(lang)
        then
            LanguageScoutDB.guildLanguages[guildKey] = nil
        end
    end
end

ns.EnsureGuildLanguagesTable = EnsureGuildLanguagesTable

local function SetStoredGuildLanguage(guildName, realm, lang)
    if not IsSupportedLanguage(lang) then
        return
    end

    local guildKey = BuildGuildKey(guildName, realm)
    if not guildKey then
        return
    end

    EnsureGuildLanguagesTable()
    LanguageScoutDB.guildLanguages[guildKey] = lang
    return guildKey
end

ns.SetStoredGuildLanguage = SetStoredGuildLanguage

local function GetStoredGuildLanguage(guildName, realm)
    local guildKey = BuildGuildKey(guildName, realm)
    if not guildKey then
        return
    end

    return LanguageScoutDB.guildLanguages and LanguageScoutDB.guildLanguages[guildKey], guildKey
end

local function RememberPlayerGuild(playerKey, guildName, realm)
    if not playerKey then
        return
    end

    local guildKey = BuildGuildKey(guildName, realm)
    if not guildKey then
        return
    end

    local previousGuildKey = sessionPlayerGuilds[playerKey]
    if previousGuildKey == nil then
        if sessionPlayerGuildEntryCount >= MAX_SESSION_PLAYER_GUILD_ENTRIES then
            return
        end
        sessionPlayerGuildEntryCount = sessionPlayerGuildEntryCount + 1
    end

    sessionPlayerGuilds[playerKey] = guildKey
    return guildKey
end

ns.RememberPlayerGuild = RememberPlayerGuild

local function FindStoredGuildKeyForPlayer(playerKey)
    if not playerKey then
        return
    end

    local storedGuildKey = sessionPlayerGuilds[playerKey]
    if storedGuildKey then
        return storedGuildKey
    end

    local shortPlayerName = GetShortPlayerName(playerKey)
    if not shortPlayerName or shortPlayerName == "" then
        return
    end

    -- Fall back to short-name matching so same-realm references can still
    -- resolve after data arrived once without a normalized realm suffix.
    local matchingGuildKey
    for storedPlayerKey, storedPlayerGuildKey in pairs(sessionPlayerGuilds) do
        if GetShortPlayerName(storedPlayerKey) == shortPlayerName then
            if matchingGuildKey and matchingGuildKey ~= storedPlayerGuildKey then
                return
            end
            matchingGuildKey = storedPlayerGuildKey
        end
    end

    return matchingGuildKey
end

local function ResolveContextPlayer(contextData)
    if not contextData then
        return
    end

    if contextData.unit and ns.CanInspectUnit(contextData.unit) and UnitExists(contextData.unit) then
        if not UnitIsPlayer(contextData.unit) then
            return
        end

        local unitName, unitRealm = UnitName(contextData.unit)
        if unitName then
            return FullName(unitName, unitRealm)
        end
    end

    local name = contextData.fullName or contextData.name or contextData.playerName
    if ns.UsesSurnames then
        return SurnameFullName(name, contextData.surname)
    end
    local realm = contextData.server or contextData.realm
    if name then
        local parsedName, parsedRealm = ParseFullName(name)
        return FullName(parsedName, realm or parsedRealm)
    end
end

ns.ResolveContextPlayer = ResolveContextPlayer

local observedEnemyPlayerLookup = {}

local function IsOpposingFactionUnit(unit)
    if not ns.CanInspectUnit(unit) then return false end
    if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then
        return false
    end

    local playerFaction = UnitFactionGroup and UnitFactionGroup("player")
    local unitFaction = UnitFactionGroup and UnitFactionGroup(unit)
    if playerFaction and unitFaction then
        return playerFaction ~= unitFaction
    end

    return UnitCanAttack and UnitCanAttack("player", unit) and true or false
end

ns.IsOpposingFactionUnit = IsOpposingFactionUnit

local function RememberUnitHostility(unit, playerKey)
    if not playerKey or not IsOpposingFactionUnit(unit) then
        return false
    end

    observedEnemyPlayerLookup[playerKey] = true
    return true
end

ns.RememberUnitHostility = RememberUnitHostility

ns.IsKnownEnemyPlayer = function(playerKey)
    return playerKey and observedEnemyPlayerLookup[playerKey] == true
end

local guildRosterLookup = {}
local guildRosterShortLookup = {}
local guildRosterRefreshPending = false
local guildRosterRefreshQueued = false
local lastGuildRosterRefreshTime = 0
local lastGuildRosterName
local lastGuildRosterMemberCount
local GUILD_ROSTER_REFRESH_THROTTLE_SECONDS = 5
local GUILD_ROSTER_FORCED_REFRESH_THROTTLE_SECONDS = 30
local GUILD_ROSTER_SAME_SNAPSHOT_REFRESH_SECONDS = 15 * 60
local RefreshGuildRosterLookup

local function QueueGuildRosterRefresh()
    guildRosterRefreshPending = true

    if guildRosterRefreshQueued or not (C_Timer and C_Timer.After) then
        return
    end

    guildRosterRefreshQueued = true
    C_Timer.After(GUILD_ROSTER_REFRESH_THROTTLE_SECONDS + 0.1, function()
        guildRosterRefreshQueued = false
        if guildRosterRefreshPending then
            RefreshGuildRosterLookup(false)
        end
    end)
end

RefreshGuildRosterLookup = function(force)
    if not force and InCombatLockdown and InCombatLockdown() then
        QueueGuildRosterRefresh()
        return
    end

    local now = GetTime and GetTime() or 0
    local isInGuild = IsInGuild and IsInGuild()
    local ownGuildName = isInGuild and GetGuildInfo and GetGuildInfo("player")
    local guildMemberCount = isInGuild and GetNumGuildMembers and GetNumGuildMembers() or 0
    local hasGuildRosterCache = next(guildRosterLookup) ~= nil
    local isSameRosterSnapshot = ownGuildName == lastGuildRosterName
        and guildMemberCount == lastGuildRosterMemberCount

    if lastGuildRosterRefreshTime > 0
        and now > 0
        and isSameRosterSnapshot
    then
        local refreshInterval = force and GUILD_ROSTER_FORCED_REFRESH_THROTTLE_SECONDS
            or GUILD_ROSTER_SAME_SNAPSHOT_REFRESH_SECONDS
        if (force or hasGuildRosterCache) and (now - lastGuildRosterRefreshTime) < refreshInterval then
            guildRosterRefreshPending = false
            return
        end
    end

    if not force and now > 0 and (now - lastGuildRosterRefreshTime) < GUILD_ROSTER_REFRESH_THROTTLE_SECONDS then
        QueueGuildRosterRefresh()
        return
    end

    lastGuildRosterRefreshTime = now
    lastGuildRosterName = ownGuildName
    lastGuildRosterMemberCount = guildMemberCount
    guildRosterRefreshPending = false
    local debugStart = ns.DebugPerfStart and ns.DebugPerfStart()
    guildRosterLookup = {}
    guildRosterShortLookup = {}

    if not isInGuild then
        if ns.DebugPerfStop then
            ns.DebugPerfStop("GuildRosterRefresh", debugStart, "not in guild")
        end
        return
    end

    for index = 1, guildMemberCount do
        local guildMemberName = GetGuildRosterInfo and GetGuildRosterInfo(index)
        local guildMemberKey = guildMemberName and NormalizePlayerKey(guildMemberName)
        local guildMemberShortName = guildMemberName and GetShortPlayerName(guildMemberName)
        if guildMemberKey then
            guildRosterLookup[guildMemberKey] = true
            if ownGuildName and ownGuildName ~= "" then
                local _, guildMemberRealm = ParseFullName(guildMemberKey)
                RememberPlayerGuild(guildMemberKey, ownGuildName, guildMemberRealm)
            end
        end

        if guildMemberShortName and guildMemberShortName ~= "" then
            guildRosterShortLookup[guildMemberShortName] = true
        end
    end

    if ns.DebugPerfStop then
        ns.DebugPerfStop("GuildRosterRefresh", debugStart, tostring(guildMemberCount) .. " members")
    end
end

local function GetGuildContextForPlayerKey(playerKey)
    if not playerKey then
        return
    end

    local storedGuildKey = FindStoredGuildKeyForPlayer(playerKey)
    if storedGuildKey then
        local guildName, guildRealm = ParseGuildKey(storedGuildKey)
        if guildName then
            return guildName, guildRealm
        end
    end

    if not IsInGuild or not IsInGuild() then
        return
    end

    local ownGuildName = GetGuildInfo and GetGuildInfo("player")
    if not ownGuildName or ownGuildName == "" then
        return
    end

    -- Build the roster cache lazily so chat-context actions can still infer a
    -- guild even if no roster event fired yet in this session.
    if not next(guildRosterLookup) and GuildRoster then
        GuildRoster()
        RefreshGuildRosterLookup(true)
    end

    local shortPlayerName = GetShortPlayerName(playerKey)
    if guildRosterLookup[playerKey] or (shortPlayerName and guildRosterShortLookup[shortPlayerName]) then
        local _, playerRealm = ParseFullName(playerKey)
        RememberPlayerGuild(playerKey, ownGuildName, playerRealm)
        return ownGuildName, playerRealm
    end
end

ns.GetGuildContextForPlayerKey = GetGuildContextForPlayerKey

local currentPlayerKey

local function RefreshCurrentPlayerKey()
    local playerName, playerRealm = UnitName("player")
    if not playerName then
        currentPlayerKey = nil
        return
    end

    currentPlayerKey = FullName(playerName, playerRealm)
    return currentPlayerKey
end

ns.RefreshCurrentPlayerKey = RefreshCurrentPlayerKey

local function GetCurrentPlayerKey()
    if currentPlayerKey then
        return currentPlayerKey
    end

    return RefreshCurrentPlayerKey()
end

ns.GetCurrentPlayerKey = GetCurrentPlayerKey

local function MarkPlayerLanguagesChanged()
    ns.MarkKnownPlayersDirty()
    if type(ns.MarkPlayerLanguageCacheDirty) == "function" then
        ns.MarkPlayerLanguageCacheDirty()
    end
end

local function SetPlayerLanguageRecord(playerKey, lang, source, selfReported)
    if not playerKey or not lang or not source then
        return
    end

    local previousRecord = LanguageScoutDB.players[playerKey]
    local previousWasManaged = type(previousRecord) == "table"
        and MANAGED_PLAYER_LANGUAGE_SOURCES[previousRecord.source]
    local isManaged = MANAGED_PLAYER_LANGUAGE_SOURCES[source]

    if previousWasManaged and not isManaged then
        managedAutomaticPlayerLanguageEntryCount = math.max(0, managedAutomaticPlayerLanguageEntryCount - 1)
    elseif not previousWasManaged and isManaged then
        managedAutomaticPlayerLanguageEntryCount = managedAutomaticPlayerLanguageEntryCount + 1
    end

    LanguageScoutDB.players[playerKey] = {
        lang = lang,
        source = source,
        updatedAt = GetCurrentTimestamp(),
        selfReported = selfReported and true or nil,
    }
end

local function RemoveOldestManagedAutomaticPlayerLanguages()
    local candidates = {}
    for playerKey, record in pairs(LanguageScoutDB.players or {}) do
        if type(record) == "table"
            and MANAGED_PLAYER_LANGUAGE_SOURCES[record.source]
        then
            candidates[#candidates + 1] = {
                playerKey = playerKey,
                updatedAt = tonumber(record.updatedAt) or 0,
            }
        end
    end

    table.sort(candidates, function(a, b)
        if a.updatedAt == b.updatedAt then
            return a.playerKey < b.playerKey
        end
        return a.updatedAt < b.updatedAt
    end)

    local removeCount = math.min(
        AUTOMATIC_PLAYER_LANGUAGE_EVICTION_BATCH_SIZE,
        #candidates
    )
    for index = 1, removeCount do
        local playerKey = candidates[index].playerKey
        LanguageScoutDB.players[playerKey] = nil
    end

    playerLanguageEntryCount = math.max(0, playerLanguageEntryCount - removeCount)
    managedAutomaticPlayerLanguageEntryCount =
        math.max(0, managedAutomaticPlayerLanguageEntryCount - removeCount)
    return removeCount > 0
end

local function EnsureManagedAutomaticCapacity()
    -- Automatic cleanup is intentionally paused. Keep the timestamp-based batch
    -- eviction implementation above available in case real-world SavedVariables
    -- size or performance measurements justify enabling it in a future release.
    if not AUTOMATIC_PLAYER_LANGUAGE_CLEANUP_ENABLED then
        return true
    end

    if managedAutomaticPlayerLanguageEntryCount < AUTOMATIC_PLAYER_LANGUAGE_CLEANUP_THRESHOLD then
        return true
    end

    return RemoveOldestManagedAutomaticPlayerLanguages()
end

local function WarnAboutLargePlayerLanguageDatabase()
    if largePlayerLanguageRecordWarningShown
        or playerLanguageEntryCount < AUTOMATIC_PLAYER_LANGUAGE_CLEANUP_THRESHOLD
    then
        return
    end

    largePlayerLanguageRecordWarningShown = true
    if type(ns.PrintChatMessage) == "function" then
        ns.PrintChatMessage(string.format(
            L("PLAYER_LANGUAGE_RECORD_WARNING"),
            playerLanguageEntryCount,
            AUTOMATIC_PLAYER_LANGUAGE_CLEANUP_THRESHOLD
        ))
    end
end

local function IsPlayerLanguageRejected(playerKey, lang)
    local rejected = LanguageScoutDB.rejectedPlayerLanguages
    local languages = rejected and rejected[playerKey]
    return type(languages) == "table" and languages[lang] == true
end

local function ClearPlayerLanguageRejection(playerKey, lang)
    local rejected = LanguageScoutDB.rejectedPlayerLanguages
    local languages = rejected and rejected[playerKey]
    if type(languages) == "table" and languages[lang] == true then
        languages[lang] = nil
        if not next(languages) then rejected[playerKey] = nil end
        ns.MarkUndoneGuessesDirty()
        return true
    end
    return false
end

ns.AllowPlayerLanguageAgain = function(rawName, lang)
    if not IsSupportedLanguage(lang) then return false end
    local playerKey = NormalizePlayerKey(rawName)
    if not playerKey then return false end
    return ClearPlayerLanguageRejection(playerKey, lang)
end

local function AddPlayerLanguageIfMissing(rawName, lang, source)
    if not IsSupportedLanguage(lang) then
        return false
    end

    local playerKey = NormalizePlayerKey(rawName)
    if not playerKey then
        return false
    end

    if LanguageScoutDB.players[playerKey] then
        return false
    end

    source = NormalizePlayerLanguageSource(source)
    if source ~= "manual" and IsPlayerLanguageRejected(playerKey, lang) then
        return false
    end
    if MANAGED_PLAYER_LANGUAGE_SOURCES[source] and not EnsureManagedAutomaticCapacity() then
        return false
    end

    playerLanguageEntryCount = playerLanguageEntryCount + 1
    SetPlayerLanguageRecord(playerKey, lang, source)
    if source == "manual" then ClearPlayerLanguageRejection(playerKey, lang) end
    MarkPlayerLanguagesChanged()
    return true, playerKey
end

ns.AddPlayerLanguageIfMissing = AddPlayerLanguageIfMissing

local function RemovePlayerLanguage(playerKey)
    if not playerKey or not LanguageScoutDB.players[playerKey] then
        return false
    end

    local record = LanguageScoutDB.players[playerKey]
    if type(record) == "table" and MANAGED_PLAYER_LANGUAGE_SOURCES[record.source] then
        managedAutomaticPlayerLanguageEntryCount =
            math.max(0, managedAutomaticPlayerLanguageEntryCount - 1)
    end
    LanguageScoutDB.players[playerKey] = nil
    playerLanguageEntryCount = math.max(0, playerLanguageEntryCount - 1)
    MarkPlayerLanguagesChanged()
    return true
end

ns.RemovePlayerLanguage = RemovePlayerLanguage

ns.RejectAutomaticPlayerLanguage = function(playerKey, lang)
    local record = playerKey and LanguageScoutDB.players[playerKey]
    if type(record) ~= "table" or record.source ~= "automatic" or record.lang ~= lang then
        return false
    end
    if not RemovePlayerLanguage(playerKey) then return false end

    local rejected = LanguageScoutDB.rejectedPlayerLanguages
    if type(rejected) ~= "table" then
        rejected = {}
        LanguageScoutDB.rejectedPlayerLanguages = rejected
    end
    rejected[playerKey] = rejected[playerKey] or {}
    rejected[playerKey][lang] = true
    ns.MarkUndoneGuessesDirty()
    return true
end

local BULK_REMOVABLE_PLAYER_LANGUAGE_SOURCES = {
    automatic = true,
    sync = true,
}

local function RemovePlayerLanguagesBySource(source)
    if not BULK_REMOVABLE_PLAYER_LANGUAGE_SOURCES[source] then
        return 0
    end

    local removedCount = 0
    for playerKey, record in pairs(LanguageScoutDB.players) do
        if type(record) == "table"
            and record.source == source
        then
            LanguageScoutDB.players[playerKey] = nil
            removedCount = removedCount + 1
        end
    end

    if removedCount > 0 then
        RecountPlayerLanguageEntries()
        MarkPlayerLanguagesChanged()
    end

    return removedCount
end

ns.RemovePlayerLanguagesBySource = RemovePlayerLanguagesBySource

local function SetPlayerLanguage(playerKey, lang, syncEntry, source, selfReported)
    if not playerKey or not IsSupportedLanguage(lang) then
        return false
    end

    source = NormalizePlayerLanguageSource(source)
    selfReported = source == "sync" and selfReported == true or nil
    local previousRecord = LanguageScoutDB.players[playerKey]
    local previousLang = type(previousRecord) == "table" and previousRecord.lang or nil
    -- Chat evidence must never downgrade a manual choice or direct declaration.
    if type(previousRecord) == "table" then
        if source == "automatic" and (previousRecord.source == "manual" or previousRecord.selfReported) then
            return false
        end
        if selfReported and previousRecord.source == "manual" then return false end
    end
    if source ~= "manual" and not selfReported and IsPlayerLanguageRejected(playerKey, lang) then
        return false
    end
    if previousLang == lang then
        if (source == "manual" or selfReported)
            and (previousRecord.source ~= source or previousRecord.selfReported ~= selfReported)
        then
            SetPlayerLanguageRecord(playerKey, lang, source, selfReported)
            ClearPlayerLanguageRejection(playerKey, lang)
            MarkPlayerLanguagesChanged()
            return true
        end
        return false
    end

    if previousLang == nil
        and MANAGED_PLAYER_LANGUAGE_SOURCES[source]
        and not EnsureManagedAutomaticCapacity()
    then
        return false
    end

    if previousLang == nil then
        playerLanguageEntryCount = playerLanguageEntryCount + 1
    end
    SetPlayerLanguageRecord(playerKey, lang, source, selfReported)
    if source == "manual" or selfReported then ClearPlayerLanguageRejection(playerKey, lang) end
    MarkPlayerLanguagesChanged()

    if syncEntry then
        ns.SyncNewPlayerLanguage(playerKey, lang)
    end

    return true
end

ns.SetPlayerLanguage = SetPlayerLanguage

ns.SetSelfReportedPlayerLanguage = function(rawName, lang)
    local playerKey = NormalizePlayerKey(rawName)
    local changed = SetPlayerLanguage(playerKey, lang, false, "sync", true)
    return changed, playerKey
end

local function SetPlayerLanguagesBulk(playerKeys, lang, source)
    if not IsSupportedLanguage(lang) or type(playerKeys) ~= "table" then
        return 0
    end

    source = NormalizePlayerLanguageSource(source or "guild")
    local changedCount = 0
    for _, playerKey in ipairs(playerKeys) do
        local record = playerKey and LanguageScoutDB.players[playerKey]
        local previousLang = type(record) == "table" and record.lang or nil
        local protected = source == "automatic" and type(record) == "table"
            and (record.source == "manual" or record.selfReported)
        if playerKey and previousLang ~= lang
            and not protected
            and (source == "manual" or not IsPlayerLanguageRejected(playerKey, lang))
        then
            if previousLang == nil then
                if MANAGED_PLAYER_LANGUAGE_SOURCES[source]
                    and not EnsureManagedAutomaticCapacity()
                then
                    break
                end
                playerLanguageEntryCount = playerLanguageEntryCount + 1
            end
            SetPlayerLanguageRecord(playerKey, lang, source)
            if source == "manual" then ClearPlayerLanguageRejection(playerKey, lang) end
            changedCount = changedCount + 1
        end
    end

    if changedCount > 0 then
        MarkPlayerLanguagesChanged()
    end

    return changedCount
end

ns.SetPlayerLanguagesBulk = SetPlayerLanguagesBulk

ns.GetRecordCounts = function()
    EnsureGuildLanguagesTable()
    local currentPlayerLanguageCount = RecountPlayerLanguageEntries()

    local guildLanguageCount = 0
    for _ in pairs(LanguageScoutDB.guildLanguages) do
        guildLanguageCount = guildLanguageCount + 1
    end

    local customKeywordCount = 0
    if type(LanguageScoutDB.autoDetectWords) == "table" then
        for _, words in pairs(LanguageScoutDB.autoDetectWords) do
            if type(words) == "table" then
                customKeywordCount = customKeywordCount + #words
            end
        end
    end

    return {
        playerLanguages = currentPlayerLanguageCount,
        managedAutomaticPlayerLanguages = managedAutomaticPlayerLanguageEntryCount,
        playerGuilds = sessionPlayerGuildEntryCount,
        guildLanguages = guildLanguageCount,
        customKeywords = customKeywordCount,
        automaticCleanupThreshold = AUTOMATIC_PLAYER_LANGUAGE_CLEANUP_THRESHOLD,
        automaticCleanupEnabled = AUTOMATIC_PLAYER_LANGUAGE_CLEANUP_ENABLED,
        playerGuildLimit = MAX_SESSION_PLAYER_GUILD_ENTRIES,
    }
end

local function TryApplyStoredGuildLanguageToUnit(unit, playerKey, guildName, playerRealm)
    if not ns.CanInspectUnit(unit) then return end
    if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then
        return
    end

    if not playerKey then
        local playerName
        playerName, playerRealm = UnitName(unit)
        if not playerName then
            return
        end
        playerKey = FullName(playerName, playerRealm)
    elseif not playerRealm then
        _, playerRealm = ParseFullName(playerKey)
    end

    guildName = guildName or (GetGuildInfo and GetGuildInfo(unit))
    if not guildName then
        return
    end

    RememberPlayerGuild(playerKey, guildName, playerRealm)

    local guildLanguage = GetStoredGuildLanguage(guildName, playerRealm)
    if not guildLanguage then
        return
    end

    if not playerKey or LanguageScoutDB.players[playerKey] then
        return
    end

    if not SetPlayerLanguage(playerKey, guildLanguage, false, "guild") then
        return
    end
    if type(ns.ShowAutoLanguageMarkedMessage) == "function" then
        ns.ShowAutoLanguageMarkedMessage(playerKey, guildLanguage, L("AUTO_REASON_GUILD_ASSIGNMENT"))
    end
end

ns.TryApplyStoredGuildLanguageToUnit = TryApplyStoredGuildLanguageToUnit

local playerDataFrame = CreateFrame("Frame")
playerDataFrame:RegisterEvent("PLAYER_LOGIN")
playerDataFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
playerDataFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
playerDataFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
playerDataFrame:RegisterEvent("PLAYER_LOGOUT")
playerDataFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGOUT" then
        -- SavedVariables are serialized after this event. Scrub the obsolete
        -- persistent cache again in case another code path restored it.
        LanguageScoutDB.playerGuilds = nil
        return
    end

    if event == "PLAYER_LOGIN" then
        if type(ns.RefreshPlayerRealm) == "function" then
            ns.RefreshPlayerRealm()
        end
        RefreshCurrentPlayerKey()
    end

    if event == "PLAYER_REGEN_ENABLED" then
        if guildRosterRefreshPending then
            RefreshGuildRosterLookup(false)
        end
        return
    end

    if event == "PLAYER_LOGIN" then
        EnsureGuildLanguagesTable()
        WarnAboutLargePlayerLanguageDatabase()
    end
    ns.MarkKnownPlayersDirty()

    if event == "PLAYER_LOGIN" or event == "PLAYER_GUILD_UPDATE" then
        if GuildRoster and IsInGuild and IsInGuild() then
            GuildRoster()
        end
    end

    RefreshGuildRosterLookup(event == "PLAYER_LOGIN" or event == "PLAYER_GUILD_UPDATE")
end)
