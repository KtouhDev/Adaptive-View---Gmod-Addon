PM_EBLANSKY_ADAPTIVE_VIEW = PM_EBLANSKY_ADAPTIVE_VIEW or {}

local AV = PM_EBLANSKY_ADAPTIVE_VIEW
local NET_SETTINGS = "pmav_settings"
local NET_BOUNDS = "pmav_bounds"
local GetRule
AV.ModelCollisionBounds = {}
AV.Generation = (AV.Generation or 0) + 1
local GENERATION = AV.Generation

if SERVER then
    AddCSLuaFile("autorun/client/pm_eblansky_adaptive_view.lua")
    util.AddNetworkString(NET_SETTINGS)
    util.AddNetworkString(NET_BOUNDS)

    local entityMeta = FindMetaTable("Entity")

    if entityMeta and not AV.CollisionBoundsPatched then
        AV.OriginalSetCollisionBounds = AV.OriginalSetCollisionBounds or entityMeta.SetCollisionBounds

        function entityMeta:SetCollisionBounds(mins, maxs)
            if not AV.InternalCollisionApply and IsValid(self) and self.pmavBlockExternalCollisionBounds then
                return
            end

            return AV.OriginalSetCollisionBounds(self, mins, maxs)
        end

        AV.CollisionBoundsPatched = true
    end
end

local function NormalizeModel(model)
    return string.lower(string.Trim(tostring(model or "")))
end

local function NumberOr(value, fallback)
    value = tonumber(value)

    if value == nil then
        return fallback
    end

    return value
end

local function GetStableModelBounds(ent, fallbackMins, fallbackMaxs)
    if not IsValid(ent) then
        return fallbackMins, fallbackMaxs
    end

    local model = NormalizeModel(ent:GetModel())

    if model == "" then
        return fallbackMins, fallbackMaxs
    end

    local cached = AV.ModelCollisionBounds[model]

    if cached then
        return Vector(cached.mins.x, cached.mins.y, cached.mins.z), Vector(cached.maxs.x, cached.maxs.y, cached.maxs.z)
    end

    local mins, maxs = ent:GetModelBounds()

    mins = mins or fallbackMins or Vector(-16, -16, 0)
    maxs = maxs or fallbackMaxs or Vector(16, 16, 72)

    cached = {
        mins = Vector(mins.x, mins.y, mins.z),
        maxs = Vector(maxs.x, maxs.y, maxs.z)
    }
    AV.ModelCollisionBounds[model] = cached

    return Vector(cached.mins.x, cached.mins.y, cached.mins.z), Vector(cached.maxs.x, cached.maxs.y, cached.maxs.z)
end

local function GetSaneHorizontalBounds(modelMins, modelMaxs, defaultMins, defaultMaxs)
    local minX = NumberOr(modelMins and modelMins.x, defaultMins.x)
    local minY = NumberOr(modelMins and modelMins.y, defaultMins.y)
    local maxX = NumberOr(modelMaxs and modelMaxs.x, defaultMaxs.x)
    local maxY = NumberOr(modelMaxs and modelMaxs.y, defaultMaxs.y)
    local halfX = math.max(math.abs(minX), math.abs(maxX))
    local halfY = math.max(math.abs(minY), math.abs(maxY))

    -- Some models report broken bounds: tiny foot-only boxes, or giant boxes
    -- caused by accessories/weapons. Use the smaller sane axis when one axis
    -- explodes, then clamp to movement-friendly player hull sizes.
    local smaller = math.min(halfX, halfY)
    local larger = math.max(halfX, halfY)

    if smaller > 0 and larger / smaller > 2.25 then
        halfX = smaller
        halfY = smaller
    end

    halfX = math.Clamp(halfX, 12, 32)
    halfY = math.Clamp(halfY, 12, 32)

    return -halfX, -halfY, halfX, halfY
end

local function GetCollisionBodyHeight(ent, settings, modelMaxs, fallbackHeight)
    local rule = GetRule(settings, ent:GetModel())

    if rule and rule.mode == "height" then
        return rule.height + settings.globalOffset + (rule.offset or 0)
    end

    local modelHeight = NumberOr(modelMaxs and modelMaxs.z, fallbackHeight or 72)

    return math.Clamp(modelHeight + settings.globalOffset + (rule and rule.offset or 0), 12, 180)
end

local function NearlyEqualVector(a, b, epsilon)
    epsilon = epsilon or 0.01

    return math.abs(a.x - b.x) <= epsilon and math.abs(a.y - b.y) <= epsilon and math.abs(a.z - b.z) <= epsilon
end

local function BroadcastBounds(ent, mins, maxs, duckMins, duckMaxs)
    net.Start(NET_BOUNDS)
    net.WriteEntity(ent)
    net.WriteVector(mins)
    net.WriteVector(maxs)
    net.WriteBool(duckMins ~= nil and duckMaxs ~= nil)

    if duckMins and duckMaxs then
        net.WriteVector(duckMins)
        net.WriteVector(duckMaxs)
    end

    net.Broadcast()
end

local function SetPlayerHullStable(ply, mins, maxs, duckMins, duckMaxs)
    local actualMins, actualMaxs = ply:GetHull()
    local actualDuckMins, actualDuckMaxs = ply:GetHullDuck()
    local actualMatches = NearlyEqualVector(actualMins, mins) and
        NearlyEqualVector(actualMaxs, maxs) and
        NearlyEqualVector(actualDuckMins, duckMins) and
        NearlyEqualVector(actualDuckMaxs, duckMaxs)

    if ply.pmavLastHullMins and
        NearlyEqualVector(ply.pmavLastHullMins, mins) and
        NearlyEqualVector(ply.pmavLastHullMaxs, maxs) and
        NearlyEqualVector(ply.pmavLastDuckMins, duckMins) and
        NearlyEqualVector(ply.pmavLastDuckMaxs, duckMaxs) and
        actualMatches then
        BroadcastBounds(ply, mins, maxs, duckMins, duckMaxs)
        return
    end

    ply.pmavLastHullMins = Vector(mins.x, mins.y, mins.z)
    ply.pmavLastHullMaxs = Vector(maxs.x, maxs.y, maxs.z)
    ply.pmavLastDuckMins = Vector(duckMins.x, duckMins.y, duckMins.z)
    ply.pmavLastDuckMaxs = Vector(duckMaxs.x, duckMaxs.y, duckMaxs.z)

    ply:SetHull(mins, maxs)
    ply:SetHullDuck(duckMins, duckMaxs)

    BroadcastBounds(ply, mins, maxs, duckMins, duckMaxs)
end

local function SetPlayerViewOffsetsStable(ply, stand, duck)
    local actualStand = ply:GetViewOffset()
    local actualDuck = ply:GetViewOffsetDucked()
    local actualMatches = NearlyEqualVector(actualStand, stand) and NearlyEqualVector(actualDuck, duck)

    if ply.pmavLastStandOffset and
        NearlyEqualVector(ply.pmavLastStandOffset, stand) and
        NearlyEqualVector(ply.pmavLastDuckOffset, duck) and
        actualMatches then
        return
    end

    ply.pmavLastStandOffset = Vector(stand.x, stand.y, stand.z)
    ply.pmavLastDuckOffset = Vector(duck.x, duck.y, duck.z)

    ply:SetViewOffset(stand)
    ply:SetViewOffsetDucked(duck)
end

local function SetEntityCollisionBoundsStable(ent, mins, maxs)
    if ent.pmavLastBoundsMins and
        NearlyEqualVector(ent.pmavLastBoundsMins, mins) and
        NearlyEqualVector(ent.pmavLastBoundsMaxs, maxs) then
        BroadcastBounds(ent, mins, maxs)
        return
    end

    ent.pmavLastBoundsMins = Vector(mins.x, mins.y, mins.z)
    ent.pmavLastBoundsMaxs = Vector(maxs.x, maxs.y, maxs.z)
    ent.pmavAdaptiveBoundsApplied = true
    ent.pmavBlockExternalCollisionBounds = true

    AV.InternalCollisionApply = true
    ent:SetCollisionBounds(mins, maxs)
    AV.InternalCollisionApply = false

    BroadcastBounds(ent, mins, maxs)
end

local function IsPointInsideBounds(localPos, mins, maxs, padding)
    padding = padding or 0

    return localPos.x >= mins.x - padding and localPos.x <= maxs.x + padding and
        localPos.y >= mins.y - padding and localPos.y <= maxs.y + padding and
        localPos.z >= mins.z - padding and localPos.z <= maxs.z + padding
end

local function IsUsableDamagePoint(pos)
    return pos and pos ~= vector_origin and pos.x == pos.x and pos.y == pos.y and pos.z == pos.z
end

local function IsWorldPointInsideAdaptiveBounds(ent, pos, padding)
    return IsUsableDamagePoint(pos) and IsPointInsideBounds(ent:WorldToLocal(pos), ent.pmavLastBoundsMins, ent.pmavLastBoundsMaxs, padding or 1)
end

local function RayIntersectsAdaptiveBounds(ent, startPos, direction, padding)
    if not IsUsableDamagePoint(startPos) or not direction then
        return false
    end

    padding = padding or 1

    local localStart = ent:WorldToLocal(startPos)
    local localEnd = ent:WorldToLocal(startPos + direction * 32768)
    local localDir = localEnd - localStart

    if localDir:LengthSqr() <= 0.0001 then
        return false
    end

    localDir:Normalize()

    local mins = Vector(
        ent.pmavLastBoundsMins.x - padding,
        ent.pmavLastBoundsMins.y - padding,
        ent.pmavLastBoundsMins.z - padding
    )
    local maxs = Vector(
        ent.pmavLastBoundsMaxs.x + padding,
        ent.pmavLastBoundsMaxs.y + padding,
        ent.pmavLastBoundsMaxs.z + padding
    )

    local tMin = 0
    local tMax = 32768

    local function testAxis(startValue, dirValue, minValue, maxValue)
        if math.abs(dirValue) < 0.000001 then
            return startValue >= minValue and startValue <= maxValue, tMin, tMax
        end

        local inv = 1 / dirValue
        local t1 = (minValue - startValue) * inv
        local t2 = (maxValue - startValue) * inv

        if t1 > t2 then
            t1, t2 = t2, t1
        end

        tMin = math.max(tMin, t1)
        tMax = math.min(tMax, t2)

        return tMin <= tMax, tMin, tMax
    end

    local ok = testAxis(localStart.x, localDir.x, mins.x, maxs.x)

    if not ok then
        return false
    end

    ok = testAxis(localStart.y, localDir.y, mins.y, maxs.y)

    if not ok then
        return false
    end

    ok = testAxis(localStart.z, localDir.z, mins.z, maxs.z)

    return ok
end

local function ShouldBlockAdaptiveDamage(ent, dmginfo)
    if not IsValid(ent) or ent:IsPlayer() or not ent.pmavAdaptiveBoundsApplied then
        return false
    end

    if not ent.pmavLastBoundsMins or not ent.pmavLastBoundsMaxs or not dmginfo then
        return false
    end

    local attacker = dmginfo:GetAttacker()

    if IsValid(attacker) and attacker:IsPlayer() and isfunction(attacker.GetAimVector) then
        local startPos = isfunction(attacker.GetShootPos) and attacker:GetShootPos() or attacker:EyePos()
        local direction = attacker:GetAimVector()

        return not RayIntersectsAdaptiveBounds(ent, startPos, direction, 1)
    end

    if ent.pmavLastBulletHitPos and ent.pmavLastBulletHitTime and CurTime() - ent.pmavLastBulletHitTime <= 0.1 then
        return not IsWorldPointInsideAdaptiveBounds(ent, ent.pmavLastBulletHitPos, 1)
    end

    if IsValid(attacker) and attacker:IsPlayer() and isfunction(attacker.GetEyeTrace) then
        local trace = attacker:GetEyeTrace()

        if trace and trace.Entity == ent and IsUsableDamagePoint(trace.HitPos) then
            return not IsWorldPointInsideAdaptiveBounds(ent, trace.HitPos, 1)
        end
    end

    local candidatePositions = {}

    if isfunction(dmginfo.GetDamagePosition) then
        candidatePositions[#candidatePositions + 1] = dmginfo:GetDamagePosition()
    end

    if isfunction(dmginfo.GetReportedPosition) then
        candidatePositions[#candidatePositions + 1] = dmginfo:GetReportedPosition()
    end

    local checkedAny = false

    for _, pos in ipairs(candidatePositions) do
        if IsUsableDamagePoint(pos) then
            checkedAny = true

            if IsWorldPointInsideAdaptiveBounds(ent, pos, 1) then
                return false
            end
        end
    end

    return checkedAny
end

local function InvalidatePlayerStableState(ply)
    if not IsValid(ply) then
        return
    end

    ply.pmavLastHullMins = nil
    ply.pmavLastHullMaxs = nil
    ply.pmavLastDuckMins = nil
    ply.pmavLastDuckMaxs = nil
    ply.pmavLastStandOffset = nil
    ply.pmavLastDuckOffset = nil
end

local function SanitizeRule(rule)
    if not istable(rule) then
        return nil
    end

    local mode = tostring(rule.mode or "auto")

    if mode ~= "auto" and mode ~= "height" and mode ~= "off" then
        mode = "auto"
    end

    return {
        mode = mode,
        height = math.Clamp(NumberOr(rule.height, 64), 0, 160),
        offset = math.Clamp(NumberOr(rule.offset, 0), -64, 64)
    }
end

local function SanitizeSettings(settings)
    settings = istable(settings) and settings or {}

    local rules = {}

    if istable(settings.rules) then
        for model, rule in pairs(settings.rules) do
            model = NormalizeModel(model)
            rule = SanitizeRule(rule)

            if model ~= "" and rule then
                rules[model] = rule
            end
        end
    end

    return {
        enabled = settings.enabled ~= false,
        autoScale = math.Clamp(NumberOr(settings.autoScale, 0.92), 0.1, 2),
        globalOffset = math.Clamp(NumberOr(settings.globalOffset, 0), -64, 64),
        minHeight = math.Clamp(NumberOr(settings.minHeight, 4), 0, 120),
        maxHeight = math.Clamp(NumberOr(settings.maxHeight, 120), 8, 180),
        clientHeight = math.Clamp(NumberOr(settings.clientHeight, 0), 0, 180),
        smooth = math.Clamp(NumberOr(settings.smooth, 10), 0, 30),
        collision = settings.collision ~= false,
        collisionMode = math.Clamp(math.floor(NumberOr(settings.collisionMode, 3)), 0, 3),
        collisionRadius = math.Clamp(NumberOr(settings.collisionRadius, 16), 0, 24),
        collisionOnlyPlayers = settings.collisionOnlyPlayers == true,
        npcCollision = settings.npcCollision ~= false,
        multiplayerSafe = settings.multiplayerSafe ~= false,
        rules = rules
    }
end

GetRule = function(settings, model)
    return settings.rules[NormalizeModel(model)]
end

local function GetBoneHeight(ply, boneName, extra)
    local bone = ply:LookupBone(boneName)

    if not bone then
        return nil
    end

    local bonePos = ply:GetBonePosition(bone)

    if not bonePos or bonePos == vector_origin then
        return nil
    end

    return bonePos.z - ply:GetPos().z + extra
end

local function GetAttachmentHeight(ply, attachmentName)
    local attachmentID = ply:LookupAttachment(attachmentName)

    if not attachmentID or attachmentID <= 0 then
        return nil
    end

    local attachment = ply:GetAttachment(attachmentID)

    if not attachment or not attachment.Pos then
        return nil
    end

    return attachment.Pos.z - ply:GetPos().z
end

local function GetModelAutoHeight(ply, settings)
    if settings.clientHeight and settings.clientHeight > 0 then
        return math.Clamp(settings.clientHeight, settings.minHeight, math.max(settings.maxHeight, settings.minHeight))
    end

    if isfunction(ply.SetupBones) then
        ply:SetupBones()
    end

    local modelHeight =
        GetAttachmentHeight(ply, "eyes") or
        GetAttachmentHeight(ply, "forward") or
        GetBoneHeight(ply, "ValveBiped.Bip01_Head1", 2) or
        GetBoneHeight(ply, "ValveBiped.Bip01_Neck1", 7)

    if not modelHeight then
        local _, maxs = ply:GetModelBounds()
        modelHeight = math.max(NumberOr(maxs and maxs.z, 72) * settings.autoScale, 1)
    end

    local minHeight = settings.minHeight
    local maxHeight = math.max(settings.maxHeight, minHeight)

    return math.Clamp(modelHeight, minHeight, maxHeight)
end

local function GetTargetHeights(ply, settings)
    local rule = GetRule(settings, ply:GetModel())

    if not settings.enabled or rule and rule.mode == "off" then
        return nil
    end

    local standHeight = rule and rule.mode == "height" and rule.height or GetModelAutoHeight(ply, settings)
    standHeight = standHeight + settings.globalOffset + (rule and rule.offset or 0)

    local mins, maxs = ply:GetModelBounds()
    mins = mins or Vector(0, 0, 0)
    maxs = maxs or Vector(16, 16, 72)

    local footSafeHeight = math.max(NumberOr(mins.z, 0) + 8, 4)
    standHeight = math.Clamp(standHeight, footSafeHeight, math.max(settings.maxHeight, footSafeHeight))

    local defaultStand = ply.pmavDefaultStand or Vector(0, 0, 64)
    local defaultDuck = ply.pmavDefaultDuck or Vector(0, 0, 28)
    local duckRatio = defaultStand.z ~= 0 and defaultDuck.z / defaultStand.z or 0.4375
    local duckHeight = math.max(standHeight * duckRatio, footSafeHeight)

    return standHeight, duckHeight, mins, maxs
end

local function GetEntityTargetHeight(ent, settings, modelMins, modelMaxs)
    local rule = GetRule(settings, ent:GetModel())

    if not settings.enabled or rule and rule.mode == "off" then
        return nil
    end

    local targetHeight = rule and rule.mode == "height" and rule.height or
        math.max(NumberOr(modelMaxs and modelMaxs.z, 72) * settings.autoScale, 1)

    targetHeight = targetHeight + settings.globalOffset + (rule and rule.offset or 0)

    local footSafeHeight = math.max(NumberOr(modelMins and modelMins.z, 0) + 8, 4)

    return math.Clamp(targetHeight, footSafeHeight, math.max(settings.maxHeight, footSafeHeight))
end

if CLIENT then
    AV.BuildSettingsPayload = function()
        return SanitizeSettings({
            enabled = GetConVar("pmav_enabled"):GetBool(),
            autoScale = GetConVar("pmav_auto_scale"):GetFloat(),
            globalOffset = GetConVar("pmav_global_offset"):GetFloat(),
            minHeight = GetConVar("pmav_min_height"):GetFloat(),
            maxHeight = GetConVar("pmav_max_height"):GetFloat(),
            clientHeight = AV.GetLocalAutoHeight and AV.GetLocalAutoHeight() or 0,
            smooth = 10,
            collision = GetConVar("pmav_collision"):GetBool(),
            collisionMode = GetConVar("pmav_collision_mode"):GetInt(),
            collisionRadius = GetConVar("pmav_collision_radius"):GetFloat(),
            collisionOnlyPlayers = GetConVar("pmav_collision_only_players"):GetBool(),
            npcCollision = GetConVar("pmav_npc_collision"):GetBool(),
            multiplayerSafe = GetConVar("pmav_multiplayer_safe"):GetBool(),
            rules = AV.ModelRules or {}
        })
    end

    function AV.SyncSettingsToServer()
        if not net then
            return
        end

        local payload = AV.BuildSettingsPayload()

        timer.Simple(0, function()
            net.Start(NET_SETTINGS)
            net.WriteTable(payload)
            net.SendToServer()
        end)
    end

    return
end

AV.PlayerSettings = AV.PlayerSettings or {}
AV.SharedSettings = AV.SharedSettings or SanitizeSettings({})
AV.ManagedEntities = AV.ManagedEntities or {}

local function CopySettingsForWorld(settings)
    local copied = table.Copy(settings or AV.SharedSettings or SanitizeSettings({}))
    copied.clientHeight = 0

    return SanitizeSettings(copied)
end

local function GetSettingsForPlayer(ply)
    if ply:IsBot() then
        return CopySettingsForWorld(AV.SharedSettings)
    end

    return AV.PlayerSettings[ply]
end

local function CaptureDefaults(ply)
    if ply.pmavDefaultsCaptured then
        return
    end

    ply.pmavDefaultsCaptured = true
    ply.pmavDefaultStand = ply:GetViewOffset()
    ply.pmavDefaultDuck = ply:GetViewOffsetDucked()

    if isfunction(ply.GetHull) then
        ply.pmavDefaultHullMins, ply.pmavDefaultHullMaxs = ply:GetHull()
    end

    if isfunction(ply.GetHullDuck) then
        ply.pmavDefaultDuckMins, ply.pmavDefaultDuckMaxs = ply:GetHullDuck()
    end

    ply.pmavDefaultHullMins = ply.pmavDefaultHullMins or Vector(-16, -16, 0)
    ply.pmavDefaultHullMaxs = ply.pmavDefaultHullMaxs or Vector(16, 16, 72)
    ply.pmavDefaultDuckMins = ply.pmavDefaultDuckMins or Vector(-16, -16, 0)
    ply.pmavDefaultDuckMaxs = ply.pmavDefaultDuckMaxs or Vector(16, 16, 36)
end

local function RestorePlayer(ply)
    if not IsValid(ply) or not ply.pmavDefaultsCaptured then
        return
    end

    SetPlayerViewOffsetsStable(ply, ply.pmavDefaultStand, ply.pmavDefaultDuck)
    SetPlayerHullStable(ply, ply.pmavDefaultHullMins, ply.pmavDefaultHullMaxs, ply.pmavDefaultDuckMins, ply.pmavDefaultDuckMaxs)
end

local function ApplyPlayer(ply)
    if not IsValid(ply) then
        return
    end

    CaptureDefaults(ply)

    local settings = GetSettingsForPlayer(ply)

    if not settings then
        RestorePlayer(ply)
        return
    end

    local standHeight, duckHeight = GetTargetHeights(ply, settings)

    if not standHeight then
        RestorePlayer(ply)
        return
    end

    SetPlayerViewOffsetsStable(
        ply,
        Vector(ply.pmavDefaultStand.x, ply.pmavDefaultStand.y, standHeight),
        Vector(ply.pmavDefaultDuck.x, ply.pmavDefaultDuck.y, duckHeight)
    )

    if settings.collision and settings.collisionMode > 0 then
        local resizeHeight = settings.collisionMode == 1 or settings.collisionMode == 3
        local resizeWidth = settings.collisionMode == 2 or settings.collisionMode == 3
        local modelMins, modelMaxs = GetStableModelBounds(ply, ply.pmavDefaultHullMins, ply.pmavDefaultHullMaxs)
        local rule = GetRule(settings, ply:GetModel())
        local bodyHeight = rule and rule.mode == "height" and
            rule.height + settings.globalOffset + (rule.offset or 0) or
            standHeight
        local hullHeight = resizeHeight and math.Clamp(bodyHeight + 6, 18, 180) or ply.pmavDefaultHullMaxs.z
        local duckHullHeight = resizeHeight and math.Clamp(math.min(duckHeight + 6, hullHeight), 12, 120) or ply.pmavDefaultDuckMaxs.z
        local hullMins = ply.pmavDefaultHullMins
        local duckHullMins = ply.pmavDefaultDuckMins
        local hullMaxs = Vector(ply.pmavDefaultHullMaxs.x, ply.pmavDefaultHullMaxs.y, hullHeight)
        local duckHullMaxs = Vector(ply.pmavDefaultDuckMaxs.x, ply.pmavDefaultDuckMaxs.y, duckHullHeight)

        if resizeWidth then
            local minX, minY, maxX, maxY = GetSaneHorizontalBounds(modelMins, modelMaxs, ply.pmavDefaultHullMins, ply.pmavDefaultHullMaxs)

            if settings.multiplayerSafe and game.MaxPlayers() > 1 and not ply:IsBot() then
                minX = math.min(minX, ply.pmavDefaultHullMins.x)
                minY = math.min(minY, ply.pmavDefaultHullMins.y)
                maxX = math.max(maxX, ply.pmavDefaultHullMaxs.x)
                maxY = math.max(maxY, ply.pmavDefaultHullMaxs.y)
            end

            hullMins = Vector(minX, minY, ply.pmavDefaultHullMins.z)
            hullMaxs.x = maxX
            hullMaxs.y = maxY
            duckHullMins = Vector(minX, minY, ply.pmavDefaultDuckMins.z)
            duckHullMaxs.x = maxX
            duckHullMaxs.y = maxY
        end

        SetPlayerHullStable(ply, hullMins, hullMaxs, duckHullMins, duckHullMaxs)
    else
        SetPlayerHullStable(ply, ply.pmavDefaultHullMins, ply.pmavDefaultHullMaxs, ply.pmavDefaultDuckMins, ply.pmavDefaultDuckMaxs)
    end
end

local function IsAdaptiveWorldEntity(ent)
    if not IsValid(ent) or ent:IsPlayer() or ent:IsWeapon() then
        return false
    end

    local class = ent:GetClass()

    local isNextBot = isfunction(ent.IsNextBot) and ent:IsNextBot()

    return ent:IsNPC() or isNextBot or string.find(class, "npc", 1, true) or string.find(class, "nextbot", 1, true)
end

local function CaptureEntityDefaults(ent)
    if ent.pmavBoundsCaptured then
        return
    end

    ent.pmavBoundsCaptured = true
    ent.pmavDefaultCollisionMins, ent.pmavDefaultCollisionMaxs = ent:GetCollisionBounds()

    if not ent.pmavDefaultCollisionMins or not ent.pmavDefaultCollisionMaxs or ent.pmavDefaultCollisionMaxs:LengthSqr() <= 0.01 then
        ent.pmavDefaultCollisionMins = Vector(-16, -16, 0)
        ent.pmavDefaultCollisionMaxs = Vector(16, 16, 72)
    end
end

local function RestoreEntity(ent)
    if not IsValid(ent) or not ent.pmavBoundsCaptured or not ent.pmavAdaptiveBoundsApplied then
        return
    end

    ent.pmavLastBoundsMins = Vector(ent.pmavDefaultCollisionMins.x, ent.pmavDefaultCollisionMins.y, ent.pmavDefaultCollisionMins.z)
    ent.pmavLastBoundsMaxs = Vector(ent.pmavDefaultCollisionMaxs.x, ent.pmavDefaultCollisionMaxs.y, ent.pmavDefaultCollisionMaxs.z)
    ent.pmavAdaptiveBoundsApplied = false
    ent.pmavBlockExternalCollisionBounds = false

    AV.InternalCollisionApply = true
    ent:SetCollisionBounds(ent.pmavDefaultCollisionMins, ent.pmavDefaultCollisionMaxs)
    AV.InternalCollisionApply = false
    BroadcastBounds(ent, ent.pmavDefaultCollisionMins, ent.pmavDefaultCollisionMaxs)
end

local function ApplyEntity(ent)
    if not IsAdaptiveWorldEntity(ent) then
        return
    end

    AV.ManagedEntities[ent] = true
    CaptureEntityDefaults(ent)

    local settings = CopySettingsForWorld(AV.SharedSettings)
    local rule = GetRule(settings, ent:GetModel())

    if settings.collisionOnlyPlayers or not settings.npcCollision or not settings.enabled or rule and rule.mode == "off" or not settings.collision or settings.collisionMode <= 0 then
        RestoreEntity(ent)
        return
    end

    local resizeHeight = settings.collisionMode == 1 or settings.collisionMode == 3
    local resizeWidth = settings.collisionMode == 2 or settings.collisionMode == 3
    local modelMins, modelMaxs = GetStableModelBounds(ent, Vector(-16, -16, 0), Vector(16, 16, 72))

    local targetHeight = GetEntityTargetHeight(ent, settings, modelMins, modelMaxs)

    if not targetHeight then
        RestoreEntity(ent)
        return
    end

    local mins = Vector(-16, -16, ent.pmavDefaultCollisionMins.z)
    local maxs = Vector(16, 16, resizeHeight and math.Clamp(targetHeight + 6, 18, 180) or ent.pmavDefaultCollisionMaxs.z)

    if resizeWidth then
        local minX, minY, maxX, maxY = GetSaneHorizontalBounds(modelMins, modelMaxs, ent.pmavDefaultCollisionMins, ent.pmavDefaultCollisionMaxs)

        mins.x = minX
        mins.y = minY
        maxs.x = maxX
        maxs.y = maxY
    end

    SetEntityCollisionBoundsStable(ent, mins, maxs)
end

local function ScheduleEntityApply(ent)
    timer.Simple(1, function()
        if AV.Generation ~= GENERATION then
            return
        end

        ApplyEntity(ent)
    end)
end

local function ScheduleAllEntitiesApply()
    timer.Simple(0, function()
        if AV.Generation ~= GENERATION then
            return
        end

        for _, ent in ipairs(ents.GetAll()) do
            ApplyEntity(ent)
        end
    end)
end

local function GetWorldSettingsSignature(settings)
    settings = settings or AV.SharedSettings or SanitizeSettings({})
    local ruleParts = {}

    for model, rule in SortedPairs(settings.rules or {}) do
        ruleParts[#ruleParts + 1] = table.concat({
            NormalizeModel(model),
            tostring(rule.mode or ""),
            tostring(math.Round(NumberOr(rule.height, 0), 3)),
            tostring(math.Round(NumberOr(rule.offset, 0), 3))
        }, ":")
    end

    return table.concat({
        settings.enabled and "1" or "0",
        settings.collision and "1" or "0",
        tostring(settings.collisionMode or 0),
        settings.collisionOnlyPlayers and "1" or "0",
        settings.npcCollision and "1" or "0",
        tostring(settings.autoScale or 0),
        tostring(settings.globalOffset or 0),
        tostring(settings.minHeight or 0),
        tostring(settings.maxHeight or 0),
        table.concat(ruleParts, ",")
    }, "|")
end

local function SmoothApplyPlayer(ply, fromStand, fromDuck, toStand, toDuck, settings)
    local duration = 0

    if duration <= 0 then
        ApplyPlayer(ply)
        return
    end

    local started = CurTime()
    local timerName = "pmav_smooth_" .. ply:EntIndex()

    timer.Remove(timerName)
    timer.Create(timerName, 0, 0, function()
        if not IsValid(ply) then
            timer.Remove(timerName)
            return
        end

        if AV.Generation ~= GENERATION then
            timer.Remove(timerName)
            return
        end

        local progress = math.Clamp((CurTime() - started) / duration, 0, 1)
        progress = 1 - (1 - progress) * (1 - progress)

        ply:SetViewOffset(Vector(ply.pmavDefaultStand.x, ply.pmavDefaultStand.y, Lerp(progress, fromStand, toStand)))
        ply:SetViewOffsetDucked(Vector(ply.pmavDefaultDuck.x, ply.pmavDefaultDuck.y, Lerp(progress, fromDuck, toDuck)))

        if progress >= 1 then
            timer.Remove(timerName)
            ApplyPlayer(ply)
        end
    end)
end

local function GetAppliedHeights(ply)
    return ply:GetViewOffset().z, ply:GetViewOffsetDucked().z
end

net.Receive(NET_SETTINGS, function(_, ply)
    CaptureDefaults(ply)

    local oldEnabled = AV.PlayerSettings[ply] and AV.PlayerSettings[ply].enabled
    local fromStand, fromDuck = GetAppliedHeights(ply)
    AV.PlayerSettings[ply] = SanitizeSettings(net.ReadTable())
    local settings = AV.PlayerSettings[ply]
    local oldWorldSignature = AV.WorldSettingsSignature
    AV.SharedSettings = CopySettingsForWorld(settings)
    local newWorldSignature = GetWorldSettingsSignature(AV.SharedSettings)
    local toStand, toDuck = GetTargetHeights(ply, settings)
    local smoothing = false

    if not toStand then
        toStand = ply.pmavDefaultStand.z
        toDuck = ply.pmavDefaultDuck.z
    end

    if oldEnabled ~= nil and oldEnabled ~= settings.enabled then
        smoothing = true
        SmoothApplyPlayer(ply, fromStand, fromDuck, toStand, toDuck, settings)
    else
        ApplyPlayer(ply)
    end

    if not smoothing then
        timer.Simple(0, function()
            if AV.Generation ~= GENERATION then
                return
            end

            ApplyPlayer(ply)
        end)
    end

    if oldWorldSignature ~= newWorldSignature then
        AV.WorldSettingsSignature = newWorldSignature
        ScheduleAllEntitiesApply()
    end
end)

hook.Add("OnEntityCreated", "pm_eblansky_adaptive_view_entities", function(ent)
    ScheduleEntityApply(ent)
end)

hook.Add("EntityRemoved", "pm_eblansky_adaptive_view_entities", function(ent)
    AV.ManagedEntities[ent] = nil
end)

hook.Add("EntityFireBullets", "pm_eblansky_adaptive_view_bullet_bounds", function(_, data)
    if not data then
        return
    end

    local oldCallback = data.Callback

    data.Callback = function(attacker, trace, dmginfo)
        if trace and IsValid(trace.Entity) and trace.Entity.pmavAdaptiveBoundsApplied and IsUsableDamagePoint(trace.HitPos) then
            trace.Entity.pmavLastBulletHitPos = trace.HitPos
            trace.Entity.pmavLastBulletHitTime = CurTime()

            if not IsWorldPointInsideAdaptiveBounds(trace.Entity, trace.HitPos, 1) and dmginfo then
                dmginfo:SetDamage(0)
            end
        end

        if isfunction(oldCallback) then
            return oldCallback(attacker, trace, dmginfo)
        end
    end

    return true
end)

hook.Add("ScaleNPCDamage", "pm_eblansky_adaptive_view_damage_bounds", function(npc, _, dmginfo)
    if ShouldBlockAdaptiveDamage(npc, dmginfo) then
        dmginfo:SetDamage(0)
        return true
    end
end)

hook.Add("EntityTakeDamage", "pm_eblansky_adaptive_view_damage_bounds", function(ent, dmginfo)
    if ShouldBlockAdaptiveDamage(ent, dmginfo) then
        dmginfo:SetDamage(0)
        return true
    end
end)

hook.Add("PlayerSpawn", "pm_eblansky_adaptive_view", function(ply)
    InvalidatePlayerStableState(ply)

    timer.Simple(0, function()
        if AV.Generation ~= GENERATION then
            return
        end

        ApplyPlayer(ply)
    end)

    timer.Simple(0.25, function()
        if AV.Generation ~= GENERATION then
            return
        end

        ApplyPlayer(ply)
    end)

    timer.Simple(1, function()
        if AV.Generation ~= GENERATION then
            return
        end

        ApplyPlayer(ply)
    end)
end)

hook.Add("PlayerSetModel", "pm_eblansky_adaptive_view", function(ply)
    InvalidatePlayerStableState(ply)

    timer.Simple(0, function()
        if AV.Generation ~= GENERATION then
            return
        end

        ApplyPlayer(ply)
    end)

    timer.Simple(0.25, function()
        if AV.Generation ~= GENERATION then
            return
        end

        ApplyPlayer(ply)
    end)

    timer.Simple(1, function()
        if AV.Generation ~= GENERATION then
            return
        end

        ApplyPlayer(ply)
    end)
end)

hook.Add("PlayerDeath", "pm_eblansky_adaptive_view", function(ply)
    InvalidatePlayerStableState(ply)
end)

hook.Add("PlayerDisconnected", "pm_eblansky_adaptive_view", function(ply)
    AV.PlayerSettings[ply] = nil
end)
