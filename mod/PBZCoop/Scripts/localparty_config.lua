-- Four-player configuration and viewport planning. No engine memory accesses.
-- Controller IDs are logical player IDs; native device routing must bind these.
local M = {}

function M.create(mode, pads)
    assert(mode == 'four_pads' or mode == 'keyboard_three_pads', 'Unknown input mode')
    local count = mode == 'four_pads' and 4 or 3
    assert(type(pads) == 'table' and #pads == count, 'Wrong number of gamepads')
    local players, used = {}, {}
    if mode == 'keyboard_three_pads' then
        players[1] = { player = 1, controllerId = 0, input = 'keyboard_mouse' }
    end
    for _, slot in ipairs(pads) do
        assert(type(slot) == 'number' and slot % 1 == 0 and slot >= 0 and slot <= 3,
            'XInput slot must be an integer from 0 through 3')
        assert(not used[slot], 'A gamepad cannot control two players')
        used[slot] = true
        local n = #players + 1
        players[n] = { player = n, controllerId = n - 1, input = 'gamepad', slot = slot }
    end
    return { mode = mode, players = players }
end

-- Rectangles in Windows desktop coordinates, ordered by player assignment.
-- Reject gaps/overlaps: a single spanning window must tile the four screens.
function M.viewports(screens)
    assert(type(screens) == 'table' and #screens == 4, 'Exactly four screens required')
    local left, top, right, bottom = math.huge, math.huge, -math.huge, -math.huge
    local area = 0
    for i, s in ipairs(screens) do
        assert(s.width > 0 and s.height > 0, 'Invalid screen dimensions')
        left, top = math.min(left, s.x), math.min(top, s.y)
        right, bottom = math.max(right, s.x + s.width), math.max(bottom, s.y + s.height)
        area = area + s.width * s.height
        for j = 1, i - 1 do
            local o = screens[j]
            assert(s.x >= o.x + o.width or o.x >= s.x + s.width or
                s.y >= o.y + o.height or o.y >= s.y + s.height, 'Screens overlap')
        end
    end
    local width, height = right - left, bottom - top
    assert(area == width * height, 'Arrange screens without gaps')
    local views = {}
    for i, s in ipairs(screens) do
        views[i] = { x = (s.x - left) / width, y = (s.y - top) / height,
            width = s.width / width, height = s.height / height }
    end
    return { x = left, y = top, width = width, height = height, views = views }
end

return M
