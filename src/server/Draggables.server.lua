-- Physics-based draggable items.
--
-- HOW TO SET UP AN ITEM IN STUDIO:
--   1. Make a Part or Model. Leave it UNANCHORED (Anchored = false) —
--      physics dragging needs the object free to move.
--   2. Add the tag "Draggable" to it (Properties > Tags, or the Tag Editor).
--   That's it. Players can now grab it and drag it around, and it will
--   swing, collide, and fall realistically.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tags = require(ReplicatedStorage:WaitForChild("Tags"))

local function setupDraggable(item)
	-- Skip if it already has one (e.g. you added it by hand in Studio).
	if item:FindFirstChildOfClass("DragDetector") then
		return
	end

	-- DragDetector is Roblox's built-in dragging object: it handles mouse,
	-- touch, and gamepad input for us. We just configure how it behaves.
	local dragDetector = Instance.new("DragDetector")

	-- Physical = the object is pulled by real physics forces, so it has
	-- weight, collides with walls, and can knock other things over.
	dragDetector.ResponseStyle = Enum.DragDetectorResponseStyle.Physical

	-- TranslateViewPlane = it moves in the plane facing the camera,
	-- which feels like carrying it in front of you.
	dragDetector.DragStyle = Enum.DragDetectorDragStyle.TranslateViewPlane

	-- How far away (in studs) a player can be and still grab it.
	dragDetector.MaxActivationDistance = 30

	dragDetector.Parent = item
end

-- Wire up everything already tagged, plus anything tagged later.
for _, item in ipairs(CollectionService:GetTagged(Tags.Draggable)) do
	setupDraggable(item)
end
CollectionService:GetInstanceAddedSignal(Tags.Draggable):Connect(setupDraggable)
