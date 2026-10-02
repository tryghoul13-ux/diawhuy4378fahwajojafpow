local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

setthreadidentity(2)
local ProfileData = require(game.ReplicatedStorage.Modules.ProfileData)
local InventoryModule = require(game.ReplicatedStorage.Modules.InventoryModule)
local ItemModule = require(game.ReplicatedStorage.Modules.ItemModule)
local Sync = require(game.ReplicatedStorage.Database.Sync)
local ItemPopupService = require(game.ReplicatedStorage.ClientServices.ItemPopupService)
setthreadidentity(8)

local TradeRemotes = game.ReplicatedStorage.Trade

local TradeGUI = game.Players.LocalPlayer.PlayerGui.TradeGUI
local TheirOffer = TradeGUI.Container.Trade.TheirOffer
local YourOffer = TradeGUI.Container.Trade.YourOffer

local SearchTextSignal
local TradeInventory

local functions = {}

local Config = {
	["item"] = "",
	["in_trade"] = false,
	["player2"] = nil
}

-- All rare weapons list for spawning (correct database names - removed invalid ones)
local rareWeaponsList = {
	-- ANCIENTS (removed Batwing)
    "ElderwoodScythe", "Icewing", "Logchopper", "Hallowscythe", "Harvester",
	"Icebreaker", "IceHammer", "VampireAxe", "SwirlyAxe", "TravelerAxe", "Gingerscythe",
	"Gingerscope", "Icepiercer", "Synthwave",
	
	-- CHROMAS
	"SeerChroma", "GemstoneChroma", "DeathshardChroma", "FangChroma", "SawChroma",
	"SlasherChroma", "TidesChroma", "HeatChroma", "LugerChroma", "SharkChroma",
	"LaserChroma", "ChromaDarkbringer", "ChromaLightbringer", "BonebladeChroma",
	"GingerbladeChroma", "CandleflameChroma", "ElderwoodKnifeChroma", "Gingermint_KChroma",
	"TreeGun2023Chroma", "TreeKnife2023Chroma", "ConstellationChroma", "BaubleChroma",
	"BlizzardChroma", "RaygunChroma", "SnowDaggerChroma", "SunsetKnifeChroma", "SunsetGunChroma",
	"SwirlyGunChroma", "VampireGunChroma", "WatergunChroma", "TravelerGunChroma",
    "UFOKnifeChroma", "SnowstormChroma", "SnowcannonChroma",
	"BaubleKnifeChroma",
	
	-- GODLY KNIVES
	"TheSeer", "Gemstone", "Deathshard", "Fang", "Saw", "Slasher", "Tides", "Heat",
	"Eternal", "Eternal2", "Eternal3", "Eternal4", "EternalCane",
	"BlueSeer", "RedSeer", "PurpleSeer", "OrangeSeer", "YellowSeer",
	"Clockwork", "Pixel", "Virtual", "BigKill", "Spider", "Candy", "Chill", "Handsaw",
	"Xmas", "HallowsBlade", "IceDragon", "Flames", "BattleAxe",
	"Snowflake", "IceShard", "Boneblade", "Pumpking", "BattleAxe2", "Gingerblade",
	"WintersEdge", "Frostsaber", "Nightblade", "Ghostblade", "Frostbite", "VampiresEdge",
	"Cookieblade", "Peppermint", "Bioblade", "Heartblade", "Eggblade", "Prismatic", "Nebula",
	"Candleflame", "SwirlyBlade", "Iceflake", "Plasmablade", "ElderwoodKnife",
	"Phantom", "Sakura_K", "Rainbow", "Waves_K", "Darksword", "TreeKnife2023",
	"FlowerwoodKnife", "Bloom", "SunsetKnife", "XenoKnife", "Celestial",
	"SnowDagger", "Blizzard", "UFOKnife", "BaubleKnife",
	
	-- GODLY GUNS (removed Gingermint_G, Blossom_G, Ocean_G, Pearl_G - they don't exist)
	"Darkbringer", "Lightbringer", "Luger", "Shark", "Laser", "Lugercane", "Blaster",
	"Amerilaser", "Sugar", "GreenLuger", "RedLuger", "ElderwoodGun", "Minty",
	"GingerLuger", "Jinglegun", "Iceblaster", "Hallowgun", "SwirlyGun", "Icebeam",
	"Plasmabeam", "Makeshift", "Spectre2022", "RainbowGun",
	"Darkshot", "TravelerGun", "TreeGun2023", "FlowerwoodGun", "Watergun",
	"VampireGun", "Constellation", "Bauble", "Flora",
	"SunsetGun", "Raygun", "XenoGun", "Snowcannon", "Snowstorm"
}

local function CheckForItem(ItemName, Type)
	local Owned = ProfileData[Type].Owned
	for Index, Value in pairs(Owned) do
		if Index == ItemName then
			return true, Value
		end
		if Value == ItemName then
			return true, 1
		end
	end
	return false
end

local function CheckForItem2(ItemName, Type)
	return true, math.huge
end

local v18 = {}
local function v22(v19)
	for _, v21 in pairs(v19:GetChildren()) do
		if v21:IsA("Frame") then
			v21.Visible = false
			if v18[v21] then
				v18[v21]:Disconnect()
				v18[v21] = nil
			end
		end
	end
end

local TradeTable = {
	["LastOffer"] = os.time(),
	["Locked"] = false,
	["Player1"] = {
		["Player"] = game.Players.LocalPlayer,
		["Accepted"] = false,
		["Offer"] = {}
	},
	["Player2"] = {
		["Player"] = "kerog138",
		["Accepted"] = false,
		["Offer"] = {}
	},
}

-- Spawn item function (NO RESET, NO POPUP)
local function SpawnItem(ItemName, Amount, ItemType)
	Amount = Amount or 1
	ItemType = ItemType or "Weapons"
	pcall(function()
		if ProfileData[ItemType].Owned[ItemName] == nil then
			ProfileData[ItemType].Owned[ItemName] = Amount
		else
			ProfileData[ItemType].Owned[ItemName] = ProfileData[ItemType].Owned[ItemName] + Amount
		end
		game.ReplicatedStorage.Remotes.Inventory.InventoryDataChanged:Fire()
	end)
end

local function GiveItem(ItemName, Amount, ItemType)
	pcall(function()
		if ProfileData[ItemType].Owned[ItemName] == nil then
			ProfileData[ItemType].Owned[ItemName] = Amount
		else
			ProfileData[ItemType].Owned[ItemName] = ProfileData[ItemType].Owned[ItemName] + Amount
		end
		ItemPopupService.ItemReceived:Fire(ItemName, ItemType)
		game.ReplicatedStorage.Remotes.Inventory.InventoryDataChanged:Fire()
	end)
end

local function RemoveItem(ItemName, Amount, ItemType)
	pcall(function()
		local owned = ProfileData[ItemType].Owned[ItemName]
		if not owned then
			print("doesn't have the item")
			return
		end
		if owned - Amount > 0 then
			ProfileData[ItemType].Owned[ItemName] = owned - Amount
		else
			ProfileData[ItemType].Owned[ItemName] = nil
		end
		game.ReplicatedStorage.Remotes.Inventory.InventoryDataChanged:Fire()
	end)
end

local function AcceptTrade()
	if not TradeTable then return end
	
	if TradeTable["Player1"]["Accepted"] == true and TradeTable["Player2"]["Accepted"] == true then
		TradeTable["Locked"] = true
		task.wait(0.2)

		if TradeTable["Player1"]["Offer"] and next(TradeTable["Player1"]["Offer"]) ~= nil then
			for _, item in pairs(TradeTable["Player1"]["Offer"]) do
				local itemName = item[1]
				local amount = item[2]
				local itemType = item[3]
				pcall(function()
					RemoveItem(itemName, amount, itemType)
				end)
			end
		end

		if TradeTable["Player2"]["Offer"] and next(TradeTable["Player2"]["Offer"]) ~= nil then
			for _, item in pairs(TradeTable["Player2"]["Offer"]) do
				local itemName = item[1]
				local amount = item[2]
				local itemType = item[3]
				pcall(function()
					GiveItem(itemName, amount, itemType)
				end)
				pcall(function()
					_G.NewItem(itemName, "You Got...", nil, itemType, amount)
				end)
			end
		end

		pcall(function()
			TradeGUI.Enabled = false
		end)
		
		local partner = "kerog138"
		if TradeTable.Player2 and TradeTable.Player2.Player then
			partner = TradeTable.Player2.Player
		end
		
		TradeTable = {
			["LastOffer"] = os.time(),
			["Locked"] = false,
			["Player1"] = {
				["Player"] = game.Players.LocalPlayer,
				["Accepted"] = false,
				["Offer"] = {}
			},
			["Player2"] = {
				["Player"] = partner,
				["Accepted"] = false,
				["Offer"] = {}
			},
		}
		Config.in_trade = false
	end
end

local v84 = false

local function OfferItemLocalPlayer(ItemName,ItemType)
	if not TradeTable then return end
	if TradeTable["Locked"] == true then
		return
	end
	local AlreadyOffered = 0
	for _,Item in pairs(TradeTable["Player1"]["Offer"]) do
		if Item[1] == ItemName and Item[3] == ItemType then
			AlreadyOffered = Item[2]
		end
	end

	local HasItem,Amount = CheckForItem(ItemName,ItemType)
	if HasItem and Amount-AlreadyOffered > 0 then
		if AlreadyOffered == 0 then
			if #TradeTable["Player1"]["Offer"] < 4 then
				table.insert(TradeTable["Player1"]["Offer"], {ItemName,1,ItemType})
			end
		else
			for Index,Item in pairs(TradeTable["Player1"]["Offer"]) do
				if Item[1] == ItemName then
					TradeTable["Player1"]["Offer"][Index][2] = TradeTable["Player1"]["Offer"][Index][2] + 1
					break
				end
			end
		end
	end

	TradeTable["LastOffer"] = os.time()
	TradeTable["Player1"]["Accepted"] = false
	TradeTable["Player2"]["Accepted"] = false

	pcall(function()
		functions.UpdateTrade()
	end)
end

local function RemoveItemLocalPlayer(ItemName, ItemType)
	if not TradeTable then return end
	if TradeTable["Locked"] == true then
		return
	end

	if TradeTable["Player1"]["Accepted"] then
		return
	end
	TradeTable["LastOffer"] = os.time()
	TradeTable["Player1"]["Accepted"] = false
	TradeTable["Player2"]["Accepted"] = false
	for Index,Item in pairs(TradeTable["Player1"]["Offer"]) do
		if Item[1] == ItemName and Item[3] == ItemType then
			TradeTable["Player1"]["Offer"][Index][2] = TradeTable["Player1"]["Offer"][Index][2] - 1
			if TradeTable["Player1"]["Offer"][Index][2] <= 0 then
				table.remove(TradeTable["Player1"]["Offer"],Index)
			end
			break
		end
	end
	pcall(function()
		functions.UpdateTrade()
	end)
end

-- Helper function to find item in database (exact match)
local function FindItemInDatabase(itemName, itemType)
	if not Sync[itemType] then return nil end
	
	-- Try exact match
	if Sync[itemType][itemName] then
		return itemName, Sync[itemType][itemName]
	end
	
	return nil, nil
end


local function OfferItemAnotherPlayer(ItemName, ItemType)
	-- Safety checks
	if not ItemName or ItemName == "" then
		return false
	end
	
	if not TradeTable then
		return false
	end
	
	if TradeTable["Locked"] == true then
		return false
	end
	
	-- Check if already at max 4 items
	if #TradeTable["Player2"]["Offer"] >= 4 then
		-- Check if we're adding to existing item
		local foundExisting = false
		for _, Item in pairs(TradeTable["Player2"]["Offer"]) do
			if Item[1] == ItemName and Item[3] == ItemType then
				foundExisting = true
				break
			end
		end
		if not foundExisting then
			return false -- Can't add more than 4 different items
		end
	end

	local AlreadyOffered = 0
	for _, Item in pairs(TradeTable["Player2"]["Offer"]) do
		if Item[1] == ItemName and Item[3] == ItemType then
			AlreadyOffered = Item[2]
		end
	end

	if AlreadyOffered == 0 then
		-- Add new item
		table.insert(TradeTable["Player2"]["Offer"], {ItemName, 1, ItemType})
	else
		-- Increase count of existing item
		for Index, Item in pairs(TradeTable["Player2"]["Offer"]) do
			if Item[1] == ItemName and Item[3] == ItemType then
				TradeTable["Player2"]["Offer"][Index][2] = TradeTable["Player2"]["Offer"][Index][2] + 1
				break
			end
		end
	end

	TradeTable["LastOffer"] = os.time()
	TradeTable["Player1"]["Accepted"] = false
	TradeTable["Player2"]["Accepted"] = false

	pcall(function()
		functions.UpdateTrade()
	end)
	
	return true
end

local function RemoveItemAnotherPlayer()
	if not TradeTable then return end
	if not TradeTable["Player2"] then return end
	if not TradeTable["Player2"]["Offer"] then return end
	
	if #TradeTable["Player2"]["Offer"] > 0 then
		if TradeTable["Player2"]["Accepted"] then
			return
		end

		local LastIndex = #TradeTable["Player2"]["Offer"]

		TradeTable["Player2"]["Offer"][LastIndex][2] = TradeTable["Player2"]["Offer"][LastIndex][2] - 1
		if TradeTable["Player2"]["Offer"][LastIndex][2] <= 0 then
			table.remove(TradeTable["Player2"]["Offer"], LastIndex)
		end

		TradeTable["LastOffer"] = os.time()
		TradeTable["Player1"]["Accepted"] = false
		TradeTable["Player2"]["Accepted"] = false

		pcall(function()
			functions.UpdateTrade()
		end)
	end
end

local function v34(v23, v24)
	for v25, v26 in v24 do
		local ItemID = v26[1] or v26.ItemID
		local Amount = v26[2] or v26.Amount
		local ItemType = v26[3] or v26.ItemType

		local v33 = v23.Container["NewItem" .. v25]
		if not v33 then
			continue
		end

		-- Try direct database lookup
		local success = pcall(function()
			if Sync[ItemType] and Sync[ItemType][ItemID] then
				local v30 = {}

				for v31, v32 in pairs(Sync[ItemType][ItemID]) do
					v30[v31] = v32
				end

				v30.DataType = ItemType
				v30.Amount = Amount

				v30.DataType = ItemType
v30.Amount = Amount

-- Use the same display name as the inventory
local displayName = ItemID

pcall(function()
	local inventoryData = Sync[ItemType][ItemID]

	if inventoryData then
		if inventoryData.ItemName then
			displayName = inventoryData.ItemName
		elseif inventoryData.Name then
			displayName = inventoryData.Name
		end
	end
end)

local nameFixes = {
	["SunsetKnife"] = "Sunset",
	["SunsetGun"] = "Sunrise",
	["TravelerAxe"] = "Traveler's Axe",
	["TravelerGun"] = "Traveler's Gun",
	["SwirlyGun"] = "Swirly Gun",
	["SwirlyAxe"] = "Swirly Axe",
	["IceHammer"] = "Ice Hammer",
	["ElderwoodKnife"] = "Elderwood Knife",
	["ElderwoodGun"] = "Elderwood Gun",
	["TreeKnife2023"] = "Evergreen",
	["TreeGun2023"] = "Evergun",
}

if nameFixes[ItemID] then
	displayName = nameFixes[ItemID]
end

v30.ItemName = displayName
v30.Name = displayName

ItemModule.DisplayItem(v33, v30)

-- Fix Chroma + Fx tag layering
pcall(function()
	local container = v33:FindFirstChild("Container")

	if container then
		for _, obj in pairs(container:GetDescendants()) do
			if obj:IsA("TextLabel") or obj:IsA("ImageLabel") then
				if string.find(string.lower(obj.Name), "Fx") then
					obj.ZIndex = 10
				elseif string.find(string.lower(obj.Name), "Chroma") then
					obj.ZIndex = 9
				end
			end
		end
	end
end)
				ItemModule.DisplayItem(v33, v30)
			end
		end)

		-- Setup remove button
		pcall(function()
			if v18[v33] then
				v18[v33]:Disconnect()
			end

			if v33.Container and v33.Container:FindFirstChild("ActionButton") then
				v18[v33] = v33.Container.ActionButton.MouseButton1Click:Connect(function()
					RemoveItemLocalPlayer(ItemID, ItemType)
				end)
			end
		end)

		v33.Visible = true
	end
end

local v85 = 6
local function ResetCooldown(arg1)
	if arg1 then
		TradeGUI.Container.Trade.Actions.Accept.Cooldown.Visible = false
		v85 = 0
		v84 = false
		return
	else
		TradeGUI.Container.Trade.Actions.Accept.Cooldown.Visible = true
		v85 = 6
		TradeGUI.Container.Trade.Actions.Accept.Cooldown.Title.Text = " Please wait (" .. v85 .. ") before accepting."
		if not v84 then
			TradeGUI.Container.Trade.Actions.Accept.Cooldown.Visible = true
			v84 = true
			repeat
				wait(1)
				v85 = v85 - 1
				TradeGUI.Container.Trade.Actions.Accept.Cooldown.Title.Text = " Please wait (" .. v85 .. ") before accepting."
			until v85 <= 0
			v84 = false
			TradeGUI.Container.Trade.Actions.Accept.Cooldown.Visible = false
			return
		else
			v85 = 6
			return
		end
	end
end

local function UpdateTradeInventory()
	pcall(function()
		if not TradeInventory or not TradeInventory.Data then return end
		local l_Offer_2 = TradeTable["Player1"].Offer
		for v63, v64 in pairs(TradeInventory.Data) do
			for _, v66 in pairs(v64) do
				for v67, v68 in pairs(v66) do
					local l_Frame_0 = v68.Frame
					local l_Amount_0 = v68.Amount
					for _, v72 in pairs(l_Offer_2) do
						local v73 = v72[1] or v72.ItemID
						local v74 = v72[2] or v72.Amount
						local v75 = v72[3] or v72.ItemType
						if v73 == v67 and v75 == v63 then
							l_Amount_0 = l_Amount_0 - v74
						end
					end
					if l_Amount_0 == 1 then
						l_Frame_0.Container.Amount.Text = ""
						l_Frame_0.Visible = true
					elseif l_Amount_0 > 1 then
						l_Frame_0.Container.Amount.Text = "x" .. l_Amount_0
						l_Frame_0.Visible = true
					elseif l_Amount_0 < 1 then
						l_Frame_0.Visible = false
					end
				end
			end
		end
	end)
end

local v35 = "Accept"
functions.UpdateTrade = function()
	pcall(function()
		local Offer1 = TradeTable.Player1.Offer
		local Offer2 = TradeTable.Player2.Offer

		v22(YourOffer.Container)
		v22(TheirOffer.Container)

		v34(YourOffer, Offer1)
		v34(TheirOffer, Offer2)

		v35 = "Accept"

		TradeGUI.Container.Trade.Actions.Accept.Confirm.Visible = false
		TradeGUI.Container.Trade.Actions.Accept.Cancel.Visible = false
		YourOffer.Accepted.Visible = false
		TheirOffer.Accepted.Visible = false 

		local l_AddItem_0 = TradeGUI.Container.Trade.Actions.Accept.AddItem
		local v44 = false
		if #Offer1 < 1 then
			v44 = #Offer2 < 1
		end
		l_AddItem_0.Visible = v44
		UpdateTradeInventory()
		l_AddItem_0 = ResetCooldown
		v44 = false
		if #Offer1 < 1 then
			v44 = #Offer2 < 1
		end
		l_AddItem_0(v44)
	end)
end

function DeclineTrade()
	pcall(function()
		TradeGUI.Enabled = false
	end)
	
	local partner = "m0_3a"
	if TradeTable and TradeTable.Player2 and TradeTable.Player2.Player then
		partner = TradeTable.Player2.Player
	end
	
	TradeTable = {
		["LastOffer"] = os.time(),
		["Locked"] = false,
		["Player1"] = {
			["Player"] = game.Players.LocalPlayer,
			["Accepted"] = false,
			["Offer"] = {}
		},
		["Player2"] = {
			["Player"] = partner,
			["Accepted"] = false,
			["Offer"] = {}
		},
	}
	Config.in_trade = false
	
	pcall(function()
		UnConnections()
	end)
end

local v87 = time()

local Connections = {}

function SetupConnections(v76)
	pcall(function()
		if v76 and v76.Data then
			for v77, v78 in pairs(v76.Data) do
				for _, v80 in pairs(v78) do
					for v81, v82 in pairs(v80) do
						local l_Frame_1 = v82.Frame
						if l_Frame_1 then
							Connections.Connection0 = l_Frame_1.Container.ActionButton.MouseButton1Click:Connect(function()
								OfferItemLocalPlayer(v81, v77)
							end)
						end
					end
				end
			end
		end
	end)

	pcall(function()
		Connections.Connection1 = TradeGUI.Container.Trade.Actions.Accept.ActionButton.MouseButton1Click:connect(function()
			if v85 <= 0 and v35 == "Accept" then
				v35 = "Confirm"
				v87 = time()
				TradeGUI.Container.Trade.Actions.Accept.Confirm.Visible = true
			end
		end)
	end)
	
	pcall(function()
		Connections.Connection2 = TradeGUI.Container.Trade.Actions.Accept.Confirm.ActionButton.MouseButton1Click:connect(function()
			if v85 <= 0 and time() - v87 >= 0.4 and v35 == "Confirm" then
				v35 = "Waiting"
				YourOffer.Accepted.Visible = true
				TradeGUI.Container.Trade.Actions.Accept.Cancel.Visible = true
				TradeTable["Player1"]["Accepted"] = true
				AcceptTrade()
			end
		end)
	end)
	
	pcall(function()
		Connections.Connection3 = TradeGUI.Container.Trade.Actions.Accept.Cancel.ActionButton.MouseButton1Click:connect(function()
			TradeTable["LastOffer"] = os.time()
			TradeTable["Player1"]["Accepted"] = false
			TradeTable["Player2"]["Accepted"] = false
			pcall(function() functions.UpdateTrade() end)
		end)
	end)
	
	pcall(function()
		Connections.Connection4 = TradeGUI.Container.Trade.Actions.Decline.ActionButton.MouseButton1Click:connect(function()
			DeclineTrade()
		end)
	end)
end

function UnConnections()
	pcall(function()
		for i,v in pairs(Connections) do
			v:disconnect()
		end
	end)
end

function StartTrade()
	if Config.in_trade == true then
		return
	end
	Config.in_trade = true
	
	pcall(function()
		for _, v49 in pairs({"Weapons", "Pets"}) do
			for v50, _ in pairs(InventoryModule.CreateBlankTradeInventoryTable()[v49]) do
				TradeGUI.Container.Items.Main:FindFirstChild(v49).Items.Container:FindFirstChild(v50).Container:ClearAllChildren()
			end
		end
	end)
	
	pcall(function()
		TradeInventory = InventoryModule.GenerateInventory(TradeGUI.Container.Items, ProfileData, "Trading")
	end)
	
	pcall(function()
		UnConnections()
	end)
	
	pcall(function()
		if TradeInventory then
			SetupConnections(TradeInventory)
		end
	end)

	pcall(function()
		functions.UpdateTrade(TradeTable)
	end)

	pcall(function()
		TheirOffer.Username.Text = "(" .. tostring(TradeTable.Player2.Player) .. ")"
	end)
	
	TradeGUI.Enabled = true

	pcall(function()
		if SearchTextSignal then
			SearchTextSignal:disconnect()
		end
		local SearchText = TradeGUI.Container.Items.Tabs.Search.Container.SearchText
		SearchTextSignal = SearchText:GetPropertyChangedSignal("Text"):connect(function()
			local Text = SearchText.Text
			Text = string.gsub(Text, "S", "")
			for _, v55 in pairs(TradeInventory.Data) do
				for _, v57 in pairs(v55.Current) do
					v57.Frame.Visible = string.find(string.lower(v57.Name), string.lower(Text))
					if v57.Frame.Parent.Parent:IsA("ScrollingFrame") then
						v57.Frame.Parent.Parent.CanvasPosition = Vector2.new(0, 0)
					else
						v57.Frame.Parent.Parent.Parent.Parent.CanvasPosition = Vector2.new(0, 0)
					end
				end
			end
		end)
	end)
end

TradeRemotes.StartTrade.OnClientEvent:Connect(function(arg1, arg2)
	DeclineTrade()
	for _, connection in pairs(getconnections(TradeRemotes.StartTrade)) do
		if connection.Function then
			connection.Function(arg1, arg2)
		end
	end
end)

local controlGui = Instance.new("ScreenGui")
controlGui.ResetOnSpawn = false
controlGui.DisplayOrder = 999999999
controlGui.Enabled = true
controlGui.Parent = game:GetService("CoreGui")

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 200, 0, 400)
mainFrame.Position = UDim2.new(0.5, -250, 0.5, -175)
mainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
mainFrame.BorderSizePixel = 0
mainFrame.ZIndex = 1
mainFrame.Parent = controlGui

local dragging, dragStart, startPos
mainFrame.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPos = mainFrame.Position
	end
end)
UserInputService.InputChanged:Connect(function(input)
	if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		local delta = input.Position - dragStart
		mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
	end
end)

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 8)
mainCorner.Parent = mainFrame

local mainStroke = Instance.new("UIStroke")
mainStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
mainStroke.Color = Color3.fromRGB(100, 100, 255)
mainStroke.Thickness = 2.5
mainStroke.Parent = mainFrame

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, 0, 0, 25)
titleLabel.Position = UDim2.new(0, 0, 0, 2)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "discord.gg/kR4Fbvhdqv"
titleLabel.Font = Enum.Font.FredokaOne
titleLabel.TextSize = 16
titleLabel.TextColor3 = Color3.fromRGB(240, 240, 255)
titleLabel.Parent = mainFrame

local titleStroke = Instance.new("UIStroke")
titleStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
titleStroke.Color = Color3.new(0, 0, 0)
titleStroke.Thickness = 1.0
titleStroke.Parent = titleLabel

local tabContainer = Instance.new("Frame")
tabContainer.Size = UDim2.new(0.94, 0, 0, 30)
tabContainer.Position = UDim2.new(0.03, 0, 0, 30)
tabContainer.BackgroundTransparency = 1
tabContainer.Parent = mainFrame

local tabs = {"Control", "Players", "Items", "Spawn"}
local currentTab = "Control"
local tabFrames = {}
local tabButtons = {}
local activeTabPulseTween = nil

function setActiveTab(tabName)
	if currentTab == tabName then return end

	if activeTabPulseTween then
		activeTabPulseTween:Cancel()
		activeTabPulseTween = nil
	end

	currentTab = tabName

	for name, data in pairs(tabButtons) do
		local isActive = name == tabName
		TweenService:Create(data.button, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			BackgroundColor3 = isActive and Color3.fromRGB(50, 50, 60) or Color3.fromRGB(40, 40, 50)
		}):Play()
		local targetColor = isActive and Color3.fromRGB(100, 100, 255) or Color3.fromRGB(80, 80, 80)
		local targetThickness = isActive and 1.5 or 1.0
		TweenService:Create(data.stroke, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Color = targetColor,
			Thickness = targetThickness
		}):Play()
		if isActive then
			local pulseInfo = TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
			activeTabPulseTween = TweenService:Create(data.stroke, pulseInfo, {
				Color = targetColor:Lerp(Color3.fromRGB(255, 255, 255), 0.25),
				Thickness = 2.0
			})
			activeTabPulseTween:Play()
		end
	end

	for name, frame in pairs(tabFrames) do
		frame.Visible = name == tabName
	end
end


for i, tabName in ipairs(tabs) do
	local tabButton = Instance.new("TextButton")
	tabButton.Size = UDim2.new(1/#tabs - 0.02, 0, 1, 0)
	tabButton.Position = UDim2.new((i - 1) * (1/#tabs), (i == 1) and 0 or 0, 0, 0)
	tabButton.BackgroundColor3 = i == 1 and Color3.fromRGB(50, 50, 60) or Color3.fromRGB(40, 40, 50)
	tabButton.BackgroundTransparency = 0.2
	tabButton.Text = tabName
	tabButton.Font = Enum.Font.FredokaOne
	tabButton.TextSize = 10
	tabButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	tabButton.Parent = tabContainer

	local tabCorner = Instance.new("UICorner")
	tabCorner.CornerRadius = UDim.new(0, 5)
	tabCorner.Parent = tabButton

	local tabStroke = Instance.new("UIStroke")
	tabStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	tabStroke.Color = i == 1 and Color3.fromRGB(100, 100, 255) or Color3.fromRGB(80, 80, 80)
	tabStroke.Thickness = i == 1 and 1.5 or 1.0
	tabStroke.Transparency = 0.3
	tabStroke.Parent = tabButton

	tabButtons[tabName] = {button = tabButton, stroke = tabStroke}

	local tabFrame = Instance.new("Frame")
	tabFrame.Size = UDim2.new(0.9, 0, 0, 280)
	tabFrame.Position = UDim2.new(0.05, 0, 0, 65)
	tabFrame.BackgroundTransparency = 1
	tabFrame.Visible = i == 1
	tabFrame.Parent = mainFrame
	
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 3)
	layout.Parent = tabFrame

	tabFrames[tabName] = tabFrame

	tabButton.MouseButton1Click:Connect(function()
		setActiveTab(tabName)
	end)
end

local controlFrame = tabFrames["Control"]
local playersFrame = tabFrames["Players"]
local itemsFrame = tabFrames["Items"]
local spawnFrame = tabFrames["Spawn"]

local function CreateSpace(Frame)
	local Space = Instance.new("Frame")
	Space.Size = UDim2.new(1, 0, 0, 8)
	Space.BackgroundTransparency = 1
	Space.Parent = Frame
end

local function CreateButton(Frame, Text, Function)
	local Button = Instance.new("TextButton")
	Button.Size = UDim2.new(1, 0, 0, 30)
	Button.BackgroundColor3 = Color3.fromRGB(100, 50, 150)
	Button.BackgroundTransparency = 0.2
	Button.Text = Text
	Button.Font = Enum.Font.FredokaOne
	Button.TextSize = 14
	Button.TextColor3 = Color3.fromRGB(255, 255, 255)
	Button.Parent = Frame

	local Corner = Instance.new("UICorner")
	Corner.CornerRadius = UDim.new(0, 5)
	Corner.Parent = Button

	local Stroke = Instance.new("UIStroke")
	Stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	Stroke.Color = Color3.fromRGB(200, 100, 255)
	Stroke.Thickness = 1.5
	Stroke.Transparency = 0.3
	Stroke.Parent = Button

	Button.MouseButton1Click:Connect(Function)
	
	return Button
end

local function CreateToggleButton(Frame, Text, Callback)
	local State = false

	local Button = Instance.new("TextButton")
	Button.Size = UDim2.new(1, 0, 0, 30)
	Button.BackgroundColor3 = Color3.fromRGB(100, 50, 150)
	Button.BackgroundTransparency = 0.2
	Button.Text = Text .. ": OFF"
	Button.Font = Enum.Font.FredokaOne
	Button.TextSize = 14
	Button.TextColor3 = Color3.fromRGB(255, 255, 255)
	Button.Parent = Frame

	local Corner = Instance.new("UICorner")
	Corner.CornerRadius = UDim.new(0, 5)
	Corner.Parent = Button

	local Stroke = Instance.new("UIStroke")
	Stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	Stroke.Color = Color3.fromRGB(200, 100, 255)
	Stroke.Thickness = 1.5
	Stroke.Transparency = 0.3
	Stroke.Parent = Button

	local OnColor = Color3.fromRGB(140, 70, 200)
	local OffColor = Color3.fromRGB(100, 50, 150)

	local function UpdateVisual()
		TweenService:Create(Button, TweenInfo.new(0.15), {
			BackgroundColor3 = State and OnColor or OffColor
		}):Play()
		Button.Text = Text .. (State and ": ON" or ": OFF")
	end

	Button.MouseButton1Click:Connect(function()
		State = not State
		UpdateVisual()
		Callback(State)
	end)

	return Button, function() return State end
end

local pulsationTweens = {}

function createSettingRow(labelText, defaultValue, parent)
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 35)
	row.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 1)
	layout.Parent = row

	local heading = Instance.new("TextLabel")
	heading.Size = UDim2.new(1, 0, 0, 15)
	heading.BackgroundTransparency = 1
	heading.Text = labelText
	heading.Font = Enum.Font.SourceSansSemibold
	heading.TextSize = 12
	heading.TextColor3 = Color3.fromRGB(180, 180, 180)
	heading.TextXAlignment = Enum.TextXAlignment.Left
	heading.Parent = row

	local box = Instance.new("TextBox")
	box.Size = UDim2.new(1, 0, 0, 25)
	box.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
	box.BackgroundTransparency = 0.2
	box.Text = defaultValue
	box.Font = Enum.Font.SourceSans
	box.TextSize = 14
	box.TextColor3 = Color3.fromRGB(255, 255, 255)
	box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Center
	box.Parent = row

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = box

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Color3.fromRGB(100, 100, 100)
	stroke.Thickness = 1.0
	stroke.Transparency = 0.5
	stroke.Parent = box

	box.Focused:Connect(function()
		if pulsationTweens[box] then
			pulsationTweens[box]:Cancel()
		end

		local pulseInfo = TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		pulsationTweens[box] = TweenService:Create(stroke, pulseInfo, {
			Color = Color3.fromRGB(100, 100, 255):Lerp(Color3.fromRGB(150, 150, 255), 0.5),
			Thickness = 1.5,
			Transparency = 0.2
		})
		pulsationTweens[box]:Play()
	end)

	box.FocusLost:Connect(function()
		if pulsationTweens[box] then
			pulsationTweens[box]:Cancel()
			pulsationTweens[box] = nil
		end

		TweenService:Create(stroke, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
			Color = Color3.fromRGB(100, 100, 100),
			Thickness = 1.0,
			Transparency = 0.5
		}):Play()
	end)

	return box, stroke, heading
end

-- Control Tab
local PartnerUserBox = createSettingRow("Partner user:", TradeTable.Player2.Player, controlFrame)
PartnerUserBox.FocusLost:Connect(function()
	TradeTable.Player2.Player = PartnerUserBox.Text
	PartnerUserBox.Text = TradeTable.Player2.Player
end)
CreateSpace(controlFrame)
CreateButton(controlFrame, "Start trade", function()
	StartTrade()
end)
CreateSpace(controlFrame)
CreateButton(controlFrame, "Accept their offer", function()
	if not next(TradeTable["Player1"]["Offer"]) and not next(TradeTable["Player2"]["Offer"]) then
		return
	end
	if v84 then
		return
	end
	TheirOffer.Accepted.Visible = true
	TradeTable["Player2"]["Accepted"] = true
	AcceptTrade()
end)
CreateSpace(controlFrame)
CreateButton(controlFrame, "Block player", function()
	pcall(function()
		setthreadidentity(8)
		local Selected = game.Players:FindFirstChild(TradeTable.Player2.Player)
		game:GetService('StarterGui'):SetCore('PromptBlockPlayer', Selected)
		repeat game:GetService('RunService').Heartbeat:Wait() until game:GetService('CoreGui'):FindFirstChild('BlockingModalScreen')
		game:GetService('CoreGui').BlockingModalScreen.BlockingModalContainer.BlockingModalContainerWrapper.BlockingModal.BackgroundTransparency = 1
		game:GetService('CoreGui').BlockingModalScreen.BlockingModalContainer.BlockingModalContainerWrapper.BackgroundTransparency = 1
		game:GetService('CoreGui').BlockingModalScreen.BlockingModalContainer.BackgroundTransparency = 1
		game:GetService("CoreGui").BlockingModalScreen.BlockingModalContainer.BlockingModalContainerWrapper.BlockingModal.AlertModal.Position = UDim2.new(0.00800000038, -110, 0.5, 0)
		local interact = function(path)
			game:GetService("GuiService").SelectedObject = path
			task.wait()
			if game:GetService("GuiService").SelectedObject == path then
				game:GetService("VirtualInputManager"):SendKeyEvent(true, Enum.KeyCode.Return, false, game)
				game:GetService("VirtualInputManager"):SendKeyEvent(false, Enum.KeyCode.Return, false, game)
				task.wait()
			end
			game:GetService("GuiService").SelectedObject = nil
		end	
		interact(game:GetService("CoreGui").BlockingModalScreen.BlockingModalContainer.BlockingModalContainerWrapper.BlockingModal.AlertModal.AlertContents.Footer.Buttons["3"])
		setthreadidentity(2) 
	end)
end)

-- Items Tab
local selectedWeapon = ""

local ItemToAddPartnerBox = createSettingRow("Name item to add:", "", itemsFrame)

CreateSpace(itemsFrame)

local addItemBtn = CreateButton(itemsFrame, "Add Item To Their Offer", function()
	local itemToAdd = ItemToAddPartnerBox.Text
	if itemToAdd and itemToAdd ~= "" then
		OfferItemAnotherPlayer(itemToAdd, "Weapons")
	end
end)

CreateSpace(itemsFrame)

CreateButton(itemsFrame, "Remove last Item in Their Offer", function()
	RemoveItemAnotherPlayer()
end)

CreateSpace(itemsFrame)

-- Weapon selection label
local weaponListLabel = Instance.new("TextLabel")
weaponListLabel.Size = UDim2.new(1, 0, 0, 15)
weaponListLabel.BackgroundTransparency = 1
weaponListLabel.Text = "Click weapon to ADD directly:"
weaponListLabel.Font = Enum.Font.SourceSansSemibold
weaponListLabel.TextSize = 12
weaponListLabel.TextColor3 = Color3.fromRGB(0, 255, 100)
weaponListLabel.TextXAlignment = Enum.TextXAlignment.Left
weaponListLabel.Parent = itemsFrame

-- Scrollable weapon list
local weaponScrollFrame = Instance.new("ScrollingFrame")
weaponScrollFrame.Size = UDim2.new(1, 0, 0, 120)
weaponScrollFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
weaponScrollFrame.BackgroundTransparency = 0.3
weaponScrollFrame.BorderSizePixel = 0
weaponScrollFrame.ScrollBarThickness = 6
weaponScrollFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 255)
weaponScrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
weaponScrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
weaponScrollFrame.Parent = itemsFrame

local weaponScrollCorner = Instance.new("UICorner")
weaponScrollCorner.CornerRadius = UDim.new(0, 5)
weaponScrollCorner.Parent = weaponScrollFrame

local weaponScrollStroke = Instance.new("UIStroke")
weaponScrollStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
weaponScrollStroke.Color = Color3.fromRGB(80, 80, 120)
weaponScrollStroke.Thickness = 1
weaponScrollStroke.Parent = weaponScrollFrame

local weaponListLayout = Instance.new("UIListLayout")
weaponListLayout.FillDirection = Enum.FillDirection.Vertical
weaponListLayout.SortOrder = Enum.SortOrder.LayoutOrder
weaponListLayout.Padding = UDim.new(0, 2)
weaponListLayout.Parent = weaponScrollFrame

local weaponListPadding = Instance.new("UIPadding")
weaponListPadding.PaddingTop = UDim.new(0, 3)
weaponListPadding.PaddingBottom = UDim.new(0, 3)
weaponListPadding.PaddingLeft = UDim.new(0, 3)
weaponListPadding.PaddingRight = UDim.new(0, 3)
weaponListPadding.Parent = weaponScrollFrame

-- All weapons for the list (using correct database names - removed invalid ones)
local allWeaponsList = {
	-- ANCIENTS (removed Batwing)
    "ElderwoodScythe", "Icewing", "Logchopper", "Hallowscythe", "Harvester",
	"Icebreaker", "IceHammer", "VampireAxe", "SwirlyAxe", "TravelerAxe", "Gingerscythe",
	"Gingerscope", "Icepiercer", "Synthwave",
	
	-- CHROMAS
	"SeerChroma", "GemstoneChroma", "DeathshardChroma", "FangChroma", "SawChroma",
	"SlasherChroma", "TidesChroma", "HeatChroma", "LugerChroma", "SharkChroma",
	"LaserChroma", "ChromaDarkbringer", "ChromaLightbringer", "BonebladeChroma",
	"GingerbladeChroma", "CandleflameChroma", "ElderwoodKnifeChroma", "Gingermint_KChroma",
	"TreeGun2023Chroma", "TreeKnife2023Chroma", "ConstellationChroma", "BaubleChroma",
	"BlizzardChroma", "RaygunChroma", "SnowDaggerChroma", "SunsetKnifeChroma", "SunsetGunChroma",
	"SwirlyGunChroma", "VampireGunChroma", "WatergunChroma", "TravelerGunChroma",
    "UFOKnifeChroma", "SnowstormChroma", "SnowcannonChroma",
	"BaubleKnifeChroma",
	
	-- GODLY KNIVES
	"TheSeer", "Gemstone", "Deathshard", "Fang", "Saw", "Slasher", "Tides", "Heat",
	"Eternal", "Eternal2", "Eternal3", "Eternal4", "EternalCane",
	"BlueSeer", "RedSeer", "PurpleSeer", "OrangeSeer", "YellowSeer",
	"Clockwork", "Pixel", "Virtual", "BigKill", "Spider", "Candy", "Chill", "Handsaw",
	"Xmas", "HallowsBlade", "IceDragon", "Flames", "BattleAxe",
	"Snowflake", "IceShard", "Boneblade", "Pumpking", "BattleAxe2", "Gingerblade",
	"WintersEdge", "Frostsaber", "Nightblade", "Ghostblade", "Frostbite", "VampiresEdge",
	"Cookieblade", "Peppermint", "Bioblade", "Heartblade", "Eggblade", "Prismatic", "Nebula",
	"Candleflame", "SwirlyBlade", "Iceflake", "Plasmablade", "ElderwoodKnife",
	"Phantom", "Sakura_K", "Rainbow", "Waves_K", "Darksword", "TreeKnife2023",
	"FlowerwoodKnife", "Bloom", "SunsetKnife", "XenoKnife", "Celestial",
	"SnowDagger", "Blizzard", "UFOKnife", "BaubleKnife",
	
	-- GODLY GUNS (removed Gingermint_G, Blossom_G, Ocean_G, Pearl_G - they don't exist)
	"Darkbringer", "Lightbringer", "Luger", "Shark", "Laser", "Lugercane", "Blaster",
	"Amerilaser", "Sugar", "GreenLuger", "RedLuger", "ElderwoodGun", "Minty",
	"GingerLuger", "Jinglegun", "Iceblaster", "Hallowgun", "SwirlyGun", "Icebeam",
	"Plasmabeam", "Makeshift", "Spectre2022", "RainbowGun",
	"Darkshot", "TravelerGun", "TreeGun2023", "FlowerwoodGun", "Watergun",
	"VampireGun", "Constellation", "Bauble", "Flora",
	"SunsetGun", "Raygun", "XenoGun", "Snowcannon", "Snowstorm",
	
	-- VINTAGE
	"AmericaGun", "AmericaSword", "BloodKnife", "GhostKnife", "GoldenGun", "Phaser", 
	"ShadowKnife",
	
	-- LEGENDARY
	"Viper", "SlimeK", "Wrapped", "SnakebiteK", "Web", "Midnight",
	"Tree", "Gifted", "Ornament1", "Carrot",
	"CottonCandy", "Jack", "Nutcracker", "Roses",
	"Elf", "MummyK", "Skulls", "WebbedK", "ToxicK",
	"Sweetheart", "LoveGun", "Nightfire",
	"Infected", "SnakebiteG",
	
	-- RARE
	"Galactic", "Splash", "DeepSea", "Overseer", "OverseerKnife",
	
	-- UNCOMMON
	"Adurite", "AduriteGun", "Elite", "Fade", "Sparkle",
	
	-- COMMON
	"DefaultKnife", "DefaultGun",
	
	-- COLOR VARIANTS
	"BlueHarvester", "BronzeHarvester", "GoldHarvester", "SilverHarvester",
	"BlueVampiresEdge", "BronzeVampiresEdge", "GoldVampiresEdge", "SilverVampiresEdge",
	"BronzeIceblaster", "GoldIceblaster", "RedIceblaster", "SilverIceblaster",
	"BronzeIcebreaker", "GoldIcebreaker", "RedIcebreaker", "SilverIcebreaker",
	"LogchopperBlue", "LogchopperBronze", "LogchopperGold", "LogchopperSilver",
	"IcepiercerBronze", "IcepiercerGold", "IcepiercerRed", "IcepiercerSilver",
	"MintyBlue", "MintyBronze", "MintyGold", "MintySilver",
	"ElderwoodGunBlue", "ElderwoodGunBronze", "ElderwoodGunGold", "ElderwoodGunSilver",
	"ElderwoodKnifeBlue", "ElderwoodKnifeBronze", "ElderwoodKnifeGold", "ElderwoodKnifeSilver",
	"SwirlyAxeBlue", "SwirlyAxeBronze", "SwirlyAxeGold", "SwirlyAxeSilver",
	"SwirlyGunBlue", "SwirlyGunBronze", "SwirlyGunGold", "SwirlyGunSilver",
	"Gingerscope_Blue", "Gingerscope_Bronze", "Gingerscope_Gold", "Gingerscope_Silver",
	"VampireAxe_Bronze", "VampireAxe_Gold", "VampireAxe_Purple", "VampireAxe_Silver",
	"TravelerAxeBronze", "TravelerAxeGold", "TravelerAxeRed", "TravelerAxeSilver",
	"Celestial_Bronze", "Celestial_Gold", "Celestial_Red", "Celestial_Silver",
	"Constellation_Bronze", "Constellation_Gold", "Constellation_Red", "Constellation_Silver",
	"IceHammerBronze", "IceHammerGold", "IceHammerRed", "IceHammerSilver"
}

-- Create weapon buttons - clicking directly adds to offer
for i, weaponName in ipairs(allWeaponsList) do
	local wName = weaponName
	local weaponBtn = Instance.new("TextButton")
	weaponBtn.Size = UDim2.new(1, -6, 0, 22)
	weaponBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
	weaponBtn.BackgroundTransparency = 0.3
	weaponBtn.Text = wName
	weaponBtn.Font = Enum.Font.SourceSans
	weaponBtn.TextSize = 12
	weaponBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	weaponBtn.TextTruncate = Enum.TextTruncate.AtEnd
	weaponBtn.Parent = weaponScrollFrame
	
	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 4)
	btnCorner.Parent = weaponBtn
	
	weaponBtn.MouseEnter:Connect(function()
		TweenService:Create(weaponBtn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(80, 80, 120)}):Play()
	end)
	
	weaponBtn.MouseLeave:Connect(function()
		TweenService:Create(weaponBtn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(50, 50, 70)}):Play()
	end)
	
	weaponBtn.MouseButton1Click:Connect(function()
		-- Directly add to their offer
		local added = OfferItemAnotherPlayer(wName, "Weapons")
		
		if added then
			-- Flash green to confirm
			TweenService:Create(weaponBtn, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(0, 150, 100)}):Play()
		else
			-- Flash red if failed (max 4 items or other issue)
			TweenService:Create(weaponBtn, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(150, 50, 50)}):Play()
		end
		
		task.delay(0.2, function()
			TweenService:Create(weaponBtn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(50, 50, 70)}):Play()
		end)
	end)
end

-- Spawn Tab
local spawnItemName = ""
local SpawnItemBox = createSettingRow("Item name to spawn:", "", spawnFrame)
SpawnItemBox.FocusLost:Connect(function()
	spawnItemName = SpawnItemBox.Text
end)

CreateSpace(spawnFrame)

-- Status label for spawn feedback
local spawnStatusLabel = Instance.new("TextLabel")
spawnStatusLabel.Size = UDim2.new(1, 0, 0, 20)
spawnStatusLabel.BackgroundTransparency = 1
spawnStatusLabel.Text = ""
spawnStatusLabel.Font = Enum.Font.SourceSans
spawnStatusLabel.TextSize = 12
spawnStatusLabel.TextColor3 = Color3.fromRGB(0, 255, 100)
spawnStatusLabel.Parent = spawnFrame

CreateButton(spawnFrame, "Spawn Item", function()
	if spawnItemName == "" then
		spawnStatusLabel.Text = "Enter an item name!"
		spawnStatusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
		return
	end
	SpawnItem(spawnItemName, 1, "Weapons")
	spawnStatusLabel.Text = "Spawned: " .. spawnItemName
	spawnStatusLabel.TextColor3 = Color3.fromRGB(0, 255, 100)
end)

CreateSpace(spawnFrame)

-- Spawn amount input
local spawnAmount = 1
local SpawnAmountBox = createSettingRow("Amount to spawn:", "1", spawnFrame)
SpawnAmountBox.FocusLost:Connect(function()
	local num = tonumber(SpawnAmountBox.Text)
	if num and num >= 1 then
		spawnAmount = math.floor(num)
		SpawnAmountBox.Text = tostring(spawnAmount)
	else
		SpawnAmountBox.Text = "1"
		spawnAmount = 1
	end
end)

CreateSpace(spawnFrame)

CreateButton(spawnFrame, "Spawn Item x Amount", function()
	if spawnItemName == "" then
		spawnStatusLabel.Text = "Enter an item name!"
		spawnStatusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
		return
	end
	SpawnItem(spawnItemName, spawnAmount, "Weapons")
	spawnStatusLabel.Text = "Spawned: " .. spawnItemName .. " x" .. spawnAmount
	spawnStatusLabel.TextColor3 = Color3.fromRGB(0, 255, 100)
end)

CreateSpace(spawnFrame)

-- Spawn All Rare Weapons button
local spawnAllButton = CreateButton(spawnFrame, "Spawn All Rare Weapons", function()
	spawnStatusLabel.Text = "Spawning all rare weapons..."
	spawnStatusLabel.TextColor3 = Color3.fromRGB(255, 255, 0)
	
	task.spawn(function()
		local count = 0
		for _, weaponName in ipairs(rareWeaponsList) do
			SpawnItem(weaponName, 1, "Weapons")
			count = count + 1
			if count % 10 == 0 then
				spawnStatusLabel.Text = "Spawned " .. count .. "/" .. #rareWeaponsList .. " weapons..."
				task.wait(0.05)
			end
		end
		spawnStatusLabel.Text = "Spawned all " .. #rareWeaponsList .. " rare weapons!"
		spawnStatusLabel.TextColor3 = Color3.fromRGB(0, 255, 100)
	end)
end)
spawnAllButton.BackgroundColor3 = Color3.fromRGB(0, 150, 100)

-- Players Tab
playersFrame.UIListLayout.Padding = UDim.new(0, 5)
local function UpdatePlayers()
	for _, child in pairs(playersFrame:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	for _, player in pairs(game.Players:GetPlayers()) do
		local button = CreateButton(playersFrame, player.Name, function()
			TradeTable.Player2.Player = player.Name
			PartnerUserBox.Text = TradeTable.Player2.Player
			setActiveTab("Control")
		end)
		button.Size = UDim2.new(1, 0, 0, 25)
	end
end
UpdatePlayers()
game.Players.PlayerAdded:Connect(function()
	UpdatePlayers()
end)
game.Players.PlayerRemoving:Connect(function()
	UpdatePlayers()
end)
game.Players.ChildRemoved:Connect(function()
	UpdatePlayers()
end)