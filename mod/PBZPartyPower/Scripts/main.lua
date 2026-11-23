-- Independent session-only power controller. Never writes PBZ saves or loads arbitrary requests as Lua.
local source=debug.getinfo(1,'S').source:sub(2):gsub('\\','/')
local root=assert(source:match('^(.*)/Scripts/main%.lua$'))..'/'
local coop=root:gsub('PBZPartyPower/$','PBZCoop/')
local helpers=require('UEHelpers')
local factory=dofile(root..'Scripts/power.lua')
local gs,ability
local function valid(o)return o~=nil and o:IsValid()end
local function log(s)print('[PartyPower] '..s..'\n')end
local function player1()
 local context=helpers.GetPlayerController()
 if not valid(context)or not valid(gs)then return nil,nil end
 local pc=gs:GetPlayerController(context,0)
 return pc,valid(pc)and pc.Pawn or nil
end
local function hp(p)return p.AttributeSetBase.Health.CurrentValue,p.AttributeSetBase.Health_Max.CurrentValue end
local session=tostring(os.time())..'-'..tostring({}):gsub('[^%w]','')
local wanted,lastId,lastState=false,'none','off'
local M
local party={count=0,loading=true}
function party.ready()return not party.loading end
local api={valid=valid,log=log,gs=function()return gs end,getPlayer1=player1,game={getHealth=hp,
 isDead=function(p)return p:IsDead() or hp(p)<=0 end,
 setHealth=function(p,n)p.AttributeSetBase.Health.BaseValue=n;p.AttributeSetBase.Health.CurrentValue=n end}}
local function readSmall(name)
 local f=io.open(root..name,'rb');if not f then return nil end
 local s=f:read(257);f:close();if not s or #s>256 then return nil end;return s
end
local function routeCount()
 local f=io.open(coop..'four_route.txt','rb');if not f then return 0 end
 local t=f:read(513);f:close();if not t or #t>512 then return 0 end
 local lines={};for l in t:gmatch('[^\r\n]+')do lines[#lines+1]=l end
 if #lines~=5 then return 0 end
 for i=1,4 do if not lines[i]:match('^%d+ %-?%d+$')then return 0 end end
 local n=tonumber(lines[5]);return n and n>=2 and n<=4 and n%1==0 and n or 0
end
local function publish(state,applied)
 -- A launcher/virus scanner can briefly hold this file. A missed heartbeat
 -- must never cancel the user's gameplay setting; retry on the next tick.
 local f=io.open(root..'status.txt','wb');if not f then return false end
 local count=party.loading and not wanted and 0 or party.count
 local ok=f:write(string.format('PBZPOWER1 %s %s %d %d %s\n',session,state,count,math.min(applied,count),lastId));f:close()
 return ok~=nil
end
local function stop()
 wanted=false;if M then M.stop();M=nil end;lastState='off'
end
local function tick()
 assert(IsInGameThread(),'Game-thread callback required')
 gs=StaticFindObject('/Script/Engine.Default__GameplayStatics')
 ability=StaticFindObject('/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary')
 local pc,p=player1();party.count=routeCount();party.loading=true
 if valid(pc)and valid(p)and valid(ability)and party.count>=2 and p:GetClass():GetFName():ToString():find('BP_Renewal_Hun_')then
  local present=0
  for slot=0,party.count-1 do
   local other=gs:GetPlayerController(pc,slot);local body=valid(other)and other.Pawn or nil
   if valid(body)and body:GetClass():GetFName():ToString():find('BP_Renewal_Hun_')then present=present+1 end
  end
  party.loading=present~=party.count
 end
 local command=readSmall('request.txt')
 if command then
  local s,id,action=command:match('^PBZPOWER1 ([%w%-]+) ([%w%-]+) (o[nf]+)\r?\n?$')
  if s==session and id~=lastId and #id<=80 and (action=='on'or action=='off')then
   lastId=id
   if action=='off'then stop()
   elseif not party.loading then wanted=true;lastState='waiting'
   else lastState='error' end
  end
 end
 local applied=0
 if wanted and not party.loading then
  if not M then
   local effect=FindObject('BlueprintGeneratedClass','GE_PBZLieInvulnerable_C')
   assert(valid(effect)and effect:GetCDO().DurationPolicy==1,'Known invulnerability effect unavailable')
   M=factory(api,party,{effect=effect,asc=function(pawn)return ability:GetAbilitySystemComponent(pawn)end,running=function()return wanted end})
  end
  M.step()
  local result=M.status()
  for _,row in ipairs(result.players)do
   if not row.dead and row.shieldCount>0 then applied=applied+1 end
  end
  lastState=applied==party.count and 'on'or 'waiting'
 elseif wanted then lastState='waiting' end
 publish(lastState,applied)
end
publish('off',0)
LoopInGameThreadWithDelay(500,function()
 local ok,err=pcall(tick)
 if not ok then
  log('ERROR '..tostring(err));pcall(stop);lastState='error';pcall(publish,'error',0)
 end
 return false
end)
log('Ready; default OFF. Only current-session requests from setup are accepted.')
