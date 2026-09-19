--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

require "UnLua"
require "Common.TableUtil"

local Client = require "Network.Client"
local UIUtils = require "_Game.Utils.UIUtils"
local Database = require "_Game.Utils.Database"
local BackpackSystem = require("Module.Backpack.BackpackSystem")

---@type M
local M = Class()

--构造函数
function M:Construct()
    self:InitUI()
end

function M:Destruct()
    if self.LongPress_Sub then
        UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.LongPress_Sub)
        self.LongPress_Sub = nil
    end
    if self.LongPress_Add then
        UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.LongPress_Add)
        self.LongPress_Add = nil
    end
end

function M:InitUI()
    self.Btn_Cancel.OnGHSClicked:Add(self, self.OnClicked_Btn_Cancel)
    self.Btn_Certain.OnGHSClicked:Add(self, self.OnClicked_Btn_Certain)

    --普通点击
    self.Btn_Sub.OnGHSClicked:Add(self, self.OnClicked_Btn_Sub)
    self.Btn_Add.OnGHSClicked:Add(self, self.OnClicked_Btn_Add)
    --长按
    self.Btn_Sub.OnGHSPressed:Add(self, self.OnPressed_Btn_Sub)
    self.Btn_Sub.OnGHSReleased:Add(self, self.OnReleased_Btn_Sub)
    self.Btn_Add.OnGHSPressed:Add(self, self.OnPressed_Btn_Add)
    self.Btn_Add.OnGHSReleased:Add(self, self.OnReleased_Btn_Add)

    --self.Text_SelectedCount.OnTextChanged:Add(self, self.OnTextCommitted_Text_SelectedCount)
    self.Text_SelectedCount.OnTextCommitted:Add(self, self.OnTextCommitted_Text_SelectedCount)

    self.Slider_SelectedCount.OnGHSValueChanged:Add(self, self.OnValueChanged_SliderCount)
end

function M:RefreshUI(itemData)
    print("====Use:" .. tostring(table.dump(itemData)))

    self.ItemData = itemData

    self.Text_Count:SetText(itemData and itemData.count or "1")
    self.Text_ItemName:SetText(itemData and Database.L10n(itemData.config.itemName) or "未知")
    self.Text_ItemDes:SetText(itemData and Database.L10n(itemData.config.effectDesc) or "无")

    self.DefaultMaxCount = self.ItemData.count < 1 and 1 or (self.ItemData.count - 1)

    self.SelectedCount = 1
    self.SliderValue = 0 --self.SelectedCount / self.ItemData.count

    --稀有度背景图片
    if itemData.config.rarityPath and itemData.config.rarityPath ~= '' then
        local strArr = string.split(itemData.config.rarityPath, '/')
        local littePath = strArr[#strArr]
        local rarityPath = string.format('/Game/_Game/%s.%s', itemData.config.rarityPath, littePath)
        local itemRarityPic = LoadObject(rarityPath)
        if itemRarityPic then
            self.iconbox_res:SetBrushFromAtlasInterface(itemRarityPic)
        end
    end

    --icon
    if itemData.config.iconPath and itemData.config.iconPath ~= '' then
        self.item_res:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        local strArr = string.split(itemData.config.iconPath, '/')
        local littePath = strArr[#strArr]
        local iconResPath = string.format('/Game/_Game/%s.%s', itemData.config.iconPath, littePath)
        local iconRes = LoadObject(iconResPath)
        if iconRes then
            self.item_res:SetBrushFromAtlasInterface(iconRes)
        end
    else
        self.item_res:SetVisibility(UE.ESlateVisibility.Collapsed)
    end

    self:RefreshSelectedInfo()
end

function M:RefreshSelectedInfo()
    self.bIsSetText = true
    self.Text_SelectedCount:SetText(self.SelectedCount)
    self.bIsSetText = false
    self.Slider_SelectedCount:SetValue(self.SliderValue)
end

function M:LongPressedSubEvent()
    if self.SelectedCount <= 1 then
        if self.LongPress_Sub then
            UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.LongPress_Sub)
            self.LongPress_Sub = nil
        end
        return
    end

    self.SelectedCount = self.SelectedCount - 1
    self.SliderValue = (self.SelectedCount - 1) / (self.DefaultMaxCount)
    self:RefreshSelectedInfo()
end

function M:LongPressedAddEvent()
    if self.SelectedCount >= self.ItemData.count then
        if self.LongPress_Add then
            UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.LongPress_Add)
            self.LongPress_Add = nil
        end
        return
    end
    self.SelectedCount = self.SelectedCount + 1
    self.SliderValue = (self.SelectedCount - 1) / (self.DefaultMaxCount)
    self:RefreshSelectedInfo()
end

----------------------------------------------------------------------
---
function M:OnClicked_Btn_Cancel()
    UIManager:GetInstance():RemoveUI(self)
end

function M:OnClicked_Btn_Certain()
    print("======使用道具:" .. tostring(self.SelectedCount))
    UIManager:GetInstance():RemoveUI(self)

    local msg = {}
    msg.item_uuid = self.ItemData.item_uuid
    msg.count = self.SelectedCount
    BackpackSystem:GetInstance():CachedUseItem(self.ItemData, true)
    Client.send("req_use_item", msg)
end

function M:OnClicked_Btn_Sub()
    if self.SelectedCount == 1 then return end
    self.SelectedCount = self.SelectedCount - 1
    self.SliderValue = (self.SelectedCount - 1) / (self.DefaultMaxCount)
    self:RefreshSelectedInfo()
end

function M:OnClicked_Btn_Add()
    if self.SelectedCount == self.ItemData.count then return end
    self.SelectedCount = self.SelectedCount + 1
    self.SliderValue = (self.SelectedCount - 1) / (self.DefaultMaxCount)
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

function M:OnTextCommitted_Text_SelectedCount(Text, CommitMethod)
    if self.bIsSetText or self.bIsSliderChanged then return end
    local cnt = 1
    local forceRefreshText = false
    local tonum = tonumber(Text)
    if not tonum or tonum < 1 then
        cnt = 1
        forceRefreshText = true
    elseif tonum > self.ItemData.count then
        cnt = self.ItemData.count
        forceRefreshText = count
    else
        cnt = tonum
    end

    self.SelectedCount = cnt
    self.SliderValue = (self.SelectedCount - 1) / (self.DefaultMaxCount)
    self.Slider_SelectedCount:SetValue(self.SliderValue)
    if forceRefreshText then
        self.bIsSetText = true
        self.Text_SelectedCount:SetText(self.SelectedCount)
        self.bIsSetText = false
    end
end

function M:OnValueChanged_SliderCount(ui, value)
    self.SelectedCount = math.floor(self.DefaultMaxCount * value) + 1
    self.SliderValue = value --self.SelectedCount / self.ItemData.count
    self.bIsSetText = true
    self.Text_SelectedCount:SetText(self.SelectedCount)
    self.bIsSetText = false
end

return M
