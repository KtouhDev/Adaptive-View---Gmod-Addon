PM_EBLANSKY_ADAPTIVE_VIEW = PM_EBLANSKY_ADAPTIVE_VIEW or {}

local AV = PM_EBLANSKY_ADAPTIVE_VIEW
local NET_SETTINGS = "pmav_settings"
local NET_BOUNDS = "pmav_bounds"
local GetRule
AV.ModelCollisionBounds = {}
AV.Generation = (AV.Generation or 0) + 1
local GENERATION = AV.Generation
local MIN_SPEED_SCALE = 0.75
local MAX_SPEED_SCALE = 1.3
local MIN_JUMP_SCALE = 0.85
local MAX_JUMP_SCALE = 1.15
local SOURCE_UNIT_METERS = 0.01905
local ENTITY_DAMAGE_BOUNDS_GRACE = 2
local MAX_NET_SETTINGS_BITS = 1024 * 1024
local NET_SETTINGS_COOLDOWN = 0.25
local MAX_MODEL_RULES = 512

if SERVER then
    AddCSLuaFile("autorun/client/pm_eblansky_adaptive_view.lua")
    util.AddNetworkString(NET_SETTINGS)
    util.AddNetworkString(NET_BOUNDS)
    CreateConVar("pmav_alladmins", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Allow non-admin players to edit Adaptive View settings when sv_cheats is also enabled.")
    CreateConVar("pmav_injail", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Lock Adaptive View settings menu for everyone.")
    CreateConVar("pmav_debug_mp", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Allow Adaptive View debug bounds networking in multiplayer.")

    cvars.AddChangeCallback("pmav_alladmins", function(_, _, newValue)
        local enabled = tostring(newValue or "0") ~= "0"
        local message = enabled and
            "[adaptive view] Переменная \"pmav_alladmins\" была изменена! Некоторые настройки могут не отображаться, введите \"spawnmenu_reload\" для перезагрузки его и получения функций которые сейчас не доступны." or
            "[adaptive view] Переменная \"pmav_alladmins\" была изменена! Некоторые настройки больше не доступны и могут отображаться в Q-Menu, можете ввести \"spawnmenu_reload\", что-бы очистить меню adaptive view."

        PrintMessage(HUD_PRINTTALK, message)
    end, "pm_eblansky_adaptive_view_alladmins_notice")

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

local function IsSettingsEditAllowed(ply)
    local inJail = GetConVar("pmav_injail")

    if inJail and inJail:GetBool() then
        return false
    end

    if not IsValid(ply) then
        return true
    end

    if game.SinglePlayer() then
        return true
    end

    if isfunction(ply.IsAdmin) and ply:IsAdmin() then
        return true
    end

    local cheats = GetConVar("sv_cheats")
    local allowAll = GetConVar("pmav_alladmins")

    return cheats and cheats:GetBool() and allowAll and allowAll:GetBool() or false
end

local function IsDebugBoundsAllowed()
    local inJail = GetConVar("pmav_injail")

    if inJail and inJail:GetBool() then
        return false
    end

    return game.SinglePlayer()
end

local function NormalizeModel(model)
    return string.lower(string.Trim(tostring(model or "")))
end

local function GetRuleModelAliases(model)
    model = NormalizeModel(model)

    if model == "" then
        return {}
    end

    local aliases = {model}
    local prefix, name = string.match(model, "^(.*[/\\])([^/\\]+)%.mdl$")

    if not prefix or not name then
        return aliases
    end

    local stripped = string.gsub(name, "_pm$", "")
    stripped = string.gsub(stripped, "_player$", "")
    stripped = string.gsub(stripped, "_playermodel$", "")

    if stripped ~= name then
        aliases[#aliases + 1] = prefix .. stripped .. ".mdl"
    else
        aliases[#aliases + 1] = prefix .. name .. "_pm.mdl"
        aliases[#aliases + 1] = prefix .. name .. "_player.mdl"
        aliases[#aliases + 1] = prefix .. name .. "_playermodel.mdl"
    end

    return aliases
end

local function GetCanonicalRuleModel(model)
    model = NormalizeModel(model)

    local prefix, name = string.match(model, "^(.*[/\\])([^/\\]+)%.mdl$")

    if not prefix or not name then
        return model
    end

    name = string.gsub(name, "_pm$", "")
    name = string.gsub(name, "_player$", "")
    name = string.gsub(name, "_playermodel$", "")

    return prefix .. name .. ".mdl"
end

local function NumberOr(value, fallback)
    value = tonumber(value)

    if value == nil then
        return fallback
    end

    return value
end

local function GetAdaptiveModelScale(ent, settings)
    if not settings or settings.scaleSupport ~= true or not IsValid(ent) or not isfunction(ent.GetModelScale) then
        return 1
    end

    local minScale = math.max(NumberOr(settings.scaleMin, 0.5), 0.01)
    local maxScale = math.max(NumberOr(settings.scaleMax, 2), minScale)

    return math.Clamp(NumberOr(ent:GetModelScale(), 1), minScale, maxScale)
end

local function ScaleBounds(mins, maxs, scale)
    if math.abs(scale - 1) < 0.001 then
        return mins, maxs
    end

    return Vector(mins.x * scale, mins.y * scale, mins.z * scale),
        Vector(maxs.x * scale, maxs.y * scale, maxs.z * scale)
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
    local height = math.max(NumberOr(modelMaxs and modelMaxs.z, defaultMaxs.z) - NumberOr(modelMins and modelMins.z, defaultMins.z), 1)

    -- Some models report broken bounds: tiny foot-only boxes, or giant boxes
    -- caused by accessories/weapons. Use the smaller sane axis when one axis
    -- explodes, then clamp to movement-friendly player hull sizes.
    local smaller = math.min(halfX, halfY)
    local larger = math.max(halfX, halfY)

    if larger > height * 0.55 then
        local compactHalf = math.Clamp(height * 0.18, 8, 24)
        halfX = math.min(halfX, compactHalf)
        halfY = math.min(halfY, compactHalf)
    elseif smaller > 0 and larger / smaller > 2.25 then
        halfX = smaller
        halfY = smaller
    end

    halfX = math.Clamp(halfX, 8, 32)
    halfY = math.Clamp(halfY, 8, 32)

    return -halfX, -halfY, halfX, halfY
end

local function ApplyRuleHorizontalOverrides(rule, minX, minY, maxX, maxY, scale)
    if not rule then
        return minX, minY, maxX, maxY
    end

    scale = NumberOr(scale, 1)
    local length = NumberOr(rule.collisionLength, 0)
    local width = NumberOr(rule.collisionWidth, 0)
    local ruleMinX = NumberOr(rule.collisionMinX, 0)
    local ruleMaxX = NumberOr(rule.collisionMaxX, 0)
    local ruleMinY = NumberOr(rule.collisionMinY, 0)
    local ruleMaxY = NumberOr(rule.collisionMaxY, 0)
    local hasAsymmetricBounds = ruleMinX < 0 or ruleMaxX > 0 or ruleMinY < 0 or ruleMaxY > 0

    if not hasAsymmetricBounds and length > 0 then
        local halfLength = math.Clamp(length * scale * 0.5, 6, 48)
        minX = -halfLength
        maxX = halfLength
    end

    if not hasAsymmetricBounds and width > 0 then
        local halfWidth = math.Clamp(width * scale * 0.5, 6, 48)
        minY = -halfWidth
        maxY = halfWidth
    end

    if hasAsymmetricBounds then
        if ruleMinX < 0 then
            minX = math.Clamp(ruleMinX * scale, -96, -4)
        end

        if ruleMaxX > 0 then
            maxX = math.Clamp(ruleMaxX * scale, 4, 96)
        end

        if ruleMinY < 0 then
            minY = math.Clamp(ruleMinY * scale, -96, -4)
        end

        if ruleMaxY > 0 then
            maxY = math.Clamp(ruleMaxY * scale, 4, 96)
        end
    end

    return minX, minY, maxX, maxY
end

local function HasRuleHorizontalOverride(rule)
    return rule and (
        NumberOr(rule.collisionWidth, 0) > 0 or
        NumberOr(rule.collisionLength, 0) > 0 or
        NumberOr(rule.collisionMinX, 0) < 0 or
        NumberOr(rule.collisionMaxX, 0) > 0 or
        NumberOr(rule.collisionMinY, 0) < 0 or
        NumberOr(rule.collisionMaxY, 0) > 0
    )
end

local function ClampAutoHorizontalBounds(rule, minX, minY, maxX, maxY)
    if HasRuleHorizontalOverride(rule) then
        return minX, minY, maxX, maxY
    end

    return math.Clamp(minX, -32, -8),
        math.Clamp(minY, -32, -8),
        math.Clamp(maxX, 8, 32),
        math.Clamp(maxY, 8, 32)
end

local function LockAutoHorizontalAspect(rule, minX, minY, maxX, maxY)
    if HasRuleHorizontalOverride(rule) then
        return minX, minY, maxX, maxY
    end

    local halfX = math.max(math.abs(minX), math.abs(maxX))
    local halfY = math.max(math.abs(minY), math.abs(maxY))
    local half = math.Clamp(math.max(halfX, halfY), 8, 32)

    return -half, -half, half, half
end

local function Percentile(values, fraction)
    local count = #values

    if count <= 0 then
        return nil
    end

    table.sort(values)

    local index = math.Clamp(math.ceil(count * fraction), 1, count)

    return values[index]
end

local function GetPlayerBoneHorizontalBounds(ply, modelMins, modelMaxs, defaultMins, defaultMaxs)
    if not IsValid(ply) or not isfunction(ply.GetBoneCount) or not isfunction(ply.GetBonePosition) then
        return GetSaneHorizontalBounds(modelMins, modelMaxs, defaultMins, defaultMaxs)
    end

    if isfunction(ply.SetupBones) then
        ply:SetupBones()
    end

    local boneCount = ply:GetBoneCount() or 0
    local absX = {}
    local absY = {}
    local minZ = NumberOr(modelMins and modelMins.z, -8) - 4
    local maxZ = NumberOr(modelMaxs and modelMaxs.z, 72) + 4
    local origin = ply:GetPos()

    for bone = 0, boneCount - 1 do
        local pos = ply:GetBonePosition(bone)

        if pos and pos ~= vector_origin and pos:DistToSqr(origin) > 0.01 then
            local localPos = ply:WorldToLocal(pos)

            if localPos.z >= minZ and localPos.z <= maxZ then
                absX[#absX + 1] = math.abs(localPos.x)
                absY[#absY + 1] = math.abs(localPos.y)
            end
        end
    end

    if #absX < 5 or #absY < 5 then
        return GetSaneHorizontalBounds(modelMins, modelMaxs, defaultMins, defaultMaxs)
    end

    -- Use a percentile instead of the absolute maximum so PM accessories,
    -- tails, held props, or weapon bones do not inflate the movement hull.
    local halfX = math.Clamp(NumberOr(Percentile(absX, 0.8), 8) + 8, 8, 32)
    local halfY = math.Clamp(NumberOr(Percentile(absY, 0.8), 8) + 8, 8, 32)

    return -halfX, -halfY, halfX, halfY
end

local function ClassLooksAdaptive(class)
    class = string.lower(tostring(class or ""))

    return string.find(class, "npc", 1, true) ~= nil or
        string.find(class, "nextbot", 1, true) ~= nil or
        string.find(class, "lambda", 1, true) ~= nil or
        string.find(class, "zeta", 1, true) ~= nil or
        string.find(class, "drg", 1, true) ~= nil
end

local function GetRuleCameraOffset(rule)
    if not rule then
        return 0
    end

    return NumberOr(rule.cameraOffset, NumberOr(rule.offset, 0))
end

local function GetRuleCameraOffsetX(rule)
    return NumberOr(rule and rule.cameraOffsetX, 0)
end

local function GetRuleCameraOffsetY(rule)
    return NumberOr(rule and rule.cameraOffsetY, 0)
end

local function GetRuleCollisionHeight(rule)
    if not rule then
        return 0
    end

    return NumberOr(rule.collisionHeight, 0)
end

local function GetCollisionBodyHeight(ent, settings, modelMaxs, fallbackHeight)
    local rule = GetRule(settings, ent:GetModel())

    local ruleCollisionHeight = GetRuleCollisionHeight(rule)

    if ruleCollisionHeight > 0 then
        return ruleCollisionHeight
    end

    local modelHeight = NumberOr(modelMaxs and modelMaxs.z, fallbackHeight or 72)

    return math.Clamp(modelHeight, 12, 180)
end

local function NearlyEqualVector(a, b, epsilon)
    epsilon = epsilon or 0.01

    return math.abs(a.x - b.x) <= epsilon and math.abs(a.y - b.y) <= epsilon and math.abs(a.z - b.z) <= epsilon
end

local function BroadcastBounds(ent, mins, maxs, duckMins, duckMaxs)
    if not IsDebugBoundsAllowed() then
        return
    end

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

local function SetPlayerStandHullStable(ply, mins, maxs)
    local actualMins, actualMaxs = ply:GetHull()
    local actualMatches = NearlyEqualVector(actualMins, mins) and NearlyEqualVector(actualMaxs, maxs)

    if ply.pmavLastHullMins and
        NearlyEqualVector(ply.pmavLastHullMins, mins) and
        NearlyEqualVector(ply.pmavLastHullMaxs, maxs) and
        actualMatches then
        BroadcastBounds(ply, mins, maxs, ply.pmavLastDuckMins, ply.pmavLastDuckMaxs)
        return
    end

    ply.pmavLastHullMins = Vector(mins.x, mins.y, mins.z)
    ply.pmavLastHullMaxs = Vector(maxs.x, maxs.y, maxs.z)

    ply:SetHull(mins, maxs)

    BroadcastBounds(ply, mins, maxs, ply.pmavLastDuckMins, ply.pmavLastDuckMaxs)
end

local function SetPlayerDuckHullCache(ply, duckMins, duckMaxs)
    ply.pmavLastDuckMins = Vector(duckMins.x, duckMins.y, duckMins.z)
    ply.pmavLastDuckMaxs = Vector(duckMaxs.x, duckMaxs.y, duckMaxs.z)
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
    ent.pmavAdaptiveBoundsAppliedAt = CurTime()
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

local function CanUseAdaptiveDamageBounds(ent)
    if not IsValid(ent) or not ent.pmavAdaptiveBoundsApplied then
        return false
    end

    local createdAt = NumberOr(ent.pmavCreatedAt, 0)
    local appliedAt = NumberOr(ent.pmavAdaptiveBoundsAppliedAt, 0)
    local readyAt = math.max(createdAt, appliedAt) + ENTITY_DAMAGE_BOUNDS_GRACE

    return CurTime() >= readyAt
end

local function DamageInfoHasType(dmginfo, damageType)
    return damageType ~= nil and isfunction(dmginfo.IsDamageType) and dmginfo:IsDamageType(damageType)
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
    if not IsValid(ent) or ent:IsPlayer() or not CanUseAdaptiveDamageBounds(ent) then
        return false
    end

    if not ent.pmavLastBoundsMins or not ent.pmavLastBoundsMaxs or not dmginfo then
        return false
    end

    if DamageInfoHasType(dmginfo, DMG_BLAST) or
        DamageInfoHasType(dmginfo, DMG_BURN) or
        DamageInfoHasType(dmginfo, DMG_SONIC) or
        DamageInfoHasType(dmginfo, DMG_RADIATION) or
        DamageInfoHasType(dmginfo, DMG_DISSOLVE) or
        DamageInfoHasType(dmginfo, DMG_PLASMA) or
        DamageInfoHasType(dmginfo, DMG_AIRBOAT) or
        DamageInfoHasType(dmginfo, DMG_BLAST_SURFACE) then
        return false
    end

    local attacker = dmginfo:GetAttacker()

    if ent.pmavLastBulletHitPos and ent.pmavLastBulletHitTime and CurTime() - ent.pmavLastBulletHitTime <= 0.1 then
        return not IsWorldPointInsideAdaptiveBounds(ent, ent.pmavLastBulletHitPos, 1)
    end

    if not IsValid(attacker) or not attacker:IsPlayer() then
        return false
    end

    if IsValid(attacker) and attacker:IsPlayer() and isfunction(attacker.GetEyeTrace) then
        local trace = attacker:GetEyeTrace()

        if trace and trace.Entity == ent and IsUsableDamagePoint(trace.HitPos) then
            return not IsWorldPointInsideAdaptiveBounds(ent, trace.HitPos, 1)
        end
    end

    if isfunction(attacker.GetAimVector) then
        local startPos = isfunction(attacker.GetShootPos) and attacker:GetShootPos() or attacker:EyePos()
        local direction = attacker:GetAimVector()

        return not RayIntersectsAdaptiveBounds(ent, startPos, direction, 1)
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

local function InvalidatePlayerStableState(ply, keepPinState)
    if not IsValid(ply) then
        return
    end

    ply.pmavLastHullMins = nil
    ply.pmavLastHullMaxs = nil
    ply.pmavLastDuckMins = nil
    ply.pmavLastDuckMaxs = nil
    ply.pmavLastStandOffset = nil
    ply.pmavLastDuckOffset = nil

    if keepPinState and ply.pmavPinModel == ply:GetModel() then
        return
    end

    ply.pmavPinModel = nil
    ply.pmavPinBaseHeadHeight = nil
    ply.pmavPinTargetHeadDelta = nil
    ply.pmavPinSmoothedHeadDelta = nil
    ply.pmavPinLastOriginZ = nil
    ply.pmavPinStairFreezeUntil = nil
    ply.pmavPinLiveStandHeight = nil
    ply.pmavPinLiveDuckHeight = nil
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
        offset = math.Clamp(NumberOr(rule.offset, 0), -64, 64),
        cameraOffset = math.Clamp(NumberOr(rule.cameraOffset, NumberOr(rule.offset, 0)), -64, 64),
        duckCameraHeight = math.Clamp(NumberOr(rule.duckCameraHeight, 0), 0, 160),
        collisionHeight = math.Clamp(NumberOr(rule.collisionHeight, 0), 0, 180),
        collisionWidth = math.Clamp(NumberOr(rule.collisionWidth, 0), 0, 96),
        collisionLength = math.Clamp(NumberOr(rule.collisionLength, 0), 0, 96),
        collisionMinX = math.Clamp(NumberOr(rule.collisionMinX, 0), -96, 0),
        collisionMaxX = math.Clamp(NumberOr(rule.collisionMaxX, 0), 0, 96),
        collisionMinY = math.Clamp(NumberOr(rule.collisionMinY, 0), -96, 0),
        collisionMaxY = math.Clamp(NumberOr(rule.collisionMaxY, 0), 0, 96),
        cameraOffsetX = math.Clamp(NumberOr(rule.cameraOffsetX, 0), -64, 64),
        cameraOffsetY = math.Clamp(NumberOr(rule.cameraOffsetY, 0), -64, 64),
        pinCameraOnEye = rule.pinCameraOnEye == true,
        pinEyeSmoothing = math.Clamp(NumberOr(rule.pinEyeSmoothing, 0.50), 0, 1),
        mass = math.Clamp(NumberOr(rule.mass, -1), -1, 500),
        pickupLimit = math.Clamp(NumberOr(rule.pickupLimit, -1), -1, 500),
        speed = math.Clamp(NumberOr(rule.speed, -1), -2, 20),
        jump = math.Clamp(NumberOr(rule.jump, -1), -2, 20)
    }
end

local function SanitizeSettings(settings)
    settings = istable(settings) and settings or {}

    local rules = {}

    local ruleCount = 0

    if istable(settings.rules) then
        for model, rule in pairs(settings.rules) do
            if ruleCount >= MAX_MODEL_RULES then
                break
            end

            model = NormalizeModel(model)
            rule = SanitizeRule(rule)

            if model ~= "" and rule then
                rules[model] = rule
                ruleCount = ruleCount + 1
            end
        end
    end

    return {
        enabled = settings.enabled ~= false,
        effectiveModel = NormalizeModel(settings.effectiveModel),
        autoScale = math.Clamp(NumberOr(settings.autoScale, 0.92), 0.1, 2),
        globalOffset = math.Clamp(NumberOr(settings.globalOffset, 0), -64, 64),
        cameraFov = math.Clamp(NumberOr(settings.cameraFov, 0), 0, 160),
        cameraOffsetX = math.Clamp(NumberOr(settings.cameraOffsetX, 0), -64, 64),
        cameraOffsetY = math.Clamp(NumberOr(settings.cameraOffsetY, 0), -64, 64),
        scaleSupport = settings.scaleSupport ~= false,
        scaleMin = math.Clamp(NumberOr(settings.scaleMin, 0.5), 0.05, 10),
        scaleMax = math.max(math.Clamp(NumberOr(settings.scaleMax, 2), 0.05, 10), math.Clamp(NumberOr(settings.scaleMin, 0.5), 0.05, 10)),
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
        adaptiveSpeed = settings.adaptiveSpeed == true,
        adaptiveJump = settings.adaptiveJump == true,
        adaptivePickupWeight = settings.adaptivePickupWeight == true,
        rules = rules
    }
end

GetRule = function(settings, model)
    local rules = settings and settings.rules

    if not istable(rules) then
        return nil
    end

    local aliases = GetRuleModelAliases(model)

    for _, alias in ipairs(aliases) do
        local rule = rules[alias]

        if rule then
            return rule
        end
    end

    local canonical = GetCanonicalRuleModel(model)

    for ruleModel, rule in pairs(rules) do
        if GetCanonicalRuleModel(ruleModel) == canonical then
            return rule
        end
    end

    return nil
end

local function GetPlayerRuleModel(ply, settings)
    local effectiveModel = NormalizeModel(settings and settings.effectiveModel)

    if effectiveModel ~= "" then
        return effectiveModel
    end

    return NormalizeModel(IsValid(ply) and ply:GetModel() or "")
end

local function GetBoneHeight(ply, boneName, extra)
    local bone = ply:LookupBone(boneName)

    if not bone then
        return nil
    end

    local bonePos

    if isfunction(ply.GetBoneMatrix) then
        local matrix = ply:GetBoneMatrix(bone)

        if matrix and isfunction(matrix.GetTranslation) then
            bonePos = matrix:GetTranslation()
        end
    end

    if not bonePos or bonePos == vector_origin then
        bonePos = ply:GetBonePosition(bone)
    end

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
        modelHeight = math.max(NumberOr(maxs and maxs.z, 72) * settings.autoScale * GetAdaptiveModelScale(ply, settings), 1)
    end

    local minHeight = settings.minHeight
    local maxHeight = math.max(settings.maxHeight, minHeight)

    return math.Clamp(modelHeight, minHeight, maxHeight)
end

local function GetModelHeadBoneHeight(ply, settings)
    if not IsValid(ply) then
        return nil
    end

    if isfunction(ply.SetupBones) then
        ply:SetupBones()
    end

    local modelHeight =
        GetBoneHeight(ply, "ValveBiped.Bip01_Head1", 2) or
        GetBoneHeight(ply, "ValveBiped.Bip01_Neck1", 7) or
        GetAttachmentHeight(ply, "eyes") or
        GetAttachmentHeight(ply, "forward")

    if not modelHeight then
        return GetModelAutoHeight(ply, settings)
    end

    local minHeight = settings.minHeight
    local maxHeight = math.max(settings.maxHeight, minHeight)

    return math.Clamp(modelHeight, minHeight, maxHeight)
end

local function SmoothPinnedHeadDelta(ply, rawDelta, smooth)
    smooth = math.Clamp(NumberOr(smooth, 0.50), 0, 1)

    local posZ = ply:GetPos().z
    local lastOriginZ = ply.pmavPinLastOriginZ
    ply.pmavPinLastOriginZ = posZ
    local onGround = isfunction(ply.IsOnGround) and ply:IsOnGround()
    local speed2D = isfunction(ply.GetVelocity) and ply:GetVelocity():Length2D() or 0
    local crouching = isfunction(ply.Crouching) and ply:Crouching()
    local frameStep = math.max(FrameTime(), engine.TickInterval and engine.TickInterval() or 0.015)
    local currentDelta = ply.pmavPinSmoothedHeadDelta

    if currentDelta == nil then
        ply.pmavPinTargetHeadDelta = rawDelta
        ply.pmavPinSmoothedHeadDelta = rawDelta
        return rawDelta
    end

    local targetDelta = rawDelta

    if crouching then
        targetDelta = currentDelta
    end

    if lastOriginZ ~= nil and onGround then
        local originStep = math.abs(posZ - lastOriginZ)

        if speed2D > 20 and originStep > 0.035 and originStep <= 18 then
            -- IK Foot System / Outfitter can bend the live head bone on slopes and stairs.
            -- Treat ground Z micro-steps as locomotion, not a real camera height change.
            targetDelta = currentDelta
        end
    end

    local lastTarget = ply.pmavPinTargetHeadDelta
    local deadzone = Lerp(smooth, 0.65, 2.25)

    if onGround and speed2D > 20 then
        deadzone = deadzone + Lerp(smooth, 0.65, 1.50)
    end

    if lastTarget ~= nil and math.abs(targetDelta - lastTarget) < deadzone then
        targetDelta = lastTarget
    else
        ply.pmavPinTargetHeadDelta = targetDelta
    end

    if math.abs(targetDelta - currentDelta) < deadzone * 0.55 then
        return currentDelta
    end

    -- Hueglot pin stabilizer: fast enough to feel attached, but it eats head-bone bob and stair-step jitter.
    local response = Lerp(smooth, 22, 4.5)
    local alpha = 1 - math.exp(-frameStep * response)
    local wantedDelta = Lerp(math.Clamp(alpha, 0, 1), currentDelta, targetDelta)

    local maxSpeed = Lerp(smooth, 260, 55)

    if onGround and speed2D > 20 then
        maxSpeed = math.min(maxSpeed, Lerp(smooth, 130, 45))
    end

    local smoothedDelta = math.Approach(currentDelta, wantedDelta, maxSpeed * frameStep)

    ply.pmavPinSmoothedHeadDelta = smoothedDelta
    return smoothedDelta
end

local function IsTacMoveActive()
    local tacMove = GetConVar("vb_movement")

    return tacMove and tacMove:GetBool()
end

local function GetAutoPlayerMassKg(heightUnits)
    local heightMeters = math.max(NumberOr(heightUnits, 72) * SOURCE_UNIT_METERS, 0.1)
    local heightCm = heightMeters * 100

    if heightCm <= 120 then
        return math.Clamp(heightCm * 0.16, 4, 24)
    end

    return math.Clamp((heightCm - 100) * 0.9, 8, 180)
end

local function GetPickupProfileKg(heightUnits, massKg)
    local heightMeters = math.max(NumberOr(heightUnits, 72) * SOURCE_UNIT_METERS, 0.1)

    local function interpolateHeightLimit(aHeight, aLimit, bHeight, bLimit)
        local alpha = math.Clamp((heightMeters - aHeight) / math.max(bHeight - aHeight, 0.001), 0, 1)

        return Lerp(alpha, aLimit, bLimit)
    end

    local maxKg

    if heightMeters <= 0.5 then
        maxKg = interpolateHeightLimit(0.1, 12, 0.5, 45)
    elseif heightMeters <= 1 then
        maxKg = interpolateHeightLimit(0.5, 45, 1, 65)
    elseif heightMeters <= 2 then
        maxKg = interpolateHeightLimit(1, 65, 2, 95)
    elseif heightMeters <= 3 then
        maxKg = interpolateHeightLimit(2, 95, 3, 195)
    else
        maxKg = 195 + (heightMeters - 3) * 90
    end

    maxKg = math.Clamp(maxKg, 0, 500)

    return {
        easy = maxKg * 0.25,
        hard = maxKg * 0.65,
        max = maxKg
    }
end

local function GetPlayerMassAndPickupLimit(ply, settings, rule)
    local heightUnits = NumberOr(ply.pmavCurrentStandHeight, 0)

    if heightUnits <= 0 then
        heightUnits = GetModelAutoHeight(ply, settings)
    end

    local massKg = NumberOr(rule and rule.mass, -1)

    if massKg < 0 then
        massKg = GetAutoPlayerMassKg(heightUnits)
    end

    local profile = GetPickupProfileKg(heightUnits, massKg)
    local pickupLimit = NumberOr(rule and rule.pickupLimit, -1)

    if pickupLimit < 0 then
        pickupLimit = profile.max
    end

    return massKg, pickupLimit, profile
end

local function GetTargetHeights(ply, settings)
    local rule = GetRule(settings, GetPlayerRuleModel(ply, settings))

    if not settings.enabled or rule and rule.mode == "off" then
        return nil
    end

    local scale = GetAdaptiveModelScale(ply, settings)
    local cameraVerticalOffset = settings.globalOffset + GetRuleCameraOffset(rule)
    local standHeight = rule and rule.mode == "height" and rule.height * scale or GetModelAutoHeight(ply, settings)
    standHeight = standHeight + cameraVerticalOffset

    local mins, maxs = ply:GetModelBounds()
    mins = mins or Vector(0, 0, 0)
    maxs = maxs or Vector(16, 16, 72)
    mins, maxs = ScaleBounds(mins, maxs, scale)

    local footSafeHeight = math.max(NumberOr(mins.z, 0) + 8, 4)
    standHeight = math.Clamp(standHeight, footSafeHeight, math.max(settings.maxHeight, footSafeHeight))

    local defaultStand = ply.pmavDefaultStand or Vector(0, 0, 64)
    local defaultDuck = ply.pmavDefaultDuck or Vector(0, 0, 28)
    local duckRatio = defaultStand.z ~= 0 and defaultDuck.z / defaultStand.z or 0.4375

    if IsTacMoveActive() then
        duckRatio = 28 / 64
    end

    local duckHeight

    if rule and rule.duckCameraHeight and rule.duckCameraHeight > 0 then
        duckHeight = rule.duckCameraHeight * scale + cameraVerticalOffset
        duckHeight = math.Clamp(duckHeight, footSafeHeight, standHeight)
    else
        duckHeight = math.max(standHeight * duckRatio, footSafeHeight)
    end

    return standHeight, duckHeight, mins, maxs
end

local function GetEntityTargetHeight(ent, settings, modelMins, modelMaxs)
    local rule = GetRule(settings, ent:GetModel())

    if not settings.enabled or rule and rule.mode == "off" then
        return nil
    end

    local targetHeight = math.max(NumberOr(modelMaxs and modelMaxs.z, 72) * settings.autoScale, 1)

    local ruleCollisionHeight = GetRuleCollisionHeight(rule)

    if ruleCollisionHeight > 0 then
        targetHeight = ruleCollisionHeight
    end

    local footSafeHeight = math.max(NumberOr(modelMins and modelMins.z, 0) + 8, 4)

    return math.Clamp(targetHeight, footSafeHeight, math.max(settings.maxHeight, footSafeHeight))
end

local function GetPlayerAutoCollisionHeight(ply, settings, modelMins)
    local autoHeight = GetModelAutoHeight(ply, settings) + settings.globalOffset
    local footSafeHeight = math.max(NumberOr(modelMins and modelMins.z, 0) + 8, 4)

    return math.Clamp(autoHeight, footSafeHeight, math.max(settings.maxHeight, footSafeHeight))
end

if CLIENT then
    local function ClientConVarFloat(name, fallback)
        local convar = GetConVar(name)

        return convar and convar:GetFloat() or fallback
    end

    local function ClientConVarBool(name, fallback)
        local convar = GetConVar(name)

        return convar and convar:GetBool() or fallback
    end

    local function ClientConVarInt(name, fallback)
        local convar = GetConVar(name)

        return convar and convar:GetInt() or fallback
    end

    AV.BuildSettingsPayload = function()
        local enabled = ClientConVarBool("pmav_enabled", true)

        return SanitizeSettings({
            enabled = enabled,
            autoScale = ClientConVarFloat("pmav_auto_scale", 0.92),
            globalOffset = ClientConVarFloat("pmav_global_offset", 0),
            cameraFov = ClientConVarFloat("pmav_camera_fov", 0),
            cameraOffsetX = ClientConVarFloat("pmav_camera_offset_x", 0),
            cameraOffsetY = ClientConVarFloat("pmav_camera_offset_y", 0),
            scaleSupport = ClientConVarBool("pmav_scale_support", true),
            scaleMin = ClientConVarFloat("pmav_scale_min", 0.5),
            scaleMax = ClientConVarFloat("pmav_scale_max", 2),
            minHeight = ClientConVarFloat("pmav_min_height", 4),
            maxHeight = ClientConVarFloat("pmav_max_height", 120),
            clientHeight = AV.GetLocalAutoHeight and AV.GetLocalAutoHeight() or 0,
            effectiveModel = AV.GetAdaptiveLookupModel and AV.GetAdaptiveLookupModel() or "",
            smooth = 10,
            collision = enabled and ClientConVarBool("pmav_collision", true),
            collisionMode = ClientConVarInt("pmav_collision_mode", 3),
            collisionRadius = ClientConVarFloat("pmav_collision_radius", 16),
            collisionOnlyPlayers = ClientConVarBool("pmav_collision_only_players", false),
            npcCollision = enabled and ClientConVarBool("pmav_npc_collision", true),
            multiplayerSafe = ClientConVarBool("pmav_multiplayer_safe", true),
            adaptiveSpeed = enabled and ClientConVarBool("pmav_adaptive_speed", false),
            adaptiveJump = enabled and ClientConVarBool("pmav_adaptive_jump", false),
            adaptivePickupWeight = enabled and ClientConVarBool("pmav_adaptive_pickup_weight", false),
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
AV.PlayerEnabledOverride = AV.PlayerEnabledOverride or {}
AV.SharedSettings = AV.SharedSettings or SanitizeSettings({})
AV.ManagedEntities = AV.ManagedEntities or {}

local function CopySettingsForWorld(settings)
    local copied = table.Copy(settings or AV.SharedSettings or SanitizeSettings({}))
    copied.clientHeight = 0
    copied.effectiveModel = ""

    return SanitizeSettings(copied)
end

local function GetSettingsForPlayer(ply)
    local forcedEnabled = AV.PlayerEnabledOverride[ply]

    if ply:IsBot() then
        local settings = CopySettingsForWorld(AV.SharedSettings)

        if forcedEnabled ~= nil then
            settings.enabled = forcedEnabled
        end

        return settings
    end

    local settings = AV.PlayerSettings[ply] or CopySettingsForWorld(AV.SharedSettings)

    if forcedEnabled ~= nil then
        settings = SanitizeSettings(settings)
        settings.enabled = forcedEnabled

        if not forcedEnabled then
            settings.collision = false
            settings.npcCollision = false
            settings.adaptiveSpeed = false
            settings.adaptiveJump = false
            settings.adaptivePickupWeight = false
        end
    end

    return settings
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

    if isfunction(ply.GetWalkSpeed) then
        ply.pmavDefaultWalkSpeed = ply:GetWalkSpeed()
    end

    if isfunction(ply.GetRunSpeed) then
        ply.pmavDefaultRunSpeed = ply:GetRunSpeed()
    end

    if isfunction(ply.GetJumpPower) then
        ply.pmavDefaultJumpPower = ply:GetJumpPower()
    end
end

local function RestorePlayer(ply, forceEngineDefaults)
    if not IsValid(ply) then
        return
    end

    if not forceEngineDefaults and not ply.pmavDefaultsCaptured then
        return
    end

    local stand = forceEngineDefaults and Vector(0, 0, 64) or ply.pmavDefaultStand
    local duck = forceEngineDefaults and Vector(0, 0, 28) or ply.pmavDefaultDuck
    local hullMins = forceEngineDefaults and Vector(-16, -16, 0) or ply.pmavDefaultHullMins
    local hullMaxs = forceEngineDefaults and Vector(16, 16, 72) or ply.pmavDefaultHullMaxs
    local duckMins = forceEngineDefaults and Vector(-16, -16, 0) or ply.pmavDefaultDuckMins
    local duckMaxs = forceEngineDefaults and Vector(16, 16, 36) or ply.pmavDefaultDuckMaxs

    -- Hard-off path: if the addon was hot-reloaded while active, the captured
    -- defaults can already be adaptive. The Enable add-on checkbox must still
    -- fully detach from camera/hull logic.
    SetPlayerViewOffsetsStable(ply, stand, duck)
    SetPlayerHullStable(ply, hullMins, hullMaxs, duckMins, duckMaxs)
    ply.pmavCurrentStandHeight = nil
    ply.pmavCurrentDuckHeight = nil
    ply.pmavCurrentCameraOffsetX = nil
    ply.pmavCurrentCameraOffsetY = nil

    if isfunction(ply.SetWalkSpeed) then
        ply:SetWalkSpeed(forceEngineDefaults and 200 or ply.pmavDefaultWalkSpeed or 200)
    end

    if isfunction(ply.SetRunSpeed) then
        ply:SetRunSpeed(forceEngineDefaults and 400 or ply.pmavDefaultRunSpeed or 400)
    end

    if isfunction(ply.SetJumpPower) then
        ply:SetJumpPower(forceEngineDefaults and 200 or ply.pmavDefaultJumpPower or 200)
    end

    ply.pmavMovementScale = 1
    ply.pmavJumpScale = 1
    ply.pmavAppliedSpeed = false
    ply.pmavAppliedJump = false
    ply.pmavCurrentStandHeight = nil
    ply.pmavCurrentDuckHeight = nil
    ply.pmavCurrentCameraOffsetX = nil
    ply.pmavCurrentCameraOffsetY = nil
end

local function ResolveRuleMovementScale(value, autoScale, autoEnabled)
    value = NumberOr(value, -1)

    if math.abs(value) < 0.0001 then
        return 1
    end

    if value == -2 then
        return 1
    end

    if value == -1 then
        return autoEnabled and autoScale or 1
    end

    return math.max(value, 0)
end

local function ShouldApplyMovementScale(ruleValue, autoEnabled)
    ruleValue = NumberOr(ruleValue, -1)

    if math.abs(ruleValue) < 0.0001 then
        return false
    end

    return autoEnabled or ruleValue ~= -1
end

local function RestoreAppliedMovementScale(ply)
    if ply.pmavDefaultWalkSpeed and isfunction(ply.SetWalkSpeed) then
        ply:SetWalkSpeed(ply.pmavDefaultWalkSpeed)
    end

    if ply.pmavDefaultRunSpeed and isfunction(ply.SetRunSpeed) then
        ply:SetRunSpeed(ply.pmavDefaultRunSpeed)
    end

    if ply.pmavDefaultJumpPower and isfunction(ply.SetJumpPower) then
        ply:SetJumpPower(ply.pmavDefaultJumpPower)
    end

    ply.pmavMovementScale = 1
    ply.pmavJumpScale = 1
    ply.pmavAppliedSpeed = false
    ply.pmavAppliedJump = false
end

local function ApplyPlayerMovementScale(ply, settings, hullHeight, rule)
    if not settings or not settings.enabled then
        RestoreAppliedMovementScale(ply)
        return
    end

    local defaultHullHeight = math.max(NumberOr(ply.pmavDefaultHullMaxs and ply.pmavDefaultHullMaxs.z, 72), 1)
    local rawScale = NumberOr(hullHeight, defaultHullHeight) / defaultHullHeight
    local speedScale = math.Clamp(rawScale, MIN_SPEED_SCALE, MAX_SPEED_SCALE)
    local jumpScale = math.Clamp(1 + (rawScale - 1) * 0.45, MIN_JUMP_SCALE, MAX_JUMP_SCALE)
    speedScale = ResolveRuleMovementScale(rule and rule.speed, speedScale, settings.adaptiveSpeed)
    jumpScale = ResolveRuleMovementScale(rule and rule.jump, jumpScale, settings.adaptiveJump)

    ply.pmavMovementScale = speedScale
    ply.pmavJumpScale = jumpScale

    if ShouldApplyMovementScale(rule and rule.speed, settings.adaptiveSpeed) then
        if ply.pmavDefaultWalkSpeed and isfunction(ply.SetWalkSpeed) then
            ply:SetWalkSpeed(math.max(math.Round(ply.pmavDefaultWalkSpeed * speedScale), 0))
        end

        if ply.pmavDefaultRunSpeed and isfunction(ply.SetRunSpeed) then
            ply:SetRunSpeed(math.max(math.Round(ply.pmavDefaultRunSpeed * speedScale), 0))
        end
        ply.pmavAppliedSpeed = true
    else
        if ply.pmavAppliedSpeed and ply.pmavDefaultWalkSpeed and isfunction(ply.SetWalkSpeed) then
            ply:SetWalkSpeed(ply.pmavDefaultWalkSpeed)
        end

        if ply.pmavAppliedSpeed and ply.pmavDefaultRunSpeed and isfunction(ply.SetRunSpeed) then
            ply:SetRunSpeed(ply.pmavDefaultRunSpeed)
        end

        ply.pmavAppliedSpeed = false
    end

    if ShouldApplyMovementScale(rule and rule.jump, settings.adaptiveJump) then
        if ply.pmavDefaultJumpPower and isfunction(ply.SetJumpPower) then
            ply:SetJumpPower(math.max(math.Round(ply.pmavDefaultJumpPower * jumpScale), 0))
        end
        ply.pmavAppliedJump = true
    elseif ply.pmavAppliedJump and ply.pmavDefaultJumpPower and isfunction(ply.SetJumpPower) then
        ply:SetJumpPower(ply.pmavDefaultJumpPower)
        ply.pmavAppliedJump = false
    end
end

local function ApplyPlayer(ply)
    if not IsValid(ply) then
        return
    end

    CaptureDefaults(ply)

    local settings = GetSettingsForPlayer(ply)

    if not settings then
        RestorePlayer(ply, true)
        return
    end

    if not settings.enabled then
        RestorePlayer(ply, true)
        return
    end

    local ruleModel = GetPlayerRuleModel(ply, settings)
    local rule = GetRule(settings, ruleModel)
    local standHeight, duckHeight = GetTargetHeights(ply, settings)

    if not standHeight then
        RestorePlayer(ply)
        return
    end

    if rule and rule.pinCameraOnEye == true and ply.pmavPinModel == ruleModel and ply.pmavPinSmoothedHeadDelta ~= nil then
        local pinDelta = NumberOr(ply.pmavPinSmoothedHeadDelta, 0)
        standHeight = math.Clamp(standHeight + pinDelta, settings.minHeight, math.max(settings.maxHeight, settings.minHeight))
        duckHeight = math.Clamp(duckHeight + pinDelta, settings.minHeight, standHeight)
    end

    ply.pmavCurrentStandHeight = standHeight
    ply.pmavCurrentDuckHeight = duckHeight
    ply.pmavCurrentCameraOffsetX = math.Clamp(NumberOr(settings.cameraOffsetX, 0) + GetRuleCameraOffsetX(rule), -64, 64)
    ply.pmavCurrentCameraOffsetY = math.Clamp(NumberOr(settings.cameraOffsetY, 0) + GetRuleCameraOffsetY(rule), -64, 64)

    local massKg, pickupLimitKg, pickupProfile = GetPlayerMassAndPickupLimit(ply, settings, rule)
    ply.pmavMassKg = massKg
    ply.pmavPickupEasyKg = pickupProfile.easy
    ply.pmavPickupHardKg = pickupProfile.hard
    ply.pmavPickupLimitKg = pickupLimitKg

    if isfunction(ply.SetNW2Float) then
        ply:SetNW2Float("pmav_mass_kg", massKg)
        ply:SetNW2Float("pmav_pickup_easy_kg", pickupProfile.easy)
        ply:SetNW2Float("pmav_pickup_hard_kg", pickupProfile.hard)
        ply:SetNW2Float("pmav_pickup_limit_kg", pickupLimitKg)
    end

    SetPlayerViewOffsetsStable(
        ply,
        Vector(ply.pmavDefaultStand.x, ply.pmavDefaultStand.y, standHeight),
        Vector(ply.pmavDefaultDuck.x, ply.pmavDefaultDuck.y, duckHeight)
    )

    local tacMoveActive = IsTacMoveActive() --Наебни говна, дочь казаха за помощь в этом аддоне

    if settings.collision and settings.collisionMode > 0 then
        local resizeHeight = settings.collisionMode == 1 or settings.collisionMode == 3
        local resizeWidth = settings.collisionMode == 2 or settings.collisionMode == 3
        local modelMins, modelMaxs = GetStableModelBounds(ply, ply.pmavDefaultHullMins, ply.pmavDefaultHullMaxs)
        local modelScale = GetAdaptiveModelScale(ply, settings)
        modelMins, modelMaxs = ScaleBounds(modelMins, modelMaxs, modelScale)
        local rule = GetRule(settings, ruleModel)
        local ruleCollisionHeight = GetRuleCollisionHeight(rule)
        local hullHeight = ply.pmavDefaultHullMaxs.z

        if resizeHeight then
            if ruleCollisionHeight > 0 then
                hullHeight = math.Clamp(ruleCollisionHeight, 18, 180)
            else
                hullHeight = math.Clamp(GetPlayerAutoCollisionHeight(ply, settings, modelMins) + 6, 18, 180)
            end
        end

        local cameraToHullTop = math.max(hullHeight - standHeight, 0)
        local duckHullHeight = resizeHeight and math.Clamp(math.min(duckHeight + cameraToHullTop, hullHeight), 12, 120) or ply.pmavDefaultDuckMaxs.z
        local hullMins = ply.pmavDefaultHullMins
        local duckHullMins = resizeHeight and ply.pmavDefaultHullMins or ply.pmavDefaultDuckMins
        local hullMaxs = Vector(ply.pmavDefaultHullMaxs.x, ply.pmavDefaultHullMaxs.y, hullHeight)
        local duckHullMaxs = Vector(ply.pmavDefaultDuckMaxs.x, ply.pmavDefaultDuckMaxs.y, duckHullHeight)

        if resizeWidth then
            local minX, minY, maxX, maxY = GetPlayerBoneHorizontalBounds(ply, modelMins, modelMaxs, ply.pmavDefaultHullMins, ply.pmavDefaultHullMaxs)
            minX, minY, maxX, maxY = ApplyRuleHorizontalOverrides(rule, minX, minY, maxX, maxY, modelScale)
            minX, minY, maxX, maxY = ClampAutoHorizontalBounds(rule, minX, minY, maxX, maxY)
            minX, minY, maxX, maxY = LockAutoHorizontalAspect(rule, minX, minY, maxX, maxY)

            if settings.multiplayerSafe and game.MaxPlayers() > 1 and not ply:IsBot() then
                minX = math.min(minX, ply.pmavDefaultHullMins.x)
                minY = math.min(minY, ply.pmavDefaultHullMins.y)
                maxX = math.max(maxX, ply.pmavDefaultHullMaxs.x)
                maxY = math.max(maxY, ply.pmavDefaultHullMaxs.y)
            end

            hullMins = Vector(minX, minY, ply.pmavDefaultHullMins.z)
            hullMaxs.x = maxX
            hullMaxs.y = maxY
            duckHullMins = Vector(minX, minY, resizeHeight and ply.pmavDefaultHullMins.z or ply.pmavDefaultDuckMins.z)
            duckHullMaxs.x = maxX
            duckHullMaxs.y = maxY
        end

        if tacMoveActive then
            SetPlayerDuckHullCache(ply, ply.pmavDefaultDuckMins, ply.pmavDefaultDuckMaxs)
            SetPlayerStandHullStable(ply, hullMins, hullMaxs)
            RestoreAppliedMovementScale(ply)
        else
            SetPlayerHullStable(ply, hullMins, hullMaxs, duckHullMins, duckHullMaxs)
            ApplyPlayerMovementScale(ply, settings, hullHeight, rule)
        end
    else
        if tacMoveActive then
            SetPlayerDuckHullCache(ply, ply.pmavDefaultDuckMins, ply.pmavDefaultDuckMaxs)
            SetPlayerStandHullStable(ply, ply.pmavDefaultHullMins, ply.pmavDefaultHullMaxs)
            RestoreAppliedMovementScale(ply)
        else
            SetPlayerHullStable(ply, ply.pmavDefaultHullMins, ply.pmavDefaultHullMaxs, ply.pmavDefaultDuckMins, ply.pmavDefaultDuckMaxs)
            ApplyPlayerMovementScale(ply, settings, ply.pmavDefaultHullMaxs.z, GetRule(settings, ruleModel))
        end
    end
end

hook.Add("FinishMove", "pm_eblansky_adaptive_view_tacmove_camera", function(ply)
    if not IsValid(ply) or not ply.pmavDefaultsCaptured then
        return
    end

    local settings = GetSettingsForPlayer(ply)
    local ruleModel = settings and GetPlayerRuleModel(ply, settings) or NormalizeModel(ply:GetModel())
    local rule = settings and GetRule(settings, ruleModel)

    if not settings or not settings.enabled or rule and rule.mode == "off" then
        return
    end

    local livePin = rule and rule.pinCameraOnEye == true

    if livePin then
        local standHeight, duckHeight = GetTargetHeights(ply, settings)
        local headHeight = GetModelHeadBoneHeight(ply, settings)

        if not standHeight or not duckHeight or not headHeight then
            return
        end

        if ply.pmavPinModel ~= ruleModel then
            ply.pmavPinBaseHeadHeight = nil
            ply.pmavPinTargetHeadDelta = nil
            ply.pmavPinSmoothedHeadDelta = nil
            ply.pmavPinLastOriginZ = nil
            ply.pmavPinStairFreezeUntil = nil
            ply.pmavPinLiveStandHeight = nil
            ply.pmavPinLiveDuckHeight = nil
            ply.pmavPinModel = ruleModel
        end

        if not ply.pmavPinBaseHeadHeight then
            ply.pmavPinBaseHeadHeight = headHeight
        end

        local smooth = math.Clamp(NumberOr(rule.pinEyeSmoothing, 0.50), 0, 1)
        local headDelta = SmoothPinnedHeadDelta(ply, headHeight - ply.pmavPinBaseHeadHeight, smooth)
        standHeight = math.Clamp(standHeight + headDelta, settings.minHeight, math.max(settings.maxHeight, settings.minHeight))
        duckHeight = math.Clamp(duckHeight + headDelta, settings.minHeight, standHeight)
        ply.pmavPinLiveStandHeight = standHeight
        ply.pmavPinLiveDuckHeight = duckHeight

        ply.pmavCurrentStandHeight = standHeight
        ply.pmavCurrentDuckHeight = duckHeight
    elseif not IsTacMoveActive() then
        ply.pmavPinModel = nil
        ply.pmavPinBaseHeadHeight = nil
        ply.pmavPinTargetHeadDelta = nil
        ply.pmavPinSmoothedHeadDelta = nil
        ply.pmavPinLastOriginZ = nil
        ply.pmavPinStairFreezeUntil = nil
        ply.pmavPinLiveStandHeight = nil
        ply.pmavPinLiveDuckHeight = nil
        return
    end

    if not ply.pmavCurrentStandHeight or not ply.pmavCurrentDuckHeight then
        return
    end

    SetPlayerViewOffsetsStable(
        ply,
        Vector(ply.pmavDefaultStand.x, ply.pmavDefaultStand.y, ply.pmavCurrentStandHeight),
        Vector(ply.pmavDefaultDuck.x, ply.pmavDefaultDuck.y, ply.pmavCurrentDuckHeight)
    )
end)

local function IsPlayerAdaptiveCollisionActive(ply)
    local settings = GetSettingsForPlayer(ply)
    local rule = settings and GetRule(settings, GetPlayerRuleModel(ply, settings))

    return settings and settings.enabled and settings.collision and settings.collisionMode > 0 and not (rule and rule.mode == "off")
end

local function HasNoCollideConstraintWithPlayer(ent, ply)
    if not constraint or not isfunction(constraint.FindConstraints) then
        return false
    end

    local constraints = constraint.FindConstraints(ent, "NoCollide")

    if not istable(constraints) then
        return false
    end

    for _, data in ipairs(constraints) do
        if istable(data) and (data.Ent1 == ply or data.Ent2 == ply or data.Entity and data.Entity[ply]) then
            return true
        end
    end

    return false
end

local function ShouldStuckTraceHit(ply, ent)
    if ent == ply then
        return false
    end

    if not IsValid(ent) then
        return true
    end

    if isfunction(ent.GetSolid) and ent:GetSolid() == SOLID_NONE then
        return false
    end

    if isfunction(ent.IsSolid) and not ent:IsSolid() then
        return false
    end

    if isfunction(ent.IsEFlagSet) and ent:IsEFlagSet(EFL_NOCLIP_ACTIVE) then
        return false
    end

    if isfunction(ent.IsSolidFlagSet) and FSOLID_NOT_SOLID and ent:IsSolidFlagSet(FSOLID_NOT_SOLID) then
        return false
    end

    local shouldCollide = hook.Run("ShouldCollide", ply, ent)

    if shouldCollide == false then
        return false
    end

    if HasNoCollideConstraintWithPlayer(ent, ply) then
        return false
    end

    local collisionGroup = isfunction(ent.GetCollisionGroup) and ent:GetCollisionGroup() or COLLISION_GROUP_NONE

    if collisionGroup == COLLISION_GROUP_IN_VEHICLE or
        collisionGroup == COLLISION_GROUP_DEBRIS or
        collisionGroup == COLLISION_GROUP_DEBRIS_TRIGGER or
        collisionGroup == COLLISION_GROUP_INTERACTIVE_DEBRIS or
        collisionGroup == COLLISION_GROUP_PASSABLE_DOOR or
        collisionGroup == COLLISION_GROUP_WEAPON or
        collisionGroup == COLLISION_GROUP_PROJECTILE or
        collisionGroup == COLLISION_GROUP_DISSOLVING then
        return false
    end

    local class = string.lower(tostring(ent:GetClass() or ""))

    if string.StartWith(class, "prop_") and isfunction(ent.GetPhysicsObject) then
        local phys = ent:GetPhysicsObject()

        if IsValid(phys) and isfunction(phys.IsCollisionEnabled) and not phys:IsCollisionEnabled() then
            return false
        end
    end

    return true
end

local function TracePlayerHullAt(ply, pos)
    if not IsValid(ply) or not isfunction(ply.GetHull) then
        return nil
    end

    local mins, maxs

    if isfunction(ply.Crouching) and ply:Crouching() and isfunction(ply.GetHullDuck) then
        mins, maxs = ply:GetHullDuck()
    else
        mins, maxs = ply:GetHull()
    end

    return util.TraceHull({
        start = pos,
        endpos = pos,
        mins = mins,
        maxs = maxs,
        filter = function(ent)
            return ShouldStuckTraceHit(ply, ent)
        end,
        mask = MASK_PLAYERSOLID,
        collisiongroup = COLLISION_GROUP_PLAYER_MOVEMENT or COLLISION_GROUP_PLAYER
    })
end

local function GetEntityPickupWeightKg(ent)
    if not IsValid(ent) or not isfunction(ent.OBBMins) or not isfunction(ent.OBBMaxs) then
        return nil
    end

    local mins = ent:OBBMins()
    local maxs = ent:OBBMaxs()

    if not mins or not maxs then
        return nil
    end

    local size = maxs - mins
    local x = math.max(math.abs(size.x) * SOURCE_UNIT_METERS, 0.02)
    local y = math.max(math.abs(size.y) * SOURCE_UNIT_METERS, 0.02)
    local z = math.max(math.abs(size.z) * SOURCE_UNIT_METERS, 0.02)
    local volume = x * y * z
    local longest = math.max(x, y, z)
    local shortest = math.max(math.min(x, y, z), 0.02)
    local thinness = math.Clamp(longest / shortest, 1, 12)
    local shapeFactor = Lerp(math.Clamp((thinness - 1) / 11, 0, 1), 1, 0.72)

    return math.Clamp(volume * 120 * shapeFactor, 0.05, 800)
end

local function GetPlayerPickupLimit(ply, settings, rule)
    local pickupLimit = NumberOr(ply.pmavPickupLimitKg, -1)

    if pickupLimit < 0 then
        local _
        _, pickupLimit = GetPlayerMassAndPickupLimit(ply, settings, rule)
    end

    return pickupLimit
end

local function CanPlayerPickupByAdaptiveMass(ply, ent, mode)
    if not IsValid(ply) or not IsValid(ent) then
        return nil
    end

    local settings = GetSettingsForPlayer(ply)

    if not settings or not settings.enabled or not settings.adaptivePickupWeight then
        ply.pmavHeavyPickupEnt = nil
        ply.pmavHeavyPickupWeight = nil
        ply.pmavHeavyPickupLimit = nil
        return nil
    end

    local rule = GetRule(settings, GetPlayerRuleModel(ply, settings))

    if rule and rule.mode == "off" then
        return nil
    end

    local pickupLimit = GetPlayerPickupLimit(ply, settings, rule)

    if pickupLimit <= 0 then
        return false
    end

    local pickupWeight = GetEntityPickupWeightKg(ent)

    if not pickupWeight or pickupWeight <= 0 then
        return nil
    end

    local ratio = pickupWeight / math.max(pickupLimit, 0.001)

    if ratio > (mode == "physgun" and 1.8 or 1.0) then
        return false
    end

    if mode == "physgun" then
        ply.pmavHeavyPickupEnt = ent
        ply.pmavHeavyPickupWeight = pickupWeight
        ply.pmavHeavyPickupLimit = pickupLimit
    end

    return nil
end

hook.Add("PhysgunPickup", "pm_eblansky_adaptive_view_pickup_weight", function(ply, ent)
    if IsValid(ply) then
        ply.pmavHeavyPickupEnt = nil
        ply.pmavHeavyPickupWeight = nil
        ply.pmavHeavyPickupLimit = nil
    end

    -- Do not limit the physgun. Adaptive pickup weight is gameplay flavor for
    -- normal hand pickup; the physgun is a sandbox/build tool and must stay usable.
    return nil
end)

hook.Add("PhysgunDrop", "pm_eblansky_adaptive_view_pickup_weight", function(ply, ent)
    if ply.pmavHeavyPickupEnt == ent then
        ply.pmavHeavyPickupEnt = nil
        ply.pmavHeavyPickupWeight = nil
        ply.pmavHeavyPickupLimit = nil
    end
end)

hook.Add("AllowPlayerPickup", "pm_eblansky_adaptive_view_use_pickup_weight", function(ply, ent)
    return CanPlayerPickupByAdaptiveMass(ply, ent, "use")
end)

hook.Remove("GravGunPickupAllowed", "pm_eblansky_adaptive_view_pickup_weight")

local PLAYER_ENGINE_MASS_KG = 85
local SOURCE_GRAVITY = 600

local function ApplyAdaptiveHeldPickupWeight(ply)
    local ent = ply.pmavHeavyPickupEnt

    if not IsValid(ply) or not IsValid(ent) then
        ply.pmavHeavyPickupEnt = nil
        return
    end

    local settings = GetSettingsForPlayer(ply)

    if not settings or not settings.enabled or not settings.adaptivePickupWeight then
        ply.pmavHeavyPickupEnt = nil
        return
    end

    local limit = math.max(NumberOr(ply.pmavHeavyPickupLimit, 0), 0.001)
    local weight = math.max(NumberOr(ply.pmavHeavyPickupWeight, 0), 0)
    local ratio = weight / limit

    if ratio < 0.65 or not isfunction(ent.GetPhysicsObject) then
        return
    end

    local phys = ent:GetPhysicsObject()

    if not IsValid(phys) or not isfunction(phys.ApplyForceCenter) then
        return
    end

    local heaviness = math.Clamp((ratio - 0.65) / 1.15, 0, 1)
    local pull = (weight * SOURCE_GRAVITY) * Lerp(heaviness * heaviness, 0.25, 3.5)

    phys:ApplyForceCenter(Vector(0, 0, -pull))
end

local function ApplyAdaptivePlayerWeight(ply)
    if not IsValid(ply) or not ply:Alive() then
        return
    end

    local settings = GetSettingsForPlayer(ply)

    if not settings or not settings.enabled then
        return
    end

    local rule = GetRule(settings, GetPlayerRuleModel(ply, settings))

    if rule and rule.mode == "off" then
        return
    end

    local massKg = NumberOr(ply.pmavMassKg, -1)

    if massKg < 0 then
        massKg = GetPlayerMassAndPickupLimit(ply, settings, rule)
    end

    massKg = math.Clamp(NumberOr(massKg, PLAYER_ENGINE_MASS_KG), 0, 500)

    if math.abs(massKg - PLAYER_ENGINE_MASS_KG) < 0.5 then
        return
    end

    local ground = isfunction(ply.GetGroundEntity) and ply:GetGroundEntity()

    if not IsValid(ground) or ground:IsWorld() or not isfunction(ground.GetPhysicsObject) then
        return
    end

    local phys = ground:GetPhysicsObject()

    if not IsValid(phys) or not phys:IsMotionEnabled() or not isfunction(phys.ApplyForceOffset) then
        return
    end

    local compensation = math.Clamp(PLAYER_ENGINE_MASS_KG - massKg, -350, 350) * SOURCE_GRAVITY
    phys:ApplyForceOffset(Vector(0, 0, compensation), ply:GetPos())
end

hook.Add("Tick", "pm_eblansky_adaptive_view_player_weight", function()
    for _, ply in ipairs(player.GetAll()) do
        ApplyAdaptiveHeldPickupWeight(ply)
    end
end)

local function IsPlayerHullStuck(ply, pos)
    local trace = TracePlayerHullAt(ply, pos or ply:GetPos())

    return trace and (trace.StartSolid or trace.AllSolid or trace.Hit) or false
end

local function IsPlayerInNoclip(ply)
    return IsValid(ply) and isfunction(ply.GetMoveType) and ply:GetMoveType() == MOVETYPE_NOCLIP
end

local function TryUnstuckPlayer(ply)
    if IsPlayerInNoclip(ply) then
        ply.pmavStuckSince = nil
        return false
    end

    local origin = ply:GetPos()

    if not IsPlayerHullStuck(ply, origin) then
        return true
    end

    local directions = {
        Vector(1, 0, 0),
        Vector(-1, 0, 0),
        Vector(0, 1, 0),
        Vector(0, -1, 0),
        Vector(1, 1, 0):GetNormalized(),
        Vector(1, -1, 0):GetNormalized(),
        Vector(-1, 1, 0):GetNormalized(),
        Vector(-1, -1, 0):GetNormalized()
    }

    for _, z in ipairs({0, 8, 16, 32}) do
        for radius = 16, 160, 16 do
            for _, direction in ipairs(directions) do
                local candidate = origin + direction * radius + Vector(0, 0, z)

                if not IsPlayerHullStuck(ply, candidate) then
                    ply:SetPos(candidate)
                    ply:SetLocalVelocity(vector_origin)
                    ply.pmavStuckSince = nil
                    return true
                end
            end
        end
    end

    return false
end

local function IsAdaptiveWorldEntity(ent)
    if not IsValid(ent) or ent:IsPlayer() or ent:IsWeapon() then
        return false
    end

    local class = ent:GetClass()

    local isNextBot = isfunction(ent.IsNextBot) and ent:IsNextBot()

    return ent:IsNPC() or isNextBot or ClassLooksAdaptive(class)
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
    if not IsValid(ent) then
        return
    end

    ent.pmavBlockExternalCollisionBounds = false
    ent.pmavAdaptiveBoundsApplied = false
    ent.pmavAdaptiveBoundsAppliedAt = nil
    ent.pmavLastBulletHitPos = nil
    ent.pmavLastBulletHitTime = nil
    ent.pmavLastAppliedModel = NormalizeModel(ent:GetModel())

    if not ent.pmavBoundsCaptured or not ent.pmavDefaultCollisionMins or not ent.pmavDefaultCollisionMaxs then
        ent.pmavLastBoundsMins = nil
        ent.pmavLastBoundsMaxs = nil
        return
    end

    ent.pmavLastBoundsMins = Vector(ent.pmavDefaultCollisionMins.x, ent.pmavDefaultCollisionMins.y, ent.pmavDefaultCollisionMins.z)
    ent.pmavLastBoundsMaxs = Vector(ent.pmavDefaultCollisionMaxs.x, ent.pmavDefaultCollisionMaxs.y, ent.pmavDefaultCollisionMaxs.z)

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
    ent.pmavCreatedAt = ent.pmavCreatedAt or CurTime()

    local model = NormalizeModel(ent:GetModel())

    if ent.pmavLastAppliedModel ~= nil and ent.pmavLastAppliedModel ~= model then
        ent.pmavBoundsCaptured = nil
        ent.pmavDefaultCollisionMins = nil
        ent.pmavDefaultCollisionMaxs = nil
        ent.pmavLastBoundsMins = nil
        ent.pmavLastBoundsMaxs = nil
    end

    ent.pmavLastAppliedModel = model
    CaptureEntityDefaults(ent)

    local settings = CopySettingsForWorld(AV.SharedSettings)
    local rule = GetRule(settings, model)

    if settings.collisionOnlyPlayers or not settings.npcCollision or not settings.enabled or rule and rule.mode == "off" or not settings.collision or settings.collisionMode <= 0 then
        RestoreEntity(ent)
        return
    end

    local resizeHeight = settings.collisionMode == 1 or settings.collisionMode == 3
    local resizeWidth = settings.collisionMode == 2 or settings.collisionMode == 3
    local modelMins, modelMaxs = GetStableModelBounds(ent, Vector(-16, -16, 0), Vector(16, 16, 72))
    modelMins, modelMaxs = ScaleBounds(modelMins, modelMaxs, GetAdaptiveModelScale(ent, settings))

    local targetHeight = GetEntityTargetHeight(ent, settings, modelMins, modelMaxs)

    if not targetHeight then
        RestoreEntity(ent)
        return
    end

    local mins = Vector(-16, -16, ent.pmavDefaultCollisionMins.z)
    local maxs = Vector(16, 16, resizeHeight and math.Clamp(targetHeight, 18, 180) or ent.pmavDefaultCollisionMaxs.z)

    if resizeWidth then
        local minX, minY, maxX, maxY = GetSaneHorizontalBounds(modelMins, modelMaxs, ent.pmavDefaultCollisionMins, ent.pmavDefaultCollisionMaxs)
        minX, minY, maxX, maxY = ApplyRuleHorizontalOverrides(rule, minX, minY, maxX, maxY, GetAdaptiveModelScale(ent, settings))
        minX, minY, maxX, maxY = ClampAutoHorizontalBounds(rule, minX, minY, maxX, maxY)
        minX, minY, maxX, maxY = LockAutoHorizontalAspect(rule, minX, minY, maxX, maxY)

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

local function ResyncAllAdaptivePlayers()
    for _, ply in ipairs(player.GetAll()) do
        InvalidatePlayerStableState(ply)
        ApplyPlayer(ply)
    end

    ScheduleAllEntitiesApply()
end

concommand.Add("pmav_resync_scale", function(ply)
    if IsValid(ply) and not IsSettingsEditAllowed(ply) then
        return
    end

    ResyncAllAdaptivePlayers()
end)

local function GetWorldSettingsSignature(settings)
    settings = settings or AV.SharedSettings or SanitizeSettings({})
    local ruleParts = {}

    for model, rule in SortedPairs(settings.rules or {}) do
        ruleParts[#ruleParts + 1] = table.concat({
            NormalizeModel(model),
            tostring(rule.mode or ""),
            tostring(math.Round(NumberOr(rule.height, 0), 3)),
            tostring(math.Round(NumberOr(rule.offset, 0), 3)),
            tostring(math.Round(NumberOr(rule.cameraOffset, 0), 3)),
            tostring(math.Round(NumberOr(rule.duckCameraHeight, 0), 3)),
            tostring(math.Round(NumberOr(rule.collisionHeight, 0), 3)),
            tostring(math.Round(NumberOr(rule.collisionWidth, 0), 3)),
            tostring(math.Round(NumberOr(rule.collisionLength, 0), 3)),
            tostring(math.Round(NumberOr(rule.collisionMinX, 0), 3)),
            tostring(math.Round(NumberOr(rule.collisionMaxX, 0), 3)),
            tostring(math.Round(NumberOr(rule.collisionMinY, 0), 3)),
            tostring(math.Round(NumberOr(rule.collisionMaxY, 0), 3)),
            tostring(math.Round(NumberOr(rule.cameraOffsetX, 0), 3)),
            tostring(math.Round(NumberOr(rule.cameraOffsetY, 0), 3)),
            rule.pinCameraOnEye and "1" or "0",
            tostring(math.Round(NumberOr(rule.pinEyeSmoothing, 0), 3)),
            tostring(math.Round(NumberOr(rule.speed, -1), 3)),
            tostring(math.Round(NumberOr(rule.jump, -1), 3))
        }, ":")
    end

    return table.concat({
        settings.enabled and "1" or "0",
        settings.collision and "1" or "0",
        tostring(settings.collisionMode or 0),
        settings.collisionOnlyPlayers and "1" or "0",
        settings.npcCollision and "1" or "0",
        settings.adaptiveSpeed and "1" or "0",
        settings.adaptiveJump and "1" or "0",
        settings.adaptivePickupWeight and "1" or "0",
        tostring(settings.autoScale or 0),
        tostring(settings.globalOffset or 0),
        tostring(settings.cameraFov or 0),
        tostring(settings.cameraOffsetX or 0),
        tostring(settings.cameraOffsetY or 0),
        settings.scaleSupport and "1" or "0",
        tostring(settings.scaleMin or 0),
        tostring(settings.scaleMax or 0),
        tostring(settings.minHeight or 0),
        tostring(settings.maxHeight or 0),
        table.concat(ruleParts, ",")
    }, "|")
end

local function SmoothApplyPlayer(ply, fromStand, fromDuck, toStand, toDuck, settings)
    local rule = GetRule(settings, GetPlayerRuleModel(ply, settings))
    local duration = rule and rule.pinCameraOnEye == true and math.Clamp(NumberOr(rule.pinEyeSmoothing, 0.50), 0, 1) * 1.50 or 0

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
    if not IsSettingsEditAllowed(ply) then
        return
    end

    local now = CurTime()

    if IsValid(ply) then
        if ply.pmavNextSettingsNet and ply.pmavNextSettingsNet > now then
            return
        end

        ply.pmavNextSettingsNet = now + NET_SETTINGS_COOLDOWN
    end

    if isfunction(net.BytesLeft) and net.BytesLeft() > MAX_NET_SETTINGS_BITS then
        return
    end

    local incomingSettings = net.ReadTable()

    CaptureDefaults(ply)

    local oldSettings = AV.PlayerSettings[ply]
    local oldRule = oldSettings and GetRule(oldSettings, GetPlayerRuleModel(ply, oldSettings))
    local oldEnabled = oldSettings and oldSettings.enabled
    local fromStand, fromDuck = GetAppliedHeights(ply)
    AV.PlayerSettings[ply] = SanitizeSettings(incomingSettings)
    local settings = AV.PlayerSettings[ply]

    if AV.PlayerEnabledOverride[ply] ~= nil then
        settings.enabled = AV.PlayerEnabledOverride[ply]

        if not settings.enabled then
            settings.collision = false
            settings.npcCollision = false
            settings.adaptiveSpeed = false
            settings.adaptiveJump = false
        end
    end

    local oldWorldSignature = AV.WorldSettingsSignature
    AV.SharedSettings = CopySettingsForWorld(settings)
    local newWorldSignature = GetWorldSettingsSignature(AV.SharedSettings)
    local toStand, toDuck = GetTargetHeights(ply, settings)
    local smoothing = false

    if not settings.enabled then
        timer.Remove("pmav_smooth_" .. ply:EntIndex())
        RestorePlayer(ply, true)

        for _, delay in ipairs({0, 0.25, 1, 2}) do
            timer.Simple(delay, function()
                if AV.Generation ~= GENERATION or not IsValid(ply) then
                    return
                end

                RestorePlayer(ply, true)
            end)
        end

        if oldWorldSignature ~= newWorldSignature then
            AV.WorldSettingsSignature = newWorldSignature
            ScheduleAllEntitiesApply()
        end

        return
    end

    if not toStand then
        toStand = ply.pmavDefaultStand.z
        toDuck = ply.pmavDefaultDuck.z
    end

    local newRule = GetRule(settings, GetPlayerRuleModel(ply, settings))
    local pinChanged = oldRule and newRule and oldRule.pinCameraOnEye ~= newRule.pinCameraOnEye

    if oldEnabled ~= nil and (oldEnabled ~= settings.enabled or pinChanged) then
        smoothing = true
        SmoothApplyPlayer(ply, fromStand, fromDuck, toStand, toDuck, settings)
    else
        ApplyPlayer(ply)
    end

    if not smoothing then
        for _, delay in ipairs({0, 0.25, 1, 2}) do
            timer.Simple(delay, function()
                if AV.Generation ~= GENERATION then
                    return
                end

                ApplyPlayer(ply)
            end)
        end
    end

    if oldWorldSignature ~= newWorldSignature then
        AV.WorldSettingsSignature = newWorldSignature
        ScheduleAllEntitiesApply()
    end
end)

concommand.Add("pmav_set_enabled", function(ply, _, args)
    if IsValid(ply) and not IsSettingsEditAllowed(ply) then
        return
    end

    local enabled = tostring(args and args[1] or "1") ~= "0"

    if IsValid(ply) then
        AV.PlayerEnabledOverride[ply] = enabled
        CaptureDefaults(ply)

        local settings = SanitizeSettings(AV.PlayerSettings[ply] or CopySettingsForWorld(AV.SharedSettings))
        settings.enabled = enabled
        settings.collision = enabled and settings.collision or false
        settings.npcCollision = enabled and settings.npcCollision or false
        settings.adaptiveSpeed = enabled and settings.adaptiveSpeed or false
        settings.adaptiveJump = enabled and settings.adaptiveJump or false
        settings.adaptivePickupWeight = enabled and settings.adaptivePickupWeight or false

        AV.PlayerSettings[ply] = settings
        AV.SharedSettings = CopySettingsForWorld(settings)
        AV.WorldSettingsSignature = GetWorldSettingsSignature(AV.SharedSettings)

        timer.Remove("pmav_smooth_" .. ply:EntIndex())

        if enabled then
            ApplyPlayer(ply)
        else
            RestorePlayer(ply, true)
        end
    else
        local settings = SanitizeSettings(AV.SharedSettings or {})
        settings.enabled = enabled
        settings.collision = enabled and settings.collision or false
        settings.npcCollision = enabled and settings.npcCollision or false
        settings.adaptiveSpeed = enabled and settings.adaptiveSpeed or false
        settings.adaptiveJump = enabled and settings.adaptiveJump or false
        settings.adaptivePickupWeight = enabled and settings.adaptivePickupWeight or false
        AV.SharedSettings = CopySettingsForWorld(settings)
    end

    ScheduleAllEntitiesApply()
end)

hook.Add("OnEntityCreated", "pm_eblansky_adaptive_view_entities", function(ent)
    ent.pmavCreatedAt = CurTime()
    ScheduleEntityApply(ent)
end)

hook.Add("EntityRemoved", "pm_eblansky_adaptive_view_entities", function(ent)
    AV.ManagedEntities[ent] = nil
end)

timer.Create("pm_eblansky_adaptive_view_entity_model_watch", 1, 0, function()
    if AV.Generation ~= GENERATION then
        timer.Remove("pm_eblansky_adaptive_view_entity_model_watch")
        return
    end

    for ent in pairs(AV.ManagedEntities) do
        if not IsValid(ent) then
            AV.ManagedEntities[ent] = nil
        else
            local model = NormalizeModel(ent:GetModel())

            if model ~= ent.pmavLastAppliedModel then
                ApplyEntity(ent)
            end
        end
    end
end)

hook.Remove("EntityFireBullets", "pm_eblansky_adaptive_view_bullet_bounds")
hook.Remove("ScaleNPCDamage", "pm_eblansky_adaptive_view_damage_bounds")
hook.Remove("EntityTakeDamage", "pm_eblansky_adaptive_view_damage_bounds")

hook.Add("PlayerSpawn", "pm_eblansky_adaptive_view", function(ply)
    InvalidatePlayerStableState(ply)
    ApplyPlayer(ply)

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
    ApplyPlayer(ply)

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

hook.Add("OnPlayerHitGround", "pm_eblansky_adaptive_view_soft_landing", function(ply, inWater, onFloater, speed)
    if not IsValid(ply) or inWater or onFloater then
        return
    end

    local settings = GetSettingsForPlayer(ply)

    if not settings or not settings.enabled then
        return
    end

    local rule = GetRule(settings, GetPlayerRuleModel(ply, settings))

    if not settings.adaptiveJump and not (rule and NumberOr(rule.jump, -1) ~= -1) then
        return
    end

    local jumpScale = NumberOr(ply.pmavJumpScale, 1)

    if jumpScale >= 0.95 then
        return
    end

    -- Tiny adaptive hulls should not play heavy landing behavior after a
    -- normal scaled jump, but real high-speed falls still pass through.
    if NumberOr(speed, 0) <= 520 then
        return true
    end
end)

hook.Add("PlayerDisconnected", "pm_eblansky_adaptive_view", function(ply)
    AV.PlayerSettings[ply] = nil
    AV.PlayerEnabledOverride[ply] = nil
end)

hook.Add("Think", "pm_eblansky_adaptive_view_stuck_watch", function()
    if AV.NextStuckWatch and AV.NextStuckWatch > CurTime() then
        return
    end

    AV.NextStuckWatch = CurTime() + 0.25

    for _, ply in ipairs(player.GetAll()) do
        local settings = IsValid(ply) and GetSettingsForPlayer(ply)
        local modelScale = settings and GetAdaptiveModelScale(ply, settings) or 1

        if IsValid(ply) and (not ply.pmavLastAdaptiveModelScale or math.abs(ply.pmavLastAdaptiveModelScale - modelScale) > 0.001) then
            ply.pmavLastAdaptiveModelScale = modelScale
            InvalidatePlayerStableState(ply)
            ApplyPlayer(ply)
        end

        if IsValid(ply) and IsPlayerInNoclip(ply) then
            ply.pmavStuckSince = nil
        elseif IsValid(ply) and ply:Alive() and IsPlayerAdaptiveCollisionActive(ply) then
            if IsPlayerHullStuck(ply) then
                ply.pmavStuckSince = ply.pmavStuckSince or CurTime()

                if CurTime() - ply.pmavStuckSince >= 5 then
                    TryUnstuckPlayer(ply)
                end
            else
                ply.pmavStuckSince = nil
            end
        elseif IsValid(ply) then
            ply.pmavStuckSince = nil
        end
    end
end)

timer.Simple(0.25, function()
    if AV.Generation ~= GENERATION then
        return
    end

    for _, ply in ipairs(player.GetAll()) do
        InvalidatePlayerStableState(ply, true)
        ApplyPlayer(ply)
    end

    ScheduleAllEntitiesApply()
end)
