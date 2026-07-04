-- Ultimate Farm Script - Final Version
-- Pathfinding до старта, живой бег к финишу, ускорение от волны
-- Если волна близко - бежать прямо без остановок

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local CoreGui = game:GetService("CoreGui")
local VirtualInputManager = game:GetService("VirtualInputManager")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- ============ КОНСТАНТЫ ============
local KICK_POWER = 10
local KICK_READY_RADIUS = 10
local MIN_WAVE_DISTANCE = 300
local MOVEMENT_TIMEOUT = 30
local JUMP_COOLDOWN = 0.5
local UPDATE_INTERVAL = 0.3
local CAMERA_WAIT_TIMEOUT = 5
local FINISH_DELAY_MIN = 0.3
local FINISH_DELAY_MAX = 1.2
local FINISH_SPEED_MIN = 20
local FINISH_SPEED_MAX = 30
local FINISH_WAIT_MIN = 0.1
local FINISH_WAIT_MAX = 0.8
local SWAY_AMOUNT = 8
local SWAY_CHANCE = 0.3
local STRAFE_CHANCE = 0.15
local STOP_CHANCE = 0.05

-- Волна: если ближе этого расстояния - бежим прямо на максимальной скорости
local WAVE_DANGER_DISTANCE = 100
local WAVE_DANGER_SPEED = 35

-- ============ ПЕРЕМЕННЫЕ ============
local character, humanoid, rootPart
local kickReadyPart, kickReadyPos
local revKickEvent
local isKickActive, isBpActive, isAutoSell, isAutoBonus = false, false, false, false
local isAutoSpeedUpgrade, isAutoWeight, isAutoBuyWeight, isAutoTradeBallberto = false, false, false, false
local lastJumpTime, baseWalkSpeed = 0, 16
local bpData, claimedCount = nil, 0
local selectedBrainrots = {}
local selectedMutations = {["None"] = true}
local lastGUIUpdate = 0

-- GUI элементы
local screenGui, openButton, mainMenu
local kickToggle, kickStatus, kickWaveLabel
local bpToggle, bpStatus, bpInfoLabel
local sellToggle, sellStatus
local bonusToggle, bonusStatus
local speedUpgradeToggle, speedUpgradeStatus
local weightToggle, weightStatus
local buyWeightToggle, buyWeightStatus
local tradeToggle, tradeStatus
local currentTab = "Main"

-- ============ БЕЗОПАСНЫЕ ФУНКЦИИ ДАННЫХ ============
local EntitiesData, MutationData
pcall(function() EntitiesData = require(ReplicatedStorage.Shared.Data.EntitiesData) end)
pcall(function() MutationData = require(ReplicatedStorage.Shared.Data.MutationData) end)

local function safeCPS(name)
	if not EntitiesData then return 0 end
	if not EntitiesData.Brainrots then return 0 end
	local data = EntitiesData.Brainrots[name]
	if not data then return 0 end
	local cpsRaw = data.CPS
	if not cpsRaw then return 0 end
	local num = nil
	pcall(function() if type(cpsRaw) == "table" and cpsRaw.Value then num = tonumber(tostring(cpsRaw.Value)) end end)
	if not num and type(cpsRaw) == "string" then num = tonumber(cpsRaw:gsub(",", ""):gsub("%s", "")) end
	if not num and type(cpsRaw) == "number" then num = cpsRaw end
	if not num then num = tonumber(tostring(cpsRaw):gsub(",", ""):gsub("%s", ""):gsub("[^%d.]", "")) end
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

local function isWaveDangerous()
	local dist = getClosestWave()
	return dist < WAVE_DANGER_DISTANCE
end

local function isCameraOnPlayer()
	if not rootPart then return false end
	local camPos = camera.CFrame.Position
	local playerPos = rootPart.Position
	local dist = (camPos - playerPos).Magnitude
	return dist < 50 and camera.CameraType == Enum.CameraType.Custom
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

-- ============ KICK ============
local function initKickRefs()
	local areas = workspace:FindFirstChild("Areas")
	if areas then kickReadyPart = areas:FindFirstChild("KickReady"); if kickReadyPart then kickReadyPos = kickReadyPart.Position end end
	local net = findNetwork()
	if net then revKickEvent = net:FindFirstChild("rev_KickEvent") end
end

-- Движение К СТАРТУ (Pathfinding)
local function moveToKickReady()
	if not updateCharacterReferences() then return false end
	if not humanoid or not rootPart or not kickReadyPos then return false end
	if humanoid.Health <= 0 then return false end
	if isInKickReady() then return true end
	
	local path = PathfindingService:CreatePath({
		AgentRadius = 2, AgentHeight = 5, AgentCanJump = true,
		AgentMaxSlope = 45, WaypointSpacing = 3, Costs = {Water = 20}
	})
	
	local success = pcall(function() path:ComputeAsync(rootPart.Position, kickReadyPos) end)
	
	if success and path.Status == Enum.PathStatus.Success then
		local waypoints = path:GetWaypoints()
		humanoid.WalkSpeed = 24; humanoid.AutoRotate = true
		for _, wp in ipairs(waypoints) do
			if not isKickActive or not updateCharacterReferences() then return false end
			if humanoid.Health <= 0 then return false end
			if isInKickReady() then return true end
			humanoid:MoveTo(wp.Position)
			local wpStart, lp = tick(), rootPart.Position
			while isKickActive and tick() - wpStart < 5 do
				if not updateCharacterReferences() or humanoid.Health <= 0 then return false end
				if isInKickReady() then return true end
				if (rootPart.Position - wp.Position).Magnitude <= 3 then break end
				if (rootPart.Position - lp).Magnitude < 0.3 then
					if tick() - lastJumpTime > JUMP_COOLDOWN then humanoid.Jump = true; lastJumpTime = tick() end
				else lp = rootPart.Position end
				task.wait(0.1)
			end
		end
	else
		humanoid.WalkSpeed = 24; humanoid.AutoRotate = true; humanoid:MoveTo(kickReadyPos)
		local st = tick()
		while isKickActive and tick() - st < MOVEMENT_TIMEOUT do
			if not updateCharacterReferences() or humanoid.Health <= 0 then return false end
			if isInKickReady() then return true end
			if tick() - lastJumpTime > JUMP_COOLDOWN then humanoid.Jump = true; lastJumpTime = tick() end
			humanoid:MoveTo(kickReadyPos); task.wait(0.1)
		end
	end
	return isInKickReady()
end

-- Движение К ФИНИШУ (живое, но если волна близко - бежим прямо на максималке)
local function moveToFinish()
	if not updateCharacterReferences() then return false end
	if not humanoid or not rootPart or not kickReadyPos then return false end
	if humanoid.Health <= 0 then return false end
	if isInKickReady() then return true end
	
	waitForCameraOnPlayer()
	
	-- Задержка перед бегом (только если волна не опасна)
	if not isWaveDangerous() then
		local delay = FINISH_DELAY_MIN + math.random() * (FINISH_DELAY_MAX - FINISH_DELAY_MIN)
		local delayStart = tick()
		while isKickActive and tick() - delayStart < delay do
			if not updateCharacterReferences() then return false end
			if isInKickReady() then return true end
			if isWaveDangerous() then break end -- Волна близко - прекращаем ждать
			task.wait(0.05)
		end
	end
	
	-- Переменные для живого движения
	local swayDirection = 0
	local isStopped = false
	local stopTimer = 0
	
	while isKickActive do
		if not updateCharacterReferences() then return false end
		if humanoid.Health <= 0 then return false end
		if isInKickReady() then return true end
		
		-- ПРОВЕРКА ВОЛНЫ: если близко - бежим прямо на максимальной скорости
		local waveDanger = isWaveDangerous()
		
		if waveDanger then
			-- ОПАСНОСТЬ: бежим прямо к финишу на максимальной скорости
			humanoid.WalkSpeed = WAVE_DANGER_SPEED
			humanoid.AutoRotate = true
			humanoid:MoveTo(kickReadyPos)
			isStopped = false -- Не стоим когда волна близко
			
			-- Чаще прыгаем для скорости
			if tick() - lastJumpTime > 0.3 then
				humanoid.Jump = true
				lastJumpTime = tick()
			end
		else
			-- БЕЗОПАСНО: живое движение
			if isStopped then
				humanoid:MoveTo(rootPart.Position)
				stopTimer = stopTimer + 0.1
				if stopTimer > 1 then isStopped = false; stopTimer = 0 end
			else
				-- Шанс остановиться
				if math.random() < STOP_CHANCE then
					isStopped = true; stopTimer = 0
				else
					-- Шанс сменить направление шатания
					if math.random() < SWAY_CHANCE then
						swayDirection = math.random(-1, 1)
					end
					
					-- Шанс пойти боком
					if math.random() < STRAFE_CHANCE then
						swayDirection = math.random() < 0.5 and -1 or 1
					end
					
					-- Вычисляем цель с шатанием
					local targetPos = kickReadyPos
					if swayDirection ~= 0 then
						local forward = (kickReadyPos - rootPart.Position).Unit
						local right = Vector3.new(-forward.Z, 0, forward.X)
						targetPos = targetPos + right * swayDirection * SWAY_AMOUNT
					end
					
					humanoid:MoveTo(targetPos)
					
					-- Случайная скорость
					local speed = FINISH_SPEED_MIN + math.random() * (FINISH_SPEED_MAX - FINISH_SPEED_MIN)
					humanoid.WalkSpeed = speed
					
					-- Случайный прыжок
					if math.random() < 0.05 then
						if tick() - lastJumpTime > JUMP_COOLDOWN then
							humanoid.Jump = true; lastJumpTime = tick()
						end
					end
				end
			end
		end
		
		-- Проверка застревания
		if humanoid.MoveDirection.Magnitude < 0.1 and not isStopped then
			if tick() - lastJumpTime > JUMP_COOLDOWN then
				humanoid.Jump = true; lastJumpTime = tick()
			end
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
			if inGame == nil and kd == nil then moveToKickReady() else moveToFinish() end
		end
		
		-- Удар с случайной задержкой
		if isInKickReady() and inGame == nil and kd == nil then
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
	local net = findNetwork()
	if not net then return false end
	return pcall(function() net.FireServer("SELL_ENTITY", guid) end)
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
	local WeightServiceClient, Network, WeightsData
	pcall(function() WeightServiceClient = require(ReplicatedStorage.Modules.ServicesLoader.WeightServiceClient) end)
	pcall(function() Network = require(ReplicatedStorage.Shared.Packages.Network) end)
	pcall(function() WeightsData = require(ReplicatedStorage.Shared.Data.WeightsData) end)
	while isAutoWeight do
		if WeightServiceClient and WeightsData then
			pcall(function()
				local best, bestPPS = nil, 0
				for _, name in ipairs(WeightServiceClient.Owned or {}) do
					local data = WeightsData.Weights[name]
					if data and data.PPS and data.PPS > bestPPS then bestPPS = data.PPS; best = name end
				end
				if best and best ~= WeightServiceClient.Equipped and Network then Network.FireServer("WeightEquip", best) end
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

-- ============ AUTO TRADE BALLBERTO ============
local function autoTradeBallbertoLoop()
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
	
	local function checkBallberto()
		if not player.Backpack then return false, nil end
		for _, item in ipairs(player.Backpack:GetChildren()) do
			if item:IsA("Tool") and item.Name == "Ballberto" and item:HasTag("EntityTool") then return item:GetAttribute("GUID"), item end
		end
		return false, nil
	end
	
	Network.OnClientEvent("trade_n"):Connect(function(userId, time)
		if isAutoTradeBallberto and targetUserId and userId == targetUserId then
			pcall(function() Network.FireServer("trade_start", userId) end); tradeStarted = true; itemAdded = false
		end
	end)
	
	Network.OnClientEvent("trade_s"):Connect(function(status, ...)
		if not isAutoTradeBallberto then return end
		if status == "Trading" then
			if not itemAdded then task.wait(0.3); local guid, _ = checkBallberto(); if guid then pcall(function() Network.FireServer("trade_i", "AddItem", guid) end); itemAdded = true end end
			task.wait(0.3); pcall(function() Network.FireServer("trade_i", "Confirm") end)
		elseif status == "Cancelled" then tradeStarted, itemAdded, tradeCompleted = false, false, false end
	end)
	
	Network.OnClientEvent("trade_u"):Connect(function(data)
		if not isAutoTradeBallberto or not data then return end
		if data.Stage == "Process" then tradeCompleted = true
		elseif data.Stage == "Final" then task.wait(0.2); pcall(function() Network.FireServer("trade_i", "Confirm") end)
		elseif data.Stage == "Trade" and not itemAdded then local guid, _ = checkBallberto(); if guid then pcall(function() Network.FireServer("trade_i", "AddItem", guid) end); itemAdded = true end end
	end)
	
	while isAutoTradeBallberto do
		local guid, _ = checkBallberto()
		if guid and not tradeCompleted then
			if findTargetPlayer() and not tradeStarted then pcall(function() Network.FireServer("trade_r", targetUserId) end); tradeStarted = true; task.wait(2) end
		elseif tradeCompleted then tradeStarted, itemAdded, tradeCompleted = false, false, false end
		task.wait(3)
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
	mainMenu.Size = UDim2.new(0, 340, 0, 480); mainMenu.Position = UDim2.new(0.5, -170, 0.06, 0)
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
	
	local content = Instance.new("Frame"); content.Size = UDim2.new(1, 0, 1, -40); content.Position = UDim2.new(0, 0, 0, 40); content.BackgroundTransparency = 1; content.Parent = mainMenu
	local scroll = Instance.new("ScrollingFrame"); scroll.Size = UDim2.new(1, -6, 1, 0); scroll.Position = UDim2.new(0, 3, 0, 0)
	scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0; scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100); scroll.CanvasSize = UDim2.new(0, 0, 0, 800)
	scroll.Parent = content; Instance.new("UIListLayout", scroll).Padding = UDim.new(0, 5)
	
	local function sec(title, h, color)
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
	
	local sections = {
		{title = "⚽ AUTO KICK (WaveSafe)", color = Color3.fromRGB(255, 200, 100), text = "KICK", ref = "isKickActive", loop = kickLoop},
		{title = "🎁 AUTO BATTLEPASS", color = Color3.fromRGB(100, 200, 255), text = "BP", ref = "isBpActive", loop = bpLoop},
		{title = "💰 AUTO SELL", color = Color3.fromRGB(255, 200, 100), text = "SELL", ref = "isAutoSell", loop = autoSellLoop},
		{title = "🎯 AUTO BONUS", color = Color3.fromRGB(200, 150, 255), text = "BONUS", ref = "isAutoBonus", loop = autoBonusLoop},
		{title = "⬆ AUTO SPEED", color = Color3.fromRGB(150, 255, 150), text = "SPEED", ref = "isAutoSpeedUpgrade", loop = autoSpeedUpgradeLoop},
		{title = "🏋 AUTO WEIGHT", color = Color3.fromRGB(255, 150, 150), text = "WEIGHT", ref = "isAutoWeight", loop = autoWeightLoop},
		{title = "🛒 AUTO BUY WEIGHT", color = Color3.fromRGB(255, 220, 150), text = "BUY W", ref = "isAutoBuyWeight", loop = autoBuyWeightLoop},
		{title = "🤝 TRADE BALLBERTO", color = Color3.fromRGB(200, 255, 200), text = "TRADE", ref = "isAutoTradeBallberto", loop = autoTradeBallbertoLoop},
	}
	
	local refs, states = {}, {}
	for _, s in ipairs(sections) do
		refs[s.ref] = (function(n) return function(v)
			if n == "isKickActive" then isKickActive = v elseif n == "isBpActive" then isBpActive = v
			elseif n == "isAutoSell" then isAutoSell = v elseif n == "isAutoBonus" then isAutoBonus = v
			elseif n == "isAutoSpeedUpgrade" then isAutoSpeedUpgrade = v elseif n == "isAutoWeight" then isAutoWeight = v
			elseif n == "isAutoBuyWeight" then isAutoBuyWeight = v elseif n == "isAutoTradeBallberto" then isAutoTradeBallberto = v
			end
		end end)(s.ref)
		states[s.ref] = (function(n) return function()
			if n == "isKickActive" then return isKickActive elseif n == "isBpActive" then return isBpActive
			elseif n == "isAutoSell" then return isAutoSell elseif n == "isAutoBonus" then return isAutoBonus
			elseif n == "isAutoSpeedUpgrade" then return isAutoSpeedUpgrade elseif n == "isAutoWeight" then return isAutoWeight
			elseif n == "isAutoBuyWeight" then return isAutoBuyWeight elseif n == "isAutoTradeBallberto" then return isAutoTradeBallberto
			end
		end end)(s.ref)
	end
	
	for _, s in ipairs(sections) do
		local section = sec(s.title, 78, s.color)
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
	
	local infoSection = sec("📊 ИНФО", 140, Color3.fromRGB(200, 200, 200))
	local kwv = lbl(infoSection, "Волны: --", 26)
	local bpinfo = lbl(infoSection, "BP: --", 44)
	local morphinfo = lbl(infoSection, "Морф: --", 62)
	local posinfo = lbl(infoSection, "Позиция: --", 80)
	local invinfo = lbl(infoSection, "Инвентарь: --", 98)
	local waveinfo = lbl(infoSection, "Статус: --", 116)
	
	scroll.CanvasSize = UDim2.new(0, 0, 0, #sections * 83 + 150)
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
print("Farm Menu loaded! Wave-safe: danger = full speed straight.")
