local UIUtils = require "_Game.Utils.UIUtils"
local Database = require("_Game.Utils.Database")
local CharacterSystem = require "Module.CharacterSystem.CharacterSystem"
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
   
end

function M:Destruct()
   
end

function M:Tick(MyGeometry, deltaTime)
    if self.StartLvUpAnimation then
        self.PastTime = self.PastTime + deltaTime
        if self.PastTime > self.ItemAnimationDelayTime then
            local realTime = self.PastTime - self.ItemAnimationDelayTime
            local curTime = self.ItemAnimationTime + (self.IntiAnimationIndex - 1) / 7 * self.ItemAnimationTime + (self.IntiAnimationIndex - 1) % 7 * self.ItemAnimationTime
            if realTime > curTime then
                local list = self.ListView_Attr
                if list then
                    local widgets = list:GetDisplayedEntryWidgets()
                    if self.IntiAnimationIndex <= widgets:Length() then
                        local ui = widgets:Get(self.IntiAnimationIndex)
                        if ui then
                            ui:PlayAnimationForward(ui.In, 1, false)
                        end
                    else
                        self.StartLvUpAnimation = false
                    end
                    self.IntiAnimationIndex = self.IntiAnimationIndex + 1
                else
                    self.StartLvUpAnimation = false
                end
            end
        end
    end
end

function M:InitData()

end
function M:InitUI()
    self.Img_Bg.OnMouseButtonDownEvent:Unbind()
    self.Img_Bg.OnMouseButtonDownEvent:Bind(self, self.OnClicked_Img_Bg)

    self.ListView_Reward.BP_OnEntryInitialized:Add(self, function(wbp, data, ui) 
        self:BP_OnEntryInitialized_Reward(data, ui)
    end)
    self.ListView_Reward.BP_OnItemClicked:Add(self, function(wbp, itemData)
        self:BP_OnItemClicked_Reward(itemData)
    end)
    self.ListView_SkillAttr.BP_OnEntryInitialized:Add(self, function(wbp, data, ui)
        self:BP_OnEntryInitialized_SkillAttr(data, ui)
    end)
    self.ListView_SkillAttr2.BP_OnEntryInitialized:Add(self, function(wbp, data, ui)
        self:BP_OnEntryInitialized_SkillAttr2(data, ui)
    end)
    self.ListView_Attr.BP_OnEntryInitialized:Add(self, function(wbp, data, ui)
        self:BP_OnEntryInitialized_Attr(data, ui)
    end)
end

function M:RefreshUI(charId, effectType, effectItemList)
    print("===类型:" .. tostring(effectType))
    self.CharId = charId
    self.ItemDataSource = effectItemList
    
    self.Panel_Reward:SetVisibility(effectType == UIUtils.CharTalentEffectType.Item and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)

    local isSkill = effectType == UIUtils.CharTalentEffectType.Skill
    local isSkillUp = effectItemList[1].value > 1
    self.Panel_Skill:SetVisibility((isSkill and not isSkillUp) and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
    self.Panel_SkillLevelUP:SetVisibility((isSkill and isSkillUp) and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
  
    local isCharacteristic = effectType == UIUtils.CharTalentEffectType.Characteristic
    local isCharacteristicUp = effectItemList[1].value > 1
    self.Panel_Characteristic:SetVisibility((isCharacteristic and not isCharacteristicUp) and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
    self.Panel_CharacteristicLevelUP:SetVisibility((isCharacteristic and isCharacteristicUp) and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
  
    self.Panel_Attr:SetVisibility(effectType == UIUtils.CharTalentEffectType.Atrribute and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
    
    print("===道具类型:" .. tostring(table.dump(effectItemList, nil, 10)))
    if effectType == UIUtils.CharTalentEffectType.Item then
        self:RefreshReward()
        self:PlayAnimationForward(self.Reward)
    elseif effectType == UIUtils.CharTalentEffectType.Skill then
        if isSkillUp then
            self:RefreshSkillUp()
            self:PlayAnimationForward(self.SkillLevelUp)
        else
            self:RefreshSkill()
            self:PlayAnimationForward(self.Skill)
        end
    elseif effectType == UIUtils.CharTalentEffectType.Characteristic then
        if isCharacteristicUp then
            self:RefreshCharacteristicLevelUp()
            self:PlayAnimationForward(self.CharacteristicLevelUp)
        else
            self:RefreshCharacteristic()
            self:PlayAnimationForward(self.Characteristic)
        end
    elseif effectType == UIUtils.CharTalentEffectType.Atrribute then
        self:RefreshAtrribute()
        self:PlayAnimationForward(self.Attr)
    end
end

function M:RefreshReward()
    local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
    local ItemClass = UE.UClass.Load(ItemSourcePath)
    local attrDataSource = {}
    for i = 1, #self.ItemDataSource do
        local itemData = NewObject(ItemClass)
        itemData.Index = i
        itemData.ItemId = self.ItemDataSource[i].id
        table.insert(attrDataSource, itemData)
    end
    self.ListView_Reward:ClearListItems()
    self.ListView_Reward:BP_SetListItems(attrDataSource)
    
end

function M:RefreshSkill()
    local skillId = self.ItemDataSource[1].id
    local skillLv = self.ItemDataSource[1].value 
    local skillConfig = Database.Query('d_skill', skillId)
    if not skillConfig then
        LOG_ERROR('----->天赋技能:' .. tostring(skillId) .. ", d_skill 表中未找到！")
        return
    end
    self.Text_SkillName:SetText(Database.L10n(skillConfig.skillName))
    self.Text_SkillLv:SetText("Lv." .. tostring(skillLv))
    
    local isActiveSkill = skillConfig.belong == UIUtils.ESkillTabType.Active
    -- self.active_skill_base:SetVisibility(isActiveSkill and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
    -- self.passive_skill_base:SetVisibility(not isActiveSkill and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
    --icon
    local iconPath = string.format("/Script/Paper2D.PaperSprite'/Game/_Game/TP_New/Character_skill_res/Frames/%s_png.%s_png'", skillConfig.showIcon, skillConfig.showIcon)
    local iconObj = LoadObject(iconPath)
    if iconObj then
        self.skill_icon_res:SetBrushFromAtlasInterface(iconObj)
    end
end

function M:RefreshSkillUp()
    local skillId = self.ItemDataSource[1].id
    local skillLv = self.ItemDataSource[1].value 
    local skillConfig = Database.Query('d_skill', skillId)
    local isActiveSkill = skillConfig.belong == UIUtils.ESkillTabType.Active

    --icon
    local iconPath = string.format("/Script/Paper2D.PaperSprite'/Game/_Game/TP_New/Character_skill_res/Frames/%s_png.%s_png'", skillConfig.showIcon, skillConfig.showIcon)
    local iconObj = LoadObject(iconPath)
    if iconObj then
        self.skill_icon_res_old:SetBrushFromAtlasInterface(iconObj)
        self.skill_icon_res_new:SetBrushFromAtlasInterface(iconObj)
    end
    
    self.Text_SkillLv_Old:SetText("Lv." .. tostring(skillLv - 1))
    self.Text_SkillLv_New:SetText("Lv." .. tostring(skillLv))

    local skillLvConfig = UIUtils.GetSkillFightLvConfig(skillId, skillLv - 1)
    local skillNextLvConfig = UIUtils.GetSkillFightLvConfig(skillId, skillLv)
    if not skillLvConfig then
        LOG_ERROR("========获取不到数据:d_skill_fight_level: skillId:" .. tostring(skillId) .. ",skillLv:" .. tostring(preLv))
        return 
    end
    if not skillNextLvConfig then
        skillNextLvConfig = skillLvConfig
    end
    
    local ItemSourcePath = "/Script/Engine.Blueprint'/Game/_Game/Blueprints/UI/UI_Character/UI_Data/BP_ListItemData.BP_ListItemData_C'"
    local ItemClass = UE.UClass.Load(ItemSourcePath)
    --属性 
    local arrItemListDataSource = {}
    local arrItemListDataSource2 = {}
    local desStrArr = string.split(Database.L10n(skillConfig.paramsItem), '|')
    local paramStrArr = string.split(skillLvConfig.inbornSkill, ',')
    local nextParamStrArr = string.split(skillNextLvConfig.inbornSkill, ',')
    for k, desStr in ipairs(desStrArr) do
        local itemData = NewObject(ItemClass)
        itemData.Index = k
        itemData.Value = desStr
        itemData.ValueEx = paramStrArr[k]
        table.insert(arrItemListDataSource, itemData)

        local itemData2 = NewObject(ItemClass)
        itemData2.Index = k
        itemData2.Value = desStr
        itemData.ValueEx = (paramStrArr[k] or '') .. '|' .. (nextParamStrArr[k] or '')
        table.insert(arrItemListDataSource2, itemData2)
    end

    self.ListView_SkillAttr:ClearListItems()
    self.ListView_SkillAttr:BP_SetListItems(arrItemListDataSource)

    self.ListView_SkillAttr2:ClearListItems()
    self.ListView_SkillAttr2:BP_SetListItems(arrItemListDataSource2)
end

function M:RefreshCharacteristic()
    local characteristicId = self.ItemDataSource[1].id
    local characteristicLv = self.ItemDataSource[1].value 

    local config = Database.Query('d_characteristic', characteristicId)

    --特性icon
    local iconPath = string.format("/Game/_Game/TP_New/Character_Detail_res/Frames/%s_png.%s_png", config.characteristicIcon, config.characteristicIcon)
    local iconObj = LoadObject(iconPath)
    if iconObj then
        self.Img_FeatureIcon:SetBrushFromAtlasInterface(iconObj)
    end
    --特性title
    self.Text_CharacteristicName:SetText(Database.L10n(config.characteristicName))
    --特性等级
    self.Text_CharacteristicLv:SetText("LV." .. characteristicLv)
end

function M:RefreshCharacteristicLevelUp()
    local characteristicId = self.ItemDataSource[1].id
    local characteristicLv = self.ItemDataSource[1].value 

    local config = Database.Query('d_characteristic', characteristicId)
    --特性icon
    local iconPath = string.format("/Game/_Game/TP_New/Character_Detail_res/Frames/%s_png.%s_png", config.characteristicIcon, config.characteristicIcon)
    local iconObj = LoadObject(iconPath)
    if iconObj then
        self.Img_FeatureIcon_1:SetBrushFromAtlasInterface(iconObj)
        self.Img_FeatureIcon_2:SetBrushFromAtlasInterface(iconObj)
    end
    --特性title
    self.Text_CharacteristicName:SetText(Database.L10n(config.characteristicName))
    --特性等级
    self.Text_CharacteristicLv2:SetText("LV." .. (characteristicLv - 1))
    self.Text_CharacteristicLv3:SetText("LV." .. characteristicLv)
end

function M:RefreshAtrribute()
    print("====>>" .. tostring(#self.ItemDataSource))
    local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
    local ItemClass = UE.UClass.Load(ItemSourcePath)
    local attrDataSource = {}
    for i = 1, #self.ItemDataSource do
        local itemData = NewObject(ItemClass)
        itemData.Index = i
        itemData.ItemId = self.ItemDataSource[i].id
        table.insert(attrDataSource, itemData)
    end
    self.ListView_Attr:ClearListItems()
    self.ListView_Attr:BP_SetListItems(attrDataSource)

    --开始列表动画
    self.PastTime = 0
    self.IntiAnimationIndex = 1
    self.StartLvUpAnimation = true
end

----------------------------------------------------------------------
----------------------------------------------------------------------
function M:OnClicked_Img_Bg()
    UIManager:GetInstance():RemoveUI(self)
    return UE.UWidgetBlueprintLibrary.Handled()
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.OnClicked_Img_Bg)
InputUtils.RegisterUIAction(M, InputAssets.IA_Confirm, UE.ETriggerEvent.Completed, M.OnClicked_Img_Bg)

function M:BP_OnEntryInitialized_Reward(data, ui)
    local itemData = self.ItemDataSource[data.Index]

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
    local itemData = self.ItemDataSource[data.Index]
    UIUtils.ShowItemInfo(itemData.id, itemData.value)
end

function M:BP_OnEntryInitialized_SkillAttr(itemData, ui)
    ui.Text_Title:SetText(itemData.Value)
    ui.Text_CurValue:SetText(itemData.ValueEx)
    ui.Img_Bg:SetVisibility(itemData.Index % 2 == 1 and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
end

function M:BP_OnEntryInitialized_SkillAttr2(itemData, ui)
    ui.Text_Title:SetText(itemData.Value)
    ui.Text_CurValue:SetText(itemData.ValueEx)
    ui.Img_Bg:SetVisibility(itemData.Index % 2 == 1 and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
end

function M:BP_OnEntryInitialized_Attr(data, ui)
    local itemData = self.ItemDataSource[data.Index]
    local attrId = itemData.id
    local addValue = itemData.value
    local curAttrs = UIUtils.GetCharacterAllAttr(self.CharId, true)
    local attrValue = curAttrs[attrId] or 0
    local attrConfig = Database.Query('d_attributes', attrId)

    print('----addvalue:' .. tostring(addValue) .. ",attrValue:" .. tostring(attrValue))
    local oldAtrr = attrValue - addValue
    --背景图片
    --ui.Img_Bg:SetVisibility((data.Index % 2 == 1) and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Collapsed)
    --属性类型图片
    local iconPath = string.format("'/Game/_Game/TP_New/Attribute_res/Frames/%s_png.%s_png'", attrConfig.attrIcon, attrConfig.attrIcon)
    local iconObj = LoadObject(iconPath)
    if iconObj then
        ui.Img_Icon:SetBrushFromAtlasInterface(iconObj)
    end
    ui.Img_Arrow:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    ui.Text_Title:SetText(Database.L10n(attrConfig.attrName))
    if attrConfig.types == UIUtils.AttributeType.AbsoluteValue then
        local curValue = oldAtrr
        local mewAttrValue = oldAtrr + addValue
        ui:SetNextValue(mewAttrValue, '{0}')
        ui.Text_NextValue:SetText(0)
        ui.Text_CurValue:SetText(curValue)
    else
        local curValue = math.floor(oldAtrr * 100)
        local mewAttrValue = math.floor(oldAtrr * 100 + addValue * 100)
        ui:SetNextValue(mewAttrValue, '{0}%')
        ui.Text_NextValue:SetText('0%')
        ui.Text_CurValue:SetText(string.format('%d%%', curValue))
    end
    ui.Panel_Item:SetVisibility(UE.ESlateVisibility.Visible)
    ui.Panel_Item:SetRenderOpacity(0)
end

return M