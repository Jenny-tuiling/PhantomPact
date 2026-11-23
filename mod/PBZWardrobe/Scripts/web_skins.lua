-- Body-only procedural skins. Call public mutators on the game thread.
-- Keeps PBZ's original mesh, animation graph, weapons and gameplay collision.
local source=debug.getinfo(1,'S').source:gsub('^@',''):gsub('\\','/')
local moduleDir=assert(source:match('^(.*)/[^/]+$'),'Cannot locate web_skins.lua')
local M={version='2026.11.18-web-skins-5-matte'}
local options={dataDir=moduleDir..'/Data',pollMs=1000}
local explicitData=false
local dataCache,textureCache={},{}
local live,building={},{}
local buildingAny=false
local json,contract,materialParent,proceduralClass
local running,generation=false,0
local selections={'pbz_original','pbz_original','pbz_original','pbz_original'}
local supported={chenchen='辰辰',xiaobao='小宝',zhubajie='猪八戒',fengfeng='枫枫'}
local expectedParts={chenchen=17,xiaobao=17,zhubajie=16,fengfeng=16}
local cosmeticNames={Hun_Hat=true,Hun_Hat01=true,meshhead=true,meshBrowLashCard=true,
 meshScarf=true,meshBand=true,CA_Hun_Cape=true,CA_Hun_UpperCloth=true,CA_Hun_Skirt=true,CA_Hun_Hair=true}
local cosmeticLower={};for name in pairs(cosmeticNames)do cosmeticLower[name:lower()]=true end
local function log(s) if options.log then options.log('[WebSkins] '..s) else print('[WebSkins] '..s..'\n') end end
-- All delayed callbacks stay on the engine thread. Async timer callbacks
-- registering ExecuteInGameThread can otherwise race this VM's hook stack.
local function after(ms,fn)
 assert(type(ExecuteInGameThreadWithDelay)=='function','Native delayed game-thread callbacks unavailable')
 return ExecuteInGameThreadWithDelay(ms,fn)
end
local function stage(id,part,label)
 pcall(function()
  local f=io.open(moduleDir..'/web_skin_stage.log','a')
  if f then
   f:write(os.date('%Y-%m-%d %H:%M:%S')..' '..id..' '..tostring(part and part.name or '-')..' '..label..'\n')
   f:flush();f:close()
  end
 end)
end
local function valid(v)
 if v==nil or type(v)=='string' or type(v)=='number' or type(v)=='boolean' then return false end
 local ok,r=pcall(function()return v:IsValid()end);return ok and r==true
end
local function full(v)if not valid(v)then return ''end;local ok,s=pcall(function()return v:GetFullName()end);return ok and tostring(s) or ''end
local function key(v)if not valid(v)then return nil end;return full(v)..'@'..tostring(v:GetAddress())end
local function identity()return {Rotation={X=0,Y=0,Z=0,W=1},Translation={X=0,Y=0,Z=0},Scale3D={X=1,Y=1,Z=1}}end
local function cleanPath(p)assert(type(p)=='string' and p~='' and not p:find('%z'),'Invalid path');return p:gsub('\\','/'):gsub('/+$','')end
local function read(path)
 local f,err=io.open(path,'rb');assert(f,'Cannot read '..path..': '..tostring(err))
 local s=f:read('*a');f:close();assert(#s<80*1024*1024,'Skin data is unexpectedly large');return s
end
local function decoder()
 if json then return json end
 if options.jsonPath then json=dofile(options.jsonPath)
 else
  local f=io.open(moduleDir..'/json.lua','rb')
  if f then f:close();json=dofile(moduleDir..'/json.lua')
  else local ok,value=pcall(require,'json');if ok then json=value end end
 end
 assert(type(json)=='table' and type(json.decode)=='function','JSON decoder unavailable; configure jsonPath')
 return json
end
local function reference()
 if not contract then
  contract=decoder().decode(read(options.dataDir..'/reference-contract.json'))
  assert(contract.schema==1 and type(contract.bones)=='table' and #contract.bones>0,'Invalid reference contract')
 end
 return contract
end
local function data(id)
 assert(supported[id],'Unsupported web skin '..tostring(id))
 if dataCache[id] then return dataCache[id] end
 local d=decoder().decode(read(options.dataDir..'/'..id..'.json'))
 assert(d.schema==1 and d.id==id and type(d.parts)=='table' and #d.parts==expectedParts[id],'Incomplete web skin '..id)
 assert(d.palette==id..'-palette.png','Unexpected palette path')
 local seen={}
 for _,p in ipairs(d.parts)do
  assert(type(p.name)=='string' and not seen[p.name] and type(p.bone)=='string' and p.bone:match('^[A-Za-z0-9_]+$'),'Invalid body part')
  seen[p.name]=true
  assert(type(p.vertices)=='table' and #p.vertices>0 and #p.vertices==#p.normals and #p.vertices==#p.uv,'Invalid mesh arrays')
  assert(type(p.indices)=='table' and #p.indices%3==0,'Invalid triangles')
  for _,i in ipairs(p.indices)do assert(type(i)=='number' and i%1==0 and i>=0 and i<#p.vertices,'Invalid triangle index')end
 end
 dataCache[id]=d;reference()
 log('Cached '..id..' parts='..expectedParts[id])
 return d
end
local function numeric(v)return type(v)=='number' and v==v and v~=math.huge and v~=-math.huge end
local function closeVector(a,b,epsilon)
 for _,axis in ipairs({'X','Y','Z'})do if not numeric(a[axis]) or math.abs(a[axis]-b[axis])>epsilon then return false end end
 return true
end
local function compatible(mesh)
 local check=reference()
 for _,b in ipairs(check.bones)do
  local index=mesh:GetBoneIndex(FName(b.name));assert(type(index)=='number' and index>=0,'Missing bone '..b.name)
  local parent=mesh:GetParentBone(FName(b.name)):ToString();assert(parent==b.parent,'Different bone parent '..b.name)
  local t=mesh:GetRefPoseTransform(index)
  assert(closeVector(t.Translation,b.ref.Translation,.02),'Different reference position '..b.name)
  assert(closeVector(t.Scale3D,b.ref.Scale3D,.002),'Different reference scale '..b.name)
  local q,r=t.Rotation,b.ref.Rotation
  local dot=q.X*r.X+q.Y*r.Y+q.Z*r.Z+q.W*r.W
  assert(numeric(dot) and math.abs(math.abs(dot)-1)<.0002,'Different reference rotation '..b.name)
 end
 return true
end
local function parentMaterial()
 if valid(materialParent)then return materialParent end
 -- Website bodies use MeshStandardMaterial. The palette contains albedo,
 -- not emitted radiance; an Unlit parent washes it out under PBZ exposure.
 local path='/InterchangeAssets/gltf/MaterialInstances/MI_Default_Mask_DS.MI_Default_Mask_DS'
 materialParent=StaticFindObject(path)
 if not valid(materialParent)then
  local pkg,name=path:match('^(.-)%.([^%.]+)$')
  local helper=StaticFindObject('/Script/AssetRegistry.Default__AssetRegistryHelpers')
  assert(valid(helper),'Asset registry unavailable')
  materialParent=helper:GetAsset({PackageName=FName(pkg),AssetName=FName(name)})
 end
 assert(valid(materialParent),'Palette material unavailable');return materialParent
end
local function texture(pawn,id)
 local t=textureCache[id]
 if not valid(t)then
  local library=StaticFindObject('/Script/Engine.Default__KismetRenderingLibrary')
  assert(valid(library),'Texture importer unavailable')
  t=library:ImportFileAsTexture2D(pawn,options.dataDir..'/'..id..'-palette.png')
  assert(valid(t),'Palette import failed '..id);textureCache[id]=t
 end
 return t
end
local flagMethods={bRenderInMainPass='SetRenderInMainPass',bRenderInDepthPass='SetRenderInDepthPass',CastShadow='SetCastShadow',
 bVisible='SetVisibility',bHiddenInGame='SetHiddenInGame'}
local function setFlag(c,property,value)
 local method=flagMethods[property]
 if property=='bVisible' or property=='bHiddenInGame'then c[method](c,value,false)else c[method](c,value)end
end
local function hidePart(record,component,isMain)
 if not valid(component)then return end
 local k=key(component);local row=record.hidden[k]
 if not row then
  row={component=component,flags={},desired={}}
  record.hidden[k]=row
  local desired={bRenderInMainPass=false,bRenderInDepthPass=false,CastShadow=false}
  if not isMain then desired.bVisible=false;desired.bHiddenInGame=true end
  for property,value in pairs(desired)do
   local ok,current=pcall(function()return component[property]end)
   if ok and type(current)=='boolean'then row.flags[property]=current;row.desired[property]=value end
  end
  if isMain then assert(row.flags.bRenderInMainPass~=nil,'Cannot preserve original render state')end
 end
 for property,value in pairs(row.desired)do
  local ok,current=pcall(function()return component[property]end)
  if ok and current~=value then setFlag(component,property,value)end
 end
end
local function enumerateCosmetics(record)
 local pawn=record.pawn
 for name in pairs(cosmeticNames)do
  local ok,c=pcall(function()return pawn[name]end)
  if ok and valid(c)then hidePart(record,c,false)end
 end
 local cls=StaticFindObject('/Script/Engine.SceneComponent')
 if not valid(cls)then return end
 local array=pawn:K2_GetComponentsByClass(cls)
 local function inspect(c)
  if not valid(c)then local ok,v=pcall(function()return c:get()end);c=ok and v or nil end
  if not valid(c)then return end
  local n=c:GetFName():ToString():lower()
  if cosmeticLower[n]then hidePart(record,c,false)end
 end
 if type(array)=='table'then for _,c in ipairs(array)do inspect(c)end
 elseif array then array:ForEach(function(_,entry)inspect(entry)end)end
end
local function destroy(record,restore)
 if not record then return end
 for _,c in ipairs(record.parts or {})do
  if valid(c)then pcall(function()c:K2_DestroyComponent(record.pawn)end)end
 end
 record.parts={}
 if restore then
  for _,row in pairs(record.hidden or {})do
   if valid(row.component)then
    for property,value in pairs(row.flags)do pcall(setFlag,row.component,property,value)end
   end
  end
  if valid(record.mesh) and record.oldTickOption~=nil then
   pcall(function()record.mesh.VisibilityBasedAnimTickOption=record.oldTickOption end)
  end
 end
 record.hidden={}
end
function M.configure(config)
 assert(not running and next(live)==nil,'Stop existing skins before reconfiguring')
 config=config or {}
 if config.dataDir then options.dataDir=cleanPath(config.dataDir);explicitData=true end
 if config.jsonPath then options.jsonPath=cleanPath(config.jsonPath)end
 if config.pollMs then assert(config.pollMs>=250 and config.pollMs<=10000,'Invalid polling interval');options.pollMs=config.pollMs end
 if config.log then assert(type(config.log)=='function');options.log=config.log end
 dataCache,textureCache={},{};json,contract=nil,nil
 return M
end
function M.registerProfiles(profiles)
 assert(type(profiles)=='table' and type(profiles.byId)=='table','Profiles unavailable')
 for id,name in pairs(supported)do
  local existing=profiles.byId[id]
  assert(not existing or existing.procedural_skin,'Conflicting profile '..id)
  if not existing then
   local p={schema=1,id=id,name=name,native_original=true,procedural_skin=true,sort_order=id=='chenchen' and 800 or id=='xiaobao' and 801 or id=='zhubajie' and 802 or 803,
    slots={},paint={enabled=false},hide_original={enabled=false,native_cloth=false,component_names={},asset_roots={},asset_fragments={}}}
   profiles.byId[id]=p
   if type(profiles.list)=='table'then table.insert(profiles.list,p)end
  end
 end
 return M
end
function M.preload(id) return data(id)end
function M.cleanup(pawn)
 local k=key(pawn)
 if k and live[k]then local old=live[k];live[k]=nil;destroy(old,true);log('Removed '..old.id..' from '..full(pawn));return true end
 return false
end
function M.apply(pawn,id)
 assert(valid(pawn),'Player unavailable');assert(supported[id],'Unsupported web skin')
 if buildingAny then return false,'Another skin construction is in progress' end
 local k=key(pawn);assert(k and not building[k],'Skin construction already running')
 local old=live[k]
 if old and old.id==id then
  local complete=valid(old.mesh) and valid(pawn.Mesh) and old.mesh:GetAddress()==pawn.Mesh:GetAddress()
  if complete and old.meshAsset then complete=full(old.mesh.SkeletalMesh)==old.meshAsset end
  for _,c in ipairs(old.parts)do if not valid(c)then complete=false;break end end
  if complete and #old.parts==expectedParts[id] then
   hidePart(old,old.mesh,true)
   for _,row in pairs(old.hidden)do if valid(row.component)then for property,value in pairs(row.desired)do
    if row.component[property]~=value then setFlag(row.component,property,value)end
   end end end
   if old.mesh.VisibilityBasedAnimTickOption~=0 then old.mesh.VisibilityBasedAnimTickOption=0 end
   return true
  end
 end
 building[k]=true;buildingAny=true
 local record={pawn=pawn,id=id,parts={},hidden={}}
 local ok,err=pcall(function()
  if old then live[k]=nil;destroy(old,true)end
  local d=data(id);local mesh=pawn.Mesh;assert(valid(mesh),'Original skeletal mesh unavailable');record.mesh=mesh;record.meshAsset=full(mesh.SkeletalMesh)
  compatible(mesh)
  proceduralClass=valid(proceduralClass) and proceduralClass or StaticFindObject('/Script/ProceduralMeshComponent.ProceduralMeshComponent')
  assert(valid(proceduralClass),'Procedural mesh component unavailable')
  local parent=parentMaterial();local tex=texture(pawn,id);local material
  for _,part in ipairs(d.parts)do
   local c=pawn:AddComponentByClass(proceduralClass,true,identity(),false)
   assert(valid(c),'Cannot create '..part.name);record.parts[#record.parts+1]=c
   c:SetVisibility(false,false);c:SetCollisionEnabled(0)
   c:SetReceivesDecals(false) -- Environment projection must not paint the character body.
   stage(id,part,'mesh.before vertices='..#part.vertices..' indices='..#part.indices)
   c:CreateMeshSection_LinearColor(0,part.vertices,part.indices,part.normals,part.uv,{},{},{},{},{},false,false)
   stage(id,part,'mesh.after')
   assert(c:GetNumSections()==1,'Missing geometry for '..part.name)
   if not valid(material)then
    material=c:CreateDynamicMaterialInstance(0,parent,FName('WebSkin_'..id))
    assert(valid(material),'Palette material instance unavailable')
    material:SetTextureParameterValue(FName('BaseColorTexture'),tex)
    material:SetVectorParameterValue(FName('BaseColorFactor'),{R=1,G=1,B=1,A=1})
    -- The source material's .8 tint is already baked into the sRGB palette.
    -- User-selected matte finish; preserve the baked palette and base color.
    material:SetScalarParameterValue(FName('RoughnessFactor'),1)
    material:SetScalarParameterValue(FName('MetallicFactor'),0)
    material:SetScalarParameterValue(FName('SpecularFactor'),0)
    material:SetScalarParameterValue(FName('EmissiveStrength'),0)
   else c:SetMaterial(0,material)end
   assert(c:K2_AttachToComponent(mesh,FName(part.bone),2,2,2,false),'Cannot attach '..part.name)
  end
  -- The original remains visible until all geometry, material and attachments exist.
  assert(#record.parts==expectedParts[id],'Incomplete body')
  record.oldTickOption=mesh.VisibilityBasedAnimTickOption
  assert(type(record.oldTickOption)=='number','Cannot preserve animation tick setting')
  mesh.VisibilityBasedAnimTickOption=0
  hidePart(record,mesh,true);enumerateCosmetics(record)
  for _,c in ipairs(record.parts)do c:SetVisibility(true,false)end
 end)
 building[k]=nil;buildingAny=false
 if not ok then destroy(record,true);log('Failed '..id..': '..tostring(err));return false,tostring(err)end
 live[k]=record
 log('Applied '..id..' parts='..expectedParts[id]..' pawn='..full(pawn))
 -- Costume components can arrive after ClientRestart. Inspect only this owner.
 for _,delay in ipairs({1000,3000})do
  after(delay,function()
   if live[k]==record and valid(pawn)then pcall(enumerateCosmetics,record)end
  end)
 end
 return true
end
local function currentPlayers()
 local gs=StaticFindObject('/Script/Engine.Default__GameplayStatics')
 if not valid(gs)then return {}end
 local context
 if type(FindFirstOf)=='function'then context=FindFirstOf('PlayerController')end
 if not valid(context)then return {}end
 local players={}
 for index=0,3 do local ok,p=pcall(function()return gs:GetPlayerPawn(context,index)end);if ok and valid(p)then players[index+1]=p end end
 return players
end
local failures={}
local function ensurePlayers()
 local players=currentPlayers();local active={}
 for seat,pawn in pairs(players)do
  local k=key(pawn);local id=selections[seat];active[k]=true
  if supported[id]then
   local cls=pawn:GetClass():GetFName():ToString()
   if cls=='BP_Renewal_Hun_C' or cls=='BP_Player_Hero_Hun_C'then
    local last=failures[k]
    if not last or os.clock()-last>10 then
     local ok,a,b=pcall(M.apply,pawn,id)
     if not ok or not a then
      failures[k]=os.clock();log('Seat '..seat..' deferred: '..tostring(ok and b or a))
     else failures[k]=nil end
    end
   end
  elseif live[k]then M.cleanup(pawn)end
 end
 for k,row in pairs(live)do
  if not valid(row.pawn)then live[k]=nil;failures[k]=nil
  elseif not active[k]then live[k]=nil;destroy(row,true);failures[k]=nil end
 end
end
function M.start(profiles,appearance)
 assert(not running,'Web skins already started')
 assert(type(profiles)=='table' and type(profiles.root)=='string','Profiles root unavailable')
 if not explicitData then options.dataDir=cleanPath(profiles.root)..'/WebSkins/Data' end
 if not options.jsonPath then options.jsonPath=cleanPath(profiles.root)..'/Scripts/json.lua' end
 M.registerProfiles(profiles)
 selections={'pbz_original','pbz_original','pbz_original','pbz_original'}
 local f=io.open(profiles.root..'/player_skins.txt','rb')
 if f then local i=0;for line in f:lines()do i=i+1;if i>4 then break end;selections[i]=line:gsub('\r','')end;f:close()end
 -- Decode each selected skin once before characters appear, never per respawn.
 local preloaded={}
 for _,id in ipairs(selections)do if supported[id] and not preloaded[id]then data(id);preloaded[id]=true end end
 running=true;generation=generation+1;local token=generation
 if appearance and type(appearance.onPawn)=='function'then
  appearance.onPawn(function()
   after(250,function()
    if running and generation==token then ensurePlayers()end
   end)
  end)
 end
 local function tick()
  if not running or generation~=token then return end
  local ok,err=pcall(ensurePlayers);if not ok then log('Lifecycle check: '..tostring(err))end
  if running and generation==token then after(options.pollMs,tick)end
 end
 after(0,tick);log('Started per-player skins on native game-thread timers; original gameplay skeleton retained')
 return M
end
function M.stop()
 running=false;generation=generation+1
 for k,record in pairs(live)do live[k]=nil;destroy(record,true)end
 failures={};log('Stopped and restored owned render flags')
end
function M.status()
 local result={running=running,version=M.version,dataDir=options.dataDir,players={}}
 for _,row in pairs(live)do result.players[#result.players+1]={id=row.id,pawn=full(row.pawn),parts=#row.parts}end
 return result
end
return M
