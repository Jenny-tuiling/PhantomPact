-- Personal main-weapon selection; never writes the shared backpack or player 1.
return function(api,party)
    local root=api.modDir()
    local last={},{}
    local settled={}
    local slot={TagName=FName('Weapon.Slot.Main')}
    local function unwrap(v) local ok,x=pcall(function()return v:get()end);return ok and x or v end
    local function tick()
        if party.loading then settled={};return end
        local pc,p1=api.getPlayer1()
        if not api.valid(p1) or api.gs():IsGamePaused(pc) then return end
        local bag=api.game.backpackOf(p1)
        if not bag then return end
        local owned={}
        for _,v in ipairs(bag:GetAllNormalWeapons()) do owned[unwrap(v):ToString()]=true end
        local catalog={}
        for _,cfg in ipairs(FindAllOf('PBZ_MainWeaponConfig_C') or {}) do
            local path=cfg:GetFullName():match(' (/PBZCombatAsset/ActorData/Players/Hun/Weapon/.*)$')
            local id=path and path:match('/Weapon_Hun_([%w]+)%.Weapon_Hun_%w+$')
            -- Only exact owned IDs are accepted. No substring guesses or unlocking.
            if id and owned[id] then catalog[id]={path=path,cfg=cfg} end
        end
        local lines={}
        for id,item in pairs(catalog) do lines[#lines+1]=id..'\t'..item.path end
        table.sort(lines)
        local f=io.open(root..'party_weapon_catalog.txt','w');if f then f:write(table.concat(lines,'\n'));f:close()end
        local requests={}
        f=io.open(root..'party_weapons.txt','r')
        if f then for line in f:lines() do requests[#requests+1]=line:gsub('\r','') end;f:close() end
        for i=2,party.count do
            local pawn=party.states[i] and party.states[i].p2Pawn
            if api.valid(pawn) then
                local address=pawn:GetAddress()
                if not settled[i] or settled[i].address~=address then settled[i]={address=address,at=os.clock()+6} end
                local item=catalog[requests[i]]
                local key=tostring(address)..':'..tostring(requests[i])
                if item and last[i]~=key and os.clock()>=settled[i].at then
                    local cwc=pawn['Character Weapons Component']
                    if not cwc:IsArmed(slot) then
                        cwc:SetSlotWeapon(slot,math.max(cwc:GetCurrentWeaponIndex(slot,false) or 0,0),item.cfg)
                        last[i]=key
                        api.log('Party weapon: P'..i..' selected '..requests[i])
                    end
                end
            end
        end
    end
    LoopInGameThreadWithDelay(1000,function()
        local ok,err=pcall(tick)
        if not ok then api.log('Party weapons: '..tostring(err)) end
        return false
    end)
end
