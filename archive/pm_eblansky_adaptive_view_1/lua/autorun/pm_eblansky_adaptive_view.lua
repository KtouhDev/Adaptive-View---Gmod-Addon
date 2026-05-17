PM_EBLANSKY_ADAPTIVE_VIEW = PM_EBLANSKY_ADAPTIVE_VIEW or {}

local AV = PM_EBLANSKY_ADAPTIVE_VIEW
local NET_SETTINGS = "pmav_settings"

if SERVER then
    AddCSLuaFile("autorun/client/pm_eblansky_adaptive_view.lua")
    util.AddNetworkString(NET_SETTINGS)
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

local function NearlyEqualVector(a, b, epsilon)
    epsilon = epsilon or 0.01

    return math.abs(a.x - b.x) <= epsilon and math.abs(a.y - b.y) <= epsilon and math.abs(a.z - b.z) <= epsilon
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
        return
    end

    ply.pmavLastHullMins = Vector(mins.x, mins.y, mins.z)
    ply.pmavLastHullMaxs = Vector(maxs.x, maxs.y, maxs.z)
    ply.pmavLastDuckMins = Vector(duckMins.x, duckMins.y, duckMins.z)
    ply.pmavLastDuckMaxs = Vector(duckMaxs.x, duckMaxs.y, duckMaxs.z)

    ply:SetHull(mins, maxs)
    ply:SetHullDuck(duckMins, duckMaxs)
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
        multiplayerSafe = settings.multiplayerSafe ~= false,
        rules = rules
    }
end

local function GetRule(settings, model)
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
        modelHeight = math.max(NumberOr(maxs.z, 72) * settings.autoScale, 1)
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
    local footSafeHeight = math.max(NumberOr(mins.z, 0) + 8, 4)
    standHeight = math.Clamp(standHeight, footSafeHeight, math.max(settings.maxHeight, footSafeHeight))

    local defaultStand = ply.pmavDefaultStand or Vector(0, 0, 64)
    local defaultDuck = ply.pmavDefaultDuck or Vector(0, 0, 28)
    local duckRatio = defaultStand.z ~= 0 and defaultDuck.z / defaultStand.z or 0.4375
    local duckHeight = math.max(standHeight * duckRatio, footSafeHeight)

    return standHeight, duckHeight, mins, maxs
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
        local hullHeight = resizeHeight and math.Clamp(standHeight + 8, 18, 180) or ply.pmavDefaultHullMaxs.z
        local duckHullHeight = resizeHeight and math.Clamp(duckHeight + 6, 12, 120) or ply.pmavDefaultDuckMaxs.z
        local hullMins = ply.pmavDefaultHullMins
        local duckHullMins = ply.pmavDefaultDuckMins
        local hullMaxs = Vector(ply.pmavDefaultHullMaxs.x, ply.pmavDefaultHullMaxs.y, hullHeight)
        local duckHullMaxs = Vector(ply.pmavDefaultDuckMaxs.x, ply.pmavDefaultDuckMaxs.y, duckHullHeight)

        if resizeWidth then
            local modelMins, modelMaxs = ply:GetModelBounds()
            local minX = math.min(NumberOr(modelMins.x, ply.pmavDefaultHullMins.x), -8)
            local minY = math.min(NumberOr(modelMins.y, ply.pmavDefaultHullMins.y), -8)
            local maxX = math.max(NumberOr(modelMaxs.x, ply.pmavDefaultHullMaxs.x), 8)
            local maxY = math.max(NumberOr(modelMaxs.y, ply.pmavDefaultHullMaxs.y), 8)

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
end

local function RestoreEntity(ent)
    if not IsValid(ent) or not ent.pmavBoundsCaptured then
        return
    end

    ent:SetCollisionBounds(ent.pmavDefaultCollisionMins, ent.pmavDefaultCollisionMaxs)
end

local function ApplyEntity(ent)
    if not IsAdaptiveWorldEntity(ent) then
        return
    end

    CaptureEntityDefaults(ent)

    local settings = CopySettingsForWorld(AV.SharedSettings)

    if not settings.enabled or not settings.collision or settings.collisionMode <= 0 then
        RestoreEntity(ent)
        return
    end

    local resizeHeight = settings.collisionMode == 1 or settings.collisionMode == 3
    local resizeWidth = settings.collisionMode == 2 or settings.collisionMode == 3
    local modelMins, modelMaxs = ent:GetModelBounds()

    if not modelMins or not modelMaxs then
        return
    end

    local mins = Vector(ent.pmavDefaultCollisionMins.x, ent.pmavDefaultCollisionMins.y, ent.pmavDefaultCollisionMins.z)
    local maxs = Vector(ent.pmavDefaultCollisionMaxs.x, ent.pmavDefaultCollisionMaxs.y, ent.pmavDefaultCollisionMaxs.z)

    if resizeWidth then
        mins.x = NumberOr(modelMins.x, mins.x)
        mins.y = NumberOr(modelMins.y, mins.y)
        maxs.x = NumberOr(modelMaxs.x, maxs.x)
        maxs.y = NumberOr(modelMaxs.y, maxs.y)
    end

    if resizeHeight then
        maxs.z = NumberOr(modelMaxs.z, maxs.z)
    end

    ent:SetCollisionBounds(mins, maxs)
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
    AV.SharedSettings = CopySettingsForWorld(settings)
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
            ApplyPlayer(ply)
        end)
    end
end)

hook.Add("OnEntityCreated", "pm_eblansky_adaptive_view_entities", function(ent)
    timer.Simple(0, function()
        ApplyEntity(ent)
    end)

    timer.Simple(0.25, function()
        ApplyEntity(ent)
    end)
end)

hook.Add("PlayerSpawn", "pm_eblansky_adaptive_view", function(ply)
    InvalidatePlayerStableState(ply)

    timer.Simple(0, function()
        ApplyPlayer(ply)
    end)

    timer.Simple(0.25, function()
        ApplyPlayer(ply)
    end)

    timer.Simple(1, function()
        ApplyPlayer(ply)
    end)
end)

hook.Add("PlayerSetModel", "pm_eblansky_adaptive_view", function(ply)
    InvalidatePlayerStableState(ply)

    timer.Simple(0, function()
        ApplyPlayer(ply)
    end)

    timer.Simple(0.25, function()
        ApplyPlayer(ply)
    end)

    timer.Simple(1, function()
        ApplyPlayer(ply)
    end)
end)

hook.Add("PlayerDeath", "pm_eblansky_adaptive_view", function(ply)
    InvalidatePlayerStableState(ply)
end)

hook.Add("PlayerDisconnected", "pm_eblansky_adaptive_view", function(ply)
    AV.PlayerSettings[ply] = nil
end)

timer.Create("pm_eblansky_adaptive_view_world_entities", 1, 0, function()
    for _, ply in ipairs(player.GetAll()) do
        if ply:Alive() then
            ApplyPlayer(ply)
        end
    end

    for _, ent in ipairs(ents.GetAll()) do
        ApplyEntity(ent)
    end
end)
