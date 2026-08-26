-- Handles collectible coins scattered around the obby.
--
-- How to set one up in Studio:
--   1. Place a Part shaped like a coin (a flattened cylinder works well).
--   2. Add the tag "Coin" to it.
--   3. Optional: turn on CanCollide = false so players don't bump into it.
--
-- Touching a coin adds 1 to the player's Coins stat and removes the coin.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Tags = require(game:GetService("ReplicatedStorage"):WaitForChild("Tags"))

-- Prevents a single coin being collected twice if a player's body parts
-- touch it more than once in the same frame.
local beingCollected = {}

local function onCoinTouched(coin, hit)
	if beingCollected[coin] then
		return
	end

	local character = hit.Parent
	local player = character and Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	local coinsStat = leaderstats and leaderstats:FindFirstChild("Coins")
	if not coinsStat then
		return
	end

	beingCollected[coin] = true
	coinsStat.Value += 1
	coin:Destroy()
end

local function setupCoin(coin)
	coin.Touched:Connect(function(hit)
		onCoinTouched(coin, hit)
	end)
end

for _, coin in ipairs(CollectionService:GetTagged(Tags.Coin)) do
	setupCoin(coin)
end
CollectionService:GetInstanceAddedSignal(Tags.Coin):Connect(setupCoin)
