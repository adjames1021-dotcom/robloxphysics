-- Handles checkpoint parts in the obby.
--
-- How to set one up in Studio:
--   1. Place a Part where you want the checkpoint.
--   2. Add the tag "Checkpoint" to it (Studio's "Tag Editor" plugin, or the
--      Properties/Tags panel under the Model tab).
--   3. Add a Number attribute called "Order" to the part (right-click the
--      part in Properties > Attributes > "+") and set it to 1, 2, 3... in
--      the order players should reach them.
--
-- When a player's character touches a checkpoint with a higher Order than
-- their current Stage, we bump their Stage stat and remember the spot so
-- they respawn there instead of the very start of the obby.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Tags = require(game:GetService("ReplicatedStorage"):WaitForChild("Tags"))

-- Stores each player's most recent checkpoint CFrame (position + rotation).
local lastCheckpoint = {}

local function getPlayerFromPart(part)
	local character = part.Parent
	if not character then
		return nil
	end
	return Players:GetPlayerFromCharacter(character)
end

local function onCheckpointTouched(checkpoint, hit)
	local player = getPlayerFromPart(hit)
	if not player then
		return
	end

	local order = checkpoint:GetAttribute("Order")
	if not order then
		warn(checkpoint:GetFullName() .. " is tagged Checkpoint but has no 'Order' attribute")
		return
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	local stage = leaderstats and leaderstats:FindFirstChild("Stage")
	if not stage then
		return
	end

	if order > stage.Value then
		stage.Value = order
		lastCheckpoint[player] = checkpoint.CFrame
	end
end

local function setupCheckpoint(checkpoint)
	checkpoint.Touched:Connect(function(hit)
		onCheckpointTouched(checkpoint, hit)
	end)
end

for _, checkpoint in ipairs(CollectionService:GetTagged(Tags.Checkpoint)) do
	setupCheckpoint(checkpoint)
end
CollectionService:GetInstanceAddedSignal(Tags.Checkpoint):Connect(setupCheckpoint)

-- When a player's character respawns, teleport them to their last checkpoint
-- (if they have reached one yet) instead of the default spawn.
local function onCharacterAdded(player, character)
	local cframe = lastCheckpoint[player]
	if not cframe then
		return
	end

	local humanoidRootPart = character:WaitForChild("HumanoidRootPart", 5)
	if humanoidRootPart then
		-- Move them slightly above the checkpoint so they don't spawn inside the floor.
		character:PivotTo(cframe + Vector3.new(0, 3, 0))
	end
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	lastCheckpoint[player] = nil
end)
