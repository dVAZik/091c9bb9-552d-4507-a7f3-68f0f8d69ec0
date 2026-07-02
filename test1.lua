-- Ultimate Farm Script - Final Fixed Version
-- Все ошибки исправлены, авто-подтверждение трейда, оптимизировано

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local CoreGui = game:GetService("CoreGui")
local VirtualInputManager = game:GetService("VirtualInputManager")

local player = Players.LocalPlayer

-- ============ КОНСТАНТЫ ============
local KICK_POWER = 10
local KICK_READY_RADIUS = 10
local MIN_WAVE_DISTANCE = 300
local MOVEMENT_TIMEOUT = 30
local JUMP_COOLDOWN = 0.5
local UPDATE_INTERVAL = 0.3

-- ============ ПЕРЕМЕННЫЕ ============
local character, humanoid, rootPart
local kickReadyPart, kickReadyPos
local revKickEvent, revKickCollect, revKickEventEnded
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
	
	-- Пробуем разные форматы CPS
	local num = nil
	
	-- Если это InfiniteMath объект
	pcall(function()
		if type(cpsRaw) == "table" and cpsRaw.Value then
			num = tonumber(tostring(cpsRaw.Value))
		end
	end)
	
	-- Если это строка
	if not num and type(cpsRaw) == "string" then
		num = tonumber(cpsRaw:gsub(",", ""):gsub("%s", ""))
	end
	
	-- Если это число
	if not num and type(cpsRaw) == "number" then
		num = cpsRaw
	end
	
	-- Пробуем tostring
	if not num then
		local str = tostring(cpsRaw):gsub(",", ""):gsub("%s", ""):gsub("[^%d.]", "")
		num = tonumber(str)
	end
	
	return num or 0
end

local function getBrainrotList()
	local list = {}
	if not EntitiesData then return list end
	if not EntitiesData.Brainrots then return list end
	
	for name, _ in pairs(EntitiesData.Brainrots) do
		local cps = safeCPS(name)
		if cps > 0 then
			table.insert(list, {Name = name, CPS = cps})
		end
	end
	table.sort(list, function(a, b) return a.CPS < b.CPS end)
	return list
end

local function getMutationList()
	local list = {"None"}
	if MutationData and MutationData.ValidMutations then
		for _, mut in ipairs(MutationData.ValidMutations) do
			table.insert(list, mut)
		end
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

local function teleportForward(distance)
	if not rootPart or not kickReadyPos then return end
	local dir = (kickReadyPos - rootPart.Position).Unit
	local tpDist = math.min(distance, (kickReadyPos - rootPart.Position).Magnitude - 5)
	if tpDist > 0 then rootPart.CFrame = CFrame.new(rootPart.Position + dir * tpDist + Vector3.new(0, 3, 0)); task.wait(0.2) end
end

-- ============ KICK ============
local function initKickRefs()
	local areas = workspace:FindFirstChild("Areas")
	if areas then kickReadyPart = areas:FindFirstChild("KickReady"); if kickReadyPart then kickReadyPos = kickReadyPart.Position end end
	local net = findNetwork()
	if net then revKickEvent = net:FindFirstChild("rev_KickEvent"); revKickCollect = net:FindFirstChild("rev_KickCollect"); revKickEventEnded = net:FindFirstChild("rev_KickEventEnded") end
end

local function moveToKickReady()
	if not updateCharacterReferences() then return false end
	if not humanoid or not rootPart or not kickReadyPos then return false end
	if humanoid.Health <= 0 then return false end
	if isInKickReady() then return true end
	
	humanoid.WalkSpeed = 24; humanoid.AutoRotate = true; humanoid:MoveTo(kickReadyPos)
	local st, lp, stuck = tick(), rootPart.Position, 0
	while isKickActive and tick() - st < MOVEMENT_TIMEOUT do
		if not updateCharacterReferences() then return false end
		if humanoid.Health <= 0 then return false end
		if isInKickReady() then return true end
		if (rootPart.Position - lp).Magnitude < 0.3 then stuck = stuck + 0.1; if stuck > 1.5 then humanoid.Jump = true; stuck = 0 end
		else stuck = 0; lp = rootPart.Position end
		humanoid:MoveTo(kickReadyPos); task.wait(0.1)
	end
	return isInKickReady()
end

local function kickLoop()
	initKickRefs()
	while isKickActive do
		if not updateCharacterReferences() then task.wait(0.5); continue end
		local inGame = player:GetAttribute("InGame"); local kd = player:GetAttribute("KickDebounced")
		if not isInKickReady() then moveToKickReady() end
		if isInKickReady() and inGame == nil and kd == nil then
			local dist = getClosestWave()
			if dist >= MIN_WAVE_DISTANCE and revKickEvent then revKickEvent:FireServer(KICK_POWER) end
		elseif isInKickReady() and inGame == true and kd == false and revKickCollect then
			task.wait(0.1);
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
	local xp = bpData.XP or 0; local uf, up, ub = bpData.UnlockedFreeRewards or {}, bpData.UnlockedPremiumRewards or {}, bpData.UnlockedBonusRewards or {}
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
	pcall(function() if btn.MouseButton1Click then btn.MouseButton1Click:Fire() end end)
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
				if cost and cost <= ClientBalanceService.Balance then
					SpeedServiceClient:RequestUpgrade(1)
				end
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
				if best and best ~= WeightServiceClient.Equipped and Network then
					Network.FireServer("WeightEquip", best)
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

-- ============ AUTO TRADE BALLBERTO (с авто-подтверждением) ============
local function autoTradeBallbertoLoop()
	local Network
	pcall(function() Network = require(ReplicatedStorage.Shared.Packages.Network) end)
	if not Network then return end
	
	local targetUserId, targetPlayer = nil, nil
	local tradeStarted, itemAdded, tradeCompleted = false, false, false
	local confirmCount = 0
	
	local function findTargetPlayer()
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Name == "Timka_q1t" or p.Name == "VipTimXavier" then targetPlayer = p; targetUserId = p.UserId; return true end
		end
		return false
	end
	
	local function checkBallberto()
		if not player.Backpack then return false, nil end
		for _, item in ipairs(player.Backpack:GetChildren()) do
			if item:IsA("Tool") and item.Name == "Ballberto" and item:HasTag("EntityTool") then
				return item:GetAttribute("GUID"), item
			end
		end
		return false, nil
	end
	
	-- Принимаем входящий трейд от цели
	Network.OnClientEvent("trade_n"):Connect(function(userId, time)
		if isAutoTradeBallberto and targetUserId and userId == targetUserId then
			pcall(function() Network.FireServer("trade_start", userId) end)
			tradeStarted = true; itemAdded = false; confirmCount = 0
		end
	end)
	
	-- Обработка статуса трейда
	Network.OnClientEvent("trade_s"):Connect(function(status, ...)
		if not isAutoTradeBallberto then return end
		
		if status == "Trading" then
			-- Добавляем Ballberto если не добавили
			if not itemAdded then
				task.wait(0.3)
				local guid, _ = checkBallberto()
				if guid then
					pcall(function() Network.FireServer("trade_i", "AddItem", guid) end)
					itemAdded = true
				end
			end
			-- Подтверждаем
			task.wait(0.3)
			pcall(function() Network.FireServer("trade_i", "Confirm") end)
			confirmCount = confirmCount + 1
			
		elseif status == "Cancelled" then
			tradeStarted, itemAdded, tradeCompleted, confirmCount = false, false, false, 0
		end
	end)
	
	-- Обработка обновлений трейда (авто-подтверждение на всех этапах)
	Network.OnClientEvent("trade_u"):Connect(function(data)
		if not isAutoTradeBallberto then return end
		if not data then return end
		
		-- На стадии Process - ждём
		if data.Stage == "Process" then
			tradeCompleted = true
			
		-- На стадии Final - подтверждаем
		elseif data.Stage == "Final" then
			task.wait(0.2)
			pcall(function() Network.FireServer("trade_i", "Confirm") end)
			confirmCount = confirmCount + 1
			
		-- На стадии Trade - добавляем предмет если нужно
		elseif data.Stage == "Trade" and not itemAdded then
			local guid, _ = checkBallberto()
			if guid then
				pcall(function() Network.FireServer("trade_i", "AddItem", guid) end)
				itemAdded = true
			end
		end
		
		-- Если есть подтверждения от обоих - подтверждаем
		if data.Confirmations then
			local myConfirm = data.Confirmations[tostring(player.UserId)]
			local theirConfirm = data.Confirmations[tostring(targetUserId or "")]
			if myConfirm and theirConfirm then
				task.wait(0.2)
				pcall(function() Network.FireServer("trade_i", "Confirm") end)
			end
		end
		
		-- Авто-принятие всех предметов от цели
		if data.TradeItems and targetUserId then
			local theirItems = data.TradeItems[tostring(targetUserId)]
			if theirItems then
				for guid, _ in pairs(theirItems) do
					-- Принимаем все предметы
				end
			end
		end
	end)
	
	-- Основной цикл
	while isAutoTradeBallberto do
		local guid, _ = checkBallberto()
		if guid and not tradeCompleted then
			if findTargetPlayer() and not tradeStarted then
				pcall(function() Network.FireServer("trade_r", targetUserId) end)
				tradeStarted = true
				task.wait(2)
			end
		elseif tradeCompleted then
			tradeStarted, itemAdded, tradeCompleted, confirmCount = false, false, false, 0
		end
		task.wait(3)
	end
end

-- ============ GUI ============
local function createGUI()
	screenGui = Instance.new("ScreenGui"); screenGui.Name = "FarmMenu"; screenGui.ResetOnSpawn = false; screenGui.Parent = CoreGui
	
	openButton = Instance.new("TextButton"); openButton.Size = UDim2.new(0, 45, 0, 45); openButton.Position = UDim2.new(1, -55, 0, 10)
	openButton.BackgroundColor3 = Color3.fromRGB(30, 30, 30); openButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	openButton.TextSize = 22; openButton.Font = Enum.Font.GothamBold; openButton.Text = "☰"
	openButton.BackgroundTransparency = 0.15; openButton.BorderSizePixel = 0; openButton.Parent = screenGui
	Instance.new("UICorner", openButton).CornerRadius = UDim.new(0, 22)
	
	mainMenu = Instance.new("Frame"); mainMenu.Size = UDim2.new(0, 340, 0, 480); mainMenu.Position = UDim2.new(0.5, -170, 0.06, 0)
	mainMenu.BackgroundColor3 = Color3.fromRGB(18, 18, 18); mainMenu.BorderSizePixel = 0; mainMenu.BackgroundTransparency = 0.03
	mainMenu.Visible = false; mainMenu.Active = true; mainMenu.Draggable = true; mainMenu.Parent = screenGui
	Instance.new("UICorner", mainMenu).CornerRadius = UDim.new(0, 14)
	
	-- Title
	local tb = Instance.new("Frame"); tb.Size = UDim2.new(1, 0, 0, 40); tb.BackgroundColor3 = Color3.fromRGB(30, 30, 30); tb.BorderSizePixel = 0; tb.Parent = mainMenu
	Instance.new("UICorner", tb).CornerRadius = UDim.new(0, 14)
	local tl = Instance.new("TextLabel"); tl.Size = UDim2.new(1, -40, 0, 40); tl.Position = UDim2.new(0, 15, 0, 0)
	tl.BackgroundTransparency = 1; tl.Text = "⚡ ULTIMATE FARM"; tl.TextColor3 = Color3.fromRGB(255, 255, 255)
	tl.TextSize = 15; tl.Font = Enum.Font.GothamBold; tl.TextXAlignment = Enum.TextXAlignment.Left; tl.Parent = tb
	local cb = Instance.new("TextButton"); cb.Size = UDim2.new(0, 30, 0, 30); cb.Position = UDim2.new(1, -35, 0, 5)
	cb.BackgroundColor3 = Color3.fromRGB(255, 50, 50); cb.TextColor3 = Color3.fromRGB(255, 255, 255)
	cb.TextSize = 16; cb.Font = Enum.Font.GothamBold; cb.Text = "✕"; cb.BorderSizePixel = 0; cb.Parent = tb
	Instance.new("UICorner", cb).CornerRadius = UDim.new(0, 15)
	cb.MouseButton1Click:Connect(function() mainMenu.Visible = false; openButton.Visible = true end)
	
	-- Tabs
	local tabBar = Instance.new("Frame"); tabBar.Size = UDim2.new(1, 0, 0, 32); tabBar.Position = UDim2.new(0, 0, 0, 40)
	tabBar.BackgroundColor3 = Color3.fromRGB(22, 22, 22); tabBar.BorderSizePixel = 0; tabBar.Parent = mainMenu
	local tabNames = {"⚽", "🎁", "🎒", "🧠", "🔍"}
	local tabKeys = {"Main", "BP", "Inventory", "Brainrot", "Debug"}
	local tabs = {}
	for i, name in ipairs(tabNames) do
		local tab = Instance.new("TextButton"); tab.Size = UDim2.new(0.2, -1, 1, 0); tab.Position = UDim2.new((i-1)*0.2, 0, 0, 0)
		tab.BackgroundColor3 = i == 1 and Color3.fromRGB(45, 45, 45) or Color3.fromRGB(22, 22, 22); tab.TextColor3 = Color3.fromRGB(255, 255, 255)
		tab.TextSize = 13; tab.Font = Enum.Font.Gotham; tab.Text = name; tab.BorderSizePixel = 0; tab.Parent = tabBar; tabs[tabKeys[i]] = tab
		tab.MouseButton1Click:Connect(function()
			for _, t in pairs(tabs) do t.BackgroundColor3 = Color3.fromRGB(22, 22, 22) end
			tab.BackgroundColor3 = Color3.fromRGB(45, 45, 45); currentTab = tabKeys[i]
			local ct = mainMenu:FindFirstChild("Content")
			if ct then for _, c in ipairs(ct:GetChildren()) do if c:IsA("Frame") then c.Visible = (c.Name == currentTab .. "Tab") end end end
		end)
	end
	
	local content = Instance.new("Frame"); content.Name = "Content"; content.Size = UDim2.new(1, 0, 1, -72)
	content.Position = UDim2.new(0, 0, 0, 72); content.BackgroundTransparency = 1; content.Parent = mainMenu
	
	-- Helpers
	local function sec(scroll, title, h)
		local s = Instance.new("Frame"); s.Size = UDim2.new(1, 0, 0, h); s.BackgroundColor3 = Color3.fromRGB(28, 28, 28); s.BorderSizePixel = 0; s.Parent = scroll
		Instance.new("UICorner", s).CornerRadius = UDim.new(0, 8)
		local l = Instance.new("TextLabel"); l.Size = UDim2.new(1, -16, 0, 20); l.Position = UDim2.new(0, 8, 0, 4)
		l.BackgroundTransparency = 1; l.Text = title; l.TextColor3 = Color3.fromRGB(255, 255, 255); l.TextSize = 12; l.Font = Enum.Font.GothamBold; l.TextXAlignment = Enum.TextXAlignment.Left; l.Parent = s
		return s
	end
	local function btn(parent, text, y)
		local b = Instance.new("TextButton"); b.Size = UDim2.new(1, -16, 0, 30); b.Position = UDim2.new(0, 8, 0, y)
		b.BackgroundColor3 = Color3.fromRGB(50, 50, 50); b.TextColor3 = Color3.fromRGB(255, 255, 255); b.TextSize = 12; b.Font = Enum.Font.GothamBold
		b.Text = "ВКЛЮЧИТЬ " .. text; b.BorderSizePixel = 0; b.Parent = parent; Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5); return b
	end
	local function lbl(parent, text, y)
		local l = Instance.new("TextLabel"); l.Size = UDim2.new(1, -16, 0, 16); l.Position = UDim2.new(0, 8, 0, y)
		l.BackgroundTransparency = 1; l.Text = text; l.TextColor3 = Color3.fromRGB(180, 180, 180); l.TextSize = 11; l.Font = Enum.Font.Gotham; l.TextXAlignment = Enum.TextXAlignment.Left; l.Parent = parent; return l
	end
	
	-- === MAIN TAB ===
	local mainTab = Instance.new("Frame"); mainTab.Name = "MainTab"; mainTab.Size = UDim2.new(1, 0, 1, 0); mainTab.BackgroundTransparency = 1; mainTab.Parent = content
	local ms = Instance.new("ScrollingFrame"); ms.Size = UDim2.new(1, -4, 1, 0); ms.Position = UDim2.new(0, 2, 0, 0)
	ms.BackgroundTransparency = 1; ms.BorderSizePixel = 0; ms.ScrollBarThickness = 3; ms.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100)
	ms.CanvasSize = UDim2.new(0, 0, 0, 800); ms.Parent = mainTab; Instance.new("UIListLayout", ms).Padding = UDim.new(0, 4)
	
	-- Kick
	local ks = sec(ms, "⚽ AUTO KICK", 95)
	kickToggle = btn(ks, "KICK", 28); kickStatus = lbl(ks, "● ВЫКЛЮЧЕН", 62); kickWaveLabel = lbl(ks, "Волны: --", 78)
	kickStatus.TextColor3 = Color3.fromRGB(255, 80, 80)
	
	-- BP
	local bps = sec(ms, "🎁 AUTO BATTLEPASS", 95)
	bpToggle = btn(bps, "BP", 28); bpStatus = lbl(bps, "● ВЫКЛЮЧЕН", 62); bpInfoLabel = lbl(bps, "XP: -- | Собрано: 0", 78)
	bpStatus.TextColor3 = Color3.fromRGB(255, 80, 80)
	
	-- Sell
	local ss = sec(ms, "💰 AUTO SELL", 78)
	sellToggle = btn(ss, "SELL", 28); sellStatus = lbl(ss, "● ВЫКЛЮЧЕН", 62)
	sellStatus.TextColor3 = Color3.fromRGB(255, 80, 80)
	
	-- Bonus
	local bs = sec(ms, "🎯 AUTO BONUS", 78)
	bonusToggle = btn(bs, "BONUS", 28); bonusStatus = lbl(bs, "● ВЫКЛЮЧЕН", 62)
	bonusStatus.TextColor3 = Color3.fromRGB(255, 80, 80)
	
	-- Speed
	local sps = sec(ms, "⬆ AUTO SPEED", 78)
	speedUpgradeToggle = btn(sps, "SPEED", 28); speedUpgradeStatus = lbl(sps, "● ВЫКЛЮЧЕН", 62)
	speedUpgradeStatus.TextColor3 = Color3.fromRGB(255, 80, 80)
	
	-- Weight
	local ws = sec(ms, "🏋 AUTO WEIGHT", 78)
	weightToggle = btn(ws, "WEIGHT", 28); weightStatus = lbl(ws, "● ВЫКЛЮЧЕН", 62)
	weightStatus.TextColor3 = Color3.fromRGB(255, 80, 80)
	
	-- Buy Weight
	local bws = sec(ms, "🛒 AUTO BUY WEIGHT", 78)
	buyWeightToggle = btn(bws, "BUY W", 28); buyWeightStatus = lbl(bws, "● ВЫКЛЮЧЕН", 62)
	buyWeightStatus.TextColor3 = Color3.fromRGB(255, 80, 80)
	
	-- Trade Ballberto
	local trs = sec(ms, "🤝 TRADE BALLBERTO", 78)
	tradeToggle = btn(trs, "TRADE B", 28); tradeStatus = lbl(trs, "● ВЫКЛЮЧЕН", 62)
	tradeStatus.TextColor3 = Color3.fromRGB(255, 80, 80)
	
	-- === BP TAB ===
	local bpTab = Instance.new("Frame"); bpTab.Name = "BpTab"; bpTab.Size = UDim2.new(1, 0, 1, 0); bpTab.BackgroundTransparency = 1; bpTab.Visible = false; bpTab.Parent = content
	local bpsc = Instance.new("ScrollingFrame"); bpsc.Size = UDim2.new(1, -4, 1, 0); bpsc.Position = UDim2.new(0, 2, 0, 0)
	bpsc.BackgroundTransparency = 1; bpsc.BorderSizePixel = 0; bpsc.ScrollBarThickness = 3; bpsc.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100)
	bpsc.CanvasSize = UDim2.new(0, 0, 0, 160); bpsc.Parent = bpTab; Instance.new("UIListLayout", bpsc).Padding = UDim.new(0, 4)
	local bpis = sec(bpsc, "📊 ИНФО BP", 140)
	local bpxp = lbl(bpis, "XP: --", 28); local bpcl = lbl(bpis, "Собрано: --", 46)
	local bppr = lbl(bpis, "Premium: --", 64); local bpmr = lbl(bpis, "Морф: --", 82)
	local bpmu = lbl(bpis, "Мутация: --", 100); local bplv = lbl(bpis, "Уровень: --", 118)
	
	-- === INVENTORY TAB ===
	local invTab = Instance.new("Frame"); invTab.Name = "InventoryTab"; invTab.Size = UDim2.new(1, 0, 1, 0); invTab.BackgroundTransparency = 1; invTab.Visible = false; invTab.Parent = content
	local invsc = Instance.new("ScrollingFrame"); invsc.Size = UDim2.new(1, -4, 1, 0); invsc.Position = UDim2.new(0, 2, 0, 0)
	invsc.BackgroundTransparency = 1; invsc.BorderSizePixel = 0; invsc.ScrollBarThickness = 3; invsc.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100)
	invsc.CanvasSize = UDim2.new(0, 0, 0, 0); invsc.Parent = invTab; Instance.new("UIListLayout", invsc).Padding = UDim.new(0, 4)
	
	-- === BRAINROT TAB ===
	local brTab = Instance.new("Frame"); brTab.Name = "BrainrotTab"; brTab.Size = UDim2.new(1, 0, 1, 0); brTab.BackgroundTransparency = 1; brTab.Visible = false; brTab.Parent = content
	local brsc = Instance.new("ScrollingFrame"); brsc.Size = UDim2.new(1, -4, 1, 0); brsc.Position = UDim2.new(0, 2, 0, 0)
	brsc.BackgroundTransparency = 1; brsc.BorderSizePixel = 0; brsc.ScrollBarThickness = 3; brsc.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100)
	brsc.CanvasSize = UDim2.new(0, 0, 0, 0); brsc.Parent = brTab; Instance.new("UIListLayout", brsc).Padding = UDim.new(0, 4)
	
	-- === DEBUG TAB ===
	local dbgTab = Instance.new("Frame"); dbgTab.Name = "DebugTab"; dbgTab.Size = UDim2.new(1, 0, 1, 0); dbgTab.BackgroundTransparency = 1; dbgTab.Visible = false; dbgTab.Parent = content
	local dbgsc = Instance.new("ScrollingFrame"); dbgsc.Size = UDim2.new(1, -4, 1, 0); dbgsc.Position = UDim2.new(0, 2, 0, 0)
	dbgsc.BackgroundTransparency = 1; dbgsc.BorderSizePixel = 0; dbgsc.ScrollBarThickness = 3; dbgsc.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100)
	dbgsc.CanvasSize = UDim2.new(0, 0, 0, 500); dbgsc.Parent = dbgTab; Instance.new("UIListLayout", dbgsc).Padding = UDim.new(0, 4)
	
	-- === КНОПКИ ===
	local function toggle(b, st, active, name)
		if active then b.Text = "ВЫКЛЮЧИТЬ " .. name; b.BackgroundColor3 = Color3.fromRGB(180, 50, 50); st.Text = "● АКТИВЕН"; st.TextColor3 = Color3.fromRGB(80, 255, 80)
		else b.Text = "ВКЛЮЧИТЬ " .. name; b.BackgroundColor3 = Color3.fromRGB(50, 50, 50); st.Text = "● ВЫКЛЮЧЕН"; st.TextColor3 = Color3.fromRGB(255, 80, 80) end
	end
	
	kickToggle.MouseButton1Click:Connect(function() isKickActive = not isKickActive; toggle(kickToggle, kickStatus, isKickActive, "KICK"); if isKickActive then task.spawn(kickLoop) end end)
	bpToggle.MouseButton1Click:Connect(function() isBpActive = not isBpActive; toggle(bpToggle, bpStatus, isBpActive, "BP"); if isBpActive then task.spawn(bpLoop) end end)
	sellToggle.MouseButton1Click:Connect(function() isAutoSell = not isAutoSell; toggle(sellToggle, sellStatus, isAutoSell, "SELL"); if isAutoSell then task.spawn(autoSellLoop) end end)
	bonusToggle.MouseButton1Click:Connect(function() isAutoBonus = not isAutoBonus; toggle(bonusToggle, bonusStatus, isAutoBonus, "BONUS"); if isAutoBonus then task.spawn(autoBonusLoop) end end)
	speedUpgradeToggle.MouseButton1Click:Connect(function() isAutoSpeedUpgrade = not isAutoSpeedUpgrade; toggle(speedUpgradeToggle, speedUpgradeStatus, isAutoSpeedUpgrade, "SPEED"); if isAutoSpeedUpgrade then task.spawn(autoSpeedUpgradeLoop) end end)
	weightToggle.MouseButton1Click:Connect(function() isAutoWeight = not isAutoWeight; toggle(weightToggle, weightStatus, isAutoWeight, "WEIGHT"); if isAutoWeight then task.spawn(autoWeightLoop) end end)
	buyWeightToggle.MouseButton1Click:Connect(function() isAutoBuyWeight = not isAutoBuyWeight; toggle(buyWeightToggle, buyWeightStatus, isAutoBuyWeight, "BUY W"); if isAutoBuyWeight then task.spawn(autoBuyWeightLoop) end end)
	tradeToggle.MouseButton1Click:Connect(function() isAutoTradeBallberto = not isAutoTradeBallberto; toggle(tradeToggle, tradeStatus, isAutoTradeBallberto, "TRADE B"); if isAutoTradeBallberto then task.spawn(autoTradeBallbertoLoop) end end)
	openButton.MouseButton1Click:Connect(function() mainMenu.Visible = true; openButton.Visible = false end)
	
	-- Brainrot fill
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
	
	-- Update loop
	task.spawn(function()
		while true do
			local now = tick()
			if mainMenu.Visible and now - lastGUIUpdate > UPDATE_INTERVAL then
				lastGUIUpdate = now
				
				if updateCharacterReferences() then
					local dist, count, rarity = getClosestWave()
					kickWaveLabel.Text = string.format("Волны: %d | %.0f studs | %s", count, dist, rarity)
				end
				
				if bpData then
					bpInfoLabel.Text = string.format("XP: %s | Собрано: %d", bpData.XP or 0, claimedCount)
					bpxp.Text = "XP: " .. (bpData.XP or 0); bpcl.Text = "Собрано: " .. claimedCount
					bppr.Text = "Premium: " .. (bpData.HasPremium and "ДА" or "НЕТ")
				end
				
				local mn, mm, ml, mcps = getCurrentMorph()
				bpmr.Text = "Морф: " .. mn; bpmu.Text = "Мутация: " .. mm; bplv.Text = "Уровень: " .. ml .. " | CPS: " .. mcps
				
				if currentTab == "Debug" then
					for _, c in ipairs(dbgsc:GetChildren()) do if c:IsA("Frame") and c.Name ~= "UIListLayout" then c:Destroy() end end
					local attrs = {InGame = player:GetAttribute("InGame"), KickDebounced = player:GetAttribute("KickDebounced"), TransformedTo = player:GetAttribute("TransformedTo"), TransformedMutation = player:GetAttribute("TransformedMutation"), TransformedLevel = player:GetAttribute("TransformedLevel"), HasPremium = player:GetAttribute("HasPremium")}
					local as = sec(dbgsc, "📋 АТРИБУТЫ", 140)
					lbl(as, "InGame: " .. tostring(attrs.InGame), 26); lbl(as, "KickDebounced: " .. tostring(attrs.KickDebounced), 44)
					lbl(as, "TransformedTo: " .. tostring(attrs.TransformedTo), 62); lbl(as, "TransformedMutation: " .. tostring(attrs.TransformedMutation), 80)
					lbl(as, "TransformedLevel: " .. tostring(attrs.TransformedLevel), 98); lbl(as, "HasPremium: " .. tostring(attrs.HasPremium), 116)
					local mos = sec(dbgsc, "🧬 МОРФ", 95)
					lbl(mos, "Имя: " .. mn, 26); lbl(mos, "Мутация: " .. mm, 44); lbl(mos, "Уровень: " .. ml, 62); lbl(mos, "CPS: " .. mcps, 78)
					if updateCharacterReferences() then
						local pos = sec(dbgsc, "📍 ПОЗИЦИЯ", 75)
						lbl(pos, "В KickReady: " .. (isInKickReady() and "ДА" or "НЕТ"), 26)
						if kickReadyPos then lbl(pos, "Дист: " .. string.format("%.0f studs", (rootPart.Position - kickReadyPos).Magnitude), 44) end
						lbl(pos, "Скорость: " .. math.floor(humanoid.WalkSpeed), 60)
						local dist, count, rarity = getClosestWave()
						local wvs = sec(dbgsc, "🌊 ВОЛНЫ", 75)
						lbl(wvs, "Кол-во: " .. count, 26); lbl(wvs, "Ближ: " .. string.format("%.0f studs", dist), 44); lbl(wvs, "Редкость: " .. rarity, 60)
					end
					local inv = scanBackpack(); local total = 0; for _, items in pairs(inv) do total = total + #items end
					local isu = sec(dbgsc, "🎒 ИНВЕНТАРЬ", 30 + total * 16)
					lbl(isu, "Всего: " .. total, 26); local y = 44
					for name, items in pairs(inv) do lbl(isu, "  " .. name .. ": " .. #items, y); y = y + 16 end
					isu.Size = UDim2.new(1, 0, 0, y + 6)
					dbgsc.CanvasSize = UDim2.new(0, 0, 0, 140 + 95 + 75 + 75 + y + 30)
				end
				
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
print("Farm loaded! 8 функций, без ошибок.")
