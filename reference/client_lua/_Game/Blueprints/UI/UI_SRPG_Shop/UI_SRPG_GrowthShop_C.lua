local BackpackSystem = require 'Module.Backpack.BackpackSystem'
local PlayerSystem = require "Module.Player.PlayerSystem"
local Database = require("_Game.Utils.Database")
local Protos = require("Helper.Protos")
local Client = require "Network.Client"
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"
local MessageManager = require("Framework.Updater.MessageManager"):GetInstance()

---@type UI_SRPG_Shop_Growth_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

function M:Construct()
    if not M.ShopTitleButton then
        M.Font = LoadObject('/Game/_Game/Fonts/ZiHunBingYuYaSong_Font.ZiHunBingYuYaSong_Font')
        M.FontRef = UnLua.Ref(M.Font)
        M.ShopTitleButton = LoadClass("/Game/_Game/Blueprints/UI/UI_SRPG_Shop/ShopTitleButton.ShopTitleButton_C")
        M.ShopTitleButtonRef = UnLua.Ref(M.ShopTitleButton)
        M.UI_SRPG_Shop_Growth_Item = LoadClass('/Game/_Game/Blueprints/UI/UI_SRPG_Shop/UI_SRPG_Shop_Growth_Item.UI_SRPG_Shop_Growth_Item_C')
        M.UI_SRPG_Shop_Growth_ItemRef = UnLua.Ref(M.UI_SRPG_Shop_Growth_Item)
    end
    NetworkMessageManager:GetInstance():AddListener(Protos.RES_PLAYER_UNIVERSE_GROWTH, self)
    NetworkMessageManager:GetInstance():AddListener(Protos.RES_PLAYER_UNIVERSE_GROWTH_RESET, self)
end

function M:Destruct()
    if self.NPC then
        self.NPC:K2_DestroyActor()
    end
    
    NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_PLAYER_UNIVERSE_GROWTH, self)
    NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_PLAYER_UNIVERSE_GROWTH_RESET, self)
end

function M:Close()
    UIManager:GetInstance():RemoveUI(self)
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.Close)

function M:Init()
    local playerClass = LoadClass('/Game/_Game/Blueprints/NPCs/BP_NPC_SrpgShop.BP_NPC_SrpgShop_C')
    local trans = UE.UKismetMathLibrary.MakeTransform(
        UE.FVector(400, 350, 100),
        UE.FRotator(0, 0, 0),
        UE.FVector(1, 1, 1))
    self.NPC = self:GetWorld():SpawnActor(playerClass, trans,
        UE.ESpawnActorCollisionHandlingMethod.AlwaysSpawn, self, self)

    self.Exit.OnClicked:Add(self, self.Close)

    self.Reset.OnClicked:Add(self, self.ReqReset)

    self.shopConfig = require("ClientDatas.d_srpg_growth")

    self:UpdateLevelInfo()
    self:UpdateItems()
end

function M:UpdateItems()
    self.ShopItem:ClearChildren()
    for _, itemInfo in pairs(self.shopConfig) do
        ---@type UI_SRPG_Shop_Growth_Item_C
        local item = UE.UWidgetBlueprintLibrary.Create(self, M.UI_SRPG_Shop_Growth_Item)
        local itemLevel = PlayerSystem:GetInstance():GetSrpgGrowthNodeLevel(itemInfo.id) or 0
        local currentValue = itemInfo.display[itemLevel] or 0
        local nextValue = itemInfo.display[itemLevel + 1] or 0

        self.ShopItem:AddChild(item)

        item.Name:SetText(Database.L10n(itemInfo.nameId))

        if itemLevel > 0 then
            item.Bonus:SetText(string.format(itemInfo.upgrade, currentValue))
        end
        item.Bonus:SetVisibility(itemLevel > 0 and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Collapsed)

        item.Lv:SetText(itemLevel)
        item.LvMax:SetText(itemInfo.level)
        item.LevelUp:SetVisibility(itemLevel < itemInfo.level and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Collapsed)
        item.Max:SetVisibility(itemLevel < itemInfo.level and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Collapsed)
        item.MaxInfo:SetVisibility(itemLevel == itemInfo.level and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Collapsed)

        if itemLevel < itemInfo.level then
            item.Change:SetText(string.format(itemInfo.upgrade, nextValue - currentValue))
        end
        item.Change:SetVisibility(itemLevel < itemInfo.level and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Collapsed)

        item.LevelUp.OnClicked:Add(item, function()
            ---@type ReqPlayerUniverseGrowth
            Client.send(Protos.REQ_PLAYER_UNIVERSE_GROWTH, {
                node_id = itemInfo.id
            })
        end)

        item.Max.OnClicked:Add(item, function()
            self:UpgradeToMax(itemInfo.id)
        end)

        local points = PlayerSystem:GetInstance():GetSrpgGrowthPoints()

        item.LevelUp:SetIsEnabled(points >= itemInfo.cost)
        item.Max:SetIsEnabled(points >= itemInfo.cost)
    end
end

function M:UpdateLevelInfo()
    local level, exp = PlayerSystem:GetInstance():GetSrpgGrowthLevel()
    local maxExp = Database.Query("d_srpg_exp", level).exp
    local points = PlayerSystem:GetInstance():GetSrpgGrowthPoints()

    self.Level:SetText(tostring(level))
    self.Exp:SetText(tostring(exp))
    self.MaxExp:SetText(tostring(maxExp))
    self.ProgressBar:SetPercent(exp / maxExp)
    self.Points:SetText(tostring(points))
end

function M:UpgradeToMax(itemId)
    local itemInfo = Database.Query("d_srpg_growth", itemId)
    local itemLevel = PlayerSystem:GetInstance():GetSrpgGrowthNodeLevel(itemId) or 0

    local points = PlayerSystem:GetInstance():GetSrpgGrowthPoints()

    local level = math.min(itemInfo.level - itemLevel, math.floor(points / itemInfo.cost))

    for i = 1, level do
        Client.send(Protos.REQ_PLAYER_UNIVERSE_GROWTH, {
            node_id = itemId
        })
    end
end

function M:ReqReset()
    Client.send(Protos.REQ_PLAYER_UNIVERSE_GROWTH_RESET)
end

---@param self UI_SRPG_GrowthShop_C
---@param parsed_msg ResPlayerUniverseGrowthMessage
M[Protos.RES_PLAYER_UNIVERSE_GROWTH] = function(self, result, msgId, parsed_msg)
    if result == 0 then
        PlayerSystem:GetInstance():LevelUpSrpgGrowthNode(parsed_msg.req_data.node_id)

        self:UpdateItems()
        self:UpdateLevelInfo()

        MessageManager:Broadcast('OnMsg_Universe_Growth')
    end
end

M[Protos.RES_PLAYER_UNIVERSE_GROWTH_RESET] = function(self, result, msgId, parsed_msg)
    if result == 0 then
        PlayerSystem:GetInstance():ResetSrpgGrowth()

        self:UpdateItems()
        self:UpdateLevelInfo()
    end
end

return M
