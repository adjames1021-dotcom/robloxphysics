-- Bakery drag-and-drop system.
--
-- HOW TO SET IT UP IN STUDIO:
--
--   Draggable items (ingredients, pots, pans):
--     1. Make a Part or Model for the item. Anchor it (Anchored = true).
--     2. Add the tag "Draggable" to it (Model tab > Tag Editor / Properties > Tags).
--     3. Optional: add a String attribute "ItemType" (e.g. "Flour", "Egg", "Pot").
--        This controls which drop zones will accept it.
--
--   Drop zones (burners, mixing spots, counter slots):
--     1. Make a Part where items should snap to. A thin, flat part works well.
--        Tip: set Transparency ~0.5 so players can see it's a target.
--     2. Add the tag "DropZone" to it.
--     3. Optional: add a String attribute "Accepts" listing the ItemTypes it
--        takes, separated by commas (e.g. "Flour,Egg" or just "Pot").
--        Leave it off to accept anything.
--
-- WHAT HAPPENS IN GAME:
--   Players click and drag any tagged item. While dragging, drop zones that
--   would accept the item glow green. Release the item near a free, matching
--   zone and it snaps neatly onto it; release it anywhere else and it floats
--   back to where it was picked up, so items never get lost.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tags = require(ReplicatedStorage:WaitForChild("Tags"))

-- How close (in studs) a dropped item must be to a zone to snap onto it.
local SNAP_DISTANCE = 8

-- Remembers where each item was when a drag started, so we can send it back
-- if the player drops it nowhere useful.
local dragStartCFrames = {}

-- Remembers which item is currently sitting on each zone (one item per zone).
local zoneContents = {}

--------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------

-- Works for both single Parts and Models.
local function getPivot(item)
	return item:GetPivot()
end

local function getItemHeight(item)
	if item:IsA("Model") then
		return item:GetExtentsSize().Y
	end
	return item.Size.Y
end

-- Does this zone accept this item? Compares the zone's "Accepts" list
-- against the item's "ItemType". No "Accepts" attribute = accepts anything.
local function zoneAcceptsItem(zone, item)
	local accepts = zone:GetAttribute("Accepts")
	if not accepts or accepts == "" then
		return true
	end

	local itemType = item:GetAttribute("ItemType")
	if not itemType then
		return false
	end

	for name in string.gmatch(accepts, "[^,%s]+") do
		if name == itemType then
			return true
		end
	end
	return false
end

-- Finds the closest free zone (within SNAP_DISTANCE) that accepts the item.
local function findBestZone(item)
	local itemPosition = getPivot(item).Position
	local bestZone = nil
	local bestDistance = SNAP_DISTANCE

	for _, zone in ipairs(CollectionService:GetTagged(Tags.DropZone)) do
		local occupiedBy = zoneContents[zone]
		local isFree = occupiedBy == nil or occupiedBy == item
		if isFree and zoneAcceptsItem(zone, item) then
			local distance = (zone.Position - itemPosition).Magnitude
			if distance < bestDistance then
				bestDistance = distance
				bestZone = zone
			end
		end
	end

	return bestZone
end

-- Places the item so it sits centered on top of the zone.
local function snapItemToZone(item, zone)
	local restingHeight = zone.Size.Y / 2 + getItemHeight(item) / 2
	item:PivotTo(zone.CFrame * CFrame.new(0, restingHeight, 0))
end

--------------------------------------------------------------------
-- Green glow on compatible zones while dragging
--------------------------------------------------------------------

local function showZoneHints(item)
	for _, zone in ipairs(CollectionService:GetTagged(Tags.DropZone)) do
		if zoneContents[zone] == nil and zoneAcceptsItem(zone, item) then
			local highlight = Instance.new("Highlight")
			highlight.Name = "DropHint"
			highlight.FillColor = Color3.fromRGB(80, 220, 100)
			highlight.FillTransparency = 0.6
			highlight.OutlineColor = Color3.fromRGB(80, 220, 100)
			highlight.Parent = zone
		end
	end
end

local function clearZoneHints()
	for _, zone in ipairs(CollectionService:GetTagged(Tags.DropZone)) do
		local hint = zone:FindFirstChild("DropHint")
		if hint then
			hint:Destroy()
		end
	end
end

--------------------------------------------------------------------
-- Wiring up each draggable item
--------------------------------------------------------------------

local function onDragStart(item)
	dragStartCFrames[item] = getPivot(item)

	-- If it was sitting on a zone, that zone is now free again.
	for zone, occupant in pairs(zoneContents) do
		if occupant == item then
			zoneContents[zone] = nil
		end
	end

	showZoneHints(item)
end

local function onDragEnd(item)
	clearZoneHints()

	local zone = findBestZone(item)
	if zone then
		snapItemToZone(item, zone)
		zoneContents[zone] = item
	else
		-- Dropped in the middle of nowhere: send it back where it came from.
		local returnTo = dragStartCFrames[item]
		if returnTo then
			item:PivotTo(returnTo)
		end
	end

	dragStartCFrames[item] = nil
end

local function setupDraggable(item)
	-- Give the item a DragDetector if it doesn't already have one.
	-- The DragDetector does all the hard work of mouse/touch dragging for us.
	local dragDetector = item:FindFirstChildOfClass("DragDetector")
	if not dragDetector then
		dragDetector = Instance.new("DragDetector")
		dragDetector.Parent = item
	end

	-- Geometric = the item follows the cursor directly (needs Anchored parts).
	-- TranslateViewPlane = it moves in the plane facing the camera, which
	-- feels like picking something up and carrying it.
	dragDetector.ResponseStyle = Enum.DragDetectorResponseStyle.Geometric
	dragDetector.DragStyle = Enum.DragDetectorDragStyle.TranslateViewPlane
	dragDetector.MaxActivationDistance = 30

	dragDetector.DragStart:Connect(function()
		onDragStart(item)
	end)

	dragDetector.DragEnd:Connect(function()
		onDragEnd(item)
	end)
end

for _, item in ipairs(CollectionService:GetTagged(Tags.Draggable)) do
	setupDraggable(item)
end
CollectionService:GetInstanceAddedSignal(Tags.Draggable):Connect(setupDraggable)
