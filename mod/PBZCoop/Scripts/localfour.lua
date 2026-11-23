-- Four-seat adapter for PhantomPact's original localcoop.lua.
-- Gameplay/death/interactions stay in localcoop; this file owns seats and routing.
return function(api)
    local M, running = {}, false
    local valid, gs = api.valid, api.gs
    local party = {count=4, states={}, partners={}, medicines={}, rests={}, sits={}, bindings={}}
    local inputMode = 'four_pads'
    local function write(name, value)
        local f=assert(io.open(api.modDir()..name,'w')); f:write(value); f:close()
    end
    local function unroute() write('four_route.txt','0 -1\n0 -1\n0 -1\n0 -1\n'..party.count..'\n') end
    local function readBindings()
        local assigned={}
        local f=io.open(api.modDir()..'four_bindings.txt','r')
        if f then for line in f:lines() do assigned[#assigned+1]=tonumber(line) end; f:close() end
        if #assigned~=4 then
            for i=1,4 do assigned[i]=inputMode=='keyboard_three_pads' and (i==1 and 0 or i-1) or i end
        end
        party.bindings=assigned
    end
    function party.connected(slot) return (party.bindings[slot] or -1)>=0 end
    function party.ready()
        if party.loading then return false end
        local pc,pawn=api.getPlayer1()
        return valid(pc) and valid(pawn) and pawn:GetClass():GetFullName():find('BP_Renewal_Hun_')~=nil
    end
    -- PBZ CreatePlayer(true) runs single-player initialization for every local
    -- controller. Live PRE/POST trace (2026-11-19) proved that it clears the
    -- shared LastSaveActorID and replaces ReviveTransform with StartGameTransform.
    -- Preserve the current native checkpoint only across this synchronous call.
    -- Never cache it across maps or substitute a guessed/previous-save location.
    local function createSeatPreservingCheckpoint(pc,id)
        local system=FindFirstOf('PBZGameSystem')
        assert(valid(system),'Checkpoint subsystem unavailable; defer additional player creation')
        local systemAt,systemName=system:GetAddress(),system:GetFullName()
        local host=pc.Pawn
        assert(valid(host),'Host unavailable before additional player creation')
        local hostAt,hostName=host:GetAddress(),host:GetFullName()
        local function number(v)assert(type(v)=='number'and v==v and math.abs(v)<1e12,'Invalid checkpoint number');return v end
        local function vector(v)return {X=number(v.X),Y=number(v.Y),Z=number(v.Z)}end
        local t,r=system.ReviveTransform,system.ReviveCameraRotation
        local saved={transform={Translation=vector(t.Translation),Scale3D=vector(t.Scale3D),
            Rotation={X=number(t.Rotation.X),Y=number(t.Rotation.Y),Z=number(t.Rotation.Z),W=number(t.Rotation.W)}},
            camera={Pitch=number(r.Pitch),Yaw=number(r.Yaw),Roll=number(r.Roll)},
            actor=system.LastSaveActorID:ToString(),locked=system.bSaveActorLocked}
        assert(type(saved.actor)=='string'and type(saved.locked)=='boolean','Invalid native checkpoint metadata')
        local ok,created=pcall(function()return gs():CreatePlayer(pc,id,true)end)
        local current=FindFirstOf('PBZGameSystem')
        local currentPc,currentHost=api.getPlayer1()
        assert(valid(current)and current:GetAddress()==systemAt and current:GetFullName()==systemName
            and valid(currentPc)and currentPc:GetAddress()==pc:GetAddress()
            and valid(currentHost)and currentHost:GetAddress()==hostAt and currentHost:GetFullName()==hostName,
            'World/host changed during additional player creation; stale checkpoint was not restored')
        -- These are runtime properties. No save/checkpoint activation/teleport API.
        current.ReviveTransform=saved.transform
        current.ReviveCameraRotation=saved.camera
        current.LastSaveActorID=FName(saved.actor)
        current.bSaveActorLocked=saved.locked
        local restored=current.ReviveTransform
        local function sameVec(a,b)return math.abs(a.X-b.X)<.01 and math.abs(a.Y-b.Y)<.01 and math.abs(a.Z-b.Z)<.01 end
        assert(sameVec(restored.Translation,saved.transform.Translation)
            and sameVec(restored.Scale3D,saved.transform.Scale3D)
            and sameVec(restored.Rotation,saved.transform.Rotation)
            and math.abs(restored.Rotation.W-saved.transform.Rotation.W)<.0001
            and current.LastSaveActorID:ToString()==saved.actor
            and current.bSaveActorLocked==saved.locked,'Native checkpoint restoration failed')
        local c=current.ReviveCameraRotation
        assert(math.abs(c.Pitch-saved.camera.Pitch)<.01 and math.abs(c.Yaw-saved.camera.Yaw)<.01
            and math.abs(c.Roll-saved.camera.Roll)<.01,'Checkpoint camera restoration failed')
        api.log('LocalFour checkpoint preserved across CreatePlayer P'..(id+1)..' save='..saved.actor)
        if not ok then error(created)end
        return created
    end
    local function seat(slot)
        local state=party.states[slot]
        if valid(state.p2Controller) then return state.p2Controller end
        local pc=api.getPlayer1()
        local viewport=FindFirstOf('GameViewportClient')
        assert(valid(pc) and valid(viewport),'No viewport for party seat')
        viewport.MaxSplitscreenPlayers=4
        local added=gs():GetPlayerController(pc,slot-1)
        if not valid(added) then added=createSeatPreservingCheckpoint(pc,slot-1) end
        assert(valid(added),'CreatePlayer failed for '..slot)
        state.p2Controller=added
        added:SetActorTickEnabled(true)
        return added
    end
    local function spawn(slot, class)
        local state=party.states[slot]
        if party.loading or valid(state.p2Pawn) then return end
        unroute()
        local pc=seat(slot)
        -- Retain a failed attempt: retry possession, never allocate a new Soul
        -- every tick while the controller refuses it.
        local pending=state.pendingSpawn
        if pending and pending.controller~=pc then
            if valid(pending.pawn) then pending.pawn:K2_DestroyActor() end
            state.pendingSpawn=nil;pending=nil
        end
        if not pending or not valid(pending.pawn) then
            pending={controller=pc,old=pc.Pawn,pawn=api.spawnBesidePlayer1(class)}
            state.pendingSpawn=pending
        end
        local soul=pending.pawn
        assert(valid(soul),'Pawn creation failed for '..slot)
        local old=pending.old
        if not valid(pc.Pawn) or pc.Pawn:GetAddress()~=soul:GetAddress() then pc:Possess(soul) end
        assert(valid(pc.Pawn) and pc.Pawn:GetAddress()==soul:GetAddress(),'Possess did not assign player '..slot)
        state.p2Pawn=soul
        state.pendingSpawn=nil
        if valid(old) and old:GetAddress()~=soul:GetAddress() then
            local ok,err=pcall(function()old:K2_DestroyActor()end)
            if not ok then api.log('Old spawn pawn cleanup failed P'..slot..': '..tostring(err)) end
        end
        api.log('LocalFour upstream: player '..slot..' possessed')
    end
    local function remove(slot)
        local state=party.states[slot]
        local pc,pending=state.p2Controller,state.pendingSpawn
        -- Invalidate references even if unroute or engine removal throws.
        state.p2Controller,state.p2Pawn=nil,nil
        state.pendingSpawn=nil
        local errors={}
        local function attempt(fn)local ok,err=pcall(fn);if not ok then errors[#errors+1]=tostring(err)end end
        attempt(unroute)
        if pending and valid(pending.pawn) then attempt(function()pending.pawn:K2_DestroyActor()end) end
        if valid(pc) then attempt(function()gs():RemovePlayer(pc,true)end) end
        if #errors>0 then error(table.concat(errors,'; ')) end
    end
    local function fanout(callbacks,...)
        for i=2,party.count do
            if callbacks[i] then
                local ok,err=pcall(callbacks[i],...)
                if not ok then api.log('Party callback P'..i..': '..tostring(err)) end
            end
        end
    end
    local function dispatchRest(kind)
        if party.loading then return end
        if kind=='death' then party.regroupPending=true; party.recoveredAfter=nil end
        fanout(party.rests,kind)
    end
    local function dispatchSit() if not party.loading then fanout(party.sits) end end
    -- One medicine hook, one selected partner, no nested host-controller swaps.
    local medicineOwner
    local function medicineCounted(id)
        medicineOwner=nil
        if party.loading then return end
        for i=2,party.count do
            local m=party.medicines[i]
            if m and m.wants() then medicineOwner=m; break end
        end
        if medicineOwner then medicineOwner.counted(id) end
    end
    local function medicineBefore() if medicineOwner then medicineOwner.before() end end
    local function medicineAfter()
        local owner=medicineOwner; medicineOwner=nil
        if owner then owner.after() end
    end
    local function ensure()
        if party.loading then return end
        readBindings()
        local pc,pawn=api.getPlayer1()
        if not(valid(pc) and valid(pawn)) or not pawn:GetClass():GetFullName():find('BP_Renewal_Hun_') then return end
        local viewport=FindFirstOf('GameViewportClient')
        if not valid(viewport) then return end
        viewport.MaxSplitscreenPlayers=4
        local maps=StaticFindObject('/Script/EngineSettings.Default__GameMapsSettings')
        maps.FourPlayerSplitscreenLayout=1; maps.TwoPlayerSplitscreenLayout=1; maps.ThreePlayerSplitscreenLayout=2
        api.setGamepadOffset(false)
        local players={pc}
        for i=2,party.count do
            local state=party.states[i]
            if not valid(state.p2Controller) or not valid(state.p2Pawn) then unroute(); return end
            players[i]=state.p2Controller
        end
        local route,report={"0 -1","0 -1","0 -1","0 -1"},{}
        for i=1,party.count do
            gs():SetPlayerControllerID(players[i],i-1)
            route[i]=string.format('%d %d',players[i].Player:GetAddress(),party.bindings[i])
            report[i]=string.format('P%d controller=%d pawn=%s',i,i-1,players[i].Pawn:GetFullName())
        end
        gs():SetForceDisableSplitscreen(pc,false)
        write('vp.txt',string.format('%d %d\n',viewport:GetAddress(),maps:GetAddress()+93))
        write('four_route.txt',table.concat(route,'\n')..'\n'..party.count..'\n')
        write('screens.txt',({[2]='party2',[3]='three',[4]='four'})[party.count]..'\n')
        write('four_status.txt',table.concat(report,'\n'))
        api.game.hookMedicine(medicineCounted,medicineBefore,medicineAfter)
    end
    function M.start(mode,count)
        if running then return end
        party.count=tonumber(count) or 4; assert(party.count>=2 and party.count<=4 and party.count%1==0,'Invalid player count'); running=true; inputMode=mode or 'four_pads'
        os.remove(api.modDir()..'four_actions.txt') -- never replay a previous game's commands
        assert(inputMode=='four_pads' or inputMode=='keyboard_three_pads','Invalid LocalInput')
        unroute(); readBindings()
        local factory=dofile(api.modDir()..'Scripts/localcoop.lua')
        local interactions=dofile(api.modDir()..'Scripts/local_interactions.lua')(valid,RegisterHook,api.log)
        for i=2,party.count do
            local slot=i
            party.states[slot]={}
            local adapter=setmetatable({state=party.states[slot],party=party,partySlot=slot}, {__index=api})
            adapter.log=function(message) api.log('[P'..slot..'] '..message) end
            adapter.spawnPawnForPlayer2=function(class) spawn(slot,class) end
            adapter.removePlayer2=function() remove(slot) end
            adapter.claimInteraction=function(thing)return interactions.claim(slot,thing)end
            adapter.releaseInteraction=function()interactions.release(slot)end
            adapter.hookInteraction=function(path,before,after)interactions.hook(slot,path,before,after)end
            adapter.game=setmetatable({}, {__index=api.game})
            adapter.game.hookRest=function(callback)
                party.rests[slot]=callback
                return api.game.hookRest(dispatchRest)
            end
            adapter.game.hookSit=function(callback)
                party.sits[slot]=callback
                return api.game.hookSit(dispatchSit)
            end
            party.partners[slot]=factory(adapter)
            if slot==2 then api.localcoop=party.partners[slot] end
            party.partners[slot].start(party.count,party.count)
        end
        -- Original map hooks run first, preserving dust/gauges and removing seats.
        RegisterLoadMapPreHook(function()
            party.loading=true
            interactions.clear()
            party.downSince,party.hostAddress,party.regroupPending,party.recoveredAfter=nil,nil,nil,nil
            party.optimizationHolds=nil
            medicineOwner=nil
            local ok,err=pcall(unroute);if not ok then api.log('Map unroute failed: '..tostring(err))end
            ok,err=pcall(write,'screens.txt','one\n');if not ok then api.log('Map screens reset failed: '..tostring(err))end
        end)
        RegisterLoadMapPostHook(function() party.loading=false end)
        LoopInGameThreadWithDelay(500,function()
            local ok,err=pcall(ensure)
            if not ok then unroute(); api.log('LocalFour adapter: '..tostring(err)) end
            return false
        end)
        api.log('LocalFour: original PhantomPact partner lifecycle x3; existing device routing preserved')
        dofile(api.modDir()..'Scripts/party_controls.lua')(api,party)
        dofile(api.modDir()..'Scripts/party_weapons.lua')(api,party)
        dofile(api.modDir()..'Scripts/dialog_guard.lua')(api)
        dofile(api.modDir()..'Scripts/party_ai.lua')(api,party)
        dofile(api.modDir()..'Scripts/party_recovery.lua')(api,party)
    end
    function M.regroup()
        for i=2,party.count do if party.partners[i] then party.partners[i].partyRegroup() end end
    end
    return M
end

