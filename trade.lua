-- faketrade.lua — ТЕСТ: косметический трейд с фантомом. ТОЛЬКО картинка на твоём экране.
-- Кнопка «Трейд (тест)»: окно трейда MM2 (клон) → фантом постепенно кладёт 2-4 предмета (по 1-2,
-- с паузами) → кулдаун 6с (принять нельзя) → фантом принимает → ТЫ сам жмёшь Accept/Confirm →
-- родная презентация «You Got…» по центру и улёт в инвентарь (по каждому предмету).
-- Предметы появляются в инвентаре ТОЛЬКО в локальной копии профиля на клиенте: сервер о них не знает,
-- после перезахода пропадут. Никаких реальных ников, предметов по факту нет. Реквизит.
-- Запуск:  loadstring(readfile('trade.lua'))()

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

-- Партнёр по трейду — ВЫДУМАННЫЙ ник, не реальный игрок: сделка-реквизит не должна выглядеть
-- как действие конкретного живого человека. Реальные аккаунты — только в лидерборде (fakeplayers).
local FAKE_NAMES = {
	"Tori_x_plays", "blxckfox_07", "NovaStrike21", "kitty_cat_2012", "Ryder_Gamez",
	"ZaneTheGreat", "pixelmochi9", "IcyWolf_44", "Marco_plays_", "SunnyDays_07",
	"Axel_Dragon", "lunar_bunny12", "Kade_RBLX", "StarFall_Mia", "ToastyBear_",
	"Jett_2013", "velvet_owl88", "TurboNoodle", "Cinder_Kat", "Dex_Plays_Yt",
	"FrostedFlake_", "Orion_Gamer7", "peachy_lena", "HyperKiwi09", "Nolan_xx_",
	"ShadowMoth_", "CrunchyBean", "Zephyr_Kid", "mintchoco_44", "BlazeRunner23",
	"Quinn_Plays", "RustyTaco_", "Wren_x_09", "OtterBoi_7",
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
local VAL_MIN, VAL_MAX = 1, 15000 -- снизу без порога: дешёвых годли на рынке больше всего — это и есть разнообразие

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

-- «Богатство» трейда по реальным ценам dreampets: чаще нищий, реже средний, редко дорогой.
-- weight — как часто выпадает уровень (из 1000)
local bands = {
	{ min = VAL_MIN, max = 700, weight = 900 }, -- нищий ~90%: ~100 разных годли/ancient до 700 ₽
	{ min = 600, max = 2500, weight = 85 }, -- средний ~8.5%: Sunset, Bauble, Sakura…
	{ min = 2000, max = VAL_MAX, weight = 15 }, -- дорогой ~1.5% (очень редко): Vampire's Axe, Celestial, Evergun…
}
local function rollBand()
	local total = 0
	for _, b in ipairs(bands) do
		total += b.weight
	end
	local r = math.random() * total
	for _, b in ipairs(bands) do
		r -= b.weight
		if r <= 0 then
			return b
		end
	end
	return bands[1]
end
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
-- Память последних выданных предметов: пока в уровне есть другие, недавние не повторяем —
-- так за ~20 выданных предметов один и тот же почти не встречается дважды
local RECENT_MAX = 20
local recent, recentCount = {}, {}
local function remember(id)
	recent[#recent + 1] = id
	recentCount[id] = (recentCount[id] or 0) + 1
	while #recent > RECENT_MAX do
		local old = table.remove(recent, 1)
		recentCount[old] -= 1
		if recentCount[old] <= 0 then
			recentCount[old] = nil
		end
	end
end
-- предмет уровня: сначала из тех, что давно не выпадали; exclude — уже лежат в этом трейде
local function pickInBand(band, exclude)
	local fresh, any = {}, {}
	for _, id in ipairs(pool) do
		local v = priceById[id]
		if v and v >= band.min and v <= band.max and not exclude[id] then
			any[#any + 1] = id
			if not recentCount[id] then
				fresh[#fresh + 1] = id
			end
		end
	end
	if #fresh > 0 then
		return pick(fresh)
	end
	return (#any > 0) and pick(any) or nil
end
-- Сколько предметов кладёт фантом: в основном один
local function rollCount()
	local r = math.random(1, 100)
	if r <= 72 then
		return 1
	elseif r <= 93 then
		return 2
	end
	return 3
end
-- что положит фантом: сначала выпадает уровень богатства, потом изредка сет ЭТОГО уровня
-- (все предметы сета не дороже потолка уровня), иначе 1-3 РАЗНЫХ предмета уровня (чаще один)
local prevSet = nil
local function buildTrade()
	local band = rollBand()
	local chosen, used = {}, {}
	local function addId(id)
		if id and not used[id] then
			used[id] = true
			chosen[#chosen + 1] = id
		end
	end
	local fitting = {}
	for _, s in ipairs(setCands) do
		local fits = s ~= prevSet -- не тот же сет, что в прошлый раз
		for _, id in ipairs(s) do
			if (priceById[id] or math.huge) > band.max then
				fits = false
				break
			end
		end
		if fits then
			fitting[#fitting + 1] = s
		end
	end
	if #fitting > 0 and math.random() < 0.12 then
		local s = pick(fitting)
		prevSet = s
		-- сет обычно парой; тройкой — изредка, если в нём три предмета
		local n = (#s >= 3 and math.random() < 0.25) and 3 or 2
		for i = 1, n do
			addId(s[i])
		end
	else
		prevSet = nil
		for _ = 1, rollCount() do
			addId(pickInBand(band, used))
		end
	end
	if #chosen == 0 and #pool > 0 then
		addId(pick(pool)) -- уровень оказался пустым — кладём хоть что-то
	end
	for _, id in ipairs(chosen) do
		remember(id)
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

-- ВИЗУАЛЬНО в инвентарь. Дописываем предмет в ЛОКАЛЬНУЮ копию профиля (ProfileData на клиенте) через
-- родной клиентский обработчик профиля — игра сама перерисует инвентарь. На сервер ничего не уходит,
-- после перезахода всё пропадёт. Экипировать такие предметы не надо: сервер о них не знает.
local RemInv = RS:FindFirstChild("Remotes") and RS.Remotes:FindFirstChild("Inventory")
env.FakeOwned = env.FakeOwned or {} -- { itemId = сколько фейковых штук } — переживает перезапуск скрипта
env.FakeExpected = env.FakeExpected or {} -- { itemId = сколько должно быть в профиле с фейками }
local fakeOwned, expected = env.FakeOwned, env.FakeExpected

-- лог продолжается между перезапусками (иначе повторный запуск затирает строки прошлого трейда)
local logBuf = {}
pcall(function()
	for line in tostring(readfile("trade_log.txt")):gmatch("[^\n]+") do
		logBuf[#logBuf + 1] = line
	end
end)
logBuf[#logBuf + 1] = "---- запуск ----"
local logDirty = false
local function tlog(s)
	s = tostring(s)
	print("[ФейкТрейд] " .. s)
	logBuf[#logBuf + 1] = os.date("%H:%M:%S") .. " " .. s
	if #logBuf > 200 then
		table.remove(logBuf, 1)
	end
	logDirty = true
	pcall(writefile, "trade_log.txt", table.concat(logBuf, "\n"))
end
-- из потоков кликов writefile может молча не работать — дописываем лог из своего потока (как reader)
env.FakeTradeRun = (env.FakeTradeRun or 0) + 1
local myRun = env.FakeTradeRun
task.spawn(function()
	while env.FakeTradeRun == myRun do
		task.wait(0.5)
		if logDirty then
			logDirty = false
			pcall(writefile, "trade_log.txt", table.concat(logBuf, "\n"))
		end
	end
end)

local function profileOk()
	return type(ProfileData) == "table" and type(ProfileData.Weapons) == "table"
		and type(ProfileData.Weapons.Owned) == "table"
end
local function ownedCount(id)
	return profileOk() and tonumber(ProfileData.Weapons.Owned[id]) or 0
end

-- обработчик ремоута внутри модуля ProfileData (тот, что обновляет профиль, когда сервер шлёт изменения)
local function profileHandler(remoteName)
	local r = RemInv and RemInv:FindFirstChild(remoteName)
	if not (getconnections and r) then
		return nil
	end
	local ok, conns = pcall(getconnections, r.OnClientEvent)
	if not ok or type(conns) ~= "table" then
		return nil
	end
	for _, c in ipairs(conns) do
		local f = c.Function
		local okS, src = pcall(debug.info, f, "s")
		if f and okS and tostring(src):find("ProfileData") then
			return f
		end
	end
	return nil
end

-- снимок профиля, чтобы откатить попытку с неверным форматом аргументов
local function copyOf(t)
	local c = {}
	if type(t) == "table" then
		for k, v in pairs(t) do
			c[k] = v
		end
	end
	return c
end
local function syncTo(t, src)
	for k in pairs(t) do
		if src[k] == nil then
			t[k] = nil
		end
	end
	for k, v in pairs(src) do
		t[k] = v
	end
end
local function snapshot()
	local W = ProfileData.Weapons
	return { top = copyOf(ProfileData), W = W, w = copyOf(W), O = W.Owned, o = copyOf(W.Owned) }
end
local function restore(s)
	syncTo(ProfileData, s.top)
	syncTo(s.W, s.w)
	syncTo(s.O, s.o)
end

-- формат аргументов обработчика точно не известен — пробуем по очереди, проверяем по ProfileData,
-- удачный способ запоминаем (env.FakeInvMethod) и дальше начинаем с него
local INV_METHODS = {
	{ "CII(тип,id,кол-во)", function(id, prev, target)
		profileHandler("ChangeInventoryItem")("Weapons", id, target)
	end },
	{ "CII(тип,id,+1)", function(id, prev, target)
		profileHandler("ChangeInventoryItem")("Weapons", id, target - prev)
	end },
	{ "CII(id,тип,кол-во)", function(id, prev, target)
		profileHandler("ChangeInventoryItem")(id, "Weapons", target)
	end },
	{ "CPD(Weapons,таблица)", function(id, prev, target)
		local W = copyOf(ProfileData.Weapons)
		W.Owned = copyOf(W.Owned)
		W.Owned[id] = target
		profileHandler("ChangeProfileData")("Weapons", W)
	end },
}

-- запасной вариант: пишем в профиль сами и дёргаем локальные сигналы «инвентарь изменился»
local function directAdd(id, target)
	ProfileData.Weapons.Owned[id] = target
	for _, bn in ipairs({ "InventoryDataChanged", "ProfileDataChanged" }) do
		local b = RemInv and RemInv:FindFirstChild(bn)
		if b and b:IsA("BindableEvent") then
			pcall(function()
				b:Fire("Weapons")
			end)
		end
	end
end

local function addOne(id, target)
	local prev = ownedCount(id)
	if prev == target then
		return
	end
	local order = { env.FakeInvMethod }
	for i = 1, #INV_METHODS do
		if i ~= env.FakeInvMethod then
			order[#order + 1] = i
		end
	end
	for _, i in ipairs(order) do
		local m = INV_METHODS[i]
		local snap = snapshot()
		local ok, err = pcall(m[2], id, prev, target)
		local now = ownedCount(id)
		if ok and now == target then
			if env.FakeInvMethod ~= i then
				env.FakeInvMethod = i
				tlog("инвентарь: способ «" .. m[1] .. "» сработал")
			end
			return
		end
		restore(snap)
		tlog(("инвентарь: «%s» не подошёл (%s, было %d, стало %d)"):format(
			m[1], ok and "без ошибки" or tostring(err):sub(1, 120), prev, now))
	end
	local ok, err = pcall(directAdd, id, target)
	tlog("инвентарь: запасной способ (прямо в профиль + сигнал) " .. (ok and "ок" or ("ошибка " .. tostring(err))))
end

local applying = false
local function addToInventory(list)
	if not profileOk() then
		tlog("инвентарь: ProfileData недоступен — в инвентарь не добавить")
		return
	end
	applying = true
	local res = {}
	for _, id in ipairs(list) do
		fakeOwned[id] = (fakeOwned[id] or 0) + 1
		addOne(id, ownedCount(id) + 1)
		expected[id] = ownedCount(id)
		res[#res + 1] = id .. "=" .. expected[id]
	end
	applying = false
	tlog("инвентарь: в профиле теперь " .. table.concat(res, ", "))
end

-- если сервер пришлёт свежий профиль (крафт/покупка и т.п.), фейки из локальной копии пропадут —
-- возвращаем их. Если вернуть не вышло, expected опускается до факта, чтобы не крутиться по кругу.
local reapplyQueued = false
local function reapply()
	if reapplyQueued then
		return
	end
	reapplyQueued = true
	task.delay(0.5, function()
		pcall(function()
			if setthreadidentity then
				setthreadidentity(8)
			end
		end)
		reapplyQueued = false
		if applying or not profileOk() then
			return
		end
		applying = true
		local n = 0
		for id, cnt in pairs(fakeOwned) do
			local have = ownedCount(id)
			if have < (expected[id] or 0) then
				addOne(id, have + cnt)
				expected[id] = ownedCount(id)
				n += 1
			end
		end
		applying = false
		if n > 0 then
			tlog("инвентарь: профиль обновился с сервера — вернул фейков: " .. n)
		end
	end)
end
if env.FakeInvConns then
	for _, c in ipairs(env.FakeInvConns) do
		pcall(function()
			c:Disconnect()
		end)
	end
end
env.FakeInvConns = {}
for _, bn in ipairs({ "InventoryDataChanged", "ProfileDataChanged" }) do
	local b = RemInv and RemInv:FindFirstChild(bn)
	if b and b:IsA("BindableEvent") then
		table.insert(env.FakeInvConns, b.Event:Connect(reapply))
	end
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
	local invReady = false -- инвентарь дорисован: только после этого фантом начинает класть предметы
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
		invReady = true
	end)

	-- фантом добавляет предметы постепенно: окно открылось → пауза 1.5-2.5с → первый предмет,
	-- затем остальные по одному (иногда по 2), с паузами
	task.spawn(function()
		pcall(function()
			if setthreadidentity then
				setthreadidentity(8)
			end
		end)
		-- Пауза считается с момента, когда окно реально на экране: генерация инвентаря слева может
		-- на пару секунд подвесить игру, и раньше пауза за это время «съедалась» — предмет лежал сразу
		local readyBy = os.clock() + 6
		while not invReady and os.clock() < readyBy do
			task.wait()
		end
		task.wait()
		task.wait()
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

	-- завершение (ТОЛЬКО когда обе стороны приняли): окно → родная раздача + локальная копия инвентаря.
	local function complete()
		if state == "Done" then
			return
		end
		state = "Done"
		task.wait(0.45)
		finish()
		task.spawn(function()
			pcall(function()
				if setthreadidentity then
					setthreadidentity(8)
				end
			end)
			tlog("трейд завершён, добавляю в инвентарь: " .. table.concat(offered, ", "))
			addToInventory(offered) -- в локальную копию профиля → игра перерисует инвентарь
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

tlog(("готово. dreampets: %s · пул: %d · ProfileData: %s · InventoryModule: %s · обработчик CII: %s · CPD: %s. Жми «Трейд (тест)»."):format(
	dpOk and "ок" or "фолбэк", #pool, profileOk() and "ок" or "нет", InventoryModule and "ок" or "нет",
	profileHandler("ChangeInventoryItem") and "есть" or "нет", profileHandler("ChangeProfileData") and "есть" or "нет"))
