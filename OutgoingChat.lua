local _, ns = ...

local MAX_CHAT_MESSAGE_BYTES = 255

local function PrefixOutgoingMessage(message, chatType, maxBytes)
    if ns.IsSecret(message) or type(message) ~= "string"
        or not ns.IsOutgoingPrefixChannelEnabled(chatType)
        or not message:find("%S") or message:match("^%s*/")
    then
        return message
    end

    local language = ns.GetOwnEffectiveLanguage()
    if not ns.IsSupportedLanguage(language) then return message end

    -- Preserve explicit supported language tags rather than stacking tags.
    local existingTag = message:match("^%s*%[([%a]+)%]")
    if existingTag then
        existingTag = existingTag:upper()
        if ns.IsSupportedLanguage(existingTag) then return message end
    end

    local prefix = "[" .. language .. "] "
    local limit = MAX_CHAT_MESSAGE_BYTES
    if not ns.IsSecret(maxBytes) and type(maxBytes) == "number" and maxBytes > 0 then
        limit = math.min(limit, maxBytes)
    end
    -- Never truncate player text, split UTF-8, or damage a link to make room for a tag.
    if #message + #prefix > limit then return message end
    return prefix .. message
end

local function OnPreSendText(editBox)
    if ns.IsSecret(editBox) or not editBox or type(editBox.GetText) ~= "function"
        or type(editBox.SetText) ~= "function"
    then
        return
    end
    local chatType
    if editBox.GetChatType then
        chatType = editBox:GetChatType()
    elseif editBox.GetAttribute then
        chatType = editBox:GetAttribute("chatType")
    end
    local message = editBox:GetText()
    if ns.IsSecret(message) then return end
    local maxBytes = editBox.GetMaxBytes and editBox:GetMaxBytes()
    local prefixed = PrefixOutgoingMessage(message, chatType, maxBytes)
    if prefixed ~= message then editBox:SetText(prefixed) end
end

local registryHookRegistered, legacyHookRegistered = false, false
local function RegisterOutgoingChatHooks()
    if not registryHookRegistered and EventRegistry and EventRegistry.RegisterCallback then
        -- Modern clients expose a user-addon callback after slash-command parsing.
        EventRegistry:RegisterCallback("ChatFrame.OnEditBoxPreSendText", function(_, editBox)
            OnPreSendText(editBox)
        end, ns)
        registryHookRegistered = true
    end
    if not legacyHookRegistered and type(ChatEdit_ParseText) == "function" and hooksecurefunc then
        -- Older clients read the edit box immediately after this parser returns.
        hooksecurefunc("ChatEdit_ParseText", function(editBox, send)
            if send == 1 then OnPreSendText(editBox) end
        end)
        legacyHookRegistered = true
    end
end

RegisterOutgoingChatHooks()
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", RegisterOutgoingChatHooks)
