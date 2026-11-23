-- The 1.7.3 two-player interaction hook has one owner. Keep that invariant
-- when localcoop is instantiated for P2/P3/P4; do not change game progression.
return function(valid, register, log)
 local M={};local callbacks,claims,owners,frames={},{},{},{}
 local hooked=false;local epoch=0;local active={}
 local function identity(a)return a:GetAddress(),a:GetFullName()end
 function M.release(slot)
  local c=owners[slot]
  if c and claims[c.address]==c then claims[c.address]=nil end
  owners[slot]=nil
 end
 function M.claim(slot,thing)
  if not valid(thing)then return false end
  local address,name=identity(thing);local c=claims[address]
  if c and (not valid(c.thing)or c.name~=name)then M.release(c.slot);c=nil end
  if c and c.slot~=slot then return false end
  local held=owners[slot]
  if held and held~=c then
   if valid(held.thing)then return false end
   M.release(slot)
  end
  if not c then c={slot=slot,thing=thing,address=address,name=name};claims[address]=c;owners[slot]=c end
  return true
 end
 function M.hook(slot,path,before,after)
  callbacks[slot]={before=before,after=after}
  if hooked then return end
  register(path,function(ctx)
   local frame={epoch=epoch};frames[#frames+1]=frame
   local ok,err=pcall(function()
    local a=ctx:get();if not valid(a)then return end
    local address,name=identity(a);local c=claims[address]
    if not c or c.name~=name or not valid(c.thing)then return end
    local cb=callbacks[c.slot];if not cb then return end
    -- The same native action may re-enter. Its inner post must not return the
    -- controller borrowed by the still-running outer action.
    if active[c.slot] then return end
    frame.slot=c.slot;active[c.slot]=frame
    frame.after=cb.after
    cb.before(ctx)
   end)
   if not ok then
    -- A partial pre-hook must return P1 before the native function continues.
    if frame.after then
     local restored=pcall(frame.after)
     if restored then frame.after=nil;if active[frame.slot]==frame then active[frame.slot]=nil end end
    end
    log('Interaction pre-hook failed: '..tostring(err))
   end
  end,function()
   local frame=table.remove(frames)
   if frame and frame.epoch==epoch and frame.after then
    local ok,err=pcall(frame.after);if not ok then log('Interaction restore failed: '..tostring(err))end
   end
   if frame and frame.slot and active[frame.slot]==frame then active[frame.slot]=nil end
  end)
  hooked=true -- failed registration can be retried, as in the existing fix
 end
 function M.clear()
  epoch=epoch+1;claims={};owners={};frames={};active={}
 end
 return M
end
