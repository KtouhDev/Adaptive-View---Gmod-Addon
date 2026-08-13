if SERVER then return end

PM_EBLANSKY_ADAPTIVE_VIEW = PM_EBLANSKY_ADAPTIVE_VIEW or {}

local AV = PM_EBLANSKY_ADAPTIVE_VIEW
local DATA_FILE = "pm_eblansky_adaptive_view/models.json"
local OpenThanksWindow

AV.ModernIconMaterials = {}

local cvEnabled = CreateClientConVar("pmav_enabled", "1", true, false, "Enable Adaptive View add-on logic.")
local cvAutoScale = CreateClientConVar("pmav_auto_scale", "0.92", true, false, "Part of model height used as eye height.")
local cvGlobalOffset = CreateClientConVar("pmav_global_offset", "0", true, false, "Global camera height offset.")
local cvCameraFov = CreateClientConVar("pmav_camera_fov", "0", true, false, "Reserved camera FOV override. 0 keeps the game default.")
local cvCameraOffsetX = CreateClientConVar("pmav_camera_offset_x", "0", true, false, "Reserved camera local X offset.")
local cvCameraOffsetY = CreateClientConVar("pmav_camera_offset_y", "0", true, false, "Reserved camera local Y offset.")
local cvScaleSupport = CreateClientConVar("pmav_scale_support", "1", true, false, "Account for model scale from ULX scale and similar addons.")
local cvScaleMin = CreateClientConVar("pmav_scale_min", "0.5", true, false, "Minimum model scale Adaptive View will use.")
local cvScaleMax = CreateClientConVar("pmav_scale_max", "2", true, false, "Maximum model scale Adaptive View will use.")
local cvSmooth = CreateClientConVar("pmav_smooth", "10", true, false, "Hidden option-switch smoothing speed.")
local cvMinHeight = CreateClientConVar("pmav_min_height", "4", true, false, "Minimum standing camera height.")
local cvMaxHeight = CreateClientConVar("pmav_max_height", "120", true, false, "Maximum standing camera height.")
local cvCollision = CreateClientConVar("pmav_collision", "1", true, false, "Resize player collision hull with adaptive height.")
local cvCollisionMode = CreateClientConVar("pmav_collision_mode", "3", true, false, "Adaptive collision mode: 0 none, 1 height, 2 width/length, 3 all.")
local cvCollisionRadius = CreateClientConVar("pmav_collision_radius", "16", true, false, "Adaptive player collision hull half-width.")
local cvCollisionOnlyPlayers = CreateClientConVar("pmav_collision_only_players", "0", true, false, "Apply Adaptive View collision only to players.")
local cvNpcCollision = CreateClientConVar("pmav_npc_collision", "0", true, false, "Apply Adaptive View collision to NPCs and NextBots.")
local cvMultiplayerSafe = CreateClientConVar("pmav_multiplayer_safe", "1", true, false, "Avoid shrinking player width/length in multiplayer.")
local cvAdaptiveSpeed = CreateClientConVar("pmav_adaptive_speed", "0", true, false, "Scale walk/run speed from adaptive hitbox height.")
local cvAdaptiveJump = CreateClientConVar("pmav_adaptive_jump", "0", true, false, "Scale jump power from adaptive hitbox height.")
local cvAdaptivePickupWeight = CreateClientConVar("pmav_adaptive_pickup_weight", "0", true, false, "Apply Adaptive View pickup weight limits.")
local cvDebugBounds = CreateClientConVar("pmav_debug_bounds", "0", true, false, "Draw Adaptive View debug collision bounds.")
local cvNpcCollisionDefaultMigration = CreateClientConVar("pmav_npc_collision_default_migration", "0", true, false, "Internal Adaptive View migration for NPC collision default.")
local cvSupportOutfitter = CreateClientConVar("pm_supp_outfitter", "1", true, false, "Enable compatibility support for Outfitter: Multiplayer Playermodels.")
local cvSupportIKFoot = CreateClientConVar("pm_supp_ikfoot", "1", true, false, "Enable compatibility support for IK Foot System.")
local cvModernUnits = CreateClientConVar("pmav_modern_units", "metric", true, false, "Modern UI units: metric or imperial.")

local SOURCE_UNIT_METERS = 0.01905
local METERS_TO_FEET = 3.280839895
local KG_TO_LB = 2.2046226218
local MODERN_PROFILE_FOV = 35
-- Hueglot note: чмо блять хуй пенис пизда,
-- ало шлюхис грушич победитор поездатор.
-- local MODERN_HULL_SERVER_VISUAL_BIAS = 2

surface.CreateFont("PMAVModernGeneralTitle", {
    font = "Roboto",
    size = 24,
    weight = 400,
    antialias = true
})

surface.CreateFont("PMAVModernGeneralRuleTitle", {
    font = "Roboto",
    size = 27,
    weight = 400,
    antialias = true
})

surface.CreateFont("PMAVModernGeneralText", {
    font = "Roboto",
    size = 18,
    weight = 400,
    antialias = true
})

surface.CreateFont("PMAVModernGeneralUnit", {
    font = "Roboto",
    size = 19,
    weight = 700,
    antialias = true
})

surface.CreateFont("PMAVModernGeneralSmall", {
    font = "Roboto",
    size = 13,
    weight = 400,
    antialias = true
})

AV.ModelRules = AV.ModelRules or {}
AV.SmoothedOffset = AV.SmoothedOffset or 0
AV.LastViewOffset = AV.LastViewOffset or vector_origin
AV.ServerBounds = {}

local function NormalizeModel(model)
    return string.lower(string.Trim(tostring(model or "")))
end

local function GetAdaptiveLookupModel(ent)
    if not IsValid(ent) then
        return ""
    end

    if not cvSupportOutfitter:GetBool() then
        return NormalizeModel(ent:GetModel())
    end

    local enforced = ent.enforce_model

    if (not enforced or enforced == "") and isfunction(ent.GetEnforceModel) then
        enforced = ent:GetEnforceModel()
    end

    return NormalizeModel(enforced and enforced ~= "" and enforced or ent:GetModel())
end

local function NumberOr(value, fallback)
    value = tonumber(value)

    if value == nil then
        return fallback
    end

    return value
end

local function IsOutfitterEnforcing(ent)
    if not IsValid(ent) then
        return false
    end

    if not cvSupportOutfitter:GetBool() then
        return false
    end

    if ent.enforce_model and ent.enforce_model ~= "" then
        return true
    end

    return isfunction(ent.GetEnforceModel) and ent:GetEnforceModel() ~= nil
end

function AV.GetAdaptiveLookupModel(ent)
    return GetAdaptiveLookupModel(IsValid(ent) and ent or LocalPlayer())
end

local function IsIKFootActive(ent)
    if not IsValid(ent) then
        return false
    end

    if not cvSupportIKFoot:GetBool() then
        return false
    end

    local cvar = GetConVar("ik_foot")

    if not cvar or not cvar:GetBool() then
        return false
    end

    return istable(IKFoot) or hook.GetTable().PostPlayerDraw and hook.GetTable().PostPlayerDraw.IKFoot_PostPlayerDraw ~= nil
end

local function GetIKFootPostPlayerDrawHook()
    local postPlayerDraw = hook.GetTable().PostPlayerDraw

    if not postPlayerDraw then
        return nil
    end

    if isfunction(postPlayerDraw.IKFoot_PostPlayerDraw) then
        return postPlayerDraw.IKFoot_PostPlayerDraw
    end

    for name, func in pairs(postPlayerDraw) do
        local normalizedName = string.lower(tostring(name or ""))

        if isfunction(func) and (string.find(normalizedName, "ikfoot", 1, true) or string.find(normalizedName, "ik_foot", 1, true)) then
            return func
        end
    end

    return nil
end

local function GetLocalAdaptiveModelScale(ply)
    if not cvScaleSupport:GetBool() or not IsValid(ply) or not isfunction(ply.GetModelScale) then
        return 1
    end

    local minScale = math.max(cvScaleMin:GetFloat(), 0.01)
    local maxScale = math.max(cvScaleMax:GetFloat(), minScale)

    return math.Clamp(NumberOr(ply:GetModelScale(), 1), minScale, maxScale)
end

local function GetEntityBodygroupSignature(ent)
    if not IsValid(ent) or not isfunction(ent.GetNumBodyGroups) or not isfunction(ent.GetBodygroup) then
        return ""
    end

    local parts = {}
    local count = math.Clamp(NumberOr(ent:GetNumBodyGroups(), 0), 0, 64)

    for i = 0, count - 1 do
        parts[#parts + 1] = tostring(i) .. ":" .. tostring(ent:GetBodygroup(i) or 0)
    end

    return table.concat(parts, ",")
end

local function GetEntityBoundsSignature(ent)
    if not IsValid(ent) or not isfunction(ent.GetModelBounds) then
        return ""
    end

    local mins, maxs = ent:GetModelBounds()

    if not mins or not maxs then
        return ""
    end

    return table.concat({
        tostring(math.Round(NumberOr(mins.x, 0), 2)),
        tostring(math.Round(NumberOr(mins.y, 0), 2)),
        tostring(math.Round(NumberOr(mins.z, 0), 2)),
        tostring(math.Round(NumberOr(maxs.x, 0), 2)),
        tostring(math.Round(NumberOr(maxs.y, 0), 2)),
        tostring(math.Round(NumberOr(maxs.z, 0), 2))
    }, ":")
end

local function ClassLooksAdaptive(class)
    class = string.lower(tostring(class or ""))

    return string.find(class, "npc", 1, true) ~= nil or
        string.find(class, "nextbot", 1, true) ~= nil or
        string.find(class, "lambda", 1, true) ~= nil or
        string.find(class, "zeta", 1, true) ~= nil or
        string.find(class, "drg", 1, true) ~= nil
end

local function NormalizeRule(rule)
    if not istable(rule) then
        return nil
    end

    local mode = tostring(rule.mode or "auto")

    if mode ~= "auto" and mode ~= "height" and mode ~= "off" then
        mode = "auto"
    end

    return {
        mode = mode,
        height = NumberOr(rule.height, 64),
        offset = NumberOr(rule.offset, 0),
        cameraOffset = NumberOr(rule.cameraOffset, NumberOr(rule.offset, 0)),
        duckCameraHeight = NumberOr(rule.duckCameraHeight, 0),
        collisionHeight = NumberOr(rule.collisionHeight, 0),
        collisionWidth = NumberOr(rule.collisionWidth, 0),
        collisionLength = NumberOr(rule.collisionLength, 0),
        collisionMinX = NumberOr(rule.collisionMinX, 0),
        collisionMaxX = NumberOr(rule.collisionMaxX, 0),
        collisionMinY = NumberOr(rule.collisionMinY, 0),
        collisionMaxY = NumberOr(rule.collisionMaxY, 0),
        cameraOffsetX = NumberOr(rule.cameraOffsetX, 0),
        cameraOffsetY = NumberOr(rule.cameraOffsetY, 0),
        pinCameraOnEye = rule.pinCameraOnEye == true,
        pinEyeSmoothing = NumberOr(rule.pinEyeSmoothing, 0.50),
        mass = NumberOr(rule.mass, -1),
        pickupLimit = NumberOr(rule.pickupLimit, -1),
        speed = NumberOr(rule.speed, -1),
        jump = NumberOr(rule.jump, -1)
    }
end

local function CanLocalEditSettings()
    local inJail = GetConVar("pmav_injail")

    if inJail and inJail:GetBool() then
        return false
    end

    local ply = LocalPlayer()

    if game.SinglePlayer() then
        return true
    end

    if IsValid(ply) and isfunction(ply.IsAdmin) and ply:IsAdmin() then
        return true
    end

    local cheats = GetConVar("sv_cheats")
    local allowAll = GetConVar("pmav_alladmins")

    return cheats and cheats:GetBool() and allowAll and allowAll:GetBool() or false
end

local function CanUseDebugBounds()
    local inJail = GetConVar("pmav_injail")

    if inJail and inJail:GetBool() then
        return false
    end

    return game.SinglePlayer()
end

local function AddThanksOnly(panel)
    local thanksButton = panel:Button("Thank them!")
    thanksButton.DoClick = OpenThanksWindow
end

local function AddCompatibilitySupportPanel(panel)
    local supportPanel = vgui.Create("DPanel")
    supportPanel:SetTall(64)
    supportPanel:DockPadding(10, 22, 10, 8)
    supportPanel.Paint = function(_, w, h)
        surface.SetDrawColor(88, 88, 88, 255)
        surface.DrawOutlinedRect(0, 8, w, h - 8, 1)
        draw.SimpleText("Compatibility support", "DermaDefaultBold", 10, 8, Color(235, 235, 235), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local outfitterSupport = vgui.Create("DCheckBoxLabel", supportPanel)
    outfitterSupport:Dock(TOP)
    outfitterSupport:SetText("Support Outfitter")
    outfitterSupport:SetConVar("pm_supp_outfitter")
    outfitterSupport:SetTextColor(Color(235, 235, 235))
    outfitterSupport:SizeToContents()

    panel:AddItem(supportPanel)
end

local function ReadRules()
    AV.ModelRules = {}

    if not file.Exists(DATA_FILE, "DATA") then
        return
    end

    local decoded = util.JSONToTable(file.Read(DATA_FILE, "DATA") or "")

    if not istable(decoded) then
        return
    end

    for model, rule in pairs(decoded) do
        model = NormalizeModel(model)

        if model ~= "" then
            local normalizedRule = NormalizeRule(rule)

            if normalizedRule then
                AV.ModelRules[model] = normalizedRule
            end
        end
    end
end

local function WriteRules()
    file.CreateDir("pm_eblansky_adaptive_view")
    file.Write(DATA_FILE, util.TableToJSON(AV.ModelRules, true))
end

local function ReadSavedRule(model)
    model = NormalizeModel(model)

    if model == "" or not file.Exists(DATA_FILE, "DATA") then
        return nil
    end

    local decoded = util.JSONToTable(file.Read(DATA_FILE, "DATA") or "")

    if not istable(decoded) then
        return nil
    end

    for savedModel, rule in pairs(decoded) do
        if NormalizeModel(savedModel) == model then
            return NormalizeRule(rule)
        end
    end

    return nil
end

local function DefaultRule()
    return {
        mode = "auto",
        height = 64,
        offset = 0,
        cameraOffset = 0,
        duckCameraHeight = 0,
        collisionHeight = 0,
        collisionWidth = 0,
        collisionLength = 0,
        collisionMinX = 0,
        collisionMaxX = 0,
        collisionMinY = 0,
        collisionMaxY = 0,
        cameraOffsetX = 0,
        cameraOffsetY = 0,
        pinCameraOnEye = false,
        pinEyeSmoothing = 0.50,
        mass = -1,
        pickupLimit = -1,
        speed = -1,
        jump = -1
    }
end

local function FormatMovementRuleValue(value)
    value = NumberOr(value, -1)

    if value == -1 then
        return "auto"
    end

    if value == -2 then
        return "base"
    end

    return tostring(math.Round(value, 2)) .. "x"
end

local function SourceUnitsToMeters(units)
    return NumberOr(units, 0) * SOURCE_UNIT_METERS
end

local function MetersToSourceUnits(meters)
    return NumberOr(meters, 0) / SOURCE_UNIT_METERS
end

local function FormatMeters(meters)
    local rounded = math.Round(NumberOr(meters, 0), 2)

    if math.abs(rounded - math.Round(rounded)) < 0.001 then
        return tostring(math.Round(rounded)) .. " M"
    end

    return string.Replace(string.format("%.2f", rounded), ".", ",") .. " M"
end

local function GetMetricStep(maxMeters)
    maxMeters = math.max(NumberOr(maxMeters, 1.25), 0.25)

    local step = 0.25

    while maxMeters / step > 7 do
        step = step * 2
    end

    return step
end

local function GetIconMaterial(name)
    AV.ModernIconMaterials = AV.ModernIconMaterials or {}

    if AV.ModernIconMaterials[name] ~= nil then
        return AV.ModernIconMaterials[name]
    end

    local materialPath = "4mo_icos/mui/" .. name .. ".png"
    local mat = Material(materialPath, "smooth mips")

    if mat:IsError() then
        mat = Material("../addons/pm_eblansky_adaptive_view/icos/" .. name .. ".png", "smooth mips")
    end

    if mat:IsError() then
        mat = nil
    end

    AV.ModernIconMaterials[name] = mat or false

    return mat
end

local function GetModernMaterial(path)
    AV.ModernUiMaterials = AV.ModernUiMaterials or {}

    if AV.ModernUiMaterials[path] ~= nil then
        return AV.ModernUiMaterials[path]
    end

    local mat = Material(path, "smooth mips")

    if mat:IsError() then
        mat = Material("../addons/pm_eblansky_adaptive_view/" .. path, "smooth mips")
    end

    if mat:IsError() then
        mat = nil
    end

    AV.ModernUiMaterials[path] = mat or false

    return mat
end

local function DrawModernMarkerHandle(x, y, w, h, color, state)
    state = math.Clamp(NumberOr(state, 0), 0, 2)

    local leftRadius = h * 0.5
    local hoverRightRadius = 12
    local pressedRightRadius = 7
    local rightRadius

    if state <= 1 then
        rightRadius = Lerp(state, h * 0.5, hoverRightRadius)
    else
        rightRadius = Lerp(state - 1, hoverRightRadius, pressedRightRadius)
    end

    draw.RoundedBox(leftRadius, x, y, leftRadius * 2, h, color)
    surface.SetDrawColor(color.r, color.g, color.b, color.a or 255)
    surface.DrawRect(x + leftRadius, y, math.max(w - leftRadius - rightRadius, 0), h)
    draw.RoundedBox(rightRadius, x + w - rightRadius * 2, y, rightRadius * 2, h, color)
    surface.DrawRect(x + w - rightRadius * 2, y + rightRadius, rightRadius * 2, math.max(h - rightRadius * 2, 0))
end

local function DrawModernMarkerHandleVertical(x, y, w, h, color, state)
    state = math.Clamp(NumberOr(state, 0), 0, 2)

    local bottomRadius = w * 0.5
    local hoverTopRadius = 12
    local pressedTopRadius = 7
    local topRadius

    if state <= 1 then
        topRadius = Lerp(state, w * 0.5, hoverTopRadius)
    else
        topRadius = Lerp(state - 1, hoverTopRadius, pressedTopRadius)
    end

    draw.RoundedBox(topRadius, x, y, w, topRadius * 2, color)
    surface.SetDrawColor(color.r, color.g, color.b, color.a or 255)
    surface.DrawRect(x, y + topRadius, w, math.max(h - topRadius - bottomRadius, 0))
    draw.RoundedBox(bottomRadius, x, y + h - bottomRadius * 2, w, bottomRadius * 2, color)
    surface.DrawRect(x + topRadius, y, math.max(w - topRadius * 2, 0), topRadius * 2)
end

local function DrawMaterialCenteredFit(mat, centerX, centerY, maxW, maxH)
    if not mat then
        return
    end

    local matW = math.max(NumberOr(mat:Width(), maxW), 1)
    local matH = math.max(NumberOr(mat:Height(), maxH), 1)
    local scale = math.min(maxW / matW, maxH / matH)
    local drawW = matW * scale
    local drawH = matH * scale

    surface.SetMaterial(mat)
    surface.SetDrawColor(255, 255, 255, 255)
    surface.DrawTexturedRect(centerX - drawW * 0.5, centerY - drawH * 0.5, drawW, drawH)
end

ReadRules()

if cvNpcCollisionDefaultMigration:GetInt() < 1 then
    RunConsoleCommand("pmav_npc_collision", "0")
    RunConsoleCommand("pmav_npc_collision_default_migration", "1")
end

if not CanUseDebugBounds() and cvDebugBounds:GetBool() then
    RunConsoleCommand("pmav_debug_bounds", "0")
end

function AV.GetRule(model)
    return AV.ModelRules[NormalizeModel(model)]
end

function AV.SetRule(model, mode, height, offset, cameraOffset, collisionHeight, collisionWidth, collisionLength, speed, jump, shouldSave, duckCameraHeight, collisionMinX, collisionMaxX, collisionMinY, collisionMaxY, cameraOffsetX, cameraOffsetY, pinCameraOnEye, pinEyeSmoothing, mass, pickupLimit)
    model = NormalizeModel(model)

    if model == "" then
        return
    end

    if mode == nil then
        AV.ModelRules[model] = nil
    else
        AV.ModelRules[model] = NormalizeRule({
            mode = mode,
            height = NumberOr(height, 64),
            offset = NumberOr(offset, NumberOr(cameraOffset, 0)),
            cameraOffset = NumberOr(cameraOffset, NumberOr(offset, 0)),
            duckCameraHeight = NumberOr(duckCameraHeight, NumberOr(AV.ModelRules[model] and AV.ModelRules[model].duckCameraHeight, 0)),
            collisionHeight = NumberOr(collisionHeight, 0),
            collisionWidth = NumberOr(collisionWidth, 0),
            collisionLength = NumberOr(collisionLength, 0),
            collisionMinX = NumberOr(collisionMinX, NumberOr(AV.ModelRules[model] and AV.ModelRules[model].collisionMinX, 0)),
            collisionMaxX = NumberOr(collisionMaxX, NumberOr(AV.ModelRules[model] and AV.ModelRules[model].collisionMaxX, 0)),
            collisionMinY = NumberOr(collisionMinY, NumberOr(AV.ModelRules[model] and AV.ModelRules[model].collisionMinY, 0)),
            collisionMaxY = NumberOr(collisionMaxY, NumberOr(AV.ModelRules[model] and AV.ModelRules[model].collisionMaxY, 0)),
            cameraOffsetX = NumberOr(cameraOffsetX, NumberOr(AV.ModelRules[model] and AV.ModelRules[model].cameraOffsetX, 0)),
            cameraOffsetY = NumberOr(cameraOffsetY, NumberOr(AV.ModelRules[model] and AV.ModelRules[model].cameraOffsetY, 0)),
            pinCameraOnEye = pinCameraOnEye == nil and (AV.ModelRules[model] and AV.ModelRules[model].pinCameraOnEye == true) or pinCameraOnEye == true,
            pinEyeSmoothing = NumberOr(pinEyeSmoothing, NumberOr(AV.ModelRules[model] and AV.ModelRules[model].pinEyeSmoothing, 0.50)),
            mass = NumberOr(mass, NumberOr(AV.ModelRules[model] and AV.ModelRules[model].mass, -1)),
            pickupLimit = NumberOr(pickupLimit, NumberOr(AV.ModelRules[model] and AV.ModelRules[model].pickupLimit, -1)),
            speed = NumberOr(speed, -1),
            jump = NumberOr(jump, -1)
        })
    end

    if shouldSave ~= false then
        WriteRules()
    end

    if isfunction(AV.SyncSettingsToServer) then
        AV.SyncSettingsToServer()
    end

    if isfunction(AV.RefreshRulesList) then
        AV.RefreshRulesList()
    end
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

local function GetModelHeightFromEntity(ent)
    local modelHeight =
        GetAttachmentHeight(ent, "eyes") or
        GetAttachmentHeight(ent, "forward") or
        GetBoneHeight(ent, "ValveBiped.Bip01_Head1", 2) or
        GetBoneHeight(ent, "ValveBiped.Bip01_Neck1", 7)
    local followsPose = modelHeight ~= nil

    if not modelHeight then
        local _, maxs = ent:GetModelBounds()
        modelHeight = math.max(NumberOr(maxs.z, 72) * cvAutoScale:GetFloat(), 1)
    end

    return modelHeight, followsPose
end

local function GetReferenceModelHeight(model)
    model = NormalizeModel(model)
    AV.ReferenceHeights = AV.ReferenceHeights or {}

    local cached = AV.ReferenceHeights[model]

    if istable(cached) then
        return cached.height, cached.followsPose
    end

    if isnumber(cached) then
        AV.ReferenceHeights[model] = nil
    end

    local height = nil
    local followsPose = false
    local ent = ClientsideModel(model, RENDERGROUP_OTHER)

    if IsValid(ent) then
        ent:SetNoDraw(true)
        ent:SetPos(vector_origin)
        ent:SetAngles(Angle(0, 0, 0))

        if isfunction(ent.SetupBones) then
            ent:SetupBones()
        end

        height, followsPose = GetModelHeightFromEntity(ent)
        ent:Remove()
    end

    AV.ReferenceHeights[model] = {
        height = height or 0,
        followsPose = followsPose
    }

    return AV.ReferenceHeights[model].height, AV.ReferenceHeights[model].followsPose
end

local function GetModelAutoHeight(ply)
    local modelHeight, followsPose = GetReferenceModelHeight(GetAdaptiveLookupModel(ply))
    local scale = GetLocalAdaptiveModelScale(ply)

    if not modelHeight or modelHeight <= 0 then
        if isfunction(ply.SetupBones) then
            ply:SetupBones()
        end

        modelHeight, followsPose = GetModelHeightFromEntity(ply)
    else
        modelHeight = modelHeight * scale
    end

    local minHeight = cvMinHeight:GetFloat()
    local maxHeight = math.max(cvMaxHeight:GetFloat(), minHeight)

    return math.Clamp(modelHeight, minHeight, maxHeight), followsPose
end

local function GetModelHeadBoneHeight(ply)
    if not IsValid(ply) then
        return 0
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
        return GetModelAutoHeight(ply)
    end

    local minHeight = cvMinHeight:GetFloat()
    local maxHeight = math.max(cvMaxHeight:GetFloat(), minHeight)

    return math.Clamp(modelHeight, minHeight, maxHeight), true
end

local function SmoothPinnedHeadDelta(ply, rawDelta, smooth)
    smooth = math.Clamp(NumberOr(smooth, 0.50), 0, 1)

    local posZ = ply:GetPos().z
    local lastOriginZ = ply.pmavPinLastOriginZ
    ply.pmavPinLastOriginZ = posZ
    local onGround = isfunction(ply.IsOnGround) and ply:IsOnGround()
    local speed2D = isfunction(ply.GetVelocity) and ply:GetVelocity():Length2D() or 0
    local crouching = isfunction(ply.Crouching) and ply:Crouching()
    local ikFootActive = IsIKFootActive(ply)
    local frameStep = math.max(FrameTime(), engine.TickInterval and engine.TickInterval() or 0.015)
    local currentDelta = ply.pmavPinSmoothedHeadDelta

    if currentDelta == nil then
        ply.pmavPinTargetHeadDelta = rawDelta
        ply.pmavPinSmoothedHeadDelta = rawDelta
        return rawDelta
    end

    local targetDelta = rawDelta

    if crouching or (ikFootActive and onGround) then
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

function AV.GetLocalAutoHeight()
    local ply = LocalPlayer()

    if not IsValid(ply) then
        return 0
    end

    return GetModelAutoHeight(ply)
end

local function GetTargetHeight(ply, duckAmount)
    local model = GetAdaptiveLookupModel(ply)
    local rule = AV.GetRule(model)

    if rule and rule.mode == "off" then
        return nil
    end

    local standingHeight

    if rule and rule.mode == "height" then
        standingHeight = rule.height * GetLocalAdaptiveModelScale(ply)
    else
        standingHeight = GetModelAutoHeight(ply)
    end

    standingHeight = standingHeight + cvGlobalOffset:GetFloat() + (rule and rule.cameraOffset or rule and rule.offset or 0)

    local tacMove = GetConVar("vb_movement")
    local duckRatio = 0.4375

    if not tacMove or not tacMove:GetBool() then
        local baseStand = ply:GetViewOffset().z
        local baseDuck = ply:GetViewOffsetDucked().z
        duckRatio = baseStand ~= 0 and baseDuck / baseStand or duckRatio
    end

    local duckHeight

    if rule and rule.duckCameraHeight and rule.duckCameraHeight > 0 then
        duckHeight = rule.duckCameraHeight * GetLocalAdaptiveModelScale(ply) + cvGlobalOffset:GetFloat() + (rule.cameraOffset or rule.offset or 0)
        duckHeight = math.Clamp(duckHeight, 18, standingHeight)
    else
        duckHeight = math.max(standingHeight * duckRatio, 18)
    end

    return Lerp(duckAmount, standingHeight, duckHeight)
end

hook.Add("FinishMove", "pm_eblansky_adaptive_view_tacmove_camera", function(ply)
    if ply ~= LocalPlayer() or not IsValid(ply) or not cvEnabled:GetBool() then
        return
    end

    local model = GetAdaptiveLookupModel(ply)
    local rule = AV.GetRule(model)
    local tacMove = GetConVar("vb_movement")
    local livePin = rule and rule.pinCameraOnEye == true
    local outfitterActive = IsOutfitterEnforcing(ply)

    if not livePin and not outfitterActive and (not tacMove or not tacMove:GetBool()) then
        return
    end

    local standHeight = GetTargetHeight(ply, 0)
    local duckHeight = GetTargetHeight(ply, 1)

    if not standHeight or not duckHeight then
        return
    end

    if livePin then
        local headHeight = GetModelHeadBoneHeight(ply)

        if not headHeight then
            return
        end

        if ply.pmavPinModel ~= model then
            ply.pmavPinBaseHeadHeight = nil
            ply.pmavPinTargetHeadDelta = nil
            ply.pmavPinSmoothedHeadDelta = nil
            ply.pmavPinLastOriginZ = nil
            ply.pmavPinStairFreezeUntil = nil
            ply.pmavPinLiveStandHeight = nil
            ply.pmavPinLiveDuckHeight = nil
            ply.pmavPinModel = model
        end

        if not ply.pmavPinBaseHeadHeight then
            ply.pmavPinBaseHeadHeight = headHeight
        end

        local smooth = math.Clamp(NumberOr(rule and rule.pinEyeSmoothing, 0.50), 0, 1)
        local headDelta = SmoothPinnedHeadDelta(ply, headHeight - ply.pmavPinBaseHeadHeight, smooth)
        local minHeight = cvMinHeight:GetFloat()
        local maxHeight = math.max(cvMaxHeight:GetFloat(), minHeight)
        standHeight = math.Clamp(standHeight + headDelta, minHeight, maxHeight)
        duckHeight = math.Clamp(duckHeight + headDelta, minHeight, standHeight)
        ply.pmavPinLiveStandHeight = standHeight
        ply.pmavPinLiveDuckHeight = duckHeight
    else
        ply.pmavPinModel = nil
        ply.pmavPinBaseHeadHeight = nil
        ply.pmavPinTargetHeadDelta = nil
        ply.pmavPinSmoothedHeadDelta = nil
        ply.pmavPinLastOriginZ = nil
        ply.pmavPinStairFreezeUntil = nil
        ply.pmavPinLiveStandHeight = nil
        ply.pmavPinLiveDuckHeight = nil
    end

    ply:SetViewOffset(Vector(0, 0, standHeight))
    ply:SetViewOffsetDucked(Vector(0, 0, duckHeight))
end)

local function GetLocalCameraPlaneOffset()
    if not cvEnabled:GetBool() then
        return 0, 0
    end

    local ply = LocalPlayer()

    if not IsValid(ply) then
        return 0, 0
    end

    local rule = AV.GetRule(GetAdaptiveLookupModel(ply))

    if rule and rule.mode == "off" then
        return 0, 0
    end

    local side = cvCameraOffsetX:GetFloat() + NumberOr(rule and rule.cameraOffsetX, 0)
    local forward = cvCameraOffsetY:GetFloat() + NumberOr(rule and rule.cameraOffsetY, 0)

    return math.Clamp(side, -64, 64), math.Clamp(forward, -64, 64)
end

hook.Add("CalcView", "pm_eblansky_adaptive_view_camera_plane_offset", function(ply, origin, angles, fov, znear, zfar)
    if ply ~= LocalPlayer() or not IsValid(ply) then
        return
    end

    local side, forward = GetLocalCameraPlaneOffset()

    if math.abs(side) < 0.001 and math.abs(forward) < 0.001 then
        return
    end

    return {
        origin = origin + angles:Right() * side + angles:Forward() * forward,
        angles = angles,
        fov = fov,
        znear = znear,
        zfar = zfar,
        drawviewer = false
    }
end)

hook.Add("CalcViewModelView", "pm_eblansky_adaptive_view_camera_plane_offset", function(weapon, viewModel, oldEyePos, oldEyeAng, eyePos, eyeAng)
    local side, forward = GetLocalCameraPlaneOffset()

    if math.abs(side) < 0.001 and math.abs(forward) < 0.001 then
        return
    end

    eyeAng = eyeAng or oldEyeAng or angle_zero
    eyePos = eyePos or oldEyePos or vector_origin

    return eyePos + eyeAng:Right() * side + eyeAng:Forward() * forward, eyeAng
end)

hook.Add("PostPlayerDraw", "pm_eblansky_adaptive_view_ikfoot_seen", function(ply)
    if ply == LocalPlayer() then
        ply.pmavIKFootNaturalFrame = FrameNumber()
    end
end)

local function PrepareLocalPlayerIKFootPose(ply)
    if not IsValid(ply) then
        return
    end

    -- Local players are often not advanced through the same draw path as remote
    -- players. IK Foot reads the current skeleton, so make sure the base pose is fresh
    -- before we ask its PostPlayerDraw hook to calculate foot placement.
    if isfunction(ply.UpdateClientsideAnimation) then
        pcall(ply.UpdateClientsideAnimation, ply)
    end

    if isfunction(ply.FrameAdvance) then
        pcall(ply.FrameAdvance, ply, 0)
    end

    if isfunction(ply.InvalidateBoneCache) then
        pcall(ply.InvalidateBoneCache, ply)
    end

    if isfunction(ply.SetupBones) then
        pcall(ply.SetupBones, ply)
    end
end

local function RunIKFootRuntimeDirect(ply)
    if not istable(IKFoot) or not istable(IKFoot.Runtime) then
        return false
    end

    local rt = IKFoot.Runtime

    if not istable(rt.Apply) or not istable(rt.Controller) then
        return false
    end

    if not isfunction(rt.GetIKBones) or not isfunction(rt.GetIKParamBool) or not isfunction(rt.CanManipulateBones) then
        return false
    end

    if not isfunction(rt.Apply.StripIKFromBones) or not isfunction(rt.Apply.BuildSkeleton) or not isfunction(rt.Apply.ApplyResult) then
        return false
    end

    if not isfunction(rt.Controller.Calculate) then
        return false
    end

    local alive = isfunction(ply.Alive) and ply:Alive()

    if ply.IKWasAlive == false and alive then
        if isfunction(rt.Apply.HardResetPlayer) then
            rt.Apply.HardResetPlayer(ply)
        end

        ply.IKWasAlive = alive
        return true
    end

    ply.IKWasAlive = alive

    if not alive then
        if isfunction(rt.Apply.ResetPlayer) then
            rt.Apply.ResetPlayer(ply)
        end

        return true
    end

    local bones = rt.GetIKBones(ply)

    if not rt.GetIKParamBool(ply, "enabled") then
        if isfunction(rt.Apply.ResetPlayer) then
            rt.Apply.ResetPlayer(ply, bones)
        end

        return true
    end

    if not rt.CanManipulateBones(ply) then
        if isfunction(rt.Apply.ResetPlayer) then
            rt.Apply.ResetPlayer(ply, bones)
        end

        return true
    end

    if not bones or not bones.lFoot or not bones.rFoot or not bones.lCalf or not bones.rCalf or not bones.lThigh or not bones.rThigh then
        if isfunction(rt.Apply.ResetPlayer) then
            rt.Apply.ResetPlayer(ply, bones)
        end

        return true
    end

    if ply.IKLastKnownModel ~= ply:GetModel() then
        ply.IKLastKnownModel = ply:GetModel()

        if isfunction(IKFoot.InvalidateModelCache) then
            IKFoot.InvalidateModelCache(ply.IKLastKnownModel)
        end

        if rt.GetIKParamBool(ply, "auto_model_detect") and isfunction(IKFoot.AutoApplyModelSettings) then
            timer.Simple(0.15, function()
                if IsValid(ply) then
                    IKFoot.AutoApplyModelSettings(ply)
                end
            end)
        end
    end

    rt.Apply.StripIKFromBones(ply, bones)

    if isfunction(ply.SetupBones) then
        ply:SetupBones()
    end

    local ok, result = pcall(function()
        local skeleton = rt.Apply.BuildSkeleton(ply, bones)

        if not skeleton then
            return nil
        end

        local calculated = rt.Controller.Calculate(ply, skeleton)

        if not calculated then
            return nil
        end

        rt.Apply.ApplyResult(ply, bones, calculated)
        return calculated
    end)

    if not ok then
        ply.IKFailCount = (ply.IKFailCount or 0) + 1

        if ply.IKFailCount >= 8 and isfunction(rt.State and rt.State.SoftRecover) then
            rt.State.SoftRecover(ply)
        end

        if ply.IKFailCount >= 15 and isfunction(rt.Apply.HardResetPlayer) then
            rt.Apply.HardResetPlayer(ply)
            ply.IKFailCount = 0
        end

        return true
    end

    if not result then
        ply.IKFailCount = (ply.IKFailCount or 0) + 1
        return true
    end

    ply.IKFailCount = 0

    local debugCvar = rt.CVars and rt.CVars.debug

    if debugCvar and debugCvar:GetInt() > 0 and isfunction(rt.Controller.DrawDebug) then
        rt.Controller.DrawDebug(ply, result)
    end

    return true
end

local function RunLocalIKFootCompat(reason)
    if not cvSupportIKFoot:GetBool() then
        return
    end

    local ply = LocalPlayer()
    local frame = FrameNumber()

    if not IsValid(ply) then
        return
    end

    if reason ~= "think" and ply.pmavIKFootCompatFrame == frame then
        return
    end

    if reason == "think" then
        local nextThink = ply.pmavIKFootCompatThinkTime or 0

        if nextThink > CurTime() then
            return
        end

        ply.pmavIKFootCompatThinkTime = CurTime() + 0.01
    end

    local cvar = GetConVar("ik_foot")

    if not cvar or not cvar:GetBool() then
        return
    end

    PrepareLocalPlayerIKFootPose(ply)

    -- IK Foot normally updates in PostPlayerDraw. Local first-person bodies are not
    -- always drawn through that path, so run it before first-person body/legs render.
    ply.pmavIKFootCompatFrame = frame
    ply.pmavIKFootForcedFrame = frame
    ply.pmavIKFootForcedReason = reason

    if RunIKFootRuntimeDirect(ply) then
        return
    end

    local ikHook = GetIKFootPostPlayerDrawHook()

    if not isfunction(ikHook) then
        return
    end

    local ok, err = pcall(ikHook, ply)

    if not ok then
        MsgC(Color(255, 120, 80), "[Adaptive View] IK Foot compatibility failed: " .. tostring(err) .. "\n")
    end
end

-- IK Foot compatibility experiment is intentionally parked for now.
-- The code above is kept for a future pass, but no hooks are registered.
-- hook.Add("Think", "pm_eblansky_adaptive_view_ikfoot_localplayer_think", function()
--     RunLocalIKFootCompat("think")
-- end)
--
-- hook.Add("PreRender", "pm_eblansky_adaptive_view_ikfoot_localplayer_prerender", function()
--     RunLocalIKFootCompat("pre_render")
-- end)
--
-- hook.Add("PreDrawOpaqueRenderables", "pm_eblansky_adaptive_view_ikfoot_localplayer_preopaque", function()
--     RunLocalIKFootCompat("pre_opaque")
-- end)
--
-- hook.Add("PreDrawViewModel", "pm_eblansky_adaptive_view_ikfoot_localplayer_previewmodel", function()
--     RunLocalIKFootCompat("pre_viewmodel")
-- end)
--
-- hook.Add("PreDrawEffects", "pm_eblansky_adaptive_view_ikfoot_localplayer_preeffects", function()
--     RunLocalIKFootCompat("pre_effects")
-- end)
--
-- hook.Add("PreDrawTranslucentRenderables", "pm_eblansky_adaptive_view_ikfoot_localplayer_pretranslucent", function()
--     RunLocalIKFootCompat("pre_translucent")
-- end)
--
-- hook.Add("PostDrawOpaqueRenderables", "pm_eblansky_adaptive_view_ikfoot_localplayer_postopaque", function()
--     RunLocalIKFootCompat("post_opaque")
-- end)

local function ResetSettingsExceptRules()
    RunConsoleCommand("pmav_auto_scale", "0.92")
    RunConsoleCommand("pmav_global_offset", "0")
    RunConsoleCommand("pmav_camera_fov", "0")
    RunConsoleCommand("pmav_camera_offset_x", "0")
    RunConsoleCommand("pmav_camera_offset_y", "0")
    RunConsoleCommand("pmav_scale_support", "1")
    RunConsoleCommand("pmav_scale_min", "0.5")
    RunConsoleCommand("pmav_scale_max", "2")
    RunConsoleCommand("pmav_smooth", "10")
    RunConsoleCommand("pmav_min_height", "4")
    RunConsoleCommand("pmav_max_height", "120")
    RunConsoleCommand("pmav_collision", "1")
    RunConsoleCommand("pmav_collision_mode", "3")
    RunConsoleCommand("pmav_collision_radius", "16")
    RunConsoleCommand("pmav_collision_only_players", "0")
    RunConsoleCommand("pmav_npc_collision", "0")
    RunConsoleCommand("pmav_multiplayer_safe", "1")
    RunConsoleCommand("pmav_adaptive_speed", "0")
    RunConsoleCommand("pmav_adaptive_jump", "0")
    RunConsoleCommand("pmav_adaptive_pickup_weight", "0")
    RunConsoleCommand("pmav_debug_bounds", "0")
    AV.SmoothedOffset = 0
    AV.LastViewOffset = vector_origin

    if isfunction(AV.SyncSettingsToServer) then
        timer.Simple(0, AV.SyncSettingsToServer)
    end
end

local function FillRulesList(list)
    AV.ActiveRulesList = list
    list:Clear()

    for model, rule in SortedPairs(AV.ModelRules) do
        local height = rule.mode == "height" and tostring(math.Round(rule.height, 2)) or "-"
        local cameraOffset = tostring(math.Round(rule.cameraOffset or rule.offset or 0, 2))
        local collisionHeight = rule.collisionHeight and rule.collisionHeight > 0 and tostring(math.Round(rule.collisionHeight, 2)) or "auto"
        local collisionWidth = rule.collisionWidth and rule.collisionWidth > 0 and tostring(math.Round(rule.collisionWidth, 2)) or "auto"
        local collisionLength = rule.collisionLength and rule.collisionLength > 0 and tostring(math.Round(rule.collisionLength, 2)) or "auto"

        list:AddLine(model, rule.mode, height, cameraOffset, collisionHeight, collisionWidth, collisionLength, FormatMovementRuleValue(rule.speed), FormatMovementRuleValue(rule.jump))
    end
end

function AV.RefreshRulesList()
    if IsValid(AV.ActiveRulesList) then
        FillRulesList(AV.ActiveRulesList)
    end
end

local function CollectPlayerModels()
    local models = {}
    local seen = {}

    local function addModel(name, model)
        model = NormalizeModel(model)

        if model == "" or seen[model] then
            return
        end

        seen[model] = true
        models[#models + 1] = {
            name = tostring(name or model),
            model = model
        }
    end

    if player_manager and player_manager.AllValidModels then
        for name, model in pairs(player_manager.AllValidModels()) do
            addModel(name, model)
        end
    end

    if IsValid(LocalPlayer()) then
        addModel("Current player model", LocalPlayer():GetModel())
    end

    table.sort(models, function(a, b)
        return a.model < b.model
    end)

    return models
end

local function OpenModelPicker(title, initialModel, onChoose)
    local frame = vgui.Create("DFrame")
    frame:SetTitle(title or "Choose player model")
    frame:SetSize(760, 520)
    frame:Center()
    frame:MakePopup()

    local top = vgui.Create("DPanel", frame)
    top:Dock(TOP)
    top:SetTall(56)
    top:DockMargin(8, 8, 8, 4)
    top.Paint = nil

    local modelEntry = vgui.Create("DTextEntry", top)
    modelEntry:Dock(TOP)
    modelEntry:SetTall(24)
    modelEntry:SetText(NormalizeModel(initialModel))
    modelEntry:SetPlaceholderText("models/player/group01/male_07.mdl")

    local searchEntry = vgui.Create("DTextEntry", top)
    searchEntry:Dock(BOTTOM)
    searchEntry:SetTall(24)
    searchEntry:SetPlaceholderText("Search")

    local useTyped = vgui.Create("DButton", frame)
    useTyped:Dock(BOTTOM)
    useTyped:DockMargin(8, 4, 8, 8)
    useTyped:SetTall(28)
    useTyped:SetText("Use this model path")

    local body = vgui.Create("DPanel", frame)
    body:Dock(FILL)
    body:DockMargin(8, 4, 8, 4)
    body.Paint = nil

    local preview = vgui.Create("DModelPanel", body)
    preview:Dock(RIGHT)
    preview:SetWide(240)
    preview:SetFOV(36)

    local list = vgui.Create("DListView", body)
    list:Dock(FILL)
    list:AddColumn("Name")
    list:AddColumn("Model")

    local allModels = CollectPlayerModels()

    local function choose(model)
        model = NormalizeModel(model)

        if model == "" then
            return
        end

        if isfunction(onChoose) then
            onChoose(model)
        end

        frame:Close()
    end

    local function updatePreview(model)
        model = NormalizeModel(model)

        if model == "" then
            return
        end

        pcall(function()
            preview:SetModel(model)
        end)
    end

    local function fill()
        local needle = string.lower(searchEntry:GetValue() or "")
        list:Clear()

        for _, item in ipairs(allModels) do
            if needle == "" or string.find(string.lower(item.name), needle, 1, true) or string.find(item.model, needle, 1, true) then
                list:AddLine(item.name, item.model)
            end
        end
    end

    list.OnRowSelected = function(_, _, row)
        local model = row:GetColumnText(2)
        modelEntry:SetText(model)
        updatePreview(model)
    end

    list.DoDoubleClick = function(_, _, row)
        choose(row:GetColumnText(2))
    end

    searchEntry.OnChange = fill
    modelEntry.OnEnter = function()
        choose(modelEntry:GetValue())
    end
    useTyped.DoClick = function()
        choose(modelEntry:GetValue())
    end

    fill()
    updatePreview(modelEntry:GetValue())
end

local function OpenRuleEditor(oldModel, onSaved)
    oldModel = NormalizeModel(oldModel)

    if oldModel == "" then
        return
    end

    local rule = table.Copy(AV.GetRule(oldModel) or DefaultRule())

    local frame = vgui.Create("DFrame")
    frame:SetTitle("Edit model rule (An improved version of this menu is under development)")
    frame:SetSize(460, 470)
    frame:Center()
    frame:MakePopup()

    local modelEntry = vgui.Create("DTextEntry", frame)
    modelEntry:Dock(TOP)
    modelEntry:DockMargin(8, 8, 8, 4)
    modelEntry:SetTall(24)
    modelEntry:SetText(oldModel)

    local chooseButton = vgui.Create("DButton", frame)
    chooseButton:Dock(TOP)
    chooseButton:DockMargin(8, 0, 8, 6)
    chooseButton:SetTall(26)
    chooseButton:SetText("Choose model")

    local modeBox = vgui.Create("DComboBox", frame)
    modeBox:Dock(TOP)
    modeBox:DockMargin(8, 0, 8, 6)
    modeBox:SetTall(24)
    modeBox:AddChoice("Auto height", "auto")
    modeBox:AddChoice("Exact height", "height")
    modeBox:AddChoice("Disable for this model", "off")
    modeBox:ChooseOptionID(rule.mode == "height" and 2 or rule.mode == "off" and 3 or 1)

    local heightSlider = vgui.Create("DNumSlider", frame)
    heightSlider:Dock(TOP)
    heightSlider:DockMargin(8, 0, 8, 0)
    heightSlider:SetText("Camera exact height")
    heightSlider:SetMinMax(20, 120)
    heightSlider:SetDecimals(0)
    heightSlider:SetValue(rule.height or 64)

    local offsetSlider = vgui.Create("DNumSlider", frame)
    offsetSlider:Dock(TOP)
    offsetSlider:DockMargin(8, 0, 8, 0)
    offsetSlider:SetText("Camera offset")
    offsetSlider:SetMinMax(-32, 32)
    offsetSlider:SetDecimals(1)
    offsetSlider:SetValue(rule.cameraOffset or rule.offset or 0)

    local collisionHeightSlider = vgui.Create("DNumSlider", frame)
    collisionHeightSlider:Dock(TOP)
    collisionHeightSlider:DockMargin(8, 0, 8, 0)
    collisionHeightSlider:SetText("Hitbox height (0 = auto)")
    collisionHeightSlider:SetMinMax(0, 180)
    collisionHeightSlider:SetDecimals(0)
    collisionHeightSlider:SetValue(rule.collisionHeight or 0)

    local collisionWidthSlider = vgui.Create("DNumSlider", frame)
    collisionWidthSlider:Dock(TOP)
    collisionWidthSlider:DockMargin(8, 0, 8, 0)
    collisionWidthSlider:SetText("Hitbox width (0 = auto)")
    collisionWidthSlider:SetMinMax(0, 96)
    collisionWidthSlider:SetDecimals(0)
    collisionWidthSlider:SetValue(rule.collisionWidth or 0)

    local collisionLengthSlider = vgui.Create("DNumSlider", frame)
    collisionLengthSlider:Dock(TOP)
    collisionLengthSlider:DockMargin(8, 0, 8, 0)
    collisionLengthSlider:SetText("Hitbox length (0 = auto)")
    collisionLengthSlider:SetMinMax(0, 96)
    collisionLengthSlider:SetDecimals(0)
    collisionLengthSlider:SetValue(rule.collisionLength or 0)

    local speedSlider = vgui.Create("DNumSlider", frame)
    speedSlider:Dock(TOP)
    speedSlider:DockMargin(8, 0, 8, 0)
    speedSlider:SetText("Speed (-2 base, -1 auto, 0 off)")
    speedSlider:SetMinMax(-2, 5)
    speedSlider:SetDecimals(2)
    speedSlider:SetValue(NumberOr(rule.speed, -1))

    local jumpSlider = vgui.Create("DNumSlider", frame)
    jumpSlider:Dock(TOP)
    jumpSlider:DockMargin(8, 0, 8, 0)
    jumpSlider:SetText("Jump force (-2 base, -1 auto, 0 off)")
    jumpSlider:SetMinMax(-2, 5)
    jumpSlider:SetDecimals(2)
    jumpSlider:SetValue(NumberOr(rule.jump, -1))

    local saveButton = vgui.Create("DButton", frame)
    saveButton:Dock(BOTTOM)
    saveButton:DockMargin(8, 6, 8, 8)
    saveButton:SetTall(30)
    saveButton:SetText("Save rule")

    chooseButton.DoClick = function()
        OpenModelPicker("Choose model for rule", modelEntry:GetText(), function(model)
            modelEntry:SetText(model)
        end)
    end

    saveButton.DoClick = function()
        local newModel = NormalizeModel(modelEntry:GetText())

        if newModel == "" then
            return
        end

        local selectedID = modeBox:GetSelectedID() or 1
        local mode = modeBox:GetOptionData(selectedID) or "auto"

        if newModel ~= oldModel then
            AV.SetRule(oldModel, nil)
        end

        AV.SetRule(
            newModel,
            mode,
            heightSlider:GetValue(),
            offsetSlider:GetValue(),
            offsetSlider:GetValue(),
            collisionHeightSlider:GetValue(),
            collisionWidthSlider:GetValue(),
            collisionLengthSlider:GetValue(),
            speedSlider:GetValue(),
            jumpSlider:GetValue()
        )

        if isfunction(onSaved) then
            onSaved(newModel, mode, heightSlider:GetValue(), offsetSlider:GetValue(), collisionHeightSlider:GetValue(), collisionWidthSlider:GetValue(), collisionLengthSlider:GetValue(), speedSlider:GetValue(), jumpSlider:GetValue())
        end

        oldModel = newModel
        saveButton:SetText("Saved")

        timer.Simple(0.8, function()
            if IsValid(saveButton) then
                saveButton:SetText("Save rule")
            end
        end)
    end
end

function OpenThanksWindow()
    local frame = vgui.Create("DFrame")
    frame:SetTitle("Adaptive View - Thank them!")
    frame:SetSize(540, 270)
    frame:Center()
    frame:MakePopup()

    local text = vgui.Create("RichText", frame)
    text:Dock(FILL)
    text:DockMargin(10, 8, 10, 10)

    text:InsertColorChange(80, 180, 255, 255)
    text:AppendText("Adaptive View credits\n\n")
    text:InsertColorChange(235, 235, 235, 255)
    text:AppendText("Дочь казаха — Programming\n\n")
    text:AppendText("TotallyARussian — For the idea of adding a width change, and separating the overview from the Box. ")
    text:InsertColorChange(180, 180, 180, 255)
    text:AppendText("(It's there now, but it's not implemented properly, this feature will manifest itself in the Rule menu update)\n\n")
    text:InsertColorChange(235, 235, 235, 255)
    text:AppendText("TheRyleeFella — Finding a bug related to grenades from ARC Escape From Tarkov.\n")
end

function OpenThanksWindow()
    local frame = vgui.Create("DFrame")
    frame:SetTitle("Adaptive View - Thank them!")
    frame:SetSize(620, 300)
    frame:Center()
    frame:MakePopup()

    local text = vgui.Create("RichText", frame)
    text:Dock(FILL)
    text:DockMargin(10, 8, 10, 10)

    local function addName(name, url)
        if url and url ~= "" and isfunction(text.InsertClickableTextStart) then
            text:InsertClickableTextStart(url)
            text:AppendText(name)
            text:InsertClickableTextEnd()
            return
        end

        text:AppendText(name)
    end

    local function addCredit(name, role, url)
        text:InsertColorChange(120, 200, 255, 255)
        addName(name, url)
        text:InsertColorChange(235, 235, 235, 255)
        text:AppendText(" - " .. role .. "\n\n")
    end

    text:InsertColorChange(80, 180, 255, 255)
    text:AppendText("Adaptive View credits\n\n")
    addCredit("Doch kazaha", "Programming a server script", "https://steamcommunity.com/profiles/76561199492270733")
    addCredit("TotallyARussian", "For the idea of adding a width change, and separating the overview from the Box. (It's there now, but it's not implemented properly, this feature will manifest itself in the Rule menu update)", "https://steamcommunity.com/id/xXxedgemasterxXx")
    addCredit("TheRyleeFella", "Finding a bug related to grenades from ARC Escape From Tarkov.", "https://steamcommunity.com/profiles/76561199199788875")
    addCredit("KarmotineOverdose", "For the idea of sliders for movement speed and jump power adjustment!", "https://steamcommunity.com/id/karmotineov")
    addCredit("TimRtec", "Reported a conflict with the \"TacMove\" addon related to movement speed and crouch height!", "https://steamcommunity.com/profiles/76561198234686368")
    addCredit("R4YL0", "Pointed out a bug with the \"Outfitter\" addon.", "https://steamcommunity.com/id/R4YL0")
    addCredit("ChloeV", "Found a bug with PM settings saving in the new MUI.", "https://steamcommunity.com/profiles/76561198391574956")
    addCredit("mec fluuri", "Suggested camera offset settings.", "https://steamcommunity.com/profiles/76561198122587193")
    addCredit("CokedBadger", "Suggested \"Pin camera on eye height\".", "https://steamcommunity.com/id/10238714120938")
    addCredit("TOYO1515", "Suggested pickup strength depending on player model height.", "https://steamcommunity.com/id/TOYO151515")
    addCredit("Remenix", "For the suggestion of adding ULX command support", "https://steamcommunity.com/id/xinemer")
end

local function OpenModernRuleMenuNotice()
    local frame = vgui.Create("DFrame")
    frame:SetTitle("Adaptive View - Modern UI Update")
    frame:SetSize(560, 230)
    frame:Center()
    frame:MakePopup()

    local text = vgui.Create("RichText", frame)
    text:Dock(FILL)
    text:DockMargin(10, 8, 10, 10)
    text:InsertColorChange(80, 180, 255, 255)
    text:AppendText("About a future update for this menu\n\n")
    text:InsertColorChange(235, 235, 235, 255)
    text:AppendText("We are currently working on a new Modern Menu. This menu will include a more convenient visual setup for the highest point of the model's head, camera height, the lowest point for the feet, and easier hitbox customization for both height and width, along with other improvements")
end

local function OpenModernRuleMenu()
    local ply = LocalPlayer()

    if not IsValid(ply) then
        return
    end

    local model = GetAdaptiveLookupModel(ply)

    if model == "" then
        return
    end

    local rule = table.Copy(AV.GetRule(model) or DefaultRule())
    local autoHeight = math.max(AV.GetLocalAutoHeight() or 64, 1)
    local modelMins, modelMaxs = ply:GetModelBounds()
    local modelScale = GetLocalAdaptiveModelScale(ply)
    local modelHeight = math.max(NumberOr(modelMaxs and modelMaxs.z, autoHeight) * modelScale, autoHeight)
    local setModernActiveModel
    local getModernModelHeightForPath
    local metricRangeScale = 1
    local activeModernTab = "heights"

    local function getModernEffectiveRangeScale()
        if activeModernTab == "heights" then
            return 1 + (math.max(NumberOr(metricRangeScale, 1), 1) - 1) * 0.55
        end

        return math.max(NumberOr(metricRangeScale, 1), 1)
    end

    local function gameHeightToVisualHeight(height)
        return math.max(NumberOr(height, 0), 0)
    end

    local function visualHeightToGameHeight(height)
        return math.max(NumberOr(height, 0), 0)
    end

    local function getModernFootSafeHeight()
        return math.max(NumberOr(modelMins and modelMins.z, 0) * modelScale + 8, 4)
    end

    local function clampModernCameraHeight(height)
        local footSafeHeight = getModernFootSafeHeight()
        local maxHeight = math.max(cvMaxHeight:GetFloat(), footSafeHeight)

        return math.Clamp(NumberOr(height, autoHeight), footSafeHeight, maxHeight)
    end

    local function getModernRuleCameraOffset(activeRule)
        activeRule = activeRule or rule

        return NumberOr(activeRule.cameraOffset, NumberOr(activeRule.offset, 0))
    end

    local function getModernAutoCameraHeightForPath(path, scale)
        local modelHeight, followsPose = GetReferenceModelHeight(path)
        scale = NumberOr(scale, 1)

        if not modelHeight or modelHeight <= 0 then
            local fallbackHeight = getModernModelHeightForPath and getModernModelHeightForPath(path) or autoHeight
            modelHeight = fallbackHeight * cvAutoScale:GetFloat()
        elseif followsPose then
            modelHeight = modelHeight * scale
        else
            modelHeight = modelHeight * scale
        end

        return math.Clamp(modelHeight, cvMinHeight:GetFloat(), math.max(cvMaxHeight:GetFloat(), cvMinHeight:GetFloat()))
    end

    local function getModernCameraHeight(activeRule)
        activeRule = activeRule or rule

        local baseHeight = activeRule.mode == "height" and NumberOr(activeRule.height, autoHeight) * modelScale or getModernAutoCameraHeightForPath(model, modelScale)
        local verticalOffset = cvGlobalOffset:GetFloat() + getModernRuleCameraOffset(activeRule)

        return clampModernCameraHeight(baseHeight + verticalOffset)
    end

    local function getModernDuckCameraHeight(activeRule)
        activeRule = activeRule or rule

        if activeRule.duckCameraHeight and activeRule.duckCameraHeight > 0 then
            return clampModernCameraHeight(activeRule.duckCameraHeight * modelScale + cvGlobalOffset:GetFloat() + getModernRuleCameraOffset(activeRule))
        end

        local defaultStand = IsValid(ply) and ply:GetViewOffset().z or 64
        local defaultDuck = IsValid(ply) and ply:GetViewOffsetDucked().z or 28
        local duckRatio = defaultStand ~= 0 and defaultDuck / defaultStand or 0.4375

        return math.max(getModernCameraHeight(activeRule) * duckRatio, getModernFootSafeHeight())
    end

    local function getModernCollisionBottom()
        return gameHeightToVisualHeight(0)
    end

    local function getModernCollisionTopFromHull(bottomVisual, hullHeight)
        return NumberOr(bottomVisual, 0) + math.max(NumberOr(hullHeight, 0), 0)
    end

    local function getModernCollisionHeight(activeRule)
        activeRule = activeRule or rule

        local bottomVisual = getModernCollisionBottom()

        if activeRule.collisionHeight and activeRule.collisionHeight > 0 then
            return gameHeightToVisualHeight(math.Clamp(activeRule.collisionHeight, 18, 180))
        end

        return gameHeightToVisualHeight(math.Clamp(modelHeight, 18, 180))
    end

    local function getModernDuckCollisionHeight(activeRule)
        local standingHullTop = visualHeightToGameHeight(getModernCollisionHeight(activeRule))
        local cameraToHullTop = math.max(standingHullTop - getModernCameraHeight(activeRule), 0)

        return gameHeightToVisualHeight(math.Clamp(math.min(getModernDuckCameraHeight(activeRule) + cameraToHullTop, standingHullTop), 12, 120))
    end

    local function getStoredCameraHeightFromFinal(finalHeight)
        local gameHeight = visualHeightToGameHeight(finalHeight)
        local verticalOffset = cvGlobalOffset:GetFloat()

        return math.max((clampModernCameraHeight(gameHeight) - verticalOffset) / math.max(modelScale, 0.001), 0)
    end

    local function getStoredDuckCameraHeightFromFinal(finalHeight)
        local gameHeight = visualHeightToGameHeight(finalHeight)
        local verticalOffset = cvGlobalOffset:GetFloat()

        return math.max((clampModernCameraHeight(gameHeight) - verticalOffset) / math.max(modelScale, 0.001), 0)
    end

    local function getStoredCollisionHeightFromFinal(finalHeight)
        return math.max(visualHeightToGameHeight(finalHeight), 0)
    end

    local hullTop = getModernCollisionHeight(rule)
    local crouchTop = gameHeightToVisualHeight(getModernDuckCameraHeight(rule))
    local hullBottom = getModernCollisionBottom()
    local cameraTop = gameHeightToVisualHeight(getModernCameraHeight(rule))

    local frame = vgui.Create("DFrame")
    frame:SetTitle("Rule for: " .. model)
    frame:SetSize(math.min(ScrW() - 80, 1360), math.min(ScrH() - 80, 820))
    frame:Center()
    frame:MakePopup()
    frame.Paint = function(self, w, h)
        surface.SetDrawColor(40, 40, 40, 255)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(46, 46, 46, 255)
        surface.DrawRect(0, 0, w, 24)
        surface.SetDrawColor(60, 60, 60, 255)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    local body = vgui.Create("DPanel", frame)
    body:Dock(FILL)
    body:DockMargin(0, 0, 0, 0)
    body.Paint = nil

    local rightPanel = vgui.Create("DPanel", body)
    rightPanel:Dock(RIGHT)
    rightPanel:SetWide(math.max(360, frame:GetWide() * 0.43))
    rightPanel:DockMargin(0, 6, 5, 8)
    rightPanel.Paint = nil

    local sheet = vgui.Create("DPropertySheet", rightPanel)
    sheet:Dock(FILL)
    sheet:DockMargin(0, 0, 0, 0)
    sheet.Paint = function(_, w, h)
        local contentTop = 22
        draw.RoundedBox(2, 0, contentTop, w, h - contentTop, Color(88, 88, 88, 255))
        draw.RoundedBox(2, 1, contentTop + 1, w - 2, h - contentTop - 2, Color(40, 40, 40, 255))
    end

    local generalPage = vgui.Create("DPanel", sheet)
    generalPage.Paint = function(_, w, h)
        surface.SetDrawColor(40, 40, 40, 255)
        surface.DrawRect(0, 0, w, h)
    end

    local rulesPage = vgui.Create("DPanel", sheet)
    rulesPage.Paint = function(_, w, h)
        surface.SetDrawColor(40, 40, 40, 255)
        surface.DrawRect(0, 0, w, h)
    end

    sheet:AddSheet("General", generalPage, nil)
    sheet:AddSheet("Rules", rulesPage, nil)

    local valuesLabel = vgui.Create("DLabel", generalPage)
    valuesLabel:SetVisible(false)

    local generalCanvas = vgui.Create("DPanel", generalPage)
    generalCanvas:Dock(FILL)
    generalCanvas:DockMargin(0, 0, 0, 0)

    local generalColors = {
        bg = Color(40, 40, 40, 255),
        border = Color(88, 88, 88, 255),
        section = Color(42, 42, 42, 255),
        header = Color(49, 49, 49, 255),
        field = Color(69, 69, 69, 255),
        fieldText = Color(255, 255, 255, 255),
        placeholder = Color(188, 188, 188, 205),
        soft = Color(186, 186, 186, 255),
        line = Color(72, 72, 72, 255),
        blue = Color(12, 102, 232, 255),
        switchOff = Color(97, 97, 97, 255),
        switchBorder = Color(76, 76, 76, 255)
    }

    local function formatModernMeters(sourceUnits)
        local meters = SourceUnitsToMeters(sourceUnits)

        if cvModernUnits:GetString() == "imperial" then
            local feet = meters * METERS_TO_FEET
            local rounded = math.Round(feet, 2)

            if math.abs(rounded - math.Round(rounded)) < 0.001 then
                return tostring(math.Round(rounded)) .. " ft"
            end

            return string.Replace(string.format("%.2f", rounded), ".", ",") .. " ft"
        end

        return FormatMeters(meters)
    end

    local function formatModernMeterValue(sourceUnits)
        local value = SourceUnitsToMeters(sourceUnits)

        if cvModernUnits:GetString() == "imperial" then
            value = value * METERS_TO_FEET
        end

        local rounded = math.Round(value, 2)

        return string.Replace(string.format("%.2f", rounded), ".", ",")
    end

    local function formatModernMassValue(kg)
        local value = NumberOr(kg, 0)

        if cvModernUnits:GetString() == "imperial" then
            value = value * KG_TO_LB
        end

        return string.Replace(string.format("%.1f", math.Round(value, 1)), ".", ",")
    end

    local function getModernLengthUnit()
        return cvModernUnits:GetString() == "imperial" and "ft" or "m"
    end

    local function getModernMassUnit()
        return cvModernUnits:GetString() == "imperial" and "lb" or "kg"
    end

    local function getModernModelName(path)
        local fileName = string.GetFileFromFilename(path or "") or ""
        fileName = string.gsub(fileName, "%.[^%.]+$", "")

        return fileName ~= "" and fileName or "Name"
    end

    local modernModelHeightCache = {}
    local modernModelBoundsCache = {}

    local function getModernModelBoundsForPath(path)
        path = NormalizeModel(path)

        if modernModelBoundsCache[path] then
            return modernModelBoundsCache[path].mins, modernModelBoundsCache[path].maxs
        end

        local mins = Vector(0, 0, 0)
        local maxs = Vector(16, 16, autoHeight)
        local ent = ClientsideModel(path, RENDERGROUP_OTHER)

        if IsValid(ent) then
            ent:SetNoDraw(true)

            if isfunction(ent.SetupBones) then
                ent:SetupBones()
            end

            local entMins, entMaxs = ent:GetModelBounds()
            if entMins and entMaxs then
                mins = Vector(entMins.x, entMins.y, entMins.z)
                maxs = Vector(entMaxs.x, entMaxs.y, entMaxs.z)
            end

            ent:Remove()
        end

        modernModelBoundsCache[path] = {
            mins = mins,
            maxs = maxs
        }

        return mins, maxs
    end

    getModernModelHeightForPath = function(path)
        path = NormalizeModel(path)

        if modernModelHeightCache[path] then
            return modernModelHeightCache[path]
        end

        local mins, maxs = getModernModelBoundsForPath(path)
        local height = math.max(NumberOr(maxs and maxs.z, 0), NumberOr(maxs and mins and maxs.z - mins.z, 0), autoHeight)

        modernModelHeightCache[path] = height

        return height
    end

    local function getModernModelMetric(path)
        path = NormalizeModel(path)

        local activeRule = AV.GetRule(path)
        local height = NumberOr(activeRule and activeRule.collisionHeight, 0)

        if height <= 0 then
            height = getModernModelHeightForPath(path)
        end

        return formatModernMeters(height)
    end

    local function createModernGeneralEntry(parent, placeholder, unit, autoValue)
        local entry = vgui.Create("DTextEntry", parent)
        entry:SetText("")
        entry:SetFont("PMAVModernGeneralText")
        entry:SetTextColor(generalColors.fieldText)
        entry:SetTextInset(5, 0)
        if entry.SetCursorColor then
            entry:SetCursorColor(generalColors.fieldText)
        end
        if entry.SetHighlightColor then
            entry:SetHighlightColor(generalColors.blue)
        end
        entry.placeholder = tostring(placeholder or "")
        entry.unit = tostring(unit or "")
        entry.unitResolver = isfunction(unit) and unit or nil
        entry.autoValue = autoValue == true
        entry.Paint = function(self, w, h)
            draw.RoundedBox(5, 0, 0, w, h, generalColors.field)

            if self:GetText() == "" and self.placeholder ~= "" then
                draw.SimpleText(self.placeholder, "PMAVModernGeneralText", 5, h * 0.5, generalColors.placeholder, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end

            local unitText = self.unitResolver and tostring(self.unitResolver()) or self.unit
            draw.RoundedBox(4, w - 28, 1, 27, h - 2, generalColors.blue)
            draw.SimpleText(unitText, "PMAVModernGeneralUnit", w - 14, h * 0.5, generalColors.fieldText, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

            local sx, sy = self:LocalToScreen(0, 0)
            render.SetScissorRect(sx + 5, sy, sx + w - 35, sy + h, true)
            self:DrawTextEntryText(generalColors.fieldText, generalColors.blue, generalColors.fieldText)
            render.SetScissorRect(0, 0, 0, 0, false)
        end

        return entry
    end

    local drawModernIcon

    local function createModernGeneralSwitch(parent, defaultValue)
        local button = vgui.Create("DButton", parent)
        button:SetText("")
        button:SetCursor("hand")
        button.value = defaultValue == true
        button.anim = button.value and 0 or 1
        button.dragging = false
        button.DoClick = function(self)
        end
        button.OnMousePressed = function(self, mouseCode)
            if mouseCode ~= MOUSE_LEFT then
                return
            end

            self.dragging = true
            self.wasDragging = false
            self.dragStartX = self:CursorPos()
            self:MouseCapture(true)
        end
        button.OnCursorMoved = function(self, x)
            if not self.dragging then
                return
            end

            if math.abs(x - NumberOr(self.dragStartX, x)) > 2 then
                self.wasDragging = true
                self:SetCursor("sizewe")
            end

            self.anim = math.Clamp((x - 2) / math.max(self:GetWide() - 4, 1), 0, 1)
        end
        button.OnMouseReleased = function(self, mouseCode)
            if mouseCode ~= MOUSE_LEFT or not self.dragging then
                return
            end

            self.dragging = false
            self:MouseCapture(false)
            self:SetCursor("hand")
            if self.wasDragging then
                self.value = (self.anim or 0) < 0.5
                self.wasDragging = false
            else
                self.value = not self.value
            end

            if isfunction(self.OnValueChanged) then
                self:OnValueChanged(self.value)
            end
        end
        button.Think = function(self)
            if self.dragging then
                return
            end

            self.anim = Lerp(FrameTime() * 28, self.anim or 0, self.value and 0 or 1)
        end
        button.Paint = function(self, w, h)
            draw.RoundedBox(4, 0, 0, w, h, generalColors.switchBorder)
            draw.RoundedBox(3, 2, 2, w - 4, h - 4, generalColors.switchOff)

            local activeW = math.floor((w - 4) * 0.5)
            local activeX = 2 + math.Round((w - 4 - activeW) * (self.anim or 0))
            draw.RoundedBox(3, activeX, 2, activeW, h - 4, generalColors.blue)

            draw.SimpleText("on", "PMAVModernGeneralText", math.floor(w * 0.26), h * 0.5, generalColors.fieldText, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText("off", "PMAVModernGeneralText", math.floor(w * 0.74), h * 0.5, generalColors.fieldText, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end

        return button
    end

    local function createModernSmoothSlider(parent, defaultValue)
        local slider = vgui.Create("DPanel", parent)
        slider.value = math.Clamp(NumberOr(defaultValue, 0.50), 0, 1)
        slider.displayValue = slider.value
        slider.knobAnim = 0
        slider.dragging = false
        slider:SetCursor("hand")
        slider.SetValue = function(self, value)
            self.value = math.Clamp(NumberOr(value, 0), 0, 1)
            self.displayValue = self.value
        end
        slider.GetValue = function(self)
            return self.value or 0
        end
        slider.OnMousePressed = function(self, code)
            if code ~= MOUSE_LEFT then
                return
            end

            self.dragging = true
            self:MouseCapture(true)
            self:UpdateFromCursor(false)
        end
        slider.OnMouseReleased = function(self, code)
            if code ~= MOUSE_LEFT then
                return
            end

            self.dragging = false
            self:MouseCapture(false)
            self:UpdateFromCursor(false)

            if isfunction(self.OnValueChanged) then
                self:OnValueChanged(self.value)
            end
        end
        slider.OnCursorMoved = function(self)
            if self.dragging then
                self:UpdateFromCursor(false)
            end
        end
        slider.UpdateFromCursor = function(self, notify)
            local x = self:CursorPos()
            local left = 44
            local right = math.max(self:GetWide() - 44, left + 1)
            local nextValue = math.Clamp((x - left) / math.max(right - left, 1), 0, 1)

            if math.abs(nextValue - NumberOr(self.value, 0)) > 0.001 then
                self.value = nextValue

                if notify ~= false and isfunction(self.OnValueChanged) then
                    self:OnValueChanged(self.value)
                end
            end
        end
        slider.Think = function(self)
            self.displayValue = self.value or 0
            self.knobAnim = Lerp(math.Clamp(FrameTime() * 22, 0, 1), self.knobAnim or 0, self.dragging and 1 or 0)
        end
        slider.Paint = function(self, w, h)
            local value = math.Clamp(self.displayValue or self.value or 0, 0, 1)
            local centerY = 28
            local left = 44
            local right = math.max(w - 44, left + 1)
            local knobX = Lerp(value, left, right)
            local knobSize = Lerp(self.knobAnim or 0, 11, 16)

            draw.SimpleText("Smooth camera", "PMAVModernGeneralText", w * 0.5, 0, generalColors.fieldText, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

            draw.RoundedBox(3, left, centerY - 3, right - left, 6, Color(205, 205, 205, 255))
            draw.RoundedBox(3, left, centerY - 3, math.max(knobX - left, 0), 6, generalColors.blue)

            draw.RoundedBox(knobSize * 0.5, knobX - knobSize * 0.5, centerY - knobSize * 0.5, knobSize, knobSize, generalColors.blue)

            draw.SimpleText(tostring(math.Round((self.value or 0) * 100)) .. "%", "PMAVModernGeneralSmall", w * 0.5, centerY + 9, generalColors.fieldText, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

            drawModernIcon("Potato", 7, centerY - 11, 24)
            drawModernIcon("Smoothes", w - 34, centerY - 12, 24)
        end

        return slider
    end

    drawModernIcon = function(name, x, y, size)
        local mat = GetModernMaterial("4mo_icos/mui/GenIcos/" .. name .. ".png") or GetModernMaterial("4mo_icos/mui/" .. name .. ".png")

        if not mat then
            return
        end

        local mw = math.max(mat:Width(), 1)
        local mh = math.max(mat:Height(), 1)
        local scale = math.min(size / mw, size / mh)
        local iw = math.floor(mw * scale)
        local ih = math.floor(mh * scale)

        surface.SetMaterial(mat)
        surface.SetDrawColor(255, 255, 255, 255)
        surface.DrawTexturedRect(math.floor(x + (size - iw) * 0.5), math.floor(y + (size - ih) * 0.5), iw, ih)
    end

    local function modernGeneralTextValue(value, isAuto)
        if isAuto then
            return ""
        end

        return tostring(value)
    end

    local generalControls
    local markerByKey

    local function getModernAutoMassKg(heightUnits)
        local heightMeters = math.max(SourceUnitsToMeters(heightUnits), 0.1)
        local heightCm = heightMeters * 100

        if heightCm <= 120 then
            return math.Clamp(heightCm * 0.16, 4, 24)
        end

        return math.Clamp((heightCm - 100) * 0.9, 8, 180)
    end

    local function getModernAutoPickupLimitKg(heightUnits, massKg)
        local heightMeters = math.max(SourceUnitsToMeters(heightUnits), 0.1)

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

        return math.Clamp(maxKg, 0, 500)
    end

    local function getModernAutoMovementScales(heightUnits)
        local defaultHullHeight = math.max(IsValid(ply) and NumberOr(ply.pmavDefaultHullMaxs and ply.pmavDefaultHullMaxs.z, 72) or 72, 1)
        local rawScale = NumberOr(heightUnits, defaultHullHeight) / defaultHullHeight

        return math.Clamp(rawScale, 0.75, 1.3), math.Clamp(1 + (rawScale - 1) * 0.45, 0.85, 1.15)
    end

    local function updateModernPhysicalAutoPlaceholders(activeRule)
        activeRule = activeRule or rule

        if not generalControls then
            return
        end

        local heightUnits = NumberOr(markerByKey and markerByKey.hull and markerByKey.hull.value, getModernCollisionHeight(activeRule))
        local speedScale, jumpScale = getModernAutoMovementScales(heightUnits)
        local massKg = NumberOr(activeRule.mass, -1)

        if massKg < 0 then
            massKg = getModernAutoMassKg(heightUnits)
        end

        local pickupLimitKg = NumberOr(activeRule.pickupLimit, -1)

        if pickupLimitKg < 0 then
            pickupLimitKg = getModernAutoPickupLimitKg(heightUnits, massKg)
        end

        generalControls.speed.placeholder = tostring(math.Round(speedScale, 2))
        generalControls.jump.placeholder = tostring(math.Round(jumpScale, 2))
        generalControls.mass.placeholder = formatModernMassValue(massKg)
        generalControls.push.placeholder = formatModernMassValue(pickupLimitKg)
    end

    local autoGeneral = {
        height = formatModernMeterValue(getModernCollisionHeight(rule)),
        camera = formatModernMeterValue(getModernCameraHeight(rule)),
        crouch = formatModernMeterValue(getModernDuckCameraHeight(rule)),
        camX = "0",
        camY = "0",
        speed = "1",
        jump = "1",
        mass = "11",
        push = "25",
        pinSmooth = "0,50"
    }

    generalControls = {
        height = createModernGeneralEntry(generalCanvas, autoGeneral.height, getModernLengthUnit, true),
        camera = createModernGeneralEntry(generalCanvas, autoGeneral.camera, getModernLengthUnit, true),
        crouch = createModernGeneralEntry(generalCanvas, autoGeneral.crouch, getModernLengthUnit, true),
        camX = createModernGeneralEntry(generalCanvas, autoGeneral.camX, getModernLengthUnit, false),
        camY = createModernGeneralEntry(generalCanvas, autoGeneral.camY, getModernLengthUnit, false),
        speed = createModernGeneralEntry(generalCanvas, autoGeneral.speed, "S", true),
        jump = createModernGeneralEntry(generalCanvas, autoGeneral.jump, "J", true),
        mass = createModernGeneralEntry(generalCanvas, autoGeneral.mass, getModernMassUnit, true),
        push = createModernGeneralEntry(generalCanvas, autoGeneral.push, getModernMassUnit, true),
        pinEye = createModernGeneralSwitch(generalCanvas, false),
        pinSmooth = createModernSmoothSlider(generalCanvas, NumberOr(rule.pinEyeSmoothing, 0.50))
    }

    generalControls.mass:SetVisible(false)
    generalControls.pinSmooth:SetVisible(rule.pinCameraOnEye == true)

    generalControls.height:SetText(modernGeneralTextValue(formatModernMeterValue(rule.collisionHeight), NumberOr(rule.collisionHeight, 0) <= 0))
    generalControls.camera:SetText(modernGeneralTextValue(formatModernMeterValue(rule.height * modelScale), rule.mode ~= "height"))
    generalControls.crouch:SetText(modernGeneralTextValue(formatModernMeterValue(rule.duckCameraHeight * modelScale), NumberOr(rule.duckCameraHeight, 0) <= 0))
    generalControls.camX:SetText(modernGeneralTextValue(formatModernMeterValue(rule.cameraOffsetX), NumberOr(rule.cameraOffsetX, 0) == 0))
    generalControls.camY:SetText(modernGeneralTextValue(formatModernMeterValue(rule.cameraOffsetY), NumberOr(rule.cameraOffsetY, 0) == 0))
    generalControls.speed:SetText(modernGeneralTextValue(NumberOr(rule.speed, -1), NumberOr(rule.speed, -1) == -1))
    generalControls.jump:SetText(modernGeneralTextValue(NumberOr(rule.jump, -1), NumberOr(rule.jump, -1) == -1))
    generalControls.mass:SetText(modernGeneralTextValue(formatModernMassValue(rule.mass), NumberOr(rule.mass, -1) == -1))
    generalControls.push:SetText(modernGeneralTextValue(formatModernMassValue(rule.pickupLimit), NumberOr(rule.pickupLimit, -1) == -1))
    generalControls.pinEye.value = rule.pinCameraOnEye == true
    generalControls.pinEye.anim = generalControls.pinEye.value and 0 or 1
    updateModernPhysicalAutoPlaceholders(rule)

    local generalDrop = vgui.Create("DButton", generalCanvas)
    generalDrop:SetText("")
    generalDrop:SetCursor("hand")
    generalDrop.selectedModel = model
    local generalDropIcon = vgui.Create("SpawnIcon", generalDrop)
    generalDropIcon:SetMouseInputEnabled(false)
    generalDropIcon:SetPos(26, 5)
    generalDropIcon:SetSize(18, 18)
    generalDropIcon:SetModel(model)

    local function updateGeneralDropPreview()
        local selectedModel = NormalizeModel(generalDrop.selectedModel or model)

        if generalDropIcon.LastModel ~= selectedModel then
            generalDropIcon.LastModel = selectedModel
            generalDropIcon:SetModel(selectedModel)
        end
    end

    generalDrop.DoClick = function()
        local menu = DermaMenu()
        local hasRules = false

        for ruleModel in SortedPairs(AV.ModelRules or {}) do
            hasRules = true
            menu:AddOption(getModernModelName(ruleModel), function()
                if isfunction(setModernActiveModel) then
                    setModernActiveModel(ruleModel)
                else
                    generalDrop.selectedModel = ruleModel
                    updateGeneralDropPreview()
                end
            end):SetIcon("icon16/user.png")
        end

        if not hasRules then
            menu:AddOption("No model rules yet")
        end

        menu:Open()
    end
    generalDrop.Paint = function(_, w, h)
        draw.RoundedBox(2, 0, 0, w, h, generalColors.border)
        draw.RoundedBox(2, 1, 1, w - 2, h - 2, generalColors.header)

        surface.SetDrawColor(generalColors.fieldText)
        local cx, cy = 13, math.floor(h * 0.5) - 2
        surface.DrawLine(cx - 3, cy, cx, cy + 4)
        surface.DrawLine(cx + 3, cy, cx, cy + 4)

        generalDropIcon:SetPos(26, math.floor((h - 18) * 0.5))
        generalDropIcon:SetSize(18, 18)
        updateGeneralDropPreview()

        local name = getModernModelName(generalDrop.selectedModel or model)
        local metric = getModernModelMetric(generalDrop.selectedModel or model)
        draw.SimpleText(name, "PMAVModernGeneralText", 49, h * 0.5, generalColors.fieldText, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        surface.SetFont("PMAVModernGeneralText")
        local nameW = surface.GetTextSize(name)
        draw.SimpleText(metric, "PMAVModernGeneralSmall", math.min(49 + nameW + 8, w - 78), h * 0.5 + 1, generalColors.soft, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local unitDrop = vgui.Create("DComboBox", generalCanvas)
    unitDrop:SetValue(cvModernUnits:GetString() == "imperial" and "Imperial (ft / lb)" or "Metric (m / kg)")
    unitDrop:AddChoice("Metric (m / kg)", "metric")
    unitDrop:AddChoice("Imperial (ft / lb)", "imperial")

    local generalLayout = {}

    local function updateModernGeneralLayout(w, h)
        generalCanvas:SetPos(0, 0)
        generalCanvas:SetSize(w, h)

        local pad = 10
        local contentW = math.max(w - pad * 2, 320)
        local x = pad
        local groupGap = 18
        local iconGap = 5
        local iconSize = 26
        local entryH = 26
        local entryW = math.min(100, math.floor((contentW - iconSize * 3 - iconGap * 3 - groupGap * 2) / 3))
        local pinOn = generalControls.pinEye.value == true

        generalLayout.x = x
        generalLayout.width = contentW
        generalLayout.icons = {}
        generalLayout.pinOn = pinOn
        generalLayout.cameraBoxH = pinOn and 150 or 96
        generalLayout.physicalTitleY = pinOn and 380 or 326
        generalLayout.physicalBoxY = pinOn and 398 or 340
        generalLayout.physicalBoxH = pinOn and 108 or 91

        generalDrop:SetPos(x, 10)
        generalDrop:SetSize(contentW, 29)
        unitDrop:SetPos(x + contentW - 132, 52)
        unitDrop:SetSize(132, 24)

        local function placeEntry(key, iconName, px, py, ew)
            ew = ew or entryW
            table.insert(generalLayout.icons, {name = iconName, x = px, y = py, size = iconSize})
            generalControls[key]:SetPos(px + iconSize + iconGap, py)
            generalControls[key]:SetSize(ew, entryH)

            return px + iconSize + iconGap + ew
        end

        local totalOffsetW = entryW * 3 + iconSize * 3 + iconGap * 3 + groupGap * 2
        local ox = math.floor(x + (contentW - totalOffsetW) * 0.5)
        ox = placeEntry("height", "Height", ox, 131) + groupGap
        ox = placeEntry("camera", "camHeight", ox, 131) + groupGap
        placeEntry("crouch", "OnCrouchCamHeight", ox, 131)

        local cameraEntryW = math.min(100, math.floor((contentW - iconSize * 2 - iconGap * 2 - groupGap) / 2))
        local camTotalW = cameraEntryW * 2 + iconSize * 2 + iconGap * 2 + groupGap
        local camX = math.floor(x + (contentW - camTotalW) * 0.5)
        camX = placeEntry("camX", "camXOffset", camX, 220, cameraEntryW) + groupGap
        placeEntry("camY", "camYOffset", camX, 220, cameraEntryW)

        local switchW = 59
        local switchTextW = math.min(185, contentW - iconSize - iconGap - 15 - switchW - 40)
        local switchTotalW = iconSize + iconGap + switchTextW + 15 + switchW
        local sx = math.floor(x + (contentW - switchTotalW) * 0.5)
        table.insert(generalLayout.icons, {name = "CamToeyeLayer", x = sx, y = 264, size = iconSize})
        generalLayout.pinTextX = sx + iconSize + iconGap
        generalControls.pinEye:SetPos(generalLayout.pinTextX + switchTextW + 15, 264)
        generalControls.pinEye:SetSize(switchW, entryH)
        generalControls.pinSmooth:SetVisible(pinOn)

        if pinOn then
            local sliderW = math.Clamp(math.floor(contentW * 0.56), 220, 310)
            generalControls.pinSmooth:SetPos(math.floor(x + (contentW - sliderW) * 0.5), 302)
            generalControls.pinSmooth:SetSize(sliderW, 50)
        end

        local physEntryW = math.min(100, math.floor((contentW - iconSize * 2 - iconGap * 2 - groupGap) / 2))
        local physTotalW = physEntryW * 2 + iconSize * 2 + iconGap * 2 + groupGap
        local px = math.floor(x + (contentW - physTotalW) * 0.5)
        local physY = pinOn and 424 or 354
        local px2 = placeEntry("speed", "WalkSpeed", px, physY, physEntryW) + groupGap
        placeEntry("jump", "JumpForce", px2, physY, physEntryW)

        local pickupTotalW = iconSize + iconGap + physEntryW
        px = math.floor(x + (contentW - pickupTotalW) * 0.5)
        placeEntry("push", "KgtoUp", px, physY + 40, physEntryW)
        generalControls.mass:SetVisible(false)
    end

    generalCanvas.Paint = function(_, w, h)
        surface.SetDrawColor(generalColors.bg)
        surface.DrawRect(0, 0, w, h)

        local x = generalLayout.x or 0
        local width = generalLayout.width or w
        local centerX = x + width * 0.5

        draw.SimpleText("Rule:", "PMAVModernGeneralRuleTitle", centerX, 56, generalColors.fieldText, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("Offset's:", "PMAVModernGeneralText", centerX, 104, generalColors.fieldText, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        draw.RoundedBox(2, x, 117, width, 51, generalColors.border)
        draw.RoundedBox(2, x + 1, 118, width - 2, 49, generalColors.section)

        local cameraBoxH = generalLayout.cameraBoxH or 96
        local physicalTitleY = generalLayout.physicalTitleY or 326
        local physicalBoxY = generalLayout.physicalBoxY or 340
        local physicalBoxH = generalLayout.physicalBoxH or 91

        draw.SimpleText("Camera settings:", "PMAVModernGeneralText", centerX, 193, generalColors.fieldText, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.RoundedBox(2, x, 206, width, cameraBoxH, generalColors.border)
        draw.RoundedBox(2, x + 1, 207, width - 2, cameraBoxH - 2, generalColors.section)
        surface.SetDrawColor(generalColors.line)
        surface.DrawRect(x + 20, 254, width - 40, 1)

        draw.SimpleText("Pin camera on eye heigh", "PMAVModernGeneralText", generalLayout.pinTextX or x, 277, generalColors.fieldText, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        draw.SimpleText("Physical Attributes:", "PMAVModernGeneralText", centerX, physicalTitleY, generalColors.fieldText, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.RoundedBox(2, x, physicalBoxY, width, physicalBoxH, generalColors.border)
        draw.RoundedBox(2, x + 1, physicalBoxY + 1, width - 2, physicalBoxH - 2, generalColors.section)

        for _, icon in ipairs(generalLayout.icons or {}) do
            drawModernIcon(icon.name, icon.x, icon.y, icon.size)
        end
    end

    generalPage.PerformLayout = function(_, w, h)
        updateModernGeneralLayout(w, h)
    end

    generalCanvas.Think = function(self)
        local pinOn = generalControls.pinEye.value == true
        local sig = tostring(self:GetWide()) .. ":" .. tostring(self:GetTall()) .. ":" .. tostring(pinOn)

        if self.pmavLayoutSig ~= sig then
            self.pmavLayoutSig = sig
            updateModernGeneralLayout(generalPage:GetWide(), generalPage:GetTall())
        end
    end

    local zoomSlider

    local showModernRuleActionButtons = false
    local function setupModernRuleActionButton(button, text, bottomMargin)
        button:SetText(text)

        if showModernRuleActionButtons then
            button:Dock(BOTTOM)
            button:DockMargin(18, 4, 18, bottomMargin or 4)
            button:SetTall(30)
        else
            button:SetVisible(false)
            button:SetTall(0)
        end
    end

    local applyButton = vgui.Create("DButton", rulesPage)
    setupModernRuleActionButton(applyButton, "Apply & Save", 18)

    local previewButton = vgui.Create("DButton", rulesPage)
    setupModernRuleActionButton(previewButton, "Apply", 4)

    local removeRuleButton = vgui.Create("DButton", rulesPage)
    setupModernRuleActionButton(removeRuleButton, "Remove saved rule", 4)

    local resetPreviewButton = vgui.Create("DButton", rulesPage)
    setupModernRuleActionButton(resetPreviewButton, "Reset preview", 4)

    local ruleScroll = vgui.Create("DScrollPanel", rulesPage)
    ruleScroll:Dock(FILL)
    ruleScroll:DockMargin(0, 0, 0, 8)
    ruleScroll.Paint = function(_, w, h)
        surface.SetDrawColor(40, 40, 40, 255)
        surface.DrawRect(0, 0, w, h)
    end

    local ruleCanvas = vgui.Create("DPanel", ruleScroll)
    ruleScroll:AddItem(ruleCanvas)
    ruleCanvas:Dock(TOP)
    ruleCanvas:SetTall(600)
    ruleCanvas.Paint = function(self, w, h)
        surface.SetDrawColor(40, 40, 40, 255)
        surface.DrawRect(0, 0, w, h)

        local closeMat = GetModernMaterial("4mo_icos/mui/close.png")
        local pad = 10
        local sectionX = pad
        local sectionW = math.max(w - pad * 2 - 8, 320)

        local function drawSectionTitle(text, x, y)
            surface.SetFont("PMAVModernGeneralRuleTitle")
            local tw, th = surface.GetTextSize(text)

            surface.SetDrawColor(40, 40, 40, 255)
            surface.DrawRect(x + 18, y - th * 0.5 - 2, tw + 12, th + 4)
            draw.SimpleText(text, "PMAVModernGeneralRuleTitle", x + 24, y, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end

        local function drawSection(y, height, title)
            draw.RoundedBox(2, sectionX, y, sectionW, height, Color(131, 131, 131, 255))
            draw.RoundedBox(2, sectionX + 1, y + 1, sectionW - 2, height - 2, Color(40, 40, 40, 255))
            drawSectionTitle(title, sectionX, y)
        end

        local function drawModelRow(x, y, rowW, rowH, ruleModel, metric, large, removable)
            local bg = large and Color(56, 56, 56, 255) or Color(40, 40, 40, 255)
            local border = large and Color(88, 88, 88, 255) or Color(64, 64, 64, 255)
            local avatar = large and 42 or 28
            local nameFont = large and "PMAVModernGeneralText" or "PMAVModernGeneralSmall"
            local metricFont = "PMAVModernGeneralSmall"

            draw.RoundedBox(2, x, y, rowW, rowH, border)
            draw.RoundedBox(2, x + 1, y + 1, rowW - 2, rowH - 2, bg)
            surface.SetDrawColor(234, 0, 255, 255)
            surface.DrawRect(x + 10, math.floor(y + (rowH - avatar) * 0.5), avatar, avatar)

            local modelName = getModernModelName(ruleModel)
            local textX = x + avatar + 24
            draw.SimpleText(modelName, nameFont, textX, y + rowH * 0.5, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

            surface.SetFont(nameFont)
            local nameW = surface.GetTextSize(modelName)
            draw.SimpleText(metric or "", metricFont, textX + nameW + 10, y + rowH * 0.5 + 2, generalColors.soft, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

            if removable then
                local closeSize = large and 22 or 18
                local closeX = x + rowW - closeSize - 16
                local closeY = y + rowH * 0.5 - closeSize * 0.5
                draw.RoundedBox(6, closeX, closeY, closeSize, closeSize, Color(70, 70, 70, 255))

                if closeMat then
                    surface.SetMaterial(closeMat)
                    surface.SetDrawColor(220, 220, 220, 255)
                    surface.DrawTexturedRect(closeX + 5, closeY + 5, closeSize - 10, closeSize - 10)
                else
                    draw.SimpleText("x", "PMAVModernGeneralText", closeX + closeSize * 0.5, closeY + closeSize * 0.5, Color(220, 220, 220), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
            end
        end

        local ruleModels = {}
        for ruleModel in SortedPairs(AV.ModelRules or {}) do
            table.insert(ruleModels, ruleModel)
        end

        local withoutModels = {}
        if player_manager and player_manager.AllValidModels then
            for _, modelPath in SortedPairs(player_manager.AllValidModels()) do
                modelPath = NormalizeModel(modelPath)

                if not AV.GetRule(modelPath) then
                    table.insert(withoutModels, modelPath)
                end
            end
        end

        if #withoutModels == 0 then
            table.insert(withoutModels, model)
        end

        local mainModel = model
        local mainHasRule = AV.GetRule(mainModel) ~= nil
        local withRowH = 42
        local withGap = 10
        local mainRowH = 58
        local withRows = 0
        for _, ruleModel in ipairs(ruleModels) do
            if NormalizeModel(ruleModel) ~= mainModel then
                withRows = withRows + 1
            end
        end

        local withHeight = 56 + mainRowH + math.max(withRows, 0) * (withRowH + withGap) + 16
        local withoutRowH = 46
        local withoutGap = 10
        local withoutTop = 20 + withHeight + 18
        local withoutHeight = 48 + #withoutModels * (withoutRowH + withoutGap) + 14
        local totalHeight = withoutTop + withoutHeight + 18

        if self:GetTall() ~= totalHeight then
            self:SetTall(totalHeight)
        end

        drawSection(20, withHeight, "Player models with Rule")
        drawModelRow(sectionX + 12, 44, sectionW - 24, mainRowH, mainModel, getModernModelMetric(mainModel), true, mainHasRule)

        local rowY = 44 + mainRowH + 12
        for _, ruleModel in ipairs(ruleModels) do
            if NormalizeModel(ruleModel) ~= mainModel then
                drawModelRow(sectionX + 72, rowY, sectionW - 144, withRowH, ruleModel, getModernModelMetric(ruleModel), false, true)
                rowY = rowY + withRowH + withGap
            end
        end

        drawSection(withoutTop, withoutHeight, "Player models out Rule")

        rowY = withoutTop + 36
        for _, withoutModel in ipairs(withoutModels) do
            drawModelRow(sectionX + 20, rowY, sectionW - 40, withoutRowH, withoutModel, getModernModelMetric(withoutModel), false, false)
            rowY = rowY + withoutRowH + withoutGap
        end
    end

    ruleCanvas.OnMousePressed = function(_, code)
        if code ~= MOUSE_LEFT then
            return
        end

        local mx, my = ruleCanvas:CursorPos()
        local pad = 10
        local sectionX = pad
        local sectionW = math.max(ruleCanvas:GetWide() - pad * 2 - 8, 320)
        local ruleModels = {}

        for ruleModel in SortedPairs(AV.ModelRules or {}) do
            table.insert(ruleModels, ruleModel)
        end

        local mainRowH = 58
        local closeSize = 22
        local closeX = sectionX + 12 + sectionW - 24 - closeSize - 16
        local closeY = 44 + mainRowH * 0.5 - closeSize * 0.5

        if AV.GetRule(model) and mx >= closeX and mx <= closeX + closeSize and my >= closeY and my <= closeY + closeSize then
            AV.SetRule(model, nil)
            return
        end

        local rowY = 44 + mainRowH + 12
        for _, ruleModel in ipairs(ruleModels) do
            if NormalizeModel(ruleModel) ~= model then
                local rowH = 42
                closeSize = 18
                closeX = sectionX + 72 + sectionW - 144 - closeSize - 16
                closeY = rowY + rowH * 0.5 - closeSize * 0.5

                if mx >= closeX and mx <= closeX + closeSize and my >= closeY and my <= closeY + closeSize then
                    AV.SetRule(ruleModel, nil)
                    return
                end

                rowY = rowY + rowH + 10
            end
        end
    end

    ruleScroll:SetVisible(false)
    ruleScroll:SetMouseInputEnabled(false)

    local modernRuleState
    local modernRuleRoot = vgui.Create("DPanel", rulesPage)
    modernRuleRoot:Dock(FILL)
    modernRuleRoot:DockMargin(0, 0, 0, 8)
    modernRuleRoot:SetZPos(100)
    modernRuleRoot.Paint = function(_, w, h)
        surface.SetDrawColor(40, 40, 40, 255)
        surface.DrawRect(0, 0, w, h)
    end
    local modernRuleGhostPanel = vgui.Create("DPanel", modernRuleRoot)
    modernRuleGhostPanel:SetSize(260, 36)
    modernRuleGhostPanel:SetZPos(1000)
    modernRuleGhostPanel:SetMouseInputEnabled(false)
    modernRuleGhostPanel:SetVisible(true)
    modernRuleGhostPanel.Paint = function(self, w, h)
        local dragModel = modernRuleState and modernRuleState.draggingModel

        if not dragModel then
            return
        end

        draw.RoundedBox(2, 0, 0, w, h, Color(70, 70, 70, 180))
        draw.RoundedBox(2, 1, 1, w - 2, h - 2, Color(40, 40, 40, 210))
        draw.SimpleText(getModernModelName(dragModel or ""), "PMAVModernGeneralSmall", 42, h * 0.5, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local modernRuleGhostIcon = vgui.Create("SpawnIcon", modernRuleGhostPanel)
    modernRuleGhostIcon:SetPos(8, 6)
    modernRuleGhostIcon:SetSize(24, 24)
    modernRuleGhostIcon:SetMouseInputEnabled(false)
    modernRuleGhostPanel.Think = function(self)
        local dragModel = modernRuleState and modernRuleState.draggingModel

        if not dragModel then
            modernRuleGhostIcon:SetVisible(false)
            return
        end

        if self.LastModel ~= dragModel then
            self.LastModel = dragModel
            modernRuleGhostIcon:SetModel(dragModel)
        end

        local x, y = modernRuleRoot:CursorPos()
        self:SetPos(math.Clamp(x + 12, 4, math.max(modernRuleRoot:GetWide() - self:GetWide() - 4, 4)), math.Clamp(y + 12, 4, math.max(modernRuleRoot:GetTall() - self:GetTall() - 4, 4)))
        modernRuleGhostIcon:SetVisible(true)
    end

    local modernRuleWithSection = vgui.Create("DPanel", modernRuleRoot)
    local modernRuleWithoutSection = vgui.Create("DPanel", modernRuleRoot)
    modernRuleState = {
        withLimit = 10,
        withoutLimit = 10,
        pendingDragModel = nil,
        dragStartX = 0,
        dragStartY = 0,
        draggingModel = nil,
        withScroll = 0,
        withoutScroll = 0
    }

    local function paintModernRuleSection(self, w, h)
        draw.RoundedBox(2, 0, 0, w, h, Color(131, 131, 131, 255))
        draw.RoundedBox(2, 1, 1, w - 2, h - 2, Color(40, 40, 40, 255))

        surface.SetFont("PMAVModernGeneralRuleTitle")
        local title = self.Title or ""
        local tw, th = surface.GetTextSize(title)
        surface.SetDrawColor(40, 40, 40, 255)
        surface.DrawRect(18, 0, tw + 16, th + 6)
        draw.SimpleText(title, "PMAVModernGeneralRuleTitle", 26, 0, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end

    modernRuleWithSection.Title = "Player models with Rule"
    modernRuleWithoutSection.Title = "Player models out Rule"
    modernRuleWithSection.Paint = paintModernRuleSection
    modernRuleWithoutSection.Paint = paintModernRuleSection

    local function getModernRuleModels()
        local models = {}

        if AV.GetRule(model) then
            models[#models + 1] = model
        end

        for ruleModel in SortedPairs(AV.ModelRules or {}) do
            ruleModel = NormalizeModel(ruleModel)

            if ruleModel ~= "" and ruleModel ~= model then
                models[#models + 1] = ruleModel
            end
        end

        return models
    end

    local function getModernModelsWithoutRule()
        local models = {}

        if player_manager and player_manager.AllValidModels then
            for _, modelPath in SortedPairs(player_manager.AllValidModels()) do
                modelPath = NormalizeModel(modelPath)

                if modelPath ~= "" and not AV.GetRule(modelPath) then
                    models[#models + 1] = modelPath
                end
            end
        end

        return models
    end

    local rebuildModernRuleSections
    local scrollModernRuleSection

    local function createModernRuleForModel(ruleModel)
        ruleModel = NormalizeModel(ruleModel)

        if ruleModel == "" or AV.GetRule(ruleModel) then
            return
        end

        local ruleScale = 1
        local localPlayer = LocalPlayer()

        if IsValid(localPlayer) and GetAdaptiveLookupModel(localPlayer) == ruleModel then
            ruleScale = GetLocalAdaptiveModelScale(localPlayer)
        end

        local ruleCameraHeight = getModernAutoCameraHeightForPath(ruleModel, ruleScale)
        local ruleHullHeight = math.Clamp(getModernModelHeightForPath(ruleModel) * ruleScale, 18, 180)
        local defaultStand = IsValid(localPlayer) and localPlayer:GetViewOffset().z or 64
        local defaultDuck = IsValid(localPlayer) and localPlayer:GetViewOffsetDucked().z or 28
        local duckRatio = defaultStand ~= 0 and defaultDuck / defaultStand or 0.4375
        local ruleDuckHeight = math.max(ruleCameraHeight * duckRatio, getModernFootSafeHeight())
        local storeScale = math.max(ruleScale, 0.001)

        AV.SetRule(ruleModel, "height", ruleCameraHeight / storeScale, 0, 0, ruleHullHeight, 0, 0, -1, -1, true, ruleDuckHeight / storeScale)
    end

    local function removeModernRuleForModel(ruleModel)
        ruleModel = NormalizeModel(ruleModel)

        if ruleModel == "" then
            return
        end

        local wasActive = NormalizeModel(model) == ruleModel
        AV.SetRule(ruleModel, nil)

        if wasActive then
            rule = DefaultRule()

            if isfunction(setModernActiveModel) then
                setModernActiveModel(ruleModel)
            end
        elseif isfunction(rebuildModernRuleSections) then
            rebuildModernRuleSections()
        end
    end

    local function finishModernRuleDrag()
        local dragModel = modernRuleState and modernRuleState.draggingModel

        if not dragModel then
            modernRuleState.pendingDragModel = nil
            return
        end

        local sx, sy = modernRuleWithSection:LocalCursorPos()
        local releasedOnWithRule = sx >= 0 and sy >= 0 and sx <= modernRuleWithSection:GetWide() and sy <= modernRuleWithSection:GetTall()

        if releasedOnWithRule then
            createModernRuleForModel(dragModel)

            if isfunction(setModernActiveModel) then
                setModernActiveModel(dragModel)
            end

            rebuildModernRuleSections()
        end

        modernRuleState.pendingDragModel = nil
        modernRuleState.draggingModel = nil
    end

    local function createModernRuleMoreButton(parent, y, limitKey)
        local button = vgui.Create("DButton", parent)
        button:SetText("")
        button:SetPos(20, y)
        button:SetSize(math.max(parent:GetWide() - 40, 220), 32)
        button:SetCursor("hand")
        button.DoClick = function()
            modernRuleState[limitKey] = modernRuleState[limitKey] + 20
            rebuildModernRuleSections()
        end
        button.Paint = function(_, w, h)
            draw.RoundedBox(2, 0, 0, w, h, Color(64, 64, 64, 255))
            draw.RoundedBox(2, 1, 1, w - 2, h - 2, Color(40, 40, 40, 255))
            draw.SimpleText("Больше...", "PMAVModernGeneralText", w * 0.5, h * 0.5, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end

    local function createModernRuleRow(parent, ruleModel, x, y, w, h, large, removable, canCreate)
        local row = vgui.Create("DButton", parent)
        row:SetText("")
        row:SetPos(x, y)
        row:SetSize(w, h)
        row:SetCursor("hand")
        row.ModelPath = ruleModel
        row.OnMouseWheeled = function(_, delta)
            if parent.OnMouseWheeled then
                return parent:OnMouseWheeled(delta)
            end
        end
        row.DoClick = function()
            if canCreate then
                createModernRuleForModel(ruleModel)
                if isfunction(setModernActiveModel) then
                    setModernActiveModel(ruleModel)
                end
                rebuildModernRuleSections()
            elseif isfunction(setModernActiveModel) then
                setModernActiveModel(ruleModel)
            end
        end
        row.OnMousePressed = function(self, code)
            if code == MOUSE_LEFT then
                if canCreate then
                    local mx, my = gui.MousePos()
                    modernRuleState.pendingDragModel = ruleModel
                    modernRuleState.dragStartX = mx
                    modernRuleState.dragStartY = my
                    modernRuleState.draggingModel = nil
                end

                self:MouseCapture(canCreate == true)
            end
        end
        row.Think = function()
            if modernRuleState.pendingDragModel ~= ruleModel then
                return
            end

            if not input.IsMouseDown(MOUSE_LEFT) then
                modernRuleState.pendingDragModel = nil
                return
            end

            local mx, my = gui.MousePos()
            local dx = mx - NumberOr(modernRuleState.dragStartX, mx)
            local dy = my - NumberOr(modernRuleState.dragStartY, my)

            if dx * dx + dy * dy >= 36 then
                modernRuleState.draggingModel = ruleModel
                modernRuleState.pendingDragModel = nil

                if IsValid(modernRuleGhostPanel) then
                    modernRuleGhostPanel:MoveToFront()
                end
            end
        end
        row.OnMouseReleased = function(self, code)
            if code == MOUSE_LEFT and canCreate then
                local x, y = self:CursorPos()
                local releasedOnRow = x >= 0 and y >= 0 and x <= self:GetWide() and y <= self:GetTall()
                local sx, sy = modernRuleWithSection:LocalCursorPos()
                local releasedOnWithRule = sx >= 0 and sy >= 0 and sx <= modernRuleWithSection:GetWide() and sy <= modernRuleWithSection:GetTall()

                if modernRuleState.draggingModel == ruleModel and releasedOnWithRule then
                    createModernRuleForModel(ruleModel)
                    if isfunction(setModernActiveModel) then
                        setModernActiveModel(ruleModel)
                    end
                    rebuildModernRuleSections()
                elseif not modernRuleState.draggingModel and releasedOnRow then
                    createModernRuleForModel(ruleModel)
                    if isfunction(setModernActiveModel) then
                        setModernActiveModel(ruleModel)
                    end
                    rebuildModernRuleSections()
                end
            elseif code == MOUSE_LEFT and not canCreate and modernRuleState.draggingModel then
                createModernRuleForModel(modernRuleState.draggingModel)
                if isfunction(setModernActiveModel) then
                    setModernActiveModel(modernRuleState.draggingModel)
                end
                rebuildModernRuleSections()
            elseif code == MOUSE_LEFT and not canCreate then
                local x, y = self:CursorPos()

                if x >= 0 and y >= 0 and x <= self:GetWide() and y <= self:GetTall() and isfunction(setModernActiveModel) then
                    setModernActiveModel(ruleModel)
                end
            end

            if not modernRuleState.draggingModel then
                modernRuleState.pendingDragModel = nil
            end
            self:MouseCapture(false)
        end
        row.Paint = function(_, rowW, rowH)
            local bg = large and Color(56, 56, 56, 255) or Color(40, 40, 40, 255)
            local border = large and Color(88, 88, 88, 255) or Color(64, 64, 64, 255)
            local avatar = large and 42 or 28
            local textX = avatar + 24
            local nameFont = large and "PMAVModernGeneralText" or "PMAVModernGeneralSmall"
            local modelName = getModernModelName(ruleModel)
            local metric = getModernModelMetric(ruleModel)

            draw.RoundedBox(2, 0, 0, rowW, rowH, border)
            draw.RoundedBox(2, 1, 1, rowW - 2, rowH - 2, bg)
            draw.SimpleText(modelName, nameFont, textX, rowH * 0.5, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

            surface.SetFont(nameFont)
            local nameW = surface.GetTextSize(modelName)
            draw.SimpleText(metric, "PMAVModernGeneralSmall", textX + nameW + 10, rowH * 0.5 + 2, generalColors.soft, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end

        local avatar = large and 42 or 28
        local icon = vgui.Create("SpawnIcon", row)
        icon:SetPos(10, math.floor((h - avatar) * 0.5))
        icon:SetSize(avatar, avatar)
        icon:SetModel(ruleModel)
        icon:SetMouseInputEnabled(false)

        if removable then
            local closeMat = GetModernMaterial("4mo_icos/mui/close.png")
            local closeSize = large and 22 or 18
            local close = vgui.Create("DButton", row)
            close:SetText("")
            close:SetPos(w - closeSize - 16, math.floor(h * 0.5 - closeSize * 0.5))
            close:SetSize(closeSize, closeSize)
            close:SetCursor("hand")
            close.DoClick = function()
                removeModernRuleForModel(ruleModel)
            end
            close.Paint = function(_, cw, ch)
                draw.RoundedBox(6, 0, 0, cw, ch, Color(70, 70, 70, 255))

                if closeMat then
                    surface.SetMaterial(closeMat)
                    surface.SetDrawColor(220, 220, 220, 255)
                    surface.DrawTexturedRect(5, 5, cw - 10, ch - 10)
                else
                    draw.SimpleText("x", "PMAVModernGeneralText", cw * 0.5, ch * 0.5, Color(220, 220, 220), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
            end
        end
    end

    rebuildModernRuleSections = function()
        if not IsValid(modernRuleWithSection) or not IsValid(modernRuleWithoutSection) then
            return
        end

        modernRuleWithSection:Clear()
        modernRuleWithoutSection:Clear()

        local ruleModels = getModernRuleModels()
        local withoutModels = getModernModelsWithoutRule()
        local listTop = 36
        local withListPanel = vgui.Create("DPanel", modernRuleWithSection)
        local withoutListPanel = vgui.Create("DPanel", modernRuleWithoutSection)
        withListPanel:SetPos(1, listTop)
        withListPanel:SetSize(math.max(modernRuleWithSection:GetWide() - 2, 220), math.max(modernRuleWithSection:GetTall() - listTop - 8, 1))
        withoutListPanel:SetPos(1, listTop)
        withoutListPanel:SetSize(math.max(modernRuleWithoutSection:GetWide() - 2, 220), math.max(modernRuleWithoutSection:GetTall() - listTop - 8, 1))
        withListPanel.Paint = nil
        withoutListPanel.Paint = nil
        withListPanel.OnMouseWheeled = function(_, delta)
            return scrollModernRuleSection("withScroll", modernRuleWithSection, delta)
        end
        withoutListPanel.OnMouseWheeled = function(_, delta)
            return scrollModernRuleSection("withoutScroll", modernRuleWithoutSection, delta)
        end

        local withW = math.max(withListPanel:GetWide() - 24, 220)
        local withoutW = math.max(withoutListPanel:GetWide() - 24, 220)
        local withSmallH = math.Clamp(math.floor((modernRuleWithSection:GetTall() - 58) / 10) - 4, 22, 34)
        local withoutRowH = math.Clamp(math.floor((modernRuleWithoutSection:GetTall() - 54) / 10) - 4, 22, 34)
        local rowGap = 4
        local withHasMore = #ruleModels > modernRuleState.withLimit
        local withoutHasMore = #withoutModels > modernRuleState.withoutLimit
        local withVisibleLimit = modernRuleState.withLimit
        local withoutVisibleLimit = modernRuleState.withoutLimit
        modernRuleState.withScroll = math.Clamp(modernRuleState.withScroll, 0, NumberOr(modernRuleState.withScrollMax, 0))
        modernRuleState.withoutScroll = math.Clamp(modernRuleState.withoutScroll, 0, NumberOr(modernRuleState.withoutScrollMax, 0))

        local y = -modernRuleState.withScroll
        local drawn = 0

        for i, ruleModel in ipairs(ruleModels) do
            if drawn >= withVisibleLimit then
                break
            end

            local large = i == 1 and ruleModel == model
            local rowH = large and math.min(withSmallH + 10, 42) or withSmallH
            local rowX = large and 12 or 58
            local rowW = large and withW or math.max(withW - 92, 180)

            createModernRuleRow(withListPanel, ruleModel, rowX, y, rowW, rowH, large, true, false)

            y = y + rowH + rowGap
            drawn = drawn + 1
        end

        if withHasMore then
            createModernRuleMoreButton(withListPanel, y, "withLimit")
            y = y + 36
        end

        modernRuleState.withScrollMax = math.max(y + modernRuleState.withScroll - withListPanel:GetTall(), 0)

        y = -modernRuleState.withoutScroll
        drawn = 0
        for _, withoutModel in ipairs(withoutModels) do
            if drawn >= withoutVisibleLimit then
                break
            end

            createModernRuleRow(withoutListPanel, withoutModel, 20, y, withoutW - 16, withoutRowH, false, false, true)

            y = y + withoutRowH + rowGap
            drawn = drawn + 1
        end

        if withoutHasMore then
            createModernRuleMoreButton(withoutListPanel, y, "withoutLimit")
            y = y + 36
        end

        modernRuleState.withoutScrollMax = math.max(y + modernRuleState.withoutScroll - withoutListPanel:GetTall(), 0)

        local clampedWith = math.Clamp(modernRuleState.withScroll, 0, modernRuleState.withScrollMax)
        local clampedWithout = math.Clamp(modernRuleState.withoutScroll, 0, modernRuleState.withoutScrollMax)
        if clampedWith ~= modernRuleState.withScroll or clampedWithout ~= modernRuleState.withoutScroll then
            modernRuleState.withScroll = clampedWith
            modernRuleState.withoutScroll = clampedWithout
            timer.Simple(0, function()
                if IsValid(modernRuleRoot) then
                    rebuildModernRuleSections()
                end
            end)
        end
    end

    scrollModernRuleSection = function(key, section, delta)
        local maxScroll = NumberOr(modernRuleState[key .. "Max"], 0)
        modernRuleState[key] = math.Clamp(NumberOr(modernRuleState[key], 0) - delta * 34, 0, maxScroll)
        rebuildModernRuleSections()

        return true
    end

    modernRuleWithSection.OnMouseWheeled = function(_, delta)
        return scrollModernRuleSection("withScroll", modernRuleWithSection, delta)
    end

    modernRuleWithoutSection.OnMouseWheeled = function(_, delta)
        return scrollModernRuleSection("withoutScroll", modernRuleWithoutSection, delta)
    end

    modernRuleWithSection.OnMouseReleased = function()
        finishModernRuleDrag()
    end

    modernRuleRoot.Think = function()
        if modernRuleState and modernRuleState.draggingModel and not input.IsMouseDown(MOUSE_LEFT) then
            finishModernRuleDrag()
        end
    end

    modernRuleRoot.PerformLayout = function(_, w, h)
        local pad = 10
        local gap = 12
        local sectionH = math.floor((h - pad * 2 - gap) * 0.5)

        modernRuleWithSection:SetPos(pad, pad)
        modernRuleWithSection:SetSize(w - pad * 2, sectionH)
        modernRuleWithoutSection:SetPos(pad, pad + sectionH + gap)
        modernRuleWithoutSection:SetSize(w - pad * 2, h - pad * 2 - gap - sectionH)
        rebuildModernRuleSections()
    end

    timer.Simple(0, function()
        if IsValid(modernRuleRoot) then
            rebuildModernRuleSections()
        end
    end)

    local viewport = vgui.Create("DPanel", body)
    viewport:Dock(FILL)
    viewport:DockMargin(0, 28, 0, 0)
    viewport.Paint = function(_, w, h)
        surface.SetDrawColor(40, 40, 40, 255)
        surface.DrawRect(0, 0, w, h)
    end

    local bottomTabs = vgui.Create("DPanel", viewport)
    bottomTabs:Dock(BOTTOM)
    bottomTabs:SetTall(42)
    bottomTabs.Paint = nil

    local modelPanel = vgui.Create("DModelPanel", viewport)
    modelPanel:Dock(FILL)
    modelPanel:SetModel(model)
    modelPanel:SetFOV(MODERN_PROFILE_FOV)
    modelPanel:SetAnimated(false)
    modelPanel.RunAnimation = function() end

    local function syncModernPreviewAppearance(ent)
        if not IsValid(ent) or not IsValid(ply) then
            return
        end

        if isfunction(ent.SetSkin) and isfunction(ply.GetSkin) then
            ent:SetSkin(ply:GetSkin())
        end

        if isfunction(ent.SetBodygroup) and isfunction(ply.GetBodygroup) and isfunction(ply.GetNumBodyGroups) then
            for i = 0, ply:GetNumBodyGroups() - 1 do
                ent:SetBodygroup(i, ply:GetBodygroup(i))
            end
        end
    end

    local function freezeModernPreviewEntity(ent, crouched)
        if not IsValid(ent) then
            return
        end

        local sequence
        local wantedSequence = crouched and (ent:LookupSequence("crouchidle") >= 0 and "crouchidle" or "cidle_all") or "idle_all_01"
        sequence = ent:LookupSequence(wantedSequence)

        if (not sequence or sequence < 0) and isfunction(ent.SelectWeightedSequence) then
            sequence = ent:SelectWeightedSequence(crouched and ACT_COVER_LOW or ACT_IDLE)
        end

        local cycle = crouched and 0.55 or 0

        ent.AutomaticFrameAdvance = false
        ent:SetPlaybackRate(0)

        if isfunction(ent.SetIK) then
            ent:SetIK(false)
        end

        if sequence and sequence >= 0 then
            ent:SetSequence(sequence)
        end

        ent:SetPoseParameter("move_x", 0)
        ent:SetPoseParameter("move_y", 0)
        ent:SetPoseParameter("move_yaw", 0)
        ent:SetPoseParameter("body_yaw", 0)
        ent:SetPoseParameter("body_pitch", 0)
        ent:SetPoseParameter("head_pitch", 0)
        ent:SetPoseParameter("head_yaw", 0)
        ent:SetCycle(cycle)

        if isfunction(ent.FrameAdvance) then
            ent:FrameAdvance(0)
        end

        if isfunction(ent.SetupBones) then
            ent:SetupBones()
        end

        ent:SetCycle(cycle)
        syncModernPreviewAppearance(ent)
    end

    timer.Simple(0, function()
        if IsValid(modelPanel) and IsValid(modelPanel.Entity) then
            modelPanel.Entity.RunAnimation = function() end
            freezeModernPreviewEntity(modelPanel.Entity, false)
        end
    end)

    local getDisplayMaxUnits
    local drawModernPreviewHull = function() end
    local widthState
    local yFromUnits
    local getWidthLayout
    local widthXToPanel
    local widthYToPanel
    local projection = {
        lookZ = 64,
        distance = 256,
        fov = 35,
        maxUnits = 128,
        orthoHalfWidth = 64,
        panelH = 1,
        previewScale = 1,
        previewFootOffset = 0,
        previewSize = Vector(32, 32, 64),
        unitToPreviewUnit = 1,
        metricOriginPreview = 0
    }

    local function updateModernPreviewTransform(ent)
        if not IsValid(ent) then
            return
        end

        if isfunction(ent.SetModelScale) then
            ent:SetModelScale(1, 0)
        end

        if isfunction(ent.SetupBones) then
            ent:SetupBones()
        end

        local mins, maxs = ent:GetRenderBounds()
        local renderHeight = math.max(NumberOr(maxs and maxs.z, 0) - NumberOr(mins and mins.z, 0), 1)
        local targetHeight = math.max(NumberOr(modelHeight, renderHeight), 1)
        local rawSize = maxs - mins

        projection.previewScale = 1
        projection.previewFootOffset = 0
        projection.previewSize = Vector(math.abs(rawSize.x), math.abs(rawSize.y), math.abs(rawSize.z))
        projection.unitToPreviewUnit = math.max(renderHeight / targetHeight, 0.001)
        projection.metricOriginPreview = NumberOr(mins and mins.z, 0)
        ent:SetPos(vector_origin)
    end

    local function updateModelCamera()
        if not IsValid(modelPanel.Entity) then
            return
        end

        local ent = modelPanel.Entity
        ent:SetAngles(Angle(0, 270, 0))
        updateModernPreviewTransform(ent)
        local size = projection.previewSize or Vector(32, 32, modelHeight)
        local panelH = math.max(modelPanel:GetTall(), 1)
        local panelW = math.max(modelPanel:GetWide(), 1)
        local aspect = panelW / panelH

        if activeModernTab == "widths" then
            local visibleScale = getModernEffectiveRangeScale()
            local maxSide = math.max(
                math.abs(widthState and widthState.minX or -16),
                math.abs(widthState and widthState.maxX or 16),
                math.abs(widthState and widthState.minY or -16),
                math.abs(widthState and widthState.maxY or 16),
                math.abs(widthState and widthState.cameraX or 0) + 8,
                math.abs(widthState and widthState.cameraY or 0) + 8,
                size.x * 0.55,
                size.y * 0.55,
                32
            ) * visibleScale
            local layoutLeft = 44
            local layoutRight = math.max(panelW - 58, layoutLeft + 180)
            local layoutTop = 54
            local layoutBottom = panelH - 48
            local usableW = math.max(layoutRight - layoutLeft, 1)
            local usableH = math.max(layoutBottom - layoutTop, 1)
            local pixelsPerUnit = math.min(usableW, usableH) * 0.45 / math.max(maxSide, 1)

            projection.lookZ = 0
            projection.distance = math.max(size.z + 220, 256)
            projection.maxUnits = math.max(panelH / math.max(pixelsPerUnit, 0.001), maxSide * 2.2, 48)
            projection.orthoHalfWidth = math.max(panelW / math.max(pixelsPerUnit, 0.001) * 0.5, maxSide * 1.1, 48)
            projection.panelH = panelH

            ent:SetPos(vector_origin)
            modelPanel:SetLookAt(Vector(0, 0, 0))
            modelPanel:SetCamPos(Vector(0, 0, projection.distance))
            return
        end

        local maxUnits = getDisplayMaxUnits and select(1, getDisplayMaxUnits()) or math.max(size.z, 64) * 1.25
        local lookZ = maxUnits * 0.5
        local distance = math.max(math.max(size.x, size.y) + 160, 256)
        local modelHalfWidth = math.max(size.x, size.y) * 0.72
        local orthoHalfWidth = math.max(maxUnits * aspect * 0.5, modelHalfWidth, 32)

        projection.lookZ = lookZ
        projection.distance = distance
        projection.maxUnits = maxUnits
        projection.orthoHalfWidth = orthoHalfWidth
        projection.panelH = panelH

        ent:SetPos(vector_origin)
        modelPanel:SetLookAt(Vector(0, 0, lookZ))
        modelPanel:SetCamPos(Vector(0, -distance, lookZ))
    end

    modelPanel.Paint = function(self, w, h)
        surface.SetDrawColor(40, 40, 40, 255)
        surface.DrawRect(0, 0, w, h)

        if activeModernTab == "widths" and getWidthLayout and widthXToPanel and widthYToPanel then
            local layout = getWidthLayout(w, h)
            surface.SetDrawColor(62, 62, 62, 255)
            local gridStep = math.max(8, math.Round(layout.largest / 4 / 4) * 4)

            for units = -layout.largest, layout.largest, gridStep do
                local x = widthXToPanel(units, layout)
                local y = widthYToPanel(units, layout)

                if x >= layout.left - 2 and x <= layout.right + 2 then
                    surface.DrawLine(x, layout.top, x, layout.bottom)
                end

                if y >= layout.top - 2 and y <= layout.bottom + 2 then
                    surface.DrawLine(layout.left, y, layout.right, y)
                end
            end
        elseif getDisplayMaxUnits and yFromUnits then
            local _, displayMeters, step = getDisplayMaxUnits()
            local metricTextLeft = w - 141

            surface.SetDrawColor(62, 62, 62, 255)
            for meters = 0, displayMeters + 0.001, step do
                local units = MetersToSourceUnits(meters)
                local y = yFromUnits(units, h)

                if y >= -40 and y <= h + 40 then
                    surface.DrawLine(0, y, w, y)
                end
            end
        end

        if not IsValid(self.Entity) then
            return
        end

        updateModelCamera()
        self:LayoutEntity(self.Entity)

        local camPos
        local lookAt

        if activeModernTab == "widths" then
            camPos = Vector(0, 0, projection.distance)
            lookAt = Vector(0, 0, 0)
        else
            camPos = Vector(0, -projection.distance, projection.lookZ)
            lookAt = Vector(0, 0, projection.lookZ)
        end

        local ang = (lookAt - camPos):Angle()

        local screenX, screenY = self:LocalToScreen(0, 0)

        render.SetScissorRect(screenX, screenY, screenX + w, screenY + h, true)
        cam.Start({
            type = "3D",
            origin = camPos,
            angles = ang,
            x = screenX,
            y = screenY,
            w = w,
            h = h,
            znear = 1,
            zfar = projection.distance + math.max(projection.orthoHalfWidth, projection.maxUnits) + 256,
            ortho = {
                left = -projection.orthoHalfWidth,
                right = projection.orthoHalfWidth,
                bottom = projection.maxUnits * 0.5,
                top = -projection.maxUnits * 0.5
            }
        })
            render.SuppressEngineLighting(true)
            render.SetLightingOrigin(self.Entity:GetPos())
            render.ResetModelLighting(1, 1, 1)
            render.SetColorModulation(1, 1, 1)
            render.SetBlend(1)
            freezeModernPreviewEntity(self.Entity, self.HoveredMarker == "crouch")
            self.Entity:DrawModel()
            drawModernPreviewHull()
            freezeModernPreviewEntity(self.Entity, self.HoveredMarker == "crouch")
            render.SuppressEngineLighting(false)
        cam.End3D()
        render.SetScissorRect(0, 0, 0, 0, false)
    end

    timer.Simple(0, function()
        if IsValid(modelPanel) then
            updateModelCamera()
        end
    end)

    modelPanel.LayoutEntity = function(self, ent)
        local hovered = self.HoveredMarker
        ent:SetAngles(activeModernTab == "widths" and Angle(0, 0, 0) or Angle(0, 270, 0))
        ent:SetPos(vector_origin)
        freezeModernPreviewEntity(ent, hovered == "crouch")
        updateModernPreviewTransform(ent)
    end

    local markers = {
        {
            key = "hull",
            label = "Hitbox height",
            icon = "HeighHB",
            iconW = 20,
            iconH = 25,
            color = Color(30, 137, 20, 255),
            value = hullTop,
            minValue = 0
        },
        {
            key = "camera",
            label = "Camera height",
            icon = "View",
            iconW = 24,
            iconH = 10,
            color = Color(29, 113, 243, 255),
            value = cameraTop,
            minValue = 0
        },
        {
            key = "crouch",
            label = "Crouch hitbox",
            icon = "ViewInCrouch",
            iconW = 14,
            iconH = 23,
            iconYOffset = 1,
            color = Color(119, 123, 11, 255),
            value = crouchTop,
            minValue = 0
        },
        {
            key = "floor",
            label = "Feet / floor",
            icon = "FloorHB",
            iconW = 22,
            iconH = 19,
            color = Color(196, 115, 34, 255),
            value = hullBottom,
            minValue = 0,
            locked = true
        }
    }

    markerByKey = {}

    for _, marker in ipairs(markers) do
        markerByKey[marker.key] = marker
        marker.animState = 0
    end

    local function parseModernGeneralNumber(entry)
        if not IsValid(entry) then
            return nil
        end

        local text = string.Trim(entry:GetText() or "")

        if text == "" then
            return nil
        end

        return tonumber(string.Replace(text, ",", "."))
    end

    local function parseModernGeneralMeters(entry)
        local value = parseModernGeneralNumber(entry)

        if value == nil then
            return nil
        end

        if cvModernUnits:GetString() == "imperial" then
            value = value / METERS_TO_FEET
        end

        return MetersToSourceUnits(value)
    end

    local function parseModernGeneralMass(entry)
        local value = parseModernGeneralNumber(entry)

        if value == nil then
            return nil
        end

        if cvModernUnits:GetString() == "imperial" then
            value = value / KG_TO_LB
        end

        return value
    end

    local function syncModernGeneralHeightFields()
        local heightUnits = parseModernGeneralMeters(generalControls.height)
        local cameraUnits = parseModernGeneralMeters(generalControls.camera)
        local crouchUnits = parseModernGeneralMeters(generalControls.crouch)

        if heightUnits then
            markerByKey.hull.value = math.max(heightUnits, markerByKey.hull.minValue or 0)
        end

        if cameraUnits then
            markerByKey.camera.value = math.max(cameraUnits, markerByKey.camera.minValue or 0)
        end

        if crouchUnits then
            markerByKey.crouch.value = math.max(crouchUnits, markerByKey.crouch.minValue or 0)
        end
    end

    local suppressModernGeneralChange = false
    local applyModernRule
    local modernPreviewApplyQueued = false
    local function scheduleModernPreviewApply()
        if modernPreviewApplyQueued then
            return
        end

        modernPreviewApplyQueued = true
        timer.Simple(0.04, function()
            modernPreviewApplyQueued = false

            if not IsValid(frame) or not isfunction(applyModernRule) then
                return
            end

            applyModernRule(false)
        end)
    end

    local function updateModernGeneralFieldsFromVisual()
        suppressModernGeneralChange = true
        generalControls.height:SetText(formatModernMeterValue(markerByKey.hull.value))
        generalControls.camera:SetText(formatModernMeterValue(markerByKey.camera.value))
        generalControls.crouch:SetText(formatModernMeterValue(markerByKey.crouch.value))

        if widthState then
            generalControls.camX:SetText(formatModernMeterValue(widthState.cameraX or 0))
            generalControls.camY:SetText(formatModernMeterValue(widthState.cameraY or 0))
        end

        updateModernPhysicalAutoPlaceholders(rule)
        suppressModernGeneralChange = false
    end

    local function syncModernGeneralRuleFields()
        local camX = parseModernGeneralMeters(generalControls.camX)
        local camY = parseModernGeneralMeters(generalControls.camY)
        local speed = parseModernGeneralNumber(generalControls.speed)
        local jump = parseModernGeneralNumber(generalControls.jump)
        local mass = parseModernGeneralMass(generalControls.mass)
        local pickupLimit = parseModernGeneralMass(generalControls.push)
        local pinSmooth = IsValid(generalControls.pinSmooth) and generalControls.pinSmooth:GetValue() or nil

        if camX and widthState then
            widthState.cameraX = camX
        end

        if camY and widthState then
            widthState.cameraY = camY
        end

        if speed ~= nil then
            rule.speed = speed
        else
            rule.speed = -1
        end

        if jump ~= nil then
            rule.jump = jump
        else
            rule.jump = -1
        end

        if mass ~= nil then
            rule.mass = mass
        else
            rule.mass = -1
        end

        if pickupLimit ~= nil then
            rule.pickupLimit = pickupLimit
        else
            rule.pickupLimit = -1
        end

        rule.pinCameraOnEye = generalControls.pinEye.value == true

        if pinSmooth ~= nil then
            rule.pinEyeSmoothing = math.Clamp(NumberOr(pinSmooth, 0.50), 0, 1)
        end
    end

    local function refreshModernUnitFields()
        updateModernGeneralFieldsFromVisual()

        suppressModernGeneralChange = true
        generalControls.mass:SetText(modernGeneralTextValue(formatModernMassValue(rule.mass), NumberOr(rule.mass, -1) == -1))
        generalControls.push:SetText(modernGeneralTextValue(formatModernMassValue(rule.pickupLimit), NumberOr(rule.pickupLimit, -1) == -1))
        unitDrop:SetValue(cvModernUnits:GetString() == "imperial" and "Imperial (ft / lb)" or "Metric (m / kg)")
        suppressModernGeneralChange = false

        updateModernPhysicalAutoPlaceholders(rule)
    end

    unitDrop.OnSelect = function(_, _, _, data)
        data = data == "imperial" and "imperial" or "metric"

        syncModernGeneralHeightFields()
        syncModernGeneralRuleFields()
        RunConsoleCommand("pmav_modern_units", data)
        timer.Simple(0, function()
            if IsValid(frame) then
                refreshModernUnitFields()
            end
        end)
    end

    for _, entry in ipairs({
        generalControls.height,
        generalControls.camera,
        generalControls.crouch
    }) do
        entry.OnChange = function()
            if suppressModernGeneralChange then
                return
            end

            syncModernGeneralHeightFields()
            updateModernPhysicalAutoPlaceholders(rule)
            scheduleModernPreviewApply()
        end
        entry.OnEnter = function()
            if isfunction(applyModernRule) then
                applyModernRule(true)
            end
        end
        entry.OnLoseFocus = function()
            if isfunction(applyModernRule) then
                applyModernRule(true)
            end
        end
    end

    for _, entry in ipairs({
        generalControls.camX,
        generalControls.camY,
        generalControls.speed,
        generalControls.jump,
        generalControls.mass,
        generalControls.push
    }) do
        entry.OnChange = function()
            if suppressModernGeneralChange then
                return
            end

            syncModernGeneralRuleFields()
            updateModernPhysicalAutoPlaceholders(rule)
            scheduleModernPreviewApply()
        end
        entry.OnEnter = function()
            if isfunction(applyModernRule) then
                applyModernRule(true)
            end
        end
        entry.OnLoseFocus = function()
            if isfunction(applyModernRule) then
                applyModernRule(true)
            end
        end
    end

    local activeMarker = nil
    local activeMarkerOffsetY = 0
    local activeWidthMarker = nil
    local hoveredWidthMarker = nil
    local cameraOffsetAnim = 0
    local updateValuesLabel

    local function getDefaultHorizontalBounds()
        local mins, maxs = IsValid(ply) and ply:GetHull()

        if mins and maxs then
            return mins.x, mins.y, maxs.x, maxs.y
        end

        return -16, -16, 16, 16
    end

    local function buildModernWidthState(activeRule)
        activeRule = activeRule or rule

        local minX, minY, maxX, maxY = getDefaultHorizontalBounds()
        local length = NumberOr(activeRule.collisionLength, 0)
        local width = NumberOr(activeRule.collisionWidth, 0)

        if length > 0 then
            minX = -length * 0.5
            maxX = length * 0.5
        end

        if width > 0 then
            minY = -width * 0.5
            maxY = width * 0.5
        end

        return {
            minX = NumberOr(activeRule.collisionMinX, 0) < 0 and NumberOr(activeRule.collisionMinX, 0) or minX,
            maxX = NumberOr(activeRule.collisionMaxX, 0) > 0 and NumberOr(activeRule.collisionMaxX, 0) or maxX,
            minY = NumberOr(activeRule.collisionMinY, 0) < 0 and NumberOr(activeRule.collisionMinY, 0) or minY,
            maxY = NumberOr(activeRule.collisionMaxY, 0) > 0 and NumberOr(activeRule.collisionMaxY, 0) or maxY,
            cameraX = NumberOr(activeRule.cameraOffsetX, 0),
            cameraY = NumberOr(activeRule.cameraOffsetY, 0)
        }
    end

    widthState = buildModernWidthState(rule)

    setModernActiveModel = function(nextModel)
        nextModel = NormalizeModel(nextModel)

        if nextModel == "" then
            return
        end

        model = nextModel
        rule = table.Copy(AV.GetRule(model) or DefaultRule())
        modelMins, modelMaxs = getModernModelBoundsForPath(model)
        modelScale = IsValid(ply) and GetAdaptiveLookupModel(ply) == model and GetLocalAdaptiveModelScale(ply) or 1
        autoHeight = math.max(getModernModelHeightForPath(model) * modelScale, 1)
        modelHeight = autoHeight

        hullTop = getModernCollisionHeight(rule)
        crouchTop = gameHeightToVisualHeight(getModernDuckCameraHeight(rule))
        cameraTop = gameHeightToVisualHeight(getModernCameraHeight(rule))

        markerByKey.hull.value = hullTop
        markerByKey.camera.value = cameraTop
        markerByKey.crouch.value = crouchTop
        markerByKey.floor.value = getModernCollisionBottom()
        widthState = buildModernWidthState(rule)

        generalDrop.selectedModel = model
        updateGeneralDropPreview()
        updateModernGeneralFieldsFromVisual()
        suppressModernGeneralChange = true
        generalControls.speed:SetText(modernGeneralTextValue(NumberOr(rule.speed, -1), NumberOr(rule.speed, -1) == -1))
        generalControls.jump:SetText(modernGeneralTextValue(NumberOr(rule.jump, -1), NumberOr(rule.jump, -1) == -1))
        generalControls.mass:SetText(modernGeneralTextValue(formatModernMassValue(rule.mass), NumberOr(rule.mass, -1) == -1))
        generalControls.push:SetText(modernGeneralTextValue(formatModernMassValue(rule.pickupLimit), NumberOr(rule.pickupLimit, -1) == -1))
        generalControls.pinEye.value = rule.pinCameraOnEye == true
        generalControls.pinEye.anim = generalControls.pinEye.value and 0 or 1
        if IsValid(generalControls.pinSmooth) then
            generalControls.pinSmooth:SetValue(NumberOr(rule.pinEyeSmoothing, 0.50))
        end
        suppressModernGeneralChange = false
        updateModernPhysicalAutoPlaceholders(rule)

        if IsValid(modelPanel) then
            modelPanel:SetModel(model)
            if IsValid(modelPanel.Entity) then
                freezeModernPreviewEntity(modelPanel.Entity, false)
            end
        end

        updateModelCamera()
        updateValuesLabel()

        if isfunction(rebuildModernRuleSections) then
            rebuildModernRuleSections()
        end
    end

    local function getModernPreviewHullBounds()
        local mins = Vector(-16, -16, 0)
        local maxs = Vector(16, 16, 72)

        if IsValid(ply) then
            local liveMins, liveMaxs = ply:GetHull()

            if liveMins and liveMaxs then
                mins = liveMins
                maxs = liveMaxs
            end
        end

        local floor = NumberOr(markerByKey.floor and markerByKey.floor.value, 0)
        local top = NumberOr(markerByKey.hull and markerByKey.hull.value, modelHeight)

        return Vector(widthState.minX or mins.x, widthState.minY or mins.y, floor), Vector(widthState.maxX or maxs.x, widthState.maxY or maxs.y, math.max(top, floor + 1))
    end

    drawModernPreviewHull = function()
        if activeModernTab == "widths" then
            return
        end

        if not cvDebugBounds:GetBool() then
            return
        end

        local mins, maxs = getModernPreviewHullBounds()
        local topCenter = Vector((mins.x + maxs.x) * 0.5, (mins.y + maxs.y) * 0.5, maxs.z)

        render.DrawWireframeBox(Vector(0, 0, 0), Angle(0, 0, 0), mins, maxs, Color(70, 225, 255, 255), true)
        render.SetColorMaterial()
        render.DrawSphere(topCenter, 0.9, 8, 8, Color(255, 40, 40, 255))
    end

    getDisplayMaxUnits = function()
        local highest = math.max(modelHeight, autoHeight, markerByKey.hull.value, markerByKey.camera.value, markerByKey.crouch.value, markerByKey.floor.value, 64)
        local maxMeters = SourceUnitsToMeters(highest) * 1.18 * getModernEffectiveRangeScale()
        local step = GetMetricStep(maxMeters)
        local displayMeters = math.max(step * 5, math.ceil(maxMeters / step) * step)

        return MetersToSourceUnits(displayMeters), displayMeters, step
    end

    yFromUnits = function(units, h)
        h = math.max(NumberOr(h, projection.panelH), 1)

        return h - math.Clamp(NumberOr(units, 0) / math.max(projection.maxUnits, 1), 0, 1) * h
    end

    local function unitsFromY(y, h)
        h = math.max(NumberOr(h, projection.panelH), 1)

        return math.Clamp((h - NumberOr(y, h)) / h, 0, 1) * math.max(projection.maxUnits, 1)
    end

    updateValuesLabel = function()
        local savedRule = AV.GetRule(model)
        local liveMins, liveMaxs = IsValid(ply) and ply:GetHull()
        local serverBounds = AV.ServerBounds and AV.ServerBounds[ply]

        valuesLabel:SetText(string.format(
            "Model: %s\nRule: %s\nVisual model height: %s\nCamera visual: %s\nDuck camera: %s\nHitbox top: %s\nHitbox bottom: %s\nWidth X: %.1f .. %.1f | Y: %.1f .. %.1f\nCamera XY offset: %.1f / %.1f\nScale: %.2fx\nRule HB: %.2f | Live HB: %.2f | Server HB: %.2f | Mode: %d",
            model,
            savedRule and "exists" or "not saved",
            formatModernMeters(modelHeight),
            formatModernMeters(markerByKey.camera.value),
            formatModernMeters(markerByKey.crouch.value),
            formatModernMeters(markerByKey.hull.value),
            formatModernMeters(markerByKey.floor.value),
            widthState.minX,
            widthState.maxX,
            widthState.minY,
            widthState.maxY,
            widthState.cameraX,
            widthState.cameraY,
            modelScale,
            NumberOr(savedRule and savedRule.collisionHeight, 0),
            NumberOr(liveMaxs and liveMaxs.z, 0),
            NumberOr(serverBounds and serverBounds.maxs and serverBounds.maxs.z, 0),
            cvCollisionMode:GetInt()
        ))
    end

    local function ensureModernHeightCollisionMode()
        if not cvCollision:GetBool() then
            RunConsoleCommand("pmav_collision", "1")
        end

        local mode = cvCollisionMode:GetInt()

        if mode == 0 then
            RunConsoleCommand("pmav_collision_mode", "1")
        elseif mode == 2 then
            RunConsoleCommand("pmav_collision_mode", "3")
        end
    end

    local function ensureModernWidthCollisionMode()
        if not cvCollision:GetBool() then
            RunConsoleCommand("pmav_collision", "1")
        end

        local mode = cvCollisionMode:GetInt()

        if mode == 0 then
            RunConsoleCommand("pmav_collision_mode", "2")
        elseif mode == 1 then
            RunConsoleCommand("pmav_collision_mode", "3")
        end
    end

    applyModernRule = function(shouldSave, keepVisualHeights)
        if not keepVisualHeights then
            syncModernGeneralHeightFields()
        end

        syncModernGeneralRuleFields()
        ensureModernHeightCollisionMode()
        ensureModernWidthCollisionMode()

        local finalCameraHeight = markerByKey.camera.value
        local finalDuckCameraHeight = markerByKey.crouch.value
        local finalCollisionHeight = math.max(markerByKey.hull.value, 0)
        local height = getStoredCameraHeightFromFinal(finalCameraHeight)
        local duckHeight = getStoredDuckCameraHeightFromFinal(finalDuckCameraHeight)
        local collisionHeight = getStoredCollisionHeightFromFinal(finalCollisionHeight)

        AV.SetRule(
            model,
            "height",
            height,
            0,
            0,
            collisionHeight,
            rule.collisionWidth or 0,
            rule.collisionLength or 0,
            rule.speed or -1,
            rule.jump or -1,
            shouldSave,
            duckHeight,
            widthState.minX,
            widthState.maxX,
            widthState.minY,
            widthState.maxY,
            widthState.cameraX,
            widthState.cameraY,
            rule.pinCameraOnEye == true,
            NumberOr(rule.pinEyeSmoothing, 0.50),
            NumberOr(rule.mass, -1),
            NumberOr(rule.pickupLimit, -1)
        )

        rule = table.Copy(AV.GetRule(model) or rule)
        widthState = buildModernWidthState(rule)
        if isfunction(rebuildModernRuleSections) then
            rebuildModernRuleSections()
        end
        updateValuesLabel()
        timer.Simple(0.15, function()
            if IsValid(frame) then
                updateValuesLabel()
            end
        end)
    end

    generalControls.pinEye.OnValueChanged = function(_, value)
        if suppressModernGeneralChange then
            return
        end

        rule.pinCameraOnEye = value == true
        generalCanvas.pmavLayoutSig = nil
        updateModernGeneralLayout(generalPage:GetWide(), generalPage:GetTall())
        generalPage:InvalidateLayout(true)
        generalCanvas:InvalidateLayout(true)

        if isfunction(applyModernRule) then
            applyModernRule(true)
        end
    end

    generalControls.pinSmooth.OnValueChanged = function(_, value)
        if suppressModernGeneralChange then
            return
        end

        rule.pinEyeSmoothing = math.Clamp(NumberOr(value, 0.50), 0, 1)

        if isfunction(applyModernRule) then
            applyModernRule(true)
        end
    end

    previewButton.DoClick = function()
        applyModernRule(false)
    end

    applyButton.DoClick = function()
        applyModernRule(true)
    end

    resetPreviewButton.DoClick = function()
        rule = table.Copy(AV.GetRule(model) or DefaultRule())
        hullTop = getModernCollisionHeight(rule)
        crouchTop = gameHeightToVisualHeight(getModernDuckCameraHeight(rule))
        cameraTop = gameHeightToVisualHeight(getModernCameraHeight(rule))
        markerByKey.hull.value = hullTop
        markerByKey.camera.value = cameraTop
        markerByKey.crouch.value = crouchTop
        markerByKey.floor.value = getModernCollisionBottom()
        widthState = buildModernWidthState(rule)
        metricRangeScale = 1

        if IsValid(zoomSlider) then
            zoomSlider:SetValue(metricRangeScale)
        end

        updateModernGeneralFieldsFromVisual()
        updateModelCamera()
        updateValuesLabel()
    end

    removeRuleButton.DoClick = function()
        AV.SetRule(model, nil, nil, nil, nil, nil, nil, nil, nil, nil, true)
        rule = DefaultRule()
        resetPreviewButton:DoClick()
    end

    local widthHandles = {
        { key = "minX", label = "Left", icon = "LeftHB", color = Color(30, 137, 20, 255) },
        { key = "maxX", label = "Right", icon = "RightHB", color = Color(30, 137, 20, 255) },
        { key = "maxY", label = "Forward", icon = "ForwardHB", color = Color(30, 137, 20, 255) },
        { key = "minY", label = "Back", icon = "BackHB", color = Color(30, 137, 20, 255) }
    }

    getWidthLayout = function(w, h)
        local left = 44
        local right = math.max(w - 58, left + 180)
        local top = 54
        local bottom = h - 48
        local centerX = (left + right) * 0.5
        local centerY = (top + bottom) * 0.5
        local largest = math.max(
            math.abs(widthState.minX or -16),
            math.abs(widthState.maxX or 16),
            math.abs(widthState.minY or -16),
            math.abs(widthState.maxY or 16),
            math.abs(widthState.cameraX or 0) + 8,
            math.abs(widthState.cameraY or 0) + 8,
            32
        ) * getModernEffectiveRangeScale()
        local pixelsPerUnit = math.min(right - left, bottom - top) * 0.45 / math.max(largest, 1)

        return {
            left = left,
            right = right,
            top = top,
            bottom = bottom,
            centerX = centerX,
            centerY = centerY,
            handleTopY = 24,
            handleRightX = w - 22,
            pixelsPerUnit = pixelsPerUnit,
            largest = largest
        }
    end

    widthXToPanel = function(value, layout)
        return layout.centerX + NumberOr(value, 0) * layout.pixelsPerUnit
    end

    widthYToPanel = function(value, layout)
        return layout.centerY - NumberOr(value, 0) * layout.pixelsPerUnit
    end

    local function panelToWidthX(value, layout)
        return math.Clamp((NumberOr(value, layout.centerX) - layout.centerX) / math.max(layout.pixelsPerUnit, 0.001), -96, 96)
    end

    local function panelToWidthY(value, layout)
        return math.Clamp((layout.centerY - NumberOr(value, layout.centerY)) / math.max(layout.pixelsPerUnit, 0.001), -96, 96)
    end

    local function getWidthHandlePosition(handle, layout)
        local minX = widthXToPanel(widthState.minX, layout)
        local maxX = widthXToPanel(widthState.maxX, layout)
        local minY = widthYToPanel(widthState.minY, layout)
        local maxY = widthYToPanel(widthState.maxY, layout)
        local centerX = (minX + maxX) * 0.5
        local centerY = (minY + maxY) * 0.5

        if handle.key == "minX" then
            return minX, layout.handleTopY
        elseif handle.key == "maxX" then
            return maxX, layout.handleTopY
        elseif handle.key == "maxY" then
            return layout.handleRightX, maxY
        end

        return layout.handleRightX, minY
    end

    local function applyWidthDrag(key, x, y, layout)
        if key == "camera" then
            widthState.cameraX = math.Clamp(panelToWidthX(x, layout), -64, 64)
            widthState.cameraY = math.Clamp(panelToWidthY(y, layout), -64, 64)
        elseif key == "minX" then
            widthState.minX = math.min(panelToWidthX(x, layout), (widthState.maxX or 16) - 4)
        elseif key == "maxX" then
            widthState.maxX = math.max(panelToWidthX(x, layout), (widthState.minX or -16) + 4)
        elseif key == "minY" then
            widthState.minY = math.min(panelToWidthY(y, layout), (widthState.maxY or 16) - 4)
        elseif key == "maxY" then
            widthState.maxY = math.max(panelToWidthY(y, layout), (widthState.minY or -16) + 4)
        end

        widthState.minX = math.Clamp(widthState.minX, -96, -4)
        widthState.maxX = math.Clamp(widthState.maxX, 4, 96)
        widthState.minY = math.Clamp(widthState.minY, -96, -4)
        widthState.maxY = math.Clamp(widthState.maxY, 4, 96)
        updateModernGeneralFieldsFromVisual()
        updateValuesLabel()
        updateModelCamera()
    end

    modelPanel.OnMousePressed = function(self, code)
        if code ~= MOUSE_LEFT then
            return
        end

        local mx, my = self:CursorPos()

        if activeModernTab == "widths" then
            local layout = getWidthLayout(self:GetWide(), self:GetTall())
            local camX = widthXToPanel(widthState.cameraX, layout)
            local camY = widthYToPanel(widthState.cameraY, layout)

            if math.abs(mx - camX) <= 26 and math.abs(my - camY) <= 26 then
                activeWidthMarker = "camera"
                self:MouseCapture(true)
                return
            end

            for _, handle in ipairs(widthHandles) do
                local hx, hy = getWidthHandlePosition(handle, layout)

                if math.abs(mx - hx) <= 24 and math.abs(my - hy) <= 24 then
                    activeWidthMarker = handle.key
                    self:MouseCapture(true)
                    return
                end
            end

            return
        end

        for _, marker in ipairs(markers) do
            if not marker.locked then
                local y = yFromUnits(marker.value, self:GetTall())

                if math.abs(my - y) <= 30 and mx >= self:GetWide() * 0.08 and mx <= self:GetWide() - 20 then
                    activeMarker = marker
                    activeMarkerOffsetY = my - y
                    self:MouseCapture(true)
                    return
                end
            end
        end
    end

    modelPanel.OnMouseReleased = function(self)
        local shouldApply = activeMarker ~= nil or activeWidthMarker ~= nil
        activeMarker = nil
        activeMarkerOffsetY = 0
        activeWidthMarker = nil
        self:MouseCapture(false)

        if shouldApply then
            applyModernRule(true, true)
        end
    end

    modelPanel.OnMouseWheeled = function(_, delta)
        metricRangeScale = math.Clamp(metricRangeScale - delta * 0.05, 1, 3)

        if IsValid(zoomSlider) then
            zoomSlider:SetValue(metricRangeScale)
        end

        updateModelCamera()
        return true
    end

    modelPanel.OnCursorMoved = function(self, _, y)
        local x = select(1, self:CursorPos())

        if activeModernTab == "widths" then
            local layout = getWidthLayout(self:GetWide(), self:GetTall())

            if activeWidthMarker then
                applyWidthDrag(activeWidthMarker, x, y, layout)
                return
            end

            hoveredWidthMarker = nil
            local camX = widthXToPanel(widthState.cameraX, layout)
            local camY = widthYToPanel(widthState.cameraY, layout)

            if math.abs(x - camX) <= 26 and math.abs(y - camY) <= 26 then
                hoveredWidthMarker = "camera"
            else
                for _, handle in ipairs(widthHandles) do
                    local hx, hy = getWidthHandlePosition(handle, layout)

                    if math.abs(x - hx) <= 24 and math.abs(y - hy) <= 24 then
                        hoveredWidthMarker = handle.key
                        break
                    end
                end
            end

            self.HoveredMarker = nil
            return
        end

        local hovered = nil

        if activeMarker then
            activeMarker.value = math.max(unitsFromY(y - activeMarkerOffsetY, self:GetTall()), activeMarker.minValue or 0)
            updateModernGeneralFieldsFromVisual()
            updateValuesLabel()
            updateModelCamera()
            return
        end

        for _, marker in ipairs(markers) do
            if not marker.locked and math.abs(y - yFromUnits(marker.value, self:GetTall())) <= 30 then
                hovered = marker.key
                break
            end
        end

        self.HoveredMarker = hovered
    end

    modelPanel.PaintOver = function(self, w, h)
        updateModelCamera()

        local maxUnits, displayMeters, step = getDisplayMaxUnits()
        local left = 0
        local right = w - 5
        local metricTextLeft = right - 136

        if activeModernTab == "widths" then
            local layout = getWidthLayout(w, h)
            local minX = widthXToPanel(widthState.minX, layout)
            local maxX = widthXToPanel(widthState.maxX, layout)
            local minY = widthYToPanel(widthState.minY, layout)
            local maxY = widthYToPanel(widthState.maxY, layout)
            local camX = widthXToPanel(widthState.cameraX, layout)
            local camY = widthYToPanel(widthState.cameraY, layout)
            local shouldDrawWidthDebugHull = cvDebugBounds:GetBool()

            if shouldDrawWidthDebugHull then
                surface.SetDrawColor(70, 225, 255, 220)
                surface.DrawLine(minX, minY, maxX, minY)
                surface.DrawLine(maxX, minY, maxX, maxY)
                surface.DrawLine(maxX, maxY, minX, maxY)
                surface.DrawLine(minX, maxY, minX, minY)
            end

            surface.SetDrawColor(70, 225, 255, 85)
            surface.DrawLine(layout.centerX, layout.top, layout.centerX, layout.bottom)
            surface.DrawLine(layout.left, layout.centerY, layout.right, layout.centerY)

            for _, handle in ipairs(widthHandles) do
                local hx, hy = getWidthHandlePosition(handle, layout)
                local isVerticalSide = handle.key == "minX" or handle.key == "maxX"
                local isActive = activeWidthMarker == handle.key
                local isHovered = hoveredWidthMarker == handle.key
                local targetState = isActive and 2 or isHovered and 1 or 0
                handle.animState = Lerp(FrameTime() * 14, handle.animState or 0, targetState)

                local baseSize = isVerticalSide and 38 or 34
                local pressedW = 62
                local pressedH = 62
                local pressedProgress = math.Clamp((handle.animState or 0) - 1, 0, 1)
                local handleW = isVerticalSide and baseSize or Lerp(pressedProgress, baseSize, pressedW)
                local handleH = isVerticalSide and Lerp(pressedProgress, baseSize, pressedH) or baseSize
                local color = Color(handle.color.r, handle.color.g, handle.color.b, isActive and 255 or isHovered and 230 or 190)
                local handleX = isVerticalSide and hx - handleW * 0.5 or layout.handleRightX - handleW
                local handleY = isVerticalSide and layout.handleTopY - baseSize * 0.5 or hy - handleH * 0.5

                surface.SetDrawColor(color.r, color.g, color.b, isActive and 255 or isHovered and 217 or 178)

                if isVerticalSide then
                    surface.DrawRect(hx - 1, handleY + handleH * 0.5, 2, layout.bottom - handleY)
                else
                    surface.DrawRect(layout.left, hy - 1, layout.handleRightX - handleW * 0.5 - layout.left, 2)
                end

                if isVerticalSide then
                    DrawModernMarkerHandleVertical(handleX, handleY, handleW, handleH, color, handle.animState)
                else
                    DrawModernMarkerHandle(handleX, handleY, handleW, handleH, color, handle.animState)
                end

                local icon = GetIconMaterial(handle.icon)

                if icon then
                    local iconW = isVerticalSide and 25 or 40
                    local iconH = isVerticalSide and 56 or 15
                    surface.SetMaterial(icon)
                    surface.SetDrawColor(255, 255, 255, 255)
                    surface.DrawTexturedRect(handleX + handleW * 0.5 - iconW * 0.5, handleY + handleH * 0.5 - iconH * 0.5, iconW, iconH)
                else
                    draw.SimpleText(handle.label, "DermaDefaultBold", handleX + handleW * 0.5, handleY + handleH * 0.5, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
            end

            local hoveredAmount = (hoveredWidthMarker == "camera" or activeWidthMarker == "camera") and 1 or 0
            cameraOffsetAnim = Lerp(FrameTime() * 14, cameraOffsetAnim, hoveredAmount)
            local normalMat = GetModernMaterial("4mo_icos/mui/CameraHadNormal.png")
            local hoverMat = GetModernMaterial("4mo_icos/mui/CamreraHadHovered.png")
            local normalSize = 30

            if normalMat then
                surface.SetMaterial(normalMat)
                surface.SetDrawColor(255, 255, 255, 255)
                surface.DrawTexturedRect(camX - normalSize * 0.5, camY - normalSize * 0.5, normalSize, normalSize)
            else
                draw.RoundedBox(16, camX - 15, camY - 15, 30, 30, Color(29, 113, 243, 230))
            end

            if hoverMat then
                local pressed = activeWidthMarker == "camera"
                local scale = pressed and 0.3 or Lerp(cameraOffsetAnim, 0.2, 1)
                local size = 42 * scale

                surface.SetMaterial(hoverMat)
                surface.SetDrawColor(255, 255, 255, math.Round(255 * math.max(cameraOffsetAnim, pressed and 1 or 0)))
                surface.DrawTexturedRect(camX - size * 0.5, camY - size * 0.5, size, size)
            end

            if activeWidthMarker == "camera" then
                surface.SetDrawColor(255, 255, 255, 180)
                surface.DrawLine(camX, layout.top, camX, layout.bottom)
                surface.DrawLine(layout.left, camY, layout.right, camY)
            end

            return
        end

        -- Meter labels are intentionally hidden while the visual ruler is being refined.

        if activeModernTab == "widths" then
            local layout = getWidthLayout(w, h)
            local minX = widthXToPanel(widthState.minX, layout)
            local maxX = widthXToPanel(widthState.maxX, layout)
            local minY = widthYToPanel(widthState.minY, layout)
            local maxY = widthYToPanel(widthState.maxY, layout)
            local camX = widthXToPanel(widthState.cameraX, layout)
            local camY = widthYToPanel(widthState.cameraY, layout)

            surface.SetDrawColor(70, 225, 255, 220)
            surface.DrawLine(minX, minY, maxX, minY)
            surface.DrawLine(maxX, minY, maxX, maxY)
            surface.DrawLine(maxX, maxY, minX, maxY)
            surface.DrawLine(minX, maxY, minX, minY)

            surface.SetDrawColor(70, 225, 255, 80)
            surface.DrawLine(layout.centerX, layout.top, layout.centerX, layout.bottom)
            surface.DrawLine(layout.left, layout.centerY, layout.right, layout.centerY)

            for _, handle in ipairs(widthHandles) do
                local hx, hy = getWidthHandlePosition(handle, layout)
                local isActive = activeWidthMarker == handle.key
                local isHovered = hoveredWidthMarker == handle.key
                local size = isActive and 34 or isHovered and 31 or 28
                local color = Color(handle.color.r, handle.color.g, handle.color.b, isActive and 255 or isHovered and 230 or 190)

                surface.SetDrawColor(color)
                surface.DrawRect(hx - size * 0.5, hy - size * 0.5, size, size)

                local icon = GetIconMaterial(handle.icon)
                if icon then
                    surface.SetMaterial(icon)
                    surface.SetDrawColor(255, 255, 255, 255)
                    surface.DrawTexturedRect(hx - 10, hy - 10, 20, 20)
                else
                    draw.SimpleText(handle.label, "DermaDefaultBold", hx, hy, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
            end

            local hoveredAmount = (hoveredWidthMarker == "camera" or activeWidthMarker == "camera") and 1 or 0
            cameraOffsetAnim = Lerp(FrameTime() * 14, cameraOffsetAnim, hoveredAmount)
            local normalMat = GetModernMaterial("4mo_icos/mui/CameraHadNormal.png")
            local hoverMat = GetModernMaterial("4mo_icos/mui/CamreraHadHovered.png")
            local normalSize = 30

            if normalMat then
                surface.SetMaterial(normalMat)
                surface.SetDrawColor(255, 255, 255, 255)
                surface.DrawTexturedRect(camX - normalSize * 0.5, camY - normalSize * 0.5, normalSize, normalSize)
            else
                draw.RoundedBox(16, camX - 15, camY - 15, 30, 30, Color(29, 113, 243, 230))
            end

            if hoverMat then
                local pressed = activeWidthMarker == "camera"
                local scale = pressed and 0.3 or Lerp(cameraOffsetAnim, 0.2, 1)
                local size = 42 * scale

                surface.SetMaterial(hoverMat)
                surface.SetDrawColor(255, 255, 255, math.Round(255 * math.max(cameraOffsetAnim, pressed and 1 or 0)))
                surface.DrawTexturedRect(camX - size * 0.5, camY - size * 0.5, size, size)
            end

            if activeWidthMarker == "camera" then
                surface.SetDrawColor(255, 255, 255, 180)
                surface.DrawLine(camX, layout.top, camX, layout.bottom)
                surface.DrawLine(layout.left, camY, layout.right, camY)
            end

            draw.SimpleText(string.format("X %.1f / Y %.1f", widthState.cameraX, widthState.cameraY), "DermaDefaultBold", layout.left, layout.top - 22, Color(220, 220, 220), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            return
        end

        for _, marker in ipairs(markers) do
            local y = yFromUnits(marker.value, h)
            local color = marker.color

            if y >= -40 and y <= h + 40 then
                local cursorX, cursorY = self:CursorPos()
                local baseSize = 34
                local pressedW = 62
                local hitW = pressedW
                local hitH = 40
                local handleState = 0
                local hitX = right - hitW

                if activeMarker == marker then
                    handleState = 2
                elseif cursorX >= hitX and cursorX <= right and cursorY >= y - hitH * 0.5 and cursorY <= y + hitH * 0.5 then
                    handleState = 1
                end

                marker.animState = Lerp(math.Clamp(FrameTime() * 14, 0, 1), marker.animState or 0, handleState)

                local handleW = baseSize
                if marker.animState > 1 then
                    handleW = Lerp(marker.animState - 1, baseSize, pressedW)
                end

                local handleH = baseSize
                local handleX = right - handleW
                local handleY = y - handleH * 0.5
                local dimmedAlpha = activeMarker and 64 or self.HoveredMarker and 128 or 178
                local lineAlpha = dimmedAlpha

                if activeMarker == marker then
                    lineAlpha = 255
                elseif self.HoveredMarker == marker.key then
                    lineAlpha = 217
                end

                surface.SetDrawColor(color.r, color.g, color.b, lineAlpha)
                surface.DrawRect(0, y - 1, math.max(handleX, 0), 2)

                DrawModernMarkerHandle(handleX, handleY, handleW, handleH, color, marker.animState)

                local icon = GetIconMaterial(marker.icon)

                if icon then
                    surface.SetMaterial(icon)
                    surface.SetDrawColor(255, 255, 255, 255)
                    local pressedProgress = math.Clamp((marker.animState or 0) - 1, 0, 1)
                    local iconScale = Lerp(pressedProgress, 1, 1.12)
                    local drawW = (marker.iconW or 22) * iconScale
                    local drawH = (marker.iconH or 22) * iconScale
                    local circleCenterX = right - baseSize * 0.5
                    local rectCenterX = handleX + handleW * 0.5
                    local centerX = Lerp(pressedProgress, circleCenterX, rectCenterX)
                    local centerY = y + NumberOr(marker.iconYOffset, 0)
                    surface.DrawTexturedRect(centerX - drawW * 0.5, centerY - drawH * 0.5, drawW, drawH)
                else
                    draw.SimpleText(marker.key == "camera" and "eye" or marker.key == "floor" and "L" or "HB", "DermaDefaultBold", right - baseSize * 0.5, y, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
            end
        end

    end

    local function makeBottomTab(text, tabKey, x)
        local tab = vgui.Create("DButton", bottomTabs)
        tab:SetText("")
        tab:SetSize(105, 26)
        tab:SetPos(x, 8)
        tab.Paint = function(_, w, h)
            local active = activeModernTab == tabKey
            draw.RoundedBox(3, 0, 0, w, h, active and Color(45, 180, 195) or Color(90, 96, 112))
            surface.SetDrawColor(140, 150, 160, 255)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
            draw.SimpleText(text, "DermaDefaultBold", w * 0.5, h * 0.5, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        tab.DoClick = function()
            activeModernTab = tabKey
            activeMarker = nil
            activeWidthMarker = nil
            hoveredWidthMarker = nil
        end
        return tab
    end

    bottomTabs.PerformLayout = function(_, w)
        local tabW = 105
        local gap = 14
        local zoomW = 190
        local totalW = tabW * 2 + gap + zoomW + 10
        local startX = math.max(w * 0.5 - totalW * 0.5, 10)

        if not IsValid(bottomTabs.HeightTab) then
            bottomTabs.HeightTab = makeBottomTab("Heights", "heights", startX)
            bottomTabs.WidthTab = makeBottomTab("Widths", "widths", startX + tabW + gap)
        end

        bottomTabs.HeightTab:SetPos(startX, 8)
        bottomTabs.WidthTab:SetPos(startX + tabW + gap, 8)
    end

    zoomSlider = vgui.Create("DNumSlider", bottomTabs)
    zoomSlider:SetText("")
    zoomSlider:SetMinMax(1, 3)
    zoomSlider:SetDecimals(2)
    zoomSlider:SetValue(metricRangeScale)
    zoomSlider:SetWide(150)
    zoomSlider.OnValueChanged = function(_, value)
        metricRangeScale = value
        updateModelCamera()
    end

    bottomTabs.PaintOver = function(_, w)
        local tabW = 105
        local gap = 14
        local zoomW = 190
        local totalW = tabW * 2 + gap + zoomW + 10
        local startX = math.max(w * 0.5 - totalW * 0.5, 10)
        local zoomX = startX + (tabW + gap) * 2 + 2

        zoomSlider:SetPos(zoomX + 20, 3)
        draw.SimpleText("-", "DermaLarge", zoomX, 20, Color(230, 230, 230), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("+", "DermaLarge", zoomX + 166, 20, Color(230, 230, 230), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    updateValuesLabel()
end

local function AddAdaptiveViewMenu()
    spawnmenu.AddToolMenuOption("Options", "Player", "pm_eblansky_adaptive_view", "Adaptive View", "", "", function(panel)
        panel:ClearControls()

        if not CanLocalEditSettings() then
            AddThanksOnly(panel)
            return
        end

        AddCompatibilitySupportPanel(panel)

        panel:CheckBox("Enable add-on", "pmav_enabled")
        panel:CheckBox("Adapt collision", "pmav_collision")
        panel:CheckBox("Adapt NPC/NextBot collision (experimental)", "pmav_npc_collision")
        panel:CheckBox("Collision only players", "pmav_collision_only_players")
        panel:CheckBox("Adapt speed to hitbox height", "pmav_adaptive_speed")
        panel:CheckBox("Adapt jump to hitbox height", "pmav_adaptive_jump")
        panel:CheckBox("Adapt pickup weight", "pmav_adaptive_pickup_weight")
        if CanUseDebugBounds() then
            panel:CheckBox("Draw debug bounds", "pmav_debug_bounds")
        end

        local thanksButton = panel:Button("Thank them!")
        thanksButton.DoClick = OpenThanksWindow

        local modernRuleButton = panel:Button("Edit Rules")
        modernRuleButton.DoClick = OpenModernRuleMenu

        local legacyRules = vgui.Create("DForm")
        legacyRules:SetName("Legacy")
        panel:AddItem(legacyRules)

        local collisionMode = vgui.Create("DComboBox")
        collisionMode:AddChoice("Nothing", "0")
        collisionMode:AddChoice("Height only", "1")
        collisionMode:AddChoice("Width/length only", "2")
        collisionMode:AddChoice("Height + width/length", "3")
        collisionMode:ChooseOptionID(math.Clamp(cvCollisionMode:GetInt(), 0, 3) + 1)
        collisionMode.OnSelect = function(_, _, _, value)
            RunConsoleCommand("pmav_collision_mode", value)
        end
        legacyRules:AddItem(collisionMode)

        legacyRules:NumSlider("Auto height scale", "pmav_auto_scale", 0.7, 1.1, 2)
        legacyRules:NumSlider("Global offset", "pmav_global_offset", -24, 24, 1)
        legacyRules:NumSlider("Min auto height", "pmav_min_height", 0, 80, 0)
        legacyRules:NumSlider("Max auto height", "pmav_max_height", 50, 160, 0)

        local resetButton = legacyRules:Button("Reset settings, keep model rules")
        resetButton.DoClick = ResetSettingsExceptRules

        local modelEntry = vgui.Create("DTextEntry")
        modelEntry:SetPlaceholderText("models/player/group01/male_07.mdl")
        modelEntry:SetText(IsValid(LocalPlayer()) and LocalPlayer():GetModel() or "")
        legacyRules:AddItem(modelEntry)

        local heightSlider = vgui.Create("DNumSlider")
        heightSlider:SetText("Camera exact height")
        heightSlider:SetMinMax(20, 120)
        heightSlider:SetDecimals(0)
        heightSlider:SetValue(64)
        legacyRules:AddItem(heightSlider)

        local offsetSlider = vgui.Create("DNumSlider")
        offsetSlider:SetText("Camera offset")
        offsetSlider:SetMinMax(-32, 32)
        offsetSlider:SetDecimals(1)
        offsetSlider:SetValue(0)
        legacyRules:AddItem(offsetSlider)

        local collisionHeightSlider = vgui.Create("DNumSlider")
        collisionHeightSlider:SetText("Hitbox height (0 = auto)")
        collisionHeightSlider:SetMinMax(0, 180)
        collisionHeightSlider:SetDecimals(0)
        collisionHeightSlider:SetValue(0)
        legacyRules:AddItem(collisionHeightSlider)

        local collisionWidthSlider = vgui.Create("DNumSlider")
        collisionWidthSlider:SetText("Hitbox width (0 = auto)")
        collisionWidthSlider:SetMinMax(0, 96)
        collisionWidthSlider:SetDecimals(0)
        collisionWidthSlider:SetValue(0)
        legacyRules:AddItem(collisionWidthSlider)

        local collisionLengthSlider = vgui.Create("DNumSlider")
        collisionLengthSlider:SetText("Hitbox length (0 = auto)")
        collisionLengthSlider:SetMinMax(0, 96)
        collisionLengthSlider:SetDecimals(0)
        collisionLengthSlider:SetValue(0)
        legacyRules:AddItem(collisionLengthSlider)

        local speedSlider = vgui.Create("DNumSlider")
        speedSlider:SetText("Speed (-2 base, -1 auto, 0 off)")
        speedSlider:SetMinMax(-2, 5)
        speedSlider:SetDecimals(2)
        speedSlider:SetValue(-1)
        legacyRules:AddItem(speedSlider)

        local jumpSlider = vgui.Create("DNumSlider")
        jumpSlider:SetText("Jump force (-2 base, -1 auto, 0 off)")
        jumpSlider:SetMinMax(-2, 5)
        jumpSlider:SetDecimals(2)
        jumpSlider:SetValue(-1)
        legacyRules:AddItem(jumpSlider)

        local modeBox = vgui.Create("DComboBox")
        modeBox:AddChoice("Auto height", "auto", true)
        modeBox:AddChoice("Exact height", "height")
        modeBox:AddChoice("Disable for this model", "off")
        legacyRules:AddItem(modeBox)

        local list = vgui.Create("DListView")
        list:SetTall(180)
        list:AddColumn("Model")
        list:AddColumn("Mode")
        list:AddColumn("Cam height")
        list:AddColumn("Cam offset")
        list:AddColumn("HB height")
        list:AddColumn("HB width")
        list:AddColumn("HB length")
        list:AddColumn("Speed")
        list:AddColumn("Jump")

        local function getSelectedRule()
            local selected = list:GetSelectedLine()

            if not selected then
                return nil, nil
            end

            local row = list:GetLine(selected)
            local model = row and row:GetColumnText(1)

            return model, model and AV.GetRule(model)
        end

        local function resetRuleControls(rule)
            rule = rule or DefaultRule()
            modeBox:ChooseOptionID(rule.mode == "height" and 2 or rule.mode == "off" and 3 or 1)
            heightSlider:SetValue(rule.height or 64)
            offsetSlider:SetValue(rule.cameraOffset or rule.offset or 0)
            collisionHeightSlider:SetValue(rule.collisionHeight or 0)
            collisionWidthSlider:SetValue(rule.collisionWidth or 0)
            collisionLengthSlider:SetValue(rule.collisionLength or 0)
            speedSlider:SetValue(NumberOr(rule.speed, -1))
            jumpSlider:SetValue(NumberOr(rule.jump, -1))
        end

        local function saveRuleForModel(model, shouldSave)
            local selectedID = modeBox:GetSelectedID() or 1
            local mode = modeBox:GetOptionData(selectedID)
            AV.SetRule(
                model,
                mode or "auto",
                heightSlider:GetValue(),
                offsetSlider:GetValue(),
                offsetSlider:GetValue(),
                collisionHeightSlider:GetValue(),
                collisionWidthSlider:GetValue(),
                collisionLengthSlider:GetValue(),
                speedSlider:GetValue(),
                jumpSlider:GetValue(),
                shouldSave
            )
            FillRulesList(list)
        end

        local function applyCurrentModelRule(shouldSave)
            if not IsValid(LocalPlayer()) then
                return
            end

            local model = GetAdaptiveLookupModel(LocalPlayer())

            if model == "" or not AV.GetRule(model) then
                return
            end

            modelEntry:SetText(model)
            saveRuleForModel(model, shouldSave)
        end

        list.OnRowSelected = function(_, _, row)
            local model = row:GetColumnText(1)
            local rule = AV.GetRule(model)

            modelEntry:SetText(model)

            if rule then
                resetRuleControls(rule)
            end
        end

        list.OnRowRightClick = function(_, _, row)
            local model = row:GetColumnText(1)
            local menu = DermaMenu()
            menu:AddOption("Remove rule", function()
                AV.SetRule(model, nil)
                FillRulesList(list)
            end)
            menu:AddOption("Copy model path", function()
                SetClipboardText(model)
            end)
            menu:Open()
        end

        list.DoDoubleClick = function(_, _, row)
            OpenRuleEditor(row:GetColumnText(1), function(newModel, mode, height, offset, collisionHeight, collisionWidth, collisionLength, speed, jump)
                modelEntry:SetText(newModel)
                modeBox:ChooseOptionID(mode == "height" and 2 or mode == "off" and 3 or 1)
                heightSlider:SetValue(height or 64)
                offsetSlider:SetValue(offset or 0)
                collisionHeightSlider:SetValue(collisionHeight or 0)
                collisionWidthSlider:SetValue(collisionWidth or 0)
                collisionLengthSlider:SetValue(collisionLength or 0)
                speedSlider:SetValue(NumberOr(speed, -1))
                jumpSlider:SetValue(NumberOr(jump, -1))
                FillRulesList(list)
            end)
        end

        local applyButton = legacyRules:Button("Apply")
        applyButton.DoClick = function()
            applyCurrentModelRule(false)
        end

        local applySaveButton = legacyRules:Button("Apply & Save")
        applySaveButton.DoClick = function()
            applyCurrentModelRule(true)
        end

        local backButton = legacyRules:Button("Back to save")
        backButton.DoClick = function()
            local model = NormalizeModel(IsValid(LocalPlayer()) and LocalPlayer():GetModel() or modelEntry:GetText())
            local rule = model ~= "" and ReadSavedRule(model)

            if not rule then
                return
            end

            modelEntry:SetText(model)
            resetRuleControls(rule)
            AV.ModelRules[model] = rule
            FillRulesList(list)

            if isfunction(AV.SyncSettingsToServer) then
                AV.SyncSettingsToServer()
            end
        end

        local modernMenuButton = legacyRules:Button("About a future update for this menu(Modern UI Uptdate)")
        modernMenuButton.DoClick = OpenModernRuleMenuNotice

        legacyRules:AddItem(list)

        local saveButton = legacyRules:Button("Save model rule")
        saveButton.DoClick = function()
            saveRuleForModel(modelEntry:GetText(), true)
        end

        local addButton = legacyRules:Button("Add model from picker")
        addButton.DoClick = function()
            OpenModelPicker("Add model rule", modelEntry:GetText(), function(model)
                modelEntry:SetText(model)
                resetRuleControls(DefaultRule())
                saveRuleForModel(model, true)
            end)
        end

        local currentButton = legacyRules:Button("Use current model")
        currentButton.DoClick = function()
            if IsValid(LocalPlayer()) then
                local model = GetAdaptiveLookupModel(LocalPlayer())
                modelEntry:SetText(model)

                local rule = AV.GetRule(model)

                if rule then
                    resetRuleControls(rule)
                end
            end
        end

        local removeButton = legacyRules:Button("Remove selected model rule")
        removeButton.DoClick = function()
            local selectedModel = getSelectedRule()
            AV.SetRule(selectedModel or modelEntry:GetText(), nil)
            FillRulesList(list)
        end

        FillRulesList(list)
    end)
end

hook.Add("PopulateToolMenu", "pm_eblansky_adaptive_view_menu", AddAdaptiveViewMenu)

local function SyncSettingsSoon()
    if not CanUseDebugBounds() and cvDebugBounds:GetBool() then
        RunConsoleCommand("pmav_debug_bounds", "0")
    end

    if not isfunction(AV.SyncSettingsToServer) then
        return
    end

    if not CanLocalEditSettings() then
        return
    end

    timer.Create("pm_eblansky_adaptive_view_sync", 0.05, 1, AV.SyncSettingsToServer)
end

for _, convarName in ipairs({
    "pmav_auto_scale",
    "pmav_global_offset",
    "pmav_camera_fov",
    "pmav_camera_offset_x",
    "pmav_camera_offset_y",
    "pmav_scale_support",
    "pmav_scale_min",
    "pmav_scale_max",
    "pmav_smooth",
    "pmav_min_height",
    "pmav_max_height",
    "pmav_collision",
    "pmav_collision_mode",
    "pmav_collision_radius",
    "pmav_collision_only_players",
    "pmav_npc_collision",
    "pmav_multiplayer_safe",
    "pmav_adaptive_speed",
    "pmav_adaptive_jump",
    "pmav_adaptive_pickup_weight",
    "pmav_alladmins",
    "pmav_injail",
    "pmav_debug_mp",
    "pm_supp_outfitter"
}) do
    cvars.AddChangeCallback(convarName, SyncSettingsSoon, "pm_eblansky_adaptive_view")
end

cvars.AddChangeCallback("pmav_enabled", function(_, _, newValue)
    local enabled = tostring(newValue or "1") ~= "0"
    RunConsoleCommand("pmav_set_enabled", enabled and "1" or "0")

    if enabled then
        timer.Simple(0.05, SyncSettingsSoon)
    end
end, "pm_eblansky_adaptive_view_enabled_gate")

cvars.AddChangeCallback("pmav_auto_scale", function()
    AV.ReferenceHeights = {}
end, "pm_eblansky_adaptive_view_cache")

cvars.AddChangeCallback("pm_supp_outfitter", function()
    AV.ReferenceHeights = {}
    AV.LastSyncedState = nil
    AV.LastPredictedStand = nil
    AV.LastPredictedDuck = nil

    local ply = LocalPlayer()

    if IsValid(ply) then
        ply.pmavPinModel = nil
        ply.pmavPinBaseHeadHeight = nil
        ply.pmavPinTargetHeadDelta = nil
        ply.pmavPinSmoothedHeadDelta = nil
        ply.pmavPinLastOriginZ = nil
        ply.pmavPinStairFreezeUntil = nil
        ply.pmavPinLiveStandHeight = nil
        ply.pmavPinLiveDuckHeight = nil
    end
end, "pm_eblansky_adaptive_view_outfitter_cache")

cvars.AddChangeCallback("pm_supp_ikfoot", function()
    local ply = LocalPlayer()

    if IsValid(ply) then
        ply.pmavIKFootNaturalFrame = nil
        ply.pmavIKFootCompatFrame = nil
        ply.pmavIKFootCompatThinkTime = nil
        ply.pmavIKFootForcedFrame = nil
        ply.pmavIKFootForcedReason = nil
        ply.pmavPinLastOriginZ = nil
        ply.pmavPinStairFreezeUntil = nil
    end
end, "pm_eblansky_adaptive_view_ikfoot_cache")

hook.Add("InitPostEntity", "pm_eblansky_adaptive_view_sync", function()
    RunConsoleCommand("pmav_set_enabled", cvEnabled:GetBool() and "1" or "0")
    timer.Simple(0.25, SyncSettingsSoon)
    timer.Simple(1, SyncSettingsSoon)
end)

hook.Add("OutfitApply", "pm_eblansky_adaptive_view_outfitter_sync", function(ply, modelPath)
    if ply ~= LocalPlayer() or not IsValid(ply) then
        return
    end

    if not cvSupportOutfitter:GetBool() then
        return
    end

    local model = NormalizeModel(modelPath or GetAdaptiveLookupModel(ply))

    if model ~= "" then
        AV.ReferenceHeights = AV.ReferenceHeights or {}
        AV.ReferenceHeights[model] = nil
    end

    AV.LastSyncedState = nil
    AV.LastPredictedStand = nil
    AV.LastPredictedDuck = nil
    ply.pmavPinModel = nil
    ply.pmavPinBaseHeadHeight = nil
    ply.pmavPinTargetHeadDelta = nil
    ply.pmavPinSmoothedHeadDelta = nil
    ply.pmavPinLastOriginZ = nil
    ply.pmavPinStairFreezeUntil = nil
    ply.pmavPinLiveStandHeight = nil
    ply.pmavPinLiveDuckHeight = nil

    timer.Simple(0.1, SyncSettingsSoon)
    timer.Simple(0.75, SyncSettingsSoon)
end)

timer.Create("pm_eblansky_adaptive_view_model_watch", 0.5, 0, function()
    local ply = LocalPlayer()

    if not IsValid(ply) then
        return
    end

    local model = GetAdaptiveLookupModel(ply)
    local alive = ply:Alive()

    if AV.LastAliveState ~= nil and AV.LastAliveState ~= alive then
        AV.LastPredictedStand = nil
        AV.LastPredictedDuck = nil
    end

    AV.LastAliveState = alive

    local scale = math.Round(GetLocalAdaptiveModelScale(ply), 3)
    local skin = isfunction(ply.GetSkin) and tostring(ply:GetSkin() or 0) or "0"
    local bodygroups = GetEntityBodygroupSignature(ply)
    local bounds = GetEntityBoundsSignature(ply)
    local state = model .. "|" .. tostring(alive) .. "|" .. tostring(scale) .. "|" .. skin .. "|" .. bodygroups .. "|" .. bounds

    if AV.LastSyncedState == state then
        return
    end

    if AV.LastSyncedModel ~= model or AV.LastSyncedBounds ~= bounds or AV.LastSyncedBodygroups ~= bodygroups or AV.LastSyncedSkin ~= skin then
        AV.ReferenceHeights = AV.ReferenceHeights or {}
        AV.ReferenceHeights[model] = nil
        AV.LastPredictedStand = nil
        AV.LastPredictedDuck = nil
        ply.pmavPinModel = nil
        ply.pmavPinBaseHeadHeight = nil
        ply.pmavPinTargetHeadDelta = nil
        ply.pmavPinSmoothedHeadDelta = nil
        ply.pmavPinLastOriginZ = nil
        ply.pmavPinLiveStandHeight = nil
        ply.pmavPinLiveDuckHeight = nil
    end

    AV.LastSyncedState = state
    AV.LastSyncedModel = model
    AV.LastSyncedBounds = bounds
    AV.LastSyncedBodygroups = bodygroups
    AV.LastSyncedSkin = skin

    if cvEnabled:GetBool() then
        timer.Simple(0, SyncSettingsSoon)
        timer.Simple(0.25, SyncSettingsSoon)
    else
        RunConsoleCommand("pmav_set_enabled", "0")
    end
end)

hook.Remove("Think", "pm_eblansky_adaptive_view_prediction")

net.Receive("pmav_bounds", function()
    local ent = net.ReadEntity()
    local mins = net.ReadVector()
    local maxs = net.ReadVector()
    local hasDuck = net.ReadBool()
    local duckMins
    local duckMaxs

    if hasDuck then
        duckMins = net.ReadVector()
        duckMaxs = net.ReadVector()
    end

    if IsValid(ent) then
        AV.ServerBounds[ent] = {
            mins = mins,
            maxs = maxs,
            duckMins = duckMins,
            duckMaxs = duckMaxs,
            time = CurTime()
        }
    end
end)

local function ShouldDrawDebugBounds(ent)
    if not IsValid(ent) or ent:IsWeapon() then
        return false
    end

    local class = string.lower(ent:GetClass() or "")

    if string.find(class, "prop_", 1, true) or string.find(class, "ragdoll", 1, true) then
        return false
    end

    if ent:IsPlayer() or ent:IsNPC() then
        if cvCollisionOnlyPlayers:GetBool() and not ent:IsPlayer() then
            return false
        end

        return true
    end

    if isfunction(ent.IsNextBot) and ent:IsNextBot() then
        if cvCollisionOnlyPlayers:GetBool() then
            return false
        end

        return true
    end

    if cvCollisionOnlyPlayers:GetBool() then
        return false
    end

    return ClassLooksAdaptive(class)
end

local function DrawDebugBounds()
    if not cvEnabled:GetBool() or not cvDebugBounds:GetBool() or not CanUseDebugBounds() then
        return
    end

    render.SetColorMaterial()

    for _, ent in ipairs(ents.GetAll()) do
        if ShouldDrawDebugBounds(ent) then
            local mins, maxs

            local serverBounds = AV.ServerBounds[ent]

            if serverBounds then
                if ent:IsPlayer() and ent:Crouching() and serverBounds.duckMins and serverBounds.duckMaxs then
                    mins = serverBounds.duckMins
                    maxs = serverBounds.duckMaxs
                else
                    mins = serverBounds.mins
                    maxs = serverBounds.maxs
                end

            elseif ent:IsPlayer() and isfunction(ent.GetHull) then
                if ent:Crouching() and isfunction(ent.GetHullDuck) then
                    mins, maxs = ent:GetHullDuck()
                else
                    mins, maxs = ent:GetHull()
                end
            else
                mins, maxs = nil, nil
            end

            if mins and maxs then
                local color = Color(80, 220, 255, 255)

                if ent:IsNPC() or isfunction(ent.IsNextBot) and ent:IsNextBot() or ClassLooksAdaptive(ent:GetClass()) then
                    color = Color(255, 180, 80, 255)
                elseif ent:IsPlayer() and ent:IsBot() then
                    color = Color(180, 120, 255, 255)
                end

                render.DrawWireframeBox(ent:GetPos(), Angle(0, 0, 0), mins, maxs, color, true)
            end
        end
    end
end

hook.Add("PostDrawTranslucentRenderables", "pm_eblansky_adaptive_view_debug_bounds", DrawDebugBounds)

timer.Simple(0.1, SyncSettingsSoon)
timer.Simple(1, SyncSettingsSoon)
timer.Simple(0.2, function()
    if AV.InitialEnabledCommandSent then
        return
    end

    AV.InitialEnabledCommandSent = true
    RunConsoleCommand("pmav_set_enabled", cvEnabled:GetBool() and "1" or "0")
end)
