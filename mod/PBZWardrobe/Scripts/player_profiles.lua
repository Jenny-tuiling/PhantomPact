-- Per-seat selections, read once before play; no save/inventory changes.
local M={}
local function warning(message)
    print('[PartyWardrobe] WARNING '..message..'\n')
end
function M.load(path,available)
    local choices={'pbz_original','pbz_original','pbz_original','pbz_original'}
    local f=io.open(path,'rb')
    if not f then return choices end
    local line=0
    for raw in f:lines() do
        line=line+1
        if line>4 then
            warning('Ignoring skin selections after player 4; selection file unchanged')
            break
        end
        local value=raw:gsub('\r','')
        if not value:match('^[a-z0-9_-]+$') then
            warning('Invalid skin selection for player '..line..'; using pbz_original for this session; selection file unchanged')
        elseif not available[value] then
            warning('Unavailable skin '..value:sub(1,80)..' for player '..line..'; using pbz_original for this session; selection file unchanged')
        else
            choices[line]=value
        end
    end
    f:close()
    return choices
end
function M.resolve(pawn,gs,valid)
    if not valid(pawn) then return nil end
    for index=0,3 do
        local candidate=gs:GetPlayerPawn(pawn,index)
        if valid(candidate) and candidate:GetAddress()==pawn:GetAddress() then return index+1 end
    end
    return nil -- cinematic actors do not inherit a guest selection
end
return M
