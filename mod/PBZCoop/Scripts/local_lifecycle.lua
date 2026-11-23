-- World-scoped work may never act on a later map, including same-map reloads.
return function()
 local M={epoch=1,loading=false}
 function M.leave()M.epoch=M.epoch+1;M.loading=true end
 function M.enter()M.loading=false end
 function M.token()if M.loading then return false end;return M.epoch end
 function M.accept(token)return token==M.epoch and not M.loading end
 return M
end
