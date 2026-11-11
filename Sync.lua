local _, ns = ...
local UnitName = ns.ReadUnitName

if not (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) then
    return
end

local ADDON_PREFIX = ns.ADDON_PREFIX
local AddPlayerLanguageIfMissing = ns.AddPlayerLanguageIfMissing
local SetSelfReportedPlayerLanguage = ns.SetSelfReportedPlayerLanguage
local FullName = ns.FullName
local GetCurrentPlayerKey = ns.GetCurrentPlayerKey
local GetOwnEffectiveLanguage = ns.GetOwnEffectiveLanguage
local IsSupportedLanguage = ns.IsSupportedLanguage
local L = ns.L
local NormalizePlayerKey = ns.NormalizePlayerKey
local PrintChatMessage = ns.PrintChatMessage
local ShowAutoLanguageMarkedMessage = ns.ShowAutoLanguageMarkedMessage
local ADDON_VERSION = ns.ADDON_VERSION or "0"
-- Version numbers belong to this product; older addon names used a different
-- release sequence while sharing the same language-data protocol.
local VERSION_MESSAGE_PREFIX = "VER:LanguageScout:"
local DebugSyncEvent = ns.DebugSyncEvent
local IsSyncDebugTraceActive = ns.IsSyncDebugTraceActive

C_ChatInfo.RegisterAddonMessagePrefix(ADDON_PREFIX)

local addonCommFrame = CreateFrame("Frame")
if not addonCommFrame then
    return
end

addonCommFrame:RegisterEvent("CHAT_MSG_ADDON")
addonCommFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
addonCommFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
addonCommFrame:RegisterEvent("PLAYER_LOGIN")
addonCommFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

local lastGroupSyncState
local lastGuildSyncState
local lastNearbyRequestByPlayer = {}
local nearbyRequestPlayerCount = 0
local pendingNearbyLanguageRequests = {}
local pendingNearbyLanguageRequestCount = 0
local nearbyLanguageRequestFlushQueued = false
local lastSyncRequestByDistribution = {}
local lastSyncBroadcastByDistribution = {}
local lastBatchBroadcastByDistribution = {}
local queuedSyncRequestByDistribution = {}
local pendingBatchRequestByDistribution = {}
local pendingCombatSyncBroadcastByDistribution = {}
local activeSyncBroadcastByDistribution = {}
local pendingSyncResponseByDistribution = {}
local pendingCombatInboundMessages = {}
local pendingCombatInboundReadIndex = 1
local pendingCombatInboundWriteIndex = 0
local pendingCombatInboundQueued = false
local pendingCombatOutboundMessages = {}
local pendingCombatOutboundReadIndex = 1
local pendingCombatOutboundWriteIndex = 0
local pendingCombatOutboundQueued = false
local warnedOutdatedVersion
local NEARBY_REQUEST_THROTTLE_SECONDS = 60
local SYNC_REQUEST_THROTTLE_SECONDS = 15
local SYNC_FULL_BROADCAST_COOLDOWN_SECONDS = 60 * 60
local SYNC_BROADCAST_BATCH_SIZE = 10
local SYNC_MESSAGE_BYTE_LIMIT = 255
local SYNC_BROADCAST_BATCH_DELAY = 0.1
local SYNC_RESPONSE_ELECTION_MAX_DELAY = 5
local SYNC_INBOUND_BATCH_SIZE = 100
local SYNC_OUTBOUND_BATCH_SIZE = 50
local SYNC_QUEUE_BATCH_DELAY = 0.05
local SYNC_QUEUE_LIMIT = 1000
local NEARBY_REQUEST_CACHE_LIMIT = 1000
local NEARBY_REQUEST_QUEUE_LIMIT = 200
local NEARBY_REQUEST_BATCH_SIZE = 10
local NEARBY_REQUEST_BATCH_DELAY = 0.05

local function GetSyncMessageCommand(message)
    if type(message) ~= "string" then
        return "UNKNOWN"
    end
    return message:match("^([A-Z]+)") or "UNKNOWN"
end

local function TraceSyncEvent(eventName, distribution, peer, extra)
    if type(DebugSyncEvent) ~= "function"
        or (type(IsSyncDebugTraceActive) == "function" and not IsSyncDebugTraceActive())
    then
        return
    end

    local details = {}
    if distribution and distribution ~= "" then
        details[#details + 1] = distribution
    end
    if peer and peer ~= "" then
        details[#details + 1] = peer
    end
    if extra and extra ~= "" then
        details[#details + 1] = extra
    end

    DebugSyncEvent(eventName, table.concat(details, ", "))
end

local function ClearNearbyRequest(playerKey)
    if playerKey and lastNearbyRequestByPlayer[playerKey] ~= nil then
        lastNearbyRequestByPlayer[playerKey] = nil
        nearbyRequestPlayerCount = math.max(0, nearbyRequestPlayerCount - 1)
    end
end

local function RememberNearbyRequest(playerKey, timestamp)
    if lastNearbyRequestByPlayer[playerKey] == nil then
        if nearbyRequestPlayerCount >= NEARBY_REQUEST_CACHE_LIMIT then
            wipe(lastNearbyRequestByPlayer)
            nearbyRequestPlayerCount = 0
        end
        nearbyRequestPlayerCount = nearbyRequestPlayerCount + 1
    end

    lastNearbyRequestByPlayer[playerKey] = timestamp
end

local function IsValidSyncedPlayerName(playerName)
    return type(playerName) == "string"
        and playerName ~= ""
        and #playerName <= 120
        and not playerName:find("[:%c]")
end

local function IsPartyDistribution(distribution)
    return distribution == "PARTY" or distribution == "RAID" or distribution == "INSTANCE_CHAT"
end

local function IsInInstanceGroup()
    if not IsInGroup then
        return false
    end

    local instanceCategory = LE_PARTY_CATEGORY_INSTANCE
    if Enum and Enum.PartyCategory and Enum.PartyCategory.Instance then
        instanceCategory = Enum.PartyCategory.Instance
    end

    if instanceCategory == nil then
        return false
    end

    return IsInGroup(instanceCategory)
end

local function GetGroupSyncDistribution()
    if IsInInstanceGroup() then
        return "INSTANCE_CHAT"
    end

    if IsInRaid() then
        return "RAID"
    end

    if IsInGroup() then
        return "PARTY"
    end
end

local function IsSyncDistributionEnabled(distribution)
    if distribution == "GUILD" then
        return LanguageScoutDB.syncGuild
    end

    if IsPartyDistribution(distribution) then
        return LanguageScoutDB.syncParty
    end
end

local ProcessQueuedCombatOutboundMessages
local ProcessQueuedCombatInboundMessages
local ProcessAddonMessage

local function IsInCombat()
    return InCombatLockdown and InCombatLockdown()
end

local function QueueCombatOutboundMessage(message, distribution, target, requireSyncEnabled)
    local queuedCount = pendingCombatOutboundWriteIndex - pendingCombatOutboundReadIndex + 1
    if queuedCount >= SYNC_QUEUE_LIMIT then
        return false
    end

    pendingCombatOutboundWriteIndex = pendingCombatOutboundWriteIndex + 1
    pendingCombatOutboundMessages[pendingCombatOutboundWriteIndex] = {
        message = message,
        distribution = distribution,
        target = target,
        requireSyncEnabled = requireSyncEnabled,
    }

    if IsInCombat() then
        return
    end

    if pendingCombatOutboundQueued or not (C_Timer and C_Timer.After) then
        return
    end

    pendingCombatOutboundQueued = true
    C_Timer.After(SYNC_QUEUE_BATCH_DELAY, function()
        pendingCombatOutboundQueued = false
        ProcessQueuedCombatOutboundMessages()
    end)
    return true
end

local function SendAddonMessage(message, distribution, target, requireSyncEnabled)
    if not distribution then
        return
    end

    if requireSyncEnabled and not IsSyncDistributionEnabled(distribution) then
        return
    end

    if IsInCombat() then
        TraceSyncEvent("QUEUE OUT " .. GetSyncMessageCommand(message), distribution, target, "combat")
        QueueCombatOutboundMessage(message, distribution, target, requireSyncEnabled)
        return
    end

    C_ChatInfo.SendAddonMessage(ADDON_PREFIX, message, distribution, target)
    if IsSyncDebugTraceActive and IsSyncDebugTraceActive() then
        local command = GetSyncMessageCommand(message)
        if command ~= "ENTRY" then
            TraceSyncEvent("OUT " .. command, distribution, target)
        end
    end
end

local function SendSyncMessage(message, distribution, target)
    SendAddonMessage(message, distribution, target, true)
end

ProcessQueuedCombatOutboundMessages = function()
    if IsInCombat() then
        return
    end

    local processedCount = 0
    while processedCount < SYNC_OUTBOUND_BATCH_SIZE
        and pendingCombatOutboundReadIndex <= pendingCombatOutboundWriteIndex
    do
        local item = pendingCombatOutboundMessages[pendingCombatOutboundReadIndex]
        pendingCombatOutboundMessages[pendingCombatOutboundReadIndex] = nil
        pendingCombatOutboundReadIndex = pendingCombatOutboundReadIndex + 1
        processedCount = processedCount + 1

        if item and item.distribution and (not item.requireSyncEnabled or IsSyncDistributionEnabled(item.distribution)) then
            C_ChatInfo.SendAddonMessage(ADDON_PREFIX, item.message, item.distribution, item.target)
            TraceSyncEvent(
                "OUT " .. GetSyncMessageCommand(item.message),
                item.distribution,
                item.target,
                "dequeued"
            )
        end
    end

    if pendingCombatOutboundReadIndex > pendingCombatOutboundWriteIndex then
        pendingCombatOutboundMessages = {}
        pendingCombatOutboundReadIndex = 1
        pendingCombatOutboundWriteIndex = 0
        return
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(SYNC_QUEUE_BATCH_DELAY, ProcessQueuedCombatOutboundMessages)
    else
        ProcessQueuedCombatOutboundMessages()
    end
end

local function QueueCombatInboundMessage(msg, distribution, sender)
    local queuedCount = pendingCombatInboundWriteIndex - pendingCombatInboundReadIndex + 1
    if queuedCount >= SYNC_QUEUE_LIMIT then
        return false
    end

    pendingCombatInboundWriteIndex = pendingCombatInboundWriteIndex + 1
    pendingCombatInboundMessages[pendingCombatInboundWriteIndex] = {
        msg = msg,
        distribution = distribution,
        sender = sender,
    }

    if IsInCombat() then
        return
    end

    if pendingCombatInboundQueued or not (C_Timer and C_Timer.After) then
        return
    end

    pendingCombatInboundQueued = true
    C_Timer.After(SYNC_QUEUE_BATCH_DELAY, function()
        pendingCombatInboundQueued = false
        ProcessQueuedCombatInboundMessages()
    end)
    return true
end

local function SendVersion(distribution)
    SendSyncMessage(VERSION_MESSAGE_PREFIX .. ADDON_VERSION, distribution)
end

local function ParseVersionParts(version)
    local parts = {}
    if type(version) ~= "string" then
        return parts
    end

    local release = version:match("^(%d+%.%d+%.%d+)") or ""
    for part in release:gmatch("%d+") do
        parts[#parts + 1] = tonumber(part) or 0
    end

    return parts
end

local function GetReleaseStage(version)
    local suffix = version:lower()
    local rc = tonumber(suffix:match("%-rc%.?(%d+)$"))
    if rc then return 2, rc end
    local beta = tonumber(suffix:match("%-beta%.(%d+)$"))
    if beta then return 1, beta end
    return 3, 0
end

local function IsRemoteVersionNewer(remoteVersion)
    local remoteParts = ParseVersionParts(remoteVersion)
    local localParts = ParseVersionParts(ADDON_VERSION)
    local partCount = math.max(#remoteParts, #localParts)

    for index = 1, partCount do
        local remotePart = remoteParts[index] or 0
        local localPart = localParts[index] or 0
        if remotePart > localPart then
            return true
        elseif remotePart < localPart then
            return false
        end
    end

    local remoteStage, remoteRevision = GetReleaseStage(remoteVersion)
    local localStage, localRevision = GetReleaseStage(ADDON_VERSION)
    if remoteStage ~= localStage then return remoteStage > localStage end
    return remoteRevision > localRevision
end

local function HandleVersionMessage(remoteVersion)
    if not IsRemoteVersionNewer(remoteVersion) then
        return
    end

    if warnedOutdatedVersion == remoteVersion then
        return
    end

    warnedOutdatedVersion = remoteVersion
    if type(PrintChatMessage) == "function" then
        PrintChatMessage(L("VERSION_OUTDATED_MESSAGE"))
    end
end

local BroadcastKnownLanguages

local RequestSync

local function QueueSyncRequest(distribution, delay)
    if queuedSyncRequestByDistribution[distribution] or not (C_Timer and C_Timer.After) then
        return
    end

    queuedSyncRequestByDistribution[distribution] = true
    C_Timer.After(delay, function()
        queuedSyncRequestByDistribution[distribution] = nil
        RequestSync(distribution)
    end)
end

local function GetKnownLanguageBroadcastDebugDetail(distribution, requesterKey, status)
    local details = distribution or "UNKNOWN"
    if requesterKey and requesterKey ~= "" then
        details = details .. ", requester " .. requesterKey
    end
    if status and status ~= "" then
        details = details .. ", " .. status
    end
    return details
end

local function ContinueKnownLanguageBroadcast(distribution)
    local state = activeSyncBroadcastByDistribution[distribution]
    if not state or not IsSyncDistributionEnabled(distribution) then
        activeSyncBroadcastByDistribution[distribution] = nil
        return
    end

    if IsInCombat() then
        pendingCombatSyncBroadcastByDistribution[distribution] = true
        return
    end

    local debugStart = ns.DebugPerfStart and ns.DebugPerfStart()
    local playerKeys = state.playerKeys
    local scannedThisBatch = 0
    local sentThisBatch = 0
    local packet = "BATCH1"

    while scannedThisBatch < SYNC_BROADCAST_BATCH_SIZE and state.nextEntryIndex <= #playerKeys do
        local playerKey = playerKeys[state.nextEntryIndex]
        local record = LanguageScoutDB.players[playerKey]
        local lang = type(record) == "table" and record.lang or nil
        state.nextEntryIndex = state.nextEntryIndex + 1
        scannedThisBatch = scannedThisBatch + 1

        if IsSupportedLanguage(lang) and IsValidSyncedPlayerName(playerKey) then
            local entry = ":" .. playerKey .. ":" .. lang
            if state.batch then
                if #packet + #entry > SYNC_MESSAGE_BYTE_LIMIT then
                    SendSyncMessage(packet, distribution)
                    packet = "BATCH1"
                end
                packet = packet .. entry
            else
                SendSyncMessage("ENTRY" .. entry, distribution)
            end
            sentThisBatch = sentThisBatch + 1
            state.sentCount = state.sentCount + 1
        end
    end
    if state.batch and packet ~= "BATCH1" then
        SendSyncMessage(packet, distribution)
    end

    if state.nextEntryIndex > #playerKeys then
        activeSyncBroadcastByDistribution[distribution] = nil
        TraceSyncEvent("FULL SYNC COMPLETE", distribution, nil, tostring(state.sentCount) .. " entries")
        if ns.DebugPerfStop then
            ns.DebugPerfStop(
                "Sync:BroadcastKnownLanguagesBatch",
                debugStart,
                GetKnownLanguageBroadcastDebugDetail(
                    distribution,
                    state.requesterKey,
                    "done, " .. tostring(state.sentCount) .. " entries"
                )
            )
        end
        return
    end

    if ns.DebugPerfStop then
        ns.DebugPerfStop(
            "Sync:BroadcastKnownLanguagesBatch",
            debugStart,
            GetKnownLanguageBroadcastDebugDetail(
                distribution,
                state.requesterKey,
                tostring(sentThisBatch) .. " sent"
            )
        )
    end
    TraceSyncEvent("FULL SYNC BATCH", distribution, nil, tostring(sentThisBatch) .. " entries")

    if C_Timer and C_Timer.After then
        C_Timer.After(SYNC_BROADCAST_BATCH_DELAY, function()
            ContinueKnownLanguageBroadcast(distribution)
        end)
    else
        ContinueKnownLanguageBroadcast(distribution)
    end
end

local function StartKnownLanguageBroadcast(distribution, myPlayerKey, initialSentCount, requesterKey, batch)
    if activeSyncBroadcastByDistribution[distribution] then
        return
    end

    -- Snapshot keys so changes between batches cannot invalidate iteration.
    -- Read the current language at send time and skip removed records.
    local playerKeys = {}
    for playerName, record in pairs(LanguageScoutDB.players or {}) do
        if playerName ~= myPlayerKey and type(record) == "table" and IsSupportedLanguage(record.lang) then
            playerKeys[#playerKeys + 1] = playerName
        end
    end

    activeSyncBroadcastByDistribution[distribution] = {
        playerKeys = playerKeys,
        nextEntryIndex = 1,
        sentCount = initialSentCount or 0,
        requesterKey = requesterKey,
        batch = batch,
    }

    TraceSyncEvent("FULL SYNC START", distribution, nil, tostring(#playerKeys) .. " entries")
    ContinueKnownLanguageBroadcast(distribution)
end

local function SendOwnLanguageEntry(distribution)
    local myPlayerKey = GetCurrentPlayerKey()
    local ownLanguage = GetOwnEffectiveLanguage and GetOwnEffectiveLanguage()
    if not myPlayerKey or not IsSupportedLanguage(ownLanguage) then
        return myPlayerKey, 0
    end

    SendSyncMessage("ENTRY:" .. myPlayerKey .. ":" .. ownLanguage, distribution)
    return myPlayerKey, 1
end

BroadcastKnownLanguages = function(distribution, requesterKey, batch)
    if not distribution or not IsSyncDistributionEnabled(distribution) then
        return
    end

    if IsInCombat() then
        pendingCombatSyncBroadcastByDistribution[distribution] = { requesterKey = requesterKey, batch = batch }
        return
    end

    local now = GetTime and GetTime() or 0
    local broadcastTimes = batch and lastBatchBroadcastByDistribution or lastSyncBroadcastByDistribution
    local lastBroadcast = broadcastTimes[distribution]
    if lastBroadcast and now > 0 and (now - lastBroadcast) < SYNC_FULL_BROADCAST_COOLDOWN_SECONDS then
        local debugStart = ns.DebugPerfStart and ns.DebugPerfStart()
        if ns.DebugPerfStop then
            ns.DebugPerfStop(
                "Sync:BroadcastKnownLanguages",
                debugStart,
                GetKnownLanguageBroadcastDebugDetail(distribution, requesterKey, "full sync cooldown")
            )
        end
        return
    end

    broadcastTimes[distribution] = now
    local debugStart = ns.DebugPerfStart and ns.DebugPerfStart()
    SendVersion(distribution)
    local myPlayerKey, initialSentCount = SendOwnLanguageEntry(distribution)

    StartKnownLanguageBroadcast(distribution, myPlayerKey, initialSentCount, requesterKey, batch)

    if ns.DebugPerfStop then
        ns.DebugPerfStop(
            "Sync:BroadcastKnownLanguages",
            debugStart,
            GetKnownLanguageBroadcastDebugDetail(distribution, requesterKey, "queued")
        )
    end
end

local function GetSyncResponseDelay(requesterKey)
    local ownPlayerKey = GetCurrentPlayerKey() or ""
    local hash = 0
    local hashInput = ownPlayerKey .. ":" .. (requesterKey or "")
    for index = 1, #hashInput do
        hash = (hash * 33 + string.byte(hashInput, index)) % 500
    end
    return (hash / 500) * SYNC_RESPONSE_ELECTION_MAX_DELAY
end

local function CancelPendingSyncResponse(distribution, requesterKey, batch)
    local pending = pendingSyncResponseByDistribution[distribution]
    if not pending or pending.requesterKey ~= requesterKey or pending.batch ~= batch then
        return
    end

    pending.cancelled = true
    pendingSyncResponseByDistribution[distribution] = nil
    TraceSyncEvent("ELECTION CANCELLED", distribution, requesterKey)
end

local function QueueSyncResponse(distribution, requester, batch)
    if not distribution or not IsSyncDistributionEnabled(distribution) then
        return
    end

    local now = GetTime and GetTime() or 0
    local broadcastTimes = batch and lastBatchBroadcastByDistribution or lastSyncBroadcastByDistribution
    local lastBroadcast = broadcastTimes[distribution]
    local active = activeSyncBroadcastByDistribution[distribution]
    if (active and active.batch == batch)
        or (lastBroadcast and now > 0
            and (now - lastBroadcast) < SYNC_FULL_BROADCAST_COOLDOWN_SECONDS)
    then
        return
    end

    local requesterKey = NormalizePlayerKey(requester)
    if not requesterKey then
        return
    end

    local existing = pendingSyncResponseByDistribution[distribution]
    if existing then
        if batch and not existing.batch then return end
        if existing.requesterKey == requesterKey and existing.batch == batch then
            return
        end
        existing.cancelled = true
    end

    if not (C_Timer and C_Timer.After) then
        BroadcastKnownLanguages(distribution, requesterKey, batch)
        return
    end

    local pending = {
        requesterKey = requesterKey,
        batch = batch,
        cancelled = false,
    }
    pendingSyncResponseByDistribution[distribution] = pending
    local responseDelay = GetSyncResponseDelay(requesterKey)
    TraceSyncEvent(
        "ELECTION QUEUED",
        distribution,
        requesterKey,
        string.format("%.2f s", responseDelay)
    )

    local function CompletePendingSyncResponse()
        if pending.cancelled or pendingSyncResponseByDistribution[distribution] ~= pending then
            return
        end

        if IsInCombat() or activeSyncBroadcastByDistribution[distribution] then
            C_Timer.After(1, CompletePendingSyncResponse)
            return
        end

        pendingSyncResponseByDistribution[distribution] = nil
        TraceSyncEvent("ELECTION WON", distribution, requesterKey)
        SendSyncMessage((batch and "SYNCSTART2:" or "SYNCSTART:") .. requesterKey, distribution)
        BroadcastKnownLanguages(distribution, requesterKey, batch)
    end

    C_Timer.After(responseDelay, CompletePendingSyncResponse)
end

RequestSync = function(distribution)
    if not distribution then
        return
    end

    local now = GetTime and GetTime() or 0
    local lastRequest = lastSyncRequestByDistribution[distribution]
    if lastRequest and now > 0 and (now - lastRequest) < SYNC_REQUEST_THROTTLE_SECONDS then
        QueueSyncRequest(distribution, SYNC_REQUEST_THROTTLE_SECONDS - (now - lastRequest) + 0.1)
        return
    end

    lastSyncRequestByDistribution[distribution] = now
    SendVersion(distribution)
    if IsInCombat() or not (C_Timer and C_Timer.After) then
        SendSyncMessage("SYNCREQ", distribution)
        return
    end

    local request = {}
    pendingBatchRequestByDistribution[distribution] = request
    SendSyncMessage("SYNCREQ2", distribution)
    C_Timer.After(SYNC_RESPONSE_ELECTION_MAX_DELAY + 1, function()
        if pendingBatchRequestByDistribution[distribution] ~= request then return end
        pendingBatchRequestByDistribution[distribution] = nil
        if (distribution == "GUILD" and IsInGuild()) or distribution == GetGroupSyncDistribution() then
            SendSyncMessage("SYNCREQ", distribution)
        end
    end)
end

local function SendLanguageRequest(target)
    if not target or target == "" then
        return
    end

    SendAddonMessage("REQ", "WHISPER", target, false)
end

local ProcessQueuedNearbyLanguageRequests

local function HasConfirmedPlayerLanguage(playerKey)
    local record = LanguageScoutDB.players[playerKey]
    return type(record) == "table" and (record.source == "manual" or record.selfReported == true)
end

local function QueueNearbyLanguageRequest(playerKey)
    if pendingNearbyLanguageRequests[playerKey] then
        return true
    end

    if pendingNearbyLanguageRequestCount >= NEARBY_REQUEST_QUEUE_LIMIT then
        return false
    end

    pendingNearbyLanguageRequests[playerKey] = true
    pendingNearbyLanguageRequestCount = pendingNearbyLanguageRequestCount + 1

    if nearbyLanguageRequestFlushQueued then
        return true
    end

    if not (C_Timer and C_Timer.After) then
        pendingNearbyLanguageRequests[playerKey] = nil
        pendingNearbyLanguageRequestCount = pendingNearbyLanguageRequestCount - 1
        SendLanguageRequest(playerKey)
        return true
    end

    nearbyLanguageRequestFlushQueued = true
    C_Timer.After(0, function()
        nearbyLanguageRequestFlushQueued = false
        ProcessQueuedNearbyLanguageRequests()
    end)
    return true
end

ProcessQueuedNearbyLanguageRequests = function()
    local processedCount = 0
    for playerKey in pairs(pendingNearbyLanguageRequests) do
        pendingNearbyLanguageRequests[playerKey] = nil
        pendingNearbyLanguageRequestCount = pendingNearbyLanguageRequestCount - 1
        processedCount = processedCount + 1
        if HasConfirmedPlayerLanguage(playerKey) then
            ClearNearbyRequest(playerKey)
        else
            SendLanguageRequest(playerKey)
        end

        if processedCount >= NEARBY_REQUEST_BATCH_SIZE then
            break
        end
    end

    if pendingNearbyLanguageRequestCount <= 0 then
        pendingNearbyLanguageRequestCount = 0
        return
    end

    if C_Timer and C_Timer.After then
        nearbyLanguageRequestFlushQueued = true
        C_Timer.After(NEARBY_REQUEST_BATCH_DELAY, function()
            nearbyLanguageRequestFlushQueued = false
            ProcessQueuedNearbyLanguageRequests()
        end)
    end
end

local function RequestNearbyLanguageByPlayerKey(playerKey)
    if not playerKey or playerKey == GetCurrentPlayerKey() then
        return
    end

    if HasConfirmedPlayerLanguage(playerKey) then
        return
    end

    local now = GetTime and GetTime() or 0
    local lastRequest = lastNearbyRequestByPlayer[playerKey]
    if lastRequest and (now - lastRequest) < NEARBY_REQUEST_THROTTLE_SECONDS then
        return
    end

    if QueueNearbyLanguageRequest(playerKey) then
        RememberNearbyRequest(playerKey, now)
    end
end

ns.RequestNearbyLanguageByPlayerKey = RequestNearbyLanguageByPlayerKey

ns.RequestLanguageFromUnit = function(unit, playerKey)
    if not ns.CanInspectUnit(unit) or not UnitExists(unit) or not UnitIsPlayer(unit) then
        return
    end

    if UnitCanCooperate and not UnitCanCooperate("player", unit) then
        return
    end

    if UnitIsFriend and not UnitIsFriend("player", unit) then
        return
    end

    if not playerKey then
        local playerName, playerRealm = UnitName(unit)
        playerKey = FullName(playerName, playerRealm)
    end
    RequestNearbyLanguageByPlayerKey(playerKey)
end

ns.SyncNewPlayerLanguage = function(playerName, lang)
    if not playerName or not IsSupportedLanguage(lang) then
        return
    end

    if LanguageScoutDB.syncGuild and IsInGuild() then
        TraceSyncEvent("PUBLISH ENTRY", "GUILD", playerName, lang)
        SendSyncMessage("ENTRY:" .. playerName .. ":" .. lang, "GUILD")
    end

    if LanguageScoutDB.syncParty then
        local distribution = GetGroupSyncDistribution()
        if distribution then
            TraceSyncEvent("PUBLISH ENTRY", distribution, playerName, lang)
            SendSyncMessage("ENTRY:" .. playerName .. ":" .. lang, distribution)
        end
    end
end

ns.SyncOwnLanguage = function()
    local myPlayerKey = GetCurrentPlayerKey()
    local ownLanguage = GetOwnEffectiveLanguage and GetOwnEffectiveLanguage()
    if not myPlayerKey or not IsSupportedLanguage(ownLanguage) then
        return
    end

    ns.SyncNewPlayerLanguage(myPlayerKey, ownLanguage)
end

local function UpdateSyncRequests()
    local currentGroupState = "NONE"
    local groupDistribution = GetGroupSyncDistribution()
    if groupDistribution then
        currentGroupState = groupDistribution .. ":" .. tostring(GetNumGroupMembers() or 0)
    end

    if currentGroupState ~= lastGroupSyncState then
        lastGroupSyncState = currentGroupState

        if groupDistribution then
            RequestSync(groupDistribution)
        end
    end

    local currentGuildState = IsInGuild() and "GUILD" or "NONE"
    if currentGuildState ~= lastGuildSyncState then
        lastGuildSyncState = currentGuildState

        if currentGuildState == "GUILD" then
            RequestSync("GUILD")
        end
    end
end

local function SendLanguage(target)
    local ownLanguage = GetOwnEffectiveLanguage and GetOwnEffectiveLanguage()
    if not IsSupportedLanguage(ownLanguage) then
        return
    end

    SendAddonMessage("LANG:" .. ownLanguage, "WHISPER", target, false)
end

local function ApplySyncedEntry(playerName, lang, sender)
    local playerKey = NormalizePlayerKey(playerName)
    local senderKey = NormalizePlayerKey(sender)
    -- Only the sender can confirm their own language. Relayed records remain
    -- add-only guesses, even if the original peer had confirmed them locally.
    if playerKey and playerKey == senderKey then
        return SetSelfReportedPlayerLanguage(playerName, lang)
    end
    return AddPlayerLanguageIfMissing(playerName, lang, "sync")
end

ProcessAddonMessage = function(msg, distribution, sender)
    if msg:sub(1, 7) == "BATCH1:" then
        if #msg == 7 or not IsSyncDistributionEnabled(distribution) then return end

        -- Validate the whole packet before applying any entry.
        local entries, offset = {}, 8
        while offset <= #msg do
            local name, lang, nextOffset = msg:match("^([^:]+):([A-Z]+)()", offset)
            if not name or not IsValidSyncedPlayerName(name) or not IsSupportedLanguage(lang)
                or #entries >= SYNC_BROADCAST_BATCH_SIZE * 2
            then
                return
            end
            entries[#entries + 1] = name
            entries[#entries + 1] = lang
            if nextOffset > #msg then break end
            if msg:sub(nextOffset, nextOffset) ~= ":" or nextOffset == #msg then return end
            offset = nextOffset + 1
        end
        for index = 1, #entries, 2 do
            ApplySyncedEntry(entries[index], entries[index + 1], sender)
        end
        return #entries / 2
    end

    local playerName, entryLanguage = msg:match("^ENTRY:([^:]+):([A-Z]+)$")
    if playerName then
        if IsSyncDistributionEnabled(distribution) and IsValidSyncedPlayerName(playerName) then
            ApplySyncedEntry(playerName, entryLanguage, sender)
        end
        return
    end

    local remoteVersion = msg:sub(1, #VERSION_MESSAGE_PREFIX) == VERSION_MESSAGE_PREFIX
        and msg:sub(#VERSION_MESSAGE_PREFIX + 1)
    if remoteVersion then
        HandleVersionMessage(remoteVersion)
        return
    end

    if msg == "REQ" then
        SendLanguage(sender)
        return
    end

    if msg == "SYNCREQ" or msg == "SYNCREQ2" then
        local senderKey = NormalizePlayerKey(sender)
        if senderKey and senderKey == GetCurrentPlayerKey() then
            return
        end

        if IsSyncDistributionEnabled(distribution) then
            QueueSyncResponse(distribution, sender, msg == "SYNCREQ2")
        end
        return
    end

    local batchRequester = msg:match("^SYNCSTART2:(.+)$")
    local syncStartRequester = batchRequester or msg:match("^SYNCSTART:(.+)$")
    if syncStartRequester and IsValidSyncedPlayerName(syncStartRequester) then
        local requesterKey = NormalizePlayerKey(syncStartRequester)
        local senderKey = NormalizePlayerKey(sender)
        local ownKey = GetCurrentPlayerKey()
        if requesterKey and senderKey and senderKey ~= ownKey then
            CancelPendingSyncResponse(distribution, requesterKey, batchRequester ~= nil)
            if requesterKey == ownKey or not batchRequester then
                pendingBatchRequestByDistribution[distribution] = nil
            end
        end
        return
    end

    local lang = msg:match("^LANG:([A-Z]+)$")
    if distribution == "WHISPER" and IsSupportedLanguage(lang) then
        local senderKey = NormalizePlayerKey(sender)
        if senderKey then
            ClearNearbyRequest(senderKey)
        end
        local wasAdded, playerKey = SetSelfReportedPlayerLanguage(sender, lang)
        if wasAdded and type(ShowAutoLanguageMarkedMessage) == "function" then
            ShowAutoLanguageMarkedMessage(playerKey or sender, lang, L("AUTO_REASON_PROPAGATION"))
        end
    end
end

ProcessQueuedCombatInboundMessages = function()
    if IsInCombat() then
        return
    end

    local processedCount = 0
    while processedCount < SYNC_INBOUND_BATCH_SIZE
        and pendingCombatInboundReadIndex <= pendingCombatInboundWriteIndex
    do
        local item = pendingCombatInboundMessages[pendingCombatInboundReadIndex]
        pendingCombatInboundMessages[pendingCombatInboundReadIndex] = nil
        pendingCombatInboundReadIndex = pendingCombatInboundReadIndex + 1

        if item then
            TraceSyncEvent(
                "IN " .. GetSyncMessageCommand(item.msg),
                item.distribution,
                item.sender,
                "dequeued"
            )
            processedCount = processedCount + (ProcessAddonMessage(item.msg, item.distribution, item.sender) or 1)
        end
    end

    if pendingCombatInboundReadIndex > pendingCombatInboundWriteIndex then
        pendingCombatInboundMessages = {}
        pendingCombatInboundReadIndex = 1
        pendingCombatInboundWriteIndex = 0
        return
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(SYNC_QUEUE_BATCH_DELAY, ProcessQueuedCombatInboundMessages)
    else
        ProcessQueuedCombatInboundMessages()
    end
end

local function HandleAddonCommEvent(_, event, ...)
    if event == "PLAYER_REGEN_ENABLED" then
        ProcessQueuedCombatInboundMessages()

        for distribution, pending in pairs(pendingCombatSyncBroadcastByDistribution) do
            pendingCombatSyncBroadcastByDistribution[distribution] = nil
            if activeSyncBroadcastByDistribution[distribution] then
                ContinueKnownLanguageBroadcast(distribution)
            elseif type(pending) == "table" then
                BroadcastKnownLanguages(distribution, pending.requesterKey, pending.batch)
            end
        end

        ProcessQueuedCombatOutboundMessages()
        return
    end

    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_GUILD_UPDATE" or event == "PLAYER_LOGIN" then
        UpdateSyncRequests()
        return
    end

    local prefix, msg, distribution, sender = ...
    if ns.IsSecret(prefix) or ns.IsSecret(msg) or ns.IsSecret(distribution) or ns.IsSecret(sender) then return end
    if prefix ~= ADDON_PREFIX then
        return
    end
    if type(msg) ~= "string" or #msg > SYNC_MESSAGE_BYTE_LIMIT or type(sender) ~= "string" or sender == "" then
        return
    end

    if IsInCombat() then
        TraceSyncEvent("QUEUE IN " .. GetSyncMessageCommand(msg), distribution, sender, "combat")
        QueueCombatInboundMessage(msg, distribution, sender)
        return
    end

    if IsSyncDebugTraceActive and IsSyncDebugTraceActive() then
        TraceSyncEvent("IN " .. GetSyncMessageCommand(msg), distribution, sender)
    end
    ProcessAddonMessage(msg, distribution, sender)
end

addonCommFrame:SetScript("OnEvent", function(frame, event, ...)
    local debugStart = ns.DebugPerfStart and ns.DebugPerfStart()
    HandleAddonCommEvent(frame, event, ...)
    if debugStart and ns.DebugPerfStop then
        ns.DebugPerfStop("Sync:" .. tostring(event), debugStart)
    end
end)
