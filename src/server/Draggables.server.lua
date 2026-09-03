-- Server side of the physics carry system.
--
-- HOW TO SET UP AN ITEM IN STUDIO:
--   1. Make a Part or Model. Leave it UNANCHORED (Anchored = false).
--      (For a Model, weld its parts together and set a PrimaryPart.)
--   2. Add the tag "Draggable" to it (Properties > Tags, or the Tag Editor).
--
-- SLOT PADS (tag: AttachSurface):
--   A slot pad holds exactly ONE item. Drop an item on a pad and it snaps
--   centered onto it and sticks; grab it to take it back off. Anchor a pad
--   on a counter, or weld an unanchored pad onto a draggable object (like a
--   cookie sheet) with a Studio WeldConstraint - then carrying the sheet
--   carries every slotted item with it.
--
-- OVEN (tag: Oven) + RAW DOUGH (tag: UncookedCookie):
--   Make an invisible part filling the inside of your oven, tag it "Oven"
--   (Anchored = true, CanCollide = false, Transparency = 1). Any item tagged
--   "UncookedCookie" that sits inside it for BAKE_TIME seconds turns cooked
--   brown. Pulling it out early resets its progress.
--
-- The actual carrying happens in the client script (DragController), because
-- that's where the camera lives. This server script's jobs are:
--   * create the RemoteEvents the client talks to us through
--   * check the client isn't cheating (item really is draggable, in range,
--     and not already carried by someone else)
--   * hand physics control ("network ownership") of the item to the carrier
--     while they hold it, so it moves with zero lag on their screen
--   * snap dropped items into free slot pads, and release them when grabbed
--   * bake raw dough that sits inside an oven region

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tags = require(ReplicatedStorage:WaitForChild("Tags"))

-- How far away (in studs) a player may be when grabbing an item.
-- The client checks this too, but the server check is the one that counts.
local MAX_GRAB_DISTANCE = 35

-- How long (seconds) raw dough must stay inside an oven to finish baking.
local BAKE_TIME = 6

-- The color raw dough turns when it finishes baking.
local COOKED_COLOR = Color3.fromRGB(148, 92, 44)

-- How strongly KeepUpright items are nudged back to standing. Torque scales
-- with the item's mass so light and heavy items feel the same. Higher =
-- rights itself faster and is harder to knock over; lower = wobblier.
local UPRIGHT_TORQUE_PER_MASS = 400
local UPRIGHT_RESPONSIVENESS = 15

--------------------------------------------------------------------
-- RemoteEvents: the "phone line" between client and server
--------------------------------------------------------------------
local remotes = Instance.new("Folder")
remotes.Name = "DragRemotes"

local startDragRemote = Instance.new("RemoteEvent")
startDragRemote.Name = "StartDrag"
startDragRemote.Parent = remotes

local stopDragRemote = Instance.new("RemoteEvent")
stopDragRemote.Name = "StopDrag"
stopDragRemote.Parent = remotes

remotes.Parent = ReplicatedStorage

--------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------

-- Returns every physical piece of the item (a lone Part, or all parts
-- inside a Model).
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

-- The item's "main" part: the part itself, or a Model's primary part.
local function getMainPart(item)
	if item:IsA("BasePart") then
		return item
	end
	if item:IsA("Model") then
		return item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function getHalfHeight(item)
	if item:IsA("Model") then
		return item:GetExtentsSize().Y / 2
	end
	return item.Size.Y / 2
end

local function distanceToPlayer(player, item)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return math.huge
	end
	return (item:GetPivot().Position - root.Position).Magnitude
end

--------------------------------------------------------------------
-- Who is carrying what (one carrier per item, one item per player)
--------------------------------------------------------------------
local carriedBy = {} -- item -> player
local carrying = {} -- player -> item

--------------------------------------------------------------------
-- Slot pads: each AttachSurface holds exactly one item
--------------------------------------------------------------------
local slotOccupant = {} -- slot pad part -> the item sitting in it
local itemSlot = {} -- item -> the slot pad it sits in

-- Is this slot pad empty? (Also tidies up if its old occupant vanished.)
local function isSlotFree(slot)
	local occupant = slotOccupant[slot]
	if occupant then
		if occupant.Parent and itemSlot[occupant] == slot then
			return false
		end
		slotOccupant[slot] = nil -- stale entry, clean it up
	end
	return true
end

-- Snaps the item centered on top of the slot pad and welds it there.
-- A WeldConstraint is like an invisible bolt: the item becomes one solid
-- piece with the pad until the weld is destroyed.
local function attachItemToSlot(item, slot)
	local mainPart = getMainPart(item)
	if not mainPart then
		return
	end

	local restingHeight = slot.Size.Y / 2 + getHalfHeight(item)
	item:PivotTo(slot.CFrame * CFrame.new(0, restingHeight, 0))
	mainPart.AssemblyLinearVelocity = Vector3.zero
	mainPart.AssemblyAngularVelocity = Vector3.zero

	local weld = Instance.new("WeldConstraint")
	weld.Name = "SurfaceWeld"
	weld.Part0 = slot
	weld.Part1 = mainPart
	weld.Parent = mainPart

	slotOccupant[slot] = item
	itemSlot[item] = slot
end

-- Unsticks the item: removes its weld and frees up its slot.
local function detachFromSurface(item)
	for _, part in ipairs(getParts(item)) do
		local weld = part:FindFirstChild("SurfaceWeld")
		if weld then
			weld:Destroy()
		end
	end
	local slot = itemSlot[item]
	if slot and slotOccupant[slot] == item then
		slotOccupant[slot] = nil
	end
	itemSlot[item] = nil
end

-- After an item is dropped, wait for it to come to rest, then look straight
-- down: if it landed on a free slot pad, snap it in.
local function tryAttachToSurface(item)
	local mainPart = getMainPart(item)
	if not mainPart then
		return
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { item }

	for _ = 1, 6 do -- keep checking for ~2 seconds while it settles
		task.wait(0.35)
		if not item.Parent or carriedBy[item] then
			return -- item was destroyed, or someone grabbed it again
		end
		-- Still tumbling? Wait for the next check.
		if mainPart.AssemblyLinearVelocity.Magnitude < 2 then
			local origin = item:GetPivot().Position
			local rayLength = getHalfHeight(item) + 1.5
			local result = workspace:Raycast(origin, Vector3.new(0, -rayLength, 0), params)
			if result
				and CollectionService:HasTag(result.Instance, Tags.AttachSurface)
				and isSlotFree(result.Instance) then
				attachItemToSlot(item, result.Instance)
			end
			return -- settled: either slotted or resting somewhere else
		end
	end
end

--------------------------------------------------------------------
-- Grabbing and releasing
--------------------------------------------------------------------

local function release(player)
	local item = carrying[player]
	if not item then
		return
	end
	carrying[player] = nil
	carriedBy[item] = nil

	-- Give physics control back to the server (it decides automatically).
	if item.Parent then
		for _, part in ipairs(getParts(item)) do
			if not part.Anchored then
				part:SetNetworkOwnershipAuto()
			end
		end
		task.spawn(tryAttachToSurface, item)
	end
end

startDragRemote.OnServerEvent:Connect(function(player, item)
	-- Safety checks: ignore the request unless everything is legit.
	if typeof(item) ~= "Instance" or not item.Parent then
		return
	end
	if not CollectionService:HasTag(item, Tags.Draggable) then
		return
	end
	if carriedBy[item] and carriedBy[item] ~= player then
		return -- someone else is holding it
	end
	if distanceToPlayer(player, item) > MAX_GRAB_DISTANCE then
		return -- too far away
	end

	release(player) -- drop anything they were already holding

	-- Grabbing a slotted item takes it OFF its slot pad.
	detachFromSurface(item)

	carrying[player] = item
	carriedBy[item] = player

	-- Let the carrier's machine simulate the item = perfectly smooth carry.
	for _, part in ipairs(getParts(item)) do
		if not part.Anchored then
			part:SetNetworkOwner(player)
		end
	end
end)

stopDragRemote.OnServerEvent:Connect(release)
Players.PlayerRemoving:Connect(release)

--------------------------------------------------------------------
-- The oven: bake raw dough that sits inside an Oven region
--------------------------------------------------------------------

-- Walks up from a touched part to the tagged dough item it belongs to.
local function findUncookedItem(part)
	local current = part
	while current and current ~= workspace do
		if CollectionService:HasTag(current, Tags.UncookedCookie) then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function bake(item)
	for _, part in ipairs(getParts(item)) do
		part.Color = COOKED_COLOR
	end
	CollectionService:RemoveTag(item, Tags.UncookedCookie)
	item:SetAttribute("Cooked", true)
end

local bakeProgress = {} -- dough item -> seconds spent in an oven

task.spawn(function()
	while true do
		task.wait(0.5)

		-- Find every raw dough item currently inside any oven region.
		local inOven = {}
		for _, oven in ipairs(CollectionService:GetTagged(Tags.Oven)) do
			if oven:IsA("BasePart") and oven.Parent then
				for _, part in ipairs(workspace:GetPartsInPart(oven)) do
					local item = findUncookedItem(part)
					if item then
						inOven[item] = true
					end
				end
			end
		end

		-- Tick up the timer for dough in an oven; bake when it's done.
		for item in pairs(inOven) do
			bakeProgress[item] = (bakeProgress[item] or 0) + 0.5
			if bakeProgress[item] >= BAKE_TIME then
				bakeProgress[item] = nil
				bake(item)
			end
		end

		-- Dough taken out early goes back to raw: progress resets.
		for item in pairs(bakeProgress) do
			if not inOven[item] then
				bakeProgress[item] = nil
			end
		end
	end
end)

--------------------------------------------------------------------
-- KeepUpright: gently nudge tagged items back to standing
--------------------------------------------------------------------
-- An AlignOrientation with LIMITED torque constantly steers the item's
-- up-axis toward world-up - like a toy with a weighted bottom. Because the
-- torque is capped, the item can still tip over, tumble when thrown, and
-- wobble; it just prefers to end up upright. Yaw (spinning like a top) is
-- left completely free.
local function setupKeepUpright(item)
	local mainPart = getMainPart(item)
	if not mainPart or mainPart:FindFirstChild("UprightForce") then
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "UprightAttachment"
	attachment.Axis = Vector3.new(0, 1, 0) -- the axis we want pointing up
	attachment.Parent = mainPart

	local align = Instance.new("AlignOrientation")
	align.Name = "UprightForce"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.PrimaryAxisOnly = true -- only steer the up-axis, leave yaw free
	align.PrimaryAxis = Vector3.new(0, 1, 0) -- ...toward world up
	align.RigidityEnabled = false
	align.MaxTorque = mainPart.AssemblyMass * UPRIGHT_TORQUE_PER_MASS
	align.Responsiveness = UPRIGHT_RESPONSIVENESS
	align.Parent = mainPart
end

for _, item in ipairs(CollectionService:GetTagged(Tags.KeepUpright)) do
	setupKeepUpright(item)
end
CollectionService:GetInstanceAddedSignal(Tags.KeepUpright):Connect(setupKeepUpright)

--------------------------------------------------------------------
-- Prepare every tagged item
--------------------------------------------------------------------
local function setupDraggable(item)
	for _, part in ipairs(getParts(item)) do
		part.CanCollide = true -- collide with the world and with players
	end

	-- Remove any leftover DragDetector from the old system so the two
	-- dragging methods don't fight each other.
	local oldDetector = item:FindFirstChildOfClass("DragDetector")
	if oldDetector then
		oldDetector:Destroy()
	end
end

for _, item in ipairs(CollectionService:GetTagged(Tags.Draggable)) do
	setupDraggable(item)
end
CollectionService:GetInstanceAddedSignal(Tags.Draggable):Connect(setupDraggable)
