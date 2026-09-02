-- Client side of the Lumber Tycoon 2 style carry system.
--
-- WHAT IT DOES:
--   Click and HOLD a tagged item to carry it. The item floats toward a point
--   in front of your camera (your crosshair in first person, your mouse
--   cursor in third person) on a springy invisible leash, while you keep
--   full control of your camera and movement. Release the button to drop it.
--
-- HOW: when you grab something, we create an AlignPosition — a physics
-- constraint that constantly pulls the item toward a target point. Every
-- frame we move that target to sit in front of wherever you're looking.
-- Because it's a physics pull (not teleporting), the item swings naturally,
-- collides with walls and players, and drops realistically when released.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tags = require(ReplicatedStorage:WaitForChild("Tags"))
local remotes = ReplicatedStorage:WaitForChild("DragRemotes")
local startDragRemote = remotes:WaitForChild("StartDrag")
local stopDragRemote = remotes:WaitForChild("StopDrag")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Tuning knobs -----------------------------------------------------
local MAX_GRAB_DISTANCE = 30 -- how far away you can grab from (studs)
local MIN_HOLD_DISTANCE = 6 -- carried items never come closer than this
local MAX_HOLD_DISTANCE = 14 -- ...or float farther out than this
local PULL_STRENGTH = 35 -- higher = tighter leash, lower = floatier swing
---------------------------------------------------------------------

-- Everything about the item we're currently holding (nil = holding nothing).
local held = nil

-- Walks up from the exact part you clicked (e.g. the lid of a pot Model)
-- to find the tagged thing it belongs to.
local function findDraggable(instance)
	local current = instance
	while current and current ~= workspace do
		if CollectionService:HasTag(current, Tags.Draggable) then
			return current
		end
		current = current.Parent
	end
	return nil
end

-- The part the leash attaches to: the item itself, or a Model's main part.
local function getMainPart(item)
	if item:IsA("BasePart") then
		return item
	end
	if item:IsA("Model") then
		return item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

-- A ray from the camera through the mouse/crosshair position.
local function getAimRay()
	local mousePosition = UserInputService:GetMouseLocation()
	return camera:ViewportPointToRay(mousePosition.X, mousePosition.Y)
end

local function drop()
	if not held then
		return
	end

	held.alignPosition:Destroy()
	held.attachment:Destroy()
	held.updateConnection:Disconnect()
	held = nil

	stopDragRemote:FireServer()
end

local function grab(item, grabDistance)
	local mainPart = getMainPart(item)
	if not mainPart then
		return
	end

	-- Tell the server we're picking this up (it double-checks and then
	-- lets our machine simulate the item's physics for a lag-free carry).
	startDragRemote:FireServer(item)

	-- The attachment is the "hook" on the item the leash pulls on.
	local attachment = Instance.new("Attachment")
	attachment.Name = "CarryAttachment"
	attachment.Parent = mainPart

	-- The AlignPosition is the leash: it pulls the hook toward .Position.
	local alignPosition = Instance.new("AlignPosition")
	alignPosition.Name = "CarryForce"
	alignPosition.Mode = Enum.PositionAlignmentMode.OneAttachment
	alignPosition.Attachment0 = attachment
	alignPosition.ApplyAtCenterOfMass = true -- no wild spinning
	alignPosition.MaxForce = math.huge
	alignPosition.Responsiveness = PULL_STRENGTH
	alignPosition.Parent = mainPart

	-- Carry it at roughly the distance you grabbed it from, within limits.
	local holdDistance = math.clamp(grabDistance, MIN_HOLD_DISTANCE, MAX_HOLD_DISTANCE)

	-- Every frame, move the leash's target to a point in front of the camera.
	local updateConnection = RunService.RenderStepped:Connect(function()
		if not item.Parent or not mainPart.Parent then
			drop() -- the item was destroyed while we held it
			return
		end
		local aimRay = getAimRay()
		alignPosition.Position = aimRay.Origin + aimRay.Direction * holdDistance
	end)

	held = {
		item = item,
		attachment = attachment,
		alignPosition = alignPosition,
		updateConnection = updateConnection,
	}
end

local function tryGrabAtCursor()
	local aimRay = getAimRay()

	-- Fire a ray into the world to see what's under the cursor/crosshair,
	-- ignoring our own character so we can't grab ourselves.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }

	local result = workspace:Raycast(aimRay.Origin, aimRay.Direction * MAX_GRAB_DISTANCE, params)
	if not result then
		return
	end

	local item = findDraggable(result.Instance)
	if item then
		grab(item, result.Distance)
	end
end

-- Press = try to grab, release = drop. Works for mouse and touch.
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return -- the click was on a menu/button, not the world
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		tryGrabAtCursor()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		drop()
	end
end)
