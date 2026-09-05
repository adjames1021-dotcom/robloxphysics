-- Server side of the physics carry system.
--
-- HOW TO SET UP AN ITEM IN STUDIO:
--   1. Make a Part or Model. Leave it UNANCHORED (Anchored = false).
--      (For a Model, weld its parts together and set a PrimaryPart.)
--   2. Add the tag "Draggable" to it (Properties > Tags, or the Tag Editor).
--
-- ITEM HOLDERS (tag: AttachSurface):
--   Tag ONE part (a cookie sheet, a counter section) and it holds up to 6
--   draggable items in an invisible 3x2 grid across its top - no extra
--   parts needed. Drop an item on or near it and the item snaps into the
--   nearest empty grid spot and sticks; grab it to take it back off.
--   Works anchored (a counter) or on a draggable tray (tag it with BOTH
--   Draggable and AttachSurface): carrying the tray carries its items.
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
-- Item holders: each AttachSurface part holds up to 6 items in a 3x2 grid
--------------------------------------------------------------------

-- The grid across the holder's top (3 across its X size, 2 across its Z).
local SLOT_COLUMNS = 3
local SLOT_ROWS = 2
local MAX_ITEMS = SLOT_COLUMNS * SLOT_ROWS

-- How close (studs) a dropped item must be to a grid spot to snap into it.
local ATTACH_RANGE = 2.5

-- Use the middle of the holder's top for the grid (keeps clear of the lip).
local GRID_MARGIN = 0.82

local holderItems = {} -- holder part -> { [gridIndex] = item }
local itemHolder = {} -- item -> { holder = part, index = gridIndex }

-- Where grid spot #index sits on top of the holder (in world space).
local function getSlotCFrame(holder, index)
	local column = (index - 1) % SLOT_COLUMNS
	local row = math.floor((index - 1) / SLOT_COLUMNS)
	local x = (column - (SLOT_COLUMNS - 1) / 2) * holder.Size.X * GRID_MARGIN / SLOT_COLUMNS
	local z = (row - (SLOT_ROWS - 1) / 2) * holder.Size.Z * GRID_MARGIN / SLOT_ROWS
	return holder.CFrame * CFrame.new(x, holder.Size.Y / 2, z)
end

-- Every part welded to the item WITHOUT passing through a holder or an
-- anchored part: the whole cookie (disc + chips), but NOT the sheet it may
-- be welded onto - and therefore not the other cookies on that sheet.
local function getWeldedGroup(item)
	local mainPart = getMainPart(item)
	if not mainPart then
		return {}
	end
	local seen = { [mainPart] = true }
	local queue = { mainPart }
	local group = { mainPart }
	while #queue > 0 do
		local part = table.remove(queue)
		for _, neighbor in ipairs(part:GetConnectedParts()) do
			if not seen[neighbor] then
				seen[neighbor] = true
				if not neighbor.Anchored
					and not CollectionService:HasTag(neighbor, Tags.AttachSurface) then
					table.insert(group, neighbor)
					table.insert(queue, neighbor)
				end
			end
		end
	end
	return group
end


-- This holder's occupancy table, with vanished items tidied out.
local function getHolderItems(holder)
	local items = holderItems[holder]
	if not items then
		items = {}
		holderItems[holder] = items
	end
	for index, occupant in pairs(items) do
		local entry = itemHolder[occupant]
		local mainPart = occupant.Parent and getMainPart(occupant)
		local stillWelded = mainPart and mainPart:FindFirstChild("SurfaceWeld")
		if not stillWelded or not entry
			or entry.holder ~= holder or entry.index ~= index then
			items[index] = nil -- gone or unwelded: free the spot
			if entry and entry.holder == holder and entry.index == index then
				itemHolder[occupant] = nil
			end
		end
	end
	return items
end

-- Snaps the item onto grid spot #index and welds it there.
-- The ENTIRE welded assembly (disc + chips + anything else welded on) is
-- teleported together and laid flat, aligned with the sheet, resting so its
-- lowest point touches the sheet's top - no floating, no sinking, and no
-- physics freak-out from moving one welded piece without its partners.
-- A WeldConstraint is like an invisible bolt: the item becomes one solid
-- piece with the holder until the weld is destroyed.
local function attachItemToHolder(item, holder, index)
	local mainPart = getMainPart(item)
	if not mainPart then
		return
	end

	local slotTop = getSlotCFrame(holder, index)

	-- The move: pivot goes to the grid spot, laid flat with the sheet.
	local delta = slotTop * item:GetPivot():Inverse()

	-- Work out where every welded piece ends up, and how low the whole
	-- thing would hang, so we can lift it to rest exactly on the top.
	local parts = getWeldedGroup(item)

	-- Take physics control on the server for the snap, so the previous
	-- carrier's machine can't overwrite the teleport with stale positions
	-- (that's what left cookies hovering in the air).
	for _, part in ipairs(parts) do
		pcall(part.SetNetworkOwner, part, nil)
	end
	local newCFrames = {}
	local lowestY = math.huge
	for i, part in ipairs(parts) do
		local cf = delta * part.CFrame
		newCFrames[i] = cf
		local size = part.Size
		-- half the part's height along world up, whatever its tilt
		local halfY = (math.abs(cf.RightVector.Y) * size.X
			+ math.abs(cf.UpVector.Y) * size.Y
			+ math.abs(cf.LookVector.Y) * size.Z) / 2
		lowestY = math.min(lowestY, cf.Position.Y - halfY)
	end
	local lift = Vector3.new(0, slotTop.Position.Y - lowestY, 0)

	for i, part in ipairs(parts) do
		part.CFrame = newCFrames[i] + lift
		part.AssemblyLinearVelocity = Vector3.zero
		part.AssemblyAngularVelocity = Vector3.zero
	end

	local weld = Instance.new("WeldConstraint")
	weld.Name = "SurfaceWeld"
	weld.Part0 = holder
	weld.Part1 = mainPart
	weld.Parent = mainPart

	-- Hand physics decisions back to Roblox now that it's welded on.
	pcall(mainPart.SetNetworkOwnershipAuto, mainPart)

	getHolderItems(holder)[index] = item
	itemHolder[item] = { holder = holder, index = index }
end

-- Unsticks the item: removes its weld and frees up its grid spot. The weld
-- can live on any piece of the welded group (grabbing a chip must free the
-- whole cookie), so search all of it.
local function detachFromSurface(item)
	for _, part in ipairs(getWeldedGroup(item)) do
		local weld = part:FindFirstChild("SurfaceWeld")
		if weld then
			weld:Destroy()
		end
	end
	local entry = itemHolder[item]
	if entry then
		local items = holderItems[entry.holder]
		if items and items[entry.index] == item then
			items[entry.index] = nil
		end
		itemHolder[item] = nil
	end
end

-- Finds the closest empty grid spot on any holder near the item.
local function findNearestFreeSpot(item, mainPart)
	local itemPosition = item:GetPivot().Position
	local bestHolder, bestIndex, bestDistance = nil, nil, ATTACH_RANGE

	for _, holder in ipairs(CollectionService:GetTagged(Tags.AttachSurface)) do
		if holder:IsA("BasePart")
			and holder:IsDescendantOf(workspace)
			and not holder:IsDescendantOf(item) -- a tray can't catch itself
			and holder.AssemblyRootPart ~= mainPart.AssemblyRootPart then -- already one piece with us
			local items = getHolderItems(holder)
			for index = 1, MAX_ITEMS do
				if not items[index] then
					local distance = (getSlotCFrame(holder, index).Position - itemPosition).Magnitude
					if distance < bestDistance then
						bestHolder, bestIndex, bestDistance = holder, index, distance
					end
				end
			end
		end
	end
	return bestHolder, bestIndex
end

-- After an item is dropped, wait for it to come to rest, then snap it into
-- the nearest empty grid spot within ATTACH_RANGE studs.
local function tryAttachToSurface(item)
	local mainPart = getMainPart(item)
	if not mainPart then
		return
	end

	for _ = 1, 15 do -- keep checking for ~3 seconds while it settles
		task.wait(0.2)
		if not item.Parent or carriedBy[item] then
			return -- item was destroyed, or someone grabbed it again
		end
		-- Still tumbling fast? Wait for the next check.
		if mainPart.AssemblyLinearVelocity.Magnitude < 6 then
			local holder, index = findNearestFreeSpot(item, mainPart)
			if holder then
				attachItemToHolder(item, holder, index)
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
		-- chocolate chips stay chocolate: skip parts with "chip" in the name
		if not string.find(string.lower(part.Name), "chip") then
			part.Color = COOKED_COLOR
		end
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
