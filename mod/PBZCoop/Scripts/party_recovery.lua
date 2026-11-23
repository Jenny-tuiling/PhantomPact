-- Factory; all calls are made by party_recovery on the existing game thread.
-- Owns only custom modes it explicitly installed. Never edits FOV, story tags,
-- sequences, split-screen, input-ignore flags, or another system's custom mode.
local function makeCamera(api,party)
    local M={}
    local baselines,stable,owned,last={},{},{},{}
    local staleNarrative='CameraType.Narrative.XSSL.DaiZuoRenOu'
    local function safe(fn)local ok,value=pcall(fn);if ok then return value end end
    local function valid(value)return value~=nil and safe(function()return api.valid(value)end)==true end
    local function finite(v)return type(v)=='number'and v==v and math.abs(v)<1e9 end
    local function same(a,b)return valid(a)and valid(b)and a:GetAddress()==b:GetAddress()end
    local function full(v)return valid(v)and v:GetFullName()or nil end
    local function key(v)return valid(v)and(full(v)..'@'..tostring(v:GetAddress()))or nil end
    local function tag(value)return safe(function()return value.TagName:ToString()end)end
    local function time(pc)
        local value=safe(function()return api.gs():GetTimeSeconds(pc)end)
        return finite(value)and value or os.clock()
    end
    local function log(text)if api.log then api.log('Camera recovery: '..text)end end
    local function context(seat)
        if type(seat)~='number'or seat%1~=0 or seat<1 or seat>(party.count or 1)then return nil,'该玩家未加入本局'end
        local host=api.getPlayer1();if not valid(host)then return nil,'请先进入存档'end
        local pc=safe(function()return api.gs():GetPlayerController(host,seat-1)end)
        local pawn=valid(pc)and safe(function()return pc.Pawn end)or nil
        local camera=valid(pawn)and safe(function()return pawn.NBCamera end)or nil
        if not valid(pc)or not valid(pawn)or not valid(camera)then return nil,'该玩家的镜头尚未就绪'end
        return {seat=seat,pc=pc,pawn=pawn,camera=camera,pawnKey=key(pawn),cameraKey=key(camera)}
    end
    local function playable(ctx)
        if party.loading or not party.ready()then return false,'场景加载中，请稍后重试'end
        local game=api.game
        if not game or safe(function()return game.inCutscene()end)~=false then return false,'过场期间暂不恢复视角'end
        if safe(function()return api.gs():IsGamePaused(ctx.pc)end)~=false then return false,'请先关闭暂停菜单'end
        if safe(function()return game.isDead(ctx.pawn)end)~=false then return false,'角色死亡时暂不恢复视角'end
        if safe(function()return ctx.pc:IsMoveInputIgnored()end)~=false or safe(function()return ctx.pc:IsLookInputIgnored()end)~=false
            or(api.panel and api.panel.open)then return false,'请先结束当前菜单或交互'end
        local target=safe(function()return ctx.pc:GetViewTarget()end)
        if valid(target)and not same(target,ctx.pawn)then return false,'当前正在使用专用镜头，请结束后重试'end
        return true
    end
    local function snapshot(ctx)
        local c=ctx.camera
        local custom=safe(function()return c:IsSetCustomCameraMode()end)
        local ref=safe(function()return c.CustomCameraMode end)
        if not valid(ref)and custom==true then ref=safe(function()return c:GetCurrentCameraMode()end)end
        local distance=safe(function()return c:GetCameraDistance()end)
        local fov=safe(function()return ctx.pc.PlayerCameraManager:GetFOVAngle()end)
        return {current=tag(safe(function()return c:GetCurrentCameraModeTag()end)),
            desired=tag(safe(function()return c:GetDesiredCameraModeTag()end)),
            initial=tag(safe(function()return c:GetInitialCameraModeTag()end)),
            custom=custom,customObject=ref,customName=full(ref),
            distance=finite(distance)and distance or nil,fov=finite(fov)and fov or nil,time=time(ctx.pc)}
    end
    local function public(s)
        return {current=s.current,desired=s.desired,initial=s.initial,custom=s.custom,
            customMode=s.customName,distance=s.distance,fov=s.fov,time=s.time}
    end
    local function isOurs(row)
        if not row or not valid(row.camera)then return false end
        local set=safe(function()return row.camera:IsSetCustomCameraMode()end)
        local actual=safe(function()return row.camera.CustomCameraMode end)
        if not valid(actual)and set==true then actual=safe(function()return row.camera:GetCurrentCameraMode()end)end
        return set==true and same(actual,row.asset)
    end
    local function release(seat,reason)
        local row=owned[seat];if not row then return true end
        -- If another system took the custom slot, do not reset its replacement.
        if isOurs(row)then
            local ok,err=pcall(function()row.camera:ResetCustomCameraMode(true)end)
            if not ok then row.releaseError=tostring(err);row.phase='release_pending';return false end
        end
        owned[seat]=nil
        last[seat]=last[seat]or{};last[seat].releaseReason=reason
        log('P'..seat..' released owned custom ('..reason..')')
        return true
    end
    local function observeNormal(ctx,s)
        local seat=ctx.seat
        if baselines[seat]and baselines[seat].pawnKey~=ctx.pawnKey then baselines[seat]=nil;stable[seat]=nil end
        -- Only a settled native initial mode is a baseline. Combat, narrative,
        -- custom modes and interpolation are never remembered as normal zoom.
        if s.custom~=false or not s.initial or s.initial=='None'or s.current~=s.initial or s.desired~=s.initial
            or not s.distance or s.distance<50 or s.distance>2500 or not s.fov or s.fov<20 or s.fov>160 then stable[seat]=nil;return end
        local tagValue=ctx.camera:GetInitialCameraModeTag()
        local mode=ctx.camera:GetCameraMode(tagValue);if not valid(mode)then stable[seat]=nil;return end
        local candidate=stable[seat]
        if not candidate or candidate.cameraKey~=ctx.cameraKey or candidate.mode~=s.initial or s.time<candidate.time
            or math.abs(candidate.distance-s.distance)>.5 or math.abs(candidate.fov-s.fov)>.2 then
            stable[seat]={cameraKey=ctx.cameraKey,mode=s.initial,distance=s.distance,fov=s.fov,time=s.time};return
        end
        if s.time-candidate.time>=.75 then
            baselines[seat]={pawnKey=ctx.pawnKey,cameraKey=ctx.cameraKey,mode=s.initial,asset=mode,
                distance=s.distance,fov=s.fov,time=s.time}
        end
    end
    function M.restore(seat)
        local ctx,reason=context(seat);if not ctx then return false,reason end
        local allowed;allowed,reason=playable(ctx)
        if not allowed then release(seat,'protected_state');return false,reason end
        local s=snapshot(ctx);last[seat]={before=public(s)}
        local previous=owned[seat]
        if previous then
            if not release(seat,'explicit_retry')then return false,'原恢复镜头尚未释放，请稍后重试'end
            s=snapshot(ctx)
        end
        if s.custom~=false then return false,'其他功能正在控制镜头，本次未覆盖'end
        if not s.initial or s.initial=='None'then return false,'尚未找到原生默认视角'end
        local narrative=(s.current and s.current:find('CameraType.Narrative.',1,true)==1)
            or(s.desired and s.desired:find('CameraType.Narrative.',1,true)==1)
        if narrative and(s.current~=staleNarrative or s.desired~=staleNarrative)then return false,'该叙事视角尚未确认结束，本次未覆盖'end
        local tagValue=ctx.camera:GetInitialCameraModeTag()
        local mode=ctx.camera:GetCameraMode(tagValue)
        if not valid(mode)then return false,'原生默认镜头资源尚未就绪'end
        local baseline=baselines[seat]
        if baseline and(baseline.pawnKey~=ctx.pawnKey or baseline.cameraKey~=ctx.cameraKey or baseline.mode~=s.initial or not same(baseline.asset,mode))then baseline=nil end
        local row
        local ok,err=pcall(function()
            if narrative then
                row={camera=ctx.camera,pawnKey=ctx.pawnKey,cameraKey=ctx.cameraKey,asset=mode,
                    stale=s.desired,initial=s.initial,started=s.time,phase='requested'}
                owned[seat]=row
                ctx.camera:SetCustomCameraMode(mode,true)
                assert(isOurs(row),'Native custom camera did not accept the requested default asset')
            else
                ctx.camera:SetCameraMode(tagValue,true,true)
            end
            if baseline then ctx.camera:SetCameraDistance(baseline.distance,true)end
        end)
        if not ok then release(seat,'apply_failed');return false,'视角恢复未完成：'..tostring(err)end
        last[seat].requestedMode=s.initial;last[seat].baselineDistance=baseline and baseline.distance or nil
        last[seat].observed=public(snapshot(ctx));last[seat].phase='requested'
        log('P'..seat..' requested native default; custom='..tostring(narrative)..'; distance='..tostring(baseline and baseline.distance or 'native asset default'))
        return true,'已请求恢复'..seat..'号视角；镜头过渡后生效'
    end
    function M.tick()
        for seat=1,4 do
            local ctx=context(seat);local row=owned[seat]
            if not ctx then
                if row then release(seat,'player_unavailable')end
                baselines[seat]=nil;stable[seat]=nil
            else
                local allowed=playable(ctx);local s=snapshot(ctx)
                if row then
                    local reason
                    if row.phase=='release_pending'then reason='pending_release'
                    elseif row.pawnKey~=ctx.pawnKey or row.cameraKey~=ctx.cameraKey then reason='player_changed'
                    elseif not allowed then reason='protected_state'
                    elseif s.desired~=row.stale or s.initial~=row.initial then reason='native_mode_changed'
                    elseif not isOurs(row)then reason='custom_slot_changed'end
                    if reason then release(seat,reason)
                    else row.phase=s.time-row.started>=.5 and'active'or'requested';row.observed=public(s)end
                elseif allowed then observeNormal(ctx,s)end
                if last[seat]then last[seat].observed=public(s);if not owned[seat]then last[seat].phase='native'end end
            end
        end
    end
    function M.stop()
        for seat=1,4 do release(seat,'stop')end
        baselines,stable={},{}
    end
    function M.status()
        local result={slots={}}
        for seat=1,4 do
            local b,o=baselines[seat],owned[seat]
            if b or o or last[seat]then result.slots[#result.slots+1]={slot=seat,
                baseline=b and{mode=b.mode,distance=b.distance,fov=b.fov,time=b.time}or nil,
                owned=o and{mode=full(o.asset),stale=o.stale,phase=o.phase,observed=o.observed,releaseError=o.releaseError}or nil,
                last=last[seat]}end
        end
        return result
    end
    return M
end


-- Camera factory is inserted above this core when preparing the final payload.
return function(api,party)
    local M={anchors={},camera=makeCamera(api,party)}
    local valid,game=api.valid,api.game
    local dir=api.modDir()
    local boot=tostring(os.time())..'-'..tostring(math.floor(os.clock()*1000))
    local nativeSession,seen=nil,{}
    local lastHeartbeat,lastSample=-1e9,-1e9
    local pendingStable,worldKey,playerKey,hookWarning=nil,nil,nil,nil
    local lastObserved=nil
    -- Conservative sampling policy, not altered game movement settings.
    local PATH_SPEED_MAX,PATH_VERTICAL_MAX,PATH_GAP_MAX=1200,150,1.25
    local serial=0
    local replies,replyOrder={},{}
    local function finite(v)return type(v)=='number'and v==v and math.abs(v)<1e12 end
    local function vec(v)
        assert(finite(v.X)and finite(v.Y)and finite(v.Z),'Invalid position')
        return {X=v.X,Y=v.Y,Z=v.Z}
    end
    local function distance(a,b)return math.sqrt((a.X-b.X)^2+(a.Y-b.Y)^2+(a.Z-b.Z)^2)end
    local function now()
        local pc=api.getPlayer1()
        local ok,t=pcall(function()return api.gs():GetTimeSeconds(pc)end)
        return ok and finite(t)and t or os.clock()
    end
    local function read(name,limit)
        local f=io.open(dir..name,'rb');if not f then return nil end
        local s=f:read(limit+1);f:close()
        return s and #s<=limit and s or nil
    end
    local function write(name,text)
        local f=assert(io.open(dir..name,'wb'));assert(f:write(text));assert(f:close())
    end
    local function notify(text)
        api.log('Party recovery: '..text)
        if api.status then pcall(api.status.notify,'party-recovery',text)end
    end
    local function slot(slot)
        if type(slot)~='number'or slot%1~=0 or slot<1 or slot>(party.count or 1)then return nil,nil,'该玩家未加入本局' end
        local host=api.getPlayer1()
        if not valid(host)then return nil,nil,'请先进入存档' end
        local pc=api.gs():GetPlayerController(host,slot-1)
        local pawn=valid(pc)and pc.Pawn or nil
        if not valid(pc)or not valid(pawn)then return nil,nil,'该玩家尚未生成' end
        return pc,pawn
    end
    local function playable(pc,pawn)
        if party.loading or not party.ready()then return false,'正在加载场景，请稍后重试' end
        if game.isDead(pawn)then return false,'角色死亡时不执行恢复' end
        if api.gs():IsGamePaused(pc)or game.inCutscene()then return false,'请先结束菜单或过场，再使用恢复' end
        if pc:IsMoveInputIgnored()or pc:IsLookInputIgnored()or (api.panel and api.panel.open)then return false,'当前交互尚未结束，请结束后重试' end
        return true
    end
    local function identity(pawn)
        return pawn:GetOuter():GetFullName(),pawn:GetAddress()
    end
    local function resetAnchors()
        M.anchors={};pendingStable=nil;lastObserved=nil
    end
    local function syncIdentity(pawn)
        local world,id=identity(pawn)
        if worldKey~=world or playerKey~=id then
            worldKey,playerKey=world,id;resetAnchors()
        end
    end
    local function dimensions(pawn)
        local capsule=pawn.CapsuleComponent
        assert(valid(capsule),'Capsule unavailable')
        local radius,half=capsule:GetScaledCapsuleRadius(),capsule:GetScaledCapsuleHalfHeight()
        assert(finite(radius)and finite(half)and radius>=5 and half>=radius and half<=300,'Invalid capsule dimensions')
        return radius,half
    end
    local function checkedGround(pawn,position)
        local lib=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')
        assert(valid(lib),'Ground trace unavailable')
        local radius,half=dimensions(pawn)
        local none={R=0,G=0,B=0,A=0}
        local hit={}
        local got=lib:LineTraceSingle(pawn,{X=position.X,Y=position.Y,Z=position.Z+40},
            {X=position.X,Y=position.Y,Z=position.Z-half-100},0,false,{pawn},0,hit,true,none,none,0)
        if got~=true or not hit.Location or not hit.ImpactNormal then return nil,'没有确认到可靠地面' end
        local floor=vec(hit.Location);local nz=hit.ImpactNormal.Z
        if not finite(nz)or nz<0.75 then return nil,'该处坡度过陡' end
        if math.abs((position.Z-half)-floor.Z)>45 then return nil,'落脚点高度已改变' end
        local center={X=position.X,Y=position.Y,Z=floor.Z+half+4}
        local blocked=lib:CapsuleTraceSingle(pawn,center,{X=center.X,Y=center.Y,Z=center.Z+1},
            radius+2,half,0,false,{pawn},0,{},true,none,none,0)
        if blocked~=false then return nil,'该处空间不足，可能有墙壁或障碍' end
        return center
    end
    local function checkContinuity(position,speed,time)
        if lastObserved then
            local dt=time-lastObserved.time
            local moved=distance(position,lastObserved.position)
            -- Detect same-world relocation as well as normal LoadMapPreHook.
            -- A wall-clock gap does not grant a huge unobserved travel budget.
            local allowance=math.max(200,math.min(PATH_SPEED_MAX,math.max(speed,lastObserved.speed))*math.max(0,math.min(dt,PATH_GAP_MAX))*1.5+100)
            if dt<0 or moved>1500 or moved>allowance or(dt>PATH_GAP_MAX and moved>200)then
                resetAnchors()
                M.lastReset={reason='discontinuous_path',time=time,distance=moved}
                return false
            end
        end
        return true
    end
    local function sampleAnchor(time)
        local function state(code,message)
            M.sampleStatus={state=code,message=message,time=time}
        end
        local pc,pawn,reason=slot(1);if not pc then pendingStable=nil;state('no_pawn',reason);return end
        syncIdentity(pawn)
        local position=vec(pawn:K2_GetActorLocation())
        local velocity=vec(pawn:GetVelocity())
        local speed=math.sqrt(velocity.X^2+velocity.Y^2+velocity.Z^2)
        checkContinuity(position,speed,time)
        lastObserved={position=position,time=time,speed=speed}
        local playableNow;playableNow,reason=playable(pc,pawn)
        if not playableNow then pendingStable=nil;state('not_playable',reason);return end
        local movement=pawn.CharacterMovement.MovementMode
        if movement~=1 and movement~=2 then pendingStable=nil;state('not_grounded','角色未处于普通地面移动状态');return end
        if velocity.X^2+velocity.Y^2>PATH_SPEED_MAX^2 or math.abs(velocity.Z)>PATH_VERTICAL_MAX then
            pendingStable=nil;state('unstable_velocity','移动或下坠速度异常，暂不记录安全点');return
        end
        -- Every sample, including while walking/running, must pass the same
        -- real floor and full-capsule clearance checks used at return time.
        local point;point,reason=checkedGround(pawn,position)
        if not point then pendingStable=nil;state('ground_rejected',reason);return end
        if not pendingStable or time<pendingStable.time or time-pendingStable.lastTime>PATH_GAP_MAX then
            pendingStable={position=position,time=time,lastTime=time,confirmations=1}
            state('confirming_ground','正在连续确认经过的安全地面');return
        end
        pendingStable.lastTime=time;pendingStable.position=position
        pendingStable.confirmations=pendingStable.confirmations+1
        if pendingStable.confirmations<3 or time-pendingStable.time<1 then
            state('confirming_ground','正在连续确认经过的安全地面');return
        end
        local latest=M.anchors[1]
        if latest and distance(point,latest.point)<100 then state('already_recorded','当前位置附近已有安全点');return end
        table.insert(M.anchors,1,{point=point,rotation={Pitch=0,Yaw=pawn:K2_GetActorRotation().Yaw,Roll=0},time=time,world=worldKey})
        while #M.anchors>16 do table.remove(M.anchors)end
        M.anchorError=nil;state('recorded','已记录走过且经地面、空间检查的安全点')
    end
    function M.safeReturn()
        local report={time=now(),recorded=#M.anchors,candidates=0,checked=0,rejections={}}
        M.lastSafe=report
        local function result(ok,code,message)
            report.ok=ok;report.code=code;report.message=message;return ok,message
        end
        local pc,pawn,reason=slot(1);if not pc then return result(false,'no_pawn',reason)end
        syncIdentity(pawn);report.recorded=#M.anchors
        local ok;ok,reason=playable(pc,pawn);if not ok then return result(false,'not_playable',reason)end
        local move=pawn.CharacterMovement.MovementMode
        if move~=1 and move~=2 and move~=3 then return result(false,'movement_state','攀爬、乘船等动作中不执行脱困')end
        local velocity=vec(pawn:GetVelocity())
        if move==3 and math.abs(velocity.Z)>150 then return result(false,'falling','正在跳跃或下落，请先稳定后重试')end
        local current=vec(pawn:K2_GetActorLocation())
        if not checkContinuity(current,math.sqrt(velocity.X^2+velocity.Y^2+velocity.Z^2),report.time)then
            report.recorded=#M.anchors
            return result(false,'path_changed','检测到场景内位置突变，旧安全点已清除；本次未传送')
        end
        local candidates={}
        for _,anchor in ipairs(M.anchors)do
            local d=distance(current,anchor.point)
            if anchor.world==worldKey and d>=100 and d<=1500 then candidates[#candidates+1]={anchor=anchor,distance=d}end
        end
        report.candidates=#candidates
        table.sort(candidates,function(a,b)return a.distance<b.distance end)
        for _,candidate in ipairs(candidates)do
            report.checked=report.checked+1
            local destination,why=checkedGround(pawn,candidate.anchor.point)
            if destination then
                local actualDistance=distance(current,destination)
                if actualDistance<100 or actualDistance>1500 then
                    destination=nil;why='地面变化后的实际落点超出1至15米范围'
                end
            end
            if destination then
                -- Engine TeleportTo still performs its encroachment check; no unchecked SetActorLocation.
                local moved=pawn:K2_TeleportTo(destination,candidate.anchor.rotation)
                if moved==true then
                    pawn.CharacterMovement:StopMovementImmediately()
                    local landed=vec(pawn:K2_GetActorLocation())
                    if distance(landed,destination)>100 then return result(false,'adjusted','落点被游戏调整，请检查当前位置')end
                    pendingStable=nil;lastObserved={position=landed,time=now(),speed=0}
                    return result(true,'returned','1号已回到最近记录的安全落脚点')
                end
                why='引擎拒绝此落脚点的碰撞检查'
            end
            report.rejections[#report.rejections+1]={distance=candidate.distance,reason=why}
        end
        if #M.anchors==0 then
            return result(false,'no_bookmarks','尚未记录安全点：请先在正常地面稳定行走或站立1秒；本次未传送')
        elseif #candidates==0 then
            return result(false,'out_of_range','已记录安全点，但均不在1至15米范围内；未执行传送')
        end
        return result(false,'destinations_rejected','附近安全点目前不可用：'..tostring(report.rejections[1]and report.rejections[1].reason or '落点检查未通过'))
    end
    function M.restoreCamera(seat)
        if not M.camera then return false,'视角恢复模块尚未就绪' end
        return M.camera.restore(seat)
    end
    local function dispatch(action,seat)
        if action=='camera'then return M.restoreCamera(seat)end
        if action=='safe'and seat==1 then return M.safeReturn()end
        return false,'不支持的恢复操作'
    end
    local function run(action,seat,id)
        local ok,done,message=pcall(dispatch,action,seat)
        local state=not ok and 'error'or(done and 'ok'or'blocked')
        message=not ok and ('恢复未执行：'..tostring(done))or tostring(message or '没有收到执行结果')
        message=message:gsub('[\r\n]',' '):sub(1,950)
        M.lastRequest={time=now(),source=id and 'settings'or'native',id=id,action=action,seat=seat,state=state,message=message}
        if id then
            local reply='PBZREC1 '..id..' '..state..' '..message..'\n'
            replies[id]=reply;replyOrder[#replyOrder+1]=id
            if #replyOrder>32 then replies[table.remove(replyOrder,1)]=nil end
            write('recovery_status.txt',reply)
        end
        notify(message)
        return done,state,message
    end
    local function pollUI()
        local path=dir..'recovery_requests.txt'
        local f=io.open(path,'rb');if not f then return end
        local line=f:read(257);f:close()
        assert(os.remove(path),'Cannot consume recovery request')
        if not line or #line>256 then notify('已忽略异常恢复请求');return end
        local id,action,seat=line:match('^PBZREC1 ([A-Za-z0-9%-]+) ([a-z]+) ([1-4])\r?\n?$')
        seat=tonumber(seat)
        if not id or #id>80 or (action~='camera'and action~='safe')or(action=='safe'and seat~=1)then
            notify('已忽略无效恢复请求');return
        end
        if replies[id]then write('recovery_status.txt',replies[id]);return end
        run(action,seat,id)
    end
    local function pollNative()
        local data=read('recovery_actions.txt',256);if not data then return end
        local session,a,b,c,d,e,hook=data:match('^PBZRECINPUT1 (%d+) (%d+) (%d+) (%d+) (%d+) (%d+) ([01])\r?\n?$')
        if not session or hook~='1'then return end
        local counters={tonumber(a),tonumber(b),tonumber(c),tonumber(d),tonumber(e)}
        for _,v in ipairs(counters)do if not finite(v)or v>4294967295 then return end end
        if nativeSession~=session then nativeSession,seen=session,counters;return end
        for i=1,5 do
            if counters[i]<seen[i]then
                seen[i]=counters[i] -- Counter reset/wrap is never an input event.
            elseif counters[i]>seen[i]then
                seen[i]=counters[i]
                if i==5 then run('safe',1)elseif i<=(party.count or 1)then run('camera',i)end
            end
        end
    end
    function M.tick()
        local time=now()
        pollUI();pollNative()
        if M.camera then M.camera.tick()end
        if time<lastSample or time-lastSample>=0.5 then
            lastSample=time
            local ok,err=pcall(sampleAnchor,time)
            if not ok then
                M.sampleStatus={state='error',time=time,message=tostring(err)}
                if M.anchorError~=tostring(err)then M.anchorError=tostring(err);api.log('Party recovery safe point deferred: '..M.anchorError)end
            end
        end
        if time<lastHeartbeat or time-lastHeartbeat>=1 then
            lastHeartbeat=time;write('recovery_ready.txt','PBZRECOVERY1 '..boot..' '..party.count..'\n')
            local hook=read('recovery_input_status.txt',128)
            if hook then
                local xinput,keyboard,code=hook:match('^PBZRECHOOK1 ([01]) ([01]) (%d+)')
                if keyboard=='0'and hookWarning~=code then hookWarning=code;api.log('Party recovery: keyboard shortcut unavailable ('..code..'); use gamepad or recovery panel')end
            end
        end
    end
    function M.status()
        local counters={};for i,v in ipairs(seen)do counters[i]=v end
        return {anchors=#M.anchors,world=worldKey,nativeSession=nativeSession,nativeSeen=counters,boot=boot,
            sample=M.sampleStatus,lastReset=M.lastReset,lastSafe=M.lastSafe,lastRequest=M.lastRequest,anchorError=M.anchorError,
            camera=M.camera and M.camera.status()or nil}
    end
    -- Discard any prior-run UI request; never replay a button press on a later game launch.
    os.remove(dir..'recovery_requests.txt')
    os.remove(dir..'recovery_ready.txt')
    RegisterLoadMapPreHook(function()
        resetAnchors();worldKey,playerKey=nil,nil
        if M.camera then M.camera.stop()end
    end)
    LoopInGameThreadWithDelay(100,function()
        local ok,err=pcall(M.tick)
        if not ok then api.log('Party recovery error: '..tostring(err))end
        return false
    end)
    party.recovery=M
    api.log('Party recovery ready: explicit camera reset; player 1 checked-ground return; no save/progression writes')
    return M
end
