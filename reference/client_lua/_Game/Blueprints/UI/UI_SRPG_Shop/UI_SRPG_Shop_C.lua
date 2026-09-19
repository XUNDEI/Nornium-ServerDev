local hex_grid = require "Helper.hex_grid"
local SrpgModel = require("Module.Srpg.SrpgModel")
local SrpgController = require("Module.Srpg.SrpgController")
local Client = require "Network.Client"
local Protos = require("Helper.Protos")
local Database = require("_Game.Utils.Database")
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_SRPG_Shop_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

function M:Initialize()
    
end

function M:Construct()
    if not M.ShopTitleButton then
        M.ShopTitleButton = LoadClass("/Game/_Game/Blueprints/UI/UI_SRPG_Shop/ShopTitleButton.ShopTitleButton_C")
        M.ShopTitleButtonRef = UnLua.Ref(M.ShopTitleButton)
        M.UI_SRPG_Shop_item = LoadClass('/Game/_Game/Blueprints/UI/UI_SRPG_Shop/UI_SRPG_Shop_item.UI_SRPG_Shop_item_C')
        M.UI_SRPG_Shop_itemRef = UnLua.Ref(M.UI_SRPG_Shop_item)

        M.RES_ICONS = {
            [1] = LoadObject('/Game/_Game/TP_New/Common/Frames/Icon_res_1_png.Icon_res_1_png'),
            [2] = LoadObject('/Game/_Game/TP_New/Common/Frames/Icon_res_2_png.Icon_res_2_png'),
            [3] = LoadObject('/Game/_Game/TP_New/Common/Frames/Icon_res_3_png.Icon_res_3_png'),
            [4] = LoadObject('/Game/_Game/TP_New/Common/Frames/Icon_res_4_png.Icon_res_4_png'),
        }
        M.RES_ICONSRef = {
            UnLua.Ref(M.RES_ICONS[1]),
            UnLua.Ref(M.RES_ICONS[2]),
            UnLua.Ref(M.RES_ICONS[3]),
            UnLua.Ref(M.RES_ICONS[4]),
        }
    end
    self.Exit.OnClicked:Add(self.Exit, function()
        self:Close()
    end)

    MessageManager:GetInstance():AddListener(SrpgModel.ResourceChanged, self)

    NetworkMessageManager:GetInstance():AddListener(Protos.RES_MAIN_POS_SHOP_BUY, self)
    NetworkMessageManager:GetInstance():AddListener(Protos.RES_MAIN_POS_SHOP_REFRESH, self)
end

function M:Destruct()
    MessageManager:GetInstance():RemoveListener(SrpgModel.ResourceChanged, self)

    NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_MAIN_POS_SHOP_BUY, self)
    NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_MAIN_POS_SHOP_REFRESH, self)
end

---@param selectedShopInfo MainPosShopInfo
function M:Show(selectedShopInfo)
    self:InitUI()

    self.shopButtons[selectedShopInfo].ShopTitleButton:SetIsCheckedAndFireEvent(true)

    self:SetVisibility(UE.ESlateVisibility.Visible)
end

function M:Close()
    UIManager:GetInstance():RemoveUI(self)
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.Close)

function M:InitUI()
    self.shopButtons = {}
    self.ShopTitleList:ClearChildren()
    for _, mainPos in pairs(SrpgController:GetInstance():GetMainPosInfo()) do
        for _, attachInfo in pairs(mainPos.main_pos_attach_infos) do
            if attachInfo.main_pos_attach_extra == SrpgModel.AttachType.Shop then
                self:AddShop(mainPos.hex, attachInfo.main_pos_shop_info)
            end
        end
    end

    self:UpdateResources()
end

function M:UpdateResources()
    for i = 1, 3 do
        self.UI_SRPG_res[string.format("res%d_value", i)]:SetText(tostring(SrpgController:GetInstance():GetResource(i)))
    end
end

---@param shopInfo MainPosShopInfo
function M:ShowShop(shopInfo)
    self.selectedShop = shopInfo
    local hex
    local index
    for _, mainPos in pairs(SrpgController:GetInstance():GetMainPosInfo()) do
        for i, attachInfo in ipairs(mainPos.main_pos_attach_infos) do
            if attachInfo.main_pos_attach_extra == SrpgModel.AttachType.Shop then
                if attachInfo.main_pos_shop_info == shopInfo then
                    hex = mainPos.hex
                    index = i
                end
            end
        end
    end

    local shopConfig = Database.Query("d_srpg_shop_base", shopInfo.shop_id)

    self.Image:SetBrushFromAtlasInterface(M.RES_ICONS[shopConfig.refreshCost[1]])
    self.TextRefreshPrice:SetText(tostring(shopConfig.refreshCost[2]))
    self.GHSButtonRefresh.OnClicked:Clear()
    self.GHSButtonRefresh.OnClicked:Add(self, function()
        ---@type ReqMainPosShopRefresh
        self.msg = {
            hex = hex,
            attach_index = index - 1,
        }

        Client.send(Protos.REQ_MAIN_POS_SHOP_REFRESH, self.msg)
    end)

    self.Desc:SetText(Database.L10n(shopConfig.txtId))

    self.ShopItem:ClearChildren()
    for i, itemInfo in ipairs(shopInfo.item_infos) do
        ---@type UI_SRPG_Shop_item_C
        local item = UE.UWidgetBlueprintLibrary.Create(self, M.UI_SRPG_Shop_item)

        self.ShopItem:AddChild(item)
        item.Slot:SetRow(math.floor((i - 1) / 4))
        item.Slot:SetColumn((i - 1) % 4)

        local itemConfig = Database.Query("d_srpg_shop_item", itemInfo.item_id)
        local itemName = Database.L10n(itemConfig.nameId)

        item.item_value:SetVisibility(UE.ESlateVisibility.Hidden)
        item.item_name:SetText(itemName)

        item.res_icon:SetBrushFromAtlasInterface(M.RES_ICONS[itemConfig.itemCost[1]])
        item.item_icon:SetBrushFromAtlasInterface(LoadObject(itemConfig.iconPath))
        item.res_value:SetText(tostring(itemConfig.itemCost[2]))

        item.Btn_buy:SetIsEnabled(not itemInfo.sold)

        item.Btn_buy.OnClicked:Add(item, function()
            ---@type ReqMainPosShopBuy
            self.msg = {
                hex = hex,
                attach_index = index - 1,
                item_index = i - 1,
            }

            Client.send(Protos.REQ_MAIN_POS_SHOP_BUY, self.msg)
        end)
    end
end

---@param self UI_SRPG_Shop_C
M[SrpgModel.ResourceChanged] = function(self)
    self:UpdateResources()
end

---@param self UI_SRPG_Shop_C
---@param parsed_msg ResMainPosShopBuyMessage
M[Protos.RES_MAIN_POS_SHOP_BUY] = function(self, result, msgId, parsed_msg)
    if result == 0 then
        SrpgController:GetInstance():BuyItem(self.msg.hex, self.msg.attach_index + 1, self.msg.item_index + 1)

        self:ShowShop(self.selectedShop)

        self.msg = nil
    end
end

---@param self UI_SRPG_Shop_C
---@param parsed_msg ResMainPosShopRefreshMessage
M[Protos.RES_MAIN_POS_SHOP_REFRESH] = function(self, result, msgId, parsed_msg)
    if result == 0 then
        SrpgController:GetInstance():RefreshShop(self.msg.hex, self.msg.attach_index + 1, parsed_msg.res_main_pos_shop_refresh.item_infos)

        self:ShowShop(self.selectedShop)

        self.msg = nil
    end
end

---@param shopInfo MainPosShopInfo
function M:AddShop(hex, shopInfo)
    ---@type ShopTitleButton_C
    local shopButton = UE.UWidgetBlueprintLibrary.Create(self, M.ShopTitleButton)

    self.ShopTitleList:AddChild(shopButton)

    shopButton.ShopTitleButton.CheckBoxGroup = self.ShopTitleGroup
    self.ShopTitleGroup:ResetToggleState()

    local shopConfig = Database.Query("d_srpg_shop_base", shopInfo.shop_id)
    local shopName = Database.L10n(shopConfig.nameId)

    shopButton.Selected:SetText(shopName)
    shopButton.Unselected:SetText(shopName)

    shopButton.ShopTitleButton.OnCheckStateChanged:Add(shopButton, function(_, isOn)
        if isOn then
            self:ShowShop(shopInfo)
        end
    end)

    self.shopButtons[shopInfo] = shopButton
end

return M
