-- Server side of the physics carry system.
--
-- HOW TO SET UP AN ITEM IN STUDIO:
--   1. Make a Part or Model. Leave it UNANCHORED (Anchored = false).
--      (For a Model, weld its parts together and set a PrimaryPart.)
--   2. Add the tag "Draggable" to it (Properties > Tags, or the Tag Editor).
--
-- The actual carrying happens in the client script (DragController), because
-- that's where the camera lives. This server script's jobs are:
--   * create the RemoteEvents the client talks to us through
--   * check the client isn't cheating (item really is draggable, in range,
--     and not already carried by someone else)
--   * hand physics control ("network ownership") of the item to the carrier
--     while they hold it, so it moves with zero lag on their screen

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
