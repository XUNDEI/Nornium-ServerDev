require "UnLua"
require "Common.TableUtil"

local Client = require "Network.Client"
local Database = require("_Game.Utils.Database")
local UIUtils = require('_Game.Utils.UIUtils')
local MallSystem = require "Module.ShopSystem.MallSystem"
local BackpackSystem = require 'Module.Backpack.BackpackSystem'
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_SwapMoney_C
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
    local controller = UE.UGameplayStatics.GetPlayerController(self, 0)
    controller.BP_PlayerController_City_UniverseBridge.BlockInputAction = true
    self.ShowInteractOptions = false
    self.HideCursor = false
end

function M:Destruct()
    MessageManager:GetInstance():RemoveListener("OnMsg_Ntf_Item_Info", self)
    if self.LongPress_Sub then
        UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.LongPress_Sub)
        self.LongPress_Sub = nil
    end
    if self.LongPress_Add then
        UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.LongPress_Add)
        self.LongPress_Add = nil
    end

    local controller = UE.UGameplayStatics.GetPlayerController(self, 0)
    if controller then
        controller.BP_PlayerController_City_UniverseBridge.BlockInputAction = false
    end
    self.ShowInteractOptions = true
    self.HideCursor = true
end

function M:OnMsg_Ntf_Item_Info(changed_item_infos)
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
    --重新获取背包数据
    self:RefreshPanel()
end

function M:InitData()

end

function M:InitUI()
    self.Btn_Close.OnGHSClicked:Add(self, self.OnClicked_Btn_Close)
    self.Btn_Confirm.OnGHSClicked:Add(self, self.OnClicked_Btn_Confirm)

    --普通点击
    self.Btn_Sub.OnGHSClicked:Add(self, self.OnClicked_Btn_Sub)
    self.Btn_Add.OnGHSClicked:Add(self, self.OnClicked_Btn_Add)
    --长按
    self.Btn_Sub.OnGHSPressed:Add(self, self.OnPressed_Btn_Sub)
    self.Btn_Sub.OnGHSReleased:Add(self, self.OnReleased_Btn_Sub)
    self.Btn_Add.OnGHSPressed:Add(self, self.OnPressed_Btn_Add)
    self.Btn_Add.OnGHSReleased:Add(self, self.OnReleased_Btn_Add)

    self.Slider_SelectedCount.OnGHSValueChanged:Add(self, self.OnValueChanged_SliderCount)

    self:PlayAnimationForward(self.vfxin)
end

--gotItemId 目标道具id
--costId 消耗道具id
--costCount --消耗道具个数
--price --兑换目标个数
function M:RefreshMoney(gotItemId, costId, costCount, price)
    --兑换的道具信息
    self.GotItemId = gotItemId --获得的道具id
    self.GotItemCount = price --1:200,值存200

    --消耗物品
    self.CostItemId = costId --消耗道具id
    self.CostItemCount = costCount --消耗道具获得的比例 比如消耗1个获得200个gotItemId

    self.SelectedCount = 0

    self:RefreshPanel()
end

function M:RefreshPanel()
    local hasCostItemCount = UIUtils.GetItemCount(self.CostItemId)
    --最大兑换次数
    local maxTimes = math.floor(hasCostItemCount / self.CostItemCount)
    self.DefaultMaxCount = maxTimes --math.max(maxTimes, 1)
    self.Slider_SelectedCount:SetMinValue(0)
    self.Slider_SelectedCount:SetMaxValue(self.DefaultMaxCount == 0 and 1 or self.DefaultMaxCount)
    self.SliderValue = self.SelectedCount / (self.DefaultMaxCount == 0 and 1 or self.DefaultMaxCount)
    self.Slider_SelectedCount:SetStepSize(math.max(maxTimes / 10, 1))

    self.SelectedCount = math.modf(math.min(self.SelectedCount, self.DefaultMaxCount))

    --消耗道具信息
    local itemConfig = UIUtils.GetItemConfigById(self.CostItemId)
    if itemConfig.iconPath and itemConfig.iconPath ~= '' then
        self.Img_CostItem:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        self.Img_CostItem1:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        local strArr = string.split(itemConfig.iconPath, '/')
        local littePath = strArr[#strArr]
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
    --稀有度背景图片
    if gotItemConfig.rarityPath and gotItemConfig.rarityPath ~= '' then
        local strArr = string.split(gotItemConfig.rarityPath, '/')
        local littePath = strArr[#strArr]
        local rarityPath = string.format('/Game/_Game/%s.%s', gotItemConfig.rarityPath, littePath)
        local itemRarityPic = LoadObject(rarityPath)
        if itemRarityPic then
            self.UI_Item.wp_container_icon_res:SetBrushFromAtlasInterface(itemRarityPic)
        end
    end
    self.UI_Item.Text_Count:SetText(Database.L10n(gotItemConfig.itemName))

    if gotItemConfig.iconPath and gotItemConfig.iconPath ~= '' then
        self.Img_GetItem:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        local strArr = string.split(gotItemConfig.iconPath, '/')
        local littePath = strArr[#strArr]
        local iconResPath = string.format('/Game/_Game/%s.%s', gotItemConfig.iconPath, littePath)
        local iconResPath2 = string.format('/Game/_Game/TP_New/Common/Frames/Icon_%s_png.Icon_%s_png', gotItemConfig.id, gotItemConfig.id)
        local iconRes = LoadObject(iconResPath)
        if iconRes then
            self.UI_Item.wp_icon_res:SetBrushFromAtlasInterface(iconRes)
        end
        local iconRes2 = LoadObject(iconResPath2)
        if iconRes2 then
            self.Img_GetItem:SetBrushFromAtlasInterface(iconRes2) 
        end
    else
        self.Img_GetItem:SetVisibility(UE.ESlateVisibility.Collapsed)
    end

    --兑换比例
    self.Text_CostItemCountOne:SetText(self.CostItemCount)
    self.Text_GetItemCountOne:SetText(self.GotItemCount)

    --背包已有道具个数
    local hasCostItemCount = UIUtils.GetItemCount(self.CostItemId)
    self.Text_CostItemHave:SetText(hasCostItemCount)

    self:RefreshSelectedInfo()
end

function M:RefreshSelectedInfo(bIsForce)
    self.Text_SelectedCount:SetText(self.SelectedCount)
    -- local hasCostItemCount = UIUtils.GetItemCount(self.CostItemId)
    -- local isFull = self.SelectedCount * self.CostItemCount < hasCostItemCount
    -- isFull = isFull or (self.SelectedCount <= 0)
    --self.Btn_Confirm:SetIsEnabled(isFull)
    if self.DefaultMaxCount <= 0 and self.SelectedCount <= 0 then
        self.Btn_Confirm:SetIsEnabled(true)
    elseif self.DefaultMaxCount > 0 and self.SelectedCount <= 0 then
        self.Btn_Confirm:SetIsEnabled(false)
    else
        self.Btn_Confirm:SetIsEnabled(true)
    end

    if not bIsForce then
        self.Slider_SelectedCount:SetValue(self.SelectedCount)
    end
    self.ProgressBar:SetPercent((self.SelectedCount) / (self.DefaultMaxCount == 0 and 1 or self.DefaultMaxCount))
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
    --背包已有道具个数
    local hasCostItemCount, uuid = UIUtils.GetItemCount(self.CostItemId)
    local maxCostItemCount = hasCostItemCount / self.CostItemCount
    if hasCostItemCount <= 0 or maxCostItemCount < self.SelectedCount then
        UIUtils.ShowComNotice(Database.L10n(468), self, function()
            local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
            if gameInstance:OpenLink(9029) then
                ---@type UI_TopUp_Shop_C
                local ui = gameInstance:AddUMG('UI_TopUp_Shop')
                ui.TopUp:SetIsCheckedAndFireEvent(true)
            end
        end, function()

        end)
    elseif self.SelectedCount <= 0 then
        return
    else
        local itemConfig = UIUtils.GetItemConfigById(self.CostItemId)
        local ItemData = {
            config = itemConfig,
            count = self.SelectedCount
        }
        BackpackSystem:GetInstance():CachedUseItem(ItemData, true)
        --兑换道具
        local msg = {}
        msg.item_uuid = uuid
        msg.count = self.SelectedCount
        Client.send("req_use_item", msg)
    end
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.OnClicked_Btn_Close)
InputUtils.RegisterUIAction(M, InputAssets.IA_Confirm, UE.ETriggerEvent.Completed, M.OnClicked_Btn_Confirm)

function M:OnClicked_Btn_Sub()
    if self.SelectedCount <= 0 then
        self.SelectedCount = 0
        return
    end
    self.SelectedCount = self.SelectedCount - 1
    self.SliderValue = (self.SelectedCount) / (self.DefaultMaxCount == 0 and 1 or self.DefaultMaxCount)
    self:RefreshSelectedInfo()
end

function M:OnClicked_Btn_Add()
    if self.SelectedCount >= self.DefaultMaxCount then
        self.SelectedCount = self.DefaultMaxCount
        return
    end
    self.SelectedCount = self.SelectedCount + 1
    self.SliderValue = (self.SelectedCount) / (self.DefaultMaxCount == 0 and 1 or self.DefaultMaxCount)
    self:RefreshSelectedInfo()
end

function M:OnPressed_Btn_Sub()
    self.LongPress_Sub = UE.UKismetSystemLibrary.K2_SetTimerDelegate(
        { self, self.LongPressedSubEvent },
        self.IntervalTime,
        true,
        self.InitialStartDelay)
end

function M:OnReleased_Btn_Sub()
    if self.LongPress_Sub then
        UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.LongPress_Sub)
        self.LongPress_Sub = nil
    end
end

function M:OnPressed_Btn_Add()
    self.LongPress_Add = UE.UKismetSystemLibrary.K2_SetTimerDelegate(
        { self, self.LongPressedAddEvent },
        self.IntervalTime,
        true,
        self.InitialStartDelay)
end

function M:OnReleased_Btn_Add()
    if self.LongPress_Add then
        UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.LongPress_Add)
        self.LongPress_Add = nil
    end
end


function M:LongPressedSubEvent()
    if self.SelectedCount <= 0 then
        if self.LongPress_Sub then
            UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.LongPress_Sub)
            self.LongPress_Sub = nil
        end
        return
    end

    self.SelectedCount = self.SelectedCount - 1
    self:RefreshSelectedInfo()
end

function M:LongPressedAddEvent()
    if self.SelectedCount >= self.DefaultMaxCount then
        if self.LongPress_Add then
            UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.LongPress_Add)
            self.LongPress_Add = nil
        end
        return
    end
    self.SelectedCount = self.SelectedCount + 1
    self:RefreshSelectedInfo()
end

function M:OnValueChanged_SliderCount(ui, value)
    print('---rate:' .. tostring(value))
    local calCount = math.floor(value)
    -- print('---calCount:' .. tostring(calCount) .. ",self.SelectedCount:" .. tostring(self.SelectedCount))
    if self.SelectedCount ~= calCount then
        self.SelectedCount = calCount
        self:RefreshSelectedInfo(true)
    end
end

return M
