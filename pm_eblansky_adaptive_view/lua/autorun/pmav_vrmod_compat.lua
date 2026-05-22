if SERVER then
	AddCSLuaFile()
end

local AV = _G.PM_EBLANSKY_ADAPTIVE_VIEW or {}
_G.PM_EBLANSKY_ADAPTIVE_VIEW = AV

local VR_HALF_WIDTH = 10
local VR_MINS = Vector(-VR_HALF_WIDTH, -VR_HALF_WIDTH, 0)
local DEF_MINS = Vector(-16, -16, 0)
local DEF_MAXS = Vector(16, 16, 72)
local DEF_DUCK_MAXS = Vector(16, 16, 36)
local CV_FLAGS = bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED)

local function CreateCompatConVar(name, default, flags, help, min, max)
	if GetConVar(name) then return GetConVar(name) end
	return CreateConVar(name, default, flags, help, min, max)
end

local cvEnabled = CreateCompatConVar("pmav_vr_enabled", "1", CV_FLAGS, "Enable Adaptive View VRMod compatibility.", 0, 1)
local cvHull = CreateCompatConVar("pmav_vr_hull", "1", CV_FLAGS, "Adapt VRMod player hull height from the player model.", 0, 1)
local cvCamera = CreateCompatConVar("pmav_vr_camera", "1", CV_FLAGS, "Clamp VRMod HMD camera height to the adaptive model-safe zone.", 0, 1)
local cvMin = CreateCompatConVar("pmav_vr_hull_min", "24", CV_FLAGS, "Minimum Adaptive View VR hull height.", 12, 120)
local cvMax = CreateCompatConVar("pmav_vr_hull_max", "120", CV_FLAGS, "Maximum Adaptive View VR hull height.", 24, 180)
local cvDuckRatio = CreateCompatConVar("pmav_vr_duck_ratio", "0.5", CV_FLAGS, "Adaptive View VR duck hull ratio.", 0.25, 0.9)
local cvEyeScale = CreateCompatConVar("pmav_vr_eye_scale", "0.92", CV_FLAGS, "Model height fraction used as automatic VR character eye height.", 0.5, 1.2)
local cvTopMargin = CreateCompatConVar("pmav_vr_camera_top_margin", "2", CV_FLAGS, "Extra space below adaptive hull top for VR camera clamp.", 0, 16)
local cvBottomRatio = CreateCompatConVar("pmav_vr_camera_bottom_ratio", "0.18", CV_FLAGS, "Lowest safe VR camera fraction of adaptive hull height.", 0, 0.75)

local function AddonEnabled()
	local main = GetConVar("pmav_enabled")
	return cvEnabled:GetBool() and (not main or main:GetBool())
end

local function NumberOr(value, fallback)
	value = tonumber(value)
	if value == nil then return fallback end
	return value
end

local function IsPlayerInVR(ply)
	if not IsValid(ply) then return false end
	if vrmod and isfunction(vrmod.IsPlayerInVR) then return vrmod.IsPlayerInVR(ply) == true end
	return ply.IsInVR and ply:IsInVR() or false
end

local function GetModelCollisionHeight(ply)
	if not IsValid(ply) then return DEF_MAXS.z end

	local mins, maxs = ply:GetModelBounds()
	if not mins or not maxs then return DEF_MAXS.z end

	local floorZ = math.min(NumberOr(mins.z, 0), 0)
	local topZ = NumberOr(maxs.z, DEF_MAXS.z)
	local height = topZ - floorZ

	if height <= 0 or height ~= height then
		return DEF_MAXS.z
	end

	return height
end

local function GetAdaptiveHull(ply)
	local minHeight = math.max(cvMin:GetFloat(), 12)
	local maxHeight = math.max(cvMax:GetFloat(), minHeight)
	local standHeight = math.Clamp(GetModelCollisionHeight(ply), minHeight, maxHeight)
	local duckRatio = math.Clamp(cvDuckRatio:GetFloat(), 0.25, 0.9)
	local duckHeight = math.Clamp(standHeight * duckRatio, 12, math.min(standHeight, 96))

	return Vector(VR_HALF_WIDTH, VR_HALF_WIDTH, standHeight), Vector(VR_HALF_WIDTH, VR_HALF_WIDTH, duckHeight)
end

local function ApplyAdaptiveEyeHeight(ply)
	if not CLIENT or not AddonEnabled() or not cvHull:GetBool() then return end

	local hullMaxs = GetAdaptiveHull(ply)
	local eyeHeight = math.Clamp(hullMaxs.z * math.Clamp(cvEyeScale:GetFloat(), 0.5, 1.2), 30, 100)
	local convar = GetConVar("vrmod_charactereyeheight")

	if convar and math.abs(convar:GetFloat() - eyeHeight) > 0.05 then
		RunConsoleCommand("vrmod_charactereyeheight", tostring(math.Round(eyeHeight, 1)))
	end
end

local function ApplyVRHull(ply)
	if not AddonEnabled() or not cvHull:GetBool() or not IsPlayerInVR(ply) then return end

	local maxs, duckMaxs = GetAdaptiveHull(ply)
	ply:SetHull(VR_MINS, maxs)
	ply:SetHullDuck(VR_MINS, duckMaxs)
	ApplyAdaptiveEyeHeight(ply)
end

local function RestoreVRHull(ply)
	if not IsValid(ply) then return end
	ply:SetHull(DEF_MINS, DEF_MAXS)
	ply:SetHullDuck(DEF_MINS, DEF_DUCK_MAXS)
end

local function ApplyVRHullDelayed(ply)
	if not IsValid(ply) then return end

	timer.Simple(0, function()
		ApplyVRHull(ply)
	end)

	timer.Simple(0.25, function()
		ApplyVRHull(ply)
	end)
end

hook.Add("VRMod_Start", "pmav_vrmod_hull", ApplyVRHullDelayed)
hook.Add("VRMod_Exit", "pmav_vrmod_hull", RestoreVRHull)

hook.Add("PlayerSpawn", "pmav_vrmod_hull", function(ply)
	ApplyVRHullDelayed(ply)
end)

hook.Add("PlayerSetModel", "pmav_vrmod_hull", function(ply)
	ApplyVRHullDelayed(ply)
end)

local function ReapplyAllVRHulls()
	for _, ply in ipairs(player.GetAll()) do
		ApplyVRHull(ply)
	end
end

cvars.AddChangeCallback("pmav_vr_enabled", ReapplyAllVRHulls, "pmav_vrmod")
cvars.AddChangeCallback("pmav_vr_hull", ReapplyAllVRHulls, "pmav_vrmod")
cvars.AddChangeCallback("pmav_vr_hull_min", ReapplyAllVRHulls, "pmav_vrmod")
cvars.AddChangeCallback("pmav_vr_hull_max", ReapplyAllVRHulls, "pmav_vrmod")
cvars.AddChangeCallback("pmav_vr_duck_ratio", ReapplyAllVRHulls, "pmav_vrmod")
cvars.AddChangeCallback("pmav_vr_eye_scale", ReapplyAllVRHulls, "pmav_vrmod")

if CLIENT then
	local TRACKED_POSES = {
		"hmd",
		"pose_lefthand",
		"pose_righthand",
		"pose_waist",
		"pose_leftfoot",
		"pose_rightfoot"
	}

	local function ShiftTrackingZ(delta)
		if not g_VR or not g_VR.origin or not g_VR.tracking or math.abs(delta) <= 0.001 then return end

		g_VR.origin.z = g_VR.origin.z + delta

		for _, poseName in ipairs(TRACKED_POSES) do
			local pose = g_VR.tracking[poseName]
			if pose and pose.pos then
				pose.pos.z = pose.pos.z + delta
			end
		end
	end

	local function ClampAdaptiveCameraZ(ply)
		if not AddonEnabled() or not cvHull:GetBool() or not cvCamera:GetBool() then return end
		if not g_VR or not g_VR.tracking or not g_VR.tracking.hmd or not g_VR.origin then return end

		local hullMaxs = GetAdaptiveHull(ply)
		local feetZ = ply:GetPos().z
		local topMargin = math.Clamp(cvTopMargin:GetFloat(), 0, 16)
		local bottomRatio = math.Clamp(cvBottomRatio:GetFloat(), 0, 0.75)
		local minZ = feetZ + math.max(hullMaxs.z * bottomRatio, 4)
		local maxZ = feetZ + math.max(hullMaxs.z - topMargin, minZ + 1)
		local hmdZ = g_VR.tracking.hmd.pos.z

		if hmdZ > maxZ then
			ShiftTrackingZ(maxZ - hmdZ)
		elseif hmdZ < minZ then
			ShiftTrackingZ(minZ - hmdZ)
		end
	end

	local function InitFallbackInputDefaults()
		g_VR = g_VR or {}
		g_VR.input = g_VR.input or {}

		local defaults = {
			boolean_primaryfire = false,
			boolean_secondaryfire = false,
			boolean_left_pickup = false,
			boolean_right_pickup = false,
			boolean_jump = false,
			boolean_crouch = false,
			boolean_spawnmenu = false,
			boolean_use = false,
			boolean_reload = false,
			boolean_undo = false,
			boolean_chat = false,
			boolean_changeweapon = false,
			boolean_teleport = false,
			boolean_sprint = false,
			boolean_flashlight = false,
			boolean_menucontext = false,
			lweaponmenu = false,
			vector1_primaryfire = 0,
			vector1_secondaryfire = 0,
			vector1_left_squeeze = 0,
			vector1_right_squeeze = 0,
			vector1_forward = 0,
			vector1_reverse = 0,
			vector2_walkdirection = {x = 0, y = 0},
			vector2_smoothturn = {x = 0, y = 0},
			vector2_steer = {x = 0, y = 0},
			analog_left = {x = 0, y = 0},
			analog_right = {x = 0, y = 0}
		}

		for key, value in pairs(defaults) do
			if g_VR.input[key] == nil then
				g_VR.input[key] = istable(value) and table.Copy(value) or value
			end
		end

		g_VR.input.skeleton_lefthand = g_VR.input.skeleton_lefthand or {fingerCurls = {0, 0, 0, 0, 0}}
		g_VR.input.skeleton_righthand = g_VR.input.skeleton_righthand or {fingerCurls = {0, 0, 0, 0, 0}}
	end

	local function InstallVRModuleShims()
		if not VRMOD_UpdatePosesAndActions then
			VRMOD_UpdatePosesAndActions = function()
				return true
			end
		end

		if not VRMOD_GetPoses then
			VRMOD_GetPoses = function()
				return {}
			end
		end

		if not VRMOD_GetActions then
			VRMOD_GetActions = function()
				InitFallbackInputDefaults()
				return g_VR.input, {}
			end
		end

		if not VRMOD_DoRenderLoop then
			VRMOD_DoRenderLoop = function()
				if isfunction(VRUtilClientRender) then
					local ok, err = pcall(VRUtilClientRender)
					if not ok then
						ErrorNoHalt("[Adaptive View] VRUtilClientRender fallback failed: " .. tostring(err) .. "\n")
					end
				end

				return true
			end
		end
	end

	local function WrapVRModSetupXRActions()
		if not vrmod or not isfunction(vrmod.SetupXRActions) then return end
		if vrmod.pmavSetupXRActionsWrapper == vrmod.SetupXRActions then return end

		local original = vrmod.SetupXRActions
		vrmod.pmavSetupXRActionsOriginal = original

		function vrmod.SetupXRActions(...)
			if not (VRMOD_CreateActionSet and VRMOD_SuggestBindings and VRMOD_SetActiveActionSets and VRMOD_AttachActionSets) then
				InitFallbackInputDefaults()

				if vrmod.logger and vrmod.logger.Warn then
					vrmod.logger.Warn("Adaptive View: OpenXR action API is unavailable; using VRMod fallback input defaults.")
				else
					print("[Adaptive View] OpenXR action API is unavailable; using VRMod fallback input defaults.")
				end

				return false
			end

			return original(...)
		end

		vrmod.pmavSetupXRActionsWrapper = vrmod.SetupXRActions
	end

	concommand.Add("pmav_vr_install_shims", InstallVRModuleShims)
	concommand.Add("pmav_vr_wrap_now", WrapVRModSetupXRActions)
	timer.Create("pmav_vrmod_wrap_actions", 0.25, 0, function()
		InstallVRModuleShims()
		WrapVRModSetupXRActions()
	end)
	hook.Add("Initialize", "pmav_vrmod_wrap_actions", function()
		InstallVRModuleShims()
		WrapVRModSetupXRActions()
	end)
	hook.Add("InitPostEntity", "pmav_vrmod_wrap_actions", function()
		InstallVRModuleShims()
		WrapVRModSetupXRActions()
	end)

	hook.Add("VRMod_Tracking", "pmav_vrmod_camera_clamp", function()
		local ply = LocalPlayer()
		if not IsValid(ply) then return end

		ClampAdaptiveCameraZ(ply)
		ApplyAdaptiveEyeHeight(ply)
	end)
end
