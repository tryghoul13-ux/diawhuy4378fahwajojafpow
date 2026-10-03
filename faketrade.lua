-- faketrade.lua — ТЕСТ: косметический трейд с фантомом. ТОЛЬКО картинка на твоём экране.
-- Кнопка «Трейд (тест)»: окно трейда MM2 (клон) → фантом постепенно кладёт 2-4 предмета (по 1-2,
-- с паузами) → кулдаун 6с (принять нельзя) → фантом принимает → ТЫ сам жмёшь Accept/Confirm →
-- родная презентация «You Got…» по центру и улёт в инвентарь (по каждому предмету).
-- НИЧЕГО не пишется в инвентарь, никаких реальных ников, предметов по факту нет. Реквизит.
-- Запуск:  loadstring(readfile('faketrade.lua'))()

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local lp = Players.LocalPlayer
local gui = lp:WaitForChild("PlayerGui")
local env = (getgenv and getgenv()) or _G

-- модули игры: картинки/презентация + МОЙ инвентарь для панели слева (только чтение, ничего не меняем).
local Sync, ItemModule, ItemPopupService, ProfileData, InventoryModule
pcall(function()
	Sync = require(RS.Database.Sync)
end)
pcall(function()
	ItemModule = require(RS.Modules.ItemModule)
end)
pcall(function()
	InventoryModule = require(RS.Modules.InventoryModule)
end)
-- презентация «You Got…» + ProfileData (мой инвентарь) — требуют низкую thread identity.
-- Идентити восстанавливаем ОБЯЗАТЕЛЬНО, даже если require упал (иначе весь скрипт останется на 2
-- и DisplayItem/HttpGet начнут молча падать → в трейд ничего не кладётся).
local _idOld = (getthreadidentity and getthreadidentity()) or 8
pcall(function()
	if setthreadidentity then
		setthreadidentity(2)
	end
end)
pcall(function()
	ItemPopupService = require(RS.ClientServices.ItemPopupService)
end)
pcall(function()
	ProfileData = require(RS.Modules.ProfileData)
end)
pcall(function()
	if setthreadidentity then
		setthreadidentity(_idOld)
	end
end)

local FAKE_NAMES = {
	"ProSniper_2011", "xXDarkWolfXx", "Katya_plays", "itz_mia07", "Dmitry1337",
	"sofiaa_xo", "NoScope_King", "Vanya_2012", "ZxcBoy_77", "Lunaa_games",
	"Max_Power99", "Alina_cute", "Ghost_Rider22", "nagibator_07", "Timofey2013",
	"Milana_star", "RBLX_Jake", "coolkid_2011", "Nastya_xd", "Kirill_pro",
	"ShadowGamerr", "iiSashaii", "Dragon_2012", "emma_plays7", "zombie_slayer1",
	"Lucky_Nikita", "pixel_girl_", "Artem_777", "snowww_xo", "DarkLord_99",
	"Tommy_gamerr", "Kristina_07", "oof_master22", "Vlad_2013", "cherry_mia",
	"NubGamer_xd", "Sofia_rblx", "red_panda77", "Egor_pro12", "sweetie_2011",
}
local function pick(t)
	return t[math.random(1, #t)]
end

local nameFixes = {
	SunsetKnife = "Sunset", SunsetGun = "Sunrise", TravelerAxe = "Traveler's Axe",
	TravelerGun = "Traveler's Gun", SwirlyGun = "Swirly Gun", SwirlyAxe = "Swirly Axe",
	IceHammer = "Ice Hammer", ElderwoodKnife = "Elderwood Knife", ElderwoodGun = "Elderwood Gun",
	TreeKnife2023 = "Evergreen", TreeGun2023 = "Evergun",
}

-- Примерная ценность предметов. ТОЛЬКО годли и выше (ancient) — ни комонок, ни ниже.
-- Значения приблизительные, статичные. Если нужно точно — подвяжу живые цены dreampets (как invcalc).
local VALUES = {
	-- godly ножи
	Chill = 600, Heat = 750, Tides = 900, Slasher = 800, Saw = 700, Fang = 1500, Deathshard = 1800,
	Gemstone = 3500, TheSeer = 4500, Ghostblade = 550, Nightblade = 650, Frostbite = 700,
	VampiresEdge = 900, Frostsaber = 1200, WintersEdge = 1600, Boneblade = 1500, Snowflake = 1800,
	IceShard = 1300, Gingerblade = 1800, Cookieblade = 1500, Peppermint = 1200, Bioblade = 1100,
	Heartblade = 1500, Eggblade = 1200, Candleflame = 2000, SwirlyBlade = 2500, Iceflake = 2000,
	Plasmablade = 2500, ElderwoodKnife = 2800, Phantom = 3200, Sakura_K = 2000, Rainbow = 3000,
	Waves_K = 2600, Darksword = 2600, Bloom = 2000, SunsetKnife = 3200, XenoKnife = 2600,
	Celestial = 4200, SnowDagger = 2500, Blizzard = 3000, UFOKnife = 3500, BaubleKnife = 2000,
	Clockwork = 4800, Pixel = 2000, Virtual = 2500, BigKill = 2000, Spider = 2000, Candy = 1500,
	Handsaw = 1500, Xmas = 2000, HallowsBlade = 1800, IceDragon = 3200, Flames = 3600,
	BattleAxe = 2000, Pumpking = 2600, TreeKnife2023 = 2600, FlowerwoodKnife = 2000,
	-- godly пистолеты
	Luger = 1500, Shark = 1200, Laser = 1200, Blaster = 1500, Lugercane = 2600, Darkbringer = 3600,
	Lightbringer = 3600, Amerilaser = 2000, Sugar = 1500, ElderwoodGun = 2800, Minty = 1500,
	GingerLuger = 1500, Jinglegun = 1200, Iceblaster = 1200, Hallowgun = 1800, SwirlyGun = 2000,
	Icebeam = 2000, Plasmabeam = 2600, Makeshift = 2600, Spectre2022 = 2000, RainbowGun = 3000,
	Darkshot = 2600, TravelerGun = 1800, TreeGun2023 = 2600, FlowerwoodGun = 2000, Watergun = 2600,
	VampireGun = 2000, Constellation = 4200, Bauble = 2000, Flora = 2600, SunsetGun = 3200,
	Raygun = 3600, XenoGun = 2600, Snowcannon = 2600, Snowstorm = 3000, GreenLuger = 2000, RedLuger = 2000,
	-- ancients
	SwirlyAxe = 4800, TravelerAxe = 3600, VampireAxe = 4200, IceHammer = 3000, Icebreaker = 2600,
	Logchopper = 2600, Harvester = 3000, Hallowscythe = 3600, Icewing = 4200, ElderwoodScythe = 4800,
	Gingerscythe = 3600, Gingerscope = 3000, Icepiercer = 3000, Synthwave = 4800,
}

-- тематические сеты (нож/топор + пистолет одной темы) — иногда фантом кидает именно сет
local SETS = {
	{ "VampireAxe", "VampireGun" },
	{ "SwirlyAxe", "SwirlyGun" },
	{ "TravelerAxe", "TravelerGun" },
	{ "ElderwoodKnife", "ElderwoodGun", "ElderwoodScythe" },
	{ "SunsetKnife", "SunsetGun" },
	{ "TreeKnife2023", "TreeGun2023" },
	{ "XenoKnife", "XenoGun" },
	{ "BaubleKnife", "Bauble" },
	{ "FlowerwoodKnife", "FlowerwoodGun" },
	{ "Gingerscythe", "Gingerscope", "GingerLuger" },
}

-- ЦЕНЫ живьём с маркета dreampets (как invcalc) — чтобы валуе было настоящим. Напр. Gingerscope
-- реально дороже 5000 и в трейд не попадёт. Если сайт недоступен — фолбэк на VALUES выше.
local HttpService = game:GetService("HttpService")
local DP_API = "https://mm2-test.dreampets.gg/api/market/v1/market/products"
local VAL_MIN, VAL_MAX = 500, 15000

local function norm(s)
	return (tostring(s or ""):lower():gsub("[^%w]", ""))
end
local function pkey(name, cat, chroma, rarity)
	return norm(name) .. "|" .. tostring(cat or ""):lower() .. "|" .. (chroma and "c" or "-") .. "|" .. tostring(rarity or ""):lower()
end
local dpPrice, dpLoose = {}, {}
local function fetchPrices()
	local offset = 0
	for _ = 1, 20 do
		local body = game:HttpGet(DP_API .. "?search=&currency=rub&sort=popularity_desc&limit=1000&offset=" .. offset)
		local data = HttpService:JSONDecode(body)
		local page = (type(data) == "table") and data.products
		if type(page) ~= "table" or #page == 0 then
			break
		end
		for _, p in ipairs(page) do
			local price = tonumber(p.min_price)
			if price and type(p.name) == "string" then
				local chroma = p.chroma == true
				local k = pkey(p.name, p.category, chroma, p.rarity)
				if not dpPrice[k] or price < dpPrice[k] then
					dpPrice[k] = price
				end
				local lk = pkey(p.name, p.category, chroma, "")
				if not dpLoose[lk] or price < dpLoose[lk] then
					dpLoose[lk] = price
				end
			end
		end
		offset += #page
	end
end
local dpOk = pcall(fetchPrices)

local function priceForItem(id, e)
	local p = dpPrice[pkey(e.ItemName, e.ItemType, e.Chroma == true, e.Rarity)]
	if not p then
		p = dpLoose[pkey(e.ItemName, e.ItemType, e.Chroma == true, "")]
	end
	if not p then
		p = VALUES[id] -- фолбэк, если предмета нет на маркете / сайт недоступен
	end
	return p
end

-- цветные варианты (Bronze/Gold/Silver/Red/Blue/Purple/Green) в трейд не берём — не нужны
local COLORS = { "Bronze", "Gold", "Silver", "Red", "Blue", "Purple", "Green" }
local function isColorVariant(id)
	for _, c in ipairs(COLORS) do
		if id:find("^" .. c) or id:find(c .. "$") or id:find("_" .. c) then
			return true
		end
	end
	return false
end

-- пул: godly/ancient/unique нож-пистолет (не хрома, не цветной вариант), с ценой в [VAL_MIN,VAL_MAX]
local pool, poolSet, priceById = {}, {}, {}
if Sync and type(Sync.Item) == "table" then
	for id, e in pairs(Sync.Item) do
		local sid = tostring(id)
		if type(e) == "table" and (e.ItemType == "Knife" or e.ItemType == "Gun")
			and not sid:find("^Default") and not isColorVariant(sid) and e.Image ~= nil and e.Chroma ~= true then
			local rar = tostring(e.Rarity or ""):lower()
			if rar == "godly" or rar == "ancient" or rar == "unique" then
				local p = priceForItem(id, e)
				if p and p >= VAL_MIN and p <= VAL_MAX then
					pool[#pool + 1] = id
					poolSet[id] = true
					priceById[id] = p
				end
			end
		end
	end
end

-- бенды «богатства»: то поскромнее, то средний, то дорогой — для разнообразия
local bands = { { VAL_MIN, 2500 }, { 2000, 7000 }, { 6000, VAL_MAX } }
-- валидные сеты (хотя бы 2 предмета набора попали в пул по цене)
local setCands = {}
for _, s in ipairs(SETS) do
	local valid = {}
	for _, id in ipairs(s) do
		if poolSet[id] then
			valid[#valid + 1] = id
		end
	end
	if #valid >= 2 then
		setCands[#setCands + 1] = valid
	end
end
local function pickInBand(band)
	local cands = {}
	for _, id in ipairs(pool) do
		local v = priceById[id]
		if v and v >= band[1] and v <= band[2] then
			cands[#cands + 1] = id
		end
	end
	return (#cands > 0) and pick(cands) or (#pool > 0 and pick(pool) or nil)
end
-- что положит фантом: иногда сет (2-3 темы), иначе 1-3 РАЗНЫХ предмета в случайном бенде (без стака)
local function buildTrade()
	local chosen, used = {}, {}
	local function addId(id)
		if id and not used[id] then
			used[id] = true
			chosen[#chosen + 1] = id
		end
	end
	if #setCands > 0 and math.random() < 0.45 then
		local s = pick(setCands)
		local n = math.min(#s, math.random(2, 3))
		for i = 1, n do
			addId(s[i])
		end
	else
		local total = math.random(1, 3)
		local band = pick(bands)
		local tries = 0
		while #chosen < total and tries < 40 do
			addId(pickInBand(band))
			tries += 1
		end
	end
	return chosen
end

-- рисуем предмет в карточку (как v34: копия полей, DataType, имя, слои Chroma/Fx) + убираем «••»
local function displayInto(slot, itemId)
	-- клон лежит в CoreGui — для доступа к нему нужен высокий identity (иначе "lacking capability Plugin")
	pcall(function()
		if setthreadidentity then
			setthreadidentity(8)
		end
	end)
	local e = Sync.Item[itemId]
	if not (slot and type(e) == "table" and ItemModule and ItemModule.DisplayItem) then
		return
	end
	local data = {}
	for k, v in pairs(e) do
		data[k] = v
	end
	data.DataType = "Weapons"
	data.Amount = 1
	local displayName = e.ItemName or e.Name or itemId
	if nameFixes[itemId] then
		displayName = nameFixes[itemId]
	end
	data.ItemName = displayName
	data.Name = displayName
	pcall(function()
		ItemModule.DisplayItem(slot, data)
	end)
	-- слои Chroma/Fx, чтобы не налезали
	pcall(function()
		local container = slot:FindFirstChild("Container")
		if container then
			for _, obj in ipairs(container:GetDescendants()) do
				if obj:IsA("TextLabel") or obj:IsA("ImageLabel") then
					local n = string.lower(obj.Name)
					if string.find(n, "fx") then
						obj.ZIndex = 10
					elseif string.find(n, "chroma") then
						obj.ZIndex = 9
					end
				end
			end
		end
	end)
	-- «точки» над предметом = лейбл количества (Amount) со значением "..". При 1 шт. делаем пустым.
	-- DisplayItem выставляет его с задержкой, поэтому чистим сразу, на следующий кадр и через 0.12с.
	-- лейбл количества (Amount="..") держим пустым/скрытым, в т.ч. если DisplayItem пересоздаёт его позже
	local function isDotsText(s)
		s = tostring(s)
		return s == ".." or s == "." or s == "..." or s == "•" or s == "••"
	end
	local function hookAmount(d)
		if (d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox"))
			and (d.Name == "Amount" or isDotsText(d.Text)) then
			local function hide()
				if d.Text ~= "" then
					d.Text = ""
				end
				if d.Visible then
					d.Visible = false
				end
			end
			hide()
			pcall(function()
				d:GetPropertyChangedSignal("Text"):Connect(hide)
				d:GetPropertyChangedSignal("Visible"):Connect(hide)
			end)
		end
	end
	for _, d in ipairs(slot:GetDescendants()) do
		hookAmount(d)
	end
	slot.DescendantAdded:Connect(hookAmount)
	slot.Visible = true
end

-- презентация «получил предмет»: РОДНАЯ из игры (как в твоём скрипте). В инвентарь НИЧЕГО не пишем.
local function playReceiveAnim(itemId)
	if ItemPopupService and ItemPopupService.ItemReceived then
		local ok = pcall(function()
			ItemPopupService.ItemReceived:Fire(itemId, "Weapons")
		end)
		if ok then
			return
		end
	end
	-- запасной вариант: своя картинка по центру → в инвентарь
	local e = Sync.Item[itemId]
	local img = e and e.Image
	if not img then
		return
	end
	local sg2 = Instance.new("ScreenGui")
	sg2.Name = "FakeTradeAnim"
	sg2.IgnoreGuiInset = true
	sg2.DisplayOrder = 600
	sg2.ResetOnSpawn = false
	sg2.Parent = gui -- PlayerGui (CoreGui недоступен из task.spawn в этом Delta)
	local pic = Instance.new("ImageLabel")
	pic.BackgroundTransparency = 1
	pic.AnchorPoint = Vector2.new(0.5, 0.5)
	pic.Position = UDim2.fromScale(0.5, 0.5)
	pic.Size = UDim2.fromOffset(0, 0)
	pic.Image = (typeof(img) == "number") and ("rbxassetid://" .. img) or tostring(img)
	pic.Parent = sg2
	task.spawn(function()
		TweenService:Create(pic, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.fromOffset(180, 180),
		}):Play()
		task.wait(0.9)
		TweenService:Create(pic, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.fromScale(0.5, 0.93),
			Size = UDim2.fromOffset(28, 28),
			ImageTransparency = 0.25,
		}):Play()
		task.wait(0.62)
		TweenService:Create(pic, TweenInfo.new(0.15), { ImageTransparency = 1 }):Play()
		task.wait(0.2)
		pcall(function()
			sg2:Destroy()
		end)
	end)
end

local busy = false
local function runFakeTrade()
	if busy then
		return
	end
	local realGui = gui:FindFirstChild("TradeGUI")
	if not realGui then
		warn("[ФейкТрейд] TradeGUI не найден — ты точно в игре?")
		return
	end
	if #pool == 0 then
		warn("[ФейкТрейд] пул предметов пуст (база не загрузилась?)")
		return
	end
	busy = true

	if env.FakeTradeGui then
		pcall(function()
			env.FakeTradeGui:Destroy()
		end)
	end
	local tg = realGui:Clone()
	tg.Name = "FakeTradeGUI"
	tg.Enabled = true
	pcall(function()
		tg.ResetOnSpawn = false
	end)
	tg.Parent = gui -- PlayerGui: доступен при обычном identity (в CoreGui task.spawn не достучаться)
	env.FakeTradeGui = tg

	local function finish()
		pcall(function()
			tg:Destroy()
		end)
		env.FakeTradeGui = nil
		busy = false
	end

	local trade = tg:FindFirstChild("Container")
	trade = trade and trade:FindFirstChild("Trade")
	if not trade then
		finish()
		warn("[ФейкТрейд] нет Container.Trade в окне")
		return
	end
	local their = trade:FindFirstChild("TheirOffer")
	local yours = trade:FindFirstChild("YourOffer")
	local theirCont = their and their:FindFirstChild("Container")

	local function clearOffer(off)
		local cont = off and off:FindFirstChild("Container")
		if cont then
			for _, c in ipairs(cont:GetChildren()) do
				if c:IsA("GuiObject") and c.Name:find("^NewItem") then
					c.Visible = false
				end
			end
		end
		local acc = off and off:FindFirstChild("Accepted")
		if acc then
			acc.Visible = false
		end
	end
	clearOffer(their)
	clearOffer(yours)

	-- имя фантома (НЕ реальный игрок)
	local phantom = pick(FAKE_NAMES)
	local un = their and their:FindFirstChild("Username")
	if un and un:IsA("TextLabel") then
		un.Text = "(" .. phantom .. ")"
	end

	-- кнопки/кулдаун
	local actions = trade:FindFirstChild("Actions")
	local acc = actions and actions:FindFirstChild("Accept")
	local confirm = acc and acc:FindFirstChild("Confirm")
	local cancel = acc and acc:FindFirstChild("Cancel")
	local addItem = acc and acc:FindFirstChild("AddItem")
	local cooldown = acc and acc:FindFirstChild("Cooldown")
	local cdTitle = cooldown and cooldown:FindFirstChild("Title")
	if confirm then
		confirm.Visible = false
	end
	if cancel then
		cancel.Visible = false
	end
	if addItem then
		addItem.Visible = false
	end

	local offered = buildTrade() -- что положит фантом (сет или 1-3 по бенду)
	local addingDone = false
	local cdEnd = math.huge -- принять нельзя, пока не выставим
	local state = "Accept"
	local phantomAccepted = false
	local myConfirmed = false
	local tryComplete -- трейд завершается ТОЛЬКО когда обе стороны приняли

	-- МОЙ реальный инвентарь — в панель СЛЕВА (как в настоящем трейде), а не в оффер.
	-- В ОТДЕЛЬНОМ потоке: GenerateInventory может подвиснуть на клоне и заблокировать весь трейд.
	task.spawn(function()
		pcall(function()
			if setthreadidentity then
				setthreadidentity(8)
			end
		end)
		pcall(function()
			local items = trade.Parent and trade.Parent:FindFirstChild("Items")
			if InventoryModule and ProfileData and items then
				InventoryModule.GenerateInventory(items, ProfileData, "Trading")
			end
		end)
	end)

	-- фантом добавляет предметы постепенно: окно открылось → пауза 1.5-2.5с → первый предмет,
	-- затем остальные по одному (иногда по 2), с паузами
	task.spawn(function()
		pcall(function()
			if setthreadidentity then
				setthreadidentity(8)
			end
		end)
		task.wait(1.5 + math.random())
		local idx = 0
		while idx < #offered do
			local batch = math.min((math.random() < 0.25) and 2 or 1, #offered - idx)
			for _ = 1, batch do
				idx += 1
				displayInto(theirCont and theirCont:FindFirstChild("NewItem" .. idx), offered[idx])
			end
			local a = their and their:FindFirstChild("Accepted")
			if a then
				a.Visible = false
			end
			if idx < #offered then
				task.wait(1 + math.random() * 1.4)
			end
		end
		addingDone = true
		cdEnd = os.clock() + 6
		if cooldown then
			cooldown.Visible = true
		end
		for n = 6, 1, -1 do
			if cdTitle and cdTitle:IsA("TextLabel") then
				cdTitle.Text = " Please wait (" .. n .. ") before accepting."
			end
			task.wait(1)
		end
		if cooldown then
			cooldown.Visible = false
		end
		-- фантом принимает через 1-2с после отсчёта (не мгновенно)
		task.wait(1 + math.random())
		phantomAccepted = true
		local a2 = their and their:FindFirstChild("Accepted")
		if a2 then
			a2.Visible = true
		end
		if tryComplete then
			tryComplete()
		end
	end)

	-- завершение (ТОЛЬКО когда обе стороны приняли): окно → родная раздача. Ноль в инвентарь.
	local function complete()
		if state == "Done" then
			return
		end
		state = "Done"
		task.wait(0.45)
		finish()
		task.spawn(function()
			if ItemPopupService and ItemPopupService.ItemReceived then
				for _, id in ipairs(offered) do
					pcall(function()
						ItemPopupService.ItemReceived:Fire(id, "Weapons")
					end)
				end
			else
				for _, id in ipairs(offered) do
					playReceiveAnim(id)
					task.wait(1.0)
				end
			end
		end)
	end
	tryComplete = function()
		if phantomAccepted and myConfirmed and state ~= "Done" then
			complete()
		end
	end

	local function wire(frame, fn)
		local b = frame and frame:FindFirstChild("ActionButton")
		if not b and frame and frame:IsA("GuiButton") then
			b = frame
		end
		if b and b:IsA("GuiButton") then
			b.Active = true
			b.MouseButton1Click:Connect(function()
				pcall(function()
					if setthreadidentity then
						setthreadidentity(8)
					end
				end)
				fn()
			end)
		end
	end

	-- моё принятие: ставлю галочку и пробую завершить (завершится, ТОЛЬКО если фантом тоже принял)
	local function myAccept()
		myConfirmed = true
		local a = yours and yours:FindFirstChild("Accepted")
		if a then
			a.Visible = true
		end
		tryComplete()
	end

	-- Accept жмёшь ТЫ (после добавления и кулдауна) → Confirm → ждём принятие обеих сторон
	wire(acc, function()
		if not addingDone or os.clock() < cdEnd or state ~= "Accept" then
			return
		end
		state = "Confirm"
		if confirm then
			confirm.Visible = true
		else
			myAccept()
		end
	end)
	wire(confirm, function()
		if state ~= "Confirm" then
			return
		end
		if cancel then
			cancel.Visible = true
		end
		myAccept()
	end)
	wire(cancel, function()
		state = "Accept"
		myConfirmed = false
		if confirm then
			confirm.Visible = false
		end
		if cancel then
			cancel.Visible = false
		end
		local a = yours and yours:FindFirstChild("Accepted")
		if a then
			a.Visible = false
		end
	end)
	wire(actions and actions:FindFirstChild("Decline"), finish)
end

-- кнопка-триггер (перетаскиваемая)
if env.FakeTradeBtnGui then
	pcall(function()
		env.FakeTradeBtnGui:Destroy()
	end)
end
local sg = Instance.new("ScreenGui")
sg.Name = "FakeTradeBtnGui"
sg.ResetOnSpawn = false
sg.DisplayOrder = 500
sg.Parent = gui -- PlayerGui
env.FakeTradeBtnGui = sg

local btn = Instance.new("TextButton")
btn.Size = UDim2.fromOffset(160, 40)
btn.Position = UDim2.fromScale(0.5, 0.12)
btn.AnchorPoint = Vector2.new(0.5, 0.5)
btn.BackgroundColor3 = Color3.fromRGB(60, 140, 80)
btn.TextColor3 = Color3.new(1, 1, 1)
btn.Font = Enum.Font.FredokaOne
btn.TextSize = 16
btn.AutoButtonColor = true
btn.Text = "▶ Трейд (тест)"
btn.Parent = sg
local cr = Instance.new("UICorner")
cr.CornerRadius = UDim.new(0, 8)
cr.Parent = btn

local drag, dStart, sPos
btn.InputBegan:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
		drag = true
		dStart = i.Position
		sPos = btn.Position
	end
end)
UIS.InputChanged:Connect(function(i)
	if drag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
		local d = i.Position - dStart
		btn.Position = UDim2.new(sPos.X.Scale, sPos.X.Offset + d.X, sPos.Y.Scale, sPos.Y.Offset + d.Y)
	end
end)
UIS.InputEnded:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
		drag = false
	end
end)

btn.Activated:Connect(runFakeTrade)

print(("[ФейкТрейд] готово. dreampets: %s · пул: %d · ProfileData: %s · InventoryModule: %s. Жми «Трейд (тест)»."):format(
	dpOk and "ок" or "фолбэк", #pool, ProfileData and "ок" or "нет", InventoryModule and "ок" or "нет"))
