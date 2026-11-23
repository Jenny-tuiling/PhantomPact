-- Session-only player buffs. Loaded explicitly; no installed startup hook or save edits.
return function(api,party,env)
 local M={enabled=true,actors={},errors=0}
 local kinds={'Physical','PhysicalSharp','PhysicalBlunt','Fire','Toxin','Ice','Aqua','Lightning','Blood','Chaos'}
 local prefix='DealtVulnerabilityMultiplier_'
 local function same(a,b)return type(a)=='number' and type(b)=='number' and math.abs(a-b)<0.0001 end
 local function identity(p)return api.valid(p) and p:GetFullName() or nil end
 local function restore(r)
  if identity(r.pawn)~=r.name then return end
  if r.handle and api.valid(r.asc)then r.asc:RemoveActiveGameplayEffect(r.handle,1);r.handle=nil end
  for key,b in pairs(r.damage)do
   local a=r.pawn.AttributeSetBase[key]
   -- Another writer replacing the base owns that new value.
   if same(a.BaseValue,b.given)then a.BaseValue=b.base;a.CurrentValue=a.CurrentValue/10 end
  end
  for key,b in pairs(r.incoming)do
   local a=r.pawn.AttributeSetBase[key]
   if same(a.BaseValue,0)then a.BaseValue=b.base;a.CurrentValue=b.current end
  end
 end
 function M.stop()
  M.enabled=false
  for _,r in pairs(M.actors)do local ok,e=pcall(restore,r);if not ok then api.log('TEMP_POWER restore: '..tostring(e));M.errors=M.errors+1 end end
  M.actors={}
  api.log('TEMP_PARTY_POWER OFF: owned player effects and damage multipliers restored')
 end
 function M.step()
  if not M.enabled then return end
  if not env.running()then M.stop();return end
  if party.loading or not party.ready()then return end
  local seen={}
  local pc1=api.getPlayer1()
  for slot=1,party.count do
   local pc=api.gs():GetPlayerController(pc1,slot-1)
   local p=api.valid(pc)and pc.Pawn or nil
   if api.valid(p)then
    local id=p:GetAddress();seen[id]=true
    local r=M.actors[id]
    if r and r.name~=identity(p)then M.actors[id]=nil;r=nil end
    if not api.game.isDead(p) and (api.game.getHealth(p)or 0)>1 then
     if not r then
      local asc=env.asc(p)
      assert(api.valid(asc),'Player ability system unavailable')
      r={pawn=p,name=identity(p),asc=asc,slot=slot,damage={},incoming={}};M.actors[id]=r
      -- Existing co-op downed/cutscene shields remain owned by the co-op mod.
      api.game.setHealth(p,select(2,api.game.getHealth(p)))
      if api.game.showPlayerHealth then api.game.showPlayerHealth(p)end
     end
     for _,kind in ipairs(kinds)do
      local key=prefix..kind;local a=p.AttributeSetBase[key]
      local b=r.damage[key]
      if not b or not same(a.BaseValue,b.given)then
       assert(type(a.BaseValue)=='number' and a.BaseValue>=0 and a.BaseValue<100000,'Invalid damage base')
       b={base=a.BaseValue,given=a.BaseValue*10};r.damage[key]=b
       a.BaseValue=b.given;a.CurrentValue=a.CurrentValue*10
      end
      local incomingKey='TakenReductionMultiplier_'..kind
      local incoming=p.AttributeSetBase[incomingKey]
      local original=r.incoming[incomingKey]
      if not original or not same(incoming.BaseValue,0)then
       assert(type(incoming.BaseValue)=='number' and type(incoming.CurrentValue)=='number','Incoming damage attribute unavailable')
       r.incoming[incomingKey]={base=incoming.BaseValue,current=incoming.CurrentValue}
       incoming.BaseValue=0;incoming.CurrentValue=0
      end
     end
     local count=r.asc:GetGameplayEffectCount(env.effect,nil,true)
     if count==0 then
      r.handle=r.asc:BP_ApplyGameplayEffectToSelf(env.effect,1,r.asc:MakeEffectContext())
      assert(r.asc:GetGameplayEffectCount(env.effect,nil,true)>0,'Invulnerability effect was not accepted')
     end
     api.game.setHealth(p,select(2,api.game.getHealth(p)))
    end
   end
  end
  for id,r in pairs(M.actors)do if not seen[id]then restore(r);M.actors[id]=nil end end
 end
 function M.status()
  local out={enabled=M.enabled,errors=M.errors,players={}}
  for _,r in pairs(M.actors)do
   if identity(r.pawn)==r.name then
    local p=r.pawn;local hp,mx=api.game.getHealth(p)
    local x={slot=r.slot,name=r.name,hp=hp,maxHp=mx,dead=api.game.isDead(p),shieldCount=r.asc:GetGameplayEffectCount(env.effect,nil,true),damage={},incoming={}}
    for _,kind in ipairs(kinds)do local a=p.AttributeSetBase[prefix..kind];x.damage[kind]={base=a.BaseValue,current=a.CurrentValue};x.incoming[kind]=p.AttributeSetBase['TakenReductionMultiplier_'..kind].CurrentValue end
    out.players[#out.players+1]=x
   end
  end
  table.sort(out.players,function(a,b)return a.slot<b.slot end)
  return out
 end
 return M
end
