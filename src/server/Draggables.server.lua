-- Physics-based draggable items.
--
-- HOW TO SET UP AN ITEM IN STUDIO:
--   1. Make a Part or Model. Leave it UNANCHORED (Anchored = false) —
--      physics dragging needs the object free to move.
--   2. Add the tag "Draggable" to it (Properties > Tags, or the Tag Editor).
--   That's it. Players can grab it and drag it around (works in first person
--   too: aim the crosshair at it, click-hold, and steer with the camera).
--   Items collide with the world and with players while being carried.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tags = require(ReplicatedStorage:WaitForChild("Tags"))

-- Returns every physical piece of the item (a lone Part, or all parts
-- inside a Model), so we can adjust collision and ownership on each.
local function getParts(item)
	if item:IsA("BasePart") then
		return { item }
	end
	local parts = {}
	for _, child in ipairs(item:GetDescendants()) do
		if child:IsA("BasePart") then
			table.insert(parts, child)
		end
	end
	return parts
end

local function setupDraggable(item)
	-- Make sure every piece actually collides with the world and players.
	for _, part in ipairs(getParts(item)) do
		part.CanCollide = true
	end

	-- Skip if it already has a DragDetector (e.g. added by hand in Studio).
	if item:FindFirstChildOfClass("DragDetector") then
		return
	end

	-- DragDetector is Roblox's built-in dragging object: it handles mouse,
	-- touch, and gamepad input for us. We just configure how it behaves.
	local dragDetector = Instance.new("DragDetector")

	-- Physical = the object is pulled by real physics forces, so it has
	-- weight, collides with walls and players, and can knock things over.
	dragDetector.ResponseStyle = Enum.DragDetectorResponseStyle.Physical

	-- TranslateViewPlane = it moves in the plane facing the camera. In first
	-- person this means the object follows your crosshair as you look around.
	dragDetector.DragStyle = Enum.DragDetectorDragStyle.TranslateViewPlane

	-- Pull from the object's middle instead of the exact spot you clicked.
	-- Without this, grabbing a corner makes the object spin and wobble.
	dragDetector.ApplyAtCenterOfMass = true

	-- How hard the object is pulled toward your cursor. Higher = it keeps up
	-- with your mouse more tightly instead of lagging behind on a stretchy
	-- rubber band. (Default is 10; try 15-40 to taste.)
	dragDetector.Responsiveness = 25

	-- How far away (in studs) a player can be and still grab it.
	dragDetector.MaxActivationDistance = 30

	dragDetector.Parent = item

	-- SMOOTHNESS: normally the server simulates this object's physics, so
	-- every drag movement takes a round trip to the server and back — that's
	-- the laggy, floaty feel. While a player drags, we hand physics control
	-- ("network ownership") of the object to that player's machine so it
	-- responds instantly, then give it back when they let go.
	dragDetector.DragStart:Connect(function(player)
		for _, part in ipairs(getParts(item)) do
			if not part.Anchored then
				part:SetNetworkOwner(player)
			end
		end
	end)

	dragDetector.DragEnd:Connect(function()
		for _, part in ipairs(getParts(item)) do
			if not part.Anchored then
				part:SetNetworkOwnershipAuto()
			end
		end
	end)
end

-- Wire up everything already tagged, plus anything tagged later.
for _, item in ipairs(CollectionService:GetTagged(Tags.Draggable)) do
	setupDraggable(item)
end
CollectionService:GetInstanceAddedSignal(Tags.Draggable):Connect(setupDraggable)
