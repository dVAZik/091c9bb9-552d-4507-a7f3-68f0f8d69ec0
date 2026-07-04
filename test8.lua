-- Добавь эту переменную к остальным:
local ENABLE_FINISH_DELAY = true

-- Добавь этот GUI элемент в настройки (после waveSettingsSection):
local delayToggleSection = sec(setScroll, "⏱ ЗАДЕРЖКА ПЕРЕД БЕГОМ", 78, Color3.fromRGB(255, 200, 150))
local delayToggleBtn = Instance.new("TextButton")
delayToggleBtn.Size = UDim2.new(1, -16, 0, 30); delayToggleBtn.Position = UDim2.new(0, 8, 0, 28)
delayToggleBtn.BackgroundColor3 = Color3.fromRGB(80, 180, 80); delayToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
delayToggleBtn.TextSize = 12; delayToggleBtn.Font = Enum.Font.GothamBold
delayToggleBtn.Text = "⏹ ВКЛЮЧЕНА"; delayToggleBtn.BorderSizePixel = 0; delayToggleBtn.Parent = delayToggleSection
Instance.new("UICorner", delayToggleBtn).CornerRadius = UDim.new(0, 5)
local delayToggleStatus = lbl(delayToggleSection, "Задержка: " .. FINISH_DELAY_MIN .. "-" .. FINISH_DELAY_MAX .. " сек", 62)

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

-- В функции applySettings() добавь обновление текста:
delayToggleStatus.Text = ENABLE_FINISH_DELAY and "Задержка: " .. FINISH_DELAY_MIN .. "-" .. FINISH_DELAY_MAX .. " сек" or "Задержка: ОТКЛЮЧЕНА"

-- Измени moveToFinish():
local function moveToFinish()
	if not updateCharacterReferences() then return false end
	if not humanoid or not rootPart or not kickReadyPos then return false end
	if humanoid.Health <= 0 then return false end
	if isInKickReady() then return true end
	
	waitForCameraOnPlayer()
	
	-- Задержка только если включена
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
