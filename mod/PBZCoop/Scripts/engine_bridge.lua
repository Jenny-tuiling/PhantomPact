-- Derived game-facing helpers from PhantomPact 1.7.3; retained for compatibility.
return function()
-- PBZCoop: co-op proof of concept for Phantom Blade Zero (UE4SS Lua mod).
-- Written to be game-agnostic so it can be tested on any UE4/UE5 game first.
--
-- F6  PvP's page (pvppanel.lua); the "info" command prints player 1's character
-- F7  list characters near player 1 (finds enemy classes)
-- F8  spawn player 2: a second local player + a copy of player 1's character (F8-F11 need PBZCOOP_DEBUG=1)
-- F9  remove player 2

local VERSION = "local-0.1.0"
local TAG = "[PBZCoop] "
if (os.getenv("PBZCOOP_INSTANCE") or "1") ~= "1" then
    TAG = "[PBZCoop#" .. os.getenv("PBZCOOP_INSTANCE") .. "] "
end
local NEARBY_RADIUS = 5000      -- Unreal units (cm), used by F7
local P2_SPAWN_OFFSET = 200     -- how far beside player 1 to spawn player 2
local P2_CONTROLLER_ID = 1      -- local player index for player 2
-- true: keyboard/mouse drives player 1 and the FIRST gamepad drives player 2,
-- so one person with one controller can test co-op alone.
-- false: player 1 = gamepad 1, player 2 = gamepad 2.
local OFFSET_GAMEPADS = true

-- ESpawnActorCollisionHandlingMethod::AdjustIfPossibleButAlwaysSpawn
local SPAWN_ADJUST_ALWAYS = 2
local SCALE_MULTIPLY_WITH_ROOT = 1   -- ESpawnActorScaleMethod::MultiplyWithRoot (engine default)

local state = {
    p2Controller = nil,
    p2Pawn = nil,
}

local function log(msg)
    print(TAG .. msg .. "\n")
end

-- Safe for anything: a stale reference handed back mid-respawn once had an IsValid that wasn't a function
-- ("attempt to call a string value"), which broke that tick's whole snapshot read.
local function isValid(obj)
    return obj:IsValid()
end

local function valid(obj)
    if obj == nil or type(obj) == "string" or type(obj) == "number" or type(obj) == "boolean" then
        return false
    end
    local ok, result = pcall(isValid, obj)   -- (no closure: this runs hundreds of times a second)
    return ok and result == true
end

local function gameplayStatics()
    return StaticFindObject("/Script/Engine.Default__GameplayStatics")
end

local function applyGamepadOffset()
    local settings = StaticFindObject("/Script/EngineSettings.Default__GameMapsSettings")
    if settings ~= nil and settings:IsValid() then
        settings.bOffsetPlayerGamepadIds = OFFSET_GAMEPADS
    end
end

-- Player 1's controller is the one with ControllerId 0, not just the first one found,
-- because after F8 there are two PlayerControllers. Kept, because FindFirstOf takes about a millisecond and this runs
-- many times a frame: it's looked up again when it goes (a map change), and asked of the game every few seconds to be
-- sure. Only a controller that's gone needs the search: that search was a 10 ms frame every 5 s, in whichever stage came
-- first.
local PC_RECHECK_S = 5.0
local PC_SEARCH_S = 0.25          -- while there's no controller at all (loading): searched this often at most
local player1Pc, pcCheckedAt, pcSearchedAt = nil, -1e9, -1e9

local function getPlayer1()
    local now = os.clock()
    if not valid(player1Pc) then
        player1Pc = nil
        if now - pcSearchedAt < PC_SEARCH_S then
            return nil, nil
        end
        pcSearchedAt, pcCheckedAt = now, now
        local gs = gameplayStatics()
        local anyPc = FindFirstOf("PlayerController")
        if not valid(gs) or not valid(anyPc) then
            return nil, nil
        end
        local pc = gs:GetPlayerController(anyPc, 0)
        if not valid(pc) then
            return nil, nil
        end
        player1Pc = pc
    elseif now - pcCheckedAt >= PC_RECHECK_S then
        pcCheckedAt = now
        local gs = gameplayStatics()
        local pc = valid(gs) and gs:GetPlayerController(player1Pc, 0)
        if valid(pc) then
            player1Pc = pc
        end
    end
    local pawn = player1Pc.Pawn
    if not valid(pawn) then
        return player1Pc, nil
    end
    return player1Pc, pawn
end

local function fmtVec(v)
    return string.format("(%.0f, %.0f, %.0f)", v.X, v.Y, v.Z)
end

local function distance(a, b)
    local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- F6: what is the player character made of?
local function spawnBesidePlayer1(pawnClass)
    local pc, pawn = getPlayer1()
    if not valid(pawn) then
        log("No player 1 pawn to spawn beside.")
        return nil
    end
    if not valid(pawnClass) then
        log("Pawn class not found.")
        return nil
    end
    local gs = gameplayStatics()

    local loc = pawn:K2_GetActorLocation()
    local yaw = math.rad(pawn:K2_GetActorRotation().Yaw)
    local side = yaw + math.pi / 2
    local transform = {
        Rotation = { X = 0.0, Y = 0.0, Z = math.sin(yaw / 2), W = math.cos(yaw / 2) },
        Translation = {
            X = loc.X + math.cos(side) * P2_SPAWN_OFFSET,
            Y = loc.Y + math.sin(side) * P2_SPAWN_OFFSET,
            Z = loc.Z,
        },
        Scale3D = { X = 1.0, Y = 1.0, Z = 1.0 },
    }

    local actor
    local ok, err = pcall(function()
        -- UE 5.5+ added a TransformScaleMethod parameter to both calls (PBZ is 5.7, Wukong was 5.0).
        local newApi = pcall(function()
            actor = gs:BeginDeferredActorSpawnFromClass(pc, pawnClass, transform, SPAWN_ADJUST_ALWAYS, nil, SCALE_MULTIPLY_WITH_ROOT)
        end)
        if not newApi then
            actor = gs:BeginDeferredActorSpawnFromClass(pc, pawnClass, transform, SPAWN_ADJUST_ALWAYS, nil)
        end
        if not valid(actor) then
            error("BeginDeferredActorSpawnFromClass returned nothing")
        end
        if newApi then
            actor = gs:FinishSpawningActor(actor, transform, SCALE_MULTIPLY_WITH_ROOT)
        else
            actor = gs:FinishSpawningActor(actor, transform)
        end
        if not valid(actor) then
            error("FinishSpawningActor returned nothing")
        end
    end)
    if not ok then
        log("Spawning failed: " .. tostring(err))
        return nil
    end
    log("Spawned: " .. actor:GetFullName())

    -- The spawn transform's position is ignored in Wukong (the actor lands at the world
    -- origin), so place it explicitly, as UE4SS's SplitScreenMod does.
    local target = { X = transform.Translation.X, Y = transform.Translation.Y, Z = transform.Translation.Z }
    local facing = { Pitch = 0.0, Yaw = math.deg(yaw), Roll = 0.0 }
    actor:K2_SetActorLocationAndRotation(target, facing, false, {}, true)
    local actual = actor:K2_GetActorLocation()
    log(string.format("Placed at %s, %.0f cm from player 1.", fmtVec(actual), distance(actual, loc)))
    return actor
end


return {log=log,valid=valid,gs=gameplayStatics,getPlayer1=getPlayer1,distance=distance,
fmtVec=fmtVec,state=state,version=VERSION,spawnBesidePlayer1=spawnBesidePlayer1,
setGamepadOffset=function(on) OFFSET_GAMEPADS=on;applyGamepadOffset() end,
onGameThread=function(fn) return function(...) local args={...};ExecuteInGameThread(function()fn(table.unpack(args))end)end end}
end
