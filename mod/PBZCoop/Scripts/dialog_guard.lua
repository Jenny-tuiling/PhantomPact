-- PBZ sometimes removes a completed dialogue without deactivating it.
-- Observe attachment first; never end an on-screen or newly constructed dialogue.
return function(api)
    if _G.PBZ_DIALOG_GUARD_STARTED then return end
    _G.PBZ_DIALOG_GUARD_STARTED=true
    local tracked={}
    LoopInGameThreadWithDelay(250,function()
        local ok,err=pcall(function()
            local present={}
            for _,w in ipairs(FindAllOf('WBP_FlowDialog_C') or {}) do
                if api.valid(w) then
                    local id=w:GetFullName();present[id]=true
                    local attached=w:IsInViewport() or api.valid(w:GetParent())
                    if attached then
                        tracked[id]={seen=true}
                    elseif not w:IsActivated() then
                        tracked[id]=nil
                    elseif tracked[id] and tracked[id].seen then
                        local record=tracked[id]
                        record.detachedAt=record.detachedAt or os.clock()
                        if os.clock()-record.detachedAt>=3 then
                            w:DeactivateWidget();tracked[id]=nil
                            api.log('Dialog guard: released completed, detached dialogue')
                        end
                    end
                end
            end
            for id in pairs(tracked) do if not present[id] then tracked[id]=nil end end
        end)
        if not ok then api.log('Dialog guard error: '..tostring(err)) end
        return false
    end)
end
