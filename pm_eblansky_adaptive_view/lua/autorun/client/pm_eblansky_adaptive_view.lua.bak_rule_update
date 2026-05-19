if SERVER then return end

PM_EBLANSKY_ADAPTIVE_VIEW = PM_EBLANSKY_ADAPTIVE_VIEW or {}

local AV = PM_EBLANSKY_ADAPTIVE_VIEW
local DATA_FILE = "pm_eblansky_adaptive_view/models.json"

local cvEnabled = CreateClientConVar("pmav_enabled", "1", true, false, "Enable adaptive camera height.")
local cvAutoScale = CreateClientConVar("pmav_auto_scale", "0.92", true, false, "Part of model height used as eye height.")
local cvGlobalOffset = CreateClientConVar("pmav_global_offset", "0", true, false, "Global camera height offset.")
local cvSmooth = CreateClientConVar("pmav_smooth", "10", true, false, "Hidden option-switch smoothing speed.")
local cvMinHeight = CreateClientConVar("pmav_min_height", "4", true, false, "Minimum standing camera height.")
local cvMaxHeight = CreateClientConVar("pmav_max_height", "120", true, false, "Maximum standing camera height.")
local cvCollision = CreateClientConVar("pmav_collision", "1", true, false, "Resize player collision hull with adaptive height.")
local cvCollisionMode = CreateClientConVar("pmav_collision_mode", "3", true, false, "Adaptive collision mode: 0 none, 1 height, 2 width/length, 3 all.")
local cvCollisionRadius = CreateClientConVar("pmav_collision_radius", "16", true, false, "Adaptive player collision hull half-width.")
local cvCollisionOnlyPlayers = CreateClientConVar("pmav_collision_only_players", "0", true, false, "Apply Adaptive View collision only to players.")
local cvNpcCollision = CreateClientConVar("pmav_npc_collision", "1", true, false, "Apply Adaptive View collision to NPCs and NextBots.")
local cvMultiplayerSafe = CreateClientConVar("pmav_multiplayer_safe", "1", true, false, "Avoid shrinking player width/length in multiplayer.")
local cvDebugBounds = CreateClientConVar("pmav_debug_bounds", "0", true, false, "Draw Adaptive View debug collision bounds.")

AV.ModelRules = AV.ModelRules or {}
AV.SmoothedOffset = AV.SmoothedOffset or 0
AV.LastViewOffset = AV.LastViewOffset or vector_origin
AV.ServerBounds = {}

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

        if model ~= "" and istable(rule) then
            local mode = tostring(rule.mode or "auto")

            if mode == "auto" or mode == "height" or mode == "off" then
                AV.ModelRules[model] = {
                    mode = mode,
                    height = NumberOr(rule.height, 64),
                    offset = NumberOr(rule.offset, 0)
                }
            end
        end
    end
end

local function WriteRules()
    file.CreateDir("pm_eblansky_adaptive_view")
    file.Write(DATA_FILE, util.TableToJSON(AV.ModelRules, true))
end

ReadRules()

function AV.GetRule(model)
    return AV.ModelRules[NormalizeModel(model)]
end

function AV.SetRule(model, mode, height, offset)
    model = NormalizeModel(model)

    if model == "" then
        return
    end

    if mode == nil then
        AV.ModelRules[model] = nil
    else
        AV.ModelRules[model] = {
            mode = mode,
            height = NumberOr(height, 64),
            offset = NumberOr(offset, 0)
        }
    end

    WriteRules()

    if isfunction(AV.SyncSettingsToServer) then
        AV.SyncSettingsToServer()
    end
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
    local modelHeight, followsPose = GetReferenceModelHeight(ply:GetModel())

    if not modelHeight or modelHeight <= 0 then
        if isfunction(ply.SetupBones) then
            ply:SetupBones()
        end

        modelHeight, followsPose = GetModelHeightFromEntity(ply)
    end

    local minHeight = cvMinHeight:GetFloat()
    local maxHeight = math.max(cvMaxHeight:GetFloat(), minHeight)

    return math.Clamp(modelHeight, minHeight, maxHeight), followsPose
end

function AV.GetLocalAutoHeight()
    local ply = LocalPlayer()

    if not IsValid(ply) then
        return 0
    end

    return GetModelAutoHeight(ply)
end

local function GetTargetHeight(ply, duckAmount)
    local rule = AV.GetRule(ply:GetModel())

    if rule and rule.mode == "off" then
        return nil
    end

    local standingHeight
    local followsPose = false

    if rule and rule.mode == "height" then
        standingHeight = rule.height
    else
        standingHeight, followsPose = GetModelAutoHeight(ply)
    end

    standingHeight = standingHeight + cvGlobalOffset:GetFloat() + (rule and rule.offset or 0)

    if followsPose then
        return standingHeight
    end

    local baseStand = ply:GetViewOffset().z
    local baseDuck = ply:GetViewOffsetDucked().z
    local duckRatio = baseStand ~= 0 and baseDuck / baseStand or 0.4375
    local duckHeight = math.max(standingHeight * duckRatio, 18)

    return Lerp(duckAmount, standingHeight, duckHeight)
end

local function ResetSettingsExceptRules()
    RunConsoleCommand("pmav_enabled", "1")
    RunConsoleCommand("pmav_auto_scale", "0.92")
    RunConsoleCommand("pmav_global_offset", "0")
    RunConsoleCommand("pmav_smooth", "10")
    RunConsoleCommand("pmav_min_height", "4")
    RunConsoleCommand("pmav_max_height", "120")
    RunConsoleCommand("pmav_collision", "1")
    RunConsoleCommand("pmav_collision_mode", "3")
    RunConsoleCommand("pmav_collision_radius", "16")
    RunConsoleCommand("pmav_collision_only_players", "0")
    RunConsoleCommand("pmav_npc_collision", "1")
    RunConsoleCommand("pmav_multiplayer_safe", "1")
    RunConsoleCommand("pmav_debug_bounds", "0")
    AV.SmoothedOffset = 0
    AV.LastViewOffset = vector_origin

    if isfunction(AV.SyncSettingsToServer) then
        timer.Simple(0, AV.SyncSettingsToServer)
    end
end

local function FillRulesList(list)
    list:Clear()

    for model, rule in SortedPairs(AV.ModelRules) do
        local height = rule.mode == "height" and tostring(math.Round(rule.height, 2)) or "-"
        list:AddLine(model, rule.mode, height, tostring(math.Round(rule.offset or 0, 2)))
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

    local rule = table.Copy(AV.GetRule(oldModel) or {
        mode = "auto",
        height = 64,
        offset = 0
    })

    local frame = vgui.Create("DFrame")
    frame:SetTitle("Edit model rule")
    frame:SetSize(420, 260)
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
    heightSlider:SetText("Exact standing height")
    heightSlider:SetMinMax(20, 120)
    heightSlider:SetDecimals(0)
    heightSlider:SetValue(rule.height or 64)

    local offsetSlider = vgui.Create("DNumSlider", frame)
    offsetSlider:Dock(TOP)
    offsetSlider:DockMargin(8, 0, 8, 0)
    offsetSlider:SetText("Model offset")
    offsetSlider:SetMinMax(-32, 32)
    offsetSlider:SetDecimals(1)
    offsetSlider:SetValue(rule.offset or 0)

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

        AV.SetRule(newModel, mode, heightSlider:GetValue(), offsetSlider:GetValue())

        if isfunction(onSaved) then
            onSaved(newModel, mode, heightSlider:GetValue(), offsetSlider:GetValue())
        end

        frame:Close()
    end
end

local function AddAdaptiveViewMenu()
    spawnmenu.AddToolMenuOption("Options", "Player", "pm_eblansky_adaptive_view", "Adaptive View", "", "", function(panel)
        panel:ClearControls()
        panel:CheckBox("Enable adaptive camera", "pmav_enabled")
        panel:CheckBox("Adapt collision", "pmav_collision")
        panel:CheckBox("Adapt NPC/NextBot collision (experimental)", "pmav_npc_collision")
        panel:CheckBox("Collision only players", "pmav_collision_only_players")
        panel:CheckBox("Draw debug bounds", "pmav_debug_bounds")

        local collisionMode = vgui.Create("DComboBox")
        collisionMode:AddChoice("Nothing", "0")
        collisionMode:AddChoice("Height only", "1")
        collisionMode:AddChoice("Width/length only", "2")
        collisionMode:AddChoice("Height + width/length", "3")
        collisionMode:ChooseOptionID(math.Clamp(cvCollisionMode:GetInt(), 0, 3) + 1)
        collisionMode.OnSelect = function(_, _, _, value)
            RunConsoleCommand("pmav_collision_mode", value)
        end
        panel:AddItem(collisionMode)

        panel:NumSlider("Auto height scale", "pmav_auto_scale", 0.7, 1.1, 2)
        panel:NumSlider("Global offset", "pmav_global_offset", -24, 24, 1)
        panel:NumSlider("Min auto height", "pmav_min_height", 0, 80, 0)
        panel:NumSlider("Max auto height", "pmav_max_height", 50, 160, 0)

        local resetButton = panel:Button("Reset settings, keep model rules")
        resetButton.DoClick = ResetSettingsExceptRules

        local modelEntry = vgui.Create("DTextEntry")
        modelEntry:SetPlaceholderText("models/player/group01/male_07.mdl")
        modelEntry:SetText(IsValid(LocalPlayer()) and LocalPlayer():GetModel() or "")
        panel:AddItem(modelEntry)

        local heightSlider = vgui.Create("DNumSlider")
        heightSlider:SetText("Exact standing height")
        heightSlider:SetMinMax(20, 120)
        heightSlider:SetDecimals(0)
        heightSlider:SetValue(64)
        panel:AddItem(heightSlider)

        local offsetSlider = vgui.Create("DNumSlider")
        offsetSlider:SetText("Model offset")
        offsetSlider:SetMinMax(-32, 32)
        offsetSlider:SetDecimals(1)
        offsetSlider:SetValue(0)
        panel:AddItem(offsetSlider)

        local modeBox = vgui.Create("DComboBox")
        modeBox:AddChoice("Auto height", "auto", true)
        modeBox:AddChoice("Exact height", "height")
        modeBox:AddChoice("Disable for this model", "off")
        panel:AddItem(modeBox)

        local list = vgui.Create("DListView")
        list:SetTall(180)
        list:AddColumn("Model")
        list:AddColumn("Mode")
        list:AddColumn("Height")
        list:AddColumn("Offset")
        panel:AddItem(list)

        local function getSelectedRule()
            local selected = list:GetSelectedLine()

            if not selected then
                return nil, nil
            end

            local row = list:GetLine(selected)
            local model = row and row:GetColumnText(1)

            return model, model and AV.GetRule(model)
        end

        local function saveRuleForModel(model)
            local selectedID = modeBox:GetSelectedID() or 1
            local mode = modeBox:GetOptionData(selectedID)
            AV.SetRule(model, mode or "auto", heightSlider:GetValue(), offsetSlider:GetValue())
            FillRulesList(list)
        end

        list.OnRowSelected = function(_, _, row)
            local model = row:GetColumnText(1)
            local rule = AV.GetRule(model)

            modelEntry:SetText(model)

            if rule then
                modeBox:ChooseOptionID(rule.mode == "height" and 2 or rule.mode == "off" and 3 or 1)
                heightSlider:SetValue(rule.height or 64)
                offsetSlider:SetValue(rule.offset or 0)
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
            OpenRuleEditor(row:GetColumnText(1), function(newModel, mode, height, offset)
                modelEntry:SetText(newModel)
                modeBox:ChooseOptionID(mode == "height" and 2 or mode == "off" and 3 or 1)
                heightSlider:SetValue(height or 64)
                offsetSlider:SetValue(offset or 0)
                FillRulesList(list)
            end)
        end

        local saveButton = panel:Button("Save model rule")
        saveButton.DoClick = function()
            saveRuleForModel(modelEntry:GetText())
        end

        local addButton = panel:Button("Add model from picker")
        addButton.DoClick = function()
            OpenModelPicker("Add model rule", modelEntry:GetText(), function(model)
                modelEntry:SetText(model)
                saveRuleForModel(model)
            end)
        end

        local currentButton = panel:Button("Use current model")
        currentButton.DoClick = function()
            if IsValid(LocalPlayer()) then
                modelEntry:SetText(LocalPlayer():GetModel())
            end
        end

        local removeButton = panel:Button("Remove selected model rule")
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
    if not isfunction(AV.SyncSettingsToServer) then
        return
    end

    timer.Create("pm_eblansky_adaptive_view_sync", 0.05, 1, AV.SyncSettingsToServer)
end

for _, convarName in ipairs({
    "pmav_enabled",
    "pmav_auto_scale",
    "pmav_global_offset",
    "pmav_smooth",
    "pmav_min_height",
    "pmav_max_height",
    "pmav_collision",
    "pmav_collision_mode",
    "pmav_collision_radius",
    "pmav_collision_only_players",
    "pmav_npc_collision",
    "pmav_multiplayer_safe"
}) do
    cvars.AddChangeCallback(convarName, SyncSettingsSoon, "pm_eblansky_adaptive_view")
end

cvars.AddChangeCallback("pmav_auto_scale", function()
    AV.ReferenceHeights = {}
end, "pm_eblansky_adaptive_view_cache")

hook.Add("InitPostEntity", "pm_eblansky_adaptive_view_sync", function()
    timer.Simple(0.25, SyncSettingsSoon)
    timer.Simple(1, SyncSettingsSoon)
end)

timer.Create("pm_eblansky_adaptive_view_model_watch", 0.5, 0, function()
    local ply = LocalPlayer()

    if not IsValid(ply) then
        return
    end

    local model = NormalizeModel(ply:GetModel())
    local alive = ply:Alive()

    if AV.LastAliveState ~= nil and AV.LastAliveState ~= alive then
        AV.LastPredictedStand = nil
        AV.LastPredictedDuck = nil
    end

    AV.LastAliveState = alive

    local state = model .. "|" .. tostring(alive)

    if AV.LastSyncedState == state then
        return
    end

    AV.LastSyncedState = state
    timer.Simple(0, SyncSettingsSoon)
    timer.Simple(0.25, SyncSettingsSoon)
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

    return string.find(class, "npc", 1, true) ~= nil or string.find(class, "nextbot", 1, true) ~= nil
end

local function DrawDebugBounds()
    if not cvDebugBounds:GetBool() then
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

                if ent:IsNPC() or isfunction(ent.IsNextBot) and ent:IsNextBot() then
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
