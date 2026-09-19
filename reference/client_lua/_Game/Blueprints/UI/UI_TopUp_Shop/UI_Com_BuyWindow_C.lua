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
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

local NoticeType = 
{
    NotHasChar = 458,
    FullChar = 459,
}

---@type M
local M = Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

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
    print("====Buy:" .. tostring(table.dump(itemData)))
    
    self.ItemData = itemData
    local count = UIUtils.GetItemCount(self.ItemData.item_config.id)
    self.Text_Count:SetText(count)
    self.Text_ItemName:SetText(self.ItemData and Database.L10n(self.ItemData.item_config.itemName) or "未知")
    local desc
    if itemData.item_config.itemType == 10 then
        desc = UIUtils.GetWeaponSkillDesc(itemData.item_config.id, 1)
    else
        desc = Database.L10n(self.ItemData.item_config.effectDesc)
    end
    self.Text_ItemDes:SetText(self.ItemData and desc or "无")

    self.DefaultMaxCount = self.ItemData.count < 1 and 1 or (self.ItemData.count - 1)
    
    self.SelectedCount = 1
    self.SliderValue = 0
    self.ship_ProgressBar:SetPercent(0)

    --稀有度背景图片
    if itemData.item_config.rarityPath and itemData.item_config.rarityPath ~= '' then
        local strArr = string.split(itemData.item_config.rarityPath, '/')
        local littePath = strArr[#strArr]
        local rarityPath = string.format('/Game/_Game/%s.%s', itemData.item_config.rarityPath, littePath)
        local itemRarityPic = LoadObject(rarityPath)
        if itemRarityPic then
            self.iconbox_res:SetBrushFromAtlasInterface(itemRarityPic)
        end
    end

    --icon
    if itemData.item_config.iconPath and itemData.item_config.iconPath ~= '' then
        self.item_res:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        local strArr = string.split(itemData.item_config.iconPath, '/')
        local littePath = strArr[#strArr]
        local iconResPath = string.format('/Game/_Game/%s.%s', itemData.item_config.iconPath, littePath)
        local iconRes = LoadObject(iconResPath)
        if iconRes then
            self.item_res:SetBrushFromAtlasInterface(iconRes)
        end
    else
        self.item_res:SetVisibility(UE.ESlateVisibility.Collapsed)
    end

    if self.DefaultMaxCount == 0 then
        self.SliderValue = 1
        self.ship_ProgressBar:SetPercent(1)
        self.Slider_SelectedCount:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        self.Text_SelectedCount:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    else
        self.Slider_SelectedCount:SetVisibility(UE.ESlateVisibility.Visible)
        self.Text_SelectedCount:SetVisibility(UE.ESlateVisibility.Visible)
    end

    local hasGold = UIUtils.GetItemCount(itemData.config.currency)
    if hasGold >= itemData.config.price[1] then
        self.Btn_Certain:SetRenderOpacity(1)
        self.Btn_Certain:SetVisibility(UE.ESlateVisibility.Visible)
    else
        self.Btn_Certain:SetRenderOpacity(0.5)
        self.Btn_Certain:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
    end

    self:RefreshSelectedInfo()
end

function M:RefreshSelectedInfo()
    self.bIsSetText = true
    self.Text_SelectedCount:SetText(self.SelectedCount)
    self.bIsSetText = false
    self.Slider_SelectedCount:SetValue(self.SliderValue)
    self.ship_ProgressBar:SetPercent(self.SliderValue)
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

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.OnClicked_Btn_Cancel)

function M:OnClicked_Btn_Certain()
    if self.ItemData.noticeType then
        UIManager:GetInstance():RemoveUI(self)
        UIUtils.ShowComNotice(Database.L10n(self.ItemData.noticeType), self, 
            function()
                local msg = {}
                msg.mall_id = self.ItemData.mall_id
                msg.mall_item_id = self.ItemData.mall_item_id
                msg.mall_item_count = self.SelectedCount
                msg.last_auto_refresh_seconds = self.ItemData.last_auto_refresh_seconds
                msg.steam_id = self.ItemData.steam_id
                msg.steam_current_game_language = self.ItemData.steam_current_game_language
                Client.send("req_mall_buy", msg)
                UIManager:GetInstance():RemoveUI(self)
                print("======点击购买:" .. tostring(msg))
            end,
            function()
            end)
    else
        local msg = {}
        msg.mall_id = self.ItemData.mall_id
        msg.mall_item_id = self.ItemData.mall_item_id
        msg.mall_item_count = self.SelectedCount
        msg.last_auto_refresh_seconds = self.ItemData.last_auto_refresh_seconds
        msg.steam_id = self.ItemData.steam_id
        msg.steam_current_game_language = self.ItemData.steam_current_game_language
        Client.send("req_mall_buy", msg)
        UIManager:GetInstance():RemoveUI(self)
        print("======点击购买:" .. tostring(msg))
    end
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Confirm, UE.ETriggerEvent.Completed, M.OnClicked_Btn_Certain)

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
        forceRefreshText = cnt
    else
        cnt = tonum
    end

    self.SelectedCount = cnt
    self.SliderValue = (self.SelectedCount - 1) / (self.DefaultMaxCount)
    self.ship_ProgressBar:SetPercent(self.SliderValue)
    self.Slider_SelectedCount:SetValue(self.SliderValue)
    if forceRefreshText then
        self.bIsSetText = true
        self.Text_SelectedCount:SetText(self.SelectedCount)
        self.bIsSetText = false
    end
end

function M:OnValueChanged_SliderCount(ui, value)
    self.SelectedCount = math.floor(self.DefaultMaxCount * value + 1 / self.ItemData.count) + 1
    self.SliderValue = value --self.SelectedCount / self.ItemData.count
    self.bIsSetText = true
    self.Text_SelectedCount:SetText(self.SelectedCount)
    self.bIsSetText = false
    self.ship_ProgressBar:SetPercent(value)
end

return M
