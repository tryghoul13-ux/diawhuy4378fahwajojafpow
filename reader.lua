-- Ридер игроков для MM2: уровень и экипированные предметы каждого игрока.
-- Данные берутся из атрибутов игрока (Level, EquippedKnife, EquippedGun и т.д.),
-- MM2 сама рассылает их всем. Ролей тут нет.
-- Редкость скинов берётся из базы предметов игры (ReplicatedStorage.Database).
-- Подсвечиваются игроки, у которых нож или пистолет выше Legendary.
-- Кнопка «🚫 Авто» сама блокирует тех, у кого и нож, и пистолет ниже годли.
-- Запуск в Delta: loadstring(readfile('reader.lua'))()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local CoreGui = game:GetService("CoreGui")
local GuiService = game:GetService("GuiService")
local _, VirtualInputManager = pcall(game.GetService, game, "VirtualInputManager") -- жать кнопку в окне Roblox

-- Повторный запуск заменяет старое окно, а не плодит копии
local env = (getgenv and getgenv()) or _G
if env.ReaderGui then
	env.ReaderGui:Destroy()
end

-- ID оператора: по нему exe на ПК находит именно эту панель. Создаётся один раз,
-- хранится в operator_id.txt рядом с ридером. Показывается в окне, чтобы вставить в exe
local operatorId
pcall(function()
	if isfile and isfile("operator_id.txt") then
		operatorId = readfile("operator_id.txt")
	end
end)
if type(operatorId) ~= "string" or #operatorId < 3 then
	math.randomseed(os.time() + math.floor(os.clock() * 1000))
	local chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	operatorId = ""
	for _ = 1, 5 do
		local i = math.random(1, #chars)
		operatorId = operatorId .. chars:sub(i, i)
	end
	pcall(writefile, "operator_id.txt", operatorId)
end

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

local function label(props)
	props.BackgroundTransparency = 1
	props.Font = props.Font or Enum.Font.Gotham
	props.TextColor3 = props.TextColor3 or Color3.fromRGB(215, 215, 222)
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	props.TextTruncate = Enum.TextTruncate.AtEnd
	return new("TextLabel", props)
end

-- Редкость предметов

-- База предметов MM2, по ней игра сама красит инвентарь
local itemTables = {}
local database = ReplicatedStorage:FindFirstChild("Database")
if database then
	for _, module in ipairs(database:GetDescendants()) do
		if module:IsA("ModuleScript") then
			local ok, data = pcall(require, module)
			if ok and type(data) == "table" then
				table.insert(itemTables, data)
			end
		end
	end
end

local function findEntry(t, id, depth, seen)
	if depth > 4 or seen[t] then
		return nil
	end
	seen[t] = true
	local direct = rawget(t, id)
	if type(direct) == "table" then
		return direct
	end
	for _, v in pairs(t) do
		if type(v) == "table" then
			local found = findEntry(v, id, depth + 1, seen)
			if found then
				return found
			end
		end
	end
	return nil
end

local rarityCache = {}
local function getRarity(id)
	if id == nil then
		return nil
	end
	if rarityCache[id] == nil then
		local rarity = false
		for _, t in ipairs(itemTables) do
			local entry = findEntry(t, id, 1, {})
			if entry then
				rarity = rawget(entry, "Rarity") or false
				if rarity and rawget(entry, "Chroma") == true then
					rarity = "Chroma " .. tostring(rarity)
				end
				break
			end
		end
		rarityCache[id] = rarity
	end
	return rarityCache[id] or nil
end

-- Asset id картинки предмета из базы игры. Поле Image бывает в трёх видах:
-- "...assetId=123", "rbxassetid://123", "rbxthumb://...id=123". Выдёргиваем число.
local assetCache = {}
local function itemAsset(id)
	if id == nil then
		return nil
	end
	if assetCache[id] == nil then
		local found = false
		for _, t in ipairs(itemTables) do
			local entry = findEntry(t, id, 1, {})
			if entry then
				local img = rawget(entry, "Image")
				if type(img) == "string" then
					found = img:match("assetId=(%d+)") or img:match("rbxassetid://(%d+)")
						or img:match("id=(%d+)") or img:match("(%d+)") or false
				end
				break
			end
		end
		assetCache[id] = found
	end
	return assetCache[id] or nil
end

-- Цены предметов (с mm2values.com). Берём из локального values.lua, а если его нет
-- (запуск короткой командой с GitHub) — тянем по ссылке. Нет и ссылки — работаем без цен.
-- ВАЖНО: вставь сюда raw-ссылку на свой values.lua (меняется при настройке GitHub):
local VALUES_URL = "https://raw.githubusercontent.com/tryghoul13-ux/diawhuy4378fahwajojafpow/main/values.lua"
local valueDB
pcall(function()
	local txt
	if isfile and isfile("values.lua") then
		txt = readfile("values.lua")
	end
	if type(txt) ~= "string" or #txt < 100 then
		-- локального файла нет — качаем по ссылке
		local url = (_G and _G.MM2_VALUES_URL) or VALUES_URL
		if not url:find("USERNAME", 1, true) then -- ссылка настроена
			pcall(function()
				txt = game:HttpGet(url)
			end)
			if type(txt) == "string" then
				pcall(writefile, "values.lua", txt) -- закэшируем локально
			end
		end
	end
	if type(txt) == "string" then
		local chunk = loadstring(txt)
		if chunk then
			local ok, data = pcall(chunk)
			if ok and type(data) == "table" and type(data.byKey) == "table" then
				valueDB = data
			end
		end
	end
end)

-- Крутыми считаем только годли и выше (ancient/unique/vintage; хромы тоже — у них в строке
-- редкости есть "godly"). Всё ниже (common..legendary) в цену и в топ не идёт: там и фейки
-- из-за совпадения имён сезонок, и ценность копеечная.
local HIGH_RARITIES = { "godly", "ancient", "unique", "vintage" }

local function isHigh(rarity)
	if rarity == nil then
		return false
	end
	local key = string.lower(tostring(rarity))
	for _, name in ipairs(HIGH_RARITIES) do
		if key:find(name) then
			return true
		end
	end
	return false
end

-- Рарность игры -> категория на сайте
local RARITY_TO_CAT = {
	common = "common", uncommon = "uncommon", rare = "rare", legendary = "legend",
	godly = "godly", ancient = "ancient", unique = "unique", vintage = "vintage",
}
local function rarityCat(rarity)
	if rarity == nil then
		return nil
	end
	local key = string.lower(tostring(rarity))
	if key:find("chroma") then
		return "chroma"
	end
	for name, cat in pairs(RARITY_TO_CAT) do
		if key:find(name) then
			return cat
		end
	end
	return nil -- Classic и прочее, чего на сайте нет
end

-- Имя-ключ, как в values.lua: убираем хвосты Knife/Gun, годы и служебные _K_/_G_
local function normBase(id)
	local s = tostring(id):lower():gsub("[^a-z0-9]", " ")
	local toks = {}
	for t in s:gmatch("%S+") do
		if not (t == "gun" or t == "knife" or t == "g" or t == "k"
			or t:match("^%d%d$") or t:match("^[12]%d%d%d$"))
		then
			toks[#toks + 1] = t
		end
	end
	s = table.concat(toks):gsub("knife$", ""):gsub("gun$", "")
	return s
end

-- Цена предмета. Считаем только годли и выше и только строго по редкости+типу+имени
-- (без запасного поиска по одному имени — он давал фейки, напр. Floral_G_2026 -> rare Floral).
-- slot = "knife"/"gun"; для рюкзака тип неизвестен (slot=nil) — пробуем оба.
local function itemValue(id, rarity, slot)
	if id == nil or not valueDB or not isHigh(rarity) then
		return nil
	end
	local cat = rarityCat(rarity)
	if not cat then
		return nil
	end
	local base = normBase(id)
	if base == "" then
		return nil
	end
	if slot then
		return valueDB.byKey[cat .. "|" .. slot .. "|" .. base]
	end
	return valueDB.byKey[cat .. "|knife|" .. base] or valueDB.byKey[cat .. "|gun|" .. base]
end

-- Короткая запись цены: 1500 -> "1.5K", 2000000 -> "2M"
local function fmtValue(v)
	local s
	if v >= 1e9 then
		s = ("%.1fB"):format(v / 1e9)
	elseif v >= 1e6 then
		s = ("%.1fM"):format(v / 1e6)
	elseif v >= 1e3 then
		s = ("%.1fK"):format(v / 1e3)
	else
		return tostring(v)
	end
	return (s:gsub("%.0(%a)$", "%1")) -- "2.0M" -> "2M"
end

-- Цвет цены по тиру: чем дороже, тем «горячее». Так видно, что круче, что хуже
local VALUE_TIERS = {
	{ 1000000, Color3.fromRGB(255, 70, 200) }, -- 1M+  топ
	{ 100000, Color3.fromRGB(180, 110, 255) },
	{ 10000, Color3.fromRGB(255, 120, 60) },
	{ 1000, Color3.fromRGB(255, 205, 70) },
	{ 100, Color3.fromRGB(140, 230, 150) },
	{ 10, Color3.fromRGB(90, 200, 255) },
}
local function valueColor(v)
	for _, tier in ipairs(VALUE_TIERS) do
		if v >= tier[1] then
			return tier[2]
		end
	end
	return Color3.fromRGB(150, 160, 170) -- мелочь
end

-- Ремоут полного инвентаря (та же кнопка «Inventory», что в игре). Нет его — рюкзак не считаем
local invRemote
pcall(function()
	invRemote = ReplicatedStorage.Remotes.Extras.GetFullInventory
end)

-- Цена владеемого предмета (тип неизвестен) — то же, что itemValue без slot
local function ownedItemValue(id, rarity)
	return itemValue(id, rarity, nil)
end

local RARITY_COLORS = {
	chroma = Color3.fromRGB(0, 255, 160),
	godly = Color3.fromRGB(255, 70, 200),
	ancient = Color3.fromRGB(170, 110, 255),
	unique = Color3.fromRGB(255, 150, 50),
	vintage = Color3.fromRGB(230, 200, 90),
	legendary = Color3.fromRGB(255, 180, 60),
	rare = Color3.fromRGB(80, 150, 255),
	uncommon = Color3.fromRGB(110, 205, 120),
	common = Color3.fromRGB(175, 180, 190),
	classic = Color3.fromRGB(120, 210, 230),
}

-- chroma надо проверять первым: строка редкости у хром — "Chroma Godly" и т.п.
local RARITY_ORDER = { "chroma", "godly", "ancient", "unique", "vintage", "legendary", "rare", "uncommon", "common", "classic" }

local function rarityColor(rarity)
	if rarity == nil then
		return Color3.fromRGB(150, 160, 170)
	end
	local key = string.lower(tostring(rarity))
	for _, name in ipairs(RARITY_ORDER) do
		if key:find(name) then
			return RARITY_COLORS[name]
		end
	end
	return Color3.fromRGB(90, 220, 255) -- ивентовые и прочие редкие
end

-- Цвет предмета: база по редкости, но с лёгким разбросом по имени, чтобы два предмета
-- одной редкости (напр. два ancient) чуть отличались оттенком и различались глазом
local function variedColor(rarity, id)
	local base = rarityColor(rarity)
	local n = 0
	for i = 1, #tostring(id) do
		n = (n * 31 + string.byte(id, i)) % 100000
	end
	local h, s, v = Color3.toHSV(base)
	h = (h + ((n % 21) - 10) / 360) % 1 -- ±10° по тону
	v = math.clamp(v + (((n // 21) % 13) - 6) / 100, 0.4, 1) -- ±0.06 по яркости
	return Color3.fromHSV(h, s, v)
end

-- Имя предмета, покрашенное по редкости (с разбросом). value — цветом по тиру цены
local function itemText(id, rarity, valEntry)
	if id == nil then
		return "—"
	end
	local s = ('<font color="#%s">%s</font>'):format(variedColor(rarity, id):ToHex(), tostring(id))
	if isHigh(rarity) then
		s = s .. (' <font color="#%s"><b>[%s]</b></font>'):format(
			rarityColor(rarity):ToHex(), tostring(rarity))
	end
	if valEntry then
		s = s .. (' <font color="#%s"><b>%s</b></font>'):format(
			valueColor(valEntry.v):ToHex(), fmtValue(valEntry.v))
	end
	return s
end

-- Окно

local gui = new("ScreenGui", {
	Name = "ReaderGui",
	ResetOnSpawn = false, -- не пропадает после смерти
	IgnoreGuiInset = true, -- затемнение на весь экран
	DisplayOrder = 100, -- поверх интерфейса игры
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})

local overlay = new("Frame", {
	Name = "Overlay",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.4,
	Active = true, -- нажатия не уходят в игру под окном
	Parent = gui,
})

local panel = new("Frame", {
	Name = "Panel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.7, 0.8),
	BackgroundColor3 = Color3.fromRGB(28, 28, 34),
	Parent = overlay,
})
new("UICorner", { CornerRadius = UDim.new(0, 12), Parent = panel })
new("UISizeConstraint", {
	MinSize = Vector2.new(300, 240),
	MaxSize = Vector2.new(760, 560),
	Parent = panel,
})
new("UIPadding", {
	PaddingTop = UDim.new(0, 14),
	PaddingBottom = UDim.new(0, 14),
	PaddingLeft = UDim.new(0, 16),
	PaddingRight = UDim.new(0, 16),
	Parent = panel,
})

local title = label({
	Name = "Title",
	Size = UDim2.new(1, -340, 0, 40),
	Font = Enum.Font.GothamBold,
	Text = "👥 Игроки",
	TextSize = 24,
	RichText = true, -- для цветного ID оператора в конце
	TextColor3 = Color3.fromRGB(240, 240, 245),
	Parent = panel,
})

-- Старт: включает полностью автоматический режим (блокает всех без годли+, ловит новых)
local autoButton = new("TextButton", {
	Name = "StartButton",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -52, 0, 0),
	Size = UDim2.fromOffset(260, 40),
	BackgroundColor3 = Color3.fromRGB(50, 140, 70),
	Font = Enum.Font.GothamBold,
	Text = "▶ Старт",
	TextSize = 20,
	TextColor3 = Color3.new(1, 1, 1),
	Parent = panel,
})
new("UICorner", { CornerRadius = UDim.new(0, 8), Parent = autoButton })

-- ✕ только закрывает окно, из игры не выходит
local closeButton = new("TextButton", {
	Name = "CloseButton",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(1, 0),
	Size = UDim2.fromOffset(44, 40),
	BackgroundColor3 = Color3.fromRGB(60, 60, 72),
	Font = Enum.Font.GothamBold,
	Text = "X", -- символа ✕ в шрифте Roblox нет, рисовался пустым квадратом
	TextSize = 22,
	TextColor3 = Color3.new(1, 1, 1),
	Parent = panel,
})
new("UICorner", { CornerRadius = UDim.new(0, 8), Parent = closeButton })

local list = new("ScrollingFrame", {
	Name = "List",
	Position = UDim2.fromOffset(0, 52),
	Size = UDim2.new(1, 0, 1, -58), -- на всю высоту, снизу небольшой отступ
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	Parent = panel,
})
new("UIListLayout", {
	Padding = UDim.new(0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = list,
})

-- Служебная строка (от замера осталась, скрыта). Нужна, чтобы старый код не падал
local testStatus = label({
	Name = "TestStatus",
	Position = UDim2.new(0, 0, 1, -24),
	Size = UDim2.new(1, 0, 0, 20),
	TextSize = 14,
	TextColor3 = Color3.fromRGB(255, 210, 120),
	Text = "",
	Visible = false,
	Parent = panel,
})

-- После закрытия окна остаётся эта кнопка, чтобы открыть его снова
local openButton = new("TextButton", {
	Name = "OpenButton",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -16),
	Size = UDim2.fromOffset(150, 44),
	BackgroundColor3 = Color3.fromRGB(28, 28, 34),
	Font = Enum.Font.GothamBold,
	Text = "👥 Игроки",
	TextSize = 20,
	TextColor3 = Color3.new(1, 1, 1),
	Visible = false,
	Parent = gui,
})
new("UICorner", { CornerRadius = UDim.new(0, 10), Parent = openButton })

-- Строки игроков

local rows = {} -- [player] = { frame = Frame, high = есть ли скин выше Legendary, blocked = заблокирован ли }
local connections = {}

local function setOpen(isOpen)
	overlay.Visible = isOpen
	openButton.Visible = not isOpen
end

-- Блок обычный, как в меню Roblox, только без ручного подтверждения.
-- Сам блок из Delta сделать нельзя: у Delta нет права RobloxScript, а require модулей
-- Roblox (CorePackages) ломает меню Roblox до перезахода. Поэтому открываем
-- обычное окно блокировки и сами жмём в нём кнопку. Блокирует сам Roblox, своими правами.
local blockedIds = {}
-- [userId] = true: мы разблокировали игрока (или Roblox сказал «нечего снимать»), а клиентский
-- список GetBlockedUserIds может залипнуть и показывать его заблокированным. Держим «не заблокирован».
-- СОХРАНЯЕМ В ФАЙЛ: при перезаходе в игру ридер перезапускается, и без файла пометка бы потерялась,
-- из-за чего при повторном входе снова висела бы «Снять блок», а автоблок бы игрока пропускал.
local serverUnblocked = {}
local SU_FILE = "server_unblocked.txt"
local function setServerUnblocked(userId, value)
	serverUnblocked[userId] = value or nil
	local ids = {}
	for id in pairs(serverUnblocked) do
		ids[#ids + 1] = tostring(id)
	end
	pcall(writefile, SU_FILE, table.concat(ids, ","))
end
pcall(function() -- восстанавливаем список при запуске
	if isfile and isfile(SU_FILE) then
		for id in readfile(SU_FILE):gmatch("%d+") do
			serverUnblocked[tonumber(id)] = true
		end
	end
end)
local lastBlockEvent = {} -- [userId] = true/false: что последним сообщил Roblox (PlayerBlockedEvent)
local blockInProgress = false

-- Очередь: кого не удалось заблокировать сразу (лимит Roblox или сбой нажатия).
-- Ридер сам пробует снова, пока не получится. Вышедших с сервера из очереди убирает.
local queue = {} -- [player] = { block = true/false, nextTry = os.clock() }
local RETRY_LIMIT = 60 -- через сколько секунд повторять после лимита Roblox
local RETRY_FAILED = 10 -- после сбоя нажатия

local autoBlock = false -- включён ли авто-блок
local autoSkip = {} -- [userId] = true: кого вручную разблокировали или убрали из очереди, авто-блок их не трогает

-- Очередь запросов рюкзака: игроков дёргаем по одному, чтобы не долбить сервер
local invQueue = {}
local invDebug = {} -- временно: разбор по игрокам для проверки сумм (inv_debug.txt)

local workingOffset -- сдвиг от центра надписи, при котором нажатие сработало, запоминаем

-- Что известно о лимите: сколько блоков проходит подряд (count) и через сколько секунд
-- после первого из них лимит снимается (window). Намеряет кнопка «🧪 Замер», хранится в limit.txt
local limitInfo
local recentBlocks = {} -- os.time() удачных блоков за этот запуск
pcall(function()
	local text = readfile("limit.txt")
	local count, window = text:match("count=(%d+)"), text:match("window=(%d+)")
	if count and window then
		limitInfo = { count = tonumber(count), window = tonumber(window) }
	end
end)

local function fmt(seconds)
	return ("%d:%02d"):format(math.floor(seconds / 60), math.floor(seconds % 60))
end

-- Через сколько секунд повторять после лимита. Если лимит замерен, считаем точно:
-- он снимается через window после первого из последних count блоков
local function limitRetryDelay()
	if limitInfo and #recentBlocks >= limitInfo.count then
		local first = recentBlocks[#recentBlocks - limitInfo.count + 1]
		local wait = first + limitInfo.window + 3 - os.time()
		return wait > 0 and wait or 15
	end
	return RETRY_LIMIT
end

local function markBlocked(player, isBlocked)
	blockedIds[player.UserId] = isBlocked or nil
	if isBlocked then
		setServerUnblocked(player.UserId, false) -- реально заблокировали — фантом неактуален
	end
	local entry = rows[player]
	if entry and entry.setBlocked then
		entry.setBlocked(isBlocked)
	end
end

-- Возвращает true, если список удалось прочитать
local function refreshBlocked()
	local ok, ids = pcall(StarterGui.GetCore, StarterGui, "GetBlockedUserIds")
	if not ok or type(ids) ~= "table" then
		return false
	end
	blockedIds = {}
	for _, id in ipairs(ids) do
		blockedIds[id] = true
	end
	-- Залипшие фантомы: сервер их уже разблокировал, не верим клиентскому списку
	for id in pairs(serverUnblocked) do
		blockedIds[id] = nil
	end
	for player, entry in pairs(rows) do
		if entry.setBlocked then
			entry.setBlocked(blockedIds[player.UserId] == true)
		end
	end
	return true
end

-- Сырой ответ списка Roblox по одному игроку, БЕЗ поправки на serverUnblocked.
-- Нужен для подтверждения блока: иначе пометка «не заблокирован» мешала бы подтвердить новый блок.
-- true — есть в списке, false — нет, nil — список не прочитался
local function rawBlocked(userId)
	local ok, ids = pcall(StarterGui.GetCore, StarterGui, "GetBlockedUserIds")
	if not ok or type(ids) ~= "table" then
		return nil
	end
	for _, id in ipairs(ids) do
		if id == userId then
			return true
		end
	end
	return false
end

-- Кнопка «Заблокировать» / «Разблокировать» в окне Roblox. Точная подпись зависит
-- от языка, поэтому ищем короткий текст со словом «блок», без «и пожаловаться», «отмена» и т.п.
local SKIP_WORDS = { "пожал", "Пожал", "жалоб", "сообщ", "report", "Report", "Отмен", "отмен",
	"Cancel", "cancel", "Подтвер", "подтвер", "Confirm", "confirm", " и ", " and ", "?" }

local function isConfirmText(text, player)
	if #text == 0 or #text > 40 then
		return false
	end
	if not (text:find("блок", 1, true) or text:find("Блок", 1, true) or text:lower():find("block", 1, true)) then
		return false
	end
	for _, word in ipairs(SKIP_WORDS) do
		if text:find(word, 1, true) then
			return false
		end
	end
	return not text:find(player.DisplayName, 1, true) and not text:find(player.Name, 1, true)
end

local function findConfirmLabel(candidates, player)
	local best
	for _, obj in ipairs(candidates) do
		if obj.Parent and obj.Visible and obj.AbsoluteSize.X > 0 and isConfirmText(obj.Text, player) then
			-- Кнопка блока последняя: ниже или правее остальных
			if not best or obj.AbsolutePosition.Y > best.AbsolutePosition.Y
				or (obj.AbsolutePosition.Y == best.AbsolutePosition.Y and obj.AbsolutePosition.X > best.AbsolutePosition.X)
			then
				best = obj
			end
		end
	end
	return best
end

-- Кнопка, внутри которой надпись. Затемнение на весь экран тоже кнопка (жмёт «Отмена»), его пропускаем
local function buttonOf(label)
	local screen = workspace.CurrentCamera.ViewportSize
	local obj = label
	while obj and obj:IsA("GuiObject") do
		if obj:IsA("GuiButton") and obj.AbsoluteSize.X < screen.X * 0.8 then
			return obj
		end
		obj = obj.Parent
	end
	return nil
end

local function pressEscape()
	pcall(function()
		VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Escape, false, game)
		task.wait(0.05)
		VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Escape, false, game)
	end)
end

-- Ждёт, пока надпись пропадёт (окно закрылось). true, если пропала
local function waitGone(label, seconds)
	local deadline = os.clock() + seconds
	while label:IsDescendantOf(game) and os.clock() < deadline do
		task.wait(0.1)
	end
	return not label:IsDescendantOf(game)
end

-- Точное место нажатия неизвестно: с отступом верхней панели или без него.
-- Водим мышь по вариантам и смотрим, когда кнопка подсветится (GuiState = Hover).
-- Возвращает "clicked" (окно закрылось), "left" (игрок вышел, не жали) или "missed"
local function clickOn(label, playerLeft)
	local button = buttonOf(label)
	local center = label.AbsolutePosition + label.AbsoluteSize / 2
	local inset = GuiService:GetGuiInset()

	-- Новое окно блокировки Roblox (FoundationOverlay) НЕ реагирует на клик мышью по координатам:
	-- его кнопка активируется выбором (GuiService.SelectedObject) и клавишей Enter.
	-- Пробуем это первым — так же надёжно жмётся и старое окно Roblox.
	if button then
		local okSel = pcall(function()
			GuiService.SelectedObject = button
		end)
		task.wait(0.1)
		local selected = okSel and GuiService.SelectedObject == button
		if selected then
			pcall(function()
				VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
				task.wait(0.05)
				VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
			end)
			local gone = waitGone(label, 2)
			pcall(function()
				GuiService.SelectedObject = nil
			end)
			if gone then
				print("[Ридер] активировал кнопку выбором+Enter:", button:GetFullName())
				return "clicked", 1
			end
		else
			pcall(function()
				GuiService.SelectedObject = nil
			end)
		end
	end

	-- На MEmu срабатывает центр + отступ верхней панели, его пробуем первым
	local points = { center + inset, center, center - inset }
	if workingOffset then
		table.insert(points, 1, center + workingOffset)
	end
	local log = {}

	local target
	for _, point in ipairs(points) do
		local ok = pcall(function()
			VirtualInputManager:SendMouseMoveEvent(point.X, point.Y, game)
		end)
		task.wait(0.15)
		local state = button and button.GuiState
		log[#log + 1] = ("%d,%d->%s"):format(point.X, point.Y, ok and tostring(state) or "ошибка")
		if button and state == Enum.GuiState.Hover then
			target = point
			break
		end
	end

	local screenGui = label:FindFirstAncestorWhichIsA("ScreenGui")
	print("[Ридер] кнопка:", button and button:GetFullName(), "экран:", screenGui and screenGui.Name,
		"IgnoreGuiInset:", screenGui and screenGui.IgnoreGuiInset, "inset:", inset, "проба:", table.concat(log, " "))

	-- Подсветка подтвердила, что курсор на кнопке: жмём один раз и больше не трогаем.
	-- Окно может висеть несколько секунд, пока Roblox ждёт ответа сервера, и повторное
	-- нажатие в это время даёт ложный успех без настоящего блока
	if target then
		pcall(function()
			VirtualInputManager:SendMouseButtonEvent(target.X, target.Y, 0, true, game, 1)
			task.wait(0.05)
			VirtualInputManager:SendMouseButtonEvent(target.X, target.Y, 0, false, game, 1)
		end)
		workingOffset = target - center
		print("[Ридер] нажали в", target)
		return "clicked"
	end

	-- Подсветки не было: жмём по очереди, пока окно не отреагирует.
	-- Выше центра не жмём, там соседняя кнопка «Заблокировать и пожаловаться»
	local tries = { center + inset, center }
	local presses = 0
	for _, point in ipairs(tries) do
		-- Игрок ушёл, пока окно открывалось: блок на него не тратим
		if playerLeft() then
			return "left", presses
		end
		pcall(function()
			VirtualInputManager:SendMouseButtonEvent(point.X, point.Y, 0, true, game, 1)
			task.wait(0.05)
			VirtualInputManager:SendMouseButtonEvent(point.X, point.Y, 0, false, game, 1)
		end)
		presses += 1
		if waitGone(label, 1.5) then
			workingOffset = point - center
			print("[Ридер] нажали в", point)
			return "clicked", presses
		end
		if playerLeft() then
			return "left", presses
		end
		-- Мышь не сработала, пробуем касанием
		pcall(function()
			VirtualInputManager:SendTouchEvent(7, 0, point.X, point.Y)
			task.wait(0.05)
			VirtualInputManager:SendTouchEvent(7, 2, point.X, point.Y)
		end)
		presses += 1
		if waitGone(label, 1.5) then
			workingOffset = point - center
			print("[Ридер] нажали касанием в", point)
			return "clicked", presses
		end
	end
	return "missed", presses
end

local function never()
	return false
end

-- Открыто ли ещё окно Roblox (по надписям, которые в нём появились)
local function dialogOpen(candidates)
	for _, obj in ipairs(candidates) do
		if obj:IsDescendantOf(game) then
			local name = obj:GetFullName()
			if name:find("Modal", 1, true) or name:find("Prompt", 1, true)
				or name:find("Dialog", 1, true) or name:find("Alert", 1, true)
			then
				return true
			end
		end
	end
	return false
end

local CANCEL_TEXTS = { ["Отмена"] = true, ["Отменить"] = true, ["Cancel"] = true }

-- Закрывает окно Roblox без блока, чтобы оно не висело на экране:
-- Escape, потом «Отмена», потом нажатие мимо окна (по затемнению, оно тоже отменяет)
local function closeDialog(candidates)
	if not dialogOpen(candidates) then
		return true
	end
	pressEscape()
	task.wait(0.5)
	if not dialogOpen(candidates) then
		return true
	end
	for _, obj in ipairs(candidates) do
		if obj:IsDescendantOf(game) and CANCEL_TEXTS[obj.Text] then
			clickOn(obj, never)
			task.wait(0.5)
			if not dialogOpen(candidates) then
				return true
			end
			break
		end
	end
	local screen = workspace.CurrentCamera.ViewportSize
	local point = Vector2.new(8, screen.Y / 2) + GuiService:GetGuiInset()
	pcall(function()
		VirtualInputManager:SendMouseButtonEvent(point.X, point.Y, 0, true, game, 1)
		task.wait(0.05)
		VirtualInputManager:SendMouseButtonEvent(point.X, point.Y, 0, false, game, 1)
	end)
	task.wait(0.5)
	local closed = not dialogOpen(candidates)
	if not closed then
		print("[Ридер] окно Roblox не закрылось")
	end
	return closed
end

-- Если Roblox не смог заблокировать (в том числе лимит блоков), вместо закрытия окна
-- он показывает уведомление об ошибке. Ищем его среди новых надписей
local ERROR_WORDS = { "пошло не так", "went wrong", "шибк", "rror", "лимит", "imit",
	"лишком", "oo many", "позже", "later" }

local function findErrorText(objs, from)
	for i = from, #objs do
		local obj = objs[i]
		if obj.Parent then
			for _, word in ipairs(ERROR_WORDS) do
				if obj.Text:find(word, 1, true) then
					return obj.Text
				end
			end
		end
	end
	return nil
end

-- Журнал блоков: по нему можно понять, через сколько времени снимается лимит Roblox
local function logBlock(player, block, result)
	local line = ("%s | %s | %s (%d) | %s\n"):format(
		os.date("%Y-%m-%d %H:%M:%S"), block and "блок" or "разблок", player.Name, player.UserId, result)
	pcall(function()
		local old = (isfile and isfile("block_log.txt")) and readfile("block_log.txt") or ""
		writefile("block_log.txt", old .. line)
	end)
	print("[Ридер] " .. line)
end

-- Блокирует или разблокирует. Возвращает true или false и причину:
-- "left" игрок вышел, "limit" Roblox отказал (лимит блоков), "failed" не получилось нажать
-- (окно закрыто), "notblocked" окно закрылось, но в списке Roblox разблока нет, "noprompt" окно не открылось
local function setBlockedAsync(player, block)
	local function playerLeft()
		return player.Parent ~= Players
	end
	if playerLeft() then
		return false, "left"
	end

	local candidates = {}
	local watcher = CoreGui.DescendantAdded:Connect(function(obj)
		-- Чат и сам ридер не трогаем: там могут быть слова «block», «error» и т.п.
		if (obj:IsA("TextLabel") or obj:IsA("TextButton"))
			and not obj:IsDescendantOf(gui)
			and not obj:GetFullName():find("Chat", 1, true)
		then
			table.insert(candidates, obj)
		end
	end)
	local function finish(success, reason)
		watcher:Disconnect()
		gui.Enabled = true
		if success then
			if block then
				table.insert(recentBlocks, os.time())
				setServerUnblocked(player.UserId, false) -- заблокировали — пометка «не заблокирован» снята
			else
				-- Разблокировали — держим «не заблокирован» и после перезахода, чтобы залипший
				-- список Roblox не вернул кнопку в «Снять блок», а автоблок взял игрока снова
				setServerUnblocked(player.UserId, true)
			end
		end
		logBlock(player, block, success and "ok" or reason)
		return success, reason
	end

	-- Ридер выше окна Roblox, без этого нажатие попало бы в него
	gui.Enabled = false
	lastBlockEvent[player.UserId] = nil
	local ok, err = pcall(StarterGui.SetCore, StarterGui, block and "PromptBlockPlayer" or "PromptUnblockPlayer", player)
	if not ok then
		print("[Ридер] окно блокировки не открылось:", err)
		return finish(false, "noprompt")
	end

	local label
	local deadline = os.clock() + 3
	repeat
		task.wait()
		label = findConfirmLabel(candidates, player)
	until label or playerLeft() or os.clock() > deadline

	if not label then
		if playerLeft() then
			closeDialog(candidates)
			return finish(false, "left")
		end
		-- Если игрок уже заблокирован, Roblox окно не показывает
		if refreshBlocked() and (blockedIds[player.UserId] == true) == block then
			return finish(true)
		end
		-- Кнопку не нашли: закрываем окно, очередь попробует ещё раз
		local texts = {}
		for _, obj in ipairs(candidates) do
			if obj.Parent and obj.Text ~= "" then
				texts[#texts + 1] = obj.Text
			end
		end
		print("[Ридер] кнопка в окне не найдена, тексты:", table.concat(texts, " | "))
		closeDialog(candidates)
		return finish(false, "failed")
	end

	-- Окно появляется с анимацией, ждём, пока кнопка встанет на место
	local last
	for _ = 1, 30 do
		task.wait()
		if last == label.AbsolutePosition then
			break
		end
		last = label.AbsolutePosition
	end
	task.wait(0.3) -- кнопки в окне Roblox могут не принимать нажатие сразу после появления

	local clickIndex = #candidates -- всё, что появится дальше, это ответ Roblox на нажатие
	local clickTime = os.clock()
	local click, presses = clickOn(label, playerLeft)
	if click == "left" then
		closeDialog(candidates) -- игрока уже нет, блок не тратим
		return finish(false, "left")
	elseif click == "missed" then
		-- Не попали: закрываем окно, очередь попробует ещё раз
		print("[Ридер] окно не закрылось после нажатия:", label.Text)
		closeDialog(candidates)
		return finish(false, "failed")
	end

	-- Ждём окончательный ответ сервера. Событию блока и списку сразу после нажатия верить
	-- нельзя: Roblox отмечает игрока заблокированным заранее, а при отказе снимает отметку.
	-- Окно закрывается целиком только при настоящем успехе. При отказе (429, лимит)
	-- вместо окна появляется «Something went wrong». На 429 Roblox сам повторяет запрос
	-- через 5 с, поэтому ответ может прийти через 6 с и позже
	local outcome
	deadline = os.clock() + 15
	repeat
		task.wait(0.2)
		local errorText = findErrorText(candidates, clickIndex + 1)
		if errorText then
			print("[Ридер] Roblox отказал:", errorText)
			outcome = "error"
		elseif not dialogOpen(candidates) then
			outcome = "closed"
		end
	until outcome or os.clock() > deadline

	if outcome == "error" then
		closeDialog(candidates)
		if not block then
			-- Разблокировка «Error Unblocking User» = на сервере блока нет (его нечего снимать).
			-- Клиентский список мог залипнуть (фантом). Верим серверу: он НЕ заблокирован.
			-- Помечаем как фантом, чтобы залипший список больше не возвращал кнопку в «Снять блок».
			setServerUnblocked(player.UserId, true)
			markBlocked(player, false)
			print("[Ридер] сервер: блока нет, снимаю залипшую отметку:", player.Name)
			return finish(true)
		end
		-- Блок: ошибка — но вдруг он уже в списке. Иначе это отказ (лимит)
		task.wait(1)
		if rawBlocked(player.UserId) == true then
			return finish(true)
		end
		return finish(false, "limit")
	elseif not outcome then
		print("[Ридер] сервер не ответил за 15 с")
		closeDialog(candidates)
		return finish(false, "failed")
	end

	-- Окно закрылось без ошибки — но это ещё НЕ успех. Roblox помечает игрока в своём
	-- локальном списке ОПТИМИСТИЧНО, сразу по клику, до ответа сервера, и откатывает
	-- отметку, если сервер отказал (400/429 и т.п.). Поэтому сначала даём серверу ответить,
	-- потом подтверждаем по списку ДВАЖДЫ подряд — верим только устойчивому результату.
	-- Если нажатий было несколько, окно мог закрыть второй вызов, пока первый запрос
	-- ещё висит. Тогда ждём, пока первый точно ответит (с повтором Roblox это до 7 с)
	if (presses or 1) > 1 then
		local rest = clickTime + 7 - os.clock()
		if rest > 0 then
			task.wait(rest)
		end
	end
	task.wait(1.2) -- пауза на ответ сервера и откат оптимистичной отметки (сервер отвечает ~0.2 с)
	-- Проверяем по СЫРОМУ списку Roblox (rawBlocked), а не по blockedIds: во время блока пометка
	-- serverUnblocked ещё стоит и обнулила бы blockedIds, не дав подтвердить новый блок
	local confirmed = 0
	for _ = 1, 5 do
		local rb = rawBlocked(player.UserId)
		if rb ~= nil then
			if rb == block then
				confirmed += 1
				if confirmed >= 2 then
					local okR, reasonR = finish(true) -- для блока снимает пометку serverUnblocked
					refreshBlocked() -- теперь кнопки с учётом актуальной пометки
					return okR, reasonR
				end
			else
				print("[Ридер] список Roblox не подтвердил результат:", player.Name)
				return finish(false, block and "notblocked" or "stillblocked")
			end
		end
		task.wait(0.5)
	end
	print("[Ридер] не удалось подтвердить блок по списку Roblox:", player.Name)
	return finish(false, block and "notblocked" or "stillblocked")
end

-- Если блокнули или разблокнули через меню Roblox
local function onBlockChanged(isBlocked)
	return function(player)
		if typeof(player) == "Instance" and player:IsA("Player") then
			lastBlockEvent[player.UserId] = isBlocked
			markBlocked(player, isBlocked)
		else
			refreshBlocked()
		end
	end
end

for eventName, isBlocked in pairs({ PlayerBlockedEvent = true, PlayerUnblockedEvent = false }) do
	local ok, event = pcall(StarterGui.GetCore, StarterGui, eventName)
	if ok and event then
		table.insert(connections, event.Event:Connect(onBlockChanged(isBlocked)))
	end
end
task.spawn(refreshBlocked) -- список может грузиться с сервера, окно не ждёт

local function attr(player, name, default)
	local value = player:GetAttribute(name)
	if value == nil then
		return default
	end
	return value
end

local function roman(n)
	local s = ""
	for _, pair in ipairs({ { 10, "X" }, { 9, "IX" }, { 5, "V" }, { 4, "IV" }, { 1, "I" } }) do
		while n >= pair[1] do
			s ..= pair[2]
			n -= pair[1]
		end
	end
	return s
end

local function updateTitle()
	local count, high = 0, 0
	for _, entry in pairs(rows) do
		count += 1
		if entry.high then
			high += 1
		end
	end
	local queued = 0
	for _ in pairs(queue) do
		queued += 1
	end
	title.Text = "👥 Игроки (" .. count .. ")" .. (high > 0 and ("   ★ " .. high) or "")
		.. (queued > 0 and ("   ⏳ " .. queued) or "")
		.. '   <font color="#7FD6FF" size="16">exe: ' .. operatorId .. "</font>"
end

-- Одна попытка блока с результатом на кнопке. Кого не вышло, ставим в очередь
local function runBlock(player, block)
	blockInProgress = true
	local entry = rows[player]
	if entry and entry.showStatus then
		entry.showStatus("...")
	end
	if not block then
		-- Разблокировка: намерение «он НЕ заблокирован» фиксируем СРАЗУ и в файл, ещё до запроса.
		-- Даже если запрос к Roblox упадёт (пустое окно/фантом) — при перезаходе не будет висеть
		-- «Снять блок», а автоблок возьмёт игрока снова
		setServerUnblocked(player.UserId, true)
		markBlocked(player, false)
	end
	local called, ok, reason = pcall(setBlockedAsync, player, block)
	blockInProgress = false
	if not called then
		print("[Ридер] ошибка в блоке:", ok)
		gui.Enabled = true
		ok, reason = false, "failed"
	end

	-- Разблокировку НЕ повторяем: локально уже снято и записано в файл, что бы сервер ни ответил
	if not block then
		queue[player] = nil
		updateTitle()
		if entry and entry.showStatus then
			entry.showStatus("✓ Снято", 1.5)
		end
		return
	end

	if ok then
		queue[player] = nil
		-- Лимит, похоже, снят: остальных из очереди пробуем сразу
		for _, item in pairs(queue) do
			item.nextTry = math.min(item.nextTry, os.clock())
		end
	elseif reason == "left" then
		queue[player] = nil -- вышел с сервера, блок не тратим
	else
		-- После трёх сбоев подряд не дёргаем окно каждые 10 секунд
		local old = queue[player]
		local fails = ((old and old.fails) or 0) + 1
		local delay = RETRY_FAILED
		if reason == "limit" then
			delay = limitRetryDelay()
			-- Лимит общий на все блоки: остальных из очереди раньше тоже не пробуем,
			-- иначе каждый откроет окно Roblox и получит тот же отказ
			for _, item in pairs(queue) do
				if item.block then
					item.nextTry = math.max(item.nextTry, os.clock() + delay)
				end
			end
		elseif fails >= 3 then
			delay = RETRY_LIMIT
		end
		queue[player] = { block = block, nextTry = os.clock() + delay, fails = fails, auto = old and old.auto }
	end
	updateTitle()

	entry = rows[player]
	if entry and entry.showStatus then
		if ok then
			entry.showStatus("✓ Готово", 1.5)
		elseif reason == "left" then
			entry.showStatus("Вышел", 3)
		else
			entry.showStatus(reason == "limit" and "Лимит" or "Ещё раз", 2)
		end
	end
end

-- Замер лимита. Блокирует подряд любых игроков сервера (кроме друзей), пока Roblox не откажет,
-- потом проверяет, когда лимит снимется. Делает это два раза: первый грубо (проверка раз в 15 с),
-- второй точно (молча ждёт почти до первого результата, дальше проверка раз в 5 с).
-- Ход замера пишется в limit_test.txt, итог в limit.txt, и очередь дальше берёт его оттуда.

local testRunning = false
local testLines = {}

local function testNote(text)
	local line = os.date("%H:%M:%S") .. "  " .. text
	testLines[#testLines + 1] = line
	print("[Замер] " .. line)
	pcall(writefile, "limit_test.txt", table.concat(testLines, "\n"))
	testStatus.Text = "🧪 " .. text
end

-- Друзей не блокируем ни в замере, ни авто-блоком: блок удаляет из друзей.
-- Сначала живой статус дружбы в клиенте (сразу видно, если друга удалили прямо в игре).
-- Нет его — спрашиваем Roblox и помним ответ минуту. Ошибку запроса НЕ запоминаем: раньше один
-- сбой навсегда записывал игрока в «друзья», и авто-блок его больше никогда не трогал
local friendCache = {}
local FRIEND_TTL = 60
local function isFriend(player)
	local okStatus, status = pcall(Players.LocalPlayer.GetFriendStatus, Players.LocalPlayer, player)
	if okStatus and (status == Enum.FriendStatus.Friend or status == Enum.FriendStatus.NotFriend) then
		return status == Enum.FriendStatus.Friend
	end
	local cached = friendCache[player.UserId]
	if cached == nil or os.clock() - cached.at > FRIEND_TTL then
		local ok, result = pcall(Players.LocalPlayer.IsFriendsWith, Players.LocalPlayer, player.UserId)
		if not ok then
			return true -- не смогли проверить — сейчас не трогаем, спросим на следующем тике
		end
		cached = { value = result == true, at = os.clock() }
		friendCache[player.UserId] = cached
	end
	return cached.value
end

-- Кого блокировать в замере: любого, кроме себя, друзей, уже заблокированных
-- и тех, у кого надето годли+ (ценных не трогаем даже ради замера)
local function pickTarget()
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= Players.LocalPlayer and not blockedIds[player.UserId] and not isFriend(player) then
			local entry = rows[player]
			if not (entry and entry.high) then
				return player
			end
		end
	end
	return nil
end

-- Одна попытка. true блок прошёл, false лимит, nil игроки кончились или замер остановили
local function testAttempt()
	for _ = 1, 5 do
		if not testRunning then
			return nil
		end
		local target = pickTarget()
		if not target then
			return nil, "кончились игроки для блока (друзей не трогаем)"
		end
		while blockInProgress do
			task.wait(0.2)
		end
		blockInProgress = true
		local called, ok, reason = pcall(setBlockedAsync, target, true)
		blockInProgress = false
		if not called then
			gui.Enabled = true
			print("[Замер] ошибка:", ok)
			ok, reason = false, "failed"
		end
		if ok then
			return true, target
		elseif reason == "limit" then
			return false, target
		end
		-- Игрок вышел или не попали по кнопке: это не ответ лимита, пробуем ещё
		task.wait(2)
	end
	return nil, "пять попыток подряд сорвались"
end

-- Ждёт с отсчётом в строке замера. false, если замер остановили
local function testWait(seconds, what)
	local untilTime = os.clock() + seconds
	while testRunning and os.clock() < untilTime do
		testStatus.Text = ("🧪 %s, проверка через %d с"):format(what, math.ceil(untilTime - os.clock()))
		task.wait(1)
	end
	return testRunning
end

local function runLimitTest()
	testLines = {}
	testNote("старт: блокирую подряд до лимита")
	local measures = {} -- { count = блоков до лимита, fromFirst = снялся через N с после первого, fromLimit = после отказа }
	local burst = {} -- os.clock() удачных блоков текущей серии
	local stopReason = "остановлено"

	while testRunning and #measures < 2 do
		-- 1. Блокируем подряд, пока Roblox не откажет
		local hitAt
		while testRunning do
			local ok, info = testAttempt()
			if ok == nil then
				stopReason = info or stopReason
				break
			elseif ok then
				burst[#burst + 1] = os.clock()
				testNote(("блок #%d прошёл: %s"):format(#burst, info.Name))
			else
				hitAt = os.clock()
				testNote(("ЛИМИТ после %d блоков подряд"):format(#burst))
				break
			end
		end
		if not hitAt then
			break
		end
		if #burst == 0 then
			-- Лимит остался с прошлых блоков, когда он начался, неизвестно.
			-- Ждём, пока снимется, это ещё не замер
			local cleared = false
			while testRunning do
				if not testWait(15, "лимит ещё с прошлых блоков") then
					break
				end
				local ok, info = testAttempt()
				if ok == nil then
					stopReason = info or stopReason
					break
				elseif ok then
					burst = { os.clock() }
					testNote(("старый лимит снят, блок #1 прошёл: %s"):format(info.Name))
					cleared = true
					break
				end
			end
			if not cleared then
				break
			end
			continue
		end
		local count, first = #burst, burst[1]

		-- 2. Ждём, когда лимит снимется
		local step = 15
		if #measures > 0 then
			-- Второй раз: молча ждём почти до первого результата, чтобы лишние проверки
			-- не повлияли на лимит, и дальше проверяем часто
			local quiet = first + measures[1].fromFirst - 25 - os.clock()
			if quiet > 0 and not testWait(quiet, "точный замер, жду") then
				break
			end
			step = 5
		end
		local resetAt
		while testRunning do
			if not testWait(step, ("лимит, прошло %s"):format(fmt(os.clock() - first))) then
				break
			end
			local ok, info = testAttempt()
			if ok == nil then
				stopReason = info or stopReason
				break
			elseif ok then
				resetAt = os.clock()
				testNote(("лимит снят через %s после первого блока серии (%s после отказа), блок прошёл: %s"):format(
					fmt(resetAt - first), fmt(resetAt - hitAt), info.Name))
				break
			end
			if #measures == 0 and os.clock() - hitAt > 180 then
				step = 60 -- долго не снимается, проверяем реже
			end
			if os.clock() - hitAt > 1800 then
				stopReason = "за 30 минут лимит не снялся"
				testRunning = false
			end
		end
		if not resetAt then
			break
		end
		measures[#measures + 1] = { count = count, fromFirst = resetAt - first, fromLimit = resetAt - hitAt }
		burst = { resetAt } -- блок, которым проверили, первый в новой серии
	end

	if #measures == 0 then
		testNote("замер не закончен: " .. stopReason)
		return
	end
	local parts = {}
	for i, m in ipairs(measures) do
		parts[#parts + 1] = ("%d) %d блоков, снялся через %s"):format(i, m.count, fmt(m.fromFirst))
	end
	-- Точнее второй замер. Если его нет, берём первый
	local best = measures[#measures]
	limitInfo = { count = best.count, window = math.ceil(best.fromFirst) }
	pcall(writefile, "limit.txt", ("count=%d\nwindow=%d\n"):format(limitInfo.count, limitInfo.window))
	local verdict = ""
	if #measures >= 2 then
		local diff = math.abs(measures[2].fromFirst - measures[1].fromFirst)
		verdict = diff <= 25 and ", замеры сходятся" or (", замеры расходятся на %d с"):format(diff)
	else
		verdict = ", только один замер: " .. stopReason
	end
	testNote("замеры: " .. table.concat(parts, "; "))
	testNote(("ИТОГ: %d блока подряд, снимается через %s после первого%s"):format(
		limitInfo.count, fmt(limitInfo.window), verdict))
end

-- Старт/Стоп автоматического режима
local function updateAutoButton()
	autoButton.Text = autoBlock and "⏸ Стоп" or "▶ Старт"
	autoButton.BackgroundColor3 = autoBlock and Color3.fromRGB(170, 60, 60) or Color3.fromRGB(50, 140, 70)
end

autoButton.Activated:Connect(function()
	autoBlock = not autoBlock
	if not autoBlock then
		-- Остановили: ещё не начатые авто-блоки отменяем, поставленные вручную остаются
		for player, item in pairs(queue) do
			if item.auto then
				queue[player] = nil
			end
		end
		updateTitle()
	end
	updateAutoButton()
end)

local function addRow(player)
	if rows[player] then
		return
	end
	local isMe = player == Players.LocalPlayer
	local row = new("Frame", {
		Name = player.Name,
		Size = UDim2.new(1, -10, 0, 80),
		BackgroundColor3 = isMe and Color3.fromRGB(40, 55, 85) or Color3.fromRGB(40, 40, 50),
		Parent = list,
	})
	new("UICorner", { CornerRadius = UDim.new(0, 8), Parent = row })
	new("UIPadding", {
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		Parent = row,
	})
	local stroke = new("UIStroke", { Thickness = 2, Enabled = false, Parent = row })

	local name = "@" .. player.Name -- только юзернейм, дисплейное не нужно
	local nameLabel = label({
		Size = UDim2.new(1, -200, 0, 22),
		Font = Enum.Font.GothamBold,
		Text = name,
		TextSize = 18,
		TextColor3 = Color3.new(1, 1, 1),
		RichText = true, -- пометка «друг» другим цветом
		Parent = row,
	})
	local level = label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(200, 22),
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		TextColor3 = Color3.fromRGB(255, 200, 80),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = row,
	})
	local weapons = label({
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, isMe and 0 or -130, 0, 20), -- справа кнопка блока
		TextSize = 16,
		RichText = true, -- чтобы красить редкость цветом
		Parent = row,
	})
	local extra = label({
		Position = UDim2.fromOffset(0, 48),
		Size = UDim2.new(1, isMe and 0 or -130, 0, 20),
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		RichText = true, -- красим итог и предметы рюкзака по отдельности
		TextColor3 = Color3.fromRGB(150, 150, 165),
		Parent = row,
	})

	-- low: и нож, и пистолет опознаны и оба ниже годли (для авто-блока)
	local entry = { frame = row, high = false, low = false, blocked = false, addedAt = os.clock() }
	rows[player] = entry

	-- Себя заблокировать нельзя, у своей строки кнопки нет
	if not isMe then
		local blockButton = new("TextButton", {
			Name = "BlockButton",
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.fromScale(1, 1),
			Size = UDim2.fromOffset(120, 34),
			Font = Enum.Font.GothamBold,
			TextSize = 16,
			TextColor3 = Color3.new(1, 1, 1),
			Parent = row,
		})
		new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = blockButton })

		local statusUntil = 0 -- пока показываем результат, кнопку не перерисовываем

		-- Обычный вид кнопки: отсчёт до повтора, если игрок в очереди, иначе блок или разблок
		function entry.refreshButton()
			if os.clock() < statusUntil then
				return
			end
			local item = queue[player]
			if item then
				local left = math.max(0, math.ceil(item.nextTry - os.clock()))
				blockButton.Text = ("⏳ %d:%02d"):format(math.floor(left / 60), left % 60)
				blockButton.BackgroundColor3 = Color3.fromRGB(170, 110, 30)
			else
				blockButton.Text = entry.blocked and "Снять блок" or "🚫 Блок"
				blockButton.BackgroundColor3 = entry.blocked and Color3.fromRGB(70, 70, 82) or Color3.fromRGB(150, 50, 50)
			end
		end

		-- Временная надпись. Без seconds держится до следующей
		function entry.showStatus(text, seconds)
			blockButton.Text = text
			statusUntil = seconds and (os.clock() + seconds) or math.huge
			if seconds then
				task.delay(seconds, function()
					if blockButton.Parent then
						entry.refreshButton()
					end
				end)
			end
		end

		function entry.setBlocked(isBlocked)
			entry.blocked = isBlocked
			row.BackgroundTransparency = isBlocked and 0.6 or 0 -- заблокированные бледнее
			entry.refreshButton()
		end
		entry.setBlocked(blockedIds[player.UserId] == true)

		blockButton.Activated:Connect(function()
			-- Нажатие на того, кто ждёт в очереди, отменяет блок. Авто-блок его больше не ставит
			if queue[player] then
				queue[player] = nil
				autoSkip[player.UserId] = true
				updateTitle()
				entry.showStatus("Отменено", 1.5)
				return
			end
			-- Сняли блок вручную: авто-блок не должен заблокировать снова
			if entry.blocked then
				autoSkip[player.UserId] = true
			end
			if blockInProgress then
				-- Окно Roblox одно на всех: встаём в очередь сразу за текущим
				queue[player] = { block = not entry.blocked, nextTry = os.clock() }
				updateTitle()
				entry.refreshButton()
				return
			end
			runBlock(player, not entry.blocked)
		end)
	end

	local function refresh()
		local lvl = tonumber(attr(player, "Level", 0)) or 0
		local prestige = tonumber(attr(player, "Prestige", 0)) or 0
		local text = "Ур. " .. lvl
		if prestige > 0 then
			text ..= " · " .. roman(prestige) -- престиж римскими, как на лидерборде MM2
		end
		if attr(player, "Elite", false) then
			text ..= " · Elite"
		end
		level.Text = text

		local knife = player:GetAttribute("EquippedKnife")
		local gun = player:GetAttribute("EquippedGun")
		local knifeRarity, gunRarity = getRarity(knife), getRarity(gun)
		local knifeVal = itemValue(knife, knifeRarity, "knife")
		local gunVal = itemValue(gun, gunRarity, "gun")
		weapons.Text = "Нож: " .. itemText(knife, knifeRarity, knifeVal)
			.. "     Пистолет: " .. itemText(gun, gunRarity, gunVal)
		-- Нижняя строка: итог рюкзака + топ предметов с ценами. Пока грузится — сумма надетого
		local equippedSum = (knifeVal and knifeVal.v or 0) + (gunVal and gunVal.v or 0)
		if entry.invItems then
			if #entry.invItems == 0 then
				extra.Text = '🎒 <font color="#9AA0AA">годли+ нет</font>'
			else
				local parts = { ('🎒 <font color="#%s"><b>%s</b></font>'):format(
					valueColor(entry.invValue):ToHex(), fmtValue(entry.invValue)) }
				for i = 1, math.min(3, #entry.invItems) do
					local it = entry.invItems[i]
					local qty = it.qty > 1 and ("×" .. it.qty) or ""
					local valStr = it.v and (' <font color="#%s">%s</font>'):format(
						valueColor(it.v):ToHex(), fmtValue(it.v)) or ""
					parts[#parts + 1] = ('<font color="#%s">%s</font>%s%s'):format(
						variedColor(it.rarity, it.id):ToHex(), it.id, valStr, qty)
				end
				extra.Text = table.concat(parts, "  ")
			end
		elseif equippedSum > 0 then
			extra.Text = ('💰 Надето: <font color="#%s">%s</font>'):format(
				valueColor(equippedSum):ToHex(), fmtValue(equippedSum))
		else
			extra.Text = invRemote and "🎒 ..." or ""
		end

		local best = (isHigh(knifeRarity) and knifeRarity) or (isHigh(gunRarity) and gunRarity) or nil
		entry.high = best ~= nil
		-- Если хоть один предмет не опознан (ещё не загрузился или нет в базе), не трогаем
		entry.low = knifeRarity ~= nil and gunRarity ~= nil and not entry.high
		stroke.Enabled = entry.high
		if best then
			stroke.Color = rarityColor(best)
		end
		-- Сортировка: у кого дороже инвентарь, тот выше (пока рюкзак не загружен — по надетому).
		-- При равной цене — по прокачке (престиж важнее уровня). Цена режется до 2M,
		-- чтобы ключ влез в LayoutOrder (целое число).
		local bestVal = entry.invValue or equippedSum
		if entry.high and bestVal == 0 then
			bestVal = 1 -- годли без цены на сайте: держим чуть выше обычных
		end
		entry.value = bestVal
		local vTerm = math.min(math.floor(bestVal), 2000000)
		local lvlTerm = math.min(prestige * 1000 + lvl, 999)
		row.LayoutOrder = -(vTerm * 1000 + lvlTerm)

		-- Данные для экспорта в exe на ПК (та же панель, но строками)
		entry.export = {
			name = name,
			level = text,
			high = entry.high,
			knifeId = knife, knifeRarity = knifeRarity, knifeVal = knifeVal and knifeVal.v,
			gunId = gun, gunRarity = gunRarity, gunVal = gunVal and gunVal.v,
		}
		updateTitle()
	end

	entry.refresh = refresh
	refresh()
	table.insert(connections, player.AttributeChanged:Connect(refresh))
	-- Ставим в очередь на подсчёт рюкзака
	if invRemote then
		table.insert(invQueue, player)
	end
end

local function removeRow(player)
	local entry = rows[player]
	if entry then
		entry.frame:Destroy()
		rows[player] = nil
	end
	-- Вышел с сервера — забываем ручные решения по нему. Если он зайдёт снова,
	-- авто-блок оценит его заново и заблокирует, а не будет помнить старую разблокировку
	queue[player] = nil
	-- Забываем РУЧНОЕ решение «не блокировать» — чтобы при повторном входе автоблок сработал снова
	autoSkip[player.UserId] = nil
	friendCache[player.UserId] = nil -- дружбу тоже перепроверим при повторном входе
	-- serverUnblocked НЕ сбрасываем: если сервер сказал «блока нет», это верно и после перезахода,
	-- иначе залипший список Roblox снова пометил бы его заблокированным и автоблок бы его пропустил
	updateTitle()
end

for _, player in ipairs(Players:GetPlayers()) do
	addRow(player)
end
table.insert(connections, Players.PlayerAdded:Connect(addRow))
table.insert(connections, Players.PlayerRemoving:Connect(removeRow))

-- Авто-блок: ставит в очередь всех, у кого и нож, и пистолет ниже годли.
-- Только что зашедших 10 с не трогаем: пока MM2 грузит их данные, могут висеть стандартные скины
-- Годли+ нигде нет: ни надето, ни в рюкзаке. Если рюкзак ещё не проверен (invItems == nil)
-- и его вообще можно проверить — ждём, не блокуем. Нет доступа к рюкзаку — решаем по надетому
local function hasNoHigh(entry)
	if entry.high then
		return false -- надето годли+
	end
	if not invRemote then
		return true -- рюкзак недоступен, судим по надетому
	end
	if entry.invItems ~= nil then
		return #entry.invItems == 0 -- рюкзак проверен: годли+ в нём нет
	end
	-- рюкзак ещё не загрузился: ждём до 10 с, потом всё равно блокуем (по надетому)
	return (os.clock() - entry.addedAt) > 10
end

local function queueAutoBlocks()
	-- Блокируем всех, у кого и нож, и пистолет ниже годли — в том числе друзей
	-- (блок удалит из друзей, это ожидаемо). nextTry с запасом: если за это время игрок
	-- окажется годли+ (докрутился атрибут или подгрузился рюкзак), следующий тик очереди
	-- снимет его из очереди до блока
	for player, entry in pairs(rows) do
		if autoBlock and entry.low and hasNoHigh(entry) and not entry.blocked and not queue[player]
			and not autoSkip[player.UserId] and player ~= Players.LocalPlayer
			and os.clock() - entry.addedAt > 4 -- даём данным MM2 чуть прогрузиться
		then
			queue[player] = { block = true, nextTry = os.clock() + 1, auto = true }
			updateTitle()
		end
	end
end

-- Очередь: раз в секунду обновляет отсчёт на кнопках и сама запускает тех, чьё время пришло
local alive = true
task.spawn(function()
	local tick = 0
	while alive do
		task.wait(1)
		tick += 1
		-- Раз в ~6 с сверяем кнопки с реальным списком Roblox: если игрок на самом деле
		-- НЕ заблокирован, а кнопка висит «Снять блок», она сама вернётся в «🚫 Блок».
		-- Во время самого блока не трогаем, чтобы не мешать его проверке
		if tick % 6 == 0 and not blockInProgress and not testRunning then
			pcall(refreshBlocked)
		end
		for player, item in pairs(queue) do
			-- Вышел с сервера, уже в нужном состоянии (например, блокнули через меню Roblox)
			-- или, если блок авто, у него обнаружился годли+ (надел или нашёлся в рюкзаке)
			if player.Parent ~= Players or (blockedIds[player.UserId] == true) == item.block
				or (item.auto and not (rows[player] and rows[player].low and hasNoHigh(rows[player])))
			then
				queue[player] = nil
				updateTitle()
			end
		end
		if autoBlock then
			queueAutoBlocks()
		end
		for player, entry in pairs(rows) do
			if entry.refreshButton then
				entry.refreshButton()
			end
		end
		if not blockInProgress and not testRunning then -- во время замера очередь ждёт
			local due, dueItem
			for player, item in pairs(queue) do
				if os.clock() >= item.nextTry and (not dueItem or item.nextTry < dueItem.nextTry) then
					due, dueItem = player, item
				end
			end
			if due then
				runBlock(due, dueItem.block)
			end
		end
	end
end)

-- Подсчёт рюкзака игрока: берём инвентарь через GetFullInventory, суммируем цену владеемого.
-- Это ровно то, что открывает кнопка «Inventory» в игре, просто сразу с ценами
local function fetchInventory(player)
	if not invRemote then
		return
	end
	local ok, inv = pcall(function()
		return invRemote:InvokeServer(player)
	end)
	if not ok or type(inv) ~= "table" then
		return false -- не вышло (ошибка/лимит) — воркер попробует позже
	end
	local owned = type(inv.Weapons) == "table" and inv.Weapons.Owned
	if type(owned) ~= "table" then
		return true -- ответ есть, но оружия нет — считаем обработанным
	end
	local total, count = 0, 0
	local items = {} -- только годли и выше: { id, rarity, v (цена за штуку), qty }
	for id, qty in pairs(owned) do
		qty = tonumber(qty) or 1
		local rarity = getRarity(id)
		if isHigh(rarity) then -- всё ниже годли в счёт не идёт
			count += qty
			local e = ownedItemValue(id, rarity)
			local v = e and e.v or nil
			if v then
				total += v * qty
			end
			items[#items + 1] = { id = id, rarity = rarity, v = v, qty = qty }
		end
	end
	-- Дороже — выше; предметы без цены в конце
	table.sort(items, function(a, b)
		return (a.v or -1) > (b.v or -1)
	end)
	local entry = rows[player]
	if entry then
		entry.invValue = total
		entry.invCount = count
		entry.invItems = items
		if entry.refresh then
			entry.refresh()
		end
	end

	-- временный разбор для проверки
	local dbg = { ("%s: итог %d, предметов %d"):format(player.Name, total, count) }
	for _, it in ipairs(items) do
		dbg[#dbg + 1] = ("   %s [%s] x%d = %s"):format(
			it.id, tostring(it.rarity), it.qty, it.v and tostring(it.v) or "нет цены")
	end
	invDebug[player.Name] = table.concat(dbg, "\n")
	local all = {}
	for _, line in pairs(invDebug) do
		all[#all + 1] = line
	end
	pcall(writefile, "inv_debug.txt", table.concat(all, "\n\n"))
	return true
end

-- Фоновый воркер: дёргает рюкзаки по одному с паузой, чтобы не спамить сервер.
-- Если не вышло — ставим игрока обратно в очередь (до 4 попыток), чтобы рюкзак всё же загрузился
local invTries = {}
task.spawn(function()
	while alive do
		local player = table.remove(invQueue, 1)
		if player and player.Parent == Players and rows[player] and not (rows[player].invItems) then
			local ok = fetchInventory(player)
			if ok == false then
				invTries[player] = (invTries[player] or 0) + 1
				if invTries[player] < 4 then
					table.insert(invQueue, player) -- попробуем ещё раз позже
				end
				task.wait(2)
			else
				task.wait(0.5)
			end
		else
			task.wait(0.4)
		end
	end
end)

print("[Ридер] ID оператора для exe:", operatorId)

-- Один предмет в строку экспорта: "id:редкость:цена:assetId" (пустые поля допустимы)
local function expItem(id, rarity, v)
	return ("%s:%s:%s:%s"):format(
		tostring(id or ""), tostring(rarity or ""), v and tostring(v) or "", itemAsset(id) or "")
end

local function exportPanel()
	-- Перечитываем код оператора: exe мог сгенерировать новый (кнопка ⟳) и записать в файл.
	-- Тогда сразу начинаем писать панель под новым кодом, без перезапуска ридера.
	pcall(function()
		if isfile and isfile("operator_id.txt") then
			local cur = readfile("operator_id.txt"):gsub("%s", "")
			if #cur >= 3 and cur ~= operatorId then
				operatorId = cur
			end
		end
	end)
	local list = {}
	for _, entry in pairs(rows) do
		if entry.export then
			list[#list + 1] = entry
		end
	end
	table.sort(list, function(a, b)
		return (a.value or 0) > (b.value or 0)
	end)
	-- Шапка: PANEL, число игроков, ID, время
	local lines = { ("PANEL\t%d\t%s\t%s"):format(#list, operatorId, os.date("%H:%M:%S")) }
	for _, entry in ipairs(list) do
		local ex = entry.export
		-- Рюкзак без надетых ножа/пистолета: они уже в строке оружия, иначе в exe каждый вылезал дважды
		local items = {}
		if entry.invItems then
			for _, it in ipairs(entry.invItems) do
				if #items >= 6 then
					break
				end
				if it.id ~= ex.knifeId and it.id ~= ex.gunId then
					items[#items + 1] = expItem(it.id, it.rarity, it.v)
				end
			end
		end
		-- Поля через таб: имя, уровень, годли+(0/1), блок(0/1), нож, пистолет, итог рюкзака, топ-предметы
		lines[#lines + 1] = table.concat({
			ex.name, ex.level,
			ex.high and "1" or "0", entry.blocked and "1" or "0",
			expItem(ex.knifeId, ex.knifeRarity, ex.knifeVal),
			expItem(ex.gunId, ex.gunRarity, ex.gunVal),
			entry.invValue ~= nil and tostring(entry.invValue) or "",
			table.concat(items, ";"),
		}, "\t")
	end
	pcall(writefile, "panel_" .. operatorId .. ".txt", table.concat(lines, "\n"))
end

task.spawn(function()
	while alive do
		pcall(exportPanel)
		task.wait(1.5)
	end
end)

-- Анти-АФК: Roblox выкидывает после 20 минут без ввода.
-- 1) Когда игра считает игрока простаивающим (событие Idled), жмём «виртуальную» кнопку —
--    таймер простоя сбрасывается. От кика спасает именно это.
-- 2) Раз в ANTI_AFK_EVERY секунд, если сам не ходил, персонаж делает шаг туда и обратно.
local ANTI_AFK_EVERY = 5
local ANTI_AFK_STEP = 2.5 -- длина шага, studs
local VirtualUser = game:GetService("VirtualUser")
table.insert(connections, Players.LocalPlayer.Idled:Connect(function()
	pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new())
	end)
	print("[Ридер] анти-АФК: сбросил таймер простоя")
end))

task.spawn(function()
	local lastMove = os.clock()
	while alive do
		task.wait(1)
		local character = Players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (humanoid and root) or humanoid.Health <= 0 then
			lastMove = os.clock() -- персонажа нет (респавн, между раундами) — ждём
		elseif humanoid.MoveDirection.Magnitude > 0.1 then
			lastMove = os.clock() -- игрок ходит сам — не мешаем
		elseif os.clock() - lastMove >= ANTI_AFK_EVERY then
			lastMove = os.clock()
			local start = root.Position
			pcall(function()
				humanoid:MoveTo(start + root.CFrame.LookVector * ANTI_AFK_STEP)
				task.wait(0.7)
				humanoid:MoveTo(start)
			end)
			print("[Ридер] анти-АФК: шаг туда-обратно")
		end
	end
end)
print("[Ридер] анти-АФК включён: шаг раз в", ANTI_AFK_EVERY, "с")

-- При повторном запуске старое окно уничтожается, отключаем и его подписки и очередь
gui.Destroying:Connect(function()
	alive = false
	testRunning = false
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
end)

closeButton.Activated:Connect(function()
	setOpen(false)
end)
openButton.Activated:Connect(function()
	setOpen(true)
	refreshBlocked() -- вдруг кого-то блокнули через меню Roblox
end)

-- Куда повесить GUI: в Delta это скрытая папка gethui() или CoreGui.
-- В обычном LocalScript туда нельзя, поэтому остаётся PlayerGui.
local parents = {
	function() return gethui() end,
	function() return game:GetService("CoreGui") end,
	function() return Players.LocalPlayer:WaitForChild("PlayerGui") end,
}
for _, getParent in ipairs(parents) do
	if pcall(function() gui.Parent = getParent() end) and gui.Parent then
		break
	end
end

env.ReaderGui = gui
setOpen(true)

-- Отчёт для проверки: какую редкость нашли у надетых скинов
local report = { "таблиц в базе: " .. #itemTables }
for _, player in ipairs(Players:GetPlayers()) do
	for _, slot in ipairs({ "EquippedKnife", "EquippedGun" }) do
		local id = player:GetAttribute(slot)
		report[#report + 1] = ("%s %s: %s -> %s"):format(player.Name, slot, tostring(id), tostring(getRarity(id)))
	end
end
pcall(writefile, "reader_log.txt", table.concat(report, "\n"))
print("[Ридер] игроков:", #Players:GetPlayers(), "таблиц в базе:", #itemTables)
