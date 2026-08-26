-- Handles "kill bricks" (lava, spikes, etc.) in the obby.
--
-- How to set one up in Studio:
--   1. Place a Part where you want players to die on touch.
--   2. Add the tag "KillPart" to it (Tag Editor plugin, or Properties > Tags).
--
-- Touching one instantly kills the player's character. Since Checkpoints.server.lua
-- listens for the character respawning, they'll come back at their last checkpoint.

local CollectionService = game:GetService("CollectionService")
local Tags = require(game:GetService("ReplicatedStorage"):WaitForChild("Tags"))

local function onKillPartTouched(hit)
	local character = hit.Parent
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid.Health = 0
	end
end

local function setupKillPart(part)
	part.Touched:Connect(onKillPartTouched)
end

for _, part in ipairs(CollectionService:GetTagged(Tags.KillPart)) do
	setupKillPart(part)
end
CollectionService:GetInstanceAddedSignal(Tags.KillPart):Connect(setupKillPart)
