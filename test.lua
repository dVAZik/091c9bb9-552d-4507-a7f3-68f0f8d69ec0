-- Auto Farm Script - Complete Final Version
-- Auto Kick + Auto BP + Auto Sell + Auto Bonus Click (2 метода) + Debug

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local CoreGui = game:GetService("CoreGui")
local VirtualInputManager = game:GetService("VirtualInputManager")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

-- ============ КОНСТАНТЫ ============
local KICK_POWER = 10
local KICK_READY_RADIUS = 10
local MIN_WAVE_DISTANCE = 300
local MOVEMENT_TIMEOUT = 30
local JUMP_COOLDOWN = 0.5
local WAYPOINT_REACH_DISTANCE = 3
local NORMAL_SPEED_MULTIPLIER = 1.0
local MAX_SPEED_MULTIPLIER = 3.5
local DANGER_DISTANCE = 150
local CRITICAL_DISTANCE = 50

-- ============ ПЕРЕМЕННЫЕ ============
local character, humanoid, rootPart
local kickReadyPart, kickReadyPos
local revKickEvent, revKickCollect, revKickEventEnded
local isKickActive = false
local lastJumpTime = 0
local baseWalkSpeed = 16

local isBpActive = false
local bpData, claimedCount = nil, 0

local isAutoSell = false
local selectedBrainrots = {}
local selectedMutations = {["None"] = true}

local isAutoBonus = false

-- GUI
local screenGui, openButton, mainMenu
local kickToggle, kickStatus, kickWaveLabel
local bpToggle, bpStatus, bpInfoLabel
local sellToggle, sellStatus
local bonusToggle, bonusStatus
local currentTab = "Main"

-- ============ ДАННЫЕ ============
local EntitiesData, MutationData
pcall(function() EntitiesData = require(ReplicatedStorage.Shared.Data.EntitiesData) end)
pcall(function() MutationData = require(ReplicatedStorage.Shared.Data.MutationData) end)

local function safeCPS(name)
	if not EntitiesData or not EntitiesData.Brainrots or not EntitiesData.Brainrots[name] then return 0 end
	local cpsRaw = EntitiesData.Brainrots[name].CPS
	if not cpsRaw then return 0 end
	local cpsStr = tostring(cpsRaw):gsub(",", ""):gsub("%s", "")
	local num = tonumber(cpsStr)
	if num then return num end
	pcall(function()
		if cpsRaw.Value then
			local v = tostring(cpsRaw.Value):gsub(",", ""):gsub("%s", "")
			num = tonumber(v)
		end
	end)
	return num or 0
end

local function getBrainrotList()
	local list = {}
	if EntitiesData and EntitiesData.Brainrots then
		for name, data in pairs(EntitiesData.Brainrots) do
			local cps = safeCPS(name)
			if cps > 0 then
				table.insert(list, {
					Name = name, CPS = cps,
					Rarity = data.Rarity or "?", Best = data.Best or 0
				})
			end
		end
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
	if not player.Character then return "Нет", "Нет", 0, "Нет" end
	for _, child in ipairs(player.Character:GetChildren()) do
		if child:IsA("Tool") and child:HasTag("EntityTool") then
			return child.Name, child:GetAttribute("Mutation") or "None", child:GetAttribute("Level") or 1, safeCPS(child.Name)
		end
	end
	return "Нет", "Нет", 0, "Нет"
end

local function scanBackpack()
	local inv = {}
	if not player.Backpack then return inv end
	for _, item in ipairs(player.Backpack:GetChildren()) do
		if item:IsA("Tool") and item:HasTag("EntityTool") then
			local name = item.Name
			local level = item:GetAttribute("Level") or 1
			local mutation = item:GetAttribute("Mutation") or "None"
			local guid = item:GetAttribute("GUID")
			local cps = safeCPS(name)
			if not inv[name] then inv[name] = {} end
			table.insert(inv[name], {Level = level, Mutation = mutation, GUID = guid, CPS = cps})
		end
	end
	return inv
end

local function getPlayerAttributes()
	return {
		InGame = player:GetAttribute("InGame"),
		KickDebounced = player:GetAttribute("KickDebounced"),
		TransformedTo = player:GetAttribute("TransformedTo"),
		TransformedMutation = player:GetAttribute("TransformedMutation"),
		TransformedLevel = player:GetAttribute("TransformedLevel"),
		HasPremium = player:GetAttribute("HasPremium")
	}
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

local function getClosestWaveDistance()
	local waves = workspace:FindFirstChild("Waves")
	if not waves or not rootPart then return math.huge, 0, "Нет" end
	local minDistance, waveCount, closestRarity = math.huge, 0, "Нет"
	for _, wave in pairs(waves:GetChildren()) do
		local wavePos = nil
		if wave:IsA("Model") then wavePos = wave.PrimaryPart and wave.PrimaryPart.Position or wave:GetPivot().Position
		elseif wave:IsA("BasePart") then wavePos = wave.Position end
		if wavePos then
			waveCount = waveCount + 1
			local d = (rootPart.Position - wavePos).Magnitude
			if d < minDistance then minDistance = d; closestRarity = wave:GetAttribute("Rarity") or wave.Name end
		end
	end
	return minDistance, waveCount, closestRarity
end

local function calculateDynamicSpeed()
	if humanoid then baseWalkSpeed = humanoid.WalkSpeed end
	local dist, count = getClosestWaveDistance()
	local mult = NORMAL_SPEED_MULTIPLIER
	if count > 0 and dist < DANGER_DISTANCE then
		if dist <= CRITICAL_DISTANCE then mult = MAX_SPEED_MULTIPLIER
		else
			local t = 1 - (dist - CRITICAL_DISTANCE) / (DANGER_DISTANCE - CRITICAL_DISTANCE)
			mult = NORMAL_SPEED_MULTIPLIER + (MAX_SPEED_MULTIPLIER - NORMAL_SPEED_MULTIPLIER) * (t * t)
		end
	end
	return baseWalkSpeed * mult
end

local function teleportForward(distance)
	if not rootPart or not kickReadyPos then return end
	local dir = (kickReadyPos - rootPart.Position).Unit
	local tpDist = math.min(distance, (kickReadyPos - rootPart.Position).Magnitude - 5)
	if tpDist > 0 then
		rootPart.CFrame = CFrame.new(rootPart.Position + dir * tpDist + Vector3.new(0, 3, 0))
		task.wait(0.2)
	end
end

-- ============ KICK ============
local function initKickReferences()
	local areas = workspace:FindFirstChild("Areas")
	if areas then kickReadyPart = areas:FindFirstChild("KickReady"); if kickReadyPart then kickReadyPos = kickReadyPart.Position end end
	local network = findNetwork()
	if network then
		revKickEvent = network:FindFirstChild("rev_KickEvent")
		revKickCollect = network:FindFirstChild("rev_KickCollect")
		revKickEventEnded = network:FindFirstChild("rev_KickEventEnded")
	end
end

local function moveToKickReadyBeforeKick()
	if not updateCharacterReferences() then return false end
	if not humanoid or not rootPart or not kickReadyPos then return false end
	if humanoid.Health <= 0 or humanoid:GetState() == Enum.HumanoidStateType.Dead then return false end
	if isInKickReady() then return true end
	
	if (rootPart.Position - kickReadyPos).Magnitude <= 30 then
		humanoid.WalkSpeed = baseWalkSpeed; humanoid.AutoRotate = true; humanoid:MoveTo(kickReadyPos)
		local st, lp = tick(), rootPart.Position
		while isKickActive and tick() - st < 10 do
			if not updateCharacterReferences() or humanoid.Health <= 0 then return false end
			if isInKickReady() then humanoid:MoveTo(rootPart.Position); return true end
			if (rootPart.Position - lp).Magnitude < 0.5 then
				if tick() - lastJumpTime > JUMP_COOLDOWN then humanoid.Jump = true; lastJumpTime = tick() end
				if tick() - st > 3 then teleportForward(1) end
			else lp = rootPart.Position end
			humanoid:MoveTo(kickReadyPos); task.wait(0.05)
		end
		return isInKickReady()
	end
	
	for attempt = 1, 10 do
		if not isKickActive or not updateCharacterReferences() then return false end
		if isInKickReady() then return true end
		local waypoints, pathFound = {}, false
		pcall(function()
			local path = PathfindingService:CreatePath({AgentRadius = 2, AgentHeight = 5, AgentCanJump = true, AgentMaxSlope = 45, WaypointSpacing = 3, Costs = {Water = 20}})
			path:ComputeAsync(rootPart.Position, kickReadyPos); waypoints = path:GetWaypoints(); pathFound = (#waypoints > 0)
		end)
		if pathFound and #waypoints > 0 then
			for _, wp in ipairs(waypoints) do
				if not isKickActive or not updateCharacterReferences() then return false end
				if humanoid.Health <= 0 then return false end
				if isInKickReady() then humanoid:MoveTo(rootPart.Position); return true end
				humanoid.WalkSpeed = baseWalkSpeed; humanoid.AutoRotate = true; humanoid:MoveTo(wp.Position)
				local wst, lp = tick(), rootPart.Position
				while isKickActive and tick() - wst < 5 do
					if not updateCharacterReferences() or humanoid.Health <= 0 then return false end
					if isInKickReady() then humanoid:MoveTo(rootPart.Position); return true end
					if (rootPart.Position - wp.Position).Magnitude <= WAYPOINT_REACH_DISTANCE then break end
					if (rootPart.Position - lp).Magnitude < 0.5 then
						if tick() - lastJumpTime > JUMP_COOLDOWN then humanoid.Jump = true; lastJumpTime = tick() end
						if tick() - wst > 3 then teleportForward(2); break end
					else lp = rootPart.Position end
					task.wait(0.05)
				end
			end
			if isInKickReady() then return true end
		else teleportForward(math.random(10, 30) / 10); if isInKickReady() then return true end end
	end
	return isInKickReady()
end

local function moveToKickReadyAfterKick()
	if not updateCharacterReferences() then return false end
	if not humanoid or not rootPart or not kickReadyPos then return false end
	if humanoid.Health <= 0 or humanoid:GetState() == Enum.HumanoidStateType.Dead then return false end
	if isInKickReady() then return true end
	humanoid.WalkSpeed = calculateDynamicSpeed(); humanoid.AutoRotate = true; humanoid:MoveTo(kickReadyPos)
	local st, lp = tick(), rootPart.Position
	while isKickActive and tick() - st < MOVEMENT_TIMEOUT do
		if not updateCharacterReferences() then return false end
		if humanoid.Health <= 0 then humanoid:MoveTo(rootPart.Position); return false end
		if isInKickReady() then humanoid:MoveTo(rootPart.Position); return true end
		humanoid.WalkSpeed = calculateDynamicSpeed()
		if (rootPart.Position - lp).Magnitude < 0.5 then
			if tick() - lastJumpTime > JUMP_COOLDOWN then humanoid.Jump = true; lastJumpTime = tick() end
			if tick() - st > 3 then teleportForward(2) end
		else lp = rootPart.Position end
		humanoid:MoveTo(kickReadyPos); task.wait(0.05)
	end
	for i = 1, 5 do
		if not updateCharacterReferences() or humanoid.Health <= 0 then break end
		if isInKickReady() then return true end
		teleportForward(2); humanoid:MoveTo(kickReadyPos); task.wait(0.3)
	end
	return isInKickReady()
end

local function kickLoop()
	initKickReferences()
	while isKickActive do
		if not updateCharacterReferences() then task.wait(0.5); continue end
		local inGame = player:GetAttribute("InGame"); local kickDebounced = player:GetAttribute("KickDebounced")
		if not isInKickReady() then
			if inGame == nil and kickDebounced == nil then moveToKickReadyBeforeKick() else moveToKickReadyAfterKick() end
		end
		if isInKickReady() and inGame == nil and kickDebounced == nil then
			local dist, _, _ = getClosestWaveDistance()
			if dist >= MIN_WAVE_DISTANCE and revKickEvent then revKickEvent:FireServer(KICK_POWER) end
		elseif isInKickReady() and inGame == true and kickDebounced == false and revKickCollect and revKickEventEnded then
			revKickCollect:FireServer(); task.wait(0.1); revKickEventEnded:FireServer()
		end
		task.wait(0.1)
	end
end

-- ============ BATTLEPASS ============
local function getBPData()
	local network = findNetwork()
	if not network then return nil end
	local ds = network:FindFirstChild("rev_BattlePassDataSend")
	if ds and ds:IsA("RemoteEvent") then ds.OnClientEvent:Connect(function(d) bpData = d end) end
	return bpData
end

local function claimReward(id, rewardType)
	local network = findNetwork()
	if not network then return false end
	local func = network:FindFirstChild(rewardType == "Bonus" and "ref_BattlePassAttemptBonusClaim" or "ref_BattlePassAttemptClaim")
	if func then local s, r = pcall(func.InvokeServer, func, id, rewardType); return s and r end
	return false
end

local function autoClaim()
	if not bpData then bpData = getBPData(); if not bpData then return 0 end end
	local xp = bpData.XP or 0
	local uf, up, ub = bpData.UnlockedFreeRewards or {}, bpData.UnlockedPremiumRewards or {}, bpData.UnlockedBonusRewards or {}
	local nc = 0
	local fr = {{1,500},{2,1000},{3,1500},{4,2000},{5,2500},{6,3000},{7,3500},{8,4000},{9,4500},{10,5000},{11,5500},{12,6000},{13,6500},{14,7000},{15,7500}}
	for _, r in ipairs(fr) do if xp >= r[2] and not table.find(uf, r[1]) then if claimReward(r[1], "Free") then table.insert(uf, r[1]); nc = nc + 1; task.wait(0.1) end end end
	if bpData.HasPremium then
		local pr = {{0,0},{1,500},{2,1000},{3,1500},{4,2000},{5,2500},{6,3000},{7,3500},{8,4000},{9,4500},{10,5000},{11,5500},{12,6000},{13,6500},{14,7000},{15,7500}}
		for _, r in ipairs(pr) do if xp >= r[2] and not table.find(up, r[1]) then if claimReward(r[1], "Premium") then table.insert(up, r[1]); nc = nc + 1; task.wait(0.1) end end end
	end
	local af = true; for _, r in ipairs(fr) do if not table.find(uf, r[1]) then af = false; break end end
	if af then
		local br = {{1,8250},{2,9000},{3,9750},{4,10500},{5,11250}}
		for _, r in ipairs(br) do if xp >= r[2] and not table.find(ub, r[1]) then if claimReward(r[1], "Bonus") then table.insert(ub, r[1]); nc = nc + 1; task.wait(0.1) end end end
	end
	return nc
end

local function bpLoop() while isBpActive do local n = autoClaim(); if n > 0 then claimedCount = claimedCount + n end; task.wait(1) end end

-- ============ AUTO SELL ============
local function sellItem(guid)
	local network = findNetwork()
	if not network then return false end
	return pcall(function() network.FireServer("SELL_ENTITY", guid) end)
end

local function autoSellLoop()
	while isAutoSell do
		for name, items in pairs(scanBackpack()) do
			for _, item in ipairs(items) do
				local keep = selectedBrainrots[name] and (selectedMutations[item.Mutation] or item.Mutation == "None")
				if not keep and item.GUID then sellItem(item.GUID); task.wait(0.05) end
			end
		end
		task.wait(2)
	end
end

-- ============ AUTO BONUS CLICK (ДВА МЕТОДА) ============
local function clickBonusButton(button)
	local absPos = button.AbsolutePosition
	local absSize = button.AbsoluteSize
	local x = absPos.X + absSize.X / 2
	local y = absPos.Y + absSize.Y / 2
	
	-- Метод 1: VirtualInputManager (симуляция клика мыши)
	pcall(function()
		VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
		task.wait(0.01)
		VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
	end)
	
	-- Метод 2: Вызов Activated события напрямую
	pcall(function()
		if button.Activated then
			-- Пробуем получить все привязанные функции
			for _, bindable in ipairs(button.Activated:GetBindables()) do
				bindable:Fire()
			end
		end
	end)
	
	-- Метод 3: MouseButton1Click
	pcall(function()
		if button.MouseButton1Click then
			button.MouseButton1Click:Fire()
		end
	end)
	
	-- Метод 4: прямой вызов события через firesignal
	pcall(function()
		local guiService = game:GetService("GuiService")
		-- Пробуем через InputBegan
		if button.InputBegan then
			button.InputBegan:Fire({
				Position = Vector2.new(x, y),
				UserInputType = Enum.UserInputType.MouseButton1
			})
			task.wait(0.01)
			button.InputEnded:Fire({
				Position = Vector2.new(x, y),
				UserInputType = Enum.UserInputType.MouseButton1
			})
		end
	end)
end

local function autoBonusLoop()
	while isAutoBonus do
		local hasWeight = false
		if player.Character then
			for _, tool in ipairs(player.Character:GetChildren()) do
				if tool:IsA("Tool") and tool:HasTag("EntityTool") then
					local weightModels = ReplicatedStorage.Objects:FindFirstChild("WeightModels")
					if weightModels and weightModels:FindFirstChild(tool.Name) then
						hasWeight = true
						break
					end
				end
			end
		end
		
		if hasWeight then
			local playerGui = player:FindFirstChild("PlayerGui")
			if playerGui then
				local kickUpgrades = playerGui:FindFirstChild("KickUpgrades")
				if kickUpgrades and kickUpgrades.Enabled then
					for _, child in ipairs(kickUpgrades:GetDescendants()) do
						if child:IsA("ImageButton") and (child.Name == "Bonus" or child.Name:find("Bonus")) and child.Visible and child.Active then
							clickBonusButton(child)
							task.wait(0.03)
						end
					end
				end
			end
		end
		
		task.wait(0.05)
	end
end

-- ============ GUI ============
local function createGUI()
	screenGui = Instance.new("ScreenGui"); screenGui.Name = "FarmMenuGUI"; screenGui.ResetOnSpawn = false; screenGui.Parent = CoreGui
	
	openButton = Instance.new("TextButton"); openButton.Size = UDim2.new(0, 45, 0, 45); openButton.Position = UDim2.new(1, -55, 0, 10)
	openButton.BackgroundColor3 = Color3.fromRGB(30, 30, 30); openButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	openButton.TextSize = 22; openButton.Font = Enum.Font.GothamBold; openButton.Text = "☰"
	openButton.BackgroundTransparency = 0.15; openButton.BorderSizePixel = 0; openButton.Parent = screenGui
	Instance.new("UICorner", openButton).CornerRadius = UDim.new(0, 22)
	
	mainMenu = Instance.new("Frame"); mainMenu.Size = UDim2.new(0, 320, 0, 460); mainMenu.Position = UDim2.new(0.5, -160, 0.1, 0)
	mainMenu.BackgroundColor3 = Color3.fromRGB(20, 20, 20); mainMenu.BorderSizePixel = 0; mainMenu.BackgroundTransparency = 0.05
	mainMenu.Visible = false; mainMenu.Active = true; mainMenu.Draggable = true; mainMenu.Parent = screenGui
	Instance.new("UICorner", mainMenu).CornerRadius = UDim.new(0, 12)
	
	local titleBar = Instance.new("Frame"); titleBar.Size = UDim2.new(1, 0, 0, 40); titleBar.BackgroundColor3 = Color3.fromRGB(35, 35, 35); titleBar.BorderSizePixel = 0; titleBar.Parent = mainMenu
	Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 12)
	local titleLabel = Instance.new("TextLabel"); titleLabel.Size = UDim2.new(1, -40, 0, 40); titleLabel.Position = UDim2.new(0, 15, 0, 0)
	titleLabel.BackgroundTransparency = 1; titleLabel.Text = "FARM MENU"; titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	titleLabel.TextSize = 16; titleLabel.Font = Enum.Font.GothamBold; titleLabel.TextXAlignment = Enum.TextXAlignment.Left; titleLabel.Parent = titleBar
	local closeButton = Instance.new("TextButton"); closeButton.Size = UDim2.new(0, 30, 0, 30); closeButton.Position = UDim2.new(1, -35, 0, 5)
	closeButton.BackgroundColor3 = Color3.fromRGB(255, 50, 50); closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeButton.TextSize = 18; closeButton.Font = Enum.Font.GothamBold; closeButton.Text = "✕"; closeButton.BorderSizePixel = 0; closeButton.Parent = titleBar
	Instance.new("UICorner", closeButton).CornerRadius = UDim.new(0, 15)
	closeButton.MouseButton1Click:Connect(function() mainMenu.Visible = false; openButton.Visible = true end)
	
	local tabBar = Instance.new("Frame"); tabBar.Size = UDim2.new(1, 0, 0, 32); tabBar.Position = UDim2.new(0, 0, 0, 40)
	tabBar.BackgroundColor3 = Color3.fromRGB(25, 25, 25); tabBar.BorderSizePixel = 0; tabBar.Parent = mainMenu
	local tabNames = {"⚽", "🎁", "🎒", "🧠", "🔍"}
	local tabKeys = {"Main", "BP", "Inventory", "Brainrot", "Debug"}
	local tabs = {}
	for i, name in ipairs(tabNames) do
		local tab = Instance.new("TextButton"); tab.Size = UDim2.new(0.2, -1, 1, 0); tab.Position = UDim2.new((i-1)*0.2, 0, 0, 0)
		tab.BackgroundColor3 = i == 1 and Color3.fromRGB(45, 45, 45) or Color3.fromRGB(25, 25, 25); tab.TextColor3 = Color3.fromRGB(255, 255, 255)
		tab.TextSize = 14; tab.Font = Enum.Font.Gotham; tab.Text = name; tab.BorderSizePixel = 0; tab.Parent = tabBar; tabs[tabKeys[i]] = tab
		tab.MouseButton1Click:Connect(function()
			for _, t in pairs(tabs) do t.BackgroundColor3 = Color3.fromRGB(25, 25, 25) end
			tab.BackgroundColor3 = Color3.fromRGB(45, 45, 45); currentTab = tabKeys[i]
			local ct = mainMenu:FindFirstChild("Content")
			if ct then for _, c in ipairs(ct:GetChildren()) do if c:IsA("Frame") then c.Visible = (c.Name == currentTab .. "Tab") end end end
		end)
	end
	
	local content = Instance.new("Frame"); content.Name = "Content"; content.Size = UDim2.new(1, 0, 1, -72)
	content.Position = UDim2.new(0, 0, 0, 72); content.BackgroundTransparency = 1; content.Parent = mainMenu
	
	local function makeSection(scroll, title, h)
		local s = Instance.new("Frame"); s.Size = UDim2.new(1, 0, 0, h); s.BackgroundColor3 = Color3.fromRGB(30, 30, 30); s.BorderSizePixel = 0; s.Parent = scroll
		Instance.new("UICorner", s).CornerRadius = UDim.new(0, 8)
		local l = Instance.new("TextLabel"); l.Size = UDim2.new(1, -20, 0, 22); l.Position = UDim2.new(0, 10, 0, 5)
		l.BackgroundTransparency = 1; l.Text = title; l.TextColor3 = Color3.fromRGB(255, 255, 255); l.TextSize = 13; l.Font = Enum.Font.GothamBold; l.TextXAlignment = Enum.TextXAlignment.Left; l.Parent = s
		return s
	end
	local function makeButton(parent, text, y)
		local b = Instance.new("TextButton"); b.Size = UDim2.new(1, -20, 0, 34); b.Position = UDim2.new(0, 10, 0, y)
		b.BackgroundColor3 = Color3.fromRGB(60, 60, 60); b.TextColor3 = Color3.fromRGB(255, 255, 255); b.TextSize = 13; b.Font = Enum.Font.GothamBold
		b.Text = "ВКЛЮЧИТЬ " .. text; b.BorderSizePixel = 0; b.Parent = parent; Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6); return b
	end
	local function makeLabel(parent, y, text)
		local l = Instance.new("TextLabel"); l.Size = UDim2.new(1, -20, 0, 17); l.Position = UDim2.new(0, 10, 0, y)
		l.BackgroundTransparency = 1; l.Text = text; l.TextColor3 = Color3.fromRGB(180, 180, 180); l.TextSize = 11; l.Font = Enum.Font.Gotham; l.TextXAlignment = Enum.TextXAlignment.Left; l.Parent = parent; return l
	end
	
	-- MAIN TAB
	local mainTab = Instance.new("Frame"); mainTab.Name = "MainTab"; mainTab.Size = UDim2.new(1, 0, 1, 0); mainTab.BackgroundTransparency = 1; mainTab.Parent = content
	local mainScroll = Instance.new("ScrollingFrame"); mainScroll.Size = UDim2.new(1, -6, 1, 0); mainScroll.Position = UDim2.new(0, 3, 0, 0)
	mainScroll.BackgroundTransparency = 1; mainScroll.BorderSizePixel = 0; mainScroll.ScrollBarThickness = 3; mainScroll.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100)
	mainScroll.CanvasSize = UDim2.new(0, 0, 0, 520); mainScroll.Parent = mainTab; Instance.new("UIListLayout", mainScroll).Padding = UDim.new(0, 6)
	
	local kickSection = makeSection(mainScroll, "⚽ AUTO KICK", 115)
	kickToggle = makeButton(kickSection, "KICK", 30)
	kickStatus = makeLabel(kickSection, 68, "Статус: ВЫКЛЮЧЕН"); kickStatus.TextColor3 = Color3.fromRGB(255, 80, 80)
	kickWaveLabel = makeLabel(kickSection, 88, "Волны: --")
	
	local bpSection = makeSection(mainScroll, "🎁 AUTO BATTLEPASS", 115)
	bpToggle = makeButton(bpSection, "BP", 30)
	bpStatus = makeLabel(bpSection, 68, "Статус: ВЫКЛЮЧЕН"); bpStatus.TextColor3 = Color3.fromRGB(255, 80, 80)
	bpInfoLabel = makeLabel(bpSection, 88, "Собрано: 0 | XP: --")
	
	local sellSection = makeSection(mainScroll, "💰 AUTO SELL", 85)
	sellToggle = makeButton(sellSection, "SELL", 30)
	sellStatus = makeLabel(sellSection, 66, "Статус: ВЫКЛЮЧЕН"); sellStatus.TextColor3 = Color3.fromRGB(255, 80, 80)
	
	local bonusSection = makeSection(mainScroll, "🎯 AUTO BONUS CLICK", 85)
	bonusToggle = makeButton(bonusSection, "BONUS", 30)
	bonusStatus = makeLabel(bonusSection, 66, "Статус: ВЫКЛЮЧЕН"); bonusStatus.TextColor3 = Color3.fromRGB(255, 80, 80)
	
	-- BP TAB
	local bpTab = Instance.new("Frame"); bpTab.Name = "BpTab"; bpTab.Size = UDim2.new(1, 0, 1, 0); bpTab.BackgroundTransparency = 1; bpTab.Visible = false; bpTab.Parent = content
	local bpScroll = Instance.new("ScrollingFrame"); bpScroll.Size = UDim2.new(1, -6, 1, 0); bpScroll.Position = UDim2.new(0, 3, 0, 0)
	bpScroll.BackgroundTransparency = 1; bpScroll.BorderSizePixel = 0; bpScroll.ScrollBarThickness = 3; bpScroll.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100)
	bpScroll.CanvasSize = UDim2.new(0, 0, 0, 180); bpScroll.Parent = bpTab; Instance.new("UIListLayout", bpScroll).Padding = UDim.new(0, 6)
	local bpInfoSec = makeSection(bpScroll, "📊 ИНФО BP", 140)
	local bpxpLabel = makeLabel(bpInfoSec, 30, "XP: --")
	local bpclLabel = makeLabel(bpInfoSec, 49, "Собрано: --")
	local bpprLabel = makeLabel(bpInfoSec, 68, "Premium: --")
	local bpmrLabel = makeLabel(bpInfoSec, 87, "Морф: --")
	local bpmuLabel = makeLabel(bpInfoSec, 106, "Мутация: --")
	local bplvLabel = makeLabel(bpInfoSec, 122, "Уровень: --")
	
	-- INVENTORY TAB
	local invTab = Instance.new("Frame"); invTab.Name = "InventoryTab"; invTab.Size = UDim2.new(1, 0, 1, 0); invTab.BackgroundTransparency = 1; invTab.Visible = false; invTab.Parent = content
	local invScroll = Instance.new("ScrollingFrame"); invScroll.Size = UDim2.new(1, -6, 1, 0); invScroll.Position = UDim2.new(0, 3, 0, 0)
	invScroll.BackgroundTransparency = 1; invScroll.BorderSizePixel = 0; invScroll.ScrollBarThickness = 3; invScroll.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100)
	invScroll.CanvasSize = UDim2.new(0, 0, 0, 0); invScroll.Parent = invTab; Instance.new("UIListLayout", invScroll).Padding = UDim.new(0, 4)
	
	-- BRAINROT TAB
	local brTab = Instance.new("Frame"); brTab.Name = "BrainrotTab"; brTab.Size = UDim2.new(1, 0, 1, 0); brTab.BackgroundTransparency = 1; brTab.Visible = false; brTab.Parent = content
	local brScroll = Instance.new("ScrollingFrame"); brScroll.Size = UDim2.new(1, -6, 1, 0); brScroll.Position = UDim2.new(0, 3, 0, 0)
	brScroll.BackgroundTransparency = 1; brScroll.BorderSizePixel = 0; brScroll.ScrollBarThickness = 3; brScroll.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100)
	brScroll.CanvasSize = UDim2.new(0, 0, 0, 0); brScroll.Parent = brTab; Instance.new("UIListLayout", brScroll).Padding = UDim.new(0, 4)
	
	-- DEBUG TAB
	local debugTab = Instance.new("Frame"); debugTab.Name = "DebugTab"; debugTab.Size = UDim2.new(1, 0, 1, 0); debugTab.BackgroundTransparency = 1; debugTab.Visible = false; debugTab.Parent = content
	local debugScroll = Instance.new("ScrollingFrame"); debugScroll.Size = UDim2.new(1, -6, 1, 0); debugScroll.Position = UDim2.new(0, 3, 0, 0)
	debugScroll.BackgroundTransparency = 1; debugScroll.BorderSizePixel = 0; debugScroll.ScrollBarThickness = 3; debugScroll.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100)
	debugScroll.CanvasSize = UDim2.new(0, 0, 0, 500); debugScroll.Parent = debugTab; Instance.new("UIListLayout", debugScroll).Padding = UDim.new(0, 6)
	
	-- Обработчики кнопок
	kickToggle.MouseButton1Click:Connect(function()
		isKickActive = not isKickActive
		if isKickActive then kickToggle.Text = "ВЫКЛЮЧИТЬ KICK"; kickToggle.BackgroundColor3 = Color3.fromRGB(180, 50, 50); kickStatus.Text = "Статус: АКТИВЕН"; kickStatus.TextColor3 = Color3.fromRGB(80, 255, 80); task.spawn(kickLoop)
		else kickToggle.Text = "ВКЛЮЧИТЬ KICK"; kickToggle.BackgroundColor3 = Color3.fromRGB(60, 60, 60); kickStatus.Text = "Статус: ВЫКЛЮЧЕН"; kickStatus.TextColor3 = Color3.fromRGB(255, 80, 80) end
	end)
	bpToggle.MouseButton1Click:Connect(function()
		isBpActive = not isBpActive
		if isBpActive then bpToggle.Text = "ВЫКЛЮЧИТЬ BP"; bpToggle.BackgroundColor3 = Color3.fromRGB(180, 50, 50); bpStatus.Text = "Статус: АКТИВЕН"; bpStatus.TextColor3 = Color3.fromRGB(80, 255, 80); task.spawn(bpLoop)
		else bpToggle.Text = "ВКЛЮЧИТЬ BP"; bpToggle.BackgroundColor3 = Color3.fromRGB(60, 60, 60); bpStatus.Text = "Статус: ВЫКЛЮЧЕН"; bpStatus.TextColor3 = Color3.fromRGB(255, 80, 80) end
	end)
	sellToggle.MouseButton1Click:Connect(function()
		isAutoSell = not isAutoSell
		if isAutoSell then sellToggle.Text = "ВЫКЛЮЧИТЬ SELL"; sellToggle.BackgroundColor3 = Color3.fromRGB(180, 50, 50); sellStatus.Text = "Статус: АКТИВЕН"; sellStatus.TextColor3 = Color3.fromRGB(80, 255, 80); task.spawn(autoSellLoop)
		else sellToggle.Text = "ВКЛЮЧИТЬ SELL"; sellToggle.BackgroundColor3 = Color3.fromRGB(60, 60, 60); sellStatus.Text = "Статус: ВЫКЛЮЧЕН"; sellStatus.TextColor3 = Color3.fromRGB(255, 80, 80) end
	end)
	bonusToggle.MouseButton1Click:Connect(function()
		isAutoBonus = not isAutoBonus
		if isAutoBonus then bonusToggle.Text = "ВЫКЛЮЧИТЬ BONUS"; bonusToggle.BackgroundColor3 = Color3.fromRGB(180, 50, 50); bonusStatus.Text = "Статус: АКТИВЕН"; bonusStatus.TextColor3 = Color3.fromRGB(80, 255, 80); task.spawn(autoBonusLoop)
		else bonusToggle.Text = "ВКЛЮЧИТЬ BONUS"; bonusToggle.BackgroundColor3 = Color3.fromRGB(60, 60, 60); bonusStatus.Text = "Статус: ВЫКЛЮЧЕН"; bonusStatus.TextColor3 = Color3.fromRGB(255, 80, 80) end
	end)
	openButton.MouseButton1Click:Connect(function() mainMenu.Visible = true; openButton.Visible = false end)
	
	-- Brainrot чекбоксы
	local brLabel = Instance.new("TextLabel"); brLabel.Size = UDim2.new(1, 0, 0, 22); brLabel.BackgroundTransparency = 1
	brLabel.Text = "🧠 Brainrot'ы (не продавать):"; brLabel.TextColor3 = Color3.fromRGB(200, 200, 200); brLabel.TextSize = 12; brLabel.Font = Enum.Font.GothamBold; brLabel.TextXAlignment = Enum.TextXAlignment.Left; brLabel.Parent = brScroll
	local brainrots = getBrainrotList()
	for i, br in ipairs(brainrots) do
		local h = Instance.new("Frame"); h.Size = UDim2.new(1, 0, 0, 32); h.BackgroundColor3 = Color3.fromRGB(30, 30, 30); h.BorderSizePixel = 0; h.Parent = brScroll
		Instance.new("UICorner", h).CornerRadius = UDim.new(0, 5)
		local cbx = Instance.new("TextButton"); cbx.Size = UDim2.new(0, 22, 0, 22); cbx.Position = UDim2.new(0, 6, 0, 5); cbx.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
		cbx.TextColor3 = Color3.fromRGB(255, 255, 255); cbx.TextSize = 12; cbx.Font = Enum.Font.GothamBold; cbx.Text = ""; cbx.BorderSizePixel = 0; cbx.Parent = h
		Instance.new("UICorner", cbx).CornerRadius = UDim.new(0, 4)
		local nm = Instance.new("TextLabel"); nm.Size = UDim2.new(0.55, -34, 0, 22); nm.Position = UDim2.new(0, 32, 0, 5); nm.BackgroundTransparency = 1
		nm.Text = br.Name; nm.TextColor3 = Color3.fromRGB(255, 255, 255); nm.TextSize = 11; nm.Font = Enum.Font.GothamBold; nm.TextXAlignment = Enum.TextXAlignment.Left; nm.TextTruncate = Enum.TextTruncate.AtEnd; nm.Parent = h
		local info = Instance.new("TextLabel"); info.Size = UDim2.new(0.4, -10, 0, 22); info.Position = UDim2.new(0.58, 0, 0, 5); info.BackgroundTransparency = 1
		info.Text = string.format("[%s]", br.CPS); info.TextColor3 = Color3.fromRGB(150, 150, 150); info.TextSize = 10; info.Font = Enum.Font.Gotham; info.TextXAlignment = Enum.TextXAlignment.Right; info.Parent = h
		cbx.MouseButton1Click:Connect(function() selectedBrainrots[br.Name] = not selectedBrainrots[br.Name]; cbx.BackgroundColor3 = selectedBrainrots[br.Name] and Color3.fromRGB(80, 180, 80) or Color3.fromRGB(50, 50, 50); cbx.Text = selectedBrainrots[br.Name] and "✓" or "" end)
	end
	local mutLabel = Instance.new("TextLabel"); mutLabel.Size = UDim2.new(1, 0, 0, 22); mutLabel.BackgroundTransparency = 1
	mutLabel.Text = "🔬 Мутации (не продавать):"; mutLabel.TextColor3 = Color3.fromRGB(200, 200, 200); mutLabel.TextSize = 12; mutLabel.Font = Enum.Font.GothamBold; mutLabel.TextXAlignment = Enum.TextXAlignment.Left; mutLabel.Parent = brScroll
	local mutations = getMutationList()
	for i, mut in ipairs(mutations) do
		local h = Instance.new("Frame"); h.Size = UDim2.new(1, 0, 0, 32); h.BackgroundColor3 = Color3.fromRGB(30, 30, 30); h.BorderSizePixel = 0; h.Parent = brScroll
		Instance.new("UICorner", h).CornerRadius = UDim.new(0, 5)
		local cbx = Instance.new("TextButton"); cbx.Size = UDim2.new(0, 22, 0, 22); cbx.Position = UDim2.new(0, 6, 0, 5)
		cbx.BackgroundColor3 = mut == "None" and Color3.fromRGB(80, 180, 80) or Color3.fromRGB(50, 50, 50); cbx.TextColor3 = Color3.fromRGB(255, 255, 255)
		cbx.TextSize = 12; cbx.Font = Enum.Font.GothamBold; cbx.Text = mut == "None" and "✓" or ""; cbx.BorderSizePixel = 0; cbx.Parent = h
		Instance.new("UICorner", cbx).CornerRadius = UDim.new(0, 4)
		local nm = Instance.new("TextLabel"); nm.Size = UDim2.new(1, -34, 0, 22); nm.Position = UDim2.new(0, 32, 0, 5); nm.BackgroundTransparency = 1
		nm.Text = mut; nm.TextColor3 = Color3.fromRGB(200, 200, 200); nm.TextSize = 11; nm.Font = Enum.Font.Gotham; nm.TextXAlignment = Enum.TextXAlignment.Left; nm.Parent = h
		cbx.MouseButton1Click:Connect(function() selectedMutations[mut] = not selectedMutations[mut]; cbx.BackgroundColor3 = selectedMutations[mut] and Color3.fromRGB(80, 180, 80) or Color3.fromRGB(50, 50, 50); cbx.Text = selectedMutations[mut] and "✓" or "" end)
	end
	brScroll.CanvasSize = UDim2.new(0, 0, 0, 44 + #brainrots * 36 + 22 + #mutations * 36 + 20)
	
	-- Обновление GUI
	task.spawn(function()
		while true do
			if mainMenu.Visible then
				if updateCharacterReferences() then
					local dist, count, rarity = getClosestWaveDistance()
					kickWaveLabel.Text = string.format("Волны: %d, мин: %.0f studs (%s)", count, dist, rarity)
				end
				if bpData then
					bpInfoLabel.Text = string.format("Собрано: %d | XP: %s", claimedCount, bpData.XP or 0)
					if bpxpLabel then bpxpLabel.Text = "XP: " .. (bpData.XP or 0) end
					if bpclLabel then bpclLabel.Text = "Собрано: " .. claimedCount end
					if bpprLabel then bpprLabel.Text = "Premium: " .. (bpData.HasPremium and "ДА" or "НЕТ") end
				end
				local mn, mm, ml, mcps = getCurrentMorph()
				if bpmrLabel then bpmrLabel.Text = "Морф: " .. mn end
				if bpmuLabel then bpmuLabel.Text = "Мутация: " .. mm end
				if bplvLabel then bplvLabel.Text = "Уровень: " .. ml .. " | CPS: " .. mcps end
				
				if currentTab == "Debug" then
					for _, child in ipairs(debugScroll:GetChildren()) do if child:IsA("Frame") and child.Name ~= "UIListLayout" then child:Destroy() end end
					local attrs = getPlayerAttributes()
					local attrSec = makeSection(debugScroll, "📋 АТРИБУТЫ", 160)
					makeLabel(attrSec, 28, "InGame: " .. tostring(attrs.InGame))
					makeLabel(attrSec, 47, "KickDebounced: " .. tostring(attrs.KickDebounced))
					makeLabel(attrSec, 66, "TransformedTo: " .. tostring(attrs.TransformedTo))
					makeLabel(attrSec, 85, "TransformedMutation: " .. tostring(attrs.TransformedMutation))
					makeLabel(attrSec, 104, "TransformedLevel: " .. tostring(attrs.TransformedLevel))
					makeLabel(attrSec, 123, "HasPremium: " .. tostring(attrs.HasPremium))
					local morphSec = makeSection(debugScroll, "🧬 МОРФ", 110)
					makeLabel(morphSec, 28, "Имя: " .. mn); makeLabel(morphSec, 47, "Мутация: " .. mm)
					makeLabel(morphSec, 66, "Уровень: " .. ml); makeLabel(morphSec, 85, "CPS: " .. mcps)
					if updateCharacterReferences() then
						local posSec = makeSection(debugScroll, "📍 ПОЗИЦИЯ", 90)
						makeLabel(posSec, 28, "В KickReady: " .. (isInKickReady() and "ДА" or "НЕТ"))
						if kickReadyPos then makeLabel(posSec, 47, "Дист. до зоны: " .. string.format("%.0f studs", (rootPart.Position - kickReadyPos).Magnitude)) end
						makeLabel(posSec, 66, "Скорость: " .. math.floor(humanoid.WalkSpeed))
						local dist, count, rarity = getClosestWaveDistance()
						local waveSec = makeSection(debugScroll, "🌊 ВОЛНЫ", 90)
						makeLabel(waveSec, 28, "Количество: " .. count); makeLabel(waveSec, 47, "Ближайшая: " .. string.format("%.0f studs", dist)); makeLabel(waveSec, 66, "Редкость: " .. rarity)
					end
					local inv = scanBackpack(); local total = 0; for _, items in pairs(inv) do total = total + #items end
					local invSumSec = makeSection(debugScroll, "🎒 ИНВЕНТАРЬ", 50 + total * 18)
					makeLabel(invSumSec, 28, "Всего: " .. total); makeLabel(invSumSec, 47, "Типов: " .. table.getn(inv))
					local y = 66; for name, items in pairs(inv) do makeLabel(invSumSec, y, string.format("  %s: %d", name, #items)); y = y + 18 end
					invSumSec.Size = UDim2.new(1, 0, 0, y + 10)
					debugScroll.CanvasSize = UDim2.new(0, 0, 0, 160 + 110 + 90 + 90 + y + 30)
				end
				
				if currentTab == "Inventory" then
					for _, child in ipairs(invScroll:GetChildren()) do if child:IsA("Frame") and child.Name ~= "UIListLayout" then child:Destroy() end end
					local inv = scanBackpack(); local y = 0
					for name, items in pairs(inv) do for _, item in ipairs(items) do
						local f = Instance.new("Frame"); f.Size = UDim2.new(1, 0, 0, 50); f.BackgroundColor3 = Color3.fromRGB(30, 30, 30); f.BorderSizePixel = 0; f.Parent = invScroll
						Instance.new("UICorner", f).CornerRadius = UDim.new(0, 5)
						local n = Instance.new("TextLabel"); n.Size = UDim2.new(1, -12, 0, 22); n.Position = UDim2.new(0, 6, 0, 4); n.BackgroundTransparency = 1
						n.Text = name; n.TextColor3 = Color3.fromRGB(255, 255, 255); n.TextSize = 12; n.Font = Enum.Font.GothamBold; n.TextXAlignment = Enum.TextXAlignment.Left; n.Parent = f
						local info = Instance.new("TextLabel"); info.Size = UDim2.new(1, -12, 0, 18); info.Position = UDim2.new(0, 6, 0, 28); info.BackgroundTransparency = 1
						info.Text = string.format("LVL %d | %s | CPS: %s", item.Level, item.Mutation, item.CPS); info.TextColor3 = Color3.fromRGB(150, 150, 150); info.TextSize = 10; info.Font = Enum.Font.Gotham; info.TextXAlignment = Enum.TextXAlignment.Left; info.Parent = f
						y = y + 54
					end end
					invScroll.CanvasSize = UDim2.new(0, 0, 0, y + 10)
				end
			end
			task.wait(0.3)
		end
	end)
end

-- ============ ЗАПУСК ============
createGUI()
player.CharacterAdded:Connect(function(c) character = c; task.wait(0.5); updateCharacterReferences() end)
if player.Character then updateCharacterReferences() end
getBPData()
print("Farm Menu Complete loaded! Bonus Click с 4 методами.")
