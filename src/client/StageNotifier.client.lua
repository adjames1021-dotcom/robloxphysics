-- Shows a short on-screen message whenever the player's "Stage" number goes up,
-- so reaching a checkpoint actually feels like something happened.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

local function createNotifierGui()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "StageNotifierGui"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = player:WaitForChild("PlayerGui")

	local label = Instance.new("TextLabel")
	label.Name = "StageLabel"
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0.15, 0)
	label.Size = UDim2.new(0, 400, 0, 50)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.5
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextTransparency = 1
	label.Text = ""
	label.Parent = screenGui

	return label
end

local label = createNotifierGui()

local function showStageMessage(stageNumber)
	label.Text = "Checkpoint " .. stageNumber .. " reached!"
	label.TextTransparency = 0

	local fadeOut = TweenService:Create(label, TweenInfo.new(1.5), { TextTransparency = 1 })
	task.wait(1)
	fadeOut:Play()
end

local function onCharacterAdded()
	local leaderstats = player:WaitForChild("leaderstats")
	local stage = leaderstats:WaitForChild("Stage")

	-- Skip the very first value (Stage starts at 1 when a player joins).
	local lastSeenStage = stage.Value

	stage:GetPropertyChangedSignal("Value"):Connect(function()
		if stage.Value > lastSeenStage then
			showStageMessage(stage.Value)
		end
		lastSeenStage = stage.Value
	end)
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	onCharacterAdded()
end
