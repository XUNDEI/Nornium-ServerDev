--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local Client = require "Network.Client"
local UIUtils = require "_Game.Utils.UIUtils"
local Database = require("_Game.Utils.Database")
local d_gacha_vip = require "ClientDatas.d_gacha_vip"
local MallSystem = require "Module.ShopSystem.MallSystem"
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_AddUp_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

function M:OnClicked_Exit()
    self:BindToAnimationFinished(self.vfxquit, function()
        UIManager:GetInstance():RemoveUI(self)
    end)
    self:PlayAnimationForward(self.vfxquit, 1, false)
    self.Exit:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.OnClicked_Exit)
InputUtils.RegisterMouseEvent(M)

--function M:Initialize(Initializer)
--end

--function M:PreConstruct(IsDesignTime)
--end

function M:Construct()
    self.Exit.OnGHSClicked:Add(self, self.OnClicked_Exit)
    self.Visual.OnClicked:Add(self, self.OnClicked_Visual)
    self.ExplainBtn.OnGHSClicked:Add(self, self.OnClicked_Explain)
    self.HideCharge = true
    self:InitUI()
    MessageManager:GetInstance():AddListener("OnMsg_Res_Receive_Charge_Point_Reward", self)
end

function M:Destruct()
    MessageManager:GetInstance():RemoveListener("OnMsg_Res_Receive_Charge_Point_Reward", self)
end

--function M:Tick(MyGeometry, InDeltaTime)
--end

function M:InitUI() 
    local charge_point = MallSystem:GetInstance().MallInfo.charge_point_info.charge_point
    local received_charge_point_ids = MallSystem:GetInstance().MallInfo.charge_point_info.received_charge_point_ids
    local gacha_vip_infos = {}
    local received_vip_infos = {}
    local vip_infos = {}
    for charge_point_id, _ in ipairs(d_gacha_vip) do
        local charge_point_info = { charge_point_id = charge_point_id, is_received = false }
        for index, received_charge_point_id in ipairs(received_charge_point_ids) do
            if received_charge_point_id == charge_point_id then
                --已领取
                charge_point_info.is_received = true
                break
            end
        end

        if charge_point_info.is_received then
            table.insert(received_vip_infos, charge_point_info)
        else
            table.insert(vip_infos, charge_point_info)
        end
    end

    for _, charge_point_info in ipairs(vip_infos) do
        table.insert(gacha_vip_infos, charge_point_info)
    end

    for _, charge_point_info in ipairs(received_vip_infos) do
        table.insert(gacha_vip_infos, charge_point_info)
    end

    self.TextAddup:SetText(Database.L10n(479))
    if self.HideCharge then
        self.TextCharge:SetText('******')
        self.VisualOff:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        self.Visualon:SetVisibility(UE.ESlateVisibility.Hidden)
        self.ChargeNum:SetVisibility(UE.ESlateVisibility.Hidden)
        self.LevelCharge:SetVisibility(UE.ESlateVisibility.Hidden)
        self.TextVisible:SetText(Database.L10n(483))
    else
        local num = string.format("%.2f", charge_point / 10000)
        self.TextCharge:SetText('$' .. num)
        self.VisualOff:SetVisibility(UE.ESlateVisibility.Hidden)
        self.Visualon:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        self.ChargeNum:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        self.LevelCharge:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        self.TextVisible:SetText(Database.L10n(482))
    end
    self.ScrollBox:ClearChildren()
    local maxLevel = false
    for index, gacha_vip_info in ipairs(gacha_vip_infos) do
        local config = d_gacha_vip[gacha_vip_info.charge_point_id]
        local max_chargeRank = 0
        if not maxLevel then
            if charge_point < config.chargeRank then
                local num = string.format("%.2f", charge_point / 10000)
                self.CurrentLevel:SetText('$' .. num)
                num = string.format("%.2f", config.chargeRank / 10000)
                self.MaxLevel:SetText('$' .. num)
                self.LevelCharge:SetPercent(charge_point / config.chargeRank)
                maxLevel = true
            else
                if config.chargeRank > max_chargeRank then
                    max_chargeRank = config.chargeRank
                end
            end
        end
        if not maxLevel then
            local num = string.format("%.2f", charge_point / 10000)
            self.CurrentLevel:SetText('$' .. num)
            num = string.format("%.2f", max_chargeRank / 10000)
            self.MaxLevel:SetText('$' .. num)
            self.LevelCharge:SetPercent(1)
        end
        local reward_ui = UE.UWidgetBlueprintLibrary.Create(self,
            UE.UClass.Load("/Game/_Game/Blueprints/UI/UI_Mall/UI_AddUp_Reward.UI_AddUp_Reward_C"))
        local num = string.format("%.2f", config.chargeRank / 10000)
        reward_ui.TextNum:SetText(num)
        reward_ui.Receive.OnGHSClicked:Add(self, function()
            local msg = {}
            msg.charge_point_id = gacha_vip_info.charge_point_id
            Client.send("req_mall_receive_charge_point_reward", msg)
        end)

        if charge_point < config.chargeRank then
            reward_ui.Receive:SetVisibility(UE.ESlateVisibility.Hidden)
            reward_ui.TextHorizontalBox:SetVisibility(UE.ESlateVisibility.Visible)
            local str = Database.L10n(481)
            local num = string.format("%.2f", (config.chargeRank - charge_point) / 10000)
            str = string.format(str, num)
            reward_ui.TextNeedCharge:SetText(str)
            reward_ui.TextAddUp:SetText(Database.L10n(480))
        else
            local is_received = gacha_vip_info.is_received
            if is_received then
                reward_ui.ImageReward:SetVisibility(UE.ESlateVisibility.Hidden)
                reward_ui.TextReward:SetVisibility(UE.ESlateVisibility.Hidden)
                reward_ui.ImageReceive:SetVisibility(UE.ESlateVisibility.Visible)
                reward_ui.TextReceive:SetVisibility(UE.ESlateVisibility.Visible)
                reward_ui.Receive:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
            else
                reward_ui.ImageReward:SetVisibility(UE.ESlateVisibility.Visible)
                reward_ui.TextReward:SetVisibility(UE.ESlateVisibility.Visible)
                reward_ui.ImageReceive:SetVisibility(UE.ESlateVisibility.Hidden)
                reward_ui.TextReceive:SetVisibility(UE.ESlateVisibility.Hidden)
                reward_ui.Receive:SetVisibility(UE.ESlateVisibility.Visible)
            end
            
            reward_ui.TextHorizontalBox:SetVisibility(UE.ESlateVisibility.Hidden)
        end
        reward_ui.ChargePointId = gacha_vip_info.charge_point_id

        local ItemSourcePath =
        '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
        local ItemClass = UE.UClass.Load(ItemSourcePath)
        local item_num = #config.focusedReward / 3
        reward_ui.ItemBox:ClearChildren()
        for i = 1, item_num do
            local item_ui = UE.UWidgetBlueprintLibrary.Create(self, UE.UClass.Load("/Game/_Game/Blueprints/UI/UI_Shop/UI_Get_Item.UI_Get_Item_C"))
            local item_id = config.focusedReward[i * 3 - 2]
            local itemConfig = UIUtils.GetItemConfigById(item_id)
            --手动设置一下RenderOpacity 避免ui改动ItemPanel的RenderOpacity 导致出现获得物品又会先显示最后一个，然后再从第一个显示一遍
            item_ui.ItemPanel:SetRenderOpacity(0)
            if itemConfig then
                item_ui.ItemPanel:SetRenderOpacity(1)
                item_ui.TextName:SetText(Database.L10n(itemConfig.itemName))
                item_ui.TextNum:SetText(config.focusedReward[i * 3])
                reward_ui.ItemBox:AddChild(item_ui)

                --稀有度背景图片
                if itemConfig.rarityPath and itemConfig.rarityPath ~= '' then
                    local strArr = string.split(itemConfig.rarityPath, '/')
                    local littePath = strArr[#strArr]
                    local rarityPath = string.format('/Game/_Game/TP_New/Common/Frames/%s.%s', littePath, littePath)
                    local itemRarityPic = LoadObject(rarityPath)
                    if itemRarityPic then
                        item_ui.container_icon_res:SetBrushFromAtlasInterface(itemRarityPic)
                    end
                end
    
                --icon
                if itemConfig.iconPath and itemConfig.iconPath ~= '' then
                    local strArr = string.split(itemConfig.iconPath, '/')
                    local littePath = strArr[#strArr]
                    local iconResPath = string.format('/Game/_Game/%s.%s', itemConfig.iconPath, littePath)
                    local iconRes = LoadObject(iconResPath)
                    if iconRes then
                        item_ui.icon_res:SetBrushFromAtlasInterface(iconRes)
                    end
                end

                item_ui.Img_bg.OnMouseButtonDownEvent:Unbind()
                item_ui.Img_bg.OnMouseButtonDownEvent:Bind(self, function(self, MyGeometry, MouseEvent)
                    if UE.UKismetInputLibrary.PointerEvent_IsMouseButtonDown(MouseEvent, UE.EKeys.LeftMouseButton) then
                        UIUtils.ShowItemInfo(item_id)
                    end
                    return UE.UWidgetBlueprintLibrary.Handled()
                end)
            end
        end

        item_num = #config.normalReward / 3
        for i = 1, item_num do
            local item_ui = UE.UWidgetBlueprintLibrary.Create(self, UE.UClass.Load("/Game/_Game/Blueprints/UI/UI_Shop/UI_Get_Item.UI_Get_Item_C"))
            local item_id = config.normalReward[i * 3 - 2]
            local itemConfig = UIUtils.GetItemConfigById(item_id)
            --手动设置一下RenderOpacity 避免ui改动ItemPanel的RenderOpacity 导致出现获得物品又会先显示最后一个，然后再从第一个显示一遍
            item_ui.ItemPanel:SetRenderOpacity(0)
            if itemConfig then
                item_ui.ItemPanel:SetRenderOpacity(1)
                item_ui.TextName:SetText(Database.L10n(itemConfig.itemName))
                item_ui.TextNum:SetText(config.normalReward[i * 3])
                reward_ui.ItemBox:AddChild(item_ui)

                --稀有度背景图片
                if itemConfig.rarityPath and itemConfig.rarityPath ~= '' then
                    local strArr = string.split(itemConfig.rarityPath, '/')
                    local littePath = strArr[#strArr]
                    local rarityPath = string.format('/Game/_Game/TP_New/Common/Frames/%s.%s', littePath, littePath)
                    local itemRarityPic = LoadObject(rarityPath)
                    if itemRarityPic then
                        item_ui.container_icon_res:SetBrushFromAtlasInterface(itemRarityPic)
                    end
                end
    
                --icon
                if itemConfig.iconPath and itemConfig.iconPath ~= '' then
                    local strArr = string.split(itemConfig.iconPath, '/')
                    local littePath = strArr[#strArr]
                    local iconResPath = string.format('/Game/_Game/%s.%s', itemConfig.iconPath, littePath)
                    local iconRes = LoadObject(iconResPath)
                    if iconRes then
                        item_ui.icon_res:SetBrushFromAtlasInterface(iconRes)
                    end
                end

                item_ui.Img_bg.OnMouseButtonDownEvent:Unbind()
                item_ui.Img_bg.OnMouseButtonDownEvent:Bind(self, function(self, MyGeometry, MouseEvent)
                    if UE.UKismetInputLibrary.PointerEvent_IsMouseButtonDown(MouseEvent, UE.EKeys.LeftMouseButton) then
                        UIUtils.ShowItemInfo(item_id)
                    end
                    return UE.UWidgetBlueprintLibrary.Handled()
                end)
            end
        end
        self.ScrollBox:AddChild(reward_ui)
    end
    self:UnbindAllFromAnimationFinished(self.vfxin)
    self:BindToAnimationFinished(self.vfxin, function()
        self:PlayItemAnim()
    end)
    self:PlayAnimationForward(self.vfxin, 1, false)

    local currency_data = {
        9001,
        9002,
    }
    self.UI_Money:RefreshData(currency_data)
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.OnClicked_Exit)

function M:OnClicked_Visual()
    self.HideCharge = not self.HideCharge
    local charge_point = MallSystem:GetInstance().MallInfo.charge_point_info.charge_point
    if self.HideCharge then
        self.TextCharge:SetText('******')
        self.VisualOff:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        self.Visualon:SetVisibility(UE.ESlateVisibility.Hidden)
        self.ChargeNum:SetVisibility(UE.ESlateVisibility.Hidden)
        self.LevelCharge:SetVisibility(UE.ESlateVisibility.Hidden)
        self.TextVisible:SetText(Database.L10n(483))
    else
        local num = string.format("%.2f", charge_point / 10000)
        self.TextCharge:SetText('$' .. num)
        self.VisualOff:SetVisibility(UE.ESlateVisibility.Hidden)
        self.Visualon:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        self.ChargeNum:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        self.LevelCharge:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        self.TextVisible:SetText(Database.L10n(482))
    end
end

function M:OnClicked_Explain()
    UIUtils.ShowSystemDes(1007)
end

function M:OnMsg_Res_Receive_Charge_Point_Reward(charge_point_id)
    print("======OnMsg_Res_Receive_Charge_Point_Reward:" .. charge_point_id)
    local config = d_gacha_vip[charge_point_id]
    local children = self.ScrollBox:GetAllChildren()
    for idx = 1, children:Length() do
        local widget = children:Get(idx)
        if widget.ChargePointId == charge_point_id then
            widget.ImageReward:SetVisibility(UE.ESlateVisibility.Hidden)
            widget.TextReward:SetVisibility(UE.ESlateVisibility.Hidden)
            widget.ImageReceive:SetVisibility(UE.ESlateVisibility.Visible)
            widget.TextReceive:SetVisibility(UE.ESlateVisibility.Visible)
            widget.Receive:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
        end
    end

    if config then
        local reward_items = {}
        local item_num = #config.focusedReward / 3
        for i = 1, item_num do
            table.insert(reward_items, { item_id = config.focusedReward[i * 3 - 2], count = config.focusedReward[i * 3] })
        end
        
        item_num = #config.normalReward / 3
        for i = 1, item_num do
            table.insert(reward_items, { item_id = config.normalReward[i * 3 - 2], count = config.normalReward[i * 3] })
        end

        self.UI_GetItem_Notice = UE.UGameplayStatics.GetGameInstance(self):AddUMG('UI_GetItem_Notice')
        self.UI_GetItem_Notice:RefreshUI(reward_items)
    end
    self:InitUI()
end

return M
