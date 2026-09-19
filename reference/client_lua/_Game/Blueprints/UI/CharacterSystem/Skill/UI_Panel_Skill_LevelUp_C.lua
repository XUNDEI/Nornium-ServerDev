local UIUtils = require "_Game.Utils.UIUtils"
local Database = require("_Game.Utils.Database")
local BackpackSystem = require "Module.Backpack.BackpackSystem"
local CharacterSystem = require "Module.CharacterSystem.CharacterSystem"
local Client = require "Network.Client"
local PlayerSystem = require "Module.Player.PlayerSystem"
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_Panel_Equip_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
}

function M:Construct()
    self:InitData()
    self:InitUI()
    MessageManager:GetInstance():AddListener("OnMsg_Req_Character_Skill_Level_Up_Success", self)
end

function M:Destruct()
    MessageManager:GetInstance():RemoveListener("OnMsg_Req_Character_Skill_Level_Up_Success", self)
end

function M:InitData()
    
end

function M:InitUI()
    self.Btn_Close.OnGHSClicked:Add(self, self.OnClicked_Btn_Close)
    self.Btn_LevelUp.OnGHSClicked:Add(self, self.OnClicked_Btn_LevelUp)

    self.List_Attr.BP_OnEntryInitialized:Clear()
    self.List_Attr.BP_OnEntryInitialized:Add(self, function(wbp, itemData, widget) 
        self:BP_OnEntryInitialized_Attr(itemData, widget)
    end)

    self.List_Mat.BP_OnEntryInitialized:Clear()
    self.List_Mat.BP_OnEntryInitialized:Add(self, function(wbp, itemData, widget) 
        self:BP_OnEntryInitialized_Mat(itemData, widget)
    end)

    self.List_Mat.BP_OnItemClicked:Clear()
    self.List_Mat.BP_OnItemClicked:Add(self, function(wbp, itemData) 
        self:BP_OnItemClicked_Mat(itemData)
    end)
end

function M:OnMsg_Req_Character_Skill_Level_Up_Success()
    --显示升级提示框
    local ui = UE4.UGameplayStatics.GetGameInstance(self):AddUMG('UI_levelup_success')
    ui:RefreshUI(2, self.InitSkillLv, self.InitSkillLv + 1, self.InitSkillId, nil)

    UIManager:GetInstance():RemoveUI(self)
end

function M:RefreshUI(preui, charId, skillId, skillLv)
    self.PreUI = preui
    self.InitCharId = charId
    self.InitSkillId = skillId
    self.InitSkillLv = skillLv
    local d_skill = require("ClientDatas.d_skill")
    if not d_skill or not d_skill[skillId] then
        LOG_ERROR("========获取不到数据:d_skill, skillId:" .. tostring(skillId))
        return
    end
    local skillConfig = d_skill[skillId]
    self.Text_SkillName:SetText(Database.L10n(skillConfig.skillName))
    self.Text_SkillLv:SetText("Lv." .. skillLv)
    self.Text_SkillLvNext:SetText("Lv." .. (skillLv + 1))

    local skillLvConfig = UIUtils.GetSkillFightLvConfig(skillId, skillLv)
    local skillNextLvConfig = UIUtils.GetSkillFightLvConfig(skillId, skillLv + 1)
    if not skillLvConfig then
        LOG_ERROR("========获取不到数据:d_skill_fight_level: skillId:" .. tostring(skillId) .. ",skillLv:" .. tostring(skillLv))
        return 
    end

    local descList, valueList = UIUtils.ParseSkillParams(skillId, skillLv)
    local nextValueList = valueList
    if skillNextLvConfig then
        local _, vlist = UIUtils.ParseSkillParams(skillId, skillLv + 1)
        nextValueList = vlist
    end

    local ItemSourcePath = "/Script/Engine.Blueprint'/Game/_Game/Blueprints/UI/UI_Character/UI_Data/BP_ListItemData.BP_ListItemData_C'"
    local ItemClass = UE.UClass.Load(ItemSourcePath)

    --属性 
    local arrItemListDataSource = {}

    for k, desStr in ipairs(descList) do
        local itemData = NewObject(ItemClass)
        itemData.Index = k
        itemData.Value = desStr
        itemData.ValueEx = (valueList[k] or '') .. '|' .. (nextValueList[k] or '')
        table.insert(arrItemListDataSource, itemData)
    end
    self.List_Attr:ClearListItems()
    self.List_Attr:BP_SetListItems(arrItemListDataSource)

    --解析材料
    local currencyList, matList, bIsfull = UIUtils.ParseMatrailConfig(skillLvConfig.material)
    self.MaterialList = matList
    local BagSystem = require "Module.Backpack.BackpackSystem"
    if #currencyList == 0 then
        currencyList[1] = {
            item_id = 9001,
            count = BagSystem:GetInstance():GetItemCount(9001),
            needCount = 0,
        }
    end
    --货币
    local hasGold = currencyList[1].count
    local needGold = currencyList[1].needCount

    --货币类型
    local currencyId = currencyList[1].item_id
    local currencyConfig = UIUtils.GetItemConfigById(currencyId)
    --icon
    --货币图片
    local iconResPath = string.format('/Game/_Game/TP_New/Common/Frames/Icon_%d_png.Icon_%d_png', currencyConfig.id, currencyConfig.id)
    local iconRes = LoadObject(iconResPath)
    if iconRes then
        self.Image_2:SetBrushFromAtlasInterface(iconRes)
    end

    local textColor = UE.FSlateColor()
    textColor.SpecifiedColor = hasGold >= needGold and UE.FLinearColor(1.0, 1.0, 1.0, 1.0) or UE.FLinearColor(1.0, 0.0, 0.0, 1.0)
    self.Text_HaveGold:SetColorAndOpacity(textColor)
    self.Text_HaveGold:SetText("/" .. hasGold)
    self.Text_NeedGold:SetText(needGold)

    --材料列表
    local ItemListDataSource = {}
    for index = 1, #self.MaterialList do
        local itemData = NewObject(ItemClass)
        itemData.Index = index
        itemData.Id = self.MaterialList[index].item_id
        table.insert(ItemListDataSource, itemData)
    end
    self.List_Mat:ClearListItems()
    self.List_Mat:BP_SetListItems(ItemListDataSource)

    --升级技能需要的角色等级
    local isUnlock = true
    if skillLvConfig and skillLvConfig.condition and '' ~= skillLvConfig.condition then
        isUnlock = UIUtils.IsUnlock(self.InitCharId, skillLvConfig.condition)
    end

    local canLevelUp = isUnlock and hasGold >= needGold and bIsfull
    LOG_DEBUG("========canLevelUp:", canLevelUp, "isUnlock:", isUnlock, "hasGold:", hasGold, "needGold:", needGold, "bIsfull:", bIsfull, skillLvConfig and table.dump(skillLvConfig.condition))
    self.Btn_LevelUp:SetIsEnabled(canLevelUp)
end

----------------------------------------------------------------------\
---点击事件
function M:OnClicked_Btn_Close()
    if self.PreUI then
        self.PreUI:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        self.PreUI = nil
    end
    UIManager:GetInstance():RemoveUI(self)
end

function M:OnClicked_Btn_LevelUp()

    local SrpgController = require('Module.Srpg.SrpgController')
    if SrpgController:GetInstance():HasPendingFight() then
        UIUtils.ShowNotify(self, Database.L10n(285))
        return
    end
    
    --时间判定
    if not self.LastReqLevelUpTime then 
        self.LastReqLevelUpTime = PlayerSystem:GetInstance():GetServerTime() - 1
    end
    local now = PlayerSystem:GetInstance():GetServerTime()
    if now - self.LastReqLevelUpTime <= 0.5 then return end
    self.LastReqLevelUpTime = now

    --self:SetVisibility(UE.ESlateVisibility.Hidden)
    CharacterSystem:GetInstance():CacheSkillInfo(self.InitCharId, self.InitSkillId, self.InitSkillLv + 1)
    local msg = {
        character_id = self.InitCharId,
        skill_id = self.InitSkillId,
        item_infos = self:GetSelectedBagItem()
    }
    print("======ReqCharacterSkillLevelUp:" .. tostring(table.dump(msg, false, 10)))
    Client.send("req_character_skill_level_up", msg)
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.OnClicked_Btn_Close)
InputUtils.RegisterUIAction(M, InputAssets.IA_Confirm, UE.ETriggerEvent.Completed, M.OnClicked_Btn_LevelUp)

function M:BP_OnEntryInitialized_Attr(itemData, ui)
    local values = string.split(itemData.ValueEx, '|')
    ui.Text_Title:SetText(itemData.Value)
    ui.Text_CurValue:SetText(values[1])
    ui.Text_NextValue:SetText(values[2])
    ui.Img_Bg:SetVisibility(itemData.Index % 2 == 1 and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
end

function M:BP_OnEntryInitialized_Mat(item_data, ui)
    local itemData = self.MaterialList[item_data.Index]

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

    local hasMat = itemData.count > 0
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

    --选中个数
    local textColor = UE.FSlateColor()
    textColor.SpecifiedColor = itemData.count >= itemData.needCount and UE.FLinearColor(0.0, 0.0, 0.0, 1.0) or UE.FLinearColor(1.0, 0.0, 0.0, 1.0)
    ui.Text_Count:SetColorAndOpacity(textColor)
    ui.Text_Count:SetText(itemData.count .. "/" .. itemData.needCount)
end

function M:BP_OnItemClicked_Mat(item_data)
    local itemData = self.MaterialList[item_data.Index]
    UIUtils.ShowItemInfo(itemData.item_id, itemData.hasCount)
end

----------------------------------------------------------------------
---辅助函数
function M:GetSelectedBagItem()
    local itemInfos = {}
    local bagInfo = BackpackSystem:GetInstance().BagInfo
    for _, v in pairs(self.MaterialList) do
        local needCount = v.needCount
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

return M