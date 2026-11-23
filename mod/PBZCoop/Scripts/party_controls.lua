-- Commands are generated from raw input before guest input is blocked.
-- All manual and AI requests share one bounded, game-thread regroup queue.
return function(api,party)
    local M={}
    local lastSession,lastCount,lastLock,seen,seenRecall=nil,nil,false,{0,0,0},0
    local pending,tips,tipText={}, {}, {}
    local textUntil,shownText=nil,''
    local nextSeat,nextAttempt=2,0
    local function now()
        local ok,t=pcall(function()local pc=api.getPlayer1();return api.gs():GetTimeSeconds(pc)end)
        return ok and type(t)=='number'and t==t and t or os.clock()
    end
    local function notify(text)
        api.log('Party controls: '..text)
        if api.status then pcall(api.status.notify,'party-controls',text)end
        shownText=text;textUntil=now()+5
    end
    local function identity()
        local pc,pawn=api.getPlayer1()
        if not(api.valid(pc)and api.valid(pawn))then return nil end
        return pawn:GetOuter():GetFullName()..':'..tostring(pawn:GetAddress()),pc,pawn
    end
    local function clear()
        pending={};nextSeat=2;nextAttempt=0
    end
    local function manual(reason)return reason~='ai_distance'end
    function M.requestRegroup(seat,reason)
        if type(seat)~='number'or seat%1~=0 or seat<2 or seat>(party.count or 1)then return false,'not_joined'end
        if reason~='manual'and reason~='host_recall'and reason~='ai_distance'then return false,'invalid_reason'end
        if party.loading or not party.ready()then return false,'loading'end
        local key,_,pawn=identity()
        if not key or api.game.isDead(pawn)then return false,'host_unavailable'end
        local time=now()
        local prior=pending[seat]
        if prior and(prior.identity~=key or time>prior.expires)then pending[seat]=nil;prior=nil end
        if prior then
            -- AI polling must never extend the lifetime of a stale request.
            if manual(reason)then prior.reason=reason;prior.expires=time+10 end
            return true,'already_queued'
        end
        pending[seat]={reason=reason,identity=key,expires=time+10}
        return true,'queued'
    end
    party.requestRegroup=M.requestRegroup
    party.controls=M
    local function render(lock,pc)
        if not api.status or not api.status.newTipWidget then return end
        local show=lock or(textUntil and now()<textUntil)
        local lib=StaticFindObject('/Script/UMG.Default__WidgetLayoutLibrary')
        local size,scale=lib:GetViewportSize(pc),lib:GetViewportScale(pc)
        local text=lock and '队友操作已锁定 · 1号L3＋RT按住3秒解锁 / 队友双摇杆3秒归队' or shownText
        for seat=1,(party.count or 4)do
            if show and not api.valid(tips[seat])then tips[seat]=api.status.newTipWidget(450,true);tipText[seat]=nil end
            if api.valid(tips[seat])then
                if tipText[seat]~=text then
                    tips[seat]:SetText(FText(text));tipText[seat]=text
                    -- Same one-shot FadeIn as the original status.show helper.
                    -- WB_TipsText starts with ItemText opacity zero.
                    pcall(function()tips[seat]:PlayAnimation(tips[seat].FadeIn,0,1,0,1,false)end)
                end
                tips[seat]:SetDesiredSizeInViewport({X=size.X/scale/(party.count or 4)-40,Y=80})
                tips[seat]:SetPositionInViewport({X=size.X/scale*(seat-1)/(party.count or 4)+20,Y=30},false)
                tips[seat]:SetVisibility(show and 3 or 1)
            end
        end
    end
    local function pollInput()
        local f=io.open(api.modDir()..'four_actions.txt','r');if not f then return end
        local data=f:read(513);f:close();if not data or #data>512 then return end
        local session,locked,a,b,c,hook,count,recall=data:match('^(%d+) ([01]) (%d+) (%d+) (%d+) ([01]) ([234]) (%d+)\r?\n?$')
        if not session then
            session,locked,a,b,c,hook,count=data:match('^(%d+) ([01]) (%d+) (%d+) (%d+) ([01]) ([234])\r?\n?$')
            recall='0' -- Previous seven-field producer has no host recall action.
        end
        if not session or hook~='1'or tonumber(count)~=(party.count or 1)then return end
        local counters={tonumber(a),tonumber(b),tonumber(c)};recall=tonumber(recall)
        for _,n in ipairs({counters[1],counters[2],counters[3],recall})do if n>4294967295 then return end end
        if lastSession~=session or lastCount~=count then
            lastSession,lastCount=session,count;seen=counters;seenRecall=recall;clear()
        end
        local lock=locked=='1';party.inputLocked=lock
        if lock~=lastLock then
            lastLock=lock
            notify(lock and '队友操作已锁定；双摇杆按住3秒仍可归队。1号L3＋RT按住3秒解锁。'or'队友操作已恢复。')
            if lock then
                for seat=2,(party.count or 4)do
                    local state=party.states[seat];local pawn=state and state.p2Pawn
                    if api.valid(pawn)then pcall(function()pawn.CharacterMovement:StopMovementImmediately()end)end
                end
            end
        end
        for i=1,((party.count or 4)-1)do
            if counters[i]>seen[i]then
                local accepted=M.requestRegroup(i+1,'manual')
                notify(accepted and('玩家'..(i+1)..'请求归队；等待安全落点。')or('玩家'..(i+1)..'暂时不能归队，请恢复正常操作后重试。'))
            end
            seen[i]=counters[i] -- Reset/wrap establishes a baseline; never an action.
        end
        if recall>seenRecall then
            local accepted=0
            for seat=2,(party.count or 4)do if M.requestRegroup(seat,'host_recall')then accepted=accepted+1 end end
            notify(accepted>0 and '1号请求召回全队；将逐个检查并归队。'or'当前不能召回队友，请结束加载、死亡或交互后重试。')
        end
        seenRecall=recall
    end
    local function processQueue()
        local time=now();local key,pc,pawn=identity()
        if party.loading or not key or api.game.isDead(pawn)then clear();return end
        for seat,request in pairs(pending)do
            if seat>(party.count or 1)or request.identity~=key then pending[seat]=nil
            elseif time>request.expires then
                pending[seat]=nil
                if manual(request.reason)then notify('玩家'..seat..'暂未归队：角色或落点仍不安全，请稍后重试。')end
            end
        end
        if time<nextAttempt or not party.ready()or api.gs():IsGamePaused(pc)or api.game.inCutscene()then return end
        if (api.panel and api.panel.open)or pc:IsMoveInputIgnored()or pc:IsLookInputIgnored()then return end
        local movement=pawn.CharacterMovement.MovementMode
        if movement~=1 and movement~=2 then return end
        for offset=0,((party.count or 4)-2)do
            local seat=2+((nextSeat-2+offset)%((party.count or 4)-1))
            local request=pending[seat]
            if request then
                nextSeat=seat%(party.count or 4)+1;if nextSeat<2 then nextSeat=2 end
                if request.reason=='ai_distance'then
                    local allowed=party.ai and party.ai.autoRegroupAllowed
                    local ok,value=false,false
                    if type(allowed)=='function'then ok,value=pcall(allowed,seat)end
                    if not ok or value~=true then pending[seat]=nil;return end
                end
                local peer=party.partners[seat]
                if not peer or type(peer.partySafeRegroup)~='function'then
                    pending[seat]=nil
                    if manual(request.reason)then notify('玩家'..seat..'的安全归队模块尚未就绪。')end
                    return
                end
                -- One original-partner dispatch per tick, shared by AI and players.
                local ok,done,reason=pcall(peer.partySafeRegroup,request.reason)
                M.lastOutcome={seat=seat,reason=request.reason,ok=ok and done==true,detail=ok and reason or tostring(done),time=time}
                nextAttempt=time+(ok and done and .6 or .2)
                if ok and done then
                    pending[seat]=nil
                    if manual(request.reason)then notify('玩家'..seat..'已回到1号身边。')end
                elseif not ok then
                    pending[seat]=nil;api.log('Party regroup request failed: '..tostring(done))
                    if manual(request.reason)then notify('玩家'..seat..'归队未执行，请稍后重试。')end
                end
                return
            end
        end
    end
    function M.tick()
        pollInput()
        local _,pc=identity();if not party.loading and party.ready()and api.valid(pc)then pcall(render,party.inputLocked==true,pc)end
        processQueue()
    end
    function M.status()
        local queued={};for seat,request in pairs(pending)do queued[#queued+1]={seat=seat,reason=request.reason,expires=request.expires}end
        table.sort(queued,function(a,b)return a.seat<b.seat end)
        return {queued=queued,lastOutcome=M.lastOutcome,session=lastSession,recall=seenRecall,nextAttempt=nextAttempt}
    end
    RegisterLoadMapPreHook(function()clear();lastSession,lastCount=nil,nil;seenRecall=0 end)
    LoopInGameThreadWithDelay(100,function()
        local ok,err=pcall(M.tick);if not ok then api.log('Party controls error: '..tostring(err))end
        return false
    end)
    return M
end
