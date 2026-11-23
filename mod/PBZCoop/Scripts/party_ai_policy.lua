-- Companion policy V2.3: pure local decisions, no engine/model/network calls.
-- API preserved: new(slot), reset(state), step(state,snapshot,nowSeconds).
-- Positions in cm; yaw in degrees. snap.friends is an ARRAY of positioned actors,
-- optionally carrying hp/max_hp, slot and their previous-tick target_id. leader.yaw
-- sets formation orientation. Enemy optional target_id, vx/vy and attacking=true
-- must be observed facts; an arbitrary active montage is NOT an attack signal.
-- snap.capabilities optionally declares attack/block/dodge. Omitted capabilities
-- keep legacy intentions; explicit false removes the corresponding intention.
-- Outputs preserve move_x/y,look_yaw,target_id,attack/block/dodge,mode/reason;
-- role,decision,phase,target_score explain the selected tactic. Combat reason stays
-- 'assist' for the adapter's pulse-latch contract. No pathfinding/heal/teleport.
-- Optional verified capsule radius adjusts combat geometry only. Enemy yaw can
-- orient flank sectors. feedback={target_id,attack_count,last_attack_at} counts
-- adapter-approved NEW button pulses, not held samples, accepted moves or hits.
-- HP/posture decrease is shared target progress, never attributed to this actor.
-- player.posture/max_posture is observed ShaChi, not a generic stamina model.
-- Simultaneous light+guard requires capabilities.guard_attack==true. Guard time,
-- reserve ratios and critical-health withdrawal are initial tuning choices;
-- none are claimed to be game-authored move timings or red/black-attack detectors.
-- aggressive=true is this user's immortal-companion play mode, not a health or
-- invulnerability modification. Lifecycle checks still suspend invalid actors.
-- assignment_active=true makes a shared, same-tick target plan authoritative.
local M = {version=2.3}
-- TARGET_ASSIGNMENTS_BEGIN
local TargetAssignments=(function()
-- Stateless assignment for at most P2/P3/P4 (Lua 5.3+).
-- assign({{slot=2,candidates={{id=...,score=...},...}},...}) -> {[slot]=id}
-- Scores must be finite and within [-1e6,1e6]. Quantize to 0.001, rounding ties
-- away from zero; all comparisons use these integer scores (sum <= 3e9).
-- Stage 1: maximum distinct-target coverage, then maximum quantized score of unique
-- assignments. Stage 2: fill remaining reachable slots by least current target
-- load, then score. This does NOT claim maximum total score after stage 2.
-- Ties use ascending slot, then id type and canonical string; absent sorts last.
-- Untrusted input: dense arrays only; >3 rows rejects input; >128 candidates
-- rejects that row. Repeated slots merge, repeated IDs retain their best finite
-- score; a merged slot with >128 distinct IDs is rejected. Metatables are rejected.
-- Complexity: O(U * 2^3 * 3), U <= 384, plus canonical sorting. No N^3 search.
local M={version=1}
local MAX_ROWS,MAX_CANDIDATES=3,128
local function finite(x)return type(x)=='number' and x==x and x~=math.huge and x~=-math.huge end
local function plain(t)return type(t)=='table' and getmetatable(t)==nil end
local function arrayLength(t,limit)
    if not plain(t)then return nil end
    local n=0
    for k in pairs(t)do
        n=n+1
        if n>limit or type(k)~='number' or k%1~=0 or k<1 or k>limit then return nil end
    end
    for i=1,n do if rawget(t,i)==nil then return nil end end
    return n
end
local function canonical(id)
    if type(id)=='string' and #id>0 then return id,'string:'..id end
    if finite(id)then
        local integer=math.tointeger and math.tointeger(id)
        if integer then return integer,'number:'..string.format('%d',integer)end
        if id==0 then id=0 end -- normalize negative zero on number-only runtimes.
        return id,'number:'..string.format('%.17g',id)
    end
    return nil,nil
end
local function better(a,b,targetCount)
    if not b then return true end
    if a.sum~=b.sum then return a.sum>b.sum end
    for i=1,3 do
        local left=a.ids[i]~=0 and a.ids[i] or targetCount+1
        local right=b.ids[i]~=0 and b.ids[i] or targetCount+1
        if left~=right then return left<right end
    end
    return false
end
local function extend(state,slotIndex,targetIndex,score)
    local nextState={ids={state.ids[1],state.ids[2],state.ids[3]},
        sum=state.sum+score}
    nextState.ids[slotIndex]=targetIndex
    return nextState
end
local function normalize(rows)
    local count=arrayLength(rows,MAX_ROWS);if not count then return {} end
    local bySlot={}
    for i=1,count do
        local row=rows[i]
        if plain(row)then
            local slot=row.slot
            if finite(slot) and slot%1==0 and slot>=2 and slot<=4 then
                local length=arrayLength(row.candidates,MAX_CANDIDATES)
                if length then
                    local merged=bySlot[slot] or {};bySlot[slot]=merged
                    for j=1,length do
                        local candidate=row.candidates[j]
                        if plain(candidate) and finite(candidate.score) and candidate.score>=-1e6 and candidate.score<=1e6 then
                            local id,key=canonical(candidate.id)
                            if key then
                                local score=candidate.score>=0 and math.floor(candidate.score*1000+0.5)
                                    or -math.floor(-candidate.score*1000+0.5)
                                local previous=merged[key]
                                if not previous or score>previous.score then
                                    merged[key]={id=id,key=key,score=score}
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    local byId={}
    for slot=2,4 do
        local merged=bySlot[slot];local size=0
        if merged then for _ in pairs(merged)do size=size+1 end end
        if size<=MAX_CANDIDATES and merged then
            for key,candidate in pairs(merged)do
                local target=byId[key]
                if not target then target={id=candidate.id,key=key,scores={}};byId[key]=target end
                target.scores[slot-1]=candidate.score
            end
        end
    end
    local targets={};for _,target in pairs(byId)do targets[#targets+1]=target end
    table.sort(targets,function(a,b)return a.key<b.key end)
    return targets
end
function M.assign(rows)
    local targets=normalize(rows);local count=#targets
    if count==0 then return {} end
    local bits={1,2,4};local popcount={ [0]=0,1,1,2,1,2,2,3 }
    local states={[0]={ids={0,0,0},sum=0}}
    for targetIndex,target in ipairs(targets)do
        local nextStates={}
        for mask=0,7 do nextStates[mask]=states[mask]end
        for mask=0,7 do
            local state=states[mask]
            if state then
                for slotIndex=1,3 do
                    local score=target.scores[slotIndex];local bit=bits[slotIndex]
                    if score~=nil and math.floor(mask/bit)%2==0 then
                        local nextState=extend(state,slotIndex,targetIndex,score)
                        local nextMask=mask+bit
                        if better(nextState,nextStates[nextMask],count)then nextStates[nextMask]=nextState end
                    end
                end
            end
        end
        states=nextStates
    end
    local best,bestCoverage=nil,-1
    for mask=0,7 do
        local state=states[mask];local coverage=popcount[mask]
        if state and (coverage>bestCoverage or coverage==bestCoverage and better(state,best,count))then
            best,bestCoverage=state,coverage
        end
    end
    local assigned,loads={},{}
    for slotIndex=1,3 do
        local targetIndex=best.ids[slotIndex]
        if targetIndex~=0 then assigned[slotIndex]=targetIndex;loads[targetIndex]=(loads[targetIndex] or 0)+1 end
    end
    -- A maximum matching leaves no reachable unused target for an unmatched slot.
    -- Fill those slots in stable player order, balancing only their valid choices.
    for slotIndex=1,3 do
        if not assigned[slotIndex]then
            local chosen,chosenLoad,chosenScore
            for targetIndex,target in ipairs(targets)do
                local score=target.scores[slotIndex]
                if score~=nil then
                    local load=loads[targetIndex] or 0
                    if not chosen or load<chosenLoad or load==chosenLoad and score>chosenScore then
                        chosen,chosenLoad,chosenScore=targetIndex,load,score
                    end
                end
            end
            if chosen then assigned[slotIndex]=chosen;loads[chosen]=(loads[chosen] or 0)+1 end
        end
    end
    local output={}
    for slotIndex=1,3 do
        if assigned[slotIndex]then output[slotIndex+1]=targets[assigned[slotIndex]].id end
    end
    return output
end
return M
end)()
-- TARGET_ASSIGNMENTS_END
local atan2 = math.atan2 or function(y,x) return math.atan(y,x) end
local C = {
    ARM_SECONDS=0.15,MAX_STEP_GAP=0.5,MAX_STATE_AGE=0.25,
    FOLLOW_START=150,FOLLOW_STOP=70,LEASH=1200,ACQUIRE_RANGE=900,RETAIN_RANGE=1100,
    ENEMY_LEASH=1200,MAX_HEIGHT=250,ATTACK_RANGE=180,DEFEND_RANGE=300,
    DEFEND_SECONDS=0.45,DODGE_INTERVAL=1.2,LOW_HEALTH=0.28,RECOVER_HEALTH=0.45,
    STUCK_SECONDS=2,STUCK_PROGRESS=25,STUCK_WAIT=1,MAX_ENEMIES=128,
    FRIEND_SPACE=140,DAMAGE_MEMORY=2.5,
    FEEDBACK_MIN_PULSES=3,FEEDBACK_SPAN=1.6,FEEDBACK_MAX_AGE=1.25,
    REPOSITION_SECONDS=0.65,
    GUARD_ENTER=0.50,GUARD_LEAVE=0.25,GUARD_HOLD=0.65,GUARD_RELEASE=0.35,
    UNKNOWN_GUARD_HOLD=0.25,UNKNOWN_GUARD_RELEASE=0.85,
    CRITICAL_HEALTH=0.12,CRITICAL_WITHDRAW=0.65,CRITICAL_INTERVAL=2.0,
}
M.constants=C
local ROLES={
    [2]={name='guard',back=210,side=-160,ring=140,angle=0,burst=2,interval=0.42,pressure=0.8},
    [3]={name='flank',back=330,side=220,ring=150,angle=95,burst=3,interval=0.34,pressure=2.3},
    [4]={name='support',back=420,side=-220,ring=165,angle=-75,burst=2,interval=0.46,pressure=1.7},
}
local function finite(x)return type(x)=='number' and x==x and math.abs(x)<math.huge end
local function idok(id)return (type(id)=='string' and #id>0) or (finite(id) and id>0) end
local function position(p)
    return type(p)=='table' and idok(p.id) and finite(p.x) and finite(p.y) and finite(p.z)
        and math.abs(p.x)<=1e12 and math.abs(p.y)<=1e12 and math.abs(p.z)<=1e12
end
local function list(v)return type(v)=='table' and v or {} end
local function dist(a,b)local x,y=a.x-b.x,a.y-b.y;return math.sqrt(x*x+y*y)end
local function clamp(x,a,b)return math.max(a,math.min(b,x))end
local function meleeRange(p,e)
    if finite(p.radius) and finite(e.radius) and p.radius>0 and e.radius>0 then
        return math.max(C.ATTACK_RANGE,math.min(420,p.radius+e.radius+70))
    end
    return C.ATTACK_RANGE
end
local function unit(x,y)
    local n=math.sqrt(x*x+y*y);if n<0.001 then return 0,0 end;return x/n,y/n
end
local function neutral(mode,reason)
    return {move_x=0,move_y=0,attack=false,block=false,dodge=false,mode=mode or 'waiting',reason=reason or 'idle'}
end
local function clear(s)local slot=s.slot;for k in pairs(s)do s[k]=nil end;s.slot=slot end
function M.new(slot)return {slot=slot}end
function M.reset(s)assert(type(s)=='table','policy state must be a table');clear(s)end
local function stop(s,reason)clear(s);return neutral('suspended',reason)end
local function can(snap,kind)
    return type(snap.capabilities)~='table' or snap.capabilities[kind]~=false
end
local function face(out,p,t)
    if dist(p,t)>0.001 then out.look_yaw=math.deg(atan2(t.y-p.y,t.x-p.x)) end
end
local function move(out,p,t,speed)
    local x,y=unit(t.x-p.x,t.y-p.y);out.move_x,out.move_y=x*speed,y*speed;face(out,p,t)
end
local function friendSet(snap)
    local set={[snap.player.id]=true,[snap.leader.id]=true}
    for _,id in ipairs(list(snap.friend_ids))do if idok(id)then set[id]=true end end
    for _,a in ipairs(list(snap.friends))do if position(a)then set[a.id]=true end end
    return set
end
local function allies(snap)
    local all,seen={snap.leader},{[snap.leader.id]=true}
    for _,a in ipairs(list(snap.friends))do
        if position(a) and a.id~=snap.player.id and not seen[a.id] and not a.dead and (a.hp==nil or finite(a.hp) and a.hp>0) then
            seen[a.id]=true;all[#all+1]=a
        end
    end
    return all
end
local function rememberDamage(s,snap,now)
    s.friend_hp,s.hurt=s.friend_hp or {},s.hurt or {}
    for _,a in ipairs(allies(snap))do
        if finite(a.hp) and a.hp>0 then
            if s.friend_hp[a.id] and a.hp<s.friend_hp[a.id]-0.01 then s.hurt[a.id]=now+C.DAMAGE_MEMORY end
            s.friend_hp[a.id]=a.hp
        end
    end
    for id,untilAt in pairs(s.hurt)do if now>=untilAt then s.hurt[id]=nil end end
end
local function closing(p,e)
    if not finite(e.vx) or not finite(e.vy) or math.abs(e.vx)>10000 or math.abs(e.vy)>10000 then return 0 end
    local x,y=unit(p.x-e.x,p.y-e.y);return e.vx*x+e.vy*y
end
local function pressure(snap,id)
    local count=0
    for _,a in ipairs(list(snap.friends))do
        if position(a) and a.id~=snap.player.id and a.id~=snap.leader.id and not a.dead
            and (a.hp==nil or finite(a.hp) and a.hp>0) and a.target_id==id then count=count+1 end
    end
    return count
end
local function choose(s,snap,now,role)
    local p,leader=snap.player,snap.leader
    local friends,all=friendSet(snap),allies(snap)
    local best,score,bestInfo,nearCount=nil,-math.huge,nil,0
    local current,currentScore,currentInfo
    for i,e in ipairs(list(snap.enemies))do
        if i>C.MAX_ENEMIES then break end
        if position(e) and e.hostile==true and not e.dead and e.attackable~=false and e.visible~=false
            and finite(e.hp) and e.hp>0 and not friends[e.id] and math.abs(e.z-p.z)<=C.MAX_HEIGHT
            and math.abs(e.z-leader.z)<=C.MAX_HEIGHT and dist(e,leader)<=C.ENEMY_LEASH then
            local d=dist(e,p)
            local range=meleeRange(p,e);local extra=range-C.ATTACK_RANGE
            if d<=260+extra then nearCount=nearCount+1 end
            if d<=(e.id==s.target_id and C.RETAIN_RANGE or C.ACQUIRE_RANGE)
                and (snap.assignment_active~=true or e.id==snap.assigned_target_id) then
                local hostDistance=dist(e,leader)
                local urgent=(e.target_id==leader.id and 5 or 0)
                local why=e.target_id==leader.id and 'protect_leader' or 'nearby_hostile'
                local threat=3-d/600+math.max(0,1-hostDistance/650)*(role.name=='guard' and 5 or 3)
                if friends[e.target_id] then threat=threat+2 end
                for _,a in ipairs(all)do
                    if s.hurt[a.id] and dist(a,e)<400 then
                        urgent=urgent+4*(1-dist(a,e)/800);why='protect_injured_ally'
                    end
                end
                if e.attacking==true and (d<C.DEFEND_RANGE+extra or friends[e.target_id])then threat=threat+2 end
                if closing(p,e)>160 and d<450+extra then threat=threat+1.5 end
                -- Finish a nearby weakened hostile, while leaving host/ally danger
                -- higher priority. Unknown maximum health never invents this bonus.
                if finite(e.max_hp) and e.max_hp>0 and e.hp/e.max_hp<=0.25 and d<=350+extra then
                    threat=threat+1+4*(0.25-clamp(e.hp/e.max_hp,0,0.25))
                    if urgent==0 then why='finish_weakened_hostile' end
                end
                local load=pressure(snap,e.id)
                if snap.assignment_active==true then
                    load=0
                    for slot,id in pairs(type(snap.assignments)=='table' and snap.assignments or {})do
                        if slot~=s.slot and id==e.id then load=load+1 end
                    end
                    why=load==0 and 'assigned_single_target' or 'assigned_focus_fire'
                end
                threat=threat+urgent-load*role.pressure+(e.id==s.target_id and 0.8 or 0)
                if urgent==0 and e.id==s.failed_target_id and now<(s.failed_until or 0) then threat=threat-1.6 end
                if load==0 and role.name~='guard' and urgent==0 and why=='nearby_hostile' then why='share_targets' end
                local info={distance=d,range=range,pressure=load,urgent=urgent,why=why}
                if e.id==s.target_id then current,currentScore,currentInfo=e,threat,info end
                if threat>score then best,score,bestInfo=e,threat,info end
            end
        end
    end
    if current and best and best.id~=current.id then
        -- Previous-tick shared targets otherwise make all three actors switch in
        -- lockstep. Stagger commitment by slot and require a useful improvement.
        -- A newly urgent host/ally threat, or invalid current target, bypasses it.
        local emergency=bestInfo.urgent>currentInfo.urgent+1
        local committed=now<(s.target_since or now)+0.55+(s.slot-2)*0.13
            or now<(s.reposition_until or 0)
        if not emergency and (committed or score-currentScore<0.65) then
            return current,currentScore,currentInfo,nearCount
        end
    end
    return best,score,bestInfo,nearCount
end
-- One shared assignment per adapter tick. Each row contains only in-range,
-- observed hostile actors; geometry probes still decide actual movement/hits.
function M.assignTargets(actors,leader,enemies)
    if not position(leader) or leader.dead or not finite(leader.hp) or leader.hp<=0 then return {} end
    local friends={[leader.id]=true}
    for _,a in ipairs(list(actors))do if position(a)then friends[a.id]=true end end
    local rows={}
    for _,a in ipairs(list(actors))do
        if position(a) and ROLES[a.slot] and a.id~=leader.id and not a.dead
            and finite(a.hp) and a.hp>0 and finite(a.max_hp) and a.max_hp>0
            and a.grounded==true and dist(a,leader)<=C.LEASH and math.abs(a.z-leader.z)<=C.MAX_HEIGHT then
            local candidates={}
            for i,e in ipairs(list(enemies))do
                if i>C.MAX_ENEMIES then break end
                if position(e) and e.hostile==true and not e.dead and e.attackable~=false and e.visible~=false
                    and finite(e.hp) and e.hp>0 and not friends[e.id]
                    and math.abs(e.z-a.z)<=C.MAX_HEIGHT and math.abs(e.z-leader.z)<=C.MAX_HEIGHT
                    and dist(e,leader)<=C.ENEMY_LEASH then
                    local d=dist(a,e)
                    if d<=(e.id==a.target_id and C.RETAIN_RANGE or C.ACQUIRE_RANGE) then
                        -- A continuing engagement has a modest travel advantage.
                        -- Host protection is a score, never an all-slots override.
                        local score=30-d/25+(e.id==a.target_id and 8 or 0)
                            +(e.target_id==leader.id and (a.slot==2 and 5 or 3) or 0)
                            +(e.target_id==a.id and 2 or 0)+(d<=meleeRange(a,e) and 3 or 0)
                        candidates[#candidates+1]={id=e.id,score=score}
                    end
                end
            end
            rows[#rows+1]={slot=a.slot,candidates=candidates}
        end
    end
    return TargetAssignments.assign(rows)
end
local function formation(role,leader)
    local yaw=finite(leader.yaw) and math.rad(leader.yaw) or 0
    return {x=leader.x-math.cos(yaw)*role.back-math.sin(yaw)*role.side,
        y=leader.y-math.sin(yaw)*role.back+math.cos(yaw)*role.side,z=leader.z}
end
local function spacing(out,snap)
    local p=snap.player
    local x,y=0,0
    for _,a in ipairs(allies(snap))do
        if math.abs(a.z-p.z)<=C.MAX_HEIGHT then
            local d=dist(p,a)
            if d<C.FRIEND_SPACE then
                local dx,dy=unit(p.x-a.x,p.y-a.y)
                if d<0.001 then
                    dx,dy=unit(out.move_x,out.move_y)
                    if dx==0 and dy==0 then
                        dx,dy=unit(-1,out.role=='flank' and 0.8 or out.role=='support' and -0.9 or -0.4)
                    end
                end
                local strength=(C.FRIEND_SPACE-d)/C.FRIEND_SPACE
                x,y=x+dx*strength,y+dy*strength
            end
        end
    end
    if x*x+y*y>0.01 then
        local mx,my=out.move_x+x*0.4,out.move_y+y*0.4
        local n=math.sqrt(mx*mx+my*my);local scale=n>0.8 and 0.8/n or 1
        out.move_x,out.move_y=mx*scale,my*scale
        return true
    end
    return false
end
local function follow(s,snap,out,force,role)
    local p,leader=snap.player,snap.leader
    if math.abs(p.z-leader.z)>C.MAX_HEIGHT then out.mode,out.reason='blocked','different_height';return end
    local goal=formation(role,leader)
    -- Beyond the leash take the direct return first, then settle into formation.
    if force then goal=leader end
    local d=dist(p,goal)
    if d>=C.FOLLOW_START then s.following=true end
    if d<=C.FOLLOW_STOP then s.following=false end
    out.mode,out.reason,out.decision,out.phase='following','leader','formation_'..role.name,'formation'
    if s.following then move(out,p,goal,d>500 and 0.78 or 0.55)
    else out.mode,out.reason='waiting','in_formation' end
    if spacing(out,snap) and out.mode=='waiting' then out.mode,out.decision='following','give_allies_space' end
end
local function escape(s,now,out)
    local elapsed=now-s.escape_at
    out.mode,out.reason,out.phase='blocked','no_progress','unstuck'
    if s.escape_attempt>3 then out.decision='wait_for_route';return elapsed<3 end
    if elapsed<0.25 then
        out.move_x,out.move_y=-s.escape_x*0.4,-s.escape_y*0.4;out.decision='unstuck_backstep'
    elseif elapsed<0.7 then
        local side=((s.slot+s.escape_attempt)%2==0) and 1 or -1
        out.move_x,out.move_y=-s.escape_y*side*0.45,s.escape_x*side*0.45;out.decision='unstuck_sidestep'
    elseif elapsed<1.0 then out.decision='unstuck_wait'
    else return false end
    return true
end
local function progress(s,p,now,out)
    local moving=out.move_x*out.move_x+out.move_y*out.move_y>=0.01
    if not moving then s.progress_at=nil;return out end
    if not s.progress_at then s.progress_at,s.progress_x,s.progress_y=now,p.x,p.y
    elseif dist(p,{x=s.progress_x,y=s.progress_y})>=C.STUCK_PROGRESS then
        s.progress_at,s.progress_x,s.progress_y=now,p.x,p.y;s.escape_attempt=0
    elseif now-s.progress_at>=C.STUCK_SECONDS then
        s.escape_at,s.escape_x,s.escape_y=now,unit(out.move_x,out.move_y)
        s.escape_attempt=(s.escape_attempt or 0)+1;s.progress_at=nil
        local role=out.role;out=neutral('blocked','no_progress');out.role=role;escape(s,now,out)
    end
    return out
end
local function combatGoal(role,e,leader,range)
    local base=role.name~='guard' and finite(e.yaw) and math.rad(e.yaw)
        or atan2(leader.y-e.y,leader.x-e.x)
    local a=base+math.rad(role.angle)
    local ring=role.ring+range-C.ATTACK_RANGE
    return {x=e.x+math.cos(a)*ring,y=e.y+math.sin(a)*ring,z=e.z},a,ring
end
local function resourceRatio(p)
    if finite(p.posture) and p.posture>=0 and finite(p.max_posture) and p.max_posture>0 then
        return clamp(p.posture/p.max_posture,0,1)
    end
    return nil
end
local function releaseGuard(s,now)
    if s.guard_until then
        local rest=s.guard_unknown and C.UNKNOWN_GUARD_RELEASE or C.GUARD_RELEASE
        s.next_guard=math.max(s.next_guard or 0,now+rest)
        s.guard_until=nil
    end
end
local function guardOverlay(s,snap,now,resource,wanted,hardPressure,combined)
    if resource~=nil then
        if resource<=C.GUARD_LEAVE then s.guard_reserved=true
        elseif resource>=C.GUARD_ENTER then s.guard_reserved=false end
    end
    if not wanted or not can(snap,'block') or s.guard_reserved then releaseGuard(s,now);return false end
    -- In fallback serial mode, never cancel an in-flight light-button pulse to
    -- insert guard. Reliable distinct mappings are required for the combined mode.
    if not combined and now<(s.last_light_intent or -1e9)+0.16 then return false end
    if s.guard_until then
        if resource==nil and not s.guard_unknown then
            s.guard_unknown=true;s.guard_until=math.min(s.guard_until,now+C.UNKNOWN_GUARD_HOLD)
        end
        if now<s.guard_until then return true end
        local rest=s.guard_unknown and C.UNKNOWN_GUARD_RELEASE or C.GUARD_RELEASE
        s.next_guard=math.max(s.next_guard or 0,s.guard_until+rest);s.guard_until=nil
    end
    if now<(s.next_guard or -1e9) then return false end
    if resource~=nil and resource>=C.GUARD_ENTER then
        s.guard_unknown=false;s.guard_until=now+C.GUARD_HOLD;return true
    elseif resource==nil and hardPressure then
        s.guard_unknown=true;s.guard_until=now+C.UNKNOWN_GUARD_HOLD;return true
    end
    return false
end
local function resetFeedback(s,f,target)
    s.feedback_watch={target_id=target.id,count=f.attack_count,hp=target.hp,
        posture=finite(target.posture) and target.posture>=0 and target.posture or nil,pulses=0}
    return s.feedback_watch
end
local function targetProgress(s,snap,target,now,eligible)
    local f=snap.feedback
    if type(f)~='table' or f.target_id~=target.id or not finite(f.attack_count)
        or f.attack_count<0 or f.attack_count%1~=0 or f.attack_count>1e12 then
        s.feedback_watch=nil;return
    end
    local w=s.feedback_watch
    if not w or w.target_id~=target.id or f.attack_count<w.count then resetFeedback(s,f,target);return end
    local posture=finite(target.posture) and target.posture>=0 and target.posture or nil
    local changed=target.hp<w.hp-0.01 or (posture and w.posture and posture<w.posture-0.01)
    w.hp,w.posture=target.hp,posture
    if changed then
        resetFeedback(s,f,target)
        s.reposition_until,s.feedback_attempts=nil,0
        if s.failed_target_id==target.id then s.failed_target_id,s.failed_until=nil,nil end
        return
    end
    if f.attack_count>w.count then
        if not finite(f.last_attack_at) or f.last_attack_at>now or now-f.last_attack_at>C.MAX_STEP_GAP
            or (w.last_ack and f.last_attack_at<w.last_ack) then resetFeedback(s,f,target);return end
        w.pulses=w.pulses+f.attack_count-w.count
        w.first_ack=w.first_ack or f.last_attack_at
        w.last_ack,w.count=f.last_attack_at,f.attack_count
    end
    if w.last_ack and now-w.last_ack>C.FEEDBACK_MAX_AGE then resetFeedback(s,f,target);return end
    if eligible and not s.reposition_until and w.pulses>=C.FEEDBACK_MIN_PULSES
        and w.last_ack-w.first_ack>=C.FEEDBACK_SPAN and now-w.last_ack>=0.16 then
        s.feedback_attempts=(s.feedback_attempts or 0)+1
        s.reposition_until=now+C.REPOSITION_SECONDS
        s.reposition_side=(s.slot+s.feedback_attempts)%2==0 and 1 or -1
        s.failed_target_id,s.failed_until=target.id,now+C.REPOSITION_SECONDS+3
        s.burst_count,s.recovery_until=0,nil
        resetFeedback(s,f,target)
    end
end
local function arm(s,snap,now)
    clear(s);s.active,s.epoch,s.actor_id,s.leader_id=true,snap.epoch,snap.player.id,snap.leader.id
    s.last_time,s.arm_until,s.prev_hp=now,now+C.ARM_SECONDS,snap.player.hp
    s.next_attack,s.next_dodge,s.next_defense=s.arm_until,s.arm_until,s.arm_until
    s.next_withdraw=s.arm_until
    rememberDamage(s,snap,now)
    return neutral('waiting','arming')
end
function M.step(s,snap,now)
    assert(type(s)=='table','policy state must be a table')
    local role=ROLES[s.slot];if not role then return stop(s,'human_only_slot')end
    if type(snap)~='table' or snap.enabled~=true then clear(s);return neutral('manual','disabled')end
    if not finite(now)then return stop(s,'invalid_clock')end
    if snap.ready~=true or snap.paused or snap.cutscene or snap.input_locked then return stop(s,'game_not_ready')end
    local p,leader=snap.player,snap.leader
    if not position(p) or not position(leader)then return stop(s,'invalid_actor')end
    if p.dead or leader.dead or not finite(p.hp) or not finite(p.max_hp) or p.hp<=0 or p.max_hp<=0 then return stop(s,'unavailable_player')end
    if leader.hp~=nil and (not finite(leader.hp) or leader.hp<=0)then return stop(s,'unavailable_player')end
    if p.grounded~=true then return stop(s,'not_grounded')end
    if snap.observed_at~=nil and (not finite(snap.observed_at) or now-snap.observed_at>C.MAX_STATE_AGE or snap.observed_at>now)then return stop(s,'stale_snapshot')end
    if s.last_time and now<s.last_time then return stop(s,'clock_reversed')end
    if s.last_time and now-s.last_time>C.MAX_STEP_GAP then clear(s);s.last_time=now;return neutral('suspended','step_gap')end
    if not s.active or s.epoch~=snap.epoch or s.actor_id~=p.id or s.leader_id~=leader.id then return arm(s,snap,now)end
    if now==s.last_time then return neutral('waiting','duplicate_tick')end
    s.last_time=now
    local damage=p.hp<(s.prev_hp or p.hp)-0.01;s.prev_hp=p.hp
    if damage then s.last_hurt=now end
    rememberDamage(s,snap,now)
    if now<s.arm_until then return neutral('waiting','arming')end
    local out=neutral();out.role=role.name
    local aggressive=snap.aggressive==true
    local ratio=p.hp/p.max_hp
    if aggressive then s.cautious,s.withdraw_until,s.next_withdraw=false,nil,nil
    elseif ratio<=C.LOW_HEALTH then s.cautious=true
    elseif ratio>=C.RECOVER_HEALTH and now-(s.last_hurt or -1e9)>=1 then s.cautious=false end
    out.health_state=aggressive and 'immortal_offense' or s.cautious and 'cautious' or 'healthy'
    if dist(p,leader)>C.LEASH then
        s.target_id,s.defend_until,s.escape_at=nil,nil,nil
        s.feedback_watch,s.reposition_until=nil,nil;releaseGuard(s,now);follow(s,snap,out,true,role)
        out.reason=out.mode=='blocked' and out.reason or 'return_to_leader'
        return progress(s,p,now,out)
    end
    if s.escape_at then
        if escape(s,now,out)then return out end
        s.escape_at=nil;if (s.escape_attempt or 0)>3 then s.escape_attempt=0 end
    end
    local target,score,info,crowd=choose(s,snap,now,role)
    if (target and target.id or nil)~=s.target_id then
        s.burst_count,s.recovery_until,s.defend_until=0,nil,nil;s.target_since=target and now or nil
        s.feedback_watch,s.reposition_until,s.feedback_attempts=nil,nil,0
    end
    s.target_id=target and target.id or nil
    if not target then
        releaseGuard(s,now)
        follow(s,snap,out,false,role)
        return progress(s,p,now,out)
    end
    out.target_id,out.target_score,out.target_reason=target.id,score,info.why;face(out,p,target)
    local d,range=info.distance,info.range;local extra=range-C.ATTACK_RANGE
    out.melee_range=range
    local signal=target.attacking==true and d<=C.DEFEND_RANGE+extra
    local rushing=closing(p,target)>160 and d<300+extra
    local crowded=crowd>=2 and d<260+extra
    if damage and d<=C.DEFEND_RANGE+extra then
        s.defend_until=now+C.DEFEND_SECONDS;s.defend_reason='recent_damage'
    elseif signal or rushing or crowded then
        s.defend_until=now+0.15
        s.defend_reason=signal and 'observed_attack' or rushing and 'closing_threat' or 'surrounded'
    end
    local hardPressure=damage or signal or rushing or crowded or (s.defend_until and now<s.defend_until)
    local resource=resourceRatio(p)
    out.resource_ratio=resource
    out.resource_state=resource==nil and 'unknown' or resource<=C.GUARD_LEAVE and 'reserve'
        or resource<C.GUARD_ENTER and 'rebuilding' or 'ready'
    local combined=type(snap.capabilities)=='table' and snap.capabilities.guard_attack==true
    local targetEmpty=finite(target.posture) and target.posture>=0 and target.posture<=0.01
    local safeToRelease=targetEmpty and crowd<=1 and not signal and not damage
    local wantGuard=(not aggressive or combined) and not safeToRelease and d<=C.DEFEND_RANGE+extra
        and (hardPressure or (combined and resource~=nil and d<=range+40))
    local guarded=guardOverlay(s,snap,now,resource,wantGuard,hardPressure,combined)
    if not aggressive and ratio<=C.CRITICAL_HEALTH and (damage or signal) and now>=(s.next_withdraw or 0)then
        s.withdraw_until=now+C.CRITICAL_WITHDRAW;s.next_withdraw=now+C.CRITICAL_INTERVAL
    end
    local withdrawing=s.withdraw_until and now<s.withdraw_until
    if s.reposition_until and now>=s.reposition_until then s.reposition_until=nil end
    targetProgress(s,snap,target,now,not withdrawing and not (guarded and not combined) and d<=range+40)
    if withdrawing then
        s.burst_count,s.recovery_until=0,nil
        out.mode,out.reason,out.decision,out.phase='retreat','critical_health','brief_critical_withdraw','withdraw'
        if dist(p,leader)>450 then move(out,p,formation(role,leader),0.65)
        elseif d<350+extra then move(out,target,p,0.55)end
        spacing(out,snap);face(out,p,target)
        out.block=guarded
        if (damage or signal) and d<=250+extra and now>=s.next_dodge and can(snap,'dodge')then
            out.dodge,out.block,s.next_dodge=true,false,now+C.DODGE_INTERVAL
        end
        return progress(s,p,now,out)
    end
    if s.reposition_until and now<s.reposition_until then
        releaseGuard(s,now)
        out.mode,out.reason,out.phase,out.decision='combat','attack_no_progress','reposition','try_lateral_opening'
        local x,y=unit(p.x-target.x,p.y-target.y);if x==0 and y==0 then x,y=1,0 end
        out.move_x,out.move_y=-y*s.reposition_side*0.45,x*s.reposition_side*0.45
        spacing(out,snap);face(out,p,target)
        -- Immortal companions keep pressing while changing angle inside reach.
        -- Aiming/LOS and physical release edges remain the adapter's authority.
        if aggressive and d<=range then
            out.reason='assist'
            if now>=s.next_attack and can(snap,'attack')then
                out.attack=true;s.next_attack=now+role.interval;s.last_light_intent=now
            end
        end
        return progress(s,p,now,out)
    end
    if guarded and not combined then
        out.mode,out.reason,out.phase,out.decision='defending','guard_only','guard_only','separate_guard_mapping'
        out.block=true;spacing(out,snap);face(out,p,target)
        return progress(s,p,now,out)
    end
    out.mode,out.reason,out.decision='combat','assist',info.why
    out.block=guarded
    local goal,angle,ring=combatGoal(role,target,leader,range)
    local currentAngle=atan2(p.y-target.y,p.x-target.x)
    local angleError=math.abs((math.deg(angle-currentAngle)+180)%360-180)
    local flank=role.name~='guard' and info.urgent==0
        and (info.pressure>0 or (not aggressive and role.name=='flank'))
        and angleError>55 and dist(p,goal)>95 and (s.burst_count or 0)==0
        and (d>range or now-(s.target_since or now)<0.45)
    if d>range or flank then
        out.phase,out.decision='approach',flank and 'take_flank' or 'close_to_threat'
        -- Near the enemy use a tangent first instead of walking through its body.
        if flank and d<280+extra then
            local signed=(math.deg(angle-currentAngle)+180)%360-180
            local a=currentAngle+(signed>=0 and math.pi/3 or -math.pi/3)
            goal={x=target.x+math.cos(a)*math.max(d,ring),y=target.y+math.sin(a)*math.max(d,ring),z=target.z}
        end
        move(out,p,goal,d>350+extra and 0.7 or 0.45);spacing(out,snap);face(out,p,target)
    else
        out.phase=guarded and 'guarded_pressure' or resource~=nil and resource<=C.GUARD_LEAVE and 'reserve_light' or 'pressure'
        out.decision=guarded and 'guarded_light' or out.phase=='reserve_light' and 'reserve_light' or 'light_pressure'
        if now>=s.next_attack and can(snap,'attack')then
            out.attack=true;s.burst_count=(s.burst_count or 0)%role.burst+1;s.next_attack=now+role.interval
            s.last_light_intent=now
        end
    end
    return progress(s,p,now,out)
end
return M
