require "UnLua"
require "Common.TableUtil"

local Database = require('_Game.Utils.Database')
local ActivitySystem = require('Module.Activity.ActivitySystem')
local datetime = require("_Game.Utils.datetime")
local UIUtils = require('_Game.Utils.UIUtils')
local PlayerSystem = require('Module.Player.PlayerSystem')
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_Activiy_SignIn_C
local M = Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

--构造函数
function M:Construct()
    self:InitUI()
    self:InitData()
    MessageManager:GetInstance():AddListener('OnMsg_Res_Activity_Sign', self)
end

function M:Destruct()
    MessageManager:GetInstance():RemoveListener('OnMsg_Res_Activity_Sign', self)
end 

function M:OnMsg_Res_Activity_Sign()
    self.bIsRequestReward = false
    print('---------OnMsg_Res_Activity_Sign')
    if self.LastItemUI and self.LastItemUI.get then
        self.LastItemUI:BindToAnimationFinished(self.LastItemUI.get, function()
            self:DelayShowReward()
        end)
        self.LastItemUI:PlayAnimationForward(self.LastItemUI.get, 1, false)
    end
end

function M:DelayShowReward()
    print('------------>DelayShowReward')
    --通用奖励物品弹框
    if self.CurTempDayIndex and self.CurTempDayIndex > 0 then
        local config = require('ClientDatas.d_activity')[self.ActivityId]
        local activityConfig = require('ClientDatas.d_activity_sign')[config.parameter]
        local rewardList = {}
        local reward = activityConfig['reward' .. tostring(self.CurTempDayIndex)]
        table.insert(rewardList, {
            itemId = reward[1],
            count = reward[3],
        })
        UIUtils.ShowGetRewardCommonUI(self, rewardList)
    end
    self:RefreshUI(self.ActivityId, true)
end

function M:InitUI()
    for i = 1, 7 do 
        local item = self['UI_SignInItem' .. i]
        item.Btn_Item.OnGHSClicked:Clear()
        item.Btn_Item.OnGHSClicked:Add(self, function() 
            self:OnClicked_Btn_Item(i, item)
        end)
    end
end

function M:InitData()

end

function M:InitUIEx()
    
end

function M:Tick(MyGeometry, InDeltaTime)
    if not self.TempTime then 
        self.TempTime = 0 
        self.LastTemTime = 0
    end
    self.LastTemTime = self.LastTemTime or 0
    self.TempTime = self.TempTime + InDeltaTime 
    if self.TempTime - self.LastTemTime >= 1 then
        local nowTime = PlayerSystem:GetInstance():GetServerTime()
        print('----服务器时间:' .. os.date("%Y-%m-%d %H:%M:%S", nowTime))
        self.LastTemTime = self.TempTime
    end
end

function M:RefreshUI(activity_id, noAnimation)
    self.ActivityId = activity_id
    self.ActivityInfo = ActivitySystem:GetInstance():GetServerActivityInfo(activity_id)
    self.IsGetReward = self:IsGetToDayReward()
    -- print("------>activityId:" .. tostring(activity_id))
    -- print("------>info:" .. tostring(table.dump(activity_info, false, 10)))
    local config = require('ClientDatas.d_activity')[activity_id]
    local activityConfig = require('ClientDatas.d_activity_sign')[config.parameter]
    for i = 1, 7 do
        local ui = self['UI_SignInItem' .. i]
        local rewards = activityConfig['reward' .. tostring(i)]
        local rewardItemId = rewards[1]
        local rewardItemCount = rewards[3]
        local itemConfig = UIUtils.GetItemConfigById(rewardItemId)
        --稀有度背景图片
        if itemConfig.rarityPath and itemConfig.rarityPath ~= '' then
            local strArr = string.split(itemConfig.rarityPath, '/')
            local littePath = strArr[#strArr]
            local rarityPath = string.format('/Game/_Game/%s.%s', itemConfig.rarityPath, littePath)
            local itemRarityPic = LoadObject(rarityPath)
            if itemRarityPic then
                ui.Img_Item_Bg:SetBrushFromAtlasInterface(itemRarityPic)
            end
        end
        if i ~= 7 then
            --图标
            if itemConfig.iconPath and itemConfig.iconPath ~= '' then
                local strArr = string.split(itemConfig.iconPath, '/')
                local littePath = strArr[#strArr]
                local iconResPath = string.format('/Game/_Game/%s.%s', itemConfig.iconPath, littePath)
                local iconRes = LoadObject(iconResPath)
                if iconRes then
                    ui.Img_Item_Res:SetBrushFromAtlasInterface(iconRes)
                end
            else
                ui.Img_Item_Res:SetVisibility(UE.ESlateVisibility.Collapsed)
            end

        end
       
        ui.Text_Count:SetText('x' .. tostring(rewardItemCount))

        ui.Img_Item_Res.OnMouseButtonDownEvent:Unbind()
        ui.Img_Item_Res.OnMouseButtonDownEvent:Bind(self, function()
            UIUtils.ShowItemInfo(rewardItemId, rewardItemCount)
            return UE.UWidgetBlueprintLibrary.Handled()
        end)
        

        --签到次数
        local signCount = self.ActivityInfo.activity_sign_in_info.sign_in_times
        if self.IsGetReward then
            ui.Btn_Item:SetIsEnabled(i > signCount)
            ui.Img_Get:SetVisibility((i <= signCount) and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
            ui.Img_FX:SetVisibility(UE.ESlateVisibility.Hidden)
        else
            ui.Img_FX:SetVisibility(UE.ESlateVisibility.Hidden)
            if i <= signCount then
                --已经签到过了
                ui.Btn_Item:SetIsEnabled(false)
                ui.Img_Get:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
            elseif i == signCount + 1 then 
                ui.Img_Get:SetVisibility(UE.ESlateVisibility.Hidden)
                ui.Btn_Item:SetIsEnabled(true)
                --标记特效
                ui.Img_FX:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
            else
                ui.Img_Get:SetVisibility(UE.ESlateVisibility.Hidden)
                ui.Btn_Item:SetIsEnabled(true)
            end 
        end
    end

    --剩余时间
    local config = Database.Query("d_activity", 1)
    local endTime = datetime.str_to_time(config.closeTime)
    local timeLeft = endTime - PlayerSystem:GetInstance():GetServerTime()

    self.Text_Time:SetText(datetime.format_time(timeLeft))

    if self.InitAnimation and not noAnimation then
        self:PlayAnimationForward(self.InitAnimation, 1, false)
    end
end

----------------------------------------------------------------------
---ui Event
function M:OnClicked_Btn_Item(index, ui)
    print('-----------------index:' .. tostring(index))
    local signCount = self.ActivityInfo.activity_sign_in_info.sign_in_times
    if self:IsGetToDayReward() then
        UIUtils.ShowNotify(self, Database.L10n(325))
    else--奖励还未领取
        if index == signCount + 1 then
            if self.bIsRequestReward then return end
            self.bIsRequestReward = true
            self.LastItemUI = ui
            self.CurTempDayIndex = index
            ActivitySystem:GetInstance():ReqActivitySign(self.ActivityInfo.activity_id)
        end
    end
end

--今日奖励是否已领取
function M:IsGetToDayReward()
    if self.ActivityInfo.activity_sign_in_info.last_sign_in_seconds == 0 then --从未领取过
        return false
    else
        local refreshTime = UIUtils.get_daily_refresh(self.ActivityInfo.activity_sign_in_info.last_sign_in_seconds) 
        return refreshTime <= 0 
    end
end

return M
