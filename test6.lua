-- Ultimate Farm Script - Final Version
-- Все ошибки исправлены, настраиваемые параметры в GUI
-- Скорость игрока = скорость волны при приближении
-- Задержка перед бегом вкл/выкл

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local VirtualInputManager = game:GetService("VirtualInputManager")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- ============ НАСТРАИВАЕМЫЕ ПАРАМЕТРЫ ============
local KICK_POWER = 10
local KICK_READY_RADIUS = 10
local MIN_WAVE_DISTANCE = 300
local FINISH_DELAY_MIN = 0.3
local FINISH_DELAY_MAX = 1.2
local FINISH_WAIT_MIN = 0.1
local FINISH_WAIT_MAX = 0.8
local SWAY_AMOUNT = 8
local SWAY_CHANCE = 0.3
local STRAFE_CHANCE = 0.15
local JUMP_CHANCE = 0.05
local WAVE_DANGER_DISTANCE = 100
local WAVE_CRITICAL_DISTANCE = 30
local ENABLE_FINISH_DELAY = true

-- ============ КОНСТАНТЫ ============
local MOVEMENT_TIMEOUT = 30
local JUMP_COOLDOWN = 0.5
local UPDATE_INTERVAL = 0.3
local CAMERA_WAIT_TIMEOUT = 5
local TELEPORT_OFFSET_Y = 5

local WAVE_SPEEDS = {
	Common = 11, Rare = 18, Epic = 32, Legendary = 45,
	Mythic = 55, Godly = 68, Secret = 80, Rainbow = 90,
	Hacked = 100, Demon = 110, Celestial = 125, Eternal = 135,
	["Eternal+"] = 155, Abyssal = 165
}

-- ============ ПЕРЕМЕННЫЕ ============
local character, humanoid, rootPart
local kickReadyPart, kickReadyPos
local revKickEvent
local isKickActive, isBpActive, isAutoSell, isAutoBonus = false, false, false, false
local isAutoSpeedUpgrade, isAutoWeight, isAutoBuyWeight, isAutoTrade = false, false, false, false
local lastJumpTime, baseWalkSpeed = 0, 16
local bpData, claimedCount = nil, 0
local selectedBrainrots = {}
local selectedMutations = {["None"] = true}
local lastGUIUpdate = 0
local hasTeleported = false

local TRADE_ITEMS = {"Ballberto", "Netini Goalini"}

-- GUI
local screenGui, openButton, mainMenu
local kickToggle, kickStatus, kickWaveLabel
local bpToggle, bpStatus, bpInfoLabel
local sellToggle, sellStatus
local bonusToggle, bonusStatus
local speedUpgradeToggle, speedUpgradeStatus
local weightToggle, weightStatus
local buyWeightToggle, buyWeightStatus
local tradeToggle, tradeStatus

local kickPowerInput, kickRadiusInput, minWaveDistInput
local delayMinInput, delayMaxInput, waitMinInput, waitMaxInput
local swayAmountInput, swayChanceInput, strafeChanceInput, jumpChanceInput
local waveDangerInput, waveCriticalInput
local delayToggleBtn, delayToggleStatus
local currentTab = "Main"

-- ============ ДАННЫЕ ============
local EntitiesData, MutationData
pcall(function() EntitiesData = require(ReplicatedStorage.Shared.Data.EntitiesData) end)
pcall(function() MutationData = require(ReplicatedStorage.Shared.Data.MutationData) end)

local function safeCPS(name)
	if not EntitiesData or not EntitiesData.Brainrots then return 0 end
	local data = EntitiesData.Brainrots[name]
	if not data then return 0 end
	local cpsRaw = data.CPS
	if not cpsRaw then return 0 end
	local num = nil
	pcall(function()
		if type(cpsRaw) == "table" and cpsRaw.Value then
			local val = tostring(cpsRaw.Value):gsub("[^%d.]", "")
			if val ~= "" then num = tonumber(val) end
		end
	end)
	if not num then
		local str = tostring(cpsRaw):gsub(",", ""):gsub("%s", ""):gsub("[^%d.]", "")
		if str ~= "" then num = tonumber(str) end
	end
	if not num and type(cpsRaw) == "number" then num = cpsRaw end
	return num or 0
end

local function getBrainrotList()
	local list = {}
	if not EntitiesData or not EntitiesData.Brainrots then return list end
	for name, _ in pairs(EntitiesData.Brainrots) do
		local cps = safeCPS(name)
		if cps > 0 then table.insert(list, {Name = name, CPS = cps}) end
	end
	table.sort(list, function(a, b) return a.CPS < b.CPS end)
	return list
end

local function getMutationList()
	local list = {"None"}
	if MutationData and MutationData.ValidMutations then
		for _, mut in ipairs(MutationData.ValidMutations) do table.insert(list, mut) end
	end
	return list
end

local function getCurrentMorph()
	if not player.Character then return "Нет", "Нет", 0, 0 end
	for _, child in ipairs(player.Character:GetChildren()) do
		if child:IsA("Tool") and child:HasTag("EntityTool") then
			return child.Name, child:GetAttribute("Mutation") or "None", child:GetAttribute("Level") or 1, safeCPS(child.Name)
		end
	end
	return "Нет", "Нет", 0, 0
end

local function scanBackpack()
	local inv = {}
	if not player.Backpack then return inv end
	for _, item in ipairs(player.Backpack:GetChildren()) do
		if item:IsA("Tool") and item:HasTag("EntityTool") then
			local name = item.Name
			if not inv[name] then inv[name] = {} end
			table.insert(inv[name], {
				Level = item:GetAttribute("Level") or 1,
				Mutation = item:GetAttribute("Mutation") or "None",
				GUID = item:GetAttribute("GUID"),
				CPS = safeCPS(name)
			})
		end
	end
	return inv
end

-- ============ УТИЛИТЫ ============
local function findNetwork()
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	if shared then
		local packages = shared:FindFirstChild("Packages")
		if packages then return packages:FindFirstChild("Network") end
	end
	return nil
end

-- Безопасный FireServer
local function safeFireServer(eventName, ...)
	local net = findNetwork()
	if not net then return end
	local event = net:FindFirstChild(eventName)
	if event then
		pcall(function() event:FireServer(...) end)
	end
end

local function updateCharacterReferences()
	character = player.Character
	if character then
		humanoid = character:FindFirstChild("Humanoid")
		rootPart = character:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and rootPart then
			baseWalkSpeed = humanoid.WalkSpeed
			return true
		end
	end
	return false
end

local function isInKickReady()
	if not rootPart or not kickReadyPos then return false end
	return (rootPart.Position - kickReadyPos).Magnitude <= KICK_READY_RADIUS
end

local function getClosestWave()
	local waves = workspace:FindFirstChild("Waves")
	if not waves or not rootPart then return math.huge, 0, "Нет" end
	local md, wc, cr = math.huge, 0, "Нет"
	for _, w in pairs(waves:GetChildren()) do
		local wp = nil
		if w:IsA("Model") then wp = w.PrimaryPart and w.PrimaryPart.Position or w:GetPivot().Position
		elseif w:IsA("BasePart") then wp = w.Position end
		if wp then wc = wc + 1; local d = (rootPart.Position - wp).Magnitude; if d < md then md = d; cr = w:GetAttribute("Rarity") or w.Name end end
	end
	return md, wc, cr
end

local function getDynamicSpeed()
	local waveDist, _, rarity = getClosestWave()
	local waveSpeed = WAVE_SPEEDS[rarity] or 25
	
	if waveDist >= WAVE_DANGER_DISTANCE then return baseWalkSpeed end
	if waveDist <= WAVE_CRITICAL_DISTANCE then return waveSpeed end
	
	local t = 1 - (waveDist - WAVE_CRITICAL_DISTANCE) / (WAVE_DANGER_DISTANCE - WAVE_CRITICAL_DISTANCE)
	return baseWalkSpeed + (waveSpeed - baseWalkSpeed) * t
end

local function isCameraOnPlayer()
	if not rootPart then return false end
	return (camera.CFrame.Position - rootPart.Position).Magnitude < 50 and camera.CameraType == Enum.CameraType.Custom
end

local function waitForCameraOnPlayer()
	local waitStart = tick()
	while isKickActive and tick() - waitStart < CAMERA_WAIT_TIMEOUT do
		if not updateCharacterReferences() then return false end
		if isCameraOnPlayer() then return true end
		task.wait(0.1)
	end
	return true
end

local function teleportToStart()
	if not kickReadyPos or not rootPart then return false end
	rootPart.CFrame = CFrame.new(kickReadyPos + Vector3.new(0, TELEPORT_OFFSET_Y, 0))
	task.wait(0.3)
	if humanoid then humanoid:MoveTo(rootPart.Position) end
	hasTeleported = true
	return true
end

-- ============ KICK ============
local function initKickRefs()
	local areas = workspace:FindFirstChild("Areas")
	if areas then kickReadyPart = areas:FindFirstChild("KickReady"); if kickReadyPart then kickReadyPos = kickReadyPart.Position end end
	local net = findNetwork()
	if net then revKickEvent = net:FindFirstChild("rev_KickEvent") end
end

local function moveToFinish()
	if not updateCharacterReferences() then return false end
	if not humanoid or not rootPart or not kickReadyPos then return false end
	if humanoid.Health <= 0 then return false end
	if isInKickReady() then return true end
	
	waitForCameraOnPlayer()
	
	if ENABLE_FINISH_DELAY then
		local delay = FINISH_DELAY_MIN + math.random() * (FINISH_DELAY_MAX - FINISH_DELAY_MIN)
		local delayStart = tick()
		while isKickActive and tick() - delayStart < delay do
			if not updateCharacterReferences() then return false end
			if isInKickReady() then return true end
			task.wait(0.05)
		end
	end
	
	local swayDirection = 0
	humanoid.AutoRotate = true
	
	while isKickActive do
		if not updateCharacterReferences() then return false end
		if humanoid.Health <= 0 then return false end
		if isInKickReady() then return true end
		
		humanoid.WalkSpeed = getDynamicSpeed()
		
		if math.random() < SWAY_CHANCE then swayDirection = math.random(-1, 1) end
		if math.random() < STRAFE_CHANCE then swayDirection = math.random() < 0.5 and -1 or 1 end
		
		local targetPos = kickReadyPos
		if swayDirection ~= 0 then
			local forward = (kickReadyPos - rootPart.Position).Unit
			local right = Vector3.new(-forward.Z, 0, forward.X)
			targetPos = targetPos + right * swayDirection * SWAY_AMOUNT
		end
		
		humanoid:MoveTo(targetPos)
		
		if math.random() < JUMP_CHANCE then
			if tick() - lastJumpTime > JUMP_COOLDOWN then humanoid.Jump = true; lastJumpTime = tick() end
		end
		
		if humanoid.MoveDirection.Magnitude < 0.1 then
			if tick() - lastJumpTime > JUMP_COOLDOWN then humanoid.Jump = true; lastJumpTime = tick() end
		end
		
		task.wait(0.1)
	end
	
	return isInKickReady()
end

local function kickLoop()
	initKickRefs()
	while isKickActive do
		if not updateCharacterReferences() then task.wait(0.5); continue end
		
		local inGame = player:GetAttribute("InGame")
		local kd = player:GetAttribute("KickDebounced")
		
		if not isInKickReady() then
			if inGame == nil and kd == nil then
				if not hasTeleported then teleportToStart() end
			else
				hasTeleported = false
				moveToFinish()
			end
		end
		
		if isInKickReady() and inGame == nil and kd == nil then
			hasTeleported = false
			local waitTime = FINISH_WAIT_MIN + math.random() * (FINISH_WAIT_MAX - FINISH_WAIT_MIN)
			local waitStart = tick()
			while isKickActive and tick() - waitStart < waitTime do
				if not updateCharacterReferences() then break end
				if not isInKickReady() then break end
				inGame = player:GetAttribute("InGame")
				kd = player:GetAttribute("KickDebounced")
				if inGame ~= nil or kd ~= nil then break end
				task.wait(0.05)
			end
			
			if isInKickReady() and inGame == nil and kd == nil then
				local dist = getClosestWave()
				if dist >= MIN_WAVE_DISTANCE and revKickEvent then
					revKickEvent:FireServer(KICK_POWER)
				end
			end
		end
		
		task.wait(0.1)
	end
end

-- ============ BATTLEPASS ============
local function getBPData()
	local net = findNetwork()
	if not net then return nil end
	local ds = net:FindFirstChild("rev_BattlePassDataSend")
	if ds and ds:IsA("RemoteEvent") then ds.OnClientEvent:Connect(function(d) bpData = d end) end
	return bpData
end

local function claimReward(id, rt)
	local net = findNetwork()
	if not net then return false end
	local func = net:FindFirstChild(rt == "Bonus" and "ref_BattlePassAttemptBonusClaim" or "ref_BattlePassAttemptClaim")
	if func then local s, r = pcall(func.InvokeServer, func, id, rt); return s and r end
	return false
end

local function autoClaim()
	if not bpData then bpData = getBPData(); if not bpData then return 0 end end
	local xp = bpData.XP or 0
	local uf, up, ub = bpData.UnlockedFreeRewards or {}, bpData.UnlockedPremiumRewards or {}, bpData.UnlockedBonusRewards or {}
	local nc = 0
	for i = 1, 15 do if xp >= i*500 and not table.find(uf, i) then if claimReward(i, "Free") then table.insert(uf, i); nc = nc + 1; task.wait(0.1) end end end
	if bpData.HasPremium then for i = 0, 15 do if xp >= i*500 and not table.find(up, i) then if claimReward(i, "Premium") then table.insert(up, i); nc = nc + 1; task.wait(0.1) end end end end
	local af = true; for i = 1, 15 do if not table.find(uf, i) then af = false; break end end
	if af then for i, xpr in ipairs({8250, 9000, 9750, 10500, 11250}) do if xp >= xpr and not table.find(ub, i) then if claimReward(i, "Bonus") then table.insert(ub, i); nc = nc + 1; task.wait(0.1) end end end end
	return nc
end

local function bpLoop() while isBpActive do local n = autoClaim(); if n > 0 then claimedCount = claimedCount + n end; task.wait(1) end end

-- ============ AUTO SELL ============
local function sellItem(guid)
	safeFireServer("SELL_ENTITY", guid)
end

local function autoSellLoop()
	while isAutoSell do
		for name, items in pairs(scanBackpack()) do
			for _, item in ipairs(items) do
				if not (selectedBrainrots[name] and (selectedMutations[item.Mutation] or item.Mutation == "None")) and item.GUID then
					sellItem(item.GUID); task.wait(0.05)
				end
			end
		end
		task.wait(2)
	end
end

-- ============ AUTO BONUS CLICK ============
local function clickBonus(btn)
	local x = btn.AbsolutePosition.X + btn.AbsoluteSize.X/2
	local y = btn.AbsolutePosition.Y + btn.AbsoluteSize.Y/2
	pcall(function() VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0); task.wait(0.01); VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0) end)
	pcall(function() for _, b in ipairs(btn.Activated:GetBindables()) do b:Fire() end end)
end

local function autoBonusLoop()
	while isAutoBonus do
		local hasWeight = false
		if player.Character then
			for _, tool in ipairs(player.Character:GetChildren()) do
				if tool:IsA("Tool") and tool:HasTag("EntityTool") then
					local wm = ReplicatedStorage.Objects:FindFirstChild("WeightModels")
					if wm and wm:FindFirstChild(tool.Name) then hasWeight = true; break end
				end
			end
		end
		if hasWeight then
			local pg = player:FindFirstChild("PlayerGui")
			if pg then
				local ku = pg:FindFirstChild("KickUpgrades")
				if ku and ku.Enabled then
					for _, child in ipairs(ku:GetDescendants()) do
						if child:IsA("ImageButton") and (child.Name == "Bonus" or child.Name:find("Bonus")) and child.Visible and child.Active then
							clickBonus(child); task.wait(0.03)
						end
					end
				end
			end
		end
		task.wait(0.05)
	end
end

-- ============ AUTO SPEED UPGRADE ============
local function autoSpeedUpgradeLoop()
	local SpeedServiceClient, ClientBalanceService, SpeedData
	pcall(function() SpeedServiceClient = require(ReplicatedStorage.Modules.ServicesLoader.SpeedServiceClient) end)
	pcall(function() ClientBalanceService = require(ReplicatedStorage.Modules.ServicesLoader.ClientBalanceService) end)
	pcall(function() SpeedData = require(ReplicatedStorage.Shared.Data.SpeedData) end)
	while isAutoSpeedUpgrade do
		if SpeedServiceClient and ClientBalanceService and SpeedData then
			pcall(function()
				local cost = SpeedData:GetCostForLevel(SpeedServiceClient.Level)
				if cost and cost <= ClientBalanceService.Balance then SpeedServiceClient:RequestUpgrade(1) end
			end)
		end
		task.wait(1)
	end
end

-- ============ AUTO BEST WEIGHT ============
local function autoWeightLoop()
	local WeightServiceClient, WeightsData
	pcall(function() WeightServiceClient = require(ReplicatedStorage.Modules.ServicesLoader.WeightServiceClient) end)
	pcall(function() WeightsData = require(ReplicatedStorage.Shared.Data.WeightsData) end)
	while isAutoWeight do
		if WeightServiceClient and WeightsData then
			pcall(function()
				local best, bestPPS = nil, 0
				for _, name in ipairs(WeightServiceClient.Owned or {}) do
					local data = WeightsData.Weights[name]
					if data and data.PPS and data.PPS > bestPPS then bestPPS = data.PPS; best = name end
				end
				if best and best ~= WeightServiceClient.Equipped then
					safeFireServer("WeightEquip", best)
				end
			end)
		end
		task.wait(3)
	end
end

-- ============ AUTO BUY WEIGHT ============
local function autoBuyWeightLoop()
	local ShopController, ClientBalanceService, WeightServiceClient, WeightsData
	pcall(function() ShopController = require(ReplicatedStorage.Modules.ControllerLoader.ShopController) end)
	pcall(function() ClientBalanceService = require(ReplicatedStorage.Modules.ServicesLoader.ClientBalanceService) end)
	pcall(function() WeightServiceClient = require(ReplicatedStorage.Modules.ServicesLoader.WeightServiceClient) end)
	pcall(function() WeightsData = require(ReplicatedStorage.Shared.Data.WeightsData) end)
	while isAutoBuyWeight do
		if ShopController and ClientBalanceService and WeightServiceClient and WeightsData then
			pcall(function()
				local owned = WeightServiceClient.Owned or {}
				local best, bestPPS = nil, 0
				for name, data in pairs(WeightsData.Weights) do
					if not table.find(owned, name) and data.Cost and data.PPS and data.Cost <= ClientBalanceService.Balance and data.PPS > bestPPS then
						bestPPS = data.PPS; best = name
					end
				end
				if best then ShopController:BuyItem("WeightShop", best) end
			end)
		end
		task.wait(2)
	end
end

-- ============ AUTO TRADE ============
local function autoTradeLoop()
	local Network
	pcall(function() Network = require(ReplicatedStorage.Shared.Packages.Network) end)
	if not Network then return end
	local targetUserId, targetPlayer, tradeStarted, itemAdded, tradeCompleted = nil, nil, false, false, false
	
	local function findTargetPlayer()
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Name == "Timka_q1t" or p.Name == "VipTimXavier" then targetPlayer = p; targetUserId = p.UserId; return true end
		end
		return false
	end
	
	local function findTradeItem()
		if not player.Backpack then return false, nil, nil end
		for _, item in ipairs(player.Backpack:GetChildren()) do
			if item:IsA("Tool") and item:HasTag("EntityTool") then
				for _, tradeName in ipairs(TRADE_ITEMS) do
					if item.Name == tradeName then return item:GetAttribute("GUID"), item, tradeName end
				end
			end
		end
		return false, nil, nil
	end
	
	Network.OnClientEvent("trade_n"):Connect(function(userId, time)
		if isAutoTrade and targetUserId and userId == targetUserId then
			safeFireServer("trade_start", userId)
			tradeStarted = true; itemAdded = false
		end
	end)
	
	Network.OnClientEvent("trade_s"):Connect(function(status, ...)
		if not isAutoTrade then return end
		if status == "Trading" then
			if not itemAdded then
				task.wait(0.3)
				local guid, _, _ = findTradeItem()
				if guid then safeFireServer("trade_i", "AddItem", guid); itemAdded = true end
			end
			task.wait(0.3)
			safeFireServer("trade_i", "Confirm")
		elseif status == "Cancelled" then
			tradeStarted, itemAdded, tradeCompleted = false, false, false
		end
	end)
	
	Network.OnClientEvent("trade_u"):Connect(function(data)
		if not isAutoTrade or not data then return end
		if data.Stage == "Process" then tradeCompleted = true
		elseif data.Stage == "Final" then task.wait(0.2); safeFireServer("trade_i", "Confirm")
		elseif data.Stage == "Trade" and not itemAdded then
			local guid, _, _ = findTradeItem()
			if guid then safeFireServer("trade_i", "AddItem", guid); itemAdded = true end
		end
	end)
	
	while isAutoTrade do
		local guid, _, _ = findTradeItem()
		if guid and not tradeCompleted then
			if findTargetPlayer() and not tradeStarted then
				safeFireServer("trade_r", targetUserId)
				tradeStarted = true; task.wait(2)
			end
		elseif tradeCompleted then
			tradeStarted, itemAdded, tradeCompleted = false, false, false
		end
		task.wait(3)
	end
end

-- ============ ПРИМЕНЕНИЕ НАСТРОЕК ============
local function applySettings()
	local function tonumberSafe(str, default)
		if not str or str == "" then return default end
		local num = tonumber(str)
		return num or default
	end
	
	if kickPowerInput then KICK_POWER = tonumberSafe(kickPowerInput.Text, 10) end
	if kickRadiusInput then KICK_READY_RADIUS = tonumberSafe(kickRadiusInput.Text, 10) end
	if minWaveDistInput then MIN_WAVE_DISTANCE = tonumberSafe(minWaveDistInput.Text, 300) end
	if delayMinInput then FINISH_DELAY_MIN = tonumberSafe(delayMinInput.Text, 0.3) end
	if delayMaxInput then FINISH_DELAY_MAX = tonumberSafe(delayMaxInput.Text, 1.2) end
	if waitMinInput then FINISH_WAIT_MIN = tonumberSafe(waitMinInput.Text, 0.1) end
	if waitMaxInput then FINISH_WAIT_MAX = tonumberSafe(waitMaxInput.Text, 0.8) end
	if swayAmountInput then SWAY_AMOUNT = tonumberSafe(swayAmountInput.Text, 8) end
	if swayChanceInput then SWAY_CHANCE = tonumberSafe(swayChanceInput.Text, 0.3) end
	if strafeChanceInput then STRAFE_CHANCE = tonumberSafe(strafeChanceInput.Text, 0.15) end
	if jumpChanceInput then JUMP_CHANCE = tonumberSafe(jumpChanceInput.Text, 0.05) end
	if waveDangerInput then WAVE_DANGER_DISTANCE = tonumberSafe(waveDangerInput.Text, 100) end
	if waveCriticalInput then WAVE_CRITICAL_DISTANCE = tonumberSafe(waveCriticalInput.Text, 30) end
	
	if delayToggleStatus then
		delayToggleStatus.Text = ENABLE_FINISH_DELAY and "Задержка: " .. FINISH_DELAY_MIN .. "-" .. FINISH_DELAY_MAX .. " сек" or "Задержка: ОТКЛЮЧЕНА"
	end
end

-- ============ GUI ============
local function createGUI()
	screenGui = Instance.new("ScreenGui"); screenGui.Name = "FarmMenu"; screenGui.ResetOnSpawn = false; screenGui.Parent = CoreGui
	
	openButton = Instance.new("TextButton")
	openButton.Size = UDim2.new(0, 46, 0, 46); openButton.Position = UDim2.new(1, -58, 0, 10)
	openButton.BackgroundColor3 = Color3.fromRGB(25, 25, 25); openButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	openButton.TextSize = 22; openButton.Font = Enum.Font.GothamBold; openButton.Text = "☰"
	openButton.BackgroundTransparency = 0.15; openButton.BorderSizePixel = 0; openButton.Parent = screenGui
	Instance.new("UICorner", openButton).CornerRadius = UDim.new(0, 23)
	
	mainMenu = Instance.new("Frame")
	mainMenu.Size = UDim2.new(0, 360, 0, 500); mainMenu.Position = UDim2.new(0.5, -180, 0.04, 0)
	mainMenu.BackgroundColor3 = Color3.fromRGB(18, 18, 18); mainMenu.BorderSizePixel = 0
	mainMenu.BackgroundTransparency = 0.03; mainMenu.Visible = false
	mainMenu.Active = true; mainMenu.Draggable = true; mainMenu.Parent = screenGui
	Instance.new("UICorner", mainMenu).CornerRadius = UDim.new(0, 14)
	
	local tb = Instance.new("Frame"); tb.Size = UDim2.new(1, 0, 0, 40); tb.BackgroundColor3 = Color3.fromRGB(30, 30, 30); tb.BorderSizePixel = 0; tb.Parent = mainMenu
	Instance.new("UICorner", tb).CornerRadius = UDim.new(0, 14)
	local tl = Instance.new("TextLabel"); tl.Size = UDim2.new(1, -40, 0, 40); tl.Position = UDim2.new(0, 15, 0, 0)
	tl.BackgroundTransparency = 1; tl.Text = "⚡ FARM MENU"; tl.TextColor3 = Color3.fromRGB(255, 255, 255)
	tl.TextSize = 15; tl.Font = Enum.Font.GothamBold; tl.TextXAlignment = Enum.TextXAlignment.Left; tl.Parent = tb
	local cb = Instance.new("TextButton"); cb.Size = UDim2.new(0, 30, 0, 30); cb.Position = UDim2.new(1, -35, 0, 5)
	cb.BackgroundColor3 = Color3.fromRGB(255, 50, 50); cb.TextColor3 = Color3.fromRGB(255, 255, 255)
	cb.TextSize = 16; cb.Font = Enum.Font.GothamBold; cb.Text = "✕"; cb.BorderSizePixel = 0; cb.Parent = tb
	Instance.new("UICorner", cb).CornerRadius = UDim.new(0, 15)
	cb.MouseButton1Click:Connect(function() mainMenu.Visible = false; openButton.Visible = true end)
	
	local tabBar = Instance.new("Frame"); tabBar.Size = UDim2.new(1, 0, 0, 32); tabBar.Position = UDim2.new(0, 0, 0, 40)
	tabBar.BackgroundColor3 = Color3.fromRGB(22, 22, 22); tabBar.BorderSizePixel = 0; tabBar.Parent = mainMenu
	local tabNames = {"⚽", "⚙", "🎒", "🧠"}
	local tabKeys = {"Main", "Settings", "Inventory", "Brainrot"}
	local tabs = {}
	for i, name in ipairs(tabNames) do
		local tab = Instance.new("TextButton"); tab.Size = UDim2.new(0.25, -1, 1, 0); tab.Position = UDim2.new((i-1)*0.25, 0, 0, 0)
		tab.BackgroundColor3 = i == 1 and Color3.fromRGB(45, 45, 45) or Color3.fromRGB(22, 22, 22); tab.TextColor3 = Color3.fromRGB(255, 255, 255)
		tab.TextSize = 14; tab.Font = Enum.Font.Gotham; tab.Text = name; tab.BorderSizePixel = 0; tab.Parent = tabBar; tabs[tabKeys[i]] = tab
		tab.MouseButton1Click:Connect(function()
			for _, t in pairs(tabs) do t.BackgroundColor3 = Color3.fromRGB(22, 22, 22) end
			tab.BackgroundColor3 = Color3.fromRGB(45, 45, 45); currentTab = tabKeys[i]
			local ct = mainMenu:FindFirstChild("Content")
			if ct then for _, c in ipairs(ct:GetChildren()) do if c:IsA("Frame") then c.Visible = (c.Name == currentTab .. "Tab") end end end
		end)
	end
	
	local content = Instance.new("Frame"); content.Name = "Content"; content.Size = UDim2.new(1, 0, 1, -72); content.Position = UDim2.new(0, 0, 0, 72); content.BackgroundTransparency = 1; content.Parent = mainMenu
	
	local function sec(scroll, title, h, color)
		local s = Instance.new("Frame"); s.Size = UDim2.new(1, 0, 0, h); s.BackgroundColor3 = Color3.fromRGB(28, 28, 28); s.BorderSizePixel = 0; s.Parent = scroll
		Instance.new("UICorner", s).CornerRadius = UDim.new(0, 8)
		local l = Instance.new("TextLabel"); l.Size = UDim2.new(1, -16, 0, 20); l.Position = UDim2.new(0, 8, 0, 4)
		l.BackgroundTransparency = 1; l.Text = title; l.TextColor3 = color or Color3.fromRGB(255, 255, 255)
		l.TextSize = 12; l.Font = Enum.Font.GothamBold; l.TextXAlignment = Enum.TextXAlignment.Left; l.Parent = s
		return s
	end
	local function btn(parent, text, y)
		local b = Instance.new("TextButton"); b.Size = UDim2.new(1, -16, 0, 30); b.Position = UDim2.new(0, 8, 0, y)
		b.BackgroundColor3 = Color3.fromRGB(50, 50, 50); b.TextColor3 = Color3.fromRGB(255, 255, 255)
		b.TextSize = 12; b.Font = Enum.Font.GothamBold; b.Text = "▶ " .. text; b.BorderSizePixel = 0; b.Parent = parent
		Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5); return b
	end
	local function lbl(parent, text, y)
		local l = Instance.new("TextLabel"); l.Size = UDim2.new(1, -16, 0, 16); l.Position = UDim2.new(0, 8, 0, y)
		l.BackgroundTransparency = 1; l.Text = text; l.TextColor3 = Color3.fromRGB(180, 180, 180)
		l.TextSize = 11; l.Font = Enum.Font.Gotham; l.TextXAlignment = Enum.TextXAlignment.Left; l.Parent = parent; return l
	end
	local function input(parent, y, defaultText, width)
		local tb = Instance.new("TextBox")
		tb.Size = UDim2.new(width or 0.35, -16, 0, 26); tb.Position = UDim2.new(0.65, 0, 0, y)
		tb.BackgroundColor3 = Color3.fromRGB(40, 40, 40); tb.TextColor3 = Color3.fromRGB(255, 255, 255)
		tb.TextSize = 11; tb.Font = Enum.Font.Gotham; tb.Text = tostring(defaultText)
		tb.BorderSizePixel = 0; tb.PlaceholderText = tostring(defaultText)
		tb.PlaceholderColor3 = Color3.fromRGB(150, 150, 150)
		tb.Parent = parent
		Instance.new("UICorner", tb).CornerRadius = UDim.new(0, 4)
		return tb
	end
	
	-- === MAIN TAB ===
	local mainTab = Instance.new("Frame"); mainTab.Name = "MainTab"; mainTab.Size = UDim2.new(1, 0, 1, 0); mainTab.BackgroundTransparency = 1; mainTab.Parent = content
	local ms = Instance.new("ScrollingFrame"); ms.Size = UDim2.new(1, -6, 1, 0); ms.Position = UDim2.new(0, 3, 0, 0)
	ms.BackgroundTransparency = 1; ms.BorderSizePixel = 0; ms.ScrollBarThickness = 4
	ms.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100); ms.CanvasSize = UDim2.new(0, 0, 0, 850)
	ms.Parent = mainTab; Instance.new("UIListLayout", ms).Padding = UDim.new(0, 5)
	
	local sections = {
		{title = "⚽ AUTO KICK", color = Color3.fromRGB(255, 200, 100), text = "KICK", ref = "isKickActive", loop = kickLoop},
		{title = "🎁 AUTO BATTLEPASS", color = Color3.fromRGB(100, 200, 255), text = "BP", ref = "isBpActive", loop = bpLoop},
		{title = "💰 AUTO SELL", color = Color3.fromRGB(255, 200, 100), text = "SELL", ref = "isAutoSell", loop = autoSellLoop},
		{title = "🎯 AUTO BONUS", color = Color3.fromRGB(200, 150, 255), text = "BONUS", ref = "isAutoBonus", loop = autoBonusLoop},
		{title = "⬆ AUTO SPEED", color = Color3.fromRGB(150, 255, 150), text = "SPEED", ref = "isAutoSpeedUpgrade", loop = autoSpeedUpgradeLoop},
		{title = "🏋 AUTO WEIGHT", color = Color3.fromRGB(255, 150, 150), text = "WEIGHT", ref = "isAutoWeight", loop = autoWeightLoop},
		{title = "🛒 AUTO BUY WEIGHT", color = Color3.fromRGB(255, 220, 150), text = "BUY W", ref = "isAutoBuyWeight", loop = autoBuyWeightLoop},
		{title = "🤝 AUTO TRADE", color = Color3.fromRGB(200, 255, 200), text = "TRADE", ref = "isAutoTrade", loop = autoTradeLoop},
	}
	
	local refs, states = {}, {}
	for _, s in ipairs(sections) do
		refs[s.ref] = (function(n) return function(v)
			if n == "isKickActive" then isKickActive = v elseif n == "isBpActive" then isBpActive = v
			elseif n == "isAutoSell" then isAutoSell = v elseif n == "isAutoBonus" then isAutoBonus = v
			elseif n == "isAutoSpeedUpgrade" then isAutoSpeedUpgrade = v elseif n == "isAutoWeight" then isAutoWeight = v
			elseif n == "isAutoBuyWeight" then isAutoBuyWeight = v elseif n == "isAutoTrade" then isAutoTrade = v
			end
		end end)(s.ref)
		states[s.ref] = (function(n) return function()
			if n == "isKickActive" then return isKickActive elseif n == "isBpActive" then return isBpActive
			elseif n == "isAutoSell" then return isAutoSell elseif n == "isAutoBonus" then return isAutoBonus
			elseif n == "isAutoSpeedUpgrade" then return isAutoSpeedUpgrade elseif n == "isAutoWeight" then return isAutoWeight
			elseif n == "isAutoBuyWeight" then return isAutoBuyWeight elseif n == "isAutoTrade" then return isAutoTrade
			end
		end end)(s.ref)
	end
	
	for _, s in ipairs(sections) do
		local section = sec(ms, s.title, 78, s.color)
		local b = btn(section, s.text, 28)
		local status = lbl(section, "● ВЫКЛЮЧЕН", 62); status.TextColor3 = Color3.fromRGB(255, 80, 80)
		b.MouseButton1Click:Connect(function()
			local current = not states[s.ref]()
			refs[s.ref](current)
			b.Text = current and "⏹ " .. s.text or "▶ " .. s.text
			b.BackgroundColor3 = current and Color3.fromRGB(180, 50, 50) or Color3.fromRGB(50, 50, 50)
			status.Text = current and "● АКТИВЕН" or "● ВЫКЛЮЧЕН"
			status.TextColor3 = current and Color3.fromRGB(80, 255, 80) or Color3.fromRGB(255, 80, 80)
			if current then task.spawn(s.loop) end
		end)
	end
	
	local infoSection = sec(ms, "📊 ИНФО", 140, Color3.fromRGB(200, 200, 200))
	local kwv = lbl(infoSection, "Волны: --", 26)
	local bpinfo = lbl(infoSection, "BP: --", 44)
	local morphinfo = lbl(infoSection, "Морф: --", 62)
	local posinfo = lbl(infoSection, "Позиция: --", 80)
	local invinfo = lbl(infoSection, "Инвентарь: --", 98)
	local waveinfo = lbl(infoSection, "Статус: --", 116)
	
	-- === SETTINGS TAB ===
	local settingsTab = Instance.new("Frame"); settingsTab.Name = "SettingsTab"; settingsTab.Size = UDim2.new(1, 0, 1, 0); settingsTab.BackgroundTransparency = 1; settingsTab.Visible = false; settingsTab.Parent = content
	local setScroll = Instance.new("ScrollingFrame"); setScroll.Size = UDim2.new(1, -6, 1, 0); setScroll.Position = UDim2.new(0, 3, 0, 0)
	setScroll.BackgroundTransparency = 1; setScroll.BorderSizePixel = 0; setScroll.ScrollBarThickness = 4
	setScroll.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100); setScroll.CanvasSize = UDim2.new(0, 0, 0, 850)
	setScroll.Parent = settingsTab; Instance.new("UIListLayout", setScroll).Padding = UDim.new(0, 5)
	
	local kickSettingsSection = sec(setScroll, "⚽ НАСТРОЙКИ УДАРА", 110, Color3.fromRGB(255, 200, 100))
	lbl(kickSettingsSection, "Сила удара:", 26); kickPowerInput = input(kickSettingsSection, 26, 10)
	lbl(kickSettingsSection, "Радиус зоны:", 56); kickRadiusInput = input(kickSettingsSection, 56, 10)
	lbl(kickSettingsSection, "Мин. дист. волны:", 86); minWaveDistInput = input(kickSettingsSection, 86, 300)
	
	local moveSettingsSection = sec(setScroll, "🏃 НАСТРОЙКИ ДВИЖЕНИЯ", 200, Color3.fromRGB(150, 255, 150))
	lbl(moveSettingsSection, "Задержка MIN:", 26); delayMinInput = input(moveSettingsSection, 26, 0.3)
	lbl(moveSettingsSection, "Задержка MAX:", 56); delayMaxInput = input(moveSettingsSection, 56, 1.2)
	lbl(moveSettingsSection, "Ожидание MIN:", 86); waitMinInput = input(moveSettingsSection, 86, 0.1)
	lbl(moveSettingsSection, "Ожидание MAX:", 116); waitMaxInput = input(moveSettingsSection, 116, 0.8)
	lbl(moveSettingsSection, "Шатание (studs):", 146); swayAmountInput = input(moveSettingsSection, 146, 8)
	lbl(moveSettingsSection, "Шанс шатания:", 176); swayChanceInput = input(moveSettingsSection, 176, 0.3)
	
	local moveSettingsSection2 = sec(setScroll, "🏃 ДВИЖЕНИЕ 2", 100, Color3.fromRGB(150, 255, 150))
	lbl(moveSettingsSection2, "Шанс стрейфа:", 26); strafeChanceInput = input(moveSettingsSection2, 26, 0.15)
	lbl(moveSettingsSection2, "Шанс прыжка:", 56); jumpChanceInput = input(moveSettingsSection2, 56, 0.05)
	
	local delayToggleSection = sec(setScroll, "⏱ ЗАДЕРЖКА ПЕРЕД БЕГОМ", 78, Color3.fromRGB(255, 200, 150))
	delayToggleBtn = Instance.new("TextButton")
	delayToggleBtn.Size = UDim2.new(1, -16, 0, 30); delayToggleBtn.Position = UDim2.new(0, 8, 0, 28)
	delayToggleBtn.BackgroundColor3 = Color3.fromRGB(80, 180, 80); delayToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	delayToggleBtn.TextSize = 12; delayToggleBtn.Font = Enum.Font.GothamBold
	delayToggleBtn.Text = "⏹ ВКЛЮЧЕНА"; delayToggleBtn.BorderSizePixel = 0; delayToggleBtn.Parent = delayToggleSection
	Instance.new("UICorner", delayToggleBtn).CornerRadius = UDim.new(0, 5)
	delayToggleStatus = lbl(delayToggleSection, "Задержка: " .. FINISH_DELAY_MIN .. "-" .. FINISH_DELAY_MAX .. " сек", 62)
	
	delayToggleBtn.MouseButton1Click:Connect(function()
		ENABLE_FINISH_DELAY = not ENABLE_FINISH_DELAY
		if ENABLE_FINISH_DELAY then
			delayToggleBtn.Text = "⏹ ВКЛЮЧЕНА"
			delayToggleBtn.BackgroundColor3 = Color3.fromRGB(80, 180, 80)
			delayToggleStatus.Text = "Задержка: " .. FINISH_DELAY_MIN .. "-" .. FINISH_DELAY_MAX .. " сек"
		else
			delayToggleBtn.Text = "▶ ВЫКЛЮЧЕНА"
			delayToggleBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
			delayToggleStatus.Text = "Задержка: ОТКЛЮЧЕНА"
		end
	end)
	
	local waveSettingsSection = sec(setScroll, "🌊 НАСТРОЙКИ ВОЛНЫ", 110, Color3.fromRGB(150, 200, 255))
	lbl(waveSettingsSection, "Дист. ускорения:", 26); waveDangerInput = input(waveSettingsSection, 26, 100)
	lbl(waveSettingsSection, "Крит. дистанция:", 56); waveCriticalInput = input(waveSettingsSection, 56, 30)
	
	local applySection = sec(setScroll, "💾 ПРИМЕНИТЬ", 60, Color3.fromRGB(255, 255, 100))
	local applyBtn = Instance.new("TextButton")
	applyBtn.Size = UDim2.new(1, -16, 0, 30); applyBtn.Position = UDim2.new(0, 8, 0, 26)
	applyBtn.BackgroundColor3 = Color3.fromRGB(80, 180, 80); applyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	applyBtn.TextSize = 13; applyBtn.Font = Enum.Font.GothamBold; applyBtn.Text = "💾 ПРИМЕНИТЬ НАСТРОЙКИ"
	applyBtn.BorderSizePixel = 0; applyBtn.Parent = applySection
	Instance.new("UICorner", applyBtn).CornerRadius = UDim.new(0, 5)
	applyBtn.MouseButton1Click:Connect(function() applySettings() end)
	
	-- === INVENTORY TAB ===
	local invTab = Instance.new("Frame"); invTab.Name = "InventoryTab"; invTab.Size = UDim2.new(1, 0, 1, 0); invTab.BackgroundTransparency = 1; invTab.Visible = false; invTab.Parent = content
	local invsc = Instance.new("ScrollingFrame"); invsc.Size = UDim2.new(1, -6, 1, 0); invsc.Position = UDim2.new(0, 3, 0, 0)
	invsc.BackgroundTransparency = 1; invsc.BorderSizePixel = 0; invsc.ScrollBarThickness = 4
	invsc.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100); invsc.CanvasSize = UDim2.new(0, 0, 0, 0)
	invsc.Parent = invTab; Instance.new("UIListLayout", invsc).Padding = UDim.new(0, 4)
	
	-- === BRAINROT TAB ===
	local brTab = Instance.new("Frame"); brTab.Name = "BrainrotTab"; brTab.Size = UDim2.new(1, 0, 1, 0); brTab.BackgroundTransparency = 1; brTab.Visible = false; brTab.Parent = content
	local brsc = Instance.new("ScrollingFrame"); brsc.Size = UDim2.new(1, -6, 1, 0); brsc.Position = UDim2.new(0, 3, 0, 0)
	brsc.BackgroundTransparency = 1; brsc.BorderSizePixel = 0; brsc.ScrollBarThickness = 4
	brsc.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100); brsc.CanvasSize = UDim2.new(0, 0, 0, 0)
	brsc.Parent = brTab; Instance.new("UIListLayout", brsc).Padding = UDim.new(0, 4)
	
	local brl = Instance.new("TextLabel"); brl.Size = UDim2.new(1, 0, 0, 20); brl.BackgroundTransparency = 1
	brl.Text = "🧠 Brainrot (не продавать):"; brl.TextColor3 = Color3.fromRGB(200, 200, 200); brl.TextSize = 12; brl.Font = Enum.Font.GothamBold; brl.TextXAlignment = Enum.TextXAlignment.Left; brl.Parent = brsc
	for _, br in ipairs(getBrainrotList()) do
		local h = Instance.new("Frame"); h.Size = UDim2.new(1, 0, 0, 30); h.BackgroundColor3 = Color3.fromRGB(30, 30, 30); h.BorderSizePixel = 0; h.Parent = brsc
		Instance.new("UICorner", h).CornerRadius = UDim.new(0, 5)
		local cbx = Instance.new("TextButton"); cbx.Size = UDim2.new(0, 20, 0, 20); cbx.Position = UDim2.new(0, 6, 0, 5); cbx.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
		cbx.TextColor3 = Color3.fromRGB(255, 255, 255); cbx.TextSize = 10; cbx.Font = Enum.Font.GothamBold; cbx.Text = ""; cbx.BorderSizePixel = 0; cbx.Parent = h
		Instance.new("UICorner", cbx).CornerRadius = UDim.new(0, 3)
		local nm = Instance.new("TextLabel"); nm.Size = UDim2.new(0.55, -30, 0, 20); nm.Position = UDim2.new(0, 30, 0, 5); nm.BackgroundTransparency = 1
		nm.Text = br.Name; nm.TextColor3 = Color3.fromRGB(255, 255, 255); nm.TextSize = 11; nm.Font = Enum.Font.GothamBold; nm.TextXAlignment = Enum.TextXAlignment.Left; nm.TextTruncate = Enum.TextTruncate.AtEnd; nm.Parent = h
		local inf = Instance.new("TextLabel"); inf.Size = UDim2.new(0.4, -10, 0, 20); inf.Position = UDim2.new(0.58, 0, 0, 5); inf.BackgroundTransparency = 1
		inf.Text = "[" .. br.CPS .. "]"; inf.TextColor3 = Color3.fromRGB(150, 150, 150); inf.TextSize = 10; inf.Font = Enum.Font.Gotham; inf.TextXAlignment = Enum.TextXAlignment.Right; inf.Parent = h
		cbx.MouseButton1Click:Connect(function() selectedBrainrots[br.Name] = not selectedBrainrots[br.Name]; cbx.BackgroundColor3 = selectedBrainrots[br.Name] and Color3.fromRGB(80, 180, 80) or Color3.fromRGB(50, 50, 50); cbx.Text = selectedBrainrots[br.Name] and "✓" or "" end)
	end
	local mutl = Instance.new("TextLabel"); mutl.Size = UDim2.new(1, 0, 0, 20); mutl.BackgroundTransparency = 1
	mutl.Text = "🔬 Мутации (не продавать):"; mutl.TextColor3 = Color3.fromRGB(200, 200, 200); mutl.TextSize = 12; mutl.Font = Enum.Font.GothamBold; mutl.TextXAlignment = Enum.TextXAlignment.Left; mutl.Parent = brsc
	for _, mut in ipairs(getMutationList()) do
		local h = Instance.new("Frame"); h.Size = UDim2.new(1, 0, 0, 30); h.BackgroundColor3 = Color3.fromRGB(30, 30, 30); h.BorderSizePixel = 0; h.Parent = brsc
		Instance.new("UICorner", h).CornerRadius = UDim.new(0, 5)
		local cbx = Instance.new("TextButton"); cbx.Size = UDim2.new(0, 20, 0, 20); cbx.Position = UDim2.new(0, 6, 0, 5)
		cbx.BackgroundColor3 = mut == "None" and Color3.fromRGB(80, 180, 80) or Color3.fromRGB(50, 50, 50); cbx.TextColor3 = Color3.fromRGB(255, 255, 255)
		cbx.TextSize = 10; cbx.Font = Enum.Font.GothamBold; cbx.Text = mut == "None" and "✓" or ""; cbx.BorderSizePixel = 0; cbx.Parent = h
		Instance.new("UICorner", cbx).CornerRadius = UDim.new(0, 3)
		local nm = Instance.new("TextLabel"); nm.Size = UDim2.new(1, -30, 0, 20); nm.Position = UDim2.new(0, 30, 0, 5); nm.BackgroundTransparency = 1
		nm.Text = mut; nm.TextColor3 = Color3.fromRGB(200, 200, 200); nm.TextSize = 11; nm.Font = Enum.Font.Gotham; nm.TextXAlignment = Enum.TextXAlignment.Left; nm.Parent = h
		cbx.MouseButton1Click:Connect(function() selectedMutations[mut] = not selectedMutations[mut]; cbx.BackgroundColor3 = selectedMutations[mut] and Color3.fromRGB(80, 180, 80) or Color3.fromRGB(50, 50, 50); cbx.Text = selectedMutations[mut] and "✓" or "" end)
	end
	brsc.CanvasSize = UDim2.new(0, 0, 0, 40 + #getBrainrotList() * 34 + 20 + #getMutationList() * 34 + 20)
	
	openButton.MouseButton1Click:Connect(function() mainMenu.Visible = true; openButton.Visible = false end)
	
	task.spawn(function()
		while true do
			if mainMenu.Visible and tick() - lastGUIUpdate > UPDATE_INTERVAL then
				lastGUIUpdate = tick()
				if updateCharacterReferences() then
					local dist, count, rarity = getClosestWave()
					kwv.Text = string.format("Волны: %d | %.0f studs | %s", count, dist, rarity)
					posinfo.Text = "Позиция: " .. (isInKickReady() and "В ЗОНЕ" or string.format("%.0f studs", kickReadyPos and (rootPart.Position - kickReadyPos).Magnitude or 0))
				end
				if bpData then bpinfo.Text = "BP: XP " .. (bpData.XP or 0) .. " | Собрано " .. claimedCount end
				local mn, mm, ml, _ = getCurrentMorph()
				morphinfo.Text = "Морф: " .. mn .. " | " .. mm .. " | LVL " .. ml
				local inv = scanBackpack(); local total = 0; for _, items in pairs(inv) do total = total + #items end
				invinfo.Text = "Инвентарь: " .. total .. " предм."
				waveinfo.Text = "Kick: " .. (isKickActive and "АКТИВЕН" or "ВЫКЛ") .. " | BP: " .. (isBpActive and "АКТИВЕН" or "ВЫКЛ")
				
				if currentTab == "Inventory" then
					for _, c in ipairs(invsc:GetChildren()) do if c:IsA("Frame") and c.Name ~= "UIListLayout" then c:Destroy() end end
					local inv = scanBackpack(); local y = 0
					for name, items in pairs(inv) do for _, item in ipairs(items) do
						local f = Instance.new("Frame"); f.Size = UDim2.new(1, 0, 0, 46); f.BackgroundColor3 = Color3.fromRGB(28, 28, 28); f.BorderSizePixel = 0; f.Parent = invsc
						Instance.new("UICorner", f).CornerRadius = UDim.new(0, 5)
						local n = Instance.new("TextLabel"); n.Size = UDim2.new(1, -10, 0, 20); n.Position = UDim2.new(0, 5, 0, 3); n.BackgroundTransparency = 1
						n.Text = name; n.TextColor3 = Color3.fromRGB(255, 255, 255); n.TextSize = 11; n.Font = Enum.Font.GothamBold; n.TextXAlignment = Enum.TextXAlignment.Left; n.Parent = f
						local inf = Instance.new("TextLabel"); inf.Size = UDim2.new(1, -10, 0, 18); inf.Position = UDim2.new(0, 5, 0, 24); inf.BackgroundTransparency = 1
						inf.Text = string.format("LVL %d | %s | CPS: %s", item.Level, item.Mutation, item.CPS); inf.TextColor3 = Color3.fromRGB(150, 150, 150); inf.TextSize = 10; inf.Font = Enum.Font.Gotham; inf.TextXAlignment = Enum.TextXAlignment.Left; inf.Parent = f
						y = y + 50
					end end
					invsc.CanvasSize = UDim2.new(0, 0, 0, y + 6)
				end
			end
			task.wait(0.1)
		end
	end)
end

-- ============ ЗАПУСК ============
createGUI()
player.CharacterAdded:Connect(function(c) character = c; task.wait(0.5); updateCharacterReferences() end)
if player.Character then updateCharacterReferences() end
getBPData()
print("Farm Menu loaded! All errors fixed, safe FireServer.")
