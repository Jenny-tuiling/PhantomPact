-- In-game connection status: the relay's status line turned into short tips at the bottom of the screen, in the
-- game's own ink-bar tip widget (WB_TipsText, the one behind "This door doesn't open from this side").
-- (From appdoze's PR #2; the tip is re-created after map travel, which removes it from the screen.)
--
-- Shown when something changes: partner connected / lost, settings that differ between the two PCs (the relays'
-- hello exchange), packets refused because the Secrets differ, a lasting high ping, Steam staying on its relays, and an
-- untested game build. Also keeps net.rttMs for the ghost's prediction (coop.lua).

return function(api)
    local log, valid, game = api.log, api.valid, api.game

    local POLL_S = 1.0              -- status reads
    local SHOW_S = 4.0              -- how long a tip stays
    local HIGH_PING_MS = 250        -- warn when the round trip stays above this...
    local HIGH_PING_FOR = 5         -- ...for this many reads in a row
    local RELAYED_FOR = 30          -- reads in a row before saying Steam relays: it can start there, then go direct
    local REPEAT_S = 60             -- the same warning at most once a minute
    local GUEST_ALONE_S = 20        -- a guest that has heard nothing for this long is told what to check
    local HOST_ALONE_S = 90         -- a host, the same, once: it may just be waiting for a friend
    local TIP_CLASS = "/Game/PBZContent/UI/InGame/SwitchUI/WB_TipsText.WB_TipsText_C"
    local TIP_FIT = 150             -- letters a tip line holds before it breaks (lang.fit): the screen holds ~190

    local status = { on = true, last = {}, lastShown = {}, highPingReads = 0, relayedReads = 0, relayShown = false,
        buildShown = false }
    local nextPoll = 0
    local tip
    local tipOverTwo = false            -- whether tip was made for local co-op's two monitors (on player 1's screen)

    -- A new ink-bar text widget at viewport layer z, or nil. Made from the widget's class: copying an instance on
    -- screen (as first written) found none until the game had shown a tip itself, so nothing ever appeared.
    function status.newTipWidget(z, fullViewport)
        local cls = FindObject("WidgetBlueprintGeneratedClass", "WB_TipsText_C")
        if not valid(cls) then
            cls = StaticFindObject(TIP_CLASS)
        end
        if not valid(cls) and type(LoadAsset) == "function" then
            pcall(LoadAsset, TIP_CLASS)
            cls = StaticFindObject(TIP_CLASS)
        end
        local pc = api.getPlayer1()
        if not (valid(cls) and valid(pc)) then
            return nil
        end
        local w = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary"):Create(pc, cls, pc)
        if not valid(w) then
            return nil
        end
        -- (Local co-op over two monitors: on player 1's, where the game's own menus are. Over the whole window the edge
        -- between the monitors would cut it in half.)
        if not fullViewport and status.overTwoMonitors() then
            w:AddToPlayerScreen(z)
        else
            w:AddToViewport(z)
        end
        w:SetVisibility(3)                          -- HitTestInvisible: seen, never clicked
        return w
    end

    function status.overTwoMonitors()
        local lc = api.localcoop
        return lc ~= nil and lc.spread ~= nil and lc.spread() == true
    end

    function status.onScreen(w)
        return valid(w) and select(2, pcall(function() return w:IsInViewport() end)) == true
    end

    local tipSerial = 0

    local function show(text)
        log("Status: " .. text)
        if not status.on then
            return
        end
        pcall(function()
            local twoMonitors = status.overTwoMonitors()
            if not status.onScreen(tip) or tipOverTwo ~= twoMonitors then
                if valid(tip) then
                    pcall(function() tip:RemoveFromParent() end)
                end
                tip = status.newTipWidget(400)
                tipOverTwo = twoMonitors
                if not tip then
                    return
                end
            end
            tip:SetVisibility(3)                    -- HitTestInvisible: seen, never clicked
            if api.lang.arabic() then
                -- (The game's text keeps the English, hidden, for the bar's size; the Arabic, its head too so it reads right
                -- to left from its start, goes beside it in the one font with Arabic: pbz.lua's game.arabicTip.)
                tip:SetText(FText(api.lang.fit("Phantom Pact: " .. text, TIP_FIT)))
                game.arabicTip(tip, api.lang.say("Phantom Pact: ") .. api.lang.say(text))
            else
                if game.arabicTipUsed then
                    game.arabicTip(tip, nil)
                end
                tip:SetText(FText(api.lang.fit("Phantom Pact: " .. api.lang.say(text), TIP_FIT)))
            end
            pcall(function() tip:PlayAnimation(tip.FadeIn, 0, 1, 0, 1, false) end)
            local shown = tip
            tipSerial = tipSerial + 1
            local serial = tipSerial
            if game.after then
                game.after(SHOW_S, function()
                    if valid(shown) and shown == tip and serial == tipSerial then   -- (a later tip has this widget for its own time)
                        pcall(function() shown:SetVisibility(1) end)   -- collapsed
                    end
                end)
            end
        end)
    end

    -- A message at most once per REPEAT_S per key, unless it changed.
    local function notify(key, text)
        local now = os.clock()
        local prev = status.lastShown[key]
        if prev and prev.text == text and now - prev.at < REPEAT_S then
            return
        end
        status.lastShown[key] = { text = text, at = now }
        show(text)
    end

    status.notify=notify
    return status
end
