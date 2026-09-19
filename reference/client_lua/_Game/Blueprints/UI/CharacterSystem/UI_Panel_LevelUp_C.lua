require "UnLua"
require "Common.TableUtil"
local BackpackSystem = require "Module.Backpack.BackpackSystem"
local UIUtils = require "_Game.Utils.UIUtils"
local Database = require("_Game.Utils.Database")
local d_com_params = require("ClientDatas.d_com_params")
local Client = require("Network.Client")
local Protos = require("Helper.Protos")
local MessageManager = require "Framework.Updater.MessageManager"
local NetworkMessageManager = require "Framework.Updater.NetworkMessageManager"
local CharacterSystem = require "Module.CharacterSystem.CharacterSystem"
local PlayerSystem = require "Module.Player.PlayerSystem"
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_Panel_LevelUp_C
local M = Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)
--构造函数
function M:Construct()
    self:InitUI()
    MessageManager:GetInstance():AddListener("OnMsg_Ntf_Item_Info", self)
    MessageManager:GetInstance():AddListener("OnMsg_Req_Character_Level_Up_Success", self)
    MessageManager:GetInstance():AddListener("OnMsg_Req_Character_Level_Break_Success", self)
    MessageManager:GetInstance():AddListener("OnMsg_Req_Strengthen_Weapon_Success", self)
    MessageManager:GetInstance():AddListener("OnMsg_Req_Strengthen_Equip_Success", self)
    NetworkMessageManager:GetInstance():AddListener(Protos.RES_CHARACTER_LEVEL_UP, self)
    NetworkMessageManager:GetInstance():AddListener(Protos.RES_WEAPON_LEVEL_UP, self)
    NetworkMessageManager:GetInstance():AddListener(Protos.RES_ARM_LEVEL_UP, self)
end

function M:Destruct()
    if self.ShowCalculatingHandle then
        UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.ShowCalculatingHandle)
        self.ShowCalculatingHandle = nil
    end

    if self.LongPressEvent then
        UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.LongPressEvent)
        self.LongPressEvent = nil
    end

    MessageManager:GetInstance():RemoveListener("OnMsg_Ntf_Item_Info", self)
    MessageManager:GetInstance():RemoveListener("OnMsg_Req_Character_Level_Up_Success", self)
    MessageManager:GetInstance():RemoveListener("OnMsg_Req_Character_Level_Break_Success", self)
    MessageManager:GetInstance():RemoveListener("OnMsg_Req_Strengthen_Weapon_Success", self)
    MessageManager:GetInstance():RemoveListener("OnMsg_Req_Strengthen_Equip_Success", self)
    NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_CHARACTER_LEVEL_UP, self)
    NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_WEAPON_LEVEL_UP, self)
    NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_ARM_LEVEL_UP, self)
end

M[Protos.RES_CHARACTER_LEVEL_UP] = function(self, result, msgId, parsed_msg)
    self.waiting = false
end

M[Protos.RES_WEAPON_LEVEL_UP] = function(self, result, msgId, parsed_msg)
    self.waiting = false
end

M[Protos.RES_ARM_LEVEL_UP] = function(self, result, msgId, parsed_msg)
    self.waiting = false
end

function M:OnMsg_Ntf_Item_Info()
    --重新获取背包数据
    self:RefreshUI(false)
end

function M:OnMsg_Req_Character_Level_Up_Success()
    self.waiting = false
    self:RefreshLevelUpUI()
end
function M:OnMsg_Req_Character_Level_Break_Success()
    self.waiting = false
    self:RefreshLevelUpUI(true)
end

function M:OnMsg_Req_Strengthen_Weapon_Success()
    self.waiting = false
    self:RefreshLevelUpUI()
end

function M:OnMsg_Req_Strengthen_Equip_Success()
    self.waiting = false
    self:RefreshLevelUpUI()
end

function M:RefreshLevelUpUI(isBreak)
    if self.UITag == "Character" then
        local CharacterInfo = CharacterSystem:GetInstance().CharacterInfo
        for _, v in pairs(CharacterInfo) do 
            if v.character_id == self.InitId then
                self.InitExp = v.exp
                self.InitBreakTimes = v.break_times
                break
            end
        end
        local curlv, _, _ = self:GetLevelInfo(self.InitId, self.InitBreakTimes, self.InitExp)
        --弹出成功ui
       
        local nextMaxLv = UIUtils.GetCharacterMaxLevel(self.InitId, self.InitBreakTimes)
        if isBreak then
            local ui = UE4.UGameplayStatics.GetGameInstance(self):AddUMG('UI_levelup_success')
            ui:RefreshUI(1, self.InitLv, curlv, nextMaxLv, self.CachedLevelUpAttrList)
        else
            if curlv > self.InitLv then
                local ui = UE4.UGameplayStatics.GetGameInstance(self):AddUMG('UI_levelup_success')
                ui:RefreshUI(0, self.InitLv, curlv, nextMaxLv, self.CachedLevelUpAttrList)
            end
        end
    elseif self.UITag == "Weapon" then
        local bEquipped = false
        local CharacterInfo = CharacterSystem:GetInstance().CharacterInfo
        for _, v in pairs(CharacterInfo) do 
            if v.weapon_info.item_uuid == self.InitUUID then
                bEquipped = true
                self.InitBreakTimes = v.weapon_info.weapon_info.break_times
                self.InitExp = v.weapon_info.weapon_info.exp
                break
            end
        end

        if not bEquipped then
            local ItemInfo = BackpackSystem:GetInstance():GetItemByUUID(self.InitUUID)
            if ItemInfo then
                self.InitBreakTimes = ItemInfo.weapon_info.break_times
                self.InitExp = ItemInfo.weapon_info.exp
            end
        end
        local curlv, _, _ = self:GetLevelInfo(self.InitId, self.InitBreakTimes, self.InitExp)
        --弹出成功ui
       
        local nextMaxLv = UIUtils.GetWeaponMaxLevel(self.InitId, self.InitBreakTimes)
        if curlv == self.InitLv then
            local ui = UE4.UGameplayStatics.GetGameInstance(self):AddUMG('UI_levelup_success')
            ui:RefreshUI(1, self.InitLv, curlv, nextMaxLv, self.CachedLevelUpAttrList)
        else
            if curlv > self.InitLv then 
                local ui = UE4.UGameplayStatics.GetGameInstance(self):AddUMG('UI_levelup_success')
                ui:RefreshUI(0, self.InitLv, curlv, nextMaxLv, self.CachedLevelUpAttrList)
            end
        end
    elseif self.UITag == "Equip" then
        local bEquipped = false
        local CharacterInfo = CharacterSystem:GetInstance().CharacterInfo
        for _, characterInfo in pairs(CharacterInfo) do 
            for __, arm_info in ipairs(characterInfo.arm_infos) do
                if arm_info.item_uuid == self.InitUUID then
                    self.InitBreakTimes = arm_info.arm_info.break_times
                    self.InitExp = arm_info.arm_info.exp
                    self.InitArmInfo = arm_info
                    break
                end
            end
        end

        if not bEquipped then
            local ItemInfo = BackpackSystem:GetInstance():GetItemByUUID(self.InitUUID)
            if ItemInfo then
                self.InitBreakTimes = ItemInfo.arm_info.break_times
                self.InitExp = ItemInfo.arm_info.exp
            end
        end
        local curlv, _, _ = self:GetLevelInfo(self.InitId, self.InitBreakTimes, self.InitExp)
        --弹出成功ui
        local nextMaxLv = UIUtils.GetEquipMaxLevel(self.InitId, self.InitBreakTimes)
        if curlv == self.InitLv then
            local ui = UE4.UGameplayStatics.GetGameInstance(self):AddUMG('UI_levelup_success')
            ui:RefreshUI(1, self.InitLv, curlv, nextMaxLv, self.CachedLevelUpAttrList)
        else
            if curlv > self.InitLv then
                local ui = UE4.UGameplayStatics.GetGameInstance(self):AddUMG('UI_levelup_success')
                ui:RefreshUI(0, self.InitLv, curlv, nextMaxLv, self.CachedLevelUpAttrList)
            end
        end
    end
    self:InitData()
    self:RefreshUI(false)
end

function M:InitUI()
    self.Btn_BackButton.OnGHSClicked:Add(self, self.OnClicked_Btn_BackButton)
    self.Btn_LevelUp.OnGHSClicked:Add(self, self.OnClicked_Btn_LevelUp)
    self.Btn_LevelBreak.OnGHSClicked:Add(self, self.OnClicked_Btn_LevelBreak)
    self.Btn_ListReset.OnGHSClicked:Add(self, self.OnClicked_Btn_ListRest)
    self.Btn_ListMax.OnGHSClicked:Add(self, self.OnClicked_Btn_ListMax)
    self.Btn_Pre.OnGHSClicked:Add(self, self.OnClicked_Btn_Pre)
    self.Btn_Next.OnGHSClicked:Add(self, self.OnClicked_Btn_Next)

    --属性列表
    self.ListView_Attr.BP_OnEntryInitialized:Clear()
    self.ListView_Attr.BP_OnEntryInitialized:Add(self, function(wbp, item, widget) 
        self:BP_OnEntryInitialized_Attr(item, widget)
    end)
  
    --材料列表
    self.ListView_Mat.BP_OnEntryInitialized:Clear()
    self.ListView_Mat.BP_OnEntryInitialized:Add(self, function(wbp, item, widget) 
        self:BP_OnEntryInitialized_Mat(item, widget)
    end)
    self.ListView_Mat.BP_OnItemClicked:Clear()
    self.ListView_Mat.BP_OnItemClicked:Add(self, function(wbp, item)
        self:BP_OnItemClicked_Mat(item)
    end)

    --突破材料列表
    self.ListView_BreakMat.BP_OnEntryInitialized:Clear()
    self.ListView_BreakMat.BP_OnEntryInitialized:Add(self, function(wbp, item, widget)
        self:BP_OnEntryInitialized_BreakMat(item, widget)
    end)
    self.ListView_BreakMat.BP_OnItemClicked:Clear()
    self.ListView_BreakMat.BP_OnItemClicked:Add(self, function(wbp, item)
        self:BP_OnItemClicked_BreakMat(item)
    end)


    --等级列表
    self.ListView_LevelScroll.BP_OnEntryInitialized:Clear()
    self.ListView_LevelScroll.BP_OnEntryInitialized:Add(self, function(wbp, item, ui)
        self:BP_OnEntryInitialized_Level(item, ui)
    end)
    --self.ListView_LevelScroll:SetScrollbarVisibility(UE.ESlateVisibility.Hidden)

    --等级列表突破
    self.ListView_LevelScrollBreak.BP_OnEntryInitialized:Clear()
    self.ListView_LevelScrollBreak.BP_OnEntryInitialized:Add(self, function(wbp, item, ui)
        self:BP_OnEntryInitialized_LevelBreak(item, ui)
    end)
    self.ListView_LevelScrollBreak:SetScrollbarVisibility(UE.ESlateVisibility.Hidden)
end

--设置来源 角色系统/背包系统 背包系统特用函数
function M:SetIsFromBackpack(isFromBackpack)
    self.IsFromBackpack = isFromBackpack
end

function M:SetBackUI(beforeUI, UITag, uuid, initId, breakTimes, exp)
    self.BackUI = beforeUI
    self.UITag = UITag
    self.InitUUID = uuid
    self.InitId = initId --当前角色数据
    self.InitBreakTimes = breakTimes
    self.InitExp = exp --当前武器/装备数据

    self:InitData()
    self:RefreshUI(false)
end

function M:InitData()
    --print("====self.InitExp:" .. tostring(self.InitExp))
    local curlv, nextNeedExp, allExp = self:GetLevelInfo(self.InitId, self.InitBreakTimes, self.InitExp)
    self.InitLv = curlv --当前等级
    self.InitNeedExp = nextNeedExp --当前升级需要经验
    self.InitNextExp = allExp --当前升级总经验
    self.InitHaveExp = allExp - nextNeedExp

    self.MaxBreakTimes = self:GetInitMaxBreakTimes(self.InitId)

    self.InitMaxLv = self:GetInitMaxLevel()

    self.MaxLvWithMaxBreakTime = self:GetMaxLvWithMaxBreakTimes()

    self.TempLv = self.InitLv
end

function M:InitAddData()
    self.AddExp = self:GetAddExp() --选中材料增加的经验
    print("===addExp:" .. tostring(self.AddExp) .. ",initExp:" .. tostring(self.InitExp))
    local curlv, nextNeedExp, allExp = self:GetLevelInfo(self.InitId, self.InitBreakTimes, self.InitExp + self.AddExp)
    print("===curlv:" .. tostring(curlv) .. ",nextNeedExp:" .. tostring(nextNeedExp) .. ",allExp:" .. tostring(allExp))
    if nextNeedExp > 0 and curlv == self:GetInitMaxLevel() then
        local left = allExp - nextNeedExp
        if left > 0 then
            self.AddExp = self.AddExp - left
        end
    end
   
    self.TempLv = curlv --临时等级
    self.TempNeedExp = nextNeedExp --临时升级需要经验
    self.TempNextExp = allExp --临时升级总经验
end

function M:InitSelectedLvAddData()
    self.AddExp = UIUtils.GetCharacterAllExp(self.TempLv) - self.InitExp
    local curlv, nextNeedExp, allExp = self:GetLevelInfo(self.InitId, self.InitBreakTimes, self.InitExp + self.AddExp)

    self.TempLv = curlv --临时等级
    self.TempNeedExp = nextNeedExp --临时升级需要经验
    self.TempNextExp = allExp --临时升级总经验
end

function M:InitBreakData()
    self.TempBreakTimes = self.InitBreakTimes + 1
end

function M:RefreshUI(bForce)
    local isMaxBreakTimes = self.InitBreakTimes == self.MaxBreakTimes
    self.IsFull = self.InitLv == self.MaxLvWithMaxBreakTime
    self.IsBreak = self.InitLv == self.InitMaxLv and not self.IsFull

    if isMaxBreakTimes and self.IsBreak then
        UIManager:GetInstance():RemoveUI(self)
        if self.BackUI then
            if self.UITag == "Character" then
                self.BackUI:MoveCameraToLevelUp(true)
            end
            self.BackUI:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
            self.BackUI = nil
        end
        return
    end

    self.Panel_LevelUp:SetVisibility(not self.IsBreak and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
    self.Panel_LevelBreak:SetVisibility(self.IsBreak and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
    self.Btn_ListReset:SetVisibility(self.IsBreak and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.Visible)
    self.Btn_ListMax:SetVisibility(self.IsBreak and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.Visible)
    self.Text_LevelUp:SetVisibility(self.IsBreak and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.Visible)
    self.MaxPanel:SetVisibility(UE.ESlateVisibility.Hidden)

    if self.IsFull then
        self.ListView_LevelScroll:SetScrollOffset(0)
        self:RefreshLevelFull()
    elseif self.IsBreak then
        self.ListView_LevelScroll:SetScrollOffset(0)
        self:RefreshLevelBreak()
    else
        self.ListView_LevelScrollBreak:SetScrollOffset(0)
        self:RefreshLevelUp(bForce)
    end
    self.IsInit = true
end

function M:RefreshLevelUp(bForce)
    --刷新当前经验值
    self.Text_Exp:SetText(string.format("%s/%s", self.InitHaveExp, self.InitNextExp))
    self.nowexp:SetPercent(self.InitHaveExp / self.InitNextExp)
    --获取要升级消耗的道具数据
    self.LevelUpItemList = self:GetLevelUpMaterialList()
    self.UserClickMat = false
    self.InitScrollView = true
    --根据self.NeedExp自动计算升到下一级选择的材料
    self:ClearAllLevelUpItem()
    
    if bForce then
        self:AutoLevelUp() 
    end

    self:InitAddData()

    self:RefreshAddExp()

    self:RefreshLevelScroll(self.TempLv, self.InitMaxLv)
end

function M:RefreshLevelBreak()
    self:InitBreakData()

    self:RefreshAddBreak()

    --突破等级列表
    self:RefreshLevelScroll(self.TempBreakTimes, self.MaxBreakTimes)
end

function M:RefreshLevelFull()
    self.title:SetVisibility(UE.ESlateVisibility.Hidden)
    self.LevelUpButton:SetVisibility(UE.ESlateVisibility.Hidden)
    self.ListView_Mat:SetVisibility(UE.ESlateVisibility.Hidden)
    self.calculating:SetVisibility(UE.ESlateVisibility.Hidden)
    self.MaxPanel:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)

    --属性列表刷新
    self.LevelUpAttrList = self:GetLevelUpAttrList()
    local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
    local ItemClass = UE.UClass.Load(ItemSourcePath)
    local attrDataSource = {}
    for i = 1, #self.LevelUpAttrList do
        local itemData = NewObject(ItemClass)
        itemData.Index = i
        itemData.ItemId = self.LevelUpAttrList[i].item_id
        table.insert(attrDataSource, itemData)
    end

    self.ListView_Attr:ClearListItems()
    self.ListView_Attr:BP_SetListItems(attrDataSource)
    self.TextMax:SetText(Database.L10n(239))
    self:RefreshLevelScroll(self.TempLv, self.InitMaxLv)
end

function M:RefreshAddBreak()
    --获取突破提升的属性
    self.LevelUpAttrList = self:GetLevelBreakAttrList()
    --属性列表刷新
    local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
    local ItemClass = UE.UClass.Load(ItemSourcePath)
    local attrDataSource = {}
    for i = 1, #self.LevelUpAttrList do
        local itemData = NewObject(ItemClass)
        itemData.Index = i
        itemData.ItemId = self.LevelUpAttrList[i].item_id
        table.insert(attrDataSource, itemData)
    end

    self.ListView_Attr:ClearListItems()
    self.ListView_Attr:BP_SetListItems(attrDataSource)

    local isOk = false
    --获取突破消耗的道具数据
    self.LevelBreakCurrencyList, self.LevelBreakItemList, isOk = self:GetLevelBreakMaterialList()
    --默认5个材料列表
    local levelUpItemListDataSource = {}
    for i = 1, #self.LevelBreakItemList do 
        local itemData = NewObject(ItemClass)
        itemData.Index = i 
        itemData.ItemId = self.LevelBreakItemList[i].item_id
        table.insert(levelUpItemListDataSource, itemData)
    end
    
    self.ListView_BreakMat:ClearListItems()
    self.ListView_BreakMat:BP_SetListItems(levelUpItemListDataSource)

    --刷新金币
    local hasGold = self.LevelBreakCurrencyList[1].count
    local needGold = self.LevelBreakCurrencyList[1].needCount

    --金币文字颜色
    local textColor = UE.FSlateColor()
    textColor.SpecifiedColor = hasGold >= needGold and UE.FLinearColor(1.0, 1.0, 1.0, 1.0) or UE.FLinearColor(1.0, 0.0, 0.0, 1.0)
    self.Text_BreakHaveGold:SetColorAndOpacity(textColor)
    self.Text_BreakHaveGold:SetText("/" .. hasGold)
    self.Text_BreakNeedGold:SetText(needGold)

    --判定是否角色等级>=限制等级
    local targetBreakTimes = self.InitBreakTimes + 1
    --按钮状态
    isOk = isOk and hasGold >= needGold and self.TempBreakTimes == targetBreakTimes
    if self.UITag == "Character" then
        local config = nil
        local d_role_levelbreak = require('ClientDatas.d_role_levelbreak')
        for _, levelbreakConfig in pairs(d_role_levelbreak) do 
            if levelbreakConfig.roleId == self.InitId and (self.TempBreakTimes - 1) == levelbreakConfig.levelbreak then
                config = levelbreakConfig
                break
            end
        end
        if config and config.playerLevel then
            local isPlayerLevelFull = PlayerSystem:GetInstance().Level >= config.playerLevel
            isOk = isOk and isPlayerLevelFull

            self.UI_Sub_LevelUp.Img_Ok:SetVisibility(isPlayerLevelFull and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
            self.UI_Sub_LevelUp.Img_Fail:SetVisibility(not isPlayerLevelFull and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
            self.UI_Sub_LevelUp.Level:SetText(config.playerLevel)
            self.UI_Sub_LevelUp.CHKBox:SetIsChecked(isPlayerLevelFull)
        end
        self.UI_Sub_LevelUp:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
    elseif self.UITag == 'Weapon' then
        local config = nil
        local d_weapon_levelbreak = require('ClientDatas.d_weapon_levelbreak')
        for _, levelbreakConfig in pairs(d_weapon_levelbreak) do 
            if levelbreakConfig.weaponId == self.InitId and self.InitBreakTimes == levelbreakConfig.levelbreak then
                config = levelbreakConfig
                break
            end
        end
        if config and config.limitlevel then
            local isPlayerLevelFull = PlayerSystem:GetInstance().Level >= config.limitlevel
            isOk = isOk and isPlayerLevelFull

            self.UI_Sub_LevelUp.Img_Ok:SetVisibility(isPlayerLevelFull and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
            self.UI_Sub_LevelUp.Img_Fail:SetVisibility(not isPlayerLevelFull and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
            self.UI_Sub_LevelUp.Level:SetText(config.limitlevel)
            self.UI_Sub_LevelUp.CHKBox:SetIsChecked(isPlayerLevelFull)
        end
        self.UI_Sub_LevelUp:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
    else
        self.UI_Sub_LevelUp:SetVisibility(UE.ESlateVisibility.Hidden)
    end

    self.Btn_LevelBreak:SetIsEnabled(isOk)

    --等级提示
    local isNextLv = self.TempBreakTimes == targetBreakTimes
    local tips = isNextLv and Database.L10n(503201) or Database.L10n(503202)
    if isNextLv then
        local nextMaxLv = self:GetInitMaxLevel()
        tips = string.format(tips, '<span color="#00B1FFFF">' .. nextMaxLv .. "</>")
    else
        local preMaxLv = self:GetInitMaxLevel()
        tips = string.format(tips, '<span color="#FF0000FF">' .. preMaxLv .. "</>")
    end
    self.Text_Tips:SetVisibility(UE.ESlateVisibility.Hidden)
    -- self.Text_Tips:SetText(tips)
end

function M:ClearAllLevelUpItem()
    if self.LevelUpItemList then
        for i = #self.LevelUpItemList, 1, -1 do 
            local item = self.LevelUpItemList[i]
            item.selectCount = 0
        end
    end
end

function M:AutoLevelUp()
    local needExp = self:GetNeedExp()
    print("===needExp:" .. tostring(needExp))
    --相同等级时，计算有误
    if needExp < 0 then
        needExp = 0
    end

    if self.LevelUpItemList then
        for i = #self.LevelUpItemList, 1, -1 do 
            local item = self.LevelUpItemList[i]
            item.selectCount = 0
            if item.count > 0 and needExp > 0 then
                if needExp >= item.config.subParam[1] then
                    local count, temp2 = math.modf(needExp / item.config.subParam[1])
                    if count > 0 then
                        if item.count >= count then
                            item.selectCount = count
                            needExp = needExp - item.config.subParam[1] * count
                        else
                            item.selectCount = item.count
                            needExp = needExp - item.config.subParam[1] * item.count
                        end
                    end
                end
            end
        end
        if needExp > 0 then
            for i = 1, #self.LevelUpItemList do 
                local item = self.LevelUpItemList[i]
                if item.count - item.selectCount > 0 and needExp > 0 then
                    local count = math.ceil(needExp / item.config.subParam[1])
                    if count > 0 then
                        if item.count - item.selectCount >= count then
                            item.selectCount = item.selectCount + count
                            needExp = needExp - item.config.subParam[1] * count
                        else
                            item.selectCount = item.selectCount + count
                            needExp = needExp - item.config.subParam[1] * item.count
                        end
                    end
                end
            end
        end
    end
    print("===needExp2:" .. tostring(needExp))
    return needExp
end

function M:ForceLevelUP()
    local needExp = self:AutoLevelUp()
    print("===ForceLevelUP.needExp1:" .. tostring(needExp))
    if needExp < 0 then
        return
    end
    if self.LevelUpItemList then
        for i = #self.LevelUpItemList, 1, -1 do 
            local item = self.LevelUpItemList[i]
            if needExp > 0 and needExp >= item.config.subParam[1] then
                local count = math.ceil(needExp / item.config.subParam[1])
                item.selectCount = item.selectCount + count
                needExp = needExp - count * item.config.subParam[1]
            end
        end
    end
    print("===ForceLevelUP.needExp2:" .. tostring(needExp))
    return needExp
end

function M:RefreshAddExp()
    -- print("====addExp:" .. tostring(self.AddExp)) 
    -- print("===self.InitHaveExp + self.AddExp:" .. tostring(self.InitHaveExp + self.AddExp))
    --增加的经验值
    self.Text_ExpAdd:SetText(self.AddExp > 0 and ("+" .. self.AddExp) or "")
    self.newexp:SetPercent((self.InitHaveExp + self.AddExp) / self.InitNextExp)

    --计算增加的属性 获取升级提升的属性
    self.LevelUpAttrList = self:GetLevelUpAttrList()
    local hasGold = UIUtils.GetGold()
    local needGold = (self.AddExp * self:GetGoldCoinRate())

    local textColor = UE.FSlateColor()
    textColor.SpecifiedColor = hasGold >= needGold and UE.FLinearColor(1.0, 1.0, 1.0, 1.0) or UE.FLinearColor(1.0, 0.0, 0.0, 1.0)
    self.Text_HaveGold:SetColorAndOpacity(textColor)
    self.Text_HaveGold:SetText("/" .. hasGold)
    self.Text_NeedGold:SetText(needGold)

    local isFull = true
    local isEmpty = true
    for _, v in pairs(self.LevelUpItemList) do 
        if v.selectCount > 0 then
            isEmpty = false
        end 
        if v.selectCount > v.count then
            isFull = false
        end
    end
    local isOk = (self.TempLv >= self.InitLv and self.TempLv <= self.InitMaxLv) and not isEmpty and isFull and (hasGold >= needGold)
    self.Btn_LevelUp:SetIsEnabled(isOk)

    --属性列表刷新
    local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
    local ItemClass = UE.UClass.Load(ItemSourcePath)
    local attrDataSource = {}
    for i = 1, #self.LevelUpAttrList do
        local itemData = NewObject(ItemClass)
        itemData.Index = i
        itemData.ItemId = self.LevelUpAttrList[i].item_id
        table.insert(attrDataSource, itemData)
    end

    self.ListView_Attr:ClearListItems()
    self.ListView_Attr:BP_SetListItems(attrDataSource)

    if not self.UserClickMat and self.InitScrollView then
        --默认5个材料列表
        local levelUpItemListDataSource = {}
        for i = 1, #self.LevelUpItemList do 
            local itemData = NewObject(ItemClass)
            itemData.Index = i 
            itemData.ItemId = self.LevelUpItemList[i].item_id
            table.insert(levelUpItemListDataSource, itemData)
        end
        
        self.ListView_Mat:ClearListItems()
        self.ListView_Mat:BP_SetListItems(levelUpItemListDataSource)
    else
        self:RefreshListViewAllItem_Mat()
    end
end

function M:RefreshLevelScroll(curLv, maxLv)
    -- print("===RefreshLevelScroll:" .. tostring(curLv) .. ",maxLv:" .. tostring(maxLv))
    local count = maxLv - curLv + 5
    local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
    local ItemClass = UE.UClass.Load(ItemSourcePath)
    local itemDataSource = {}
    for i = 1, count do 
        local itemData = NewObject(ItemClass)
        itemData.Index = curLv - 3 + i 
        itemData.ItemId = curLv - 3 + i 
        table.insert(itemDataSource, itemData)
    end

    self.LastScrollOffset = 0
    self.LastLevelIndex = 0
    self.MaxIndex = maxLv - curLv
    self.IsForceScroll = true

    if self.ShowCalculatingHandle then
        UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.ShowCalculatingHandle)
        self.ShowCalculatingHandle = nil
    end
    self.calculating:SetVisibility(UE.ESlateVisibility.Hidden)
    if self.IsBreak then
        self.ListView_LevelScrollBreak:ClearListItems()
        self.ListView_LevelScrollBreak:BP_SetListItems(itemDataSource)
        self.ListView_LevelScrollBreak:SetScrollOffset(0)
    else
        self.ListView_LevelScroll:ClearListItems()
        self.ListView_LevelScroll:BP_SetListItems(itemDataSource)
        self.ListView_LevelScroll:SetScrollOffset(0)
    end
    --等级列表左右按钮
    self.Btn_Pre:SetVisibility(self.TempLv ~= self.InitLv and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
    self.Btn_Next:SetVisibility(self.TempLv ~= self.InitMaxLv and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
end

function M:ScrollToLevel(Index)
    -- print("=====ScrollToLevel:" .. tostring(Index))
    self.IsForceScroll = true
    if self.IsBreak then
        self.ListView_LevelScrollBreak:SetScrollOffset(Index)
    else
        self.ListView_LevelScroll:SetScrollOffset(Index)
        --等级列表左右按钮
        self.Btn_Pre:SetVisibility(self.TempLv ~= self.InitLv and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
        self.Btn_Next:SetVisibility(self.TempLv ~= self.InitMaxLv and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
    end
end

function M:Tick(MyGeometry, InDeltaTime)
    if not self.IsInit then
        return 
    end
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    if playerController and playerController.MousePressed then
        return
    end
    if self.IsBreak then
        self.IsRefreshPending = self.ListView_LevelScrollBreak:IsRefreshPending()
        if self.IsRefreshPending then
            if not self.bIsListScrollStart then
                self.bIsListScrollStart = true --标记滚动开始
                self.bIsListScrollEnd = false
                if self.bSetNewIndex then
                    if self.LastLevelIndex == 0 or self.LastLevelIndex == self.MaxIndex then
                        self.bSetNewIndex = false
                    end
                end
                if not self.bSetNewIndex and not self.UserClickMat and not self.InitScrollView then
                    self:ShowCalculating(true)
                end
                if self.bSetNewIndex then
                    self.bSetNewIndex = false
                end
            end
            self:RefreshListViewAllItems(self.ListView_LevelScrollBreak)
        else
            if not self.bIsListScrollEnd then
                self.bIsListScrollEnd = true --标记滚动结束
                self.bIsListScrollStart = false
                if self.InitScrollView then
                    self.InitScrollView = false
                    self.ListView_LevelScroll:SetScrollOffset(0)
                    return
                end

                local curScrollOffset = self.ListView_LevelScrollBreak:GetScrollOffset()
                local _, modNUm = math.modf(curScrollOffset)
                local newOffset = modNUm < 0.5 and math.floor(curScrollOffset) or math.ceil(curScrollOffset)
                newOffset = UE.UKismetMathLibrary.Clamp(newOffset, 0, self.MaxIndex)
                if not UE.UKismetMathLibrary.NearlyEqual_FloatFloat(curScrollOffset, self.LastScrollOffset, 0.01) then
                    if self.LastLevelIndex == newOffset and self.LastLevelIndex == self.MaxIndex then
                        if not UE.UKismetMathLibrary.NearlyEqual_FloatFloat(curScrollOffset, newOffset, 0.1) then
                            self.ListView_LevelScrollBreak:SetScrollOffset(newOffset)
                        end
                    else
                        self.ListView_LevelScrollBreak:SetScrollOffset(newOffset)

                        if self.LastLevelIndex ~= newOffset then
                            self.LastLevelIndex = newOffset
                            self.bSetNewIndex = true
                            self:OnScrollViewSelected(newOffset)
                            self:ShowCalculating(false)
                        else 
                            self.bSetNewIndex = false
                            self:ShowCalculating(false)
                        end
                    end
                    self.LastScrollOffset = curScrollOffset
                else
                    self.bSetNewIndex = false
                    self:ShowCalculating(false)
                end
            end
            self:RefreshListViewAllItems(self.ListView_LevelScrollBreak)
        end
    else
        self.IsRefreshPending = self.ListView_LevelScroll:IsRefreshPending()
        if self.IsRefreshPending then
            if not self.bIsListScrollStart then
                self.bIsListScrollStart = true --标记滚动开始
                self.bIsListScrollEnd = false
                if self.bSetNewIndex then
                    if self.LastLevelIndex == 0 or self.LastLevelIndex == self.MaxIndex then
                        self.bSetNewIndex = false
                    end
                end
                if not self.bSetNewIndex and not self.UserClickMat and not self.InitScrollView then
                    self:ShowCalculating(true)
                end
                if self.bSetNewIndex then
                    self.bSetNewIndex = false
                end
            end
            self:RefreshListViewAllItems(self.ListView_LevelScroll)
        else
            if not self.bIsListScrollEnd then
                self.bIsListScrollEnd = true --标记滚动结束
                self.bIsListScrollStart = false
                if self.InitScrollView then
                    self.InitScrollView = false
                    self.ListView_LevelScroll:SetScrollOffset(0)
                    return
                end

                local curScrollOffset = self.ListView_LevelScroll:GetScrollOffset()
                local _, modNUm = math.modf(curScrollOffset)
                local newOffset = modNUm < 0.5 and math.floor(curScrollOffset) or math.ceil(curScrollOffset)
                newOffset = UE.UKismetMathLibrary.Clamp(newOffset, 0, self.MaxIndex)
                if not UE.UKismetMathLibrary.NearlyEqual_FloatFloat(curScrollOffset, self.LastScrollOffset, 0.01) then
                    if self.LastLevelIndex == newOffset and self.LastLevelIndex == self.MaxIndex then
                        if not UE.UKismetMathLibrary.NearlyEqual_FloatFloat(curScrollOffset, newOffset, 0.1) then
                            self.ListView_LevelScroll:SetScrollOffset(newOffset)
                        end
                    else
                        self.ListView_LevelScroll:SetScrollOffset(newOffset)

                        if self.LastLevelIndex ~= newOffset then
                            self.LastLevelIndex = newOffset
                            self.bSetNewIndex = true
                            self:OnScrollViewSelected(newOffset)
                            self:ShowCalculating(false)
                        else 
                            self.bSetNewIndex = false
                            self:ShowCalculating(false)
                        end
                    end
                    self.LastScrollOffset = curScrollOffset
                else
                    self.bSetNewIndex = false
                    self:ShowCalculating(false)
                end
                
            end
            self:RefreshListViewAllItems(self.ListView_LevelScroll)
        end
    end
end

function M:RefreshListViewAllItems(listView)
    local curScrollOffset = listView:GetScrollOffset()
    local newOffset = UE.UKismetMathLibrary.FCeil(curScrollOffset + 0.5)
    local widgets = listView:GetDisplayedEntryWidgets()
    local maxLv = self.IsBreak and self.MaxBreakTimes or self.InitMaxLv
    newOffset = self.IsBreak and (newOffset + self.InitBreakTimes) or (newOffset + self.InitLv - 1)

    for i = 1, widgets:Length() do
        local ui = widgets:Get(i)
        local textColor = UE.FSlateColor()
        if ui.Index == (maxLv + 1) then
            ui.Text_Lv:SetVisibility(UE.ESlateVisibility.Hidden)
            ui.Text_Lv_1:SetVisibility(UE.ESlateVisibility.Hidden)
        elseif ui.Index == newOffset then
            ui.Text_Lv:SetVisibility(UE.ESlateVisibility.Visible)
            ui.Text_Lv_1:SetVisibility(UE.ESlateVisibility.Hidden)
        elseif math.abs(ui.Index - newOffset) == 1 then
            ui.Text_Lv:SetVisibility(UE.ESlateVisibility.Hidden)
            ui.Text_Lv_1:SetVisibility(UE.ESlateVisibility.Visible)
            textColor.SpecifiedColor = UE.FLinearColor(0.846873, 0.879623, 1.0, 1.0)
            ui.Text_Lv_1:SetColorAndOpacity(textColor)
        else
            ui.Text_Lv:SetVisibility(UE.ESlateVisibility.Hidden)
            ui.Text_Lv_1:SetVisibility(UE.ESlateVisibility.Visible)
            textColor.SpecifiedColor = UE.FLinearColor(0.846873, 0.879623, 1.0, 0.5)
            ui.Text_Lv_1:SetColorAndOpacity(textColor)
        end
    end
end

function M:OnScrollViewSelected(index)
    --print("=======OnScrollViewSelected:" .. tostring(index))
    if self.InitScrollView then
        self.InitScrollView = false
        return
    end
    if self.UserClickMat then
        self.UserClickMat = false
        return
    end
    if self.IsBreak then
        self.TempBreakTimes = index + self.InitBreakTimes + 1
        self:RefreshAddBreak()
    else
        self.TempLv = index + self.InitLv
        self:ForceLevelUP()
        self:InitAddData()
        self:RefreshAddExp()
        if not self.isAutoScroll then
            self:ScrollToLevel(self.TempLv - self.InitLv)
            self.isAutoScroll = true
        end
        
    end
end

function M:OnHideLevelUpEnd()
    local controller = UE.UGameplayStatics.GetPlayerController(self, 0)
    --获取控制器组件
    if controller and controller.BP_PlayerController_City_UniverseBridge then
        if controller.BP_PlayerController_City_UniverseBridge.OnHideLevelUpEnd then
            controller.BP_PlayerController_City_UniverseBridge.OnHideLevelUpEnd:Clear()
        end 
    end
    if self.UITag == "Character" then 
        self.BackUI:MoveCameraToLevelUp(true)
    end
    self.BackUI:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    self.BackUI = nil
end

--滚动时显示计算图片`
function M:ShowCalculating(bShow)
    self.calculating:SetVisibility(bShow and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
    self:SetShowAllItemCount(not bShow)
end

function M:OnShowCalculatingEnd()
    self.calculating:SetVisibility(UE.ESlateVisibility.Hidden)
    self:SetShowAllItemCount(true)
    if self.ShowCalculatingHandle then
        UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.ShowCalculatingHandle)
        self.ShowCalculatingHandle = nil
    end
end

--- 
function M:SetShowAllItemCount(isVisible)
    local widgets = self.ListView_Mat:GetDisplayedEntryWidgets()
    for i = 1, widgets:Length() do
        local ui = widgets:Get(i)
        local itemData = self.LevelUpItemList[ui.Index]
        ui.Btn_ItemSub:SetVisibility((isVisible and itemData.selectCount > 0) and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
    end
end

function M:RefreshListViewAllItem_Mat()
    local widgets = self.ListView_Mat:GetDisplayedEntryWidgets()
    for i = 1, widgets:Length() do
        local ui = widgets:Get(i)
        local itemData = self.LevelUpItemList[ui.Index]

        --选中个数
        local selectCountStr = itemData.selectCount > 0 and itemData.selectCount or ""
        local textColor = UE.FSlateColor()
        textColor.SpecifiedColor = itemData.selectCount <= itemData.count and UE.FLinearColor(1.0, 1.0, 1.0, 1.0) or UE.FLinearColor(1.0, 0.0, 0.0, 1.0)
        ui.Text_SelectCount:SetColorAndOpacity(textColor)
        ui.Text_SelectCount:SetText(selectCountStr)

        --总个数
        ui.Text_Count:SetText(itemData.count)
        ui.lackState:SetVisibility(UE.ESlateVisibility.Hidden)

        ui.Btn_ItemSub:SetVisibility(itemData.selectCount > 0 and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
    end
end

----------------------------------------------------------------------
---ui event
function M:OnClicked_Btn_BackButton()
    
    if self.BackUI then
        --额外判断当前场景
        if self.IsFromBackpack then
            local controller = UE.UGameplayStatics.GetPlayerController(self, 0)
            
            --获取控制器组件
            if controller and controller.BP_PlayerController_City_UniverseBridge then
                if controller.BP_PlayerController_City_UniverseBridge.OnHideLevelUpEnd then
                    controller.BP_PlayerController_City_UniverseBridge.OnHideLevelUpEnd:Add(self, self.OnHideLevelUpEnd)
                end 
                controller.BP_PlayerController_City_UniverseBridge:LevelUpToBackpack()
            end
        else
            -- if self.BackUI.BackFromLevelUp then
            --     self.BackUI:BackFromLevelUp()
            -- end
            if self.UITag == "Character" then
                self.BackUI:MoveCameraToLevelUp(true)
            end
            self.BackUI:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
            self.BackUI = nil
        end
    end
    UIManager:GetInstance():RemoveUI(self)
end

function M:IA_Confirm()
    if self.IsBreak then
        local isMaxBreakTimes = self.InitBreakTimes == self.MaxBreakTimes
        if isMaxBreakTimes then
            return
        end
  
        if self.Btn_LevelBreak:GetIsEnabled() then
            self:OnClicked_Btn_LevelBreak()
        end
    else
        local selectedItemInfo = self:GetSelectedBagItem()
        if self.Btn_LevelUp:GetIsEnabled() and #selectedItemInfo > 0 then
            self:OnClicked_Btn_LevelUp()
        end
    end
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.OnClicked_Btn_BackButton)
InputUtils.RegisterUIAction(M, InputAssets.IA_Confirm, UE.ETriggerEvent.Completed, M.IA_Confirm)
function M:OnClicked_Btn_LevelUp()
    if not self.AddExp then return end
    --时间判定
    if not self.LastReqLevelUpTime then 
        self.LastReqLevelUpTime = PlayerSystem:GetInstance():GetServerTime() - 1
    end
    local now = PlayerSystem:GetInstance():GetServerTime()
    if now - self.LastReqLevelUpTime <= 0.5 then return end
    self.LastReqLevelUpTime = now

    local SrpgController = require('Module.Srpg.SrpgController')
    if SrpgController:GetInstance():HasPendingFight() then
        UIUtils.ShowNotify(self, Database.L10n(285))
        return
    end
    self.CachedLevelUpAttrList = self.LevelUpAttrList
    if self.UITag == "Character" then
        if not self.waiting then
            self.waiting = true
            print("===所有经验:" .. tostring(self.InitExp + self.AddExp))
            CharacterSystem:GetInstance():CacheCharacterInfo(self.InitId, self.InitExp + self.AddExp, self.InitBreakTimes)
            local msg = {
                character_id = self.InitId,
                item_infos = self:GetSelectedBagItem()
            }
            Client.send("req_character_level_up", msg)
        end
    elseif self.UITag == "Weapon" then
        if not self.waiting then
            self.waiting = true
            --缓存升级的武器id
            BackpackSystem:GetInstance():CacheWeaponOrEquipInfo(self.InitUUID, self.InitId, self.InitExp + self.AddExp,
                self.InitBreakTimes)
            local msg = {
                item_uuid = self.InitUUID,
                item_infos = self:GetSelectedBagItem()
            }
            Client.send("req_weapon_level_up", msg)
        end
    elseif self.UITag == "Equip" then
        if not self.waiting then
            self.waiting = true
            BackpackSystem:GetInstance():CacheWeaponOrEquipInfo(self.InitUUID, self.InitId, self.InitExp + self.AddExp,
                self.InitBreakTimes)
            local msg = {
                item_uuid = self.InitUUID,
                item_infos = self:GetSelectedBagItem()
            }
            Client.send("req_arm_level_up", msg)
        end
    end
end

function M:OnClicked_Btn_LevelBreak()
    local SrpgController = require('Module.Srpg.SrpgController')
    if SrpgController:GetInstance():HasPendingFight() then
        UIUtils.ShowNotify(self, Database.L10n(285))
        return
    end
    --时间判定
    if not self.LastReqLevelBreakTime then 
        self.LastReqLevelBreakTime = PlayerSystem:GetInstance():GetServerTime() - 1
    end
    local now = PlayerSystem:GetInstance():GetServerTime()
    if now - self.LastReqLevelBreakTime <= 0.5 then return end
    self.LastReqLevelBreakTime = now

    self.CachedLevelUpAttrList = self.LevelUpAttrList
    if self.UITag == "Character" then
        if not self.waiting then
            self.waiting = true
            CharacterSystem:GetInstance():CacheCharacterInfo(self.InitId, self.InitExp, self.InitBreakTimes + 1)
            local msg = {
                character_id = self.InitId
            }
            Client.send("req_character_level_break", msg)
        end
    elseif self.UITag == "Weapon" then
        if not self.waiting then
            self.waiting = true
            BackpackSystem:GetInstance():CacheWeaponOrEquipInfo(self.InitUUID, self.InitId, self.InitExp,
                self.InitBreakTimes + 1)
            local msg = {
                item_uuid = self.InitUUID
            }
            Client.send("req_weapon_level_break", msg)
        end
    elseif self.UITag == "Equip" then
        if not self.waiting then
            self.waiting = true
            BackpackSystem:GetInstance():CacheWeaponOrEquipInfo(self.InitUUID, self.InitId, self.InitExp,
                self.InitBreakTimes + 1)
            local msg = {
                item_uuid = self.InitUUID
            }
            Client.send("req_arm_level_break", msg)
        end
    end
end

function M:OnClicked_Btn_ListRest()
    if self.IsBreak and self.ListView_LevelScrollBreak:IsRefreshPending() then
        return
    end
    if not self.IsBreak and self.ListView_LevelScroll:IsRefreshPending() then
        return
    end
    if self.IsBreak then
        self.TempBreakTimes = self.InitBreakTimes
        self:RefreshAddBreak()
        self:ScrollToLevel(0)
    else
        if self.TempLv ~= self.InitLv then
            self.bSetNewIndex = false
            self.TempLv = self.InitLv
            --self:AutoLevelUp()
            self:InitAddData()
            self:RefreshAddExp()
            self:ScrollToLevel(0)
        end
    end
end

function M:OnClicked_Btn_ListMax()
    if self.TempLv ~= self.InitMaxLv then
        self.bSetNewIndex = false
        self.TempLv = self.InitMaxLv
        self:AutoLevelUp()
        self:InitAddData()
        self:RefreshAddExp()
        self:ScrollToLevel(self.TempLv - self.InitLv)
    end
end

function M:OnClicked_Btn_Pre()
    local curTime = UE.UKismetSystemLibrary.GetGameTimeInSeconds(self)
    if curTime - (self.LastClickChangeLvTime or 0) < self.ClickBtnTime then
        return
    end
    self.LastClickChangeLvTime = curTime
    if self.IsBreak then
        local tmpLv = self.TempBreakTimes - 1
        self.TempBreakTimes = tmpLv <= self.InitBreakTimes and self.InitBreakTimes or tmpLv
        self:RefreshAddBreak()
    else
        if self.TempLv ~= self.InitLv then
            self.bSetNewIndex = false
            local tmpLv = self.TempLv - 1
            self.TempLv = tmpLv <= self.InitLv and self.InitLv or tmpLv
            self:ForceLevelUP()
            self:InitAddData()
            self:RefreshAddExp()
            self:ScrollToLevel(self.TempLv - self.InitLv)
        end
    end
end

function M:OnClicked_Btn_Next()
    local curTime = UE.UKismetSystemLibrary.GetGameTimeInSeconds(self)
    if curTime - (self.LastClickChangeLvTime or 0) < self.ClickBtnTime then
        return
    end
    self.LastClickChangeLvTime = curTime
    if self.IsBreak then
        local tmpLv = self.TempBreakTimes + 1
        self.TempBreakTimes = tmpLv > self.MaxBreakTimes and self.MaxBreakTimes or tmpLv
        self:RefreshAddBreak()
    else
        if self.TempLv ~= self.InitMaxLv then
            self.bSetNewIndex = false
            local tmpLv = self.TempLv + 1
            self.TempLv = tmpLv > self.InitMaxLv and self.InitMaxLv or tmpLv
            self:ForceLevelUP()
            self:InitAddData()
            self:RefreshAddExp()
            self:ScrollToLevel(self.TempLv - self.InitLv)
        end
    end
end

--属性列表
function M:BP_OnEntryInitialized_Attr(item, ui)
    local attrInfo = self.LevelUpAttrList[item.Index]
    --背景图片
    ui.Img_Bg:SetVisibility((item.Index % 2 == 1) and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Collapsed)

    --属性类型图片
    local iconPath = string.format("'/Game/_Game/TP_New/Attribute_res/Frames/%s_png.%s_png'", attrInfo.config.attrIcon, attrInfo.config.attrIcon)
    local iconObj = LoadObject(iconPath)
    if iconObj then
        ui.Img_Icon:SetBrushFromAtlasInterface(iconObj)
    end
    local bShowUp = (attrInfo.attrUp or 0) > 0
    ui.Text_Title:SetText(Database.L10n(attrInfo.config.attrName))

    -- ui.Text_CurValue:SetText(bShowUp and attrInfo.attrValue or "")
    local textColor = UE.FSlateColor()
    textColor.SpecifiedColor = bShowUp and UE.FLinearColor(0.545725, 0.603828, 0.760525, 1.0) or UE.FLinearColor(0.278431, 0.329412, 0.47451, 1.0)
    ui.Text_NextValue:SetColorAndOpacity(textColor)
    -- ui.Text_NextValue:SetText(bShowUp and ((attrInfo.attrValue or 0) + (attrInfo.attrUp or 0)) or (attrInfo.attrValue or 0))
    if attrInfo.config.types == UIUtils.AttributeType.AbsoluteValue then
        local curValue = math.floor((attrInfo.attrValue or 0))
        local attrValue = math.floor((attrInfo.attrValue or 0) + (attrInfo.attrUp or 0))
        ui.Text_NextValue:SetText(attrValue)
        ui.Text_CurValue:SetText(bShowUp and curValue or "")
    else
        local curValue = math.floor((attrInfo.attrValue * 100 or 0))
        local attrValue = math.floor((attrInfo.attrValue * 100 or 0) + (attrInfo.attrUp * 100 or 0))
        ui.Text_NextValue:SetText(string.format('%d%%', attrValue))
        ui.Text_CurValue:SetText(bShowUp and string.format('%d%%', curValue) or "")
    end

    --ui.Text_NextValue:SetVisibility(bShowUp and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
    ui.Img_Arrow:SetVisibility(bShowUp and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
end

--材料列表
function M:BP_OnEntryInitialized_Mat(item, ui)
    local itemData = self.LevelUpItemList[item.Index]
    ui.Index = item.Index
    ui.ItemId = item.ItemId

    --点击事件
    ui.Btn_ItemAdd.OnGHSClicked:Clear()
    ui.Btn_ItemAdd.OnGHSClicked:Add(self, function()
        local audioPath = "/Script/Engine.SoundCue'/Game/_Game/SoundEffects/UI/Cue/SC_UI_add.SC_UI_add'";
        local audioSource = LoadObject(audioPath)
        if audioSource then
            if UE.UGameplayStatics.ObjectIsA(audioSource, UE.USoundBase.StaticClass()) then
                UE.UGameplayStatics.SpawnSound2D(self, audioSource)
            else
                LOG_ERROR("===错误的音频资源类型:", audioPath)
            end
        end
        if not self.IsFirstPlayNotifyUI then
            self.IsFirstPlayNotifyUI = true
            self:PlayAnimationForward(self.kuaisutouru, 1, false) 
        end
        if (self.TempLv < self.InitMaxLv) and itemData.selectCount < itemData.count then
            itemData.selectCount = itemData.selectCount + 1
            self.UserClickMat = true
            ui.Text_SelectCount:SetText(itemData.selectCount)
            ui.Btn_ItemSub:SetVisibility(itemData.selectCount > 0 and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
            self:InitAddData()
            self:RefreshAddExp()
            self:ScrollToLevel(self.TempLv - self.InitLv)
        else
            UIUtils.ShowItemInfo(item.ItemId, itemData.count)
        end
    end)
    --长按
    ui.Btn_ItemAdd.OnGHSPressed:Clear()
    ui.Btn_ItemAdd.OnGHSPressed:Add(self, function()
        self.LongPressItemIndex = item.Index
        self.LongPressItem = ui
        self.LongPressEvent = UE.UKismetSystemLibrary.K2_SetTimerDelegate(  
            { self, self.OnLongPressedAddEvent }, 
            self.IntervalTime, 
            true,
            self.InitialStartDelay)
    end)

    ui.Btn_ItemAdd.OnGHSReleased:Clear()
    ui.Btn_ItemAdd.OnGHSReleased:Add(self, function()
        self.LongPressItemIndex = 0
        self.LongPressItem = nil
        self.IsLongPressedAddButton = false
        if UE.UKismetSystemLibrary.IsValid(self.LongPressedSound) then
            self.LongPressedSound:Stop()
            self.LongPressedSound.bAutoDestroy = true
            self.LongPressedSound = nil
        end
        if self.LongPressEvent then
            UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.LongPressEvent)
            self.LongPressEvent = nil
        end
    end)


    ui.Btn_ItemSub.OnGHSClicked:Clear()
    ui.Btn_ItemSub.OnGHSClicked:Add(self, function()
        local audioPath = "/Script/Engine.SoundCue'/Game/_Game/SoundEffects/UI/Cue/SC_UI_sub.SC_UI_sub'"
        local audioSource = LoadObject(audioPath)
        if audioSource then
            if UE.UGameplayStatics.ObjectIsA(audioSource, UE.USoundBase.StaticClass()) then
                UE.UGameplayStatics.SpawnSound2D(self, audioSource)
            else
                LOG_ERROR("===错误的音频资源类型:", audioPath)
            end
        end
        if (self.TempLv <= self.InitMaxLv) and itemData.selectCount > 0 then
            itemData.selectCount = itemData.selectCount - 1
            self.UserClickMat = true
            ui.Text_SelectCount:SetText(itemData.selectCount)
            ui.Btn_ItemSub:SetVisibility(itemData.selectCount > 0 and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
            self:InitAddData()
            self:RefreshAddExp()
            self:ScrollToLevel(self.TempLv - self.InitLv)
        end
    end)

    --长按
    ui.Btn_ItemSub.OnGHSPressed:Clear()
    ui.Btn_ItemSub.OnGHSPressed:Add(self, function()
        self.LongPressItemIndex = item.Index
        self.LongPressItem = ui
        self.LongPressEvent = UE.UKismetSystemLibrary.K2_SetTimerDelegate(  
            { self, self.OnLongPressedSubEvent }, 
            self.IntervalTime, 
            true,
            self.InitialStartDelay)
    end)

    ui.Btn_ItemSub.OnGHSReleased:Clear()
    ui.Btn_ItemSub.OnGHSReleased:Add(self, function()
        self.LongPressItemIndex = 0
        self.LongPressItem = nil
        self.IsLongPressedSubButton = false
        if UE.UKismetSystemLibrary.IsValid(self.LongPressedSound) then
            self.LongPressedSound:Stop()
            self.LongPressedSound.bAutoDestroy = true
            self.LongPressedSound = nil
        end
        if self.LongPressEvent then
            UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.LongPressEvent)
            self.LongPressEvent = nil
        end
    end)
    
    --选中个数
    local selectCountStr = itemData.selectCount > 0 and itemData.selectCount or ""
    local textColor = UE.FSlateColor()
    textColor.SpecifiedColor = itemData.selectCount <= itemData.count and UE.FLinearColor(1.0, 1.0, 1.0, 1.0) or UE.FLinearColor(1.0, 0.0, 0.0, 1.0)
    ui.Text_SelectCount:SetColorAndOpacity(textColor)
    ui.Text_SelectCount:SetText(selectCountStr)

    --总个数
    ui.Text_Count:SetText(itemData.count)

    --稀有度背景图片
    if itemData.config.rarityPath and itemData.config.rarityPath ~= '' then
        local strArr = string.split(itemData.config.rarityPath, '/')
        local littePath = strArr[#strArr]
        local rarityPath = string.format('/Game/_Game/%s.%s', itemData.config.rarityPath, littePath)
        local itemRarityPic = LoadObject(rarityPath)
        if itemRarityPic then
            ui.bg_icon_res:SetBrushFromAtlasInterface(itemRarityPic)
        end
    end

    --icon
    if itemData.config.iconPath and itemData.config.iconPath ~= '' then
        local strArr = string.split(itemData.config.iconPath, '/')
        local littePath = strArr[#strArr]
        local iconResPath = string.format('/Game/_Game/%s.%s', itemData.config.iconPath, littePath)
        local iconRes = LoadObject(iconResPath)
        if iconRes then
            ui.icon_res:SetBrushFromAtlasInterface(iconRes)
        end
    end

    ui.lackState:SetVisibility(UE.ESlateVisibility.Hidden)

    ui.Btn_ItemSub:SetVisibility(itemData.selectCount > 0 and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
end

--材料列表点击
function M:BP_OnItemClicked_Mat(item)
    local itemData = self.LevelUpItemList[item.Index]
    UIUtils.ShowItemInfo(item.ItemId, itemData.selectCount)
end

function M:BP_OnEntryInitialized_BreakMat(item, ui)
    local itemData = self.LevelBreakItemList[item.Index]

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

    if itemData.config.iconPath and itemData.config.iconPath ~= '' then
        local strArr = string.split(itemData.config.iconPath, '/')
        local littePath = strArr[#strArr]
        local iconResPath = string.format('/Game/_Game/%s.%s', itemData.config.iconPath, littePath)
        local iconRes = LoadObject(iconResPath)
        if iconRes then
            ui.wp_icon_res:SetBrushFromAtlasInterface(iconRes)
        end
    end

    ui.lackState:SetVisibility(UE.ESlateVisibility.Hidden)
    --选中个数
    local textColor = UE.FSlateColor()
    textColor.SpecifiedColor = itemData.count >= itemData.needCount and UE.FLinearColor(0.0, 0.0, 0.0, 1.0) or UE.FLinearColor(1.0, 0.0, 0.0, 1.0)
    ui.Text_Count:SetColorAndOpacity(textColor)
    ui.Text_Count:SetText(itemData.count .. "/" .. itemData.needCount)
end

function M:BP_OnItemClicked_BreakMat(item)
    if not self.IsLongPressedAddButton and not self.IsLongPressedSubButton then
        local itemData = self.LevelBreakItemList[item.Index]
        UIUtils.ShowItemInfo(itemData.itemId, itemData.count)
    end
end

function M:BP_OnEntryInitialized_Level(item, ui)
    ui.Index = item.Index
    if not self.IsBreak then
        ui.Img_Max:SetVisibility(UE.ESlateVisibility.Hidden)
        ui.Text_Lv:SetVisibility(UE.ESlateVisibility.Hidden)
        ui.Text_Lv_1:SetVisibility(UE.ESlateVisibility.Hidden)
        
        if item.Index == (self.InitMaxLv + 1) then
            ui.Img_Max:SetVisibility(UE.ESlateVisibility.Visible)
            ui:SetRenderOpacity(1)
        elseif item.Index < self.InitLv or (item.Index > (self.InitMaxLv + 1)) then
            ui:SetRenderOpacity(0)
        else
            local textColor = UE.FSlateColor()
            if ui.Index == self.InitLv then
                ui.Text_Lv:SetVisibility(UE.ESlateVisibility.Visible)
                ui.Text_Lv:SetText(ui.Index)
                ui.Text_Lv_1:SetText(ui.Index)
            elseif math.abs(ui.Index - self.InitLv) == 1 then
                ui.Text_Lv:SetText(ui.Index)
                ui.Text_Lv_1:SetVisibility(UE.ESlateVisibility.Visible)
                ui.Text_Lv_1:SetText(ui.Index)
                textColor.SpecifiedColor = UE.FLinearColor(0.846873, 0.879623, 1.0, 1.0)
                ui.Text_Lv_1:SetColorAndOpacity(textColor)
            else
                ui.Text_Lv:SetText(ui.Index)
                ui.Text_Lv_1:SetVisibility(UE.ESlateVisibility.Visible)
                ui.Text_Lv_1:SetText(ui.Index)
                textColor.SpecifiedColor = UE.FLinearColor(0.846873, 0.879623, 1.0, 0.5)
                ui.Text_Lv_1:SetColorAndOpacity(textColor)
            end
            ui:SetRenderOpacity(1)
        end
    end
end

function M:BP_OnEntryInitialized_LevelBreak(item, ui)
    ui.Index = item.Index
    if self.IsBreak then
        ui.Img_Max:SetVisibility(UE.ESlateVisibility.Hidden)
        ui.Text_Lv:SetVisibility(UE.ESlateVisibility.Hidden)
        ui.Text_Lv_1:SetVisibility(UE.ESlateVisibility.Hidden)
        if item.Index == (self.MaxBreakTimes + 1) then
            ui.Img_Max:SetVisibility(UE.ESlateVisibility.Visible)
            ui:SetRenderOpacity(1)
        elseif item.Index < (self.InitBreakTimes + 1) or (item.Index > (self.MaxBreakTimes + 1)) then
            ui:SetRenderOpacity(0)
        else
            local textColor = UE.FSlateColor()
            if ui.Index == (self.InitBreakTimes + 1) then
                ui.Text_Lv:SetVisibility(UE.ESlateVisibility.Visible)
                ui.Text_Lv:SetText(ui.Index)
                ui.Text_Lv_1:SetText(ui.Index)
            elseif math.abs(ui.Index - (self.InitBreakTimes + 1)) == 1 then
                ui.Text_Lv:SetText(ui.Index)
                ui.Text_Lv_1:SetVisibility(UE.ESlateVisibility.Visible)
                ui.Text_Lv_1:SetText(ui.Index)
                textColor.SpecifiedColor = UE.FLinearColor(0.846873, 0.879623, 1.0, 1.0)
                ui.Text_Lv_1:SetColorAndOpacity(textColor)
            else
                ui.Text_Lv:SetText(ui.Index)
                ui.Text_Lv_1:SetVisibility(UE.ESlateVisibility.Visible)
                ui.Text_Lv_1:SetText(ui.Index)
                textColor.SpecifiedColor = UE.FLinearColor(0.846873, 0.879623, 1.0, 0.5)
                ui.Text_Lv_1:SetColorAndOpacity(textColor)
            end
            ui:SetRenderOpacity(1)
        end
    end
end

--材料列表加号长按
function M:OnLongPressedAddEvent()
    if self.LongPressItemIndex and self.LongPressItemIndex > 0 and self.LongPressItem then
        local itemData = self.LevelUpItemList[self.LongPressItemIndex]
        if (self.TempLv < self.InitMaxLv) and itemData.selectCount < itemData.count then
           
            if not self.IsLongPressedAddButton then
                local audioPath = "/Script/Engine.SoundCue'/Game/_Game/SoundEffects/UI/Cue/SC_UI_add_loop.SC_UI_add_loop'"
                local audioSource = LoadObject(audioPath)
                if audioSource then
                    if UE.UGameplayStatics.ObjectIsA(audioSource, UE.USoundBase.StaticClass()) then
                        self.LongPressedSound = UE.UGameplayStatics.SpawnSound2D(self, audioSource)
                    else
                        LOG_ERROR("===错误的音频资源类型:", audioPath)
                    end
                end
            end
            self.IsLongPressedAddButton = true

            itemData.selectCount = itemData.selectCount + 1
            self.UserClickMat = true
            self.LongPressItem.Text_SelectCount:SetText(itemData.selectCount)
            self.LongPressItem.Btn_ItemSub:SetVisibility(itemData.selectCount > 0 and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
            self:InitAddData()
            self:RefreshAddExp()
            self:ScrollToLevel(self.TempLv - self.InitLv)
        else
            self.IsLongPressedAddButton = false
            if UE.UKismetSystemLibrary.IsValid(self.LongPressedSound) then
                self.LongPressedSound:Stop()
                self.LongPressedSound.bAutoDestroy = true
                self.LongPressedSound = nil
            end
            if self.LongPressEvent then
                UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.LongPressEvent)
                self.LongPressEvent = nil
            end
        end
    end
end

--材料列表减号长按
function M:OnLongPressedSubEvent()
    if self.LongPressItemIndex and self.LongPressItemIndex > 0 and self.LongPressItem then
        local itemData = self.LevelUpItemList[self.LongPressItemIndex]
        if (self.TempLv <= self.InitMaxLv) and itemData.selectCount > 0 then
            if not self.IsLongPressedSubButton then
                local audioPath = "/Script/Engine.SoundCue'/Game/_Game/SoundEffects/UI/Cue/SC_UI_sub_loop.SC_UI_sub_loop'"
                local audioSource = LoadObject(audioPath)
                if audioSource then
                    if UE.UGameplayStatics.ObjectIsA(audioSource, UE.USoundBase.StaticClass()) then
                        self.LongPressedSound = UE.UGameplayStatics.SpawnSound2D(self, audioSource)
                    else
                        LOG_ERROR("===错误的音频资源类型:", audioPath)
                    end
                end
            end
           
            self.IsLongPressedSubButton = true
            itemData.selectCount = itemData.selectCount - 1
            self.UserClickMat = true
            self.LongPressItem.Text_SelectCount:SetText(itemData.selectCount)
            self.LongPressItem.Btn_ItemSub:SetVisibility(itemData.selectCount > 0 and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
            self:InitAddData()
            self:RefreshAddExp()
            self:ScrollToLevel(self.TempLv - self.InitLv)
        else
            self.IsLongPressedSubButton = false
            if UE.UKismetSystemLibrary.IsValid(self.LongPressedSound) then
                self.LongPressedSound:Stop()
                self.LongPressedSound.bAutoDestroy = true
                self.LongPressedSound = nil
            end
            if self.LongPressEvent then
                UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.LongPressEvent)
                self.LongPressEvent = nil
            end
        end
    end
end

------------------------------------------------------------------------------
---辅助函数
function M:GetItemSubType()
    if self.UITag == "Character" then
        return UIUtils.ItemTempPropType.CharacterExp
    elseif self.UITag == "Weapon" then
        return UIUtils.ItemTempPropType.WeaponExp
    elseif self.UITag == "Equip" then
        return UIUtils.ItemTempPropType.EquipExp
    end
end

function M:GetGoldCoinRate()
    if self.UITag == "Character" then
        return d_com_params[1].value[2]
    elseif self.UITag == "Weapon" then
        return d_com_params[2].value[2]
    elseif self.UITag == "Equip" then
        return d_com_params[3].value[2]
    end
end

function M:GetLevelInfo(id, breakTimes, exp)
    if self.UITag == "Character" then
        return UIUtils.GetCharacterLevel(id, breakTimes, exp)
    elseif self.UITag == "Weapon" then
        return UIUtils.GetWeaponLevel(id, breakTimes, exp)
    elseif self.UITag == "Equip" then
        return UIUtils.GetEquipLevel(id, breakTimes, exp)
    end
end

--最大突破等级
function M:GetInitMaxBreakTimes()
    if self.UITag == "Character" then
        return UIUtils.GetCharacterMaxBreakTimes(self.InitId)
    elseif self.UITag == "Weapon" then
        return UIUtils.GetWeaponMaxBreakTimes(self.InitId)
    elseif self.UITag == "Equip" then
        return UIUtils.GetEquipMaxBreakTimes(self.InitId)
    end
end

--最大等级
function M:GetInitMaxLevel(breakTimes)
    if self.UITag == "Character" then
        return UIUtils.GetCharacterMaxLevel(self.InitId, breakTimes or self.InitBreakTimes)
    elseif self.UITag == "Weapon" then
        return UIUtils.GetWeaponMaxLevel(self.InitId, breakTimes or self.InitBreakTimes)
    elseif self.UITag == "Equip" then
        return UIUtils.GetEquipMaxLevel(self.InitId, breakTimes or self.InitBreakTimes)
    end
end

--最大突破次数下的最大等级
function M:GetMaxLvWithMaxBreakTimes()
    if self.UITag == "Character" then
        local maxBreakTimes = UIUtils.GetCharacterMaxBreakTimes(self.InitId)
        return UIUtils.GetCharacterMaxLevel(self.InitId, maxBreakTimes)
    elseif self.UITag == "Weapon" then
        local maxBreakTimes = UIUtils.GetWeaponMaxBreakTimes(self.InitId)
        return UIUtils.GetWeaponMaxLevel(self.InitId, maxBreakTimes)
    elseif self.UITag == "Equip" then
        local maxBreakTimes = UIUtils.GetEquipMaxBreakTimes(self.InitId)
        return UIUtils.GetEquipMaxLevel(self.InitId, maxBreakTimes)
    end
end

----------------------------------------------------------------------
---升级配置
function M:GetLevelUpAttrList()
    local attrList = {}
    local d_attributes = require("ClientDatas.d_attributes")
    if self.UITag == "Character" then
        local addAttr = UIUtils.GetCharacterLevelUpAttr(self.InitId, self.InitLv, self.TempLv) --可能等级一样 每提升属性
        
        local characterAttr = UIUtils.GetCharacterAttr(self.InitId, self.InitLv, self.InitBreakTimes)
        local attrEx = UIUtils.GetCharacterAttrEx(self.InitId)
        for i, v in pairs(attrEx) do
            characterAttr[i] = (characterAttr[i] or 0) + v
        end

        --固定属性 1001, 1002, 1003, 1004
        local attrMaxHp = {
            attrId = 1001,
            attrValue = characterAttr[1001],
            attrUp = addAttr[1001] or 0,
            config = d_attributes[1001]
        }
        table.insert(attrList, attrMaxHp)
        local attrAttack = {
            attrId = 1002,
            attrValue = characterAttr[1002],
            attrUp = addAttr[1002] or 0,
            config = d_attributes[1002]
        }
        table.insert(attrList, attrAttack)
        local attrPhysicalDefense = {
            attrId = 1024,
            attrValue = characterAttr[1024],
            attrUp = addAttr[1024] or 0,
            config = d_attributes[1024]
        }
        table.insert(attrList, attrPhysicalDefense)
        local attrMagicDefense = {
            attrId = 1025,
            attrValue = characterAttr[1025],
            attrUp = addAttr[1025] or 0,
            config = d_attributes[1025]
        }
        table.insert(attrList, attrMagicDefense)
    elseif self.UITag == "Weapon" then
        local addAttr = UIUtils.GetWeaponLevelUpAttr(self.InitId, self.InitLv, self.TempLv)
        local baseAttr = UIUtils.GetWeaponBaseAttr(self.InitId, self.InitLv)
        for id, value in pairs(baseAttr) do 
            local attr = {
                attrId = id,
                attrValue = value,
                attrUp = addAttr[id] or 0,
                config = d_attributes[id]
            }
            table.insert(attrList, attr)
        end
    elseif self.UITag == "Equip" then
        local addAttr = UIUtils.GetEquipLevelUpAttr(self.InitId, self.InitLv, self.TempLv)
        local baseAttr = UIUtils.GetEquipBaseAttr(self.InitArmInfo)
        for id, value in pairs(baseAttr) do 
            local attr = {
                attrId = id,
                attrValue = value,
                attrUp = addAttr[id] or 0,
                config = d_attributes[id]
            }
            table.insert(attrList, attr)
        end
    end
    return attrList
end

--获取要升级消耗的道具数据
function M:GetLevelUpMaterialList()
    local result = {}
    local itemNum = 0
    local materailConfigList = UIUtils.GetAllItemConfigByType(UIUtils.ItemMainType.TempProp, self:GetItemSubType())
    for k, v in pairs(materailConfigList) do
        local item = {
            item_id = k,
            count = BackpackSystem:GetInstance():GetItemCount(k),
            selectCount = 0,
            config = v
        }
        table.insert(result, item)
        itemNum = itemNum + 1
    end
    
    if itemNum > 1 then
        table.sort(result, function(a, b)
            return a.item_id < b.item_id
        end)
    end
    return result
end

function M:GetAddExp()
    local result = 0
    if self.LevelUpItemList then
        for _, v in pairs(self.LevelUpItemList) do
            result = result + v.selectCount * v.config.subParam[1]
        end
    end
    return result
end

----------------------------------------------------------------------
---突破配置
function M:GetLevelBreakItemConfig(onlySingle)
    if self.UITag == "Character" then
        return UIUtils.GetCharacterLevelBreakMat(self.InitId, onlySingle and (self.TempBreakTimes - 1) or self.InitBreakTimes, self.TempBreakTimes)
    elseif self.UITag == "Weapon" then
        return UIUtils.GetWeaponLevelBreakMat(self.InitId, onlySingle and (self.TempBreakTimes - 1) or self.InitBreakTimes, self.TempBreakTimes)
    elseif self.UITag == "Equip" then
        return UIUtils.GetEquipLevelBreakMat(self.InitId, onlySingle and (self.TempBreakTimes - 1) or self.InitBreakTimes, self.TempBreakTimes)
    end
    return nil
end

--突破所需材料
function M:GetLevelBreakMaterialList(onlySingle)
    local currencyList = {}
    local matList = {}
    local levelBreakConfigList = self:GetLevelBreakItemConfig(onlySingle)
    local bCanBreak = true
    if levelBreakConfigList then
        for itemId, count in pairs(levelBreakConfigList) do
            local hasCount = BackpackSystem:GetInstance():GetItemCount(itemId)
            local config = UIUtils.GetItemConfigById(itemId)
            
            local item = {
                itemId = itemId,
                needCount = count,
                count = hasCount,
                config = config
            }
            if config.itemType == UIUtils.ItemMainType.Currency then
                table.insert(currencyList, item)
            else
                table.insert(matList, item)
            end
            if count > hasCount then
                bCanBreak = false
            end
        end
    end
    
    return currencyList, matList, bCanBreak
end

function M:GetLevelBreakNextItemConfig()
    if self.UITag == "Character" then
        local baseAttr = UIUtils.GetCharacterAttr(self.InitId, self.InitLv, self.InitBreakTimes)
        local attrEx = UIUtils.GetCharacterAttrEx(self.InitId)
        for i, v in pairs(attrEx) do
            baseAttr[i] = (baseAttr[i] or 0) + v
        end
        return UIUtils.GetCharacterLevelBreakAttr(self.InitId, self.InitBreakTimes, self.TempBreakTimes), baseAttr
    elseif self.UITag == "Weapon" then
        return UIUtils.GetWeaponLevelBreakAttr(self.InitId, self.InitBreakTimes, self.TempBreakTimes), UIUtils.GetWeaponAttr(self.InitId, self.InitLv, self.InitBreakTimes)
    elseif self.UITag == "Equip" then
        return UIUtils.GetEquipLevelBreakAttr(self.InitId, self.InitBreakTimes, self.TempBreakTimes), UIUtils.GetEquipAttr(self.InitArmInfo)
    end
    return nil
end

--突破属性列表
function M:GetLevelBreakAttrList()
    local attrList = {}
    local d_attributes = require("ClientDatas.d_attributes")
    local addAttrInfo, baseAttrInfo = self:GetLevelBreakNextItemConfig()
    if addAttrInfo then
        for attrId, upValue in pairs(addAttrInfo) do
            local attr = {
                attrId = attrId,
                attrValue = baseAttrInfo[attrId] or 0, 
                attrUp = upValue,
                config = d_attributes[attrId],
            }
            table.insert(attrList, attr)
        end
    end
    return attrList
end

function M:GetSelectedBagItem()
    local itemInfos = {}
    local bagInfo = BackpackSystem:GetInstance().BagInfo
    
    for _, v in pairs(self.LevelUpItemList) do
        local needCount = v.selectCount
        local itemInfo = bagInfo[v.item_id]
        if itemInfo then
            for _, item in pairs(itemInfo) do
                if needCount <= 0 then
                    break
                elseif needCount >= item.count then
                    table.insert(itemInfos, {
                        item_uuid = item.item_uuid,
                        count = item.count
                    })
                    needCount = needCount - item.count
                elseif needCount < item.count then
                    table.insert(itemInfos, {
                        item_uuid = item.item_uuid,
                        count = needCount
                    })
                    needCount = needCount - item.count
                end
            end
        end
    end
    return itemInfos
end

function M:GetNeedExp()
    if self.UITag == "Character" then
        return UIUtils.GetCharacterAllExp(self.TempLv or (self.InitLv)) - self.InitExp
    elseif self.UITag == "Weapon" then
        return UIUtils.GetWeaponAllExp(self.InitId, self.TempLv or (self.InitLv)) - self.InitExp
    elseif self.UITag == "Equip" then
        return UIUtils.GetEquipAllExp(self.InitId, self.TempLv or (self.InitLv)) - self.InitExp
    end
    return 0
end

return M