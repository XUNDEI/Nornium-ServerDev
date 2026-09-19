local UIUtils = require "_Game.Utils.UIUtils"
local Database = require("_Game.Utils.Database")
local CharacterSystem = require "Module.CharacterSystem.CharacterSystem"
local MessageManager = require "Framework.Updater.MessageManager"
local Client = require("Network.Client")
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"
local PlayerSystem = require('Module.Player.PlayerSystem')

---@type UI_Panel_Equip_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Cursor,
    InputAssets.IMC_UI_Common,
}

InputUtils.RegisterMouseEvent(M)

function M:Construct()
    self:InitData()
    self:InitUI()
    MessageManager:GetInstance():AddListener("OnMsg_Req_Character_Talent_Active_Success", self)
    MessageManager:GetInstance():AddListener("OnMsg_Ntf_Item_Info", self)
end

function M:Destruct()
    MessageManager:GetInstance():RemoveListener("OnMsg_Req_Character_Talent_Active_Success", self)
    MessageManager:GetInstance():RemoveListener("OnMsg_Ntf_Item_Info", self)
end

function M:InitData()
    
end

function M:OnMsg_Req_Character_Talent_Active_Success()
    self.bIsAnimWaiting = true
    self.TeamModelTimerHander1 = UE.UKismetSystemLibrary.K2_SetTimerDelegate(
        { self, self.DelayPlayAnimation }, 
        1, 
        false
    )
end

function M:OnMsg_Ntf_Item_Info(itemList)
    if self.TalentConfig.openNeed == UIUtils.EOpenNeedType.CostItem then
        local bNeedRefresh = false
        for i = 1, #self.TalentConfig.openNeedPrice, 2 do 
            local itemId = self.TalentConfig.openNeedPrice[i]
            for _, v in pairs(itemList) do
                if v.item_id == itemId then
                    bNeedRefresh = true
                    break
                end
            end
            if bNeedRefresh then
                break
            end
        end
        if bNeedRefresh then
            self:RefreshMatrial()
        end
    end
end

function M:DelayPlayAnimation()
    local ui = UE4.UGameplayStatics.GetGameInstance(self):AddUMG('UI_Talent_Tips')
    ui:RefreshUI(self.CharId, self.TalentConfig.inbornEffect, self.RewardInfoList)

    self.bIsAnimWaiting = false
    --self:RefreshPos(UE.FVector2D(-10000, -10000), UE.FVector2D(0, 0))
    UIManager:GetInstance():RemoveUI(self)
end

function M:InitUI()
    self.Btn_Close.OnGHSClicked:Add(self, self.OnClicked_Btn_Close)
    self.Btn_Active.OnGHSClicked:Add(self, self.OnClicked_Btn_Active)

    self.ListView_Condition.BP_OnEntryInitialized:Clear()
    self.ListView_Condition.BP_OnEntryInitialized:Add(self, function(wbp, itemData, widget) 
        self:BP_OnEntryInitialized_Condition(itemData, widget)
    end)
    self.ListView_Material.BP_OnEntryInitialized:Clear()
    self.ListView_Material.BP_OnEntryInitialized:Add(self, function(wbp, itemData, widget) 
        self:BP_OnEntryInitialized_Material(itemData, widget)
    end)
    self.ListView_Material.BP_OnItemClicked:Clear()
    self.ListView_Material.BP_OnItemClicked:Add(self, function(wbp, itemData)
        self:BP_OnItemClicked_Material(itemData)
    end)

    self.ListView_Reward.BP_OnEntryInitialized:Clear()
    self.ListView_Reward.BP_OnEntryInitialized:Add(self, function(wbp, itemData, widget)
        self:BP_OnEntryInitialized_Reward(itemData, widget)
    end)
    self.ListView_Reward.BP_OnItemClicked:Clear()
    self.ListView_Reward.BP_OnItemClicked:Add(self, function(wbp, itemData)
        self:BP_OnItemClicked_Reward(itemData)
    end)
end

function M:RefreshUI(backUI, character_id, talentId)
    --print("===talentId:" .. tostring(talentId))
    self.BackUI = backUI
    self.CharId = character_id
    self.CharInfo = CharacterSystem:GetInstance():GetCharacterInfoById(character_id)
    self.InitTalentId = talentId
    self.TalentConfig = UIUtils.GetTalentConfig(talentId, character_id)

    --icon
    if self.TalentConfig.inbornIcon and self.TalentConfig.inbornIcon ~= '' then
        local iconPath = string.format("Texture2D'/Game/_Game/TP_New/Character_inborn/Frames/%s_png.%s_png'", self.TalentConfig.inbornIcon, self.TalentConfig.inbornIcon)
        local iconTexture = LoadObject(iconPath)
        if iconTexture then
            self.Img_Icon:SetBrushFromAtlasInterface(iconTexture)
        end
    end
    --名字/描述
    self.Text_Name:SetText(Database.L10n(self.TalentConfig.inbornName))
    --self.Text_Name2:SetText(Database.L10n(self.TalentConfig.inbornName))
    self.Text_Des:SetText(Database.L10n(self.TalentConfig.inbornDesc))

    --是否已经激活
    self.IsActived = self:TalentIsActive(self.InitTalentId)
    self.Panel_Actived:SetVisibility(self.IsActived and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
    self.Panel_Getted:SetVisibility(self.IsActived and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
    self.Panel_Need:SetVisibility(self.IsActived and UE.ESlateVisibility.Collapsed or UE.ESlateVisibility.SelfHitTestInvisible)

    --获取奖励道具信息
    self.RewardInfoList = UIUtils.GetTalentEffect(self.TalentConfig.inbornEffect, self.TalentConfig.inbornEffectPrice)
    print("======RewardInfoList:" .. tostring(table.dump(self.RewardInfoList, nil, false)))

    --判断奖励类型
    --self.Panel_Des:SetVisibility(self.TalentConfig.inbornEffect == UIUtils.CharTalentEffectType.Item and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.SelfHitTestInvisible)
    --self.Panel_Reward:SetVisibility(self.TalentConfig.inbornEffect == UIUtils.CharTalentEffectType.Item and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
    self.WidgetSwitcher:SetActiveWidgetIndex(self.TalentConfig.inbornEffect == UIUtils.CharTalentEffectType.Item and 1 or 0)
    if self.TalentConfig.inbornEffect == UIUtils.CharTalentEffectType.Item then
        local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
        local ItemClass = UE.UClass.Load(ItemSourcePath)
        local attrDataSource = {}
        for i = 1, #self.RewardInfoList do
            local itemData = NewObject(ItemClass)
            itemData.Index = i
            itemData.ItemId = self.RewardInfoList[i].item_id
            table.insert(attrDataSource, itemData)
        end
        self.ListView_Reward:ClearListItems()
        self.ListView_Reward:BP_SetListItems(attrDataSource)
    end

    self:RefreshMatrial()
    
    

    self:PlayAnimationForward(self.InitAnimation, 1, false)
end

function M:RefreshMatrial()
    --激活条件判定
    local isFull, tips, exInfo = UIUtils.GetTalentUnlock(self.CharId, self.TalentConfig.openNeed, self.TalentConfig.openNeedPrice, self.TalentConfig.inbornNeedTxt)
    self.ActiveAllItemList = tips
    self.MoneyItemList = exInfo
    --print("======ActiveAllItemList:" .. tostring(table.dump(self.ActiveAllItemList, nil, false)))
    --print("======MoneyItemList:" .. tostring(table.dump(self.MoneyItemList, nil, false)))
    --判断激活类型
    if not self.IsActived then
        self.Panel_Cost:SetVisibility(UE.ESlateVisibility.Hidden)
        if self.TalentConfig.openNeed == UIUtils.EOpenNeedType.CostItem then
            local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
            local ItemClass = UE.UClass.Load(ItemSourcePath)
            local attrDataSource = {}
            for i = 1, #self.ActiveAllItemList do
                local itemData = NewObject(ItemClass)
                itemData.Index = i
                itemData.ItemId = self.ActiveAllItemList[i].item_id
                table.insert(attrDataSource, itemData)
            end
            self.ListView_Material:ClearListItems()
            self.ListView_Material:BP_SetListItems(attrDataSource)
            --货币类型判断
            if #self.MoneyItemList > 0 then
                self.Panel_Cost:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
                local moneyItem = self.MoneyItemList[1]
                --货币图片
                local iconResPath = string.format('/Game/_Game/TP_New/Common/Frames/Icon_%d_png.Icon_%d_png', moneyItem.config.id, moneyItem.config.id)
                local iconRes = LoadObject(iconResPath)
                if iconRes then
                    self.Image_202:SetBrushFromAtlasInterface(iconRes)
                end
                moneyItem.hasCount = UIUtils.GetItemCount(moneyItem.item_id)
                local textColor = UE.FSlateColor()
                textColor.SpecifiedColor = moneyItem.hasCount >= moneyItem.count and UE.FLinearColor(1.0, 1.0, 1.0, 1.0) or UE.FLinearColor(1.0, 0.0, 0.0, 1.0)
                self.Text_HaveGold:SetColorAndOpacity(textColor)
                self.Text_HaveGold:SetText("/" .. moneyItem.hasCount)
                self.Text_NeedGold:SetText(moneyItem.count)
            else
                self.Panel_Cost:SetVisibility(UE.ESlateVisibility.Hidden)
            end
    
            self.ListView_Condition:SetVisibility(UE.ESlateVisibility.Hidden)
            self.ListView_Material:SetVisibility(UE.ESlateVisibility.Visible)
        else
            local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
            local ItemClass = UE.UClass.Load(ItemSourcePath)
            local attrDataSource = {}
            for i = 1, #self.ActiveAllItemList do
                local itemData = NewObject(ItemClass)
                itemData.Index = i
                itemData.ItemId = self.ActiveAllItemList[i].item_id
                table.insert(attrDataSource, itemData)
            end
            self.ListView_Condition:ClearListItems()
            self.ListView_Condition:BP_SetListItems(attrDataSource)
    
            
            self.ListView_Condition:SetVisibility(UE.ESlateVisibility.Visible)
            self.ListView_Material:SetVisibility(UE.ESlateVisibility.Hidden)
        end
    end

    local prevIsActive = self:PrevTalentIsActive(self.InitTalentId, self.CharId)
    --self.Text_Actived:SetVisibility(self.IsActived and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
    self.Btn_Active:SetVisibility(self.IsActived and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.Visible)
    self.Btn_Active:SetIsEnabled(isFull and prevIsActive)
end

function M:RefreshPos(touchPos, offset, uiSize)
    self.UISize = uiSize
    self.LastTouchPos = touchPos
    self.LastOffset = offset
    self:DelayRefreshPos()
end

function M:RefreshContentPos()
    local size = UE.USlateBlueprintLibrary.GetLocalSize(self.Panel_Content:GetCachedGeometry())
    if size.X == 0 and size.Y == 0 then
        size.X = 500
        size.Y = 750
    end
    local touchX = self.LastTouchPos.X
    if (touchX) >= (self.UISize.X - size.X) then
        touchX = touchX - size.X 
    else
        touchX = touchX + self.LastOffset.X
    end
    local touchY = self.LastTouchPos.Y 
    if touchY <= (size.Y / 2) then
        touchY = 0
    elseif (touchY) >= (self.UISize.Y - size.Y / 2) then
        touchY = self.UISize.Y - size.Y 
    else
        touchY = touchY - size.Y / 2 
    end
    local newPos = UE.FVector2D(touchX, touchY)
    local slot = UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(self.Panel_Content)
    slot:SetPosition(newPos)
    self:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
end

----------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------
---
function M:OnClicked_Btn_Active()
    local SrpgController = require('Module.Srpg.SrpgController')
    if SrpgController:GetInstance():HasPendingFight() then
        UIUtils.ShowNotify(self, Database.L10n(285))
        return
    end

    local now = PlayerSystem:GetInstance():GetServerTime()
    if not self.LastClickGachaTenTime then 
        self.LastClickGachaTenTime = now - 1
    end
    if now - self.LastClickGachaTenTime < 0.5 then
        print('------点击太快') 
        return 
    end
    self.LastClickGachaTenTime = now
    if CharacterSystem:GetInstance().CachedTalentCharId and CharacterSystem:GetInstance().CachedTalentCharId > 0 then
        print('------点击太快') 
        return 
    end

    if self.bIsAnimWaiting then 
        print('------点击太快') 
        return
    end

    print("====激活天赋:" .. tostring(self.InitTalentId))
    if self.TalentConfig.openNeed == UIUtils.EOpenNeedType.CostItem then 
        CharacterSystem:GetInstance():CacheTalentInfo(self.CharInfo.character_id, self.InitTalentId, self.ActiveAllItemList, self.MoneyItemList)
    else
        CharacterSystem:GetInstance():CacheTalentInfo(self.CharInfo.character_id, self.InitTalentId)
    end
    local msg = {
        character_id = self.CharId,
        talent_id = self.InitTalentId
    }
    Client.send("req_character_unlock_talent", msg)
end

function M:OnClicked_Btn_Close()
    UIManager:GetInstance():RemoveUI(self)
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.OnClicked_Btn_Close)

function M:BP_OnEntryInitialized_Condition(data, ui)
    local itemData = self.ActiveAllItemList[data.Index]
    --ui.Text_Index:SetText(itemData.Index)
    ui.Img_Ok:SetVisibility(itemData.isUnlock and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
    ui.Img_Fail:SetVisibility(not itemData.isUnlock and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
    ui.Text_Title:SetText(itemData.tip)
    ui.CHKBox:SetIsChecked(itemData.isUnlock)
end

function M:BP_OnEntryInitialized_Material(data, ui)
    local itemData = self.ActiveAllItemList[data.Index]

    --稀有度背景图片
    if itemData.config.rarityPath and itemData.config.rarityPath ~= '' then
        local strArr = string.split(itemData.config.rarityPath, '/')
        local littePath = strArr[#strArr]
        local rarityPath = string.format('/Game/_Game/%s.%s', itemData.config.rarityPath, littePath)
        local itemRarityPic = LoadObject(rarityPath)
        if itemRarityPic then
            ui.wp_container_icon_res:SetBrushFromAtlasInterface(itemRarityPic)
        end
    end

    itemData.hasCount = UIUtils.GetItemCount(itemData.item_id)
    local hasMat = itemData.hasCount > 0
    if hasMat then
        ui.lackState:SetVisibility(UE.ESlateVisibility.Hidden)
    else
        ui.lackState:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    end

    if itemData.config.iconPath and itemData.config.iconPath ~= '' then
        local strArr = string.split(itemData.config.iconPath, '/')
        local littePath = strArr[#strArr]
        local iconResPath = string.format('/Game/_Game/%s.%s', itemData.config.iconPath, littePath)
        local iconRes = LoadObject(iconResPath)
        if iconRes then
            ui.wp_icon_res:SetBrushFromAtlasInterface(iconRes)
        end
    end
   
    
    --选中个数
    local textColor = UE.FSlateColor()
    textColor.SpecifiedColor = itemData.hasCount >= itemData.count and UE.FLinearColor(0.0, 0.0, 0.0, 1.0) or UE.FLinearColor(1.0, 0.0, 0.0, 1.0)
    ui.Text_Count:SetColorAndOpacity(textColor)
    ui.Text_Count:SetText(itemData.hasCount .. "/" .. itemData.count)
end

function M:BP_OnItemClicked_Material(data)
    local itemData = self.ActiveAllItemList[data.Index]
    --print("===item:" .. tostring(table.dump(itemData, nil, 10)))
    UIUtils.ShowItemInfo(itemData.item_id, itemData.hasCount)
end

function M:BP_OnEntryInitialized_Reward(data, ui)
    local itemData = self.RewardInfoList[data.Index]

    --稀有度背景图片
    if itemData.config.rarityPath and itemData.config.rarityPath ~= '' then
        local strArr = string.split(itemData.config.rarityPath, '/')
        local littePath = strArr[#strArr]
        local rarityPath = string.format('/Game/_Game/%s.%s', itemData.config.rarityPath, littePath)
        local itemRarityPic = LoadObject(rarityPath)
        if itemRarityPic then
            ui.wp_container_icon_res:SetBrushFromAtlasInterface(itemRarityPic)
        end
    end

    local hasMat = itemData.value > 0
    if hasMat then
        ui.lackState:SetVisibility(UE.ESlateVisibility.Hidden)
        ui.wp_icon_res:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        --icon
        if itemData.config.iconPath and itemData.config.iconPath ~= '' then
            local strArr = string.split(itemData.config.iconPath, '/')
            local littePath = strArr[#strArr]
            local iconResPath = string.format('/Game/_Game/%s.%s', itemData.config.iconPath, littePath)
            local iconRes = LoadObject(iconResPath)
            if iconRes then
                ui.wp_icon_res:SetBrushFromAtlasInterface(iconRes)
            end
        end
    else
        ui.wp_icon_res:SetVisibility(UE.ESlateVisibility.Hidden)
        ui.lackState:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        --icon
        if itemData.config.iconPath and itemData.config.iconPath ~= '' then
            local strArr = string.split(itemData.config.iconPath, '/')
            local littePath = strArr[#strArr]
            local iconResPath = string.format('/Game/_Game/%s.%s', itemData.config.iconPath, littePath)
            local iconRes = LoadObject(iconResPath)
            if iconRes then
                ui.lackIcon:SetBrushFromAtlasInterface(iconRes)
            end
        end
    end
   
    --个数
    ui.Text_Count:SetText(itemData.value)
end

function M:BP_OnItemClicked_Reward(data)
    local itemData = self.RewardInfoList[data.Index] 
    --print("===reward:" .. tostring(table.dump(itemData, nil, 10)))
    UIUtils.ShowItemInfo(itemData.id, itemData.value)
end

----------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------
---
function M:TalentIsActive(talent_id)
    if self.CharInfo.talent_ids then
        for _, talentId in ipairs(self.CharInfo.talent_ids) do
            if talentId == talent_id then
                return true
            end
        end
    end
    return false
end

function M:PrevTalentIsActive(talent_id, character_id)
    local talentConfig = UIUtils.GetTalentConfig(talent_id, character_id)
    --print("===frontHole:" .. tostring(talentConfig.frontHole))
    if talentConfig.frontHole == 0 then
        return true
    end
    local prevConfig = UIUtils.GetTalentConfigByHole(talentConfig.frontHole, character_id)
    --print("===prevConfig.id:" .. tostring(prevConfig.id))
    if not prevConfig then
        return true
    end
    return self:TalentIsActive(prevConfig.id)
end

return M