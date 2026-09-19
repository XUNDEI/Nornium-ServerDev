require "UnLua"
require "Common.TableUtil"

local Client = require "Network.Client"
local Database = require("_Game.Utils.Database")
local UIUtils = require('_Game.Utils.UIUtils')
local MallSystem = require "Module.ShopSystem.MallSystem"
local BackpackSystem = require 'Module.Backpack.BackpackSystem'
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_SwapTicket_C
local M = Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

function M:Construct()
    self:InitData()
    self:InitUI()
    MessageManager:GetInstance():AddListener("OnMsg_Ntf_Item_Info", self)
    MessageManager:GetInstance():AddListener("OnMsg_Bag_Use_Item_Success", self)
    local controller = UE.UGameplayStatics.GetPlayerController(self, 0)
    controller.BP_PlayerController_City_UniverseBridge.BlockInputAction = true
    self.ShowInteractOptions = false
    self.HideCursor = false
end

function M:Destruct()
    local controller = UE.UGameplayStatics.GetPlayerController(self, 0)
    if controller then
        controller.BP_PlayerController_City_UniverseBridge.BlockInputAction = false
    end
    self.ShowInteractOptions = true
    self.HideCursor = true
    MessageManager:GetInstance():RemoveListener("OnMsg_Ntf_Item_Info", self)
    MessageManager:GetInstance():RemoveListener("OnMsg_Bag_Use_Item_Success", self)
end

function M:OnMsg_Ntf_Item_Info(changed_item_infos)
    if not self.ItemData then --购买钻石
        local rewardList = {}
        for _, v in pairs(changed_item_infos) do
            if v.count > 0 then
                table.insert(rewardList, {
                    itemId = v.item_id,
                    count = v.count,
                })
            end
        end
        if #rewardList > 0 then
            UIUtils.ShowGetRewardCommonUI(self, rewardList)
        end
        self:RefreshInfo()
    else--抽卡
        local hasCostItemCount = UIUtils.GetItemCount(self.GotItemId)
        if self.MallItemId and self.MallItemCount <= hasCostItemCount then
            UIManager:GetInstance():RemoveUI(self)
            --继续开抽
            MessageManager:GetInstance():Broadcast('OnMsg_SwapTicket')
        end
    end
end

function M:OnMsg_Bag_Use_Item_Success()
    if not self.ItemData then --购买钻石
        UIManager:GetInstance():RemoveUI(self)
    else
        self:RefreshInfo()
    end
end

function M:InitData()

end

function M:InitUI()
    self.Btn_Close.OnGHSClicked:Add(self, self.OnClicked_Btn_Close)
    self.Btn_Confirm.OnGHSClicked:Add(self, self.OnClicked_Btn_Confirm)
    self:PlayAnimationForward(self.vfxin)
end

function M:GetMallInfoById(shopType)
    local mallInfos = MallSystem:GetInstance().MallInfo.mall_infos
    for _, mall_info in ipairs(mallInfos) do
        if mall_info.mall_id == shopType then
            return mall_info
        end
    end
    return nil
end

--购买票据
function M:RefreshUI(itemId, needTickCount)
    self.MallItemId = itemId
    self.MallItemCount = needTickCount --购买的抽卡券个数
    local mallConfig = Database.Query('d_mall', itemId)
    self.ItemData = self:GetMallInfoById(mallConfig.shopType)

    --兑换的道具信息
    self.GotItemId = mallConfig.goods[1] --获得的道具id
    --消耗物品
    self.CostItemId = mallConfig.currency --消耗道具id

    self.CostItemCount = mallConfig.price[1] --需要消耗的个数 200
    self.CostItemPrice = mallConfig.goods[3] or 1  --消耗道具获得的比例 比如消耗200个获得1个gotItemId

    --购买次数
    self.CostItemNeedCount = math.ceil(self.MallItemCount / self.CostItemPrice) * self.CostItemCount
   
    self:RefreshInfo()
end

--gotItemId 目标道具id
--costId 消耗道具id
--costCount --消耗道具个数 1:200中的1
--price --兑换目标个数 1:200中的200
--购买钻石
function M:RefreshMoney(gotItemId, needCount, costId, costCount, price)
    self.MallItemCount = needCount

    --兑换的道具信息
    self.GotItemId = gotItemId --获得的道具id

    --消耗物品
    self.CostItemId = costId --消耗道具id
    self.CostItemCount = costCount --需要消耗的个数 1
    self.CostItemPrice = price  --消耗道具获得的比例 比如消耗1个获得200个gotItemId

    --购买次数
    self.CostItemNeedCount = math.ceil(self.MallItemCount / self.CostItemPrice) * self.CostItemCount

    self:RefreshInfo()
end

function M:RefreshInfo()
  
    --消耗道具信息
    local itemConfig = UIUtils.GetItemConfigById(self.CostItemId)
    if itemConfig.iconPath and itemConfig.iconPath ~= '' then
        self.Img_CostItem:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        self.Img_CostItem1:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        local strArr = string.split(itemConfig.iconPath, '/')
        -- local littePath = strArr[#strArr]
        local iconResPath = string.format('/Game/_Game/TP_New/Common/Frames/Icon_%s_png.Icon_%s_png', itemConfig.id, itemConfig.id)
        local iconRes = LoadObject(iconResPath)
        if iconRes then
            self.Img_CostItem:SetBrushFromAtlasInterface(iconRes)
            self.Img_CostItem1:SetBrushFromAtlasInterface(iconRes)
        end
    else
        self.Img_CostItem:SetVisibility(UE.ESlateVisibility.Collapsed)
        self.Img_CostItem1:SetVisibility(UE.ESlateVisibility.Collapsed)
    end

    local gotItemConfig = UIUtils.GetItemConfigById(self.GotItemId)
    -- --稀有度背景图片
    -- if gotItemConfig.rarityPath and gotItemConfig.rarityPath ~= '' then
    --     local strArr = string.split(gotItemConfig.rarityPath, '/')
    --     local littePath = strArr[#strArr]
    --     local rarityPath = string.format('/Game/_Game/%s.%s', gotItemConfig.rarityPath, littePath)
    --     local itemRarityPic = LoadObject(rarityPath)
    --     if itemRarityPic then
    --         self.UI_Item.wp_container_icon_res:SetBrushFromAtlasInterface(itemRarityPic)
    --     end
    -- end
    -- self.UI_Item.Text_Count:SetText(Database.L10n(gotItemConfig.itemName))

    if gotItemConfig.iconPath and gotItemConfig.iconPath ~= '' then
        self.Img_GetItem:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        local strArr = string.split(gotItemConfig.iconPath, '/')
        local littePath = strArr[#strArr]
        local iconResPath = string.format('/Game/_Game/TP_New/Common/Frames/Icon_%s_png.Icon_%s_png', gotItemConfig.id, gotItemConfig.id)
        local iconRes = LoadObject(iconResPath)
        if iconRes then
            self.Img_GetItem:SetBrushFromAtlasInterface(iconRes)
            -- self.UI_Item.wp_icon_res:SetBrushFromAtlasInterface(iconRes)
        end
    else
        self.Img_GetItem:SetVisibility(UE.ESlateVisibility.Collapsed)
    end

    --兑换比例
    self.Text_CostItemCountOne:SetText(self.CostItemCount)
    self.Text_GetItemCountOne:SetText(self.CostItemPrice)

    --背包已有道具个数
    local hasCostItemCount = UIUtils.GetItemCount(self.CostItemId)
    self.Text_CostItemHave:SetText(hasCostItemCount)

    hasCostItemCount = math.floor(hasCostItemCount / self.CostItemCount)
    local strId = 0
    --判断提示文字
    if self.CostItemId == UIUtils.ECurrencyId.Diamond then --钻石购买票据
        if self.GotItemId and self.GotItemId > 0 then
            if self.GotItemId == UIUtils.EGachaTicket.GachaTickLimit then
                strId = hasCostItemCount >= self.MallItemCount and 509 or 508
            else
                strId = hasCostItemCount >= self.MallItemCount and 511 or 510
            end
        end
    elseif self.CostItemId == UIUtils.ECurrencyId.NolenLens then
        strId = hasCostItemCount >= self.MallItemCount and 500 or 467
    end
   
    local str = strId > 0 and Database.L10n(strId) or ''
    str = string.gsub(str, "\\", "")
    self.Text_Tips:SetText(string.format(str, itemConfig.id, math.ceil(self.CostItemNeedCount)))
end

-------------------------------------------------------
--- UI Event
function M:OnClicked_Btn_Close()
    self:BindToAnimationFinished(self.vfxquit, function()
        UIManager:GetInstance():RemoveUI(self)
    end)
    self:PlayAnimationForward(self.vfxquit)
end

function M:OnClicked_Btn_Confirm()
    local hasCostItemCount = UIUtils.GetItemCount(self.CostItemId)
    local needAllCount = math.modf(self.MallItemCount * self.CostItemCount / self.CostItemPrice)
    --背包已有道具个数
    if hasCostItemCount < needAllCount then
        if self.CostItemId == UIUtils.ECurrencyId.NolenLens then

            UIUtils.ShowComNotice(Database.L10n(468), self, function()
                local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
                if gameInstance:OpenLink(9029) then
                    ---@type UI_TopUp_Shop_C
                    local ui = gameInstance:AddUMG('UI_TopUp_Shop')
                    ui.TopUp:SetIsCheckedAndFireEvent(true)
                end
            end, function()
                UIManager:GetInstance():RemoveUI(self)
            end)
        else
            --计算需要的货币9007个数
            local price = require('ClientDatas.d_gacha_params')[7].value2
            local needCount = needAllCount - hasCostItemCount
            local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
            local ui = gameInstance:AddUMG('UI_SwapTicket_C')
            if ui then
                ui:RefreshMoney(self.CostItemId, needCount, UIUtils.ECurrencyId.NolenLens, 1, price)
            end
        end
    else
        if self.CostItemId == UIUtils.ECurrencyId.NolenLens then
            local itemConfig = UIUtils.GetItemConfigById(self.CostItemId)
            local ItemData = {
                config = itemConfig,
                count = self.MallItemCount
            }
            BackpackSystem:GetInstance():CachedUseItem(ItemData, true)

            local _, uuid = UIUtils.GetItemCount(self.CostItemId)
            local msg = {}
            msg.item_uuid = uuid
            msg.count = self.MallItemCount
            Client.send("req_use_item", msg)
        else
            local msg = {}
            msg.mall_id = self.ItemData.mall_id
            msg.mall_item_id = self.MallItemId
            msg.mall_item_count = self.MallItemCount
            msg.last_auto_refresh_seconds = self.ItemData.last_auto_refresh_seconds
            local bSuccess, SteamId, CurrentGameLanguage = UE.UGameplayStatics.GetGameInstance(self):PreparePayWithSteam(0)
            if bSuccess then
                msg.steam_id = SteamId
                msg.steam_current_game_language = CurrentGameLanguage
            end
            Client.send("req_mall_buy", msg)
        end
    end
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.OnClicked_Btn_Close)
InputUtils.RegisterUIAction(M, InputAssets.IA_Confirm, UE.ETriggerEvent.Completed, M.OnClicked_Btn_Confirm)

return M
