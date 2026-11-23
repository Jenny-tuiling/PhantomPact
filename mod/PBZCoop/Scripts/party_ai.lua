-- Local companion controller for the existing four-player adapter.
-- No network, model, damage/health writes, spawning or player-1 input injection.
return function(api, party)
    local Policy = dofile(api.modDir() .. 'Scripts/party_ai_policy.lua')
    local M = { slots = {}, sequence = 0, errors = {}, packetFailures = 0 }
    local valid, game = api.valid, api.game
    local dir = api.modDir()
    local lastStatus, lastSession, enemyAt, enemies = nil, nil, -1e9, {}
    local enemyActors={}
    local lastTick, mapEpoch = nil, 0
    local AUTO_DISTANCE_CM,AUTO_HEIGHT_CM,AUTO_CONFIRM_S,AUTO_COOLDOWN_S=2500,600,3,8
    local KEY = {
        Gamepad_DPad_Up=1, Gamepad_DPad_Down=2, Gamepad_DPad_Left=4, Gamepad_DPad_Right=8,
        Gamepad_RightThumbstick=128, Gamepad_LeftShoulder=256, Gamepad_RightShoulder=512,
        Gamepad_FaceButton_Bottom=4096, Gamepad_FaceButton_Right=8192,
        Gamepad_FaceButton_Left=16384, Gamepad_FaceButton_Top=32768,
        Gamepad_LeftTrigger='lt', Gamepad_LeftTriggerAxis='lt',
        Gamepad_RightTrigger='rt', Gamepad_RightTriggerAxis='rt'
    }
    -- Names evidenced by the upstream local-coop test helpers and guard probe.
    -- Resolve their actual gamepad bindings in active contexts; never guess buttons.
    local ACTION = { IA_AttackL_Press='attack', IA_Stance='block' }
    local function finite(x) return type(x)=='number' and x==x and math.abs(x)<1e15 end
    local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
    local function report(key,text)
        if M.errors[key] == text then return end
        M.errors[key]=text; api.log('Party AI: '..text)
    end
    local function nowOf(pc)
        local ok,t=pcall(function() return api.gs():GetTimeSeconds(pc) end)
        return ok and finite(t) and t or os.clock()
    end
    local function readStatus()
        local f=io.open(dir..'party_ai_status.txt','rb')
        if not f then return nil end
        local data=f:read(1025); f:close()
        if not data or #data>1024 then return nil end
        local lines={}; for line in data:gmatch('[^\r\n]+') do lines[#lines+1]=line end
        if #lines~=4 then return nil end
        local session,installed,accepted=lines[1]:match('^PBZAI1 (%d+) ([01]) (%d+)$')
        if not session or installed~='1' then return nil end
        local out={session=session,accepted=tonumber(accepted),rows={}}
        for i=2,4 do
            local slot,enabled,epoch,reason=lines[i]:match('^([234]) ([01]) (%d+) ([0-4])$')
            slot=tonumber(slot);epoch=tonumber(epoch)
            if not slot or not epoch or epoch<1 or out.rows[slot] then return nil end
            out.rows[slot]={enabled=enabled=='1',epoch=epoch,reason=tonumber(reason)}
        end
        return out
    end
    local function pad() return {buttons=0,lt=0,rt=0,lx=0,ly=0,rx=0,ry=0} end
    local function press(p,k)
        if k=='lt' then p.lt=255 elseif k=='rt' then p.rt=255
        elseif type(k)=='number' then p.buttons=p.buttons | k end
    end
    local function slotState(slot)
        local s=M.slots[slot]
        if not s then s={policy=Policy.new(slot),mode='manual',mappings={},mappingAt=-1e9};M.slots[slot]=s end
        return s
    end
    local function resetSlot(s)
        Policy.reset(s.policy);s.attackUntil=nil;s.attackTarget=nil;s.lastOutput=nil;s.obstacle=nil;s.obstacleAt=nil
        s.dodgeUntil=nil;s.detourUntil=nil;s.nextDetour=nil
        s.feedback=nil;s.pendingAttack=nil;s.attackSerial=0;s.submittedAttackId=nil;s.publishedAttackDown=false
        s.autoFarSince=nil
    end
    local function subsystem(pc)
        for _,sub in ipairs(FindAllOf('EnhancedInputLocalPlayerSubsystem') or {}) do
            local ok,match=pcall(function() return sub:GetOuter():GetAddress()==pc.Player:GetAddress() end)
            if ok and match and valid(sub) then return sub end
        end
    end
    local function bindings(pc,s,now)
        if now<s.mappingAt+5 and s.mappingPC==pc:GetAddress() then return s.mappings end
        s.mappingAt,s.mappingPC,s.mappings=now,pc:GetAddress(),{}
        local sub=subsystem(pc)
        if not sub then return s.mappings end
        local found={attack={},block={}}
        for _,context in ipairs(FindAllOf('InputMappingContext') or {}) do
            local ok,active=pcall(function() return sub:HasMappingContext(context,{}) end)
            if ok and active then
                local function scan(arr)
                    arr:ForEach(function(_,entry)
                        local item=entry:get()
                        local name=item.Action:GetFName():ToString()
                        local kind=ACTION[name]
                        if kind then
                            local k=KEY[item.Key.KeyName:ToString()]
                            if k then found[kind][k]=true end
                        end
                    end)
                end
                pcall(function() scan(context.DefaultKeyMappings.Mappings) end)
                pcall(function() scan(context.Mappings) end)
            end
        end
        for kind,keys in pairs(found) do
            local count,chosen=0,nil
            for k in pairs(keys) do count=count+1;chosen=k end
            if count==1 then s.mappings[kind]=chosen end
        end
        if s.mappings.attack and s.mappings.attack==s.mappings.block then
            s.mappings.attack,s.mappings.block=nil,nil
            report('map_collision'..s.policy.slot,'Attack and stance share one key; ambiguous actions disabled.')
        end
        report('map'..s.policy.slot,'P'..tostring(s.policy.slot)..' bindings: attack='..tostring(s.mappings.attack)..' block='..tostring(s.mappings.block))
        return s.mappings
    end
    local function snapshot(actor)
        if not valid(actor) then return nil end
        local hp,maxhp=game.getHealth(actor)
        local loc=actor:K2_GetActorLocation()
        if not(finite(hp) and finite(maxhp) and maxhp>0 and finite(loc.X) and finite(loc.Y) and finite(loc.Z)) then return nil end
        local movement=actor.CharacterMovement.MovementMode
        local p={id=tostring(actor:GetAddress()),x=loc.X,y=loc.Y,z=loc.Z,hp=hp,max_hp=maxhp,
            grounded=movement==1 or movement==2,dead=game.isDead(actor)}
        -- These read-only calls are already used by PBZ's local-coop adapter.
        pcall(function()local r=actor:K2_GetActorRotation();if finite(r.Yaw)then p.yaw=r.Yaw end end)
        pcall(function()local v=actor:GetVelocity();if finite(v.X)and finite(v.Y)then p.vx,p.vy=v.X,v.Y end end)
        pcall(function()
            local r=actor.CapsuleComponent:GetScaledCapsuleRadius()
            if finite(r)and r>0 and r<=1000 then p.radius=r end
        end)
        pcall(function()
            local value=game.getPosture(actor)
            if finite(value)and value>=0 then p.posture=value end
        end)
        pcall(function()
            local maximum=actor.AttributeSetBase.Shachi_Max.CurrentValue
            if finite(maximum)and maximum>0 then p.max_posture=maximum end
        end)
        return p
    end
    local function farFromLeader(player,leader)
        return (player.x-leader.x)^2+(player.y-leader.y)^2>AUTO_DISTANCE_CM^2
            or math.abs(player.z-leader.z)>=AUTO_HEIGHT_CM
    end
    -- The shared controls queue rechecks this immediately before consuming an AI
    -- request. Manual off, death, menus, loading and input lock cancel old work.
    function M.autoRegroupAllowed(slot)
        if type(slot)~='number'or slot<2 or slot>(party.count or 1)or slot%1~=0 then return false,'not_joined' end
        local status=readStatus()
        if not status or status.session~=lastSession or not status.rows[slot].enabled then return false,'manual_or_stale' end
        if M.stopped or party.loading or party.inputLocked then return false,'paused' end
        local peer,state=party.partners[slot],party.states[slot]
        if not peer or not state then return false,'not_joined' end
        local ok,ready=pcall(peer.partyAIReady)
        if not ok or ready~=true then return false,'partner_not_ready' end
        local _,host=api.getPlayer1()
        local leader,player=snapshot(host),snapshot(state.p2Pawn)
        if not leader or not player or leader.dead or player.dead or leader.hp<=0 or player.hp<=0
            or not leader.grounded or not player.grounded then return false,'not_grounded_or_alive' end
        return farFromLeader(player,leader),'distance_rechecked'
    end
    local function queueAutoRegroup(slot,s,now,player,leader)
        if not leader.grounded or party.inputLocked or not farFromLeader(player,leader)then s.autoFarSince=nil;return end
        if s.autoFarSince and now<s.autoFarSince then s.autoFarSince=nil;s.autoNextAt=nil end
        s.autoFarSince=s.autoFarSince or now
        if now-s.autoFarSince<AUTO_CONFIRM_S or now<(s.autoNextAt or -1e9)then return end
        if type(party.requestRegroup)~='function'then s.autoNextAt=now+1;return end
        local ok,accepted,reason=pcall(party.requestRegroup,slot,'ai_distance')
        s.autoNextAt=now+(ok and accepted==true and AUTO_COOLDOWN_S or 1)
        s.autoLast={time=now,queued=ok and accepted==true,reason=ok and reason or tostring(accepted)}
        if ok and accepted==true then s.autoFarSince=nil end
    end
    local function getEnemies(now,leader,friends)
        if now>=enemyAt and now-enemyAt<0.25 then return enemies end
        enemyAt=now;enemies={};enemyActors={}
        local candidates={}
        for _,actor in ipairs(game.listEnemies(false) or {}) do
            local ok,e=pcall(function()
                if not valid(actor) or friends[tostring(actor:GetAddress())] then return nil end
                local p=snapshot(actor)
                if p and not p.dead and p.hp>0 and (p.x-leader.x)^2+(p.y-leader.y)^2<=1800^2 then
                    p.hostile=true
                    -- Existing boss probes use these exact fields. Hidden phase
                    -- placeholders are not combat targets; unknown properties
                    -- remain unknown, rather than being guessed from a name.
                    pcall(function()p.visible=actor.bHidden~=true end)
                    pcall(function()if valid(actor.Mesh)and actor.Mesh:IsVisible()==false then p.visible=false end end)
                    pcall(function()p.attackable=valid(actor.Controller)end)
                    if p.visible==false or p.attackable==false then return nil end
                    pcall(function()
                        local out={}
                        StaticFindObject('/Script/SGameAI.Default__SGameAIFunctionLibrary'):GetTargetActor(actor.Controller,out)
                        if valid(out.Target)then p.target_id=tostring(out.Target:GetAddress())end
                    end)
                    enemyActors[p.id]=actor;return p
                end
            end)
            if ok and e then candidates[#candidates+1]=e end
        end
        -- Engine enumeration order is not relevance order; retain nearest threats.
        table.sort(candidates,function(a,b)
            local da=(a.x-leader.x)^2+(a.y-leader.y)^2
            local db=(b.x-leader.x)^2+(b.y-leader.y)^2
            return da==db and a.id<b.id or da<db
        end)
        for i=1,math.min(32,#candidates)do enemies[i]=candidates[i]end
        return enemies
    end
    local function clearAttack(pawn,player,targetId,friendlyActors)
        local target=enemyActors[targetId]
        if not valid(target) or game.isDead(target) then return false end
        local inactive=false
        pcall(function()if target.bHidden==true then inactive=true end end)
        pcall(function()if valid(target.Mesh)and target.Mesh:IsVisible()==false then inactive=true end end)
        pcall(function()if not valid(target.Controller)then inactive=true end end)
        if inactive then return false end -- phase may change inside the enemy-cache interval
        local lib=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')
        if not valid(lib) then return false end
        local ignore={target};for _,actor in ipairs(friendlyActors) do ignore[#ignore+1]=actor end
        local loc=target:K2_GetActorLocation()
        local none={R=0,G=0,B=0,A=0}
        local hit=lib:LineTraceSingle(pawn,{X=player.x,Y=player.y,Z=player.z},loc,0,false,ignore,0,{},true,none,none,0)
        return hit==false
    end
    -- Existing upstream LineTraceSingle signature, no teleport/path bypass.
    -- When the probe cannot be read reliably, movement waits rather than walking over a ledge.
    local function safeMove(pawn,p,mx,my,friendlyActors)
        if mx*mx+my*my<0.001 then return 0,0 end
        local lib=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')
        if not valid(lib) then return 0,0 end
        local length=math.sqrt(mx*mx+my*my);local dx,dy=mx/length,my/length
        local dest={X=p.x+dx*120,Y=p.y+dy*120,Z=p.z}
        local none={R=0,G=0,B=0,A=0}
        local function trace(a,b)
            local hit={}
            local got=lib:LineTraceSingle(pawn,a,b,0,false,friendlyActors,0,hit,true,none,none,0)
            return got,hit
        end
        local wall=trace({X=p.x,Y=p.y,Z=p.z},{X=dest.X,Y=dest.Y,Z=p.z})
        if wall then return 0,0 end
        local half=90
        pcall(function()
            local h=pawn.CapsuleComponent:GetScaledCapsuleHalfHeight()
            if finite(h)and h>=10 and h<=500 then half=h end
        end)
        local got,hit=trace({X=dest.X,Y=dest.Y,Z=p.z+40},{X=dest.X,Y=dest.Y,Z=p.z-half-150})
        local z=hit.Location and tonumber(hit.Location.Z)
        if not got or not finite(z) or math.abs(z-(p.z-half))>120 then return 0,0 end
        return mx,my
    end
    local function steerSafely(s,pawn,player,mx,my,friendlyActors,now)
        local function probe(x,y)
            local ok,a,b=pcall(safeMove,pawn,player,x,y,friendlyActors)
            if ok and a*a+b*b>0.001 then return a,b end
        end
        local x,y=probe(mx,my)
        if x then s.detourUntil=nil;return x,y end
        -- Local obstacle avoidance, not a navmesh. Every candidate still passes
        -- the same wall AND ground checks. Do not alternate left/right each tick.
        if s.detourUntil and now<s.detourUntil then
            x,y=probe(s.detourX,s.detourY)
            if x then return x,y end
        end
        if now<(s.nextDetour or 0)then return 0,0 end
        s.nextDetour=now+0.2
        local side=s.policy.slot==3 and -1 or 1
        for _,sign in ipairs({side,-side})do
            local angle=math.rad(60*sign)
            local dx=(mx*math.cos(angle)-my*math.sin(angle))*0.65
            local dy=(mx*math.sin(angle)+my*math.cos(angle))*0.65
            x,y=probe(dx,dy)
            if x then s.detourX,s.detourY,s.detourUntil=x,y,now+0.6;return x,y end
        end
        return 0,0
    end
    local function output(slot,row,now,leader,friends,friendlyActors,enemyList,teammates,assignments)
        local s=slotState(slot);local result=pad()
        s.pendingAttack=nil
        local state=party.states[slot];local peer=party.partners[slot]
        if slot>(party.count or 1) or not state or not peer or not row then
            resetSlot(s);s.enabled=row and row.enabled or false;s.ready=false;s.mode='waiting';s.blockReason='not_joined'
            return result,false
        end
        local ok,ready,readyReason=pcall(peer.partyAIReady)
        s.blockReason=not ok and tostring(ready)or(ready~=true and(readyReason or 'partner_not_ready')or nil)
        ready=ok and ready==true and leader~=nil and not leader.dead and party.loading~=true
        local pc,pawn=state.p2Controller,state.p2Pawn
        local player=ready and snapshot(pawn) or nil
        if player and (player.dead or player.hp<=0 or not player.grounded) then ready=false end
        if party.loading then s.blockReason='loading' end
        local identity=ready and player and player.id or nil
        if s.identity~=identity or s.epoch~=row.epoch then
            resetSlot(s);s.identity,s.epoch=identity,row.epoch;s.warmup=now+0.2;s.mappingAt=-1e9
        end
        local enabled=row.enabled and ready and player~=nil
        s.enabled,s.ready=row.enabled,ready and player~=nil
        if not row.enabled then
            resetSlot(s);s.mode='manual';return result,ready and player~=nil
        end
        if not enabled or now<(s.warmup or 0) then s.mode='waiting';return result,false end
        queueAutoRegroup(slot,s,now,player,leader)
        local friendIds={};for id in pairs(friends) do friendIds[#friendIds+1]=id end
        local map=bindings(pc,s,now)
        local snap={enabled=true,ready=true,epoch=tostring(mapEpoch)..':'..row.epoch,
            player=player,leader=leader,enemies=enemyList,friend_ids=friendIds,friends=teammates,
            feedback=s.feedback,aggressive=true,
            assignment_active=assignments~=nil,assignments=assignments,
            assigned_target_id=assignments and assignments[slot] or nil,
            capabilities={attack=map.attack~=nil,block=map.block~=nil,dodge=false,
                guard_attack=map.attack~=nil and map.block~=nil and map.attack~=map.block},
            paused=false,cutscene=false,input_locked=party.inputLocked==true}
        local out=Policy.step(s.policy,snap,now)
        s.mode,s.lastOutput=out.mode,out
        local mx,my=out.move_x or 0,out.move_y or 0
        if mx*mx+my*my>0.001 then
            local safe,x,y=pcall(steerSafely,s,pawn,player,mx,my,friendlyActors,now)
            mx,my=safe and x or 0,safe and y or 0
            if mx==0 and my==0 then s.mode='blocked';s.blockReason='movement_probe_blocked' end
        end
        local rotation=pc:GetControlRotation()
        local yaw=tonumber(rotation.Yaw)
        if not finite(yaw) then return pad(),false end
        if finite(out.look_yaw) then
            local delta=(out.look_yaw-yaw+180)%360-180
            yaw=yaw+clamp(delta,-9,9) -- max180deg/s at20Hz, only this AI player's camera
            pc:SetControlRotation({Pitch=-10,Yaw=yaw,Roll=0})
        end
        local rad=math.rad(yaw)
        result.lx=math.floor(clamp(-math.sin(rad)*mx+math.cos(rad)*my,-1,1)*32767)
        result.ly=math.floor(clamp(math.cos(rad)*mx+math.sin(rad)*my,-1,1)*32767)
        local aimed=finite(out.look_yaw) and math.abs((out.look_yaw-yaw+180)%360-180)<=45
        local visible,clear=false,false
        if out.target_id and (out.attack or s.attackUntil) then
            visible,clear=pcall(clearAttack,pawn,player,out.target_id,friendlyActors)
        end
        if out.mode~='combat' or out.reason~='assist' or not aimed or not visible or not clear
            or (s.attackTarget and s.attackTarget~=out.target_id) then s.attackUntil=nil end
        if out.attack and map.attack and aimed and visible and clear then
            s.attackUntil=now+0.12;s.attackTarget=out.target_id
            s.attackSerial=(s.attackSerial or 0)+1
        end
        -- PBZ permits light attack and stance together. Resource selection is
        -- the policy's job; a guard command must not erase an attack pulse.
        if out.dodge then s.attackUntil=nil end
        if out.block or out.dodge then press(result,map.block) end
        if s.attackUntil and now<s.attackUntil and out.target_id and map.attack then
            press(result,map.attack)
            s.pendingAttack={id=s.attackSerial,target_id=out.target_id,at=now}
        end
        -- Dodge is deliberately not mapped until this build's action is verified.
        return result,true
    end
    -- Use the same status factory and full-window channel as the visible lock
    -- notice. Each seat owns a separate tip positioned over its viewport pane.
    -- Text/FadeIn are initialized once per ownership/layout transition only.
    local function clearBanner(s)
        if valid(s.banner) then pcall(function()s.banner:RemoveFromParent()end) end
        s.banner,s.bannerKey,s.bannerFailedKey,s.bannerLabel=nil,nil,nil,nil
    end
    local function clearBanners()
        for _,s in pairs(M.slots)do clearBanner(s)end
    end
    local function updateBanners(status,pc,wrote)
        for slot=2,4 do
            local s=slotState(slot);local row=status.rows[slot]
            local state=party.states[slot];local controller=state and state.p2Controller
            local show=row.enabled and s.ready==true and slot<=(party.count or 1)
                and party.loading~=true and valid(controller)
            if not show then clearBanner(s)
            elseif wrote then
                local ok,err=pcall(function()
                    local lib=StaticFindObject('/Script/UMG.Default__WidgetLayoutLibrary')
                    local size,scale=lib:GetViewportSize(pc),lib:GetViewportScale(pc)
                    assert(finite(size.X)and finite(size.Y)and finite(scale)and scale>0,'Invalid banner viewport')
                    local paneWidth=size.X/scale/(party.count or 1)
                    local width=math.min(600,paneWidth-40)
                    assert(width>=100,'Guest viewport too small for banner')
                    local key=table.concat({controller:GetAddress(),pc:GetAddress(),row.epoch,mapEpoch,width,size.X,size.Y,scale,party.count},':')
                    local roles={guard='护卫',flank='突击',support='协攻'}
                    local modes={combat='进攻',defending='防御',retreat='后撤',following='跟随',blocked='避障',waiting='就位'}
                    local last=s.lastOutput or {}
                    local label='AI托管中 · '..(roles[last.role]or '队友')..' · '..(modes[s.mode]or '等待')
                    if valid(s.banner)and s.bannerKey==key then
                        if s.bannerLabel~=label then s.banner:SetText(FText(label));s.bannerLabel=label end
                        return
                    end
                    if s.bannerFailedKey==key then return end
                    clearBanner(s);s.bannerFailedKey=key
                    assert(api.status and type(api.status.newTipWidget)=='function','AI banner factory unavailable')
                    local tip=api.status.newTipWidget(455, true) -- coordinates are in the full game window
                    assert(valid(tip),'AI banner creation failed')
                    s.banner=tip -- owned immediately so partial creation can be reclaimed
                    tip:SetText(FText(label));s.bannerLabel=label
                    -- Match status.show: let FadeIn finish once, with restore
                    -- disabled. Never stop it at the transparent initial frame.
                    tip:PlayAnimation(tip.FadeIn,0,1,0,1,false)
                    assert(valid(tip.ItemText),'AI banner text child unavailable')
                    tip.ItemText:SetRenderOpacity(1)
                    tip:SetColorAndOpacity({R=1,G=0.12,B=0.12,A=1})
                    tip:SetRenderOpacity(1)
                    tip:SetDesiredSizeInViewport({X=width,Y=80})
                    tip:SetPositionInViewport({X=paneWidth*(slot-1)+20,Y=120},false)
                    tip:SetVisibility(3) -- HitTestInvisible; never takes game/menu input
                    s.bannerKey,s.bannerFailedKey=key,nil
                end)
                if not ok then
                    local failed=s.bannerFailedKey
                    clearBanner(s);s.bannerFailedKey=failed
                    report('banner'..slot,'P'..slot..' AI banner unavailable: '..tostring(err))
                end
            end
        end
    end
    local function writePacket(status,rows)
        M.sequence=math.max(M.sequence,status.accepted or 0)+1
        local parts={'PBZAI1 '..status.session..' '..string.format('%.0f',M.sequence)}
        for slot=2,4 do
            local row=rows[slot];local p=row.pad
            parts[#parts+1]=string.format('%d %.0f %d %d %d %d %d %d %d %d',slot,status.rows[slot].epoch,
                row.allow and 1 or 0,p.buttons,p.lt,p.rt,p.lx,p.ly,p.rx,p.ry)
        end
        -- The native reader validates the whole bounded record before accepting it.
        local f,err=io.open(dir..'party_ai_input.txt','wb')
        if not f then return false,tostring(err or 'Cannot open input packet') end
        local ok,wrote,writeError=pcall(f.write,f,table.concat(parts,'\n')..'\n')
        local closed,closeResult,closeError=pcall(f.close,f)
        if not ok then return false,tostring(wrote) end
        if not wrote then return false,tostring(writeError or 'Cannot write input packet') end
        if not closed then return false,tostring(closeResult) end
        if not closeResult then return false,tostring(closeError or 'Cannot close input packet') end
        return true
    end
    local function neutral(status)
        M.targetAssignments={}
        local rows={};for slot=2,4 do rows[slot]={pad=pad(),allow=false};resetSlot(slotState(slot)) end
        if status then pcall(writePacket,status,rows) end
    end
    function M.tick()
        if M.stopped then return end
        local status=readStatus()
        if not status then
            clearBanners();for _,s in pairs(M.slots)do s.autoFarSince=nil end
            return -- native watchdog releases output, preserving requested mode
        end
        if status.session~=lastSession then
            lastSession=status.session;M.sequence=status.accepted;lastTick=nil
            clearBanners()
            for slot=2,4 do resetSlot(slotState(slot)) end
            for _,s in pairs(M.slots)do s.autoNextAt=nil end
        end
        lastStatus=status
        local pc,p1=api.getPlayer1();local now=nowOf(pc)
        if lastTick and (now<lastTick or now-lastTick>0.5) then
            if now<lastTick then for _,s in pairs(M.slots)do s.autoNextAt=nil end end
            lastTick=now;clearBanners();neutral(status);return
        end
        lastTick=now
        local leader=valid(p1) and snapshot(p1) or nil
        local friends,friendlyActors,teammates,combatants={},{},{},{}
        if leader then friends[leader.id]=true;friendlyActors[1]=p1 end
        for slot=2,party.count do
            local p=party.states[slot] and party.states[slot].p2Pawn
            if valid(p) then
                friends[tostring(p:GetAddress())]=true;friendlyActors[#friendlyActors+1]=p
                local ok,a=pcall(snapshot,p)
                if ok and a then
                    a.slot=slot
                    local prior=slotState(slot);local row=status.rows[slot]
                    local sameActor=prior.identity==a.id and prior.epoch==row.epoch
                    a.target_id=row.enabled and sameActor and prior.enabled and prior.lastOutput and prior.lastOutput.target_id or nil
                    -- Make one coherent roster before any slot makes a decision.
                    -- Manual/not-ready/unmapped seats never reserve enemies.
                    local peer=party.partners[slot]
                    local readyOK,ready=false,false
                    if row.enabled and peer and type(peer.partyAIReady)=='function' then
                        readyOK,ready=pcall(peer.partyAIReady)
                    end
                    a.ai=row.enabled and readyOK and ready==true and sameActor
                        and leader~=nil and not leader.dead and leader.hp>0
                        and not a.dead and a.hp>0 and a.grounded
                        and party.loading~=true and party.inputLocked~=true
                        and now>=(prior.warmup or math.huge) and prior.policy.active==true
                        and now>=(prior.policy.arm_until or math.huge)
                    if a.ai then
                        local map=bindings(party.states[slot].p2Controller,prior,now)
                        a.ai=map.attack~=nil
                    end
                    if a.ai then combatants[#combatants+1]=a end
                    teammates[#teammates+1]=a
                end
            end
        end
        local any=false;for slot=2,party.count do if status.rows[slot].enabled then any=true end end
        local enemyList=any and leader and getEnemies(now,leader,friends) or {}
        local assignments=type(Policy.assignTargets)=='function' and Policy.assignTargets(combatants,leader,enemyList) or nil
        M.targetAssignments=assignments or {}
        local rows={}
        for slot=2,4 do
            local ok,p,allow=pcall(output,slot,status.rows[slot],now,leader,friends,friendlyActors,enemyList,teammates,assignments)
            if not ok then report('slot'..slot,'P'..slot..' paused after error: '..tostring(p));p,allow=pad(),false;resetSlot(slotState(slot)) end
            rows[slot]={pad=p,allow=allow}
        end
        local wrote,writeError=writePacket(status,rows)
        if not wrote then
            M.packetFailures=M.packetFailures+1;M.lastPacketError=writeError
            report('packet_io','Input packet deferred; native watchdog retained: '..tostring(writeError))
        else
            M.lastPacketError=nil
            -- A published pulse is not a hit or an animation acknowledgement.
            -- Commit once, only after packet I/O succeeds; repeated held samples
            -- and failed writes cannot manufacture attack feedback.
            for slot=2,4 do
                local s=slotState(slot);local pending=s.pendingAttack
                if pending and not s.publishedAttackDown then
                    local previous=s.feedback
                    local count=previous and previous.target_id==pending.target_id and previous.attack_count or 0
                    s.feedback={target_id=pending.target_id,attack_count=count+1,last_attack_at=pending.at}
                    s.submittedAttackId=pending.id
                end
                s.publishedAttackDown=pending~=nil
            end
        end
        updateBanners(status,pc,wrote)
    end
    function M.stop()
        if M.stopped then return end
        M.stopped=true;clearBanners();neutral(lastStatus)
    end
    function M.status()
        local out={tacticalVersion='2.3',session=lastSession,sequence=M.sequence,packetFailures=M.packetFailures,
            lastPacketError=M.lastPacketError,targetAssignments=M.targetAssignments,slots={}}
        for slot=2,4 do
            local s=M.slots[slot]
            if s then out.slots[#out.slots+1]={slot=slot,enabled=s.enabled,desired=s.enabled,ready=s.ready,mode=s.mode,
                blockReason=s.blockReason,epoch=s.epoch,mappings=s.mappings,lastOutput=s.lastOutput,bannerVisible=valid(s.banner),
                autoRegroup=s.autoLast,autoRegroupAfter=s.autoNextAt,feedback=s.feedback} end
        end
        return out
    end
    RegisterLoadMapPreHook(function()
        if M.stopped then return end
        clearBanners()
        mapEpoch=mapEpoch+1;enemyAt,enemies,lastTick=-1e9,{},nil;enemyActors={};neutral(lastStatus)
        for _,s in pairs(M.slots) do
            s.identity,s.mappings,s.autoNextAt=nil,{},nil
        end
    end)
    LoopInGameThreadWithDelay(50,function()
        if M.stopped then return true end
        local ok,err=pcall(M.tick)
        if not ok then clearBanners();neutral(lastStatus);report('tick',tostring(err)) end
        return false
    end)
    party.ai=M
    api.log('Party AI tactical v2.3 ready: P1 human; P2-P4 L3+RT hold4s. Immortal-companion offense; shared target allocation; local rules.')
    return M
end
