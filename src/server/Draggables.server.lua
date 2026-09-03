-- Server side of the physics carry system.
--
-- HOW TO SET UP AN ITEM IN STUDIO:
--   1. Make a Part or Model. Leave it UNANCHORED (Anchored = false).
--      (For a Model, weld its parts together and set a PrimaryPart.)
--   2. Add the tag "Draggable" to it (Properties > Tags, or the Tag Editor).
--
-- ATTACH SURFACES (cookie sheets, trays, counters):
--   Tag a part "AttachSurface" and anything you drop on top of it sticks to
--   it. Grab a stuck item to take it back off. Tag a part with BOTH
--   "Draggable" and "AttachSurface" to make a carryable tray - carry the
--   cookie sheet and the cookies riding on it come along.
--
-- The actual carrying happens in the client script (DragController), because
-- that's where the camera lives. This server script's jobs are:
--   * create the RemoteEvents the client talks to us through
--   * check the client isn't cheating (item really is draggable, in range,
--     and not already carried by someone else)
--   * hand physics control ("network ownership") of the item to the carrier
--     while they hold it, so it moves with zero lag on their screen
--   * stick dropped items to attach surfaces, and unstick them when grabbed

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tags = require(ReplicatedStorage:WaitForChild("Tags"))

-- How far away (in studs) a player may be when grabbing an item.
-- The client checks this too, but the server check is the one that counts.
local MAX_GRAB_DISTANCE = 35

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
-- Sticking items to attach surfaces
--------------------------------------------------------------------

-- Unsticks the item: removes any weld our attach system created on it.
local function detachFromSurface(item)
	for _, part in ipairs(getParts(item)) do
		local weld = part:FindFirstChild("SurfaceWeld")
		if weld then
			weld:Destroy()
		end
	end
end

-- After an item is dropped, wait for it to come to rest, then look straight
-- down: if it's sitting on a part tagged AttachSurface, weld it in place.
-- A WeldConstraint is like an invisible bolt - the item becomes one solid
-- piece with the surface until the weld is destroyed.
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
			if result and CollectionService:HasTag(result.Instance, Tags.AttachSurface) then
				local weld = Instance.new("WeldConstraint")
				weld.Name = "SurfaceWeld"
				weld.Part0 = result.Instance
				weld.Part1 = mainPart
				weld.Parent = mainPart
				mainPart.AssemblyLinearVelocity = Vector3.zero
			end
			return -- settled: either welded or resting somewhere else
		end
	end
end

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

	-- Grabbing a stuck item takes it OFF its surface.
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
