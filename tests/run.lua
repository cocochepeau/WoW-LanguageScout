-- Native Lua 5.1 can also run this from the addon directory: lua tests/run.lua
local root = addonRoot or "."
local files = { "Localization.lua", "Core.lua", "PlayerData.lua", "UIHooks.lua", "Nameplates.lua", "OutgoingChat.lua", "AutoDetect.lua", "Sync.lua", "Options.lua" }
local manifest = assert(io.open(root .. "/LanguageScout.toc", "rb"))
local addonVersion = assert(manifest:read("*a"):match("## Version:%s*([^\r\n]+)"))
manifest:close()

local function installSettingsMocks(e)
    e.widgets, e.categories = {}, {}
    local createFrame = e.CreateFrame
    local function enhance(f, kind, parent, template)
        f.kind, f.parent, f.template, f.shown, f.enabled, f.text = kind, parent, template, true, true, ""
        e.widgets[#e.widgets + 1] = f
        function f:ClearAllPoints() self.points = {} end
        function f:SetPoint(...) self.points = self.points or {}; table.insert(self.points, { ... }) end
        function f:SetSize(w, h) self.width, self.height = w, h end
        function f:SetWidth(w) self.width = w end
        function f:SetHeight(h) self.height = h end
        function f:GetWidth() return self.width or 600 end
        function f:GetHeight() return self.height or 200 end
        function f:Hide() self.shown = false end
        function f:Show()
            local wasShown = self.shown
            self.shown = true
            if not wasShown and self.scripts and self.scripts.OnShow then self.scripts.OnShow(self) end
        end
        function f:IsShown() return self.shown end
        function f:SetText(text)
            local changed = self.text ~= text
            self.text = text
            if changed and self.scripts and self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end
        end
        function f:GetText() return self.text end
        function f:GetStringWidth() return #(self.text or "") * 6 end
        function f:SetChecked(checked) self.checked = checked and true or false end
        function f:GetChecked() return self.checked end
        function f:SetEnabled(enabled) self.enabled = enabled end
        function f:GetScript(script) return self.scripts[script] end
        function f:Click()
            if not self.enabled then return end
            if self.kind == "CheckButton" then self.checked = not self.checked end
            if self.scripts.OnClick then self.scripts.OnClick(self) end
        end
        function f:SetScrollChild(child) self.scrollChild = child end
        function f:GetVerticalScroll() return self.scroll or 0 end
        function f:SetVerticalScroll(value)
            local previous = self.scroll or 0
            self.scroll = value
            if previous ~= value and self.scripts.OnVerticalScroll then self.scripts.OnVerticalScroll(self, value) end
        end
        function f:CreateFontString() return enhance({}, "FontString", self) end
        function f:GetFontString() self.fontString = self.fontString or self:CreateFontString(); return self.fontString end
        function f:SetOwner(owner) self.owner, self.doubleLines = owner, {} end
        function f:IsOwned(owner) return self.owner == owner end
        function f:AddLine() end
        function f:AddDoubleLine(...) self.doubleLines = self.doubleLines or {}; table.insert(self.doubleLines, { ... }) end
        for _, method in ipairs({ "SetJustifyH", "SetJustifyV", "SetTextColor", "SetAutoFocus", "SetMaxLetters", "EnableMouse", "EnableMouseWheel", "UpdateScrollChildRect", "ClearFocus", "SetFocus", "HighlightText" }) do
            f[method] = function() end
        end
        if kind == "CheckButton" then f.Text = f:CreateFontString() end
        return f
    end
    e.CreateFrame = function(kind, name, parent, template) return enhance(createFrame(), kind, parent, template) end
    enhance(e.GameTooltip, "GameTooltip")
    local function category(frame, title, parent)
        local c = { frame = frame, title = title, parent = parent, id = #e.categories + 1 }
        function c:GetID() return self.id end
        e.categories[#e.categories + 1] = c
        return c
    end
    e.Settings = {
        RegisterCanvasLayoutCategory = category,
        RegisterCanvasLayoutSubcategory = function(parent, frame, title) return category(frame, title, parent) end,
        RegisterAddOnCategory = function() end,
        OpenToCategory = function(id) e.openCategoryId = id end,
    }
    e.UIDropDownMenu_Initialize = function(dropdown, initialize) dropdown.initialize = initialize end
    e.UIDropDownMenu_SetWidth = function(dropdown, width) dropdown.width = width end
    e.UIDropDownMenu_SetSelectedValue = function(dropdown, value) dropdown.selectedValue = value end
    e.UIDropDownMenu_SetText = function(dropdown, text) dropdown.text = text end
    e.UIDropDownMenu_CreateInfo = function() return {} end
    e.UIDropDownMenu_AddButton = function(info) e.menuItems[#e.menuItems + 1] = info end
    function e.findCheckbox(labelKey)
        for _, widget in ipairs(e.widgets) do
            if widget.kind == "CheckButton" and widget.Text.text == e.ns.L(labelKey) then return widget end
        end
        error("missing checkbox " .. labelKey)
    end
    function e.selectDropdown(dropdown, value)
        e.menuItems = {}
        dropdown.initialize()
        for _, info in ipairs(e.menuItems) do
            if info.value == value then info.func(); return end
        end
        error("missing dropdown value " .. tostring(value))
    end
    function e.playerRows()
        local rows = {}
        for _, widget in ipairs(e.widgets) do
            if widget.entry and widget.nameText and widget.shown then rows[#rows + 1] = widget end
        end
        return rows
    end
end

local function newAddon(savedDB, surnames, withSettings, locale, preferredSettings, outgoingHookMode)
    if surnames == nil then surnames = true end
    local env = setmetatable({ LanguageScoutDB = savedDB, usesSurnames = surnames, testLocale = locale or "enUS", preferredSettings = preferredSettings, outgoingHookMode = outgoingHookMode }, { __index = _G })
    env._G = env
    setfenv(function()
        ns, frames, filters, sent, timers, hooks, messages = {}, {}, {}, {}, {}, {}, {}
        now, inCombat, dirtyCount = 100, false, 0
        units = { player = { name = usesSurnames and "Reviewer Tester" or "Reviewer", realm = "TestRealm" } }
        function GetTime() return now end
        function GetServerTime() return 1700000000 + now end
        function GetLocale() return testLocale end
        if preferredSettings then
            C_AccountServices = {
                GetPreferredPlaySettings = function() return preferredSettings.loaded, preferredSettings.localeID end,
                RequestPreferredPlaySettings = function() end,
            }
            function GetAvailableLocaleInfo()
                return {
                    { localeId = 1, localeName = "deDE" },
                    { localeId = 2, localeName = "frFR" },
                    { localeId = 3, localeName = "enUS" },
                    { localeId = 4, localeName = "zhCN" },
                }
            end
        end
        function GetBuildInfo() return "test", "", "", usesSurnames and 16001 or 20506 end
        function RegionalUniqueNamesEnabled() return usesSurnames end
        function GetNormalizedRealmName() return "TestRealm" end
        function UnitName(unit)
            local info = units[unit]
            if info then return info.name, usesSurnames and "" or info.realm end
        end
        UnitNameUnmodified = UnitName
        function UnitExists(unit) return units[unit] ~= nil end
        function UnitIsPlayer(unit) return units[unit] ~= nil end
        function UnitClass(unit) return "Mage", units[unit] and units[unit].class or "MAGE" end
        function UnitGUID(unit) return units[unit] and "Player-" .. units[unit].name end
        function UnitCanCooperate() return true end
        function UnitIsFriend() return true end
        function GetGuildInfo(unit) return units[unit] and units[unit].guild end
        function IsInGuild() return false end
        function IsInGroup() return false end
        function IsInRaid() return false end
        function InCombatLockdown() return inCombat end
        function wipe(t) for k in pairs(t) do t[k] = nil end end
        function print(message) messages[#messages + 1] = message end
        SlashCmdList, StaticPopupDialogs = {}, {}
        YES, NO = "Yes", "No"
        function SetItemRef() end
        function hooksecurefunc(name, f) hooks[name] = f end
        function ChatEdit_ParseText() end
        registryCallbacks = {}
        EventRegistry = {
            RegisterCallback = function(_, event, callback, owner)
                registryCallbacks[event] = { callback = callback, owner = owner }
            end,
        }
        if outgoingHookMode == "legacy" or outgoingHookMode == "late" then EventRegistry = nil end
        if outgoingHookMode == "modern" or outgoingHookMode == "late" then ChatEdit_ParseText = nil end
        function CreateFrame()
            local f = { events = {}, scripts = {} }
            function f:RegisterEvent(e) self.events[e] = true end
            function f:IsEventRegistered(e) return self.events[e] end
            function f:UnregisterEvent(e) self.events[e] = nil end
            function f:SetScript(e, cb) self.scripts[e] = cb end
            function f:HookScript(e, cb) self.scripts[e] = cb end
            function f:HasScript() return true end
            function f:SetOwner() end
            frames[#frames + 1] = f
            return f
        end
        GameTooltip, UIParent = CreateFrame(), {}
        function ChatFrame_AddMessageEventFilter(e, f)
            filters[e] = filters[e] or {}
            table.insert(filters[e], f)
        end
        C_Timer = { After = function(delay, cb) timers[#timers + 1] = { at = now + delay, cb = cb } end }
        C_ChatInfo = {
            RegisterAddonMessagePrefix = function() end,
            SendAddonMessage = function(prefix, msg, distribution, target)
                sent[#sent + 1] = { prefix = prefix, msg = msg, distribution = distribution, target = target }
            end,
        }
        C_AddOns = {
            GetAddOnMetadata = function(name, field)
                if name == "LanguageScout" and field == "Version" then return addonVersion end
            end,
        }
        function emit(event, ...)
            for _, frame in ipairs(frames) do
                if frame.events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event, ...) end
            end
        end
        function receive(msg, sender, distribution)
            emit("CHAT_MSG_ADDON", "LMARK", msg, distribution or "GUILD", sender or "Peer Tester")
        end
        function detect(msg, author, event)
            event = event or "CHAT_MSG_CHANNEL"
            local list = filters[event]
            return list[#list](nil, event, msg, author or "Target Tester")
        end
        function advance(seconds)
            local limit, count = now + seconds, 0
            while true do
                local nextIndex, nextTimer
                for i, t in ipairs(timers) do
                    if t.at <= limit and (not nextTimer or t.at < nextTimer.at) then nextIndex, nextTimer = i, t end
                end
                if not nextTimer then break end
                table.remove(timers, nextIndex)
                now = nextTimer.at
                nextTimer.cb()
                count = count + 1
                assert(count < 10000, "timer loop")
            end
            now = limit
        end
        function undo(playerKey, lang)
            ns.ShowAutoLanguageMarkedMessage(playerKey, lang, "test", true)
            hooks.SetItemRef("languagescoutundo:" .. playerKey .. ":" .. lang)
        end
    end, env)()
    if withSettings then installSettingsMocks(env) end
    for _, filename in ipairs(files) do
        setfenv(assert(loadfile(root .. "/" .. filename)), env)("LanguageScout", env.ns)
    end
    local markKnownPlayersDirty = env.ns.MarkKnownPlayersDirty
    env.ns.MarkKnownPlayersDirty = function()
        env.dirtyCount = env.dirtyCount + 1
        markKnownPlayersDirty()
    end
    return env
end

local passed, failed = 0, 0
local function equal(actual, expected, message)
    assert(actual == expected, (message or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function test(label, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL " .. label .. ": " .. tostring(err))
    end
end

for _, surnames in ipairs({ true, false }) do
    local env = newAddon(nil, surnames)
    local detectionPassed, total, failures = env.ns.RunAutoDetectSelfTests()
    local petPassed, petTotal, petFailures = env.ns.RunPetNameSelfTests()
    print((surnames and "Forever" or "Anniversary") .. " built-in checks: " .. (detectionPassed + petPassed) .. "/" .. (total + petTotal))
    for _, failure in ipairs(failures) do print(failure) end
    for _, failure in ipairs(petFailures) do print(failure) end
    passed = passed + detectionPassed + petPassed
    failed = failed + total - detectionPassed + petTotal - petPassed
end

for _, channel in ipairs({ "GUILD", "SAY", "YELL" }) do
    local event = "CHAT_MSG_" .. channel
    test(channel .. " detects and stores the sender's language", function()
        local e = newAddon()
        local blocked, msg, author = e.detect("Bonjour", "Target Tester", event)
        equal(blocked, false)
        equal(msg, "Bonjour")
        equal(author, "Target Tester")
        equal(e.LanguageScoutDB.players["Target Tester"].lang, "FR")
        equal(e.LanguageScoutDB.players["Target Tester"].source, "automatic")
    end)

    test(channel .. " respects global and per-language autodetection settings", function()
        local e = newAddon()
        e.LanguageScoutDB.autoDetect = false
        e.detect("Bonjour", "Target Tester", event)
        equal(e.LanguageScoutDB.players["Target Tester"], nil)
        e.LanguageScoutDB.autoDetect = true
        e.ns.SetLanguageAutoDetectEnabled("FR", false)
        e.detect("Bonjour", "Target Tester", event)
        equal(e.LanguageScoutDB.players["Target Tester"], nil)
    end)

    test(channel .. " protects manual and self-reported records", function()
        local e = newAddon()
        e.ns.SetPlayerLanguage("Manual Tester", "RU", false, "manual")
        e.ns.SetSelfReportedPlayerLanguage("Confirmed Tester", "RU")
        e.detect("Привіт друзі", "Manual Tester", event)
        e.detect("Привіт друзі", "Confirmed Tester", event)
        equal(e.LanguageScoutDB.players["Manual Tester"].lang, "RU")
        equal(e.LanguageScoutDB.players["Manual Tester"].source, "manual")
        equal(e.LanguageScoutDB.players["Confirmed Tester"].lang, "RU")
        equal(e.LanguageScoutDB.players["Confirmed Tester"].selfReported, true)
    end)

    test(channel .. " leaves ambiguous Cyrillic unknown", function()
        local e = newAddon()
        e.detect("привет всем", "Target Tester", event)
        equal(e.LanguageScoutDB.players["Target Tester"], nil)
    end)

    test(channel .. " respects undo on repeated chat and peer sync", function()
        local e = newAddon()
        e.detect("Bonjour", "Target Tester", event)
        e.undo("Target Tester", "FR")
        e.detect("Bonjour", "Target Tester", event)
        e.receive("ENTRY:Target Tester:FR")
        equal(e.LanguageScoutDB.players["Target Tester"], nil)
    end)

    test(channel .. " includes its source in detection debug feedback", function()
        local e = newAddon()
        e.LanguageScoutDB.debugPerformance = true
        e.detect("Bonjour", "Target Tester", event)
        assert(e.messages[#e.messages]:find('source "' .. channel:lower() .. '" (' .. event .. ')', 1, true))
    end)
end

test("manual RU and UA survive distinguishing chat evidence", function()
    for _, sample in ipairs({ { "RU", "Привіт друзі" }, { "UA", "быстро" } }) do
        local e = newAddon()
        e.ns.SetPlayerLanguage("Target Tester", sample[1], false, "manual")
        e.detect(sample[2])
        equal(e.LanguageScoutDB.players["Target Tester"].lang, sample[1])
        equal(e.LanguageScoutDB.players["Target Tester"].source, "manual")
    end
end)

test("automatic RU and UA can still be corrected", function()
    local e = newAddon()
    e.ns.SetPlayerLanguage("Target Tester", "RU", false, "automatic")
    e.detect("Привіт друзі")
    equal(e.LanguageScoutDB.players["Target Tester"].lang, "UA")
    e.detect("быстро")
    equal(e.LanguageScoutDB.players["Target Tester"].lang, "RU")
end)

test("bulk automatic updates also protect manual and self-reported records", function()
    local e = newAddon()
    e.ns.SetPlayerLanguage("Manual Tester", "RU", false, "manual")
    e.ns.SetSelfReportedPlayerLanguage("Confirmed Tester", "RU")
    e.ns.AddPlayerLanguageIfMissing("Guessed Tester", "RU", "automatic")
    equal(e.ns.SetPlayerLanguagesBulk({ "Manual Tester", "Confirmed Tester", "Guessed Tester" }, "UA", "automatic"), 1)
    equal(e.LanguageScoutDB.players["Manual Tester"].lang, "RU")
    equal(e.LanguageScoutDB.players["Confirmed Tester"].lang, "RU")
    equal(e.LanguageScoutDB.players["Guessed Tester"].lang, "UA")
end)

test("own LANG replaces automatic, guild, sync and legacy guesses", function()
    for _, source in ipairs({ "automatic", "guild", "sync", "legacy" }) do
        local e = newAddon({ players = { ["Target Tester"] = { lang = "DE", source = source, updatedAt = 10 } } })
        e.receive("LANG:FR", "Target Tester", "WHISPER")
        local record = e.LanguageScoutDB.players["Target Tester"]
        equal(record.lang, "FR")
        equal(record.source, "sync")
        equal(record.selfReported, true)
        equal(e.ns.GetRecordCounts().playerLanguages, 1)
    end
end)

test("own declarations preserve manual choices", function()
    local e = newAddon()
    e.ns.SetPlayerLanguage("Target Tester", "DE", false, "manual")
    e.receive("LANG:FR", "Target Tester", "WHISPER")
    e.receive("ENTRY:Target Tester:FR", "Target Tester")
    e.receive("BATCH1:Target Tester:FR", "Target Tester")
    equal(e.LanguageScoutDB.players["Target Tester"].lang, "DE")
    equal(e.LanguageScoutDB.players["Target Tester"].source, "manual")
end)

test("own ENTRY and BATCH confirm only the sender", function()
    for _, packet in ipairs({ "ENTRY:Target Tester:FR", "BATCH1:Target Tester:FR:Other Tester:PL" }) do
        local e = newAddon()
        e.ns.AddPlayerLanguageIfMissing("Target Tester", "DE", "automatic")
        e.receive(packet, "Target Tester")
        equal(e.LanguageScoutDB.players["Target Tester"].lang, "FR")
        equal(e.LanguageScoutDB.players["Target Tester"].selfReported, true)
        if e.LanguageScoutDB.players["Other Tester"] then
            equal(e.LanguageScoutDB.players["Other Tester"].selfReported, nil)
        end
    end
end)

test("third-party ENTRY and BATCH cannot correct or confirm guesses", function()
    local e = newAddon()
    e.ns.AddPlayerLanguageIfMissing("Target Tester", "DE", "automatic")
    e.receive("ENTRY:Target Tester:FR")
    e.receive("BATCH1:Target Tester:FR:Other Tester:PL")
    equal(e.LanguageScoutDB.players["Target Tester"].lang, "DE")
    equal(e.LanguageScoutDB.players["Target Tester"].selfReported, nil)
    equal(e.LanguageScoutDB.players["Other Tester"].lang, "PL")
end)

test("same-language confirmation updates metadata and invalidates the list", function()
    local e = newAddon()
    e.ns.AddPlayerLanguageIfMissing("Target Tester", "RU", "automatic")
    local before = e.dirtyCount
    e.receive("LANG:RU", "Target Tester", "WHISPER")
    equal(e.LanguageScoutDB.players["Target Tester"].selfReported, true)
    equal(e.dirtyCount, before + 1)
    e.detect("Привіт друзі")
    equal(e.LanguageScoutDB.players["Target Tester"].lang, "RU")
    equal(e.ns.GetRecordCounts().playerLanguages, 1)
end)

test("self-reported records survive reload and automatic correction", function()
    local e = newAddon()
    e.receive("LANG:RU", "Target Tester", "WHISPER")
    e = newAddon(e.LanguageScoutDB)
    e.detect("Привіт друзі")
    equal(e.LanguageScoutDB.players["Target Tester"].lang, "RU")
    equal(e.LanguageScoutDB.players["Target Tester"].selfReported, true)
end)

test("updated self-report and explicit manual correction still work", function()
    local e = newAddon()
    e.receive("LANG:RU", "Target Tester", "WHISPER")
    e.receive("LANG:FR", "Target Tester", "WHISPER")
    equal(e.LanguageScoutDB.players["Target Tester"].lang, "FR")
    e.ns.SetPlayerLanguage("Target Tester", "FR", false, "manual")
    equal(e.LanguageScoutDB.players["Target Tester"].source, "manual")
    equal(e.LanguageScoutDB.players["Target Tester"].selfReported, nil)
end)

test("confirmation identity uses surname and realm normalization", function()
    local e = newAddon()
    e.ns.AddPlayerLanguageIfMissing("Target Tester", "DE", "automatic")
    e.receive("ENTRY:Target Tester:FR", "Target Other")
    equal(e.LanguageScoutDB.players["Target Tester"].lang, "DE")
    e = newAddon(nil, false)
    e.ns.AddPlayerLanguageIfMissing("Target-TestRealm", "DE", "automatic")
    e.receive("ENTRY:Target:FR", "Target-TestRealm")
    equal(e.LanguageScoutDB.players["Target-TestRealm"].selfReported, true)
end)

test("malformed LANG packets and non-whisper LANG are ignored", function()
    local e = newAddon()
    for _, msg in ipairs({ "prefixLANG:FR", "LANG:FR:extra", "LANG:XX", "LANG:fr" }) do
        e.receive(msg, "Target Tester", "WHISPER")
    end
    e.receive("LANG:FR", "Target Tester", "GUILD")
    equal(e.LanguageScoutDB.players["Target Tester"], nil)
end)

test("disabled guild and party sync cannot change records", function()
    local e = newAddon()
    e.LanguageScoutDB.syncGuild, e.LanguageScoutDB.syncParty = false, false
    e.receive("ENTRY:Target Tester:FR", "Target Tester")
    e.receive("BATCH1:Target Tester:FR", "Target Tester", "PARTY")
    equal(e.LanguageScoutDB.players["Target Tester"], nil)
end)

test("nearby requests can confirm guesses but skip confirmed and manual records", function()
    for _, source in ipairs({ "automatic", "guild", "sync", "manual", "self" }) do
        local e = newAddon()
        if source == "self" then e.ns.SetSelfReportedPlayerLanguage("Target Tester", "DE")
        else e.ns.AddPlayerLanguageIfMissing("Target Tester", "DE", source) end
        e.ns.RequestNearbyLanguageByPlayerKey("Target Tester")
        e.advance(0)
        equal(#e.sent, (source == "self" or source == "manual") and 0 or 1)
        if #e.sent > 0 then
            equal(e.sent[1].msg, "REQ")
            equal(e.sent[1].target, "Target Tester")
            e.ns.RequestNearbyLanguageByPlayerKey("Target Tester")
            e.advance(0)
            equal(#e.sent, 1, "nearby throttle")
        end
    end
end)

test("unit detection requests confirmation for an already inferred player", function()
    local e = newAddon()
    e.units.target = { name = "Target Tester" }
    e.ns.AddPlayerLanguageIfMissing("Target Tester", "DE", "automatic")
    e.ns.TryAutoDetectFromUnit("target")
    e.advance(0)
    equal(e.sent[1].msg, "REQ")
end)

test("an intervening confirmation cancels a queued nearby request", function()
    local e = newAddon()
    e.ns.RequestNearbyLanguageByPlayerKey("Target Tester")
    e.receive("LANG:DE", "Target Tester", "WHISPER")
    e.advance(0)
    equal(#e.sent, 0)
end)

test("ambiguous Cyrillic text and names stay unknown", function()
    local e = newAddon()
    e.detect("привет всем")
    e.detect("hello", "Анна Иванова")
    equal(e.LanguageScoutDB.players["Target Tester"], nil)
    equal(e.LanguageScoutDB.players["Анна Иванова"], nil)
    equal(#e.sent, 0)
end)

test("distinguishing Cyrillic names still work", function()
    local e = newAddon()
    e.detect("hello", "Іван Тест")
    e.detect("hello", "Пётр Тест")
    equal(e.LanguageScoutDB.players["Іван Тест"].lang, "UA")
    equal(e.LanguageScoutDB.players["Пётр Тест"].lang, "RU")
end)

test("undo blocks peer ENTRY, BATCH and repeated automatic detection", function()
    local e = newAddon()
    e.detect("Suche Gruppe für Todesminen")
    e.undo("Target Tester", "DE")
    equal(e.LanguageScoutDB.players["Target Tester"], nil)
    e.receive("ENTRY:Target Tester:DE")
    e.receive("BATCH1:Target Tester:DE")
    e.detect("Suche Gruppe für Todesminen")
    equal(e.LanguageScoutDB.players["Target Tester"], nil)
    equal(e.ns.GetRecordCounts().playerLanguages, 0)
end)

test("undo rejection survives reload", function()
    local e = newAddon()
    e.ns.AddPlayerLanguageIfMissing("Target Tester", "DE", "automatic")
    e.undo("Target Tester", "DE")
    e = newAddon(e.LanguageScoutDB)
    e.receive("BATCH1:Target Tester:DE")
    e.detect("Suche Gruppe für Todesminen")
    equal(e.LanguageScoutDB.players["Target Tester"], nil)
end)

test("undo rejects only that language and respects later manual decisions", function()
    local e = newAddon()
    e.ns.AddPlayerLanguageIfMissing("Target Tester", "DE", "automatic")
    e.undo("Target Tester", "DE")
    e.receive("ENTRY:Target Tester:FR")
    equal(e.LanguageScoutDB.players["Target Tester"].lang, "FR")
    e.ns.SetPlayerLanguage("Target Tester", "DE", false, "manual")
    equal(e.LanguageScoutDB.players["Target Tester"].source, "manual")
    equal(e.LanguageScoutDB.rejectedPlayerLanguages["Target Tester"], nil)
end)

test("direct self-report can supersede a rejected guess", function()
    local e = newAddon()
    e.ns.AddPlayerLanguageIfMissing("Target Tester", "DE", "automatic")
    e.undo("Target Tester", "DE")
    e.receive("LANG:DE", "Target Tester", "WHISPER")
    equal(e.LanguageScoutDB.players["Target Tester"].selfReported, true)
    equal(e.LanguageScoutDB.rejectedPlayerLanguages["Target Tester"], nil)
end)

test("stale undo cannot delete a subsequent manual choice or self-report", function()
    for _, source in ipairs({ "manual", "self" }) do
        local e = newAddon()
        e.ns.AddPlayerLanguageIfMissing("Target Tester", "DE", "automatic")
        e.ns.ShowAutoLanguageMarkedMessage("Target Tester", "DE", "test", true)
        if source == "manual" then e.ns.SetPlayerLanguage("Target Tester", "DE", false, "manual")
        else e.ns.SetSelfReportedPlayerLanguage("Target Tester", "DE") end
        e.hooks.SetItemRef("languagescoutundo:Target Tester:DE")
        equal(e.LanguageScoutDB.players["Target Tester"].lang, "DE")
        equal(e.LanguageScoutDB.rejectedPlayerLanguages["Target Tester"], nil)
    end
end)

test("guild inference cannot restore an undone language", function()
    local e = newAddon()
    e.ns.AddPlayerLanguageIfMissing("Target Tester", "DE", "automatic")
    e.undo("Target Tester", "DE")
    equal(e.ns.SetPlayerLanguage("Target Tester", "DE", false, "guild"), false)
    equal(e.ns.SetPlayerLanguagesBulk({ "Target Tester" }, "DE", "guild"), 0)
    equal(e.LanguageScoutDB.players["Target Tester"], nil)
end)

test("explicit bulk manual assignment clears an undo rejection", function()
    local e = newAddon()
    e.ns.AddPlayerLanguageIfMissing("Target Tester", "DE", "automatic")
    e.undo("Target Tester", "DE")
    equal(e.ns.SetPlayerLanguagesBulk({ "Target Tester" }, "DE", "manual"), 1)
    equal(e.LanguageScoutDB.players["Target Tester"].source, "manual")
    equal(e.LanguageScoutDB.rejectedPlayerLanguages["Target Tester"], nil)
end)

test("combat-queued stale data cannot undo a rejection", function()
    local e = newAddon()
    e.ns.AddPlayerLanguageIfMissing("Target Tester", "DE", "automatic")
    e.inCombat = true
    e.receive("ENTRY:Target Tester:DE")
    e.undo("Target Tester", "DE")
    e.inCombat = false
    e.emit("PLAYER_REGEN_ENABLED")
    equal(e.LanguageScoutDB.players["Target Tester"], nil)
end)

test("combat-queued self-report can correct a guess", function()
    local e = newAddon()
    e.ns.AddPlayerLanguageIfMissing("Target Tester", "DE", "automatic")
    e.inCombat = true
    e.receive("LANG:FR", "Target Tester", "WHISPER")
    equal(e.LanguageScoutDB.players["Target Tester"].lang, "DE")
    e.inCombat = false
    e.emit("PLAYER_REGEN_ENABLED")
    equal(e.LanguageScoutDB.players["Target Tester"].lang, "FR")
    equal(e.LanguageScoutDB.players["Target Tester"].selfReported, true)
end)

test("malformed rejection data and confirmation metadata are sanitized", function()
    local e = newAddon({
        players = { ["Manual Tester"] = { lang = "DE", source = "manual", updatedAt = 10, selfReported = true } },
        rejectedPlayerLanguages = { ["Target Tester"] = { DE = true, XX = true, FR = "yes" }, bad = 4, empty = {} },
    })
    equal(e.LanguageScoutDB.players["Manual Tester"].selfReported, nil)
    equal(e.LanguageScoutDB.rejectedPlayerLanguages["Target Tester"].DE, true)
    equal(e.LanguageScoutDB.rejectedPlayerLanguages["Target Tester"].XX, nil)
    equal(e.LanguageScoutDB.rejectedPlayerLanguages["Target Tester"].FR, nil)
    equal(e.LanguageScoutDB.rejectedPlayerLanguages.bad, nil)
    equal(e.LanguageScoutDB.rejectedPlayerLanguages.empty, nil)
end)

test("malformed batches remain atomic", function()
    local e = newAddon()
    e.receive("BATCH1:Target Tester:DE:Other Tester:XX")
    equal(e.LanguageScoutDB.players["Target Tester"], nil)
end)

for _, setting in ipairs({
    { "channel", "CHAT_MSG_CHANNEL" },
    { "guild", "CHAT_MSG_GUILD" },
    { "party", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER" },
    { "raid", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER" },
    { "instance", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" },
    { "say", "CHAT_MSG_SAY" },
    { "yell", "CHAT_MSG_YELL" },
}) do
    test(setting[1] .. " switch gates every event in its channel", function()
        for index = 2, #setting do
            local e = newAddon()
            equal(e.ns.SetChatDetectionChannelEnabled(setting[1], false), true)
            e.detect("Bonjour", "Target Tester", setting[index])
            equal(e.LanguageScoutDB.players["Target Tester"], nil)
            e.ns.SetChatDetectionChannelEnabled(setting[1], true)
            e.detect("Bonjour", "Target Tester", setting[index])
            equal(e.LanguageScoutDB.players["Target Tester"].lang, "FR")
        end
    end)
end

test("channel settings preserve saved choices and migrate missing values", function()
    local e = newAddon({ autoDetect = false, chatDetectionChannels = { guild = false, say = false, unknown = false } })
    equal(e.LanguageScoutDB.chatDetectionChannels.guild, false)
    equal(e.LanguageScoutDB.chatDetectionChannels.say, false)
    equal(e.LanguageScoutDB.chatDetectionChannels.yell, true)
    equal(e.LanguageScoutDB.chatDetectionChannels.unknown, nil)
    equal(e.ns.IsChatDetectionChannelEnabled("CHAT_MSG_YELL"), false)
    e.LanguageScoutDB.autoDetect = true
    e = newAddon(e.LanguageScoutDB)
    equal(e.ns.IsChatDetectionChannelEnabled("CHAT_MSG_GUILD"), false)
    equal(e.ns.IsChatDetectionChannelEnabled("CHAT_MSG_YELL"), true)
    equal(e.ns.SetChatDetectionChannelEnabled("unknown", true), false)
end)

test("channel switches also gate corrections and character-name fallbacks", function()
    local e = newAddon()
    e.ns.AddPlayerLanguageIfMissing("Target Tester", "RU", "automatic")
    e.ns.SetChatDetectionChannelEnabled("say", false)
    e.detect("Привіт друзі", "Target Tester", "CHAT_MSG_SAY")
    equal(e.LanguageScoutDB.players["Target Tester"].lang, "RU")
    e.detect("hello", "Іван Тест", "CHAT_MSG_SAY")
    equal(e.LanguageScoutDB.players["Іван Тест"], nil)
end)

test("disabling one channel leaves other channels and cached detection working", function()
    local e = newAddon()
    e.ns.SetChatDetectionChannelEnabled("guild", false)
    e.detect("Bonjour", "Guild Tester", "CHAT_MSG_GUILD")
    e.detect("Bonjour", "Party Tester", "CHAT_MSG_PARTY")
    equal(e.LanguageScoutDB.players["Guild Tester"], nil)
    equal(e.LanguageScoutDB.players["Party Tester"].lang, "FR")
end)

test("settings checkboxes update detection and preserve choices under the master switch", function()
    local e = newAddon(nil, true, true)
    local guild = e.findCheckbox("AUTO_DETECT_CHANNEL_GUILD")
    guild:Click()
    equal(e.LanguageScoutDB.chatDetectionChannels.guild, false)
    e.detect("Bonjour", "Guild Tester", "CHAT_MSG_GUILD")
    equal(e.LanguageScoutDB.players["Guild Tester"], nil)
    local master = e.findCheckbox("AUTO_DETECT_CHAT")
    master:Click()
    equal(guild.enabled, false)
    equal(guild.checked, false)
    equal(e.findCheckbox("AUTO_DETECT_CHANNEL_PARTY").checked, true)
    master:Click()
    equal(guild.enabled, true)
    equal(guild.checked, false)
    guild:Click()
    e.detect("Bonjour", "Guild Tester", "CHAT_MSG_GUILD")
    equal(e.LanguageScoutDB.players["Guild Tester"].lang, "FR")
end)

test("restoring defaults refreshes every channel checkbox", function()
    local e = newAddon({ autoDetect = false, chatDetectionChannels = { guild = false, say = false } }, true, true)
    e.StaticPopupDialogs.LANGUAGESCOUT_RESTORE_DEFAULTS.OnAccept()
    for _, channel in ipairs(e.ns.CHAT_DETECTION_CHANNELS) do
        equal(e.LanguageScoutDB.chatDetectionChannels[channel.key], true)
        equal(e.findCheckbox(channel.labelKey).checked, true)
        equal(e.findCheckbox(channel.labelKey).enabled, true)
    end
end)

test("player list and tooltips distinguish confirmed languages from synced guesses", function()
    local e = newAddon(nil, true, true)
    e.receive("LANG:FR", "Confirmed Tester", "WHISPER")
    e.receive("ENTRY:Guessed Tester:DE")
    e.categories[1].frame:Show()
    local rows = e.playerRows()
    equal(#rows, 2)
    for _, row in ipairs(rows) do
        local expected = row.entry.playerName == "Confirmed Tester" and e.ns.L("PLAYER_SOURCE_CONFIRMED") or e.ns.L("PLAYER_SOURCE_SYNC")
        equal(row.sourceText.text, expected)
        row.scripts.OnEnter(row)
        equal(e.GameTooltip.doubleLines[2][2], expected)
    end
end)

test("source filter separates confirmed and third-party sync records", function()
    local e = newAddon(nil, true, true)
    e.receive("LANG:FR", "Confirmed Tester", "WHISPER")
    e.receive("ENTRY:Guessed Tester:DE")
    e.categories[1].frame:Show()
    local dropdown
    for _, widget in ipairs(e.widgets) do
        if widget.initialize and widget.text == e.ns.L("ALL_SOURCES") then dropdown = widget; break end
    end
    assert(dropdown, "missing source dropdown")
    e.selectDropdown(dropdown, "confirmed")
    equal(#e.playerRows(), 1)
    equal(e.playerRows()[1].entry.playerName, "Confirmed Tester")
    e.selectDropdown(dropdown, "sync")
    equal(#e.playerRows(), 1)
    equal(e.playerRows()[1].entry.playerName, "Guessed Tester")
    e.selectDropdown(dropdown, nil)
    equal(#e.playerRows(), 2)
end)

for _, locale in ipairs({ "enUS", "deDE", "esES", "esMX", "frFR", "ruRU" }) do
    test(locale .. " settings have translated channel and source labels", function()
        local e = newAddon(nil, true, true, locale)
        for _, channel in ipairs(e.ns.CHAT_DETECTION_CHANNELS) do
            assert(e.ns.L(channel.labelKey) ~= channel.labelKey)
            equal(e.findCheckbox(channel.labelKey).checked, true)
        end
        assert(e.ns.L("PLAYER_SOURCE_CONFIRMED") ~= "PLAYER_SOURCE_CONFIRMED")
        assert(e.ns.L("PLAYER_SOURCE_CONFIRMED") ~= e.ns.L("PLAYER_SOURCE_SYNC"))
    end)
end

local function undonePanel(e)
    for _, category in ipairs(e.categories) do
        if category.title == e.ns.L("UNDONE_GUESSES") then return category.frame end
    end
    error("missing undone guesses settings page")
end

local function undoneRows(e)
    local rows = {}
    for _, widget in ipairs(e.widgets) do
        if widget.guess and widget.allowButton and widget.shown then rows[#rows + 1] = widget end
    end
    return rows
end

local function assertEffectiveLanguage(e, expected)
    local text = string.format(e.ns.L("EFFECTIVE_LANGUAGE"), expected)
    for _, widget in ipairs(e.widgets) do
        if widget.kind == "FontString" and widget.parent == e.categories[1].frame and widget.text == text then return end
    end
    error("effective language label did not show " .. text)
end

local function ownLanguageDropdown(e)
    for _, widget in ipairs(e.widgets) do
        if widget.initialize and widget.parent == e.categories[1].frame
            and widget.text == e.ns.L("AUTO_LANGUAGE")
        then
            return widget
        end
    end
    error("missing own-language dropdown")
end

test("undone page lists saved pairs in player and language order", function()
    local e = newAddon({ rejectedPlayerLanguages = {
        ["Zulu Tester"] = { FR = true }, ["Alpha Tester"] = { FR = true, DE = true },
    } }, true, true)
    undonePanel(e):Show()
    local rows = undoneRows(e)
    equal(#rows, 3)
    equal(rows[1].guess.playerName, "Alpha Tester")
    equal(rows[1].guess.lang, "DE")
    equal(rows[2].guess.lang, "FR")
    equal(rows[3].guess.playerName, "Zulu Tester")
    equal(rows[1].nameText.text, "Alpha Tester")
    equal(rows[1].languageText.text, e.ns.GetLanguageDisplayName("DE"))
end)

test("Allow again removes only that rejection and refreshes the list", function()
    local e = newAddon({ rejectedPlayerLanguages = {
        ["Target Tester"] = { DE = true, FR = true }, ["Other Tester"] = { DE = true },
    } }, true, true)
    undonePanel(e):Show()
    for _, row in ipairs(undoneRows(e)) do
        if row.guess.playerName == "Target Tester" and row.guess.lang == "DE" then row.allowButton:Click(); break end
    end
    equal(#undoneRows(e), 2)
    equal(e.LanguageScoutDB.rejectedPlayerLanguages["Target Tester"].DE, nil)
    equal(e.LanguageScoutDB.rejectedPlayerLanguages["Target Tester"].FR, true)
    equal(e.LanguageScoutDB.rejectedPlayerLanguages["Other Tester"].DE, true)
    equal(e.LanguageScoutDB.players["Target Tester"], nil)
    equal(#e.sent, 0)
end)

test("Allow again permits fresh chat detection after reload", function()
    local e = newAddon({ rejectedPlayerLanguages = { ["Target Tester"] = { DE = true } } }, true, true)
    undonePanel(e):Show()
    undoneRows(e)[1].allowButton:Click()
    equal(e.LanguageScoutDB.rejectedPlayerLanguages["Target Tester"], nil)
    e = newAddon(e.LanguageScoutDB)
    e.detect("Suche Gruppe für Todesminen")
    equal(e.LanguageScoutDB.players["Target Tester"].lang, "DE")
    equal(e.LanguageScoutDB.players["Target Tester"].source, "automatic")
end)

test("Allow again permits fresh peer sync and preserves existing manual records", function()
    local e = newAddon({
        players = { ["Manual Tester"] = { lang = "FR", source = "manual", updatedAt = 10 } },
        rejectedPlayerLanguages = { ["Target Tester"] = { DE = true }, ["Manual Tester"] = { DE = true } },
    })
    equal(e.ns.AllowPlayerLanguageAgain("Target Tester", "DE"), true)
    e.receive("ENTRY:Target Tester:DE")
    equal(e.LanguageScoutDB.players["Target Tester"].lang, "DE")
    equal(e.ns.AllowPlayerLanguageAgain("Manual Tester", "DE"), true)
    equal(e.LanguageScoutDB.players["Manual Tester"].lang, "FR")
    equal(e.LanguageScoutDB.players["Manual Tester"].source, "manual")
end)

test("invalid or already allowed pairs leave rejections unchanged", function()
    local e = newAddon({ rejectedPlayerLanguages = { ["Target Tester"] = { DE = true } } })
    equal(e.ns.AllowPlayerLanguageAgain("Target Tester", "XX"), false)
    equal(e.ns.AllowPlayerLanguageAgain("Target Tester", "FR"), false)
    equal(e.ns.AllowPlayerLanguageAgain("", "DE"), false)
    equal(e.ns.AllowPlayerLanguageAgain("Other Tester", "DE"), false)
    equal(e.LanguageScoutDB.rejectedPlayerLanguages["Target Tester"].DE, true)
end)

test("allowing a realm-less Anniversary pair uses its normalized identity", function()
    local e = newAddon({ rejectedPlayerLanguages = { ["Target-TestRealm"] = { DE = true } } }, false)
    equal(e.ns.AllowPlayerLanguageAgain("Target", "DE"), true)
    equal(e.LanguageScoutDB.rejectedPlayerLanguages["Target-TestRealm"], nil)
end)

test("undone page updates when undo or direct confirmation changes a rejection", function()
    local e = newAddon(nil, true, true)
    undonePanel(e):Show()
    e.detect("Bonjour")
    e.undo("Target Tester", "FR")
    equal(#undoneRows(e), 1)
    e.receive("LANG:FR", "Target Tester", "WHISPER")
    equal(#undoneRows(e), 0)
    local foundEmpty = false
    for _, widget in ipairs(e.widgets) do
        if widget.text == e.ns.L("NO_UNDONE_GUESSES") and widget.shown then foundEmpty = true end
    end
    equal(foundEmpty, true)
end)

test("manual decisions update an open undone list", function()
    local e = newAddon({ rejectedPlayerLanguages = { ["Target Tester"] = { DE = true } } }, true, true)
    undonePanel(e):Show()
    e.ns.SetPlayerLanguage("Target Tester", "DE", false, "manual")
    equal(#undoneRows(e), 0)
end)

test("removing the final undone row clamps the scrolled list to zero", function()
    local e = newAddon({ rejectedPlayerLanguages = { ["Target Tester"] = { DE = true } } }, true, true)
    undonePanel(e):Show()
    local scroll = undoneRows(e)[1].parent.parent
    scroll:SetVerticalScroll(100)
    undoneRows(e)[1].allowButton:Click()
    equal(scroll:GetVerticalScroll(), 0)
    equal(#undoneRows(e), 0)
end)

test("effective language follows manual selection and returns to the Forever preference", function()
    local e = newAddon(nil, true, true, "enUS", { loaded = true, localeID = 1 })
    assertEffectiveLanguage(e, e.ns.GetLanguageDisplayName("DE"))
    local dropdown = ownLanguageDropdown(e)
    e.selectDropdown(dropdown, "FR")
    assertEffectiveLanguage(e, e.ns.GetLanguageDisplayName("FR"))
    e.selectDropdown(dropdown, nil)
    assertEffectiveLanguage(e, e.ns.GetLanguageDisplayName("DE"))
end)

test("effective language updates when the Forever preference arrives or changes", function()
    local preference = { loaded = false, localeID = 1 }
    local e = newAddon(nil, true, true, "enUS", preference)
    assertEffectiveLanguage(e, e.ns.GetLanguageDisplayName("EN"))
    preference.loaded = true
    e.emit("PREFERRED_PLAY_SETTINGS_UPDATED")
    assertEffectiveLanguage(e, e.ns.GetLanguageDisplayName("DE"))
    preference.localeID = 2
    e.emit("PREFERRED_PLAY_SETTINGS_UPDATED")
    assertEffectiveLanguage(e, e.ns.GetLanguageDisplayName("FR"))
    preference.localeID = 3
    e.emit("PREFERRED_PLAY_SETTINGS_UPDATED")
    assertEffectiveLanguage(e, e.ns.GetLanguageDisplayName("EN"))
end)

test("preference updates preserve a manual own-language selection", function()
    local preference = { loaded = true, localeID = 1 }
    local e = newAddon({ myLanguage = "FR" }, true, true, "enUS", preference)
    preference.localeID = 3
    e.emit("PREFERRED_PLAY_SETTINGS_UPDATED")
    assertEffectiveLanguage(e, e.ns.GetLanguageDisplayName("FR"))
end)

test("effective language falls back to the client when preference APIs are absent", function()
    local e = newAddon(nil, true, true, "deDE")
    assertEffectiveLanguage(e, e.ns.GetLanguageDisplayName("DE"))
end)

test("effective language uses the Anniversary client language", function()
    local e = newAddon(nil, false, true, "deDE")
    assertEffectiveLanguage(e, e.ns.GetLanguageDisplayName("DE"))
end)

test("restoring defaults updates the effective language without clearing undone guesses", function()
    local e = newAddon({ myLanguage = "FR", rejectedPlayerLanguages = { ["Target Tester"] = { DE = true } } },
        true, true, "enUS", { loaded = true, localeID = 1 })
    e.StaticPopupDialogs.LANGUAGESCOUT_RESTORE_DEFAULTS.OnAccept()
    assertEffectiveLanguage(e, e.ns.GetLanguageDisplayName("DE"))
    equal(e.LanguageScoutDB.rejectedPlayerLanguages["Target Tester"].DE, true)
end)

for _, locale in ipairs({ "enUS", "deDE", "esES", "esMX", "frFR", "ruRU" }) do
    test(locale .. " translates the undone page and effective language display", function()
        local e = newAddon({ myLanguage = "FR", rejectedPlayerLanguages = { ["Target Tester"] = { DE = true } } }, true, true, locale)
        for _, key in ipairs({ "UNDONE_GUESSES", "UNDONE_GUESSES_DESCRIPTION", "NO_UNDONE_GUESSES", "ALLOW_AGAIN", "EFFECTIVE_LANGUAGE", "EFFECTIVE_LANGUAGE_UNAVAILABLE" }) do
            assert(e.ns.L(key) ~= key, "missing translation " .. key)
        end
        undonePanel(e):Show()
        equal(undoneRows(e)[1].allowButton.text, e.ns.L("ALLOW_AGAIN"))
        assertEffectiveLanguage(e, e.ns.GetLanguageDisplayName("FR"))
    end)
end

test("Languages rows scroll inside their settings page and the last row remains editable", function()
    local e = newAddon(nil, true, true, "frFR")
    local panel = e.categories[2].frame
    panel:Show()
    local rows = {}
    for _, widget in ipairs(e.widgets) do
        if widget.markCheckbox and widget.autoDetectCheckbox then rows[#rows + 1] = widget end
    end
    equal(#rows, #e.ns.SUPPORTED_LANGUAGES)
    local list = rows[1].parent
    local scroll = list.parent
    equal(scroll.kind, "ScrollFrame")
    equal(scroll.parent, panel)
    equal(scroll.scrollChild, list)
    for _, row in ipairs(rows) do equal(row.parent, list) end

    scroll:SetHeight(180)
    rows[1].scripts.OnMouseWheel(rows[1], -10)
    equal(scroll:GetVerticalScroll(), list:GetHeight() - scroll:GetHeight())
    local last = rows[#rows]
    equal(last.languageText.text, e.ns.GetLanguageDisplayName("CZSK"))
    local bottom = -last.points[1][5] + last:GetHeight()
    assert(bottom <= list:GetHeight(), "last language row exceeds scrollable content")
    assert(bottom <= scroll:GetVerticalScroll() + scroll:GetHeight(), "last row cannot be reached")
    last.markCheckbox:Click()
    last.autoDetectCheckbox:Click()
    equal(e.ns.IsLanguageMarkEnabled("CZSK"), true)
    equal(e.ns.IsLanguageAutoDetectEnabled("CZSK"), false)
    e = newAddon(e.LanguageScoutDB, true, true, "frFR")
    equal(e.ns.IsLanguageMarkEnabled("CZSK"), true)
    equal(e.ns.IsLanguageAutoDetectEnabled("CZSK"), false)
end)

test("Languages wheel scrolling works over checkboxes and clamps after resizing", function()
    local e = newAddon(nil, true, true)
    local row
    for _, widget in ipairs(e.widgets) do
        if widget.markCheckbox and widget.autoDetectCheckbox then row = widget; break end
    end
    local scroll = row.parent.parent
    scroll:SetHeight(180)
    row.markCheckbox.scripts.OnMouseWheel(row.markCheckbox, -1)
    equal(scroll:GetVerticalScroll(), 126)
    row.autoDetectCheckbox.scripts.OnMouseWheel(row.autoDetectCheckbox, 10)
    equal(scroll:GetVerticalScroll(), 0)
    row.markCheckbox.scripts.OnMouseWheel(row.markCheckbox, -10)
    assert(scroll:GetVerticalScroll() > 0)
    scroll:SetHeight(700)
    scroll.scripts.OnSizeChanged(scroll)
    equal(scroll:GetVerticalScroll(), 0)
    row.scripts.OnMouseWheel(row, -1)
    equal(scroll:GetVerticalScroll(), 0)
end)

test("fresh LanguageScout install uses its own saved variables and settings category", function()
    local e = newAddon(nil, true, true)
    equal(type(e.LanguageScoutDB.players), "table")
    equal(type(e.LanguageScoutCharacterDB), "table")
    equal(e.categories[1].title, "LanguageScout")
end)

test("new commands open the renamed settings", function()
    local e = newAddon(nil, true, true)
    equal(e.SLASH_LANGUAGESCOUT1, "/languagescout")
    equal(e.SLASH_LANGUAGESCOUT2, "/ls")
    equal(e.SLASH_LANGUAGESCOUT3, nil)
    e.SlashCmdList.LANGUAGESCOUT()
    equal(e.openCategoryId, e.categories[1]:GetID())
    equal(e.SLASH_LANGUAGESCOUTDEBUG1, "/lsdebug")
    equal(e.SLASH_LANGUAGESCOUTDEBUG2, "/languagescoutdebug")
    equal(e.SLASH_LANGUAGESCOUTDEBUG3, nil)
    e.SlashCmdList.LANGUAGESCOUTDEBUG("test")
    local passed, total = e.ns.RunAutoDetectSelfTests()
    local petPassed, petTotal = e.ns.RunPetNameSelfTests()
    local expected = string.format("LanguageScout self-test: %d/%d passed.", passed + petPassed, total + petTotal)
    assert(e.messages[#e.messages]:find(expected, 1, true))
end)

test("chat flags use compact rectangular dimensions without changing message data", function()
    local e = newAddon()
    e.ns.SetPlayerLanguage("Target Tester", "DE", false, "manual")
    for _, event in ipairs({
        "CHAT_MSG_CHANNEL", "CHAT_MSG_GUILD", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
        "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_INSTANCE_CHAT",
        "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_SAY", "CHAT_MSG_YELL",
    }) do
        local blocked, msg, author, extra = e.filters[event][1](nil, event, "hello", "Target Tester", "preserved")
        equal(blocked, false)
        equal(msg, "|TInterface\\AddOns\\LanguageScout\\flags\\DE.tga:12:18:0:0|t hello")
        equal(author, "Target Tester")
        equal(extra, "preserved")
    end
end)

test("renamed addon still sends and receives the legacy communication protocol", function()
    local e = newAddon()
    e.IsInGuild = function() return true end
    e.ns.SyncNewPlayerLanguage("Target Tester", "DE")
    equal(e.sent[1].prefix, "LMARK")
    equal(e.sent[1].msg, "ENTRY:Target Tester:DE")
    e.emit("CHAT_MSG_ADDON", "LMARK", "ENTRY:Other Tester:FR", "GUILD", "Peer Tester")
    equal(e.LanguageScoutDB.players["Other Tester"].lang, "FR")
end)

test("undo links use the new name and remain clickable", function()
    local e = newAddon()
    e.detect("Bonjour")
    assert(e.messages[#e.messages]:find("|Hlanguagescoutundo:Target Tester:FR|h", 1, true))
    e.hooks.SetItemRef("languagescoutundo:Target Tester:FR")
    equal(e.LanguageScoutDB.players["Target Tester"], nil)
    equal(e.LanguageScoutDB.rejectedPlayerLanguages["Target Tester"].FR, true)
end)

for _, locale in ipairs({ "enUS", "deDE", "esES", "esMX", "frFR", "ruRU" }) do
    test(locale .. " messages and debug instructions use LanguageScout branding", function()
        local e = newAddon(nil, true, true, locale)
        for _, key in ipairs({ "AUTO_MARKED_MESSAGE", "VERSION_OUTDATED_MESSAGE", "WIPE_ALL_DATA_CONFIRM", "DEBUG_STATUS_MESSAGE" }) do
            assert(e.ns.L(key):find("LanguageScout", 1, true), key)
            assert(not e.ns.L(key):find("LanguageMarker", 1, true), key)
        end
        assert(e.ns.L("DEBUG_STATUS_MESSAGE"):find("/lsdebug", 1, true))
    end)
end

for _, sample in ipairs({
    { "DE", "Kann mir jemand helfen bei der Quest?" },
    { "FR", "Tu peux m’inviter ?" },
    { "ES", "Voy de camino!" },
    { "RU", "НУЖЕН ТАНК" },
    { "UA", "ДУЖЕ ДЯКУЮ" },
    { "IT", "Ci manca un tank" },
    { "PT", "Muito obrigado" },
}) do
    test(sample[1] .. " conversation phrases respect language settings and undo", function()
        local e = newAddon()
        e.ns.SetLanguageAutoDetectEnabled(sample[1], false)
        e.detect(sample[2])
        equal(e.LanguageScoutDB.players["Target Tester"], nil)
        e.ns.SetLanguageAutoDetectEnabled(sample[1], true)
        e.detect(sample[2])
        equal(e.LanguageScoutDB.players["Target Tester"].lang, sample[1])
        e.undo("Target Tester", sample[1])
        e.detect(sample[2])
        equal(e.LanguageScoutDB.players["Target Tester"], nil)
    end)
end

test("custom phrases match complete ordered words with punctuation and spaces", function()
    local e = newAddon({ autoDetectWords = { FR = { "licorne amicale" } } })
    e.detect("licorne très amicale", "Gap Tester")
    e.detect("amicale licorne", "Order Tester")
    e.detect("licorne amicalement", "Suffix Tester")
    equal(e.LanguageScoutDB.players["Gap Tester"], nil)
    equal(e.LanguageScoutDB.players["Order Tester"], nil)
    equal(e.LanguageScoutDB.players["Suffix Tester"], nil)
    e.detect("LICORNE…\194\160AMICALE!", "Target Tester")
    equal(e.LanguageScoutDB.players["Target Tester"].lang, "FR")
end)

test("words from separate messages do not combine into a phrase", function()
    local e = newAddon()
    e.detect("merci")
    e.detect("beaucoup")
    equal(e.LanguageScoutDB.players["Target Tester"], nil)
    e.detect("merci beaucoup")
    equal(e.LanguageScoutDB.players["Target Tester"].lang, "FR")
end)

test("repeated weak words stay weak while different clues can combine", function()
    local e = newAddon()
    e.detect("pour pour pour", "Repeat Tester")
    equal(e.LanguageScoutDB.players["Repeat Tester"], nil)
    e.detect("pour son groupe", "Target Tester")
    equal(e.LanguageScoutDB.players["Target Tester"].lang, "FR")
end)

test("equally strong mixed-language phrases remain undecided", function()
    local e = newAddon()
    e.detect("ci manca un tank, sto arrivando / estou chegando")
    equal(e.LanguageScoutDB.players["Target Tester"].lang, "IT")
    e.detect("ci manca un tank / estou chegando", "Mixed Tester")
    equal(e.LanguageScoutDB.players["Mixed Tester"], nil)
end)

test("release metadata reports the TOC version", function()
    local e = newAddon()
    equal(e.ns.ADDON_VERSION, addonVersion)
end)

test("older addon version sequences cannot trigger a false update warning", function()
    local e = newAddon()
    e.receive("VER:2.1.0-RC9")
    e.receive("VER:WoWLingo:9.0.0")
    e.receive("VER:LanguageScout:1.0.0")
    e.receive("VER:LanguageScout:0.9.0")
    e.receive("VER:LanguageScout:" .. addonVersion)
    equal(#e.messages, 0)
    local nextVersion = addonVersion:gsub("(%d+)$", function(patch) return tonumber(patch) + 1 end)
    e.receive("VER:LanguageScout:" .. nextVersion)
    equal(#e.messages, 1)
    equal(e.messages[1], e.ns.L("VERSION_OUTDATED_MESSAGE"))
    e.receive("VER:LanguageScout:" .. nextVersion)
    equal(#e.messages, 1)
end)

test("version announcements identify the renamed product", function()
    local e = newAddon()
    e.IsInGuild = function() return true end
    e.emit("PLAYER_GUILD_UPDATE")
    equal(e.sent[1].msg, "VER:LanguageScout:" .. addonVersion)
    equal(e.sent[1].prefix, "LMARK")
end)

local function outgoingBox(message, chatType, maxBytes)
    local box = { text = message, chatType = chatType, maxBytes = maxBytes, edits = 0 }
    function box:GetText() return self.text end
    function box:SetText(text) self.text = text; self.edits = self.edits + 1 end
    function box:GetChatType() return self.chatType end
    function box:GetAttribute(key) if key == "chatType" then return self.chatType end end
    function box:GetMaxBytes() return self.maxBytes end
    return box
end

local function outgoing(e, message, chatType, mode, maxBytes)
    local box = outgoingBox(message, chatType, maxBytes)
    if mode == "legacy" then
        box.GetChatType = nil
        assert(e.hooks.ChatEdit_ParseText)(box, 1)
    else
        local registered = assert(e.registryCallbacks["ChatFrame.OnEditBoxPreSendText"])
        registered.callback(registered.owner, box)
    end
    return box.text, box
end

for _, mode in ipairs({ "legacy", "modern" }) do
    for _, channel in ipairs({
        { "channel", "CHANNEL" }, { "guild", "GUILD" }, { "party", "PARTY" },
        { "raid", "RAID" }, { "instance", "INSTANCE_CHAT" }, { "say", "SAY" }, { "yell", "YELL" },
    }) do
        test(mode .. " outgoing " .. channel[1] .. " tags are enabled by default and individually optional", function()
            local e = newAddon({ myLanguage = "FR" }, nil, nil, nil, nil, mode)
            equal(outgoing(e, "Bonjour à tous !", channel[2], mode), "[FR] Bonjour à tous !")
            equal(e.ns.SetOutgoingPrefixChannelEnabled(channel[1], false), true)
            equal(outgoing(e, "Bonjour à tous !", channel[2], mode), "Bonjour à tous !")
            e.ns.SetOutgoingPrefixChannelEnabled(channel[1], true)
            equal(outgoing(e, "Bonjour à tous !", channel[2], mode), "[FR] Bonjour à tous !")
        end)
    end
end

test("outgoing opt-out and individual channel choices survive reload and default migration", function()
    local e = newAddon({ myLanguage = "FR", prefixOutgoingMessages = false,
        outgoingPrefixChannels = { guild = false, unknown = true } })
    equal(outgoing(e, "hello", "SAY"), "hello")
    equal(e.LanguageScoutDB.outgoingPrefixChannels.guild, false)
    equal(e.LanguageScoutDB.outgoingPrefixChannels.say, true)
    equal(e.LanguageScoutDB.outgoingPrefixChannels.unknown, nil)
    equal(e.ns.SetOutgoingPrefixChannelEnabled("unknown", true), false)
    e = newAddon(e.LanguageScoutDB)
    equal(outgoing(e, "hello", "SAY"), "hello")
    e.LanguageScoutDB.prefixOutgoingMessages = true
    equal(outgoing(e, "hello", "SAY"), "[FR] hello")
    equal(outgoing(e, "hello", "GUILD"), "hello")
    e = newAddon({ myLanguage = "FR", outgoingPrefixChannels = "invalid" })
    equal(outgoing(e, "hello", "SAY"), "[FR] hello")
end)

test("outgoing prefixes are independent of detection, display and synchronization settings", function()
    local e = newAddon({ myLanguage = "DE", autoDetect = false, displayFlagsInChat = false,
        syncGuild = false, syncParty = false, chatDetectionChannels = { guild = false } })
    equal(outgoing(e, "hello", "GUILD"), "[DE] hello")
    equal(#e.sent, 0)
    e.ns.SetOutgoingPrefixChannelEnabled("say", false)
    equal(e.ns.IsChatDetectionChannelEnabled("CHAT_MSG_SAY"), false)
    e.LanguageScoutDB.autoDetect = true
    equal(e.ns.IsChatDetectionChannelEnabled("CHAT_MSG_SAY"), true)
end)

test("outgoing tags follow manual language and current Forever preferred language", function()
    local preference = { loaded = true, localeID = 2 }
    local e = newAddon(nil, true, nil, "deDE", preference)
    equal(outgoing(e, "hello", "SAY"), "[FR] hello")
    preference.localeID = 1
    equal(outgoing(e, "hello", "SAY"), "[DE] hello")
    e.LanguageScoutDB.myLanguage = "ES"
    equal(outgoing(e, "hello", "SAY"), "[ES] hello")
    e.LanguageScoutDB.myLanguage = nil
    preference.loaded = false
    equal(outgoing(e, "hello", "SAY"), "[DE] hello")
    preference.loaded = true; preference.localeID = 3
    equal(outgoing(e, "hello", "SAY"), "[EN] hello")
end)

test("Anniversary outgoing tags follow its supported client language", function()
    local e = newAddon(nil, false, nil, "frFR")
    equal(outgoing(e, "hello", "SAY"), "[FR] hello")
    e = newAddon(nil, false, nil, "enUS")
    equal(outgoing(e, "hello", "SAY"), "[EN] hello")
end)

test("outgoing prefixes preserve explicit language tags and do not duplicate across hooks", function()
    local e = newAddon({ myLanguage = "FR" })
    for _, message in ipairs({ "[FR] hello", "[fr] hello", "  [DE] hello", "[EN] hello", "[CZSK] hello" }) do
        equal(outgoing(e, message, "PARTY"), message)
    end
    equal(outgoing(e, "[LFG] tank", "CHANNEL"), "[FR] [LFG] tank")
    local _, box = outgoing(e, "hello", "PARTY")
    e.hooks.ChatEdit_ParseText(box, 1)
    equal(box.text, "[FR] hello")
    equal(box.edits, 1)
end)

test("outgoing hooks ignore whispers, emotes, commands and non-message chat types", function()
    local e = newAddon({ myLanguage = "FR" })
    for _, chatType in ipairs({ "WHISPER", "BN_WHISPER", "OFFICER", "RAID_WARNING", "EMOTE", "AFK", "DND", "UNKNOWN" }) do
        equal(outgoing(e, "hello", chatType), "hello")
    end
    equal(outgoing(e, "hello", nil), "hello")
    for _, message in ipairs({ "", "   ", "/reload", " /cast Fireball", "/ls", "/dance" }) do
        equal(outgoing(e, message, "SAY"), message)
    end
    local box = outgoingBox("hello", "SAY")
    e.hooks.ChatEdit_ParseText(box, 0)
    equal(box.text, "hello", "typing must not insert a tag")
    e.hooks.ChatEdit_ParseText(box, 1)
    equal(box.text, "[FR] hello")
end)

test("outgoing prefixes keep complete UTF-8 text and links within the byte limit", function()
    local e = newAddon({ myLanguage = "FR" })
    local boundary = string.rep("é", 125)
    equal(outgoing(e, boundary, "SAY"), "[FR] " .. boundary)
    equal(outgoing(e, boundary .. "!", "SAY"), boundary .. "!")
    equal(outgoing(e, "hello", "SAY", nil, 9), "hello")
    equal(outgoing(e, "hello", "SAY", nil, 10), "[FR] hello")
    equal(outgoing(e, "hello", "SAY", nil, 0), "[FR] hello")
    local link = "|cffa335ee|Hitem:123:0:0:0|h[Test item]|h|r"
    equal(outgoing(e, link, "PARTY"), "[FR] " .. link)
    e.LanguageScoutDB.myLanguage = "CZSK"
    equal(outgoing(e, "hello", "SAY"), "[CZSK] hello")
end)

test("outgoing hooks do not inspect secret text or chat types", function()
    local e = newAddon({ myLanguage = "FR" })
    local secret = {}
    e.issecretvalue = function(value) return value == secret end
    equal(outgoing(e, secret, "SAY"), secret)
    equal(outgoing(e, "hello", secret), "hello")
    local registered = e.registryCallbacks["ChatFrame.OnEditBoxPreSendText"]
    registered.callback(registered.owner, secret)
end)

test("outgoing hooks register once and support a late-loading legacy chat parser", function()
    local e = newAddon({ myLanguage = "FR" })
    local legacy = e.hooks.ChatEdit_ParseText
    local modern = e.registryCallbacks["ChatFrame.OnEditBoxPreSendText"]
    e.emit("PLAYER_LOGIN"); e.emit("ADDON_LOADED", "OtherAddon")
    equal(e.hooks.ChatEdit_ParseText, legacy)
    equal(e.registryCallbacks["ChatFrame.OnEditBoxPreSendText"], modern)
    e = newAddon({ myLanguage = "FR" }, nil, nil, nil, nil, "late")
    equal(e.hooks.ChatEdit_ParseText, nil)
    e.ChatEdit_ParseText = function() end
    e.emit("ADDON_LOADED", "Blizzard_ChatFrameBase")
    equal(outgoing(e, "hello", "SAY", "legacy"), "[FR] hello")
end)

local function outgoingPanel(e)
    for _, category in ipairs(e.categories) do
        if category.title == e.ns.L("OUTGOING_MESSAGES") then return category.frame end
    end
    error("missing outgoing settings page")
end

test("outgoing settings opt-out disables channel controls while retaining choices", function()
    local e = newAddon({ myLanguage = "FR" }, true, true)
    local panel = outgoingPanel(e)
    panel:Show()
    local master = e.findCheckbox("PREFIX_OUTGOING_MESSAGES")
    local guild
    for _, widget in ipairs(e.widgets) do
        if widget.parent == panel and widget.kind == "CheckButton"
            and widget.Text.text == e.ns.L("AUTO_DETECT_CHANNEL_GUILD") then guild = widget end
    end
    equal(master:GetChecked(), true)
    guild:Click()
    equal(e.LanguageScoutDB.outgoingPrefixChannels.guild, false)
    master:Click()
    equal(outgoing(e, "hello", "SAY"), "hello")
    equal(guild.enabled, false)
    master:Click()
    equal(guild.enabled, true)
    equal(guild:GetChecked(), false)
    equal(outgoing(e, "hello", "SAY"), "[FR] hello")
    equal(outgoing(e, "hello", "GUILD"), "hello")
    e.StaticPopupDialogs.LANGUAGESCOUT_RESTORE_DEFAULTS.OnAccept()
    equal(e.LanguageScoutDB.prefixOutgoingMessages, true)
    equal(e.LanguageScoutDB.outgoingPrefixChannels.guild, true)
    equal(guild:GetChecked(), true)
end)

for _, locale in ipairs({ "enUS", "deDE", "esES", "esMX", "frFR", "ruRU" }) do
    test(locale .. " translates outgoing settings and updates the live prefix preview", function()
        local e = newAddon(nil, true, true, locale)
        local dropdown = ownLanguageDropdown(e)
        e.selectDropdown(dropdown, "FR")
        local panel = outgoingPanel(e)
        panel:Show()
        for _, key in ipairs({ "OUTGOING_MESSAGES", "OUTGOING_MESSAGES_DESCRIPTION",
            "PREFIX_OUTGOING_MESSAGES", "OUTGOING_PREFIX_CHANNELS", "OUTGOING_PREFIX_PREVIEW" }) do
            assert(e.ns.L(key) ~= key, key)
        end
        local function assertPreview(tag)
            local expected = string.format(e.ns.L("OUTGOING_PREFIX_PREVIEW"), tag)
            for _, widget in ipairs(e.widgets) do
                if widget.parent == panel and widget.text == expected then return end
            end
            error("missing outgoing preview " .. expected)
        end
        assertPreview("[FR]")
        e.selectDropdown(dropdown, "DE")
        assertPreview("[DE]")
        e.selectDropdown(dropdown, nil)
        local clientTag = ({ enUS = "[EN]", deDE = "[DE]", esES = "[ES]", esMX = "[ES]", frFR = "[FR]", ruRU = "[RU]" })[locale]
        assertPreview(clientTag or e.ns.L("EFFECTIVE_LANGUAGE_UNAVAILABLE"))
    end)
end

for _, language in ipairs({ "EN", "DE", "ES", "RU", "UA", "FR", "IT", "SV", "NO", "DA", "TR", "PL", "PT", "NL", "CZSK" }) do
    test(language .. " tags work for outgoing messages and incoming detection", function()
        local e = newAddon({ myLanguage = language })
        local message = outgoing(e, "...", "SAY")
        equal(message, "[" .. language .. "] ...")
        local blocked, returned, author = e.detect(message)
        equal(blocked, false)
        equal(returned, message)
        equal(author, "Target Tester")
        equal(e.LanguageScoutDB.players["Target Tester"].lang, language)
        equal(e.LanguageScoutDB.players["Target Tester"].source, "automatic")
        local reason = string.format(e.ns.L("AUTO_REASON_CHAT_PREFIX"), "[" .. language .. "]")
        assert(e.messages[#e.messages]:find(reason, 1, true))
        assert(e.messages[#e.messages]:find("|Hlanguagescoutundo:", 1, true))
    end)
end

for _, channel in ipairs({
    { "channel", "CHAT_MSG_CHANNEL" }, { "guild", "CHAT_MSG_GUILD" },
    { "party", "CHAT_MSG_PARTY" }, { "party", "CHAT_MSG_PARTY_LEADER" },
    { "raid", "CHAT_MSG_RAID" }, { "raid", "CHAT_MSG_RAID_LEADER" },
    { "instance", "CHAT_MSG_INSTANCE_CHAT" }, { "instance", "CHAT_MSG_INSTANCE_CHAT_LEADER" },
    { "say", "CHAT_MSG_SAY" }, { "yell", "CHAT_MSG_YELL" },
}) do
    test(channel[2] .. " leading tag detection follows its detection-channel switch", function()
        local e = newAddon()
        e.ns.SetChatDetectionChannelEnabled(channel[1], false)
        e.detect("[FR] ...", "Target Tester", channel[2])
        equal(e.LanguageScoutDB.players["Target Tester"], nil)
        e.ns.SetChatDetectionChannelEnabled(channel[1], true)
        e.detect("[FR] ...", "Target Tester", channel[2])
        equal(e.LanguageScoutDB.players["Target Tester"].lang, "FR")
    end)
end

test("tag detection respects master and language switches independently of outgoing tags", function()
    local e = newAddon({ prefixOutgoingMessages = false, outgoingPrefixChannels = { guild = false } })
    e.LanguageScoutDB.autoDetect = false
    e.detect("[FR] Bonjour", "Target Tester", "CHAT_MSG_GUILD")
    equal(e.LanguageScoutDB.players["Target Tester"], nil)
    e.LanguageScoutDB.autoDetect = true
    e.ns.SetLanguageAutoDetectEnabled("FR", false)
    e.detect("[FR] Suche Gruppe", "Target Tester", "CHAT_MSG_GUILD")
    equal(e.LanguageScoutDB.players["Target Tester"], nil, "disabled tag must not become a different body guess")
    e.ns.SetLanguageAutoDetectEnabled("FR", true)
    e.detect("[FR] Suche Gruppe", "Target Tester", "CHAT_MSG_GUILD")
    equal(e.LanguageScoutDB.players["Target Tester"].lang, "FR")
end)

test("a leading tag takes priority over other language clues and sender-name clues", function()
    local e = newAddon()
    e.detect("[FR] Привіт друзі", "Іван Тест")
    equal(e.LanguageScoutDB.players["Іван Тест"].lang, "FR")
    e.detect("[DE] Bonjour", "Other Tester")
    equal(e.LanguageScoutDB.players["Other Tester"].lang, "DE")
end)

test("tags correct inferred records but preserve manual and confirmed assignments", function()
    for _, source in ipairs({ "automatic", "guild", "sync", "legacy" }) do
        local e = newAddon({ players = { ["Target Tester"] = { lang = "DE", source = source, updatedAt = 10 } } })
        e.detect("[FR] ...")
        equal(e.LanguageScoutDB.players["Target Tester"].lang, "FR")
        equal(e.LanguageScoutDB.players["Target Tester"].source, "automatic")
        local messages = #e.messages
        e.detect("[FR] ...")
        equal(#e.messages, messages, "repeat tags must not produce repeat feedback")
    end
    local e = newAddon()
    e.ns.SetPlayerLanguage("Manual Tester", "DE", false, "manual")
    e.ns.SetSelfReportedPlayerLanguage("Confirmed Tester", "DE")
    e.detect("[FR] ...", "Manual Tester")
    e.detect("[FR] ...", "Confirmed Tester")
    equal(e.LanguageScoutDB.players["Manual Tester"].lang, "DE")
    equal(e.LanguageScoutDB.players["Confirmed Tester"].lang, "DE")
    equal(e.LanguageScoutDB.players["Confirmed Tester"].selfReported, true)
end)

test("undo rejects repeated tags until Allow again, including after reload", function()
    local e = newAddon()
    e.detect("[FR] ...")
    e.hooks.SetItemRef("languagescoutundo:Target Tester:FR")
    equal(e.LanguageScoutDB.players["Target Tester"], nil)
    e = newAddon(e.LanguageScoutDB)
    e.detect("[FR] ...")
    equal(e.LanguageScoutDB.players["Target Tester"], nil)
    e.ns.AllowPlayerLanguageAgain("Target Tester", "FR")
    e.detect("[FR] ...")
    equal(e.LanguageScoutDB.players["Target Tester"].lang, "FR")
end)

test("tags accept case, whitespace and display markup, including existing flag filters", function()
    for _, message in ipairs({ "[fr] ...", "  [FR] ...", "[FR]", "[FR]\t...",
        "|cff00ff00[FR]|r ...", "|TInterface\\AddOns\\LanguageScout\\flags\\DE.tga:12:18:0:0|t [FR] ..." }) do
        local e = newAddon()
        e.detect(message)
        equal(e.LanguageScoutDB.players["Target Tester"].lang, "FR")
    end
    local e = newAddon()
    e.ns.SetPlayerLanguage("Target Tester", "DE", false, "automatic")
    local message, author = "[FR] ...", "Target Tester"
    for _, filter in ipairs(e.filters.CHAT_MSG_PARTY) do
        local blocked
        blocked, message, author = filter(nil, "CHAT_MSG_PARTY", message, author)
        equal(blocked, false)
    end
    equal(e.LanguageScoutDB.players["Target Tester"].lang, "FR")
end)

test("non-leading, malformed, linked and unsupported tags do not identify a language", function()
    for _, message in ipairs({ "... [FR]", "[FR]...", "[ FR ] ...", "[FRA] ...", "[XX] ...",
        "[ENG] ...", "[FR ...", "|Hitem:1|h[FR]|h ..." }) do
        local e = newAddon()
        e.detect(message)
        equal(e.LanguageScoutDB.players["Target Tester"], nil, message)
    end
    local e = newAddon()
    e.detect("[LFG] merci beaucoup")
    equal(e.LanguageScoutDB.players["Target Tester"].lang, "FR", "normal text detection must remain available")
end)

test("tag detection preserves Anniversary identities and normal synchronization", function()
    local e = newAddon(nil, false)
    e.IsInGuild = function() return true end
    e.detect("[FR] ...", "Target", "CHAT_MSG_GUILD")
    equal(e.LanguageScoutDB.players["Target-TestRealm"].lang, "FR")
    equal(e.sent[1].msg, "ENTRY:Target-TestRealm:FR")
    equal(e.sent[1].distribution, "GUILD")
end)

for _, locale in ipairs({ "enUS", "deDE", "esES", "esMX", "frFR", "ruRU" }) do
    test(locale .. " translates tag-detection feedback", function()
        local e = newAddon(nil, true, nil, locale)
        assert(e.ns.L("AUTO_REASON_CHAT_PREFIX") ~= "AUTO_REASON_CHAT_PREFIX")
        e.detect("[FR] ...")
        assert(e.messages[#e.messages]:find(string.format(e.ns.L("AUTO_REASON_CHAT_PREFIX"), "[FR]"), 1, true))
    end)
end

for _, scenario in ipairs({
    { name = "missing preference API", configure = function(e) e.C_AccountServices = nil end },
    { name = "missing locale-list API", configure = function(e) e.GetAvailableLocaleInfo = nil end },
    { name = "unloaded preference", configure = function(_, preference) preference.loaded = false end },
    { name = "unsupported preferred language", configure = function(_, preference) preference.localeID = 4 end },
    { name = "unrecognized preferred locale", configure = function(_, preference) preference.localeID = 999 end },
    { name = "preference API failure", configure = function(e)
        e.C_AccountServices.GetPreferredPlaySettings = function() error("unavailable") end
    end },
    { name = "locale-list API failure", configure = function(e)
        e.GetAvailableLocaleInfo = function() error("unavailable") end
    end },
    { name = "invalid locale-list response", configure = function(e)
        e.GetAvailableLocaleInfo = function() return false end
    end },
}) do
    test("Forever client-language fallback handles " .. scenario.name, function()
        local preference = { loaded = true, localeID = 1 }
        local e = newAddon(nil, true, true, "frFR", preference)
        equal(e.ns.GetOwnEffectiveLanguage(), "DE", "supported preference wins over client language")
        scenario.configure(e, preference)
        e.emit("PREFERRED_PLAY_SETTINGS_UPDATED")
        equal(e.ns.GetOwnEffectiveLanguage(), "FR")
        assertEffectiveLanguage(e, e.ns.GetLanguageDisplayName("FR"))
        equal(outgoing(e, "bonjour", "SAY"), "[FR] bonjour")
    end)
end

test("Forever fallback follows preference updates while preserving a manual override", function()
    local preference = { loaded = false, localeID = 1 }
    local e = newAddon(nil, true, true, "frFR", preference)
    local dropdown = ownLanguageDropdown(e)
    assertEffectiveLanguage(e, e.ns.GetLanguageDisplayName("FR"))
    equal(outgoing(e, "hello", "SAY"), "[FR] hello")
    preference.loaded = true
    e.emit("PREFERRED_PLAY_SETTINGS_UPDATED")
    assertEffectiveLanguage(e, e.ns.GetLanguageDisplayName("DE"))
    equal(outgoing(e, "hello", "SAY"), "[DE] hello")
    e.selectDropdown(dropdown, "ES")
    preference.localeID = 4
    e.emit("PREFERRED_PLAY_SETTINGS_UPDATED")
    assertEffectiveLanguage(e, e.ns.GetLanguageDisplayName("ES"))
    equal(outgoing(e, "hello", "SAY"), "[ES] hello")
    e.selectDropdown(dropdown, nil)
    assertEffectiveLanguage(e, e.ns.GetLanguageDisplayName("FR"))
    equal(outgoing(e, "hello", "SAY"), "[FR] hello")
end)

test("Forever still reports unavailable when neither preference nor client is supported", function()
    local e = newAddon(nil, true, true, "zhCN", { loaded = true, localeID = 999 })
    equal(e.ns.GetOwnEffectiveLanguage(), nil)
    assertEffectiveLanguage(e, e.ns.L("EFFECTIVE_LANGUAGE_UNAVAILABLE"))
    equal(outgoing(e, "hello", "SAY"), "hello")
end)

for _, locale in ipairs({ "enUS", "enGB" }) do
    test(locale .. " selects English automatically on both clients", function()
        for _, surnames in ipairs({ true, false }) do
            local e = newAddon(nil, surnames, true, locale)
            equal(e.ns.GetOwnEffectiveLanguage(), "EN")
            assertEffectiveLanguage(e, "English")
            equal(outgoing(e, "hello", "PARTY"), "[EN] hello")
            local dropdown = ownLanguageDropdown(e)
            e.selectDropdown(dropdown, "FR")
            equal(e.ns.GetOwnEffectiveLanguage(), "FR")
            e.selectDropdown(dropdown, nil)
            equal(e.ns.GetOwnEffectiveLanguage(), "EN")
        end
    end)
end

test("English preferred language takes priority over a supported client fallback", function()
    local e = newAddon(nil, true, true, "frFR", { loaded = true, localeID = 3 })
    equal(e.ns.GetOwnEffectiveLanguage(), "EN")
    assertEffectiveLanguage(e, e.ns.GetLanguageDisplayName("EN"))
    equal(outgoing(e, "hello", "SAY"), "[EN] hello")
end)

for _, sample in ipairs({
    { "enUS", "English" }, { "deDE", "Englisch" }, { "frFR", "Anglais" },
    { "esES", "Inglés" }, { "esMX", "Inglés" }, { "ruRU", "Английский" },
}) do
    test(sample[1] .. " translates English in language selection", function()
        local e = newAddon(nil, true, true, sample[1])
        equal(e.ns.GetLanguageDisplayName("EN"), sample[2])
        equal(e.ns.IsLanguageMarkEnabled("EN"), true)
        equal(e.ns.IsLanguageAutoDetectEnabled("EN"), true)
        e.selectDropdown(ownLanguageDropdown(e), "EN")
        equal(e.LanguageScoutDB.myLanguage, "EN")
        assertEffectiveLanguage(e, sample[2])
    end)
end

test("English adds defaults without losing saved language choices or opt-outs", function()
    local db = { myLanguage = "FR", languageOptions = { FR = { mark = false, autoDetect = false } },
        players = { ["Known Tester"] = { lang = "DE", source = "manual", updatedAt = 10 } } }
    local e = newAddon(db)
    equal(e.ns.IsLanguageMarkEnabled("EN"), true)
    equal(e.ns.IsLanguageAutoDetectEnabled("EN"), true)
    equal(e.ns.IsLanguageMarkEnabled("FR"), false)
    equal(e.ns.IsLanguageAutoDetectEnabled("FR"), false)
    equal(e.ns.GetOwnEffectiveLanguage(), "FR")
    equal(e.LanguageScoutDB.players["Known Tester"].lang, "DE")
    e.ns.SetLanguageAutoDetectEnabled("EN", false)
    e.ns.SetLanguageMarkEnabled("EN", false)
    e = newAddon(e.LanguageScoutDB)
    equal(e.ns.IsLanguageMarkEnabled("EN"), false)
    equal(e.ns.IsLanguageAutoDetectEnabled("EN"), false)
end)

test("English phrases, explicit tags and custom keywords respect detection settings and undo", function()
    local e = newAddon({ autoDetectWords = { EN = { "friendly unicorn" } } })
    e.ns.SetLanguageAutoDetectEnabled("EN", false)
    for _, message in ipairs({ "[EN] ...", "Can you invite me?", "friendly unicorn" }) do
        e.detect(message)
        equal(e.LanguageScoutDB.players["Target Tester"], nil)
    end
    e.ns.SetLanguageAutoDetectEnabled("EN", true)
    e.detect("FRIENDLY---UNICORN!")
    equal(e.LanguageScoutDB.players["Target Tester"].lang, "EN")
    e.hooks.SetItemRef("languagescoutundo:Target Tester:EN")
    for _, message in ipairs({ "[en] ...", "Can you invite me?", "friendly unicorn" }) do
        e.detect(message)
        equal(e.LanguageScoutDB.players["Target Tester"], nil)
    end
    e.ns.AllowPlayerLanguageAgain("Target Tester", "EN")
    e.detect("Can you invite me?")
    equal(e.LanguageScoutDB.players["Target Tester"].lang, "EN")
end)

test("English sharing supports ENTRY, BATCH and direct declarations with record protections", function()
    local e = newAddon()
    e.IsInGuild = function() return true end
    e.ns.SetPlayerLanguage("Target Tester", "EN", true, "automatic")
    equal(e.sent[1].msg, "ENTRY:Target Tester:EN")
    e.receive("ENTRY:Other Tester:EN")
    e.receive("BATCH1:Batch Tester:EN")
    equal(e.LanguageScoutDB.players["Other Tester"].lang, "EN")
    equal(e.LanguageScoutDB.players["Batch Tester"].lang, "EN")
    e.receive("LANG:EN", "Other Tester", "WHISPER")
    equal(e.LanguageScoutDB.players["Other Tester"].selfReported, true)
    e.ns.SetPlayerLanguage("Manual Tester", "FR", false, "manual")
    e.receive("LANG:EN", "Manual Tester", "WHISPER")
    e.detect("[EN] ...", "Manual Tester")
    equal(e.LanguageScoutDB.players["Manual Tester"].lang, "FR")
    local _, message = e.filters.CHAT_MSG_PARTY[1](nil, "CHAT_MSG_PARTY", "hello", "Target Tester")
    equal(message, "|TInterface\\AddOns\\LanguageScout\\flags\\EN.tga:12:18:0:0|t hello")
end)

test("English word detection leaves shared jargon unknown and mixed-language ties undecided", function()
    for _, message in ipairs({ "hi", "hello", "thanks", "lfg tank healer dps", "gg wp brb afk lol", "invite please" }) do
        local e = newAddon()
        e.detect(message)
        equal(e.LanguageScoutDB.players["Target Tester"], nil, message)
    end
    local e = newAddon()
    e.detect("Can you invite me? Merci beaucoup!")
    equal(e.LanguageScoutDB.players["Target Tester"], nil)
end)

local function nameplateFixture(withSettings, savedDB, locale)
    local e = newAddon(savedDB, true, withSettings, locale)
    local plates, order = {}, {}
    local updater
    for _, frame in ipairs(e.frames) do
        if frame.events.NAME_PLATE_UNIT_ADDED and frame.events.NAME_PLATE_UNIT_REMOVED then updater = frame end
    end
    assert(updater, "missing nameplate event handler")
    e.plateApiCalls = 0
    e.C_NamePlate = {
        GetNamePlateForUnit = function(unit, includeForbidden)
            equal(includeForbidden, false, "forbidden nameplates must never be requested")
            e.plateApiCalls = e.plateApiCalls + 1
            return plates[unit]
        end,
        GetNamePlates = function()
            local visible = {}
            for _, unit in ipairs(order) do if plates[unit] then visible[#visible + 1] = plates[unit] end end
            return visible
        end,
    }
    e.UnitIsPlayer = function(unit) return e.units[unit] ~= nil and e.units[unit].player ~= false end
    e.UnitGUID = function(unit) return e.units[unit] and "Player-" .. unit end
    function e.addPlate(unit, playerName, isPlayer)
        e.units[unit] = { name = playerName, realm = "TestRealm", player = isPlayer }
        local name = { width = 140, textWidth = 100, justify = "CENTER", shown = true }
        function name:IsForbidden() return self.forbidden end
        function name:IsShown() return self.shown end
        function name:GetWidth() return self.width end
        function name:GetStringWidth() return self.textWidth end
        function name:GetJustifyH() return self.justify end
        local unitFrame = { unit = unit, name = name, textures = {} }
        function unitFrame:IsForbidden() return self.forbidden end
        function unitFrame:CreateTexture()
            assert(not self.forbidden, "cannot create textures on a forbidden frame")
            local texture = { parent = self, shown = false, writes = 0 }
            function texture:IsForbidden() return self.parent.forbidden end
            local function write(self)
                assert(not self:IsForbidden(), "cannot modify a forbidden texture")
                self.writes = self.writes + 1
            end
            function texture:Hide() write(self); self.shown = false end
            function texture:Show() write(self); self.shown = true end
            function texture:ClearAllPoints() write(self); self.point = nil end
            function texture:SetPoint(...) write(self); self.point = { ... } end
            function texture:SetSize(w, h) write(self); self.width, self.height = w, h end
            function texture:SetTexture(path) write(self); self.texture = path end
            self.textures[#self.textures + 1] = texture
            return texture
        end
        local plate = { UnitFrame = unitFrame, namePlateUnitToken = unit }
        function plate:IsForbidden() return self.forbidden end
        function plate:GetUnit() return self.namePlateUnitToken end
        plates[unit] = plate
        order[#order + 1] = unit
        return plate, unitFrame, name
    end
    function e.plateTick()
        if updater.scripts.OnUpdate then updater.scripts.OnUpdate(updater, 0.2) end
    end
    e.nameplateUpdater, e.nameplates = updater, plates
    return e
end

test("nameplate flags start off and do not query plates or create textures", function()
    local e = nameplateFixture()
    local _, unitFrame = e.addPlate("nameplate1", "Target Tester")
    e.ns.SetPlayerLanguage("Target Tester", "FR", false, "manual")
    e.emit("NAME_PLATE_UNIT_ADDED", "nameplate1")
    e.emit("PLAYER_LOGIN")
    equal(e.LanguageScoutDB.nameplateFlagPosition, "off")
    equal(e.plateApiCalls, 0)
    equal(#unitFrame.textures, 0)
    equal(e.nameplateUpdater.scripts.OnUpdate, nil)
end)

test("nameplate position follows visible name text for left, center and right alignment", function()
    local e = nameplateFixture()
    local _, unitFrame, name = e.addPlate("nameplate1", "Target Tester")
    e.ns.SetPlayerLanguage("Target Tester", "FR", false, "manual")
    for _, sample in ipairs({
        { "LEFT", "left", "RIGHT", "LEFT", -4 }, { "LEFT", "right", "LEFT", "RIGHT", -36 },
        { "CENTER", "left", "RIGHT", "LEFT", 16 }, { "CENTER", "right", "LEFT", "RIGHT", -16 },
        { "RIGHT", "left", "RIGHT", "LEFT", 36 }, { "RIGHT", "right", "LEFT", "RIGHT", 4 },
    }) do
        name.justify = sample[1]
        equal(e.ns.SetNameplateFlagPosition(sample[2]), true)
        local flag = unitFrame.textures[1]
        equal(flag.shown, true)
        equal(flag.texture, "Interface\\AddOns\\LanguageScout\\flags\\FR.tga")
        equal(flag.width, 18); equal(flag.height, 12)
        equal(flag.point[1], sample[3]); equal(flag.point[2], name)
        equal(flag.point[3], sample[4]); equal(flag.point[4], sample[5]); equal(flag.point[5], 0)
    end
    equal(#unitFrame.textures, 1, "position changes must reuse the texture")
    name.textWidth = 200
    e.ns.SetNameplateFlagPosition("right")
    equal(unitFrame.textures[1].point[4], 4, "clipped text uses the font-string boundary")
    e.ns.SetNameplateFlagPosition("off")
    equal(unitFrame.textures[1].shown, false)
    equal(e.nameplateUpdater.scripts.OnUpdate, nil)
end)

test("nameplate flags skip unknown players, pets, NPCs and conflicting surnames", function()
    local e = nameplateFixture()
    local _, unknown = e.addPlate("nameplate1", "Unknown Tester")
    local _, pet = e.addPlate("nameplate2", "Pet Tester", false)
    local _, npc = e.addPlate("nameplate3", "Npc Tester", false)
    local _, surname = e.addPlate("nameplate4", "Target Other")
    for _, key in ipairs({ "Target Tester", "Pet Tester", "Npc Tester" }) do
        e.ns.SetPlayerLanguage(key, "FR", false, "manual")
    end
    e.ns.SetNameplateFlagPosition("left")
    for _, unitFrame in ipairs({ unknown, pet, npc, surname }) do equal(#unitFrame.textures, 0) end
end)

test("nameplate flags refresh when languages are detected, changed, removed or names change", function()
    local e = nameplateFixture()
    local _, unitFrame, name = e.addPlate("nameplate1", "Target Tester")
    e.ns.SetNameplateFlagPosition("left")
    equal(#unitFrame.textures, 0)
    e.detect("[FR] ...", "Target Tester")
    e.plateTick()
    local flag = unitFrame.textures[1]
    equal(flag.shown, true)
    equal(flag.texture, "Interface\\AddOns\\LanguageScout\\flags\\FR.tga")
    e.ns.SetPlayerLanguage("Target Tester", "EN", false, "manual")
    e.plateTick()
    equal(flag.texture, "Interface\\AddOns\\LanguageScout\\flags\\EN.tga")
    name.shown = false; e.plateTick(); equal(flag.shown, false)
    name.shown = true; e.plateTick(); equal(flag.shown, true)
    e.ns.RemovePlayerLanguage("Target Tester"); e.plateTick(); equal(flag.shown, false)
    e.ns.SetPlayerLanguage("Other Tester", "DE", false, "manual")
    e.units.nameplate1.name = "Other Tester"
    e.emit("UNIT_NAME_UPDATE", "nameplate1")
    equal(flag.texture, "Interface\\AddOns\\LanguageScout\\flags\\DE.tga")
    equal(flag.shown, true)
end)

test("nameplate removal and pooled unit frames do not leak another player's flag", function()
    local e = nameplateFixture()
    local plate, unitFrame = e.addPlate("nameplate1", "Target Tester")
    e.ns.SetPlayerLanguage("Target Tester", "FR", false, "manual")
    e.ns.SetPlayerLanguage("Other Tester", "DE", false, "manual")
    e.ns.SetNameplateFlagPosition("right")
    local flag = unitFrame.textures[1]
    e.emit("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    equal(flag.shown, false)
    e.units.nameplate1.name = "Unknown Tester"
    e.emit("NAME_PLATE_UNIT_ADDED", "nameplate1")
    equal(flag.shown, false)
    e.units.nameplate1.name = "Target Tester"
    e.emit("NAME_PLATE_UNIT_ADDED", "nameplate1")
    equal(flag.shown, true)
    e.nameplates.nameplate1 = nil
    e.nameplates.nameplate2 = plate
    e.units.nameplate2 = { name = "Other Tester", realm = "TestRealm" }
    plate.namePlateUnitToken, unitFrame.unit = "nameplate2", "nameplate2"
    e.emit("NAME_PLATE_UNIT_ADDED", "nameplate2")
    e.emit("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    equal(flag.shown, true, "a stale removal must not hide the new owner's flag")
    equal(flag.texture, "Interface\\AddOns\\LanguageScout\\flags\\DE.tga")
    equal(#unitFrame.textures, 1)
end)

test("restricted nameplate frames and names are skipped without creating textures", function()
    for _, target in ipairs({ "plate", "frame", "name" }) do
        local e = nameplateFixture()
        local plate, unitFrame, name = e.addPlate("nameplate1", "Target Tester")
        e.ns.SetPlayerLanguage("Target Tester", "FR", false, "manual")
        if target == "plate" then plate.forbidden = true
        elseif target == "frame" then unitFrame.forbidden = true
        else name.forbidden = true end
        e.ns.SetNameplateFlagPosition("left")
        e.emit("NAME_PLATE_UNIT_ADDED", "nameplate1")
        equal(#unitFrame.textures, 0)
    end
end)

test("nameplate flags avoid modifying regions that become forbidden", function()
    local e = nameplateFixture()
    local _, unitFrame = e.addPlate("nameplate1", "Target Tester")
    e.ns.SetPlayerLanguage("Target Tester", "FR", false, "manual")
    e.ns.SetNameplateFlagPosition("left")
    local flag = unitFrame.textures[1]
    local writes = flag.writes
    unitFrame.forbidden = true
    e.plateTick()
    e.ns.SetNameplateFlagPosition("off")
    equal(flag.writes, writes)
end)

test("nameplate flags skip secret unit tokens, names and geometry", function()
    local e = nameplateFixture()
    local secret = {}
    e.issecretvalue = function(value) return value == secret end
    local plate1 = e.addPlate("nameplate1", "Unknown Tester")
    plate1.GetUnit = function() return secret end
    local _, unitFrame, name = e.addPlate("nameplate2", "Target Tester")
    e.ns.SetPlayerLanguage("Target Tester", "FR", false, "manual")
    e.ns.SetNameplateFlagPosition("left")
    equal(unitFrame.textures[1].shown, true, "one secret plate must not prevent other flags")
    name.textWidth = secret
    e.plateTick()
    equal(unitFrame.textures[1].shown, false)
    name.textWidth = 100
    name.justify = secret
    e.plateTick()
    equal(unitFrame.textures[1].shown, false)
    name.justify = "CENTER"
    name.shown = secret
    e.plateTick()
    equal(unitFrame.textures[1].shown, false)
    name.shown = true
    e.units.nameplate2.name = secret
    e.plateTick()
    equal(unitFrame.textures[1].shown, false)
    e.emit("NAME_PLATE_UNIT_ADDED", secret)
    e.emit("NAME_PLATE_UNIT_REMOVED", secret)
end)

test("nameplate settings validate saved values and tolerate absent or late client APIs", function()
    for _, value in ipairs({ "invalid", false, {}, 42 }) do
        local e = newAddon({ nameplateFlagPosition = value })
        equal(e.LanguageScoutDB.nameplateFlagPosition, "off")
        equal(e.ns.SetNameplateFlagPosition("invalid"), false)
        equal(e.LanguageScoutDB.nameplateFlagPosition, "off")
        equal(e.ns.SetNameplateFlagPosition("left"), true)
        e = newAddon(e.LanguageScoutDB)
        equal(e.LanguageScoutDB.nameplateFlagPosition, "left")
    end
    local e = nameplateFixture(false, { nameplateFlagPosition = "right", displayFlagsInChat = false,
        displayFlagsInTooltip = false })
    local plate, unitFrame = e.addPlate("nameplate1", "Target Tester")
    plate.GetUnit = nil -- Legacy clients can expose the unit token as a field.
    e.ns.SetPlayerLanguage("Target Tester", "FR", false, "manual")
    e.emit("PLAYER_ENTERING_WORLD")
    equal(unitFrame.textures[1].shown, true)
    equal(unitFrame.textures[1].point[1], "LEFT")
end)

for _, locale in ipairs({ "enUS", "deDE", "esES", "esMX", "frFR", "ruRU" }) do
    test(locale .. " translates nameplate settings and applies Off, Left and Right immediately", function()
        local e = nameplateFixture(true, nil, locale)
        for _, key in ipairs({ "NAMEPLATES", "NAMEPLATES_DESCRIPTION", "NAMEPLATE_FLAG_POSITION",
            "NAMEPLATE_FLAG_OFF", "NAMEPLATE_FLAG_LEFT", "NAMEPLATE_FLAG_RIGHT" }) do
            assert(e.ns.L(key) ~= key, key)
        end
        local panel, dropdown
        for _, category in ipairs(e.categories) do
            if category.title == e.ns.L("NAMEPLATES") then panel = category.frame end
        end
        assert(panel, "missing nameplate settings")
        for _, widget in ipairs(e.widgets) do
            if widget.parent == panel and widget.initialize then dropdown = widget end
        end
        assert(dropdown)
        panel:Show()
        equal(dropdown.selectedValue, "off")
        local _, unitFrame = e.addPlate("nameplate1", "Target Tester")
        e.ns.SetPlayerLanguage("Target Tester", "FR", false, "manual")
        e.selectDropdown(dropdown, "left")
        equal(unitFrame.textures[1].shown, true)
        equal(dropdown.text, e.ns.L("NAMEPLATE_FLAG_LEFT"))
        e.selectDropdown(dropdown, "right")
        equal(unitFrame.textures[1].point[1], "LEFT")
        equal(dropdown.text, e.ns.L("NAMEPLATE_FLAG_RIGHT"))
        e.StaticPopupDialogs.LANGUAGESCOUT_RESTORE_DEFAULTS.OnAccept()
        equal(e.LanguageScoutDB.nameplateFlagPosition, "off")
        equal(dropdown.selectedValue, "off")
        equal(unitFrame.textures[1].shown, false)
    end)
end

local function attachPlaterPlate(plate, blizzardFrame, blizzardName, unit)
    -- Shape from the supplied Plater-v663-Forever source: Plater.lua's frame
    -- creation, UpdatePlateText, ShowHealthBar, and HideHealthBar paths.
    local platerFrame = { unit = unit, namePlateUnitToken = unit, PlaterOnScreen = true,
        textures = {}, shown = true, IsForbidden = blizzardFrame.IsForbidden,
        CreateTexture = blizzardFrame.CreateTexture }
    local healthBar = { textures = {}, shown = true, IsForbidden = blizzardFrame.IsForbidden,
        CreateTexture = blizzardFrame.CreateTexture }
    local function label(parent)
        local name = {}
        for key, value in pairs(blizzardName) do name[key] = value end
        name.parent, name.shown = parent, true
        function name:GetParent() return self.parent end
        function name:IsVisible() return self.shown and self.parent.shown end
        return name
    end
    local regular = label(healthBar)
    local special = label(platerFrame)
    special.shown = false
    platerFrame.healthBar, platerFrame.unitName = healthBar, regular
    platerFrame.ActorNameSpecial = special
    healthBar.unitName = regular
    plate.unitFrame, plate.CurrentUnitNameString = platerFrame, regular
    plate.ActorNameSpecial = special
    blizzardName.shown = false
    return platerFrame, healthBar, regular, special
end

test("Plater flags use the active health-bar name and inherit its parent", function()
    local e = nameplateFixture()
    local plate, blizzard, blizzardName = e.addPlate("nameplate1", "Target Tester")
    local plater, healthBar, name = attachPlaterPlate(plate, blizzard, blizzardName, "nameplate1")
    name.justify = "LEFT"
    e.ns.SetPlayerLanguage("Target Tester", "FR", false, "manual")
    e.ns.SetNameplateFlagPosition("left")
    local flag = healthBar.textures[1]
    equal(flag.shown, true)
    equal(flag.parent, healthBar)
    equal(flag.point[2], name)
    equal(flag.point[1], "RIGHT")
    equal(flag.point[4], -4)
    equal(#blizzard.textures, 0, "Plater must not use the hidden Blizzard name")
    equal(#plater.textures, 0)
    e.ns.SetNameplateFlagPosition("right")
    equal(flag.point[1], "LEFT")
    equal(flag.point[4], -36)
    e.ns.SetPlayerLanguage("Target Tester", "EN", false, "manual")
    e.plateTick()
    equal(flag.texture, "Interface\\AddOns\\LanguageScout\\flags\\EN.tga")
    e.ns.SetNameplateFlagPosition("off")
    equal(flag.shown, false)
end)

test("Plater name-only mode switches labels without stale health-bar flags", function()
    local e = nameplateFixture()
    local plate, blizzard, blizzardName = e.addPlate("nameplate1", "Target Tester")
    local plater, healthBar, regular, special = attachPlaterPlate(plate, blizzard, blizzardName, "nameplate1")
    e.ns.SetPlayerLanguage("Target Tester", "DE", false, "manual")
    e.ns.SetNameplateFlagPosition("left")
    local regularFlag = healthBar.textures[1]
    plate.CurrentUnitNameString, healthBar.shown, regular.shown = special, false, false
    special.shown = true
    e.plateTick()
    local specialFlag = plater.textures[1]
    equal(regularFlag.shown, false)
    equal(specialFlag.shown, true)
    equal(specialFlag.parent, plater)
    equal(specialFlag.point[2], special)
    e.ns.SetNameplateFlagPosition("right")
    equal(specialFlag.point[1], "LEFT")
    plate.CurrentUnitNameString, healthBar.shown, regular.shown = regular, true, true
    special.shown = false
    e.plateTick()
    equal(regularFlag.shown, true)
    equal(specialFlag.shown, false)
    equal(#healthBar.textures, 1)
    equal(#plater.textures, 1)
    e.ns.SetNameplateFlagPosition("off")
    equal(regularFlag.shown, false)
    equal(specialFlag.shown, false)
end)

test("Plater and Blizzard plates work together including native plate-type fallback", function()
    local e = nameplateFixture()
    local platerPlate, oldFrame, oldName = e.addPlate("nameplate1", "Target Tester")
    local plater, healthBar = attachPlaterPlate(platerPlate, oldFrame, oldName, "nameplate1")
    local _, nativeFrame = e.addPlate("nameplate2", "Other Tester")
    e.ns.SetPlayerLanguage("Target Tester", "FR", false, "manual")
    e.ns.SetPlayerLanguage("Other Tester", "EN", false, "manual")
    e.ns.SetNameplateFlagPosition("right")
    equal(healthBar.textures[1].shown, true)
    equal(nativeFrame.textures[1].shown, true)
    equal(nativeFrame.textures[1].texture, "Interface\\AddOns\\LanguageScout\\flags\\EN.tga")
    plater.PlaterOnScreen = false
    oldName.shown = true
    e.plateTick()
    equal(healthBar.textures[1].shown, false)
    equal(oldFrame.textures[1].shown, true)
    equal(nativeFrame.textures[1].shown, true)
end)

test("late Plater initialization replaces an existing Blizzard flag", function()
    local e = nameplateFixture()
    local plate, blizzard, blizzardName = e.addPlate("nameplate1", "Target Tester")
    e.ns.SetPlayerLanguage("Target Tester", "FR", false, "manual")
    e.ns.SetNameplateFlagPosition("left")
    local oldFlag = blizzard.textures[1]
    equal(oldFlag.shown, true)
    local _, healthBar = attachPlaterPlate(plate, blizzard, blizzardName, "nameplate1")
    e.emit("ADDON_LOADED", "Plater")
    equal(oldFlag.shown, false)
    equal(healthBar.textures[1].shown, true)
    equal(healthBar.textures[1].point[2], plate.CurrentUnitNameString)
end)

test("Plater name aliases and unit-token seeding tolerate incomplete setup", function()
    local e = nameplateFixture()
    local plate, blizzard, blizzardName = e.addPlate("nameplate1", "Target Tester")
    local plater, healthBar, name = attachPlaterPlate(plate, blizzard, blizzardName, "nameplate1")
    plate.GetUnit, plate.namePlateUnitToken = nil, nil
    plate.CurrentUnitNameString = nil
    plater.unit = nil
    e.ns.SetPlayerLanguage("Target Tester", "FR", false, "manual")
    e.ns.SetNameplateFlagPosition("left")
    equal(healthBar.textures[1].shown, true)
    equal(healthBar.textures[1].point[2], name)
    healthBar.unitName = nil
    e.plateTick()
    equal(healthBar.textures[1].shown, true, "unitFrame.unitName alias must remain usable")
    plater.namePlateUnitToken = "nameplate99"
    e.plateTick()
    equal(healthBar.textures[1].shown, false, "a stale unit token must not show another player's flag")
end)

test("Plater hidden current names do not fall back to another visible label", function()
    local e = nameplateFixture()
    local plate, blizzard, blizzardName = e.addPlate("nameplate1", "Target Tester")
    local _, healthBar, name, special = attachPlaterPlate(plate, blizzard, blizzardName, "nameplate1")
    e.ns.SetPlayerLanguage("Target Tester", "FR", false, "manual")
    e.ns.SetNameplateFlagPosition("left")
    local flag = healthBar.textures[1]
    name.shown, special.shown, blizzardName.shown = false, true, true
    e.plateTick()
    equal(flag.shown, false)
    equal(#blizzard.textures, 0)
    name.shown, healthBar.shown = true, false
    e.plateTick()
    equal(flag.shown, false, "a hidden health-bar parent must not leave a flag")
end)

test("Plater pooled plates clear flags when the unit becomes unknown or a pet", function()
    local e = nameplateFixture()
    e.LanguageScoutDB.autoDetectPetNames = false
    local plate, blizzard, blizzardName = e.addPlate("nameplate1", "Target Tester")
    local _, healthBar = attachPlaterPlate(plate, blizzard, blizzardName, "nameplate1")
    e.ns.SetPlayerLanguage("Target Tester", "FR", false, "manual")
    e.ns.SetNameplateFlagPosition("right")
    local flag = healthBar.textures[1]
    e.emit("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    equal(flag.shown, false)
    e.units.nameplate1.name = "Unknown Tester"
    e.emit("NAME_PLATE_UNIT_ADDED", "nameplate1")
    equal(flag.shown, false)
    e.units.nameplate1.name = "Target Tester"
    e.units.nameplate1.player = false
    e.emit("NAME_PLATE_UNIT_ADDED", "nameplate1")
    equal(flag.shown, false)
end)

test("Plater restricted frames, parents and labels remain untouched", function()
    for _, target in ipairs({ "plate", "plater", "parent", "name" }) do
        local e = nameplateFixture()
        local plate, blizzard, blizzardName = e.addPlate("nameplate1", "Target Tester")
        local plater, healthBar, name = attachPlaterPlate(plate, blizzard, blizzardName, "nameplate1")
        if target == "plate" then plate.forbidden = true
        elseif target == "plater" then plater.forbidden = true
        elseif target == "parent" then healthBar.forbidden = true
        else name.forbidden = true end
        e.ns.SetPlayerLanguage("Target Tester", "FR", false, "manual")
        e.ns.SetNameplateFlagPosition("left")
        equal(#healthBar.textures, 0)
        equal(#plater.textures, 0)
        equal(#blizzard.textures, 0)
    end
end)

test("Plater secret current labels and active-state flags are skipped", function()
    local e = nameplateFixture()
    local secret = {}
    e.issecretvalue = function(value) return value == secret end
    local plate, blizzard, blizzardName = e.addPlate("nameplate1", "Target Tester")
    local plater, healthBar = attachPlaterPlate(plate, blizzard, blizzardName, "nameplate1")
    e.ns.SetPlayerLanguage("Target Tester", "FR", false, "manual")
    e.ns.SetNameplateFlagPosition("left")
    local flag = healthBar.textures[1]
    plate.CurrentUnitNameString = secret
    e.plateTick()
    equal(flag.shown, false)
    plate.CurrentUnitNameString = healthBar.unitName
    plater.PlaterOnScreen = secret
    e.plateTick()
    equal(flag.shown, false)
    equal(#blizzard.textures, 0)
end)

local function channelMessage(e, message, author, channelName, baseName, channelNumber, event)
    event = event or "CHAT_MSG_CHANNEL"
    local filters = e.filters[event]
    return filters[#filters](nil, event, message, author or "Target Tester", "Common", channelName,
        nil, nil, 0, channelNumber or 6, baseName, nil, 123, nil)
end

for _, sample in ipairs({
    { "EN", "English" }, { "FR", "Français" }, { "DE", "Deutsch" }, { "ES", "Español" },
    { "RU", "Русский" }, { "UA", "Українська" }, { "IT", "Italiano" }, { "SV", "Svenska" },
    { "NO", "Norsk" }, { "DA", "Dansk" }, { "TR", "Türkçe" }, { "PL", "Polski" },
    { "PT", "Português" }, { "NL", "Nederlands" }, { "CZSK", "Čeština" },
}) do
    test(sample[1] .. " language-labelled channels identify only an otherwise unknown sender", function()
        local e = newAddon()
        local channel = "Commerce - " .. sample[2] .. "16"
        local blocked, returned, author = channelMessage(e, "...", "Target Tester", channel)
        equal(blocked, false); equal(returned, "..."); equal(author, "Target Tester")
        local record = e.LanguageScoutDB.players["Target Tester"]
        equal(record.lang, sample[1]); equal(record.source, "automatic"); equal(record.channelHint, channel)
        equal(e.LanguageScoutDB.players["Other Tester"], nil)
        assert(e.messages[#e.messages]:find(string.format(e.ns.L("AUTO_REASON_LANGUAGE_CHANNEL"), channel), 1, true))
        assert(e.messages[#e.messages]:find("|Hlanguagescoutundo:Target Tester:", 1, true))
    end)
end

test("channel clues recognize localized names, codes, suffix numbers and canonical base metadata", function()
    for _, name in ipairs({ "Trade - French16", "Commerce - Francais 16", "Handel - Französisch16",
        "Comercio - Francés16", "Trade - FR16", "[6. Commerce - FRANÇAIS16]", "Trade – French16" }) do
        local e = newAddon()
        channelMessage(e, "...", "Target Tester", name)
        equal(e.LanguageScoutDB.players["Target Tester"].lang, "FR", name)
    end
    local e = newAddon()
    channelMessage(e, "...", "Target Tester", "6. Trade - English16", "Commerce - Français16")
    equal(e.LanguageScoutDB.players["Target Tester"].lang, "FR")
    equal(e.LanguageScoutDB.players["Target Tester"].channelHint, "Commerce - Français16")
    e = newAddon()
    channelMessage(e, "...", "Target Tester", "6. Commerce - Français16", "Trade")
    equal(e.LanguageScoutDB.players["Target Tester"].lang, "FR", "display metadata can supply a missing base label")
end)

test("ordinary localized, city and ambiguous channel names provide no language clue", function()
    for _, name in ipairs({ "Commerce", "Commerce - Thunder Bluff", "Commerce (local) - Thunder Bluff",
        "Général - Forêt d’Elwynn", "Trade - France16", "Trade - French Guild16", "Trade-French",
        "French", "[FR]", "Trade - Unknown16", "Trade - Français16 - Stormwind", "" }) do
        local e = newAddon(nil, true, nil, "frFR")
        channelMessage(e, "...", "Target Tester", name)
        equal(e.LanguageScoutDB.players["Target Tester"], nil, name)
    end
    local e = newAddon()
    channelMessage(e, "", "Target Tester", "Commerce - Français16")
    channelMessage(e, "   ", "Target Tester", "Commerce - Français16")
    equal(e.LanguageScoutDB.players["Target Tester"], nil)
    channelMessage(e, "...", "Target Tester", "Commerce - Français16", nil, nil, "CHAT_MSG_GUILD")
    equal(e.LanguageScoutDB.players["Target Tester"], nil, "only public-channel messages use channel clues")
end)

test("channel clues respect their option, global, public-channel and per-language switches", function()
    local e = newAddon()
    local function absent()
        channelMessage(e, "...", "Target Tester", "Commerce - Français16")
        equal(e.LanguageScoutDB.players["Target Tester"], nil)
    end
    e.LanguageScoutDB.autoDetectLanguageChannels = false; absent()
    e.LanguageScoutDB.autoDetectLanguageChannels = true
    e.LanguageScoutDB.autoDetect = false; absent()
    e.LanguageScoutDB.autoDetect = true
    e.ns.SetChatDetectionChannelEnabled("channel", false); absent()
    e.ns.SetChatDetectionChannelEnabled("channel", true)
    e.ns.SetLanguageAutoDetectEnabled("FR", false); absent()
    e.ns.SetLanguageAutoDetectEnabled("FR", true)
    channelMessage(e, "...", "Target Tester", "Commerce - Français16")
    equal(e.LanguageScoutDB.players["Target Tester"].lang, "FR")
    e.LanguageScoutDB.autoDetectLanguageChannels = false
    e = newAddon(e.LanguageScoutDB)
    equal(e.LanguageScoutDB.autoDetectLanguageChannels, false)
    equal(e.LanguageScoutDB.players["Target Tester"].channelHint, "Commerce - Français16")
    channelMessage(e, "...", "Other Tester", "Trade - English16")
    equal(e.LanguageScoutDB.players["Other Tester"], nil)
    channelMessage(e, "Can you invite me?", "Other Tester", "Commerce - Français16")
    equal(e.LanguageScoutDB.players["Other Tester"].lang, "EN")
end)

test("message evidence takes priority over the channel on the first message", function()
    for _, sample in ipairs({ { "[EN] ...", "EN" }, { "Suche Gruppe", "DE" }, { "Bonjour", "FR" } }) do
        local e = newAddon()
        channelMessage(e, sample[1], "Target Tester", "Commerce - Français16")
        equal(e.LanguageScoutDB.players["Target Tester"].lang, sample[2])
        equal(e.LanguageScoutDB.players["Target Tester"].channelHint, nil)
    end
end)

test("repeated channel messages do not strengthen or overwrite channel guesses", function()
    local e = newAddon()
    channelMessage(e, "...", "Target Tester", "Commerce - Français16")
    local record = e.LanguageScoutDB.players["Target Tester"]
    local messages, updatedAt = #e.messages, record.updatedAt
    e.now = e.now + 10
    channelMessage(e, "...", "Target Tester", "Commerce - Français16")
    channelMessage(e, "...", "Target Tester", "Trade - German16")
    equal(e.LanguageScoutDB.players["Target Tester"], record)
    equal(record.updatedAt, updatedAt)
    equal(record.lang, "FR"); equal(#e.messages, messages)
    equal(e.ns.GetRecordCounts().playerLanguages, 1)
    equal(#e.sent, 0)
end)

test("later message evidence can correct or confirm a channel guess after reload", function()
    for _, sample in ipairs({ { "Can you invite me?", "EN" }, { "[EN] ...", "EN" }, { "Bonjour", "FR" }, { "[FR] ...", "FR" } }) do
        local e = newAddon()
        channelMessage(e, "...", "Target Tester", "Commerce - Français16")
        e = newAddon(e.LanguageScoutDB)
        e.IsInGuild = function() return true end
        e.detect(sample[1], "Target Tester", "CHAT_MSG_PARTY")
        local record = e.LanguageScoutDB.players["Target Tester"]
        equal(record.lang, sample[2]); equal(record.channelHint, nil)
        equal(e.sent[1].msg, "ENTRY:Target Tester:" .. sample[2])
        channelMessage(e, "...", "Target Tester", "Trade - German16")
        equal(e.LanguageScoutDB.players["Target Tester"].lang, sample[2])
    end
end)

test("channel clues do not overwrite existing assignments or direct declarations", function()
    for _, source in ipairs({ "manual", "automatic", "sync", "guild" }) do
        local e = newAddon()
        e.ns.SetPlayerLanguage("Target Tester", "DE", false, source)
        channelMessage(e, "...", "Target Tester", "Commerce - Français16")
        equal(e.LanguageScoutDB.players["Target Tester"].lang, "DE")
        equal(e.LanguageScoutDB.players["Target Tester"].source, source)
    end
    local e = newAddon()
    channelMessage(e, "...", "Target Tester", "Commerce - Français16")
    e.receive("LANG:EN", "Target Tester", "WHISPER")
    equal(e.LanguageScoutDB.players["Target Tester"].channelHint, nil)
    equal(e.LanguageScoutDB.players["Target Tester"].selfReported, true)
    channelMessage(e, "...", "Target Tester", "Commerce - Français16")
    equal(e.LanguageScoutDB.players["Target Tester"].lang, "EN")
end)

test("undo and Allow again govern channel guesses across reloads", function()
    local e = newAddon()
    channelMessage(e, "...", "Target Tester", "Commerce - Français16")
    e.hooks.SetItemRef("languagescoutundo:Target Tester:FR")
    e = newAddon(e.LanguageScoutDB)
    channelMessage(e, "...", "Target Tester", "Commerce - Français16")
    equal(e.LanguageScoutDB.players["Target Tester"], nil)
    e.ns.AllowPlayerLanguageAgain("Target Tester", "FR")
    channelMessage(e, "...", "Target Tester", "Commerce - Français16")
    equal(e.LanguageScoutDB.players["Target Tester"].lang, "FR")
end)

test("channel metadata prevents stale mappings when channel numbers or cities change", function()
    local e = newAddon()
    channelMessage(e, "...", "First Tester", "Commerce - Français16", nil, 6)
    channelMessage(e, "...", "Second Tester", "Trade - German16", nil, 6)
    channelMessage(e, "...", "Third Tester", "Commerce (local) - Thunder Bluff", nil, 6)
    equal(e.LanguageScoutDB.players["First Tester"].lang, "FR")
    equal(e.LanguageScoutDB.players["Second Tester"].lang, "DE")
    equal(e.LanguageScoutDB.players["Third Tester"], nil)
end)

test("secret and malformed channel metadata is never inspected or stored", function()
    local e = newAddon()
    local secret = {}
    e.issecretvalue = function(value) return value == secret end
    channelMessage(e, "...", "Target Tester", secret, secret)
    equal(e.LanguageScoutDB.players["Target Tester"], nil)
    for _, name in ipairs({ {}, 42, "Trade - Français16\n", "|cff00ff00Trade - Français16|r", string.rep("X", 170) .. " - French16" }) do
        channelMessage(e, "...", "Target Tester", name)
        equal(e.LanguageScoutDB.players["Target Tester"], nil)
    end
    channelMessage(e, "...", "Target Tester", secret, "Trade - French16")
    equal(e.LanguageScoutDB.players["Target Tester"].lang, "FR")
end)

test("weak channel guesses stay out of full synchronization until message evidence confirms them", function()
    local e = newAddon()
    e.IsInGuild = function() return true end
    channelMessage(e, "...", "Target Tester", "Commerce - Français16")
    equal(#e.sent, 0)
    e.ns.SetPlayerLanguage("Known Tester", "DE", false, "manual")
    e.receive("SYNCREQ2", "Peer Tester", "GUILD")
    e.advance(10)
    local sawKnown = false
    for _, packet in ipairs(e.sent) do
        assert(not packet.msg:find("Target Tester", 1, true), packet.msg)
        if packet.msg:find("Known Tester", 1, true) then sawKnown = true end
    end
    assert(sawKnown, "normal records must still be synchronized")
end)

test("database migration preserves only valid automatic channel provenance", function()
    for _, hint in ipairs({ "", {}, 42, "bad\nchannel", "|cffffffffchannel", string.rep("x", 161) }) do
        local e = newAddon({ players = { ["Target Tester"] = { lang = "FR", source = "automatic", updatedAt = 10, channelHint = hint } } })
        equal(e.LanguageScoutDB.players["Target Tester"].channelHint, nil)
    end
    for _, source in ipairs({ "manual", "guild", "sync" }) do
        local e = newAddon({ players = { ["Target Tester"] = { lang = "FR", source = source, updatedAt = 10, channelHint = "Trade - French16" } } })
        equal(e.LanguageScoutDB.players["Target Tester"].channelHint, nil)
    end
end)

for _, locale in ipairs({ "enUS", "deDE", "esES", "esMX", "frFR", "ruRU" }) do
    test(locale .. " translates channel guesses, tooltips, and the opt-out setting", function()
        local e = newAddon(nil, true, true, locale)
        for _, key in ipairs({ "AUTO_DETECT_LANGUAGE_CHANNELS", "AUTO_REASON_LANGUAGE_CHANNEL", "PLAYER_SOURCE_CHANNEL", "CHANNEL_EVIDENCE" }) do
            assert(e.ns.L(key) ~= key, key)
        end
        local checkbox = e.findCheckbox("AUTO_DETECT_LANGUAGE_CHANNELS")
        equal(checkbox:GetChecked(), true)
        checkbox:Click()
        equal(e.LanguageScoutDB.autoDetectLanguageChannels, false)
        checkbox:Click()
        channelMessage(e, "...", "Target Tester", "Commerce - Français16")
        e.categories[1].frame:Show()
        local row = e.playerRows()[1]
        equal(row.sourceText.text, e.ns.L("PLAYER_SOURCE_CHANNEL"))
        row.scripts.OnEnter(row)
        equal(e.GameTooltip.doubleLines[4][1], e.ns.L("CHANNEL_EVIDENCE"))
        equal(e.GameTooltip.doubleLines[4][2], "Commerce - Français16")
        e.findCheckbox("AUTO_DETECT_CHAT"):Click()
        equal(checkbox.enabled, false)
        e.StaticPopupDialogs.LANGUAGESCOUT_RESTORE_DEFAULTS.OnAccept()
        equal(checkbox.enabled, true)
        equal(checkbox:GetChecked(), true)
    end)
end

print("Total: " .. passed .. " passed, " .. failed .. " failed")
assert(failed == 0, "LanguageScout test failures")
