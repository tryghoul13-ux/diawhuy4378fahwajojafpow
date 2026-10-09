-- Калькулятор инвентаря MM2 в рублях по ценам маркета dreampets.gg.
-- Цены каждый раз берутся свежими с сайта (минимальная цена предложения), никаких сохранённых списков:
-- при запуске, перед подсчётом (если загружены больше 3 минут назад) и по кнопке 🔄.
-- Выбираешь игрока — его инвентарь запрашивается у игры заново (то же, что кнопка «Inventory»).
-- Предметы можно убирать, менять количество и добавлять (для расчёта обмена) — сумма пересчитывается сразу.
-- Запуск в Delta: loadstring(readfile('invcalc.lua'))()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")

-- Повторный запуск заменяет старое окно
local env = (getgenv and getgenv()) or _G
if env.InvCalcGui then
	pcall(function()
		env.InvCalcGui:Destroy()
	end)
end

local API = "https://mm2-test.dreampets.gg/api/market/v1/market/products"
local PRICE_MAX_AGE = 180 -- сек: цены старше перед подсчётом скачиваются заново
local CHECK_FROM = 300 -- ₽: у предметов дороже проверяем, сколько всего предложений
local ROW_LIMIT = 120 -- строк предметов сразу; остальные по кнопке «Показать ещё»
local RUB = "₽"

local function new(className, props)
	local inst = Instance.new(className)
	for key, value in pairs(props) do
		if key ~= "Parent" then
			inst[key] = value
		end
	end
	inst.Parent = props.Parent
	return inst
end

local function corner(parent, r)
	return new("UICorner", { CornerRadius = UDim.new(0, r or 8), Parent = parent })
end

local function label(props)
	props.BackgroundTransparency = 1
	props.Font = props.Font or Enum.Font.Gotham
	props.TextColor3 = props.TextColor3 or Color3.fromRGB(225, 227, 235)
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	props.TextTruncate = props.TextTruncate or Enum.TextTruncate.AtEnd
	return new("TextLabel", props)
end

local COL = {
	window = Color3.fromRGB(24, 25, 32),
	panel = Color3.fromRGB(30, 31, 40),
	card = Color3.fromRGB(37, 39, 50),
	cardSel = Color3.fromRGB(48, 56, 86),
	text = Color3.fromRGB(236, 238, 244),
	muted = Color3.fromRGB(140, 146, 162),
	gold = Color3.fromRGB(255, 205, 90),
	green = Color3.fromRGB(100, 210, 130),
	red = Color3.fromRGB(235, 90, 90),
	orange = Color3.fromRGB(255, 165, 70),
	button = Color3.fromRGB(56, 58, 74),
	accent = Color3.fromRGB(60, 120, 230),
}

local RARITY_COLORS = {
	chroma = Color3.fromRGB(0, 255, 160),
	godly = Color3.fromRGB(255, 70, 200),
	ancient = Color3.fromRGB(170, 110, 255),
	unique = Color3.fromRGB(255, 150, 50),
	vintage = Color3.fromRGB(230, 200, 90),
	legendary = Color3.fromRGB(255, 90, 90),
	rare = Color3.fromRGB(80, 150, 255),
	uncommon = Color3.fromRGB(110, 205, 120),
	common = Color3.fromRGB(190, 195, 205),
	classic = Color3.fromRGB(120, 210, 230),
	christmas = Color3.fromRGB(110, 220, 130),
	halloween = Color3.fromRGB(255, 140, 40),
}
local function rarityColor(rarity, chroma)
	if chroma then
		return RARITY_COLORS.chroma
	end
	return RARITY_COLORS[rarity or ""] or COL.text
end

local CAT_NAMES = { knife = "нож", gun = "пистолет", misc = "ивент", floating = "питомец", walking = "питомец" }

-- "godly", chroma -> "Chroma Godly"
local function rarityText(rarity, chroma)
	rarity = tostring(rarity or "")
	if rarity == "" then
		return ""
	end
	return (chroma and "Chroma " or "") .. rarity:sub(1, 1):upper() .. rarity:sub(2)
end

-- 1234.5 -> "1 235", 4.3 -> "4,3"
local function fmt(v)
	if v == nil then
		return "—"
	end
	if math.abs(v) < 100 and v ~= math.floor(v) then
		local s = string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", "")
		return (s:gsub("%.", ","))
	end
	local n = math.floor(math.abs(v) + 0.5)
	local s = tostring(n):reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", "")
	return (v < 0 and "−" or "") .. s
end
local function rub(v)
	return fmt(v) .. " " .. RUB
end

local function norm(s)
	return (tostring(s or ""):lower():gsub("[^%w]", ""))
end

-- строчные буквы и для кириллицы (для поиска по русским названиям)
local function lowerAll(s)
	s = tostring(s or "")
	local ok, out = pcall(function()
		local t = {}
		for _, c in utf8.codes(s) do
			if c >= 0x410 and c <= 0x42F then
				c += 0x20
			elseif c == 0x401 then
				c = 0x451
			elseif c >= 65 and c <= 90 then
				c += 32
			end
			t[#t + 1] = utf8.char(c)
		end
		return table.concat(t)
	end)
	return ok and out or s:lower()
end

----------------------------------------------------------------------------------------------
-- База предметов игры: имя, тип, редкость, хрома, картинка

local Sync
pcall(function()
	Sync = require(ReplicatedStorage.Database.Sync)
end)

local function imageOf(img)
	if type(img) == "number" then
		return "rbxthumb://type=Asset&id=" .. img .. "&w=150&h=150"
	end
	if type(img) ~= "string" then
		return ""
	end
	if img:find("^rbxassetid://") or img:find("^rbxthumb://") then
		return img
	end
	local id = img:match("assetId=(%d+)") or img:match("[?&]id=(%d+)") or img:match("^(%d+)$")
	return id and ("rbxthumb://type=Asset&id=" .. id .. "&w=150&h=150") or ""
end

local infoCache = {}
local function infoFor(id, isPet)
	local key = (isPet and "p:" or "w:") .. id
	if infoCache[key] == nil then
		local info = false
		local db = Sync and (isPet and Sync.Pets or Sync.Item)
		local e = type(db) == "table" and rawget(db, id)
		if type(e) == "table" then
			info = {
				name = tostring((isPet and (e.Name or e.ItemName)) or e.ItemName or id),
				cat = tostring((isPet and e.Type) or e.ItemType or ""):lower(),
				rarity = tostring(e.Rarity or ""):lower(),
				chroma = e.Chroma == true or (isPet and id:find("Chroma") ~= nil) or false,
				year = e.Year,
				image = imageOf(e.Image),
			}
		end
		infoCache[key] = info
	end
	return infoCache[key] or nil
end

-- Картинка для добавленного из каталога предмета: ищем такой же предмет в базе игры
local imageByKey
local function catalogImage(name, cat, chroma, rarity)
	if not imageByKey then
		imageByKey = {}
		local function scan(db, isPet)
			if type(db) ~= "table" then
				return
			end
			for id, _ in pairs(db) do
				local info = type(id) == "string" and infoFor(id, isPet)
				if info then
					local k = norm(info.name) .. "|" .. info.cat .. "|" .. tostring(info.chroma) .. "|" .. info.rarity
					imageByKey[k] = imageByKey[k] or info.image
				end
			end
		end
		scan(Sync and Sync.Item, false)
		scan(Sync and Sync.Pets, true)
	end
	return imageByKey[norm(name) .. "|" .. cat .. "|" .. tostring(chroma) .. "|" .. rarity] or ""
end

----------------------------------------------------------------------------------------------
-- Цены с dreampets

local function priceKey(name, cat, chroma, rarity)
	return norm(name) .. "|" .. tostring(cat) .. "|" .. (chroma and "c" or "-") .. "|" .. tostring(rarity or "")
end

local prices = { byKey = {}, byLoose = {}, list = {} }
local priceState = { ok = false, at = 0, time = nil, count = 0, err = nil, loading = false }
local offers = {} -- [product_id] = число предложений; сбрасывается вместе с ценами

local onPriceState -- обновить строку статуса (задаётся ниже, когда есть окно)

local function fetchPrices()
	local byKey, byLoose, list = {}, {}, {}
	local offset = 0
	for _ = 1, 20 do -- весь каталог влезает в одну страницу, но вдруг разрастётся
		local body = game:HttpGet(API .. "?search=&currency=rub&sort=popularity_desc&limit=1000&offset=" .. offset)
		local data = HttpService:JSONDecode(body)
		local page = type(data) == "table" and data.products
		if type(page) ~= "table" then
			error("сайт ответил не так, как ожидалось")
		end
		if #page == 0 then
			break
		end
		for _, p in ipairs(page) do
			local price = tonumber(p.min_price)
			if price and type(p.name) == "string" then
				local entry = {
					price = price,
					pid = p.product_id,
					name = p.name,
					ru = type(p.names_by_locale) == "table" and p.names_by_locale.ru or nil,
					cat = tostring(p.category),
					rarity = tostring(p.rarity),
					chroma = p.chroma == true,
				}
				local k = priceKey(p.name, entry.cat, entry.chroma, entry.rarity)
				byKey[k] = byKey[k] or {}
				table.insert(byKey[k], entry)
				local lk = priceKey(p.name, entry.cat, entry.chroma, "")
				byLoose[lk] = byLoose[lk] or {}
				table.insert(byLoose[lk], entry)
				table.insert(list, entry)
			end
		end
		offset += #page
	end
	if #list == 0 then
		error("в каталоге нет ни одной цены")
	end
	local function byPrice(a, b)
		return a.price < b.price
	end
	for _, t in pairs(byKey) do
		table.sort(t, byPrice)
	end
	for _, t in pairs(byLoose) do
		table.sort(t, byPrice)
	end
	return byKey, byLoose, list
end

-- Свежие цены: качаем, если их нет, они старше PRICE_MAX_AGE или force
local function refreshPrices(force)
	if priceState.loading then
		while priceState.loading do
			task.wait(0.1)
		end
		return priceState.ok
	end
	if not force and priceState.ok and os.clock() - priceState.at < PRICE_MAX_AGE then
		return true
	end
	priceState.loading = true
	if onPriceState then
		onPriceState()
	end
	local ok, a, b, c = pcall(fetchPrices)
	if ok then
		prices.byKey, prices.byLoose, prices.list = a, b, c
		priceState.ok = true
		priceState.at = os.clock()
		priceState.time = os.date("%H:%M")
		priceState.count = #c
		priceState.err = nil
		offers = {}
	else
		priceState.err = tostring(a):gsub("^.-:%d+: ", "")
	end
	priceState.loading = false
	if onPriceState then
		onPriceState()
	end
	return ok
end

-- Сколько всего предложений у товара (одно дорогое предложение — часто прикол, а не цена)
local function offerCount(pid)
	if offers[pid] == nil then
		local n = false
		local ok, body = pcall(function()
			return game:HttpGet(API .. "/" .. pid .. "/stats?currency=rub")
		end)
		if ok then
			local ok2, d = pcall(function()
				return HttpService:JSONDecode(body)
			end)
			if ok2 and type(d) == "table" then
				n = tonumber(d.sale_count) or false
			end
		end
		offers[pid] = n
	end
	return offers[pid]
end

----------------------------------------------------------------------------------------------
-- Инвентарь игрока (свежий запрос к игре)

local invRemote
pcall(function()
	invRemote = ReplicatedStorage.Remotes.Extras.GetFullInventory
end)

local SKIP = { DefaultKnife = true, DefaultGun = true } -- есть у всех, не продаются

-- Считаем только годли и выше (как ридер): комонки, анкомонки, рарки и легендарки не берём.
-- Хрома-годли тоже годли («Chroma Godly» содержит «godly»)
local HIGH_RARITIES = { "godly", "ancient", "unique", "vintage" }
local function isHigh(rarity)
	local key = tostring(rarity or ""):lower()
	for _, name in ipairs(HIGH_RARITIES) do
		if key:find(name, 1, true) then
			return true
		end
	end
	return false
end

local function loadInventory(player)
	if not invRemote then
		return nil, "в этой игре нет инвентаря MM2"
	end
	local ok, inv = pcall(function()
		return invRemote:InvokeServer(player)
	end)
	if not ok or type(inv) ~= "table" then
		return nil, "игра не отдала инвентарь, попробуй ещё раз"
	end
	local items = {}
	local function take(container, isPet)
		local owned = type(container) == "table" and container.Owned
		if type(owned) ~= "table" then
			return
		end
		for id, qty in pairs(owned) do
			if type(id) == "number" then -- на случай, если это список, а не словарь
				id, qty = qty, 1
			end
			id = tostring(id)
			qty = tonumber(qty) or 1
			if not SKIP[id] and qty > 0 then
				table.insert(items, { id = id, qty = qty, pet = isPet })
			end
		end
	end
	take(inv.Weapons, false)
	take(inv.Pets, true)
	return items
end

-- Строка расчёта: что за предмет, сколько есть, сколько считаем, цена
local function makeLine(fields)
	local line = fields
	line.qty = line.qty or line.owned
	line.included = line.price ~= nil
	return line
end

local function priceFor(name, cat, chroma, rarity)
	local variants = prices.byKey[priceKey(name, cat, chroma, rarity)]
	local loose = false
	if not variants then
		variants = prices.byLoose[priceKey(name, cat, chroma, "")]
		loose = variants ~= nil
	end
	if variants and #variants > 0 then
		return variants[1], variants[#variants].price, #variants, loose
	end
	return nil
end

local function buildLines(items)
	local lines = {}
	for _, it in ipairs(items) do
		local info = infoFor(it.id, it.pet)
		-- Ниже годли не показываем и не считаем. Предмет, которого нет в базе игры (новый),
		-- оставляем: его редкость неизвестна, а цены у него всё равно нет — в сумму он не идёт
		if not info or isHigh(info.rarity) then
			local line = { key = (it.pet and "p:" or "w:") .. it.id, id = it.id, owned = it.qty, pet = it.pet }
			if info then
				line.name, line.cat, line.rarity, line.chroma = info.name, info.cat, info.rarity, info.chroma
				line.year, line.image = info.year, info.image
				local best, maxPrice, variants, loose = priceFor(info.name, info.cat, info.chroma, info.rarity)
				if best then
					line.price, line.pid, line.priceMax, line.variants, line.loose = best.price, best.pid, maxPrice, variants, loose
				end
			else
				line.name, line.cat, line.rarity, line.chroma, line.image = it.id, "", "", false, ""
			end
			table.insert(lines, makeLine(line))
		end
	end
	table.sort(lines, function(a, b)
		local av, bv = (a.price or -1) * a.owned, (b.price or -1) * b.owned
		if av ~= bv then
			return av > bv
		end
		return a.name < b.name
	end)
	return lines
end

-- Итог: сейчас (с правками) и как было (без правок, подозрительные не считаем)
local function totals(lines)
	local now, base = 0, 0
	for _, l in ipairs(lines) do
		if l.price then
			if not l.added and not l.suspicious then
				base += l.price * l.owned
			end
			if l.included and l.qty > 0 then
				now += l.price * l.qty
			end
		end
	end
	return now, base
end

----------------------------------------------------------------------------------------------
-- Окно

local connections = {}
local function connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(connections, c)
	return c
end

local gui = new("ScreenGui", {
	Name = "InvCalcGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 110, -- поверх ридера
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})

local window = new("Frame", {
	Name = "Window",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.9, 0.88),
	BackgroundColor3 = COL.window,
	Active = true, -- нажатия не уходят в игру
	Parent = gui,
})
corner(window, 14)
new("UIStroke", { Color = Color3.fromRGB(60, 62, 80), Thickness = 1, Parent = window })
new("UISizeConstraint", { MinSize = Vector2.new(560, 340), MaxSize = Vector2.new(1000, 620), Parent = window })
new("UIPadding", {
	PaddingTop = UDim.new(0, 10),
	PaddingBottom = UDim.new(0, 12),
	PaddingLeft = UDim.new(0, 12),
	PaddingRight = UDim.new(0, 12),
	Parent = window,
})

-- Шапка: за неё окно перетаскивается
local titleBar = new("Frame", {
	Name = "TitleBar",
	Size = UDim2.new(1, 0, 0, 40),
	BackgroundTransparency = 1,
	Active = true,
	Parent = window,
})
label({
	Name = "Title",
	Size = UDim2.new(0, 260, 1, 0),
	Font = Enum.Font.GothamBold,
	Text = "💰 Инвентарь в " .. RUB,
	TextSize = 22,
	TextColor3 = COL.text,
	Parent = titleBar,
})
local priceStatus = label({
	Name = "PriceStatus",
	Position = UDim2.fromOffset(270, 0),
	Size = UDim2.new(1, -270 - 104, 1, 0),
	Font = Enum.Font.GothamMedium,
	Text = "",
	TextSize = 14,
	TextColor3 = COL.muted,
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = titleBar,
})
local function smallButton(text, color, parent)
	local b = new("TextButton", {
		BackgroundColor3 = color or COL.button,
		Font = Enum.Font.GothamBold,
		Text = text,
		TextSize = 18,
		TextColor3 = Color3.new(1, 1, 1),
		AutoButtonColor = true,
		Parent = parent,
	})
	corner(b, 8)
	return b
end
local refreshButton = smallButton("🔄", COL.button, titleBar)
refreshButton.AnchorPoint = Vector2.new(1, 0)
refreshButton.Position = UDim2.new(1, -52, 0, 2)
refreshButton.Size = UDim2.fromOffset(44, 36)
local closeButton = smallButton("X", COL.button, titleBar)
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, 0, 0, 2)
closeButton.Size = UDim2.fromOffset(44, 36)

-- Левая колонка: игроки сервера
local LEFT_W = 250
local leftPanel = new("Frame", {
	Name = "Players",
	Position = UDim2.fromOffset(0, 50),
	Size = UDim2.new(0, LEFT_W, 1, -50),
	BackgroundColor3 = COL.panel,
	Parent = window,
})
corner(leftPanel, 10)
local playersTitle = label({
	Position = UDim2.fromOffset(12, 6),
	Size = UDim2.new(1, -24, 0, 26),
	Font = Enum.Font.GothamBold,
	Text = "Игроки",
	TextSize = 16,
	TextColor3 = COL.muted,
	Parent = leftPanel,
})
local playerList = new("ScrollingFrame", {
	Position = UDim2.fromOffset(6, 36),
	Size = UDim2.new(1, -12, 1, -42),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	Parent = leftPanel,
})
new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = playerList })

-- Правая колонка: расчёт выбранного игрока
local right = new("Frame", {
	Name = "Detail",
	Position = UDim2.fromOffset(LEFT_W + 10, 50),
	Size = UDim2.new(1, -LEFT_W - 10, 1, -50),
	BackgroundTransparency = 1,
	Parent = window,
})

local header = new("Frame", {
	Name = "Header",
	Size = UDim2.new(1, 0, 0, 84),
	BackgroundColor3 = COL.panel,
	Parent = right,
})
corner(header, 10)
local headAvatar = new("ImageLabel", {
	Position = UDim2.fromOffset(10, 10),
	Size = UDim2.fromOffset(64, 64),
	BackgroundColor3 = COL.card,
	Image = "",
	Parent = header,
})
corner(headAvatar, 32)
local headName = label({
	Position = UDim2.fromOffset(86, 12),
	Size = UDim2.new(1, -86 - 240, 0, 28),
	Font = Enum.Font.GothamBold,
	Text = "Выбери игрока слева",
	TextSize = 22,
	TextColor3 = COL.text,
	Parent = header,
})
local headSub = label({
	Position = UDim2.fromOffset(86, 44),
	Size = UDim2.new(1, -86 - 240, 0, 22),
	Font = Enum.Font.Gotham,
	Text = "цены: минимальная цена на маркете dreampets.gg",
	TextSize = 14,
	TextColor3 = COL.muted,
	Parent = header,
})
local headTotal = label({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 6),
	Size = UDim2.fromOffset(230, 40),
	Font = Enum.Font.GothamBlack,
	Text = "",
	TextSize = 32,
	TextColor3 = COL.gold,
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = header,
})
local headWas = label({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 48),
	Size = UDim2.fromOffset(330, 22),
	Font = Enum.Font.GothamMedium,
	Text = "",
	TextSize = 14,
	TextColor3 = COL.muted,
	TextXAlignment = Enum.TextXAlignment.Right,
	RichText = true,
	Parent = header,
})

-- Строка под шапкой: сколько предметов, сброс правок, поиск для добавления
local toolbar = new("Frame", {
	Name = "Toolbar",
	Position = UDim2.fromOffset(0, 92),
	Size = UDim2.new(1, 0, 0, 36),
	BackgroundTransparency = 1,
	Parent = right,
})
local infoLabel = label({
	Size = UDim2.new(1, -330, 1, 0),
	Font = Enum.Font.GothamMedium,
	Text = "",
	TextSize = 14,
	TextColor3 = COL.muted,
	RichText = true,
	Parent = toolbar,
})
local searchBox = new("TextBox", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -112, 0, 0),
	Size = UDim2.fromOffset(210, 36),
	BackgroundColor3 = COL.panel,
	Font = Enum.Font.Gotham,
	PlaceholderText = "+ добавить предмет…",
	PlaceholderColor3 = COL.muted,
	Text = "",
	TextSize = 15,
	TextColor3 = COL.text,
	TextXAlignment = Enum.TextXAlignment.Left,
	ClearTextOnFocus = false,
	Visible = false,
	Parent = toolbar,
})
corner(searchBox, 8)
new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 8), Parent = searchBox })
local resetButton = smallButton("Сбросить", COL.button, toolbar)
resetButton.AnchorPoint = Vector2.new(1, 0)
resetButton.Position = UDim2.fromScale(1, 0)
resetButton.Size = UDim2.fromOffset(104, 36)
resetButton.TextSize = 15
resetButton.Visible = false

local itemList = new("ScrollingFrame", {
	Name = "Items",
	Position = UDim2.fromOffset(0, 136),
	Size = UDim2.new(1, 0, 1, -136),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 5,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	Parent = right,
})
new("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder, Parent = itemList })

local emptyLabel = label({
	Position = UDim2.fromOffset(0, 136),
	Size = UDim2.new(1, 0, 0, 60),
	Font = Enum.Font.GothamMedium,
	Text = "👈 Нажми на игрока — посчитаю его инвентарь по свежим ценам",
	TextSize = 17,
	TextColor3 = COL.muted,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextWrapped = true,
	Parent = right,
})

-- Подсказки поиска: всплывают под полем
local suggest = new("Frame", {
	Name = "Suggest",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -112, 0, 132),
	Size = UDim2.fromOffset(420, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = COL.panel,
	Visible = false,
	ZIndex = 20,
	Parent = right,
})
corner(suggest, 8)
new("UIStroke", { Color = Color3.fromRGB(70, 72, 92), Parent = suggest })
new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = suggest })
new("UIPadding", {
	PaddingTop = UDim.new(0, 4),
	PaddingBottom = UDim.new(0, 4),
	PaddingLeft = UDim.new(0, 4),
	PaddingRight = UDim.new(0, 4),
	Parent = suggest,
})

-- Кнопка, чтобы вернуть закрытое окно
local openButton = smallButton("💰 " .. RUB, COL.window, gui)
openButton.AnchorPoint = Vector2.new(0.5, 1)
openButton.Position = UDim2.new(0.5, 170, 1, -16) -- правее кнопки ридера «Игроки»
openButton.Size = UDim2.fromOffset(120, 44)
openButton.TextSize = 20
openButton.Visible = false

----------------------------------------------------------------------------------------------
-- Состояние и отрисовка

local current -- { player, lines, loading, refreshing, error, note, at }
local playerCards = {} -- [player] = { frame, total }
local lastTotals = {} -- [userId] = сумма при последнем подсчёте (только в этой сессии)
local itemRows = {} -- строки предметов текущего игрока

onPriceState = function()
	if priceState.loading then
		priceStatus.Text = "⏳ качаю цены с dreampets…"
		priceStatus.TextColor3 = COL.muted
	elseif priceState.ok then
		local age = math.floor((os.clock() - priceState.at) / 60)
		priceStatus.Text = ("dreampets · %d цен · %s%s"):format(priceState.count, priceState.time,
			priceState.err and " (обновить не вышло)" or (age >= 1 and (" · " .. age .. " мин назад") or ""))
		priceStatus.TextColor3 = priceState.err and COL.orange or COL.muted
	else
		priceStatus.Text = "⚠ нет цен: " .. tostring(priceState.err or "?") .. " — нажми 🔄"
		priceStatus.TextColor3 = COL.red
	end
end

local function updateTotals()
	if not current or not current.lines then
		headTotal.Text = ""
		headWas.Text = ""
		resetButton.Visible = false
		return
	end
	local now, base = totals(current.lines)
	headTotal.Text = rub(now)
	local edited = false
	for _, l in ipairs(current.lines) do
		if l.added or l.qty ~= l.owned or (l.included ~= (l.price ~= nil and not l.suspicious)) then
			edited = true
			break
		end
	end
	if edited and math.abs(now - base) >= 0.005 then
		local diff = now - base
		headWas.Text = ('было %s · <font color="#%s">%s%s</font>'):format(
			rub(base),
			diff < 0 and "EB5A5A" or "64D282",
			diff > 0 and "+" or "",
			rub(diff)
		)
	elseif edited then
		headWas.Text = "правки не меняют сумму"
	else
		headWas.Text = ""
	end
	resetButton.Visible = edited
	if current.player then
		lastTotals[current.player.UserId] = now
		local card = playerCards[current.player]
		if card then
			card.total.Text = rub(now)
		end
	end
	-- сводка по предметам
	local priced, unpriced, flagged = 0, 0, 0
	for _, l in ipairs(current.lines) do
		if l.price then
			priced += 1
		else
			unpriced += 1
		end
		if l.suspicious and not l.included then
			flagged += 1
		end
	end
	local parts = { ("предметов: %d"):format(priced + unpriced) }
	if unpriced > 0 then
		table.insert(parts, ("без цены: %d"):format(unpriced))
	end
	if flagged > 0 then
		table.insert(parts, ('<font color="#FFA546">⚠ не в сумме: %d</font>'):format(flagged))
	end
	if current.refreshing then
		table.insert(parts, "⏳ обновляю…")
	elseif current.note then
		table.insert(parts, '<font color="#FFA546">' .. current.note .. "</font>")
	end
	infoLabel.Text = table.concat(parts, " · ")
end

local function clearItems()
	for _, r in ipairs(itemRows) do
		r.frame:Destroy()
	end
	itemRows = {}
	suggest.Visible = false
end

-- Одна строка предмета; update() перекрашивает её после правок
local function makeItemRow(line, order)
	local row = new("Frame", {
		Size = UDim2.new(1, -6, 0, 54),
		BackgroundColor3 = COL.card,
		LayoutOrder = order,
		Parent = itemList,
	})
	corner(row, 8)
	local rc = rarityColor(line.rarity, line.chroma)
	local icon = new("ImageLabel", {
		Position = UDim2.fromOffset(6, 5),
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = Color3.fromRGB(26, 27, 34),
		Image = line.image or "",
		ScaleType = Enum.ScaleType.Fit,
		Parent = row,
	})
	corner(icon, 6)
	new("UIStroke", { Color = rc, Thickness = 1.5, Parent = icon })
	local nameLabel = label({
		Position = UDim2.fromOffset(60, 6),
		Size = UDim2.new(1, -60 - 330, 0, 22),
		Font = Enum.Font.GothamBold,
		Text = line.name .. (line.owned > 1 and ("  ×" .. line.owned) or ""),
		TextSize = 16,
		TextColor3 = rc,
		Parent = row,
	})
	local subLabel = label({
		Position = UDim2.fromOffset(60, 29),
		Size = UDim2.new(1, -60 - 330, 0, 18),
		Font = Enum.Font.Gotham,
		Text = "",
		TextSize = 12,
		TextColor3 = COL.muted,
		RichText = true,
		Parent = row,
	})
	-- справа налево: [Убрать] [сумма] [- qty +]
	local toggle = smallButton("Убрать", COL.button, row)
	toggle.AnchorPoint = Vector2.new(1, 0.5)
	toggle.Position = UDim2.new(1, -6, 0.5, 0)
	toggle.Size = UDim2.fromOffset(84, 38)
	toggle.TextSize = 14
	local priceLabel = label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -98, 0, 6),
		Size = UDim2.fromOffset(120, 24),
		Font = Enum.Font.GothamBold,
		Text = "",
		TextSize = 17,
		TextColor3 = COL.gold,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = row,
	})
	local unitLabel = label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -98, 0, 30),
		Size = UDim2.fromOffset(120, 18),
		Font = Enum.Font.Gotham,
		Text = "",
		TextSize = 12,
		TextColor3 = COL.muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = row,
	})
	local qtyBox = new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -226, 0.5, 0),
		Size = UDim2.fromOffset(100, 38),
		BackgroundTransparency = 1,
		Parent = row,
	})
	local minus = smallButton("−", COL.button, qtyBox)
	minus.Size = UDim2.fromOffset(32, 38)
	local qtyLabel = label({
		Position = UDim2.fromOffset(32, 0),
		Size = UDim2.fromOffset(36, 38),
		Font = Enum.Font.GothamBold,
		Text = "",
		TextSize = 16,
		TextColor3 = COL.text,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = qtyBox,
	})
	local plus = smallButton("+", COL.button, qtyBox)
	plus.Position = UDim2.fromOffset(68, 0)
	plus.Size = UDim2.fromOffset(32, 38)

	local r = { frame = row, line = line }
	function r.update()
		local active = line.price ~= nil and line.included and line.qty > 0
		-- подпись: тип · редкость · год · пометки
		local bits = {}
		if CAT_NAMES[line.cat] then
			table.insert(bits, CAT_NAMES[line.cat])
		end
		if line.rarity ~= "" then
			table.insert(bits, rarityText(line.rarity, line.chroma))
		end
		if line.year then
			table.insert(bits, tostring(line.year))
		end
		if line.added then
			table.insert(bits, '<font color="#64D282">добавлен</font>')
		end
		if not line.price then
			table.insert(bits, "нет на маркете")
		elseif line.suspicious then
			table.insert(bits, '<font color="#FFA546">⚠ одно предложение</font>')
		elseif line.variants and line.variants > 1 and line.priceMax > line.price * 1.5 then
			table.insert(bits, ("≈ есть варианты до %s"):format(rub(line.priceMax)))
		elseif line.loose then
			table.insert(bits, "≈ цена другой редкости")
		end
		subLabel.Text = table.concat(bits, " · ")

		if line.price then
			priceLabel.Text = active and rub(line.price * line.qty) or "—"
			priceLabel.TextColor3 = active and COL.gold or COL.muted
			unitLabel.Text = (line.qty > 1 or line.owned > 1) and (rub(line.price) .. " за шт") or ""
		else
			priceLabel.Text = ""
			unitLabel.Text = ""
		end

		local maxQty = line.added and 99 or line.owned
		qtyBox.Visible = line.price ~= nil and (maxQty > 1 or line.added) and line.included
		-- подписи тянутся до кнопок справа: с [- 1 +] места меньше
		local reserve = qtyBox.Visible and 334 or 232
		nameLabel.Size = UDim2.new(1, -60 - reserve, 0, 22)
		subLabel.Size = UDim2.new(1, -60 - reserve, 0, 18)
		qtyLabel.Text = tostring(line.qty)
		minus.AutoButtonColor = line.qty > 0
		minus.TextTransparency = line.qty > 0 and 0 or 0.6
		plus.TextTransparency = line.qty < maxQty and 0 or 0.6

		toggle.Visible = line.price ~= nil
		if line.added then
			toggle.Text = "Убрать"
			toggle.BackgroundColor3 = COL.button
		elseif line.included and line.qty > 0 then
			toggle.Text = "Убрать"
			toggle.BackgroundColor3 = COL.button
		else
			toggle.Text = line.suspicious and "Учесть" or "Вернуть"
			toggle.BackgroundColor3 = line.suspicious and Color3.fromRGB(150, 95, 30) or COL.accent
		end
		row.BackgroundTransparency = (active or not line.price) and 0 or 0.55
		nameLabel.TextTransparency = active and 0 or 0.45
		icon.ImageTransparency = active and 0 or 0.55
	end

	connect(toggle.Activated, function()
		line.touched = true -- дальше автопроверки это решение не трогают
		if line.added then
			-- добавленный предмет убираем совсем
			for i, l in ipairs(current.lines) do
				if l == line then
					table.remove(current.lines, i)
					break
				end
			end
			for i, rr in ipairs(itemRows) do
				if rr == r then
					table.remove(itemRows, i)
					break
				end
			end
			row:Destroy()
		elseif line.included and line.qty > 0 then
			line.included = false
		else
			line.included = true
			if line.qty == 0 then
				line.qty = line.owned
			end
		end
		r.update()
		updateTotals()
	end)
	connect(minus.Activated, function()
		if line.qty > 0 then
			line.qty -= 1
			line.touched = true
			r.update()
			updateTotals()
		end
	end)
	connect(plus.Activated, function()
		local maxQty = line.added and 99 or line.owned
		if line.qty < maxQty then
			line.qty += 1
			line.included = true
			line.touched = true
			r.update()
			updateTotals()
		end
	end)

	r.update()
	return r
end

local function renderItems(keepScroll)
	local scrollPos = itemList.CanvasPosition
	clearItems()
	if not current then
		emptyLabel.Visible = true
		emptyLabel.Text = "👈 Нажми на игрока — посчитаю его инвентарь по свежим ценам"
		searchBox.Visible = false
		return
	end
	if current.loading or current.error or not current.lines then
		emptyLabel.Visible = true
		emptyLabel.Text = current.error and ("⚠ " .. current.error) or "⏳ считаю…"
		emptyLabel.TextColor3 = current.error and COL.red or COL.muted
		searchBox.Visible = false
		return
	end
	emptyLabel.TextColor3 = COL.muted
	emptyLabel.Visible = #current.lines == 0
	emptyLabel.Text = "У игрока нет годли и выше"
	searchBox.Visible = priceState.ok
	-- у коллекционеров бывают сотни предметов: сначала рисуем самые дорогие, остальное по кнопке
	local shown = math.min(#current.lines, current.showAll and math.huge or ROW_LIMIT)
	for i = 1, shown do
		table.insert(itemRows, makeItemRow(current.lines[i], i))
	end
	if shown < #current.lines then
		local more = smallButton(("Показать ещё %d (дешевле %s)"):format(#current.lines - shown, rub(current.lines[shown].price or 0)), COL.button, itemList)
		more.Size = UDim2.new(1, -6, 0, 44)
		more.TextSize = 15
		more.LayoutOrder = shown + 1
		local state = current
		connect(more.Activated, function()
			state.showAll = true
			if current == state then
				renderItems(true)
			end
		end)
		table.insert(itemRows, { frame = more, update = function() end })
	end
	if keepScroll then
		task.defer(function() -- размер списка пересчитается к следующему кадру
			itemList.CanvasPosition = scrollPos
		end)
	else
		itemList.CanvasPosition = Vector2.new(0, 0)
	end
end

local function setHeaderSub()
	local state = current
	if not state or not state.player then
		headSub.Text = "цены: минимальная цена на маркете dreampets.gg"
		return
	end
	local bits = { "@" .. state.player.Name }
	if not state.player.Parent then
		table.insert(bits, "вышел")
	end
	if state.at then
		table.insert(bits, (state.player.Parent and "посчитано в " or "") .. state.at)
	end
	headSub.Text = table.concat(bits, " · ")
end

local function setHeader(player)
	headAvatar.Image = ""
	if not player then
		headName.Text = "Выбери игрока слева"
		setHeaderSub()
		return
	end
	headName.Text = player.DisplayName
	setHeaderSub()
	task.spawn(function()
		local ok, img = pcall(function()
			return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		end)
		if ok and current and current.player == player then
			headAvatar.Image = img
		end
	end)
end

-- Дорогие позиции с одним-единственным предложением помечаем: часто это «прикол» (100 000 ₽ за обычный
-- пистолет), а не цена. В сумму по умолчанию не идут, руками можно вернуть («Учесть»).
-- Добавленные руками предметы только помечаются — их выбрал сам пользователь.
local function checkLines(lines)
	local left = 0
	for _, l in ipairs(lines) do
		if l.price and l.price >= CHECK_FROM and l.pid then
			left += 1
			task.spawn(function()
				local n = offerCount(l.pid)
				if n then
					local single = n <= 1
					if not l.added and not l.touched and single ~= (l.suspicious == true) then
						l.included = not single
					end
					l.suspicious = single
				end
				left -= 1
			end)
		else
			if l.suspicious and not l.touched and not l.added then
				l.included = l.price ~= nil
			end
			l.suspicious = nil
		end
	end
	local t0 = os.clock()
	while left > 0 and os.clock() - t0 < 15 do
		task.wait(0.05)
	end
end

-- После обновления цен/инвентаря переносим правки пользователя на свежие строки
local function mergeEdits(oldLines, newLines)
	local old = {}
	for _, l in ipairs(oldLines) do
		if not l.added then
			old[l.key] = l
		end
	end
	for _, l in ipairs(newLines) do
		local o = old[l.key]
		if o and o.touched then
			l.touched = true
			l.qty = math.min(o.qty, l.owned)
			l.included = o.included and l.price ~= nil
		end
	end
	for i = #oldLines, 1, -1 do
		local l = oldLines[i]
		if l.added then
			local best, maxPrice, variants = priceFor(l.name, l.cat, l.chroma, l.rarity)
			if best then
				l.price, l.pid, l.priceMax, l.variants = best.price, best.pid, maxPrice, variants
			end
			table.insert(newLines, 1, l)
		end
	end
	return newLines
end

-- Посчитать игрока: свежие цены (если старше 3 минут) + свежий инвентарь.
-- oldLines — при обновлении: правки сохраняются, а на экране до конца остаётся старый список.
local function loadInto(state, oldLines)
	local okPrices = refreshPrices(false)
	if current ~= state then
		return
	end
	if not okPrices and not priceState.ok then
		state.loading = false
		state.error = "не удалось получить цены с dreampets (" .. tostring(priceState.err) .. "). Нажми 🔄"
		renderItems()
		return
	end
	local items, err = loadInventory(state.player)
	if current ~= state then
		return
	end
	if not items then
		state.loading = false
		if oldLines then
			state.note = "инвентарь не обновился: " .. err
		else
			state.error = err
			renderItems()
		end
		return
	end
	local lines = buildLines(items)
	if oldLines then
		lines = mergeEdits(oldLines, lines)
	end
	checkLines(lines)
	if current ~= state then
		return
	end
	state.lines = lines
	state.loading = false
	state.error = nil
	state.note = nil
	state.at = os.date("%H:%M")
	renderItems(oldLines ~= nil)
	updateTotals()
	setHeaderSub()
end

local function selectPlayer(player)
	local state = { player = player, loading = true }
	current = state
	for p, card in pairs(playerCards) do
		card.frame.BackgroundColor3 = (p == player) and COL.cardSel or COL.card
	end
	setHeader(player)
	updateTotals()
	renderItems()
	task.spawn(loadInto, state, nil)
end

-- Обновить выбранного игрока, не теряя правок (кнопка 🔄 и автообновление)
local function refreshCurrent()
	local state = current
	if not state or not state.player or state.loading or state.refreshing then
		return
	end
	if not state.lines then
		selectPlayer(state.player)
		return
	end
	state.refreshing = true
	updateTotals()
	loadInto(state, state.lines)
	state.refreshing = false
	if current == state then
		updateTotals()
	end
end

-- Карточки игроков слева
local function rebuildPlayers()
	for _, card in pairs(playerCards) do
		card.frame:Destroy()
	end
	playerCards = {}
	local list = Players:GetPlayers()
	table.sort(list, function(a, b)
		if a == Players.LocalPlayer then
			return true
		elseif b == Players.LocalPlayer then
			return false
		end
		return a.DisplayName:lower() < b.DisplayName:lower()
	end)
	playersTitle.Text = ("Игроки на сервере (%d)"):format(#list)
	for i, p in ipairs(list) do
		local card = new("TextButton", {
			Size = UDim2.new(1, -4, 0, 50),
			BackgroundColor3 = (current and current.player == p) and COL.cardSel or COL.card,
			Text = "",
			AutoButtonColor = true,
			LayoutOrder = i,
			Parent = playerList,
		})
		corner(card, 8)
		local av = new("ImageLabel", {
			Position = UDim2.fromOffset(6, 6),
			Size = UDim2.fromOffset(38, 38),
			BackgroundColor3 = COL.panel,
			Image = "",
			Parent = card,
		})
		corner(av, 19)
		label({
			Position = UDim2.fromOffset(52, 6),
			Size = UDim2.new(1, -56, 0, 20),
			Font = Enum.Font.GothamBold,
			Text = p.DisplayName .. (p == Players.LocalPlayer and "  (ты)" or ""),
			TextSize = 15,
			TextColor3 = COL.text,
			Parent = card,
		})
		label({
			Position = UDim2.fromOffset(52, 27),
			Size = UDim2.new(1, -56 - 80, 0, 16),
			Font = Enum.Font.Gotham,
			Text = "@" .. p.Name,
			TextSize = 12,
			TextColor3 = COL.muted,
			Parent = card,
		})
		local total = label({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 27),
			Size = UDim2.fromOffset(80, 16),
			Font = Enum.Font.GothamBold,
			Text = lastTotals[p.UserId] and rub(lastTotals[p.UserId]) or "",
			TextSize = 12,
			TextColor3 = COL.gold,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = card,
		})
		playerCards[p] = { frame = card, total = total }
		connect(card.Activated, function()
			selectPlayer(p)
		end)
		task.spawn(function()
			local ok, img = pcall(function()
				return Players:GetUserThumbnailAsync(p.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
			end)
			if ok and av.Parent then
				av.Image = img
			end
		end)
	end
end

-- Поиск по каталогу: добавить предмет в расчёт (например, что игрок получит в обмене)
local suggestButtons = {}
local function showSuggestions(query)
	for _, b in ipairs(suggestButtons) do
		b:Destroy()
	end
	suggestButtons = {}
	local q = norm(query)
	local qru = lowerAll(query):gsub("%s+", "")
	if #q < 2 and utf8.len(qru) < 2 then
		suggest.Visible = false
		return
	end
	-- одинаковые товары разных годов склеиваем: показываем самый дешёвый вариант
	local found, seen = {}, {}
	for _, e in ipairs(prices.list) do
		local hit = (#q >= 2 and norm(e.name):find(q, 1, true)) or (e.ru and lowerAll(e.ru):gsub("%s+", ""):find(qru, 1, true))
		if hit then
			local k = priceKey(e.name, e.cat, e.chroma, e.rarity)
			local prev = seen[k]
			if not prev then
				seen[k] = e
				table.insert(found, e)
			elseif e.price < prev.price then
				found[table.find(found, prev)] = e
				seen[k] = e
			end
		end
	end
	-- сначала точное начало названия, потом дороже
	table.sort(found, function(a, b)
		local as, bs = norm(a.name):sub(1, #q) == q, norm(b.name):sub(1, #q) == q
		if as ~= bs then
			return as
		end
		return a.price > b.price
	end)
	for i = 1, math.min(6, #found) do
		local e = found[i]
		local b = new("TextButton", {
			Size = UDim2.new(1, 0, 0, 34),
			BackgroundColor3 = COL.card,
			Text = "",
			AutoButtonColor = true,
			LayoutOrder = i,
			ZIndex = 21,
			Parent = suggest,
		})
		corner(b, 6)
		label({
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(1, -120, 1, 0),
			Font = Enum.Font.GothamBold,
			Text = e.name .. "  ·  " .. (CAT_NAMES[e.cat] or e.cat) .. "  ·  " .. rarityText(e.rarity, e.chroma),
			TextSize = 14,
			TextColor3 = rarityColor(e.rarity, e.chroma),
			ZIndex = 22,
			Parent = b,
		})
		label({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 0),
			Size = UDim2.fromOffset(100, 34),
			Font = Enum.Font.GothamBold,
			Text = rub(e.price),
			TextSize = 14,
			TextColor3 = COL.gold,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 22,
			Parent = b,
		})
		connect(b.Activated, function()
			if not current or not current.lines then
				return
			end
			local _, maxPrice, variants = priceFor(e.name, e.cat, e.chroma, e.rarity)
			local line = makeLine({
				key = "add:" .. tostring(e.pid) .. ":" .. tostring(os.clock()),
				name = e.name,
				cat = e.cat,
				rarity = e.rarity,
				chroma = e.chroma,
				image = catalogImage(e.name, e.cat, e.chroma, e.rarity),
				price = e.price,
				pid = e.pid,
				priceMax = maxPrice,
				variants = variants,
				owned = 0,
				qty = 1,
				added = true,
			})
			local state = current
			table.insert(state.lines, 1, line)
			local r = makeItemRow(line, -#state.lines)
			table.insert(itemRows, 1, r)
			searchBox.Text = ""
			suggest.Visible = false
			itemList.CanvasPosition = Vector2.new(0, 0)
			updateTotals()
			task.spawn(function() -- одно предложение? — пометим
				checkLines({ line })
				if current == state and r.frame.Parent then
					r.update()
					updateTotals()
				end
			end)
		end)
		table.insert(suggestButtons, b)
	end
	suggest.Visible = #found > 0
end

connect(searchBox:GetPropertyChangedSignal("Text"), function()
	showSuggestions(searchBox.Text)
end)

connect(resetButton.Activated, function()
	if not current or not current.lines then
		return
	end
	local kept = {}
	for _, l in ipairs(current.lines) do
		if not l.added then
			l.qty = l.owned
			l.included = l.price ~= nil and not l.suspicious
			l.touched = nil
			table.insert(kept, l)
		end
	end
	current.lines = kept
	renderItems()
	updateTotals()
end)

-- 🔄: свежие цены сразу + свежий инвентарь выбранного игрока, правки остаются
connect(refreshButton.Activated, function()
	task.spawn(function()
		refreshPrices(true)
		refreshCurrent()
	end)
end)

local function refreshIfStale()
	if priceState.ok and not priceState.loading and os.clock() - priceState.at >= PRICE_MAX_AGE then
		if refreshPrices(true) then
			refreshCurrent()
		end
	end
end

connect(closeButton.Activated, function()
	window.Visible = false
	openButton.Visible = true
	suggest.Visible = false
end)
connect(openButton.Activated, function()
	window.Visible = true
	openButton.Visible = false
	onPriceState()
	task.spawn(refreshIfStale) -- окно долго было закрыто — цены могли устареть
end)

-- Окно не уезжает за край экрана: центр зажимаем так, чтобы окно влезало целиком
local function placeWindow(cx, cy)
	local screen, size = gui.AbsoluteSize, window.AbsoluteSize
	local function clamp(v, half, total)
		if total <= half * 2 then
			return total / 2
		end
		return math.clamp(v, half, total - half)
	end
	window.Position = UDim2.fromOffset(clamp(cx, size.X / 2, screen.X), clamp(cy, size.Y / 2, screen.Y))
end

-- Перетаскивание окна за шапку (палец или мышь)
do
	local dragging, dragStart, startCenter
	connect(titleBar.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			local p, s = window.AbsolutePosition, window.AbsoluteSize
			dragging, dragStart, startCenter = true, input.Position, Vector2.new(p.X + s.X / 2, p.Y + s.Y / 2)
		end
	end)
	connect(UserInputService.InputChanged, function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - dragStart
			placeWindow(startCenter.X + d.X, startCenter.Y + d.Y)
		end
	end)
	connect(UserInputService.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

connect(Players.PlayerAdded, function()
	rebuildPlayers()
end)
connect(Players.PlayerRemoving, function(p)
	task.defer(function()
		rebuildPlayers()
		if current and current.player == p then
			setHeaderSub()
		end
	end)
end)

gui.Destroying:Connect(function()
	for _, c in ipairs(connections) do
		c:Disconnect()
	end
end)

-- Куда повесить окно: скрытая папка Delta, иначе CoreGui, иначе PlayerGui
for _, getParent in ipairs({
	function()
		return gethui()
	end,
	function()
		return game:GetService("CoreGui")
	end,
	function()
		return Players.LocalPlayer:WaitForChild("PlayerGui")
	end,
}) do
	if pcall(function()
		gui.Parent = getParent()
	end) and gui.Parent then
		break
	end
end
env.InvCalcGui = gui

if not Sync then
	priceStatus.Text = "⚠ не нашёл базу предметов MM2 — это точно Murder Mystery 2?"
	priceStatus.TextColor3 = COL.red
end

rebuildPlayers()
updateTotals()
renderItems()
task.spawn(refreshPrices, true) -- цены сразу при запуске

-- Пока окно открыто: раз в 20 с обновляем «N мин назад», а цены старше 3 минут
-- тихо перекачиваем и пересчитываем выбранного игрока (правки сохраняются)
task.spawn(function()
	while gui.Parent do
		task.wait(20)
		if not gui.Parent then
			break
		end
		onPriceState()
		if window.Visible then
			refreshIfStale()
		end
	end
end)
